-- 44_categorie_mission.sql — 2026-09-21
-- (1) Catégorie PROPRE À LA MISSION (override du défaut task_type) : une mission « libre »
--     (ex. « Pools de leads ») n'est plus condamnée à « admin ».
-- (2) Vocabulaire simplifié : business / recrutement (au lieu d'un « chasse » unique) +
--     veille / relance / pilotage / admin. Prépare le routage vers des sous-agents spécialisés.
-- Catégorie effective lue par le CRM = coalesce(mission.categorie, task_type.categorie).

-- 1) Colonne override sur la mission
alter table public.agent_missions
  add column if not exists categorie text
  check (categorie is null or categorie in ('business','recrutement','veille','relance','pilotage','admin'));

-- 2) Migrer le vocabulaire des task_types (drop 'chasse')
alter table public.agent_task_types drop constraint if exists agent_task_types_categorie_check;
-- Défaut raisonnable pour la chasse générique ; les campagnes / lk / libre sont business OU
-- recrutement selon la mission → décidé par l'override mission (défaut null).
update public.agent_task_types set categorie = 'business' where type = 'chasse.sourcer';
-- Filet générique : TOUTE catégorie hors du nouveau vocab (ex. 'chasse' sur campagne.*, lk.envoyer…)
-- retombe à null, décidée par l'override mission. Évite toute violation de contrainte.
update public.agent_task_types set categorie = null
 where categorie is not null
   and categorie not in ('business','recrutement','veille','relance','pilotage','admin');
alter table public.agent_task_types
  add constraint agent_task_types_categorie_check
  check (categorie is null or categorie in ('business','recrutement','veille','relance','pilotage','admin'));

-- 3) Backlog : catégorie EFFECTIVE = override mission sinon défaut task_type (dernière colonne, inchangée de place)
create or replace view public.agent_v_backlog as
  select m.id, m.titre, m.kind, m.statut, m.priorite, m.contexte, m.updated_at,
         count(t.id) filter (where t.statut = 'due')        as nb_due,
         count(t.id) filter (where t.statut = 'claimed')    as nb_claimed,
         count(t.id) filter (where t.statut = 'waiting_go') as nb_waiting_go,
         count(t.id) filter (where t.statut = 'failed')     as nb_failed,
         count(t.id) filter (where t.statut = 'done')       as nb_done,
         coalesce(m.categorie, tt.categorie) as categorie
    from public.agent_missions m
    left join public.agent_tasks t on t.mission_id = m.id
    left join public.agent_task_types tt on tt.type = m.task_type
   where m.statut in ('active','paused')
   group by m.id, coalesce(m.categorie, tt.categorie);
alter view public.agent_v_backlog set (security_invoker = on);

-- 4) Taguer l'existant
update public.agent_missions set categorie = 'business'    where titre ilike '%pool%lead%';
update public.agent_missions set categorie = 'recrutement' where titre ilike 'Recrutement Sales ETI Paris%';

-- Vérif :
--   select titre, kind, categorie from public.agent_v_backlog order by categorie nulls last;
