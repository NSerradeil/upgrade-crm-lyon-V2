# SPEC — Tableau de bord interactif multi-KPI

**Fichier cible :** `supabase/CRM_Live.html`
**Composant cible :** `TabTDB` (ligne ~3446)
**Deploy :** `bash supabase/deploy_staging.sh` → **staging uniquement, ne jamais pousser sur main**

---

## 1. Contexte & objectif

Le tableau de bord actuel (`TabTDB`) affiche 4 dalles KPI statiques + un graphique CA fixe en dessous.
L'objectif est de rendre les dalles **cliquables** pour switcher dynamiquement le graphique affiché, et d'ajouter 3 nouvelles vues chart (Marge, Intercontrat, Missions).

**Prototype de référence validé :** `PROTO_TDB_multikpi.html` (dans ce même dossier).
Le code de ce prototype constitue la source de vérité pour les composants à implémenter.

---

## 2. Design System — contraintes impératives

Claude Code **doit respecter scrupuleusement** la charte graphique Upgrade ("DA Pro Lyon") :

| Token | Valeur |
|---|---|
| Midnight | `#1C1F35` |
| Snow | `#FFFFFF` |
| Red | `#FF3D2E` |
| Blue | `#4A7FE5` |
| Green | `#00C218` |
| Yellow | `#FFE500` |
| Pink | `#FF66FF` |
| Border neutre | `#E4E4E6` |

**Règles visuelles impératives :**
- `border-radius: 0` partout — **aucune valeur `borderRadius` autre que `0`**, ni en CSS ni en inline styles
- Police : `Outfit` (déjà chargée dans le fichier), poids utilisés : 400, 600, 700, 800, 900
- Ombre brutalist : `4px 4px 0 <couleur>` (pas de blur)
- Bordure active : `2px solid #1C1F35` avec `borderLeft: 5px solid <couleur_kpi>`
- État actif d'une dalle : `background: #1C1F35`, valeur en blanc, label en couleur de la dalle
- `transition: all 120ms ease` sur les dalles au hover
- `filter: brightness(0.97)` au survol des dalles inactives

---

## 3. Modifications dans `TabTDB`

### 3.1 Nouveau state

Ajouter en tête du composant `TabTDB` :

```js
const [activeChart, setActiveChart] = useState('ca');
// Valeurs possibles : 'ca' | 'marge' | 'inter' | 'missions'
```

### 3.2 Tableau de configuration des KPI cards

Remplacer les dalles statiques actuelles par une configuration dynamique :

```js
const CARDS = [
  {
    id: 'missions',
    color: '#00C218',
    value: enMission.length,
    label: 'EN MISSION',
    sub: `${enMission.length} consultant${enMission.length > 1 ? 's' : ''} actifs`,
  },
  {
    id: 'inter',
    color: intercontrat.length > 0 ? '#FFE500' : '#ccc',
    value: intercontrat.length,
    label: 'INTERCONTRAT',
    sub: intercontrat.length > 0
      ? intercontrat.map(m => m.consultant?.split(' ')[0]).join(', ')
      : 'Aucun',
    badge: tauxInterAnn >= 8 ? '⚠ MALUS' : tauxInterAnn >= 5 ? 'Attention' : null,
    badgeColor: tauxInterAnn >= 8 ? '#FF3D2E' : '#92400e',
  },
  {
    id: 'ca',
    color: '#4A7FE5',
    value: fmtK(caYTD),
    label: 'CA YTD',
    sub: 'toutes missions',
  },
  {
    id: 'marge',
    color: '#FF66FF',
    value: fmtK(margeYTD),
    label: 'MARGE YTD',
    sub: `${tauxMarge.toFixed(1)}% taux de marge`,
  },
];
```

> Les variables `enMission`, `intercontrat`, `caYTD`, `margeYTD`, `tauxMarge`, `tauxInterAnn` sont **déjà calculées** dans `TabTDB`. Il suffit d'ajouter `tauxInterAnn` (voir §3.3) et `fmtK` (voir §3.4).

### 3.3 Calculs à ajouter dans `TabTDB`

