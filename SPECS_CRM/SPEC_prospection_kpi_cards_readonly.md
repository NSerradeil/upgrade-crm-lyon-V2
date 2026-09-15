# SPEC — KPI Cards Prospection (Intéressés · Relances · Injoignables) — Read-only

**Fichier cible :** `supabase/CRM_Live.html`
**Cards concernées :** `CardInteresses`, `CardRelances`, `CardInjoignables`
**Deploy :** `bash supabase/deploy_staging.sh` → **staging uniquement, jamais main**

> **Instructions Claude Code :** utiliser les patterns "Simplifier Superpowers" et "Frontend UI Skill". Réutiliser les composants existants `SidePanel`, `CardHeader`, `VoirToutFooter`, `VoirToutPanel`.

---

## Principe directeur

**Les cards KPI sont des surfaces analytiques, pas des surfaces d'action.**

Les boutons inline (Créer besoin, Marquer fait, Prochaine session, Ignorer) sont **supprimés**. Les actions se font dans les panneaux CRM existants — `ContactDetail`, `TacheDetailPanel` — qui ont déjà tout le contexte nécessaire.

Chaque ligne est un **lien de navigation** : clic → ouvre le panneau CRM de l'objet concerné. L'état local simplifié (fini les Sets `created/ignored/done`) allège les composants.

---

## Changements transversaux

| Avant | Après |
|---|---|
| Boutons inline dans les rows | Aucun bouton. Flèche `›` en fin de ligne. |
| `onClick` → action Supabase | `onClick` → `setDetailContact(c)` ou `setDetailTache(t)` |
| Hover neutre | Hover → fond légèrement teinté (couleur de la card) |
| States `created`, `ignored`, `done` | Supprimés |
| Prop drilling actions | Props réduits à `onOpen(id)` |

---

## 1. Card Intéressés

### Données source

```js
// Contacts statut 'interested' issus de session_prospection_contacts
const { data } = await sb
  .from('session_prospection_contacts')
  .select(`
    contact_id,
    notes,
    created_at,
    session_id,
    sessions_prospection ( nom, date_session ),
    contacts ( prenom, nom, groupe, poste )
  `)
  .eq('statut', 'interested')
  .order('created_at', { ascending: false });
```

### Composant `InterRow`

```jsx
function InterRow({ row, onOpen }) {
  const [hov, setHov] = useState(false);
  const c = row.contacts;
  return (
    <div
      onClick={() => onOpen(row.contact_id)}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        padding: '12px 18px',
        borderBottom: `1px solid ${C.border}`,
        display: 'flex', gap: 12, alignItems: 'flex-start',
        cursor: 'pointer',
        background: hov ? '#f5faf5' : C.snow,
        transition: 'background 80ms',
      }}
    >
      <div style={{ width: 3, background: C.green, alignSelf: 'stretch', flexShrink: 0 }} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', gap: 8, flexWrap: 'wrap' }}>
          <div>
            <div style={{ fontWeight: 800, fontSize: 13 }}>{c.prenom} {c.nom}</div>
            <div style={{ fontSize: 11, color: C.blue, fontWeight: 700 }}>{c.groupe} · {c.poste}</div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
            <div style={{ fontSize: 10, color: '#bbb', textAlign: 'right' }}>
              <div>{row.sessions_prospection?.nom}</div>
              <div>{new Date(row.created_at).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short' })}</div>
            </div>
            <span style={{ fontSize: 14, color: '#ccc' }}>›</span>
          </div>
        </div>
        {row.notes && (
          <div style={{ fontSize: 11, color: '#888', marginTop: 5, fontStyle: 'italic', borderLeft: `2px solid ${C.green}`, paddingLeft: 8, lineHeight: 1.5 }}>
            {row.notes}
          </div>
        )}
      </div>
    </div>
  );
}
```

### Composant `CardInteresses`

