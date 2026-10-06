-- db/56_pipeline_prospect_renommage.sql : renommage et fusion d'étapes du pipeline prospect, 06/10/2026
-- Décision Nicolas : « Qualifié » devient « RDV effectué », « En veille » devient « À relancer »,
-- « Perdu » est fusionné dans « Ne pas recontacter » (son motif_perte, facultatif, devient celui de NPRC).
-- Aucune contrainte CHECK sur etape_prospect, aucune fonction, vue ni policy RLS ne teste ces libellés
-- (vérifié en prod le 06/10) : seules les données bougent.
-- À appliquer EN MÊME TEMPS que le push de l'app (index.html) et du MCP 8.29.0. Rejouable sans effet.

begin;

-- Sauvegarde des lignes touchées (retour arrière possible). RLS activée sans policy : invisible via l'API.
create table if not exists _pipeline_renommage_20261006 as
  select id, etape_prospect, prochaine_action_date, prochaine_action_libelle, motif_perte
  from contacts where etape_prospect in ('Qualifié','En veille','Perdu');
alter table _pipeline_renommage_20261006 enable row level security;

update contacts set etape_prospect = 'RDV effectué' where etape_prospect = 'Qualifié';
update contacts set etape_prospect = 'À relancer'   where etape_prospect = 'En veille';
-- Perdu -> Ne pas recontacter : le motif_perte reste, la prochaine action disparaît (NPRC n'en porte pas).
update contacts set etape_prospect = 'Ne pas recontacter',
                    prochaine_action_date = null, prochaine_action_libelle = null
  where etape_prospect = 'Perdu';

comment on column contacts.etape_prospect is
  'Étape du pipeline prospect (ne vaut que si statut = Prospect) : À contacter, Contacté, En discussion, RDV planifié, RDV effectué, À relancer, Ne pas recontacter. Cf. SPEC_prospects_pipeline_etapes.md';
comment on column contacts.motif_perte is
  'Contacts : motif facultatif de l''étape « Ne pas recontacter » (ex-étape Perdu). Besoins : motif de Besoin Perdu.';

-- Filet de transition : un client resté sur l'ancien code (PWA en cache, MCP 8.28.0 pas encore réinstallé)
-- qui écrirait encore un ancien libellé est traduit à l'écriture au lieu de polluer la colonne.
-- À SUPPRIMER une fois le MCP 8.29.0 installé chez tous (drop trigger trg_contacts_etape_legacy ;
-- drop function contacts_etape_legacy()).
create or replace function contacts_etape_legacy() returns trigger
language plpgsql as $$
begin
  new.etape_prospect := case new.etape_prospect
    when 'Qualifié'  then 'RDV effectué'
    when 'En veille' then 'À relancer'
    when 'Perdu'     then 'Ne pas recontacter'
    else new.etape_prospect end;
  return new;
end $$;

drop trigger if exists trg_contacts_etape_legacy on contacts;
create trigger trg_contacts_etape_legacy
  before insert or update of etape_prospect on contacts
  for each row execute function contacts_etape_legacy();

-- Contrôle : plus aucun ancien libellé.
do $$
declare n int;
begin
  select count(*) into n from contacts where etape_prospect in ('Qualifié','En veille','Perdu');
  if n > 0 then raise exception 'migration 56 : % contact(s) encore sur un ancien libellé', n; end if;
end $$;

commit;
