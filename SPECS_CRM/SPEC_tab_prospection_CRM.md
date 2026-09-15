# SPEC — Tab Prospection intégré dans le CRM Upgrade

**Fichier cible :** `supabase/CRM_Live.html`
**Migrations SQL :** `supabase/migrations/YYYYMMDD_prospection.sql`
**Position dans la nav :** entre `prospects` (Contacts) et `besoins`
**Deploy :** `bash supabase/deploy_staging.sh` → **staging uniquement, jamais main**

> **Instructions Claude Code :** utiliser les patterns "Simplifier Superpowers" et "Frontend UI Skill" pour produire des composants propres, à la charte DA Upgrade, en réutilisant les composants existants (`SidePanel`, `BtnAction`, `ConfirmDelete`, `StatutBadge`, etc.).

---

## 1. Vue d'ensemble — ce que fait le tab Prospection

Le tab Prospection est une **interface de gestion de sessions d'appels sortants** intégrée nativement au CRM. Il remplace le workflow actuel copier-coller (artefact React externe → Claude → MCP).

### Flux complet

```
Tab Prospection
  └─ Liste des sessions passées (+ KPI cards cliquables)
       ├─ Clic sur une session → SidePanel détail droit (pattern identique aux autres onglets)
       └─ "+ Nouvelle session"
            ├─ Étape 1 : nom + filtres (agence, délai dernier contact)
            ├─ Étape 2 : sélection des contacts depuis la base CRM
            └─ Étape 3 : Session active
                 ├─ Vue liste / Vue un par un
                 ├─ Cartes contact : statut appel + notes + relance
                 └─ "Terminer la session"
                      ├─ UPDATE contacts (tél, email, LinkedIn si saisis)
                      ├─ INSERT historique_actions (1 par contact appelé)
                      ├─ INSERT taches (relances, liées au contact + session)
                      ├─ INSERT/UPDATE session_prospection_contacts
                      ├─ UPDATE sessions_prospection (statut='done', stats)
                      └─ Retour liste avec nouvelle session en tête
```

---

## 2. Migrations SQL

### Fichier : `supabase/migrations/YYYYMMDD_prospection.sql`

```sql
-- ── Table sessions_prospection ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sessions_prospection (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom             TEXT NOT NULL,
  date_session    DATE NOT NULL DEFAULT CURRENT_DATE,
  responsable     TEXT NOT NULL,
  agence          TEXT,
  statut          TEXT DEFAULT 'active' CHECK (statut IN ('active','done')),
  nb_contacts     INTEGER DEFAULT 0,
  nb_interesses   INTEGER DEFAULT 0,
  nb_relances     INTEGER DEFAULT 0,
  nb_injoignables INTEGER DEFAULT 0,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

-- ── Table session_prospection_contacts ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS session_prospection_contacts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id      UUID REFERENCES sessions_prospection(id) ON DELETE CASCADE,
  contact_id      INTEGER REFERENCES contacts(id),
  statut          TEXT DEFAULT 'none'
                  CHECK (statut IN ('none','called','interested','unreachable','not_interested')),
  notes           TEXT,
  want_relance    BOOLEAN DEFAULT false,
  relance_date    DATE,
  relance_note    TEXT,
  tel_saisi       TEXT,    -- coordonnée saisie pendant la session (si manquante sur le contact)
  email_saisi     TEXT,
  linkedin_saisi  TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- ── Ajout colonne session_prospection_id dans taches ────────────────────────
ALTER TABLE taches
  ADD COLUMN IF NOT EXISTS session_prospection_id UUID
  REFERENCES sessions_prospection(id) ON DELETE SET NULL;

-- ── Index de performance ─────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_spc_session ON session_prospection_contacts(session_id);
CREATE INDEX IF NOT EXISTS idx_spc_contact ON session_prospection_contacts(contact_id);
CREATE INDEX IF NOT EXISTS idx_taches_session ON taches(session_prospection_id);
```

---

## 3. Ajout du tab dans la navigation

### Dans le tableau `TABS` — insérer entre `prospects` et `besoins`

```js
// Calculer le compteur : sessions actives ou total
const sessionsActives = sessions.filter(s => s.statut === 'active');

// Dans TABS[], après 'prospects' et avant 'besoins' :
{ id:'prospection', label: <>
  <Icon d={ICONS.phone} size={14}/> Prosp.&nbsp;({sessions.length})
  {sessionsActives.length > 0 && (
    <span style={{ width:6, height:6, background:C.yellow, display:'inline-block', marginLeft:4, verticalAlign:'middle' }}/>
  )}
</> }
```

### Dans TAB_COLORS

```js
TAB_COLORS['prospection'] = '#FFE500';  // Jaune — même logique que badge ATTENTION
```

### Dans le rendu conditionnel des onglets

```jsx
{tab === 'prospection' && (
  <TabProspection
    profile={profile}
    contacts={contacts}           // tous les contacts CRM (pour la sélection)
    contactMap={contactMap}       // map id→contact
    onRefresh={onRefresh}
    isAdmin={isAdmin}
  />
)}
```

---

## 4. Composant `TabProspection`

### State

