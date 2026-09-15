# BUG + SPEC — Périodes de mission : décimales & sync automatique
**CRM Upgrade Lyon V2**
**Date :** 03/04/2026

---

## Bug 1 — Trop de décimales sur TJM / CJM / delta

### Symptôme (screenshot)

```
CJM ACHAT : 276.74€       → ok à 2 chiffres mais incohérent avec le reste
CJM ACHAT : 284.65€
Delta     : +7.90999999999  ← flottant non arrondi, visuellement cassé
```

### Fix

**Règle uniforme : 1 seule décimale** sur tous les montants affichés dans la section Périodes (TJM vente, CJM achat, deltas, marge).

```js
// Formatter à utiliser partout dans MissionPeriodesSection
const fmtMontant = (v) => {
  if (v === null || v === undefined || v === '') return '—';
  return `${Number(v).toFixed(1)} €`;
};

const fmtDelta = (prev, curr) => {
  const diff = Number(curr) - Number(prev);
  if (diff === 0) return null;
  return `${diff > 0 ? '+' : ''}${diff.toFixed(1)}€`;
};

const fmtMarge = (v, c) => {
  if (!v || !c) return '—';
  return `${(((v - c) / v) * 100).toFixed(1)}%`;
};
```

**Appliquer à :**
- Colonne TJM VENTE dans la table (ligne existante + ligne draft)
- Colonne CJM ACHAT dans la table
- Pills delta (+X.X€ / -X.X€)
- Marge % dans la colonne et dans le KPI récap
- TJM moyen dans le KPI récap

---

## Spec 2 — Calculs marge & CA sur le renouvellement actif

### Contexte

Quand une mission est renouvelée, les calculs de marge et de CA dans le pipe/dashboard doivent utiliser les conditions financières de la **période active**, pas la période initiale.

### Règle

> La période active est celle dont `debut <= TODAY <= fin`. S'il n'y a pas de période active (ex : mission terminée ou pas encore démarrée), prendre la période avec le `debut` le plus récent.

### Logique applicative

```js
const getActivePeriod = (periods) => {
  const today = new Date().toISOString().split('T')[0];
  return (
    periods.find(p => p.debut <= today && p.fin >= today) ||
    [...periods].sort((a, b) => b.debut.localeCompare(a.debut))[0] ||
    null
  );
};
```

### Champs à synchroniser sur la mission parente

À chaque fois qu'une période est ajoutée ou modifiée, recalculer et mettre à jour la mission parente :

```js
const syncMissionFromPeriods = async (missionId, periods) => {
  const active = getActivePeriod(periods);
  if (!active) return;

  await sb.from('missions').update({
    tjm_vente:      active.tjm_vente,
    cjm_consultant: active.cjm_consultant,
    date_fin:       [...periods].sort((a, b) =>
                      b.fin.localeCompare(a.fin))[0]?.fin,   // fin = dernière période
  }).eq('id', missionId);
};
```

**Note :** `date_debut` de la mission reste celle de la première période (ne jamais l'écraser).

### Impact sur les calculs existants

| Calcul | Avant fix | Après fix |
|---|---|---|
| Marge mission dans le pipe | `tjm_vente` initial | `tjm_vente` de la période active |
| CA estimé mission | `tjm_vente` initial | `tjm_vente` de la période active |
| Badge GESTIONNAIRE (exploits) | inchangé | inchangé (basé sur COUNT, pas TJM) |
| Badge GOLDMAKER (CA YTD) | valeur figée | mis à jour avec TJM actif |
| Badge RENTIER (marge) | valeur figée | mis à jour avec marge active |

---

## Spec 3 — Mise à jour automatique au changement de champs

### Comportement attendu

Quand un commercial modifie un champ dans une période existante (N° commande, TJM, CJM), la mission parente se met à jour **automatiquement si la période modifiée est active à la date de modification**.

### Règle de déclenchement

```
SI période modifiée = période active à today
ALORS → sync immédiate sur missions (tjm_vente, cjm_consultant)
SINON → pas de sync (modification d'historique, ne pas affecter le présent)
```

### Implémentation

```js
const updatePeriod = async (missionId, periodId, changes, allPeriods) => {
  // 1. Mettre à jour la période
  const { data: updated } = await sb
    .from('mission_periods')
    .update(changes)
    .eq('id', periodId)
    .select()
    .single();

  // 2. Recalculer les périodes avec la version mise à jour
  const newPeriods = allPeriods.map(p => p.id === periodId ? { ...p, ...changes } : p);

  // 3. Sync mission parente uniquement si la période modifiée est la période active
  const active = getActivePeriod(newPeriods);
  if (active?.id === periodId) {
    await syncMissionFromPeriods(missionId, newPeriods);
  }

  // 4. Log si TJM ou CJM changé
  const tjmChanged = changes.tjm_vente !== undefined;
  const cjmChanged = changes.cjm_consultant !== undefined;
  if (tjmChanged || cjmChanged) {
    await sb.from('historique_actions').insert({
      contact_id:  mission.contact_id,
      type:        'modification_conditions_mission',
      description: `Conditions mises à jour — période ${updated.label}${
        tjmChanged ? ` · TJM → ${Number(changes.tjm_vente).toFixed(1)}€` : ''
      }${cjmChanged ? ` · CJM → ${Number(changes.cjm_consultant).toFixed(1)}€` : ''}`,
      auteur: activeProfile.nom,
    });
  }

  return updated;
};
```

---

## Acceptance criteria

### Bug décimales
- [ ] TJM, CJM, deltas et marge s'affichent avec **exactement 1 décimale** partout dans la section Périodes
- [ ] Plus de flottant non arrondi type `+7.90999999999`
- [ ] Les KPIs récap (TJM moyen, marge moyenne) respectent aussi la règle 1 décimale

### Sync marge & CA
- [ ] Après ajout d'un renouvellement, `tjm_vente` et `cjm_consultant` de la mission = valeurs de la période active
- [ ] Le pipe affiche le TJM du renouvellement, pas de la période initiale
- [ ] GOLDMAKER et RENTIER recalculent avec les nouvelles valeurs après sync

### Mise à jour automatique au changement
- [ ] Modifier TJM/CJM d'une période active → mission parente mise à jour immédiatement
- [ ] Modifier TJM/CJM d'une période passée → mission parente **non** mise à jour
- [ ] Chaque modification de TJM ou CJM est loggée dans `historique_actions`
- [ ] Modifier le N° de commande ne déclenche pas de sync sur la mission parente
