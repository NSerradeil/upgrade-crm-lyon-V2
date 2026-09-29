// tests/prospect-pipeline.test.mjs — la logique pure du pipeline prospect.
// Les fonctions sont extraites d'index.html (mono-fichier, pas de module) — même méthode
// que tests/seq-parcours.test.mjs : on teste le code qui tourne vraiment, pas une copie.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

// Le decalage explicite de combineDT depend du fuseau du poste : on fige Paris pour que les cas ete/hiver soient stables.
process.env.TZ = 'Europe/Paris';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nconst ${nom} ?= ?[^\\n]*;\\n`),
                    new RegExp(`\\nconst ${nom} = \\{[\\s\\S]*?\\n\\};\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['DEFAULT_TASK_TIME', 'combineDT', 'PROSPECT_ETAPES', 'PROSPECT_ETAPES_ACTIVES', 'PROSPECT_ETAPES_SORTIE',
              'PROSPECT_MOTIFS_PERTE', 'prospectEtapeOuDefaut', 'prospectEtapeRequiert',
              'prospectCanSubmit', 'prospectEnRetard', 'prospectTacheLibelle',
              'prospectTacheEcheance', 'prospectReveilPreset', 'prospectPatchEtape', 'prospectTachePayload',
              'prospectSurLeBoard', 'prospectTacheEstProspection', 'etapeDepuisResultatAppel',
              'prospectPatchDepuisAppel', 'prospectRepartitionBoard', 'prospectEtapeFermeTaches',
              'prospectTacheBoucleEtape'];
const src = NOMS.map(extrait).join('\n');
const API = new Function(`${src}\nreturn {${NOMS.join(',')}};`)();
const { PROSPECT_ETAPES, PROSPECT_ETAPES_ACTIVES, PROSPECT_ETAPES_SORTIE,
        prospectEtapeOuDefaut, prospectEtapeRequiert, prospectCanSubmit,
        prospectEnRetard, prospectTacheLibelle, prospectTacheEcheance,
        prospectReveilPreset, prospectPatchEtape, prospectTachePayload,
        prospectSurLeBoard, prospectTacheEstProspection, etapeDepuisResultatAppel,
        prospectPatchDepuisAppel, prospectRepartitionBoard, prospectEtapeFermeTaches,
        prospectTacheBoucleEtape } = API;

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

// C1 : une chaine naive serait lue en UTC par Supabase et reviendrait decalee de 1 ou 2 h.
test('C1 l echeance porte un decalage explicite, ete +02:00 et hiver +01:00', () => {
  assert.equal(prospectTacheEcheance('2026-10-05'), '2026-10-05T09:00:00+02:00');
  assert.equal(prospectTacheEcheance('2027-01-12'), '2027-01-12T09:00:00+01:00');
  assert.equal(prospectTacheEcheance('2026-10-05T14:30'), '2026-10-05T14:30:00+02:00');
  assert.equal(prospectTacheEcheance('2027-01-12T14:30'), '2027-01-12T14:30:00+01:00');
  // le decalage suit la date visee, pas la date du jour : 27 mars 2027 hiver, 29 mars 2027 ete
  assert.equal(prospectTacheEcheance('2027-03-27'), '2027-03-27T09:00:00+01:00');
  assert.equal(prospectTacheEcheance('2027-03-29'), '2027-03-29T09:00:00+02:00');
});

test('C1 une valeur deja datee avec un decalage passe telle quelle, vide reste null', () => {
  assert.equal(prospectTacheEcheance('2026-10-05T09:00:00+02:00'), '2026-10-05T09:00:00+02:00');
  assert.equal(prospectTacheEcheance('2026-10-05T07:00:00Z'), '2026-10-05T07:00:00Z');
  assert.equal(prospectTacheEcheance(''), null);
  assert.equal(prospectTacheEcheance(null), null);
});

