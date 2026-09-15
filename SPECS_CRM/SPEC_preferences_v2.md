# SPEC — Système de Préférences v2 + Volet Admin
**CRM Upgrade Lyon V2** · Feature enhancement
**Date :** 28/03/2026

---

## Contexte

Le système de préférences actuel stocke 10 champs dans `profile.preferences` (JSON). Cette spec définit :
1. **Delta de nouveaux champs** à ajouter aux préférences utilisateur individuelles
2. **Bug fix** du conflit localStorage vs `default_tab`
3. **Volet Admin** : panneau de configuration des valeurs par défaut au niveau agence/commercial

---

## 1. État actuel des préférences (existant — ne pas casser)

```js
profile.preferences = {
  default_tab: 'contacts',           // onglet ouvert au démarrage
  contacts_sort: 'alpha',            // tri liste contacts
  taches_sort: 'echeance',          // tri liste tâches
  pipe_sort: 'ca_desc',             // tri pipe
  notifications_email: true,
  theme: 'light',
  langue: 'fr',
  compact_mode: false,
  kanban_column_order: [...],        // ordre colonnes kanban pipe
  displayed_badge: 'recruteur:2',    // badge affiché dans le header
}
```

---

## 2. Delta — Nouveaux champs préférences utilisateur

### 2.1 Filtres par défaut manquants

Ces filtres sont aujourd'hui hardcodés ou stockés en localStorage sans persistance cross-device.

```js
// À ajouter dans profile.preferences
contacts_filter_statut: 'all',       // 'all' | 'Client' | 'Prospect' | 'Lead' | 'Froid'
contacts_filter_agence: 'all',       // 'all' | 'Lyon' | 'Paris' | 'Bordeaux' | ...
contacts_filter_responsable: 'me',   // 'me' | 'all' | <nom_commercial>

taches_filter_echeance: 'all',       // 'all' | 'today' | 'week' | 'late'
taches_filter_responsable: 'me',     // 'me' | 'all' | <nom_commercial>

missions_filter_statut: 'all',       // 'all' | 'En cours' | 'Terminée' | 'Suspendue'
missions_filter_agence: 'all',       // 'all' | 'Lyon' | 'Paris' | ...

pipe_filter_risk: 'all',             // 'all' | 'high' | 'medium' | 'low'
pipe_filter_agence: 'all',           // 'all' | 'Lyon' | 'Paris' | ...
pipe_filter_responsable: 'me',       // 'me' | 'all' | <nom_commercial>
```

### 2.2 Comportement & affichage

```js
contacts_density: 'normal',          // 'compact' | 'normal' | 'spacious'
pipe_colonnes_visibles: null,        // null = toutes | string[] = liste colonnes affichées
prospection_focus_mode: false,       // true = masque sidebar pendant session prospection
agenda_default_view: 'week',        // 'day' | 'week' | 'month'
```

### 2.3 Migration localStorage → prefs

**Bug actuel :** `crm_tab` dans localStorage écrase `default_tab` depuis les préférences, ce qui casse la persistance cross-device.

**Fix :**
```js
// Avant (dans le composant App au mount)
const savedTab = localStorage.getItem('crm_tab') || profile.preferences?.default_tab || 'contacts';

// Après
// Supprimer la lecture localStorage pour l'onglet par défaut.
// localStorage.removeItem('crm_tab') au moment de la migration.
// L'onglet actif PENDANT la session reste en state local (useState) mais
// au démarrage on lit uniquement profile.preferences.default_tab.

const savedTab = profile.preferences?.default_tab || 'contacts';
// Note : conserver localStorage uniquement pour la session courante si besoin UX
// mais NE PAS l'utiliser comme valeur initiale au montage.
```

**Acceptance criteria du fix :**
- [ ] Au démarrage, l'onglet ouvert = `profile.preferences.default_tab`
- [ ] Changer d'onglet pendant la session ne modifie pas les préférences
- [ ] Choisir "Onglet par défaut" dans Paramètres → Préférences persiste en DB et prend effet au prochain démarrage
- [ ] localStorage `crm_tab` n'interfère plus

---

## 3. UX — Onglet "Préférences" dans Paramètres (utilisateur)

L'onglet Préférences existant dans Paramètres est étendu avec des sections collapsables.

### Structure

