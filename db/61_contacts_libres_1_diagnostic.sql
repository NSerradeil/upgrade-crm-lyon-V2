-- ══════════════════════════════════════════════════════════════════════
-- 61 — Contacts libres d'accès (06/11/2026, décisions Nicolas) : le référent d'un contact ne bloque plus
-- BLOC 1/3 — DIAGNOSTIC (lecture seule, ne modifie RIEN)
--
-- Lancer sur le Mac mini (lecture seule forcée par la transaction READ ONLY) :
--   ssh jules@100.123.217.38 '/opt/homebrew/bin/docker exec -i supabase-db psql -U supabase_admin -d postgres -P pager=off' \
--     < db/61_contacts_libres_1_diagnostic.sql
-- Tout écart avec un ATTENDU = arrêt et compte rendu avant le bloc 2.
-- ══════════════════════════════════════════════════════════════════════

begin transaction read only;

-- D1. ATTENDU : corbeille | corbeille_journal (db/60 en prod).
select to_regclass('public.corbeille') as corbeille, to_regclass('public.corbeille_journal') as journal;

-- D2. Empreintes des fonctions touchées par db/61 et db/62.
-- ATTENDU : supprimer_fiche = e015b770fef173f55edff5bd45198ec5 ; guard_responsable_change = 6078f6019d620aa74c8463110c8fed3a ;
--           transferer_responsabilite = md5 du corps de db/59_2_apply.sql (l. 67-132), calculé à part (T0.2).
select proname, md5(prosrc), length(prosrc)
  from pg_proc
 where pronamespace = 'public'::regnamespace
   and proname in ('supprimer_fiche','transferer_responsabilite','guard_responsable_change','_garde_suppression_directe')
 order by 1;

-- D3. Policies des tables concernées. ATTENDU : contacts UPDATE admin+commercial, DELETE admin seul ; corbeille lecture admin.
select tablename, policyname, cmd, roles, qual, with_check
  from pg_policies
 where schemaname = 'public'
   and tablename in ('contacts','contact_compte','comptes','historique_actions','corbeille','corbeille_journal')
 order by 1, 3, 2;

-- D4. Triggers non internes. ATTENDU : trg_guard_responsable sur besoins, comptes, contacts, missions, taches ;
--     aucun trg_alerte_double_contact.
select tgrelid::regclass as table_, tgname, pg_get_triggerdef(t.oid) as def
  from pg_trigger t
 where not tgisinternal
   and tgrelid in ('public.contacts'::regclass, 'public.comptes'::regclass, 'public.historique_actions'::regclass,
                   'public.contact_compte'::regclass, 'public.besoins'::regclass, 'public.missions'::regclass,
                   'public.taches'::regclass, 'public.besoin_candidats'::regclass)
 order by 1, 2;

-- D5. Profils par rôle. ATTENDU : admin 2, commercial 4, partner 1.
select role, count(*) from public.profiles group by 1 order by 1;

-- D6. Contacts : total, sans référent, référent inconnu. ATTENDU : ~2244 | 0 | 0.
select count(*) as total,
       count(*) filter (where responsable is null or btrim(responsable) = '') as sans_referent,
       count(*) filter (where responsable is not null and responsable not in (select nom from public.profiles)) as referent_inconnu
  from public.contacts;

-- D7. Corbeille. ATTENDU : 0 ligne (sinon noter : des suppressions réelles ont eu lieu).
select objet_type, count(*) from public.corbeille group by 1;

-- D8. Règle « Ne pas recontacter » en base. ATTENDU : fonctions de prospection jules seulement (aucune ne teste le
--     responsable pour la SORTIE de NPC).
select n.nspname, p.proname
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where p.prosrc ilike '%recontacter%' and n.nspname in ('public','jules')
 order by 1, 2;

-- D9. Natures de cartes Jules (information pour L3, hors périmètre de db/61).
select pg_get_constraintdef(oid) from pg_constraint where conname = 'agent_approvals_nature_check';

-- D10. Journal des transferts (information).
select objet_type, count(*) from public.transferts_responsabilite group by 1;

rollback;
