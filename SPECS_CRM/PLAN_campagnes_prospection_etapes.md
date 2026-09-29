# Campagnes de prospection de Jules qui font avancer le pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** qu'une campagne de prospection de Jules (mission `kind = campagne`, `config.preset = 'prospection'`) tienne toute seule le pipeline Prospect du CRM : fiche liée ou créée à la première vraie tentative de contact, étape qui avance sans jamais reculer, une ligne d'historique par événement, tâche « Répondre à X » sur réponse positive, et GO de Nicolas au parapheur pour « Ne pas recontacter », « Perdu » et l'homonyme.

**Architecture :** point de passage unique, l'outil MCP `agent_sequence_upsert`. Il écrit la séquence comme aujourd'hui, PUIS, pour une campagne au preset prospection explicite, déduit l'événement (ou prend celui passé par Jules), applique la correspondance du §4 de la spec (règles pures dans `server/campagne-rules.mjs`, écritures dans `server/campagne-crm.mjs`, dépendances réseau injectées) et dit dans sa réponse ce qu'il a fait. Un échec CRM ne défait jamais la séquence. Côté base, une seule colonne (`agent_sequences.contact_id`, migration 54). Côté app, la sortie manuelle du cockpit applique la même correspondance, verrouillée par un jeu de cas commun lu par les deux suites de tests. Côté Jules, la consigne `routines/campagne-boucle.md` passe les nouveaux paramètres.

**Tech Stack :** Node 25 (ESM `.mjs`, `node:test`, zod) pour le MCP ; PostgREST / Supabase (Postgres) ; app mono-fichier `index.html` (React 18 + Babel standalone dans le navigateur) ; SQL collé dans le SQL Editor Supabase ; Markdown pour la consigne Jules.

**Spec :** `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/SPECS_CRM/SPEC_campagnes_prospection_etapes.md` (autorité ; copie identique dans le worktree `prospects-pipeline`, même chemin relatif).

**Emplacements** (chaque tâche redonne ses chemins absolus) :
- MCP (worktree, branche `feat/campagnes-prospection`) : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes`
- App web (worktree, branche `feat/campagnes-prospection`) : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline`
- Jules (branche `main`, beaucoup de changements sans rapport en cours) : `/Users/nicolasserradeil/Pro/Jules`

---

## Décisions du plan

Ce que la spec laisse ouvert, tranché ici (une ligne de raison chacune).

1. **Déduction de l'événement** : `deduitEvenement(avant, apres)` compare l'état avant/après écriture, dans cet ordre de priorité : conversion (statut `converted`), arrêt (`stopped` : étape ≤ 1 = invitation expirée, relances en hausse = silence, sinon sortie « autre »), réponse (statut `replied`, étape 6 franchie ou sentiment changé), relance, premier message, acceptation, invitation. Raison : un appel = un événement, le plus avancé, pour une seule ligne d'historique.
2. **Dernière relance = silence** : une `relance_envoyee` qui fait passer la séquence en `stopped` (plan de `bin/seqcadence.py` épuisé) est traitée comme la sortie « fin des relances sans réponse ». Raison : c'est exactement ce que seqcadence écrit (« parcours terminé, sans réponse »), et Jules n'a pas d'autre moment pour le dire.
3. **Création à toute première tentative de contact effective**, pas seulement à l'acceptation : une séquence qui arrive directement à l'étape « message », « réponse » ou « RDV » (ajout spontané, InMail) crée aussi la fiche en Contacté, puis l'effet de l'événement s'applique. Raison : sinon ces personnes n'auraient jamais de fiche ; la règle de Nicolas (« jamais à l'ajout, seulement au premier vrai contact ») est respectée.
4. **Nom et propriétaire de la campagne** : nom = `agent_missions.titre` ; propriétaire = `profiles.nom` de `agent_missions.owner_id`, à défaut l'utilisateur du token (`getAuthCaller`). Raison : ce sont les seules sources en base ; `owner_id` est posé par la RLS.
5. **Idempotence sans nouvelle colonne** : la ligne d'historique est son propre témoin. Son début « Campagne <titre> : <libellé> » est déterministe (relance numérotée, mail et appel datés du jour) ; si une ligne commence déjà ainsi sur la fiche, rien n'est réécrit (ni étape, ni ligne, ni tâche). Tâches : pas de seconde tâche si une `tw_prospect_` est ouverte. Demandes de GO : titre déterministe, pas de seconde carte en attente. Raison : la spec limite la migration 54 à `contact_id`.
6. **Fiche supprimée** : chaque lien pose un événement `campagne.fiche_liee` (journal `agent_events`). Une séquence sans lien mais avec cette trace ne recrée jamais de fiche (elle se relie seulement si une autre fiche existe déjà avec le même profil). Raison : `on delete set null` efface le lien ; un humain qui supprime une fiche ne doit pas la voir renaître.
7. **GO exécutable par Jules** : pour chaque demande, le MCP crée une tâche `libre` en `waiting_go` dont `payload.instruction` porte l'appel exact (`crm_update_contact ...` ou `agent_sequence_upsert ... contact_id / nouvelle_fiche`), puis une carte au parapheur liée à cette tâche. GO ou réponse = la tâche repart (mécanisme existant de l'app et du MCP) ; refus = elle est annulée. Jamais liée à `JULES_TASK_ID`. Raison : lier la carte à la tâche de campagne en cours relancerait toute la passe au GO.
8. **Homonyme** : carte `decision`, une option « Lier à la fiche N (...) » par fiche trouvée plus « Créer une nouvelle fiche » ; la réponse se rejoue via deux nouveaux paramètres de `agent_sequence_upsert`, `contact_id` (lien explicite, vérifié) et `nouvelle_fiche` (passe outre l'homonyme). Raison : `crm_create_contact` refuse un homonyme (anti-doublon nom + prénom), il fallait une porte explicite.
9. **Société comparée** : il faut les deux sociétés connues et égales après normalisation (sans accents, casse ni ponctuation) ; même prénom + nom avec une société différente OU inconnue d'un côté = question d'homonyme. Raison : dans le doute on demande, on ne lie pas une mauvaise personne.
10. **Jour ouvré suivant** : jour civil de Paris de l'événement + 1, en sautant samedi, dimanche et fériés français (fixes, lundi de Pâques, Ascension, lundi de Pentecôte), à 09:00 heure de Paris avec le décalage de la date visée (`normaliseEcheance`). Même calcul dans le MCP et dans l'app. Raison : c'est l'heure où Nicolas traite ses relances.
11. **Prochaine action d'un Contacté** : `next_due_at` de la séquence si elle est dans le futur, sinon le jour ouvré suivant à 09:00 ; libellé « Relance campagne (Jules) » ; jamais de tâche CRM. Raison : à l'acceptation, seqcadence met `next_due_at = maintenant` (message dû tout de suite), ce qui ferait apparaître la fiche en retard.
12. **En veille** : une réponse positive le fait passer En discussion, un RDV pris en RDV planifié (la personne revient) ; acceptation, message et relance n'y écrivent que l'historique ; « pas le bon profil » n'y écrit que l'historique (la sortie Perdu est réservée aux étapes actives) ; un refus ou un silence repousse le réveil à 6 mois.
13. **Perdu reste Perdu** : historique seulement, sauf une réponse positive qui crée quand même « Répondre à X » (action humaine) et « ne me contactez plus » qui demande le GO (protection).
14. **« Ne pas recontacter » figé** : une fiche liée en NPC ne reçoit plus aucune écriture, et le MCP arrête la séquence (`stopped`, note datée) pour qu'aucun message ne reparte. À l'ajout d'une personne dans une campagne de prospection, une fiche trouvée en NPC fait refuser la séquence (rien n'est écrit). Raison : « Ne pas recontacter l'emporte sur tout ».
15. **Nouveau paramètre `canal`** (`linkedin` par défaut, `mail`, `appel`) pour le type d'historique (`LinkedIn`, `Mail envoyé`, `Mail reçu`, `Appel sortant`). Aucun paramètre CRM (`evenement`, `motif_sortie`, `rdv_date`, `canal`, identité, `contact_id`, `nouvelle_fiche`) n'est écrit dans `agent_sequences` ; le lien `contact_id` n'est posé qu'après vérification que la fiche existe.
16. **Réutilisation de la création de contact** : la construction de la fiche de `crm_create_contact` est extraite dans `server/contact-norm.mjs` (`donneesNouveauContact`) et partagée ; la recherche du §3, plus stricte, remplace l'anti-doublon nom + prénom pour les créations de campagne. Raison : `index.mjs` démarre le serveur à l'import et ne peut pas être testé ni importé par un autre module.
17. **Responsables** : historique = propriétaire de la campagne ; tâche = responsable de la fiche (à défaut le propriétaire) ; fiche créée = propriétaire, agence via `getAgenceFor`.
18. **Sortie manuelle dans l'app** : Nicolas est le décideur, donc les sorties qui demandent son GO côté Jules (Perdu, Ne pas recontacter) s'appliquent directement ; seule la fiche déjà liée bouge (aucune recherche ni création dans l'app) ; le détail d'historique commence comme celui du MCP pour que Jules ne le double pas. Le câblage existant perdait la raison de sortie (`arreterSuivi:s=>...` ignorait le 2e argument) : corrigé au passage.
19. **Compatibilité sans migration** : la lecture « avant » ne sélectionne pas `contact_id`. Si le MCP 8.27.0 tourne avant la migration 54, les séquences s'écrivent quand même et la réponse signale « CRM non mis à jour ».

## Global Constraints

- Zéro tiret cadratin (U+2014) et zéro demi-cadratin (U+2013) dans tout texte visible ajouté : réponses d'outil, lignes d'historique, titres et détails de cartes, toasts, libellés, changelog, commentaires SQL, consigne Jules. Virgule, deux-points ou parenthèse à la place.
- Étapes, accents et casse exacts : `À contacter`, `Contacté`, `En discussion`, `RDV planifié`, `Qualifié`, `En veille`, `Perdu`, `Ne pas recontacter`. Motif de perte : `Pas le bon interlocuteur`.
- Toute date écrite l'est avec un décalage explicite (`+01:00` / `+02:00`, ou `Z` venant de la base), jamais naïve ; les échéances « jour » sont à 09:00 heure de Paris (`normaliseEcheance` côté MCP, `combineDT` / `prospectTacheEcheance` côté app).
- Lectures ciblées uniquement (egress Supabase) : toujours un `select` explicite, jamais `select *` ajouté, `limit` quand une ligne suffit.
- App : mono-fichier `index.html`, fonctions racine en style `var` / `function` comme les fonctions `prospect*` existantes ; style brutaliste pour tout élément ajouté (`borderRadius: 0`, police `Outfit`, `textTransform: 'uppercase'`, `letterSpacing: '0.03em'`).
- Le source MCP en service `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-src` n'est JAMAIS modifié par une tâche de code : tout se fait dans le worktree `upgrade-crm-mcp-wt-campagnes` (seule la tâche 13, manuelle, bascule le source).
- Version `8.27.0` dans `manifest.json` (version + long_description), `CRM_VERSION` et le changelog de `crm_version` (`server/index.mjs`).
- Périmètre : seul `config.preset === 'prospection'` (et `kind === 'campagne'`) déclenche un effet CRM, testé explicitement ; sans preset ou en recrutement, aucune lecture ni écriture CRM ; seules les cibles `externe` et `contact_crm` (jamais `plateforme`, jamais `candidat_recruitee`).
- L'écriture CRM ne bloque ni ne fait jamais échouer l'écriture de la séquence : toute erreur CRM devient une ligne « ⚠️ CRM non mis à jour (...). La séquence, elle, est bien écrite. » (seule exception voulue : l'ajout d'une personne en « Ne pas recontacter » est refusé).
- La todo de Nicolas (tâches CRM `taches`) ne reçoit que des actions humaines : « Répondre à X » et « Confirmer la date du RDV : X ». Jamais de tâche CRM pour une relance que Jules exécute.
- Git : toujours `/usr/bin/git` (un hook intercepte `git`), toujours `-C <dépôt>`, jamais `git add -A` ni `git add .` : seulement les fichiers de la tâche. Ajouter à chaque message de commit la ligne `Co-Authored-By` que ton environnement prescrit, s'il en prescrit une.
- Tests MCP : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes && node --test tests/*.test.mjs` (plus `node --check server/index.mjs` quand `index.mjs` change).
- Tests app : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline && node --test tests/*.test.mjs && node tests/check-babel.mjs` (JAMAIS `node --test tests/`, qui exécuterait aussi les fixtures et `check-babel.mjs`).

## Review Focus

Cinq façons d'échouer que la spec implique sans les tester ligne à ligne. Chacune a son test épinglé dans la tâche propriétaire (nom de test préfixé `REVIEW FOCUS n`). Le relecteur de chaque tâche vérifie que le test existe, qu'il échoue sans le code et qu'il passe avec.

1. **Le même événement rejoué deux fois** (worker relancé, `agent_sequence_upsert` rappelé) : ni seconde fiche, ni seconde ligne d'historique, ni seconde tâche. Épinglé en tâche 6 (`REVIEW FOCUS 1`).
2. **Événement sur une séquence dont la fiche liée a été supprimée** (`contact_id` remis à null par la base) : aucune fiche recréée, rien écrit, et on le dit. Épinglé en tâche 5 (`REVIEW FOCUS 2`, recherche) et tâche 6 (`REVIEW FOCUS 2`, application).
3. **Homonyme dans une autre société** : ni lien ni création, question à Nicolas avec la liste des fiches. Épinglé en tâche 5 (`REVIEW FOCUS 3`), la carte au parapheur en tâche 8 (« de bout en bout : un homonyme »).
4. **Fiche passée en « Ne pas recontacter » par un humain pendant la campagne** : la fiche ne bouge plus, aucune ligne n'est écrite, la séquence s'arrête. Épinglé en tâche 7 (`REVIEW FOCUS 4`).
5. **Identité manquante quand la création est due** (pas de prénom ou de nom, aucun profil LinkedIn trouvé) : rien n'est créé, la séquence reste sans lien, la réponse dit « identité manquante ». Épinglé en tâche 5 (`REVIEW FOCUS 5`, recherche) et tâche 6 (`REVIEW FOCUS 5`, application).

Couverts en plus par des tests ordinaires demandés au §7 : campagne sans preset ou en recrutement (tâche 7), URL LinkedIn avec paramètres de suivi, slash final, casse ou encodage (tâches 2 et 5), cas été et hiver du réveil (tâche 2).

## File Structure

| Fichier | Responsabilité | Tâche | Action |
|---|---|---|---|
| `upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline/db/54_agent_sequences_contact_id.sql` | colonne `agent_sequences.contact_id` bigint, FK `contacts(id)` `on delete set null`, index | 1 | créer |
| `.../prospects-pipeline/tests/db-54.test.mjs` | la 54 est un ajout pur, au bon type | 1 | créer |
| `upgrade-crm-mcp-wt-campagnes/server/campagne-rules.mjs` | règles pures : périmètre, LinkedIn, dates, événement, libellés, correspondance §4 | 2, 3 | créer |
| `upgrade-crm-mcp-wt-campagnes/tests/campagne-rules.test.mjs` | tests des règles de base | 2 | créer |
| `upgrade-crm-mcp-wt-campagnes/tests/campagne-effets.test.mjs` | table du §4, garde-fous, jeu de cas commun | 3 | créer |
| `upgrade-crm-mcp-wt-campagnes/tests/fixtures/campagne-sortie-cas.json` | jeu de cas commun des sorties (copie MCP) | 3 | créer |
| `upgrade-crm-mcp-wt-campagnes/server/contact-norm.mjs` | normalisation et construction d'une fiche contact | 4 | créer |
| `upgrade-crm-mcp-wt-campagnes/tests/contact-norm.test.mjs` | construction de fiche inchangée, import dans `index.mjs` | 4 | créer |
| `upgrade-crm-mcp-wt-campagnes/server/index.mjs` | import de la normalisation (4), dépendances CRM passées aux outils agent (7), version et changelog (9) | 4, 7, 9 | modifier |
| `upgrade-crm-mcp-wt-campagnes/tests/fausse-base.mjs` | fausse base PostgREST en mémoire (helper, pas une suite) | 5 | créer |
| `upgrade-crm-mcp-wt-campagnes/server/campagne-crm.mjs` | recherche, lien, création (5), application des effets (6), demandes de GO (8) | 5, 6, 8 | créer puis modifier |
| `upgrade-crm-mcp-wt-campagnes/tests/campagne-fiche.test.mjs` | recherche et création de fiche | 5 | créer |
| `upgrade-crm-mcp-wt-campagnes/tests/campagne-appliquer.test.mjs` | application d'un événement, idempotence | 6 | créer |
| `upgrade-crm-mcp-wt-campagnes/server/agent-tools.mjs` | `agent_sequence_upsert` : paramètres, lecture avant, garde NPC, volet CRM | 7 | modifier |
| `upgrade-crm-mcp-wt-campagnes/tests/agent-sequence-campagne.test.mjs` | l'outil de bout en bout sur fausse base | 7 | créer |
| `upgrade-crm-mcp-wt-campagnes/tests/campagne-demandes.test.mjs` | cartes au parapheur et tâches de GO | 8 | créer |
| `upgrade-crm-mcp-wt-campagnes/manifest.json` | version, description longue, description de l'outil | 9 | modifier |
| `upgrade-crm-mcp-wt-campagnes/tests/version-8-27.test.mjs` | version partout, changelog sans tiret | 9 | créer |
| `.../prospects-pipeline/index.html` | fonctions pures des sorties (10), câblage du cockpit (11) | 10, 11 | modifier |
| `.../prospects-pipeline/tests/fixtures/campagne-sortie-cas.json` | jeu de cas commun des sorties (copie app, identique) | 10 | créer |
| `.../prospects-pipeline/tests/campagne-sortie.test.mjs` | fonctions pures de la sortie manuelle | 10 | créer |
| `.../prospects-pipeline/tests/campagne-cockpit.test.mjs` | écritures de la sortie manuelle et câblage | 11 | créer |
| `/Users/nicolasserradeil/Pro/Jules/routines/campagne-boucle.md` | consigne du worker : paramètres à passer | 12 | modifier |

---

## Tâche 1 : migration 54, lien `agent_sequences.contact_id`

**Files :**
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline/db/54_agent_sequences_contact_id.sql`
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline/tests/db-54.test.mjs`

**Interfaces :**
- Consumes : table `public.contacts` dont la clé `id` est un `bigint` (preuve : `db/01_interco_imputations.sql` et `db/04_role_partner.sql`, `contact_consultant_id bigint not null references public.contacts(id)`) ; table `public.agent_sequences` (`db/25`, `db/28`, `db/48`, `db/49`).
- Produces : colonne `public.agent_sequences.contact_id bigint null references public.contacts(id) on delete set null`, index partiel `agent_sequences_contact_idx`. Consommée par les tâches 5 à 8 (MCP) et 11 (app, via `select('*')`).

Contexte : la spec (§6.1) impose « rien d'autre » dans cette migration. Style d'en-tête : celui de `db/51_contacts_etape_prospect.sql` (`-- db/NN_nom.sql : SPEC_..., date`). Ce fichier se colle à la main dans le SQL Editor Supabase (tâche 13) : cette tâche ne l'exécute pas.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/db-54.test.mjs` :

```js
// tests/db-54.test.mjs : la migration 54 est un ajout pur, au bon type, rejouable.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../db/54_agent_sequences_contact_id.sql', import.meta.url), 'utf8');
const code = sql.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

test('54 : contact_id bigint, cle etrangere vers contacts, on delete set null, index', () => {
  assert.match(code, /alter table public\.agent_sequences\s+add column if not exists contact_id bigint references public\.contacts\(id\) on delete set null;/);
  assert.match(code, /create index if not exists agent_sequences_contact_idx\s+on public\.agent_sequences \(contact_id\) where contact_id is not null;/);
});

test('54 : rien d autre qu un ajout (ni drop, ni update, ni delete de donnees)', () => {
  assert.doesNotMatch(code, /\bdrop\b|\bupdate\b|delete from|truncate/i);
});

test('54 : aucun tiret cadratin ni demi-cadratin', () => {
  assert.doesNotMatch(sql, /[\u2013\u2014]/);
});
```

- [ ] **Étape 2 : le lancer et le voir échouer**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline && node --test tests/db-54.test.mjs`
Attendu : échec `ENOENT: no such file or directory, open '.../db/54_agent_sequences_contact_id.sql'`.

- [ ] **Étape 3 : écrire la migration**

Créer `db/54_agent_sequences_contact_id.sql` :

```sql
-- db/54_agent_sequences_contact_id.sql : SPEC_campagnes_prospection_etapes.md, 29/09/2026
-- A coller dans le SQL Editor Supabase, AVANT la bascule du MCP 8.27.0 (le MCP lit et ecrit cette
-- colonne ; sans elle, les effets CRM des campagnes echouent et le disent, les sequences s'ecrivent
-- quand meme). Rejouable sans risque : ajout de colonne et d'index, aucune donnee modifiee.
-- Lien optionnel d'une sequence de campagne vers la fiche contact du CRM, pose par le MCP
-- (agent_sequence_upsert) a la premiere vraie tentative de contact d'une campagne de prospection.
-- Supprimer la fiche remet le lien a null : la sequence, elle, reste.
-- contacts.id est un bigint (cf. db/01 et db/04, contact_consultant_id bigint references contacts) :
-- la cle etrangere a le meme type.

alter table public.agent_sequences
  add column if not exists contact_id bigint references public.contacts(id) on delete set null;

comment on column public.agent_sequences.contact_id is
  'Fiche contact liee a la personne suivie (campagnes de prospection). Null tant qu elle n a pas ete contactee, ou si la fiche a ete supprimee.';

create index if not exists agent_sequences_contact_idx
  on public.agent_sequences (contact_id) where contact_id is not null;

-- Controle apres passage (une ligne attendue, data_type = bigint) :
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'public' and table_name = 'agent_sequences' and column_name = 'contact_id';
-- Cle etrangere et sa regle de suppression (confdeltype = 'n' pour set null) :
--   select conname, confdeltype from pg_constraint
--    where conrelid = 'public.agent_sequences'::regclass and contype = 'f' and conname like '%contact%';
```

- [ ] **Étape 4 : relancer toute la suite**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline && node --test tests/*.test.mjs && node tests/check-babel.mjs`
Attendu : tout passe (dont les 3 tests `54 : ...`), puis `OK babel`.

- [ ] **Étape 5 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline add db/54_agent_sequences_contact_id.sql tests/db-54.test.mjs
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline commit -m "db(campagnes): 54, lien agent_sequences.contact_id vers la fiche contact"
```

---

## Tâche 2 : règles pures, partie 1 (périmètre, LinkedIn, dates, événement, libellés)

**Files :**
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/server/campagne-rules.mjs`
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/campagne-rules.test.mjs`

**Interfaces :**
- Consumes : `server/prospect-rules.mjs` : `PROSPECT_ETAPES_ACTIVES` (tableau des 5 étapes actives), `normaliseEcheance(v) -> { ok, valeur }` (date nue = 09:00 Paris avec décalage ; valeur déjà décalée gardée telle quelle).
- Produces (exports ESM de `server/campagne-rules.mjs`) :
  - constantes `CAMPAGNE_EVENEMENTS`, `CAMPAGNE_MOTIFS_SORTIE`, `CAMPAGNE_CANAUX`, `LIBELLE_RELANCE_CAMPAGNE` (`"Relance campagne (Jules)"`), `LIBELLE_CONFIRMER_RDV` (`"Confirmer la date du RDV"`), `MOTIF_PERTE_PROFIL` (`"Pas le bon interlocuteur"`), `LIBELLES_SORTIE` (motif -> libellé) ;
  - `estCampagneProspection(mission) -> boolean`, `rangEtape(etape) -> number` ;
  - `slugLinkedin(v) -> string|null`, `normIdentite(s) -> string`, `normSociete(s) -> string` ;
  - `dateParis(instant) -> 'YYYY-MM-DD'`, `fmtJour(ymd) -> 'JJ/MM/AAAA'`, `fmtEcheance(iso) -> 'JJ/MM à HH:MM'`, `ajouteMois(ymd, n) -> ymd`, `reveilSixMois(maintenant) -> iso`, `feriesFR(annee) -> Set<ymd>`, `jourOuvreSuivant(maintenant) -> ymd`, `echeanceJourOuvreSuivant(maintenant) -> iso`, `prochaineRelance(sequence, maintenant) -> { prochaine_action_date, prochaine_action_libelle }` ;
  - `deduitEvenement(avant, apres) -> { type, motif?, sentiment? } | null`, `resoutEvenement(params, avant, apres) -> { type, motif, sentiment, canal, rdv_date } | null`, `evenementSansEffet(evt) -> boolean`, `libelleEvenement(evt, { nbRelances, maintenant }) -> string|null`, `typeHistorique(evt) -> string`.
  Consommés par les tâches 3, 5, 6, 7.

Contexte : étapes de séquence de `/Users/nicolasserradeil/Pro/Jules/bin/seqcadence.py` : 0 identifié, 1 invité, 2 accepté, 3 messagé, 4 et 5 relances, 6 répondu, 7 converti ; statuts `active`, `replied`, `paused`, `stopped`, `converted`. `slugLinkedin` reprend l'extraction de `refCanonique` (`server/agent-tools.mjs`) et ajoute la casse. Le module doit rester sans aucun tiret cadratin (un test le vérifie), commentaires compris.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/campagne-rules.test.mjs` :

```js
// Regles pures des campagnes de prospection : perimetre, LinkedIn, dates, evenement, libelles.
// Cf. SPECS_CRM/SPEC_campagnes_prospection_etapes.md (repo web), §2, §3, §4 et §6.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  estCampagneProspection, slugLinkedin, normSociete, normIdentite, dateParis, ajouteMois, reveilSixMois,
  feriesFR, jourOuvreSuivant, echeanceJourOuvreSuivant, prochaineRelance, deduitEvenement, resoutEvenement,
  evenementSansEffet, libelleEvenement, typeHistorique, fmtEcheance, LIBELLE_RELANCE_CAMPAGNE,
} from "../server/campagne-rules.mjs";

test("seule une campagne au preset prospection EXPLICITE est dans le perimetre", () => {
  assert.equal(estCampagneProspection({ kind: "campagne", config: { preset: "prospection" } }), true);
  assert.equal(estCampagneProspection({ kind: "campagne", config: { preset: "recrutement" } }), false);
  assert.equal(estCampagneProspection({ kind: "campagne", config: {} }), false, "sans preset : aucun effet");
  assert.equal(estCampagneProspection({ kind: "campagne", config: null }), false);
  assert.equal(estCampagneProspection({ kind: "recurring", config: { preset: "prospection" } }), false);
  assert.equal(estCampagneProspection(null), false);
});

test("slug LinkedIn sans parametres de suivi, slash final, casse ni encodage", () => {
  assert.equal(slugLinkedin("https://www.linkedin.com/in/jean-dupont-123/?utm_source=share&trk=x"), "jean-dupont-123");
  assert.equal(slugLinkedin("https://fr.linkedin.com/in/Jean-Dupont"), "jean-dupont");
  assert.equal(slugLinkedin("linkedin.com/in/jean-dupont/"), "jean-dupont");
  assert.equal(slugLinkedin("https://www.linkedin.com/in/aur%C3%A9lien-x#about"), "aurélien-x");
  assert.equal(slugLinkedin("jean-dupont"), "jean-dupont");
  assert.equal(slugLinkedin("https://www.linkedin.com/company/upgrade"), null);
  assert.equal(slugLinkedin("Dupont|Crédit Agricole"), null);
  assert.equal(slugLinkedin(""), null);
  assert.equal(slugLinkedin(null), null);
});

test("societe et identite comparees sans accents, casse ni ponctuation", () => {
  assert.equal(normSociete("Crédit Agricole S.A."), normSociete("credit agricole s a"));
  assert.notEqual(normSociete("Orange"), normSociete("Crédit Agricole"));
  assert.equal(normSociete(null), "");
  assert.equal(normIdentite("Jean-Émile"), normIdentite("jean emile"));
  assert.equal(normIdentite("  DUPONT "), "dupont");
});

test("date civile de Paris d'un instant, y compris tard le soir en UTC", () => {
  assert.equal(dateParis(new Date("2026-09-29T10:00:00+02:00")), "2026-09-29");
  assert.equal(dateParis(new Date("2026-09-29T23:30:00Z")), "2026-09-30");
});

test("ajout de mois : fin de mois ramenee au dernier jour reel", () => {
  assert.equal(ajouteMois("2026-09-29", 6), "2027-03-29");
  assert.equal(ajouteMois("2026-08-31", 6), "2027-02-28");
  assert.equal(ajouteMois("2026-12-15", 6), "2027-06-15");
});

test("reveil a 6 mois, 09h00 heure de Paris, decalage explicite ete et hiver", () => {
  assert.equal(reveilSixMois(new Date("2026-09-29T10:00:00+02:00")), "2027-03-29T09:00:00+02:00");
  assert.equal(reveilSixMois(new Date("2026-05-10T10:00:00+02:00")), "2026-11-10T09:00:00+01:00");
  assert.equal(reveilSixMois(new Date("2026-08-31T10:00:00+02:00")), "2027-02-28T09:00:00+01:00");
  assert.equal(reveilSixMois(new Date("2026-09-29T23:30:00Z")), "2027-03-30T09:00:00+02:00");
});

test("jours feries francais : fixes et mobiles", () => {
  const f = feriesFR(2026);
  for (const d of ["2026-01-01", "2026-04-06", "2026-05-01", "2026-05-08", "2026-05-14", "2026-05-25",
                   "2026-07-14", "2026-08-15", "2026-11-01", "2026-11-11", "2026-12-25"]) assert.ok(f.has(d), d);
  assert.ok(feriesFR(2027).has("2027-03-29"), "lundi de Paques 2027");
  assert.equal(f.has("2026-09-30"), false);
});

test("jour ouvre suivant : week-end et feries sautes", () => {
  assert.equal(jourOuvreSuivant(new Date("2026-09-29T10:00:00+02:00")), "2026-09-30");
  assert.equal(jourOuvreSuivant(new Date("2026-10-02T10:00:00+02:00")), "2026-10-05");
  assert.equal(jourOuvreSuivant(new Date("2026-10-02T22:30:00Z")), "2026-10-05", "samedi 00h30 a Paris");
  assert.equal(jourOuvreSuivant(new Date("2026-11-10T10:00:00+01:00")), "2026-11-12");
  assert.equal(jourOuvreSuivant(new Date("2026-12-24T10:00:00+01:00")), "2026-12-28");
  assert.equal(jourOuvreSuivant(new Date("2027-03-26T10:00:00+01:00")), "2027-03-30");
});

test("echeance du jour ouvre suivant : 09h00 avec le decalage de la date visee", () => {
  assert.equal(echeanceJourOuvreSuivant(new Date("2027-03-26T10:00:00+01:00")), "2027-03-30T09:00:00+02:00");
  assert.equal(echeanceJourOuvreSuivant(new Date("2026-10-23T10:00:00+02:00")), "2026-10-26T09:00:00+01:00");
  assert.equal(fmtEcheance("2026-10-26T09:00:00+01:00"), "26/10 à 09:00");
});

test("prochaine action d'un Contacte : la relance de la sequence si elle est a venir, sinon le jour ouvre suivant", () => {
  const now = new Date("2026-09-29T10:00:00+02:00");
  assert.deepEqual(prochaineRelance({ next_due_at: "2026-10-13T08:00:00+00:00" }, now),
    { prochaine_action_date: "2026-10-13T08:00:00+00:00", prochaine_action_libelle: LIBELLE_RELANCE_CAMPAGNE });
  assert.deepEqual(prochaineRelance({ next_due_at: "2026-09-29T07:00:00Z" }, now),
    { prochaine_action_date: "2026-09-30T09:00:00+02:00", prochaine_action_libelle: LIBELLE_RELANCE_CAMPAGNE });
  assert.equal(prochaineRelance({ next_due_at: null }, now).prochaine_action_date, "2026-09-30T09:00:00+02:00");
});

test("evenement deduit du changement d'etat de la sequence", () => {
  const s = (etape, statut = "active", nb_relances = 0, sentiment = null) => ({ etape, statut, nb_relances, sentiment });
  assert.deepEqual(deduitEvenement(s(0), s(1)), { type: "invite_envoyee" });
  assert.deepEqual(deduitEvenement(s(1), s(2)), { type: "acceptee" });
  assert.deepEqual(deduitEvenement(null, s(2)), { type: "acceptee" });
  assert.deepEqual(deduitEvenement(s(2), s(3)), { type: "message_envoye" });
  assert.deepEqual(deduitEvenement(s(3), s(4, "active", 1)), { type: "relance_envoyee" });
  assert.deepEqual(deduitEvenement(s(4, "active", 1), s(5, "stopped", 2)), { type: "sortie", motif: "silence" });
  assert.deepEqual(deduitEvenement(s(3), s(6, "replied", 0, "positif")), { type: "reponse", sentiment: "positif" });
  assert.deepEqual(deduitEvenement(s(6, "replied", 0, "neutre"), s(6, "replied", 0, "positif")), { type: "reponse", sentiment: "positif" });
  assert.deepEqual(deduitEvenement(s(6, "replied"), s(7, "converted")), { type: "conversion" });
  assert.deepEqual(deduitEvenement(s(1), s(1, "stopped")), { type: "expiration" });
  assert.deepEqual(deduitEvenement(s(3), s(3, "stopped")), { type: "sortie", motif: "autre" });
  assert.equal(deduitEvenement(s(3), s(3)), null, "etat inchange : aucun evenement");
});

test("evenement explicite prioritaire ; la derniere relance qui clot la sequence vaut silence", () => {
  const av = { etape: 4, statut: "active", nb_relances: 1 };
  assert.deepEqual(resoutEvenement({ evenement: "relance_envoyee" }, av, { ...av, etape: 5, statut: "stopped", nb_relances: 2 }),
    { canal: "linkedin", rdv_date: null, type: "sortie", motif: "silence", sentiment: null });
  assert.deepEqual(resoutEvenement({ evenement: "reponse", sentiment: "negatif", canal: "mail" }, av, { ...av, etape: 6, statut: "replied" }),
    { canal: "mail", rdv_date: null, type: "reponse", motif: null, sentiment: "negatif" });
  assert.deepEqual(resoutEvenement({ evenement: "sortie" }, av, { ...av, statut: "stopped" }),
    { canal: "linkedin", rdv_date: null, type: "sortie", motif: "autre", sentiment: null });
  assert.deepEqual(resoutEvenement({ evenement: "conversion", rdv_date: "2026-10-06T14:30" }, av, { ...av, etape: 7, statut: "converted" }),
    { canal: "linkedin", rdv_date: "2026-10-06T14:30", type: "conversion", motif: null, sentiment: null });
  assert.deepEqual(resoutEvenement({ motif_sortie: "refus" }, { etape: 3, statut: "active" }, { etape: 3, statut: "stopped" }),
    { canal: "linkedin", rdv_date: null, sentiment: null, motif: "refus", type: "sortie" });
  assert.equal(resoutEvenement({}, { etape: 3, statut: "active" }, { etape: 3, statut: "active" }), null);
});

test("invitation envoyee, expiration et doublon n'ont aucun effet CRM", () => {
  assert.equal(evenementSansEffet({ type: "invite_envoyee" }), true);
  assert.equal(evenementSansEffet({ type: "expiration" }), true);
  assert.equal(evenementSansEffet({ type: "sortie", motif: "doublon" }), true);
  assert.equal(evenementSansEffet({ type: "sortie", motif: "refus" }), false);
  assert.equal(evenementSansEffet(null), true);
});

test("libelles d'historique stables : ce sont eux qui rendent un evenement rejouable sans doublon", () => {
  const maintenant = new Date("2026-09-29T10:00:00+02:00");
  assert.equal(libelleEvenement({ type: "acceptee" }, { maintenant }), "invitation acceptée");
  assert.equal(libelleEvenement({ type: "message_envoye" }, { maintenant }), "premier message envoyé");
  assert.equal(libelleEvenement({ type: "relance_envoyee" }, { nbRelances: 2, maintenant }), "relance 2 envoyée");
  assert.equal(libelleEvenement({ type: "mail_envoye" }, { maintenant }), "mail envoyé le 29/09/2026");
  assert.equal(libelleEvenement({ type: "appel_passe" }, { maintenant }), "appel passé le 29/09/2026");
  assert.equal(libelleEvenement({ type: "reponse", sentiment: "positif" }, { maintenant }), "réponse positive");
  assert.equal(libelleEvenement({ type: "reponse", sentiment: "negatif" }, { maintenant }), "réponse négative");
  assert.equal(libelleEvenement({ type: "reponse" }, { maintenant }), "réponse neutre");
  assert.equal(libelleEvenement({ type: "conversion" }, { maintenant }), "RDV pris");
  assert.equal(libelleEvenement({ type: "sortie", motif: "npc" }, { maintenant }), "ne me contactez plus");
  assert.equal(libelleEvenement({ type: "sortie", motif: "silence" }, { maintenant }), "fin des relances sans réponse");
  assert.equal(libelleEvenement({ type: "invite_envoyee" }, { maintenant }), null);
});

test("type d'historique selon le canal", () => {
  assert.equal(typeHistorique({ type: "acceptee", canal: "linkedin" }), "LinkedIn");
  assert.equal(typeHistorique({ type: "mail_envoye", canal: "mail" }), "Mail envoyé");
  assert.equal(typeHistorique({ type: "appel_passe", canal: "appel" }), "Appel sortant");
  assert.equal(typeHistorique({ type: "reponse", canal: "mail" }), "Mail reçu");
  assert.equal(typeHistorique({ type: "message_envoye", canal: "mail" }), "Mail envoyé");
  assert.equal(typeHistorique({ type: "reponse" }), "LinkedIn");
});

test("aucun tiret cadratin ni demi-cadratin dans le module", () => {
  const src = readFileSync(new URL("../server/campagne-rules.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(src, /[\u2013\u2014]/);
});
```

- [ ] **Étape 2 : le lancer et le voir échouer**

Commande : `node --test /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/campagne-rules.test.mjs`
Attendu : `Error [ERR_MODULE_NOT_FOUND]: Cannot find module '.../server/campagne-rules.mjs'`.

- [ ] **Étape 3 : écrire le module**

Créer `server/campagne-rules.mjs` avec exactement ce contenu (la tâche 3 ajoutera une seconde partie à la fin) :

```js
// Regles pures des campagnes de prospection de Jules : cf. SPECS_CRM/SPEC_campagnes_prospection_etapes.md
// (repo web). Aucune entree/sortie ici, tout se teste sans reseau. Les ecritures vivent dans
// campagne-crm.mjs, le branchement dans agent-tools.mjs (agent_sequence_upsert).
import { PROSPECT_ETAPES_ACTIVES, normaliseEcheance } from "./prospect-rules.mjs";

export const CAMPAGNE_EVENEMENTS = ["acceptee", "message_envoye", "relance_envoyee", "reponse", "conversion", "mail_envoye", "appel_passe", "sortie"];
export const CAMPAGNE_MOTIFS_SORTIE = ["converti", "refus", "silence", "profil", "doublon", "npc", "autre"];
export const CAMPAGNE_CANAUX = ["linkedin", "mail", "appel"];
export const LIBELLE_RELANCE_CAMPAGNE = "Relance campagne (Jules)";
export const LIBELLE_CONFIRMER_RDV = "Confirmer la date du RDV";
export const MOTIF_PERTE_PROFIL = "Pas le bon interlocuteur";
export const LIBELLES_SORTIE = { converti: "RDV pris", refus: "refus", silence: "fin des relances sans réponse",
  profil: "pas le bon profil", npc: "ne me contactez plus", doublon: "doublon", autre: "sortie de campagne" };

// Perimetre : une campagne dont le preset est EXPLICITEMENT prospection. Sans preset, la cadence
// retombe sur les valeurs de prospection, mais ce n'est pas une declaration d'intention.
export function estCampagneProspection(mission) {
  return !!mission && mission.kind === "campagne" && (mission.config || {}).preset === "prospection";
}

export function rangEtape(etape) { return PROSPECT_ETAPES_ACTIVES.indexOf(etape); }

// Slug de profil LinkedIn, comparable : meme extraction que refCanonique (agent-tools.mjs), plus
// la casse (LinkedIn ne la distingue pas). Parametres de suivi, ancre et slash final retires.
// null si la valeur n'est pas un profil (/company/, format ledger « nom|compte », vide).
export function slugLinkedin(v) {
  const brut = String(v ?? "").trim();
  if (!brut || (brut.includes("|") && !/^https?:/i.test(brut))) return null;
  const m = /\/in\/([^/?#]+)/i.exec(brut);
  let slug = m ? m[1] : (/[/:.]/.test(brut) ? null : brut);
  if (!slug) return null;
  try { slug = decodeURIComponent(slug); } catch { /* % mal forme : on garde tel quel */ }
  slug = slug.replace(/\/+$/, "").trim().toLowerCase();
  return slug || null;
}

