# Droits d'écriture élargis + visibilité inter-agences — Plan d'implémentation

**Goal :** tout commercial peut modifier n'importe quel objet du CRM (sans le supprimer ni
changer son responsable), avec trace automatique ; et plus aucun objet n'est caché à son
propre responsable quand son agence diffère.

**Architecture :** tout se joue dans `index.html` (mono-fichier React + Babel in-browser).
Chantier A = dédoubler le gate `isOwner`/`canEdit` en deux notions distinctes `canEdit`
(ouvert) / `canDelete` (propriétaire) dans 5 panneaux, + un helper `logEdits` central.
Chantier B = ajouter la clause `|| responsable === moi` sur 2 filtres, + élargir la liste
des responsables proposés. **Aucune migration DB** : les policies RLS ne restreignent que
le rôle `partner`.

**Tech stack :** React 18 via CDN, Babel standalone, Supabase JS, Tailwind CDN.

## Global Constraints

- `index.html` fait 8014 lignes et **ne se compile pas** : une `SyntaxError` Babel = écran
  blanc en prod. Chaque tâche se termine par un chargement réel de la page.
- **Pas de framework de test** dans ce projet. La vérification se fait au navigateur, par
  assertions `browser_evaluate` sur l'état réel du DOM. C'est le substitut au test unitaire :
  aucune tâche n'est « faite » sans une assertion exécutée qui retourne le résultat attendu.
- **Prod = `main` → GitHub Pages, pas de staging.** Validation en local + OK Nicolas avant
  tout push (règle `crm-deploy-local-avant-prod`).
- Le rôle `partner` (Maria-José) ne doit gagner **aucun** droit. Ses restrictions dures sont
  en base (`*_partner_*`), mais l'UI ne doit pas non plus lui afficher de boutons nouveaux.
- Serveur local : `python3 -m http.server 8899` depuis la racine du repo. Verrou navigateur
  obligatoire avant toute session Playwright (`bin/jules-browser-lock.sh`).

---

## Fichiers touchés

| Fichier | Rôle |
|---|---|
| `index.html` | tout le code applicatif (mono-fichier, pas de découpage possible sans refonte) |
| `SPECS_CRM/PLAN_droits_ecriture_et_visibilite.md` | ce plan, cases à cocher au fil de l'eau |

---

## Task 1 : Chantier B — la clause de visibilité manquante

Le plus petit gain le plus rapide : 110 contacts redeviennent visibles à leur responsable.
Indépendant du chantier A, donc livré et vérifié d'abord.

**Files :** Modify `index.html:2625`, `index.html:5035`

**Interfaces :**
- Consomme : `profile.nom` (déjà dans le scope des deux composants), `filterAgence`, `filterMine`
- Produit : rien de nouveau. Aligne `TabProspects` et `TabPipe` sur la logique déjà en place
  lignes 4714 (`TabBesoins`) et 5538 (`TabMissions`).

- [ ] **Step 1 : poser l'assertion qui échoue (avant modification)**

Serveur local lancé, connecté, onglet Prospects. Filtrer l'agence sur « Paris ».
Assertion à exécuter :

```js
// doit renvoyer 0 AVANT le fix : aucun contact hors-agence visible
() => {
  const rows=[...document.querySelectorAll('[data-contact-id]')];
  return rows.length;
}
```

Note : si `data-contact-id` n'existe pas dans le DOM, compter via le state React n'est pas
possible depuis la console. Fallback : comparer le compteur « N contacts » affiché à côté
des filtres avant / après le fix. Relever le nombre AVANT et le noter ici : `______`

- [ ] **Step 2 : corriger `TabProspects` (ligne 2625)**

Avant :
```js
if(!filterMine&&filterAgence&&c.agence!==filterAgence) return false;
```
Après :
```js
if(!filterMine&&filterAgence&&c.agence!==filterAgence&&c.responsable!==profile.nom) return false;
```

- [ ] **Step 3 : corriger `TabPipe` (ligne 5035)**

Avant :
```js
if(filterAgence&&b.agence!==filterAgence) return false;
```
Après :
```js
if(filterAgence&&b.agence!==filterAgence&&b.responsable!==profile.nom) return false;
```

- [ ] **Step 4 : vérifier que la page compile toujours**

