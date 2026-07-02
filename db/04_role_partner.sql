-- db/04 — Rôle `partner` : périmètre = liste explicite de consultants
-- =====================================================================
-- Modèle : LECTURE ouverte au niveau DB pour contacts/comptes/missions (comme le reste
-- du CRM → le périmètre visuel est fait côté APP). Ce fichier verrouille en DUR :
--   (a) les ÉCRITURES du partner (limitées à SES consultants, jamais de DELETE)
--   (b) la LECTURE des tables NON ouvertes (mission_periods, historique_*, taches) →
--       le partner ne voit QUE celles rattachées à ses consultants.
-- Les besoins / prospection restent INVISIBLES au partner (aucune branche + agence neutre).
--
-- ADDITIF : on n'ajoute que des policies `*_partner_*` gardées par get_my_role()='partner'.
-- Les policies admin/commercial existantes ne sont PAS touchées → zéro régression.
-- À exécuter dans Supabase → SQL Editor. Réversible (voir bloc ROLLBACK en fin).

-- 1) Table d'affectation partner ↔ consultants ------------------------
create table if not exists public.partner_consultants (
  partner_id            uuid   not null references public.profiles(id) on delete cascade,
  contact_consultant_id bigint not null references public.contacts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (partner_id, contact_consultant_id)
);
alter table public.partner_consultants enable row level security;

drop policy if exists pc_read on public.partner_consultants;
create policy pc_read on public.partner_consultants for select
  using ( partner_id = auth.uid() or get_my_role() = 'admin' );

drop policy if exists pc_write on public.partner_consultants;
create policy pc_write on public.partner_consultants for all
  using ( get_my_role() = 'admin' ) with check ( get_my_role() = 'admin' );

-- 2) Helper : le consultant c_id est-il dans MON périmètre partner ? ----
create or replace function public.is_my_consultant(c_id bigint)
returns boolean language sql stable security definer
set search_path = public as $$
  select exists (
    select 1 from public.partner_consultants pc
    where pc.partner_id = auth.uid() and pc.contact_consultant_id = c_id
  );
$$;

-- 3) CONTACTS (SELECT déjà ouvert) — UPDATE de ses consultants ---------
drop policy if exists contacts_partner_update on public.contacts;
create policy contacts_partner_update on public.contacts for update
  using      ( get_my_role()='partner' and public.is_my_consultant(id) )
  with check ( get_my_role()='partner' and public.is_my_consultant(id) );
-- (INSERT contacts déjà autorisé à tout authentifié ; DELETE : pas de branche partner)

-- 4) MISSIONS (SELECT déjà ouvert) — INSERT + UPDATE (pas de DELETE) ---
drop policy if exists missions_partner_insert on public.missions;
create policy missions_partner_insert on public.missions for insert
  with check ( get_my_role()='partner' and public.is_my_consultant(contact_consultant_id) );
drop policy if exists missions_partner_update on public.missions;
create policy missions_partner_update on public.missions for update
  using      ( get_my_role()='partner' and public.is_my_consultant(contact_consultant_id) )
  with check ( get_my_role()='partner' and public.is_my_consultant(contact_consultant_id) );

-- 5) MISSION_PERIODS (SELECT restreint) — READ + INSERT + UPDATE -------
drop policy if exists mp_partner_read on public.mission_periods;
create policy mp_partner_read on public.mission_periods for select
  using ( get_my_role()='partner' and exists (
    select 1 from public.missions m
    where m.id = mission_periods.mission_id and public.is_my_consultant(m.contact_consultant_id) ) );
drop policy if exists mp_partner_insert on public.mission_periods;
create policy mp_partner_insert on public.mission_periods for insert
  with check ( get_my_role()='partner' and exists (
    select 1 from public.missions m
    where m.id = mission_periods.mission_id and public.is_my_consultant(m.contact_consultant_id) ) );
drop policy if exists mp_partner_update on public.mission_periods;
create policy mp_partner_update on public.mission_periods for update
  using ( get_my_role()='partner' and exists (
    select 1 from public.missions m
    where m.id = mission_periods.mission_id and public.is_my_consultant(m.contact_consultant_id) ) )
  with check ( get_my_role()='partner' and exists (
    select 1 from public.missions m
    where m.id = mission_periods.mission_id and public.is_my_consultant(m.contact_consultant_id) ) );

-- 6) HISTORIQUE_MISSIONS (SELECT restreint) — READ + INSERT -----------
drop policy if exists hm_partner_read on public.historique_missions;
create policy hm_partner_read on public.historique_missions for select
  using ( get_my_role()='partner' and exists (
    select 1 from public.missions m
    where m.id = historique_missions.mission_id and public.is_my_consultant(m.contact_consultant_id) ) );