```js
// Taux intercontrat annuel YTD
const JOURS_OUV = 18.16;
const joursInterYTD = /* somme des jours intercontrat de Jan à mois courant */;
const avgCdi = /* moyenne nb CDI actifs Jan → mois courant */;
const tauxInterAnn = avgCdi > 0 ? (joursInterYTD / (218 * avgCdi)) * 100 : 0;

// Taux intercontrat mensuel (tableau 12 mois)
const tauxInterM = MOIS_KEYS.map((_, i) =>
  nbCdiParMois[i] > 0 ? (joursInterParMois[i] / (nbCdiParMois[i] * JOURS_OUV)) * 100 : 0
);

// Marge mensuelle
const margeMensuel = MOIS_KEYS.map(k =>
  missions.reduce((s, m) => s + (m[k] || 0) * ((m.tjm || 0) - (m.cjm || 0)), 0)
);
const margeYTD = margeMensuel.slice(0, curMonth + 1).reduce((a, b) => a + b, 0);
const tauxMarge = caYTD > 0 ? margeYTD / caYTD * 100 : 0;

// Flow missions mensuel
const missionFlow = MOIS_KEYS.map((_, i) => ({
  actifs:    missions.filter(m => (m[MOIS_KEYS[i]] || 0) > 0 && m.statut !== 'Intercontrat').length,
  nouvelles: missions.filter(m => {
    if (!m.date_debut) return false;
    const d = new Date(m.date_debut);
    return d.getFullYear() === currentYear && d.getMonth() === i;
  }).length,
  fins: missions.filter(m => {
    if (!m.date_fin) return false;
    const d = new Date(m.date_fin);
    return d.getFullYear() === currentYear && d.getMonth() === i;
  }).length,
}));
```

> **Note :** Adapter selon les noms de variables déjà existants dans `TabTDB`. La logique prime sur les noms exacts.

### 3.4 Fonction utilitaire `fmtK`

```js
function fmtK(n) {
  return n >= 1000 ? `${(n / 1000).toFixed(0)}k€` : `${Math.round(n)}€`;
}
```

Si une fonction similaire existe déjà, la réutiliser.

### 3.5 Rendu des dalles KPI

Remplacer le rendu statique par :

```jsx
<div style={{display:'grid', gridTemplateColumns:'repeat(4,1fr)', gap:10, marginBottom:16}}>
  {CARDS.map(c => {
    const isOn = activeChart === c.id;
    return (
      <div
        key={c.id}
        onClick={() => setActiveChart(c.id)}
        style={{
          cursor: 'pointer',
          transition: 'all 120ms ease',
          background: isOn ? '#1C1F35' : '#fff',
          border: `2px solid ${isOn ? '#1C1F35' : '#E4E4E6'}`,
          borderLeft: `5px solid ${c.color}`,
          padding: '16px 14px',
          boxShadow: isOn ? `4px 4px 0 ${c.color}` : 'none',
          transform: isOn ? 'translate(-2px,-2px)' : 'none',
          position: 'relative',
          borderRadius: 0,  // IMPÉRATIF — charte brutalist
        }}
      >
        {/* Badge alerte (ex: MALUS intercontrat) */}
        {c.badge && (
          <span style={{
            position:'absolute', top:8, right:8,
            fontSize:10, fontWeight:800,
            background: c.badgeColor, color:'#fff',
            padding:'1px 6px', borderRadius:0,
          }}>{c.badge}</span>
        )}
        {/* Valeur principale */}
        <div style={{
          fontSize:30, fontWeight:900,
          color: isOn ? '#fff' : '#1C1F35',
          letterSpacing:'-0.02em', lineHeight:1,
        }}>{c.value}</div>
        {/* Label KPI */}
        <div style={{
          fontSize:10, fontWeight:700, letterSpacing:'0.1em',
          color: isOn ? c.color : '#999',
          marginTop:6, textTransform:'uppercase',
        }}>{c.label}</div>
        {/* Sous-label */}
        <div style={{
          fontSize:11, color: isOn ? '#aaa' : '#ccc',
          marginTop:3, overflow:'hidden',
          textOverflow:'ellipsis', whiteSpace:'nowrap',
        }}>{c.sub}</div>
      </div>
    );
  })}
</div>
```

### 3.6 Conteneur du chart (conditionnel)