export function normIdentite(s) {
  return String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/[-_.']+/g, " ").replace(/\s+/g, " ").trim();
}

export function normSociete(s) {
  return String(s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, " ").trim();
}

// Date civile de Paris (YYYY-MM-DD) d'un instant.
export function dateParis(instant) {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/Paris", year: "numeric", month: "2-digit", day: "2-digit" })
    .format(new Date(instant));
}

export function fmtJour(ymd) {
  const [y, m, d] = String(ymd).slice(0, 10).split("-");
  return `${d}/${m}/${y}`;
}

// Une echeance produite par normaliseEcheance porte deja l'heure murale de Paris.
export function fmtEcheance(iso) {
  const s = String(iso);
  return `${s.slice(8, 10)}/${s.slice(5, 7)} à ${s.slice(11, 16)}`;
}

// Ajout de mois, fin de mois ramenee au dernier jour reel (31 aout + 6 mois = 28 fevrier).
export function ajouteMois(ymd, n) {
  const [y, m, d] = String(ymd).slice(0, 10).split("-").map(Number);
  const cible = new Date(Date.UTC(y, m - 1 + n, 1));
  const dernier = new Date(Date.UTC(cible.getUTCFullYear(), cible.getUTCMonth() + 1, 0)).getUTCDate();
  cible.setUTCDate(Math.min(d, dernier));
  return cible.toISOString().slice(0, 10);
}

// Reveil « En veille » : 6 mois apres l'evenement, 09:00 heure de Paris, decalage explicite.
export function reveilSixMois(maintenant) {
  return normaliseEcheance(ajouteMois(dateParis(maintenant), 6)).valeur;
}

// Jours feries francais d'une annee (fixes, lundi de Paques, Ascension, lundi de Pentecote).
export function feriesFR(annee) {
  const a = annee % 19, b = Math.floor(annee / 100), c = annee % 100, d = Math.floor(b / 4), e = b % 4,
    f = Math.floor((b + 8) / 25), g = Math.floor((b - f + 1) / 3), h = (19 * a + b - d - g + 15) % 30,
    i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = Math.floor((a + 11 * h + 22 * l) / 451),
    mois = Math.floor((h + l - 7 * m + 114) / 31), jour = ((h + l - 7 * m + 114) % 31) + 1;
  const paques = Date.UTC(annee, mois - 1, jour);
  const iso = (t) => new Date(t).toISOString().slice(0, 10);
  const s = new Set(["01-01", "05-01", "05-08", "07-14", "08-15", "11-01", "11-11", "12-25"].map((md) => `${annee}-${md}`));
  for (const n of [1, 39, 50]) s.add(iso(paques + n * 86400000));
  return s;
}

// Jour ouvre suivant (YYYY-MM-DD) le jour civil de Paris de `maintenant` : ni samedi, ni dimanche, ni ferie.
export function jourOuvreSuivant(maintenant) {
  let t = Date.parse(`${dateParis(maintenant)}T12:00:00Z`);
  for (;;) {
    t += 86400000;
    const d = new Date(t);
    const dow = d.getUTCDay();
    const iso = d.toISOString().slice(0, 10);
    if (dow !== 0 && dow !== 6 && !feriesFR(d.getUTCFullYear()).has(iso)) return iso;
  }
}

export function echeanceJourOuvreSuivant(maintenant) {
  return normaliseEcheance(jourOuvreSuivant(maintenant)).valeur;
}

// Prochaine action d'un Contacte : la relance de la sequence si elle est a venir, sinon le jour
// ouvre suivant a 09:00. Libelle fixe : c'est Jules qui l'execute, pas de tache CRM.
export function prochaineRelance(sequence, maintenant) {
  const n = sequence && sequence.next_due_at;
  const t = n ? Date.parse(n) : NaN;
  let date = null;
  if (!isNaN(t) && t > new Date(maintenant).getTime()) {
    const r = normaliseEcheance(n);
    if (r.ok && r.valeur) date = r.valeur;
  }
  return { prochaine_action_date: date || echeanceJourOuvreSuivant(maintenant), prochaine_action_libelle: LIBELLE_RELANCE_CAMPAGNE };
}

// Evenement deduit du changement d'etat d'une sequence (etapes de bin/seqcadence.py : 0 identifie,
// 1 invite, 2 accepte, 3 message, 4-5 relances, 6 repondu, 7 converti). Un seul evenement par
// appel, le plus avance. `avant` null = sequence nouvelle (etape 0, active).
export function deduitEvenement(avant, apres) {
  const a = { etape: 0, statut: "active", nb_relances: 0, sentiment: null, ...(avant || {}) };
  const b = apres || {};
  const ea = Number(a.etape) || 0;
  const eb = Number(b.etape ?? ea) || 0;
  const na = Number(a.nb_relances) || 0;
  const nb = Number(b.nb_relances ?? na) || 0;
  const sa = a.statut || "active";
  const sbis = b.statut || sa;
  if (sbis === "converted" && sa !== "converted") return { type: "conversion" };
  if (sbis === "stopped" && sa !== "stopped") {
    if (eb <= 1) return { type: "expiration" };
    if (nb > na) return { type: "sortie", motif: "silence" };
    return { type: "sortie", motif: "autre" };
  }
  const repondu = (sbis === "replied" && sa !== "replied") || (eb >= 6 && ea < 6) || (!!b.sentiment && b.sentiment !== a.sentiment);
  if (repondu) return { type: "reponse", sentiment: b.sentiment || "neutre" };
  if (nb > na || (eb >= 4 && eb <= 5 && eb > ea)) return { type: "relance_envoyee" };
  if (eb >= 3 && ea < 3) return { type: "message_envoye" };
  if (eb >= 2 && ea < 2) return { type: "acceptee" };
  if (eb === 1 && ea < 1) return { type: "invite_envoyee" };
  return null;
}

// Evenement effectif d'un appel : l'explicite gagne ; sinon la deduction. Une relance qui clot la
// sequence (plan de relances epuise) est la « fin des relances sans reponse ».
export function resoutEvenement(params, avant, apres) {
  const base = { canal: params.canal || "linkedin", rdv_date: params.rdv_date || null };
  if (params.evenement) {
    const epuise = params.evenement === "relance_envoyee" && apres.statut === "stopped" && ((avant && avant.statut) || "active") !== "stopped";
    if (epuise) return { ...base, type: "sortie", motif: "silence", sentiment: null };
    return {
      ...base, type: params.evenement,
      motif: params.evenement === "sortie" ? (params.motif_sortie || "autre") : null,
      sentiment: params.evenement === "reponse" ? (params.sentiment || apres.sentiment || "neutre") : null,
    };
  }
  const d = deduitEvenement(avant, apres);
  if (!d) return null;
  const out = { ...base, sentiment: null, motif: null, ...d };
  if (out.type === "sortie" && params.motif_sortie) out.motif = params.motif_sortie;
  return out;
}

// Invitation envoyee, invitation expiree, doublon : rien au CRM, pas meme une lecture.
export function evenementSansEffet(evt) {
  return !evt || evt.type === "invite_envoyee" || evt.type === "expiration" || (evt.type === "sortie" && evt.motif === "doublon");
}

const SENTIMENT_FEMININ = { positif: "positive", neutre: "neutre", negatif: "négative" };

// Libelle d'historique d'un evenement. Il est STABLE : « Campagne <titre> : <libelle> » sert de
// temoin d'idempotence (un evenement rejoue retrouve sa ligne et ne reecrit rien).
export function libelleEvenement(evt, ctx = {}) {
  const jour = fmtJour(dateParis(ctx.maintenant || new Date()));
  switch (evt && evt.type) {
    case "acceptee": return "invitation acceptée";
    case "message_envoye": return "premier message envoyé";
    case "relance_envoyee": return `relance ${ctx.nbRelances || 1} envoyée`;
    case "mail_envoye": return `mail envoyé le ${jour}`;
    case "appel_passe": return `appel passé le ${jour}`;
    case "reponse": return `réponse ${SENTIMENT_FEMININ[evt.sentiment] || "neutre"}`;
    case "conversion": return "RDV pris";
    case "sortie": return LIBELLES_SORTIE[evt.motif] || LIBELLES_SORTIE.autre;
    default: return null;
  }
}

export function typeHistorique(evt) {
  if (evt.type === "mail_envoye") return "Mail envoyé";
  if (evt.type === "appel_passe") return "Appel sortant";
  if (evt.canal === "mail") return evt.type === "reponse" ? "Mail reçu" : "Mail envoyé";
  if (evt.canal === "appel") return "Appel sortant";
  return "LinkedIn";
}
```

- [ ] **Étape 4 : relancer toute la suite MCP**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes && node --test tests/*.test.mjs`
Attendu : tout passe (16 tests dans `campagne-rules.test.mjs`, les 49 tests existants inchangés).

- [ ] **Étape 5 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes add server/campagne-rules.mjs tests/campagne-rules.test.mjs
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes commit -m "feat(mcp): regles pures des campagnes de prospection (perimetre, LinkedIn, dates, evenement)"
```

---

## Tâche 3 : règles pures, partie 2 (correspondance du §4 et jeu de cas commun)

**Files :**
- Modify : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/server/campagne-rules.mjs` (ajout à la fin)
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/fixtures/campagne-sortie-cas.json`
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/campagne-effets.test.mjs`

**Interfaces :**
- Consumes (déjà dans `server/campagne-rules.mjs`, tâche 2) : `rangEtape`, `reveilSixMois`, `echeanceJourOuvreSuivant`, `prochaineRelance`, `LIBELLES_SORTIE`, `LIBELLE_CONFIRMER_RDV`, `MOTIF_PERTE_PROFIL`, et l'import `normaliseEcheance` de `./prospect-rules.mjs`.
- Produces :
  - `effetSortie(motif, contact) -> { action: 'rien'|'historique'|'etape'|'go', etape: string|null, motif_perte: string|null, reveil6m: boolean }` (forme partagée avec l'app, tâche 10) ;
  - `effetCampagneSurProspect(evt, contact, sequence, { maintenant, campagne }) -> { creer, patch, historique, tache: {titre, due}|null, go: {etape, motif_perte, motif_perte_precision}|null, arreterSequence, raison }`. `evt` = sortie de `resoutEvenement` ; `contact` = `{ id, prenom, nom, statut, responsable, etape_prospect }` ou `null` ; `sequence` = `{ next_due_at, nb_relances }`.
  Consommés par la tâche 6.
- Le fichier `tests/fixtures/campagne-sortie-cas.json` est copié à l'identique dans le repo web à la tâche 10.

Contexte : la table du §4 de la spec, pour une fiche absente, un Prospect à chaque étape (« Ne pas recontacter » compris) et un Client. « Une étape ne recule jamais » ; « Ne pas recontacter l'emporte sur tout » ; un non-Prospect ne bouge jamais (sauf GO « ne me contactez plus ») ; les sorties ne s'appliquent qu'aux étapes actives.

- [ ] **Étape 1 : écrire le jeu de cas commun**

Créer `tests/fixtures/campagne-sortie-cas.json` :

```json
{
  "commentaire": "Jeu de cas commun : copie identique dans tests/fixtures/ du repo web (worktree prospects-pipeline) et du repo MCP (worktree campagnes). Motif de sortie de campagne vers effet sur la fiche liee. action : rien, historique, etape ou go (GO de Nicolas cote Jules, applique directement par Nicolas dans l app). Toute modification se fait dans les deux copies.",
  "cas": [
    { "nom": "converti, A contacter : RDV planifie", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "À contacter" },
      "attendu": { "action": "etape", "etape": "RDV planifié", "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, prospect sans etape : RDV planifie", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": null },
      "attendu": { "action": "etape", "etape": "RDV planifié", "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, En discussion : RDV planifie", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "En discussion" },
      "attendu": { "action": "etape", "etape": "RDV planifié", "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, RDV planifie : pas de recul, historique", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "RDV planifié" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, Qualifie : pas de recul, historique", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "Qualifié" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, En veille : reprise en RDV planifie", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "En veille" },
      "attendu": { "action": "etape", "etape": "RDV planifié", "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, Perdu reste Perdu", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "Perdu" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, Client : statut intouche", "motif": "converti", "contact": { "statut": "Client", "etape_prospect": null },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "refus, Contacte : En veille a 6 mois", "motif": "refus", "contact": { "statut": "Prospect", "etape_prospect": "Contacté" },
      "attendu": { "action": "etape", "etape": "En veille", "motif_perte": null, "reveil6m": true } },
    { "nom": "refus, deja En veille : reveil repousse", "motif": "refus", "contact": { "statut": "Prospect", "etape_prospect": "En veille" },
      "attendu": { "action": "etape", "etape": "En veille", "motif_perte": null, "reveil6m": true } },
    { "nom": "refus, Perdu reste Perdu", "motif": "refus", "contact": { "statut": "Prospect", "etape_prospect": "Perdu" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "refus, Candidat : historique", "motif": "refus", "contact": { "statut": "Candidat", "etape_prospect": null },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "silence, Qualifie : En veille", "motif": "silence", "contact": { "statut": "Prospect", "etape_prospect": "Qualifié" },
      "attendu": { "action": "etape", "etape": "En veille", "motif_perte": null, "reveil6m": true } },
    { "nom": "profil, Contacte : GO Perdu", "motif": "profil", "contact": { "statut": "Prospect", "etape_prospect": "Contacté" },
      "attendu": { "action": "go", "etape": "Perdu", "motif_perte": "Pas le bon interlocuteur", "reveil6m": false } },
    { "nom": "profil, En veille : historique, la sortie est reservee aux etapes actives", "motif": "profil", "contact": { "statut": "Prospect", "etape_prospect": "En veille" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "profil, Client : rien", "motif": "profil", "contact": { "statut": "Client", "etape_prospect": null },
      "attendu": { "action": "rien", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "npc, En discussion : GO Ne pas recontacter", "motif": "npc", "contact": { "statut": "Prospect", "etape_prospect": "En discussion" },
      "attendu": { "action": "go", "etape": "Ne pas recontacter", "motif_perte": null, "reveil6m": false } },
    { "nom": "npc, Perdu : GO Ne pas recontacter, protection", "motif": "npc", "contact": { "statut": "Prospect", "etape_prospect": "Perdu" },
      "attendu": { "action": "go", "etape": "Ne pas recontacter", "motif_perte": null, "reveil6m": false } },
    { "nom": "npc, Client : GO Ne pas recontacter, protection", "motif": "npc", "contact": { "statut": "Client", "etape_prospect": null },
      "attendu": { "action": "go", "etape": "Ne pas recontacter", "motif_perte": null, "reveil6m": false } },
    { "nom": "doublon : rien", "motif": "doublon", "contact": { "statut": "Prospect", "etape_prospect": "Contacté" },
      "attendu": { "action": "rien", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "autre, Contacte : historique", "motif": "autre", "contact": { "statut": "Prospect", "etape_prospect": "Contacté" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "deja Ne pas recontacter : fige", "motif": "refus", "contact": { "statut": "Prospect", "etape_prospect": "Ne pas recontacter" },
      "attendu": { "action": "rien", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "npc sur une fiche deja Ne pas recontacter : fige", "motif": "npc", "contact": { "statut": "Client", "etape_prospect": "Ne pas recontacter" },
      "attendu": { "action": "rien", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "fiche absente : rien", "motif": "refus", "contact": null,
      "attendu": { "action": "rien", "etape": null, "motif_perte": null, "reveil6m": false } }
  ]
}
```

- [ ] **Étape 2 : écrire le test qui échoue**

Créer `tests/campagne-effets.test.mjs` :

```js
// Correspondance evenement de campagne -> fiche (SPEC_campagnes_prospection_etapes.md §4), en pur.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { effetSortie, effetCampagneSurProspect } from "../server/campagne-rules.mjs";

const NOW = new Date("2026-09-29T10:00:00+02:00");
const CTX = { maintenant: NOW, campagne: "Prospection DSI Lyon" };
const SEQ = { next_due_at: "2026-10-13T08:00:00+00:00", nb_relances: 0 };
const P = (etape) => ({ id: 7, prenom: "Jean", nom: "DUPONT", statut: "Prospect", responsable: "Nicolas Serradeil", etape_prospect: etape });
const CLIENT = { id: 8, prenom: "Marie", nom: "MARTIN", statut: "Client", responsable: "Camille Salinson", etape_prospect: null };
const COLONNES = ["absent", "À contacter", "Contacté", "En discussion", "RDV planifié", "Qualifié", "En veille", "Perdu", "Ne pas recontacter", "Client"];
const CONTACTS = [null, P("À contacter"), P("Contacté"), P("En discussion"), P("RDV planifié"), P("Qualifié"),
                  P("En veille"), P("Perdu"), P("Ne pas recontacter"), CLIENT];

// Resume d'un plan en un mot, pour lire la table d'un coup d'oeil.
function code(p) {
  if (p.arreterSequence) return "stop";
  if (p.creer) return "creer";
  if (p.go) return "go:" + p.go.etape;
  if (p.patch && p.patch.etape_prospect) return p.patch.etape_prospect + (p.tache ? "+tache" : "");
  if (p.tache) return "tache";
  if (p.patch) return "hist+relance";
  if (p.historique) return "hist";
  return "rien";
}

const SORTANT = ["creer", "Contacté", "hist+relance", "hist", "hist", "hist", "hist", "hist", "stop", "hist"];
const VEILLE = ["rien", "En veille", "En veille", "En veille", "En veille", "En veille", "En veille", "hist", "stop", "hist"];
const RDV = ["RDV planifié+tache", "RDV planifié+tache", "RDV planifié+tache", "hist", "hist", "RDV planifié+tache", "hist", "stop", "hist"];
const NPC = "go:Ne pas recontacter";
const TABLE = [
  [{ type: "acceptee" }, SORTANT],
  [{ type: "message_envoye" }, SORTANT],
  [{ type: "relance_envoyee" }, SORTANT],
  [{ type: "mail_envoye", canal: "mail" }, SORTANT],
  [{ type: "appel_passe", canal: "appel" }, SORTANT],
  [{ type: "reponse", sentiment: "positif" }, ["creer", "En discussion+tache", "En discussion+tache", "tache", "tache", "tache", "En discussion+tache", "tache", "stop", "tache"]],
  [{ type: "reponse", sentiment: "neutre" }, ["creer", "hist", "hist", "hist", "hist", "hist", "hist", "hist", "stop", "hist"]],
  [{ type: "reponse", sentiment: "negatif" }, ["creer", ...VEILLE.slice(1)]],
  [{ type: "conversion" }, ["creer", ...RDV]],
  [{ type: "sortie", motif: "converti" }, ["rien", ...RDV]],
  [{ type: "sortie", motif: "refus" }, VEILLE],
  [{ type: "sortie", motif: "silence" }, VEILLE],
  [{ type: "sortie", motif: "profil" }, ["rien", "go:Perdu", "go:Perdu", "go:Perdu", "go:Perdu", "go:Perdu", "hist", "hist", "stop", "rien"]],
  [{ type: "sortie", motif: "npc" }, ["rien", NPC, NPC, NPC, NPC, NPC, NPC, NPC, "stop", NPC]],
  [{ type: "sortie", motif: "doublon" }, Array(10).fill("rien")],
  [{ type: "sortie", motif: "autre" }, ["rien", "hist", "hist", "hist", "hist", "hist", "hist", "hist", "stop", "hist"]],
  [{ type: "invite_envoyee" }, Array(10).fill("rien")],
  [{ type: "expiration" }, Array(10).fill("rien")],
];

test("table du §4 : chaque evenement, fiche absente, Prospect a chaque etape, Client", () => {
  for (const [evt, attendus] of TABLE) {
    CONTACTS.forEach((c, i) => {
      const nom = `${evt.type}${evt.motif ? " " + evt.motif : ""}${evt.sentiment ? " " + evt.sentiment : ""} / ${COLONNES[i]}`;
      assert.equal(code(effetCampagneSurProspect(evt, c, SEQ, CTX)), attendus[i], nom);
    });
  }
});

test("une etape ne recule jamais : un Qualifie qui recoit une relance reste Qualifie, sans patch", () => {
  const p = effetCampagneSurProspect({ type: "relance_envoyee" }, P("Qualifié"), SEQ, CTX);
  assert.equal(p.patch, null);
  assert.equal(p.historique, true);
});

test("Contacte depuis A contacter : prochaine action = la relance de la sequence, libelle Jules, pas de tache", () => {
  const p = effetCampagneSurProspect({ type: "acceptee" }, P("À contacter"), SEQ, CTX);
  assert.deepEqual(p.patch, { etape_prospect: "Contacté", prochaine_action_date: "2026-10-13T08:00:00+00:00",
                              prochaine_action_libelle: "Relance campagne (Jules)" });
  assert.equal(p.tache, null, "c'est Jules qui relance : rien dans la todo de Nicolas");
});

test("reponse positive : En discussion et tache Repondre a X le jour ouvre suivant a 09h00", () => {
  const p = effetCampagneSurProspect({ type: "reponse", sentiment: "positif" }, P("Contacté"), SEQ, CTX);
  assert.deepEqual(p.tache, { titre: "Répondre à Jean DUPONT", due: "2026-09-30T09:00:00+02:00" });
  assert.equal(p.patch.etape_prospect, "En discussion");
  assert.equal(p.patch.prochaine_action_date, "2026-09-30T09:00:00+02:00");
});

test("refus : En veille, reveil a 6 mois 09h00 avec decalage, precision du refus", () => {
  const p = effetCampagneSurProspect({ type: "sortie", motif: "refus" }, P("En discussion"), SEQ, CTX);
  assert.equal(p.patch.etape_prospect, "En veille");
  assert.equal(p.patch.prochaine_action_date, "2027-03-29T09:00:00+02:00");
  assert.equal(p.patch.prochaine_action_libelle, "Réveil prospect");
  assert.equal(p.patch.motif_perte_precision, "Refus en campagne Prospection DSI Lyon");
});

test("silence au bout des relances : En veille avec sa precision", () => {
  const p = effetCampagneSurProspect({ type: "sortie", motif: "silence" }, P("Contacté"), SEQ, CTX);
  assert.equal(p.patch.etape_prospect, "En veille");
  assert.equal(p.patch.motif_perte_precision, "Sans réponse à la campagne Prospection DSI Lyon");
});

test("RDV pris avec date : prochaine action a la date du RDV, sans tache", () => {
  const p = effetCampagneSurProspect({ type: "conversion", rdv_date: "2026-10-06T14:30" }, P("En discussion"), SEQ, CTX);
  assert.deepEqual(p.patch, { etape_prospect: "RDV planifié", prochaine_action_date: "2026-10-06T14:30:00+02:00",
                              prochaine_action_libelle: "RDV prospect" });
  assert.equal(p.tache, null);
});

test("RDV pris sans date : Confirmer la date du RDV le jour ouvre suivant, avec tache", () => {
  const p = effetCampagneSurProspect({ type: "conversion" }, P("Contacté"), SEQ, CTX);
  assert.equal(p.patch.prochaine_action_libelle, "Confirmer la date du RDV");
  assert.equal(p.patch.prochaine_action_date, "2026-09-30T09:00:00+02:00");
  assert.deepEqual(p.tache, { titre: "Confirmer la date du RDV : Jean DUPONT", due: "2026-09-30T09:00:00+02:00" });
});

test("Ne pas recontacter et Perdu : GO demande, aucune etape posee", () => {
  const npc = effetCampagneSurProspect({ type: "sortie", motif: "npc" }, P("Contacté"), SEQ, CTX);
  assert.equal(npc.patch, null);
  assert.deepEqual(npc.go, { etape: "Ne pas recontacter", motif_perte: null, motif_perte_precision: "Demande en campagne Prospection DSI Lyon" });
  const perdu = effetCampagneSurProspect({ type: "sortie", motif: "profil" }, P("Contacté"), SEQ, CTX);
  assert.equal(perdu.patch, null);
  assert.deepEqual(perdu.go, { etape: "Perdu", motif_perte: "Pas le bon interlocuteur",
                               motif_perte_precision: "Sortie de la campagne Prospection DSI Lyon : pas le bon profil" });
});

test("Ne pas recontacter est fige : aucune ecriture, la sequence doit s'arreter", () => {
  for (const evt of [{ type: "reponse", sentiment: "positif" }, { type: "acceptee" }, { type: "sortie", motif: "npc" }]) {
    const p = effetCampagneSurProspect(evt, P("Ne pas recontacter"), SEQ, CTX);
    assert.equal(p.arreterSequence, true, evt.type);
    assert.equal(p.patch, null); assert.equal(p.historique, false); assert.equal(p.tache, null); assert.equal(p.go, null);
  }
});

test("un Client n'est jamais deplace dans le pipeline", () => {
  for (const [evt] of TABLE) assert.equal(effetCampagneSurProspect(evt, CLIENT, SEQ, CTX).patch, null, evt.type);
});

test("jeu de cas commun avec l'app : correspondance des sorties manuelles", () => {
  const cas = JSON.parse(readFileSync(new URL("./fixtures/campagne-sortie-cas.json", import.meta.url), "utf8")).cas;
  assert.ok(cas.length >= 20);
  for (const c of cas) assert.deepEqual(effetSortie(c.motif, c.contact), c.attendu, c.nom);
});
```

- [ ] **Étape 3 : le lancer et le voir échouer**

Commande : `node --test /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/campagne-effets.test.mjs`
Attendu : `SyntaxError: The requested module '../server/campagne-rules.mjs' does not provide an export named 'effetCampagneSurProspect'` (ou `'effetSortie'`).

- [ ] **Étape 4 : implémenter**

Ajouter à la FIN de `server/campagne-rules.mjs` (après `typeHistorique`) :

```js
// ── Correspondance evenement de campagne -> fiche (SPEC §4) ──

// Sortie d'une personne (motif) -> effet sur sa fiche. Forme partagee avec l'app (campagneEffetSortie
// dans index.html), verrouillee par tests/fixtures/campagne-sortie-cas.json :
// { action: 'rien'|'historique'|'etape'|'go', etape, motif_perte, reveil6m }.
// « Ne pas recontacter » l'emporte sur tout ; les sorties En veille et Perdu ne s'appliquent qu'a une
// etape active (un En veille qui refuse voit seulement son reveil repousse) ; un Perdu reste Perdu ;
// un non-Prospect ne bouge jamais, sauf « ne me contactez plus » (protection, via GO).
export function effetSortie(motif, contact) {
  const r = (action, etape = null, motif_perte = null, reveil6m = false) => ({ action, etape, motif_perte, reveil6m });
  if (!contact) return r("rien");
  if (contact.etape_prospect === "Ne pas recontacter") return r("rien");
  if (motif === "doublon") return r("rien");
  if (motif === "npc") return r("go", "Ne pas recontacter");
  if (contact.statut !== "Prospect") return motif === "profil" ? r("rien") : r("historique");
  const etape = contact.etape_prospect || "À contacter";
  if (etape === "Perdu") return r("historique");
  const rang = rangEtape(etape);
  if (motif === "profil") return rang >= 0 ? r("go", "Perdu", MOTIF_PERTE_PROFIL) : r("historique");
  if (motif === "refus" || motif === "silence") return r("etape", "En veille", null, true);
  if (motif === "converti") {
    return (etape === "En veille" || (rang >= 0 && rang < rangEtape("RDV planifié"))) ? r("etape", "RDV planifié") : r("historique");
  }
  return r("historique");
}

const EVT_CONTACT = new Set(["acceptee", "message_envoye", "relance_envoyee", "mail_envoye", "appel_passe", "reponse", "conversion"]);

// Ce qu'un evenement produit sur une fiche (null = aucune fiche trouvee). Plan :
// { creer, patch, historique, tache: {titre, due}|null, go: {etape, motif_perte, motif_perte_precision}|null,
//   arreterSequence, raison }. `patch` ne contient que les champs contacts a ecrire (etape_prospect si
// l'etape bouge). Jamais de recul : l'etape cible n'est retenue que si elle est plus avancee.
export function effetCampagneSurProspect(evt, contact, sequence, ctx = {}) {
  const maintenant = ctx.maintenant || new Date();
  const campagne = ctx.campagne || "";
  const plan = { creer: false, patch: null, historique: false, tache: null, go: null, arreterSequence: false, raison: "" };
  const type = evt && evt.type;
  if (!type || !(EVT_CONTACT.has(type) || type === "sortie")) return { ...plan, raison: "aucun effet CRM pour cet événement" };
  if (type === "sortie" && evt.motif === "doublon") return { ...plan, raison: "doublon : aucun effet CRM" };
  if (!contact) {
    if (type === "sortie") return { ...plan, raison: "aucune fiche liée : rien à sortir" };
    return { ...plan, creer: true, raison: "première tentative de contact : fiche à créer" };
  }
  if (contact.etape_prospect === "Ne pas recontacter") {
    return { ...plan, arreterSequence: true, raison: "fiche en « Ne pas recontacter », la campagne ne la touche plus" };
  }
  const qui = [contact.prenom, contact.nom].filter(Boolean).join(" ");
  let motif = null;
  if (type === "sortie") motif = evt.motif || "autre";
  else if (type === "reponse" && evt.sentiment === "negatif") motif = "refus";
  else if (type === "conversion") motif = "converti";
  if (motif) {
    const s = effetSortie(motif, contact);
    if (s.action === "rien") return { ...plan, raison: `${LIBELLES_SORTIE[motif]} : aucun effet sur cette fiche` };
    if (s.action === "historique") return { ...plan, historique: true, raison: "historique seulement" };
    if (s.action === "go") {
      const precision = s.etape === "Ne pas recontacter" ? `Demande en campagne ${campagne}` : `Sortie de la campagne ${campagne} : pas le bon profil`;
      return { ...plan, historique: true, go: { etape: s.etape, motif_perte: s.motif_perte, motif_perte_precision: precision },
        raison: `GO de Nicolas requis pour « ${s.etape} »` };
    }
    if (s.etape === "En veille") {
      return { ...plan, historique: true, raison: "En veille, réveil à 6 mois",
        patch: { etape_prospect: "En veille", prochaine_action_date: reveilSixMois(maintenant), prochaine_action_libelle: "Réveil prospect",
          motif_perte_precision: motif === "silence" ? `Sans réponse à la campagne ${campagne}` : `Refus en campagne ${campagne}` } };
    }
    const rdv = evt.rdv_date ? normaliseEcheance(evt.rdv_date) : { ok: false };
    if (rdv.ok && rdv.valeur) {
      return { ...plan, historique: true, raison: "RDV planifié à la date du RDV",
        patch: { etape_prospect: "RDV planifié", prochaine_action_date: rdv.valeur, prochaine_action_libelle: "RDV prospect" } };
    }
    const due = echeanceJourOuvreSuivant(maintenant);
    return { ...plan, historique: true, raison: "RDV planifié, date à confirmer",
      patch: { etape_prospect: "RDV planifié", prochaine_action_date: due, prochaine_action_libelle: LIBELLE_CONFIRMER_RDV },
      tache: { titre: `${LIBELLE_CONFIRMER_RDV} : ${qui}`, due } };
  }
  const etape = contact.statut === "Prospect" ? (contact.etape_prospect || "À contacter") : null;
  if (type === "reponse") {
    if (evt.sentiment !== "positif") return { ...plan, historique: true, raison: "réponse neutre : historique" };
    const tache = { titre: `Répondre à ${qui}`, due: echeanceJourOuvreSuivant(maintenant) };
    const avance = etape !== null && (etape === "En veille" || (rangEtape(etape) >= 0 && rangEtape(etape) < rangEtape("En discussion")));
    return { ...plan, historique: true, tache,
      patch: avance ? { etape_prospect: "En discussion", prochaine_action_date: tache.due, prochaine_action_libelle: `Répondre à ${qui}` } : null,
      raison: avance ? "réponse positive : En discussion" : "réponse positive : étape conservée" };
  }
  // Tentative de contact sortante : acceptee, message, relance, mail, appel.
  if (etape === "À contacter") return { ...plan, historique: true, patch: { etape_prospect: "Contacté", ...prochaineRelance(sequence, maintenant) }, raison: "Contacté" };
  if (etape === "Contacté") return { ...plan, historique: true, patch: prochaineRelance(sequence, maintenant), raison: "prochaine relance reportée sur la fiche" };
  return { ...plan, historique: true, raison: "historique seulement" };
}
```

- [ ] **Étape 5 : relancer toute la suite MCP**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes && node --test tests/*.test.mjs`
Attendu : tout passe (12 tests dans `campagne-effets.test.mjs`, dont la table complète et le jeu de cas commun ; le test « aucun tiret cadratin » de `campagne-rules.test.mjs` passe toujours).

- [ ] **Étape 6 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes add server/campagne-rules.mjs tests/campagne-effets.test.mjs tests/fixtures/campagne-sortie-cas.json
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes commit -m "feat(mcp): correspondance evenement de campagne vers fiche prospect, jeu de cas commun des sorties"
```

---

## Tâche 4 : construction d'une fiche contact partagée (`contact-norm.mjs`)

**Files :**
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/server/contact-norm.mjs`
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/contact-norm.test.mjs`
- Modify : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/server/index.mjs` (définitions `decodeUnicode` à `normVille` près de `function fmtDate`, import en tête, handler de `crm_create_contact`)

**Interfaces :**
- Consumes : rien de nouveau.
- Produces (exports de `server/contact-norm.mjs`) : `decodeUnicode(s)`, `normNom(s)`, `normPrenom(s)`, `normEmail(s)`, `normVille(s)`, `normLinkedinUrl(v) -> string|null`, `donneesNouveauContact(p) -> objet contacts` (`p` = paramètres de `crm_create_contact` avec `agence` résolue et `role` déjà normalisé). Consommés par `index.mjs` (ici) et par la tâche 5 (`creeFicheProspect`).

Contexte : `index.mjs` démarre le serveur MCP à l'import (`main()` en bas du fichier) : on ne peut ni le tester ni l'importer depuis un autre module. On extrait donc la normalisation, à comportement strictement identique, pour que la création de fiche des campagnes réutilise celle de `crm_create_contact` (spec §6.3 : « réutilise l'existant »). Le reste de `index.mjs` (anti-doublon, `crm_update_contact`, autres outils) continue d'appeler `normNom`, `normVille`... qui deviennent des imports.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/contact-norm.test.mjs` :

```js
// La construction d'une fiche contact est partagee entre crm_create_contact et les campagnes de
// prospection : une seule normalisation, sinon deux portes produisent deux formats.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { donneesNouveauContact, normNom, normPrenom, normLinkedinUrl } from "../server/contact-norm.mjs";

test("donneesNouveauContact : la fiche que crm_create_contact construisait avant l'extraction", () => {
  const d = donneesNouveauContact({ nom: "dupont", prenom: "jean-émile", statut: "Prospect", responsable: "Nicolas Serradeil",
    agence: "Lyon", groupe: "Crédit Agricole", email: " Jean.Dupont@CA.fr ", ville: "lyon", linkedin: "www.linkedin.com/in/jean-dupont" });
  assert.match(d.updated_at, /^\d{4}-\d{2}-\d{2}T/);
  delete d.updated_at;
  assert.deepEqual(d, { nom: "DUPONT", prenom: "Jean-Émile", employeur: null, statut: "Prospect", responsable: "Nicolas Serradeil",
    agence: "Lyon", email: "jean.dupont@ca.fr", telephone: null, role: null, ville: "Lyon", commentaires: null,
    linkedin: "https://www.linkedin.com/in/jean-dupont", nb_relance: 0, etape_prospect: "À contacter" });
});

test("un Candidat garde sa societe dans employeur et n'entre pas au pipeline", () => {
  const d = donneesNouveauContact({ nom: "Martin", prenom: "marie", statut: "Candidat", responsable: "Nicolas Serradeil", agence: "Lyon", groupe: "Sopra Steria" });
  assert.equal(d.employeur, "Sopra Steria");
  assert.equal("etape_prospect" in d, false);
});

test("normalisations unitaires", () => {
  assert.equal(normNom("dupr\\u00e9"), "DUPRÉ");
  assert.equal(normPrenom("anne  claire"), "Anne Claire");
  assert.equal(normLinkedinUrl("https://www.linkedin.com/in/x/"), "https://www.linkedin.com/in/x/");
  assert.equal(normLinkedinUrl(""), null);
});

test("index.mjs importe la normalisation au lieu de la redefinir", () => {
  const src = readFileSync(new URL("../server/index.mjs", import.meta.url), "utf8");
  assert.match(src, /import \{ decodeUnicode, normNom, normPrenom, normEmail, normVille, donneesNouveauContact \} from "\.\/contact-norm\.mjs";/);
  assert.doesNotMatch(src, /\nfunction (decodeUnicode|normNom|normPrenom|normEmail|normVille)\(/);
  assert.match(src, /const data = donneesNouveauContact\(\{/);
});

test("aucun tiret cadratin ni demi-cadratin dans le module", () => {
  const src = readFileSync(new URL("../server/contact-norm.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(src, /[\u2013\u2014]/);
});
```

- [ ] **Étape 2 : le lancer et le voir échouer**

Commande : `node --test /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/contact-norm.test.mjs`
Attendu : `Error [ERR_MODULE_NOT_FOUND]: Cannot find module '.../server/contact-norm.mjs'`.

- [ ] **Étape 3 : créer le module**

Créer `server/contact-norm.mjs` :

```js
// Normalisation d'une fiche contact, partagee par crm_create_contact (index.mjs) et par la creation
// de fiche des campagnes de prospection (campagne-crm.mjs). Fonctions pures, sans reseau.
export function decodeUnicode(s) {
  return String(s ?? "").replace(/\\u([0-9a-fA-F]{4})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
}
export function normNom(s) { return decodeUnicode(s).trim().toUpperCase(); }
export function normPrenom(s) {
  return decodeUnicode(s).trim().split(/\s+/).map(w => w.split("-").map(p => p.charAt(0).toUpperCase() + p.slice(1).toLowerCase()).join("-")).join(" ");
}
export function normEmail(s) { return s.trim().toLowerCase(); }
export function normVille(s) { return s.trim().charAt(0).toUpperCase() + s.trim().slice(1).toLowerCase(); }
export function normLinkedinUrl(v) {
  if (!v) return null;
  const s = String(v).trim();
  return s.startsWith("http") ? s : "https://" + s;
}

// Fiche a inserer dans `contacts`, exactement comme crm_create_contact la construisait avant
// l'extraction. `p.role` arrive deja normalise par l'appelant (nomenclature metier des consultants),
// `p.agence` deja resolue. Un Prospect entre au pipeline a l'etape « À contacter ».
export function donneesNouveauContact(p) {
  const isCandidat = p.statut === "Candidat";
  const societe = p.groupe || p.employeur || "";
  const data = {
    nom: normNom(p.nom), prenom: normPrenom(p.prenom),
    employeur: isCandidat ? (societe || null) : (p.employeur || null),
    statut: p.statut, responsable: p.responsable, agence: p.agence,
    email: p.email ? normEmail(p.email) : null, telephone: p.telephone || null,
    role: p.role || null,
    ville: p.ville ? normVille(p.ville) : null,
    commentaires: p.commentaires || null, linkedin: normLinkedinUrl(p.linkedin),
    nb_relance: 0, updated_at: new Date().toISOString(),
  };
  if (p.statut === "Prospect") data.etape_prospect = "À contacter";
  return data;
}
```

- [ ] **Étape 4 : brancher `index.mjs`**

4a. Dans `server/index.mjs`, juste APRÈS la ligne qui commence par `import { PROSPECT_ETAPES, valideChangementEtape,` (ligne d'import de `./prospect-rules.mjs`), ajouter la ligne :

```js
import { decodeUnicode, normNom, normPrenom, normEmail, normVille, donneesNouveauContact } from "./contact-norm.mjs";
```

4b. Supprimer ces six définitions (juste après `function fmtDate`), remplacées par l'import :

```js
function decodeUnicode(s) { return s.replace(/\\u([0-9a-fA-F]{4})/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16))); }
function normNom(s) { return decodeUnicode(s).trim().toUpperCase(); }
function normPrenom(s) {
  return decodeUnicode(s).trim().split(/\s+/).map(w => w.split("-").map(p => p.charAt(0).toUpperCase() + p.slice(1).toLowerCase()).join("-")).join(" ");
}
function normEmail(s) { return s.trim().toLowerCase(); }
function normVille(s) { return s.trim().charAt(0).toUpperCase() + s.trim().slice(1).toLowerCase(); }
```

4c. Dans le handler de `crm_create_contact`, remplacer ce bloc (de `const isCandidat` jusqu'à la ligne `if (params.statut === "Prospect") data.etape_prospect = "À contacter";` incluse) :

```js
    const isCandidat = params.statut === "Candidat";
    // Candidat : société = employeur (texte). Prospect/Client : lien compte (contact_compte) posé plus bas.
    // Phase 5 : on n'écrit plus la colonne groupe (condamnée au DROP).
    const societe = params.groupe || params.employeur || "";
    const data = {
      nom: nNom, prenom: nPrenom,
      employeur: isCandidat ? (societe || null) : (params.employeur || null),
      statut: params.statut, responsable: params.responsable, agence: params.agence || getAgenceFromResponsable(params.responsable),
      email: params.email ? normEmail(params.email) : null, telephone: params.telephone || null,
      role: (CONSULTANT_STATUTS_MCP.has(params.statut) ? normMetier(params.role).val : (params.role || "")) || null,
      ville: params.ville ? normVille(params.ville) : null,
      commentaires: params.commentaires || null, linkedin: params.linkedin ? (params.linkedin.trim().startsWith('http') ? params.linkedin.trim() : 'https://'+params.linkedin.trim()) : null,
      nb_relance: 0, updated_at: new Date().toISOString(),
    };
    // Un Prospect entre au pipeline à l'étape « À contacter » (les autres statuts n'ont pas d'étape).
    if (params.statut === "Prospect") data.etape_prospect = "À contacter";
```

par :

```js
    // Candidat : société = employeur (texte). Prospect/Client : lien compte (contact_compte) posé plus bas.
    // Phase 5 : on n'écrit plus la colonne groupe (condamnée au DROP). La fiche est construite par
    // donneesNouveauContact (contact-norm.mjs), partagée avec la création depuis une campagne de prospection.
    const societe = params.groupe || params.employeur || "";
    const data = donneesNouveauContact({
      ...params,
      agence: params.agence || getAgenceFromResponsable(params.responsable),
      role: (CONSULTANT_STATUTS_MCP.has(params.statut) ? normMetier(params.role).val : (params.role || "")) || null,
    });
```

La variable `societe` reste utilisée plus bas (lien au compte) ; `nNom` et `nPrenom` restent utilisés par l'anti-doublon au-dessus : ne pas les supprimer.

- [ ] **Étape 5 : vérifier**

Commandes :
`cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes && node --check server/index.mjs && node --test tests/*.test.mjs`
Attendu : `node --check` silencieux, tous les tests passent (5 dans `contact-norm.test.mjs`).

- [ ] **Étape 6 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes add server/contact-norm.mjs server/index.mjs tests/contact-norm.test.mjs
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes commit -m "refactor(mcp): construction de fiche contact partagee (contact-norm.mjs), crm_create_contact inchange"
```

---

## Tâche 5 : recherche, lien et création de la fiche (`campagne-crm.mjs`, partie 1)

**Files :**
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/fausse-base.mjs`
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/server/campagne-crm.mjs`
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/campagne-fiche.test.mjs`

**Interfaces :**
- Consumes : `server/campagne-rules.mjs` : `slugLinkedin`, `normIdentite`, `normSociete`, `prochaineRelance` ; `server/contact-norm.mjs` : `donneesNouveauContact`. Dépendances injectées `deps` : `sbGet(table, params)`, `sbPost(table, data) -> ligne`, `sbPatch(table, filtresEgalite, data) -> ligne|{}`, `resolveCompteId(nom) -> { id, nom }`, `syncContactCompte(contactId, compteId)`, `getAgenceFor(nom) -> agence`, `getAuthCaller() -> { nom, role }|null` (mêmes signatures que dans `index.mjs`).
- Produces (exports de `server/campagne-crm.mjs`) :
  - `COLS_CONTACT_CAMPAGNE` (chaîne `select`) ;
  - `societesDe(deps, contacts) -> { [id]: societe }` ;
  - `rechercheFiche(deps, { sequence, identite, contactIdExplicite, nouvelleFiche }) -> { statut: 'liee'|'trouvee'|'homonyme'|'aucune'|'supprimee', contact, via, homonymes, identiteManquante }` ;
  - `lieSequence(deps, sequence, mission, contact, via)` (pose `contact_id`, trace `campagne.fiche_liee`, met à jour `sequence.contact_id`) ;
  - `creeFicheProspect(deps, { identite, owner, campagne, sequence, maintenant }) -> contact` ;
  - `proprietaireCampagne(deps, mission) -> nom`.
  - `tests/fausse-base.mjs` : `fausseBase(init) -> { tables, journal, sbGet, sbPost, sbPatch, sbDelete, sbRpc, lectures(table), ecritures(table) }`. Consommé par les tests des tâches 6, 7, 8.
  Consommés par les tâches 6, 7, 8.

Contexte : ordre de recherche du §3 de la spec (lien de la séquence, profil LinkedIn normalisé, prénom + nom + société ; homonyme dans une autre société = question). Société d'une fiche : compte primaire (`contact_compte.is_primary`, puis `comptes.nom`) pour un Prospect ou un Client, sinon `employeur` (même règle que `societeByContact` de `index.mjs`, en lectures ciblées). `agent_events` n'a pas de contrainte sur `kind`. `fausse-base.mjs` n'est pas une suite (pas de suffixe `.test.mjs`) : `node --test tests/*.test.mjs` ne le lance pas.

- [ ] **Étape 1 : écrire la fausse base**

Créer `tests/fausse-base.mjs` :

```js
// tests/fausse-base.mjs : fausse base PostgREST en memoire, pour tester campagne-crm.mjs et
// agent_sequence_upsert sans reseau. Filtres geres : eq, neq, ilike, like (joker *), in, not.in,
// is.null, et or=(champ.op.valeur,...). select, limit, order et offset ne filtrent pas (select reste
// dans le journal, pour les tests d'egress). Ce fichier n'est pas une suite de tests (pas de .test.mjs).
let compteur = 1000;
const nouvelId = (table) => {
  compteur += 1;
  return table.startsWith("agent_") ? `00000000-0000-4000-8000-${String(compteur).padStart(12, "0")}` : compteur;
};
function motif(pat, flags) {
  const corps = String(pat).split("*").map((s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*");
  return new RegExp(`^${corps}$`, flags);
}
function teste(val, cond) {
  const s = val === null || val === undefined ? null : String(val);
  if (cond.startsWith("eq.")) return s === cond.slice(3);
  if (cond.startsWith("neq.")) return s !== cond.slice(4);
  if (cond.startsWith("ilike.")) return s !== null && motif(cond.slice(6), "i").test(s);
  if (cond.startsWith("like.")) return s !== null && motif(cond.slice(5), "").test(s);
  if (cond.startsWith("in.(")) return cond.slice(4, -1).split(",").includes(s);
  if (cond.startsWith("not.in.(")) return !cond.slice(8, -1).split(",").includes(s);
  if (cond === "is.null") return s === null;
  throw new Error(`filtre non gere par la fausse base : ${cond}`);
}
const NON_FILTRES = new Set(["select", "limit", "order", "offset"]);
function garde(r, params) {
  return Object.entries(params).every(([k, v]) => {
    if (NON_FILTRES.has(k)) return true;
    if (k === "or") {
      return String(v).slice(1, -1).split(",").some((c) => {
        const i = c.indexOf(".");
        return teste(r[c.slice(0, i)], c.slice(i + 1));
      });
    }
    return teste(r[k], String(v));
  });
}
export function fausseBase(init = {}) {
  const tables = {};
  for (const [k, rows] of Object.entries(init)) tables[k] = rows.map((r) => ({ ...r }));
  const t = (n) => (tables[n] ||= []);
  const journal = [];
  return {
    tables, journal,
    sbGet: async (table, params = {}) => {
      journal.push(["GET", table, params]);
      let rows = t(table).filter((r) => garde(r, params));
      if (params.limit !== undefined) rows = rows.slice(0, Number(params.limit));
      return rows.map((r) => ({ ...r }));
    },
    sbPost: async (table, data) => {
      journal.push(["POST", table, data]);
      const row = { ...data, id: data.id ?? nouvelId(table) };
      t(table).push(row);
      return { ...row };
    },
    sbPatch: async (table, filters, data) => {
      journal.push(["PATCH", table, filters, data]);
      const rows = t(table).filter((r) => Object.entries(filters).every(([k, v]) => String(r[k]) === String(v)));
      rows.forEach((r) => Object.assign(r, data));
      return rows.length ? { ...rows[0] } : {};
    },
    sbDelete: async () => true,
    sbRpc: async () => ({}),
    lectures: (table) => journal.filter(([op, tb]) => op === "GET" && tb === table),
    ecritures: (table) => journal.filter(([op, tb]) => op !== "GET" && tb === table),
  };
}
```

- [ ] **Étape 2 : écrire le test qui échoue**

Créer `tests/campagne-fiche.test.mjs` :

```js
// Recherche, lien et creation de la fiche d'une personne de campagne (SPEC §3), sur fausse base.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fausseBase } from "./fausse-base.mjs";
import { rechercheFiche, creeFicheProspect, proprietaireCampagne, lieSequence } from "../server/campagne-crm.mjs";

const JEAN = { id: 5, prenom: "Jean", nom: "DUPONT", statut: "Prospect", responsable: "Nicolas Serradeil", etape_prospect: "Contacté",
               employeur: null, linkedin: "https://www.linkedin.com/in/jean-dupont/" };
const seq = (extra = {}) => ({ id: "S1", contact_id: null, target_kind: "externe", target_ref: "inconnu", target_label: "Jean Dupont", ...extra });
const HOMONYME = { id: 9, prenom: "Jean", nom: "DUPONT", statut: "Prospect", responsable: "Camille Salinson", etape_prospect: "Contacté", employeur: null, linkedin: null };
const avecCompte = (init = {}) => fausseBase({ contacts: [HOMONYME], contact_compte: [{ contact_id: 9, compte_id: "c1", is_primary: true }],
                                               comptes: [{ id: "c1", nom: "Crédit Agricole" }], ...init });

test("1. la sequence porte deja un lien : on s'arrete la", async () => {
  const b = fausseBase({ contacts: [JEAN] });
  const r = await rechercheFiche(b, { sequence: seq({ contact_id: 5, target_ref: "autre-slug" }) });
  assert.equal(r.statut, "liee"); assert.equal(r.contact.id, 5); assert.equal(r.via, "lien de la séquence");
});

test("une sequence contact_crm designe sa fiche par target_ref", async () => {
  const b = fausseBase({ contacts: [JEAN] });
  const r = await rechercheFiche(b, { sequence: seq({ target_kind: "contact_crm", target_ref: "5" }) });
  assert.equal(r.statut, "liee"); assert.equal(r.contact.id, 5);
});

test("un lien explicite (reponse de Nicolas) passe avant tout", async () => {
  const b = avecCompte();
  const r = await rechercheFiche(b, { sequence: seq(), contactIdExplicite: 9 });
  assert.equal(r.statut, "liee"); assert.equal(r.contact.id, 9); assert.equal(r.via, "lien explicite");
});

test("meme profil LinkedIn malgre parametres de suivi, slash final, casse et sous-domaine", async () => {
  const b = fausseBase({ contacts: [JEAN] });
  const r = await rechercheFiche(b, { sequence: seq(), identite: { linkedin_url: "https://fr.linkedin.com/in/Jean-Dupont?trk=abc" } });
  assert.equal(r.statut, "trouvee"); assert.equal(r.contact.id, 5); assert.equal(r.via, "profil LinkedIn");
});

test("le slug de target_ref suffit quand linkedin_url manque", async () => {
  const b = fausseBase({ contacts: [JEAN] });
  const r = await rechercheFiche(b, { sequence: seq({ target_ref: "jean-dupont" }) });
  assert.equal(r.statut, "trouvee"); assert.equal(r.contact.id, 5);
});

test("un slug accentue stocke encode est retrouve", async () => {
  const b = fausseBase({ contacts: [{ ...JEAN, id: 6, linkedin: "https://www.linkedin.com/in/aur%C3%A9lien-x" }] });
  const r = await rechercheFiche(b, { sequence: seq({ target_ref: "aurélien-x" }) });
  assert.equal(r.statut, "trouvee"); assert.equal(r.contact.id, 6);
});

test("3. meme prenom, nom et societe (compte primaire d'un Prospect)", async () => {
  const b = avecCompte();
  const r = await rechercheFiche(b, { sequence: seq(), identite: { prenom: "jean", nom: "Dupont", societe: "credit agricole" } });
  assert.equal(r.statut, "trouvee"); assert.equal(r.contact.id, 9); assert.equal(r.via, "prénom, nom et société");
});

test("la societe d'un Candidat est son employeur", async () => {
  const b = fausseBase({ contacts: [{ ...HOMONYME, id: 10, statut: "Candidat", employeur: "Sopra Steria" }] });
  const r = await rechercheFiche(b, { sequence: seq(), identite: { prenom: "Jean", nom: "Dupont", societe: "Sopra Steria" } });
  assert.equal(r.statut, "trouvee"); assert.equal(r.contact.id, 10);
});

test("REVIEW FOCUS 3 : homonyme dans une autre societe, ni lien ni creation, les fiches pour la question", async () => {
  const b = avecCompte();
  const r = await rechercheFiche(b, { sequence: seq(), identite: { prenom: "Jean", nom: "Dupont", societe: "Orange" } });
  assert.equal(r.statut, "homonyme"); assert.equal(r.contact, null);
  assert.deepEqual(r.homonymes, [{ id: 9, prenom: "Jean", nom: "DUPONT", statut: "Prospect", societe: "Crédit Agricole" }]);
});

test("meme nom sans societe connue : c'est aussi une question", async () => {
  const b = avecCompte();
  const r = await rechercheFiche(b, { sequence: seq(), identite: { prenom: "Jean", nom: "Dupont" } });
  assert.equal(r.statut, "homonyme");
});

test("nouvelle_fiche (decision de Nicolas) : l'homonyme ne bloque plus la creation", async () => {
  const b = avecCompte();
  const r = await rechercheFiche(b, { sequence: seq(), identite: { prenom: "Jean", nom: "Dupont", societe: "Orange" }, nouvelleFiche: true });
  assert.equal(r.statut, "aucune");
});

test("rien trouve", async () => {
  const b = fausseBase({ contacts: [] });
  const r = await rechercheFiche(b, { sequence: seq(), identite: { prenom: "Jean", nom: "Dupont", societe: "Orange" } });
  assert.equal(r.statut, "aucune");
});

test("REVIEW FOCUS 5 : identite manquante et aucun profil LinkedIn trouve", async () => {
  const b = fausseBase({ contacts: [JEAN] });
  const r = await rechercheFiche(b, { sequence: seq(), identite: {} });
  assert.equal(r.statut, "aucune"); assert.equal(r.identiteManquante, true);
});

test("REVIEW FOCUS 2 : fiche liee puis supprimee (contact_id remis a null) : jamais recreee", async () => {
  const b = fausseBase({ contacts: [], agent_events: [{ id: 1, sequence_id: "S1", kind: "campagne.fiche_liee" }] });
  const r = await rechercheFiche(b, { sequence: seq(), identite: { prenom: "Jean", nom: "Dupont", societe: "Orange" } });
  assert.equal(r.statut, "supprimee");
  const r2 = await rechercheFiche(b, { sequence: seq(), identite: {} });
  assert.equal(r2.statut, "supprimee");
});

test("fiche supprimee mais une autre fiche porte le meme profil : on lie celle qui existe", async () => {
  const b = fausseBase({ contacts: [JEAN], agent_events: [{ id: 1, sequence_id: "S1", kind: "campagne.fiche_liee" }] });
  const r = await rechercheFiche(b, { sequence: seq({ target_ref: "jean-dupont" }) });
  assert.equal(r.statut, "trouvee"); assert.equal(r.contact.id, 5);
});

test("un lien vers une fiche qui n'existe plus vaut supprimee", async () => {
  const b = fausseBase({ contacts: [] });
  const r = await rechercheFiche(b, { sequence: seq({ contact_id: 404 }) });
  assert.equal(r.statut, "supprimee");
});

test("egress : aucune lecture de contacts sans select cible", async () => {
  const b = avecCompte();
  await rechercheFiche(b, { sequence: seq({ target_ref: "jean-dupont" }), identite: { prenom: "Jean", nom: "Dupont", societe: "Orange" } });
  const lectures = b.lectures("contacts");
  assert.ok(lectures.length >= 2);
  for (const [, , params] of lectures) assert.ok(params.select && params.select !== "*", JSON.stringify(params));
});

test("lieSequence : pose contact_id et laisse la trace campagne.fiche_liee", async () => {
  const b = fausseBase({ agent_sequences: [{ id: "S1", contact_id: null }] });
  const s = seq();
  await lieSequence(b, s, { id: "M1" }, { id: 5 }, "profil LinkedIn");
  assert.equal(b.tables.agent_sequences[0].contact_id, 5);
  assert.equal(s.contact_id, 5);
  const [ev] = b.tables.agent_events;
  assert.equal(ev.kind, "campagne.fiche_liee"); assert.equal(ev.sequence_id, "S1"); assert.deepEqual(ev.data, { contact_id: 5, via: "profil LinkedIn" });
});

test("creation : Prospect en Contacte, responsable = proprietaire, compte lie, LinkedIn canonique", async () => {
  const b = fausseBase({});
  const liens = [];
  const deps = { ...b, getAgenceFor: async (n) => (n === "Nicolas Serradeil" ? "Lyon" : "?"),
    resolveCompteId: async (nom) => ({ id: "c1", nom }), syncContactCompte: async (cid, compteId) => { liens.push([cid, compteId]); } };
  const c = await creeFicheProspect(deps, {
    identite: { prenom: "jean", nom: "dupont", societe: "Crédit Agricole", linkedin_url: "https://fr.linkedin.com/in/Jean-Dupont?trk=x" },
    owner: "Nicolas Serradeil", campagne: "Prospection DSI Lyon",
    sequence: { target_kind: "externe", target_ref: "jean-dupont", next_due_at: "2026-10-13T08:00:00+00:00" },
    maintenant: new Date("2026-09-29T10:00:00+02:00"),
  });
  const row = b.tables.contacts[0];
  assert.equal(row.statut, "Prospect"); assert.equal(row.etape_prospect, "Contacté");
  assert.equal(row.nom, "DUPONT"); assert.equal(row.prenom, "Jean");
  assert.equal(row.responsable, "Nicolas Serradeil"); assert.equal(row.agence, "Lyon");
  assert.equal(row.linkedin, "https://www.linkedin.com/in/jean-dupont/");
  assert.equal(row.prochaine_action_date, "2026-10-13T08:00:00+00:00");
  assert.equal(row.prochaine_action_libelle, "Relance campagne (Jules)");
  assert.equal(row.commentaires, "Fiche créée par la campagne Prospection DSI Lyon");
  assert.equal(c.id, row.id);
  assert.deepEqual(liens, [[row.id, "c1"]]);
});

test("proprietaire de la campagne : profil du owner_id, sinon l'utilisateur du token, sinon erreur", async () => {
  const b = fausseBase({ profiles: [{ id: "u1", nom: "Nicolas Serradeil" }] });
  assert.equal(await proprietaireCampagne(b, { owner_id: "u1" }), "Nicolas Serradeil");
  assert.equal(await proprietaireCampagne({ ...b, getAuthCaller: async () => ({ nom: "Augustin Debouy" }) }, { owner_id: "u9" }), "Augustin Debouy");
  await assert.rejects(proprietaireCampagne({ ...b, getAuthCaller: async () => null }, { owner_id: "u9" }), /propriétaire/);
});

test("aucun tiret cadratin ni demi-cadratin dans le module", () => {
  const src = readFileSync(new URL("../server/campagne-crm.mjs", import.meta.url), "utf8");
  assert.doesNotMatch(src, /[\u2013\u2014]/);
});
```

- [ ] **Étape 3 : le lancer et le voir échouer**

Commande : `node --test /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/campagne-fiche.test.mjs`
Attendu : `Error [ERR_MODULE_NOT_FOUND]: Cannot find module '.../server/campagne-crm.mjs'`.

- [ ] **Étape 4 : écrire le module**

Créer `server/campagne-crm.mjs` avec exactement ce contenu (les tâches 6 et 8 le compléteront) :

```js
// Ecritures CRM des campagnes de prospection de Jules (SPEC_campagnes_prospection_etapes.md, repo
// web) : recherche de la fiche, lien, creation, puis application des effets decides en pur par
// campagne-rules.mjs. Toutes les dependances reseau sont injectees dans `deps` (sbGet, sbPost,
// sbPatch, resolveCompteId, syncContactCompte, getAgenceFor, getAuthCaller) : ce module se teste
// avec une fausse base, sans importer index.mjs (qui demarre le serveur).
import { slugLinkedin, normIdentite, normSociete, prochaineRelance } from "./campagne-rules.mjs";
import { donneesNouveauContact } from "./contact-norm.mjs";

// Colonnes lues sur une fiche : jamais de select * (egress Supabase).
export const COLS_CONTACT_CAMPAGNE = "id,prenom,nom,statut,responsable,etape_prospect,employeur,linkedin,prochaine_action_date";

// Societe de chaque fiche : compte primaire (contact_compte) pour un Prospect ou un Client, sinon
// employeur. Meme regle que societeByContact (index.mjs), en lectures ciblees.
export async function societesDe(deps, contacts) {
  const out = {};
  for (const c of contacts) out[c.id] = c.employeur || "";
  const ids = contacts.filter((c) => c.statut === "Prospect" || c.statut === "Client").map((c) => c.id);
  if (!ids.length) return out;
  const liens = await deps.sbGet("contact_compte", { contact_id: `in.(${ids.join(",")})`, is_primary: "eq.true", select: "contact_id,compte_id" });
  const cids = [...new Set(liens.map((l) => l.compte_id).filter((v) => v !== null && v !== undefined))];
  if (!cids.length) return out;
  const comptes = await deps.sbGet("comptes", { id: `in.(${cids.join(",")})`, select: "id,nom" });
  const nomDe = Object.fromEntries(comptes.map((c) => [c.id, c.nom]));
  for (const l of liens) if (nomDe[l.compte_id]) out[l.contact_id] = nomDe[l.compte_id];
  return out;
}

// Recherche de la fiche d'une personne de campagne, dans l'ordre du §3 de la spec. Rend
// { statut: 'liee'|'trouvee'|'homonyme'|'aucune'|'supprimee', contact, via, homonymes, identiteManquante }.
// - liee : lien explicite (decision de Nicolas), lien porte par la sequence, ou target_ref d'une
//   sequence contact_crm ;
// - trouvee : meme profil LinkedIn (slug normalise), sinon meme prenom + nom + societe ;
// - homonyme : meme prenom + nom, mais societe differente ou inconnue (question a Nicolas) ;
// - supprimee : la sequence a deja ete liee a une fiche qui n'existe plus (contact_id remis a null
//   par la base) : on ne recree jamais une fiche qu'un humain a supprimee.
export async function rechercheFiche(deps, { sequence, identite = {}, contactIdExplicite = null, nouvelleFiche = false }) {
  const { sbGet } = deps;
  const parId = async (id) => (await sbGet("contacts", { id: `eq.${id}`, select: COLS_CONTACT_CAMPAGNE, limit: "1" }))[0] || null;
  const refCrm = sequence.target_kind === "contact_crm" && /^\d+$/.test(String(sequence.target_ref ?? "")) ? Number(sequence.target_ref) : null;
  const idLie = contactIdExplicite ?? sequence.contact_id ?? refCrm;
  if (idLie !== null && idLie !== undefined) {
    const c = await parId(idLie);
    if (c) return { statut: "liee", contact: c, via: contactIdExplicite != null ? "lien explicite" : "lien de la séquence" };
    return { statut: "supprimee", contact: null };
  }
  const dejaLiee = async () => {
    if (!sequence.id) return false;
    const trace = await sbGet("agent_events", { sequence_id: `eq.${sequence.id}`, kind: "eq.campagne.fiche_liee", select: "id", limit: "1" });
    return trace.length > 0;
  };
  const slug = slugLinkedin(identite.linkedin_url) || (sequence.target_kind === "externe" ? slugLinkedin(sequence.target_ref) : null);
  if (slug) {
    const motifs = [...new Set([slug, encodeURIComponent(slug)])].map((m) => `linkedin.ilike.*${m}*`);
    const rows = await sbGet("contacts", { or: `(${motifs.join(",")})`, select: COLS_CONTACT_CAMPAGNE, limit: "20" });
    const hit = rows.find((c) => slugLinkedin(c.linkedin) === slug);
    if (hit) return { statut: "trouvee", contact: hit, via: "profil LinkedIn" };
  }
  if (!identite.prenom || !identite.nom) {
    if (await dejaLiee()) return { statut: "supprimee", contact: null };
    return { statut: "aucune", contact: null, identiteManquante: true };
  }
  const rows = await sbGet("contacts", { nom: `ilike.${String(identite.nom).trim()}`, select: COLS_CONTACT_CAMPAGNE, limit: "50" });
  const memes = rows.filter((c) => normIdentite(c.prenom) === normIdentite(identite.prenom) && normIdentite(c.nom) === normIdentite(identite.nom));
  if (memes.length) {
    const societes = await societesDe(deps, memes);
    const cible = normSociete(identite.societe);
    const meme = cible ? memes.find((c) => normSociete(societes[c.id]) === cible) : null;
    if (meme) return { statut: "trouvee", contact: meme, via: "prénom, nom et société" };
    if (!nouvelleFiche) {
      return { statut: "homonyme", contact: null,
        homonymes: memes.map((c) => ({ id: c.id, prenom: c.prenom, nom: c.nom, statut: c.statut, societe: societes[c.id] || "" })) };
    }
  }
  if (await dejaLiee()) return { statut: "supprimee", contact: null };
  return { statut: "aucune", contact: null };
}

// Pose le lien sequence -> fiche, et en garde la trace dans le journal : c'est elle qui empeche de
// recreer une fiche supprimee depuis (la base remet contact_id a null, la trace reste).
export async function lieSequence(deps, sequence, mission, contact, via) {
  await deps.sbPatch("agent_sequences", { id: sequence.id }, { contact_id: contact.id });
  sequence.contact_id = contact.id;
  try {
    await deps.sbPost("agent_events", { actor: "mcp", kind: "campagne.fiche_liee", sequence_id: sequence.id, mission_id: mission.id,
      message: `${sequence.target_label} : fiche ${contact.id} (${via})`, data: { contact_id: contact.id, via } });
  } catch (_) { /* la trace est un filet, jamais un echec du lien */ }
}

