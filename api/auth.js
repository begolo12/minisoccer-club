import { neon } from '@neondatabase/serverless';
import { bearer, issueToken, verifyToken } from './_auth.js';

// POST /api/auth  { action, ... }
//   status   : publik, cek apakah DB masih kosong (layar login)
//   register : publik, hanya saat tabel users kosong (admin pertama)
//   login    : publik, password dicek bcrypt oleh Postgres (pgcrypto)
//   change   : siapa pun yang sudah masuk — ganti password sendiri
//   create   : admin — tambah user
//   reset    : admin — ganti password user lain
//   delete   : admin — hapus user
//   setActive: admin — nonaktifkan/aktifkan akun (tanpa menghapus riwayat)
//
// Password TIDAK pernah dibaca/ditulis lewat /api/sql; semua di sini
// pakai koneksi owner (DATABASE_URL). Koneksi web (/api/sql) pakai role
// terbatas `app_web` yang tidak punya akses kolom password.

const sql = neon(process.env.DATABASE_URL);

// Batas panjang password.
//
// 6 karakter terlalu lemah untuk akun yang bisa melihat kas klub. Dinaikkan ke
// 8, TAPI hanya untuk password BARU (`create`, `reset`, `change`, `register`).
// Jalur `login` memang tidak pernah memeriksa panjang minimum — ia hanya
// membandingkan dengan hash yang tersimpan — jadi akun lama yang passwordnya
// 6-7 karakter tetap bisa masuk. Yang dijaga adalah password berikutnya.
const MIN_PASS = 8;

const MAX_USER = 40;
const MAX_PASS = 200;
const MAX_BODY = 8 * 1024;

// Batas salah password sebelum akun dikunci sementara.
const MAX_FAILS = 5;
const LOCK_MINUTES = 10;

// Batas percobaan login.
//
// Dulu penghitungnya `Map` di memori instance. Di Vercel, satu fungsi bisa
// berjalan di beberapa instance sekaligus, dan tiap instance punya Map sendiri
// — jadi batas 30 percobaan sebenarnya 30 × jumlah instance, dan instance baru
// (setelah idle) mulai dari nol. Penyerang tinggal mengulang sampai kena
// instance yang masih segar.
//
// Sekarang hitungannya di Postgres, satu baris per IP, lewat satu `INSERT ...
// ON CONFLICT` yang atomik: tidak ada balapan baca-lalu-tulis.
const WINDOW_MS = 5 * 60_000;
const MAX_HITS = 30;

/**
 * Sudah terlalu banyak percobaan dari IP ini?
 *
 * Gagal-terbuka kalau DB bermasalah: tanpa DB, login memang tidak bisa
 * dilanjutkan, jadi menolak dengan 429 hanya menyamarkan masalah sebenarnya.
 */