```jsx
<div style={{background:'#fff', border:'2px solid #1C1F35', padding:'20px 24px 24px', borderRadius:0}}>
  {activeChart === 'ca'       && <ChartCA    caMensuel={caMensuel} caYTD={caYTD} curMonth={curMonth} />}
  {activeChart === 'marge'    && <ChartMarge margeMensuel={margeMensuel} margeYTD={margeYTD} caMensuel={caMensuel} tauxMarge={tauxMarge} curMonth={curMonth} />}
  {activeChart === 'inter'    && <ChartInter tauxM={tauxInterM} tauxAnn={tauxInterAnn} curMonth={curMonth} />}
  {activeChart === 'missions' && <ChartMissions flow={missionFlow} curMonth={curMonth} />}
</div>
<div style={{marginTop:8, fontSize:11, color:'#bbb', textAlign:'right', fontFamily:'Outfit,sans-serif'}}>
  ↑ Cliquer sur une dalle pour changer la vue
</div>
```

---

## 4. Système de coordonnées partagé — CRITIQUE

**Toutes les barres et toutes les lignes de seuil doivent utiliser les mêmes constantes.** C'est la clé pour éviter le décalage entre barres et lignes de seuil (bug rencontré lors du prototypage).

```js
// À définir une seule fois, en dehors des composants
const CH = { TOTAL: 180, TOP: 22, BOT: 20, H: 138 };
// TOTAL = hauteur totale du conteneur
// BOT   = espace réservé en bas (labels de mois)
// TOP   = espace réservé en haut (labels de valeurs)
// H     = TOTAL - TOP - BOT = hauteur utile des barres
```

**Hauteur d'une barre :**
```js
const barH = v => Math.max((v / max) * CH.H, v > 0 ? 6 : 2);
// min 6px si valeur > 0 (visibilité), 2px si 0 (placeholder)
```

**Position d'une ligne de seuil :**
```js
const lineBot = threshold => CH.BOT + (threshold / max) * CH.H;
// Même formule que barH → alignement parfait garanti
```

**Conteneur absolu pour chaque chart :**
```jsx
<div style={{position:'relative', height:CH.TOTAL, marginTop:8}}>
  {/* lignes de seuil en absolu */}
  {/* barres en absolu */}
  {/* labels en absolu */}
</div>
```

> ⚠️ **Ne jamais utiliser `display:flex` + `alignItems:'flex-end'` + `flex:1` pour les barres.** Ce pattern fait s'effondrer les hauteurs à 0px. Utiliser exclusivement `position:absolute` + `bottom:CH.BOT` + `height:barH(v)`.

---

## 5. Composant générique `AbsBars`

Ce composant mutualisé gère le rendu absolu des barres pour CA et Marge :

```jsx
function AbsBars({ data, max, getColor, getTopLabel, getTopLabel2, getFins, gap = 4, curMonth }) {
  const barH = v => Math.max((v / max) * CH.H, v > 0 ? 6 : 2);
  const MOIS = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];
  return (
    <div style={{position:'relative', height:CH.TOTAL, marginTop:8}}>
      <div style={{position:'absolute', left:0, right:0, top:0, bottom:0, display:'flex', gap, zIndex:3}}>
        {data.map((v, i) => {
          const bh     = barH(v);
          const color  = getColor(v, i);
          const topLbl = getTopLabel ? getTopLabel(v, i) : null;
          const topLb2 = getTopLabel2 ? getTopLabel2(v, i) : null;
          const fins   = getFins ? getFins(i) : null;
          return (
            <div key={i} style={{flex:1, position:'relative', minWidth:0}}>
              {/* Barre */}
              <div style={{
                position:'absolute', left:0, right:0,
                bottom:CH.BOT, height:bh,
                background:color, transition:'height 300ms',
              }}/>
              {/* Label valeur */}
              {topLbl && (
                <div style={{
                  position:'absolute', left:0, right:0,
                  bottom: CH.BOT + bh + 2,
                  textAlign:'center', fontSize:10, fontWeight:700,
                  color:topLbl.color, whiteSpace:'nowrap', lineHeight:1.2,
                }}>{topLbl.text}</div>
              )}
              {/* Label secondaire (ex: taux %) */}
              {topLb2 && (
                <div style={{
                  position:'absolute', left:0, right:0,
                  bottom: CH.BOT + bh + 14,
                  textAlign:'center', fontSize:9, color:'#aaa', whiteSpace:'nowrap',
                }}>{topLb2}</div>
              )}
              {/* Badge fins (sous la barre) */}
              {fins && fins > 0 && (
                <div style={{
                  position:'absolute', left:'50%', transform:'translateX(-50%)',
                  bottom: CH.BOT - 1,
                  fontSize:9, fontWeight:800,
                  color:'#FF3D2E', background:'#FF3D2E15',
                  padding:'0 3px', whiteSpace:'nowrap', zIndex:4,
                }}>−{fins}</div>
              )}
              {/* Label mois */}
              <div style={{
                position:'absolute', left:0, right:0, bottom:3,
                textAlign:'center', fontSize:10, fontWeight:600,
                color: i === curMonth ? '#1C1F35' : '#ccc',
              }}>{MOIS[i]}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
```

