# SPEC — Rôle `partner` (suivi de portefeuille consultants)

**CRM Upgrade Lyon V2** · Nouveau rôle + périmètre par liste explicite de consultants
**Auteur :** Nicolas Serradeil + Jules
**Date :** 2026-07-02
**Statut :** À VALIDER avant implémentation

---

## Besoin

Créer un compte pour **Maria-Jose « Majo » Paquelier** (`Maria-Jose.Paquelier@upgrade.fr`),
qui suit un **portefeuille explicite de consultants en mission**. Elle doit avoir les
**mêmes droits qu'un commercial (Amel/Camille)** — CRUD, pas de suppression, pas d'admin —
mais **uniquement sur son périmètre**, défini par une **liste nommée de consultants**
(pas par agence, pas par un filtre métier flou).

### Périmètre initial de Majo (7 consultants, tous Consultant CDI)
| Consultant | contact_id |
|---|---|
| Naomi Pereira | 365 |
| Mathilde Villanti | 366 |
| Frédéric Tapia | 367 |
| Lucas Molina | 368 |
| Melissa Laborde | 369 |
| Manon Faraldi | 394 |
| Marie Maitrallin | 1418 |

---

## Modèle retenu : périmètre par affectation explicite (PAS par agence ni métier)

Le CRM n'a aujourd'hui que 2 niveaux (`admin` / non-admin) et scope tout par `agence` ou
`responsable`. Aucun filtre « designer » propre n'existe (le rôle est un texte libre).
→ On introduit un **rôle `partner`** dont la visibilité s'appuie sur une **table de liaison
`partner_consultants`** : Nicolas ajoute/retire un consultant du périmètre de Majo quand il
veut, sans toucher au code.

### Nouvelle table `partner_consultants`
```sql
create table public.partner_consultants (
  partner_id            uuid    not null references public.profiles(id) on delete cascade,
  contact_consultant_id bigint  not null references public.contacts(id) on delete cascade,
  created_at            timestamptz not null default now(),
  primary key (partner_id, contact_consultant_id)
);
alter table public.partner_consultants enable row level security;
-- lecture : le partner voit ses propres affectations ; admin voit tout
create policy pc_read on public.partner_consultants for select
  using ( partner_id = auth.uid()
          or (select role from public.profiles where id = auth.uid()) = 'admin' );
-- écriture : admin uniquement (c'est Nicolas qui gère les périmètres)
create policy pc_write on public.partner_consultants for all
  using ( (select role from public.profiles where id = auth.uid()) = 'admin' )
  with check ( (select role from public.profiles where id = auth.uid()) = 'admin' );
```

### Profil Majo
```sql
-- 1) créer l'utilisateur auth (Supabase → Authentication → Add user, email + mot de passe)
--    email : Maria-Jose.Paquelier@upgrade.fr
-- 2) insérer/mettre à jour son profil (id = l'uuid auth généré)
insert into public.profiles (id, nom, agence, role)
values ('<uuid_auth_majo>', 'Maria-Jose Paquelier', 'Partner', 'partner');
--   ⚠️ agence = 'Partner' (NEUTRE, PAS 'Lyon') : sinon les branches RLS filtrées par agence
--      (ex. besoins_select) lui donneraient la lecture de tous les besoins Lyon.
-- 3) affecter ses 7 consultants
insert into public.partner_consultants (partner_id, contact_consultant_id) values
  ('<uuid_auth_majo>', 365), ('<uuid_auth_majo>', 366), ('<uuid_auth_majo>', 367),
  ('<uuid_auth_majo>', 368), ('<uuid_auth_majo>', 369), ('<uuid_auth_majo>', 394),
  ('<uuid_auth_majo>', 1418);
```

---

## Ce à quoi Majo a accès (RECAP pour validation)

| Donnée | READ | WRITE (create/update, PAS delete) |
|---|---|---|
| Ses 7 consultants (contacts) | ✅ | ✅ |
| Missions de ses consultants (`contact_consultant_id` ∈ sa liste) | ✅ | ✅ (suivi, statut, CR) |
| Périodes de mission de ces missions | ✅ | ✅ (renouvellements) |
| Actions / tâches liées à ces consultants/missions | ✅ | ✅ |
| Comptes clients où ces consultants sont en mission | ✅ (contexte) | ❌ |
| **Tout le reste** : autres consultants/contacts, prospection, besoins, autres comptes, autres agences | ❌ | ❌ |
| Suppression (delete), administration (users, config) | ❌ | ❌ |

