-- ══════════════════════════════════════════════════════════════════════
-- 62 — Corbeille : tout commercial peut mettre un CONTACT en corbeille (06/11/2026, décision Nicolas)
-- BLOC 2/3 — APPLY (transactionnel, auto-testé, tout ou rien)
--
-- CE QUI CHANGE :
--   1. supprimer_fiche (db/60) : pour un CONTACT, le contrôle « responsable ou admin » est retiré : tout commercial
--      (admin ou commercial) peut le supprimer, quel que soit son référent. Tout le reste est identique à db/60 :
--      garde-fous contact (effectif, mission, besoin, interco, partner, séquence Jules active), quota 20 / 24 h,
--      archive complète en corbeille, journal. COMPTES : règle inchangée (responsable ou admin, D4).
--   2. _garde_suppression_directe : seul le message change (il ne dit plus « seul le responsable »).
--
-- CE QUI NE BOUGE PAS : la policy delete_contacts reste « admin seul » (le DELETE direct reste fermé : tout passe
-- par supprimer_fiche et la corbeille). Aucune suppression définitive. Corbeille et restauration inchangées.
--
-- Lancer sur le Mac mini : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/62_corbeille_contacts_libres_2_apply.sql
-- Retour arrière : db/62_corbeille_contacts_libres_rollback.sql
-- ══════════════════════════════════════════════════════════════════════

begin;

-- ─── 0. Garde d'entrée : on part bien de db/60 telle qu'en prod le 06/11 ───
do $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.supprimer_fiche(text,text,text,text,boolean)'::regprocedure)
     <> 'e015b770fef173f55edff5bd45198ec5' then
    raise exception 'supprimer_fiche a changé depuis db/60 : arrêt, relire avant d''appliquer';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public._garde_suppression_directe()'::regprocedure)
     <> '84b7cab4a528386012e736df435559db' then
    raise exception '_garde_suppression_directe a changé depuis db/60 : arrêt';
  end if;
end $$;

-- ─── 1. supprimer_fiche (copie de db/60 l. 180-401, un seul bloc changé : « Droit sur la fiche ») ───
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

  -- Droit sur la fiche. Contact (db/62, 06/11) : tout commercial (le référent est informatif).
  -- Compte : responsable ou admin (D4 de la spec du 05/11, inchangé).
  if v_role <> 'admin' and v_type = 'compte' then
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
  'db/60 + db/62 : seule porte de suppression d''un compte ou d''un contact. Contact : tout commercial ; compte : responsable (commercial) ou admin ; '
  'garde-fous (compte vide, contact hors effectif/mission/besoin/séquence), quota 20/24 h, archive dans corbeille.';
revoke all on function public.supprimer_fiche(text, text, text, text, boolean) from public, anon;
grant execute on function public.supprimer_fiche(text, text, text, text, boolean) to authenticated, service_role;

-- ─── 2. Garde du DELETE direct (copie de db/60 l. 596-612, message seul changé) ───
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
    raise exception 'Suppression directe fermée sur les % : utilise le bouton Supprimer de l''appli (recharge la page) ou mets à jour le connecteur Claude. Elle est gardée en archive.',
      tg_table_name using errcode = '42501';
  end if;
  return null;
end;
$$;
revoke all on function public._garde_suppression_directe() from public, anon, authenticated, service_role;
comment on function public._garde_suppression_directe() is
  'db/60 + db/62 : DELETE direct sur contacts/comptes fermé aux utilisateurs connectés non admin (passer par supprimer_fiche).';

-- ─── 3. Tests intégrés (fiches ZZTEST62 créées puis annulées : rien ne reste en base) ───
do $$
declare
  a_id uuid; a_nom text; b_id uuid; b_nom text; pa_id uuid;
  j_a text; j_pa text;
  k1 bigint; c1 bigint; am uuid; t1 text;
  res jsonb; n int; n2 int; v text;
  n_corb int; n_jour int;