---

## 6. Composant `ChartHeader`

```jsx
function ChartHeader({ title, kpi, kpiLabel, color, children }) {
  return (
    <div style={{display:'flex', alignItems:'center', gap:12, marginBottom:4, flexWrap:'wrap'}}>
      <span style={{width:10, height:10, background:color, display:'inline-block', flexShrink:0}}/>
      <span style={{fontSize:13, fontWeight:700, color:'#1C1F35', fontFamily:'Outfit,sans-serif'}}>{title}</span>
      <span style={{fontSize:12, color:'#bbb'}}>{kpiLabel} : {kpi}</span>
      {children}
    </div>
  );
}
```

---

## 7. Composant `ChartCA`

```jsx
function ChartCA({ caMensuel, caYTD, curMonth }) {
  const max = Math.max(...caMensuel, 1);
  return (
    <>
      <ChartHeader title="CA mensuel 2026" kpi={fmtFull(caYTD)} kpiLabel="YTD" color="#4A7FE5" />
      <AbsBars
        data={caMensuel}
        max={max}
        curMonth={curMonth}
        getColor={(v, i) => i > curMonth ? '#E4E4E6' : i < curMonth ? '#4A7FE5BB' : '#4A7FE5'}
        getTopLabel={(v, i) => v > 0 ? { text: fmtK(v), color: i > curMonth ? '#ddd' : '#4A7FE5' } : null}
      />
    </>
  );
}
```

**Logique couleur :**
- Mois passés (< curMonth) : `#4A7FE5BB` (légèrement transparent)
- Mois courant : `#4A7FE5` (plein)
- Mois futurs (> curMonth) : `#E4E4E6` (gris neutre)

---

## 8. Composant `ChartMarge`

```jsx
function ChartMarge({ margeMensuel, margeYTD, caMensuel, tauxMarge, curMonth }) {
  const max = Math.max(...margeMensuel, 1);
  const rates = margeMensuel.map((m, i) => caMensuel[i] > 0 ? (m / caMensuel[i] * 100) : 0);
  return (
    <>
      <ChartHeader title="Marge mensuelle 2026" kpi={fmtFull(margeYTD)} kpiLabel="YTD" color="#FF66FF">
        <span style={{
          fontSize:11, background:'#FF66FF22', color:'#c020c0',
          padding:'2px 8px', fontWeight:700, borderRadius:0,
        }}>
          Taux moyen {tauxMarge.toFixed(1)}%
        </span>
      </ChartHeader>
      <AbsBars
        data={margeMensuel}
        max={max}
        curMonth={curMonth}
        getColor={(v, i) => i > curMonth ? '#E4E4E6' : i < curMonth ? '#FF66FFBB' : '#FF66FF'}
        getTopLabel={(v, i) => v > 0 ? { text: fmtK(v), color: i > curMonth ? '#ddd' : '#FF66FF' } : null}
        getTopLabel2={(v, i) => rates[i] > 0 && i <= curMonth ? `${rates[i].toFixed(0)}%` : null}
      />
    </>
  );
}
```

**Spécificité :** `getTopLabel2` affiche le taux de marge mensuel (en %) en petits caractères sous le label de valeur.

---

## 9. Composant `ChartInter` — Intercontrat

C'est le composant le plus complexe. Il affiche barres + lignes de seuil + badges trimestriels.

