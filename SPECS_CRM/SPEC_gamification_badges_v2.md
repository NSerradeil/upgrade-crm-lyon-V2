# SPEC — Gamification Badges V2 : 6 nouveaux exploits
**CRM Upgrade Lyon V2** · Feature · Complément de SPEC_gamification_badges_titres.md
**Date :** 26/03/2026

---

## Rappel conventions (identiques aux 9 badges existants)

- Icônes 100% SVG inline, `viewBox="0 0 40 40"`, DA brutalist (coins à 90°, pas de border-radius)
- L1 : outline only (`fill="none"`, stroke couleur, strokeWidth 1.5)
- L2 : fill partiel (`${color}40`) + stroke + détail ajouté
- L3 : fill complet + détails supplémentaires
- L4 : fill complet + stroke `#FFD700` sur contours principaux + **pixel crown** (5 rects 3×3)
- `getLevel`, `getProgress`, `resolveDisplayedBadge` : fonctions existantes, aucune modification

---

## 1. Les 6 nouveaux badges

### 🎙️ TRIBUN
> *"La prospection n'est pas un sprint pour toi — c'est un entraînement permanent. Tu te poses, tu décroches, tu recommences. Pendant que d'autres attendent le bon moment, toi tu crées le rythme."*

**Règle XP** : *+1 XP par session de prospection terminée (statut = "done")*

**Metric** : `COUNT(sessions_prospection WHERE statut='done' AND responsable = profile.nom)`

**Palette** : `#F97316`

| Level | Seuil | Titre |
|---|---|---|
| Junior | 5 | **Bavard** |
| Confirmé | 20 | **Loquace** |
| Senior | 40 | **Intarissable** |
| Expert | 80 | **Tribun** |

**Icône SVG** — téléphone combiné + bulle de dialogue (brutaliste) :
```
Téléphone base (identique PROSPECTEUR) :
  rect x=9  y=8  w=10 h=7   (écouteur)
  rect x=21 y=25 w=10 h=7   (micro)
  rect x=9  y=13 w=22 h=14  (corps)

Bulle speech (à droite, hors téléphone) :
  rect x=26 y=5 w=12 h=10   (corps bulle)
  polygon points="27,15 30,15 27,18"  (queue bulle)

L1 : téléphone outline + bulle outline vide
L2 : téléphone fill ${color}40 + bulle fill ${color}20 + 2 petits rects (lignes) dans bulle
L3 : téléphone fill color + bulle fill color + 3 rects blancs (lignes de texte)
L4 : L3 + stroke=#FFD700 sur téléphone + pixel crown
```

---

### 💰 GOLDMAKER
> *"Derrière chaque mission, il y a un chiffre. Et derrière ce chiffre, il y a toi — le commercial qui a trouvé le bon profil, convaincu le bon client, et signé au bon moment. Ton CA, c'est la mesure tangible de ton impact."*