drop policy if exists hm_partner_insert on public.historique_missions;
create policy hm_partner_insert on public.historique_missions for insert
  with check ( get_my_role()='partner' and exists (
    select 1 from public.missions m
    where m.id = historique_missions.mission_id and public.is_my_consultant(m.contact_consultant_id) ) );

-- 7) HISTORIQUE_ACTIONS (SELECT restreint ; FK contact = id_prospect) --
drop policy if exists ha_partner_read on public.historique_actions;
create policy ha_partner_read on public.historique_actions for select
  using ( get_my_role()='partner' and public.is_my_consultant(id_prospect) );
drop policy if exists ha_partner_insert on public.historique_actions;
create policy ha_partner_insert on public.historique_actions for insert
  with check ( get_my_role()='partner' and public.is_my_consultant(id_prospect) );

-- 8) TACHES (SELECT restreint) — READ + INSERT + UPDATE ---------------
--    Visible/éditable si liée à un de ses consultants (contact_id) OU à une de ses missions.
drop policy if exists taches_partner_read on public.taches;
create policy taches_partner_read on public.taches for select
  using ( get_my_role()='partner' and (
      public.is_my_consultant(contact_id)
      or exists (select 1 from public.missions m
                 where m.id = taches.mission_id and public.is_my_consultant(m.contact_consultant_id)) ) );
drop policy if exists taches_partner_insert on public.taches;
create policy taches_partner_insert on public.taches for insert
  with check ( get_my_role()='partner' and (
      public.is_my_consultant(contact_id)
      or exists (select 1 from public.missions m
                 where m.id = taches.mission_id and public.is_my_consultant(m.contact_consultant_id)) ) );
drop policy if exists taches_partner_update on public.taches;
create policy taches_partner_update on public.taches for update
  using ( get_my_role()='partner' and (
      public.is_my_consultant(contact_id)
      or exists (select 1 from public.missions m
                 where m.id = taches.mission_id and public.is_my_consultant(m.contact_consultant_id)) ) )
  with check ( get_my_role()='partner' and (
      public.is_my_consultant(contact_id)
      or exists (select 1 from public.missions m
                 where m.id = taches.mission_id and public.is_my_consultant(m.contact_consultant_id)) ) );

-- 9) Provisionnement de Majo (à compléter avec l'uuid auth) -----------
-- a) Supabase → Authentication → Add user : Maria-Jose.Paquelier@upgrade.fr (+ mot de passe)
-- b) récupérer l'uuid généré, puis :
-- insert into public.profiles (id, nom, agence, role)
-- values ('<UUID_AUTH_MAJO>', 'Maria-Jose Paquelier', 'Partner', 'partner')
-- on conflict (id) do update set nom=excluded.nom, agence=excluded.agence, role=excluded.role;
--   ⚠️ agence = 'Partner' (valeur NEUTRE, PAS 'Lyon') → évite toute fuite de lecture par
--      les branches agence (ex. besoins_select filtre par agence).
-- c) affecter ses 7 consultants :
-- insert into public.partner_consultants (partner_id, contact_consultant_id) values
--   ('<UUID_AUTH_MAJO>', 365),  -- Naomi Pereira
--   ('<UUID_AUTH_MAJO>', 366),  -- Mathilde Villanti
--   ('<UUID_AUTH_MAJO>', 367),  -- Frédéric Tapia
--   ('<UUID_AUTH_MAJO>', 368),  -- Lucas Molina
--   ('<UUID_AUTH_MAJO>', 369),  -- Melissa Laborde
--   ('<UUID_AUTH_MAJO>', 394),  -- Manon Faraldi
--   ('<UUID_AUTH_MAJO>', 1418)  -- Marie Maitrallin
-- on conflict do nothing;

-- =====================================================================
-- ROLLBACK (si besoin de tout défaire) :
--   drop policy if exists contacts_partner_update on public.contacts;
--   drop policy if exists missions_partner_insert on public.missions;
--   drop policy if exists missions_partner_update on public.missions;
--   drop policy if exists mp_partner_read on public.mission_periods;
--   drop policy if exists mp_partner_insert on public.mission_periods;
--   drop policy if exists mp_partner_update on public.mission_periods;
--   drop policy if exists hm_partner_read on public.historique_missions;
--   drop policy if exists hm_partner_insert on public.historique_missions;
--   drop policy if exists ha_partner_read on public.historique_actions;
--   drop policy if exists ha_partner_insert on public.historique_actions;
--   drop policy if exists taches_partner_read on public.taches;
--   drop policy if exists taches_partner_insert on public.taches;
--   drop policy if exists taches_partner_update on public.taches;
--   drop function if exists public.is_my_consultant(bigint);
--   drop table if exists public.partner_consultants;
--   -- + supprimer le profil et l'utilisateur auth de Majo
