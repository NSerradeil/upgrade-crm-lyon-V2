# RECETTE UX/UI — Onglet Prospection
**CRM Upgrade Lyon V2** · Revue du 24/03/2026
**Testeur :** Claude (chapeau PM · Lead Design · Lead Tech · QA)
**URL :** https://nserradeil.github.io/upgrade-crm-lyon-V2/
**Méthode :** Session test créée (3 contacts : Loïc FESTAS, Sabrina VOISIN, Gwendoline CHANTELAT), parcours complet, session supprimée en fin de test.

---

## Synthèse des issues

| Priorité | Count | Thème |
|---|---|---|
| 🔴 P0 — Bloquant | 1 | Bouton inaccessible |
| 🟠 P1 — WCAG Critique | 4 | Contraste couleur (RGAA AA) |
| 🟡 P2 — Majeur | 5 | UX / comportement |
| 🔵 P3 — Mineur | 7 | Copy / accents |
| ⚪ P4 — Évolution | 7 | Amélioration produit |

---

## P0 — Bloquant

### BUG-01 · Bouton "LANCER LA SESSION" non cliquable à la souris

**Écran :** NewSession (formulaire de création)
**Symptôme :** Le clic sur le bouton "LANCER LA SESSION (N CONTACTS)" sélectionne le contact situé visuellement derrière le bouton au lieu de lancer la session. Le bouton est techniquement présent dans le DOM (`getBoundingClientRect().top: 731` dans une fenêtre 828px) mais son positionnement crée un décalage entre sa position CSS et sa position perçue à l'écran.

**Root cause probable :** Le bouton n'est pas `position: fixed` — il est statique au bas d'un conteneur scrollable. Le scaling entre les coordonnées CSS (1920px) et les pixels screenshot fait que les clics visuels atterrissent sur les lignes de contact juste au-dessus du bouton, cochant un contact supplémentaire.

**Impact :** La session ne peut pas être lancée sans passer par la console JavaScript. Bloquant pour tout utilisateur.

**Fix Claude Code :**
```js
// Dans le composant NewSession, rendre le bouton sticky
style={{
  position: 'sticky',
  bottom: 0,
  zIndex: 10,
  background: C.midnight,
  // Ajouter un padding vertical pour éviter la confusion avec les lignes
  margin: '0 -18px',
  padding: '12px 18px',
  borderTop: `2px solid ${C.blue}`,
}}
```

---

## P1 — WCAG Critique (RGAA AA)

> Seuils WCAG AA : 4.5:1 pour texte normal (< 18px), 3:1 pour grand texte (≥ 18px bold) et UI components.

### WCAG-01 · Jaune #FFE500 sur fond blanc — ratio 1.07:1 🔴🔴

**Occurrences :**
- Stat "0 relances" dans la barre de session active (11px)
- Mini-stat "0 RELANCES" dans le SessionDetailPanel / SidePanel (22px bold → seuil 3:1 mais 1.07 < 3)
- Label "RELANCES" sous la KPI card
- Bordure gauche jaune de la KPI card RELANCES (composant UI → seuil 3:1)

**Fix :** Remplacer le jaune `#FFE500` par un jaune foncé `#B8A000` (ratio ~4.6:1 sur blanc) pour les textes. Conserver `#FFE500` uniquement pour les accents décoratifs purs (bordures, points) sans texte dessus.

```js
// Dans les constantes de couleur
C.yellowText = '#B8A000';  // Textes et labels
C.yellow     = '#FFE500';  // Accents décoratifs uniquement
```

### WCAG-02 · Vert #00C218 sur fond blanc — ratio 1.67:1 🔴

**Occurrences :**
- Stat "0 intéressés" dans la barre de session active (11px)
- Mini-stat "1 INTERESSES" dans le SessionDetailPanel (22px bold → ratio 1.67 < 3:1)
- Badge "INTERESSE" (green border + green text) dans le SidePanel
- "1 intéressés" dans la ligne de session de la liste

**Fix :** Utiliser un vert foncé `#007A10` (ratio ~4.9:1 sur blanc) pour les textes verts.

```js
C.greenText = '#007A10';  // Textes et labels
C.green     = '#00C218';  // Accents décoratifs, fonds avec texte blanc dessus
```

### WCAG-03 · Violet #823DE8 sur Midnight #1C1F35 — ratio 2.97:1 🟠

**Occurrences :**
- Label "SESSIONS" de la KPI card active (11px sur fond midnight)
- Libellé mois en violet dans le chart historique Sessions (9px → aggravé)
- Taux % mensuel en violet dans le chart

**Fix :** Utiliser le blanc `#FFFFFF` sur midnight pour les labels de card active, quelle que soit la couleur de la card. La couleur de la card s'exprime uniquement via le `boxShadow` et la bordure gauche, pas via le texte.

```jsx
// Label card active : toujours blanc sur midnight, jamais la couleur de la card
color: active ? '#FFFFFF' : C.mid
```

