// tests/campagne-sortie.test.mjs : la sortie manuelle d'une personne de campagne de prospection
// (cockpit Jules), logique pure. Fonctions extraites d'index.html, comme tests/prospect-pipeline.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

process.env.TZ = 'Europe/Paris';   // combineDT pose le decalage du poste : on fige Paris

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nconst ${nom} ?= ?[^\\n]*;\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['DEFAULT_TASK_TIME', 'combineDT', 'PROSPECT_ETAPES', 'PROSPECT_ETAPES_ACTIVES', 'PROSPECT_ETAPES_SORTIE',
              'prospectEtapeOuDefaut', 'prospectEtapeRequiert', 'prospectTacheLibelle', 'prospectTacheEcheance',
              'prospectReveilPreset', 'prospectPatchEtape', 'prospectTachePayload',
              'CAMPAGNE_MOTIF_PERTE_PROFIL', 'CAMPAGNE_LIBELLES_SORTIE', 'campagneEstProspection', 'campagneEffetSortie',
              'campagneJourOuvreSuivant', 'campagneSortiePlan'];
const API = new Function(`${NOMS.map(extrait).join('\n')}\nreturn {${NOMS.join(',')}};`)();
const { campagneEstProspection, campagneEffetSortie, campagneJourOuvreSuivant, campagneSortiePlan } = API;

const P = (etape) => ({ id: 7, prenom: 'Jean', nom: 'DUPONT', statut: 'Prospect', responsable: 'Nicolas Serradeil', etape_prospect: etape });
const CTX = { campagne: 'Prospection DSI Lyon', aujourdhui: '2026-09-29', responsable: 'Nicolas Serradeil' };

test('jeu de cas commun avec le MCP : correspondance des sorties manuelles', () => {
  const cas = JSON.parse(readFileSync(new URL('./fixtures/campagne-sortie-cas.json', import.meta.url), 'utf8')).cas;
  assert.ok(cas.length >= 20);
  for (const c of cas) assert.deepEqual(campagneEffetSortie(c.motif, c.contact), c.attendu, c.nom);
});

test('seule une campagne au preset prospection explicite touche au pipeline', () => {
  assert.equal(campagneEstProspection({ kind: 'campagne', config: { preset: 'prospection' } }), true);
  assert.equal(campagneEstProspection({ kind: 'campagne', config: {} }), false);
  assert.equal(campagneEstProspection({ kind: 'campagne', config: { preset: 'recrutement' } }), false);
  assert.equal(campagneEstProspection(null), false);
});

test('jour ouvre suivant : week-end et feries sautes, meme calcul que le MCP', () => {
  assert.equal(campagneJourOuvreSuivant('2026-09-29'), '2026-09-30');
  assert.equal(campagneJourOuvreSuivant('2026-10-02'), '2026-10-05');
  assert.equal(campagneJourOuvreSuivant('2026-11-10'), '2026-11-12');
  assert.equal(campagneJourOuvreSuivant('2026-12-24'), '2026-12-28');
  assert.equal(campagneJourOuvreSuivant('2027-03-26'), '2027-03-30');
});

test('refus : En veille, reveil a 6 mois 09h00 avec decalage, detail avec l etape', () => {
  const p = campagneSortiePlan('refus', P('Contacté'), CTX);
  assert.equal(p.patch.etape_prospect, 'En veille');
  assert.equal(p.patch.prochaine_action_date, '2027-03-29T09:00:00+02:00');
  assert.equal(p.patch.prochaine_action_libelle, 'Réveil prospect');
  assert.equal(p.detail, 'Campagne Prospection DSI Lyon : refus (sortie par Nicolas Serradeil) · étape → En veille');
  assert.equal(p.tache, null); assert.equal(p.fermeTaches, false);
});

test('converti : RDV planifie, Confirmer la date du RDV le jour ouvre suivant, tache tw_prospect_', () => {
  const p = campagneSortiePlan('converti', P('Contacté'), CTX);
  assert.equal(p.patch.etape_prospect, 'RDV planifié');
  assert.equal(p.patch.prochaine_action_date, '2026-09-30T09:00:00+02:00');
  assert.equal(p.patch.prochaine_action_libelle, 'Confirmer la date du RDV');
  assert.match(p.tache.id, /^tw_prospect_7_\d+$/);
  assert.equal(p.tache.titre, 'Confirmer la date du RDV : Jean DUPONT');
  assert.equal(p.tache.due_date, '2026-09-30T09:00:00+02:00');
  assert.equal(p.tache.responsable, 'Nicolas Serradeil');
});

test('ne plus contacter sur un Client : Ne pas recontacter pose, taches fermees, raison par defaut', () => {
  const p = campagneSortiePlan('npc', { id: 8, prenom: 'Marie', nom: 'MARTIN', statut: 'Client', responsable: 'Camille Salinson', etape_prospect: null }, CTX);
  assert.equal(p.patch.etape_prospect, 'Ne pas recontacter');
  assert.equal(p.patch.motif_perte_precision, 'Demande en campagne Prospection DSI Lyon');
  assert.equal(p.fermeTaches, true);
});

test('pas le bon profil : Perdu, motif Pas le bon interlocuteur, taches fermees', () => {
  const p = campagneSortiePlan('profil', P('En discussion'), { ...CTX, precision: 'cherche un DSI, pas un RSSI' });
  assert.equal(p.patch.etape_prospect, 'Perdu');
  assert.equal(p.patch.motif_perte, 'Pas le bon interlocuteur');
  assert.equal(p.patch.motif_perte_precision, 'cherche un DSI, pas un RSSI');
  assert.equal(p.fermeTaches, true);
});

test('autre : historique seul ; doublon : rien a ecrire', () => {
  const autre = campagneSortiePlan('autre', P('Contacté'), CTX);
  assert.equal(autre.patch, null);
  assert.equal(autre.detail, 'Campagne Prospection DSI Lyon : sortie de campagne (sortie par Nicolas Serradeil)');
  assert.equal(campagneSortiePlan('doublon', P('Contacté'), CTX).detail, null);
});

test('aucun tiret cadratin ni demi-cadratin dans le code ajoute', () => {
  const src = ['CAMPAGNE_LIBELLES_SORTIE', 'campagneEffetSortie', 'campagneJourOuvreSuivant', 'campagneSortiePlan'].map(extrait).join('\n');
  assert.doesNotMatch(src, /[–—]/);
});
