-- ══════════════════════════════════════════════════════════════════════
-- 66 — Porte d'appel : une ligne d'historique PAR APPEL   (20/11/2026, suite de T1, décisions de Nicolas)
-- BLOC 2/3 — APPLY (transactionnel, auto-testé, tout ou rien). Prérequis : db/65 en place. ADDITIF.
--
-- DÉCISIONS ACTÉES (Nicolas, 20/11) :
--   * Direction (admin) : lecture seule sur la session d'un autre. La porte refuse d'y noter un résultat (db/65, inchangé).
--   * « Ne plus appeler » arrête TOUTES les séquences Jules en cours de la fiche, y compris celles d'un collègue
--     (RGPD ; l'écran CRM n'arrête que celles de l'utilisateur). Comportement db/65 gardé, testé ici (T1.21).
--   * Un deuxième appel à la même personne AJOUTE une ligne d'historique (nouveau dans ce fichier).
--   * M1 (tranché, VOULU) : corriger un geste (même geste, autre résultat) peut faire sortir de « Ne pas recontacter »
--     SEULEMENT si c'est ce même geste qui l'avait posé et que personne n'a touché la fiche depuis : c'est la
--     correction d'un mauvais tap (spec §11). Un NOUVEL appel repart de la fiche actuelle : « Ne pas recontacter »
--     y reste terminal (T1.22). Un « Ne pas recontacter » posé par quelqu'un d'autre n'est jamais défait.
--     Les tâches annulées et séquences arrêtées à l'entrée en NPC ne sont pas rouvertes par une correction.
--
-- CE QUI CHANGE :
--   1. session_prospection_contacts : geste_id (identifiant du geste fourni par l'appli), nb_appels, appels_precedents
--      (pile des appels précédents de la personne dans la session : leur ligne d'historique et leur tâche restent).
--   2. enregistrer_resultat_appel gagne deux paramètres EN FIN, avec valeur par défaut (appels actuels inchangés) :
--      p_nouvel_appel boolean default false, p_geste_id uuid default null.
--        - p_nouvel_appel = vrai et p_geste_id différent du geste en cours : NOUVEL appel = nouvelle ligne
--          d'historique, nouvelle tâche ; l'appel précédent garde les siennes.
--        - même p_geste_id : rejeu ou correction de SA ligne (jamais de doublon).
--        - p_resultat = 'none' : annule le DERNIER appel (sa ligne, sa tâche à faire) ; l'appel précédent redevient
--          le résultat et la fiche revient à son état d'avant ce geste (si personne ne l'a touchée).
--   2 bis. Idempotence par geste (relecture db/66) : gestes_annules garde les gestes annulés ; un geste déjà empilé,
--      déjà annulé, ou une annulation qui ne vise plus le dernier appel revient sans rien écrire (deja_traite = true).
--      Corriger un ancien appel (autre geste que le dernier, sans p_nouvel_appel) est refusé. Un 'none' SANS geste
--      (appelant à 10 paramètres, écran CRM) annule toute la pile, comme db/65. Toute écriture de la porte est limitée
--      à l'historique et aux tâches de CETTE fiche.
--   2 ter. Filet renforcé : trg_spc_garde_porte devient BEFORE INSERT OR UPDATE et protège toutes les colonnes de la porte.
--   3. M5 : retirer une ligne d'historique remet contacts.date_dernier à la date de la dernière ligne restante
--      (seulement si date_dernier venait de la ligne retirée, et s'il reste une ligne ; sinon inchangé).
--
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/66_porte_un_historique_par_appel_2_apply.sql
-- Retour arrière : db/66_porte_un_historique_par_appel_rollback.sql (à passer AVANT celui de db/65)
-- ══════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP on
begin;

do $$
begin
  if to_regprocedure('public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text)') is null then
    raise exception 'db/65 absente (porte à 10 paramètres introuvable) : arrêt';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public'
              and table_name = 'session_prospection_contacts' and column_name = 'geste_id') then
    raise exception 'db/66 déjà passée : arrêt';
  end if;
  if to_regclass('public._fn_bak_db66_20261120') is not null then
    raise exception 'Sauvegarde _fn_bak_db66_20261120 déjà présente : arrêt';
  end if;
end $$;

-- ─── 0. Sauvegarde de la porte db/65 (pour le retour arrière) ───
create table public._fn_bak_db66_20261120 as
  select 'public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text)'::text as fonction,
         pg_get_functiondef('public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text)'::regprocedure) as definition,
         now() as sauvegarde_le
  union all
  select 'public.spc_garde_porte()', pg_get_functiondef('public.spc_garde_porte()'::regprocedure), now();
alter table public._fn_bak_db66_20261120 enable row level security;
revoke all on public._fn_bak_db66_20261120 from anon, authenticated;

-- ─── 1. Colonnes ───
alter table public.session_prospection_contacts
  add column geste_id uuid,
  add column nb_appels integer not null default 0,
  add column appels_precedents jsonb,
  add column gestes_annules uuid[];
update public.session_prospection_contacts set nb_appels = 1
 where geste_at is not null and statut in ('called','interested','unreachable','not_interested');

-- ─── 2. M5 : date_dernier après retrait d'une ligne d'historique ───
create or replace function public._spc_date_dernier_retrait(p_contact integer, p_date date)
returns void
language plpgsql
set search_path = public, pg_temp
as $$
declare v_max date;
begin
  if p_date is null then return; end if;
  -- Une autre ligne du même jour ou plus récente existe : date_dernier reste juste.
  if exists (select 1 from public.historique_actions where id_prospect = p_contact and date >= p_date) then return; end if;
  select max(date) into v_max from public.historique_actions where id_prospect = p_contact and date <= current_date;
  if v_max is null then return; end if;   -- plus aucune ligne : on ne sait pas d'où venait l'ancienne valeur, on n'y touche pas
  update public.contacts set date_dernier = v_max
   where id = p_contact and date_dernier is not null
     and ((date_dernier at time zone 'Europe/Paris')::date = p_date or (date_dernier at time zone 'UTC')::date = p_date);
end $$;
revoke all on function public._spc_date_dernier_retrait(integer, date) from public, anon, authenticated;

-- ─── 3. La porte, avec p_nouvel_appel et p_geste_id (remplace la version à 10 paramètres) ───
drop function public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text);
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
  p_note_suite text default null,       -- note de la relance (libellé de la prochaine action, comme au CRM)
  p_nouvel_appel boolean default false, -- db/66 : vrai = un NOUVEL appel à la même personne (nouvelle ligne d'historique)
  p_geste_id uuid default null          -- db/66 : identifiant du geste, fourni par l'appli ; obligatoire pour un nouvel appel
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
  v_nouveau boolean := false;
  v_pop jsonb;
  v_hdate date;
  i int;
begin
  -- a. Appelant : une personne connectée avec un profil. Pas d'anon, pas de clé service.
  if v_uid is null then
    raise exception 'Enregistrement refusé : il faut être connecté.' using errcode = '42501';
  end if;
  select p.nom, p.role into v_nom, v_role from public.profiles p where p.id = v_uid;
  if v_nom is null then
    raise exception 'Enregistrement refusé : profil introuvable.' using errcode = '42501';
  end if;
  -- Relecture B1 : un partner (ou tout autre rôle) ne passe pas, même sur une session à son nom.
  if v_role is distinct from 'admin' and v_role is distinct from 'commercial' then
    raise exception 'Enregistrement refusé : réservé aux commerciaux.' using errcode = '42501';
  end if;
  -- Filet db/65 : signale au trigger trg_spc_garde_porte que l'écriture vient de la porte.
  perform set_config('crm.porte_appel', '1', true);

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
  if p_suite = 'rdv' and p_date_suite is null then
    raise exception 'La suite « RDV pris » demande la date du RDV.' using errcode = '22023';
  end if;
  if p_suite = 'rdv' and p_resultat <> 'interested' then
    raise exception 'La suite « RDV pris » ne va qu''avec « Intéressant ».' using errcode = '22023';
  end if;
  if coalesce(p_nouvel_appel, false) and not (p_resultat = any (c_appels)) then
    raise exception 'Un nouvel appel demande un résultat d''appel.' using errcode = '22023';
  end if;
  if coalesce(p_nouvel_appel, false) and p_geste_id is null then
    raise exception 'Un nouvel appel demande son identifiant de geste (p_geste_id), pour qu''un rejeu ne le double pas.' using errcode = '22023';
  end if;

  -- c. Session (verrouillée : les gestes d'une même session passent l'un après l'autre) et droits.
  select * into s from public.sessions_prospection where id = p_session for update;
  if not found then
    raise exception 'Session introuvable.' using errcode = 'P0002';
  end if;
  -- Spec §10 : la direction voit tout en lecture, mais ne note jamais un résultat à la place de quelqu'un.
  if s.responsable is distinct from v_nom then
    raise exception 'Enregistrement refusé : cette session est celle de %.', s.responsable using errcode = '42501';
  end if;
  -- Ordre des verrous : la fiche avant la ligne de session (comme fusionner_contacts et supprimer_fiche).
  perform 1 from public.contacts where id = p_contact for update;

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

  -- Relecture db/66 : idempotence par geste.
  if p_geste_id is not null and p_geste_id is distinct from r.geste_id
     and (p_geste_id = any (coalesce(r.gestes_annules, '{}'::uuid[]))
          or exists (select 1 from jsonb_array_elements(coalesce(r.appels_precedents, '[]'::jsonb)) e where e ->> 'geste_id' = p_geste_id::text)
          or (p_resultat = 'none' and r.geste_id is not null)) then
    -- geste déjà empilé, déjà annulé, ou annulation qui ne vise plus le dernier appel : rejeu tardif, rien n'est réécrit
    return jsonb_build_object('ok', true, 'deja_traite', true, 'session', p_session, 'contact', p_contact,
                              'resultat', r.statut, 'nb_appels', coalesce(r.nb_appels, 0), 'geste_id', r.geste_id);
  end if;
  if not coalesce(p_nouvel_appel, false) and p_resultat = any (c_appels) and p_geste_id is not null
     and r.geste_id is not null and p_geste_id <> r.geste_id and r.statut = any (c_appels) then
    raise exception 'Ce geste n''est pas le dernier appel : nouvel appel (p_nouvel_appel) ou correction du dernier.' using errcode = '22023';
  end if;
  -- Appelant à 10 paramètres (écran CRM : retirer une personne, supprimer la session) : 'none' sans geste = tout annuler, comme db/65.
  if p_resultat = 'none' and p_geste_id is null and r.appels_precedents is not null then
    for i in 1 .. jsonb_array_length(r.appels_precedents) loop
      perform public.enregistrer_resultat_appel(p_session, p_contact, 'none',
                p_geste_id => (select x.geste_id from public.session_prospection_contacts x where x.id = r.id));
    end loop;
    select * into r from public.session_prospection_contacts where id = r.id;
    select * into c from public.contacts where id = p_contact;
  end if;

  -- d0. Nouvel appel (db/66) : l'appel précédent garde sa ligne d'historique et sa tâche ; il est empilé dans
  --     appels_precedents et le nouvel appel repart de la fiche telle qu'elle est maintenant. Un rejeu du même
  --     geste (même p_geste_id) n'est PAS un nouvel appel : c'est un rejeu ou une correction de SA ligne.
  if coalesce(p_nouvel_appel, false) and r.statut = any (c_appels) and p_geste_id is distinct from r.geste_id then
    v_nouveau := true;
    r.appels_precedents := coalesce(r.appels_precedents, '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'statut', r.statut, 'precision', r.precision, 'notes', r.notes, 'suite', r.suite, 'date_suite', r.date_suite,
      'ne_plus_appeler', r.ne_plus_appeler, 'want_relance', r.want_relance, 'relance_date', r.relance_date,
      'relance_note', r.relance_note, 'appel_at', r.appel_at, 'historique_id', r.historique_id, 'tache_id', r.tache_id,
      'geste_id', r.geste_id, 'contact_avant', r.contact_avant, 'contact_pose', r.contact_pose));
    r.historique_id := null; r.tache_id := null; r.contact_avant := null; r.contact_pose := null; r.appel_at := null;
    r.statut := 'none';
    r.nb_appels := coalesce(r.nb_appels, 0) + 1;
  end if;

  -- d. Ligne de session : on pose le nouvel état du geste.
  if p_resultat = 'none' and r.statut = any (c_appels) and jsonb_array_length(coalesce(r.appels_precedents, '[]'::jsonb)) > 0 then
    -- db/66 : annuler le DERNIER appel. Sa ligne d'historique et sa tâche (si encore à faire) sont retirées ; la fiche
    -- revient à son état d'avant ce geste si personne ne l'a touchée depuis ; l'appel précédent redevient le résultat.
    if r.historique_id is not null then
      delete from public.historique_actions where id = r.historique_id and id_prospect = p_contact returning date into v_hdate;
      perform public._spc_date_dernier_retrait(p_contact, v_hdate);
      v_ecrit := v_ecrit || 'historique_retire'::text;
    end if;
    if r.tache_id is not null then
      select t.statut into v_tache_statut from public.taches t where t.id = r.tache_id and t.contact_id = p_contact;
      if found and v_tache_statut = 'a_faire' then
        delete from public.taches where id = r.tache_id and contact_id = p_contact;
        v_ecrit := v_ecrit || 'tache_retiree'::text;
      end if;
    end if;
    v_actuel := jsonb_build_object('etape_prospect', c.etape_prospect, 'prochaine_action_date', public._ts_utc(c.prochaine_action_date),
                  'prochaine_action_libelle', c.prochaine_action_libelle, 'motif_perte', c.motif_perte,
                  'motif_perte_precision', c.motif_perte_precision);
    if r.contact_pose is not null and (r.contact_pose - '_statut') = v_actuel
       and r.contact_pose ->> '_statut' is not distinct from c.statut and r.contact_avant is distinct from v_actuel then
      update public.contacts
         set etape_prospect = r.contact_avant ->> 'etape_prospect',
             prochaine_action_date = (r.contact_avant ->> 'prochaine_action_date')::timestamptz,
             prochaine_action_libelle = r.contact_avant ->> 'prochaine_action_libelle',
             motif_perte = r.contact_avant ->> 'motif_perte',
             motif_perte_precision = r.contact_avant ->> 'motif_perte_precision',
             updated_at = v_now
       where id = p_contact;
      select * into c from public.contacts where id = p_contact;
      v_ecrit := v_ecrit || 'fiche'::text;
    end if;
    if r.geste_id is not null then r.gestes_annules := array_append(coalesce(r.gestes_annules, '{}'::uuid[]), r.geste_id); end if;
    v_pop := r.appels_precedents -> -1;
    r.appels_precedents := r.appels_precedents - (-1);
    if jsonb_array_length(r.appels_precedents) = 0 then r.appels_precedents := null; end if;
    r.statut := v_pop ->> 'statut';
    r.precision := v_pop ->> 'precision';
    r.notes := v_pop ->> 'notes';
    r.suite := v_pop ->> 'suite';
    r.date_suite := (v_pop ->> 'date_suite')::timestamptz;
    r.ne_plus_appeler := coalesce((v_pop ->> 'ne_plus_appeler')::boolean, false);
    r.want_relance := coalesce((v_pop ->> 'want_relance')::boolean, false);
    r.relance_date := (v_pop ->> 'relance_date')::date;
    r.relance_note := v_pop ->> 'relance_note';
    r.appel_at := (v_pop ->> 'appel_at')::timestamptz;
    r.historique_id := (v_pop ->> 'historique_id')::integer;
    r.tache_id := v_pop ->> 'tache_id';
    r.geste_id := (v_pop ->> 'geste_id')::uuid;
    r.contact_avant := v_pop -> 'contact_avant';
    r.contact_pose := v_pop -> 'contact_pose';
    if jsonb_typeof(r.contact_avant) = 'null' then r.contact_avant := null; end if;
    if jsonb_typeof(r.contact_pose) = 'null' then r.contact_pose := null; end if;
    r.nb_appels := greatest(coalesce(r.nb_appels, 1) - 1, 0);
    v_canal := 'telephone';
  elsif p_resultat = 'message' then
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
    if r.geste_id is not null then r.gestes_annules := array_append(coalesce(r.gestes_annules, '{}'::uuid[]), r.geste_id); end if;
    r.geste_id := null; r.nb_appels := 0;
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
    r.geste_id := coalesce(p_geste_id, r.geste_id);
    if coalesce(r.nb_appels, 0) = 0 then r.nb_appels := 1; end if;
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
  -- Le statut du contact fait partie de la photo (relecture I1) : un passage en Client entre deux gestes compte
  -- comme une modification par quelqu'un d'autre.
  if r.contact_avant is null or (r.contact_pose is not null and
     ((r.contact_pose - '_statut') is distinct from v_actuel or r.contact_pose ->> '_statut' is distinct from c.statut)) then
    r.contact_avant := v_actuel;
  end if;
  v_base := r.contact_avant;
  v_etape_avant := c.etape_prospect;

  v_want := r.want_relance;
  -- Échéance de la relance d'un message : celle demandée, sinon J+7 à 9 h (Paris).
  if r.message_at is not null then
    if p_resultat = 'message' then
      v_msg_due := case when coalesce(p_suite, '') = 'aucune' then null
                        else coalesce(p_date_suite, ((((r.message_at at time zone 'Europe/Paris')::date) + 7) + time '09:00') at time zone 'Europe/Paris') end;
    else
      select t.due_date into v_msg_due from public.taches t where t.id = r.message_tache_id and t.contact_id = p_contact;
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
  r.contact_pose := case when r.statut = 'none' then null else v_cible || jsonb_build_object('_statut', c.statut) end;
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
    if r.historique_id is not null and exists (select 1 from public.historique_actions where id = r.historique_id and id_prospect = p_contact) then
      update public.historique_actions set type_action = 'Appel sortant', details = v_details
       where id = r.historique_id and id_prospect = p_contact and (type_action, details) is distinct from ('Appel sortant', v_details);
    else
      insert into public.historique_actions (id_prospect, date, type_action, details, responsable)
      values (p_contact, coalesce((r.appel_at at time zone 'Europe/Paris')::date, v_jour), 'Appel sortant', v_details, v_nom) returning id into r.historique_id;
      v_ecrit := v_ecrit || 'historique'::text;
    end if;
  elsif r.historique_id is not null then
    delete from public.historique_actions where id = r.historique_id and id_prospect = p_contact returning date into v_hdate;
    perform public._spc_date_dernier_retrait(p_contact, v_hdate);
    r.historique_id := null;
    v_ecrit := v_ecrit || 'historique_retire'::text;
  end if;

  -- g. Tâche de suite de l'appel : UNE tâche, corrigée ou retirée. Un appel qu'on dépile (annulation du suivant)
  --    garde sa tâche telle quelle : jamais recréée ni corrigée (relecture db/66, I2).
  if v_pop is null then
  if r.statut = any (c_appels) and r.want_relance and r.date_suite is not null then
    v_titre := case r.suite when 'rdv' then 'Préparer le RDV avec ' || v_nom_contact
                            when 'presentation' then 'Envoyer une présentation à ' || v_nom_contact
                            else 'Relance ' || v_nom_contact || coalesce(' — ' || v_societe, '') end;
    v_due := case when r.suite = 'rdv' then r.date_suite - interval '1 hour' else r.date_suite end;
    v_notes := concat_ws(E'\n', 'Session : ' || s.nom, 'Statut : ' || v_label, r.relance_note);
    select t.statut into v_tache_statut from public.taches t where t.id = r.tache_id and t.contact_id = p_contact;
    -- Tâche liée encore à faire : corrigée. Faite ou annulée : gardée si la suite demandée est la même, sinon
    -- une nouvelle tâche est créée (relecture I2 : un rappel après une tâche faite ne doit pas se perdre).
    if r.tache_id is not null and found and (v_tache_statut = 'a_faire'
       or (select (t.titre, t.due_date) from public.taches t where t.id = r.tache_id and t.contact_id = p_contact) is not distinct from (v_titre, v_due)) then
      if v_tache_statut = 'a_faire' then
        update public.taches set titre = v_titre, due_date = v_due, notes = v_notes, updated_at = v_now
         where id = r.tache_id and (titre, due_date, notes) is distinct from (v_titre, v_due, v_notes);
      end if;
    else
      r.tache_id := 'tw_relance_' || p_contact || '_' || (extract(epoch from clock_timestamp()) * 1000)::bigint || '_a';
      insert into public.taches (id, titre, statut, due_date, contact_id, session_prospection_id, notes, responsable)
      values (r.tache_id, v_titre, 'a_faire', v_due, p_contact, p_session, v_notes, v_nom);
      v_ecrit := v_ecrit || 'tache'::text;
    end if;
  elsif r.tache_id is not null then
    select t.statut into v_tache_statut from public.taches t where t.id = r.tache_id and t.contact_id = p_contact;
    if found and v_tache_statut = 'a_faire' then
      delete from public.taches where id = r.tache_id and contact_id = p_contact;
      v_ecrit := v_ecrit || 'tache_retiree'::text;
    end if;
    r.tache_id := null;
  end if;
  end if;

  -- h. Message envoyé : UNE ligne d'historique (« Mail envoyé » ou « LinkedIn ») et UNE relance.
  if r.message_at is not null then
    v_details := concat_ws(E'\n', 'Session : ' || s.nom,
                   'Message envoyé par ' || case r.message_canal when 'mail' then 'mail' else 'LinkedIn' end || ' (envoyé par ' || v_nom || ')',
                   case when p_resultat = 'message' and nullif(p_note, '') is not null then left(p_note, 500) end);
    if r.message_historique_id is not null and exists (select 1 from public.historique_actions where id = r.message_historique_id and id_prospect = p_contact) then
      if p_resultat = 'message' then
        update public.historique_actions
           set type_action = case r.message_canal when 'mail' then 'Mail envoyé' else 'LinkedIn' end, details = v_details
         where id = r.message_historique_id and id_prospect = p_contact;
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
        select t.statut into v_tache_statut from public.taches t where t.id = r.message_tache_id and t.contact_id = p_contact;
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
        select t.statut into v_tache_statut from public.taches t where t.id = r.message_tache_id and t.contact_id = p_contact;
        if found and v_tache_statut = 'a_faire' then delete from public.taches where id = r.message_tache_id and contact_id = p_contact; end if;
        r.message_tache_id := null;
      end if;
    end if;
  else
    if r.message_historique_id is not null then
      delete from public.historique_actions where id = r.message_historique_id and id_prospect = p_contact returning date into v_hdate;
      perform public._spc_date_dernier_retrait(p_contact, v_hdate);
      r.message_historique_id := null;
      v_ecrit := v_ecrit || 'historique_message_retire'::text;
    end if;
    if r.message_tache_id is not null then
      select t.statut into v_tache_statut from public.taches t where t.id = r.message_tache_id and t.contact_id = p_contact;
      if found and v_tache_statut = 'a_faire' then delete from public.taches where id = r.message_tache_id and contact_id = p_contact; end if;
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
         maj_par = r.maj_par, geste_id = r.geste_id, nb_appels = coalesce(r.nb_appels, 0),
         appels_precedents = r.appels_precedents, gestes_annules = r.gestes_annules
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
    'nouvel_appel', v_nouveau, 'nb_appels', coalesce(r.nb_appels, 0), 'geste_id', r.geste_id,
    'etape_avant', v_etape_avant, 'etape_apres', v_etape_apres,
    'historique_id', r.historique_id, 'tache_id', r.tache_id,
    'message_historique_id', r.message_historique_id, 'message_tache_id', r.message_tache_id,
    'npc', jsonb_build_object('taches_annulees', v_npc_taches, 'sequences_arretees', v_npc_seq),
    'ecrit', to_jsonb(v_ecrit),
    'compteurs', (select jsonb_build_object('appels', nb_contacts, 'interesses', nb_interesses, 'injoignables', nb_injoignables,
                                            'relances', nb_relances, 'messages', nb_messages)
                    from public.sessions_prospection where id = p_session));
end $$;

revoke all on function public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text,boolean,uuid) from public, anon;
grant execute on function public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text,boolean,uuid) to authenticated;
do $$ begin
  if has_function_privilege('anon', 'public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text,boolean,uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.enregistrer_resultat_appel(uuid,integer,text,text,text,text,timestamptz,boolean,text,text,boolean,uuid)', 'execute') then
    raise exception 'Droits de la porte incorrects (anon doit être refusé, authenticated autorisé) : arrêt';
  end if;