### WCAG-04 · Bleu #4A7FE5 sur blanc — ratio 3.72:1 (FAIL texte < 18px) 🟠

**Occurrences :**
- Stat "1 appeles" dans la barre de session active (11px)
- Liens téléphone et email dans les cards contact de session active

**Fix :** Utiliser `#2C5FC4` (ratio ~5.2:1) pour les textes bleus sur blanc.

```js
C.blueText = '#2C5FC4';  // Textes bleus sur fond blanc
C.blue     = '#4A7FE5';  // Accents, fonds, borders
```

---

## P2 — Majeur

### BUG-02 · KPI card SESSIONS en violet (#823DE8) au lieu de bleu (#4A7FE5)

**Fichier :** `supabase/CRM_Live.html`
**Symptôme :** La card SESSIONS utilise `#823DE8` — la couleur du tab Pipe — au lieu du bleu `#4A7FE5` associé à la Prospection. La bordure gauche violette, le `boxShadow` violet actif et les labels violets sont tous erronés.

**Root cause :** Dans `KPI_CARDS`, la valeur `color` de Sessions a été initialisée à `TAB_COLORS.pipe` (`#823DE8`) au lieu de `C.blue`.

**Fix :**
```js
const KPI_CARDS = [
  { id: 'sessions', label: 'Sessions', color: C.blue },  // ← était #823DE8
  { id: 'interesses', label: 'Intéressés', color: C.green },
  { id: 'relances',   label: 'Relances',   color: C.yellow },
  { id: 'injoignables', label: 'Injoignables', color: C.mid },
];
```

### BUG-03 · Pas de confirmation avant TERMINER LA SESSION

**Écran :** Session Active
**Symptôme :** Cliquer "TERMINER LA SESSION" ferme immédiatement la session sans modale de confirmation. Si des contacts n'ont pas encore été traités, ils sont silencieusement ignorés (dans le test : 2/3 contacts non traités).

**Fix :** Ajouter une modale de confirmation quand `nTraites < total` :

```jsx
if (contactsNonTraites > 0) {
  // Afficher modale : "X contacts non traités. Terminer quand même ?"
  setShowConfirmTerminer(true);
} else {
  terminerSession();
}
```

### BUG-04 · Bouton SUPPRIMER hors viewport dans le SidePanel

**Symptôme :** Dans certaines configurations de fenêtre, le bouton SUPPRIMER du SessionDetailPanel est positionné à `left: 1946px` pour un viewport de 1920px — inaccessible à la souris.

**Root cause :** Le SidePanel a une largeur fixe (~510px) et est ancré à droite, mais son contenu interne (bouton SUPPRIMER + zone de stats) dépasse légèrement la largeur du panel en fonction du padding.

**Fix :** Contraindre le panel et son contenu à `max-width: 100%` avec `box-sizing: border-box`.

```jsx
// SidePanel container
style={{ width: 510, maxWidth: '100vw', boxSizing: 'border-box', overflowX: 'hidden' }}
```

### BUG-05 · Bouton "PAS INTÉRESSÉ" tronqué en vue liste session active

**Écran :** Session Active (vue liste, pas vue focus)
**Symptôme :** Le 4ème bouton d'action "PAS INTÉRESSÉ" est coupé par le bord droit du conteneur. Il est visible en vue focus mais pas en vue liste.

**Fix :** La rangée de boutons action doit s'adapter : soit réduire les marges, soit condenser les libellés (PAS INT.), soit utiliser un flex wrap.

```jsx
// Boutons action — wrap si nécessaire
style={{ display: 'flex', gap: 4, flexWrap: 'nowrap', flexShrink: 0 }}
// Réduire padding des boutons : padding: '4px 8px' → '4px 6px'
```

### BUG-06 · Risque de suppression accidentelle (SidePanel + CTA en overlap)

