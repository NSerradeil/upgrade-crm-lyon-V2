# BUG — Crash mobile CRM sur le compte Nicolas Serradeil
**CRM Upgrade Lyon V2** · Anomalie critique
**Date :** 03/04/2026
**Priorité :** HAUTE — utilisateur bloqué sur mobile

---

## Symptôme

L'application crash au chargement sur mobile Safari (iOS) avec le message :

> "Un problème récurrent est survenu sur « https://nserradeil.github.io/upgrade-crm-lyon-V2/ »."

Écran entièrement noir, aucun contenu ne s'affiche.

---

## Contexte clé

**Les autres commerciaux peuvent ouvrir le CRM normalement sur mobile.**

→ Ce n'est **pas** un bug de compatibilité mobile générale.
→ Le crash est **spécifique au compte / aux données de Nicolas Serradeil**.

---

## Hypothèses de cause (par probabilité décroissante)

### H1 — Volume de données trop important au chargement initial (très probable)
Le profil de Nicolas Serradeil est le compte admin / le plus ancien du CRM. Il concentre probablement le plus grand volume de données : contacts, tâches, historique d'actions, sessions de prospection, badges, etc.

Sur mobile Safari, la mémoire JS est limitée (~300-500 MB). Un `SELECT *` sans pagination sur une table volumineuse peut provoquer un OOM (Out Of Memory) silencieux qui crash le tab.

```js
// Requêtes à risque au mount :
sb.from('historique_actions').select('*')   // 1817 actions visibles dans le screenshot
sb.from('contacts').select('*')             // 246+ contacts
sb.from('taches').select('*')
sb.from('prospection_sessions').select('*')
```

**Fix :** Ajouter `.limit()` et pagination sur toutes les requêtes du chargement initial. Ne charger que les N derniers enregistrements nécessaires à l'affichage de la vue active.

### H2 — Calcul des badges (gamification) trop lourd
La fonction `loadAchievements()` agrège plusieurs tables pour calculer les scores de 15 badges × 4 niveaux. Sur un profil avec beaucoup de données, ce calcul peut saturer le thread JS sur mobile.

```js
// loadAchievements() exécute potentiellement 8-10 requêtes en parallèle
// sur des tables volumineuses — à profiler
```

**Fix :** Différer le calcul des badges après le premier rendu (lazy load, `useEffect` avec délai ou `requestIdleCallback`).

### H3 — JSON trop volumineux dans `profile.preferences`
Si `profile.preferences` contient des données accumulées (ex : `kanban_column_order` très long, ou des données de session stockées par erreur), le parse JSON au démarrage peut planter.

**Fix :** Vérifier la taille du JSON `preferences` en base pour l'utilisateur `nicolas.serradeil@upgrade.fr`.

```sql
SELECT length(preferences::text) FROM profiles WHERE email = 'nicolas.serradeil@upgrade.fr';
```

### H4 — localStorage corrompu ou saturé (Safari mobile)
Safari mobile impose une limite stricte sur le localStorage (~5MB). Si des données ont été accumulées (logs de session, cache de contacts, etc.), une écriture peut échouer silencieusement et provoquer un état incohérent qui crash l'app au prochain démarrage.

**Fix :** Ajouter un `try/catch` autour de toutes les lectures/écritures localStorage. Implémenter un mécanisme de reset du localStorage si le chargement échoue.

```js
const safeGetLocalStorage = (key) => {
  try { return localStorage.getItem(key); }
  catch (e) { console.warn('localStorage read failed:', e); return null; }
};
```

### H5 — Erreur JS non catchée spécifique au profil
Une donnée malformée dans le profil de Nicolas (ex : `displayed_badge` avec un format inattendu, `kanban_column_order` contenant un `null`, date invalide dans une mission) peut lever une exception non catchée qui crash le rendu React entier.

**Fix :** Wrapper le composant racine dans un `ErrorBoundary` React pour éviter le crash total et afficher un message d'erreur utile.

```jsx
class CRMErrorBoundary extends React.Component {
  state = { hasError: false, error: null };
  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }
  componentDidCatch(error, info) {
    console.error('CRM crash:', error, info);
    // Optionnel : envoyer à Sentry / log Supabase
  }
  render() {
    if (this.state.hasError) {
      return (
        <div style={{ padding: 32, color: '#111', fontFamily: 'sans-serif' }}>
          <h2>Une erreur est survenue</h2>
          <p>Essayez de vider le cache ou contactez l'administrateur.</p>
          <button onClick={() => localStorage.clear() && window.location.reload()}>
            Réinitialiser et recharger
          </button>
          <pre style={{ fontSize: 10, color: '#999', marginTop: 16 }}>
            {this.state.error?.toString()}
          </pre>
        </div>
      );
    }
    return this.props.children;
  }
}
```

---

## Plan de débogage recommandé

### Étape 1 — Identifier si c'est lié aux données du profil
Tester avec un autre compte sur le même mobile → si ça marche, confirme H1/H2/H3/H5.

### Étape 2 — Inspecter depuis Safari desktop (Web Inspector)
```
Safari desktop → Développement → [iPhone de Nicolas] → upgrade-crm-lyon-V2
→ Console → identifier l'erreur exacte et le stack trace
```

### Étape 3 — Vérifier le volume des données en base
```sql
-- Nombre d'actions historique pour Nicolas
SELECT COUNT(*) FROM historique_actions
JOIN contacts ON contacts.id = historique_actions.contact_id
WHERE contacts.responsable = 'Nicolas Serradeil';

-- Taille du JSON preferences
SELECT length(preferences::text) as prefs_size
FROM profiles WHERE email = 'nicolas.serradeil@upgrade.fr';
```

### Étape 4 — Tester le reset localStorage
Ouvrir le CRM en mode navigation privée sur le même mobile (localStorage vide) → si ça charge, confirme H4.

### Étape 5 — Ajouter l'ErrorBoundary en urgence
Même sans avoir trouvé la cause, l'ErrorBoundary doit être ajouté immédiatement pour remplacer l'écran noir par un message d'erreur lisible avec bouton de reset.

---

## Acceptance criteria du fix

- [ ] Le CRM se charge sur mobile Safari pour Nicolas Serradeil
- [ ] En cas d'erreur, un `ErrorBoundary` affiche un message lisible + bouton reset au lieu de l'écran noir
- [ ] Les requêtes au chargement initial ont toutes un `.limit()` ou une pagination
- [ ] Le calcul des badges est différé (lazy) et ne bloque pas le premier rendu
- [ ] `localStorage` est accédé uniquement dans des `try/catch`
- [ ] Aucune régression pour les autres commerciaux sur mobile

---

## Reproductibilité

| Environnement | Résultat |
|---|---|
| Mobile Safari iOS — compte Nicolas Serradeil | 💥 Crash écran noir |
| Mobile Safari iOS — autres commerciaux | ✅ Fonctionne |
| Desktop — compte Nicolas Serradeil | ✅ Fonctionne (supposé) |
