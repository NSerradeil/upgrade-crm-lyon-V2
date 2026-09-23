-- 49_agent_sequences_plateforme.sql — 2026-09-23
--
-- LE SCAN DEVIENT UNE CAMPAGNE (décision Nicolas 23/09).
-- Constat du matin : le scan est UNE tâche monolithique qui doit avaler 22 plateformes
-- d'affilée. Le worker en a fait 11 sur 21 et a abandonné le reste « faute de temps », en
-- écrivant « pas d'onglet ouvert » sur des plateformes qui étaient ouvertes. Une plateforme
-- sautée disparaît dans un tableau que personne ne relit.
--   → Une CAMPAGNE « Veille plateformes », une SÉQUENCE par plateforme, chacune avec son
--     playbook, sa cadence et son heure de passage. Un passage court et ciblé au lieu d'un
--     marathon ; une séquence en retard se voit dans le cockpit.
--
-- Le levier est `agent_sequences.target_kind`, jusqu'ici toujours une personne. Pas de
-- nouvelle table de suivi : une plateforme EST une cible suivie, comme une personne.
--
-- ⚠️ Ce qui change pour les séquences de PERSONNES : rien. Les colonnes ajoutées sont
-- nullables ou ont un défaut, la contrainte de target_kind est ÉLARGIE (jamais restreinte),
-- et le pattern d'étapes des personnes est inchangé. Les dizaines de séquences en cours
-- gardent leur historique, leur étape et leur échéance.
--
-- Idempotent. À coller dans le SQL Editor Supabase (cf. DEPLOY.md).
begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1) Une cible n'est plus forcément une personne
-- ════════════════════════════════════════════════════════════════════════════
alter table public.agent_sequences drop constraint if exists agent_sequences_target_kind_check;
alter table public.agent_sequences
  add constraint agent_sequences_target_kind_check
  check (target_kind in ('contact_crm','candidat_recruitee','externe','plateforme'));

comment on column public.agent_sequences.target_kind is
  'Nature de la cible suivie. contact_crm/candidat_recruitee/externe = une PERSONNE (parcours '
  'invitation → message → relances). plateforme = une plateforme de besoins (parcours ouverture '
  '→ liste des besoins → besoins ouverts → qualifiés au CRM). target_ref = l''id du manifeste '
  'routines/scan-plateformes/platforms.json.';

-- ════════════════════════════════════════════════════════════════════════════
-- 2) Le pattern d'étapes dépend du TYPE DE CIBLE
-- ════════════════════════════════════════════════════════════════════════════
-- Plutôt qu'empiler des cas particuliers dans l'affichage, on nomme les patterns une
-- fois, en base, et tout le monde lit la même table (cockpit, MCP, stat hebdo).
--
-- Pour une plateforme, l'étape n°2 « Liste des besoins » est le GATE DE COUVERTURE, et
-- c'est tout l'objet de ce chantier : le scan du 23/09 a calé exactement là sur 5
-- plateformes (onglet ouvert sur l'accueil, jamais descendu jusqu'à la liste). « Ouverte »
-- n'est PAS « couverte » : une plateforme dont on n'a pas atteint la liste n'a rien scanné.
create table if not exists public.agent_sequence_patterns (
  target_kind  text primary key,
  libelle      text not null,           -- comment on appelle une cible de ce type, au singulier
  libelle_plur text not null,           -- ... et au pluriel (titre de section du cockpit)
  etapes       text[] not null,         -- les étapes, dans l'ordre
  etape_gate   smallint,                -- nb d'étapes en deçà duquel le passage ne compte pas
  gate_libelle text                     -- ce qu'on dit quand le gate n'est pas franchi
);
insert into public.agent_sequence_patterns (target_kind, libelle, libelle_plur, etapes, etape_gate, gate_libelle) values
  ('personne',   'Personne',   'Personnes suivies',
     array['Invitation','Message','Relance 1','Relance 2'], null, null),
  ('plateforme', 'Plateforme', 'Plateformes suivies',
     array['Ouverte','Liste des besoins','Besoins ouverts','Qualifiés au CRM'], 2,
     'ouverte mais liste jamais atteinte — NON COUVERTE')
