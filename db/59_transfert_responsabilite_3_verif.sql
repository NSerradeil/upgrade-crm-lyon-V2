-- ══════════════════════════════════════════════════════════════════════
-- 59 — Transfert de responsabilité — BLOC 3/3 — VÉRIFICATION (après le bloc 2, lecture seule)
--
--   ssh jules@100.123.217.38 '/opt/homebrew/bin/docker exec -i supabase-db psql -U supabase_admin -d postgres -P pager=off' \
--     < db/59_transfert_responsabilite_3_verif.sql
--
-- Le vrai test fonctionnel a déjà tourné DANS le bloc 2 (notices « OK T1 … T6 »). Ici on photographie
-- l'état. Puis test réel DEPUIS L'APP avec un compte commercial (cf. ordre d'application).
-- ══════════════════════════════════════════════════════════════════════

begin transaction read only;

-- V1. La fonction existe, est SECURITY DEFINER, search_path figé. Attendu : 1 ligne, true, {search_path=public, pg_temp}.
select p.proname, p.prosecdef as security_definer, p.proconfig
from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'transferer_responsabilite';

-- V2. Qui peut l'appeler. Attendu : authenticated = true, anon = false.
select r.rolname, has_function_privilege(r.rolname, 'public.transferer_responsabilite(text,bigint,text)', 'execute') as peut_appeler
from pg_roles r where r.rolname in ('anon','authenticated','service_role') order by 1;

-- V3. Journal : lecture seule pour authenticated, rien pour anon.
--     Attendu : authenticated → SELECT uniquement ; aucune ligne pour anon.
select grantee, privilege_type from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'transferts_responsabilite' and grantee in ('anon','authenticated')
order by 1, 2;

-- V4. RLS active et une seule policy (lecture). Attendu : true, puis 1 ligne SELECT.
select relrowsecurity from pg_class where oid = 'public.transferts_responsabilite'::regclass;
select policyname, cmd, qual from pg_policies where tablename = 'transferts_responsabilite';

-- V5. Rien d'autre n'a bougé : le garde-fou db/10 et les policies UPDATE de contacts/comptes sont les mêmes
--     qu'au diagnostic D1/D2 (à comparer à l'œil).
select c.relname, t.tgname, t.tgenabled from pg_trigger t join pg_class c on c.oid = t.tgrelid
where not t.tgisinternal and t.tgname = 'trg_guard_responsable' order by 1;
select tablename, cmd, policyname, qual, with_check from pg_policies
where tablename in ('contacts','comptes') and cmd = 'UPDATE' order by 1, 3;

-- V6. Journal vide juste après application (les tests ont été annulés). Attendu : 0.
--     Plus tard : la liste des transferts réels.
select count(*) as transferts from public.transferts_responsabilite;
select * from public.transferts_responsabilite order by created_at desc limit 20;

rollback;
