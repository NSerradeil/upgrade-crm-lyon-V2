-- ══════════════════════════════════════════════════════════════════════
-- 60 — Suppression par le responsable, avec corbeille (lot 1 : comptes + contacts)
-- Spec : SPECS_CRM/2026-11-05-suppression-responsable-archive.md (décisions D1 à D5 tranchées par Nicolas le 05/11)
-- BLOC 2/3 — APPLY (transactionnel, auto-testé, tout ou rien)
--
-- CE QUE ÇA AJOUTE :
--   1. Table `corbeille` : copie complète de chaque fiche supprimée (ligne + enfants + références détachées).
--      Lecture réservée aux admins, aucune écriture directe (seules les fonctions y écrivent).
--   2. Table `corbeille_journal` : une ligne par événement (suppression, suppression_admin, restauration,
--      purge, purge_auto), sans contenu métier. Survit aux purges.
--   3. `supprimer_fiche(p_type, p_id, p_motif, p_origine, p_forcer)` : LA porte de suppression des comptes et contacts.
--   4. `restaurer_fiche(p_corbeille_id, p_origine)` : remise en place (admin), même id.
--   5. `purger_corbeille(p_corbeille_id | p_avant, p_origine)` : vidage manuel (admin).
--   6. `purger_corbeille_auto()` : purge des archives de plus de 12 mois (D2), pour la clé service / le tick du mini.
--
-- CE QUI CHANGE (fermeture) :
--   7. Politique `delete_contacts` réduite à l'admin (avant : admin OU responsable, sans trace).
--      `comptes_delete_admin` et `contact_compte_delete_admin` : inchangées (déjà admin seul).
--   8. Garde `trg_garde_suppression_directe` (niveau instruction, BEFORE DELETE) sur contacts et comptes :
--      un DELETE direct par un utilisateur connecté NON admin lève une ERREUR explicite au lieu du
--      « 0 ligne, pas d'erreur » de la RLS (fin des faux « supprimé » des vieux clients).
--      EXEMPTÉS : postgres, supabase_admin, service_role (Jules, scripts de fusion de doublons, crm-sql.sh)
--      et les fonctions SECURITY DEFINER (dont supprimer_fiche).
--
-- RÈGLES DE supprimer_fiche :
--   - appelant connecté admin ou commercial (partner refusé) ; clé service acceptée seulement avec
--     p_origine 'jules' ou 'builder' (traitée comme admin) ; superuser en SQL avec p_origine 'builder' idem ;
--   - commercial : uniquement les fiches dont il est responsable ; fiche sans responsable ou d'un membre
--     parti → refus, « demande à un admin » (D4) ; quota 20 suppressions par 24 h ;
--   - admin : toute fiche, archivée aussi (D1), sans quota ; peut forcer les garde-fous (p_forcer, admin seul) ;
--   - compte : refus s'il reste des missions, des besoins ou des contacts ACTIFS rattachés (D5) ;
--     les liens contact↔compte clos partent avec lui (archivés) ;
--   - contact : refus s'il est Consultant CDI / Freelance / Prestataire, lié à une mission, un besoin,
--     une imputation interco, un partner, ou visé par une séquence Jules active / en pause ;
--     son historique, ses liens comptes, candidatures, tâches et lignes de session partent avec lui (archivés) ;
--   - une fiche par appel, verrouillée pendant l'opération.
--
-- Lancer sur le Mac mini (superuser, arrêt à la 1re erreur, relance PostgREST) :
--   zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/60_suppression_archive_2_apply.sql
-- Toute incohérence pendant les tests intégrés → exception → ROLLBACK complet, rien n'est appliqué.
-- Retour arrière : db/60_suppression_archive_rollback.sql
-- ⚠️ À appliquer EN MÊME TEMPS que l'appli (lot 2) : voir l'ordre dans le rapport / la spec (§ 7).
-- ══════════════════════════════════════════════════════════════════════

begin;

-- ─── 1. Corbeille ───
create table if not exists public.corbeille (
  id                bigserial primary key,
  objet_type        text        not null check (objet_type in ('compte','contact','besoin','mission','tache')),
  objet_id          text        not null,
  libelle           text,
  responsable_fiche text,
  ligne             jsonb       not null,
  liens             jsonb       not null default '{}'::jsonb,
  motif             text,
  origine           text        not null check (origine in ('app','mcp','jules','builder')),
  forcee            boolean     not null default false,
  par_nom           text        not null,
  par_user          uuid,
  par_role          text        not null,
  supprime_le       timestamptz not null default now(),
  restaure_le       timestamptz,
  restaure_par      text
);
create index if not exists corbeille_objet_idx on public.corbeille (objet_type, objet_id);
create index if not exists corbeille_quota_idx on public.corbeille (par_user, supprime_le desc);
create index if not exists corbeille_date_idx  on public.corbeille (supprime_le);
comment on table public.corbeille is
  'db/60 : copie complète des fiches supprimées (ligne + enfants + références détachées). Écrite UNIQUEMENT par '
  'supprimer_fiche / restaurer_fiche / purger_corbeille*. Lecture admin. Purge auto à 12 mois (purger_corbeille_auto).';

create table if not exists public.corbeille_journal (
  id           bigserial primary key,
  evenement    text        not null check (evenement in ('suppression','suppression_admin','restauration','purge','purge_auto')),
  corbeille_id bigint,
  objet_type   text        not null,
  objet_id     text        not null,
  libelle      text,
  par_nom      text        not null,
  par_user     uuid,
  origine      text,
  forcee       boolean     not null default false,
  nb_lignes    integer     not null default 0,
  created_at   timestamptz not null default now()
);
create index if not exists corbeille_journal_objet_idx on public.corbeille_journal (objet_type, objet_id, created_at desc);
comment on table public.corbeille_journal is
  'db/60 : trace des suppressions, restaurations et purges (sans contenu métier). Écrite UNIQUEMENT par les fonctions db/60.';

alter table public.corbeille         enable row level security;
alter table public.corbeille_journal enable row level security;
-- Les privilèges par défaut de Supabase donnent tout à anon/authenticated/service_role : on reprend la main.
revoke all on public.corbeille, public.corbeille_journal from public, anon, authenticated, service_role;
grant select on public.corbeille, public.corbeille_journal to authenticated, service_role;
revoke all on sequence public.corbeille_id_seq, public.corbeille_journal_id_seq from public, anon, authenticated, service_role;

drop policy if exists corbeille_lecture_admin on public.corbeille;
create policy corbeille_lecture_admin on public.corbeille
  for select to authenticated using (get_my_role() = 'admin');
drop policy if exists corbeille_journal_lecture_admin on public.corbeille_journal;
create policy corbeille_journal_lecture_admin on public.corbeille_journal
  for select to authenticated using (get_my_role() = 'admin');
-- Aucune policy INSERT/UPDATE/DELETE : seules les fonctions (propriétaire des tables) y écrivent.


