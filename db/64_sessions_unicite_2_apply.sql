-- ══════════════════════════════════════════════════════════════════════
-- 64 — Sessions d'appel : une seule ligne par (session, contact)   (20/11/2026, tranche T0)
-- BLOC 2/3 — APPLY (transactionnel, auto-testé, tout ou rien)
--
-- CE QUI CHANGE :
--   1. Sauvegarde complète AVANT : _spc_bak_20261120 (session_prospection_contacts),
--      _sessions_prospection_bak_20261120, _fn_bak_20261120 (définition de fusionner_contacts).
--      RLS activée sans policy : lisibles par le superuser seulement.
--   2. Dédoublonnage : pour chaque couple (session, contact), on garde la ligne qui porte un résultat
--      (statut <> 'none'), sinon la plus récente. Aucune ligne avec résultat n'est supprimée (garde-fou).
--   3. Contrainte d'unicité spc_session_contact_uniq (session_id, contact_id).
--   4. Trigger trg_spc_insertion_remplace (BEFORE INSERT) : un INSERT sur un couple déjà présent ne crée plus
--      de ligne. Avec un résultat, il REMPLACE le contenu de la ligne existante ; avec 'none', il ne fait rien.
--      Utilité : les onglets du CRM restés ouverts avec l'ancien code (upsert sans clé), et le connecteur MCP
--      qui ajoute un contact déjà présent, continuent de marcher sans erreur et sans doublon.
--   5. fusionner_contacts (db/63) : la ligne de session du doublon n'est déplacée que si la fiche gardée n'est
--      pas déjà dans la même session (sinon elle part en corbeille avec le doublon, comme les candidatures).
--      Sans ça, la contrainte ferait échouer la fusion de deux fiches présentes dans la même session.
--
-- CE QUI NE BOUGE PAS : les compteurs nb_* des sessions, l'historique, les tâches, les contacts, les droits.
--
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/64_sessions_unicite_2_apply.sql
-- Retour arrière : db/64_sessions_unicite_rollback.sql
-- ══════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP on
begin;

-- Personne n'écrit dans la table pendant les quelques millisecondes du passage.
lock table public.session_prospection_contacts in share row exclusive mode;

-- ─── 0. Garde d'entrée ───
do $$
begin
  if exists (select 1 from pg_constraint where conrelid = 'public.session_prospection_contacts'::regclass and contype = 'u') then
    raise exception 'Une contrainte d''unicité existe déjà sur session_prospection_contacts : arrêt';
  end if;
  if to_regclass('public._spc_bak_20261120') is not null then
    raise exception 'Sauvegarde _spc_bak_20261120 déjà présente : arrêt (passage déjà fait ?)';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'public.fusionner_contacts(bigint,bigint,text,text)'::regprocedure)
     <> 'b9baabcdc516526e2d1488bf5bcce84e' then
    raise exception 'fusionner_contacts a changé depuis db/63 : arrêt, relire avant d''appliquer';
  end if;
  if exists (select 1 from public.session_prospection_contacts group by session_id, contact_id
              having count(*) filter (where statut <> 'none') > 1) then
    raise exception 'Un couple (session, contact) porte deux résultats : arrêt, cas non prévu';
  end if;
end $$;

-- ─── 1. Sauvegardes ───
create table public._spc_bak_20261120 as select * from public.session_prospection_contacts;
create table public._sessions_prospection_bak_20261120 as select * from public.sessions_prospection;
create table public._fn_bak_20261120 as
  select 'public.fusionner_contacts(bigint,bigint,text,text)'::text as fonction,
         pg_get_functiondef('public.fusionner_contacts(bigint,bigint,text,text)'::regprocedure) as definition,
         now() as sauvegarde_le;
alter table public._spc_bak_20261120 enable row level security;
alter table public._sessions_prospection_bak_20261120 enable row level security;
alter table public._fn_bak_20261120 enable row level security;
revoke all on public._spc_bak_20261120, public._sessions_prospection_bak_20261120, public._fn_bak_20261120 from anon, authenticated;

-- Photo des chiffres AVANT (par session) pour la vérification interne.
create temp table _avant on commit drop as
select s.id, s.statut, s.nb_contacts, s.nb_interesses, s.nb_relances, s.nb_injoignables,
       count(distinct (c.contact_id)) as couples,
       count(*) filter (where c.statut <> 'none') as res,
       count(*) filter (where c.statut = 'called') as a, count(*) filter (where c.statut = 'interested') as i,
       count(*) filter (where c.statut = 'unreachable') as n, count(*) filter (where c.statut = 'not_interested') as p
  from public.sessions_prospection s left join public.session_prospection_contacts c on c.session_id = s.id
 group by s.id;

