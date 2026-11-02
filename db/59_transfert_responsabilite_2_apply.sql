-- ══════════════════════════════════════════════════════════════════════
-- 59 — Transfert de responsabilité d'un contact ou d'un compte (02/11/2026, GO Nicolas Slack)
-- BLOC 2/3 — APPLY (transactionnel, auto-testé, tout ou rien)
--
-- CE QUE ÇA AJOUTE (rien n'est modifié ni supprimé) :
--   1. Table `transferts_responsabilite` : le journal de chaque transfert (qui, quoi, de qui, à qui, quand).
--   2. Fonction `transferer_responsabilite(p_type, p_id, p_nouveau)` (SECURITY DEFINER), appelée par
--      l'app (sb.rpc) et le MCP. Elle ne touche QU'UNE colonne : `responsable` (+ `updated_at`).
--
-- RÈGLES TENUES PAR LA FONCTION :
--   - appelant connecté, rôle admin ou commercial (un partner ne transfère rien) ;
--   - appelant = responsable ACTUEL de la fiche, ou admin. Pas de « reprise de main » : un commercial
--     ne peut pas s'attribuer la fiche d'un collègue (c'est déjà la règle du trigger db/10, inchangé) ;
--   - cible = un profil admin/commercial existant, non banni, non supprimé, différent du responsable actuel.
--
-- CE QUI NE BOUGE PAS (volontairement, rien de plus que demandé) :
--   - les contacts rattachés à un compte transféré gardent leur responsable ;
--   - les tâches, besoins, missions et actions liés gardent le leur ;
--   - contact_compte, groupe, trigger de sync consultants : non concernés (on n'écrit que `responsable`) ;
--   - pas de ligne dans historique_actions : son trigger trg_update_date_dernier ferait bouger
--     « dernier contact » sur une simple réattribution. Le journal dédié porte la trace.
--   - les policies RLS et le trigger db/10 : inchangés. Aucune colonne n'est ouverte en écriture.
--
-- Lancer sur le Mac mini (superuser, arrêt à la 1re erreur, relance PostgREST) :
--   zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/59_transfert_responsabilite_2_apply.sql
-- Toute incohérence pendant les tests intégrés → exception → ROLLBACK complet, rien n'est appliqué.
-- Retour arrière : db/59_transfert_responsabilite_rollback.sql
-- ══════════════════════════════════════════════════════════════════════

begin;

-- ─── 1. Journal ───
create table if not exists public.transferts_responsabilite (
  id                  bigserial primary key,
  objet_type          text        not null check (objet_type in ('contact','compte')),
  objet_id            bigint      not null,
  ancien_responsable  text,
  nouveau_responsable text        not null,
  par_nom             text        not null,
  par_user            uuid        not null,
  created_at          timestamptz not null default now()
);
create index if not exists transferts_responsabilite_objet_idx
  on public.transferts_responsabilite (objet_type, objet_id, created_at desc);

comment on table public.transferts_responsabilite is
  'Journal des transferts de responsabilité (contact/compte). Écrit UNIQUEMENT par transferer_responsabilite() (db/59).';

alter table public.transferts_responsabilite enable row level security;
revoke all on public.transferts_responsabilite from anon, authenticated;
grant select on public.transferts_responsabilite to authenticated;

drop policy if exists transferts_resp_lecture on public.transferts_responsabilite;
create policy transferts_resp_lecture on public.transferts_responsabilite
  for select to authenticated
  using (get_my_role() = any (array['admin','commercial']));
-- Aucune policy INSERT/UPDATE/DELETE : seule la fonction (propriétaire de la table) y écrit.


-- ─── 2. La fonction ───
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


-- ─── 3. Tests intégrés (chaque cas est annulé ; un échec annule TOUTE la migration) ───
do $$
declare
  a_id uuid; a_nom text; b_nom text;
  c_a bigint; c_autre bigint; k_a bigint;
  v text; n int; n_avant int;
  v_jwt text; adm_id uuid;
begin
  -- A = un commercial actif qui possède au moins un contact ET un compte ; B = un autre commercial actif.
  select p.id, p.nom into a_id, a_nom
  from public.profiles p left join auth.users u on u.id = p.id
  where p.role = 'commercial' and u.deleted_at is null
    and not (coalesce(u.banned_until, '-infinity'::timestamptz) > now())
    and exists (select 1 from public.contacts c where c.responsable = p.nom)
    and exists (select 1 from public.comptes  k where k.responsable = p.nom)
  order by p.nom limit 1;
  select p.nom into b_nom
  from public.profiles p left join auth.users u on u.id = p.id
  where p.role in ('admin','commercial') and p.nom <> a_nom and u.deleted_at is null
    and not (coalesce(u.banned_until, '-infinity'::timestamptz) > now())
  order by p.nom limit 1;
  if a_id is null or b_nom is null then
    raise exception 'Tests impossibles : pas de commercial actif possédant contact + compte, ou pas de second commercial.';
  end if;
  select id into c_a     from public.contacts where responsable = a_nom order by id limit 1;
  select id into k_a     from public.comptes  where responsable = a_nom order by id limit 1;
  select id into c_autre from public.contacts where responsable is distinct from a_nom order by id limit 1;
  select count(*) into n_avant from public.transferts_responsabilite;
  v_jwt := json_build_object('sub', a_id, 'role', 'authenticated')::text;
  raise notice 'Tests avec A = %, B = %, contact A = %, compte A = %, contact d''un autre = %', a_nom, b_nom, c_a, k_a, c_autre;

  -- T1 : A donne SON contact à B → passe, une seule colonne bouge, journal écrit.
  begin
    perform set_config('request.jwt.claims', v_jwt, true);
    perform set_config('request.jwt.claim.sub', a_id::text, true);
    set local role authenticated;
    perform public.transferer_responsabilite('contact', c_a, b_nom);
    reset role;
    select responsable into v from public.contacts where id = c_a;
    if v is distinct from b_nom then raise exception 'KO T1 : responsable = %, attendu %', v, b_nom; end if;
    select count(*) into n from public.transferts_responsabilite
      where objet_type = 'contact' and objet_id = c_a and nouveau_responsable = b_nom and par_nom = a_nom;
    if n <> 1 then raise exception 'KO T1 : journal (% ligne)', n; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T1 : le responsable donne son contact';
  end;

  -- T2 : A donne SON compte à B → passe.
  begin
    perform set_config('request.jwt.claims', v_jwt, true);
    perform set_config('request.jwt.claim.sub', a_id::text, true);
    set local role authenticated;
    perform public.transferer_responsabilite('compte', k_a, b_nom);
    reset role;
    select responsable into v from public.comptes where id = k_a;
    if v is distinct from b_nom then raise exception 'KO T2 : responsable = %, attendu %', v, b_nom; end if;
    raise exception 'TEST_ANNULE';
  exception when others then
    if sqlerrm <> 'TEST_ANNULE' then raise; end if;
    raise notice 'OK T2 : le responsable donne son compte';
  end;

  -- T3 : A tente de s'attribuer (ou de donner) le contact d'un autre → refusé.
  if c_autre is not null then
    begin
      perform set_config('request.jwt.claims', v_jwt, true);
      perform set_config('request.jwt.claim.sub', a_id::text, true);
      set local role authenticated;
      perform public.transferer_responsabilite('contact', c_autre, a_nom);
      raise exception 'KO T3 : reprise de main acceptée';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Transfert refusé : cette fiche appartient%' then raise exception 'KO T3 : mauvais refus (%)', sqlerrm; end if;
      raise notice 'OK T3 : pas de reprise de main';
    end;
  end if;

  -- T4 : cible inconnue → refusé.
  begin
    perform set_config('request.jwt.claims', v_jwt, true);
    perform set_config('request.jwt.claim.sub', a_id::text, true);
    set local role authenticated;
    perform public.transferer_responsabilite('contact', c_a, 'Personne Inexistante');
    raise exception 'KO T4 : cible inconnue acceptée';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like 'Transfert refusé : « Personne Inexistante »%' then raise exception 'KO T4 : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T4 : cible hors commerciaux actifs refusée';
  end;

  -- T5 : sans session (auth.uid() nul, ex. service_role) → refusé.
  begin
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    perform set_config('request.jwt.claim.sub', '', true);
    perform public.transferer_responsabilite('contact', c_a, b_nom);
    raise exception 'KO T5 : transfert sans session accepté';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    if sqlerrm not like 'Transfert refusé : aucune session%' then raise exception 'KO T5 : mauvais refus (%)', sqlerrm; end if;
    raise notice 'OK T5 : sans session, refusé';
  end;

  -- T6 : la table de journal n'est pas écrivable en direct par un commercial.
  begin
    perform set_config('request.jwt.claims', v_jwt, true);
    perform set_config('request.jwt.claim.sub', a_id::text, true);
    set local role authenticated;
    insert into public.transferts_responsabilite (objet_type, objet_id, nouveau_responsable, par_nom, par_user)
      values ('contact', 0, 'x', 'x', a_id);
    raise exception 'KO T6 : insertion directe acceptée';
  exception when others then
    if sqlerrm like 'KO%' then raise; end if;
    raise notice 'OK T6 : journal non écrivable en direct (%)', sqlerrm;
  end;

  -- T7 : l'admin confie la fiche d'un collègue → passe.
  select id into adm_id from public.profiles where role = 'admin' order by nom limit 1;
  if adm_id is not null and c_autre is not null then
    begin
      perform set_config('request.jwt.claims', json_build_object('sub', adm_id, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', adm_id::text, true);
      set local role authenticated;
      perform public.transferer_responsabilite('contact', c_autre, a_nom);
      reset role;
      select responsable into v from public.contacts where id = c_autre;
      if v is distinct from a_nom then raise exception 'KO T7 : responsable = %, attendu %', v, a_nom; end if;
      raise exception 'TEST_ANNULE';
    exception when others then
      if sqlerrm <> 'TEST_ANNULE' then raise; end if;
      raise notice 'OK T7 : l''admin réattribue librement';
    end;
  end if;

  -- T8 : cible bannie (ex. collaborateur parti) → refusé, si un tel profil existe.
  select p.nom into v
  from public.profiles p join auth.users u on u.id = p.id
  where p.role in ('admin','commercial') and (u.banned_until > now() or u.deleted_at is not null)
  order by p.nom limit 1;
  if v is not null then
    begin
      perform set_config('request.jwt.claims', v_jwt, true);
      perform set_config('request.jwt.claim.sub', a_id::text, true);
      set local role authenticated;
      perform public.transferer_responsabilite('contact', c_a, v);
      raise exception 'KO T8 : cible bannie acceptée';
    exception when others then
      if sqlerrm like 'KO%' then raise; end if;
      if sqlerrm not like 'Transfert refusé : « %' then raise exception 'KO T8 : mauvais refus (%)', sqlerrm; end if;
      raise notice 'OK T8 : cible bannie refusée';
    end;
  end if;

  -- Rien ne doit rester des tests.
  select count(*) into n from public.transferts_responsabilite;
  if n <> n_avant then raise exception 'KO : % ligne(s) de test restée(s) dans le journal', n - n_avant; end if;
end $$;

-- PostgREST doit voir la nouvelle fonction (crm-sql.sh le relance aussi, ceinture + bretelles).
notify pgrst, 'reload schema';

commit;
