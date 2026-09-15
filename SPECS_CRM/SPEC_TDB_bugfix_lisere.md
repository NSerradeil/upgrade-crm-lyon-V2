# SPEC — Bugfix TDB : liseré des cartes KPI + bordure colorée du chart

**Fichier cible :** `supabase/CRM_Live.html`
**Composant cible :** `TabTDB`
**Deploy :** `bash supabase/deploy_staging.sh` → **staging uniquement, jamais main**

---

## Contexte

Deux bugs visuels constatés après intégration de la feature multi-KPI interactive :

1. **Bug #1 — Liseré de la carte disparaît au clic** : la bordure gauche colorée (`borderLeft`) s'efface quand une dalle passe en état actif (fond midnight).
2. **Bug #2 — Conteneur du chart sans couleur** : le bloc chart en dessous des dalles garde une bordure `#1C1F35` uniforme. Il devrait avoir un accent coloré (bordure haute ou gauche) reflétant la dalle active.

---

## Bug #1 — Liseré de carte écrasé par la propriété `border` shorthand

### Cause racine

En React inline styles, si `border` est appliqué **après** `borderLeft` dans l'objet de style, la propriété shorthand `border` réécrit les 4 côtés et **écrase** `borderLeft`. Résultat : le liseré coloré disparaît.

```js
// ❌ MAUVAIS — border shorthand écrase borderLeft
style={{
  borderLeft: `5px solid ${c.color}`,   // ← défini en premier
  border: `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`, // ← écrase tout
}}

// ❌ MAUVAIS également — même problème avec Tailwind si une classe border-* est appliquée
```

### Fix — Décomposer les propriétés de bordure individuellement

```js
// ✅ CORRECT — propriétés individuelles, pas de shorthand
style={{
  borderTop:    `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
  borderRight:  `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
  borderBottom: `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
  borderLeft:   `5px solid ${c.color}`,  // ← toujours présent, actif ou pas
}}
```

**Le liseré coloré (`borderLeft: 5px solid ${c.color}`) doit être visible dans les deux états** : inactif (fond blanc) ET actif (fond midnight `#1C1F35`). C'est l'indicateur visuel permanent de la nature du KPI.

### Rendu attendu carte active

| Propriété | Valeur |
|---|---|
| `background` | `#1C1F35` |
| `borderTop/Right/Bottom` | `2px solid #1C1F35` |
| `borderLeft` | `5px solid ${c.color}` ← **toujours présent** |
| `boxShadow` | `4px 4px 0 ${c.color}` |
| `transform` | `translate(-2px, -2px)` |
| valeur principale | couleur `#ffffff` |
| label KPI | couleur `${c.color}` |

### Rendu attendu carte inactive

| Propriété | Valeur |
|---|---|
| `background` | `#ffffff` |
| `borderTop/Right/Bottom` | `2px solid #E4E4E6` |
| `borderLeft` | `5px solid ${c.color}` ← **toujours présent** |
| `boxShadow` | `none` |
| `transform` | `none` |
| valeur principale | couleur `#1C1F35` |
| label KPI | couleur `#999` |

---

## Bug #2 — Conteneur du chart sans accent coloré

### Comportement actuel

Le conteneur du chart a une bordure uniforme `2px solid #1C1F35` quelle que soit la dalle sélectionnée.

### Comportement attendu

Le conteneur du chart doit avoir une **bordure gauche épaisse de la couleur de la dalle active**, identique au principe des cartes KPI.

```js
// Récupérer la couleur de la carte active
const activeColor = CARDS.find(c => c.id === activeChart)?.color ?? '#1C1F35';
```

```jsx
// ✅ Conteneur chart avec accent coloré
<div style={{
  background: '#fff',
  borderTop:    '2px solid #1C1F35',
  borderRight:  '2px solid #1C1F35',
  borderBottom: '2px solid #1C1F35',
  borderLeft:   `5px solid ${activeColor}`,  // ← couleur dynamique
  padding: '20px 24px 24px',
  borderRadius: 0,
}}>
  {activeChart === 'ca'       && <ChartCA    ... />}
  {activeChart === 'marge'    && <ChartMarge ... />}
  {activeChart === 'inter'    && <ChartInter ... />}
  {activeChart === 'missions' && <ChartMissions ... />}
</div>
```

### Correspondance couleurs actives

| `activeChart` | Couleur du liseré |
|---|---|
| `'missions'` | `#00C218` (vert) |
| `'inter'` | `#FFE500` (jaune) ou `#ccc` si aucun intercontrat |
| `'ca'` | `#4A7FE5` (bleu) |
| `'marge'` | `#FF66FF` (pink) |

> Utiliser `CARDS.find(c => c.id === activeChart)?.color` plutôt qu'un switch hardcodé, pour que ça reste synchronisé avec la config `CARDS`.

---

## Résumé des changements

### 1. Dans le rendu des cartes KPI — remplacer `border` shorthand

```jsx
// Avant (bugué)
style={{
  border: `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
  borderLeft: `5px solid ${c.color}`,
  ...
}}

// Après (corrigé)
style={{
  borderTop:    `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
  borderRight:  `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
  borderBottom: `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
  borderLeft:   `5px solid ${c.color}`,
  ...
}}
```

### 2. Ajouter `activeColor` avant le return du composant

```js
const activeColor = CARDS.find(c => c.id === activeChart)?.color ?? '#E4E4E6';
```

### 3. Dans le conteneur chart — ajouter le liseré coloré dynamique

```jsx
// Avant
style={{ border: '2px solid #1C1F35', ... }}

// Après
style={{
  borderTop:    '2px solid #1C1F35',
  borderRight:  '2px solid #1C1F35',
  borderBottom: '2px solid #1C1F35',
  borderLeft:   `5px solid ${activeColor}`,
  ...
}}
```

---

## Critères QA

| # | Test | Attendu |
|---|---|---|
| 1 | Charge initiale (activeChart = 'ca') | Dalle CA en midnight, liseré bleu `#4A7FE5` visible sur son côté gauche ET sur le conteneur chart |
| 2 | Clic sur dalle Missions | Dalle Missions en midnight + liseré vert, 3 autres dalles blanches avec leur liseré coloré visible, conteneur chart avec liseré vert |
| 3 | Clic sur dalle Intercontrat | Liseré jaune sur la dalle ET sur le conteneur chart |
| 4 | Clic sur dalle Marge | Liseré pink `#FF66FF` sur la dalle ET sur le conteneur chart |
| 5 | Dalles inactives | Liseré coloré de chaque dalle toujours visible même quand elle n'est pas sélectionnée |
| 6 | Deploy | `bash supabase/deploy_staging.sh` uniquement |