En clair : Majo = un commercial dont l'univers se limite à **ses 7 consultants + leurs
missions**. Elle ne voit ni la prospection, ni les besoins, ni les autres consultants Lyon.

---

## ⚠️ Réalité découverte sur le modèle de lecture (02/07)
Les policies SELECT de `contacts`, `comptes`, `missions`, `contact_compte`, `besoin_candidats`
sont `qual = true` → **lecture ouverte au niveau DB pour tout authentifié**. La visibilité par
agence (Amel ne voit que Paris) est faite **côté APP**, pas en RLS. Conséquence :
- Le « Majo ne voit que ses 7 » sur ces tables = **côté APP** (même mécanisme que le filtre agence).
- La RLS verrouille en DUR : ses **écritures** (limitées à ses consultants) + la **lecture des
  tables non ouvertes** (`mission_periods`, `historique_missions`, `historique_actions`, `taches`).
- Un mur de lecture DB pour elle seule = refonte du modèle ouvert → hors périmètre (risqué).
Le SQL final vit dans **`db/04_role_partner.sql`** (policies ADDITIVES `*_partner_*`, gardées
par `get_my_role()='partner'` → aucune touche aux policies admin/commercial).

## Impact RLS (Supabase — appliqué à la main dans SQL Editor) — voir db/04_role_partner.sql

Principe commun : ajouter à chaque table une **branche `partner`** qui autorise la ligne
si elle est rattachée à un consultant de `partner_consultants` du user courant. Les branches
existantes (agence/responsable/admin) restent inchangées → **aucun impact sur Amel/Camille/admin**.

Helper (évite la répétition) :
```sql
create or replace function public.is_my_consultant(c_id bigint)
returns boolean language sql stable security definer as $$
  select exists (
    select 1 from public.partner_consultants pc
    where pc.partner_id = auth.uid() and pc.contact_consultant_id = c_id
  );
$$;
```

- **contacts** : `... OR is_my_consultant(contacts.id)` en SELECT et UPDATE.
- **missions** : `... OR is_my_consultant(missions.contact_consultant_id)` en SELECT et UPDATE.
- **mission_periods** : via la mission parente (`... OR is_my_consultant((select contact_consultant_id from missions m where m.id = mission_periods.mission_id))`).
- **actions / taches** : `... OR is_my_consultant(contact_id)` (et/ou via besoin/mission liés).
- **comptes** : SELECT autorisé si le compte porte une mission d'un de ses consultants ;
  pas de WRITE partner.
- **besoins, prospection_sessions, autres contacts** : PAS de branche partner → invisibles.

⚠️ À faire proprement : lister les policies actuelles de chaque table avant de les recréer
(on ré-écrit la policy complète, on n'en ajoute pas une 2e qui pourrait élargir).

---

## Impact App (`index.html`)

La sécurité réelle = RLS (une donnée hors périmètre ne remonte pas, même si un onglet
s'affiche). L'app ne fait que l'UX :
- `role === 'partner'` traité comme non-admin (pas d'accès config/users).
- Masquer pour `partner` les onglets **Prospection** et **Besoins/Pipeline** (vides pour elle
  de toute façon) → ne garder que **Missions** et **Contacts** (filtrés à son périmètre par RLS).
- Vérifier qu'aucun écran ne casse si ces listes sont réduites.

---

## Déploiement (cf. DEPLOY.md — LOCAL D'ABORD)

1. **DB** : appliquer le SQL (table + helper + policies) dans Supabase SQL Editor ; versionner
   dans `db/04_role_partner.sql`. Immédiat, réversible (drop policies + table).
2. **Auth** : créer l'utilisateur de Majo côté Supabase (email + mot de passe), récupérer son uuid.
3. **App** : modifier `index.html` en local, servir en local, **preview + OK Nicolas**, puis push `main`.
4. **Test** : se connecter en tant que Majo (ou simuler) → vérifier qu'elle voit SES 7 consultants
   et leurs missions, et RIEN d'autre (pas de prospection, pas de besoins, pas d'autres contacts).

## Réversibilité
`drop table partner_consultants cascade;` + retrait des branches `partner` des policies +
`delete from profiles where role='partner'` + suppression de l'utilisateur auth. Aucun impact
sur les données métier existantes.
