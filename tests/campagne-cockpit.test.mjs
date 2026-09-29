// tests/campagne-cockpit.test.mjs : la sortie manuelle d'une personne depuis le cockpit Jules applique
// au CRM la correspondance des campagnes de prospection. julesSortieCampagneCrm est extraite d'index.html
// et jouee contre un faux client Supabase ; le cablage de l'ecran est verifie sur le source.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

process.env.TZ = 'Europe/Paris';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nasync function ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nconst ${nom} ?= ?[^\\n]*;\\n`),
                    new RegExp(`\\nconst ${nom} = \\[[\\s\\S]*?\\n\\];\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['DEFAULT_TASK_TIME', 'combineDT', 'PROSPECT_ETAPES', 'PROSPECT_ETAPES_ACTIVES', 'PROSPECT_ETAPES_SORTIE',
              'prospectEtapeOuDefaut', 'prospectEtapeRequiert', 'prospectTacheLibelle', 'prospectTacheEcheance',
              'prospectReveilPreset', 'prospectPatchEtape', 'prospectTachePayload', 'prospectAnnulerTachesOuvertes',
              'CAMPAGNE_MOTIF_PERTE_PROFIL', 'CAMPAGNE_LIBELLES_SORTIE', 'campagneEstProspection', 'campagneEffetSortie',
              'campagneJourOuvreSuivant', 'campagneSortiePlan', 'julesSortieCampagneCrm', 'JULES_RAISONS_SORTIE'];
const SRC = NOMS.map(extrait).join('\n');
const charge = (sb) => new Function('sb', 'getToday', `${SRC}\nreturn { julesSortieCampagneCrm, JULES_RAISONS_SORTIE };`)(sb, () => '2026-09-29');

