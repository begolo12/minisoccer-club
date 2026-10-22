// Rapikan data lama supaya cocok dengan aturan baru.
//
//   1. Booking berbiaya yang belum pernah masuk kas → dibuatkan catatan
//      pengeluaran "Sewa lapangan" yang tertaut (`booking_id`). Tanpa ini
//      "Total sewa" di halaman Booking dan saldo Kas menghitung dua angka
//      berbeda untuk uang yang sama.
//   2. Iuran ganda untuk anggota + periode yang sama → disisakan yang
//      terbaru (paid_at terbesar, lalu id terbesar).
//   3. Index unik iuran dipasang setelah datanya bersih.
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
const payments = (
  await run(
    `SELECT id, member_id, period, amount, paid_at FROM payments
      ORDER BY member_id, period, paid_at DESC, id DESC`,
  )
).rows;

const keep = new Map();
const dupes = [];
for (const p of payments) {
  const key = `${p.member_id}|${p.period}`;
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

// ---------- 3. Index unik ----------
if (dry) {
  console.log('[dry] index unik iuran tidak dibuat.');
} else {
  try {
    await run('CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_member_period ON payments (member_id, period)');
    console.log('index unik iuran: siap (idx_payments_member_period).');
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
         SELECT 1 FROM payments GROUP BY member_id, period HAVING count(*) > 1
       ) d`,
    )
  ).rows[0].n;
  console.log(`sisa booking tanpa kas: ${stillOrphan} • sisa grup iuran ganda: ${stillDupe}`);
  if (stillOrphan || stillDupe) process.exit(1);
}
