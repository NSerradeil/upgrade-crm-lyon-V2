# AUDIT — Doublons comptes / contacts + qualité des rattachements
**CRM Upgrade Lyon V2** · 27/07/2026 · lecture seule, aucune modification appliquée

Demandé par Nicolas après le fix du filtre responsables (« je pense qu'il y en a »).
Base : 401 comptes, 1755 contacts, 260 besoins.

---

## 1. Comptes en doublon — 11 groupes, 23 fiches

### 1a. À FUSIONNER (vraies redondances, 7 groupes)

| Groupe | ids | Détail |
|---|---|---|
| **Descours & Cabaud** | **206 / 294 / 325** | 3 variantes d'écriture. 325 porte 2 besoins, 294 en porte 1, 206 aucun. Canon = **325** (orthographe correcte + mission DS en cours) |
| HomeServe | 107 / 150 | « HomeServe France » vs « Homeserve » |
| Boiron | 132 / 377 | « Boiron France » vs « Boiron » |
| Volvo | 342 / 360 | « Volvo » vs « Volvo Group » |
| Convivio | 71 / 191 | « Convivio » vs « Groupe Convivio » |
| BPCE | 52 / 231 | ⚠️ responsables différents : 52 Nicolas, 231 Camille |
| Generali | 75 / 176 | ⚠️ responsables différents : 75 Anne-Claire, 176 Camille |

Les 2 derniers sont à trancher entre commerciaux avant fusion (qui garde le compte).

### 1b. À NE PAS FUSIONNER (entités distinctes — vérifié)

| Groupe | ids | Pourquoi |
|---|---|---|
| **Groupe ADP / ADP** | 80 / 170 | ⚠️ piège : Groupe ADP = Aéroports de Paris ; ADP = Automatic Data Processing (paie). Deux sociétés sans rapport. |
| Engie / Engie Digital | 64 / 391 | Engie Digital est une entité propre, et 391 est **Client actif** (≠ prospect). |
| APRIL / APRIL International | 70 / 309 | Filiale distincte. |
| TF1+ / Groupe TF1 | 99 / 358 | TF1+ = la plateforme streaming. À trancher, mais responsables différents (Amel / Camille). |

---

## 2. Contacts en doublon

### 2a. Email identique — 5 groupes, doublon certain

| Personne | ids | Note |
|---|---|---|
| Sophie BIGAY | 1340 / 1718 | groupe « VYV3 » vs « VYV » |
| Pauline GRANGE | 1339 / 1716 | idem |
| Julien BES (Alptis) | 55 / 1461 | rôles divergents : « Manager IT/CP » vs « Head of Product » |
| Ndeye Thilo DIOP | 1957 / 1990 | statuts divergents : Candidat vs Freelance |
| Julie DÉSORMONTS | 1345 / 1723 | accent + espace double |

### 2b. Même URL LinkedIn (hors erreurs de saisie) — 6 groupes certains

Benjamin HAREAU 539/1755 · Pierre COTIS 1967/1972 · Savinien LUCBEREILH 1510/1516 ·
Gregory GNOS 1405/1556 · Kévin MORLAND 1407/1559 (+ groupe APRIL vs APRIL International).

### 2c. Même prénom + nom — 43 groupes / 87 fiches

Majorité = vrais doublons créés en 2 passes (une fiche avec email, l'autre avec le rôle).
Exemples : Pierre GUELEN **×3** (1259/1466/1670), Bruno MATHIS, Léonard MENUT,
Mathieu CHESNEAU, Maria MATHIEU, Julien CLEMENT, Mickael GRANET, Thomas DE CRÉCY.

⚠️ **Cas à ne PAS fusionner sans vérifier** :
- **Antoine VERMOREL** 172 (Framatome, Nicolas) / 958 (Saint-Gobain, Camille) → soit un
  changement d'employeur, soit deux personnes. À confirmer avant de toucher.
- **Yvan MORELLI** 1586 (Nicolas) / 2044 (Louis Py) → même compte CA-TS, 2 responsables.
- **Adrien TICHOUX** 808 (candidat, Camille) / 1729 (prospect CEGEDIM, Anne-Claire) →
  candidat devenu prospect ? deux rôles, deux propriétaires.
- **Franck NGNODJOM** 417 (candidat) / 1498 (prospect) → même personne, deux natures.
- **Mariame KEÏTA** 775 (Camille) / 1790 (Anne-Claire) → deux commerciales sur la même candidate.

Liste complète des 43 groupes : `scratchpad/dups_contacts.json`.

---

## 3. 🔴 PLUS GRAVE QUE LES DOUBLONS — 6 contacts portent le LinkedIn de quelqu'un d'autre

Découvert en croisant les URLs. Ce n'est pas un doublon : c'est une **fiche qui pointe vers
le profil d'une autre personne réelle, déjà présente dans la base**. Risque direct : écrire
au mauvais interlocuteur depuis le compte de Nicolas.

| Fiche | ...pointe vers |
|---|---|
| 129 Stéphanie ROBIN (Elcia) | Juliette GÉRARD (442, Backmarket) |
| 130 Yolaine EUDELINE (Elcia) | Lucien GIMEL (451, Betclic) |
| 131 Marie-Mathilde CARPIN (Elcia) | Etienne LAMANDE (452, Betclic) |
| 132 Céline VERNAY (Cegid) | Laurent HERVAUD (453, Betclic) |
| 133 Lamia JAAFAR (Cegid) | Inès LASSAUVAGEUX (454, Betclic) |
| 134 Julie MERVEILLE (Cegid) | Damien JAMET (510, Ubisoft) |

Les 6 fiches sont des ids **consécutifs 129-134** (Elcia/Cegid) et pointent vers des ids
**442-510** : ça ressemble à un décalage de colonnes lors d'un import, pas à 6 fautes de frappe.
**Recommandation : vider le champ `linkedin` sur ces 6 fiches** plutôt que deviner la bonne URL.

À vérifier à la main (2 cas non concluants) :
- id=23 David GOUTAGNEUX (Volvo) → `/in/emosign/` — slug d'agence, probablement faux.
- id=1869 Mathieu KERHARO (Qonto) → `/in/` — URL vide, à nettoyer.

### Autres saletés dans le champ `linkedin` (1001 fiches remplies)
- **962** URL de profil cohérentes ✅
- **20** URL de *recherche* LinkedIn au lieu d'un profil (ids 1531-1534, 1908, 1922-1936)
- **6** valeurs qui ne sont pas des URLs : `https://Data Product Manager` (915),
  `https://NC` (1772), une adresse mail (1982), un lien Outlook (1792), un lien ATS Tellent (1694, 1781)

---

## 4. La cause structurelle — pourquoi les doublons vont revenir

Même famille de défaut que le bug du filtre responsables qu'on vient de corriger : **les
rattachements se font par texte libre, pas par identifiant.**

- `besoins.compte` = **le nom du compte en texte** (pas de FK). 87 libellés distincts, dont
  **27 ne correspondent à aucune fiche compte** : `CATS` (14 besoins), `SNCF Connect` (7),
  `Crédit Agricole Technologies et Services` (5), `CA-TS` (3), `BNP ITG` + `BNP ITG ` (espace
  final, 2 buckets), `ENGIE` vs `Engie`, `Edenred` vs `Edenred `…
- `contacts.groupe` = idem. 426 libellés, dont **55 sans fiche compte** : `Axa`/`AXA`,
  `Bouygues Telecom`/`Bouygues Télécom`, `CDISCOUNT`, et des valeurs qui ne sont pas des
  comptes du tout (`Candidat` 16 fois, `Freelance` 4 fois).
- `missions.compte_id` est, lui, un **vrai identifiant numérique**. C'est le bon modèle.

Conséquence : fusionner les fiches doublons nettoie l'affichage mais ne règle rien au fond.
Tant que `besoins.compte` et `contacts.groupe` sont du texte saisi librement, chaque nouvelle
orthographe recrée un silo — et un compte fusionné laisse derrière lui des besoins rattachés
à un nom qui n'existe plus.

**Reco d'ordre de traitement**
1. Les 6 LinkedIn erronés (risque opérationnel immédiat, 1 UPDATE)
2. Descours & Cabaud 206/294/325 (bloque la mission DS en cours)
3. Les doublons contacts à email/LinkedIn identique (certains, mécaniques)
4. Arbitrage des cas à responsables différents (BPCE, Generali, TF1, Vermorel, Morelli, Keïta)
5. Chantier de fond : passer `besoins.compte` et `contacts.groupe` en `compte_id`, avec
   sélecteur dans l'app — c'est le seul moyen d'arrêter la production de doublons
