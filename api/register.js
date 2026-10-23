import { neon } from '@neondatabase/serverless';

import { usernameBase, usernameCandidate, validateRegistration } from './_register-rules.js';

// POST /api/register  { name, phone, address, position }
//
// Pendaftaran anggota dari tautan publik (tanpa login). Satu permintaan
// membuat DUA baris: anggota di `members` dan akun di `users`, karena nama
// depan anggota dipakai sebagai username.
//
// Kenapa endpoint sendiri, bukan /api/sql:
//   * `users.password_hash` hanya boleh ditulis lewat koneksi owner; role
//     `app_web` sengaja tidak punya izin kolom itu.
//   * Tamu tidak boleh menulis lewat /api/sql (mode publik read-only), dan
//     melonggarkan aturan itu akan membuka SEMUA tabel untuk siapa pun.
//
// Password awal = nomor HP yang didaftarkan. Nomornya sudah diisi orang itu
// sendiri, jadi tidak perlu dikirim lewat kanal lain; pengguna bisa
// menggantinya sendiri di Pengaturan setelah masuk. Ini kompromi yang
// disengaja: alternatifnya password acak yang harus dicatat, dan di klub
// seperti ini itu berakhir sebagai "lupa password" setiap minggu.

// Koneksi dibuat saat permintaan pertama, bukan saat modul diimpor: tes
// memuat berkas ini tanpa DATABASE_URL (yang diuji hanya aturan validasinya),
// dan `neon()` melempar kalau connection string belum ada.
let _sql = null;
const db = () => {
  if (!_sql) _sql = neon(process.env.DATABASE_URL);
  return _sql;
};

const MAX_BODY = 4 * 1024;

// Batas percobaan per IP. Formulir publik tanpa batas adalah pintu spam ke
// tabel anggota; batas longgar supaya satu orang yang salah isi beberapa kali
// tidak ikut terkunci.
const WINDOW_MS = 10 * 60_000;
const MAX_HITS = 10;
const hits = new Map();

function tooMany(ip) {
  const now = Date.now();
  const h = hits.get(ip);
  if (!h || now > h.reset) {
    hits.set(ip, { n: 1, reset: now + WINDOW_MS });
    if (hits.size > 5000) hits.clear();
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

export default async function handler(req, res) {
  res.setHeader('cache-control', 'no-store');
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  if (!process.env.DATABASE_URL) {
    return res.status(500).json({ error: 'Server belum dikonfigurasi. Hubungi admin klub.' });
  }
  const sql = db();

  const raw = typeof req.body === 'string' ? req.body : JSON.stringify(req.body ?? {});
  if (raw.length > MAX_BODY) return res.status(413).json({ error: 'Permintaan terlalu besar' });

  if (tooMany(clientIp(req))) {
    res.setHeader('retry-after', String(WINDOW_MS / 1000));
    return res.status(429).json({ error: 'Terlalu banyak percobaan. Tunggu beberapa menit.' });
  }

  const parsed = validateRegistration(bodyOf(req));
  if (!parsed.ok) return res.status(400).json({ error: parsed.error });
  const { name, phone, address, position } = parsed.value;

  try {
    // Nomor HP adalah penanda orang, bukan sekadar kontak: mendaftar dua kali
    // dengan nomor yang sama akan membuat dua anggota dan dua akun untuk satu
    // orang, lalu iurannya terbelah.
    const existing = await sql`SELECT id FROM members WHERE phone = ${phone} LIMIT 1`;
    if (existing.length) {
      return res.status(409).json({
        error: 'Nomor HP ini sudah terdaftar. Hubungi admin kalau datanya perlu diperbarui.',
      });
    }

    const base = usernameBase(name);
    for (let n = 1; n <= 99; n++) {
      const username = usernameCandidate(base, n);
      const [member] = await sql`
        INSERT INTO members (name, phone, address, position)
        VALUES (${name}, ${phone}, ${address}, ${position})
        RETURNING id`;
      const [user] = await sql`
        INSERT INTO users (username, role, member_id, password_hash)
        VALUES (${username}, 'member', ${member.id}, crypt(${phone}, gen_salt('bf', 10)))
        ON CONFLICT (username) DO NOTHING
        RETURNING id, username`;
      if (user) {
        return res.status(200).json({
          memberId: member.id,
          name,
          username: user.username,
          password: phone,
        });
      }
      // Username sudah dipakai orang lain: batalkan anggota yang barusan
      // dibuat, lalu coba nomor berikutnya (irvan → irvan2 → irvan3).
      await sql`DELETE FROM members WHERE id = ${member.id}`;
    }

    return res.status(409).json({
      error: 'Nama ini sudah dipakai banyak anggota. Tambahkan nama tengah lalu coba lagi.',
    });
  } catch (e) {
    console.error('[register]', e.message);
    return res.status(500).json({ error: 'Pendaftaran gagal disimpan. Coba lagi.' });
  }
}
