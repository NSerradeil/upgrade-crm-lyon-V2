# Filtre "Actifs" sur l'onglet Besoins — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter un pill "ACTIFS" en 1ʳᵉ position du filtre statut de l'onglet Besoins (vue Liste), sélectionné par défaut, qui masque les besoins de statut "Besoin Perdu". La vue Kanban reste strictement inchangée.

**Architecture:** Modification ciblée d'un seul composant React (`TabBesoins`) dans le fichier source unique `CRM_Live.html`. Introduction d'une constante sentinel `BESOIN_FILTER_ACTIFS = 'ACTIFS'`, d'un nouveau pill, et d'une dérivation `sortedList` qui applique le filtre uniquement à la vue Liste — `KanbanBesoins` continue de consommer `sorted` non-filtré-actifs.

**Tech Stack:** React 18 (UMD, pas de build), Babel standalone (transpile JSX en navigateur), Tailwind CSS, fichier unique HTML. Pas de framework de tests automatisés — vérif via `check_crm.js` (sanity JSX) + recette manuelle sur staging.

**Spec source :** `~/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/SPECS_CRM/SPEC_besoin_filtre_actifs.md`

**Fichier édité :** `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html`

---

## File Structure

| Fichier | Action | Rôle |
|---|---|---|
| `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html` | **Modify** | Source unique du SPA — toutes les modifs vont là |
| `~/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/index.html` | **Pas touché manuellement** | Fichier déployé, écrasé par `deploy_staging.sh` / `deploy_prod.sh` |

---

## Task 1: Vérifier l'état initial

**Files:** lecture seule

- [ ] **Step 1: Confirmer la cible et le repo git**

```bash
ls -la ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
cd ~/Pro/02_Agence/LYON/CRM && git status
```

Expected: fichier présent, repo git propre (pas de modif en cours sur `CRM_Live.html`).

- [ ] **Step 2: Vérifier les lignes de référence dans CRM_Live.html**

