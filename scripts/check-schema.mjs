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

// Kolom yang dipakai app (lib/data/models.dart) + kolom wajib dari
// db/schema.sql. Daftar ini sengaja eksplisit: menambah kolom baru di schema
// berarti menambah baris di sini, dan itu yang membuat drift ketahuan lebih
// awal daripada lewat layar error di HP pengguna.
const EXPECTED = {
  members: ['id', 'name', 'phone', 'position', 'jersey', 'active', 'joined_at'],
  // `users` hanya bisa dibaca admin, jadi tanpa token endpoint menjawab 403
  // ("Hanya admin yang bisa melihat pengguna"). Itu jawaban yang benar, bukan
  // schema yang kurang — kolomnya diperiksa lewat e2e-check yang punya token.
  users: ['id', 'username', 'role', 'member_id', 'active', 'created_at', 'failed_attempts', 'locked_until'],
  matches: [
    'id', 'played_at', 'venue', 'status', 'goals_for', 'goals_against', 'notes',
    'home_team_id', 'away_team_id',
  ],
  match_sessions: ['id', 'match_id', 'session_no', 'score_home', 'score_away', 'winner', 'started_at', 'ended_at'],
  match_events: ['id', 'match_id', 'session_id', 'member_id', 'minute', 'type'],
  transactions: ['id', 'kind', 'category', 'amount', 'occurred_at', 'member_id', 'period', 'note', 'created_at', 'booking_id'],
  payments: ['id', 'member_id', 'amount', 'period', 'paid_at', 'note'],
  bookings: ['id', 'title', 'starts_at', 'duration_min', 'cost', 'status'],
  announcements: ['id', 'title', 'body', 'created_at'],
  settings: ['key', 'value'],
  teams: ['id', 'name', 'created_at'],
  team_players: ['team_id', 'member_id'],
  tournaments: ['id', 'name', 'venue', 'starts_at', 'match_minutes', 'break_minutes', 'groups', 'status', 'created_at'],
  tournament_teams: ['tournament_id', 'team_id', 'group_no'],
  tournament_matches: [
    'id', 'tournament_id', 'group_no', 'round', 'slot', 'home_team_id', 'away_team_id',
    'kickoff', 'score_home', 'score_away', 'status',
  ],
};

const EXPECTED_VIEWS = ['v_team_standings'];

async function ask(sql) {
  const res = await fetch(`${base}/api/sql`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
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
  if (status === 403 && table === 'users') return true; // butuh admin, bukan schema
  if (status !== 200) {
    const msg = body?.error || `HTTP ${status}`;
    // Tabel tidak ada dan kolom tidak ada sama-sama 400 dari /api/sql.
    problems.push(`${table}.${column}: ${msg}`);
    return false;
  }
  return true;
}

async function checkTable(table, columns) {
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
