-- 57_verrou_profils_roles.sql — un utilisateur ne peut plus changer lui-même ses droits (06/10/2026)
--
-- Faille trouvée à la relecture de l'appli Jules : la policy `write_profiles` (ALL, id = auth.uid())
-- laisse chaque utilisateur modifier SA ligne de profiles, y compris `role` → n'importe qui pouvait
-- se passer `admin`. Même risque avec `nom` (les policies d'écriture comparent `responsable` au nom :
-- prendre le nom d'une collègue donnerait la main sur ses fiches) et `agence` (périmètre).
-- L'appli CRM ne modifie que `preferences` (index.html), donc rien ne casse.
--
-- Règle : depuis l'API (rôle `authenticated` ou `anon`), interdiction d'insérer un profil ou de
-- modifier role / nom / agence. L'éditeur SQL (postgres), le service_role (Jules, MCP) et
-- supabase_admin gardent la main pour administrer les profils.
-- À coller dans Supabase > SQL Editor, puis lancer la requête de VÉRIFICATION en bas.

create or replace function public.profiles_verrou_droits()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      raise exception 'creation de profil reservee a l''administration';
    end if;
    if new.role is distinct from old.role
       or new.nom is distinct from old.nom
       or new.agence is distinct from old.agence then
      raise exception 'role, nom et agence ne se modifient que par l''administration';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_verrou_droits on public.profiles;
create trigger profiles_verrou_droits
  before insert or update on public.profiles
  for each row execute function public.profiles_verrou_droits();

-- VÉRIFICATION (doit rendre une ligne : profiles_verrou_droits | O) :
-- select tgname, tgenabled from pg_trigger where tgrelid = 'public.profiles'::regclass and not tgisinternal;
