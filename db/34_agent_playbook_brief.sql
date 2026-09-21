-- db/34_agent_playbook_brief.sql — Le brief du matin devient un playbook versionné.
--
-- Suite de db/33 (scan des plateformes), qui laissait ce cas ouvert en note de bas de fichier :
-- « matin.brief pointe encore vers skill:brief-du-jour […] le rapatrier demande une décision ».
-- La décision est prise (Nicolas, 21/09) : on le rapatrie.
--
-- Ce qui a déclenché l'arbitrage : le brief du 21/09 a rendu une version amputée en annonçant
-- « Calendrier/Mail/Obsidian non connectés ». Les logs MCP de cette session (3e9e0c5b) montrent
-- pourtant apple-mail connecté en 5,7 s, apple-mail-calendar en 2,8 s, plaud en 3,9 s, tous
-- avec hasTools:true. Le worker n'avait simplement appelé aucun des trois.
--
-- Cause : le skill `brief-du-jour` est écrit pour COWORK, pas pour un worker. Il vise
-- `mcp__Upgrade_CRM__*` (chez Jules c'est `mcp__upgrade-crm__*`), `mcp__obsidian__search-vault`
-- (inexistant : le vault est en accès fichier), `mcp__cowork__present_files` (inexistant) et
-- écrit son artefact React dans /sessions/.../mnt/outputs/ (chemin Cowork). Sa règle de repli
-- — « si une source est indisponible, mentionner discrètement et continuer » — a fait le reste.
-- Le worker a donc suivi le skill correctement ; c'est le skill qui ne lui était pas destiné.
--
-- Le skill reste EN PLACE et inchangé : il est partagé avec les autres commerciaux de l'agence,
-- qui l'utilisent en session interactive, et une synchro depuis le compte Claude écraserait
-- toute retouche locale. On ne le touche pas — on cesse simplement de le faire exécuter par un
-- worker. Le playbook `routines/brief-du-jour.md` (dépôt Jules, versionné) prend le relais :
-- vrais noms d'outils, sortie texte au parapheur, pas d'artefact React.
--
-- Effet de bord voulu : le brief entre enfin dans le périmètre de la boucle d'amélioration des
-- playbooks (sous-projet 5), qui ne sait travailler que sur des fichiers de `routines/`.
--
-- À coller dans le SQL Editor Supabase. Idempotent.
begin;

update public.agent_task_types
   set skill_path = 'routines/brief-du-jour.md'
 where type = 'matin.brief';

commit;

-- Vérification après application :
--   select type, skill_path from public.agent_task_types where type = 'matin.brief';
-- Attendu : routines/brief-du-jour.md
--
-- Test grandeur nature : le brief du lendemain 7h. Il doit citer des RDV du calendrier et des
-- signaux mail. S'il annonce encore une source « non connectée », il doit désormais en donner
-- le code d'erreur exact — le prompt de l'ordonnanceur l'y oblige depuis le 21/09.
