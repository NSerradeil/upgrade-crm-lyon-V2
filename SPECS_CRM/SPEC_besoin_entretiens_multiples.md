# SPEC — Besoins : entretiens par candidat + statut "Entretien"

**Fichier cible :** `supabase/CRM_Live.html`
**SQL migration :** `supabase/migrations/YYYYMMDD_candidat_entretien.sql`
**Composants touchés :** `BesoinDetail` (section candidats), `CANDIDAT_STATUTS`
**Deploy :** `bash supabase/deploy_staging.sh` → **staging uniquement, jamais main**

---

## 1. Analyse de l'existant

| Élément | État actuel |
|---|---|
| `date_entretien` | Champ unique global sur la table `besoins` |
| Statuts candidat | `en_attente → proposé → retenu / refusé` |
| Table `besoin_candidats` | id, besoin_id, contact_id, statut, tjm_propose, created_by |

**Problème :** Avec plusieurs candidats, il n'est pas possible de planifier un entretien distinct par personne. La date est mutualisée sur le besoin.

---

## 2. Décision produit — éviter l'usine à gaz

**Principe directeur :** une ligne candidat = un statut + une date d'entretien optionnelle. Pas de table d'entretiens séparée, pas de calendrier, pas d'invitations email. Juste un champ date inline sur la ligne du candidat.

**Ce qu'on NE fait PAS :**
- ❌ Table `entretiens` séparée avec type/lieu/participants
- ❌ Notifications ou rappels automatiques
- ❌ Calendrier intégré
- ❌ Workflow multi-étapes (1er entretien, 2ème entretien…)
- ❌ Supprimer le champ `date_entretien` global du besoin (backward compat)

---

## 3. Migration SQL

### Fichier : `supabase/migrations/YYYYMMDD_candidat_entretien.sql`

```sql
-- Ajout du champ date_entretien sur besoin_candidats
ALTER TABLE besoin_candidats
  ADD COLUMN IF NOT EXISTS date_entretien TIMESTAMPTZ;

-- Le champ date_entretien global sur besoins est conservé (rétrocompatibilité)
-- Il n'est plus affiché dans le formulaire d'édition (remplacé par les dates par candidat)
```

C'est tout. **Une seule colonne ajoutée.**

---

## 4. Mise à jour de `CANDIDAT_STATUTS`

Ajouter le statut `entretien` entre `propose` et `retenu` :

```js
// Avant
const CANDIDAT_STATUTS = [
  { value: 'en_attente', label: 'En attente',  color: 'bg-neutral-100 text-slate',   dot: 'bg-neutral-300' },
  { value: 'propose',    label: 'Proposé',      color: 'bg-azure-20 text-azure-100',  dot: 'bg-azure-200'   },
  { value: 'retenu',     label: 'Retenu',       color: 'bg-jade-20 text-jade-100',    dot: 'bg-jade-200'    },
  { value: 'refuse',     label: 'Refusé',       color: 'bg-coral-20 text-coral-100',  dot: 'bg-coral-200'   },
];

// Après — ajouter 'entretien' entre 'propose' et 'retenu'
const CANDIDAT_STATUTS = [
  { value: 'en_attente', label: 'En attente',  color: 'bg-neutral-100 text-slate',    dot: 'bg-neutral-300'  },
  { value: 'propose',    label: 'Proposé',      color: 'bg-azure-20 text-azure-100',   dot: 'bg-azure-200'    },
  { value: 'entretien',  label: 'Entretien',    color: 'bg-lemon-20 text-yellow-700',  dot: 'bg-yellow-400'   },
  { value: 'retenu',     label: 'Retenu',       color: 'bg-jade-20 text-jade-100',     dot: 'bg-jade-200'     },
  { value: 'refuse',     label: 'Refusé',       color: 'bg-coral-20 text-coral-100',   dot: 'bg-coral-200'    },
];
```

> Couleur choisie : **jaune** (`bg-lemon-20 text-yellow-700`) — cohérent avec le code couleur existant (jaune = attention/en cours dans la charte Upgrade).

---

## 5. Modification du rendu candidat dans `BesoinDetail`

### Logique : date inline conditionnelle

Quand le statut d'un candidat est `'entretien'`, afficher un champ datetime compact directement sur sa ligne.

### Nouvelle fonction `updateEntretien`

```js
async function updateEntretien(id, dateVal) {
  await sb.from('besoin_candidats')
    .update({ date_entretien: dateVal || null })
    .eq('id', id);
  // Recharger les candidats
  await loadCandidats();
}
```

### Nouveau rendu de la ligne candidat

