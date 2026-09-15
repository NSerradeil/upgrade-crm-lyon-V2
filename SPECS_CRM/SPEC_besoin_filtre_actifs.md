# SPEC — Filtre "Actifs" sur l'onglet Besoins
**CRM Upgrade Lyon V2** · Évolution mineure
**Auteur :** Nicolas Serradeil + Claude
**Date :** 04/05/2026

---

## Besoin

> "Dans l'onglet Besoins, on voit aussi les besoins perdus, c'est relou. J'aimerais un filtre 'Actifs' qui les masque par défaut, comme sur l'onglet Pipe."

Au quotidien, le commercial bosse sur ses besoins en cours (opportunités, push, ouverts, entretiens, gagnés récents). Les besoins perdus sont du bruit visuel dans la liste — on doit pouvoir les masquer en un clic, et idéalement par défaut.

---

## État actuel

Pills de filtre statut sur l'onglet Besoins (vue Liste) :

```
[ TOUS ] [ OPPORTUNITÉ ] [ PUSH ] [ OUVERT ] [ PROFIL PROPOSÉ ] [ ENTRETIEN PROG. ] [ ENTRETIEN PASSÉ ] [ GAGNÉ ] [ PERDU ]
```

- `filterStatut` initial = `''` → pill TOUS actif → on voit **tous** les besoins, perdus inclus
- Pas d'option intermédiaire pour "tout sauf perdus"

## État cible

```
[ ACTIFS ] [ TOUS ] [ OPPORTUNITÉ ] [ PUSH ] [ OUVERT ] [ PROFIL PROPOSÉ ] [ ENTRETIEN PROG. ] [ ENTRETIEN PASSÉ ] [ GAGNÉ ] [ PERDU ]
```

- Nouveau pill **ACTIFS** en 1ʳᵉ position
- **ACTIFS** = sélectionné par défaut au chargement de l'onglet
- **TOUS** reste disponible en 2ᵉ position (échappatoire pour vraiment tout voir)
- Comportement radio identique (un seul pill actif à la fois)

---

## Définition de "Actif"

Un besoin est **actif** si son `statut` est différent de `'Besoin Perdu'`.

| Statut | Actif ? |
|---|---|
| Opportunité | ✅ |
| Push opportuniste | ✅ |
| Besoin ouvert | ✅ |
| Profil proposé | ✅ |
| Entretien programmé | ✅ |
| Entretien passé | ✅ |
| Besoin Gagné | ✅ |
| Besoin Perdu | ❌ |

**Cohérence avec l'existant** : cette définition est déjà utilisée dans le code à la ligne `1692` (`availableBesoins`), qui filtre `b.statut !== 'Besoin Perdu'` pour les pickers. On réutilise la même règle.

---

## Comportement

### Compteur sous les pills

Le label se met à jour selon le pill actif :

