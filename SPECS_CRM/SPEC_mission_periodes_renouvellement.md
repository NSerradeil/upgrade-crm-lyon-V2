# SPEC — Périodes de mission & Renouvellement
**CRM Upgrade Lyon V2** · Feature
**Date :** 03/04/2026
**Rôles :** Tech Lead · Product Owner · Lead UX

---

## 1. Contexte produit

Aujourd'hui, renouveler une mission oblige à créer une nouvelle fiche mission depuis zéro. C'est une friction inutile : on perd la continuité historique (TJM, N° commandes, durée réelle de la relation), on duplique les données, et le commercial ne peut pas voir l'évolution des conditions dans le temps.

**Objectif :** permettre l'ajout de périodes successives sur une mission existante, avec suivi des conditions financières et d'un commentaire de contexte par période.

---

## 2. Modèle de données

### 2.1 Nouvelle table Supabase : `mission_periods`

```sql
CREATE TABLE mission_periods (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  mission_id      uuid NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  label           text NOT NULL,                        -- "Période initiale", "Renouvellement 1"…
  debut           date NOT NULL,
  fin             date NOT NULL,
  numero_commande text,
  tjm_vente       numeric(10,2),
  cjm_consultant  numeric(10,2),
  commentaire     text,
  created_by      text,                                 -- nom du commercial
  created_at      timestamptz DEFAULT now(),

  CONSTRAINT periods_dates_check CHECK (fin > debut)
);

CREATE INDEX idx_mission_periods_mission_id ON mission_periods(mission_id);
```

### 2.2 Migration des données existantes

Pour chaque mission existante ayant `date_debut` et `date_fin` en base :

```sql
INSERT INTO mission_periods (mission_id, label, debut, fin, tjm_vente, cjm_consultant)
SELECT id, 'Période initiale', date_debut, date_fin, tjm_vente, cjm_consultant
FROM missions
WHERE date_debut IS NOT NULL;
```

### 2.3 Champs missions existants (ne pas supprimer)

Les champs `date_debut`, `date_fin`, `tjm_vente`, `cjm_consultant` restent sur la table `missions` et sont **synchronisés** automatiquement avec la dernière période active pour rétrocompatibilité avec le reste du CRM (pipe, calculs de marge, etc.).

**Règle de sync :** à chaque `INSERT` ou `UPDATE` sur `mission_periods`, mettre à jour la mission parente :

```sql
-- Trigger ou logique applicative côté frontend
UPDATE missions SET
  date_fin      = (SELECT MAX(fin) FROM mission_periods WHERE mission_id = $mission_id),
  tjm_vente     = (SELECT tjm_vente FROM mission_periods WHERE mission_id = $mission_id ORDER BY debut DESC LIMIT 1),
  cjm_consultant= (SELECT cjm_consultant FROM mission_periods WHERE mission_id = $mission_id ORDER BY debut DESC LIMIT 1)
WHERE id = $mission_id;
```

---

## 3. API / Supabase (Superpowers)

### 3.1 Fetch des périodes d'une mission

```js
// Dans loadMissionDetail()
const { data: periods } = await sb
  .from('mission_periods')
  .select('*')
  .eq('mission_id', missionId)
  .order('debut', { ascending: true });
```

### 3.2 Ajout d'une période (renouvellement)

```js
const addPeriod = async (missionId, draft, userName) => {
  const { data, error } = await sb
    .from('mission_periods')
    .insert({
      mission_id:      missionId,
      label:           draft.label,
      debut:           draft.debut,
      fin:             draft.fin,
      numero_commande: draft.commande || null,
      tjm_vente:       draft.tjm_vente ? Number(draft.tjm_vente) : null,
      cjm_consultant:  draft.cjm_consultant ? Number(draft.cjm_consultant) : null,
      commentaire:     draft.commentaire || null,
      created_by:      userName,
    })
    .select()
    .single();

  if (error) throw error;

  // Sync mission parente
  await syncMissionFromPeriods(missionId);

  // Log action
  await sb.from('historique_actions').insert({
    contact_id:  mission.contact_id,
    type:        'renouvellement_mission',
    description: `Renouvellement mission ${mission.titre} — ${draft.debut} → ${draft.fin}`,
    auteur:      userName,
  });

  return data;
};
```

### 3.3 Règles de validation avant insert

```js
const validatePeriod = (draft, existingPeriods) => {
  const errors = [];
  if (!draft.debut) errors.push('Date de début obligatoire');
  if (!draft.fin)   errors.push('Date de fin obligatoire');
  if (draft.debut >= draft.fin) errors.push('La fin doit être après le début');

  // Pas de chevauchement avec périodes existantes
  const overlap = existingPeriods.some(p =>
    draft.debut <= p.fin && draft.fin >= p.debut
  );
  if (overlap) errors.push('Les périodes ne peuvent pas se chevaucher');

  return errors;
};
```

---

## 4. UX & Frontend

### 4.1 Principes UX