test('C1 relecture : 09:00 stocke revient a 09:00 heure de Paris (instant identique)', () => {
  // Supabase renvoie le timestamptz en UTC ; l'app l'affiche en Europe/Paris (extractTime).
  for (const [d, off] of [['2026-10-05', 2], ['2027-01-12', 1]]) {
    const ecrit = prospectTacheEcheance(d);
    const instant = new Date(ecrit);
    assert.equal(instant.toISOString(), `${d}T${String(9 - off).padStart(2, '0')}:00:00.000Z`);
    const relu = instant.toLocaleTimeString('fr-FR', { timeZone: 'Europe/Paris', hour: '2-digit', minute: '2-digit', hour12: false });
    assert.equal(relu, '09:00');
  }
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

test('un prospect avec un besoin actif quitte le board', () => {
  const c = { id: 7, statut: 'Prospect', etape_prospect: 'Qualifié' };
  assert.equal(prospectSurLeBoard(c, []), true);
  assert.equal(prospectSurLeBoard(c, [{ contact_id: 7, statut: 'Opportunité' }]), false);
  assert.equal(prospectSurLeBoard(c, [{ contact_id: 7, statut: 'Besoin Gagné' }]), false);
});

test('un besoin perdu rend le prospect au board', () => {
  const c = { id: 7, statut: 'Prospect', etape_prospect: 'Qualifié' };
  assert.equal(prospectSurLeBoard(c, [{ contact_id: 7, statut: 'Besoin Perdu' }]), true);
});

test('un besoin sur un AUTRE contact ne sort personne', () => {
  const c = { id: 7, statut: 'Prospect' };
  assert.equal(prospectSurLeBoard(c, [{ contact_id: 99, statut: 'Opportunité' }]), true);
});

test('prospectTacheEstProspection : prefixe tw_prospect_ ET contact lie', () => {
  assert.equal(prospectTacheEstProspection({ id: 'tw_prospect_12_1700', contact_id: 12 }), true);
  assert.equal(prospectTacheEstProspection({ id: 'tw_prospect_12_1700', contact_id: null }), false);
  assert.equal(prospectTacheEstProspection({ id: 'tw_prospect_12_1700' }), false);
  assert.equal(prospectTacheEstProspection({ id: 'tw_abc', contact_id: 12 }), false);
  assert.equal(prospectTacheEstProspection({ id: 42, contact_id: 12 }), false);
  assert.equal(prospectTacheEstProspection(null), false);
});

test('le resultat d appel fait avancer l etape', () => {
  assert.equal(etapeDepuisResultatAppel('interested', false, 'À contacter'), 'En discussion');
  assert.equal(etapeDepuisResultatAppel('unreachable', false, 'À contacter'), 'Contacté');
  assert.equal(etapeDepuisResultatAppel('not_interested', false, 'En discussion'), 'Perdu');
  assert.equal(etapeDepuisResultatAppel('not_interested', true, 'En discussion'), 'Ne pas recontacter');
  assert.equal(etapeDepuisResultatAppel('called', false, 'À contacter'), 'Contacté');
});

test('un appel ne fait jamais RECULER une etape deja avancee', () => {
  assert.equal(etapeDepuisResultatAppel('called', false, 'RDV planifié'), 'RDV planifié');
  assert.equal(etapeDepuisResultatAppel('unreachable', false, 'En discussion'), 'En discussion');
  // mais une sortie est toujours possible
  assert.equal(etapeDepuisResultatAppel('not_interested', false, 'RDV planifié'), 'Perdu');
});

test('un statut d appel neutre ne change rien', () => {
  assert.equal(etapeDepuisResultatAppel('none', false, 'Contacté'), 'Contacté');
});

test('RGPD : un appel ne LEVE jamais « Ne pas recontacter »', () => {
  for (const s of ['called', 'interested', 'unreachable', 'none', 'not_interested']) {
    assert.equal(etapeDepuisResultatAppel(s, false, 'Ne pas recontacter'), 'Ne pas recontacter', s);
    assert.equal(etapeDepuisResultatAppel(s, true, 'Ne pas recontacter'), 'Ne pas recontacter', s);
  }
});

// ---- prospectPatchDepuisAppel : ce qui s'ecrit sur le contact en fin de session d'appels ----
test('appel : « pas interesse » sur un Client pose Ne pas recontacter (protection RGPD)', () => {
  const p = prospectPatchDepuisAppel({ statut: 'Client', status: 'not_interested' }, true);
  assert.equal(p.etape_prospect, 'Ne pas recontacter');
  assert.equal(p.prochaine_action_date, null);
  assert.equal(p.prochaine_action_libelle, null);
  assert.ok(p.motif_perte_precision);
  assert.ok(p.updated_at);
});

test('appel : « pas interesse » est pose meme avec avancer=false, et sur un Prospect avance', () => {
  assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'RDV planifié', status: 'not_interested' }, false).etape_prospect, 'Ne pas recontacter');
  assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'RDV planifié', status: 'not_interested' }, true).etape_prospect, 'Ne pas recontacter');
});