-- ─── 2. Dédoublonnage ───
create temp table _a_supprimer on commit drop as
select id, statut from (
  select c.id, c.statut, row_number() over (partition by c.session_id, c.contact_id
                                            order by (c.statut <> 'none') desc, c.created_at desc, c.id desc) rn
    from public.session_prospection_contacts c) x
 where rn > 1;

do $$
declare v_attendu int; v_n int;
begin
  select count(*) - count(distinct (session_id, contact_id)) into v_attendu from public.session_prospection_contacts;
  if exists (select 1 from _a_supprimer where statut <> 'none') then
    raise exception 'Le dédoublonnage supprimerait une ligne avec résultat : arrêt';
  end if;
  delete from public.session_prospection_contacts where id in (select id from _a_supprimer);
  get diagnostics v_n = row_count;
  if v_n <> v_attendu then
    raise exception 'Lignes supprimées % <> attendues %', v_n, v_attendu;
  end if;
  raise notice 'Dédoublonnage : % lignes supprimées (toutes en statut none)', v_n;
end $$;

-- ─── 3. Contrainte d'unicité ───
alter table public.session_prospection_contacts
  add constraint spc_session_contact_uniq unique (session_id, contact_id);

-- ─── 4. Un INSERT sur un couple existant remplace au lieu d'ajouter ───
create or replace function public.spc_insertion_remplace()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  if new.session_id is null or new.contact_id is null then
    return new;
  end if;
  if not exists (select 1 from public.session_prospection_contacts
                  where session_id = new.session_id and contact_id = new.contact_id) then
    return new;
  end if;
  -- Le couple existe : un résultat remplace le contenu de la ligne, un 'none' ne fait rien.
  if coalesce(new.statut, 'none') <> 'none' then
    update public.session_prospection_contacts
       set statut = new.statut, notes = new.notes, want_relance = new.want_relance,
           relance_date = new.relance_date, relance_note = new.relance_note,
           tel_saisi = new.tel_saisi, email_saisi = new.email_saisi, linkedin_saisi = new.linkedin_saisi
     where session_id = new.session_id and contact_id = new.contact_id;
  end if;
  return null;
end $$;

-- Sur un INSERT ... ON CONFLICT (session_id, contact_id) DO UPDATE (le nouveau code du CRM), PostgreSQL déclenche
-- aussi ce BEFORE INSERT : le trigger fait lui-même la mise à jour, ce qui revient au même qu'un upsert.
create trigger trg_spc_insertion_remplace
  before insert on public.session_prospection_contacts
  for each row execute function public.spc_insertion_remplace();

-- ─── 5. fusionner_contacts : pas de doublon de session à la fusion ───
do $$
declare
  v_def text := pg_get_functiondef('public.fusionner_contacts(bigint,bigint,text,text)'::regprocedure);
  v_old text := 'with m as (update public.session_prospection_contacts set contact_id = p_garde where contact_id = p_doublon returning id)';
  v_new text := 'with m as (update public.session_prospection_contacts x set contact_id = p_garde where x.contact_id = p_doublon '
             || 'and not exists (select 1 from public.session_prospection_contacts y where y.session_id = x.session_id and y.contact_id = p_garde) '
             || 'returning x.id)';
begin
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then
    raise exception 'fusionner_contacts : le passage à corriger n''apparaît pas exactement une fois';
  end if;
  execute replace(v_def, v_old, v_new);
end $$;

-- ─── 6. Tests intégrés (annulés par savepoint ; toute erreur annule TOUT) ───
savepoint tests;
do $$
declare
  v_s uuid; v_c int; v_n int; v_st text; v_note text; v_ok boolean;
