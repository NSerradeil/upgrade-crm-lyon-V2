# Refonte du suivi de l'intercontrat — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remplacer le suivi de l'intercontrat par missions fictives par un objet propre (`interco_imputations`) rattaché au contact « Consultant CDI », avec saisie intégrée à la fiche contact, calcul de carte corrigé, outils MCP et migration de l'existant.

**Architecture :** App React mono-fichier (`upgrade-crm-lyon-V2/index.html`) parlant à Supabase via `supabase-js` (`sb.from(...)`). Serveur MCP mono-fichier (`upgrade-crm-mcp-src/server/index.mjs`) parlant à Supabase REST via helpers `sbGet/sbPost/sbPatch/sbDelete` + `server.tool(...)`. Schéma Supabase géré à la main (pas de dossier migrations dans le repo). **Aucun framework de test** → vérification = SQL dans l'éditeur Supabase, appels MCP réels, contrôle visuel navigateur.

**Tech Stack :** PostgreSQL/Supabase (PostgREST + RLS), React 18 via CDN + Babel standalone (JSX inline dans `index.html`), Node ESM + `@modelcontextprotocol/sdk` + `zod` pour le MCP.

## Global Constraints

- **Spec de référence :** `upgrade-crm-lyon-V2/SPECS_CRM/SPEC_interco_refonte.md` — toute exigence en découle.
- **Données stockées = jours** (numeric). Pas de quotité. 100%/50% = raccourcis de remplissage côté UI uniquement.
- **Jours ouvrés = jours ouvrés RÉELS du mois** (jours fériés FR déduits), partout : remplissage du bouton 100% ET dénominateur de la carte. Plus de constante `18,16`.
- **Coût interco = `cjm_snapshot × jours`** — `cjm_snapshot` figé à la saisie, jamais recalculé sur le CJM courant.
- **Seuils inchangés :** `≥5%` Attention, `≥8%` MALUS.
- **Droits WRITE :** `agence_contact == profile.agence` OU `contact.responsable == profile.nom` OU `profile.role==='admin'`. READ = tous (calqué sur `SPEC_contacts_permissions_agence`).
- **Pas de commit/push sans demande explicite de Nicolas** (règle projet). Les étapes « Commit » ci-dessous sont préparées mais à ne lancer qu'après son GO.
- **Repos :** app = `upgrade-crm-lyon-V2`, MCP = `upgrade-crm-mcp-src`. Les deux sont des dépôts git séparés.

---

## Structure des fichiers touchés

- **DB (artefacts SQL, exécutés à la main dans Supabase, versionnés pour traçabilité)** — nouveau dossier `upgrade-crm-lyon-V2/db/` :
  - `db/01_interco_imputations.sql` — table + index + contrainte unique.
  - `db/02_interco_rls.sql` — politiques RLS.
  - `db/03_interco_migration.sql` — migration missions interco → `interco_imputations`.
  - `db/04_interco_verif.sql` — requêtes de vérification des totaux avant/après.
  - `db/05_interco_cleanup.sql` — suppression des missions interco + retrait du statut.
- **App** `upgrade-crm-lyon-V2/index.html` :
  - helper `joursOuvresMois(annee, moisIdx)` (nouveau, près des helpers date existants).
  - chargement `interco_imputations` + recalcul de la carte data interco (remplace le bloc ~4738-4795).
  - module de saisie interco dans le panneau d'édition contact (`EditContact`, ~1085-1136).
  - garde d'écriture `canEditInterco(contact, profile)`.
- **MCP** `upgrade-crm-mcp-src/server/index.mjs` :
  - 4 outils `crm_set_interco`, `crm_get_interco`, `crm_list_interco`, `crm_delete_interco` (près des autres `server.tool`).
- **Script de sauvegarde** `upgrade-crm-mcp-src/server/backup_interco_missions.mjs` (one-off, réutilise le pattern fetch REST).

---

## Task 1 : Table `interco_imputations` + contraintes

**Files:**
- Create: `upgrade-crm-lyon-V2/db/01_interco_imputations.sql`

**Interfaces:**
- Produces: table `interco_imputations(id, contact_consultant_id, annee, mois, jours, cjm_snapshot, updated_by, updated_at)` avec `UNIQUE(contact_consultant_id, annee, mois)`. Consommée par toutes les tâches suivantes.

- [ ] **Step 1 : Écrire le SQL de création**

```sql
-- db/01_interco_imputations.sql
create table if not exists public.interco_imputations (
  id bigint generated always as identity primary key,
  contact_consultant_id bigint not null references public.contacts(id) on delete cascade,
  annee int not null check (annee between 2000 and 2100),
  mois int not null check (mois between 1 and 12),
  jours numeric(5,2) not null default 0 check (jours >= 0),
  cjm_snapshot numeric(10,2),
  updated_by text,
  updated_at timestamptz not null default now(),
  unique (contact_consultant_id, annee, mois)
);
create index if not exists idx_interco_annee_mois on public.interco_imputations (annee, mois);
create index if not exists idx_interco_consultant on public.interco_imputations (contact_consultant_id);
```

- [ ] **Step 2 : Exécuter dans l'éditeur SQL Supabase**

Coller le contenu de `db/01_interco_imputations.sql` dans Supabase → SQL Editor → Run.
Expected : `Success. No rows returned`.

- [ ] **Step 3 : Vérifier la création**

Run (SQL Editor) :
```sql
select column_name, data_type from information_schema.columns
where table_name = 'interco_imputations' order by ordinal_position;
```
Expected : 8 lignes (id, contact_consultant_id, annee, mois, jours, cjm_snapshot, updated_by, updated_at).

