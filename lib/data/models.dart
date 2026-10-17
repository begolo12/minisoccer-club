/// Model + query layer. Semua akses DB lewat sini.
library;

import '../core/db.dart';

// ---------- Members ----------

class Member {
  final int id;
  final String name;
  final String? phone;
  final String position;
  final int? jersey;
  final bool active;
  final DateTime joinedAt;

  Member({
    required this.id,
    required this.name,
    this.phone,
    required this.position,
    this.jersey,
    required this.active,
    required this.joinedAt,
  });

  factory Member.fromMap(Map<String, dynamic> m) => Member(
        id: m['id'] as int,
        name: m['name'] as String,
        phone: m['phone'] as String?,
        position: (m['position'] as String?) ?? 'Bebas',
        jersey: m['jersey'] as int?,
        active: (m['active'] as bool?) ?? true,
        joinedAt: _dt(m['joined_at']),
      );

  static Future<List<Member>> all({bool activeOnly = false}) async {
    final rows = await Db.query(
      'SELECT * FROM members ${activeOnly ? 'WHERE active' : ''} ORDER BY name',
    );
    return rows.map(Member.fromMap).toList();
  }

  static Future<void> insert({
    required String name,
    String? phone,
    required String position,
    int? jersey,
  }) =>
      Db.execute(
        'INSERT INTO members (name, phone, position, jersey) VALUES (@name, @phone, @position, @jersey)',
        params: {'name': name, 'phone': phone, 'position': position, 'jersey': jersey},
      );

  Future<void> update({
    required String name,
    String? phone,
    required String position,
    int? jersey,
    required bool active,
  }) =>
      Db.execute(
        '''UPDATE members SET name=@name, phone=@phone, position=@position,
           jersey=@jersey, active=@active WHERE id=@id''',
        params: {
          'id': id, 'name': name, 'phone': phone,
          'position': position, 'jersey': jersey, 'active': active,
        },
      );

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM members WHERE id=@id', params: {'id': id});

  static Future<int> countActive() async {
    final rows = await Db.query('SELECT count(*)::int AS c FROM members WHERE active');
    return rows.first['c'] as int;
  }
}

// ---------- Matches ----------

class Match {
  final int id;
  final String opponent;
  final DateTime playedAt;
  final String? venue;
  final bool isHome;
  final String status;
  final int goalsFor;
  final int goalsAgainst;
  final String? notes;

  Match({
    required this.id,
    required this.opponent,
    required this.playedAt,
    this.venue,
    required this.isHome,
    required this.status,
    required this.goalsFor,
    required this.goalsAgainst,
    this.notes,
  });

  factory Match.fromMap(Map<String, dynamic> m) => Match(
        id: m['id'] as int,
        opponent: m['opponent'] as String,
        playedAt: _dt(m['played_at']),
        venue: m['venue'] as String?,
        isHome: (m['is_home'] as bool?) ?? true,
        status: (m['status'] as String?) ?? 'scheduled',
        goalsFor: (m['goals_for'] as int?) ?? 0,
        goalsAgainst: (m['goals_against'] as int?) ?? 0,
        notes: m['notes'] as String?,
      );

  String get resultLabel {
    if (status != 'finished') return 'vs $opponent';
    if (goalsFor > goalsAgainst) return 'Menang $goalsFor-$goalsAgainst';
    if (goalsFor < goalsAgainst) return 'Kalah $goalsFor-$goalsAgainst';
    return 'Draw $goalsFor-$goalsAgainst';
  }

  static Future<List<Match>> all({int limit = 100}) async {
    final rows = await Db.query(
      'SELECT * FROM matches ORDER BY played_at DESC LIMIT @limit',
      params: {'limit': limit},
    );
    return rows.map(Match.fromMap).toList();
  }

  static Future<List<Match>> upcoming() async {
    final rows = await Db.query(
      "SELECT * FROM matches WHERE status='scheduled' AND played_at >= now() - interval '3 hours' ORDER BY played_at ASC LIMIT 5",
    );
    return rows.map(Match.fromMap).toList();
  }

