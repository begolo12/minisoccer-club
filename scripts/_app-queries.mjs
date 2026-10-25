// Semua query yang benar-benar dikirim aplikasi (lib/data/models.dart), sebagai
// data murni tanpa `node:test`.
//
// Satu sumber kebenaran untuk dua pemakai:
//   - api/_app-queries.test.mjs  → memastikan filter `_guard.js` tidak terlalu
//     ketat (query yang ditolak = fitur mati) dan setiap tabel punya grant.
//   - scripts/e2e-check.mjs      → menjalankan query yang sama ke server
//     sungguhan untuk tiap role, jadi schema yang kurang kolom atau izin yang
//     belum diberikan ketahuan sebelum dilihat pengguna.
export const reads = {
  members: 'SELECT * FROM members WHERE active ORDER BY name',
  membersAll: 'SELECT * FROM members  ORDER BY name',
  memberCount: 'SELECT count(*)::int AS c FROM members WHERE active',
  // `WHERE home_team_id IS NOT NULL AND away_team_id IS NOT NULL` membuang
  // baris warisan schema v1 (laga lawan luar yang tidak punya dua tim klub).
  matches: `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id
     WHERE NOT (m.home_team_id IS NULL AND m.away_team_id IS NULL) ORDER BY m.played_at DESC LIMIT @limit`,
  upcoming: `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id
     WHERE NOT (m.home_team_id IS NULL AND m.away_team_id IS NULL) AND (m.status='ongoing' OR (m.status='scheduled' AND m.played_at >= now() - interval '3 hours')) ORDER BY m.played_at ASC LIMIT 5`,
  matchById: `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id
     WHERE NOT (m.home_team_id IS NULL AND m.away_team_id IS NULL) AND m.id=@id`,
  recentFinished: `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id
     WHERE NOT (m.home_team_id IS NULL AND m.away_team_id IS NULL) AND m.status='finished' ORDER BY m.played_at DESC LIMIT @limit`,
  teamMatches: `SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id
     WHERE NOT (m.home_team_id IS NULL AND m.away_team_id IS NULL) AND (m.home_team_id=@t OR m.away_team_id=@t) ORDER BY m.played_at DESC LIMIT @limit`,
  matchStats: `SELECT count(*) FILTER (WHERE goals_for > goals_against)::int AS w,
                count(*) FILTER (WHERE goals_for = goals_against)::int AS d,
                count(*) FILTER (WHERE goals_for < goals_against)::int AS l,
                coalesce(sum(goals_for), 0)::int AS gf,
                coalesce(sum(goals_against), 0)::int AS ga
         FROM matches WHERE status='finished' `,
  events: `SELECT e.*, m.name AS member_name FROM match_events e
         LEFT JOIN members m ON m.id = e.member_id
         WHERE e.match_id = @mid ORDER BY e.minute NULLS LAST, e.id`,
  // Iuran terikat TURNAMEN (bukan bulan): `tournament_id`, bukan `period`.
  payments: `SELECT p.*, m.name AS member_name, t.name AS tournament_name
         FROM payments p
         JOIN members m ON m.id = p.member_id
         LEFT JOIN tournaments t ON t.id = p.tournament_id
         WHERE p.tournament_id = @t
         ORDER BY p.paid_at DESC`,
  paymentsInMonth: `SELECT p.*, m.name AS member_name, t.name AS tournament_name
         FROM payments p
         JOIN members m ON m.id = p.member_id
         LEFT JOIN tournaments t ON t.id = p.tournament_id
         WHERE p.paid_at >= @from AND p.paid_at < @to
         ORDER BY p.paid_at DESC`,
  // `GROUP BY m.id, p.id` — Postgres mengizinkan semua kolom ikut dipilih
  // lewat functional dependency pada primary key. Menyebut `m.phone` di sini
  // membuat query DITOLAK untuk tamu dan anggota (lihat api/_privacy.js).
  duesBill: `SELECT m.*, p.id AS payment_id, p.amount AS paid_amount,
                p.paid_at AS paid_at, p.note AS paid_note
         FROM members m
         JOIN team_players tp ON tp.member_id = m.id
         JOIN tournament_teams tt ON tt.team_id = tp.team_id
         LEFT JOIN payments p ON p.member_id = m.id AND p.tournament_id = @t
         WHERE tt.tournament_id = @t
         GROUP BY m.id, p.id
         ORDER BY m.name`,
  paymentExists: 'SELECT 1 AS ok FROM payments WHERE member_id=@mid AND tournament_id=@t LIMIT 1',
  paymentsForMember: `SELECT p.*, m.name AS member_name, t.name AS tournament_name
         FROM payments p
         JOIN members m ON m.id = p.member_id
         LEFT JOIN tournaments t ON t.id = p.tournament_id
         WHERE p.member_id = @m
         ORDER BY p.paid_at DESC`,
  unpaidForMember: `SELECT t.* FROM tournaments t
         JOIN tournament_teams tt ON tt.tournament_id = t.id
         JOIN team_players tp ON tp.team_id = tt.team_id
         WHERE tp.member_id = @m
           AND t.entry_fee > 0
           AND NOT EXISTS (
             SELECT 1 FROM payments p
             WHERE p.member_id = @m AND p.tournament_id = t.id)
         GROUP BY t.id
         ORDER BY t.starts_at DESC`,
  attendanceForBooking: `SELECT a.*, m.name AS member_name, t.id AS transaction_id,
                t.amount AS transaction_amount,
                b.title AS booking_title, b.starts_at AS booking_starts_at
         FROM booking_attendance a
         JOIN members m ON m.id = a.member_id
         JOIN bookings b ON b.id = a.booking_id
         LEFT JOIN transactions t ON t.attendance_id = a.id
         WHERE a.booking_id=@bid ORDER BY m.name`,
  attendanceForMember: `SELECT a.*, m.name AS member_name, t.id AS transaction_id,
                t.amount AS transaction_amount,
                b.title AS booking_title, b.starts_at AS booking_starts_at
         FROM booking_attendance a
         JOIN members m ON m.id = a.member_id
         JOIN bookings b ON b.id = a.booking_id
         LEFT JOIN transactions t ON t.attendance_id = a.id
         WHERE a.member_id=@m ORDER BY b.starts_at DESC`,
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

export const writes = {
  insertMember:
    'INSERT INTO members (name, phone, address, position, jersey) VALUES (@name, @phone, @address, @position, @jersey)',
  updateMember: `UPDATE members SET name=@name, phone=@phone, address=@address,
           position=@position, jersey=@jersey, active=@active WHERE id=@id`,
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
  insertPayment: `INSERT INTO payments (member_id, amount, tournament_id, note)
           VALUES (@mid, @amt, @t, @note) RETURNING id`,
  insertTransaction: `INSERT INTO transactions (kind, category, amount, occurred_at, note)
           VALUES (@kind, @category, @amount, @date, @note)`,
  insertBooking: `INSERT INTO bookings (title, starts_at, duration_min, cost)
           VALUES (@t, @s, @d, @c) RETURNING id`,
  insertBookingCash: `INSERT INTO transactions (kind, category, amount, occurred_at, note, booking_id)
         VALUES ('expense', 'sewa', @amount, @date, @note, @booking)`,
  insertAttendance: `INSERT INTO booking_attendance (booking_id, member_id, share_amount)
         VALUES (@bid, @m, 0)
         ON CONFLICT (booking_id, member_id) DO NOTHING
         RETURNING id`,
  rebalanceAttendance: `UPDATE booking_attendance SET share_amount = v.share
         FROM (VALUES (@id0, @s0), (@id1, @s1)) AS v(id, share)
         WHERE booking_attendance.id = v.id`,
  deleteAttendance: 'DELETE FROM booking_attendance WHERE id=@id',
  markAttendancePaid: 'UPDATE booking_attendance SET paid_at=now() WHERE id=@id',
  clearAttendancePaid: 'UPDATE booking_attendance SET paid_at=NULL WHERE id=@id',
  insertAttendanceCash: `INSERT INTO transactions (kind, category, amount, occurred_at, member_id, note, attendance_id)
         VALUES ('income', 'patungan', @amount, @date, @member, @note, @a)
         ON CONFLICT (attendance_id) DO NOTHING`,
  deleteAttendanceCash: 'DELETE FROM transactions WHERE attendance_id=@a',
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

/**
 * Nilai contoh untuk setiap parameter `@nama` supaya query bisa dijalankan
 * sungguhan (bukan hanya diikat). Tipe sengaja cocok dengan kolomnya: id
 * integer dan tanggal ISO.
 */
export const sampleParams = {
  limit: 20,
  id: 1,
  t: 1,
  h: 1,
  a: 2,
  mid: 1,
  mem: 1,
  // Booking untuk kehadiran/patungan. Sengaja `bid`, bukan `b`: huruf b
  // sudah dipakai sebagai isi pengumuman, jadi satu nilai contoh tidak bisa
  // mewakili dua arti berbeda.
  bid: 1,
  share: 50000,
  id0: 1,
  s0: 50000,
  id1: 2,
  s1: 50000,
  min: 12,
  m: 1,
  p: '2026-10',
  // Rentang bulan untuk `Payment.inMonth` (nama sengaja bukan @a/@b supaya
  // tidak bertabrakan dengan id tim tamu).
  from: '2026-10-01T00:00:00.000Z',
  to: '2026-11-01T00:00:00.000Z',
  amt: 50000,
  amount: 50000,
  name: '_uji_query',
  phone: '0800000000',
  position: 'Bebas',
  jersey: 9,
  active: true,
  type: 'goal',
  kind: 'income',
  category: 'lain',
  date: '2026-10-01',
  s: '2026-10-01T10:00:00.000Z',
  d: 90,
  c: 0,
  note: '_uji_query',
  n: '_uji_query',
  v: null,
  b: '_uji_query',
  gf: 0,
  ga: 0,
  sn: 1,
  w: 'draw',
  mm: 20,
  bm: 0,
  g: 1,
  g0: 1,
  g1: 2,
  r0: 1,
  r1: 1,
  s0: 1,
  s1: 2,
  h0: 1,
  h1: 2,
  a0: 2,
  a1: 1,
  k0: '2026-10-01T10:00:00.000Z',
  k1: '2026-10-01T11:00:00.000Z',
  t0: 1,
  t1: 2,
  team0: 1,
  team1: 2,
  m0: 1,
  m1: 2,
  booking: null,
};

/** Ambil nama parameter `@nama` dari sebuah query, berurutan unik. */
export function paramNames(sql) {
  return [...new Set([...sql.matchAll(/@([a-zA-Z_][a-zA-Z0-9_]*)/g)].map((m) => m[1]))];
}

/** Objek params untuk satu query, hanya yang benar-benar dipakai. */
export function paramsFor(sql) {
  const out = {};
  for (const name of paramNames(sql)) out[name] = sampleParams[name] ?? null;
  return out;
}
