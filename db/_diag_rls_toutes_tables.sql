-- DIAG — photo complète des policies RLS sur les tables métier
-- 27/07/2026 · lecture seule
--
-- Pourquoi : l'audit des policies de `besoins` a montré que (a) le SELECT commercial
-- exige `agence = get_my_agence()` sans échappatoire par le responsable — d'où le
-- besoin BPM002771 invisible à Louis Py — et (b) l'UPDATE/DELETE commercial exige
-- `responsable = get_my_nom()`. Donc le chantier « écriture ouverte à tous les
-- commerciaux » a bien un volet BASE, contrairement à ce que la spec affirmait.
-- Il faut la même photo sur les 4 autres tables avant de réécrire la spec.

SELECT tablename, policyname, cmd, roles,
       qual        AS condition_lecture,
       with_check  AS condition_ecriture
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('contacts','comptes','missions','taches',
                    'historique_actions','historique_missions','sessions_prospection')
ORDER BY tablename, cmd, policyname;

-- Et la définition des 3 fonctions d'aide, pour savoir exactement ce qu'elles renvoient
SELECT proname, pg_get_functiondef(oid) AS definition
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('get_my_role','get_my_agence','get_my_nom');

-- ─── COMPLÉMENT (27/07) — il manque les policies d'ÉCRITURE ───
-- Le premier passage n'a renvoyé que les SELECT/ALL. Pour chiffrer le volet base du
-- chantier A, il faut les INSERT/UPDATE/DELETE de contacts, comptes et taches :
SELECT tablename, policyname, cmd, qual AS condition_lecture, with_check AS condition_ecriture
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('contacts','comptes','taches','historique_actions')
  AND cmd IN ('INSERT','UPDATE','DELETE')
ORDER BY tablename, cmd;
