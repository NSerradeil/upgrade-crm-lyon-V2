# Suppression par le responsable, avec archive (« corbeille »)

Demande de Nicolas, 05/11/2026. Décisions D1 à D5 tranchées par Nicolas le 05/11 (voir § 6). Lots L1 + L2 codés et testés le 05/11 (voir § 7), **rien n'est encore appliqué en prod**.
Origine : Anne-Claire a déplacé les contacts du doublon « FDJ United » vers « FDJ » et ne pouvait pas supprimer le compte vide.

---

## En bref (pour Nicolas)

1. Chaque commercial pourra supprimer **ses propres** fiches (contacts, comptes, puis besoins, missions, tâches). Jamais celles d'un collègue.
2. Quand un commercial supprime, la fiche disparaît du CRM mais une **copie complète part dans une corbeille** en base (avec son historique, ses liens, qui l'a supprimée, quand, pourquoi).
3. Quand toi (ou Pierre, l'autre admin) supprimez, la fiche part AUSSI en corbeille (décision D1), avec une ligne de trace « suppression_admin ».
4. Toi seul (admin), depuis Jules ou un builder, peux **vider** la corbeille ou **remettre** une fiche supprimée par erreur.
5. Garde-fous : impossible de supprimer un compte qui a encore des missions, des besoins ou des contacts rattachés ; impossible de supprimer un contact qui est consultant, en mission ou sur un besoin. Une fiche à la fois, avec confirmation.
6. Le cas FDJ United devient simple : Anne-Claire déplace ses contacts, puis supprime le compte vide elle-même.
7. Découverte importante : **aujourd'hui, un commercial peut déjà effacer pour de bon ses contacts, besoins, missions et tâches, sans aucune trace** (un contact supprimé emporte tout son historique d'échanges). Le chantier corrige ça aussi.
8. Autre découverte : l'outil de suppression de compte du connecteur Claude annonce « supprimé » à un commercial alors que rien n'est supprimé, et décroche au passage les missions et besoins du compte. À corriger dans la même livraison.
9. Livraison en petits morceaux : d'abord comptes + contacts (base, puis appli, puis connecteur), ensuite besoins / missions / tâches.
10. Les 5 décisions sont tranchées (§ 6) : admin archivé aussi, purge automatique à 12 mois, lot 1 = comptes + contacts, fiche sans responsable = admin seul, compte non vide refusé.

Le doublon FDJ United (compte 454) n'existe déjà plus en base (vérifié le 05/11 à 16h) : le cas d'Anne-Claire est réglé, ce chantier sert aux suivants.

---

## 1. État des lieux (lu en base de prod le 05/11, lecture seule)

### 1.1 Qui est qui

- `profiles.nom` (texte, nom complet) + `profiles.role` (`admin` / `commercial` / `partner`).
- Les politiques RLS lient l'utilisateur connecté par deux fonctions : `get_my_nom()` et `get_my_role()` (SECURITY DEFINER, lisent `profiles` par `auth.uid()`).
- Côté schéma `jules` : `jules.est_direction()` = « rôle admin », `jules.est_service_jwt()` = « appel avec la clé service (Jules, builders) ».
- Admins actuels : **Nicolas Serradeil, Pierre Solle**. Commerciaux : Amel Benzai, Anne-Claire Decker, Camille Salinson, Louis Py. Partner : Maria-Jose Paquelier.
- La colonne `responsable` est **un texte (nom complet)**, pas un identifiant. Pas de clé étrangère vers `profiles`.

### 1.2 Volumes

| Table | Lignes | Remarque |
|---|---|---|
| comptes | 598 | **100 sans responsable** (dont 2 avec missions) ; 23 sans aucun lien (ni contact, ni mission, ni besoin) |
| contacts | 2 235 | tous ont un responsable |
| contact_compte | 1 703 | colonnes `date_debut`, `date_fin`, `is_primary`, `role` |
| besoins | 498 | id = uuid |
| missions | 157 | 109 En cours, 2 New, 46 Terminée |
| taches | 1 774 | id = texte |
| historique_actions | 5 857 | jusqu'à 58 actions pour un même contact |

Les identifiants de `comptes` et `contacts` viennent de séquences (pas de colonne « identity ») : une restauration peut réinsérer la fiche **avec le même id**, ce qui reconnecte automatiquement les références sans clé étrangère côté Jules (voir 1.5).

### 1.3 Droits de suppression actuels (politiques DELETE / ALL)

| Table | Qui peut supprimer aujourd'hui | Archive ? |
|---|---|---|
| comptes | admin seulement (`comptes_delete_admin`) | non |
| contact_compte | admin seulement | non |
| contacts | **admin OU responsable** (`delete_contacts`) | **non** |
| besoins | admin, ou commercial responsable | **non** |
| missions | **admin OU responsable**, quel que soit le statut (même En cours avec du CA) | **non** |
| taches | admin ou responsable ; partner sur ses consultants | non |
| historique_actions | admin ou auteur ; partner sur ses consultants | non |
| historique_missions, mission_periods | admin / responsable de la mission / partner | non |

Conclusion : le droit demandé existe déjà pour contacts / besoins / missions / tâches, **sans archive ni garde-fou**. Seuls les comptes sont réservés à l'admin.

### 1.4 Ce qui se passe à la suppression (clés étrangères)

Supprimer un **compte** :
- `contact_compte` → CASCADE (liens effacés)
- `besoins.compte_id`, `missions.compte_id` → SET NULL (le besoin / la mission perd son compte : **les KPI CA/marge du compte disparaissent sans bruit**)

Supprimer un **contact** :
- CASCADE : `historique_actions` (tout l'historique d'échanges), `contact_compte`, `besoin_candidats`, `interco_imputations`, `partner_consultants`
- bloquant (NO ACTION) : `besoins.contact_id / candidat_id / consultant_id`, `missions.contact_consultant_id / contact_referent_id`, `session_prospection_contacts`
- SET NULL : `jules.agent_sequences.contact_id` (331 séquences actives au total en base)

Supprimer une **mission** : CASCADE `historique_missions`, `mission_periods` ; SET NULL `taches.mission_id`.
Supprimer un **besoin** : CASCADE `besoin_candidats` ; SET NULL `missions.besoin_id` ; bloquant `historique_actions.besoin_id`, `taches.besoin_id`.

### 1.5 Références sans clé étrangère (schéma `jules`)

Ces tables pointent vers un compte, un besoin ou une mission sans contrainte : `jules.partages_compte`, `jules.comptes_ecartes`, `jules.vivier_prospects`, `jules.push_besoins` (compte_id), `jules.partages_besoin`, `jules.besoins_masques`, `jules.agent_missions` (besoin_id). Après une suppression, elles pointent dans le vide (sans planter). On ne les touche pas ; une restauration avec le même id les reconnecte.

### 1.6 Triggers en place

- `trg_guard_responsable` (db/10) sur comptes, contacts, besoins, missions, taches : seul le responsable ou un admin change le responsable. Inchangé.
- `trg_contacts_sortie_effectif`, `besoins_crm_vers_appli` (AFTER UPDATE), `trg_update_date_dernier` (AFTER INSERT historique) : aucun ne se déclenche sur DELETE.
- Le trigger de **synchro consultant ↔ groupe/compte** (chantier 1.D) a été retiré par `db/18_drop_trigger_groupe_consultant.sql` : il n'existe plus en prod, aucune interaction.
- Aucun trigger BEFORE/AFTER DELETE sur ces tables aujourd'hui.

### 1.7 Code qui supprime aujourd'hui

App (`index.html`) :
- Contact (l. ~2713) : 4 appels séparés, non atomiques (historique, besoin_candidats, tâches, puis contact). Bouton visible si admin ou responsable.
- Compte (l. ~4829) : `sb.from('comptes').delete()`, bouton visible **admin seulement** (`CompteSidebar`, l. ~5124). Modale `ConfirmDeleteCompteModal` déjà prévue (« action irréversible »).
- Mission (l. ~3195 et ~3562), besoin (l. ~6586), tâche (l. ~5636) : suppressions directes.

Connecteur MCP 8.34.0 (`upgrade-crm-mcp-src/server/index.mjs` sur le mini, l. ~1192-1256) :
- `crm_delete_contact`, `crm_delete_compte`, `crm_delete_mission`, `crm_delete_besoin` : suppressions directes en plusieurs appels.
- **Bug** : `crm_delete_compte` appelé par un commercial met d'abord `compte_id = NULL` sur les besoins et missions du compte (autorisé par db/09), puis le DELETE du compte est filtré par la RLS (0 ligne, pas d'erreur) et l'outil répond « ✅ Compte supprimé ». Résultat : compte toujours là, missions et besoins décrochés. Même faux succès possible côté app (le DELETE filtré ne renvoie pas d'erreur), mais le bouton y est caché aux non-admins.