```jsx
function ChartInter({ tauxM, tauxAnn, curMonth }) {
  const max = Math.max(...tauxM, 10, 1);
  const col  = v => v >= 8 ? '#FF3D2E' : v >= 5 ? '#FFE500' : '#00C218';
  const status = tauxAnn < 5
    ? { label: '✓ Objectif atteint', bg: '#dcfce7', color: '#166534' }
    : tauxAnn < 8
    ? { label: '⚠ Attention',        bg: '#fef9c3', color: '#92400e' }
    : { label: '✕ MALUS',            bg: '#fee2e2', color: '#991b1b' };

  const barH   = v => Math.max((v / max) * CH.H, v > 0 ? 6 : 2);
  const lineBot = t => CH.BOT + (t / max) * CH.H;  // MÊME FORMULE que barH → alignement garanti

  const MOIS = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];

  return (
    <>
      {/* Header */}
      <div style={{display:'flex', alignItems:'center', gap:10, marginBottom:6, flexWrap:'wrap'}}>
        <span style={{fontSize:13, fontWeight:700, color:'#1C1F35', fontFamily:'Outfit,sans-serif'}}>
          Taux d'intercontrat mensuel 2026
        </span>
        <span style={{
          fontSize:11, background:'#1C1F35', color:'#FFE500',
          padding:'2px 10px', fontWeight:800, borderRadius:0,
        }}>
          Annuel YTD : {tauxAnn.toFixed(1)}%
        </span>
        <span style={{
          fontSize:11, background:status.bg, color:status.color,
          padding:'2px 10px', fontWeight:700, borderRadius:0,
        }}>
          {status.label}
        </span>
      </div>

      {/* Container absolu partagé — barres + lignes de seuil dans le MÊME référentiel */}
      <div style={{position:'relative', height:CH.TOTAL, marginTop:8}}>

        {/* Lignes de seuil — position bottom calculée avec lineBot() */}
        {[
          { v: 5, color: '#00C218', label: 'objectif 5%' },
          { v: 8, color: '#FF3D2E', label: 'malus 8%'    },
        ].map(({ v, color, label }) => (
          <div key={v} style={{
            position:'absolute', left:0, right:0,
            bottom: lineBot(v),
            borderTop: `2px dashed ${color}`,
            zIndex: 2,
          }}>
            <span style={{
              position:'absolute', right:0, top:-14,
              fontSize:9, fontWeight:800, color,
              background:'#fff', padding:'0 4px',
            }}>{label}</span>
          </div>
        ))}

        {/* Barres */}
        <div style={{
          position:'absolute', left:0, right:0, top:0, bottom:0,
          display:'flex', gap:4, zIndex:3,
        }}>
          {tauxM.map((v, i) => {
            const bh     = barH(v);
            const future = i > curMonth;
            const color  = future ? '#E4E4E6' : col(v);
            return (
              <div key={i} style={{flex:1, position:'relative', minWidth:0}}>
                <div style={{
                  position:'absolute', left:0, right:0,
                  bottom:CH.BOT, height:bh,
                  background:color, opacity:future ? 0.35 : 1,
                  transition:'height 300ms',
                }}/>
                {v > 0 && (
                  <div style={{
                    position:'absolute', left:0, right:0,
                    bottom: CH.BOT + bh + 2,
                    textAlign:'center', fontSize:10, fontWeight:700,
                    color: future ? '#ddd' : col(v), whiteSpace:'nowrap',
                  }}>{v.toFixed(1)}%</div>
                )}
                <div style={{
                  position:'absolute', left:0, right:0, bottom:3,
                  textAlign:'center', fontSize:10, fontWeight:600,
                  color: i === curMonth ? '#1C1F35' : '#ccc',
                }}>{MOIS[i]}</div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Badges trimestriels */}
      <div style={{display:'flex', gap:8, marginTop:14, flexWrap:'wrap'}}>
        {[['T1',0,3],['T2',3,6],['T3',6,9],['T4',9,12]].map(([t, from, to]) => {
          const vals   = tauxM.slice(from, to).filter(v => v > 0);
          const avg    = vals.length > 0 ? vals.reduce((a,b) => a+b, 0) / vals.length : null;
          const isCur  = from <= curMonth && curMonth < to;
          const bg     = avg === null ? '#f3f4f6' : avg >= 8 ? '#fee2e2' : avg >= 5 ? '#fef9c3' : '#dcfce7';
          const clr    = avg === null ? '#999'    : avg >= 8 ? '#991b1b' : avg >= 5 ? '#92400e' : '#166534';
          return (
            <div key={t} style={{
              fontSize:11,
              background: isCur ? '#1C1F35' : bg,
              color:      isCur ? '#FFE500' : clr,
              padding:'4px 12px', fontWeight:700, borderRadius:0,
              border: isCur ? '2px solid #1C1F35' : '2px solid transparent',
            }}>
              {t} — {avg !== null ? avg.toFixed(1) + '%' : 'n/a'}
            </div>
          );
        })}
        <div style={{fontSize:11, color:'#aaa', padding:'4px 0', marginLeft:'auto'}}>
          Objectif annuel : &lt;5% · Malus si trimestre &gt;8%
        </div>
      </div>
    </>
  );
}
```

