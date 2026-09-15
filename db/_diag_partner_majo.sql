-- DIAGNOSTIC — pourquoi le rôle partner ne s'applique pas à Maria-José
-- Lance d'ABORD ce SELECT, regarde la colonne role :
select id, nom, agence, role
from public.profiles
where nom ilike '%paquelier%';
-- Attendu pour que la logique partner marche : role = 'partner' (en minuscules, exact).
-- Si role est NULL / 'Partner' / autre → c'est la cause. Corrige avec le bloc ci-dessous.

-- ── FIX (à lancer seulement si le role n'est pas déjà 'partner') ──
-- Met le rôle partner + agence neutre 'Partner' (évite les fuites par agence).
update public.profiles
set role='partner', agence='Partner'
where nom ilike '%paquelier%';

-- Puis (ré)affecte son auto-visibilité maintenant que role='partner' (l'insert de db/05
-- n'avait rien fait si le role n'était pas bon) :
insert into public.partner_consultants (partner_id, contact_consultant_id)
select p.id, 373 from public.profiles p
where p.role='partner' and p.nom ilike '%paquelier%'
on conflict do nothing;

-- Vérif finale : son périmètre (doit lister ses consultants + 373 = elle-même) :
select pc.contact_consultant_id, c.prenom, c.nom
from public.partner_consultants pc
join public.profiles p on p.id = pc.partner_id
join public.contacts c on c.id = pc.contact_consultant_id
where p.nom ilike '%paquelier%'
order by 1;