  static Future<void> insert({
    required String opponent,
    required DateTime playedAt,
    String? venue,
    required bool isHome,
  }) =>
      Db.execute(
        '''INSERT INTO matches (opponent, played_at, venue, is_home)
           VALUES (@opponent, @playedAt, @venue, @isHome)''',
        params: {'opponent': opponent, 'playedAt': playedAt, 'venue': venue, 'isHome': isHome},
      );

  Future<void> finish({required int gf, required int ga}) => Db.execute(
        "UPDATE matches SET status='finished', goals_for=@gf, goals_against=@ga WHERE id=@id",
        params: {'id': id, 'gf': gf, 'ga': ga},
      );

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM matches WHERE id=@id', params: {'id': id});

  /// Rekap W/D/L dari pertandingan selesai.
  static Future<List<int>> stats() async {
    final rows = await Db.query(
      '''SELECT count(*) FILTER (WHERE goals_for > goals_against)::int AS w,
                count(*) FILTER (WHERE goals_for = goals_against)::int AS d,
                count(*) FILTER (WHERE goals_for < goals_against)::int AS l,
                coalesce(sum(goals_for), 0)::int AS gf,
                coalesce(sum(goals_against), 0)::int AS ga
         FROM matches WHERE status='finished' ''',
    );
    final r = rows.first;
    return [r['w'] as int, r['d'] as int, r['l'] as int, r['gf'] as int, r['ga'] as int];
  }
}

// ---------- Match events ----------

class MatchEvent {
  final int id;
  final int matchId;
  final int? memberId;
  final String memberName;
  final int? minute;
  final String type;

  MatchEvent({
    required this.id,
    required this.matchId,
    this.memberId,
    required this.memberName,
    this.minute,
    required this.type,
  });

  factory MatchEvent.fromMap(Map<String, dynamic> m) => MatchEvent(
        id: m['id'] as int,
        matchId: m['match_id'] as int,
        memberId: m['member_id'] as int?,
        memberName: (m['member_name'] as String?) ?? '(mantan anggota)',
        minute: m['minute'] as int?,
        type: m['type'] as String,
      );

  static const typeLabels = {
    'goal': 'Gol',
    'assist': 'Assist',
    'yellow': 'Kartu Kuning',
    'red': 'Kartu Merah',
  };

  static Future<List<MatchEvent>> forMatch(int matchId) async {
    final rows = await Db.query(
      '''SELECT e.*, m.name AS member_name FROM match_events e
         LEFT JOIN members m ON m.id = e.member_id
         WHERE e.match_id = @mid ORDER BY e.minute NULLS LAST, e.id''',
      params: {'mid': matchId},
    );
    return rows.map(MatchEvent.fromMap).toList();
  }

  static Future<void> insert({
    required int matchId,
    int? memberId,
    int? minute,
    required String type,
  }) =>
      Db.execute(
        '''INSERT INTO match_events (match_id, member_id, minute, type)
           VALUES (@mid, @mem, @min, @type)''',
        params: {'mid': matchId, 'mem': memberId, 'min': minute, 'type': type},
      );

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM match_events WHERE id=@id', params: {'id': id});
}

// ---------- Payments ----------

class Payment {
  final int id;
  final int memberId;
  final String memberName;
  final double amount;
  final String period;
  final DateTime paidAt;
  final String? note;

  Payment({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.amount,
    required this.period,
    required this.paidAt,
    this.note,
  });

  factory Payment.fromMap(Map<String, dynamic> m) => Payment(
        id: m['id'] as int,
        memberId: m['member_id'] as int,
        memberName: (m['member_name'] as String?) ?? '',
        amount: _num(m['amount']),
        period: m['period'] as String,
        paidAt: _dt(m['paid_at']),
        note: m['note'] as String?,
      );

  static Future<List<Payment>> all({String? period}) async {
    final rows = await Db.query(
      '''SELECT p.*, m.name AS member_name FROM payments p
         JOIN members m ON m.id = p.member_id
         ${period != null ? 'WHERE p.period = @p' : ''}
         ORDER BY p.paid_at DESC''',
      params: period != null ? {'p': period} : const {},
    );
    return rows.map(Payment.fromMap).toList();
  }