```bash
grep -n "function TabBesoins\|const STATUT_BTNS\|BESOIN_STATUTS_ORDRE = \[\|<KanbanBesoins" ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

Expected:
- `BESOIN_STATUTS_ORDRE = [` à la ligne 205
- `function TabBesoins` à la ligne 3884
- `const STATUT_BTNS=[` à la ligne 3924
- `<KanbanBesoins besoins={sorted}` à la ligne 4035

Si les lignes ont bougé : ajuster les références dans les tasks suivantes en conséquence.

---

## Task 2: Ajouter la constante sentinel `BESOIN_FILTER_ACTIFS`

**Files:**
- Modify: `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html` (ligne ~205)

- [ ] **Step 1: Repérer la ligne d'insertion**

Le fichier contient déjà :
```js
const BESOIN_STATUTS_ORDRE = ['Opportunité','Push opportuniste','Besoin ouvert','Profil proposé','Entretien programmé','Entretien passé','Besoin Gagné','Besoin Perdu'];
```

- [ ] **Step 2: Ajouter la constante juste après**

Edit : insérer une nouvelle ligne immédiatement après `const BESOIN_STATUTS_ORDRE = [...];`

```js
const BESOIN_STATUTS_ORDRE = ['Opportunité','Push opportuniste','Besoin ouvert','Profil proposé','Entretien programmé','Entretien passé','Besoin Gagné','Besoin Perdu'];
const BESOIN_FILTER_ACTIFS = 'ACTIFS';
```

- [ ] **Step 3: Vérifier syntaxe**

```bash
node ~/Pro/02_Agence/LYON/CRM/supabase/check_crm.js ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

Expected: aucune erreur de parsing JSX.

---

## Task 3: Ajouter le pill ACTIFS au tableau `STATUT_BTNS`

**Files:**
- Modify: `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html` (ligne 3924-3934)

- [ ] **Step 1: Localiser le tableau actuel**

État actuel (ligne 3924) :
```js
const STATUT_BTNS=[
  {label:'TOUS',value:''},
  {label:'OPPORTUNITÉ',value:'Opportunité'},
  {label:'PUSH',value:'Push opportuniste'},
  {label:'OUVERT',value:'Besoin ouvert'},
  {label:'PROFIL PROPOSÉ',value:'Profil proposé'},
  {label:'ENTRETIEN PROG.',value:'Entretien programmé'},
  {label:'ENTRETIEN PASSÉ',value:'Entretien passé'},
  {label:'GAGNÉ',value:'Besoin Gagné'},
  {label:'PERDU',value:'Besoin Perdu'},
];
```

- [ ] **Step 2: Insérer ACTIFS en 1ʳᵉ position**

Remplacement par :
```js
const STATUT_BTNS=[
  {label:'ACTIFS',value:BESOIN_FILTER_ACTIFS},
  {label:'TOUS',value:''},
  {label:'OPPORTUNITÉ',value:'Opportunité'},
  {label:'PUSH',value:'Push opportuniste'},
  {label:'OUVERT',value:'Besoin ouvert'},
  {label:'PROFIL PROPOSÉ',value:'Profil proposé'},
  {label:'ENTRETIEN PROG.',value:'Entretien programmé'},
  {label:'ENTRETIEN PASSÉ',value:'Entretien passé'},
  {label:'GAGNÉ',value:'Besoin Gagné'},
  {label:'PERDU',value:'Besoin Perdu'},
];
```

- [ ] **Step 3: Vérifier syntaxe**

```bash
node ~/Pro/02_Agence/LYON/CRM/supabase/check_crm.js ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

Expected: PASS.

---

## Task 4: Changer le state initial de `filterStatut`

**Files:**
- Modify: `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html` (ligne 3885)

- [ ] **Step 1: Localiser le state**

État actuel (ligne 3885) :
```js
const [search,setSearch]=useState(''); const [filterStatut,setFilterStatut]=useState('');
```

- [ ] **Step 2: Remplacer le défaut par ACTIFS**

Remplacement (uniquement le `useState('')` du `filterStatut`, pas celui de `search`) :
```js
const [search,setSearch]=useState(''); const [filterStatut,setFilterStatut]=useState(BESOIN_FILTER_ACTIFS);
```

- [ ] **Step 3: Vérifier syntaxe**

```bash
node ~/Pro/02_Agence/LYON/CRM/supabase/check_crm.js ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

Expected: PASS.

---

## Task 5: Modifier la condition de filtre dans `sorted`

**Files:**
- Modify: `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html` (ligne 3906)

**Principe** : `sorted` est consommé par le Kanban (ligne 4035). Il doit donc **ignorer** le sentinel ACTIFS — ACTIFS sera appliqué uniquement sur la dérivation `sortedList` (Task 6).

- [ ] **Step 1: Localiser la condition de filtre statut**

État actuel (ligne 3906, à l'intérieur de `.filter(b=>{...})`) :
```js
if(filterStatut&&b.statut!==filterStatut) return false;
```

- [ ] **Step 2: Remplacer par une version qui ignore le sentinel ACTIFS**

```js
if(filterStatut && filterStatut!==BESOIN_FILTER_ACTIFS && b.statut!==filterStatut) return false;
```

- [ ] **Step 3: Vérifier syntaxe**

```bash
node ~/Pro/02_Agence/LYON/CRM/supabase/check_crm.js ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

Expected: PASS.

---

## Task 6: Ajouter la dérivation `sortedList`

**Files:**
- Modify: `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html` (juste après le bloc `sorted`, autour de la ligne 3919-3920)

- [ ] **Step 1: Localiser la fin du bloc `sorted`**

Le bloc `sorted` se termine ligne 3919 (approx) par :
```js
.sort((a,b)=>BESOIN_STATUTS_ORDRE.indexOf(a.statut)-BESOIN_STATUTS_ORDRE.indexOf(b.statut));
},[besoins,search,filterStatut,filterResp,filterAgence,contactMap]);
```

- [ ] **Step 2: Insérer `sortedList` juste après**

Ajouter une nouvelle ligne :
```js
const sortedList=useMemo(()=>filterStatut===BESOIN_FILTER_ACTIFS?sorted.filter(b=>b.statut!=='Besoin Perdu'):sorted,[sorted,filterStatut]);
```

Le bloc final doit ressembler à :
```js
const sorted=useMemo(()=>{
  /* ... existant ... */
},[besoins,search,filterStatut,filterResp,filterAgence,contactMap]);

const sortedList=useMemo(()=>filterStatut===BESOIN_FILTER_ACTIFS?sorted.filter(b=>b.statut!=='Besoin Perdu'):sorted,[sorted,filterStatut]);
```

- [ ] **Step 3: Vérifier syntaxe**

```bash
node ~/Pro/02_Agence/LYON/CRM/supabase/check_crm.js ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

Expected: PASS.

---

## Task 7: Mettre à jour `hasFilter` et `resetAll`

**Files:**
- Modify: `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html` (lignes 3921-3922)

**Principe** : ACTIFS est l'état "neutre" (défaut). Il ne doit pas être perçu comme un filtre actif (sinon le bouton ✕ s'affiche en permanence). Le `resetAll` remet ACTIFS, pas TOUS.

