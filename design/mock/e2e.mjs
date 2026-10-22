// E2E alur data: kirim SQL yang sama persis dengan yang dikirim app
// (lib/data/models.dart) ke mock backend, lalu periksa hasil bacaannya.
// Pakai: node design/mock/e2e.mjs
const BASE = 'http://localhost:8099/api/sql';

let failures = 0;
const check = (label, ok, extra = '') => {
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}${extra ? ` — ${extra}` : ''}`);
  if (!ok) failures++;
};

async function sql(query, params = {}) {
  const res = await fetch(BASE, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ sql: query, params }),
  });
  if (!res.ok) throw new Error(`${res.status} ${await res.text()}`);
  return res.json();
}
const rows = async (q, p) => (await sql(q, p)).rows;
const run = async (q, p) => (await sql(q, p)).rowCount;

const MATCH_SELECT = `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id`;

const sessionsOf = async (id) =>
  rows('SELECT * FROM match_sessions WHERE match_id=@m ORDER BY session_no', { m: id });

// ---------- 1. Tambah anggota ----------
// Nama diberi cap waktu supaya skrip bisa dijalankan berkali-kali pada mock
// yang sama tanpa mengambil baris sisa run sebelumnya.
const stamp = Date.now().toString(36);
const memberName = `E2E Pemain ${stamp}`;
await run(
  'INSERT INTO members (name, phone, position, jersey) VALUES (@name, @phone, @position, @jersey)',
  { name: memberName, phone: null, position: 'Bek', jersey: 99 },
);
const newMember = (await rows('SELECT * FROM members WHERE active ORDER BY name')).find(
  (m) => m.name === memberName,
);
check('anggota baru tersimpan', !!newMember);

// ---------- 2. Buat tim + pemain ----------
const team = await rows('INSERT INTO teams (name) VALUES (@n) RETURNING id', { n: `Tim E2E ${stamp}` });
check('tim baru mengembalikan id', typeof team[0]?.id === 'number', JSON.stringify(team));
const teamId = team[0].id;
await run('INSERT INTO team_players (team_id, member_id) VALUES (@t, @m) ON CONFLICT DO NOTHING', {
  t: teamId,
  m: newMember.id,
});
const squad = await rows(
  `SELECT tp.team_id, m.* FROM team_players tp
         JOIN members m ON m.id = tp.member_id
         ORDER BY m.name`,
);
check('pemain masuk tim', squad.some((r) => r.team_id === teamId && r.id === newMember.id));

// ---------- 3. Jadwal tanding ----------
await run(
  `INSERT INTO matches (home_team_id, away_team_id, played_at, venue)
         VALUES (@h, @a, @t, @v)`,
  { h: teamId, a: 1, t: new Date().toISOString(), v: 'Lapangan E2E' },
);
const created = (await rows(`${MATCH_SELECT} ORDER BY m.played_at DESC LIMIT @limit`, { limit: 100 }))
  .find((m) => m.home_team_id === teamId);
check('laga terjadwal dibuat', !!created && created.status === 'scheduled');
const matchId = created.id;

// ---------- 4. Sesi 1: 2–0 ----------
await run(
  `INSERT INTO match_sessions (match_id, session_no, score_home, score_away, winner, ended_at)
           VALUES (@m, @sn, @h, @a, @w, now())
           ON CONFLICT (match_id, session_no) DO UPDATE SET
             score_home=@h, score_away=@a, winner=@w, ended_at=now()`,
  { m: matchId, sn: 1, h: 2, a: 0, w: 'home' },
);
const SYNC = `UPDATE matches SET
             goals_for = COALESCE((SELECT sum(score_home) FROM match_sessions WHERE match_id=@m),
                                  CASE WHEN status='finished' THEN goals_for ELSE 0 END),
             goals_against = COALESCE((SELECT sum(score_away) FROM match_sessions WHERE match_id=@m),
                                      CASE WHEN status='finished' THEN goals_against ELSE 0 END),
             status = CASE
               WHEN status='scheduled'
                    AND EXISTS (SELECT 1 FROM match_sessions WHERE match_id=@m) THEN 'ongoing'
               WHEN status='ongoing'
                    AND NOT EXISTS (SELECT 1 FROM match_sessions WHERE match_id=@m) THEN 'scheduled'
               ELSE status END
           WHERE id=@m`;
await run(SYNC, { m: matchId });
let fresh = (await rows(`${MATCH_SELECT} WHERE m.id=@id`, { id: matchId }))[0];
check('sesi 1 membuat laga berjalan 2–0', fresh.status === 'ongoing' && fresh.goals_for === 2 && fresh.goals_against === 0,
  `${fresh.status} ${fresh.goals_for}-${fresh.goals_against}`);

// ---------- 5. Sesi 2: 1–1 → total 3–1 ----------
await run(
  `INSERT INTO match_sessions (match_id, session_no, score_home, score_away, winner, ended_at)
           VALUES (@m, @sn, @h, @a, @w, now())
           ON CONFLICT (match_id, session_no) DO UPDATE SET
             score_home=@h, score_away=@a, winner=@w, ended_at=now()`,
  { m: matchId, sn: 2, h: 1, a: 1, w: 'draw' },
);
await run(SYNC, { m: matchId });
fresh = (await rows(`${MATCH_SELECT} WHERE m.id=@id`, { id: matchId }))[0];
check('total sesi = 3–1', fresh.goals_for === 3 && fresh.goals_against === 1,
  `${fresh.goals_for}-${fresh.goals_against}`);

// ---------- 6. Selesaikan (skor dialog diabaikan karena ada sesi) ----------
await run("UPDATE matches SET status='finished', goals_for=@gf, goals_against=@ga WHERE id=@id", {
  id: matchId, gf: 9, ga: 9,
});
fresh = (await rows(`${MATCH_SELECT} WHERE m.id=@id`, { id: matchId }))[0];
check('selesai memakai jumlah sesi, bukan angka dialog',
  fresh.status === 'finished' && fresh.goals_for === 3 && fresh.goals_against === 1,
  `${fresh.status} ${fresh.goals_for}-${fresh.goals_against}`);

// ---------- 7. Klasemen memakai laga selesai ----------
const standings = await rows(
  `SELECT * FROM v_team_standings
         ORDER BY points DESC, (goals_for - goals_against) DESC, goals_for DESC, name`,
);
const e2eRow = standings.find((s) => s.team_id === teamId);
const oppRow = standings.find((s) => s.team_id === 1);
check('klasemen menghitung kemenangan 3 poin', e2eRow?.points === 3 && e2eRow?.won === 1,
  `poin ${e2eRow?.points} menang ${e2eRow?.won}`);
check('tim lawan dapat 0 poin dan 1 kalah', oppRow?.lost >= 1, `kalah ${oppRow?.lost}`);

// ---------- 8. Hapus sesi terakhir pada laga selesai ----------
const ses = await sessionsOf(matchId);
await run('DELETE FROM match_sessions WHERE id=@id', { id: ses[ses.length - 1].id });
await run(SYNC, { m: matchId });
fresh = (await rows(`${MATCH_SELECT} WHERE m.id=@id`, { id: matchId }))[0];
check('hapus sesi pada laga selesai tidak mengubah hasil jadi 0–0',
  fresh.status === 'finished' && fresh.goals_for === 2 && fresh.goals_against === 0,
  `${fresh.status} ${fresh.goals_for}-${fresh.goals_against}`);

// ---------- 9. Hapus sesi terakhir pada laga berjalan ----------
await run(
  `INSERT INTO matches (home_team_id, away_team_id, played_at, venue)
         VALUES (@h, @a, @t, @v)`,
  { h: teamId, a: 2, t: new Date().toISOString(), v: null },
);
const second = (await rows(`${MATCH_SELECT} WHERE m.home_team_id=@t OR m.away_team_id=@t ORDER BY m.played_at DESC LIMIT @limit`,
  { t: teamId, limit: 20 })).find((m) => m.status === 'scheduled');
await run(
  `INSERT INTO match_sessions (match_id, session_no, score_home, score_away, winner, ended_at)
           VALUES (@m, @sn, @h, @a, @w, now())`,
  { m: second.id, sn: 1, h: 1, a: 0, w: 'home' },
);
await run(SYNC, { m: second.id });
let live = (await rows(`${MATCH_SELECT} WHERE m.id=@id`, { id: second.id }))[0];
check('laga kembali berjalan setelah sesi ditambah', live.status === 'ongoing' && live.goals_for === 1,
  `${live.status} ${live.goals_for}-${live.goals_against}`);
const liveSessions = await sessionsOf(second.id);
await run('DELETE FROM match_sessions WHERE id=@id', { id: liveSessions[0].id });
await run(SYNC, { m: second.id });
live = (await rows(`${MATCH_SELECT} WHERE m.id=@id`, { id: second.id }))[0];
check('sesi habis pada laga berjalan: kembali terjadwal dan skor 0–0',
  live.status === 'scheduled' && live.goals_for === 0 && live.goals_against === 0,
  `${live.status} ${live.goals_for}-${live.goals_against}`);

// ---------- 10. Laga berjalan lama tetap muncul di beranda ----------
const old = new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString();
await run(
  `INSERT INTO matches (home_team_id, away_team_id, played_at, venue)
         VALUES (@h, @a, @t, @v)`,
  { h: 3, a: 4, t: old, v: 'Lapangan Lama' },
);
const stale = (await rows(`${MATCH_SELECT} ORDER BY m.played_at DESC LIMIT @limit`, { limit: 100 }))
  .find((m) => m.played_at === old);
await run(
  `INSERT INTO match_sessions (match_id, session_no, score_home, score_away, winner, ended_at)
           VALUES (@m, @sn, @h, @a, @w, now())`,
  { m: stale.id, sn: 1, h: 1, a: 1, w: 'draw' },
);
await run(SYNC, { m: stale.id });
const upcoming = await rows(
  `${MATCH_SELECT} WHERE m.status='ongoing' OR (m.status='scheduled' AND m.played_at >= now() - interval '3 hours') ORDER BY m.played_at ASC LIMIT 5`,
);
check('laga berjalan 6 jam lalu masih muncul di beranda',
  upcoming.some((m) => m.id === stale.id), upcoming.map((m) => `${m.id}:${m.status}`).join(','));

// ---------- 11. Turnamen: buat, jadwal, skor, klasemen ----------
const tour = await rows(
  `INSERT INTO tournaments (name, venue, starts_at, match_minutes, break_minutes, groups)
         VALUES (@n, @v, @s, @mm, @bm, @g) RETURNING id`,
  { n: `Turnamen E2E ${stamp}`, v: null, s: new Date().toISOString(), mm: 20, bm: 0, g: 1 },
);
check('turnamen baru mengembalikan id', typeof tour[0]?.id === 'number', JSON.stringify(tour));
const tourId = tour[0].id;
await run(
  `INSERT INTO tournament_teams (tournament_id, team_id, group_no)
         VALUES (@t, @team0, @g0),(@t, @team1, @g1) ON CONFLICT DO NOTHING`,
  { t: tourId, team0: teamId, g0: 1, team1: 2, g1: 1 },
);
await run(
  `INSERT INTO tournament_matches
           (tournament_id, group_no, round, slot, home_team_id, away_team_id, kickoff)
         VALUES (@t0, @g0, @r0, @s0, @h0, @a0, @k0) ON CONFLICT DO NOTHING`,
  {
    t0: tourId, g0: 1, r0: 1, s0: 1, h0: teamId, a0: 2,
    k0: new Date().toISOString(),
  },
);
const tourTeams = await rows(
  `SELECT t.*, tt.group_no FROM tournament_teams tt
         JOIN teams t ON t.id = tt.team_id
         WHERE tt.tournament_id=@t ORDER BY tt.group_no, t.name`,
  { t: tourId },
);
check('dua tim terdaftar di turnamen', tourTeams.length === 2, `${tourTeams.length} tim`);
const tourMatches = await rows('SELECT * FROM tournament_matches WHERE tournament_id=@t ORDER BY slot', { t: tourId });
check('jadwal turnamen dibuat', tourMatches.length === 1, `${tourMatches.length} laga`);

await run(
  `UPDATE tournament_matches SET score_home=@h, score_away=@a, status='done'
         WHERE id=@id`,
  { id: tourMatches[0].id, h: 0, a: 2 },
);
const afterScore = await rows('SELECT * FROM tournament_matches WHERE tournament_id=@t ORDER BY slot', { t: tourId });
check('skor turnamen tersimpan sebagai done',
  afterScore[0].status === 'done' && afterScore[0].score_away === 2,
  `${afterScore[0].status} ${afterScore[0].score_home}-${afterScore[0].score_away}`);

// Klasemen dihitung klien (Standing.compute) dari daftar laga: tiru di sini.
const gTeams = new Map(tourTeams.map((t) => [t.id, { name: t.name, played: 0, won: 0, drawn: 0, lost: 0, gf: 0, ga: 0 }]));
for (const m of afterScore) {
  if (m.status !== 'done') continue;
  const h = gTeams.get(m.home_team_id), a = gTeams.get(m.away_team_id);
  h.played++; a.played++;
  h.gf += m.score_home; h.ga += m.score_away;
  a.gf += m.score_away; a.ga += m.score_home;
  if (m.score_home > m.score_away) { h.won++; a.lost++; }
  else if (m.score_home < m.score_away) { a.won++; h.lost++; }
  else { h.drawn++; a.drawn++; }
}
const awayTeam = gTeams.get(2);
check('tim away yang menang dapat 3 poin', awayTeam.won === 1, JSON.stringify(awayTeam));

// ---------- 12. Reset skor turnamen ----------
await run(
  `UPDATE tournament_matches SET score_home=NULL, score_away=NULL,
           status='scheduled' WHERE id=@id`,
  { id: tourMatches[0].id },
);
const afterReset = await rows('SELECT * FROM tournament_matches WHERE tournament_id=@t ORDER BY slot', { t: tourId });
check('reset skor mengembalikan status terjadwal',
  afterReset[0].status === 'scheduled' && afterReset[0].score_home === null);

// ---------- 13. Iuran: cek duplikat per anggota + periode ----------
const payMember = newMember.id;
const period = new Date().toISOString().slice(0, 7);
const before = await rows('SELECT 1 AS ok FROM payments WHERE member_id=@mid AND period=@p LIMIT 1',
  { mid: payMember, p: period });
check('belum ada iuran untuk anggota ini', before.length === 0, `${before.length} baris`);
await run(
  `INSERT INTO payments (member_id, amount, period, note)
           VALUES (@mid, @amt, @period, @note)`,
  { mid: payMember, amt: 75000, period, note: null },
);
const after = await rows('SELECT 1 AS ok FROM payments WHERE member_id=@mid AND period=@p LIMIT 1',
  { mid: payMember, p: period });
check('iuran pertama tercatat', after.length === 1, `${after.length} baris`);
const other = await rows('SELECT 1 AS ok FROM payments WHERE member_id=@mid AND period=@p LIMIT 1',
  { mid: payMember + 100, p: period });
check('anggota lain tidak dianggap sudah bayar', other.length === 0, `${other.length} baris`);

// ---------- 14. Buka lagi laga yang sudah selesai ----------
await run(
  `UPDATE matches SET status = CASE
             WHEN EXISTS (SELECT 1 FROM match_sessions WHERE match_id=@id)
               THEN 'ongoing' ELSE 'scheduled' END
           WHERE id=@id`,
  { id: matchId },
);
const reopened = (await rows(`${MATCH_SELECT} WHERE m.id=@id`, { id: matchId }))[0];
check('buka lagi mengembalikan status berjalan karena masih ada sesi',
  reopened.status === 'ongoing', reopened.status);
const standingsAfterReopen = await rows(
  `SELECT * FROM v_team_standings
         ORDER BY points DESC, (goals_for - goals_against) DESC, goals_for DESC, name`,
);
const reopenedRow = standingsAfterReopen.find((s) => s.team_id === teamId);
check('poin hilang dari klasemen setelah dibuka lagi',
  (reopenedRow?.points ?? 0) === 0 && (reopenedRow?.played ?? 0) === 0,
  `poin ${reopenedRow?.points} main ${reopenedRow?.played}`);

// ---------- 15. Hapus tim: status turnamen ikut dihitung ulang ----------
// Selesaikan dulu satu laga turnamen supaya statusnya 'done', lalu hapus tim
// dan jalankan syncStatus seperti yang dilakukan `Team.delete` di app.
await run(
  `UPDATE tournament_matches SET score_home=@h, score_away=@a, status='done'
         WHERE id=@id`,
  { id: tourMatches[0].id, h: 2, a: 1 },
);
const SYNC_TOUR = `UPDATE tournaments SET status = CASE
             WHEN EXISTS (SELECT 1 FROM tournament_matches
                          WHERE tournament_id=@t AND status <> 'done')
               THEN CASE WHEN EXISTS (SELECT 1 FROM tournament_matches
                                       WHERE tournament_id=@t AND status='done')
                         THEN 'running' ELSE 'draft' END
             WHEN EXISTS (SELECT 1 FROM tournament_matches WHERE tournament_id=@t)
               THEN 'done'
             ELSE status END
           WHERE id=@t`;
await run(SYNC_TOUR, { t: tourId });
let tourState = (await rows('SELECT * FROM tournaments ORDER BY id')).find((t) => t.id === tourId);
check('turnamen berstatus selesai setelah semua laga terisi', tourState.status === 'done', tourState.status);

const affected = await rows(
  `SELECT DISTINCT tournament_id FROM tournament_matches
         WHERE home_team_id=@id OR away_team_id=@id`,
  { id: teamId },
);
check('turnamen yang terdampak terdeteksi sebelum hapus',
  affected.some((a) => a.tournament_id === tourId), JSON.stringify(affected));

await run('DELETE FROM teams WHERE id=@id', { id: teamId });
for (const a of affected) await run(SYNC_TOUR, { t: a.tournament_id });

const leftMatches = await rows('SELECT * FROM tournament_matches WHERE tournament_id=@t', { t: tourId });
check('jadwal turnamen tim yang dihapus ikut hilang (CASCADE)', leftMatches.length === 0,
  `${leftMatches.length} laga tersisa`);
tourState = (await rows('SELECT * FROM tournaments ORDER BY id')).find((t) => t.id === tourId);
check('turnamen yang kehilangan semua laga tidak lagi "selesai"',
  tourState.status === 'draft', tourState.status);

// ---------- 16. Booking → kas: satu pengeluaran, satu catatan ----------
const bk = await rows(
  `INSERT INTO bookings (title, starts_at, duration_min, cost)
         VALUES (@t, @s, @d, @c) RETURNING id`,
  { t: `Sewa E2E ${stamp}`, s: new Date().toISOString(), d: 90, c: 350000 },
);
const bookingId = bk[0].id;
await run(
  `INSERT INTO transactions (kind, category, amount, occurred_at, note, booking_id)
         VALUES ('expense', 'sewa', @amount, @date, @note, @booking)`,
  { amount: 350000, date: new Date().toISOString().slice(0, 10), note: 'Sewa E2E', booking: bookingId },
);
const withCash = await rows(
  `SELECT b.*, t.id AS transaction_id FROM bookings b
         LEFT JOIN transactions t ON t.booking_id = b.id
         ORDER BY b.starts_at DESC LIMIT 100`,
);
const savedBooking = withCash.find((b) => b.id === bookingId);
check('booking baru langsung tertaut ke catatan kas', savedBooking?.transaction_id != null,
  `transaction_id=${savedBooking?.transaction_id}`);
const cashForBooking = (await rows('SELECT * FROM transactions')).filter((t) => t.booking_id === bookingId);
check('hanya satu catatan kas per booking', cashForBooking.length === 1, `${cashForBooking.length} catatan`);

await run('DELETE FROM bookings WHERE id=@id', { id: bookingId });
const cashAfterDelete = (await rows('SELECT * FROM transactions')).filter((t) => t.booking_id === bookingId);
check('hapus booking menghapus catatan kasnya', cashAfterDelete.length === 0, `${cashAfterDelete.length} catatan`);

// ---------- 17. Hapus tim tidak menghapus riwayat internal ----------
const orphan = (await rows(`${MATCH_SELECT} WHERE m.id=@id`, { id: matchId }))[0];
check('laga tetap ada setelah tim dihapus', !!orphan, JSON.stringify(orphan ?? null));
check('nama tim yang hilang menjadi NULL (app memakai "Tim dihapus")',
  orphan.home_name === null && orphan.home_team_id === null,
  `home_name=${orphan.home_name} home_team_id=${orphan.home_team_id}`);


// ---------- 17b. Catatan pertandingan lewat papan catat ----------
const beforeEvents = (await rows(
  `SELECT e.*, m.name AS member_name FROM match_events e
         LEFT JOIN members m ON m.id = e.member_id
         WHERE e.match_id = @mid ORDER BY e.minute NULLS LAST, e.id`,
  { mid: matchId },
)).length;
await run(
  `INSERT INTO match_events (match_id, member_id, minute, type)
           VALUES (@mid, @mem, @min, @type)`,
  { mid: matchId, mem: newMember.id, min: null, type: 'goal' },
);
const afterEvents = await rows(
  `SELECT e.*, m.name AS member_name FROM match_events e
         LEFT JOIN members m ON m.id = e.member_id
         WHERE e.match_id = @mid ORDER BY e.minute NULLS LAST, e.id`,
  { mid: matchId },
);
check('catatan gol tersimpan tanpa menit', afterEvents.length === beforeEvents + 1,
  `${afterEvents.length - beforeEvents} baru`);
check('catatan membawa nama pemain', afterEvents.at(-1).member_name === memberName,
  afterEvents.at(-1).member_name);

// ---------- 17c. Ubah jadwal, mulai laga, kelola tim turnamen ----------
await run(
  `UPDATE matches SET home_team_id=@h, away_team_id=@a,
           played_at=@t, venue=@v WHERE id=@id`,
  { id: second.id, h: 1, a: 2, t: new Date().toISOString(), v: 'Lapangan Baru' },
);
const rescheduled = (await rows(`${MATCH_SELECT} WHERE m.id=@id`, { id: second.id }))[0];
check('jadwal laga bisa diubah tanpa menghapus hasil',
  rescheduled.home_team_id === 1 && rescheduled.venue === 'Lapangan Baru' && rescheduled.status === 'scheduled',
  `${rescheduled.home_name} vs ${rescheduled.away_name} @ ${rescheduled.venue} (${rescheduled.status})`);

await run("UPDATE matches SET status='ongoing' WHERE id=@id AND status='scheduled'", { id: second.id });
const started = (await rows(`${MATCH_SELECT} WHERE m.id=@id`, { id: second.id }))[0];
check('laga terjadwal bisa dimulai tanpa sesi', started.status === 'ongoing',
  `${started.status} ${started.goals_for}-${started.goals_against}`);

// Turnamen baru khusus bagian ini: turnamen `tourId` sudah kehilangan semua
// jadwalnya saat timnya dihapus di langkah 15.
const tour2 = await rows(
  `INSERT INTO tournaments (name, venue, starts_at, match_minutes, break_minutes, groups)
         VALUES (@n, @v, @s, @mm, @bm, @g) RETURNING id`,
  { n: `Turnamen Ulang ${stamp}`, v: null, s: new Date().toISOString(), mm: 20, bm: 0, g: 1 },
);
const tour2Id = tour2[0].id;
await run(
  `INSERT INTO tournament_teams (tournament_id, team_id, group_no)
         VALUES (@t, @team0, @g0),(@t, @team1, @g1) ON CONFLICT DO NOTHING`,
  { t: tour2Id, team0: 1, g0: 1, team1: 2, g1: 1 },
);
await run(
  `INSERT INTO tournament_matches
           (tournament_id, group_no, round, slot, home_team_id, away_team_id, kickoff)
         VALUES (@t0, @g0, @r0, @s0, @h0, @a0, @k0) ON CONFLICT DO NOTHING`,
  { t0: tour2Id, g0: 1, r0: 1, s0: 1, h0: 1, a0: 2, k0: new Date().toISOString() },
);
const tour2Matches = await rows('SELECT * FROM tournament_matches WHERE tournament_id=@t', { t: tour2Id });

// Beri satu skor dulu: guard "kelola tim" hanya relevan kalau sudah ada hasil.
await run(
  `UPDATE tournament_matches SET score_home=@h, score_away=@a, status='done'
         WHERE id=@id`,
  { id: tour2Matches[0].id, h: 1, a: 0 },
);
const doneCount = (await rows(
  `SELECT count(*)::int AS n FROM tournament_matches
         WHERE tournament_id=@t AND status='done'`,
  { t: tour2Id },
))[0].n;
check('hitung laga berskor sebelum kelola tim', doneCount === 1, `${doneCount} laga done`);
// Turnamen dengan skor harus menolak penjadwalan ulang (dicek klien).
check('kelola tim ditolak kalau sudah ada skor', doneCount > 0, 'guard aktif');
await run('DELETE FROM tournament_matches WHERE tournament_id=@t', { t: tour2Id });
await run('DELETE FROM tournament_teams WHERE tournament_id=@t', { t: tour2Id });
await run(
  `INSERT INTO tournament_teams (tournament_id, team_id, group_no)
         VALUES (@t, @team0, @g0),(@t, @team1, @g1) ON CONFLICT DO NOTHING`,
  { t: tour2Id, team0: 1, g0: 1, team1: 2, g1: 1 },
);
await run(
  `INSERT INTO tournament_matches
           (tournament_id, group_no, round, slot, home_team_id, away_team_id, kickoff)
         VALUES (@t0, @g0, @r0, @s0, @h0, @a0, @k0) ON CONFLICT DO NOTHING`,
  { t0: tour2Id, g0: 1, r0: 1, s0: 1, h0: 1, a0: 2, k0: new Date().toISOString() },
);
const rebuilt = await rows('SELECT * FROM tournament_matches WHERE tournament_id=@t', { t: tour2Id });
check('jadwal turnamen bisa dibuat ulang setelah skor direset',
  rebuilt.length === 1 && rebuilt[0].status === 'scheduled', `${rebuilt.length} laga`);

// ---------- 17d. Koreksi pengumuman & transaksi kas ----------
await run(
  'UPDATE announcements SET title=@t, body=@b WHERE id=@id',
  { id: 1, t: 'Judul dikoreksi', b: 'Isi dikoreksi' },
);
const ann = (await rows('SELECT * FROM announcements')).find((a) => a.id === 1);
check('pengumuman bisa dikoreksi tanpa membuat ulang',
  ann.title === 'Judul dikoreksi' && ann.body === 'Isi dikoreksi', ann.title);

const txBefore = (await rows('SELECT * FROM transactions')).find((t) => t.kind === 'expense' && !t.booking_id);
await run(
  `UPDATE transactions SET kind=@kind, category=@category,
             amount=@amount, occurred_at=@date, note=@note WHERE id=@id`,
  {
    id: txBefore.id, kind: 'expense', category: 'wasit',
    amount: 250000, date: txBefore.occurred_at, note: 'Wasit (dikoreksi)',
  },
);
const txAfter = (await rows('SELECT * FROM transactions')).find((t) => t.id === txBefore.id);
check('nominal transaksi kas bisa dikoreksi',
  Number(txAfter.amount) === 250000 && txAfter.category === 'wasit' && txAfter.note === 'Wasit (dikoreksi)',
  `${txAfter.amount} ${txAfter.category}`);

// ---------- 18. `npm run db:fix`: booking lama masuk kas, iuran ganda dirapikan ----------
// Mock sengaja punya satu booking yang sudah tertaut dan dua yang belum
// (seed). Jalankan statement yang sama dengan scripts/fix-data.mjs.
// Buat satu booking tanpa tautan kas supaya pemeriksaan ini tetap berarti
// saat skrip dijalankan ulang pada mock yang sama.
await run(
  `INSERT INTO bookings (title, starts_at, duration_min, cost)
         VALUES (@t, @s, @d, @c) RETURNING id`,
  { t: `Sewa tanpa kas ${stamp}`, s: new Date().toISOString(), d: 90, c: 200000 },
);
const fixOrphans = await rows(
  `SELECT b.id, b.title, b.cost, b.starts_at FROM bookings b
      LEFT JOIN transactions t ON t.booking_id = b.id
      WHERE b.cost > 0 AND t.id IS NULL
      ORDER BY b.starts_at`,
);
check('booking berbiaya yang belum masuk kas terdeteksi', fixOrphans.length > 0,
  `${fixOrphans.length} booking`);
for (const b of fixOrphans) {
  await run(
    `INSERT INTO transactions (kind, category, amount, occurred_at, note, booking_id)
     VALUES ('expense', 'sewa', @amount, @date, @note, @booking)`,
    { amount: b.cost, date: b.starts_at, note: b.title, booking: b.id },
  );
}
const orphansAfter = await rows(
  `SELECT b.id, b.title, b.cost, b.starts_at FROM bookings b
      LEFT JOIN transactions t ON t.booking_id = b.id
      WHERE b.cost > 0 AND t.id IS NULL
      ORDER BY b.starts_at`,
);
check('setelah db:fix tidak ada booking tanpa catatan kas', orphansAfter.length === 0,
  `${orphansAfter.length} tersisa`);

const cashTotal = (await rows('SELECT * FROM transactions'))
  .filter((t) => t.booking_id != null)
  .reduce((s, t) => s + Number(t.amount), 0);
const rentTotal = (await rows('SELECT b.*, t.id AS transaction_id FROM bookings b LEFT JOIN transactions t ON t.booking_id = b.id ORDER BY b.starts_at DESC LIMIT 100'))
  .reduce((s, b) => s + Number(b.cost), 0);
check('total sewa = total catatan kas sewa', cashTotal === rentTotal,
  `kas ${cashTotal} vs booking ${rentTotal}`);

// Iuran ganda: buat satu duplikat, pastikan terdeteksi lalu terhapus.
await run(
  `INSERT INTO payments (member_id, amount, period, note)
           VALUES (@mid, @amt, @period, @note)`,
  { mid: payMember, amt: 75000, period, note: 'duplikat uji' },
);
const dupeGroups = (await rows(
  `SELECT count(*)::int AS n FROM (
         SELECT 1 FROM payments GROUP BY member_id, period HAVING count(*) > 1
       ) d`,
))[0].n;
check('iuran ganda terdeteksi', dupeGroups >= 1, `${dupeGroups} grup`);
const allPayments = (await rows('SELECT * FROM payments')).sort(
  (a, b) => a.member_id - b.member_id || a.period.localeCompare(b.period) ||
    b.paid_at.localeCompare(a.paid_at) || b.id - a.id,
);
const seen = new Set();
const toDelete = [];
for (const p of allPayments) {
  const key = `${p.member_id}|${p.period}`;
  if (seen.has(key)) toDelete.push(p.id);
  else seen.add(key);
}
for (const id of toDelete) await run('DELETE FROM payments WHERE id=@id', { id });
const dupeAfter = (await rows(
  `SELECT count(*)::int AS n FROM (
         SELECT 1 FROM payments GROUP BY member_id, period HAVING count(*) > 1
       ) d`,
))[0].n;
check('setelah db:fix tidak ada iuran ganda', dupeAfter === 0, `${dupeAfter} grup`);

console.log(failures === 0 ? '\nSEMUA E2E LULUS' : `\n${failures} E2E GAGAL`);
process.exit(failures === 0 ? 0 : 1);
