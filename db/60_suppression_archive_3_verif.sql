-- ══════════════════════════════════════════════════════════════════════
-- 60 — Suppression par le responsable, avec corbeille
-- BLOC 3/3 — VÉRIFICATION (lecture seule) après le bloc 2
--
--   ssh jules@100.123.217.38 '/opt/homebrew/bin/docker exec -i supabase-db psql -U supabase_admin -d postgres -P pager=off' \
--     < db/60_suppression_archive_3_verif.sql
-- ══════════════════════════════════════════════════════════════════════

begin transaction read only;

-- V1. Objets créés. Attendu : 2 tables, 8 fonctions, 7 triggers (garde suppression : contacts, comptes ;
--     garde détachement : besoin_candidats, besoins, historique_actions, missions, taches).
select 'table' as quoi, relname as nom, relrowsecurity as rls from pg_class
 where relnamespace = 'public'::regnamespace and relname in ('corbeille','corbeille_journal')
union all
select 'fonction', proname || case when prosecdef then ' (security definer)' else '' end, null from pg_proc
 where pronamespace = 'public'::regnamespace
   and proname in ('supprimer_fiche','restaurer_fiche','purger_corbeille','purger_corbeille_auto','_corbeille_appelant','_corbeille_reinserer','_garde_suppression_directe','_garde_detachement')
union all
select 'trigger', tgrelid::regclass::text || '.' || tgname, tgenabled = 'O' from pg_trigger where tgname in ('trg_garde_suppression_directe','trg_garde_detachement')
order by 1, 2;

-- V2. delete_contacts = admin seul. Attendu : qual = (get_my_role() = 'admin'::text), roles = {authenticated}.
select tablename, policyname, roles, qual from pg_policies
where schemaname = 'public' and tablename in ('contacts','comptes','contact_compte') and cmd = 'DELETE' order by 1;

-- V3. Droits d'exécution. Attendu :
--   supprimer_fiche / restaurer_fiche / purger_corbeille : authenticated = true, anon = false
--   purger_corbeille_auto : authenticated = false, service_role = true
--   _corbeille_* : authenticated = false
select p.proname,
       has_function_privilege('anon', p.oid, 'execute')          as anon,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated,
       has_function_privilege('service_role', p.oid, 'execute')  as service_role
from pg_proc p where p.pronamespace = 'public'::regnamespace
  and p.proname in ('supprimer_fiche','restaurer_fiche','purger_corbeille','purger_corbeille_auto','_corbeille_appelant','_corbeille_reinserer')
order by 1;

-- V4. Corbeille : aucune écriture possible hors fonctions. Attendu : toutes les colonnes à false sauf select.
select t.relname,
       has_table_privilege('authenticated', t.oid, 'select') as select_auth,
       has_table_privilege('authenticated', t.oid, 'insert') as insert_auth,
       has_table_privilege('authenticated', t.oid, 'update') as update_auth,
       has_table_privilege('authenticated', t.oid, 'delete') as delete_auth,
       has_table_privilege('anon', t.oid, 'select')          as select_anon
from pg_class t where t.relnamespace = 'public'::regnamespace and t.relname in ('corbeille','corbeille_journal');

-- V5. Les tests ne laissent rien. Attendu : 0, 0, 0, 0.
select (select count(*) from public.corbeille) as corbeille,
       (select count(*) from public.corbeille_journal) as journal,
       (select count(*) from public.comptes where nom like 'ZZTEST60%') as comptes_test,
       (select count(*) from public.contacts where nom like 'TEST60%') as contacts_test;

commit;

-- Suivi courant (admin) :
--   select id, objet_type, objet_id, libelle, responsable_fiche, par_nom, origine, motif, supprime_le, restaure_le
--   from public.corbeille order by supprime_le desc limit 50;
--   select * from public.corbeille_journal order by created_at desc limit 50;
