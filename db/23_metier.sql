-- db/23_metier.sql — normalise le métier des consultants sur la nomenclature Upgrade.
-- À coller dans le SQL Editor Supabase. Idempotent.
--
-- Pourquoi : `contacts.role` portait à la fois le métier (« Product Owner ») et l'intitulé de la
-- mission (« Business Analyst IT Retail & Supply Chain Cegid Y2 ») → 43 valeurs distinctes pour
-- 180 consultants, filtre injouable. L'intitulé de mission a déjà sa colonne : `missions.projet`.
-- Donc `contacts.role` ne porte plus QUE le métier, sur 12 valeurs.
--
-- Pas de contrainte CHECK : `role` sert aussi aux prospects (« DSI », « Head of Product »),
-- où le texte libre est légitime. La nomenclature est tenue par la liste déroulante de l'app,
-- qui ne s'applique qu'aux consultants.
begin;

-- Nomenclature : Product Designer · Product Owner · Product Manager · Business Analyst
--   Motion Designer · UX Research · Chef·fe de projet · Scrum master · Coach Agile
--   UI Designer · UX Designer · Lead Designer
update public.contacts c set role = v.metier
from (values
  -- Product Designer (le défaut de l'agence : « Consultant CDI », « Consultant » et les vides
  -- ne disent pas le métier — arbitrage Nicolas 14/09 : ce sont des product designers)
  ('Product Designer',     array['product designer','consultante product designer',
                                 'product designer (freelance)','ux designer / product designer',
                                 'consultant cdi','consultant']),
  ('Product Owner',        array['product owner','po','po senior','po/ba','ppo po',
                                 'product owner freelance',
                                 'product owner anaplan senior advanced consultant luxe retail']),
  ('Product Manager',      array['product manager','pm senior - ia','po/pm/product coach',
                                 'vp product / deputy cpo',
                                 'product manager ia / product owner assurances, full safe - freelance']),
  ('Business Analyst',     array['business analyst','business analyst consultante fonctionnelle cegid y2',
                                 'business analyst it retail & supply chain cegid y2',
                                 'business solutions specialist it supply-chain wms/oms/tms']),
  ('Motion Designer',      array['motion designer','da / motion designer','da/motion designer']),
  ('Chef·fe de projet',    array['chef de projet','chef de projet it retail expert pos',
                                 'po/cdp project manager crm adobe',
                                 'ecommerce & customer project manager omnichannel retail luxury']),
  ('Scrum master',         array['scrum master senior - coach agile','scrum master coach agile',
                                 'scrum master senior coach agile']),
  ('Lead Designer',        array['lead designer','senior lead designer freelance (paris, ex-renault trucks)']),
  ('UX Designer',          array['ux designer / ergonome hf','référent ux'])
) as v(metier, sources)
where c.statut in ('Consultant CDI','Freelance','Prestataire')
  and lower(btrim(coalesce(c.role,''))) = any (v.sources)
  and c.role is distinct from v.metier;

-- Les consultants sans rôle du tout : Product Designer aussi (même arbitrage).
update public.contacts set role = 'Product Designer'
 where statut in ('Consultant CDI','Freelance','Prestataire')
   and btrim(coalesce(role,'')) = '';

commit;

-- Vérifications -------------------------------------------------------------
-- Attendu : ~9 lignes de nomenclature + les 7 hors nomenclature laissés en l'état
-- (UX Writer ×3, Expert Accessibilité RGAA, OMS & Omnichannel Transformation Lead,
--  ARM Sanofi, Responsable commercial / delivery V35 EDF) — à trancher avec Nicolas.
select role, count(*) from public.contacts
 where statut in ('Consultant CDI','Freelance','Prestataire')
 group by 1 order by 2 desc, 1;