on conflict (target_kind) do update set
  libelle = excluded.libelle, libelle_plur = excluded.libelle_plur,
  etapes = excluded.etapes, etape_gate = excluded.etape_gate, gate_libelle = excluded.gate_libelle;

comment on table public.agent_sequence_patterns is
  'Cycle d''étapes par type de cible. ''personne'' vaut pour contact_crm/candidat_recruitee/externe '
  '(ses étapes réelles restent calculées depuis la cadence de la campagne : ce sont des libellés '
  'de référence). ''plateforme'' est le cycle du scan. etape_gate = nombre d''étapes en deçà '
  'duquel le passage NE COMPTE PAS comme une couverture.';

-- ════════════════════════════════════════════════════════════════════════════
-- 3) Cadence, heure de passage et playbook, propres à CHAQUE séquence
-- ════════════════════════════════════════════════════════════════════════════
-- Une campagne de personnes garde sa cadence de campagne (config.cadence.relances) : ces
-- colonnes restent nulles chez elles et ne changent rien. Une plateforme, elle, a son
-- propre rythme — Nicolas 23/09 : au départ TOUTES quotidiennes, pas de réglage fin.
alter table public.agent_sequences add column if not exists cadence_jours smallint;
alter table public.agent_sequences add column if not exists heure_passage time;
alter table public.agent_sequences add column if not exists playbook_path text;
alter table public.agent_sequences add column if not exists last_pass_at timestamptz;

alter table public.agent_sequences drop constraint if exists agent_sequences_cadence_jours_check;
alter table public.agent_sequences
  add constraint agent_sequences_cadence_jours_check
  check (cadence_jours is null or cadence_jours between 1 and 90);

comment on column public.agent_sequences.cadence_jours is
  'Cible à rythme propre (plateforme) : nombre de jours entre deux passages. NULL = la cadence '
  'vient de la campagne (cas des personnes).';
comment on column public.agent_sequences.heure_passage is
  'Heure de passage (Europe/Paris). Les tâches de scan sont needs_browser donc sérialisées : '
  'les heures sont ÉTALÉES pour que deux plateformes ne se marchent pas dessus.';
comment on column public.agent_sequences.playbook_path is
  'Chemin du playbook DANS LE DÉPÔT Jules (routines/scan-plateformes/references/*.md). La base '
  'ne stocke QUE le chemin : le playbook reste versionné dans git, corrigeable sans toucher au '
  'CRM. Peut être vide — la fiche n''existe pas encore.';

-- ════════════════════════════════════════════════════════════════════════════
-- 4) Le rendement d'un passage
-- ════════════════════════════════════════════════════════════════════════════
-- Un passage laisse une ligne : jusqu'où on est allé, ce qu'on a vu, ce qu'on a créé, et
-- POURQUOI on n'est pas allé au bout. C'est la matière de la stat hebdo, et c'est aussi le
-- seul moyen de rendre visible un « je n'ai pas atteint la liste » au lieu de le noyer.
create table if not exists public.agent_sequence_passages (
  id             bigint generated always as identity primary key,
  owner_id       uuid not null default auth.uid() references public.profiles(id),
  sequence_id    uuid not null references public.agent_sequences(id) on delete cascade,
  task_id        uuid,
  at             timestamptz not null default now(),
  etape_atteinte smallint not null,
  nb_vus         int not null default 0,      -- besoins vus dans la liste
  nb_nouveaux    int not null default 0,      -- besoins NOUVEAUX créés/enrichis au CRM
  motif          text,                        -- pourquoi on s'est arrêté là (obligatoire sous le gate)
  notes          text
);
create index if not exists agent_sequence_passages_seq_idx
  on public.agent_sequence_passages (sequence_id, at desc);
