# SPEC — Association libre de contacts aux objets CRM
**CRM Upgrade Lyon V2** · Correction permissions + filtre
**Auteur :** Nicolas Serradeil + Claude
**Date :** 15/04/2026

---

## Besoin exprimé

> "Un commercial doit pouvoir associer n'importe quel contact à un de ses objets (besoin, mission, tâche), même si le contact a un autre commercial responsable que lui."

---

## Problème identifié

### 1. RLS Supabase trop restrictif (SELECT)
La policy `contacts_select_cross` limitait la visibilité :
```sql
-- AVANT : seuls les contacts de mon agence OU dont je suis responsable
agence = get_my_agence() OR responsable = get_my_nom()
```
Un commercial Lyon ne voyait pas un contact Paris sauf s'il en était le responsable.

### 2. Filtre frontend sur AddTacheModal
```js
// AVANT : ligne 1425
contacts.filter(c => isAdmin || c.responsable === profile.nom)
```
Même parmi les contacts visibles, seuls ceux dont le commercial est responsable étaient sélectionnables pour les tâches.

---

## Corrections appliquées

### 1. Nouvelle migration SQL
**Fichier :** `supabase/migrations/20260415_contacts_select_all_commercials.sql`

```sql
DROP POLICY IF EXISTS "contacts_select_cross" ON contacts;

CREATE POLICY "contacts_select_all" ON contacts
  FOR SELECT USING (
    get_my_role() IN ('admin', 'commercial')
  );
```

Tout commercial authentifié peut désormais **voir** tous les contacts.
La policy UPDATE reste inchangée (seuls admin, responsable, ou même agence peuvent modifier).

### 2. Fix frontend — AddTacheModal
```js
// APRÈS : plus de filtre responsable
const myContacts = useMemo(
  () => [...contacts].sort((a,b) => (a.nom||'').localeCompare(b.nom||'')),
  [contacts]
);
```

---

## Impact

| Composant | Avant | Après |
|---|---|---|
| ContactPicker dans Besoin | Tous les contacts chargés (mais RLS limitait) | Tous les contacts de la base |
| ContactPicker dans Tâche | Filtrés par responsable | Tous les contacts de la base |
| ContactPicker dans Mission | Tous les contacts chargés (mais RLS limitait) | Tous les contacts de la base |
| Édition de contacts | Limité agence + responsable | Inchangé (même règle UPDATE) |
| Liste contacts (onglet) | Limité agence + responsable | Tous visibles |

---

## Acceptance criteria

- [x] Migration SQL créée
- [x] Filtre responsable supprimé dans AddTacheModal
- [ ] Tester : un commercial Lyon peut chercher et associer un contact Paris à un besoin
- [ ] Tester : un commercial peut associer un contact d'un autre commercial à une tâche
- [ ] Vérifier : un commercial NE PEUT PAS modifier un contact dont il n'est pas responsable et qui n'est pas de son agence (policy UPDATE inchangée)
