-- 50 — Un rc=0 sans agent_task_done n'est plus compté `done`
--
-- Cas vécu 25/09 (tâche Jules 8b9009e9, « Relever les réponses LinkedIn en attente ») :
-- le worker a buté sur un Chrome CDP injoignable, déposé une approbation de blocage,
-- alerté Nicolas, puis s'est arrêté sans jamais appeler `agent_task_done`. Il est sorti
-- en rc=0. Le scheduler (bin/jules-scheduler.py) clôturait alors systématiquement en
-- `done` avec pour tout compte rendu `{"rc": 0, "note": "worker terminé sans
-- agent_task_done"}` — zéro réponse relevée, mais l'état affirmait que c'était fait.
--
-- Nouveau statut `sans_cr` : une sortie silencieuse du worker (rc=0, jamais d'appel à
-- `agent_task_done`) — distinct de `done` (le worker a positivement rendu un résultat,
-- y compris un no-op assumé du type « rien de nouveau, clos en silence ») et de `failed`
-- (le worker a planté / rendu un code non nul). Terminal comme les deux : une mission
-- récurrente reprend normalement à la prochaine échéance de cadence, mais le CR horaire
-- et le bilan santé (bin/jules-cr-horaire.py, bin/jules-healthcheck-signals.py) doivent
-- pouvoir la distinguer d'une vraie réussite.

alter table public.agent_tasks
  drop constraint if exists agent_tasks_statut_check;
alter table public.agent_tasks
  add constraint agent_tasks_statut_check
  check (statut in ('due','claimed','waiting_go','done','failed','cancelled','sans_cr'));