create index if not exists agent_sequence_passages_at_idx
  on public.agent_sequence_passages (owner_id, at desc);

comment on column public.agent_sequence_passages.etape_atteinte is
  'Nombre d''étapes franchies (cf. agent_sequence_patterns). Pour une plateforme : 0 pas ouverte, '
  '1 ouverte SANS la liste (= non couverte), 2 liste atteinte, 3 besoins ouverts, 4 qualifiés au CRM.';

-- Un passage sous le gate SANS motif est refusé : « je n'ai pas atteint la liste » sans dire
-- pourquoi est exactement l'information qui manquait le 23/09 au matin.
create or replace function public.agent_sequence_passage_apply()
returns trigger language plpgsql security invoker as $$
declare s public.agent_sequences; p public.agent_sequence_patterns; kind text; gate smallint;
begin
  select * into s from public.agent_sequences where id = new.sequence_id;
  if not found then raise exception 'séquence % introuvable', new.sequence_id; end if;
  kind := case when s.target_kind = 'plateforme' then 'plateforme' else 'personne' end;
  select * into p from public.agent_sequence_patterns where target_kind = kind;
  gate := coalesce(p.etape_gate, 0);
  if new.etape_atteinte < gate and coalesce(btrim(new.motif), '') = '' then
    raise exception 'passage sous le seuil de couverture (% < %) sans motif : dire POURQUOI la liste n''a pas été atteinte est obligatoire', new.etape_atteinte, gate;
  end if;
  -- La séquence suit son dernier passage, et sa prochaine échéance se repose d'elle-même
  -- sur SA cadence, à SON heure. C'est ce qui rend la boucle autonome : plus personne n'a
  -- à replanifier un scan à la main.
  update public.agent_sequences
     set etape        = new.etape_atteinte,
         last_pass_at = new.at,
         next_due_at  = case when s.statut = 'active' and s.cadence_jours is not null
                        then ((current_date + coalesce(s.cadence_jours,1) * interval '1 day'
                               + coalesce(s.heure_passage, time '08:00')) at time zone 'Europe/Paris')
                        else s.next_due_at end,
         updated_at   = now()
   where id = new.sequence_id;
  insert into public.agent_events (owner_id, actor, kind, sequence_id, mission_id, message, data)
  values (new.owner_id, 'worker',
          case when new.etape_atteinte < gate then 'sequence.passage_incomplet' else 'sequence.passage' end,
          new.sequence_id, s.mission_id,
          s.target_label || ' — étape ' || new.etape_atteinte || '/' || coalesce(array_length(p.etapes,1),0)
            || ' · ' || new.nb_vus || ' vus · ' || new.nb_nouveaux || ' nouveaux'
            || coalesce(' — ' || new.motif, ''),
          jsonb_build_object('etape', new.etape_atteinte, 'nb_vus', new.nb_vus,
                             'nb_nouveaux', new.nb_nouveaux, 'motif', new.motif));
  return new;
end $$;

drop trigger if exists agent_sequence_passage_apply_trg on public.agent_sequence_passages;
create trigger agent_sequence_passage_apply_trg
  after insert on public.agent_sequence_passages
  for each row execute function public.agent_sequence_passage_apply();