end $$;

-- ─── 3 bis. Filet renforcé (relecture db/66, B1) : hors de la porte, un utilisateur (authenticated, anon) ne peut ni
--     poser ni modifier les colonnes tenues par la porte (liens vers l'historique et les tâches, pile, photos de fiche).
--     Sinon il pourrait y glisser l'id d'une ligne d'historique ou d'une tâche d'un collègue, que la porte réécrirait.
--     Les fonctions security definer (fusion, corbeille) gardent la seule règle db/65.
create or replace function public.spc_garde_porte()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if coalesce(current_setting('crm.porte_appel', true), '') = '1' then
    return new;   -- la porte
  end if;
  if current_user not in ('authenticated','anon') then
    null;         -- fonctions security definer (fusion, corbeille) : seules les règles db/65 ci-dessous s'appliquent
  elsif tg_op = 'INSERT' then
    if new.geste_at is not null or new.historique_id is not null or new.tache_id is not null
       or new.message_historique_id is not null or new.message_tache_id is not null or new.contact_avant is not null
       or new.contact_pose is not null or new.geste_id is not null or new.appels_precedents is not null or coalesce(new.nb_appels, 0) <> 0
       or new.gestes_annules is not null or new.message_at is not null or new.appel_at is not null then
      raise exception 'Colonnes tenues par la porte d''appel : à poser par enregistrer_resultat_appel.' using errcode = '42501';
    end if;
    return new;
  elsif (new.geste_at, new.historique_id, new.tache_id, new.message_historique_id, new.message_tache_id, new.contact_avant,
      new.contact_pose, new.geste_id, new.appels_precedents, new.nb_appels, new.message_at, new.appel_at, new.gestes_annules)
     is distinct from
     (old.geste_at, old.historique_id, old.tache_id, old.message_historique_id, old.message_tache_id, old.contact_avant,
      old.contact_pose, old.geste_id, old.appels_precedents, old.nb_appels, old.message_at, old.appel_at, old.gestes_annules) then
    raise exception 'Colonnes tenues par la porte d''appel : à poser par enregistrer_resultat_appel.' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and old.geste_at is not null
     and (new.statut, new.notes, new.want_relance, new.relance_date, new.relance_note)
         is distinct from (old.statut, old.notes, old.want_relance, old.relance_date, old.relance_note) then
    raise exception 'Ligne tenue par la porte d''appel : à corriger par enregistrer_resultat_appel.' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger trg_spc_garde_porte on public.session_prospection_contacts;
create trigger trg_spc_garde_porte before insert or update on public.session_prospection_contacts
  for each row execute function public.spc_garde_porte();

-- ─── 4. Tests db/65 rejoués sur la nouvelle porte ───
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

  -- T1.12 : filet, une écriture hors porte sur une ligne tenue par la porte est refusée
  perform set_config('crm.porte_appel', '', true);
  v_ok := false;
  begin update public.session_prospection_contacts set statut = 'called' where session_id = v_s and contact_id = v_c;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'T1.12 : écriture hors porte non refusée'; end if;

  -- T1.13 : un admin ne note pas dans la session d'un autre
  perform set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where role = 'admin' and nom <> n_a limit 1), 'role', 'authenticated')::text, true);
  v_ok := false;
  begin perform public.enregistrer_resultat_appel(v_s, v_c, 'called'); exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'T1.13 : admin non refusé'; end if;

  -- T1.14 : un partner est refusé même sur une session à son nom
  if exists (select 1 from public.profiles where role = 'partner') then
    update public.sessions_prospection set responsable = (select nom from public.profiles where role = 'partner' limit 1) where id = v_s;
    perform set_config('request.jwt.claims', json_build_object('sub', (select id from public.profiles where role = 'partner' limit 1), 'role', 'authenticated')::text, true);
    v_ok := false;
    begin perform public.enregistrer_resultat_appel(v_s, v_c2, 'called'); exception when insufficient_privilege then v_ok := true; end;
    if not v_ok then raise exception 'T1.14 : partner non refusé'; end if;
  end if;

  raise notice 'Tests T1.1 à T1.14 : OK';
