-- ══════════════════════════════════════════════════════════════════════
-- 65 — Sessions d'appel : la porte d'écriture unique `enregistrer_resultat_appel`   (20/11/2026, tranche T1)
-- BLOC 2/3 — APPLY (transactionnel, auto-testé, tout ou rien). Prérequis : db/64 en place.
--
-- CE QUI CHANGE :
--   1. session_prospection_contacts : statut accepte 'message' ; colonnes du geste (canal, precision, suite,
--      date_suite, ne_plus_appeler, appel_at, geste_at, historique_id, tache_id), du message (message_canal,
--      message_at, message_historique_id, message_tache_id) et de la correction (contact_avant, contact_pose, maj_par).
--   2. sessions_prospection : nb_messages (compteur à part : nb_contacts reste un nombre d'appels), origine
--      ('crm' par défaut, 'jules'), mission_jules_id (dossier Jules d'origine).
--   3. public._appel_contact_cible(...) : les règles d'étape du CRM (index.html, prospectPatchDepuisAppel et
--      etapeDepuisResultatAppel) reprises À L'IDENTIQUE, en fonction pure (testée contre le code JS).
--   4. public.enregistrer_resultat_appel(...) : pour UNE personne d'une session, en UNE transaction : ligne de
--      session, fiche contact (étape, prochaine action), UNE ligne d'historique, LA tâche de suite, compteurs.
--      Rejouable (le même appel deux fois ne double rien), corrigeable (un autre résultat corrige les écritures
--      du premier), annulable (p_resultat = 'none' ; 'message_annule' pour un message).
--      Droits : la session est à celui qui appelle, ou à un admin (règle actuelle des sessions). Aucun accès anon.
--
-- CE QUI NE BOUGE PAS : l'écran « Prosp. » du CRM (il écrit toujours à « Terminer »), les sessions passées,
-- les compteurs existants, les droits des tables.
--
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/65_porte_resultat_appel_2_apply.sql
-- Retour arrière : db/65_porte_resultat_appel_rollback.sql
-- ══════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP on
begin;

-- ─── 0. Garde d'entrée ───
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'spc_session_contact_uniq') then
    raise exception 'db/64 absente (contrainte spc_session_contact_uniq) : arrêt';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'session_prospection_contacts' and column_name = 'geste_at') then
    raise exception 'Colonnes T1 déjà présentes : arrêt (passage déjà fait ?)';
  end if;
  if exists (select 1 from pg_proc where proname = 'enregistrer_resultat_appel') then
    raise exception 'enregistrer_resultat_appel existe déjà : arrêt';
  end if;
  if pg_get_constraintdef((select oid from pg_constraint where conname = 'session_prospection_contacts_statut_check'))
     <> 'CHECK ((statut = ANY (ARRAY[''none''::text, ''called''::text, ''interested''::text, ''unreachable''::text, ''not_interested''::text])))' then
    raise exception 'Contrainte de statut inattendue : arrêt';
  end if;
end $$;

-- ─── 1. Colonnes ───
alter table public.session_prospection_contacts drop constraint session_prospection_contacts_statut_check;
alter table public.session_prospection_contacts add constraint session_prospection_contacts_statut_check
  check (statut = any (array['none','called','interested','unreachable','not_interested','message']));

alter table public.session_prospection_contacts
  add column canal text check (canal in ('telephone','mail','linkedin')),
  add column precision text check (precision in ('messagerie','sonne_dans_le_vide','numero_faux',
                                                 'pas_le_bon_moment','deja_equipe','pas_concerne')),
  add column suite text check (suite in ('aucune','rappel','rdv','presentation','mail','reveil')),
  add column date_suite timestamptz,
  add column ne_plus_appeler boolean not null default false,
  add column appel_at timestamptz,
  add column geste_at timestamptz,
  add column historique_id integer references public.historique_actions(id) on delete set null,
  add column tache_id text references public.taches(id) on delete set null,
  add column message_canal text check (message_canal in ('mail','linkedin')),
  add column message_at timestamptz,
  add column message_historique_id integer references public.historique_actions(id) on delete set null,
  add column message_tache_id text references public.taches(id) on delete set null,
  add column contact_avant jsonb,
  add column contact_pose jsonb,
  add column maj_par text;

create index spc_historique_id_idx on public.session_prospection_contacts (historique_id) where historique_id is not null;
create index spc_message_historique_id_idx on public.session_prospection_contacts (message_historique_id) where message_historique_id is not null;
create index spc_tache_id_idx on public.session_prospection_contacts (tache_id) where tache_id is not null;
create index spc_message_tache_id_idx on public.session_prospection_contacts (message_tache_id) where message_tache_id is not null;

