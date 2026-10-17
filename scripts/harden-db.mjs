// Batasi koneksi web ke role `app_web`: tanpa DDL, tanpa kolom password.
// Jalankan sekali: `node scripts/harden-db.mjs` (butuh DATABASE_URL owner).
// Password role dibuat acak dan dicetak sebagai DATABASE_URL_WEB — simpan di Vercel.
import { request } from 'node:https';
import { resolve4 } from 'node:dns/promises';
import { randomBytes } from 'node:crypto';

const owner = process.env.DATABASE_URL;
if (!owner) {
  console.error('DATABASE_URL belum diset.');
  process.exit(1);
}

const host = new URL(owner).hostname;
const [ip] = await resolve4(host);
// ponytail: paksa IPv4, tanpa fallback IPv6 (lihat scripts/init-db.mjs).
const lookup = (_h, o, cb) => (o.all ? cb(null, [{ address: ip, family: 4 }]) : cb(null, ip, 4));

function run(conn, query, params = []) {
  const body = JSON.stringify({ query, params });
  return new Promise((resolve, reject) => {
    const req = request(
      {
        host,
        servername: host,
        lookup,
        family: 4,
        path: '/sql',
        method: 'POST',
        timeout: 30000,
        headers: {
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(body),
          'neon-connection-string': conn,
          'neon-pooler': 'true',
        },
      },
      (res) => {
        let raw = '';
        res.on('data', (d) => (raw += d));
        res.on('end', () => {
          let json = {};
          try {
            json = JSON.parse(raw);
          } catch {
            return reject(new Error(`HTTP ${res.statusCode}: ${raw.slice(0, 200)}`));
          }
          if (res.statusCode !== 200) return reject(new Error(json.message || raw));
          resolve(json);
        });
      },
    );
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', reject);
    req.end(body);
  });
}

const password = process.env.APP_WEB_PASSWORD || randomBytes(18).toString('base64url');

const exists = await run(owner, "SELECT 1 FROM pg_roles WHERE rolname = 'app_web'");
if (!exists.rows?.length) await run(owner, 'CREATE ROLE app_web LOGIN');

const setup = [
  `ALTER ROLE app_web WITH LOGIN PASSWORD '${password}'`,
  'REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_web',
  'REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM app_web',
  'REVOKE ALL ON SCHEMA public FROM app_web',
  'GRANT USAGE ON SCHEMA public TO app_web',
  // users: hanya kolom aman. password_hash sengaja tidak diberikan.
  'GRANT SELECT (id, username, role, member_id, active, created_at) ON users TO app_web',
  `GRANT SELECT, INSERT, UPDATE, DELETE ON
     members, matches, match_sessions, match_events, transactions, payments,
     bookings, announcements, settings, tournaments, teams, team_players,
     tournament_matches
   TO app_web`,
  'GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_web',
  'GRANT SELECT ON v_monthly_finance, v_player_stats, v_standings TO app_web',
];

for (const q of setup) await run(owner, q);

const web = new URL(owner);
web.username = 'app_web';
web.password = password;

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
    await run(web.toString(), q);
  } catch (e) {
    bad++;
    console.error('HARUS BOLEH tapi gagal:', q, '->', e.message);
  }
}
for (const q of mustFail) {
  try {
    await run(web.toString(), q);
    bad++;
    console.error('HARUS DITOLAK tapi lolos:', q);
  } catch {
    /* diharapkan gagal */
  }
}
await run(owner, "DELETE FROM announcements WHERE title = '_uji_akses'").catch(() => {});

if (bad) {
  console.error(`GAGAL: ${bad} pemeriksaan tidak sesuai.`);
  process.exit(1);
}

console.log('OK — role app_web siap, 6 pemeriksaan akses lulus.');
console.log(`DATABASE_URL_WEB=${web.toString()}`);
