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

// Koneksi web WAJIB pakai role terbatas `app_web` (DATABASE_URL_WEB).
// Fallback ke DATABASE_URL hanya untuk pengembangan lokal: kalau variabel
// terbatas lupa dipasang di produksi, app tetap jalan tapi dengan hak owner
// dan lapis pengaman pertama (izin Postgres) hilang tanpa suara.
const webUrl = process.env.DATABASE_URL_WEB || process.env.DATABASE_URL;
if (!process.env.DATABASE_URL_WEB) {
  console.warn('[sql] DATABASE_URL_WEB belum diset — memakai koneksi owner. Jalankan scripts/harden-db.mjs.');
}

const sql = neon(webUrl);

// /api/auth membatasi 8 KB; jalur SQL lebih longgar (satu INSERT jadwal
// turnamen bisa panjang) tapi tetap dibatasi supaya body raksasa tidak
// di-parse dan dikirim ke Neon sebelum ditolak `_guard` (20.000 karakter).
const MAX_BODY = 128 * 1024;

export default async function handler(req, res) {
  res.setHeader('cache-control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  // Tanpa token = tamu. Aplikasi memang menampilkan data klub tanpa login
  // (mode publik read-only); tulis tetap ditolak di `_guard.js` karena role
  // `public` hanya boleh SELECT. Token yang ada tapi kedaluwarsa tetap 401
  // supaya sesi yang habis tidak diam-diam turun jadi tamu.
  const token = bearer(req);
  let session = null;
  if (token) {
    session = verifyToken(token);
    if (!session) return res.status(401).json({ error: 'Sesi habis, silakan login ulang' });
  }
  const viewer = session || { r: 'public', u: 'tamu' };

  const raw = typeof req.body === 'string' ? req.body : JSON.stringify(req.body ?? {});
  if (raw.length > MAX_BODY) return res.status(413).json({ error: 'Permintaan terlalu besar' });

  let body;
  try {
    body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
  } catch {
    return res.status(400).json({ error: 'Body bukan JSON' });
  }

  const { sql: text, params = {} } = body;
  const blocked = rejectSql(text, viewer);
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