```js
const [sessions, setSessions]           = useState([]);
const [loading, setLoading]             = useState(true);
const [screen, setScreen]               = useState('list');   // 'list' | 'new' | 'active'
const [activeSession, setActiveSession] = useState(null);     // session en cours de création/editing
const [detailSession, setDetailSession] = useState(null);     // session ouverte dans SidePanel
const [activeKpi, setActiveKpi]         = useState(null);     // KPI card cliquée (voir §9)
const [kpiContacts, setKpiContacts]     = useState([]);       // contacts du KPI affiché
```

### Chargement des sessions

```js
async function loadSessions() {
  setLoading(true);
  const { data } = await sb
    .from('sessions_prospection')
    .select('*')
    .eq('responsable', profile.nom)   // ou isAdmin : sans filtre
    .order('created_at', { ascending: false });
  setSessions(data || []);
  setLoading(false);
}

useEffect(() => { loadSessions(); }, []);
```

### Rendu principal

```jsx
return (
  <div style={{ padding: '0 0 40px' }}>
    {screen === 'list'   && <SessionList   sessions={sessions} onNew={() => setScreen('new')} onDetail={setDetailSession} loading={loading} activeKpi={activeKpi} setActiveKpi={setActiveKpi} kpiContacts={kpiContacts} setKpiContacts={setKpiContacts} />}
    {screen === 'new'    && <NewSession    contacts={contacts} profile={profile} onStart={s => { setActiveSession(s); setScreen('active'); }} onBack={() => setScreen('list')} />}
    {screen === 'active' && <SessionActive session={activeSession} contactMap={contactMap} profile={profile} onDone={() => { setScreen('list'); loadSessions(); }} onBack={() => setScreen('list')} />}

    {/* SidePanel détail session (identique aux autres onglets) */}
    {detailSession && (
      <SessionDetailPanel
        session={detailSession}
        contactMap={contactMap}
        onClose={() => setDetailSession(null)}
      />
    )}
  </div>
);
```

---

## 5. Écran `SessionList` — liste + KPI cards

### KPI cards cliquables (voir §9 pour le comportement détail)

```jsx
const KPI_DEFS = [
  { id:'total',       label:'Sessions',          getValue: ss => ss.length,                              color: C.midnight },
  { id:'interesses',  label:'Intéressés (total)', getValue: ss => ss.reduce((a,s)=>a+s.nb_interesses,0), color: C.green    },
  { id:'relances',    label:'Relances créées',    getValue: ss => ss.reduce((a,s)=>a+s.nb_relances,0),   color: C.yellow   },
  { id:'injoignables',label:'Injoignables',       getValue: ss => ss.reduce((a,s)=>a+s.nb_injoignables,0), color: '#999'  },
];
```

Chaque card :
- Inactif : fond blanc, liseré gauche coloré, bordures grises (même pattern que TDB)
- Actif (clic) : fond midnight, shadow offset couleur KPI, valeur en blanc
- Au clic → charge les contacts correspondants et les affiche dans le bloc détail KPI (§9)

### Liste des sessions

```jsx
// Table "brutalist" avec header midnight
<div style={{ background: C.snow, border: `2px solid ${C.midnight}` }}>
  <div style={{ background: C.midnight, padding: '10px 18px', display: 'flex', justifyContent: 'space-between' }}>
    <span style={{ color: C.snow, fontWeight: 800, fontSize: 12, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
      Historique des sessions
    </span>
    <BtnAction variant="primary" icon={ICONS.add} label="+ Nouvelle session" onClick={onNew} />
  </div>

  {sessions.map(s => (
    <div key={s.id} onClick={() => onDetail(s)} style={{
      padding: '14px 18px', borderBottom: `1px solid ${C.border}`,
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      cursor: 'pointer',
      transition: 'background 80ms',
    }}
    onMouseEnter={e => e.currentTarget.style.background = '#f9f9f9'}
    onMouseLeave={e => e.currentTarget.style.background = C.snow}
    >
      <div>
        <div style={{ fontWeight: 800, fontSize: 14, color: C.midnight }}>{s.nom}</div>
        <div style={{ fontSize: 11, color: '#999', marginTop: 2 }}>
          {new Date(s.date_session).toLocaleDateString('fr-FR')} · {s.responsable} · {s.nb_contacts} contacts
        </div>
      </div>
      <div style={{ display: 'flex', gap: 10, alignItems: 'center' }}>
        {s.nb_interesses > 0  && <Tag color={C.green}  label={`🎯 ${s.nb_interesses} intéressés`} />}
        {s.nb_relances > 0    && <Tag color={C.yellow} label={`🔄 ${s.nb_relances} relances`} />}
        {s.statut === 'active' && <Tag color={C.red}   label="En cours" />}
        <Icon d={ICONS.chevronRight} size={14} color="#ccc" />
      </div>
    </div>
  ))}

  {sessions.length === 0 && !loading && (
    <div style={{ padding: 48, textAlign: 'center', color: '#ccc', fontSize: 13, fontWeight: 700 }}>
      Aucune session — lance ta première prospection
    </div>
  )}
</div>
```

---

## 6. Écran `NewSession` — création de session

### Deux étapes dans la même page (pas de wizard)

