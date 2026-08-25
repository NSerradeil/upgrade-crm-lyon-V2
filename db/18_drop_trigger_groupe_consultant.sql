-- ══════════════════════════════════════════════════════════════════════
-- 18 — HOTFIX post-DROP (db/17) : supprimer le trigger obsolète qui écrivait
--      contacts.groupe depuis les missions (maintenance « société consultant »).
-- Date : 2026-08-25 · Spec : SPECS_CRM/SPEC_compte_id_besoins_contacts.md
--
-- SYMPTÔME : après le DROP de contacts.groupe, TOUTE écriture de mission échoue
--   avec « column "groupe" of relation "contacts" does not exist » (SQLSTATE 42703),
--   car un trigger sur public.missions met à jour contacts.groupe (colonne disparue).
-- Le trigger est désormais INUTILE : la société d'un consultant est dérivée à la volée
--   (app : client de sa mission active ; MCP : employeur). On le supprime + sa fonction.
--
-- Le nom du trigger/fonction n'étant pas versionné (créé jadis directement en base),
-- on le retrouve dynamiquement : tout trigger sur missions dont la fonction cite « groupe ».
-- ══════════════════════════════════════════════════════════════════════

DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT t.tgname, p.oid AS foid, p.proname
    FROM pg_trigger t
    JOIN pg_class c   ON c.oid = t.tgrelid
    JOIN pg_proc  p   ON p.oid = t.tgfoid
    WHERE c.relname = 'missions'
      AND NOT t.tgisinternal
      AND pg_get_functiondef(p.oid) ILIKE '%groupe%'
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.missions', r.tgname);
    RAISE NOTICE 'Trigger supprimé : % (fonction %)', r.tgname, r.proname;
    BEGIN
      EXECUTE format('DROP FUNCTION IF EXISTS %s', r.foid::regprocedure);
      RAISE NOTICE 'Fonction supprimée : %', r.proname;
    EXCEPTION WHEN others THEN
      RAISE NOTICE 'Fonction % conservée (encore utilisée ?) : %', r.proname, SQLERRM;
    END;
  END LOOP;
END $$;

-- VÉRIF : plus aucun trigger sur missions ne doit citer « groupe ».
SELECT t.tgname AS trigger_restant, p.proname AS fonction
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_proc  p ON p.oid = t.tgfoid
WHERE c.relname = 'missions' AND NOT t.tgisinternal
  AND pg_get_functiondef(p.oid) ILIKE '%groupe%';
-- Attendu : 0 ligne.
