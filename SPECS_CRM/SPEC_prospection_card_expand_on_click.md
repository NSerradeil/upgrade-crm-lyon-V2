# SPEC — ProspectionContactCard : ouverture au clic + déployée par défaut en Focus

**Fichier** : `supabase/CRM_Live.html` — composant `ProspectionContactCard`
**Date** : 26/03/2026
**Priorité** : P1

---

## Comportement actuel

La carte se déploie (affiche détails : téléphone, email, notes, relance) uniquement quand on clique sur un bouton de statut (Appelé, Intéressé, Pas joignable, Pas intéressé). Un clic ailleurs sur la carte ne fait rien.

## Comportement cible

### 1. Clic n'importe où sur la carte → déploie/réduit

- Cliquer sur la zone nom/société de la carte → toggle `expanded`
- Quand `expanded = true` sans statut sélectionné → carte ouverte en style **neutre/blanc** (pas de couleur de fond)
- Quand `expanded = true` avec statut → carte ouverte avec la couleur du statut (comportement inchangé)
- Clic sur un statut → sélectionne le statut ET ouvre la carte (si pas déjà ouverte)

### 2. Vue Focus → cartes déployées par défaut

En mode Vue Focus (`session.isFocus === true` ou prop `focusMode`), toutes les cartes sont initialisées avec `expanded = true`.

---

## Implémentation

### State `expanded` dans `ProspectionContactCard`

```js
// Ajouter prop optionnelle defaultExpanded pour le mode Focus
function ProspectionContactCard({ sc, idx, updateItem, defaultExpanded }) {
  var [expanded, setExpanded] = React.useState(defaultExpanded || sc.status !== 'none');
  // sc.status !== 'none' : si le contact a déjà un statut → déployé par défaut
```

### Zone cliquable sur le header de carte

Entourer la zone nom/société d'un handler `onClick` qui toggle `expanded` :

```jsx
{/* Header cliquable — NE PAS mettre onClick sur toute la carte pour éviter les conflits avec les boutons internes */}
<div
  onClick={function(e) {
    // Ne pas toggle si le clic vient d'un bouton (statut, checkbox, input)
    if (e.target.tagName === 'BUTTON' || e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
    setExpanded(function(v) { return !v; });
  }}
  style={{ cursor: 'pointer', userSelect: 'none' }}
>
  <span style={{fontWeight: 800}}>{sc.prenom} {sc.nom}</span>
  <span style={{color: '#666', fontSize: 12}}> {sc.groupe}</span>
  {/* Icône chevron pour indiquer l'état collapsed/expanded */}
  <span style={{float: 'right', fontSize: 10, color: '#999', marginTop: 2}}>
    {expanded ? '▲' : '▼'}
  </span>
</div>
```

### Clic sur statut → force expanded = true

```js
// Dans le handler des boutons de statut
onClick={function() {
  updateItem(idx, { status: sc.status === key ? 'none' : key });
  setExpanded(true); // ouvrir la carte si ce n'est pas déjà le cas
}}
```

### Style de la carte ouverte sans statut (neutre/blanc)

```js
var cardBg = sc.status === 'none'
  ? (expanded ? '#FFFFFF' : 'transparent')   // blanc quand ouvert, transparent quand fermé
  : STATUS_COLORS[sc.status];                 // couleur du statut sinon (inchangé)

var cardBorder = sc.status === 'none' && expanded
  ? '2px solid #E4E4E6'   // bordure légère neutre
  : '2px solid ' + STATUS_COLORS[sc.status]; // bordure colorée selon statut (inchangé)
```

### Mode Focus : `defaultExpanded = true`

Dans le composant parent (`ProspectionActive`), passer `defaultExpanded` selon le mode :

```jsx
{items.map(function(sc, idx) {
  return (
    <ProspectionContactCard
      key={sc.id}
      sc={sc}
      idx={idx}
      updateItem={updateItem}
      defaultExpanded={session.isFocus === true}  // déployé par défaut en Focus
    />
  );
})}
```

---

## Résumé des changements

| Action | Avant | Après |
|--------|-------|-------|
| Clic sur nom/société | Rien | Toggle expanded |
| Clic sur statut | Ouvre + colorise | Ouvre (si fermé) + colorise |
| Carte sans statut, ouverte | Impossible | Fond blanc, bordure grise |
| Mode Focus, à l'ouverture | Cartes fermées | Cartes toutes déployées |
| Contact déjà appelé, rechargement | Déployé ✅ | Déployé ✅ (inchangé) |
