-- 39_agent_slack_amorces.sql — 2026-09-21
-- Relais CRM → Slack (spec §4, « discuter avec Jules »). Un bouton du CRM écrit ici une
-- « amorce » ; le pont Slack (démon) la détecte, la poste dans le DM de Nicolas avec le
-- contexte, et la réponse relance Jules AVEC ce contexte (mission_id) — pour qu'une tâche
-- créée derrière reste dans la même mission par défaut.
-- Le CRM ne parle jamais directement à Slack : il écrit une ligne, le pont s'en charge.

create table if not exists public.agent_slack_amorces (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null default auth.uid() references public.profiles(id),
  kind        text not null check (kind in ('approval','mission','task','mission_create','free')),
  ref_id      text,                       -- id de l'appro / mission / tâche concernée (selon kind)
  mission_id  uuid references public.agent_missions(id),  -- héritage : la suite reste dans cette mission
  titre       text not null,              -- ce sur quoi on rebondit (affiché dans le DM)
  contexte    text,                       -- résumé humain optionnel
  statut      text not null default 'pending' check (statut in ('pending','posted','done','error')),
  slack_channel text,                     -- DM où l'amorce a été postée
  slack_ts    text,                       -- ts du message d'amorce (racine du fil de réponse)
  erreur      text,
  created_at  timestamptz not null default now(),
  posted_at   timestamptz
);
create index if not exists agent_slack_amorces_pending_idx
  on public.agent_slack_amorces (statut, created_at) where statut = 'pending';

alter table public.agent_slack_amorces enable row level security;
drop policy if exists agent_slack_amorces_owner_all on public.agent_slack_amorces;
create policy agent_slack_amorces_owner_all on public.agent_slack_amorces
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- Vérif :
--   insert into public.agent_slack_amorces (kind, titre) values ('free','test');
--   select id, kind, titre, statut from public.agent_slack_amorces order by created_at desc limit 3;