**Étape 1 — Paramètres :**
- Champ `nom` (texte libre, placeholder : "ex : Rappels mars — Grands comptes Lyon")
- Select `agence` : Lyon / Paris / Bordeaux / Tous
- Select `delaiJours` : 14 / 30 / 60 / 90 jours depuis dernier contact

**Étape 2 — Sélection des contacts :**

Contacts filtrés depuis la prop `contacts` (tous les contacts CRM) :

```js
const filtered = contacts.filter(c => {
  if (agence !== 'Tous' && c.agence !== agence) return false;
  // filtre sur dernier contact : utiliser c.updated_at ou un champ date_dernier_contact si disponible
  return c.nom.toLowerCase().includes(searchQ.toLowerCase());
});
```

Pour chaque contact dans la liste :
- Checkbox de sélection (brutalist : carré plein, pas de `rounded`)
- Nom + Entreprise + Poste
- Agence + date dernier contact
- Badges jaunes si coordonnées manquantes : `📞?` `✉?` `in?`

Bouton "Tout sélectionner / Désélectionner"

**Bouton lancer :**

```jsx
<BtnAction
  variant="primary"
  label={`▶ Lancer la session (${selected.size} contacts)`}
  onClick={handleStart}
  disabled={selected.size === 0}
  shadow={C.green}
/>
```

`handleStart` crée d'abord la session en base :

```js
async function handleStart() {
  // 1. Insérer la session en base
  const { data: sess } = await sb.from('sessions_prospection').insert({
    nom: nom || `Session ${new Date().toLocaleDateString('fr-FR')}`,
    date_session: new Date().toISOString().slice(0, 10),
    responsable: profile.nom,
    agence: agence !== 'Tous' ? agence : null,
    statut: 'active',
  }).select().single();

  // 2. Insérer les contacts de la session
  const rows = [...selected].map(id => ({
    session_id: sess.id,
    contact_id: id,
    statut: 'none',
  }));
  await sb.from('session_prospection_contacts').insert(rows);

  // 3. Passer à l'écran session active
  onStart({ ...sess, contacts: contacts.filter(c => selected.has(c.id)) });
}
```

---

## 7. Écran `SessionActive` — interface d'appel

### State

```js
const [sessionContacts, setSessionContacts] = useState(
  session.contacts.map(c => ({
    ...c,
    spc_id: null,       // id de session_prospection_contacts
    status: 'none',
    notes: '',
    wantRelance: false,
    relanceDate: null,
    relanceNote: '',
    editTel: c.telephone || '',
    editEmail: c.email || '',
    editLinkedin: c.linkedin || '',
  }))
);
const [view, setView] = useState('list');   // 'list' | 'focus'
const [focusIdx, setFocusIdx] = useState(0);
const [saving, setSaving] = useState(false);
```

### Sauvegarde auto en temps réel (debounce)

Chaque modification d'un contact (statut, notes, relance) → debounced UPSERT dans `session_prospection_contacts` (500ms) pour ne pas perdre le travail en cas de fermeture accidentelle.

```js
const saveContact = useCallback(debounce(async (sc) => {
  await sb.from('session_prospection_contacts').upsert({
    id: sc.spc_id || undefined,
    session_id: session.id,
    contact_id: sc.id,
    statut: sc.status,
    notes: sc.notes || null,
    want_relance: sc.wantRelance,
    relance_date: sc.relanceDate ? fmtISO(sc.relanceDate) : null,
    relance_note: sc.relanceNote || null,
    tel_saisi: sc.editTel !== sc.telephone ? sc.editTel : null,
    email_saisi: sc.editEmail !== sc.email ? sc.editEmail : null,
    linkedin_saisi: sc.editLinkedin !== sc.linkedin ? sc.editLinkedin : null,
  });
}, 500), [session.id]);
```

### Carte contact — champs clés

**Coordonnées :** si `c.telephone` existe → lien cliquable `tel:`. Sinon → input `CoordInput` avec validation (orange si vide, vert si valide). Idem email et LinkedIn.

**Statuts d'appel :** 4 boutons (sans `border-radius`) :

| Bouton | Couleur active | Icône |
|---|---|---|
| Appelé | `C.blue` | ✅ |
| Intéressé ! | `C.green` | 🎯 |
| Pas joignable | `#999` | 📵 |
| Pas intéressé | `C.red` | ⛔ |

**Bloc relance** (conditionnel, visible si status ≠ 'none') :
- Fond `#FFFBF0`, liseré jaune `C.yellow`
- Checkbox "✓ Créer une tâche de relance"
- Presets date : Demain / 3 jours / 1 semaine + sélecteur date
- Note relance (textarea)

### Bouton "Terminer la session"

```jsx
<button onClick={handleTerminer} disabled={saving || stats.done === 0} style={{
  background: C.midnight, color: C.snow,
  border: `2px solid ${C.midnight}`,
  borderLeft: `5px solid ${C.green}`,
  boxShadow: `4px 4px 0 ${C.green}`,
  padding: '10px 20px', fontWeight: 900, fontSize: 12,
  textTransform: 'uppercase', letterSpacing: '0.06em',
  cursor: stats.done === 0 ? 'not-allowed' : 'pointer',
}}>
  {saving ? '⏳ Enregistrement...' : '✓ Terminer la session'}
</button>
```

