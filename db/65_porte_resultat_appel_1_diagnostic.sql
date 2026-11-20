-- ══════════════════════════════════════════════════════════════════════
-- 65 — Porte d'écriture des sessions d'appel (T1) — BLOC 1/3 — DIAGNOSTIC (lecture seule)
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/65_porte_resultat_appel_1_diagnostic.sql
-- ══════════════════════════════════════════════════════════════════════
begin read only;

-- 1. Prérequis : db/64 en place, rien de T1 encore
select (select count(*) from pg_constraint where conname = 'spc_session_contact_uniq') as db64_contrainte_attendu_1,
       (select count(*) from pg_trigger where tgname = 'trg_spc_insertion_remplace') as db64_trigger_attendu_1,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'session_prospection_contacts'
         and column_name in ('geste_at','canal','historique_id')) as colonnes_t1_attendu_0,
       (select count(*) from pg_proc where proname in ('enregistrer_resultat_appel','_appel_contact_cible','_ts_utc')) as fonctions_t1_attendu_0,
       pg_get_constraintdef((select oid from pg_constraint where conname = 'session_prospection_contacts_statut_check')) as contrainte_statut;

-- 2. Photo des sessions (le bloc 2 n'en change aucune donnée)
select statut, count(*) sessions, sum(nb_contacts) appels, sum(nb_interesses) interesses, sum(nb_injoignables) injoignables,
       sum(nb_relances) relances from public.sessions_prospection group by 1 order by 1;
select statut, count(*) lignes from public.session_prospection_contacts group by 1 order by 1;

-- 3. Tables touchées par la porte : volumes (agrégats)
select (select count(*) from public.historique_actions where type_action = 'Appel sortant') as historique_appels,
       (select count(*) from public.taches where session_prospection_id is not null) as taches_de_session,
       (select count(*) from public.profiles where role = 'commercial') as commerciaux,
       (select count(*) from public.profiles where role = 'admin') as admins;
rollback;
