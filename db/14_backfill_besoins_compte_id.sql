-- ══════════════════════════════════════════════════════════════════════
-- 14 — Backfill BESOINS : texte `compte` → `compte_id` (phase 2, partie besoins)
-- Spec : SPECS_CRM/SPEC_compte_id_besoins_contacts.md · décisions Nicolas 21/08
-- Transaction atomique. Rejouable (idempotent sur les liens ; création compte gardée).
-- Ne touche PAS encore aux contacts (db/15) ni au drop du texte (db/16).
-- ══════════════════════════════════════════════════════════════════════
BEGIN;

-- Helper de normalisation (réutilisé aussi par db/15) : lower + trim + espaces compactés.
CREATE OR REPLACE FUNCTION public.crm_norm(t text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT lower(btrim(regexp_replace(coalesce(t,''),'\s+',' ','g'))) $$;

-- 0) Fusion du doublon compte APRIL(70)/April(442) : repointer les refs vers 70 puis supprimer 442.
UPDATE public.missions       SET compte_id = 70 WHERE compte_id = 442;
UPDATE public.contact_compte SET compte_id = 70 WHERE compte_id = 442;
DELETE FROM public.comptes WHERE id = 442;

-- 1) Créer les comptes canoniques manquants (seulement si aucun nom normalisé équivalent n'existe).
--    statut 'Prospect' par défaut + responsable NULL → Nicolas ajustera (cf. rapport).
WITH wanted(nom) AS (VALUES
  ('Crédit Agricole Technologies & Services (CATS)'),
  ('SNCF Connect'), ('BNP ITG'), ('AXA'), ('Michelin Digital'),
  ('Solocal'), ('Avril'), ('BPCE'), ('ENGIE'), ('Iroko'),
  ('Little Big Connection')
)
INSERT INTO public.comptes (nom, statut)
SELECT w.nom, 'Prospect'
FROM wanted w
WHERE crm_norm(w.nom) NOT IN (SELECT crm_norm(nom) FROM public.comptes);

-- 2) Table de correspondance ALIAS orphelin → nom canonique (les libellés = un compte existant
--    se lient directement à l'étape 3b, pas besoin de les lister ici).
CREATE TEMP TABLE alias_map(raw text, cible text) ON COMMIT DROP;
INSERT INTO alias_map(raw, cible) VALUES
  ('CATS',                                     'Crédit Agricole Technologies & Services (CATS)'),
  ('Crédit Agricole Technologies et Services', 'Crédit Agricole Technologies & Services (CATS)'),
  ('CA-TS',                                    'Crédit Agricole Technologies & Services (CATS)'),
  ('Alpha',                                    'Crédit Agricole Technologies & Services (CATS)'),
  ('Crédit Agricole Technology & Services',    'Crédit Agricole Technologies & Services (CATS)'),
  ('Crédit Agricole',                          'Crédit Agricole Technologies & Services (CATS)'),
  ('BPCE - SI',                                'BPCE'),
  ('ENGIE - GBU LEI',                          'ENGIE'),
  ('Banque (LBC anonymisé)',                   'Little Big Connection'),
  ('Banque/Assurance Niort (LBC)',             'Little Big Connection'),
  ('LBC',                                      'Little Big Connection');
-- (SNCF Connect, BNP ITG [+ variante espace], AXA, Michelin Digital, Solocal, Avril, IROKO
--  ont un libellé == nom canonique → gérés par le match normalisé direct 3b.)

-- 3a) Lier via alias (orphelins renommés).
UPDATE public.besoins b SET compte_id = c.id
FROM alias_map a
JOIN public.comptes c ON crm_norm(c.nom) = crm_norm(a.cible)
WHERE b.compte_id IS NULL AND crm_norm(b.compte) = crm_norm(a.raw);

-- 3b) Lier par match normalisé direct (libellé == nom d'un compte, casse/espace ignorés).
UPDATE public.besoins b SET compte_id = c.id
FROM public.comptes c
WHERE b.compte_id IS NULL
  AND coalesce(btrim(b.compte),'') <> ''
  AND crm_norm(b.compte) = crm_norm(c.nom);

-- ─────────────────────────────────────────────────────────────────────
-- VÉRIF (à lire avant de valider mentalement le COMMIT) :
-- V1 : combien de besoins avec texte sont maintenant liés vs encore NULL (devrait être ~0 NULL).
SELECT
  count(*) FILTER (WHERE coalesce(btrim(compte),'')<>'')                       AS besoins_avec_texte,
  count(*) FILTER (WHERE coalesce(btrim(compte),'')<>'' AND compte_id IS NOT NULL) AS lies,
  count(*) FILTER (WHERE coalesce(btrim(compte),'')<>'' AND compte_id IS NULL)     AS restants_non_lies
FROM public.besoins;

-- V2 : la liste des besoins avec texte NON liés (à inspecter s'il en reste).
SELECT compte AS libelle, count(*) AS nb
FROM public.besoins
WHERE coalesce(btrim(compte),'')<>'' AND compte_id IS NULL
GROUP BY compte ORDER BY nb DESC;

-- V3 : les comptes créés par ce script (rapport).
SELECT id, nom, statut FROM public.comptes
WHERE nom IN ('Crédit Agricole Technologies & Services (CATS)','SNCF Connect','BNP ITG','AXA',
              'Michelin Digital','Solocal','Avril','BPCE','ENGIE','Iroko','Little Big Connection')
ORDER BY nom;

COMMIT;
