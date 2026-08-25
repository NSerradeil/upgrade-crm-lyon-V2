-- ══════════════════════════════════════════════════════════════════════
-- 17 — Chantier compte_id : PHASE 5 (finale) — DROP des colonnes texte
-- Date : 2026-08-25 · Spec : SPECS_CRM/SPEC_compte_id_besoins_contacts.md
--
-- ⚠️ IRRÉVERSIBLE. À N'EXÉCUTER QUE lorsque TOUT ce qui lit/écrit ces colonnes
--    est déjà déployé et vérifié :
--    • App web (index.html) ≥ Lot A « P5-lotA » (société dérivée injectée, écritures retirées).
--    • MCP (index.mjs) ≥ v8.14.0 installé PARTOUT (toi + cowork + sessions Jules).
--      Un ancien MCP (≤ 8.13) écrit encore compte/groupe → il PLANTERAIT après ce DROP.
--    • Aucun autre client n'écrit ces colonnes.
--
-- Source de vérité après ce DROP :
--    • besoins   → compte_id (FK comptes)
--    • contacts  → contact_compte (Prospect/Client) + employeur (candidats)
-- ══════════════════════════════════════════════════════════════════════

BEGIN;

-- Garde-fou : refuser le DROP s'il reste des besoins Prospect/Client-liés sans compte_id
-- alors qu'ils ont un ancien texte (signalerait une bascule incomplète). Informative.
DO $$
DECLARE n_besoins int; n_contacts int;
BEGIN
  SELECT count(*) INTO n_besoins  FROM public.besoins  WHERE compte IS NOT NULL AND btrim(compte) <> '' AND compte_id IS NULL;
  RAISE NOTICE 'Besoins avec texte compte mais sans compte_id (info) : %', n_besoins;
  SELECT count(*) INTO n_contacts FROM public.contacts WHERE statut IN ('Prospect','Client')
     AND groupe IS NOT NULL AND btrim(groupe) <> ''
     AND NOT EXISTS (SELECT 1 FROM public.contact_compte cc WHERE cc.contact_id = contacts.id);
  RAISE NOTICE 'Contacts Prospect/Client avec texte groupe mais sans lien contact_compte (info) : %', n_contacts;
END $$;

ALTER TABLE public.besoins  DROP COLUMN IF EXISTS compte;
ALTER TABLE public.contacts DROP COLUMN IF EXISTS groupe;

-- VÉRIF (après exécution) : les 2 colonnes ne doivent plus exister.
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema='public'
  AND ((table_name='besoins'  AND column_name='compte')
    OR (table_name='contacts' AND column_name='groupe'));
-- Attendu : 0 ligne.

COMMIT;
