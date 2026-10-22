import { test } from 'node:test';
import assert from 'node:assert/strict';

import { rejectSql, toPositional } from './_guard.js';
import { APP_WEB_TABLES, APP_WEB_VIEWS } from '../scripts/_grants.mjs';

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
  matches: `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id ORDER BY m.played_at DESC LIMIT @limit`,
  upcoming: `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id WHERE m.status='ongoing' OR (m.status='scheduled' AND m.played_at >= now() - interval '3 hours') ORDER BY m.played_at ASC LIMIT 5`,
  matchById: `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id WHERE m.id=@id`,
  recentFinished: `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id WHERE m.status='finished' ORDER BY m.played_at DESC LIMIT @limit`,
  teamMatches: `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id WHERE m.home_team_id=@t OR m.away_team_id=@t ORDER BY m.played_at DESC LIMIT @limit`,
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
  paymentExists: 'SELECT 1 AS ok FROM payments WHERE member_id=@mid AND period=@p LIMIT 1',
  transactions: `SELECT * FROM transactions
         WHERE to_char(occurred_at, 'YYYY-MM') = @p
         ORDER BY occurred_at DESC, id DESC`,
  bookings: "SELECT * FROM bookings WHERE status='booked' AND starts_at >= now() ORDER BY starts_at ASC LIMIT 5",
  bookingsWithCash: `SELECT b.*, t.id AS transaction_id FROM bookings b
         LEFT JOIN transactions t ON t.booking_id = b.id
         ORDER BY b.starts_at DESC LIMIT 100`,
  sessions: 'SELECT * FROM match_sessions WHERE match_id=@m ORDER BY session_no',
  scorers: `SELECT coalesce(m.name, '(mantan anggota)') AS name,
                count(*) FILTER (WHERE e.type='goal')::int   AS goals,
                count(*) FILTER (WHERE e.type='assist')::int AS assists
         FROM match_events e LEFT JOIN members m ON m.id = e.member_id
         GROUP BY 1 HAVING count(*) FILTER (WHERE e.type='goal') > 0
         ORDER BY goals DESC, assists DESC LIMIT 10`,
  teams: 'SELECT * FROM teams ORDER BY name',
  teamPlayers: `SELECT tp.team_id, m.* FROM team_players tp
         JOIN members m ON m.id = tp.member_id
         ORDER BY m.name`,
  teamPlayersTournament: `SELECT tp.team_id, m.* FROM team_players tp
         JOIN members m ON m.id = tp.member_id
         JOIN tournament_teams tt ON tt.team_id = tp.team_id
         WHERE tt.tournament_id=@t ORDER BY m.name`,
  teamTournaments: `SELECT DISTINCT tournament_id FROM tournament_matches
         WHERE home_team_id=@id OR away_team_id=@id`,
  teamDeletionImpact: `SELECT (SELECT count(*)::int FROM matches
                WHERE home_team_id=@id OR away_team_id=@id) AS internal,
              (SELECT count(*)::int FROM tournament_matches
                WHERE home_team_id=@id OR away_team_id=@id) AS tournament`,
  teamStandings: `SELECT * FROM v_team_standings
         ORDER BY points DESC, (goals_for - goals_against) DESC, goals_for DESC, name`,
  tournamentTeams: `SELECT t.*, tt.group_no FROM tournament_teams tt
         JOIN teams t ON t.id = tt.team_id
         WHERE tt.tournament_id=@t ORDER BY tt.group_no, t.name`,
  tournamentMatchList: 'SELECT * FROM tournament_matches WHERE tournament_id=@t ORDER BY slot',
  tournamentDoneCount: `SELECT count(*)::int AS n FROM tournament_matches
         WHERE tournament_id=@t AND status='done'`,
  tournaments: 'SELECT * FROM tournaments ORDER BY starts_at DESC',
  users: 'SELECT id, username, role, active FROM users ORDER BY role, username',
};

