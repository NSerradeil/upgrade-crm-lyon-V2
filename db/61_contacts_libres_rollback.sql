-- ══════════════════════════════════════════════════════════════════════
-- 61 — Contacts libres d'accès — ROLLBACK (remet exactement l'état du 06/11 avant db/61)
--   zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/61_contacts_libres_rollback.sql
-- Les changements de référent faits entre-temps restent (ils sont journalisés dans transferts_responsabilite).
-- ══════════════════════════════════════════════════════════════════════

begin;

-- 1. Garde db/10 remise sur contacts, garde db/61 retirée.
drop trigger if exists trg_garde_referent_contact on public.contacts;
drop function if exists public.garde_referent_contact();
drop trigger if exists trg_guard_responsable on public.contacts;
create trigger trg_guard_responsable before update of responsable on public.contacts
  for each row execute function public.guard_responsable_change();

-- 2. transferer_responsabilite telle que db/59 (copie exacte, md5 du corps d99ff764f87f2cae147c90853de48fa5).
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

  -- Droit : responsable actuel ou admin. Pas de reprise de main.
  if v_par_role <> 'admin' and v_ancien is distinct from v_par_nom then
    raise exception 'Transfert refusé : cette fiche appartient à %. Seul son responsable ou un admin peut la confier à quelqu''un d''autre.',
      coalesce(v_ancien, '(personne)') using errcode = 'P0001';
  end if;

  if v_ancien is not distinct from v_cible then
    raise exception 'Transfert inutile : % est déjà responsable de cette fiche.', v_cible using errcode = 'P0001';
  end if;

  -- Écriture : UNE colonne. Le trigger db/10 repasse derrière et doit être d'accord (même règle).
  if v_type = 'contact' then
    update public.contacts set responsable = v_cible, updated_at = now() where id = p_id;
  else
    update public.comptes  set responsable = v_cible, updated_at = now() where id = p_id;
  end if;

  insert into public.transferts_responsabilite (objet_type, objet_id, ancien_responsable, nouveau_responsable, par_nom, par_user)
  values (v_type, p_id, v_ancien, v_cible, v_par_nom, v_uid);

  return jsonb_build_object('type', v_type, 'id', p_id, 'ancien', v_ancien, 'nouveau', v_cible, 'par', v_par_nom);
end;
$$;

comment on function public.transferer_responsabilite(text, bigint, text) is
  'db/59 : le responsable actuel (ou un admin) confie un contact ou un compte à un autre commercial actif. '
  'N''écrit que la colonne responsable, journalise dans transferts_responsabilite.';

revoke all on function public.transferer_responsabilite(text, bigint, text) from public, anon;
grant execute on function public.transferer_responsabilite(text, bigint, text) to authenticated;

-- 3. Contrôle : on est bien revenu à l'état d'avant.
do $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.transferer_responsabilite(text,bigint,text)'::regprocedure)
     <> 'd99ff764f87f2cae147c90853de48fa5' then
    raise exception 'KO rollback : transferer_responsabilite différente de db/59';
  end if;
  if (select count(*) from pg_trigger where tgname = 'trg_guard_responsable'
        and tgrelid in ('public.contacts'::regclass,'public.comptes'::regclass,'public.besoins'::regclass,'public.missions'::regclass,'public.taches'::regclass)) <> 5 then
    raise exception 'KO rollback : garde db/10 absente d''une des 5 tables';
  end if;
  raise notice 'OK rollback db/61 : état du 06/11 rétabli';
end $$;

notify pgrst, 'reload schema';

commit;
