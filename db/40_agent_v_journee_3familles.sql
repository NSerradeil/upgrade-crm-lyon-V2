-- 40_agent_v_journee_3familles.sql — 2026-09-21
-- La frise « Ce qui tourne » passe en TROIS couloirs : ponctuelles / routines / campagnes.
-- Jusqu'ici la vue ne rendait que le rythme opératoire (37) : on ne voyait pas ce que Jules
-- fait AUJOURD'HUI hors routine (une chasse lancée ce matin, un envoi de campagne à 14h).
-- On ajoute donc une colonne `famille` et deux sources de plus, toutes deux tirées des tâches
-- datées du jour. Additif : lecture seule, ne modifie aucune donnée.
--   famille = 'routine'    → occurrences de cadence des missions recurring de rythme
--   famille = 'ponctuelle' → tâches du jour d'une mission oneshot (ou sans mission)
--   famille = 'campagne'   → tâches du jour d'une mission kind='campagne'

-- La colonne prevu_at change de type (timestamp -> timestamptz) : create or replace ne
-- suffit pas, il faut déposer la vue d'abord. Aucune donnée, aucune dépendance.
drop view if exists public.agent_v_journee;
create view public.agent_v_journee as
with occ as (
  select m.id as mission_id, m.titre,
         -- timestamptz, comme les deux autres branches : une UNION exige un type unique,
         -- et Postgres refuse de changer le type d'une colonne de vue sans drop (d'où le
         -- drop view ci-dessus). L'heure de cadence est une heure de Paris.
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

union all

-- Ponctuelles et campagnes : une tâche datée du jour = un pin. On exclut les tâches déjà
-- portées par le couloir « routine » (missions de rythme), pour ne pas les compter deux fois.
select td.mission_id,
       coalesce(nullif(td.titre,''), td.mission_titre) as titre,
       td.due_at as prevu_at,
       case when td.kind = 'campagne' then 'campagne' else 'ponctuelle' end as famille,
       case
         when td.statut = 'done'                     then 'done'
         when td.statut in ('claimed','waiting_go')  then 'running'
         when td.statut = 'failed'                   then 'failed'
         else 'pending'
       end as etat
  from tache_du_jour td
 where td.mission_id is null
    or td.mission_id not in (select mission_id from occ)
 order by 3;

alter view public.agent_v_journee set (security_invoker = on);

-- Vérif :
--   select famille, count(*) from public.agent_v_journee group by 1;
--   select * from public.agent_v_journee order by famille, prevu_at;
