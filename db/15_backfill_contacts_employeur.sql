-- ══════════════════════════════════════════════════════════════════════
-- 15 — Backfill CONTACTS (1/2) : `groupe` → `employeur` pour candidats/consultants/freelances
-- Spec : SPECS_CRM/SPEC_compte_id_besoins_contacts.md · décisions Nicolas 21/08
-- Ces statuts ne sont PAS reliés à un compte (leur employeur n'est pas un compte client) :
-- on recopie simplement leur `groupe` (l'employeur) dans le nouveau champ `employeur`.
-- Le lien Prospect/Client → compte se fera en db/16 (contact_compte). crm_norm() créée en db/14.
-- Transaction atomique, rejouable.
-- ══════════════════════════════════════════════════════════════════════
BEGIN;

-- Recopie groupe → employeur pour les statuts "porteurs d'un employeur", SAUF les placeholders
-- qui ne sont pas des employeurs ("Candidat", "Freelance").
UPDATE public.contacts
SET employeur = btrim(groupe)
WHERE statut IN ('Candidat','Consultant CDI','Freelance','Prestataire')
  AND coalesce(btrim(groupe),'') <> ''
  AND crm_norm(groupe) NOT IN ('candidat','freelance')
  AND employeur IS DISTINCT FROM btrim(groupe);   -- idempotent : ne réécrit pas si déjà bon

-- ─────────────────────────────────────────────────────────────────────
-- VÉRIF (avant COMMIT mental) :
-- V1 : combien de contacts de ces statuts ont désormais un employeur, vs restés vides (placeholders).
SELECT
  count(*) FILTER (WHERE statut IN ('Candidat','Consultant CDI','Freelance','Prestataire')
                     AND coalesce(btrim(groupe),'')<>'')                          AS cibles_avec_groupe,
  count(*) FILTER (WHERE statut IN ('Candidat','Consultant CDI','Freelance','Prestataire')
                     AND coalesce(btrim(employeur),'')<>'')                       AS avec_employeur,
  count(*) FILTER (WHERE statut IN ('Candidat','Consultant CDI','Freelance','Prestataire')
                     AND coalesce(btrim(groupe),'')<>'' AND crm_norm(groupe) IN ('candidat','freelance')) AS placeholders_ignores
FROM public.contacts;

-- V2 : échantillon de contrôle (10 lignes) statut / groupe / employeur.
SELECT statut, groupe, employeur
FROM public.contacts
WHERE statut IN ('Candidat','Consultant CDI','Freelance','Prestataire')
  AND coalesce(btrim(employeur),'')<>''
ORDER BY updated_at DESC NULLS LAST
LIMIT 10;

COMMIT;