// Cree la fiche d'une personne de campagne a sa premiere vraie tentative de contact : Prospect en
// Contacte, responsable = proprietaire de la campagne, societe rattachee au compte comme le fait
// crm_create_contact, prochaine action = la relance de la sequence.
export async function creeFicheProspect(deps, { identite, owner, campagne, sequence, maintenant }) {
  const slug = slugLinkedin(identite.linkedin_url) || (sequence.target_kind === "externe" ? slugLinkedin(sequence.target_ref) : null);
  const agence = await deps.getAgenceFor(owner);
  const data = donneesNouveauContact({
    nom: identite.nom, prenom: identite.prenom, statut: "Prospect", responsable: owner, agence,
    groupe: identite.societe || "", linkedin: slug ? `https://www.linkedin.com/in/${slug}/` : null,
    commentaires: `Fiche créée par la campagne ${campagne}`,
  });
  Object.assign(data, { etape_prospect: "Contacté", ...prochaineRelance(sequence, maintenant) });
  const c = await deps.sbPost("contacts", data);
  if (c.id && identite.societe) {
    const { id: compteId } = await deps.resolveCompteId(identite.societe);
    if (compteId) await deps.syncContactCompte(c.id, compteId);
  }
  return { ...data, ...c };
}

// Proprietaire de la campagne (nom canonique de profiles), sinon l'utilisateur du token.
export async function proprietaireCampagne(deps, mission) {
  if (mission.owner_id) {
    const r = await deps.sbGet("profiles", { id: `eq.${mission.owner_id}`, select: "nom", limit: "1" });
    if (r[0] && r[0].nom) return r[0].nom;
  }
  const moi = deps.getAuthCaller ? await deps.getAuthCaller() : null;
  if (moi && moi.nom) return moi.nom;
  throw new Error("propriétaire de la campagne introuvable");
}
```

- [ ] **Étape 5 : relancer toute la suite MCP**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes && node --test tests/*.test.mjs`
Attendu : tout passe (21 tests dans `campagne-fiche.test.mjs`, dont `REVIEW FOCUS 2`, `3` et `5`).

