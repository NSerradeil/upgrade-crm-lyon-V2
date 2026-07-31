-- ══════════════════════════════════════════════════════════════════════
-- 12 — Deux points sortis du balayage RLS complet du 31/07
--   A. `mission_periods` cloisonnée par responsable alors que `missions` est ouverte
--   B. VÉRIFIER si la partie ① de db/09 (lecture des historiques) a bien été appliquée
-- ══════════════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════════════
-- B. À FAIRE EN PREMIER — vérifier avant de corriger
--
-- La carte des droits montre `read_historique` et `read_hist_missions` en
-- « par RESPONSABLE », alors que db/09 les avait réécrites en « admin OU commercial ».
-- `read_taches`, écrite dans le MÊME fichier, est bien passée. Soit le fichier a été
-- exécuté par morceaux, soit une erreur a interrompu la section ①.
--
-- CE QUE ÇA CHANGE SI C'EST CONFIRMÉ : la trace automatique des modifications (commit
-- ff325ff) écrit la ligne d'historique au nom de son VRAI auteur. Si la lecture reste
-- limitée à `responsable = get_my_nom()`, le propriétaire de la fiche — le seul que ça
-- intéresse — ne voit jamais la trace. La fonctionnalité serait inopérante.
-- ══════════════════════════════════════════════════════════════════════

SELECT tablename, policyname, qual AS condition_lecture
FROM pg_policies
WHERE schemaname = 'public'
  AND policyname IN ('read_historique','read_hist_missions','read_taches')
ORDER BY tablename;
-- Attendu SI db/09 a bien été appliqué en entier :
--     les trois portent `get_my_role() = ANY (ARRAY['admin','commercial'])`
-- Si `read_historique` ou `read_hist_missions` contient encore `get_my_nom()`,
-- appliquer le rattrapage ci-dessous.


-- ─── RATTRAPAGE de db/09 § ① (à ne lancer que si la vérif le confirme) ───
drop policy if exists read_historique on public.historique_actions;
create policy read_historique on public.historique_actions
  for select
  using (get_my_role() = any (array['admin','commercial']));

drop policy if exists read_hist_missions on public.historique_missions;
create policy read_hist_missions on public.historique_missions
  for select
  using (get_my_role() = any (array['admin','commercial']));


-- ══════════════════════════════════════════════════════════════════════
-- A. `mission_periods` — aligner sur `missions`
--
-- État relevé le 31/07 :
--     read_mission_periods  (SELECT) : par responsable de la mission
--     write_mission_periods (ALL)    : par responsable de la mission
--
-- Or `missions_select_all` est à `true` et le pré-filtre app `vMissions` a été ouvert à
-- l'agence le 28/07 (commit c021efe). Conséquence AUJOURD'HUI EN PROD : un commercial
-- voit la mission d'un collègue mais sa section « périodes » est vide — pas de
-- renouvellements, pas de n° de commande, pas de TJM par période. Et depuis 269ab97 le
-- n° de commande de la racine est justement alimenté par la période active : il voit
-- donc un numéro sans pouvoir consulter la période d'où il vient.
--
-- Personne ne l'a encore signalé. C'est le 4e cas du même défaut, trouvé par balayage
-- plutôt que par un collègue bloqué.
-- ══════════════════════════════════════════════════════════════════════

-- Lecture : ouverte aux commerciaux, comme les missions elles-mêmes.
drop policy if exists read_mission_periods on public.mission_periods;
create policy read_mission_periods on public.mission_periods
  for select
  using (get_my_role() = any (array['admin','commercial']));

-- Écriture : ouverte aux commerciaux (cohérent avec db/09 sur missions), mais on éclate
-- le ALL pour ne PAS ouvrir la suppression du même coup — une période supprimée fait
-- perdre un historique de renouvellement et de facturation.
drop policy if exists write_mission_periods on public.mission_periods;

create policy mission_periods_insert on public.mission_periods
  for insert
  with check (get_my_role() = any (array['admin','commercial']));

create policy mission_periods_update on public.mission_periods
  for update
  using      (get_my_role() = any (array['admin','commercial']))
  with check (get_my_role() = any (array['admin','commercial']));

-- Suppression : l'admin, le créateur de la période, ou le responsable de la mission.
create policy mission_periods_delete on public.mission_periods
  for delete
  using (
    get_my_role() = 'admin'
    or created_by = get_my_nom()
    or exists (select 1 from missions m
               where m.id = mission_periods.mission_id and m.responsable = get_my_nom())
  );


-- ══════════════════════════════════════════════════════════════════════
-- VÉRIFICATION
-- ══════════════════════════════════════════════════════════════════════
SELECT tablename, cmd, policyname, coalesce(qual, with_check) AS condition
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('mission_periods','historique_actions','historique_missions')
  AND policyname NOT LIKE '%partner%'
ORDER BY tablename, cmd, policyname;

-- ⚠️ Comme toujours : ces policies ne se testent PAS depuis l'éditeur SQL (auth.uid()
-- y est NULL, donc tout est refusé — faux négatif garanti). Le vrai test : un commercial
-- ouvre la mission d'un collègue et voit ses périodes ; et il voit dans l'historique
-- d'une de ses fiches la trace laissée par quelqu'un d'autre.


-- ══════════════════════════════════════════════════════════════════════
-- ROLLBACK — état du 31/07 avant ce fichier
-- ══════════════════════════════════════════════════════════════════════
-- drop policy if exists mission_periods_insert on public.mission_periods;
-- drop policy if exists mission_periods_update on public.mission_periods;
-- drop policy if exists mission_periods_delete on public.mission_periods;
-- drop policy if exists read_mission_periods on public.mission_periods;
-- create policy read_mission_periods on public.mission_periods for select
--   using ((get_my_role() = 'admin') or (exists (select 1 from missions m
--     where m.id = mission_periods.mission_id and m.responsable = get_my_nom())));
-- create policy write_mission_periods on public.mission_periods for all
--   using ((get_my_role() = 'admin') or (exists (select 1 from missions m
--     where m.id = mission_periods.mission_id and m.responsable = get_my_nom())))
--   with check ((get_my_role() = 'admin') or (exists (select 1 from missions m
--     where m.id = mission_periods.mission_id and m.responsable = get_my_nom())));
--
-- (Le rollback de la partie B est le contenu d'origine relevé par la requête de vérif :
--  le noter avant de lancer le rattrapage.)
