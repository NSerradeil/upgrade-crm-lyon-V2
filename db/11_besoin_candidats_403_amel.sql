-- ══════════════════════════════════════════════════════════════════════
-- 11 — `besoin_candidats` : 403 RLS au positionnement d'un candidat
-- Date : 31/07/2026
--
-- SIGNALÉ PAR AMEL : impossible de positionner Elena Codreanu (contact 1142) sur le
-- besoin « UX Research - CATS - Chapitre UX UI » (839ef93e-e6bc-48f4-a629-736bd4aff434).
-- Erreur : 403, row-level security policy sur `besoin_candidats`.
--
-- ⚠️ SON HYPOTHÈSE EST À ÉCARTER : elle soupçonnait le statut « Consultant CDI » d'Elena.
-- Les policies RLS ne regardent pas le statut du contact. Les faits :
--
--     besoin 839ef93e…  responsable = 'Amel Benzai'   agence = 'Lyon'
--     Amel Benzai       agence      = 'Paris'
--
-- Amel est DÉJÀ responsable du besoin et reste bloquée → la policy ne teste pas la
-- propriété mais très probablement l'AGENCE, via un EXISTS sur `besoins`.
--
-- C'est le MÊME motif que le bug de Louis Py (db/08) : une condition d'agence sans
-- échappatoire par le responsable, sur un besoin rattaché à une autre agence que celle
-- de son propriétaire. Troisième occurrence du même défaut. `besoin_candidats` n'était
-- pas dans le périmètre de l'audit du 28/07 (db/09) : c'est le trou à combler.
-- ══════════════════════════════════════════════════════════════════════


-- ─── ÉTAPE 1 — CONFIRMER avant de corriger ───
-- (je n'ai pas pu lire pg_policies : non exposé via l'API REST)
SELECT policyname, cmd, roles,
       qual       AS condition_lecture,
       with_check AS condition_ecriture
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'besoin_candidats'
ORDER BY cmd, policyname;
-- Ce qu'on cherche : une condition contenant `get_my_agence()`. Si c'est le cas,
-- l'hypothèse est confirmée et l'ÉTAPE 2 s'applique.
-- Si à la place on voit `get_my_nom()` seul, ou une condition sur le rôle, STOP :
-- me le renvoyer, le correctif ci-dessous ne serait pas le bon.

-- Contexte utile à afficher en même temps
SELECT b.id, b.titre, b.responsable, b.agence AS agence_besoin,
       p.agence AS agence_du_responsable
FROM besoins b LEFT JOIN profiles p ON p.nom = b.responsable
WHERE b.id = '839ef93e-e6bc-48f4-a629-736bd4aff434';
-- Attendu : responsable Amel Benzai · agence_besoin Lyon · agence_du_responsable Paris


-- ─── ÉTAPE 2 — LE CORRECTIF ───
-- On aligne `besoin_candidats` sur ce que db/09 a fait ailleurs : lecture et écriture
-- ouvertes aux commerciaux, suppression réservée à l'auteur du lien ou à l'admin.
-- Positionner un candidat sur un besoin est une action de staffing quotidienne : la
-- cloisonner par agence empêche justement le travail inter-agences qu'on vient d'ouvrir.

drop policy if exists besoin_candidats_select on public.besoin_candidats;
drop policy if exists besoin_candidats_commercial_select on public.besoin_candidats;
create policy besoin_candidats_select on public.besoin_candidats
  for select
  using (get_my_role() = any (array['admin','commercial']));

drop policy if exists besoin_candidats_insert on public.besoin_candidats;
drop policy if exists besoin_candidats_commercial_insert on public.besoin_candidats;
create policy besoin_candidats_insert on public.besoin_candidats
  for insert
  with check (get_my_role() = any (array['admin','commercial']));

drop policy if exists besoin_candidats_update on public.besoin_candidats;
drop policy if exists besoin_candidats_commercial_update on public.besoin_candidats;
create policy besoin_candidats_update on public.besoin_candidats
  for update
  using      (get_my_role() = any (array['admin','commercial']))
  with check (get_my_role() = any (array['admin','commercial']));

-- Suppression : l'auteur du lien ou l'admin. On ne défait pas le positionnement d'un
-- collègue par mégarde.
drop policy if exists besoin_candidats_delete on public.besoin_candidats;
drop policy if exists besoin_candidats_commercial_delete on public.besoin_candidats;
create policy besoin_candidats_delete on public.besoin_candidats
  for delete
  using (get_my_role() = 'admin' or created_by = get_my_nom());

-- ⚠️ Les policies `*_partner_*` de cette table, s'il en existe, ne sont PAS touchées :
-- les DROP ci-dessus ne visent que des noms explicites. Vérifier à l'étape 3.


-- ─── ÉTAPE 3 — VÉRIFIER ───
SELECT policyname, cmd, qual AS lecture, with_check AS ecriture
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'besoin_candidats'
ORDER BY cmd, policyname;
-- Attendu : SELECT/INSERT/UPDATE ouverts aux commerciaux, DELETE = admin OR created_by,
-- et les éventuelles policies partner intactes.

-- Le vrai test, c'est AMEL : qu'elle recharge le CRM et repositionne Elena sur le besoin.
-- ⚠️ Rappel : ces policies ne se testent PAS depuis l'éditeur SQL — auth.uid() y est NULL,
-- donc get_my_role() renvoie NULL et tout est refusé. Faux négatif garanti.


-- ══════════════════════════════════════════════════════════════════════
-- ROLLBACK — à compléter avec la sortie de l'ÉTAPE 1 avant de l'utiliser
-- ══════════════════════════════════════════════════════════════════════
-- Les policies d'origine n'étant pas connues au moment d'écrire ce fichier, COPIER la
-- sortie de l'étape 1 quelque part avant de lancer l'étape 2. Sans ça, pas de retour
-- arrière fidèle possible.
