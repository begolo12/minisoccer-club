// Bersihkan SEMUA sisa data uji dari berbagai awalan tag.
//
// Uji browser yang gagal di tengah jalan meninggalkan anggota/booking, dan
// sisa itu membuat uji berikutnya salah kesimpulan (mis. dialog kehadiran
// berisi 15 nama lama sehingga tombol yang dicari tidak ketemu).
import { readFileSync } from 'node:fs';
import { makeRunner } from './_neon.mjs';

const url = /^DATABASE_URL=(.+)$/m.exec(readFileSync('.env', 'utf8'))[1].trim();
const run = await makeRunner(url);

// Awalan tag uji. Garis bawah di-escape saat dipakai: di SQL `_` adalah
// wildcard satu karakter, jadi pola `_at_%` juga cocok dengan nama asli seperti
// "Natalia" dan akan menghapus anggota klub yang tidak ada hubungannya dengan
// uji.
const patterns = ['_at_%', '_md_%', '_dt_%', '_uji_%', '_flow_%', '_money_%', '_e2e_%',
  '_bug_%', '_audit_%', '_ob_%', '_ft_%', '_mo_%', '_pz_%', '_dv_%', '_rl_%', '_rb_%',
  '_dg_%', '_dg2_%', '_dg3_%', '_dbg_%', '_dbg2_%', '_dbg3_%'];
const like = patterns.map((p) => p.replace(/_/g, '\\_'));

for (const p of like) {
  const bookings = (await run('SELECT id FROM bookings WHERE title LIKE $1', [p])).rows;
  for (const b of bookings) {
    await run('DELETE FROM transactions WHERE attendance_id IN (SELECT id FROM booking_attendance WHERE booking_id=$1)', [b.id]);
    await run('DELETE FROM transactions WHERE booking_id=$1', [b.id]);
    await run('DELETE FROM booking_attendance WHERE booking_id=$1', [b.id]);
    await run('DELETE FROM bookings WHERE id=$1', [b.id]);
  }
  const tours = (await run('SELECT id FROM tournaments WHERE name LIKE $1', [p])).rows;
  for (const t of tours) {
    await run('DELETE FROM payments WHERE tournament_id=$1', [t.id]);
    await run('DELETE FROM tournament_teams WHERE tournament_id=$1', [t.id]);
    await run('DELETE FROM tournament_matches WHERE tournament_id=$1', [t.id]);
    await run('DELETE FROM tournaments WHERE id=$1', [t.id]);
  }
  const teams = (await run('SELECT id FROM teams WHERE name LIKE $1', [p])).rows;
  for (const t of teams) {
    await run('DELETE FROM team_players WHERE team_id=$1', [t.id]);
    await run('DELETE FROM teams WHERE id=$1', [t.id]);
  }
  await run('DELETE FROM payments WHERE member_id IN (SELECT id FROM members WHERE name LIKE $1)', [p]);
  await run('DELETE FROM booking_attendance WHERE member_id IN (SELECT id FROM members WHERE name LIKE $1)', [p]);
  await run('DELETE FROM members WHERE name LIKE $1', [p]);
}

const counts = {};
for (const [label, sql] of Object.entries({
  members: 'SELECT count(*)::int AS n FROM members',
  bookings: 'SELECT count(*)::int AS n FROM bookings',
  attendance: 'SELECT count(*)::int AS n FROM booking_attendance',
  transactions: 'SELECT count(*)::int AS n FROM transactions',
  tournaments: 'SELECT count(*)::int AS n FROM tournaments',
  teams: 'SELECT count(*)::int AS n FROM teams',
  payments: 'SELECT count(*)::int AS n FROM payments',
})) {
  counts[label] = (await run(sql)).rows[0].n;
}
console.log('sisa data:', JSON.stringify(counts));

const names = (await run('SELECT name FROM members ORDER BY name')).rows.map((r) => r.name);
console.log('anggota tersisa:', names.join(', ') || '(kosong)');