- [ ] **Étape 6 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes add server/campagne-crm.mjs tests/fausse-base.mjs tests/campagne-fiche.test.mjs
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes commit -m "feat(mcp): campagnes, recherche lien et creation de la fiche prospect"
```

---

## Tâche 6 : application d'un événement à la fiche (`campagne-crm.mjs`, partie 2)

**Files :**
- Modify : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/server/campagne-crm.mjs` (ligne d'import, ajout à la fin)
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/campagne-appliquer.test.mjs`

**Interfaces :**
- Consumes : `server/campagne-rules.mjs` : `effetCampagneSurProspect`, `evenementSansEffet`, `libelleEvenement`, `typeHistorique`, `dateParis`, `fmtJour`, `fmtEcheance` ; `server/prospect-rules.mjs` : `valideChangementEtape(patch, contactActuel, appelant) -> { ok, erreur }`, `nettoyageChangementEtape(patch, contactActuel) -> patch` ; `server/campagne-crm.mjs` (tâche 5) : `rechercheFiche`, `lieSequence`, `creeFicheProspect` ; `tests/fausse-base.mjs` : `fausseBase`.
- Produces : `appliqueEffetsCampagne(deps, ctx) -> { lignes: string[], demandes: Array<{ genre: 'npc'|'perdu'|'homonyme', contact, go?, homonymes? }>, contact }` avec `ctx = { mission: { id, titre }, owner, sequence (état APRÈS écriture, avec id, contact_id, nb_relances, next_due_at, notes, target_*), evt (sortie de resoutEvenement), identite: { prenom, nom, societe, linkedin_url }, lien: { contact_id, nouvelle_fiche }, maintenant: Date }`. Lève une erreur si une écriture échoue. Consommé par la tâche 7 ; la tâche 8 lui fait déposer les `demandes`.

Contexte : §3 à §5 de la spec. Une ligne d'historique par événement, type selon le canal, détail « Campagne <nom> : <événement> » suivi de « · étape → X » si l'étape a bougé, responsable = propriétaire de la campagne. Tâche « Répondre à X » : id préfixé `tw_prospect_<contactId>_<horodatage>` (c'est ce qui fait redemander l'étape à la clôture dans l'app), statut `en_cours`, due au jour ouvré suivant 09:00, pas de doublon si une `tw_prospect_` est déjà ouverte (ni `fait` ni `annule`). Idempotence : décision 5 du plan.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/campagne-appliquer.test.mjs` :

```js
// Application d'un evenement de campagne a la fiche (SPEC §3 a §5), sur fausse base.
import { test } from "node:test";
import assert from "node:assert/strict";
import { fausseBase } from "./fausse-base.mjs";
import { appliqueEffetsCampagne } from "../server/campagne-crm.mjs";

const MISSION = { id: "M1", titre: "Prospection DSI Lyon", kind: "campagne", config: { preset: "prospection" }, owner_id: "u1" };
const NOW = new Date("2026-09-29T10:00:00+02:00");
const ID = { prenom: "Jean", nom: "Dupont", societe: "Crédit Agricole", linkedin_url: "https://www.linkedin.com/in/jean-dupont/" };
const JEAN = (etape, extra = {}) => ({ id: 7, prenom: "Jean", nom: "DUPONT", statut: "Prospect", responsable: "Nicolas Serradeil",
  etape_prospect: etape, employeur: null, linkedin: "https://www.linkedin.com/in/jean-dupont/", motif_perte: null, ...extra });
const seq = (extra = {}) => ({ id: "S1", mission_id: "M1", target_kind: "externe", target_ref: "jean-dupont", target_label: "Jean Dupont",
  etape: 2, statut: "active", nb_relances: 0, next_due_at: "2026-10-13T08:00:00+00:00", notes: null, contact_id: null, ...extra });
function monde(init = {}) {
  const s = init.sequence || seq();
  const b = fausseBase({ profiles: [{ id: "u1", nom: "Nicolas Serradeil" }], agent_sequences: [s], ...init.tables });
  const deps = { ...b, getAgenceFor: async () => "Lyon", resolveCompteId: async (nom) => ({ id: "c1", nom }),
    syncContactCompte: async () => {}, getAuthCaller: async () => null };
  return { b, deps, s };
}
const ctx = (s, evt, extra = {}) => ({ mission: MISSION, owner: "Nicolas Serradeil", sequence: s,
  evt: { canal: "linkedin", rdv_date: null, motif: null, sentiment: null, ...evt }, identite: ID, lien: {}, maintenant: NOW, ...extra });

test("invitation acceptee sans fiche : creation en Contacte, lien, une ligne d'historique", async () => {
  const { b, deps, s } = monde();
  const r = await appliqueEffetsCampagne(deps, ctx(s, { type: "acceptee" }));
  assert.equal(b.tables.contacts.length, 1);
  const c = b.tables.contacts[0];
  assert.equal(c.etape_prospect, "Contacté");
  assert.equal(b.tables.agent_sequences[0].contact_id, c.id);
  assert.equal(b.tables.historique_actions.length, 1);
  assert.deepEqual({ ...b.tables.historique_actions[0], id: undefined }, { id: undefined, id_prospect: c.id, date: "2026-09-29",
    type_action: "LinkedIn", details: "Campagne Prospection DSI Lyon : invitation acceptée · étape → Contacté", responsable: "Nicolas Serradeil" });
  assert.ok(r.lignes.some((l) => /^fiche créée \(ID \d+\) en Contacté/.test(l)), r.lignes.join(" | "));
});

test("REVIEW FOCUS 1 : le meme evenement rejoue ne cree ni seconde fiche, ni seconde ligne, ni seconde tache", async () => {
  const { b, deps, s } = monde();
  await appliqueEffetsCampagne(deps, ctx(s, { type: "acceptee" }));
  const r2 = await appliqueEffetsCampagne(deps, ctx(s, { type: "acceptee" }));
  assert.equal(b.tables.contacts.length, 1);
  assert.equal(b.tables.historique_actions.length, 1);
  assert.ok(r2.lignes.some((l) => /déjà tracé/.test(l)), r2.lignes.join(" | "));
  await appliqueEffetsCampagne(deps, ctx(s, { type: "reponse", sentiment: "positif" }));
  await appliqueEffetsCampagne(deps, ctx(s, { type: "reponse", sentiment: "positif" }));
  assert.equal(b.tables.taches.length, 1);
  assert.equal(b.tables.historique_actions.length, 2);
});

test("reponse positive sur un Contacte lie : En discussion, tache Repondre a X le jour ouvre suivant 09h00", async () => {
  const { b, deps, s } = monde({ sequence: seq({ contact_id: 7, etape: 6, statut: "replied", sentiment: "positif" }), tables: { contacts: [JEAN("Contacté")] } });
  await appliqueEffetsCampagne(deps, ctx(s, { type: "reponse", sentiment: "positif" }));
  const c = b.tables.contacts[0];
  assert.equal(c.etape_prospect, "En discussion");
  assert.equal(c.prochaine_action_date, "2026-09-30T09:00:00+02:00");
  assert.equal(c.motif_perte, null);
  const [t] = b.tables.taches;
  assert.match(t.id, /^tw_prospect_7_\d+$/);
  assert.equal(t.titre, "Répondre à Jean DUPONT"); assert.equal(t.due_date, "2026-09-30T09:00:00+02:00");
  assert.equal(t.statut, "en_cours"); assert.equal(t.responsable, "Nicolas Serradeil"); assert.equal(t.contact_id, 7);
  assert.equal(b.tables.historique_actions[0].details, "Campagne Prospection DSI Lyon : réponse positive · étape → En discussion");
});

test("pas de seconde tache si une tache de prospection est deja ouverte", async () => {
  const { b, deps, s } = monde({ sequence: seq({ contact_id: 7 }), tables: { contacts: [JEAN("Contacté")],
    taches: [{ id: "tw_prospect_7_1", contact_id: 7, statut: "en_cours" }] } });
  const r = await appliqueEffetsCampagne(deps, ctx(s, { type: "reponse", sentiment: "positif" }));
  assert.equal(b.tables.taches.length, 1);
  assert.ok(r.lignes.some((l) => /déjà ouverte/.test(l)));
});

test("un Client qui repond positivement : statut et etape intouches, historique et tache a son responsable", async () => {
  const client = { id: 8, prenom: "Marie", nom: "MARTIN", statut: "Client", responsable: "Camille Salinson", etape_prospect: null, employeur: null, linkedin: null };
  const { b, deps, s } = monde({ sequence: seq({ contact_id: 8 }), tables: { contacts: [client] } });
  await appliqueEffetsCampagne(deps, ctx(s, { type: "reponse", sentiment: "positif" }));
  assert.equal(b.tables.contacts[0].etape_prospect, null);
  assert.equal(b.tables.contacts[0].statut, "Client");
  assert.equal(b.tables.historique_actions[0].details, "Campagne Prospection DSI Lyon : réponse positive");
  assert.equal(b.tables.taches[0].responsable, "Camille Salinson");
});

test("REVIEW FOCUS 2 : la fiche liee a ete supprimee, rien n'est recree", async () => {
  const { b, deps, s } = monde({ tables: { contacts: [], agent_events: [{ id: 1, sequence_id: "S1", kind: "campagne.fiche_liee" }] } });
  const r = await appliqueEffetsCampagne(deps, ctx(s, { type: "reponse", sentiment: "positif" }));
  assert.equal((b.tables.contacts || []).length, 0);
  assert.equal((b.tables.historique_actions || []).length, 0);
  assert.ok(r.lignes.some((l) => /supprimée/.test(l)));
});

test("REVIEW FOCUS 5 : identite manquante au moment de creer, rien n'est cree et on le dit", async () => {
  const { b, deps, s } = monde({ sequence: seq({ target_ref: "inconnu" }) });
  const r = await appliqueEffetsCampagne(deps, ctx(s, { type: "acceptee" }, { identite: {} }));
  assert.equal((b.tables.contacts || []).length, 0);
  assert.equal(b.tables.agent_sequences[0].contact_id, null);
  assert.ok(r.lignes.some((l) => /identité manquante/.test(l)));
});

test("refus : En veille, reveil a 6 mois 09h00 avec decalage", async () => {
  const { b, deps, s } = monde({ sequence: seq({ contact_id: 7 }), tables: { contacts: [JEAN("En discussion")] } });
  await appliqueEffetsCampagne(deps, ctx(s, { type: "sortie", motif: "refus" }));
  assert.equal(b.tables.contacts[0].etape_prospect, "En veille");
  assert.equal(b.tables.contacts[0].prochaine_action_date, "2027-03-29T09:00:00+02:00");
  assert.equal(b.tables.historique_actions[0].details, "Campagne Prospection DSI Lyon : refus · étape → En veille");
});

test("ne me contactez plus : l'etape ne bouge pas, l'historique est ecrit, un GO est demande", async () => {
  const { b, deps, s } = monde({ sequence: seq({ contact_id: 7 }), tables: { contacts: [JEAN("Contacté")] } });
  const r = await appliqueEffetsCampagne(deps, ctx(s, { type: "sortie", motif: "npc" }));
  assert.equal(b.tables.contacts[0].etape_prospect, "Contacté");
  assert.equal(b.tables.historique_actions[0].details, "Campagne Prospection DSI Lyon : ne me contactez plus");
  assert.equal(r.demandes.length, 1);
  assert.equal(r.demandes[0].genre, "npc");
  assert.ok(r.lignes.some((l) => /GO de Nicolas requis/.test(l)));
});

test("homonyme : rien cree ni lie, la question est rendue", async () => {
  const autre = { id: 9, prenom: "Jean", nom: "DUPONT", statut: "Prospect", responsable: "Camille Salinson", etape_prospect: "Contacté", employeur: null, linkedin: null };
  const { b, deps, s } = monde({ sequence: seq({ target_ref: "jean-dupont-autre" }), tables: { contacts: [autre],
    contact_compte: [{ contact_id: 9, compte_id: "c9", is_primary: true }], comptes: [{ id: "c9", nom: "Orange" }] } });
  const r = await appliqueEffetsCampagne(deps, ctx(s, { type: "acceptee" }, { identite: { ...ID, linkedin_url: null } }));
  assert.equal(b.tables.contacts.length, 1);
  assert.equal(b.tables.agent_sequences[0].contact_id, null);
  assert.equal((b.tables.historique_actions || []).length, 0);
  assert.equal(r.demandes[0].genre, "homonyme");
  assert.ok(r.lignes.some((l) => /homonyme/.test(l)));
});

test("fiche en Ne pas recontacter : aucune ecriture sur la fiche, la sequence est arretee", async () => {
  const { b, deps, s } = monde({ sequence: seq({ contact_id: 7 }), tables: { contacts: [JEAN("Ne pas recontacter")] } });
  const r = await appliqueEffetsCampagne(deps, ctx(s, { type: "message_envoye" }));
  assert.equal(b.tables.agent_sequences[0].statut, "stopped");
  assert.equal(b.tables.agent_sequences[0].next_due_at, null);
  assert.equal((b.tables.historique_actions || []).length, 0);
  assert.equal(b.ecritures("contacts").length, 0);
  assert.ok(r.lignes.some((l) => /séquence arrêtée/.test(l)));
});

test("invitation envoyee : aucune lecture ni ecriture CRM", async () => {
  const { b, deps, s } = monde();
  const r = await appliqueEffetsCampagne(deps, ctx(s, { type: "invite_envoyee" }));
  assert.equal(b.journal.length, 0);
  assert.deepEqual(r.lignes, []);
});

test("aucune ligne de reponse avec un tiret cadratin", async () => {
  const { deps, s } = monde();
  const r = await appliqueEffetsCampagne(deps, ctx(s, { type: "reponse", sentiment: "positif" }));
  for (const l of r.lignes) assert.doesNotMatch(l, /[\u2013\u2014]/, l);
});
```

- [ ] **Étape 2 : le lancer et le voir échouer**

Commande : `node --test /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/campagne-appliquer.test.mjs`
Attendu : `SyntaxError: The requested module '../server/campagne-crm.mjs' does not provide an export named 'appliqueEffetsCampagne'`.

- [ ] **Étape 3 : implémenter**

3a. Dans `server/campagne-crm.mjs`, remplacer la ligne d'import :

```js
import { slugLinkedin, normIdentite, normSociete, prochaineRelance } from "./campagne-rules.mjs";
```

par :

```js
import { slugLinkedin, normIdentite, normSociete, prochaineRelance, effetCampagneSurProspect, evenementSansEffet,
  libelleEvenement, typeHistorique, dateParis, fmtJour, fmtEcheance } from "./campagne-rules.mjs";
import { valideChangementEtape, nettoyageChangementEtape } from "./prospect-rules.mjs";
```

3b. Ajouter à la FIN du fichier :

```js
// Applique un evenement de campagne a la fiche. Ordre : fiche (lien ou creation), garde « Ne pas
// recontacter », temoin d'idempotence (la ligne d'historique de cet evenement existe deja : rien
// n'est reecrit), puis etape, historique, tache. Les demandes de GO sont RENDUES dans `demandes`,
// jamais deposees ici. Rend { lignes, demandes, contact } ; une ecriture en echec LEVE une erreur
// (c'est l'appelant qui garantit que la sequence reste ecrite).
async function ecritEffets(deps, ctx) {
  const { sbGet, sbPost, sbPatch } = deps;
  const { mission, owner, sequence, evt } = ctx;
  const identite = ctx.identite || {};
  const lien = ctx.lien || {};
  const maintenant = ctx.maintenant || new Date();
  const campagne = mission.titre || "";
  const regles = { maintenant, campagne };
  const lignes = [], demandes = [];
  if (evenementSansEffet(evt)) return { lignes, demandes, contact: null };

  const r = await rechercheFiche(deps, { sequence, identite, contactIdExplicite: lien.contact_id ?? null, nouvelleFiche: !!lien.nouvelle_fiche });
  if (r.statut === "supprimee") {
    lignes.push("la fiche liée a été supprimée du CRM : rien recréé, rien écrit");
    return { lignes, demandes, contact: null };
  }
  if (r.statut === "homonyme") {
    if (effetCampagneSurProspect(evt, null, sequence, regles).creer) {
      demandes.push({ genre: "homonyme", homonymes: r.homonymes, contact: null });
      lignes.push(`homonyme au CRM dans une autre société (fiche ${r.homonymes.map((h) => h.id).join(", ")}) : rien créé ni lié, question à Nicolas`);
    }
    return { lignes, demandes, contact: null };
  }
  let contact = r.contact;
  let etapeAvant = contact ? contact.etape_prospect : null;
  let creee = false;
  if (contact && (sequence.contact_id === null || sequence.contact_id === undefined)) {
    await lieSequence(deps, sequence, mission, contact, r.via);
    lignes.push(`fiche liée (ID ${contact.id}, ${r.via})`);
  }
  let plan = effetCampagneSurProspect(evt, contact, sequence, regles);
  if (plan.creer) {
    if (!identite.prenom || !identite.nom) {
      lignes.push("identité manquante (prenom et nom) : fiche non créée. Repasser l'appel avec prenom, nom, societe et linkedin_url.");
      return { lignes, demandes, contact: null };
    }
    contact = await creeFicheProspect(deps, { identite, owner, campagne, sequence, maintenant });
    creee = true;
    etapeAvant = null;
    await lieSequence(deps, sequence, mission, contact, "fiche créée");
    lignes.push(`fiche créée (ID ${contact.id}) en Contacté, liée à la séquence`);
    plan = effetCampagneSurProspect(evt, contact, sequence, regles);
  }
  if (plan.arreterSequence) {
    const note = [sequence.notes, `[${fmtJour(dateParis(maintenant))}] Arrêt automatique : fiche CRM en « Ne pas recontacter »`].filter(Boolean).join("\n");
    await sbPatch("agent_sequences", { id: sequence.id }, { statut: "stopped", next_due_at: null, notes: note });
    lignes.push(`${plan.raison} : séquence arrêtée`);
    return { lignes, demandes, contact };
  }
  if (!plan.historique && !plan.patch && !plan.tache && !plan.go) {
    if (plan.raison) lignes.push(plan.raison);
    return { lignes, demandes, contact };
  }
  const prefixe = `Campagne ${campagne} : ${libelleEvenement(evt, { nbRelances: sequence.nb_relances, maintenant })}`;
  const deja = await sbGet("historique_actions", { id_prospect: `eq.${contact.id}`, details: `like.${prefixe}*`, select: "id", limit: "1" });
  if (deja.length) {
    lignes.push("événement déjà tracé sur la fiche : rien réécrit");
    return { lignes, demandes, contact };
  }
  let etapeEcrite = creee ? "Contacté" : null;
  if (plan.patch) {
    const patch = { ...plan.patch, updated_at: maintenant.toISOString() };
    if ("etape_prospect" in patch) {
      const verdict = valideChangementEtape(patch, contact, { nom: null, role: null });
      if (!verdict.ok) throw new Error(verdict.erreur);
      Object.assign(patch, nettoyageChangementEtape(patch, contact));
    }
    await sbPatch("contacts", { id: contact.id }, patch);
    if (patch.etape_prospect && patch.etape_prospect !== etapeAvant) etapeEcrite = patch.etape_prospect;
  }
  const details = prefixe + (etapeEcrite ? ` · étape → ${etapeEcrite}` : "");
  await sbPost("historique_actions", { id_prospect: contact.id, date: dateParis(maintenant), type_action: typeHistorique(evt), details, responsable: owner });
  lignes.push(`historique : « ${details} »`);
  if (etapeEcrite && !creee) lignes.push(`étape ${etapeAvant || "À contacter"} → ${etapeEcrite}`);
  if (plan.tache) {
    const ouvertes = await sbGet("taches", { contact_id: `eq.${contact.id}`, id: "like.tw_prospect_*", statut: "not.in.(fait,annule)", select: "id", limit: "1" });
    if (ouvertes.length) {
      lignes.push(`tâche non créée : une tâche de prospection est déjà ouverte sur la fiche (${ouvertes[0].id})`);
    } else {
      const resp = contact.responsable || owner;
      await sbPost("taches", { id: `tw_prospect_${contact.id}_${maintenant.getTime()}`, titre: plan.tache.titre, statut: "en_cours",
        due_date: plan.tache.due, contact_id: contact.id, besoin_id: null, mission_id: null, notes: `Campagne ${campagne}`, responsable: resp });
      lignes.push(`tâche « ${plan.tache.titre} » créée pour ${resp}, échéance ${fmtEcheance(plan.tache.due)}`);
    }
  }
  if (plan.go) {
    demandes.push({ genre: plan.go.etape === "Ne pas recontacter" ? "npc" : "perdu", contact, go: plan.go });
    lignes.push(`GO de Nicolas requis pour « ${plan.go.etape} » : l'étape ne bouge pas avant`);
  }
  return { lignes, demandes, contact };
}

