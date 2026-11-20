-- ══════════════════════════════════════════════════════════════════════
-- 68 — La fusion de contacts recolle les profils de dossier Jules — BLOC 1/3 — DIAGNOSTIC (lecture seule)
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/68_fusion_recolle_jules_1_diagnostic.sql
-- Rien n'est écrit (transaction en lecture seule, annulée à la fin).
-- ══════════════════════════════════════════════════════════════════════
begin transaction read only;

-- D1. Empreintes des fonctions remplacées par le bloc 2 (relevé du 20/11, avant 68) :
--     _fusion_defaire = 03d8a9d222ea9e997a03651c339bd8b2 · _fusion_photo = 8783cfebd9edd79e081fc8e232d96b32
--     fusionner_contacts = 8a04a9bf25f9f50d8389eea6c008fa8f · restaurer_fiche / supprimer_fiche non modifiées.
select proname, md5(prosrc), prosrc ~ 'db/68' as deja_68 from pg_proc
 where pronamespace = 'public'::regnamespace
   and proname in ('fusionner_contacts','_fusion_photo','_fusion_defaire','restaurer_fiche','supprimer_fiche') order by 1;

-- D2. Clés étrangères vers public.contacts. Relevé du 20/11 : 13, dont jules.profils_mission(crm_contact_id) « set null »,
--     la seule que fusionner_contacts ne déplaçait pas (les 12 autres le sont depuis 63).
select conrelid::regclass as table_, a.attname as colonne, confdeltype as on_delete
  from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any (c.conkey)
 where c.contype = 'f' and c.confrelid = 'public.contacts'::regclass order by 1, 2;

-- D3. Références sans clé étrangère vers un contact qui n'existe plus (orphelins). Relevé du 20/11 :
--     taches.contact_id 39 (anciennes tâches tw_* d'avril, aucune vers une fiche fusionnée), besoins_statuts 6 (ancien suivi),
--     les autres 0.
select 'taches.contact_id' as colonne, count(*) as orphelins from public.taches t
 where contact_id is not null and not exists (select 1 from public.contacts c where c.id = t.contact_id)
union all select 'besoins_statuts.contact_id', count(*) from public.besoins_statuts b
 where contact_id ~ '^\d+$' and not exists (select 1 from public.contacts c where c.id = b.contact_id::bigint)
union all select 'jules.alertes_double_contact.contact_id', count(*) from jules.alertes_double_contact a
 where contact_id is not null and not exists (select 1 from public.contacts c where c.id = a.contact_id)
union all select 'jules.agent_sequences.target_ref (contact_crm)', count(*) from jules.agent_sequences s
 where target_kind = 'contact_crm' and target_ref ~ '^\d+$' and not exists (select 1 from public.contacts c where c.id = s.target_ref::bigint)
union all select 'jules.partages_compte.contacts_exclus', count(*) from jules.partages_compte p
 where exists (select 1 from unnest(p.contacts_exclus) x where not exists (select 1 from public.contacts c where c.id = x))
union all select 'jules.profils_mission.crm_contact_id', count(*) from jules.profils_mission p
 where crm_contact_id is not null and not exists (select 1 from public.contacts c where c.id = p.crm_contact_id);

-- D4. Fusions passées (tracées dans la corbeille) et profils de dossier qui auraient perdu leur fiche à cause d'elles
--     (même LinkedIn ou même nom que le doublon, fiche vide). Relevé du 20/11 : 3 archives (77 test du 11/11, 80, 81),
--     0 profil concerné : rien à rattraper.
select k.id as archive, k.objet_id as doublon, k.liens -> 'fusion' ->> 'garde' as garde, k.supprime_le, k.restaure_le
  from public.corbeille k where k.objet_type = 'contact' and (k.liens ? 'fusion' or k.motif ~* 'fusion') order by k.id;
select k.id as archive, p.id as profil, p.nom, p.crm_contact_id
  from public.corbeille k join jules.profils_mission p
    on (jules.normaliser_linkedin(p.lien) = jules.normaliser_linkedin(k.ligne ->> 'linkedin'))
    or lower(btrim(p.nom)) = lower(btrim(coalesce(k.ligne ->> 'prenom', '') || ' ' || coalesce(k.ligne ->> 'nom', '')))
 where k.objet_type = 'contact' and (k.liens ? 'fusion' or k.motif ~* 'fusion') and p.crm_contact_id is null;

-- D5. Droits (doit rester vrai / faux / faux).
select has_function_privilege('authenticated', 'public.fusionner_contacts(bigint,bigint,text,text)', 'execute') as fusion_authenticated,
       has_function_privilege('authenticated', 'public._fusion_defaire(jsonb)', 'execute') as defaire_authenticated,
       has_function_privilege('authenticated', 'public._fusion_photo(bigint)', 'execute') as photo_authenticated;

rollback;
