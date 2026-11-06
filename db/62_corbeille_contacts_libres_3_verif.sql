-- ══════════════════════════════════════════════════════════════════════
-- 62 — Corbeille contacts libres — BLOC 3/3 — VÉRIFICATION (lecture seule)
-- ══════════════════════════════════════════════════════════════════════

begin transaction read only;

-- V1. ATTENDU : t | t (la règle « responsable ou admin » ne vaut plus que pour les comptes ; message de garde changé).
select position('if v_role <> ''admin'' and v_type = ''compte'' then' in prosrc) > 0 as regle_compte_seule
  from pg_proc where oid = 'public.supprimer_fiche(text,text,text,text,boolean)'::regprocedure;
select position('Seul le responsable' in prosrc) = 0 as message_garde_change
  from pg_proc where oid = 'public._garde_suppression_directe()'::regprocedure;

-- V2. ATTENDU : delete_contacts = (get_my_role() = 'admin'::text) : le DELETE direct reste fermé.
select policyname, cmd, qual from pg_policies where schemaname = 'public' and tablename = 'contacts' and cmd = 'DELETE';

-- V3. ATTENDU : authenticated et service_role ont EXECUTE, pas anon.
select has_function_privilege('authenticated', 'public.supprimer_fiche(text,text,text,text,boolean)', 'execute') as auth,
       has_function_privilege('service_role',  'public.supprimer_fiche(text,text,text,text,boolean)', 'execute') as service,
       has_function_privilege('anon',          'public.supprimer_fiche(text,text,text,text,boolean)', 'execute') as anon;

-- V4. ATTENDU : 0 | 0 (aucune fiche de test restée).
select (select count(*) from public.contacts where nom like 'TEST62%') as contacts_test,
       (select count(*) from public.comptes where nom like 'ZZTEST62%') as comptes_test;

-- V5. Corbeille (information).
select objet_type, par_nom, count(*) from public.corbeille group by 1, 2 order by 1, 2;

rollback;
