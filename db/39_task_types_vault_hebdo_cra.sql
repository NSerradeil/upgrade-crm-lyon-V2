-- db/39_task_types_vault_hebdo_cra.sql — 2026-09-21
-- Migration "ancien monde (SKILLs + plists launchd) → noyau d'état CRM" pour les
-- routines restées en plan après le commit 5ac4ef3 (18/09, pools de leads) :
--   1) midday.cleanup   — nettoyage vault 12h (remplace le plist com.upgrade.jules.vault-midday)
--                          INCLUT l'hygiène Recruitee (§7ter du skill) : Nicolas a tranché le
--                          29/07/2026 (cf. routines/hygiene-fiches-recruitee.md § "Quand elle
--                          tourne") qu'elle reste accrochée au midday, pas une tâche séparée,
--                          pour que le débrief parte dans le même message Slack. On ne recrée
--                          donc PAS de task_type recruitee.hygiene à côté — ça romprait cette
--                          décision et doublerait le run (deux workers sur le même vault/CRM).
--   2) prep.point_lyon   — prépa point Lyon du lundi (Nicolas/Pierre)
--   3) prep.point_france — prépa point France du vendredi
--   4) cra.relance       — relance CRA mensuelle (le 20, avec validation préalable de la liste)
--
-- midday.cleanup a needs_browser=true : le skill fait de la vérification LinkedIn (contacts
-- incomplets) ET la passe LinkedIn de l'hygiène Recruitee qu'il embarque désormais.
--
-- cra.relance utilise la cadence mensuelle {"dom":[20],"times":[...]} — support ajouté dans
-- bin/agentcadence.py et dans le schéma zod de agent_mission_create/update (agent-tools.mjs,
-- CRM_VERSION 8.23.0). Les 3 autres restent en cadence hebdo classique {"days":[...]}.
--
-- À coller dans le SQL Editor Supabase. Idempotent.
begin;

insert into public.agent_task_types (type, description, needs_browser, default_model, payload_keys, skill_path, categorie) values
  ('midday.cleanup',    'Nettoyage structurel + enrichissement web du vault Obsidian (12h), hygiène Recruitee incluse (§7ter)', true, 'sonnet', '{}', 'skill:midday-cleanup', 'pilotage'),
  ('prep.point_lyon',   'Prépa du point Lyon du lundi (Nicolas/Pierre)',                                                       false, 'sonnet', '{}', 'routines/prep-points-hebdo.md', 'pilotage'),
  ('prep.point_france', 'Prépa du point France du vendredi',                                                                   false, 'sonnet', '{}', 'routines/prep-points-hebdo.md', 'pilotage'),
  ('cra.relance',       'Relance CRA mensuelle (le 20) — liste à valider avant tout envoi',                                    false, 'sonnet', '{}', 'routines/relances-cra-mensuelles.md', 'relance')
on conflict (type) do update set description = excluded.description,
  needs_browser = excluded.needs_browser, default_model = excluded.default_model,
  payload_keys = excluded.payload_keys, skill_path = excluded.skill_path, categorie = excluded.categorie;

commit;

-- Vérification après application :
--   select type, skill_path, needs_browser, categorie from public.agent_task_types
--   where type in ('midday.cleanup','prep.point_lyon','prep.point_france','cra.relance');
--
-- Note midday.cleanup : skill_path garde le préfixe `skill:` (convention du prompt de
-- l'ordonnanceur, cf. build_prompt dans bin/jules-scheduler.py) car le skill vit dans
-- ~/Pro/03_Outils-IA/SKILLs/midday-cleanup/SKILL.md, partagé avec l'agence — on ne le
-- rapatrie PAS dans routines/ (contrainte du chantier du 21/09), contrairement à
-- scan.plateformes et matin.brief qui, eux, ont un playbook versionné dans routines/.
