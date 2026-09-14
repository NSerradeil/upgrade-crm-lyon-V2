// agence-calc.js — logique pure de l'onglet Agence (SPEC_agence_effectifs.md).
// Fichier JS classique (pas de JSX) : chargé par index.html AVANT le bloc Babel et testé avec `node --test`.
(function (root) {
  const MANAGER_TRIGRAMMES = {
    NSE: 'Nicolas Serradeil', ACD: 'Anne-Claire Decker', CSA: 'Camille Salinson', ABE: 'Amel Benzai',
    PSO: 'Pierre Solle', MJP: 'Majo Paquelier', LBL: 'Louis Blandin', CAJ: 'Cassandre Jacquemin',
    APL: 'Anthony Plancoulaine', WSA: 'Weronika Sawicki', FEL: 'Fabrice Elmoznino', HSI: 'Hervé Sinpaseuth',
    SLE: 'Stanislas Le Moy', JSE: 'Julian Sendra', COS: 'Constance Salem',
  };
  const CDI_STATUTS = ['Consultant CDI'];
  const ST_STATUTS = ['Freelance', 'Prestataire'];
  const CONSULTANT_STATUTS_AGENCE = CDI_STATUTS.concat(ST_STATUTS);
  const COL = { vert: '#00C218', orange: '#F97316', rouge: '#FF3D2E', gris: '#E4E4E6', midnight: '#1C1F35', blanc: '#FFFFFF', mute: '#A4A6AB' };

  // Casquettes internes (contacts.responsabilite). null = salarié·e sans casquette.
  const RESPONSABILITES = {
    lead_partner:        { label: 'Lead partner',           court: 'Lead partner', bg: '#823DE8', color: '#FFFFFF' },
    partner:             { label: 'Partner',                court: 'Partner',      bg: '#1C1F35', color: '#FFFFFF' },
    referent_technique:  { label: 'Référent·e technique',   court: 'Réf. tech',    bg: '#5090FE', color: '#FFFFFF' },
    referent_design_ops: { label: 'Référent·e Design Ops',  court: 'Réf. DesignOps', bg: '#FF78FD', color: '#1C1F35' },
  };
  const EST_PARTNER = (r) => r === 'partner' || r === 'lead_partner';
  // Liste des « partners responsables » proposables : les consultants porteurs d'une casquette
  // partner/lead partner + les commerciaux. Dédoublonnée par trigramme (Majo existe des deux côtés).
  function optionsPartners(contacts, profiles) {
    const out = new Map();
    (contacts || []).forEach((c) => {
      if (!EST_PARTNER(c.responsabilite) || !c.trigramme) return;
      if (c.date_sortie && d0(c.date_sortie) <= new Date().toISOString().slice(0, 10)) return;
      out.set(c.trigramme, { trigramme: c.trigramme, nom: `${c.prenom || ''} ${c.nom || ''}`.trim(), source: 'consultant', responsabilite: c.responsabilite, contact_id: c.id });
    });
    (profiles || []).forEach((p) => {
      if (!p.trigramme || out.has(p.trigramme)) return;
      out.set(p.trigramme, { trigramme: p.trigramme, nom: p.nom, source: 'commercial', profile_id: p.id });
    });
    return [...out.values()].sort((a, b) => (a.source === b.source ? a.nom.localeCompare(b.nom) : a.source === 'consultant' ? -1 : 1));
  }

  const cjmFromSalaire = (s) => Math.round((Number(s) / 215) * 1.7 * 100) / 100;
  const d0 = (iso) => (iso || '').slice(0, 10);
  const joursEntre = (a, b) => Math.round((Date.parse(d0(b) + 'T00:00:00Z') - Date.parse(d0(a) + 'T00:00:00Z')) / 86400000);
  const fmtJJMM = (iso) => { const s = d0(iso); return s ? `${s.slice(8, 10)}/${s.slice(5, 7)}` : ''; };
  const fmtJJMMAAAA = (iso) => { const s = d0(iso); return s ? `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)}` : ''; };
  const fmtJ = (n) => (n % 1 ? n.toFixed(1).replace('.', ',') : String(n));

  function computeCollab(c, ctx) {
    const { missions = [], intercos = [], partnerNomById = {}, partnerIdByContact = {}, partnerNomByTri = {}, todayISO, annee } = ctx;
    const mine = missions.filter((m) => m.contact_consultant_id === c.id);
    const enCours = mine.filter((m) => m.statut === 'En cours')
      .sort((a, b) => (d0(b.date_fin_mission) || '9999').localeCompare(d0(a.date_fin_mission) || '9999'));
    const aVenir = mine.filter((m) => m.statut === 'New' && d0(m.date_debut_mission) > todayISO)
      .sort((a, b) => d0(a.date_debut_mission).localeCompare(d0(b.date_debut_mission)));
    const missionEnCours = enCours[0] || aVenir[0] || null;
    const isCdi = CDI_STATUTS.includes(c.statut);
    const joursAvantDispo = enCours[0] && enCours[0].date_fin_mission ? joursEntre(todayISO, enCours[0].date_fin_mission) : null;
    const tjm = missionEnCours && missionEnCours.tjm != null ? Number(missionEnCours.tjm) : null;
    const cjm = c.cjm != null && c.cjm !== '' ? Number(c.cjm) : (missionEnCours && missionEnCours.cjm != null ? Number(missionEnCours.cjm) : null);
    const marge = tjm && cjm != null ? (tjm - cjm) / tjm : null;
    const intercoAnnee = intercos.filter((i) => i.contact_consultant_id === c.id && Number(i.annee) === annee)
      .reduce((s, i) => s + (parseFloat(i.jours) || 0), 0);
    let etat;
    if (c.statut_rh === 'arret_maladie' || c.statut_rh === 'conge') etat = c.statut_rh;
    else if (enCours[0]) etat = 'en_mission';
    else if (aVenir[0]) etat = 'demarre_bientot';
    else etat = isCdi ? 'intercontrat' : 'sans_mission';
    const sorti = !!(c.date_sortie && d0(c.date_sortie) <= todayISO);
    const pid = partnerIdByContact[c.id];
    const partnerNom = (pid && partnerNomById[pid]) || (partnerNomByTri || {})[c.manager_trigramme] || MANAGER_TRIGRAMMES[c.manager_trigramme] || c.manager_trigramme || '';
    const typeLabel = isCdi ? 'CDI' : (c.statut === 'Prestataire' ? 'Sous-traitant' : 'Freelance');
    return Object.assign({}, c, { missionEnCours, joursAvantDispo, tjm, cjm, marge, intercoAnnee, etat, sorti, partnerNom, typeLabel, isCdi, _annee: annee });
  }

  function etatDispo(k) {
    switch (k.etat) {
      case 'arret_maladie': return { label: `Arrêt maladie${k.statut_rh_depuis ? ' · depuis le ' + fmtJJMM(k.statut_rh_depuis) : ''}`, bg: COL.rouge, color: COL.blanc };
      case 'conge':         return { label: `Congé${k.statut_rh_depuis ? ' · depuis le ' + fmtJJMM(k.statut_rh_depuis) : ''}`, bg: COL.rouge, color: COL.blanc };
      case 'demarre_bientot': return { label: `démarre le ${fmtJJMM(k.missionEnCours.date_debut_mission)}`, bg: COL.vert, color: COL.midnight };
      case 'intercontrat':  return { label: `interco · ${fmtJ(k.intercoAnnee)} j cumulés ${k._annee || new Date().getFullYear()}`, bg: COL.gris, color: COL.midnight };
      case 'sans_mission':  return { label: 'sans mission', bg: COL.gris, color: COL.midnight };
      case 'en_mission': {
        const j = k.joursAvantDispo;
        if (j == null) return { label: 'fin non définie', bg: COL.vert, color: COL.midnight };
        if (j < 0) return { label: `dépassée de ${-j} j`, bg: COL.rouge, color: COL.blanc };
        if (j <= 30) return { label: `J-${j}`, bg: COL.rouge, color: COL.blanc };
        if (j <= 60) return { label: `J-${j}`, bg: COL.orange, color: COL.blanc };
        return { label: `J-${j}`, bg: COL.vert, color: COL.midnight };
      }
      default: return { label: '', bg: COL.gris, color: COL.midnight };
    }
  }

  // Seuil de marge : 30 % en CDI, 20 % en portage / sous-traitance (règle Upgrade).
  function seuilMarge(k) { return k && k.isCdi === false ? 0.20 : 0.30; }
  function sousSeuil(k) { return k && k.marge != null && k.marge < seuilMarge(k); }
  function margeStyle(m, k) {
    if (m == null || isNaN(m)) return { color: COL.mute };
    const s = seuilMarge(k);
    if (m < s - 0.10) return { color: COL.rouge };
    if (m < s) return { color: COL.orange };
    return { color: COL.midnight };
  }

  function computeKpis(collabs, mode) {
    const act = collabs.filter((k) => !k.sorti);
    const avg = (arr) => (arr.length ? Math.round((arr.reduce((s, v) => s + v, 0) / arr.length) * 10000) / 10000 : null);
    const cjms = act.map((k) => k.cjm).filter((v) => v != null && !isNaN(v));
    const tjms = act.map((k) => k.tjm).filter((v) => v != null && !isNaN(v));
    const marges = act.map((k) => k.marge).filter((v) => v != null && !isNaN(v));
    const fins60 = act.filter((k) => k.etat === 'en_mission' && k.joursAvantDispo != null && k.joursAvantDispo <= 60).length;
    return {
      effectif: act.length, cjmMoyen: avg(cjms), tjmMoyen: avg(tjms), margeMoyenne: avg(marges),
      dispo60: fins60, fins60,
      intercoAnnee: act.filter((k) => k.isCdi).reduce((s, k) => s + (k.intercoAnnee || 0), 0),
    };
  }

  function prochainJourOuvre930(todayISO, feries) {
    const f = feries || new Set();
    let d = new Date(d0(todayISO) + 'T00:00:00Z');
    do { d.setUTCDate(d.getUTCDate() + 1); } while (d.getUTCDay() === 0 || d.getUTCDay() === 6 || f.has(d.toISOString().slice(0, 10)));
    return d.toISOString().slice(0, 10) + 'T09:30:00';
  }

  const ALERTE_PREFIX = '⏳ Fin de mission';
  function planAlertes(collabs, taches, ctx) {
    const { todayISO, feries, profilNom } = ctx;
    const aCreer = [], aClore = [];
    const due = prochainJourOuvre930(todayISO, feries);
    collabs.forEach((k) => {
      if (k.sorti || k.etat !== 'en_mission' || !k.missionEnCours) return;
      const m = k.missionEnCours;
      const existing = taches.filter((t) => t.mission_id === m.id && (t.titre || '').startsWith(ALERTE_PREFIX));
      const j = k.joursAvantDispo;
      if (j != null && j >= 0 && j <= 60) {
        if (existing.length) return;
        const client = m.client || '';
        const margePct = k.marge != null ? Math.round(k.marge * 100) : null;
        aCreer.push({
          id: `al_${m.id}_${Date.now()}`,
          titre: `${ALERTE_PREFIX} ${k.prenom || ''} ${k.nom || ''} — ${client} le ${fmtJJMM(m.date_fin_mission)} (J-${j})`.replace(/\s+—\s+le/, ' le'),
          statut: 'en_cours', due_date: due, contact_id: k.id, mission_id: m.id, besoin_id: null,
          responsable: m.responsable || k.responsable || profilNom,
          notes: `Alerte auto onglet Agence (${k.isCdi ? 'préparer la suite' : 'renouvellement ou fin de contrat'}). TJM ${k.tjm ?? '?'} · CJM ${k.cjm ?? '?'} · marge ${margePct != null ? margePct + ' %' : '?'}`,
        });
      } else if (j != null && j > 60) {
        existing.filter((t) => t.statut === 'a_faire' || t.statut === 'en_cours')
          .forEach((t) => aClore.push({ id: t.id, note: `mission prolongée au ${fmtJJMMAAAA(m.date_fin_mission)}` }));
      }
    });
    return { aCreer, aClore };
  }

  // ── Détails des dalles KPI (spec §5.1) ─────────────────────────────────────
  function arriveesSortiesParMois(collabs, annee) {
    const arrivees = Array(12).fill(0), sorties = Array(12).fill(0), listeArrivees = Array.from({ length: 12 }, () => []);
    collabs.forEach((k) => {
      const e = d0(k.date_entree), s = d0(k.date_sortie);
      if (e && +e.slice(0, 4) === annee) { const i = +e.slice(5, 7) - 1; arrivees[i]++; listeArrivees[i].push(k); }
      if (s && +s.slice(0, 4) === annee) sorties[+s.slice(5, 7) - 1]++;
    });
    // effectif en fin de mois : présents entrés avant la fin du mois et non sortis avant la fin du mois
    const cumul = Array.from({ length: 12 }, (_, i) => {
      const fin = `${annee}-${String(i + 1).padStart(2, '0')}-31`;
      return collabs.filter((k) => (!k.date_entree || d0(k.date_entree) <= fin) && (!k.date_sortie || d0(k.date_sortie) > fin)).length;
    });
    listeArrivees.forEach((l) => l.sort((a, b) => d0(a.date_entree).localeCompare(d0(b.date_entree))));
    return { arrivees, sorties, cumul, listeArrivees };
  }
  function tranchesTjm(collabs) {
    const T = [{ label: '< 500 €', min: -Infinity, max: 500 }, { label: '500-600 €', min: 500, max: 600 }, { label: '600-700 €', min: 600, max: 700 }, { label: '> 700 €', min: 700, max: Infinity }];
    return T.map((t) => Object.assign({}, t, { items: collabs.filter((k) => k.tjm != null && k.tjm >= t.min && k.tjm < t.max) }));
  }
  function tranchesMarge(collabs) {
    const T = [{ label: '< 20 %', min: -Infinity, max: 0.20, color: COL.rouge }, { label: '20-30 %', min: 0.20, max: 0.30, color: COL.orange }, { label: '30-40 %', min: 0.30, max: 0.40, color: COL.midnight }, { label: '> 40 %', min: 0.40, max: Infinity, color: COL.vert }];
    return T.map((t) => Object.assign({}, t, { items: collabs.filter((k) => k.marge != null && k.marge >= t.min && k.marge < t.max).sort((a, b) => a.marge - b.marge) }));
  }
  const MOIS_KEYS_AC = ['jan', 'fev', 'mar', 'avr', 'mai', 'jun', 'jul', 'aou', 'sep', 'oct', 'nov', 'dec'];
  function tjmMargeParMois(missions, annee) {
    const tjm = [], marge = [];
    MOIS_KEYS_AC.forEach((k) => {
      const act = missions.filter((m) => (parseFloat(m['jours_' + k]) || 0) > 0 && parseFloat(m.tjm) > 0);
      if (!act.length) { tjm.push(null); marge.push(null); return; }
      const t = act.reduce((s, m) => s + parseFloat(m.tjm), 0) / act.length;
      const mg = act.reduce((s, m) => s + (parseFloat(m.tjm) - (parseFloat(m.cjm) || 0)) / parseFloat(m.tjm), 0) / act.length;
      tjm.push(Math.round(t * 100) / 100); marge.push(Math.round(mg * 10000) / 10000);
    });
    return { tjm, marge };
  }
  // Taux d'intercontrat HISTORIQUE (correction 14/09) : le dénominateur est l'effectif CDI réellement
  // présent CHAQUE MOIS (date_entree / date_sortie), pas l'effectif d'aujourd'hui. Sans ça, marquer
  // quelqu'un « sorti » effaçait rétroactivement ses jours d'interco et faussait le taux annuel (et donc
  // l'objectif 5 % / malus 8 %). `cdis` doit contenir TOUS les CDI du périmètre, sortis compris.
  function presentAuMois(c, annee, i) {
    const deb = d0(c.date_entree) || '0000-01-01';
    const fin = d0(c.date_sortie) || '9999-12-31';
    const m = String(i + 1).padStart(2, '0');
    const dernier = new Date(annee, i + 1, 0).getDate();
    return deb <= `${annee}-${m}-${dernier}` && fin >= `${annee}-${m}-01`;
  }
  function intercoStats(cdis, intercos, annee, curMonthIdx, joursOuvresMoisFn) {
    const list = Array.isArray(cdis) ? cdis : [...cdis].map((id) => ({ id }));   // compat : un Set d'ids reste accepté
    const ids = new Set(list.map((c) => c.id));
    const rows = intercos.filter((r) => Number(r.annee) === annee && ids.has(r.contact_consultant_id));
    const j = (i) => rows.filter((r) => r.mois === i + 1).reduce((s, r) => s + (parseFloat(r.jours) || 0), 0);
    const c = (i) => rows.filter((r) => r.mois === i + 1).reduce((s, r) => s + (parseFloat(r.jours) || 0) * (parseFloat(r.cjm_snapshot) || 0), 0);
    const effectif = (i) => list.filter((x) => presentAuMois(x, annee, i)).length;
    const tauxM = Array.from({ length: 12 }, (_, i) => { const d = effectif(i) * joursOuvresMoisFn(annee, i); return d > 0 ? (j(i) / d) * 100 : 0; });
    const joursYTD = Array.from({ length: curMonthIdx + 1 }, (_, i) => j(i)).reduce((a, b) => a + b, 0);
    const coutYTD = Array.from({ length: curMonthIdx + 1 }, (_, i) => c(i)).reduce((a, b) => a + b, 0);
    const denom = Array.from({ length: curMonthIdx + 1 }, (_, i) => effectif(i) * joursOuvresMoisFn(annee, i)).reduce((a, b) => a + b, 0);
    const tauxAnn = denom > 0 ? (joursYTD / denom) * 100 : 0;
    const courantRempli = rows.some((r) => r.mois === curMonthIdx + 1 && (parseFloat(r.jours) || 0) > 0);
    const idxAff = (courantRempli || curMonthIdx === 0) ? curMonthIdx : curMonthIdx - 1;
    const parMois = (i) => rows.filter((r) => r.mois === i + 1 && (parseFloat(r.jours) || 0) > 0)
      .map((r) => ({ contact_consultant_id: r.contact_consultant_id, jours: parseFloat(r.jours) || 0, cout: (parseFloat(r.jours) || 0) * (parseFloat(r.cjm_snapshot) || 0) }))
      .sort((a, b) => b.jours - a.jours);
    return { tauxM, tauxAnn, joursYTD, coutYTD, idxAff, fallbackM1: !courantRempli && idxAff !== curMonthIdx, nbCourant: parMois(idxAff).length, parMois, effectif };
  }

  const AgenceCalc = { MANAGER_TRIGRAMMES, RESPONSABILITES, EST_PARTNER, optionsPartners, seuilMarge, sousSeuil, CDI_STATUTS, ST_STATUTS, CONSULTANT_STATUTS_AGENCE, ALERTE_PREFIX, COL,
    cjmFromSalaire, joursEntre, fmtJJMM, fmtJJMMAAAA, fmtJ, computeCollab, etatDispo, margeStyle, computeKpis, prochainJourOuvre930, planAlertes,
    arriveesSortiesParMois, tranchesTjm, tranchesMarge, tjmMargeParMois, intercoStats };
  root.AgenceCalc = AgenceCalc;
  if (typeof module !== 'undefined' && module.exports) module.exports = AgenceCalc;
})(typeof globalThis !== 'undefined' ? globalThis : window);
