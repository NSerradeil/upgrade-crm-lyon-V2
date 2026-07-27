-- ══════════════════════════════════════════════════════════════════════
-- 06 — Normalisation du champ `responsable` de la table `taches`
-- Date : 27/07/2026
--
-- PROBLÈME : le filtre "Tous les responsables" de l'onglet Tâches affiche
-- 3 entrées pour Nicolas (Nicolas / Nicolas Serradeil / nicolas.serradeil@upgrade.fr)
-- parce qu'il se construit sur les valeurs brutes distinctes de taches.responsable.
--
-- CAUSE : le MCP CRM accepte `responsable` en texte libre, sans le confronter
-- à profiles.nom. L'app (index.html) écrit toujours profile.nom : elle est saine.
--
-- PÉRIMÈTRE (audit du 27/07 sur les 7 tables portant un `responsable`) :
--   taches                31 lignes à corriger  (25 email + 6 "Nicolas")
--   historique_missions     8 lignes à corriger  (email)
--   historique_actions     19 lignes à corriger  ("Jules")
--   comptes / besoins / missions / sessions_prospection : PROPRES, on n'y touche pas.
--
-- Backups (rollback possible) :
--   db/_backup_taches_responsable_20260727.json      (31 lignes)
--   db/_backup_historique_responsable_20260727.json  (19 + 8 lignes)
-- ══════════════════════════════════════════════════════════════════════

-- ─── ÉTAPE 1 — AVANT : constater l'état (à lancer d'abord) ───
SELECT responsable, count(*) AS nb
FROM taches
GROUP BY responsable
ORDER BY nb DESC;
-- Attendu : Camille Salinson 620 | Nicolas Serradeil 538 | Anne Claire Decker 282
--           Amel Benzai 80 | nicolas.serradeil@upgrade.fr 25 | (null) 6
--           Nicolas 6 | Louis Py 2


-- ─── ÉTAPE 2 — LA CORRECTION (31 lignes) ───
UPDATE taches
SET responsable = 'Nicolas Serradeil'
WHERE responsable IN ('nicolas.serradeil@upgrade.fr', 'Nicolas');
-- Attendu : UPDATE 31

-- NOTE : les 6 tâches à responsable NULL ne sont PAS touchées volontairement.
-- Ce sont des relances de mars 2026, toutes en statut 'fait'/'annule', et une
-- valeur vide ne crée pas d'entrée fantôme dans le filtre. Zéro impact.


-- ─── ÉTAPE 2b — historique_missions (8 lignes) ───
-- Suivis de mission de Nicolas (janv→avr 2026) écrits avec son email.
UPDATE historique_missions
SET responsable = 'Nicolas Serradeil'
WHERE responsable = 'nicolas.serradeil@upgrade.fr';
-- Attendu : UPDATE 8   (ids 196 à 203)


-- ─── ÉTAPE 2c — historique_actions (19 lignes) ───
-- Invitations/messages LinkedIn des 15-16/06/2026 (campagne Laurie Martineau)
-- envoyés par Jules depuis le compte de Nicolas. Décision Nicolas du 27/07 :
-- le commercial de référence est Nicolas ; la mention de l'exécutant reste
-- lisible dans `details`.
UPDATE historique_actions
SET responsable = 'Nicolas Serradeil'
WHERE responsable = 'Jules';
-- Attendu : UPDATE 19  (ids 5202-5214, 5251-5256)


-- ─── ÉTAPE 3 — APRÈS : vérifier ───
SELECT responsable, count(*) AS nb
FROM taches
GROUP BY responsable
ORDER BY nb DESC;
-- Attendu : Camille Salinson 620 | Nicolas Serradeil 569 | Anne Claire Decker 282
--           Amel Benzai 80 | (null) 6 | Louis Py 2
-- => plus qu'UNE entrée Nicolas, et 538 + 25 + 6 = 569 tâches réunies.

-- Contrôle croisé FINAL : aucune valeur de responsable hors profiles.nom,
-- sur les 6 tables qui portent ce champ.
SELECT 'taches' AS src, responsable FROM taches
  WHERE responsable IS NOT NULL AND responsable NOT IN (SELECT nom FROM profiles)
UNION ALL SELECT 'comptes', responsable FROM comptes
  WHERE responsable IS NOT NULL AND responsable NOT IN (SELECT nom FROM profiles)
UNION ALL SELECT 'besoins', responsable FROM besoins
  WHERE responsable IS NOT NULL AND responsable NOT IN (SELECT nom FROM profiles)
UNION ALL SELECT 'missions', responsable FROM missions
  WHERE responsable IS NOT NULL AND responsable NOT IN (SELECT nom FROM profiles)
UNION ALL SELECT 'historique_actions', responsable FROM historique_actions
  WHERE responsable IS NOT NULL AND responsable NOT IN (SELECT nom FROM profiles)
UNION ALL SELECT 'historique_missions', responsable FROM historique_missions
  WHERE responsable IS NOT NULL AND responsable NOT IN (SELECT nom FROM profiles)
UNION ALL SELECT 'sessions_prospection', responsable FROM sessions_prospection
  WHERE responsable IS NOT NULL AND responsable NOT IN (SELECT nom FROM profiles);
-- Attendu : 0 ligne.


-- ─── ROLLBACK (si besoin) ───
-- Les 31 ids sont dans le backup JSON. Pour revenir en arrière :
--
-- UPDATE taches SET responsable = 'Nicolas' WHERE id IN (
--   'tw_1782720692964','tw_1782720695531','tw_1782720697183',
--   'tw_1780558375994','tw_1782720699129','tw_1782720701208');
--   -- ^ les 6 AO EDF DivNum + SNCF Connect
--
-- UPDATE taches SET responsable = 'nicolas.serradeil@upgrade.fr' WHERE id IN (
--   'tw_1783429741085','tw_1783429742588','tw_1784815362243','tw_1783429744699',
--   'tw_1783429746196','tw_1782137114233','tw_1782471931003','tw_1782914630616',
--   'tw_1784545430254','tw_1784545432994','tw_1781714059440','tw_1781714063181',
--   'tw_1784729054992','tw_1781714065672','tw_1781714067455','tw_1782310425758',
--   'tw_1784793882320','tw_1778683452503','tw_1778686109196','tw_1784793885982',
--   'tw_1782817363461','tw_1784124145054','tw_1782374607943','tw_1782990336584',
--   'tw_1784815356364');
--
-- UPDATE historique_missions SET responsable = 'nicolas.serradeil@upgrade.fr'
--   WHERE id BETWEEN 196 AND 203;
--
-- UPDATE historique_actions SET responsable = 'Jules' WHERE id IN (
--   5202,5203,5204,5205,5206,5207,5208,5209,5210,5211,5212,5213,5214,
--   5251,5252,5253,5254,5255,5256);
