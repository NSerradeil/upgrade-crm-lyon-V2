-- db/25_agent_noyau.sql — Noyau d'état Jules : missions, tâches réclamables, séquences,
-- campagnes, parapheur, événements. À coller dans le SQL Editor Supabase. Idempotent.
-- Spec : ~/Pro/Jules/docs/superpowers/specs/2026-09-17-noyau-etat-jules-design.md
-- Tables en public.agent_* (pas de schéma dédié : PostgREST n'expose que public).
begin;

alter table public.profiles add column if not exists jules_enabled boolean not null default false;
comment on column public.profiles.jules_enabled is 'Affiche l''onglet Jules du CRM et autorise la création de missions agent_*.';

-- 1) Missions ----------------------------------------------------------------
create table if not exists public.agent_missions (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references public.profiles(id),
  titre        text not null,
  kind         text not null default 'oneshot' check (kind in ('oneshot','recurring')),
  statut       text not null default 'active' check (statut in ('active','paused','done','cancelled')),
  cadence      jsonb,                         -- {"days":[1,2,3,4,5],"times":["10:00","16:00"]}
  task_type    text,                          -- type de la tâche engendrée à chaque occurrence (recurring)
  task_payload jsonb not null default '{}'::jsonb,
  contexte     text,
  priorite     smallint not null default 2 check (priorite between 1 and 3),
  besoin_id    text,
  recruitee_offer_id text,
  campaign_id  uuid,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- 2) Types de tâches (liste fermée) -------------------------------------------
create table if not exists public.agent_task_types (
  type          text primary key,
  description   text not null,
  needs_browser boolean not null default false,
  default_model text not null default 'sonnet',
  payload_keys  text[] not null default '{}'   -- clés obligatoires du payload
);
insert into public.agent_task_types (type, description, needs_browser, default_model, payload_keys) values
  ('ronde.tour',       'Ronde : Slack, mails, calendrier, CRM, vault',           false, 'sonnet', '{}'),
  ('matin.brief',      'Brief du matin + todo CRM du jour',                      false, 'sonnet', '{}'),
  ('bilan.vendredi',   'Bilan de la semaine',                                    false, 'sonnet', '{}'),
  ('scan.plateformes', 'Scan des plateformes fournisseur',                       true,  'sonnet', '{}'),
  ('chasse.sourcer',   'Sourcer des profils pour une mission de chasse',         true,  'sonnet', '{mission_titre}'),
  ('lk.envoyer',       'Envoyer invitations/messages LinkedIn validés',          true,  'sonnet', '{sequence_ids}'),
  ('lk.lire_acceptations', 'Lire les acceptations/réponses LinkedIn',            true,  'haiku',  '{}'),
  ('crm.relancer',     'Relance mail/CRM d''un contact',                         false, 'sonnet', '{contact_id}'),
  ('libre',            'Mission décrite en texte libre dans payload.instruction', false, 'sonnet', '{instruction}')
on conflict (type) do update set description = excluded.description,
  needs_browser = excluded.needs_browser, default_model = excluded.default_model, payload_keys = excluded.payload_keys;

