-- ══════════════════════════════════════════════════════════════════════
-- 61 — Contacts libres d'accès — BLOC 3/3 — VÉRIFICATION (lecture seule)
--   ssh jules@100.123.217.38 '/opt/homebrew/bin/docker exec -i supabase-db psql -U supabase_admin -d postgres -P pager=off' \
--     < db/61_contacts_libres_3_verif.sql
-- ══════════════════════════════════════════════════════════════════════

begin transaction read only;

-- V1. ATTENDU : besoins | comptes | missions | taches (4 lignes, PAS contacts).
select tgrelid::regclass as table_ from pg_trigger where tgname = 'trg_guard_responsable' order by 1;

-- V2. ATTENDU : contacts | trg_garde_referent_contact | ... BEFORE UPDATE OF responsable ... garde_referent_contact()
select tgrelid::regclass as table_, tgname, pg_get_triggerdef(oid) from pg_trigger where tgname = 'trg_garde_referent_contact';

-- V3. ATTENDU : t (la règle « responsable ou admin » ne vaut plus que pour les comptes).
select position('v_type = ''compte'' and v_par_role' in prosrc) > 0 as regle_compte_seule
  from pg_proc where oid = 'public.transferer_responsabilite(text,bigint,text)'::regprocedure;

-- V4. ATTENDU : authenticated a EXECUTE sur transferer_responsabilite, pas anon ; personne sur garde_referent_contact.
select has_function_privilege('authenticated', 'public.transferer_responsabilite(text,bigint,text)', 'execute') as auth_transfert,
       has_function_privilege('anon', 'public.transferer_responsabilite(text,bigint,text)', 'execute') as anon_transfert,
       has_function_privilege('authenticated', 'public.garde_referent_contact()', 'execute') as auth_garde;

-- V5. Policies contacts inchangées. ATTENDU : delete_contacts = admin seul.
select policyname, cmd, qual from pg_policies where schemaname = 'public' and tablename = 'contacts' order by cmd, policyname;

-- V6. Aucune fiche de test restée. ATTENDU : 0 | 0
select (select count(*) from public.contacts where nom = 'ZZTEST61') as contacts_test,
       (select count(*) from public.comptes where nom = 'ZZTEST61 Compte') as comptes_test;

-- V7. Derniers changements de référent (information).
select objet_type, objet_id, ancien_responsable, nouveau_responsable, par_nom, created_at
  from public.transferts_responsabilite order by created_at desc limit 5;

rollback;
