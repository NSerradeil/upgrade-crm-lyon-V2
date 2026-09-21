-- 35_agent_approval_critique.sql — 2026-09-21
-- Criticité explicite d'une approbation (défaut : non critique). L'onglet Jules colore la
-- carte en rouge et la remonte en tête ; un filet côté UI bascule aussi sur l'âge (spec §5.1).
-- Additif : n'altère aucune donnée existante (colonne à défaut false).
-- (Numéro 35 : 34 est pris par 34_agent_playbook_brief.sql d'une autre session.)

alter table public.agent_approvals
  add column if not exists critique boolean not null default false;

create or replace view public.agent_v_parapheur as
  select id, nature, titre, detail, options, task_id, critique, created_at
    from public.agent_approvals
   where statut = 'pending'
   order by critique desc,
            case nature when 'bloque' then 0 when 'decision' then 1 else 2 end,
            created_at;

alter view public.agent_v_parapheur set (security_invoker = on);

-- Vérif :
--   select column_name from information_schema.columns
--    where table_name='agent_approvals' and column_name='critique';
--   select id, critique from public.agent_v_parapheur limit 5;
