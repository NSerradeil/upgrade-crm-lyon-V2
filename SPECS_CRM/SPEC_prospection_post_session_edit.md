# SPEC — Modification post-session de prospection
**CRM Upgrade Lyon V2** · Évolution UX
**Source :** Retour Anne-Claire Decker (commerciale Bordeaux) · 25/03/2026
**Auteur :** Nicolas Serradeil + Claude (PM + Lead UX)

---

## Besoin exprimé

> « Permettre de modifier des actions dans une session après avoir cliqué sur "Terminer". Il arrive que l'on souhaite revenir sur certaines informations qui n'ont pas été saisies à l'instant T. »

---

## Analyse du besoin

### Cas d'usage principal

Anne-Claire termine une session de 30 appels. Elle a rempli les statuts à la volée (intéressé, injoignable, etc.) mais quelques contacts ont des informations manquantes :
- Note de relance oubliée
- Numéro de téléphone mis à jour pendant l'appel non saisi
- Statut mal sélectionné dans la précipitation

Elle voudrait rouvrir la session terminée pour corriger ces informations **dans les heures qui suivent**, sans recréer une nouvelle session.

### Ce qui existe aujourd'hui

Quand une session passe à `statut: 'done'`, le `ProspectionDetailPanel` s'ouvre en lecture seule. Il montre les stats (intéressés, injoignables, relances) mais ne permet aucune modification.

Le bouton **Éditer** existant (`handleEdit`) dans `TabProspection` permet de modifier la **liste de contacts** (ajouter/retirer) mais pas les résultats (statuts, notes, relances).

---

## État cible

### Nouvelle action : "Modifier les résultats"

Dans `ProspectionDetailPanel` (vue détail d'une session terminée), ajouter un bouton **"Modifier les résultats"** qui ouvre une vue d'édition des résultats de session.

```
┌──────────────────────────────────────────────────────┐
│ Session : Lyon - Industrie · 24/03/2026              │
│ 12 appelés · 2 intéressés · 3 injoignables · 1 relance│
├──────────────────────────────────────────────────────┤
│ [Modifier les contacts ▸]  [Modifier les résultats ▸]│
└──────────────────────────────────────────────────────┘
```

### Vue "Modifier les résultats"

Réutilise `ProspectionActive` avec un mode `readOnly=false` mais sans la logique de "nouvelle session". Les contacts déjà traités sont affichés avec leurs statuts actuels modifiables.

**Différences avec la session active normale :**
- Titre : "Correction · [Nom de la session]" (au lieu du nom brut)
- Pas de contact en statut `none` — tous ont déjà un statut
- Le bouton "Terminer la session" devient **"Enregistrer les modifications"**
- Pas de nouveau log d'historique "Appel sortant" pour les contacts non modifiés (évite les doublons)
- **Seuls les contacts dont le statut OU les notes ont changé** génèrent un nouvel historique

### Logique de sauvegarde (`handleSaveEdits`)

```js
// Différences par rapport à handleTerminer :
// 1. On ne recrée pas d'historique pour les inchangés
// 2. On ne recrée pas de tâches relances déjà existantes
// 3. On met à jour les tâches relances existantes si date/note changée
// 4. On peut ajouter de nouvelles tâches relances pour les contacts qui n'en avaient pas

var relancesExistantes = await sb.from('taches')
  .select('id, contact_id')
  .eq('session_prospection_id', session.id);

for (const sc of modifiedContacts) {
  // Mettre à jour session_prospection_contacts
  await sb.from('session_prospection_contacts').upsert({
    session_id: session.id, contact_id: sc.id,
    statut: sc.status, notes: sc.notes,
    want_relance: sc.wantRelance,
    relance_date: sc.relanceDate || null,
    relance_note: sc.relanceNote || null,
  });

  // Gérer la relance : update si existante, insert si nouvelle
  const existing = relancesExistantes.data.find(r => r.contact_id === sc.id);
  if (sc.wantRelance && sc.relanceDate) {
    if (existing) {
      await sb.from('taches').update({
        due_date: sc.relanceDate,
        notes: ['Session : ' + session.nom, sc.relanceNote || null].filter(Boolean).join('\n'),
      }).eq('id', existing.id);
    } else {
      // Nouvelle relance — avec gestion d'erreur
      const { error: relErr } = await sb.from('taches').insert({
        titre: `Relance ${sc.prenom} ${sc.nom} — ${sc.groupe}`.trim(),
        statut: 'a_faire', due_date: sc.relanceDate,
        contact_id: sc.id, session_prospection_id: session.id,
        notes: ['Session : ' + session.nom, sc.relanceNote || null].filter(Boolean).join('\n'),
        responsable: profile.nom,
      });
      if (relErr) toast('⚠️ Erreur relance : ' + relErr.message, 'error');
    }
  } else if (!sc.wantRelance && existing) {
    // Suppression de relance décochée
    await sb.from('taches').delete().eq('id', existing.id);
  }
}
```

---

## Contraintes et limites

- **Qui peut modifier ?** Le `responsable` de la session (vérifié côté UI avec `session.responsable === profile.nom`) OU un admin.
- **Délai ?** Pas de contrainte de délai en V1. Si nécessaire, limiter à 7 jours après la session en V2.
- **Contacts non traités (`statut: none`) ?** Non modifiables via cette vue — ils n'apparaissent pas dans la liste des résultats (filtre `appeles` uniquement).

---

## Acceptance criteria

- [ ] Le `ProspectionDetailPanel` d'une session terminée affiche un bouton "Modifier les résultats" (si `session.responsable === profile.nom` OU admin)
- [ ] La vue d'édition affiche tous les contacts appelés avec leurs statuts et notes actuels
- [ ] Modifier un statut met à jour `session_prospection_contacts`
- [ ] Ajouter/modifier une relance → upsert dans `taches` avec gestion d'erreur
- [ ] Supprimer une relance (décocher) → delete dans `taches`
- [ ] Les stats de la session (nb_interesses, nb_relances, etc.) se recalculent à la sauvegarde
- [ ] Un log distinct est créé dans `historique_actions` : `type_action: 'Correction session'`
- [ ] Aucune régression sur la session active normale (mode création)