**Règle XP** : *Score = CA cumulé YTD (1er janvier → aujourd'hui) sur toutes les missions actives et terminées du responsable*

**Metric** :
```js
// Missions du responsable dont la période chevauche l'année courante
// CA mission = tjm × nb_jours (ou champ ca si disponible en base)
// Si mission démarrée avant le 1er janvier : ne compter que les jours depuis le 1er jan
const currentYear = new Date().getFullYear();
const startOfYear = new Date(currentYear, 0, 1);
// score = SUM(ca_ytd) pour chaque mission WHERE responsable = profile.nom
//         AND date_debut <= today
//         AND (date_fin >= startOfYear OR statut = 'En cours')
```

> Note pour Code : si un champ `ca` ou `ca_total` existe sur `missions`, l'utiliser filtré sur l'année courante. Sinon calculer `tjm × nb_jours_ytd` côté JS.

**Palette** : `#EAB308` (gold)

**Affichage score** : formater en euros — `score.toLocaleString('fr-FR') + ' €'` dans BadgeCard et detail panel.

| Level | Seuil | Titre |
|---|---|---|
| Junior | 500 000 € | **Contributeur** |
| Confirmé | 1 000 000 € | **Générateur** |
| Senior | 3 000 000 € | **Producteur** |
| Expert | 4 000 000 € | **Goldmaker** |

**Icône SVG** — stack de pièces :
```
Pièce base = ellipse horizontale (cercle aplati brutaliste → rect arrondi → rect 16×8 avec rx=4...
→ version brutaliste : rect x=12 y=18 w=16 h=6 + rect x=10 y=14 w=20 h=6 + rect x=12 y=10 w=16 h=6)

L1 : 1 seule "pièce" (rect 16×6 centré) outline + "€" en text cx=20 cy=21 fontSize=8
L2 : 2 pièces empilées (2 rects décalés en y) fill ${color}40 + "€" fill color
L3 : 3 pièces empilées fill color, "€" fill white sur la pièce du haut
L4 : 3 pièces fill + stroke=#FFD700 + "€" fill=#FFD700 + pixel crown
```

---

### 📈 RENTIER
> *"Closer, c'est bien. Closer avec de la marge, c'est mieux. Tu ne remplis pas le pipeline à n'importe quel prix — tu choisis tes deals, tu défends tes conditions, et ton portefeuille reflète cette exigence."*

**Règle XP** : *+0,5 pt par mission avec taux de marge > 20% · +1 pt si > 30% · +2 pts si > 40%*

**Metric** :
```js
// Fetch : missions WHERE responsable = profile.nom AND cjm IS NOT NULL AND tjm IS NOT NULL AND tjm > 0
// Calcul côté JS :
let score = 0;
missions.forEach(m => {
  const taux = (m.cjm / m.tjm) * 100;
  if (taux > 40)      score += 2;
  else if (taux > 30) score += 1;
  else if (taux > 20) score += 0.5;
});
// score = total de points pondérés
```

**Palette** : `#10B981` (emerald)

**Affichage score** : `score.toFixed(1) + ' pts'`

| Level | Seuil | Titre |
|---|---|---|
| Junior | 5 pts | **Équilibré** |
| Confirmé | 20 pts | **Rentable** |
| Senior | 30 pts | **Stratège** |
| Expert | 50 pts | **Rentier** |

**Icône SVG** — symbole % + graphique montant :
```
% brutaliste :
  circle cx=14 cy=14 r=4   (cercle haut gauche)
  circle cx=26 cy=26 r=4   (cercle bas droite)
  line x1=10 y1=30 x2=30 y2=10 strokeWidth=2.5  (diagonale)

L1 : % outline complet (fill=none)
L2 : % outline + 3 mini barres montantes à droite :
     rect x=28 y=28 w=3 h=4  (barre 1, courte)
     rect x=32 y=24 w=3 h=8  (barre 2, moyenne)
     → (légèrement hors viewBox → ajuster x=24,28 y=28,24,20)
L3 : circles du % fill color + barres fill color (3 barres montantes intégrées dans la vue)
     Adapter layout pour tenir dans 40×40 :
       % centré à gauche x=8-22
       barres à droite x=26-36
L4 : L3 + stroke=#FFD700 sur circles + pixel crown
```

---

### 🏗️ ARCHITECTE
> *"Avant de closer, tu construis. Chaque besoin formalisé, c'est une opportunité que tu as eu le flair de cadrer avant qu'elle ne disparaisse dans le flou. Le pipeline ne se remplit pas tout seul — c'est toi qui poses les premières briques."*

**Règle XP** : *+1 XP par besoin créé dans le CRM (tous statuts)*

**Metric** : `COUNT(besoins WHERE responsable = profile.nom)`

**Palette** : `#A78BFA` (lavande)

| Level | Seuil | Titre |
|---|---|---|
| Junior | 20 besoins | **Dessinateur** |
| Confirmé | 50 besoins | **Constructeur** |
| Senior | 100 besoins | **Ingénieur** |
| Expert | 200 besoins | **Architecte** |

**Icône SVG** — règle + équerre :
```
Règle horizontale :
  rect x=4 y=18 w=32 h=6   (corps règle)
  Graduations : 5 petits rects 1×3 espacés de 5px en y=18 (sur le bord supérieur)

Équerre (L2+) :
  path M=8,8 L=8,18 L=18,18  (l'angle droit de l'équerre)

L1 : règle outline seule + 3 graduations
L2 : règle fill ${color}40 + 5 graduations + équerre outline
L3 : règle fill color (graduations fill white) + équerre fill color
     + petit crayon en diagonal haut-droite :
       rect x=28 y=6 w=4 h=12 transform="rotate(-30 30 12)"  (corps crayon)
       polygon points="28,18 30,18 29,22"  (pointe)
L4 : L3 + stroke=#FFD700 sur règle + pixel crown
```

---

### 🤝 DIPLOMATE
> *"Le téléphone, c'est bien. La salle de réunion, c'est autre chose. Tu sors du bureau, tu vas chez les clients, tu serres des mains. Ces rendez-vous-là créent quelque chose qu'aucun email ne peut reproduire — une relation."*

**Règle XP** : *+1 XP par RDV logué dans les tâches (type='RDV') OU dans l'historique d'actions (type='RDV')*

**Metric** :
```js
const [rTaches, rActions] = await Promise.all([
  sb.from('taches')
    .select('id', { count:'exact', head:true })
    .eq('responsable', profileNom)
    .eq('type', 'RDV'),
  sb.from('historique_actions')
    .select('id', { count:'exact', head:true })
    .eq('responsable', profileNom)
    .eq('type', 'RDV'),
]);
const nbDiplomate = (rTaches.count || 0) + (rActions.count || 0);
```

**Palette** : `#0EA5E9` (sky blue)

| Level | Seuil | Titre |
|---|---|---|
| Junior | 15 RDV | **Accessible** |
| Confirmé | 40 RDV | **Présent** |
| Senior | 80 RDV | **Diplomate** |
| Expert | 150 RDV | **Plénipotentiaire** |

**Icône SVG** — poignée de main :
```
Deux mains qui se rejoignent (vue de face, symétrique) :

Main gauche :
  rect x=4 y=16 w=12 h=8   (paume)
  rect x=4 y=10 w=3  h=7   (doigt 1)
  rect x=8 y=9  w=3  h=7   (doigt 2)
  rect x=12 y=10 w=3 h=6   (doigt 3)

Main droite (miroir) :
  rect x=24 y=16 w=12 h=8
  rect x=33 y=10 w=3  h=7
  rect x=29 y=9  w=3  h=7
  rect x=25 y=10 w=3  h=6

Jointure centrale :
  rect x=14 y=16 w=12 h=8  (zone de contact)

L1 : outline uniquement (fill=none)
L2 : paumes fill ${color}40 + doigts outline + jointure fill ${color}30
L3 : mains fill color + doigts fill (légèrement plus foncé) + manchettes :
     rect x=4  y=24 w=12 h=5 fill=${color} (manchette gauche)
     rect x=24 y=24 w=12 h=5 fill=${color} (manchette droite)
L4 : L3 + stroke=#FFD700 sur les contours des paumes + pixel crown
```

---

### ⚡ SPEED CLOSER
> *"30 jours. C'est tout ce qu'il te faut entre un brief client et une mission démarrée. Tu ne laisses pas le temps à l'opportunité de refroidir. Là où d'autres s'enlisent dans les allers-retours, toi tu exécutes."*

**Règle XP** : *+1 XP par besoin passé au statut "pourvu" en moins de 30 jours après sa création*

**Metric** :
```js
// Fetch
const { data: besoins } = await sb
  .from('besoins')
  .select('created_at, updated_at')
  .eq('responsable', profileNom)
  .eq('statut', 'pourvu');

// Calcul côté JS
const score = (besoins || []).filter(b => {
  const created = new Date(b.created_at);
  const closed  = new Date(b.updated_at);
  const days    = (closed - created) / (1000 * 60 * 60 * 24);
  return days < 30;
}).length;
```

**Palette** : `#DC2626` (red vif)

| Level | Seuil | Titre |
|---|---|---|
| Junior | 1 deal | **Réactif** |
| Confirmé | 4 deals | **Agile** |
| Senior | 8 deals | **Speed Closer** |
| Expert | 15 deals | **Éclair** |

**Icône SVG** — éclair (foudre) + chrono :
```
Éclair central :
  polygon points="23,4 17,20 22,20 17,36 26,20 21,20 23,4"

Chrono (L2+, à gauche de l'éclair) :
  circle cx=10 cy=22 r=7  (cadran)
  rect x=8 y=14 w=4 h=2   (couronne)
  line x1=10 y1=22 x2=10 y2=17  (aiguille heure)
  line x1=10 y1=22 x2=13 y2=22  (aiguille minute)

L1 : éclair outline seul
L2 : éclair fill ${color}40 + chrono outline (cercle + aiguilles)
L3 : éclair fill color + chrono fill ${color}30 (aiguilles fill color)
     + 2 traits de vitesse à gauche de l'éclair :
       line x1=4 y1=16 x2=14 y2=16
       line x1=6 y1=20 x2=14 y2=20
L4 : éclair fill + traits + chrono + stroke=#FFD700 sur éclair + pixel crown
```

---

## 2. Ajouts dans `BADGE_META`

```js
// Ajouter aux 9 entrées existantes :
tribun: {
  label: 'Tribun',
  color: '#F97316',
  titles: ['Bavard', 'Loquace', 'Intarissable', 'Tribun'],
  unit: 'sessions de prospection',
  description: "La prospection n'est pas un sprint pour toi — c'est un entraînement permanent. Tu te poses, tu décroches, tu recommences. Pendant que d'autres attendent le bon moment, toi tu crées le rythme.",
  xpRule: "+1 XP par session de prospection terminée (statut « done »)",
},
goldmaker: {
  label: 'Goldmaker',
  color: '#EAB308',
  titles: ['Contributeur', 'Générateur', 'Producteur', 'Goldmaker'],
  unit: '€ CA YTD',
  description: "Derrière chaque mission, il y a un chiffre. Et derrière ce chiffre, il y a toi — le commercial qui a trouvé le bon profil, convaincu le bon client, et signé au bon moment. Ton CA, c'est la mesure tangible de ton impact.",
  xpRule: "Score = CA cumulé YTD sur toutes les missions actives et terminées du responsable",
},
rentier: {
  label: 'Rentier',
  color: '#10B981',
  titles: ['Équilibré', 'Rentable', 'Stratège', 'Rentier'],
  unit: 'pts de marge',
  description: "Closer, c'est bien. Closer avec de la marge, c'est mieux. Tu ne remplis pas le pipeline à n'importe quel prix — tu choisis tes deals, tu défends tes conditions, et ton portefeuille reflète cette exigence.",
  xpRule: "+0,5 pt si marge > 20% · +1 pt si > 30% · +2 pts si > 40%",
},
architecte: {
  label: 'Architecte',
  color: '#A78BFA',
  titles: ['Dessinateur', 'Constructeur', 'Ingénieur', 'Architecte'],
  unit: 'besoins créés',
  description: "Avant de closer, tu construis. Chaque besoin formalisé, c'est une opportunité que tu as eu le flair de cadrer avant qu'elle ne disparaisse dans le flou. Le pipeline ne se remplit pas tout seul — c'est toi qui poses les premières briques.",
  xpRule: "+1 XP par besoin créé dans le CRM (tous statuts)",
},
diplomate: {
  label: 'Diplomate',
  color: '#0EA5E9',
  titles: ['Accessible', 'Présent', 'Diplomate', 'Plénipotentiaire'],
  unit: 'RDV loggés',
  description: "Le téléphone, c'est bien. La salle de réunion, c'est autre chose. Tu sors du bureau, tu vas chez les clients, tu serres des mains. Ces rendez-vous-là créent quelque chose qu'aucun email ne peut reproduire — une relation.",
  xpRule: "+1 XP par RDV logué dans les tâches ou l'historique d'actions",
},
speedcloser: {
  label: 'Speed Closer',
  color: '#DC2626',
  titles: ['Réactif', 'Agile', 'Speed Closer', 'Éclair'],
  unit: 'deals < 30 jours',
  description: "30 jours. C'est tout ce qu'il te faut entre un brief client et une mission démarrée. Tu ne laisses pas le temps à l'opportunité de refroidir. Là où d'autres s'enlisent dans les allers-retours, toi tu exécutes.",
  xpRule: "+1 XP par besoin passé au statut « pourvu » en moins de 30 jours après sa création",
},
```

---

## 3. Ajouts dans `BADGE_THRESHOLDS`

```js
// Ajouter aux 9 entrées existantes :
tribun:      [5,       20,        40,        80],
goldmaker:   [500000,  1000000,   3000000,   4000000],
rentier:     [5,       20,        30,        50],
architecte:  [20,      50,        100,       200],
diplomate:   [15,      40,        80,        150],
speedcloser: [1,       4,         8,         15],
```

---

## 4. Ajouts dans `loadAchievements`

```js
// Ajouter en parallèle aux fetches existants :

// TRIBUN
sb.from('sessions_prospection')
  .select('id', { count:'exact', head:true })
  .eq('statut', 'done')
  .eq('responsable', profileNom),

// GOLDMAKER + RENTIER — même requête, deux calculs
sb.from('missions')
  .select('tjm, cjm, date_debut, date_fin, statut')
  .eq('responsable', profileNom)
  .not('tjm', 'is', null),

// ARCHITECTE
sb.from('besoins')
  .select('id', { count:'exact', head:true })
  .eq('responsable', profileNom),

// DIPLOMATE — deux sources
sb.from('taches')
  .select('id', { count:'exact', head:true })
  .eq('responsable', profileNom)
  .eq('type', 'RDV'),
sb.from('historique_actions')
  .select('id', { count:'exact', head:true })
  .eq('responsable', profileNom)
  .eq('type', 'RDV'),

// SPEED CLOSER
sb.from('besoins')
  .select('created_at, updated_at')
  .eq('responsable', profileNom)
  .eq('statut', 'pourvu'),
```

```js
// Calculs côté JS à ajouter dans le return :
const currentYear = new Date().getFullYear();
const startOfYear = new Date(currentYear, 0, 1);
const today = new Date();

// GOLDMAKER : CA YTD
let caYTD = 0;
(rMissionsV2.data || []).forEach(m => {
  if (!m.tjm || !m.date_debut) return;
  const debut = new Date(m.date_debut);
  const fin   = m.date_fin ? new Date(m.date_fin) : today;
  const debutYTD = debut < startOfYear ? startOfYear : debut;
  const finYTD   = fin > today ? today : fin;
  if (debutYTD > finYTD) return;
  const jours = Math.round((finYTD - debutYTD) / (1000 * 60 * 60 * 24));
  caYTD += m.tjm * jours;
});

// RENTIER : points de marge pondérés
let margeScore = 0;
(rMissionsV2.data || []).forEach(m => {
  if (!m.tjm || !m.cjm || m.tjm === 0) return;
  const taux = (m.cjm / m.tjm) * 100;
  if (taux > 40)      margeScore += 2;
  else if (taux > 30) margeScore += 1;
  else if (taux > 20) margeScore += 0.5;
});

// SPEED CLOSER
const speedCloserScore = (rSpeedCloser.data || []).filter(b => {
  const days = (new Date(b.updated_at) - new Date(b.created_at)) / (1000 * 60 * 60 * 24);
  return days < 30;
}).length;

return {
  // ...existants...
  tribun:      rTribun.count       || 0,
  goldmaker:   caYTD,
  rentier:     margeScore,
  architecte:  rArchitecte.count  || 0,
  diplomate:   (rDiplomateTaches.count || 0) + (rDiplomateActions.count || 0),
  speedcloser: speedCloserScore,
};
```

---

## 5. Ajout dans `BADGE_ICONS`

```js
// Ajouter les 6 nouvelles entrées dans la map BADGE_ICONS :
const BADGE_ICONS = {
  // ...existants (9 badges)...
  tribun:      (lv, color) => (/* téléphone + bulle speech — voir specs SVG §1 */),
  goldmaker:   (lv, color) => (/* stack pièces — voir specs SVG §1 */),
  rentier:     (lv, color) => (/* % + barres montantes — voir specs SVG §1 */),
  architecte:  (lv, color) => (/* règle + équerre + crayon — voir specs SVG §1 */),
  diplomate:   (lv, color) => (/* poignée de main — voir specs SVG §1 */),
  speedcloser: (lv, color) => (/* éclair + chrono — voir specs SVG §1 */),
};
```

> **Note pour Claude Code** : implémenter chaque icône avec les 4 levels via `switch(lv)` ou conditions `lv >= N`. Respecter strictement les règles DA : viewBox 0 0 40 40, strokeWidth 1.5–2.5, fill plein au L3, pixel crown au L4, stroke #FFD700 au L4. Les formes décrites en §1 sont les formes cibles — liberté sur les détails tant que la lisibilité et la progression visuelle L1→L4 sont claires.

---

## 6. Grille Exploits — mise à jour layout

```
Avant : 3×3 = 9 badges
Après : 5 lignes, adapter la grille

Option A — 3 colonnes × 5 lignes (15 cases, 15 badges) :
  Ligne 1 : Prospecteur  | Chasseur    | Éleveur
  Ligne 2 : Connaisseur  | Recruteur   | Gestionnaire
  Ligne 3 : Productif    | Networker   | Relanceur
  Ligne 4 : Tribun       | Goldmaker   | Rentier
  Ligne 5 : Architecte   | Diplomate   | Speed Closer

grid-template-columns: repeat(3, 1fr)  ← inchangé
```

Score total : `/60` (15 badges × 4 levels)

---

## 7. Acceptance criteria

- [ ] 6 nouvelles entrées dans `BADGE_META`, `BADGE_THRESHOLDS`, `BADGE_ICONS`, `loadAchievements`
- [ ] Icônes SVG 100% inline pour les **4 levels de chaque nouveau badge** — même standard DA que les 9 existants
- [ ] L4 pixel crown gold sur tous les nouveaux badges sans exception
- [ ] TRIBUN : label catégorie affiché = **"TRIBUN"** (pas "Marathonien")
- [ ] RENTIER : label catégorie affiché = **"RENTIER"** (pas "Marge")
- [ ] GOLDMAKER : score affiché formaté `"X € CA YTD"` dans BadgeCard et detail panel
- [ ] RENTIER : score affiché `"X,X pts"` (1 décimale car demi-points possibles)
- [ ] SPEED CLOSER : calcul du délai sur `created_at → updated_at` côté JS, seuil strict < 30 jours
- [ ] GOLDMAKER + RENTIER partagent la même requête `missions` (optimisation)
- [ ] DIPLOMATE : somme taches + historique_actions de type 'RDV'
- [ ] Grille Exploits en **5 lignes × 3 colonnes** (15 badges)
- [ ] Score `/36` → `/60` mis à jour dans le header de la page Exploits
- [ ] `loadAchievements` recalculé après : `handleSaveBesoin`, `handleTerminerSession`, `handleSaveMission`, `handleCompleteTask`, `handleLogAction` (type RDV)
