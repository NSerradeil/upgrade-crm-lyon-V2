-- db/53_ventilation_prospects.sql : SPEC_prospects_pipeline_etapes.md, 29/09/2026
-- Ventile les prospects restés en « À contacter » après la 51 dans la bonne étape, en lisant
-- leur historique (actions, sessions d'appels, besoins, tâches ouvertes).
--
-- EN DEUX TEMPS, à coller dans le SQL Editor Supabase :
--   ÉTAPE 1 : calcule les propositions dans une table à part. Ne modifie AUCUN contact.
--             Relire les deux requêtes de contrôle en bas de l'étape 1.
--   ÉTAPE 2 : applique les propositions. À ne lancer qu'après relecture de l'étape 1.
--   RETOUR ARRIÈRE : en bas du fichier.
--
-- Périmètre : contacts statut = 'Prospect', étape nulle ou « À contacter », et SANS aucun
-- « Changement d'étape » dans l'historique (un prospect déplacé à la main depuis la mise en
-- service n'est jamais touché). Les autres étapes, dont « Ne pas recontacter », ne bougent pas.
--
-- Règles, de la plus forte à la plus faible :
--   1. Un besoin lié au contact (besoins.contact_id)                        -> Qualifié
--   2. Dernier signal négatif = « Pas intéressé » en session, plus récent
--      que tout signal positif                                             -> En veille, réveil
--                                                                             à session + 6 mois, 09h00
--   3. Signal positif : RDV tenu, mail reçu, « Intéressant » en session    -> En discussion
--   4. Démarche sortante seule : LinkedIn, mail envoyé, appel, relance,
--      « Appelé » ou « Pas joignable » en session                          -> Contacté
--   5. Rien de tout ça                                                     -> reste À contacter
-- Prochaine action des étapes actives : la plus proche tâche ouverte du contact, sinon vide.
-- Aucune ligne d'historique n'est écrite : sinon chaque carte afficherait « ventilation »
-- comme dernière action. La table de l'étape 1 sert de trace et de sauvegarde.


-- ═══════════════ ÉTAPE 1 : propositions (aucun contact modifié) ═══════════════

drop table if exists _ventilation_prospects_20260929;

create table _ventilation_prospects_20260929 as
with perimetre as (
  select c.id, c.etape_prospect as ancienne_etape,
         c.prochaine_action_date as ancienne_date, c.prochaine_action_libelle as ancien_libelle
  from contacts c
  where c.statut = 'Prospect'
    and coalesce(c.etape_prospect, 'À contacter') = 'À contacter'
    and not exists (select 1 from historique_actions h
                    where h.id_prospect = c.id and h.type_action = 'Changement d''étape')
),
signaux as (
  -- Historique : RDV tenu et réponse reçue = positif ; démarche sortante = contact.
  select h.id_prospect as contact_id, h.date::date as d,
         case
           when h.type_action in ('RDV','RDV client','rdv','Café','Afterwork') then 'positif'
           when h.type_action in ('Mail reçu','Email reçu') then 'positif'
           when h.type_action in ('LinkedIn','linkedin','Message LinkedIn','Message LK','Message',
                                  'Mail envoyé','Email','Mail','Appel sortant','Tel','Appel','Call',
                                  'Appel LinkedIn','SMS','Relance','Relance auto','Relance programmée',
                                  'Premier contact') then 'sortant'
         end as nature
  from historique_actions h
  join perimetre p on p.id = h.id_prospect
  union all
  -- Sessions d'appels (seules les sessions terminées comptent).
  select spc.contact_id, sp.date_session::date,
         case spc.statut
           when 'interested'     then 'positif'
           when 'not_interested' then 'negatif'
           when 'called'         then 'sortant'
           when 'unreachable'    then 'sortant'
         end
  from session_prospection_contacts spc
  join sessions_prospection sp on sp.id = spc.session_id
  join perimetre p on p.id = spc.contact_id
  where sp.statut = 'done'
),
agreg as (
  select contact_id,
         max(d) filter (where nature = 'positif') as dernier_positif,
         max(d) filter (where nature = 'negatif') as dernier_negatif,
         max(d) filter (where nature = 'sortant') as dernier_sortant
  from signaux where nature is not null
  group by contact_id
),
proposition as (
  select p.*,
         exists (select 1 from besoins b where b.contact_id = p.id) as a_un_besoin,
         a.dernier_positif, a.dernier_negatif, a.dernier_sortant,
         case
           when exists (select 1 from besoins b where b.contact_id = p.id) then 'Qualifié'
           when a.dernier_negatif is not null
                and a.dernier_negatif >= coalesce(a.dernier_positif, date '1900-01-01') then 'En veille'
           when a.dernier_positif is not null then 'En discussion'
           when a.dernier_sortant is not null then 'Contacté'
           else 'À contacter'
         end as nouvelle_etape
  from perimetre p
  left join agreg a on a.contact_id = p.id
)
select pr.id, pr.ancienne_etape, pr.ancienne_date, pr.ancien_libelle, pr.nouvelle_etape,
       pr.a_un_besoin, pr.dernier_positif, pr.dernier_negatif, pr.dernier_sortant,
       case
         when pr.nouvelle_etape = 'En veille'
           then ((pr.dernier_negatif + interval '6 months')::date + time '09:00') at time zone 'Europe/Paris'
         when pr.nouvelle_etape in ('Contacté','En discussion','Qualifié')
           then (select min(t.due_date) from taches t
                 where t.contact_id = pr.id and t.statut not in ('fait','annule'))
       end as nouvelle_date,
       case
         when pr.nouvelle_etape = 'En veille' then 'Relance après refus'
         when pr.nouvelle_etape in ('Contacté','En discussion','Qualifié')
           then (select t.titre from taches t
                 where t.contact_id = pr.id and t.statut not in ('fait','annule')
                 order by t.due_date asc nulls last limit 1)
       end as nouveau_libelle
from proposition pr;

-- Contrôle 1 : répartition proposée (seules les lignes où l'étape change seront écrites).
select nouvelle_etape, count(*) as nb,
       count(*) filter (where nouvelle_date is not null) as avec_date
from _ventilation_prospects_20260929
group by nouvelle_etape
order by array_position(array['À contacter','Contacté','En discussion','RDV planifié','Qualifié',
                              'En veille','Perdu','Ne pas recontacter'], nouvelle_etape);

-- Contrôle 2 : échantillon lisible, 40 lignes, pour vérifier quelques cas à l'œil.
select v.nouvelle_etape, c.prenom, c.nom, c.responsable,
       v.dernier_positif, v.dernier_negatif, v.dernier_sortant, v.a_un_besoin,
       v.nouvelle_date, v.nouveau_libelle
from _ventilation_prospects_20260929 v
join contacts c on c.id = v.id
where v.nouvelle_etape <> 'À contacter'
order by v.nouvelle_etape, c.nom
limit 40;


-- ═══════════════ ÉTAPE 2 : application (après relecture de l'étape 1) ═══════════════

begin;

update contacts c
set etape_prospect           = v.nouvelle_etape,
    prochaine_action_date    = v.nouvelle_date,
    prochaine_action_libelle = v.nouveau_libelle,
    motif_perte              = null
from _ventilation_prospects_20260929 v
where c.id = v.id
  and v.nouvelle_etape <> 'À contacter'
  -- Garde : le contact n'a pas bougé depuis le calcul de l'étape 1.
  and c.statut = 'Prospect'
  and coalesce(c.etape_prospect, 'À contacter') = 'À contacter';

-- Contrôle : doit rendre les mêmes nombres que le contrôle 1 (hors « À contacter »).
select c.etape_prospect, count(*)
from contacts c join _ventilation_prospects_20260929 v on v.id = c.id
where v.nouvelle_etape <> 'À contacter'
group by c.etape_prospect;

commit;


-- ═══════════════ RETOUR ARRIÈRE (seulement en cas de besoin) ═══════════════
-- Remet les contacts ventilés dans leur état d'avant, s'ils n'ont pas été re-déplacés depuis.
--
-- update contacts c
-- set etape_prospect = v.ancienne_etape,
--     prochaine_action_date = v.ancienne_date,
--     prochaine_action_libelle = v.ancien_libelle
-- from _ventilation_prospects_20260929 v
-- where c.id = v.id and v.nouvelle_etape <> 'À contacter'
--   and c.etape_prospect = v.nouvelle_etape;
--
-- Ménage, une fois la ventilation validée (quelques semaines plus tard) :
-- drop table _ventilation_prospects_20260929;
