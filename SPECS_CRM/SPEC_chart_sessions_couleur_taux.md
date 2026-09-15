# SPEC — Couleur du taux % dans le chart Historique Sessions
**CRM Upgrade Lyon V2** · Fix cosmétique
**Date :** 24/03/2026

---

## Problème

Dans la card KPI Sessions > HISTORIQUE SESSIONS, le taux "5% intéressés" affiché au-dessus de chaque barre mensuelle est en **rouge (#FF3D2E)**.

Le rouge est la couleur de "Pas intéressés" — l'afficher sur le taux d'intéressés est sémantiquement incorrect et contre-intuitif.

## Fix

Le taux % au-dessus de la barre doit utiliser la **couleur de la donnée qu'il représente** :

| Donnée affichée | Couleur actuelle | Couleur cible |
|---|---|---|
| `X% intéressés` | `#FF3D2E` ❌ | `#007A10` ✅ (vert accessible — cf. SPEC_RECETTE) |
| `X% injoignables` | à vérifier | `#888` (gris neutre) |

> ⚠️ Utiliser `#007A10` (et non `#00C218`) pour respecter le ratio WCAG AA 4.5:1 sur fond blanc — documenté dans `SPEC_RECETTE_PROSPECTION.md` §WCAG-02.

## Localisation dans le code

Chercher dans le composant `CardSessions` / `renderHistoriqueSessions` la ligne qui affiche le pourcentage au-dessus de la barre. Le style `color` est probablement calé sur `C.red` ou `TAB_COLORS.prospection`.

```js
// Avant
color: C.red   // ou '#FF3D2E'

// Après
color: '#007A10'   // vert accessible pour texte sur blanc
```

## Acceptance criteria
- [ ] Le "X% intéressés" s'affiche en vert foncé `#007A10` au-dessus de la barre
- [ ] La légende "■ Intéressés" reste en `#00C218` (carré décoratif, pas du texte — WCAG UI component, seuil 3:1 OK)
- [ ] Aucune autre couleur du chart n'est modifiée
