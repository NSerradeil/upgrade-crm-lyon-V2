# SPEC — Refonte du suivi de l'intercontrat
**CRM Upgrade Lyon V2** · Évolution modèle de données + UX saisie + MCP + carte data interco
**Auteur :** Nicolas Serradeil + Jules/Claude (PM + Lead Tech)
**Date :** 27/06/2026

---

## Besoin exprimé

> "Aujourd'hui on suit l'intercontrat en créant une *mission intercontrat* par consultant. Ça alimente la carte data interco (nb d'inter, taux mensuel / trimestre / YTD, seuils 5 et 8, par France / commercial / agence). Mais c'est lourd, et on doit laisser les missions inter ouvertes pour ne pas perdre les imputations. Je veux simplifier et améliorer."

---

## Diagnostic du modèle actuel

L'interco est portée par un objet **mission** (`statut='Intercontrat'`) avec les colonnes `jours_<mois>`.

Calcul actuel de la carte (extrait `index.html`) :
- dénominateur = nb de **missions** CDI actives dans le mois (`type_contrat='CDI'` ou statut interco) × constante `18,16` j ouvrés ;
- numérateur = somme des `jours_<mois>` des missions interco ;
- taux mensuel = jours interco ÷ (nb CDI × 18,16) ; YTD lissé ; seuils `≥5` (Attention) et `≥8` (MALUS).

### Deux douleurs (exprimées)
1. **Création + maintenance manuelle** d'une mission fictive par consultant en interco.
2. **Obligation de laisser la mission ouverte** sinon on perd la possibilité d'imputer les jours → missions fantômes qui polluent le pipeline et faussent CA/marge.

### Deux bugs de calcul (constatés)
1. Le dénominateur compte des **missions CDI**, pas des **consultants uniques** → un CDI avec 2 missions le même mois est compté 2× → taux faussé.
2. La constante `18,16` au dénominateur ≠ jours ouvrés **réels** du mois → un « 100% interco » ne tombe pas pile à 100%.

### Cause racine
On détourne l'objet *mission* (qui a un client, un CA, une marge) pour ce qui est en réalité une **période d'intercontrat** rattachée à un consultant. D'où tous les contournements.

---

## Décision : approche retenue

**Découpler l'interco de la mission.** L'interco devient un objet propre rattaché au **contact « Consultant CDI »** (référentiel effectif qui existe déjà, avec CJM). Plus de mission fictive à ouvrir/fermer/maintenir.

Bénéfices : supprime les 2 douleurs, corrige les 2 bugs, conserve la saisie en jours (confirmée nécessaire), et fiabilise le dénominateur (consultants uniques) + le coût (CJM × jours).

---

## Modèle de données

Nouvelle table **`interco_imputations`** — forme « longue » (1 ligne par consultant × mois) :

```
interco_imputations
  id                     PK
  contact_consultant_id  FK → contacts (statut « Consultant CDI »)
  annee                  int   (ex. 2026)
  mois                   int   (1–12)
  jours                  numeric (ex. 9)
  cjm_snapshot           numeric  -- CJM du consultant figé À LA SAISIE (voir Coût)
  updated_by             FK → user
  updated_at             timestamptz
  UNIQUE (contact_consultant_id, annee, mois)
```

### Ce qu'on NE stocke PAS (on dérive — évite les désynchros)
- **agence + responsable** → lus depuis le contact consultant (pas de copie).
- **« en interco actuellement »** → dérivé : a des jours interco sur le mois courant.

### Coût interco — calculé, jamais figé comme montant, mais CJM figé
Le CJM d'un consultant est aujourd'hui un **champ fixe** sur le contact, **qui peut évoluer**. Calculer `CJM_actuel × jours_passés` réécrirait rétroactivement les coûts des mois clos.
→ On stocke `cjm_snapshot` sur chaque ligne (capturé à la saisie/màj du mois). **Coût = `cjm_snapshot × jours`.** Les hausses futures de CJM n'altèrent pas l'historique.
*(Évolution possible : si un historique de CJM daté est créé un jour, on basculera la lecture dessus sans changer le reste.)*

---

## Calcul de la carte « data interco » (corrigé)

- **Dénominateur** = nb de **contacts uniques** statut « Consultant CDI » de l'agence/scope, × **jours ouvrés réels du mois** (table/fonction jours ouvrés par mois, plus de constante 18,16).
- **Numérateur** = somme `jours` de `interco_imputations` sur le mois/scope.
- **Taux mensuel** = numérateur ÷ dénominateur ; **trimestre** et **YTD** agrégés sur la même base.
- **Seuils** inchangés : `≥5%` Attention, `≥8%` MALUS.
- **Coût interco** affiché = somme `cjm_snapshot × jours`.
- **Scopes** : France (admin/multi-agence) / par agence / par commercial — dérivés du contact.

