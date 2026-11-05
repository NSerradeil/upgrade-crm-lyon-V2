-- ══════════════════════════════════════════════════════════════════════
-- 60 — Suppression par le responsable, avec corbeille (lot 1 : comptes + contacts)
-- BLOC 1/3 — DIAGNOSTIC (lecture seule, ne modifie RIEN)
--
-- Lancer sur le Mac mini (lecture seule forcée par la transaction READ ONLY) :
--   ssh jules@100.123.217.38 '/opt/homebrew/bin/docker exec -i supabase-db psql -U supabase_admin -d postgres -P pager=off' \
--     < db/60_suppression_archive_1_diagnostic.sql
-- (Ou coller dans l'éditeur SQL de Studio : tout est en lecture.)
-- Relire les attendus avant de lancer le bloc 2.
-- ══════════════════════════════════════════════════════════════════════

begin transaction read only;

-- D1. Rien de db/60 n'existe encore. Attendu : 0 ligne (sinon db/60 déjà appliqué : passer au bloc 3).
select 'table' as quoi, relname as nom from pg_class
 where relnamespace = 'public'::regnamespace and relname in ('corbeille','corbeille_journal')
union all
select 'fonction', proname from pg_proc
 where pronamespace = 'public'::regnamespace
   and proname in ('supprimer_fiche','restaurer_fiche','purger_corbeille','purger_corbeille_auto','_corbeille_appelant','_corbeille_reinserer','_garde_suppression_directe')
union all
select 'trigger', tgname from pg_trigger where tgname = 'trg_garde_suppression_directe';

-- D2. Politiques DELETE actuelles sur comptes / contacts / contact_compte.
--     Attendu : comptes_delete_admin et contact_compte_delete_admin = admin seul ;
--               delete_contacts = (get_my_role() = 'admin' OR responsable = get_my_nom())  ← celle que db/60 ferme.
select tablename, policyname, cmd, roles, qual
from pg_policies
where schemaname = 'public' and tablename in ('comptes','contacts','contact_compte') and cmd in ('DELETE','ALL')
order by 1, 2;

-- D3. Clés étrangères vers comptes et contacts (ce que la fonction archive / détache / refuse).
--     Attendu (05/11) : 15 lignes. Une ligne NOUVELLE = une table à ajouter à la fonction avant d'appliquer.
--       vers comptes  : besoins.compte_id (n), contact_compte.compte_id (c), missions.compte_id (n)
--       vers contacts : jules.agent_sequences.contact_id (n), besoin_candidats (c), besoins x3 (a), contact_compte (c),
--                       historique_actions (c), interco_imputations (c), missions x2 (a), partner_consultants (c),
--                       session_prospection_contacts (a)
select conrelid::regclass as table_source, a.attname as colonne, confrelid::regclass as vers, confdeltype as on_delete
from pg_constraint c
join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
where c.contype = 'f' and c.confrelid in ('public.comptes'::regclass, 'public.contacts'::regclass)
order by 3, 1, 2;

-- D4. Helpers utilisés par la fonction. Attendu : 4 lignes.
select n.nspname || '.' || p.proname as fonction
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where (n.nspname = 'public' and p.proname in ('get_my_nom','get_my_role'))
   or (n.nspname = 'jules'  and p.proname in ('est_direction','est_service_jwt'))
order by 1;

-- D5. Aucun trigger DELETE existant sur comptes / contacts. Attendu : 0 ligne.
select c.relname, t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid
where not t.tgisinternal and c.relname in ('comptes','contacts') and (t.tgtype & 8) <> 0;

-- D6. Profils pour les tests intégrés du bloc 2. Attendu : admin ≥ 1, commercial ≥ 2.
select role, count(*) from public.profiles group by role order by role;

-- D7. Volumes (pour la mémoire) : comptes sans responsable, contacts, séquences actives liées à un contact.
select (select count(*) from public.comptes) as comptes,
       (select count(*) from public.comptes where responsable is null or trim(responsable) = '') as comptes_sans_responsable,
       (select count(*) from public.contacts) as contacts,
       (select count(*) from jules.agent_sequences where contact_id is not null and statut in ('active','paused')) as sequences_actives_sur_contact;

-- D8. Responsables qui ne sont plus des profils actifs (fiches « d'un membre parti », supprimables par un admin seul).
select responsable, count(*) as nb_fiches from (
  select responsable from public.comptes union all select responsable from public.contacts) x
where responsable is not null and responsable not in (select nom from public.profiles where role in ('admin','commercial'))
group by responsable order by 2 desc;

commit;