-- ════════════════════════════════════════════════════════════════════════════
-- 5) La stat hebdo — matière d'une PROPOSITION, jamais d'un ajustement automatique
-- ════════════════════════════════════════════════════════════════════════════
-- Décision Nicolas 23/09 : pas d'ajustement automatique de la cadence. Une plateforme peut
-- dormir trois semaines puis sortir l'AO de l'année ; un réglage automatique l'aurait mise
-- en veille juste avant. Jules sort la stat une fois par semaine en ronde et PROPOSE ; c'est
-- Nicolas qui tranche.
create or replace function public.agent_scan_stats(p_jours int default 7)
returns table (
  sequence_id uuid, plateforme text, target_ref text, statut text,
  cadence_jours smallint, heure_passage time, playbook_path text,
  nb_passages bigint, nb_couverts bigint, nb_incomplets bigint,
  besoins_vus bigint, besoins_nouveaux bigint,
  dernier_passage timestamptz, dernier_motif text, en_retard boolean
) language sql security invoker as $$
  select s.id, s.target_label, s.target_ref, s.statut,
         s.cadence_jours, s.heure_passage, s.playbook_path,
         count(pa.id),
         count(pa.id) filter (where pa.etape_atteinte >= 2),
         count(pa.id) filter (where pa.etape_atteinte <  2),
         coalesce(sum(pa.nb_vus), 0), coalesce(sum(pa.nb_nouveaux), 0),
         max(pa.at),
         (array_agg(pa.motif order by pa.at desc) filter (where pa.motif is not null))[1],
         s.statut = 'active' and (s.next_due_at is null or s.next_due_at < now() - interval '2 hours')
    from public.agent_sequences s
    left join public.agent_sequence_passages pa
           on pa.sequence_id = s.id and pa.at >= now() - make_interval(days => p_jours)
   where s.target_kind = 'plateforme'
   group by s.id
   order by coalesce(sum(pa.nb_nouveaux), 0) desc, s.target_label;
$$;

comment on function public.agent_scan_stats(int) is
  'Stat hebdo du scan, par plateforme : passages, couverts vs incomplets, besoins vus/nouveaux, '
  'dernier motif d''échec, retard. Sert à PROPOSER un ajustement de cadence à Nicolas — jamais '
  'à l''appliquer (décision Nicolas 23/09).';

-- ════════════════════════════════════════════════════════════════════════════
-- 6) RLS
-- ════════════════════════════════════════════════════════════════════════════
alter table public.agent_sequence_passages enable row level security;
drop policy if exists agent_sequence_passages_owner_all on public.agent_sequence_passages;
create policy agent_sequence_passages_owner_all on public.agent_sequence_passages
  for all using (owner_id = auth.uid()) with check (owner_id = auth.uid());

alter table public.agent_sequence_patterns enable row level security;
drop policy if exists agent_sequence_patterns_read on public.agent_sequence_patterns;
create policy agent_sequence_patterns_read on public.agent_sequence_patterns for select using (true);

-- ════════════════════════════════════════════════════════════════════════════
-- 7) Les deux types de tâches du scan par séquence
-- ════════════════════════════════════════════════════════════════════════════
-- scan.plateforme = UN passage sur UNE plateforme (court, ciblé, navigateur).
-- scan.recap      = LA consolidation : 22 séquences ne font PAS 22 messages dans #commerce
--                   (contrainte Nicolas 23/09). Les passages alimentent la journée, une
--                   seule tâche poste un récap groupé par agence.
insert into public.agent_task_types (type, description, needs_browser, default_model, payload_keys) values
  ('scan.plateforme', 'Passage de scan sur UNE plateforme (une séquence de la campagne Veille plateformes)', true,  'sonnet', '{sequence_id}'),
  ('scan.recap',      'Récap groupé du scan du jour — UN seul message par agence',                           false, 'sonnet', '{}')
on conflict (type) do update set description = excluded.description,
  needs_browser = excluded.needs_browser, default_model = excluded.default_model,
  payload_keys = excluded.payload_keys;

update public.agent_task_types set categorie = 'veille', domaine = 'plateformes', skill_path = 'routines/scan-plateformes/passage.md'
 where type = 'scan.plateforme';
update public.agent_task_types set categorie = 'veille', domaine = null, skill_path = 'routines/scan-plateformes/recap.md'
 where type = 'scan.recap';

