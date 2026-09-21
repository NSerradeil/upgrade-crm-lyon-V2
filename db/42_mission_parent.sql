-- 42_mission_parent.sql — 2026-09-21
-- Une campagne = 1 mission chapeau (kind='campagne') + N phases récurrentes
-- (kind='recurring', task_type campagne.*). Jusqu'ici rien ne les reliait en base : dans la
-- table Missions ça faisait 4 lignes (dont 3 taguées « Routine ») pour UNE campagne → perturbant.
-- On ajoute un vrai lien parent, et on backfille l'existant par convention de titre « Parent — phase ».
-- Additif : colonne nullable + un update de rattachement. Aucune suppression.

alter table public.agent_missions
  add column if not exists parent_mission_id uuid references public.agent_missions(id);

-- Backfill : rattacher chaque phase de campagne à sa mission chapeau (même préfixe de titre).
update public.agent_missions ph
   set parent_mission_id = par.id
  from public.agent_missions par
 where par.kind = 'campagne'
   and ph.id <> par.id
   and ph.kind = 'recurring'
   and ph.task_type like 'campagne.%'
   and ph.parent_mission_id is null
   and ph.titre like par.titre || ' — %';

-- agent_missions est chargée en select('*') par l'onglet Jules → parent_mission_id y arrive
-- sans toucher aux vues. La table masquera les phases et les montrera dans le volet du parent.

-- Vérif :
--   select id, titre, kind, task_type, parent_mission_id from public.agent_missions
--    where titre ilike '%Sales ETI Paris%' order by parent_mission_id nulls first;
