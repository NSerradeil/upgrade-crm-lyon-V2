-- ══════════════════════════════════════════════════════════════════════
-- 64 — BLOC 3/3 — VÉRIFICATION après passage (lecture seule, agrégats seulement)
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/64_sessions_unicite_3_verif.sql
-- ══════════════════════════════════════════════════════════════════════

begin read only;

-- 1. Plus aucun doublon ; contrainte et trigger en place
select (select count(*) from (select 1 from public.session_prospection_contacts group by session_id, contact_id having count(*) > 1) d) as doublons_attendu_0,
       (select count(*) from pg_constraint where conname = 'spc_session_contact_uniq') as contrainte_attendu_1,
       (select count(*) from pg_trigger where tgname = 'trg_spc_insertion_remplace' and tgenabled = 'O') as trigger_attendu_1,
       (select position('y.session_id = x.session_id' in prosrc) > 0 from pg_proc where oid = 'public.fusionner_contacts(bigint,bigint,text,text)'::regprocedure) as fusion_corrigee;

-- 2. Lignes : actuelles + supprimées = sauvegarde ; toutes les supprimées étaient 'none'
select (select count(*) from public._spc_bak_20261120) as lignes_avant,
       (select count(*) from public.session_prospection_contacts) as lignes_apres,
       (select count(*) from public._spc_bak_20261120 b where not exists (select 1 from public.session_prospection_contacts c where c.id = b.id)) as supprimees,
       (select count(*) from public._spc_bak_20261120 b where b.statut <> 'none' and not exists (select 1 from public.session_prospection_contacts c where c.id = b.id)) as supprimees_avec_resultat_attendu_0;

-- 3. Par session : compteurs stockés et résultats par statut identiques à la sauvegarde
with av as (
  select s.id, s.nb_contacts, s.nb_interesses, s.nb_relances, s.nb_injoignables,
         count(*) filter (where c.statut <> 'none') res, count(distinct c.contact_id) couples
    from public._sessions_prospection_bak_20261120 s left join public._spc_bak_20261120 c on c.session_id = s.id group by 1, 2, 3, 4, 5),
ap as (
  select s.id, s.nb_contacts, s.nb_interesses, s.nb_relances, s.nb_injoignables,
         count(*) filter (where c.statut <> 'none') res, count(distinct c.contact_id) couples
    from public.sessions_prospection s left join public.session_prospection_contacts c on c.session_id = s.id group by 1, 2, 3, 4, 5)
select count(*) as sessions, count(*) filter (where (av.*)::text = (ap.*)::text) as identiques
  from av join ap using (id);

-- 4. Onglet Prosp. d'Anne-Claire (sessions terminées 2026) : sessions, contacts, intéressants, injoignables, pas intéressés
select count(*) as sessions, sum(s.nb_contacts) as contacts, sum(s.nb_interesses) as interessants,
       sum(s.nb_injoignables) as injoignables, sum(s.nb_relances) as relances,
       (select count(*) from public.session_prospection_contacts c join public.sessions_prospection s2 on s2.id = c.session_id
         where s2.responsable like 'Anne-Claire%' and c.statut = 'not_interested') as pas_interesses
  from public.sessions_prospection s
 where s.responsable like 'Anne-Claire%' and s.statut = 'done' and s.date_session >= '2026-01-01';

rollback;
