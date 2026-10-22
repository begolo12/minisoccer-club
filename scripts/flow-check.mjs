// Uji alur admin dari ujung ke ujung pada server sungguhan: buat anggota,
// tim, laga, sesi, skor, turnamen, kas, lalu bersihkan lagi.
//
// scripts/e2e-check.mjs membuktikan setiap query lolos filter + izin. Skrip
// ini melangkah lebih jauh: memastikan rangkaian yang dipakai admin di UI
// benar-benar saling menyambung (id yang dikembalikan INSERT dipakai query
// berikutnya, status ikut berubah, klasemen menghitung hasilnya).
//
//   BASE=https://minisoccer-club.vercel.app node scripts/flow-check.mjs
//
// Butuh ADMIN_USER/ADMIN_PASS. Semua baris yang dibuat berawalan `_flow_`
// dan dihapus di akhir, termasuk saat gagal.
const base = (process.env.BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPass = process.env.ADMIN_PASS || 'admin123';

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

const q = (token, sql, params = {}) => post('/api/sql', { sql, params }, token);

// ---------- login ----------
let r = await post('/api/auth', { action: 'login', username: adminUser, password: adminPass });
if (r.code !== 200) {
  console.error(`Tidak bisa login sebagai ${adminUser}. Set ADMIN_USER/ADMIN_PASS.`);
  process.exit(1);
}
const token = r.json.token;
check('login admin', true);

const stamp = Date.now().toString(36);
const tag = `_flow_${stamp}`;
const made = { members: [], teams: [], tournaments: [], bookings: [], announcements: [] };

try {
  // ---------- 1. anggota ----------
  const m1 = await q(
    token,
    'INSERT INTO members (name, phone, position, jersey) VALUES (@n, @p, @pos, @j) RETURNING id',
    { n: `${tag}_A`, p: '0811', pos: 'Kiper', j: 1 },
  );
  const m2 = await q(
    token,
    'INSERT INTO members (name, phone, position, jersey) VALUES (@n, @p, @pos, @j) RETURNING id',
    { n: `${tag}_B`, p: '0812', pos: 'Penyerang', j: 9 },
  );
  check('tambah anggota', m1.code === 200 && m2.code === 200);
  const idA = m1.json.rows?.[0]?.id;
  const idB = m2.json.rows?.[0]?.id;
  made.members.push(idA, idB);

  // ---------- 2. tim ----------
  const t1 = await q(token, 'INSERT INTO teams (name) VALUES (@n) RETURNING id', { n: `${tag}_Tim1` });
  const t2 = await q(token, 'INSERT INTO teams (name) VALUES (@n) RETURNING id', { n: `${tag}_Tim2` });
  check('buat tim', t1.code === 200 && t2.code === 200, `${t1.json.error ?? ''}${t2.json.error ?? ''}`);
  const teamA = t1.json.rows?.[0]?.id;
  const teamB = t2.json.rows?.[0]?.id;
  made.teams.push(teamA, teamB);

  const addP = await q(
    token,
    'INSERT INTO team_players (team_id, member_id) VALUES (@t, @m) ON CONFLICT DO NOTHING',
    { t: teamA, m: idA },
  );
  check('masukkan pemain ke tim', addP.code === 200, addP.json.error ?? '');

  // ---------- 3. laga + sesi + skor ----------
  const match = await q(
    token,
    `INSERT INTO matches (home_team_id, away_team_id, played_at, venue)
     VALUES (@h, @a, now(), @v) RETURNING id`,
    { h: teamA, a: teamB, v: `${tag}_lapangan` },
  );
  check('buat jadwal laga', match.code === 200, match.json.error ?? '');
  const matchId = match.json.rows?.[0]?.id;

  const sess = await q(
    token,
    `INSERT INTO match_sessions (match_id, session_no, score_home, score_away, winner, ended_at)
     VALUES (@m, 1, 3, 1, 'home', now())`,
    { m: matchId },
  );
  check('catat sesi (3–1)', sess.code === 200, sess.json.error ?? '');

  const sync = await q(
    token,
    `UPDATE matches SET
       goals_for = COALESCE((SELECT sum(score_home) FROM match_sessions WHERE match_id=@m), 0),
       goals_against = COALESCE((SELECT sum(score_away) FROM match_sessions WHERE match_id=@m), 0),
       status = 'finished'
     WHERE id=@m`,
    { m: matchId },
  );
  check('selesaikan laga', sync.code === 200, sync.json.error ?? '');

  // ---------- 4. klasemen menghitung hasil ----------
  const standings = await q(token, 'SELECT * FROM v_team_standings WHERE team_id IN (@a, @b)', {
    a: teamA,
    b: teamB,
  });
  // Kolom view ini `bigint` (hasil COUNT), dan driver Neon mengirimnya sebagai
  // string supaya angka besar tidak kehilangan presisi. Bandingkan sebagai
  // angka, jangan dengan `===` mentah.
  const num = (v) => Number(v ?? 0);
  const rowA = standings.json.rows?.find((x) => Number(x.team_id) === teamA);
  const rowB = standings.json.rows?.find((x) => Number(x.team_id) === teamB);
  check(
    'klasemen: tim A menang 3 poin',
    standings.code === 200 && num(rowA?.won) === 1 && num(rowA?.points) === 3,
    `won ${rowA?.won} poin ${rowA?.points}`,
  );
  check(
    'klasemen: tim B kalah 0 poin',
    num(rowB?.lost) === 1 && num(rowB?.points) === 0,
    `lost ${rowB?.lost} poin ${rowB?.points}`,
  );

  // ---------- 5. turnamen + grup + jadwal ----------
  const tour = await q(
    token,
    `INSERT INTO tournaments (name, venue, starts_at, match_minutes, break_minutes, groups)
     VALUES (@n, @v, now(), 20, 0, 1) RETURNING id`,
    { n: `${tag}_Turnamen`, v: `${tag}_lapangan` },
  );
  check('buat turnamen', tour.code === 200, tour.json.error ?? '');
  const tourId = tour.json.rows?.[0]?.id;
  made.tournaments.push(tourId);

  const groups = await q(
    token,
    `INSERT INTO tournament_teams (tournament_id, team_id, group_no)
     VALUES (@t, @a, 1), (@t, @b, 1) ON CONFLICT DO NOTHING`,
    { t: tourId, a: teamA, b: teamB },
  );
  check('bagi tim ke grup', groups.code === 200, groups.json.error ?? '');

  const sched = await q(
    token,
    `INSERT INTO tournament_matches
       (tournament_id, group_no, round, slot, home_team_id, away_team_id, kickoff)
     VALUES (@t, 1, 1, 1, @h, @a, now()) ON CONFLICT DO NOTHING`,
    { t: tourId, h: teamA, a: teamB },
  );
  check('buat jadwal turnamen', sched.code === 200, sched.json.error ?? '');

  const tm = await q(token, 'SELECT id FROM tournament_matches WHERE tournament_id=@t', { t: tourId });
  const tmId = tm.json.rows?.[0]?.id;
  const score = await q(
    token,
    "UPDATE tournament_matches SET score_home=2, score_away=0, status='done' WHERE id=@id",
    { id: tmId },
  );
  check('isi skor turnamen', score.code === 200, score.json.error ?? '');

  // ---------- 6. kas + booking + iuran ----------
  const book = await q(
    token,
    'INSERT INTO bookings (title, starts_at, duration_min, cost) VALUES (@t, now(), 90, 350000) RETURNING id',
    { t: `${tag}_booking` },
  );
  const bookId = book.json.rows?.[0]?.id;
  made.bookings.push(bookId);
  check('buat booking', book.code === 200, book.json.error ?? '');

  const cash = await q(
    token,
    `INSERT INTO transactions (kind, category, amount, occurred_at, note, booking_id)
     VALUES ('expense', 'sewa', 350000, CURRENT_DATE, @n, @b)`,
    { n: `${tag}_sewa`, b: bookId },
  );
  check('catat sewa ke kas', cash.code === 200, cash.json.error ?? '');

  // Iuran terikat turnamen (bukan bulan). Turnamen sudah dibuat di langkah 6.
  const pay = await q(
    token,
    'INSERT INTO payments (member_id, amount, tournament_id, note) VALUES (@m, 50000, @t, @n) RETURNING id',
    { m: idA, t: tourId, n: `${tag}_iuran` },
  );
  check('catat iuran turnamen', pay.code === 200, pay.json.error ?? '');

  // ---------- 7. pengumuman ----------
  const ann = await q(
    token,
    'INSERT INTO announcements (title, body) VALUES (@t, @b) RETURNING id',
    { t: `${tag}_pengumuman`, b: 'isi' },
  );
  made.announcements.push(ann.json.rows?.[0]?.id);
  check('buat pengumuman', ann.code === 200, ann.json.error ?? '');

  // ---------- 8. baca balik: data terlihat oleh tamu ----------
  const guestRead = await q(null, 'SELECT count(*)::int AS n FROM members WHERE name LIKE @p', {
    p: `${tag}%`,
  });
  check('tamu melihat data yang baru dibuat', guestRead.code === 200 && guestRead.json.rows[0].n === 2);
} finally {
  // ---------- bersihkan ----------
  const cleanup = [
    ['matches', 'DELETE FROM matches WHERE venue = @v', { v: `${tag}_lapangan` }],
    ['tournament_matches', 'DELETE FROM tournament_matches WHERE tournament_id = ANY(@ids)', { ids: made.tournaments }],
    ['tournament_teams', 'DELETE FROM tournament_teams WHERE tournament_id = ANY(@ids)', { ids: made.tournaments }],
    ['tournaments', 'DELETE FROM tournaments WHERE name LIKE @p', { p: `${tag}%` }],
    ['team_players', 'DELETE FROM team_players WHERE team_id = ANY(@ids)', { ids: made.teams }],
    ['teams', 'DELETE FROM teams WHERE name LIKE @p', { p: `${tag}%` }],
    ['payments', 'DELETE FROM payments WHERE member_id = ANY(@ids)', { ids: made.members }],
    ['members', 'DELETE FROM members WHERE name LIKE @p', { p: `${tag}%` }],
    ['bookings', 'DELETE FROM bookings WHERE title LIKE @p', { p: `${tag}%` }],
    ['announcements', 'DELETE FROM announcements WHERE title LIKE @p', { p: `${tag}%` }],
  ];
  let clean = 0;
  for (const [label, sql, params] of cleanup) {
    const res = await q(token, sql, params);
    if (res.code === 200) clean++;
    else console.error(`  bersih-bersih ${label}: ${res.json.error ?? res.code}`);
  }
  check(`data uji dibersihkan (${clean}/${cleanup.length})`, clean === cleanup.length);

  const bad = results.filter((x) => !x.ok).length;
  console.log(`\nTarget: ${base}`);
  console.log(`${results.length - bad}/${results.length} lulus.`);
  process.exit(bad ? 1 : 0);
}