-- 3) Tâches ------------------------------------------------------------------
create table if not exists public.agent_tasks (
  id             uuid primary key default gen_random_uuid(),
  owner_id       uuid not null default auth.uid() references public.profiles(id),
  mission_id     uuid references public.agent_missions(id),
  parent_task_id uuid references public.agent_tasks(id),
  crm_task_id    text,                       -- public.taches.id, convergence future onglet Tâches
  type           text not null references public.agent_task_types(type),
  titre          text not null,
  payload        jsonb not null default '{}'::jsonb,
  due_at         timestamptz not null default now(),
  priorite       smallint not null default 2 check (priorite between 1 and 3),
  statut         text not null default 'due' check (statut in ('due','claimed','waiting_go','done','failed','cancelled')),
  leased_by      text,
  lease_until    timestamptz,
  heartbeat_at   timestamptz,
  attempts       smallint not null default 0,
  result         jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists agent_tasks_claim_idx on public.agent_tasks (statut, due_at, priorite);
create index if not exists agent_tasks_mission_idx on public.agent_tasks (mission_id);

-- 4) Campagnes ---------------------------------------------------------------
create table if not exists public.agent_campaigns (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null default auth.uid() references public.profiles(id),
  titre           text not null,
  objectif        text,
  target_criteria jsonb not null default '{}'::jsonb,
  templates       jsonb not null default '{}'::jsonb,
  constraints     jsonb not null default '{}'::jsonb,
  quotas          jsonb not null default '{}'::jsonb,
  review_profiles boolean not null default true,
  autonomy        text not null default 'assistee' check (autonomy in ('assistee','revue_profils','autonome')),
  preset          text,
  statut          text not null default 'draft' check (statut in ('draft','active','paused','done','cancelled')),
  validated_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
alter table public.agent_missions drop constraint if exists agent_missions_campaign_fk;
alter table public.agent_missions add constraint agent_missions_campaign_fk
  foreign key (campaign_id) references public.agent_campaigns(id);

-- 5) Séquences (état par personne) --------------------------------------------
create table if not exists public.agent_sequences (
  id           uuid primary key default gen_random_uuid(),
  owner_id     uuid not null default auth.uid() references public.profiles(id),
  campaign_id  uuid not null references public.agent_campaigns(id),
  target_kind  text not null check (target_kind in ('contact_crm','candidat_recruitee','externe')),
  target_ref   text not null,
  target_label text not null,
  etape        smallint not null default 0,
  next_due_at  timestamptz,
  nb_relances  smallint not null default 0,
  sent_at      timestamptz,
  accepted_at  timestamptz,
  replied_at   timestamptz,
  sentiment    text check (sentiment is null or sentiment in ('positif','neutre','negatif')),
  statut       text not null default 'active' check (statut in ('active','replied','stopped','converted')),
  notes        text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (campaign_id, target_kind, target_ref)
);
create index if not exists agent_sequences_due_idx on public.agent_sequences (statut, next_due_at);

-- 6) Parapheur ---------------------------------------------------------------
create table if not exists public.agent_approvals (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null default auth.uid() references public.profiles(id),
  nature     text not null check (nature in ('go','decision','bloque')),
  titre      text not null,
  detail     text,
  options    jsonb,
  task_id    uuid references public.agent_tasks(id),
  statut     text not null default 'pending' check (statut in ('pending','approved','rejected','answered')),
  decision   text,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

-- 7) Événements --------------------------------------------------------------
create table if not exists public.agent_events (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null default auth.uid() references public.profiles(id),
  at          timestamptz not null default now(),
  actor       text not null,
  kind        text not null,
  task_id     uuid,
  mission_id  uuid,
  sequence_id uuid,
  data        jsonb,
  message     text
);
create index if not exists agent_events_at_idx on public.agent_events (owner_id, at desc);
create table if not exists public.agent_events_daily (
  owner_id   uuid not null references public.profiles(id),
  jour       date not null,
  mission_id uuid,
  nb_events  int not null,
  resume     text,
  primary key (owner_id, jour, mission_id)
);

-- 8) updated_at ----------------------------------------------------------------
create or replace function public.agent_touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
do $$ declare t text; begin
  foreach t in array array['agent_missions','agent_tasks','agent_campaigns','agent_sequences'] loop
    execute format('drop trigger if exists %I_touch on public.%I', t, t);
    execute format('create trigger %I_touch before update on public.%I for each row execute function public.agent_touch_updated_at()', t, t);
  end loop; end $$;

