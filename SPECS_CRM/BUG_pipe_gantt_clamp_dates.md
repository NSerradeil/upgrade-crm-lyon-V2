# BUG — Pipe : barre Gantt mal positionnée quand mission hors année courante

**Fichier** : `supabase/CRM_Live.html` — composant Pipe / tableau missions (vue calendrier/Gantt)
**Date** : 26/03/2026
**Priorité** : P1

---

## Symptôme

Dans le tableau Pipe, les barres colorées représentant la durée d'une mission sont mal positionnées quand :

1. **La mission a démarré AVANT l'année courante** (ex : démarrage oct 2025, on est en 2026)
   → La barre commence en octobre **2026** au lieu de partir de **janvier 2026** (début d'année)

2. **La mission se termine APRÈS l'année courante** (ex : fin mars 2027, on est en 2026)
   → La barre devrait aller jusqu'en **décembre 2026** (fin d'année), pas au-delà

## Cause racine

Le calcul de position/largeur de la barre Gantt utilise directement `month(date_debut)` et `month(date_fin)` sans clamp sur l'année courante. Si la date de début est en 2025, `month = 10` → la barre commence à la colonne octobre 2026 (décalée d'une année).

---

## Règle de clamp à appliquer

```js
var CURRENT_YEAR = new Date().getFullYear(); // 2026

// Clamp start : si démarrage avant Jan de l'année courante → ramener à Jan (mois 1)
var startMonth = date_debut
  ? (new Date(date_debut).getFullYear() < CURRENT_YEAR
      ? 1
      : new Date(date_debut).getMonth() + 1)  // getMonth() = 0-indexed
  : null;

// Clamp end : si fin après Déc de l'année courante → ramener à Déc (mois 12)
var endMonth = date_fin
  ? (new Date(date_fin).getFullYear() > CURRENT_YEAR
      ? 12
      : new Date(date_fin).getMonth() + 1)
  : null;

// Si la mission est entièrement hors année courante (finie avant Jan ou commence après Déc)
// → ne pas afficher de barre (ou afficher grisé)
var isBeforeYear = date_fin && new Date(date_fin).getFullYear() < CURRENT_YEAR;
var isAfterYear  = date_debut && new Date(date_debut).getFullYear() > CURRENT_YEAR;
if (isBeforeYear || isAfterYear) {
  // barre invisible ou style "hors période"
}
```

---

## Cas concrets

| Mission | date_debut | date_fin | Avant fix | Après fix |
|---------|-----------|---------|-----------|-----------|
| Kristina JOVOVIC | oct 2025 | ? | barre commence oct 2026 ❌ | barre commence jan 2026 ✅ |
| Mission fin mars 2027 | jan 2026 | mars 2027 | barre dépasse déc 2026 ❌ | barre s'arrête déc 2026 ✅ |
| Mission terminée en 2025 | mai 2025 | sept 2025 | barre visible ❌ | pas de barre (hors année) ✅ |
| Mission normale | mars 2026 | sept 2026 | ✅ | ✅ (inchangé) |

---

## Localisation dans le code

Chercher le calcul qui transforme `date_debut` / `date_fin` en position/largeur de cellule dans la grille mensuelle. Mots-clés probables : `colStart`, `colSpan`, `gridColumn`, `monthStart`, `monthEnd`, `startCol`, `span`.

Exemple de pattern à trouver et corriger :
```js
// ❌ Avant
var col = new Date(mission.date_debut).getMonth() + 1; // retourne 10 pour oct 2025

// ✅ Après (avec clamp)
var rawYear = new Date(mission.date_debut).getFullYear();
var col = rawYear < CURRENT_YEAR ? 1 : new Date(mission.date_debut).getMonth() + 1;
```
