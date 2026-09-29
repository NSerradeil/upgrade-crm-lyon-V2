# SPEC : Les campagnes de prospection de Jules font avancer le pipeline des prospects
**CRM Upgrade Lyon V2 + MCP upgrade-crm + Jules** · Évolution
**Auteur :** Nicolas Serradeil + Claude
**Date :** 29/09/2026
**Dépend de :** `SPEC_prospects_pipeline_etapes.md` (en production depuis le 29/09)

---

## 1. Le besoin

Jules mène des campagnes (missions `kind = campagne`). Trois scénarios existent : **prospection**,
**scan** (plateformes) et **recrutement**. Dans une campagne de prospection, Jules invite, message,
relance et lit les réponses de décideurs sur LinkedIn. Aujourd'hui rien de tout ça n'atteint le CRM :
une personne en campagne n'est connue que par son profil LinkedIn, sa fiche contact n'existe pas ou
n'est pas liée, son étape de prospect ne bouge pas, rien n'est écrit dans l'historique.

**Objectif :** qu'une campagne de prospection tienne le pipeline à jour toute seule. Le commercial
ouvre l'onglet Prospects et voit, sans saisie, qui a été contacté, qui a répondu, qui a un RDV, qui
est en veille.

**Critère de succès :** sur une campagne de prospection en cours, chaque personne ayant accepté une
invitation (ou reçu un premier mail, ou un premier appel) a une fiche Prospect liée, à la bonne
étape, avec l'historique de la campagne ; aucune fiche en double n'a été créée ; aucun
« Ne pas recontacter » ni « Perdu » n'a été posé sans le GO de Nicolas.

## 2. Périmètre

