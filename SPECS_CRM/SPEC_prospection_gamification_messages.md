# SPEC — Prospection : messages encourageants sur la barre de progression

**Fichier** : `supabase/CRM_Live.html` — composant `ProspectionActive` (barre de progression)
**Date** : 26/03/2026
**Priorité** : P2 (nice to have / gamification)

---

## Comportement attendu

Sous (ou à côté de) la barre de complétion, afficher un **message court et encourageant** qui :
- Change selon le % de complétion (par palier)
- Est **tiré aléatoirement** parmi plusieurs options pour chaque palier (évite la répétition)
- Se met à jour à chaque contact traité
- Disparaît (ou passe en message de fin) à 100%

---

## Messages par palier

```js
const ENCOURAGEMENTS = {
  0: [
    "Allez, on se lance ! 💪",
    "La liste n'attend que toi.",
    "Premier call = premier pas.",
  ],
  // 1–24%
  low: [
    "Bien démarré !",
    "C'est parti, continue comme ça.",
    "Les premières lignes sont toujours les meilleures.",
    "Bon rythme, reste focus.",
  ],
  // 25–49%
  quarter: [
    "Déjà 1/4 — t'es lancé.",
    "Le moteur chauffe bien.",
    "Bonne cadence, keep going.",
    "Un quart de fait, trois à venir.",
  ],
  // 50%
  half: [
    "Moitié chemin — halfway hero. 🎯",
    "50% — t'es dans la zone.",
    "La moitié est derrière toi.",
    "Mi-chemin, on lâche rien.",
  ],
  // 51–74%
  above_half: [
    "Plus de la moitié — la fin approche.",
    "T'es dans le bon sens.",
    "Chaque appel compte, continue.",
    "La liste fond, c'est bon signe.",
  ],
  // 75–89%
  almost: [
    "Sprint final en vue 🏁",
    "Dernière ligne droite !",
    "Plus que quelques calls.",
    "T'y es presque — donne tout.",
    "75% — l'effort paie.",
  ],
  // 90–99%
  final: [
    "Tout dernier effort ! 🔥",
    "Quelques contacts restants — on finit fort.",
    "La fin est là, accroche-toi.",
    "Presque ! Ne lâche pas maintenant.",
  ],
  // 100%
  done: [
    "Session bouclée — GG ! 🎉",
    "100% — mission accomplie.",
    "Tout le monde a été contacté. Bien joué.",
    "C'est dans la boîte. Belle session ! 🏆",
  ],
};
```

---

## Logique de sélection

```js
function getEncouragement(pct) {
  var pool;
  if (pct === 0)        pool = ENCOURAGEMENTS[0];
  else if (pct < 25)    pool = ENCOURAGEMENTS.low;
  else if (pct < 50)    pool = ENCOURAGEMENTS.quarter;
  else if (pct === 50)  pool = ENCOURAGEMENTS.half;
  else if (pct < 75)    pool = ENCOURAGEMENTS.above_half;
  else if (pct < 90)    pool = ENCOURAGEMENTS.almost;
  else if (pct < 100)   pool = ENCOURAGEMENTS.final;
  else                  pool = ENCOURAGEMENTS.done;

  // Tirage aléatoire stable par palier (change seulement quand on change de palier)
  // Utiliser le pct comme seed léger pour éviter que le message change à chaque render
  var idx = Math.floor(pct / 10) % pool.length;
  return pool[idx];
}
```

> Pour avoir un tirage vraiment aléatoire à chaque changement de palier, stocker le message dans un `useState` et le re-tirer uniquement quand le palier change :

```js
var currentPalier = pct === 0 ? '0'
  : pct < 25 ? 'low' : pct < 50 ? 'quarter'
  : pct === 50 ? 'half' : pct < 75 ? 'above_half'
  : pct < 90 ? 'almost' : pct < 100 ? 'final' : 'done';

var [message, setMessage] = React.useState(() => getEncouragement(pct));
var [lastPalier, setLastPalier] = React.useState(currentPalier);

React.useEffect(() => {
  if (currentPalier !== lastPalier) {
    var pool = ENCOURAGEMENTS[currentPalier] || ENCOURAGEMENTS.low;
    setMessage(pool[Math.floor(Math.random() * pool.length)]);
    setLastPalier(currentPalier);
  }
}, [currentPalier]);
```

---

## Intégration dans le rendu

Juste sous la barre de progression (actuellement `X/Y traités`) :

```jsx
{/* Barre existante */}
<div style={{...barreStyle}} />

{/* Message encourageant */}
{message && (
  <div style={{
    fontSize: 11,
    fontStyle: 'italic',
    color: pct === 100 ? '#00C218' : '#4A7FE5',
    marginTop: 4,
    textAlign: 'center',
    letterSpacing: '0.02em',
    minHeight: 16,
  }}>
    {message}
  </div>
)}
```

- Couleur **verte** à 100%, **bleue** sinon
- `minHeight: 16` pour éviter le layout shift quand le message change

---

## Calcul du % (rappel)

```js
var total = items.length;
var traites = items.filter(function(c) { return c.status !== 'none'; }).length;
var pct = total > 0 ? Math.round((traites / total) * 100) : 0;
```
