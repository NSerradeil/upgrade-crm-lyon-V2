# Onglet Jules « Cockpit » — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refondre l'onglet Jules du CRM en un cockpit lisible (accueil + cartes couleur/volet, frise du jour, table missions Nature/Type) avec renvois 360 Slack.

**Architecture:** App = `index.html` mono-fichier, React via Babel-standalone navigateur (pas de build). Données = Supabase (vues `agent_v_*`), schéma appliqué **à la main** dans SQL Editor (fichiers `db/*.sql` = traçabilité). 360 = pont Slack Python (`~/Pro/Jules/bin/`) + playbooks (`~/Pro/Jules/routines/`). Pas de framework de test UI : vérif = `node tests/check-babel.mjs` (le JSX parse) + smoke live sur GitHub Pages.

**Tech Stack:** PostgreSQL/PostgREST (Supabase), React 18 + Babel standalone (inline), Python 3 (pont Slack), Slack API.

**Spec:** `docs/superpowers/specs/2026-09-21-onglet-jules-cockpit-design.md`

## Global Constraints

- **DA néo-brutaliste** : bords `2px solid`, ombres dures `4-5px 0`, police `Outfit`, palette `JULES_*` (déjà définie L7328-7335). Chiffres en `IBM Plex Mono`.
- **On travaille AUTOUR de la feature « ajuster/appro »** (`JulesAjuster` L8050, `julesActions.ajuster`). Ne pas réécrire ce geste ; le réutiliser. CRM-UI ne démarre qu'après merge de cet agent (un seul implémenteur sur la zone TabJules de `index.html`).
- **Egress Supabase** : `select` de colonnes ciblées, jamais `select('*')` élargi sans valider les colonnes vs schéma.
- **Déploiement** : SQL → coller dans Supabase SQL Editor (live immédiat) ; app → push `main` → GitHub Pages. « Testé en réel » = déployé et vérifié sur https://nserradeil.github.io/upgrade-crm-lyon-V2/.
- **Vues `security invoker`** (cf. `db/29`) : toute nouvelle vue est créée en `security_invoker=on` pour respecter la RLS.
- Le composant `TabJules` lit ses données lui-même (profils `jules_enabled`), `fetchAll` n'est pas touché.

---

## Sous-projet CRM-DATA (db/) — non bloqué, à faire en premier

### Task 1 : Colonne `critique` sur `agent_approvals` + exposition parapheur

