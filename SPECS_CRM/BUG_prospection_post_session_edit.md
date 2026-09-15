# BUG REPORT — Post-session edit : 2 bugs
**CRM Upgrade Lyon V2** · Bugs identifiés après implémentation SPEC_prospection_post_session_edit
**Date :** 25/03/2026

---

## Bug 1 — CRITIQUE : `null value in column "id"` sur chaque relance (6 toasts d'erreur)

### Symptôme
À chaque clic sur "Enregistrer les modifications" dans le mode post-session edit, autant de toasts rouges que de relances dans la session :
```
⚠️ Erreur relance : null value in column "id" of relation "taches" violates not-null constraint
```

### Root cause
**La table `taches` utilise un `id` TEXT sans valeur par défaut côté Supabase.** Tous les inserts dans `taches` doivent fournir un `id` explicite.

Le pattern utilisé dans le reste du code :
```js
// AddTacheModal (ligne ~1065)
id: `tw_${Date.now()}`

// Entretien besoin (ligne ~2766)
id: `tw_entretien_${besoin.id}_${Date.now()}`
```

**Les inserts de relances prospection oublient ce champ — dans les deux endroits :**

**Endroit 1 — `handleTerminer` (session normale) :**
```js
// BUG (ligne ~5133-5139) :
await sb.from('taches').insert(relances.map(function(sc4){return {
  titre: ...,
  statut: 'a_faire', due_date: sc4.relanceDate, contact_id: sc4.id,
  session_prospection_id: session.id,
  notes: ...,
  responsable: profile.nom,
  // ← MANQUE : id
};}));
```

**Endroit 2 — `handleSaveEdits` (post-session edit) :**
```js
// BUG (ligne ~5206) :
var ins = await sb.from('taches').insert({
  titre: ..., statut: 'a_faire', due_date: sc3.relanceDate,
  contact_id: sc3.id, session_prospection_id: session.id,
  notes: ..., responsable: profile.nom,
  // ← MANQUE : id
});
```

### Fix

Ajouter `id` dans les deux inserts :

**Endroit 1 — `handleTerminer`, dans le `.map(function(sc4){return {` :**
```js
// Ajouter en premier champ :
id: 'tw_relance_' + sc4.id + '_' + Date.now(),
```

**Endroit 2 — `handleSaveEdits`, dans l'objet d'insert :**
```js
// Ajouter en premier champ :
id: 'tw_relance_' + sc3.id + '_' + Date.now(),
```

> ⚠️ Si plusieurs relances sont insérées en boucle rapide pour le même contact, `Date.now()` peut collisionner. Préférer `Date.now() + '_' + k` (avec `k` = index de boucle) dans `handleSaveEdits` pour garantir l'unicité.

---

## Bug 2 — MOYEN : Notes session non répercutées sur la fiche contact + champ `editAts` manquant

### Symptôme A — Commentaire contact non mis à jour
L'utilisateur modifie les "Notes d'appel" d'un contact dans la session post-edit → les modifications s'enregistrent bien dans `session_prospection_contacts.notes` mais **n'apparaissent pas dans la fiche contact** (champ `contacts.commentaires`).

**Root cause :** Les deux champs sont distincts. La session gère `sc.notes` → `session_prospection_contacts.notes` (notes de session). La fiche contact affiche `contacts.commentaires`. `handleSaveEdits` met à jour la session mais n'écrit pas dans `contacts.commentaires`.

Note : Ce comportement est le même dans `handleTerminer` (session normale) — ce n'est pas une régression, mais un manque.

### Fix A

Dans `handleSaveEdits`, step 1 (contact updates), ajouter la propagation des notes vers `commentaires` si non vides et différentes :

```js
// Dans la boucle de mise à jour contacts, après les champs existants :
if (sc.notes && sc.notes.trim() && sc.notes.trim() !== (sc.commentaires||'').trim()) {
  upd.commentaires = sc.notes.trim();
}
```

> Alternative plus sûre : ajouter un champ `editCommentaires` dédié dans l'état de session (initialisé avec `c.commentaires || ''`) et l'afficher comme textarea éditable dans la vue focus, séparé des notes de session. Cela distingue explicitement "note de l'appel" (temporaire) et "commentaire du contact" (permanent).

### Symptôme B — Champ ATS non sauvegardé dans le post-edit

`handleSaveEdits` manque la sauvegarde de `editAts`, présente dans `handleTerminer`.

**Comparaison des deux fonctions :**

| Champ | `handleTerminer` | `handleSaveEdits` |
|---|---|---|
| `editTel` → `contacts.telephone` | ✅ | ✅ |
| `editEmail` → `contacts.email` | ✅ | ✅ |
| `editLinkedin` → `contacts.linkedin` | ✅ | ✅ |
| `editVille` → `contacts.ville` | ✅ | ✅ |
| `editRole` → `contacts.role` | ✅ | ✅ |
| `editAts` → `contacts.ats` | ✅ | ❌ MANQUANT |
| `notes` → `contacts.commentaires` | ❌ | ❌ |

### Fix B

Dans `handleSaveEdits`, step 1, ajouter après `editRole` :
```js
if (sc.editAts && sc.editAts !== (sc.ats||sc.recruitee||'')) upd.ats = sc.editAts;
```

---

## Récapitulatif des lignes à modifier

| Fichier | Ligne approx. | Action |
|---|---|---|
| `CRM_Live.html` | ~5133 | `handleTerminer` insert relance → ajouter `id: 'tw_relance_' + sc4.id + '_' + Date.now()` |
| `CRM_Live.html` | ~5206 | `handleSaveEdits` insert relance → ajouter `id: 'tw_relance_' + sc3.id + '_' + Date.now()` |
| `CRM_Live.html` | ~5184 | `handleSaveEdits` contact upd → ajouter `editAts` |
| `CRM_Live.html` | ~5179 | `handleSaveEdits` contact upd → ajouter propagation `notes → commentaires` (optionnel selon choix archi) |

---

## Priorité

| Bug | Priorité | Impact |
|---|---|---|
| Bug 1 — id manquant (×2 endroits) | **P0** | Aucune relance prospection ne peut être créée. Fonctionnalité de relance cassée depuis le début. |
| Bug 2B — editAts manquant | **P2** | Perte silencieuse des mises à jour ATS via post-edit. |
| Bug 2A — notes → commentaires | **P3** | Confusion UX, mais les données ne sont pas perdues (stockées dans session). |
