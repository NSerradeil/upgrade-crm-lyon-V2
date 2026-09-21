# Onglet Jules — refonte « Cockpit » (V2)

**Date** : 2026-09-21
**Auteur** : Jules (session design, casquette expert)
**Statut** : à valider par Nicolas avant plan d'implémentation
**Maquette validée** : https://claude.ai/artifact/VYMSpQa5nCK6nsMF6hRTMy (V3)

## 1. Problème

L'onglet Jules actuel (`index.html`, `TabJules` ~L8239, composants L7418→8371) empile
**3 bandeaux repliables visuellement identiques** en une seule colonne de texte/listes :
parapheur, en-cours, missions. Constats de Nicolas (capture 21/09) :

1. **On ne comprend pas ce que la page permet.** Un commercial ne voit pas qu'il a là son
   IA d'automation + le suivi de ce qu'elle fait.
2. **Il faut scroller** pour dérouler 3 menus trop similaires.
3. **Pas de lisibilité de l'état réel** : impossible de savoir si un traitement est *fait*,
   *en cours* ou *planté*. Manque de couleur et de vue graphique.
4. **Cartes trop denses** : tout le détail est inline. Il faudrait de **petites cartes**
   avec code couleur (échanger avec l'IA / simple go-nogo / criticité) et le détail dans un
   **volet latéral**.
5. **Pas de 360** avec Slack : quand Jules pose un truc au parapheur côté Slack, l'outil
   doit dire « va voir la suite dans l'outil » ; l'outil doit dire « Jules va t'écrire » ;
   Slack doit porter un message contextualisé.
6. Divergence UI ≠ `a-valider.md` (ex. « EDF v35 arbitrage » présent dans le fichier, absent
   de l'UI) → trou de tuyau à corriger.

## 2. Ce qu'on ne touche pas (garde-fou)

- Un agent travaille en parallèle sur **« Feature ajuster + update appro »**
  (`JulesAjuster` L8050, `julesActions.ajuster`, updates `agent_approvals`). **La refonte
  travaille AUTOUR** : on réutilise le geste « Ajuster » tel quel, on ne réécrit pas cette
  logique. Merge à coordonner (mission [[sdd-un-seul-implementeur-par-fichier]] : un seul
  implémenteur par zone de `index.html`).
- On ne change pas les **vues SQL existantes** (`agent_v_parapheur`, `_encours`,
  `_due_today`, `_backlog`, `_campagnes`) sauf ajout additif décrit en §5.
- On n'écrit jamais dans `Pilotage National/*` (règles normatives).

## 3. Direction validée (maquette)

Quatre zones, différenciées visuellement (fini les 3 bandeaux jumeaux) :

### 3.1 Bandeau d'accueil (validé tel quel)
Wordmark Jules + phrase de rôle (« Ton IA d'automation. Elle chasse, veille et relance
pendant que tu vends — ici tu vois ce qu'elle fait et tu tranches. ») + **3 compteurs
cliquables** qui scrollent vers la zone : *Attendent ton go* (parapheur), *Tournent là*
(encours), *Missions actives* (backlog).

### 3.2 « Ce qui t'attend » — petites cartes + volet latéral
- Grille de **petites cartes** (min 268px, auto-fill).
- **Code couleur = type d'action** (bande latérale gauche 6px) :
  - 🟢 **vert** = `nature='go'` → simple **go/no-go** in-app (Accorder / Ajuster / Refuser).
  - 🔵 **bleu** = `nature='decision'` **ou** `'bloque'` → décision : **boutons d'options
    in-app** (1 clic, depuis `options`) + **« Répondre dans Slack »** pour la réponse libre.
  - 🔴 **rouge** = **criticité** (overlay indépendant de la nature, voir §5.1).
- Puces de filtre : Tout / Échanger / Go-no-go / Critique.
- Clic sur le corps de la carte → **volet latéral** : ce que Jules attend, contexte & source,
  texte proposé (citation), **encart renvoi 360**, actions en pied (clics in-app + bascule
  Slack pour les mots). Conforme au modèle §4 « CRM = clics, Slack = mots ».

### 3.3 « Ce qui tourne » — frise du jour (validé : timeline, pas jauges)
- **Frise horaire 7h→19h** avec un repère « maintenant ».
- Un **pin par passage cyclique** du jour (brief, scan, rondes) avec pastille d'état :
  ✓ vert (fait) · ● bleu pulsé (en cours) · ✕ rouge (planté) · pointillé gris (à venir).
- Clic sur un pin → volet : ce qui s'est passé + **renvoi 360** (« Jules va t'écrire » si
  décision ; « action de ton côté » si planté, ex. Okta expiré).
- Sous la frise : **one-shots en cours** (chasses, enrichissements) en puces vivantes
  (pouls bleu = tourne, rouge = échec), avec `heartbeat_age_s>900` = « sans signe de vie ».

### 3.4 « Missions » — table, type en colonnes
Colonnes : **Mission · Nature · Type · État · Avancement · Prochaine action**.
- **Nature** (récurrence, nouvelle colonne demandée par Nicolas) : ⟳ **Routine** (bleu) /
  ◈ **Campagne** (violet) / • **Ponctuel**. Dérivée : présente dans `agent_v_campagnes` →
  campagne ; sinon `agent_missions.kind='recurring'` → routine ; `'oneshot'` → ponctuel.
- **Type** (intention métier) : chasse / veille / relance / admin… (champ de mission).
  ⚠️ Nature ≠ Type (règle [[typologie-missions-carcan-commerciaux]]).
- **État** dérivé de `julesPouls` (nb_claimed→en cours, nb_failed→planté,
  nb_waiting_go→attend accord, paused→pause).
- Clic sur une ligne → volet mission (journal récent + actions Pause/Clôturer/Écrire à Jules).

### 3.5 Volet latéral (drawer)
Panneau droit (min(440px,92vw), plein écran < 560px), scrim, fermeture Échap/clic-dehors.
Remplace l'affichage inline de tout le détail. Toutes les actions d'écriture y sont
disponibles (via `julesActions` existant, y compris « Ajuster » de l'autre chantier).

## 4. Modèle d'interaction CRM ↔ Slack — **décidé : « CRM = clics, Slack = mots »**

Principe non négociable (évite le doublon de chemins, cf. avertissement Nicolas 21/09) :
le CRM **affiche et pilote** ; **l'échange en mots se fait dans Slack**.

- **Dans le CRM (clics, sans sortir)** : Accorder / Refuser (go/no-go), et les **boutons
  d'options structurés** d'une décision (ex. « Je regarde côté Lyon » / « J'attends Pierre »,
  portés par `agent_approvals.options`). Un clic écrit la décision, Jules reprend la tâche liée.
  **Exception conservée** : « Ajuster » (éditer le brouillon d'un `go` avant de l'accorder,
  `JulesAjuster` — feature mergée) reste in-app : c'est éditer un brouillon, pas discuter.
- **Dans Slack (mots)** : dès qu'il faut **écrire une réponse libre / discuter**, le CRM
  bascule vers le **DM Jules pré-rempli** avec le contexte de l'item. La zone texte libre de
  l'ancien modal TRANCHER est **remplacée** par un bouton « Répondre dans Slack » (on garde
  les boutons d'options in-app). C'est LA voie de conversation — pas de saisie libre in-app.
- **Slack/parapheur → Outil** : quand Jules dépose une approbation, le message Slack porte le
  **lead + un lien vers l'onglet** (`?tab=jules&appro=<id>`, « la suite est dans le cockpit »)
  au lieu de re-déballer le détail (cohérent règle concision Slack + JOINDRE).
- **Outil → Jules** : encart « Jules va t'écrire » pour ce que **Jules initie** (livrable,
  décision à venir), jamais pour dupliquer un geste faisable in-app.
- **Deep-links** : app `?tab=jules&appro=<uuid>` / `&mission=<uuid>` ouvre directement le bon
  volet ; DM Slack pré-rempli via l'API du bot Jules.

## 5. Ajouts de données (additifs, côté CRM/builder)

### 5.1 Criticité du parapheur — **décidé : champ explicite + filet âge**
Ajout **nullable** `critique boolean` sur `agent_approvals` (défaut `false`), exposé par
`agent_v_parapheur`. Alimenté par Jules à la création de l'approbation quand il sait que
c'est critique. **Filet de sécurité** : l'UI bascule aussi en 🔴 tout item non critique qui
attend depuis plus d'un **seuil d'âge** (à fixer, p. ex. 24 h ouvrées). Effet UI : bande
rouge + flag « urgent » + remontée en tête de la grille du parapheur.

### 5.2 Frise du jour — **décidé : vue SQL `agent_v_journee`**
Nouvelle vue `agent_v_journee` : pour chaque mission `kind='recurring'` dont la cadence tombe
aujourd'hui, une ligne = l'occurrence du jour avec heure prévue et **état résolu**
(`done` / `running` / `failed` / `pending`), reconstruit depuis `agent_tasks` + `agent_events`.
L'UI n'a plus qu'à placer les pins et colorer. (Option calcul-client écartée : fenêtre de
200 events trop courte pour être fiable.)

### 5.3 Trou UI ≠ a-valider.md
`a-valider.md` est une **vue générée** (noyau d'état). Vérifier pourquoi « EDF v35 » y est
sans ligne `agent_approvals` correspondante : soit fichier périmé, soit approbation jamais
créée. Corriger le tuyau pour que tout item mis au parapheur devienne une ligne
`agent_approvals` (source unique). Investigation builder.

## 6. Découpage en sous-projets

1. **CRM-DATA** (`db/`) — vue `agent_v_journee` (§5.2) + colonne `critique` sur
   `agent_approvals` exposée par `agent_v_parapheur` (§5.1). Prérequis dur de CRM-UI.
2. **CRM-UI** (`index.html`, zone TabJules) — refonte des 4 zones + volet, branchée sur les
   vues (existantes + `agent_v_journee`).
3. **360-WIRING** (pont Slack `bin/jules-slack-bot.py` / `bin/jules-say.sh`, playbooks
   `routines/`) — deep-links, messages contextualisés, renvois croisés. Dépend du format
   de deep-link défini en CRM-UI.
4. **FIX-TUYAU** (§5.3) — investigation + correctif parapheur/a-valider.

Ordre proposé : CRM-DATA → CRM-UI → 360-WIRING → FIX-TUYAU (les deux derniers parallélisables).

## 7. Contraintes transverses

- **DA** : néo-brutaliste conservé (bords 2px, ombres dures 4-5px, Outfit, palette
  `JULES_*`). IBM Plex Mono pour les chiffres.
- **Responsive** : phone-first, volet plein écran < 560px, table en `overflow-x`.
- **Egress Supabase** : select ciblé, pas de `select('*')` élargi ([[crm-egress-fetchall-colonnes]]).
- **Petit fix UI = merge direct main** ([[petits-correctifs-merge-direct-main.md]]) ; mais
  cette refonte n'est pas un petit fix → branche + revue.
- Le composant lit ses données lui-même (profils `jules_enabled`, cf. commentaire L7323).
