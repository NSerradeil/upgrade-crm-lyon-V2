-- ══════════════════════════════════════════════════════════════════════
-- 67 — Sessions d'appel : filet contre l'ANCIEN écran « Prosp. » resté ouvert dans un onglet   (20/11/2026)
-- BLOC 2/3 — APPLY (transactionnel, auto-testé, tout ou rien). Prérequis : db/65 (et db/66) en place.
--
-- POURQUOI : le nouvel écran « Prosp. » écrit chaque résultat par la porte enregistrer_resultat_appel, au clic. Un onglet
-- resté sur l'ANCIENNE version de l'appli (pas rechargé après le déploiement, PWA iPhone) écrirait encore, à « Terminer »,
-- l'historique « Appel sortant » et la tâche de relance de chaque personne : en double pour les personnes déjà notées par
-- la porte. Son « Supprimer » et son « Modifier » effaceraient les lignes de session en laissant les écritures de la porte.
--
-- CE QUI CHANGE (seulement pour une requête d'un utilisateur connecté, hors porte ; les fonctions security definer comme
-- la fusion, la corbeille ou la porte, et les suppressions en cascade, ne sont pas concernées) :
--   1. historique_actions, BEFORE INSERT : une ligne « Appel sortant » (ou « Note session ») de l'ancien écran, pour une
--      personne déjà notée par la porte dans CETTE session (reconnue au début « Session : <nom de la session> »), est
--      IGNORÉE (la ligne n'est pas insérée, les autres lignes du même envoi le sont). Pas d'erreur : l'ancien écran
--      continue, rien n'est doublé.
--   2. taches, BEFORE INSERT : une tâche rattachée à une session (session_prospection_id) pour une personne déjà notée par
--      la porte dans cette session est IGNORÉE de la même façon (la porte a déjà posé LA tâche).
--   3. session_prospection_contacts, BEFORE DELETE : supprimer la ligne d'une personne déjà notée par la porte (statut
--      différent de 'none') dans une session EN COURS est refusé (le nouvel écran annule d'abord par la porte).
--   4. sessions_prospection, BEFORE DELETE : supprimer une session EN COURS qui a encore un résultat écrit par la porte est
--      refusé (même raison). Une session terminée se supprime comme avant.
--
-- CE QUI NE BOUGE PAS : la porte, terminer_session_appel, le nouvel écran, la Jules app, le connecteur, les droits.
--
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/67_garde_ancien_ecran_2_apply.sql
-- Retour arrière : db/67_garde_ancien_ecran_rollback.sql
-- ══════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP on
begin;

do $$
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public'
                  and table_name = 'session_prospection_contacts' and column_name = 'geste_at') then
    raise exception 'db/65 absente (colonne geste_at) : arrêt';
  end if;
  if exists (select 1 from pg_proc where proname = 'spc_garde_ancien_ecran') then
    raise exception 'db/67 déjà passée : arrêt';
  end if;
end $$;

-- Une requête « à surveiller » = un utilisateur connecté (rôle authenticated), hors porte. Test écrit EN LIGNE dans chaque
-- trigger (aucune fonction auxiliaire : service_role et les propriétaires de fonctions n'ont besoin d'aucun droit en plus).

-- 1. Historique de l'ancien écran pour une personne déjà notée par la porte : ignoré.
create or replace function public.historique_garde_ancien_ecran()
returns trigger language plpgsql set search_path = public, pg_temp as
$$
begin
  if (current_user = 'authenticated' and coalesce(current_setting('crm.porte_appel', true), '') <> '1')
     and new.type_action in ('Appel sortant', 'Note session')
     and (new.details like 'Session : %' or new.details like '[Correction session : %')
     and exists (select 1 from public.session_prospection_contacts c
                   join public.sessions_prospection s on s.id = c.session_id
                  where c.contact_id = new.id_prospect and c.geste_at is not null and c.statut <> 'none'
                    and s.responsable = new.responsable
                    and (left(new.details, length('Session : ' || s.nom || E'\n')) = 'Session : ' || s.nom || E'\n'
                         or new.details = 'Session : ' || s.nom
                         or left(new.details, length('[Correction session : ' || s.nom || ']')) = '[Correction session : ' || s.nom || ']')) then
    return null;   -- déjà écrit par la porte : on n'ajoute pas de doublon
  end if;
  return new;
end $$;
create trigger trg_historique_garde_ancien_ecran before insert on public.historique_actions
  for each row execute function public.historique_garde_ancien_ecran();

