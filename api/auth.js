import { neon } from '@neondatabase/serverless';
import { bearer, issueToken, verifyToken } from './_auth.js';

// POST /api/auth  { action, ... }
//   status   : publik, cek apakah DB masih kosong (layar login)
//   register : publik, hanya saat tabel users kosong (admin pertama)
//   login    : publik, password dicek bcrypt oleh Postgres (pgcrypto)
//   create   : admin — tambah user
//   reset    : admin — ganti password user lain
//   delete   : admin — hapus user
//
// Password TIDAK pernah dibaca/ditulis lewat /api/sql; semua di sini
// pakai koneksi owner (DATABASE_URL). Koneksi web (/api/sql) pakai role
// terbatas `app_web` yang tidak punya akses kolom password.

const sql = neon(process.env.DATABASE_URL);

const MAX_FAILS = 5;
const LOCK_MINUTES = 10;
const MIN_PASS = 6; // ponytail: 6 biar tidak mengunci user lama; naikkan ke 8 kalau boleh.
const MAX_USER = 40;
const MAX_PASS = 200;
const MAX_BODY = 8 * 1024;

// ponytail: rate limit per instance (Map). Cukup untuk membendung brute force
// biasa; ganti ke Redis/DB kalau butuh batas lintas instance.
const WINDOW_MS = 5 * 60_000;
const MAX_HITS = 30;
const hits = new Map();

function tooMany(ip) {
  const now = Date.now();
  const h = hits.get(ip);
  if (!h || now > h.reset) {
    hits.set(ip, { n: 1, reset: now + WINDOW_MS });
    if (hits.size > 5000) hits.clear(); // jaga memori
    return false;
  }
  h.n++;
  return h.n > MAX_HITS;
}

const clientIp = (req) =>
  String(req.headers['x-forwarded-for'] || req.socket?.remoteAddress || '').split(',')[0].trim();

const bodyOf = (req) => {
  try {
    return typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
  } catch {
    return {};
  }
};

const adminOf = (req) => {
  const s = verifyToken(bearer(req));
  return s && s.r === 'admin' ? s : null;
};

/// Sesi siapa pun yang sudah masuk (admin, bendahara, anggota).
const sessionOf = (req) => verifyToken(bearer(req));

