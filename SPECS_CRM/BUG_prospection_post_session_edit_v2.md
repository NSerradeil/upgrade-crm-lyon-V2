# BUG — Post-session edit : 3 bugs critiques

**Date** : 25/03/2026
**Fichier cible** : `supabase/CRM_Live.html`
**Priorité** : P0 (bloquant), P1 (design)
**Testé sur** : Session 25/03 Nicolas Serradeil (Loïc FESTAS) + Session 24/03 Anne-Claire Decker (38 contacts)

---

## Contexte

La feature "Modifier les résultats" (bouton RÉSULTATS sur une session TERMINÉE) permet à un commercial de corriger statuts, notes et relances après coup. L'implémentation souffre de 3 bugs identifiés par recette.

---

## Bug 1 — P0 : `handleSaveEdits` crée des lignes dupliquées dans `session_prospection_contacts`

### Symptôme
À chaque clic sur "Enregistrer les modifications", un **nouveau contact fantôme** apparaît dans le panel de détail de session. Exemple : Loïc FESTAS apparaît 2 fois après 2 saves. Après N saves, N copies du contact.

### Cause racine
Dans `handleSaveEdits`, l'étape 2 (mise à jour de `session_prospection_contacts`) utilise **`upsert` sans `onConflict`** :

```js
// ❌ CODE BUGUÉ (production actuelle)
await sb.from('session_prospection_contacts').upsert({
  session_id: session.id,
  contact_id: sc2.id,
  statut: sc2.status,
  notes: sc2.notes || null,
  ...
});
```

