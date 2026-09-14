// tests/check-babel.mjs — compile le bloc <script type="text/babel"> d'index.html avec Babel standalone
// (même moteur que le navigateur) pour attraper une SyntaxError AVANT de recharger la page.
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
let Babel;
try { Babel = require('@babel/standalone'); }
catch { console.error('npm i -g @babel/standalone  (ou: npm i --no-save @babel/standalone dans le repo)'); process.exit(2); }
const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const m = html.match(/<script type="text\/babel">([\s\S]*?)<\/script>/);
if (!m) { console.error('bloc text/babel introuvable'); process.exit(1); }
try {
  Babel.transform(m[1], { presets: ['react'], filename: 'index.html' });
  console.log('OK babel');
} catch (e) {
  const off = html.indexOf(m[1]); const lineOffset = html.slice(0, off).split('\n').length - 1;
  console.error(`SyntaxError index.html:${(e.loc?.line||0)+lineOffset}:${e.loc?.column||0} — ${e.message.split('\n')[0]}`);
  process.exit(1);
}
