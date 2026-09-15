# BUG — Affichage flag NPC dans la liste contacts
**CRM Upgrade Lyon V2**
**Date :** 28/03/2026

---

## Problème

Le flag `NPC` s'affiche comme un badge rouge indépendant sur une 2ème ligne sous le badge statut. Ça casse l'alignement de la ligne et rend la colonne STATUT illisible.

**Situation actuelle (screenshot) :**
```
| PROSPECT △ |
| NPC        |   ← badge rouge en dessous, 2ème ligne, trop grand
```

---

## Fix attendu

### Principe

Le flag NPC ne doit **pas** créer de 2ème ligne. Il doit s'intégrer **inline** avec le badge statut, sous forme d'un **petit pill discret** à droite du badge, sur la même ligne.

### Rendu cible

```
| PROSPECT  △  NPC |
  ↑ badge statut    ↑ petit pill inline, même ligne
```

### Spécifications visuelles du pill NPC

```css
/* Pill NPC inline */
display: inline-flex;
align-items: center;
padding: 1px 5px;
border-radius: 3px;
font-size: 9px;
font-weight: 700;
letter-spacing: 0.05em;
background-color: #FEE2E2;   /* rouge très pâle */
color: #DC2626;               /* rouge texte */
border: 1px solid #FECACA;
margin-left: 4px;
vertical-align: middle;
line-height: 1;
```

→ Petit, pas agressif, clairement lisible, ne déborde pas.

### Structure HTML cible dans la cellule STATUT

```jsx
<td className="statut-cell">
  <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexWrap: 'nowrap' }}>
    {/* Badge statut principal */}
    <span className={`badge badge-${statut.toLowerCase()}`}>{statut}</span>

    {/* Icône alerte si besoin */}
    {hasAlert && <span className="alert-icon">△</span>}

    {/* Flag NPC — inline, jamais sur une 2ème ligne */}
    {contact.npc && (
      <span style={{
        display: 'inline-flex',
        alignItems: 'center',
        padding: '1px 5px',
        borderRadius: 3,
        fontSize: 9,
        fontWeight: 700,
        letterSpacing: '0.05em',
        backgroundColor: '#FEE2E2',
        color: '#DC2626',
        border: '1px solid #FECACA',
        lineHeight: 1,
        whiteSpace: 'nowrap',
      }}>
        NPC
      </span>
    )}
  </div>
</td>
```

### Ce qui change

| Avant | Après |
|---|---|
| Badge NPC rouge plein sur 2ème ligne | Pill NPC petit, inline sur même ligne |
| `display: block` ou `flex-wrap: wrap` | `flexWrap: 'nowrap'`, tout sur une ligne |
| Taille identique au badge statut | Font 9px, padding minimal |
| Rouge agressif `#DC2626` fond | Fond `#FEE2E2` (rouge pâle), texte `#DC2626` |

---

## Acceptance criteria

- [ ] La colonne STATUT reste sur **une seule ligne** même quand NPC est présent
- [ ] Le pill NPC est visible mais discret (fond pâle, texte rouge, petite taille)
- [ ] L'icône alerte `△` reste présente si applicable, toujours inline
- [ ] Pas de wrapping sur les résolutions normales (1280px+)
- [ ] Le pill NPC n'apparaît pas si `contact.npc === false` (ou null/undefined)