---

## 8. Logique `handleTerminer` — opérations Supabase

C'est la fonction centrale. Elle effectue les opérations dans cet ordre précis :

```js
async function handleTerminer() {
  setSaving(true);
  const now = new Date();
  const today = now.toISOString().slice(0, 10);
  const appelés = sessionContacts.filter(c => c.status !== 'none');

  // ── 1. UPDATE contacts : coordonnées saisies pendant la session ──────────
  for (const sc of appelés) {
    const upd = {};
    if (sc.editTel     && sc.editTel     !== sc.telephone) upd.telephone = sc.editTel;
    if (sc.editEmail   && sc.editEmail   !== sc.email)     upd.email     = sc.editEmail;
    if (sc.editLinkedin && sc.editLinkedin !== sc.linkedin) upd.linkedin  = sc.editLinkedin;
    if (Object.keys(upd).length > 0) {
      upd.updated_at = now.toISOString();
      await sb.from('contacts').update(upd).eq('id', sc.id);
    }
  }

  // ── 2. INSERT historique_actions : 1 action "Appel sortant" par contact ──
  //    Note : même si "Pas intéressé" ou "Pas joignable" → on logge quand même
  const STATUT_LABELS = {
    called: 'Appelé', interested: 'Intéressé', unreachable: 'Pas joignable', not_interested: 'Pas intéressé',
  };
  const actions = appelés.map(sc => ({
    id_prospect: sc.id,
    date: today,
    type_action: 'Appel sortant',
    details: [
      `Session : ${session.nom}`,
      `Résultat : ${STATUT_LABELS[sc.status]}`,
      sc.notes ? `Notes : ${sc.notes}` : null,
    ].filter(Boolean).join('\n'),
    responsable: profile.nom,
    created_at: now.toISOString(),
  }));
  await sb.from('historique_actions').insert(actions);

  // ── 3. INSERT taches : relances liées au contact ET à la session ─────────
  const relances = appelés.filter(sc => sc.wantRelance && sc.relanceDate);
  if (relances.length > 0) {
    const tasks = relances.map(sc => ({
      id: `tw_${Date.now()}_${sc.id}`,
      titre: `Relance ${sc.prenom || ''} ${sc.nom} — ${sc.entreprise || ''}`.trim(),
      statut: 'a_faire',
      due_date: fmtISO(sc.relanceDate),
      contact_id: sc.id,
      session_prospection_id: session.id,  // ← lien vers la session
      notes: [
        `Session prospection : ${session.nom}`,
        `Statut appel : ${STATUT_LABELS[sc.status]}`,
        sc.relanceNote || null,
      ].filter(Boolean).join('\n'),
      responsable: profile.nom,
      created_at: now.toISOString(),
    }));
    await sb.from('taches').insert(tasks);
  }

  // ── 4. UPDATE session_prospection_contacts (statut final) ────────────────
  for (const sc of sessionContacts) {
    await sb.from('session_prospection_contacts').upsert({
      id: sc.spc_id || undefined,
      session_id: session.id,
      contact_id: sc.id,
      statut: sc.status,
      notes: sc.notes || null,
      want_relance: sc.wantRelance,
      relance_date: sc.relanceDate ? fmtISO(sc.relanceDate) : null,
      relance_note: sc.relanceNote || null,
      tel_saisi: sc.editTel !== sc.telephone ? sc.editTel : null,
      email_saisi: sc.editEmail !== sc.email ? sc.editEmail : null,
      linkedin_saisi: sc.editLinkedin !== sc.linkedin ? sc.editLinkedin : null,
    });
  }

  // ── 5. UPDATE sessions_prospection : marquer done + stats ────────────────
  await sb.from('sessions_prospection').update({
    statut: 'done',
    nb_contacts:     appelés.length,
    nb_interesses:   appelés.filter(c => c.status === 'interested').length,
    nb_relances:     relances.length,
    nb_injoignables: appelés.filter(c => c.status === 'unreachable').length,
    updated_at:      now.toISOString(),
  }).eq('id', session.id);

  setSaving(false);
  onDone();  // → retour liste, rechargement
}
```

---

## 9. KPI Cards cliquables avec détail contextuel (option)

### Principe — identique au tab Missions

Dans `SessionList`, les 4 KPI cards sont **cliquables**. Quand on en clique une :
1. La card devient active (fond midnight, shadow colorée)
2. Un bloc "détail KPI" apparaît juste en dessous des cards, au-dessus de la liste des sessions
3. Ce bloc affiche les contacts correspondants (agrégés sur toutes les sessions)

### Définition des KPI + leurs détails