```jsx
{candidats.map(bc => {
  const c = contactMap[bc.contact_id];
  const st = CANDIDAT_STATUTS.find(s => s.value === bc.statut) || CANDIDAT_STATUTS[0];
  const showDate = bc.statut === 'entretien';

  return (
    <div key={bc.id} style={{
      display: 'flex', alignItems: 'center', gap: 8,
      flexWrap: 'wrap',
      background: showDate ? '#FFFDE7' : '#F9F9F9',  // fond jaune léger si entretien
      padding: '8px 12px',
      borderLeft: showDate ? '3px solid #FFE500' : '3px solid transparent',
    }}>

      {/* Dot statut */}
      <span style={{ width: 8, height: 8, borderRadius: '50%', background: st.dot, flexShrink: 0 }}/>

      {/* Nom du candidat */}
      <button
        onClick={() => onNavToContact?.(bc.contact_id)}
        style={{ fontWeight: 700, fontSize: 13, color: '#1C1F35', textDecoration: 'underline', background: 'none', border: 'none', cursor: 'pointer', flex: 1, textAlign: 'left' }}
      >
        {c?.prenom} {c?.nom}
      </button>

      {/* TJM proposé */}
      {!readOnly && (
        <input
          type="number"
          placeholder="TJM"
          defaultValue={bc.tjm_propose}
          onBlur={e => updateTjm(bc.id, e.target.value)}
          style={{ width: 64, fontSize: 12, padding: '3px 6px', border: '1px solid #E4E4E6', textAlign: 'right', borderRadius: 0 }}
        />
      )}

      {/* Dropdown statut */}
      {!readOnly && (
        <select
          value={bc.statut}
          onChange={e => updateStatut(bc.id, e.target.value)}
          style={{ fontSize: 11, padding: '3px 6px', fontWeight: 700, borderRadius: 0, border: '2px solid #1C1F35', background: '#fff', cursor: 'pointer' }}
        >
          {CANDIDAT_STATUTS.map(s => (
            <option key={s.value} value={s.value}>{s.label}</option>
          ))}
        </select>
      )}

      {/* Date entretien — visible uniquement si statut = entretien */}
      {!readOnly && showDate && (
        <input
          type="datetime-local"
          value={bc.date_entretien ? bc.date_entretien.slice(0, 16) : ''}
          onChange={e => updateEntretien(bc.id, e.target.value || null)}
          style={{
            fontSize: 11, padding: '3px 6px',
            border: '2px solid #FFE500',
            borderRadius: 0, background: '#fff',
            color: '#1C1F35', fontFamily: 'Outfit, sans-serif',
          }}
        />
      )}

      {/* Affichage date si readOnly */}
      {readOnly && showDate && bc.date_entretien && (
        <span style={{ fontSize: 11, color: '#92400e', fontWeight: 700 }}>
          📅 {new Date(bc.date_entretien).toLocaleDateString('fr-FR', { day:'2-digit', month:'short', hour:'2-digit', minute:'2-digit' })}
        </span>
      )}

      {/* Bouton retirer candidat */}
      {!readOnly && (
        <button
          onClick={() => removeCandidat(bc.id)}
          style={{ fontSize: 14, color: '#FF3D2E', background: 'none', border: 'none', cursor: 'pointer', lineHeight: 1 }}
        >×</button>
      )}
    </div>
  );
})}
```

---

## 6. Mise à jour du formulaire d'édition du besoin (`BesoinFormModal`)

### Retirer le champ `date_entretien` global du formulaire d'édition

Le champ `date_entretien` global du besoin **ne doit plus apparaître** dans le formulaire d'édition — il est remplacé par les dates par candidat.

Chercher dans `BesoinFormModal` le champ :
```jsx
// Supprimer ce champ (ou le masquer)
<label>Date entretien</label>
<input type="datetime-local" ... name="date_entretien" ... />
```

> ⚠️ Conserver la colonne en base (backward compat), supprimer uniquement le champ du formulaire.

---

## 7. Résumé du flux utilisateur

```
Candidat ajouté au besoin
    → statut : En attente

Nicolas propose le profil au client
    → statut : Proposé

Client souhaite rencontrer le candidat
    → statut : Entretien  ← NOUVEAU
    → une date apparaît automatiquement sur la ligne
    → Nicolas saisit la date/heure de l'entretien

Après entretien
    → statut : Retenu  ou  Refusé
```

---

## 8. Critères QA

| # | Test | Attendu |
|---|---|---|
| 1 | Dropdown candidat | 5 options : En attente / Proposé / **Entretien** / Retenu / Refusé |
| 2 | Passage à "Entretien" | Champ datetime apparaît inline sur la ligne du candidat, fond jaune léger |
| 3 | Saisie date entretien | Sauvegarde dans `besoin_candidats.date_entretien` (sans rechargement full page) |
| 4 | 2 candidats "Entretien" | Chaque ligne a son propre champ date, indépendant |
| 5 | Retour à "Proposé" | Champ date disparaît, date conservée en base mais non affichée |
| 6 | Formulaire édition besoin | Champ `date_entretien` global absent du formulaire |
| 7 | Mode readOnly | Date entretien affichée en texte formaté (📅 27 mar. 14:00), pas de champ input |
| 8 | border-radius | Tous les nouveaux éléments à `borderRadius: 0` |
| 9 | Migration SQL | `ALTER TABLE besoin_candidats ADD COLUMN date_entretien TIMESTAMPTZ` sans erreur |
| 10 | Deploy | `bash supabase/deploy_staging.sh` — jamais main |
