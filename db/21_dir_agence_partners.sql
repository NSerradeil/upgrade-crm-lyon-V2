-- db/21_dir_agence_partners.sql — « Directeur d'agence » : peut changer le partner d'un consultant.
-- À coller dans le SQL Editor Supabase. Idempotent.
-- Contexte : Nicolas et Pierre sont déjà `admin`. Anne-Claire Decker est `commercial` mais dirige
-- l'agence Bordeaux/Ouest : on lui donne ce droit précis sans lui ouvrir tous les droits admin.
begin;

-- 1) Marqueur directeur d'agence -------------------------------------------
alter table public.profiles add column if not exists dir_agence boolean not null default false;
update public.profiles set dir_agence = true where nom in ('Anne Claire Decker');

-- 2) Helper : qui peut réaffecter un consultant à un partner ---------------
create or replace function public.can_manage_partners()
returns boolean language sql stable security definer
set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and (p.role = 'admin' or p.dir_agence)
  );
$$;

-- 3) Écriture sur partner_consultants --------------------------------------
-- La table existe déjà (créée hors migration, cf. db/04). On n'active PAS la RLS si elle ne l'est
-- pas déjà : on se contente d'ajouter les policies, qui ne prennent effet que si la RLS est active.
drop policy if exists pc_manage_insert on public.partner_consultants;
create policy pc_manage_insert on public.partner_consultants for insert
  with check ( public.can_manage_partners() );

drop policy if exists pc_manage_delete on public.partner_consultants;
create policy pc_manage_delete on public.partner_consultants for delete
  using ( public.can_manage_partners() );

drop policy if exists pc_manage_update on public.partner_consultants;
create policy pc_manage_update on public.partner_consultants for update
  using ( public.can_manage_partners() ) with check ( public.can_manage_partners() );

commit;

-- 4) Vérifications ----------------------------------------------------------
select nom, role, dir_agence from public.profiles order by nom;                 -- Anne Claire Decker = true
select policyname, cmd from pg_policies
 where tablename = 'partner_consultants' order by policyname;                   -- pc_manage_insert/delete/update
select relrowsecurity as rls_active from pg_class where relname = 'partner_consultants';
