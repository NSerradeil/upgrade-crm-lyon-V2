# SPEC — Système de Gamification : Badges & Titres
**CRM Upgrade Lyon V2** · Feature majeure
**Date :** 26/03/2026
**Ref data** : Nicolas = 853 contacts prospectés au 26/03 → seuils calibrés sur cette base

---

## 1. Philosophie & Principes de Design

### Contexte
Petite équipe de ~5 commerciaux en agence. L'enjeu n'est PAS la compétition inter-individus (destructrice à cette échelle) mais la **maîtrise personnelle** et la **fierté de progression**. Le système doit récompenser la régularité et la qualité du travail CRM, pas la performance brute.

### Principes retenus
1. **Mastery > Competition** : pas de leaderboard. Chaque commercial voit sa propre progression.
2. **Critères transparents** : chaque badge affiche exactement ce qui est mesuré.
3. **Feedback immédiat** : le badge se met à jour dès le seuil franchi.
4. **Badges verrouillés visibles** : grisés + cliquables pour savoir comment les gagner.
5. **Calcul on-the-fly** : aucune nouvelle table. Scores calculés depuis les tables existantes.
6. **Icônes 100% code** : tout dessiné en JSX/SVG inline dans la DA brutalist Upgrade — aucun asset externe, aucune image importée.

---

## 2. Nomenclature des niveaux

| Level | Code | Label UI | Style badge |
|---|---|---|---|
| 1 | `junior` | Junior | Outline fine sur fond blanc |
| 2 | `confirme` | Confirmé | Fill 40% + stroke couleur |
| 3 | `senior` | Senior | Fill complet, couleur saturée |
| 4 | `expert` | Expert | Fill + stroke gold `#FFD700` + pixel crown |

---

## 3. Catégories de Badges (9)

### 🎯 PROSPECTEUR
**Metric** : total contacts appelés en sessions (`session_prospection_contacts` via `sessions_prospection.responsable`)
**Palette** : `#4A7FE5`

> Calibrage : Nicolas = 853 contacts au 26/03. Cible L3 "Négociateur" avec marge vers L4.

| Level | Seuil | Titre | Description |
|---|---|---|---|
| Junior | 50 – 249 | **Prospecteur** | "Tu décroches le téléphone. C'est déjà ça." |
| Confirmé | 250 – 749 | **Accrocheur** | "Tu ne lâches pas. Les refus ne t'arrêtent pas." |
| Senior | 750 – 1 999 | **Négociateur** | "Chaque appel est une opportunité que tu ne rates plus." |
| Expert | 2 000+ | **Maître du Pitch** | "Upgrade incarne ta voix. Tu maîtrises l'art de convaincre." |

---

### 🏹 CHASSEUR
**Metric** : nombre de comptes clients distincts dans lesquels au moins 1 mission a été ouverte — `COUNT(DISTINCT contact_referent_id)` in `missions WHERE responsable = profile.nom`

> ⚠️ Différent de ÉLEVEUR (qui mesure les comptes avec ≥2 missions) : ici 1 mission suffit, l'objectif est la largeur du portefeuille.

**Palette** : `#FF3D2E`

| Level | Seuil | Titre | Description |
|---|---|---|---|
| Junior | 1 – 4 | **Éclaireur** | "Tu as ouvert les premiers territoires." |
| Confirmé | 5 – 10 | **Pisteur** | "Tu suis la piste jusqu'au bout." |
| Senior | 11 – 25 | **Chasseur** | "Tu n'attends pas que la proie vienne à toi." |
| Expert | 26+ | **Prédateur** | "Les comptes ouverts s'accumulent. Le marché te connaît." |

---

### 🌱 ÉLEVEUR
**Metric** : nombre de comptes clients distincts (`contact_referent_id` unique) avec ≥ 2 missions portées par le même responsable — récompense la **largeur** de la fidélisation
**Palette** : `#00C218`

| Level | Seuil | Titre | Description |
|---|---|---|---|
| Junior | 1 compte | **Semeur** | "Tu plantes. Les premières graines poussent." |
| Confirmé | 2 – 4 comptes | **Cultivateur** | "Plusieurs clients te font confiance durablement." |
| Senior | 5 – 9 comptes | **Éleveur** | "Tes clients reviennent. Tu deviens incontournable." |
| Expert | 10+ comptes | **Patriarche** | "Un portefeuille solide, construit sur la durée." |

---

### 🏛️ CONNAISSEUR
**Metric** : nombre maximum de missions sur un **même compte** — `MAX(COUNT per contact_referent_id)` in `missions WHERE responsable = profile.nom` — récompense la **profondeur** sur un compte unique

> Complémentaire à ÉLEVEUR : ÉLEVEUR = nombre de comptes fidélisés. CONNAISSEUR = profondeur sur le compte le plus développé.

**Palette** : `#10B981` (emerald, distinct du vert ÉLEVEUR)

| Level | Seuil | Titre | Description |
|---|---|---|---|
| Junior | 2 missions / même compte | **Habitué** | "On sait ton nom à l'accueil. Tu reviens." |
| Confirmé | 5 missions / même compte | **Familier** | "Tu fais partie des meubles. Le client te fait confiance." |
| Senior | 10 missions / même compte | **Connaisseur** | "Tu connais ce compte par cœur. Chaque rouage, chaque interlocuteur." |
| Expert | 20 missions / même compte | **Référent** | "Ce compte, c'est toi. La relation est structurelle." |

