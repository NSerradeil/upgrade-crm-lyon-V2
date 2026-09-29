# Pipeline des prospects — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Donner un cycle de vie au contact de statut `Prospect` — une étape, une prochaine action datée, une vue kanban — en clonant le pattern éprouvé des Besoins.

**Architecture:** Toute la logique décidable (validations, mapping, calcul de retard, échéance de tâche) vit dans des **fonctions pures nommées, déclarées au niveau racine d'`index.html`**, extractibles par `tests/*.test.mjs` selon la méthode maison (`tests/seq-parcours.test.mjs`). Les composants React les consomment sans jamais redécider. Le MCP importe la même logique de validation, réécrite une fois dans `server/prospect-rules.mjs` et testée à part, pour que le garde-fou ne dépende pas de l'écran.

**Tech Stack:** `index.html` mono-fichier (React via Babel navigateur, pas de build), Supabase JS direct, migrations SQL manuelles dans `db/`, tests `node --test` sur `.mjs`, MCP en ESM (`upgrade-crm-mcp-src/server/index.mjs`) packagé en `.mcpb`.

**Spec:** `SPECS_CRM/SPEC_prospects_pipeline_etapes.md`

## Global Constraints

- **Mono-fichier :** toute l'UI vit dans `index.html`. Pas de nouveau fichier JS côté app, pas de bundler, pas d'import ES. Les fonctions sont déclarées au niveau racine du `<script type="text/babel">`.
- **Pas d'écran blanc :** `bin/pre-push.sh` refuse le push si `node tests/check-babel.mjs` échoue. Une erreur JSX casse **toute** l'application en production. Exécuter ce check avant chaque commit touchant `index.html`.
- **Style brutaliste :** `borderRadius:0`, `boxShadow:'4px 4px 0 '+couleur`, `fontFamily:'Outfit,sans-serif'`, `textTransform:'uppercase'`, `letterSpacing:'0.03em'`.
- **Egress Supabase :** `select` ciblé uniquement. Toute colonne ajoutée doit l'être au select principal des contacts (`index.html:11573`) et exister réellement en base avant le push.
- **Migrations :** `db/NN_snake_case.sql`, idempotentes (`add column if not exists`), en-tête Date + Spec, appliquées à la main. Dernier numéro utilisé : **50**.
- **Zéro tiret cadratin** dans les libellés visibles par l'utilisateur.
- **Nommage des étapes, valeurs exactes :** `À contacter`, `Contacté`, `En discussion`, `RDV planifié`, `Qualifié`, `En veille`, `Perdu`, `Ne pas recontacter`.
- **Heure par défaut des tâches créées :** `09:00`.
- **MCP :** version cible `8.26.0` dans `manifest.json` ET dans le changelog de la description serveur (`server/index.mjs:452`).

## Review Focus

Cinq failles que la spec implique sans qu'aucune tâche ne les exerce spontanément. Chaque ligne a son test rattaché à la tâche qui possède le code.