  static Future<void> insert({
    required int memberId,
    required double amount,
    required String period,
    String? note,
  }) =>
      Db.execute(
        '''INSERT INTO payments (member_id, amount, period, note)
           VALUES (@mid, @amt, @period, @note)''',
        params: {'mid': memberId, 'amt': amount, 'period': period, 'note': note},
      );

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM payments WHERE id=@id', params: {'id': id});

  /// Total iuran per periode (yyyy-MM).
  static Future<double> totalForPeriod(String period) async {
    final rows = await Db.query(
      'SELECT coalesce(sum(amount), 0) AS total FROM payments WHERE period = @p',
      params: {'p': period},
    );
    return _num(rows.first['total']);
  }
}

// ---------- Bookings ----------

class Booking {
  final int id;
  final String title;
  final DateTime startsAt;
  final int durationMin;
  final double cost;
  final String status;

  Booking({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.durationMin,
    required this.cost,
    required this.status,
  });

  factory Booking.fromMap(Map<String, dynamic> m) => Booking(
        id: m['id'] as int,
        title: m['title'] as String,
        startsAt: _dt(m['starts_at']),
        durationMin: (m['duration_min'] as int?) ?? 90,
        cost: _num(m['cost']),
        status: (m['status'] as String?) ?? 'booked',
      );

  static const statusLabels = {'booked': 'Dipesan', 'done': 'Selesai', 'canceled': 'Batal'};

  static Future<List<Booking>> all() async {
    final rows = await Db.query('SELECT * FROM bookings ORDER BY starts_at DESC LIMIT 100');
    return rows.map(Booking.fromMap).toList();
  }

  static Future<List<Booking>> upcoming() async {
    final rows = await Db.query(
      "SELECT * FROM bookings WHERE status='booked' AND starts_at >= now() ORDER BY starts_at ASC LIMIT 5",
    );
    return rows.map(Booking.fromMap).toList();
  }

  static Future<void> insert({
    required String title,
    required DateTime startsAt,
    required int durationMin,
    required double cost,
  }) =>
      Db.execute(
        '''INSERT INTO bookings (title, starts_at, duration_min, cost)
           VALUES (@t, @s, @d, @c)''',
        params: {'t': title, 's': startsAt, 'd': durationMin, 'c': cost},
      );

  Future<void> setStatus(String s) =>
      Db.execute('UPDATE bookings SET status=@s WHERE id=@id', params: {'s': s, 'id': id});

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM bookings WHERE id=@id', params: {'id': id});
}

// ---------- Announcements ----------

class Announcement {
  final int id;
  final String title;
  final String body;
  final DateTime createdAt;

  Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory Announcement.fromMap(Map<String, dynamic> m) => Announcement(
        id: m['id'] as int,
        title: m['title'] as String,
        body: m['body'] as String,
        createdAt: _dt(m['created_at']),
      );

  static Future<List<Announcement>> all() async {
    final rows = await Db.query('SELECT * FROM announcements ORDER BY created_at DESC LIMIT 50');
    return rows.map(Announcement.fromMap).toList();
  }

  static Future<void> insert({required String title, required String body}) => Db.execute(
        'INSERT INTO announcements (title, body) VALUES (@t, @b)',
        params: {'t': title, 'b': body},
      );

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM announcements WHERE id=@id', params: {'id': id});
}

// ---------- Sessions (per-babak, ada pemenangnya) ----------

class MatchSession {
  final int id;
  final int matchId;
  final int sessionNo;
  final int scoreHome;
  final int scoreAway;
  final String winner; // home | away | draw

  MatchSession({
    required this.id,
    required this.matchId,
    required this.sessionNo,
    required this.scoreHome,
    required this.scoreAway,
    required this.winner,
  });

  factory MatchSession.fromMap(Map<String, dynamic> m) => MatchSession(
        id: m['id'] as int,
        matchId: m['match_id'] as int,
        sessionNo: (m['session_no'] as int?) ?? 1,
        scoreHome: (m['score_home'] as int?) ?? 0,
        scoreAway: (m['score_away'] as int?) ?? 0,
        winner: (m['winner'] as String?) ?? 'draw',
      );

  static const winnerLabels = {'home': 'Menang', 'away': 'Kalah', 'draw': 'Seri'};

