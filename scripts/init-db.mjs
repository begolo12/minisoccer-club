// Jalankan schema ke Neon: `npm run db:init`
// Butuh env DATABASE_URL (connection string Neon).
//
// Kenapa pakai `https` langsung, bukan `@neondatabase/serverless`?
// Di sebagian jaringan, DNS mengembalikan alamat IPv6 duluan dan `fetch` Node
// gagal connect (ETIMEDOUT). Endpoint HTTP Neon sama saja, jadi kita paksa IPv4.
import { request } from 'node:https';
import { readFileSync } from 'node:fs';
import { resolve4 } from 'node:dns/promises';

const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL belum diset.');
  process.exit(1);
}

const host = new URL(url).hostname;
const [ip] = await resolve4(host);

// ponytail: paksa IPv4, tanpa fallback IPv6. Ganti kalau IPv6 sudah jalan normal.
const lookup = (_h, o, cb) =>
  o.all ? cb(null, [{ address: ip, family: 4 }]) : cb(null, ip, 4);

function run(query) {
  const body = JSON.stringify({ query, params: [] });
  return new Promise((resolve, reject) => {
    const req = request(
      {
        host,
        servername: host,
        lookup,
        family: 4,
        path: '/sql',
        method: 'POST',
        timeout: 30000,
        headers: {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(body),
          'neon-connection-string': url,
          'neon-pooler': 'true',
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (d) => (raw += d));
        res.on('end', () => {
          let json = {};
          try {
            json = JSON.parse(raw);
          } catch {
            return reject(new Error(`HTTP ${res.statusCode}: ${raw.slice(0, 200)}`));
          }
          if (res.statusCode !== 200) return reject(new Error(json.message || raw));
          resolve(json);
        });
      },
    );
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', reject);
    req.end(body);
  });
}

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
  await run(stmt);
}
console.log(`OK — ${statements.length} statement dijalankan.`);
