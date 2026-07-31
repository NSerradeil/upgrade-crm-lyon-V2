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
-- propriété mais l'AGENCE, via un EXISTS sur `besoins`. CONFIRMÉ le 31/07 (étape 1).
--
-- C'est le MÊME motif que le bug de Louis Py (db/08) : une condition d'agence sans
-- échappatoire par le responsable, sur un besoin rattaché à une autre agence que celle
-- de son propriétaire. Troisième occurrence du même défaut. `besoin_candidats` n'était
-- pas dans le périmètre de l'audit du 28/07 (db/09) : c'est le trou à combler.
-- ══════════════════════════════════════════════════════════════════════


-- ─── ÉTAPE 1 — CONFIRMÉE le 31/07 ───
-- Hypothèse validée mot pour mot. Les TROIS policies d'écriture portent la même
-- condition, et AUCUNE ne prévoit d'échappatoire par le responsable :
--
--   besoin_candidats_insert  WITH CHECK : admin OR EXISTS(besoins b
--                              WHERE b.id = besoin_id AND b.agence = get_my_agence())
--   besoin_candidats_update  USING      : idem
--   besoin_candidats_delete  USING      : idem
--   besoin_candidats_select  USING      : true  ← lecture ouverte
--
-- Amel (agence Paris) sur un besoin en agence Lyon : le EXISTS échoue → 403.
-- Effet pervers du SELECT à `true` : elle VOIT le besoin et ses candidats mais ne peut
-- rien y ajouter. Le pire des cas pour comprendre ce qui se passe.
SELECT policyname, cmd, roles,
       qual       AS condition_lecture,
       with_check AS condition_ecriture
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'besoin_candidats'
ORDER BY cmd, policyname;
-- (Requête conservée pour rejouer le constat. Résultat obtenu : voir l'encadré ci-dessus.)

-- Contexte utile à afficher en même temps
SELECT b.id, b.titre, b.responsable, b.agence AS agence_besoin,
       p.agence AS agence_du_responsable
FROM besoins b LEFT JOIN profiles p ON p.nom = b.responsable
WHERE b.id = '839ef93e-e6bc-48f4-a629-736bd4aff434';
-- Attendu : responsable Amel Benzai · agence_besoin Lyon · agence_du_responsable Paris


-- ─── ÉTAPE 2 — LE CORRECTIF ───
-- On aligne `besoin_candidats` sur ce que db/09 a fait ailleurs : lecture et écriture
-- ouvertes aux commerciaux, suppression réservée à l'auteur du lien, au responsable du
-- besoin, ou à l'admin.
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

-- Suppression : l'auteur du lien, OU le responsable du besoin, OU l'admin. On ne défait
-- pas le positionnement d'un collègue par mégarde, mais le responsable d'un besoin doit
-- pouvoir nettoyer sa propre short-list.
drop policy if exists besoin_candidats_delete on public.besoin_candidats;
drop policy if exists besoin_candidats_commercial_delete on public.besoin_candidats;
create policy besoin_candidats_delete on public.besoin_candidats
  for delete
  using (
    get_my_role() = 'admin'
    or created_by = get_my_nom()
    or exists (select 1 from besoins b
               where b.id = besoin_candidats.besoin_id and b.responsable = get_my_nom())
  );

-- ⚠️ Les policies `*_partner_*` de cette table, s'il en existe, ne sont PAS touchées :
-- les DROP ci-dessus ne visent que des noms explicites. Vérifier à l'étape 3.


-- ─── ÉTAPE 3 — VÉRIFIER ───
SELECT policyname, cmd, qual AS lecture, with_check AS ecriture
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'besoin_candidats'
ORDER BY cmd, policyname;
-- Attendu : SELECT/INSERT/UPDATE ouverts aux commerciaux ; DELETE = admin OR created_by
-- OR responsable du besoin ; et les éventuelles policies partner intactes.

-- Le vrai test, c'est AMEL : qu'elle recharge le CRM et repositionne Elena sur le besoin.
-- ⚠️ Rappel : ces policies ne se testent PAS depuis l'éditeur SQL — auth.uid() y est NULL,
-- donc get_my_role() renvoie NULL et tout est refusé. Faux négatif garanti.


-- ══════════════════════════════════════════════════════════════════════
-- ROLLBACK — état exact du 31/07 avant correctif (relevé à l'étape 1)
-- ══════════════════════════════════════════════════════════════════════
-- drop policy if exists besoin_candidats_insert on public.besoin_candidats;
-- create policy besoin_candidats_insert on public.besoin_candidats for insert to authenticated
--   with check ((get_my_role() = 'admin') or (exists (select 1 from besoins b
--     where b.id = besoin_candidats.besoin_id and b.agence = get_my_agence())));
--
-- drop policy if exists besoin_candidats_update on public.besoin_candidats;
-- create policy besoin_candidats_update on public.besoin_candidats for update to authenticated
--   using ((get_my_role() = 'admin') or (exists (select 1 from besoins b
--     where b.id = besoin_candidats.besoin_id and b.agence = get_my_agence())));
--
-- drop policy if exists besoin_candidats_delete on public.besoin_candidats;
-- create policy besoin_candidats_delete on public.besoin_candidats for delete to authenticated
--   using ((get_my_role() = 'admin') or (exists (select 1 from besoins b
--     where b.id = besoin_candidats.besoin_id and b.agence = get_my_agence())));
--
-- drop policy if exists besoin_candidats_select on public.besoin_candidats;
-- create policy besoin_candidats_select on public.besoin_candidats for select to authenticated
--   using (true);
