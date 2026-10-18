import { test } from 'node:test';
import assert from 'node:assert/strict';

import { rejectSql, toPositional } from './_guard.js';

// Query yang benar-benar dikirim aplikasi (lib/data/models.dart). Tujuannya
// menangkap filter yang terlalu ketat: kalau daftar ini ditolak, fitur di app
// ikut mati walau tidak ada masalah keamanan.
const admin = { r: 'admin' };
const treasurer = { r: 'treasurer' };
const member = { r: 'member' };

const reads = {
  members: 'SELECT * FROM members WHERE active ORDER BY name',
  membersAll: 'SELECT * FROM members  ORDER BY name',
  memberCount: 'SELECT count(*)::int AS c FROM members WHERE active',
  matches: 'SELECT * FROM matches ORDER BY played_at DESC LIMIT @limit',
  upcoming:
    "SELECT * FROM matches WHERE status IN ('scheduled', 'ongoing') AND played_at >= now() - interval '3 hours' ORDER BY played_at ASC LIMIT 5",
  recentFinished: "SELECT * FROM matches WHERE status='finished' ORDER BY played_at DESC LIMIT @limit",
  matchStats: `SELECT count(*) FILTER (WHERE goals_for > goals_against)::int AS w,
                count(*) FILTER (WHERE goals_for = goals_against)::int AS d,
                count(*) FILTER (WHERE goals_for < goals_against)::int AS l,
                coalesce(sum(goals_for), 0)::int AS gf,
                coalesce(sum(goals_against), 0)::int AS ga
         FROM matches WHERE status='finished' `,
  events: `SELECT e.*, m.name AS member_name FROM match_events e
         LEFT JOIN members m ON m.id = e.member_id
         WHERE e.match_id = @mid ORDER BY e.minute NULLS LAST, e.id`,
  payments: `SELECT p.*, m.name AS member_name FROM payments p
         JOIN members m ON m.id = p.member_id
         WHERE p.period = @p
         ORDER BY p.paid_at DESC`,
  standardAmount: `SELECT amount, count(*)::int AS n FROM payments
         GROUP BY amount ORDER BY n DESC, amount DESC LIMIT 1`,
  transactions: `SELECT * FROM transactions
         WHERE to_char(occurred_at, 'YYYY-MM') = @p
         ORDER BY occurred_at DESC, id DESC`,
  bookings: "SELECT * FROM bookings WHERE status='booked' AND starts_at >= now() ORDER BY starts_at ASC LIMIT 5",
  sessions: 'SELECT * FROM match_sessions WHERE match_id=@m ORDER BY session_no',
  scorers: `SELECT coalesce(m.name, '(mantan anggota)') AS name,
                count(*) FILTER (WHERE e.type='goal')::int   AS goals,
                count(*) FILTER (WHERE e.type='assist')::int AS assists
         FROM match_events e LEFT JOIN members m ON m.id = e.member_id
         GROUP BY 1 HAVING count(*) FILTER (WHERE e.type='goal') > 0
         ORDER BY goals DESC, assists DESC LIMIT 10`,
  teamPlayers: `SELECT tp.team_id, m.* FROM team_players tp
         JOIN members m ON m.id = tp.member_id
         JOIN teams t ON t.id = tp.team_id
         WHERE t.tournament_id=@t ORDER BY m.name`,
  users: 'SELECT id, username, role, active FROM users ORDER BY role, username',
};

