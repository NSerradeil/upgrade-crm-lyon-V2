# SPEC — Pipeline des prospects · Étapes & prochaine action datée
**CRM Upgrade Lyon V2** · Évolution majeure
**Auteur :** Nicolas Serradeil + Claude (PM + Lead UX)
**Date :** 29/09/2026
**Origine du besoin :** demande d'Anne-Claire (agence Bordeaux/Ouest), schéma de pipeline en 5 étapes + 3 sorties.

---

## Contexte & challenge produit

### Besoin exprimé
> "Le statut de contact reste « Prospect », on ajoute un champ **Étape** qui dit où il en est, comme les colonnes d'un Pipedrive. Chaque prospect avance dans 5 étapes, avec une prochaine action datée."
> — Anne-Claire

> "J'imagine avoir un système proche de celui de l'onglet Besoins. Quand dans la vue Contacts on sélectionne le type « Prospect », ça changerait le tableau pour avoir le même que celui de Besoins, + le toggle permettant de passer d'une vue cartes à la vue kanban."
> — Nicolas

### État actuel
Un contact de statut `Prospect` n'a **aucun cycle de vie**. Il porte `date_dernier` (dernier contact) et un flag `ne_pas_recontacter`, rien d'autre. On ne peut répondre ni à « où en est ce prospect ? », ni à « qui dois-je relancer aujourd'hui ? ».

L'onglet « Prosp. » **n'est pas un pipeline** : ce sont des sessions d'appels sortants (reporting + exécution). Il ne porte aucun état durable du prospect. Cette spec ne le remplace pas, elle le branche dessus.

### Parti pris : cloner le pattern Besoins, ne pas en inventer un autre
Le pipeline Besoins est éprouvé et compris par l'équipe. On reprend **sa grammaire à l'identique** : stepper cliquable, micro-formulaire contextuel avec champs obligatoires, log en historique, motif obligatoire à la perte, modale de proposition à la jonction suivante.

La chaîne devient continue et lisible de bout en bout :

```
CONTACT (Prospect)                    BESOIN                         MISSION
À contacter → Contacté → En discussion   Opportunité → … → Gagné   →  contact = Client
→ RDV planifié → Qualifié  ──[modale]──→
```

Chaque jonction est une **modale de proposition**, jamais un automatisme silencieux — exactement comme `Besoin Gagné → proposeMission` (index.html:5630).

