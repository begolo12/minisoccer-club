// Uji keamanan endpoint live. Jalankan: node scratch/security-check.mjs
const base = process.env.BASE || 'https://minisoccer-club.vercel.app';

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

// 1. Tanpa token
let r = await post('/api/sql', { sql: 'SELECT 1' });
check('sql tanpa token ditolak 401', r.code === 401, `code ${r.code}`);

// 2. Login admin
r = await post('/api/auth', { action: 'login', username: 'admin', password: 'admin123' });
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

// 8. Tulis ke users lewat /api/sql
r = await post('/api/sql', { sql: "UPDATE users SET role='admin' WHERE id=1" }, auth);
check('tulis users lewat sql ditolak', r.code === 403, `code ${r.code}`);

// 9. Kelola user tanpa admin (butuh akun member; dilewati kalau tidak ada)
// 10. Error DB tidak bocor detail
r = await post('/api/sql', { sql: 'SELECT * FROM tabel_tidak_ada' }, auth);
check(
  'error DB tidak bocor detail',
  r.code === 400 && r.json.error === 'Query gagal dijalankan',
  `${r.code} ${r.json.error}`,
);

// 11. Password salah
r = await post('/api/auth', { action: 'login', username: 'admin', password: 'salah-sekali' });
check('password salah 401 + pesan umum', r.code === 401 && r.json.error === 'Username atau password salah');

// 12. Register saat sudah ada user
r = await post('/api/auth', { action: 'register', username: 'penyusup', password: 'penyusup123' });
check('register setelah ada user ditolak', r.code === 403, `code ${r.code}`);

// 13. Aksi admin tanpa token
r = await post('/api/auth', { action: 'create', username: 'x', password: 'xxxxxx' });
check('create user tanpa token ditolak', r.code === 403, `code ${r.code}`);

// 14. Security headers
const head = await fetch(base + '/');
const h = head.headers;
check('header CSP ada', !!h.get('content-security-policy'));
check('header X-Frame-Options DENY', h.get('x-frame-options') === 'DENY');
check('header nosniff', h.get('x-content-type-options') === 'nosniff');
check('header HSTS', !!h.get('strict-transport-security'));

const bad = results.filter((x) => !x.ok).length;
console.log(`\n${results.length - bad}/${results.length} lulus.`);
process.exit(bad ? 1 : 0);
