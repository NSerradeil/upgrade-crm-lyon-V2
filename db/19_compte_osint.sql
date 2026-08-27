-- ══════════════════════════════════════════════════════════════════════
-- 19 — Infos publiques compte : colonnes OSINT + news
-- Date : 2026-08-27 · Spec : SPECS_CRM/SPEC_compte_infos_publiques_osint.md
--
-- OBJECTIF : enrichir l'onglet Infos de la fiche compte avec des données
-- publiques auto-remplies par les workers Jules (batch annuel infos de base +
-- veille hebdo news). Toutes les colonnes sont nullable → non-cassant, l'app
-- masque les blocs vides. Les workers écrivent via CRM_PG_URL (bypass RLS),
-- aucune policy additionnelle nécessaire.
--
-- IDEMPOTENT (IF NOT EXISTS) : rejouable sans risque.
-- ══════════════════════════════════════════════════════════════════════

ALTER TABLE public.comptes
  ADD COLUMN IF NOT EXISTS siren           TEXT,
  ADD COLUMN IF NOT EXISTS adresse         TEXT,
  ADD COLUMN IF NOT EXISTS description     TEXT,
  ADD COLUMN IF NOT EXISTS effectifs       INTEGER,
  ADD COLUMN IF NOT EXISTS effectifs_annee INTEGER,
  ADD COLUMN IF NOT EXISTS ca              BIGINT,
  ADD COLUMN IF NOT EXISTS ca_annee        INTEGER,
  ADD COLUMN IF NOT EXISTS resultat_net    BIGINT,
  ADD COLUMN IF NOT EXISTS resultat_annee  INTEGER,
  ADD COLUMN IF NOT EXISTS news            JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS osint_maj       DATE,
  ADD COLUMN IF NOT EXISTS news_maj        DATE;

-- ─────────────────────────────────────────────────────────────────────
-- VÉRIF (à lire après exécution) — les 12 colonnes doivent exister.
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='comptes'
  AND column_name IN ('siren','adresse','description','effectifs','effectifs_annee',
                      'ca','ca_annee','resultat_net','resultat_annee','news','osint_maj','news_maj')
ORDER BY column_name;
