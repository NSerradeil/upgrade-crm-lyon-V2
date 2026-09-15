# SPEC — KPI "Pas intéressés" sur la liste Prospection

**Fichier** : `supabase/CRM_Live.html` — composant `ProspectionList` / `TabProspection`
**Date** : 25/03/2026
**Priorité** : P1
**Modèle** : identique au comportement de la card "Intéressants" existante

---

## Comportement attendu

Ajouter une **5e card KPI** "PAS INTÉRESSÉS" sur la vue liste Prospection, avec :
- Compteur = nombre total de contacts `statut = 'not_interested'` toutes sessions confondues
- Couleur rouge (#FF3D2E) — cohérent avec le badge PAS INTÉRESSÉ dans les sessions
- Au clic → panel drill-down "CONTACTS PAS INTÉRESSÉS" (même style que "CONTACTS INTÉRESSANTS")
- Panel refermable via ×

---

## Implémentation

### 1. Ajouter la card dans le tableau `kpiCards`

Chercher le tableau où sont définis les KPIs (autour de la ligne avec `id:'interesses'`) :

```js
// Avant (4 cards) :
var kpiCards = [
  {id:'total',      label:'SESSIONS',     value: filtered.length,                                          color:'#4A7FE5'},
  {id:'interesses', label:'INTÉRESSANTS', value: filtered.reduce((a,s) => a+(s.nb_interesses||0), 0),      color:'#00C218'},
  {id:'relances',   label:'RELANCES',     value: filtered.reduce((a,s) => a+(s.nb_relances||0), 0),        color:'#FFE500'},
  {id:'injoignables',label:'INJOIGNABLES',value: filtered.reduce((a,s) => a+(s.nb_injoignables||0), 0),    color:'#999'},
];

// Après (5 cards) — ajouter avant ou après 'injoignables' :
var kpiCards = [
  {id:'total',          label:'SESSIONS',        value: filtered.length,                                       color:'#4A7FE5'},
  {id:'interesses',     label:'INTÉRESSANTS',    value: filtered.reduce((a,s) => a+(s.nb_interesses||0), 0),   color:'#00C218'},
  {id:'relances',       label:'RELANCES',         value: filtered.reduce((a,s) => a+(s.nb_relances||0), 0),    color:'#FFE500'},
  {id:'injoignables',   label:'INJOIGNABLES',    value: filtered.reduce((a,s) => a+(s.nb_injoignables||0), 0), color:'#999'},
  {id:'not_interested', label:'PAS INTÉRESSÉS',  value: 0, color:'#FF3D2E'}, // valeur calculée dynamiquement, voir §2
];
```

> Le compteur "Pas intéressés" n'est **pas stocké** dans `sessions_prospection` (pas de colonne `nb_not_interested`). La valeur est donc calculée à la volée via une requête au chargement — voir §2.

### 2. Charger le compteur "Pas intéressés" au montage

Dans `TabProspection` (ou `ProspectionList`), au même endroit que `loadSessions()`, ajouter un chargement du compteur :

```js
// Compter les contacts 'not_interested' toutes sessions (filtrées par agence/commercial si applicable)
var countRes = await sb
  .from('session_prospection_contacts')
  .select('contact_id', { count: 'exact', head: true })
  .eq('statut', 'not_interested');

var nbNotInterested = countRes.count || 0;
setNbNotInterested(nbNotInterested); // nouveau state
```

Ajouter le state :
```js
const [nbNotInterested, setNbNotInterested] = React.useState(0);
```

Et brancher la valeur dans `kpiCards` :
```js
{id:'not_interested', label:'PAS INTÉRESSÉS', value: nbNotInterested, color:'#FF3D2E'},
```

### 3. Ajouter la branche dans le handler de clic KPI

Chercher le bloc `if (id === 'relances')` ou similaire et ajouter :

```js
} else if (id === 'not_interested') {
  var r3 = await sb
    .from('session_prospection_contacts')
    .select('contact_id, notes, created_at, sessions_prospection(nom, date_session)')
    .eq('statut', 'not_interested')
    .order('created_at', { ascending: false });
  data = r3.data || [];
}
```

### 4. Ajouter le rendu du panel "CONTACTS PAS INTÉRESSÉS"

Dans le bloc de rendu du panel drill-down (après le bloc `id === 'interesses'`), ajouter une branche `id === 'not_interested'`. Le rendu est **identique** à "CONTACTS INTÉRESSANTS", en changeant :

- Titre : `CONTACTS PAS INTÉRESSÉS`
- Couleur de la bordure gauche des cards : `#FF3D2E`
- Pas de lien besoin (contrairement à "intéressants")

```jsx
{activeKpi === 'not_interested' && kpiData.length > 0 && (
  <div style={{marginBottom:16, border:'2px solid #FF3D2E', borderLeft:'4px solid #FF3D2E'}}>
    <div style={{background:'#1C1F35', padding:'8px 16px', display:'flex', justifyContent:'space-between', alignItems:'center'}}>
      <span style={{color:'#fff', fontWeight:800, fontSize:11, textTransform:'uppercase', letterSpacing:'0.08em'}}>
        Contacts pas intéressés
      </span>
      <button onClick={function(){setActiveKpi(null);}} style={{background:'none',border:'none',color:'#FFE500',cursor:'pointer',fontWeight:900,fontSize:14}}>×</button>
    </div>
    {kpiData.map(function(row) {
      var c = contactMap[row.contact_id] || {};
      var session = row.sessions_prospection || {};
      return (
        <div key={row.contact_id + '_' + row.created_at}
          style={{padding:'10px 16px', borderBottom:'1px solid #E4E4E6', cursor:'pointer'}}
          onClick={function(){ if(onNavToContact) onNavToContact(row.contact_id); }}
        >
          <div style={{fontWeight:800, fontSize:13}}>{c.prenom} {c.nom}</div>
          <div style={{fontSize:11, color:'#4A7FE5', marginBottom:2}}>
            {c.groupe} {c.role ? '· ' + c.role : ''}
          </div>
          <div style={{fontSize:10, color:'#999', marginBottom:4}}>
            {session.nom} · {session.date_session ? new Date(session.date_session).toLocaleDateString('fr-FR',{day:'numeric',month:'long'}) : ''}
          </div>
          {row.notes && (
            <div style={{fontSize:11, color:'#555', fontStyle:'italic', borderLeft:'3px solid #FF3D2E', paddingLeft:8}}>
              {row.notes}
            </div>
          )}
        </div>
      );
    })}
    {kpiData.length === 0 && (
      <div style={{padding:16, color:'#999', fontSize:12, textAlign:'center'}}>Aucune donnée</div>
    )}
  </div>
)}
```

---

## Rendu visuel attendu

```
┌──────────┐ ┌──────────────┐ ┌──────────┐ ┌─────────────┐ ┌──────────────────┐
│    3     │ │      1       │ │    3     │ │     13      │ │        1         │
│ SESSIONS │ │ INTÉRESSANTS │ │ RELANCES │ │ INJOIGNABLES│ │ PAS INTÉRESSÉS   │
└──────────┘ └──────────────┘ └──────────┘ └─────────────┘ └──────────────────┘
                                                                 ↑ rouge #FF3D2E
```

Au clic → panel sous les cards :

```
┌─ CONTACTS PAS INTÉRESSÉS ─────────────────────────────────── × ┐
│ Camille MAYET                                                    │
│ D-Edge (Accor group) · DRH                                       │
│ Session Calls 24/03/2026 · 24 mars                               │
│ ❙ pas intéressée par l'échange, décline toute invitation         │
├──────────────────────────────────────────────────────────────────┤
│ ...                                                              │
└──────────────────────────────────────────────────────────────────┘
```

---

## Notes

- Si la grille 4 colonnes devient trop étroite à 5 cards, passer à `gridTemplateColumns: 'repeat(5, 1fr)'` (idem, juste changer le 4 en 5)
- Le filtre agence/commercial de la liste sessions ne s'applique **pas** automatiquement au compteur `not_interested` (requête globale). Évolution future si nécessaire.
