-- db/01 — table interco_imputations + contrainte unique (exécuté dans Supabase SQL Editor le 2026-06-27)
create table if not exists public.interco_imputations (
  id bigint generated always as identity primary key,
  contact_consultant_id bigint not null references public.contacts(id) on delete cascade,
  annee int not null check (annee between 2000 and 2100),
  mois int not null check (mois between 1 and 12),
  jours numeric(5,2) not null default 0 check (jours >= 0),
  cjm_snapshot numeric(10,2),
  updated_by text,
  updated_at timestamptz not null default now(),
  unique (contact_consultant_id, annee, mois)
);
create index if not exists idx_interco_annee_mois on public.interco_imputations (annee, mois);
create index if not exists idx_interco_consultant on public.interco_imputations (contact_consultant_id);
