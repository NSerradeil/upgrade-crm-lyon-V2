// tests/db-54.test.mjs : la migration 54 est un ajout pur, au bon type, rejouable.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../db/54_agent_sequences_contact_id.sql', import.meta.url), 'utf8');
const code = sql.split('\n').filter(l => !l.trim().startsWith('--')).join('\n');

test('54 : contact_id bigint, cle etrangere vers contacts, on delete set null, index', () => {
  assert.match(code, /alter table public\.agent_sequences\s+add column if not exists contact_id bigint references public\.contacts\(id\) on delete set null;/);
  assert.match(code, /create index if not exists agent_sequences_contact_idx\s+on public\.agent_sequences \(contact_id\) where contact_id is not null;/);
});

test('54 : rien d autre qu un ajout (ni drop, ni update, ni delete de donnees)', () => {
  assert.doesNotMatch(code, /\bdrop\b|\bupdate\b|delete from|truncate/i);
});

test('54 : aucun tiret cadratin ni demi-cadratin', () => {
  assert.doesNotMatch(sql, /[–—]/);
});
