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
              'prospectTacheBoucleEtape', 'PROSPECT_FILTRE_ACTIFS', 'prospectSectionsListe',
              'prospectDerniereActionMap', 'prospectDerniereActionTexte', 'prospectSectionsVisibles'];
const src = NOMS.map(extrait).join('\n');
const API = new Function(`${src}\nreturn {${NOMS.join(',')}};`)();
const { PROSPECT_ETAPES, PROSPECT_ETAPES_ACTIVES, PROSPECT_ETAPES_SORTIE,
        prospectEtapeOuDefaut, prospectEtapeRequiert, prospectCanSubmit,
        prospectEnRetard, prospectTacheLibelle, prospectTacheEcheance,
        prospectReveilPreset, prospectPatchEtape, prospectTachePayload,
        prospectSurLeBoard, prospectTacheEstProspection, etapeDepuisResultatAppel,
        prospectPatchDepuisAppel, prospectRepartitionBoard, prospectEtapeFermeTaches,
        prospectTacheBoucleEtape, PROSPECT_FILTRE_ACTIFS, prospectSectionsListe,
        prospectDerniereActionMap, prospectDerniereActionTexte, prospectSectionsVisibles } = API;

test('les 7 etapes, dans l ordre, avec les accents exacts', () => {
  assert.deepEqual(PROSPECT_ETAPES, ['À contacter', 'Contacté', 'En discussion',
    'RDV planifié', 'RDV effectué', 'À relancer', 'Ne pas recontacter']);
  assert.equal(PROSPECT_ETAPES_ACTIVES.length, 5);
  assert.equal(PROSPECT_ETAPES_SORTIE.length, 2);
  // actives + sorties recouvrent exactement l'ensemble, sans doublon
  assert.deepEqual([...PROSPECT_ETAPES_ACTIVES, ...PROSPECT_ETAPES_SORTIE].sort(),
                   [...PROSPECT_ETAPES].sort());
});

test('REVIEW FOCUS 1 — un prospect sans etape est traite comme « A contacter »', () => {
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect' }), 'À contacter');
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect', etape_prospect: null }), 'À contacter');
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect', etape_prospect: '' }), 'À contacter');
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect', etape_prospect: 'Perdu' }), 'À contacter');   // etape disparue : retombe sur À contacter
});

test('les etapes actives exigent une date, « A contacter » non', () => {
  assert.equal(prospectEtapeRequiert('À contacter').date, false);
  for (const e of ['Contacté', 'En discussion', 'RDV planifié', 'RDV effectué']) {
    assert.equal(prospectEtapeRequiert(e).date, true, e);
  }
  assert.equal(prospectEtapeRequiert('À relancer').date, true);   // date de reveil
  assert.equal(prospectEtapeRequiert('Ne pas recontacter').motif, false);   // motif facultatif
  assert.equal(prospectEtapeRequiert('Ne pas recontacter').date, false);
  assert.equal(prospectEtapeRequiert('Ne pas recontacter').commentaire, true);
});