  static Future<List<MatchSession>> forMatch(int matchId) async {
    final rows = await Db.query(
      'SELECT * FROM match_sessions WHERE match_id=@m ORDER BY session_no',
      params: {'m': matchId},
    );
    return rows.map(MatchSession.fromMap).toList();
  }

  /// Pemenang dihitung dari skor, bukan diinput manual.
  static Future<void> save({
    int? id,
    required int matchId,
    required int sessionNo,
    required int home,
    required int away,
  }) async {
    final winner = home > away ? 'home' : (away > home ? 'away' : 'draw');
    if (id == null) {
      await Db.execute(
        '''INSERT INTO match_sessions (match_id, session_no, score_home, score_away, winner, ended_at)
           VALUES (@m, @sn, @h, @a, @w, now())
           ON CONFLICT (match_id, session_no) DO UPDATE SET
             score_home=@h, score_away=@a, winner=@w, ended_at=now()''',
        params: {'m': matchId, 'sn': sessionNo, 'h': home, 'a': away, 'w': winner},
      );
    } else {
      await Db.execute(
        '''UPDATE match_sessions SET score_home=@h, score_away=@a, winner=@w, ended_at=now()
           WHERE id=@id''',
        params: {'id': id, 'h': home, 'a': away, 'w': winner},
      );
    }
    await _syncTotals(matchId);
  }

  static Future<void> delete(int id, int matchId) async {
    await Db.execute('DELETE FROM match_sessions WHERE id=@id', params: {'id': id});
    await _syncTotals(matchId);
  }

  /// Skor laga = jumlah semua sesi, biar ringkasan tetap konsisten.
  static Future<void> _syncTotals(int matchId) => Db.execute(
        '''UPDATE matches SET
             goals_for = COALESCE((SELECT sum(score_home) FROM match_sessions WHERE match_id=@m), 0),
             goals_against = COALESCE((SELECT sum(score_away) FROM match_sessions WHERE match_id=@m), 0),
             status = CASE WHEN status='scheduled' THEN 'ongoing' ELSE status END
           WHERE id=@m''',
        params: {'m': matchId},
      );
}

// ---------- Users ----------

class AppUser {
  final int id;
  final String username;
  final String role; // admin | treasurer | member
  final bool active;

  AppUser({required this.id, required this.username, required this.role, required this.active});

  factory AppUser.fromMap(Map<String, dynamic> m) => AppUser(
        id: m['id'] as int,
        username: m['username'] as String,
        role: (m['role'] as String?) ?? 'member',
        active: (m['active'] as bool?) ?? true,
      );

  static const roles = ['admin', 'treasurer', 'member'];

  static Future<List<AppUser>> all() async {
    final rows = await Db.query('SELECT * FROM users ORDER BY role, username');
    return rows.map(AppUser.fromMap).toList();
  }

  static Future<void> insert(String username, String role) => Db.execute(
        'INSERT INTO users (username, role) VALUES (@u, @r)',
        params: {'u': username.trim(), 'r': role},
      );

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM users WHERE id=@id', params: {'id': id});
}

DateTime _dt(dynamic v) =>
    v is DateTime ? v : DateTime.parse(v.toString()).toLocal();
  final String name;
  final int goals;
  final int assists;

  ScorerRow({required this.name, required this.goals, required this.assists});

  static Future<List<ScorerRow>> top() async {
    final rows = await Db.query(
      '''SELECT coalesce(m.name, '(mantan anggota)') AS name,
                count(*) FILTER (WHERE e.type='goal')::int   AS goals,
                count(*) FILTER (WHERE e.type='assist')::int AS assists
         FROM match_events e LEFT JOIN members m ON m.id = e.member_id
         GROUP BY 1 HAVING count(*) FILTER (WHERE e.type='goal') > 0
         ORDER BY goals DESC, assists DESC LIMIT 10''',
    );
    return rows
        .map((r) => ScorerRow(
              name: r['name'] as String,
              goals: r['goals'] as int,
              assists: r['assists'] as int,
            ))
        .toList();
  }
}

DateTime _dt(dynamic v) =>
    v is DateTime ? v : DateTime.parse(v.toString()).toLocal();

/// Neon mengembalikan NUMERIC sebagai String (biar presisi).
double _num(dynamic v) => switch (v) {
      null => 0,
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };
