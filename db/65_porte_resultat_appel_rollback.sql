-- ══════════════════════════════════════════════════════════════════════
-- 65 — RETOUR ARRIÈRE de db/65_porte_resultat_appel_2_apply.sql
-- Retire la porte d'écriture et ses colonnes. Ce que la porte a écrit dans les colonnes neuves est d'abord
-- copié dans _spc_t1_bak_<horodatage> et _sessions_t1_bak_<horodatage> (RLS, superuser seul).
-- Les lignes d'historique et les tâches créées par la porte restent (ce sont de vraies écritures du CRM).
-- Une ligne au statut 'message' (sans appel) repasse en 'none' (le message reste dans l'historique du contact).
-- Décisions actées 20/11 (Nicolas) : direction en lecture seule sur la session d'un autre ; « Ne plus appeler »
-- arrête aussi les séquences Jules d'un collègue (RGPD). Rien à défaire pour elles ici.
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/65_porte_resultat_appel_rollback.sql
-- ══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on
begin;
lock table public.session_prospection_contacts in share row exclusive mode;

do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'session_prospection_contacts' and column_name = 'geste_id') then
    raise exception 'db/66 en place : passer d''abord db/66_porte_un_historique_par_appel_rollback.sql';
  end if;
end $$;

do $$
declare v_suffixe text := to_char(now() at time zone 'Europe/Paris', 'YYYYMMDD_HH24MI');
begin
  execute format('create table public.%I as select id, session_id, contact_id, statut, canal, precision, suite, date_suite, ne_plus_appeler,
                  appel_at, geste_at, historique_id, tache_id, message_canal, message_at, message_historique_id, message_tache_id,
                  contact_avant, contact_pose, maj_par from public.session_prospection_contacts where geste_at is not null', '_spc_t1_bak_' || v_suffixe);
  execute format('create table public.%I as select id, nb_messages, origine, mission_jules_id from public.sessions_prospection', '_sessions_t1_bak_' || v_suffixe);
  execute format('alter table public.%I enable row level security', '_spc_t1_bak_' || v_suffixe);
  execute format('alter table public.%I enable row level security', '_sessions_t1_bak_' || v_suffixe);
  execute format('revoke all on public.%I, public.%I from anon, authenticated', '_spc_t1_bak_' || v_suffixe, '_sessions_t1_bak_' || v_suffixe);
  raise notice 'Sauvegardes : _spc_t1_bak_% et _sessions_t1_bak_%', v_suffixe, v_suffixe;
end $$;

drop trigger if exists trg_spc_garde_porte on public.session_prospection_contacts;
drop function if exists public.spc_garde_porte();
drop function if exists public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text);
drop function if exists public._appel_contact_cible(jsonb,text,text,boolean,boolean,timestamptz,text,text,boolean,timestamptz,date);
drop function if exists public._ts_utc(timestamptz);

update public.session_prospection_contacts set statut = 'none' where statut = 'message';
alter table public.session_prospection_contacts drop constraint session_prospection_contacts_statut_check;
alter table public.session_prospection_contacts add constraint session_prospection_contacts_statut_check
  check (statut = any (array['none','called','interested','unreachable','not_interested']));

alter table public.session_prospection_contacts
  drop column canal, drop column precision, drop column suite, drop column date_suite, drop column ne_plus_appeler,
  drop column appel_at, drop column geste_at, drop column historique_id, drop column tache_id, drop column message_canal,
  drop column message_at, drop column message_historique_id, drop column message_tache_id, drop column contact_avant,
  drop column contact_pose, drop column maj_par;
alter table public.sessions_prospection drop column nb_messages, drop column origine, drop column mission_jules_id;

do $$
begin
  if exists (select 1 from pg_proc where proname = 'enregistrer_resultat_appel') then raise exception 'porte encore là'; end if;
  raise notice 'Retour arrière db/65 : OK';
end $$;
commit;
