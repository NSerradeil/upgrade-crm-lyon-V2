-- 47_domaine_task_types.sql -- 2026-09-22
-- Parallelisation navigateur (chantier builder) : le scheduler ne doit plus traiter
-- TOUTE tache needs_browser comme un seul et meme verrou global (browser_busy). On
-- introduit un domaine par type de tache navigateur : au plus UNE tache par
-- domaine a la fois, mais deux domaines DIFFERENTS peuvent tourner en meme temps
-- (ex. plateformes + linkedin). linkedin reste un cas a part : jamais deux taches
-- linkedin simultanees, contrainte non negociable liee au gouverneur de quota global
-- (bin/jules-lk-governor.py), qui n'est PAS touche par ce chantier.
--
-- domaine = null pour les types qui n'utilisent pas le navigateur (needs_browser=false).

alter table public.agent_task_types
  add column if not exists domaine text;

alter table public.agent_task_types drop constraint if exists agent_task_types_domaine_check;
alter table public.agent_task_types
  add constraint agent_task_types_domaine_check
  check (domaine is null or domaine in ('linkedin', 'plateformes', 'autre'));

-- CORRECTION 22/09 (revue avant application) : la premiere version classait par motif de
-- nom, avec 'autre' en defaut. Deux types y tombaient a tort :
--   * chasse.sourcer  -> sourcing de profils SUR LINKEDIN. En 'autre', il aurait pu tourner
--     en meme temps qu'un campagne.envoyer : deux taches LinkedIn simultanees, exactement ce
--     que la contrainte « zero risque de ban » interdit.
--   * midday.cleanup  -> porte la passe d'hygiene Recruitee, qui ouvre LinkedIn (etape 7ter).
-- Le defaut sur est donc le PLUS RESTRICTIF : toute tache navigateur qui n'est pas
-- manifestement une plateforme fournisseur est traitee comme LinkedIn, donc serialisee. Se
-- tromper dans ce sens coute un peu de parallelisme ; se tromper dans l'autre coute un compte.
update public.agent_task_types
   set domaine = case
     when type ilike '%plateforme%' or type ilike 'scan.%' then 'plateformes'
     else 'linkedin'
   end
 where needs_browser = true and domaine is null;

-- Un type qui n'utilise pas le navigateur n'a pas de domaine : le laisser a null evite
-- qu'il compte dans un quelconque verrou.
update public.agent_task_types set domaine = null where needs_browser is not true;

-- Verif :
--   select type, needs_browser, domaine from public.agent_task_types order by needs_browser desc, type;
-- Attendu : scan.plateformes -> plateformes ; campagne.*, lk.*, chasse.sourcer,
-- midday.cleanup -> linkedin ; tout le reste -> null.