- **Dedans :** les campagnes dont `config.preset = 'prospection'`, **explicitement**. Une campagne
  sans `preset` (la cadence retombe alors sur les valeurs de prospection, mais ce n'est pas une
  déclaration d'intention) ou en `recrutement` ne touche jamais au pipeline.
- **Dehors :** le scan (il suit des plateformes, pas des personnes) ; le recrutement (pas de
  Prospect, et Recruitee est un autre chantier) ; les séquences créées avant la mise en service
  (rattachables plus tard par une passe de ventilation, comme la migration 53).

## 3. Quand une fiche Prospect est créée

**Règle de Nicolas :** jamais à l'ajout dans la campagne, **seulement à la première vraie tentative
de contact**, pour qu'une fiche créée depuis une campagne démarre au minimum en « Contacté » :

- invitation LinkedIn **acceptée** (une invitation envoyée ne suffit pas) ;
- premier mail envoyé ;
- premier appel passé.

### Vérification avant création (obligatoire)

Dans cet ordre, on s'arrête au premier résultat :

1. la séquence porte déjà un lien vers une fiche (`agent_sequences.contact_id`) ;
2. une fiche a le même profil LinkedIn, comparé après normalisation (même normalisation que le MCP
   applique déjà aux URL LinkedIn) ;
3. une fiche a le même prénom, le même nom **et** la même société.

- Trouvée : on **lie** la séquence à cette fiche, on n'en crée pas.
- Même prénom et même nom mais **autre société** : on ne crée rien, on ne lie rien, on pose la
  question à Nicolas au parapheur (homonyme ou changement de poste).
- Rien trouvé : on crée la fiche, statut `Prospect`, étape `Contacté`, responsable = le
  propriétaire de la campagne, société rattachée au compte comme le fait déjà `crm_create_contact`.

### Contact existant qui n'est pas un Prospect

Client, Candidat, Consultant, Freelance : **on ne touche jamais à son statut ni à son étape**. On
écrit seulement la ligne d'historique, et la tâche « Répondre à X » sur une réponse positive.
Exception de protection : « Ne me contactez plus » donne lieu à la demande de GO comme pour un
Prospect (le refus doit être protégé quel que soit le statut).

## 4. Correspondance événement de campagne → CRM

| Événement | Fiche absente | Fiche Prospect existante | Autre statut |
|---|---|---|---|
| Invitation envoyée | rien | rien | rien |
| Invitation acceptée, 1er mail, 1er appel | **création** en Contacté, liée | Contacté si elle était en À contacter | historique |
| Message ou relance envoyé | sans objet | historique ; prochaine action = relance suivante | historique |
| Réponse positive | sans objet | **En discussion** + tâche « Répondre à X » | historique + tâche |
| RDV pris (conversion) | sans objet | **RDV planifié**, prochaine action = date du RDV | historique |
| Réponse neutre | sans objet | ne bouge pas, historique | historique |
| Refus (réponse négative) | sans objet | **En veille**, réveil à 6 mois | historique |
| Silence au bout des relances | sans objet | **En veille**, réveil à 6 mois | historique |
| « Ne me contactez plus » | sans objet | **GO au parapheur**, puis Ne pas recontacter | GO, puis Ne pas recontacter |
| Pas le bon profil | sans objet | **GO au parapheur**, puis Perdu, motif « Pas le bon interlocuteur » | rien |
| Doublon | sans objet | rien (la séquence est liée à la fiche existante) | rien |
| Invitation expirée (21 jours) | rien | rien | rien |

### Règles transverses

- **Une étape ne recule jamais** sous l'effet d'une campagne. L'ordre est celui des étapes actives
  du pipeline (À contacter < Contacté < En discussion < RDV planifié < Qualifié). Un prospect
  Qualifié qui reçoit une relance reste Qualifié.
- Les sorties (En veille, Perdu, Ne pas recontacter) ne s'appliquent qu'à une fiche en étape
  active. Un prospect déjà en veille qui refuse à nouveau voit son réveil repoussé à 6 mois ; un
  Perdu reste Perdu.
- **« Ne pas recontacter » l'emporte sur tout** : un contact dans cette étape n'est jamais ajouté à
  une campagne de prospection, et une campagne ne le fait plus bouger.
- **Réveil « En veille » :** 6 mois après l'événement, à 09h00 heure de Paris, stocké avec son
  décalage horaire explicite (jamais de date naïve).
- **Prochaine action d'un Contacté :** la date de la prochaine relance de la séquence, libellé
  « Relance campagne (Jules) ». **Pas de tâche CRM** : c'est Jules qui l'exécute, la todo de
  Nicolas ne porte que ce que lui seul peut faire.
- **Tâche « Répondre à X » :** assignée au responsable de la fiche, le jour ouvré suivant à 09h00,
  identifiant préfixé `tw_prospect_` (sa clôture dans l'app redemande l'étape, comme toute tâche de
  prospection). Pas de doublon si une tâche de prospection est déjà ouverte sur la fiche.
- **RDV pris sans date connue :** l'étape RDV planifié exige une prochaine action datée. Sans date
  de RDV transmise, la prochaine action est « Confirmer la date du RDV », le jour ouvré suivant à
  09h00, et une tâche CRM est créée pour le responsable.

### Autonomie (décision de Nicolas)

Jules déplace seul : Contacté, En discussion, RDV planifié, En veille.
**Passent par le GO de Nicolas, au parapheur :** Ne pas recontacter, Perdu, et le cas de l'homonyme
dans une autre société. Tant que le GO n'est pas donné, l'étape ne bouge pas ; la campagne, elle,
continue de s'arrêter normalement pour cette personne.

## 5. Traçage

Chaque événement de campagne concernant une fiche liée écrit **une** ligne dans
`historique_actions` : type selon le canal (`LinkedIn`, `Mail envoyé`, `Appel sortant`, `Mail reçu`
pour une réponse par mail), détail « Campagne <nom> : <événement> », suivi de « · étape → X » si
l'étape a bougé. Une seule ligne par événement, pour que la « dernière action » des cartes Prospect
reste lisible. Responsable = le propriétaire de la campagne.

## 6. Architecture

**Point de passage unique : l'outil MCP `agent_sequence_upsert`.** Jules l'appelle déjà à chaque
avancée de séquence. Après avoir écrit la séquence, et **seulement** pour une campagne
`preset = 'prospection'`, il applique la correspondance ci-dessus. Jules ne peut pas l'oublier : c'est
le même geste.

1. **Base, migration 54 :** `agent_sequences.contact_id`, lien optionnel vers `contacts.id` (même
   type que la clé de `contacts`), `on delete set null`, avec un index. Rien d'autre.
2. **MCP, module de règles pur** (à côté de `prospect-rules.mjs`, testé de la même façon) :
   - `effetCampagneSurProspect(evenement, contact, sequence)` : ce qu'un événement produit (créer,
     lier, étape cible, prochaine action, tâche, demande de GO, rien) ;
   - la recherche de fiche dans l'ordre du §3 ;
   - les garde-fous (pas de recul, Ne pas recontacter figé, statut non Prospect intouché).
