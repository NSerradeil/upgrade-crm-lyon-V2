# SPEC — Droits d'écriture élargis + visibilité inter-agences
**CRM Upgrade Lyon V2** · 27/07/2026 · validé par Nicolas en brainstorming

Deux chantiers distincts mais qui répondent au même besoin : **arrêter de bloquer un
commercial sur un objet qui le concerne**. Aucune migration de base : les policies RLS
ne restreignent que le rôle `partner`, les commerciaux ont déjà l'écriture ouverte au
niveau DB. Tout se joue dans `index.html`.

---

## Chantier A — Écriture ouverte à tous les commerciaux

### Règle
Tout commercial peut **modifier tous les champs** de n'importe quel contact, compte,
besoin, mission ou tâche, et y **ajouter notes, actions et tâches**, qu'il en soit
responsable ou non.

Restent réservés au responsable (ou à l'admin) :
- **Supprimer**
- **Changer le `responsable`** de la fiche (sinon on se vole les comptes entre commerciaux)

Le rôle `partner` (Maria-José) n'est **pas** élargi : son périmètre reste sa liste de
consultants, verrouillé en dur par les policies `*_partner_*` en base.

### Le problème de code à régler d'abord
Les 5 panneaux calculent une variable unique qui garde **Modifier ET Supprimer ensemble** :

| Objet | ligne | variable actuelle |
|---|---|---|
| Contact | 1799 | `isOwner` |
| Compte | 2931 | `isOwner` |
| Besoin | 4258 | `isOwner` |
| Mission | 2414 | `canEdit` |
| Tâche | 3362 / 3551 | `canEdit` |

Il faut **dédoubler la notion**, pas élargir la condition existante — sinon ouvrir
l'édition ouvre aussi la suppression :

```js
const canEdit   = profile.role !== 'partner' || <périmètre partner inchangé>
const canDelete = isAdmin || objet.responsable === profile.nom
```

Puis répartir les boutons : `Modifier` → `canEdit` · `Supprimer` → `canDelete` ·
le champ `responsable` du formulaire d'édition → `canDelete` (même exigence de propriété).

### Traçabilité
Un helper unique appelé au save :

```js
async function logEdits(type, objet, avant, apres)
```

Il compare champ par champ et n'écrit **que si l'auteur n'est pas le responsable** —
pas de bruit quand le responsable travaille sur ses propres fiches. Une ligne par champ
modifié dans `historique_actions` :

> « Camille Salinson a modifié Téléphone : 06.12… → 07.45… »

Réutilise la table et le fil d'historique qui existent déjà : zéro nouvelle table,
zéro nouvel écran. Pas de notification au responsable (écarté : risque de spam à 5
commerciaux qui s'enrichissent mutuellement).

---

## Chantier B — Visibilité inter-agences

### Le besoin
Un objet doit être visible par **son responsable** ET par **les commerciaux de l'agence
de l'objet**. Exemple de Nicolas : un besoin à Lyon dont le responsable est un Parisien
doit apparaître chez le Parisien (il en est responsable) *et* chez le Lyonnais (c'est sa
région).

### État des lieux — la règle existe déjà à 2 endroits sur 4
Les onglets **Besoins** et **Missions** appliquent déjà l'union. Les 2 autres ont oublié
la clause `|| responsable === moi` :

| Onglet | ligne | état | fiches invisibles à leur propre responsable |
|---|---|---|---|
| Besoins | 4714 | ✅ union OK | — |
| Missions | 5538 | ✅ union OK | — |
| **Prospects** (contacts) | **2625** | 🔴 clause manquante | **110** |
| **Pipe** (besoins) | **5035** | 🔴 clause manquante | **7** |

Détail des 110 contacts invisibles : 57 de Camille en agence Lyon · 29 d'Anne-Claire en
agence Lyon · 9 d'Anne-Claire en agence Nantes · 9 de Nicolas en agence Paris · 5 d'Amel
en agence Lyon · 1 de Nicolas en agence Bordeaux.

### Correctif
Aligner les 2 lignes fautives sur ce que font déjà les 2 autres :

```js
// ligne 2625 — TabProspects
if(!filterMine && filterAgence && c.agence!==filterAgence && c.responsable!==profile.nom) return false;

// ligne 5035 — TabPipe
if(filterAgence && b.agence!==filterAgence && b.responsable!==profile.nom) return false;
```

### Sélecteur de responsable (validé par Nicolas)
`responsablesVisibles` (ligne 4702, et ses équivalents 2591 / 4692 / 4978 / 5514) ne
propose que les commerciaux **de l'agence filtrée**. Conséquence : en filtrant sur Lyon,
Camille voit bien ses besoins lyonnais dans la liste mais ne peut pas *filtrer* sur
« Nicolas ». → **élargir la liste aux commerciaux de l'agence filtrée PLUS tout
responsable ayant au moins un objet visible dans la vue courante.**

### Hors périmètre (décision Nicolas)
Les 110 contacts et 7 besoins dont l'`agence` diffère de celle du responsable ne sont
**pas** re-qualifiés. Certains sont volontaires (un commercial qui suit un compte hors
de sa région), et l'objectif est qu'on les voie, pas qu'on les déplace. On corrige
l'affichage, on ne touche pas à la donnée.

---

## Recette

**Chantier A** — avec un profil commercial non-admin (pas Nicolas) :
1. Ouvrir un contact dont on n'est pas responsable → `Modifier` visible, `Supprimer` absent.
2. Modifier le téléphone → sauvegarde OK, et une ligne apparaît dans l'historique de la fiche.
3. Le champ `responsable` du formulaire est en lecture seule.
4. Idem sur compte, besoin, mission, tâche.
5. Modifier une de SES propres fiches → **aucune** ligne d'historique parasite.
6. Profil `partner` (Maria-José) : périmètre inchangé, aucun accès élargi.

**Chantier B** :
1. Se connecter en Camille (agence Paris, filtre agence = Paris) → ses 57 contacts en
   agence Lyon apparaissent dans l'onglet Prospects.
2. Filtrer l'agence sur Lyon en étant Camille → ses besoins lyonnais restent visibles,
   et « Nicolas » est proposé dans le sélecteur de responsable.
3. Vérifier qu'aucun commercial ne voit un objet ni à lui ni de son agence.

**Non négociable avant push** : validation en local (serveur + parcours réel) puis OK
Nicolas. La prod est GitHub Pages, il n'y a pas de staging.