- [ ] **Step 4 : Vérifier la contrainte unique (anti-doublon)**

Run :
```sql
insert into interco_imputations (contact_consultant_id, annee, mois, jours)
  values ((select id from contacts where statut='Consultant CDI' limit 1), 2026, 3, 9);
insert into interco_imputations (contact_consultant_id, annee, mois, jours)
  values ((select id from contacts where statut='Consultant CDI' limit 1), 2026, 3, 5);
```
Expected : 1re ligne OK, 2e échoue avec `duplicate key value violates unique constraint`.
Puis nettoyer : `delete from interco_imputations where annee=2026 and mois=3;`

- [ ] **Step 5 : Commit (après GO Nicolas)**

```bash
cd upgrade-crm-lyon-V2
git add db/01_interco_imputations.sql
git commit -m "feat(interco): table interco_imputations + contrainte unique"
```

---

## Task 2 : RLS sur `interco_imputations`

**Files:**
- Create: `upgrade-crm-lyon-V2/db/02_interco_rls.sql`

**Interfaces:**
- Consumes: table de Task 1.
- Produces: politiques `interco_read_all`, `interco_write_agence_resp_admin`. La règle WRITE s'appuie sur le contact lié (`agence`, `responsable`) et le profil utilisateur (table `profiles`/`users` existante — confirmer le nom au Step 1).

- [ ] **Step 1 : Confirmer la table de profils et ses colonnes**

Run (SQL Editor) :
```sql
select table_name from information_schema.tables
where table_name in ('profiles','users') and table_schema='public';
select column_name from information_schema.columns
where table_name = '<table_trouvée>' ; -- repérer nom (text), agence (text), role (text), et la clé reliant à auth.uid()
```
Noter : nom de la table de profils, colonne reliant `auth.uid()` (souvent `id`), colonnes `nom`, `agence`, `role`. Adapter le SQL du Step 2 avec ces noms.

- [ ] **Step 2 : Écrire le SQL RLS**

```sql
-- db/02_interco_rls.sql  (adapter <profiles>, <nom>, <agence>, <role> aux noms réels)
alter table public.interco_imputations enable row level security;

-- READ : tout utilisateur authentifié
create policy interco_read_all on public.interco_imputations
  for select using (auth.role() = 'authenticated');

-- WRITE (insert/update/delete) : agence du contact == agence user, OU responsable du contact == nom user, OU admin
create policy interco_write_agence_resp_admin on public.interco_imputations
  for all
  using (
    exists (
      select 1
      from public.contacts c
      join public.<profiles> p on p.id = auth.uid()
      where c.id = interco_imputations.contact_consultant_id
        and ( c.agence = p.<agence>
              or c.responsable = p.<nom>
              or p.<role> = 'admin' )
    )
  )
  with check (
    exists (
      select 1
      from public.contacts c
      join public.<profiles> p on p.id = auth.uid()
      where c.id = interco_imputations.contact_consultant_id
        and ( c.agence = p.<agence>
              or c.responsable = p.<nom>
              or p.<role> = 'admin' )
    )
  );
```

- [ ] **Step 3 : Exécuter dans Supabase SQL Editor**

Expected : `Success. No rows returned`.

- [ ] **Step 4 : Vérifier que RLS est actif**

Run :
```sql
select relrowsecurity from pg_class where relname='interco_imputations';
```
Expected : `true`. Et `select polname from pg_policies where tablename='interco_imputations';` → 2 politiques.

- [ ] **Step 5 : Commit (après GO)**

```bash
cd upgrade-crm-lyon-V2
git add db/02_interco_rls.sql
git commit -m "feat(interco): RLS lecture tous / écriture agence+responsable+admin"
```

---

## Task 3 : Helper `joursOuvresMois` dans l'app

**Files:**
- Modify: `upgrade-crm-lyon-V2/index.html` (zone helpers date)

**Interfaces:**
- Produces: `joursOuvresMois(annee:int, moisIdx:int /*0-11*/) → number` — nb de jours ouvrés réels (lun-ven moins fériés FR) du mois. Consommée par Task 4 (carte) et Task 5/6 (raccourci 100%).

- [ ] **Step 1 : Écrire le helper (jours fériés FR inclus, Pâques par algo de Meeus)**

Insérer près des autres helpers date :
```javascript
function feriesFR(annee){
  // Pâques (algorithme de Meeus/Jones/Butcher)
  const a=annee%19,b=Math.floor(annee/100),c=annee%100,d=Math.floor(b/4),e=b%4,
    f=Math.floor((b+8)/25),g=Math.floor((b-f+1)/3),h=(19*a+b-d-g+15)%30,
    i=Math.floor(c/4),k=c%4,l=(32+2*e+2*i-h-k)%7,m=Math.floor((a+11*h+22*l)/451),
    mois=Math.floor((h+l-7*m+114)/31),jour=((h+l-7*m+114)%31)+1;
  const paques=new Date(annee,mois-1,jour);
  const d2=(base,off)=>{const x=new Date(base);x.setDate(x.getDate()+off);return x;};
  const set=new Set([
    new Date(annee,0,1),   // Jour de l'an
    d2(paques,1),          // Lundi de Pâques
    new Date(annee,4,1),   // Fête du travail
    new Date(annee,4,8),   // Victoire 1945
    d2(paques,39),         // Ascension
    d2(paques,50),         // Lundi de Pentecôte
    new Date(annee,6,14),  // Fête nationale
    new Date(annee,7,15),  // Assomption
    new Date(annee,10,1),  // Toussaint
    new Date(annee,10,11), // Armistice
    new Date(annee,11,25), // Noël
  ].map(x=>`${x.getFullYear()}-${x.getMonth()}-${x.getDate()}`));
  return set;
}
function joursOuvresMois(annee, moisIdx){
  const feries=feriesFR(annee);
  const nb=new Date(annee,moisIdx+1,0).getDate();
  let n=0;
  for(let j=1;j<=nb;j++){
    const dt=new Date(annee,moisIdx,j), dow=dt.getDay();
    if(dow===0||dow===6) continue;
    if(feries.has(`${annee}-${moisIdx}-${j}`)) continue;
    n++;
  }
  return n;
}
```

