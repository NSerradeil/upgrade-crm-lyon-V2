-- ══════════════════════════════════════════════════════════════════════
-- 68 — La fusion de contacts recolle les profils de dossier Jules — BLOC 3/3 — VÉRIFICATION + ESSAIS
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/68_fusion_recolle_jules_3_verif.sql
-- Tout se passe dans UNE transaction ANNULÉE à la fin (rollback) : les fiches et le profil d'essai disparaissent.
-- Avant 68, l'essai E2 s'arrête sur « profil détaché » (c'est le défaut corrigé).
-- ══════════════════════════════════════════════════════════════════════
\set ON_ERROR_STOP on
begin;

-- V1. Marques 68 + droits (attendu : 3 lignes deja_68 = t ; puis t / f / f).
select proname, prosecdef, proconfig, prosrc ~ 'db/68' as deja_68 from pg_proc
 where pronamespace = 'public'::regnamespace and proname in ('fusionner_contacts','_fusion_photo','_fusion_defaire') order by 1;
select has_function_privilege('authenticated', 'public.fusionner_contacts(bigint,bigint,text,text)', 'execute') as fusion_authenticated,
       has_function_privilege('authenticated', 'public._fusion_defaire(jsonb)', 'execute') as defaire_authenticated,
       has_function_privilege('authenticated', 'public._fusion_photo(bigint)', 'execute') as photo_authenticated;

-- E0. Données d'essai : deux fiches « même mail », même responsable (Nicolas), et un profil de dossier Jules relié
--     au doublon, dans un dossier de Nicolas qui n'est plus actif (la liste d'appels n'y réagit pas).
do $$
declare v_g int; v_d int; v_m uuid; v_p uuid;
begin
  select id into v_m from jules.agent_missions
   where owner_id = 'd61df9f5-dd0a-4d24-819f-186c89df52b1' and statut <> 'active' order by created_at desc limit 1;
  if v_m is null then raise exception 'essai 68 : aucun dossier inactif de Nicolas pour poser le profil d''essai'; end if;
  insert into public.contacts (prenom, nom, email, responsable, statut)
  values ('Essai', 'Soixantehuit', 'essai-db68@exemple.invalid', 'Nicolas Serradeil', 'Prospect') returning id into v_g;
  insert into public.contacts (prenom, nom, email, responsable, statut)
  values ('Essai', 'Soixantehuit', 'essai-db68@exemple.invalid', 'Nicolas Serradeil', 'Prospect') returning id into v_d;
  insert into jules.profils_mission (mission_id, owner_id, kind, nom, source, crm_contact_id)
  values (v_m, 'd61df9f5-dd0a-4d24-819f-186c89df52b1', 'decideur', 'Essai Soixantehuit', 'crm', v_d) returning id into v_p;
  perform set_config('db68.garde', v_g::text, true);
  perform set_config('db68.doublon', v_d::text, true);
  perform set_config('db68.profil', v_p::text, true);
  raise notice 'E0 : fiche gardée %, doublon %, profil %', v_g, v_d, v_p;
end $$;

-- E1. RÔLE COMMERCIAL (Anne-Claire, authenticated) : la fonction s'exécute (pas de 42501) et refuse par la règle
--     métier (fusion réservée à un admin). Rien ne bouge.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"74bd8fea-bb7a-4c92-aec3-3ba750dfd44e","role":"authenticated"}', true);
do $$
begin
  if not has_function_privilege('public.fusionner_contacts(bigint,bigint,text,text)', 'execute') then
    raise exception 'E1 ÉCHEC : authenticated ne peut pas exécuter fusionner_contacts';
  end if;
  begin
    perform public.fusionner_contacts(current_setting('db68.garde')::bigint, current_setting('db68.doublon')::bigint, 'app', 'essai db/68');
    raise exception 'E1 ÉCHEC : une commerciale a pu fusionner';
  exception
    when insufficient_privilege then raise exception 'E1 ÉCHEC : 42501 (droits) : %', sqlerrm;
    when sqlstate 'P0001' then
      if sqlerrm !~ 'réservée à un admin' then raise exception 'E1 ÉCHEC : refus inattendu : %', sqlerrm; end if;
      raise notice 'E1 OK (commerciale) : %', sqlerrm;
  end;
end $$;

