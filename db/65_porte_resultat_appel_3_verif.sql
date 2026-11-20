-- ══════════════════════════════════════════════════════════════════════
-- 65 — Porte d'écriture des sessions d'appel (T1) — BLOC 3/3 — VÉRIFICATION (lecture seule)
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/65_porte_resultat_appel_3_verif.sql
-- ══════════════════════════════════════════════════════════════════════
begin read only;

-- 1. Fonction et droits : authenticated oui, anon non ; aides internes fermées
select has_function_privilege('authenticated', 'public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text)', 'execute') as authenticated_attendu_t,
       has_function_privilege('anon', 'public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text)', 'execute') as anon_attendu_f,
       has_function_privilege('authenticated', 'public._appel_contact_cible(jsonb,text,text,boolean,boolean,timestamptz,text,text,boolean,timestamptz,date)', 'execute') as aide_authenticated_attendu_f,
       (select prosecdef from pg_proc where proname = 'enregistrer_resultat_appel') as security_definer_attendu_t;

-- 2. Colonnes ajoutées
select count(*) filter (where table_name = 'session_prospection_contacts') as colonnes_spc_attendu_16,
       count(*) filter (where table_name = 'sessions_prospection') as colonnes_sessions_attendu_3
  from information_schema.columns
 where table_schema = 'public'
   and ((table_name = 'session_prospection_contacts' and column_name in ('canal','precision','suite','date_suite','ne_plus_appeler','appel_at','geste_at',
         'historique_id','tache_id','message_canal','message_at','message_historique_id','message_tache_id','contact_avant','contact_pose','maj_par'))
     or (table_name = 'sessions_prospection' and column_name in ('nb_messages','origine','mission_jules_id')));

-- 3. Données des sessions inchangées par le passage (comparées à la sauvegarde db/64).
--    Juste au moment du passage seulement : après le premier geste, la porte recalcule les compteurs de sa session.
select count(*) as sessions,
       count(*) filter (where (s.nb_contacts, s.nb_interesses, s.nb_relances, s.nb_injoignables) = (b.nb_contacts, b.nb_interesses, b.nb_relances, b.nb_injoignables)) as compteurs_identiques,
       count(*) filter (where s.nb_messages = 0 and s.origine = 'crm') as nb_messages_0_origine_crm
  from public.sessions_prospection s join public._sessions_prospection_bak_20261120 b on b.id = s.id;
select statut, count(*) lignes, count(*) filter (where geste_at is not null) passees_par_la_porte
  from public.session_prospection_contacts group by 1 order by 1;
select (select count(*) from pg_trigger where tgname = 'trg_spc_garde_porte') as filet_attendu_1;
rollback;
