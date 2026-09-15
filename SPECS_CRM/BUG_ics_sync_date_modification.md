# BUG — Feed ICS : modification de date d'une tâche non reflétée dans le calendrier

**Date** : 26/03/2026
**Cas concret** : "Point de suivi mission Clément ROGIER — EDF" (id: t075)
- Date dans le CRM : **30/03/2026** ✅
- Date dans Apple Calendar (feed ICS) : **26/03/2026** ❌
- Délai depuis la modification : plusieurs jours
- "Actualiser" forcé dans Apple Calendar → aucun changement

---

## Cause probable

Le standard iCalendar (RFC 5545) exige que chaque événement modifié ait ses champs `SEQUENCE` et `LAST-MODIFIED` mis à jour pour que les clients calendar détectent le changement :

```
BEGIN:VEVENT
UID:t075@upgrade-crm
DTSTART:20260330T090000Z   ← date correcte
LAST-MODIFIED:20260320T...  ← ❌ date de création initiale, jamais mis à jour
SEQUENCE:0                  ← ❌ toujours 0, devrait s'incrémenter à chaque modif
END:VEVENT
```

Sans ces champs mis à jour, Apple Calendar considère que l'événement n'a pas changé et **ignore la nouvelle date**.

---

## Où chercher dans le code

Le feed ICS est généré par une fonction (Edge Function Supabase, endpoint, ou génération côté client). Chercher :

- Fichier : probablement `functions/ics/` ou `api/calendar` ou un endpoint `/ics` dans le code
- Mots-clés : `VEVENT`, `DTSTART`, `UID`, `SEQUENCE`, `LAST-MODIFIED`, `BEGIN:VCALENDAR`

---

## Fix

### 1. Ajouter `LAST-MODIFIED` dynamique

```
LAST-MODIFIED:${formatICSDate(task.updated_at || task.created_at)}
```

`updated_at` doit être mis à jour dans la table `taches` à chaque modification (trigger Supabase ou update explicite dans le code CRM).

### 2. Incrémenter `SEQUENCE`

Option A — Stocker `sequence` dans la table `taches` et l'incrémenter à chaque UPDATE :
```sql
-- À chaque update de due_date ou titre :
UPDATE taches SET sequence = COALESCE(sequence, 0) + 1, updated_at = now()
WHERE id = $1;
```

Option B — Calculer à la volée depuis `updated_at` (moins précis mais fonctionnel) :
```js
// Nombre de jours depuis la création = proxy du sequence
var sequence = Math.floor((new Date(task.updated_at) - new Date(task.created_at)) / 86400000);
```

### 3. S'assurer que `updated_at` est mis à jour partout

Dans le CRM, chaque fois qu'une tâche est modifiée (date, titre, statut), vérifier que le PATCH inclut :
```js
await sb.from('taches').update({
  due_date: newDate,
  updated_at: new Date().toISOString(),  // ← obligatoire
}).eq('id', taskId);
```

Si la table `taches` a un trigger `moddatetime` Supabase → c'est automatique. Sinon, l'ajouter manuellement dans chaque update du CRM.

### 4. Template VEVENT corrigé

```
BEGIN:VEVENT
UID:{task.id}@upgrade-crm-lyon
SUMMARY:{task.titre}
DTSTART;TZID=Europe/Paris:{formatDate(task.due_date)}T090000
DTEND;TZID=Europe/Paris:{formatDate(task.due_date)}T100000
DESCRIPTION:{task.notes || ''}
LAST-MODIFIED:{formatICSDate(task.updated_at)}   ← ✅ dynamique
SEQUENCE:{task.sequence || 0}                    ← ✅ incrémenté
STATUS:{task.statut === 'fait' ? 'COMPLETED' : 'CONFIRMED'}
END:VEVENT
```

---

## Vérification rapide

Pour confirmer que c'est bien le problème : inspecter le contenu brut du feed ICS.

Dans un terminal :
```bash
curl "URL_DU_FEED_ICS" | grep -A 20 "t075"
```

Si `LAST-MODIFIED` = date de création initiale et `SEQUENCE:0` → hypothèse confirmée.

---

## Priorité

P1 — La sync calendrier est au cœur de l'utilité du feed ICS. Sans ça, les modifications de dates ne remontent jamais sans supprimer/recréer l'abonnement.
