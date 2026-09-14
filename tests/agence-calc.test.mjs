import { test } from 'node:test';
import assert from 'node:assert/strict';
import '../agence-calc.js';
const A = globalThis.AgenceCalc;

const T = '2026-09-14';
const FERIES = new Set(['2026-11-11']);
const base = { id: 1, prenom: 'Laurie', nom: 'MARTINEAU', statut: 'Consultant CDI', agence: 'Lyon', cjm: 411.16, responsable: 'Nicolas Serradeil' };
const mk = (over) => ({ ...base, ...over });
const ctx = (missions = [], intercos = [], extra = {}) => ({ missions, intercos, partnerNomById: { 'u-majo': 'Majo Paquelier' }, partnerIdByContact: {}, todayISO: T, annee: 2026, ...extra });

test('cjmFromSalaire : 61000 → 482.33', () => { assert.equal(A.cjmFromSalaire(61000), 482.33); });
test('joursEntre', () => { assert.equal(A.joursEntre('2026-09-14', '2026-12-31'), 108); assert.equal(A.joursEntre('2026-09-14', '2026-09-11'), -3); });

test('en mission > 60 j → vert', () => {
  const c = A.computeCollab(mk(), ctx([{ id: 'm1', contact_consultant_id: 1, statut: 'En cours', tjm: 490, cjm: 411.16, date_fin_mission: '2026-12-31', client: 'EDF' }]));
  assert.equal(c.etat, 'en_mission'); assert.equal(c.joursAvantDispo, 108); assert.equal(c.tjm, 490);
  assert.equal(Math.round(c.marge * 1000) / 1000, 0.161);
  assert.equal(A.etatDispo(c).bg, '#00C218');
});
test('≤ 60 j → orange, ≤ 30 j → rouge, dépassée → rouge libellé', () => {
  const m = (fin) => [{ id: 'm', contact_consultant_id: 1, statut: 'En cours', tjm: 600, date_fin_mission: fin }];
  assert.equal(A.etatDispo(A.computeCollab(mk(), ctx(m('2026-10-30')))).bg, '#F97316');   // 46 j
  assert.equal(A.etatDispo(A.computeCollab(mk(), ctx(m('2026-09-30')))).bg, '#FF3D2E');   // 16 j
  const dep = A.etatDispo(A.computeCollab(mk(), ctx(m('2026-09-11'))));
  assert.equal(dep.bg, '#FF3D2E'); assert.match(dep.label, /dépassée de 3 j/);
});
test('mission sans date de fin → en_mission, joursAvantDispo null', () => {
  const c = A.computeCollab(mk(), ctx([{ id: 'm', contact_consultant_id: 1, statut: 'En cours', tjm: 600, date_fin_mission: null }]));
  assert.equal(c.etat, 'en_mission'); assert.equal(c.joursAvantDispo, null); assert.match(A.etatDispo(c).label, /fin non définie/);
});
test('CDI sans mission → intercontrat + cumul année', () => {
  const c = A.computeCollab(mk(), ctx([], [{ contact_consultant_id: 1, annee: 2026, mois: 8, jours: 12 }, { contact_consultant_id: 1, annee: 2026, mois: 9, jours: 5.5 }, { contact_consultant_id: 1, annee: 2025, mois: 12, jours: 9 }]));
  assert.equal(c.etat, 'intercontrat'); assert.equal(c.intercoAnnee, 17.5);
  assert.equal(A.etatDispo(c).bg, '#E4E4E6'); assert.match(A.etatDispo(c).label, /17,5 j cumulés 2026/);
});
test('ST sans mission → sans_mission ; typeLabel', () => {
  const c = A.computeCollab(mk({ statut: 'Freelance', type_presta: 'freelance' }), ctx());
  assert.equal(c.etat, 'sans_mission'); assert.equal(c.typeLabel, 'Freelance');
  assert.equal(A.computeCollab(mk({ statut: 'Prestataire', type_presta: 'sous_traitant' }), ctx()).typeLabel, 'Sous-traitant');
});
test('statut_rh prime sur la mission', () => {
  const c = A.computeCollab(mk({ statut_rh: 'arret_maladie', statut_rh_depuis: '2026-09-01' }), ctx([{ id: 'm', contact_consultant_id: 1, statut: 'En cours', tjm: 600, date_fin_mission: '2026-12-31' }]));
  assert.equal(c.etat, 'arret_maladie'); const b = A.etatDispo(c); assert.equal(b.bg, '#FF3D2E'); assert.equal(b.color, '#FFFFFF'); assert.match(b.label, /Arrêt maladie · depuis le 01\/09/);
});
test('mission New à venir → demarre_bientot', () => {
  const c = A.computeCollab(mk(), ctx([{ id: 'm', contact_consultant_id: 1, statut: 'New', tjm: 600, date_debut_mission: '2026-09-22', date_fin_mission: '2026-12-31' }]));
  assert.equal(c.etat, 'demarre_bientot'); assert.match(A.etatDispo(c).label, /démarre le 22\/09/);
});
test('plusieurs missions En cours → la fin la plus lointaine', () => {
  const c = A.computeCollab(mk(), ctx([{ id: 'a', contact_consultant_id: 1, statut: 'En cours', tjm: 500, date_fin_mission: '2026-10-01' }, { id: 'b', contact_consultant_id: 1, statut: 'En cours', tjm: 600, date_fin_mission: '2026-12-31' }]));
  assert.equal(c.missionEnCours.id, 'b');
});
test('sorti + partnerNom + fallback trigramme', () => {
  const c1 = A.computeCollab(mk({ date_sortie: '2026-06-30', manager_trigramme: 'NSE' }), ctx([], [], { partnerIdByContact: {} }));
  assert.equal(c1.sorti, true); assert.equal(c1.partnerNom, 'Nicolas Serradeil');
  const c2 = A.computeCollab(mk({ date_sortie: '2027-01-01' }), ctx([], [], { partnerIdByContact: { 1: 'u-majo' } }));
  assert.equal(c2.sorti, false); assert.equal(c2.partnerNom, 'Majo Paquelier');
});
test('margeStyle', () => {
  assert.equal(A.margeStyle(0.35).color, '#1C1F35'); assert.equal(A.margeStyle(0.25).color, '#F97316'); assert.equal(A.margeStyle(0.15).color, '#FF3D2E'); assert.equal(A.margeStyle(null).color, '#A4A6AB');
});
test('computeKpis cdi', () => {
  const cs = [
    A.computeCollab(mk({ id: 1, cjm: 400 }), ctx([{ id: 'a', contact_consultant_id: 1, statut: 'En cours', tjm: 600, date_fin_mission: '2026-12-31' }])),
    A.computeCollab(mk({ id: 2, cjm: 300 }), ctx([{ id: 'b', contact_consultant_id: 2, statut: 'En cours', tjm: 500, date_fin_mission: '2026-10-01' }])),
    A.computeCollab(mk({ id: 3, cjm: 350 }), ctx([], [{ contact_consultant_id: 3, annee: 2026, mois: 9, jours: 10 }])),
  ];
  const k = A.computeKpis(cs, 'cdi');
  assert.equal(k.effectif, 3); assert.equal(k.cjmMoyen, 350); assert.equal(k.tjmMoyen, 550);
  assert.equal(Math.round(k.margeMoyenne * 1000) / 1000, 0.367); assert.equal(k.dispo60, 1); assert.equal(k.intercoAnnee, 10);
});
test('prochainJourOuvre930 : vendredi → lundi, veille de férié → saute', () => {
  assert.equal(A.prochainJourOuvre930('2026-09-11', FERIES), '2026-09-14T09:30:00'); // ven → lun
  assert.equal(A.prochainJourOuvre930('2026-11-10', FERIES), '2026-11-12T09:30:00'); // 11/11 férié
  assert.equal(A.prochainJourOuvre930('2026-09-14', FERIES), '2026-09-15T09:30:00'); // jamais aujourd'hui
});
test('planAlertes : crée à ≤60 j, idempotent, clôt si prolongée', () => {
  const m = { id: 'm1', contact_consultant_id: 1, statut: 'En cours', tjm: 600, cjm: 400, date_fin_mission: '2026-10-30', client: 'EDF', responsable: 'Nicolas Serradeil' };
  const c = A.computeCollab(mk({ cjm: 400 }), ctx([m]));
  const r1 = A.planAlertes([c], [], { todayISO: T, feries: FERIES, profilNom: 'Amel Benzai' });
  assert.equal(r1.aCreer.length, 1);
  const t = r1.aCreer[0];
  assert.match(t.titre, /^⏳ Fin de mission Laurie MARTINEAU — EDF le 30\/10 \(J-46\)/);
  assert.equal(t.mission_id, 'm1'); assert.equal(t.contact_id, 1); assert.equal(t.responsable, 'Nicolas Serradeil');
  assert.equal(t.due_date, '2026-09-15T09:30:00'); assert.equal(t.statut, 'en_cours'); assert.match(t.notes, /TJM 600 · CJM 400 · marge 33 %/);
  // idempotence : une tâche existe (même clôturée) → rien
  const r2 = A.planAlertes([c], [{ id: 'x', mission_id: 'm1', titre: '⏳ Fin de mission Laurie MARTINEAU — EDF le 30/10 (J-46)', statut: 'fait' }], { todayISO: T, feries: FERIES, profilNom: 'Amel' });
  assert.equal(r2.aCreer.length, 0); assert.equal(r2.aClore.length, 0);
  // prolongée > 60 j avec alerte ouverte → aClore
  const c2 = A.computeCollab(mk({ cjm: 400 }), ctx([{ ...m, date_fin_mission: '2027-03-31' }]));
  const r3 = A.planAlertes([c2], [{ id: 'x', mission_id: 'm1', titre: '⏳ Fin de mission …', statut: 'en_cours' }], { todayISO: T, feries: FERIES, profilNom: 'Amel' });
  assert.equal(r3.aCreer.length, 0); assert.deepEqual(r3.aClore, [{ id: 'x', note: 'mission prolongée au 31/03/2027' }]);
  // sorti ou sans mission → rien
  assert.equal(A.planAlertes([A.computeCollab(mk({ date_sortie: '2026-01-01' }), ctx([m]))], [], { todayISO: T, feries: FERIES, profilNom: 'A' }).aCreer.length, 0);
});
test('arriveesSortiesParMois', () => {
  const cs = [mk({ id: 1, date_entree: '2026-02-10' }), mk({ id: 2, date_entree: '2026-02-23' }), mk({ id: 3, date_entree: '2025-06-01', date_sortie: '2026-06-30' }), mk({ id: 4, date_entree: '2026-11-02' })].map((c) => A.computeCollab(c, ctx()));
  const r = A.arriveesSortiesParMois(cs, 2026);
  assert.deepEqual(r.arrivees, [0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]);
  assert.deepEqual(r.sorties, [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
  assert.equal(r.cumul[0], 1); assert.equal(r.cumul[1], 3); assert.equal(r.cumul[5], 2); assert.equal(r.cumul[11], 3);
  assert.deepEqual(r.listeArrivees[1].map((k) => k.id), [1, 2]);
});
test('tranchesTjm / tranchesMarge', () => {
  const mission = (id, tjm) => ({ id: 'm' + id, contact_consultant_id: id, statut: 'En cours', tjm, date_fin_mission: '2026-12-31' });
  const cs = [[1, 450, 400], [2, 550, 300], [3, 650, 500], [4, 800, 400]].map(([id, tjm, cjm]) => A.computeCollab(mk({ id, cjm }), ctx([mission(id, tjm)])));
  const t = A.tranchesTjm(cs);
  assert.deepEqual(t.map((x) => [x.label, x.items.length]), [['< 500 €', 1], ['500-600 €', 1], ['600-700 €', 1], ['> 700 €', 1]]);
  const g = A.tranchesMarge(cs); // marges : 0.11, 0.45, 0.23, 0.5
  assert.deepEqual(g.map((x) => [x.label, x.items.length]), [['< 20 %', 1], ['20-30 %', 1], ['30-40 %', 0], ['> 40 %', 2]]);
  assert.equal(g[0].color, '#FF3D2E'); assert.equal(g[3].color, '#00C218');
});
test('tjmMargeParMois', () => {
  const ms = [{ tjm: 600, cjm: 400, jours_jan: 10, jours_fev: 0 }, { tjm: 800, cjm: 400, jours_jan: 5, jours_fev: 20 }];
  const r = A.tjmMargeParMois(ms, 2026);
  assert.equal(r.tjm[0], 700); assert.equal(r.tjm[1], 800); assert.equal(r.tjm[2], null);
  assert.equal(Math.round(r.marge[0] * 1000) / 1000, 0.417); assert.equal(r.marge[1], 0.5);
});
test('intercoStats (logique TDB)', () => {
  const jo = () => 20; // 20 j ouvrés / mois pour le test
  const intercos = [{ contact_consultant_id: 1, annee: 2026, mois: 1, jours: 10, cjm_snapshot: 400 }, { contact_consultant_id: 2, annee: 2026, mois: 2, jours: 4, cjm_snapshot: 300 }];
  const s = A.intercoStats(new Set([1, 2]), intercos, 2026, 2, jo); // mars courant (idx 2), non saisi → M-1 = fév
  assert.equal(s.tauxM[0], 25); assert.equal(s.tauxM[1], 10); assert.equal(s.joursYTD, 14); assert.equal(s.coutYTD, 5200);
  assert.equal(Math.round(s.tauxAnn * 100) / 100, 11.67); assert.equal(s.idxAff, 1); assert.equal(s.fallbackM1, true); assert.equal(s.nbCourant, 1);
  assert.deepEqual(s.parMois(0), [{ contact_consultant_id: 1, jours: 10, cout: 4000 }]);
});
