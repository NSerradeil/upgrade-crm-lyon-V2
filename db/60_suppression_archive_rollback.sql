-- ══════════════════════════════════════════════════════════════════════
-- 60 — Suppression par le responsable, avec corbeille — ROLLBACK
--
-- Remet EXACTEMENT l'état d'avant db/60 :
--   - politique delete_contacts rouverte au responsable (admin OU responsable = get_my_nom()) ;
--   - garde trg_garde_suppression_directe retirée de contacts et comptes ;
--   - fonctions supprimées ;
--   - corbeille et journal SAUVEGARDÉS dans _corbeille_bak_60 / _corbeille_journal_bak_60 (lecture superuser seule),
--     puis supprimés. Les fiches archivées restent donc récupérables à la main.
--
-- ⚠️ ORDRE : remettre d'abord l'appli d'avant (revert du lot 2), PUIS lancer ce rollback.
--    Si on lance ce rollback avec l'appli du lot 2 en ligne, le bouton Supprimer affiche « fonction introuvable »
--    (proprement, rien de cassé) jusqu'au revert de l'appli.
--
--   zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/60_suppression_archive_rollback.sql
-- ══════════════════════════════════════════════════════════════════════

begin;

-- 1. Sauvegarde du contenu (si la corbeille existe).
do $$
begin
  if to_regclass('public.corbeille') is not null then
    execute 'create table if not exists public._corbeille_bak_60 as select * from public.corbeille where false';
    execute 'insert into public._corbeille_bak_60 select * from public.corbeille';
    execute 'alter table public._corbeille_bak_60 enable row level security';
    execute 'revoke all on public._corbeille_bak_60 from anon, authenticated, service_role';
  end if;
  if to_regclass('public.corbeille_journal') is not null then
    execute 'create table if not exists public._corbeille_journal_bak_60 as select * from public.corbeille_journal where false';
    execute 'insert into public._corbeille_journal_bak_60 select * from public.corbeille_journal';
    execute 'alter table public._corbeille_journal_bak_60 enable row level security';
    execute 'revoke all on public._corbeille_journal_bak_60 from anon, authenticated, service_role';
  end if;
end $$;

-- 2. Garde et politique d'avant.
drop trigger if exists trg_garde_suppression_directe on public.contacts;
drop trigger if exists trg_garde_suppression_directe on public.comptes;
drop function if exists public._garde_suppression_directe();

drop policy if exists delete_contacts on public.contacts;
create policy delete_contacts on public.contacts
  for delete to public using ((get_my_role() = 'admin'::text) or (responsable = get_my_nom()));

-- 3. Fonctions et tables.
drop function if exists public.supprimer_fiche(text, text, text, text, boolean);
drop function if exists public.restaurer_fiche(bigint, text);
drop function if exists public.purger_corbeille(bigint, timestamptz, text);
drop function if exists public.purger_corbeille_auto();
drop function if exists public._corbeille_reinserer(regclass, jsonb);
drop function if exists public._corbeille_appelant(text);
drop table if exists public.corbeille_journal;
drop table if exists public.corbeille;

notify pgrst, 'reload schema';

commit;

-- Vérification : attendu 0 ligne pour la 1re requête, et delete_contacts = admin OU responsable.
select proname as reste from pg_proc where pronamespace = 'public'::regnamespace
  and proname in ('supprimer_fiche','restaurer_fiche','purger_corbeille','purger_corbeille_auto','_corbeille_appelant','_corbeille_reinserer','_garde_suppression_directe')
union all select relname from pg_class where relnamespace = 'public'::regnamespace and relname in ('corbeille','corbeille_journal')
union all select tgname from pg_trigger where tgname = 'trg_garde_suppression_directe';
select policyname, roles, qual from pg_policies where schemaname = 'public' and tablename = 'contacts' and cmd = 'DELETE';
