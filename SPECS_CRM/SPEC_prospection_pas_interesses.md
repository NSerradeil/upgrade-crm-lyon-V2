# SPEC — Card "Pas intéressés" + rename "Intéressant"
**CRM Upgrade Lyon V2** · Évolutions UX/sémantique (Points 2 et 3 CR Anne-Claire)
**Source :** Retour Anne-Claire Decker (commerciale Bordeaux) · 25/03/2026
**Auteur :** Nicolas Serradeil + Claude (PM + Lead UX)

---

## Besoins exprimés

> **Point 2 :** « Ajouter un onglet dédié aux prospects pour lesquels il n'a pas été possible d'obtenir de suite (refus, pas de réponse définitive, etc.). »

> **Point 3 :** « Changer le libellé "Intéressé" en "Intéressant" pour mieux refléter la nature du prospect (profil jugé pertinent, indépendamment de sa réponse immédiate). »

---

## Analyse

### Point 2 — "Onglet Pas intéressés"

Anne-Claire utilise "onglet" de manière informelle. Elle ne demande pas un 8e onglet dans la navigation principale — elle veut **retrouver facilement les contacts marqués "Pas intéressé"** d'une ou plusieurs sessions.

**Valeur produit :** les "Pas intéressés" sont une mine d'or commerciale :
- Contact refusant aujourd'hui → potentiellement reconsidérable dans 6 mois
- Constitue un vivier de "warm leads" à reprospector plus tard
- Évite de les reprospecter trop tôt (mauvaise impression)

**Implémentation proposée :** une 4e KPI card dans la vue détail de session, et une vue liste dans le dashboard Prospection.

### Point 3 — Rename "Intéressé" → "Intéressant"

Changement sémantique fondé :
- `interested` (statut interne) = le commercial juge ce contact pertinent / à suivre
- "Intéressé" suggère que le contact lui-même a manifesté son intérêt (passif)
- "Intéressant" = jugement du commercial → sémantique correcte

Impact : renommer tous les labels de l'UI, sans toucher au code métier ni à la valeur stockée (`status: 'interested'`).

---

## Modifications

### 1. Rename labels "Intéressé" → "Intéressant" (Points 3)

Tous les labels à changer dans `CRM_Live.html` :

| Emplacement | Valeur actuelle | Valeur cible |
|---|---|---|
| `LABELS` object (variable) | `'interested': 'Intéressé'` | `'interested': 'Intéressant'` |
| KPI card header (ProspectionDetailPanel) | `Intéressés` | `Intéressants` |
| KPI card header (CardSessions dashboard) | `Intéressés` | `Intéressants` |
| Badge statut sur contact dans session | `Intéressé` | `Intéressant` |
| Chip filter dans ProspectionDetailPanel | `Intéressés` | `Intéressants` |
| Tooltip / aria-label si présents | `Intéressé(s)` | `Intéressant(s)` |

> ⚠️ **Ne pas toucher à la valeur de la donnée** : `status: 'interested'`, `LABELS.interested`, etc. restent inchangés dans le code — seuls les strings affichés à l'utilisateur changent.

```js
// Avant
const LABELS = { interested: 'Intéressé', unreachable: 'Injoignable', ... };

// Après
const LABELS = { interested: 'Intéressant', unreachable: 'Injoignable', ... };
```

### 2. Card "Pas intéressants" dans ProspectionDetailPanel (Point 2)

Actuellement, le détail de session affiche 3 KPI cards :
```
[X Intéressants] [X Injoignables] [X Relances]
```

**Ajouter une 4e card :**
```
[X Intéressants] [X Pas intéressants] [X Injoignables] [X Relances]
```

La card "Pas intéressants" :
- **Valeur :** nombre de contacts avec `statut: 'not_interested'` dans `session_prospection_contacts`
- **Cliquable :** ouvre un panel/liste de ces contacts (même pattern que "Intéressants")
- **Couleur :** `#888` (gris neutre — ni rouge ni vert, statut terminal mais pas négatif)

```js
// Dans le ProspectionDetailPanel, section KPI cards
const nbPasInteressants = spcRows.filter(r => r.statut === 'not_interested').length;
// ... ou selon la valeur exacte stockée dans session_prospection_contacts.statut
```

> ⚠️ **À vérifier dans le code :** La valeur exacte stockée pour "Pas intéressé" dans `session_prospection_contacts.statut`. Chercher `LABELS` ou le statut correspondant au bouton "Pas intéressé" dans `ProspectionActive`.

### 3. Section "Pas intéressants" dans le dashboard Prospection

Dans le `CardSessions` (KPI dashboard, onglet Prospection) :

Ajouter dans la section HISTORIQUE SESSIONS (chart) une visualisation des "Pas intéressants" en **gris** (actuellement seuls les intéressants et injoignables sont représentés).

Ou, alternative plus légère : une section pliable "Contacts à reprospector" dans le détail d'une session — liste des contacts `not_interested` des 3 derniers mois, filtrables par agence.

**Recommandation V1 :** juste la 4e KPI card dans ProspectionDetailPanel. La section dashboard est une évolution V2.

---

## Acceptance criteria

**Rename Intéressant (Point 3) :**
- [ ] Tous les labels affichés "Intéressé(s)" sont remplacés par "Intéressant(s)" dans l'UI
- [ ] La valeur `'interested'` dans le code/base n'est pas modifiée
- [ ] Le chart `CardSessions` affiche "X% intéressants" (et non "intéressés")

**Card Pas intéressants (Point 2) :**
- [ ] Le `ProspectionDetailPanel` affiche une 4e KPI card "Pas intéressants" (compte + couleur grise)
- [ ] La card est cliquable et filtre la liste de contacts sur `statut = 'not_interested'`
- [ ] La card s'affiche à 0 si aucun contact n'a ce statut (pas masquée)
- [ ] Aucune régression sur les 3 cards existantes

---

## Localisation dans le code

| Élément | Chercher |
|---|---|
| `LABELS` object | `interested:` dans `CRM_Live.html` |
| ProspectionDetailPanel | `function ProspectionDetailPanel` |
| CardSessions / chart | `function CardSessions` ou `renderHistoriqueSessions` |
| Statut "Pas intéressé" stocké | Chercher `not_interested` ou le bouton correspondant dans `ProspectionActive` |
