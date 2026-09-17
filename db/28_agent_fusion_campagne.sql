-- db/28_agent_fusion_campagne.sql — fusion campagne → mission (décision Nicolas 17/09) :
-- une mission peut être kind='campagne' et porte un bloc config jsonb (cible, gabarits,
-- contraintes, quotas, review_profiles, autonomy, preset). agent_sequences pointe désormais
-- mission_id (plus campaign_id). agent_campaigns disparaît (vérifiée vide via REST avant ce
-- script — bin/agentdb.py — le 17/09 : agent_campaigns et agent_sequences sont vides en prod).
-- Ajoute agent_task_types.skill_path (décision skills). À coller dans le SQL Editor Supabase.
-- Idempotent. Style db/25_agent_noyau.sql.
begin;

-- 1) Missions : kind accepte 'campagne', + colonne config -------------------
alter table public.agent_missions drop constraint if exists agent_missions_kind_check;
alter table public.agent_missions add constraint agent_missions_kind_check
  check (kind in ('oneshot', 'recurring', 'campagne'));

alter table public.agent_missions add column if not exists config jsonb not null default '{}'::jsonb;
comment on column public.agent_missions.config is
  'Mission kind=campagne : target_criteria, templates, constraints, quotas, review_profiles (bool), autonomy (assistee|revue_profils|autonome), preset, validated_at.';

-- 2) Retrait du lien vers agent_campaigns ------------------------------------
alter table public.agent_missions drop constraint if exists agent_missions_campaign_fk;
alter table public.agent_missions drop column if exists campaign_id;

-- 3) Séquences : campaign_id → mission_id ------------------------------------
alter table public.agent_sequences add column if not exists mission_id uuid references public.agent_missions(id);
-- Pas de migration de données : campaign_id référençait agent_campaigns.id, un espace d'ids
-- disjoint de agent_missions.id — un simple `update … set mission_id = campaign_id` n'aurait
-- aucun sens. La table est vide en prod (vérifié le 17/09 via bin/agentdb.py) : rien à porter.
do $$
begin
  if (select count(*) from public.agent_sequences) = 0 then
    alter table public.agent_sequences drop constraint if exists agent_sequences_campaign_id_key;
    alter table public.agent_sequences drop column if exists campaign_id;
    alter table public.agent_sequences alter column mission_id set not null;
  else
    raise exception 'agent_sequences non vide (%) : fusion campagne→mission à revoir avant de continuer', (select count(*) from public.agent_sequences);
  end if;
end $$;
create unique index if not exists agent_sequences_mission_target_uidx
  on public.agent_sequences (mission_id, target_kind, target_ref);

-- 4) agent_campaigns disparaît (vérifiée vide) -------------------------------
-- to_regclass : au rejeu, la table n'existe déjà plus (droppée au 1er passage) —
-- un `select count(*) from public.agent_campaigns` échouerait alors avec
-- "relation agent_campaigns does not exist" et casserait toute la transaction.
do $$
begin
  if to_regclass('public.agent_campaigns') is not null then
    if (select count(*) from public.agent_campaigns) > 0 then
      raise exception 'agent_campaigns non vide (%) : ne pas dropper, migrer les données d''abord', (select count(*) from public.agent_campaigns);
    end if;
  end if;
end $$;
drop table if exists public.agent_campaigns;

-- 5) Types de tâches : skill_path ---------------------------------------------
alter table public.agent_task_types add column if not exists skill_path text;
update public.agent_task_types set skill_path = v.skill_path
  from (values
    ('ronde.tour',           'routines/ronde.md'),
    ('matin.brief',          'skill:brief-du-jour'),
    ('bilan.vendredi',       'memoire/format-bilan-semaine.md'),
    ('scan.plateformes',     'skill:scan-plateformes'),
    ('chasse.sourcer',       'routines/chasse-candidat.md'),
    ('lk.envoyer',           'routines/chasse-ref-linkedin.md'),
    ('lk.lire_acceptations', 'routines/chasse-ref-linkedin.md'),
    ('crm.relancer',         null),
    ('libre',                null)
  ) as v(type, skill_path)
  where public.agent_task_types.type = v.type;

-- 6) Vue agent_v_campagnes : missions kind=campagne + compteurs de séquences --
create or replace view public.agent_v_campagnes as
  select m.id, m.titre, m.statut, m.priorite, m.config, m.updated_at,
         count(s.id) filter (where s.statut = 'active')    as nb_active,
         count(s.id) filter (where s.statut = 'replied')   as nb_replied,
         count(s.id) filter (where s.statut = 'stopped')   as nb_stopped,
         count(s.id) filter (where s.statut = 'converted') as nb_converted,
         count(s.id) filter (where s.statut = 'active' and s.next_due_at < (current_date + 1)::timestamptz) as nb_due_today
    from public.agent_missions m left join public.agent_sequences s on s.mission_id = m.id
   where m.kind = 'campagne'
   group by m.id;

commit;
