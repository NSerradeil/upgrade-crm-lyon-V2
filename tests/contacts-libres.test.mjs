// tests/contacts-libres.test.mjs : contacts libres d'accès (06/11/2026, db/61 et db/62).
// Un contact n'a plus de propriétaire qui bloque : tout commercial (admin ou commercial) le modifie, le sort de
// « Ne pas recontacter », en change le référent. Les comptes gardent la règle « responsable ou admin ».
// Fonctions extraites d'index.html, comme tests/prospect-pipeline.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

process.env.TZ = 'Europe/Paris';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  for (const re of [new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`),
                    new RegExp(`\\nconst ${nom} ?= ?[^\\n]*;\\n`),
                    new RegExp(`\\nconst ${nom} = \\{[\\s\\S]*?\\n\\};\\n`)]) {
    const m = html.match(re);
    if (m) return m[0];
  }
  throw new Error(`${nom} introuvable dans index.html`);
}
const NOMS = ['DEFAULT_TASK_TIME', 'combineDT', 'PROSPECT_ETAPES', 'PROSPECT_ETAPES_ACTIVES', 'PROSPECT_ETAPES_SORTIE',
              'prospectEtapeOuDefaut', 'prospectEtapeAccepteDate', 'prospectEtapeRequiert', 'prospectTacheLibelle', 'prospectTacheEcheance',
              'prospectReveilPreset', 'prospectPatchEtape', 'prospectTachePayload',
              'CAMPAGNE_MOTIF_PERTE_PROFIL', 'CAMPAGNE_LIBELLES_SORTIE', 'campagneEstProspection', 'campagneEffetSortie',
              'campagneJourOuvreSuivant', 'campagneSortiePlan',
              'peutAgirSurContact', 'peutTransferer'];
const API = new Function(`${NOMS.map(extrait).join('\n')}\nreturn {${NOMS.join(',')}};`)();
const { peutAgirSurContact, peutTransferer, campagneSortiePlan } = API;

const ADMIN = { nom: 'Nicolas Serradeil', role: 'admin' };
const CAMILLE = { nom: 'Camille Salinson', role: 'commercial' };
const PARTNER = { nom: 'Maria-Jose Paquelier', role: 'partner' };
const CONTACT_DE_LOUIS = { id: 12, prenom: 'Jean', nom: 'DUPONT', statut: 'Prospect', responsable: 'Louis Py' };
const COMPTE_DE_LOUIS = { id: 5, nom: 'ACME', responsable: 'Louis Py' };

test('peutAgirSurContact : admin et commercial oui, partner non', () => {
  assert.equal(peutAgirSurContact(ADMIN), true);
  assert.equal(peutAgirSurContact(CAMILLE), true);
  assert.equal(peutAgirSurContact(PARTNER), false);
  assert.equal(peutAgirSurContact(null), false);
  assert.equal(peutAgirSurContact({ nom: 'X', role: 'consultant' }), false);
});

test('peutTransferer : contact d un collegue transferable par un commercial, compte d un collegue non', () => {
  assert.equal(peutTransferer(CAMILLE, CONTACT_DE_LOUIS, 'contact'), true);
  assert.equal(peutTransferer(CAMILLE, COMPTE_DE_LOUIS, 'compte'), false);
  assert.equal(peutTransferer(CAMILLE, { ...COMPTE_DE_LOUIS, responsable: 'Camille Salinson' }, 'compte'), true);
  assert.equal(peutTransferer(ADMIN, COMPTE_DE_LOUIS, 'compte'), true);
  assert.equal(peutTransferer(PARTNER, CONTACT_DE_LOUIS, 'contact'), false);
  assert.equal(peutTransferer(CAMILLE, null, 'contact'), false);
});

test('plan RDV planifie : la tache va a l auteur de la sortie, pas au referent', () => {
  const ctx = { campagne: 'Prospection DSI Lyon', aujourdhui: '2026-09-29', responsable: 'Camille Salinson' };
  const p = campagneSortiePlan('converti', { ...CONTACT_DE_LOUIS, etape_prospect: 'Contacté' }, ctx);
  assert.equal(p.tache.responsable, 'Camille Salinson');
  // Sans auteur connu, repli sur le référent.
  const p2 = campagneSortiePlan('converti', { ...CONTACT_DE_LOUIS, etape_prospect: 'Contacté' }, { ...ctx, responsable: '' });
  assert.equal(p2.tache.responsable, 'Louis Py');
});
