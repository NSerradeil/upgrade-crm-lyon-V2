-- ══════════════════════════════════════════════════════════════════════
-- 09 — Écriture élargie aux commerciaux + lecture ouverte (historique, tâches)
-- Date : 28/07/2026 · arbitrages Nicolas du 28/07
-- Spec : SPECS_CRM/SPEC_droits_ecriture_et_visibilite_inter_agences.md
--
-- OBJECTIF : tout commercial peut MODIFIER n'importe quel objet du CRM ;
-- SUPPRIMER reste réservé au responsable (ou à l'admin).
--
-- POURQUOI CETTE MIGRATION EXISTE : la 1re version de la spec affirmait « aucune
-- migration DB ». C'était faux — déduit d'un commentaire d'en-tête au lieu de
-- `pg_policies`. L'audit du 27-28/07 montre que `besoins`, `missions` et `taches`
-- restreignent l'UPDATE à `responsable = get_my_nom()`. Sans ce fichier, le chantier
-- livrerait des boutons « Modifier » actifs et des UPDATE rejetés EN SILENCE.
--
-- ÉTAT AVANT (audit complet du 28/07) :
--   comptes    SELECT true      · UPDATE true            → déjà ouvert, RIEN À FAIRE
--   contacts   SELECT true      · UPDATE admin|resp|agence → à élargir hors agence
--   missions   SELECT true      · UPDATE admin|resp        → à élargir
--   besoins    SELECT agence|resp (corrigé en db/08) · UPDATE admin|resp → à élargir
--   taches     SELECT admin|resp · UPDATE admin|resp       → à élargir (lecture ET écriture)
--   historique_actions SELECT admin|resp · INSERT true     → lecture à ouvrir
--
-- ⚠️ LIMITE ASSUMÉE — « on ne change pas le responsable d'une fiche » ne peut PAS
-- être garanti par RLS : une policy WITH CHECK ne voit que la ligne NOUVELLE, pas
-- l'ancienne, donc elle ne peut pas comparer l'ancien et le nouveau `responsable`.
-- Ce garde-fou est donc posé dans l'UI uniquement. Quelqu'un qui appellerait l'API
-- directement pourrait réattribuer une fiche. Si ça devient un vrai risque, il
-- faudra un TRIGGER BEFORE UPDATE — hors périmètre ici (YAGNI).
--
-- Le rôle `partner` n'est PAS touché : toutes les policies `*_partner_*` restent
-- en place à l'identique, et aucune policy ci-dessous ne l'inclut.
-- ══════════════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════════════
-- ① LECTURE — historique ouvert à la France entière (arbitrage Nicolas)
--
-- Motif : la trace automatique des modifications doit être lisible par le
-- PROPRIÉTAIRE de la fiche. Comme la ligne d'historique porte le nom de son
-- véritable auteur, `responsable = get_my_nom()` la rendait invisible à la seule
-- personne concernée. On ouvre la lecture à tous les commerciaux plutôt que de
-- falsifier l'auteur.
-- ══════════════════════════════════════════════════════════════════════

drop policy if exists read_historique on public.historique_actions;
create policy read_historique on public.historique_actions
  for select
  using (get_my_role() = any (array['admin','commercial']));
-- Le partner garde sa propre policy `ha_partner_read` (périmètre consultants).

-- Idem pour l'historique des missions, sinon un commercial voit la mission de son
-- agence mais pas son fil de suivi — incohérent.
drop policy if exists read_hist_missions on public.historique_missions;
create policy read_hist_missions on public.historique_missions
  for select
  using (get_my_role() = any (array['admin','commercial']));


-- ══════════════════════════════════════════════════════════════════════
-- ② LECTURE — tâches ouvertes à tous les commerciaux (arbitrage Nicolas)
--
-- Motif : `read_taches` limitait la lecture au destinataire. Conséquence du commit
-- ffe7278 (20/07) qui ouvrait la CRÉATION de tâches : on pouvait créer une tâche
-- pour un collègue et ne plus jamais la revoir. Piège, pas fonctionnalité.
--
-- Perf vérifiée avant décision (28/07) : `taches` = 1565 lignes / 0,90 Mo,
-- `historique_actions` = 3701 lignes / 1,26 Mo. L'admin charge DÉJÀ ces volumes
-- tous les jours sans souci — `fetchAll` n'a aucune limite par rôle. Le mobile est
-- déjà bridé (1000 tâches / 300 lignes d'historique) indépendamment du rôle.
-- Sur 1565 tâches, 322 sont actives, et le filtre responsable est par défaut sur
-- « moi » : la liste reste personnelle tant qu'on ne la déverrouille pas.
-- ══════════════════════════════════════════════════════════════════════

drop policy if exists read_taches on public.taches;
create policy read_taches on public.taches
  for select
  using (get_my_role() = any (array['admin','commercial']));

-- La création était déjà ouverte (`insert_taches_all_authenticated` = true), mais
-- `taches_insert_all` la re-restreignait au responsable. Les policies permissives
-- se combinant en OU, l'INSERT passait déjà — on nettoie quand même cette policy
-- devenue trompeuse pour qui relit les droits.
drop policy if exists taches_insert_all on public.taches;
create policy taches_insert_all on public.taches
  for insert
  with check (get_my_role() = any (array['admin','commercial']));


-- ══════════════════════════════════════════════════════════════════════
-- ③ ÉCRITURE — modifier oui, supprimer non
--
-- Méthode : les policies `ALL` existantes (write_*) mélangent UPDATE et DELETE
-- sous une seule condition `admin OR responsable`. On les remplace par des
-- policies SÉPARÉES par commande — sinon élargir la modification élargirait la
-- suppression du même coup. C'est le miroir exact du dédoublement
-- isOwner → canEdit / canDelete fait côté app.
-- ══════════════════════════════════════════════════════════════════════

-- ─── contacts : l'UPDATE était ouvert à l'agence, on l'ouvre à tous ───
drop policy if exists update_contacts on public.contacts;
drop policy if exists contacts_update_cross on public.contacts;
create policy contacts_update_all_commerciaux on public.contacts
  for update
  using      (get_my_role() = any (array['admin','commercial']))
  with check (get_my_role() = any (array['admin','commercial']));
-- DELETE inchangé : `delete_contacts` = admin OR responsable. On n'y touche pas.

-- ─── missions : write_missions (ALL) éclatée en UPDATE ouvert / DELETE fermé ───
drop policy if exists write_missions on public.missions;
create policy missions_update_all_commerciaux on public.missions
  for update
  using      (get_my_role() = any (array['admin','commercial']))
  with check (get_my_role() = any (array['admin','commercial']));
create policy missions_insert_commerciaux on public.missions
  for insert
  with check (get_my_role() = any (array['admin','commercial']));
create policy missions_delete_owner on public.missions
  for delete
  using (get_my_role() = 'admin' or responsable = get_my_nom());

-- ─── besoins : UPDATE ouvert, DELETE et INSERT inchangés ───
drop policy if exists besoins_commercial_update on public.besoins;
create policy besoins_update_all_commerciaux on public.besoins
  for update
  using      (get_my_role() = any (array['admin','commercial']))
  with check (get_my_role() = any (array['admin','commercial']));
-- `besoins_commercial_delete` (responsable) et `besoins_commercial_insert` : inchangés.
-- `besoins_admin_all` (ALL, admin) : inchangée.

-- ─── taches : write_taches (ALL) éclatée ───
drop policy if exists write_taches on public.taches;
create policy taches_update_all_commerciaux on public.taches
  for update
  using      (get_my_role() = any (array['admin','commercial']))
  with check (get_my_role() = any (array['admin','commercial']));
create policy taches_delete_owner on public.taches
  for delete
  using (get_my_role() = 'admin' or responsable = get_my_nom());

-- ─── historique_actions : l'auteur peut corriger sa propre ligne ───
drop policy if exists write_historique on public.historique_actions;
create policy historique_update_author on public.historique_actions
  for update
  using      (get_my_role() = 'admin' or responsable = get_my_nom())
  with check (get_my_role() = 'admin' or responsable = get_my_nom());
create policy historique_delete_author on public.historique_actions
  for delete
  using (get_my_role() = 'admin' or responsable = get_my_nom());
-- L'INSERT reste ouvert (`insert_actions_all_authenticated` = true) : c'est ce qui
-- permet à la trace automatique de s'écrire quel que soit l'auteur.

-- ─── historique_missions : idem ───
drop policy if exists write_hist_missions on public.historique_missions;
create policy hist_missions_write_commerciaux on public.historique_missions
  for update
  using      (get_my_role() = any (array['admin','commercial']))
  with check (get_my_role() = any (array['admin','commercial']));
create policy hist_missions_delete_admin on public.historique_missions
  for delete
  using (get_my_role() = 'admin');


-- ══════════════════════════════════════════════════════════════════════
-- ④ VÉRIFICATION
--
-- ⚠️ NE PAS tenter de vérifier en usurpant une identité ici : l'éditeur SQL
-- s'exécute sans JWT, `auth.uid()` est NULL, les get_my_*() renvoient NULL et
-- TOUTE policy évalue à faux. On lirait « 0 ligne » partout — faux négatif garanti.
-- Constaté le 27/07. La vérification se fait en relisant les policies, puis
-- DEPUIS L'APP avec un vrai compte commercial.
-- ══════════════════════════════════════════════════════════════════════

-- Photo finale : qui peut quoi, sur chaque table métier
SELECT tablename, cmd, policyname, qual AS lecture, with_check AS ecriture
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('contacts','comptes','besoins','missions','taches',
                    'historique_actions','historique_missions')
  AND policyname NOT LIKE '%partner%'
ORDER BY tablename, cmd, policyname;

-- Ce qu'on doit y lire, table par table :
--   SELECT  → ouvert (true, ou admin|commercial) partout
--   INSERT  → ouvert aux commerciaux partout
--   UPDATE  → ouvert aux commerciaux partout
--   DELETE  → admin OR responsable (contacts, besoins, missions, taches),
--             admin seul (comptes, historique_missions)

-- Contrôle : le partner n'a rien gagné. Ses policies doivent être intactes.
SELECT tablename, policyname, cmd FROM pg_policies
WHERE schemaname='public' AND policyname LIKE '%partner%'
ORDER BY tablename, policyname;
-- Attendu : les mêmes 13 policies `*_partner_*` qu'avant cette migration.


-- ══════════════════════════════════════════════════════════════════════
-- ROLLBACK — restaure l'état du 28/07 avant migration
-- ══════════════════════════════════════════════════════════════════════
-- drop policy if exists contacts_update_all_commerciaux on public.contacts;
-- create policy update_contacts on public.contacts for update
--   using ((get_my_role()='admin') or (responsable=get_my_nom()))
--   with check ((get_my_role()='admin') or (responsable=get_my_nom()));
-- create policy contacts_update_cross on public.contacts for update
--   using ((get_my_role()='admin') or (responsable=get_my_nom()) or (agence=get_my_agence()));
--
-- drop policy if exists missions_update_all_commerciaux on public.missions;
-- drop policy if exists missions_insert_commerciaux on public.missions;
-- drop policy if exists missions_delete_owner on public.missions;
-- create policy write_missions on public.missions for all
--   using ((get_my_role()='admin') or (responsable=get_my_nom()))
--   with check ((get_my_role()='admin') or (responsable=get_my_nom()));
--
-- drop policy if exists besoins_update_all_commerciaux on public.besoins;
-- create policy besoins_commercial_update on public.besoins for update
--   using ((get_my_role()='commercial') and (responsable=get_my_nom()))
--   with check ((get_my_role()='commercial') and (responsable=get_my_nom()));
--
-- drop policy if exists taches_update_all_commerciaux on public.taches;
-- drop policy if exists taches_delete_owner on public.taches;
-- create policy write_taches on public.taches for all
--   using ((get_my_role()='admin') or (responsable=get_my_nom()))
--   with check ((get_my_role()='admin') or (responsable=get_my_nom()));
-- drop policy if exists read_taches on public.taches;
-- create policy read_taches on public.taches for select
--   using ((get_my_role()='admin') or (responsable=get_my_nom()));
-- drop policy if exists taches_insert_all on public.taches;
-- create policy taches_insert_all on public.taches for insert
--   with check ((get_my_role()='admin') or (responsable=get_my_nom()));
--
-- drop policy if exists historique_update_author on public.historique_actions;
-- drop policy if exists historique_delete_author on public.historique_actions;
-- create policy write_historique on public.historique_actions for all
--   using ((get_my_role()='admin') or (responsable=get_my_nom()))
--   with check ((get_my_role()='admin') or (responsable=get_my_nom()));
-- drop policy if exists read_historique on public.historique_actions;
-- create policy read_historique on public.historique_actions for select
--   using ((get_my_role()='admin') or (responsable=get_my_nom()));
--
-- drop policy if exists hist_missions_write_commerciaux on public.historique_missions;
-- drop policy if exists hist_missions_delete_admin on public.historique_missions;
-- create policy write_hist_missions on public.historique_missions for all
--   using ((get_my_role()='admin') or (exists (select 1 from missions m
--     where m.id=historique_missions.mission_id and m.responsable=get_my_nom())))
--   with check ((get_my_role()='admin') or (exists (select 1 from missions m
--     where m.id=historique_missions.mission_id and m.responsable=get_my_nom())));
-- drop policy if exists read_hist_missions on public.historique_missions;
-- create policy read_hist_missions on public.historique_missions for select
--   using ((get_my_role()='admin') or (exists (select 1 from missions m
--     where m.id=historique_missions.mission_id and m.responsable=get_my_nom())));