- **Zero disruption** : la section Périodes vit dans le détail mission existant, pas dans un nouvel écran ou une modale
- **Progressive disclosure** : la section est collapsable ; les commentaires se déplient à la demande (icône 💬)
- **Feedback immédiat** : delta TJM/CJM affiché en temps réel, marge calculée live pendant la saisie
- **Guard rail** : si TJM ou CJM change, un hint visuel encourage à renseigner un commentaire — sans le rendre obligatoire (pas de friction excessive)

### 4.2 Placement dans le détail mission

La section **PÉRIODES DE MISSION** s'insère entre le bloc d'informations de la mission et la section Historique/Actions, dans le panneau latéral ou la vue détail selon le layout actuel.

```
┌─ Détail Mission ──────────────────────────────────────┐
│  [Header mission : titre, consultant, client, statut] │
│  [Infos : agence, responsable, type contrat]          │
│                                                        │
│  ▼ PÉRIODES DE MISSION  [2]          ← nouvelle section│
│    [table périodes + bouton renouveler]               │
│                                                        │
│  ▼ HISTORIQUE                                         │
│    [actions, logs]                                    │
└────────────────────────────────────────────────────────┘
```

### 4.3 DA Upgrade — règles visuelles

**Typographie & couleurs (système existant) :**
```js
// Headers section
fontSize: 11, fontWeight: 700, letterSpacing: 1, color: '#9CA3AF', textTransform: 'uppercase'

// Valeurs numériques importantes (TJM)
fontSize: 13, fontWeight: 700, color: '#111'

// Labels champs formulaire
fontSize: 10, fontWeight: 700, color: '#6B7280', letterSpacing: 0.8

// Texte secondaire / commentaires
fontSize: 13, fontStyle: 'italic', color: '#374151'

// Jaune Upgrade (existant dans les badges statut)
#FFD600
```

**Badges delta TJM/CJM :**
```js
// Hausse
{ background: '#D1FAE5', color: '#065F46' }   // vert pâle
// Baisse
{ background: '#FEE2E2', color: '#991B1B' }   // rouge pâle
```

**Ligne EN COURS :**
```js
background: '#FFFBEB'  // jaune très pâle — cohérent avec la palette Upgrade
```

**Pill "EN COURS" :**
```js
{ background: '#FEF3C7', color: '#92400E', fontSize: 9, fontWeight: 700 }
```

**Hint commentaire (TJM modifié) :**
```js
{ background: '#FEF3C7', color: '#92400E' }  // orange chaud — alerte douce
```

**Bouton "Renouveler la mission" :**
```js
// Dashed border — bouton d'ajout discret, DA Upgrade standard
border: '1px dashed #D1D5DB', background: '#F9FAFB', color: '#374151'
```

**Formulaire inline (état "adding") :**
```js
background: '#EFF6FF', border: '1px solid #BFDBFE'  // bleu pâle — mode édition
```

### 4.4 Structure du composant React

```jsx
// Composant principal
<MissionPeriodesSection
  missionId={mission.id}
  periods={periods}           // chargé depuis mission_periods
  currentUser={activeProfile.nom}
  onPeriodsChange={reloadMission}
/>

// Sous-composants
<PeriodeRow period={p} index={idx} allPeriods={periods} />
  └─ <CommentaireBlock commentaire={p.commentaire} isOpen={...} />
  └─ <DeltaTag prev={periods[idx-1]} curr={p} field="tjm_vente" />

<PeriodeForm
  draft={draft}
  lastPeriod={periods[periods.length - 1]}
  onChange={setDraft}
  onConfirm={handleConfirm}
  onCancel={handleCancel}
  validationErrors={errors}
/>

<KpisRecap periods={periods} />
```

### 4.5 États du composant

```
IDLE          → affiche la liste + bouton "Renouveler"
ADDING        → affiche la liste + formulaire inline ouvert
SAVING        → bouton "Confirmer" en loading (spinner)
ERROR         → message d'erreur inline sous le formulaire
SUCCESS       → la nouvelle période apparaît dans la liste, formulaire fermé
```

### 4.6 Colonnes de la table

| Colonne | Largeur | Contenu |
|---|---|---|
| Label | 130px | "Période initiale" / "Renouvellement N" + pill EN COURS |
| Début | 100px | Date formatée `dd mmm yyyy` |
| Fin | 100px | Date formatée |
| N° Commande | 120px | Monospace, gris |
| TJM Vente | 90px | Valeur + delta pill |
| CJM Consultant | 90px | Valeur + delta pill |
| Marge | 55px | % coloré (vert ≥25%, orange ≥15%, rouge <15%) |
| 💬 | 28px | Toggle commentaire — grisé si vide |

### 4.7 KPIs récap (sous la section)

4 cards en ligne :
- **Durée totale** : de `periods[0].debut` à `periods[last].fin`, en mois
- **TJM moyen vente** : moyenne arithmétique
- **Marge moyenne** : moyenne des marges par période
- **Commentaires** : `X / N` — signal de complétude documentaire

