-- db/51_contacts_etape_prospect.sql : SPEC_prospects_pipeline_etapes.md, 29/09/2026
-- A coller dans le SQL Editor Supabase. Idempotent.
-- Pipeline des prospects : étape, prochaine action datée, motif de sortie.

alter table contacts add column if not exists etape_prospect text;
alter table contacts add column if not exists prochaine_action_date timestamptz;
alter table contacts add column if not exists prochaine_action_libelle text;
alter table contacts add column if not exists motif_perte text;
alter table contacts add column if not exists motif_perte_precision text;

comment on column contacts.etape_prospect is
  'Étape du pipeline prospect. Ne vaut que si statut = Prospect. Cf. SPEC_prospects_pipeline_etapes.md';

-- Backfill : tout prospect existant démarre en « À contacter », sans action exigée.
update contacts set etape_prospect = 'À contacter'
  where statut = 'Prospect' and etape_prospect is null;

-- Reprise du flag ne_pas_recontacter (supprimé en migration 52).
update contacts set etape_prospect = 'Ne pas recontacter',
                    motif_perte_precision = coalesce(motif_perte_precision, ne_pas_recontacter_note)
  where statut = 'Prospect' and ne_pas_recontacter = true;

create index if not exists idx_contacts_etape_prospect
  on contacts (etape_prospect) where statut = 'Prospect';
create index if not exists idx_contacts_prochaine_action
  on contacts (prochaine_action_date) where statut = 'Prospect';
