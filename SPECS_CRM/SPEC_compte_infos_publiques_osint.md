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

## 3. Alimentation — ancrée sur la fiche VAULT (pivot 27/08, décision Nicolas)
Un script API aveugle par NOM s'est révélé **trop peu fiable** sur les grands comptes
(homonymes : Accor→PME belge/Nouméa, AFD→Roure ; holdings de groupe = peu de salariés
directs + comptes consolidés absents → un homonyme opérationnel gagne). Le champ `ville`
du CRM est majoritairement vide → inutilisable comme garde-fou. **Décision : l'identité
est confirmée EN AMONT par la fiche compte du VAULT** (source de vérité), puis on fetch
de façon fiable.

- **Outil** `~/Pro/Jules/bin/jules-compte-osint.py` :
  - `--id <compte> --siren <siren>` → **mode fiable** : fetch par SIREN (zéro matching),
    écrit siren/adresse/CA/résultat/(description) + `osint_maj`.
  - `--id <compte> --fields-file <json>` → écrit des champs vérifiés au web (effectifs
    exacts, description, CA de groupe…) que l'API ne donne pas.
  - (le mode batch par NOM subsiste mais est PEU FIABLE → diagnostic seulement, jamais à l'aveugle.)
- **Passe raisonnée (LLM)** portée par la **veille** (`routines/veille-signaux.md`, section
  « Enrichir la fiche compte ») : à chaque compte scanné, confirme identité+SIREN depuis le
  vault (le capitalise si absent), fetch infos de base par SIREN, complète effectifs/CA de
  groupe au web, écrit CRM + reporte dans la fiche vault. Progressif, à la midday-cleanup —
  les plus gros comptes d'abord, le reste au fil des passes.

## 4. News — dans la même passe de veille
- 2-3 actualités récentes/pertinentes par compte, **URL vérifiée** (jules-check-url + WebFetch),
  résumé neutre → `bin/jules-compte-news.py --id <compte> --file news.json` (écrit `news` + `news_maj`).
- **Priorité top 10** = comptes par CA projeté (`crm_list_comptes order=ca_projete`), puis le reste
  au fil de la veille.

## 5. Init « costaud » du top 10 (fait le 27/08)
Pour ne pas partir de zéro : identité confirmée + infos de base (SIREN) + effectifs/description/news
(5 sous-agents web Sonnet, gate URL) écrits sur les 10 comptes au plus gros CA projeté
(EDF, Enedis, Axa France, SNCF Connect & Tech, Bouygues Telecom, Funecap, BNP Paribas ITG,
Accor, Société Générale, Louboutin).

## Déploiement
1. `db/19_compte_osint.sql` collé en SQL Editor (effet immédiat). ✅ fait 27/08.
2. UI testée en local + OK Nicolas AVANT push `main` (Nicolas pousse : `git push` deny-ruled).
3. Scripts + veille : côté `~/Pro/Jules/`. Pas de launchd annuel (l'aveugle est abandonné).

## Hors périmètre
- News hors top 10 à la demande / au clic (page statique — arbitrage 27/08).
- Historique financier multi-années · édition manuelle des news.
