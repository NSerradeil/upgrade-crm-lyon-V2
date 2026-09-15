# SPEC — Sortie des effectifs : le consultant redevient « Candidat »

**Demande Nicolas, 15/09/2026** — cas Alexine SEMENT : sortie des effectifs actée (mission
Société Générale « Terminée » le 30/08/2026, `date_sortie` renseignée), mais sa fiche porte
toujours le badge **CONSULTANT CDI**. Elle doit rester dans Comptes & Contacts (c'est normal),
mais son statut doit **repasser à `Candidat`** : elle retourne au vivier, replaçable.

**Fichiers cibles :** `db/24_sortie_effectif.sql` (nouveau) · `agence-calc.js` · `index.html`
**Tests :** `tests/agence-calc.test.mjs`
**Déploiement :** migration SQL à coller dans Supabase **AVANT** de pousser l'app (cf. `DEPLOY.md`).

---

## 1. Le piège à connaître avant de coder

La règle « sorti → statut Candidat » est juste sur le fond, mais **appliquée naïvement elle
casse trois calculs de l'onglet Agence**, parce que tout le périmètre Agence est filtré **par
`contacts.statut`** :

```js
// index.html ~3449
const statuts = mode==='cdi' ? CDI_STATUTS : (mode==='st' ? ST_STATUTS : CONSULTANT_STATUTS_AGENCE);
return contacts.filter(c => statuts.includes(c.statut)).map(...)
```

Si le statut bascule sur `Candidat`, la personne **disparaît de `collabs`**, et avec elle :

| Calcul | Où | Ce qui casse |
|---|---|---|
| **Taux d'intercontrat historique** | `agence-calc.js:196` → `intercoStats(cdisPourInterco,…)` | Le commentaire du code le dit noir sur blanc : « `cdis` doit contenir **TOUS les CDI du périmètre, sortis compris** ». Sinon les jours d'interco déjà consommés par la personne s'effacent rétroactivement → taux annuel faussé, et donc l'objectif 5 % / malus 8 % avec. |
| **Sorties du mois / de l'année** | `arriveesSortiesParMois` + badge « Sorti·es (n) » | Une sortie CDI se compte sur `date_sortie` d'un membre de `collabs`. Plus personne dans `collabs` → **barre à 0, total faux**. Le commentaire ligne 3517 prévient déjà du même piège. |
| **Effectif cumulé fin de mois** | `arriveesSortiesParMois.cumul` | Idem : l'historique des mois passés perd la personne, la courbe se déforme rétroactivement. |

👉 **Conclusion de conception :** on ne peut pas se contenter de changer le statut. Il faut
**dissocier deux notions** qui étaient jusqu'ici confondues dans `contacts.statut` :

- **le statut commercial d'aujourd'hui** (`Candidat`) — ce qui s'affiche, ce qui pilote le vivier ;
- **la nature du lien d'effectif qu'on a eu avec la personne** (« c'était un CDI »)
  — ce dont l'historique Agence a besoin, pour toujours.

---

## 2. Décision produit

### 2.1 Le concept : « ancien collaborateur »

Un **ancien collaborateur** = un contact qui :
- a un `date_sortie` renseigné et **échu** (`<= aujourd'hui`) ;
- a repassé son `statut` à **`Candidat`** ;
- **conserve** ses champs collaborateur (`date_entree`, `date_sortie`, `salaire_annuel`,
  `type_presta`, `manager_trigramme`, `agence`) ;
- porte une **nouvelle colonne `ancien_statut`** qui mémorise ce qu'il était (`Consultant CDI`,
  `Freelance` ou `Prestataire`).

`ancien_statut` est la clé de voûte : c'est ce qui permet à l'onglet Agence de continuer à
compter la personne dans son **historique** sans la compter dans son **effectif du jour**.

### 2.2 Ce qu'on NE fait PAS

- ❌ Pas de nouveau statut « Ancien collaborateur » dans `STATUTS_CONTACT` — Nicolas veut
  explicitement `Candidat`, pour qu'elle réapparaisse dans le vivier et les recherches candidat.
- ❌ Pas d'archivage vers une table séparée.
- ❌ **Pas de bascule automatique pour les freelances / sous-traitants sur fin de mission.**
  Un free/ST n'a pas de contrat d'effectif : « Freelance » décrit sa **nature**, pas un lien avec
  nous. Il sort déjà de l'effectif tout seul quand sa mission se termine (règle du 14/09 :
  effectif ST = mission `En cours`/`New`). La bascule ne se déclenche donc que si quelqu'un
  renseigne **explicitement** une `date_sortie` sur sa fiche.

### 2.3 Le déclencheur

**`date_sortie` renseignée et échue + statut ∈ {Consultant CDI, Freelance, Prestataire}
→ `ancien_statut := statut` puis `statut := 'Candidat'`.**

Réversible : si on efface la `date_sortie` d'un ancien collaborateur (erreur de saisie,
réembauche), le statut d'origine est restauré depuis `ancien_statut`, qui est remis à `NULL`.

---

## 3. Implémentation

### 3.1 DB — `db/24_sortie_effectif.sql`

1. `alter table contacts add column if not exists ancien_statut text` (+ CHECK sur les 3 valeurs).
2. **Trigger** `BEFORE INSERT OR UPDATE` : applique la bascule et la réversion ci-dessus.
   Le trigger est le bon niveau parce qu'il couvre **toutes** les portes d'écriture — l'app,
   le MCP, l'import `crm-import-collab.py`, le SQL Editor — et pas seulement le formulaire.