test('appel : un contact deja Ne pas recontacter ne bouge plus (null), quel que soit le resultat', () => {
  for (const status of ['not_interested', 'interested', 'called', 'unreachable']) {
    assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'Ne pas recontacter', status }, true), null, status);
  }
});

test('appel : prospect interesse avec relance => etape + prochaine action', () => {
  const p = prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'À contacter', status: 'interested',
    wantRelance: true, relanceDate: '2026-10-15', relanceNote: 'Rappeler pour le RDV' }, true);
  assert.equal(p.etape_prospect, 'En discussion');
  assert.equal(p.prochaine_action_date, prospectTacheEcheance('2026-10-15'));
  assert.equal(p.prochaine_action_libelle, 'Rappeler pour le RDV');
});

test('appel : relance sans note => libelle par defaut de l etape', () => {
  const p = prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'À contacter', status: 'interested',
    wantRelance: true, relanceDate: '2026-10-15' }, true);
  assert.equal(p.prochaine_action_libelle, prospectTacheLibelle('En discussion'));
});

test('appel : avancer=false ne fait avancer aucune etape (seul NPC est pose)', () => {
  assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'À contacter', status: 'interested' }, false), null);
  assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'À contacter', status: 'called' }, false), null);
});

test('appel : un non-prospect interesse ne recoit ni etape ni action', () => {
  for (const statut of ['Client', 'Candidat', 'Freelance']) {
    assert.equal(prospectPatchDepuisAppel({ statut, status: 'interested', wantRelance: true, relanceDate: '2026-10-15' }, true), null, statut);
  }
});

test('appel : un appel ne fait pas reculer, et sans changement ni relance rien n est ecrit', () => {
  assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'RDV planifié', status: 'called' }, true), null);
  const p = prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'RDV planifié', status: 'called',
    wantRelance: true, relanceDate: '2026-10-15' }, true);
  assert.equal(p.etape_prospect, undefined);   // etape inchangee, seule la prochaine action est ecrite
  assert.ok(p.prochaine_action_date);
});

test('appel : une etape de sortie (Perdu) ne recoit pas de prochaine action', () => {
  const p = prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'Perdu', status: 'interested',
    wantRelance: true, relanceDate: '2026-10-15' }, true);
  assert.equal(p, null);
});

// I4 : la cloture d'une tache de prospection ne reboucle sur l'etape que si le contact est encore dans le pipeline.
test('I4 prospectEtapeFermeTaches : Perdu et Ne pas recontacter seulement', () => {
  assert.equal(prospectEtapeFermeTaches('Perdu'), true);
  assert.equal(prospectEtapeFermeTaches('Ne pas recontacter'), true);
  for (const e of ['À contacter', 'Contacté', 'En discussion', 'RDV planifié', 'Qualifié', 'En veille']) {
    assert.equal(prospectEtapeFermeTaches(e), false, e);
  }
});

