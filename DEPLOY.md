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
