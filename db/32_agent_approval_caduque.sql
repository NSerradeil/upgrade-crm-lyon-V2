-- db/32_agent_approval_caduque.sql — Péremption du parapheur (agent_approvals).
-- Pourquoi : une entrée `pending` que Nicolas ne traite jamais reste indéfiniment
-- visible dans agent_v_parapheur et dans journal/a-valider.md, alors qu'elle n'a
-- souvent plus lieu d'être (contexte périmé). Règle Nicolas du 18/09 : passé 15
-- jours sans réponse, l'entrée devient `caduque` — elle sort de la vue (qui ne
-- montre que 'pending') SANS rien supprimer (traçabilité complète conservée dans
-- agent_approvals + un événement agent_events par entrée périmée, pour que le
-- brief du matin puisse les nommer). À coller dans le SQL Editor Supabase.
-- Idempotent.
begin;

-- 1) Étendre le check du statut pour accepter 'caduque' -----------------------
alter table public.agent_approvals drop constraint if exists agent_approvals_statut_check;
alter table public.agent_approvals add constraint agent_approvals_statut_check
  check (statut in ('pending', 'approved', 'rejected', 'answered', 'caduque'));

-- 2) Fonction de péremption ----------------------------------------------------
-- Passe en 'caduque' toutes les approbations 'pending' plus vieilles que
-- p_jours (15 par défaut), pour l'owner courant, journalise un événement par
-- ligne touchée et renvoie le nombre de lignes passées en 'caduque'.
-- owner_id est repris de chaque ligne d'approbation (pas de auth.uid()) car
-- cette fonction est appelée depuis le scheduler serveur, où auth.uid() est nul.
create or replace function public.agent_approvals_peremption(p_jours int default 15)
returns int language plpgsql security invoker as $$
declare n int;
begin
  with perimees as (
    update public.agent_approvals
       set statut = 'caduque'
     where statut = 'pending'
       and created_at < now() - make_interval(days => p_jours)
     returning id, owner_id, titre)
  insert into public.agent_events (owner_id, actor, kind, message)
  select owner_id, 'sched', 'approval.caduque', titre
    from perimees;
  get diagnostics n = row_count;
  return n;
end $$;

commit;

-- Vérification après application :
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--    where conrelid = 'public.agent_approvals'::regclass and conname = 'agent_approvals_statut_check';
--   select public.agent_approvals_peremption(15);
--   select id, statut, titre, created_at from public.agent_approvals where statut = 'caduque' order by created_at desc limit 20;
--   select * from public.agent_events where kind = 'approval.caduque' order by at desc limit 20;
