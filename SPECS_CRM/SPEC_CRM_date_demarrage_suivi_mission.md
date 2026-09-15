# SPEC — Nouveaux champs : Date de démarrage initiale & Date de dernier suivi

**Auteur :** Nicolas Serradeil
**Date :** 2026-03-20
**Version :** 1.0
**Périmètre :** CRM Upgrade — entités Mission et Contact (client)

---

## 1. Contexte & Besoin

Le CRM Upgrade ne permet pas actuellement de distinguer :
- la **date à laquelle un consultant a démarré sa mission chez un client** (date initiale d'entrée, indépendante des renouvellements de commande)
- la **date du dernier suivi de mission** réalisé par le commercial (contact avec le client référent ou le consultant pour suivi de mission)
- la **date du dernier suivi client** toutes missions confondues sur un compte client

Ces informations sont aujourd'hui dans le Tableau de Bord Excel (`Tableau_Bord_Lyon_2026.xlsx`, onglet `Régie`, colonnes `Date Entrée` et `Dernier suivi mission`) mais ne sont pas accessibles dans le CRM ni exploitables dans les outils MCP / Claude.

---

## 2. Champs à créer

### 2.1 Sur l'entité **Mission**

| Champ | Nom technique | Type | Editable | Description |
|---|---|---|---|---|
| Date de démarrage initiale | `date_demarrage_initiale` | `date` (YYYY-MM-DD) | ✅ Oui | Date d'entrée du consultant chez le client, au démarrage de la mission. Ne change pas lors d'un renouvellement de commande. |
| Date du dernier suivi mission | `date_dernier_suivi_mission` | `date` (YYYY-MM-DD) | ✅ Oui | Date du dernier suivi de mission réalisé (contact avec le client référent ou le consultant). Mise à jour auto à chaque action de type "Suivi de mission" loggée. |

### 2.2 Sur l'entité **Contact** (type client)

| Champ | Nom technique | Type | Editable | Description |
|---|---|---|---|---|
| Date du dernier suivi client | `date_dernier_suivi_client` | `date` (YYYY-MM-DD) | ✅ Oui | Date du dernier suivi réalisé sur ce contact client, toutes missions confondues. Mise à jour auto à chaque action de type "Suivi de mission" loggée sur une mission liée au contact. |

---

## 3. Règles métier

### 3.1 `date_demarrage_initiale` (Mission)
- Saisie manuelle à la création de la mission, ou via `crm_update_mission`.
- Ne doit **pas** être écrasée automatiquement lors de la mise à jour de la période de commande (`crm_update_mission_period`).
- Doit être **inférieure ou égale** à `date_debut` de la période courante.

### 3.2 `date_dernier_suivi_mission` (Mission)
- Mise à jour **automatiquement** à chaque appel de `crm_log_mission_action` avec `type_action = "Suivi de mission"` : la date de l'action devient la valeur du champ si elle est plus récente que la valeur actuelle.
- Peut aussi être mise à jour **manuellement** via `crm_update_mission`.
- Ne régresse jamais automatiquement (on ne remplace que si date_action > date_dernier_suivi_mission).

### 3.3 `date_dernier_suivi_client` (Contact)
- Mise à jour **automatiquement** à chaque `crm_log_mission_action` avec `type_action = "Suivi de mission"` : si la mission est associée à un contact client, la date est répercutée sur le contact si elle est plus récente.
- Peut aussi être mise à jour **manuellement** via `crm_update_contact` (champ : `dernier_suivi_client`).

---

## 4. Affichage

### 4.1 Fiche Mission (détail)
Afficher les deux nouveaux champs dans la section "Infos mission" :

```
Date de démarrage initiale : [date]
Date du dernier suivi mission : [date] — [nombre de jours depuis le dernier suivi] j
```

Ajouter un **indicateur visuel** sur le délai depuis le dernier suivi :
- 🟢 < 30 jours
- 🟡 30–60 jours
- 🔴 > 60 jours (ou jamais renseigné)

### 4.2 Fiche Contact (détail)
Afficher dans la section "Infos client" :

```
Dernier suivi client : [date] — [nombre de jours]
```

Même logique d'indicateur visuel (30 / 60 jours).

### 4.3 Vue Pipeline / Liste des missions
Ajouter les deux colonnes optionnelles (masquées par défaut, affichables) :
- `Date démarrage`
- `Dernier suivi` (avec indicateur coloré)

---

## 5. Changements API / MCP

### 5.1 `crm_get_mission` — **mise à jour**
Ajouter dans la réponse :
```json
{
  "date_demarrage_initiale": "YYYY-MM-DD | null",
  "date_dernier_suivi_mission": "YYYY-MM-DD | null"
}
```

### 5.2 `crm_update_mission` — **mise à jour**
Autoriser la modification des champs :
- `date_demarrage_initiale`
- `date_dernier_suivi_mission`

### 5.3 `crm_log_mission_action` — **mise à jour**
Si `type_action == "Suivi de mission"` :
1. Mettre à jour `date_dernier_suivi_mission` sur la mission si `date_action` > valeur actuelle.
2. Mettre à jour `date_dernier_suivi_client` sur le contact client associé à la mission si `date_action` > valeur actuelle.

### 5.4 `crm_get_contact` — **mise à jour**
Ajouter dans la réponse :
```json
{
  "date_dernier_suivi_client": "YYYY-MM-DD | null"
}
```

### 5.5 `crm_update_contact` — **mise à jour**
Autoriser la modification du champ :
- `dernier_suivi_client` → mapped to `date_dernier_suivi_client`

### 5.6 `crm_list_missions` — **mise à jour (optionnel)**
Ajouter `date_demarrage_initiale` et `date_dernier_suivi_mission` dans les objets de la liste (peut être `null`).

### 5.7 `crm_weekly_summary` — **mise à jour (optionnel)**
Inclure un bloc "Missions sans suivi depuis > 30 jours" en exploitant `date_dernier_suivi_mission`.

---

## 6. Alimentation initiale des données (migration)

### 6.1 Source des données
Fichier : `Tableau_Bord_Lyon_2026.xlsx` — onglet `Régie`

| Champ CRM | Colonne Excel | Index colonne |
|---|---|---|
| `date_demarrage_initiale` | `Date Entrée` | 11 |
| `date_dernier_suivi_mission` | `Dernier suivi mission` | 15 |

Le matching mission ↔ ligne Excel se fait sur la combinaison : **Consultant (nom) + Client**.

### 6.2 Données disponibles au 20/03/2026 (onglet Régie)

| Consultant | Client | Date Entrée | Dernier suivi mission |
|---|---|---|---|
| Yann DELERUE | SNCF | 26/06/2024 | 02/10/2026 |
| Naomi PEREIRA | Groupe SEB | 02/12/2024 | 15/10/2026 |
| Mathilde VILLANTI | EDF | 09/12/2024 | 19/02/2026 |
| Frédéric TAPIA | EDF | 10/02/2025 | 17/06/2026 |
| Lucas MOLINA | Enedis | 02/03/2025 | 24/07/2025 |
| Melissa LABORDE | EDF | 13/10/2025 | 19/12/2025 |
| Matteo FERRERA | EDF | 13/10/2025 | 18/12/2025 |
| Paul HANNECART | EDF | 17/10/2025 | 12/02/2025 |
| Justine BEAUCHET-CRAON | EDF | 17/11/2025 | 20/02/2026 |
| Maria-Jose PAQUELIER | EDF | 23/02/2026 | — |
| Manon FARALDI | EDF | 16/03/2026 | — |
| Nicolas LOBJOIS | EDF | 09/10/2023 | 18/06/2025 |
| Florent VASQUEZ | Enedis | 03/02/2024 | 01/01/2026 |
| Chloé CORDEL | EDF | 09/09/2024 | 10/06/2025 |
| Etna VILALLONGA | EDF | 03/11/2025 | 07/10/2025 |

> **Note :** Le champ `date_dernier_suivi_mission` peut aussi être alimenté a posteriori depuis l'historique des actions CRM de type "Suivi de mission" déjà loggées sur les missions — en prenant la date la plus récente par mission.

### 6.3 Script de migration suggéré
Le script de migration doit :
1. Lire le fichier Excel (onglet Régie).
2. Pour chaque ligne, matcher avec la mission CRM via (nom consultant + client).
3. Écrire `date_demarrage_initiale` = `Date Entrée`.
4. Écrire `date_dernier_suivi_mission` = `max(Dernier suivi mission Excel, MAX(date_action WHERE type="Suivi de mission") sur la mission)`.
5. Calculer `date_dernier_suivi_client` = `MAX(date_dernier_suivi_mission)` sur toutes les missions actives d'un contact client.

---

## 7. Cas limites

| Cas | Comportement attendu |
|---|---|
| Mission créée sans `date_demarrage_initiale` | Champ `null`, affiché "Non renseigné" dans l'UI |
| Plusieurs missions actives pour un client | `date_dernier_suivi_client` = date la plus récente parmi toutes les missions du contact |
| Action loggée avec date antérieure à `date_dernier_suivi_mission` | Pas d'écrasement — la valeur actuelle est conservée |
| Mission terminée | Les champs restent visibles en lecture seule dans l'historique |

---

## 8. Priorité & effort estimé

| Tâche | Priorité | Effort |
|---|---|---|
| Ajout champs BDD (Mission + Contact) | P0 | XS |
| Migration données depuis Excel | P0 | S |
| API `crm_get_mission` + `crm_update_mission` | P0 | S |
| API `crm_get_contact` + `crm_update_contact` | P0 | XS |
| Mise à jour auto via `crm_log_mission_action` | P0 | S |
| Affichage fiche Mission + Contact | P1 | S |
| Indicateurs visuels (30/60j) | P1 | XS |
| Colonnes dans vue Pipeline | P2 | S |
| Bloc weekly_summary | P2 | XS |