---

### 🤝 RECRUTEUR
**Metric** : `missions WHERE besoin_id IS NOT NULL AND responsable = profile.nom`
**Palette** : `#8B5CF6`

| Level | Seuil | Titre | Description |
|---|---|---|---|
| Junior | 1 – 9 | **Talent Finder** | "Tu réunis les bons profils avec les bons besoins." |
| Confirmé | 10 – 14 | **Recruteur** | "Tu matches les talents avec les opportunités." |
| Senior | 15 – 30 | **Chasseur de Têtes** | "On vient te voir pour trouver la perle rare." |
| Expert | 31+ | **DRH Upgrade** | "Tu as construit une filière. Le pool tourne." |

---

### 📋 GESTIONNAIRE
**Metric** : `historique_missions WHERE responsable = profile.nom` (chaque ligne = 1 suivi logué)
**Palette** : `#F59E0B`

| Level | Seuil | Titre | Description |
|---|---|---|---|
| Junior | 10 – 50 | **Coordinateur** | "Tu gardes le fil. Tes missions avancent." |
| Confirmé | 51 – 100 | **Chef de Projet** | "Tu structures. Tes clients sentent la différence." |
| Senior | 101 – 300 | **Gestionnaire** | "Rien ne t'échappe. Le suivi est ta signature." |
| Expert | 301+ | **Pilote** | "Tu pilotes en aveugle et tu n'atterris jamais mal." |

---

### 🚀 PRODUCTIF
**Metric** : `besoins WHERE statut='pourvu' AND responsable = profile.nom`
**Palette** : `#06B6D4`

| Level | Seuil | Titre | Description |
|---|---|---|---|
| Junior | 1 – 5 | **Lanceur** | "Tu transformes les opportunités. Les premiers deals." |
| Confirmé | 6 – 15 | **Transformeur** | "Tes besoins ne restent pas longtemps ouverts." |
| Senior | 16 – 35 | **Closer** | "Du brief au démarrage, tu raccourcis le cycle." |
| Expert | 36+ | **Machine à Closer** | "Productivité max. Le pipeline ne s'engorge jamais." |

---

### 🌐 NETWORKER
**Metric** : `contacts WHERE responsable = profile.nom`
**Palette** : `#6366F1`

> Calibrage : si 853 contacts en sessions, total contacts CRM potentiellement ~500-1000.

| Level | Seuil | Titre | Description |
|---|---|---|---|
| Junior | 50 – 299 | **Connecté** | "Ton réseau existe. Il grandit." |
| Confirmé | 300 – 599 | **Networker** | "Tu alimentes le CRM. Chaque contact compte." |
| Senior | 600 – 999 | **Hub** | "Tout passe par toi. Tu es un nœud central." |
| Expert | 1 000+ | **Super Connecteur** | "Un réseau qui vit et travaille pour toi." |

---

### 🔄 RELANCEUR
**Metric** : `taches WHERE session_prospection_id IS NOT NULL AND statut='fait' AND responsable = profile.nom`
**Palette** : `#EC4899`

| Level | Seuil | Titre | Description |
|---|---|---|---|
| Junior | 5 – 14 | **Persévérant** | "Tu rappelles. Tu ne laisses pas tomber." |
| Confirmé | 15 – 34 | **Ténace** | "Les prospects ne t'oublient pas." |
| Senior | 35 – 74 | **Bulldozer** | "Tu traverses les objections." |
| Expert | 75+ | **Inépuisable** | "Tu rappelles là où tout le monde a abandonné." |

---

## 4. Calcul des scores (JS)

```js
const BADGE_THRESHOLDS = {
  prospecteur:  [50,  250,  750,  2000],
  chasseur:     [1,   5,    11,   26],
  eleveur:      [1,   2,    5,    10],
  connaisseur:  [2,   5,    10,   20],   // MAX missions sur 1 même compte
  recruteur:    [1,   10,   15,   31],
  gestionnaire: [10,  51,   101,  301],
  productif:    [1,   6,    16,   36],
  networker:    [50,  300,  600,  1000],
  relanceur:    [5,   15,   35,   75],
};

// Retourne 0 (non débloqué) à 4 (expert)
function getLevel(category, score) {
  const t = BADGE_THRESHOLDS[category];
  if (score >= t[3]) return 4;
  if (score >= t[2]) return 3;
  if (score >= t[1]) return 2;
  if (score >= t[0]) return 1;
  return 0;
}

// Retourne { pct, current, next, nextLabel }
function getProgress(category, score) {
  const t = BADGE_THRESHOLDS[category];
  const level = getLevel(category, score);
  if (level === 0) return { current: score, next: t[0], pct: Math.round(score / t[0] * 100) };
  if (level === 4) return { current: score, next: null, pct: 100 };
  const low = t[level - 1], high = t[level];
  return { current: score, next: high, pct: Math.round((score - low) / (high - low) * 100) };
}
```

---

## 5. Icônes SVG — Composant `BadgeIcon`