```js
const KPI_DEFS = [
  {
    id: 'interesses',
    label: 'Intéressés',
    color: C.green,
    getCount: ss => ss.reduce((a,s) => a + s.nb_interesses, 0),
    // Requête pour le détail
    loadDetail: async () => {
      const { data } = await sb
        .from('session_prospection_contacts')
        .select('contact_id, notes, session_id, sessions_prospection(nom, date_session)')
        .eq('statut', 'interested')
        .order('created_at', { ascending: false });
      return data || [];
    },
    renderRow: (row, contactMap) => {
      const c = contactMap[row.contact_id];
      return `${c?.prenom} ${c?.nom} — ${c?.groupe} · Session : ${row.sessions_prospection?.nom}`;
    },
  },
  {
    id: 'relances',
    label: 'Relances en attente',
    color: C.yellow,
    getCount: ss => ss.reduce((a,s) => a + s.nb_relances, 0),
    loadDetail: async () => {
      const { data } = await sb
        .from('taches')
        .select('*, contacts(prenom,nom,groupe)')
        .not('session_prospection_id', 'is', null)
        .eq('statut', 'a_faire')
        .order('due_date', { ascending: true });
      return data || [];
    },
    renderRow: (row) => `${row.contacts?.prenom} ${row.contacts?.nom} — ${row.contacts?.groupe} · Échéance : ${new Date(row.due_date).toLocaleDateString('fr-FR')}`,
  },
  {
    id: 'injoignables',
    label: 'Injoignables',
    color: '#999',
    getCount: ss => ss.reduce((a,s) => a + s.nb_injoignables, 0),
    loadDetail: async () => {
      const { data } = await sb
        .from('session_prospection_contacts')
        .select('contact_id, created_at, session_id, sessions_prospection(nom)')
        .eq('statut', 'unreachable')
        .order('created_at', { ascending: false })
        .limit(20);
      return data || [];
    },
  },
];
```

### Rendu du bloc détail KPI

```jsx
{activeKpi && kpiContacts.length > 0 && (
  <div style={{
    background: C.snow,
    border: `2px solid ${KPI_DEFS.find(k=>k.id===activeKpi)?.color || C.midnight}`,
    borderLeft: `5px solid ${KPI_DEFS.find(k=>k.id===activeKpi)?.color || C.midnight}`,
    marginBottom: 16, padding: 0,
  }}>
    <div style={{ background: C.midnight, padding: '8px 16px', display: 'flex', justifyContent: 'space-between' }}>
      <span style={{ color: C.snow, fontWeight: 800, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.08em' }}>
        {KPI_DEFS.find(k=>k.id===activeKpi)?.label}
      </span>
      <button onClick={() => setActiveKpi(null)} style={{ color: C.yellow, background: 'none', border: 'none', cursor: 'pointer', fontSize: 14 }}>✕</button>
    </div>
    {kpiContacts.map((row, i) => (
      <div key={i} style={{ padding: '10px 16px', borderBottom: `1px solid ${C.border}`, fontSize: 12, color: C.midnight }}>
        {/* renderRow selon le KPI actif — voir sous-sections ci-dessous */}
      </div>
    ))}
  </div>
)}
```

---

### 9a. Comportement "Ignorer / Dismiss" — Intéressés et Injoignables

Les cartes **Intéressés** et **Injoignables** affichent des listes d'items actionnables. L'utilisateur peut traiter chaque ligne de trois façons. Ces états sont **locaux (React state)** — ils ne persistent pas en base, ils servent uniquement à nettoyer la vue pendant la session.

#### État partagé dans chaque composant card

```js
const [ignored, setIgnored] = useState(new Set()); // IDs des lignes cachées
```

Chaque row accepte `ignored` et `setIgnored` en props. Si `ignored.has(c.id)` → retour `null` (ligne invisible).

#### Pagination mobile (PWA)

```js
const PREVIEW_N = 4; // items affichés avant "Voir tout"

const visible = DATA.filter(c => !ignored.has(c.id)); // retire les ignorés
const shown   = visible.slice(0, PREVIEW_N);           // prévisualisation
```

Footer cliquable `VoirToutFooter` → ouvre `VoirToutPanel` (SidePanel simulé) si `visible.length > PREVIEW_N`.
Quand `visible.length === 0` → afficher le message "✓ Tous les contacts ont été traités".

---

### 9b. Card Intéressés — actions par ligne

Chaque ligne = un contact `statut='interested'` issu de `session_prospection_contacts`.

| Bouton | Comportement |
|---|---|
| **+ Créer besoin** | Marque la ligne `done` (badge vert "✓ Besoin créé"), cache les boutons. **Ne retire pas la ligne** — feedback visible. |
| **Ignorer** | `setIgnored(s => new Set([...s, c.id]))` → **retire la ligne** immédiatement. Aucune action en base. |

```jsx
// InterRow — structure des actions
function InterRow({ c, created, setCreated, ignored, setIgnored }) {
  if (ignored.has(c.id)) return null;
  const done = created.has(c.id);
  return (
    <div ...>
      ...
      <div style={{ marginTop:8, display:'flex', gap:8, alignItems:'center', flexWrap:'wrap' }}>
        {done
          ? <span style={{ color:C.green }}>✓ Besoin créé</span>
          : <>
              <button onClick={() => setCreated(s => new Set([...s, c.id]))}>
                + Créer besoin
              </button>
              <button onClick={() => setIgnored(s => new Set([...s, c.id]))}>
                Ignorer
              </button>
            </>
        }
      </div>
    </div>
  );
}
```