// Point d'entree unique, appele par agent_sequence_upsert pour une campagne de prospection.
// ctx = { mission, owner, sequence (etat APRES ecriture, avec id), evt (resoutEvenement), identite,
//         lien: { contact_id, nouvelle_fiche }, maintenant }.
export async function appliqueEffetsCampagne(deps, ctx) {
  const r = await ecritEffets(deps, ctx);
  return r;
}
```

- [ ] **Étape 4 : relancer toute la suite MCP**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes && node --test tests/*.test.mjs`
Attendu : tout passe (13 tests dans `campagne-appliquer.test.mjs`, dont `REVIEW FOCUS 1`, `2` et `5` ; le test « aucun tiret cadratin » de `campagne-fiche.test.mjs` passe toujours).

- [ ] **Étape 5 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes add server/campagne-crm.mjs tests/campagne-appliquer.test.mjs
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes commit -m "feat(mcp): campagnes, application d'un evenement a la fiche (etape, historique, tache, idempotence)"
```

---

## Tâche 7 : branchement dans `agent_sequence_upsert`

**Files :**
- Modify : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/server/agent-tools.mjs` (imports, signature de `registerAgentTools`, bloc `agent_sequence_upsert`)
- Modify : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/server/index.mjs` (appel de `registerAgentTools` dans `main()`)
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/agent-sequence-campagne.test.mjs`

**Interfaces :**
- Consumes : `server/campagne-rules.mjs` : `estCampagneProspection`, `resoutEvenement`, `CAMPAGNE_EVENEMENTS`, `CAMPAGNE_MOTIFS_SORTIE`, `CAMPAGNE_CANAUX` ; `server/campagne-crm.mjs` : `rechercheFiche`, `appliqueEffetsCampagne`, `proprietaireCampagne` ; dans `index.mjs` : `resolveCompteId(nom)`, `syncContactCompte(contactId, compteId)`, `getAgenceFor(nom)`, `getAuthCaller()` (fonctions de module existantes) ; `tests/fausse-base.mjs`.
- Produces :
  - `registerAgentTools(server, { sbGet, sbPost, sbPatch, sbDelete, sbRpc, handleError, z, crm = null })`, `crm = { resolveCompteId, syncContactCompte, getAgenceFor, getAuthCaller }` ;
  - `agent_sequence_upsert` accepte en plus, facultatifs : `evenement` (enum `CAMPAGNE_EVENEMENTS`), `motif_sortie` (enum `CAMPAGNE_MOTIFS_SORTIE`), `rdv_date` (string), `canal` (enum `CAMPAGNE_CANAUX`), `prenom`, `nom`, `societe`, `linkedin_url` (strings), `contact_id` (number), `nouvelle_fiche` (boolean). Aucun n'est écrit dans `agent_sequences`. La réponse se termine, pour une campagne de prospection, par des lignes `CRM : ...` ou une ligne `⚠️ CRM non mis à jour (...). La séquence, elle, est bien écrite.` ; un ajout refusé commence par `🚫`.
  Consommé par la tâche 8 (instructions de GO qui rappellent l'outil) et la tâche 12 (consigne Jules).

Contexte : §6.3 de la spec. L'écriture de la séquence reste exactement celle d'aujourd'hui (recherche par `id` ou par clé, alerte de doublon, événements `sequence.*`) ; les tests existants de `tests/agent-tools.test.mjs` doivent passer sans modification. On lit l'état AVANT (colonnes ciblées, sans `contact_id`, cf. décision 19), on écrit, puis le volet CRM s'exécute SEULEMENT si la mission est une campagne au preset prospection et la cible une personne (`externe` ou `contact_crm`). Le refus d'ajout d'une fiche en NPC ne vaut qu'à la création d'une séquence (pas de ligne existante). La description de l'outil garde son début existant (y compris son tiret d'origine, on ne réécrit pas l'existant) ; seule la partie ajoutée, qui commence à « Campagne de prospection », est soumise à la règle sans tiret.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/agent-sequence-campagne.test.mjs` :

```js
// agent_sequence_upsert, point de passage unique : une campagne de prospection tient le pipeline
// Prospect a jour (SPEC_campagnes_prospection_etapes.md §6.3). Fausse base, aucun reseau.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { registerAgentTools } from "../server/agent-tools.mjs";
import { fausseBase } from "./fausse-base.mjs";

const z = await import("../server/node_modules/zod/index.js").then((m) => m.z);
const M = "11111111-1111-4111-8111-111111111111";
const S = "22222222-2222-4222-8222-222222222222";
const mission = (config) => ({ id: M, titre: "Prospection DSI Lyon", kind: "campagne", config, owner_id: "u1", statut: "active" });
const JEAN = (etape) => ({ id: 7, prenom: "Jean", nom: "DUPONT", statut: "Prospect", responsable: "Nicolas Serradeil", etape_prospect: etape,
  employeur: null, linkedin: "https://www.linkedin.com/in/jean-dupont", motif_perte: null });
const SEQ = (extra = {}) => ({ id: S, mission_id: M, target_kind: "externe", target_ref: "jean-dupont", target_label: "Jean Dupont",
  etape: 3, statut: "active", nb_relances: 0, sentiment: null, next_due_at: "2026-10-13T08:00:00+00:00", notes: null, contact_id: 7, ...extra });
const IDENTITE = { prenom: "Jean", nom: "Dupont", societe: "Crédit Agricole", linkedin_url: "https://www.linkedin.com/in/jean-dupont/" };

function outil(init = {}, { crm = true, panne = null } = {}) {
  const b = fausseBase({ profiles: [{ id: "u1", nom: "Nicolas Serradeil" }], agent_task_types: [], ...init });
  const tools = new Map();
  const server = { tool: (name, _d, _s, h) => tools.set(name, h) };
  const deps = {
    resolveCompteId: async (nom) => ({ id: "c1", nom }), syncContactCompte: async () => {},
    getAgenceFor: async () => { if (panne) throw new Error(panne); return "Lyon"; },
    getAuthCaller: async () => ({ nom: "Nicolas Serradeil", role: "admin" }),
  };
  registerAgentTools(server, { ...b, handleError: (e) => `ERR: ${e.message}`, z, crm: crm ? deps : null });
  return { b, up: tools.get("agent_sequence_upsert") };
}
const texte = (res) => res.content[0].text;
const nouvelle = (extra = {}) => ({ mission_id: M, target_kind: "externe", target_ref: "https://www.linkedin.com/in/jean-dupont/",
  target_label: "Jean Dupont", etape: 2, statut: "active", accepted_at: "2026-09-29T08:00:00Z", next_due_at: "2026-09-29T08:00:00Z", ...IDENTITE, ...extra });

test("invitation acceptee deduite : fiche creee en Contacte, liee, historisee ; l'identite n'entre pas dans la sequence", async () => {
  const { b, up } = outil({ agent_missions: [mission({ preset: "prospection" })] });
  const res = await up(nouvelle());
  const [seq] = b.tables.agent_sequences;
  const [c] = b.tables.contacts;
  assert.equal(c.etape_prospect, "Contacté"); assert.equal(c.nom, "DUPONT"); assert.equal(c.statut, "Prospect");
  assert.equal(c.responsable, "Nicolas Serradeil");
  assert.match(c.prochaine_action_date, /^\d{4}-\d{2}-\d{2}T09:00:00\+0[12]:00$/, "relance passee : jour ouvre suivant 09h00");
  assert.equal(seq.contact_id, c.id);
  for (const k of ["prenom", "nom", "societe", "linkedin_url", "evenement"]) assert.equal(k in seq, false, `${k} ne doit pas etre ecrit dans la sequence`);
  assert.equal(b.tables.historique_actions[0].details, "Campagne Prospection DSI Lyon : invitation acceptée · étape → Contacté");
  assert.match(texte(res), /CRM : fiche créée \(ID \d+\) en Contacté/);
});

test("campagne sans preset ou en recrutement : aucune lecture ni ecriture CRM", async () => {
  for (const config of [{}, { preset: "recrutement" }]) {
    const { b, up } = outil({ agent_missions: [mission(config)] });
    const res = await up(nouvelle());
    assert.equal(b.lectures("contacts").length, 0, JSON.stringify(config));
    assert.equal((b.tables.contacts || []).length, 0);
    assert.doesNotMatch(texte(res), /CRM/);
  }
});

test("le CRM ne bloque jamais la sequence : echec d'ecriture CRM = sequence ecrite et echec signale", async () => {
  const { b, up } = outil({ agent_missions: [mission({ preset: "prospection" })] }, { panne: "panne réseau" });
  const res = await up(nouvelle());
  assert.equal(b.tables.agent_sequences.length, 1);
  assert.match(texte(res), /⚠️ CRM non mis à jour \(panne réseau\)\. La séquence, elle, est bien écrite\./);
});

test("une personne en Ne pas recontacter n'est jamais ajoutee a une campagne de prospection", async () => {
  const { b, up } = outil({ agent_missions: [mission({ preset: "prospection" })], contacts: [JEAN("Ne pas recontacter")] });
  const res = await up({ mission_id: M, target_kind: "externe", target_ref: "jean-dupont", target_label: "Jean Dupont", etape: 0, statut: "active" });
  assert.equal((b.tables.agent_sequences || []).length, 0);
  assert.match(texte(res), /🚫 Jean Dupont n'est PAS ajouté\(e\)/);
});

test("REVIEW FOCUS 4 : un humain passe la fiche en Ne pas recontacter en cours de campagne, la sequence s'arrete, la fiche ne bouge pas", async () => {
  const { b, up } = outil({ agent_missions: [mission({ preset: "prospection" })], agent_sequences: [SEQ()], contacts: [JEAN("Ne pas recontacter")] });
  const res = await up({ id: S, mission_id: M, target_kind: "externe", target_ref: "jean-dupont", target_label: "Jean Dupont",
                         etape: 4, nb_relances: 1, next_due_at: "2026-10-20T08:00:00Z" });
  assert.equal(b.tables.agent_sequences[0].statut, "stopped");
  assert.equal(b.tables.agent_sequences[0].next_due_at, null);
  assert.equal(b.tables.contacts[0].etape_prospect, "Ne pas recontacter");
  assert.equal((b.tables.historique_actions || []).length, 0);
  assert.match(texte(res), /séquence arrêtée/);
});

test("reponse positive deduite (etape 6, sentiment positif) : En discussion et tache Repondre a X", async () => {
  const { b, up } = outil({ agent_missions: [mission({ preset: "prospection" })], agent_sequences: [SEQ()], contacts: [JEAN("Contacté")] });
  await up({ id: S, mission_id: M, target_kind: "externe", target_ref: "jean-dupont", target_label: "Jean Dupont",
             etape: 6, statut: "replied", replied_at: "2026-09-29T09:00:00Z", sentiment: "positif", next_due_at: null });
  assert.equal(b.tables.contacts[0].etape_prospect, "En discussion");
  const [t] = b.tables.taches;
  assert.equal(t.titre, "Répondre à Jean DUPONT");
  assert.match(t.id, /^tw_prospect_7_\d+$/);
  assert.match(t.due_date, /^\d{4}-\d{2}-\d{2}T09:00:00\+0[12]:00$/);
});

test("evenement explicite : sortie pour refus, En veille a 6 mois", async () => {
  const { b, up } = outil({ agent_missions: [mission({ preset: "prospection" })], agent_sequences: [SEQ()], contacts: [JEAN("Contacté")] });
  const res = await up({ id: S, mission_id: M, target_kind: "externe", target_ref: "jean-dupont", target_label: "Jean Dupont",
                         statut: "stopped", evenement: "sortie", motif_sortie: "refus" });
  assert.equal(b.tables.contacts[0].etape_prospect, "En veille");
  assert.match(b.tables.contacts[0].prochaine_action_date, /T09:00:00\+0[12]:00$/);
  const crm = texte(res).slice(texte(res).indexOf("\nCRM"));
  assert.doesNotMatch(crm, /[\u2013\u2014]/, "les lignes CRM de la reponse sont sans tiret cadratin");
});

test("sans dependances CRM (ancien serveur), une campagne de prospection ecrit la sequence et le signale", async () => {
  const { b, up } = outil({ agent_missions: [mission({ preset: "prospection" })] }, { crm: false });
  const res = await up(nouvelle());
  assert.equal(b.tables.agent_sequences.length, 1);
  assert.match(texte(res), /⚠️ CRM non mis à jour \(dépendances CRM absentes du serveur\)/);
});

test("index.mjs passe les dependances CRM a registerAgentTools", () => {
  const src = readFileSync(new URL("../server/index.mjs", import.meta.url), "utf8");
  assert.match(src, /registerAgentTools\(server, \{ sbGet, sbPost, sbPatch, sbDelete, sbRpc, handleError, z, crm: \{ resolveCompteId, syncContactCompte, getAgenceFor, getAuthCaller \} \}\);/);
});
```

- [ ] **Étape 2 : le lancer et le voir échouer**

Commande : `node --test /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/agent-sequence-campagne.test.mjs`
Attendu : plusieurs échecs (aucune fiche n'est créée, donc `b.tables.contacts` vaut `undefined` et la déstructuration lève un `TypeError` ; réponse sans `CRM :` ; séquence créée malgré la fiche en NPC ; `registerAgentTools(server, { ..., crm: ... })` absent de `index.mjs`).

- [ ] **Étape 3 : imports et signature**

3a. Dans `server/agent-tools.mjs`, juste après la ligne `import { findSimilar } from "./agent-similar.mjs";`, ajouter :

```js
import { estCampagneProspection, resoutEvenement, CAMPAGNE_EVENEMENTS, CAMPAGNE_MOTIFS_SORTIE, CAMPAGNE_CANAUX } from "./campagne-rules.mjs";
import { rechercheFiche, appliqueEffetsCampagne, proprietaireCampagne } from "./campagne-crm.mjs";
```

3b. Remplacer la ligne :

```js
export function registerAgentTools(server, { sbGet, sbPost, sbPatch, sbDelete, sbRpc, handleError, z }) {
```

par :

```js
export function registerAgentTools(server, { sbGet, sbPost, sbPatch, sbDelete, sbRpc, handleError, z, crm = null }) {
```

- [ ] **Étape 4 : remplacer le bloc `agent_sequence_upsert`**

Dans `server/agent-tools.mjs`, remplacer TOUT le bloc qui va de la ligne `  // ═══ agent_sequence_* ═══` jusqu'à la fin de l'appel `server.tool("agent_sequence_upsert", ...)` (la ligne `  }));` qui précède `  server.tool("agent_sequence_list", ...`), bornes comprises pour le commentaire, par :

```js
  // ═══ agent_sequence_* ═══
  // Paramètres du volet CRM des campagnes de prospection : ce ne sont PAS des colonnes de
  // agent_sequences, ils ne partent jamais dans l'écriture de la séquence.
  const PARAMS_CRM = ["evenement", "motif_sortie", "rdv_date", "canal", "prenom", "nom", "societe", "linkedin_url", "contact_id", "nouvelle_fiche"];
  // État AVANT écriture, pour déduire l'événement. contact_id n'y figure pas : une base sans la
  // migration 54 ne doit jamais faire échouer l'écriture d'une séquence.
  const COLS_AVANT = "id,mission_id,target_label,target_kind,target_ref,etape,statut,sentiment,nb_relances,next_due_at,notes";
  const depsCrm = () => ({ sbGet, sbPost, sbPatch, ...(crm || {}) });
  const estPersonne = (kind) => kind === "externe" || kind === "contact_crm";
  const identiteDe = (c) => ({ prenom: c.prenom, nom: c.nom, societe: c.societe, linkedin_url: c.linkedin_url });
  async function lireMission(missionId) {
    try {
      const r = await sbGet("agent_missions", { id: `eq.${missionId}`, select: "id,titre,kind,config,owner_id", limit: "1" });
      return { mission: r[0] || null, erreur: null };
    } catch (e) { return { mission: null, erreur: e.message }; }
  }
  // « Ne pas recontacter » l'emporte sur tout : une personne dont la fiche y est n'entre jamais dans
  // une campagne de prospection. Lecture CRM en échec : l'ajout n'est pas bloqué.
  async function refusNpc(p, crmParams) {
    if (!crm) return "";
    try {
      const r = await rechercheFiche(depsCrm(), {
        sequence: { target_kind: p.target_kind, target_ref: p.target_ref },
        identite: identiteDe(crmParams), contactIdExplicite: crmParams.contact_id ?? null,
      });
      if (r.contact && r.contact.etape_prospect === "Ne pas recontacter") {
        return `🚫 ${p.target_label} n'est PAS ajouté(e) à la campagne : sa fiche CRM (ID ${r.contact.id}) est en « Ne pas recontacter ». Une campagne de prospection ne contacte jamais cette personne. Rien n'a été écrit.`;
      }
    } catch (e) { /* lecture CRM en échec : l'ajout n'est pas bloqué */ }
    return "";
  }
  // Volet CRM, APRÈS l'écriture de la séquence. Ne lève jamais : un échec devient une ligne ⚠️.
  async function voletCrm({ mission, erreurMission, avant, apres, crmParams, p }) {
    if (!estPersonne(apres.target_kind)) return "";
    if (!mission) {
      return erreurMission && Object.keys(crmParams).length
        ? `\n⚠️ CRM : campagne illisible (${erreurMission}), aucun effet CRM. La séquence, elle, est bien écrite.` : "";
    }
    if (!estCampagneProspection(mission)) return "";
    try {
      const evt = resoutEvenement({ ...crmParams, sentiment: p.sentiment }, avant, apres);
      if (!evt) return "";
      if (!crm) throw new Error("dépendances CRM absentes du serveur");
      const deps = depsCrm();
      const owner = await proprietaireCampagne(deps, mission);
      const r = await appliqueEffetsCampagne(deps, {
        mission, owner, sequence: apres, evt, maintenant: new Date(), identite: identiteDe(crmParams),
        lien: { contact_id: crmParams.contact_id ?? null, nouvelle_fiche: !!crmParams.nouvelle_fiche },
      });
      return r.lignes.length ? "\n" + r.lignes.map((l) => `CRM : ${l}`).join("\n") : "";
    } catch (e) {
      return `\n⚠️ CRM non mis à jour (${e.message}). La séquence, elle, est bien écrite.`;
    }
  }
  server.tool("agent_sequence_upsert", "Créer ou mettre à jour l'état d'une CIBLE suivie dans une campagne (mission kind=campagne) — étape, prochaine échéance, dates, sentiment. Une cible est une PERSONNE (contact_crm/candidat_recruitee/externe : invitation → message → relances) ou une PLATEFORME de besoins (plateforme : ouverture → liste des besoins → besoins ouverts → qualifiés au CRM). Clé = mission_id + target_kind + target_ref. Campagne de prospection (config.preset=prospection, et seulement elle) : le CRM suit tout seul. À la première vraie tentative de contact (invitation acceptée, premier mail, premier appel), la fiche Prospect est liée (lien, profil LinkedIn, prénom + nom + société) ou créée en Contacté ; son étape avance sans jamais reculer ; une ligne d'historique par événement ; tâche « Répondre à X » sur réponse positive. Ne pas recontacter, Perdu et homonyme passent par le GO de Nicolas au parapheur. Passe evenement, motif_sortie, rdv_date et l'identité (prenom, nom, societe, linkedin_url) ; sans evenement, il est déduit du changement d'état. Un échec CRM n'empêche jamais l'écriture de la séquence : il est signalé dans la réponse.", {
    id: z.string().optional().describe("Identifiant d'une séquence EXISTANTE. Fourni, il désigne CETTE ligne-là : elle est mise à jour, y compris pour changer de campagne (mission_id). Sans lui, la clé reste mission_id + target_kind + target_ref."),
    mission_id: z.string(), target_kind: z.enum(["contact_crm", "candidat_recruitee", "externe", "plateforme"]), target_ref: z.string(), target_label: z.string(),
    etape: z.number().optional(), next_due_at: z.string().nullable().optional(), nb_relances: z.number().optional(),
    sent_at: z.string().optional(), accepted_at: z.string().optional(), replied_at: z.string().optional(),
    sentiment: z.enum(["positif", "neutre", "negatif"]).optional(), statut: z.enum(["active", "replied", "paused", "stopped", "converted"]).optional(), notes: z.string().optional(),
    // Cible à rythme propre (target_kind='plateforme') : sa cadence, son heure, son playbook.
    // Nulles chez une personne — sa cadence vient de la campagne (config.cadence.relances).
    cadence_jours: z.number().optional().describe("Plateforme : jours entre deux passages (1 = quotidien)."),
    heure_passage: z.string().optional().describe("Plateforme : heure de passage HH:MM (Europe/Paris). Les scans sont sérialisés : étaler les heures."),
    playbook_path: z.string().nullable().optional().describe("Chemin du playbook dans le dépôt Jules (routines/scan-plateformes/references/*.md). Peut être vide : la fiche n'existe pas encore."),
    resume_at: z.string().nullable().optional().describe("Séquence en pause : date de reprise automatique."),
    // Volet CRM des campagnes de prospection (jamais écrit dans la séquence).
    evenement: z.enum(CAMPAGNE_EVENEMENTS).optional().describe("Campagne de prospection : ce qui vient de se passer (acceptee, message_envoye, relance_envoyee, reponse, conversion, mail_envoye, appel_passe, sortie). Sans lui, il est déduit du changement d'étape, de statut ou de sentiment."),
    motif_sortie: z.enum(CAMPAGNE_MOTIFS_SORTIE).optional().describe("Avec evenement=sortie : converti, refus, silence, profil (pas le bon profil), doublon, npc (ne me contactez plus), autre."),
    rdv_date: z.string().optional().describe("Avec evenement=conversion : date du RDV (2026-10-06T14:30 = heure de Paris). Sans elle, la prochaine action est « Confirmer la date du RDV »."),
    canal: z.enum(CAMPAGNE_CANAUX).optional().describe("Canal de l'événement, pour le type d'historique : linkedin (défaut), mail, appel."),
    prenom: z.string().optional().describe("Identité de la personne, exigée pour créer sa fiche au premier contact."),
    nom: z.string().optional(), societe: z.string().optional(), linkedin_url: z.string().optional(),
    contact_id: z.number().optional().describe("Lier explicitement la séquence à cette fiche CRM (réponse de Nicolas à une question d'homonyme)."),
    nouvelle_fiche: z.boolean().optional().describe("Créer une nouvelle fiche malgré un homonyme (décision de Nicolas)."),
  }, wrap(async ({ id, ...brut }) => {
    const p = {}, crmParams = {};
    for (const [k, v] of Object.entries(brut)) (PARAMS_CRM.includes(k) ? crmParams : p)[k] = v;
    p.target_ref = refCanonique(p.target_kind, p.target_ref);
    const { mission, erreur: erreurMission } = await lireMission(p.mission_id);
    // Un `id` fourni DÉSIGNE cette ligne-là. Avant le 22/09 ce paramètre n'existait pas :
    // il était donc ignoré en silence, la recherche par clé (mission_id + target_ref) ne
    // trouvait rien sur la nouvelle campagne, et l'outil CRÉAIT une seconde séquence en
    // laissant la première active. Deux séquences actives sur la même personne = le message
    // part DEUX fois, depuis deux campagnes, et consomme deux fois le quota LinkedIn.
    // Rattrapé à la main le 21/09 sur Quentin Muhl et Alice Bonneau, avant tout envoi.
    if (id) {
      checkUuid(id, "séquence id");
      const cible = await sbGet("agent_sequences", { id: `eq.${id}`, select: COLS_AVANT });
      if (!cible.length) throw new Error(`séquence ${id} introuvable — rien n'a été écrit (on ne crée jamais une ligne à la place d'un id qu'on ne retrouve pas)`);
      const avant = cible[0];
      const deplacee = avant.mission_id !== p.mission_id;
      const s = await sbPatch("agent_sequences", { id }, p);
      await event("worker", deplacee ? "sequence.deplacee" : "sequence.updated",
                  `${p.target_label} → étape ${p.etape ?? "?"}${deplacee ? ` (déplacée de campagne)` : ""}`,
                  { sequence_id: id });
      const crmTxt = await voletCrm({ mission, erreurMission, avant: deplacee ? null : avant, apres: { ...avant, ...p, ...s, id }, crmParams, p });
      return ok(`✅ Séquence ${p.target_label} ${deplacee ? "DÉPLACÉE vers cette campagne" : "mise à jour"} (${s.id || id})${crmTxt}`);
    }
    const existing = await sbGet("agent_sequences", { mission_id: `eq.${p.mission_id}`, target_kind: `eq.${p.target_kind}`, target_ref: `eq.${p.target_ref}`, select: COLS_AVANT });
    // Filet anti-doublon : la même personne suivie ailleurs, ACTIVE. On ne refuse pas — deux
    // campagnes peuvent légitimement viser quelqu'un — mais on le DIT, pour que le doublon ne
    // se découvre pas le jour où la personne reçoit deux messages.
    let alerte = "";
    if (!existing.length) {
      if (estCampagneProspection(mission) && estPersonne(p.target_kind)) {
        const refus = await refusNpc(p, crmParams);
        if (refus) return ok(refus);
      }
      const ailleurs = await sbGet("agent_sequences", {
        target_ref: `eq.${p.target_ref}`, statut: "eq.active", select: "id,mission_id",
      });
      const autres = ailleurs.filter((a) => a.mission_id !== p.mission_id);
      if (autres.length) alerte = ` — ⚠️ ${p.target_label} est DÉJÀ suivi(e) activement sur ${autres.length} autre(s) campagne(s) : ${autres.map((a) => a.id.slice(0, 8)).join(", ")}. Si c'est un déplacement, rappeler cet outil avec l'\`id\` de la séquence existante au lieu d'en créer une seconde.`;
    }
    const s = existing.length ? await sbPatch("agent_sequences", { id: existing[0].id }, p) : await sbPost("agent_sequences", p);
    const sid = s.id || existing[0]?.id;
    await event("worker", existing.length ? "sequence.updated" : "sequence.created", `${p.target_label} → étape ${p.etape ?? "?"}`, { sequence_id: sid });
    const avant = existing[0] || null;
    const crmTxt = await voletCrm({ mission, erreurMission, avant, apres: { ...(avant || {}), ...p, ...s, id: sid }, crmParams, p });
    return ok(`✅ Séquence ${p.target_label} ${existing.length ? "mise à jour" : "créée"} (${sid})${alerte}${crmTxt}`);
  }));