begin
  -- Un couple existant, pris dans une session terminée.
  select session_id, contact_id into v_s, v_c from public.session_prospection_contacts where statut <> 'none' limit 1;
  select count(*) into v_n from public.session_prospection_contacts;

  -- T1 : INSERT 'none' sur le couple existant -> rien ne change
  insert into public.session_prospection_contacts (session_id, contact_id, statut, notes) values (v_s, v_c, 'none', 'T1');
  if (select count(*) from public.session_prospection_contacts) <> v_n then raise exception 'T1 : ligne ajoutée'; end if;
  if exists (select 1 from public.session_prospection_contacts where session_id = v_s and contact_id = v_c and (statut = 'none' or notes = 'T1')) then
    raise exception 'T1 : la ligne existante a été écrasée par un none';
  end if;

  -- T2 : INSERT avec résultat (ancien upsert du CRM) -> remplace, pas de nouvelle ligne
  insert into public.session_prospection_contacts (session_id, contact_id, statut, notes) values (v_s, v_c, 'called', 'T2');
  select statut, notes into v_st, v_note from public.session_prospection_contacts where session_id = v_s and contact_id = v_c;
  if (select count(*) from public.session_prospection_contacts) <> v_n or v_st <> 'called' or v_note <> 'T2' then
    raise exception 'T2 : remplacement KO (% %)', v_st, v_note;
  end if;

  -- T3 : upsert ON CONFLICT (session_id, contact_id) (nouveau CRM) -> remplace
  insert into public.session_prospection_contacts (session_id, contact_id, statut, notes) values (v_s, v_c, 'interested', 'T3')
    on conflict (session_id, contact_id) do update set statut = excluded.statut, notes = excluded.notes;
  select statut, notes into v_st, v_note from public.session_prospection_contacts where session_id = v_s and contact_id = v_c;
  if (select count(*) from public.session_prospection_contacts) <> v_n or v_st <> 'interested' or v_note <> 'T3' then
    raise exception 'T3 : upsert KO';
  end if;

  -- T4 : INSERT d'un couple nouveau -> ligne créée
  insert into public.session_prospection_contacts (session_id, contact_id, statut)
    select v_s, min(id), 'none' from public.contacts
     where id not in (select contact_id from public.session_prospection_contacts where session_id = v_s and contact_id is not null);
  if (select count(*) from public.session_prospection_contacts) <> v_n + 1 then raise exception 'T4 : nouvelle ligne non créée'; end if;

  -- T5 : la contrainte tient même sans le trigger
  alter table public.session_prospection_contacts disable trigger trg_spc_insertion_remplace;
  v_ok := false;
  begin
    insert into public.session_prospection_contacts (session_id, contact_id, statut) values (v_s, v_c, 'none');
  exception when unique_violation then v_ok := true;
  end;
  alter table public.session_prospection_contacts enable trigger trg_spc_insertion_remplace;
  if not v_ok then raise exception 'T5 : la contrainte d''unicité n''a pas refusé le doublon'; end if;

  -- T6 : fusionner_contacts compilée avec le correctif
  if position('y.session_id = x.session_id' in (select prosrc from pg_proc where oid = 'public.fusionner_contacts(bigint,bigint,text,text)'::regprocedure)) = 0 then
    raise exception 'T6 : correctif de fusionner_contacts absent';
  end if;
  raise notice 'Tests T1 à T6 : OK';
end $$;
rollback to savepoint tests;

-- ─── 7. Vérification finale : rien n'a bougé sauf les doublons ───
do $$
declare v_diff int;
begin
  if exists (select 1 from public.session_prospection_contacts group by session_id, contact_id having count(*) > 1) then
    raise exception 'Il reste des doublons';
  end if;
  select count(*) into v_diff
    from _avant a
    join (select s.id, s.nb_contacts, s.nb_interesses, s.nb_relances, s.nb_injoignables,
                 count(distinct c.contact_id) couples, count(*) filter (where c.statut <> 'none') res,
                 count(*) filter (where c.statut = 'called') a, count(*) filter (where c.statut = 'interested') i,
                 count(*) filter (where c.statut = 'unreachable') n, count(*) filter (where c.statut = 'not_interested') p
            from public.sessions_prospection s left join public.session_prospection_contacts c on c.session_id = s.id
           group by s.id) b using (id)
   where (a.nb_contacts, a.nb_interesses, a.nb_relances, a.nb_injoignables, a.couples, a.res, a.a, a.i, a.n, a.p)
         is distinct from (b.nb_contacts, b.nb_interesses, b.nb_relances, b.nb_injoignables, b.couples, b.res, b.a, b.i, b.n, b.p);
  if v_diff <> 0 then
    raise exception '% session(s) ont changé de compteurs ou de résultats : annulation', v_diff;
  end if;
  if (select count(*) from public.session_prospection_contacts) + (select count(*) from _a_supprimer)
     <> (select count(*) from public._spc_bak_20261120) then
    raise exception 'Comptage lignes incohérent avec la sauvegarde';
  end if;
  raise notice 'Vérification finale : OK (% sessions, compteurs et résultats identiques)', (select count(*) from _avant);
end $$;

commit;
