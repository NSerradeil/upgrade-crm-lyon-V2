# SPEC — KPI Card Sessions (tab Prospection)

**Fichier cible :** `supabase/CRM_Live.html`
**Composant concerné :** `CardSessions` dans le tab Prospection
**Deploy :** `bash supabase/deploy_staging.sh` → **staging uniquement, jamais main**

> **Instructions Claude Code :** utiliser les patterns "Simplifier Superpowers" et "Frontend UI Skill". Réutiliser les composants `CardHeader` et le système de coordonnées `CH` déjà en place dans le TDB (`SPEC_TDB_multikpi.md`).

---

## Contexte

La card Sessions affiche une **vue annuelle sous forme de barres empilées par mois** (Jan–Déc). Chaque barre est décomposée en 3 segments selon le résultat de l'appel : Intéressés, Injoignables, Pas intéressés. Ce sont les 3 outcomes directs d'un appel — les relances sont une action dérivée, elles n'apparaissent pas ici.

---

## 1. Données source

### Requête Supabase — agrégat mensuel

```js
// Charger les sessions terminées de l'année en cours, groupées par mois
const { data } = await sb
  .from('sessions_prospection')
  .select('date_session, nb_contacts, nb_interesses, nb_injoignables, nb_pas_interesses')
  .eq('statut', 'done')
  .gte('date_session', `${annee}-01-01`)
  .lte('date_session', `${annee}-12-31`)
  .order('date_session', { ascending: true });
```

### Agrégation côté client — tableau des 12 mois

```js
const MOIS_LABELS = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];

// Initialiser 12 mois à zéro
const parMois = MOIS_LABELS.map((m, i) => ({
  m, idx: i, n: 0, int: 0, inj: 0, pas: 0, tot: 0,
}));

// Remplir avec les données
data.forEach(row => {
  const i = new Date(row.date_session).getMonth();
  parMois[i].n   += 1;
  parMois[i].int += row.nb_interesses      || 0;
  parMois[i].inj += row.nb_injoignables    || 0;
  parMois[i].pas += row.nb_pas_interesses  || 0;
  parMois[i].tot += row.nb_contacts        || 0;
});
```

---

## 2. Système de coordonnées du chart

```js
const CHS = { TOTAL: 170, TOP: 26, BOT: 22, H: 122 };
// TOTAL = hauteur totale du conteneur (px)
// TOP   = espace au-dessus des barres (labels taux d'intérêt + nb sessions)
// BOT   = espace en bas (labels mois)
// H     = hauteur dessinable pour les barres (= TOTAL - TOP - BOT)
```

Même principe que `CH` du TDB : positionnement absolu, pas de flex pour les barres.

```js
// Hauteur d'un segment
const segH = (valeur / maxTot) * CHS.H;
// maxTot = Math.max(...parMois.map(m => m.tot), 1)
```

---

## 3. Segments — définition

3 segments seulement. **Les relances ne figurent pas ici** — elles sont une action déclenchée depuis le résultat, pas un outcome de l'appel.

```js
const SEG_DEFS = [
  { key: 'int', color: C.green,    label: 'Intéressés'     },
  { key: 'inj', color: '#bbb',     label: 'Injoignables'   },
  { key: 'pas', color: '#e8e8e8',  label: 'Pas intéressés' },
];
```

**Ordre d'empilement (bas → haut) :** Intéressés (vert, en bas), Injoignables (gris), Pas intéressés (gris clair, en haut). Les résultats les plus positifs en bas — lecture naturelle.

---

## 4. Composant `CardSessions`

### 4a. Header

Utiliser le header midnight standard (même que les autres cards KPI), avec :
- Titre : `Sessions {annee}` (ex. `Sessions 2026`)
- Count : `{totalSessions} sessions · {totalContacts} contacts`
- Taux global YTD en couleur (vert/jaune/rouge selon seuils 25%/10%) : `{tauxGlobal}% intéressés`

```js
const totalSessions = parMois.reduce((a, m) => a + m.n,   0);
const totalContacts = parMois.reduce((a, m) => a + m.tot, 0);
const totalInt      = parMois.reduce((a, m) => a + m.int, 0);
const tauxGlobal    = totalContacts > 0 ? Math.round((totalInt / totalContacts) * 100) : 0;
const tauxColor     = tauxGlobal >= 25 ? C.green : tauxGlobal >= 10 ? C.yellow : C.red;
```

### 4b. Légende

Bande fine sous le header (fond `#fafafa`, `borderBottom: 1px solid ${C.border}`) avec les 3 pictos couleur + label.

### 4c. Chart — barres empilées

Conteneur : `position: relative`, `height: CHS.TOTAL`, `display: flex` (12 colonnes `flex: 1`).

Pour chaque mois :