test('I4 la boucle d etape ne s applique pas a un contact Perdu ou NPC', () => {
  const t = { id: 'tw_prospect_12_1700000000000', contact_id: 12 };
  assert.equal(prospectTacheBoucleEtape(t, { statut: 'Prospect', etape_prospect: 'Contacté' }), true);
  assert.equal(prospectTacheBoucleEtape(t, { statut: 'Prospect', etape_prospect: 'En veille' }), true);
  assert.equal(prospectTacheBoucleEtape(t, { statut: 'Prospect', etape_prospect: 'Perdu' }), false);
  assert.equal(prospectTacheBoucleEtape(t, { statut: 'Prospect', etape_prospect: 'Ne pas recontacter' }), false);
  assert.equal(prospectTacheBoucleEtape(t, { statut: 'Client', etape_prospect: null }), false);
  assert.equal(prospectTacheBoucleEtape(t, null), false);
  // tache ordinaire : jamais de boucle
  assert.equal(prospectTacheBoucleEtape({ id: 'tw_1700000000000', contact_id: 12 }, { statut: 'Prospect' }), false);
  assert.equal(prospectTacheBoucleEtape({ id: 'tw_relance_12_1', contact_id: 12 }, { statut: 'Prospect' }), false);
});

// I5 : spec R4, le reveil remonte en tete de « À contacter » avec un badge, sans changer l'etape.
test('I5 un En veille echu remonte en tete de « À contacter », badge Reveil, etape inchangee', () => {
  const now = '2026-10-10T08:00:00Z';
  const echu = { id: 1, statut: 'Prospect', etape_prospect: 'En veille', prochaine_action_date: '2026-10-01T09:00:00+02:00' };
  const futur = { id: 2, statut: 'Prospect', etape_prospect: 'En veille', prochaine_action_date: '2027-01-01T09:00:00+01:00' };
  const ac1 = { id: 3, statut: 'Prospect', etape_prospect: 'À contacter', prochaine_action_date: '2026-09-01T09:00:00+02:00' };
  const ac2 = { id: 4, statut: 'Prospect', etape_prospect: null };
  const r = prospectRepartitionBoard([ac1, ac2, echu, futur], now);
  assert.deepEqual(r.parEtape['À contacter'].map(c => c.id), [1, 3, 4]);
  assert.deepEqual(r.parEtape['En veille'].map(c => c.id), [2]);
  assert.deepEqual(Object.keys(r.reveil), ['1']);
  assert.equal(echu.etape_prospect, 'En veille');           // rien n'est reecrit
  for (const e of PROSPECT_ETAPES) assert.ok(Array.isArray(r.parEtape[e]), e);
});

test('I5 un En veille sans date ou a date future reste en veille', () => {
  const now = '2026-10-10T08:00:00Z';
  const r = prospectRepartitionBoard([
    { id: 1, statut: 'Prospect', etape_prospect: 'En veille' },
    { id: 2, statut: 'Prospect', etape_prospect: 'Perdu', prochaine_action_date: '2020-01-01T09:00:00Z' }], now);
  assert.deepEqual(r.parEtape['En veille'].map(c => c.id), [1]);
  assert.deepEqual(r.parEtape['Perdu'].map(c => c.id), [2]);
  assert.deepEqual(r.reveil, {});
});

// I3 : jeu de cas commun avec le MCP (copie identique de tests/fixtures/prospect-patch-cas.json
// dans upgrade-crm-mcp-src-next). Si l'une des deux moities diverge, ce test ou son jumeau casse.
test('I3 jeu de cas commun : prospectPatchEtape nettoie comme le serveur MCP', () => {
  const cas = JSON.parse(readFileSync(new URL('./fixtures/prospect-patch-cas.json', import.meta.url), 'utf8')).cas;
  assert.ok(cas.length >= 9);
  for (const c of cas) {
    const p = prospectPatchEtape(c.etape, c.form);
    assert.equal(p.etape_prospect, c.etape);
    for (const [k, v] of Object.entries(c.attendu)) assert.equal(p[k], v, `${c.nom} : ${k}`);
  }
});