test('canSubmit bloque tant que l obligatoire manque', () => {
  assert.equal(prospectCanSubmit('Contacté', {}), false);
  assert.equal(prospectCanSubmit('Contacté', { prochaine_action_date: '2026-10-05' }), true);
  assert.equal(prospectCanSubmit('Ne pas recontacter', { motif_perte: 'Pas de besoin' }), false);   // la precision reste exigee
  assert.equal(prospectCanSubmit('Ne pas recontacter', { motif_perte_precision: 'a demande', motif_perte: 'Pas de besoin' }), true);
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
  assert.equal(prospectTacheLibelle('À relancer'), 'Réveil prospect');
  assert.equal(prospectTacheLibelle('Contacté'), 'Rappeler');
  assert.equal(prospectTacheLibelle('RDV planifié'), 'RDV prospect');
  assert.ok(prospectTacheLibelle('RDV effectué').length > 0);
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

test('le patch de Ne pas recontacter porte le motif facultatif et efface la prochaine action', () => {
  const p = prospectPatchEtape('Ne pas recontacter', { motif_perte: 'Choix concurrent', motif_perte_precision: 'Devoteam' });
  assert.equal(p.etape_prospect, 'Ne pas recontacter');
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

test('« Ne pas recontacter » garde la precision et le motif, efface la prochaine action', () => {
  const p = prospectPatchEtape('Ne pas recontacter', { motif_perte_precision: 'a demandé le 12/09',
    motif_perte: 'Choix concurrent', prochaine_action_date: '2026-10-05', prochaine_action_libelle: 'Rappeler' });
  assert.equal(p.etape_prospect, 'Ne pas recontacter');
  assert.equal(p.motif_perte_precision, 'a demandé le 12/09');
  assert.equal(p.motif_perte, 'Choix concurrent');
  assert.equal(p.prochaine_action_date, null);
  assert.equal(p.prochaine_action_libelle, null);
});

test('le patch de mise en veille porte la date de reveil comme prochaine action', () => {
  const p = prospectPatchEtape('À relancer', { prochaine_action_date: '2027-03-29' });
  assert.match(p.prochaine_action_date, /^2027-03-29T09:00/);
  assert.equal(p.prochaine_action_libelle, 'Réveil prospect');
  assert.equal(p.motif_perte, null);
});

test('le patch de mise en veille conserve le commentaire', () => {
  const p = prospectPatchEtape('À relancer', { prochaine_action_date: '2027-03-29',
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
  assert.equal(prospectTachePayload({id:42}, 'Ne pas recontacter', {motif_perte:'Autre', creer_tache:true},
    'Nicolas Serradeil'), null);
});

test('un prospect avec un besoin actif quitte le board', () => {
  const c = { id: 7, statut: 'Prospect', etape_prospect: 'RDV effectué' };
  assert.equal(prospectSurLeBoard(c, []), true);
  assert.equal(prospectSurLeBoard(c, [{ contact_id: 7, statut: 'Opportunité' }]), false);
  assert.equal(prospectSurLeBoard(c, [{ contact_id: 7, statut: 'Besoin Gagné' }]), false);
});

test('un besoin perdu rend le prospect au board', () => {
  const c = { id: 7, statut: 'Prospect', etape_prospect: 'RDV effectué' };
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
  assert.equal(etapeDepuisResultatAppel('not_interested', false, 'En discussion'), 'À relancer');
  assert.equal(etapeDepuisResultatAppel('not_interested', true, 'En discussion'), 'Ne pas recontacter');
  assert.equal(etapeDepuisResultatAppel('called', false, 'À contacter'), 'Contacté');
});

test('un appel ne fait jamais RECULER une etape deja avancee', () => {
  assert.equal(etapeDepuisResultatAppel('called', false, 'RDV planifié'), 'RDV planifié');
  assert.equal(etapeDepuisResultatAppel('unreachable', false, 'En discussion'), 'En discussion');
  // mais une sortie est toujours possible
  assert.equal(etapeDepuisResultatAppel('not_interested', false, 'RDV planifié'), 'À relancer');
  assert.equal(etapeDepuisResultatAppel('not_interested', true, 'RDV planifié'), 'Ne pas recontacter');
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
const AUJ = '2026-09-29';   // date fournie a la fonction pure (evite getToday dans le test)

test('appel : « pas interesse » sans case sur un Prospect => À relancer a +6 mois 09:00 avec decalage explicite', () => {
  const p = prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'En discussion', status: 'not_interested' }, true, AUJ);
  assert.equal(p.etape_prospect, 'À relancer');
  assert.equal(p.prochaine_action_date, '2027-03-29T09:00:00+02:00');   // 29 mars 2027 = heure d'ete
  assert.match(p.prochaine_action_date, /T09:00:00[+-]\d{2}:\d{2}$/);
  assert.equal(p.prochaine_action_libelle, 'Relance après refus');
  assert.equal(p.motif_perte, null);
  assert.ok(p.updated_at);
  // hiver : 30 sept + 6 mois = 30 mars, heure d'ete ; 31 aout + 6 mois = 28 fev, heure d'hiver
  assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', status: 'not_interested' }, false, '2026-08-31').prochaine_action_date, '2027-02-28T09:00:00+01:00');
});

test('appel : « pas interesse » sans case : la note de relance du rang donne le libelle', () => {
  const p = prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'Contacté', status: 'not_interested',
    wantRelance: true, relanceDate: '2026-10-15', relanceNote: 'Revoir apres leur levee' }, true, AUJ);
  assert.equal(p.prochaine_action_libelle, 'Revoir apres leur levee');
  assert.equal(p.prochaine_action_date, '2027-03-29T09:00:00+02:00');   // la date de reveil reste +6 mois
});

test('appel : « pas interesse » sans case sur un non-Prospect => aucun changement d etape', () => {
  for (const statut of ['Client', 'Candidat', 'Freelance']) {
    assert.equal(prospectPatchDepuisAppel({ statut, status: 'not_interested' }, true, AUJ), null, statut);
    assert.equal(prospectPatchDepuisAppel({ statut, status: 'not_interested', nePlusAppeler: false }, false, AUJ), null, statut);
  }
});

test('appel : « pas interesse » + case « ne plus appeler » => Ne pas recontacter, Prospect comme Client', () => {
  for (const statut of ['Prospect', 'Client', 'Candidat']) {
    const p = prospectPatchDepuisAppel({ statut, etape_prospect: 'En discussion', status: 'not_interested', nePlusAppeler: true }, true, AUJ);
    assert.equal(p.etape_prospect, 'Ne pas recontacter', statut);
    assert.equal(p.prochaine_action_date, null);
    assert.equal(p.prochaine_action_libelle, null);
    assert.ok(p.motif_perte_precision);
    assert.ok(p.updated_at);
  }
  // meme avec avancer=false (correction de session)
  assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'RDV planifié', status: 'not_interested', nePlusAppeler: true }, false, AUJ).etape_prospect, 'Ne pas recontacter');
});

test('appel : la case n a d effet que sur « pas interesse »', () => {
  assert.equal(prospectPatchDepuisAppel({ statut: 'Client', status: 'interested', nePlusAppeler: true }, true, AUJ), null);
  assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'À contacter', status: 'called', nePlusAppeler: true }, true, AUJ).etape_prospect, 'Contacté');
});

