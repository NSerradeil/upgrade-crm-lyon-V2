-- db/31_agent_types_campagne.sql — Types de tâches pour les campagnes autonomes.
-- Trois types : lire (acceptations/réponses), envoyer (invitations/relances), alimenter (vivier).
-- À coller dans le SQL Editor Supabase. Idempotent.
-- Spec : ~/Pro/Jules/.superpowers/sdd/2026-09-18-campagnes-autonomes/task-4-brief.md
begin;

-- Types de tâches pour les campagnes autonomes ----------------------------------
insert into public.agent_task_types (type, description, needs_browser, default_model, payload_keys, skill_path) values
  ('campagne.lire',      'Lire les acceptations et réponses d''une campagne', true, 'sonnet', '{mission_id}', 'routines/campagne-boucle.md'),
  ('campagne.envoyer',   'Envoyer les invitations, accroches et relances dues',  true, 'sonnet', '{mission_id}', 'routines/campagne-boucle.md'),
  ('campagne.alimenter', 'Compléter le vivier de la campagne',                 true, 'sonnet', '{mission_id}', 'routines/campagne-boucle.md')
on conflict (type) do update set
  description = excluded.description,
  needs_browser = excluded.needs_browser,
  default_model = excluded.default_model,
  payload_keys = excluded.payload_keys,
  skill_path = excluded.skill_path;

commit;

-- Vérification après application : select type, description, needs_browser, default_model, payload_keys, skill_path from public.agent_task_types order by type;
-- Résultat attendu : 12 types (les 9 du noyau + 0 de fusion + 3 campagne)
--   bilan.vendredi          | Bilan de la semaine                                       | false | sonnet | {} | memoire/format-bilan-semaine.md
--   campagne.alimenter      | Compléter le vivier de la campagne                      | true  | sonnet | {mission_id} | routines/campagne-boucle.md
--   campagne.envoyer        | Envoyer les invitations, accroches et relances dues     | true  | sonnet | {mission_id} | routines/campagne-boucle.md
--   campagne.lire           | Lire les acceptations et réponses d'une campagne       | true  | sonnet | {mission_id} | routines/campagne-boucle.md
--   chasse.sourcer          | Sourcer des profils pour une mission de chasse         | true  | sonnet | {mission_titre} | routines/chasse-candidat.md
--   crm.relancer            | Relance mail/CRM d'un contact                          | false | sonnet | {contact_id} | (null)
--   lk.envoyer              | Envoyer invitations/messages LinkedIn validés           | true  | sonnet | {sequence_ids} | routines/chasse-ref-linkedin.md
--   lk.lire_acceptations    | Lire les acceptations/réponses LinkedIn                 | true  | haiku  | {} | routines/chasse-ref-linkedin.md
--   libre                   | Mission décrite en texte libre dans payload.instruction | false | sonnet | {instruction} | (null)
--   matin.brief             | Brief du matin + todo CRM du jour                       | false | sonnet | {} | skill:brief-du-jour
--   ronde.tour              | Ronde : Slack, mails, calendrier, CRM, vault          | false | sonnet | {} | routines/ronde.md
--   scan.plateformes        | Scan des plateformes fournisseur                       | true  | sonnet | {} | skill:scan-plateformes
