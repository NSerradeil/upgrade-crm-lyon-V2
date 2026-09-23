-- 48 — Pause d'un suivi de campagne (barre de transport du cockpit Jules)
--
-- Nicolas 23/09 : sur chaque personne suivie, une barre façon platine hifi
-- (⏮ étape précédente · ⏭ étape suivante · ⏸ pause · ⏹ sortir). La pause est le seul
-- geste qui n'existait pas en base : « c'est les vacances, on suspend » n'est ni un arrêt
-- (on ne perd pas la personne) ni un suivi actif (aucune relance ne doit partir).
--   • statut 'paused'  : plus aucune relance ne part, la séquence reste dans la campagne.
--   • resume_at        : facultatif. Renseigné, la séquence repart TOUTE SEULE à cette date.
-- L'historique des gestes manuels (et leur raison) vit dans agent_events (sequence_id) et
-- dans `notes` — pas de table de plus : c'est déjà ce que le panneau de détail affiche.

alter table public.agent_sequences
  drop constraint if exists agent_sequences_statut_check;
alter table public.agent_sequences
  add constraint agent_sequences_statut_check
  check (statut in ('active','replied','paused','stopped','converted'));

alter table public.agent_sequences
  add column if not exists resume_at timestamptz;

comment on column public.agent_sequences.resume_at is
  'Pause : date de reprise automatique. NULL = pause indéfinie, reprise à la main.';

create index if not exists agent_sequences_reprise_idx
  on public.agent_sequences (statut, resume_at) where statut = 'paused';

-- Reprise automatique : idempotente, sans paramètre, appelable à chaque tick par qui lit
-- les séquences (cockpit toutes les 30 s, outil MCP agent_sequence_due_today). Une pause
-- dont la date de reprise est passée redevient un suivi actif, et le dit dans le journal.
create or replace function public.agent_sequences_reprendre_dues()
returns integer
language plpgsql
security invoker
as $$
declare n integer := 0;
begin
  with repris as (
    update public.agent_sequences
       set statut = 'active', resume_at = null, updated_at = now()
     where statut = 'paused'
       and resume_at is not null
       and resume_at <= now()
    returning id, mission_id, target_label, owner_id
  )
  insert into public.agent_events (owner_id, actor, kind, sequence_id, mission_id, message)
  select owner_id, 'crm', 'sequence.resumed', id, mission_id,
         target_label || ' — reprise automatique (fin de pause)'
    from repris;
  get diagnostics n = row_count;
  return n;
end;
$$;

-- Vérif :
--   select statut, count(*) from public.agent_sequences group by statut;
--   select public.agent_sequences_reprendre_dues();