1. **Un prospect sans `etape_prospect`** (créé par le MCP d'une ancienne version, ou par un import) ne doit ni crasher le board ni disparaître : il est traité comme « À contacter ». → Tâche 1, `prospectEtapeOuDefaut`.
2. **Une date de réveil dans le passé** saisie à la main (erreur de frappe, `2025` au lieu de `2026`) ne doit pas rendre la carte invisible : elle compte comme retard, pas comme date ignorée. → Tâche 1, test `prospectEnRetard` sur date très ancienne.
3. **Un contact en étape de sortie qui repasse en `À contacter`** doit voir sa `prochaine_action_date` et son `motif_perte` nettoyés, sinon il traîne un motif de perte périmé qui s'affichera plus tard. → Tâche 3, test `prospectPatchEtape`.
4. **Deux onglets ouverts sur le même prospect** : le second écrit par-dessus le premier sans le savoir. La garde anti-doublon de tâche doit être évaluée sur les données fraîches, pas sur le state React. → Tâche 4, la vérification interroge Supabase et non le tableau `taches` en mémoire.
5. **Le MCP appelé avec une étape inconnue** (faute de frappe de Jules, casse ou accent absent : `qualifie`, `RDV Planifie`) doit être refusé avec la liste des valeurs admises, pas écrire une étape fantôme qui n'apparaîtra dans aucune colonne. → Tâche 11, test `valideEtapeProspect`.

---

## File Structure

| Fichier | Responsabilité | Action |
|---|---|---|
| `db/51_contacts_etape_prospect.sql` | Colonnes, index, backfill, reprise du flag | Créer |
| `db/52_drop_ne_pas_recontacter.sql` | Suppression différée du flag | Créer (non appliquée) |
| `index.html` (racine du script) | Constantes + fonctions pures du pipeline | Modifier |
| `index.html` `ContactDetail` (2114) | Stepper + micro-formulaire | Modifier |
| `index.html` `TabProspects` (3756) | Toggle, colonnes liste, tri, kanban | Modifier |
| `index.html` `ProspectsKanban` | Board 5 colonnes + 3 sorties repliées | Créer (dans le fichier) |
| `index.html` `TabProspection` (11436) | Mapping fin de session vers étape | Modifier |
| `tests/prospect-pipeline.test.mjs` | Tests des fonctions pures extraites | Créer |
| `upgrade-crm-mcp-src/server/prospect-rules.mjs` | Validation partagée, testable seule | Créer |
| `upgrade-crm-mcp-src/tests/prospect-rules.test.mjs` | Tests de la validation | Créer |
| `upgrade-crm-mcp-src/server/index.mjs` | Outils contacts + `crm_prospects_due_today` | Modifier |
| `upgrade-crm-mcp-src/manifest.json` | Bump 8.26.0 | Modifier |

**Pourquoi la validation est écrite deux fois** (une en fonction pure dans `index.html`, une dans `prospect-rules.mjs`) : les deux exécutables n'ont aucun chemin d'import commun — l'app est un HTML compilé dans le navigateur, le MCP un module Node. Les mutualiser demanderait un build que ce repo n'a pas. Le test de la tâche 11 verrouille l'équivalence en rejouant **les mêmes cas** des deux côtés.

---

### Task 1: Logique pure du pipeline

Le socle. Aucune UI, aucun appel réseau. Tout ce qui décide vit ici.

**Files:**
- Modify: `index.html` (déclarations racine, juste après `STATUTS_CONTACT` ligne 215)
- Test: `tests/prospect-pipeline.test.mjs` (créer)

**Interfaces:**
- Consumes: rien.
- Produces:
  - `PROSPECT_ETAPES: string[]` (les 8, dans l'ordre)
  - `PROSPECT_ETAPES_ACTIVES: string[]` (les 5)
  - `PROSPECT_ETAPES_SORTIE: string[]` (les 3)
  - `PROSPECT_MOTIFS_PERTE: string[]`
  - `PROSPECT_BADGE_COLORS: {[etape]: {bg, color}}`
  - `prospectEtapeOuDefaut(contact) -> string`
  - `prospectEtapeRequiert(etape) -> {date: bool, motif: bool, commentaire: bool}`
  - `prospectCanSubmit(etape, form) -> bool`
  - `prospectEnRetard(contact, now) -> bool`
  - `prospectTacheLibelle(etape) -> string`
  - `prospectTacheEcheance(dateISO) -> string` (ISO, heure forcée à 09:00 si absente)
  - `prospectReveilPreset(base, preset) -> string` (`'3m' | '6m' | '1a'`, retourne `YYYY-MM-DD`)

- [ ] **Step 1: Écrire le test qui échoue**

Créer `tests/prospect-pipeline.test.mjs` :

```javascript
// tests/prospect-pipeline.test.mjs — la logique pure du pipeline prospect.
// Les fonctions sont extraites d'index.html (mono-fichier, pas de module) — même méthode
// que tests/seq-parcours.test.mjs : on teste le code qui tourne vraiment, pas une copie.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nconst ${nom} = [^\\n]*;\\n`),
                    new RegExp(`\\nconst ${nom} = \\{[\\s\\S]*?\\n\\};\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['PROSPECT_ETAPES', 'PROSPECT_ETAPES_ACTIVES', 'PROSPECT_ETAPES_SORTIE',
              'PROSPECT_MOTIFS_PERTE', 'prospectEtapeOuDefaut', 'prospectEtapeRequiert',
              'prospectCanSubmit', 'prospectEnRetard', 'prospectTacheLibelle',
              'prospectTacheEcheance', 'prospectReveilPreset'];
const src = NOMS.map(extrait).join('\n');
const API = new Function(`${src}\nreturn {${NOMS.join(',')}};`)();
const { PROSPECT_ETAPES, PROSPECT_ETAPES_ACTIVES, PROSPECT_ETAPES_SORTIE,
        prospectEtapeOuDefaut, prospectEtapeRequiert, prospectCanSubmit,
        prospectEnRetard, prospectTacheLibelle, prospectTacheEcheance,
        prospectReveilPreset } = API;

test('les 8 etapes, dans l ordre, avec les accents exacts', () => {
  assert.deepEqual(PROSPECT_ETAPES, ['À contacter', 'Contacté', 'En discussion',
    'RDV planifié', 'Qualifié', 'En veille', 'Perdu', 'Ne pas recontacter']);
  assert.equal(PROSPECT_ETAPES_ACTIVES.length, 5);
  assert.equal(PROSPECT_ETAPES_SORTIE.length, 3);
  // actives + sorties recouvrent exactement l'ensemble, sans doublon
  assert.deepEqual([...PROSPECT_ETAPES_ACTIVES, ...PROSPECT_ETAPES_SORTIE].sort(),
                   [...PROSPECT_ETAPES].sort());
});

test('REVIEW FOCUS 1 — un prospect sans etape est traite comme « A contacter »', () => {
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect' }), 'À contacter');
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect', etape_prospect: null }), 'À contacter');
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect', etape_prospect: '' }), 'À contacter');
  assert.equal(prospectEtapeOuDefaut({ statut: 'Prospect', etape_prospect: 'Perdu' }), 'Perdu');
});

test('les etapes actives exigent une date, « A contacter » non', () => {
  assert.equal(prospectEtapeRequiert('À contacter').date, false);
  for (const e of ['Contacté', 'En discussion', 'RDV planifié', 'Qualifié']) {
    assert.equal(prospectEtapeRequiert(e).date, true, e);
  }
  assert.equal(prospectEtapeRequiert('En veille').date, true);   // date de reveil
  assert.equal(prospectEtapeRequiert('Perdu').motif, true);
  assert.equal(prospectEtapeRequiert('Perdu').date, false);
  assert.equal(prospectEtapeRequiert('Ne pas recontacter').commentaire, true);
});

test('canSubmit bloque tant que l obligatoire manque', () => {
  assert.equal(prospectCanSubmit('Contacté', {}), false);
  assert.equal(prospectCanSubmit('Contacté', { prochaine_action_date: '2026-10-05' }), true);
  assert.equal(prospectCanSubmit('Perdu', {}), false);
  assert.equal(prospectCanSubmit('Perdu', { motif_perte: 'Pas de besoin' }), true);
  assert.equal(prospectCanSubmit('À contacter', {}), true);
  assert.equal(prospectCanSubmit('Ne pas recontacter', {}), false);
  assert.equal(prospectCanSubmit('Ne pas recontacter', { motif_perte_precision: 'a demande' }), true);
});

test('REVIEW FOCUS 2 — une date de reveil dans le passe compte comme retard', () => {
  const now = new Date('2026-09-29T10:00:00Z');
  assert.equal(prospectEnRetard({ prochaine_action_date: '2025-01-01T09:00:00Z' }, now), true);
  assert.equal(prospectEnRetard({ prochaine_action_date: '2026-09-28T09:00:00Z' }, now), true);
  assert.equal(prospectEnRetard({ prochaine_action_date: '2026-12-01T09:00:00Z' }, now), false);
  assert.equal(prospectEnRetard({ prochaine_action_date: null }, now), false);
  assert.equal(prospectEnRetard({}, now), false);
});

test('l echeance de tache est forcee a 09h00 quand l heure est absente', () => {
  assert.match(prospectTacheEcheance('2026-10-05'), /^2026-10-05T09:00/);
  assert.match(prospectTacheEcheance('2026-10-05T14:30'), /^2026-10-05T14:30/);
});

test('le libelle de tache est pre-rempli depuis l etape visee', () => {
  assert.equal(prospectTacheLibelle('En veille'), 'Réveil prospect');
  assert.equal(prospectTacheLibelle('Contacté'), 'Rappeler');
  assert.equal(prospectTacheLibelle('RDV planifié'), 'RDV prospect');
  assert.ok(prospectTacheLibelle('Qualifié').length > 0);
  // Aucun libelle ne contient de tiret cadratin (marqueur IA, regle maison).
  for (const e of PROSPECT_ETAPES) assert.ok(!/[—–]/.test(prospectTacheLibelle(e)), e);
});

test('les presets de reveil tombent a 3 mois, 6 mois, 1 an', () => {
  assert.equal(prospectReveilPreset('2026-09-29', '3m'), '2026-12-29');
  assert.equal(prospectReveilPreset('2026-09-29', '6m'), '2027-03-29');
  assert.equal(prospectReveilPreset('2026-09-29', '1a'), '2027-09-29');
  // fin de mois : le 31 aout + 6 mois ne doit pas deborder sur mars
  assert.equal(prospectReveilPreset('2026-08-31', '6m'), '2027-02-28');
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `node --test tests/prospect-pipeline.test.mjs`
Expected: FAIL avec `PROSPECT_ETAPES introuvable dans index.html`

- [ ] **Step 3: Écrire l'implémentation minimale**

Dans `index.html`, juste après la ligne 215 (`const STATUTS_CONTACT = [...]`), insérer au niveau racine :

```javascript
// ═══ Pipeline prospect — cf. SPECS_CRM/SPEC_prospects_pipeline_etapes.md ═══
const PROSPECT_ETAPES_ACTIVES = ['À contacter','Contacté','En discussion','RDV planifié','Qualifié'];
const PROSPECT_ETAPES_SORTIE = ['En veille','Perdu','Ne pas recontacter'];
const PROSPECT_ETAPES = ['À contacter','Contacté','En discussion','RDV planifié','Qualifié','En veille','Perdu','Ne pas recontacter'];
const PROSPECT_MOTIFS_PERTE = ['Budget insuffisant','Pas le bon interlocuteur','Pas de besoin','Choix concurrent','Perdu de vue','Autre'];
const PROSPECT_BADGE_COLORS = {
  'À contacter':       { bg:'#E4E4E6', color:'#1C1F35' },
  'Contacté':          { bg:'#FFE500', color:'#1C1F35' },
  'En discussion':     { bg:'#5090FE', color:'#FFFFFF' },
  'RDV planifié':      { bg:'#8B5CF6', color:'#FFFFFF' },
  'Qualifié':          { bg:'#00C218', color:'#1C1F35' },
  'En veille':         { bg:'#A4A6AB', color:'#FFFFFF' },
  'Perdu':             { bg:'#FF6B6B', color:'#FFFFFF' },
  'Ne pas recontacter':{ bg:'#1C1F35', color:'#FFFFFF' }
};

function prospectEtapeOuDefaut(contact) {
  var e = contact && contact.etape_prospect;
  return (e && PROSPECT_ETAPES.indexOf(e) >= 0) ? e : 'À contacter';
}

function prospectEtapeRequiert(etape) {
  return {
    date: etape === 'En veille' || (PROSPECT_ETAPES_ACTIVES.indexOf(etape) > 0),
    motif: etape === 'Perdu',
    commentaire: etape === 'Ne pas recontacter'
  };
}

function prospectCanSubmit(etape, form) {
  var r = prospectEtapeRequiert(etape); form = form || {};
  if (r.date && !form.prochaine_action_date) return false;
  if (r.motif && !form.motif_perte) return false;
  if (r.commentaire && !form.motif_perte_precision) return false;
  return true;
}

function prospectEnRetard(contact, now) {
  var d = contact && contact.prochaine_action_date;
  if (!d) return false;
  var t = new Date(d).getTime();
  if (isNaN(t)) return false;
  return t <= (now ? new Date(now).getTime() : Date.now());
}

function prospectTacheLibelle(etape) {
  var L = { 'Contacté':'Rappeler', 'En discussion':'Relancer', 'RDV planifié':'RDV prospect',
            'Qualifié':'Qualifier le besoin', 'En veille':'Réveil prospect',
            'À contacter':'Premier contact', 'Perdu':'Suivi prospect',
            'Ne pas recontacter':'Suivi prospect' };
  return L[etape] || 'Suivi prospect';
}

function prospectTacheEcheance(dateISO) {
  if (!dateISO) return null;
  return dateISO.length > 10 ? dateISO : (dateISO + 'T09:00');
}

function prospectReveilPreset(base, preset) {
  var d = new Date(base + 'T12:00:00Z');
  var jour = d.getUTCDate();
  var mois = { '3m':3, '6m':6, '1a':12 }[preset] || 3;
  d.setUTCDate(1);
  d.setUTCMonth(d.getUTCMonth() + mois);
  // Fin de mois : on retombe sur le dernier jour reel du mois cible (31 aout + 6 mois = 28 fev).
  var dernier = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate();
  d.setUTCDate(Math.min(jour, dernier));
  return d.toISOString().slice(0, 10);
}
```

- [ ] **Step 4: Lancer les tests pour vérifier qu'ils passent**

Run: `node --test tests/prospect-pipeline.test.mjs`
Expected: PASS, 8 tests

- [ ] **Step 5: Vérifier que l'app compile toujours**

Run: `node tests/check-babel.mjs`
Expected: sortie vide, code 0

- [ ] **Step 6: Commit**

```bash
git add tests/prospect-pipeline.test.mjs index.html
git commit -m "feat(prospects): logique pure du pipeline d etapes"
```

---

### Task 2: Migration 51 et chargement des colonnes

**Files:**
- Create: `db/51_contacts_etape_prospect.sql`
- Create: `db/52_drop_ne_pas_recontacter.sql` (écrite maintenant, **appliquée plus tard**)
- Modify: `index.html:11573` (select principal des contacts)

**Interfaces:**
- Consumes: rien.
- Produces: les contacts chargés dans l'app portent `etape_prospect`, `prochaine_action_date`, `prochaine_action_libelle`, `motif_perte`, `motif_perte_precision`.

- [ ] **Step 1: Écrire la migration 51**

Créer `db/51_contacts_etape_prospect.sql` avec le contenu exact du bloc SQL de la spec, section « Modèle de données ».

- [ ] **Step 2: Écrire la migration 52, sans l'appliquer**

Créer `db/52_drop_ne_pas_recontacter.sql` :

```sql
-- SPEC_prospects_pipeline_etapes.md — differee d une semaine apres la 51.
-- NE PAS APPLIQUER avant d avoir verifie qu aucun contact NPC n a ete perdu :
--   select count(*) from contacts c where c.ne_pas_recontacter = true
--     and c.etape_prospect is distinct from 'Ne pas recontacter'
--     and not exists (select 1 from historique_actions h
--                     where h.id_prospect = c.id and h.type_action = 'Changement d''étape');
--   -- doit retourner 0 (voir db/52 : les contacts levés depuis la mise en service sont ignorés)
alter table contacts drop column if exists ne_pas_recontacter;
alter table contacts drop column if exists ne_pas_recontacter_note;
alter table contacts drop column if exists ne_pas_recontacter_date;
```

- [ ] **Step 3: Appliquer la 51 en base et vérifier le backfill**

Appliquer `db/51_contacts_etape_prospect.sql` dans l'éditeur SQL Supabase, puis vérifier :

```sql
select etape_prospect, count(*) from contacts where statut = 'Prospect' group by 1 order by 2 desc;
select count(*) from contacts where statut = 'Prospect' and etape_prospect is null;  -- doit valoir 0
select count(*) from contacts where ne_pas_recontacter = true
  and etape_prospect is distinct from 'Ne pas recontacter';                          -- doit valoir 0
```

Expected: toutes les lignes ont une étape ; les deux compteurs de contrôle valent 0.

- [ ] **Step 4: Ajouter les colonnes au select**

Dans `index.html:11573`, ajouter à la liste des colonnes du select contacts (et, dans le commit final de la branche, retirer `ne_pas_recontacter`, `ne_pas_recontacter_note`, `ne_pas_recontacter_date` : plus rien ne les lit) :

```
,etape_prospect,prochaine_action_date,prochaine_action_libelle,motif_perte,motif_perte_precision
```

- [ ] **Step 5: Vérifier en conditions réelles**

Ouvrir l'app, console navigateur, vérifier qu'aucune erreur `column ... does not exist` n'apparaît et qu'un contact prospect porte bien `etape_prospect`.

- [ ] **Step 6: Commit**

```bash
node tests/check-babel.mjs
git add db/51_contacts_etape_prospect.sql db/52_drop_ne_pas_recontacter.sql index.html
git commit -m "feat(prospects): migration 51, colonnes d etape chargees dans l app"
```

---

### Task 3: Calcul du patch d'étape

La fonction qui transforme « étape visée + formulaire » en patch Supabase. Isolée de l'UI pour être testable, et parce que c'est là que se cachent les fuites de données périmées.

**Files:**
- Modify: `index.html` (après les fonctions de la tâche 1)
- Test: `tests/prospect-pipeline.test.mjs` (ajouter)

**Interfaces:**
- Consumes: `prospectEtapeRequiert`, `prospectTacheEcheance` (Tâche 1).
- Produces: `prospectPatchEtape(etape, form) -> object` — le patch à passer à `sb.from('contacts').update(...)`.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter `prospectPatchEtape` à la liste `NOMS` du fichier de test, puis ajouter :

```javascript
test('le patch porte la date et le libelle pour une etape active', () => {
  const p = prospectPatchEtape('Contacté', { prochaine_action_date: '2026-10-05',
                                             prochaine_action_libelle: 'Rappeler le matin' });
  assert.equal(p.etape_prospect, 'Contacté');
  assert.match(p.prochaine_action_date, /^2026-10-05T09:00/);
  assert.equal(p.prochaine_action_libelle, 'Rappeler le matin');
  assert.equal(p.motif_perte, null);
});

test('le patch d une perte porte le motif et efface la prochaine action', () => {
  const p = prospectPatchEtape('Perdu', { motif_perte: 'Choix concurrent', motif_perte_precision: 'Devoteam' });
  assert.equal(p.etape_prospect, 'Perdu');
  assert.equal(p.motif_perte, 'Choix concurrent');
  assert.equal(p.motif_perte_precision, 'Devoteam');
  assert.equal(p.prochaine_action_date, null);
  assert.equal(p.prochaine_action_libelle, null);
});

test('REVIEW FOCUS 3 — revenir en « A contacter » nettoie motif et action periemes', () => {
  const p = prospectPatchEtape('À contacter', {});
  assert.equal(p.etape_prospect, 'À contacter');
  assert.equal(p.motif_perte, null);
  assert.equal(p.motif_perte_precision, null);
  assert.equal(p.prochaine_action_date, null);
  assert.equal(p.prochaine_action_libelle, null);
});

test('le patch de mise en veille porte la date de reveil comme prochaine action', () => {
  const p = prospectPatchEtape('En veille', { prochaine_action_date: '2027-03-29' });
  assert.match(p.prochaine_action_date, /^2027-03-29T09:00/);
  assert.equal(p.prochaine_action_libelle, 'Réveil prospect');
});

test('le patch porte toujours updated_at', () => {
  assert.ok(prospectPatchEtape('À contacter', {}).updated_at);
});
```

- [ ] **Step 2: Lancer le test pour vérifier qu'il échoue**

Run: `node --test tests/prospect-pipeline.test.mjs`
Expected: FAIL, `prospectPatchEtape introuvable dans index.html`

- [ ] **Step 3: Écrire l'implémentation**

```javascript
function prospectPatchEtape(etape, form) {
  form = form || {};
  var r = prospectEtapeRequiert(etape);
  var garde = r.date;   // seules les etapes qui exigent une date la conservent
  return {
    etape_prospect: etape,
    prochaine_action_date: garde ? prospectTacheEcheance(form.prochaine_action_date) : null,
    prochaine_action_libelle: garde
      ? (form.prochaine_action_libelle || prospectTacheLibelle(etape))
      : null,
    motif_perte: etape === 'Perdu' ? (form.motif_perte || null) : null,
    motif_perte_precision: (etape === 'Perdu' || etape === 'Ne pas recontacter')
      ? (form.motif_perte_precision || null) : null,
    updated_at: new Date().toISOString()
  };
}
```

- [ ] **Step 4: Lancer les tests**

Run: `node --test tests/prospect-pipeline.test.mjs`
Expected: PASS, 13 tests

- [ ] **Step 5: Commit**

```bash
node tests/check-babel.mjs
git add index.html tests/prospect-pipeline.test.mjs
git commit -m "feat(prospects): calcul du patch d etape, nettoyage des champs periemes"
```

---

### Task 4: Stepper et micro-formulaire sur la fiche contact

Premier morceau visible. Un prospect peut changer d'étape depuis sa fiche.

**Files:**
- Modify: `index.html` `ContactDetail` (2114) — insertion du stepper en tête
- Modify: `index.html` — deux composants créés juste avant `ContactDetail`

**Interfaces:**
- Consumes: `PROSPECT_ETAPES`, `PROSPECT_BADGE_COLORS`, `prospectEtapeOuDefaut`, `prospectCanSubmit`, `prospectPatchEtape`, `prospectReveilPreset`, `prospectTacheLibelle`.
- Produces:
  - `<ProspectStatusStepper contact onEtapeClick={(etape) => void} />`
  - `<ProspectMicroForm targetEtape contact onConfirm={(etape, form) => Promise} onCancel saving />`

- [ ] **Step 1: Écrire `ProspectStatusStepper`**

Cloner `BesoinStatusStepper2` (index.html:5432), en l'insérant juste avant `function ContactDetail` :

```javascript
// Stepper d'etape prospect — clone de BesoinStatusStepper2 (ligne 5432).
// Toutes les etapes sont contextuelles ici : meme « À contacter » passe par le
// micro-formulaire, pour nettoyer motif et action periemes (cf. prospectPatchEtape).
function ProspectStatusStepper({ contact, onEtapeClick }) {
  var courante = prospectEtapeOuDefaut(contact);
  var idx = PROSPECT_ETAPES.indexOf(courante);
  return (
    <div style={{display:'flex',gap:4,flexWrap:'wrap',padding:'8px 0'}}>
      {PROSPECT_ETAPES.map(function(e, i){
        var isCurrent = e === courante;
        var bc = PROSPECT_BADGE_COLORS[e] || {bg:'#E4E4E6',color:'#1C1F35'};
        return <button key={e} onClick={function(){ if(!isCurrent) onEtapeClick(e); }} style={{
          padding:'4px 10px',fontSize:10,fontWeight:isCurrent?900:700,
          background:isCurrent?'#1C1F35':'#fff',
          color:isCurrent?'#fff':'#1C1F35',
          border:isCurrent?'0':'1px solid #E4E4E6',
          boxShadow:isCurrent?'3px 3px 0 '+bc.bg:'none',
          transform:isCurrent?'translate(-1px,-1px)':'none',
          cursor:isCurrent?'default':'pointer',
          borderRadius:0,textTransform:'uppercase',letterSpacing:'0.03em',
          transition:'all 80ms',fontFamily:'Outfit,sans-serif',
          opacity:PROSPECT_ETAPES_SORTIE.indexOf(e)>=0&&!isCurrent?0.6:1
        }}>{e}</button>;
      })}
    </div>
  );
}
```

- [ ] **Step 2: Écrire `ProspectMicroForm`**

Cloner `BesoinMicroForm` (index.html:5464) :

```javascript
// Micro-formulaire contextuel de changement d'etape — clone de BesoinMicroForm (5464).
function ProspectMicroForm({ targetEtape, contact, onConfirm, onCancel, saving }) {
  var [formData, setFormData] = useState({
    prochaine_action_libelle: prospectTacheLibelle(targetEtape),
    creer_tache: true
  });
  var upd = function(k,v){setFormData(function(p){var n={};for(var x in p)n[x]=p[x];n[k]=v;return n;});};
  var bc = PROSPECT_BADGE_COLORS[targetEtape]||{bg:'#E4E4E6'};
  var r = prospectEtapeRequiert(targetEtape);
  var canSubmit = prospectCanSubmit(targetEtape, formData);
  var aujourdhui = new Date().toISOString().slice(0,10);

  return (
    <div style={{border:'2px solid #1C1F35',boxShadow:'4px 4px 0 '+bc.bg,background:'#FAFAFA',padding:16,margin:'8px 0',borderRadius:0}}>
      <div style={{fontSize:12,fontWeight:800,color:'#1C1F35',textTransform:'uppercase',marginBottom:12}}>Passage à : {targetEtape}</div>

      {targetEtape==='En veille'&&<>
        <Field label="Date de réveil *">
          <div style={{display:'flex',gap:6,marginBottom:6}}>
            {[['3m','3 mois'],['6m','6 mois'],['1a','1 an']].map(function(p){
              return <button key={p[0]} onClick={function(){upd('prochaine_action_date',prospectReveilPreset(aujourdhui,p[0]));}}
                style={{padding:'4px 10px',fontSize:10,fontWeight:700,border:'1px solid #E4E4E6',background:'#fff',borderRadius:0,cursor:'pointer',textTransform:'uppercase'}}>{p[1]}</button>;
            })}
          </div>
          <input type="date" value={formData.prochaine_action_date||''} onChange={function(e){upd('prochaine_action_date',e.target.value);}} className={inputCls}/>
        </Field>
        <Field label="Commentaire"><textarea value={formData.motif_perte_precision||''} onChange={function(e){upd('motif_perte_precision',e.target.value);}} rows={2} className={inputCls+' resize-none'}/></Field>
      </>}

      {r.date&&targetEtape!=='En veille'&&<>
        <Field label={targetEtape==='RDV planifié'?'Date du RDV *':'Prochaine action, date *'}>
          <input type="datetime-local" value={formData.prochaine_action_date||''} onChange={function(e){upd('prochaine_action_date',e.target.value);}} className={inputCls}/>
        </Field>
        <Field label="Prochaine action, libellé">
          <input value={formData.prochaine_action_libelle||''} onChange={function(e){upd('prochaine_action_libelle',e.target.value);}} className={inputCls}/>
        </Field>
      </>}

      {targetEtape==='Perdu'&&<>
        <Field label="Motif *"><select value={formData.motif_perte||''} onChange={function(e){upd('motif_perte',e.target.value);}} className={inputCls}>
          <option value="">— Choisir —</option>
          {PROSPECT_MOTIFS_PERTE.map(function(m){return <option key={m}>{m}</option>;})}
        </select></Field>
        <Field label="Commentaire"><textarea value={formData.motif_perte_precision||''} onChange={function(e){upd('motif_perte_precision',e.target.value);}} rows={2} className={inputCls+' resize-none'}/></Field>
      </>}

      {targetEtape==='Ne pas recontacter'&&<>
        <Field label="Détail *"><textarea value={formData.motif_perte_precision||''} onChange={function(e){upd('motif_perte_precision',e.target.value);}} placeholder="Ce que la personne a demandé, et quand." rows={2} className={inputCls+' resize-none'}/></Field>
      </>}

      {r.date&&<label style={{display:'flex',alignItems:'center',gap:6,fontSize:11,marginTop:8,cursor:'pointer'}}>
        <input type="checkbox" checked={!!formData.creer_tache} onChange={function(e){upd('creer_tache',e.target.checked);}}/>
        Créer la tâche CRM correspondante
      </label>}

      <div style={{display:'flex',gap:8,marginTop:12}}>
        <BtnAction variant="primary" label={saving?'...':'Confirmer'} onClick={function(){onConfirm(targetEtape,formData);}} disabled={saving||!canSubmit}/>
        <button onClick={onCancel} style={{fontSize:11,color:'#999',background:'none',border:'none',cursor:'pointer',textTransform:'uppercase'}}>Annuler</button>
      </div>
    </div>
  );
}
```

- [ ] **Step 3: Brancher dans `ContactDetail`**

Dans `ContactDetail` (index.html:2114), ajouter l'état puis le rendu en tête de panneau, visible seulement pour un prospect :

```javascript
const [etapeCible,setEtapeCible]=useState(null);
const [etapeSaving,setEtapeSaving]=useState(false);
```

Puis, juste après le bloc de la bannière (ligne ~2161) :

```jsx
{contact.statut==='Prospect'&&<>
  <ProspectStatusStepper contact={contact} onEtapeClick={setEtapeCible}/>
  {etapeCible&&<ProspectMicroForm targetEtape={etapeCible} contact={contact} saving={etapeSaving}
    onCancel={()=>setEtapeCible(null)}
    onConfirm={handleEtapeConfirm}/>}
</>}
```

- [ ] **Step 4: Écrire `handleEtapeConfirm` (sans la tâche, qui vient en Tâche 5)**

```javascript
const handleEtapeConfirm=async(etape,form)=>{
  setEtapeSaving(true);
  const patch=prospectPatchEtape(etape,form);
  const {error}=await sb.from('contacts').update(patch).eq('id',contact.id);
  if(error){toast('Erreur: '+error.message,'error');setEtapeSaving(false);return;}
  await sb.from('historique_actions').insert({id_prospect:contact.id,date:getToday(),
    type_action:'Changement d\'étape',details:`Étape → ${etape}`,responsable:profile.nom});
  toast('Étape → '+etape);
  setEtapeCible(null);setEtapeSaving(false);onRefresh();
};
```

- [ ] **Step 5: Vérifier la compilation puis recetter à la main**

Run: `node tests/check-babel.mjs`
Expected: code 0.

Puis, dans l'app : ouvrir un contact Prospect, le stepper apparaît. Cliquer « Contacté » : le micro-formulaire s'ouvre, Confirmer est désactivé tant qu'aucune date n'est saisie. Saisir une date, confirmer : le stepper se met à jour, l'historique porte la ligne. Ouvrir un contact Client : aucun stepper.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat(prospects): stepper et micro-formulaire d etape sur la fiche contact"
```

---

### Task 5: Création de la tâche CRM, avec garde anti-doublon

**Files:**
- Modify: `index.html` `ContactDetail` — `handleEtapeConfirm`
- Modify: `index.html` — fonction pure `prospectTachePayload` au niveau racine
- Test: `tests/prospect-pipeline.test.mjs`

**Interfaces:**
- Consumes: `prospectTacheEcheance`, `prospectTacheLibelle`.
- Produces: `prospectTachePayload(contact, etape, form, responsable) -> object|null` — la ligne à insérer dans `taches`, ou `null` si la case n'est pas cochée.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter `prospectTachePayload` à `NOMS`, puis :

```javascript
test('pas de tache si la case n est pas cochee', () => {
  assert.equal(prospectTachePayload({id:42}, 'Contacté',
    {prochaine_action_date:'2026-10-05', creer_tache:false}, 'Nicolas Serradeil'), null);
});

test('la tache porte le contact, l echeance a 09h00 et le responsable', () => {
  const t = prospectTachePayload({id:42, prenom:'Léo', nom:'Brignone'}, 'Contacté',
    {prochaine_action_date:'2026-10-05', prochaine_action_libelle:'Rappeler', creer_tache:true},
    'Nicolas Serradeil');
  assert.equal(t.contact_id, 42);
  assert.equal(t.responsable, 'Nicolas Serradeil');
  assert.match(t.due_date, /^2026-10-05T09:00/);
  assert.ok(t.titre.includes('Rappeler'));
  assert.ok(t.titre.includes('Brignone'));
  assert.ok(t.id.startsWith('tw_prospect_42_'));
  assert.equal(t.besoin_id, null);
  assert.equal(t.mission_id, null);
  assert.ok(!/[—–]/.test(t.titre));
});

test('pas de tache pour une etape sans date', () => {
  assert.equal(prospectTachePayload({id:42}, 'Perdu', {motif_perte:'Autre', creer_tache:true},
    'Nicolas Serradeil'), null);
});
```

- [ ] **Step 2: Lancer le test**

Run: `node --test tests/prospect-pipeline.test.mjs`
Expected: FAIL, `prospectTachePayload introuvable`

- [ ] **Step 3: Écrire l'implémentation**

```javascript
function prospectTachePayload(contact, etape, form, responsable) {
  form = form || {};
  if (!form.creer_tache) return null;
  var due = prospectTacheEcheance(form.prochaine_action_date);
  if (!due) return null;
  var qui = [contact.prenom, contact.nom].filter(Boolean).join(' ');
  var quoi = form.prochaine_action_libelle || prospectTacheLibelle(etape);
  return {
    id: 'tw_prospect_' + contact.id + '_' + Date.now(),
    titre: quoi + (qui ? ' : ' + qui : ''),
    statut: 'en_cours',
    due_date: due,
    contact_id: parseInt(contact.id),
    besoin_id: null,
    mission_id: null,
    notes: null,
    responsable: responsable
  };
}
```

- [ ] **Step 4: Lancer les tests**

Run: `node --test tests/prospect-pipeline.test.mjs`
Expected: PASS, 19 tests

- [ ] **Step 5: Brancher dans `handleEtapeConfirm` avec la garde anti-doublon**

**Review Focus 4** : la garde interroge Supabase, pas le tableau `taches` du state React, qui peut être périmé si un autre onglet a déjà créé la tâche. Insérer avant le `toast` final :

```javascript
const tache=prospectTachePayload(contact,etape,form,profile.nom);
if(tache){
  // Garde anti-doublon sur donnees fraiches : un autre onglet a pu deja poser la tache.
  const {data:dejaLa}=await sb.from('taches').select('id')
    .eq('contact_id',parseInt(contact.id))
    .like('id','tw_prospect_%')
    .not('statut','in','("fait","annule")').limit(1);
  if(dejaLa&&dejaLa.length>0){
    toast('Action re-planifiée, pense à mettre à jour la tâche existante');
  } else {
    const {error:tErr}=await sb.from('taches').insert(tache);
    if(!tErr) toast('📅 Tâche créée'); else toast('Étape enregistrée, tâche non créée','error');
  }
}
```

- [ ] **Step 6: Recetter à la main**

Passer un prospect en « Contacté » avec la case cochée : une tâche apparaît dans l'onglet Tâches, à 9h00, au bon jour. Repasser le même prospect en « En discussion » : le toast « re-planifiée » s'affiche et aucune seconde tâche n'est créée.

- [ ] **Step 7: Commit**

```bash
node tests/check-babel.mjs
git add index.html tests/prospect-pipeline.test.mjs
git commit -m "feat(prospects): creation de la tache CRM avec garde anti-doublon"
```

---

### Task 6: Vue liste — toggle, colonnes, tri

**Files:**
- Modify: `index.html` `TabProspects` (3756-3929)

**Interfaces:**
- Consumes: tout le socle des tâches 1 et 3.
- Produces: état `prospectView` (`'list' | 'kanban'`), persisté dans `prefs.prospects_view`.

- [ ] **Step 1: Ajouter l'état, sans toucher à `viewMode`**

⚠️ `viewMode` (index.html:3765) sert déjà à basculer Contacts / Comptes. Ne pas le réutiliser. Ajouter à côté :

```javascript
const [prospectView,setProspectView]=useState(prefs?.prospects_view||'list');
```

- [ ] **Step 2: Afficher le toggle, uniquement quand le filtre statut vaut Prospect**

Près du filtre statut (index.html:4315-4317), dans le bloc `viewMode==='contacts'` :

```jsx
{filterStatut==='Prospect'&&<div style={{display:'flex',gap:0,marginLeft:'auto'}}>
  {[['list','Liste'],['kanban','Kanban']].map(function(v){
    return <button key={v[0]} onClick={function(){setProspectView(v[0]);savePref('prospects_view',v[0]);}}
      style={{padding:'6px 12px',fontSize:11,fontWeight:prospectView===v[0]?900:700,
        background:prospectView===v[0]?'#1C1F35':'#fff',color:prospectView===v[0]?'#fff':'#1C1F35',
        border:'1px solid #E4E4E6',borderRadius:0,cursor:'pointer',textTransform:'uppercase'}}>{v[1]}</button>;
  })}
</div>}
```

Reprendre le mécanisme de persistance exactement comme `TabBesoins` le fait pour `prefs.besoins_view` (index.html:5976) ; si l'helper porte un autre nom que `savePref`, utiliser celui du fichier.

- [ ] **Step 3: Ajouter les deux colonnes au tableau**

Dans l'en-tête et dans chaque ligne, sous condition `filterStatut==='Prospect'` :

```jsx
{filterStatut==='Prospect'&&<td style={{padding:'4px 8px'}}>
  <ColorBadge label={prospectEtapeOuDefaut(c)} colors={PROSPECT_BADGE_COLORS[prospectEtapeOuDefaut(c)]}/>
</td>}
{filterStatut==='Prospect'&&<td style={{padding:'4px 8px',fontSize:11,
  borderLeft:prospectEnRetard(c)?'3px solid #FF6B6B':'none'}}>
  {c.prochaine_action_date?<>{fmtDate(c.prochaine_action_date)} <span style={{color:'#A4A6AB'}}>{c.prochaine_action_libelle||''}</span></>:'—'}
</td>}
```

Utiliser les helpers de badge et de date déjà présents dans le fichier (`ColorBadge` index.html:890, et le formateur de date employé dans les autres colonnes) plutôt que d'en écrire de nouveaux.

- [ ] **Step 4: Trier par prochaine action quand on est sur Prospect**

Le tri actuel se fait sur `date_dernier` (index.html:3763 et 3808). Ajouter, sans le remplacer :

```javascript
// Sur le filtre Prospect, ce qui est en retard remonte : tri par prochaine action croissante,
// les contacts sans action datee en fin de liste.
if(filterStatut==='Prospect'){
  liste=liste.slice().sort(function(a,b){
    var da=a.prochaine_action_date||'9999', db=b.prochaine_action_date||'9999';
    return da.localeCompare(db);
  });
}
```

- [ ] **Step 5: Vérifier la non-régression**

Run: `node tests/check-babel.mjs`

Puis dans l'app : filtre « Tous » → le tableau est identique à avant, pas de toggle, pas de colonnes en plus. Filtre « Prospect » → toggle et colonnes présents, les retards en haut. La bascule Contacts / Comptes fonctionne toujours. Recharger la page : le toggle a gardé sa valeur.

- [ ] **Step 6: Commit**

```bash
git add index.html
git commit -m "feat(prospects): vue liste, toggle et colonnes d etape"
```

---

### Task 7: Kanban `ProspectsKanban`

**Files:**
- Modify: `index.html` — nouveau composant avant `TabProspects`, rendu dans `TabProspects`

**Interfaces:**
- Consumes: le hook drag&drop (index.html:701-719), le CSS `.kanban-board` / `.kanban-col` / `.kanban-card` (index.html:83-92), `prospectEtapeOuDefaut`, `prospectEnRetard`, `PROSPECT_BADGE_COLORS`.
- Produces: `<ProspectsKanban contacts primaryCompteByContact compteMap onCardClick onDrop={(contact, etapeCible) => void} />`

- [ ] **Step 1: Écrire le composant**

Cloner la structure du kanban Besoins (index.html:5920), en gardant les 3 colonnes de sortie repliées par défaut :

```javascript
// Kanban des prospects — clone du kanban Besoins (5920). Cloné et non factorisé :
// le kanban Besoins est couplé en dur à BESOIN_STATUTS_ORDRE et besoinCandidats, le
// généraliser ferait porter un risque de régression à un écran qui marche.
function ProspectsKanban({ contacts, societeOf, onCardClick, onDrop }) {
  const [sortiesOuvertes,setSortiesOuvertes]=useState(false);
  const [overCol,setOverCol]=useState(null);
  const colonnes=sortiesOuvertes?PROSPECT_ETAPES:PROSPECT_ETAPES_ACTIVES;
  const parEtape=useMemo(()=>{
    const m={}; PROSPECT_ETAPES.forEach(e=>m[e]=[]);
    (contacts||[]).forEach(c=>{ m[prospectEtapeOuDefaut(c)].push(c); });
    PROSPECT_ETAPES.forEach(e=>m[e].sort((a,b)=>
      (a.prochaine_action_date||'9999').localeCompare(b.prochaine_action_date||'9999')));
    return m;
  },[contacts]);

  return (<>
    <div style={{display:'flex',justifyContent:'flex-end',marginBottom:6}}>
      <button onClick={()=>setSortiesOuvertes(v=>!v)} style={{fontSize:10,fontWeight:700,
        padding:'4px 10px',border:'1px solid #E4E4E6',background:'#fff',borderRadius:0,
        cursor:'pointer',textTransform:'uppercase'}}>
        {sortiesOuvertes?'Masquer les sorties':'Afficher les sorties'}
      </button>
    </div>
    <div className="kanban-board">
      {colonnes.map(function(etape){
        var bc=PROSPECT_BADGE_COLORS[etape];
        return <div key={etape}
          className={`kanban-col${overCol===etape?' drag-over':''}`}
          onDragOver={function(e){e.preventDefault();setOverCol(etape);}}
          onDragLeave={function(){setOverCol(null);}}
          onDrop={function(e){e.preventDefault();setOverCol(null);
            var id=e.dataTransfer.getData('text/plain');
            var c=(contacts||[]).find(function(x){return String(x.id)===String(id);});
            if(c&&prospectEtapeOuDefaut(c)!==etape) onDrop(c,etape);}}>
          <div style={{fontSize:10,fontWeight:900,textTransform:'uppercase',padding:'4px 2px',
            borderBottom:'3px solid '+bc.bg,marginBottom:4}}>
            {etape} <span style={{color:'#A4A6AB'}}>{parEtape[etape].length}</span>
          </div>
          <div className="kanban-items">
            {parEtape[etape].map(function(c){
              var retard=prospectEnRetard(c);
              return <div key={c.id} className="kanban-card" draggable
                onDragStart={function(e){e.dataTransfer.setData('text/plain',String(c.id));}}
                onClick={function(){onCardClick(c);}}
                style={{borderLeft:retard?'3px solid #FF6B6B':'1px solid #E4E4E6'}}>
                <div style={{fontSize:11,fontWeight:800}}>{c.prenom} {c.nom}</div>
                <div style={{fontSize:10,color:'#A4A6AB'}}>{societeOf(c)||''}</div>
                {c.prochaine_action_date&&<div style={{fontSize:10,marginTop:2,
                  color:retard?'#FF6B6B':'#1C1F35',fontWeight:retard?800:400}}>
                  {c.prochaine_action_date.slice(0,10)} · {c.prochaine_action_libelle||''}
                </div>}
              </div>;
            })}
          </div>
        </div>;
      })}
    </div>
  </>);
}
```

- [ ] **Step 2: Le rendre dans `TabProspects`**

Remplacer le rendu du tableau quand `filterStatut==='Prospect' && prospectView==='kanban'` :

```jsx
{viewMode==='contacts'&&filterStatut==='Prospect'&&prospectView==='kanban'
  ? <ProspectsKanban contacts={contactsFiltres} societeOf={societeOf}
      onCardClick={setSelected} onDrop={(c,e)=>{setSelected(c);setDropEtape(e);}}/>
  : /* tableau existant, inchangé */ null}
```

Ajouter `const [dropEtape,setDropEtape]=useState(null);` dans `TabProspects`, et passer `dropEtape` à `ContactDetail` en prop `etapeInitiale`.

- [ ] **Step 3: Le drop ouvre le micro-formulaire, il n'écrit pas**

Dans `ContactDetail`, consommer la prop :

```javascript
// Un drop sur le kanban est une INTENTION : il ouvre le micro-formulaire et n'ecrit
// qu'a la confirmation. Sans ca, glisser vers « Perdu » ecrirait sans motif.
useEffect(()=>{ if(etapeInitiale) setEtapeCible(etapeInitiale); },[etapeInitiale]);
```

- [ ] **Step 4: Vérifier**

Run: `node tests/check-babel.mjs`

Dans l'app : filtre Prospect + Kanban → 5 colonnes, compteurs justes, sorties masquées puis dépliables. Glisser une carte vers « Perdu » → la fiche s'ouvre sur le micro-formulaire, motif obligatoire. Annuler → la carte est restée dans sa colonne d'origine. Confirmer → elle change de colonne après refresh. Une prochaine action dépassée affiche le liseré rouge.

- [ ] **Step 5: Commit**

```bash
git add index.html
git commit -m "feat(prospects): vue kanban, le drop ouvre le micro-formulaire"
```

---

### Task 8: Jonction « Qualifié » vers Besoin, et sortie du board

**Files:**
- Modify: `index.html` `ContactDetail` — proposition de création de besoin
- Modify: `index.html` `TabProspects` — filtrage des prospects déjà pourvus d'un besoin
- Test: `tests/prospect-pipeline.test.mjs`

**Interfaces:**
- Consumes: `prospectEtapeOuDefaut`.
- Produces: `prospectSurLeBoard(contact, besoins) -> bool`.

- [ ] **Step 1: Écrire le test qui échoue**

Ajouter `prospectSurLeBoard` à `NOMS`, puis :

```javascript
test('un prospect avec un besoin actif quitte le board', () => {
  const c = { id: 7, statut: 'Prospect', etape_prospect: 'Qualifié' };
  assert.equal(prospectSurLeBoard(c, []), true);
  assert.equal(prospectSurLeBoard(c, [{ contact_id: 7, statut: 'Opportunité' }]), false);
  assert.equal(prospectSurLeBoard(c, [{ contact_id: 7, statut: 'Besoin Gagné' }]), false);
});

test('un besoin perdu rend le prospect au board', () => {
  const c = { id: 7, statut: 'Prospect', etape_prospect: 'Qualifié' };
  assert.equal(prospectSurLeBoard(c, [{ contact_id: 7, statut: 'Besoin Perdu' }]), true);
});

test('un besoin sur un AUTRE contact ne sort personne', () => {
  const c = { id: 7, statut: 'Prospect' };
  assert.equal(prospectSurLeBoard(c, [{ contact_id: 99, statut: 'Opportunité' }]), true);
});
```

- [ ] **Step 2: Lancer le test**

Run: `node --test tests/prospect-pipeline.test.mjs`
Expected: FAIL, `prospectSurLeBoard introuvable`

- [ ] **Step 3: Écrire l'implémentation**

```javascript
function prospectSurLeBoard(contact, besoins) {
  // C'est l'existence d'un besoin ACTIF qui sort le prospect du board, pas l'etape :
  // un besoin perdu doit rendre le prospect au pipeline.
  var lies = (besoins||[]).filter(function(b){
    return String(b.contact_id) === String(contact.id) && b.statut !== 'Besoin Perdu';
  });
  return lies.length === 0;
}
```

- [ ] **Step 4: Lancer les tests**

Run: `node --test tests/prospect-pipeline.test.mjs`
Expected: PASS, 25 tests

- [ ] **Step 5: Proposer la création du besoin à l'entrée en « Qualifié »**

Dans `handleEtapeConfirm`, après le succès de l'update, cloner le pattern `proposeMission` (index.html:5630) :

```javascript
if(etape==='Qualifié'){
  const {data:dejaBesoin}=await sb.from('besoins').select('id')
    .eq('contact_id',contact.id).neq('statut','Besoin Perdu').limit(1);
  if(!dejaBesoin||dejaBesoin.length===0){ setModal('proposeBesoin'); }
}
```

Et la modale, pré-remplie compte + contact, statut `Opportunité`, réutilisant la modale « Nouveau besoin » existante (index.html:5400) plutôt que d'en écrire une seconde.

- [ ] **Step 6: Filtrer le board**

Dans `TabProspects`, appliquer `prospectSurLeBoard` à la liste passée au kanban **et** à la liste triée, quand `filterStatut==='Prospect'`.

- [ ] **Step 7: Recetter**

Passer un prospect en « Qualifié » : la modale de création de besoin s'ouvre, pré-remplie. Créer le besoin : le prospect disparaît du board. Passer ce besoin en « Besoin Perdu » : le prospect réapparaît.

- [ ] **Step 8: Commit**

```bash
node tests/check-babel.mjs
git add index.html tests/prospect-pipeline.test.mjs
git commit -m "feat(prospects): jonction Qualifie vers Besoin et sortie du board"
```

---

### Task 9: Boucle de retour depuis les tâches

**Files:**
- Modify: `index.html` `TabTaches` (~4990) — clôture d'une tâche de prospection

**Interfaces:**
- Consumes: `ProspectMicroForm`, `prospectPatchEtape`.
- Produces: rien de nouveau.

- [ ] **Step 1: Détecter les tâches de prospection**

Ce sont celles dont l'`id` commence par `tw_prospect_` (posé en Tâche 5) et qui portent un `contact_id`.

- [ ] **Step 2: Rouvrir le micro-formulaire à la clôture**

À la clôture d'une telle tâche, au lieu de simplement la passer à `fait`, ouvrir `ProspectMicroForm` sur le contact lié, pré-positionné sur son étape courante :

```javascript
// R3 : clore une tache de prospection demande ce que l'action a donne. C'est ce qui
// tient le « prochaine action obligatoire » sans regle bloquante penible.
if(String(t.id).startsWith('tw_prospect_')&&t.contact_id){
  const c=(contacts||[]).find(x=>String(x.id)===String(t.contact_id));
  if(c){ setContactEtape(c); return; }   // la tache sera close a la confirmation
}
```

- [ ] **Step 3: Clore la tâche à la confirmation de l'étape**

À la confirmation, enchaîner : patch d'étape, insertion historique, puis passage de la tâche à `fait`. Si l'utilisateur annule le micro-formulaire, **la tâche reste ouverte** — sinon on perd la prochaine action.

- [ ] **Step 4: Recetter**

Créer une tâche via un passage d'étape, aller dans l'onglet Tâches, la clore : le micro-formulaire s'ouvre. Annuler : la tâche est toujours là. Confirmer une nouvelle étape : la tâche passe à `fait` et une nouvelle est créée si la case est cochée.

- [ ] **Step 5: Commit**

```bash
node tests/check-babel.mjs
git add index.html
git commit -m "feat(prospects): clore une tache de prospection redemande l etape"
```

---

### Task 10: Branchement des sessions d'appels et retrait du flag

**Files:**
- Modify: `index.html` — fonction pure `etapeDepuisResultatAppel` au niveau racine
- Modify: `index.html` `handleTerminer` (cf. `SPEC_tab_prospection_CRM.md`, lignes 400-496), et les points de pose du flag (11092, 11171)
- Modify: `index.html:2161` (bannière), `index.html:3889` (badge), `index.html:1569-1574` (case à cocher), `index.html:2169` (levée)
- Test: `tests/prospect-pipeline.test.mjs`

**Interfaces:**
- Consumes: `PROSPECT_ETAPES`.
- Produces: `etapeDepuisResultatAppel(statutAppel, nePlusAppeler, etapeActuelle) -> string`.

- [ ] **Step 1: Écrire le test qui échoue**

```javascript
test('le resultat d appel fait avancer l etape', () => {
  assert.equal(etapeDepuisResultatAppel('interested', false, 'À contacter'), 'En discussion');
  assert.equal(etapeDepuisResultatAppel('unreachable', false, 'À contacter'), 'Contacté');
  assert.equal(etapeDepuisResultatAppel('not_interested', false, 'En discussion'), 'Perdu');
  assert.equal(etapeDepuisResultatAppel('not_interested', true, 'En discussion'), 'Ne pas recontacter');
  assert.equal(etapeDepuisResultatAppel('called', false, 'À contacter'), 'Contacté');
});

test('un appel ne fait jamais RECULER une etape deja avancee', () => {
  assert.equal(etapeDepuisResultatAppel('called', false, 'RDV planifié'), 'RDV planifié');
  assert.equal(etapeDepuisResultatAppel('unreachable', false, 'En discussion'), 'En discussion');
  // mais une sortie est toujours possible
  assert.equal(etapeDepuisResultatAppel('not_interested', false, 'RDV planifié'), 'Perdu');
});

test('un statut d appel neutre ne change rien', () => {
  assert.equal(etapeDepuisResultatAppel('none', false, 'Contacté'), 'Contacté');
});
```

- [ ] **Step 2: Lancer le test**

Run: `node --test tests/prospect-pipeline.test.mjs`
Expected: FAIL, `etapeDepuisResultatAppel introuvable`

- [ ] **Step 3: Écrire l'implémentation**

```javascript
function etapeDepuisResultatAppel(statutAppel, nePlusAppeler, etapeActuelle) {
  if (statutAppel === 'not_interested') return nePlusAppeler ? 'Ne pas recontacter' : 'Perdu';
  var cible = { interested:'En discussion', unreachable:'Contacté', called:'Contacté' }[statutAppel];
  if (!cible) return etapeActuelle;
  // Un appel ne fait jamais reculer : on ne prend la cible que si elle est plus avancee.
  var iActuelle = PROSPECT_ETAPES_ACTIVES.indexOf(etapeActuelle);
  var iCible = PROSPECT_ETAPES_ACTIVES.indexOf(cible);
  if (iActuelle < 0) return etapeActuelle;   // deja sorti du pipeline, on ne le ramene pas
  return iCible > iActuelle ? cible : etapeActuelle;
}
```

- [ ] **Step 4: Lancer les tests**

Run: `node --test tests/prospect-pipeline.test.mjs`
Expected: PASS, 28 tests

- [ ] **Step 5: Brancher dans `handleTerminer`**

Dans la boucle qui fait l'UPSERT de `session_prospection_contacts`, ajouter au patch du contact l'étape calculée, et faire porter `want_relance` / `relance_date` sur `prochaine_action_date` / `prochaine_action_libelle`. **Ne pas créer de seconde tâche** : `handleTerminer` crée déjà la tâche de relance, on réutilise la sienne.

- [ ] **Step 6: Exclure les sorties de la sélection de contacts**

Là où la sélection filtrait sur `ne_pas_recontacter !== true`, filtrer désormais sur `PROSPECT_ETAPES_SORTIE.indexOf(prospectEtapeOuDefaut(c)) < 0`.

- [ ] **Step 7: Basculer bannière, badge et case sur l'étape**

- Bannière (2161) : condition `prospectEtapeOuDefaut(contact)==='Ne pas recontacter'`, texte de détail depuis `motif_perte_precision`.
- Badge en liste (3889) : même condition.
- Case à cocher dans `ContactEditModal` (1569-1574) : **retirée**, l'étape la remplace.
- Pose automatique en fin de session (11092, 11171) : écrit l'étape, plus le flag.
- Levée réservée au propriétaire (2169) : la condition se déplace sur le stepper — si `prospectEtapeOuDefaut(contact)==='Ne pas recontacter'` et que `profile.nom !== contact.responsable` et que le rôle n'est pas admin, les boutons d'étape sont désactivés avec une infobulle « seul le responsable peut remettre ce contact en jeu ».

- [ ] **Step 8: Recetter, en insistant sur la non-régression RGPD**

Un contact en « Ne pas recontacter » : bannière rouge présente, badge en liste présent, absent de la sélection d'une nouvelle session d'appels. Connecté sous un autre commercial : impossible de le sortir de cette étape. Terminer une session en cochant « pas intéressé + ne plus appeler » : l'étape se pose.

- [ ] **Step 9: Commit**

```bash
node tests/check-babel.mjs
git add index.html tests/prospect-pipeline.test.mjs
git commit -m "feat(prospects): sessions d appels branchees sur l etape, flag NPC retire"
```

---

### Task 11: MCP v8.26.0

**Files:**
- Create: `upgrade-crm-mcp-src/server/prospect-rules.mjs`
- Create: `upgrade-crm-mcp-src/tests/prospect-rules.test.mjs`
- Modify: `upgrade-crm-mcp-src/server/index.mjs` (470, 553, 605, 452)
- Modify: `upgrade-crm-mcp-src/manifest.json` (ligne 5, et la description ligne 7)

**Interfaces:**
- Consumes: rien du navigateur (les deux exécutables n'ont aucun chemin d'import commun).
- Produces:
  - `PROSPECT_ETAPES`, `PROSPECT_ETAPES_ACTIVES`, `PROSPECT_ETAPES_SORTIE`, `PROSPECT_MOTIFS_PERTE`
  - `valideEtapeProspect(patch, contactActuel, appelant) -> {ok: bool, erreur?: string}`

- [ ] **Step 1: Écrire le test qui échoue**

Créer `upgrade-crm-mcp-src/tests/prospect-rules.test.mjs` :

```javascript
// Les garde-fous du pipeline prospect, cote serveur. Une regle qui ne vit que dans l'UI
// se contourne par l'API, ce qui revient a ne pas l'avoir.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { valideEtapeProspect, PROSPECT_ETAPES } from '../server/prospect-rules.mjs';

const NICOLAS = { nom: 'Nicolas Serradeil', role: 'commercial' };
const AUTRE   = { nom: 'Camille Durand',    role: 'commercial' };
const ADMIN   = { nom: 'Admin',             role: 'admin' };
const PROSPECT = { id: 7, statut: 'Prospect', responsable: 'Nicolas Serradeil', etape_prospect: 'Contacté' };

test('REVIEW FOCUS 5 — une etape inconnue est refusee, avec la liste des valeurs admises', () => {
  for (const faux of ['qualifie', 'RDV Planifie', 'A contacter', 'Gagné', '']) {
    const r = valideEtapeProspect({ etape_prospect: faux }, PROSPECT, NICOLAS);
    assert.equal(r.ok, false, faux);
    assert.ok(r.erreur.includes('Qualifié'), 'l erreur doit lister les valeurs admises');
  }
  assert.equal(valideEtapeProspect({ etape_prospect: 'Qualifié',
    prochaine_action_date: '2026-10-05' }, PROSPECT, NICOLAS).ok, true);
});

test('une etape active sans prochaine action est refusee', () => {
  const r = valideEtapeProspect({ etape_prospect: 'En discussion' }, PROSPECT, NICOLAS);
  assert.equal(r.ok, false);
  assert.match(r.erreur, /prochaine action/i);
});

test('« Perdu » sans motif est refuse, avec motif il passe', () => {
  assert.equal(valideEtapeProspect({ etape_prospect: 'Perdu' }, PROSPECT, NICOLAS).ok, false);
  assert.equal(valideEtapeProspect({ etape_prospect: 'Perdu', motif_perte: 'Pas de besoin' },
    PROSPECT, NICOLAS).ok, true);
});

test('seul le responsable, ou un admin, sort un contact de « Ne pas recontacter »', () => {
  const npc = { ...PROSPECT, etape_prospect: 'Ne pas recontacter' };
  const patch = { etape_prospect: 'À contacter' };
  assert.equal(valideEtapeProspect(patch, npc, AUTRE).ok, false);
  assert.match(valideEtapeProspect(patch, npc, AUTRE).erreur, /responsable/i);
  assert.equal(valideEtapeProspect(patch, npc, NICOLAS).ok, true);
  assert.equal(valideEtapeProspect(patch, npc, ADMIN).ok, true);
});

test('« A contacter » ne demande rien', () => {
  assert.equal(valideEtapeProspect({ etape_prospect: 'À contacter' }, PROSPECT, NICOLAS).ok, true);
});

test('un patch sans etape passe : la validation ne regarde que ce qu on lui donne', () => {
  assert.equal(valideEtapeProspect({ ville: 'Lyon' }, PROSPECT, NICOLAS).ok, true);
});

test('les etapes sont exactement celles de l app', () => {
  assert.deepEqual(PROSPECT_ETAPES, ['À contacter', 'Contacté', 'En discussion',
    'RDV planifié', 'Qualifié', 'En veille', 'Perdu', 'Ne pas recontacter']);
});
```

- [ ] **Step 2: Lancer le test**

Run: `cd ~/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-src && node --test tests/prospect-rules.test.mjs`
Expected: FAIL, module `../server/prospect-rules.mjs` introuvable

- [ ] **Step 3: Écrire le module**

Créer `upgrade-crm-mcp-src/server/prospect-rules.mjs` :

```javascript
// Garde-fous du pipeline prospect — cf. SPECS_CRM/SPEC_prospects_pipeline_etapes.md
// Ces regles existent DEUX fois : ici et dans index.html. Les deux executables n'ont
// aucun chemin d'import commun (HTML compile dans le navigateur, module Node). Le test
// rejoue les memes cas des deux cotes pour verrouiller l'equivalence.
export const PROSPECT_ETAPES_ACTIVES = ['À contacter','Contacté','En discussion','RDV planifié','Qualifié'];
export const PROSPECT_ETAPES_SORTIE = ['En veille','Perdu','Ne pas recontacter'];
export const PROSPECT_ETAPES = [...PROSPECT_ETAPES_ACTIVES, ...PROSPECT_ETAPES_SORTIE];
export const PROSPECT_MOTIFS_PERTE = ['Budget insuffisant','Pas le bon interlocuteur',
  'Pas de besoin','Choix concurrent','Perdu de vue','Autre'];

export function valideEtapeProspect(patch, contactActuel, appelant) {
  const etape = patch?.etape_prospect;
  if (etape === undefined || etape === null) return { ok: true };

  if (!PROSPECT_ETAPES.includes(etape)) {
    return { ok: false, erreur:
      `Étape « ${etape} » inconnue. Valeurs admises, accents et casse compris : ${PROSPECT_ETAPES.join(' · ')}` };
  }

  const exigeDate = etape === 'En veille' || PROSPECT_ETAPES_ACTIVES.indexOf(etape) > 0;
  if (exigeDate && !patch.prochaine_action_date) {
    return { ok: false, erreur:
      `L'étape « ${etape} » exige une prochaine action datée (champ prochaine_action_date).` };
  }
  if (etape === 'Perdu' && !patch.motif_perte) {
    return { ok: false, erreur:
      `L'étape « Perdu » exige un motif (champ motif_perte). Valeurs : ${PROSPECT_MOTIFS_PERTE.join(' · ')}` };
  }

  const etaitNPC = contactActuel?.etape_prospect === 'Ne pas recontacter';
  if (etaitNPC && etape !== 'Ne pas recontacter') {
    const estResponsable = appelant?.nom && appelant.nom === contactActuel?.responsable;
    if (!estResponsable && appelant?.role !== 'admin') {
      return { ok: false, erreur:
        `Seul le responsable du contact (${contactActuel?.responsable || 'inconnu'}) peut le sortir de « Ne pas recontacter ».` };
    }
  }
  return { ok: true };
}
```

- [ ] **Step 4: Lancer les tests**

Run: `node --test tests/prospect-rules.test.mjs`
Expected: PASS, 7 tests

- [ ] **Step 5: Brancher dans `crm_update_contact`**

Dans `server/index.mjs:605`, avant l'update : relire le contact courant, appeler `valideEtapeProspect`, et **retourner l'erreur au lieu d'écrire** si `ok` est faux. Même forme de refus que le garde-fou de scope de `crm_create_besoin` (v8.25.0), pour que le message soit lisible par Jules.

- [ ] **Step 6: Exposer l'étape en lecture**

- `crm_search_contacts` (470) : ajouter les 5 colonnes au select et à la sortie formatée ; ajouter les paramètres optionnels `etape` (filtre exact) et `en_retard` (booléen, `prochaine_action_date <= now()`).
- `crm_create_contact` (553) : si `statut === 'Prospect'` et qu'aucune étape n'est fournie, poser `À contacter`.

- [ ] **Step 7: Ajouter `crm_prospects_due_today`**

Nouvel outil, miroir de `agent_sequence_due_today` : les contacts `statut = 'Prospect'`, `prochaine_action_date <= now()`, étape hors sorties (sauf « En veille », dont c'est justement le réveil), triés par date croissante. Sortie : nom, société, étape, date, libellé, responsable. Paramètres : `responsable` et `agence`, optionnels.

- [ ] **Step 8: Bump de version et changelog**

- `manifest.json:5` : `"version": "8.26.0"`
- `manifest.json:7` : mentionner l'étape prospect dans la description des outils contacts
- `server/index.mjs:452` : ajouter l'entrée de changelog v8.26.0 (pipeline prospect, garde-fous, `crm_prospects_due_today`)

- [ ] **Step 9: Lancer toute la suite du MCP**

Run: `node --test tests/`
Expected: PASS, aucun test existant cassé.

- [ ] **Step 10: Commit**

```bash
cd ~/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-mcp-src
git add server/prospect-rules.mjs tests/prospect-rules.test.mjs server/index.mjs manifest.json
git commit -m "feat(mcp): pipeline prospect, garde-fous serveur, crm_prospects_due_today (v8.26.0)"
```

---

### Task 12: Rebuild et distribution du .mcpb

Tant que le paquet n'est pas reconstruit, rien de la tâche 11 n'existe pour Cowork ni pour Jules.

**Files:**
- Create: `upgrade-crm/upgrade-crm-v8.26.0.mcpb`

- [ ] **Step 1: Construire le paquet**

Reprendre la procédure de build du `.mcpb` documentée dans `DEPLOY.md` (le `8.25.0` sert de référence de ce qui doit se retrouver dedans).

- [ ] **Step 2: Vérifier la version du paquet**

Run: `unzip -p ~/Pro/03_Outils-IA/upgrade-crm/upgrade-crm-v8.26.0.mcpb manifest.json | head -6`
Expected: `"version": "8.26.0"`

- [ ] **Step 3: Installer et vérifier côté Jules**

Installer le paquet, ouvrir une **session fraîche** (les outils MCP se chargent au démarrage de session, une session déjà ouverte ne les aura pas), puis vérifier :

```
crm_version               → 8.26.0
crm_prospects_due_today   → retourne une liste, même vide, sans erreur
crm_update_contact        → sur un prospect, avec etape_prospect 'En discussion' et
                            sans date : doit REFUSER avec un message lisible