**Style du bouton Ignorer** : fond transparent, couleur `#bbb`, border `2px solid ${C.border}`, uppercase, pas de shadow → discret, secondaire.

---

### 9c. Card Injoignables — actions par ligne

Chaque ligne = un contact `statut='unreachable'` issu de `session_prospection_contacts`.

| Bouton | Comportement |
|---|---|
| **+ Prochaine session** | Ajoute à `added` **ET** à `ignored` → **retire la ligne** + mémorise la présélection. |
| **Ignorer** | Ajoute uniquement à `ignored` → **retire la ligne** sans présélection. |

```jsx
// InjRow — structure des actions
function InjRow({ c, added, setAdded, ignored, setIgnored }) {
  if (ignored.has(c.id)) return null;
  const isAdded = added.has(c.id);
  return (
    <div ...>
      ...
      <div style={{ marginTop:8, display:'flex', gap:8, alignItems:'center', flexWrap:'wrap' }}>
        {isAdded
          ? <span>✓ Ajouté à la prochaine session</span>
          : <>
              <button onClick={() => {
                setAdded(s => new Set([...s, c.id]));    // présélectionner
                setIgnored(s => new Set([...s, c.id]));  // retirer la ligne
              }}>
                + Prochaine session
              </button>
              <button onClick={() => setIgnored(s => new Set([...s, c.id]))}>
                Ignorer
              </button>
            </>
        }
      </div>
    </div>
  );
}
```

**Footerinfo** : quand `added.size > 0` → afficher en bas de la card (fond `#f9f9f9`) :
`"{N} contact(s) pré-sélectionné(s) pour la prochaine session."`

**Présélection en base** : lors de la création de la prochaine session (`NewSession`), les `contact_id` présents dans `added` doivent être pré-cochés dans le sélecteur de contacts. L'ensemble `added` doit être **persisté dans `sessionStorage`** (ou passé via context/state parent) pour survivre à la navigation inter-screens.

---

### 9d. Card Sessions — historique et stats

La card Sessions affiche la **liste des sessions passées** avec leurs métriques. C'est une vue **lecture seule** — pas d'actions de dismiss. Le clic sur une ligne ouvre le `SessionDetailPanel` (voir §10).

#### Données source

```js
// Chargé depuis Supabase via loadDetail du KPI 'total'
loadDetail: async () => {
  const { data } = await sb
    .from('sessions_prospection')
    .select('id, nom, date_session, nb_contacts, nb_interesses, nb_relances, nb_injoignables, nb_pas_interesses')
    .eq('statut', 'done')
    .order('date_session', { ascending: false });
  return data || [];
},
```

#### Rendu d'une ligne `SessionRow`

Chaque ligne affiche :

| Élément | Détail |
|---|---|
| **Nom** | `session.nom` en fontWeight 800 |
| **Date + nb contacts** | `session.date_session` + `{nb_contacts} contacts appelés` en gris |
| **Taux d'intérêt** | `Math.round((nb_interesses / nb_contacts) * 100)%` — couleur : vert ≥ 25%, jaune ≥ 10%, rouge < 10% |
| **Barre de répartition** | Flex-row, 3 segments proportionnels : vert `nb_interesses`, gris `#bbb` `nb_injoignables`, gris clair `#eee` `nb_pas_interesses` |
| **Légende** | 3 pictos couleur + label + valeur sous la barre |
| **Curseur** | `cursor:'pointer'` — clic → `onSessionClick(session)` |

```jsx
function SessionRow({ s, onSessionClick }) {
  const total   = s.nb_contacts || 1; // évite division par 0
  const pct     = k => Math.round((s[k] / total) * 100);
  const tauxInt = pct('nb_interesses');
  const urgColor = tauxInt >= 25 ? C.green : tauxInt >= 10 ? C.yellow : C.red;

  const BARS = [
    { k:'nb_interesses',    color: C.green, label:'Intéressés'      },
    { k:'nb_injoignables',  color:'#bbb',   label:'Injoignables'    },
    { k:'nb_pas_interesses',color:'#eee',   label:'Pas intéressés'  },
  ];

  return (
    <div
      onClick={() => onSessionClick(s)}
      style={{
        padding:'14px 18px', borderBottom:`1px solid ${C.border}`,
        cursor:'pointer', background: C.snow,
      }}
      onMouseEnter={e => e.currentTarget.style.background = '#f9f9f9'}
      onMouseLeave={e => e.currentTarget.style.background = C.snow}
    >
      {/* Titre + taux */}
      <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', flexWrap:'wrap', gap:4, marginBottom:8 }}>
        <div>
          <div style={{ fontWeight:800, fontSize:13 }}>{s.nom}</div>
          <div style={{ fontSize:10, color:'#bbb', marginTop:1 }}>
            {new Date(s.date_session).toLocaleDateString('fr-FR', { day:'2-digit', month:'short', year:'numeric' })}
            {' · '}{s.nb_contacts} contact{s.nb_contacts>1?'s':''} appelés
          </div>
        </div>
        <div style={{ textAlign:'right' }}>
          <div style={{ fontSize:22, fontWeight:900, color:urgColor }}>{tauxInt}%</div>
          <div style={{ fontSize:9, fontWeight:700, textTransform:'uppercase', color:'#bbb', letterSpacing:'0.06em' }}>
            taux d'intérêt
          </div>
        </div>
      </div>

      {/* Barre de répartition */}
      <div style={{ display:'flex', height:14, gap:2 }}>
        {BARS.map(b => {
          const w = pct(b.k);
          return w > 0 ? (
            <div key={b.k} style={{
              width:`${w}%`, background:b.color, overflow:'hidden',
              display:'flex', alignItems:'center', justifyContent:'center',
              fontSize:9, fontWeight:800,
              color: b.color === '#eee' ? '#999' : '#fff',
            }}>
              {w > 8 ? `${w}%` : ''}
            </div>
          ) : null;
        })}
      </div>

      {/* Légende */}
      <div style={{ display:'flex', gap:10, marginTop:5, flexWrap:'wrap' }}>
        {BARS.map(b => (
          <div key={b.k} style={{ display:'flex', alignItems:'center', gap:4 }}>
            <span style={{ width:8, height:8, background:b.color, border:`1px solid ${C.border}`, display:'inline-block' }}/>
            <span style={{ fontSize:10, color:'#999' }}>{s[b.k]} {b.label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
```