- [ ] **Step 2 : Vérifier dans la console du navigateur (app ouverte)**

Run (console) : `joursOuvresMois(2026,4)` (mai 2026).
Expected : `19` (mai 2026 : 21 jours ouvrés lun-ven − 1er mai − 8 mai − Ascension 14/05 = 19 ; recompter au calendrier réel et ajuster l'attendu si besoin).
Run : `joursOuvresMois(2026,2)` (mars 2026, sans férié) → Expected `22`.

- [ ] **Step 3 : Commit (après GO)**

```bash
cd upgrade-crm-lyon-V2
git add index.html
git commit -m "feat(interco): helper joursOuvresMois (jours ouvrés réels FR)"
```

---

## Task 4 : Recalcul de la carte data interco

**Files:**
- Modify: `upgrade-crm-lyon-V2/index.html` (bloc « Intercontrat mensuel » ~4751-4790 + chargement données)

**Interfaces:**
- Consumes: `interco_imputations` (Task 1), `joursOuvresMois` (Task 3), contacts statut « Consultant CDI ».
- Produces: variables `tauxInterM[]` (12), `tauxInterAnn`, `joursInterParMois[]`, `coutInterParMois[]`, `nbInterCourant`, recalculées sur le nouveau modèle. Le badge MALUS/Attention reste branché sur `tauxInterAnn`.

- [ ] **Step 1 : Charger les imputations interco**

Ajouter au chargement de données (là où `missions`/`contacts` sont fetchés) :
```javascript
const [intercoRows, setIntercoRows] = React.useState([]);
React.useEffect(()=>{ (async()=>{
  const { data } = await sb.from('interco_imputations').select('contact_consultant_id, annee, mois, jours, cjm_snapshot');
  setIntercoRows(data||[]);
})(); },[]);
```

- [ ] **Step 2 : Remplacer le calcul mission-based par le calcul contact-based**

Remplacer le bloc `// Intercontrat mensuel` (de `const JOURS_OUV = 18.16;` jusqu'à `tauxInterAnn`) par :
```javascript
const CY_IC = new Date().getFullYear();
const curMonthIdx = new Date().getMonth();
// effectif CDI = contacts uniques statut « Consultant CDI » du scope courant
const cdiContacts = (contacts||[]).filter(c => c.statut==='Consultant CDI'
  && (isAdmin || myMultiAgence || c.agence===profile.agence) );
const nbCdi = cdiContacts.length;
const cdiIds = new Set(cdiContacts.map(c=>c.id));
const cjmById = Object.fromEntries(cdiContacts.map(c=>[c.id, parseFloat(c.cjm)||0])); // ⚠️ confirmer le nom de colonne CJM contact (Step 4)

const interCY = intercoRows.filter(r => r.annee===CY_IC && cdiIds.has(r.contact_consultant_id));
const joursInterParMois = Array.from({length:12}, (_,i) =>
  interCY.filter(r=>r.mois===i+1).reduce((s,r)=>s+(parseFloat(r.jours)||0),0));
const coutInterParMois = Array.from({length:12}, (_,i) =>
  interCY.filter(r=>r.mois===i+1).reduce((s,r)=>s+(parseFloat(r.jours)||0)*(parseFloat(r.cjm_snapshot)||0),0));
const tauxInterM = joursInterParMois.map((j,i) => {
  const denom = nbCdi * joursOuvresMois(CY_IC, i);
  return denom>0 ? (j/denom)*100 : 0;
});
const joursInterYTD = joursInterParMois.slice(0,curMonthIdx+1).reduce((a,b)=>a+b,0);
const denomYTD = nbCdi * Array.from({length:curMonthIdx+1},(_,i)=>joursOuvresMois(CY_IC,i)).reduce((a,b)=>a+b,0);
const tauxInterAnn = denomYTD>0 ? (joursInterYTD/denomYTD)*100 : 0;
const coutInterYTD = coutInterParMois.slice(0,curMonthIdx+1).reduce((a,b)=>a+b,0);
const nbInterCourant = interCY.filter(r=>r.mois===curMonthIdx+1 && (parseFloat(r.jours)||0)>0).length;
```

- [ ] **Step 3 : Brancher la carte KPI sur les nouvelles variables**

Dans `KPI_CARDS`, remplacer la carte `id:'inter'` :
```javascript
{id:'inter',color:nbInterCourant>0?'#FFE500':'#ccc',value:nbInterCourant,label:'INTERCONTRAT',
  sub:nbInterCourant>0?`${joursInterYTD.toFixed(0)}j YTD · ${fmtK(coutInterYTD)}`:'Aucun',
  badge:tauxInterAnn>=8?'MALUS':tauxInterAnn>=5?'Attention':null,
  badgeColor:tauxInterAnn>=8?'#FF3D2E':'#92400e'},
```

- [ ] **Step 4 : Confirmer le nom de colonne CJM sur contacts**

Run (SQL Editor) :
```sql
select column_name from information_schema.columns
where table_name='contacts' and column_name ilike '%cjm%';
```
Si la colonne n'est pas `cjm`, corriger `cjmById` (Step 2) en conséquence.

- [ ] **Step 5 : Vérifier visuellement (données de test temporaires)**

Insérer une donnée connue puis recharger l'app :
```sql
insert into interco_imputations (contact_consultant_id, annee, mois, jours, cjm_snapshot)
values ((select id from contacts where statut='Consultant CDI' limit 1), 2026, 3, 9, 480);
```
Expected dans la carte : INTERCONTRAT affiche `9j YTD · 4K`, taux mars = `9 / (nbCdi × 22) × 100`. Vérifier le calcul à la main avec `nbCdi` affiché. Puis supprimer la donnée de test.

- [ ] **Step 6 : Commit (après GO)**

```bash
cd upgrade-crm-lyon-V2
git add index.html
git commit -m "feat(interco): carte data interco sur interco_imputations (consultants uniques + jours ouvrés réels)"
```

---

## Task 5 : Module de saisie interco — desktop (panneau fiche contact)

**Files:**
- Modify: `upgrade-crm-lyon-V2/index.html` (composant `EditContact` ~1085-1136)

**Interfaces:**
- Consumes: `joursOuvresMois` (Task 3), table `interco_imputations` (Task 1), `canEditInterco` (Step 1 ci-dessous).
- Produces: bloc `<IntercoEditor contact=... profile=... />` affiché uniquement quand `contact.statut==='Consultant CDI'`. Upsert sur `(contact_consultant_id, annee, mois)`.

- [ ] **Step 1 : Ajouter la garde d'écriture**

Près de `canEditAgence` (~1087) :
```javascript
const canEditInterco = (contact, profile) =>
  profile.role==='admin' || contact.agence===profile.agence || contact.responsable===profile.nom;
```

- [ ] **Step 2 : Écrire le composant `IntercoEditor` (mois courant + barre annuelle cliquable)**

```javascript
function IntercoEditor({contact, profile}){
  const annee = new Date().getFullYear();
  const curIdx = new Date().getMonth();
  const [rows,setRows]=React.useState([]);
  const [sel,setSel]=React.useState(curIdx);       // mois en édition
  const editable = profile.role==='admin' || contact.agence===profile.agence || contact.responsable===profile.nom;
  const MOIS=['Jan','Fév','Mar','Avr','Mai','Juin','Juil','Août','Sep','Oct','Nov','Déc'];
  const load=async()=>{ const {data}=await sb.from('interco_imputations')
    .select('mois,jours,cjm_snapshot').eq('contact_consultant_id',contact.id).eq('annee',annee);
    setRows(data||[]); };
  React.useEffect(()=>{ load(); },[contact.id]);
  const joursOf=(m)=>{ const r=rows.find(x=>x.mois===m+1); return r?parseFloat(r.jours)||0:0; };
  const save=async(m,jours)=>{
    if(!editable) return;
    const cjm=parseFloat(contact.cjm)||0; // ⚠️ même colonne CJM qu'en Task 4
    await sb.from('interco_imputations').upsert({
      contact_consultant_id:contact.id, annee, mois:m+1, jours,
      cjm_snapshot:cjm, updated_by:profile.nom, updated_at:new Date().toISOString()
    },{onConflict:'contact_consultant_id,annee,mois'});
    await load();
  };
  const ytd=rows.reduce((s,r)=>s+(parseFloat(r.jours)||0),0);
  const cout=rows.reduce((s,r)=>s+(parseFloat(r.jours)||0)*(parseFloat(r.cjm_snapshot)||0),0);
  const valSel=joursOf(sel);
  const ouv=joursOuvresMois(annee,sel);
  return (
    <div style={{border:'1px solid #e5e7eb',borderRadius:10,padding:12,marginTop:12}}>
      <div style={{fontSize:11,textTransform:'uppercase',letterSpacing:.5,color:'#6b7280',fontWeight:700,marginBottom:6}}>
        Interco — {MOIS[sel]} {annee}{sel===curIdx?' • mois courant':''}
        {sel!==curIdx && <span onClick={()=>setSel(curIdx)} style={{float:'right',color:'#4A7FE5',cursor:'pointer'}}>↩ mois courant</span>}
      </div>
      <div style={{display:'flex',gap:8,alignItems:'center',background:'#f0f5ff',border:'1px solid #4A7FE5',borderRadius:8,padding:8}}>
        <input type="number" min="0" step="0.5" value={valSel||''} disabled={!editable}
          onChange={e=>save(sel, parseFloat(e.target.value)||0)}
          style={{width:64,textAlign:'center',border:'1px solid #4A7FE5',borderRadius:6,padding:6,fontSize:18,fontWeight:700}}/>
        <span style={{fontSize:12}}>jours</span>
        {editable && <div style={{marginLeft:'auto',display:'flex',gap:6}}>
          <button onClick={()=>save(sel,ouv)} style={{padding:'6px 10px',borderRadius:6,border:'1px solid #4A7FE5',background:'#4A7FE5',color:'#fff',fontWeight:700,fontSize:12}}>100%</button>
          <button onClick={()=>save(sel,Math.round(ouv/2*2)/2)} style={{padding:'6px 10px',borderRadius:6,border:'1px solid #cbd5e1',background:'#fff',fontWeight:600,fontSize:12}}>50%</button>
        </div>}
      </div>
      <div style={{fontSize:10,textTransform:'uppercase',color:'#9ca3af',fontWeight:700,margin:'10px 0 4px'}}>Historique {annee} · clique un mois</div>
      <div style={{display:'flex',gap:3,alignItems:'flex-end',height:42}}>
        {MOIS.map((_,i)=>{ const j=joursOf(i); const h=Math.max(4,Math.min(36,j*4));
          const col=i===sel?'#92400e':(j>0?'#f59e0b':(i===curIdx?'#4A7FE5':'#e5e7eb'));
          return <div key={i} onClick={()=>setSel(i)} title={`${MOIS[i]} ${j}j`}
            style={{flex:1,background:col,height:h,borderRadius:2,cursor:'pointer',outline:i===sel?'2px solid #92400e':'none',outlineOffset:1}}/>; })}
      </div>
      <div style={{display:'flex',gap:3,fontSize:8,color:'#9ca3af',textAlign:'center',marginTop:3}}>
        {MOIS.map((m,i)=><span key={i} style={{flex:1,fontWeight:i===sel?700:400}}>{m[0]}</span>)}
      </div>
      <div style={{marginTop:10,paddingTop:8,borderTop:'2px solid #1C1F35',display:'flex',justifyContent:'space-between',fontSize:12,fontWeight:700}}>
        <span>YTD : {ytd.toFixed(ytd%1?1:0)}j</span><span style={{color:'#FF3D2E'}}>{Math.round(cout).toLocaleString('fr-FR')}€</span>
      </div>
      {!editable && <div style={{fontSize:11,color:'#9ca3af',marginTop:6}}>Lecture seule (hors agence/responsable).</div>}
    </div>
  );
}
```

- [ ] **Step 3 : Monter le composant dans `EditContact`**

Dans le rendu de `EditContact`, après les champs existants, ajouter :
```javascript
{f.statut==='Consultant CDI' && <IntercoEditor contact={contact} profile={profile} />}
```

- [ ] **Step 4 : Vérifier (navigateur, compte admin)**

Ouvrir une fiche contact « Consultant CDI » → éditer. Expected :
- le bloc Interco apparaît, mois courant pré-sélectionné ;
- clic « 100% » → le champ se remplit avec `joursOuvresMois` du mois, ligne créée en base (vérifier `select * from interco_imputations where contact_consultant_id=<id>`) ;
- clic sur une colonne d'un autre mois → le bloc bascule dessus, « ↩ mois courant » apparaît ;
- YTD + coût se mettent à jour ;
- ouvrir avec un compte hors agence/non responsable/non admin → bloc en lecture seule.

- [ ] **Step 5 : Commit (après GO)**

```bash
cd upgrade-crm-lyon-V2
git add index.html
git commit -m "feat(interco): module de saisie dans la fiche contact (desktop)"
```

---

## Task 6 : Module de saisie interco — adaptation mobile

**Files:**
- Modify: `upgrade-crm-lyon-V2/index.html` (composant `IntercoEditor`)

**Interfaces:**
- Consumes: `IntercoEditor` (Task 5). Pas de nouvelle interface — adaptation responsive du même composant.

- [ ] **Step 1 : Rendre la barre annuelle tapable sur mobile (pastilles) + clavier numérique**

Dans `IntercoEditor`, détecter le mobile et basculer l'historique en pastilles. Ajouter en tête du composant :
```javascript
const isMobile = typeof window!=='undefined' && window.matchMedia('(max-width:640px)').matches;
```
Sur l'input, ajouter `inputMode="numeric"` (déjà `type=number`, mais force le pavé num iOS).
Remplacer le rendu de l'historique (la `<div>` barre + labels) par un rendu conditionnel :
```javascript
{isMobile ? (
  <div style={{display:'flex',gap:8,overflowX:'auto',paddingBottom:6}}>
    {MOIS.map((m,i)=>{ const j=joursOf(i);
      const onSel=i===sel, has=j>0;
      return <div key={i} onClick={()=>setSel(i)} style={{flex:'0 0 auto',padding:'8px 12px',borderRadius:20,
        background:onSel?'#eef4ff':(has?'#fffbe6':'#f3f4f6'),
        border:onSel?'2px solid #4A7FE5':(has?'1px solid #f59e0b':'none'),
        color:onSel?'#4A7FE5':(has?'#92400e':'#9ca3af'),fontSize:13,fontWeight:has||onSel?700:600,whiteSpace:'nowrap'}}>
        {m} {j>0?`${j.toFixed(j%1?1:0)}j`:''}</div>; })}
  </div>
) : (
  /* barre annuelle desktop existante (Step 2 Task 5) */
)}
```

- [ ] **Step 2 : Vérifier en émulation mobile (DevTools, largeur ≤ 640px)**

Expected : l'historique devient une rangée de pastilles scrollable ; taper une pastille sélectionne le mois ; le gros champ ouvre le pavé numérique ; les boutons 100%/50% restent accessibles au pouce.

- [ ] **Step 3 : Commit (après GO)**

```bash
cd upgrade-crm-lyon-V2
git add index.html
git commit -m "feat(interco): adaptation mobile du module de saisie (pastilles tapables)"
```

---

## Task 7 : Outils MCP interco

**Files:**
- Modify: `upgrade-crm-mcp-src/server/index.mjs` (zone `server.tool(...)`)

**Interfaces:**
- Consumes: helpers `sbGet/sbPost/sbPatch/sbDelete`, table `interco_imputations`, table `contacts`.
- Produces: outils `crm_set_interco`, `crm_get_interco`, `crm_list_interco`, `crm_delete_interco`.

- [ ] **Step 1 : Écrire les 4 outils (pattern existant + log historique)**

Ajouter près des autres `server.tool` :
```javascript
// ─── helper : résoudre un consultant CDI par nom/email ───
async function resolveConsultant(q){
  const rows = await sbGet("contacts", { or:`(nom.ilike.*${q}*,email.ilike.*${q}*)`, statut:"eq.Consultant CDI", select:"id,nom,prenom,agence,responsable,cjm", limit:5 });
  return rows;
}

// ═══ crm_set_interco ═══
server.tool("crm_set_interco", "Définir (upsert) les jours d'intercontrat d'un consultant CDI sur un mois", {
  consultant: z.string().describe("nom ou email du consultant CDI"),
  annee: z.number(), mois: z.number().min(1).max(12), jours: z.number().min(0), responsable: z.string(),
}, async ({ consultant, annee, mois, jours, responsable }) => {
  try {
    const found = await resolveConsultant(consultant);
    if (!found.length) return { content:[{type:"text",text:`❌ Aucun « Consultant CDI » trouvé pour « ${consultant} ».`}] };
    if (found.length>1) return { content:[{type:"text",text:`⚠️ Plusieurs consultants : ${found.map(c=>`${c.prenom||''} ${c.nom} (id ${c.id})`).join(", ")}. Précise.`}] };
    const c = found[0];
    const cjm = parseFloat(c.cjm)||0;
    await sbPost("interco_imputations", [{
      contact_consultant_id:c.id, annee, mois, jours, cjm_snapshot:cjm,
      updated_by:responsable, updated_at:new Date().toISOString(),
    }].map(r=>r), ); // upsert via Prefer header ci-dessous
    return { content:[{type:"text",text:`✅ Interco ${c.prenom||''} ${c.nom} — ${mois}/${annee} : ${jours}j (coût ${Math.round(jours*cjm)}€)`}] };
  } catch (e) { return { content:[{type:"text",text:handleError(e)}] }; }
});
```
⚠️ PostgREST upsert : `sbPost` envoie un POST simple. Pour l'upsert sur la contrainte unique, ajouter le header `Prefer: resolution=merge-duplicates`. Étendre `sbPost` pour accepter des headers optionnels, OU créer un `sbUpsert(table, data)` dédié :
```javascript
async function sbUpsert(table, data){
  const token = await getToken();
  const resp = await fetch(`${SUPABASE_URL}/rest/v1/${table}`, {
    method:"POST",
    headers:{ ...mkHeaders(token), Prefer:"return=representation,resolution=merge-duplicates" },
    body: JSON.stringify(data),
  });
  if(!resp.ok) throw new Error(`UPSERT ${table} failed (${resp.status}): ${await resp.text()}`);
  const r = await resp.json(); return Array.isArray(r)?r[0]:r;
}
```
Et dans `crm_set_interco`, remplacer le `sbPost(...)` par `await sbUpsert("interco_imputations", { contact_consultant_id:c.id, annee, mois, jours, cjm_snapshot:cjm, updated_by:responsable, updated_at:new Date().toISOString() });`

```javascript
// ═══ crm_get_interco ═══
server.tool("crm_get_interco", "Lire l'intercontrat d'un consultant CDI pour une année", {
  consultant: z.string(), annee: z.number(),
}, async ({ consultant, annee }) => {
  try {
    const found = await resolveConsultant(consultant);
    if (!found.length) return { content:[{type:"text",text:`❌ Aucun consultant pour « ${consultant} ».`}] };
    const c = found[0];
    const rows = await sbGet("interco_imputations", { contact_consultant_id:`eq.${c.id}`, annee:`eq.${annee}`, order:"mois.asc", select:"mois,jours,cjm_snapshot" });
    const MOIS=["Jan","Fév","Mar","Avr","Mai","Juin","Juil","Août","Sep","Oct","Nov","Déc"];
    const tot=rows.reduce((s,r)=>s+(+r.jours||0),0), cout=rows.reduce((s,r)=>s+(+r.jours||0)*(+r.cjm_snapshot||0),0);
    const lignes=rows.filter(r=>+r.jours>0).map(r=>`- ${MOIS[r.mois-1]} : ${r.jours}j`).join("\n")||"_aucun mois_";
    return { content:[{type:"text",text:`**Interco ${c.prenom||''} ${c.nom} — ${annee}**\n${lignes}\n\n**Total : ${tot}j · coût ${Math.round(cout)}€**`}] };
  } catch (e) { return { content:[{type:"text",text:handleError(e)}] }; }
});

// ═══ crm_list_interco ═══
server.tool("crm_list_interco", "Vue d'ensemble interco (taux + seuils) sur un mois ou une année", {
  annee: z.number(), mois: z.number().min(1).max(12).optional(), agence: z.string().optional(),
}, async ({ annee, mois, agence }) => {
  try {
    const cP = { statut:"eq.Consultant CDI", select:"id,nom,prenom,agence" };
    if (agence) cP.agence=`eq.${agence}`;
    const cdis = await sbGet("contacts", cP);
    const nbCdi = cdis.length;
    const ids = new Set(cdis.map(c=>c.id));
    const iP = { annee:`eq.${annee}`, select:"contact_consultant_id,mois,jours,cjm_snapshot" };
    if (mois) iP.mois=`eq.${mois}`;
    let rows = await sbGet("interco_imputations", iP);
    rows = rows.filter(r=>ids.has(r.contact_consultant_id));
    const jours = rows.reduce((s,r)=>s+(+r.jours||0),0);
    const cout = rows.reduce((s,r)=>s+(+r.jours||0)*(+r.cjm_snapshot||0),0);
    // jours ouvrés réels (réplique de joursOuvresMois côté serveur — voir Step 2)
    const moisListe = mois ? [mois] : Array.from({length:12},(_,i)=>i+1);
    const denom = nbCdi * moisListe.reduce((s,m)=>s+joursOuvresMoisSrv(annee,m-1),0);
    const taux = denom>0 ? (jours/denom*100) : 0;
    const badge = taux>=8?"🔴 MALUS":taux>=5?"🟠 Attention":"🟢 OK";
    return { content:[{type:"text",text:`**Interco ${agence||"France"} — ${mois?`${mois}/`:""}${annee}**\nCDI : ${nbCdi} · jours interco : ${jours} · coût : ${Math.round(cout)}€\nTaux : **${taux.toFixed(1)}%** ${badge}`}] };
  } catch (e) { return { content:[{type:"text",text:handleError(e)}] }; }
});

// ═══ crm_delete_interco ═══
server.tool("crm_delete_interco", "Remettre à 0 (supprimer) l'interco d'un consultant sur un mois", {
  consultant: z.string(), annee: z.number(), mois: z.number().min(1).max(12),
}, async ({ consultant, annee, mois }) => {
  try {
    const found = await resolveConsultant(consultant);
    if (!found.length) return { content:[{type:"text",text:`❌ Aucun consultant pour « ${consultant} ».`}] };
    const c = found[0];
    await sbDelete("interco_imputations", { contact_consultant_id:c.id, annee, mois });
    return { content:[{type:"text",text:`✅ Interco ${c.prenom||''} ${c.nom} ${mois}/${annee} supprimé.`}] };
  } catch (e) { return { content:[{type:"text",text:handleError(e)}] }; }
});
```

- [ ] **Step 2 : Ajouter le helper jours ouvrés côté serveur**

Copier `feriesFR` + une version `joursOuvresMoisSrv(annee, moisIdx)` (identique à Task 3) près des helpers date du MCP, pour `crm_list_interco`.

- [ ] **Step 3 : Vérifier les outils (appels MCP réels)**

Depuis Claude (session avec le MCP) :
- `crm_set_interco(consultant="<nom CDI connu>", annee=2026, mois=3, jours=9, responsable="Nicolas Serradeil")` → ✅ + coût.
- `crm_get_interco(consultant="<même>", annee=2026)` → liste mars 9j, total cohérent.
- `crm_list_interco(annee=2026, mois=3)` → taux + badge.
- `crm_delete_interco(consultant="<même>", annee=2026, mois=3)` → ✅ ; un `crm_get_interco` confirme la suppression.

- [ ] **Step 4 : Commit (après GO)**

```bash
cd upgrade-crm-mcp-src
git add server/index.mjs
git commit -m "feat(interco): outils MCP set/get/list/delete interco"
```

---

## Task 8 : Migration de l'existant + sauvegarde

**Files:**
- Create: `upgrade-crm-mcp-src/server/backup_interco_missions.mjs`
- Create: `upgrade-crm-lyon-V2/db/03_interco_migration.sql`
- Create: `upgrade-crm-lyon-V2/db/04_interco_verif.sql`

**Interfaces:**
- Consumes: missions `statut='Intercontrat'` (colonnes `jours_jan..jours_dec`, `contact_consultant_id`, `cjm`), table `interco_imputations`.
- Produces: lignes `interco_imputations` issues des missions interco + fichier de sauvegarde JSON.

- [ ] **Step 1 : Script de sauvegarde des missions interco**

```javascript
// backup_interco_missions.mjs — exécuter : node backup_interco_missions.mjs > backup_interco_missions.json
import fs from "node:fs";
const SUPABASE_URL="https://ehfseahxoivfhmpiyoqa.supabase.co";
// réutiliser getToken/sbGet : importer depuis index.mjs OU recopier la logique d'auth.
// Ici version autonome minimale :
const EMAIL=process.env.SUPABASE_EMAIL, PASS=process.env.SUPABASE_PASSWORD, ANON=process.env.SUPABASE_ANON_KEY;
const t=await (await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`,{method:"POST",headers:{apikey:ANON,"Content-Type":"application/json"},body:JSON.stringify({email:EMAIL,password:PASS})})).json();
const rows=await (await fetch(`${SUPABASE_URL}/rest/v1/missions?statut=eq.Intercontrat&select=*`,{headers:{apikey:ANON,Authorization:`Bearer ${t.access_token}`}})).json();
fs.writeFileSync("backup_interco_missions.json", JSON.stringify(rows,null,2));
console.error(`Sauvegardé ${rows.length} missions interco.`);
```
Lancer : `SUPABASE_ANON_KEY=<anon> node backup_interco_missions.mjs`. Expected : fichier `backup_interco_missions.json` créé, taille > 0.

- [ ] **Step 2 : SQL de migration (missions interco → lignes mensuelles)**

```sql
-- db/03_interco_migration.sql
insert into interco_imputations (contact_consultant_id, annee, mois, jours, cjm_snapshot, updated_by, updated_at)
select m.contact_consultant_id,
       2026 as annee,
       v.mois,
       v.jours,
       m.cjm as cjm_snapshot,
       'migration' as updated_by,
       now()