```

Ne rien changer à `agent_sequence_list` ni à la suite.

- [ ] **Étape 5 : passer les dépendances CRM depuis `index.mjs`**

Dans `server/index.mjs`, fonction `main()`, remplacer :

```js
  registerAgentTools(server, { sbGet, sbPost, sbPatch, sbDelete, sbRpc, handleError, z });
```

par :

```js
  registerAgentTools(server, { sbGet, sbPost, sbPatch, sbDelete, sbRpc, handleError, z, crm: { resolveCompteId, syncContactCompte, getAgenceFor, getAuthCaller } });
```

- [ ] **Étape 6 : vérifier**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes && node --check server/agent-tools.mjs && node --check server/index.mjs && node --test tests/*.test.mjs`
Attendu : tout passe, dont les 9 tests de `agent-sequence-campagne.test.mjs` (`REVIEW FOCUS 4` compris) et, SANS modification, tous ceux de `agent-tools.test.mjs`.

- [ ] **Étape 7 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes add server/agent-tools.mjs server/index.mjs tests/agent-sequence-campagne.test.mjs
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes commit -m "feat(mcp): agent_sequence_upsert tient le pipeline prospect des campagnes de prospection"
```

---

## Tâche 8 : GO de Nicolas au parapheur (Ne pas recontacter, Perdu, homonyme)

**Files :**
- Modify : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/server/campagne-crm.mjs` (fonction `appliqueEffetsCampagne` et ajout à la fin)
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/campagne-demandes.test.mjs`

**Interfaces :**
- Consumes : `ecritEffets(deps, ctx)` (tâche 6, non exporté, même fichier) qui rend `demandes` ; `deps.sbGet`, `deps.sbPost` ; tables `agent_tasks` (`mission_id, titre, type, statut, priorite, due_at, payload`), `agent_approvals` (`nature, titre, detail, options, task_id, statut`), `agent_events` ; type de tâche `libre` (existant, `payload_keys = {instruction}`).
- Produces (exports de `server/campagne-crm.mjs`) : `titreDemande(genre, campagne, qui, contact) -> string`, `contenuDemande(d, { campagne, qui }) -> { nature, options, detail, instruction }`, `deposeDemande(deps, d) -> string` (ligne de réponse) ; `appliqueEffetsCampagne` dépose désormais chaque demande et ajoute sa ligne.

Contexte : décision 7 et 8 du plan. Dans l'app, `julesActions.accorder` et `julesActions.repondre` repassent la tâche liée de `waiting_go` à `due` ; `agent_approval_decide` (MCP) fait de même et met `decision` dans `payload`. Un refus annule la tâche. La carte ne doit JAMAIS être liée à `process.env.JULES_TASK_ID` (d'où l'appel direct à `sbPost("agent_approvals", ...)` et non à l'outil `agent_approval_create`). `statut: "pending"` est écrit explicitement pour que le contrôle de doublon lise la même valeur que la base.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/campagne-demandes.test.mjs` :

```js
// Ne pas recontacter, Perdu et homonyme passent par le GO de Nicolas (SPEC §4, Autonomie) : la demande
// arrive au parapheur avec une tache qui porte l'appel exact, et l'etape ne bouge pas avant.
import { test } from "node:test";
import assert from "node:assert/strict";
import { fausseBase } from "./fausse-base.mjs";
import { deposeDemande, appliqueEffetsCampagne } from "../server/campagne-crm.mjs";

const MISSION = { id: "11111111-1111-4111-8111-111111111111", titre: "Prospection DSI Lyon", kind: "campagne", config: { preset: "prospection" }, owner_id: "u1" };
const SEQ = { id: "22222222-2222-4222-8222-222222222222", mission_id: MISSION.id, target_kind: "externe", target_ref: "jean-dupont",
              target_label: "Jean Dupont", etape: 3, statut: "stopped", nb_relances: 0, next_due_at: null, notes: null, contact_id: 7 };
const JEAN = { id: 7, prenom: "Jean", nom: "DUPONT", statut: "Prospect", responsable: "Nicolas Serradeil", etape_prospect: "Contacté",
               employeur: null, linkedin: "https://www.linkedin.com/in/jean-dupont", motif_perte: null };
const GO_NPC = { etape: "Ne pas recontacter", motif_perte: null, motif_perte_precision: "Demande en campagne Prospection DSI Lyon" };
const GO_PERDU = { etape: "Perdu", motif_perte: "Pas le bon interlocuteur", motif_perte_precision: "Sortie de la campagne Prospection DSI Lyon : pas le bon profil" };
const npc = () => ({ genre: "npc", mission: MISSION, sequence: SEQ, evt: { type: "sortie", motif: "npc" }, identite: {},
                     owner: "Nicolas Serradeil", contact: JEAN, go: GO_NPC });

test("npc : tache libre en attente de GO portant l'appel exact, carte go liee a cette tache", async () => {
  process.env.JULES_TASK_ID = "33333333-3333-4333-8333-333333333333";
  try {
    const b = fausseBase({});
    const ligne = await deposeDemande(b, npc());
    const [t] = b.tables.agent_tasks;
    const [a] = b.tables.agent_approvals;
    assert.equal(t.type, "libre"); assert.equal(t.statut, "waiting_go"); assert.equal(t.mission_id, MISSION.id);
    assert.match(t.payload.instruction, /crm_update_contact avec contact_id=7, champ="etape_prospect", valeur="Ne pas recontacter"/);
    assert.match(t.payload.instruction, /motif_perte_precision="Demande en campagne Prospection DSI Lyon", responsable="Nicolas Serradeil"/);
    assert.deepEqual(t.payload.campagne_crm, { genre: "npc", sequence_id: SEQ.id, contact_id: 7 });
    assert.equal(a.nature, "go"); assert.equal(a.task_id, t.id);
    assert.notEqual(a.task_id, process.env.JULES_TASK_ID, "le GO ne relance jamais la tache de campagne en cours");
    assert.equal(a.titre, "Campagne Prospection DSI Lyon : passer Jean DUPONT (fiche 7) en Ne pas recontacter");
    assert.match(ligne, /^demande déposée au parapheur/);
  } finally { delete process.env.JULES_TASK_ID; }
});

test("une demande deja en attente n'est pas redeposee", async () => {
  const b = fausseBase({});
  await deposeDemande(b, npc());
  const ligne = await deposeDemande(b, npc());
  assert.equal(b.tables.agent_approvals.length, 1);
  assert.equal(b.tables.agent_tasks.length, 1);
  assert.match(ligne, /déjà au parapheur/);
});

test("perdu : valeur Perdu, motif Pas le bon interlocuteur", async () => {
  const b = fausseBase({});
  await deposeDemande(b, { ...npc(), genre: "perdu", evt: { type: "sortie", motif: "profil" }, go: GO_PERDU });
  const [t] = b.tables.agent_tasks;
  assert.match(t.payload.instruction, /valeur="Perdu", motif_perte="Pas le bon interlocuteur", motif_perte_precision="Sortie de la campagne Prospection DSI Lyon : pas le bon profil"/);
  assert.equal(b.tables.agent_approvals[0].titre, "Campagne Prospection DSI Lyon : passer Jean DUPONT (fiche 7) en Perdu, pas le bon interlocuteur");
});

test("homonyme : decision, une option par fiche plus Creer une nouvelle fiche, instruction rappelable telle quelle", async () => {
  const b = fausseBase({});
  await deposeDemande(b, { genre: "homonyme", mission: MISSION, sequence: { ...SEQ, contact_id: null }, evt: { type: "acceptee", canal: "linkedin" },
    identite: { prenom: "Jean", nom: "Dupont", societe: "Orange", linkedin_url: "https://www.linkedin.com/in/jean-dupont/" }, owner: "Nicolas Serradeil",
    contact: null, homonymes: [{ id: 9, prenom: "Jean", nom: "DUPONT", statut: "Prospect", societe: "Crédit Agricole" }] });
  const [a] = b.tables.agent_approvals;
  const [t] = b.tables.agent_tasks;
  assert.equal(a.nature, "decision");
  assert.deepEqual(a.options, ["Lier à la fiche 9 (Jean DUPONT, Crédit Agricole, Prospect)", "Créer une nouvelle fiche"]);
  assert.equal(a.titre, "Campagne Prospection DSI Lyon : Jean Dupont, homonyme au CRM, lier ou créer ?");
  assert.match(t.payload.instruction, new RegExp(`agent_sequence_upsert avec id="${SEQ.id}", mission_id="${MISSION.id}", target_kind="externe", target_ref="jean-dupont", target_label="Jean Dupont", evenement="acceptee", contact_id=N`));
  assert.match(t.payload.instruction, /nouvelle_fiche=true, prenom="Jean", nom="Dupont", societe="Orange", linkedin_url="https:\/\/www\.linkedin\.com\/in\/jean-dupont\/"/);
});

test("de bout en bout : un ne me contactez plus arrive au parapheur et l'etape ne bouge pas", async () => {
  const b = fausseBase({ profiles: [{ id: "u1", nom: "Nicolas Serradeil" }], agent_sequences: [SEQ], contacts: [JEAN] });
  const r = await appliqueEffetsCampagne({ ...b, getAgenceFor: async () => "Lyon" }, { mission: MISSION, owner: "Nicolas Serradeil", sequence: { ...SEQ },
    evt: { type: "sortie", motif: "npc", canal: "linkedin", rdv_date: null, sentiment: null }, identite: {}, lien: {},
    maintenant: new Date("2026-09-29T10:00:00+02:00") });
  assert.equal(b.tables.contacts[0].etape_prospect, "Contacté");
  assert.equal(b.tables.agent_approvals.length, 1);
  assert.ok(r.lignes.some((l) => /^demande déposée au parapheur/.test(l)), r.lignes.join(" | "));
});

test("de bout en bout : un homonyme arrive au parapheur, rien n'est cree", async () => {
  const autre = { id: 9, prenom: "Jean", nom: "DUPONT", statut: "Prospect", responsable: "Camille Salinson", etape_prospect: "Contacté", employeur: null, linkedin: null };
  const s = { ...SEQ, contact_id: null, target_ref: "jean-dupont-2", statut: "active", etape: 2 };
  const b = fausseBase({ profiles: [{ id: "u1", nom: "Nicolas Serradeil" }], agent_sequences: [s], contacts: [autre],
    contact_compte: [{ contact_id: 9, compte_id: "c9", is_primary: true }], comptes: [{ id: "c9", nom: "Crédit Agricole" }] });
  const r = await appliqueEffetsCampagne({ ...b, getAgenceFor: async () => "Lyon" }, { mission: MISSION, owner: "Nicolas Serradeil", sequence: { ...s },
    evt: { type: "acceptee", canal: "linkedin", motif: null, rdv_date: null, sentiment: null },
    identite: { prenom: "Jean", nom: "Dupont", societe: "Orange" }, lien: {}, maintenant: new Date("2026-09-29T10:00:00+02:00") });
  assert.equal(b.tables.contacts.length, 1);
  assert.equal(b.tables.agent_approvals[0].nature, "decision");
  assert.ok(r.lignes.some((l) => /homonyme/.test(l)));
});

test("aucun tiret cadratin dans titres, details, options et instructions", async () => {
  const b = fausseBase({});
  await deposeDemande(b, npc());
  await deposeDemande(b, { ...npc(), genre: "perdu", go: GO_PERDU });
  await deposeDemande(b, { genre: "homonyme", mission: MISSION, sequence: SEQ, evt: { type: "acceptee" }, identite: { prenom: "Jean", nom: "Dupont" },
    owner: "Nicolas Serradeil", contact: null, homonymes: [{ id: 9, prenom: "Jean", nom: "DUPONT", statut: "Prospect", societe: "" }] });
  const tout = JSON.stringify([b.tables.agent_approvals, b.tables.agent_tasks]);
  assert.doesNotMatch(tout, /[\u2013\u2014]/);
});
```

- [ ] **Étape 2 : le lancer et le voir échouer**

Commande : `node --test /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/campagne-demandes.test.mjs`
Attendu : `SyntaxError: The requested module '../server/campagne-crm.mjs' does not provide an export named 'deposeDemande'`.

- [ ] **Étape 3 : implémenter**

Dans `server/campagne-crm.mjs`, remplacer la fonction posée par la tâche 6 :

```js
export async function appliqueEffetsCampagne(deps, ctx) {
  const r = await ecritEffets(deps, ctx);
  return r;
}
```

par (la fonction, puis la section des demandes, jusqu'à la fin du fichier) :

```js
export async function appliqueEffetsCampagne(deps, ctx) {
  const r = await ecritEffets(deps, ctx);
  for (const d of r.demandes) {
    r.lignes.push(await deposeDemande(deps, { ...d, mission: ctx.mission, sequence: ctx.sequence, evt: ctx.evt,
      identite: ctx.identite || {}, owner: ctx.owner }));
  }
  return r;
}

// ── Demandes de GO au parapheur : Ne pas recontacter, Perdu, homonyme (SPEC §4, Autonomie) ──
// Chaque demande = une tache `libre` en attente de GO, dont le payload porte l'appel EXACT a faire,
// et une carte au parapheur liee a CETTE tache (jamais a la tache de campagne en cours : son GO la
// relancerait en entier). GO ou reponse = la tache repart (mecanisme existant du parapheur) ;
// refus = elle est annulee. Titre deterministe : une demande deja en attente n'est pas redeposee.
export function titreDemande(genre, campagne, qui, contact) {
  if (genre === "npc") return `Campagne ${campagne} : passer ${qui} (fiche ${contact.id}) en Ne pas recontacter`;
  if (genre === "perdu") return `Campagne ${campagne} : passer ${qui} (fiche ${contact.id}) en Perdu, pas le bon interlocuteur`;
  return `Campagne ${campagne} : ${qui}, homonyme au CRM, lier ou créer ?`;
}

export function contenuDemande(d, { campagne, qui }) {
  if (d.genre === "homonyme") {
    const idt = d.identite || {};
    const s = d.sequence;
    const options = d.homonymes.map((h) => `Lier à la fiche ${h.id} (${[h.prenom, h.nom].filter(Boolean).join(" ")}, ${h.societe || "société inconnue"}, ${h.statut || "statut inconnu"})`)
      .concat(["Créer une nouvelle fiche"]);
    const appel = `id="${s.id}", mission_id="${d.mission.id}", target_kind="${s.target_kind}", target_ref="${s.target_ref}", target_label="${s.target_label}", evenement="${d.evt.type}"`
      + (d.evt.motif ? `, motif_sortie="${d.evt.motif}"` : "")
      + (d.evt.rdv_date ? `, rdv_date="${d.evt.rdv_date}"` : "")
      + (d.evt.canal && d.evt.canal !== "linkedin" ? `, canal="${d.evt.canal}"` : "");
    const identite = `prenom="${idt.prenom || ""}", nom="${idt.nom || ""}", societe="${idt.societe || ""}", linkedin_url="${idt.linkedin_url || ""}"`;
    return {
      nature: "decision", options,
      detail: `${qui}${idt.societe ? ` (${idt.societe})` : ""} vient de la campagne ${campagne}. Une ou plusieurs fiches du CRM portent le même prénom et le même nom dans une autre société : homonyme ou changement de poste ? Rien n'a été créé ni lié en attendant ta réponse.`,
      instruction: `Question d'homonyme tranchée par Nicolas : lire payload.decision. Si elle commence par « Lier à la fiche N », appeler agent_sequence_upsert avec ${appel}, contact_id=N. Si elle vaut « Créer une nouvelle fiche », appeler agent_sequence_upsert avec ${appel}, nouvelle_fiche=true, ${identite}. Sinon, ne rien faire. Clore ensuite cette tâche avec agent_task_done.`,
    };
  }
  const npc = d.genre === "npc";
  const c = d.contact;
  const args = `contact_id=${c.id}, champ="etape_prospect", valeur="${npc ? "Ne pas recontacter" : "Perdu"}"`
    + (npc ? "" : `, motif_perte="${d.go.motif_perte}"`)
    + `, motif_perte_precision="${d.go.motif_perte_precision}", responsable="${d.owner}"`;
  return {
    nature: "go", options: undefined,
    detail: npc
      ? `${qui} (fiche ${c.id}) a demandé à ne plus être contacté(e) pendant la campagne ${campagne}. Au GO, la fiche passe en « Ne pas recontacter ». Sans GO, l'étape ne bouge pas.`
      : `${qui} (fiche ${c.id}) n'est pas le bon profil pour la campagne ${campagne}. Au GO, la fiche passe en « Perdu », motif « Pas le bon interlocuteur ». Sans GO, l'étape ne bouge pas.`,
    instruction: `GO de Nicolas reçu (un refus aurait annulé cette tâche). Appeler crm_update_contact avec ${args}. Clore ensuite cette tâche avec agent_task_done.`,
  };
}

export async function deposeDemande(deps, d) {
  const { sbGet, sbPost } = deps;
  const campagne = d.mission.titre || "";
  const idt = d.identite || {};
  const qui = d.contact ? [d.contact.prenom, d.contact.nom].filter(Boolean).join(" ")
    : ([idt.prenom, idt.nom].filter(Boolean).join(" ") || d.sequence.target_label);
  const titre = titreDemande(d.genre, campagne, qui, d.contact);
  const deja = await sbGet("agent_approvals", { titre: `eq.${titre}`, statut: "eq.pending", select: "id", limit: "1" });
  if (deja.length) return `demande déjà au parapheur (${deja[0].id}), rien redéposé`;
  const { nature, options, detail, instruction } = contenuDemande(d, { campagne, qui });
  const t = await sbPost("agent_tasks", { mission_id: d.mission.id, titre, type: "libre", statut: "waiting_go", priorite: 2,
    due_at: new Date().toISOString(),
    payload: { instruction, campagne_crm: { genre: d.genre, sequence_id: d.sequence.id, contact_id: d.contact ? d.contact.id : null } } });
  const a = await sbPost("agent_approvals", { nature, titre, detail, options, task_id: t.id, statut: "pending" });
  try {
    await sbPost("agent_events", { actor: "mcp", kind: "approval.created", message: `${nature} : ${titre}`,
      task_id: t.id, mission_id: d.mission.id, sequence_id: d.sequence.id });
  } catch (_) { /* journal annexe, jamais bloquant */ }
  return `demande déposée au parapheur (${a.id}) : ${titre}`;
}
```

- [ ] **Étape 4 : relancer toute la suite MCP**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes && node --test tests/*.test.mjs`
Attendu : tout passe (7 tests dans `campagne-demandes.test.mjs` ; les tests des tâches 5, 6 et 7 inchangés et verts).

- [ ] **Étape 5 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes add server/campagne-crm.mjs tests/campagne-demandes.test.mjs
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes commit -m "feat(mcp): campagnes, Ne pas recontacter, Perdu et homonyme au GO de Nicolas"
```

---

## Tâche 9 : version 8.27.0 et changelog

**Files :**
- Modify : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/server/index.mjs` (`CRM_VERSION`, `CRM_BUILD_DATE`, texte de `crm_version`)
- Modify : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/manifest.json` (`version`, `long_description`, description de l'outil `agent_sequence_upsert` dans `tools`)
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/version-8-27.test.mjs`

**Interfaces :**
- Consumes : état final des tâches 2 à 8 (ce que le changelog décrit).
- Produces : `CRM_VERSION = "8.27.0"`, `manifest.version = "8.27.0"`. Lu par la tâche 13 (`crm_version` en recette).

Contexte : règle du dépôt, toute évolution du MCP bumpe la version dans `index.mjs` ET `manifest.json`. Le changelog vit dans la chaîne du `server.tool("crm_version", ...)`, sous forme de template literal où les retours à la ligne sont écrits `\n` (deux caractères, barre oblique inverse puis n), comme les entrées voisines.

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/version-8-27.test.mjs` :

```js
// Toute evolution du MCP : version dans index.mjs ET manifest.json, changelog, description d'outil.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const manifest = JSON.parse(readFileSync(new URL("../manifest.json", import.meta.url), "utf8"));
const index = readFileSync(new URL("../server/index.mjs", import.meta.url), "utf8");

test("version 8.27.0 partout : manifest, CRM_VERSION, changelog", () => {
  assert.equal(manifest.version, "8.27.0");
  assert.match(manifest.long_description, /^Connecteur MCP v8\.27\.0 pour le CRM Upgrade\. v8\.27\.0 : /);
  assert.match(index, /const CRM_VERSION = "8\.27\.0";/);
  const i27 = index.indexOf("**Changelog v8.27.0 :**"), i26 = index.indexOf("**Changelog v8.26.0 :**");
  assert.ok(i27 > 0 && i27 < i26, "l'entree 8.27.0 precede la 8.26.0");
});

