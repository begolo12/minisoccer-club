// Cek schema database produksi lewat endpoint publik /api/sql.
//
// Kenapa lewat endpoint, bukan koneksi langsung? Supaya bisa dijalankan tanpa
// memegang connection string (mis. dari mesin siapa pun), dan yang diuji
// adalah jalur yang benar-benar dipakai app: role terbatas `app_web` + filter
// `_guard.js`. Kalau sebuah kolom/tabel/view hilang di DB atau izinnya lupa
// diberikan, gejalanya di app adalah "Query gagal dijalankan" di seluruh
// halaman — persis yang terjadi pada rilis "Publik read-only".
//
//   node scripts/check-schema.mjs                      # produksi
//   API_BASE=http://localhost:3000 node scripts/check-schema.mjs
//
// Exit code 1 kalau ada yang kurang, jadi bisa dipakai di CI setelah deploy.
const base = (process.env.API_BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');

// Tabel uang (kas, iuran, sewa, pengaturan) DITOLAK untuk tamu sejak mode
// publik dilock. Tanpa token, pemeriksaan schema melaporkan lima "masalah"
// yang sebenarnya bukan masalah — itu jawaban guard, bukan kolom yang hilang.
// Jadi: masuk sebagai admin kalau kredensial tersedia; kalau tidak, tabel
// tersebut ditandai "tidak diperiksa" alih-alih gagal.
import { adminCredentials } from './_admin-auth.mjs';

let token = null;
try {
  const { user, pass } = adminCredentials();
  const res = await fetch(`${base}/api/auth`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'login', username: user, password: pass }),
  });
  if (res.ok) {
    const body = await res.json();
    if (typeof body.token === 'string') token = body.token;
  }
} catch {
  // Kredensial tidak ada: lanjut sebagai tamu.
}

// Kolom yang dipakai app (lib/data/models.dart) + kolom wajib dari
// db/schema.sql. Daftar ini sengaja eksplisit: menambah kolom baru di schema
// berarti menambah baris di sini, dan itu yang membuat drift ketahuan lebih
// awal daripada lewat layar error di HP pengguna.
const EXPECTED = {
  members: ['id', 'name', 'phone', 'address', 'position', 'jersey', 'active', 'joined_at'],
  // `users` hanya bisa dibaca admin, jadi tanpa token endpoint menjawab 403
  // ("Hanya admin yang bisa melihat pengguna"). Itu jawaban yang benar, bukan
  // schema yang kurang — kolomnya diperiksa lewat e2e-check yang punya token.
  users: ['id', 'username', 'role', 'member_id', 'active', 'created_at', 'failed_attempts', 'locked_until', 'token_version'],
  matches: [
    'id', 'played_at', 'venue', 'status', 'goals_for', 'goals_against', 'notes',
    'home_team_id', 'away_team_id',
  ],
  match_sessions: ['id', 'match_id', 'session_no', 'score_home', 'score_away', 'winner', 'started_at', 'ended_at'],
  match_events: ['id', 'match_id', 'session_id', 'member_id', 'minute', 'type'],
  transactions: ['id', 'kind', 'category', 'amount', 'occurred_at', 'member_id', 'note', 'created_at', 'booking_id', 'attendance_id'],
  // Iuran terikat TURNAMEN, bukan bulan: `period` sudah dihapus, diganti
  // `tournament_id`. Index unik (member_id, tournament_id) mencegah satu
  // anggota tercatat dua kali untuk turnamen yang sama.
  payments: ['id', 'member_id', 'amount', 'tournament_id', 'paid_at', 'note'],
  bookings: ['id', 'title', 'starts_at', 'duration_min', 'cost', 'status'],
  // Kehadiran per sesi + patungan biaya lapangan.
  booking_attendance: ['id', 'booking_id', 'member_id', 'share_amount', 'paid_at', 'note', 'created_at'],
  announcements: ['id', 'title', 'body', 'created_at'],
  settings: ['key', 'value'],
  teams: ['id', 'name', 'created_at'],
  team_players: ['team_id', 'member_id'],
  tournaments: [
    'id', 'name', 'venue', 'starts_at', 'match_minutes', 'break_minutes',
    'groups', 'entry_fee', 'status', 'created_at',
  ],
  tournament_teams: ['tournament_id', 'team_id', 'group_no'],
  tournament_matches: [
    'id', 'tournament_id', 'group_no', 'round', 'slot', 'home_team_id', 'away_team_id',
    'kickoff', 'score_home', 'score_away', 'status',
  ],
  // Jejak audit: diisi server (`api/sql.js`), dibaca admin saja. Tanpa token
  // setiap kolomnya dijawab 403 — lihat pengecualian di `checkColumn`.
  audit_log: ['id', 'at', 'actor', 'role', 'tbl', 'op', 'row_id', 'detail'],
};

