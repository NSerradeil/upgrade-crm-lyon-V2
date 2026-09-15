-- db/24_sortie_effectif.sql — Sortie des effectifs : le collaborateur redevient « Candidat ».
-- À coller dans le SQL Editor Supabase. Idempotent.
--
-- Pourquoi : une sortie des effectifs était portée par `contacts.date_sortie` SEULE — le statut
-- restait « Consultant CDI ». La fiche d'Alexine SEMENT affichait donc le badge CONSULTANT CDI
-- alors qu'elle est sortie le 30/08/2026 (demande Nicolas 15/09). Elle doit repasser « Candidat » :
-- elle retourne au vivier, replaçable.
--
-- Le piège : tout le périmètre de l'onglet Agence se filtre sur `contacts.statut`. Basculer le
-- statut sans autre précaution ferait disparaître la personne de l'HISTORIQUE Agence — taux
-- d'intercontrat annuel faussé (ses jours passés s'effaceraient rétroactivement) et sorties du
-- mois à zéro. D'où `ancien_statut` : le statut du jour devient « Candidat », mais la nature du
-- lien d'effectif qu'on a eu avec la personne reste connue. Détail : SPEC_sortie_effectif_retour_candidat.md.
begin;

-- 1) La colonne mémoire ------------------------------------------------------
alter table public.contacts add column if not exists ancien_statut text;

comment on column public.contacts.ancien_statut is
  'Statut d''effectif d''origine d''un ancien collaborateur repassé « Candidat » à sa sortie. '
  'NULL pour tout le monde sauf les anciens collaborateurs. Sert à l''historique de l''onglet Agence.';

alter table public.contacts drop constraint if exists contacts_ancien_statut_check;
alter table public.contacts add constraint contacts_ancien_statut_check
  check (ancien_statut is null or ancien_statut in ('Consultant CDI','Freelance','Prestataire'));

-- 2) Le trigger de bascule ---------------------------------------------------
-- Au niveau de la base et non de l'app, pour couvrir TOUTES les portes d'écriture :
-- formulaire CRM, serveur MCP, crm-import-collab.py, SQL Editor.
create or replace function public.contacts_sortie_effectif()
returns trigger language plpgsql as $$
begin
  -- Sortie échue depuis un statut d'effectif → on mémorise puis on repasse Candidat.
  if new.date_sortie is not null
     and new.date_sortie <= current_date
     and new.statut in ('Consultant CDI','Freelance','Prestataire')
  then
    new.ancien_statut := new.statut;
    new.statut        := 'Candidat';

  -- Réversion (erreur de saisie, réembauche) : on efface la date de sortie d'un ancien
  -- collaborateur → il retrouve son statut d'origine et la mémoire se vide.
  elsif new.date_sortie is null
     and new.ancien_statut is not null
     and new.statut = 'Candidat'
  then
    new.statut        := new.ancien_statut;
    new.ancien_statut := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_contacts_sortie_effectif on public.contacts;
create trigger trg_contacts_sortie_effectif
  before insert or update of statut, date_sortie, ancien_statut on public.contacts
  for each row execute function public.contacts_sortie_effectif();

-- 3) Backfill = le patch correctif -------------------------------------------
-- Tous ceux qui sont DÉJÀ sortis mais portent encore un statut d'effectif.
-- Au 15/09/2026 : Alexine SEMENT (id 1137, sortie le 30/08/2026) et elle seule.
-- Les 8 autres fiches Paris de l'écart TACE↔CRM n'ont pas de date_sortie → non concernées
-- (décision métier en attente, cf. §5 de la SPEC).
update public.contacts
   set ancien_statut = statut,
       statut        = 'Candidat',
       updated_at    = now()
 where date_sortie is not null
   and date_sortie <= current_date
   and statut in ('Consultant CDI','Freelance','Prestataire');

commit;

-- 4) Vérifications (à lire après exécution) -----------------------------------
-- a) La colonne et sa contrainte existent
select column_name, data_type from information_schema.columns
 where table_name='contacts' and column_name='ancien_statut';            -- attendu : 1 ligne, text

-- b) Plus personne de sorti ne porte un statut d'effectif
select count(*) as restant_a_basculer from public.contacts
 where date_sortie is not null and date_sortie <= current_date
   and statut in ('Consultant CDI','Freelance','Prestataire');           -- attendu : 0

-- c) Les anciens collaborateurs, avec leurs données d'effectif CONSERVÉES
select id, nom, prenom, statut, ancien_statut, agence, date_entree, date_sortie
  from public.contacts where ancien_statut is not null order by date_sortie desc;
                                                    -- attendu : SEMENT Alexine / Candidat / Consultant CDI
                                                    --           date_entree 2024-02-26, date_sortie 2026-08-30

-- d) L'effectif du jour n'a pas bougé : 65 CDI + 47 SST = 112
select count(*) filter (where statut='Consultant CDI') as cdi
  from public.contacts
 where statut in ('Consultant CDI','Freelance','Prestataire')
   and (date_sortie is null or date_sortie > current_date);              -- attendu : cdi = 65
