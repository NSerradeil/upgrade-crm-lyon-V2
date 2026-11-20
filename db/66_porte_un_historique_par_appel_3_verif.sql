-- ══════════════════════════════════════════════════════════════════════
-- 66 — Une ligne d'historique par appel — BLOC 3/3 — VÉRIFICATION (lecture seule)
-- Rappel des décisions vérifiées par les tests du bloc 2 : direction en lecture seule sur la session d'un autre
-- (T1.13) ; « Ne plus appeler » arrête aussi les séquences Jules d'un collègue (T1.21).
-- ══════════════════════════════════════════════════════════════════════
begin read only;
select to_regprocedure('public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text)') is null as ancienne_signature_retiree,
       has_function_privilege('authenticated', 'public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text,boolean,uuid)', 'execute') as authenticated_attendu_t,
       has_function_privilege('anon', 'public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text,boolean,uuid)', 'execute') as anon_attendu_f,
       has_function_privilege('authenticated', 'public._spc_date_dernier_retrait(integer,date)', 'execute') as aide_authenticated_attendu_f,
       (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'session_prospection_contacts'
         and column_name in ('geste_id','nb_appels','appels_precedents')) as colonnes_attendu_3;
select statut, count(*) lignes, count(*) filter (where geste_at is not null) passees_par_la_porte, sum(nb_appels) appels_notes
  from public.session_prospection_contacts group by 1 order by 1;
select (select count(*) from public.historique_actions where type_action = 'Appel sortant') as historique_appels,
       (select count(*) from public.taches where session_prospection_id is not null) as taches_de_session;
rollback;
