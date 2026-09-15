# BUG — Badge "tâches en retard" affiche le total agence au lieu du perso
**CRM Upgrade Lyon V2** · Bug comportemental
**Date :** 26/03/2026

---

## Problème

Le badge "X tâches en retard" affiché dans le header du CRM (ou dans la section Tâches) montre **39 tâches** pour Nicolas alors qu'il n'en a que **9 en propre**.

### Cause racine

`tachesRetard` est calculé à partir de `vTaches` (vue admin = toutes les tâches de l'agence). En mode admin, `vTaches` contient les tâches de tous les responsables — le badge affiche donc un total agence plutôt que le total personnel.

## Fix

Le badge "tâches en retard" doit **toujours** afficher uniquement les tâches dont `responsable === activeProfile.nom`, indépendamment du mode admin.

```js
// Avant (approximatif)
const tachesRetard = vTaches.filter(t => t.statut !== 'done' && isPast(t.date_echeance));

// Après
const tachesRetard = taches  // utiliser taches (liste personnelle), pas vTaches
  .filter(t => t.statut !== 'done' && isPast(t.date_echeance));

// OU si vTaches est la seule source disponible :
const tachesRetard = vTaches
  .filter(t => t.responsable === activeProfile.nom && t.statut !== 'done' && isPast(t.date_echeance));
```

> `vTaches` reste utilisé pour les vues admin (liste complète agence), mais **jamais** pour le compteur personnel du header.

## Localisation dans le code

Chercher `tachesRetard` ou `retard` dans le composant header / dashboard. La correction doit être ciblée uniquement sur le calcul du badge, sans toucher aux vues listes existantes.

## Acceptance criteria
- [ ] Le badge affiche uniquement les tâches en retard de `activeProfile.nom`
- [ ] En mode admin, la vue liste complète des tâches agence n'est pas affectée
- [ ] Si Nicolas a 9 tâches en retard, le badge affiche "9" quel que soit le mode