Recharger `http://localhost:8899/index.html`, puis :
```js
() => ({ blanc: document.body.innerText.trim().length < 50 })
```
Attendu : `{blanc: false}`. Et zéro `SyntaxError` dans la console (le message Babel
« deoptimised the styling … exceeds the max of 500KB » est normal, ce n'est pas une erreur).

- [ ] **Step 5 : vérifier le gain, chiffré**

Le compteur de l'onglet Prospects filtré sur Paris doit avoir **augmenté**. Le nombre
attendu dépend du profil connecté :
- en Nicolas (Lyon), filtre Paris → +9 contacts (les 9 fiches Nicolas en agence Paris)
- en Camille (Paris), filtre Paris → +57 (ses fiches en agence Lyon)

Assertion de non-régression, à faire en Nicolas avec filtre agence = Lyon : aucun contact
dont `agence` ≠ Lyon **et** `responsable` ≠ Nicolas Serradeil ne doit apparaître.

- [ ] **Step 6 : commit**

```bash
git add index.html
git commit -m "fix(visibilite): un objet reste visible a son responsable meme hors de son agence

Les onglets Prospects (2625) et Pipe (5035) filtraient sur la seule agence, sans
la clause '|| responsable === moi' que Besoins (4714) et Missions (5538) avaient
deja. Consequence : 110 contacts et 7 besoins etaient invisibles a leur propre
responsable (57 fiches de Camille en agence Lyon, 29 d'Anne-Claire, 9 de Nicolas
en agence Paris)."
```

---

## Task 2 : Chantier B — élargir la liste des responsables proposés

**Files :** Modify `index.html:2591`, `index.html:4702`, `index.html:4978`, `index.html:5514`

**Interfaces :**
- Consomme : `allProfiles`, `commerciauxParAgence`, `filterAgence`, et la liste d'objets
  affichée par l'onglet (`contacts` / `besoins` / `missions`)
- Produit : `responsablesVisibles` — mêmes noms de variable, même type (`string[]` trié)

- [ ] **Step 1 : écrire le helper, une seule fois, près de `respOptions` (ligne 1097)**

```js
// Responsables proposés au filtre : les commerciaux de l'agence filtrée, PLUS tout
// responsable ayant au moins un objet visible dans la vue courante. Sans ce second
// terme, un commercial voit ses objets hors-agence dans la liste mais ne peut pas
// filtrer dessus (le nom du collegue n'est pas propose).
function respFilterOptions({ allProfiles, commerciauxParAgence, agence, objets, isAdmin }) {
  if (isAdmin && !agence) return [...new Set((allProfiles||[]).map(p=>p.nom).filter(Boolean))].sort();
  const base = (agence && commerciauxParAgence ? (commerciauxParAgence[agence]||[]) : []);
  const presents = [...new Set((objets||[]).map(o=>o.responsable).filter(Boolean))];
  return [...new Set([...base, ...presents])].sort();
}
```

- [ ] **Step 2 : brancher sur `TabBesoins` (ligne 4702-4706)**

Avant :
```js
const responsablesVisibles=useMemo(()=>{
  if(isAdmin&&!filterAgence) return [...new Set(allProfiles.map(p=>p.nom).filter(Boolean))].sort();
  const ag=filterAgence||profile.agence;
  return commerciauxParAgence[ag]||[];
},[isAdmin,filterAgence,profile.agence,allProfiles,commerciauxParAgence]);
```
Après :
```js
const responsablesVisibles=useMemo(()=>respFilterOptions({
  allProfiles, commerciauxParAgence, agence: filterAgence||profile.agence,
  objets: sorted, isAdmin,
}),[isAdmin,filterAgence,profile.agence,allProfiles,commerciauxParAgence,sorted]);
```

⚠️ `sorted` est défini APRÈS `responsablesVisibles` dans le fichier (ligne 4708). Il faut
donc **déplacer le bloc `responsablesVisibles` après `sorted`**, sinon `ReferenceError` au
rendu. Vérifier la même chose sur les 3 autres sites avant de brancher.

- [ ] **Step 3 : brancher les 3 autres sites**

Appliquer le même remplacement lignes 2591 (`TabProspects`, objets = la liste de contacts
filtrée), 4978 (`TabPipe`, objets = besoins filtrés) et 5514 (`TabMissions`, objets =
missions filtrées). Reprendre à chaque fois le nom de la variable de liste locale du
composant — ce n'est pas toujours `sorted`, le vérifier par lecture avant d'éditer.

- [ ] **Step 4 : vérifier**

Recharger, puis sur l'onglet Besoins avec filtre agence = Lyon :
```js
() => {
  const s=[...document.querySelectorAll('select')].find(x=>[...x.options].some(o=>/Tous les responsables/.test(o.textContent)));
  return s ? [...s.options].map(o=>o.textContent) : 'filtre absent';
}
```
Attendu : la liste contient les commerciaux Lyon **et** tout responsable d'un besoin lyonnais
(donc `Louis Py`, qui a 3 besoins en agence Lyon alors qu'il est à Paris).
Attendu aussi : pas de doublon dans les options, liste triée.

- [ ] **Step 5 : commit**

```bash
git add index.html
git commit -m "feat(filtres): proposer aussi les responsables ayant un objet visible hors agence"
```

---

## Task 3 : Chantier A — dédoubler le gate en canEdit / canDelete

**Files :** Modify `index.html` lignes 1799 · 1821-1824 · 2414 · 2448-2452 · 2931 · 3034-3036 ·
3362 · 3421-3426 · 3508-3512 · 3551 · 4258 · 4403-4409 · 4421

**Interfaces :**
- Consomme : `profile.role`, `profile.nom`, `isAdmin`, l'objet du panneau
- Produit : dans chaque panneau, deux booléens au lieu d'un — `canEdit` (ouvert à tous les
  commerciaux) et `canDelete` (admin ou responsable). Les noms sont identiques dans les 5
  panneaux pour qu'un futur lecteur n'ait pas à réapprendre la convention.

⚠️ **Le piège de cette tâche** : `isOwner`/`canEdit` gardent aujourd'hui Modifier **et**
Supprimer dans le même fragment JSX (`{isOwner && <>…</>}`). Élargir la condition existante
ouvrirait la suppression à tous. Il faut donc découper le fragment, pas changer le test.

- [ ] **Step 1 : Contact (1799) — définir les deux booléens**

Avant :
```js
const isOwner = profile.role==='admin' || contact.responsable===profile.nom || profile.role==='partner';
```
Après :
```js
// canEdit : ouvert a tous les commerciaux (le partner garde son perimetre, verrouille en base)
const canEdit  = profile.role==='admin' || profile.role==='commercial' || profile.role==='partner';
const canDelete= profile.role==='admin' || contact.responsable===profile.nom;
```

- [ ] **Step 2 : Contact (1821-1824) — découper le fragment**

Avant :
```js
{isOwner && <>
  <BtnAction variant="edit" icon={ICONS.edit} label="Modifier" onClick={()=>setModal('edit')}/>
  {profile.role!=='partner'&&(modal!=='confirmDel'
    ? <BtnAction variant="danger" icon={ICONS.delete} label="Supprimer" onClick={()=>setModal('confirmDel')}/>
```
Après :
```js
{canEdit && <BtnAction variant="edit" icon={ICONS.edit} label="Modifier" onClick={()=>setModal('edit')}/>}
{canDelete && <>
  {profile.role!=='partner'&&(modal!=='confirmDel'
    ? <BtnAction variant="danger" icon={ICONS.delete} label="Supprimer" onClick={()=>setModal('confirmDel')}/>
```
Le reste du fragment (fermeture, `ConfirmDelete`) suit `canDelete`. Relire les 25 lignes
autour avant d'éditer : la structure JSX est imbriquée, un `</>` mal placé = écran blanc.

Le bouton « Lever le flag » (ligne 1841) passe de `isOwner` à `canEdit` — lever un flag
NPC est une modification, pas une suppression.

- [ ] **Step 3 : Compte (2931 + 3034-3036)**

Ce panneau **sépare déjà** Modifier et Supprimer (`Modifier`→`isOwner`, `Supprimer`→`isAdmin`).
Il suffit donc de renommer et d'élargir :
```js
const canEdit = isAdmin || profile?.role==='commercial';
```
et remplacer `{isOwner&&<BtnAction … label="Modifier" …/>}` par `{canEdit&&…}`, ainsi que
le `{(isOwner||isAdmin)&&<div …>}` englobant par `{(canEdit||isAdmin)&&<div …>}`.
`Supprimer` reste sur `isAdmin` : ne pas y toucher.

- [ ] **Step 4 : Besoin (4258 + 4403-4409 + 4421)**

```js
const canEdit  = isAdmin || profile.role==='commercial';
const canDelete= isAdmin || besoin.responsable===profile.nom;
```
`Modifier`/`Annuler` → `canEdit`. Le bloc `Supprimer`/`ConfirmDelete` → `canDelete`.
`BesoinStatusStepper2` (4421) → `canEdit` (changer le statut d'un besoin est une
modification, et c'est précisément ce qu'on veut permettre à un collègue sur place).

- [ ] **Step 5 : Mission (2414 + 2448-2452 + 2503)**

```js
const canEdit  = isAdmin || profile.role==='commercial' || profile.role==='partner';
const canDelete= isAdmin || mission.responsable===profile.nom;
```
`Modifier` → `canEdit`. `EditableJoursGrid` (2503) → `canEdit`. Le bloc `Supprimer` → `canDelete`.

⚠️ **Décision à confirmer avec Nicolas** : le bouton `Terminer` (2451) passe-t-il en
`canEdit` ? Terminer la mission d'un collègue est un acte lourd. Défaut retenu ici :
`canEdit` (c'est un changement de statut, cohérent avec « tout modifier »). Si Nicolas
préfère, le basculer sur `canDelete`.

- [ ] **Step 6 : Tâche (3362 + 3551 + 3421-3426 + 3508-3512)**

Deux sites définissent `canEdit` pour les tâches (carte compacte et panneau détail) :
```js
const canEdit  = isAdmin || profile.role==='commercial' || profile.role==='partner';
const canDelete= isAdmin || t.responsable===profile.nom;
```
`Fait` et `Modifier` → `canEdit`. `Supprimer` → `canDelete`, aux deux endroits
(le panneau 3421-3426 et les petits boutons de la carte 3508-3512).

⚠️ Même question que Step 5 pour `Fait` : clore la tâche d'un collègue. Défaut : `canEdit`.

- [ ] **Step 7 : verrouiller le champ `responsable` dans les formulaires d'édition**

Le `responsable` ne doit être modifiable que par le propriétaire ou l'admin (sinon on se
vole les comptes). Sites concernés : `ContactEditModal` (1288), `MissionFormModal` (2065),
`CompteFormModal` (1761), `AddTacheModal` (1647), et le formulaire d'édition de besoin.
Remplacer le gate `isAdmin` / `canEditAgence` de ce champ précis par :
```js
const canReassign = isAdmin || objet.responsable === profile.nom;
```
et afficher le `<select>` si `canReassign`, sinon le nom en texte simple.

- [ ] **Step 8 : vérifier au navigateur, profil par profil**

La page charge (pas d'écran blanc), puis pour un contact dont Nicolas n'est PAS responsable :
```js
() => {
  const t=document.body.innerText;
  return { modifier: t.includes('Modifier'), supprimer: t.includes('Supprimer') };
}
```
Attendu en tant que **commercial non responsable** : `{modifier:true, supprimer:false}`.
Nicolas étant admin, ce test exige un profil commercial — à faire avec un compte de test
ou en forçant temporairement `profile.role` en console. Le noter honnêtement si non testé.

- [ ] **Step 9 : commit**

```bash
git add index.html
git commit -m "feat(perms): tout commercial peut modifier, seul le responsable peut supprimer

isOwner/canEdit gardaient Modifier ET Supprimer dans le meme fragment JSX : la
notion est dedoublee en canEdit (ouvert aux commerciaux) et canDelete (admin ou
responsable) dans les 5 panneaux. Le champ responsable reste reserve au
proprietaire. Le perimetre du role partner est inchange."
```

---

## Task 4 : Chantier A — la trace automatique des modifications

**Files :** Modify `index.html` (nouveau helper près de `respOptions` ligne 1097, + appel
dans les 5 handlers de sauvegarde)

**Interfaces :**
- Consomme : `sb` (client Supabase global), `profile.nom`, `getToday()`
- Produit : `logEdits(type, objet, avant, apres, profile)` → `Promise<void>`. Écrit dans
  `historique_actions` (colonnes : `id_prospect`, `date`, `type_action`, `details`,
  `responsable`). N'écrit rien si l'auteur est le responsable de l'objet.

- [ ] **Step 1 : écrire le helper**

```js
// Trace les modifications faites par un NON-responsable, pour que le proprietaire
// de la fiche retrouve qui a touche quoi. Silencieux quand le responsable travaille
// sur ses propres fiches (sinon l'historique devient illisible).
const CHAMPS_TRACES = {
  contact: ['prenom','nom','groupe','ville','role','telephone','email','linkedin','statut','cjm'],
  compte:  ['nom','secteur','ville','statut','site_web'],
  besoin:  ['titre','statut','compte','budget','tjm_vente','cjm_achat','date_demarrage','date_fin'],
  mission: ['client','statut','date_debut_mission','date_fin_mission','tjm_vente','cjm_achat'],
  tache:   ['titre','statut','due_date','notes'],
};

async function logEdits(type, objet, avant, apres, profile) {
  if (!objet || objet.responsable === profile.nom) return;   // le proprietaire : pas de bruit
  const champs = CHAMPS_TRACES[type] || [];
  const diffs = champs
    .filter(k => (avant?.[k] ?? null) !== (apres?.[k] ?? null))
    .map(k => `${k} : ${avant?.[k] ?? '(vide)'} → ${apres?.[k] ?? '(vide)'}`);
  if (!diffs.length) return;
  const contactId = type === 'contact' ? objet.id : (objet.contact_id ?? null);
  if (!contactId) return;   // historique_actions est rattache a un contact
  await sb.from('historique_actions').insert(diffs.map(d => ({
    id_prospect: contactId,
    date: getToday(),
    type_action: 'Note interne',
    details: `${profile.nom} a modifié ${type} : ${d}`,
    responsable: profile.nom,
  })));
}
```

⚠️ Limite assumée : `historique_actions.id_prospect` rattache la ligne à un **contact**.
Un compte ou une mission sans `contact_id` ne peut donc pas être tracé par ce mécanisme.
À constater à l'exécution : si le trou est gênant, il faudra une colonne polymorphe — mais
c'est un chantier à part, pas à glisser ici (YAGNI tant que Nicolas ne l'a pas demandé).

- [ ] **Step 2 : appeler depuis le handler de sauvegarde du contact**

Dans `ContactEditModal`, capturer l'état avant édition (`const avant = {...contact}` au
montage) et après le `sb.from('contacts').update(...)` réussi :
```js
await logEdits('contact', contact, avant, f, profile);
```

