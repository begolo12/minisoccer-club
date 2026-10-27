// Batasi koneksi web ke role `app_web`: tanpa DDL, tanpa kolom password.
// Jalankan sekali: `node scripts/harden-db.mjs` (butuh DATABASE_URL owner).
// Password role dibuat acak dan dicetak sebagai DATABASE_URL_WEB — simpan di Vercel.
//
// Dua mode:
//   * role belum ada  → buat role, pasang password acak, cetak URL-nya.
//   * role sudah ada  → JANGAN sentuh password; hanya perbaiki izin.
//
// Kenapa begitu: dulu skrip ini selalu `ALTER ROLE ... PASSWORD` dengan nilai
// acak baru. Akibatnya setiap kali dijalankan (mis. setelah `db:init` yang
// membuat ulang view), kredensial di Vercel jadi kedaluwarsa dan seluruh app
// menjawab "Query gagal dijalankan" sampai env diperbarui. Untuk merotasi
// password dengan sengaja, pakai `npm run db:rotate -- app_web`.
import { randomBytes } from 'node:crypto';

import { makeRunner } from './_neon.mjs';
import { APP_WEB_TABLES, APP_WEB_VIEWS } from './_grants.mjs';

const owner = process.env.DATABASE_URL;
if (!owner) {
  console.error('DATABASE_URL belum diset.');
  process.exit(1);
}

const runOwner = await makeRunner(owner);

const exists = await runOwner("SELECT 1 FROM pg_roles WHERE rolname = 'app_web'");
const isNew = !exists.rows?.length;
// Password hanya dipasang kalau role baru dibuat, atau kalau pemanggil
// menuliskan password secara eksplisit lewat APP_WEB_PASSWORD. Tanpa dua
// syarat itu, password lama dibiarkan supaya kredensial di Vercel tetap sah.
const explicitPassword = process.env.APP_WEB_PASSWORD;
const setPassword = isNew || Boolean(explicitPassword);
const password = explicitPassword || randomBytes(18).toString('base64url');

if (isNew) {
  await runOwner(`CREATE ROLE app_web LOGIN PASSWORD '${password}'`);
} else if (setPassword) {
  await runOwner(`ALTER ROLE app_web WITH LOGIN PASSWORD '${password}'`);
} else {
  await runOwner('ALTER ROLE app_web WITH LOGIN');
}

const setup = [
  'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_web',
  'REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM app_web',
  'REVOKE ALL ON SCHEMA public FROM app_web',
  'GRANT USAGE ON SCHEMA public TO app_web',
  // Batas waktu per statement. Filter `_guard.js` memeriksa bentuknya, bukan
  // biayanya: satu JOIN besar tetap bisa menyandera fungsi Vercel sampai
  // timeout platform. Batas 8 detik cukup untuk laporan terbesar di app ini
  // (klasemen semua laga) dan memutus query yang salah tulis.
  "ALTER ROLE app_web SET statement_timeout = '8s'",
  "ALTER ROLE app_web SET idle_in_transaction_session_timeout = '10s'",
  // users: hanya kolom aman. password_hash sengaja tidak diberikan.
  'GRANT SELECT (id, username, role, member_id, active, created_at, token_version) ON users TO app_web',
  `GRANT SELECT, INSERT, UPDATE, DELETE ON
     ${APP_WEB_TABLES.join(', ')}
   TO app_web`,
  // Jejak audit: hanya tambah dan baca. Tanpa UPDATE/DELETE, catatan yang sudah
  // dibuat tidak bisa dihapus lewat koneksi aplikasi — termasuk kalau suatu saat
  // ada bug yang mengirim DELETE ke tabel ini.
  'GRANT SELECT, INSERT ON audit_log TO app_web',
  'GRANT USAGE, SELECT ON SEQUENCE audit_log_id_seq TO app_web',
  'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_web',
  `GRANT SELECT ON ${APP_WEB_VIEWS.join(', ')} TO app_web`,
];

for (const q of setup) await runOwner(q);

// Uji batas akses hanya mungkin kalau password-nya kita ketahui.
const knownPassword = setPassword;
const web = new URL(owner);
web.username = 'app_web';
if (knownPassword) web.password = password;
const runWeb = await makeRunner(web.toString());

// ---- uji batas akses ----
const mustOk = [
  'SELECT count(*)::int AS n FROM members',
  "INSERT INTO announcements (title, body) VALUES ('_uji_akses', '_uji_akses') RETURNING id",
];
const mustFail = [
  'SELECT password_hash FROM users LIMIT 1',
  "UPDATE users SET password_hash = 'x' WHERE id = 1",
  'DROP TABLE announcements',
  'CREATE TABLE _uji_akses (id int)',
];

let bad = 0;
if (!knownPassword) {
  // Password tidak diketahui (role lama, tidak diset lewat env), jadi koneksi
  // sebagai app_web tidak bisa diuji. Izin tetap sudah diperbaiki di atas;
  // uji batas akses lengkap ada di `npm run check:e2e` yang memakai token app.
  console.log('OK — izin app_web diperbarui (password tidak diubah).');
  console.log('     Uji batas akses: npm run check:e2e');
  process.exit(0);
}

for (const q of mustOk) {
  try {
    await runWeb(q);
  } catch (e) {
    bad++;
    console.error('HARUS BOLEH tapi gagal:', q, '->', e.message);
  }
}
for (const q of mustFail) {
  try {
    await runWeb(q);
    bad++;
    console.error('HARUS DITOLAK tapi lolos:', q);
  } catch {
    /* diharapkan gagal */
  }
}
await runOwner("DELETE FROM announcements WHERE title = '_uji_akses'").catch(() => {});

if (bad) {
  console.error(`GAGAL: ${bad} pemeriksaan tidak sesuai.`);
  process.exit(1);
}

console.log(`OK — role app_web ${isNew ? 'dibuat' : 'diperbarui'}, 6 pemeriksaan akses lulus.`);
if (setPassword) {
  console.log(`DATABASE_URL_WEB=${web.toString()}`);
} else {
  console.log('Password app_web tidak diubah (pakai password yang sudah ada di Vercel).');
  console.log('Untuk merotasi dengan sengaja: npm run db:rotate -- app_web');
}