#### Structure `CardSessions`

```jsx
function CardSessions({ sessions, onSessionClick }) {
  const [panel, setPanel] = useState(false);
  const shown = sessions.slice(0, PREVIEW_N);

  return (
    <>
      <CardHeader
        color={C.blue}
        title="Historique sessions"
        count={`${sessions.length} session${sessions.length>1?'s':''}`}
        hint="· taux d'intérêt par session"
        totalItems={sessions.length}
        onVoirTout={() => setPanel(true)}
      />
      {shown.map(s => <SessionRow key={s.id} s={s} onSessionClick={onSessionClick} />)}
      {sessions.length === 0 && (
        <div style={{ padding:'24px 18px', textAlign:'center', fontSize:12, color:'#bbb', fontWeight:700 }}>
          Aucune session terminée pour l'instant.
        </div>
      )}
      <VoirToutFooter shown={shown.length} total={sessions.length} color={C.blue} onVoirTout={() => setPanel(true)} />
      {panel && (
        <VoirToutPanel title="Toutes les sessions" color={C.blue} onClose={() => setPanel(false)}>
          {sessions.map(s => <SessionRow key={s.id} s={s} onSessionClick={s => { setPanel(false); onSessionClick(s); }} />)}
        </VoirToutPanel>
      )}
    </>
  );
}
```

**Clic sur une session** → appelle `onSessionClick(session)` → ouvre `SessionDetailPanel` (§10) avec la session sélectionnée. Si le panel Voir tout est ouvert, le fermer avant d'ouvrir le `SessionDetailPanel`.

**Pas de dismiss/ignore** sur cette card : les sessions sont des données historiques immuables.

---

## 10. Composant `SessionDetailPanel` — volet droit

Utilise le composant `SidePanel` existant (lignes ~663 de `CRM_Live.html`). **Pattern strictement identique aux autres onglets** (`TacheDetailPanel`, `BesoinDetail`, etc.).

```jsx
function SessionDetailPanel({ session, contactMap, onClose }) {
  const [spcRows, setSpcRows] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      const { data } = await sb
        .from('session_prospection_contacts')
        .select('*')
        .eq('session_id', session.id)
        .neq('statut', 'none')
        .order('created_at');
      setSpcRows(data || []);
      setLoading(false);
    }
    load();
  }, [session.id]);

  const stats = {
    interesses:   spcRows.filter(r => r.statut === 'interested').length,
    relances:     spcRows.filter(r => r.want_relance && r.relance_date).length,
    injoignables: spcRows.filter(r => r.statut === 'unreachable').length,
  };

  return (
    <SidePanel
      title={session.nom}
      badge={session.statut === 'done' ? 'Terminée' : 'En cours'}
      onClose={onClose}
      actions={null}  // pas de boutons d'action pour l'instant
    >
      {/* Date + responsable */}
      <div style={{ padding: '12px 20px', borderBottom: `1px solid ${C.border}`, fontSize: 12, color: '#999' }}>
        {new Date(session.date_session).toLocaleDateString('fr-FR', { day:'2-digit', month:'long', year:'numeric' })}
        &nbsp;·&nbsp;{session.responsable}
        {session.agence && <>&nbsp;·&nbsp;{session.agence}</>}
      </div>

      {/* Stats session */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 8, padding: '14px 20px', borderBottom: `1px solid ${C.border}` }}>
        {[
          { v: session.nb_contacts,     label: 'Appelés',     color: C.midnight },
          { v: stats.interesses,        label: 'Intéressés',  color: C.green    },
          { v: stats.relances,          label: 'Relances',    color: C.yellow   },
        ].map(s => (
          <div key={s.label} style={{ textAlign: 'center', background: C.bg, padding: '10px 8px', border: `1px solid ${C.border}`, borderLeft: `3px solid ${s.color}` }}>
            <div style={{ fontSize: 22, fontWeight: 900, color: s.color }}>{s.v}</div>
            <div style={{ fontSize: 9, fontWeight: 700, textTransform: 'uppercase', color: '#bbb', letterSpacing: '0.06em', marginTop: 2 }}>{s.label}</div>
          </div>
        ))}
      </div>

      {/* Liste des contacts appelés */}
      <div style={{ padding: '14px 20px' }}>
        <div style={{ fontSize: 11, fontWeight: 800, textTransform: 'uppercase', letterSpacing: '0.08em', color: '#999', marginBottom: 10 }}>
          Contacts traités
        </div>
        {loading && <div style={{ color: '#ccc', fontSize: 12 }}>Chargement...</div>}
        {spcRows.map(row => {
          const c = contactMap[row.contact_id];
          const cfg = STATUS_CFG[row.statut] || STATUS_CFG.none;
          return (
            <div key={row.id} style={{ padding: '10px 0', borderBottom: `1px solid ${C.border}`, display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 700, fontSize: 13 }}>{c?.prenom} {c?.nom}</div>
                <div style={{ fontSize: 11, color: '#888' }}>{c?.groupe}</div>
                {row.notes && <div style={{ fontSize: 11, color: '#999', marginTop: 3, fontStyle: 'italic' }}>« {row.notes} »</div>}
                {row.want_relance && row.relance_date && (
                  <div style={{ fontSize: 10, color: C.yellow, fontWeight: 700, marginTop: 3 }}>
                    🔄 Relance : {new Date(row.relance_date).toLocaleDateString('fr-FR')}
                  </div>
                )}
              </div>
              <span style={{ fontSize: 10, fontWeight: 800, textTransform: 'uppercase', letterSpacing: '0.06em', background: cfg.bg, color: cfg.color, border: `2px solid ${cfg.color}`, padding: '2px 6px', marginLeft: 8, flexShrink: 0 }}>
                {cfg.icon} {cfg.label}
              </span>
            </div>
          );
        })}
      </div>
    </SidePanel>
  );
}
```

