# SPEC — Infos publiques compte (fiche société auto-enrichie)

Date : 2026-08-27 · Demande : Nicolas · Statut : validé (design GO)

## Objectif
Populer l'onglet **Infos** de la fiche compte avec des données publiques (mode OSINT,
sans jamais afficher le mot « OSINT ») : adresse, site web (déjà présent), effectifs,
CA, résultat net, description, + un encart **Actualités** (2-3 news résumées avec lien
source). Alimenté automatiquement par des workers Jules, éditable manuellement en secours.

## Arbitrages tranchés (Nicolas, 27/08)
- **Pas de rafraîchissement « à la volée » au clic** (le CRM est une page statique, pas de
  backend pour lancer un worker). On se limite à : **batch annuel** (infos de base, tous
  comptes) + **veille hebdo** (news, top 10 comptes par volume d'affaires Upgrade).
  Hors top 10 : pas de news auto en V1.
- **Source infos de base** : `recherche-entreprises.api.gouv.fr` (officiel, gratuit) en
  principal ; **le web (LLM) ne complète que les trous** (typiquement les groupes type EDF
  en comptes consolidés que l'API ne couvre pas).
- **CA / résultat net** : on stocke **la valeur la plus récente disponible** (n-1, sinon
  n-2, sinon n-3) **avec son année**. Pas d'historique 3 ans.
- **UI** : on enrichit l'onglet **Infos** existant (pas de nouvel onglet, pas de libellé
  « OSINT »), juste des champs propres : effectifs, CA, résultat, adresse, description, news.

## 1. Schéma DB — `db/19_compte_osint.sql`
Colonnes ajoutées à `comptes` (toutes nullable, `IF NOT EXISTS`) :
- `siren` text — clé de rapprochement API
- `adresse` text — siège
- `description` text — présentation courte (activité)
- `effectifs` integer · `effectifs_annee` integer
- `ca` bigint (€) · `ca_annee` integer
- `resultat_net` bigint (€) · `resultat_annee` integer
- `news` jsonb — `[{titre, resume, url, date}]` (default `'[]'::jsonb`)
- `osint_maj` date — dernier rafraîchissement infos de base
- `news_maj` date — dernier rafraîchissement news

RLS : ces colonnes suivent les policies existantes de `comptes` (lecture ouverte, écriture
verrouillée). Les workers écrivent via `CRM_PG_URL` (connexion Postgres directe, bypass RLS),
donc aucune policy additionnelle nécessaire. À appliquer par collage en SQL Editor.

## 2. UI — onglet Infos (`index.html`, bloc `activeTab==='infos'`)
Sous les champs actuels (secteur / ville / site / notes), ajouter — chaque bloc masqué si vide :
- **Chiffres clés** : Effectifs (`effectifs` + `(effectifs_annee)`), CA (`ca` formaté €,
  `(ca_annee)`), Résultat net (`resultat_net`, `(resultat_annee)`), Adresse.
- **Description** : texte 2-3 lignes.
- **Actualités** : liste de `news` — pour chaque item, titre + résumé court + lien source
  cliquable (`target=_blank`), date. Style aligné sur les autres blocs (labels `text-[10px]
  uppercase`). Note discrète « maj le <osint_maj> / <news_maj> » en bas.
Formatage montants : helper `fmtEuros` (k€ / M€ lisibles).

Formulaire compte (`CompteFormModal`) : ajouter les champs éditables (effectifs, ca,
ca_annee, resultat_net, resultat_annee, adresse, description, siren) pour correction manuelle.
`news` reste géré par les workers (pas d'édition manuelle en V1). Les nouveaux champs
numériques → `null` si vide dans le payload.

## 3. Worker infos de base — annuel · `~/Pro/Jules/bin/jules-compte-osint.py`
- Script **pur API** (pas de LLM) : pour chaque compte sans `osint_maj` récent, requête
  `recherche-entreprises.api.gouv.fr/search?q=<nom>` → meilleur match → SIREN, adresse,
  effectifs (tranche+année), activité (→ description), et `finances` (CA + résultat net par
  année si l'entité dépose ses comptes) → on prend l'année la plus récente.
- Écrit dans `comptes` via `psql "$CRM_PG_URL"` (source `~/.config/jules/crm-backup.env`),
  set `osint_maj = today`.
- **Trous** (pas de match fiable, ou groupe sans finances : EDF, SNCF…) → log dans un
  fichier `comptes-osint-trous.txt` ; une passe web légère Jules (session LLM) les complète
  ensuite. Le script ne devine jamais.
- launchd : 1×/an (mi-janvier). Lançable à la demande.
- Garde-fous : rapprochement par nom risqué (homonymes) → n'écrit que si le match est net
  (nom normalisé proche + une seule entité dominante) ; sinon → trou. Ne jamais écraser une
  valeur saisie manuellement plus récente que le dernier run automatique (comparer `osint_maj`).

## 4. News — skill Jules hebdo (top 10)
- **Top 10** = comptes par volume d'affaires Upgrade = somme du CA missions (périodes ×
  TJM/CJM) par compte. Métrique à confirmer ; fallback = nb missions actives.
- Skill de veille (déjà hebdo chez Jules) : pour chacun des 10 comptes, recherche web
  2-3 actualités récentes et pertinentes (levée, réorg, nouveau produit, recrutement, résultats),
  résumé court + URL source, écrit `news` (JSONB) + `news_maj` via `CRM_PG_URL`.
- Chaque news porte une **URL source vérifiée** (règle veille Jules) ; résumé neutre.

## Déploiement
1. `db/19_compte_osint.sql` collé en SQL Editor (effet immédiat).
2. UI testée en local (`python3 -m http.server`) + preview + OK Nicolas AVANT push `main`
   (Nicolas pousse : `git push` deny-ruled pour Jules).
3. Worker + skill : livrés côté `~/Pro/Jules/`, branchés en launchd / veille.

## Hors périmètre V1
- News hors top 10 (pas de déclenchement au clic).
- Historique financier multi-années.
- Édition manuelle des news.