- [ ] **Step 1: Localiser les deux lignes**

État actuel (lignes 3921-3922) :
```js
const hasFilter=search||filterStatut||filterResp||(isAdmin?filterAgence!=='':filterAgence!==profile.agence);
const resetAll=()=>{setSearch('');setFilterStatut('');setFilterResp('');setFilterAgence(isAdmin?'':profile.agence);};
```

- [ ] **Step 2: Remplacer**

```js
const hasFilter=search||(filterStatut&&filterStatut!==BESOIN_FILTER_ACTIFS)||filterResp||(isAdmin?filterAgence!=='':filterAgence!==profile.agence);
const resetAll=()=>{setSearch('');setFilterStatut(BESOIN_FILTER_ACTIFS);setFilterResp('');setFilterAgence(isAdmin?'':profile.agence);};
```

- [ ] **Step 3: Vérifier syntaxe**

```bash
node ~/Pro/02_Agence/LYON/CRM/supabase/check_crm.js ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

Expected: PASS.

---

## Task 8: Mettre à jour le compteur (utiliser `sortedList`)

**Files:**
- Modify: `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html` (ligne 3976)

- [ ] **Step 1: Localiser la ligne du compteur**

État actuel (ligne 3976) :
```jsx
<div className="text-xs text-neutral-300 mb-3">{sorted.length} besoin{sorted.length>1?'s':''}</div>
```

- [ ] **Step 2: Remplacer**

```jsx
<div className="text-xs text-neutral-300 mb-3">{sortedList.length} besoin{sortedList.length>1?'s':''}{filterStatut===BESOIN_FILTER_ACTIFS?' actif'+(sortedList.length>1?'s':''):''}{filterStatut==='Besoin Perdu'?' perdu'+(sortedList.length>1?'s':''):''}</div>
```

- [ ] **Step 3: Vérifier syntaxe**

```bash
node ~/Pro/02_Agence/LYON/CRM/supabase/check_crm.js ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

Expected: PASS.

---

## Task 9: Mettre à jour le grouping par statut (utiliser `sortedList`)

**Files:**
- Modify: `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html` (lignes 3978-3979)

- [ ] **Step 1: Localiser le bloc de grouping**

État actuel (ligne 3978) :
```jsx
{(filterStatut?[filterStatut]:BESOIN_STATUTS_ORDRE).map(statut=>{
  const items=sorted.filter(b=>b.statut===statut);
```

- [ ] **Step 2: Remplacer la ligne 3978 (l'expression d'itération)**

```jsx
{(filterStatut===BESOIN_FILTER_ACTIFS?BESOIN_STATUTS_ORDRE.filter(s=>s!=='Besoin Perdu'):filterStatut?[filterStatut]:BESOIN_STATUTS_ORDRE).map(statut=>{
```

- [ ] **Step 3: Remplacer la ligne 3979 (le filtre des items dans la section)**

```jsx
const items=sortedList.filter(b=>b.statut===statut);
```

- [ ] **Step 4: Vérifier syntaxe**

```bash
node ~/Pro/02_Agence/LYON/CRM/supabase/check_crm.js ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

Expected: PASS.

---

## Task 10: Vérifier que le Kanban reste intact

**Files:**
- Read-only check: `~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html` (ligne 4035)

- [ ] **Step 1: Confirmer que la prop `besoins` du Kanban consomme bien `sorted` (et non `sortedList`)**

```bash
grep -n "<KanbanBesoins besoins=" ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

Expected output: `<KanbanBesoins besoins={sorted} ...` (variable `sorted`, pas `sortedList`).

→ Si la sortie montre `sortedList`, **ANNULER cette modif** : la consigne explicite est que la vue Kanban ne change pas.

---

## Task 11: Tester localement avant deploy

**Files:** aucun (test navigateur)

- [ ] **Step 1: Ouvrir le fichier source dans le navigateur**

```bash
open ~/Pro/02_Agence/LYON/CRM/supabase/CRM_Live.html
```

- [ ] **Step 2: Connexion + onglet Besoins**

Se connecter avec un compte admin (Nicolas / Pierre) → cliquer sur l'onglet "Besoins".

- [ ] **Step 3: Checklist de recette locale**

Cocher visuellement chaque point :

