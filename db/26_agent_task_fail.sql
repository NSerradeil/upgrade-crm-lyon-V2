-- db/26_agent_task_fail.sql — agent_task_fail atomique (fix round 1 de la Task 6).
-- Remplace le read-then-write JS (attempts lu puis réécrit, non atomique) par une
-- seule instruction UPDATE + insertion d'événement. À coller dans le SQL Editor
-- Supabase. Idempotent.
begin;

create or replace function public.agent_task_fail(
  p_task uuid, p_reason text, p_definitive boolean default false, p_max_attempts int default 3
) returns public.agent_tasks language plpgsql security invoker as $$
declare r public.agent_tasks;
begin
  update public.agent_tasks
     set attempts = attempts + 1,
         statut = case when p_definitive or attempts + 1 >= p_max_attempts then 'failed' else 'due' end,
         leased_by = null, lease_until = null,
         result = jsonb_build_object('error', p_reason)
   where id = p_task and owner_id = auth.uid()
  returning * into r;

  if not found then
    raise exception 'agent_task_fail: tâche % introuvable (ou pas la vôtre)', p_task;
  end if;

  insert into public.agent_events (actor, kind, task_id, mission_id, message)
  values ('worker', case when r.statut = 'failed' then 'task.failed' else 'task.requeued' end, r.id, r.mission_id, p_reason);

  return r;
end $$;

commit;
