# SPEC — Bug : relances prospection invisibles dans l'onglet Tâches
**CRM Upgrade Lyon V2** · Bug P0
**Source :** Retour Anne-Claire Decker (commerciale Bordeaux) · 25/03/2026
**Auteur :** Nicolas Serradeil + Claude (PM + Lead Tech)

---

## Symptôme rapporté

> « Après avoir planifié une relance depuis l'onglet de prospection, celle-ci n'apparaît pas dans la liste des tâches. »

Anne-Claire termine une session de prospection avec des relances planifiées → la session se ferme, le toast de confirmation s'affiche → mais les relances sont introuvables dans l'onglet **Tâches**.

---

## Investigation — Analyse statique du code

### 1. Insertion des relances (`handleTerminer`, ligne ~5131)

```js
var relances = appeles.filter(sc3 => sc3.wantRelance && sc3.relanceDate);
if (relances.length > 0) {
  await sb.from('taches').insert(relances.map(sc4 => ({
    titre: `Relance ${sc4.prenom} ${sc4.nom} — ${sc4.groupe}`.trim(),
    statut: 'a_faire',
    due_date: sc4.relanceDate,          // format YYYY-MM-DD ← date input
    contact_id: sc4.id,
    session_prospection_id: session.id,
    notes: [...].join('\n'),
    responsable: profile.nom,           // ex. "Decker"
  })));
  // ⚠️ PAS de const {error} = ... → les erreurs Supabase sont ignorées silencieusement
}
```

**Problème #1 — Absence de gestion d'erreur :** si l'insert Supabase échoue (RLS, contrainte NOT NULL, colonne manquante), aucun feedback utilisateur. Le toast "Session terminée" s'affiche quand même. L'utilisateur croit que les relances ont été créées alors qu'elles ne l'ont pas été.

### 2. Rafraîchissement des données

Après `handleTerminer` :
```js
onDone(); // → setScreen('list') + loadSessions() + onRefresh() = fetchAll()
```
`fetchAll()` requête bien `taches.select('*')` sans filtre côté JS → si les relances sont en base, elles remontent.

### 3. Filtre frontend `vTaches`

```js
// ligne ~5557
const vTaches = activeIsAdmin ? taches : taches.filter(t => t.responsable === activeProfile.nom);
```

Pour une non-admin (Anne-Claire), seules les tâches avec `responsable === profile.nom` sont visibles. Les relances sont créées avec `responsable: profile.nom` → le filtre devrait matcher **si les relances sont en base**.

### 4. Conclusion de l'investigation

Le flux de création est correct côté logique. Les relances **devraient apparaître** une fois créées. Le fait qu'elles n'apparaissent pas pointe vers **un échec silencieux de l'insert Supabase**. Les causes possibles (sans accès au schéma Supabase) :

| Hypothèse | Probabilité | Vérification |
|---|---|---|
| RLS `taches` bloque l'INSERT pour les non-admins | Élevée | Vérifier les policies Supabase sur `taches` |
| Contrainte NOT NULL sur un champ non fourni | Moyenne | Vérifier schéma table `taches` |
| Timeout / erreur réseau | Faible | Ajouter error handling et observer |

---

## Fix — Deux niveaux

### Fix 1 (obligatoire) — Gestion d'erreur sur l'insert

Sans ce fix, tout diagnostic est impossible pour l'utilisateur final.

```js
// Avant
if (relances.length > 0) {
  await sb.from('taches').insert(relances.map(...));
}

// Après
if (relances.length > 0) {
  const { error: relanceErr } = await sb.from('taches').insert(relances.map(...));
  if (relanceErr) {
    toast('⚠️ Erreur création relances : ' + relanceErr.message, 'error');
    console.error('[Prospection] relances insert error:', relanceErr);
    // On ne bloque pas la fin de session, mais on alerte
  }
}
```

### Fix 2 (si RLS en cause) — Vérifier et corriger la policy Supabase

Si la RLS sur `taches` bloque l'INSERT pour les commerciaux non-admin :

```sql
-- Vérifier les policies actuelles
SELECT * FROM pg_policies WHERE tablename = 'taches';

-- Policy INSERT à ajouter/corriger si manquante
CREATE POLICY "taches_insert" ON taches
  FOR INSERT WITH CHECK (
    auth.role() = 'authenticated'
    -- ou : responsable = (SELECT nom FROM profiles WHERE id = auth.uid())
  );
```

### Fix 3 (complémentaire) — Badge visuel "Relance prosp." dans TabTaches

Pour que les relances issues de sessions soient facilement identifiables dans l'onglet Tâches, ajouter un badge distinctif sur les tâches avec `session_prospection_id IS NOT NULL`.

```jsx
// Dans le composant TacheCard / TacheRow
{task.session_prospection_id && (
  <span style={{
    fontSize: 9, fontWeight: 700, padding: '2px 6px',
    background: TAB_COLORS.prospection,  // #FF3D2E
    color: '#fff', borderRadius: 0, textTransform: 'uppercase',
    letterSpacing: '0.04em', marginLeft: 6
  }}>
    Prosp.
  </span>
)}
```

---

## Localisation dans le code

| Élément | Ligne approx. | Fichier |
|---|---|---|
| Insert relances (`handleTerminer`) | ~5131 | `CRM_Live.html` |
| Filtre `vTaches` frontend | ~5557 | `CRM_Live.html` |
| KPI Relances (card Prospection) | ~4714 | `CRM_Live.html` |
| Composant carte tâche | ~2050 | `CRM_Live.html` |

---

## Acceptance criteria

- [ ] Si l'insert Supabase échoue → toast d'erreur explicite avec le message Supabase
- [ ] Les relances créées en session apparaissent dans l'onglet Tâches après rafraîchissement
- [ ] Les relances de session sont visuellement marquées (badge "Prosp.") pour être distinguées des tâches manuelles
- [ ] Si la cause est RLS : la policy Supabase est documentée et validée avec Nicolas

---

## Ordre d'implémentation recommandé

1. **Immédiat :** Ajouter le `const { error: relanceErr }` + toast d'erreur (Fix 1) — 5 min, zéro risque
2. **Vérifier en prod :** Tester avec le compte Anne-Claire — si toast d'erreur apparaît → confirme l'hypothèse RLS
3. **Si RLS :** Ajouter la policy Supabase (Fix 2)
4. **UX :** Ajouter le badge "Prosp." sur les tâches de session (Fix 3)
