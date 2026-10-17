// Jalankan schema ke Neon: `npm run db:init`
// Butuh env DATABASE_URL (connection string Neon).
import { neon } from '@neondatabase/serverless';
import { readFileSync } from 'node:fs';

const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL belum diset.');
  process.exit(1);
}

const sql = neon(url);
const raw = readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');

// Buang komentar lalu pecah per statement (schema tidak punya `;` di dalam string).
const statements = raw
  .split('\n')
  .filter((l) => !l.trimStart().startsWith('--'))
  .join('\n')
  .split(';')
  .map((s) => s.trim())
  .filter(Boolean);

for (const stmt of statements) {
  await sql.query(stmt);
}
console.log(`OK — ${statements.length} statement dijalankan.`);
