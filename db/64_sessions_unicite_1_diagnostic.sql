-- ══════════════════════════════════════════════════════════════════════
-- 64 — Sessions d'appel : une seule ligne par (session, contact)   (20/11/2026, tranche T0)
-- BLOC 1/3 — DIAGNOSTIC (lecture seule, aucun nom de contact, agrégats seulement)
--
-- Contexte : à la clôture d'une session (« Terminer »), le CRM faisait un upsert sans clé de conflit sur
-- session_prospection_contacts : les résultats s'AJOUTAIENT à côté des lignes de départ (statut 'none')
-- au lieu de les remplacer. Ce bloc mesure l'état avant le passage du bloc 2.
--
-- Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/64_sessions_unicite_1_diagnostic.sql
-- ══════════════════════════════════════════════════════════════════════

begin read only;

-- 1. Volume par statut de session : lignes, couples (session, contact) distincts, lignes avec résultat
select s.statut, count(distinct s.id) as sessions, count(c.*) as lignes,
       count(distinct (c.session_id, c.contact_id)) as couples,
       count(*) filter (where c.statut <> 'none') as lignes_avec_resultat
  from public.sessions_prospection s
  left join public.session_prospection_contacts c on c.session_id = s.id
 group by 1 order by 1;

-- 2. Doublons : couples en double, lignes en trop, et nature (une ligne résultat + une 'none', ou deux 'none')
with g as (
  select session_id, contact_id, count(*) n, count(*) filter (where statut <> 'none') nres
    from public.session_prospection_contacts group by 1, 2 having count(*) > 1)
select count(*) as couples_en_double,
       sum(n - 1) as lignes_a_supprimer,
       count(*) filter (where nres = 1) as resultat_plus_none,
       count(*) filter (where nres = 0) as none_plus_none,
       count(*) filter (where nres > 1) as deux_resultats_STOP_si_non_nul
  from g;

-- 3. Répartition des lignes à supprimer par commercial (initiales) et statut de session
with r as (
  select c.*, row_number() over (partition by c.session_id, c.contact_id
                                 order by (c.statut <> 'none') desc, c.created_at desc, c.id desc) rn
    from public.session_prospection_contacts c)
select upper(left(split_part(s.responsable, ' ', 1), 1) || left(split_part(s.responsable, ' ', 2), 1)) as qui,
       s.statut, count(*) filter (where r.rn > 1) as lignes_a_supprimer,
       count(*) filter (where r.rn > 1 and r.statut <> 'none') as dont_resultat_STOP_si_non_nul
  from r join public.sessions_prospection s on s.id = r.session_id
 group by 1, 2 order by 1, 2;

-- 4. Compteurs des sessions terminées : stockés = recalculés (contacts distincts) ?
with x as (
  select session_id,
         count(distinct contact_id) filter (where statut <> 'none') nb_c,
         count(distinct contact_id) filter (where statut = 'interested') nb_i,
         count(distinct contact_id) filter (where statut = 'unreachable') nb_u,
         count(distinct contact_id) filter (where statut = 'not_interested') nb_p,
         count(distinct contact_id) filter (where statut = 'called') nb_a
    from public.session_prospection_contacts group by 1)
select count(*) as sessions_terminees,
       count(*) filter (where s.nb_contacts = x.nb_c and s.nb_interesses = x.nb_i and s.nb_injoignables = x.nb_u) as compteurs_coherents,
       sum(s.nb_contacts) sum_nb_contacts, sum(s.nb_interesses) sum_nb_interesses,
       sum(s.nb_injoignables) sum_nb_injoignables, sum(s.nb_relances) sum_nb_relances,
       sum(x.nb_p) pas_interesses, sum(x.nb_a) appeles_seuls
  from public.sessions_prospection s join x on x.session_id = s.id
 where s.statut = 'done';

-- 5. Lecteurs qui comptent des lignes SANS filtrer le statut (ce qui bougera à l'écran)
--    a. badge « Prospecteur » (index.html:857) : lignes des sessions 2026 de chaque commercial
select upper(left(split_part(s.responsable, ' ', 1), 1) || left(split_part(s.responsable, ' ', 2), 1)) as qui,
       count(*) as badge_prospecteur_avant,
       count(distinct (c.session_id, c.contact_id)) as badge_prospecteur_apres
  from public.session_prospection_contacts c join public.sessions_prospection s on s.id = c.session_id
 where s.date_session >= '2026-01-01' and s.date_session < '2027-01-01'
 group by 1 order by 1;
--    b. carte « PAS INTÉRESSÉS » (index.html:9090) : lignes not_interested (les doublons sont des 'none' : inchangé)
select count(*) as carte_pas_interesses from public.session_prospection_contacts where statut = 'not_interested';

-- 6. Prérequis du bloc 2
select (select count(*) from pg_constraint where conrelid = 'public.session_prospection_contacts'::regclass and contype = 'u') as contraintes_unicite_existantes,
       to_regclass('public._spc_bak_20261120') as sauvegarde_deja_la,
       (select md5(prosrc) from pg_proc where oid = 'public.fusionner_contacts(bigint,bigint,text,text)'::regprocedure) as md5_fusionner_contacts_attendu_b9baabcdc516526e2d1488bf5bcce84e;

rollback;