```

- [ ] **Step 4: Installer côté Claude Cowork / Desktop**

Même paquet, même vérification.

- [ ] **Step 5: Commit**

```bash
git add upgrade-crm-v8.26.0.mcpb
git commit -m "build(mcp): paquet 8.26.0 avec le pipeline prospect"
```

---

### Task 13: Migration 52, une semaine après

**À ne lancer qu'après une semaine de production sans incident.**

- [ ] **Step 1: Vérifier qu'aucun contact n'a été perdu**

```sql
select count(*) from contacts c where c.ne_pas_recontacter = true
  and c.etape_prospect is distinct from 'Ne pas recontacter'
  and not exists (select 1 from historique_actions h
                  where h.id_prospect = c.id and h.type_action = 'Changement d''étape');
```
Expected: `0`. Le contrôle ignore les contacts dont l'étape a changé depuis la mise en service (une levée de refus légitime laisse l'ancien flag à true). Si ce n'est pas 0, **ne pas appliquer** la migration : investiguer d'abord.

- [ ] **Step 2: Vérifier qu'aucun code ne lit plus le flag**

Run: `grep -n "ne_pas_recontacter" index.html`
Expected: aucune occurrence hors commentaire historique.

- [ ] **Step 3: Appliquer `db/52_drop_ne_pas_recontacter.sql`**

- [x] **Step 4: (fait dans la branche)** Les colonnes `ne_pas_recontacter*` ont été retirées du select contacts dès la branche (revue finale, I1) : rien à retirer après coup.

- [ ] **Step 5: Commit**

```bash
node tests/check-babel.mjs
git add -A
git commit -m "chore(prospects): suppression du flag ne_pas_recontacter (migration 52)"
```
