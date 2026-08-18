-- ══════════════════════════════════════════════════════════════════════
-- VÉRIF LIVE — droits écriture inter-agences (chantier clos côté code le 18/08)
-- À coller dans l'éditeur SQL Supabase. Lecture seule, ne modifie rien.
-- But : confirmer que db/09→12 sont réellement appliquées en base (le repo ne le prouve pas).
-- ══════════════════════════════════════════════════════════════════════

-- 1) Les policies écriture/lecture sur les tables du chantier.
--    Attendu : UPDATE ouvert (admin OU commercial), DELETE réservé (admin OU responsable),
--    SELECT ouvert (true) là où db/08-12 l'ont élargi.
SELECT tablename, cmd, policyname, qual AS condition_lecture, with_check AS condition_ecriture
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('contacts','comptes','besoins','missions','taches',
                    'besoin_candidats','mission_periods',
                    'historique_actions','historique_missions')
ORDER BY tablename, cmd, policyname;

-- 2) Le trigger anti-réattribution du responsable (db/10) est-il posé et actif ?
--    Attendu : une ligne par table protégée, tgenabled = 'O' (activé).
SELECT c.relname AS table, t.tgname AS trigger, t.tgenabled AS actif
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE NOT t.tgisinternal
  AND t.tgname ILIKE '%responsable%'
ORDER BY c.relname;

-- 3) Les 3 fonctions d'aide renvoient bien ce qu'on croit.
SELECT proname, pg_get_functiondef(oid) AS definition
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('get_my_role','get_my_agence','get_my_nom');

-- Lecture des résultats :
--   • UPDATE avec with_check du type "get_my_role() IN ('admin','commercial')" (ou équivalent) = OK.
--   • DELETE avec qual "get_my_role()='admin' OR responsable=get_my_nom()" = OK.
--   • Si une table n'a PAS la policy attendue → la migration correspondante n'a pas été collée en
--     entier dans l'éditeur (antécédent connu : db/09 §① rattrapé en db/12). Rejouer le fichier manquant.