test('appel : deja À relancer + pas interesse => date de reveil repoussee a +6 mois', () => {
  const v = prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'À relancer', status: 'not_interested' }, true, AUJ);
  assert.equal(v.etape_prospect, 'À relancer');
  assert.equal(v.prochaine_action_date, '2027-03-29T09:00:00+02:00');
  // À relancer + case cochee : la protection RGPD prime
  assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'À relancer', status: 'not_interested', nePlusAppeler: true }, true, AUJ).etape_prospect, 'Ne pas recontacter');
  // Ne pas recontacter est terminal
  assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'Ne pas recontacter', status: 'not_interested' }, true, AUJ), null);
  assert.equal(etapeDepuisResultatAppel('not_interested', false, 'À relancer'), 'À relancer');
});

test('appel : la note de relance ne devient le libelle de reveil que si wantRelance', () => {
  const p = prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'Contacté', status: 'not_interested',
    wantRelance: false, relanceNote: 'note perimee' }, true, AUJ);
  assert.equal(p.prochaine_action_libelle, 'Relance après refus');
});

test('correction de session : etape touchee seulement si le resultat a change dans l edition', () => {
  const base = { statut: 'Prospect', status: 'not_interested', statutInitial: 'not_interested' };
  assert.equal(prospectPatchDepuisAppel({ ...base, etape_prospect: 'RDV planifié' }, false, AUJ, true), null);
  assert.equal(prospectPatchDepuisAppel({ ...base, etape_prospect: 'À relancer', prochaine_action_date: '2026-12-01T09:00:00+01:00' }, false, AUJ, true), null);
  assert.equal(prospectPatchDepuisAppel({ ...base, etape_prospect: 'En discussion', nePlusAppeler: true }, false, AUJ, true), null);
  // resultat change vers not_interested
  const ch = { statut: 'Prospect', etape_prospect: 'Contacté', status: 'not_interested', statutInitial: 'called' };
  const v = prospectPatchDepuisAppel(ch, false, AUJ, true);
  assert.equal(v.etape_prospect, 'À relancer');
  assert.equal(v.prochaine_action_date, '2027-03-29T09:00:00+02:00');
  assert.equal(prospectPatchDepuisAppel({ ...ch, nePlusAppeler: true }, false, AUJ, true).etape_prospect, 'Ne pas recontacter');
  // hors correction (fin de session), statutInitial est ignore
  assert.equal(prospectPatchDepuisAppel(base, true, AUJ).etape_prospect, 'À relancer');
});

