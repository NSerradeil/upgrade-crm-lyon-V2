# SPEC — Missions : terminer une mission depuis le CRM

**Fichier cible :** `supabase/CRM_Live.html`
**Composants touchés :** `MissionDetail`, auto-update statut au chargement
**Deploy :** `bash supabase/deploy_staging.sh` → **staging uniquement, jamais main**

---

## 1. Analyse de l'existant

| Élément | État actuel |
|---|---|
| `date_fin_mission` | Champ TIMESTAMPTZ sur `missions`, éditable via modal "Modifier" |
| Statut "Terminée" | Existe dans `MISSION_STATUTS`, se met uniquement manuellement via le modal complet |
| Auto-update au chargement | Code présent (lignes 4341-4347) : si `date_fin_mission < today` ET `statut != 'Terminée'` → UPDATE automatique |
| Cas Paul Hannecart | `date_fin_mission` passée mais statut non mis à jour → l'auto-update doit couvrir ce cas |

**Problème :** Pour clôturer une mission, l'utilisateur doit ouvrir le modal d'édition complet (20+ champs) juste pour changer une date et un statut. Il n'y a pas de raccourci "Terminer" dédié.

---

## 2. Décision produit

**Principe directeur :** une action = un bouton = une modale minimaliste. Terminer une mission ne doit prendre que 2 clics + 1 date.

**Ce qu'on NE fait PAS :**
- ❌ Workflow de clôture en plusieurs étapes
- ❌ Champs de bilan obligatoires
- ❌ Archivage vers une table séparée
- ❌ Notification ou email automatique

---

## 3. Bouton "Terminer" dans `MissionDetail`

### Ajout dans la barre de boutons

Le bouton "Terminer" s'ajoute dans le bloc `actions` de `MissionDetail`, **uniquement si la mission n'est pas déjà "Terminée"** :

```jsx
const actions = canEdit ? (
  <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
    <BtnAction variant="primary" icon={ICONS.add}    label="+ Action"   onClick={() => setShowAdd(true)} />
    <BtnAction variant="task"    icon={ICONS.check}  label="✓ Tâche"    onClick={() => setModal('tache')} />
    <BtnAction variant="edit"    icon={ICONS.edit}   label="Modifier"   onClick={() => setModal('edit')} />

    {/* Bouton Terminer — visible uniquement si mission pas encore terminée */}
    {mission.statut !== 'Terminée' && (
      <BtnAction
        variant="close"
        icon={ICONS.stop}       // icône carré stop (⏹) ou X
        label="Terminer"
        onClick={() => setModal('terminer')}
      />
    )}

    {/* Badge si déjà terminée */}
    {mission.statut === 'Terminée' && (
      <span style={{
        fontSize: 11, fontWeight: 700,
        background: '#E4E4E6', color: '#1C1F35',
        padding: '4px 10px', borderRadius: 0,
        textTransform: 'uppercase', letterSpacing: '0.05em',
      }}>
        ✓ Mission terminée
      </span>
    )}

    {modal !== 'confirmDel'
      ? <BtnAction variant="danger" icon={ICONS.delete} label="Supprimer" onClick={() => setModal('confirmDel')} />
      : <ConfirmDelete onConfirm={handleDelete} onCancel={() => setModal(null)} loading={deleting} />
    }
  </div>
) : null;
```

### Variant "close" à ajouter dans `BtnAction`

```js
// Dans l'objet VARIANTS de BtnAction
close: {
  background: '#1C1F35',
  color: '#E4E4E6',
  border: '2px solid #1C1F35',
  boxShadow: '4px 4px 0 #E4E4E6',  // ombre grise neutre — action finale, pas destructive
},
```

---

## 4. Modale `TerminerMissionModal`

Modale minimaliste — deux champs seulement : date de fin + confirmation.