```jsx
function CardInteresses({ rows, onOpen }) {
  const [panel, setPanel] = useState(false);
  const shown = rows.slice(0, PREVIEW_N);
  return (
    <>
      <CardHeader
        color={C.green}
        title="Intéressés"
        count={`${rows.length} contact${rows.length > 1 ? 's' : ''}`}
        hint="· ouvrir le contact pour créer un besoin"
        totalItems={rows.length}
        onVoirTout={() => setPanel(true)}
      />
      {shown.map(r => <InterRow key={r.contact_id} row={r} onOpen={onOpen} />)}
      {rows.length === 0 && <EmptyState msg="Aucun contact intéressé pour l'instant." />}
      <VoirToutFooter shown={shown.length} total={rows.length} color={C.green} onVoirTout={() => setPanel(true)} />
      {panel && (
        <VoirToutPanel title="Tous les intéressés" color={C.green} onClose={() => setPanel(false)}>
          {rows.map(r => <InterRow key={r.contact_id} row={r} onOpen={id => { setPanel(false); onOpen(id); }} />)}
        </VoirToutPanel>
      )}
    </>
  );
}
```

**`onOpen(contact_id)`** → appelle `setDetailContact(contact_id)` dans le parent → ouvre `ContactDetail` via `SidePanel`. C'est dans `ContactDetail` que l'utilisateur crée un besoin, comme d'habitude.

---

## 2. Card Relances

### Données source

```js
// Tâches de relance liées à une session de prospection, non complétées
const { data } = await sb
  .from('taches')
  .select(`
    *,
    contacts ( prenom, nom, groupe )
  `)
  .not('session_prospection_id', 'is', null)
  .eq('statut', 'a_faire')
  .order('due_date', { ascending: true });
```

### Tri des lignes

Tri urgence-first, identique à l'existant :
```js
const sorted = [...rows].sort((a, b) => {
  const score = r => {
    const today = new Date().toDateString();
    if (new Date(r.due_date) < new Date() && r.due_date.split('T')[0] !== today) return 2; // retard
    if (new Date(r.due_date).toDateString() === today) return 1; // aujourd'hui
    return 0;
  };
  return score(b) - score(a);
});
```

### Composant `RelanceRow`

```jsx
function RelanceRow({ r, onOpen }) {
  const [hov, setHov] = useState(false);
  const today   = new Date().toDateString();
  const dueDate = new Date(r.due_date);
  const isRetard    = dueDate < new Date() && dueDate.toDateString() !== today;
  const isAujourdhui = dueDate.toDateString() === today;

  const urgColor = isRetard ? C.red : isAujourdhui ? C.yellow : '#aaa';
  const urgLabel = isRetard ? 'En retard' : isAujourdhui ? "Aujourd'hui"
    : dueDate.toLocaleDateString('fr-FR', { day: '2-digit', month: 'short' });
  const urgBg = isRetard ? '#FFF5F5' : isAujourdhui ? '#FFFBF0' : C.snow;
  const urgBgHov = isRetard ? '#ffe8e8' : isAujourdhui ? '#fff5d6' : '#f9f9f9';

  return (
    <div
      onClick={() => onOpen(r.id)}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        padding: '12px 18px',
        borderBottom: `1px solid ${C.border}`,
        display: 'flex', gap: 10, alignItems: 'center',
        cursor: 'pointer',
        background: hov ? urgBgHov : urgBg,
        transition: 'background 80ms',
      }}
    >
      <div style={{ width: 3, background: urgColor, alignSelf: 'stretch', flexShrink: 0 }} />
      {/* Badge urgence */}
      <div style={{ flexShrink: 0, minWidth: 64 }}>
        <div style={{ fontSize: 9, fontWeight: 900, textTransform: 'uppercase', color: urgColor, letterSpacing: '0.05em' }}>
          {urgLabel}
        </div>
        {isRetard && <div style={{ fontSize: 8, color: C.red, fontWeight: 800, marginTop: 1 }}>⚠ RETARD</div>}
      </div>
      {/* Contenu */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 800, fontSize: 13 }}>
          {r.contacts?.prenom} {r.contacts?.nom}
          <span style={{ fontWeight: 400, color: '#999' }}> — {r.contacts?.groupe}</span>
        </div>
        {r.description && (
          <div style={{ fontSize: 11, color: '#888', marginTop: 2 }}>{r.description}</div>
        )}
      </div>
      <span style={{ fontSize: 14, color: '#ccc', flexShrink: 0 }}>›</span>
    </div>
  );
}
```