test("changelog 8.27.0, description du manifest et de l'outil : sans tiret cadratin", () => {
  const entree = index.slice(index.indexOf("**Changelog v8.27.0 :**"), index.indexOf("**Changelog v8.26.0 :**"));
  assert.match(entree, /agent_sequence_upsert/);
  assert.doesNotMatch(entree, /[\u2013\u2014]/);
  const ld = manifest.long_description.slice(0, manifest.long_description.indexOf(" v8.26.0 :"));
  assert.doesNotMatch(ld, /[\u2013\u2014]/);
  const outil = manifest.tools.find((t) => t.name === "agent_sequence_upsert");
  const ajout = outil.description.slice(outil.description.indexOf("Campagne de prospection"));
  assert.match(ajout, /nouvelle_fiche/);
  assert.doesNotMatch(ajout, /[\u2013\u2014]/);
});
```

- [ ] **Étape 2 : le lancer et le voir échouer**

Commande : `node --test /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes/tests/version-8-27.test.mjs`
Attendu : `AssertionError [ERR_ASSERTION]: Expected values to be strictly equal: '8.26.0' !== '8.27.0'`.

- [ ] **Étape 3 : bumper `index.mjs`**

3a. Remplacer `const CRM_VERSION = "8.26.0";` par `const CRM_VERSION = "8.27.0";`.
3b. Dans `const CRM_BUILD_DATE = "...";`, mettre la date du jour du commit au format `YYYY-MM-DD` (sortie de la commande `date +%F`).
3c. Dans le texte de `crm_version`, insérer IMMÉDIATEMENT AVANT `**Changelog v8.26.0 :**` (occurrence unique) le texte suivant, tel quel (les `\n` sont les deux caractères barre oblique inverse et n) :

```text
**Changelog v8.27.0 :**\n- Campagnes de prospection de Jules : agent_sequence_upsert tient le pipeline Prospect à jour tout seul, pour les campagnes dont config.preset vaut prospection et elles seules. À la première vraie tentative de contact (invitation acceptée, premier mail, premier appel), la fiche est liée (lien de la séquence, profil LinkedIn normalisé, puis prénom, nom et société) ou créée en Contacté. L'étape avance sans jamais reculer (Contacté, En discussion, RDV planifié, En veille avec réveil à 6 mois), une ligne d'historique par événement, tâche « Répondre à X » le jour ouvré suivant à 09h00. Ne pas recontacter, Perdu et homonyme passent par le GO de Nicolas au parapheur. Nouveaux paramètres : evenement, motif_sortie, rdv_date, canal, prenom, nom, societe, linkedin_url, contact_id, nouvelle_fiche ; sans evenement, il est déduit du changement d'état. Une fiche en Ne pas recontacter n'entre jamais dans une campagne de prospection. Un échec CRM ne bloque jamais l'écriture de la séquence. Colonne agent_sequences.contact_id (migration 54).\n\n
```

- [ ] **Étape 4 : bumper `manifest.json`**

4a. Remplacer `"version": "8.26.0",` par `"version": "8.27.0",`.
4b. Remplacer le début de la description longue `"long_description": "Connecteur MCP v8.26.0 pour le CRM Upgrade. v8.26.0 :` par :

```text
"long_description": "Connecteur MCP v8.27.0 pour le CRM Upgrade. v8.27.0 : campagnes de prospection de Jules, agent_sequence_upsert tient le pipeline Prospect (fiche liée ou créée au premier contact, étape qui ne recule jamais, historique, tâche Répondre à X ; Ne pas recontacter, Perdu et homonyme au GO de Nicolas), colonne agent_sequences.contact_id (migration 54). v8.26.0 :
```

4c. Dans le tableau `tools`, description de `agent_sequence_upsert`, remplacer la fin `Clé = mission_id + target_kind + target_ref."` (occurrence unique dans le fichier) par :

```text
Clé = mission_id + target_kind + target_ref. Campagne de prospection (config.preset=prospection) : le CRM suit tout seul (fiche liée ou créée au premier contact, étape, historique, tâche Répondre à X ; GO de Nicolas pour Ne pas recontacter, Perdu et homonyme). Paramètres evenement, motif_sortie, rdv_date, canal, prenom, nom, societe, linkedin_url, contact_id, nouvelle_fiche."
```

