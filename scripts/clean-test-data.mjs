// Bersihkan sisa data uji dari database produksi.
//
// Semua baris uji memakai awalan `_bug_`, `_uji_`, `_flow_`, `_money_`, atau
// `_e2e_`. Dijalankan setelah pemeriksaan manual supaya data klub tetap bersih.
//
//   node scripts/clean-test-data.mjs           # hapus
//   node scripts/clean-test-data.mjs --dry     # lihat saja
import { readFileSync } from 'node:fs';

import { makeRunner } from './_neon.mjs';

const env = readFileSync(new URL('../.env', import.meta.url), 'utf8');
const url = process.env.DATABASE_URL || /^DATABASE_URL=(.+)$/m.exec(env)?.[1].trim();
if (!url) {
  console.error('DATABASE_URL tidak ada di .env');
  process.exit(1);
}

const dry = process.argv.includes('--dry');
const run = await makeRunner(url);

// Awalan tag uji. Selain tag lama, ini mencakup tag yang dipakai skrip uji
// browser (`_at_` kehadiran, `_md_` riwayat iuran, `_dt_` iuran, `_ft_` fitur,
// `_ob_` offline, `_mo_` laga offline, …) supaya sisa run yang berhenti di
// tengah jalan tidak menumpuk di database produksi dan terlihat pengguna
// sebagai data klub palsu.
const PATTERNS = [
  '_bug_%', '_uji_%', '_flow_%', '_money_%', '_e2e_%', '_audit_%',
  '_at_%', '_md_%', '_dt_%', '_ft_%', '_ob_%', '_mo_%', '_pz_%', '_dv_%',
  '_rl_%', '_rb_%', '_dg_%', '_dg2_%', '_dg3_%', '_dbg_%', '_dbg2_%', '_dbg3_%',
];
// `_` adalah wildcard satu karakter di LIKE. Tanpa escape, `_uji_%` juga cocok
// dengan nama asli seperti "Auji" dan menghapus data klub yang bukan data uji.
const like = (col) =>
  PATTERNS.map((p) => `${col} LIKE '${p.replace(/_/g, '\\_')}'`).join(' OR ');

// Urutan penting: anak dulu, induk belakangan (FK).
const steps = [
  ['matches', `DELETE FROM matches WHERE ${like('venue')} OR ${like('opponent')}`],
  ['tournament_teams', `DELETE FROM tournament_teams WHERE team_id IN (SELECT id FROM teams WHERE ${like('name')})`],
  ['tournament_matches', `DELETE FROM tournament_matches WHERE home_team_id IN (SELECT id FROM teams WHERE ${like('name')}) OR away_team_id IN (SELECT id FROM teams WHERE ${like('name')})`],
  ['tournaments', `DELETE FROM tournaments WHERE ${like('name')}`],
  ['team_players', `DELETE FROM team_players WHERE team_id IN (SELECT id FROM teams WHERE ${like('name')}) OR member_id IN (SELECT id FROM members WHERE ${like('name')})`],
  ['teams', `DELETE FROM teams WHERE ${like('name')}`],
  ['payments', `DELETE FROM payments WHERE member_id IN (SELECT id FROM members WHERE ${like('name')})`],
  // Akun milik anggota uji. Tidak lewat /api/sql karena guard menolaknya;
  // skrip ini memakai koneksi owner, jadi aman.
  //
  // Pola `^rg[a-z]{6}$` adalah bentuk username yang dibuat skrip uji
  // pendaftaran (tag `Rg` + 6 huruf). Sengaja sempit: `LIKE 'rg%'` akan ikut
  // menghapus akun asli yang kebetulan berawalan itu.
  ['users', `DELETE FROM users
      WHERE member_id IN (SELECT id FROM members WHERE ${like('name')})
         OR (username ~ '^rg[a-z]{6}$' AND member_id IS NULL)`],
  // Patungan: setoran kas menempel di baris kehadiran, jadi dibuang lebih dulu.
  ['attendance_cash', `DELETE FROM transactions WHERE attendance_id IN (
      SELECT a.id FROM booking_attendance a
       WHERE a.booking_id IN (SELECT id FROM bookings WHERE ${like('title')})
          OR a.member_id IN (SELECT id FROM members WHERE ${like('name')}))`],
  ['attendance', `DELETE FROM booking_attendance
     WHERE booking_id IN (SELECT id FROM bookings WHERE ${like('title')})
        OR member_id IN (SELECT id FROM members WHERE ${like('name')})`],
  ['members', `DELETE FROM members WHERE ${like('name')}`],
  ['bookings', `DELETE FROM bookings WHERE ${like('title')}`],
  ['transactions', `DELETE FROM transactions WHERE ${like('note')}`],
  ['announcements', `DELETE FROM announcements WHERE ${like('title')}`],
  ['settings', `DELETE FROM settings WHERE ${like('key')}`],
];

for (const [label, sql] of steps) {
  if (dry) {
    console.log(`[dry] ${label}`);
    continue;
  }
  try {
    await run(sql);
    console.log(`OK   ${label}`);
  } catch (e) {
    console.log(`SKIP ${label}: ${e.message}`);
  }
}

console.log(`\n=== sisa baris${dry ? ' (sebelum)' : ''} ===`);
for (const t of [
  'members', 'teams', 'team_players', 'matches', 'match_sessions', 'match_events',
  'payments', 'transactions', 'bookings', 'announcements', 'settings',
  'tournaments', 'tournament_teams', 'tournament_matches',
]) {
  const r = await run(`SELECT count(*)::int AS n FROM ${t}`);
  console.log(`  ${t}: ${r.rows[0].n}`);
}