-- 2. Tâche de session de l'ancien écran pour une personne déjà notée par la porte : ignorée.
create or replace function public.taches_garde_ancien_ecran()
returns trigger language plpgsql set search_path = public, pg_temp as
$$
begin
  if (current_user = 'authenticated' and coalesce(current_setting('crm.porte_appel', true), '') <> '1') and new.session_prospection_id is not null and new.contact_id is not null
     and exists (select 1 from public.session_prospection_contacts c
                  where c.session_id = new.session_prospection_id and c.contact_id = new.contact_id
                    and c.geste_at is not null and c.statut <> 'none') then
    return null;
  end if;
  return new;
end $$;
create trigger trg_taches_garde_ancien_ecran before insert on public.taches
  for each row execute function public.taches_garde_ancien_ecran();

-- 3. Ligne notée par la porte dans une session en cours : pas de suppression directe.
create or replace function public.spc_garde_ancien_ecran()
returns trigger language plpgsql set search_path = public, pg_temp as
$$
begin
  if (current_user = 'authenticated' and coalesce(current_setting('crm.porte_appel', true), '') <> '1') and old.geste_at is not null and old.statut <> 'none'
     and exists (select 1 from public.sessions_prospection s where s.id = old.session_id and s.statut = 'active') then
    raise exception 'Résultat déjà enregistré : annule-le dans la session avant de retirer la personne (recharge la page si l''écran est ancien).'
      using errcode = '42501';
  end if;
  return old;
end $$;
create trigger trg_spc_garde_ancien_ecran before delete on public.session_prospection_contacts
  for each row execute function public.spc_garde_ancien_ecran();

-- 4. Session en cours avec un résultat écrit par la porte : pas de suppression directe.
create or replace function public.sessions_garde_ancien_ecran()
returns trigger language plpgsql set search_path = public, pg_temp as
$$
begin
  if (current_user = 'authenticated' and coalesce(current_setting('crm.porte_appel', true), '') <> '1') and old.statut = 'active'
     and exists (select 1 from public.session_prospection_contacts c
                  where c.session_id = old.id and c.geste_at is not null and c.statut <> 'none') then
    raise exception 'Session avec des résultats enregistrés : recharge la page puis supprime-la depuis le nouvel écran.'
      using errcode = '42501';
  end if;
  return old;
end $$;
create trigger trg_sessions_garde_ancien_ecran before delete on public.sessions_prospection
  for each row execute function public.sessions_garde_ancien_ecran();

-- 5. Statut et compteurs d'une session tenue par la porte : seulement par la porte ou terminer_session_appel (l'ancien
--    « Terminer » / « Enregistrer les modifications » ne les écrase plus ; le renommage reste libre).
create or replace function public.sessions_garde_compteurs()
returns trigger language plpgsql set search_path = public, pg_temp as
$$
begin
  if (current_user = 'authenticated' and coalesce(current_setting('crm.porte_appel', true), '') <> '1')
     and (new.statut, new.nb_contacts, new.nb_interesses, new.nb_relances, new.nb_injoignables)
         is distinct from (old.statut, old.nb_contacts, old.nb_interesses, old.nb_relances, old.nb_injoignables)
     and (old.origine = 'jules' or exists (select 1 from public.session_prospection_contacts c
                                           where c.session_id = old.id and c.geste_at is not null)) then
    raise exception 'Session tenue par la porte d''appel : recharge la page (écran ancien).' using errcode = '42501';
  end if;
  return new;
end $$;
create trigger trg_sessions_garde_compteurs before update on public.sessions_prospection
  for each row execute function public.sessions_garde_compteurs();


-- ─── Tests intégrés (savepoint annulé ; toute erreur annule TOUT) ───
savepoint tests_67;
do $$
declare
  u_a uuid; n_a text; v_s uuid; v_s2 uuid; v_c int; v_c2 int; v_n int; v_ok boolean;