- [ ] **Étape 5 : vérifier**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes && python3 -c "import json; json.load(open('manifest.json'))" && node --check server/index.mjs && node --test tests/*.test.mjs`
Attendu : JSON valide, `node --check` silencieux, tout passe (2 tests dans `version-8-27.test.mjs`).

- [ ] **Étape 6 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes add server/index.mjs manifest.json tests/version-8-27.test.mjs
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes commit -m "chore(mcp): v8.27.0, campagnes de prospection et pipeline prospect"
```

---

## Tâche 10 : app, correspondance des sorties manuelles et jeu de cas commun

**Files :**
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline/tests/fixtures/campagne-sortie-cas.json`
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline/tests/campagne-sortie.test.mjs`
- Modify : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline/index.html` (bloc de fonctions racine inséré juste avant `const TYPES_ACTION     = [`)

**Interfaces :**
- Consumes (fonctions racine existantes d'`index.html`) : `PROSPECT_ETAPES_ACTIVES`, `prospectEtapeOuDefaut(contact)`, `prospectPatchEtape(etape, form)`, `prospectReveilPreset(base, '6m')`, `prospectTachePayload(contact, etape, form, responsable)` (form avec `creer_tache: true`), `combineDT`, `DEFAULT_TASK_TIME`.
- Produces (fonctions racine d'`index.html`) : `CAMPAGNE_MOTIF_PERTE_PROFIL`, `CAMPAGNE_LIBELLES_SORTIE`, `campagneEstProspection(mission) -> boolean`, `campagneEffetSortie(motif, contact) -> { action, etape, motif_perte, reveil6m }` (miroir exact de `effetSortie` du MCP), `campagneJourOuvreSuivant('YYYY-MM-DD') -> 'YYYY-MM-DD'`, `campagneSortiePlan(motif, contact, { campagne, aujourdhui, responsable, precision }) -> { effet, patch, tache, fermeTaches, detail }`. Consommés par la tâche 11.

Contexte : spec §6.4, « les règles existent deux fois (app et MCP), verrouillées par un jeu de cas commun lu par les deux suites ». Le fichier JSON ci-dessous est la copie IDENTIQUE de `tests/fixtures/campagne-sortie-cas.json` du repo MCP (tâche 3) : ne pas en changer un caractère. Les tests extraient les fonctions d'`index.html` par leur nom (méthode de `tests/prospect-pipeline.test.mjs`) : chaque fonction racine doit commencer par `\nfunction nom(` et finir par une ligne `}` seule en colonne 0 ; aucune ligne `}` en colonne 0 à l'intérieur (les fonctions imbriquées sont indentées).

- [ ] **Étape 1 : poser le jeu de cas commun**

Créer `tests/fixtures/campagne-sortie-cas.json` :

```json
{
  "commentaire": "Jeu de cas commun : copie identique dans tests/fixtures/ du repo web (worktree prospects-pipeline) et du repo MCP (worktree campagnes). Motif de sortie de campagne vers effet sur la fiche liee. action : rien, historique, etape ou go (GO de Nicolas cote Jules, applique directement par Nicolas dans l app). Toute modification se fait dans les deux copies.",
  "cas": [
    { "nom": "converti, A contacter : RDV planifie", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "À contacter" },
      "attendu": { "action": "etape", "etape": "RDV planifié", "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, prospect sans etape : RDV planifie", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": null },
      "attendu": { "action": "etape", "etape": "RDV planifié", "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, En discussion : RDV planifie", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "En discussion" },
      "attendu": { "action": "etape", "etape": "RDV planifié", "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, RDV planifie : pas de recul, historique", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "RDV planifié" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, Qualifie : pas de recul, historique", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "Qualifié" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, En veille : reprise en RDV planifie", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "En veille" },
      "attendu": { "action": "etape", "etape": "RDV planifié", "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, Perdu reste Perdu", "motif": "converti", "contact": { "statut": "Prospect", "etape_prospect": "Perdu" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "converti, Client : statut intouche", "motif": "converti", "contact": { "statut": "Client", "etape_prospect": null },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "refus, Contacte : En veille a 6 mois", "motif": "refus", "contact": { "statut": "Prospect", "etape_prospect": "Contacté" },
      "attendu": { "action": "etape", "etape": "En veille", "motif_perte": null, "reveil6m": true } },
    { "nom": "refus, deja En veille : reveil repousse", "motif": "refus", "contact": { "statut": "Prospect", "etape_prospect": "En veille" },
      "attendu": { "action": "etape", "etape": "En veille", "motif_perte": null, "reveil6m": true } },
    { "nom": "refus, Perdu reste Perdu", "motif": "refus", "contact": { "statut": "Prospect", "etape_prospect": "Perdu" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "refus, Candidat : historique", "motif": "refus", "contact": { "statut": "Candidat", "etape_prospect": null },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "silence, Qualifie : En veille", "motif": "silence", "contact": { "statut": "Prospect", "etape_prospect": "Qualifié" },
      "attendu": { "action": "etape", "etape": "En veille", "motif_perte": null, "reveil6m": true } },
    { "nom": "profil, Contacte : GO Perdu", "motif": "profil", "contact": { "statut": "Prospect", "etape_prospect": "Contacté" },
      "attendu": { "action": "go", "etape": "Perdu", "motif_perte": "Pas le bon interlocuteur", "reveil6m": false } },
    { "nom": "profil, En veille : historique, la sortie est reservee aux etapes actives", "motif": "profil", "contact": { "statut": "Prospect", "etape_prospect": "En veille" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "profil, Client : rien", "motif": "profil", "contact": { "statut": "Client", "etape_prospect": null },
      "attendu": { "action": "rien", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "npc, En discussion : GO Ne pas recontacter", "motif": "npc", "contact": { "statut": "Prospect", "etape_prospect": "En discussion" },
      "attendu": { "action": "go", "etape": "Ne pas recontacter", "motif_perte": null, "reveil6m": false } },
    { "nom": "npc, Perdu : GO Ne pas recontacter, protection", "motif": "npc", "contact": { "statut": "Prospect", "etape_prospect": "Perdu" },
      "attendu": { "action": "go", "etape": "Ne pas recontacter", "motif_perte": null, "reveil6m": false } },
    { "nom": "npc, Client : GO Ne pas recontacter, protection", "motif": "npc", "contact": { "statut": "Client", "etape_prospect": null },
      "attendu": { "action": "go", "etape": "Ne pas recontacter", "motif_perte": null, "reveil6m": false } },
    { "nom": "doublon : rien", "motif": "doublon", "contact": { "statut": "Prospect", "etape_prospect": "Contacté" },
      "attendu": { "action": "rien", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "autre, Contacte : historique", "motif": "autre", "contact": { "statut": "Prospect", "etape_prospect": "Contacté" },
      "attendu": { "action": "historique", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "deja Ne pas recontacter : fige", "motif": "refus", "contact": { "statut": "Prospect", "etape_prospect": "Ne pas recontacter" },
      "attendu": { "action": "rien", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "npc sur une fiche deja Ne pas recontacter : fige", "motif": "npc", "contact": { "statut": "Client", "etape_prospect": "Ne pas recontacter" },
      "attendu": { "action": "rien", "etape": null, "motif_perte": null, "reveil6m": false } },
    { "nom": "fiche absente : rien", "motif": "refus", "contact": null,
      "attendu": { "action": "rien", "etape": null, "motif_perte": null, "reveil6m": false } }
  ]
}
```

- [ ] **Étape 2 : écrire le test qui échoue**

Créer `tests/campagne-sortie.test.mjs` :

```js
// tests/campagne-sortie.test.mjs : la sortie manuelle d'une personne de campagne de prospection
// (cockpit Jules), logique pure. Fonctions extraites d'index.html, comme tests/prospect-pipeline.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

process.env.TZ = 'Europe/Paris';   // combineDT pose le decalage du poste : on fige Paris

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nconst ${nom} ?= ?[^\\n]*;\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['DEFAULT_TASK_TIME', 'combineDT', 'PROSPECT_ETAPES', 'PROSPECT_ETAPES_ACTIVES', 'PROSPECT_ETAPES_SORTIE',
              'prospectEtapeOuDefaut', 'prospectEtapeRequiert', 'prospectTacheLibelle', 'prospectTacheEcheance',
              'prospectReveilPreset', 'prospectPatchEtape', 'prospectTachePayload',
              'CAMPAGNE_MOTIF_PERTE_PROFIL', 'CAMPAGNE_LIBELLES_SORTIE', 'campagneEstProspection', 'campagneEffetSortie',
              'campagneJourOuvreSuivant', 'campagneSortiePlan'];
const API = new Function(`${NOMS.map(extrait).join('\n')}\nreturn {${NOMS.join(',')}};`)();
const { campagneEstProspection, campagneEffetSortie, campagneJourOuvreSuivant, campagneSortiePlan } = API;

const P = (etape) => ({ id: 7, prenom: 'Jean', nom: 'DUPONT', statut: 'Prospect', responsable: 'Nicolas Serradeil', etape_prospect: etape });
const CTX = { campagne: 'Prospection DSI Lyon', aujourdhui: '2026-09-29', responsable: 'Nicolas Serradeil' };

test('jeu de cas commun avec le MCP : correspondance des sorties manuelles', () => {
  const cas = JSON.parse(readFileSync(new URL('./fixtures/campagne-sortie-cas.json', import.meta.url), 'utf8')).cas;
  assert.ok(cas.length >= 20);
  for (const c of cas) assert.deepEqual(campagneEffetSortie(c.motif, c.contact), c.attendu, c.nom);
});

test('seule une campagne au preset prospection explicite touche au pipeline', () => {
  assert.equal(campagneEstProspection({ kind: 'campagne', config: { preset: 'prospection' } }), true);
  assert.equal(campagneEstProspection({ kind: 'campagne', config: {} }), false);
  assert.equal(campagneEstProspection({ kind: 'campagne', config: { preset: 'recrutement' } }), false);
  assert.equal(campagneEstProspection(null), false);
});

test('jour ouvre suivant : week-end et feries sautes, meme calcul que le MCP', () => {
  assert.equal(campagneJourOuvreSuivant('2026-09-29'), '2026-09-30');
  assert.equal(campagneJourOuvreSuivant('2026-10-02'), '2026-10-05');
  assert.equal(campagneJourOuvreSuivant('2026-11-10'), '2026-11-12');
  assert.equal(campagneJourOuvreSuivant('2026-12-24'), '2026-12-28');
  assert.equal(campagneJourOuvreSuivant('2027-03-26'), '2027-03-30');
});

test('refus : En veille, reveil a 6 mois 09h00 avec decalage, detail avec l etape', () => {
  const p = campagneSortiePlan('refus', P('Contacté'), CTX);
  assert.equal(p.patch.etape_prospect, 'En veille');
  assert.equal(p.patch.prochaine_action_date, '2027-03-29T09:00:00+02:00');
  assert.equal(p.patch.prochaine_action_libelle, 'Réveil prospect');
  assert.equal(p.detail, 'Campagne Prospection DSI Lyon : refus (sortie par Nicolas Serradeil) · étape → En veille');
  assert.equal(p.tache, null); assert.equal(p.fermeTaches, false);
});

test('converti : RDV planifie, Confirmer la date du RDV le jour ouvre suivant, tache tw_prospect_', () => {
  const p = campagneSortiePlan('converti', P('Contacté'), CTX);
  assert.equal(p.patch.etape_prospect, 'RDV planifié');
  assert.equal(p.patch.prochaine_action_date, '2026-09-30T09:00:00+02:00');
  assert.equal(p.patch.prochaine_action_libelle, 'Confirmer la date du RDV');
  assert.match(p.tache.id, /^tw_prospect_7_\d+$/);
  assert.equal(p.tache.titre, 'Confirmer la date du RDV : Jean DUPONT');
  assert.equal(p.tache.due_date, '2026-09-30T09:00:00+02:00');
  assert.equal(p.tache.responsable, 'Nicolas Serradeil');
});

test('ne plus contacter sur un Client : Ne pas recontacter pose, taches fermees, raison par defaut', () => {
  const p = campagneSortiePlan('npc', { id: 8, prenom: 'Marie', nom: 'MARTIN', statut: 'Client', responsable: 'Camille Salinson', etape_prospect: null }, CTX);
  assert.equal(p.patch.etape_prospect, 'Ne pas recontacter');
  assert.equal(p.patch.motif_perte_precision, 'Demande en campagne Prospection DSI Lyon');
  assert.equal(p.fermeTaches, true);
});

test('pas le bon profil : Perdu, motif Pas le bon interlocuteur, taches fermees', () => {
  const p = campagneSortiePlan('profil', P('En discussion'), { ...CTX, precision: 'cherche un DSI, pas un RSSI' });
  assert.equal(p.patch.etape_prospect, 'Perdu');
  assert.equal(p.patch.motif_perte, 'Pas le bon interlocuteur');
  assert.equal(p.patch.motif_perte_precision, 'cherche un DSI, pas un RSSI');
  assert.equal(p.fermeTaches, true);
});

test('autre : historique seul ; doublon : rien a ecrire', () => {
  const autre = campagneSortiePlan('autre', P('Contacté'), CTX);
  assert.equal(autre.patch, null);
  assert.equal(autre.detail, 'Campagne Prospection DSI Lyon : sortie de campagne (sortie par Nicolas Serradeil)');
  assert.equal(campagneSortiePlan('doublon', P('Contacté'), CTX).detail, null);
});

test('aucun tiret cadratin ni demi-cadratin dans le code ajoute', () => {
  const src = ['CAMPAGNE_LIBELLES_SORTIE', 'campagneEffetSortie', 'campagneJourOuvreSuivant', 'campagneSortiePlan'].map(extrait).join('\n');
  assert.doesNotMatch(src, /[\u2013\u2014]/);
});
```

- [ ] **Étape 3 : le lancer et le voir échouer**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline && node --test tests/campagne-sortie.test.mjs`
Attendu : `Error: CAMPAGNE_MOTIF_PERTE_PROFIL introuvable dans index.html`.

- [ ] **Étape 4 : implémenter**

Dans `index.html`, insérer le bloc suivant IMMÉDIATEMENT AVANT la ligne (unique) `const TYPES_ACTION     = ['Tel','Mail envoyé','Mail reçu','RDV','LinkedIn','Note interne','Autre'];` :

```js
// ═══ Campagnes de prospection de Jules : cf. SPECS_CRM/SPEC_campagnes_prospection_etapes.md ═══
// La correspondance « sortie d'une personne -> effet sur sa fiche » existe DEUX fois : ici et dans le
// MCP (server/campagne-rules.mjs, effetSortie). Elle est verrouillee par un jeu de cas commun,
// tests/fixtures/campagne-sortie-cas.json, en copie identique dans les deux repos.
const CAMPAGNE_MOTIF_PERTE_PROFIL = 'Pas le bon interlocuteur';
const CAMPAGNE_LIBELLES_SORTIE = { converti:'RDV pris', refus:'refus', silence:'fin des relances sans réponse', profil:'pas le bon profil', npc:'ne me contactez plus', doublon:'doublon', autre:'sortie de campagne' };

// Seule une campagne au preset prospection EXPLICITE touche au pipeline.
function campagneEstProspection(mission) {
  return !!(mission && mission.kind === 'campagne' && mission.config && mission.config.preset === 'prospection');
}

// { action: 'rien'|'historique'|'etape'|'go', etape, motif_perte, reveil6m } : miroir exact de effetSortie.
function campagneEffetSortie(motif, contact) {
  function r(action, etape, motifPerte, reveil) {
    return { action: action, etape: etape || null, motif_perte: motifPerte || null, reveil6m: !!reveil };
  }
  if (!contact) return r('rien');
  if (contact.etape_prospect === 'Ne pas recontacter') return r('rien');
  if (motif === 'doublon') return r('rien');
  if (motif === 'npc') return r('go', 'Ne pas recontacter');
  if (contact.statut !== 'Prospect') return motif === 'profil' ? r('rien') : r('historique');
  var etape = prospectEtapeOuDefaut(contact);
  if (etape === 'Perdu') return r('historique');
  var rang = PROSPECT_ETAPES_ACTIVES.indexOf(etape);
  if (motif === 'profil') return rang >= 0 ? r('go', 'Perdu', CAMPAGNE_MOTIF_PERTE_PROFIL) : r('historique');
  if (motif === 'refus' || motif === 'silence') return r('etape', 'En veille', null, true);
  if (motif === 'converti') {
    return (etape === 'En veille' || (rang >= 0 && rang < PROSPECT_ETAPES_ACTIVES.indexOf('RDV planifié')))
      ? r('etape', 'RDV planifié') : r('historique');
  }
  return r('historique');
}

// Jour ouvre suivant une date YYYY-MM-DD : ni samedi, ni dimanche, ni ferie francais (fixes, lundi de
// Paques, Ascension, lundi de Pentecote). Meme calcul que jourOuvreSuivant du MCP.
function campagneJourOuvreSuivant(aujourdhui) {
  var p = String(aujourdhui).slice(0, 10).split('-');
  var d = new Date(Date.UTC(+p[0], +p[1] - 1, +p[2], 12));
  function paques(y) {
    var a=y%19,b=Math.floor(y/100),c=y%100,dd=Math.floor(b/4),e=b%4,f=Math.floor((b+8)/25),g=Math.floor((b-f+1)/3),
      h=(19*a+b-dd-g+15)%30,i=Math.floor(c/4),k=c%4,l=(32+2*e+2*i-h-k)%7,m=Math.floor((a+11*h+22*l)/451),
      mo=Math.floor((h+l-7*m+114)/31),da=((h+l-7*m+114)%31)+1;
    return Date.UTC(y, mo - 1, da, 12);
  }
  function ferie(x) {
    var md = x.toISOString().slice(5, 10);
    if (['01-01','05-01','05-08','07-14','08-15','11-01','11-11','12-25'].indexOf(md) >= 0) return true;
    var p0 = paques(x.getUTCFullYear()), t = x.getTime(), j = 86400000;
    return t === p0 + j || t === p0 + 39 * j || t === p0 + 50 * j;
  }
  do { d = new Date(d.getTime() + 86400000); } while (d.getUTCDay() === 0 || d.getUTCDay() === 6 || ferie(d));
  return d.toISOString().slice(0, 10);
}

// Plan d'une sortie manuelle depuis le cockpit (Nicolas decide : les sorties qui passent par son GO
// cote Jules s'appliquent ici directement). ctx = { campagne, aujourdhui (YYYY-MM-DD), responsable,
// precision }. Rend { effet, patch, tache, fermeTaches, detail } ; detail null = rien a ecrire.
// Le detail commence comme la ligne d'historique du MCP (« Campagne <titre> : <libelle> ») : un
// evenement rejoue ensuite par Jules retrouve cette ligne et ne la double pas.
function campagneSortiePlan(motif, contact, ctx) {
  ctx = ctx || {};
  var e = campagneEffetSortie(motif, contact);
  var plan = { effet: e, patch: null, tache: null, fermeTaches: false, detail: null };
  if (e.action === 'rien') return plan;
  var base = 'Campagne ' + (ctx.campagne || '') + ' : ' + (CAMPAGNE_LIBELLES_SORTIE[motif] || CAMPAGNE_LIBELLES_SORTIE.autre)
    + ' (sortie par ' + (ctx.responsable || 'Nicolas') + ')';
  if (e.action === 'historique') { plan.detail = base; return plan; }
  var precision = ctx.precision || null;
  if (e.etape === 'En veille') {
    plan.patch = prospectPatchEtape('En veille', { prochaine_action_date: prospectReveilPreset(ctx.aujourdhui, '6m'),
      motif_perte_precision: precision });
  } else if (e.etape === 'RDV planifié') {
    var jour = campagneJourOuvreSuivant(ctx.aujourdhui);
    var form = { creer_tache: true, prochaine_action_date: jour, prochaine_action_libelle: 'Confirmer la date du RDV' };
    plan.patch = prospectPatchEtape('RDV planifié', form);
    plan.tache = prospectTachePayload(contact, 'RDV planifié', form, contact.responsable || ctx.responsable);
  } else if (e.etape === 'Perdu') {
    plan.patch = prospectPatchEtape('Perdu', { motif_perte: e.motif_perte, motif_perte_precision: precision });
    plan.fermeTaches = true;
  } else if (e.etape === 'Ne pas recontacter') {
    plan.patch = prospectPatchEtape('Ne pas recontacter', { motif_perte_precision: precision || ('Demande en campagne ' + (ctx.campagne || '')) });
    plan.fermeTaches = true;
  }
  var bouge = plan.patch && plan.patch.etape_prospect !== prospectEtapeOuDefaut(contact);
  plan.detail = base + (bouge ? ' · étape → ' + plan.patch.etape_prospect : '');
  return plan;
}
```

- [ ] **Étape 5 : relancer toute la suite app**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline && node --test tests/*.test.mjs && node tests/check-babel.mjs`
Attendu : tout passe (9 tests dans `campagne-sortie.test.mjs`), puis `OK babel`.

- [ ] **Étape 6 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline add index.html tests/campagne-sortie.test.mjs tests/fixtures/campagne-sortie-cas.json
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline commit -m "feat(campagnes): correspondance des sorties de campagne, jeu de cas commun avec le MCP"
```

---

## Tâche 11 : app, cockpit Jules (sortie manuelle appliquée, motif « Ne plus contacter », fiche liée cliquable)

**Files :**
- Modify : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline/index.html` (fonction racine ajoutée, `julesActions.arreterSuivi`, `JULES_RAISONS_SORTIE`, `JulesDetail`, `TabJules`, rendu de l'app)
- Create : `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline/tests/campagne-cockpit.test.mjs`

**Interfaces :**
- Consumes : tâche 10 (`campagneEstProspection`, `campagneSortiePlan`) ; existants : `sb` (client Supabase global), `getToday()`, `toast(msg, type)`, `prospectAnnulerTachesOuvertes(contactId) -> { error, annulees }`, `navToContact(id)` (racine de l'app : ouvre l'onglet Prospects sur la fiche), `JULES_NOIR`, `agir(id, fn)` dans `TabJules`.
- Produces : fonction racine `async function julesSortieCampagneCrm(s, motif, mission, responsable, precision) -> plan|null` ; `julesActions.arreterSuivi(s, raison, mission, responsable)` ; motif `{cle:'npc', label:'Ne plus contacter, à sa demande'}` dans `JULES_RAISONS_SORTIE` ; props `TabJules({ ..., onNavToContact })` et `JulesDetail({ ..., onNavToContact })` ; bouton « Fiche CRM » sur une séquence qui a un `contact_id`.

Contexte : spec §6.4. Aujourd'hui `TabJules` passe `arreterSuivi:s=>agir(s.id,()=>julesActions.arreterSuivi(s))` : la raison choisie dans la modale est PERDUE (le motif retombe toujours sur « autre »). On corrige en passant raison, mission et responsable. La séquence est sortie AVANT l'écriture CRM ; un échec CRM ne l'annule pas, il s'affiche en toast d'erreur. Les séquences sont lues en `select('*')` par `useJulesData` : `contact_id` arrive sans rien changer. Le bouton reprend le style brutaliste (bordure 2px, `borderRadius: 0`, `Outfit`, majuscules, `letterSpacing: '0.03em'`).

- [ ] **Étape 1 : écrire le test qui échoue**

Créer `tests/campagne-cockpit.test.mjs` :

```js
// tests/campagne-cockpit.test.mjs : la sortie manuelle d'une personne depuis le cockpit Jules applique
// au CRM la correspondance des campagnes de prospection. julesSortieCampagneCrm est extraite d'index.html
// et jouee contre un faux client Supabase ; le cablage de l'ecran est verifie sur le source.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

process.env.TZ = 'Europe/Paris';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nasync function ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nconst ${nom} ?= ?[^\\n]*;\\n`),
                    new RegExp(`\\nconst ${nom} = \\[[\\s\\S]*?\\n\\];\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['DEFAULT_TASK_TIME', 'combineDT', 'PROSPECT_ETAPES', 'PROSPECT_ETAPES_ACTIVES', 'PROSPECT_ETAPES_SORTIE',
              'prospectEtapeOuDefaut', 'prospectEtapeRequiert', 'prospectTacheLibelle', 'prospectTacheEcheance',
              'prospectReveilPreset', 'prospectPatchEtape', 'prospectTachePayload', 'prospectAnnulerTachesOuvertes',
              'CAMPAGNE_MOTIF_PERTE_PROFIL', 'CAMPAGNE_LIBELLES_SORTIE', 'campagneEstProspection', 'campagneEffetSortie',
              'campagneJourOuvreSuivant', 'campagneSortiePlan', 'julesSortieCampagneCrm', 'JULES_RAISONS_SORTIE'];
const SRC = NOMS.map(extrait).join('\n');
const charge = (sb) => new Function('sb', 'getToday', `${SRC}\nreturn { julesSortieCampagneCrm, JULES_RAISONS_SORTIE };`)(sb, () => '2026-09-29');

// Faux client Supabase : from(t).select().eq().like().in(), update(), insert(), maybeSingle(), await.
function fauxSb(tables) {
  const appels = [];
  const sb = { from(table) {
    appels.push(table);
    const rows = () => (tables[table] = tables[table] || []);
    const filtres = []; let op = 'select', valeur = null, unique = false;
    const run = () => {
      const hit = rows().filter(r => filtres.every(f => f(r)));
      if (op === 'insert') { rows().push({ ...valeur }); return { data: [valeur], error: null }; }
      if (op === 'update') { hit.forEach(r => Object.assign(r, valeur)); return { data: hit, error: null }; }
      return { data: unique ? (hit[0] || null) : hit, error: null };
    };
    const q = {
      select() { return q; },
      eq(k, v) { filtres.push(r => String(r[k]) === String(v)); return q; },
      like(k, p) { const re = new RegExp('^' + p.split('%').map(s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('.*') + '$'); filtres.push(r => re.test(String(r[k]))); return q; },
      in(k, vs) { filtres.push(r => vs.map(String).includes(String(r[k]))); return q; },
      update(v) { op = 'update'; valeur = v; return q; },
      insert(v) { op = 'insert'; valeur = v; return q; },
      maybeSingle() { unique = true; return Promise.resolve(run()); },
      then(res, rej) { return Promise.resolve(run()).then(res, rej); },
    };
    return q;
  } };
  return { sb, appels, tables };
}
const PROSPECTION = { id: 'M1', titre: 'Prospection DSI Lyon', kind: 'campagne', config: { preset: 'prospection' } };
const JEAN = (etape, statut = 'Prospect') => ({ id: 7, prenom: 'Jean', nom: 'DUPONT', statut, responsable: 'Nicolas Serradeil', etape_prospect: etape });
const SEQ = { id: 'S1', mission_id: 'M1', target_label: 'Jean Dupont', contact_id: 7 };

test('refus : la fiche liee passe En veille a 6 mois et une ligne d historique est ecrite', async () => {
  const f = fauxSb({ contacts: [JEAN('Contacté')] });
  const plan = await charge(f.sb).julesSortieCampagneCrm(SEQ, 'refus', PROSPECTION, 'Nicolas Serradeil', '');
  assert.equal(plan.effet.etape, 'En veille');
  assert.equal(f.tables.contacts[0].etape_prospect, 'En veille');
  assert.equal(f.tables.contacts[0].prochaine_action_date, '2027-03-29T09:00:00+02:00');
  assert.deepEqual(f.tables.historique_actions, [{ id_prospect: 7, date: '2026-09-29', type_action: 'LinkedIn',
    details: 'Campagne Prospection DSI Lyon : refus (sortie par Nicolas Serradeil) · étape → En veille', responsable: 'Nicolas Serradeil' }]);
});

test('ne plus contacter : Ne pas recontacter pose directement (Nicolas decide) et taches de prospection annulees', async () => {
  const f = fauxSb({ contacts: [JEAN(null, 'Client')], taches: [{ id: 'tw_prospect_7_1', contact_id: 7, statut: 'en_cours' }] });
  await charge(f.sb).julesSortieCampagneCrm(SEQ, 'npc', PROSPECTION, 'Nicolas Serradeil', 'a demande a ne plus etre sollicite');
  assert.equal(f.tables.contacts[0].etape_prospect, 'Ne pas recontacter');
  assert.equal(f.tables.contacts[0].motif_perte_precision, 'a demande a ne plus etre sollicite');
  assert.equal(f.tables.taches[0].statut, 'annule');
});

test('converti : tache Confirmer la date du RDV creee, sauf si une tache de prospection est deja ouverte', async () => {
  const f = fauxSb({ contacts: [JEAN('Contacté')] });
  await charge(f.sb).julesSortieCampagneCrm(SEQ, 'converti', PROSPECTION, 'Nicolas Serradeil', '');
  assert.equal(f.tables.taches.length, 1);
  assert.equal(f.tables.taches[0].titre, 'Confirmer la date du RDV : Jean DUPONT');
  const g = fauxSb({ contacts: [JEAN('Contacté')], taches: [{ id: 'tw_prospect_7_1', contact_id: 7, statut: 'en_cours' }] });
  await charge(g.sb).julesSortieCampagneCrm(SEQ, 'converti', PROSPECTION, 'Nicolas Serradeil', '');
  assert.equal(g.tables.taches.length, 1);
});

test('hors campagne de prospection, sans fiche liee, ou doublon : aucune lecture ni ecriture', async () => {
  const f = fauxSb({ contacts: [JEAN('Contacté')] });
  const api = charge(f.sb);
  assert.equal(await api.julesSortieCampagneCrm(SEQ, 'refus', { ...PROSPECTION, config: {} }, 'Nicolas Serradeil', ''), null);
  assert.equal(await api.julesSortieCampagneCrm({ ...SEQ, contact_id: null }, 'refus', PROSPECTION, 'Nicolas Serradeil', ''), null);
  assert.equal(f.appels.length, 0);
  assert.equal(await api.julesSortieCampagneCrm(SEQ, 'doublon', PROSPECTION, 'Nicolas Serradeil', ''), null);
  assert.equal((f.tables.historique_actions || []).length, 0);
  assert.equal(f.tables.contacts[0].etape_prospect, 'Contacté');
});

test('le motif Ne plus contacter existe dans la modale de sortie', () => {
  const { JULES_RAISONS_SORTIE } = charge(fauxSb({}).sb);
  const npc = JULES_RAISONS_SORTIE.find(r => r.cle === 'npc');
  assert.ok(npc, 'motif npc absent');
  assert.equal(npc.label, 'Ne plus contacter, à sa demande');
  assert.doesNotMatch(npc.label, /[\u2013\u2014]/);
});

test('cablage : la raison et la mission arrivent jusqu a arreterSuivi, la fiche liee est cliquable', () => {
  assert.match(html, /async arreterSuivi\(s, raison, mission, responsable\) \{/);
  assert.match(html, /arreterSuivi:\(s,raison,mission\)=>agir\(s\.id,\(\)=>julesActions\.arreterSuivi\(s,raison,mission,profile&&profile\.nom\)\),/);
  assert.match(html, /actions\.arreterSuivi\(sq, raison, mission\); \}\}\/>\}/);
  assert.match(html, /const plan = await julesSortieCampagneCrm\(s, motif, mission, responsable, texte\);/);
  assert.match(html, /function TabJules\(\{ profile, prefs, deepLink, onNavToContact \}\) \{/);
  assert.match(html, /<TabJules profile=\{profile\} prefs=\{prefs\} deepLink=\{julesDeepLink\} onNavToContact=\{navToContact\}\/>/);
  assert.match(html, /function JulesDetail\(\{ missionId, data, onClose, actions, occupe, discuter, onNavToContact \}\) \{/);
  assert.match(html, /\{s\.contact_id&&onNavToContact&&\(/);
  assert.match(html, /onClick=\{\(\)=>\{ onClose\(\); onNavToContact\(s\.contact_id\); \}\}/);
});

test('aucun tiret cadratin ni demi-cadratin dans le code ajoute', () => {
  assert.doesNotMatch(extrait('julesSortieCampagneCrm'), /[\u2013\u2014]/);
  const i = html.indexOf('// Campagne de prospection (SPEC_campagnes_prospection_etapes.md) : la sortie applique');
  const j = html.indexOf("'error');", i);
  assert.ok(i > 0 && j > i, 'bloc ajoute a arreterSuivi introuvable');
  assert.doesNotMatch(html.slice(i, j), /[\u2013\u2014]/);
});
```

- [ ] **Étape 2 : le lancer et le voir échouer**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline && node --test tests/campagne-cockpit.test.mjs`
Attendu : `Error: julesSortieCampagneCrm introuvable dans index.html` (et l'échec des tests de câblage).

- [ ] **Étape 3 : ajouter la fonction d'écriture**

Dans `index.html`, insérer IMMÉDIATEMENT AVANT la ligne `const TYPES_ACTION     = ['Tel','Mail envoyé','Mail reçu','RDV','LinkedIn','Note interne','Autre'];` (donc juste après le bloc de la tâche 10) :

```js
// Sortie manuelle d'une personne depuis le cockpit Jules, campagne de prospection : applique a la
// fiche LIEE (s.contact_id) le plan de campagneSortiePlan. Aucune recherche ni creation de fiche ici :
// c'est le MCP qui lie et cree. Rend le plan applique, ou null si rien n'etait a faire. Leve une
// erreur si une ecriture echoue (l'appelant la signale, la sequence reste sortie).
async function julesSortieCampagneCrm(s, motif, mission, responsable, precision) {
  if (!campagneEstProspection(mission) || !s || !s.contact_id) return null;
  var lu = await sb.from('contacts').select('id,prenom,nom,statut,responsable,etape_prospect')
    .eq('id', parseInt(s.contact_id)).maybeSingle();
  if (lu.error) throw new Error(lu.error.message);
  if (!lu.data) return null;
  var c = lu.data;
  var qui = responsable || c.responsable;
  var plan = campagneSortiePlan(motif, c, { campagne: mission.titre, aujourdhui: getToday(), responsable: qui, precision: precision || null });
  if (!plan.detail) return null;
  if (plan.patch) {
    var maj = await sb.from('contacts').update(plan.patch).eq('id', c.id);
    if (maj.error) throw new Error(maj.error.message);
  }
  if (plan.fermeTaches) {
    var fermees = await prospectAnnulerTachesOuvertes(c.id);
    if (fermees.error) throw new Error(fermees.error.message);
  }
  if (plan.tache) {
    var lues = await sb.from('taches').select('id,statut').eq('contact_id', c.id).like('id', 'tw_prospect_%');
    if (lues.error) throw new Error(lues.error.message);
    var ouvertes = (lues.data || []).filter(function(t){ return t.statut !== 'fait' && t.statut !== 'annule'; });
    if (ouvertes.length === 0) {
      var cree = await sb.from('taches').insert(plan.tache);
      if (cree.error) throw new Error(cree.error.message);
    }
  }
  var h = await sb.from('historique_actions').insert({ id_prospect: c.id, date: getToday(), type_action: 'LinkedIn',
    details: plan.detail, responsable: qui });
  if (h.error) throw new Error(h.error.message);
  return plan;
}
```

- [ ] **Étape 4 : `julesActions.arreterSuivi`**

4a. Remplacer la ligne `  async arreterSuivi(s, raison) {` par `  async arreterSuivi(s, raison, mission, responsable) {`.

4b. À la fin de cette même méthode, remplacer :

```js
      message: s.target_label + ' — ' + libelle + (texte ? ' : ' + texte : '')});
  },
```

par (la première ligne est inchangée, c'est l'ancrage) :

```js
      message: s.target_label + ' — ' + libelle + (texte ? ' : ' + texte : '')});
    // Campagne de prospection (SPEC_campagnes_prospection_etapes.md) : la sortie applique a la fiche
    // liee la meme correspondance que le MCP. La sequence est deja sortie : un echec CRM ne l'annule
    // pas, il est signale.
    try {
      const plan = await julesSortieCampagneCrm(s, motif, mission, responsable, texte);
      if (plan && plan.detail) toast('Fiche CRM mise à jour : ' + plan.detail);
    } catch (e) {
      toast('Sortie enregistrée, mais la fiche CRM n\'a pas été mise à jour : ' + e.message, 'error');
    }
  },
```

- [ ] **Étape 5 : motif « Ne plus contacter »**

Dans `const JULES_RAISONS_SORTIE = [`, juste après la ligne `  {cle:'refus',    label:'Refus de la personne',             variant:'danger'},`, ajouter :

```js
  {cle:'npc',      label:'Ne plus contacter, à sa demande',  variant:'danger'},
```

- [ ] **Étape 6 : câblage de la raison, de la mission et de la fiche**

6a. Dans `JulesDetail`, modale de sortie, remplacer `actions.arreterSuivi(sq, raison); }}/>}` par `actions.arreterSuivi(sq, raison, mission); }}/>}`.

6b. Remplacer `function JulesDetail({ missionId, data, onClose, actions, occupe, discuter }) {` par `function JulesDetail({ missionId, data, onClose, actions, occupe, discuter, onNavToContact }) {`.

6c. Dans la rangée d'une séquence de `JulesDetail`, remplacer :

```jsx
                    {deplie?'▾ masquer le détail':'▸ voir le détail'}
                  </button>
                  {discuter&&<JulesSlackBtn small label="Discuter"
                    onClick={()=>discuter({kind:'free', ref_id:s.id,
```

par :

```jsx
                    {deplie?'▾ masquer le détail':'▸ voir le détail'}
                  </button>
                  {/* Fiche CRM liee (SPEC_campagnes_prospection_etapes.md §6.4) : posee par le MCP au
                      premier vrai contact d'une campagne de prospection. Un clic ouvre la fiche. */}
                  {s.contact_id&&onNavToContact&&(
                    <button type="button" onClick={()=>{ onClose(); onNavToContact(s.contact_id); }}
                      title="Ouvrir la fiche CRM liée à cette personne"
                      style={{background:'none', border:'2px solid '+JULES_NOIR, borderRadius:0, padding:'4px 8px', cursor:'pointer',
                              fontFamily:'Outfit, sans-serif', fontSize:11, fontWeight:700, color:JULES_NOIR,
                              textTransform:'uppercase', letterSpacing:'0.03em', minHeight:32}}>
                      Fiche CRM
                    </button>
                  )}
                  {discuter&&<JulesSlackBtn small label="Discuter"
                    onClick={()=>discuter({kind:'free', ref_id:s.id,
```

6d. Remplacer `function TabJules({ profile, prefs, deepLink }) {` par `function TabJules({ profile, prefs, deepLink, onNavToContact }) {`.

6e. Dans `TabJules`, remplacer `{detailId&&<JulesDetail missionId={detailId} data={J.data} onClose={()=>setDetailId(null)}` par `{detailId&&<JulesDetail missionId={detailId} data={J.data} onClose={()=>setDetailId(null)} onNavToContact={onNavToContact}` (le reste de la balise est inchangé).

6f. Dans les `actions` passées à `JulesDetail`, remplacer `arreterSuivi:s=>agir(s.id,()=>julesActions.arreterSuivi(s)),` par `arreterSuivi:(s,raison,mission)=>agir(s.id,()=>julesActions.arreterSuivi(s,raison,mission,profile&&profile.nom)),`.

6g. Dans le rendu des onglets de l'app, remplacer `<TabJules profile={profile} prefs={prefs} deepLink={julesDeepLink}/>` par `<TabJules profile={profile} prefs={prefs} deepLink={julesDeepLink} onNavToContact={navToContact}/>`.

Chacune de ces chaînes est unique dans `index.html` (vérifié) ; si un remplacement ne trouve pas sa chaîne, s'arrêter et le signaler plutôt que d'improviser.

- [ ] **Étape 7 : relancer toute la suite app**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline && node --test tests/*.test.mjs && node tests/check-babel.mjs`
Attendu : tout passe (7 tests dans `campagne-cockpit.test.mjs`), puis `OK babel`.

- [ ] **Étape 8 : vérification visuelle locale**

Commande : `cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline && python3 -m http.server 8765` puis ouvrir `http://localhost:8765`, onglet Jules, une campagne : la modale « Sortir » propose « Ne plus contacter, à sa demande » ; une séquence avec `contact_id` montre le bouton FICHE CRM. Arrêter le serveur. Ne rien pousser (la mise en ligne est la tâche 13).

- [ ] **Étape 9 : commit**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline add index.html tests/campagne-cockpit.test.mjs
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline commit -m "feat(jules): la sortie manuelle d'une campagne de prospection met la fiche a jour, motif Ne plus contacter, fiche liee cliquable"
```

---

## Tâche 12 : consigne Jules `routines/campagne-boucle.md`

**Files :**
- Modify : `/Users/nicolasserradeil/Pro/Jules/routines/campagne-boucle.md` (ce fichier SEUL)

**Interfaces :**
- Consumes : l'outil `agent_sequence_upsert` de la tâche 7 (paramètres `evenement`, `motif_sortie`, `rdv_date`, `canal`, `prenom`, `nom`, `societe`, `linkedin_url`, `contact_id`, `nouvelle_fiche`) et le comportement des tâches 6 et 8.
- Produces : la consigne que suivent les workers `campagne.lire`, `campagne.envoyer`, `campagne.alimenter`.

Contexte : spec §6.5, « passer evenement, motif_sortie et l'identité de la personne à agent_sequence_upsert. Rien d'autre à faire côté CRM ». Le dépôt Jules a de nombreux changements sans rapport, non commités : n'en toucher aucun, ne committer QUE ce fichier (d'où `commit -- <chemin>`). Le texte ajouté ne contient aucun tiret cadratin ; le texte existant du fichier n'est pas réécrit.

- [ ] **Étape 1 : écrire la vérification qui échoue**

Commande :

```bash
python3 - <<'EOF'
import re
t = open('/Users/nicolasserradeil/Pro/Jules/routines/campagne-boucle.md', encoding='utf-8').read()
i = t.index('## Le CRM suit tout seul')
j = t.index('\n## ', i + 5)
sec = t[i:j]
assert not re.search('[\u2013\u2014]', sec), 'tiret cadratin dans la section'
for k in ['acceptee', 'message_envoye', 'relance_envoyee', 'reponse', 'conversion', 'mail_envoye', 'appel_passe',
          'sortie', 'motif_sortie', 'linkedin_url', 'nouvelle_fiche', 'contact_id']:
    assert k in sec, k
k = t.index('En campagne de prospection, la tâche « Répondre à X »')
assert t.index('## Le CRM suit tout seul') < t.index('## `campagne.lire`')
print('OK')
EOF
```

Attendu avant modification : `ValueError: substring not found` (la section n'existe pas encore).

- [ ] **Étape 2 : ajouter la section**

Insérer le texte suivant IMMÉDIATEMENT AVANT la ligne de titre ``## `campagne.lire` (2 à 3 fois/jour, `needs_browser`)`` (occurrence unique), en laissant ce titre intact juste après le texte inséré :

```markdown
## Le CRM suit tout seul : campagnes de prospection (MCP 8.27.0)

> Spec : `SPECS_CRM/SPEC_campagnes_prospection_etapes.md` (repo CRM). Règle Nicolas du 29/09.

Dans une campagne dont `config.preset = "prospection"`, et SEULEMENT celle-là (une campagne
sans `preset`, ou en `recrutement`, ne touche jamais au CRM), `agent_sequence_upsert` tient la
fiche Prospect à jour : il la lie ou la crée à la première vraie tentative de contact, fait
avancer son étape (sans jamais la faire reculer), écrit une ligne d'historique par événement
et crée la tâche « Répondre à X » sur une réponse positive. Pour une personne de campagne de
prospection, je ne fais donc AUCUN `crm_create_contact`, aucun `crm_update_contact` d'étape,
aucun `crm_log_action` : ce serait un doublon.

Ce que je passe EN PLUS à chaque `agent_sequence_upsert` d'une campagne de prospection :

| Moment | `evenement` | En plus |
|---|---|---|
| invitation acceptée (`campagne.lire` étape 2, et l'étape 2bis des ajouts spontanés) | `acceptee` | `prenom`, `nom`, `societe`, `linkedin_url` lus sur le profil RÉEL |
| premier message envoyé (`campagne.envoyer`, étape 2) | `message_envoye` | |
| relance envoyée (`campagne.envoyer`, étape 3 ou 4) | `relance_envoyee` | si c'est la dernière, le MCP la compte comme « fin des relances sans réponse » |
| réponse lue (`campagne.lire` étape 4) | `reponse` | `sentiment` : `positif`, `neutre` ou `negatif` |
| RDV pris | `conversion` | `rdv_date` si je la connais (2026-10-06T14:30, heure de Paris) |
| premier mail envoyé hors LinkedIn | `mail_envoye` | `canal: "mail"` et l'identité |
| premier appel passé | `appel_passe` | `canal: "appel"` et l'identité |
| sortie d'une personne | `sortie` | `motif_sortie` : `converti`, `refus`, `silence`, `profil`, `doublon`, `npc` (« ne me contactez plus »), `autre` |

Règles :
- L'identité (`prenom`, `nom`, `societe`, `linkedin_url`) est OBLIGATOIRE au premier contact :
  sans elle, le MCP ne crée pas la fiche et le dit (« identité manquante »). Je la passe dès que
  je la connais, ça ne coûte rien.
- Sans `evenement`, le MCP le déduit du changement d'état (étape, statut, sentiment). C'est un
  filet, pas la règle : je passe `evenement` explicitement.
- Je LIS les lignes `CRM : ...` de la réponse et je les reprends dans le résumé de ma tâche.
  Une ligne `⚠️ CRM non mis à jour` ne bloque rien (la séquence est écrite) : je ne réessaie pas
  en boucle, je la cite dans `agent_task_done` pour que le builder la voie.
- « Ne pas recontacter », « Perdu » et l'homonyme dans une autre société arrivent TOUT SEULS au
  parapheur : le MCP dépose la carte et une tâche `libre` en attente de GO qui porte l'appel
  exact à faire (`crm_update_contact`, ou `agent_sequence_upsert` avec `contact_id` ou
  `nouvelle_fiche` pour un homonyme). Je ne crée pas de seconde carte. Quand cette tâche me
  revient après le GO, j'exécute l'appel tel qu'il est écrit, rien de plus.
- Réponse positive : la tâche « Répondre à X » (jour ouvré suivant, 09h00, responsable de la
  fiche) est créée par le MCP. Je ne crée PAS de tâche CRM en plus ; l'alerte immédiate à
  Nicolas (`bin/jules-say.sh`) reste due.
- Une personne dont la fiche est en « Ne pas recontacter » n'entre jamais dans une campagne de
  prospection : le MCP refuse la séquence (réponse 🚫). Si la fiche y passe pendant la campagne,
  le MCP arrête la séquence tout seul. Dans les deux cas, je n'insiste pas.
```

- [ ] **Étape 3 : ajuster l'étape 4 de `campagne.lire`**

Remplacer ces quatre lignes :

```markdown
   - **Sur sentiment positif : alerte immédiate à Nicolas**, hors brief (spec § 6) — via
     `bin/jules-say.sh` (jamais silencieux jusqu'au brief du lendemain), puis
     `agent_approval_create` si une suite demande une décision de Nicolas (ex. quel angle
     de RDV proposer), ou une tâche CRM si la suite est une relance datée.
```

par :

```markdown
   - **Sur sentiment positif : alerte immédiate à Nicolas**, hors brief (spec § 6), via
     `bin/jules-say.sh` (jamais silencieux jusqu'au brief du lendemain), puis
     `agent_approval_create` si une suite demande une décision de Nicolas (ex. quel angle
     de RDV proposer). En campagne de prospection, la tâche « Répondre à X » est déjà créée
     par `agent_sequence_upsert` (section « Le CRM suit tout seul ») : pas de tâche CRM en
     plus. Hors prospection, une tâche CRM si la suite est une relance datée.
```

- [ ] **Étape 4 : relancer la vérification**

Même commande qu'à l'étape 1. Attendu : `OK`.

- [ ] **Étape 5 : commit de ce seul fichier**

```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/Jules commit -m "contenu(campagnes): le CRM suit tout seul, parametres a passer a agent_sequence_upsert" -- routines/campagne-boucle.md
/usr/bin/git -C /Users/nicolasserradeil/Pro/Jules show --stat HEAD
```

Attendu : le commit ne contient que `routines/campagne-boucle.md`.

---

## Tâche 13 (manuelle, propriétaire seulement) : mise en service, ordre du §8

Pas d'agent pour cette tâche : chaque étape touche la production. Nicolas (ou le builder sous son GO explicite) la déroule dans l'ordre, et ne passe à l'étape suivante que si la précédente est vérifiée.

**Files :** aucun fichier de code. Actions sur Supabase, sur le source MCP en service, sur `main` de l'app, et sur le bundle `.mcpb`.

**Interfaces :** Consumes : les tâches 1 à 12 terminées et vertes. Produces : MCP 8.27.0 en service, colonne `contact_id` en base, app en ligne.

- [ ] **Étape 1 : migration 54 (avant tout le reste)**
Coller `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline/db/54_agent_sequences_contact_id.sql` dans le SQL Editor Supabase, exécuter, puis exécuter les deux requêtes de contrôle en bas du fichier. Attendu : une ligne `contact_id | bigint`, et une contrainte étrangère avec `confdeltype = 'n'`. « SQL passé » ne suffit pas : c'est le contrôle qui fait foi.

- [ ] **Étape 2 : MCP 8.27.0, bascule du source en service**
```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-wt-campagnes log --oneline main..feat/campagnes-prospection
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-src status --short
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-src merge --ff-only feat/campagnes-prospection
cd /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-src && node --test tests/*.test.mjs && node --check server/index.mjs
```
Le `status` doit être propre avant la fusion (sinon s'arrêter). La fusion change le code que chargent les NOUVELLES sessions (workers de l'ordonnanceur compris) ; une session déjà ouverte garde l'ancien code. Ouvrir une session neuve et appeler `crm_version` : attendu `v8.27.0`.

- [ ] **Étape 3 : `.mcpb` pour Cowork**
```bash
T=$(mktemp -d)
unzip -q /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-v8.26.0.mcpb -d "$T"
cp /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-src/manifest.json "$T/"
cp /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-src/server/*.mjs "$T/server/"
mkdir -p "$T/tests" && cp -R /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-src/tests/. "$T/tests/"
(cd "$T" && zip -rq /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-v8.27.0.mcpb manifest.json server tests)
mv /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-v8.26.0.mcpb /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/_archive-mcpb/
ls /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/*.mcpb
```
Attendu : UN SEUL `.mcpb` à la racine (`upgrade-crm-v8.27.0.mcpb`), qui contient bien les trois nouveaux modules (`unzip -l ... | grep -E "campagne-rules|campagne-crm|contact-norm"`). L'upload dans Cowork est un geste de Nicolas.

- [ ] **Étape 4 : app en ligne**
Servir le worktree en local (`python3 -m http.server 8765` dans `/Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2/.claude/worktrees/prospects-pipeline`), faire valider par Nicolas l'onglet Jules (motif « Ne plus contacter », bouton FICHE CRM), puis :
```bash
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2 status --short
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2 merge --ff-only feat/campagnes-prospection
/usr/bin/git -C /Users/nicolasserradeil/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-lyon-V2 push origin main
```
Pousser `main` = production immédiate (GitHub Pages) : seulement après le OK de Nicolas.

- [ ] **Étape 5 : consigne Jules**
Déjà sur `main` du dépôt Jules (tâche 12). Vérifier que la prochaine tâche `campagne.lire` d'une campagne de prospection passe `evenement` et l'identité (journal de la tâche, lignes `CRM :` dans son résumé).

- [ ] **Étape 6 : recette (spec §7), sur une vraie campagne de prospection**
1. Une invitation acceptée crée la fiche en Contacté, liée à la séquence (bouton FICHE CRM visible), avec une ligne « Campagne <nom> : invitation acceptée · étape → Contacté ».
2. Une réponse positive la passe En discussion, avec la tâche « Répondre à X » le jour ouvré suivant à 09h00 dans le calendrier de Nicolas.
3. Un refus la met En veille, réveil à 6 mois, 09h00.
4. Un « Ne me contactez plus » arrive au parapheur et ne change rien avant le GO ; au GO, la fiche passe en « Ne pas recontacter ».
5. Une personne déjà au CRM (même profil LinkedIn) n'est pas créée une seconde fois : la réponse dit « fiche liée ».
6. Une campagne en recrutement ou sans preset ne touche aucune fiche.

---

## Self-review

**Couverture de la spec :**

| Section de la spec | Tâche(s) |
|---|---|
| §1 Besoin, critère de succès (fiche liée à la bonne étape, pas de doublon, pas de NPC/Perdu sans GO) | 6, 7, 8 ; recette 13.6 |
| §2 Périmètre : preset prospection explicite, dehors scan et recrutement, séquences antérieures | 2 (`estCampagneProspection`), 7 (tests sans preset, recrutement ; cibles `externe`/`contact_crm` seules) ; séquences antérieures hors plan (décision de la spec) |
| §3 Création au premier vrai contact | 3 (`creer`), 6 (création), décision 3 |
| §3 Vérification avant création (lien, LinkedIn normalisé, prénom + nom + société), homonyme, création (Prospect, Contacté, responsable, compte) | 5 (`rechercheFiche`, `creeFicheProspect`), 8 (question d'homonyme) |
| §3 Contact existant non Prospect (statut et étape intouchés, historique, tâche, NPC protégé) | 3 (table, colonne Client ; fixture), 6 (test Client) |
| §4 Table événement vers CRM | 3 (table complète en test), 6 |
| §4 Règles transverses : pas de recul, sorties sur étapes actives, NPC l'emporte, réveil 6 mois décalé, prochaine action d'un Contacté sans tâche, « Répondre à X » 09h00 `tw_prospect_` sans doublon, RDV sans date | 2 (dates), 3, 6, 7 (garde NPC à l'ajout et en cours) |
| §4 Autonomie (Contacté, En discussion, RDV planifié, En veille seuls ; NPC, Perdu, homonyme au GO) | 3 (`go`), 8 |
| §5 Traçage (une ligne, type selon le canal, détail, responsable = propriétaire) | 2 (`libelleEvenement`, `typeHistorique`), 6 |
| §6.1 Migration 54 | 1 |
| §6.2 Module de règles pur, testé comme `prospect-rules.mjs` | 2, 3 |
| §6.3 `agent_sequence_upsert` : paramètres, déduction, réponse, échec non bloquant, réutilisation (création de contact, garde-fous d'étape, dates décalées, approbations) | 4, 5, 6, 7, 8 |
| §6.4 App : sortie manuelle, motif « Ne plus contacter », fiche cliquable, jeu de cas commun | 3 et 10 (fixture), 10, 11 |
| §6.5 Consigne Jules | 12 |
| §7 Tests unitaires et jeu de cas commun ; recette | 2, 3, 5 à 11 ; 13.6 |
| §8 Mise en service, dans l'ordre | 13 |

**Balayage des trous :** aucun « à définir », « comme la tâche N » ni nom non défini. Les chaînes « avant » des remplacements dans `index.mjs`, `agent-tools.mjs`, `index.html`, `manifest.json` et `campagne-boucle.md` ont été vérifiées uniques. La date de build (tâche 9) est donnée par une commande (`date +%F`), pas laissée en blanc.

**Cohérence des noms et des types :**
- `resoutEvenement` rend `{ type, motif, sentiment, canal, rdv_date }` (tâche 2) ; c'est la forme que lisent `effetCampagneSurProspect` (tâche 3), `ecritEffets` (tâche 6) et `contenuDemande` (tâche 8).
- `effetSortie` (MCP, tâche 3) et `campagneEffetSortie` (app, tâche 10) rendent la même forme `{ action, etape, motif_perte, reveil6m }`, vérifiée par le même fichier `campagne-sortie-cas.json`, identique dans les deux repos.
- `rechercheFiche` : paramètres `{ sequence, identite, contactIdExplicite, nouvelleFiche }` ; appelée ainsi par `ecritEffets` (tâche 6) et `refusNpc` (tâche 7). `appliqueEffetsCampagne(deps, ctx)` : `ctx.lien = { contact_id, nouvelle_fiche }` construit par `voletCrm` (tâche 7) à partir des paramètres `contact_id` et `nouvelle_fiche` de l'outil.
- `registerAgentTools(..., crm)` : `crm = { resolveCompteId, syncContactCompte, getAgenceFor, getAuthCaller }`, mêmes noms dans `index.mjs` (tâche 7) et dans les `deps` des tests (tâches 5 à 8).
- Libellés partagés MCP et app : `LIBELLES_SORTIE` et `CAMPAGNE_LIBELLES_SORTIE` ont les mêmes valeurs, donc un détail d'historique écrit par l'app (« Campagne X : refus (sortie par ...) ») est reconnu par le témoin d'idempotence du MCP (« Campagne X : refus* »).
- `contacts.id` est un `bigint` : FK de la 54 en `bigint`, `contact_id` de l'outil en `z.number()`, `parseInt` côté app.
