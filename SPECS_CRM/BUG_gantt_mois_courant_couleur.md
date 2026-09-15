# BUG — Couleur du mois courant dans le Gantt Pipe
**CRM Upgrade Lyon V2** · Fix cosmétique
**Date :** 26/03/2026

---

## Problème

Dans le Gantt du module Pipe, la colonne correspondant au **mois courant** est mise en évidence avec la couleur `midnight` (`#1C1F35`). Cette couleur est trop violente visuellement — elle écrase la lisibilité des barres de mission et donne un aspect agressif au tableau.

## Fix

Remplacer le fond midnight par une couleur discrète cohérente avec la charte.

| Élément | Avant | Après |
|---|---|---|
| Fond colonne mois courant | `#1C1F35` (midnight) | `#F0F0F2` (gris très clair / snow) |
| Bordure basse colonne mois courant | aucune | `2px solid #CCCCCC` (gris moyen, indicateur subtil) |
| Texte du header mois courant | blanc sur midnight | `#1C1F35` sur `#F0F0F2` (contraste WCAG AA ok) |

> Alternative acceptable si `#F0F0F2` est trop proche du blanc : `#E8E8EC` ou un léger fond `rgba(74,127,229,0.08)` (bleu très transparent).

## Localisation dans le code

Chercher dans le composant Gantt / `renderGantt` la logique qui détecte le mois courant :

```js
// Pattern probable
const isCurrentMonth = (month === currentMonth && year === currentYear);

// Style actuel
backgroundColor: isCurrentMonth ? C.midnight : 'transparent'

// Fix
backgroundColor: isCurrentMonth ? '#F0F0F2' : 'transparent',
borderBottom: isCurrentMonth ? '2px solid #CCCCCC' : 'none',
color: isCurrentMonth ? C.midnight : 'inherit'
```

## Acceptance criteria
- [ ] La colonne du mois courant a un fond `#F0F0F2` (ou équivalent discret)
- [ ] Le texte du header du mois courant reste lisible (ratio ≥ 4.5:1)
- [ ] Les barres de mission restent visibles sur ce fond clair
- [ ] Aucun autre mois n'est affecté