const writes = {
  insertMember:
    'INSERT INTO members (name, phone, position, jersey) VALUES (@name, @phone, @position, @jersey)',
  updateMember: `UPDATE members SET name=@name, phone=@phone, position=@position,
           jersey=@jersey, active=@active WHERE id=@id`,
  deleteMember: 'DELETE FROM members WHERE id=@id',
  insertMatch: `INSERT INTO matches (opponent, played_at, venue, is_home)
           VALUES (@opponent, @playedAt, @venue, @isHome)`,
  finishMatch: "UPDATE matches SET status='finished', goals_for=@gf, goals_against=@ga WHERE id=@id",
  insertEvent: `INSERT INTO match_events (match_id, member_id, minute, type)
           VALUES (@mid, @mem, @min, @type)`,
  insertPayment: `INSERT INTO payments (member_id, amount, period, note)
           VALUES (@mid, @amt, @period, @note)`,
  insertTransaction: `INSERT INTO transactions (kind, category, amount, occurred_at, note)
           VALUES (@kind, @category, @amount, @date, @note)`,
  insertBooking: `INSERT INTO bookings (title, starts_at, duration_min, cost)
           VALUES (@t, @s, @d, @c)`,
  upsertSession: `INSERT INTO match_sessions (match_id, session_no, score_home, score_away, winner, ended_at)
           VALUES (@m, @sn, @h, @a, @w, now())
           ON CONFLICT (match_id, session_no) DO UPDATE SET
             score_home=@h, score_away=@a, winner=@w, ended_at=now()`,
  updateSession: `UPDATE match_sessions SET score_home=@h, score_away=@a, winner=@w, ended_at=now()
           WHERE id=@id`,
  syncTotals: `UPDATE matches SET
             goals_for = COALESCE((SELECT sum(score_home) FROM match_sessions WHERE match_id=@m), 0),
             goals_against = COALESCE((SELECT sum(score_away) FROM match_sessions WHERE match_id=@m), 0),
             status = CASE WHEN status='scheduled' THEN 'ongoing' ELSE status END
           WHERE id=@m`,
  insertTournament: `INSERT INTO tournaments (name, venue, starts_at, match_minutes, break_minutes)
         VALUES (@n, @v, @s, @mm, @bm) RETURNING id`,
  insertTeams: 'INSERT INTO teams (tournament_id, name) VALUES (@t, @n) RETURNING id',
  insertSchedule: `INSERT INTO tournament_matches
           (tournament_id, round, slot, home_team_id, away_team_id, kickoff)
         VALUES (@t0, @r0, @s0, @h0, @a0, @k0),(@t1, @r1, @s1, @h1, @a1, @k1) ON CONFLICT DO NOTHING`,
  clearPlayers:
    'DELETE FROM team_players WHERE team_id IN (SELECT id FROM teams WHERE tournament_id=@t)',
  insertPlayers: 'INSERT INTO team_players (team_id, member_id) VALUES (@t0, @m0),(@t1, @m1) ON CONFLICT DO NOTHING',
  setTournamentStatus: 'UPDATE tournaments SET status=@s WHERE id=@id',
  setMatchScore: `UPDATE tournament_matches SET score_home=@h, score_away=@a, status='done'
         WHERE id=@id`,
  clearMatchScore: `UPDATE tournament_matches SET score_home=NULL, score_away=NULL,
           status='scheduled' WHERE id=@id`,
  startTournament: "UPDATE tournaments SET status='running' WHERE id=@t AND status='draft'",
  renameTeam: 'UPDATE teams SET name=@n WHERE id=@id',
  addPlayer: 'INSERT INTO team_players (team_id, member_id) VALUES (@t, @m) ON CONFLICT DO NOTHING',
  removePlayer: 'DELETE FROM team_players WHERE team_id=@t AND member_id=@m',
  deleteAnnouncement: 'DELETE FROM announcements WHERE id=@id',
  setBookingStatus: 'UPDATE bookings SET status=@s WHERE id=@id',
};

test('semua query aplikasi lolos untuk admin', () => {
  for (const [name, sql] of Object.entries(reads)) {
    assert.equal(rejectSql(sql, admin), null, `baca ${name}`);
  }
  for (const [name, sql] of Object.entries(writes)) {
    assert.equal(rejectSql(sql, admin), null, `tulis ${name}`);
  }
});

test('bendahara boleh menulis data klub', () => {
  for (const [name, sql] of Object.entries(writes)) {
    assert.equal(rejectSql(sql, treasurer), null, `tulis ${name}`);
  }
});

test('anggota hanya boleh membaca', () => {
  for (const [name, sql] of Object.entries(reads)) {
    if (name === 'users') continue; // daftar pengguna khusus admin
    assert.equal(rejectSql(sql, member), null, `baca ${name}`);
  }
  for (const [name, sql] of Object.entries(writes)) {
    assert.notEqual(rejectSql(sql, member), null, `tulis ${name}`);
  }
});

test('semua query aplikasi bisa diikat parameternya', () => {
  for (const sql of [...Object.values(reads), ...Object.values(writes)]) {
    const names = [...sql.matchAll(/@([a-zA-Z_][a-zA-Z0-9_]*)/g)].map((m) => m[1]);
    const params = Object.fromEntries(names.map((n) => [n, 1]));
    assert.doesNotThrow(() => toPositional(sql, params), sql.slice(0, 40));
  }
});
