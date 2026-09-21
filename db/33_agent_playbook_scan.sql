-- db/33_agent_playbook_scan.sql — Le scan des plateformes redevient un playbook versionné.
--
-- Pourquoi : un SKILL est une compétence que Nicolas déclenche en conversation (générer un
-- dossier de compétences, un ordre de mission, une prez). Un PLAYBOOK est le mode opératoire
-- d'un travail que Jules exécute seul dans un worker. Le scan des plateformes est le second,
-- pas le premier : personne ne le « demande », il part à 8h30 tout seul.
--
-- Il avait été déplacé dans ~/Pro/03_Outils-IA/SKILLs/ le 18/09 en résolvant un doublon avec
-- l'ancienne routine. Le doublon était réel, mais il a été résolu du mauvais côté : ce dossier
-- n'est pas versionné, donc une révision du playbook n'y laisse ni diff ni historique ni retour
-- arrière. C'est bloquant pour la boucle d'apprentissage des playbooks (sous-projet 5), où c'est
-- Jules qui écrira dedans.
--
-- Le dossier a été rapatrié tel quel dans le dépôt Jules — SKILL.md, les 14 fiches par
-- plateforme, platforms.json et okta-launch.json — sans rien réécrire. Seul le chemin change.
--
-- À coller dans le SQL Editor Supabase. Idempotent.
begin;

update public.agent_task_types
   set skill_path = 'routines/scan-plateformes/SKILL.md'
 where type = 'scan.plateformes';

commit;

-- Vérification après application :
--   select type, skill_path from public.agent_task_types where type = 'scan.plateformes';
-- Attendu : routines/scan-plateformes/SKILL.md
--
-- Note : matin.brief pointe encore vers 'skill:brief-du-jour', un skill synchronisé depuis le
-- compte Claude de Nicolas. Il n'est pas traité ici : une synchro écraserait toute révision
-- locale, donc le rapatrier demande une décision (cf. arbitrage en cours).
