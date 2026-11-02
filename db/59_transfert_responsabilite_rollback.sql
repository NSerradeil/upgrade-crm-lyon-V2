-- ══════════════════════════════════════════════════════════════════════
-- 59 — Transfert de responsabilité — ROLLBACK
--
-- Retire la fonction et le journal. NE remet PAS les anciens responsables : un transfert fait est
-- une décision métier. Pour annuler un transfert précis, l'admin le refait en sens inverse (le
-- journal donne l'ancien responsable) AVANT de lancer ce rollback, ou exporte d'abord le journal :
--   select * from public.transferts_responsabilite order by created_at;
--
-- ⚠️ À lancer APRÈS avoir retiré le bouton de l'app (sinon le bouton renvoie une erreur « fonction
-- introuvable », proprement affichée, rien de cassé).
--
--   zsh ~/Pro/Jules/bin/macmini/crm-sql.sh db/59_transfert_responsabilite_rollback.sql
-- ══════════════════════════════════════════════════════════════════════

begin;

-- Sauvegarde du journal avant suppression (si des transferts ont eu lieu).
create table if not exists public._transferts_responsabilite_bak as
  select * from public.transferts_responsabilite where false;
insert into public._transferts_responsabilite_bak select * from public.transferts_responsabilite;
alter table public._transferts_responsabilite_bak enable row level security;
revoke all on public._transferts_responsabilite_bak from anon, authenticated;

drop function if exists public.transferer_responsabilite(text, bigint, text);
drop table if exists public.transferts_responsabilite;

notify pgrst, 'reload schema';

commit;

-- Vérification : attendu 0 ligne.
select proname from pg_proc where pronamespace = 'public'::regnamespace and proname = 'transferer_responsabilite'
union all
select relname from pg_class where relnamespace = 'public'::regnamespace and relname = 'transferts_responsabilite';