```
┌─ Préférences ──────────────────────────────────────────┐
│                                                          │
│  ▼ NAVIGATION                                            │
│    Onglet par défaut : [Contacts ▼]                     │
│    Densité contacts  : ○ Compact  ● Normal  ○ Spacieux  │
│                                                          │
│  ▼ FILTRES PAR DÉFAUT — Contacts                        │
│    Statut      : [Tous ▼]                               │
│    Agence      : [Toutes ▼]                             │
│    Responsable : [Moi ▼]                                │
│                                                          │
│  ▼ FILTRES PAR DÉFAUT — Tâches                          │
│    Échéance    : [Toutes ▼]                             │
│    Responsable : [Moi ▼]                                │
│                                                          │
│  ▼ FILTRES PAR DÉFAUT — Pipe                            │
│    Risque      : [Tous ▼]                               │
│    Agence      : [Toutes ▼]                             │
│    Responsable : [Moi ▼]                                │
│                                                          │
│  ▼ FILTRES PAR DÉFAUT — Missions                        │
│    Statut      : [Tous ▼]                               │
│    Agence      : [Toutes ▼]                             │
│                                                          │
│  ▼ COMPORTEMENT                                          │
│    Focus mode prospection : [toggle]                    │
│    Vue agenda par défaut  : [Semaine ▼]                 │
│                                                          │
│  [Enregistrer les préférences]                          │
└──────────────────────────────────────────────────────────┘
```

### Persistance

```js
const savePrefs = async (newPrefs) => {
  const merged = { ...profile.preferences, ...newPrefs };
  await sb.from('profiles')
    .update({ preferences: merged })
    .eq('id', user.id);
  setProfile(p => ({ ...p, preferences: merged }));
};
```

---

## 4. Volet Admin — Defaults agence / par commercial

### Concept

Les admins peuvent définir des **valeurs par défaut d'organisation** appliquées à tout nouvel utilisateur ou à un commercial spécifique. Ces defaults sont des *suggestions initiales* : l'utilisateur peut ensuite les overrider dans ses propres préférences.

**Règle de priorité :**
```
profile.preferences (user) > org_defaults pour ce user > org_defaults global agence > hardcoded fallback
```

### 4.1 Stockage

Nouvelle table Supabase : `org_preferences`

```sql
CREATE TABLE org_preferences (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  scope       text NOT NULL,   -- 'global' | 'agence' | 'responsable'
  scope_value text,            -- null si global, 'Lyon' si agence, 'Nicolas S.' si responsable
  preferences jsonb NOT NULL DEFAULT '{}',
  updated_by  text,
  updated_at  timestamptz DEFAULT now()
);
```

Exemples de rows :
```
scope='global'       scope_value=null          preferences={contacts_filter_agence:'all', ...}
scope='agence'       scope_value='Lyon'        preferences={contacts_filter_agence:'Lyon', pipe_filter_agence:'Lyon'}
scope='responsable'  scope_value='Nicolas S.'  preferences={taches_filter_responsable:'me', contacts_filter_responsable:'me'}
```

### 4.2 UX — Panneau Admin dans Paramètres

**Visible uniquement si `activeProfile.role === 'admin'`.**

Nouvel onglet dans Paramètres (5ème, après Exploits) : **"⚙ Admin"**

```
┌─ Administration — Valeurs par défaut ───────────────────────────────┐
│                                                                       │
│  Ces réglages s'appliquent aux utilisateurs n'ayant pas encore      │
│  défini leurs propres préférences.                                   │
│                                                                       │
│  SCOPE : [Global ▼]  →  s'applique à toute l'agence                 │
│          [Agence ▼]  →  [Lyon ▼] [Paris ▼] ...                      │
│          [Commercial ▼]  →  [Nicolas S. ▼] [Julie M. ▼] ...        │
│                                                                       │
│  ┌── Onglet sélectionné : [Global] ────────────────────────────┐    │
│  │                                                               │    │
│  │  CONTACTS                                                     │    │
│  │    Filtre Statut par défaut      : [Tous ▼]                  │    │
│  │    Filtre Agence par défaut      : [Toutes ▼]                │    │
│  │    Filtre Responsable par défaut : [Tous ▼]                  │    │
│  │    Tri par défaut                : [Alphabétique ▼]          │    │
│  │                                                               │    │
│  │  TÂCHES                                                       │    │
│  │    Filtre Échéance par défaut    : [Toutes ▼]                │    │
│  │    Filtre Responsable par défaut : [Moi ▼]                   │    │
│  │    Tri par défaut                : [Échéance ▼]              │    │
│  │                                                               │    │
│  │  PIPE                                                         │    │
│  │    Filtre Risque par défaut      : [Tous ▼]                  │    │
│  │    Filtre Agence par défaut      : [Toutes ▼]                │    │
│  │    Filtre Responsable par défaut : [Tous ▼]                  │    │
│  │    Tri par défaut                : [CA desc ▼]               │    │
│  │                                                               │    │
│  │  MISSIONS                                                     │    │
│  │    Filtre Statut par défaut      : [Tous ▼]                  │    │
│  │    Filtre Agence par défaut      : [Toutes ▼]                │    │
│  │                                                               │    │
│  │  [Enregistrer les defaults]                                   │    │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                       │
│  ⚠ Ces réglages ne remplacent pas les préférences individuelles.    │
│    Un utilisateur qui a déjà sauvegardé ses prefs garde les siennes. │
└───────────────────────────────────────────────────────────────────────┘
```

