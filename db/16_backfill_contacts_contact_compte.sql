-- ══════════════════════════════════════════════════════════════════════
-- 16 — Backfill CONTACTS (2/2) : lien Prospect/Client → compte via `contact_compte`
-- Spec : SPECS_CRM/SPEC_compte_id_besoins_contacts.md · décisions Nicolas 21/08
-- Seuls les statuts Prospect/Client sont reliés à un compte (les autres = employeur, db/15).
-- GARDE : on ne pose un lien QUE pour les contacts qui n'ont AUCUN lien contact_compte
--         (on ne touche pas aux liens déjà gérés par l'app → pas de double is_primary).
-- crm_norm() créée en db/14. Transaction atomique, rejouable.
-- ══════════════════════════════════════════════════════════════════════
BEGIN;

-- 1) Créer les comptes orphelins Prospect/Client manquants (idempotent, statut 'Prospect' par défaut).
WITH wanted(nom) AS (VALUES
  ('FDJ United'),('Capgemini'),('Pennylane'),('Groupe Beaumanoir'),('+Simple'),
  ('Actual Group'),('Bary'),('BNP Paribas'),('Bridor Groupe Le Duff'),('Defacto'),
  ('Econocom'),('Finom'),('Flash Bpifrance'),('Fortuneo'),('KaOra Partners'),
  ('L-Acoustics'),('LDC Groupe'),('MADIC Group'),('Ouihelp'),('SOMFY Group'),
  ('Sumeria (ex Lydia)'),('Symalean'),('Terrena'),('The Adecco Group (Akkodis)'),
  ('TIPIAK'),('VM Matériaux')
)
INSERT INTO public.comptes (nom, statut)
SELECT w.nom, 'Prospect'
FROM wanted w
WHERE crm_norm(w.nom) NOT IN (SELECT crm_norm(nom) FROM public.comptes);

-- 2) Alias orphelin → nom canonique (les libellés == nom d'un compte se lient direct à l'étape 4).
CREATE TEMP TABLE alias_c(raw text, cible text) ON COMMIT DROP;
INSERT INTO alias_c(raw, cible) VALUES
  ('Crédit Agricole Anjou Maine', 'Crédit Agricole Technologies & Services (CATS)'),
  ('BNP Paribas - PACE',          'BNP Paribas'),
  ('SNCF Connect and tech',       'SNCF Connect'),
  ('ENGIE - GBU LEI',             'ENGIE'),
  ('FDJ Parions Sport',           'FDJ United'),
  ('FDJ United / Nirio',          'FDJ United');

-- 3) Labels de POOL / prospection (pas des comptes) : à NE PAS lier.
CREATE TEMP TABLE pool_c(raw text) ON COMMIT DROP;
INSERT INTO pool_c(raw) VALUES
  ('Prospection AURA - pool archétype Huttopia'),
  ('Décideur compte gagné - voisins du win');

-- 4) Poser le lien contact_compte (is_primary) pour les Prospect/Client SANS lien existant.
WITH resolved AS (
  SELECT ct.id AS contact_id, co.id AS compte_id
  FROM public.contacts ct
  LEFT JOIN alias_c a ON crm_norm(a.raw) = crm_norm(ct.groupe)
  JOIN public.comptes co ON crm_norm(co.nom) = crm_norm(coalesce(a.cible, ct.groupe))
  WHERE ct.statut IN ('Prospect','Client')
    AND coalesce(btrim(ct.groupe),'') <> ''
    AND crm_norm(ct.groupe) NOT IN (SELECT crm_norm(raw) FROM pool_c)
    AND NOT EXISTS (SELECT 1 FROM public.contact_compte cc WHERE cc.contact_id = ct.id)
)
INSERT INTO public.contact_compte (contact_id, compte_id, is_primary)
SELECT contact_id, compte_id, true FROM resolved
ON CONFLICT (contact_id, compte_id) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────
-- VÉRIF (avant COMMIT mental) :
-- V1 : parmi les Prospect/Client avec un groupe, combien ont maintenant un lien contact_compte.
SELECT
  count(*) FILTER (WHERE statut IN ('Prospect','Client') AND coalesce(btrim(groupe),'')<>'') AS pc_avec_groupe,
  count(*) FILTER (WHERE statut IN ('Prospect','Client') AND coalesce(btrim(groupe),'')<>''
                     AND EXISTS (SELECT 1 FROM public.contact_compte cc WHERE cc.contact_id = contacts.id)) AS pc_lies
FROM public.contacts;

-- V2 : Prospect/Client avec groupe mais TOUJOURS sans lien (attendu : labels de pool + éventuels restes).
SELECT c.groupe AS libelle, count(*) AS nb
FROM public.contacts c
WHERE c.statut IN ('Prospect','Client') AND coalesce(btrim(c.groupe),'')<>''
  AND NOT EXISTS (SELECT 1 FROM public.contact_compte cc WHERE cc.contact_id = c.id)
GROUP BY c.groupe ORDER BY nb DESC;

-- V3 : les comptes créés par ce script (rapport).
SELECT id, nom FROM public.comptes
WHERE nom IN ('FDJ United','Capgemini','Pennylane','Groupe Beaumanoir','+Simple','Actual Group',
              'Bary','BNP Paribas','Bridor Groupe Le Duff','Defacto','Econocom','Finom',
              'Flash Bpifrance','Fortuneo','KaOra Partners','L-Acoustics','LDC Groupe','MADIC Group',
              'Ouihelp','SOMFY Group','Sumeria (ex Lydia)','Symalean','Terrena',
              'The Adecco Group (Akkodis)','TIPIAK','VM Matériaux')
ORDER BY nom;

COMMIT;
