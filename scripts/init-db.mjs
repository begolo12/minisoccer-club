// Jalankan schema ke Neon: `npm run db:init`
// Butuh env DATABASE_URL (connection string Neon).
import { readFileSync } from 'node:fs';

import { makeRunner, splitStatements } from './_neon.mjs';

const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL belum diset.');
  process.exit(1);
}

const run = await makeRunner(url);
const raw = readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');
const statements = splitStatements(raw);

for (const stmt of statements) {
  await run(stmt);
}
console.log(`OK — ${statements.length} statement dijalankan.`);
