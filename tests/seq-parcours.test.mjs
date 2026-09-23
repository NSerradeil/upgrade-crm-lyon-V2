// tests/seq-parcours.test.mjs — le cycle d'étapes d'une séquence, par TYPE DE CIBLE.
//
// Depuis le 23/09, une séquence ne suit plus forcément une personne : le scan des
// plateformes est une campagne, et chaque plateforme est une cible suivie. Ce test
// verrouille les DEUX patterns, et surtout la NON-RÉGRESSION des personnes — il y en a des
// dizaines en cours, avec de l'historique : leur encodage d'étape (0 identifié · 1 invité ·
// 2 accepté · 3 messagé · 3+n relancé n · 6 répondu) ne doit pas bouger d'un iota.
//
// Les fonctions sont extraites d'index.html (mono-fichier, pas de module) — même méthode
// que le check Babel : on teste le code qui tourne vraiment, pas une copie.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  // Ordre volontaire : le const d'UNE ligne avant le const multi-lignes — sinon le motif
  // multi-lignes file jusqu'au `};` de la déclaration SUIVANTE et avale deux définitions.
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nconst ${nom} = [^\\n]*;\\n`),
                    new RegExp(`\\nconst ${nom} = \\{[\\s\\S]*?\\n\\};\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['JULES_SEQ_CADENCE_DEFAUT', 'julesSeqRelances', 'JULES_SEQ_PATTERNS',
              'julesSeqPattern', 'julesSeqTitreSection', 'julesSeqParcours',
              'julesSeqEtatDepuisFaits', 'julesSeqDelaiEtapeJours', 'julesSeqEcheance'];
const src = NOMS.map(extrait).join('\n');
const { julesSeqParcours, julesSeqEtatDepuisFaits, julesSeqEcheance, julesSeqTitreSection } =
  new Function(`${src}\nreturn {julesSeqParcours, julesSeqEtatDepuisFaits, julesSeqEcheance, julesSeqTitreSection};`)();

const CFG = { preset: 'prospection' };   // 2 relances → parcours de 4 étapes

test('personne : l\'encodage historique des étapes est intact', () => {
  const attendu = [[0, 0], [1, 1], [2, 1], [3, 2], [4, 3], [5, 4]];
  for (const [etape, faits] of attendu) {
    const p = julesSeqParcours({ etape, nb_relances: Math.max(0, etape - 3), statut: 'active' }, CFG);
    assert.equal(p.kind, 'personne');
    assert.equal(p.faits, faits, `etape ${etape} devrait valoir ${faits} étapes faites`);
    assert.equal(p.total, 4);
  }
});

test('personne : une réponse n\'est pas une sortie, et la position se relit', () => {
  const p = julesSeqParcours({ etape: 6, nb_relances: 1, statut: 'replied' }, CFG);
  assert.equal(p.aRepondu, true);
  assert.equal(p.sortie, null, 'répondre ne sort pas du parcours (règle Nicolas 21/09)');
  assert.equal(p.faits, 3, 'la barre continue de dire où la personne en est');
});

test('personne : au bout du parcours, plus rien n\'est prévu', () => {
  assert.equal(julesSeqEcheance(CFG, 4, 4, { target_kind: 'externe' }), null);
  assert.deepEqual(julesSeqEtatDepuisFaits(2, { target_kind: 'externe' }), { etape: 3, nb_relances: 0 });
});

test('plateforme : son cycle a 4 étapes, et « ouverte » n\'est PAS « couverte »', () => {
  const seq = (etape) => ({ target_kind: 'plateforme', etape, statut: 'active' });
  assert.deepEqual(julesSeqParcours(seq(0), CFG).etapes,
    ['Ouverte', 'Liste des besoins', 'Besoins ouverts', 'Qualifiés au CRM']);
  // 1 = la plateforme est ouverte mais la liste n'a jamais été atteinte. C'est l'échec
  // qui a fait passer 5 plateformes à la trappe le 23/09 : il doit CRIER, pas se lire
  // « Liste des besoins à venir ».
  const bloquee = julesSeqParcours(seq(1), CFG);
  assert.equal(bloquee.couverte, false);
  assert.match(bloquee.alerte, /NON COUVERTE/);
  for (const e of [2, 3, 4]) {
    const p = julesSeqParcours(seq(e), CFG);
    assert.equal(p.couverte, true);
    assert.equal(p.alerte, null);
  }
  // Étape 0 : pas encore ouverte du jour — rien à signaler, ce n'est pas un échec.
  assert.equal(julesSeqParcours(seq(0), CFG).alerte, null);
});

test('plateforme : son échéance suit SA cadence, jamais celle des relances', () => {
  const s = { target_kind: 'plateforme', cadence_jours: 3, heure_passage: '09:30' };
  const d = new Date(julesSeqEcheance(CFG, 4, 4, s));   // même au bout du cycle : elle repasse
  const attendu = new Date(); attendu.setDate(attendu.getDate() + 3); attendu.setHours(9, 30, 0, 0);
  assert.equal(d.toISOString(), attendu.toISOString());
  assert.deepEqual(julesSeqEtatDepuisFaits(3, s), { etape: 3, nb_relances: 0 });
});

test('le titre de la section suit le type de cible', () => {
  assert.equal(julesSeqTitreSection([{ target_kind: 'externe' }]), 'Personnes suivies');
  assert.equal(julesSeqTitreSection([{ target_kind: 'plateforme' }]), 'Plateformes suivies');
  assert.equal(julesSeqTitreSection([{ target_kind: 'plateforme' }, { target_kind: 'externe' }]), 'Cibles suivies');
});