> Détail d'implémentation à confirmer au build : périmètre du dénominateur par mois. V1 = nb de contacts « Consultant CDI » courants du scope. Si les contacts portent des dates d'entrée/sortie fiables, on raffine au mois.

---

## UX de la saisie (validée en maquette)

Module **intégré dans la fiche contact en édition (panneau latéral)**, disposition **« mois courant en avant + historique »** (option C).

### Desktop
- Bloc principal = **mois courant**, 1 champ « jours » + boutons-raccourcis **100% / 50%**.
- **Raccourcis** : 100% remplit les **jours ouvrés réels du mois** ; 50% la moitié. Saisie manuelle d'un nombre custom toujours possible. **Pas de quotité stockée** : la donnée est toujours **les jours**.
- **Historique annuel** sous le bloc (mini-barre 12 mois) : **clic sur une colonne → le bloc bascule sur ce mois** pour l'éditer, avec un retour « ↩ mois courant ».
- Bas de bloc : **YTD jours + coût** (`cjm_snapshot × jours`).

### Mobile (PWA — indispensable)
- Panneau plein écran ; gros champ centré ouvrant le **clavier numérique** ; quotité en **2 gros boutons** (100% / 50% forfait).
- L'historique 12 colonnes (trop fin au doigt) devient une **rangée de pastilles mois tapables** (scroll horizontal). Même logique, cible adaptée au pouce.

---

## MCP — outils à ajouter (pilotage interco depuis Claude)

- `crm_set_interco(consultant, annee, mois, jours)` → **upsert** sur `(contact_consultant_id, annee, mois)`, capture `cjm_snapshot` au passage.
- `crm_get_interco(consultant, annee)` → l'année d'un consultant (12 mois + total + coût).
- `crm_list_interco(annee, mois?, agence?)` → vue d'ensemble + taux + seuils par scope.
- `crm_delete_interco(consultant, annee, mois)` → remet un mois à 0 (option).

Les écritures MCP respectent les **mêmes droits** que l'UI (voir ci-dessous).

---

## Droits (calqués sur SPEC_contacts_permissions_agence)

Les contacts portent `agence` et `responsable`.

```
READ  interco d'un consultant ← tout le monde (comme la carte aujourd'hui)

WRITE interco d'un consultant ← agence_contact == agence_user   (commerciaux de l'agence du consultant)
                              OR responsable_contact == user_id  (le responsable du consultant)
                              OR role == 'admin'
```

À appliquer en **RLS Supabase** + garde côté UI + garde côté MCP.

---

## Migration de l'existant + suppression des missions interco

Séquence **avec filet de sécurité** (validée) :
1. **Migrer** : pour chaque mission `statut='Intercontrat'`, convertir chaque `jours_<mois>` non nul en ligne `interco_imputations` (consultant = `contact_consultant_id` de la mission ; `cjm_snapshot` = CJM courant du contact à la date de migration).
2. **Vérifier** : les totaux de jours interco par mois (et par agence) sont **identiques avant/après**. Écart → on s'arrête et on investigue.
3. **Sauvegarder** : export des missions interco supprimées (CSV/JSON) conservé.
4. **Supprimer** les missions `statut='Intercontrat'` → pipeline missions redevient 100% facturable, CA/marge n'ont plus à les exclure.
5. Retirer la valeur `'Intercontrat'` des statuts de mission (`MISSION_STATUTS`) et le code de calcul interco basé missions.

---

## Hors périmètre (YAGNI v1)
- Suggestion auto « il te reste X jours non staffés » (idée évoquée, repoussée — dépend d'une saisie mission parfaite + gestion congés).
- Historique de CJM daté (on fige via `cjm_snapshot` en attendant).
- Gestion fine de l'effectif par dates d'entrée/sortie (raffinement dénominateur).

---

## Points à vérifier au build
1. Champ **CJM** exact sur le contact (nom de colonne) + cas où il est vide (coût = 0 + alerte ?).
2. Source des **jours ouvrés réels par mois** (table de référence ou calcul jours fériés FR).
3. Présence/fiabilité de `responsable` sur les contacts « Consultant CDI » (sinon repli agence + admin).
4. Périmètre exact du dénominateur par mois (cf. note carte).