begin
  select id, nom into u_a, n_a from public.profiles where role = 'commercial' order by nom limit 1;
  insert into public.contacts (prenom, nom, statut, responsable, etape_prospect) values ('Zz', 'Test67a', 'Prospect', n_a, 'À contacter') returning id into v_c;
  insert into public.contacts (prenom, nom, statut, responsable, etape_prospect) values ('Zz', 'Test67b', 'Prospect', n_a, 'À contacter') returning id into v_c2;
  insert into public.sessions_prospection (nom, responsable, statut) values ('T67 test', n_a, 'active') returning id into v_s;
  insert into public.session_prospection_contacts (session_id, contact_id) values (v_s, v_c), (v_s, v_c2);
  insert into public.sessions_prospection (nom, responsable, statut) values ('T67 vide', n_a, 'active') returning id into v_s2;
  insert into public.session_prospection_contacts (session_id, contact_id) values (v_s2, v_c);

  perform set_config('request.jwt.claims', json_build_object('sub', u_a, 'role', 'authenticated')::text, true);
  perform public.enregistrer_resultat_appel(v_s, v_c, 'called', null, 'note', 'rappel', now() + interval '2 days', false, null, null);
  perform set_config('crm.porte_appel', '', true);   -- (dans un même test, le drapeau de la porte resterait posé)

  execute 'set local role authenticated';
  -- T67.1 : l'ancien « Terminer » (historique en lot) : la ligne de la personne déjà notée est ignorée, l'autre passe
  insert into public.historique_actions (id_prospect, date, type_action, details, responsable)
  values (v_c, current_date, 'Appel sortant', 'Session : T67 test' || E'\n' || 'Résultat : Appelé', n_a),
         (v_c2, current_date, 'Appel sortant', 'Session : T67 test' || E'\n' || 'Résultat : Appelé', n_a);
  select count(*) into v_n from public.historique_actions where id_prospect = v_c and type_action = 'Appel sortant';
  if v_n <> 1 then raise exception 'T67.1 : % lignes pour la personne notée par la porte', v_n; end if;
  select count(*) into v_n from public.historique_actions where id_prospect = v_c2 and type_action = 'Appel sortant';
  if v_n <> 1 then raise exception 'T67.1 : la personne non notée n''a pas son historique (%)', v_n; end if;
  -- T67.2 : un historique hors session (autre texte) n'est pas touché
  insert into public.historique_actions (id_prospect, date, type_action, details, responsable) values (v_c, current_date, 'Appel sortant', 'Appel libre', n_a);
  select count(*) into v_n from public.historique_actions where id_prospect = v_c and type_action = 'Appel sortant';
  if v_n <> 2 then raise exception 'T67.2 : appel hors session bloqué'; end if;
  -- T67.3 : la tâche de l'ancien « Terminer » est ignorée pour la personne notée, gardée pour l'autre
  insert into public.taches (id, titre, statut, due_date, contact_id, session_prospection_id, responsable)
  values ('tw_relance_t67_a', 'Relance', 'a_faire', now() + interval '1 day', v_c, v_s, n_a),
         ('tw_relance_t67_b', 'Relance', 'a_faire', now() + interval '1 day', v_c2, v_s, n_a);
  if exists (select 1 from public.taches where id = 'tw_relance_t67_a') then raise exception 'T67.3 : tâche doublée'; end if;
  if not exists (select 1 from public.taches where id = 'tw_relance_t67_b') then raise exception 'T67.3 : tâche légitime perdue'; end if;
  -- T67.4 : supprimer la ligne notée d'une session en cours : refusé ; la ligne 'none' : accepté
  v_ok := false;
  begin delete from public.session_prospection_contacts where session_id = v_s and contact_id = v_c; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'T67.4 : suppression de ligne notée non refusée'; end if;
  delete from public.session_prospection_contacts where session_id = v_s and contact_id = v_c2;
  -- T67.5 : supprimer la session en cours : refusé ; une session sans résultat porte : accepté
  v_ok := false;
  begin delete from public.sessions_prospection where id = v_s; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'T67.5 : suppression de session non refusée'; end if;
  delete from public.session_prospection_contacts where session_id = v_s2;
  delete from public.sessions_prospection where id = v_s2;
  -- T67.8 : l'ancien « Terminer » ne passe plus la session à done ni n'écrase ses compteurs ; renommer reste possible
  v_ok := false;
  begin update public.sessions_prospection set statut = 'done', nb_contacts = 9 where id = v_s; exception when insufficient_privilege then v_ok := true; end;
  if not v_ok then raise exception 'T67.8 : fin de session hors porte non refusée'; end if;
  update public.sessions_prospection set nom = 'T67 test' where id = v_s;
  -- T67.6 : le nouvel écran : annuler par la porte, puis retirer / supprimer : accepté
  perform public.enregistrer_resultat_appel(v_s, v_c, 'none');
  perform set_config('crm.porte_appel', '', true);   -- (dans un même test, le drapeau de la porte resterait posé)
  delete from public.session_prospection_contacts where session_id = v_s;
  delete from public.sessions_prospection where id = v_s;
  -- T67.7 : une session terminée se supprime comme avant (les écritures restent)
  execute 'reset role';
  insert into public.sessions_prospection (nom, responsable, statut) values ('T67 fin', n_a, 'active') returning id into v_s;
  insert into public.session_prospection_contacts (session_id, contact_id) values (v_s, v_c);
  perform public.enregistrer_resultat_appel(v_s, v_c, 'unreachable');
  perform public.terminer_session_appel(v_s);
  perform set_config('crm.porte_appel', '', true);   -- (dans un même test, le drapeau de la porte resterait posé)
  execute 'set local role authenticated';
  delete from public.session_prospection_contacts where session_id = v_s;
  delete from public.sessions_prospection where id = v_s;
  execute 'reset role';
  raise notice 'Tests T67.1 à T67.8 : OK';
end $$;
rollback to savepoint tests_67;

notify pgrst, 'reload schema';
commit;
