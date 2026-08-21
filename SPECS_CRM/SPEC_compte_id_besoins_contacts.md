# SPEC — Rattachement au compte : texte libre → `compte_id`

Date : 2026-08-21 · Auteur : Jules (builder) · Statut : design validé Nicolas, en implémentation

## But
Remplacer le rattachement « au compte » en **texte libre** (`besoins.compte`, `contacts.groupe`) par
un vrai identifiant, sur le modèle de `missions.compte_id`. Fin des silos par orthographe, des doublons
casse/espace, et du couplage `contacts.groupe → besoins.compte`.

## État de départ (inventaire 20/08)
- `besoins.compte` : texte, 87 libellés, 27 sans fiche compte. **Aucune** colonne `compte_id`.
  Pire : le champ de saisie propose ses suggestions depuis `contacts.groupe` (pas `comptes.nom`), et
  la création recopie `contact.groupe → besoin.compte` (propagation du bruit).
- `contacts.groupe` : texte, 426 libellés, 55 sans fiche (dont non-comptes : « Candidat », « Freelance »).
  MAIS la table de liaison **`contact_compte`** (M:N : `contact_id`, `compte_id`, `role`, `is_primary`)
  existe déjà et sert de lien-compte **pour les seuls statuts Prospect/Client** ; le MCP ne l'alimente jamais
  (il n'écrit que `groupe`) → divergence app/MCP.
- Modèle cible = `missions.compte_id` (FK `comptes.id`, picker `CompteAssocPicker`, zéro texte de secours).

## Décisions (Nicolas, 20-21/08)
1. **Orphelins** : libellé ⇒ vraie entreprise → créer la fiche compte + lier ; non-compte
   (Candidat/Freelance…) → laissé vide. Rapport des créations + cas douteux livré.
2. **Colonnes texte** : supprimées à la fin (compte_id / contact_compte = seule source). Côté contacts,
   la suppression de `groupe` s'accompagne de l'ajout de `contacts.employeur` (cf. déc. 3).
3. **Candidats** : gardent un **employeur en texte libre** (`contacts.employeur`), PAS de compte_id
   (leur employeur n'est pas un compte client Upgrade). Seuls Prospect/Client (+ missions) sont reliés.
4. **Sélecteur** : picker de comptes + bouton **« + créer le compte » inline** (jamais bloquant, fini le texte libre).

## Modèle cible
- **besoins** : `compte_id BIGINT` nullable, FK `comptes(id)`. Picker + inline create. `besoins.compte` supprimée en fin de parcours.
- **contacts** : lien-compte via `contact_compte` (existant) pour Prospect/Client ; `contacts.employeur TEXT`
  pour candidats/consultants ; `contacts.groupe` supprimée en fin de parcours.

## Backfill (SQL idempotent + rapport)
- Normalisation : `trim`, casse, accents (`unaccent`/lower) → match sur `comptes.nom` normalisé.
  Fusionne les doublons d'orthographe (`"BNP ITG "` = `"BNP ITG"`).
- Match certain → lien (`besoins.compte_id` ; `contact_compte` pour Prospect/Client).
- Orphelin « vraie entreprise » → **créer compte** + lier. Non-compte → laissé vide ; si candidat → recopier dans `employeur`.
- Sortie : liste des comptes créés + cas douteux (libellés ambigus) à trancher par Nicolas.
- Pré-requis data : corriger d'abord les fiches contacts 129-134 (LinkedIn d'une autre personne, cf. audit) avant résolution auto.

## App (`index.html`) — points à basculer
- **Besoin** : remplacer `CompteSearchField` (texte, alimenté par `contacts.groupe`) par le **picker comptes**
  + inline create ; supprimer la recopie `groupe→compte` ; lire via `compte_id→comptes.nom` aux ~9 sites
  (saisie 4223/4247/4449/4527 · affichage 4527/4560/4666/5342/5367 · filtre/agrégats 4845/3711/3717/3719).
- **Contact** : Prospect/Client → picker `contact_compte` (déjà là) comme **seul** chemin ; Candidat → champ
  `employeur` ; lire la « société » via `societeOf()` (contact_compte) ou `employeur` aux ~25 sites d'affichage.

## MCP (`upgrade-crm-mcp-src/server/index.mjs`) — la garde
- `crm_create/update_besoin` : accepte `compte` (nom) OU `compte_id` ; **résout** nom→id (crée si vraie
  entreprise, sinon null) ; n'écrit plus de texte libre.
- `crm_create/update_contact` : Prospect/Client → pose le lien `contact_compte` ; Candidat → écrit `employeur`.
  Aligné sur l'app. Bump version + rebuild `.mcpb` (cf. mémoire crm-mcp-bump-rebuild-mcpb).

## AVANCEMENT (maj 21/08)
- ✅ **Phase 1** (db/13) — colonnes `besoins.compte_id` + `contacts.employeur` ajoutées, appliquées en base.
- ✅ **Phase 2 backfill** (db/14 besoins · db/15 employeur · db/16 contact_compte) — appliqué + vérifié :
  besoins **276/276** liés ; contacts **1262/1271** liés (9 « Freelance » junk laissés vides) + employeur rempli ;
  39 comptes créés/consolidés, doublon APRIL fusionné.
- 🔶 **Phase 3** (UI index.html) — EN COURS :
  - **Lot 3a BESOIN — fait, en validation locale (21/08).** Nouveau `CompteCreatablePicker` (recherche
    comptes + « + créer le compte » inline → INSERT `comptes(nom,statut='Prospect')` + dédup par nom normalisé).
    Remplace `CompteSearchField` (qui lisait `contacts.groupe`) à la création (`AddBesoinModal`) et à l'édition
    (`BesoinDetail`). Recopie `groupe→compte` supprimée. Props `comptes`/`compteMap` câblées dans `TabBesoins`+`TabPipe`.
    **Décision de sync (blast radius minimal)** : source de vérité = `compte_id`, MAIS on maintient `besoins.compte`
    (texte) synchronisé = `comptes.nom` à chaque save (le picker écrit id ET nom dans le state du form). Ainsi
    tous les sites de lecture existants (`b.compte` : pipe, mission, badges gamif, recherche, agrégats) restent
    corrects **sans être touchés** — leur migration vers `compteMap` + le `DROP compte` se font en phase 5.
    Ce n'est PAS du texte libre : la valeur vient toujours d'un vrai compte.
  - **Lot 3b CONTACT — fait, validé local (21/08).** `CompteAssocField` Candidat écrit désormais `employeur`
    (mirroir `groupe=employeur` maintenu tant que `groupe` existe → les ~25 affichages qui lisent encore
    `groupe` restent cohérents jusqu'au DROP phase 5). `ContactEditModal`+`AddContactModal` persistent `employeur`.
    `societeOf()` : Candidat → `employeur||groupe` ; Prospect/Client → junction `contact_compte` ; consultants →
    `groupe` (trigger missions, inchangé). Vérifié : champ « Employeur actuel » lit bien `employeur` (Cerbulean=Fiducial).
- ✅ **Phase 4** (MCP) — FAIT (21/08, v8.12.0) : `index.mjs` — helpers `resolveCompteId` (match normalisé
  crm_norm, création auto statut Prospect si absent) + `syncContactCompte`. `crm_create/update_besoin`
  résolvent `compte`→`compte_id` (+ dénormalisation `compte`=nom). `crm_create/update_contact` : Prospect/Client
  → lien `contact_compte` (+ `groupe` dénormalisé) ; Candidat → `employeur` (+ miroir `groupe`). Champ `employeur`
  ajouté à CONTACT_ALLOWED_FIELDS. Bump 8.11→8.12, `.mcpb` reconstruit. `node --check` OK.
  ⚠️ Actif au prochain **redémarrage de session MCP** (Claude Code recharge `index.mjs`) ; pour Claude Desktop
  = réinstaller `upgrade-crm-v8.12.0.mcpb`.
- ⏳ **Phase 5** (db/17) — À FAIRE EN DERNIER : supprimer `besoins.compte` et `contacts.groupe`.
> ⚠️ Tant que la phase 3 n'est pas déployée, l'app tourne sur le TEXTE (`compte`/`groupe`) ; les colonnes
> `compte_id`/`contact_compte`/`employeur` sont remplies mais pas encore lues par l'UI. État stable et sûr.

## Ordre d'exécution (chaque étape : valider local + vérifier l'effet en base + GO Nicolas avant prod)
1. **db/13** — ajouter colonnes `besoins.compte_id` + `contacts.employeur` (nullable, non-cassant). ← 1re migration
2. **db/14** — backfill + rapport (après analyse des données réelles + fix contacts 129-134).
3. **App** — bascule picker + affichages via id (besoins puis contacts).
4. **MCP** — garde de résolution + rebuild.
5. **db/15** — supprimer `besoins.compte` et `contacts.groupe` (EN DERNIER, quand plus rien ne les lit).

## Hors périmètre (YAGNI)
- Pas de refonte de `contact_compte` (M:N conservé tel quel). Pas de fusion massive de comptes existants au-delà
  des doublons d'orthographe rencontrés au backfill. Pas de nouveau modèle d'historique.

## Critères de succès
- Saisir un besoin/contact sans jamais taper un nom de compte en texte libre (picker + inline create).
- `besoins.compte` et `contacts.groupe` supprimées ; tout l'affichage passe par `compte_id`/`contact_compte`/`employeur`.
- App web et MCP produisent le même état relationnel pour un même objet.
- Vérif base après chaque migration (pas de FK orpheline, backfill complet hors cas laissés vides volontairement).
