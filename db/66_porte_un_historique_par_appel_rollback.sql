-- ══════════════════════════════════════════════════════════════════════
-- 66 — RETOUR ARRIÈRE de db/66 : remet la porte db/65 (10 paramètres) depuis _fn_bak_db66_20261120, retire
-- p_nouvel_appel / p_geste_id, l'aide date_dernier et les colonnes geste_id, nb_appels, appels_precedents
-- (copiées d'abord dans _spc_db66_bak_<horodatage>). Les lignes d'historique et tâches des appels précédents
-- restent (vraies écritures du CRM). Les décisions actées (direction en lecture, « Ne plus appeler » qui arrête
-- aussi les séquences d'un collègue) restent celles de db/65.
-- À passer AVANT db/65_porte_resultat_appel_rollback.sql. Prévenir l'agent T2 : un appel avec p_nouvel_appel
-- ou p_geste_id échouera après ce retour arrière.
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/66_porte_un_historique_par_appel_rollback.sql
-- ══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on
begin;
do $$
declare v_suffixe text := to_char(clock_timestamp() at time zone 'Europe/Paris', 'YYYYMMDD_HH24MISS');
begin
  if to_regclass('public._fn_bak_db66_20261120') is null then raise exception 'Sauvegarde absente : arrêt'; end if;
  execute format('create table public.%I as select id, geste_id, nb_appels, appels_precedents from public.session_prospection_contacts
                  where geste_id is not null or appels_precedents is not null', '_spc_db66_bak_' || v_suffixe);
  execute format('alter table public.%I enable row level security', '_spc_db66_bak_' || v_suffixe);
  execute format('revoke all on public.%I from anon, authenticated', '_spc_db66_bak_' || v_suffixe);
  raise notice 'Sauvegarde : _spc_db66_bak_%', v_suffixe;
end $$;
drop function public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text,boolean,uuid);
do $$ begin execute (select definition from public._fn_bak_db66_20261120); end $$;
revoke all on function public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text) from public, anon;
grant execute on function public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text) to authenticated;
drop function public._spc_date_dernier_retrait(integer, date);
-- La porte db/65 est restaurée (et sa source est dans le dépôt) : la sauvegarde est retirée pour permettre un nouveau passage.
drop table public._fn_bak_db66_20261120;
alter table public.session_prospection_contacts drop column geste_id, drop column nb_appels, drop column appels_precedents;
do $$ begin
  if to_regprocedure('public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text)') is null then
    raise exception 'porte db/65 non restaurée'; end if;
  raise notice 'Retour arrière db/66 : OK';
end $$;
commit;
