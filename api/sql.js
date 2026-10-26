import { neon } from '@neondatabase/serverless';
import { bearer, verifyToken } from './_auth.js';
import { MissingParam, rejectSql, toPositional, writeTarget } from './_guard.js';
import { hiddenColumns, scrubRows } from './_privacy.js';

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
//
// Di produksi (Vercel) fallback itu GAGAL KERAS: lebih baik endpoint SQL mati
// dengan pesan jelas daripada seluruh aplikasi berjalan tanpa lapis pengaman
// hanya karena satu variabel env terlewat.
const isProd = Boolean(process.env.VERCEL);
if (!process.env.DATABASE_URL_WEB && isProd) {
  console.error('[sql] DATABASE_URL_WEB belum diset di produksi — endpoint SQL dimatikan.');
}
const webUrl = process.env.DATABASE_URL_WEB || (isProd ? null : process.env.DATABASE_URL);
if (!process.env.DATABASE_URL_WEB && !isProd) {
  console.warn('[sql] DATABASE_URL_WEB belum diset — memakai koneksi owner (mode lokal). Jalankan scripts/harden-db.mjs.');
}

const sql = webUrl ? neon(webUrl) : null;

// /api/auth membatasi 8 KB; jalur SQL lebih longgar (satu INSERT jadwal
// turnamen bisa panjang) tapi tetap dibatasi supaya body raksasa tidak
// di-parse dan dikirim ke Neon sebelum ditolak `_guard` (20.000 karakter).
const MAX_BODY = 128 * 1024;

/**
 * Catat satu tulisan ke `audit_log`.
 *
 * Sengaja TIDAK pernah melempar: kalau pencatatan gagal (tabel belum
 * dimigrasi, koneksi putus), catatan kasnya sudah tersimpan dan pengguna tidak
 * boleh melihat error karena hal yang bukan urusannya. Kegagalannya masuk log
 * server saja.
 *
 * `row_id` diambil dari `RETURNING id` kalau ada — hampir semua tulis di app
 * memakainya, jadi baris audit bisa ditautkan ke baris nyata tanpa menyimpan
 * salinan isinya.
 */
async function logWrite({ text, viewer, result }) {
  const target = writeTarget(text);
  if (!target) return;
  const first = result?.rows?.[0];
  const rawId = first && typeof first === 'object' ? first.id : null;
  // `Number(null)` = 0, jadi null harus dicek lebih dulu — kalau tidak, tulisan
  // tanpa `RETURNING id` tercatat dengan row_id 0 (baris yang tidak ada).
  const rowId = rawId == null ? null : Number(rawId);
  try {
    await sql(
      `INSERT INTO audit_log (actor, role, tbl, op, row_id, detail)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [
        viewer.u ?? 'tamu',
        viewer.r ?? 'public',
        target.table,
        target.op,
        Number.isFinite(rowId) ? rowId : null,
        result?.rowCount == null ? null : `${result.rowCount} baris`,
      ],
    );
  } catch (e) {
    console.error('[audit] gagal mencatat:', e.message);
  }
}

export default async function handler(req, res) {
  res.setHeader('cache-control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if (!sql) {
    return res.status(500).json({
      error: 'Server belum dikonfigurasi. Hubungi admin klub.',
    });
  }

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
    // Jejak audit. Ditulis SETELAH query berhasil, dan kegagalannya tidak
    // pernah menggagalkan permintaan: pengguna tidak boleh kehilangan catatan
    // kas hanya karena tabel audit sedang bermasalah.
    await logWrite({ text, viewer, result });
    // Lapis kedua privasi: hasil query disaring sebelum keluar. Guard hanya
    // bisa menolak query yang MENYEBUT kolom sensitif; `SELECT *` dan
    // `row_to_json(m)` menyebutnya tanpa nama, jadi harus disaring di sini.
    const hidden = hiddenColumns(session?.r);
    const rows = hidden.length > 0 ? scrubRows(result.rows ?? [], hidden) : result.rows ?? [];
    return res.status(200).json({ rows, rowCount: result.rowCount });
  } catch (e) {
    if (e instanceof MissingParam) return res.status(400).json({ error: e.message });
    // Detail hanya ke log server; klien dapat pesan umum.
    console.error('[sql]', e.message);
    return res.status(400).json({ error: 'Data belum bisa dimuat. Coba lagi sebentar lagi.' });
  }
}