from missions m
cross join lateral (values
  (1,m.jours_jan),(2,m.jours_fev),(3,m.jours_mar),(4,m.jours_avr),
  (5,m.jours_mai),(6,m.jours_jun),(7,m.jours_jui),(8,m.jours_aou),
  (9,m.jours_sep),(10,m.jours_oct),(11,m.jours_nov),(12,m.jours_dec)
) as v(mois,jours)
where m.statut='Intercontrat'
  and m.contact_consultant_id is not null
  and coalesce(v.jours,0) > 0
on conflict (contact_consultant_id, annee, mois) do nothing;
```
⚠️ Confirmer les noms exacts des colonnes `jours_*` sur `missions` (Step 0 ci-dessous) et l'année réelle des imputations (ici 2026). Si des missions interco portent des imputations multi-années, adapter (la table missions n'a pas d'année par colonne → toutes supposées année courante ; vérifier au Step 4).

- [ ] **Step 0 (avant Step 2) : Confirmer les noms de colonnes jours_* missions**

Run :
```sql
select column_name from information_schema.columns
where table_name='missions' and column_name like 'jours_%' order by column_name;
```
Adapter le `values (...)` du Step 2 aux noms réels.

- [ ] **Step 3 : Exécuter la migration**

Coller `db/03_interco_migration.sql` dans Supabase SQL Editor → Run.
Expected : `INSERT N` où N = nb de couples (consultant, mois) migrés.

- [ ] **Step 4 : Vérifier l'égalité des totaux avant/après**

```sql
-- db/04_interco_verif.sql
-- total jours interco par mois — source missions
with src as (
  select 3 mois, sum(jours_mar) j from missions where statut='Intercontrat'
  union all select 1, sum(jours_jan) from missions where statut='Intercontrat'
  -- ... (lister les 12 mois)
),
dst as (
  select mois, sum(jours) j from interco_imputations where annee=2026 group by mois
)
select coalesce(src.mois,dst.mois) mois, src.j src_jours, dst.j dst_jours,
       coalesce(src.j,0)-coalesce(dst.j,0) ecart