### Règles générales (DA brutalist Upgrade)
- **Pas de border-radius**, **pas de clip-path** complexe. Formes géométriques pures : rect, circle, polygon, path avec coins à 90°.
- `viewBox="0 0 40 40"` sur tous les SVG.
- L1 : `fill="none"`, `stroke={color}`, `strokeWidth="1.5"` — icône vide, outline.
- L2 : fill partiel (zone principale remplie), détails ajoutés.
- L3 : fill complet + détails supplémentaires.
- L4 : fill complet + **stroke or fill `#FFD700`** sur les contours + **pixel crown** (5 petits `rect` 3×3 disposés en arc au-dessus de l'icône).
- **Pixel crown L4** — toujours les mêmes 5 rects :
  ```jsx
  // Crown pixel (x positions: 11, 15, 19, 23, 27 — y: 3 pour les bas, 1 pour le haut central)
  <rect x="11" y="4" width="3" height="3" fill="#FFD700"/>
  <rect x="15" y="2" width="3" height="3" fill="#FFD700"/>
  <rect x="19" y="1" width="3" height="3" fill="#FFD700"/>
  <rect x="23" y="2" width="3" height="3" fill="#FFD700"/>
  <rect x="27" y="4" width="3" height="3" fill="#FFD700"/>
  ```

---

### Composant principal

```jsx
function BadgeIcon({ category, level, size = 40, greyed = false }) {
  const meta = BADGE_META[category];
  const color = greyed ? '#CCCCCC' : meta.color;
  const fill = greyed ? '#EEEEEE' : meta.color;
  const scale = size / 40;

  return (
    <svg
      viewBox="0 0 40 40"
      width={size}
      height={size}
      style={{ display: 'block', flexShrink: 0 }}
    >
      {BADGE_ICONS[category](level, color, fill)}
    </svg>
  );
}
```

---

### Specs SVG par catégorie

> Toutes les formes sont données en coordonnées pour `viewBox="0 0 40 40"`.
> `C` = couleur de catégorie. `F` = fill (transparent si L1, catégorie si L3+).

#### PROSPECTEUR — Téléphone combiné

```
Forme de base : combiné téléphone en L miroir
- Arc gauche (oreille) : rect x=8 y=8 w=8 h=8
- Corps central : rect x=8 y=14 w=24 h=12
- Arc droit (micro) : rect x=24 y=24 w=8 h=8
- Espace vide intérieur (écran) : rect x=11 y=17 w=18 h=6, fill=bg

path M12 8 L20 8 L20 32 L12 32  (colonne gauche du combiné)
path M28 8 L20 8   (bras horizontal haut)
path M28 32 L20 32 (bras horizontal bas)
```

**L1** : stroke only, strokeWidth=1.5, fill=none
**L2** : fill=`${C}30` (10% opacité couleur) + stroke + petit rect blanc 4×4 au centre (bouton)
**L3** : fill=C + 3 petits arcs de signal à droite (rects 2×4, 2×6, 2×8 espacés de 2px)
**L4** : comme L3 + stroke=#FFD700 strokeWidth=1 + pixel crown

Implémentation simplifiée recommandée :
```jsx
// Combiné = 2 rects + 1 ligne centrale
<rect x="9" y="8" width="10" height="7" fill={lv>=2?color:'none'} stroke={color} strokeWidth="1.5"/>
<rect x="21" y="25" width="10" height="7" fill={lv>=2?color:'none'} stroke={color} strokeWidth="1.5"/>
<rect x="9" y="13" width="22" height="14" fill={lv>=3?color:lv>=2?color+'30':'none'} stroke={color} strokeWidth="1.5"/>
{/* Signal arcs L3+ */}
{lv>=3 && [0,1,2].map(i => <rect key={i} x={34} y={14+i*4} width={2} height={3} fill={color}/>)}
{/* Crown L4 */}
{lv===4 && PIXEL_CROWN}
```

---

#### CONNAISSEUR — Bâtiment / Compte client

```
Icône : immeuble de bureaux stylisé (représente "un compte = une entreprise")
Base commune : rect x=10 y=12 w=20 h=24 (façade) + rect x=16 y=8 w=8 h=5 (enseigne/toiture)

Fenêtres (W) = rect 3×3, disposées en grille 2 colonnes × N rangées
  Col gauche : x=13  Col droite : x=22
  Rangées : y=16, y=21, y=26, y=31

L1 — Petit immeuble (2 rangées de fenêtres) :
  Façade : outline seulement (fill=none, stroke=color, strokeWidth=1.5)
  2 fenêtres : (13,16) et (22,16)
  Porte : rect x=17 y=30 w=6 h=6

L2 — Immeuble 3 rangées + drapeau :
  Façade fill=`${color}30`
  3 rangées de fenêtres (6 rects 3×3)
  Drapeau : line x1=20 y1=8 x2=20 y2=3 + rect x=20 y=3 w=6 h=3 fill=color

L3 — Grand immeuble fill complet + 4 rangées :
  Façade fill=color
  Fenêtres fill=white (4 rangées, 8 rects)
  Drapeau fill=color (plus grand : rect w=8 h=4)
  Porte fill=white

L4 — L3 + pixel crown + stroke=#FFD700 sur façade + fenêtres dorées :
  Fenêtres fill=#FFD700 (au lieu de white)
  stroke=#FFD700 strokeWidth=1 sur rect façade
  + pixel crown
```

---

#### CHASSEUR — Cible / Target

```
3 cercles concentriques + crosshair + flèche plantée (L3+)

L1 : circle cx=20 cy=20 r=12, circle cx=20 cy=20 r=3 (filled center dot)
L2 : + circle cx=20 cy=20 r=7 (anneau intermédiaire)
L3 : L2 + 4 lignes crosshair :
     line x1=20 y1=5 x2=20 y2=13  (haut)
     line x1=20 y1=27 x2=20 y2=35 (bas)
     line x1=5 y1=20 x2=13 y2=20  (gauche)
     line x1=27 y1=20 x2=35 y2=20 (droite)
L4 : L3 + flèche plantée en haut-droite :
     polygon points="34,4 30,8 19,19 23,23 34,4" (corps flèche)
     + pixel crown
```

---

#### ÉLEVEUR — Plante qui pousse

```
Tronc : rect x=18 y=22 w=4 h=14 (ancre basse commune à tous les levels)

L1 — Pousse :
  Tronc court : rect x=19 y=28 w=2 h=6
  Feuille gauche : polygon points="19,28 11,20 15,20" (triangle)
  Feuille droite : polygon points="21,28 29,20 25,20"

L2 — Plante :
  Tronc : rect x=19 y=20 w=2 h=14
  2 feuilles L + 2 feuilles R :
    polygon points="19,24 10,18 14,22"
    polygon points="21,24 30,18 26,22"
    polygon points="19,20 11,14 15,18"
    polygon points="21,20 29,14 25,18"

L3 — Arbre :
  Tronc : rect x=17 y=22 w=6 h=12
  Feuillage : rect x=8 y=8 w=24 h=16 (bloc carré brutaliste, fill=color)
  + rect x=12 y=5 w=16 h=6 (sommet plus étroit)

L4 — Grand arbre :
  Tronc : rect x=17 y=22 w=6 h=14
  Feuillage L3 +
  Racines : polygon points="17,36 11,36 17,30" (gauche) + polygon points="23,36 29,36 23,30" (droite)
  + pixel crown (en vert #007A10 ou gold)
```

---

#### RECRUTEUR — Silhouette(s)

```
Personne = tête (circle r=4) + corps (rect w=10 h=10, coins square)

Personne centrée :
  Tête : circle cx=20 cy=11 r=4
  Corps : rect x=15 y=17 w=10 h=11

L1 : 1 personne, outline, fill=none
L2 : 1 personne filled + checkmark ✓ à droite :
     polyline points="26,16 28,19 33,14" stroke=color fill=none strokeWidth=2
L3 : 2 personnes côte à côte (décalées -6/+6) + trait de connexion entre elles :
     Personne gauche : cx=15, corps x=10
     Personne droite : cx=25, corps x=20
     Ligne : line x1=16 y1=22 x2=24 y2=22
L4 : 3 personnes (cx=11, cx=20, cx=29) + 2 lignes de connexion + pixel crown
```

---

#### GESTIONNAIRE — Clipboard

```
Clipboard base :
  Board : rect x=8 y=10 w=24 h=24
  Clip top : rect x=16 y=6 w=8 h=6
  Inner area : rect x=11 y=14 w=18 h=17 (fond blanc/clair)

L1 : outline + 3 lignes vides :
     line x1=13 y1=18 x2=27 y2=18
     line x1=13 y1=22 x2=27 y2=22
     line x1=13 y1=26 x2=22 y2=26

L2 : board filled (léger) + checkmarks sur les 3 lignes :
     polyline points="13,18 15,21 20,16" (check 1)
     polyline points="13,22 15,25 20,20" (check 2)

L3 : board filled (color) + mini bar chart dans le board :
     rect x=14 y=26 w=3 h=4 fill=white (barre 1)
     rect x=19 y=22 w=3 h=8 fill=white (barre 2)
     rect x=24 y=24 w=3 h=6 fill=white (barre 3)

L4 : L3 + pixel crown + stroke=#FFD700 sur le board border
```

---

#### PRODUCTIF — Fusée

```
L1 — Flèche oblique :
  polygon points="24,8 32,8 32,16 20,28 18,26" (corps flèche haut-droite)
  + pointe : polygon points="22,26 28,20 30,22 24,28"

L2 — Fusée simple :
  Corps : polygon points="20,6 27,20 27,30 13,30 13,20" (pentagone vertical)
  Aileron gauche : polygon points="13,20 8,28 13,28"
  Aileron droit : polygon points="27,20 32,28 27,28"
  Hublot : circle cx=20 cy=18 r=3

L3 — Fusée + flamme :
  Fusée L2 (filled color) +
  Flamme : polygon points="14,30 20,40 26,30" fill=#FF3D2E (ou orange #F59E0B)

L4 — Fusée + flamme + étoiles :
  L3 +
  3 petites étoiles (rects 2×2) : [5,8], [33,12], [7,22]
  + pixel crown
  + stroke=#FFD700 sur corps fusée
```

---

#### NETWORKER — Réseau de nœuds

```
Nœud = circle r=3 (filled)
Lien = line strokeWidth=1.5

L1 : 3 nœuds en triangle :
  circle cx=20 cy=8 r=3   (haut)
  circle cx=11 cy=28 r=3  (bas gauche)
  circle cx=29 cy=28 r=3  (bas droite)
  line x1=20 y1=11 x2=13 y2=25
  line x1=20 y1=11 x2=27 y2=25
  line x1=14 y1=28 x2=26 y2=28

L2 : 5 nœuds (+ 2 sur les côtés) + 4 liens supplémentaires :
  + circle cx=5 cy=18 r=3
  + circle cx=35 cy=18 r=3
  + lignes vers nœuds latéraux

L3 : 7 nœuds (hexagone + centre) avec tous les liens vers le centre :
  Centre : circle cx=20 cy=20 r=3
  6 nœuds périphériques à r=12 du centre (0°, 60°, 120°, 180°, 240°, 300°)
  + 6 lignes centre→périphérie

L4 : L3 + 3 liens entre nœuds périphériques (croisés) + pixel crown
```

---

#### RELANCEUR — Flèches circulaires

```
L1 — Cycle simple :
  Arc (270°) : path d="M20 8 A12 12 0 1 1 9 26" stroke=color fill=none strokeWidth=2
  Tête flèche : polygon points="7,22 9,30 15,26" fill=color

L2 — Double cycle :
  Arc extérieur sens horaire (L1)
  Arc intérieur sens anti-horaire : path d="M20 32 A12 12 0 1 0 31 14" stroke=color fill=none strokeWidth=2
  + 2 têtes de flèche

L3 — Triple rotation + point central :
  L2 +
  circle cx=20 cy=20 r=3 fill=color (centre)
  + trait de vitesse : line x1=20 y1=20 x2=32 y2=12 stroke=color strokeWidth=1 opacity=0.5

L4 — Infini + éclair :
  path d="M8 20 C8 14 14 14 20 20 C26 26 32 26 32 20 C32 14 26 14 20 20 C14 26 8 26 8 20"
        stroke=color fill=none strokeWidth=2.5 (symbole ∞)
  Éclair au centre : polygon points="21,14 18,21 21,21 19,26 22,19 19,19" fill=color
  + pixel crown
```

---

## 6. Composant `BADGE_ICONS` map complète

```jsx
// Toutes les icônes sont des fonctions (level, color, fillColor) => JSX
const BADGE_ICONS = {
  prospecteur:  (lv, color) => (/* voir specs ci-dessus */),
  chasseur:     (lv, color) => (/* ... */),
  eleveur:      (lv, color) => (/* ... */),
  connaisseur:  (lv, color) => (/* bâtiment — voir specs ci-dessus */),
  recruteur:    (lv, color) => (/* ... */),
  gestionnaire: (lv, color) => (/* ... */),
  productif:    (lv, color) => (/* ... */),
  networker:    (lv, color) => (/* ... */),
  relanceur:    (lv, color) => (/* ... */),
};

// Pixel crown helper réutilisable
const PIXEL_CROWN = (
  <>
    <rect x="11" y="4" width="3" height="3" fill="#FFD700"/>
    <rect x="15" y="2" width="3" height="3" fill="#FFD700"/>
    <rect x="19" y="1" width="3" height="3" fill="#FFD700"/>
    <rect x="23" y="2" width="3" height="3" fill="#FFD700"/>
    <rect x="27" y="4" width="3" height="3" fill="#FFD700"/>
  </>
);
```

> **Note pour Claude Code** : Les specs ci-dessus donnent la géométrie précise. Pour chaque catégorie, implémenter les 4 levels dans une fonction switch(lv). Toutes les formes doivent respecter le style DA brutalist : coins à 90°, strokeWidth entre 1.5 et 2.5, pas de filter/shadow/gradient. Les fills de level 2 peuvent utiliser `${color}40` (25% opacité via hex alpha). Level 3 : fill plein. Level 4 : fill + stroke gold sur les bords principaux.

---

## 7. BADGE_META

```js
const BADGE_META = {
  prospecteur:  { label:'Prospecteur', color:'#4A7FE5', titles:['Prospecteur','Accrocheur','Négociateur','Maître du Pitch'],       unit:'contacts appelés' },
  chasseur:     { label:'Chasseur',    color:'#FF3D2E', titles:['Éclaireur','Pisteur','Chasseur','Prédateur'],                    unit:'comptes distincts avec mission' },
  eleveur:      { label:'Éleveur',     color:'#00C218', titles:['Semeur','Cultivateur','Éleveur','Patriarche'],                   unit:'comptes avec ≥2 missions' },
  connaisseur:  { label:'Connaisseur', color:'#10B981', titles:['Habitué','Familier','Connaisseur','Référent'],                   unit:'missions sur le même compte' },
  recruteur:    { label:'Recruteur',   color:'#8B5CF6', titles:['Talent Finder','Recruteur','Chasseur de Têtes','DRH Upgrade'],   unit:'consultants missionnés' },
  gestionnaire: { label:'Gestionnaire',color:'#F59E0B', titles:['Coordinateur','Chef de Projet','Gestionnaire','Pilote'],        unit:'suivis loggés' },
  productif:    { label:'Productif',   color:'#06B6D4', titles:['Lanceur','Transformeur','Closer','Machine à Closer'],           unit:'besoins closés' },
  networker:    { label:'Networker',   color:'#6366F1', titles:['Connecté','Networker','Hub','Super Connecteur'],                unit:'contacts CRM' },
  relanceur:    { label:'Relanceur',   color:'#EC4899', titles:['Persévérant','Ténace','Bulldozer','Inépuisable'],               unit:'relances effectuées' },
};
```

---

## 8. Composants UI

### 8.1 Badge intégré dans le bouton profil (header)

**Emplacement** : directement dans le **bouton "Nicolas Serradeil ▾"** existant dans la barre de header. Le bouton passe à **2 lignes** :

```
┌──────────────────────────────────┐
│  [N]  Nicolas Serradeil  ▾       │  ← ligne 1 : avatar + nom + flèche (inchangé)
│       [icon 14px] NÉGOCIATEUR    │  ← ligne 2 : badge icon + titre (nouveau)
└──────────────────────────────────┘
```

Click sur le bouton → ouvre le dropdown profil comme avant. **Pas d'interaction séparée pour le badge dans le bouton.**

**Structure JSX du bouton** :
```jsx
<button onClick={() => setShowMenu(v => !v)} style={{ display:'flex', alignItems:'center', gap:8, padding:'4px 10px' }}>
  {/* Avatar — inchangé */}
  <span style={{ background:'#00C218', color:'white', fontWeight:700, fontSize:13, width:24, height:24, display:'flex', alignItems:'center', justifyContent:'center' }}>
    {profile.nom[0]}
  </span>

  {/* Bloc texte 2 lignes */}
  <div style={{ display:'flex', flexDirection:'column', alignItems:'flex-start', gap:2 }}>
    <span style={{ fontSize:13, fontWeight:600, color:'#1C1F35', lineHeight:1 }}>
      {profile.nom}
    </span>
    {achievements && badgeLevel > 0 && (
      <span style={{ display:'flex', alignItems:'center', gap:3 }}>
        <BadgeIcon category={badgeCategory} level={badgeLevel} size={14} />
        <span style={{
          fontSize:10, fontWeight:700, lineHeight:1,
          color: BADGE_META[badgeCategory].color,
          letterSpacing:'0.05em', textTransform:'uppercase'
        }}>
          {BADGE_META[badgeCategory].titles[badgeLevel - 1]}
        </span>
      </span>
    )}
  </div>

  <Icon d={ICONS.chevronDown} size={12} />
</button>
```

> Si aucun badge acquis (tous L0) : le bouton reste 1 ligne, comportement inchangé.

**Badge dans le dropdown** : le badge reste **aussi présent dans le dropdown**, sous l'email, avec un comportement cliquable vers Paramètres > Exploits.

```
┌──────────────────────────────────┐
│  Nicolas Serradeil               │
│  nicolas.serradeil@upgrade.fr    │
│                                  │
│  [icon 20px]  NÉGOCIATEUR  →     │  ← cliquable → Paramètres > Exploits
│                                  │
│  ────────────────────────────    │
│  MON COMPTE                      │
│  ⚙ Paramètres                    │
│  📅 Synchronisation calendrier   │
└──────────────────────────────────┘
```

```jsx
{/* Dans le dropdown, sous l'email */}
{achievements && badgeLevel > 0 && (
  <div
    onClick={() => { setScreen('parametres'); setParamTab('exploits'); setShowMenu(false); }}
    style={{ display:'flex', alignItems:'center', gap:6, margin:'8px 0 4px', cursor:'pointer', padding:'4px 6px', border:`1px solid ${BADGE_META[badgeCategory].color}30`, background:`${BADGE_META[badgeCategory].color}08` }}
  >
    <BadgeIcon category={badgeCategory} level={badgeLevel} size={20} />
    <span style={{ fontSize:11, fontWeight:700, flex:1, color: BADGE_META[badgeCategory].color, letterSpacing:'0.06em', textTransform:'uppercase' }}>
      {BADGE_META[badgeCategory].titles[badgeLevel - 1]}
    </span>
    <span style={{ fontSize:10, color:'#999' }}>→</span>
  </div>
)}
```

**Logique de résolution** (commune au bouton header et au dropdown) :
```js
// displayedBadge = 'auto' | 'category:level' (ex: 'recruteur:2')
const { category: badgeCategory, level: badgeLevel } = resolveDisplayedBadge(prefs, achievements);

function resolveDisplayedBadge(prefs, achievements) {
  if (!prefs.displayedBadge || prefs.displayedBadge === 'auto') {
    return resolveTopBadge(achievements); // { category, level } du meilleur badge
  }
  const [category, levelStr] = prefs.displayedBadge.split(':');
  const level = parseInt(levelStr);
  const currentLevel = getLevel(category, achievements[category] || 0);
  if (currentLevel === 0) return resolveTopBadge(achievements); // fallback si catégorie non débloquée
  return { category, level: Math.min(level, currentLevel) };
}
```

### 8.2 Page "Exploits" — 4ème onglet de Paramètres

**⚠️ Pas de modal, pas de screen séparé.**
Les Exploits sont un **4ème onglet dans la page Paramètres** existante.

Tabs Paramètres : `"Profil & Sécurité"` | `"Calendrier ICS"` | `"Préférences"` | **`"Exploits"`**

**Accès** :
- Click badge dans le dropdown → `setScreen('parametres'); setParamTab('exploits')`
- Navigation directe : Paramètres → onglet "Exploits"

> Note pour Claude Code : ne pas créer de screen `'exploits'` ni de modal. Réutiliser le screen `'parametres'` et ajouter `paramTab === 'exploits'` comme 4ème cas dans le switch/if des tabs. **Si une version modale ou un screen séparé a déjà été implémenté, le supprimer.**

**Structure** :
```
Header :
  Titre "EXPLOITS" + nom du commercial + agence
  Score global = Σ(level × 100 + pct)
  Badges acquis : X / 36 (9 catégories × 4 levels)

Grille : grid-template-columns: repeat(3, 1fr), gap:12px  ← 3 colonnes pour 9 badges
  Ligne 1 : Prospecteur  | Chasseur     | Éleveur
  Ligne 2 : Connaisseur  | Recruteur    | Gestionnaire
  Ligne 3 : Productif    | Networker    | Relanceur
```

### 8.3 BadgeCard

```
┌──────────────────────────────┐
│  [BadgeIcon 48px]            │  centré
│  PROSPECTEUR                 │  uppercase 10px, gris si L0
│  Négociateur  ★★★☆           │  titre + étoiles level, couleur catégorie
│  ████████░░░  61%            │  barre progression, fill=color
│  853 / 1 999 contacts        │  stat courante / prochain seuil
└──────────────────────────────┘
```

Style si L0 : `filter:grayscale(1)`, border `#E0E0E0`, fond `#F5F5F5`, + 🔒 overlay coin haut-droit

### 8.4 BadgeDetailPanel — panneau latéral

Slide-in depuis la droite, même style que les autres panels CRM.

**Sections** :

**1. Header du panel** — icône + catégorie + level, **sans bouton Sélectionner ici**
```
┌──────────────────────────────────────────┐
│  [BadgeIcon 64px]                        │
│  Connecté                                │  ← titre du level actuel
│  NETWORKER · JUNIOR                      │  ← catégorie + level label
│  ■ □ □ □                                 │  ← 4 carrés niveaux
└──────────────────────────────────────────┘
```

**2. Barre de progression** : `232 / 300 contacts CRM` + barre fill=color

**3. Section PROGRESSION** — liste des 4 niveaux avec checkmarks

Le bouton **"Sélectionner"** apparaît sur **chaque niveau débloqué** (level ≤ currentLevel), pas uniquement le plus haut. Cela permet de choisir d'afficher un titre inférieur (ex : afficher "Recruteur" L2 plutôt que "Chasseur de Têtes" L3).

```
PROGRESSION

✓  Talent Finder               [Sélectionner]   ← L1 débloqué → bouton
   Junior · 1+ consultants missionnés

✓  Recruteur                   [✓ Sélectionné]  ← L2 débloqué + actuellement affiché
   Confirmé · 10+ consultants missionnés

✓  Chasseur de Têtes           [Sélectionner]   ← L3 débloqué → bouton
   Senior · 15+ consultants missionnés

□  DRH Upgrade                                  ← L4 non débloqué → pas de bouton
   Expert · 31+ consultants missionnés
```

**Format de stockage** — `displayedBadge` stocke **catégorie + level** :
```js
// Dans profile.preferences
displayedBadge: 'auto'              // défaut : meilleur level toutes catégories
displayedBadge: 'recruteur:2'       // Recruteur, level 2 "Recruteur"
displayedBadge: 'recruteur:3'       // Recruteur, level 3 "Chasseur de Têtes"
displayedBadge: 'prospecteur:1'     // Prospecteur, level 1 "Prospecteur"
```

**Résolution** :
```js
function resolveDisplayedBadge(prefs, achievements) {
  if (!prefs.displayedBadge || prefs.displayedBadge === 'auto') {
    return resolveTopBadge(achievements); // { category, level }
  }
  const [category, levelStr] = prefs.displayedBadge.split(':');
  const level = parseInt(levelStr);
  // Vérifier que le level est toujours débloqué (score peut pas régresser mais par sécurité)
  const currentLevel = getLevel(category, achievements[category]);
  return { category, level: Math.min(level, currentLevel) };
}
```

**Règles du bouton** :
- Présent sur **chaque ligne de level débloqué** (`i + 1 <= currentLevel`)
- Si `displayedBadge === 'category:level'` pour cette ligne → `[✓ Sélectionné]`, couleur catégorie, désactivé
- Sinon → `[Sélectionner]`, fond midnight, texte blanc, actif
- Click → `handleSavePrefs({ ...prefs, displayedBadge: \`${category}:${level}\` })`
- Level verrouillé (□) → pas de bouton

```jsx
// Dans la liste PROGRESSION, pour chaque niveau i (0-based, level = i+1)
const levelKey = `${category}:${i+1}`;
const isThisSelected = prefs.displayedBadge === levelKey;
const isUnlocked = (i + 1) <= currentLevel;

{isUnlocked && (
  <button
    onClick={() => handleSavePrefs({ ...prefs, displayedBadge: levelKey })}
    disabled={isThisSelected}
    style={{
      fontSize:10, fontWeight:700, padding:'3px 8px',
      cursor: isThisSelected ? 'default' : 'pointer',
      border: isThisSelected ? `1px solid ${color}` : '1px solid #1C1F35',
      background: isThisSelected ? `${color}15` : '#1C1F35',
      color: isThisSelected ? color : 'white',
      letterSpacing:'0.04em', whiteSpace:'nowrap'
    }}
  >
    {isThisSelected ? '✓ Sélectionné' : 'Sélectionner'}
  </button>
)}
```

**4. Mes stats** : chiffres spécifiques à la catégorie

**5. Prochaine étape** : texte humain + CTA vers l'onglet concerné si L0

---

## 9. Fetch au mount

```js
async function loadAchievements(profileNom) {
  const [rProsp, rMissions, rRecruteur, rGest, rProductif, rNetwork, rRelance] =
    await Promise.all([
      // 1. PROSPECTEUR : contacts appelés en sessions
      sb.from('session_prospection_contacts')
        .select('id, sessions_prospection!inner(responsable)', { count:'exact', head:true })
        .eq('sessions_prospection.responsable', profileNom),

      // 2+3+4. CHASSEUR / ÉLEVEUR / CONNAISSEUR : toutes les missions du responsable avec leur compte
      //        Une seule requête pour les 3 badges (évite les requêtes redondantes)
      sb.from('missions')
        .select('contact_referent_id')
        .eq('responsable', profileNom)
        .not('contact_referent_id', 'is', null),

      // 5. RECRUTEUR : missions issues d'un besoin
      sb.from('missions')
        .select('id', { count:'exact', head:true })
        .eq('responsable', profileNom)
        .not('besoin_id', 'is', null),

      // 6. GESTIONNAIRE : suivis loggés
      sb.from('historique_missions')
        .select('id', { count:'exact', head:true })
        .eq('responsable', profileNom),

      // 7. PRODUCTIF : besoins transformés en mission
      sb.from('besoins')
        .select('id', { count:'exact', head:true })
        .eq('statut', 'pourvu')
        .eq('responsable', profileNom),

      // 8. NETWORKER : contacts dans le CRM
      sb.from('contacts')
        .select('id', { count:'exact', head:true })
        .eq('responsable', profileNom),

      // 9. RELANCEUR : relances de session complétées
      sb.from('taches')
        .select('id', { count:'exact', head:true })
        .eq('statut', 'fait')
        .eq('responsable', profileNom)
        .not('session_prospection_id', 'is', null),
    ]);

  // CHASSEUR : comptes distincts avec ≥ 1 mission
  // ÉLEVEUR  : comptes avec ≥ 2 missions
  // CONNAISSEUR : MAX missions sur un même compte
  const byClient = {};
  (rMissions.data || []).forEach(m => {
    byClient[m.contact_referent_id] = (byClient[m.contact_referent_id] || 0) + 1;
  });
  const counts = Object.values(byClient);
  const nbChasseur    = counts.length;                                // comptes distincts
  const nbEleveur     = counts.filter(n => n >= 2).length;           // comptes avec ≥2 missions
  const nbConnaisseur = counts.length > 0 ? Math.max(...counts) : 0; // max missions sur 1 compte

  return {
    prospecteur:  rProsp.count      || 0,
    chasseur:     nbChasseur,
    eleveur:      nbEleveur,
    connaisseur:  nbConnaisseur,
    recruteur:    rRecruteur.count  || 0,
    gestionnaire: rGest.count       || 0,
    productif:    rProductif.count  || 0,
    networker:    rNetwork.count    || 0,
    relanceur:    rRelance.count    || 0,
  };
}
```

Recalculer après : `handleTerminer`, `handleSaveContact`, `handleCreateContact`, `handleSaveMission`, `handleSaveBesoin` (statut→pourvu), `handleCompleteTask`, `handleSaveSuivi`.

---

## 10. Acceptance criteria

- [ ] Icônes 100% SVG inline — aucun asset externe, aucune image
- [ ] L4 a toujours le pixel crown gold (5 rects) et stroke gold sur les bords principaux
- [ ] L0 : icône grisée + `opacity:0.3` + badge 🔒 coin haut-droit de la BadgeCard
- [ ] Badge visible dans le **dropdown profil** sous l'email, pas dans la barre header
- [ ] Click badge dans le dropdown → ferme dropdown + ouvre Paramètres onglet "Exploits"
- [ ] Page Exploits = **4ème onglet de Paramètres** (pas de modal, pas de screen séparé)
- [ ] Si une modal/screen Exploits a été implémentée → supprimée
- [ ] Grille Exploits en 3×3 (9 badges)
- [ ] Score affiché : X / 36 (9 × 4)
- [ ] Barre de progression affiche la bonne valeur `score / nextSeuil`
- [ ] Score global s'affiche en tête de page
- [ ] Après action (ex: terminer session), achievements re-fetchés sans full reload
- [ ] Nicolas affiche "Négociateur" (L3, 853 contacts) au lancement
- [ ] Bouton "Sélectionner" dans le BadgeDetailPanel pour choisir le badge affiché
- [ ] Bouton devient "✓ Sélectionné" (désactivé, couleur catégorie) si déjà sélectionné
- [ ] Bouton absent si badge L0 (non acquis)
- [ ] Choix persisté dans `profile.preferences.displayedBadge`
- [ ] Aucun leaderboard / comparaison inter-commerciaux
- [ ] CHASSEUR et CONNAISSEUR calculés depuis la même requête `missions` (optimisation)
- [ ] CONNAISSEUR affiche "X missions sur votre meilleur compte" dans le detail panel

---

## 11. Évolutions V2 (hors scope)

- Toast "🎉 Nouveau titre : Négociateur !" au passage de seuil (useEffect sur achievements)
- Feed équipe opt-in : "Léa vient de débloquer Closer 🚀"
- Titre dans signature email / Slack : `Nicolas Serradeil • Négociateur 🎯`
- Badge "Vétéran" : ancienneté CRM (date profil.created_at)
- Badge "Fantôme" : contacts injoignables retrouvés et relancés avec succès
