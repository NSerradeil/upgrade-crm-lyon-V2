# SPEC — Permissions contacts cross-agence + champ agence éditable
**CRM Upgrade Lyon V2** · Évolution modèle de données + permissions
**Auteur :** Nicolas Serradeil + Claude (PM + Lead Tech)
**Date :** 24/03/2026

---

## Besoin exprimé

> "En tant que commercial, je veux pouvoir avoir les droits CRUD sur tous les contacts dont je suis responsable, même s'ils dépendent d'une autre agence. Il faudra dans Contact un champ agence modifiable par les admins et les commerciaux."

---

## Clarification — deux concepts distincts

| Champ | Signification | Qui peut modifier |
|---|---|---|
| `agence` (contact) | Voir tableau ci-dessous — sens différent selon le type de contact | Admin + Responsable du contact |
| `responsable` (contact) | Commercial Upgrade assigné à ce contact | Admin + Commercial (sur ses propres contacts) |

### Sémantique du champ `agence` selon le type de contact

| Type de contact | Sens de `agence` | Exemple |
|---|---|---|
| **Client** (DRH, acheteur, directeur) | Agence Upgrade qui porte commercialement le compte | Enedis suivi par Lyon → `agence: Lyon` |
| **Prestataire / freelance / salarié** | **Localisation de la mission/prestation en cours** — pas la ville d'origine du prestataire, pas l'agence de son responsable | Salarié basé à Paris, `responsable` = commercial Paris, mais mission en cours à Lyon → `agence: Lyon` |

> ⚠️ `agence` sur un prestataire est **dynamique** : il change quand la mission change de localisation. Il reflète où la prestation se passe aujourd'hui, pas d'où vient la personne ni qui la suit dans la durée.
>
> **Conséquence directe sur les permissions** : un commercial Lyon doit pouvoir éditer un contact dont l'`agence` est Lyon — même si le `responsable` est un commercial d'une autre agence. Le droit WRITE suit donc l'`agence` ET le `responsable` (voir section Permissions ci-dessous).

---

## Nouveau modèle de permissions

### Règle actuelle (à remplacer)
```
CRUD contact ← agence_contact == agence_user
```

### Nouvelle règle
```
READ  contact ← agence_contact == agence_user   (visibilité de l'agence)
             OR responsable == user_id            (mes contacts cross-agence)

WRITE contact ← agence_contact == agence_user    (je gère les contacts de mon agence)
             OR responsable == user_id            (je gère mes contacts cross-agence)
             OR role == 'admin'

WRITE champ agence ← responsable == user_id      (je peux réaffecter mes contacts)
                  OR role == 'admin'
                  -- ⚠️ un commercial peut lire/écrire le contact via agence,
                  --    mais ne peut PAS changer le champ agence s'il n'est pas responsable
```

> **Pourquoi WRITE suit aussi `agence` (et pas seulement `responsable`) :**
> Un prestataire dont l'`agence` = Lyon et le `responsable` = commercial Paris doit être éditable par un commercial Lyon pour gérer la mission localement — même sans être le `responsable` officiel du contact.

### En clair pour un commercial

| Situation | READ | WRITE | Modifier `agence` |
|---|---|---|---|
| Contact de mon agence, je suis responsable | ✅ | ✅ | ✅ |
| Contact de mon agence, autre responsable | ✅ | ✅ | ❌ |
| Contact d'une autre agence, je suis responsable | ✅ | ✅ | ✅ |
| Contact d'une autre agence, autre responsable | ❌ | ❌ | ❌ |

---

## Impact Supabase — Row Level Security

### Table `contacts` — policies à modifier

```sql
-- READ : agence OU responsable
CREATE POLICY "contacts_select" ON contacts
  FOR SELECT USING (
    agence = (SELECT agence FROM users WHERE id = auth.uid())
    OR responsable_id = auth.uid()
  );

-- UPDATE : responsable OU admin
CREATE POLICY "contacts_update" ON contacts
  FOR UPDATE USING (
    responsable_id = auth.uid()
    OR (SELECT role FROM users WHERE id = auth.uid()) = 'admin'
  );

-- INSERT : tout commercial authentifié (inchangé)
-- DELETE : admin uniquement (inchangé)
```

### Champ `agence` — restriction supplémentaire côté app

Le RLS ci-dessus autorise le UPDATE sur le contact entier. La restriction "seul le responsable ou un admin peut changer `agence`" est gérée côté **application** (pas RLS) car Supabase ne permet pas nativement le RLS champ-par-champ.