async function tooMany(ip) {
  if (!ip) return false;
  try {
    const rows = await sql(
      `INSERT INTO auth_throttle (ip, hits, reset_at)
       VALUES ($1, 1, now() + make_interval(secs => $2))
       ON CONFLICT (ip) DO UPDATE SET
         hits = CASE WHEN auth_throttle.reset_at <= now() THEN 1
                     ELSE auth_throttle.hits + 1 END,
         reset_at = CASE WHEN auth_throttle.reset_at <= now()
                         THEN now() + make_interval(secs => $2)
                         ELSE auth_throttle.reset_at END
       RETURNING hits`,
      [ip, WINDOW_MS / 1000],
    );
    // Bersihkan baris kedaluwarsa sesekali: tabel ini hanya perlu memuat IP
    // yang sedang dalam jendela, dan tanpa pembersihan ia tumbuh selamanya.
    if (Math.random() < 0.02) {
      await sql("DELETE FROM auth_throttle WHERE reset_at < now() - interval '1 day'");
    }
    return (rows[0]?.hits ?? 0) > MAX_HITS;
  } catch (e) {
    console.error('[auth] throttle tidak bisa diperiksa:', e.message);
    return false;
  }
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
  if ((action === 'login' || action === 'register') && (await tooMany(clientIp(req)))) {
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
    if (
      action === 'create' || action === 'reset' || action === 'delete' ||
      action === 'setActive' || action === 'update' || action === 'list'
    ) {
      const admin = adminOf(req);
      if (!admin) return res.status(403).json({ error: 'Hanya admin yang bisa mengelola pengguna' });

      // ---- daftar kredensial (admin) ----
      //
      // Kenapa lewat /api/auth, bukan /api/sql: kolom `password_hash` tidak
      // pernah boleh terbaca dari jalur SQL bebas (guard menolaknya), dan
      // role `app_web` juga tidak punya grant kolom itu. Yang dikirim hanya
      // FAKTA apakah password sudah diset — bukan hash-nya.
      //
      // Password itu sendiri tidak bisa ditampilkan: disimpan sebagai bcrypt
      // satu arah (`crypt` + `gen_salt('bf')`). Yang bisa dilakukan admin:
      // menyetel password baru, lalu menyalinnya sekali dari layar.
      if (action === 'list') {
        const rows = await sql(
          `SELECT id, username, role, active, member_id, created_at,
                  (password_hash IS NOT NULL) AS has_password
             FROM users
            ORDER BY role, username`,
        );
        return res.status(200).json({ users: rows });
      }

      // Ubah username dan/atau role.
      //
      // Kenapa perlu: username anggota dibuat otomatis dari nama depan
      // ("irvan", "irvan2"). Kalau orang Spray改 nama, atau salah dibuat
      // dengan role yang keliru, tanpa ini satu-satunya jalan adalah hapus
      // lalu buat ulang — dan menghapus akun anggota berarti kehilangan
      // tautan ke baris anggotanya.
      if (action === 'update') {
        const uid = Number(id);
        if (!uid) return res.status(400).json({ error: 'id wajib' });
        const body = bodyOf(req);
        const newName = body.username === undefined ? null : String(body.username).trim();
        const newRole = body.role === undefined ? null : String(body.role);
        // Tautan ke baris anggota. Tiga keadaan, jadi `undefined` (tidak
        // diubah) harus dibedakan dari `null` (dilepas): akun admin tidak
        // punya baris anggota, akun anggota harus punya.
        const touchMember = body.member_id !== undefined;
        let newMember = null;
        if (touchMember && body.member_id !== null) {
          newMember = Number(body.member_id);
          if (!Number.isInteger(newMember) || newMember <= 0) {
            return res.status(400).json({ error: 'Anggota tidak dikenal' });
          }
        }
        if (newName === null && newRole === null && !touchMember) {
          return res.status(400).json({ error: 'Tidak ada yang diubah' });
        }
        if (newName !== null && (newName.length === 0 || newName.length > MAX_USER)) {
          return res.status(400).json({ error: `Username wajib (maks ${MAX_USER})` });
        }
        if (newRole !== null && !['admin', 'treasurer', 'member'].includes(newRole)) {
          return res.status(400).json({ error: 'Role tidak dikenal' });
        }
        // Menjaga agar klub tidak terkunci di luar: admin aktif terakhir
        // tidak boleh kehilangan aksesnya sendiri.
        if (newRole !== null && newRole !== 'admin') {
          const [target] = await sql('SELECT role, active FROM users WHERE id = $1', [uid]);
          if (!target) return res.status(404).json({ error: 'User tidak ditemukan' });
          if (target.role === 'admin' && target.active) {
            const [{ n }] = await sql(
              `SELECT count(*)::int AS n FROM users
                WHERE role = 'admin' AND active AND id <> $1`,
              [uid],
            );
            if (n === 0) {
              return res.status(400).json({ error: 'Admin aktif terakhir tidak bisa kehilangan role admin' });
            }
          }
        }
        if (touchMember && newMember !== null) {
          const [exists] = await sql('SELECT id FROM members WHERE id = $1', [newMember]);
          if (!exists) return res.status(404).json({ error: 'Anggota tidak ditemukan' });
        }
        const rows = await sql(
          `UPDATE users
              SET username  = coalesce($2, username),
                  role      = coalesce($3, role),
                  member_id = CASE WHEN $4::boolean THEN $5::int ELSE member_id END
            WHERE id = $1
            RETURNING id, username, role, active, member_id`,
          [uid, newName, newRole, touchMember, newMember],
        );
        if (!rows.length) return res.status(404).json({ error: 'User tidak ditemukan' });
        return res.status(200).json({ ok: true, user: rows[0] });
      }

      // Nonaktif ≠ hapus: riwayat iuran/patungan tetap menunjuk akunnya.
      // Yang berubah cuma pintu masuknya.
      if (action === 'setActive') {
        const uid = Number(id);
        const on = Boolean(bodyOf(req).active);
        if (!uid) return res.status(400).json({ error: 'id wajib' });
        if (!on) {
          if (uid === admin.id) return res.status(400).json({ error: 'Tidak bisa menonaktifkan akun sendiri' });
          const [target] = await sql('SELECT role FROM users WHERE id = $1', [uid]);
          if (!target) return res.status(404).json({ error: 'User tidak ditemukan' });
          if (target.role === 'admin') {
            const [{ n }] = await sql(
              `SELECT count(*)::int AS n FROM users
                WHERE role = 'admin' AND active AND id <> $1`,
              [uid],
            );
            if (n === 0) return res.status(400).json({ error: 'Admin aktif terakhir tidak bisa dinonaktifkan' });
          }
        }
        const rows = await sql(
          'UPDATE users SET active = $2 WHERE id = $1 RETURNING id, username, active',
          [uid, on],
        );
        if (!rows.length) return res.status(404).json({ error: 'User tidak ditemukan' });
        return res.status(200).json({ ok: true, active: rows[0].active });
      }

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
      `SELECT id, username, role, member_id FROM users
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
    // `member_id` ikut dikembalikan: role anggota membutuhkannya untuk
    // membuka "Akun saya" (iuran & patungan miliknya sendiri).
    return res.status(200).json({
      ...rows[0],
      member_id: rows[0].member_id ?? null,
      token: issueToken(rows[0]),
    });
  } catch (e) {
    console.error('[auth]', e);
    return res.status(500).json({ error: 'Server sedang bermasalah. Coba lagi.' });
  }
}
