-- 67 — BLOC 1/3 — DIAGNOSTIC (lecture seule). Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/67_garde_ancien_ecran_1_diagnostic.sql
begin read only;
select 'porte db/65-66' as quoi, count(*) as n from pg_proc where proname = 'enregistrer_resultat_appel'
union all select 'terminer_session_appel', count(*) from pg_proc where proname = 'terminer_session_appel'
union all select 'db/67 déjà passée', count(*) from pg_proc where proname = 'spc_garde_ancien_ecran'
union all select 'sessions en cours', count(*) from public.sessions_prospection where statut = 'active'
union all select 'sessions en cours avec résultat porte', count(distinct c.session_id) from public.session_prospection_contacts c
  join public.sessions_prospection s on s.id = c.session_id where s.statut = 'active' and c.geste_at is not null and c.statut <> 'none'
union all select 'lignes porte (toutes)', count(*) from public.session_prospection_contacts where geste_at is not null;
rollback;
