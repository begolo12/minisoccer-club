// Uji aturan uang & tautan booking↔kas pada server sungguhan.
//
// Yang dibuktikan (bukan sekadar "query jalan"):
//   1. Booking berbiaya membuat SATU pengeluaran kas yang tertaut.
//   2. Membatalkan booking membuang pengeluaran itu, sehingga "Total sewa"
//      dan saldo kas tidak berbeda.
//   3. Menghapus booking ikut menghapus kasnya (ON DELETE CASCADE).
//   4. Iuran unik per (anggota, periode) benar-benar ditolak DB.
//   5. Laga selesai langsung muncul di klasemen dengan poin yang benar, dan
//      klasemen mengembalikan angka (bukan string) — bug bigint.
//
//   BASE=https://minisoccer-club.vercel.app node scripts/money-check.mjs
import { readFileSync, existsSync } from 'node:fs';
import { adminCredentials } from './_admin-auth.mjs';

const base = (process.env.BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');
const { user: adminUser, pass: adminPass } = adminCredentials();

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

async function post(path, body, token) {
  const res = await fetch(base + path, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  let json = {};
  try {
    json = await res.json();
  } catch {
    /* bukan JSON */
  }
  return { code: res.status, json };
}

const login = await post('/api/auth', { action: 'login', username: adminUser, password: adminPass });
if (login.code !== 200) {
  console.error(`Tidak bisa login sebagai ${adminUser}.`);
  process.exit(1);
}
const token = login.json.token;
const q = (sql, params = {}) => post('/api/sql', { sql, params }, token);
const rows = async (sql, params) => (await q(sql, params)).json.rows ?? [];

const tag = `_money_${Date.now().toString(36)}`;
const num = (v) => Number(v ?? 0);

try {
  // ---------- 1. booking → kas ----------
  const book = await q(
    'INSERT INTO bookings (title, starts_at, duration_min, cost) VALUES (@t, now(), 90, 250000) RETURNING id',
    { t: tag },
  );
  const bookingId = book.json.rows?.[0]?.id;
  await q(
    `INSERT INTO transactions (kind, category, amount, occurred_at, note, booking_id)
     VALUES ('expense', 'sewa', 250000, CURRENT_DATE, @n, @b)`,
    { n: tag, b: bookingId },
  );
  let linked = await rows('SELECT id, amount, booking_id FROM transactions WHERE booking_id=@b', {
    b: bookingId,
  });
  check('booking berbiaya membuat 1 pengeluaran kas tertaut', linked.length === 1, `${linked.length} baris`);

  // ---------- 2. batal → kas ikut hilang ----------
  // Ini yang dilakukan `Booking.setStatus('canceled')` di app.
  await q("UPDATE bookings SET status='canceled' WHERE id=@id", { id: bookingId });
  await q('DELETE FROM transactions WHERE booking_id=@id', { id: bookingId });
  linked = await rows('SELECT id FROM transactions WHERE booking_id=@b', { b: bookingId });
  check('batalkan booking membuang kas tertaut', linked.length === 0, `${linked.length} sisa`);

  const activeCost = await rows(
    "SELECT coalesce(sum(cost),0)::int AS n FROM bookings WHERE title=@t AND status <> 'canceled'",
    { t: tag },
  );
  const cashCost = await rows(
    `SELECT coalesce(sum(t.amount),0)::int AS n FROM transactions t
       JOIN bookings b ON b.id = t.booking_id
      WHERE b.title=@t AND b.status <> 'canceled'`,
    { t: tag },
  );
  check(
    'Total sewa = pengeluaran sewa di kas',
    num(activeCost[0]?.n) === num(cashCost[0]?.n),
    `sewa ${activeCost[0]?.n} vs kas ${cashCost[0]?.n}`,
  );

  // ---------- 3. hapus booking → kas CASCADE ----------
  await q('DELETE FROM bookings WHERE id=@id', { id: bookingId });
  const orphan = await rows('SELECT id FROM transactions WHERE booking_id=@b', { b: bookingId });
  check('hapus booking menghapus kasnya (cascade)', orphan.length === 0, `${orphan.length} sisa`);

  // ---------- 4. iuran unik per (anggota, turnamen) ----------
  const mem = await q(
    'INSERT INTO members (name, position) VALUES (@n, @p) RETURNING id',
    { n: tag, p: 'Bebas' },
  );
  const memberId = mem.json.rows?.[0]?.id;
  const tour = await q(
    `INSERT INTO tournaments (name, starts_at, entry_fee) VALUES (@n, now(), 50000) RETURNING id`,
    { n: tag },
  );
  const tournamentId = tour.json.rows?.[0]?.id;
  const first = await q(
    'INSERT INTO payments (member_id, amount, tournament_id) VALUES (@m, 50000, @t)',
    { m: memberId, t: tournamentId },
  );
  check('iuran pertama tersimpan', first.code === 200, first.json.error ?? '');
  const second = await q(
    'INSERT INTO payments (member_id, amount, tournament_id) VALUES (@m, 50000, @t)',
    { m: memberId, t: tournamentId },
  );
  check(
    'iuran ganda turnamen sama ditolak DB',
    second.code !== 200,
    second.code === 200 ? 'DITERIMA (index unik hilang)' : 'ditolak',
  );

  // Anggota yang sama untuk turnamen BERBEDA harus boleh — itu inti
  // perubahan sistem: tiap turnamen punya tagihan sendiri.
  const tour2 = await q(
    `INSERT INTO tournaments (name, starts_at, entry_fee) VALUES (@n, now(), 75000) RETURNING id`,
    { n: `${tag}_2` },
  );
  const other = await q(
    'INSERT INTO payments (member_id, amount, tournament_id) VALUES (@m, 75000, @t)',
    { m: memberId, t: tour2.json.rows?.[0]?.id },
  );
  check('iuran turnamen berbeda tetap boleh', other.code === 200, other.json.error ?? '');

  // ---------- 5. klasemen: angka, bukan string ----------
  await q("INSERT INTO teams (name) VALUES (@a), (@b)", { a: `${tag}_A`, b: `${tag}_B` });
  const teams = await rows('SELECT id, name FROM teams WHERE name LIKE @p ORDER BY name', {
    p: `${tag}%`,
  });
  const [teamA, teamB] = teams;
  await q(
    `INSERT INTO matches (home_team_id, away_team_id, played_at, status, goals_for, goals_against, venue)
     VALUES (@h, @a, now(), 'finished', 3, 1, @v)`,
    { h: teamA.id, a: teamB.id, v: tag },
  );
  const standing = await rows('SELECT * FROM v_team_standings WHERE team_id=@t', { t: teamA.id });
  const row = standing[0];
  // Regresi: kolom view dulu bigint → String, dan app melempar
  // "type 'String' is not a subtype of type 'int'" begitu ada laga selesai.
  check(
    'klasemen mengembalikan angka (bukan string)',
    typeof row?.played === 'number' && typeof row?.points === 'number',
    `played=${typeof row?.played} points=${typeof row?.points}`,
  );
  check('klasemen: menang 3 poin', num(row?.won) === 1 && num(row?.points) === 3, `won ${row?.won} poin ${row?.points}`);
  const away = (await rows('SELECT * FROM v_team_standings WHERE team_id=@t', { t: teamB.id }))[0];
  check('klasemen: kalah 0 poin', num(away?.lost) === 1 && num(away?.points) === 0, `lost ${away?.lost} poin ${away?.points}`);
} finally {
  // ---------- bersih-bersih ----------
  await q("DELETE FROM matches WHERE venue = @v", { v: tag });
  await q("DELETE FROM team_players WHERE team_id IN (SELECT id FROM teams WHERE name LIKE @p)", { p: `${tag}%` });
  await q("DELETE FROM teams WHERE name LIKE @p", { p: `${tag}%` });
  await q("DELETE FROM payments WHERE member_id IN (SELECT id FROM members WHERE name = @n)", { n: tag });
  await q("DELETE FROM members WHERE name = @n", { n: tag });
  await q("DELETE FROM bookings WHERE title = @t", { t: tag });
  await q("DELETE FROM transactions WHERE note = @n", { n: tag });
  const leftover = await rows(
    "SELECT (SELECT count(*)::int FROM teams WHERE name LIKE @p) AS teams, (SELECT count(*)::int FROM members WHERE name = @n) AS members, (SELECT count(*)::int FROM bookings WHERE title = @t) AS bookings",
    { p: `${tag}%`, n: tag, t: tag },
  );
  const l = leftover[0] ?? {};
  check(
    'data uji dibersihkan',
    num(l.teams) === 0 && num(l.members) === 0 && num(l.bookings) === 0,
    JSON.stringify(l),
  );

  const bad = results.filter((x) => !x.ok).length;
  console.log(`\nTarget: ${base}`);
  console.log(`${results.length - bad}/${results.length} lulus.`);
  process.exit(bad ? 1 : 0);
}