3. **MCP, `agent_sequence_upsert` :**
   - nouveaux paramètres optionnels : `evenement` (`acceptee`, `message_envoye`, `relance_envoyee`,
     `reponse`, `conversion`, `mail_envoye`, `appel_passe`, `sortie`), `motif_sortie`
     (`converti`, `refus`, `silence`, `profil`, `doublon`, `npc`, `autre`), `rdv_date`, et
     l'identité de la personne (`prenom`, `nom`, `societe`, `linkedin_url`) pour la création ;
   - sans `evenement`, il est déduit du changement d'état de la séquence (étape, statut,
     sentiment), pour ne pas dépendre de la seule discipline du worker ;
   - la réponse à Jules dit ce qui a été fait côté CRM (fiche créée ou liée, étape, tâche, GO
     demandé) ;
   - **si l'écriture CRM échoue, la séquence reste écrite** et l'échec est signalé dans la
     réponse : le CRM ne bloque jamais une campagne ;
   - réutilise l'existant : création de contact et son anti-doublon, garde-fous d'étape
     (`valideEtapeProspect`, nettoyage), écriture des dates avec décalage, approbations
     (`agent_approval_create`).
4. **App, cockpit Jules :** la sortie manuelle d'une personne (converti, refus, pas le bon profil…)
   applique la même correspondance. Un motif « Ne plus contacter » est ajouté aux motifs de sortie.
   La fiche liée est cliquable depuis la séquence. Les règles existent donc deux fois (app et MCP),
   verrouillées par **un jeu de cas commun** lu par les deux suites de tests, comme pour le
   nettoyage d'étape.
5. **Jules, consigne `routines/campagne-boucle.md` :** passer `evenement`, `motif_sortie` et
   l'identité de la personne à `agent_sequence_upsert`. Rien d'autre à faire côté CRM.

## 7. Tests et recette

- **Unitaires (MCP) :** chaque ligne de la table du §4, pour une fiche absente, un Prospect à
  chaque étape, un Client ; la recherche de fiche (lien, LinkedIn normalisé, nom + société,
  homonyme dans une autre société) ; pas de recul ; Ne pas recontacter figé ; campagne
  `recrutement` ou sans `preset` sans aucun effet ; réveil à 6 mois avec décalage, cas été et
  hiver ; déduction de l'événement depuis l'état.
- **Jeu de cas commun** app / MCP pour la correspondance des sorties manuelles.
- **Recette** (sur une vraie campagne de prospection, après mise en service) : une invitation
  acceptée crée la fiche en Contacté ; une réponse positive la passe En discussion avec la tâche à
  09h00 ; un refus la met en veille à 6 mois ; un « Ne me contactez plus » arrive au parapheur et
  ne change rien avant le GO ; une personne déjà au CRM n'est pas créée une seconde fois.

## 8. Mise en service

1. Migration 54 (ajout de colonne, sans risque, à passer avant le déploiement du MCP).
2. MCP 8.27.0 : bascule du source en service, puis `.mcpb` pour Cowork.
3. App : push sur `main`.
4. Consigne Jules mise à jour.
