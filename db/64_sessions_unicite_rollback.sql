-- ══════════════════════════════════════════════════════════════════════
-- 64 — RETOUR ARRIÈRE de db/64_sessions_unicite_2_apply.sql
-- Remet : les lignes supprimées (depuis _spc_bak_20261120), l'absence de contrainte et de trigger,
-- et la définition d'origine de fusionner_contacts (depuis _fn_bak_20261120).
-- Les lignes modifiées depuis le passage (résultats notés après) sont gardées telles quelles : on ne remet
-- que les lignes qui avaient été supprimées, si leur session et leur contact existent encore.
-- Les sauvegardes sont conservées (à supprimer à la main plus tard).
--
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/64_sessions_unicite_rollback.sql
-- ATTENTION : si db/65 (porte d'écriture T1) est en place, passer d'abord db/65_..._rollback.sql.
-- ══════════════════════════════════════════════════════════════════════

\set ON_ERROR_STOP on
begin;
lock table public.session_prospection_contacts in share row exclusive mode;

do $$
begin
  if to_regclass('public._spc_bak_20261120') is null or to_regclass('public._fn_bak_20261120') is null then
    raise exception 'Sauvegardes absentes : retour arrière impossible';
  end if;
  if exists (select 1 from pg_proc where proname = 'enregistrer_resultat_appel') then
    raise exception 'La porte d''écriture T1 (db/65) est en place : passer d''abord son retour arrière';
  end if;
end $$;

drop trigger if exists trg_spc_insertion_remplace on public.session_prospection_contacts;
drop function if exists public.spc_insertion_remplace();
alter table public.session_prospection_contacts drop constraint if exists spc_session_contact_uniq;

-- Lignes supprimées par le passage : remises si leur session et leur contact existent encore.
do $$
declare v_n int; v_manquantes int;
begin
  insert into public.session_prospection_contacts
  select b.* from public._spc_bak_20261120 b
   where not exists (select 1 from public.session_prospection_contacts c where c.id = b.id)
     and exists (select 1 from public.sessions_prospection s where s.id = b.session_id)
     and exists (select 1 from public.contacts k where k.id = b.contact_id);
  get diagnostics v_n = row_count;
  select count(*) into v_manquantes from public._spc_bak_20261120 b
   where not exists (select 1 from public.session_prospection_contacts c where c.id = b.id);
  raise notice 'Retour arrière : % lignes remises, % lignes de la sauvegarde non remises (session ou contact disparu depuis)', v_n, v_manquantes;
end $$;

-- Définition d'origine de fusionner_contacts.
do $$
begin
  execute (select definition from public._fn_bak_20261120 where fonction = 'public.fusionner_contacts(bigint,bigint,text,text)');
  if (select md5(prosrc) from pg_proc where oid = 'public.fusionner_contacts(bigint,bigint,text,text)'::regprocedure)
     <> 'b9baabcdc516526e2d1488bf5bcce84e' then
    raise exception 'fusionner_contacts non restaurée à l''identique';
  end if;
  raise notice 'fusionner_contacts restaurée (md5 d''origine)';
end $$;

commit;
