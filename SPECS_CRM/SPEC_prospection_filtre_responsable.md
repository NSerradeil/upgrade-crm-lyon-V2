# SPEC — Filtre Responsable dans Nouvelle Session de Prospection
**CRM Upgrade Lyon V2** · Évolution mineure
**Auteur :** Nicolas Serradeil + Claude
**Date :** 24/03/2026

---

## Besoin

> "Ajouter le filtre responsable dans la création de session de prospection, pour voir plus facilement les contacts que l'on a chassé soi-même."

---

## État actuel

Filtres disponibles sur l'écran NOUVELLE SESSION DE PROSPECTION :
```
[NOM DE LA SESSION] [AGENCE ▾] [DERNIER CONTACT > X JOURS ▾]
```

## État cible

```
[NOM DE LA SESSION] [AGENCE ▾] [RESPONSABLE ▾] [DERNIER CONTACT > X JOURS ▾]
```

---

## Spec du filtre RESPONSABLE

### Valeurs du select

```
Tous les responsables    ← valeur par défaut
─────────────────────
★ Moi (Nicolas Serradeil)   ← raccourci en haut, résolu dynamiquement via currentUser
─────────────────────
Amel Benzai
Anne Claire Decker
Augustin Debouvy
Camille Salinson
Nicolas Serradeil
Pierre Solle
```

L'option "★ Moi" est un raccourci dynamique qui sélectionne `currentUser.id` — utile pour switcher vite sans chercher son nom dans la liste.

### Comportement

- Filtre les contacts affichés dans la liste **en combinaison** avec le filtre AGENCE
- `responsable = null` → contact sans responsable toujours affiché (sauf si "Moi" sélectionné)
- Le compteur TOUT SÉLECTIONNER (N) se met à jour selon les filtres actifs
- Le filtre persiste si on revient à la liste après une sélection partielle

### Combinaisons clés

| AGENCE | RESPONSABLE | Résultat |
|---|---|---|
| Lyon | Tous | Tous les contacts Lyon (comportement actuel) |
| Lyon | ★ Moi | Mes contacts Lyon uniquement |
| Toutes agences | ★ Moi | **Tous mes contacts cross-agence** ← cas d'usage principal |
| Toutes agences | Amel Benzai | Tous les contacts suivis par Amel |

> La combinaison "Toutes agences + Moi" est le cas d'usage principal de cette évolution — voir l'ensemble de ses contacts chassés, quelle que soit leur agence.

---

## Connexion avec la spec cross-agence

Ce filtre prend tout son sens avec les permissions cross-agence (`SPEC_contacts_permissions_agence.md`) :
- Un commercial peut maintenant être responsable de contacts d'autres agences
- Ce filtre permet de retrouver ces contacts facilement au moment de créer une session
- À terme, "Toutes agences + Moi" = l'équivalent du filtre "Mes contacts" décrit dans la spec permissions

---

## Implémentation Claude Code

### Données

Les commerciaux sont déjà disponibles dans la variable `COMMERCIAUX` utilisée par les autres filtres du CRM (filtre "Tous les commerciaux" sur le dashboard Prospection). Réutiliser la même source.

```js
// Select RESPONSABLE — même construction que le select "Tous les commerciaux" existant
const responsableSelect = buildSelect({
  id: 'filter-responsable',
  label: 'RESPONSABLE',
  options: [
    { value: '', label: 'Tous les responsables' },
    { value: currentUser.id, label: `★ Moi (${currentUser.prenom} ${currentUser.nom})` },
    ...COMMERCIAUX.map(c => ({ value: c.id, label: `${c.prenom} ${c.nom}` }))
  ],
  onChange: () => filterContacts()
});
```

### Filtre contacts

```js
// Dans filterContacts() — ajouter la condition responsable
const responsableId = document.getElementById('filter-responsable').value;

contacts = contacts.filter(c => {
  const matchAgence = !selectedAgence || c.agence === selectedAgence;
  const matchResponsable = !responsableId || c.responsable_id === responsableId;
  const matchDelai = /* logique existante */;
  return matchAgence && matchResponsable && matchDelai;
});
```

---

## Acceptance criteria

- [ ] Le select RESPONSABLE s'affiche entre AGENCE et DERNIER CONTACT
- [ ] "Tous les responsables" est la valeur par défaut
- [ ] "★ Moi" filtre dynamiquement sur `currentUser.id`
- [ ] Le filtre se combine correctement avec AGENCE et DERNIER CONTACT
- [ ] Le compteur TOUT SÉLECTIONNER (N) se met à jour à chaque changement de filtre
- [ ] "Toutes agences + Moi" affiche les contacts cross-agence dont je suis responsable
- [ ] Aucune régression sur les filtres existants