end $$;
rollback to savepoint tests_t1;

-- ─── 5. Tests db/66 (savepoint annulé ; toute erreur annule TOUT) ───
savepoint tests_t66;
do $$
declare
  u_a uuid; n_a text; u_b uuid;
  v_s uuid; v_c int; v_j jsonb; v_ok boolean;
  g1 uuid := gen_random_uuid(); g2 uuid := gen_random_uuid();
  v_h1 int; v_dd date;
begin
  select id, nom into u_a, n_a from public.profiles where role = 'commercial' order by nom limit 1;
  select id into u_b from public.profiles where role = 'commercial' and id <> u_a order by nom limit 1;
  insert into public.contacts (prenom, nom, statut, responsable, etape_prospect)
  values ('Zz', 'TestPorte66', 'Prospect', n_a, 'À contacter') returning id into v_c;
  insert into public.historique_actions (id_prospect, date, type_action, details, responsable)
  values (v_c, date '2026-01-15', 'Note interne', 'test', n_a);
  insert into public.sessions_prospection (nom, responsable, statut) values ('T66 test', n_a, 'active') returning id into v_s;
  insert into public.session_prospection_contacts (session_id, contact_id) values (v_s, v_c);
  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);

  -- T1.15 : appel 1 puis appel 2 = 2 lignes
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'unreachable', p_precision => 'messagerie', p_geste_id => g1);
  v_h1 := (v_j ->> 'historique_id')::int;
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'called', p_note => 'on s''est parlé', p_nouvel_appel => true, p_geste_id => g2);
  if (select count(*) from public.historique_actions where id_prospect = v_c and type_action = 'Appel sortant') <> 2 then raise exception 'T1.15 : 2 lignes attendues'; end if;
  if (v_j ->> 'nb_appels')::int <> 2 or not (v_j ->> 'nouvel_appel')::boolean then raise exception 'T1.15 : nb_appels %', v_j; end if;

  -- T1.16 : rejeu de l'appel 2 (même geste) = toujours 2
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'called', p_note => 'on s''est parlé', p_nouvel_appel => true, p_geste_id => g2);
  if (select count(*) from public.historique_actions where id_prospect = v_c and type_action = 'Appel sortant') <> 2 then raise exception 'T1.16 : rejeu a doublé'; end if;

  -- T1.17 : correction de l'appel 2 = 2 lignes, la 2e modifiée, la 1re intacte
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'interested', p_note => 'projet', p_nouvel_appel => true, p_geste_id => g2);
  if (select count(*) from public.historique_actions where id_prospect = v_c and type_action = 'Appel sortant') <> 2 then raise exception 'T1.17 : nombre de lignes'; end if;
  if (select details from public.historique_actions where id = v_h1) not like '%Pas répondu%' then raise exception 'T1.17 : ligne 1 modifiée'; end if;
  if (select details from public.historique_actions where id = (v_j ->> 'historique_id')::int) not like '%Intéressant%' then raise exception 'T1.17 : ligne 2 non corrigée'; end if;
  if (select etape_prospect from public.contacts where id = v_c) <> 'En discussion' then raise exception 'T1.17 : étape'; end if;

  -- T1.18 : annulation de l'appel 2 = la ligne 1 seule, résultat de l'appel 1, fiche d'après l'appel 1
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'none', p_geste_id => g2);
  if (select count(*) from public.historique_actions where id_prospect = v_c and type_action = 'Appel sortant') <> 1
     or not exists (select 1 from public.historique_actions where id = v_h1) then raise exception 'T1.18 : lignes'; end if;
  if (select statut from public.session_prospection_contacts where session_id = v_s and contact_id = v_c) <> 'unreachable' then raise exception 'T1.18 : statut'; end if;
  if (select etape_prospect from public.contacts where id = v_c) <> 'Contacté' then raise exception 'T1.18 : étape %', (select etape_prospect from public.contacts where id = v_c); end if;
  if (v_j ->> 'nb_appels')::int <> 1 then raise exception 'T1.18 : nb_appels'; end if;

  -- T1.18b : rejeu de l'annulation de l'appel 2 et rejeu tardif de l'appel 2 = sans effet
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'none', p_geste_id => g2);
  if not coalesce((v_j ->> 'deja_traite')::boolean, false) then raise exception 'T1.18b : rejeu de l''annulation non ignoré'; end if;
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'interested', p_nouvel_appel => true, p_geste_id => g2);
  if not coalesce((v_j ->> 'deja_traite')::boolean, false)
     or (select count(*) from public.historique_actions where id_prospect = v_c and type_action = 'Appel sortant') <> 1 then
    raise exception 'T1.18b : un appel annulé a été recréé'; end if;

  -- T1.19 : annulation de l'appel 1 = 0 ligne, fiche à « À contacter », date_dernier remise au 15/01 (M5)
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'none', p_geste_id => g1);
  if (select count(*) from public.historique_actions where id_prospect = v_c and type_action = 'Appel sortant') <> 0 then raise exception 'T1.19 : lignes'; end if;
  if (select etape_prospect from public.contacts where id = v_c) <> 'À contacter' then raise exception 'T1.19 : étape'; end if;
  select (date_dernier at time zone 'Europe/Paris')::date into v_dd from public.contacts where id = v_c;
  if v_dd is distinct from date '2026-01-15' then raise exception 'T1.19 : date_dernier % au lieu du 15/01', v_dd; end if;

  -- T1.20 : nouvel appel sans identifiant de geste = refusé
  v_ok := false;
  begin perform public.enregistrer_resultat_appel(v_s, v_c, 'called', p_nouvel_appel => true);
  exception when invalid_parameter_value then v_ok := true; end;
  if not v_ok then raise exception 'T1.20 : nouvel appel sans geste accepté'; end if;

  -- T1.21 (décision I4) : « Ne plus appeler » arrête la séquence Jules d'un collègue
  insert into jules.agent_sequences (owner_id, mission_id, target_kind, target_ref, target_label, contact_id, statut)
  values (u_b, (select id from jules.agent_missions order by created_at limit 1), 'contact_crm', v_c::text, 'test T66', v_c, 'active');
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'not_interested', p_ne_plus_appeler => true, p_geste_id => gen_random_uuid());
  if (select etape_prospect from public.contacts where id = v_c) <> 'Ne pas recontacter' then raise exception 'T1.21 : NPC'; end if;
  if exists (select 1 from jules.agent_sequences where contact_id = v_c and statut <> 'stopped') then raise exception 'T1.21 : séquence du collègue non arrêtée'; end if;

  -- T1.22 (M1) : un NOUVEL appel ne fait jamais sortir de « Ne pas recontacter »
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'called', p_nouvel_appel => true, p_geste_id => gen_random_uuid());
  if (select etape_prospect from public.contacts where id = v_c) <> 'Ne pas recontacter' then raise exception 'T1.22 : sorti de NPC'; end if;

  -- T1.23 (B3) : 'none' SANS geste (écran CRM : retirer une personne) annule toute la pile, comme db/65
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'called', p_nouvel_appel => true, p_geste_id => gen_random_uuid());
  v_j := public.enregistrer_resultat_appel(v_s, v_c, 'none');
  if (select count(*) from public.historique_actions where id_prospect = v_c and type_action = 'Appel sortant') <> 0 then raise exception 'T1.23 : lignes restantes'; end if;
  if (select statut from public.session_prospection_contacts where session_id = v_s and contact_id = v_c) <> 'none' then raise exception 'T1.23 : statut'; end if;

  -- T1.24 (B1) : un commercial ne peut pas glisser un lien de la porte dans sa ligne hors de la porte
  perform set_config('crm.porte_appel', '', true);
  set local role authenticated;
  v_ok := false;
  begin update public.session_prospection_contacts set historique_id = v_h1 where session_id = v_s and contact_id = v_c;
  exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then reset role; raise exception 'T1.24 : forge acceptée'; end if;
  v_ok := false;
  begin update public.session_prospection_contacts set appels_precedents = '[]'::jsonb where session_id = v_s and contact_id = v_c;
  exception when insufficient_privilege then v_ok := true; end;
  reset role;
  if not v_ok then raise exception 'T1.24 : pile forgée acceptée'; end if;

  raise notice 'Tests db/66 T1.15 à T1.24 : OK';
end $$;
rollback to savepoint tests_t66;

commit;