-- ════════════════════════════════════════════════════════════════════════════
-- 8) SEED — campagne « Veille plateformes » et ses 22 séquences
-- ════════════════════════════════════════════════════════════════════════════
-- Source : routines/scan-plateformes/platforms.json (manifeste = vérité unique du scan).
-- Toutes quotidiennes, heures étalées de 07h40 à 11h00 (10 min d'écart : les tâches sont
-- needs_browser donc sérialisées — elles ne doivent pas se marcher dessus).
-- AXA XL est seedée ARRÊTÉE avec son motif (Nicolas 13/06, pas de SSO) : présente en base,
-- donc jamais réapparue comme un oubli, et jamais planifiée non plus.
do $$
declare v_owner uuid; v_camp uuid; v_recap uuid; r record;
begin
  select id into v_owner from public.profiles where email = 'nicolas.serradeil@upgrade.fr';
  if v_owner is null then raise exception 'profil Nicolas introuvable — seed annulé'; end if;

  select id into v_camp from public.agent_missions
   where owner_id = v_owner and titre = 'Veille plateformes' and kind = 'campagne' limit 1;
  if v_camp is null then
    insert into public.agent_missions (owner_id, titre, kind, statut, priorite, categorie, contexte, config)
    values (v_owner, 'Veille plateformes', 'campagne', 'active', 1, 'veille',
      'Une séquence par plateforme de besoins. Chaque passage est court et ciblé (son playbook, '
      'sa cadence, son heure) au lieu d''un marathon de 22 plateformes. Le cycle d''une plateforme : '
      'ouvrir → ATTEINDRE LA LISTE DES BESOINS → ouvrir les nouveaux un par un → qualifier et '
      'créer/enrichir au CRM. Une plateforme dont on n''a pas atteint la liste n''est PAS couverte. '
      'Les passages alimentent la journée ; UN seul récap groupé part dans #commerce.',
      jsonb_build_object('kind_cible','plateforme','manifeste','routines/scan-plateformes/platforms.json'))
    returning id into v_camp;
  end if;

  -- La consolidation : une mission récurrente fille, à 11h30, après le dernier passage (11h00).
  select id into v_recap from public.agent_missions
   where owner_id = v_owner and parent_mission_id = v_camp and task_type = 'scan.recap' limit 1;
  if v_recap is null then
    insert into public.agent_missions (owner_id, titre, kind, statut, priorite, categorie,
                                       task_type, cadence, parent_mission_id, contexte)
    values (v_owner, 'Veille plateformes — récap du jour', 'recurring', 'active', 1, 'veille',
      'scan.recap', '{"days":[1,2,3,4,5],"times":["11:30"]}'::jsonb, v_camp,
      'UN seul message par agence, jamais un par plateforme. Consolide les passages du jour.');
  end if;

  for r in
    select * from (values
      ('alpha',               'CATS Alpha',                  '07:40'::time, 'routines/scan-plateformes/references/ivalua.md',        'active', null),
      ('easy-ca',             'Crédit Agricole EASY',        '07:50'::time, 'routines/scan-plateformes/references/ivalua.md',        'active', null),
      ('lcl-easy',            'LCL - EASY',                  '08:00'::time, 'routines/scan-plateformes/references/ivalua.md',        'active', 'miroir de Easy CA (mêmes réfs BPM) — contrôler quand même'),
      ('bpce-harmoni',        'NATIXIS / BPCE Harmoni',      '08:10'::time, 'routines/scan-plateformes/references/ivalua.md',        'active', null),
      ('bpce-it-infra',       'BPCE IT Référencement Infra', '08:20'::time, 'routines/scan-plateformes/references/ivalua.md',        'active', 'surtout infra/IT → filtrer dur sur AMOA produit/design'),
      ('pwise',               'BNP PWise',                   '08:30'::time, 'routines/scan-plateformes/references/pwise.md',         'active', null),
      ('oneproctool',         'Groupe BNP OneProcTool',      '08:40'::time, 'routines/scan-plateformes/SKILL.md#oneproctool',        'active', null),
      ('opase-obms',          'DOCAPOSTE OPASE OBMS',        '08:50'::time, 'routines/scan-plateformes/references/obms.md',          'active', null),
      ('suez-obms',           'SUEZ - OBMS',                 '09:00'::time, 'routines/scan-plateformes/references/obms.md',          'active', 'même portail obms.opase.com, compte SUEZ'),
      ('accor-obms',          'Accor OBMS',                  '09:10'::time, 'routines/scan-plateformes/references/obms.md',          'active', 'même portail obms.opase.com, compte ACCORH'),
      ('engie',               'ENGIE Connecting-Expertise',  '09:20'::time, 'routines/scan-plateformes/references/engie.md',         'active', null),
      ('axa-onevms',          'AXA France OneVMS',           '09:30'::time, 'routines/scan-plateformes/references/onevms.md',        'active', null),
      ('axa-hays',            'AXA Assistance - 3SS HAYS',   '09:40'::time, null,                                                    'active', null),
      ('axa-fieldglass',      'AXA Fieldglass',              '09:50'::time, null,                                                    'active', null),
      ('malakoff-synertrade', 'MALAKOFF HUMANIS',            '10:00'::time, 'routines/scan-plateformes/references/synertrade.md',    'active', null),
      ('piter',               'PITER Malakoff Humanis',      '10:10'::time, 'routines/scan-plateformes/references/piter.md',          'active', null),
      ('edenred',             'EDENRED - Edenbuy',           '10:20'::time, null,                                                    'active', 'reconnexion Okta = code envoyé par mail'),
      ('lbc',                 'LittleBig Connection',        '10:30'::time, 'routines/scan-plateformes/references/lbc.md',           'active', null),
      ('agrega',              'Agrega',                      '10:40'::time, 'routines/scan-plateformes/references/agrega.md',        'active', null),
      ('akilink',             'Akilink (AkiKonnect)',        '10:50'::time, 'routines/scan-plateformes/references/akilink.md',       'active', null),
      ('opteamis',            'Opteamis',                    '11:00'::time, 'routines/scan-plateformes/references/opteamis.md',      'active', null),
      ('axa-xl',              'AXA XL',                       null,          null,                                                   'stopped', 'IGNORÉE DÉFINITIVEMENT (Nicolas 13/06) : pas de SSO, aucun accès. Seedée arrêtée pour ne jamais réapparaître comme un oubli.')
    ) as v(ref, label, heure, playbook, statut, note)
  loop
    insert into public.agent_sequences
      (owner_id, mission_id, target_kind, target_ref, target_label, etape, statut,
       cadence_jours, heure_passage, playbook_path, next_due_at, notes)
    values
      (v_owner, v_camp, 'plateforme', r.ref, r.label, 0, r.statut,
       case when r.statut = 'active' then 1 else null end, r.heure, r.playbook,
       case when r.statut = 'active'
            then ((current_date + interval '1 day' + r.heure) at time zone 'Europe/Paris')
            else null end,
       r.note)
    on conflict (mission_id, target_kind, target_ref) do update set
       target_label  = excluded.target_label,
       heure_passage = excluded.heure_passage,
       playbook_path = excluded.playbook_path;
       -- statut / etape / next_due_at / notes NE sont PAS réécrits au rejeu : un passage déjà
       -- fait, une pause posée à la main ou un arrêt décidé ne doivent pas être effacés.
  end loop;
end $$;

commit;

-- Vérif :
--   select target_kind, count(*) from public.agent_sequences group by 1;
--     → attendu : les séquences de personnes inchangées + 22 'plateforme'.
--   select target_label, statut, heure_passage, playbook_path, next_due_at
--     from public.agent_sequences where target_kind = 'plateforme' order by heure_passage nulls last;
--   select * from public.agent_scan_stats(7);
--   select * from public.agent_sequence_patterns;
