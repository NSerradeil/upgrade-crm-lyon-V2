-- 45_categorie_tech.sql — 2026-09-21
-- Ajoute la catégorie « tech » : les missions dev/roadmap/infra (fix playbook, roadmap archi,
-- validation technique…) sont typées tech et pourront être exclues du commercial via un filtre
-- (idée Nicolas 21/09). L'onglet Jules est déjà admin-only (jules_enabled) ; le filtre permet en
-- plus de masquer le tech par défaut pour ne pas polluer la vue commerciale.
-- Additif : étend le vocab (mission + task_type) et retague les missions dev existantes.

alter table public.agent_missions drop constraint if exists agent_missions_categorie_check;
alter table public.agent_missions
  add constraint agent_missions_categorie_check
  check (categorie is null or categorie in ('business','recrutement','veille','relance','pilotage','admin','tech'));

alter table public.agent_task_types drop constraint if exists agent_task_types_categorie_check;
alter table public.agent_task_types
  add constraint agent_task_types_categorie_check
  check (categorie is null or categorie in ('business','recrutement','veille','relance','pilotage','admin','tech'));

-- Retaguer les missions dev/roadmap (créées en pilotage faute de mieux) en tech.
update public.agent_missions set categorie = 'tech'
 where titre ilike '🗺️ Roadmap%'
    or titre ilike 'Fix playbook%'
    or titre ilike 'Valider le fix%'
    or titre ilike '%builder%';

-- Vérif :
--   select titre, categorie from public.agent_missions where categorie='tech';
