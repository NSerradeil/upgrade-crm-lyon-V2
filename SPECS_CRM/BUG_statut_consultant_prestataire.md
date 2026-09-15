# BUG + SPEC — Suppression statut "Consultant" → "Prestataire"
**CRM Upgrade Lyon V2**
**Date :** 28/03/2026

---

## Problème

Le statut `Consultant` existe dans le dropdown et dans les données — il ne doit plus exister. Il est source de confusion avec `Consultant CDI` et `Freelance`.

---

## Changements attendus

### 1. Statuts valides (liste exhaustive après fix)

| Statut | Couleur badge |
|---|---|
| Client | (existant, inchangé) |
| Prospect | (existant, inchangé) |
| Lead | (existant, inchangé) |
| Candidat | (existant, inchangé) |
| Freelance | (existant, inchangé) |
| Consultant CDI | (existant, inchangé) |
| **Prestataire** | **Orange — `#F97316` fond, blanc texte** (nouveau, ≠ jaune) |

→ `Consultant` est **supprimé** de la liste des statuts valides et du dropdown filtre.

---

### 2. Couleur du badge Prestataire

**NE PAS** utiliser le jaune `#FFD600` (déjà utilisé pour Freelance / Consultant CDI).

```css
/* Badge Prestataire */
background-color: #F97316;   /* orange Upgrade */
color: #FFFFFF;
font-weight: 700;
```

---

### 3. Migration des données — contacts à mettre à jour

#### → Statut : `Prestataire`
Uniquement ces 2 contacts (les seuls vrais prestataires) :

| Nom | Nouveau statut |
|---|---|
| Marie AUPHAN | Prestataire |
| Etna VILALLONGA | Prestataire |

#### → Statut : `Consultant CDI`
Contacts actuellement en `Consultant` (ou `Consultant CDI`) dont le profil indique un CDI :

| Nom | Sous-titre actuel | Nouveau statut |
|---|---|---|
| Marta MANDARIC | Consultant CDI | Consultant CDI (inchangé) |
| Weronika SAWICKI | Consultant CDI | Consultant CDI (inchangé) |
| Mathilde PIERRE | Consultant CDI | Consultant CDI (inchangé) |

#### → Statut : `Freelance`
Contacts actuellement en `Consultant` dont le profil indique Freelance ou Portage :

| Nom | Sous-titre actuel | Nouveau statut |
|---|---|---|
| Julien BANON | Consultant Freelance | Freelance |
| Bertrand COLOMBO | Consultant Freelance – Portage Enedis | Freelance |
| Cyril CODOGNO | Consultant Freelance – Portage Enedis | Freelance |

> **Note :** Si d'autres contacts ont le statut `Consultant` sans indication claire, les passer en `Freelance` par défaut (cas le plus courant dans notre activité).

---

### 4. Migration SQL à exécuter en base

```sql
-- Passer tous les "Consultant" restants en Freelance par défaut
UPDATE contacts
SET statut = 'Freelance'
WHERE statut = 'Consultant';

-- Recorriger les CDI
UPDATE contacts
SET statut = 'Consultant CDI'
WHERE nom IN ('Marta MANDARIC', 'Weronika SAWICKI', 'Mathilde PIERRE');

-- Passer les 2 prestataires
UPDATE contacts
SET statut = 'Prestataire'
WHERE nom IN ('Marie AUPHAN', 'Etna VILALLONGA');
```

> Adapter les noms exacts selon la colonne `nom` ou `prenom || ' ' || nom` selon le schéma réel.

---

### 5. Changements frontend

#### Dropdown filtre statut (onglet Contacts)
```
Tous statuts
Candidat
Client
Consultant CDI
Freelance
Prestataire       ← nouveau
Prospect
```
→ Supprimer `Consultant` de cette liste.

#### Mapping couleur badge dans le composant
```js
const STATUT_COLORS = {
  'Client':        { bg: '#FFD600', text: '#000' },
  'Prospect':      { bg: '#E5E7EB', text: '#111' },
  'Lead':          { bg: '#DBEAFE', text: '#1D4ED8' },
  'Candidat':      { bg: '#F3F4F6', text: '#374151' },
  'Freelance':     { bg: '#FFD600', text: '#000' },
  'Consultant CDI':{ bg: '#FFD600', text: '#000' },
  'Prestataire':   { bg: '#F97316', text: '#FFF' },  // ← nouveau
};
```

#### Formulaire de création/édition contact
Remplacer `Consultant` par `Prestataire` dans le `<select>` du champ statut.

---

## Acceptance criteria

- [ ] `Consultant` n'apparaît plus dans le dropdown filtre ni dans le formulaire de création/édition
- [ ] Les contacts Marie Auphan et Etna Vilallonga ont le statut `Prestataire`
- [ ] Tous les anciens `Consultant Freelance` sont en `Freelance`
- [ ] Tous les anciens `Consultant CDI` sont inchangés
- [ ] Le badge `Prestataire` est orange (`#F97316` / texte blanc), distinct du jaune des autres statuts
- [ ] Aucun contact ne reste avec le statut `Consultant` en base
