# SPEC — Ajout stat "Pas intéressés" dans le chart Historique Sessions
**CRM Upgrade Lyon V2** · Évolution feature
**Date :** 26/03/2026

---

## Contexte

Le chart "HISTORIQUE SESSIONS" dans la card KPI Prospection affiche actuellement deux métriques par mois :
- Nombre d'appelés (barres grises)
- % intéressés (texte au-dessus, en vert après fix `SPEC_chart_sessions_couleur_taux.md`)

Il manque la donnée **"Pas intéressés"** qui est maintenant trackée via `statut='not_interested'` dans `session_prospection_contacts`.

## Feature

### Donnée à afficher
- Comptage des contacts avec `statut = 'not_interested'` par mois, agrégé sur les sessions du mois
- Source : `session_prospection_contacts` jointure `sessions_prospection` (filtrer par mois de `date_session`)

### Affichage dans le chart

Deux options (choisir selon rendu visuel) :

**Option A — Texte sous la barre** (symétrique au % intéressés au-dessus)
```
  5% intéressés          ← au-dessus, vert #007A10
  ████████████           ← barre grise (nb appelés)
  8 pas intéressés       ← en dessous, rouge #FF3D2E, fontSize:10
```

**Option B — Barre empilée rouge** (stacked bar) — plus complexe, option secondaire.

Préférer **Option A** pour la simplicité d'implémentation.

### Style texte "pas intéressés"
```js
{
  fontSize: 10,
  color: '#FF3D2E',
  marginTop: 2,
  textAlign: 'center'
}
```

### Chargement de la donnée

```js
// À ajouter dans le fetch des stats sessions (probablement au mount de CardSessions)
const { count: nbNotInterested } = await sb
  .from('session_prospection_contacts')
  .select('id', { count: 'exact', head: true })
  .eq('statut', 'not_interested')
  .gte('created_at', debutMois)
  .lte('created_at', finMois);
```

Adapter selon la structure de données existante du chart (qui agrège probablement déjà par mois).

### Légende

Ajouter dans la légende du chart :
```
■ Appelés   ■ Intéressés   ■ Pas intéressés
(gris)      (vert)          (rouge)
```

## Dépendances

- Fix couleur intéressés (`SPEC_chart_sessions_couleur_taux.md`) doit être appliqué en même temps ou avant
- Nécessite que `statut='not_interested'` soit bien alimenté en base (OK après fix `BUG_prospection_post_session_edit_v2.md`)

## Acceptance criteria
- [ ] Chaque barre mensuelle affiche le nb de "pas intéressés" en rouge sous la barre
- [ ] La donnée est cohérente avec les sessions du mois correspondant
- [ ] La légende est mise à jour
- [ ] Pas de régression sur l'affichage actuel des barres et du % intéressés