alter table public.sessions_prospection
  add column nb_messages integer not null default 0,
  add column origine text not null default 'crm' check (origine in ('crm','jules')),
  add column mission_jules_id uuid;

-- ─── 2. Les règles d'étape du CRM, à l'identique (fonction pure) ───
-- Horodatage écrit en texte UTC fixe dans les photos de fiche (contact_avant / contact_pose) : la comparaison
-- ne dépend pas du fuseau de la connexion (PostgREST, psql).
create or replace function public._ts_utc(p timestamptz)
returns text language sql immutable set search_path = pg_catalog as
$$ select to_char(p at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') $$;
revoke all on function public._ts_utc(timestamptz) from public, anon, authenticated;

-- Entrées : la fiche AVANT le geste (p_base : etape_prospect, prochaine_action_date, prochaine_action_libelle,
-- motif_perte, motif_perte_precision), son statut, le résultat d'appel, la case « Ne plus appeler », la suite
-- (p_want = une relance cochée, p_date_suite = son échéance, p_note_suite = sa note, p_suite = son type),
-- le message envoyé (p_message, p_msg_relance), et le jour (Paris) du geste.
-- Sortie : la fiche APRÈS (mêmes 5 champs). Reprend index.html : prospectEtapeOuDefaut, etapeDepuisResultatAppel,
-- prospectPatchDepuisAppel(sc, avancer=true), prospectPatchEtape, prospectReveilPreset('6m'), prospectTacheLibelle.
-- Seul ajout : la suite 'rdv' d'un « Intéressant » vise « RDV planifié » (jamais produite par l'écran du CRM).
create or replace function public._appel_contact_cible(
  p_base jsonb, p_statut_contact text, p_call text, p_npa boolean,
  p_want boolean, p_date_suite timestamptz, p_note_suite text, p_suite text,
  p_message boolean, p_msg_relance timestamptz, p_jour date)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  c_actives constant text[] := array['À contacter','Contacté','En discussion','RDV planifié','RDV effectué'];
  c_toutes  constant text[] := array['À contacter','Contacté','En discussion','RDV planifié','RDV effectué','À relancer','Ne pas recontacter'];
  v_out jsonb := p_base;
  v_actuelle text;
  v_cible text;
  v_nouvelle text;
  v_reveil date;
  v_lib text;
begin
  v_actuelle := p_base ->> 'etape_prospect';
  if v_actuelle is null or not (v_actuelle = any (c_toutes)) then v_actuelle := 'À contacter'; end if;
  if v_actuelle = 'Ne pas recontacter' then return v_out; end if;

  if p_call = 'not_interested' then
    if coalesce(p_npa, false) then
      return v_out || jsonb_build_object('etape_prospect', 'Ne pas recontacter', 'prochaine_action_date', null,
        'prochaine_action_libelle', null, 'motif_perte', null,
        'motif_perte_precision', 'Marqué "Ne plus appeler" en session de prospection');
    end if;
    if p_statut_contact is distinct from 'Prospect' then return v_out; end if;
    v_reveil := (p_jour + interval '6 months')::date;   -- fin de mois ramenée au dernier jour, comme le JS
    v_lib := coalesce(case when coalesce(p_want, false) then nullif(p_note_suite, '') end, 'Relance après refus');
    return v_out || jsonb_build_object('etape_prospect', 'À relancer',
      'prochaine_action_date', public._ts_utc((v_reveil + time '09:00') at time zone 'Europe/Paris'),
      'prochaine_action_libelle', v_lib, 'motif_perte', null, 'motif_perte_precision', null);
  end if;

  if p_statut_contact is distinct from 'Prospect' then return v_out; end if;

  -- Cible du résultat (un message envoyé compte comme un contact établi, comme « Appelé »).
  v_cible := case p_call when 'interested' then case when p_suite = 'rdv' then 'RDV planifié' else 'En discussion' end
                         when 'unreachable' then 'Contacté'
                         when 'called' then 'Contacté'
                         else case when coalesce(p_message, false) then 'Contacté' end end;
  v_nouvelle := v_actuelle;
  if v_cible is not null and array_position(c_actives, v_actuelle) is not null
     and array_position(c_actives, v_cible) > array_position(c_actives, v_actuelle) then
    v_nouvelle := v_cible;
  end if;
  if v_nouvelle <> v_actuelle then
    v_out := v_out || jsonb_build_object('etape_prospect', v_nouvelle);
  end if;

  if v_nouvelle = any (c_actives) then
    if p_call is not null and p_call <> 'none' and coalesce(p_want, false) and p_date_suite is not null then
      v_out := v_out || jsonb_build_object('prochaine_action_date', public._ts_utc(p_date_suite),
        'prochaine_action_libelle', coalesce(nullif(p_note_suite, ''),
          case when p_suite = 'rdv' then 'RDV prospect' else
            case v_nouvelle when 'Contacté' then 'Rappeler' when 'En discussion' then 'Relancer'
                            when 'RDV planifié' then 'RDV prospect' when 'RDV effectué' then 'Qualifier le besoin'
                            when 'À contacter' then 'Premier contact' else 'Suivi prospect' end end));
    elsif coalesce(p_message, false) and p_msg_relance is not null
          and not (p_call is not null and p_call <> 'none' and coalesce(p_want, false) and p_date_suite is not null) then
      v_out := v_out || jsonb_build_object('prochaine_action_date', public._ts_utc(p_msg_relance), 'prochaine_action_libelle', 'Relancer');
    end if;
  end if;
  return v_out;