### 4.3 Logique de résolution au démarrage

```js
// Au mount, après chargement du profile
const resolvePrefs = (userPrefs, orgDefaults_responsable, orgDefaults_agence, orgDefaults_global) => {
  return {
    ...HARDCODED_FALLBACK,           // valeurs par défaut du code
    ...orgDefaults_global,           // defaults globaux agence
    ...orgDefaults_agence,           // defaults pour l'agence du user
    ...orgDefaults_responsable,      // defaults pour ce commercial spécifique
    ...userPrefs,                    // préférences personnelles (priorité max)
  };
};

// Fetch org_preferences au démarrage (une seule requête)
const { data: orgPrefs } = await sb
  .from('org_preferences')
  .select('*')
  .in('scope', ['global', 'agence', 'responsable'])
  .or(`scope_value.is.null,scope_value.eq.${activeProfile.agence},scope_value.eq.${activeProfile.nom}`);

const globalDefaults     = orgPrefs.find(r => r.scope === 'global')?.preferences ?? {};
const agenceDefaults     = orgPrefs.find(r => r.scope === 'agence' && r.scope_value === activeProfile.agence)?.preferences ?? {};
const responsableDefaults = orgPrefs.find(r => r.scope === 'responsable' && r.scope_value === activeProfile.nom)?.preferences ?? {};

const effectivePrefs = resolvePrefs(profile.preferences, responsableDefaults, agenceDefaults, globalDefaults);
```

### 4.4 Cas d'usage typiques

| Situation | Config admin recommandée |
|---|---|
| Tout le bureau Lyon → voir seulement les contacts Lyon par défaut | `scope=agence, scope_value=Lyon, contacts_filter_agence='Lyon'` |
| Nicolas voit toujours ses tâches à lui par défaut | `scope=responsable, scope_value='Nicolas S.', taches_filter_responsable='me'` |
| Toute l'agence démarre sur l'onglet Pipe | `scope=global, default_tab='pipe'` |
| Julie voit le pipe global (toutes agences) | `scope=responsable, scope_value='Julie M.', pipe_filter_agence='all'` |

---

## 5. Schéma complet des préférences v2

```js
// profile.preferences (utilisateur individuel)
{
  // — Existant —
  default_tab: 'contacts',
  contacts_sort: 'alpha',
  taches_sort: 'echeance',
  pipe_sort: 'ca_desc',
  notifications_email: true,
  theme: 'light',
  langue: 'fr',
  compact_mode: false,
  kanban_column_order: [...],
  displayed_badge: 'recruteur:2',

  // — Nouveau v2 —
  contacts_filter_statut: 'all',
  contacts_filter_agence: 'all',
  contacts_filter_responsable: 'me',
  taches_filter_echeance: 'all',
  taches_filter_responsable: 'me',
  missions_filter_statut: 'all',
  missions_filter_agence: 'all',
  pipe_filter_risk: 'all',
  pipe_filter_agence: 'all',
  pipe_filter_responsable: 'me',
  contacts_density: 'normal',
  pipe_colonnes_visibles: null,
  prospection_focus_mode: false,
  agenda_default_view: 'week',
}
```

---

## 6. Acceptance criteria globaux

### Préférences utilisateur
- [ ] Les 14 nouveaux champs sont persistés dans `profile.preferences`
- [ ] L'UI Paramètres → Préférences expose toutes les options organisées en sections
- [ ] Le bug `crm_tab` localStorage est corrigé : au démarrage c'est `default_tab` qui prévaut
- [ ] Les filtres par défaut sont appliqués à l'ouverture de chaque onglet (sans écraser la session en cours)

### Volet Admin
- [ ] L'onglet Admin est visible uniquement pour les profils `role === 'admin'`
- [ ] Le sélecteur de scope (Global / Agence / Commercial) filtre les champs affichés
- [ ] Sauvegarder crée ou update la row correspondante dans `org_preferences`
- [ ] La résolution de priorité est correcte : user > responsable > agence > global > fallback
- [ ] Un commercial sans prefs personnalisées hérite des defaults de son agence
- [ ] Les defaults ne modifient PAS les `profile.preferences` des utilisateurs existants

### Non-régressions
- [ ] `displayed_badge` et `kanban_column_order` ne sont pas affectés
- [ ] Tous les filtres interactifs (clic dans UI) continuent à fonctionner normalement pendant la session
- [ ] Pas de requête supplémentaire à chaque changement de filtre (résolution faite une fois au mount)

---

## 7. Dépendances

- Nécessite la création de la table `org_preferences` en base (migration SQL)
- La lecture des org_preferences doit être ajoutée dans le fetch initial du profil
- L'onglet Admin dans Paramètres est conditionnel à `role === 'admin'`
- Compatible avec le système de badges (Exploits = 4ème tab, Admin = 5ème tab)