// Faux client Supabase : from(t).select().eq().like().in(), update(), insert(), maybeSingle(), await.
function fauxSb(tables) {
  const appels = [];
  const sb = { from(table) {
    appels.push(table);
    const rows = () => (tables[table] = tables[table] || []);
    const filtres = []; let op = 'select', valeur = null, unique = false;
    const run = () => {
      const hit = rows().filter(r => filtres.every(f => f(r)));
      if (op === 'insert') { rows().push({ ...valeur }); return { data: [valeur], error: null }; }
      if (op === 'update') { hit.forEach(r => Object.assign(r, valeur)); return { data: hit, error: null }; }
      return { data: unique ? (hit[0] || null) : hit, error: null };
    };
    const q = {
      select() { return q; },
      eq(k, v) { filtres.push(r => String(r[k]) === String(v)); return q; },
      like(k, p) { const re = new RegExp('^' + p.split('%').map(s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*') + '$'); filtres.push(r => re.test(String(r[k]))); return q; },
      in(k, vs) { filtres.push(r => vs.map(String).includes(String(r[k]))); return q; },
      update(v) { op = 'update'; valeur = v; return q; },
      insert(v) { op = 'insert'; valeur = v; return q; },
      maybeSingle() { unique = true; return Promise.resolve(run()); },
      then(res, rej) { return Promise.resolve(run()).then(res, rej); },
    };
    return q;
  } };
  return { sb, appels, tables };
}
const PROSPECTION = { id: 'M1', titre: 'Prospection DSI Lyon', kind: 'campagne', config: { preset: 'prospection' } };
const JEAN = (etape, statut = 'Prospect') => ({ id: 7, prenom: 'Jean', nom: 'DUPONT', statut, responsable: 'Nicolas Serradeil', etape_prospect: etape });
const SEQ = { id: 'S1', mission_id: 'M1', target_label: 'Jean Dupont', contact_id: 7 };

test('refus : la fiche liee passe En veille a 6 mois et une ligne d historique est ecrite', async () => {
  const f = fauxSb({ contacts: [JEAN('Contacté')] });
  const plan = await charge(f.sb).julesSortieCampagneCrm(SEQ, 'refus', PROSPECTION, 'Nicolas Serradeil', '');
  assert.equal(plan.effet.etape, 'En veille');
  assert.equal(f.tables.contacts[0].etape_prospect, 'En veille');
  assert.equal(f.tables.contacts[0].prochaine_action_date, '2027-03-29T09:00:00+02:00');
  assert.deepEqual(f.tables.historique_actions, [{ id_prospect: 7, date: '2026-09-29', type_action: 'LinkedIn',
    details: 'Campagne Prospection DSI Lyon : refus (le 29/09/2026), sortie par Nicolas Serradeil · étape → En veille', responsable: 'Nicolas Serradeil' }]);
});

test('ne plus contacter : Ne pas recontacter pose directement (Nicolas decide) et taches de prospection annulees', async () => {
  const f = fauxSb({ contacts: [JEAN(null, 'Client')], taches: [{ id: 'tw_prospect_7_1', contact_id: 7, statut: 'en_cours' }] });
  await charge(f.sb).julesSortieCampagneCrm(SEQ, 'npc', PROSPECTION, 'Nicolas Serradeil', 'a demande a ne plus etre sollicite');
  assert.equal(f.tables.contacts[0].etape_prospect, 'Ne pas recontacter');
  assert.equal(f.tables.contacts[0].motif_perte_precision, 'a demande a ne plus etre sollicite');
  assert.equal(f.tables.taches[0].statut, 'annule');
});

test('converti : tache Confirmer la date du RDV creee, sauf si une tache de prospection est deja ouverte', async () => {
  const f = fauxSb({ contacts: [JEAN('Contacté')] });
  await charge(f.sb).julesSortieCampagneCrm(SEQ, 'converti', PROSPECTION, 'Nicolas Serradeil', '');
  assert.equal(f.tables.taches.length, 1);
  assert.equal(f.tables.taches[0].titre, 'Confirmer la date du RDV : Jean DUPONT');
  const g = fauxSb({ contacts: [JEAN('Contacté')], taches: [{ id: 'tw_prospect_7_1', contact_id: 7, statut: 'en_cours' }] });
  await charge(g.sb).julesSortieCampagneCrm(SEQ, 'converti', PROSPECTION, 'Nicolas Serradeil', '');
  assert.equal(g.tables.taches.length, 1);
});

test('hors campagne de prospection, sans fiche liee, ou doublon : aucune lecture ni ecriture', async () => {
  const f = fauxSb({ contacts: [JEAN('Contacté')] });
  const api = charge(f.sb);
  assert.equal(await api.julesSortieCampagneCrm(SEQ, 'refus', { ...PROSPECTION, config: {} }, 'Nicolas Serradeil', ''), null);
  assert.equal(await api.julesSortieCampagneCrm({ ...SEQ, contact_id: null }, 'refus', PROSPECTION, 'Nicolas Serradeil', ''), null);
  assert.equal(f.appels.length, 0);
  assert.equal(await api.julesSortieCampagneCrm(SEQ, 'doublon', PROSPECTION, 'Nicolas Serradeil', ''), null);
  assert.equal((f.tables.historique_actions || []).length, 0);
  assert.equal(f.tables.contacts[0].etape_prospect, 'Contacté');
});

test('le motif Ne plus contacter existe dans la modale de sortie', () => {
  const { JULES_RAISONS_SORTIE } = charge(fauxSb({}).sb);
  const npc = JULES_RAISONS_SORTIE.find(r => r.cle === 'npc');
  assert.ok(npc, 'motif npc absent');
  assert.equal(npc.label, 'Ne plus contacter, à sa demande');
  assert.doesNotMatch(npc.label, /[\u2013\u2014]/);
});

test('cablage : la raison et la mission arrivent jusqu a arreterSuivi, la fiche liee est cliquable', () => {
  assert.match(html, /async arreterSuivi\(s, raison, mission, responsable\) \{/);
  assert.match(html, /arreterSuivi:\(s,raison,mission\)=>agir\(s\.id,\(\)=>julesActions\.arreterSuivi\(s,raison,mission,profile&&profile\.nom\)\),/);
  assert.match(html, /actions\.arreterSuivi\(sq, raison, mission\); \}\}\/>\}/);
  assert.match(html, /const plan = await julesSortieCampagneCrm\(s, motif, mission, responsable, texte\);/);
  assert.match(html, /function TabJules\(\{ profile, prefs, deepLink, onNavToContact \}\) \{/);
  assert.match(html, /<TabJules profile=\{profile\} prefs=\{prefs\} deepLink=\{julesDeepLink\} onNavToContact=\{navToContact\}\/>/);
  assert.match(html, /function JulesDetail\(\{ missionId, data, onClose, actions, occupe, discuter, onNavToContact \}\) \{/);
  assert.match(html, /\{s\.contact_id&&onNavToContact&&\(/);
  assert.match(html, /onClick=\{\(\)=>\{ onClose\(\); onNavToContact\(s\.contact_id\); \}\}/);
});

test('aucun tiret cadratin ni demi-cadratin dans le code ajoute', () => {
  assert.doesNotMatch(extrait('julesSortieCampagneCrm'), /[\u2013\u2014]/);
  const i = html.indexOf('// Campagne de prospection (SPEC_campagnes_prospection_etapes.md) : la sortie applique');
  const j = html.indexOf("'error');", i);
  assert.ok(i > 0 && j > i, 'bloc ajoute a arreterSuivi introuvable');
  assert.doesNotMatch(html.slice(i, j), /[\u2013\u2014]/);
});

// ---- Fix round 1 : garanties centrales ----
function fauxSbErreur(tables, tableEnErreur, op) {
  const f = fauxSb(tables);
  const base = f.sb.from;
  f.sb.from = (table) => {
    const q = base(table);
    if (table !== tableEnErreur) return q;
    const orig = q[op];
    q[op] = (v) => { orig(v); q.then = (res, rej) => Promise.resolve({ data: null, error: { message: 'boom ' + table } }).then(res, rej); return q; };
    return q;
  };
  return f;
}

test('erreur CRM sur la mise a jour de la fiche : elle est levee, aucune ligne d historique', async () => {
  const f = fauxSbErreur({ contacts: [JEAN('Contacté')] }, 'contacts', 'update');
  await assert.rejects(charge(f.sb).julesSortieCampagneCrm(SEQ, 'refus', PROSPECTION, 'Nicolas Serradeil', ''), /boom contacts/);
  assert.equal((f.tables.historique_actions || []).length, 0);
});

test('erreur CRM sur l historique : elle est levee', async () => {
  const f = fauxSbErreur({ contacts: [JEAN('Contacté')] }, 'historique_actions', 'insert');
  await assert.rejects(charge(f.sb).julesSortieCampagneCrm(SEQ, 'refus', PROSPECTION, 'Nicolas Serradeil', ''), /boom historique_actions/);
});

test('converti : l historique est ecrit AVANT la tache, donc une tache en erreur laisse une trace', async () => {
  const f = fauxSbErreur({ contacts: [JEAN('Contacté')] }, 'taches', 'insert');
  await assert.rejects(charge(f.sb).julesSortieCampagneCrm(SEQ, 'converti', PROSPECTION, 'Nicolas Serradeil', ''), /boom taches/);
  assert.equal(f.tables.historique_actions.length, 1);
});

test('precision par defaut identique au MCP (refus, silence), la saisie l emporte', async () => {
  const a = fauxSb({ contacts: [JEAN('Contacté')] });
  await charge(a.sb).julesSortieCampagneCrm(SEQ, 'refus', PROSPECTION, 'Nicolas Serradeil', '');
  assert.equal(a.tables.contacts[0].motif_perte_precision, 'Refus en campagne Prospection DSI Lyon');
  const b = fauxSb({ contacts: [JEAN('Contacté')] });
  await charge(b.sb).julesSortieCampagneCrm(SEQ, 'silence', PROSPECTION, 'Nicolas Serradeil', '');
  assert.equal(b.tables.contacts[0].motif_perte_precision, 'Sans réponse à la campagne Prospection DSI Lyon');
  const c = fauxSb({ contacts: [JEAN('Contacté')] });
  await charge(c.sb).julesSortieCampagneCrm(SEQ, 'refus', PROSPECTION, 'Nicolas Serradeil', 'raison saisie');
  assert.equal(c.tables.contacts[0].motif_perte_precision, 'raison saisie');
});

test('arreterSuivi : garde de statut conservee, CRM en try APRES l insertion de l evenement', () => {
  const i = html.indexOf('async arreterSuivi(s, raison, mission, responsable) {');
  assert.ok(i > 0);
  const corps = html.slice(i, html.indexOf('\n  },\n', i));
  assert.match(corps, /\.in\('statut',\['active','replied','paused'\]\)/);
  const ev = corps.indexOf("from('agent_events').insert");
  const tr = corps.indexOf('try {');
  const ap = corps.indexOf('julesSortieCampagneCrm(');
  assert.ok(ev > 0 && tr > ev && ap > tr, 'ordre evenement, try, appel CRM');
  assert.match(corps.slice(tr), /^try \{[\s\S]*julesSortieCampagneCrm\([\s\S]*\} catch \(e\) \{[\s\S]*toast\(/);
});
