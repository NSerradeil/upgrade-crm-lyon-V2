-- ══════════════════════════════════════════════════════════════════════
-- 13 — Rattachement au compte : PHASE 1, ajout des colonnes (non-cassant)
-- Date : 2026-08-21 · Spec : SPECS_CRM/SPEC_compte_id_besoins_contacts.md
--
-- OBJECTIF : préparer la migration texte→compte_id SANS rien casser. On ajoute
-- seulement les colonnes (nullable) ; aucun backfill, aucune suppression ici.
--   • besoins.compte_id   → FK comptes(id), remplacera le texte besoins.compte (db/15)
--   • contacts.employeur  → texte employeur des candidats (remplace l'usage de contacts.groupe
--                           pour ce cas ; le lien Prospect/Client passe par contact_compte, déjà en place)
--
-- IDEMPOTENT (IF NOT EXISTS) : rejouable sans risque.
-- RIEN À FAIRE CÔTÉ APP après ce fichier : les colonnes restent vides et ignorées
-- tant que la phase 3 (bascule UI) n'est pas déployée.
-- ══════════════════════════════════════════════════════════════════════

-- 1) besoins.compte_id — FK vers comptes, nullable, SET NULL si le compte est supprimé
--    (on ne veut pas cascade-delete des besoins quand une fiche compte disparaît).
ALTER TABLE public.besoins
  ADD COLUMN IF NOT EXISTS compte_id BIGINT REFERENCES public.comptes(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_besoins_compte_id ON public.besoins(compte_id);

-- 2) contacts.employeur — texte libre, employeur des candidats/consultants
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS employeur TEXT;

-- ─────────────────────────────────────────────────────────────────────
-- VÉRIF (à lire après exécution) — les 2 colonnes doivent exister, l'index aussi.
-- Attendu : besoins.compte_id (bigint), contacts.employeur (text), idx_besoins_compte_id.
SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema='public'
  AND (table_name='besoins'  AND column_name='compte_id')
   OR (table_name='contacts' AND column_name='employeur')
ORDER BY table_name, column_name;

SELECT indexname FROM pg_indexes
WHERE schemaname='public' AND indexname='idx_besoins_compte_id';

-- La FK : besoins.compte_id → comptes.id, ON DELETE SET NULL.
SELECT conname, confdeltype  -- confdeltype 'n' = SET NULL
FROM pg_constraint
WHERE conrelid='public.besoins'::regclass AND contype='f'
  AND conname ILIKE '%compte_id%';
