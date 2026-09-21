-- 38_task_type_categorie.sql — 2026-09-21
-- Le « Type » métier d'une mission (chasse/veille/relance/pilotage/admin) devient une DONNÉE
-- CONTRÔLÉE, portée par le type d'exécution (agent_task_types), au lieu d'être devinée par
-- mots-clés dans le CRM. Une valeur par type, gérée ici ; le CRM ne fait plus que lire.
-- Additif : colonne nullable + recrée agent_v_backlog pour l'exposer.

alter table public.agent_task_types
  add column if not exists categorie text
  check (categorie is null or categorie in ('chasse','veille','relance','pilotage','admin'));

update public.agent_task_types set categorie = v.cat from (values
  ('matin.brief',        'pilotage'),
  ('ronde.tour',         'pilotage'),
  ('bilan.vendredi',     'pilotage'),
  ('scan.plateformes',   'veille'),
  ('chasse.sourcer',     'chasse'),
  ('lk.envoyer',         'chasse'),
  ('lk.lire_acceptations','chasse'),
  ('crm.relancer',       'relance'),
  ('campagne.lire',      'chasse'),
  ('campagne.envoyer',   'chasse'),
  ('campagne.alimenter', 'chasse'),
  ('libre',              'admin')
) as v(type, cat) where public.agent_task_types.type = v.type;

-- Backlog : on rattache la catégorie du task_type de la mission (null pour un one-shot sans type).
-- categorie ajoutée EN DERNIER : CREATE OR REPLACE VIEW n'autorise que l'ajout en fin.
create or replace view public.agent_v_backlog as
  select m.id, m.titre, m.kind, m.statut, m.priorite, m.contexte, m.updated_at,
         count(t.id) filter (where t.statut = 'due')        as nb_due,
         count(t.id) filter (where t.statut = 'claimed')    as nb_claimed,
         count(t.id) filter (where t.statut = 'waiting_go') as nb_waiting_go,
         count(t.id) filter (where t.statut = 'failed')     as nb_failed,
         count(t.id) filter (where t.statut = 'done')       as nb_done,
         tt.categorie
    from public.agent_missions m
    left join public.agent_tasks t on t.mission_id = m.id
    left join public.agent_task_types tt on tt.type = m.task_type
   where m.statut in ('active','paused')
   group by m.id, tt.categorie;
alter view public.agent_v_backlog set (security_invoker = on);

-- Vérif :
--   select type, categorie from public.agent_task_types order by categorie, type;
--   select id, titre, kind, categorie from public.agent_v_backlog limit 10;
