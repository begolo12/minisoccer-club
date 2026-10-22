// Jalankan SQL ASLI yang dikirim setiap method model ke server sungguhan.
//
// Sumber query: `.audit/queries.json`, direkam `test/queries_audit_test.dart`
// dengan mencegat transport HTTP app. Jadi yang diuji bukan salinan query,
// melainkan string final setelah interpolasi — persis yang dikirim ke
// /api/sql saat pengguna menekan tombol.
//
//   flutter test test/queries_audit_test.dart     # rekam
//   node scripts/audit-queries.mjs                # uji ke server
//   BASE=http://localhost:3000 node scripts/audit-queries.mjs
//
// Yang diperiksa untuk setiap query:
//   1. Lolos filter `_guard.js` untuk admin (kalau ditolak, fitur itu mati).
//   2. Semua parameter `@nama` yang dipakai benar-benar dikirim (kalau tidak,
//      server menjawab 400 "Parameter @x tidak dikirim").
//   3. Tabel dan kolom yang disebut benar-benar ada di DB (lewat probe SELECT;
//      tidak ada tulis yang dieksekusi).
import { readFileSync, existsSync } from 'node:fs';

import { rejectSql } from '../api/_guard.js';
import { probeFor, isRead, paramNames } from './_sql-probe.mjs';

const base = (process.env.BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPass = process.env.ADMIN_PASS || 'admin123';

const file = '.audit/queries.json';
if (!existsSync(file)) {
  console.error(`${file} belum ada. Jalankan dulu:\n  flutter test test/queries_audit_test.dart`);
  process.exit(1);
}
const { queries } = JSON.parse(readFileSync(file, 'utf8'));

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

const login = await post('/api/auth', { action: 'login', username: adminUser, password: adminPass });
if (login.code !== 200) {
  console.error(`Tidak bisa login sebagai ${adminUser}. Set ADMIN_USER/ADMIN_PASS.`);
  process.exit(1);
}
const token = login.json.token;

const problems = [];
let passed = 0;

for (const q of queries) {
  const { label, sql, params } = q;

  // 1. Filter query (admin boleh menulis data klub, tidak boleh users/DDL).
  const blocked = rejectSql(sql, { r: 'admin' });
  if (blocked) {
    problems.push(`${label}: DITOLAK filter — ${blocked}`);
    continue;
  }

  // 2. Kelengkapan parameter.
  const missing = paramNames(sql).filter((n) => !Object.hasOwn(params, n));
  if (missing.length) {
    problems.push(`${label}: parameter tidak dikirim — @${missing.join(', @')}`);
    continue;
  }

  // 3. Tabel + kolom ada di DB (probe baca, tanpa eksekusi tulis).
  const probe = isRead(sql) ? sql : probeFor(sql);
  const res = await post('/api/sql', { sql: probe, params }, token);
  if (res.code !== 200) {
    problems.push(`${label}: ${res.json.error ?? `HTTP ${res.code}`} :: ${probe.slice(0, 90)}`);
    continue;
  }
  passed++;
}

console.log(`Target: ${base}`);
console.log(`${passed}/${queries.length} query lolos.`);
if (problems.length) {
  console.error(`\n${problems.length} masalah:`);
  for (const p of problems) console.error(`  FAIL ${p}`);
  process.exit(1);
}
