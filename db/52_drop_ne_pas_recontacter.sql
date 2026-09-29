-- SPEC_prospects_pipeline_etapes.md : differee d une semaine apres la 51.
-- NE PAS APPLIQUER avant d avoir verifie qu aucun contact NPC n a ete perdu.
-- Le controle ignore les contacts dont l etape a change depuis la mise en service : une
-- levee de refus legitime laisse l ancien flag a true (plus rien ne le remet a false). Seuls
-- comptent les contacts flag = true, hors NPC, qui n ont AUCUNE ligne d historique de
-- changement d etape (type_action = 'Changement d''étape', ecrit par l app et par le MCP).
--   select count(*) from contacts c where c.ne_pas_recontacter = true
--     and c.etape_prospect is distinct from 'Ne pas recontacter'
--     and not exists (select 1 from historique_actions h
--                     where h.id_prospect = c.id and h.type_action = 'Changement d''étape');
--   -- doit retourner 0
alter table contacts drop column if exists ne_pas_recontacter;
alter table contacts drop column if exists ne_pas_recontacter_note;
alter table contacts drop column if exists ne_pas_recontacter_date;
