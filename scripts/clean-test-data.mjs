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

const PATTERNS = ['_bug_%', '_uji_%', '_flow_%', '_money_%', '_e2e_%', '_audit_%'];
const like = (col) => PATTERNS.map((p) => `${col} LIKE '${p}'`).join(' OR ');

// Urutan penting: anak dulu, induk belakangan (FK).
const steps = [
  ['matches', `DELETE FROM matches WHERE ${like('venue')} OR ${like('opponent')}`],
  ['tournament_teams', `DELETE FROM tournament_teams WHERE team_id IN (SELECT id FROM teams WHERE ${like('name')})`],
  ['tournament_matches', `DELETE FROM tournament_matches WHERE home_team_id IN (SELECT id FROM teams WHERE ${like('name')}) OR away_team_id IN (SELECT id FROM teams WHERE ${like('name')})`],
  ['tournaments', `DELETE FROM tournaments WHERE ${like('name')}`],
  ['team_players', `DELETE FROM team_players WHERE team_id IN (SELECT id FROM teams WHERE ${like('name')}) OR member_id IN (SELECT id FROM members WHERE ${like('name')})`],
  ['teams', `DELETE FROM teams WHERE ${like('name')}`],
  ['payments', `DELETE FROM payments WHERE member_id IN (SELECT id FROM members WHERE ${like('name')})`],
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
