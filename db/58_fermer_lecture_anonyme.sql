-- 58_fermer_lecture_anonyme.sql — plus aucune lecture sans être connecté (08/10/2026)
--
-- Faille constatée le 08/10 après la bascule vers le Supabase du Mac mini : avec la seule clé
-- publique (celle de config.json, publiée sur GitHub Pages), l'API renvoyait des contacts
-- (nom, téléphone, salaire) sans aucune connexion. Cause : des droits SELECT accordés au rôle
-- `anon` + des policies de lecture `qual = true` ouvertes à `public` (donc à anon aussi).
--
-- Qui a besoin d'anon ? Personne pour lire des tables : le CRM (index.html), l'appli Jules,
-- le MCP et les scripts de Jules se connectent tous (password grant) AVANT toute lecture.
-- La clé publique ne sert qu'à appeler /auth/v1/token. On retire donc à anon TOUT droit sur
-- les tables, vues et séquences des schémas applicatifs, et pour les objets futurs aussi.
-- Les fonctions (get_my_role…) ne sont pas touchées : la liste des SECURITY DEFINER
-- exécutables par anon est affichée en bas pour revue.
--
-- À lancer sur le Mac mini (superuser) :
--   ssh jules@100.123.217.38 '/opt/homebrew/bin/docker exec -i supabase-db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1' < db/58_fermer_lecture_anonyme.sql
-- Retour arrière : grant select on all tables in schema public to anon; (déconseillé)

begin;

do $$
declare s text;
begin
  foreach s in array array['public','jules'] loop
    if exists (select 1 from pg_namespace where nspname = s) then
      execute format('revoke all on all tables in schema %I from anon', s);
      execute format('revoke all on all sequences in schema %I from anon', s);
      execute format('alter default privileges in schema %I revoke all on tables from anon', s);
      execute format('alter default privileges in schema %I revoke all on sequences from anon', s);
      execute format('alter default privileges for role postgres in schema %I revoke all on tables from anon', s);
      execute format('alter default privileges for role postgres in schema %I revoke all on sequences from anon', s);
    end if;
  end loop;
end $$;

commit;

-- ── VÉRIFICATION 1 : doit renvoyer 0 ligne ─────────────────────────────────────────────
select table_schema, table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'anon' and table_schema in ('public','jules')
order by 1, 2;

-- ── VÉRIFICATION 2 (revue) : fonctions SECURITY DEFINER encore appelables sans connexion ──
select n.nspname as schema, p.proname as fonction
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname in ('public','jules') and p.prosecdef
  and has_function_privilege('anon', p.oid, 'execute')
order by 1, 2;
