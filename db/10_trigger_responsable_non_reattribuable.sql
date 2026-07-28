-- ══════════════════════════════════════════════════════════════════════
-- 10 — Verrouiller le changement de `responsable` (trigger, pas RLS)
-- Date : 28/07/2026 · GO Nicolas
--
-- POURQUOI UN TRIGGER ET PAS UNE POLICY : depuis db/09, tout commercial peut modifier
-- n'importe quelle fiche. La règle « on ne se réattribue pas le compte d'un collègue »
-- ne peut PAS être exprimée en RLS : une clause WITH CHECK ne voit que la ligne
-- NOUVELLE, jamais l'ancienne, donc elle est incapable de comparer l'ancien et le
-- nouveau `responsable`. Le garde-fou n'existait donc que dans l'interface (le <select>
-- responsable est réservé à isAdmin) et restait contournable par un appel direct à l'API.
-- Un trigger BEFORE UPDATE, lui, voit OLD et NEW : c'est le seul endroit où la règle
-- peut être réellement tenue.
--
-- RÈGLE POSÉE : seul un admin, ou le responsable actuel de la fiche, peut changer le
-- `responsable`. Un commercial peut donc passer la main sur SES fiches (utile : départ
-- en congés, transfert de compte), mais ne peut pas s'attribuer celles d'un autre.
--
-- Tables concernées : celles qui portent un `responsable` et dont l'UPDATE a été ouvert
-- en db/09 → contacts, comptes, besoins, missions, taches.
-- ══════════════════════════════════════════════════════════════════════


-- ─── La fonction de garde ───
create or replace function public.guard_responsable_change()
returns trigger
language plpgsql
security definer
as $$
begin
  -- Pas de changement de responsable : on laisse passer.
  if new.responsable is not distinct from old.responsable then
    return new;
  end if;

  -- L'admin réattribue librement.
  if get_my_role() = 'admin' then
    return new;
  end if;

  -- Le responsable actuel peut passer la main (congés, transfert de compte).
  if old.responsable = get_my_nom() then
    return new;
  end if;

  raise exception
    'Réattribution refusée : cette fiche appartient à %. Seul son responsable ou un admin peut la réattribuer.',
    coalesce(old.responsable, '(personne)')
    using errcode = 'check_violation';
end;
$$;

comment on function public.guard_responsable_change() is
  'Empêche un commercial de s''attribuer une fiche dont il n''est pas responsable. '
  'Complète db/09 : RLS ne peut pas comparer OLD et NEW, seul un trigger le peut.';


-- ─── Pose du trigger sur les 5 tables ───
drop trigger if exists trg_guard_responsable on public.contacts;
create trigger trg_guard_responsable before update of responsable on public.contacts
  for each row execute function public.guard_responsable_change();

drop trigger if exists trg_guard_responsable on public.comptes;
create trigger trg_guard_responsable before update of responsable on public.comptes
  for each row execute function public.guard_responsable_change();

drop trigger if exists trg_guard_responsable on public.besoins;
create trigger trg_guard_responsable before update of responsable on public.besoins
  for each row execute function public.guard_responsable_change();

drop trigger if exists trg_guard_responsable on public.missions;
create trigger trg_guard_responsable before update of responsable on public.missions
  for each row execute function public.guard_responsable_change();

drop trigger if exists trg_guard_responsable on public.taches;
create trigger trg_guard_responsable before update of responsable on public.taches
  for each row execute function public.guard_responsable_change();


-- ══════════════════════════════════════════════════════════════════════
-- VÉRIFICATION
-- ══════════════════════════════════════════════════════════════════════

-- Les 5 triggers sont-ils en place ?
SELECT c.relname AS table_name, t.tgname AS trigger_name, t.tgenabled AS actif
FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal AND t.tgname = 'trg_guard_responsable'
ORDER BY c.relname;
-- Attendu : 5 lignes (besoins, comptes, contacts, missions, taches), actif = 'O'

-- ⚠️ NE PAS tenter de tester en usurpant une identité ici : l'éditeur SQL s'exécute
-- sans JWT, donc get_my_role() et get_my_nom() renvoient NULL. Le trigger léverait
-- alors une exception sur TOUTE réattribution, y compris légitime — ce qui donnerait
-- l'illusion qu'il fonctionne alors qu'on n'aurait rien prouvé.
--
-- ⚠️ CONSÉQUENCE IMPORTANTE DE CE MÊME POINT : les scripts qui écrivent SANS session
-- utilisateur (MCP CRM avec le compte de Nicolas = admin, donc OK ; mais tout job qui
-- passerait par la service_role ou sans JWT) verront get_my_role() à NULL et seront
-- REFUSÉS s'ils changent un responsable. À surveiller au premier usage réel.
--
-- Le vrai test se fait DEPUIS L'APP :
--   1. Nicolas (admin) réattribue une fiche  → doit passer.
--   2. Un commercial tente de réattribuer la fiche d'un collègue → doit être refusé
--      avec le message « Réattribution refusée : cette fiche appartient à … ».
--      (En pratique l'UI ne propose pas le <select>, donc ce test passe par l'API.)
--   3. Un commercial passe la main sur SA propre fiche → doit passer.


-- ══════════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ══════════════════════════════════════════════════════════════════════
-- drop trigger if exists trg_guard_responsable on public.contacts;
-- drop trigger if exists trg_guard_responsable on public.comptes;
-- drop trigger if exists trg_guard_responsable on public.besoins;
-- drop trigger if exists trg_guard_responsable on public.missions;
-- drop trigger if exists trg_guard_responsable on public.taches;
-- drop function if exists public.guard_responsable_change();