```jsx
// Calcul des segments
let cumH = 0;
const segs = SEG_DEFS.map(seg => {
  const h   = (m[seg.key] / maxTot) * CHS.H;
  const bot = CHS.BOT + cumH;
  cumH += h;
  return { ...seg, h, bot };
});
const totalBarH = (m.tot / maxTot) * CHS.H;
const tauxInt   = m.tot > 0 ? Math.round((m.int / m.tot) * 100) : null;

// Rendu des segments
segs.map(seg => seg.h > 0.5 && (
  <div style={{
    position: 'absolute',
    bottom:   seg.bot,
    left: 2, right: 2,
    height:   seg.h,
    background: seg.color,
    outline: isSelected ? `1px solid ${C.blue}` : 'none',
    opacity: isFuture ? 0.2 : 0.85,
  }} />
))
```

### 4d. Labels au-dessus de chaque barre

Deux labels empilés au-dessus de la barre :

| Label | Position | Contenu | Style |
|---|---|---|---|
| Nb sessions | `bottom: CHS.BOT + totalBarH + 13` | `{n}s` (ex. `2s`) | 8px, couleur mois courant = `C.blue`, sinon `#bbb` |
| Taux d'intérêt | `bottom: CHS.BOT + totalBarH + 3` | `{taux}%` | 8px, couleur vert/jaune/rouge selon seuils 25%/10% |

Afficher uniquement si `m.tot > 0`.

### 4e. Label mois + indicateur mois courant

```js
const CURRENT_MONTH = new Date().getMonth(); // 0-indexed
const isCurrent = m.idx === CURRENT_MONTH;
const isFuture  = m.idx > CURRENT_MONTH;
```

- **Label mois** : `bottom: 4`, centered, 9px. Mois courant → `fontWeight: 900, color: C.blue`. Futur → `color: '#ddd'`. Passé → `color: '#999'`.
- **Point bleu indicateur** : carré `4×4px`, `background: C.blue`, centré horizontalement, `bottom: CHS.BOT - 5` — uniquement sur le mois courant.

### 4f. Interaction — clic sur un mois

Cliquer sur une colonne qui a des données (`m.tot > 0`) sélectionne ce mois :

```js
const [selectedMonth, setSelectedMonth] = useState(null);
// Clic : toggle (clic sur mois déjà sélectionné → désélectionne)
onClick={() => m.tot > 0 && setSelectedMonth(isSelected ? null : m.idx)}
```

Le mois sélectionné affiche un `outline: 1px solid ${C.blue}` sur ses segments.

---

## 5. Bloc détail du mois sélectionné

Apparaît juste en dessous du chart, collé à lui (`margin: 0 18px 16px`), séparé par `borderTop: 3px solid ${C.blue}`, fond `#f5f8ff`.

Contenu : nom du mois + nb sessions + total contacts en titre, puis 4 mini-blocs chiffrés côte à côte (les 3 segments + un bloc "Total appelés") :

```jsx
{SEG_DEFS.map(seg => (
  <div style={{
    background: C.snow,
    border: `1px solid ${C.border}`,
    borderLeft: `4px solid ${seg.color}`,
    padding: '8px 12px',
  }}>
    <div style={{ fontSize:20, fontWeight:900, color: seg.color }}>{m[seg.key]}</div>
    <div style={{ fontSize:9, textTransform:'uppercase', color:'#bbb' }}>{seg.label}</div>
    <div style={{ fontSize:9, color:'#ccc' }}>{Math.round((m[seg.key]/m.tot)*100)}%</div>
  </div>
))}

{/* Bloc total */}
<div style={{ borderLeft: `4px solid ${C.mid}`, ... }}>
  <div>{m.tot}</div>
  <div>Total appelés</div>
  <div style={{ color: tauxColor }}>{Math.round((m.int/m.tot)*100)}% intérêt</div>
</div>
```

---

## 6. Style de la KPI card Sessions à l'état actif

Quand la card Sessions est active (sélectionnée dans les 4 KPI cards du haut), **toutes les bordures disparaissent** — seuls le fond midnight et la shadow offset bleue restent. Même fix que les autres cards KPI déjà corrigées.

```jsx
const active = activeKpi === 'sessions';

style={{
  background:   active ? C.midnight : C.snow,
  borderTop:    active ? '0' : `2px solid ${C.border}`,
  borderRight:  active ? '0' : `2px solid ${C.border}`,
  borderBottom: active ? '0' : `2px solid ${C.border}`,
  borderLeft:   active ? '0' : `5px solid ${C.blue}`,
  boxShadow:    active ? `4px 4px 0 ${C.blue}` : 'none',
  transform:    active ? 'translate(-2px,-2px)' : 'none',
  transition:   'all 120ms',
}}
```

---

## 7. Ce que cette card ne fait PAS

- Pas de bouton "Ignorer" ni de dismiss — lecture seule.
- Pas de bouton "Voir tout" / `VoirToutPanel` — toute l'année est affichée d'un coup dans le chart.
- Pas de clic → `SessionDetailPanel` depuis cette card (la vue détail d'une session s'ouvre depuis la **liste** des sessions en dessous du chart, pas depuis les barres).
- Les relances ne figurent pas dans les segments — elles appartiennent à la card Relances.