### 1.8 Précédent à imiter : le transfert de responsabilité (db/59)

`transferer_responsabilite(p_type, p_id, p_nouveau)` : fonction SQL unique SECURITY DEFINER, appelée par l'app (`sb.rpc`) et le MCP, journal dédié (`transferts_responsabilite`) en lecture seule, tests intégrés dans la migration (tout ou rien). On reprend exactement ce modèle.

---

## 2. Conception

### 2.1 Principe : une fonction unique, pas un trigger

Toute suppression d'une fiche métier passe par **une seule fonction SQL** `supprimer_fiche(p_type, p_id, p_motif, p_origine)`, appelée par l'app, le MCP et Jules.

Pourquoi pas un trigger BEFORE DELETE : les enfants partent en CASCADE avant que l'on puisse les photographier proprement dans le bon ordre, l'app supprime aujourd'hui en 4 appels séparés (chaque appel déclencherait sa propre archive), et un trigger ne sait pas « pourquoi / depuis où ». La fonction fait tout en une transaction : contrôles, photo complète, suppression.

Ce qui ferme les chemins de contournement : les politiques DELETE directes sont réservées à l'admin sur les tables couvertes par le lot en cours (un commercial ne peut plus faire de DELETE direct, seulement passer par la fonction).

### 2.2 La corbeille (`public.corbeille`)