-- 9) Claim atomique et reprise ------------------------------------------------
create or replace function public.agent_claim_task(p_worker text, p_lease_minutes int default 20)
returns setof public.agent_tasks language plpgsql security invoker as $$
declare r public.agent_tasks;
begin
  select * into r from public.agent_tasks
   where statut = 'due' and due_at <= now() and owner_id = auth.uid()
   order by priorite, due_at
   for update skip locked limit 1;
  if not found then return; end if;
  update public.agent_tasks
     set statut = 'claimed', leased_by = p_worker,
         lease_until = now() + make_interval(mins => p_lease_minutes), heartbeat_at = now()
   where id = r.id returning * into r;
  insert into public.agent_events (actor, kind, task_id, mission_id, message)
  values (p_worker, 'task.claimed', r.id, r.mission_id, r.titre);
  return next r;
end $$;

create or replace function public.agent_reclaim_expired(p_max_attempts int default 3)
returns int language plpgsql security invoker as $$
declare n int;
begin
  with expired as (
    update public.agent_tasks
       set attempts = attempts + 1,
           statut = case when attempts + 1 >= p_max_attempts then 'failed' else 'due' end,
           leased_by = null, lease_until = null
     where statut = 'claimed' and lease_until < now() and owner_id = auth.uid()
     returning id, mission_id, statut, titre, leased_by)
  insert into public.agent_events (actor, kind, task_id, mission_id, message)
  select 'sched', case when statut = 'failed' then 'task.failed' else 'task.reclaimed' end, id, mission_id, titre
    from expired;
  get diagnostics n = row_count;
  return n;
end $$;

-- 10) Vues ---------------------------------------------------------------------
create or replace view public.agent_v_encours as
  select t.id, t.titre, t.type, t.mission_id, m.titre as mission_titre, t.leased_by, t.heartbeat_at,
         extract(epoch from now() - t.heartbeat_at)::int as heartbeat_age_s
    from public.agent_tasks t left join public.agent_missions m on m.id = t.mission_id
   where t.statut = 'claimed';
create or replace view public.agent_v_parapheur as
  select id, nature, titre, detail, options, task_id, created_at from public.agent_approvals
   where statut = 'pending'
   order by case nature when 'bloque' then 0 when 'decision' then 1 else 2 end, created_at;
create or replace view public.agent_v_backlog as
  select m.id, m.titre, m.kind, m.statut, m.priorite, m.contexte, m.updated_at,
         count(t.id) filter (where t.statut = 'due')        as nb_due,
         count(t.id) filter (where t.statut = 'claimed')    as nb_claimed,
         count(t.id) filter (where t.statut = 'waiting_go') as nb_waiting_go,
         count(t.id) filter (where t.statut = 'failed')     as nb_failed,
         count(t.id) filter (where t.statut = 'done')       as nb_done
    from public.agent_missions m left join public.agent_tasks t on t.mission_id = m.id
   where m.statut in ('active','paused')
   group by m.id;
create or replace view public.agent_v_due_today as
  select 'task' as kind, id, titre, due_at as due, priorite from public.agent_tasks
   where statut = 'due' and due_at < (current_date + 1)::timestamptz
  union all
  select 'sequence', id, target_label || ' (étape ' || etape || ')', next_due_at, 2 from public.agent_sequences
   where statut = 'active' and next_due_at < (current_date + 1)::timestamptz;

-- 11) RLS ------------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['agent_missions','agent_tasks','agent_campaigns','agent_sequences','agent_approvals','agent_events','agent_events_daily'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I_owner_all on public.%I', t, t);
    execute format('create policy %I_owner_all on public.%I for all using (owner_id = auth.uid()) with check (owner_id = auth.uid())', t, t);
  end loop; end $$;
alter table public.agent_task_types enable row level security;
drop policy if exists agent_task_types_read on public.agent_task_types;
create policy agent_task_types_read on public.agent_task_types for select using (true);

-- 12) Activer Jules pour Nicolas -------------------------------------------------
update public.profiles set jules_enabled = true where email = 'nicolas.serradeil@upgrade.fr';

commit;
