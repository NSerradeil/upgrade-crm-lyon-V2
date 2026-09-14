-- db/20_agence.sql — Onglet Agence (SPEC_agence_effectifs.md)
-- À coller dans le SQL Editor Supabase (superuser). Idempotent.
begin;

-- 1) contacts : données collaborateur --------------------------------------
alter table public.contacts
  add column if not exists date_entree       date,
  add column if not exists date_sortie       date,
  add column if not exists salaire_annuel    numeric(10,2),
  add column if not exists cjm_manuel        boolean not null default false,
  add column if not exists statut_rh         text,
  add column if not exists statut_rh_depuis  date,
  add column if not exists type_presta       text,
  add column if not exists manager_trigramme text;

alter table public.contacts drop constraint if exists contacts_statut_rh_check;
alter table public.contacts add constraint contacts_statut_rh_check
  check (statut_rh is null or statut_rh in ('arret_maladie','conge'));

alter table public.contacts drop constraint if exists contacts_type_presta_check;
alter table public.contacts add constraint contacts_type_presta_check
  check (type_presta is null or type_presta in ('freelance','sous_traitant'));

-- Backfill type_presta depuis le statut existant
update public.contacts set type_presta='freelance'     where statut='Freelance'   and type_presta is null;
update public.contacts set type_presta='sous_traitant' where statut='Prestataire' and type_presta is null;

-- Un CJM déjà saisi avant la migration est par définition manuel (pas dérivé d'un salaire)
update public.contacts set cjm_manuel=true where cjm is not null and salaire_annuel is null;

-- 2) profiles : partner « des partners » --------------------------------------
alter table public.profiles add column if not exists partner_lead boolean not null default false;

-- 3) is_my_consultant : un partner_lead voit/édite l'union de tous les partners ----
create or replace function public.is_my_consultant(c_id bigint)
returns boolean language sql stable security definer
set search_path = public as $$
  select exists (
    select 1 from public.partner_consultants pc
    where pc.contact_consultant_id = c_id
      and ( pc.partner_id = auth.uid()
            or exists (select 1 from public.profiles p where p.id = auth.uid() and p.partner_lead) )
  );
$$;

commit;

-- 4) Vérifications (à lire après exécution) -----------------------------------
select column_name, data_type from information_schema.columns
 where table_name='contacts' and column_name in
 ('date_entree','date_sortie','salaire_annuel','cjm_manuel','statut_rh','statut_rh_depuis','type_presta','manager_trigramme')
 order by column_name;                                   -- attendu : 8 lignes
select column_name from information_schema.columns where table_name='profiles' and column_name='partner_lead'; -- 1 ligne
select type_presta, count(*) from public.contacts where statut in ('Freelance','Prestataire') group by 1;  -- 0 null
select pg_get_functiondef('public.is_my_consultant(bigint)'::regprocedure) like '%partner_lead%' as ok;      -- true
