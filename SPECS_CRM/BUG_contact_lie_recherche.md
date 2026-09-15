# BUG — Champ "Contact lié" non fonctionnel dans le formulaire Besoin
**CRM Upgrade Lyon V2**
**Date :** 03/04/2026

---

## Contexte

Dans le formulaire de création/édition d'un besoin (modale ouverte depuis le pipe ou le détail contact), le champ **CONTACT LIÉ** affiche un input de recherche avec le placeholder "Rechercher par nom, société…" mais la saisie ne déclenche aucun résultat.

---

## Symptôme précis (mis à jour)

- La recherche **fonctionne uniquement pour "Amandine Le Gourierrec"**
- Tout autre nom/société ne retourne aucun résultat
- Ce n'est pas un bug de déclenchement (la requête part) mais un bug de **périmètre de données ou de filtre**

---

## Analyse — Cause probable

Le fait qu'**un seul contact soit trouvable** oriente vers l'une de ces causes :

### Cause 1 — Filtre `responsable` ou `agence` appliqué en dur dans la requête
```js
// La requête est probablement filtrée sur l'utilisateur courant ou une agence,
// ce qui exclut tous les contacts sauf ceux du commercial connecté au moment du dev :
const { data } = await sb
  .from('contacts')
  .select('id, prenom, nom, societe')
  .eq('responsable', currentUser)          // ← filtre trop restrictif
  .or(`nom.ilike.%${query}%,...`)
  .limit(10);

// Fix : retirer le filtre responsable, la recherche Contact lié doit
// porter sur TOUS les contacts de la base, toutes agences confondues.
```

### Cause 2 — Données corrompues / champ `nom` vide pour la majorité des contacts
```js
// Si la colonne nom est vide pour la plupart des contacts et que la recherche
// porte uniquement sur `nom`, seuls les contacts avec un nom renseigné remontent.
// Fix : ajouter prenom et societe dans le OR, et vérifier la qualité des données.
.or(`nom.ilike.%${query}%,prenom.ilike.%${query}%,societe.ilike.%${query}%`)
```

### Cause 3 — Filtre `statut` excluant la majorité des contacts
```js
// La requête filtre peut-être sur un statut spécifique (ex: 'Client' uniquement)
// alors que le champ Contact lié doit pouvoir pointer vers n'importe quel contact.
// Vérifier l'absence de filtre statut dans cette requête.
```

### Cause 4 — Cache ou state non réinitialisé entre deux ouvertures de modale
```js
// Si le state contactSuggestions est initialisé avec [Amandine] en dur
// (valeur de test laissée en dev), il ne se met jamais à jour proprement.
const [contactSuggestions, setContactSuggestions] = useState([]);
// ← vérifier qu'il n'y a pas de valeur initiale hardcodée
```

---

## Fix attendu

```js
// Requête corrigée — aucun filtre autre que la recherche texte
const handleContactSearch = async (query) => {
  if (query.length < 2) return;
  const { data } = await sb
    .from('contacts')
    .select('id, prenom, nom, societe, statut')
    .or(`nom.ilike.%${query}%,prenom.ilike.%${query}%,societe.ilike.%${query}%`)
    .order('nom', { ascending: true })
    .limit(10);
  setContactSuggestions(data || []);
};
```

**Pas de filtre sur** : `responsable`, `agence`, `statut`, `created_by`.

---

## Comportement attendu après fix

### UX cible du champ Contact lié

```
[Rechercher par nom, société...]
         ↓ (dès 2 caractères)
┌─────────────────────────────────────┐
│ Hugo MORIN · EDF Renouvelables      │
│ Hugo BERNARD · Groupama             │
│ Marie AUPHAN · Enedis               │
└─────────────────────────────────────┘
```

- Recherche déclenchée à partir de **2 caractères**
- Résultats en dropdown sous l'input, max **10 suggestions**
- Chaque ligne affiche : `Prénom NOM · Société`
- Clic sur une suggestion → contact sélectionné, chip affiché dans le champ, input masqué
- Chip cliquable avec un ×  pour désélectionner

### Chip après sélection

```jsx
<div style={{
  display: 'inline-flex', alignItems: 'center', gap: 6,
  background: '#F3F4F6', border: '1px solid #E5E7EB',
  borderRadius: 6, padding: '4px 10px', fontSize: 13,
}}>
  <span>{contact.prenom} {contact.nom}</span>
  <span style={{ color: '#9CA3AF', fontSize: 11 }}>{contact.societe}</span>
  <button onClick={clearContact} style={{ ...resetBtn, color: '#6B7280' }}>×</button>
</div>
```

---

## Acceptance criteria

- [ ] Taper 2+ caractères dans le champ Contact lié → dropdown de suggestions apparaît
- [ ] La recherche porte sur `nom`, `prenom` ET `societe` (recherche partielle `ilike`)
- [ ] Cliquer sur une suggestion → contact sélectionné, affiché en chip, `contact_id` stocké dans le formulaire
- [ ] Le chip affiche prénom + nom + société
- [ ] Le × sur le chip désélectionne le contact et remet l'input visible
- [ ] Si aucun résultat → afficher "Aucun contact trouvé" dans la dropdown (pas de dropdown vide)
- [ ] Le champ fonctionne aussi bien en création qu'en édition d'un besoin existant
- [ ] En édition : si un contact est déjà lié, il est pré-affiché en chip au chargement du formulaire