**Règle couleur des barres :**
- `v >= 8%` → Rouge `#FF3D2E` (malus)
- `5% ≤ v < 8%` → Jaune `#FFE500` (attention)
- `v < 5%` → Vert `#00C218` (objectif atteint)
- Mois futurs → Gris `#E4E4E6` à `opacity:0.35`

---

## 10. Composant `ChartMissions`

```jsx
function ChartMissions({ flow, curMonth }) {
  const max  = Math.max(...flow.map(f => f.actifs), 1);
  const barH = v => Math.max((v / max) * CH.H, v > 0 ? 6 : 2);
  const MOIS = ['Jan','Fév','Mar','Avr','Mai','Jun','Jul','Aoû','Sep','Oct','Nov','Déc'];

  return (
    <>
      {/* Légende */}
      <div style={{display:'flex', alignItems:'center', gap:10, marginBottom:4, flexWrap:'wrap'}}>
        <span style={{fontSize:13, fontWeight:700, color:'#1C1F35', fontFamily:'Outfit,sans-serif'}}>
          Activité missions 2026
        </span>
        <span style={{fontSize:11, background:'#00C21815', color:'#00C218', padding:'2px 8px', fontWeight:700}}>▲ Démarrage</span>
        <span style={{fontSize:11, background:'#FF3D2E15', color:'#FF3D2E', padding:'2px 8px', fontWeight:700}}>▼ Fin</span>
        <span style={{fontSize:11, background:'#4A7FE515', color:'#4A7FE5', padding:'2px 8px', fontWeight:700}}>■ Actifs</span>
      </div>

      <div style={{position:'relative', height:CH.TOTAL, marginTop:8}}>
        <div style={{
          position:'absolute', left:0, right:0, top:0, bottom:0,
          display:'flex', gap:4, zIndex:3,
        }}>
          {flow.map((f, i) => {
            const bh     = barH(f.actifs);
            const future = i > curMonth;
            return (
              <div key={i} style={{flex:1, position:'relative', minWidth:0}}>
                {/* Barre actifs */}
                <div style={{
                  position:'absolute', left:0, right:0,
                  bottom:CH.BOT, height:bh,
                  background: future ? '#E4E4E6' : '#4A7FE5',
                  opacity: future ? 0.35 : 1,
                  transition:'height 300ms',
                }}/>
                {/* Badge démarrage — au-dessus de la barre */}
                {f.nouvelles > 0 && (
                  <div style={{
                    position:'absolute', left:'50%', transform:'translateX(-50%)',
                    bottom: CH.BOT + bh + 2,
                    fontSize:9, fontWeight:800, color:'#00C218',
                    background:'#00C21815', padding:'0 3px', whiteSpace:'nowrap', zIndex:4,
                  }}>+{f.nouvelles}</div>
                )}
                {/* Valeur actifs */}
                {f.actifs > 0 && (
                  <div style={{
                    position:'absolute', left:0, right:0,
                    bottom: CH.BOT + bh + (f.nouvelles > 0 ? 14 : 2),
                    textAlign:'center', fontSize:9, fontWeight:700,
                    color: future ? '#ccc' : '#4A7FE5',
                  }}>{f.actifs}</div>
                )}
                {/* Badge fin — sous la barre */}
                {f.fins > 0 && (
                  <div style={{
                    position:'absolute', left:'50%', transform:'translateX(-50%)',
                    bottom: CH.BOT - 1,
                    fontSize:9, fontWeight:800, color:'#FF3D2E',
                    background:'#FF3D2E15', padding:'0 3px', whiteSpace:'nowrap', zIndex:4,
                  }}>−{f.fins}</div>
                )}
                {/* Label mois */}
                <div style={{
                  position:'absolute', left:0, right:0, bottom:3,
                  textAlign:'center', fontSize:10, fontWeight:600,
                  color: i === curMonth ? '#1C1F35' : '#ccc',
                }}>{MOIS[i]}</div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Récap événements */}
      <div style={{
        marginTop:6, background:'#f9f9f9',
        border:'1px solid #E4E4E6', padding:'8px 14px',
        fontSize:11, display:'flex', gap:20, flexWrap:'wrap', alignItems:'center',
      }}>
        <span style={{
          fontWeight:700, color:'#aaa', fontSize:10,
          textTransform:'uppercase', letterSpacing:'0.05em',
        }}>Événements</span>
        {flow.map((f, i) => (f.nouvelles > 0 || f.fins > 0) && (
          <span key={i} style={{color:'#1C1F35'}}>
            <strong>{MOIS[i]}</strong>
            {f.nouvelles > 0 && <span style={{color:'#00C218', marginLeft:4}}>+{f.nouvelles}</span>}
            {f.fins > 0 && <span style={{color:'#FF3D2E', marginLeft: f.nouvelles > 0 ? 6 : 4}}>−{f.fins}</span>}
          </span>
        ))}
      </div>
    </>
  );
}
```

