# SPEC — Harmonisation des boutons d'action dans les panels (passe complète)

**Fichier cible :** `supabase/CRM_Live.html`
**Composants concernés :** `ContactDetail`, `MissionDetail`, `BesoinDetail`, `TacheDetailPanel`
**Deploy :** `bash supabase/deploy_staging.sh` → **staging uniquement, jamais main**

---

## 1. Résumé des changements

| # | Changement |
|---|---|
| A | Nouvel **ordre** des boutons : `Action → Tâche → Modifier → Supprimer` |
| B | **Action** : shadow rouge brutalist `4px 4px 0 #FF3D2E` (= modèle bouton "Nouvelle mission") |
| C | **Tâche** : fond midnight + shadow jaune `4px 4px 0 #FFE500` (différencié d'Action) |
| D | **Modifier** : fond midnight + shadow bleu `4px 4px 0 #4A7FE5` (différencié d'Action et Tâche) |
| E | **Supprimer** : bouton complet avec texte "Supprimer", contour coral, shadow coral — pas d'icône seule |
| F | **Confirmation de suppression** : harmoniser en style brutalist (supprimer le `rounded` résiduel) |
| G | **Modale Tâche** : harmoniser l'apparence de la modale `AddTacheModal` avec `AddBesoinActionModal` |

---

## 2. Composant utilitaire `BtnAction`

Pour éviter la duplication, créer un composant helper réutilisable :

```jsx
function BtnAction({ onClick, icon, label, variant = 'primary', disabled = false }) {
  const VARIANTS = {
    // + Action — modèle "Nouvelle mission"
    primary: {
      background: '#1C1F35',
      color: '#ffffff',
      border: '2px solid #1C1F35',
      boxShadow: '4px 4px 0 #FF3D2E',
      transform: 'none',
    },
    // ✓ Tâche
    task: {
      background: '#1C1F35',
      color: '#ffffff',
      border: '2px solid #1C1F35',
      boxShadow: '4px 4px 0 #FFE500',
      transform: 'none',
    },
    // ✏ Modifier
    edit: {
      background: '#1C1F35',
      color: '#ffffff',
      border: '2px solid #1C1F35',
      boxShadow: '4px 4px 0 #4A7FE5',
      transform: 'none',
    },
    // ✕ Supprimer
    danger: {
      background: '#ffffff',
      color: '#FF3D2E',
      border: '2px solid #FF3D2E',
      boxShadow: '4px 4px 0 #FF3D2E',
      transform: 'none',
    },
  };

  const base = VARIANTS[variant];

  return (
    <button
      onClick={onClick}
      disabled={disabled}
      style={{
        ...base,
        padding: '6px 12px',
        fontSize: 12,
        fontWeight: 700,
        fontFamily: 'Outfit, sans-serif',
        letterSpacing: '0.03em',
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.5 : 1,
        display: 'inline-flex',
        alignItems: 'center',
        gap: 5,
        borderRadius: 0,        // IMPÉRATIF — charte brutalist
        transition: 'all 80ms ease',
        textTransform: 'uppercase',
      }}
      onMouseEnter={e => {
        if (!disabled) e.currentTarget.style.transform = 'translate(-2px, -2px)';
      }}
      onMouseLeave={e => {
        e.currentTarget.style.transform = 'none';
      }}
    >
      {icon && <Icon d={icon} size={13} />}
      {label}
    </button>
  );
}
```

---

## 3. Nouveau bloc de boutons — template commun

**Ordre imposé : `Action → Tâche → Modifier → Supprimer`**

```jsx
<div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>

  {/* 1. Action */}
  <BtnAction
    variant="primary"
    icon={ICONS.add}
    label="+ Action"
    onClick={() => setModal('hist')}
  />

  {/* 2. Tâche */}
  <BtnAction
    variant="task"
    icon={ICONS.check}
    label="✓ Tâche"
    onClick={() => setModal('tache')}
  />

  {/* 3. Modifier */}
  <BtnAction
    variant="edit"
    icon={ICONS.edit}
    label="Modifier"
    onClick={() => setModal('edit')}
  />

  {/* 4. Supprimer */}
  {modal !== 'confirmDel' ? (
    <BtnAction
      variant="danger"
      icon={ICONS.delete}
      label="Supprimer"
      onClick={() => setModal('confirmDel')}
    />
  ) : (
    <ConfirmDelete
      onConfirm={handleDelete}
      onCancel={() => setModal(null)}
      loading={deleting}
    />
  )}

</div>
```

---

## 4. Composant `ConfirmDelete` (confirmation de suppression harmonisée)

Remplacer les confirmations inline disparates par un composant cohérent :

```jsx
function ConfirmDelete({ onConfirm, onCancel, loading }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <span style={{
        fontSize: 11, fontWeight: 700, color: '#FF3D2E',
        textTransform: 'uppercase', letterSpacing: '0.05em',
      }}>
        Confirmer ?
      </span>
      <button
        onClick={onConfirm}
        disabled={loading}
        style={{
          background: '#FF3D2E', color: '#fff',
          border: '2px solid #FF3D2E',
          boxShadow: '3px 3px 0 #1C1F35',
          padding: '4px 12px', fontSize: 11, fontWeight: 800,
          borderRadius: 0, cursor: loading ? 'wait' : 'pointer',
          textTransform: 'uppercase', fontFamily: 'Outfit, sans-serif',
        }}
      >
        {loading ? '...' : 'Oui, supprimer'}
      </button>
      <button
        onClick={onCancel}
        style={{
          background: '#fff', color: '#1C1F35',
          border: '2px solid #1C1F35',
          padding: '4px 10px', fontSize: 11, fontWeight: 700,
          borderRadius: 0, cursor: 'pointer',
          textTransform: 'uppercase', fontFamily: 'Outfit, sans-serif',
        }}
      >
        Annuler
      </button>
    </div>
  );
}
```

> ⚠️ **Supprimer** le `rounded` résiduel (`rounded`, `rounded-sm`, etc.) présent dans les confirmations actuelles — incompatible avec la charte brutalist.

---

## 5. Adaptations par composant

### `ContactDetail` (ligne ~1111)

- Remplacer le bloc `const actions = isOwner && (<>...</>)` par le template §3
- `onClick` Modifier → `setModal('edit')`
- `onClick` Action → `setModal('hist')`
- `onClick` Tâche → `setModal('tache')`
- `onClick` Supprimer → `setModal('confirmDel')` + `ConfirmDelete`

### `MissionDetail` (ligne ~1386)

- Remplacer le bloc `const actions = canEdit ? (<div...>` par le template §3
- `onClick` Modifier → `setModal('edit')`
- `onClick` Action → `setShowAdd(true)` (ouvre `AddHistMissionModal`)
- `onClick` Tâche → `setModal('tache')`
- `onClick` Supprimer → `setModal('confirmDel')` + `DeleteMissionModal`

### `BesoinDetail` (ligne ~2480)

- Remplacer le bloc `const actions = isOwner && (<>...</>)` par le template §3
- Cas particulier : le bouton Modifier est un **toggle** (`editing ? 'Annuler' : 'Modifier'`)
  - État normal : `variant="edit"` + label `"Modifier"`
  - État édition actif : remplacer par un bouton `variant="task"` avec label `"✕ Annuler"` pour distinguer visuellement
- `onClick` Action → `setModal('hist')`
- `onClick` Tâche → `setModal('tache')`

### `TacheDetailPanel` (ligne ~1867)

- Ce panel n'a pas de bouton Tâche (logique) → remplacer "✓ Marquer fait" dans la position Tâche
- Ordre adapté : `Action → Marquer fait → Modifier → Supprimer`
- "Marquer fait" : `variant="task"` (shadow jaune — action positive)

```jsx
<BtnAction variant="task" icon={ICONS.check} label="✓ Marquer fait" onClick={onComplete} />
```

---

## 6. Harmonisation de la modale `AddTacheModal`

### Problème actuel

La modale de création de tâche (ouverte depuis Contact, Besoin, Mission) a un affichage différent de `AddBesoinActionModal` et `AddHistoriqueModal` :
- Champs dans un ordre différent
- Header sans fond midnight
- Bouton de validation sans style brutalist cohérent

### Fix — Aligner sur le pattern des modales Action

La modale `AddTacheModal` doit suivre ce template de structure :

```jsx
{/* Header modale */}
<div style={{
  background: '#1C1F35', color: '#fff',
  padding: '14px 20px',
  display: 'flex', justifyContent: 'space-between', alignItems: 'center',
}}>
  <span style={{ fontWeight: 800, fontSize: 13, textTransform: 'uppercase', letterSpacing: '0.05em' }}>
    <Icon d={ICONS.check} size={14} /> Nouvelle tâche
  </span>
  <button onClick={onClose} style={{ color: '#FFE500', fontSize: 18, lineHeight: 1, background: 'none', border: 'none', cursor: 'pointer' }}>✕</button>
</div>

{/* Corps */}
<div style={{ padding: '20px', display: 'flex', flexDirection: 'column', gap: 14 }}>
  {/* Champ Titre */}
  {/* Champ Deadline */}
  {/* Champ Assigné à */}
  {/* Champ Contexte (lien automatique vers le contact/besoin/mission source) */}
</div>

{/* Footer */}
<div style={{ padding: '14px 20px', borderTop: '2px solid #E4E4E6', display: 'flex', justifyContent: 'flex-end', gap: 8 }}>
  <BtnAction variant="task" label="✓ Créer la tâche" onClick={handleSave} disabled={saving} />
  <button onClick={onClose} style={{ fontSize: 11, color: '#999', background: 'none', border: 'none', cursor: 'pointer', textTransform: 'uppercase' }}>
    Annuler
  </button>
</div>
```

---

## 7. Récapitulatif des couleurs d'ombre par bouton

| Bouton | Fond | Shadow | Signification |
|---|---|---|---|
| `+ Action` | `#1C1F35` | `4px 4px 0 #FF3D2E` | Nouvelle entrée historique — urgence/rouge |
| `✓ Tâche` | `#1C1F35` | `4px 4px 0 #FFE500` | To-do — attention/jaune |
| `✏ Modifier` | `#1C1F35` | `4px 4px 0 #4A7FE5` | Édition — informationnel/bleu |
| `✕ Supprimer` | `#ffffff` | `4px 4px 0 #FF3D2E` | Destructif — fond blanc + contour rouge |
| `✓ Marquer fait` (tâche) | `#1C1F35` | `4px 4px 0 #00C218` | Validation — succès/vert |

---

## 8. Ce qu'il ne faut PAS faire

- ❌ `border-radius` autre que 0 sur aucun bouton ni modale
- ❌ Bouton poubelle icon-only sans texte — **toujours** `"Supprimer"` en toutes lettres
- ❌ Classes Tailwind `rounded`, `rounded-sm`, `rounded-lg` sur les boutons et confirmations
- ❌ Mélanger `border` shorthand et `borderLeft` dans le même objet de styles inline
- ❌ `transition-colors` Tailwind uniquement — utiliser `transition: 'all 80ms ease'` en inline

---

## 9. Critères QA

| # | Panel | Test | Attendu |
|---|---|---|---|
| 1 | Tous | Ordre des boutons | Action → Tâche → Modifier → Supprimer (ou Marquer fait pour TacheDetail) |
| 2 | Tous | Bouton Action | Fond midnight + ombre rouge décalée, label "+ Action" |
| 3 | Tous | Bouton Tâche | Fond midnight + ombre jaune décalée, label "✓ Tâche" |
| 4 | Tous | Bouton Modifier | Fond midnight + ombre bleue décalée, label "Modifier" |
| 5 | Tous | Bouton Supprimer | Fond blanc + contour coral + ombre coral, label "Supprimer" complet visible |
| 6 | Contact + Besoin | Confirmation suppression | Composant `ConfirmDelete` brutalist, pas de `rounded`, bouton "Oui, supprimer" en rouge |
| 7 | BesoinDetail | Toggle Modifier/Annuler | Modifier = shadow bleu, état édition = shadow jaune avec "✕ Annuler" |
| 8 | TacheDetail | Bouton Marquer fait | Fond midnight + ombre verte `#00C218` |
| 9 | Tous | Hover bouton | `transform: translate(-2px, -2px)` au survol |
| 10 | Modale Tâche | Header | Fond midnight, titre "Nouvelle tâche" en blanc, croix en jaune |
| 11 | Modale Tâche | Bouton valider | `BtnAction variant="task"` shadow jaune |
| 12 | Tous | border-radius | Zéro arrondi sur tous les boutons et confirmations |
| 13 | Deploy | — | `bash supabase/deploy_staging.sh` — jamais main |
