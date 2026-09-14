-- db/22_responsabilites.sql — « Responsabilité » d'un collaborateur + liste des partners vivante.
-- À coller dans le SQL Editor Supabase. Idempotent.
--
-- Trois notions de « rôle » coexistent, à ne pas confondre :
--   · profiles.role        = accès au CRM        (admin / commercial / partner)
--   · contacts.role        = poste               (« Product Owner », « Consultant CDI »…)
--   · contacts.responsabilite = casquette agence (partner, référent·e…)   ← AJOUTÉ ICI
begin;

-- 1) Responsabilité --------------------------------------------------------
alter table public.contacts add column if not exists responsabilite text;
alter table public.contacts drop constraint if exists contacts_responsabilite_check;
alter table public.contacts add constraint contacts_responsabilite_check
  check (responsabilite is null or responsabilite in
    ('partner','lead_partner','referent_technique','referent_design_ops'));
-- null = salarié·e sans casquette particulière (le cas général).

-- 2) Trigramme : identifiant court d'un partner, déjà utilisé dans l'Excel et les objets de mail.
--    Présent des deux côtés car un « partner responsable » est soit un consultant (contacts),
--    soit un commercial (profiles).
alter table public.contacts add column if not exists trigramme text;
alter table public.profiles add column if not exists trigramme text;

-- 3) Seeds — les 10 consultants qui managent, + les 2 référentes ------------
update public.contacts c set responsabilite = v.resp, trigramme = v.tri
from (values
  ('JACQUEMIN','Cassandre','CAJ','lead_partner'),
  ('PAQUELIER','Maria-Jose','MJP','partner'),
  ('BLANDIN','Louis','LBL','partner'),
  ('PLANCOULAINE','Anthony','APL','partner'),
  ('SAWICKI','Weronika','WSA','partner'),
  ('ELMOZNINO','Fabrice','FEL','partner'),
  ('SINPASEUTH','Hervé','HSI','partner'),
  ('LE MOY','Stanislas','SLE','partner'),
  ('SENDRA','Julian','JSE','partner'),
  ('SALEM','Constance','COS','partner')
) as v(nom,prenom,tri,resp)
where c.nom = v.nom and c.prenom = v.prenom and c.statut = 'Consultant CDI';

update public.contacts set responsabilite = 'referent_technique'
 where nom = 'DUBET' and prenom = 'Maylis' and statut = 'Consultant CDI';
update public.contacts set responsabilite = 'referent_design_ops'
 where nom = 'ROUGER' and prenom = 'Justine' and statut = 'Consultant CDI';

-- 4) Trigrammes des commerciaux (ils managent aussi des consultants) --------
update public.profiles p set trigramme = v.tri from (values
  ('Nicolas Serradeil','NSE'), ('Anne Claire Decker','ACD'), ('Camille Salinson','CSA'),
  ('Amel Benzai','ABE'), ('Pierre Solle','PSO'), ('Louis Py','LPY'),
  ('Maria-Jose Paquelier','MJP')
) as v(nom,tri) where p.nom = v.nom;

-- 5) Qui peut réaffecter : admin, directeur d'agence ET lead partner --------
create or replace function public.can_manage_partners()
returns boolean language sql stable security definer
set search_path = public as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and (p.role = 'admin' or p.dir_agence or p.partner_lead)
  );
$$;

-- 6) Ménage : type_presta recopiait statut (doublon dans le formulaire) -----
-- On l'aligne une fois pour toutes ; l'app le déduira désormais du statut.
update public.contacts set type_presta = 'freelance'
 where statut = 'Freelance' and coalesce(type_presta,'') <> 'freelance';
update public.contacts set type_presta = 'sous_traitant'
 where statut = 'Prestataire' and coalesce(type_presta,'') <> 'sous_traitant';

commit;

-- 7) Vérifications ---------------------------------------------------------
select responsabilite, count(*) from public.contacts
 where responsabilite is not null group by 1 order by 1;        -- lead_partner 1, partner 9, référents 1+1
select nom, prenom, trigramme, responsabilite from public.contacts
 where trigramme is not null order by nom;                      -- 10 lignes
select nom, role, trigramme, dir_agence, partner_lead from public.profiles order by nom;
select statut, type_presta, count(*) from public.contacts
 where statut in ('Freelance','Prestataire') group by 1,2;      -- 2 lignes, plus aucun écart
