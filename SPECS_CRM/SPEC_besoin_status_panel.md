# SPEC — Status-first SidePanel · Besoins
**CRM Upgrade Lyon V2** · Évolution UX prioritaire
**Auteur :** Nicolas Serradeil + Claude (PM + Lead UX)
**Date :** 24/03/2026

---

## Contexte & challenge produit

### Besoin exprimé
> "Sur le besoin, pour changer le statut faut cliquer sur Modifier. Est-ce possible d'avoir les statuts dans le panneau latéral quand on clique sur une carte pour changer le statut plus vite ? Quand on clique sur le statut ça ouvre le panneau modifier en mettant au bon statut + champs contextuels."

### Challenge UX adopté
Le pattern "ouvrir Modifier pré-rempli" reste 2 étapes (clic statut → confirmer). En workflow commercial actif (appels, revue de pipe), c'est un clic et un changement de contexte de trop.

**Pattern initial proposé : Status-first inline (micro-form dans le panel)**
Le statut devient l'action primaire du SidePanel. Les champs contextuels viennent au contact, dans le panel, selon le statut choisi.

### ⚠️ Contrainte technique — Révision du pattern

**Problème identifié :** Dans l'architecture actuelle du CRM (single-file HTML + vanilla JS + Supabase direct), les actions déclenchées depuis des composants générés dynamiquement (innerHTML) dans un overlay perdent parfois le scope de la fonction de refresh parent. Ce bug a déjà été rencontré sur les actions inline des KPI Prospection (statuts ne persistant pas en base malgré l'appel Supabase).

**Pattern révisé : hybride simple/contextuel**

| Type de statut | Comportement | Implémentation |
|---|---|---|
| **Simples** (Opportunité → Profil proposé) | 1 clic → `crm_update_besoin()` direct + toast undo | Appel direct Supabase, même pattern que les CTA existants ✅ |
| **Contextuels** (Entretien prog/passé, Gagné, Perdu) | Clic → ouvre `renderModifierBesoin()` existant, pré-scrollé au bon statut avec champs contextuels filtrés | Réutilise le code Modifier éprouvé, zéro risque ✅ |

**Gain UX conservé :** 60-70% des changements de statut sont des statuts simples → 1 clic. Pour les statuts contextuels, le Modifier s'ouvre positionné et filtré → gain de temps réel vs l'actuel.

---

## Pipeline des statuts

```
Opportunité → Push opportuniste → Besoin ouvert → Profil proposé
    → Entretien programmé → Entretien passé → Besoin Gagné | Besoin Perdu
```

---

## Spécification du composant `BesoinSidePanel`

### Zone "Statut" dans le panel — nouveau comportement

**Emplacement :** Dans le header du SidePanel, en dessous du titre et du compte. Remplace le badge statut statique actuel.

**Rendu :**
Un stepper horizontal (ou vertical si espace contraint) affichant tous les statuts du pipeline. Le statut actuel est highlighted (fond couleur + bordure). Les statuts passés sont grisés avec coche. Les statuts futurs sont en outline.

**Interaction :**
```
Click statut → deux comportements selon le statut cible :
  1. Statut "simple" (aucun champ requis) → mise à jour immédiate + toast undo
  2. Statut "contextuel" (champs requis) → micro-form inline s'ouvre dans le panel
```

---

## Matrice statuts × comportement × champs

