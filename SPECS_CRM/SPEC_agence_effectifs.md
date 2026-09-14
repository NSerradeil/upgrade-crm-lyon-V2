# SPEC — Onglet « Agence » (effectifs CDI & sous-traitants)

**Date** : 2026-09-14 · **Demandeur** : Nicolas · **Statut** : spec validée en discussion, à planifier
**Objectif** : remplacer le fichier `Point_COLLAB-UPGRADE.xlsx` de Pierre par une vue live dans le CRM :
effectifs par agence, coût (salaire → CJM), mission en cours (TJM, marge), disponibilité, intercontrat.

---

## 1. Périmètre

### Inclus (V1)
- Nouvel onglet top-level **Agence**, placé entre *Tâches* et *Comptes & Contacts*.
- Toggle **CDI | Sous-traitants** (même composant segmenté que Contacts/Comptes).
- Bandeau KPI par périmètre filtré.
- Tableau triable/filtrable + vue cartes mobile + « Charger plus ».
- Volet latéral collaborateur (sous-onglets Mission / Interco / Infos), navigation croisée vers `MissionDetail`.
- Création/édition d'un collaborateur (CDI ou ST) par tout commercial, via le formulaire contact enrichi.
- **Export Excel** du tableau filtré (format proche de celui de Pierre).
- **Alertes proactives** : tâche CRM auto quand une dispo/fin de mission passe sous 60 jours.
- Migration SQL + script d'import initial depuis l'Excel (dry-run → GO → apply).

### Exclus (V2, notés)
- Historique des changements de salaire/CJM (`contacts_remuneration_log`).
- Colonnes « Dispo à 2 semaines / 2 mois » et « Localisation / Type mission (AT, Ctrl…) » de l'Excel.
- Création de comptes CRM pour les partners qui n'en ont pas (action admin Nicolas, hors code).

---

## 2. Modèle de données — `db/20_agence.sql`

Les collaborateurs sont déjà des `contacts` (`statut` ∈ `Consultant CDI` / `Freelance` / `Prestataire`
= `CONSULTANT_STATUTS`), les missions pointent déjà sur eux (`missions.contact_consultant_id`),
l'intercontrat aussi (`interco_imputations.contact_consultant_id`). On **étend `contacts`** :

| Colonne | Type | Rôle |
|---|---|---|
| `date_entree` | `date` | entrée dans la société (Excel col. D) |
| `date_sortie` | `date` | sortie ; si non nulle et ≤ aujourd'hui → collaborateur « sorti », masqué par défaut |
| `salaire_annuel` | `numeric(10,2)` | brut annuel, CDI uniquement |
| `cjm_manuel` | `boolean default false` | `true` si le CJM a été saisi à la main (pas recalculé depuis le salaire) |
| `statut_rh` | `text` check in (`arret_maladie`, `conge`) null | statut saisi ; `en_mission` / `intercontrat` / `dispo` sont **déduits**, jamais stockés |
| `statut_rh_depuis` | `date` | début du statut saisi |
| `type_presta` | `text` check in (`freelance`, `sous_traitant`) | ST uniquement |
| `manager_trigramme` | `text` | fallback d'affichage du partner responsable (Excel col. K) |