const EXPECTED_VIEWS = ['v_team_standings'];

// Kolom yang tidak bisa ditanyakan tanpa token karena privasi (lihat
// api/_privacy.js). Endpoint menjawab 403 untuk kolom-kolom ini — itu
// jawaban yang benar, bukan schema yang kurang.
const PRIVATE_COLUMNS = new Set(['phone', 'address']);

// Tabel yang ditutup untuk tamu (lihat api/_guard.js): tanpa token dijawab 403.
// Skrip ini jalan tanpa token, jadi 403 di sini adalah jawaban yang benar.
const GUEST_ONLY_TABLES = new Set([
  'transactions',
  'payments',
  'bookings',
  'booking_attendance',
  'settings',
]);

async function ask(sql) {
  const res = await fetch(`${base}/api/sql`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ sql, params: {} }),
  });
  const body = await res.json().catch(() => ({}));
  return { status: res.status, body };
}

const problems = [];
const notes = [];

async function checkColumn(table, column) {
  // LIMIT 0: tidak butuh baris, tapi Postgres tetap memvalidasi nama kolom.
  const { status, body } = await ask(`SELECT "${column}" FROM "${table}" LIMIT 0`);
  // Kolom yang butuh role khusus dijawab 403 — itu jawaban yang benar,
  // bukan schema yang kurang. `users` hanya untuk admin; `phone`/`address`
  // anggota hanya untuk admin/bendahara (lihat api/_privacy.js). Kolomnya
  // diperiksa lewat e2e-check yang punya token.
  // Tanpa kredensial admin, tabel uang memang tertutup untuk tamu. Itu bukan
  // schema yang kurang — jangan dilaporkan sebagai kegagalan.
  if (status === 403 && GUEST_ONLY_TABLES.has(table) && !token) {
    notes.push(`${table}: tidak diperiksa (butuh ADMIN_USER/ADMIN_PASS)`);
    return true;
  }
  if (status === 403 &&
      (table === 'users' ||
        table === 'audit_log' ||
        GUEST_ONLY_TABLES.has(table) ||
        PRIVATE_COLUMNS.has(column))) {
    return true;
  }
  if (status !== 200) {
    const msg = body?.error || `HTTP ${status}`;
    // Tabel tidak ada dan kolom tidak ada sama-sama 400 dari /api/sql.
    problems.push(`${table}.${column}: ${msg}`);
    return false;
  }
  return true;
}

async function checkTable(table, columns) {
  // `users` sengaja tidak bisa diperiksa lewat jalur ini: role `app_web`
  // hanya diberi SELECT pada kolom aman (id, username, role, member_id,
  // active, created_at, token_version). Kolom kunci login — `failed_attempts`,
  // `locked_until` — tidak pernah bisa dibaca dari sini, dan itu memang
  // tujuannya. Keberadaannya diperiksa `db:init` yang memakai koneksi owner.
  if (table === 'users') {
    notes.push('users: tidak diperiksa lewat /api/sql (kolom kunci tidak di-grant)');
    return;
  }
  const ok = await checkColumn(table, columns[0]);
  if (!ok) return; // tabelnya sendiri hilang; jangan banjiri output
  let missing = 0;
  for (const col of columns.slice(1)) {
    if (!(await checkColumn(table, col))) missing++;
  }
  if (missing === 0) notes.push(`${table}: lengkap (${columns.length} kolom)`);
}

for (const [table, columns] of Object.entries(EXPECTED)) {
  await checkTable(table, columns);
}

for (const view of EXPECTED_VIEWS) {
  const { status, body } = await ask(`SELECT * FROM "${view}" LIMIT 0`);
  if (status !== 200) {
    problems.push(`view ${view}: ${body?.error || `HTTP ${status}`}`);
  } else {
    notes.push(`view ${view}: ada`);
  }
}

console.log(`Target: ${base}`);
for (const n of notes) console.log(`  OK   ${n}`);
if (problems.length) {
  console.error(`\n${problems.length} masalah schema:`);
  for (const p of problems) console.error(`  FAIL ${p}`);
  console.error('\nPerbaikan: jalankan `npm run db:init` lalu `npm run db:harden` dengan DATABASE_URL owner.');
  process.exit(1);
}
console.log('\nSchema produksi cocok dengan db/schema.sql.');