end $$;
revoke all on function public._appel_contact_cible(jsonb,text,text,boolean,boolean,timestamptz,text,text,boolean,timestamptz,date) from public, anon, authenticated;

-- ─── 3. La porte d'écriture ───
create or replace function public.enregistrer_resultat_appel(
  p_session uuid,
  p_contact integer,
  p_resultat text,                      -- none | called | interested | unreachable | not_interested | message | message_annule
  p_precision text default null,        -- messagerie | sonne_dans_le_vide | numero_faux | pas_le_bon_moment | deja_equipe | pas_concerne
  p_note text default null,             -- note d'appel (ou début du message)
  p_suite text default null,            -- aucune | rappel | rdv | presentation | mail | reveil
  p_date_suite timestamptz default null,-- échéance de la suite (heure comprise) ; message : relance (défaut J+7 9 h)
  p_ne_plus_appeler boolean default false,
  p_canal text default null,            -- telephone (défaut d'un appel) | mail | linkedin (obligatoire pour un message)
  p_note_suite text default null        -- note de la relance (libellé de la prochaine action, comme au CRM)
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c_appels constant text[] := array['called','interested','unreachable','not_interested'];
  c_champs constant text[] := array['etape_prospect','prochaine_action_date','prochaine_action_libelle','motif_perte','motif_perte_precision'];
  v_uid uuid := auth.uid();
  v_nom text; v_role text;
  s public.sessions_prospection%rowtype;
  r public.session_prospection_contacts%rowtype;
  c public.contacts%rowtype;
  v_now timestamptz := now();
  v_jour date := (now() at time zone 'Europe/Paris')::date;
  v_label text; v_details text; v_titre text; v_due timestamptz; v_notes text;
  v_tache_statut text; v_want boolean; v_msg_due timestamptz;
  v_actuel jsonb; v_base jsonb; v_cible jsonb;
  v_etape_avant text; v_etape_apres text;
  v_jour_reveil date;
  v_nom_contact text;
  v_societe text;
  v_npc_taches int := 0; v_npc_seq int := 0;
  v_canal text;
  v_ecrit text[] := '{}';
begin
  -- a. Appelant : une personne connectée avec un profil. Pas d'anon, pas de clé service.
  if v_uid is null then
    raise exception 'Enregistrement refusé : il faut être connecté.' using errcode = '42501';
  end if;
  select p.nom, p.role into v_nom, v_role from public.profiles p where p.id = v_uid;
  if v_nom is null then
    raise exception 'Enregistrement refusé : profil introuvable.' using errcode = '42501';
  end if;

  -- b. Paramètres
  if p_resultat is null or p_resultat not in ('none','called','interested','unreachable','not_interested','message','message_annule') then
    raise exception 'Résultat inconnu : %', p_resultat using errcode = '22023';
  end if;
  if p_suite is not null and p_suite not in ('aucune','rappel','rdv','presentation','mail','reveil') then
    raise exception 'Suite inconnue : %', p_suite using errcode = '22023';
  end if;
  if p_precision is not null and p_precision not in ('messagerie','sonne_dans_le_vide','numero_faux','pas_le_bon_moment','deja_equipe','pas_concerne') then
    raise exception 'Précision inconnue : %', p_precision using errcode = '22023';
  end if;
  if p_resultat = 'message' and coalesce(p_canal, '') not in ('mail','linkedin') then
    raise exception 'Un message envoyé demande son canal : mail ou linkedin.' using errcode = '22023';
  end if;
  if p_resultat = any (c_appels) and coalesce(p_canal, 'telephone') <> 'telephone' then
    raise exception 'Un résultat d''appel a le canal telephone (reçu : %).', p_canal using errcode = '22023';
  end if;
  if coalesce(p_ne_plus_appeler, false) and p_resultat <> 'not_interested' then
    raise exception '« Ne plus appeler » ne va qu''avec « Pas intéressé ».' using errcode = '22023';
  end if;
  if p_suite = 'rdv' and p_resultat <> 'interested' then
    raise exception 'La suite « RDV pris » ne va qu''avec « Intéressant ».' using errcode = '22023';
  end if;

  -- c. Session (verrouillée : les gestes d'une même session passent l'un après l'autre) et droits.
  select * into s from public.sessions_prospection where id = p_session for update;
  if not found then
    raise exception 'Session introuvable.' using errcode = 'P0002';
  end if;
  if s.responsable is distinct from v_nom and v_role is distinct from 'admin' then
    raise exception 'Enregistrement refusé : cette session est celle de %.', s.responsable using errcode = '42501';
  end if;

  select * into r from public.session_prospection_contacts where session_id = p_session and contact_id = p_contact for update;
  if not found then
    raise exception 'Cette personne n''est pas dans la session.' using errcode = 'P0002';
  end if;
  -- Ligne enregistrée par l'ancien bouton « Terminer » du CRM : ses écritures ne sont pas reliées, on ne la reprend pas ici.
  if r.statut <> 'none' and r.geste_at is null then
    raise exception 'Résultat enregistré par l''écran « Prosp. » du CRM : à corriger depuis le CRM.' using errcode = 'P0001';
  end if;

  select * into c from public.contacts where id = p_contact for update;
  if not found then
    raise exception 'Fiche contact introuvable (supprimée ou fusionnée).' using errcode = 'P0002';
  end if;
  v_nom_contact := btrim(coalesce(c.prenom, '') || ' ' || coalesce(c.nom, ''));
  -- Société : compte principal en cours, sinon employeur (contacts.groupe n'existe plus).
  select co.nom into v_societe from public.contact_compte cc join public.comptes co on co.id = cc.compte_id
   where cc.contact_id = p_contact and cc.is_primary and cc.date_fin is null order by cc.id limit 1;
  v_societe := coalesce(nullif(btrim(v_societe), ''), nullif(btrim(c.employeur), ''));

  -- d. Ligne de session : on pose le nouvel état du geste.
  if p_resultat = 'message' then
    v_canal := p_canal;
    r.message_canal := p_canal;
    r.message_at := coalesce(r.message_at, v_now);
    if r.statut = 'none' then r.statut := 'message'; end if;
  elsif p_resultat = 'message_annule' then
    r.message_canal := null; r.message_at := null;
    if r.statut = 'message' then r.statut := 'none'; end if;
    v_canal := case when r.statut = any (c_appels) then 'telephone' end;
  elsif p_resultat = 'none' then
    r.statut := case when r.message_at is not null then 'message' else 'none' end;
    r.precision := null; r.suite := null; r.date_suite := null; r.ne_plus_appeler := false;
    r.notes := null; r.want_relance := false; r.relance_date := null; r.relance_note := null; r.appel_at := null;
    v_canal := case when r.message_at is not null then r.message_canal end;
  else
    -- Le jour du réveil « Pas intéressé » reste celui du premier geste tant que le résultat ne change pas.
    if r.statut is distinct from p_resultat then r.appel_at := v_now; end if;
    r.appel_at := coalesce(r.appel_at, v_now);
    r.statut := p_resultat;
    r.precision := p_precision;
    r.notes := nullif(p_note, '');
    r.suite := p_suite;
    r.date_suite := p_date_suite;
    r.ne_plus_appeler := coalesce(p_ne_plus_appeler, false);
    r.want_relance := coalesce(p_suite in ('rappel','rdv','presentation'), false);
    r.relance_date := case when r.want_relance and p_date_suite is not null then (p_date_suite at time zone 'Europe/Paris')::date end;
    r.relance_note := nullif(p_note_suite, '');
    v_canal := 'telephone';
  end if;
  r.geste_at := v_now;
  r.canal := v_canal;
  r.maj_par := v_nom;

  -- e. Fiche contact : on repart de la fiche d'avant le premier geste (correction sans doublon), sauf si
  --    quelqu'un l'a modifiée depuis notre dernière écriture (on repart alors de son état actuel).
  v_actuel := jsonb_build_object('etape_prospect', c.etape_prospect, 'prochaine_action_date', public._ts_utc(c.prochaine_action_date),
                'prochaine_action_libelle', c.prochaine_action_libelle, 'motif_perte', c.motif_perte,
                'motif_perte_precision', c.motif_perte_precision);
  if r.contact_avant is null or (r.contact_pose is not null and r.contact_pose is distinct from v_actuel) then
    r.contact_avant := v_actuel;
  end if;
  v_base := r.contact_avant;
  v_etape_avant := c.etape_prospect;

  v_want := r.want_relance;
  -- Échéance de la relance d'un message : celle demandée, sinon J+7 à 9 h (Paris).
  if r.message_at is not null then
    if p_resultat = 'message' then
      v_msg_due := case when coalesce(p_suite, '') = 'aucune' then null
                        else coalesce(p_date_suite, ((v_jour + 7) + time '09:00') at time zone 'Europe/Paris') end;
    else
      select t.due_date into v_msg_due from public.taches t where t.id = r.message_tache_id;
    end if;
  end if;
  v_jour_reveil := coalesce((r.appel_at at time zone 'Europe/Paris')::date, v_jour);

  if r.statut = 'none' then
    v_cible := v_base;   -- plus aucun geste : la fiche revient à son état d'avant
  else
    v_cible := public._appel_contact_cible(v_base, c.statut,
                 case when r.statut = any (c_appels) then r.statut end, r.ne_plus_appeler,
                 v_want, r.date_suite, r.relance_note, r.suite,
                 r.message_at is not null, v_msg_due, v_jour_reveil);
  end if;

  if v_cible is distinct from v_actuel then
    update public.contacts
       set etape_prospect = v_cible ->> 'etape_prospect',
           prochaine_action_date = (v_cible ->> 'prochaine_action_date')::timestamptz,
           prochaine_action_libelle = v_cible ->> 'prochaine_action_libelle',
           motif_perte = v_cible ->> 'motif_perte',
           motif_perte_precision = v_cible ->> 'motif_perte_precision',
           updated_at = v_now
     where id = p_contact;
    v_ecrit := v_ecrit || 'fiche'::text;
  end if;
  v_etape_apres := v_cible ->> 'etape_prospect';
  r.contact_pose := case when r.statut = 'none' then null else v_cible end;
  if r.statut = 'none' then r.contact_avant := null; end if;

  -- Entrée en « Ne pas recontacter » : tâches de prospection annulées, séquences arrêtées (comme le CRM).
  if v_etape_apres = 'Ne pas recontacter' and v_etape_avant is distinct from 'Ne pas recontacter' then
    update public.taches set statut = 'annule', updated_at = v_now
     where contact_id = p_contact and id like 'tw\_prospect\_%' and coalesce(statut, '') not in ('fait','annule');
    get diagnostics v_npc_taches = row_count;
    update jules.agent_sequences
       set statut = 'stopped', next_due_at = null,
           notes = concat_ws(E'\n', nullif(notes, ''), '[' || to_char(v_jour, 'DD/MM/YYYY') || '] Arrêt : fiche passée en Ne pas recontacter')
     where contact_id = p_contact and statut in ('active','replied','paused');
    get diagnostics v_npc_seq = row_count;
  end if;

  -- f. Historique de l'appel : UNE ligne, corrigée ou retirée, jamais doublée.
  if r.statut = any (c_appels) then
    v_label := case r.statut when 'called' then 'Appelé' when 'interested' then 'Intéressant'
                             when 'unreachable' then 'Pas répondu' when 'not_interested' then 'Pas intéressé' end;
    v_details := concat_ws(E'\n', 'Session : ' || s.nom, 'Résultat : ' || v_label,
                   case r.precision when 'messagerie' then 'Précision : messagerie'
                                    when 'sonne_dans_le_vide' then 'Précision : sonne dans le vide'
                                    when 'numero_faux' then 'Précision : numéro faux'
                                    when 'pas_le_bon_moment' then 'Motif : pas le bon moment'
                                    when 'deja_equipe' then 'Motif : déjà équipé'
                                    when 'pas_concerne' then 'Motif : pas concerné' end,
                   case when r.ne_plus_appeler then 'Ne plus appeler' end,
                   case when r.notes is not null then 'Notes : ' || r.notes end);
    if r.historique_id is not null and exists (select 1 from public.historique_actions where id = r.historique_id) then
      update public.historique_actions set type_action = 'Appel sortant', details = v_details
       where id = r.historique_id and (type_action, details) is distinct from ('Appel sortant', v_details);
    else
      insert into public.historique_actions (id_prospect, date, type_action, details, responsable)
      values (p_contact, v_jour, 'Appel sortant', v_details, v_nom) returning id into r.historique_id;
      v_ecrit := v_ecrit || 'historique'::text;
    end if;
  elsif r.historique_id is not null then
    delete from public.historique_actions where id = r.historique_id;
    r.historique_id := null;
    v_ecrit := v_ecrit || 'historique_retire'::text;
  end if;

  -- g. Tâche de suite de l'appel : UNE tâche, corrigée ou retirée.
  if r.statut = any (c_appels) and r.want_relance and r.date_suite is not null then
    v_titre := case r.suite when 'rdv' then 'Préparer le RDV avec ' || v_nom_contact
                            when 'presentation' then 'Envoyer une présentation à ' || v_nom_contact
                            else 'Relance ' || v_nom_contact || coalesce(' — ' || v_societe, '') end;
    v_due := case when r.suite = 'rdv' then r.date_suite - interval '1 hour' else r.date_suite end;
    v_notes := concat_ws(E'\n', 'Session : ' || s.nom, 'Statut : ' || v_label, r.relance_note);
    select t.statut into v_tache_statut from public.taches t where t.id = r.tache_id;
    if r.tache_id is not null and found then
      if v_tache_statut = 'a_faire' then
        update public.taches set titre = v_titre, due_date = v_due, notes = v_notes, updated_at = v_now
         where id = r.tache_id and (titre, due_date, notes) is distinct from (v_titre, v_due, v_notes);
      end if;   -- faite ou annulée : on la laisse telle quelle
    else
      r.tache_id := 'tw_relance_' || p_contact || '_' || (extract(epoch from clock_timestamp()) * 1000)::bigint || '_a';
      insert into public.taches (id, titre, statut, due_date, contact_id, session_prospection_id, notes, responsable)
      values (r.tache_id, v_titre, 'a_faire', v_due, p_contact, p_session, v_notes, v_nom);
      v_ecrit := v_ecrit || 'tache'::text;
    end if;
  elsif r.tache_id is not null then
    select t.statut into v_tache_statut from public.taches t where t.id = r.tache_id;
    if found and v_tache_statut = 'a_faire' then
      delete from public.taches where id = r.tache_id;
      v_ecrit := v_ecrit || 'tache_retiree'::text;
    end if;
    r.tache_id := null;
  end if;

  -- h. Message envoyé : UNE ligne d'historique (« Mail envoyé » ou « LinkedIn ») et UNE relance.
  if r.message_at is not null then
    v_details := concat_ws(E'\n', 'Session : ' || s.nom,
                   'Message envoyé par ' || case r.message_canal when 'mail' then 'mail' else 'LinkedIn' end || ' (envoyé par ' || v_nom || ')',
                   case when p_resultat = 'message' and nullif(p_note, '') is not null then left(p_note, 500) end);
    if r.message_historique_id is not null and exists (select 1 from public.historique_actions where id = r.message_historique_id) then
      if p_resultat = 'message' then
        update public.historique_actions
           set type_action = case r.message_canal when 'mail' then 'Mail envoyé' else 'LinkedIn' end, details = v_details
         where id = r.message_historique_id;
      end if;
    else
      insert into public.historique_actions (id_prospect, date, type_action, details, responsable)
      values (p_contact, v_jour, case r.message_canal when 'mail' then 'Mail envoyé' else 'LinkedIn' end, v_details, v_nom)
      returning id into r.message_historique_id;
      v_ecrit := v_ecrit || 'historique_message'::text;
    end if;
    if p_resultat = 'message' then
      if v_msg_due is not null then
        v_titre := 'Relancer ' || v_nom_contact;
        v_notes := concat_ws(E'\n', 'Session : ' || s.nom, 'Statut : Message envoyé (' || r.message_canal || ')', nullif(p_note_suite, ''));
        select t.statut into v_tache_statut from public.taches t where t.id = r.message_tache_id;
        if r.message_tache_id is not null and found then
          if v_tache_statut = 'a_faire' then
            update public.taches set titre = v_titre, due_date = v_msg_due, notes = v_notes, updated_at = v_now
             where id = r.message_tache_id and (titre, due_date, notes) is distinct from (v_titre, v_msg_due, v_notes);
          end if;
        else
          r.message_tache_id := 'tw_relance_' || p_contact || '_' || (extract(epoch from clock_timestamp()) * 1000)::bigint || '_m';
          insert into public.taches (id, titre, statut, due_date, contact_id, session_prospection_id, notes, responsable)
          values (r.message_tache_id, v_titre, 'a_faire', v_msg_due, p_contact, p_session, v_notes, v_nom);
          v_ecrit := v_ecrit || 'tache_message'::text;
        end if;
      elsif r.message_tache_id is not null then   -- suite « aucune » : la relance prévue est retirée
        select t.statut into v_tache_statut from public.taches t where t.id = r.message_tache_id;
        if found and v_tache_statut = 'a_faire' then delete from public.taches where id = r.message_tache_id; end if;
        r.message_tache_id := null;
      end if;
    end if;
  else
    if r.message_historique_id is not null then
      delete from public.historique_actions where id = r.message_historique_id;
      r.message_historique_id := null;
      v_ecrit := v_ecrit || 'historique_message_retire'::text;
    end if;
    if r.message_tache_id is not null then
      select t.statut into v_tache_statut from public.taches t where t.id = r.message_tache_id;
      if found and v_tache_statut = 'a_faire' then delete from public.taches where id = r.message_tache_id; end if;
      r.message_tache_id := null;
    end if;
  end if;

  -- i. Écriture de la ligne et des compteurs de la session.
  update public.session_prospection_contacts
     set statut = r.statut, notes = r.notes, want_relance = r.want_relance, relance_date = r.relance_date,
         relance_note = r.relance_note, canal = r.canal, precision = r.precision, suite = r.suite,
         date_suite = r.date_suite, ne_plus_appeler = r.ne_plus_appeler, appel_at = r.appel_at, geste_at = r.geste_at,
         historique_id = r.historique_id, tache_id = r.tache_id, message_canal = r.message_canal,
         message_at = r.message_at, message_historique_id = r.message_historique_id,
         message_tache_id = r.message_tache_id, contact_avant = r.contact_avant, contact_pose = r.contact_pose,
         maj_par = r.maj_par
   where id = r.id;

  update public.sessions_prospection x
     set nb_contacts = k.nb_c, nb_interesses = k.nb_i, nb_injoignables = k.nb_u,
         nb_relances = k.nb_r, nb_messages = k.nb_m, updated_at = v_now
    from (select count(*) filter (where statut = any (c_appels)) nb_c,
                 count(*) filter (where statut = 'interested') nb_i,
                 count(*) filter (where statut = 'unreachable') nb_u,
                 count(*) filter (where tache_id is not null) + count(*) filter (where message_tache_id is not null) nb_r,
                 count(*) filter (where message_at is not null) nb_m
            from public.session_prospection_contacts where session_id = p_session) k
   where x.id = p_session;

  return jsonb_build_object(
    'ok', true, 'session', p_session, 'contact', p_contact, 'resultat', r.statut,
    'etape_avant', v_etape_avant, 'etape_apres', v_etape_apres,
    'historique_id', r.historique_id, 'tache_id', r.tache_id,
    'message_historique_id', r.message_historique_id, 'message_tache_id', r.message_tache_id,
    'npc', jsonb_build_object('taches_annulees', v_npc_taches, 'sequences_arretees', v_npc_seq),
    'ecrit', to_jsonb(v_ecrit),
    'compteurs', (select jsonb_build_object('appels', nb_contacts, 'interesses', nb_interesses, 'injoignables', nb_injoignables,
                                            'relances', nb_relances, 'messages', nb_messages)
                    from public.sessions_prospection where id = p_session));
end $$;

revoke all on function public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text) from public, anon;
grant execute on function public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text) to authenticated;

-- ─── 4. Tests intégrés (savepoint annulé ; toute erreur annule TOUT) ───
savepoint tests_t1;
do $$
declare
  u_a uuid; n_a text; u_b uuid; n_b text;
  v_s uuid; v_c int; v_j jsonb; v_n int; v_h int; v_t text; v_e text; v_ok boolean;
  v_c2 int;
begin
  -- Deux commerciaux distincts (le propriétaire de la session et un collègue)
  select id, nom into u_a, n_a from public.profiles where role = 'commercial' order by nom limit 1;
  select id, nom into u_b, n_b from public.profiles where role = 'commercial' and id <> u_a order by nom limit 1;
  insert into public.contacts (prenom, nom, statut, responsable, etape_prospect, employeur)
  values ('Zz', 'TestPorteT1', 'Prospect', n_a, 'À contacter', 'Société Test') returning id into v_c;
  insert into public.contacts (prenom, nom, statut, responsable, etape_prospect)
  values ('Zz', 'TestPorteT1b', 'Prospect', n_a, 'En discussion') returning id into v_c2;
  insert into public.sessions_prospection (nom, responsable, statut) values ('T1 test', n_a, 'active') returning id into v_s;
  insert into public.session_prospection_contacts (session_id, contact_id) values (v_s, v_c), (v_s, v_c2);

  -- Anon : refusé
  perform set_config('request.jwt.claims', '', true);
  v_ok := false;
  begin perform public.enregistrer_resultat_appel(v_s, v_c, 'called'); exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'T1.1 : anon non refusé'; end if;

  -- Un collègue : refusé
  perform set_config('request.jwt.claims', json_build_object('sub', u_b, 'role', 'authenticated')::text, true);
  v_ok := false;
  begin perform public.enregistrer_resultat_appel(v_s, v_c, 'called'); exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'T1.2 : collègue non refusé'; end if;

  -- Le propriétaire : « Pas répondu » -> Contacté, 1 historique, 0 tâche
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'unreachable', 'messagerie');
  select etape_prospect into v_e from public.contacts where id = v_c;
  if v_e <> 'Contacté' then raise exception 'T1.3 : étape % au lieu de Contacté', v_e; end if;
  select count(*) into v_h from public.historique_actions where id_prospect = v_c;
  if v_h <> 1 then raise exception 'T1.3 : % lignes d''historique', v_h; end if;

  -- Rejeu identique : rien de plus
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'unreachable', 'messagerie');
  select count(*) into v_h from public.historique_actions where id_prospect = v_c;
  if v_h <> 1 then raise exception 'T1.4 : rejeu a doublé l''historique (%)', v_h; end if;

  -- Correction : « Appelé » avec rappel daté -> 1 historique corrigé, 1 tâche, prochaine action posée
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'called', null, 'on s''est parlé', 'rappel', now() + interval '3 days', false, null, 'mail');
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'called', null, 'on s''est parlé', 'rappel', (v_j ->> 'x')::timestamptz, false, null, 'mail');
  -- (deuxième appel sans date : la tâche doit être retirée)
  select count(*) into v_n from public.taches where contact_id = v_c;
  if v_n <> 0 then raise exception 'T1.5 : tâche non retirée quand la date de suite disparaît (%)', v_n; end if;
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'called', null, 'on s''est parlé', 'rappel', now() + interval '3 days', false, null, 'mail');
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'called', null, 'on s''est parlé', 'rappel', now() + interval '3 days', false, null, 'mail');
  select count(*) into v_n from public.taches where contact_id = v_c;
  select count(*) into v_h from public.historique_actions where id_prospect = v_c and type_action = 'Appel sortant';
  if v_n <> 1 or v_h <> 1 then raise exception 'T1.5 : % tâche(s), % historique(s)', v_n, v_h; end if;
  if (select prochaine_action_libelle from public.contacts where id = v_c) <> 'mail' then raise exception 'T1.5 : libellé de prochaine action'; end if;

  -- Correction en « Pas intéressé » : À relancer (réveil 6 mois), tâche retirée
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'not_interested', 'pas_le_bon_moment');
  select etape_prospect into v_e from public.contacts where id = v_c;
  if v_e <> 'À relancer' then raise exception 'T1.6 : étape %', v_e; end if;
  if (select count(*) from public.taches where contact_id = v_c) <> 0 then raise exception 'T1.6 : tâche restée'; end if;

  -- Correction en « Intéressant » : l'étape repart de la fiche d'avant (À contacter) -> En discussion
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'interested', null, 'projet en vue');
  select etape_prospect into v_e from public.contacts where id = v_c;
  if v_e <> 'En discussion' then raise exception 'T1.7 : étape % au lieu de En discussion', v_e; end if;

  -- Annulation : la fiche revient à À contacter, historique retiré, compteurs à 0
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'none');
  select etape_prospect into v_e from public.contacts where id = v_c;
  if v_e <> 'À contacter' then raise exception 'T1.8 : étape % au lieu de À contacter', v_e; end if;
  if (select count(*) from public.historique_actions where id_prospect = v_c) <> 0 then raise exception 'T1.8 : historique resté'; end if;
  if (select nb_contacts from public.sessions_prospection where id = v_s) <> 0 then raise exception 'T1.8 : compteur'; end if;

  -- Message mail : Contacté, « Mail envoyé », relance J+7, compteur messages à part
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'message', null, 'Bonjour', null, null, false, 'mail');
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'message', null, 'Bonjour', null, null, false, 'mail');
  if (select count(*) from public.historique_actions where id_prospect = v_c and type_action = 'Mail envoyé') <> 1 then raise exception 'T1.9 : historique mail'; end if;
  if (select count(*) from public.taches where contact_id = v_c) <> 1 then raise exception 'T1.9 : relance J+7'; end if;
  if (select (nb_contacts, nb_messages) from public.sessions_prospection where id = v_s) <> (0, 1) then raise exception 'T1.9 : compteurs'; end if;
  -- puis un appel sur la même personne : deux lignes de journal
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'unreachable');
  if (select count(*) from public.historique_actions where id_prospect = v_c) <> 2 then raise exception 'T1.9 : appel + message = 2 lignes'; end if;
  if (select statut from public.session_prospection_contacts where session_id = v_s and contact_id = v_c) <> 'unreachable' then raise exception 'T1.9 : statut'; end if;

  -- Ne plus appeler : Ne pas recontacter
  v_j := public.enregistrer_resultat_appel(v_s, v_c2, 'not_interested', null, null, null, null, true);
  if (select etape_prospect from public.contacts where id = v_c2) <> 'Ne pas recontacter' then raise exception 'T1.10 : NPC'; end if;

  -- Personne hors session : refusé
  v_ok := false;
  begin perform public.enregistrer_resultat_appel(v_s, -1, 'called'); exception when no_data_found then v_ok := true; end;
  if not v_ok then raise exception 'T1.11 : contact hors session non refusé'; end if;

  raise notice 'Tests T1.1 à T1.11 : OK';
end $$;
rollback to savepoint tests_t1;

commit;
