-- ══════════════════════════════════════════════════════════════════════
-- 61 — Contacts libres d'accès (06/11/2026, décision D1 de Nicolas)
-- BLOC 2/3 — APPLY (transactionnel, auto-testé, tout ou rien)
--
-- CE QUI CHANGE (contacts seulement) :
--   1. Le trigger db/10 `trg_guard_responsable` est retiré de la table `contacts` (il reste sur comptes, besoins,
--      missions, taches). Il est remplacé sur `contacts` par `trg_garde_referent_contact` :
--        - tout commercial (rôle admin ou commercial) peut changer le référent d'un contact ;
--        - un partner, ou une écriture sans session, reste refusé (comme avant : aucun droit gagné) ;
--        - chaque changement de référent est journalisé dans `transferts_responsabilite` (même par UPDATE direct).
--   2. `transferer_responsabilite` : pour un CONTACT, tout commercial peut en changer le référent ; pour un COMPTE,
--      règle inchangée (responsable actuel ou admin). Signature, droits et journal inchangés.
--
-- CE QUI NE BOUGE PAS : la colonne contacts.responsable (pas de DROP), les policies RLS (DELETE contacts reste
-- admin seul : la suppression passe par supprimer_fiche, voir db/62), les comptes, besoins, missions, tâches.
--
-- Lancer sur le Mac mini (superuser, arrêt à la 1re erreur, relance PostgREST) :
--   zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/61_contacts_libres_2_apply.sql
-- Toute incohérence pendant les tests intégrés → exception → ROLLBACK complet, rien n'est appliqué.
-- Retour arrière : db/61_contacts_libres_rollback.sql
-- ══════════════════════════════════════════════════════════════════════

begin;

-- ─── 0. Garde d'entrée : on part bien de l'état relevé le 06/11 ───
do $$
begin
  if to_regclass('public.transferts_responsabilite') is null
     or to_regprocedure('public.transferer_responsabilite(text,bigint,text)') is null then
    raise exception 'db/59 absente : arrêt';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.transferer_responsabilite(text,bigint,text)'::regprocedure)
     <> 'd99ff764f87f2cae147c90853de48fa5' then
    raise exception 'transferer_responsabilite a changé depuis db/59 : arrêt, relire avant d''appliquer';
  end if;
end $$;

-- ─── 1. Garde du référent de contact ───
create or replace function public.garde_referent_contact()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := public.get_my_role();
  v_nom  text := public.get_my_nom();
begin
  if new.responsable is not distinct from old.responsable then
    return new;
  end if;
  -- 06/11 : le référent d'un contact est informatif, tout commercial peut le changer. Un partner ou une écriture
  -- sans session ne le peut pas (comme sous db/10).
  if v_role is null or v_role not in ('admin','commercial') then
    raise exception 'Changement de référent refusé : réservé aux commerciaux (référent actuel : %).',
      coalesce(old.responsable, '(personne)') using errcode = 'check_violation';
  end if;
  -- Journal : transferer_responsabilite écrit déjà sa ligne (drapeau local) ; sinon on l'écrit ici.
  if coalesce(current_setting('crm.transfert_journalise', true), '') <> 'oui' then
    insert into public.transferts_responsabilite (objet_type, objet_id, ancien_responsable, nouveau_responsable, par_nom, par_user)
    values ('contact', new.id, old.responsable, coalesce(new.responsable, '(aucun)'), v_nom, auth.uid());
  end if;
  return new;
end;
$$;

comment on function public.garde_referent_contact() is
  'db/61 (06/11) : référent de contact modifiable par tout commercial (admin ou commercial), jamais par un partner '
  'ni sans session ; chaque changement est journalisé dans transferts_responsabilite.';

revoke all on function public.garde_referent_contact() from public, anon, authenticated;

drop trigger if exists trg_guard_responsable on public.contacts;
drop trigger if exists trg_garde_referent_contact on public.contacts;
create trigger trg_garde_referent_contact before update of responsable on public.contacts
  for each row execute function public.garde_referent_contact();


