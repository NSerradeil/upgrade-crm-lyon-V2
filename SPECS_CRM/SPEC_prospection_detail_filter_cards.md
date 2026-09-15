# SPEC — ProspectionDetailPanel : mini-cards filtrantes

**Fichier** : `supabase/CRM_Live.html` — composant `ProspectionDetailPanel`
**Date** : 25/03/2026
**Priorité** : P1

---

## Comportement actuel

Les 4 mini-cards (Appelés, Intéressants, Relances, Pas intéressés) sont purement informatives — elles affichent un chiffre mais ne déclenchent aucune action.

## Comportement cible

Chaque card est un **filtre cliquable** sur la liste "CONTACTS TRAITÉS" en dessous.

- **Par défaut** : card "Appelés" sélectionnée → affiche tous les contacts traités
- **Clic sur une card** : sélectionne cette card, filtre la liste, désélectionne l'autre
- **Reclic sur la card déjà active** : revient à "Appelés" (tout afficher)

### Mapping card → filtre

| Card | Filtre sur `rows` |
|------|-------------------|
| Appelés (défaut) | Tous — `rows` sans filtre |
| Intéressants | `r.statut === 'interested'` |
| Relances | `r.want_relance === true` (et `r.relance_date != null`) |
| Pas intéressés | `r.statut === 'not_interested'` |

> `rows` = tableau des `session_prospection_contacts` déjà chargé dans le composant.

---

## Implémentation

### 1. Ajouter un state `activeFilter`

Dans `ProspectionDetailPanel`, ajouter :

```js
const [activeFilter, setActiveFilter] = React.useState('all');
// valeurs possibles : 'all' | 'interested' | 'relance' | 'not_interested'
```

### 2. Dériver `filteredRows` depuis `rows` et `activeFilter`

```js
var filteredRows = rows;
if (activeFilter === 'interested')    filteredRows = rows.filter(function(r){ return r.statut === 'interested'; });
if (activeFilter === 'relance')       filteredRows = rows.filter(function(r){ return r.want_relance && r.relance_date; });
if (activeFilter === 'not_interested') filteredRows = rows.filter(function(r){ return r.statut === 'not_interested'; });
```

### 3. Remplacer les cards statiques par des cards cliquables

Remplacer le `.map()` des cards par :

```js
var filterCards = [
  { id: 'all',           v: session.nb_contacts||0,   l: 'Appelés',       c: '#1C1F35' },
  { id: 'interested',    v: session.nb_interesses||0, l: 'Intéressants',  c: '#007A10' },
  { id: 'relance',       v: session.nb_relances||0,   l: 'Relances',      c: '#B8A000' },
  { id: 'not_interested',v: rows.filter(function(r){return r.statut==='not_interested';}).length, l: 'Pas intéressés', c: '#FF3D2E' },
];

{filterCards.map(function(s) {
  var isActive = activeFilter === s.id;
  return (
    <div
      key={s.id}
      onClick={function(){ setActiveFilter(activeFilter === s.id && s.id !== 'all' ? 'all' : s.id); }}
      style={{
        padding: '10px',
        border: isActive ? '2px solid ' + s.c : '2px solid #E4E4E6',
        borderLeft: '4px solid ' + s.c,
        cursor: 'pointer',
        background: isActive ? s.c + '12' : 'transparent', // légère teinte de fond
        transition: 'all 0.15s ease',
        userSelect: 'none',
      }}
    >
      <div style={{ fontSize: 22, fontWeight: 900, color: s.c }}>{s.v}</div>
      <div style={{ fontSize: 10, fontWeight: 700, textTransform: 'uppercase', color: '#666', marginTop: 2 }}>{s.l}</div>
    </div>
  );
})}
```

### 4. Remplacer `rows.map(...)` par `filteredRows.map(...)` dans la liste

Dans le rendu "CONTACTS TRAITÉS", remplacer :
```js
{rows.map(function(r) { ... })}
```
par :
```js
{filteredRows.map(function(r) { ... })}
```

### 5. Afficher le nombre de résultats filtrés dans le header

Sous le titre "CONTACTS TRAITÉS", afficher dynamiquement :

```js
<div style={{fontSize:11, color:'#888', marginBottom:8}}>
  {filteredRows.length} contact{filteredRows.length > 1 ? 's' : ''}
  {activeFilter !== 'all' ? ' · ' + filterCards.find(function(c){return c.id===activeFilter;}).l : ''}
</div>
```

---

## Style de la card active

- **Border** : `2px solid [couleur de la card]` au lieu de `2px solid #E4E4E6`
- **Background** : `[couleur]12` (alpha 7% — léger fond teinté)
- **Pas de boxShadow ni de scale** — rester dans le style brutalist du CRM

---

## Comportement edge cases

- Si le filtre retourne **0 résultats** → afficher un état vide : `"Aucun contact dans cette catégorie"`
- Si `rows` n'est pas encore chargé → les cards sont cliquables mais `filteredRows = []` (idem à l'état actuel)
- Le filter reset à `'all'` à chaque ouverture du panel (géré par `useState('all')` déjà réinitialisé au montage)