| Pill actif | Affichage |
|---|---|
| ACTIFS | "X besoin(s) actif(s)" |
| TOUS | "X besoin(s)" *(comme aujourd'hui)* |
| OPPORTUNITÉ, PUSH, OUVERT, … | "X besoin(s)" *(comme aujourd'hui)* |
| PERDU | "X besoin(s) perdu(s)" |

### Sections groupées par statut

- En mode **ACTIFS** : on itère sur `BESOIN_STATUTS_ORDRE` **moins** `'Besoin Perdu'` → la section "Besoin Perdu" n'apparaît plus
- En mode **TOUS** ou autre statut spécifique : comportement actuel inchangé

### Combinaison avec les autres filtres

Le pill ACTIFS se combine **par défaut** avec :
- la **recherche** (search input)
- le filtre **AGENCE** (admin uniquement)
- le filtre **RESPONSABLE**

Logique : ACTIFS exclut juste les perdus, les autres filtres font leur boulot par-dessus.

### Vue Kanban — INTOUCHÉE

Cette spec ne concerne **que la vue Liste**. La vue Kanban (`viewMode === 'kanban'`) doit avoir un comportement **strictement identique à aujourd'hui** :

- Le pill ACTIFS n'est **pas pris en compte** par le Kanban
- La colonne "Besoin Perdu" continue d'apparaître dans le Kanban comme aujourd'hui
- Si l'utilisateur a un filtre statut spécifique actif (ex: PUSH), le Kanban applique bien ce filtre — comportement actuel inchangé
- Seul l'effet "ACTIFS = masquer perdus" est neutralisé en mode Kanban

**Implémentation** : voir section "Implémentation Claude Code" ci-dessous — on isole le filtre ACTIFS dans une dérivation `sortedList` qui n'est utilisée que pour la vue Liste. Le composant `KanbanBesoins` continue de recevoir `sorted` (sans ACTIFS appliqué).

### Réinitialisation des filtres (bouton ✕)

Le bouton ✕ "reset filtres" remet l'état initial : `filterStatut = 'ACTIFS'` (et non `''` comme aujourd'hui), search = '', filterResp = '', filterAgence = défaut admin/non-admin.

> **Détail UX** : la condition `hasFilter` (qui contrôle l'affichage du bouton ✕) doit considérer `filterStatut === 'ACTIFS'` comme l'état "neutre" — sinon le bouton ✕ s'afficherait en permanence dès l'ouverture de l'onglet.

---

## Implémentation Claude Code

### Fichier concerné

`index.html` — fonction `TabBesoins` (à partir de la ligne 3884).

### Constante sentinel

Introduire une constante en début de fichier (à côté de `BESOIN_STATUTS_ORDRE`, ligne ~205) :

```js
const BESOIN_FILTER_ACTIFS = 'ACTIFS';  // sentinel — distinct des valeurs réelles de statut
```

### Modification du state initial (ligne 3885)

```js
// AVANT
const [filterStatut,setFilterStatut]=useState('');

// APRÈS
const [filterStatut,setFilterStatut]=useState(BESOIN_FILTER_ACTIFS);
```

### Modification du filtre `sorted` (ligne 3905-3917)

**Principe** : `sorted` reste la source unique consommée par le Kanban. Il ignore donc le sentinel ACTIFS (= traite ACTIFS comme TOUS pour le statut). Une dérivation `sortedList` applique le filtre ACTIFS uniquement pour la vue Liste.

```js
// AVANT
.filter(b=>{
  if(filterStatut&&b.statut!==filterStatut) return false;
  ...
})

// APRÈS — `sorted` ignore le sentinel ACTIFS pour préserver la vue Kanban
.filter(b=>{
  if(filterStatut && filterStatut!==BESOIN_FILTER_ACTIFS && b.statut!==filterStatut) return false;
  ...
})
```

### Ajout d'une dérivation `sortedList` (juste après `sorted`)

```js
// Vue Liste uniquement : applique le filtre ACTIFS par-dessus `sorted`
const sortedList = useMemo(()=>{
  if(filterStatut===BESOIN_FILTER_ACTIFS) return sorted.filter(b=>b.statut!=='Besoin Perdu');
  return sorted;
},[sorted,filterStatut]);
```

**Conséquence** : tous les usages "Liste" doivent passer de `sorted` → `sortedList` (compteur, sections groupées). L'usage Kanban ligne 4035 reste sur `sorted`.

### Modification de la liste de pills `STATUT_BTNS` (ligne 3924)

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

### Style du pill ACTIFS

Pas de couleur dédiée dans `BESOIN_BADGE_COLORS_GLOBAL` (vu que ce n'est pas un statut réel). Quand actif, fallback sur le style "actif neutre" déjà utilisé pour TOUS :

```js
style={active&&bc?{backgroundColor:bc.bg,color:bc.color}:active?{backgroundColor:'#1C1F35',color:'#fff'}:{}}
```

→ La condition `bc` est `null` pour TOUS et ACTIFS (puisque `btn.value` n'est pas dans `BESOIN_BADGE_COLORS_GLOBAL`) → on retombe sur le style noir/blanc actuel de TOUS. **Aucune modif de style nécessaire**.

### Modification du compteur (ligne 3976) — utilise `sortedList`

```js
// AVANT
<div className="text-xs text-neutral-300 mb-3">{sorted.length} besoin{sorted.length>1?'s':''}</div>

// APRÈS
<div className="text-xs text-neutral-300 mb-3">
  {sortedList.length} besoin{sortedList.length>1?'s':''}
  {filterStatut===BESOIN_FILTER_ACTIFS?' actif'+(sortedList.length>1?'s':''):''}
  {filterStatut==='Besoin Perdu'?' perdu'+(sortedList.length>1?'s':''):''}
</div>
```

### Modification du grouping par statut (ligne 3978) — utilise `sortedList`

```js
// AVANT
{(filterStatut?[filterStatut]:BESOIN_STATUTS_ORDRE).map(statut=>{
  const items=sorted.filter(b=>b.statut===statut);
  ...
})}

// APRÈS
{(
  filterStatut===BESOIN_FILTER_ACTIFS
    ? BESOIN_STATUTS_ORDRE.filter(s=>s!=='Besoin Perdu')
  : filterStatut
    ? [filterStatut]
    : BESOIN_STATUTS_ORDRE
).map(statut=>{
  const items=sortedList.filter(b=>b.statut===statut);
  ...
})}
```

### Vue Kanban (ligne 4035) — INCHANGÉE

```js
// Reste tel quel — passe `sorted` (sans le filtre ACTIFS appliqué)
<KanbanBesoins besoins={sorted} ... />
```

### Modification de `hasFilter` et `resetAll` (lignes 3921-3922)

```js
// AVANT
const hasFilter=search||filterStatut||filterResp||(isAdmin?filterAgence!=='':filterAgence!==profile.agence);
const resetAll=()=>{setSearch('');setFilterStatut('');setFilterResp('');setFilterAgence(isAdmin?'':profile.agence);};

// APRÈS
const hasFilter=search||(filterStatut&&filterStatut!==BESOIN_FILTER_ACTIFS)||filterResp||(isAdmin?filterAgence!=='':filterAgence!==profile.agence);
const resetAll=()=>{setSearch('');setFilterStatut(BESOIN_FILTER_ACTIFS);setFilterResp('');setFilterAgence(isAdmin?'':profile.agence);};
```

---

## Hors scope (YAGNI)

- ❌ **Persistance par utilisateur** (localStorage / `prefs`) : non nécessaire pour cette V1. ACTIFS étant le défaut, l'utilisateur ne perd pas son réflexe à chaque session.
- ❌ **Filtre ACTIFS sur le Kanban** : la vue Kanban affiche déjà les colonnes par statut, l'utilisateur peut juste ignorer la colonne Perdu.
- ❌ **Toggle indépendant "masquer perdus"** : empile un nouveau pattern UI alors que les pills font le job. Garder une seule mécanique de filtre.
- ❌ **Filtre "Actifs" sur d'autres onglets** : si besoin remonte plus tard, on en fera une spec dédiée.

---

## Risques / non-régression

| Risque | Mitigation |
|---|---|
| User habitué à voir TOUS par défaut → surpris | Pill TOUS reste 2ᵉ position, friction = 1 clic |
| Lien externe / deep-link vers l'onglet Besoins → comportement change | À vérifier : si `navBesoinId` est défini au chargement, ne pas appliquer ACTIFS par défaut (cas où le besoin pointé est Perdu) |
| Régression sur la vue Kanban | Aucune modif sur Kanban — seulement le filtre `sorted` partagé. Si Kanban consomme `sorted`, vérifier que ACTIFS ne masque pas un besoin attendu en colonne Perdu |
| Bug si `filterStatut === 'ACTIFS'` se retrouve dans l'URL ou state externe | La constante sentinel `'ACTIFS'` ne collisionne avec aucune valeur de statut réelle (qui sont en français avec accents) |

### Vérification Kanban — RÉSOLUE

Le composant `KanbanBesoins` consomme `sorted` (ligne 4035). La conception `sorted` (ignore ACTIFS) + `sortedList` (applique ACTIFS) garantit que :
- Le Kanban reçoit `sorted` → les colonnes restent inchangées par le pill ACTIFS
- La vue Liste utilise `sortedList` → ACTIFS masque bien les perdus

→ **Aucune surprise sur Kanban**. Conforme à la consigne "on touche pas la vue Kanban".

---

## Acceptance criteria

- [ ] Le pill **ACTIFS** s'affiche en 1ʳᵉ position dans la barre de filtres statut
- [ ] **ACTIFS** est sélectionné par défaut à l'ouverture de l'onglet Besoins
- [ ] Cliquer sur ACTIFS masque tous les besoins de statut "Besoin Perdu"
- [ ] Cliquer sur TOUS réaffiche les besoins perdus (comportement d'origine)
- [ ] Le compteur affiche "X besoin(s) actif(s)" quand ACTIFS est actif
- [ ] Le compteur affiche "X besoin(s) perdu(s)" quand PERDU est actif
- [ ] La section "Besoin Perdu" n'apparaît plus dans la liste groupée quand ACTIFS est actif
- [ ] Le bouton ✕ "reset filtres" remet ACTIFS comme état neutre (et non TOUS)
- [ ] Le bouton ✕ ne s'affiche pas tant que seul ACTIFS est actif (pas de "filtre" perçu)
- [ ] Combinaison ACTIFS + recherche + filtre AGENCE/RESPONSABLE fonctionne correctement
- [ ] Vue Kanban : comportement strictement identique à aujourd'hui (la colonne Besoin Perdu apparaît toujours, ACTIFS n'a aucun effet visuel sur Kanban)
- [ ] Aucune régression sur les autres onglets (Pipe, Contacts, TDB, Historique, Tâches)
- [ ] Babel parse sans erreur (vérification après modif `index.html`)