| Colonne | Contenu |
|---|---|
| id | bigserial |
| objet_type | `compte` / `contact` (lot 1) ; `besoin` / `mission` / `tache` (lot 3) |
| objet_id | id d'origine (texte, pour couvrir bigint, uuid, texte) |
| libelle | « FDJ United », « Jean Dupont » : pour lister sans ouvrir le JSON |
| responsable_fiche | responsable de la fiche au moment de la suppression |
| ligne | jsonb : la ligne complète (`to_jsonb(row)`) |
| liens | jsonb : `{ "contact_compte": [...], "historique_actions": [...], "taches": [...], ... }` les lignes enfants supprimées, et `{ "detaches": {...} }` les références remises à NULL avec leur ancienne valeur |
| motif | texte libre, facultatif (« doublon de FDJ (131) ») |
| origine | `app` / `mcp` / `jules` / `builder` |
| par_nom, par_user, par_role | qui a supprimé |
| supprime_le | timestamptz |
| restaure_le, restaure_par | rempli si remise en place (la ligne reste pour l'historique, ou est retirée : voir 2.6) |

Droits : RLS activée ; aucun INSERT/UPDATE/DELETE direct (seules les fonctions écrivent) ; SELECT réservé à l'admin (une corbeille lisible par tous exposerait des fiches supprimées à des collègues). Option : le commercial voit ses propres suppressions (non retenue au lot 1).

### 2.3 Le journal (`public.corbeille_journal`)

Une ligne par événement, **sans contenu métier** : `evenement` (`suppression_admin` / `restauration` / `purge`), objet_type, objet_id, libelle, par_nom, par_user, origine, nb_lignes, created_at. Sert de trace aux suppressions admin (qui ne passent pas par la corbeille) et aux purges.

### 2.4 Règles de `supprimer_fiche`

Appelant :
- session obligatoire (`auth.uid()` non nul), rôle `admin` ou `commercial` ; un partner ne supprime rien par cette voie ;
- exception : appel avec la clé service (`jules.est_service_jwt()`) accepté **uniquement** si `p_origine in ('jules','builder')` et traité comme un admin (voir « points tranchés par défaut » en fin de spec).

Droit sur la fiche :
- commercial : `responsable = get_my_nom()` exactement. Fiche sans responsable ou d'un membre parti → refus, message « demande à un admin ou fais-la transférer » ;
- admin : toute fiche.

Garde-fous **non contournables par un commercial** (l'admin peut forcer avec `p_forcer = true`, journalisé) :

Compte :
- aucune mission rattachée (`missions.compte_id`), quel que soit le statut (une mission terminée porte du CA historique) ;
- aucun besoin rattaché (`besoins.compte_id`) ;
- aucun lien contact **actif** (`contact_compte.date_fin is null`). Les liens clos sont archivés et supprimés avec le compte (cas FDJ United) ;
- message de refus parlant : « Ce compte a encore 3 contacts rattachés et 1 besoin : déplace-les d'abord vers le bon compte, puis réessaie. »

Contact :
- pas de statut `Consultant CDI`, `Freelance` ou `Prestataire` (ce sont des personnes de l'effectif ou en mission : la sortie passe par « sortie d'effectif », pas par la suppression) ;
- aucune mission où il est consultant ou référent, aucun besoin où il est contact / candidat / consultant, aucune imputation interco, aucun lien partner ;
- aucune séquence Jules active ou en pause sur lui (`jules.agent_sequences.statut in ('active','paused')`) ; les séquences terminées sont simplement détachées (SET NULL, ancienne valeur archivée) ;
- les enfants archivés puis supprimés : `historique_actions`, `contact_compte`, `besoin_candidats`, `taches` du contact, `session_prospection_contacts`.

Anti-masse :
- une fiche par appel (pas de paramètre `ids`) ;
- quota : un commercial ne peut pas archiver plus de **20 fiches par 24 h** (au-delà : refus, « demande à un admin »). L'admin n'a pas de quota.

Suppression par un admin : archivée en corbeille comme les autres (D1, tranché le 05/11) + une ligne `suppression_admin` dans le journal. Les mêmes garde-fous s'appliquent sauf `p_forcer = true` (admin seul ; les références détachées sont archivées et remises par la restauration).

Retour : `jsonb` { type, id, libelle, archive_id | null, nb_enfants }.

### 2.5 Restauration : `restaurer_fiche(p_corbeille_id)` (admin)

- Réinsère la ligne avec **le même id**, puis les enfants (historique, liens, tâches…) et remet les références détachées.
- Refuse proprement si l'id est repris, si un parent a disparu (ex. le compte d'un lien a lui-même été supprimé : on restaure le contact sans ce lien, et on le signale), ou si la structure de la table a changé depuis (colonne disparue : on ignore la clé, colonne nouvelle : valeur par défaut).
- Marque `restaure_le / restaure_par`, journalise `restauration`.

### 2.6 Purge : `purger_corbeille(p_corbeille_id | p_avant date)` (admin)

- Admin uniquement (ou clé service avec origine `jules`/`builder`).
- Supprime définitivement les lignes visées de la corbeille ; journalise `purge` (id, libellé, nombre), sans contenu.
- Purge automatique à 12 mois (D2) : `purger_corbeille_auto()` (clé service ou superuser), à brancher sur le tick du Mac mini (voir § 7). La purge manuelle par l'admin reste possible avant.

### 2.7 Cohérence avec l'existant

- **Transfert de responsabilité** : même règle (« responsable ou admin »). Pour une fiche d'un membre parti ou sans responsable, le chemin est : l'admin transfère, puis le nouveau responsable supprime (ou l'admin supprime directement).
- **trg_guard_responsable** : non concerné (on n'écrit pas `responsable`).
- **Synchro consultants** : retirée en prod (db/18), aucune interaction. Les contacts consultants sont de toute façon refusés à la suppression.
- **KPI comptes** : comme un compte avec missions est refusé, on ne fait plus perdre de CA en silence (aujourd'hui, `SET NULL` sur `missions.compte_id`).
- **Doublons** : la suppression ne remplace pas une fusion. Le flux « doublon » reste : déplacer contacts / besoins / missions vers le bon compte, puis supprimer le compte vide. Un vrai outil de fusion en un clic est hors périmètre (ticket à part si besoin).

---

## 3. Surfaces

### 3.1 App CRM

- Bouton **Supprimer** sur la fiche compte : visible si admin **ou** `compte.responsable === profile.nom` (aujourd'hui admin seulement). Caché au partner.
- Modale de confirmation (on réutilise `ConfirmDeleteCompteModal`, texte revu) :
  - commercial : « Le compte sera retiré du CRM et gardé en archive. Un admin pourra le remettre en place. » + champ motif facultatif (pré-rempli « Doublon » si on vient d'un déplacement de contacts, optionnel) ;
  - admin : « Suppression définitive (sans archive). » ;
  - si un garde-fou bloque, le message de la base est affiché tel quel (il dit quoi faire).
- Contact : `handleDelete` remplacé par **un seul** appel `sb.rpc('supprimer_fiche', …)`. Plus de suppressions en cascade côté navigateur.
- Contrôle du résultat : on affiche « supprimé » seulement si la fonction a renvoyé l'id (fin des faux succès).
- Lot 4 éventuel : une page « Corbeille » visible des seuls admins (liste, restaurer, purger). Pas indispensable : Jules et le MCP couvrent le besoin.

### 3.2 Connecteur MCP (8.34.0 → 8.35.0, source sur le mini)

- `crm_delete_compte`, `crm_delete_contact` : réécrits pour appeler `rpc/supprimer_fiche` (fin du détachement préalable et du faux succès). Paramètre `motif` facultatif. Origine `mcp`.
- Nouveaux outils admin (le refus est porté par la base, l'outil se contente de relayer) :
  - `crm_corbeille_lister` (filtres type, responsable, période) ;
  - `crm_corbeille_restaurer` (un id) ;
  - `crm_corbeille_purger` (un id, ou « avant date »), avec confirmation explicite dans la description de l'outil.
- Lot 3 : `crm_delete_besoin`, `crm_delete_mission` passent aussi par la fonction.
- Tests node sur le mini (comme les 198 existants), `manifest.json` 8.35.0, build = re-zip, sauvegardes `*.bak*`. L'installation dans l'orga Claude (désinstaller puis ré-ajouter) n'est nécessaire que pour les humains qui utilisent le connecteur.

### 3.3 Jules

- Verbe Jules « vider la corbeille / remettre une fiche » réservé à Nicolas : appelle `purger_corbeille` / `restaurer_fiche` avec la clé service et `p_origine = 'jules'`, après confirmation de Nicolas dans Slack. Optionnel au lot 1 (le builder peut le faire en SQL).
- Jules ne supprime **pas** de fiche pour un commercial de lui-même : il peut proposer, le commercial confirme dans l'app ou via le connecteur.

---

## 4. Plan de livraison

Chaque livraison est indépendante et utile seule. SQL en 3 blocs (diagnostic → apply transactionnel avec tests intégrés → vérification) + rollback dédié, joués d'abord sur la **base jetable** du mini (`bin/macmini/base-jetable.sh`, structure de prod sans données) puis en prod via le lanceur habituel. App : preview locale, OK de Nicolas, puis push `main`. Numéro de migration : le prochain libre au moment du chantier (aujourd'hui `db/60`).

### L1 — Base : corbeille + suppression comptes et contacts (la plus petite utile)

Fichiers `db/60_suppression_archive_1_diagnostic.sql`, `_2_apply.sql`, `_3_verif.sql`, `_rollback.sql` :
- tables `corbeille`, `corbeille_journal` (RLS, lecture admin, aucune écriture directe) ;
- fonction `supprimer_fiche` pour `compte` et `contact` ;
- fonction `purger_corbeille` ;
- politique `delete_contacts` réduite à l'admin (les commerciaux passent par la fonction). `comptes_delete_admin` inchangée.
- Tests intégrés (annulés, tout ou rien) : commercial supprime son compte vide → archive + liens clos archivés ; refus compte d'un collègue ; refus compte avec mission / besoin / contact actif ; refus fiche sans responsable ; contact supprimé → historique dans l'archive ; refus contact consultant ou en séquence active ; DELETE direct d'un commercial sur contacts → 0 ligne ; admin → pas de corbeille, une ligne de journal ; quota 21e suppression refusée ; partner refusé ; sans session refusé ; purge par commercial refusée.
- Effet de bord à annoncer : tant que L2 n'est pas en ligne, le bouton « supprimer un contact » de l'app échoue pour un commercial (il appelle le DELETE direct). **L1 et L2 partent donc le même jour**, L1 d'abord, L2 dans l'heure. Alternative si on veut découpler : garder `delete_contacts` ouverte en L1 et la fermer en L2.

### L2 — App : bouton compte + suppression contact par la fonction

- `CompteSidebar` : bouton visible au responsable ; modale revue ; appel `rpc`.
- `ContactDetail.handleDelete` : un seul appel `rpc`.
- Vérification : preview locale + Playwright (smoke) : connexion commercial de test (`bin/macmini/membre-test.py`), compte vide de test → suppression OK et compte absent de la liste ; compte avec contact actif → message de refus affiché ; compte d'un collègue → pas de bouton ; console sans erreur Babel.

### L3 — Connecteur MCP 8.35.0

- `crm_delete_compte` / `crm_delete_contact` via la fonction (corrige le faux succès) ; outils admin `crm_corbeille_lister` / `crm_corbeille_purger`.
- Tests node + re-zip.

### L4 — Restauration

- `db/61` : `restaurer_fiche` (+ tests : restaurer un contact rétablit historique et liens, même id ; refus si id repris).
- MCP `crm_corbeille_restaurer` ; verbe Jules si souhaité.
- Avant L4, une restauration reste possible à la main par un builder (le JSON contient tout).

### L5 — Besoins, missions, tâches

- `supprimer_fiche` étendue à `besoin`, `mission`, `tache` ; politiques DELETE directes réduites à l'admin.
- Garde-fous mission : un commercial ne supprime qu'une mission `New` sans aucun jour saisi ni période ; jamais une mission `En cours` ou `Terminée` (CA). Besoin : refus s'il a une mission rattachée.
- App (3 écrans) + MCP (`crm_delete_besoin`, `crm_delete_mission`) + tests.

### L6 — Optionnels

- Page « Corbeille » admin dans l'app.
- Purge automatique au-delà de la rétention choisie (tâche horaire du mini, `~/bin/taches.txt`).

---

## 5. Risques

- **Fermer le DELETE direct casse un appelant oublié** (script, ancien .mcpb chez un membre). Parade : recherche de tous les `.delete()` / `sbDelete` sur ces tables avant L1 (app, MCP, `~/Pro/Jules/bin`), message d'erreur explicite.
- **Anciennes versions du connecteur** installées chez des membres : elles feront des DELETE directs refusés (0 ligne) et pourront encore annoncer un faux succès jusqu'à la mise à jour. Parade : L3 rapidement après L1, et un trigger BEFORE DELETE de garde qui **lève une erreur** (au lieu de 0 ligne silencieuse) quand un non-admin tente un DELETE direct.
- **Taille de l'archive** : un contact pèse au plus quelques dizaines de lignes d'historique ; négligeable.
- **Données personnelles** : la corbeille garde des données de personnes supprimées ; d'où une rétention à fixer (D2) et une lecture réservée à l'admin.
- **Références Jules sans clé** (vivier, partages) qui pointent dans le vide après suppression : sans effet bloquant, réparé par la restauration (même id).

---

## 6. Décisions (tranchées par Nicolas le 05/11 : D1 archiver aussi, D2 12 mois auto + manuel, D3 oui, D4 oui, D5 refuser)

- **D1. Suppression faite par un admin** : vraiment définitive comme tu l'as dit (seule une ligne de trace sans contenu), ou archivée aussi par sécurité (même coût, et tu pourrais la purger tout de suite) ? Reco : archiver aussi, pour pouvoir rattraper une erreur de manipulation, y compris par Jules.
- **D2. Durée de conservation de la corbeille** : purge uniquement à ta main, ou automatique au bout de X mois ? Reco : 12 mois automatique, purge manuelle possible avant.
- **D3. Périmètre du lot 1** : comptes + contacts, avec fermeture immédiate de la suppression directe des contacts (aujourd'hui un commercial efface un contact et tout son historique sans trace) ? Reco : oui. Les besoins, missions et tâches suivent en L5.
- **D4. Fiche sans responsable (100 comptes) ou d'un membre parti** : seul un admin peut la supprimer (ou la transférer d'abord à quelqu'un) ? Reco : oui.
- **D5. Compte qui a encore des contacts rattachés** : refuser tant qu'ils ne sont pas déplacés (comme a fait Anne-Claire), ou les détacher automatiquement en archivant les liens ? Reco : refuser (on ne perd pas un rattachement par erreur).

Points tranchés par défaut (à contredire si besoin, non bloquants) : le partner ne supprime rien ; quota de 20 suppressions par commercial et par 24 h ; Jules et les builders agissent sur la corbeille avec la clé service, au nom de l'admin, origine tracée.

---

## 7. Réalisation L1 + L2 (05/11, builder) — état et mode d'emploi

Branche `feat/suppression-corbeille` (worktree `.claude/worktrees/suppression-corbeille`), non poussée.

### Ce qui a été fait (écarts à la conception ci-dessus)
- **Restauration livrée dès L1** (`restaurer_fiche`, prévue en L4) : demandée dans la mission, testée.
- Signature : `supprimer_fiche(p_type text, p_id text, p_motif text, p_origine text, p_forcer boolean)` ; `p_id` en **texte** pour couvrir plus tard besoins (uuid) et tâches (texte). L'app envoie `String(id)`.
- Garde `trg_garde_suppression_directe` (niveau instruction) sur `contacts` et `comptes` : un DELETE direct d'un utilisateur connecté non admin lève une **erreur** claire (au lieu des 0 lignes silencieuses). Exemptés : postgres, supabase_admin, service_role (Jules, scripts de fusion de doublons, crm-sql.sh) et la fonction elle-même. L'admin garde le DELETE direct (non archivé : à fermer au lot 3 quand le connecteur passe par la fonction).
- Politiques DELETE des enfants (`historique_actions`, `taches`, `besoin_candidats`) **inchangées** : l'appli s'en sert pour supprimer un besoin ou une tâche (lot 5). `contact_compte` était déjà admin seul.
- Purge auto : `purger_corbeille_auto()`, **aucune planification créée**. Ligne à ajouter dans `~/bin/taches.txt` du mini quand Nicolas le décide :
  `03:40 tous /opt/homebrew/bin/docker exec supabase-db psql -U supabase_admin -d postgres -tAc "select public.purger_corbeille_auto()"`
- App : bouton Supprimer sur compte et contact visible pour le responsable (commercial) et l'admin, caché au partner et sur les fiches des collègues ; modale `ConfirmSuppressionModal` (motif facultatif, avertissements calculés côté appli, message de refus de la base affiché tel quel) ; « supprimé » annoncé seulement si la base renvoie l'id. `contact_compte` chargé avec `date_fin` (liens clos non comptés).

### Ordre de mise en ligne (pour que rien ne casse)
1. Bloc 1 (diagnostic, lecture seule) en prod, relire les attendus.
2. **Pousser l'appli (L2) d'abord** sur `main`. Tant que L1 n'est pas en base, le bouton Supprimer affiche « fonction introuvable » : rien n'est supprimé.
3. Dans la foulée (quelques minutes) : bloc 2 (apply, 19 notices OK attendues), puis bloc 3 (vérif).
4. Demander à l'équipe de **recharger la page** : un onglet resté sur l'ancienne appli efface l'historique du contact avant d'être bloqué sur la suppression du contact (comportement d'avant, sans archive : pas une régression, mais à éviter).
Pourquoi pas L1 d'abord : l'ancienne appli supprime l'historique, les candidatures et les tâches d'un contact AVANT le contact ; avec L1 en place, le contact serait refusé mais son historique déjà perdu.

### Retour arrière
Revert du commit de l'appli puis `db/60_suppression_archive_rollback.sql` (sauvegarde la corbeille dans `_corbeille_bak_60`).

### Ce que L1 impose au connecteur MCP 8.34.0 (lot 3)
- `crm_delete_contact` appelé par un commercial (lu sur le mini, l. 1207-1223) : il remet d'abord `id_prospect = NULL` sur tout l'historique du contact et `contact_id = NULL` sur ses tâches, tente de supprimer ses liens comptes (refusé en silence, admin seul), PUIS supprime le contact. Avec L1, ce dernier DELETE lève l'erreur « Suppression directe fermée… » : le contact reste, mais **son historique et ses tâches sont déjà décrochés** (même dégât qu'avant L1, où le contact partait avec). Réécriture L3 : un seul `rpc/supprimer_fiche` (origine `mcp`). En attendant : consigne à l'équipe (et à Jules en session membre, qui utilise le même jeton de commercial) de ne pas supprimer par Claude.
- `crm_delete_compte` appelé par un commercial : il remet d'abord `compte_id = NULL` sur les besoins et missions du compte (toujours permis par db/09), PUIS le DELETE lève l'erreur. Le compte reste, mais ses missions et besoins sont décrochés : **bug toujours présent tant que L3 n'est pas livré** (il ne ment plus, il échoue ; le décrochage reste). Réécriture : un seul appel `rpc/supprimer_fiche`, sans détachement préalable.
- Admin (Nicolas, Pierre) via 8.34 : DELETE direct toujours permis, donc **sans corbeille** jusqu'à L3.
