# SPEC — Bugfix TDB : KPI cards responsive mobile (PWA)

**Fichier cible :** `supabase/CRM_Live.html`
**Composant cible :** `TabTDB` — grille des 4 dalles KPI
**Deploy :** `bash supabase/deploy_staging.sh` → **staging uniquement, jamais main**

---

## Problème constaté

Sur mobile (PWA), la grille des 4 dalles KPI déborde horizontalement hors de l'écran.
Cause : `gridTemplateColumns: 'repeat(4, 1fr)'` est fixe et ne s'adapte pas à la largeur de l'écran.

---

## Solution — `auto-fit` + `minmax`

Remplacer la valeur fixe `repeat(4, 1fr)` par une valeur CSS fluide :

```js
// Avant (fixe, déborde sur mobile)
gridTemplateColumns: 'repeat(4, 1fr)'

// Après (fluide, wrapping automatique)
gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))'
```

**Comportement :**
- ≥ 640px (desktop/tablette) → 4 colonnes côte à côte, identique à aujourd'hui
- < 640px (mobile PWA) → wrapping automatique en 2×2
- < 320px (très petit) → 1 colonne si nécessaire

Aucun JS ni listener resize requis — le CSS `auto-fit` + `minmax` gère tout nativement.

---

## Ajustements complémentaires pour mobile

### Réduction du padding interne des cartes sur petit écran

Ajouter dans la balise `<style>` existante du fichier (ou en créer une si absente) :

```css
@media (max-width: 480px) {
  .kpi-card {
    padding: 12px 10px !important;
  }
  .kpi-value {
    font-size: 22px !important;
  }
}
```

Et ajouter les classes correspondantes sur les éléments React :

```jsx
// Sur la div carte
className="kpi-card"

// Sur le div de la valeur principale
className="kpi-value"
```

> **Alternative sans classes** : si le projet évite les classes CSS, utiliser un hook `useWindowWidth` (voir ci-dessous) pour adapter le padding en JS.

### Hook optionnel `useWindowWidth` (si approche 100% inline styles préférée)

```js
function useWindowWidth() {
  const [w, setW] = React.useState(window.innerWidth);
  React.useEffect(() => {
    const handler = () => setW(window.innerWidth);
    window.addEventListener('resize', handler);
    return () => window.removeEventListener('resize', handler);
  }, []);
  return w;
}
```

```jsx
// Dans TabTDB
const isMobile = useWindowWidth() < 480;

// Sur la grille
gridTemplateColumns: isMobile ? 'repeat(2, 1fr)' : 'repeat(4, 1fr)'

// Sur chaque carte
padding: isMobile ? '12px 10px' : '16px 14px'

// Sur la valeur principale
fontSize: isMobile ? 22 : 30
```

---

## Changement minimal recommandé (une seule ligne)

Si on veut le changement le moins risqué possible, **une seule modification suffit** et règle 90% du problème :

```js
// Grille KPI — remplacer cette ligne uniquement
gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))'
```

Le `minmax(150px, 1fr)` garantit :
- Chaque carte fait au minimum 150px de large
- Sur un écran de 360px (mobile standard) : 2 colonnes × 150px = 300px < 360px ✓
- Sur desktop 1100px : 4 colonnes × ~260px ✓

---

## Critères QA

| # | Test | Attendu |
|---|---|---|
| 1 | Desktop 1100px | 4 dalles sur une ligne, identique à aujourd'hui |
| 2 | Tablette 768px | 4 dalles sur une ligne ou 2×2 selon la place disponible |
| 3 | Mobile 390px (iPhone) | 2×2 propre, aucun débordement horizontal |
| 4 | Mobile 360px (Android) | 2×2 propre, aucun débordement horizontal |
| 5 | Scroll horizontal | Aucun scroll horizontal sur la page en mode mobile |
| 6 | Clic sur dalle (mobile) | Toujours fonctionnel, chart se met à jour sous les 4 dalles |
| 7 | Liseré et shadow | Shadow `4px 4px 0 ${c.color}` reste visible sur mobile (ne pas masquer avec overflow:hidden) |
| 8 | Deploy | `bash supabase/deploy_staging.sh` — jamais main |