from src full outer join dst on src.mois=dst.mois order by 1;
```
Expected : colonne `ecart` = 0 (ou NULL↔0) sur tous les mois. **Si un écart ≠ 0 → STOP, ne pas passer à la Task 9, investiguer.**

- [ ] **Step 5 : Commit (après GO)**

```bash
cd upgrade-crm-lyon-V2 && git add db/03_interco_migration.sql db/04_interco_verif.sql && git commit -m "feat(interco): migration missions interco → interco_imputations + vérif"
cd ../upgrade-crm-mcp-src && git add server/backup_interco_missions.mjs && git commit -m "chore(interco): script de sauvegarde des missions interco"
```

---

## Task 9 : Suppression des missions interco + nettoyage du code mort

**Files:**
- Create: `upgrade-crm-lyon-V2/db/05_interco_cleanup.sql`
- Modify: `upgrade-crm-lyon-V2/index.html` (`MISSION_STATUTS` ~1684, `<option value="Intercontrat">` ~4850/5178/5627, couleurs statut ~886)

**Interfaces:**
- Consumes: vérification Task 8 (écarts = 0) **obligatoire avant cette tâche**.

- [ ] **Step 1 : Garde-fou — re-vérifier l'égalité des totaux**

Re-lancer `db/04_interco_verif.sql`. Expected : `ecart=0` partout. Sinon STOP.

- [ ] **Step 2 : Supprimer les missions interco**

```sql
-- db/05_interco_cleanup.sql
delete from missions where statut='Intercontrat';
```
Run. Expected : `DELETE N` (= nb de missions interco sauvegardées au Task 8 Step 1).

- [ ] **Step 3 : Retirer le statut Intercontrat du code app**

Dans `index.html` :
- `MISSION_STATUTS` : retirer `'Intercontrat'`.
- supprimer les `<option value="Intercontrat">Intercontrat</option>` (3 occurrences).
- retirer l'entrée couleur `'Intercontrat': {...}` (~886) si plus utilisée.
- supprimer le `const intercontrat = missionsFiltrees.filter(...)` résiduel et tout code de calcul interco basé missions devenu mort (le calcul vit désormais sur `intercoRows`, Task 4).

- [ ] **Step 4 : Vérifier (navigateur)**

Expected :
- plus aucune mission « Intercontrat » dans la liste des missions ;
- la carte data interco affiche toujours les bons chiffres (issus de `interco_imputations`) ;
- le sélecteur de statut de mission n'offre plus « Intercontrat » ;
- aucune erreur console.

- [ ] **Step 5 : Commit (après GO)**

```bash
cd upgrade-crm-lyon-V2
git add db/05_interco_cleanup.sql index.html
git commit -m "feat(interco): suppression des missions interco + retrait du statut (code mort)"
```

---

## Ordre d'exécution & dépendances

1 → 2 (RLS dépend de la table) · 3 (indépendant) · 4 (dépend de 1+3) · 5 (dépend de 1+3) · 6 (dépend de 5) · 7 (dépend de 1) · **8 (dépend de 1)** · **9 (dépend STRICTEMENT de la vérif de 8 = écarts 0)**.

Tasks 3, 7 peuvent se faire en parallèle de 4/5/6. **Task 9 ne démarre jamais sans la vérif verte de Task 8.**

## Points à confirmer au build (rappel spec)
1. Nom exact de la colonne **CJM sur `contacts`** (Task 4 Step 4) — réutilisé Task 5/7.
2. Nom de la **table de profils** + colonnes `nom/agence/role` + clé `auth.uid()` (Task 2 Step 1).
3. Noms exacts des colonnes **`jours_*` sur `missions`** (Task 8 Step 0).
4. Année des imputations missions (Task 8 Step 2) — confirmer mono-année.