3. **Backfill** : bascule les collaborateurs déjà sortis (c'est le patch correctif Alexine).

⚠️ **Limite du trigger :** une `date_sortie` posée dans le **futur** ne déclenche rien le jour J
(aucun UPDATE n'a lieu à cette date). C'est le rattrapage 3.3 qui s'en charge.

### 3.2 `agence-calc.js` — un périmètre historique, un effectif du jour

Ajout d'une fonction unique, `statutAgence(c)`, qui répond à « qu'est-ce que cette personne
est/était pour l'agence ? » :

```js
const estAncienCollab = (c) => c.statut === 'Candidat' && !!c.ancien_statut && !!c.date_sortie;
const statutAgence    = (c) => (estAncienCollab(c) ? c.ancien_statut : c.statut);
```

Tous les filtres de périmètre Agence passent de `c.statut` à `AgenceCalc.statutAgence(c)`,
et `computeCollab` calcule `isCdi` dessus. Conséquence : un ancien CDI **revient dans `collabs`**,
donc dans l'interco historique et dans les mouvements — mais il porte `sorti === true`, donc :

- il reste **masqué par défaut** dans la liste (déjà géré : la puce « Sorti·es » le dévoile) ;
- il est **exclu des KPI du jour** (déjà géré : `act = collabs.filter(k => !k.sorti)`).

**Les compteurs d'effectif ne bougent pas** : `nbCdi`, `nbSt` et le badge de l'onglet
(`effectifActif`) lisent le `statut` **brut** + `date_sortie`. Un ancien collaborateur a
`statut = 'Candidat'` → exclu des deux côtés. **L'onglet Agence affiche toujours 112.**

### 3.3 `index.html`

| # | Endroit | Changement |
|---|---|---|
| a | `ContactEditModal.save` (~1419) | La branche « sortie du périmètre agence » **efface** `date_entree`, `date_sortie`, `type_presta`, `manager_trigramme`… dès que le statut quitte les statuts consultant. Il faut l'**exempter** quand la cible est un ancien collaborateur (`Candidat` + `date_sortie`), sinon la bascule se saborde elle-même en effaçant la `date_sortie` qui la justifie. |
| b | `AgenceTab.collabs` (~3449) | `statuts.includes(c.statut)` → `statuts.includes(AgenceCalc.statutAgence(c))`. |
| c | Alertes fin de mission (~8908) | Même substitution, pour que les alertes ne se rouvrent pas sur un sorti. |
| d | `ContactDetail` (~2062) | Bandeau **« ANCIEN COLLABORATEUR — CDI, sorti le JJ/MM/AAAA »** sous le badge `CANDIDAT`, pour que la fiche dise pourquoi elle porte encore des données collaborateur. |
| e | Rattrapage au chargement (~8908) | Sur le modèle de l'auto-update des missions échues : au chargement, tout contact dont la `date_sortie` est arrivée à échéance et qui est encore au statut consultant est basculé. Couvre la limite du trigger sur les dates futures. |

---

## 4. Recette

1. **Migration appliquée** : `select ancien_statut from contacts limit 1` ne renvoie plus d'erreur.
2. **Alexine SEMENT** : fiche → badge `CANDIDAT` + bandeau « ancien collaborateur — CDI, sorti le
   30/08/2026 ». Ses date d'entrée / de sortie sont **toujours là**.
3. **Onglet Agence** : le badge affiche **toujours 112** (65 CDI + 47 SST). Aucun mouvement.
4. **Non-régression interco** : le taux d'intercontrat annuel **est identique avant/après**.
   C'est LE test qui compte — c'est ce que la bascule naïve aurait cassé.
5. **Non-régression sorties** : puce « Sorti·es » → Alexine y figure ; le graphe « Effectif et
   mouvements » compte bien une sortie en **août 2026**.
6. **Réversion** : effacer sa `date_sortie` la repasse `Consultant CDI` et vide `ancien_statut`.
7. **Free/ST** : un freelance dont la mission passe « Terminée » **reste `Freelance`**
   (pas de bascule sans `date_sortie` explicite).

---

## 5. Hors périmètre — les 8 fiches Paris à clarifier

L'écart TACE ↔ CRM du 15/09 a sorti 9 fiches Paris (responsable Amel Benzai) présentes au CRM
et absentes du fichier TACE. Après le clean, il en reste **8 sans `date_sortie`**, dont 7 ont
pourtant une mission déjà passée « Terminée » :

| Contact | Statut | Dernière mission | Fin |
|---|---|---|---|
| KONYAKHINA Olga | Prestataire | AA (Via Colombus) | 28/02/2026 |
| LECUME Clara | Freelance | Axa | 20/03/2026 |
| KHOUM Julie | Freelance | Accor | 06/07/2026 |
| GAYRAUD Natacha | Freelance | SNCF Connect | 07/07/2026 |
| MOUMNI Nabil | Freelance | AXA | 19/07/2026 |
| JULIEN Timothée | Freelance | Bouygues | 30/07/2026 |
| SERRA Kevin | Freelance | — (mission délink) | — |
| HARRIBEY Marie-Noémie | **Consultant CDI** | Pluxee | **encore « En cours »** |

Le trigger ne les touchera pas (pas de `date_sortie`). **Décision métier attendue d'Amel**, deux
cas distincts : les free/ST sont déjà hors effectif et n'ont rien à faire (leur statut décrit leur
nature) ; **HARRIBEY Marie-Noémie est le seul vrai sujet** — CDI avec une mission encore ouverte,
donc soit elle est bien à l'effectif et il manque au TACE, soit elle est sortie et il manque
sa `date_sortie` + la clôture de sa mission.
