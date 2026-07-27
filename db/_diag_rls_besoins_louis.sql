-- DIAG — pourquoi Louis Py ne voit pas le besoin BPM002771 ?
-- 27/07/2026 · lecture seule, aucune écriture
--
-- Contexte : besoin `1cca2350-17bb-403f-b316-2139317ea110`
--   titre = BPM002771 — Scrum Master Expérimenté Lyon — Tribu Crédit Agri Pro
--   agence = 'Lyon' · responsable = 'Louis Py' · statut = 'Besoin ouvert'
-- Louis Py : role 'commercial', agence 'Paris', preferences {}
--
-- Éliminé côté app : le filtrage client (lignes 4714 et 5035 laissent passer ce besoin
-- pour Louis), le chargement (fetchAll fait select('*') sans filtre), et le service
-- worker (network-first). Reste l'hypothèse RLS.

-- ─── 1. RLS est-il actif sur besoins, et sur quelles tables ? ───
SELECT relname AS table_name, relrowsecurity AS rls_actif, relforcerowsecurity AS rls_force
FROM pg_class
WHERE relnamespace = 'public'::regnamespace
  AND relname IN ('besoins','contacts','comptes','missions','taches',
                  'historique_actions','historique_missions','sessions_prospection')
ORDER BY relname;

-- ─── 2. Toutes les policies de la table besoins ───
-- C'est LA requête qui répond à la question : si une policy SELECT filtre sur
-- l'agence ou sur le responsable pour le rôle commercial, on la verra dans `qual`.
SELECT policyname, cmd, roles, qual AS condition_lecture, with_check AS condition_ecriture
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'besoins'
ORDER BY cmd, policyname;

-- ─── 3. Comparaison : les policies des tables dont on sait la lecture ouverte ───
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('contacts','comptes','missions')
  AND cmd IN ('SELECT','ALL')
ORDER BY tablename, policyname;

-- ─── 4. Ce que voit Louis, vu depuis son compte ───
-- Remplace l'uid par celui de Louis Py (a42e1bfc-19b4-4c13-af0d-690f23db7545)
-- et exécute en simulant son rôle. Si le SELECT renvoie 0 ligne alors que la
-- fiche existe, la cause est bien RLS.
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claim.sub = 'a42e1bfc-19b4-4c13-af0d-690f23db7545';
SELECT id, titre, agence, responsable
FROM besoins
WHERE id = '1cca2350-17bb-403f-b316-2139317ea110';
-- Attendu si RLS est en cause : 0 ligne.
-- Attendu si RLS n'est pas en cause : 1 ligne → alors le problème est ailleurs et
-- il faut regarder l'écran exact de Louis (quel onglet, quels filtres actifs).
RESET ROLE;

-- ─── 5. Les fonctions d'aide utilisées par les policies ───
SELECT proname, pg_get_functiondef(oid) AS definition
FROM pg_proc
WHERE pronamespace = 'public'::regnamespace
  AND proname IN ('get_my_role','get_my_agence','get_my_nom');