| # | Vérif | Attendu |
|---|---|---|
| 1 | Pill ACTIFS visible | En 1ʳᵉ position, sélectionné (fond noir, texte blanc) |
| 2 | Pill TOUS visible | En 2ᵉ position, non sélectionné |
| 3 | Liste affichée | Aucune section "Besoin Perdu" visible |
| 4 | Compteur | "X besoin(s) actif(s)" |
| 5 | Clic sur PERDU | Affiche uniquement les perdus, compteur "X besoin(s) perdu(s)" |
| 6 | Clic sur TOUS | Toutes les sections affichées, perdus inclus, compteur "X besoin(s)" |
| 7 | Clic sur ACTIFS | Retour à l'état initial |
| 8 | Search "test" + ACTIFS | La recherche filtre + ACTIFS masque toujours les perdus matchés |
| 9 | Bouton ✕ "reset filtres" | NE s'affiche PAS quand seul ACTIFS est actif |
| 10 | Bouton ✕ après search | S'affiche, clic remet ACTIFS + search vide |
| 11 | Bascule en vue Kanban | Colonne "Besoin Perdu" toujours présente, comportement inchangé |
| 12 | Vue Kanban → retour Liste | Filtre ACTIFS toujours actif (le state se conserve) |

- [ ] **Step 4: Si échec sur un point, identifier la task à corriger et reprendre**

---

## Task 12: Commit + deploy staging

**Files:** git commit + script de deploy

- [ ] **Step 1: Vérifier le diff**

```bash
cd ~/Pro/02_Agence/LYON/CRM && git diff supabase/CRM_Live.html
```

Expected: uniquement les modifs liées au filtre ACTIFS (constante, STATUT_BTNS, sorted/sortedList, hasFilter/resetAll, compteur, grouping).

- [ ] **Step 2: Commit**

```bash
cd ~/Pro/02_Agence/LYON/CRM && git add supabase/CRM_Live.html && git commit -m "feat(besoins): filtre ACTIFS par défaut (masque les Besoin Perdu, vue Liste uniquement)"
```

- [ ] **Step 3: Deploy staging**

```bash
bash ~/Pro/02_Agence/LYON/CRM/supabase/deploy_staging.sh
```

Expected: le script lance le `check_crm.js`, push sur la branche `staging` du repo `upgrade-crm-lyon-V2`, affiche l'URL de preview.

- [ ] **Step 4: Recette sur staging**

Ouvrir l'URL de preview indiquée par le script (typiquement `https://nserradeil.github.io/upgrade-crm-lyon-V2/?staging` ou similaire). Refaire la checklist de la Task 11 sur l'env staging.

---

## Task 13: Deploy prod

**Files:** script de deploy

⚠ **Faire valider la recette par Nicolas avant cette étape.**

- [ ] **Step 1: Validation utilisateur**

Demander à Nicolas : "Recette staging OK, je peux push en prod ?"

- [ ] **Step 2: Deploy prod**

```bash
bash ~/Pro/02_Agence/LYON/CRM/supabase/deploy_prod.sh
```

Expected: merge `staging` → `main`, sauvegarde du hash pour rollback, push sur GitHub Pages prod.

- [ ] **Step 3: Vérification post-deploy**

Ouvrir l'URL prod : `https://nserradeil.github.io/upgrade-crm-lyon-V2/`

Vérifier que la 1ʳᵉ chose visible sur l'onglet Besoins est bien le pill ACTIFS sélectionné par défaut.

- [ ] **Step 4: Si bug détecté en prod**

```bash
bash ~/Pro/02_Agence/LYON/CRM/supabase/rollback.sh
```

---

## Self-Review

Vérifications faites avant remise du plan :

- [x] **Spec coverage** : chaque acceptance criterion du SPEC est couvert par une étape de recette en Task 11/12
- [x] **Pas de placeholder** : aucun "TBD"/"TODO" dans le plan, tous les blocs de code sont complets et runnables
- [x] **Type consistency** : `BESOIN_FILTER_ACTIFS`, `sortedList`, `filterStatut` utilisent les mêmes noms de bout en bout
- [x] **Conformité contrainte Kanban** : Task 10 = checkpoint explicite que `<KanbanBesoins besoins={sorted}>` reste avec `sorted` (et non `sortedList`)

---

## Récap UX final attendu

```
[ ACTIFS ✓ ]  [ TOUS ]  [ OPPORTUNITÉ ]  [ PUSH ]  [ OUVERT ]  [ PROFIL PROPOSÉ ]  [ ENTRETIEN PROG. ]  [ ENTRETIEN PASSÉ ]  [ GAGNÉ ]  [ PERDU ]
57 besoins actifs
```

Section "Besoin Perdu" absente. Bouton ✕ caché. Vue Kanban inchangée.
