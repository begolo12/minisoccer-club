import { neon } from '@neondatabase/serverless';
import { bearer, verifyToken } from './_auth.js';
import { MissingParam, rejectSql, toPositional } from './_guard.js';
import { hiddenColumns, scrubRows } from './_privacy.js';

// POST /api/sql  { sql, params }                 → { rows, rowCount }
// POST /api/sql  { queries: [{ sql, params }] }  → { results: [...] }
// Satu-satunya pintu DB untuk web dan APK (klien tidak memegang kredensial).
//
// Tiga lapis pengaman:
//   1. Koneksi pakai role `app_web` (DATABASE_URL_WEB): tanpa DDL, tanpa
//      akses kolom password. Kalau filter di bawah lolos, Postgres tetap
//      menolak.
//   2. Filter statement (`_guard.js`): satu statement, hanya
//      SELECT/INSERT/UPDATE/DELETE/WITH, target tulis yang pasti.
//   3. Cek role: `member` read-only; tulis ke `users` hanya lewat /api/auth.
//
// Dua hal yang dijaga di sini, bukan di klien:
//   * **Pencabutan sesi** — token HMAC tidak bisa ditarik; `token_version`
//     dibandingkan dengan klaim `v`, sehingga akun yang dinonaktifkan berhenti
//     menulis dalam hitungan detik, bukan menunggu 12 jam.
//   * **Tulis idempoten** — `writeId` yang sama tidak dijalankan dua kali.
//     Timeout di klien bukan bukti server belum commit.

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

// Satu permintaan boleh membawa beberapa query (layar Beranda butuh 10).
// Batas ini menjaga satu permintaan tidak menjadi pengganda beban.
const MAX_QUERIES = 24;

// Jawaban dibatasi: tabel klub berisi puluhan baris, jadi 5.000 sudah jauh di
// atas kebutuhan normal. Tanpa batas, `SELECT` tanpa LIMIT bisa menarik
// seluruh tabel ke memori fungsi.
const MAX_ROWS = 5000;

// Batas laju per instance. Sama seperti /api/auth: Map di memori proses,
// cukup untuk membendung penyalahgunaan biasa. Penghitung lintas instance
// butuh Redis, dan itu tidak sebanding untuk aplikasi klub.
const WINDOW_MS = 60_000;
const MAX_HITS_USER = 180;
const MAX_HITS_GUEST = 45;
const hits = new Map();

function tooMany(key, max) {
  const now = Date.now();
  const h = hits.get(key);
  if (!h || now > h.reset) {
    hits.set(key, { n: 1, reset: now + WINDOW_MS });
    return false;
  }
  h.n++;
  return h.n > max;
}

const clientIp = (req) =>
  String(req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '')
    .split(',')[0]
    .trim();

/**
 * Bangun handler dengan koneksi yang disuntik.
 *
 * Dipisah dari koneksi Neon supaya jalur batch, idempoten, dan pencabutan
 * sesi bisa diuji tanpa database (`api/sql.test.mjs`). Yang diuji adalah
 * perilaku yang tidak bisa dibuktikan lewat tes di klien.
 */
