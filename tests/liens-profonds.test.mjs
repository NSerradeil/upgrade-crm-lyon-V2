// tests/liens-profonds.test.mjs : liens profonds du CRM pour la Jules app (18/11/2026).
// #besoin=<uuid>, #contact=<id>, #compte=<id>, #mission=<id> ; l'ancien #/contact/<id> reste lu.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
function extrait(nom) {
  const m = html.match(new RegExp(`\\nfunction ${nom}\\(([\\s\\S]*?)\\n\\}\\n`));
  if (!m) throw new Error(`${nom} introuvable dans index.html`);
  return m[0];
}
const lienDepuisHash = new Function(`${extrait('idContactDepuisHash')}\n${extrait('lienDepuisHash')}\nreturn lienDepuisHash;`)();

test('liens profonds : formats reconnus', () => {
  assert.deepEqual(lienDepuisHash('#besoin=356539BF-57fc-4de8-ae84-3eab2d5bbd5a'), { type: 'besoin', id: '356539bf-57fc-4de8-ae84-3eab2d5bbd5a' });
  assert.deepEqual(lienDepuisHash('#contact=2793'), { type: 'contact', id: '2793' });
  assert.deepEqual(lienDepuisHash('#compte=687/'), { type: 'compte', id: '687' });
  assert.deepEqual(lienDepuisHash('#mission=0207'), { type: 'mission', id: '207' });
  assert.deepEqual(lienDepuisHash('#/contact/1234'), { type: 'contact', id: '1234' });
});

test('liens profonds : tout le reste est ignoré', () => {
  for (const h of ['', null, undefined, '#', '#contact=', '#contact=abc', '#besoin=12', '#besoin=356539bf-57fc-4de8-ae84',
    '#mission=12;alert(1)', '#compte=1&x=2', '#type=recovery&access_token=x', '#access_token=abc', '#tache=12', '#contact=1234567890123456'])
    assert.equal(lienDepuisHash(h), null, String(h));
});
