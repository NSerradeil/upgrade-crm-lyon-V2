-- db/29_agent_vues_security_invoker.sql — les vues agent_v_* doivent s'exécuter avec les
-- droits de l'APPELANT, pas du propriétaire. Sans `security_invoker`, une vue contourne la
-- RLS des tables qu'elle lit : dès qu'un second commercial a `profiles.jules_enabled = true`,
-- `agent_status` lui montrerait les missions, les tâches et le parapheur de Nicolas.
-- Aujourd'hui seul Nicolas est activé, donc aucune fuite n'a eu lieu — ce script ferme la
-- porte avant l'ouverture aux autres commerciaux (relevé à la revue finale du 18/09/2026).
-- À coller dans le SQL Editor Supabase. Idempotent.
begin;

do $$
declare v text;
begin
  foreach v in array array['agent_v_encours', 'agent_v_parapheur', 'agent_v_backlog',
                           'agent_v_due_today', 'agent_v_campagnes'] loop
    if to_regclass('public.' || v) is not null then
      execute format('alter view public.%I set (security_invoker = on)', v);
    end if;
  end loop;
end $$;

-- Vérification : les 5 vues doivent ressortir avec security_invoker=on.
-- select c.relname, c.reloptions from pg_class c
--   join pg_namespace n on n.oid = c.relnamespace
--  where n.nspname = 'public' and c.relkind = 'v' and c.relname like 'agent\_v\_%';

commit;