-- ─── 2. Qui appelle ? (helper interne) ───
create or replace function public._corbeille_appelant(p_origine text, out o_uid uuid, out o_nom text, out o_role text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  o_uid := auth.uid();
  if o_uid is not null then
    select p.nom, p.role into o_nom, o_role from public.profiles p where p.id = o_uid;
    if o_nom is null or o_role is null then
      raise exception 'Refusé : profil introuvable pour cette session.' using errcode = 'P0001';
    end if;
    return;
  end if;
  -- Clé service (Jules, builders) : seulement avec une origine qui le dit.
  if jules.est_service_jwt() then
    if p_origine in ('jules','builder') then
      o_nom := case p_origine when 'jules' then 'Jules (clé service)' else 'Builder (clé service)' end;
      o_role := 'admin';
      return;
    end if;
    raise exception 'Refusé : avec la clé service, préciser l''origine ''jules'' ou ''builder''.' using errcode = 'P0001';
  end if;
  -- Superuser en SQL direct (crm-sql.sh, Studio) : builder.
  if session_user in ('postgres','supabase_admin') and p_origine = 'builder'
     and coalesce(nullif(current_setting('request.jwt.claims', true), ''), '') = '' then
    o_nom := 'Builder (SQL)';
    o_role := 'admin';
    return;
  end if;
  raise exception 'Refusé : aucune session utilisateur (connexion requise).' using errcode = 'P0001';
end;
$$;
revoke all on function public._corbeille_appelant(text) from public, anon, authenticated, service_role;


-- ─── 3. Réinsertion d'une ligne archivée (helper interne de la restauration) ───
-- N'insère que les colonnes qui existent ENCORE (colonne disparue : ignorée ; colonne nouvelle : valeur par défaut).
-- Rend false (sans planter) si la ligne heurte un id repris, un parent disparu ou une contrainte.
create or replace function public._corbeille_reinserer(p_table regclass, p_ligne jsonb)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cols text;
begin
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into v_cols
  from pg_attribute a
  where a.attrelid = p_table and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
    and p_ligne ? a.attname;
  if v_cols is null then return false; end if;
  begin
    execute format('insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1)', p_table, v_cols, v_cols, p_table)
      using p_ligne;
    return true;
  exception when unique_violation or foreign_key_violation or check_violation or not_null_violation then
    return false;
  end;
end;
$$;
revoke all on function public._corbeille_reinserer(regclass, jsonb) from public, anon, authenticated, service_role;


-- ─── 4. supprimer_fiche ───
create or replace function public.supprimer_fiche(
  p_type    text,
  p_id      text,
  p_motif   text    default null,
  p_origine text    default 'app',
  p_forcer  boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type    text := lower(trim(coalesce(p_type, '')));
  v_origine text := lower(trim(coalesce(p_origine, 'app')));
  v_motif   text := nullif(trim(coalesce(p_motif, '')), '');
  v_forcer  boolean := coalesce(p_forcer, false);
  v_uid uuid; v_nom text; v_role text;
  v_id      bigint;
  v_ligne   jsonb;
  v_resp    text;
  v_lib     text;
  v_statut  text;
  v_liens   jsonb := '{}'::jsonb;
  v_detache jsonb := '[]'::jsonb;
  v_freins  text[] := '{}';
  n_miss int; n_bes int; n_cc int; n_interco int; n_partner int; n_seq int;
  v_quota   int;
  v_arch_id bigint;
  v_nb      int := 0;
  v_k       text;
begin
  if v_origine not in ('app','mcp','jules','builder') then
    raise exception 'Suppression refusée : origine « % » inconnue (app, mcp, jules, builder).', p_origine using errcode = 'P0001';
  end if;

  select a.o_uid, a.o_nom, a.o_role into v_uid, v_nom, v_role from public._corbeille_appelant(v_origine) a;
  if v_role not in ('admin','commercial') then
    raise exception 'Suppression refusée : réservée aux commerciaux et à l''administration.' using errcode = 'P0001';
  end if;
  if v_forcer and v_role <> 'admin' then
    raise exception 'Suppression refusée : seul un admin peut forcer une suppression.' using errcode = 'P0001';
  end if;

  if v_type not in ('compte','contact') then
    raise exception 'Suppression refusée : type « % » non pris en charge (compte ou contact).', p_type using errcode = 'P0001';
  end if;
  if coalesce(trim(p_id), '') !~ '^[0-9]+$' then
    raise exception 'Suppression refusée : identifiant « % » invalide.', p_id using errcode = 'P0001';
  end if;
  v_id := trim(p_id)::bigint;

  -- Fiche verrouillée le temps de l'opération.
  if v_type = 'compte' then
    select to_jsonb(k.*), k.responsable, k.nom into v_ligne, v_resp, v_lib
    from public.comptes k where k.id = v_id for update;
  else
    select to_jsonb(c.*), c.responsable, nullif(trim(coalesce(c.prenom, '') || ' ' || coalesce(c.nom, '')), ''), c.statut
      into v_ligne, v_resp, v_lib, v_statut
    from public.contacts c where c.id = v_id for update;
  end if;
  if v_ligne is null then
    raise exception 'Suppression refusée : % % introuvable (déjà supprimé ?).', v_type, v_id using errcode = 'P0001';
  end if;

  -- Droit sur la fiche (D4).
  if v_role <> 'admin' then
    if v_resp is null or trim(v_resp) = '' then
      raise exception 'Suppression refusée : cette fiche n''a pas de responsable. Seul un admin peut la supprimer (ou la confier d''abord à quelqu''un).'
        using errcode = 'P0001';
    end if;
    if v_resp is distinct from v_nom then
      if exists (select 1 from public.profiles p where p.nom = v_resp and p.role in ('admin','commercial')) then
        raise exception 'Suppression refusée : cette fiche appartient à %. Seul son responsable ou un admin peut la supprimer.', v_resp
          using errcode = 'P0001';
      else
        raise exception 'Suppression refusée : cette fiche appartient à %, qui n''est plus dans le CRM. Demande à un admin de la supprimer ou de te la confier.', v_resp
          using errcode = 'P0001';
      end if;
    end if;
  end if;

  -- Garde-fous (D5). L'admin peut passer outre avec p_forcer (journalisé).
  if v_type = 'compte' then
    select count(*) into n_miss from public.missions where compte_id = v_id;
    select count(*) into n_bes  from public.besoins  where compte_id = v_id;
    select count(*) into n_cc   from public.contact_compte where compte_id = v_id and date_fin is null;
    if n_cc   > 0 then v_freins := v_freins || (n_cc   || ' contact' || case when n_cc   > 1 then 's' else '' end || ' rattaché' || case when n_cc > 1 then 's' else '' end); end if;
    if n_miss > 0 then v_freins := v_freins || (n_miss || ' mission' || case when n_miss > 1 then 's' else '' end); end if;
    if n_bes  > 0 then v_freins := v_freins || (n_bes  || ' besoin'  || case when n_bes  > 1 then 's' else '' end); end if;
    if cardinality(v_freins) > 0 and not v_forcer then
      raise exception 'Suppression refusée : ce compte a encore %. Rattache-les d''abord à un autre compte (ou clos les liens), puis réessaie.',
        case when cardinality(v_freins) = 1 then v_freins[1]
             else array_to_string(v_freins[1:cardinality(v_freins) - 1], ', ') || ' et ' || v_freins[cardinality(v_freins)] end
        using errcode = 'P0001';
    end if;
  else
    if v_statut in ('Consultant CDI','Freelance','Prestataire') and not v_forcer then
      raise exception 'Suppression refusée : % est % (effectif ou en mission). Un membre de l''effectif ne se supprime pas : passe par la sortie d''effectif.',
        coalesce(v_lib, 'ce contact'), v_statut using errcode = 'P0001';
    end if;
    select count(*) into n_miss from public.missions where contact_consultant_id = v_id or contact_referent_id = v_id;
    select count(*) into n_bes  from public.besoins  where contact_id = v_id or candidat_id = v_id or consultant_id = v_id;
    select count(*) into n_interco from public.interco_imputations where contact_consultant_id = v_id;
    select count(*) into n_partner from public.partner_consultants where contact_consultant_id = v_id;
    select count(*) into n_seq from jules.agent_sequences where contact_id = v_id and statut in ('active','paused');
    if n_miss    > 0 then v_freins := v_freins || (n_miss || ' mission' || case when n_miss > 1 then 's' else '' end); end if;
    if n_bes     > 0 then v_freins := v_freins || (n_bes  || ' besoin'  || case when n_bes  > 1 then 's' else '' end); end if;
    if n_interco > 0 then v_freins := v_freins || (n_interco || ' imputation' || case when n_interco > 1 then 's' else '' end || ' interco'); end if;
    if n_partner > 0 then v_freins := v_freins || ('un rattachement partner'::text); end if;
    if n_seq     > 0 then v_freins := v_freins || (n_seq || ' séquence' || case when n_seq > 1 then 's' else '' end || ' Jules en cours'); end if;
    if cardinality(v_freins) > 0 and not v_forcer then
      raise exception 'Suppression refusée : ce contact est encore lié à %. Détache-le d''abord (ou arrête la séquence), puis réessaie.',
        case when cardinality(v_freins) = 1 then v_freins[1]
             else array_to_string(v_freins[1:cardinality(v_freins) - 1], ', ') || ' et ' || v_freins[cardinality(v_freins)] end
        using errcode = 'P0001';
    end if;
  end if;

  -- Quota anti-masse : 20 fiches par 24 h pour un commercial.
  if v_role <> 'admin' then
    select count(*) into v_quota from public.corbeille
    where par_user = v_uid and supprime_le > now() - interval '24 hours';
    if v_quota >= 20 then
      raise exception 'Suppression refusée : tu as déjà supprimé % fiches ces dernières 24 h (limite 20). Demande à un admin pour une suppression en nombre.', v_quota
        using errcode = 'P0001';
    end if;
  end if;

  -- Photo complète AVANT toute écriture.
  if v_type = 'compte' then
    v_liens := jsonb_build_object(
      'contact_compte', (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.contact_compte x where x.compte_id = v_id));
    v_detache := coalesce((
      select jsonb_agg(d) from (
        select jsonb_build_object('table','public.missions','id',m.id::text,'colonne','compte_id','valeur',m.compte_id::text) d
          from public.missions m where m.compte_id = v_id
        union all
        select jsonb_build_object('table','public.besoins','id',b.id::text,'colonne','compte_id','valeur',b.compte_id::text)
          from public.besoins b where b.compte_id = v_id
      ) s), '[]');
  else
    v_liens := jsonb_build_object(
      'contact_compte',      (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.contact_compte x      where x.contact_id = v_id),
      'taches',              (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.taches x              where x.contact_id = v_id),
      'historique_actions',  (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.historique_actions x  where x.id_prospect = v_id),
      'besoin_candidats',    (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.besoin_candidats x    where x.contact_id = v_id),
      'session_prospection_contacts', (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.session_prospection_contacts x where x.contact_id = v_id),
      'interco_imputations', (select coalesce(jsonb_agg(to_jsonb(x.*) order by x.id), '[]') from public.interco_imputations x where x.contact_consultant_id = v_id),
      'partner_consultants', (select coalesce(jsonb_agg(to_jsonb(x.*)), '[]') from public.partner_consultants x where x.contact_consultant_id = v_id));
    v_detache := coalesce((
      select jsonb_agg(d) from (
        -- séquences Jules (terminées ; actives seulement si forcé) : contact_id remis à NULL
        select jsonb_build_object('table','jules.agent_sequences','id',s.id::text,'colonne','contact_id','valeur',s.contact_id::text) d
          from jules.agent_sequences s where s.contact_id = v_id
        -- actions d'AUTRES contacts qui pointent sur une tâche de ce contact (tache_id SET NULL)
        union all
        select jsonb_build_object('table','public.historique_actions','id',h.id::text,'colonne','tache_id','valeur',h.tache_id)
          from public.historique_actions h
          where h.tache_id in (select t.id from public.taches t where t.contact_id = v_id)
            and h.id_prospect is distinct from v_id
        -- forcé uniquement (sinon refusé plus haut) : besoins et missions qui le citent
        union all
        select jsonb_build_object('table','public.besoins','id',b.id::text,'colonne',c.col,'valeur',v_id::text)
          from public.besoins b
          cross join lateral (values ('contact_id', b.contact_id), ('candidat_id', b.candidat_id), ('consultant_id', b.consultant_id)) c(col, val)
          where c.val = v_id
        union all
        select jsonb_build_object('table','public.missions','id',m.id::text,'colonne',c.col,'valeur',v_id::text)
          from public.missions m
          cross join lateral (values ('contact_consultant_id', m.contact_consultant_id), ('contact_referent_id', m.contact_referent_id)) c(col, val)
          where c.val = v_id
      ) s), '[]');
  end if;
  v_liens := v_liens || jsonb_build_object('detaches', v_detache);

  for v_k in select jsonb_object_keys(v_liens) loop
    v_nb := v_nb + jsonb_array_length(v_liens -> v_k);
  end loop;

  insert into public.corbeille (objet_type, objet_id, libelle, responsable_fiche, ligne, liens, motif, origine, forcee,
                                par_nom, par_user, par_role)
  values (v_type, v_id::text, v_lib, v_resp, v_ligne, v_liens, v_motif, v_origine, v_forcer, v_nom, v_uid, v_role)
  returning id into v_arch_id;

  -- Suppression (une transaction : tout part ou rien).
  if v_type = 'compte' then
    if v_forcer then
      update public.missions set compte_id = null where compte_id = v_id;
      update public.besoins  set compte_id = null where compte_id = v_id;
    end if;
    delete from public.comptes where id = v_id;            -- contact_compte : CASCADE (archivés ci-dessus)
  else
    if v_forcer then
      update public.besoins  set contact_id = null where contact_id = v_id;
      update public.besoins  set candidat_id = null where candidat_id = v_id;
      update public.besoins  set consultant_id = null where consultant_id = v_id;
      update public.missions set contact_consultant_id = null where contact_consultant_id = v_id;
      update public.missions set contact_referent_id = null where contact_referent_id = v_id;
    end if;
    delete from public.taches where contact_id = v_id;     -- pas de FK : à la main
    delete from public.session_prospection_contacts where contact_id = v_id;   -- FK bloquante
    update jules.agent_sequences set contact_id = null where contact_id = v_id;
    delete from public.contacts where id = v_id;           -- historique, liens, candidatures, interco, partner : CASCADE
  end if;
  if not found then
    raise exception 'Suppression non faite : la fiche % % n''a pas pu être supprimée.', v_type, v_id using errcode = 'P0001';
  end if;

  insert into public.corbeille_journal (evenement, corbeille_id, objet_type, objet_id, libelle, par_nom, par_user, origine, forcee, nb_lignes)
  values (case when v_role = 'admin' then 'suppression_admin' else 'suppression' end,
          v_arch_id, v_type, v_id::text, v_lib, v_nom, v_uid, v_origine, v_forcer, 1 + v_nb);

  return jsonb_build_object('type', v_type, 'id', v_id, 'libelle', v_lib, 'archive_id', v_arch_id,
                            'nb_enfants', v_nb, 'forcee', v_forcer, 'par', v_nom);
end;
$$;
comment on function public.supprimer_fiche(text, text, text, text, boolean) is
  'db/60 : seule porte de suppression d''un compte ou d''un contact. Responsable (commercial) ou admin ; '
  'garde-fous (compte vide, contact hors effectif/mission/besoin/séquence), quota 20/24 h, archive dans corbeille.';
revoke all on function public.supprimer_fiche(text, text, text, text, boolean) from public, anon;
grant execute on function public.supprimer_fiche(text, text, text, text, boolean) to authenticated, service_role;


-- ─── 5. restaurer_fiche (admin) ───
create or replace function public.restaurer_fiche(p_corbeille_id bigint, p_origine text default 'app')
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_origine text := lower(trim(coalesce(p_origine, 'app')));
  v_uid uuid; v_nom text; v_role text;
  r public.corbeille%rowtype;
  v_table regclass;
  v_cle text; v_ordre text[];
  v_l jsonb; v_d jsonb;
  n_ok int := 0;
  v_ignores jsonb := '[]'::jsonb;
  v_n int;
begin
  select a.o_uid, a.o_nom, a.o_role into v_uid, v_nom, v_role from public._corbeille_appelant(v_origine) a;
  if v_role <> 'admin' then
    raise exception 'Restauration refusée : réservée à un admin.' using errcode = 'P0001';
  end if;

  select * into r from public.corbeille where id = p_corbeille_id for update;
  if not found then
    raise exception 'Restauration refusée : archive % introuvable (purgée ?).', p_corbeille_id using errcode = 'P0001';
  end if;
  if r.restaure_le is not null then
    raise exception 'Restauration refusée : cette fiche a déjà été remise en place le % par %.',
      to_char(r.restaure_le at time zone 'Europe/Paris', 'DD/MM/YYYY HH24:MI'), r.restaure_par using errcode = 'P0001';
  end if;

  if r.objet_type = 'compte' then
    v_table := 'public.comptes'::regclass;
    v_ordre := array['contact_compte'];
  elsif r.objet_type = 'contact' then
    v_table := 'public.contacts'::regclass;
    -- taches avant historique (historique_actions.tache_id → taches)
    v_ordre := array['contact_compte','taches','historique_actions','besoin_candidats','session_prospection_contacts',
                     'interco_imputations','partner_consultants'];
  else
    raise exception 'Restauration refusée : type % pas encore pris en charge.', r.objet_type using errcode = 'P0001';
  end if;

  execute format('select count(*) from %s where id = $1', v_table) into v_n using (r.objet_id)::bigint;
  if v_n > 0 then
    raise exception 'Restauration refusée : l''identifiant % est de nouveau utilisé par une autre fiche.', r.objet_id using errcode = 'P0001';
  end if;
  if not public._corbeille_reinserer(v_table, r.ligne) then
    raise exception 'Restauration refusée : la fiche % % ne peut pas être réinsérée (contrainte).', r.objet_type, r.objet_id using errcode = 'P0001';
  end if;

  foreach v_cle in array v_ordre loop
    for v_l in select jsonb_array_elements(coalesce(r.liens -> v_cle, '[]'::jsonb)) loop
      if public._corbeille_reinserer(('public.' || v_cle)::regclass, v_l) then
        n_ok := n_ok + 1;
      else
        v_ignores := v_ignores || jsonb_build_object('table', v_cle, 'id', coalesce(v_l ->> 'id', v_l ->> 'partner_id'),
                                                     'raison', 'parent disparu, id repris ou contrainte');
      end if;
    end loop;
  end loop;

  -- Références détachées : remises seulement si elles sont toujours vides.
  for v_d in select jsonb_array_elements(coalesce(r.liens -> 'detaches', '[]'::jsonb)) loop
    begin
      execute format('update %s set %I = $1::%s where id::text = $2 and %I is null',
                     v_d ->> 'table', v_d ->> 'colonne',
                     (select format_type(a.atttypid, a.atttypmod) from pg_attribute a
                       where a.attrelid = (v_d ->> 'table')::regclass and a.attname = v_d ->> 'colonne'),
                     v_d ->> 'colonne')
        using v_d ->> 'valeur', v_d ->> 'id';
      get diagnostics v_n = row_count;
      if v_n = 1 then n_ok := n_ok + 1;
      else v_ignores := v_ignores || jsonb_build_object('table', v_d ->> 'table', 'id', v_d ->> 'id', 'raison', 'ligne absente ou déjà rattachée ailleurs');
      end if;
    exception when others then
      v_ignores := v_ignores || jsonb_build_object('table', v_d ->> 'table', 'id', v_d ->> 'id', 'raison', sqlerrm);
    end;
  end loop;

  -- Le trigger d'historique a pu toucher date_dernier : on remet la valeur archivée.
  if r.objet_type = 'contact' then
    update public.contacts set date_dernier = (r.ligne ->> 'date_dernier')::timestamptz,
                               updated_at   = (r.ligne ->> 'updated_at')::timestamptz
    where id = (r.objet_id)::bigint;
  end if;

  update public.corbeille set restaure_le = now(), restaure_par = v_nom where id = r.id;
  insert into public.corbeille_journal (evenement, corbeille_id, objet_type, objet_id, libelle, par_nom, par_user, origine, nb_lignes)
  values ('restauration', r.id, r.objet_type, r.objet_id, r.libelle, v_nom, v_uid, v_origine, 1 + n_ok);

  return jsonb_build_object('type', r.objet_type, 'id', r.objet_id, 'libelle', r.libelle,
                            'lignes_remises', 1 + n_ok, 'ignorees', v_ignores);
end;
$$;
comment on function public.restaurer_fiche(bigint, text) is
  'db/60 : remet en place une fiche de la corbeille (même id), ses enfants et ses références détachées. Admin seul.';
revoke all on function public.restaurer_fiche(bigint, text) from public, anon;
grant execute on function public.restaurer_fiche(bigint, text) to authenticated, service_role;


-- ─── 6. purger_corbeille (admin, manuelle) ───
create or replace function public.purger_corbeille(
  p_corbeille_id bigint      default null,
  p_avant        timestamptz default null,
  p_origine      text        default 'app'
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_origine text := lower(trim(coalesce(p_origine, 'app')));
  v_uid uuid; v_nom text; v_role text;
  v_n int := 0;
  r record;
begin
  select a.o_uid, a.o_nom, a.o_role into v_uid, v_nom, v_role from public._corbeille_appelant(v_origine) a;
  if v_role <> 'admin' then
    raise exception 'Purge refusée : réservée à un admin.' using errcode = 'P0001';
  end if;
  if (p_corbeille_id is null) = (p_avant is null) then
    raise exception 'Purge refusée : donner SOIT une archive (p_corbeille_id), SOIT une date (p_avant).' using errcode = 'P0001';
  end if;

  for r in
    delete from public.corbeille
    where (p_corbeille_id is not null and id = p_corbeille_id)
       or (p_avant is not null and supprime_le < p_avant)
    returning id, objet_type, objet_id, libelle
  loop
    insert into public.corbeille_journal (evenement, corbeille_id, objet_type, objet_id, libelle, par_nom, par_user, origine, nb_lignes)
    values ('purge', r.id, r.objet_type, r.objet_id, r.libelle, v_nom, v_uid, v_origine, 1);
    v_n := v_n + 1;
  end loop;

  if p_corbeille_id is not null and v_n = 0 then
    raise exception 'Purge refusée : archive % introuvable.', p_corbeille_id using errcode = 'P0001';
  end if;
  return jsonb_build_object('purgees', v_n, 'par', v_nom);
end;
$$;
comment on function public.purger_corbeille(bigint, timestamptz, text) is
  'db/60 : vide définitivement une archive de la corbeille (ou toutes celles d''avant une date). Admin seul, journalisé.';
revoke all on function public.purger_corbeille(bigint, timestamptz, text) from public, anon;
grant execute on function public.purger_corbeille(bigint, timestamptz, text) to authenticated, service_role;


-- ─── 7. purger_corbeille_auto (D2 : 12 mois) ───
-- Pas de planification créée ici. À brancher sur le tick du Mac mini (~/bin/taches.txt), par exemple :
--   03:40 tous /opt/homebrew/bin/docker exec supabase-db psql -U supabase_admin -d postgres -tAc "select public.purger_corbeille_auto()"
create or replace function public.purger_corbeille_auto()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_n int := 0;
  r record;
begin
  if auth.uid() is not null
     or not (jules.est_service_jwt() or session_user in ('postgres','supabase_admin')) then
    raise exception 'Purge automatique refusée : réservée à la clé service et au tick du Mac mini.' using errcode = 'P0001';
  end if;
  for r in
    delete from public.corbeille where supprime_le < now() - interval '12 months'
    returning id, objet_type, objet_id, libelle
  loop
    insert into public.corbeille_journal (evenement, corbeille_id, objet_type, objet_id, libelle, par_nom, origine, nb_lignes)
    values ('purge_auto', r.id, r.objet_type, r.objet_id, r.libelle, 'Purge automatique (12 mois)', 'builder', 1);
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.purger_corbeille_auto() is
  'db/60 : purge les archives de plus de 12 mois (décision D2). Clé service ou superuser (tick du Mac mini).';
revoke all on function public.purger_corbeille_auto() from public, anon, authenticated;
grant execute on function public.purger_corbeille_auto() to service_role;


-- ─── 8. Fermeture du DELETE direct ───
-- 8a. Contacts : la politique passe à « admin seul » (comme comptes et contact_compte).
drop policy if exists delete_contacts on public.contacts;
create policy delete_contacts on public.contacts
  for delete to authenticated using (get_my_role() = 'admin');

-- 8b. Garde au niveau de l'instruction : se déclenche même quand la RLS filtre toutes les lignes,
-- pour qu'un vieux client reçoive une ERREUR claire au lieu d'un faux succès.
create or replace function public._garde_suppression_directe()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  -- current_user = le rôle qui exécute le DELETE. Dans supprimer_fiche (SECURITY DEFINER) c'est le propriétaire,
  -- pour Jules c'est service_role, pour crm-sql.sh / Studio / scripts de fusion c'est supabase_admin ou postgres.
  if current_user in ('authenticated','anon') and coalesce(public.get_my_role(), '') <> 'admin' then
    raise exception 'Suppression directe fermée sur les % : utilise le bouton Supprimer de l''appli (recharge la page) ou mets à jour le connecteur Claude. Seul le responsable de la fiche peut la supprimer, elle est gardée en archive.',
      tg_table_name using errcode = '42501';
  end if;
  return null;
end;
$$;
revoke all on function public._garde_suppression_directe() from public, anon, authenticated, service_role;

drop trigger if exists trg_garde_suppression_directe on public.contacts;
create trigger trg_garde_suppression_directe before delete on public.contacts
  for each statement execute function public._garde_suppression_directe();
drop trigger if exists trg_garde_suppression_directe on public.comptes;
create trigger trg_garde_suppression_directe before delete on public.comptes
  for each statement execute function public._garde_suppression_directe();


-- ─── 9. Tests intégrés (chaque cas est annulé ; un échec annule TOUTE la migration) ───
-- Les fiches de test sont créées à la volée (préfixe ZZTEST60) puis annulées : rien ne reste en base.
do $$
declare
  a_id uuid; a_nom text; b_id uuid; b_nom text; adm_id uuid; adm_nom text; pa_id uuid;
  j_a text; j_b text; j_adm text; j_pa text;
  k1 bigint; c1 bigint; m1 int; s1 uuid; am uuid; t1 text;
  res jsonb; v text; n int; n2 int;
  n_corb int; n_jour int;
begin
  select p.id, p.nom into a_id, a_nom from public.profiles p where p.role = 'commercial' order by p.nom limit 1;
  select p.id, p.nom into b_id, b_nom from public.profiles p where p.role = 'commercial' and p.nom <> a_nom order by p.nom limit 1;
  select p.id, p.nom into adm_id, adm_nom from public.profiles p where p.role = 'admin' order by p.nom limit 1;
  select p.id into pa_id from public.profiles p where p.role = 'partner' order by p.nom limit 1;
  if a_id is null or b_id is null or adm_id is null then
    raise exception 'Tests impossibles : il faut 2 commerciaux et 1 admin dans profiles.';
  end if;
  j_a   := json_build_object('sub', a_id,   'role', 'authenticated')::text;
  j_b   := json_build_object('sub', b_id,   'role', 'authenticated')::text;
  j_adm := json_build_object('sub', adm_id, 'role', 'authenticated')::text;
  j_pa  := json_build_object('sub', pa_id,  'role', 'authenticated')::text;
  select count(*) into n_corb from public.corbeille;
  select count(*) into n_jour from public.corbeille_journal;
  raise notice 'Tests avec A = %, B = %, admin = %', a_nom, b_nom, adm_nom;

  -- T1 : A supprime SON compte vide (avec un lien contact clos) → archivé, liens clos archivés, journal « suppression ».
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 compte A', a_nom) returning id into k1;
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST60 lien clos', b_nom, 'Prospect') returning id into c1;
    insert into public.contact_compte (contact_id, compte_id, date_debut, date_fin, is_primary) values (c1, k1, current_date - 30, current_date - 1, false);
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    res := public.supprimer_fiche('compte', k1::text, 'doublon de test', 'app');
    reset role;
    if exists (select 1 from public.comptes where id = k1) then raise exception 'KO T1 : compte toujours là'; end if;
    if not exists (select 1 from public.contacts where id = c1) then raise exception 'KO T1 : le contact lié a disparu'; end if;
    select count(*) into n from public.corbeille
      where id = (res ->> 'archive_id')::bigint and objet_type = 'compte' and par_nom = a_nom and par_role = 'commercial'
        and jsonb_array_length(liens -> 'contact_compte') = 1 and motif = 'doublon de test';
    if n <> 1 then raise exception 'KO T1 : archive incomplète (%)', res; end if;
    select count(*) into n from public.corbeille_journal where corbeille_id = (res ->> 'archive_id')::bigint and evenement = 'suppression';
    if n <> 1 then raise exception 'KO T1 : journal (% ligne)', n; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T1 : le responsable supprime son compte vide, archivé avec ses liens clos';
  end;

  -- T2 : A tente de supprimer le compte de B → refusé.
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 compte B', b_nom) returning id into k1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('compte', k1::text, null, 'app');
    raise exception 'KO T2 : suppression du compte d''un collègue acceptée';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like 'Suppression refusée : cette fiche appartient à%' then raise exception 'KO T2 : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T2 : compte d''un collègue refusé';
  end;

  -- T3 : compte avec un contact actif, une mission et un besoin → refusé, message qui dit quoi faire.
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 compte plein', a_nom) returning id into k1;
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST60 actif', a_nom, 'Prospect') returning id into c1;
    insert into public.contact_compte (contact_id, compte_id, is_primary) values (c1, k1, true);
    insert into public.missions (consultant, compte_id, responsable) values ('ZZTEST60', k1, a_nom);
    insert into public.besoins (agence, statut, titre, responsable, compte_id) values ('Lyon', 'Opportunité', 'ZZTEST60', a_nom, k1);
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('compte', k1::text, null, 'app');
    raise exception 'KO T3 : compte non vide supprimé';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like 'Suppression refusée : ce compte a encore 1 contact rattaché, 1 mission et 1 besoin.%' then
      raise exception 'KO T3 : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T3 : compte avec contact/mission/besoin refusé (%)', sqlerrm;
  end;

  -- T4 : compte sans responsable → refusé au commercial (D4), accepté pour l'admin (archivé, D1).
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 orphelin', null) returning id into k1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    begin
      perform public.supprimer_fiche('compte', k1::text, null, 'app');
      raise exception 'KO T4 : compte sans responsable supprimé par un commercial';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Suppression refusée : cette fiche n''a pas de responsable%' then raise exception 'KO T4 : mauvais refus (%)', sqlerrm; end if;
    end;
    perform set_config('request.jwt.claims', j_adm, true);
    res := public.supprimer_fiche('compte', k1::text, null, 'app');
    reset role;
    if exists (select 1 from public.comptes where id = k1) then raise exception 'KO T4 : l''admin n''a pas supprimé'; end if;
    select count(*) into n from public.corbeille where id = (res ->> 'archive_id')::bigint and par_role = 'admin';
    if n <> 1 then raise exception 'KO T4 : suppression admin non archivée'; end if;
    select count(*) into n from public.corbeille_journal where corbeille_id = (res ->> 'archive_id')::bigint and evenement = 'suppression_admin';
    if n <> 1 then raise exception 'KO T4 : journal suppression_admin absent'; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T4 : sans responsable → admin seulement ; suppression admin archivée + journal';
  end;

  -- T5 : fiche d'un membre parti → refusée au commercial, message « demande à un admin ».
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST60 parti', 'Membre Parti ZZ', 'Prospect') returning id into c1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('contact', c1::text, null, 'app');
    raise exception 'KO T5 : fiche d''un membre parti supprimée';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like '%qui n''est plus dans le CRM. Demande à un admin%' then raise exception 'KO T5 : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T5 : fiche d''un membre parti refusée';
  end;

  -- T6 : A supprime SON contact avec historique, tâche, lien compte, séquence terminée → tout archivé, séquence détachée.
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 compte C', b_nom) returning id into k1;
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST60 contact A', a_nom, 'Prospect') returning id into c1;
    insert into public.contact_compte (contact_id, compte_id, is_primary) values (c1, k1, true);
    t1 := 'zztest60-' || c1;
    insert into public.taches (id, titre, contact_id, responsable) values (t1, 'ZZTEST60 relance', c1, a_nom);
    insert into public.historique_actions (id_prospect, date, type_action, details, responsable, tache_id)
      values (c1, current_date - 3, 'Appel', 'ZZTEST60 a', a_nom, t1), (c1, current_date - 2, 'Mail', 'ZZTEST60 b', a_nom, null);
    set local session_replication_role = replica;   -- séquence factice, sans les déclencheurs de Jules
    insert into jules.agent_missions (owner_id, titre) values (a_id, 'ZZTEST60') returning id into am;
    insert into jules.agent_sequences (owner_id, target_kind, target_ref, target_label, mission_id, statut, contact_id)
      values (a_id, 'contact_crm', c1::text, 'ZZTEST60', am, 'stopped', c1) returning id into s1;
    set local session_replication_role = origin;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    res := public.supprimer_fiche('contact', c1::text, null, 'app');
    reset role;
    if exists (select 1 from public.contacts where id = c1) then raise exception 'KO T6 : contact toujours là'; end if;
    if exists (select 1 from public.historique_actions where id_prospect = c1) then raise exception 'KO T6 : historique resté'; end if;
    if exists (select 1 from public.taches where id = t1) then raise exception 'KO T6 : tâche restée'; end if;
    select contact_id::text into v from jules.agent_sequences where id = s1;
    if v is not null then raise exception 'KO T6 : séquence non détachée'; end if;
    select jsonb_array_length(liens -> 'historique_actions'), jsonb_array_length(liens -> 'taches') + jsonb_array_length(liens -> 'contact_compte')
      into n, n2 from public.corbeille where id = (res ->> 'archive_id')::bigint;
    if n <> 2 or n2 <> 2 then raise exception 'KO T6 : archive incomplète (historique %, tâche+lien %)', n, n2; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T6 : contact supprimé, historique/tâche/lien archivés, séquence terminée détachée';
  end;

  -- T7 : contact consultant, ou sous séquence active → refusé.
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST60 cdi', a_nom, 'Consultant CDI') returning id into c1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('contact', c1::text, null, 'app');
    raise exception 'KO T7a : consultant supprimé';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like '%Un membre de l''effectif ne se supprime pas%' then raise exception 'KO T7a : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T7a : consultant refusé';
  end;
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST60 seq', a_nom, 'Prospect') returning id into c1;
    set local session_replication_role = replica;
    insert into jules.agent_missions (owner_id, titre) values (a_id, 'ZZTEST60') returning id into am;
    insert into jules.agent_sequences (owner_id, target_kind, target_ref, target_label, mission_id, statut, contact_id)
      values (a_id, 'contact_crm', c1::text, 'ZZTEST60', am, 'active', c1);
    set local session_replication_role = origin;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('contact', c1::text, null, 'app');
    raise exception 'KO T7b : contact en séquence active supprimé';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like '%1 séquence Jules en cours%' then raise exception 'KO T7b : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T7b : contact en séquence active refusé';
  end;

  -- T8 : DELETE direct d'un commercial sur contacts et sur comptes → ERREUR explicite (plus de faux succès).
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST60 direct', a_nom, 'Prospect') returning id into c1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    delete from public.contacts where id = c1;
    raise exception 'KO T8a : DELETE direct accepté sans erreur';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like 'Suppression directe fermée sur les contacts%' then raise exception 'KO T8a : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T8a : DELETE direct contacts → erreur claire';
  end;
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 direct', a_nom) returning id into k1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    delete from public.comptes where id = k1;
    raise exception 'KO T8b : DELETE direct accepté sans erreur';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like 'Suppression directe fermée sur les comptes%' then raise exception 'KO T8b : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T8b : DELETE direct comptes → erreur claire';
  end;
  -- T8c : le rôle propriétaire (postgres / supabase_admin, scripts de fusion) supprime toujours en direct.
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 fusion', a_nom) returning id into k1;
    perform set_config('request.jwt.claims', '', true);
    delete from public.comptes where id = k1;
    if exists (select 1 from public.comptes where id = k1) then raise exception 'KO T8c : le superuser ne supprime plus'; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T8c : suppression directe par le propriétaire (scripts de fusion) toujours possible';
  end;

  -- T9 : quota — 21e suppression en 24 h refusée.
  begin
    insert into public.corbeille (objet_type, objet_id, ligne, origine, par_nom, par_user, par_role)
      select 'contact', 'zz' || g, '{}'::jsonb, 'app', a_nom, a_id, 'commercial' from generate_series(1, 20) g;
    insert into public.comptes (nom, responsable) values ('ZZTEST60 quota', a_nom) returning id into k1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('compte', k1::text, null, 'app');
    raise exception 'KO T9 : quota dépassé accepté';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like '%(limite 20)%' then raise exception 'KO T9 : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T9 : 21e suppression en 24 h refusée';
  end;

  -- T10 : partner refusé ; sans session refusé ; clé service sans origine jules/builder refusée, avec origine acceptée.
  if pa_id is not null then
    begin
      insert into public.comptes (nom, responsable) values ('ZZTEST60 partner', a_nom) returning id into k1;
      perform set_config('request.jwt.claims', j_pa, true);
      set local role authenticated;
      perform public.supprimer_fiche('compte', k1::text, null, 'app');
      raise exception 'KO T10a : partner accepté';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Suppression refusée : réservée aux commerciaux%' then raise exception 'KO T10a : mauvais refus (%)', sqlerrm; end if;
      raise notice 'OK T10a : partner refusé';
    end;
  end if;
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 anon', a_nom) returning id into k1;
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    set local role authenticated;
    perform public.supprimer_fiche('compte', k1::text, null, 'app');
    raise exception 'KO T10b : sans session accepté';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like 'Refusé : aucune session%' then raise exception 'KO T10b : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T10b : sans session refusé';
  end;
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 service', a_nom) returning id into k1;
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    set local role service_role;
    begin
      perform public.supprimer_fiche('compte', k1::text, null, 'app');
      raise exception 'KO T10c : clé service origine app acceptée';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Refusé : avec la clé service%' then raise exception 'KO T10c : mauvais refus (%)', sqlerrm; end if;
    end;
    res := public.supprimer_fiche('compte', k1::text, 'test', 'jules');
    reset role;
    if (res ->> 'par') <> 'Jules (clé service)' then raise exception 'KO T10c : par = %', res ->> 'par'; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T10c : clé service seulement avec origine jules/builder';
  end;

  -- T11 : restauration — A supprime son contact, un commercial ne peut pas restaurer, l'admin restaure tout (même id).
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 compte R', b_nom) returning id into k1;
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST60 restau', a_nom, 'Prospect') returning id into c1;
    insert into public.contact_compte (contact_id, compte_id, is_primary) values (c1, k1, true);
    t1 := 'zztest60r-' || c1;
    insert into public.taches (id, titre, contact_id, responsable) values (t1, 'ZZTEST60', c1, a_nom);
    insert into public.historique_actions (id_prospect, date, type_action, details, responsable, tache_id)
      values (c1, current_date - 5, 'Appel', 'ZZTEST60 r1', a_nom, t1), (c1, current_date - 4, 'Mail', 'ZZTEST60 r2', a_nom, null);
    set local session_replication_role = replica;
    insert into jules.agent_missions (owner_id, titre) values (a_id, 'ZZTEST60') returning id into am;
    insert into jules.agent_sequences (owner_id, target_kind, target_ref, target_label, mission_id, statut, contact_id)
      values (a_id, 'contact_crm', c1::text, 'ZZTEST60', am, 'replied', c1) returning id into s1;
    set local session_replication_role = origin;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    res := public.supprimer_fiche('contact', c1::text, null, 'app');
    begin
      perform public.restaurer_fiche((res ->> 'archive_id')::bigint, 'app');
      raise exception 'KO T11 : restauration par un commercial acceptée';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Restauration refusée : réservée à un admin%' then raise exception 'KO T11 : mauvais refus (%)', sqlerrm; end if;
    end;
    perform set_config('request.jwt.claims', j_adm, true);
    res := public.restaurer_fiche((res ->> 'archive_id')::bigint, 'app');
    reset role;
    if not exists (select 1 from public.contacts where id = c1 and nom = 'TEST60 restau' and responsable = a_nom) then raise exception 'KO T11 : contact non restauré'; end if;
    select count(*) into n from public.historique_actions where id_prospect = c1;
    if n <> 2 then raise exception 'KO T11 : historique restauré % / 2', n; end if;
    if not exists (select 1 from public.historique_actions where id_prospect = c1 and tache_id = t1) then raise exception 'KO T11 : lien action→tâche perdu'; end if;
    if not exists (select 1 from public.contact_compte where contact_id = c1 and compte_id = k1) then raise exception 'KO T11 : lien compte non restauré'; end if;
    if not exists (select 1 from public.taches where id = t1) then raise exception 'KO T11 : tâche non restaurée'; end if;
    if not exists (select 1 from jules.agent_sequences where id = s1 and contact_id = c1) then raise exception 'KO T11 : séquence non raccrochée'; end if;
    if jsonb_array_length(res -> 'ignorees') <> 0 then raise exception 'KO T11 : lignes ignorées %', res -> 'ignorees'; end if;
    select count(*) into n from public.corbeille_journal where objet_type = 'contact' and objet_id = c1::text and evenement = 'restauration';
    if n <> 1 then raise exception 'KO T11 : journal restauration absent'; end if;
    -- deuxième restauration refusée
    begin
      perform set_config('request.jwt.claims', j_adm, true);
      perform public.restaurer_fiche((select max(id) from public.corbeille where objet_id = c1::text), 'app');
      raise exception 'KO T11 : double restauration acceptée';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Restauration refusée : cette fiche a déjà été remise en place%' then raise exception 'KO T11 : mauvais refus (%)', sqlerrm; end if;
    end;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T11 : restauration admin complète (même id, historique, lien, tâche, séquence), commercial refusé';
  end;

  -- T12 : admin force la suppression d'un compte avec mission → mission détachée et archivée, la restauration la raccroche.
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST60 force', a_nom) returning id into k1;
    insert into public.missions (consultant, compte_id, responsable) values ('ZZTEST60', k1, a_nom) returning id into m1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    begin
      perform public.supprimer_fiche('compte', k1::text, null, 'app', true);
      raise exception 'KO T12 : commercial a forcé';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Suppression refusée : seul un admin peut forcer%' then raise exception 'KO T12 : mauvais refus (%)', sqlerrm; end if;
    end;
    perform set_config('request.jwt.claims', j_adm, true);
    res := public.supprimer_fiche('compte', k1::text, 'test forcé', 'app', true);
    reset role;
    if (select compte_id from public.missions where id = m1) is not null then raise exception 'KO T12 : mission non détachée'; end if;
    set local role authenticated;
    res := public.restaurer_fiche((res ->> 'archive_id')::bigint, 'app');
    reset role;
    if (select compte_id from public.missions where id = m1) is distinct from k1 then raise exception 'KO T12 : mission non raccrochée (%)', res; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T12 : forçage admin seul, mission détachée puis raccrochée à la restauration';
  end;

  -- T13 : purge — commercial refusé ; admin purge une archive ; purge auto ne touche que les plus de 12 mois.
  begin
    insert into public.corbeille (objet_type, objet_id, libelle, ligne, origine, par_nom, par_user, par_role, supprime_le)
      values ('compte', 'zz-vieux', 'ZZTEST60 vieux', '{}'::jsonb, 'app', a_nom, a_id, 'commercial', now() - interval '13 months'),
             ('compte', 'zz-recent', 'ZZTEST60 récent', '{}'::jsonb, 'app', a_nom, a_id, 'commercial', now() - interval '11 months'),
             ('compte', 'zz-manuel', 'ZZTEST60 manuel', '{}'::jsonb, 'app', a_nom, a_id, 'commercial', now());
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    begin
      perform public.purger_corbeille((select id from public.corbeille where objet_id = 'zz-manuel'), null, 'app');
      raise exception 'KO T13 : purge par un commercial acceptée';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Purge refusée : réservée à un admin%' then raise exception 'KO T13 : mauvais refus (%)', sqlerrm; end if;
    end;
    begin
      perform public.purger_corbeille_auto();
      raise exception 'KO T13 : purge auto par un commercial acceptée';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
    end;
    perform set_config('request.jwt.claims', j_adm, true);
    res := public.purger_corbeille((select id from public.corbeille where objet_id = 'zz-manuel'), null, 'app');
    reset role;
    if (res ->> 'purgees')::int <> 1 or exists (select 1 from public.corbeille where objet_id = 'zz-manuel') then raise exception 'KO T13 : purge manuelle %', res; end if;
    if not exists (select 1 from public.corbeille_journal where objet_id = 'zz-manuel' and evenement = 'purge') then raise exception 'KO T13 : journal purge absent'; end if;
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    set local role service_role;
    n := public.purger_corbeille_auto();
    reset role;
    if exists (select 1 from public.corbeille where objet_id = 'zz-vieux') then raise exception 'KO T13 : archive de 13 mois non purgée'; end if;
    if not exists (select 1 from public.corbeille where objet_id = 'zz-recent') then raise exception 'KO T13 : archive de 11 mois purgée à tort'; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T13 : purge manuelle admin seul, purge auto à 12 mois';
  end;

  -- T14 : la corbeille n'est ni lisible ni écrivable par un commercial ; lisible par l'admin.
  begin
    insert into public.corbeille (objet_type, objet_id, ligne, origine, par_nom, par_role) values ('compte', 'zz-lect', '{}'::jsonb, 'app', 'x', 'admin');
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    select count(*) into n from public.corbeille where objet_id = 'zz-lect';
    if n <> 0 then raise exception 'KO T14 : corbeille lisible par un commercial'; end if;
    begin
      insert into public.corbeille (objet_type, objet_id, ligne, origine, par_nom, par_role) values ('compte', 'zz', '{}'::jsonb, 'app', 'x', 'x');
      raise exception 'KO T14 : insertion directe acceptée';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
    end;
    perform set_config('request.jwt.claims', j_adm, true);
    select count(*) into n from public.corbeille where objet_id = 'zz-lect';
    if n <> 1 then raise exception 'KO T14 : corbeille illisible par l''admin'; end if;
    reset role;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T14 : corbeille lisible par l''admin seul, aucune écriture directe';
  end;

  -- Rien ne doit rester des tests.
  if (select count(*) from public.corbeille) <> n_corb or (select count(*) from public.corbeille_journal) <> n_jour then
    raise exception 'KO : des lignes de test sont restées dans la corbeille ou le journal';
  end if;
  if exists (select 1 from public.comptes where nom like 'ZZTEST60%') or exists (select 1 from public.contacts where nom like 'TEST60%') then
    raise exception 'KO : des fiches de test sont restées';
  end if;
  perform set_config('request.jwt.claims', '', true);
end $$;

-- PostgREST doit voir les nouvelles fonctions (crm-sql.sh le relance aussi).
notify pgrst, 'reload schema';

commit;
