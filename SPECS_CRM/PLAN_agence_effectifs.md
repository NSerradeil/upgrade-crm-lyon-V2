# Onglet « Agence » — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter au CRM un onglet « Agence » (effectifs CDI + sous-traitants, filtrables par agence, coût/TJM/marge/dispo, export Excel, alertes de fin de mission) qui remplace le fichier `Point_COLLAB-UPGRADE.xlsx` de Pierre.

**Architecture:** L'app est un `index.html` mono-fichier React compilé par Babel standalone ; les collaborateurs sont des `contacts` (statuts `Consultant CDI` / `Freelance` / `Prestataire`) déjà liés aux `missions` et à `interco_imputations`. On étend `contacts` par migration, on isole toute la logique de calcul dans un **nouveau fichier JS pur `agence-calc.js`** (testable avec `node --test`, chargé avant le script Babel), et on ajoute un composant `TabAgence` + un volet `CollabDetail` qui réutilisent les patterns existants (toggle segmenté, `thCls`, `SidePanel`, `IntercoEditor`, `MissionDetail`). Aucune requête Supabase supplémentaire : tout est dérivé de `fetchAll` en `useMemo`.

**Tech Stack:** React 18 UMD + Babel standalone, Tailwind CDN, Supabase JS v2 (PostgREST + RLS), SheetJS `xlsx` 0.18.5 (lazy), Node 20 `node --test`, Python 3 + `openpyxl` (import), MCP server Node (`upgrade-crm-mcp-src`).

**Spec:** `SPECS_CRM/SPEC_agence_effectifs.md`

## Global Constraints

- Une SyntaxError JSX dans `index.html` = écran blanc total : après CHAQUE modif de `index.html`, exécuter le check de syntaxe de la Task 0 (extraction du bloc Babel + `npx @babel/cli`-less check via Babel standalone dans node) — voir Task 0 step 3.
- Règle déploiement : **local d'abord** (`python3 -m http.server 8080` dans le repo, ouvrir `http://localhost:8080/index.html`), capture, OK Nicolas, PUIS SQL collé dans Supabase, PUIS `git push` par Nicolas (`git push` est deny-ruled pour l'agent).
- Le SQL de `db/*.sql` **ne s'applique pas seul** : Nicolas le colle dans le SQL Editor Supabase. Chaque migration se termine par une requête de vérification.
- Couleurs : orange `#F97316` = Dispo ≤ 60 j / marge < 30 % ; rouge `#FF3D2E` = Dispo ≤ 30 j / marge < 20 % ; vert `#00C218` = > 60 j ; gris `#E4E4E6` = intercontrat / sans mission ; coral `#FF3D2E` fond + texte blanc = arrêt maladie / congé.
- Formule CJM : `round(salaire_annuel / 215 * 1.7, 2)`. Marge : `(tjm - cjm) / tjm`.
- Tâches CRM créées par le code : `due_date` = prochain jour ouvré (lun-ven hors `FERIES_FR`) à **09:30**, jamais avant 9h / 12-14h / après 18h30.
- Pas de tirets cadratins dans les libellés visibles par l'utilisateur ; français, ton court.
- Commits : messages en français, préfixe `feat(agence):` / `fix(agence):` / `test(agence):` / `db:` / `mcp:`, terminés par la ligne `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Ne jamais toucher aux policies partner existantes de `db/04`/`db/05` autrement que par l'extension `partner_lead` de `is_my_consultant()` (Task 1).

---

## Carte des fichiers

| Fichier | Rôle | Tâches |
|---|---|---|
| `tests/check-babel.mjs` (créer) | vérifie que le bloc `<script type="text/babel">` compile (anti écran blanc) | 0 |
| `db/20_agence.sql` (créer) | colonnes `contacts`, `profiles.partner_lead`, `is_my_consultant()` élargi, backfill `type_presta`, vérifications | 1 |
| `DEPLOY.md` (modifier) | ligne migration 20 | 1 |
| `agence-calc.js` (créer) | logique pure : `computeCollab`, `etatDispo`, `computeKpis`, `prochainJourOuvre930`, `planAlertes`, `MANAGER_TRIGRAMMES`, `cjmFromSalaire` | 2 |
| `tests/agence-calc.test.mjs` (créer) | tests `node --test` de `agence-calc.js` | 2 |
| `index.html` | `<script src="agence-calc.js">`, `fetchAll` colonnes, `partnerSet` + `partner_lead`, `TABS`/`TAB_COLORS`/raccourcis, `KpiCards` extrait du TDB + dalle interco retirée du TDB, `TabAgence` (4 dalles + détails `ChartEffectif`/`ChartInter`/`ChartTjm`/`ChartMargeAgence`), `CollabDetail`, formulaires, `exportEffectifs`, `ensureAlertesDispo` | 3, 3b, 4-8 |
| `service-worker.js` (modifier) | bump `CACHE_NAME` → `upgrade-crm-v4` (nouveau fichier statique) | 3 |
| `../upgrade-crm-mcp-src/server/index.mjs` + `manifest.json` | `crm_set_cjm` → `cjm_manuel=true`, champs contact autorisés, version 8.15.0 | 9 |
| `~/Pro/Jules/bin/crm-import-collab.py` (créer) + `~/Pro/Jules/tests/test_crm_import_collab.py` (créer) | import Excel dry-run/apply | 10 |

---

### Task 0: Garde-fou syntaxe Babel

**Files:**
- Create: `tests/check-babel.mjs`

**Interfaces:**
- Produces: commande `node tests/check-babel.mjs` → exit 0 si le JSX compile, exit 1 + ligne/colonne sinon. Toutes les tâches suivantes l'exécutent après chaque modif de `index.html`.

- [ ] **Step 1: Écrire le script**

```js
// tests/check-babel.mjs — compile le bloc <script type="text/babel"> d'index.html avec Babel standalone
// (même moteur que le navigateur) pour attraper une SyntaxError AVANT de recharger la page.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
let Babel;
try { Babel = require('@babel/standalone'); }
catch { console.error('npm i -g @babel/standalone  (ou: npm i --no-save @babel/standalone dans le repo)'); process.exit(2); }
const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const m = html.match(/<script type="text\/babel">([\s\S]*?)<\/script>/);
if (!m) { console.error('bloc text/babel introuvable'); process.exit(1); }
try {
  Babel.transform(m[1], { presets: ['react'], filename: 'index.html' });
  console.log('OK babel');
} catch (e) {
  const off = html.indexOf(m[1]); const lineOffset = html.slice(0, off).split('\n').length - 1;
  console.error(`SyntaxError index.html:${(e.loc?.line||0)+lineOffset}:${e.loc?.column||0} — ${e.message.split('\n')[0]}`);
  process.exit(1);
}
```

- [ ] **Step 2: Installer Babel standalone en local (hors git)**

Run: `cd ~/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2 && npm i --no-save @babel/standalone@7.26.10 >/dev/null && echo node_modules/ >> .gitignore && sort -u .gitignore -o .gitignore`
Expected: pas d'erreur ; `.gitignore` contient `node_modules/`.

- [ ] **Step 3: Vérifier que le check passe sur l'état actuel**

Run: `node tests/check-babel.mjs`
Expected: `OK babel`

- [ ] **Step 4: Vérifier qu'il détecte une erreur (test négatif)**

Run: `cp index.html /tmp/ix.bak && sed -i '' '8253s/return (/return (<div>/' index.html && node tests/check-babel.mjs; echo "exit=$?"; cp /tmp/ix.bak index.html && node tests/check-babel.mjs`
Expected: première exécution → `SyntaxError index.html:…` + `exit=1` ; seconde → `OK babel`.

- [ ] **Step 5: Commit**

```bash
git add tests/check-babel.mjs .gitignore
git commit -m "test: garde-fou compilation Babel d'index.html

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 1: Migration `db/20_agence.sql`

**Files:**
- Create: `db/20_agence.sql`
- Modify: `DEPLOY.md` (ajouter une ligne dans la liste des migrations, à la suite de la mention de `db/`)

**Interfaces:**
- Produces: colonnes `contacts.date_entree date`, `contacts.date_sortie date`, `contacts.salaire_annuel numeric(10,2)`, `contacts.cjm_manuel boolean not null default false`, `contacts.statut_rh text` (check `arret_maladie|conge`), `contacts.statut_rh_depuis date`, `contacts.type_presta text` (check `freelance|sous_traitant`), `contacts.manager_trigramme text` ; `profiles.partner_lead boolean not null default false` ; fonction `is_my_consultant(bigint)` élargie.

- [ ] **Step 1: Écrire la migration**

```sql
-- db/20_agence.sql — Onglet Agence (SPEC_agence_effectifs.md)
-- À coller dans le SQL Editor Supabase (superuser). Idempotent.
begin;

-- 1) contacts : données collaborateur --------------------------------------
alter table public.contacts
  add column if not exists date_entree       date,
  add column if not exists date_sortie       date,
  add column if not exists salaire_annuel    numeric(10,2),
  add column if not exists cjm_manuel        boolean not null default false,
  add column if not exists statut_rh         text,
  add column if not exists statut_rh_depuis  date,
  add column if not exists type_presta       text,
  add column if not exists manager_trigramme text;

alter table public.contacts drop constraint if exists contacts_statut_rh_check;
alter table public.contacts add constraint contacts_statut_rh_check
  check (statut_rh is null or statut_rh in ('arret_maladie','conge'));

alter table public.contacts drop constraint if exists contacts_type_presta_check;
alter table public.contacts add constraint contacts_type_presta_check
  check (type_presta is null or type_presta in ('freelance','sous_traitant'));

-- Backfill type_presta depuis le statut existant
update public.contacts set type_presta='freelance'     where statut='Freelance'   and type_presta is null;
update public.contacts set type_presta='sous_traitant' where statut='Prestataire' and type_presta is null;

-- Un CJM déjà saisi avant la migration est par définition manuel (pas dérivé d'un salaire)
update public.contacts set cjm_manuel=true where cjm is not null and salaire_annuel is null;

-- 2) profiles : partner « des partners » --------------------------------------
alter table public.profiles add column if not exists partner_lead boolean not null default false;

-- 3) is_my_consultant : un partner_lead voit/édite l'union de tous les partners ----
create or replace function public.is_my_consultant(c_id bigint)
returns boolean language sql stable security definer
set search_path = public as $$
  select exists (
    select 1 from public.partner_consultants pc
    where pc.contact_consultant_id = c_id
      and ( pc.partner_id = auth.uid()
            or exists (select 1 from public.profiles p where p.id = auth.uid() and p.partner_lead) )
  );
$$;

commit;

-- 4) Vérifications (à lire après exécution) -----------------------------------
select column_name, data_type from information_schema.columns
 where table_name='contacts' and column_name in
 ('date_entree','date_sortie','salaire_annuel','cjm_manuel','statut_rh','statut_rh_depuis','type_presta','manager_trigramme')
 order by column_name;                                   -- attendu : 8 lignes
select column_name from information_schema.columns where table_name='profiles' and column_name='partner_lead'; -- 1 ligne
select type_presta, count(*) from public.contacts where statut in ('Freelance','Prestataire') group by 1;  -- 0 null
select pg_get_functiondef('public.is_my_consultant(bigint)'::regprocedure) like '%partner_lead%' as ok;      -- true
```

