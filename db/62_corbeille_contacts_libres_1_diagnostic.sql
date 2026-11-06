-- ══════════════════════════════════════════════════════════════════════
-- 62 — Corbeille contacts libres — BLOC 1/3 — DIAGNOSTIC (lecture seule)
--   ssh jules@100.123.217.38 '/opt/homebrew/bin/docker exec -i supabase-db psql -U supabase_admin -d postgres -P pager=off' \
--     < db/62_corbeille_contacts_libres_1_diagnostic.sql
-- ══════════════════════════════════════════════════════════════════════

begin transaction read only;

-- D1. ATTENDU : supprimer_fiche = e015b770fef173f55edff5bd45198ec5 ; _garde_suppression_directe = 84b7cab4a528386012e736df435559db
--     (sinon ARRÊT : quelqu'un les a modifiées depuis db/60).
select proname, md5(prosrc) from pg_proc
 where pronamespace = 'public'::regnamespace and proname in ('supprimer_fiche','_garde_suppression_directe') order by 1;

-- D2. Corbeille (information) : lignes par type et par auteur.
select objet_type, par_nom, count(*) from public.corbeille group by 1, 2 order by 1, 2;

-- D3. ATTENDU : delete_contacts = admin seul.
select policyname, cmd, qual from pg_policies where schemaname = 'public' and tablename = 'contacts' and cmd = 'DELETE';

rollback;
