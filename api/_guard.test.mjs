import { test } from 'node:test';
import assert from 'node:assert/strict';

import { MissingParam, normalize, rejectSql, toPositional } from './_guard.js';

const admin = { r: 'admin' };
const treasurer = { r: 'treasurer' };
const member = { r: 'member' };

const allowed = (sql, session = admin) => assert.equal(rejectSql(sql, session), null, sql);
const blocked = (sql, session = admin) => assert.notEqual(rejectSql(sql, session), null, sql);

test('baca data boleh untuk semua role', () => {
  allowed('SELECT * FROM members', member);
  allowed('SELECT count(*)::int AS n FROM payments', member);
  allowed('WITH x AS (SELECT 1 AS n) SELECT * FROM x', member);
});

test('member tidak boleh menulis', () => {
  blocked("INSERT INTO members (name) VALUES ('A')", member);
  blocked('UPDATE members SET name = \'B\' WHERE id = 1', member);
  blocked('DELETE FROM payments WHERE id = 1', member);
});

test('komentar tidak bisa dipakai menyembunyikan tulis', () => {
  blocked('DELETE /* x */ FROM payments WHERE id = 1', member);
  blocked('DELETE -- x\n FROM payments WHERE id = 1', member);
  blocked('UPDATE /* x */ payments SET amount = 0', member);
  blocked('DELETE /* x */ FROM users WHERE id = 1');
});

test('users hanya lewat /api/auth, termasuk nama berskema dan berkutip', () => {
  blocked("UPDATE users SET role = 'admin' WHERE id = 1");
  blocked("UPDATE public.users SET role = 'admin' WHERE id = 1");
  blocked('UPDATE "public"."users" SET role = \'admin\' WHERE id = 1');
  blocked("DELETE FROM ONLY public.users WHERE id = 1");
  blocked("INSERT INTO public.users (username, role) VALUES ('x', 'admin')");
  blocked("WITH u AS (UPDATE public.users SET role = 'admin' RETURNING id) SELECT * FROM u");
  blocked("SELECT * FROM users WHERE id IN (DELETE FROM users RETURNING id)");
});

test('tulis ke tabel aplikasi boleh untuk admin/bendahara', () => {
  allowed("INSERT INTO members (name) VALUES ('A')", treasurer);
  allowed('UPDATE members SET name = \'B\' WHERE id = 1', treasurer);
  allowed('DELETE FROM payments WHERE id = 1', admin);
  allowed(
    `INSERT INTO match_sessions (match_id, session_no, score_home, score_away, winner)
     VALUES (1, 1, 2, 1, 'home')
     ON CONFLICT (match_id, session_no) DO UPDATE SET
       score_home = 2, score_away = 1, winner = 'home'`,
  );
  allowed(
    `INSERT INTO team_players (team_id, member_id) VALUES (1, 2)
     ON CONFLICT DO NOTHING`,
  );
});

test('DDL, multi statement, dan SELECT INTO ditolak', () => {
  blocked('DROP TABLE members');
  blocked('CREATE TABLE x (id int)');
  blocked('ALTER TABLE members ADD COLUMN x int');
  blocked('SELECT 1; SELECT 2');
  blocked('SELECT * INTO salinan FROM members');
  blocked('TRUNCATE members');
  blocked('DO $$ BEGIN DELETE FROM users; END $$');
});

test('kolom password tidak pernah lewat jalur SQL', () => {
  blocked('SELECT password_hash FROM users');
  blocked('SELECT id FROM users WHERE pin_hash IS NOT NULL');
});

test('daftar pengguna hanya untuk admin', () => {
  allowed('SELECT id, username, role, active FROM users ORDER BY role, username', admin);
  blocked('SELECT id, username, role, active FROM users', member);
  blocked('SELECT id, username FROM public.users', treasurer);
});

test('tulis tanpa target yang jelas ditolak', () => {
  blocked('SELECT * FROM members FOR UPDATE');
});

test('normalize membuang komentar tapi menjaga string', () => {
  assert.equal(normalize("SELECT 'a -- b' -- komentar").trim(), "SELECT ''");
  assert.equal(normalize('SELECT /* x */ 1').trim(), 'SELECT   1');
  assert.equal(normalize('SELECT "update" FROM t').trim(), 'SELECT "update" FROM t');
});

test('parameter @nama jadi positional dan melewati string', () => {
  const r = toPositional(
    "UPDATE members SET name=@name, note='a@b.com' WHERE id=@id AND note='@name'",
    { name: 'A', id: 3 },
  );
  assert.equal(
    r.text,
    "UPDATE members SET name=$1, note='a@b.com' WHERE id=$2 AND note='@name'",
  );
  assert.deepEqual(r.values, ['A', 3]);
});

test('parameter yang hilang ditolak, bukan jadi NULL diam-diam', () => {
  assert.throws(() => toPositional('SELECT * FROM members WHERE id=@id', {}), MissingParam);
});

test('parameter yang sama dipakai berulang memakai satu posisi', () => {
  const r = toPositional('SELECT * FROM t WHERE a=@x OR b=@x', { x: 1 });
  assert.equal(r.text, 'SELECT * FROM t WHERE a=$1 OR b=$1');
  assert.deepEqual(r.values, [1]);
});

// Uang klub tidak boleh terbaca tanpa masuk.
//
// Sebelum aturan ini, siapa pun yang tahu alamat aplikasinya bisa membaca
// siapa belum bayar iuran, saldo kas, dan biaya sewa lapangan lewat satu
// `SELECT *` — tanpa akun, tanpa jejak.
test('tamu tidak bisa membaca kas, iuran, dan sewa lapangan', () => {
  const guest = { r: 'public' };
  const cases = [
    'SELECT * FROM payments',
    'SELECT * FROM transactions',
    'SELECT * FROM bookings',
    'SELECT * FROM booking_attendance',
    'SELECT * FROM settings',
    // Lewat join/subquery juga.
    'SELECT m.name FROM members m JOIN payments p ON p.member_id = m.id',
    'SELECT sum(amount) FROM transactions WHERE kind = \'in\'',
    'WITH x AS (SELECT cost FROM bookings) SELECT * FROM x',
  ];
  for (const sql of cases) {
    const blocked = rejectSql(sql, guest);
    assert.notEqual(blocked, null, `harus ditolak: ${sql}`);
    assert.match(blocked, /Masuk dulu/);
  }
});

test('tamu tetap boleh melihat data pertandingan', () => {
  const guest = { r: 'public' };
  for (const sql of [
    'SELECT id, name, position, jersey FROM members',
    'SELECT * FROM teams',
    'SELECT * FROM tournaments',
    'SELECT * FROM matches',
    'SELECT * FROM match_events',
    'SELECT * FROM announcements',
    'SELECT * FROM v_team_standings',
  ]) {
    assert.equal(rejectSql(sql, guest), null, `harus boleh: ${sql}`);
  }
});

test('anggota dan bendahara tetap bisa membaca kas & iuran', () => {
  for (const role of ['member', 'treasurer', 'admin']) {
    const s = { r: role };
    for (const sql of [
      'SELECT * FROM payments',
      'SELECT * FROM transactions',
      'SELECT * FROM bookings',
    ]) {
      assert.equal(rejectSql(sql, s), null, `${role} harus boleh: ${sql}`);
    }
  }
});