Supabase, sans `onConflict`, traite ça comme un **INSERT pur** (car aucun `id` n'est fourni et la clé primaire est un UUID auto-généré). Résultat : une nouvelle ligne est créée à chaque save.

### Fix

Remplacer le `upsert` par un `update` avec filtre `session_id + contact_id` :

```js
// ✅ FIX
// Étape 2 — Update session_prospection_contacts
var spcErrors = 0;
for (var j = 0; j < items.length; j++) {
  var sc2 = items[j];
  var spcRes = await sb.from('session_prospection_contacts').update({
    statut: sc2.status,
    notes: sc2.notes || null,
    want_relance: sc2.wantRelance,
    relance_date: sc2.relanceDate || null,
    relance_note: sc2.relanceNote || null,
  }).eq('session_id', session.id).eq('contact_id', sc2.id);
  if (spcRes.error) {
    console.error('[PostEdit] SPC update error for contact', sc2.id, ':', spcRes.error.message);
    spcErrors++;
  }
}
if (spcErrors > 0) toast('⚠️ ' + spcErrors + ' erreur(s) mise à jour résultats', 'error');
```

---

## Bug 2 — P0 : `handleEditResults` ne déduplique pas → contacts fantômes insensibles + mises à jour croisées

### Symptôme
Quand des lignes dupliquées existent en base (créées par Bug 1), `handleEditResults` les charge toutes → `items[]` contient le même contact en double.

Conséquences :
- **La card "fantôme"** (doublon) ne répond pas aux clics (les indices ne correspondent plus)
- **Modifier l'une des deux cards** (statut ou note) → le PATCH filtre par `session_id + contact_id` → met à jour **les deux lignes en base** → les deux cards affichent le même résultat
- **Le dernier save efface le premier** : si items[0] = "intéressé" et items[30] = "appelé" (doublon non modifié), le PATCH de items[30] écrase celui de items[0]

### Fix

Dans `handleEditResults`, dédupliquer `spcRows` par `contact_id` avant d'initialiser la vue (garder la ligne la plus récente) :

```js
var handleEditResults = async function(session) {
  var result = await sb.from('session_prospection_contacts')
    .select('*')
    .eq('session_id', session.id)
    .neq('statut', 'none')
    .order('created_at'); // ASC — last wins ci-dessous

  var spcRows = result.data || [];

  // ✅ FIX — Dédupliquer par contact_id (garder la plus récente, last wins sur trié ASC)
  var spcByContact = {};
  spcRows.forEach(function(r) { spcByContact[r.contact_id] = r; });
  spcRows = Object.values(spcByContact);

  var contactIds = spcRows.map(function(r) { return r.contact_id; });
  setActiveSession({ ...session, contactIds: contactIds, spcRows: spcRows, editMode: 'results' });
  setDetailSession(null);
  setScreen('active');
};
```

> **Note** : Ce fix est un filet de sécurité permanent. La vraie correction est le Bug 1 (ne plus créer de doublons). Les deux doivent être appliqués ensemble.

---

## Bug 3 — P1 : Les notes de session écrasent `contacts.commentaires` au lieu d'être loggées en historique

### Symptôme
Dans `handleSaveEdits` étape 1, le champ `sc.notes` (note prise pendant/après le call) est écrit dans `contacts.commentaires` :

```js
// ❌ COMPORTEMENT ACTUEL
if (sc.notes && sc.notes.trim()) upd.commentaires = sc.notes.trim();
```

**Problèmes** :
1. Ça **écrase** le commentaire existant du contact à chaque save (pas d'historique, pas d'append)
2. La note de session devrait être une **entrée d'historique horodatée**, pas un champ statique du contact
3. L'utilisateur ne retrouve pas ses notes dans l'historique d'actions du contact

### Comportement attendu
- La note de session doit être **loggée comme action** dans la table `historique` (ou `actions`) avec :
  - `type` : `'note_session'`
  - `contact_id` : l'id du contact
  - `notes` : le texte de la note
  - `date` : now
  - `auteur` : `profile.nom`
  - `session_prospection_id` : `session.id`
- Le champ `contacts.commentaires` **ne doit PAS être modifié** par `handleSaveEdits`

### Fix

Dans `handleSaveEdits` étape 1, supprimer la ligne qui écrase `commentaires` et la remplacer par un INSERT dans la table historique :

```js
// ✅ FIX — Étape 1 : update contacts (données structurelles uniquement, pas les notes)
for (var i = 0; i < appeles.length; i++) {
  var sc = appeles[i];
  var upd = {};
  if (sc.editTel && sc.editTel !== sc.telephone) upd.telephone = sc.editTel;
  if (sc.editEmail && sc.editEmail !== sc.email) upd.email = sc.editEmail;
  if (sc.editLinkedin && sc.editLinkedin !== sc.linkedin) upd.linkedin = sc.editLinkedin;
  if (sc.editVille && sc.editVille !== sc.ville) upd.ville = sc.editVille;
  if (sc.editRole && sc.editRole !== sc.role) upd.role = sc.editRole;
  if (sc.editAts && sc.editAts !== (sc.ats || sc.recruitee || '')) upd.ats = sc.editAts;
  // ❌ SUPPRIMÉ : if (sc.notes && sc.notes.trim()) upd.commentaires = sc.notes.trim();
  if (Object.keys(upd).length > 0) {
    var cRes = await sb.from('contacts').update(upd).eq('id', sc.id);
    if (cRes.error) console.error('[PostEdit] Contact update error for', sc.id, ':', cRes.error.message);
  }

  // ✅ AJOUTÉ : logger la note comme action historique (si note non vide et différente de ce qui est déjà en base)
  if (sc.notes && sc.notes.trim()) {
    // Vérifier si une action note_session existe déjà pour ce contact + session
    var existingNote = await sb.from('historique')
      .select('id, notes')
      .eq('contact_id', sc.id)
      .eq('session_prospection_id', session.id)
      .eq('type', 'note_session')
      .limit(1);
    var noteExists = (existingNote.data || []).length > 0;
    var noteChanged = noteExists ? existingNote.data[0].notes !== sc.notes.trim() : true;

    if (!noteExists) {
      await sb.from('historique').insert({
        id: 'hist_note_' + sc.id + '_' + session.id.substring(0, 8) + '_' + Date.now(),
        contact_id: sc.id,
        type: 'note_session',
        notes: sc.notes.trim(),
        date: now,
        auteur: profile.nom,
        session_prospection_id: session.id,
      });
    } else if (noteChanged) {
      await sb.from('historique').update({
        notes: sc.notes.trim(),
        date: now,
      }).eq('id', existingNote.data[0].id);
    }
  }
}
```

> **⚠️ À valider** : vérifier le nom exact de la table historique et les colonnes disponibles (id, contact_id, type, notes, date, auteur, session_prospection_id). Adapter si nécessaire. Si `historique` n'a pas de colonne `session_prospection_id`, utiliser `notes` pour stocker l'ID de session dans le texte.

---

## Ordre d'application des fixes

1. **Bug 1** (upsert → update dans `handleSaveEdits`) — obligatoire, stoppe la création de doublons
2. **Bug 2** (déduplication dans `handleEditResults`) — filet de sécurité, corriger quand même
3. **Bug 3** (notes → historique) — à valider avec Nicolas sur le schéma `historique`

## Nettoyage base effectué manuellement (25/03/2026)

Les doublons créés lors des tests ont été supprimés directement en base :
- Session 24/03 Anne-Claire : 20 lignes dupliquées supprimées, stats recalculées
- Session 25/03 Nicolas (Loïc FESTAS) : 1 ligne dupliquée supprimée, `nb_contacts` = 1
- 3 tâches de relance pour session 24/03 recréées (Fabrice BERTHEUIL, Elodie LEMIN, Philippe ALBERT)
