import { neon } from '@neondatabase/serverless';
import { bearer, verifyToken } from './_auth.js';
import { MissingParam, rejectSql, toPositional } from './_guard.js';

// POST /api/sql  { sql, params }
// Satu-satunya pintu DB untuk web dan APK (klien tidak memegang kredensial).
// Wajib header `Authorization: Bearer <token>` dari /api/auth.
//
// Tiga lapis pengaman:
//   1. Koneksi pakai role `app_web` (DATABASE_URL_WEB): tanpa DDL, tanpa
//      akses kolom password. Kalau filter di bawah lolos, Postgres tetap
//      menolak.
//   2. Filter statement (`_guard.js`): satu statement, hanya
//      SELECT/INSERT/UPDATE/DELETE/WITH, target tulis yang pasti.
//   3. Cek role: `member` read-only; tulis ke `users` hanya lewat /api/auth.

const sql = neon(process.env.DATABASE_URL_WEB || process.env.DATABASE_URL);

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
  const blocked = rejectSql(text, session);
  if (blocked) return res.status(403).json({ error: blocked });

  if (params === null || typeof params !== 'object' || Array.isArray(params)) {
    return res.status(400).json({ error: 'params harus objek' });
  }

  try {
    const { text: query, values } = toPositional(text, params);
    const result = await sql(query, values, { fullResults: true });
    return res.status(200).json({ rows: result.rows, rowCount: result.rowCount });
  } catch (e) {
    if (e instanceof MissingParam) return res.status(400).json({ error: e.message });
    // Detail hanya ke log server; klien dapat pesan umum.
    console.error('[sql]', e.message);
    return res.status(400).json({ error: 'Query gagal dijalankan' });
  }
}