export default async function handler(req, res) {
  res.setHeader('cache-control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  const raw = typeof req.body === 'string' ? req.body : JSON.stringify(req.body ?? {});
  if (raw.length > MAX_BODY) return res.status(413).json({ error: 'Permintaan terlalu besar' });

  const { action, username, password, role, id } = bodyOf(req);
  const user = String(username || '').trim();
  const pass = String(password || '');

  // Batasi hanya percobaan kredensial; aksi admin yang sah tidak ikut terhitung.
  if ((action === 'login' || action === 'register') && tooMany(clientIp(req))) {
    res.setHeader('retry-after', String(WINDOW_MS / 1000));
    return res.status(429).json({ error: 'Terlalu banyak percobaan. Tunggu beberapa menit.' });
  }

  try {
    // ---- status (publik) ----
    if (action === 'status') {
      const [{ n }] = await sql('SELECT count(*)::int AS n FROM users');
      return res.status(200).json({ bootstrap: n === 0 });
    }

    // ---- admin-only ----
    if (action === 'create' || action === 'reset' || action === 'delete') {
      const admin = adminOf(req);
      if (!admin) return res.status(403).json({ error: 'Hanya admin yang bisa mengelola pengguna' });

      if (action === 'delete') {
        const uid = Number(id);
        if (!uid) return res.status(400).json({ error: 'id wajib' });
        if (uid === admin.id) return res.status(400).json({ error: 'Tidak bisa menghapus akun sendiri' });
        const rows = await sql(
          `DELETE FROM users WHERE id = $1 AND NOT (role = 'admin' AND
             (SELECT count(*) FROM users WHERE role = 'admin' AND active) <= 1)
           RETURNING id`,
          [uid],
        );
        if (!rows.length) return res.status(400).json({ error: 'Gagal hapus (admin terakhir?)' });
        return res.status(200).json({ ok: true });
      }

      const safeRole = role === 'admin' || role === 'treasurer' ? role : 'member';

      if (action === 'create') {
        if (!user || user.length > MAX_USER || pass.length < MIN_PASS || pass.length > MAX_PASS) {
          return res.status(400).json({ error: `Username wajib (maks ${MAX_USER}), password ${MIN_PASS}-${MAX_PASS} karakter` });
        }
        const rows = await sql(
          `INSERT INTO users (username, role, password_hash)
           VALUES ($1, $2, crypt($3, gen_salt('bf', 10)))
           ON CONFLICT (username) DO NOTHING
           RETURNING id, username, role`,
          [user, safeRole, pass],
        );
        if (!rows.length) return res.status(409).json({ error: 'Username sudah dipakai' });
        return res.status(200).json(rows[0]);
      }

      // reset — klien hanya mengirim id + password, jadi username tidak wajib.
      if (pass.length < MIN_PASS || pass.length > MAX_PASS) {
        return res.status(400).json({ error: `Password ${MIN_PASS}-${MAX_PASS} karakter` });
      }
      const uid = Number(id);
      if (!uid) return res.status(400).json({ error: 'id wajib' });
      const rows = await sql(
        `UPDATE users
            SET password_hash = crypt($2, gen_salt('bf', 10)),
                failed_attempts = 0,
                locked_until = NULL
          WHERE id = $1
          RETURNING id, username`,
        [uid, pass],
      );
      if (!rows.length) return res.status(404).json({ error: 'User tidak ditemukan' });
      return res.status(200).json({ ok: true, username: rows[0].username });
    }

    // ---- ganti password sendiri ----
    //
    // Pendaftaran anggota membuat akun dengan password awal = nomor HP, jadi
    // harus ada jalan bagi pemiliknya untuk menggantinya tanpa menunggu admin.
    // Password lama tetap diperiksa supaya token yang bocor tidak langsung
    // bisa dipakai mengunci pemilik akun.
    if (action === 'change') {
      const session = sessionOf(req);
      if (!session) return res.status(401).json({ error: 'Sesi habis, silakan login ulang' });
      const current = String(bodyOf(req).current || '');
      const next = String(bodyOf(req).next || '');
      if (next.length < MIN_PASS || next.length > MAX_PASS) {
        return res.status(400).json({ error: `Password ${MIN_PASS}-${MAX_PASS} karakter` });
      }
      const rows = await sql(
        `UPDATE users
            SET password_hash = crypt($2, gen_salt('bf', 10)),
                failed_attempts = 0,
                locked_until = NULL
          WHERE id = $1 AND active
            AND password_hash = crypt($3, password_hash)
          RETURNING id`,
        [session.id, next, current],
      );
      if (!rows.length) return res.status(403).json({ error: 'Password lama salah' });
      return res.status(200).json({ ok: true });
    }

    // ---- publik: register admin pertama ----
    if (action === 'register') {
      if (!user || user.length > MAX_USER || pass.length < MIN_PASS || pass.length > MAX_PASS) {
        return res.status(400).json({ error: `Username wajib (maks ${MAX_USER}), password ${MIN_PASS}-${MAX_PASS} karakter` });
      }
      const rows = await sql(
        `INSERT INTO users (username, role, password_hash)
         SELECT $1, 'admin', crypt($2, gen_salt('bf', 10))
          WHERE NOT EXISTS (SELECT 1 FROM users)
         ON CONFLICT (username) DO NOTHING
         RETURNING id, username, role`,
        [user, pass],
      );
      if (!rows.length) return res.status(403).json({ error: 'Sudah ada user. Tambah lewat menu Pengguna.' });
      return res.status(200).json({ ...rows[0], token: issueToken(rows[0]) });
    }

    // ---- login ----
    if (action !== 'login') return res.status(400).json({ error: 'action tidak dikenal' });
    if (!user || !pass) return res.status(400).json({ error: 'Username dan password wajib diisi' });
    if (user.length > MAX_USER || pass.length > MAX_PASS) {
      return res.status(401).json({ error: 'Username atau password salah' });
    }

    const [known] = await sql(
      'SELECT id, failed_attempts, locked_until FROM users WHERE username = $1',
      [user],
    );
    if (known?.locked_until && new Date(known.locked_until) > new Date()) {
      res.setHeader('retry-after', String(LOCK_MINUTES * 60));
      return res.status(429).json({ error: `Akun terkunci sementara. Coba lagi ${LOCK_MINUTES} menit.` });
    }

    const rows = await sql(
      `SELECT id, username, role FROM users
        WHERE username = $1 AND active AND password_hash IS NOT NULL
          AND password_hash = crypt($2, password_hash)`,
      [user, pass],
    );

    if (!rows.length) {
      if (known) {
        await sql(
          `UPDATE users
              SET failed_attempts = failed_attempts + 1,
                  locked_until = CASE WHEN failed_attempts + 1 >= $2
                                      THEN now() + make_interval(mins => $3)
                                      ELSE locked_until END
            WHERE id = $1`,
          [known.id, MAX_FAILS, LOCK_MINUTES],
        );
      }
      // Pesan sama untuk user tidak ada / password salah — jangan bocorkan.
      return res.status(401).json({ error: 'Username atau password salah' });
    }

    if (known.failed_attempts || known.locked_until) {
      await sql('UPDATE users SET failed_attempts = 0, locked_until = NULL WHERE id = $1', [known.id]);
    }
    return res.status(200).json({ ...rows[0], token: issueToken(rows[0]) });
  } catch (e) {
    console.error('[auth]', e);
    return res.status(500).json({ error: 'Server sedang bermasalah. Coba lagi.' });
  }
}
