// Batasi koneksi web ke role `app_web`: tanpa DDL, tanpa kolom password.
// Jalankan sekali: `node scripts/harden-db.mjs` (butuh DATABASE_URL owner).
// Password role dibuat acak dan dicetak sebagai DATABASE_URL_WEB — simpan di Vercel.
import { randomBytes } from 'node:crypto';

import { makeRunner } from './_neon.mjs';
import { APP_WEB_TABLES, APP_WEB_VIEWS } from './_grants.mjs';

const owner = process.env.DATABASE_URL;
if (!owner) {
  console.error('DATABASE_URL belum diset.');
  process.exit(1);
}

const runOwner = await makeRunner(owner);

const password = process.env.APP_WEB_PASSWORD || randomBytes(18).toString('base64url');

const exists = await runOwner("SELECT 1 FROM pg_roles WHERE rolname = 'app_web'");
if (!exists.rows?.length) await runOwner('CREATE ROLE app_web LOGIN');

const setup = [
  `ALTER ROLE app_web WITH LOGIN PASSWORD '${password}'`,
  'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_web',
  'REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM app_web',
  'REVOKE ALL ON SCHEMA public FROM app_web',
  'GRANT USAGE ON SCHEMA public TO app_web',
  // users: hanya kolom aman. password_hash sengaja tidak diberikan.
  'GRANT SELECT (id, username, role, member_id, active, created_at) ON users TO app_web',
  `GRANT SELECT, INSERT, UPDATE, DELETE ON
     ${APP_WEB_TABLES.join(', ')}
   TO app_web`,
  'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_web',
  `GRANT SELECT ON ${APP_WEB_VIEWS.join(', ')} TO app_web`,
];

for (const q of setup) await runOwner(q);

const web = new URL(owner);
web.username = 'app_web';
web.password = password;
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

console.log('OK — role app_web siap, 6 pemeriksaan akses lulus.');
console.log(`DATABASE_URL_WEB=${web.toString()}`);