### Composant `CardRelances`

```jsx
function CardRelances({ rows, onOpen }) {
  const [panel, setPanel] = useState(false);
  const sorted  = sortByUrgence(rows); // voir tri ci-dessus
  const shown   = sorted.slice(0, PREVIEW_N);
  const nRetard = rows.filter(r => isRetard(r)).length;

  return (
    <>
      <CardHeader
        color={C.yellow}
        title="Relances"
        count={`${rows.length} à faire`}
        hint={nRetard > 0 ? `· ${nRetard} en retard` : '· ouvrir la tâche pour la compléter'}
        totalItems={sorted.length}
        onVoirTout={() => setPanel(true)}
      />
      {shown.map(r => <RelanceRow key={r.id} r={r} onOpen={onOpen} />)}
      {rows.length === 0 && <EmptyState msg="Aucune relance en attente." />}
      <VoirToutFooter shown={shown.length} total={sorted.length} color={C.yellow} onVoirTout={() => setPanel(true)} />
      {panel && (
        <VoirToutPanel title="Toutes les relances" color={C.yellow} onClose={() => setPanel(false)}>
          {sorted.map(r => <RelanceRow key={r.id} r={r} onOpen={id => { setPanel(false); onOpen(id); }} />)}
        </VoirToutPanel>
      )}
    </>
  );
}
```

**`onOpen(tache_id)`** → appelle `setDetailTache(tache_id)` dans le parent → ouvre `TacheDetailPanel` via `SidePanel`. C'est dans `TacheDetailPanel` que l'utilisateur marque la tâche comme faite, comme d'habitude.

---

## 3. Card Injoignables

### Données source

```js
// Contacts unreachable depuis des sessions, groupés par contact (dernier essai en tête)
const { data } = await sb
  .from('session_prospection_contacts')
  .select(`
    contact_id,
    created_at,
    session_id,
    sessions_prospection ( nom ),
    contacts ( prenom, nom, groupe )
  `)
  .eq('statut', 'unreachable')
  .order('created_at', { ascending: false });

// Dédoublonner par contact_id, conserver le plus récent + compter les tentatives
const byContact = {};
data.forEach(row => {
  if (!byContact[row.contact_id]) {
    byContact[row.contact_id] = { ...row, nb: 0 };
  }
  byContact[row.contact_id].nb += 1;
});
const injoignables = Object.values(byContact);
```

### Composant `InjRow`

```jsx
function InjRow({ row, onOpen }) {
  const [hov, setHov] = useState(false);
  const c = row.contacts;
  // Couleur badge nb tentatives : rouge ≥ 3, jaune = 2, gris = 1
  const nbColor = row.nb >= 3 ? C.red : row.nb === 2 ? C.yellow : '#bbb';

  return (
    <div
      onClick={() => onOpen(row.contact_id)}
      onMouseEnter={() => setHov(true)}
      onMouseLeave={() => setHov(false)}
      style={{
        padding: '12px 18px',
        borderBottom: `1px solid ${C.border}`,
        display: 'flex', gap: 10, alignItems: 'center',
        cursor: 'pointer',
        background: hov ? '#f9f9f9' : C.snow,
        transition: 'background 80ms',
      }}
    >
      <div style={{ width: 3, background: '#ccc', alignSelf: 'stretch', flexShrink: 0 }} />
      {/* Badge nb tentatives */}
      <div style={{ flexShrink: 0, textAlign: 'center', minWidth: 28 }}>
        <div style={{ fontSize: 16, fontWeight: 900, color: nbColor, lineHeight: 1 }}>{row.nb}</div>
        <div style={{ fontSize: 8, fontWeight: 700, textTransform: 'uppercase', color: '#ccc', letterSpacing: '0.04em' }}>
          essai{row.nb > 1 ? 's' : ''}
        </div>
      </div>
      {/* Contenu */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 800, fontSize: 13 }}>
          {c.prenom} {c.nom}
          <span style={{ fontWeight: 400, color: '#999' }}> — {c.groupe}</span>
        </div>
        <div style={{ fontSize: 10, color: '#bbb', marginTop: 2 }}>
          Dernier essai : {new Date(row.created_at).toLocaleDateString('fr-FR', { day: '2-digit', month: 'short' })}
          {' · '}{row.sessions_prospection?.nom}
        </div>
      </div>
      <span style={{ fontSize: 14, color: '#ccc', flexShrink: 0 }}>›</span>
    </div>
  );
}
```

