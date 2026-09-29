// tests/prospect-pipeline.test.mjs — la logique pure du pipeline prospect.
// Les fonctions sont extraites d'index.html (mono-fichier, pas de module) — même méthode
// que tests/seq-parcours.test.mjs : on teste le code qui tourne vraiment, pas une copie.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nconst ${nom} = [^\\n]*;\\n`),
                    new RegExp(`\\nconst ${nom} = \\{[\\s\\S]*?\\n\\};\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['PROSPECT_ETAPES', 'PROSPECT_ETAPES_ACTIVES', 'PROSPECT_ETAPES_SORTIE',
              'PROSPECT_MOTIFS_PERTE', 'prospectEtapeOuDefaut', 'prospectEtapeRequiert',
              'prospectCanSubmit', 'prospectEnRetard', 'prospectTacheLibelle',
              'prospectTacheEcheance', 'prospectReveilPreset', 'prospectPatchEtape', 'prospectTachePayload'];
const src = NOMS.map(extrait).join('\n');
const API = new Function(`${src}\nreturn {${NOMS.join(',')}};`)();
const { PROSPECT_ETAPES, PROSPECT_ETAPES_ACTIVES, PROSPECT_ETAPES_SORTIE,
        prospectEtapeOuDefaut, prospectEtapeRequiert, prospectCanSubmit,
        prospectEnRetard, prospectTacheLibelle, prospectTacheEcheance,
        prospectReveilPreset, prospectPatchEtape, prospectTachePayload } = API;

test('les 8 etapes, dans l ordre, avec les accents exacts', () => {
  assert.deepEqual(PROSPECT_ETAPES, ['À contacter', 'Contacté', 'En discussion',
    'RDV planifié', 'Qualifié', 'En veille', 'Perdu', 'Ne pas recontacter']);
  assert.equal(PROSPECT_ETAPES_ACTIVES.length, 5);
  assert.equal(PROSPECT_ETAPES_SORTIE.length, 3);
  // actives + sorties recouvrent exactement l'ensemble, sans doublon
  assert.deepEqual([...PROSPECT_ETAPES_ACTIVES, ...PROSPECT_ETAPES_SORTIE].sort(),
                   [...PROSPECT_ETAPES].sort());
});

test('REVIEW FOCUS 1 — un prospect sans etape est traite comme « A contacter »', () => {
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect' }), 'À contacter');
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect', etape_prospect: null }), 'À contacter');
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect', etape_prospect: '' }), 'À contacter');
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect', etape_prospect: 'Perdu' }), 'Perdu');
});

test('les etapes actives exigent une date, « A contacter » non', () => {
  assert.equal(prospectEtapeRequiert('À contacter').date, false);
  for (const e of ['Contacté', 'En discussion', 'RDV planifié', 'Qualifié']) {
    assert.equal(prospectEtapeRequiert(e).date, true, e);
  }
  assert.equal(prospectEtapeRequiert('En veille').date, true);   // date de reveil
  assert.equal(prospectEtapeRequiert('Perdu').motif, true);
  assert.equal(prospectEtapeRequiert('Perdu').date, false);
  assert.equal(prospectEtapeRequiert('Ne pas recontacter').commentaire, true);
});

test('canSubmit bloque tant que l obligatoire manque', () => {
  assert.equal(prospectCanSubmit('Contacté', {}), false);
  assert.equal(prospectCanSubmit('Contacté', { prochaine_action_date: '2026-10-05' }), true);
  assert.equal(prospectCanSubmit('Perdu', {}), false);
  assert.equal(prospectCanSubmit('Perdu', { motif_perte: 'Pas de besoin' }), true);
  assert.equal(prospectCanSubmit('À contacter', {}), true);
  assert.equal(prospectCanSubmit('Ne pas recontacter', {}), false);
  assert.equal(prospectCanSubmit('Ne pas recontacter', { motif_perte_precision: 'a demande' }), true);
});

test('REVIEW FOCUS 2 — une date de reveil dans le passe compte comme retard', () => {
  const now = new Date('2026-09-29T10:00:00Z');
  assert.equal(prospectEnRetard({ prochaine_action_date: '2025-01-01T09:00:00Z' }, now), true);
  assert.equal(prospectEnRetard({ prochaine_action_date: '2026-09-28T09:00:00Z' }, now), true);
  assert.equal(prospectEnRetard({ prochaine_action_date: '2026-12-01T09:00:00Z' }, now), false);
  assert.equal(prospectEnRetard({ prochaine_action_date: null }, now), false);
  assert.equal(prospectEnRetard({}, now), false);
});

test('l echeance de tache est forcee a 09h00 quand l heure est absente', () => {
  assert.match(prospectTacheEcheance('2026-10-05'), /^2026-10-05T09:00/);
  assert.match(prospectTacheEcheance('2026-10-05T14:30'), /^2026-10-05T14:30/);
});

test('le libelle de tache est pre-rempli depuis l etape visee', () => {
  assert.equal(prospectTacheLibelle('En veille'), 'Réveil prospect');
  assert.equal(prospectTacheLibelle('Contacté'), 'Rappeler');
  assert.equal(prospectTacheLibelle('RDV planifié'), 'RDV prospect');
  assert.ok(prospectTacheLibelle('Qualifié').length > 0);
  // Aucun libelle ne contient de tiret cadratin (marqueur IA, regle maison).
  for (const e of PROSPECT_ETAPES) assert.ok(!/[—–]/.test(prospectTacheLibelle(e)), e);
});

test('les presets de reveil tombent a 3 mois, 6 mois, 1 an', () => {
  assert.equal(prospectReveilPreset('2026-09-29', '3m'), '2026-12-29');
  assert.equal(prospectReveilPreset('2026-09-29', '6m'), '2027-03-29');
  assert.equal(prospectReveilPreset('2026-09-29', '1a'), '2027-09-29');
  // fin de mois : le 31 aout + 6 mois ne doit pas deborder sur mars
  assert.equal(prospectReveilPreset('2026-08-31', '6m'), '2027-02-28');
});

test('le patch porte la date et le libelle pour une etape active', () => {
  const p = prospectPatchEtape('Contacté', { prochaine_action_date: '2026-10-05',
                                             prochaine_action_libelle: 'Rappeler le matin' });
  assert.equal(p.etape_prospect, 'Contacté');
  assert.match(p.prochaine_action_date, /^2026-10-05T09:00/);
  assert.equal(p.prochaine_action_libelle, 'Rappeler le matin');
  assert.equal(p.motif_perte, null);
});

test('le patch d une perte porte le motif et efface la prochaine action', () => {
  const p = prospectPatchEtape('Perdu', { motif_perte: 'Choix concurrent', motif_perte_precision: 'Devoteam' });
  assert.equal(p.etape_prospect, 'Perdu');
  assert.equal(p.motif_perte, 'Choix concurrent');
  assert.equal(p.motif_perte_precision, 'Devoteam');
  assert.equal(p.prochaine_action_date, null);
  assert.equal(p.prochaine_action_libelle, null);
});

test('REVIEW FOCUS 3 — revenir en « A contacter » nettoie motif et action perimes', () => {
  // Formulaire PRE-REMPLI : sans nettoyage, ces valeurs ressortiraient dans le patch.
  const perime = { motif_perte: 'Choix concurrent', motif_perte_precision: 'Devoteam',
                   prochaine_action_date: '2026-10-05', prochaine_action_libelle: 'Rappeler' };
  const p = prospectPatchEtape('À contacter', perime);
  assert.equal(p.etape_prospect, 'À contacter');
  assert.equal(p.motif_perte, null);
  assert.equal(p.motif_perte_precision, null);
  assert.equal(p.prochaine_action_date, null);
  assert.equal(p.prochaine_action_libelle, null);
});

test('« A contacter » avec un formulaire vide reste propre', () => {
  const p = prospectPatchEtape('À contacter', {});
  assert.equal(p.motif_perte, null);
  assert.equal(p.prochaine_action_date, null);
});

test('« Ne pas recontacter » garde la precision, pas de motif, efface la prochaine action', () => {
  const p = prospectPatchEtape('Ne pas recontacter', { motif_perte_precision: 'a demandé le 12/09',
    motif_perte: 'Choix concurrent', prochaine_action_date: '2026-10-05', prochaine_action_libelle: 'Rappeler' });
  assert.equal(p.etape_prospect, 'Ne pas recontacter');
  assert.equal(p.motif_perte_precision, 'a demandé le 12/09');
  assert.equal(p.motif_perte, null);
  assert.equal(p.prochaine_action_date, null);
  assert.equal(p.prochaine_action_libelle, null);
});

test('le patch de mise en veille porte la date de reveil comme prochaine action', () => {
  const p = prospectPatchEtape('En veille', { prochaine_action_date: '2027-03-29' });
  assert.match(p.prochaine_action_date, /^2027-03-29T09:00/);
  assert.equal(p.prochaine_action_libelle, 'Réveil prospect');
  assert.equal(p.motif_perte, null);
});

test('le patch de mise en veille conserve le commentaire', () => {
  const p = prospectPatchEtape('En veille', { prochaine_action_date: '2027-03-29',
    motif_perte_precision: 'Budget gelé jusqu\'à la rentrée' });
  assert.equal(p.motif_perte_precision, 'Budget gelé jusqu\'à la rentrée');
  assert.equal(p.motif_perte, null);
});

test('le patch porte toujours updated_at', () => {
  assert.ok(prospectPatchEtape('À contacter', {}).updated_at);
});

test('pas de tache si la case n est pas cochee', () => {
  assert.equal(prospectTachePayload({id:42}, 'Contacté',
    {prochaine_action_date:'2026-10-05', creer_tache:false}, 'Nicolas Serradeil'), null);
});

test('la tache porte le contact, l echeance a 09h00 et le responsable', () => {
  const t = prospectTachePayload({id:42, prenom:'Léo', nom:'Brignone'}, 'Contacté',
    {prochaine_action_date:'2026-10-05', prochaine_action_libelle:'Rappeler', creer_tache:true},
    'Nicolas Serradeil');
  assert.equal(t.contact_id, 42);
  assert.equal(t.responsable, 'Nicolas Serradeil');
  assert.match(t.due_date, /^2026-10-05T09:00/);
  assert.ok(t.titre.includes('Rappeler'));
  assert.ok(t.titre.includes('Brignone'));
  assert.ok(t.id.startsWith('tw_prospect_42_'));
  assert.equal(t.besoin_id, null);
  assert.equal(t.mission_id, null);
  assert.ok(!/[—–]/.test(t.titre));
});

test('pas de tache pour une etape sans date', () => {
  assert.equal(prospectTachePayload({id:42}, 'Perdu', {motif_perte:'Autre', creer_tache:true},
    'Nicolas Serradeil'), null);
});
