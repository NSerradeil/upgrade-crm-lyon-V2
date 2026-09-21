-- 36_agent_v_journee.sql — 2026-09-21
-- Les passages cycliques du jour et leur état résolu, pour la frise horaire de l'onglet Jules
-- (spec §5.2). Une mission recurring porte une cadence {"days":[1..7],"times":["07:00","16:00"]}
-- (jours ISO, lundi=1). On déplie les heures du jour si le jour ISO courant est dans days, puis
-- on rattache la tâche du jour (même mission, ±90 min) pour résoudre l'état.
-- Additif : lecture seule, ne modifie aucune donnée.

create or replace view public.agent_v_journee as
with occ as (
  select m.id as mission_id, m.titre,
         (current_date + (t.time)::time) as prevu_at
    from public.agent_missions m
    cross join lateral jsonb_array_elements_text(m.cadence->'times') as t(time)
   where m.kind = 'recurring' and m.statut = 'active'
     and (
       m.cadence->'days' is null
       or (extract(isodow from current_date)::int) in (
            select (d)::int from jsonb_array_elements_text(m.cadence->'days') as d
          )
     )
),
tache_du_jour as (
  select mission_id, due_at, statut
    from public.agent_tasks
   where due_at >= current_date and due_at < current_date + interval '1 day'
)
select o.mission_id, o.titre, o.prevu_at,
       case
         when td.statut = 'done'                    then 'done'
         when td.statut in ('claimed','waiting_go')  then 'running'
         when td.statut = 'failed'                   then 'failed'
         else 'pending'
       end as etat
  from occ o
  left join lateral (
    select statut
      from tache_du_jour td
     where td.mission_id = o.mission_id
       and td.due_at >= o.prevu_at - interval '90 min'
       and td.due_at <  o.prevu_at + interval '90 min'
     order by td.due_at desc
     limit 1
  ) td on true
 order by o.prevu_at;

alter view public.agent_v_journee set (security_invoker = on);

-- Vérif :
--   select * from public.agent_v_journee order by prevu_at;
