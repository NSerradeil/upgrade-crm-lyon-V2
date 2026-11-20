-- 67 — BLOC 3/3 — VÉRIFICATION (lecture seule). Lancer : zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/67_garde_ancien_ecran_3_verif.sql
begin read only;
select tgname, tgrelid::regclass as table_, tgenabled from pg_trigger
 where tgname in ('trg_historique_garde_ancien_ecran','trg_taches_garde_ancien_ecran','trg_spc_garde_ancien_ecran','trg_sessions_garde_ancien_ecran','trg_sessions_garde_compteurs')
 order by 1;   -- attendu : 5 lignes, tgenabled = O
select count(*) as fonctions_db67 from pg_proc where proname in ('historique_garde_ancien_ecran','taches_garde_ancien_ecran',
  'spc_garde_ancien_ecran','sessions_garde_ancien_ecran','sessions_garde_compteurs');   -- attendu : 5
rollback;
