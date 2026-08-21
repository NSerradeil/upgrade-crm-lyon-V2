-- ══════════════════════════════════════════════════════════════════════
-- ANALYSE (lecture seule) — libellés texte vs fiches comptes, pour cadrer le backfill (phase 2)
-- Normalisation commune : lower + trim + espaces internes compactés
--   norm(x) = lower(btrim(regexp_replace(x, '\s+', ' ', 'g')))
-- Colle les 4 résultats, je classe les orphelins (vraie entreprise → créer / non-compte → vide).
-- ══════════════════════════════════════════════════════════════════════

-- A) besoins.compte ORPHELINS (aucun compte au nom normalisé équivalent) — à créer ou laisser vide
WITH cn AS (SELECT lower(btrim(regexp_replace(nom,'\s+',' ','g'))) AS n FROM comptes)
SELECT b.compte AS libelle, count(*) AS nb_besoins
FROM besoins b
WHERE coalesce(btrim(b.compte),'') <> ''
  AND lower(btrim(regexp_replace(b.compte,'\s+',' ','g'))) NOT IN (SELECT n FROM cn)
GROUP BY b.compte
ORDER BY nb_besoins DESC, libelle;

-- B) contacts.groupe ORPHELINS — avec le détail des statuts (candidat = ira dans employeur, pas un compte)
WITH cn AS (SELECT lower(btrim(regexp_replace(nom,'\s+',' ','g'))) AS n FROM comptes)
SELECT c.groupe AS libelle,
       count(*) AS nb_contacts,
       count(*) FILTER (WHERE c.statut = 'Candidat') AS dont_candidats,
       string_agg(DISTINCT c.statut, ', ') AS statuts
FROM contacts c
WHERE coalesce(btrim(c.groupe),'') <> ''
  AND lower(btrim(regexp_replace(c.groupe,'\s+',' ','g'))) NOT IN (SELECT n FROM cn)
GROUP BY c.groupe
ORDER BY nb_contacts DESC, libelle;

-- C) RÉSUMÉ chiffré : combien vont s'auto-lier vs rester orphelins
WITH cn AS (SELECT lower(btrim(regexp_replace(nom,'\s+',' ','g'))) AS n FROM comptes)
SELECT
  (SELECT count(*) FROM besoins WHERE coalesce(btrim(compte),'')<>'') AS besoins_avec_texte,
  (SELECT count(*) FROM besoins b WHERE lower(btrim(regexp_replace(b.compte,'\s+',' ','g'))) IN (SELECT n FROM cn)) AS besoins_matchables,
  (SELECT count(*) FROM contacts WHERE coalesce(btrim(groupe),'')<>'') AS contacts_avec_texte,
  (SELECT count(*) FROM contacts c WHERE lower(btrim(regexp_replace(c.groupe,'\s+',' ','g'))) IN (SELECT n FROM cn)) AS contacts_matchables;

-- D) DOUBLONS d'orthographe DÉJÀ dans comptes (même nom normalisé, plusieurs fiches) — à fusionner au passage
SELECT lower(btrim(regexp_replace(nom,'\s+',' ','g'))) AS nom_normalise,
       count(*) AS nb_fiches, string_agg(id::text || ':' || nom, ' | ' ORDER BY id) AS fiches
FROM comptes
GROUP BY 1 HAVING count(*) > 1
ORDER BY nb_fiches DESC;
