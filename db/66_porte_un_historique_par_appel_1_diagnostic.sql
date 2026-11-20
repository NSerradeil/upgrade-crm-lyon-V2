-- ══════════════════════════════════════════════════════════════════════
-- 66 — Une ligne d'historique par appel — BLOC 1/3 — DIAGNOSTIC (lecture seule, agrégats)
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/66_porte_un_historique_par_appel_1_diagnostic.sql
-- ══════════════════════════════════════════════════════════════════════
begin read only;
select to_regprocedure('public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text)') is not null as porte_db65_presente,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'session_prospection_contacts'
         and column_name in ('geste_id','nb_appels','appels_precedents')) as colonnes_db66_attendu_0;
select statut, count(*) lignes, count(*) filter (where geste_at is not null) passees_par_la_porte
  from public.session_prospection_contacts group by 1 order by 1;
select (select count(*) from public.historique_actions where type_action = 'Appel sortant') as historique_appels,
       (select count(*) from public.taches where session_prospection_id is not null) as taches_de_session,
       (select count(*) from public.sessions_prospection) as sessions;
rollback;
