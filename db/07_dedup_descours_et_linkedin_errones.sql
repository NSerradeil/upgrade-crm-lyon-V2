-- ══════════════════════════════════════════════════════════════════════
-- 07 — ① Nettoyage des LinkedIn erronés  ② Fusion Descours & Cabaud
-- Date : 27/07/2026 · GO Nicolas
-- Détail de l'audit : SPECS_CRM/AUDIT_doublons_comptes_contacts.md
-- ══════════════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════════════
-- ① LES 6 CONTACTS QUI PORTENT LE LINKEDIN DE QUELQU'UN D'AUTRE
--
-- Risque opérationnel : écrire au mauvais interlocuteur depuis le compte
-- de Nicolas. Les 6 fiches sont des ids consécutifs (129-134, Elcia/Cegid)
-- pointant vers des ids 442-510 → décalage de colonnes à l'import.
-- On VIDE le champ plutôt que deviner la bonne URL (décision Nicolas).
--
--   129 Stéphanie ROBIN      -> pointait vers Juliette GÉRARD    (442)
--   130 Yolaine EUDELINE     -> pointait vers Lucien GIMEL       (451)
--   131 Marie-Mathilde CARPIN-> pointait vers Etienne LAMANDE    (452)
--   132 Céline VERNAY        -> pointait vers Laurent HERVAUD    (453)
--   133 Lamia JAAFAR         -> pointait vers Inès LASSAUVAGEUX  (454)
--   134 Julie MERVEILLE      -> pointait vers Damien JAMET       (510)
-- ══════════════════════════════════════════════════════════════════════

-- AVANT : garder la trace de ce qu'on efface
SELECT id, prenom, nom, groupe, linkedin FROM contacts
WHERE id IN (129,130,131,132,133,134,1869) ORDER BY id;

UPDATE contacts SET linkedin = NULL
WHERE id IN (129,130,131,132,133,134);
-- Attendu : UPDATE 6

-- Bonus même famille : URL vide "linkedin.com/in/" (Mathieu KERHARO, Qonto)
UPDATE contacts SET linkedin = NULL WHERE id = 1869;
-- Attendu : UPDATE 1

-- NOTE : id=23 David GOUTAGNEUX (Volvo) -> /in/emosign/ n'est PAS touché.
-- Slug d'agence, propriétaire non identifié : à vérifier à la main avant d'effacer.


-- ══════════════════════════════════════════════════════════════════════
-- ② FUSION DESCOURS & CABAUD — 206 + 294  ──>  325
--
-- Canon = 325 « Descours & Cabaud » : orthographe correcte, et porte la
-- mission Design System en cours (besoin « Profil proposé », Loïc Festas).
--
-- ⚠️ ORDRE IMPORTANT : `besoins.compte` et `contacts.groupe` référencent le
-- compte par son NOM en texte libre, pas par son id. Il faut donc repointer
-- les libellés AVANT de supprimer les fiches, sinon les besoins et contacts
-- restent rattachés à un nom qui n'existe plus.
-- (C'est exactement la faiblesse structurelle décrite au §4 de l'audit.)
-- ══════════════════════════════════════════════════════════════════════

-- AVANT : état des lieux
SELECT id, nom, statut, responsable FROM comptes WHERE id IN (206,294,325);
SELECT id, compte, statut, titre FROM besoins WHERE compte ILIKE '%descours%';
SELECT id, prenom, nom, groupe FROM contacts WHERE groupe ILIKE '%descours%' ORDER BY id;
-- Attendu : 3 comptes · 3 besoins (2 libellés) · 7 contacts (3 libellés)
-- Aucune mission rattachée (vérifié : missions.compte_id ne vaut jamais 206/294/325).

-- ─── 2a. Repointer les besoins (3 lignes) ───
UPDATE besoins SET compte = 'Descours & Cabaud'
WHERE compte ILIKE '%descours%' AND compte <> 'Descours & Cabaud';
-- Attendu : UPDATE 1  (le besoin « PO / AMOA Data » sur 'Descours et Cabaud')

-- ─── 2b. Repointer les contacts (7 lignes) ───
UPDATE contacts SET groupe = 'Descours & Cabaud'
WHERE groupe ILIKE '%descours%' AND groupe <> 'Descours & Cabaud';
-- Attendu : UPDATE 3  (Leila PAGNIOU 109, Jérôme GIBAUT 143, Magalie ARTUS 144)

-- ─── 2c. Supprimer les 2 fiches en trop ───
-- Les 3 fiches sont vides (secteur/ville/site_web/notes tous NULL) : aucune
-- information à rapatrier vers le canon avant suppression.
DELETE FROM comptes WHERE id IN (206,294);
-- Attendu : DELETE 2


-- ══════════════════════════════════════════════════════════════════════
-- ③ VÉRIFICATIONS FINALES
-- ══════════════════════════════════════════════════════════════════════

-- Plus qu'une fiche Descours
SELECT id, nom, statut, responsable FROM comptes WHERE nom ILIKE '%descours%';
-- Attendu : 1 ligne — 325 « Descours & Cabaud »

-- Tous les besoins et contacts pointent sur le bon libellé
SELECT DISTINCT compte FROM besoins WHERE compte ILIKE '%descours%';
SELECT DISTINCT groupe FROM contacts WHERE groupe ILIKE '%descours%';
-- Attendu : 'Descours & Cabaud' et rien d'autre, dans les deux cas

-- Les 7 LinkedIn nettoyés
SELECT id, prenom, nom, linkedin FROM contacts
WHERE id IN (129,130,131,132,133,134,1869) ORDER BY id;
-- Attendu : linkedin = NULL partout


-- ══════════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ══════════════════════════════════════════════════════════════════════
-- LinkedIn (les 6 URLs étaient fausses — un rollback ne se justifie que si
-- on découvre qu'elles étaient bonnes) :
--   UPDATE contacts SET linkedin='https://www.linkedin.com/in/jugerard/' WHERE id=129;
--   UPDATE contacts SET linkedin='https://www.linkedin.com/in/lucien-gimel-bb0a749a/' WHERE id=130;
--   UPDATE contacts SET linkedin='https://www.linkedin.com/in/etienne-lamande/' WHERE id=131;
--   UPDATE contacts SET linkedin='https://www.linkedin.com/in/laurent-hervaud-268647106/' WHERE id=132;
--   UPDATE contacts SET linkedin='https://www.linkedin.com/in/ineslassauvageux/' WHERE id=133;
--   UPDATE contacts SET linkedin='https://www.linkedin.com/in/damien-jamet-aab71165/' WHERE id=134;
--   UPDATE contacts SET linkedin='https://www.linkedin.com/in/' WHERE id=1869;
--
-- Comptes supprimés (tous champs étaient NULL sauf nom/statut/responsable) :
--   INSERT INTO comptes (id,nom,statut,responsable) VALUES
--     (206,'Descours& Cabaud','Prospect','Nicolas Serradeil'),
--     (294,'Descours et Cabaud','Prospect','Nicolas Serradeil');
--   UPDATE besoins  SET compte='Descours et Cabaud' WHERE id='1f72a85f-8a24-4e1f-ba53-c357c3457e51';
--   UPDATE contacts SET groupe='Descours& Cabaud'   WHERE id=109;
--   UPDATE contacts SET groupe='Descours et Cabaud' WHERE id IN (143,144);
