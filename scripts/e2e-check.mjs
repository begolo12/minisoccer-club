// Uji end-to-end terhadap server sungguhan (lokal atau produksi).
//
// Yang diperiksa:
//   1. Schema: setiap kolom yang dipakai app benar-benar ada di DB (lewat
//      query yang sama dengan yang dikirim app, bukan asumsi).
//   2. Baca: tamu, anggota, bendahara, admin — semua boleh membaca data klub;
//      daftar pengguna hanya admin.
//   3. Tulis: tamu & anggota ditolak (403), admin & bendahara boleh.
//   4. Tulis tidak merusak data: UPDATE/DELETE dijalankan dengan id yang tidak
//      ada (validasi kolom, 0 baris), INSERT divalidasi lewat SELECT kolomnya.
//   5. Sesi: token palsu ditolak 401.
//
//   node scripts/e2e-check.mjs                                  # produksi
//   BASE=http://localhost:3000 node scripts/e2e-check.mjs       # lokal
//
// Butuh akun admin (env ADMIN_USER / ADMIN_PASS). Kalau DB masih kosong
// (`bootstrap: true`), akun admin itu dibuat otomatis.
import { reads, writes, paramsFor } from './_app-queries.mjs';

const base = (process.env.BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPass = process.env.ADMIN_PASS || 'admin123';

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

async function post(path, body, token) {
  const res = await fetch(base + path, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  let json = {};
  try {
    json = await res.json();
  } catch {
    /* bukan JSON */
  }
  return { code: res.status, json };
}

const sqlAs = (token, sql, params = {}) => post('/api/sql', { sql, params }, token);

/**
 * Ubah query tulis jadi query baca yang memvalidasi tabel + kolomnya, tanpa
 * mengeksekusi tulis apa pun.
 *
 * Kenapa tidak dijalankan saja lalu di-rollback? `/api/sql` menerima satu
 * statement dan tidak punya transaksi, jadi `BEGIN ... ROLLBACK` tidak bisa
 * dikirim. Menjalankan UPDATE/DELETE dengan `WHERE false` pun tidak cukup:
 * `SET played_at=@t` tetap dievaluasi tipenya, dan parameter contoh tidak
 * selalu bertipe sama dengan kolom (nama `@t` dipakai untuk tanggal di satu
 * query, id tim di query lain). Yang benar-benar ingin dibuktikan di sini
 * adalah "tabel dan kolom yang disebut app ada di DB" — itu cukup lewat
 * SELECT, dan izin tulis dibuktikan terpisah oleh round-trip `settings`.
 */
function probeFor(sql) {
  const insert = /^\s*insert\s+into\s+([a-z_][a-z0-9_]*)\s*\(([^)]*)\)/i.exec(sql);
  if (insert) {
    const cols = insert[2].split(',').map((c) => c.trim()).filter(Boolean);
    return `SELECT ${cols.join(', ')} FROM ${insert[1]} LIMIT 0`;
  }

  const update = /^\s*update\s+([a-z_][a-z0-9_]*)\s+set\s+([\s\S]*?)(?:\bwhere\b|$)/i.exec(sql);
  if (update) {
    // Kolom = identifier di kiri `=` pada level teratas SET. Subquery di kanan
    // `=` dilewati supaya kolom di dalamnya tidak ikut dianggap kolom target.
    const cols = [];
    let depth = 0;
    let buf = '';
    for (const ch of update[2]) {
      if (ch === '(') depth++;
      if (ch === ')') depth--;
      if (ch === ',' && depth === 0) {
        cols.push(buf);
        buf = '';
        continue;
      }
      if (depth === 0) buf += ch;
    }
    cols.push(buf);
    const names = cols
      .map((c) => c.split('=')[0].trim())
      .filter((c) => /^[a-z_][a-z0-9_]*$/i.test(c));
    return `SELECT ${names.join(', ')} FROM ${update[1]} LIMIT 0`;
  }

  const del = /^\s*delete\s+from\s+([a-z_][a-z0-9_]*)/i.exec(sql);
  if (del) return `SELECT * FROM ${del[1]} LIMIT 0`;

  return sql;
}

// ---------- 0. Siapkan akun admin ----------
let adminToken = null;
let status = await post('/api/auth', { action: 'status' });
if (status.json.bootstrap) {
  const reg = await post('/api/auth', {
    action: 'register',
    username: adminUser,
    password: adminPass,
  });
  check('admin pertama dibuat', reg.code === 200 && !!reg.json.token, `code ${reg.code}`);
  adminToken = reg.json.token;
} else {
  const login = await post('/api/auth', {
    action: 'login',
    username: adminUser,
    password: adminPass,
  });
  check('login admin', login.code === 200 && !!login.json.token, `code ${login.code}`);
  adminToken = login.json.token;
}
if (!adminToken) {
  console.error('\nTidak bisa masuk sebagai admin. Set ADMIN_USER / ADMIN_PASS.');
  process.exit(1);
}

// ---------- 1. Token palsu ----------
let r = await sqlAs(`${adminToken}x`, 'SELECT 1 AS ok');
check('token dipalsukan ditolak 401', r.code === 401, `code ${r.code}`);

// ---------- 2. Schema: semua baca milik app ----------
console.log('\n-- schema & baca (admin) --');
let schemaBad = 0;
for (const [name, sql] of Object.entries(reads)) {
  r = await sqlAs(adminToken, sql, paramsFor(sql));
  const ok = r.code === 200;
  if (!ok) {
    schemaBad++;
    check(`baca ${name}`, false, `${r.code} ${r.json.error ?? ''}`);
  }
}
check(`semua ${Object.keys(reads).length} query baca jalan`, schemaBad === 0, `${schemaBad} gagal`);

// ---------- 3. Schema: tabel & kolom yang dipakai query tulis ----------
console.log('\n-- schema tulis (tanpa mengubah data) --');
let writeSchemaBad = 0;
for (const [name, sql] of Object.entries(writes)) {
  const probe = probeFor(sql);
  r = await sqlAs(adminToken, probe, paramsFor(sql));
  if (r.code !== 200) {
    writeSchemaBad++;
    check(`kolom tulis ${name}`, false, `${r.code} ${r.json.error ?? ''} :: ${probe.slice(0, 80)}`);
  }
}
check(
  `tabel & kolom ${Object.keys(writes).length} query tulis ada di schema`,
  writeSchemaBad === 0,
  `${writeSchemaBad} gagal`,
);

// ---------- 4. Baca sebagai tamu & anggota ----------
console.log('\n-- hak baca per role --');
const guestReads = await (async () => {
  let bad = 0;
  for (const [name, sql] of Object.entries(reads)) {
    if (name === 'users') continue;
    const res = await sqlAs(null, sql, paramsFor(sql));
    if (res.code !== 200) {
      bad++;
      check(`tamu baca ${name}`, false, `${res.code} ${res.json.error ?? ''}`);
    }
  }
  return bad;
})();
check('tamu bisa membaca semua data klub', guestReads === 0, `${guestReads} gagal`);

r = await sqlAs(null, reads.users);
check('tamu tidak bisa melihat daftar pengguna', r.code === 403, `code ${r.code}`);

// ---------- 5. Akun uji: anggota + bendahara ----------
const stamp = Date.now().toString(36);
const tempPass = `uji-${Math.random().toString(36).slice(2, 12)}`;
const madeIds = [];

async function makeUser(role) {
  const username = `uji_${role}_${stamp}`;
  const res = await post(
    '/api/auth',
    { action: 'create', username, password: tempPass, role },
    adminToken,
  );
  if (res.code !== 200) return { error: `${res.code} ${res.json.error ?? ''}` };
  madeIds.push(res.json.id);
  const login = await post('/api/auth', { action: 'login', username, password: tempPass });
  return { token: login.json.token, username };
}

const memberUser = await makeUser('member');
const treasurerUser = await makeUser('treasurer');

if (memberUser.token) {
  let bad = 0;
  for (const [name, sql] of Object.entries(reads)) {
    if (name === 'users') continue;
    const res = await sqlAs(memberUser.token, sql, paramsFor(sql));
    if (res.code !== 200) {
      bad++;
      check(`anggota baca ${name}`, false, `${res.code} ${res.json.error ?? ''}`);
    }
  }
  check('anggota bisa membaca semua data klub', bad === 0, `${bad} gagal`);

  r = await sqlAs(memberUser.token, reads.users);
  check('anggota tidak bisa melihat daftar pengguna', r.code === 403, `code ${r.code}`);

  r = await sqlAs(
    memberUser.token,
    "INSERT INTO announcements (title, body) VALUES ('_uji', '_uji')",
  );
  check('anggota tidak bisa menulis', r.code === 403, `code ${r.code}`);

  r = await post(
    '/api/auth',
    { action: 'create', username: `x_${stamp}`, password: tempPass, role: 'admin' },
    memberUser.token,
  );
  check('anggota tidak bisa mengelola pengguna', r.code === 403, `code ${r.code}`);
} else {
  check('akun anggota dibuat', false, memberUser.error);
}

// ---------- 6. Tulis oleh bendahara & admin (data sungguhan) ----------
// Tabel `settings` dipakai sebagai kanvas: satu baris kunci sementara, lalu
// dihapus lagi. Ini membuktikan izin tulis benar-benar ada di role DB, bukan
// hanya lolos filter.
const key = `_e2e_${stamp}`;
async function roundTrip(label, token) {
  const ins = await sqlAs(
    token,
    'INSERT INTO settings (key, value) VALUES (@k, @v) ON CONFLICT (key) DO UPDATE SET value=@v',
    { k: key, v: '1' },
  );
  if (ins.code !== 200) return check(label, false, `${ins.code} ${ins.json.error ?? ''}`);
  const del = await sqlAs(token, 'DELETE FROM settings WHERE key=@k', { k: key });
  check(label, del.code === 200, `${del.code} ${del.json.error ?? ''}`);
}

if (treasurerUser.token) await roundTrip('bendahara bisa menulis data klub', treasurerUser.token);
await roundTrip('admin bisa menulis data klub', adminToken);

r = await sqlAs(null, "INSERT INTO settings (key, value) VALUES ('_uji', '1')");
check('tamu tidak bisa menulis', r.code === 403, `code ${r.code}`);

// ---------- 7. Bersihkan akun uji ----------
for (const id of madeIds) {
  await post('/api/auth', { action: 'delete', id }, adminToken);
}
await sqlAs(adminToken, 'DELETE FROM settings WHERE key=@k', { k: key });

// ---------- Ringkasan ----------
const bad = results.filter((x) => !x.ok).length;
console.log(`\nTarget: ${base}`);
console.log(`${results.length - bad}/${results.length} lulus.`);
process.exit(bad ? 1 : 0);