-- ─── 2. transferer_responsabilite : contact ouvert à tout commercial ───
create or replace function public.transferer_responsabilite(p_type text, p_id bigint, p_nouveau text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_par_nom text;
  v_par_role text;
  v_cible   text;
  v_ancien  text;
  v_type    text := lower(trim(coalesce(p_type, '')));
begin
  -- Appelant : connecté, admin ou commercial.
  if v_uid is null then
    raise exception 'Transfert refusé : aucune session utilisateur (connexion requise).' using errcode = 'P0001';
  end if;
  select p.nom, p.role into v_par_nom, v_par_role from public.profiles p where p.id = v_uid;
  if v_par_nom is null or v_par_role is null or v_par_role not in ('admin','commercial') then
    raise exception 'Transfert refusé : réservé aux commerciaux et à l''administration.' using errcode = 'P0001';
  end if;

  if v_type not in ('contact','compte') then
    raise exception 'Transfert refusé : type « % » inconnu (contact ou compte).', p_type using errcode = 'P0001';
  end if;

  -- Cible : un profil admin/commercial actif (ni banni ni supprimé).
  select p.nom into v_cible
  from public.profiles p
  left join auth.users u on u.id = p.id
  where p.nom = trim(coalesce(p_nouveau, ''))
    and p.role in ('admin','commercial')
    and not (coalesce(u.banned_until, '-infinity'::timestamptz) > now())
    and u.deleted_at is null;
  if v_cible is null then
    raise exception 'Transfert refusé : « % » n''est pas un commercial actif du CRM.', coalesce(p_nouveau, '(vide)')
      using errcode = 'P0001';
  end if;

  -- Fiche : verrouillée le temps du transfert.
  if v_type = 'contact' then
    select c.responsable into v_ancien from public.contacts c where c.id = p_id for update;
  else
    select c.responsable into v_ancien from public.comptes c where c.id = p_id for update;
  end if;
  if not found then
    raise exception 'Transfert refusé : % % introuvable.', v_type, p_id using errcode = 'P0001';
  end if;

  -- Droit : contact = référent informatif, tout commercial peut le changer (06/11) ; compte = responsable ou admin.
  if v_type = 'compte' and v_par_role <> 'admin' and v_ancien is distinct from v_par_nom then
    raise exception 'Transfert refusé : ce compte appartient à %. Seul son responsable ou un admin peut le confier à quelqu''un d''autre.',
      coalesce(v_ancien, '(personne)') using errcode = 'P0001';
  end if;

  if v_ancien is not distinct from v_cible then
    raise exception 'Transfert inutile : % est déjà responsable de cette fiche.', v_cible using errcode = 'P0001';
  end if;

  -- Écriture : UNE colonne. Compte : le trigger db/10 repasse derrière (même règle). Contact : le trigger db/61
  -- vérifie le rôle ; le drapeau local lui évite d'écrire une seconde ligne de journal.
  if v_type = 'contact' then
    perform set_config('crm.transfert_journalise', 'oui', true);
    update public.contacts set responsable = v_cible, updated_at = now() where id = p_id;
    perform set_config('crm.transfert_journalise', '', true);
  else
    update public.comptes  set responsable = v_cible, updated_at = now() where id = p_id;
  end if;

  insert into public.transferts_responsabilite (objet_type, objet_id, ancien_responsable, nouveau_responsable, par_nom, par_user)
  values (v_type, p_id, v_ancien, v_cible, v_par_nom, v_uid);

  return jsonb_build_object('type', v_type, 'id', p_id, 'ancien', v_ancien, 'nouveau', v_cible, 'par', v_par_nom);
end;
$$;

comment on function public.transferer_responsabilite(text, bigint, text) is
  'db/59 + db/61 : contact : tout commercial en change le référent (informatif) ; compte : responsable actuel ou admin. '
  'Cible = commercial actif. N''écrit que la colonne responsable, journalise dans transferts_responsabilite.';

revoke all on function public.transferer_responsabilite(text, bigint, text) from public, anon;
grant execute on function public.transferer_responsabilite(text, bigint, text) to authenticated;


-- ─── 3. Tests intégrés (fiches ZZTEST61 créées puis TOUT annulé ; un échec annule TOUTE la migration) ───
do $$
declare
  a_id uuid; a_nom text; b_nom text; p_id uuid;
  c_b bigint; k_b bigint;
  v text; n int; n_avant int;
  v_jwt text;
begin
  -- A = un commercial ; B = un autre admin/commercial ; P = un partner (s'il existe).
  select p.id, p.nom into a_id, a_nom from public.profiles p where p.role = 'commercial' order by p.nom limit 1;
  select p.nom into b_nom from public.profiles p where p.role in ('admin','commercial') and p.nom <> a_nom order by p.nom limit 1;
  select p.id into p_id from public.profiles p where p.role = 'partner' order by p.nom limit 1;
  if a_id is null or b_nom is null then
    raise exception 'Tests impossibles : il faut deux profils admin/commercial.';
  end if;
  v_jwt := json_build_object('sub', a_id, 'role', 'authenticated')::text;
  select count(*) into n_avant from public.transferts_responsabilite;

  begin
    -- Fiches de test : un contact et un compte dont B est le référent.
    insert into public.contacts (nom, prenom, responsable) values ('ZZTEST61', 'Contact', b_nom) returning id into c_b;
    insert into public.comptes (nom, responsable) values ('ZZTEST61 Compte', b_nom) returning id into k_b;
    raise notice 'Tests avec A = %, B = %, contact % et compte % de B', a_nom, b_nom, c_b, k_b;

    -- T1 : A change le référent du contact de B par la fonction → passe, UNE ligne de journal.
    begin
      perform set_config('request.jwt.claims', v_jwt, true);
      perform set_config('request.jwt.claim.sub', a_id::text, true);
      set local role authenticated;
      perform public.transferer_responsabilite('contact', c_b, a_nom);
      reset role;
      select responsable into v from public.contacts where id = c_b;
      if v is distinct from a_nom then raise exception 'KO T1 : référent = %, attendu %', v, a_nom; end if;
      select count(*) into n from public.transferts_responsabilite where objet_type = 'contact' and objet_id = c_b;
      if n <> 1 then raise exception 'KO T1 : % ligne(s) de journal, attendu 1', n; end if;
      select count(*) into n from public.transferts_responsabilite
       where objet_type = 'contact' and objet_id = c_b and par_nom = a_nom and ancien_responsable = b_nom;
      if n <> 1 then raise exception 'KO T1 : ligne de journal incorrecte'; end if;
      raise exception 'TEST_ANNULE';
    exception when others then
      if sqlerrm <> 'TEST_ANNULE' then raise; end if;
      raise notice 'OK T1 : un commercial change le référent d''un contact d''un collègue (journalisé)';
    end;

    -- T2 : A ne prend toujours pas le compte de B.
    begin
      perform set_config('request.jwt.claims', v_jwt, true);
      perform set_config('request.jwt.claim.sub', a_id::text, true);
      set local role authenticated;
      perform public.transferer_responsabilite('compte', k_b, a_nom);
      raise exception 'KO T2 : reprise du compte d''un collègue acceptée';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Transfert refusé : ce compte appartient%' then raise exception 'KO T2 : mauvais refus (%)', sqlerrm; end if;
      raise notice 'OK T2 : un commercial ne prend toujours pas le compte d''un collègue';
    end;

    -- T3 : un partner est refusé par la fonction.
    if p_id is not null then
      begin
        perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', p_id::text, true);
        set local role authenticated;
        perform public.transferer_responsabilite('contact', c_b, a_nom);
        raise exception 'KO T3 : partner accepté';
      exception when others then
        if sqlerrm like 'KO%' then raise; end if;
        if sqlerrm not like 'Transfert refusé : réservé aux commerciaux%' then raise exception 'KO T3 : mauvais refus (%)', sqlerrm; end if;
        raise notice 'OK T3 : un partner est refusé';
      end;
    else
      raise notice 'OK T3 : (aucun partner dans cette base, cas non joué)';
    end if;

    -- T4 : UPDATE direct du référent d'un contact par un commercial → accepté ET journalisé.
    begin
      perform set_config('request.jwt.claims', v_jwt, true);
      perform set_config('request.jwt.claim.sub', a_id::text, true);
      set local role authenticated;
      update public.contacts set responsable = a_nom where id = c_b;
      reset role;
      select responsable into v from public.contacts where id = c_b;
      if v is distinct from a_nom then raise exception 'KO T4 : référent = %, attendu %', v, a_nom; end if;
      select count(*) into n from public.transferts_responsabilite
       where objet_type = 'contact' and objet_id = c_b and par_nom = a_nom and par_user = a_id
         and ancien_responsable = b_nom and nouveau_responsable = a_nom;
      if n <> 1 then raise exception 'KO T4 : journal (% ligne)', n; end if;
      raise exception 'TEST_ANNULE';
    exception when others then
      if sqlerrm <> 'TEST_ANNULE' then raise; end if;
      raise notice 'OK T4 : UPDATE direct du référent d''un contact par un commercial accepté et journalisé';
    end;

    -- T5 : UPDATE direct du responsable du compte d'un collègue → toujours refusé (trigger db/10).
    begin
      perform set_config('request.jwt.claims', v_jwt, true);
      perform set_config('request.jwt.claim.sub', a_id::text, true);
      set local role authenticated;
      update public.comptes set responsable = a_nom where id = k_b;
      raise exception 'KO T5 : réattribution du compte d''un collègue acceptée';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Réattribution refusée%' then raise exception 'KO T5 : mauvais refus (%)', sqlerrm; end if;
      raise notice 'OK T5 : UPDATE direct du responsable d''un compte d''un collègue toujours refusé';
    end;

    -- T6 : garde db/10 toujours sur comptes, besoins, missions, taches ; garde db/61 sur contacts.
    select count(*) into n from pg_trigger
     where tgname = 'trg_guard_responsable'
       and tgrelid in ('public.comptes'::regclass, 'public.besoins'::regclass, 'public.missions'::regclass, 'public.taches'::regclass);
    if n <> 4 then raise exception 'KO T6 : % garde(s) db/10 sur les 4 tables, attendu 4', n; end if;
    if exists (select 1 from pg_trigger where tgname = 'trg_guard_responsable' and tgrelid = 'public.contacts'::regclass) then
      raise exception 'KO T6 : la garde db/10 est encore sur contacts';
    end if;
    if not exists (select 1 from pg_trigger where tgname = 'trg_garde_referent_contact' and tgrelid = 'public.contacts'::regclass) then
      raise exception 'KO T6 : garde db/61 absente de contacts';
    end if;
    raise notice 'OK T6 : garde de responsable toujours en place sur comptes, besoins, missions, taches';

    -- T7 : un partner, ou une écriture sans session, ne change pas le référent (le trigger refuse, RLS mise à part).
    begin
      if p_id is not null then
        perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', p_id::text, true);
      else
        perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
        perform set_config('request.jwt.claim.sub', '', true);
      end if;
      update public.contacts set responsable = a_nom where id = c_b;
      raise exception 'KO T7 : changement de référent accepté pour un partner / sans session';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Changement de référent refusé%' then raise exception 'KO T7 : mauvais refus (%)', sqlerrm; end if;
      raise notice 'OK T7 : partner ou sans session refusé';
    end;

    raise exception 'FIXTURES_ANNULEES';
  exception when others then
    if sqlerrm <> 'FIXTURES_ANNULEES' then raise; end if;
  end;

  -- Rien ne doit rester des tests.
  select count(*) into n from public.transferts_responsabilite;
  if n <> n_avant then raise exception 'KO : % ligne(s) de test restée(s) dans le journal', n - n_avant; end if;
  if exists (select 1 from public.contacts where nom = 'ZZTEST61') or exists (select 1 from public.comptes where nom = 'ZZTEST61 Compte') then
    raise exception 'KO : fiche de test restée';
  end if;
end $$;

-- PostgREST doit voir la nouvelle fonction (crm-sql.sh le relance aussi).
notify pgrst, 'reload schema';

commit;
