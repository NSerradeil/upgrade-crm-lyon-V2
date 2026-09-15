# SPEC — Flag "Ne pas recontacter" sur fiche contact
**CRM Upgrade Lyon V2** · Évolution modèle de données + UI
**Source :** Retour Anne-Claire Decker (commerciale Bordeaux) · 25/03/2026
**Auteur :** Nicolas Serradeil + Claude (PM + Lead UX)

---

## Besoin exprimé

> « Lorsqu'un prospect signifie explicitement qu'il ne souhaite pas être contacté, ajouter un pictogramme rouge avec la mention "Attention" visible directement sur sa fiche contact, afin d'alerter les membres de l'équipe avant tout nouveau contact. »

---

## Analyse

### Cas d'usage

Un contact dit explicitement lors d'un appel : *"Ne m'appelez plus, je ne suis pas intéressé et ne souhaitez pas être recontacté."* ou demande la suppression de ses données (droit RGPD).

Sans flag visible, un autre commercial (ou Anne-Claire elle-même plus tard) pourrait inclure ce contact dans une prochaine session et l'appeler à nouveau — mauvaise expérience pour le contact, risque RGPD.

### Ce que ça n'est pas

Ce n'est pas le statut "Pas intéressant" d'une session (status `not_interested`) — ce dernier est temporaire et lié à une session spécifique. Le flag "Ne pas recontacter" est **permanent** sur la fiche contact et s'applique à tous les canaux.

---

## Modèle de données

### Nouveau champ sur la table `contacts`

```sql
ALTER TABLE contacts ADD COLUMN ne_pas_recontacter BOOLEAN DEFAULT false;
ALTER TABLE contacts ADD COLUMN ne_pas_recontacter_note TEXT;
ALTER TABLE contacts ADD COLUMN ne_pas_recontacter_date DATE;
```

| Champ | Type | Description |
|---|---|---|
| `ne_pas_recontacter` | boolean | Flag principal — true = ne pas recontacter |
| `ne_pas_recontacter_note` | text | Raison/contexte (optionnel) |
| `ne_pas_recontacter_date` | date | Date à laquelle le flag a été posé |

---

## UI — Fiche contact

### 1. Badge sur la card contact (liste)

Dans la liste des contacts (TabProspects), sur la carte du contact :

```jsx
{contact.ne_pas_recontacter && (
  <span style={{
    fontSize: 9, fontWeight: 700, padding: '2px 8px', borderRadius: 0,
    background: '#FF3D2E', color: '#fff', textTransform: 'uppercase',
    letterSpacing: '0.04em', display: 'inline-flex', alignItems: 'center', gap: 4
  }}>
    <Icon d={ICONS.warning} size={10}/> Ne pas recontacter
  </span>
)}
```

### 2. Bannière dans la fiche contact (détail)

En haut du panneau de détail contact (`renderContactDetail` ou équivalent), **avant toute autre information** :

```jsx
{contact.ne_pas_recontacter && (
  <div style={{
    background: '#FF3D2E', color: '#fff', padding: '10px 16px',
    fontWeight: 700, fontSize: 12, display: 'flex', alignItems: 'center',
    gap: 8, borderBottom: '3px solid #C43022', marginBottom: 16
  }}>
    <Icon d={ICONS.warning} size={16}/>
    <div>
      <div>⛔ NE PAS RECONTACTER</div>
      {contact.ne_pas_recontacter_note && (
        <div style={{fontWeight: 400, fontSize: 11, marginTop: 2}}>
          {contact.ne_pas_recontacter_note}
        </div>
      )}
      {contact.ne_pas_recontacter_date && (
        <div style={{fontWeight: 400, fontSize: 10, opacity: 0.8}}>
          Posé le {fmtDate(contact.ne_pas_recontacter_date)}
        </div>
      )}
    </div>
    {isOwner && (
      <button onClick={handleLeverFlag} style={{marginLeft:'auto',fontSize:10,background:'rgba(255,255,255,0.2)',border:'1px solid rgba(255,255,255,0.4)',color:'#fff',padding:'4px 8px',cursor:'pointer',borderRadius:0}}>
        Lever le flag
      </button>
    )}
  </div>
)}
```

### 3. Bouton "Poser le flag" dans le formulaire d'édition contact

Dans `renderModifierContact()`, zone danger/actions supplémentaires :

