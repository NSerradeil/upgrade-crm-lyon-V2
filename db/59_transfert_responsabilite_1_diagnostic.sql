-- ══════════════════════════════════════════════════════════════════════
-- 59 — Transfert de responsabilité d'un contact ou d'un compte (02/11/2026, GO Nicolas Slack)
-- BLOC 1/3 — DIAGNOSTIC (lecture seule, ne modifie RIEN)
--
-- Contexte : Anne-Claire et Camille doivent passer des prospects à un collègue ; aujourd'hui
-- seul Nicolas (admin) le fait. Lancer AVANT le bloc 2 et relire les attendus.
--
-- Lancer sur le Mac mini (lecture seule forcée par la transaction READ ONLY) :
--   ssh jules@100.123.217.38 '/opt/homebrew/bin/docker exec -i supabase-db psql -U supabase_admin -d postgres -P pager=off' \
--     < db/59_transfert_responsabilite_1_diagnostic.sql
-- (Ne PAS passer par crm-sql.sh pour ce bloc : inutile de relancer PostgREST pour une lecture.)
-- ══════════════════════════════════════════════════════════════════════

begin transaction read only;

-- D1. Le garde-fou db/10 est-il en place sur contacts et comptes ?
--     Attendu : 2 lignes (comptes, contacts) au minimum, actif = 'O'.
select c.relname as table_name, t.tgname, t.tgenabled as actif
from pg_trigger t join pg_class c on c.oid = t.tgrelid
where not t.tgisinternal and t.tgname = 'trg_guard_responsable'
order by 1;

-- D2. Sa règle est-elle toujours celle de db/10 (admin OU responsable actuel) ?
--     Attendu : true. Si false, quelqu'un l'a modifiée depuis : relire avant d'aller plus loin.
select pg_get_functiondef('public.guard_responsable_change'::regproc)
       like '%old.responsable = get_my_nom()%' as regle_db10_intacte;

-- D3. Les helpers d'identité existent (utilisés par le garde-fou).
select proname, prosecdef as security_definer
from pg_proc where pronamespace = 'public'::regnamespace
  and proname in ('get_my_role','get_my_nom')
order by 1;

-- D4. Rien ne porte déjà le nom des objets créés au bloc 2. Attendu : 0 ligne.
select 'fonction' as objet, proname as nom from pg_proc
 where pronamespace = 'public'::regnamespace and proname = 'transferer_responsabilite'
union all
select 'table', relname from pg_class
 where relnamespace = 'public'::regnamespace and relname = 'transferts_responsabilite';

-- D5. Colonnes utilisées par la fonction. Attendu : 6 lignes.
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (table_name, column_name) in (('contacts','responsable'),('contacts','updated_at'),
       ('comptes','responsable'),('comptes','updated_at'),('profiles','nom'),('profiles','role'))
order by 1, 2;

-- D6. Qui pourra RECEVOIR une fiche : admin/commercial non bannis.
--     Attendu : la liste des commerciaux actuels (Camille, Amel, Anne-Claire, Louis, Pierre, Nicolas…),
--     cible_valide = true pour tous ceux qui travaillent encore.
select p.nom, p.role, p.agence,
       (u.banned_until is not null and u.banned_until > now()) as banni,
       (u.deleted_at is not null) as supprime,
       (p.role in ('admin','commercial')
        and not (coalesce(u.banned_until, '-infinity') > now())
        and u.deleted_at is null) as cible_valide
from public.profiles p left join auth.users u on u.id = p.id
order by p.role, p.nom;

-- D7. Volumétrie par responsable (pour savoir ce qui est concerné).
select 'contacts' as objet, responsable, count(*) from public.contacts group by 2
union all
select 'comptes', responsable, count(*) from public.comptes group by 2
order by 1, 3 desc;

-- D8. Fiches dont le responsable n'est PAS un profil (legacy, ex. ancien collaborateur) :
--     elles ne pourront être transférées que par l'admin (personne n'en est « responsable actuel »).
select 'contacts' as objet, c.responsable, count(*)
from public.contacts c
where c.responsable is not null and not exists (select 1 from public.profiles p where p.nom = c.responsable)
group by 2
union all
select 'comptes', c.responsable, count(*)
from public.comptes c
where c.responsable is not null and not exists (select 1 from public.profiles p where p.nom = c.responsable)
group by 2;

-- D9. Triggers sur historique_actions (pour mémoire : la fonction n'y écrit PAS, justement parce
--     que trg_update_date_dernier y ferait bouger « dernier contact » sur une simple réattribution).
select t.tgname, p.proname
from pg_trigger t join pg_proc p on p.oid = t.tgfoid
where t.tgrelid = 'public.historique_actions'::regclass and not t.tgisinternal;

-- D10. Rôle qui possédera la fonction (= celui qui lance le bloc 2). Doit être superuser ou
--      bypassrls pour que la fonction écrive son journal malgré la RLS. Attendu : supabase_admin, true.
select current_user, rolsuper or rolbypassrls as contourne_rls
from pg_roles where rolname = current_user;

rollback;
