-- db/02 — RLS interco_imputations (exécuté dans Supabase SQL Editor le 2026-06-27)
-- profiles.id = auth.uid() (convention Supabase). Colonnes : nom, agence, role.
alter table public.interco_imputations enable row level security;

-- READ : tout utilisateur authentifié
drop policy if exists interco_read_all on public.interco_imputations;
create policy interco_read_all on public.interco_imputations
  for select using (auth.role() = 'authenticated');

-- WRITE (insert/update/delete) :
--   agence du contact == agence user  OU  responsable du contact == nom user  OU  admin
drop policy if exists interco_write_agence_resp_admin on public.interco_imputations;
create policy interco_write_agence_resp_admin on public.interco_imputations
  for all
  using (
    exists (
      select 1
      from public.contacts c
      join public.profiles p on p.id = auth.uid()
      where c.id = interco_imputations.contact_consultant_id
        and ( c.agence = p.agence
              or c.responsable = p.nom
              or p.role = 'admin' )
    )
  )
  with check (
    exists (
      select 1
      from public.contacts c
      join public.profiles p on p.id = auth.uid()
      where c.id = interco_imputations.contact_consultant_id
        and ( c.agence = p.agence
              or c.responsable = p.nom
              or p.role = 'admin' )
    )
  );