```jsx
function TerminerMissionModal({ mission, onClose, onSaved }) {
  // Pré-remplir avec date_fin_mission existante ou aujourd'hui
  const defaultDate = mission.date_fin_mission
    ? mission.date_fin_mission.slice(0, 10)
    : new Date().toISOString().slice(0, 10);

  const [dateFin, setDateFin] = React.useState(defaultDate);
  const [saving, setSaving] = React.useState(false);

  async function handleTerminer() {
    setSaving(true);
    try {
      await sb.from('missions').update({
        date_fin_mission: new Date(dateFin).toISOString(),
        statut: 'Terminée',
      }).eq('id', mission.id);

      onSaved?.();
      onClose();
    } catch (e) {
      console.error(e);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div style={{ /* overlay */ position:'fixed', inset:0, background:'rgba(0,0,0,0.5)', display:'flex', alignItems:'center', justifyContent:'center', zIndex:9999 }}>
      <div style={{ background:'#fff', width:380, border:'2px solid #1C1F35', borderRadius:0 }}>

        {/* Header */}
        <div style={{ background:'#1C1F35', color:'#fff', padding:'14px 20px', display:'flex', justifyContent:'space-between', alignItems:'center' }}>
          <span style={{ fontWeight:800, fontSize:13, textTransform:'uppercase', letterSpacing:'0.05em' }}>
            ⏹ Terminer la mission
          </span>
          <button onClick={onClose} style={{ color:'#FFE500', fontSize:18, background:'none', border:'none', cursor:'pointer', lineHeight:1 }}>✕</button>
        </div>

        {/* Corps */}
        <div style={{ padding:'20px', display:'flex', flexDirection:'column', gap:16 }}>

          {/* Nom consultant */}
          <div style={{ fontSize:13, fontWeight:700, color:'#1C1F35' }}>
            {mission.consultant} — {mission.client}
          </div>

          {/* Date de fin */}
          <div style={{ display:'flex', flexDirection:'column', gap:6 }}>
            <label style={{ fontSize:11, fontWeight:700, textTransform:'uppercase', letterSpacing:'0.06em', color:'#999' }}>
              Date de fin effective
            </label>
            <input
              type="date"
              value={dateFin}
              onChange={e => setDateFin(e.target.value)}
              style={{
                padding:'8px 12px', fontSize:13,
                border:'2px solid #1C1F35', borderRadius:0,
                fontFamily:'Outfit, sans-serif', color:'#1C1F35',
              }}
            />
            <span style={{ fontSize:11, color:'#aaa' }}>
              Le statut passera automatiquement à "Terminée"
            </span>
          </div>

        </div>

        {/* Footer */}
        <div style={{ padding:'14px 20px', borderTop:'2px solid #E4E4E6', display:'flex', justifyContent:'flex-end', gap:8 }}>
          <BtnAction
            variant="close"
            label={saving ? '...' : '⏹ Terminer la mission'}
            onClick={handleTerminer}
            disabled={saving || !dateFin}
          />
          <button
            onClick={onClose}
            style={{ fontSize:11, color:'#999', background:'none', border:'none', cursor:'pointer', textTransform:'uppercase' }}
          >
            Annuler
          </button>
        </div>

      </div>
    </div>
  );
}
```

### Appel de la modale dans `MissionDetail`

```jsx
{modal === 'terminer' && (
  <TerminerMissionModal
    mission={mission}
    onClose={() => setModal(null)}
    onSaved={() => { setModal(null); onClose?.(); }}
  />
)}
```

---

## 5. Auto-update statut au chargement — vérification et correction

### Comportement attendu

À chaque chargement du tab Missions (ou TabTDB), si une mission a `date_fin_mission < maintenant` et `statut != 'Terminée'`, son statut doit passer automatiquement à "Terminée".

### Code à vérifier / corriger (lignes ~4341-4347)

Le code d'auto-update existe déjà. Vérifier qu'il est bien exécuté et qu'il couvre les deux champs (`date_fin_mission` ET `date_fin`) :

```js
// À appeler dans le useEffect de chargement des missions
async function autoUpdateStatutsMissions(missions) {
  const now = new Date();
  const toTerminate = missions.filter(m =>
    m.statut !== 'Terminée' &&
    m.date_fin_mission &&
    new Date(m.date_fin_mission) < now
  );

  if (toTerminate.length === 0) return;

  // Batch update
  for (const m of toTerminate) {
    await sb.from('missions')
      .update({ statut: 'Terminée' })
      .eq('id', m.id);
  }
}
```

> **Cas Paul Hannecart :** Si `date_fin_mission` est renseignée et passée, l'auto-update au prochain chargement corrigera le statut sans intervention manuelle.

---

## 6. Affichage dans `MissionDetail` quand statut = "Terminée"

Quand la mission est terminée, afficher la date de fin de manière proéminente dans le header du panel :

```jsx
{mission.statut === 'Terminée' && mission.date_fin_mission && (
  <div style={{
    background:'#F3F4F6', border:'2px solid #E4E4E6',
    padding:'6px 14px', marginBottom:12,
    fontSize:12, color:'#666', display:'flex', alignItems:'center', gap:8,
  }}>
    <span style={{ fontWeight:800, color:'#1C1F35', textTransform:'uppercase', fontSize:10, letterSpacing:'0.06em' }}>
      Terminée le
    </span>
    <span style={{ fontWeight:700, color:'#1C1F35' }}>
      {new Date(mission.date_fin_mission).toLocaleDateString('fr-FR', { day:'2-digit', month:'long', year:'numeric' })}
    </span>
  </div>
)}
```

---

## 7. Critères QA

| # | Test | Attendu |
|---|---|---|
| 1 | Mission "En cours" | Bouton "Terminer" visible dans la barre d'actions |
| 2 | Mission "Terminée" | Bouton "Terminer" absent, remplacé par badge "✓ Mission terminée" |
| 3 | Clic "Terminer" | Modale s'ouvre, date pré-remplie avec `date_fin_mission` existante ou aujourd'hui |
| 4 | Valider sans date | Bouton désactivé si champ date vide |
| 5 | Validation | `missions.statut = 'Terminée'` ET `date_fin_mission` mis à jour en base |
| 6 | Fermeture modale | Panel MissionDetail se ferme (ou se recharge) avec statut "Terminée" affiché |
| 7 | Auto-update au load | Missions avec `date_fin_mission` passée et statut ≠ "Terminée" passent automatiquement à "Terminée" |
| 8 | Paul Hannecart | Après premier chargement, statut corrigé à "Terminée" automatiquement |
| 9 | Affichage date fin | Dans MissionDetail, la date de fin est affichée en bandeau si statut = "Terminée" |
| 10 | border-radius | Modale et boutons à `borderRadius: 0` |
| 11 | Deploy | `bash supabase/deploy_staging.sh` — jamais main |