### Composant `CardInjoignables`

```jsx
function CardInjoignables({ rows, onOpen }) {
  const [panel, setPanel] = useState(false);
  const shown = rows.slice(0, PREVIEW_N);
  return (
    <>
      <CardHeader
        color="#999"
        title="Injoignables"
        count={`${rows.length} contact${rows.length > 1 ? 's' : ''}`}
        hint="· ouvrir le contact pour le rappeler"
        totalItems={rows.length}
        onVoirTout={() => setPanel(true)}
      />
      {shown.map(r => <InjRow key={r.contact_id} row={r} onOpen={onOpen} />)}
      {rows.length === 0 && <EmptyState msg="Aucun injoignable pour l'instant." />}
      <VoirToutFooter shown={shown.length} total={rows.length} color="#999" onVoirTout={() => setPanel(true)} />
      {panel && (
        <VoirToutPanel title="Tous les injoignables" color="#999" onClose={() => setPanel(false)}>
          {rows.map(r => <InjRow key={r.contact_id} row={r} onOpen={id => { setPanel(false); onOpen(id); }} />)}
        </VoirToutPanel>
      )}
    </>
  );
}
```

**`onOpen(contact_id)`** → appelle `setDetailContact(contact_id)` dans le parent → ouvre `ContactDetail` via `SidePanel`. La gestion "prochaine session" se fait au moment de créer la session (filtre sur les contacts récemment injoignables dans `NewSession`), pas depuis cette card.

---

## 4. Composant `EmptyState` (utilitaire partagé)

```jsx
function EmptyState({ msg }) {
  return (
    <div style={{ padding: '24px 18px', textAlign: 'center', fontSize: 12, color: '#bbb', fontWeight: 700 }}>
      {msg}
    </div>
  );
}
```

---

## 5. Intégration dans `SessionList`

Les 3 cards reçoivent leurs données depuis le parent. Les handlers `onOpen` déclenchent les panneaux CRM existants.

```jsx
function SessionList({ ..., setDetailContact, setDetailTache }) {
  // ...
  return (
    <>
      {/* KPI cards */}
      {activeKpi === 'interesses'   && <CardInteresses  rows={kpiRows} onOpen={setDetailContact} />}
      {activeKpi === 'relances'     && <CardRelances     rows={kpiRows} onOpen={setDetailTache}   />}
      {activeKpi === 'injoignables' && <CardInjoignables rows={kpiRows} onOpen={setDetailContact} />}
      {activeKpi === 'sessions'     && <CardSessions />}
    </>
  );
}
```

`setDetailContact` et `setDetailTache` sont les setters déjà existants dans le CRM — les mêmes qui pilotent les `SidePanel` sur les autres onglets.

---

## 6. Ce qui disparaît

- Toute la logique de dismiss/ignore (`ignored` Set) — supprimée
- Bouton "Créer besoin" — action dans `ContactDetail`
- Bouton "Marquer fait" — action dans `TacheDetailPanel`
- Bouton "Prochaine session" — pré-sélection à la création de session dans `NewSession`
- Bouton "Ignorer" — inutile sans les autres actions
