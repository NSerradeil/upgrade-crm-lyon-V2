# Déploiement — Upgrade CRM Lyon V2

Runbook du déploiement. **À lire avant tout déploiement** (créé le 2026-06-27, après avoir
constaté qu'aucune doc n'existait).

## Architecture en couches (tout n'a pas besoin d'un « déploiement »)

| Couche | Où ça vit | Comment ça devient « live » |
|---|---|---|
| **Données** | Supabase (PostgreSQL + PostgREST + RLS) | **Immédiat.** Toute écriture (app, MCP, SQL Editor) est live tout de suite. Aucun commit/déploiement. |
| **Schéma DB** (tables, RLS, migrations) | Supabase, géré **à la main** | Coller le SQL de `db/*.sql` dans **Supabase → SQL Editor → Run**. Les fichiers `db/` sont versionnés pour la traçabilité, mais ne s'appliquent PAS tout seuls. |
| **App web** (`index.html`, PWA mono-fichier) | GitHub Pages | **Push sur `main`** → workflow `pages-build-deployment` rebuild auto. URL : https://nserradeil.github.io/upgrade-crm-lyon-V2/ |
| **Serveur MCP** (`../upgrade-crm-mcp-src/server/index.mjs`) | Local, **PAS un dépôt git** | Sauver le fichier ; le process MCP le charge au (re)démarrage de la session Claude. Rien à pousser. |

### Notes de version — Serveur MCP
- **8.20.0 (18/09/2026)** : `agent_event_list` — lecture filtrée du journal `agent_events` (mission_id/task_id/sequence_id, kinds, since/until, limit≤500), en complément d'`agent_event_log` (écriture) et `agent_status` (derniers N tous sujets). Sert au brief (envoyés hier, acceptations, alertes quota) et à tout récap de campagne.
- **8.19.0 (18/09/2026)** : garde anti-doublon de missions — `agent_mission_create` (kind=oneshot) refuse de créer une mission proche d'une mission existante (surtout done/cancelled) et propose de la rouvrir ; `force:true` pour créer quand même. Nouveau fichier `server/agent-similar.mjs` (normalizeTitle/similarity/findSimilar).
- **8.18.0 (17/09/2026)** : outils MCP `agent_*` (noyau d'état Jules) — fichier `server/agent-tools.mjs`.

### Migrations à appliquer (en ordre)
- `db/20_agence.sql` — onglet Agence : colonnes collaborateur sur `contacts` (date_entree, date_sortie, salaire_annuel, cjm_manuel, statut_rh, statut_rh_depuis, type_presta, manager_trigramme), `profiles.partner_lead`, `is_my_consultant()` élargi. **À appliquer AVANT de pousser l'app** (le `select` de `fetchAll` référence les nouvelles colonnes → 400 sinon).
- ⚠️ `agence-calc.js` doit être poussé AVEC `index.html` (dépendance dure du shell : 404 = écran blanc).
- `db/47_domaine_task_types.sql` (22/09/2026) — colonne `agent_task_types.domaine` (linkedin/plateformes/autre) : permet au scheduler Jules de paralleliser les taches navigateur par domaine au lieu d'un verrou global (`bin/jules-scheduler.py`). A appliquer avant de deployer le scheduler cote domaine — sans elle, `agent_task_types.domaine` est absent et le scheduler retombe sur le comportement « un seul domaine a la fois » (safe, mais pas de gain de parallelisme).

- 🔴 `db/48_agent_sequences_pause.sql` (23/09/2026) — statut `paused` + colonne `resume_at` sur `agent_sequences`, et fonction `agent_sequences_reprendre_dues()` (fin de pause automatique). **À appliquer AVANT de pousser l'app** : sans elle, le bouton ⏸ de la barre de transport des personnes suivies échoue sur la contrainte `agent_sequences_statut_check` (message d'erreur propre, rien de cassé, mais la pause est inopérante) et l'appel RPC de reprise est ignoré en silence.

## Déployer l'app (le seul vrai « déploiement »)

GitHub Pages sert depuis **`main`**, path `/`. ⚠️ **Toujours partir de `origin/main` à jour** :
le repo reçoit des commits « staging: preview CRM » fréquents — une branche locale vieille
de quelques jours peut être loin derrière (piège vécu le 27/06 : base périmée de 32 commits).

```bash
cd upgrade-crm-lyon-V2
git fetch origin && git checkout main && git reset --hard origin/main   # repartir de la prod À JOUR
# ... appliquer les changements sur index.html ...
git add index.html db/ DEPLOY.md
git commit -m "..."
git push origin main                  # déclenche pages-build-deployment
```

⚠️ `git reset --hard` **supprime les fichiers non encore commités** (db/, etc.) — committer ou
sauvegarder AVANT. (Autre piège vécu le 27/06.)

Build : ~1-2 min. Suivre : `gh run list --repo NSerradeil/upgrade-crm-lyon-V2 --limit 3`.

### 🔴 RÈGLE (Nicolas, 29/06) : LOCAL D'ABORD, JAMAIS DE PUSH DIRECT EN PROD
Tout changement de `index.html` se valide **en local AVANT le push sur `main`** :
1. servir en local (`python3 -m http.server`), ouvrir l'app, vérifier visuellement le changement ;
2. **soumettre la preview à Nicolas** (URL localhost ou screenshot) et **attendre son OK** ;
3. **seulement après**, `git push origin main` (= prod, live immédiat).
Il n'y a pas de staging GitHub Pages (Pages ne sert que `main`) → la preview locale EST l'étape de validation.

### Vérifier AVANT de pousser (pas de tests auto)
Aucun framework de test. `index.html` est un mono-fichier React compilé par **Babel standalone
en navigateur** → une erreur de syntaxe JSX casse TOUTE l'app (écran blanc). Donc avant push :
```bash
python3 -m http.server 8799    # dans upgrade-crm-lyon-V2/
# ouvrir http://localhost:8799/index.html, vérifier la console :
#   - une SyntaxError / "Unexpected token" Babel = FATAL, ne pas pousser
#   - la note "[BABEL] code generator has deoptimised ... exceeds 500KB" = bénigne (normale)
# confirmer que la page de connexion s'affiche (React monté).
```

### ⚠️ Cache service-worker (PWA)
`service-worker.js` met l'app en cache. Après un déploiement, un simple refresh ne suffit pas
toujours : **hard refresh** (Cmd+Shift+R) ou recharger 2×. PWA installée sur mobile : fermer/rouvrir.

## Staging (convention historique)

Une branche `staging` existe + des commits « staging: preview CRM (timestamp) » faits à la main.
Un SPEC mentionne `bash supabase/deploy_staging.sh` (règle « staging uniquement, jamais main »)
**mais ce script n'existe pas dans le repo** (référence morte). Pas de pipeline staging
automatisé à ce jour, et GitHub Pages ne déploie que `main`.

## Règle projet
Pas de commit/push sans demande explicite de Nicolas.
