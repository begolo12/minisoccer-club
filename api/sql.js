import { neon } from '@neondatabase/serverless';
import { bearer, verifyToken } from './_auth.js';

// POST /api/sql  { sql, params }
// Satu-satunya pintu DB untuk versi web (browser tidak bisa buka TCP ke Postgres).
// Wajib header `Authorization: Bearer <token>` dari /api/auth.
//
// Tiga lapis pengaman:
//   1. Koneksi pakai role `app_web` (DATABASE_URL_WEB): tanpa DDL, tanpa
//      akses kolom password_hash. Kalau filter di bawah lolos, Postgres
//      tetap menolak.
//   2. Filter statement: hanya SELECT/INSERT/UPDATE/DELETE/WITH, satu
//      statement, tanpa katalog sistem.
//   3. Cek role: `member` read-only; tulis ke `users` hanya lewat /api/auth.

const sql = neon(process.env.DATABASE_URL_WEB || process.env.DATABASE_URL);

const MAX_LEN = 20_000;

// Tabel yang boleh ditulis. `users` sengaja tidak ada di sini.
const WRITE_DENY = new Set(['users', 'pg_catalog', 'information_schema']);

const DANGEROUS =
  /\b(pg_[a-z_]+|information_schema|dblink|lo_import|lo_export|set_config|current_setting|grant|revoke|alter|create|drop|truncate|comment\s+on|copy|vacuum|analyze|listen|notify|security\s+definer)\b/i;

const writeTargets = (text) =>
  [...text.matchAll(/\b(?:insert\s+into|update|delete\s+from)\s+"?([a-z_][a-z0-9_]*)"?/gi)].map((m) =>
    m[1].toLowerCase(),
  );

/** Return pesan error (string) kalau query ditolak, null kalau boleh. */
function reject(text, session) {
  if (typeof text !== 'string' || !text.trim()) return 'sql required';
  if (text.length > MAX_LEN) return 'Query terlalu panjang';

  const body = text.trim().replace(/;\s*$/, '');
  if (body.includes(';')) return 'Satu statement per permintaan';

  if (!/^\s*(select|insert|update|delete|with)\b/i.test(body)) return 'Hanya SELECT/INSERT/UPDATE/DELETE';

  // Password tidak pernah lewat jalur ini — pakai /api/auth.
  if (/\b(password_hash|pin_hash)\b/i.test(body)) return 'Password hanya lewat /api/auth';

  if (DANGEROUS.test(body)) return 'Query tidak diizinkan';

  const targets = writeTargets(body);
  if (targets.length) {
    if (session.r === 'member') return 'Akun member hanya bisa melihat data';
    if (targets.some((t) => WRITE_DENY.has(t))) return 'Tabel ini hanya lewat /api/auth';
  }
  return null;
}

export default async function handler(req, res) {
  res.setHeader('cache-control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  const session = verifyToken(bearer(req));
  if (!session) return res.status(401).json({ error: 'Sesi habis, silakan login ulang' });

  let body;
  try {
    body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
  } catch {
    return res.status(400).json({ error: 'Body bukan JSON' });
  }

  const { sql: text, params = {} } = body;
  const blocked = reject(text, session);
  if (blocked) return res.status(403).json({ error: blocked });

  try {
    const { text: query, values } = toPositional(text, params || {});
    const result = await sql(query, values, { fullResults: true });
    return res.status(200).json({ rows: result.rows, rowCount: result.rowCount });
  } catch (e) {
    // Detail hanya ke log server; klien dapat pesan umum.
    console.error('[sql]', e.message);
    return res.status(400).json({ error: 'Query gagal dijalankan' });
  }
}

// `@nama` -> `$1` (driver Neon hanya menerima positional).
function toPositional(text, params) {
  const order = [];
  const sqlText = text.replace(/@([a-zA-Z_][a-zA-Z0-9_]*)/g, (_, name) => {
    let i = order.indexOf(name);
    if (i === -1) {
      order.push(name);
      i = order.length - 1;
    }
    return `$${i + 1}`;
  });
  return { text: sqlText, values: order.map((n) => params[n] ?? null) };
}
