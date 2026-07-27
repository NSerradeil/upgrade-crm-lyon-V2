-- ══════════════════════════════════════════════════════════════════════
-- 08 — Un besoin doit être visible par son responsable, même hors de son agence
-- Date : 27/07/2026
--
-- CAS RÉEL : le besoin BPM002771 « Scrum Master Expérimenté Lyon — Tribu Crédit
-- Agri Pro » (agence 'Lyon', responsable 'Louis Py') est INVISIBLE à Louis Py,
-- qui en est pourtant le responsable — parce qu'il est rattaché à l'agence Paris.
--
-- CAUSE : les deux policies SELECT de `besoins` exigent toutes les deux
-- `agence = get_my_agence()` et n'offrent aucune échappatoire par le responsable.
-- Les policies permissives se combinant en OU, un commercial n'a donc qu'une seule
-- porte d'entrée : son agence. La ligne ne quitte jamais la base.
--
--   besoins_commercial_select : role='commercial' AND agence = get_my_agence()
--   besoins_select            : admin OR agence = get_my_agence()
--                                     OR (agence du contact lié = la mienne)
--
-- `besoins` est la SEULE table dans ce cas : comptes, contacts et missions ont
-- toutes une policy SELECT `true` (lecture ouverte, périmètre fait côté app).
-- Cette restriction est donc une anomalie isolée, pas un choix d'architecture.
--
-- CORRECTIF : ajouter `OR responsable = get_my_nom()` aux deux policies SELECT.
-- On n'ouvre PAS la lecture à tout le monde (on reste sur le modèle agence) :
-- on ajoute juste le cas « c'est mon besoin ».
-- ══════════════════════════════════════════════════════════════════════

-- ─── AVANT : constater le trou ───
-- Combien de besoins sont invisibles à leur propre responsable ?
SELECT b.id, b.titre, b.agence AS agence_besoin, b.responsable, p.agence AS agence_responsable
FROM besoins b
JOIN profiles p ON p.nom = b.responsable
WHERE b.agence IS DISTINCT FROM p.agence
ORDER BY b.responsable, b.titre;
-- Attendu : 7 lignes — 3 de Nicolas Serradeil (agence Paris), 3 de Louis Py
-- (agence Lyon, dont BPM002771), 1 d'Anne Claire Decker (agence Nantes).


-- ─── LE CORRECTIF ───

-- 1) La policy du rôle commercial
drop policy if exists besoins_commercial_select on public.besoins;
create policy besoins_commercial_select on public.besoins
  for select
  using (
    get_my_role() = 'commercial'
    and (
      agence = get_my_agence()
      or responsable = get_my_nom()     -- ← ajout : mon besoin reste le mien
    )
  );

-- 2) La policy générale des utilisateurs authentifiés
drop policy if exists besoins_select on public.besoins;
create policy besoins_select on public.besoins
  for select
  to authenticated
  using (
    get_my_role() = 'admin'
    or agence = get_my_agence()
    or responsable = get_my_nom()       -- ← ajout
    or exists (
      select 1 from contacts c
      where c.id = besoins.contact_id and c.agence = get_my_agence()
    )
  );


-- ─── APRÈS : vérifier ───
--
-- ⚠️ NE PAS tenter de vérifier en usurpant l'identité de Louis dans l'éditeur SQL.
-- Testé le 27/07 : l'éditeur s'exécute SANS JWT, donc `auth.uid()` est NULL et les
-- trois fonctions get_my_*() renvoient NULL. Toute policy évalue alors à faux et on
-- lit « 0 ligne » — ce qui ressemble à « le correctif ne marche pas » alors que c'est
-- le contexte d'authentification qui manque. Faux négatif garanti.
--
-- Deux vérifications fiables à la place :

-- ① RELECTURE DES POLICIES — la clause a-t-elle bien été posée ?
SELECT policyname, cmd, qual AS condition_lecture
FROM pg_policies
WHERE schemaname='public' AND tablename='besoins' AND cmd='SELECT'
ORDER BY policyname;
-- Attendu : les deux policies contiennent maintenant `responsable = get_my_nom()`.

-- ② LA VRAIE PREUVE, DEPUIS L'APP — c'est la seule qui vaut
-- Louis recharge le CRM (Cmd+Shift+R) et cherche « BPM002771 » dans l'onglet Besoins.
-- Attendu : la fiche apparaît. Avant le correctif, elle était introuvable pour lui.
-- Contrôle de non-régression, toujours côté app : Louis ne doit voir aucun besoin
-- qui ne soit ni de l'agence Paris ni à son nom.
--
-- Rappel du périmètre attendu après correctif (requête admin, contexte normal) :
SELECT b.responsable, b.agence, count(*) AS nb
FROM besoins b
GROUP BY b.responsable, b.agence
ORDER BY b.responsable, b.agence;
-- Louis Py doit y apparaître avec ses besoins Paris ET ses 3 besoins Lyon.


-- ══════════════════════════════════════════════════════════════════════
-- ROLLBACK — restaure les deux policies dans leur état du 27/07 avant correctif
-- ══════════════════════════════════════════════════════════════════════
-- drop policy if exists besoins_commercial_select on public.besoins;
-- create policy besoins_commercial_select on public.besoins for select
--   using ((get_my_role() = 'commercial') and (agence = get_my_agence()));
--
-- drop policy if exists besoins_select on public.besoins;
-- create policy besoins_select on public.besoins for select to authenticated
--   using ((get_my_role() = 'admin') or (agence = get_my_agence())
--     or (exists (select 1 from contacts c
--                 where c.id = besoins.contact_id and c.agence = get_my_agence())));