| Statut | Type | Champs inline |
|--------|------|---------------|
| Opportunité | simple | — |
| Push opportuniste | simple | — |
| Besoin ouvert | simple | — |
| Profil proposé | simple | nb_profils_envoyes (number, optionnel), date_envoi (date, auto aujourd'hui) |
| Entretien programmé | **contextuel** | date_entretien (date+heure, **requis**), type_entretien (select: visio/présentiel/tél), interlocuteur_client (text) |
| Entretien passé | **contextuel** | cr_entretien (textarea, **requis**), resultat (select: positif/négatif/à suivre, **requis**) |
| Besoin Gagné | **contextuel** | date_demarrage (date, **requis**), duree_estimee (text), tjm_negocie (number, optionnel) |
| Besoin Perdu | **contextuel** | motif_perte (select: budget/concurrent/annulé/perdu de vue/autre, **requis**), commentaire (textarea, optionnel) |

---

## Spec comportement détaillée

### Statuts simples (1 clic) — appel direct Supabase

```
1. User clique sur le chip statut cible
2. Optimistic update : chip statut passe immédiatement à "actif" dans le panel
3. Appel direct : await supabase.from('besoins').update({ statut: newStatut }).eq('id', besoinId)
   — même pattern que les CTA "INTÉRESSÉ / PAS JOIGNABLE" de prospection qui fonctionnent
4. Toast : "Statut → [Nom statut]  [↩ Annuler 5s]"
5. Si Annuler dans les 5s : rollback Supabase + rollback chip
6. Callback refresh du panel parent (fonction passée en paramètre, pas en innerHTML)
```

⚠️ **Impératif Claude Code :** Le handler onclick doit être attaché via `addEventListener` (pas via attribut `onclick=""` dans du innerHTML dynamique) pour garantir l'accès au scope Supabase et au callback parent.

```js
// ✅ Pattern correct
chip.addEventListener('click', async () => {
  await updateStatutSimple(besoinId, newStatut, onRefresh);
});

// ❌ Pattern à éviter (perd le scope)
chip.innerHTML = `<span onclick="updateStatut('${besoinId}')">...</span>`;
```

### Statuts contextuels — ouvre Modifier existant pré-positionné

```
1. User clique sur le chip statut contextuel
2. Appel : renderModifierBesoin(besoinId, {
     preSelectStatut: statutId,
     filtreChamps: ['date_entretien', 'type_entretien', 'interlocuteur']  // selon le statut
   })
3. Le panneau Modifier s'ouvre — même code existant, même Supabase handler qui marche
4. Le statut est pré-sélectionné, seuls les champs pertinents sont affichés en premier
5. L'utilisateur complète et sauvegarde normalement
```

**Avantage :** Zéro risque de régression — on réutilise `renderModifierBesoin()` tel quel, on ajoute seulement un paramètre `preSelectStatut` et éventuellement un tri/highlight des champs contextuels.

---

## Champs contextuels détaillés

### Entretien programmé
```jsx
<DateTimePicker label="Date de l'entretien *" />
<Select label="Format" options={['Visio', 'Présentiel', 'Téléphone']} defaultValue="Visio" />
<TextInput label="Interlocuteur client" placeholder="Prénom NOM, titre" />
```
→ À la confirmation : crée automatiquement une tâche CRM "Entretien [date]" associée au besoin

### Entretien passé
```jsx
<Textarea label="Compte-rendu *" placeholder="Points clés de l'entretien..." rows={4} />
<Select label="Résultat *" options={['Positif — à suivre', 'Négatif', 'En attente retour']} />
```
→ Si résultat = Négatif → propose automatiquement passage à "Besoin Perdu"

### Besoin Gagné
```jsx
<DatePicker label="Date de démarrage *" />
<TextInput label="Durée estimée" placeholder="ex : 3 mois, indéfini" />
<NumberInput label="TJM négocié (€)" placeholder="Optionnel" />
```

### Besoin Perdu
```jsx
<Select label="Motif *" options={['Budget insuffisant', 'Choix concurrent', 'Besoin annulé', 'Perdu de vue', 'Autre']} />
<Textarea label="Commentaire" placeholder="Contexte, apprentissage..." rows={3} />
```

---

## Layout du SidePanel — zones

```
┌─────────────────────────────────────────────┐
│ [← Fermer]  TITRE BESOIN            [EDIT ✏]│  ← header minimal
│ Compte · Responsable · Créé le              │
├─────────────────────────────────────────────┤
│ STATUT PIPELINE                             │  ← zone statut interactive
│ [Opport.] [Push] [Ouvert] [Profil]          │
│ [📅 Entretien prog.▸] [Passé] [✓ Gagné] [✗]│
│                                             │
│ ↓ MICRO-FORM (visible si statut contextuel) │
│ ┌─────────────────────────────────────────┐ │
│ │ 📅 Passage à Entretien programmé        │ │
│ │ Date *  [    /    /      hh:mm        ] │ │
│ │ Format  [ Visio ▾ ]                     │ │
│ │ Interlocuteur [                       ] │ │
│ │          [CONFIRMER]  [Annuler]         │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ [+ ACTION] [✓ TÂCHE] [× ANNULER]           │  ← CTAs existants inchangés
├─────────────────────────────────────────────┤
│ CONTEXTE / CANDIDATS / HISTORIQUE           │  ← tabs existants inchangés
└─────────────────────────────────────────────┘
```

---

## Tokens visuels (brutalist style)

```js
// Chip statut inactif (futur ou passé)
chipInactive: {
  border: `1px solid ${C.border}`,
  background: 'white',
  color: C.mid,
  borderRadius: 0,
  padding: '4px 10px',
  fontSize: 11,
  fontWeight: 700,
  cursor: 'pointer',
  transition: 'none',
}

// Chip statut actif (current)
chipActive: {
  border: '0',
  background: C.midnight,
  color: 'white',
  boxShadow: `3px 3px 0 ${statusColor}`,
  transform: 'translate(-1px, -1px)',
  padding: '4px 10px',
  fontSize: 11,
  fontWeight: 900,
}

// Chip statut passé (done)
chipDone: {
  ...chipInactive,
  color: '#aaa',
  borderColor: '#ddd',
  textDecoration: 'line-through',  // optionnel
}

// Chip hover (statut futur)
chipHover: {
  background: C.midnight,
  color: 'white',
  cursor: 'pointer',
}

// Micro-form container
microForm: {
  border: `2px solid ${C.midnight}`,
  boxShadow: `4px 4px 0 ${statusColor}`,
  background: '#FAFAFA',
  padding: 16,
  margin: '8px 0',
  borderRadius: 0,
}
```

---

## Impact API / backend

```js
// Appel simple (statuts sans champs)
crm_update_besoin({
  id: besoinId,
  statut: newStatut,
  date_modif_statut: new Date().toISOString(),
})

// Appel contextuel (Entretien programmé)
crm_update_besoin({
  id: besoinId,
  statut: 'Entretien programmé',
  date_entretien: '2026-04-02T14:00:00',
  type_entretien: 'Visio',
  interlocuteur_client: 'Marie DUPONT, DRH',
  date_modif_statut: new Date().toISOString(),
})
// + crm_create_task({ titre: 'Entretien X...', date_echeance, besoin_id })
```

---

## Ce qu'on ne touche pas

- Le bouton MODIFIER reste présent pour les modifications profondes (titre, compte, responsable, etc.)
- Les CTAs + ACTION / TÂCHE / ANNULER restent inchangés
- Les tabs Contexte / Candidats / Historique restent inchangés
- Le comportement du KPI card "Pipe" dans le dashboard reste inchangé

---

## Acceptance criteria (Claude Code)

- [ ] Le chip du statut courant est visuellement distinct (midnight bg + shadow couleur)
- [ ] Clic sur statut simple → update immédiat + toast undo 5s
- [ ] Clic sur statut contextuel → micro-form s'ouvre inline dans le panel (pas de navigation)
- [ ] Champs requis bloquent le submit + feedback inline
- [ ] À la confirmation → toast + rafraîchissement du panel
- [ ] Annuler dans la micro-form → aucune modification
- [ ] Entretien programmé → création automatique d'une tâche CRM
- [ ] Aucune régression sur les autres zones du SidePanel
