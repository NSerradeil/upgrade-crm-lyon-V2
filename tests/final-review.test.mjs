// tests/final-review.test.mjs : revue finale. I3 (arret des sequences liees a l'entree en Ne pas recontacter)
// et M5 (avertissement de la sortie « Ne plus contacter » sans fiche liee). Fonctions extraites d'index.html.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

process.env.TZ = 'Europe/Paris';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nasync function ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nconst ${nom} ?= ?[^\\n]*;\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['campagneEstProspection', 'prospectEntreeNpc', 'prospectStopperSequencesLiees', 'campagneAvertissementSansFiche'];
const SRC = NOMS.map(extrait).join('\n');
const charge = (sb) => new Function('sb', `${SRC}\nreturn { ${NOMS.join(',')} };`)(sb);

function fauxSb(tables, { erreurLecture = null } = {}) {
  return { from(table) {
    const rows = () => (tables[table] = tables[table] || []);
    const filtres = []; let op = 'select', valeur = null;
    const run = () => {
      if (erreurLecture && op === 'select') return { data: null, error: { message: erreurLecture } };
      const hit = rows().filter(r => filtres.every(f => f(r)));
      if (op === 'update') { hit.forEach(r => Object.assign(r, valeur)); return { data: hit, error: null }; }
      return { data: hit, error: null };
    };
    const q = {
      select() { return q; },
      eq(k, v) { filtres.push(r => String(r[k]) === String(v)); return q; },
      in(k, vs) { filtres.push(r => vs.map(String).includes(String(r[k]))); return q; },
      update(v) { op = 'update'; valeur = v; return q; },
      then(res, rej) { return Promise.resolve(run()).then(res, rej); },
    };
    return q;
  } };
}

test('I3 : seule l entree en Ne pas recontacter arrete les sequences', () => {
  const { prospectEntreeNpc } = charge(null);
  assert.equal(prospectEntreeNpc('Contacté', 'Ne pas recontacter'), true);
  assert.equal(prospectEntreeNpc('À contacter', 'Ne pas recontacter'), true);
  assert.equal(prospectEntreeNpc('Ne pas recontacter', 'Ne pas recontacter'), false);
  assert.equal(prospectEntreeNpc('Ne pas recontacter', 'Contacté'), false, 'sortir de NPC n arrete rien');
  assert.equal(prospectEntreeNpc('Contacté', 'À relancer'), false);
});

test('I3 : stoppe active, replied et paused du contact, note datee, laisse les autres', async () => {
  const tables = { agent_sequences: [
    { id: 'a', contact_id: 7, statut: 'active', next_due_at: '2026-10-01T08:00:00Z', notes: 'n1' },
    { id: 'r', contact_id: 7, statut: 'replied', next_due_at: null, notes: null },
    { id: 'p', contact_id: 7, statut: 'paused', next_due_at: '2026-10-05T08:00:00Z', notes: null },
    { id: 's', contact_id: 7, statut: 'stopped', next_due_at: null, notes: 'deja' },
    { id: 'c', contact_id: 7, statut: 'converted', next_due_at: null, notes: null },
    { id: 'x', contact_id: 8, statut: 'active', next_due_at: '2026-10-01T08:00:00Z', notes: null },
  ] };
  const r = await charge(fauxSb(tables)).prospectStopperSequencesLiees(7);
  assert.equal(r.error, null); assert.equal(r.arretees, 3);
  const st = Object.fromEntries(tables.agent_sequences.map(s => [s.id, s.statut]));
  assert.deepEqual(st, { a: 'stopped', r: 'stopped', p: 'stopped', s: 'stopped', c: 'converted', x: 'active' });
  const a = tables.agent_sequences[0];
  assert.equal(a.next_due_at, null);
  assert.match(a.notes, /^n1\n\[\d{2}\/\d{2}\/\d{4}\] Arrêt : fiche passée en Ne pas recontacter$/);
  assert.doesNotMatch(a.notes, /[–—]/);
  assert.equal(tables.agent_sequences[3].notes, 'deja');
});

test('I3 : colonne contact_id absente (avant migration 54) : l erreur revient, rien n est leve', async () => {
  const r = await charge(fauxSb({ agent_sequences: [] }, { erreurLecture: 'column agent_sequences.contact_id does not exist' })).prospectStopperSequencesLiees(7);
  assert.match(r.error.message, /contact_id/); assert.equal(r.arretees, 0);
});

test('I3 : le cablage couvre les trois chemins NPC, pas la levee de NPC', () => {
  assert.equal((html.match(/prospectStopperSequencesLiees\(/g) || []).length, 4, 'definition + 3 appels (le 4e, la sortie du cockpit Jules, a ete retire du CRM)');
  assert.match(html, /prospectEntreeNpc\(prospectEtapeOuDefaut\(contact\),etape\)/);
  assert.match(html, /prospectEntreeNpc\(prospectEtapeOuDefaut\(sc\), patchAppel\.etape_prospect\)/);
  assert.match(html, /prospectEntreeNpc\(prospectEtapeOuDefaut\(pic2\), patchNpc\.etape_prospect\)/);
  const levee = html.slice(html.indexOf('const handleLeverNpc'), html.indexOf('const handleEtapeConfirm'));
  assert.doesNotMatch(levee, /prospectStopperSequencesLiees/);
});

test('M5 : Ne plus contacter sans fiche liee avertit ; avec fiche, ou autre motif, ou hors prospection : rien', () => {
  const { campagneAvertissementSansFiche } = charge(null);
  const PROS = { kind: 'campagne', config: { preset: 'prospection' } };
  assert.equal(campagneAvertissementSansFiche('npc', PROS, { contact_id: null }), 'Aucune fiche liée : CRM non modifié, à poser à la main');
  assert.equal(campagneAvertissementSansFiche('npc', PROS, {}), 'Aucune fiche liée : CRM non modifié, à poser à la main');
  assert.equal(campagneAvertissementSansFiche('npc', PROS, { contact_id: 7 }), null);
  assert.equal(campagneAvertissementSansFiche('refus', PROS, { contact_id: null }), null);
  assert.equal(campagneAvertissementSansFiche('npc', { kind: 'campagne', config: {} }, { contact_id: null }), null);
  assert.doesNotMatch(campagneAvertissementSansFiche('npc', PROS, {}), /[–—]/);
});
