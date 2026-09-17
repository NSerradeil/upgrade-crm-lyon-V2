-- db/27_agent_claim_respecte_pause.sql — agent_claim_task ignore les tâches des missions
-- en pause (fix round 2 de la Task 7 migration état : les 289 tâches importées seraient
-- sinon reprises immédiatement par les workers alors que leurs missions sont en pause).
-- Redéfinit public.agent_claim_task à l'identique de db/25_agent_noyau.sql sauf la clause
-- where, qui ignore désormais toute tâche dont la mission n'est pas 'active'. Idempotent.
begin;

create or replace function public.agent_claim_task(p_worker text, p_lease_minutes int default 20)
returns setof public.agent_tasks language plpgsql security invoker as $$
declare r public.agent_tasks;
begin
  select * into r from public.agent_tasks t
   where t.statut = 'due' and t.due_at <= now() and t.owner_id = auth.uid()
     and (t.mission_id is null or exists (
           select 1 from public.agent_missions m where m.id = t.mission_id and m.statut = 'active'))
   order by t.priorite, t.due_at
   for update skip locked limit 1;
  if not found then return; end if;
  update public.agent_tasks
     set statut = 'claimed', leased_by = p_worker,
         lease_until = now() + make_interval(mins => p_lease_minutes), heartbeat_at = now()
   where id = r.id returning * into r;
  insert into public.agent_events (actor, kind, task_id, mission_id, message)
  values (p_worker, 'task.claimed', r.id, r.mission_id, r.titre);
  return next r;
end $$;

commit;
