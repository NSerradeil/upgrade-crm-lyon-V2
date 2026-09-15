# SPEC — Bugfix TDB : style de la carte KPI active

**Fichier cible :** `supabase/CRM_Live.html`
**Composant cible :** `TabTDB` — rendu des dalles KPI
**Deploy :** `bash supabase/deploy_staging.sh` → **staging uniquement, jamais main**

---

## Contexte

Deux ajustements visuels sur les dalles KPI suite au fix précédent :

1. **Bordures de la carte active trop sombres** : quand une dalle est sélectionnée, les 3 bordures (top/right/bottom) sont en `#1C1F35` (midnight). Elles doivent rester grises (`#E4E4E6`), comme les cartes inactives — seul le liseré gauche est coloré.
2. **Style carte active** : doit ressembler au bouton "Nouvelle mission" — fond midnight + ombre offset colorée. Actuellement la carte active a une bordure colorée pleine autour (trop chargé). Le modèle est : fond noir, shadow brutalist `4px 4px 0 ${c.color}`, pas de bordure colorée sur les 3 côtés.

---

## Référence visuelle — bouton "Nouvelle mission"

Le bouton `+ Nouvelle mission` est le modèle exact pour l'état actif d'une dalle :
- Fond `#1C1F35`
- Ombre `4px 4px 0 #FF3D2E` (décalée, pas de blur)
- Bordures grises ou transparentes, **pas** colorées sur tout le pourtour
- `transform: translate(-2px, -2px)` pour simuler le décalage de l'ombre

---

## Fix — Style des dalles KPI

### Avant (bugué)

```js
// État actif : bordures midnight partout + éventuellement tout vert/bleu/etc.
borderTop:    `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
borderRight:  `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
borderBottom: `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
borderLeft:   `5px solid ${c.color}`,
```

### Après (corrigé)

```js
// État actif ET inactif : top/right/bottom toujours gris
// Seul borderLeft prend la couleur du KPI
borderTop:    '2px solid #E4E4E6',   // ← gris fixe, peu importe l'état
borderRight:  '2px solid #E4E4E6',   // ← gris fixe
borderBottom: '2px solid #E4E4E6',   // ← gris fixe
borderLeft:   `5px solid ${c.color}`, // ← couleur du KPI, toujours visible
```

---

## Récapitulatif complet du style par état

### Carte inactive

```js
{
  background:   '#ffffff',
  borderTop:    '2px solid #E4E4E6',
  borderRight:  '2px solid #E4E4E6',
  borderBottom: '2px solid #E4E4E6',
  borderLeft:   `5px solid ${c.color}`,
  boxShadow:    'none',
  transform:    'none',
  cursor:       'pointer',
  transition:   'all 120ms ease',
  padding:      '16px 14px',
  position:     'relative',
  borderRadius: 0,
}
```

### Carte active (modèle "bouton Nouvelle mission")

```js
{
  background:   '#1C1F35',             // fond midnight
  borderTop:    '2px solid #E4E4E6',  // gris — pas midnight, pas coloré
  borderRight:  '2px solid #E4E4E6',  // gris
  borderBottom: '2px solid #E4E4E6',  // gris
  borderLeft:   `5px solid ${c.color}`, // liseré KPI toujours présent
  boxShadow:    `4px 4px 0 ${c.color}`, // ombre offset colorée — effet brutalist
  transform:    'translate(-2px, -2px)', // décalage pour simuler le relief
  cursor:       'pointer',
  transition:   'all 120ms ease',
  padding:      '16px 14px',
  position:     'relative',
  borderRadius: 0,
}
```

### Contenu de la carte selon état

| Élément | Inactif | Actif |
|---|---|---|
| Valeur principale (chiffre) | `color: '#1C1F35'` | `color: '#ffffff'` |
| Label KPI (ex: CA YTD) | `color: '#999'` | `color: ${c.color}` |
| Sous-label | `color: '#ccc'` | `color: '#777'` |
| Badge alerte (si présent) | inchangé | inchangé |

---

## Critères QA

| # | Test | Attendu |
|---|---|---|
| 1 | Carte inactive au chargement | Fond blanc, liseré gauche coloré, 3 autres bordures gris `#E4E4E6` |
| 2 | Carte active au clic | Fond midnight, liseré gauche coloré, 3 autres bordures gris, ombre offset colorée, valeur en blanc |
| 3 | Carte active — shadow EN MISSION | `boxShadow: '4px 4px 0 #00C218'` |
| 4 | Carte active — shadow INTERCONTRAT | `boxShadow: '4px 4px 0 #FFE500'` |
| 5 | Carte active — shadow CA YTD | `boxShadow: '4px 4px 0 #4A7FE5'` |
| 6 | Carte active — shadow MARGE YTD | `boxShadow: '4px 4px 0 #FF66FF'` |
| 7 | Aucun border-radius | Toutes les cartes restent à angles droits |
| 8 | Deploy | `bash supabase/deploy_staging.sh` — jamais main |
