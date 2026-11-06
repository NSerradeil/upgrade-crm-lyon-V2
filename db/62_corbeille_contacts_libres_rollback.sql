-- ══════════════════════════════════════════════════════════════════════
-- 62 — Corbeille contacts libres — ROLLBACK (remet supprimer_fiche et _garde_suppression_directe de db/60)
--   zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/62_corbeille_contacts_libres_rollback.sql
-- Les contacts supprimés entre-temps restent en corbeille, restaurables par un admin (restaurer_fiche).
-- ══════════════════════════════════════════════════════════════════════

begin;

-- 1. supprimer_fiche telle que db/60 (copie exacte, md5 du corps e015b770fef173f55edff5bd45198ec5).
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

-- 2. _garde_suppression_directe telle que db/60 (md5 84b7cab4a528386012e736df435559db).
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

-- 3. Contrôle : on est bien revenu à db/60.
do $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.supprimer_fiche(text,text,text,text,boolean)'::regprocedure)
     <> 'e015b770fef173f55edff5bd45198ec5' then
    raise exception 'KO rollback : supprimer_fiche différente de db/60';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public._garde_suppression_directe()'::regprocedure)
     <> '84b7cab4a528386012e736df435559db' then
    raise exception 'KO rollback : _garde_suppression_directe différente de db/60';
  end if;
  raise notice 'OK rollback db/62 : supprimer_fiche et garde de db/60 rétablies';
end $$;

notify pgrst, 'reload schema';

commit;