```js
// Avant toute mise à jour du champ agence :
if (field === 'agence' && !isAdmin && contact.responsable_id !== currentUser.id) {
  throw new Error('Vous ne pouvez pas modifier l\'agence de ce contact');
}
```

---

## Modifications UI

### 1. Fiche contact — champ `Agence`

**Actuellement :** Champ affiché, non modifiable (ou absent du formulaire de modification)

**Nouveau comportement :**
- Affiché dans la fiche contact (lecture) pour tous
- **Modifiable** dans le formulaire Modifier si `role == 'admin'` OU `responsable == moi`
- Si non modifiable → champ en lecture seule avec mention "(Contactez un admin pour changer)"
- Select avec les options : `Lyon` / `Paris` / `Bordeaux` (+ options futures)

```jsx
<SelectField
  label="Agence"
  value={contact.agence}
  disabled={!canEditAgence}  // admin || responsable
  options={AGENCES}
  hint={!canEditAgence ? 'Seul le responsable ou un admin peut modifier l\'agence' : null}
/>
```

### 2. Liste contacts — filtre "Mes contacts"

Ajouter un toggle ou un filtre rapide **"Mes contacts"** dans la barre de filtres, qui affiche les contacts cross-agence dont l'utilisateur est responsable.

```
[Toutes agences ▾]  [Tous les commerciaux ▾]  [★ Mes contacts]
```

Le filtre "Mes contacts" :
- Ignore le filtre agence
- Retourne `WHERE responsable_id = currentUser.id`
- Badge count à côté du toggle

### 3. Header / KPI — compteurs

Les compteurs d'agence (ex. "65 besoins — Lyon") restent basés sur `agence_contact`, inchangés. Les contacts cross-agence dont un commercial est responsable ne gonflent pas les stats d'une autre agence.

---

## Cas limites à gérer

### Changement de responsable

Si un admin réassigne `responsable` d'un contact à un autre commercial :
- L'ancien responsable perd l'accès WRITE (mais garde READ si même agence)
- Le nouveau responsable gagne l'accès WRITE immédiatement
- → Mettre à jour aussi `agence` si le nouveau responsable est d'une autre agence ? **Non — laisser le commercial le faire manuellement** pour éviter les effets de bord silencieux.

### Contact sans responsable assigné

Si `responsable_id = null` :
- Visible par tous les commerciaux de l'agence (comportement actuel)
- Éditable par les admins uniquement
- → UI : badge "Non assigné" dans la fiche + CTA "Prendre en charge" pour s'assigner

### Transfert cross-agence

Quand un commercial change l'`agence` d'un contact :
- Log automatique dans l'historique du contact : `"Agence modifiée : Lyon → Paris par Nicolas Serradeil"`
- Notification optionnelle au responsable de l'agence cible (évolution future)

---

## Acceptance criteria (Claude Code)

**Permissions :**
- [ ] Un commercial voit ses contacts cross-agence dans la liste contacts (avec filtre "Mes contacts")
- [ ] Un commercial peut éditer un contact cross-agence dont il est responsable
- [ ] Un commercial NE PEUT PAS éditer un contact d'une autre agence dont il n'est pas responsable
- [ ] Un admin peut tout éditer

**Champ agence :**
- [ ] Le champ `agence` est visible dans la fiche contact en lecture pour tous
- [ ] Le champ `agence` est éditable dans le formulaire Modifier si admin OU responsable du contact
- [ ] Si non modifiable → champ grisé + message explicatif
- [ ] Le changement d'agence est loggué dans l'historique du contact

**Liste contacts :**
- [ ] Filtre "Mes contacts" disponible dans la barre de filtres
- [ ] "Mes contacts" ignore le filtre agence courant
- [ ] Le count du filtre "Mes contacts" est visible et à jour

**Rétrocompatibilité :**
- [ ] Les contacts de l'agence courante restent visibles (aucune régression)
- [ ] Les KPI / compteurs par agence restent basés sur `agence_contact` (inchangés)
- [ ] Le filtre par agence existant continue de fonctionner normalement

---

## Ordre d'implémentation recommandé

1. **Supabase** — modifier les RLS policies `contacts_select` + `contacts_update`
2. **Frontend** — rendre le champ `agence` conditionnel dans `renderModifierContact()`
3. **Frontend** — ajouter le filtre "Mes contacts" dans la liste contacts
4. **Frontend** — guard côté app pour la modification du champ `agence`
5. **Frontend** — log automatique du changement d'agence dans l'historique
6. **Test** — vérifier avec un compte commercial cross-agence en staging
