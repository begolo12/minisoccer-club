// Rapikan data lama supaya cocok dengan aturan baru.
//
//   1. Booking berbiaya yang belum pernah masuk kas → dibuatkan catatan
//      pengeluaran "Sewa lapangan" yang tertaut (`booking_id`). Tanpa ini
//      "Total sewa" di halaman Booking dan saldo Kas menghitung dua angka
//      berbeda untuk uang yang sama.
//   2. Iuran ganda untuk anggota + periode yang sama → disisakan yang
//      terbaru (paid_at terbesar, lalu id terbesar).
//   3. Laga warisan schema v1 (tanpa `home_team_id`/`away_team_id`) →
//      dihapus. Laga lama itu memakai kolom `opponent` (nama lawan luar) dan
//      tidak bisa dimainkan, diskor, atau masuk klasemen di app sekarang;
//      dibiarkan berarti ia muncul sebagai "Tim dihapus" di halaman Tanding.
//      Sesi dan catatan golnya ikut terhapus lewat ON DELETE CASCADE.
//   4. Index unik iuran dipasang setelah datanya bersih.
//
// Idempoten: aman dijalankan berkali-kali. Pakai `--dry` untuk melihat
// rencananya saja.
//
//   DATABASE_URL=postgresql://... npm run db:fix
//   DATABASE_URL=postgresql://... npm run db:fix -- --dry
import { makeRunner } from './_neon.mjs';

const url = process.env.DATABASE_URL;
if (!url) {
  console.error('DATABASE_URL belum diset.');
  process.exit(1);
}

const dry = process.argv.includes('--dry');
const run = await makeRunner(url);
const money = (v) => `Rp ${Number(v).toLocaleString('id-ID')}`;

// ---------- 1. Booking → kas ----------
const orphans = (
  await run(
    `SELECT b.id, b.title, b.cost, b.starts_at FROM bookings b
      LEFT JOIN transactions t ON t.booking_id = b.id
      WHERE b.cost > 0 AND t.id IS NULL
      ORDER BY b.starts_at`,
  )
).rows;

for (const b of orphans) {
  if (dry) continue;
  await run(
    `INSERT INTO transactions (kind, category, amount, occurred_at, note, booking_id)
     VALUES ('expense', 'sewa', $1, $2, $3, $4)`,
    [b.cost, b.starts_at, b.title, b.id],
  );
}
console.log(
  `${dry ? '[dry] ' : ''}booking belum masuk kas: ${orphans.length}` +
    (orphans.length ? ` (${orphans.map((b) => `${b.title} ${money(b.cost)}`).join(', ')})` : ''),
);

// ---------- 2. Iuran ganda ----------
// Dulu dikelompokkan per `payments.period` (iuran bulanan). Kolom itu sudah
// dihapus; kunci yang benar sekarang adalah pasangan anggota + turnamen —
// sama dengan `payments_member_tournament_uniq`. Script ini dulu GAGAL total
// di sini karena masih menyebut kolom yang tidak ada.
const payments = (
  await run(
    `SELECT id, member_id, tournament_id, amount, paid_at FROM payments
      ORDER BY member_id, tournament_id, paid_at DESC, id DESC`,
  )
).rows;

const keep = new Map();
const dupes = [];
for (const p of payments) {
  const key = `${p.member_id}|${p.tournament_id}`;
  if (!keep.has(key)) keep.set(key, p);
  else dupes.push(p);
}

for (const p of dupes) {
  if (dry) continue;
  await run('DELETE FROM payments WHERE id = $1', [p.id]);
}
console.log(
  `${dry ? '[dry] ' : ''}iuran ganda dihapus: ${dupes.length}` +
    (dupes.length ? ` (id ${dupes.map((p) => p.id).join(', ')})` : ''),
);

// ---------- 3. Laga warisan schema v1 ----------
// Kolom `home_team_id`/`away_team_id` baru ada sejak tanding internal. Baris
// yang masih NULL berasal dari versi lama (lawan luar, hanya `opponent`).
const legacy = (
  await run(
    `SELECT id, opponent, played_at FROM matches
      WHERE home_team_id IS NULL OR away_team_id IS NULL
      ORDER BY played_at`,
  )
).rows;

if (!dry) {
  for (const m of legacy) {
    await run('DELETE FROM matches WHERE id = $1', [m.id]);
  }
}
console.log(
  `${dry ? '[dry] ' : ''}laga lama tanpa tim dihapus: ${legacy.length}` +
    (legacy.length
      ? ` (${legacy.map((m) => `#${m.id} ${m.opponent ?? '—'}`).join(', ')})`
      : ''),
);

// ---------- 4. Index unik ----------
if (dry) {
  console.log('[dry] index unik iuran tidak dibuat.');
} else {
  try {
    // Kunci iuran sekarang anggota + TURNAMEN. Index lama
    // `idx_payments_member_period` tidak bisa dibuat lagi karena kolom
    // `period` sudah dihapus.
    await run(
      'CREATE UNIQUE INDEX IF NOT EXISTS payments_member_tournament_uniq ON payments (member_id, tournament_id)',
    );
    console.log('index unik iuran: siap (payments_member_tournament_uniq).');
  } catch (e) {
    console.error('index unik iuran GAGAL:', e.message);
    process.exit(1);
  }
}

// ---------- Ringkasan akhir ----------
if (!dry) {
  const stillOrphan = (
    await run(
      `SELECT count(*)::int AS n FROM bookings b
        LEFT JOIN transactions t ON t.booking_id = b.id
        WHERE b.cost > 0 AND t.id IS NULL`,
    )
  ).rows[0].n;
  const stillDupe = (
    await run(
      `SELECT count(*)::int AS n FROM (
         SELECT 1 FROM payments GROUP BY member_id, tournament_id HAVING count(*) > 1
       ) d`,
    )
  ).rows[0].n;
  const stillLegacy = (
    await run(
      `SELECT count(*)::int AS n FROM matches
        WHERE home_team_id IS NULL OR away_team_id IS NULL`,
    )
  ).rows[0].n;
  console.log(
    `sisa booking tanpa kas: ${stillOrphan} • sisa grup iuran ganda: ${stillDupe}` +
      ` • sisa laga tanpa tim: ${stillLegacy}`,
  );
  if (stillOrphan || stillDupe || stillLegacy) process.exit(1);
}
