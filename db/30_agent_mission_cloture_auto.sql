-- db/30_agent_mission_cloture_auto.sql — clôture automatique des missions ponctuelles
-- (demande Nicolas 18/09) : une mission kind='oneshot' passe seule en statut='done' quand
-- toutes ses tâches sont closes (aucune en due/claimed/waiting_go), au lieu de rester
-- 'active' indéfiniment. Effet inverse : une mission oneshot déjà 'done' qui reçoit une
-- tâche redevenue ouverte (insert, ou reprise après échec/GO) repasse en 'active'. Les
-- missions 'recurring' et 'campagne' ne sont jamais touchées, ni les missions 'paused'/
-- 'cancelled' (on ne joue que sur les transitions active <-> done). Trigger posé sur
-- public.agent_tasks, after insert or update of statut, for each row — il n'écrit que
-- dans agent_missions et agent_events, jamais dans agent_tasks (pas de récursion).
-- À coller dans le SQL Editor Supabase. Idempotent. Style db/25_agent_noyau.sql.
begin;

create or replace function public.agent_mission_cloture_auto() returns trigger
language plpgsql security invoker as $$
declare
  m public.agent_missions;
  v_nb_ouvertes int;
  v_nb_total int;
begin
  -- Mission concernée : celle de la ligne NEW (insert / update), sinon rien à faire.
  if new.mission_id is null then
    return new;
  end if;

  select * into m from public.agent_missions where id = new.mission_id;
  if not found or m.kind <> 'oneshot' then
    return new;
  end if;

  select count(*) filter (where statut in ('due','claimed','waiting_go')),
         count(*)
    into v_nb_ouvertes, v_nb_total
    from public.agent_tasks
   where mission_id = m.id;

  if v_nb_ouvertes = 0 and v_nb_total > 0 and m.statut = 'active' then
    -- Toutes les tâches sont closes : la mission passe en done.
    update public.agent_missions set statut = 'done' where id = m.id;
    insert into public.agent_events (owner_id, actor, kind, mission_id, message)
    values (m.owner_id, 'sched', 'mission.done', m.id, m.titre);
  elsif v_nb_ouvertes > 0 and m.statut = 'done' then
    -- Une tâche rouvre (nouvelle tâche, ou reprise due après échec/GO) : réveil de la mission.
    update public.agent_missions set statut = 'active' where id = m.id;
    insert into public.agent_events (owner_id, actor, kind, mission_id, message)
    values (m.owner_id, 'sched', 'mission.reopened', m.id, m.titre);
  end if;
  -- Statuts 'paused'/'cancelled' : on ne les touche jamais depuis ce trigger.

  return new;
end $$;

drop trigger if exists agent_tasks_mission_cloture_auto on public.agent_tasks;
create trigger agent_tasks_mission_cloture_auto
  after insert or update of statut on public.agent_tasks
  for each row execute function public.agent_mission_cloture_auto();

commit;

-- Vérification manuelle (à jouer à la main dans le SQL Editor, pas dans ce script) :
--
-- 1) mission oneshot sans tâche : reste active (rien ne se déclenche, pas d'insert sur agent_tasks)
-- select id, titre, statut from public.agent_missions where kind = 'oneshot' and statut = 'active'
--   and id not in (select distinct mission_id from public.agent_tasks where mission_id is not null);
--
-- 2) fermeture auto : toutes les tâches d'une mission oneshot passées à 'done'/'cancelled'/'failed'
--    -> vérifier que la mission est passée à 'done' et qu'un event mission.done a été loggé
-- select m.id, m.titre, m.statut, e.kind, e.at
--   from public.agent_missions m
--   left join public.agent_events e on e.mission_id = m.id and e.kind in ('mission.done','mission.reopened')
--  where m.kind = 'oneshot'
--  order by e.at desc nulls last limit 20;
--
-- 3) réouverture : insérer une nouvelle tâche 'due' sur une mission oneshot 'done'
--    -> la mission doit repasser 'active' et un event mission.reopened doit apparaître