test('relance de session : une date seule devient 09:00 avec decalage explicite (jamais naive)', () => {
  assert.equal(prospectTacheEcheance('2026-10-15'), '2026-10-15T09:00:00+02:00');
  assert.equal(prospectTacheEcheance('2026-12-15'), '2026-12-15T09:00:00+01:00');
});

test('appel : un contact deja Ne pas recontacter ne bouge plus (null), quel que soit le resultat', () => {
  for (const status of ['not_interested', 'interested', 'called', 'unreachable']) {
    assert.equal(prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'Ne pas recontacter', status, nePlusAppeler: status === 'not_interested' }, true, AUJ), null, status);
    assert.equal(prospectPatchDepuisAppel({ statut: 'Client', etape_prospect: 'Ne pas recontacter', status }, true, AUJ), null, status);
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

test('appel : avancer=false ne fait avancer aucune etape (seules les sorties « pas interesse » sont posees)', () => {
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

test('appel : une etape de sortie (Ne pas recontacter) ne recoit pas de prochaine action', () => {
  const p = prospectPatchDepuisAppel({ statut: 'Prospect', etape_prospect: 'Ne pas recontacter', status: 'interested',
    wantRelance: true, relanceDate: '2026-10-15' }, true);
  assert.equal(p, null);
});

// I4 : la cloture d'une tache de prospection ne reboucle sur l'etape que si le contact est encore dans le pipeline.
test('I4 prospectEtapeFermeTaches : Ne pas recontacter seulement', () => {
  assert.equal(prospectEtapeFermeTaches('Ne pas recontacter'), true);
  for (const e of ['À contacter', 'Contacté', 'En discussion', 'RDV planifié', 'RDV effectué', 'À relancer']) {
    assert.equal(prospectEtapeFermeTaches(e), false, e);
  }
});

test('I4 la boucle d etape ne s applique pas a un contact NPC', () => {
  const t = { id: 'tw_prospect_12_1700000000000', contact_id: 12 };
  assert.equal(prospectTacheBoucleEtape(t, { statut: 'Prospect', etape_prospect: 'Contacté' }), true);
  assert.equal(prospectTacheBoucleEtape(t, { statut: 'Prospect', etape_prospect: 'À relancer' }), true);
  assert.equal(prospectTacheBoucleEtape(t, { statut: 'Prospect', etape_prospect: 'Ne pas recontacter' }), false);
  assert.equal(prospectTacheBoucleEtape(t, { statut: 'Client', etape_prospect: null }), false);
  assert.equal(prospectTacheBoucleEtape(t, null), false);
  // tache ordinaire : jamais de boucle
  assert.equal(prospectTacheBoucleEtape({ id: 'tw_1700000000000', contact_id: 12 }, { statut: 'Prospect' }), false);
  assert.equal(prospectTacheBoucleEtape({ id: 'tw_relance_12_1', contact_id: 12 }, { statut: 'Prospect' }), false);
});

// I5 : spec R4, le reveil remonte en tete de « À contacter » avec un badge, sans changer l'etape.
test('I5 un À relancer echu remonte en tete de « À contacter », badge Reveil, etape inchangee', () => {
  const now = '2026-10-10T08:00:00Z';
  const echu = { id: 1, statut: 'Prospect', etape_prospect: 'À relancer', prochaine_action_date: '2026-10-01T09:00:00+02:00' };
  const futur = { id: 2, statut: 'Prospect', etape_prospect: 'À relancer', prochaine_action_date: '2027-01-01T09:00:00+01:00' };
  const ac1 = { id: 3, statut: 'Prospect', etape_prospect: 'À contacter', prochaine_action_date: '2026-09-01T09:00:00+02:00' };
  const ac2 = { id: 4, statut: 'Prospect', etape_prospect: null };
  const r = prospectRepartitionBoard([ac1, ac2, echu, futur], now);
  assert.deepEqual(r.parEtape['À contacter'].map(c => c.id), [1, 3, 4]);
  assert.deepEqual(r.parEtape['À relancer'].map(c => c.id), [2]);
  assert.deepEqual(Object.keys(r.reveil), ['1']);
  assert.equal(echu.etape_prospect, 'À relancer');           // rien n'est reecrit
  for (const e of PROSPECT_ETAPES) assert.ok(Array.isArray(r.parEtape[e]), e);
});

test('I5 un À relancer sans date ou a date future reste en veille', () => {
  const now = '2026-10-10T08:00:00Z';
  const r = prospectRepartitionBoard([
    { id: 1, statut: 'Prospect', etape_prospect: 'À relancer' },
    { id: 2, statut: 'Prospect', etape_prospect: 'Ne pas recontacter', prochaine_action_date: '2020-01-01T09:00:00Z' }], now);
  assert.deepEqual(r.parEtape['À relancer'].map(c => c.id), [1]);
  assert.deepEqual(r.parEtape['Ne pas recontacter'].map(c => c.id), [2]);
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

// ── Vue liste en cartes groupees par etape ──
const NOW_L = '2026-09-29T10:00:00+02:00';
const cl = (id, etape, date) => ({ id, etape_prospect: etape, prochaine_action_date: date || null });
const etapesDe = r => r.map(s => s.etape);

test('liste: ACTIFS exclut NPC et À relancer pas echu, inclut À relancer echu', () => {
  const cs = [cl(2,'Ne pas recontacter'), cl(3,'À relancer','2026-12-01'),
              cl(4,'À relancer','2026-09-01'), cl(5,'Contacté','2026-10-01'), cl(6,'En discussion')];
  const r = prospectSectionsListe(cs, PROSPECT_FILTRE_ACTIFS, NOW_L);
  const ids = r.flatMap(s => s.contacts.map(c => c.id)).sort();
  assert.deepEqual(ids, [4,5,6]);
  assert.ok(!etapesDe(r).some(e => ['Ne pas recontacter','À relancer'].includes(e)));
});

test('liste: l À relancer echu rejoint la section A contacter, en tete, avec reveil', () => {
  const cs = [cl(1,'À contacter','2026-09-20'), cl(2,'À relancer','2026-09-25')];
  const r = prospectSectionsListe(cs, PROSPECT_FILTRE_ACTIFS, NOW_L);
  assert.equal(r.length, 1);
  assert.deepEqual(r[0].contacts.map(c => c.id), [2,1]);
  assert.equal(r[0].reveil[2], true);
  assert.equal(r[0].reveil[1], undefined);
});

test('liste: TOUS garde toutes les etapes, dans l ordre PROSPECT_ETAPES, sections vides masquees', () => {
  const cs = [cl(2,'RDV effectué','2026-10-02'), cl(3,'À contacter'), cl(4,'Ne pas recontacter'), cl(5,'À relancer','2026-12-01')];
  const r = prospectSectionsListe(cs, '', NOW_L);
  assert.deepEqual(etapesDe(r), ['À contacter','RDV effectué','À relancer','Ne pas recontacter']);
});

test('liste: dans une section, date croissante, sans date en dernier', () => {
  const cs = [cl(1,'Contacté'), cl(2,'Contacté','2026-11-05'), cl(3,'Contacté','2026-10-01')];
  const r = prospectSectionsListe(cs, PROSPECT_FILTRE_ACTIFS, NOW_L);
  assert.deepEqual(r[0].contacts.map(c => c.id), [3,2,1]);
});

test('liste: filtre sur une etape ne montre que celle-la', () => {
  const cs = [cl(1,'Contacté'), cl(2,'RDV effectué'), cl(3,'À relancer','2026-12-01')];
  assert.deepEqual(etapesDe(prospectSectionsListe(cs, 'RDV effectué', NOW_L)), ['RDV effectué']);
  assert.deepEqual(etapesDe(prospectSectionsListe(cs, 'À relancer', NOW_L)), ['À relancer']);
  assert.deepEqual(prospectSectionsListe([], PROSPECT_FILTRE_ACTIFS, NOW_L), []);
});

test('liste: derniere action = la plus recente par date, egalite = id le plus eleve', () => {
  const h = [
    { id: 1, id_prospect: 7, date: '2026-09-01', type_action: 'Appel' },
    { id: 2, id_prospect: 7, date: '2026-09-20', type_action: 'Mail' },
    { id: 9, id_prospect: 7, date: '2026-09-20', type_action: 'RDV' },
    { id: 3, id_prospect: 8, date: '2026-08-01', type_action: 'Note' },
    { id: 4, id_prospect: null, date: '2026-09-28', type_action: 'Orpheline' }
  ];
  const m = prospectDerniereActionMap(h);
  assert.equal(m[7].type_action, 'RDV');
  assert.equal(m[8].type_action, 'Note');
  assert.equal(m[null], undefined);
  assert.equal(prospectDerniereActionMap([{ id: 10, id_prospect: 7, date: '2026-09-20', type_action: 'X' }, { id: 2, id_prospect: 7, date: '2026-09-20', type_action: 'Y' }])[7].type_action, 'X');
});

test('liste: contact sans historique, et texte de derniere action', () => {
  const m = prospectDerniereActionMap([]);
  assert.equal(m[42], undefined);
  assert.equal(prospectDerniereActionTexte(undefined), 'Aucune action');
  assert.equal(prospectDerniereActionTexte({ type_action: 'Appel', date: '2026-09-20', details: 'Ligne 1\n  ligne 2' }), 'Appel · 20/09 · Ligne 1 ligne 2');
  assert.equal(prospectDerniereActionTexte({ type_action: 'Mail', date: '2026-09-20' }), 'Mail · 20/09');
  assert.ok(!/[—–]/.test(prospectDerniereActionTexte(undefined)));
});

test('liste: pagination = max N cartes au total, dans l ordre des sections, comptes sur la liste complete', () => {
  const cs = [cl(1,'À contacter'), cl(2,'À contacter'), cl(3,'À contacter'), cl(4,'Contacté'), cl(5,'Contacté')];
  const secs = prospectSectionsListe(cs, PROSPECT_FILTRE_ACTIFS, NOW_L);
  const v = prospectSectionsVisibles(secs, 4);
  assert.deepEqual(v.map(s => [s.etape, s.contacts.length, s.visibles.length]), [['À contacter',3,3],['Contacté',2,1]]);
  const v2 = prospectSectionsVisibles(secs, 2);
  assert.deepEqual(v2.map(s => [s.etape, s.contacts.length, s.visibles.length]), [['À contacter',3,2]]);
  assert.equal(prospectSectionsVisibles(secs, 200).reduce((n, s) => n + s.visibles.length, 0), 5);
});