```jsx
<div style={{borderTop:'2px solid #E4E4E6',paddingTop:16,marginTop:16}}>
  <label style={{fontSize:11,fontWeight:700,color:'#FF3D2E',textTransform:'uppercase',letterSpacing:'0.04em'}}>
    ⚠️ Ne pas recontacter
  </label>
  <div style={{display:'flex',gap:8,marginTop:8,alignItems:'flex-start'}}>
    <input
      type="checkbox"
      checked={f.ne_pas_recontacter||false}
      onChange={e => setF({...f, ne_pas_recontacter: e.target.checked, ne_pas_recontacter_date: e.target.checked ? getToday() : null})}
    />
    <div style={{flex:1}}>
      <div style={{fontSize:12,color:'#1C1F35',fontWeight:600}}>Ce contact ne souhaite plus être contacté</div>
      {f.ne_pas_recontacter && (
        <textarea
          rows={2}
          placeholder="Raison / contexte (optionnel)"
          value={f.ne_pas_recontacter_note||''}
          onChange={e => setF({...f, ne_pas_recontacter_note: e.target.value})}
          style={{marginTop:6,width:'100%',fontSize:12,padding:'6px 10px',border:'1px solid #E4E4E6',borderRadius:0,resize:'none'}}
        />
      )}
    </div>
  </div>
</div>
```

### 4. Alerte dans ProspectionNew (sélection de contacts)

Quand un contact avec `ne_pas_recontacter: true` est coché dans la liste de sélection :

```jsx
{contact.ne_pas_recontacter && (
  <span title="Ce contact a demandé à ne plus être contacté" style={{color:'#FF3D2E',fontWeight:700,fontSize:10}}>
    ⛔
  </span>
)}
```

Option plus forte : **bloquer la sélection** de ce contact avec une info-bulle et empêcher l'ajout à la session.

**Recommandation V1 :** avertissement visuel (emoji ⛔) sans blocage total — le commercial décide. Blocage automatique en V2 si retour terrain.

### 5. Alerte dans ProspectionActive (si contact ajouté avant le flag)

Si un contact `ne_pas_recontacter: true` se retrouve dans une session active (ajouté avant que le flag soit posé), afficher une bannière rouge sur sa carte dans la session :

```
⛔ Ce contact a demandé à ne plus être contacté — traitez en "Pas intéressant"
```

---

## Logs historique

Quand le flag est posé ou levé, log automatique dans `historique_actions` :

```js
// Poser le flag
await sb.from('historique_actions').insert({
  id_prospect: contact.id,
  date: getToday(),
  type_action: 'Flag NPC',
  details: `Flag "Ne pas recontacter" posé par ${profile.nom}${note ? ` — ${note}` : ''}`,
  responsable: profile.nom,
});

// Lever le flag
await sb.from('historique_actions').insert({
  id_prospect: contact.id,
  date: getToday(),
  type_action: 'Flag NPC levé',
  details: `Flag "Ne pas recontacter" levé par ${profile.nom}`,
  responsable: profile.nom,
});
```

---

## Permissions

| Action | Commercial (responsable) | Commercial (autre agence) | Admin |
|---|---|---|---|
| Voir le flag | ✅ | ✅ (si visible) | ✅ |
| Poser le flag | ✅ | ✅ | ✅ |
| Lever le flag | ✅ (si responsable du contact) | ❌ | ✅ |

> Lever un flag NPC est une action sensible (risque RGPD) — réservée au responsable du contact ou à un admin.

---

## Acceptance criteria

- [ ] Nouveau champ `ne_pas_recontacter` (boolean) sur la table Supabase `contacts`
- [ ] Badge rouge "Ne pas recontacter" visible sur la carte contact dans la liste
- [ ] Bannière rouge en tête de fiche contact si flag actif, avec note et date
- [ ] Case à cocher + textarea note dans le formulaire d'édition contact
- [ ] Poser le flag → log `historique_actions` avec `type_action: 'Flag NPC'`
- [ ] Lever le flag → log `historique_actions` avec `type_action: 'Flag NPC levé'`
- [ ] Icône ⛔ sur le contact dans `ProspectionNew` si flag actif
- [ ] Alerte dans `ProspectionActive` si un contact flaggé est dans la session
- [ ] Lever le flag : réservé au responsable du contact ou admin

---

## Ordre d'implémentation recommandé

1. **Supabase** : `ALTER TABLE contacts ADD COLUMN ne_pas_recontacter BOOLEAN DEFAULT false`
2. **Fiche contact** : bannière + badge (lecture)
3. **Formulaire Modifier** : case à cocher + note
4. **Logs** : historique_actions au changement de flag
5. **Prospection** : icône ⛔ dans ProspectionNew + alerte dans ProspectionActive
