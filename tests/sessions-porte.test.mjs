// tests/sessions-porte.test.mjs — l'écran « Prosp. » écrit par la porte enregistrer_resultat_appel (db/65).
// Fonctions extraites d'index.html (même méthode que prospect-pipeline.test.mjs) : on teste le code qui tourne.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

process.env.TZ = 'Europe/Paris';
const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`), new RegExp(`\\nconst ${nom} ?= ?[^\\n]*;\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['DEFAULT_TASK_TIME', 'combineDT', 'prospectTacheEcheance', 'prospectPorteParams', 'prospectCoordsPatch',
              'prospectSessionDroits', 'prospectFileEnvois'];
const API = new Function(`function normalizeLinkedinUrl(u){return 'https://'+String(u).replace(/^https?:\\/\\//,'');}\n${NOMS.map(extrait).join('\n')}\nreturn {${NOMS.join(',')}};`)();
const { prospectPorteParams, prospectCoordsPatch, prospectSessionDroits, prospectFileEnvois } = API;
const S = '11111111-1111-1111-1111-111111111111';

test('porte : un résultat simple', () => {
  assert.deepEqual(prospectPorteParams(S, { id: '42', status: 'unreachable', notes: '', wantRelance: false, relanceDate: '', relanceNote: '' }), {
    p_session: S, p_contact: 42, p_resultat: 'unreachable', p_precision: null, p_note: null, p_suite: null,
    p_date_suite: null, p_ne_plus_appeler: false, p_canal: null, p_note_suite: null });
});

test('porte : relance cochée = suite rappel, échéance 09:00 Paris avec décalage', () => {
  const p = prospectPorteParams(S, { id: 7, status: 'called', notes: 'vu', wantRelance: true, relanceDate: '2026-12-02', relanceNote: 'mail' });
  assert.equal(p.p_suite, 'rappel');
  assert.equal(p.p_date_suite, '2026-12-02T09:00:00+01:00');
  assert.equal(p.p_note, 'vu');
  assert.equal(p.p_note_suite, 'mail');
  const ete = prospectPorteParams(S, { id: 7, status: 'called', wantRelance: true, relanceDate: '2026-07-02' });
  assert.equal(ete.p_date_suite, '2026-07-02T09:00:00+02:00');
});

test('porte : relance cochée sans date = suite sans échéance ; date sans case = rien', () => {
  const a = prospectPorteParams(S, { id: 7, status: 'called', wantRelance: true, relanceDate: '' });
  assert.equal(a.p_suite, 'rappel'); assert.equal(a.p_date_suite, null);
  const b = prospectPorteParams(S, { id: 7, status: 'called', wantRelance: false, relanceDate: '2026-12-02', relanceNote: 'x' });
  assert.equal(b.p_suite, null); assert.equal(b.p_date_suite, null);
});

test('porte : « Ne plus appeler » ne part qu avec Pas intéressé (la porte refuse sinon)', () => {
  assert.equal(prospectPorteParams(S, { id: 1, status: 'not_interested', nePlusAppeler: true }).p_ne_plus_appeler, true);
  for (const st of ['called', 'interested', 'unreachable', 'none'])
    assert.equal(prospectPorteParams(S, { id: 1, status: st, nePlusAppeler: true }).p_ne_plus_appeler, false, st);
});

test('porte : un 2e clic sur le même bouton = none, sans note ni suite', () => {
  const p = prospectPorteParams(S, { id: 1, status: 'none', notes: 'texte', wantRelance: true, relanceDate: '2026-12-02', relanceNote: 'n' });
  assert.equal(p.p_resultat, 'none');
  assert.equal(p.p_note, null); assert.equal(p.p_suite, null); assert.equal(p.p_date_suite, null); assert.equal(p.p_note_suite, null);
});

test('coordonnées : seules les saisies non vides et différentes', () => {
  const sc = { telephone: '01', editTel: '02', email: 'a@b', editEmail: 'a@b', linkedin: '', editLinkedin: 'linkedin.com/in/x',
               ville: 'Lyon', editVille: '', role: 'PO', editRole: 'PM', ats: '', editAts: '' };
  assert.deepEqual(prospectCoordsPatch(sc), { telephone: '02', linkedin: 'https://linkedin.com/in/x', role: 'PM' });
});

test('droits : session CRM à moi, en cours, tenue ou non par la porte : reprendre / modifier / supprimer', () => {
  for (const porte of [false, true]) {
    const d = prospectSessionDroits({ statut: 'active', origine: 'crm', responsable: 'Anne' }, porte, 'Anne', false);
    assert.equal(d.reprendre, true); assert.equal(d.modifier, true); assert.equal(d.supprimerEnCours, true);
  }
});

test('droits : session Jules : rien d autre que la lecture, même pour son responsable ou un admin', () => {
  for (const statut of ['active', 'done']) for (const [nom, admin] of [['Anne', false], ['Nico', true]]) {
    const d = prospectSessionDroits({ statut, origine: 'jules', responsable: 'Anne' }, false, nom, admin);
    assert.equal(d.jules, true); assert.equal(d.porte, true);
    for (const k of ['reprendre', 'modifier', 'supprimerEnCours', 'resultatsAncien', 'resultatsPorte', 'supprimerTerminee']) assert.equal(d[k], false, statut + k);
  }
});

test('droits : session d un collègue en cours : jamais reprise (la porte refuse) ; admin garde modifier/supprimer si aucune ligne porte', () => {
  const s = { statut: 'active', origine: 'crm', responsable: 'Camille' };
  const a = prospectSessionDroits(s, false, 'Nico', true);
  assert.equal(a.reprendre, false); assert.equal(a.modifier, true); assert.equal(a.supprimerEnCours, true);
  const b = prospectSessionDroits(s, true, 'Nico', true);
  assert.equal(b.reprendre, false); assert.equal(b.modifier, false); assert.equal(b.supprimerEnCours, false);
  const c = prospectSessionDroits(s, false, 'Anne', false);
  assert.equal(c.reprendre, false);
});