---

## 11. Suppression de l'ancien chart CA fixe

Repérer et **supprimer** le bloc suivant dans `TabTDB` (ligne ~3435 du fichier actuel) :

```
"flex items-end gap-1.5 h-80"
```

Ce bloc correspond au chart CA statique Tailwind à remplacer entièrement par le système conditionnel décrit dans cette spec.

---

## 12. Ordre d'implémentation recommandé

1. Ajouter les constantes `CH` et la fonction `fmtK` en tête de la section React
2. Ajouter les nouveaux calculs dans `TabTDB` (§3.3)
3. Créer les composants helpers : `ChartHeader`, `AbsBars`
4. Créer les 4 composants chart : `ChartCA`, `ChartMarge`, `ChartInter`, `ChartMissions`
5. Remplacer le rendu des dalles KPI dans `TabTDB` (§3.5)
6. Remplacer l'ancien chart fixe par le conteneur conditionnel (§3.6)
7. Supprimer le code de l'ancien chart CA statique (§11)

---

## 13. Critères QA

| # | Test | Attendu |
|---|---|---|
| 1 | Clic sur dalle CA | `activeChart` passe à `'ca'`, dalle en dark + shadow Blue, ChartCA s'affiche |
| 2 | Clic sur dalle Marge | ChartMarge s'affiche, taux mensuel en petit texte sous chaque barre |
| 3 | Clic sur dalle Intercontrat | ChartInter s'affiche, lignes de seuil 5% et 8% alignées exactement sur les barres correspondantes |
| 4 | Clic sur dalle Missions | ChartMissions s'affiche, badges +N verts au-dessus des barres, badges −N rouges en dessous |
| 5 | `border-radius` | Aucun arrondi visible sur aucun élément (dalles, barres, badges, conteneur chart) |
| 6 | Responsive | Grid 4 colonnes reste lisible jusqu'à 900px de large |
| 7 | Mois courant | Colonne du mois courant en `#1C1F35`, label en gras, barres passées légèrement atténuées |
| 8 | Badge MALUS intercontrat | Si `tauxInterAnn ≥ 8`, badge rouge `⚠ MALUS` visible en haut à droite de la dalle Intercontrat |
| 9 | Hauteur chart | Conteneur chart à exactement `CH.TOTAL = 180px`, aucun espace vide en dessous |
| 10 | Deploy | Uniquement `bash supabase/deploy_staging.sh` — ne jamais pousser sur `main` |

---

## 14. Référence prototype

Le prototype HTML complet est disponible en lecture dans `PROTO_TDB_multikpi.html` (même dossier que cette spec). Il constitue la **source de vérité visuelle et fonctionnelle**. En cas de doute sur un comportement ou une valeur de style, le prototype prime.