**Files:**
- Create: `db/34_agent_approval_critique.sql`
- Modify (référence, la vue est recréée dans le fichier) : `agent_v_parapheur` (déf. d'origine `db/25_agent_noyau.sql:209`)

**Interfaces:**
- Produces: `agent_v_parapheur` gagne la colonne `critique boolean`. L'UI lira `critique`.

- [ ] **Step 1 : Écrire la migration**

```sql
-- db/34_agent_approval_critique.sql
-- Criticité explicite d'une approbation (défaut : non critique). L'UI colore en rouge et
-- remonte en tête ; un filet côté UI bascule aussi sur l'âge (voir spec §5.1).
alter table public.agent_approvals
  add column if not exists critique boolean not null default false;

create or replace view public.agent_v_parapheur as
  select id, nature, titre, detail, options, task_id, critique, created_at
    from public.agent_approvals
   where statut = 'pending'
   order by critique desc,
            case nature when 'bloque' then 0 when 'decision' then 1 else 2 end,
            created_at;
alter view public.agent_v_parapheur set (security_invoker = on);
```

- [ ] **Step 2 : Appliquer dans Supabase SQL Editor** (coller le fichier, Run).

- [ ] **Step 3 : Vérifier**

Run (SQL Editor) :
```sql
select column_name from information_schema.columns
 where table_name = 'agent_approvals' and column_name = 'critique';
select id, critique from public.agent_v_parapheur limit 5;
```
Expected : la colonne existe ; la vue renvoie `critique` sans erreur.

- [ ] **Step 4 : Exposer `critique` au MCP** — vérifier que `agent_approval_create` (serveur MCP `../upgrade-crm-mcp-src/server/index.mjs`) accepte/écrit `critique`. Si non, ajouter le champ optionnel (défaut false) et redémarrer la session MCP.

- [ ] **Step 5 : Commit**

```bash
git add db/34_agent_approval_critique.sql
git commit -m "feat(db): criticité explicite des approbations, exposée au parapheur"
```

### Task 2 : Vue `agent_v_journee` (frise du jour)

**Files:**
- Create: `db/35_agent_v_journee.sql`

**Interfaces:**
- Produces: vue `agent_v_journee` — une ligne par occurrence cyclique **prévue aujourd'hui**, colonnes : `mission_id uuid, titre text, prevu_at timestamptz, etat text` avec `etat ∈ {done,running,failed,pending}`. L'UI place les pins par `prevu_at` et colore par `etat`.

- [ ] **Step 1 : Écrire la migration**

```sql
-- db/35_agent_v_journee.sql
-- Les passages cycliques du jour et leur état résolu. Une mission recurring a une cadence
-- {"days":[1..7],"times":["07:00","16:00"]} (jours ISO lundi=1). On déplie les times du jour
-- si le jour ISO courant est dans days, puis on rattache la tâche du jour (même mission,
-- même date) pour résoudre l'état.
create or replace view public.agent_v_journee as
with occ as (
  select m.id as mission_id, m.titre,
         (current_date + (t.time)::time) as prevu_at
    from public.agent_missions m
    cross join lateral jsonb_array_elements_text(m.cadence->'times') as t(time)
   where m.kind = 'recurring' and m.statut = 'active'
     and (
       m.cadence->'days' is null
       or (extract(isodow from current_date)::int) in (
            select (d)::int from jsonb_array_elements_text(m.cadence->'days') as d
          )
     )
),
tache_du_jour as (
  select distinct on (mission_id, date_trunc('day', due_at))
         mission_id, due_at, statut
    from public.agent_tasks
   where due_at >= current_date and due_at < current_date + interval '1 day'
   order by mission_id, date_trunc('day', due_at), due_at desc
)
select o.mission_id, o.titre, o.prevu_at,
       case
         when td.statut = 'done'                              then 'done'
         when td.statut in ('claimed','waiting_go')           then 'running'
         when td.statut = 'failed'                            then 'failed'
         else 'pending'
       end as etat
  from occ o
  left join tache_du_jour td
    on td.mission_id = o.mission_id
   and td.due_at >= o.prevu_at - interval '90 min'
   and td.due_at <  o.prevu_at + interval '90 min'
 order by o.prevu_at;
alter view public.agent_v_journee set (security_invoker = on);
```

- [ ] **Step 2 : Appliquer dans Supabase SQL Editor.**

- [ ] **Step 3 : Vérifier**

```sql
select * from public.agent_v_journee order by prevu_at;
```
Expected : une ligne par (mission recurring active dont le jour ISO tombe aujourd'hui × heure de cadence), avec `etat` cohérent (les passages passés sans tâche done → `pending`/`failed` selon la tâche rattachée).

- [ ] **Step 4 : Commit**

```bash
git add db/35_agent_v_journee.sql
git commit -m "feat(db): vue agent_v_journee — passages cycliques du jour et leur état"
```

---

## Sous-projet CRM-UI (index.html) — DÉMARRE APRÈS MERGE DE L'AGENT « AJUSTER/APPRO »

> Zone : `TabJules` (L8239) + composants Jules (L7418→8371). Chaque task finit par
> `node tests/check-babel.mjs` (0 erreur = le JSX parse) et un smoke live après push.
> On garde les composants existants réutilisés (`JulesAjuster`, modales de refus/clôture,
> `julesActions`, `useJulesData`) ; on remplace l'ASSEMBLAGE (`TabJules` return) et on ajoute
> les nouveaux sous-composants de présentation.

### Task 3 : Étendre `useJulesData` avec `journee`

**Files:**
- Modify: `index.html` — `useJulesData` (L7349-7365, le `Promise.all` `lire`)

**Interfaces:**
- Consumes: vue `agent_v_journee` (Task 2).
- Produces: `J.data.journee` = tableau `{mission_id, titre, prevu_at, etat}`.

- [ ] **Step 1** : Dans `lire`, ajouter à `Promise.all` :
  `sb.from('agent_v_journee').select('mission_id,titre,prevu_at,etat').order('prevu_at')`
  et l'ajouter au retour (`journee:r[8].data||[]`). Ajouter `jo:` à `empreinte` :
  `jo: d.journee.map(x=>x.mission_id+String(x.prevu_at)+x.etat).sort()`.
- [ ] **Step 2** : `node tests/check-babel.mjs` → 0 erreur.
- [ ] **Step 3** : Commit `feat(jules): useJulesData lit agent_v_journee`.

### Task 4 : Sous-composant `JulesVolet` (drawer latéral)

**Files:**
- Modify: `index.html` — nouveau composant + un peu de CSS (bloc `<style>` Jules).

**Interfaces:**
- Produces: `<JulesVolet ouvert titre onClose>{contenu}</JulesVolet>` + pied d'actions passé en `footer`. Plein écran < 560px, scrim, fermeture Échap/clic-dehors. Réutilisé par les 3 zones.

- [ ] **Step 1** : Écrire `JulesVolet` (panneau droit `min(440px,92vw)`, `transform: translateX`, scrim `position:fixed`). Focus trap minimal + `Escape`.
- [ ] **Step 2** : `node tests/check-babel.mjs`.
- [ ] **Step 3** : Commit `feat(jules): volet latéral réutilisable`.

### Task 5 : Zone « Ce qui t'attend » — cartes couleur + volet

**Files:**
- Modify: `index.html` — refonte de l'affichage parapheur (remplace la liste inline de `JulesParapheur` L7522 par une grille de cartes ; le détail passe dans `JulesVolet`).

**Interfaces:**
- Consumes: `J.data.parapheur` (avec `critique`), `JulesVolet`, `julesActions` (dont `ajuster`).
- Produces: `<JulesParapheur>` rend une grille de cartes ; clic corps → volet.

Règles de couleur (bande gauche 6px) :
- `nature==='go'` → **vert** (`JULES_VERT`), actions Accorder / **Ajuster** (geste existant) / Refuser.
- `nature==='decision' || 'bloque'` → **bleu** (`JULES_BLEU`), action « Trancher » / « Donner l'info » + « Répondre dans Slack ».
- **rouge** (`JULES_ROUGE`) en overlay si `critique === true` **OU** âge > seuil (constante `JULES_SEUIL_CRITIQUE_H = 24`, calculée sur `created_at`) → bande rouge + flag « urgent ».

- [ ] **Step 1** : Écrire la grille de cartes (`grid auto-fill minmax(268px,1fr)`), petites cartes (tag nature, âge, titre, contexte 2 lignes, boutons selon nature). Filtres chips Tout/Échanger/Go-no-go/Critique.
- [ ] **Step 2** : Détail dans `JulesVolet` : ce que Jules attend, contexte/source, texte proposé, encart 360, actions en pied. Le geste « Ajuster » appelle le `onAjuster` existant (pas de réécriture).
- [ ] **Step 3** : `node tests/check-babel.mjs`.
- [ ] **Step 4** : Commit `feat(jules): parapheur en cartes couleur + volet`.

### Task 6 : Zone « Ce qui tourne » — frise du jour + one-shots

**Files:**
- Modify: `index.html` — remplace `JulesEncours` (L7573) par frise (`J.data.journee`) + puces one-shots (`J.data.encours`, avec `heartbeat_age_s>900`).

**Interfaces:**
- Consumes: `J.data.journee`, `J.data.encours`, `J.data.dueToday`, `JulesVolet`.

- [ ] **Step 1** : Frise SVG/DOM 7h→19h : axe + graduations 2h, repère « maintenant » (heure locale), un pin par ligne `journee` positionné par `prevu_at`, coloré par `etat` (done ✓ vert / running ● bleu pulsé / failed ✕ rouge / pending pointillé). `overflow-x:auto` (min-width ~620px). Clic pin → volet (état + encart 360 selon `failed` = action de ton côté, sinon « Jules va t'écrire »).
- [ ] **Step 2** : Sous la frise, puces one-shots depuis `encours` (pouls bleu, rouge si `heartbeat_age_s>900`). `dueToday` (retards/aujourd'hui) conservé sous forme condensée (réutiliser la logique existante retard vs aujourd'hui).
- [ ] **Step 3** : `node tests/check-babel.mjs`.
- [ ] **Step 4** : Commit `feat(jules): ce qui tourne en frise du jour + one-shots`.

### Task 7 : Zone « Missions » — table Nature/Type

**Files:**
- Modify: `index.html` — refonte `JulesMissions` (L7689) / `JulesLigneMission` (L7666) en table.

**Interfaces:**
- Consumes: `J.data.backlog` (porte `kind`, `priorite`), `J.data.campagnes`, `JulesVolet`, `julesPouls`.

Dérivations :
- **Nature** : présent dans `campagnes` (`campaign_id`/vue) → `campagne` ; sinon `kind==='recurring'` → `routine` ; `kind==='oneshot'` → `ponctuel`.
- **Type** (intention) : **pas de champ dédié en base** (cf. spec §3.4 note). V1 : dérivation best-effort depuis `task_type`/`titre` via une petite table de correspondance `JULES_TYPE_MAP` ; « — » si inconnu. (Champ explicite = amélioration future, hors périmètre V1 — voir question ouverte plan.)
- **État** : `julesPouls` existant. **Avancement** : `nb_done/(nb_due+nb_claimed+nb_waiting_go+nb_failed+nb_done)`, barre jaune si `nb_failed>0||nb_waiting_go>0`.

- [ ] **Step 1** : Table (`overflow-x:auto`, min-width ~760px) colonnes Mission·Nature·Type·État·Avancement·Prochaine action (la « prochaine action » = `julesPhrase`). Marqueurs Nature ⟳/◈/•.
- [ ] **Step 2** : Clic ligne → `JulesVolet` mission (journal récent depuis `J.data.events` filtrés `mission_id`, actions Pause/Clôturer/Modifier/Écrire à Jules — réutiliser `julesActions`).
- [ ] **Step 3** : `node tests/check-babel.mjs`.
- [ ] **Step 4** : Commit `feat(jules): missions en table Nature/Type + volet`.

### Task 8 : Assemblage `TabJules` + bandeau d'accueil

**Files:**
- Modify: `index.html` — `TabJules` return (L8270-8368) : remplacer les 3 `JulesBandeau` par bandeau d'accueil (wordmark + phrase de rôle + 3 KPI cliquables) puis les 3 zones (§3.2-3.4). Conserver les modales (`aRefuser`, `aFermer`, `aRepondre`, `aAjuster`, `creation`) telles quelles.

- [ ] **Step 1** : Bandeau d'accueil + KPI (parapheur/encours/backlog counts) qui `scrollIntoView` vers chaque zone.
- [ ] **Step 2** : Câbler les nouvelles zones + le `JulesVolet` (un seul état `volet` {type,payload} ou réutiliser `detailId`).
- [ ] **Step 3** : `node tests/check-babel.mjs`, puis **smoke live** : push `main`, ouvrir la page, vérifier les 3 zones + volet + responsive < 560px.
- [ ] **Step 4** : Commit `feat(jules): assemblage cockpit + bandeau d'accueil`.

---

## Sous-projet 360-WIRING (~/Pro/Jules) — après CRM-UI (dépend du format de deep-link)

### Task 9 : Format de deep-link vers l'onglet

**Files:**
- Modify: `index.html` — au boot, lire `?tab=jules&appro=<id>` (ou `&mission=<id>`) → ouvrir l'onglet Jules et le volet du bon item.

**Interfaces:**
- Produces: URL canonique `…/?tab=jules&appro=<uuid>` et `…/?tab=jules&mission=<uuid>`.

- [ ] **Step 1** : Parser les query params au montage, sélectionner l'onglet Jules, ouvrir le volet ciblé si l'id existe dans `J.data`.
- [ ] **Step 2** : `node tests/check-babel.mjs` + smoke : ouvrir une URL avec `?tab=jules&appro=<id réel>`.
- [ ] **Step 3** : Commit `feat(jules): deep-link vers un item de l'onglet`.

### Task 10 : Boutons « Ouvrir dans Slack » (outil → Slack)

**Files:**
- Modify: `index.html` — cartes/missions : bouton deep-link DM Jules. Slack deep-link `slack://user?team=<T>&id=<botUserId>` (ou l'URL web du DM). Le contexte pré-rempli côté Slack sera posé par le bot (Task 12).

- [ ] **Step 1** : Ajouter le bouton (variante `.btn.sl`) sur cartes « échanger » et lignes mission ; ouvre le DM Jules.
- [ ] **Step 2** : check-babel + smoke.
- [ ] **Step 3** : Commit `feat(jules): boutons Ouvrir dans Slack`.

### Task 11 : Slack → Outil (message contextualisé + lien cockpit)

**Files:**
- Modify: `~/Pro/Jules/bin/jules-say.sh` et/ou le point où Jules dépose une approbation (playbooks `~/Pro/Jules/routines/*`, et le helper qui appelle `agent_approval_create`).

**Interfaces:**
- Produces: quand Jules crée une approbation, le message Slack porte **lead + lien** `…/?tab=jules&appro=<id>` (« la suite est dans le cockpit ») au lieu de re-déballer le détail.

- [ ] **Step 1** : Dans le flux de dépôt au parapheur, après `agent_approval_create`, construire le lien et poster un message Slack court avec le lien.
- [ ] **Step 2** : Test réel : créer une appro de test → vérifier le message Slack + que le lien ouvre le bon volet.
- [ ] **Step 3** : Commit (repo Jules) `feat(360): message Slack renvoie vers le cockpit`.

### Task 12 : Outil → Jules (« Jules va t'écrire ») + DM pré-rempli

**Files:**
- Modify: `~/Pro/Jules/bin/jules-slack-bot.py` — recevoir un « ouvrir DM avec contexte » (le bot poste un message d'amorce dans le DM quand le commercial clique « Répondre à Jules »), et `routines/` (playbook) pour la boucle de réponse.

- [ ] **Step 1** : Définir le mécanisme (le plus simple : le bouton UI ouvre le DM ; un message d'amorce est posté par le bot via un endpoint/param, ou l'amorce est déjà là parce que Jules a posté au dépôt Task 11). Choisir la voie la plus légère qui évite un backend temps réel.
- [ ] **Step 2** : Test réel bout-en-bout : depuis une carte « échanger », cliquer Slack → retrouver le fil contextualisé.
- [ ] **Step 3** : Commit `feat(360): amorce de DM contextualisée`.

---

## Sous-projet FIX-TUYAU — parallélisable

### Task 13 : Réconcilier parapheur ↔ a-valider.md

**Files:**
- Investigate: `~/Pro/Jules/journal/a-valider.md` (vue générée), le générateur de cette vue, `agent_approvals`.

- [ ] **Step 1** : Reproduire le cas « EDF v35 arbitrage » : est-il dans `a-valider.md` sans ligne `agent_approvals pending` correspondante ?
- [ ] **Step 2** : Diagnostiquer — fichier périmé (régénérer) OU approbation jamais créée (le flux qui écrit dans `a-valider.md` doit passer par `agent_approval_create`).
- [ ] **Step 3** : Corriger le tuyau pour que **tout** item mis au parapheur devienne une ligne `agent_approvals` (source unique). Vérifier que l'onglet et `a-valider.md` concordent.
- [ ] **Step 4** : Commit `fix(360): parapheur = source unique, a-valider.md dérive de agent_approvals`.

---

## Self-review (couverture spec)

- §3.1 accueil → Task 8 ✓ · §3.2 cartes/volet → Tasks 4,5 ✓ · §3.3 frise → Tasks 2,3,6 ✓ ·
  §3.4 missions Nature/Type → Task 7 ✓ · §3.5 volet → Task 4 ✓
- §4 renvois 360 → Tasks 9-12 ✓ · §5.1 criticité → Task 1 (+ filet âge Task 5) ✓ ·
  §5.2 frise data → Task 2 ✓ · §5.3 fix tuyau → Task 13 ✓
- **Gap connu remonté** : §3.4 colonne **Type** = pas de champ base ; V1 dérivé (Task 7),
  champ explicite = décision produit à trancher (question ouverte ci-dessous).

## Questions ouvertes

1. **Colonne Type (intention)** : V1 dérivée best-effort de `task_type`/`titre`. Veut-on à
   terme un champ explicite `categorie` sur `agent_missions` (que Jules pose à la création) ?
2. **Seuil âge criticité** : `JULES_SEUIL_CRITIQUE_H = 24` (h calendaires). OK ou autre valeur ?