---

## 11. Constantes `STATUS_CFG` à déclarer en tête de fichier

À ajouter dans la section des constantes globales de `CRM_Live.html` (près de `CANDIDAT_STATUTS`) :

```js
const PROSPECT_STATUTS = {
  none:          { label: 'À appeler',      color: C.border, bg: '#f9f9f9', icon: '📞' },
  called:        { label: 'Appelé',         color: '#4A7FE5', bg: '#EEF3FF', icon: '✅' },
  interested:    { label: 'Intéressé !',    color: '#00C218', bg: '#EDFFF1', icon: '🎯' },
  unreachable:   { label: 'Pas joignable',  color: '#999',    bg: '#f5f5f5', icon: '📵' },
  not_interested:{ label: 'Pas intéressé',  color: '#FF3D2E', bg: '#FFF0EF', icon: '⛔' },
};
```

---

## 12. Récupération des sessions pour le compteur de tab

Dans le `useEffect` principal qui charge les données (là où sont chargés contacts, tâches, etc.) :

```js
const { data: sessionsData } = await sb
  .from('sessions_prospection')
  .select('id, nom, statut, nb_contacts, nb_interesses, nb_relances, nb_injoignables, date_session, responsable, agence')
  .order('created_at', { ascending: false });
setSessions(sessionsData || []);
```

---

## 13. Critères QA

| # | Zone | Test | Attendu |
|---|---|---|---|
| 1 | Navigation | Tab "Prosp." | Apparaît entre Contacts et Besoins, compteur = nombre de sessions |
| 2 | SessionList | KPI cards | 4 cards cliquables avec détail contextuel au clic |
| 3 | SessionList | Clic sur une session | `SidePanel` s'ouvre à droite avec stats + contacts traités |
| 4 | SessionList | Appui Escape | `SidePanel` se ferme (comportement natif `SidePanel`) |
| 5 | NewSession | Filtre agence | Liste filtrée en temps réel |
| 6 | NewSession | Badges coordonnées manquantes | `📞?` `✉?` `in?` visibles sur les contacts concernés |
| 7 | SessionActive | Sauvegarde auto | Modifications sauvegardées en base (debounce 500ms) — si refresh, progression conservée |
| 8 | SessionActive | Coordonnées saisies | Champ input jaune si vide, vert si valide |
| 9 | handleTerminer | UPDATE contacts | `telephone`, `email`, `linkedin` mis à jour uniquement si nouveaux et valides |
| 10 | handleTerminer | INSERT historique_actions | 1 action par contact avec status ≠ 'none', type "Appel sortant", contenu de la session + notes |
| 11 | handleTerminer | INSERT taches | Tâche de relance avec `contact_id` + `session_prospection_id`, `due_date`, `notes` contextuelles |
| 12 | handleTerminer | Retour liste | Session apparaît en tête de liste avec statut "done" et stats correctes |
| 13 | TacheDetail | Lien session | Dans `TacheDetailPanel`, si `task.session_prospection_id` présent → afficher "Session : [nom]" comme lien contextuel |
| 14 | ContactDetail | Historique | Les appels de prospection apparaissent dans l'historique du contact avec type "Appel sortant" |
| 15 | Tous | border-radius | Zéro arrondi partout |
| 16 | Deploy | — | `bash supabase/deploy_staging.sh` — jamais main |