**Symptôme documenté :** Lors de la revue, un clic visant "NOUVELLE SESSION" a déclenché le bouton "SUPPRIMER" du SidePanel ouvert simultanément (les deux overlappent à l'écran). La session "Session call 23/03" a été supprimée accidentellement.

**Fix :** Quand un SidePanel est ouvert, bloquer les clics sur le fond via un overlay semi-transparent (`pointer-events: all`) ou désactiver les interactions derrière le panel.

```jsx
// Overlay derrière le panel
{panelOpen && <div style={{ position:'fixed', inset:0, zIndex:49 }} onClick={closePanel} />}
// Panel à zIndex: 50
```

---

## P3 — Mineur (Copy / Accents)

### COPY-01 · Stat labels dans session active sans accents

Toutes les occurrences suivantes :

| Actuel | Correct |
|--------|---------|
| `1 appeles` | `1 appelé` |
| `0 interesses` | `0 intéressé(s)` |
| `APPELES` (SidePanel) | `APPELÉS` |
| `INTERESSES` (SidePanel) | `INTÉRESSÉS` |

### COPY-02 · "1 contacts" (pluriel incorrect)

Dans la ligne de session : `24/03/2026 · Nicolas Serradeil · 1 contacts`
→ Pluraliser correctement : `1 contact` / `N contacts`

```js
`${n} contact${n > 1 ? 's' : ''}`
```

### COPY-03 · Empty state — "premiere" sans accent

`"Aucune session — lance ta premiere prospection"`
→ `"Aucune session — lance ta première prospection"`

### COPY-04 · "Precedent" sans accent

Navigation VUE FOCUS : bouton `Precedent` → `Précédent`

### COPY-05 · "Creer une tache de relance" sans accents

Checkbox dans le card APPELÉ → `Créer une tâche de relance`

### COPY-06 · "TOUT SELECTIONNER" sans accent

Bouton dans NewSession → `TOUT SÉLECTIONNER`

### COPY-07 · Libellé VUE FOCUS / VUE LISTE — état contre-intuitif

Le bouton affiche le **mode cible** (pas le mode actif). En vue liste, il affiche "VUE FOCUS". OK pour une convention toggle classique, mais déroutant au premier usage. Envisager d'indiquer l'état courant avec une icône : ≡ Liste / ◉ Focus.

---

## P4 — Évolutions

### EVO-01 · Raccourcis clavier pour les actions de session

En contexte de prospection téléphonique active, les mains sont occupées. Des raccourcis (ex. `A` = Appelé, `I` = Intéressé, `N` = iNjoignable, `P` = Pas intéressé, `→` = contact suivant) multiplieraient la vitesse d'utilisation.

### EVO-02 · "Pas de tel" — feedback plus doux + action directe

Le label rouge `Pas de tel` est visuellement agressif et ne propose pas d'action. Remplacer par un champ téléphone directement éditable inline (avec placeholder ⚠️), pré-focusé quand le card APPELÉ s'ouvre.

### EVO-03 · Empty state — CTA intégré

L'empty state affiche du texte gris passif. Ajouter un bouton `+ NOUVELLE SESSION` dans le bloc empty state pour guider directement l'utilisateur.

```jsx
<div>
  <p>Aucune session — lance ta première prospection</p>
  <button onClick={ouvrirNouvelleSession}>+ NOUVELLE SESSION</button>
</div>
```

### EVO-04 · Confirmation TERMINER avec résumé

Avant de terminer, afficher un récap rapide :
- X/N contacts traités
- Y intéressés · Z injoignables · W pas intéressés
- Bouton "TERMINER" ou "CONTINUER" si contacts restants

### EVO-05 · Boutons action — états visuels clearer

Actuellement INTÉRESSÉ a un fond vert même avant d'être cliqué, rendant l'état "actif" vs "inactif" peu lisible. Uniformiser : tous les boutons en `outline` par défaut, `filled` uniquement quand sélectionné.

### EVO-06 · Mobile / tablette

`body: overflow: hidden` bloque le scroll natif sur mobile. Si l'outil doit être utilisé sur iPad pendant les appels (cas d'usage réel), ce point est bloquant. La media query `max-width: 767px` existe mais nécessite d'être testée et vérifiée.

### EVO-07 · Indicateur "contacts restants" en temps réel

Pendant la session, afficher un indicateur visuel de progression plus visible : ex. une mini progress bar (`3/3` complète = verte, `0/3` = rouge). Actuellement `1/3 traités` est du texte gris discret en haut à côté du titre.

---

## Résumé des fixes pour Claude Code

### Ordre de déploiement recommandé

**Sprint 1 — Bloquants + WCAG (deploy staging)**
1. BUG-01 : sticky du bouton LANCER LA SESSION
2. WCAG-01 : `C.yellowText = '#B8A000'` pour tous les textes jaunes
3. WCAG-02 : `C.greenText = '#007A10'` pour tous les textes verts
4. BUG-02 : KPI Sessions color → `C.blue` au lieu de `#823DE8`
5. WCAG-03 : Labels cards actives → blanc sur midnight

**Sprint 2 — Majeur (deploy staging)**
6. BUG-03 : Modale confirmation TERMINER si contacts non traités
7. BUG-04 : SidePanel max-width + overflow: hidden
8. BUG-05 : Bouton PAS INTÉRESSÉ — fix overflow view liste
9. BUG-06 : Overlay derrière panel ouvert

**Sprint 3 — Copy + Évolutions**
10. COPY-01 à COPY-07 : Accents et pluriels
11. EVO-01 : Raccourcis clavier
12. EVO-03 : Empty state avec CTA

---

## Patterns Claude Code à utiliser

```
// Dans les instructions Claude Code pour les fixes :
"utilise les patterns Simplifier Superpowers et Frontend UI Skill.
Deploy : bash supabase/deploy_staging.sh — staging uniquement, jamais main."
```

**Composants à ne pas toucher :**
`SidePanel`, `CardHeader`, `CH` (système de coordonnées TDB) — réutiliser tel quel.

**Constantes à ajouter dans C (color tokens) :**
```js
C.yellowText = '#B8A000';
C.greenText  = '#007A10';
C.blueText   = '#2C5FC4';
```