-- E2. ADMIN par l'appli (Nicolas, authenticated) : la fusion recolle le profil sur la fiche gardée.
select set_config('request.jwt.claims', '{"sub":"d61df9f5-dd0a-4d24-819f-186c89df52b1","role":"authenticated"}', true);
select set_config('db68.res', public.fusionner_contacts(current_setting('db68.garde')::bigint, current_setting('db68.doublon')::bigint, 'app', 'essai db/68')::text, true);
reset role;
do $$
declare v_res jsonb := current_setting('db68.res')::jsonb; v_c int; v_arch bigint;
begin
  select crm_contact_id into v_c from jules.profils_mission where id = current_setting('db68.profil')::uuid;
  if v_c is null then raise exception 'E2 ÉCHEC : profil détaché (crm_contact_id vide) : le défaut est toujours là'; end if;
  if v_c <> current_setting('db68.garde')::int then raise exception 'E2 ÉCHEC : profil sur % au lieu de la fiche gardée', v_c; end if;
  if coalesce((v_res -> 'deplaces' ->> 'jules.profils_mission')::int, 0) <> 1 then
    raise exception 'E2 ÉCHEC : le résultat ne compte pas le profil déplacé : %', v_res -> 'deplaces';
  end if;
  if exists (select 1 from public.contacts where id = current_setting('db68.doublon')::int) then raise exception 'E2 ÉCHEC : doublon pas en corbeille'; end if;
  v_arch := (v_res ->> 'archive_id')::bigint;
  if not exists (select 1 from public.corbeille where id = v_arch and liens -> 'fusion' -> 'deplaces' -> 'jules.profils_mission' @> to_jsonb(current_setting('db68.profil')))
     or not exists (select 1 from public.corbeille where id = v_arch and jsonb_array_length(liens -> 'fusion' -> 'photo' -> 'doublon' -> 'profils_mission') = 1) then
    raise exception 'E2 ÉCHEC : archive % sans trace du profil (deplaces/photo)', v_arch;
  end if;
  if not exists (select 1 from public.historique_actions where id = (v_res ->> 'trace_id')::int and details ~ 'profil\(s\) de dossier Jules') then
    raise exception 'E2 ÉCHEC : la note de fusion ne mentionne pas le profil';
  end if;
  perform set_config('db68.arch', v_arch::text, true);
  raise notice 'E2 OK (admin appli) : profil recollé sur %, archive %, déplacés %', v_c, v_arch, v_res -> 'deplaces';
end $$;

-- E3. Défaire la fusion (restaurer_fiche, admin par l'appli) : le profil revient au doublon.
set local role authenticated;
select set_config('db68.rest', public.restaurer_fiche(current_setting('db68.arch')::bigint, 'app')::text, true);
reset role;
do $$
declare v_c int;
begin
  select crm_contact_id into v_c from jules.profils_mission where id = current_setting('db68.profil')::uuid;
  if v_c is distinct from current_setting('db68.doublon')::int then raise exception 'E3 ÉCHEC : après restauration, profil sur %', v_c; end if;
  raise notice 'E3 OK (restauration) : profil rendu au doublon % ; %', v_c, current_setting('db68.rest');
end $$;

-- E4. Clé service avec origine « jules » (chemin de la carte « Fusionner les deux fiches » via le MCP) + rejouée :
--     la 2e fusion de la même paire est refusée proprement (doublon introuvable), le profil reste sur la fiche gardée.
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('db68.res2', public.fusionner_contacts(current_setting('db68.garde')::bigint, current_setting('db68.doublon')::bigint, 'jules', 'essai db/68 carte')::text, true);
do $$
begin
  perform public.fusionner_contacts(current_setting('db68.garde')::bigint, current_setting('db68.doublon')::bigint, 'jules', 'essai db/68 rejeu');
  raise exception 'E4 ÉCHEC : la même fusion a pu être rejouée';
exception when sqlstate 'P0001' then
  if sqlerrm !~ 'introuvable' then raise exception 'E4 ÉCHEC : refus inattendu : %', sqlerrm; end if;
end $$;
reset role;
do $$
declare v_c int;
begin
  select crm_contact_id into v_c from jules.profils_mission where id = current_setting('db68.profil')::uuid;
  if v_c is distinct from current_setting('db68.garde')::int then raise exception 'E4 ÉCHEC : profil sur % après la fusion par la clé service', v_c; end if;
  raise notice 'E4 OK (clé service, origine jules) : profil recollé sur %, rejeu refusé', v_c;
end $$;

-- V2. Orphelins (même requête que D3 du diagnostic ; attendu inchangé : taches 39, besoins_statuts 6, le reste 0).
select 'jules.profils_mission.crm_contact_id' as colonne, count(*) as orphelins from jules.profils_mission p
 where crm_contact_id is not null and not exists (select 1 from public.contacts c where c.id = p.crm_contact_id);

rollback;