### Ce que ça n'est pas
- Ce n'est pas un remplacement de l'onglet « Prosp. » (sessions d'appels).
- Ce n'est pas un pipeline sur les **comptes** : l'étape vit sur le **contact**.
- Ce n'est pas un refactor du kanban Besoins.

---

## Pipeline des étapes

```
ACTIVES :  À contacter → Contacté → En discussion → RDV planifié → Qualifié
SORTIES :  En veille  ·  Perdu  ·  Ne pas recontacter
```

| Étape | Sens | Champs obligatoires au passage |
|---|---|---|
| **À contacter** | identifié, jamais appelé | — |
| **Contacté** | tentatives en cours | prochaine action datée |
| **En discussion** | a répondu | prochaine action datée |
| **RDV planifié** | date de RDV posée | date du RDV (= prochaine action) |
| **Qualifié** | besoin identifié | prochaine action datée + proposition de créer le Besoin |
| **En veille** | sortie temporaire | **date de réveil** (préréglages 3 mois / 6 mois / 1 an) |
| **Perdu** | sortie | **motif** (liste) + commentaire optionnel |
| **Ne pas recontacter** | sortie définitive | commentaire de détail |

**Sortie possible à tout moment** depuis n'importe quelle étape active.
**Retour en jeu** : à la date de réveil, un prospect « En veille » revient en tête de board avec un badge. Un prospect « Perdu » peut être repassé manuellement en « À contacter ».

---

## Décision structurante : suppression du flag `ne_pas_recontacter`

Le flag booléen actuel et l'étape « Ne pas recontacter » diraient la même chose à deux endroits. **On supprime le flag et on garde l'étape.** Un seul axe de lecture.

Le flag porte aujourd'hui deux protections qui sont **reportées telles quelles sur l'étape** :

1. **Levée réservée au responsable du contact** (index.html:2169). Garantie RGPD : n'importe qui ne peut pas remettre en jeu une personne qui a demandé qu'on lui fiche la paix. → sortir de l'étape « Ne pas recontacter » reste réservé au responsable.
2. **Exclusion automatique des sessions d'appels** (posé automatiquement aux lignes 11092 et 11171). → la sélection de contacts d'une session exclut désormais l'étape, et la fin de session pose l'étape au lieu du flag.

La **bannière rouge** en tête de fiche (index.html:2161) et le **badge en liste** (index.html:3889) restent, pilotés par l'étape.

**Migration en deux temps, pas de `DROP` sec :**
- Migration `51` : backfill `ne_pas_recontacter = true` → `etape_prospect = 'Ne pas recontacter'`, `ne_pas_recontacter_note` → `motif_perte_precision`. Le code ne lit plus que l'étape. Les colonnes restent en base, inertes.
- Migration `52`, après une semaine de prod sans incident : `DROP` des trois colonnes.

---

## Modèle de données

`db/51_contacts_etape_prospect.sql`

```sql
-- SPEC_prospects_pipeline_etapes.md — 29/09/2026
-- Pipeline des prospects : étape, prochaine action datée, motif de sortie.

alter table contacts add column if not exists etape_prospect text;
alter table contacts add column if not exists prochaine_action_date timestamptz;
alter table contacts add column if not exists prochaine_action_libelle text;
alter table contacts add column if not exists motif_perte text;
alter table contacts add column if not exists motif_perte_precision text;

comment on column contacts.etape_prospect is
  'Étape du pipeline prospect. Ne vaut que si statut = Prospect. Cf. SPEC_prospects_pipeline_etapes.md';

-- Backfill : tout prospect existant démarre en « À contacter », sans action exigée.
update contacts set etape_prospect = 'À contacter'
  where statut = 'Prospect' and etape_prospect is null;

-- Reprise du flag ne_pas_recontacter (supprimé en migration 52).
-- Volontairement SANS filtre sur statut : un contact qui portait le flag puis est passé Client
-- ou Candidat doit garder son refus d'être recontacté (RGPD). Le board ne lit que les prospects,
-- donc aucun effet de bord. La date de la demande est conservée dans motif_perte_precision.
update contacts set etape_prospect = 'Ne pas recontacter',
                    motif_perte_precision = coalesce(motif_perte_precision,
                      case when ne_pas_recontacter_date is not null
                           then 'Depuis le ' || to_char(ne_pas_recontacter_date, 'DD/MM/YYYY')
                                || coalesce(' : ' || ne_pas_recontacter_note, '')
                           else ne_pas_recontacter_note end)
  where ne_pas_recontacter = true;

create index if not exists idx_contacts_etape_prospect
  on contacts (etape_prospect) where statut = 'Prospect';
create index if not exists idx_contacts_prochaine_action
  on contacts (prochaine_action_date) where statut = 'Prospect';
```

| Colonne | Type | Équivalent côté besoin | Description |
|---|---|---|---|
| `etape_prospect` | text | `besoins.statut` | Étape du pipeline. Nommée `etape_prospect` et non `etape` car `statut` est déjà pris sur le contact. |
| `prochaine_action_date` | timestamptz | `besoins.date_entretien` (généralisé) | Pilote le board : tri, retard, réveil. |
| `prochaine_action_libelle` | text | — | « Rappeler », « Relancer le mail du 12 », « Réveil prospect ». |
| `motif_perte` | text | `besoins.motif_perte` | Obligatoire si étape = Perdu. |
| `motif_perte_precision` | text | `besoins.motif_perte_precision` | Commentaire libre, sert aussi à « Ne pas recontacter ». |

**Pas de CHECK SQL sur `etape_prospect`** : le champ `statut` du contact n'en a pas non plus (index.html:215, texte libre), on reste cohérent avec l'existant.

**Au changement de statut** (Prospect → Client via mission, ou → Candidat) : `etape_prospect` **n'est pas effacée**, elle reste comme trace. Le board ne lit que `statut = 'Prospect'`, donc elle disparaît de la vue naturellement. Même philosophie que `ancien_statut` (db/24).

**Backfill et obligation** : les prospects existants passent en « À contacter » **sans prochaine action exigée**. L'obligation ne s'applique qu'aux changements d'étape faits après la mise en production, sinon le board s'ouvre sur des milliers de lignes en retard le premier jour.

---

## Règles

### R1 — Prochaine action datée obligatoire
Toute entrée dans une étape **active** (Contacté, En discussion, RDV planifié, Qualifié) exige une `prochaine_action_date`. Le bouton Confirmer du micro-formulaire est désactivé sans elle (même mécanique que `canSubmit`, index.html:5471).

« À contacter » en est exempte : c'est l'état d'entrée, le prospect vient d'être identifié.

### R2 — La prochaine action peut créer sa tâche CRM
Le micro-formulaire porte, sous le champ de date, une case **« Créer la tâche »** cochée par défaut, avec un libellé pré-rempli depuis l'étape visée. La tâche est créée dans `taches` avec `contact_id`, `due_date`, `responsable`.

Garde anti-doublon identique à la tâche entretien (index.html:5645) : si une tâche non close existe déjà sur ce contact avec le même préfixe, on ne crée pas de seconde tâche — toast « action re-planifiée, pense à mettre à jour la tâche existante ».

Heure par défaut : **9h00** (règle Jules : les relances se traitent le matin).

### R3 — La boucle se referme depuis les tâches
Clore une tâche de prospection depuis l'onglet Tâches **rouvre le micro-formulaire d'étape** du contact lié, pour capter ce que l'action a donné. C'est ce qui tient le « action datée obligatoire » sans règle bloquante pénible : on ne t'interdit rien, on te demande la suite au bon moment.

### R4 — Réveil des prospects en veille
Passage en « En veille » → champ **Date de réveil** obligatoire, avec préréglages 3 mois / 6 mois / 1 an et saisie libre. Écrit `prochaine_action_date` = date de réveil, `prochaine_action_libelle` = « Réveil prospect », plus la tâche CRM (R2).

À la date atteinte : la carte remonte en tête de board avec un badge « réveil », et la tâche le rappelle dans Outlook. Deux rappels pour un même événement, mais deux moments : le board quand tu ouvres le CRM, la tâche quand tu ne l'ouvres pas. **Aucun job de fond** : c'est la même colonne date qui sert.

### R5 — Sortie du pipeline par le Besoin
Passage en **« Qualifié »** → modale **« Créer le besoin »**, pré-remplie avec le compte et le contact, statut `Opportunité`. Clone de `proposeMission` (index.html:5630).

C'est **l'existence d'un besoin lié au contact** qui le sort du board, pas l'étape en elle-même. Si le besoin est supprimé ou passe en `Besoin Perdu`, le prospect peut revenir sur le board en « En veille ».

La suite de la chaîne existe déjà et n'est pas touchée : `Besoin Gagné` → modale mission → contact `Client` (index.html:2397 et 11622).

### R6 — Motif obligatoire à la perte
Passage en « Perdu » → motif obligatoire, liste reprise des besoins et adaptée : `Budget insuffisant`, `Pas le bon interlocuteur`, `Pas de besoin`, `Choix concurrent`, `Perdu de vue`, `Autre`. Commentaire libre optionnel.

### R7 — Trace en historique
Chaque changement d'étape écrit dans `historique_actions`, comme `logStatutChange` pour les besoins.

### R8 — Droits
L'étape suit exactement les règles d'écriture du statut : RLS par agence (db/09, `SPEC_contacts_permissions_agence.md`). Seule exception, R8b : **sortir de l'étape « Ne pas recontacter » est réservé au responsable du contact**.

---

## UI

### Déclenchement
Dans `TabProspects` (index.html:3756), sous-vue **Contacts**, quand le filtre statut vaut **`Prospect`** (le filtre est aux lignes 4315-4317) :
- un **toggle Liste / Kanban** apparaît à droite des filtres ;
- le tableau gagne deux colonnes, **Étape** et **Prochaine action**.

Sur « Tous » ou tout autre statut, la vue reste **strictement inchangée** : l'étape n'existe que pour les prospects, un kanban sur un mélange de statuts n'aurait pas de colonnes.

⚠️ **`viewMode` est déjà pris** dans `TabProspects` (index.html:3765) pour basculer Contacts / Comptes. Le nouveau toggle s'appelle **`prospectView`** (`'list' | 'kanban'`), persisté dans les préférences sous `prefs.prospects_view`, comme `prefs.besoins_view` (index.html:5976).

### Vue liste
Deux colonnes ajoutées :
- **Étape** : badge coloré, palette calquée sur `BESOIN_BADGE_COLORS_GLOBAL` (index.html:908).
- **Prochaine action** : date + libellé, **liseré rouge** si dépassée.

Tri par défaut sur `prochaine_action_date` croissant (le retard remonte en haut), et non plus sur `date_dernier` (index.html:3763, 3808).

### Vue kanban — `ProspectsKanban`
Clone du kanban Besoins (index.html:5920). On réutilise **tel quel** : le hook drag&drop (index.html:701-719), `useListReorder`, et le CSS `.kanban-board` / `.kanban-col` / `.kanban-card` (index.html:83-92).

On **clone plutôt qu'on ne généralise** : le kanban Besoins est couplé en dur à `BESOIN_STATUTS_ORDRE`, `besoinCandidats` et `contactMap`. Le rendre générique pour ce chantier ferait porter un risque de régression à un écran qui marche, pour un gain de factorisation qu'on ne consomme que deux fois.

- **5 colonnes actives** affichées par défaut.
- **3 colonnes de sortie repliées** à droite du board, dépliables d'un clic : sinon elles écrasent visuellement les colonnes où le travail se fait.
- **Carte** : nom du contact, société (`primaryCompteByContact`, index.html:3785), prochaine action datée avec liseré rouge si dépassée, badge « réveil » si la date de réveil est atteinte.

### Drag & drop : le drop ouvre le micro-formulaire
Côté besoins, glisser une carte écrit le statut directement. **Ici, le drop ouvre le micro-formulaire et n'écrit qu'à la confirmation.** Annuler ramène la carte à sa colonne d'origine.

Raison : glisser vers « Perdu » écrirait sans motif, vers « RDV planifié » sans date. On perdrait exactement ce qui fait la valeur du pipeline. Un drop est une **intention**, la saisie la confirme.

### `ProspectStatusStepper` + `ProspectMicroForm`
Clones de `BesoinStatusStepper2` (index.html:5432) et `BesoinMicroForm` (index.html:5464), mêmes styles brutalistes (`borderRadius:0`, `boxShadow:'4px 4px 0 '+bc.bg`, Outfit uppercase).

Le stepper se place en tête de `ContactDetail` (index.html:2114), visible seulement si `statut === 'Prospect'`. Le même `ProspectMicroForm` est appelé depuis trois endroits : le stepper de la fiche, le drop sur le kanban, et la clôture d'une tâche de prospection (R3).

---

## Impact sessions d'appels (onglet « Prosp. »)

Le mapping du résultat d'appel vers l'étape, dans `handleTerminer` :

| `session_prospection_contacts.statut` | Étape appliquée |
|---|---|
| `interested` | En discussion |
| `unreachable` | Contacté |
| `not_interested` | Perdu, ou Ne pas recontacter si l'utilisateur coche « ne plus appeler » |
| `called` / `none` | Contacté (si l'étape était « À contacter ») |

Le `want_relance` / `relance_date` existant **alimente directement** `prochaine_action_date` et `prochaine_action_libelle`. La tâche de relance créée aujourd'hui par `handleTerminer` reste la même tâche : on ne la duplique pas.

La sélection de contacts d'une session **exclut les étapes de sortie** (elle excluait le flag).

Sans ce branchement, on dirait la même chose à deux endroits et le board serait périmé dès la première session d'appels.

---

## Impact MCP (`upgrade-crm-mcp-src`) — v8.25.0 → v8.26.0

Si l'étape n'existe que dans l'UI, Jules et Claude Cowork travaillent à l'aveugle et écrivent à côté.

| Outil | Évolution |
|---|---|
| `crm_search_contacts` (index.mjs:470) | Retourne `etape_prospect`, `prochaine_action_date/_libelle`. Nouveaux filtres `etape` et `en_retard`. |
| `crm_update_contact` (index.mjs:605) | Écrit l'étape, la prochaine action, le motif. Porte les garde-fous ci-dessous. |
| `crm_create_contact` (index.mjs:553) | Un contact créé en `Prospect` naît en `À contacter`. |
| **`crm_prospects_due_today`** *(nouveau)* | Miroir de `agent_sequence_due_today` : les prospects dont la prochaine action est due ou en retard, triés, avec l'étape et le libellé. C'est ce qui permet de préparer la prospection du matin sans ouvrir le CRM. |

**Garde-fous côté serveur, pas seulement côté écran.** Précédent maison : le refus de scope sur `crm_create_besoin` en v8.25.0 (index.mjs:452).

- `crm_update_contact` **refuse** de poser une étape active sans `prochaine_action_date`.
- Il **refuse** « Perdu » sans `motif_perte`.
- Il **refuse** de sortir de « Ne pas recontacter » si l'appelant n'est pas le responsable du contact.

Une règle qui ne vit que dans l'UI se contourne par l'API, ce qui revient à ne pas l'avoir.

### .mcpb
Rebuild du paquet, bump `manifest.json` en `8.26.0`, changelog dans la description du serveur (index.mjs:452), réinstall côté **Claude Cowork / Desktop** et côté **Jules**. Le paquet est le seul chemin de distribution : tant qu'il n'est pas reconstruit, rien de ce qui précède n'existe hors du navigateur.

---

## Ce qu'on ne touche pas

- Le **kanban Besoins** et le pipeline Besoins : INTOUCHÉS.
- La **sous-vue Comptes** : INTOUCHÉE.
- Les onglets **Missions**, **Pipe**, **Agence**, **Historique** : INTOUCHÉS.
- La **gamification** et les **KPI de prospection** : INTOUCHÉS (une évolution ultérieure pourra compter les passages d'étape, hors périmètre ici).
- La chaîne `Besoin Gagné → Mission → contact Client` : INTOUCHÉE.

---

## Egress & performance

Règle maison : `select` ciblé, colonnes validées contre le schéma avant push. Les cinq nouvelles colonnes s'ajoutent au select principal des contacts (index.html:11573). Les deux index partiels (`where statut = 'Prospect'`) gardent le coût marginal.

Le board se construit **côté client**, à partir des contacts déjà chargés : aucune requête supplémentaire.

---

## Acceptance criteria

**Données**
- [ ] Migration 51 appliquée, les 5 colonnes existent, les deux index aussi.
- [ ] Tous les prospects existants sont en « À contacter », aucun avec une prochaine action imposée.
- [ ] Les contacts qui portaient `ne_pas_recontacter = true` sont en étape « Ne pas recontacter », note reprise.

**Vue**
- [ ] Filtre statut = Prospect → le toggle Liste/Kanban apparaît ; sur tout autre filtre, la vue est identique à avant.
- [ ] `prospectView` est persisté : après rechargement, on retrouve sa vue.
- [ ] La bascule Contacts/Comptes existante fonctionne toujours (non-régression sur `viewMode`).
- [ ] Le kanban affiche 5 colonnes actives, les 3 sorties repliées et dépliables.
- [ ] Une prochaine action dépassée affiche un liseré rouge, en liste comme en carte.
- [ ] Le tri par défaut de la liste remonte les retards en haut.

**Règles**
- [ ] Impossible de confirmer une étape active sans prochaine action datée.
- [ ] Impossible de confirmer « Perdu » sans motif.
- [ ] « En veille » propose 3 mois / 6 mois / 1 an et une date libre.
- [ ] La case « Créer la tâche » est cochée par défaut et crée bien une tâche liée au contact, à 9h00.
- [ ] Deux passages d'étape successifs ne créent pas deux tâches doublons.
- [ ] Clore une tâche de prospection rouvre le micro-formulaire d'étape.
- [ ] « Qualifié » propose la création du besoin, pré-rempli compte + contact en `Opportunité`.
- [ ] Un contact avec un besoin lié actif n'apparaît plus sur le board.
- [ ] Chaque changement d'étape apparaît dans l'historique du contact.
- [ ] Un non-responsable ne peut pas sortir un contact de « Ne pas recontacter ».

**Sessions d'appels**
- [ ] Terminer une session fait avancer les étapes selon le mapping.
- [ ] `want_relance` alimente la prochaine action sans créer de tâche en double.
- [ ] Les contacts en étape de sortie n'apparaissent plus dans la sélection d'une session.

**MCP**
- [ ] `crm_search_contacts` retourne l'étape et filtre dessus.
- [ ] `crm_prospects_due_today` retourne les prospects dus et en retard.
- [ ] `crm_update_contact` refuse une étape active sans date, et « Perdu » sans motif.
- [ ] Le .mcpb 8.26.0 est installé côté Cowork et côté Jules, et Jules lit l'étape.

**Migration 52 (différée)**
- [ ] Après une semaine sans incident, `DROP` de `ne_pas_recontacter`, `_note`, `_date`.