- [ ] **Step 3 : idem pour compte, besoin, mission, tâche**

Même schéma dans les 4 autres formulaires. Le `type` passé doit correspondre exactement à
une clé de `CHAMPS_TRACES` (`'compte'`, `'besoin'`, `'mission'`, `'tache'`) — une clé
inconnue fait silencieusement zéro trace, donc vérifier l'orthographe.

- [ ] **Step 4 : vérifier en base**

Modifier le téléphone d'un contact dont on n'est pas responsable, puis :
```bash
# doit renvoyer la ligne fraiche
python3 -c "
import json,urllib.request
U='https://ehfseahxoivfhmpiyoqa.supabase.co';K='sb_publishable_BaNIdlZ09xavRRhG0G-ScQ_mW4hVueJ'
# (reutiliser le helper d'audit du scratchpad pour le token)
"
```
Attendu : une ligne `Note interne` dont `details` commence par « … a modifié contact :
telephone : … → … ». Puis modifier une de SES propres fiches → **aucune** nouvelle ligne.

- [ ] **Step 5 : commit**

```bash
git add index.html
git commit -m "feat(perms): tracer dans l'historique les modifications faites par un non-responsable"
```

---

## Task 5 : recette complète et mise en prod

- [ ] **Step 1 : dérouler la recette de la spec**

Les 6 points du chantier A et les 3 du chantier B, section « Recette » de
`SPEC_droits_ecriture_et_visibilite_inter_agences.md`. Noter ce qui n'a pas pu être testé
faute de profil commercial sous la main — ne pas le présenter comme vérifié.

- [ ] **Step 2 : contrôle anti-régression sur le rôle partner**

Se connecter en Maria-José (ou forcer `profile.role='partner'`) et vérifier qu'aucun bouton
nouveau n'apparaît, et que son périmètre de consultants est identique à avant.

- [ ] **Step 3 : OK Nicolas, puis push**

```bash
git push origin main
```
Puis confirmer la propagation GitHub Pages avant d'annoncer la mise en ligne.

- [ ] **Step 4 : reboucler les traces**

Mettre à jour `journal/AAAA-MM-JJ.md` et passer les lignes du backlog en `[✅ FAIT]`.
