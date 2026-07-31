-- ══════════════════════════════════════════════════════════════════════
-- AUDIT RLS COMPLET — les 17 tables du CRM
-- 31/07/2026 · LECTURE SEULE, aucune écriture
--
-- POURQUOI : trois collègues bloqués en une semaine, trois fois le MÊME défaut —
-- une condition `agence = get_my_agence()` sans échappatoire par le responsable.
--   · Louis Py    → besoins (SELECT)        → corrigé db/08
--   · le pré-filtre app vBesoins             → corrigé 68c8ba7
--   · Amel Benzai → besoin_candidats (INSERT) → corrigé db/11
-- Mon audit du 28/07 (db/09) ne couvrait que 9 tables sur 17. Les 8 autres n'ont
-- jamais été regardées, dont `session_prospection_contacts` (17 usages dans l'app)
-- et `mission_periods` (9). On arrête d'attendre le prochain signalement.
--
-- Les 3 requêtes ci-dessous sont conçues pour tenir dans un copier-coller.
-- ══════════════════════════════════════════════════════════════════════


-- ─── ① LES SUSPECTS — c'est LA requête qui répond à la question ───
-- Toute policy qui filtre sur l'agence SANS prévoir de sortie par le responsable ni par
-- l'auteur. C'est exactement le motif des trois bugs. Résultat attendu idéal : 0 ligne.
SELECT tablename, policyname, cmd,
       coalesce(qual, with_check) AS condition
FROM pg_policies
WHERE schemaname = 'public'
  AND policyname NOT LIKE '%partner%'                    -- le partner est cloisonné exprès
  AND coalesce(qual, '') || coalesce(with_check, '') LIKE '%get_my_agence%'
  AND coalesce(qual, '') || coalesce(with_check, '') NOT LIKE '%get_my_nom%'
  AND coalesce(qual, '') || coalesce(with_check, '') NOT LIKE '%created_by%'
ORDER BY tablename, cmd;


-- ─── ② LES OUBLIS — tables sans RLS, ou avec RLS mais SANS AUCUNE policy ───
-- Une table RLS activé + zéro policy est INACCESSIBLE à tout le monde sauf l'admin
-- Supabase. Une table sans RLS est au contraire GRANDE OUVERTE. Les deux méritent un œil.
SELECT c.relname AS "table",
       c.relrowsecurity AS rls_actif,
       count(p.policyname) AS nb_policies,
       CASE
         WHEN NOT c.relrowsecurity THEN '🔴 RLS DÉSACTIVÉ — table ouverte'
         WHEN count(p.policyname) = 0 THEN '🔴 RLS actif mais AUCUNE policy — table murée'
         ELSE 'ok'
       END AS verdict
FROM pg_class c
LEFT JOIN pg_policies p ON p.schemaname = 'public' AND p.tablename = c.relname
WHERE c.relnamespace = 'public'::regnamespace
  AND c.relkind = 'r'
  AND c.relname IN ('contacts','comptes','besoins','missions','taches',
                    'historique_actions','historique_missions','sessions_prospection',
                    'besoin_candidats','session_prospection_contacts','mission_periods',
                    'user_calendar_tokens','profiles','interco_imputations',
                    'contact_compte','partner_consultants','org_preferences')
GROUP BY c.relname, c.relrowsecurity
ORDER BY (CASE WHEN NOT c.relrowsecurity OR count(p.policyname)=0 THEN 0 ELSE 1 END), c.relname;


-- ─── ③ LA CARTE — une ligne par table et par commande ───
-- Vue d'ensemble compacte : qui peut faire quoi, partout. C'est ce qui servira de
-- référence pour ne plus déduire les droits d'un commentaire de fichier.
SELECT tablename AS "table",
       cmd,
       string_agg(
         policyname || ' :: ' ||
         -- ⚠️ L'ORDRE DES TESTS COMPTE. Première version (31/07) fautive : le test 'admin'
         -- arrivait en dernier, donc une policy `get_my_role() = any(array['admin',
         -- 'commercial'])` — c'est-à-dire OUVERTE AUX COMMERCIAUX — était étiquetée
         -- « admin seul ». La carte donnait une base bien plus verrouillée qu'elle ne l'est.
         -- On teste donc du plus spécifique au plus général.
         CASE
           WHEN coalesce(qual, with_check) = 'true' THEN 'OUVERT'
           WHEN coalesce(qual,'')||coalesce(with_check,'') LIKE '%commercial%'
                AND coalesce(qual,'')||coalesce(with_check,'') NOT LIKE '%get_my_agence%'
                AND coalesce(qual,'')||coalesce(with_check,'') NOT LIKE '%get_my_nom%'
                                                                         THEN 'commerciaux'
           WHEN coalesce(qual,'')||coalesce(with_check,'') LIKE '%get_my_agence%'
                AND coalesce(qual,'')||coalesce(with_check,'') LIKE '%get_my_nom%'
                                                                         THEN 'agence OU responsable'
           WHEN coalesce(qual,'')||coalesce(with_check,'') LIKE '%get_my_agence%' THEN 'par AGENCE seule ⚠️'
           WHEN coalesce(qual,'')||coalesce(with_check,'') LIKE '%created_by%'    THEN 'par AUTEUR'
           WHEN coalesce(qual,'')||coalesce(with_check,'') LIKE '%get_my_nom%'    THEN 'par RESPONSABLE'
           WHEN coalesce(qual,'')||coalesce(with_check,'') LIKE '%admin%'         THEN 'admin seul'
           ELSE 'autre'
         END,
         ' | ' ORDER BY policyname) AS regles
FROM pg_policies
WHERE schemaname = 'public'
  AND policyname NOT LIKE '%partner%'
GROUP BY tablename, cmd
ORDER BY tablename, cmd;