begin
  select p.id, p.nom into a_id, a_nom from public.profiles p where p.role = 'commercial' order by p.nom limit 1;
  select p.id, p.nom into b_id, b_nom from public.profiles p where p.role in ('admin','commercial') and p.nom <> a_nom order by p.nom limit 1;
  select p.id into pa_id from public.profiles p where p.role = 'partner' order by p.nom limit 1;
  if a_id is null or b_id is null then
    raise exception 'Tests impossibles : il faut un commercial et un autre admin/commercial dans profiles.';
  end if;
  j_a  := json_build_object('sub', a_id,  'role', 'authenticated')::text;
  j_pa := json_build_object('sub', pa_id, 'role', 'authenticated')::text;
  select count(*) into n_corb from public.corbeille;
  select count(*) into n_jour from public.corbeille_journal;
  raise notice 'Tests avec A = % (commercial), B = % (référent des fiches)', a_nom, b_nom;

  -- T1 : A supprime le contact de B (historique, tâche, lien compte) → archivé, référent et auteur notés.
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST62 compte B', b_nom) returning id into k1;
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 contact B', b_nom, 'Prospect') returning id into c1;
    insert into public.contact_compte (contact_id, compte_id, is_primary) values (c1, k1, true);
    t1 := 'zztest62-' || c1;
    insert into public.taches (id, titre, contact_id, responsable) values (t1, 'ZZTEST62 relance', c1, b_nom);
    insert into public.historique_actions (id_prospect, date, type_action, details, responsable, tache_id)
      values (c1, current_date - 3, 'Appel sortant', 'ZZTEST62 a', b_nom, t1);
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    res := public.supprimer_fiche('contact', c1::text, 'test db62', 'app');
    reset role;
    if exists (select 1 from public.contacts where id = c1) then raise exception 'KO T1 : contact toujours là'; end if;
    if exists (select 1 from public.historique_actions where id_prospect = c1) then raise exception 'KO T1 : historique resté'; end if;
    select count(*) into n from public.corbeille
     where id = (res ->> 'archive_id')::bigint and objet_type = 'contact' and responsable_fiche = b_nom
       and par_nom = a_nom and par_role = 'commercial' and motif = 'test db62';
    if n <> 1 then raise exception 'KO T1 : archive incorrecte (%)', res; end if;
    select jsonb_array_length(liens -> 'historique_actions'), jsonb_array_length(liens -> 'taches') + jsonb_array_length(liens -> 'contact_compte')
      into n, n2 from public.corbeille where id = (res ->> 'archive_id')::bigint;
    if n <> 1 or n2 <> 2 then raise exception 'KO T1 : archive incomplète (historique %, tâche+lien %)', n, n2; end if;
    select count(*) into n from public.corbeille_journal where corbeille_id = (res ->> 'archive_id')::bigint and evenement = 'suppression';
    if n <> 1 then raise exception 'KO T1 : journal (% ligne)', n; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T1 : un commercial supprime le contact d''un collègue, archivé avec historique, liens et tâches';
  end;

  -- T2 : A ne supprime toujours pas le compte vide de B.
  begin
    insert into public.comptes (nom, responsable) values ('ZZTEST62 compte vide B', b_nom) returning id into k1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('compte', k1::text, null, 'app');
    raise exception 'KO T2 : suppression du compte d''un collègue acceptée';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like 'Suppression refusée : cette fiche appartient à%' then raise exception 'KO T2 : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T2 : un commercial ne supprime toujours pas le compte vide d''un collègue';
  end;

  -- T3 : garde-fous contact intacts sur le contact d'un collègue (effectif, mission, besoin, séquence active).
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 cdi', b_nom, 'Consultant CDI') returning id into c1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('contact', c1::text, null, 'app');
    raise exception 'KO T3a : consultant supprimé';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like '%Un membre de l''effectif ne se supprime pas%' then raise exception 'KO T3a : mauvais refus (%)', sqlerrm; end if;
  end;
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 mission', b_nom, 'Client') returning id into c1;
    insert into public.missions (consultant, contact_referent_id, responsable) values ('ZZTEST62', c1, b_nom);
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('contact', c1::text, null, 'app');
    raise exception 'KO T3b : contact en mission supprimé';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like '%encore lié à 1 mission%' then raise exception 'KO T3b : mauvais refus (%)', sqlerrm; end if;
  end;
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 besoin', b_nom, 'Prospect') returning id into c1;
    insert into public.besoins (agence, statut, titre, responsable, contact_id) values ('Lyon', 'Opportunité', 'ZZTEST62', b_nom, c1);
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('contact', c1::text, null, 'app');
    raise exception 'KO T3c : contact sur un besoin supprimé';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like '%encore lié à 1 besoin%' then raise exception 'KO T3c : mauvais refus (%)', sqlerrm; end if;
  end;
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 seq', b_nom, 'Prospect') returning id into c1;
    set local session_replication_role = replica;   -- séquence factice, sans les déclencheurs de Jules
    insert into jules.agent_missions (owner_id, titre) values (b_id, 'ZZTEST62') returning id into am;
    insert into jules.agent_sequences (owner_id, target_kind, target_ref, target_label, mission_id, statut, contact_id)
      values (b_id, 'contact_crm', c1::text, 'ZZTEST62', am, 'active', c1);
    set local session_replication_role = origin;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('contact', c1::text, null, 'app');
    raise exception 'KO T3d : contact en séquence active supprimé';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like '%1 séquence Jules en cours%' then raise exception 'KO T3d : mauvais refus (%)', sqlerrm; end if;
  end;
  raise notice 'OK T3 : contact consultant / en mission / sur un besoin / en séquence active toujours refusé';

  -- T4 : partner refusé, sans session refusé.
  if pa_id is not null then
    begin
      insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 partner', b_nom, 'Prospect') returning id into c1;
      perform set_config('request.jwt.claims', j_pa, true);
      set local role authenticated;
      perform public.supprimer_fiche('contact', c1::text, null, 'app');
      raise exception 'KO T4a : partner accepté';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Suppression refusée : réservée aux commerciaux%' then raise exception 'KO T4a : mauvais refus (%)', sqlerrm; end if;
    end;
  end if;
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 anon', b_nom, 'Prospect') returning id into c1;
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    set local role authenticated;
    perform public.supprimer_fiche('contact', c1::text, null, 'app');
    raise exception 'KO T4b : sans session accepté';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like 'Refusé : aucune session%' then raise exception 'KO T4b : mauvais refus (%)', sqlerrm; end if;
  end;
  raise notice 'OK T4 : partner refusé, sans session refusé';

  -- T5 : quota, la 21e suppression d'un commercial en 24 h est refusée (même sur le contact d'un collègue).
  begin
    insert into public.corbeille (objet_type, objet_id, ligne, origine, par_nom, par_user, par_role)
      select 'contact', 'zz' || g, '{}'::jsonb, 'app', a_nom, a_id, 'commercial' from generate_series(1, 20) g;
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 quota', b_nom, 'Prospect') returning id into c1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    perform public.supprimer_fiche('contact', c1::text, null, 'app');
    raise exception 'KO T5 : quota dépassé accepté';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like '%(limite 20)%' then raise exception 'KO T5 : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T5 : quota, la 21e suppression d''un commercial en 24 h est refusée';
  end;

  -- T6 : DELETE direct d'un commercial sur contacts toujours refusé, avec le nouveau message.
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 direct', a_nom, 'Prospect') returning id into c1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    delete from public.contacts where id = c1;
    raise exception 'KO T6 : DELETE direct accepté sans erreur';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like 'Suppression directe fermée sur les contacts%Elle est gardée en archive.' or sqlerrm like '%Seul le responsable%' then
      raise exception 'KO T6 : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T6 : DELETE direct d''un commercial sur contacts toujours refusé avec le nouveau message';
  end;

  -- T7 : contact sans référent ou d'un membre parti : supprimable par un commercial (archivé).
  begin
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 parti', 'Membre Parti ZZ', 'Prospect') returning id into c1;
    perform set_config('request.jwt.claims', j_a, true);
    set local role authenticated;
    res := public.supprimer_fiche('contact', c1::text, null, 'app');
    insert into public.contacts (prenom, nom, responsable, statut) values ('Zz', 'TEST62 sans', null, 'Prospect') returning id into c1;
    res := public.supprimer_fiche('contact', c1::text, null, 'app');
    reset role;
    select count(*) into n from public.corbeille where par_nom = a_nom and libelle in ('Zz TEST62 parti', 'Zz TEST62 sans');
    if n <> 2 then raise exception 'KO T7 : % archive(s), attendu 2', n; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T7 : contact sans référent ou d''un membre parti supprimable par un commercial (archivé)';
  end;

  -- Rien ne doit rester des tests.
  if (select count(*) from public.corbeille) <> n_corb or (select count(*) from public.corbeille_journal) <> n_jour then
    raise exception 'KO : des lignes de test sont restées dans la corbeille ou son journal';
  end if;
  if exists (select 1 from public.contacts where nom like 'TEST62%') or exists (select 1 from public.comptes where nom like 'ZZTEST62%') then
    raise exception 'KO : fiche de test restée';
  end if;
end $$;

notify pgrst, 'reload schema';

commit;
