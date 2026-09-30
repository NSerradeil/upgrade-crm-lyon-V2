-- db/54_agent_sequences_contact_id.sql : SPEC_campagnes_prospection_etapes.md, 29/09/2026
-- A coller dans le SQL Editor Supabase, AVANT la bascule du MCP 8.27.0 (le MCP lit et ecrit cette
-- colonne ; sans elle, les effets CRM des campagnes echouent et le disent, les sequences s'ecrivent
-- quand meme). Rejouable sans risque : ajout de colonne et d'index, aucune donnee modifiee.
-- Lien optionnel d'une sequence de campagne vers la fiche contact du CRM, pose par le MCP
-- (agent_sequence_upsert) a la premiere vraie tentative de contact d'une campagne de prospection.
-- Supprimer la fiche remet le lien a null : la sequence, elle, reste.
-- contacts.id est un bigint (cf. db/01 et db/04, contact_consultant_id bigint references contacts) :
-- la cle etrangere a le meme type.

alter table public.agent_sequences
  add column if not exists contact_id bigint references public.contacts(id) on delete set null;

comment on column public.agent_sequences.contact_id is
  'Fiche contact liee a la personne suivie (campagnes de prospection). Null tant qu elle n a pas ete contactee, ou si la fiche a ete supprimee.';

create index if not exists agent_sequences_contact_idx
  on public.agent_sequences (contact_id) where contact_id is not null;

-- Controle apres passage (une ligne attendue, data_type = bigint) :
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'public' and table_name = 'agent_sequences' and column_name = 'contact_id';
-- Cle etrangere et sa regle de suppression (confdeltype = 'n' pour set null) :
--   select conname, confdeltype from pg_constraint
--    where conrelid = 'public.agent_sequences'::regclass and contype = 'f' and conname like '%contact%';