- [ ] **Step 2: Vérifier la syntaxe SQL localement (pas d'exécution)**

Run: `python3 -c "import re,sys;s=open('db/20_agence.sql').read();assert s.count('begin;')==1 and s.count('commit;')==1;print('ok', len(s))"`
Expected: `ok <taille>`

- [ ] **Step 3: Ajouter la ligne dans DEPLOY.md**

Dans `DEPLOY.md`, sous la ligne 11 (`| **Schéma DB** ... |`), ajouter à la fin du tableau ou de la section migrations :

```markdown
- `db/20_agence.sql` — onglet Agence : colonnes collaborateur sur `contacts` (date_entree, date_sortie, salaire_annuel, cjm_manuel, statut_rh, statut_rh_depuis, type_presta, manager_trigramme), `profiles.partner_lead`, `is_my_consultant()` élargi. **À appliquer AVANT de pousser l'app** (le `select` de `fetchAll` référence les nouvelles colonnes → 400 sinon).
```

- [ ] **Step 4: Commit**

```bash
git add db/20_agence.sql DEPLOY.md
git commit -m "db: migration 20 onglet Agence (colonnes collaborateur, partner_lead)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- [ ] **Step 5: Demander à Nicolas d'appliquer la migration**

Message à Nicolas (Slack/terminal) : « Migration `db/20_agence.sql` prête. Colle-la dans le SQL Editor Supabase et renvoie-moi le résultat des 4 selects de vérification (8 lignes / 1 ligne / 0 null / true). Sans elle, la prochaine version de l'app renverra une erreur 400 au chargement. » **Les tasks 3+ ne se déploient pas en prod avant cette confirmation** (le travail local peut continuer : Supabase local n'existe pas, donc en local on pointe déjà la prod → attendre la migration avant de charger l'app avec le nouveau `select`).

---

### Task 2: `agence-calc.js` — logique pure + tests

**Files:**
- Create: `agence-calc.js`
- Create: `tests/agence-calc.test.mjs`

**Interfaces:**
- Produces (global `window.AgenceCalc` / `module.exports`) :
  - `cjmFromSalaire(salaire:number) → number` (2 décimales)
  - `joursEntre(fromISO:string, toISO:string) → number` (entier, `to - from` en jours)
  - `computeCollab(contact, {missions, intercos, partnerNomById, partnerIdByContact, todayISO, annee}) → Collab`
    où `Collab = {...contact, missionEnCours, joursAvantDispo, tjm, cjm, marge, intercoAnnee, etat, sorti, partnerNom, typeLabel}`
    et `etat ∈ 'arret_maladie'|'conge'|'en_mission'|'demarre_bientot'|'intercontrat'|'sans_mission'`
  - `etatDispo(collab) → {label:string, bg:string, color:string}` (couleurs des Global Constraints)
  - `margeStyle(marge:number|null) → {color:string}` (`#1C1F35` normal, `#F97316` < 0.30, `#FF3D2E` < 0.20)
  - `computeKpis(collabs:Collab[], mode:'cdi'|'st') → {effectif, cjmMoyen, tjmMoyen, margeMoyenne, dispo60, intercoAnnee, fins60}`
  - `prochainJourOuvre930(todayISO, feries:Set<string>) → string` ISO `YYYY-MM-DDT09:30:00` (jour suivant ouvré, jamais aujourd'hui)
  - `planAlertes(collabs, taches, {todayISO, feries, profilNom}) → {aCreer:TacheInsert[], aClore:{id:string, note:string}[]}`
  - `arriveesSortiesParMois(collabs, annee) → {arrivees:number[12], sorties:number[12], cumul:number[12], listeArrivees:Collab[][12]}` (cumul = effectif présent en fin de chaque mois)
  - `tranchesTjm(collabs) → [{label:'< 500 €', min, max, items:Collab[]}, …]` (bornes 500/600/700)
  - `tranchesMarge(collabs) → [{label:'< 20 %', color:'#FF3D2E', items}, {label:'20-30 %', color:'#F97316', items}, {label:'30-40 %', color:'#1C1F35', items}, {label:'> 40 %', color:'#00C218', items}]`
  - `tjmMargeParMois(missions, annee) → {tjm:(number|null)[12], marge:(number|null)[12]}` (moyennes sur les missions ayant `jours_<mois> > 0`, pondération simple par mission)
  - `intercoStats(cdiIds:Set<number>, intercos, annee, curMonthIdx, joursOuvresMois:(annee,idx)=>number) → {tauxM:number[12], tauxAnn:number, joursYTD:number, coutYTD:number, idxAff:number, fallbackM1:boolean, nbCourant:number, parMois:(idx)=>{contact_consultant_id,jours,cout}[]}` (reprise à l'identique de la logique TDB lignes 5881-5906)
  - `MANAGER_TRIGRAMMES: Record<string,string>`
  - `CONSULTANT_STATUTS_AGENCE = ['Consultant CDI','Freelance','Prestataire']`, `CDI_STATUTS=['Consultant CDI']`, `ST_STATUTS=['Freelance','Prestataire']`

- [ ] **Step 1: Écrire les tests (ils échouent : fichier absent)**

```js
// tests/agence-calc.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import '../agence-calc.js';
const A = globalThis.AgenceCalc;

const T = '2026-09-14';
const FERIES = new Set(['2026-11-11']);
const base = { id: 1, prenom: 'Laurie', nom: 'MARTINEAU', statut: 'Consultant CDI', agence: 'Lyon', cjm: 411.16, responsable: 'Nicolas Serradeil' };
const mk = (over) => ({ ...base, ...over });
const ctx = (missions = [], intercos = [], extra = {}) => ({ missions, intercos, partnerNomById: { 'u-majo': 'Majo Paquelier' }, partnerIdByContact: {}, todayISO: T, annee: 2026, ...extra });

test('cjmFromSalaire : 61000 → 482.33', () => { assert.equal(A.cjmFromSalaire(61000), 482.33); });
test('joursEntre', () => { assert.equal(A.joursEntre('2026-09-14', '2026-12-31'), 108); assert.equal(A.joursEntre('2026-09-14', '2026-09-11'), -3); });

test('en mission > 60 j → vert', () => {
  const c = A.computeCollab(mk(), ctx([{ id: 'm1', contact_consultant_id: 1, statut: 'En cours', tjm: 490, cjm: 411.16, date_fin_mission: '2026-12-31', client: 'EDF' }]));
  assert.equal(c.etat, 'en_mission'); assert.equal(c.joursAvantDispo, 108); assert.equal(c.tjm, 490);
  assert.equal(Math.round(c.marge * 1000) / 1000, 0.161);
  assert.equal(A.etatDispo(c).bg, '#00C218');
});
test('≤ 60 j → orange, ≤ 30 j → rouge, dépassée → rouge libellé', () => {
  const m = (fin) => [{ id: 'm', contact_consultant_id: 1, statut: 'En cours', tjm: 600, date_fin_mission: fin }];
  assert.equal(A.etatDispo(A.computeCollab(mk(), ctx(m('2026-10-30')))).bg, '#F97316');   // 46 j
  assert.equal(A.etatDispo(A.computeCollab(mk(), ctx(m('2026-09-30')))).bg, '#FF3D2E');   // 16 j
  const dep = A.etatDispo(A.computeCollab(mk(), ctx(m('2026-09-11'))));
  assert.equal(dep.bg, '#FF3D2E'); assert.match(dep.label, /dépassée de 3 j/);
});
test('mission sans date de fin → en_mission, joursAvantDispo null', () => {
  const c = A.computeCollab(mk(), ctx([{ id: 'm', contact_consultant_id: 1, statut: 'En cours', tjm: 600, date_fin_mission: null }]));
  assert.equal(c.etat, 'en_mission'); assert.equal(c.joursAvantDispo, null); assert.match(A.etatDispo(c).label, /fin non définie/);
});
test('CDI sans mission → intercontrat + cumul année', () => {
  const c = A.computeCollab(mk(), ctx([], [{ contact_consultant_id: 1, annee: 2026, mois: 8, jours: 12 }, { contact_consultant_id: 1, annee: 2026, mois: 9, jours: 5.5 }, { contact_consultant_id: 1, annee: 2025, mois: 12, jours: 9 }]));
  assert.equal(c.etat, 'intercontrat'); assert.equal(c.intercoAnnee, 17.5);
  assert.equal(A.etatDispo(c).bg, '#E4E4E6'); assert.match(A.etatDispo(c).label, /17,5 j cumulés 2026/);
});
test('ST sans mission → sans_mission ; typeLabel', () => {
  const c = A.computeCollab(mk({ statut: 'Freelance', type_presta: 'freelance' }), ctx());
  assert.equal(c.etat, 'sans_mission'); assert.equal(c.typeLabel, 'Freelance');
  assert.equal(A.computeCollab(mk({ statut: 'Prestataire', type_presta: 'sous_traitant' }), ctx()).typeLabel, 'Sous-traitant');
});
test('statut_rh prime sur la mission', () => {
  const c = A.computeCollab(mk({ statut_rh: 'arret_maladie', statut_rh_depuis: '2026-09-01' }), ctx([{ id: 'm', contact_consultant_id: 1, statut: 'En cours', tjm: 600, date_fin_mission: '2026-12-31' }]));
  assert.equal(c.etat, 'arret_maladie'); const b = A.etatDispo(c); assert.equal(b.bg, '#FF3D2E'); assert.equal(b.color, '#FFFFFF'); assert.match(b.label, /Arrêt maladie · depuis le 01\/09/);
});
test('mission New à venir → demarre_bientot', () => {
  const c = A.computeCollab(mk(), ctx([{ id: 'm', contact_consultant_id: 1, statut: 'New', tjm: 600, date_debut_mission: '2026-09-22', date_fin_mission: '2026-12-31' }]));
  assert.equal(c.etat, 'demarre_bientot'); assert.match(A.etatDispo(c).label, /démarre le 22\/09/);
});
test('plusieurs missions En cours → la fin la plus lointaine', () => {
  const c = A.computeCollab(mk(), ctx([{ id: 'a', contact_consultant_id: 1, statut: 'En cours', tjm: 500, date_fin_mission: '2026-10-01' }, { id: 'b', contact_consultant_id: 1, statut: 'En cours', tjm: 600, date_fin_mission: '2026-12-31' }]));
  assert.equal(c.missionEnCours.id, 'b');
});
test('sorti + partnerNom + fallback trigramme', () => {
  const c1 = A.computeCollab(mk({ date_sortie: '2026-06-30', manager_trigramme: 'NSE' }), ctx([], [], { partnerIdByContact: {} }));
  assert.equal(c1.sorti, true); assert.equal(c1.partnerNom, 'Nicolas Serradeil');
  const c2 = A.computeCollab(mk({ date_sortie: '2027-01-01' }), ctx([], [], { partnerIdByContact: { 1: 'u-majo' } }));
  assert.equal(c2.sorti, false); assert.equal(c2.partnerNom, 'Majo Paquelier');
});
test('margeStyle', () => {
  assert.equal(A.margeStyle(0.35).color, '#1C1F35'); assert.equal(A.margeStyle(0.25).color, '#F97316'); assert.equal(A.margeStyle(0.15).color, '#FF3D2E'); assert.equal(A.margeStyle(null).color, '#A4A6AB');
});
test('computeKpis cdi', () => {
  const cs = [
    A.computeCollab(mk({ id: 1, cjm: 400 }), ctx([{ id: 'a', contact_consultant_id: 1, statut: 'En cours', tjm: 600, date_fin_mission: '2026-12-31' }])),
    A.computeCollab(mk({ id: 2, cjm: 300 }), ctx([{ id: 'b', contact_consultant_id: 2, statut: 'En cours', tjm: 500, date_fin_mission: '2026-10-01' }])),
    A.computeCollab(mk({ id: 3, cjm: 350 }), ctx([], [{ contact_consultant_id: 3, annee: 2026, mois: 9, jours: 10 }])),
  ];
  const k = A.computeKpis(cs, 'cdi');
  assert.equal(k.effectif, 3); assert.equal(k.cjmMoyen, 350); assert.equal(k.tjmMoyen, 550);
  assert.equal(Math.round(k.margeMoyenne * 1000) / 1000, 0.367); assert.equal(k.dispo60, 1); assert.equal(k.intercoAnnee, 10);
});
test('prochainJourOuvre930 : vendredi → lundi, veille de férié → saute', () => {
  assert.equal(A.prochainJourOuvre930('2026-09-11', FERIES), '2026-09-14T09:30:00'); // ven → lun
  assert.equal(A.prochainJourOuvre930('2026-11-10', FERIES), '2026-11-12T09:30:00'); // 11/11 férié
  assert.equal(A.prochainJourOuvre930('2026-09-14', FERIES), '2026-09-15T09:30:00'); // jamais aujourd'hui
});
test('planAlertes : crée à ≤60 j, idempotent, clôt si prolongée', () => {
  const m = { id: 'm1', contact_consultant_id: 1, statut: 'En cours', tjm: 600, cjm: 400, date_fin_mission: '2026-10-30', client: 'EDF', responsable: 'Nicolas Serradeil' };
  const c = A.computeCollab(mk(), ctx([m]));
  const r1 = A.planAlertes([c], [], { todayISO: T, feries: FERIES, profilNom: 'Amel Benzai' });
  assert.equal(r1.aCreer.length, 1);
  const t = r1.aCreer[0];
  assert.match(t.titre, /^⏳ Fin de mission Laurie MARTINEAU — EDF le 30\/10 \(J-46\)/);
  assert.equal(t.mission_id, 'm1'); assert.equal(t.contact_id, 1); assert.equal(t.responsable, 'Nicolas Serradeil');
  assert.equal(t.due_date, '2026-09-15T09:30:00'); assert.equal(t.statut, 'en_cours'); assert.match(t.notes, /TJM 600 · CJM 400 · marge 33 %/);
  // idempotence : une tâche existe (même clôturée) → rien
  const r2 = A.planAlertes([c], [{ id: 'x', mission_id: 'm1', titre: '⏳ Fin de mission Laurie MARTINEAU — EDF le 30/10 (J-46)', statut: 'fait' }], { todayISO: T, feries: FERIES, profilNom: 'Amel' });
  assert.equal(r2.aCreer.length, 0); assert.equal(r2.aClore.length, 0);
  // prolongée > 60 j avec alerte ouverte → aClore
  const c2 = A.computeCollab(mk(), ctx([{ ...m, date_fin_mission: '2027-03-31' }]));
  const r3 = A.planAlertes([c2], [{ id: 'x', mission_id: 'm1', titre: '⏳ Fin de mission …', statut: 'en_cours' }], { todayISO: T, feries: FERIES, profilNom: 'Amel' });
  assert.equal(r3.aCreer.length, 0); assert.deepEqual(r3.aClore, [{ id: 'x', note: 'mission prolongée au 31/03/2027' }]);
  // sorti ou sans mission → rien
  assert.equal(A.planAlertes([A.computeCollab(mk({ date_sortie: '2026-01-01' }), ctx([m]))], [], { todayISO: T, feries: FERIES, profilNom: 'A' }).aCreer.length, 0);
});
test('arriveesSortiesParMois', () => {
  const cs = [mk({ id: 1, date_entree: '2026-02-10' }), mk({ id: 2, date_entree: '2026-02-23' }), mk({ id: 3, date_entree: '2025-06-01', date_sortie: '2026-06-30' }), mk({ id: 4, date_entree: '2026-11-02' })].map((c) => A.computeCollab(c, ctx()));
  const r = A.arriveesSortiesParMois(cs, 2026);
  assert.deepEqual(r.arrivees, [0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]);
  assert.deepEqual(r.sorties, [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
  assert.equal(r.cumul[0], 1); assert.equal(r.cumul[1], 3); assert.equal(r.cumul[5], 2); assert.equal(r.cumul[11], 3);
  assert.deepEqual(r.listeArrivees[1].map((k) => k.id), [1, 2]);
});
test('tranchesTjm / tranchesMarge', () => {
  const mission = (id, tjm) => ({ id: 'm' + id, contact_consultant_id: id, statut: 'En cours', tjm, date_fin_mission: '2026-12-31' });
  const cs = [[1, 450, 400], [2, 550, 300], [3, 650, 500], [4, 800, 400]].map(([id, tjm, cjm]) => A.computeCollab(mk({ id, cjm }), ctx([mission(id, tjm)])));
  const t = A.tranchesTjm(cs);
  assert.deepEqual(t.map((x) => [x.label, x.items.length]), [['< 500 €', 1], ['500-600 €', 1], ['600-700 €', 1], ['> 700 €', 1]]);
  const g = A.tranchesMarge(cs); // marges : 0.11, 0.45, 0.23, 0.5
  assert.deepEqual(g.map((x) => [x.label, x.items.length]), [['< 20 %', 1], ['20-30 %', 1], ['30-40 %', 0], ['> 40 %', 2]]);
  assert.equal(g[0].color, '#FF3D2E'); assert.equal(g[3].color, '#00C218');
});
test('tjmMargeParMois', () => {
  const ms = [{ tjm: 600, cjm: 400, jours_jan: 10, jours_fev: 0 }, { tjm: 800, cjm: 400, jours_jan: 5, jours_fev: 20 }];
  const r = A.tjmMargeParMois(ms, 2026);
  assert.equal(r.tjm[0], 700); assert.equal(r.tjm[1], 800); assert.equal(r.tjm[2], null);
  assert.equal(Math.round(r.marge[0] * 1000) / 1000, 0.417); assert.equal(r.marge[1], 0.5);
});
test('intercoStats (logique TDB)', () => {
  const jo = () => 20; // 20 j ouvrés / mois pour le test
  const intercos = [{ contact_consultant_id: 1, annee: 2026, mois: 1, jours: 10, cjm_snapshot: 400 }, { contact_consultant_id: 2, annee: 2026, mois: 2, jours: 4, cjm_snapshot: 300 }];
  const s = A.intercoStats(new Set([1, 2]), intercos, 2026, 2, jo); // mars courant (idx 2), non saisi → M-1 = fév
  assert.equal(s.tauxM[0], 25); assert.equal(s.tauxM[1], 10); assert.equal(s.joursYTD, 14); assert.equal(s.coutYTD, 5200);
  assert.equal(Math.round(s.tauxAnn * 100) / 100, 11.67); assert.equal(s.idxAff, 1); assert.equal(s.fallbackM1, true); assert.equal(s.nbCourant, 1);
  assert.deepEqual(s.parMois(0), [{ contact_consultant_id: 1, jours: 10, cout: 4000 }]);
});
```

- [ ] **Step 2: Lancer les tests → échec attendu**

Run: `node --test tests/agence-calc.test.mjs 2>&1 | tail -3`
Expected: erreur `Cannot find module '../agence-calc.js'`.

- [ ] **Step 3: Écrire `agence-calc.js`**

```js
// agence-calc.js — logique pure de l'onglet Agence (SPEC_agence_effectifs.md).
// Fichier JS classique (pas de JSX) : chargé par index.html AVANT le bloc Babel et testé avec `node --test`.
(function (root) {
  const MANAGER_TRIGRAMMES = {
    NSE: 'Nicolas Serradeil', ACD: 'Anne-Claire Decker', CSA: 'Camille Salinson', ABE: 'Amel Benzai',
    PSO: 'Pierre Solle', MJP: 'Majo Paquelier', LBL: 'Louis Blandin', CAJ: 'Cassandre Jacquemin',
    APL: 'Anthony Plancoulaine', WSA: 'Weronika Sawicki', FEL: 'Fabrice Elmoznino', HSI: 'Hervé Sinpaseuth',
    SLE: 'Stanislas Le Moy', JSE: 'Julian Sendra', COS: 'Constance Salem',
  };
  const CDI_STATUTS = ['Consultant CDI'];
  const ST_STATUTS = ['Freelance', 'Prestataire'];
  const CONSULTANT_STATUTS_AGENCE = CDI_STATUTS.concat(ST_STATUTS);
  const COL = { vert: '#00C218', orange: '#F97316', rouge: '#FF3D2E', gris: '#E4E4E6', midnight: '#1C1F35', blanc: '#FFFFFF', mute: '#A4A6AB' };

  const cjmFromSalaire = (s) => Math.round((Number(s) / 215) * 1.7 * 100) / 100;
  const d0 = (iso) => (iso || '').slice(0, 10);
  const joursEntre = (a, b) => Math.round((Date.parse(d0(b) + 'T00:00:00Z') - Date.parse(d0(a) + 'T00:00:00Z')) / 86400000);
  const fmtJJMM = (iso) => { const s = d0(iso); return s ? `${s.slice(8, 10)}/${s.slice(5, 7)}` : ''; };
  const fmtJJMMAAAA = (iso) => { const s = d0(iso); return s ? `${s.slice(8, 10)}/${s.slice(5, 7)}/${s.slice(0, 4)}` : ''; };
  const fmtJ = (n) => (n % 1 ? n.toFixed(1).replace('.', ',') : String(n));

  function computeCollab(c, ctx) {
    const { missions = [], intercos = [], partnerNomById = {}, partnerIdByContact = {}, todayISO, annee } = ctx;
    const mine = missions.filter((m) => m.contact_consultant_id === c.id);
    const enCours = mine.filter((m) => m.statut === 'En cours')
      .sort((a, b) => (d0(b.date_fin_mission) || '9999').localeCompare(d0(a.date_fin_mission) || '9999'));
    const aVenir = mine.filter((m) => m.statut === 'New' && d0(m.date_debut_mission) > todayISO)
      .sort((a, b) => d0(a.date_debut_mission).localeCompare(d0(b.date_debut_mission)));
    const missionEnCours = enCours[0] || aVenir[0] || null;
    const isCdi = CDI_STATUTS.includes(c.statut);
    const joursAvantDispo = enCours[0] && enCours[0].date_fin_mission ? joursEntre(todayISO, enCours[0].date_fin_mission) : null;
    const tjm = missionEnCours && missionEnCours.tjm != null ? Number(missionEnCours.tjm) : null;
    const cjm = c.cjm != null && c.cjm !== '' ? Number(c.cjm) : (missionEnCours && missionEnCours.cjm != null ? Number(missionEnCours.cjm) : null);
    const marge = tjm && cjm != null ? (tjm - cjm) / tjm : null;
    const intercoAnnee = intercos.filter((i) => i.contact_consultant_id === c.id && Number(i.annee) === annee)
      .reduce((s, i) => s + (parseFloat(i.jours) || 0), 0);
    let etat;
    if (c.statut_rh === 'arret_maladie' || c.statut_rh === 'conge') etat = c.statut_rh;
    else if (enCours[0]) etat = 'en_mission';
    else if (aVenir[0]) etat = 'demarre_bientot';
    else etat = isCdi ? 'intercontrat' : 'sans_mission';
    const sorti = !!(c.date_sortie && d0(c.date_sortie) <= todayISO);
    const pid = partnerIdByContact[c.id];
    const partnerNom = (pid && partnerNomById[pid]) || MANAGER_TRIGRAMMES[c.manager_trigramme] || c.manager_trigramme || '';
    const typeLabel = isCdi ? 'CDI' : (c.type_presta === 'sous_traitant' || (!c.type_presta && c.statut === 'Prestataire') ? 'Sous-traitant' : 'Freelance');
    return Object.assign({}, c, { missionEnCours, joursAvantDispo, tjm, cjm, marge, intercoAnnee, etat, sorti, partnerNom, typeLabel, isCdi });
  }

  function etatDispo(k) {
    switch (k.etat) {
      case 'arret_maladie': return { label: `Arrêt maladie${k.statut_rh_depuis ? ' · depuis le ' + fmtJJMM(k.statut_rh_depuis) : ''}`, bg: COL.rouge, color: COL.blanc };
      case 'conge':         return { label: `Congé${k.statut_rh_depuis ? ' · depuis le ' + fmtJJMM(k.statut_rh_depuis) : ''}`, bg: COL.rouge, color: COL.blanc };
      case 'demarre_bientot': return { label: `démarre le ${fmtJJMM(k.missionEnCours.date_debut_mission)}`, bg: COL.vert, color: COL.midnight };
      case 'intercontrat':  return { label: `interco · ${fmtJ(k.intercoAnnee)} j cumulés ${new Date().getFullYear()}`, bg: COL.gris, color: COL.midnight };
      case 'sans_mission':  return { label: 'sans mission', bg: COL.gris, color: COL.midnight };
      case 'en_mission': {
        const j = k.joursAvantDispo;
        if (j == null) return { label: 'fin non définie', bg: COL.vert, color: COL.midnight };
        if (j < 0) return { label: `dépassée de ${-j} j`, bg: COL.rouge, color: COL.blanc };
        if (j <= 30) return { label: `J-${j}`, bg: COL.rouge, color: COL.blanc };
        if (j <= 60) return { label: `J-${j}`, bg: COL.orange, color: COL.blanc };
        return { label: `J-${j}`, bg: COL.vert, color: COL.midnight };
      }
      default: return { label: '', bg: COL.gris, color: COL.midnight };
    }
  }
  // Note : le libellé interco utilise l'année courante réelle ; computeCollab reçoit `annee` pour le cumul.
  // Pour les tests on aligne : on remplace new Date().getFullYear() par k._annee si présent.
  const _etatDispo = etatDispo;
  function etatDispoAnnee(k) { if (k.etat === 'intercontrat') return { label: `interco · ${fmtJ(k.intercoAnnee)} j cumulés ${k._annee || new Date().getFullYear()}`, bg: COL.gris, color: COL.midnight }; return _etatDispo(k); }

  function margeStyle(m) {
    if (m == null || isNaN(m)) return { color: COL.mute };
    if (m < 0.20) return { color: COL.rouge };
    if (m < 0.30) return { color: COL.orange };
    return { color: COL.midnight };
  }

  function computeKpis(collabs, mode) {
    const act = collabs.filter((k) => !k.sorti);
    const avg = (arr) => (arr.length ? Math.round((arr.reduce((s, v) => s + v, 0) / arr.length) * 100) / 100 : null);
    const cjms = act.map((k) => k.cjm).filter((v) => v != null && !isNaN(v));
    const tjms = act.map((k) => k.tjm).filter((v) => v != null && !isNaN(v));
    const marges = act.map((k) => k.marge).filter((v) => v != null && !isNaN(v));
    const fins60 = act.filter((k) => k.etat === 'en_mission' && k.joursAvantDispo != null && k.joursAvantDispo <= 60).length;
    return {
      effectif: act.length, cjmMoyen: avg(cjms), tjmMoyen: avg(tjms), margeMoyenne: avg(marges),
      dispo60: fins60, fins60,
      intercoAnnee: mode === 'cdi' ? act.reduce((s, k) => s + (k.intercoAnnee || 0), 0) : 0,
    };
  }

  function prochainJourOuvre930(todayISO, feries) {
    const f = feries || new Set();
    let d = new Date(d0(todayISO) + 'T00:00:00Z');
    do { d.setUTCDate(d.getUTCDate() + 1); } while (d.getUTCDay() === 0 || d.getUTCDay() === 6 || f.has(d.toISOString().slice(0, 10)));
    return d.toISOString().slice(0, 10) + 'T09:30:00';
  }

  const ALERTE_PREFIX = '⏳ Fin de mission';
  function planAlertes(collabs, taches, ctx) {
    const { todayISO, feries, profilNom } = ctx;
    const aCreer = [], aClore = [];
    const due = prochainJourOuvre930(todayISO, feries);
    collabs.forEach((k) => {
      if (k.sorti || k.etat !== 'en_mission' || !k.missionEnCours) return;
      const m = k.missionEnCours;
      const existing = taches.filter((t) => t.mission_id === m.id && (t.titre || '').startsWith(ALERTE_PREFIX));
      const j = k.joursAvantDispo;
      if (j != null && j >= 0 && j <= 60) {
        if (existing.length) return;
        const client = m.client || '';
        const margePct = k.marge != null ? Math.round(k.marge * 100) : null;
        aCreer.push({
          id: `al_${m.id}_${Date.now()}`,
          titre: `${ALERTE_PREFIX} ${k.prenom || ''} ${k.nom || ''} — ${client} le ${fmtJJMM(m.date_fin_mission)} (J-${j})`.replace(/\s+—\s+le/, ' le'),
          statut: 'en_cours', due_date: due, contact_id: k.id, mission_id: m.id, besoin_id: null,
          responsable: m.responsable || k.responsable || profilNom,
          notes: `Alerte auto onglet Agence (${k.isCdi ? 'préparer la suite' : 'renouvellement ou fin de contrat'}). TJM ${k.tjm ?? '?'} · CJM ${k.cjm ?? '?'} · marge ${margePct != null ? margePct + ' %' : '?'}`,
        });
      } else if (j != null && j > 60) {
        existing.filter((t) => t.statut === 'a_faire' || t.statut === 'en_cours')
          .forEach((t) => aClore.push({ id: t.id, note: `mission prolongée au ${fmtJJMMAAAA(m.date_fin_mission)}` }));
      }
    });
    return { aCreer, aClore };
  }

  // ── Détails des dalles KPI (spec §5.1) ─────────────────────────────────────
  function arriveesSortiesParMois(collabs, annee) {
    const arrivees = Array(12).fill(0), sorties = Array(12).fill(0), listeArrivees = Array.from({ length: 12 }, () => []);
    collabs.forEach((k) => {
      const e = d0(k.date_entree), s = d0(k.date_sortie);
      if (e && +e.slice(0, 4) === annee) { const i = +e.slice(5, 7) - 1; arrivees[i]++; listeArrivees[i].push(k); }
      if (s && +s.slice(0, 4) === annee) sorties[+s.slice(5, 7) - 1]++;
    });
    // effectif en fin de mois : présents entrés avant la fin du mois et non sortis avant la fin du mois
    const cumul = Array.from({ length: 12 }, (_, i) => {
      const fin = `${annee}-${String(i + 1).padStart(2, '0')}-31`;
      return collabs.filter((k) => (!k.date_entree || d0(k.date_entree) <= fin) && (!k.date_sortie || d0(k.date_sortie) > fin)).length;
    });
    listeArrivees.forEach((l) => l.sort((a, b) => d0(a.date_entree).localeCompare(d0(b.date_entree))));
    return { arrivees, sorties, cumul, listeArrivees };
  }
  function tranchesTjm(collabs) {
    const T = [{ label: '< 500 €', min: -Infinity, max: 500 }, { label: '500-600 €', min: 500, max: 600 }, { label: '600-700 €', min: 600, max: 700 }, { label: '> 700 €', min: 700, max: Infinity }];
    return T.map((t) => Object.assign({}, t, { items: collabs.filter((k) => k.tjm != null && k.tjm >= t.min && k.tjm < t.max) }));
  }
  function tranchesMarge(collabs) {
    const T = [{ label: '< 20 %', min: -Infinity, max: 0.20, color: COL.rouge }, { label: '20-30 %', min: 0.20, max: 0.30, color: COL.orange }, { label: '30-40 %', min: 0.30, max: 0.40, color: COL.midnight }, { label: '> 40 %', min: 0.40, max: Infinity, color: COL.vert }];
    return T.map((t) => Object.assign({}, t, { items: collabs.filter((k) => k.marge != null && k.marge >= t.min && k.marge < t.max).sort((a, b) => a.marge - b.marge) }));
  }
  const MOIS_KEYS_AC = ['jan', 'fev', 'mar', 'avr', 'mai', 'jun', 'jul', 'aou', 'sep', 'oct', 'nov', 'dec'];
  function tjmMargeParMois(missions, annee) {
    const tjm = [], marge = [];
    MOIS_KEYS_AC.forEach((k) => {
      const act = missions.filter((m) => (parseFloat(m['jours_' + k]) || 0) > 0 && parseFloat(m.tjm) > 0);
      if (!act.length) { tjm.push(null); marge.push(null); return; }
      const t = act.reduce((s, m) => s + parseFloat(m.tjm), 0) / act.length;
      const mg = act.reduce((s, m) => s + (parseFloat(m.tjm) - (parseFloat(m.cjm) || 0)) / parseFloat(m.tjm), 0) / act.length;
      tjm.push(Math.round(t * 100) / 100); marge.push(Math.round(mg * 10000) / 10000);
    });
    return { tjm, marge };
  }
  function intercoStats(cdiIds, intercos, annee, curMonthIdx, joursOuvresMoisFn) {
    const rows = intercos.filter((r) => Number(r.annee) === annee && cdiIds.has(r.contact_consultant_id));
    const j = (i) => rows.filter((r) => r.mois === i + 1).reduce((s, r) => s + (parseFloat(r.jours) || 0), 0);
    const c = (i) => rows.filter((r) => r.mois === i + 1).reduce((s, r) => s + (parseFloat(r.jours) || 0) * (parseFloat(r.cjm_snapshot) || 0), 0);
    const n = cdiIds.size;
    const tauxM = Array.from({ length: 12 }, (_, i) => { const d = n * joursOuvresMoisFn(annee, i); return d > 0 ? (j(i) / d) * 100 : 0; });
    const joursYTD = Array.from({ length: curMonthIdx + 1 }, (_, i) => j(i)).reduce((a, b) => a + b, 0);
    const coutYTD = Array.from({ length: curMonthIdx + 1 }, (_, i) => c(i)).reduce((a, b) => a + b, 0);
    const denom = n * Array.from({ length: curMonthIdx + 1 }, (_, i) => joursOuvresMoisFn(annee, i)).reduce((a, b) => a + b, 0);
    const tauxAnn = denom > 0 ? (joursYTD / denom) * 100 : 0;
    const courantRempli = rows.some((r) => r.mois === curMonthIdx + 1 && (parseFloat(r.jours) || 0) > 0);
    const idxAff = (courantRempli || curMonthIdx === 0) ? curMonthIdx : curMonthIdx - 1;
    const parMois = (i) => rows.filter((r) => r.mois === i + 1 && (parseFloat(r.jours) || 0) > 0)
      .map((r) => ({ contact_consultant_id: r.contact_consultant_id, jours: parseFloat(r.jours) || 0, cout: (parseFloat(r.jours) || 0) * (parseFloat(r.cjm_snapshot) || 0) }))
      .sort((a, b) => b.jours - a.jours);
    return { tauxM, tauxAnn, joursYTD, coutYTD, idxAff, fallbackM1: !courantRempli && idxAff !== curMonthIdx, nbCourant: parMois(idxAff).length, parMois };
  }

  const AgenceCalc = { MANAGER_TRIGRAMMES, CDI_STATUTS, ST_STATUTS, CONSULTANT_STATUTS_AGENCE, ALERTE_PREFIX, COL,
    cjmFromSalaire, joursEntre, fmtJJMM, fmtJJMMAAAA, fmtJ, computeCollab, etatDispo: etatDispoAnnee, margeStyle, computeKpis, prochainJourOuvre930, planAlertes,
    arriveesSortiesParMois, tranchesTjm, tranchesMarge, tjmMargeParMois, intercoStats };
  root.AgenceCalc = AgenceCalc;
  if (typeof module !== 'undefined' && module.exports) module.exports = AgenceCalc;
})(typeof globalThis !== 'undefined' ? globalThis : window);
```

Puis, pour que le test « interco … cumulés 2026 » soit déterministe quelle que soit l'année d'exécution, `computeCollab` doit poser `_annee: annee` sur l'objet retourné : dans le `Object.assign` final, ajouter `_annee: annee`.

- [ ] **Step 4: Lancer les tests → tout vert**

Run: `node --test tests/agence-calc.test.mjs 2>&1 | tail -6`
Expected: `# pass 20` / `# fail 0`. Si le test « en mission > 60 j » échoue sur la marge : `(490-411.16)/490 = 0.1609` → arrondi `0.161`, OK ; sinon corriger l'arrondi dans le test, pas dans le code.

- [ ] **Step 5: Commit**

```bash
git add agence-calc.js tests/agence-calc.test.mjs
git commit -m "feat(agence): logique pure agence-calc.js + tests node

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Câblage dans `index.html` (chargement, données, périmètre, onglet)

**Files:**
- Modify: `index.html:38` (après supabase-js : `<script src="agence-calc.js">`)
- Modify: `index.html:8050` (select contacts), `index.html:8060` (select partner_consultants → ajouter `partner_id`), `index.html:8102` (`setData`)
- Modify: `index.html:8183-8186` (partnerSet + partner_lead), `index.html:8239` (TAB_COLORS), `index.html:8243-8251` (TABS), `index.html:8144-8150` (raccourcis), `index.html:8348` (modal raccourcis), `index.html:8335` (rendu onglet)
- Modify: `service-worker.js:2` (`upgrade-crm-v4`)

**Interfaces:**
- Consumes: `window.AgenceCalc` (Task 2).
- Produces: prop set de `<TabAgence>` = `{contacts, missions, missionPeriods, intercos, taches, comptes, histMissions, besoins, partnerConsultants, allProfiles, profile, isPartner, onRefresh, onNavToMission, onNavToContact, prefs}` ; `data.intercos` (toutes les imputations de l'année courante) ; `partnerSet` élargi.

- [ ] **Step 1: Charger `agence-calc.js` et bumper le service worker**

Ligne 38, ajouter juste après la balise supabase-js :
```html
<script src="agence-calc.js"></script>
```
`service-worker.js:2` : `const CACHE_NAME = 'upgrade-crm-v4';`

- [ ] **Step 2: Étendre `fetchAll`**

Ligne 8050, remplacer la liste des colonnes contacts par :
```js
sb.from('contacts').select('id,statut,prenom,nom,ville,role,telephone,email,linkedin,besoins,responsable,date_dernier,commentaires,ats,updated_at,agence,created_at,date_dernier_suivi_client,ne_pas_recontacter,ne_pas_recontacter_note,ne_pas_recontacter_date,cjm,employeur,date_entree,date_sortie,salaire_annuel,cjm_manuel,statut_rh,statut_rh_depuis,type_presta,manager_trigramme').order('id').limit(L),
```
Ligne 8060 : `sb.from('partner_consultants').select('partner_id,contact_consultant_id').limit(10000),`
Ajouter une 12e requête après (ligne 8060) et sa destructuration ligne 8048 (`{data:intercos,error:e12},`) :
```js
sb.from('interco_imputations').select('contact_consultant_id,annee,mois,jours,cjm_snapshot').eq('annee',new Date().getFullYear()).limit(5000),
```
Ligne 8102, dans `setData({...})` ajouter `intercos:intercos||[]`. Ligne 8171, ajouter `intercos` à la destructuration.

- [ ] **Step 3: Périmètre partner + partner_lead**

Remplacer les lignes 8183-8184 par :
```js
  const isPartner = activeProfile.role==='partner';
  // partner_lead (db/20) : Cassandre voit l'union de tous les partners ; sinon un partner ne voit que SES lignes
  const partnerSet = new Set((partnerConsultants||[]).filter(x=>activeProfile.partner_lead||x.partner_id===activeProfile.id).map(x=>x.contact_consultant_id));
```
⚠️ Avant ce changement, `partnerSet` prenait TOUTES les lignes de la table (la RLS de `partner_consultants` ne renvoyait au partner que les siennes). Avec `partner_id` dans le select, le filtre app devient explicite ; pour un admin en « Voir comme » un partner, `activeProfile.id` = id du profil simulé, donc le rendu est fidèle.

- [ ] **Step 4: Onglet, couleur, raccourcis**

Ligne 8239 : ajouter `agence:'#0BA600'` n'est pas possible (déjà `taches`). Utiliser **`agence:'#00C218'`**. Nouvelle ligne :
```js
  const TAB_COLORS={taches:'#0BA600',agence:'#00C218',prospects:'#5090FE',prospection:'#FF3D2E',besoins:'#FFEA2F',pipe:'#823DE8',tdb:'#FF78FD',historique:'#565861',settings:'#A4A6AB'};
```
Ligne 8322, la couleur de texte des onglets clairs : remplacer `c==='#FFEA2F'||c==='#FF78FD'` par `c==='#FFEA2F'||c==='#FF78FD'||c==='#00C218'` (texte noir sur jade).

Dans `TABS` (8243-8251), insérer entre `taches` et `prospects` :
```js
    {id:'agence',     label:<><Icon d={ICONS.work} size={14}/> Agence ({effectifActif})</>},
```
et étendre la liste blanche partner : `['taches','agence','prospects','tdb','historique']`.
Juste avant `const TABS=[`, calculer :
```js
  const effectifActif = vContacts.filter(c=>AgenceCalc.CONSULTANT_STATUTS_AGENCE.includes(c.statut)&&!(c.date_sortie&&c.date_sortie<=TODAY)).length;
```
Raccourcis 8144-8150 : renuméroter (1 taches, 2 agence, 3 prospects, 4 prospection, 5 besoins, 6 pipe, 7 tdb, 8 historique) :
```js
      if(e.key==='1'){e.preventDefault();setTab('taches');}
      if(e.key==='2'){e.preventDefault();setTab('agence');}
      if(e.key==='3'){e.preventDefault();setTab('prospects');}
      if(e.key==='4'){e.preventDefault();setTab('prospection');}
      if(e.key==='5'){e.preventDefault();setTab('besoins');}
      if(e.key==='6'){e.preventDefault();setTab('pipe');}
      if(e.key==='7'){e.preventDefault();setTab('tdb');}
      if(e.key==='8'){e.preventDefault();setTab('historique');}
```
Ligne 8348 : `['1–7',...]` → `['1–8','Changer d\'onglet']`.

- [ ] **Step 5: Rendu de l'onglet (stub)**

Après la ligne 8335 (`tab==='prospects'`), ajouter :
```jsx
        {tab==='agence'   &&<TabAgence contacts={vContacts} missions={isPartner?vMissions:missions} missionPeriods={missionPeriods} intercos={intercos} taches={vTaches} comptes={vComptes} histMissions={vHistMiss} besoins={vBesoins} partnerConsultants={partnerConsultants} allProfiles={allProfiles} profile={activeProfile} isPartner={isPartner} onRefresh={fetchAll} onNavToMission={navToMission} onNavToContact={navToContact} prefs={prefs}/>}
```
Note : `missions` (toutes) et non `vMissions` pour un commercial, car un commercial voit la France entière dans cet onglet (spec §4) alors que `vMissions` est scopé agence.
Puis, juste avant `function TabProspects(` (ligne 2772), ajouter le stub :
```jsx
// ═══ Onglet Agence (SPEC_agence_effectifs.md) ═══
function TabAgence(props){ return <div className="tab-content text-sm text-slate italic">Onglet Agence — en construction ({props.contacts.length} contacts visibles)</div>; }
```

- [ ] **Step 6: Vérifier compilation + local**

Run: `node tests/check-babel.mjs && (python3 -m http.server 8080 >/dev/null 2>&1 &) && sleep 1 && curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/agence-calc.js`
Expected: `OK babel` puis `200`. Ouvrir `http://localhost:8080/index.html` : onglet **Agence (N)** en 2e position, jade, touche `2` l'active, stub visible. Si erreur 400 Supabase « column … does not exist » : la migration Task 1 n'est pas appliquée → stop, relancer Nicolas.

- [ ] **Step 7: Commit**

```bash
git add index.html service-worker.js
git commit -m "feat(agence): câblage onglet (données, périmètre partner_lead, nav)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3b: Extraire `KpiCards` du TDB et en retirer la dalle Intercontrat

**Files:**
- Modify: `index.html:5823-5825` (état + chargement `intercoRows`), `:5827` (défaut `activeChart`), `:5874-5906` (bloc calcul interco), `:5923-5931` (`KPI_CARDS`), `:5954-5969` (rendu cartes), `:5975`, `:5978`, `:5981-6002` (chart + hint + liste interco)

**Interfaces:**
- Produces: composant global `KpiCards({cards, active, onSelect})` où `cards = [{id, color, value, label, sub, badge?, badgeColor?}]` — rendu identique aux cartes actuelles du TDB (liseré gauche, active = midnight + ombre `4px 4px 0 color`).
- `ChartInter` (l.793) reste global, inchangé, réutilisé par l'onglet Agence.

- [ ] **Step 1: Extraire le composant carte**

Juste avant `function TabTDB(` (l.5814), ajouter :
```jsx
// Cartes KPI cliquables « dalle » — partagées TDB (Missions) et Agence. cards: [{id,color,value,label,sub,badge?,badgeColor?}]
function KpiCards({ cards, active, onSelect }) {
  return <div style={{display:'grid',gridTemplateColumns:'repeat(auto-fit,minmax(150px,1fr))',gap:12}}>
    {cards.map(c=>{ const on=active===c.id; return (
      <div key={c.id} className="kpi-hover" data-active={on?'true':undefined} onClick={()=>onSelect(c.id)}
        onMouseEnter={e=>{if(!on)e.currentTarget.style.boxShadow='0 4px 12px '+c.color+'40';}}
        onMouseLeave={e=>{if(!on)e.currentTarget.style.boxShadow='none';}}
        style={{cursor:'pointer',position:'relative',background:on?'#1C1F35':'#fff',borderTop:on?'0':'2px solid #E4E4E6',borderRight:on?'0':'2px solid #E4E4E6',borderBottom:on?'0':'2px solid #E4E4E6',borderLeft:on?'0':`5px solid ${c.color}`,padding:'16px 14px',borderRadius:0,boxShadow:on?`4px 4px 0 ${c.color}`:'none',transform:on?'translate(-2px,-2px)':'none'}}>
        <div style={{fontSize:28,fontWeight:900,color:on?'#fff':'#1C1F35',fontFamily:'Outfit,sans-serif',lineHeight:1}}>{c.value}</div>
        <div style={{fontSize:11,fontWeight:700,textTransform:'uppercase',letterSpacing:'0.05em',color:on?c.color:'#999',marginTop:4}}>{c.label}</div>
        <div style={{fontSize:11,color:on?'#777':'#ccc',marginTop:2,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}>{c.sub}</div>
        {c.badge&&<div style={{fontSize:10,fontWeight:800,color:c.badgeColor,marginTop:4,textTransform:'uppercase'}}>{c.badge}</div>}
      </div>); })}
  </div>;
}
```
Remplacer le bloc 5954-5969 (`<div style={{display:'grid'…}}>{KPI_CARDS.map(…)}</div>`) par `<KpiCards cards={KPI_CARDS} active={activeChart} onSelect={setActiveChart}/>`.

- [ ] **Step 2: Retirer l'intercontrat du TDB**

- Supprimer l.5823 (`intercoRows`), l.5824 (`interMoisSel`), l.5825 (le `useEffect` qui charge `interco_imputations`).
- l.5827 : `useState(prefs?.tdb_default_chart==='inter'?'ca':(prefs?.tdb_default_chart||'ca'))`.
- Supprimer le bloc de calcul interco l.5874-5906 (du commentaire `// Intercontrat mensuel` jusqu'à `const coutMoisAff=…` inclus). **Garder** `const currentYear`, `margeMensuel` et `missionFlow`.
- Dans `KPI_CARDS` supprimer l'entrée `{id:'inter',…}` (l.5925-5928).
- Supprimer l.5975 (`activeChart==='inter'&&<ChartInter…`), simplifier l.5978 en `Cliquer sur une dalle pour changer la vue`, supprimer le bloc l.5981-6002 (liste interco).
- Vérifier avec `grep -n "interCY\|listeInterAff\|idxTable\|nbInterCourant\|tauxInterM" index.html` → **0 résultat** dans `TabTDB` (les seuls restants seront ceux ajoutés par la Task 4 dans `TabAgence`).
- Chercher dans `TabSettings` (préférences) l'option `tdb_default_chart` : si un `<option value="inter">` existe, le retirer.

- [ ] **Step 3: Compiler + recette**

Run: `node tests/check-babel.mjs`
Expected: `OK babel`. Navigateur, onglet Missions : 3 dalles (EN MISSION · CA YTD · MARGE YTD), aucun graphe interco, aucune erreur console.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "refactor(tdb): KpiCards partagé, dalle intercontrat déplacée vers l'onglet Agence

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `TabAgence` — toggle, filtres, 4 dalles KPI + détails, tableaux

**Files:**
- Modify: `index.html` (remplacer le stub `TabAgence` de la Task 3, ajouter `AgenceKpis`, `DispoBadge`, `MargeCell`)

**Interfaces:**
- Consumes: props Task 3 ; `AgenceCalc.*` ; `KpiCards` (Task 3b), `ChartInter` (l.793), `joursOuvresMois`, `fmtK`, `MOIS_KEYS` ; `ColorBadge`, `StatutBadge`, `Icon`, `ICONS`, `norm`, `TODAY`.
- Produces: états internes `mode ('cdi'|'st')`, `selected` (Collab) → consommé par `CollabDetail` (Task 5) ; `showAdd` → `AddContactModal` avec `defaults` (Task 6) ; `filteredSorted` (Collab[]) → `exportEffectifs` (Task 7).

- [ ] **Step 1: Composants d'affichage**

Remplacer le stub par (au même endroit, avant `TabProspects`) :
```jsx
// ═══ Onglet Agence (SPEC_agence_effectifs.md) ═══
function DispoBadge({ k }) { const b=AgenceCalc.etatDispo(k); return <ColorBadge label={b.label} bg={b.bg} color={b.color}/>; }
function MargeCell({ m }) { if(m==null) return <span className="text-neutral-300">—</span>; return <span className="font-medium" style={AgenceCalc.margeStyle(m)}>{Math.round(m*100)} %</span>; }
const fmtEur0 = n => n==null?'—':Math.round(n).toLocaleString('fr-FR')+' €';
const fmtDateFR = iso => iso?AgenceCalc.fmtJJMMAAAA(iso):'—';
const MOIS_LBL_AG=['Jan','Fév','Mar','Avr','Mai','Juin','Juil','Août','Sep','Oct','Nov','Déc'];
// Barres mensuelles génériques (même rendu que ChartMissions : barres pleines, mois courant souligné). series: [{values:number[12], color, label}], line?: number[12]
function BarresMensuelles({ series, line, curMonth, selMonth, onMonthClick, fmt=v=>String(v) }) {
  const max=Math.max(1,...series.flatMap(s=>s.values),...(line||[]).filter(v=>v!=null));
  return <div>
    <div style={{display:'flex',gap:6,alignItems:'flex-end',height:140,position:'relative'}}>
      {MOIS_LBL_AG.map((m,i)=><div key={i} onClick={()=>onMonthClick&&onMonthClick(i)} title={series.map(s=>`${s.label} ${fmt(s.values[i])}`).join(' · ')} style={{flex:1,display:'flex',gap:2,alignItems:'flex-end',height:'100%',cursor:onMonthClick?'pointer':'default',outline:selMonth===i?'2px solid #1C1F35':'none',outlineOffset:2}}>
        {series.map(s=><div key={s.label} style={{flex:1,background:s.color,height:Math.max(2,(s.values[i]/max)*130),opacity:i>curMonth?0.35:1}}/>)}
        {line&&line[i]!=null&&<div style={{position:'absolute',bottom:(line[i]/max)*130,left:`${(i+0.5)*100/12}%`,width:6,height:6,marginLeft:-3,borderRadius:3,background:'#1C1F35'}}/>}
      </div>)}
    </div>
    <div style={{display:'flex',gap:6,marginTop:4}}>{MOIS_LBL_AG.map((m,i)=><div key={i} style={{flex:1,textAlign:'center',fontSize:10,fontWeight:i===curMonth?800:500,color:i===curMonth?'#1C1F35':'#9ca3af',background:i===curMonth?'#FFE500':'transparent'}}>{m}</div>)}</div>
    <div style={{display:'flex',gap:12,marginTop:8,fontSize:11,color:'#6b7280'}}>{series.map(s=><span key={s.label}><span style={{display:'inline-block',width:10,height:10,background:s.color,marginRight:4,verticalAlign:'middle'}}/>{s.label}</span>)}{line&&<span><span style={{display:'inline-block',width:8,height:8,borderRadius:4,background:'#1C1F35',marginRight:4,verticalAlign:'middle'}}/>effectif fin de mois</span>}</div>
  </div>;
}
// Liste « détail » sous une dalle : lignes cliquables → volet collaborateur
function ListeCollabs({ titre, items, cols, color='#1C1F35', onPick, vide='Rien à afficher.' }) {
  return <div style={{marginTop:12,background:'#fff',border:'2px solid #1C1F35',borderRadius:0}}>
    <div style={{display:'flex',alignItems:'center',gap:8,padding:'10px 16px',borderBottom:'2px solid #1C1F35',background:color,color:color==='#1C1F35'||color==='#FF3D2E'?'#fff':'#1C1F35'}}><span style={{fontSize:13,fontWeight:800,textTransform:'uppercase',letterSpacing:.5}}>{titre}</span><span style={{marginLeft:'auto',fontSize:12,fontWeight:700}}>{items.length}</span></div>
    {!items.length?<div style={{padding:16,fontSize:13,color:'#9ca3af'}}>{vide}</div>:items.map(k=><div key={k.id} onClick={()=>onPick(k)} className="hover:bg-azure-20 transition-colors" style={{display:'flex',alignItems:'center',gap:12,padding:'10px 16px',borderBottom:'1px solid #E4E4E6',cursor:'pointer',fontSize:13}}>
      <span style={{flex:1,fontWeight:700,color:'#1C1F35'}}>{k.prenom} {k.nom}</span>{cols.map((c,i)=><span key={i} style={{width:c.w||90,textAlign:c.right?'right':'left',color:c.color?c.color(k):'#6b7280',fontWeight:c.right?700:400}}>{c.v(k)}</span>)}<span style={{width:16,textAlign:'right',color:'#4A7FE5',fontWeight:800}}>→</span></div>)}
  </div>;
}
// Barres horizontales de répartition par tranche (TJM / marge) — clic = liste
function Tranches({ tranches, sel, onSel, fmtCount=n=>`${n}` }) {
  const max=Math.max(1,...tranches.map(t=>t.items.length));
  return <div className="space-y-2">{tranches.map((t,i)=><div key={t.label} onClick={()=>onSel(sel===i?null:i)} style={{display:'flex',alignItems:'center',gap:10,cursor:'pointer',opacity:sel==null||sel===i?1:0.4}}>
    <span style={{width:80,fontSize:12,fontWeight:700,color:t.color||'#1C1F35'}}>{t.label}</span>
    <div style={{flex:1,background:'#F4F4F5',height:22}}><div style={{width:`${(t.items.length/max)*100}%`,height:'100%',background:t.color||'#4A7FE5',outline:sel===i?'2px solid #1C1F35':'none'}}/></div>
    <span style={{width:40,textAlign:'right',fontSize:13,fontWeight:800}}>{fmtCount(t.items.length)}</span></div>)}</div>;
}
// Les 4 dalles + zone détail (spec §5.1). collabs = périmètre filtré ; cdiIds pour l'interco ; missions du périmètre pour TJM/marge par mois.
function AgenceKpiDalles({ collabs, mode, missions, intercos, contactMap, onPick, onNavToContact }) {
  const [active,setActive]=useState(null);
  const [moisSel,setMoisSel]=useState(null);
  const [trancheSel,setTrancheSel]=useState(null);
  useEffect(()=>{setMoisSel(null);setTrancheSel(null);},[active,mode]);
  const annee=new Date().getFullYear(), cur=new Date().getMonth();
  const act=collabs.filter(k=>!k.sorti);
  const k=AgenceCalc.computeKpis(act,mode);
  const enMission=act.filter(x=>x.etat==='en_mission').length, dispo=act.filter(x=>x.etat==='intercontrat'||x.etat==='sans_mission').length;
  const cdiIds=new Set(act.filter(x=>x.isCdi).map(x=>x.id));
  const ic=mode==='cdi'?AgenceCalc.intercoStats(cdiIds,intercos||[],annee,cur,joursOuvresMois):null;
  const nomsInter=ic?ic.parMois(ic.idxAff).map(r=>{const c=contactMap[r.contact_consultant_id];return c?(c.prenom||c.nom||'').split(' ')[0]:'';}).filter(Boolean):[];
  const cards=[
    {id:'effectif',color:'#00C218',value:k.effectif,label:mode==='cdi'?'CONSULTANTS':'SOUS-TRAITANTS',sub:`${enMission} en mission · ${dispo} ${mode==='cdi'?'en interco':'sans mission'}`},
    mode==='cdi'
      ?{id:'inter',color:ic.nbCourant>0?'#FFE500':'#ccc',value:ic.nbCourant,label:'INTERCONTRAT',sub:ic.nbCourant>0?`${ic.fallbackM1?`${MOIS_LBL_AG[ic.idxAff].toLowerCase()} (M-1) · `:''}${AgenceCalc.fmtJ(ic.joursYTD)}j YTD · ${fmtK(ic.coutYTD)} · ${nomsInter.join(', ')}`:'Aucun',badge:ic.tauxAnn>=8?'MALUS':ic.tauxAnn>=5?'Attention':null,badgeColor:ic.tauxAnn>=8?'#FF3D2E':'#92400e'}
      :{id:'inter',color:dispo>0?'#F97316':'#ccc',value:dispo,label:'SANS MISSION',sub:dispo>0?act.filter(x=>x.etat==='sans_mission').map(x=>x.prenom).join(', '):'Aucun'},
    {id:'tjm',color:'#4A7FE5',value:k.tjmMoyen==null?'—':Math.round(k.tjmMoyen)+' €',label:'TJM MOYEN',sub:`CJM moyen ${k.cjmMoyen==null?'—':Math.round(k.cjmMoyen)+' €'} · ${enMission} mission${enMission>1?'s':''}`},
    {id:'marge',color:'#FF66FF',value:k.margeMoyenne==null?'—':Math.round(k.margeMoyenne*100)+' %',label:'MARGE MOYENNE',sub:`seuil 30 % · ${act.filter(x=>x.marge!=null&&x.marge<0.30).length} sous le seuil`,badge:k.margeMoyenne!=null&&k.margeMoyenne<0.30?'Sous seuil':null,badgeColor:'#F97316'},
  ];
  const color=cards.find(c=>c.id===active)?.color||'#E4E4E6';
  const as=active==='effectif'?AgenceCalc.arriveesSortiesParMois(collabs,annee):null;
  const tm=active==='tjm'||active==='marge'?AgenceCalc.tjmMargeParMois(missions,annee):null;
  const tr=active==='tjm'?AgenceCalc.tranchesTjm(act):active==='marge'?AgenceCalc.tranchesMarge(act):null;
  const pick=k=>onPick(k);
  const eur=v=>v==null?'—':Math.round(v)+' €', pct=v=>v==null?'—':Math.round(v*100)+' %';
  return <div className="mb-4">
    <KpiCards cards={cards} active={active} onSelect={id=>setActive(a=>a===id?null:id)}/>
    {active&&<div style={{marginTop:12,background:'#fff',borderTop:'2px solid #E4E4E6',borderRight:'2px solid #E4E4E6',borderBottom:'2px solid #E4E4E6',borderLeft:`5px solid ${color}`,padding:'20px 24px 24px',borderRadius:0}}>
      {active==='effectif'&&<>
        <div className="text-sm font-bold text-midnight mb-3">Arrivées et sorties {annee} · effectif fin de mois</div>
        <BarresMensuelles series={[{values:as.arrivees,color:'#00C218',label:'arrivées'},{values:as.sorties,color:'#FF3D2E',label:'sorties'}]} line={as.cumul} curMonth={cur} selMonth={moisSel} onMonthClick={i=>setMoisSel(m=>m===i?null:i)}/>
        {moisSel!=null&&<ListeCollabs titre={`Arrivées ${MOIS_LBL_AG[moisSel]} ${annee}`} items={as.listeArrivees[moisSel]} color="#00C218" onPick={pick} cols={[{v:k=>k.agence||'—'},{v:k=>fmtDateFR(k.date_entree),w:100},{v:k=>(mode==='cdi'?k.partnerNom:k.responsable)||'—',w:150}]} vide="Aucune arrivée ce mois-là."/>}
      </>}
      {active==='inter'&&mode==='cdi'&&<>
        <ChartInter tauxM={ic.tauxM} tauxAnn={ic.tauxAnn} curMonth={cur} selMonth={moisSel!=null?moisSel:ic.idxAff} onMonthClick={i=>setMoisSel(m=>m===i?null:i)}/>
        {(()=>{const idx=moisSel!=null?moisSel:ic.idxAff; const rows=ic.parMois(idx).map(r=>Object.assign({},contactMap[r.contact_consultant_id]||{id:r.contact_consultant_id,nom:'(inconnu)'},{jours:r.jours,cout:r.cout})); const tj=rows.reduce((s,x)=>s+x.jours,0), tc=rows.reduce((s,x)=>s+x.cout,0);
          return <ListeCollabs titre={`En intercontrat — ${MOIS_LBL_AG[idx]} ${annee}${moisSel==null&&ic.fallbackM1?' (M-1)':''} · ${AgenceCalc.fmtJ(tj)}j · ${fmtK(tc)}`} items={rows} color="#FFE500" onPick={k=>onNavToContact&&onNavToContact(k.id)} cols={[{v:k=>k.agence||'—'},{v:k=>AgenceCalc.fmtJ(k.jours)+'j',w:48,right:true},{v:k=>fmtK(k.cout),w:64,right:true,color:()=>'#FF3D2E'}]} vide="Aucun consultant en intercontrat ce mois-ci."/>;})()}
      </>}
      {active==='inter'&&mode==='st'&&<ListeCollabs titre="Sous-traitants sans mission" items={act.filter(x=>x.etat==='sans_mission')} color="#F97316" onPick={pick} cols={[{v:k=>k.typeLabel},{v:k=>k.agence||'—'},{v:k=>k.responsable||'—',w:150}]} vide="Tous les sous-traitants sont en mission."/>}
      {active==='tjm'&&<>
        <div className="text-sm font-bold text-midnight mb-3">TJM moyen par mois {annee} (missions actives)</div>
        <BarresMensuelles series={[{values:tm.tjm.map(v=>v||0),color:'#4A7FE5',label:'TJM moyen'}]} curMonth={cur} fmt={eur}/>
        <div className="text-sm font-bold text-midnight mt-5 mb-2">Répartition par tranche de TJM</div>
        <Tranches tranches={tr} sel={trancheSel} onSel={setTrancheSel}/>
        {trancheSel!=null&&<ListeCollabs titre={`TJM ${tr[trancheSel].label}`} items={tr[trancheSel].items} color="#4A7FE5" onPick={pick} cols={[{v:k=>k.missionEnCours?.client||'—',w:140},{v:k=>eur(k.tjm),w:70,right:true},{v:k=>pct(k.marge),w:60,right:true,color:k=>AgenceCalc.margeStyle(k.marge).color}]}/>}
      </>}
      {active==='marge'&&<>
        <div className="text-sm font-bold text-midnight mb-3">Marge moyenne par mois {annee} (missions actives)</div>
        <BarresMensuelles series={[{values:tm.marge.map(v=>v==null?0:Math.round(v*100)),color:'#FF66FF',label:'marge %'}]} curMonth={cur} fmt={v=>v+' %'}/>
        <div className="text-sm font-bold text-midnight mt-5 mb-2">Répartition par tranche de marge</div>
        <Tranches tranches={tr} sel={trancheSel} onSel={setTrancheSel}/>
        <ListeCollabs titre={trancheSel!=null?`Marge ${tr[trancheSel].label}`:'Sous le seuil de 30 % — à renégocier / repositionner'} items={trancheSel!=null?tr[trancheSel].items:act.filter(x=>x.marge!=null&&x.marge<0.30).sort((a,b)=>a.marge-b.marge)} color={trancheSel!=null?(tr[trancheSel].color==='#1C1F35'?'#E4E4E6':tr[trancheSel].color):'#F97316'} onPick={pick} cols={[{v:k=>k.missionEnCours?.client||'—',w:140},{v:k=>eur(k.tjm),w:70,right:true},{v:k=>eur(k.cjm),w:70,right:true},{v:k=>pct(k.marge),w:60,right:true,color:k=>AgenceCalc.margeStyle(k.marge).color}]} vide="Personne sous 30 %. 👌"/>
      </>}
    </div>}
    <div style={{marginTop:6,fontSize:11,color:'#bbb',textAlign:'right',fontFamily:'Outfit,sans-serif'}}>{active?'Cliquer un mois / une tranche pour le détail · re-cliquer la dalle pour fermer':'Cliquer sur une dalle pour voir le détail'}</div>
  </div>;
}
```

- [ ] **Step 2: Le composant `TabAgence`**

```jsx
function TabAgence({ contacts, missions, missionPeriods, intercos, taches, comptes, histMissions, besoins, partnerConsultants, allProfiles, profile, isPartner, onRefresh, onNavToMission, onNavToContact, prefs }) {
  const [mode,setMode]=useState('cdi');
  const [search,setSearch]=useState('');
  const [filterAgence,setFilterAgence]=useState(isPartner?'':(profile.agence||''));
  const [filterResp,setFilterResp]=useState('');
  const [etats,setEtats]=useState(new Set());           // 'en_mission' | 'dispo60' | 'intercontrat' | 'rh'
  const [showSortis,setShowSortis]=useState(false);
  const [sortCol,setSortCol]=useState('dispo'); const [sortDir,setSortDir]=useState('asc');
  const [selected,setSelected]=useState(null);
  const [showAdd,setShowAdd]=useState(false);
  const [exporting,setExporting]=useState(false);
  const toggleSort=col=>{ if(sortCol===col) setSortDir(d=>d==='asc'?'desc':'asc'); else { setSortCol(col); setSortDir('asc'); } };
  const SortIcon=({col})=> sortCol!==col?<span className="ml-1 text-neutral-200">↕</span>:<span className="ml-1 text-azure-100">{sortDir==='asc'?'↑':'↓'}</span>;
  const toggleEtat=e=>setEtats(s=>{const n=new Set(s); n.has(e)?n.delete(e):n.add(e); return n;});

  const partnerNomById=useMemo(()=>Object.fromEntries((allProfiles||[]).map(p=>[p.id,p.nom])),[allProfiles]);
  const partnerIdByContact=useMemo(()=>{const o={};(partnerConsultants||[]).forEach(x=>{if(o[x.contact_consultant_id]==null)o[x.contact_consultant_id]=x.partner_id;});return o;},[partnerConsultants]);
  const collabs=useMemo(()=>{
    const statuts=mode==='cdi'?AgenceCalc.CDI_STATUTS:AgenceCalc.ST_STATUTS;
    const ctx={missions,intercos,partnerNomById,partnerIdByContact,todayISO:TODAY,annee:new Date().getFullYear()};
    return contacts.filter(c=>statuts.includes(c.statut)).map(c=>AgenceCalc.computeCollab(c,ctx));
  },[contacts,missions,intercos,partnerNomById,partnerIdByContact,mode]);
  const agences=useMemo(()=>[...new Set(collabs.map(k=>k.agence).filter(Boolean))].sort(),[collabs]);
  const responsables=useMemo(()=>[...new Set(collabs.map(k=>mode==='cdi'?k.partnerNom:k.responsable).filter(Boolean))].sort(),[collabs,mode]);

  const filteredSorted=useMemo(()=>{
    const q=norm(search);
    const rows=collabs.filter(k=>{
      if(!showSortis&&k.sorti) return false;
      if(filterAgence&&k.agence!==filterAgence) return false;
      if(filterResp&&(mode==='cdi'?k.partnerNom:k.responsable)!==filterResp) return false;
      if(etats.size){
        const isDispo60=k.etat==='en_mission'&&k.joursAvantDispo!=null&&k.joursAvantDispo<=60;
        const isRh=k.etat==='arret_maladie'||k.etat==='conge';
        const ok=(etats.has('en_mission')&&k.etat==='en_mission')||(etats.has('dispo60')&&isDispo60)||(etats.has('intercontrat')&&(k.etat==='intercontrat'||k.etat==='sans_mission'))||(etats.has('rh')&&isRh);
        if(!ok) return false;
      }
      if(q&&![k.prenom,k.nom,k.agence,k.partnerNom,k.responsable,k.missionEnCours&&k.missionEnCours.client].some(v=>norm(v||'').includes(q))) return false;
      return true;
    });
    const key=k=>{
      switch(sortCol){
        case 'nom': return (k.nom||'').toLowerCase()+' '+(k.prenom||'').toLowerCase();
        case 'agence': return k.agence||'';
        case 'resp': return (mode==='cdi'?k.partnerNom:k.responsable)||'';
        case 'entree': return k.date_entree||'0000';
        case 'salaire': return k.salaire_annuel==null?-1:Number(k.salaire_annuel);
        case 'cjm': return k.cjm==null?-1:k.cjm;
        case 'tjm': return k.tjm==null?-1:k.tjm;
        case 'marge': return k.marge==null?-9:k.marge;
        case 'mission': return (k.missionEnCours&&k.missionEnCours.client||'').toLowerCase();
        case 'type': return k.typeLabel;
        case 'dispo': default: {
          // urgences en tête : RH (-2), dépassées/≤60 par jours, interco/sans mission (-1), en mission lointaine, fin non définie (9998), démarre bientôt (9999)
          if(k.etat==='arret_maladie'||k.etat==='conge') return -2;
          if(k.etat==='intercontrat'||k.etat==='sans_mission') return -1;
          if(k.etat==='demarre_bientot') return 9999;
          return k.joursAvantDispo==null?9998:k.joursAvantDispo;
        }
      }
    };
    rows.sort((a,b)=>{const va=key(a),vb=key(b); if(va<vb) return sortDir==='asc'?-1:1; if(va>vb) return sortDir==='asc'?1:-1; return 0;});
    return rows;
  },[collabs,search,filterAgence,filterResp,etats,showSortis,sortCol,sortDir,mode]);
  const PAGE_SIZE=(typeof window!=='undefined'&&window.innerWidth<768)?50:200;
  const [visibleCount,setVisibleCount]=useState(PAGE_SIZE);
  useEffect(()=>{setVisibleCount(PAGE_SIZE);},[search,filterAgence,filterResp,etats,showSortis,sortCol,sortDir,mode]);
  const visible=filteredSorted.slice(0,visibleCount);
  const thCls="px-4 py-3 text-left font-medium cursor-pointer select-none hover:text-azure-100 whitespace-nowrap";
  const chip=(id,label)=><button key={id} onClick={()=>toggleEtat(id)} style={{fontSize:11,fontWeight:700,padding:'4px 12px',border:etats.has(id)?'0':'2px solid #E4E4E6',background:etats.has(id)?'#1C1F35':'#fff',color:etats.has(id)?'#fff':'#1C1F35',cursor:'pointer',borderRadius:0,textTransform:'uppercase',boxShadow:etats.has(id)?'3px 3px 0 #FFE500':'none',transition:'all 120ms'}}>{label}</button>;
  const nbCdi=contacts.filter(c=>AgenceCalc.CDI_STATUTS.includes(c.statut)&&!(c.date_sortie&&c.date_sortie<=TODAY)).length;
  const nbSt=contacts.filter(c=>AgenceCalc.ST_STATUTS.includes(c.statut)&&!(c.date_sortie&&c.date_sortie<=TODAY)).length;
  const missionLabel=k=>k.missionEnCours?<><div className="font-medium text-midnight">{k.missionEnCours.client||'—'}</div>{k.missionEnCours.date_fin_mission&&<div className="text-xs text-neutral-300">fin {AgenceCalc.fmtJJMM(k.missionEnCours.date_fin_mission)}</div>}</>:<span className="text-neutral-300">—</span>;

  return (
    <div className="tab-content">
      <div className="flex items-center justify-between mb-3 gap-2 flex-wrap">
        <div className="flex border rounded-lg overflow-hidden text-sm">
          <button onClick={()=>setMode('cdi')} className={`px-3 py-2 font-medium ${mode==='cdi'?'bg-midnight text-white':'bg-white text-slate hover:bg-neutral-50'}`}>CDI ({nbCdi})</button>
          <button onClick={()=>setMode('st')} className={`px-3 py-2 font-medium border-l ${mode==='st'?'bg-midnight text-white':'bg-white text-slate hover:bg-neutral-50'}`}>Sous-traitants ({nbSt})</button>
        </div>
        <div className="flex gap-2">
          <button onClick={()=>exportEffectifs(filteredSorted,mode,filterAgence,setExporting)} disabled={exporting||!filteredSorted.length} className="px-3 py-2 text-sm font-medium border-2 border-neutral-200 text-carbon hover:border-midnight disabled:opacity-50 transition-colors">{exporting?'…':'Export Excel'}</button>
          {!isPartner&&<button onClick={()=>setShowAdd(true)} className="px-4 py-2 bg-midnight text-white text-sm font-medium hover:bg-carbon btn-brutal">+ Nouveau collaborateur</button>}
        </div>
      </div>
      <div className="flex gap-2 sm:gap-3 mb-3 flex-wrap items-center">
        <input type="text" placeholder="Rechercher (nom, client, agence…)" value={search} onChange={e=>setSearch(e.target.value)} className="flex-1 min-w-[140px] sm:min-w-64 px-3 sm:px-4 py-2 border rounded-lg text-sm focus:outline-none focus:border-midnight"/>
        {!isPartner&&<select value={filterAgence} onChange={e=>{setFilterAgence(e.target.value);setFilterResp('');}} className="px-2 sm:px-3 py-2 border rounded-lg text-sm focus:outline-none"><option value="">Toutes agences</option>{agences.map(a=><option key={a} value={a}>{a}</option>)}</select>}
        <select value={filterResp} onChange={e=>setFilterResp(e.target.value)} className="px-2 sm:px-3 py-2 border rounded-lg text-sm focus:outline-none hidden sm:block"><option value="">{mode==='cdi'?'Tous partners':'Tous commerciaux'}</option>{responsables.map(r=><option key={r} value={r}>{r}</option>)}</select>
        {chip('en_mission','En mission')}{chip('dispo60','Dispo ≤ 60 j')}{chip('intercontrat',mode==='cdi'?'Intercontrat':'Sans mission')}{chip('rh','Arrêt & congés')}
        <label className="text-xs text-slate flex items-center gap-1 cursor-pointer"><input type="checkbox" checked={showSortis} onChange={e=>setShowSortis(e.target.checked)}/> Sortis</label>
      </div>
      <AgenceKpiDalles collabs={filteredSorted} mode={mode} missions={missions.filter(m=>filteredSorted.some(k=>k.id===m.contact_consultant_id))} intercos={intercos} contactMap={Object.fromEntries(contacts.map(c=>[c.id,c]))} onPick={k=>setSelected(k)} onNavToContact={onNavToContact}/>
      <div className="text-xs text-neutral-300 mb-2">{filteredSorted.length} collaborateur{filteredSorted.length>1?'s':''}</div>
      {/* Cartes mobile */}
      <div className="md:hidden space-y-2">
        {visible.map(k=>(
          <div key={k.id} onClick={()=>setSelected(k)} data-detail tabIndex="0" className="bg-white border-2 border-neutral-200 hover:border-midnight p-3 cursor-pointer active:bg-azure-20 focus:outline-none focus:border-midnight transition-colors">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0"><div className="font-bold text-midnight text-sm">{k.prenom} {k.nom}</div><div className="text-xs text-slate mt-0.5">{k.agence} · {mode==='cdi'?k.partnerNom:k.responsable}</div></div>
              <DispoBadge k={k}/>
            </div>
            <div className="flex items-center gap-3 mt-2 text-xs text-slate">{k.missionEnCours&&<span>{k.missionEnCours.client}</span>}{k.tjm!=null&&<span>TJM {fmtEur0(k.tjm)}</span>}<MargeCell m={k.marge}/></div>
          </div>
        ))}
      </div>
      {/* Tableau desktop */}
      <div className="hidden md:block bg-white border-2 border-neutral-200 overflow-x-auto">
        <table className="w-full text-sm">
          <thead><tr className="bg-neutral-50 text-[11px] font-bold uppercase tracking-[0.1em] text-slate">
            <th className={thCls} onClick={()=>toggleSort('nom')}>Collaborateur<SortIcon col="nom"/></th>
            {mode==='st'&&<th className={thCls} onClick={()=>toggleSort('type')}>Type<SortIcon col="type"/></th>}
            <th className={thCls} onClick={()=>toggleSort('agence')}>Agence<SortIcon col="agence"/></th>
            <th className={thCls} onClick={()=>toggleSort('resp')}>{mode==='cdi'?'Partner':'Commercial'}<SortIcon col="resp"/></th>
            <th className={thCls+" hidden lg:table-cell"} onClick={()=>toggleSort('entree')}>Entrée<SortIcon col="entree"/></th>
            {mode==='cdi'&&<th className={thCls+" hidden xl:table-cell"} onClick={()=>toggleSort('salaire')}>Salaire<SortIcon col="salaire"/></th>}
            <th className={thCls} onClick={()=>toggleSort('cjm')}>CJM<SortIcon col="cjm"/></th>
            <th className={thCls} onClick={()=>toggleSort('mission')}>Mission<SortIcon col="mission"/></th>
            <th className={thCls} onClick={()=>toggleSort('tjm')}>TJM<SortIcon col="tjm"/></th>
            <th className={thCls} onClick={()=>toggleSort('marge')}>Marge<SortIcon col="marge"/></th>
            <th className={thCls} onClick={()=>toggleSort('dispo')}>{mode==='cdi'?'Dispo':'Fin mission'}<SortIcon col="dispo"/></th>
          </tr></thead>
          <tbody>{visible.map(k=>(
            <tr key={k.id} onClick={()=>setSelected(k)} data-detail tabIndex="0" className={`border-t border-neutral-50 hover:bg-lemon-20 focus:bg-azure-20 focus:outline-none cursor-pointer transition-colors${selected&&selected.id===k.id?' bg-azure-20':''}${k.sorti?' opacity-50':''}`}>
              <td className="px-4 py-3"><div className="font-medium text-midnight">{k.prenom} {k.nom}</div>{k.sorti&&<div className="text-xs text-coral-100">sorti le {fmtDateFR(k.date_sortie)}</div>}</td>
              {mode==='st'&&<td className="px-4 py-3"><ColorBadge label={k.typeLabel} bg={k.typeLabel==='Freelance'?'#FF66FF':'#F97316'} color={k.typeLabel==='Freelance'?'#1C1F35':'#FFFFFF'}/></td>}
              <td className="px-4 py-3 text-slate">{k.agence||'—'}</td>
              <td className="px-4 py-3 text-slate text-xs">{(mode==='cdi'?k.partnerNom:k.responsable)||'—'}</td>
              <td className="px-4 py-3 text-slate text-xs hidden lg:table-cell">{fmtDateFR(k.date_entree)}</td>
              {mode==='cdi'&&<td className="px-4 py-3 text-slate hidden xl:table-cell">{fmtEur0(k.salaire_annuel)}</td>}
              <td className="px-4 py-3 text-slate">{fmtEur0(k.cjm)}</td>
              <td className="px-4 py-3">{missionLabel(k)}</td>
              <td className="px-4 py-3 text-slate">{fmtEur0(k.tjm)}</td>
              <td className="px-4 py-3"><MargeCell m={k.marge}/></td>
              <td className="px-4 py-3"><DispoBadge k={k}/></td>
            </tr>
          ))}</tbody>
        </table>
        {!filteredSorted.length&&<div className="px-4 py-6 text-xs text-neutral-300 italic">{mode==='cdi'?'Aucun collaborateur sur ce périmètre':'Aucun sous-traitant sur ce périmètre'}</div>}
      </div>
      {filteredSorted.length>visibleCount&&<div className="mt-3 flex justify-center"><button onClick={()=>setVisibleCount(v=>v+PAGE_SIZE)} className="px-4 py-2 text-sm font-medium border-2 border-neutral-200 text-carbon hover:border-midnight transition-colors">Charger plus ({filteredSorted.length-visibleCount} restants)</button></div>}
      {selected&&<CollabDetail collab={filteredSorted.find(k=>k.id===selected.id)||selected} missions={missions} missionPeriods={missionPeriods} histMissions={histMissions} contacts={contacts} taches={taches} besoins={besoins} comptes={comptes} profile={profile} allProfiles={allProfiles} onClose={()=>setSelected(null)} onRefresh={()=>{onRefresh();}} onNavToContact={onNavToContact}/>}
      {showAdd&&<AddContactModal profile={profile} allProfiles={allProfiles} comptes={comptes||[]} defaults={{statut:mode==='cdi'?'Consultant CDI':'Freelance',agence:filterAgence||profile.agence||''}} onClose={()=>setShowAdd(false)} onSaved={()=>{setShowAdd(false);onRefresh();}}/>}
    </div>
  );
}
```
Pour que la compilation passe avant les Tasks 5-7, ajouter TEMPORAIREMENT juste au-dessus :
```jsx
function CollabDetail({ collab, onClose }){ return <SidePanel title={`${collab.prenom} ${collab.nom}`} onClose={onClose}><div className="text-sm text-slate italic">Volet en construction</div></SidePanel>; }
async function exportEffectifs(rows,mode,agence,setBusy){ toast('Export : en construction'); }
```
(`AddContactModal` ignore encore `defaults` : c'est la Task 6 qui l'ajoute.)

- [ ] **Step 3: Compiler + recette visuelle**

Run: `node tests/check-babel.mjs`
Expected: `OK babel`. Dans le navigateur : toggle CDI/ST ; 4 dalles (CONSULTANTS · INTERCONTRAT · TJM MOYEN · MARGE MOYENNE) recalculées au filtre agence ; clic CONSULTANTS → barres arrivées/sorties + point effectif, clic sur un mois → liste des arrivées ; clic INTERCONTRAT → le graphe `ChartInter` (identique à l'ancien TDB) + liste du mois, clic ligne → fiche contact ; clic TJM → barres mensuelles + tranches, clic tranche → liste ; clic MARGE → liste « sous 30 % » par défaut ; en onglet ST la 2e dalle devient SANS MISSION. Tri par défaut Dispo croissant (arrêts en haut, puis interco, puis J-… croissant), badges orange/rouge sur les fins proches, checkbox Sortis, « Charger plus » n'apparaît que > 200 lignes. Vérifier avec « Voir comme » Majo : filtre agence masqué, pas de bouton Nouveau, ses consultants seulement.

- [ ] **Step 4: Commit**

```bash
git add index.html
git commit -m "feat(agence): tableau effectifs CDI/ST, filtres, 4 dalles KPI avec détails

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Volet latéral `CollabDetail`

**Files:**
- Modify: `index.html` (remplacer le stub `CollabDetail`)

**Interfaces:**
- Consumes: `SidePanel`, `IntercoEditor({contact, profile})`, `MissionDetail({mission, histMissions, missionPeriods, contacts, taches, missions, besoins, comptes, profile, allProfiles, onClose, onRefresh, onNavToContact, ...})`, `ContactEditModal({contact, profile, allProfiles, comptes, onClose, onSaved})`, `Field`, `DispoBadge`, `MargeCell`, `fmtEur0`, `fmtDateFR`.
- Produces: rien de nouveau pour les autres tâches.

- [ ] **Step 1: Écrire le composant**

```jsx
function CollabDetail({ collab: k, missions, missionPeriods, histMissions, contacts, taches, besoins, comptes, profile, allProfiles, onClose, onRefresh, onNavToContact }) {
  const [sub,setSub]=useState('mission');
  const [edit,setEdit]=useState(false);
  const [openMission,setOpenMission]=useState(null);
  const m=k.missionEnCours;
  const periods=m?(missionPeriods||[]).filter(p=>p.mission_id===m.id):[];
  const tabBtn=id=>`px-3 py-1.5 text-xs font-bold uppercase tracking-wider border-b-2 ${sub===id?'border-midnight text-midnight':'border-transparent text-slate hover:text-carbon'}`;
  const Row=({l,v})=><div className="flex justify-between gap-3 text-sm py-1 border-b border-neutral-50"><span className="text-slate">{l}</span><span className="font-medium text-midnight text-right">{v}</span></div>;
  const canEdit=profile.role==='admin'||profile.role==='commercial'||profile.role==='partner';
  return <>
    <SidePanel title={`${k.prenom||''} ${k.nom||''}`} onClose={onClose}
      badge={<div className="flex gap-1 flex-wrap"><StatutBadge statut={k.statut}/>{k.agence&&<ColorBadge label={k.agence} bg="#E4E4E6" color="#1C1F35"/>}<DispoBadge k={k}/></div>}
      actions={<>
        {canEdit&&<button onClick={()=>setEdit(true)} className="px-3 py-1.5 text-xs font-medium bg-midnight text-white hover:bg-carbon btn-brutal">Modifier</button>}
        <button onClick={()=>{onClose();onNavToContact&&onNavToContact(k.id);}} className="px-3 py-1.5 text-xs font-medium border-2 border-neutral-200 text-carbon hover:border-midnight">Fiche contact</button>
      </>}>
      <div className="flex gap-1 border-b-2 border-neutral-100 -mt-2">
        <button className={tabBtn('mission')} onClick={()=>setSub('mission')}>Mission</button>
        {k.isCdi&&<button className={tabBtn('interco')} onClick={()=>setSub('interco')}>Interco</button>}
        <button className={tabBtn('infos')} onClick={()=>setSub('infos')}>Infos</button>
      </div>
      {sub==='mission'&&(m?<div className="space-y-3">
        <div className="flex items-center justify-between"><div className="font-bold text-midnight">{m.client||'—'}{m.projet?<span className="text-slate font-normal"> · {m.projet}</span>:null}</div><MissionStatutBadge statut={m.statut}/></div>
        <Row l="Période" v={`${fmtDateFR(m.date_debut_mission)} → ${fmtDateFR(m.date_fin_mission)}`}/>
        <Row l="TJM" v={fmtEur0(k.tjm)}/><Row l="CJM" v={fmtEur0(k.cjm)}/>
        <Row l="Marge" v={<><MargeCell m={k.marge}/>{k.tjm!=null&&k.cjm!=null&&<span className="text-slate text-xs ml-2">{fmtEur0(k.tjm-k.cjm)} / j</span>}</>}/>
        {m.responsable&&<Row l="Commercial" v={m.responsable}/>}
        {periods.length>0&&<div><div className="text-[11px] font-bold uppercase tracking-[0.12em] text-slate mb-1">Périodes</div>{periods.map(p=><div key={p.id} className="text-xs text-slate py-0.5">{p.label||'Période'} · {fmtDateFR(p.debut)} → {fmtDateFR(p.fin)}{p.tjm_vente?` · TJM ${fmtEur0(p.tjm_vente)}`:''}</div>)}</div>}
        <button onClick={()=>setOpenMission(m)} className="px-3 py-1.5 text-xs font-medium border-2 border-neutral-200 text-carbon hover:border-midnight">Ouvrir la mission →</button>
      </div>:<div className="text-sm text-slate italic">{k.etat==='arret_maladie'||k.etat==='conge'?AgenceCalc.etatDispo(k).label:(k.isCdi?'En intercontrat · '+AgenceCalc.fmtJ(k.intercoAnnee)+' j cumulés cette année':'Sans mission en cours')}</div>)}
      {sub==='interco'&&k.isCdi&&<IntercoEditor contact={k} profile={profile}/>}
      {sub==='infos'&&<div>
        <Row l="Date d'entrée" v={fmtDateFR(k.date_entree)}/>
        {k.date_sortie&&<Row l="Date de sortie" v={fmtDateFR(k.date_sortie)}/>}
        {k.isCdi&&<Row l="Salaire brut annuel" v={fmtEur0(k.salaire_annuel)}/>}
        <Row l="CJM" v={<>{fmtEur0(k.cjm)} <span className="text-xs text-slate">{k.cjm_manuel?'(manuel)':'(calculé)'}</span></>}/>
        <Row l={k.isCdi?'Partner responsable':'Commercial'} v={(k.isCdi?k.partnerNom:k.responsable)||'—'}/>
        {!k.isCdi&&<Row l="Type" v={k.typeLabel}/>}
        <Row l="Statut RH" v={k.statut_rh?AgenceCalc.etatDispo({...k,etat:k.statut_rh}).label:'—'}/>
        {k.email&&<Row l="Email" v={k.email}/>}{k.telephone&&<Row l="Téléphone" v={k.telephone}/>}
      </div>}
    </SidePanel>
    {edit&&<ContactEditModal contact={k} profile={profile} allProfiles={allProfiles} comptes={comptes||[]} onClose={()=>setEdit(false)} onSaved={()=>{setEdit(false);onRefresh();}}/>}
    {openMission&&<MissionDetail mission={openMission} histMissions={histMissions||[]} missionPeriods={periods} contacts={contacts||[]} taches={taches||[]} missions={missions||[]} besoins={besoins||[]} comptes={comptes||[]} profile={profile} allProfiles={allProfiles} onClose={()=>setOpenMission(null)} onRefresh={()=>{setOpenMission(null);onRefresh();}} onNavToContact={onNavToContact} onNavToBesoin={()=>{}} onNavToTache={()=>{}} onNavToCompte={()=>{}}/>}
  </>;
}
```

- [ ] **Step 2: Compiler + recette**

Run: `node tests/check-babel.mjs`
Expected: `OK babel`. Navigateur : clic ligne → volet ; onglet Mission affiche TJM/CJM/marge/périodes ; « Ouvrir la mission → » ouvre `MissionDetail` par-dessus ; Interco montre l'histogramme ; « Modifier » ouvre le formulaire contact ; Échap ferme.

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat(agence): volet collaborateur (mission, interco, infos)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: Formulaires — section « Collaborateur », CJM auto, `defaults`

**Files:**
- Modify: `index.html:1349-1421` (`ContactEditModal`), `index.html:1771-1800` (`AddContactModal`)

**Interfaces:**
- Consumes: `AgenceCalc.cjmFromSalaire`, `AgenceCalc.MANAGER_TRIGRAMMES`, `Field`, `inputCls`.
- Produces: `AddContactModal` accepte `defaults?: {statut?, agence?}` ; un composant partagé `CollabFields({f, setF, isCdi, isSt})`.

- [ ] **Step 1: Composant partagé `CollabFields`** (à insérer juste avant `function ContactEditModal`)

```jsx
// Section « Collaborateur » des formulaires contact (statuts CDI / Freelance / Prestataire) — SPEC_agence_effectifs §5.6
function CollabFields({ f, setF }) {
  const isCdi=f.statut==='Consultant CDI', isSt=['Freelance','Prestataire'].includes(f.statut);
  if(!isCdi&&!isSt) return null;
  const s=k=>e=>setF(v=>({...v,[k]:e.target.value}));
  const onSalaire=e=>{const sal=e.target.value; setF(v=>({...v,salaire_annuel:sal,cjm:(!v.cjm_manuel&&sal!=='')?String(AgenceCalc.cjmFromSalaire(parseFloat(sal))):v.cjm}));};
  const onCjm=e=>setF(v=>({...v,cjm:e.target.value,cjm_manuel:true}));
  const recalc=()=>setF(v=>({...v,cjm_manuel:false,cjm:v.salaire_annuel?String(AgenceCalc.cjmFromSalaire(parseFloat(v.salaire_annuel))):v.cjm}));
  return <div style={{borderTop:'2px solid #E4E4E6',paddingTop:12,marginTop:12}} className="space-y-3">
    <div className="text-[11px] font-bold uppercase tracking-[0.12em] text-midnight">Collaborateur</div>
    <div className="grid grid-cols-2 gap-3">
      <Field label="Date d'entrée"><input type="date" value={f.date_entree||''} onChange={s('date_entree')} className={inputCls}/></Field>
      <Field label="Date de sortie"><input type="date" value={f.date_sortie||''} onChange={s('date_sortie')} className={inputCls}/></Field>
    </div>
    {isCdi&&<Field label="Salaire brut annuel (€)"><input type="number" value={f.salaire_annuel||''} onChange={onSalaire} className={inputCls} placeholder="ex: 52000"/></Field>}
    <Field label={<>CJM (€ / jour) <span className="text-slate font-normal normal-case">{f.cjm_manuel?'· saisi à la main':'· calculé = salaire / 215 × 1,7'}</span></>}>
      <div className="flex gap-2"><input type="number" value={f.cjm||''} onChange={onCjm} className={inputCls} placeholder="ex: 450"/>{isCdi&&f.cjm_manuel&&f.salaire_annuel&&<button type="button" onClick={recalc} className="px-2 text-xs border-2 border-neutral-200 hover:border-midnight whitespace-nowrap">Recalculer</button>}</div>
    </Field>
    <div className="grid grid-cols-2 gap-3">
      <Field label="Statut RH"><select value={f.statut_rh||''} onChange={s('statut_rh')} className={inputCls}><option value="">— (en mission / dispo)</option><option value="arret_maladie">Arrêt maladie</option><option value="conge">Congé</option></select></Field>
      <Field label="Depuis le"><input type="date" value={f.statut_rh_depuis||''} onChange={s('statut_rh_depuis')} className={inputCls} disabled={!f.statut_rh}/></Field>
    </div>
    <div className="grid grid-cols-2 gap-3">
      {isSt&&<Field label="Type"><select value={f.type_presta||(f.statut==='Prestataire'?'sous_traitant':'freelance')} onChange={s('type_presta')} className={inputCls}><option value="freelance">Freelance</option><option value="sous_traitant">Sous-traitant (portage, ESN)</option></select></Field>}
      <Field label={isCdi?'Partner responsable':'Manager (trigramme)'}><select value={f.manager_trigramme||''} onChange={s('manager_trigramme')} className={inputCls}><option value="">—</option>{Object.entries(AgenceCalc.MANAGER_TRIGRAMMES).sort((a,b)=>a[1].localeCompare(b[1])).map(([t,n])=><option key={t} value={t}>{n} ({t})</option>)}</select></Field>
    </div>
  </div>;
}
```

- [ ] **Step 2: `ContactEditModal`**

Ligne 1352, ajouter dans l'état initial : `date_entree:contact.date_entree||'', date_sortie:contact.date_sortie||'', salaire_annuel:contact.salaire_annuel??'', cjm_manuel:!!contact.cjm_manuel, statut_rh:contact.statut_rh||'', statut_rh_depuis:contact.statut_rh_depuis||'', type_presta:contact.type_presta||'', manager_trigramme:contact.manager_trigramme||''`.
Ligne 1358, après la construction de `upd`, ajouter :
```js
    if(['Consultant CDI','Freelance','Prestataire'].includes(f.statut)){
      Object.assign(upd,{ date_entree:f.date_entree||null, date_sortie:f.date_sortie||null, salaire_annuel:(f.salaire_annuel===''||f.salaire_annuel==null)?null:parseFloat(f.salaire_annuel), cjm_manuel:!!f.cjm_manuel, statut_rh:f.statut_rh||null, statut_rh_depuis:f.statut_rh?(f.statut_rh_depuis||getToday()):null, type_presta:f.statut==='Consultant CDI'?null:(f.type_presta||(f.statut==='Prestataire'?'sous_traitant':'freelance')), manager_trigramme:f.manager_trigramme||null });
      if(f.statut==='Consultant CDI'&&!f.cjm_manuel&&upd.salaire_annuel!=null) upd.cjm=AgenceCalc.cjmFromSalaire(upd.salaire_annuel);
    }
```
Ligne 1408 : **supprimer** l'ancien `<Field label="CJM …">` (remplacé par `CollabFields`) et insérer à sa place `<CollabFields f={f} setF={setF}/>`. Garder la ligne 1409 (`IntercoEditor`).
Ajouter aux `changes` tracés (après ligne 1370) : `if((f.salaire_annuel||'')!==String(contact.salaire_annuel??'')) changes.push('salaire modifié'); if((f.statut_rh||'')!==(contact.statut_rh||'')) changes.push(\`statut RH → ${f.statut_rh||'aucun'}\`);`

- [ ] **Step 3: `AddContactModal` avec `defaults`**

Signature ligne 1771 : `function AddContactModal({ profile, allProfiles, comptes, onClose, onSaved, defaults })`.
État initial : `statut:(defaults&&defaults.statut)||'Prospect'`, et ajouter `agence:(defaults&&defaults.agence)||profile.agence||'', date_entree:'', date_sortie:'', salaire_annuel:'', cjm_manuel:false, statut_rh:'', statut_rh_depuis:'', type_presta:'', manager_trigramme:''`.
Dans `save`, après la construction de `ins` : le même bloc `if(['Consultant CDI','Freelance','Prestataire'].includes(f.statut)){ Object.assign(ins, {...}) }` que ci-dessus (copier tel quel en remplaçant `upd` par `ins`), plus `ins.agence=f.agence||null;` si la colonne n'était pas déjà posée (vérifier dans `ins` existant : `agence` n'y est pas → l'ajouter).
Dans le JSX du formulaire, après le `Field` Statut, insérer `<CollabFields f={f} setF={setF}/>` et, si le formulaire n'a pas de champ Agence, ajouter : `<Field label="Agence"><select value={f.agence||''} onChange={s('agence')} className={inputCls}><option value="">—</option><option value="Lyon">Lyon</option><option value="Paris">Paris</option><option value="Bordeaux">Bordeaux</option><option value="Nantes">Nantes</option></select></Field>`.

- [ ] **Step 4: Compiler + recette**

Run: `node tests/check-babel.mjs`
Expected: `OK babel`. Recette : modifier un CDI → saisir salaire 61000 → CJM affiche 482.33 « calculé » ; taper un CJM à la main → « saisi à la main » + bouton Recalculer ; enregistrer, recharger : valeurs persistées, badge du volet Infos cohérent. « + Nouveau collaborateur » depuis l'onglet ST → statut pré-rempli Freelance, section Collaborateur visible.

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat(agence): section Collaborateur dans les formulaires contact, CJM auto

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Export Excel (SheetJS lazy)

**Files:**
- Modify: `index.html` (remplacer le stub `exportEffectifs`)

**Interfaces:**
- Consumes: `filteredSorted: Collab[]`, `mode`, `filterAgence`, `setBusy`.
- Produces: fichier `Effectifs_{CDI|ST}_{agence|France}_{AAAA-MM-JJ}.xlsx`.

- [ ] **Step 1: Implémenter**

```jsx
let _xlsxPromise=null;
function loadXlsx(){ // SheetJS chargé au 1er clic seulement (≈400 Ko), même CDN que React
  if(window.XLSX) return Promise.resolve(window.XLSX);
  if(!_xlsxPromise) _xlsxPromise=new Promise((res,rej)=>{const s=document.createElement('script');s.src='https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js';s.onload=()=>res(window.XLSX);s.onerror=()=>{_xlsxPromise=null;rej(new Error('SheetJS introuvable'));};document.head.appendChild(s);});
  return _xlsxPromise;
}
async function exportEffectifs(rows,mode,agence,setBusy){
  setBusy(true);
  try{
    const XLSX=await loadXlsx();
    const d=iso=>iso?new Date(iso.slice(0,10)+'T00:00:00'):null;
    const cdi=mode==='cdi';
    const head=cdi?['Nom Prénom','Agence','Partner','Entrée','Sortie','Salaire brut','CJM','Client','Fin mission','TJM','MCV','Dispo (j)','Interco cumulé (j)','Statut']
                  :['Nom Prénom','Type','Agence','Commercial','Entrée','Sortie','Client','Fin mission','CJM','TJM','MCV','Fin (j)','Statut'];
    const line=k=>{const m=k.missionEnCours||{};const st=AgenceCalc.etatDispo(k).label;return cdi
      ?[`${k.nom||''} ${k.prenom||''}`.trim(),k.agence||'',k.partnerNom||'',d(k.date_entree),d(k.date_sortie),k.salaire_annuel!=null?Number(k.salaire_annuel):null,k.cjm,m.client||'',d(m.date_fin_mission),k.tjm,k.marge,k.joursAvantDispo,k.intercoAnnee,st]
      :[`${k.nom||''} ${k.prenom||''}`.trim(),k.typeLabel,k.agence||'',k.responsable||'',d(k.date_entree),d(k.date_sortie),m.client||'',d(m.date_fin_mission),k.cjm,k.tjm,k.marge,k.joursAvantDispo,st];};
    const kp=AgenceCalc.computeKpis(rows,mode);
    const total=cdi?[`COLLAB ${cdi?'CDI':'ST'} (${kp.effectif})`,'','','','','',kp.cjmMoyen,'','',kp.tjmMoyen,kp.margeMoyenne,'',kp.intercoAnnee,'']
                   :[`SOUS-TRAITANTS (${kp.effectif})`,'','','','','','','',kp.cjmMoyen,kp.tjmMoyen,kp.margeMoyenne,'',''];
    const aoa=[head,...rows.map(line),[],total];
    const ws=XLSX.utils.aoa_to_sheet(aoa,{cellDates:true});
    const R=aoa.length, iMcv=head.indexOf('MCV'), dateCols=head.map((h,i)=>/Entrée|Sortie|Fin mission/.test(h)?i:-1).filter(i=>i>=0), eurCols=head.map((h,i)=>/Salaire|CJM|TJM/.test(h)?i:-1).filter(i=>i>=0);
    for(let r=1;r<R;r++){ const c=XLSX.utils.encode_cell({r,c:iMcv}); if(ws[c]&&typeof ws[c].v==='number') ws[c].z='0%';
      dateCols.forEach(ci=>{const a=XLSX.utils.encode_cell({r,c:ci}); if(ws[a]&&ws[a].v instanceof Date) ws[a].z='dd/mm/yyyy';});
      eurCols.forEach(ci=>{const a=XLSX.utils.encode_cell({r,c:ci}); if(ws[a]&&typeof ws[a].v==='number') ws[a].z='#,##0 €';}); }
    ws['!cols']=head.map(h=>({wch:h.length>10?h.length+2:12}));
    const wb=XLSX.utils.book_new(); XLSX.utils.book_append_sheet(wb,ws,cdi?'CDI':'Sous-traitants');
    XLSX.writeFile(wb,`Effectifs_${cdi?'CDI':'ST'}_${agence||'France'}_${TODAY}.xlsx`);
    toast(`Export ${rows.length} ligne${rows.length>1?'s':''}`);
  }catch(e){ toast('Export impossible : '+e.message,'error'); }
  finally{ setBusy(false); }
}
```
Vérifier que le CSP/service worker laisse passer `cdn.jsdelivr.net` (oui : `service-worker.js` l'ignore déjà).

- [ ] **Step 2: Compiler + recette**

Run: `node tests/check-babel.mjs`
Expected: `OK babel`. Navigateur : Export CDI avec filtre Lyon → fichier `Effectifs_CDI_Lyon_2026-….xlsx` ; ouvrir dans Excel : dates typées, MCV en %, dernière ligne « COLLAB CDI (n) » avec moyennes. Partner (Voir comme Majo) : export = ses lignes uniquement.

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat(agence): export Excel du tableau filtré (SheetJS lazy)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: Alertes proactives `ensureAlertesDispo`

**Files:**
- Modify: `index.html` (dans le composant App, après `fetchAll`/`useEffect([user])` ~8122)

**Interfaces:**
- Consumes: `AgenceCalc.computeCollab`, `AgenceCalc.planAlertes`, `FERIES_FR`, `data.contacts/missions/intercos/taches`, `profile`.
- Produces: tâches `taches` insérées (`id` = `al_<mission_id>_<ts>`), tâches clôturées (`statut:'fait'`, `date_completion`, `notes` complétées).

- [ ] **Step 1: Implémenter (après la ligne 8122)**

```js
  // ── Alertes fin de mission (SPEC_agence_effectifs §7) : 1 tâche par mission à ≤60 j, idempotent, clôture si prolongée.
  // Lancée par admin/commercial uniquement (un partner ne crée pas de tâche pour les commerciaux), une fois par chargement.
  const alertesRunRef=React.useRef('');
  useEffect(()=>{
    if(!data||!profile||profile.role==='partner'||viewAs) return;
    const key=TODAY+':'+(data.missions||[]).length+':'+(data.taches||[]).length;
    if(alertesRunRef.current===key) return; alertesRunRef.current=key;
    (async()=>{
      const ctx={missions:data.missions||[],intercos:data.intercos||[],partnerNomById:{},partnerIdByContact:{},todayISO:TODAY,annee:new Date().getFullYear()};
      const collabs=(data.contacts||[]).filter(c=>AgenceCalc.CONSULTANT_STATUTS_AGENCE.includes(c.statut)).map(c=>AgenceCalc.computeCollab(c,ctx));
      const {aCreer,aClore}=AgenceCalc.planAlertes(collabs,data.taches||[],{todayISO:TODAY,feries:FERIES_FR,profilNom:profile.nom});
      if(!aCreer.length&&!aClore.length) return;
      let n=0;
      for(const t of aCreer){ const {error}=await sb.from('taches').insert(t); if(!error) n++; }
      for(const c of aClore){ const t=(data.taches||[]).find(x=>x.id===c.id); await sb.from('taches').update({statut:'fait',date_completion:new Date().toISOString(),notes:((t&&t.notes)||'')+'\n'+c.note}).eq('id',c.id); }
      if(n||aClore.length){ toast(`${n} alerte${n>1?'s':''} fin de mission créée${n>1?'s':''}${aClore.length?`, ${aClore.length} clôturée${aClore.length>1?'s':''}`:''}`); fetchAll(); }
    })();
  },[data,profile,viewAs]);
```
⚠️ `fetchAll()` après création recharge `data` → la clé `key` change (nb tâches) → l'effet rejoue mais `planAlertes` ne trouve plus rien à créer (idempotence) → pas de boucle. Vérifier qu'aucun `sb.from('taches').insert` existant n'exige d'autres colonnes NOT NULL (le formulaire 1717 insère exactement ces champs : OK).

- [ ] **Step 2: Compiler + recette**

Run: `node tests/check-babel.mjs`
Expected: `OK babel`. Recette (sur prod, car pas de DB locale — prévenir Nicolas avant) : identifier un consultant à ≤ 60 j → au chargement, toast « 1 alerte … créée », la tâche apparaît dans Tâches avec due 09:30 prochain jour ouvré, responsable = commercial de la mission. Recharger : aucun doublon. Repousser la fin de mission > 60 j → tâche passe en `fait` avec la note « mission prolongée au … ».

- [ ] **Step 3: Commit**

```bash
git add index.html
git commit -m "feat(agence): alertes fin de mission automatiques (tâches CRM idempotentes)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: MCP `upgrade-crm` v8.15.0

**Files:**
- Modify: `../upgrade-crm-mcp-src/server/index.mjs:12` (version), `:359` (`CONTACT_ALLOWED_FIELDS`), `:2206-2235` (`crm_set_cjm`)
- Modify: `../upgrade-crm-mcp-src/manifest.json:5` (version + `long_description`)

**Interfaces:**
- Produces: `crm_set_cjm` pose `cjm_manuel:true` quand `cjm` est donné directement, `cjm_manuel:false` + `salaire_annuel` quand le salaire est donné ; `crm_update_contact` accepte `date_entree, date_sortie, salaire_annuel, statut_rh, statut_rh_depuis, type_presta, manager_trigramme`.

- [ ] **Step 1: Modifier le serveur**

Ligne 12 : `const CRM_VERSION = "8.15.0";` (+ `CRM_BUILD_DATE` = `"2026-09-…"` et une ligne de changelog là où le fichier les tient : « 8.15.0 : onglet Agence — champs collaborateur, cjm_manuel »).
Ligne 359 : ajouter à la `Set` : `"date_entree","date_sortie","salaire_annuel","statut_rh","statut_rh_depuis","type_presta","manager_trigramme"`.
Dans `crm_set_cjm`, remplacer le `sbPatch` par :
```js
    const patch = { cjm: newCjm, cjm_manuel: salaire_brut_annuel_k == null, updated_at: new Date().toISOString() };
    if (salaire_brut_annuel_k != null) patch.salaire_annuel = Math.round(salaire_brut_annuel_k * 1000);
    await sbPatch("contacts", { id: c.id }, patch);
```
`manifest.json` : `"version": "8.15.0"` et compléter `long_description` d'une phrase « v8.15 : champs collaborateur (onglet Agence) ».

- [ ] **Step 2: Valider**

Run: `cd ~/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-src && node --check server/index.mjs && python3 -c "import json;m=json.load(open('manifest.json'));print(m['version'])"`
Expected: pas d'erreur, `8.15.0`.

- [ ] **Step 3: Rebuild le `.mcpb`**

Run:
```bash
cd ~/Pro/03_Outils-IA/upgrade-crm && rm -rf /tmp/mcpb && mkdir /tmp/mcpb && unzip -q upgrade-crm-v8.14.0.mcpb -d /tmp/mcpb \
 && cp upgrade-crm-mcp-src/manifest.json /tmp/mcpb/manifest.json && cp upgrade-crm-mcp-src/server/index.mjs /tmp/mcpb/server/index.mjs \
 && (cd /tmp/mcpb && zip -rq ~/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-v8.15.0.mcpb manifest.json server) \
 && mv upgrade-crm-v8.1[0-4].0.mcpb _archive-mcpb/ && ls -la upgrade-crm-v8.15.0.mcpb
```
Expected: fichier ≈ 4,4 Mo. Puis dire à Nicolas : « MCP v8.15.0 prêt : réinstaller l'extension (pas juste restart) ; test = `crm_version` doit répondre 8.15.0 ». (`upgrade-crm-mcp-src` n'est pas un dépôt git : pas de commit.)

---

### Task 10: Import initial depuis l'Excel de Pierre

**Files:**
- Create: `~/Pro/Jules/bin/crm-import-collab.py`
- Create: `~/Pro/Jules/tests/test_crm_import_collab.py`

**Interfaces:**
- Produces: CLI `python3 ~/Pro/Jules/bin/crm-import-collab.py [--dry-run|--apply] [--xlsx PATH] [--overrides overrides.json]` ; rapports `~/Pro/Jules/journal/import-collab-dryrun.md` / `import-collab-apply.md`.
- Auth : comme le MCP, password grant Supabase avec `SUPABASE_EMAIL`/`SUPABASE_PASSWORD` lus dans `~/Pro/Jules/.mcp.json` → `mcpServers.upgrade-crm.env` (compte admin de Nicolas ⇒ RLS admin).

- [ ] **Step 1: Tests des fonctions pures (échouent : module absent)**

```python
# ~/Pro/Jules/tests/test_crm_import_collab.py
import unittest, sys, os, datetime as dt
sys.path.insert(0, os.path.expanduser('~/Pro/Jules/bin'))
import importlib; m = importlib.import_module('crm-import-collab')

class T(unittest.TestCase):
    def test_split_nom(self):
        self.assertEqual(m.split_nom('LOUIS BAÏDEZ Hadrien'), ('LOUIS BAÏDEZ', 'Hadrien'))
        self.assertEqual(m.split_nom('LE DU Anne-Charlotte'), ('LE DU', 'Anne-Charlotte'))
        self.assertEqual(m.split_nom('BRUNELIERE Adrien (Freelance)'), ('BRUNELIERE', 'Adrien'))
        self.assertEqual(m.split_nom('CORDEL Chloé (Freelance) - 4/5e - Bordeaux'), ('CORDEL', 'Chloé'))
        self.assertEqual(m.split_nom('GAUDICHON Edouard '), ('GAUDICHON', 'Edouard'))
    def test_norm_key(self):
        self.assertEqual(m.norm_key('JACQUETTON', 'Charléne'), 'jacquetton|charlene')
        self.assertEqual(m.norm_key(' Le Du ', 'anne-charlotte'), 'le du|anne-charlotte')
    def test_type_presta(self):
        self.assertEqual(m.type_presta_of('VASQUEZ Florent (Freelance - Portage Enedis)'), 'sous_traitant')
        self.assertEqual(m.type_presta_of('MANO Julien (Freelance)'), 'freelance')
    def test_salaire_from_cj(self):
        self.assertEqual(m.salaire_from_cj(482.3255813953488), 61000)
        self.assertEqual(m.salaire_from_cj(340), 43000)
    def test_parse_client(self):
        self.assertEqual(m.parse_client('Démarrage chez Société Générale le 02/10/2023'), ('Société Générale', '2023-10-02'))
        self.assertEqual(m.parse_client('Démarrage EDF  17/11/2025'), ('EDF', '2025-11-17'))
        self.assertEqual(m.parse_client('Démarrage chez CATS le 29/06/26 '), ('CATS', '2026-06-29'))
        self.assertEqual(m.parse_client("Démarrage chez l'Oréal le 11/06/2025"), ("l'Oréal", '2025-06-11'))
        self.assertEqual(m.parse_client('Recontacter Diego le client Juin/juillet 26'), (None, None))
        self.assertEqual(m.parse_client(None), (None, None))
    def test_to_iso(self):
        self.assertEqual(m.to_iso(dt.datetime(2026, 9, 22)), '2026-09-22')
        self.assertEqual(m.to_iso('29/06/26'), '2026-06-29')
        self.assertEqual(m.to_iso('/'), None); self.assertEqual(m.to_iso(None), None)
    def test_classify_rows(self):
        rows = [
            ('UPGRADE','NOM Prénom','Agence'), (None,)*3, ('Régies Paris - Nantes - Lyon - Bordeaux',None,None),
            (1,'PLANCOULAINE Anthony','Paris'), (1,'COLLAB Régies Paris - Nantes - Lyon - Bordeaux',None),
            ('Forfait',None,None), (1,'BONNET Margaux','Nantes'), (1,'COLLAB Forfait',None),
            (1,'BRUNELIERE Adrien (Freelance)','Paris'), (1,'SOUS-TRAITANTS',None), (104,'Productifs UPGRADE',None),
            (1,'DECKER Anne-Claire','Bordeaux'), (6,'Total interne',None),
        ]
        out = m.classify_rows(rows)
        self.assertEqual([(r['bloc'], r['raw'][1]) for r in out], [('cdi','PLANCOULAINE Anthony'),('cdi','BONNET Margaux'),('st','BRUNELIERE Adrien (Freelance)')])

if __name__ == '__main__': unittest.main()
```

- [ ] **Step 2: Lancer → échec**

Run: `python3 ~/Pro/Jules/tests/test_crm_import_collab.py 2>&1 | tail -2`
Expected: `ModuleNotFoundError: No module named 'crm-import-collab'`.

- [ ] **Step 3: Écrire le script**

```python
#!/usr/bin/env python3
"""Import initial des effectifs depuis Point_COLLAB-UPGRADE.xlsx vers le CRM (SPEC_agence_effectifs §8).
Usage : crm-import-collab.py [--dry-run] [--apply] [--xlsx PATH] [--overrides JSON]
Défaut = dry-run → journal/import-collab-dryrun.md. --apply écrit (jamais de DELETE), journal/import-collab-apply.md.
Auth Supabase = password grant avec les identifiants du MCP (~/Pro/Jules/.mcp.json → upgrade-crm.env)."""
import argparse, datetime as dt, json, os, re, sys, unicodedata, urllib.request
import openpyxl

SUPABASE_URL = "https://ehfseahxoivfhmpiyoqa.supabase.co"
ANON_KEY = "sb_publishable_BaNIdlZ09xavRRhG0G-ScQ_mW4hVueJ"
XLSX_DEFAULT = os.path.expanduser('~/Library/CloudStorage/OneDrive-NeuronesIT/Upgrade CODIR - TACE - TACE/Point_COLLAB-UPGRADE.xlsx')
JOURNAL = os.path.expanduser('~/Pro/Jules/journal')
COMMERCIAL_BY_TRI = {'NSE':'Nicolas Serradeil','ACD':'Anne-Claire Decker','CSA':'Camille Salinson','ABE':'Amel Benzai','PSO':'Pierre Solle'}
KNOWN_TRI = set(COMMERCIAL_BY_TRI) | {'MJP','LBL','CAJ','APL','WSA','FEL','HSI','SLE','JSE','COS'}
CDI_STATUT, ST_STATUTS = 'Consultant CDI', ('Freelance', 'Prestataire')

# ── fonctions pures (testées) ─────────────────────────────────────────────────
def _strip_accents(s): return ''.join(c for c in unicodedata.normalize('NFD', s or '') if unicodedata.category(c) != 'Mn')
def split_nom(raw):
    """'LOUIS BAÏDEZ Hadrien (Freelance) - 4/5e' → ('LOUIS BAÏDEZ','Hadrien') : le NOM = suite de mots en MAJUSCULES en tête."""
    s = re.split(r'\(| - ', (raw or '').strip())[0].strip()
    parts = s.split()
    i = 0
    while i < len(parts) and parts[i] == parts[i].upper() and not parts[i].isdigit(): i += 1
    if i == 0 or i == len(parts): i = max(1, len(parts) - 1)
    return ' '.join(parts[:i]), ' '.join(parts[i:])
def norm_key(nom, prenom): return f"{_strip_accents(nom).strip().lower()}|{_strip_accents(prenom).strip().lower()}"
def type_presta_of(raw): return 'sous_traitant' if re.search(r'portage|sous[- ]trait|esn', raw or '', re.I) else 'freelance'
def salaire_from_cj(cj): return int(round(float(cj) * 215 / 1.7 / 1000.0)) * 1000 if cj not in (None, '', '/') else None
def to_iso(v):
    if v in (None, '', '/'): return None
    if isinstance(v, dt.datetime): return v.date().isoformat()
    if isinstance(v, dt.date): return v.isoformat()
    m = re.match(r'^\s*(\d{1,2})/(\d{1,2})/(\d{2,4})\s*$', str(v))
    if not m: return None
    d, mo, y = int(m[1]), int(m[2]), int(m[3]); y = y + 2000 if y < 100 else y
    return dt.date(y, mo, d).isoformat()
def parse_client(txt):
    """'Démarrage chez Société Générale le 02/10/2023' → ('Société Générale','2023-10-02') ; sinon (None,None)."""
    if not txt or not re.search(r'd[ée]m+arr', txt, re.I): return (None, None)
    m = re.search(r'd[ée]m+arr\w*\s+(?:chez\s+|à\s+(?:la\s+)?|sur\s+)?(.+?)\s*(?:\ble\s+)?(\d{1,2}/\d{1,2}/\d{2,4})?\s*$', txt.strip(), re.I)
    if not m: return (None, None)
    client = re.sub(r'\s+(le|prévu|prévue)\s*$', '', m[1].strip(), flags=re.I).strip(' -')
    return (client or None, to_iso(m[2]) if m[2] else None)
def classify_rows(rows):
    """Parcourt la feuille TACE : ligne = collaborateur si col A numérique ET col B non vide ET pas une ligne de total.
    Bloc : 'cdi' jusqu'à la ligne 'SOUS-TRAITANTS' exclue (Régies + Forfait), 'st' = lignes '(Freelance…)', internes ignorés."""
    out, bloc = [], 'cdi'
    for r in rows:
        a, b = (r[0] if len(r) > 0 else None), (r[1] if len(r) > 1 else None)
        if isinstance(b, str) and re.match(r'^(COLLAB|SOUS-TRAITANTS|Productifs|Total)', b.strip(), re.I):
            if b.strip().upper().startswith('SOUS-TRAITANTS') or b.strip().startswith('Productifs'): bloc = 'interne'
            continue
        if not isinstance(a, (int, float)) or not isinstance(b, str) or not b.strip(): continue
        if bloc == 'interne': continue
        if '(Freelance' in b or '(freelance' in b: out.append({'bloc': 'st', 'raw': r})
        else: out.append({'bloc': 'cdi', 'raw': r})
    return out

# ── Supabase REST ────────────────────────────────────────────────────────────
def creds():
    cfg = json.load(open(os.path.expanduser('~/Pro/Jules/.mcp.json')))['mcpServers']['upgrade-crm']['env']
    return cfg['SUPABASE_EMAIL'], cfg['SUPABASE_PASSWORD']
def login():
    email, pwd = creds()
    req = urllib.request.Request(f"{SUPABASE_URL}/auth/v1/token?grant_type=password", data=json.dumps({'email': email, 'password': pwd}).encode(),
                                 headers={'apikey': ANON_KEY, 'Content-Type': 'application/json'})
    return json.load(urllib.request.urlopen(req))['access_token']
def rest(token, method, table, params='', body=None, prefer=None):
    h = {'apikey': ANON_KEY, 'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
    if prefer: h['Prefer'] = prefer
    req = urllib.request.Request(f"{SUPABASE_URL}/rest/v1/{table}{('?' + params) if params else ''}", method=method, headers=h,
                                 data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(req) as r:
        txt = r.read().decode(); return json.loads(txt) if txt else None

# ── Cœur ─────────────────────────────────────────────────────────────────────
def build_plan(sheet_rows, contacts, missions, overrides):
    idx = {}
    for c in contacts: idx.setdefault(norm_key(c.get('nom') or '', c.get('prenom') or ''), []).append(c)
    plan = {'match': [], 'create': [], 'ambigu': [], 'tri_inconnu': [], 'missions': []}
    for row in classify_rows(sheet_rows):
        r = row['raw']; raw, agence, entree, sortie, fin, cj, tjm, tri, projet = r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[10], (r[20] if len(r) > 20 else None)
        nom, prenom = split_nom(raw)
        key = norm_key(nom, prenom)
        if key in (overrides or {}).get('skip', []): continue
        forced = (overrides or {}).get('map', {}).get(key)
        cands = [c for c in contacts if c['id'] == forced] if forced else idx.get(key, [])
        if len(cands) > 1:
            same_ag = [c for c in cands if (c.get('agence') or '') == (agence or '')]
            cands = same_ag if len(same_ag) == 1 else cands
        is_cdi = row['bloc'] == 'cdi'
        patch = {'agence': agence, 'date_entree': to_iso(entree), 'date_sortie': to_iso(sortie), 'manager_trigramme': tri if tri in KNOWN_TRI else None}
        if is_cdi: patch.update({'statut': CDI_STATUT, 'salaire_annuel': salaire_from_cj(cj), 'cjm_manuel': False,
                                 'cjm': round(float(cj), 2) if cj not in (None, '', '/') else None})
        else: patch.update({'type_presta': type_presta_of(raw), 'cjm': round(float(cj), 2) if cj not in (None, '', '/') else None, 'cjm_manuel': True})
        if tri and tri not in KNOWN_TRI: plan['tri_inconnu'].append({'nom': raw, 'tri': tri})
        entry = {'raw': raw, 'nom': nom, 'prenom': prenom, 'agence': agence, 'patch': {k: v for k, v in patch.items() if v is not None}}
        if len(cands) == 1:
            c = cands[0]; entry['id'] = c['id']
            entry['diff'] = {k: (c.get(k), v) for k, v in entry['patch'].items() if str(c.get(k) if c.get(k) is not None else '') != str(v)}
            if not is_cdi and c.get('statut') not in ST_STATUTS: entry['patch']['statut'] = 'Prestataire' if patch['type_presta'] == 'sous_traitant' else 'Freelance'
            plan['match'].append(entry)
            has_mission = any(m.get('contact_consultant_id') == c['id'] and m.get('statut') == 'En cours' for m in missions)
        elif len(cands) == 0:
            entry['insert'] = dict(entry['patch'], nom=nom, prenom=prenom, statut=CDI_STATUT if is_cdi else ('Prestataire' if patch.get('type_presta') == 'sous_traitant' else 'Freelance'),
                                   responsable=COMMERCIAL_BY_TRI.get(tri, 'Pierre Solle'), nb_relance=0)
            plan['create'].append(entry); has_mission = False
        else:
            entry['candidats'] = [{'id': c['id'], 'statut': c.get('statut'), 'agence': c.get('agence')} for c in cands]; plan['ambigu'].append(entry); continue
        client, debut = parse_client(projet)
        fin_iso = to_iso(fin)
        if not has_mission and tjm not in (None, '', '/') and fin_iso and client:
            plan['missions'].append({'pour': raw, 'contact_key': key, 'contact_id': entry.get('id'), 'mission': {
                'consultant': f"{prenom} {nom}", 'client': client, 'tjm': float(tjm), 'cjm': entry['patch'].get('cjm'), 'statut': 'En cours',
                'date_debut_mission': debut, 'date_fin_mission': fin_iso, 'agence': agence, 'responsable': COMMERCIAL_BY_TRI.get(tri, 'Pierre Solle'),
                'type_contrat': 'CDI' if is_cdi else 'Freelance'}})
    return plan

def render(plan, applied=None):
    L = [f"# Import Point_COLLAB → CRM — {'APPLY' if applied is not None else 'DRY-RUN'} {dt.datetime.now():%Y-%m-%d %H:%M}", '']
    L += [f"- ✅ matchés : {len(plan['match'])} (dont {sum(1 for e in plan['match'] if e['diff'])} avec changements)", f"- ➕ à créer : {len(plan['create'])}",
          f"- ⚠️ ambigus : {len(plan['ambigu'])}", f"- ❓ trigrammes inconnus : {len(plan['tri_inconnu'])}", f"- 🧾 missions à créer : {len(plan['missions'])}", '']
    L += ['## ✅ Matchés avec changements'] + [f"- #{e['id']} {e['raw']} → " + ', '.join(f"{k}: {a!r}→{b!r}" for k, (a, b) in e['diff'].items()) for e in plan['match'] if e['diff']] + ['']
    L += ['## ➕ À créer'] + [f"- {e['raw']} ({e['agence']}) → {json.dumps(e['insert'], ensure_ascii=False)}" for e in plan['create']] + ['']
    L += ['## ⚠️ Ambigus (préciser dans overrides.json → "map": {"nom|prenom": id})'] + [f"- {e['raw']} : {e['candidats']}" for e in plan['ambigu']] + ['']
    L += ['## ❓ Trigrammes inconnus'] + [f"- {x['nom']} : {x['tri']}" for x in plan['tri_inconnu']] + ['']
    L += ['## 🧾 Missions à créer (aucune mission En cours au CRM)'] + [f"- {m['pour']} → {json.dumps(m['mission'], ensure_ascii=False)}" for m in plan['missions']] + ['']
    if applied is not None: L += ['## Écritures effectuées'] + [f"- {a}" for a in applied]
    return '\n'.join(L)

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--apply', action='store_true'); ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--xlsx', default=XLSX_DEFAULT); ap.add_argument('--overrides'); a = ap.parse_args()
    overrides = json.load(open(a.overrides)) if a.overrides else {}
    ws = openpyxl.load_workbook(a.xlsx, data_only=True)['TACE']
    rows = list(ws.iter_rows(values_only=True))
    token = login()
    contacts = rest(token, 'GET', 'contacts', 'select=id,nom,prenom,statut,agence,cjm,cjm_manuel,salaire_annuel,date_entree,date_sortie,type_presta,manager_trigramme,responsable&limit=10000')
    missions = rest(token, 'GET', 'missions', 'select=id,contact_consultant_id,statut,client,date_fin_mission&limit=10000')
    plan = build_plan(rows, contacts, missions, overrides)
    if not a.apply:
        out = os.path.join(JOURNAL, 'import-collab-dryrun.md'); open(out, 'w').write(render(plan)); print(render(plan)); print(f"\n→ {out}"); return
    applied = []
    for e in plan['match']:
        if e['diff']:
            rest(token, 'PATCH', 'contacts', f"id=eq.{e['id']}", dict(e['patch'], updated_at=dt.datetime.utcnow().isoformat()), prefer='return=minimal'); applied.append(f"PATCH contact #{e['id']} {e['raw']}")
    key_to_id = {}
    for e in plan['create']:
        res = rest(token, 'POST', 'contacts', '', dict(e['insert'], updated_at=dt.datetime.utcnow().isoformat()), prefer='return=representation')
        cid = res[0]['id']; key_to_id[norm_key(e['nom'], e['prenom'])] = cid; applied.append(f"INSERT contact #{cid} {e['raw']}")
        rest(token, 'POST', 'historique_actions', '', {'id_prospect': cid, 'date': dt.date.today().isoformat(), 'type_action': 'Note interne', 'details': 'Fiche créée par import Point_COLLAB (onglet Agence)', 'responsable': e['insert']['responsable']}, prefer='return=minimal')
    for m in plan['missions']:
        cid = m['contact_id'] or key_to_id.get(m['contact_key'])
        if not cid: continue
        body = dict(m['mission'], contact_consultant_id=cid)
        res = rest(token, 'POST', 'missions', '', body, prefer='return=representation'); applied.append(f"INSERT mission #{res[0]['id']} {m['pour']} @ {body['client']}")
    out = os.path.join(JOURNAL, 'import-collab-apply.md'); open(out, 'w').write(render(plan, applied)); print(f"{len(applied)} écritures → {out}")

if __name__ == '__main__': main()
```
Rendre exécutable : `chmod +x ~/Pro/Jules/bin/crm-import-collab.py`.

- [ ] **Step 4: Tests → verts**

Run: `python3 ~/Pro/Jules/tests/test_crm_import_collab.py 2>&1 | tail -3`
Expected: `OK` (7 tests). Si `parse_client` échoue sur `'Démarrage EDF  17/11/2025'` : la regex doit accepter l'absence de « chez » et de « le » (déjà prévu par `(?:chez\s+|…)?` et `(?:\ble\s+)?`) ; ajuster la regex, pas le test.

- [ ] **Step 5: Dry-run réel**

Run: `python3 ~/Pro/Jules/bin/crm-import-collab.py --dry-run | head -40`
Expected: bilan avec ≈ 62 CDI (61 régie + 1 forfait) + 42 ST traités, 0 écriture ; fichier `journal/import-collab-dryrun.md` créé. Vérifier à la main 3 lignes « matchés avec changements » et que les 6 internes (Decker, Serradeil, Salinson, Benzai, Leherle, Py) n'apparaissent NULLE PART.

- [ ] **Step 6: Commit (repo Jules)**

```bash
cd ~/Pro/Jules && git add bin/crm-import-collab.py tests/test_crm_import_collab.py
git commit -m "feat(crm): import effectifs Point_COLLAB → CRM (dry-run/apply)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

- [ ] **Step 7: GO Nicolas puis apply**

Joindre le dry-run à Nicolas (`[JOINDRE: journal/import-collab-dryrun.md]`), attendre son GO (+ `overrides.json` éventuel pour les ambigus), puis `python3 ~/Pro/Jules/bin/crm-import-collab.py --apply --overrides overrides.json` et vérifier dans l'onglet Agence : effectif CDI ≈ 62, ST ≈ 42, KPI moyens ≈ ligne « COLLAB » de l'Excel (CJM régie ≈ 380 €, TJM ≈ 627 €, MCV ≈ 40 %).

---

### Task 11: Recette finale et livraison

**Files:** aucun nouveau.

- [ ] **Step 1: Checklist de recette (spec §10)**

Run: `node --test tests/agence-calc.test.mjs && node tests/check-babel.mjs && python3 ~/Pro/Jules/tests/test_crm_import_collab.py`
Expected: tout vert. Puis en local (`http://localhost:8080/index.html`) :
- Nicolas (admin) : onglet Agence 2e position, jade, `2` l'active ; 4 dalles + détails (effectif/interco/TJM/marge), dalle interco absente de l'onglet Missions ; tri Dispo par défaut ; couleurs ≤ 60 orange / ≤ 30 rouge / dépassée rouge ; interco gris avec cumul ; export Excel ouvert dans Excel ; alertes créées sans doublon au 2e rechargement.
- « Voir comme » Amel (commercial Paris) : France entière, filtre Paris pré-réglé, création possible.
- « Voir comme » Majo (partner) : uniquement ses consultants, pas de filtre agence, pas de bouton Nouveau, onglets Besoins/Pipe/Prosp absents.
- Mobile (DevTools 390 px) : cartes, pas de scroll horizontal hors tableau.

- [ ] **Step 2: Capture + OK Nicolas**

Poster 2 captures (CDI + volet) à Nicolas. Attendre son OK explicite.

- [ ] **Step 3: Livraison (par Nicolas)**

Rappeler l'ordre : (1) `db/20_agence.sql` déjà appliqué (Task 1) ; (2) `! git -C ~/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2 push origin main` ; (3) recharger la PWA (nouveau service worker v4) ; (4) réinstaller le MCP v8.15.0 (Task 9) ; (5) import `--apply` (Task 10).

- [ ] **Step 4: Mémoire**

Capturer une leçon si un piège a été rencontré (`python3 ~/Pro/Jules/bin/jules-memoire.py capture …`) et noter dans `journal/AAAA-MM-JJ.md` la livraison.
