// Uji keamanan endpoint live. Jalankan: node scripts/security-check.mjs
// Butuh akun admin yang sudah ada (env ADMIN_USER/ADMIN_PASS, default admin/admin123).
//
// Sejak mode publik (tamu boleh membaca), "tanpa token" TIDAK lagi 401:
// tamu boleh SELECT data klub, tetapi tetap tidak boleh menulis. Uji di bawah
// mengikuti aturan itu; batas baca/tulis per role ada di scripts/e2e-check.mjs.
const base = (process.env.BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPass = process.env.ADMIN_PASS || 'admin123';

const post = async (path, body, headers = {}) => {
  const res = await fetch(base + path, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  let json = {};
  try {
    json = await res.json();
  } catch {
    /* bukan JSON */
  }
  return { code: res.status, json };
};

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

// 1. Tanpa token: boleh baca data klub, tidak boleh tulis.
let r = await post('/api/sql', { sql: 'SELECT 1' });
check('tamu boleh SELECT', r.code === 200, `code ${r.code}`);
r = await post('/api/sql', { sql: "INSERT INTO settings (key, value) VALUES ('_uji','1')" });
check('tamu tidak boleh menulis', r.code === 403, `code ${r.code}`);

// 2. Login admin
r = await post('/api/auth', { action: 'login', username: adminUser, password: adminPass });
check('login admin berhasil', r.code === 200 && !!r.json.token, `code ${r.code}`);
const token = r.json.token;
const auth = { authorization: `Bearer ${token}` };

// 3. Token dipalsukan
r = await post('/api/sql', { sql: 'SELECT 1' }, { authorization: `Bearer ${token}x` });
check('token dipalsukan ditolak', r.code === 401, `code ${r.code}`);

// 4. Query normal
r = await post('/api/sql', { sql: 'SELECT count(*)::int AS n FROM members' }, auth);
check('SELECT normal jalan', r.code === 200 && r.json.rows?.[0]?.n >= 0, `code ${r.code}`);

// 5. Akses kolom password lewat /api/sql
r = await post('/api/sql', { sql: 'SELECT password_hash FROM users LIMIT 1' }, auth);
check('SELECT password_hash ditolak', r.code === 403, `code ${r.code}`);

// 6. DDL
r = await post('/api/sql', { sql: 'DROP TABLE announcements' }, auth);
check('DROP ditolak', r.code === 403, `code ${r.code}`);

// 7. Multi statement
r = await post('/api/sql', { sql: 'SELECT 1; SELECT 2' }, auth);
check('multi-statement ditolak', r.code === 403, `code ${r.code}`);

// 8. Tulis ke users lewat /api/sql, termasuk nama berskema
r = await post('/api/sql', { sql: "UPDATE users SET role='admin' WHERE id=1" }, auth);
check('tulis users lewat sql ditolak', r.code === 403, `code ${r.code}`);
r = await post('/api/sql', { sql: "UPDATE public.users SET role='admin' WHERE id=1" }, auth);
check('tulis public.users lewat sql ditolak', r.code === 403, `code ${r.code}`);

// 9. Komentar tidak bisa menyembunyikan target tulis
r = await post('/api/sql', { sql: 'DELETE /* x */ FROM users WHERE id=1' }, auth);
check('komentar tidak menyembunyikan users', r.code === 403, `code ${r.code}`);

// 10. ON CONFLICT DO NOTHING tetap boleh (dipakai simpan sesi & turnamen)
r = await post(
  '/api/sql',
  {
    sql: "INSERT INTO settings (key, value) VALUES ('_uji_akses', '1') ON CONFLICT DO NOTHING",
  },
  auth,
);
check('ON CONFLICT DO NOTHING boleh', r.code === 200, `code ${r.code} ${r.json.error ?? ''}`);
await post('/api/sql', { sql: "DELETE FROM settings WHERE key='_uji_akses'" }, auth);

// 11. Parameter yang hilang ditolak, bukan jadi NULL diam-diam
r = await post('/api/sql', { sql: 'SELECT * FROM members WHERE id=@nope', params: {} }, auth);
check('parameter hilang ditolak', r.code === 400, `code ${r.code}`);

// 12. Karakter @ di dalam string tidak dianggap parameter
r = await post('/api/sql', { sql: "SELECT '@bukan_param'::text AS v" }, auth);
check('@ di string aman', r.code === 200 && r.json.rows?.[0]?.v === '@bukan_param', `code ${r.code}`);

// 13. Akun member read-only (dibuat lalu dihapus lagi)
const tempUser = `uji_${Date.now().toString(36)}`;
const tempPass = `uji-${Math.random().toString(36).slice(2, 12)}`;
r = await post(
  '/api/auth',
  { action: 'create', username: tempUser, password: tempPass, role: 'member' },
  auth,
);
const madeUser = r.code === 200;
if (madeUser) {
  const login = await post('/api/auth', { action: 'login', username: tempUser, password: tempPass });
  const memberAuth = { authorization: `Bearer ${login.json.token}` };
  const read = await post('/api/sql', { sql: 'SELECT count(*)::int AS n FROM members' }, memberAuth);
  check('member boleh membaca', read.code === 200, `code ${read.code}`);
  const write = await post(
    '/api/sql',
    { sql: "INSERT INTO announcements (title, body) VALUES ('_uji', '_uji')" },
    memberAuth,
  );
  check('member tidak boleh menulis', write.code === 403, `code ${write.code}`);
  const users = await post('/api/sql', { sql: 'SELECT id, username FROM users' }, memberAuth);
  check('member tidak boleh melihat pengguna', users.code === 403, `code ${users.code}`);
  const id = r.json.id;
  if (id) await post('/api/auth', { action: 'delete', id }, auth);
} else {
  check('akun uji member bisa dibuat', false, `code ${r.code} ${r.json.error ?? ''}`);
}

// 14. Error DB tidak bocor detail
// Pesannya sengaja generik di api/sql.js (detail hanya ke log server).
// Dulu teksnya "Query gagal dijalankan", sekarang "Data belum bisa dimuat…"
// — yang dicek bukan teks persisnya, tapi kode 400 dan TIDAK membawa
// detail Postgres (nama tabel, posisi error, SQL mentah).
r = await post('/api/sql', { sql: 'SELECT * FROM tabel_tidak_ada' }, auth);
const leakFree = !/relation|syntax|column|tabel_tidak_ada|postgres/i.test(r.json.error ?? '');
check(
  'error DB tidak bocor detail',
  r.code === 400 && leakFree,
  `${r.code} ${r.json.error}`,
);

// 15. Password salah
r = await post('/api/auth', { action: 'login', username: adminUser, password: 'salah-sekali' });
check('password salah 401 + pesan umum', r.code === 401 && r.json.error === 'Username atau password salah');

// 16. Register saat sudah ada user
r = await post('/api/auth', { action: 'register', username: 'penyusup', password: 'penyusup123' });
check('register setelah ada user ditolak', r.code === 403, `code ${r.code}`);

// 17. Aksi admin tanpa token
r = await post('/api/auth', { action: 'create', username: 'x', password: 'xxxxxx' });
check('create user tanpa token ditolak', r.code === 403, `code ${r.code}`);

// 18. Input kebesaran ditolak
r = await post('/api/auth', { action: 'login', username: 'x'.repeat(100), password: 'x' });
check('username kebesaran ditolak', r.code === 401 || r.code === 400, `code ${r.code}`);

// 19. Security headers
const head = await fetch(base + '/');
const h = head.headers;
check('header CSP ada', !!h.get('content-security-policy'));
check('header X-Frame-Options DENY', h.get('x-frame-options') === 'DENY');
check('header nosniff', h.get('x-content-type-options') === 'nosniff');
check('header HSTS', !!h.get('strict-transport-security'));

// 20. Privasi data anggota untuk tamu.
//
// Mode publik sengaja menampilkan data klub, tapi nomor HP dan alamat
// tinggal anggota adalah data pribadi. Dua lapis yang diuji di sini:
// guard (query yang menyebut kolomnya ditolak) dan saringan hasil
// (`SELECT *` tidak menyebut kolomnya, jadi isinya yang dibuang).
r = await post('/api/sql', { sql: 'SELECT name, phone FROM members' });
check('tamu tidak boleh menanyakan nomor HP', r.code === 403, `code ${r.code}`);

r = await post('/api/sql', { sql: 'SELECT address FROM members' });
check('tamu tidak boleh menanyakan alamat', r.code === 403, `code ${r.code}`);

r = await post('/api/sql', { sql: 'SELECT * FROM members LIMIT 5' });
const leaked = (r.json.rows ?? []).some((row) => 'phone' in row || 'address' in row);
check('tamu tidak menerima nomor HP/alamat di SELECT *', r.code === 200 && !leaked,
  r.code === 200 ? `baris: ${JSON.stringify(r.json.rows?.[0] ?? {})}` : `code ${r.code}`);

r = await post('/api/sql', { sql: 'SELECT count(*)::int AS c FROM members' });
check('tamu boleh menghitung anggota', r.code === 200, `code ${r.code}`);

const bad = results.filter((x) => !x.ok).length;
console.log(`\n${results.length - bad}/${results.length} lulus.`);
process.exit(bad ? 1 : 0);