test('droits : session terminée : ancien écran de correction seulement sans ligne porte ; sinon correction par la porte, responsable seul', () => {
  const s = { statut: 'done', origine: 'crm', responsable: 'Anne' };
  assert.equal(prospectSessionDroits(s, false, 'Anne', false).resultatsAncien, true);
  assert.equal(prospectSessionDroits(s, false, 'Nico', true).resultatsAncien, true);
  const p = prospectSessionDroits(s, true, 'Anne', false);
  assert.equal(p.resultatsAncien, false); assert.equal(p.resultatsPorte, true);
  const q = prospectSessionDroits(s, true, 'Nico', true);
  assert.equal(q.resultatsAncien, false); assert.equal(q.resultatsPorte, false); assert.equal(q.supprimerTerminee, true);
  assert.equal(prospectSessionDroits(s, false, null, false).resultatsAncien, false);
});

// File d'envois : minuteur manuel pour rejouer les délais.
function minuteurManuel() {
  let n = 0; const t = new Map();
  return { poser: (f, d) => { t.set(++n, f); return n; }, retirer: (h) => t.delete(h), declencher: () => { const fs = [...t.values()]; t.clear(); fs.forEach(f => f()); }, nb: () => t.size };
}
const pause = (ms) => new Promise(r => setTimeout(r, ms));

test('file : un seul envoi en vol par contact, le dernier état gagne, aucun envoi perdu', async () => {
  const etat = { v: 0 }; const recus = []; let enVol = 0, maxVol = 0;
  const f = prospectFileEnvois(async (id) => { enVol++; maxVol = Math.max(maxVol, enVol); const v = etat.v; await pause(5); recus.push([id, v]); enVol--; return true; }, () => {});
  etat.v = 1; f.planifier(9, 0);
  etat.v = 2; f.planifier(9, 0);
  etat.v = 3; f.planifier(9, 0);
  assert.equal(await f.tout(), true);
  assert.equal(maxVol, 1);
  assert.equal(recus.at(-1)[1], 3);
  assert.equal(f.enAttente(), false);
});

test('file : un texte attend son délai, un résultat l annule et part tout de suite (un seul envoi)', async () => {
  const m = minuteurManuel(); let n = 0;
  const f = prospectFileEnvois(async () => { n++; return true; }, () => {}, m);
  f.planifier(1, 1200);
  assert.equal(m.nb(), 1); assert.equal(n, 0);
  f.planifier(1, 0);
  assert.equal(m.nb(), 0);
  await f.tout();
  assert.equal(n, 1);
});

test('file : une erreur garde le contact à envoyer, tout() rend false puis true au retour du réseau', async () => {
  let reseau = false; const signaux = [];
  const f = prospectFileEnvois(async () => { if (!reseau) throw new Error('hors ligne'); return true; }, (id, v) => signaux.push(v));
  f.planifier(5, 0);
  assert.equal(await f.tout(), false);
  assert.equal(f.enAttente(), true);
  assert.equal(signaux.at(-1), 'erreur');
  reseau = true;
  assert.equal(await f.tout(), true);
  assert.equal(signaux.at(-1), 'ok');
});

test('file : envoyer qui rend false = erreur', async () => {
  const f = prospectFileEnvois(async () => false, () => {});
  f.planifier(5, 0);
  assert.equal(await f.tout(), false);
  assert.equal(f.enAttente(), true);
});

test('file : tout() attend un envoi déjà en vol', async () => {
  let fini = false;
  const f = prospectFileEnvois(async () => { await pause(20); fini = true; return true; }, () => {});
  f.planifier(3, 0);
  await pause(1);
  assert.equal(await f.tout(), true);
  assert.equal(fini, true);
});

test('écran : plus aucune écriture directe d historique, de tâche ni de ligne de session dans Terminer', () => {
  const debut = html.indexOf('var handleTerminer = async function(){');
  const fin = html.indexOf('var handleFermerCorrection');
  const corps = html.slice(debut, fin);
  assert.ok(debut > 0 && fin > debut);
  for (const interdit of ["from('historique_actions')", "from('taches')", "from('session_prospection_contacts')", "from('contacts')", 'prospectPatchDepuisAppel'])
    assert.ok(!corps.includes(interdit), interdit);
  assert.ok(corps.includes("sb.rpc('terminer_session_appel'"));
});

test('file : abandonner() (suppression) n envoie rien de ce qui attend, mais attend l envoi en vol', async () => {
  const m = minuteurManuel(); const envois = [];
  const f = prospectFileEnvois(async (id) => { envois.push(id); await pause(10); return true; }, () => {}, m);
  f.planifier(1, 0);          // part
  await pause(1);             // … et il est en vol
  f.planifier(2, 1200);       // en attente (« Ne plus appeler » coché à l'instant)
  await f.abandonner();
  m.declencher();
  await pause(20);
  assert.deepEqual(envois, [1]);
  assert.equal(f.enAttente(), false);
});

test('écran : retirer une personne relit toujours les lignes porte (jamais un état chargé plus tôt)', () => {
  const debut = html.indexOf('function ProspectionEditContacts(');
  const corps = html.slice(debut, html.indexOf('var addContact', debut));
  assert.ok(corps.includes(".not('geste_at', 'is', null)"));
  assert.ok(!/if \(porte\)/.test(corps));
});
