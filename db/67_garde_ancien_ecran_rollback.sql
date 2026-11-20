-- 67 — RETOUR ARRIÈRE de db/67_garde_ancien_ecran_2_apply.sql (retire les 4 gardes ; aucune donnée touchée).
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/67_garde_ancien_ecran_rollback.sql
\set ON_ERROR_STOP on
begin;
drop trigger if exists trg_historique_garde_ancien_ecran on public.historique_actions;
drop trigger if exists trg_taches_garde_ancien_ecran on public.taches;
drop trigger if exists trg_spc_garde_ancien_ecran on public.session_prospection_contacts;
drop trigger if exists trg_sessions_garde_ancien_ecran on public.sessions_prospection;
drop function if exists public.historique_garde_ancien_ecran();
drop function if exists public.taches_garde_ancien_ecran();
drop function if exists public.spc_garde_ancien_ecran();
drop function if exists public.sessions_garde_ancien_ecran();
drop trigger if exists trg_sessions_garde_compteurs on public.sessions_prospection;
drop function if exists public.sessions_garde_compteurs();
do $$ begin
  if exists (select 1 from pg_proc where proname = 'spc_garde_ancien_ecran') then raise exception 'retour arrière incomplet'; end if;
  raise notice 'Retour arrière db/67 : OK';
end $$;
notify pgrst, 'reload schema';
commit;