Règles :
- **CJM auto** : à l'enregistrement d'un CDI, si `salaire_annuel` renseigné et `cjm_manuel=false` →
  `cjm = round(salaire_annuel / 215 * 1.7, 2)` (formule de l'Excel). Fait côté app à la sauvegarde
  (pas de trigger : le MCP `crm_set_cjm` doit continuer à poser un CJM manuel → il passe `cjm_manuel=true`).
- Backfill `type_presta` : `Freelance` → `freelance`, `Prestataire` → `sous_traitant`.
- **Partner responsable** = `partner_consultants` (partner_id → `profiles`) fait foi, comme pour Majo.
  Si le consultant n'y est pas → afficher `manager_trigramme`. La liste des trigrammes ↔ noms vit dans
  une constante app `MANAGER_TRIGRAMMES` (NSE Nicolas Serradeil, ACD Anne-Claire Decker, CSA Camille
  Salinson, ABE Amel Benzai, PSO Pierre Sotiropoulos*, MJP Majo Paquelier, LBL Louis Blandin,
  **CAJ Cassandre Jacquemin** (« partner des partners » : elle manage tous les partners de France), APL Anthony
  Plancoulaine, WSA Weronika Sawicki, FEL Fabrice Elmoznino, HSI Hervé Sinpaseuth, SLE Stanislas Le Moy,
  JSE Julian Sendra, COS Constance Salem). Mapping validé par Nicolas le 14/09 (`*` nom de famille à confirmer).
- **Partner des partners** (Cassandre, décision Nicolas 14/09) : nouvelle colonne
  `profiles.partner_lead boolean default false`. Un partner avec `partner_lead=true` a pour périmètre
  **l'union de toutes les lignes `partner_consultants`** (tous partners, présents et futurs), en lecture
  (app : `partnerSet`) ET en écriture (RLS : `is_my_consultant()` retourne vrai si le consultant est
  rattaché à n'importe quel partner). Mêmes restrictions qu'un partner sinon (pas de besoins/prospection,
  pas de création ni suppression). Migration incluse dans `db/20_agence.sql`.
- RLS : aucune nouvelle policy. Les colonnes héritent des policies `contacts` (lecture ouverte,
  UPDATE tout commercial, DELETE responsable/admin, partner scopé `is_my_consultant`). Salaire
  visible par tous ceux qui voient l'onglet (décision Nicolas 14/09).

**Aucune nouvelle table.** Les tâches d'alerte utilisent `taches` existante (voir §7).

---

## 3. Champs calculés (app, `useMemo`, zéro requête supplémentaire)

Tout est déjà chargé par `fetchAll` (contacts, missions, interco_imputations, partner_consultants, profiles, taches).

Pour chaque collaborateur `c` :
- `missionEnCours` = mission avec `contact_consultant_id=c.id` et `statut='En cours'` (si plusieurs :
  la fin la plus lointaine) ; sinon mission `New` la plus proche (démarrage à venir, affichée « démarre le … »).
- `joursAvantDispo` = `ceil((date_fin_mission − today)/1j)` ; mission sans date de fin → `null` (« fin non définie »).
- `tjm` = `missionEnCours.tjm` ; `cjm` = `c.cjm` (fallback `missionEnCours.cjm`).
- `marge` = `(tjm − cjm) / tjm` ; `null` si tjm ou cjm absent.
- `intercoAnnee` = Σ `interco_imputations.jours` pour `c.id` et `annee = année courante`.
- `etat` (badge Dispo) :
  1. `c.statut_rh` renseigné → `arret_maladie` / `conge` (coral, « depuis le JJ/MM »)
  2. `missionEnCours` → `en_mission` avec `joursAvantDispo`
  3. sinon → `intercontrat` (CDI) / `sans_mission` (ST)
- `sorti` = `c.date_sortie && c.date_sortie <= today`.

Code couleur **Dispo / Fin de mission** (règle Nicolas) : vert `> 60 j`, **orange `≤ 60 j`**, **rouge `≤ 30 j`**
(rouge inclut négatif = mission dépassée sans clôture, libellé « dépassée de X j »). Intercontrat : gris,
libellé « interco · X j cumulés {année} ». Marge : orange si `< 30 %` (seuil §3 Upgrade.md), rouge si `< 20 %`.

---

## 4. Droits & visibilité

| Rôle | Onglet visible | Périmètre | Écriture |
|---|---|---|---|
| admin | oui | France, filtre agence libre | tout |
| commercial | oui | France, filtre agence libre (préselection = son agence) | créer/éditer tout (db/09), supprimer ses contacts |
| partner | oui | `partnerSet` (ses consultants), comme Majo aujourd'hui ; filtre agence masqué | éditer ses consultants (RLS existante), pas de création ni suppression |

Ajouter `'agence'` à la liste blanche partner ligne ~8251. Les 6 « internes » (commerciaux) ne sont pas
des collaborateurs : ils sont exclus (statut ≠ CONSULTANT_STATUTS).

---

## 5. UX / UI

### 5.1 En-tête d'onglet
- Onglet `{id:'agence', label:'Agence (N)'}` où N = effectif actif du périmètre visible ; couleur
  `TAB_COLORS.agence` = jade `#00C218` (texte midnight), seule teinte de la palette non encore prise par un onglet.
- Ligne 1 : toggle segmenté **CDI (61) | Sous-traitants (42)** (classes exactes de `viewMode` Contacts/Comptes)
  · à droite bouton `+ Nouveau collaborateur` (`btn-brutal`, bg-midnight) et bouton `Export Excel` (outline).
- Ligne 2 (filtres) : recherche texte · `select` Agence (Lyon/Paris/Bordeaux/Nantes/Toutes) ·
  `select` Responsable (partner ou commercial selon l'onglet) · chips d'état multi-sélection :
  `En mission` / `Dispo ≤ 60 j` / `Intercontrat` / `Arrêt & congés` · toggle « Sortis » (off par défaut).
- Ligne 3 : **4 widgets KPI cliquables « dalle + détail »**, exactement le composant des cartes du
  Tableau de bord Missions (carte blanche, liseré gauche couleur, active = fond midnight + ombre portée ;
  clic = ouvre la zone détail dessous, re-clic sur une autre dalle = change la vue). Recalculés sur le
  périmètre filtré (agence / partner / chips). Ce sont les chiffres que Pierre lit dans l'Excel (col. A =
  compteur, lignes de totaux « COLLAB Régies » / « SOUS-TRAITANTS » = CJ/TJM/MCV moyens) :
  | Dalle | Valeur | Sous-titre | Détail (zone sous les dalles) |
  |---|---|---|---|
  | **EFFECTIF** (vert) | nb collaborateurs actifs (CDI, ou free/ST dans l'onglet ST) | « X en mission · Y dispo » | **Arrivées et sorties par mois de l'année en cours** : barres mensuelles (arrivées en jade, sorties en coral), effectif cumulé en fin de mois en ligne ; liste des arrivées du mois cliqué (nom, agence, date, partner). |
  | **INTERCONTRAT** (jaune) — onglet ST : **SANS MISSION** (gris) | nb CDI en interco le mois affiché (M-1 si mois courant non saisi, logique TDB actuelle) | « Xj YTD · coût · prénoms » + badge MALUS ≥ 8 % / Attention ≥ 5 % | **Le widget existant du TDB, déplacé tel quel** : `ChartInter` (taux mensuel, objectif 5 %, malus 8 %, trimestres) + liste des consultants en interco du mois cliqué (jours, coût, clic → fiche). En onglet ST : liste des free sans mission. |
  | **TJM MOYEN** (bleu) | TJM moyen des missions en cours du périmètre | « CJM moyen X € · Y missions » | **TJM moyen par mois de l'année** (missions actives chaque mois, ligne) + **répartition par tranche** (barres : < 500 · 500-600 · 600-700 · > 700 €) + **par agence** quand « Toutes agences ». Clic sur une tranche → liste des collaborateurs concernés. |
  | **MARGE MOYENNE** (rose) | MCV moyenne = moyenne des (TJM−CJM)/TJM | « X % · seuil 30 % » | **Répartition par tranche** (barres : < 20 % rouge · 20-30 % orange · 30-40 % · > 40 % jade) + **liste triée des collaborateurs sous 30 %** (nom, client, TJM, CJM, marge, clic → volet) : c'est la liste d'action commerciale (renégocier / repositionner). Marge moyenne par mois de l'année en ligne. |
  Le détail TJM / Marge est une proposition (Nicolas n'avait pas d'avis) ; à ajuster après la 1re recette.
- **Conséquence sur l'onglet Missions (TDB)** : la dalle INTERCONTRAT, `ChartInter` et la liste interco
  **quittent le TDB** (qui garde EN MISSION · CA YTD · MARGE YTD). Le chargement `interco_imputations`
  spécifique au TDB est supprimé ; l'onglet Agence utilise les imputations chargées par `fetchAll`.
  Le composant carte est extrait en `KpiCards({cards, active, onSelect})` partagé par les deux onglets.

### 5.2 Tableau CDI (desktop)
Colonnes triables (`thCls` + `SortIcon`) : **Nom Prénom** · Agence · Partner · Entrée · Salaire · CJM ·
Mission (client — « fin JJ/MM ») · TJM · Marge · **Dispo** (badge). Tri par défaut : Dispo croissant
(les urgences en haut). Ligne : `border-t border-neutral-50 hover:bg-lemon-20 cursor-pointer`,
clic → volet.

### 5.3 Tableau Sous-traitants
**Nom Prénom** · Type (badge `Freelance` rose / `Sous-traitant` orange, styles `STATUT_STYLE` existants) ·
Agence · Commercial · Entrée · Mission · CJM · TJM · Marge · **Fin mission** (même badge que Dispo).

### 5.4 Mobile (`md:hidden`)
Cartes `bg-white border-2 border-neutral-200 p-3` : nom + badges (agence, état) / mission / TJM · marge.
`PAGE_SIZE` 50 mobile / 200 desktop + « Charger plus » (pattern existant).

### 5.5 Volet latéral collaborateur (`SidePanel` existant, `max-w-lg`)
- En-tête : nom, badges statut + agence + état Dispo, boutons `Modifier` (ouvre `ContactEditModal`) et
  `Ouvrir la fiche contact` (→ `ContactDetail`, navigation croisée avec retour).
- Sous-onglets (pattern `tabBtnCls` du volet Compte) :
  - **Mission** : mission en cours (client, projet, dates, TJM, CJM, marge %, marge €/jour), périodes
    (`mission_periods`), bouton `Ouvrir la mission` → `MissionDetail` en volet ; s'il n'y a pas de mission :
    état + lien « positionner sur un besoin » (V1 = simple lien vers l'onglet Besoins).
  - **Interco** (CDI seulement) : `IntercoEditor` existant (histogramme + saisie), total année et coût.
  - **Infos** : date d'entrée, date de sortie, salaire, CJM (+ mention « calculé » ou « manuel »),
    statut RH + depuis, partner/commercial, type presta — édition inline via `ContactEditModal`.

### 5.6 Formulaire (`ContactEditModal` / `AddContactModal`)
Nouvelle section **« Collaborateur »**, affichée uniquement si `statut ∈ CONSULTANT_STATUTS` :
`date_entree`, `date_sortie`, `salaire_annuel` (CDI) → CJM affiché en live, champ CJM éditable
(le modifier à la main coche `cjm_manuel`), bouton « recalculer depuis le salaire », `statut_rh` +
`statut_rh_depuis`, `type_presta` (ST), `manager_trigramme` (select `MANAGER_TRIGRAMMES`).
`+ Nouveau collaborateur` ouvre `AddContactModal` avec `statut` pré-rempli (`Consultant CDI` depuis
l'onglet CDI, `Freelance` depuis ST) et `agence` = filtre courant.

### 5.7 États vides
Texte italique muet, pattern existant : « Aucun collaborateur sur ce périmètre » / « Aucun sous-traitant en mission ».

---

## 6. Export Excel
- Bouton `Export Excel` → génère `Effectifs_{CDI|ST}_{agence}_{AAAA-MM-JJ}.xlsx` côté client via
  **SheetJS** (`xlsx` 0.18.x, UMD, chargé depuis unpkg comme React déjà). Chargement **lazy** au premier
  clic (pas d'impact sur le boot de la PWA).
- Feuille unique, colonnes = celles du tableau affiché (respecte filtres + tri), en-têtes en français,
  types natifs (dates, nombres, % marge), ligne de totaux/moyennes en bas (miroir de la ligne « COLLAB »
  de Pierre). Partner : export limité à son périmètre (même `useMemo`).

---

## 7. Alertes proactives (tâche CRM auto)

Déclencheur : au `fetchAll` (donc à chaque chargement de l'app par n'importe quel admin/commercial),
après calcul des champs §3.

Pour chaque collaborateur **non sorti** avec `missionEnCours` et `0 ≤ joursAvantDispo ≤ 60` :
- Titre : `⏳ Fin de mission {Prénom Nom} — {client} le {JJ/MM} (J-{n})`
  (CDI : « préparer la suite » ; ST : « renouvellement ou fin de contrat »).
- `mission_id` = mission, `contact_id` = collaborateur, `responsable` = `mission.responsable`
  (fallback `contact.responsable`, fallback profil courant), `statut='en_cours'`,
  `due_date` = prochain jour ouvré à **09:30** (règle « heure intelligente »),
  `notes` = « Alerte auto onglet Agence. TJM {x} · CJM {y} · marge {z} % ».
- **Idempotence** : pas de création s'il existe déjà une tâche avec `mission_id` identique et titre
  commençant par `⏳ Fin de mission` (quel que soit son statut, y compris `fait`). Une mission = une
  alerte, jamais de re-création si le commercial la clôture.
- Si la date de fin de mission est **repoussée** au-delà de 60 j alors qu'une alerte `a_faire/en_cours`
  existe → l'alerte est passée en `fait` avec note « mission prolongée au JJ/MM ».
- Les alertes remontent naturellement dans l'onglet Tâches, le brief du matin de Jules et Outlook.
- Pas d'alerte pour un partner (il ne lance pas la création ; il voit celles de ses consultants si RLS le permet).

---

## 8. Import initial — `bin/crm-import-collab.py` (repo Jules)

Source : `~/Library/CloudStorage/OneDrive-NeuronesIT/Upgrade CODIR - TACE - TACE/Point_COLLAB-UPGRADE.xlsx`,
feuille `TACE`. Blocs : « Régies » (CDI), « Forfait » (CDI), « (Freelance…) » (ST). Bloc « interne » ignoré.

1. **Dry-run** (`--dry-run`, défaut) → rapport markdown `journal/import-collab-dryrun.md` :
   - Match par `nom` + `prenom` normalisés (accents/casse/espaces) sur `contacts` avec `statut ∈ CONSULTANT_STATUTS`
     puis sur tous statuts ; agence en départage. Sorties : ✅ matché (id, diff des champs qui changent) ·
     ➕ à créer · ⚠️ ambigu (plusieurs candidats) · ❓ trigramme inconnu.
   - Pour chaque ligne : `date_entree`, `salaire_annuel = round(CJ × 215 / 1,7)` (CDI), `cjm = CJ` (ST),
     `manager_trigramme`, `type_presta` (« Portage » dans le nom → `sous_traitant`, sinon `freelance`),
     `agence`. Mission : si aucune mission `En cours` au CRM pour ce contact et que TJM + date de fin sont
     présents → proposition de création `missions` (client parsé depuis « Démarrage chez X le … », statut
     `En cours`, `tjm`, `cjm`, `date_fin_mission`, `date_debut_mission` parsée si présente, `responsable`
     = commercial du trigramme ou `Pierre Sotiropoulos`) — listée à part pour validation.
2. Nicolas valide (corrections éventuelles des ambigus dans un petit fichier `overrides.json`).
3. **Apply** (`--apply`) via l'API Supabase (clé service dans l'env Jules), journalisé dans
   `journal/import-collab-apply.md`. Aucun DELETE. Re-jouable (idempotent sur les mêmes valeurs).

---

## 9. Performance
- Aucune requête ajoutée : `useMemo` sur `[vContacts, vMissions, intercos, partnerConsultants, filtres]`.
- Tableau tronqué à `PAGE_SIZE` ; export sur la liste complète filtrée.
- SheetJS lazy-loadé (≈ 400 Ko) uniquement au clic Export.
- `fetchAll` charge déjà `interco_imputations` pour l'année ; vérifier que la limite mobile `L` n'ampute
  pas les contacts CDI (sinon requête dédiée `statut in CONSULTANT_STATUTS` sans limite : ~110 lignes).

---

## 10. Tests / recette
- **Calculs** : jeu de 6 cas (mission >60 / ≤60 / ≤30 / dépassée / sans mission CDI / arrêt maladie) →
  badge + tri attendus. CJM auto 61 000 € → 482,33 ; override manuel conservé après re-sauvegarde.
- **Droits** : « Voir comme » Majo → onglet visible, uniquement ses 7 consultants, pas de filtre agence,
  pas de bouton Nouveau. Amel (commercial Paris) → France entière, filtre pré-réglé Paris, création OK.
- **Alertes** : consultant à J-45 → 1 tâche créée à 09:30 prochain jour ouvré ; recharger l'app → 0 doublon ;
  repousser la fin à J+120 → tâche passée en `fait`.
- **Export** : fichier ouvert dans Excel, dates typées, % marge, ligne moyennes = ligne « COLLAB » de Pierre
  à ± arrondi.
- **Import** : dry-run sur l'Excel du 14/09 → 61 + 1 + 42 lignes traitées, 0 écriture ; apply → recompte
  effectif onglet = 104 actifs.
- Déploiement : règle **local d'abord** (`python3 -m http.server`) + capture + OK Nicolas, puis SQL collé
  dans Supabase, puis push `main` par Nicolas.

---

## 11. Fichiers touchés
- `index.html` : `TABS`/`TAB_COLORS`, liste blanche partner, `CONTACTS` select (`fetchAll`), nouveau bloc
  `tab==='agence'` (`TabAgence`, `CollabDetail`, `KpiCards` partagé + dalles `ChartEffectif`/`ChartInter`/
  `ChartTjm`/`ChartMarge`, `exportEffectifs`), `TabTDB` allégé (dalle interco retirée), section Collaborateur
  dans `ContactEditModal`/`AddContactModal`, routine `ensureAlertesDispo`.
- `db/20_agence.sql` (nouveau).
- `bin/crm-import-collab.py` (repo Jules, nouveau).
- `DEPLOY.md` : ligne migration 20.
- MCP `upgrade-crm` : `crm_set_cjm` pose `cjm_manuel=true` ; `crm_update_contact` accepte les nouvelles
  colonnes (bump version + rebuild `.mcpb`).
