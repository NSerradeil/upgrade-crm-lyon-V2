-- 43_agent_v_journee_task_id.sql — 2026-09-21
-- Reprend db/41 (3 couloirs) et expose l'id de la tâche (task_id) en dernière colonne, pour que
-- le panneau d'une tâche « en cours » (frise) puisse charger son ACTIVITÉ (journal/events +
-- heartbeat + result) — sinon on ne voyait que « heure prévue + mission », pas ce qui est fait.
-- Additif : lecture seule. task_id = null pour les relances de séquence (pas des agent_tasks).
drop view if exists public.agent_v_journee;
create view public.agent_v_journee as
with occ as (
  select m.id as mission_id, m.titre,
         ((current_date + (t.time)::time) at time zone 'Europe/Paris') as prevu_at
    from public.agent_missions m
    cross join lateral jsonb_array_elements_text(m.cadence->'times') as t(time)
   where m.kind = 'recurring' and m.statut = 'active'
     and m.task_type in ('matin.brief','ronde.tour','scan.plateformes','bilan.vendredi')
     and (
       m.cadence->'days' is null
       or (extract(isodow from current_date)::int) in (
            select (d)::int from jsonb_array_elements_text(m.cadence->'days') as d
          )
     )
),
tache_du_jour as (
  select t.id, t.mission_id, t.titre, t.due_at, t.statut, m.kind, m.titre as mission_titre
    from public.agent_tasks t
    left join public.agent_missions m on m.id = t.mission_id
   where t.due_at >= current_date and t.due_at < current_date + interval '1 day'
     and t.statut <> 'cancelled'
)
select o.mission_id, o.titre, o.prevu_at, 'routine'::text as famille,
       case
         when td.statut = 'done'                     then 'done'
         when td.statut in ('claimed','waiting_go')  then 'running'
         when td.statut = 'failed'                   then 'failed'
         else 'pending'
       end as etat,
       td.id as task_id
  from occ o
  left join lateral (
    select statut, id
      from tache_du_jour td
     where td.mission_id = o.mission_id
       and td.due_at >= o.prevu_at - interval '90 min'
       and td.due_at <  o.prevu_at + interval '90 min'
     order by td.due_at desc
     limit 1
  ) td on true

union all

select td.mission_id,
       coalesce(nullif(td.titre,''), td.mission_titre) as titre,
       td.due_at as prevu_at,
       case when td.kind = 'campagne' then 'campagne' else 'ponctuelle' end as famille,
       case
         when td.statut = 'done'                     then 'done'
         when td.statut in ('claimed','waiting_go')  then 'running'
         when td.statut = 'failed'                   then 'failed'
         else 'pending'
       end as etat,
       td.id as task_id
  from tache_du_jour td
 where td.mission_id is null
    or td.mission_id not in (select mission_id from occ)

union all

select s.mission_id,
       s.target_label || ' (étape ' || s.etape || ')' as titre,
       s.next_due_at as prevu_at,
       'campagne'::text as famille,
       'pending'::text  as etat,
       null::uuid       as task_id
  from public.agent_sequences s
 where s.statut = 'active'
   and s.next_due_at >= current_date
   and s.next_due_at <  current_date + interval '1 day'

 order by 3;

alter view public.agent_v_journee set (security_invoker = on);

-- Vérif :
--   select famille, task_id, titre from public.agent_v_journee order by prevu_at;