export function makeHandler(sqlFn) {
  /// Pencabutan sesi.
  ///
  /// Setiap panggilan SQL tidak perlu menyentuh tabel `users` — hasilnya
  /// di-cache 60 detik per proses. Artinya pencabutan berlaku maksimal satu
  /// menit setelah admin menekan "nonaktifkan", bukan 12 jam.
  const versionCache = new Map();
  const VERSION_TTL = 60_000;
  let missingColumnWarned = false;

  async function sessionState(session) {
    if (!session?.id) return { ok: false, reason: 'invalid' };
    const key = String(session.id);
    const now = Date.now();
    const hit = versionCache.get(key);
    if (hit && now - hit.at < VERSION_TTL) {
      return hit.ver === (session.v ?? 0) && hit.active
        ? { ok: true }
        : { ok: false, reason: 'revoked' };
    }

    try {
      const rows = await sqlFn('SELECT token_version, active FROM users WHERE id = $1', [
        session.id,
      ]);
      const row = rows[0];
      if (!row) return { ok: false, reason: 'revoked' };
      versionCache.set(key, { ver: row.token_version, active: row.active, at: now });
      return row.active && row.token_version === (session.v ?? 0)
        ? { ok: true }
        : { ok: false, reason: 'revoked' };
    } catch (e) {
      // Kolom belum ada (deploy kode sebelum `npm run db:init`): jangan
      // mematikan seluruh API. Peringatan ini harus hilang setelah migrasi.
      if (e?.code === '42703') {
        if (!missingColumnWarned) {
          missingColumnWarned = true;
          console.error('[sql] users.token_version belum ada — jalankan `npm run db:init`. Pencabutan sesi nonaktif sementara.');
        }
        return { ok: true };
      }
      // Gangguan DB sementara: token yang sah jangan sampai ditolak.
      console.error('[sql] cek sesi gagal:', e.message);
      return { ok: true };
    }
  }

  /// Jalankan satu query tulis secara idempoten.
  ///
  /// Kalau `writeId` sudah pernah diterapkan, hasil pertama diputar ulang dan
  /// query TIDAK dijalankan lagi. Ini menutup duplikasi yang dulu terjadi saat
  /// timeout di klien padahal server sudah commit.
  async function runWritten(query, values, writeId) {
    if (!writeId) return sqlFn(query, values, { fullResults: true });

    const insert = await sqlFn(
      `INSERT INTO applied_writes (write_id, result)
       VALUES ($1, '{}'::jsonb)
       ON CONFLICT (write_id) DO NOTHING
       RETURNING write_id`,
      [writeId],
    );
    if (!insert.length) {
      const [prev] = await sqlFn('SELECT result FROM applied_writes WHERE write_id = $1', [writeId]);
      const stored = prev?.result;
      // `{}` berarti penanda sempat dibuat tetapi hasilnya belum tersimpan
      // (fungsi mati di antara dua panggilan). Menjawab "sudah diterapkan"
      // di sini akan menghilangkan tulisan pengguna tanpa jejak — lebih
      // baik dijalankan sekali lagi.
      if (stored && Object.keys(stored).length > 0) {
        return {
          rows: stored.rows ?? [],
          rowCount: stored.rowCount ?? 0,
          replayed: true,
        };
      }
    }

    try {
      const result = await sqlFn(query, values, { fullResults: true });
      await sqlFn('UPDATE applied_writes SET result = $2 WHERE write_id = $1', [
        writeId,
        JSON.stringify({ rows: result.rows ?? [], rowCount: result.rowCount ?? 0 }),
      ]);
      return result;
    } catch (e) {
      // Gagal: hapus penanda supaya percobaan berikutnya benar-benar dijalankan.
      await sqlFn('DELETE FROM applied_writes WHERE write_id = $1', [writeId]).catch(() => {});
      throw e;
    }
  }

  /// Jalankan satu query dari klien, kembalikan bentuk siap-kirim.
  async function runOne(item, viewer) {
    if (!item || typeof item !== 'object') {
      return { error: 'Query tidak dikenali', status: 400 };
    }
    const { sql: text, params = {}, writeId } = item;

    const blocked = rejectSql(text, viewer);
    if (blocked) return { error: blocked, status: 403 };

    if (params === null || typeof params !== 'object' || Array.isArray(params)) {
      return { error: 'params harus objek', status: 400 };
    }
    if (
      writeId !== undefined &&
      (typeof writeId !== 'string' || writeId.length < 8 || writeId.length > 80)
    ) {
      return { error: 'writeId tidak sah', status: 400 };
    }

    try {
      const { text: query, values } = toPositional(text, params);
      const result = await runWritten(query, values, writeId);
      // Lapis kedua privasi: hasil query disaring sebelum keluar. Guard hanya
      // bisa menolak query yang MENYEBUT kolom sensitif; `SELECT *` dan
      // `row_to_json(m)` menyebutnya tanpa nama, jadi harus disaring di sini.
      const hidden = hiddenColumns(viewer?.r);
      const raw = hidden.length > 0 ? scrubRows(result.rows ?? [], hidden) : result.rows ?? [];
      if (raw.length > MAX_ROWS) {
        return { error: 'Hasil terlalu besar. Persempit pencarian.', status: 413 };
      }
      return {
        rows: raw,
        rowCount: result.rowCount ?? 0,
        ...(result.replayed ? { replayed: true } : {}),
      };
    } catch (e) {
      if (e instanceof MissingParam) return { error: e.message, status: 400 };
      // Detail hanya ke log server; klien dapat pesan umum.
      console.error('[sql]', e.message);
      return { error: 'Data belum bisa dimuat. Coba lagi sebentar lagi.', status: 400 };
    }
  }

  return async function handler(req, res) {
    res.setHeader('cache-control', 'no-store');
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
    if (!sqlFn) {
      return res.status(500).json({ error: 'Server belum dikonfigurasi. Hubungi admin klub.' });
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
      const state = await sessionState(session);
      if (!state.ok) {
        versionCache.delete(String(session.id));
        return res.status(401).json({ error: 'Sesi berakhir. Masuk lagi untuk melanjutkan.' });
      }
    }
    const viewer = session || { r: 'public', u: 'tamu' };

    const limitKey = session ? `u:${session.id}` : `ip:${clientIp(req)}`;
    if (tooMany(limitKey, session ? MAX_HITS_USER : MAX_HITS_GUEST)) {
      res.setHeader('retry-after', String(WINDOW_MS / 1000));
      return res.status(429).json({ error: 'Terlalu banyak permintaan. Tunggu sebentar.' });
    }

    const raw = typeof req.body === 'string' ? req.body : JSON.stringify(req.body ?? {});
    if (raw.length > MAX_BODY) return res.status(413).json({ error: 'Permintaan terlalu besar' });

    let body;
    try {
      body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
    } catch {
      return res.status(400).json({ error: 'Body bukan JSON' });
    }

    // Batch: `{ queries: [...] }`. Satu permintaan untuk satu layar (Beranda
    // butuh 10 query) memangkas 9 kali perjalanan pulang-pergi jaringan di HP.
    // Setiap item diperlakukan sendiri-sendiri: satu query ditolak tidak
    // menggagalkan yang lain, sama seperti perilaku `Future.wait` di klien.
    const batch = Array.isArray(body.queries) ? body.queries : null;
    if (batch) {
      if (batch.length === 0) return res.status(400).json({ error: 'queries kosong' });
      if (batch.length > MAX_QUERIES) {
        return res.status(400).json({ error: `Maksimal ${MAX_QUERIES} query per permintaan` });
      }
      const results = await Promise.all(batch.map((q) => runOne(q, viewer)));
      return res.status(200).json({ results });
    }

    const single = await runOne(body, viewer);
    if (single.error) return res.status(single.status ?? 400).json({ error: single.error });
    return res.status(200).json({ rows: single.rows, rowCount: single.rowCount });
  };
}

export default makeHandler(sql);