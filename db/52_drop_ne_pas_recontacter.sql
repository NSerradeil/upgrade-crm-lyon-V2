-- SPEC_prospects_pipeline_etapes.md : differee d une semaine apres la 51.
-- NE PAS APPLIQUER avant d avoir verifie qu aucun contact NPC n a ete perdu :
--   select count(*) from contacts where ne_pas_recontacter = true
--     and etape_prospect is distinct from 'Ne pas recontacter';
--   -- doit retourner 0
alter table contacts drop column if exists ne_pas_recontacter;
alter table contacts drop column if exists ne_pas_recontacter_note;
alter table contacts drop column if exists ne_pas_recontacter_date;