const writes = {
  insertMember:
    'INSERT INTO members (name, phone, position, jersey) VALUES (@name, @phone, @position, @jersey)',
  updateMember: `UPDATE members SET name=@name, phone=@phone, position=@position,
           jersey=@jersey, active=@active WHERE id=@id`,
  deleteMember: 'DELETE FROM members WHERE id=@id',
  insertMatch: `INSERT INTO matches (home_team_id, away_team_id, played_at, venue)
           VALUES (@h, @a, @t, @v)`,
  updateMatchSchedule: `UPDATE matches SET home_team_id=@h, away_team_id=@a,
           played_at=@t, venue=@v WHERE id=@id`,
  startMatch: "UPDATE matches SET status='ongoing' WHERE id=@id AND status='scheduled'",
  finishMatch: "UPDATE matches SET status='finished', goals_for=@gf, goals_against=@ga WHERE id=@id",
  reopenMatch: `UPDATE matches SET status = CASE
             WHEN EXISTS (SELECT 1 FROM match_sessions WHERE match_id=@id)
               THEN 'ongoing' ELSE 'scheduled' END
           WHERE id=@id`,
  insertEvent: `INSERT INTO match_events (match_id, member_id, minute, type)
           VALUES (@mid, @mem, @min, @type)`,
  insertPayment: `INSERT INTO payments (member_id, amount, period, note)
           VALUES (@mid, @amt, @period, @note)`,
  insertTransaction: `INSERT INTO transactions (kind, category, amount, occurred_at, note)
           VALUES (@kind, @category, @amount, @date, @note)`,
  insertBooking: `INSERT INTO bookings (title, starts_at, duration_min, cost)
           VALUES (@t, @s, @d, @c) RETURNING id`,
  insertBookingCash: `INSERT INTO transactions (kind, category, amount, occurred_at, note, booking_id)
         VALUES ('expense', 'sewa', @amount, @date, @note, @booking)`,
  upsertSession: `INSERT INTO match_sessions (match_id, session_no, score_home, score_away, winner, ended_at)
           VALUES (@m, @sn, @h, @a, @w, now())
           ON CONFLICT (match_id, session_no) DO UPDATE SET
             score_home=@h, score_away=@a, winner=@w, ended_at=now()`,
  updateSession: `UPDATE match_sessions SET score_home=@h, score_away=@a, winner=@w, ended_at=now()
           WHERE id=@id`,
  syncTotals: `UPDATE matches SET
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
           WHERE id=@m`,
  insertTournament: `INSERT INTO tournaments (name, venue, starts_at, match_minutes, break_minutes, groups)
         VALUES (@n, @v, @s, @mm, @bm, @g) RETURNING id`,
  insertTeam: 'INSERT INTO teams (name) VALUES (@n) RETURNING id',
  insertGroups: `INSERT INTO tournament_teams (tournament_id, team_id, group_no)
         VALUES (@t, @team0, @g0),(@t, @team1, @g1) ON CONFLICT DO NOTHING`,
  insertSchedule: `INSERT INTO tournament_matches
           (tournament_id, group_no, round, slot, home_team_id, away_team_id, kickoff)
         VALUES (@t0, @g0, @r0, @s0, @h0, @a0, @k0),(@t1, @g1, @r1, @s1, @h1, @a1, @k1) ON CONFLICT DO NOTHING`,
  clearGroups: 'DELETE FROM tournament_teams WHERE tournament_id=@t',
  clearTournamentMatches: 'DELETE FROM tournament_matches WHERE tournament_id=@t',
  updateTournamentRules: 'UPDATE tournaments SET groups=@g, match_minutes=@mm, break_minutes=@bm WHERE id=@t',
  insertPlayers: 'INSERT INTO team_players (team_id, member_id) VALUES (@t0, @m0),(@t1, @m1) ON CONFLICT DO NOTHING',
  setTournamentStatus: 'UPDATE tournaments SET status=@s WHERE id=@id',
  setMatchScore: `UPDATE tournament_matches SET score_home=@h, score_away=@a, status='done'
         WHERE id=@id`,
  clearMatchScore: `UPDATE tournament_matches SET score_home=NULL, score_away=NULL,
           status='scheduled' WHERE id=@id`,
  syncTournamentStatus: `UPDATE tournaments SET status = CASE
             WHEN EXISTS (SELECT 1 FROM tournament_matches
                          WHERE tournament_id=@t AND status <> 'done')
               THEN CASE WHEN EXISTS (SELECT 1 FROM tournament_matches
                                       WHERE tournament_id=@t AND status='done')
                         THEN 'running' ELSE 'draft' END
             WHEN EXISTS (SELECT 1 FROM tournament_matches WHERE tournament_id=@t)
               THEN 'done'
             ELSE 'draft' END
           WHERE id=@t`,
  renameTeam: 'UPDATE teams SET name=@n WHERE id=@id',
  addPlayer: 'INSERT INTO team_players (team_id, member_id) VALUES (@t, @m) ON CONFLICT DO NOTHING',
  removePlayer: 'DELETE FROM team_players WHERE team_id=@t AND member_id=@m',
  updateAnnouncement: 'UPDATE announcements SET title=@t, body=@b WHERE id=@id',
  updateTransaction: `UPDATE transactions SET kind=@kind, category=@category,
             amount=@amount, occurred_at=@date, note=@note WHERE id=@id`,
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

// Izin `app_web` (scripts/_grants.mjs) harus mencakup setiap tabel/view yang
// dipanggil app. Query yang lolos filter SQL tetap gagal di Neon kalau
// grant-nya lupa ditambah — ini yang dulu terjadi pada `tournament_teams`
// dan `v_team_standings`.
test('setiap tabel/view aplikasi punya izin app_web', () => {
  const granted = new Set([...APP_WEB_TABLES, ...APP_WEB_VIEWS, 'users']);
  const referenced = new Set();
  // `DO UPDATE SET ...` bukan nama tabel, jadi kata kunci SQL disaring.
  const keywords = new Set(['set', 'select', 'where', 'values', 'only']);
  for (const sql of [...Object.values(reads), ...Object.values(writes)]) {
    for (const m of sql.matchAll(/\b(?:from|join|into|update)\s+([a-z_][a-z0-9_]*)/gi)) {
      const name = m[1].toLowerCase();
      if (!keywords.has(name)) referenced.add(name);
    }
  }
  for (const table of referenced) {
    assert.ok(granted.has(table), `tabel ${table} dipakai app tapi tidak di-grant`);
  }
});
