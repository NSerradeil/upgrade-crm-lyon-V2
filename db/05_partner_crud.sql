-- db/05 — Rôle `partner` : ouverture du CRUD sur son périmètre (managés)
-- =====================================================================
-- Complète db/04_role_partner.sql. Le partner avait déjà : contacts UPDATE,
-- missions INSERT+UPDATE (pas DELETE), mission_periods READ+INSERT+UPDATE,
-- historique_actions/missions READ+INSERT, taches READ+INSERT+UPDATE.
-- Ici on AJOUTE ce qui manquait pour un vrai CRUD sur son périmètre :
--   historique_actions : UPDATE + DELETE
--   historique_missions: UPDATE + DELETE
--   taches             : DELETE
--   mission_periods    : DELETE (correction d'un CRA)
-- On NE touche PAS aux missions (toujours pas de DELETE partner ; l'interdiction
-- de TERMINER / changer agence / responsable est gérée côté app, cf. index.html).
-- Additif, gardé par get_my_role()='partner' + is_my_consultant(...). Réversible (bloc en fin).
-- À exécuter dans Supabase → SQL Editor APRÈS db/04.

-- Un partner ne peut PAS créer de mission → on retire l'INSERT accordé en db/04.
drop policy if exists missions_partner_insert on public.missions;

-- historique_actions (FK contact = id_prospect) : UPDATE + DELETE de son périmètre
drop policy if exists ha_partner_update on public.historique_actions;
create policy ha_partner_update on public.historique_actions for update
  using      ( get_my_role()='partner' and public.is_my_consultant(id_prospect) )
  with check ( get_my_role()='partner' and public.is_my_consultant(id_prospect) );
drop policy if exists ha_partner_delete on public.historique_actions;
create policy ha_partner_delete on public.historique_actions for delete
  using ( get_my_role()='partner' and public.is_my_consultant(id_prospect) );

-- historique_missions : UPDATE + DELETE (mission d'un de ses consultants)
drop policy if exists hm_partner_update on public.historique_missions;
create policy hm_partner_update on public.historique_missions for update
  using ( get_my_role()='partner' and exists (
    select 1 from public.missions m
    where m.id = historique_missions.mission_id and public.is_my_consultant(m.contact_consultant_id) ) )
  with check ( get_my_role()='partner' and exists (
    select 1 from public.missions m
    where m.id = historique_missions.mission_id and public.is_my_consultant(m.contact_consultant_id) ) );
drop policy if exists hm_partner_delete on public.historique_missions;
create policy hm_partner_delete on public.historique_missions for delete
  using ( get_my_role()='partner' and exists (
    select 1 from public.missions m
    where m.id = historique_missions.mission_id and public.is_my_consultant(m.contact_consultant_id) ) );

-- taches : DELETE (liée à un de ses consultants OU à une de ses missions)
drop policy if exists taches_partner_delete on public.taches;
create policy taches_partner_delete on public.taches for delete
  using ( get_my_role()='partner' and (
      public.is_my_consultant(contact_id)
      or exists (select 1 from public.missions m
                 where m.id = taches.mission_id and public.is_my_consultant(m.contact_consultant_id)) ) );

-- mission_periods : DELETE (correction d'un CRA sur une de ses missions)
drop policy if exists mp_partner_delete on public.mission_periods;
create policy mp_partner_delete on public.mission_periods for delete
  using ( get_my_role()='partner' and exists (
    select 1 from public.missions m
    where m.id = mission_periods.mission_id and public.is_my_consultant(m.contact_consultant_id) ) );

-- Trigger « ceinture + bretelles » : un partner ne peut PAS, sur une mission,
-- changer le statut mission (donc pas la TERMINER), l'agence ni le responsable.
-- N'affecte QUE les partners ; laisse passer jours_* et statut_* mensuels (le CRA).
create or replace function public.partner_mission_guard()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if get_my_role()='partner' then
    if NEW.statut      is distinct from OLD.statut      then raise exception 'Partner : changement de statut de mission interdit (terminaison)'; end if;
    if NEW.agence      is distinct from OLD.agence      then raise exception 'Partner : changement d''agence interdit'; end if;
    if NEW.responsable is distinct from OLD.responsable then raise exception 'Partner : changement de responsable interdit'; end if;
  end if;
  return NEW;
end $$;
drop trigger if exists trg_partner_mission_guard on public.missions;
create trigger trg_partner_mission_guard before update on public.missions
  for each row execute function public.partner_mission_guard();

-- =====================================================================
-- Maria-José Paquelier : auto-visibilité (elle se voit elle-même)
-- Son contact = 373, sa mission (ID 11) porte contact_consultant_id=373.
-- Ajoute 373 à SON périmètre partner (résout son uuid par le nom du profil).
insert into public.partner_consultants (partner_id, contact_consultant_id)
select p.id, 373 from public.profiles p
where p.role='partner' and p.nom ilike '%paquelier%'
on conflict do nothing;

-- =====================================================================
-- ROLLBACK :
--   drop policy if exists ha_partner_update  on public.historique_actions;
--   drop policy if exists ha_partner_delete  on public.historique_actions;
--   drop policy if exists hm_partner_update  on public.historique_missions;
--   drop policy if exists hm_partner_delete  on public.historique_missions;
--   drop policy if exists taches_partner_delete on public.taches;
--   drop policy if exists mp_partner_delete   on public.mission_periods;
--   delete from public.partner_consultants pc using public.profiles p
--     where pc.partner_id=p.id and p.nom ilike '%paquelier%' and pc.contact_consultant_id=373;