---

## 5. Gestion des erreurs & edge cases

| Cas | Comportement |
|---|---|
| Chevauchement de dates | Erreur inline sous le champ fin : "Cette période chevauche une période existante" |
| fin ≤ debut | Erreur inline : "La date de fin doit être postérieure au début" |
| Mission sans période (legacy) | Afficher "Aucune période enregistrée" + bouton "Créer la période initiale" |
| Période unique | Pas de delta affiché (pas de comparaison possible) |
| TJM ou CJM vide | Marge affichée "—", pas d'erreur |
| Suppression d'une période | Non implémenté en V1 (trop risqué historiquement) — prévoir bouton caché admin only |

---

## 6. Plan de test staging

### 6.1 Setup

```
1. Appliquer la migration SQL sur la DB staging
2. Lancer le script de migration des données existantes
3. Vérifier que les missions existantes ont bien leur "Période initiale" créée
4. Déployer la branche feature sur staging
```

### 6.2 Cas de test fonctionnels

**T01 — Affichage section périodes**
- [ ] Ouvrir une mission existante → section "PÉRIODES DE MISSION" visible avec au moins la période initiale
- [ ] La période dont les dates encadrent aujourd'hui est surlignée jaune avec pill "EN COURS"
- [ ] Le compteur de périodes dans le header est correct

**T02 — Ajout d'un renouvellement**
- [ ] Cliquer "Renouveler la mission" → formulaire s'ouvre en inline
- [ ] La date de début est pré-remplie au lendemain de la fin de la dernière période
- [ ] Remplir tous les champs → cliquer "Confirmer" → nouvelle ligne apparaît dans la table
- [ ] La mission parente a ses champs `date_fin`, `tjm_vente`, `cjm_consultant` mis à jour
- [ ] Une action est loggée dans `historique_actions`

**T03 — Validation**
- [ ] Soumettre sans date de début → erreur "Date de début obligatoire"
- [ ] Mettre fin < début → erreur "La fin doit être après le début"
- [ ] Mettre des dates qui chevauchent une période existante → erreur de chevauchement
- [ ] Le bouton "Confirmer" reste disabled tant que début ou fin est vide

**T04 — Commentaires**
- [ ] Ajouter une période avec commentaire → icône 💬 active, clic → commentaire visible en italique
- [ ] Ajouter une période sans commentaire → icône 💬 grisée (opacity 0.25)
- [ ] TJM modifié pendant la saisie → hint orange "TJM modifié — explique pourquoi" visible

**T05 — Deltas TJM/CJM**
- [ ] Si TJM renouvellement > TJM période précédente → pill vert "+X€"
- [ ] Si TJM renouvellement < TJM période précédente → pill rouge "-X€"
- [ ] Si TJM identique → pas de pill

**T06 — KPIs récap**
- [ ] Durée totale correcte (de debut[0] à fin[last])
- [ ] TJM moyen correct
- [ ] Marge moyenne correcte
- [ ] Compteur commentaires à jour après ajout

**T07 — Mission legacy sans période**
- [ ] Mission sans `date_debut` → section affiche "Aucune période enregistrée" + bouton "Créer la période initiale"

**T08 — Collapsible**
- [ ] Cliquer le header → section se réduit, chevron change
- [ ] Re-cliquer → section se ré-ouvre avec l'état précédent (formulaire fermé)

**T09 — Annuler**
- [ ] Ouvrir le formulaire → cliquer "Annuler" → formulaire disparaît, aucune donnée en base

**T10 — Droits**
- [ ] Tout commercial peut ajouter une période sur ses propres missions
- [ ] Admin peut ajouter sur toutes les missions
- [ ] En lecture seule (si applicable) → bouton "Renouveler" masqué

### 6.3 Tests de non-régression

- [ ] Le pipe charge correctement les `date_fin` et `tjm_vente` des missions modifiées
- [ ] Les calculs de marge dans les KPIs du dashboard utilisent bien les valeurs synchro
- [ ] L'export FSAP (si applicable) utilise la dernière période active
- [ ] Le badge GESTIONNAIRE (exploits) compte toujours correctement les missions actives

---

## 7. Acceptance criteria produit

- [ ] Un commercial peut renouveler une mission en < 30 secondes sans quitter le détail mission
- [ ] L'historique de toutes les périodes (TJM, dates, commandes) est visible d'un coup d'œil
- [ ] Chaque changement de conditions financières peut être documenté avec un commentaire
- [ ] Les données des missions existantes sont migrées sans perte
- [ ] Les KPIs du CRM (marge, CA, durée) restent cohérents après ajout de périodes

---

## 8. Hors scope V1

- Modification ou suppression d'une période existante (risque d'historique)
- Renouvellement partiel (changement de TJM en cours de période)
- Notification automatique au consultant lors d'un renouvellement
- Export PDF des périodes de mission
