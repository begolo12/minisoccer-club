/// Model + query layer. Semua akses DB lewat sini.
library;

import '../core/db.dart';
import 'auth.dart';

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

// ---------- Matches (tanding internal antar tim klub) ----------

/// Satu laga internal: Tim A vs Tim B dari klub yang sama.
///
/// Skor disimpan di `goals_for` (tim home) dan `goals_against` (tim away)
/// supaya kompatibel dengan data lama, tapi UI selalu memakai nama tim.
class Match {
  final int id;
  final DateTime playedAt;
  final String? venue;
  final String status;
  final int goalsFor;
  final int goalsAgainst;
  final int? homeTeamId;
  final int? awayTeamId;
  final String homeName;
  final String awayName;

  Match({
    required this.id,
    required this.playedAt,
    this.venue,
    required this.status,
    required this.goalsFor,
    required this.goalsAgainst,
    this.homeTeamId,
    this.awayTeamId,
    this.homeName = 'Tim A',
    this.awayName = 'Tim B',
  });

  factory Match.fromMap(Map<String, dynamic> m) => Match(
        id: m['id'] as int,
        playedAt: _dt(m['played_at']),
        venue: m['venue'] as String?,
        status: (m['status'] as String?) ?? 'scheduled',
        goalsFor: (m['goals_for'] as int?) ?? 0,
        goalsAgainst: (m['goals_against'] as int?) ?? 0,
        homeTeamId: m['home_team_id'] as int?,
        awayTeamId: m['away_team_id'] as int?,
        homeName: (m['home_name'] as String?) ?? (m['opponent'] as String?) ?? 'Tim dihapus',
        awayName: (m['away_name'] as String?) ?? 'Tim dihapus',
      );

  bool get finished => status == 'finished';
  bool get ongoing => status == 'ongoing';

  /// Poin yang didapat pemenang: 3 menang, 1 seri. Null kalau belum selesai.
  /// Sisi pemenang tidak mengubah poin — laga yang dimenangkan tim away tetap
  /// 3, bukan 0 seperti kalau dihitung dari sudut pandang tim home.
  int? get pointsForWinner {
    if (!finished) return null;
    return goalsFor == goalsAgainst ? kPointsDraw : kPointsWin;
  }

  String get resultLabel => finished
      ? (goalsFor > goalsAgainst ? 'Menang' : (goalsFor == goalsAgainst ? 'Seri' : 'Kalah'))
      : (ongoing ? 'Berlangsung' : 'Belum main');

  /// Keterangan satu baris untuk daftar: "Tim A 3–1 Tim B".
  String get scoreline => finished || ongoing ? '$homeName $goalsFor–$goalsAgainst $awayName' : '$homeName vs $awayName';

  /// Gol yang dicetak [teamId] di laga ini. Di halaman tim, tim bisa menjadi
  /// tim away; membaca `goalsFor` langsung akan menukar menang dan kalah.
  int goalsForTeam(int teamId) => homeTeamId == teamId ? goalsFor : goalsAgainst;

  int goalsAgainstTeam(int teamId) => homeTeamId == teamId ? goalsAgainst : goalsFor;

  /// Laga internal selalu punya dua tim klub. Baris warisan schema v1 (dibuat
  /// sebelum tanding internal ada) hanya punya `opponent` teks dan KEDUA kolom
  /// timnya NULL; baris seperti itu tidak bisa dimainkan, diskor, atau masuk
  /// klasemen, jadi tidak ditampilkan sebagai "Tim dihapus" — itu terlihat
  /// seperti data rusak padahal hanya sisa versi lama.
  ///
  /// Laga yang salah satu timnya dihapus (hanya satu kolom NULL) tetap
  /// ditampilkan: hasilnya nyata dan masih dihitung di rekap, jadi
  /// menyembunyikannya justru membuat angka tidak bisa ditelusuri.
  /// `scripts/fix-data.mjs` menghapus baris v1 dari DB.
  static const _select = '''
    SELECT m.*, h.name AS home_name, a.name AS away_name
      FROM matches m
      LEFT JOIN teams h ON h.id = m.home_team_id
      LEFT JOIN teams a ON a.id = m.away_team_id
     WHERE NOT (m.home_team_id IS NULL AND m.away_team_id IS NULL)''';

  static Future<List<Match>> all({int limit = 100}) async {
    final rows = await Db.query(
      '$_select ORDER BY m.played_at DESC LIMIT @limit',
      params: {'limit': limit},
    );
    return rows.map(Match.fromMap).toList();
  }

  /// Satu laga terbaru dari DB. Dipakai detail laga supaya skor di header
  /// ikut berubah setelah sesi ditambah atau hasil dikoreksi.
  static Future<Match?> byId(int id) async {
    final rows = await Db.query('$_select AND m.id=@id', params: {'id': id});
    return rows.isEmpty ? null : Match.fromMap(rows.first);
  }

  /// Laga yang belum selesai. Laga `ongoing` selalu ikut — laga yang sudah
  /// berjalan lama bukan alasan untuk menghilangkannya dari beranda; laga
  /// terjadwal hanya yang belum lewat lebih dari 3 jam, supaya jadwal basi
  /// tidak menumpuk.
  static Future<List<Match>> upcoming() async {
    final rows = await Db.query(
      "$_select AND (m.status='ongoing' OR (m.status='scheduled' "
      "AND m.played_at >= now() - interval '3 hours')) "
      'ORDER BY m.played_at ASC LIMIT 5',
    );
    return rows.map(Match.fromMap).toList();
  }

  /// Hasil terakhir untuk ringkasan beranda.
  static Future<List<Match>> recentFinished({int limit = 4}) async {
    final rows = await Db.query(
      "$_select AND m.status='finished' ORDER BY m.played_at DESC LIMIT @limit",
      params: {'limit': limit},
    );
    return rows.map(Match.fromMap).toList();
  }

  /// Semua laga tim tertentu (untuk riwayat di halaman tim).
  static Future<List<Match>> forTeam(int teamId, {int limit = 20}) async {
    final rows = await Db.query(
      '$_select AND (m.home_team_id=@t OR m.away_team_id=@t) '
      'ORDER BY m.played_at DESC LIMIT @limit',
      params: {'t': teamId, 'limit': limit},
    );
    return rows.map(Match.fromMap).toList();
  }

  static Future<void> insert({
    required int homeTeamId,
    required int awayTeamId,
    required DateTime playedAt,
    String? venue,
  }) {
    if (homeTeamId == awayTeamId) {
      throw Exception('Tim tidak boleh bertemu dirinya sendiri');
    }
    return Db.execute(
      '''INSERT INTO matches (home_team_id, away_team_id, played_at, venue)
         VALUES (@h, @a, @t, @v)''',
      params: {'h': homeTeamId, 'a': awayTeamId, 't': playedAt, 'v': venue},
    );
  }

  /// Ubah jadwal laga (tim, tanggal, lokasi) tanpa menghapus hasilnya.
  /// Sebelumnya satu-satunya jalan memperbaiki jadwal salah adalah hapus +
  /// buat ulang, dan itu ikut membuang sesi serta catatan gol.
  ///
  /// Tim hanya boleh diganti selama laga belum selesai: skor dan sesi
  /// tersimpan per laga, jadi menukar tim setelah ada hasil berarti
  /// memindahkan kemenangan ke tim yang tidak pernah bermain.
  Future<void> update({
    required int homeTeamId,
    required int awayTeamId,
    required DateTime playedAt,
    String? venue,
  }) async {
    if (homeTeamId == awayTeamId) {
      throw Exception('Tim tidak boleh bertemu dirinya sendiri');
    }
    final rows = await Db.query(
      'SELECT status FROM matches WHERE id=@id',
      params: {'id': id},
    );
    if (rows.isEmpty) throw Exception('Laga tidak ditemukan');
    final status = rows.first['status'] as String?;
    final teamsChanged = homeTeamId != this.homeTeamId || awayTeamId != this.awayTeamId;
    if (status == 'finished' && teamsChanged) {
      throw Exception('Hasil sudah dikunci. Buka lagi laga sebelum mengganti tim.');
    }
    await Db.execute(
      '''UPDATE matches SET home_team_id=@h, away_team_id=@a,
           played_at=@t, venue=@v WHERE id=@id''',
      params: {'id': id, 'h': homeTeamId, 'a': awayTeamId, 't': playedAt, 'v': venue},
    );
  }

  /// Tandai laga sedang berjalan tanpa menunggu gol pertama. Papan skor di
  /// beranda hanya menampilkan laga `ongoing`, jadi tanpa ini laga yang baru
  /// dimulai (0–0) tidak bisa dilihat sebagai laga hidup.
  Future<void> start() => Db.execute(
        "UPDATE matches SET status='ongoing' WHERE id=@id AND status='scheduled'",
        params: {'id': id},
      );

  /// Kunci hasil laga. Kalau laga punya sesi, skor akhir = jumlah sesi: sesi
  /// adalah rincian babaknya, jadi angka dari dialog tidak boleh berbeda
  /// dengan rincian yang tersimpan. Tanpa sesi, angka dialog yang dipakai.
  Future<void> finish({required int gf, required int ga}) async {
    final sessions = await MatchSession.forMatch(id);
    final home = sessions.isEmpty ? gf : sessions.fold<int>(0, (s, e) => s + e.scoreHome);
    final away = sessions.isEmpty ? ga : sessions.fold<int>(0, (s, e) => s + e.scoreAway);
    await Db.execute(
      "UPDATE matches SET status='finished', goals_for=@gf, goals_against=@ga WHERE id=@id",
      params: {'id': id, 'gf': home, 'ga': away},
    );
  }

  /// Buka lagi laga yang sudah dikunci. Klasemen langsung kehilangan poinnya
  /// karena `v_team_standings` hanya menghitung status `finished`. Tanpa ini
  /// hasil yang salah tekan tidak bisa diperbaiki.
  Future<void> reopen() => Db.execute(
        '''UPDATE matches SET status = CASE
             WHEN EXISTS (SELECT 1 FROM match_sessions WHERE match_id=@id)
               THEN 'ongoing' ELSE 'scheduled' END
           WHERE id=@id''',
        params: {'id': id},
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

  /// Rekap satu tim dari SELURUH laga selesainya.
  ///
  /// Return [main, menang, seri, kalah, golMemasukkan, golKebobolan].
  ///
  /// Halaman detail tim dulu menghitung ini dari daftar riwayat yang dibatasi
  /// 20 baris, sehingga "Main" di sana bisa lebih kecil daripada di klasemen
  /// untuk tim yang sama. Angka tim harus datang dari agregat, bukan dari
  /// halaman pertama daftar.
  ///
  /// Gol dibaca dari sudut pandang tim: `goals_for` adalah gol tim home, jadi
  /// saat tim ini bermain sebagai away, golnya ada di `goals_against`.
  static Future<List<int>> statsForTeam(int teamId) async {
    final rows = await Db.query(
      '''SELECT count(*)::int AS played,
                count(*) FILTER (WHERE
                  (home_team_id=@t AND goals_for > goals_against) OR
                  (away_team_id=@t AND goals_against > goals_for))::int AS won,
                count(*) FILTER (WHERE goals_for = goals_against)::int AS drawn,
                count(*) FILTER (WHERE
                  (home_team_id=@t AND goals_for < goals_against) OR
                  (away_team_id=@t AND goals_against < goals_for))::int AS lost,
                coalesce(sum(CASE WHEN home_team_id=@t THEN goals_for
                                  ELSE goals_against END), 0)::int AS gf,
                coalesce(sum(CASE WHEN home_team_id=@t THEN goals_against
                                  ELSE goals_for END), 0)::int AS ga
         FROM matches
         WHERE status='finished' AND (home_team_id=@t OR away_team_id=@t)''',
      params: {'t': teamId},
    );
    final r = rows.first;
    return [
      _int(r['played']),
      _int(r['won']),
      _int(r['drawn']),
      _int(r['lost']),
      _int(r['gf']),
      _int(r['ga']),
    ];
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

  /// Sudah ada iuran untuk anggota + periode ini? Dipakai form supaya satu
  /// anggota tidak tercatat dua kali di bulan yang sama (uangnya ikut
  /// terhitung dua kali di kas dan di label "Lunas").
  static Future<bool> existsFor(int memberId, String period) async {
    final rows = await Db.query(
      'SELECT 1 AS ok FROM payments WHERE member_id=@mid AND period=@p LIMIT 1',
      params: {'mid': memberId, 'p': period},
    );
    return rows.isNotEmpty;
  }

  static Future<void> insert({
    required int memberId,
    required double amount,
    required String period,
    String? note,
  }) async {
    if (await existsFor(memberId, period)) {
      throw Exception('Iuran periode ini sudah dicatat. Hapus catatan lama dulu '
          'kalau nominalnya salah.');
    }
    await Db.execute(
      '''INSERT INTO payments (member_id, amount, period, note)
         VALUES (@mid, @amt, @period, @note)''',
      params: {'mid': memberId, 'amt': amount, 'period': period, 'note': note},
    );
  }

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM payments WHERE id=@id', params: {'id': id});

  /// Nominal iuran yang paling sering dibayar — dipakai sebagai isian awal
  /// form dan label tunggakan, supaya tidak ada angka iuran yang ditulis
  /// mati di UI.
  static Future<double?> standardAmount() async {
    final rows = await Db.query(
      '''SELECT amount, count(*)::int AS n FROM payments
         GROUP BY amount ORDER BY n DESC, amount DESC LIMIT 1''',
    );
    if (rows.isEmpty) return null;
    final v = _num(rows.first['amount']);
    return v > 0 ? v : null;
  }
}

// ---------- Transactions (kas klub) ----------

/// Satu arus kas di luar iuran anggota. Iuran tetap di tabel `payments`
/// karena butuh status per anggota; [mergeCashLedger] menggabungkan keduanya.
class Transaction {
  final int id;
  final String kind; // income | expense
  final String category;
  final double amount;
  final DateTime occurredAt;
  final String? note;

  /// Booking yang melahirkan pengeluaran ini, kalau ada.
  ///
  /// Sewa lapangan dicatat otomatis dari form Booking. Baris kas seperti ini
  /// TIDAK boleh dikoreksi atau dihapus dari halaman Kas: nominalnya harus
  /// sama dengan `bookings.cost`, kalau tidak "Total sewa" dan saldo kas
  /// menghitung angka berbeda untuk uang yang sama. Perubahannya lewat
  /// booking-nya (atau hapus booking → kas ikut terhapus lewat CASCADE).
  final int? bookingId;

  Transaction({
    required this.id,
    required this.kind,
    required this.category,
    required this.amount,
    required this.occurredAt,
    this.note,
    this.bookingId,
  });

  /// True kalau baris ini dikelola oleh booking, bukan dibuat manual.
  bool get fromBooking => bookingId != null;

  factory Transaction.fromMap(Map<String, dynamic> m) => Transaction(
        id: _int(m['id']),
        kind: (m['kind'] as String?) ?? 'expense',
        category: (m['category'] as String?) ?? 'lain',
        amount: _num(m['amount']),
        occurredAt: _dt(m['occurred_at']),
        note: m['note'] as String?,
        bookingId: m['booking_id'] == null ? null : _int(m['booking_id']),
      );

  static const incomeCategories = <String, String>{
    'sponsor': 'Sponsor',
    'sewa': 'Sewa lapangan',
    'lain': 'Lain-lain',
  };

  static const expenseCategories = <String, String>{
    'sewa': 'Sewa lapangan',
    'konsumsi': 'Konsumsi',
    'wasit': 'Wasit',
    'perlengkapan': 'Perlengkapan',
    'lain': 'Lain-lain',
  };

  static Map<String, String> categoriesFor(String kind) =>
      kind == 'income' ? incomeCategories : expenseCategories;

  bool get isIncome => kind == 'income';
  String get categoryLabel => categoriesFor(kind)[category] ?? category;

  static Future<List<Transaction>> all({String? period}) async {
    final rows = await Db.query(
      '''SELECT * FROM transactions
         ${period == null ? '' : "WHERE to_char(occurred_at, 'YYYY-MM') = @p"}
         ORDER BY occurred_at DESC, id DESC''',
      params: period == null ? const {} : {'p': period},
    );
    return rows.map(Transaction.fromMap).toList();
  }

  static Future<void> insert({
    required String kind,
    required String category,
    required double amount,
    required DateTime occurredAt,
    String? note,
  }) =>
      Db.execute(
        '''INSERT INTO transactions (kind, category, amount, occurred_at, note)
           VALUES (@kind, @category, @amount, @date, @note)''',
        params: {
          'kind': kind,
          'category': category,
          'amount': amount,
          'date': _dateOnly(occurredAt),
          'note': note,
        },
      );

  /// Koreksi transaksi kas. Hanya untuk catatan manual — baris iuran
  /// dikelola di halaman Iuran, dan baris sewa lapangan mengikuti booking.
  Future<void> update({
    required String kind,
    required String category,
    required double amount,
    required DateTime occurredAt,
    String? note,
  }) => Db.execute(
        '''UPDATE transactions SET kind=@kind, category=@category,
             amount=@amount, occurred_at=@date, note=@note WHERE id=@id''',
        params: {
          'id': id,
          'kind': kind,
          'category': category,
          'amount': amount,
          'date': _dateOnly(occurredAt),
          'note': note,
        },
      );

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM transactions WHERE id=@id', params: {'id': id});
}

/// Satu baris buku kas: iuran (dari `payments`) atau transaksi manual.
/// [amount] bertanda: masuk positif, keluar negatif.
class CashEntry {
  final DateTime date;
  final String label;
  final String detail;
  final double amount;
  final bool dues;
  final int? transactionId;

  CashEntry({
    required this.date,
    required this.label,
    required this.detail,
    required this.amount,
    this.dues = false,
    this.transactionId,
  });

  bool get isIncome => amount >= 0;
}

/// Gabungkan iuran + transaksi jadi satu buku kas, terbaru di atas.
List<CashEntry> mergeCashLedger({
  required List<Payment> payments,
  required List<Transaction> transactions,
}) {
  final entries = <CashEntry>[
    for (final p in payments)
      CashEntry(
        date: p.paidAt,
        label: 'Iuran',
        detail: p.memberName,
        amount: p.amount,
        dues: true,
      ),
    for (final t in transactions)
      CashEntry(
        date: t.occurredAt,
        label: t.categoryLabel,
        detail: t.note ?? '',
        amount: t.isIncome ? t.amount : -t.amount,
        transactionId: t.id,
      ),
  ];
  entries.sort((a, b) {
    final byDate = b.date.compareTo(a.date);
    if (byDate != 0) return byDate;
    return (b.transactionId ?? 0).compareTo(a.transactionId ?? 0);
  });
  return entries;
}

/// Ringkasan kas. Iuran dipisah supaya UI bisa menyebut asalnya.
class CashSummary {
  final double dues;
  final double otherIncome;
  final double expense;

  const CashSummary({
    required this.dues,
    required this.otherIncome,
    required this.expense,
  });

  factory CashSummary.fromEntries(Iterable<CashEntry> entries) {
    var dues = 0.0;
    var other = 0.0;
    var expense = 0.0;
    for (final e in entries) {
      if (e.dues) {
        dues += e.amount;
      } else if (e.amount >= 0) {
        other += e.amount;
      } else {
        expense += -e.amount;
      }
    }
    return CashSummary(dues: dues, otherIncome: other, expense: expense);
  }

  double get income => dues + otherIncome;
  double get balance => income - expense;
}

// ---------- Bookings ----------

class Booking {
  final int id;
  final String title;
  final DateTime startsAt;
  final int durationMin;
  final double cost;
  final String status;

  /// Id transaksi kas yang lahir dari booking ini, kalau biayanya sudah
  /// dicatat ke kas. Null = biaya belum masuk buku kas.
  final int? transactionId;

  Booking({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.durationMin,
    required this.cost,
    required this.status,
    this.transactionId,
  });

  factory Booking.fromMap(Map<String, dynamic> m) => Booking(
        id: m['id'] as int,
        title: m['title'] as String,
        startsAt: _dt(m['starts_at']),
        durationMin: (m['duration_min'] as int?) ?? 90,
        cost: _num(m['cost']),
        status: (m['status'] as String?) ?? 'booked',
        transactionId: m['transaction_id'] as int?,
      );

  static const statusLabels = {'booked': 'Dipesan', 'done': 'Selesai', 'canceled': 'Batal'};

  bool get inCash => transactionId != null;

  static Future<List<Booking>> all() async {
    // LEFT JOIN, bukan dua query: halaman Booking perlu tahu mana yang
    // biayanya sudah masuk kas tanpa memuat seluruh transaksi.
    final rows = await Db.query(
      '''SELECT b.*, t.id AS transaction_id FROM bookings b
         LEFT JOIN transactions t ON t.booking_id = b.id
         ORDER BY b.starts_at DESC LIMIT 100''',
    );
    return rows.map(Booking.fromMap).toList();
  }

  static Future<List<Booking>> upcoming() async {
    final rows = await Db.query(
      "SELECT * FROM bookings WHERE status='booked' AND starts_at >= now() ORDER BY starts_at ASC LIMIT 5",
    );
    return rows.map(Booking.fromMap).toList();
  }

  /// Simpan booking. [postToCash] mencatat biayanya sebagai pengeluaran
  /// "Sewa lapangan" di kas dengan `booking_id` — satu pengeluaran, satu
  /// catatan. Tanpa tautan ini "Total sewa" di halaman Booking dan saldo di
  /// Kas klub menghitung dua angka berbeda untuk uang yang sama.
  static Future<void> insert({
    required String title,
    required DateTime startsAt,
    required int durationMin,
    required double cost,
    bool postToCash = true,
  }) async {
    final rows = await Db.query(
      '''INSERT INTO bookings (title, starts_at, duration_min, cost)
         VALUES (@t, @s, @d, @c) RETURNING id''',
      params: {'t': title, 's': startsAt, 'd': durationMin, 'c': cost},
    );
    if (!postToCash || cost <= 0) return;
    final id = rows.first['id'] as int;
    await Db.execute(
      '''INSERT INTO transactions (kind, category, amount, occurred_at, note, booking_id)
         VALUES ('expense', 'sewa', @amount, @date, @note, @booking)''',
      params: {
        'amount': cost,
        'date': _dateOnly(startsAt),
        'note': title,
        'booking': id,
      },
    );
  }

  /// Ubah status booking. Membatalkan booking sekaligus membuang pengeluaran
  /// kas yang tertaut.
  ///
  /// Tanpa ini, "Total sewa" (yang mengabaikan booking batal) dan saldo Kas
  /// (yang masih memuat pengeluarannya) menampilkan angka berbeda untuk uang
  /// yang sama — dan baris kas itu tidak bisa dihapus dari halaman Kas karena
  /// memang milik booking. Booking yang dibatalkan berarti sewa tidak jadi
  /// dibayar, jadi catatan kasnya juga harus hilang.
  Future<void> setStatus(String s) async {
    await Db.execute('UPDATE bookings SET status=@s WHERE id=@id', params: {'s': s, 'id': id});
    if (s == 'canceled') {
      await Db.execute(
        'DELETE FROM transactions WHERE booking_id=@id',
        params: {'id': id},
      );
    }
  }

  /// Hapus booking; catatan kasnya ikut terhapus lewat `ON DELETE CASCADE`
  /// pada `transactions.booking_id`.
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

  /// Ubah judul/isi. Tanpa ini salah ketik berarti hapus lalu buat ulang —
  /// dan pengumuman lama yang sudah dibaca anggota ikut hilang.
  Future<void> update({required String title, required String body}) => Db.execute(
        'UPDATE announcements SET title=@t, body=@b WHERE id=@id',
        params: {'id': id, 't': title, 'b': body},
      );

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM announcements WHERE id=@id', params: {'id': id});
}

// ---------- Sessions (per-babak, ada pemenangnya) ----------

/// Pemenang satu sesi dari skor. Dipakai UI, DB, dan test.
String sessionWinner(int home, int away) =>
    home > away ? 'home' : (away > home ? 'away' : 'draw');

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
    final winner = sessionWinner(home, away);
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
  ///
  /// Tanpa sesi, skor dikosongkan lagi kecuali laga sudah selesai: laga yang
  /// kembali `scheduled` tidak boleh menyisakan skor 2–1 tanpa rincian, dan
  /// hasil yang sudah dikunci tidak boleh berubah jadi 0–0 hanya karena
  /// rincian sesinya dihapus.
  static Future<void> _syncTotals(int matchId) => Db.execute(
        '''UPDATE matches SET
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
    // Kolom eksplisit: password_hash tidak pernah dikirim ke klien.
    final rows = await Db.query('SELECT id, username, role, active FROM users ORDER BY role, username');
    return rows.map(AppUser.fromMap).toList();
  }

  static Future<void> insert(String username, String role, {String? password}) async {
    if (password == null || password.isEmpty) {
      throw Exception('Password wajib diisi');
    }
    await Auth.createUser(username, role, password);
  }

  /// Atur ulang password (dipakai admin kalau anggota lupa).
  static Future<void> setPassword(int id, String password) => Auth.resetPassword(id, password);

  static Future<void> delete(int id) => Auth.deleteUser(id);
}

// ---------- Top scorers ----------

class ScorerRow {
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

// ---------- Turnamen internal ----------
//
// Format: N tim (default 4) round-robin — semua bertemu semua sekali.
// 4 tim = 3 babak × 2 laga = 6 laga. Dengan 20 menit/laga, habis 120 menit.
// Poin: menang 3, seri 1, kalah 0.

const kPointsWin = 3;
const kPointsDraw = 1;

/// Jadwal round-robin metode lingkaran. Return (babak, timHome, timAway)
/// urut waktu main. Tim ganjil dapat bye (id -1) dan dilewati.
List<(int, int, int)> roundRobin(List<int> ids) {
  if (ids.length < 2) return const [];
  final t = [...ids];
  if (t.length.isOdd) t.add(-1);
  final n = t.length;
  final out = <(int, int, int)>[];
  for (var r = 0; r < n - 1; r++) {
    for (var i = 0; i < n ~/ 2; i++) {
      final a = t[i], b = t[n - 1 - i];
      if (a != -1 && b != -1) out.add((r + 1, a, b));
    }
    t.insert(1, t.removeLast());
  }
  return out;
}

class Tournament {
  final int id;
  final String name;
  final String? venue;
  final DateTime startsAt;
  final int matchMinutes;
  final int breakMinutes;
  final int groups;
  final String status; // draft | running | done

  Tournament({
    required this.id,
    required this.name,
    this.venue,
    required this.startsAt,
    required this.matchMinutes,
    required this.breakMinutes,
    required this.groups,
    required this.status,
  });

  factory Tournament.fromMap(Map<String, dynamic> m) => Tournament(
        id: m['id'] as int,
        name: m['name'] as String,
        venue: m['venue'] as String?,
        startsAt: _dt(m['starts_at']),
        matchMinutes: (m['match_minutes'] as int?) ?? 20,
        breakMinutes: (m['break_minutes'] as int?) ?? 0,
        groups: (m['groups'] as int?) ?? 1,
        status: (m['status'] as String?) ?? 'draft',
      );

  static const statusLabels = {'draft': 'Draft', 'running': 'Berjalan', 'done': 'Selesai'};

  static Future<List<Tournament>> all() async {
    final rows = await Db.query('SELECT * FROM tournaments ORDER BY starts_at DESC');
    final items = rows.map(Tournament.fromMap).toList();
    // Urut tanggal menaruh draft paling depan karena jadwalnya paling akhir.
    // Yang dicari saat membuka halaman: yang sedang berjalan dulu, lalu yang
    // akan datang (terdekat), lalu yang sudah selesai (terbaru).
    int rank(Tournament t) => switch (t.status) { 'running' => 0, 'draft' => 1, _ => 2 };
    items.sort((a, b) {
      final byStatus = rank(a).compareTo(rank(b));
      if (byStatus != 0) return byStatus;
      return a.status == 'done'
          ? b.startsAt.compareTo(a.startsAt)
          : a.startsAt.compareTo(b.startsAt);
    });
    return items;
  }

  /// Buat turnamen: pilih tim klub, bagi ke grup, lalu jadwalkan round-robin
  /// di dalam tiap grup. Tim yang belum punya cukup pemain tetap boleh ikut.
  static Future<int> create({
    required String name,
    String? venue,
    required DateTime startsAt,
    required List<int> teamIds,
    int matchMinutes = 20,
    int breakMinutes = 0,
    int groups = 1,
  }) async {
    // Satu angka untuk baris turnamen dan pembagian grup; kalau berbeda,
    // kolom `groups` bisa bilang 8 sementara jadwalnya dibuat untuk 3.
    final g = groups.clamp(1, 8);
    final rows = await Db.query(
      '''INSERT INTO tournaments (name, venue, starts_at, match_minutes, break_minutes, groups)
         VALUES (@n, @v, @s, @mm, @bm, @g) RETURNING id''',
      params: {
        'n': name,
        'v': venue,
        's': startsAt.toUtc(),
        'mm': matchMinutes,
        'bm': breakMinutes,
        'g': g,
      },
    );
    final id = rows.first['id'] as int;
    await assignGroups(id, teamIds, groups: g);
    await _schedule(id, startsAt, matchMinutes, breakMinutes);
    return id;
  }

  /// Ganti tim yang ikut turnamen lalu buat ulang jadwalnya.
  ///
  /// Ditolak kalau sudah ada laga berstatus `done`: skor tersimpan per slot,
  /// jadi jadwal baru akan menempelkan hasil lama ke pasangan tim yang
  /// berbeda. Turnamen yang masih kosong boleh diubah kapan saja.
  static Future<void> updateTeams(
    int id,
    List<int> teamIds, {
    required DateTime startsAt,
    required int matchMinutes,
    required int breakMinutes,
    int groups = 1,
  }) async {
    if (teamIds.length < 2) throw Exception('Pilih minimal 2 tim');
    final done = await Db.query(
      "SELECT count(*)::int AS n FROM tournament_matches "
      "WHERE tournament_id=@t AND status='done'",
      params: {'t': id},
    );
    if ((done.first['n'] as int) > 0) {
      throw Exception('Sudah ada laga dengan skor. Reset skornya dulu.');
    }
    final g = groups.clamp(1, 8);
    await Db.execute(
      'DELETE FROM tournament_matches WHERE tournament_id=@t',
      params: {'t': id},
    );
    await assignGroups(id, teamIds, groups: g);
    await Db.execute(
      'UPDATE tournaments SET groups=@g, match_minutes=@mm, break_minutes=@bm '
      'WHERE id=@t',
      params: {'t': id, 'g': g, 'mm': matchMinutes, 'bm': breakMinutes},
    );
    await _schedule(id, startsAt, matchMinutes, breakMinutes);
    await syncStatus(id);
  }

  /// Bagi tim ke grup (snake) lalu simpan ke `tournament_teams`.
  static Future<void> assignGroups(int id, List<int> teamIds, {int groups = 1}) async {
    if (teamIds.isEmpty) return;
    final g = groups.clamp(1, teamIds.length);
    await Db.execute(
      'DELETE FROM tournament_teams WHERE tournament_id=@t',
      params: {'t': id},
    );
    final vals = <String>[];
    final params = <String, Object?>{};
    for (var i = 0; i < teamIds.length; i++) {
      final round = i ~/ g;
      final idx = round.isEven ? i % g : g - 1 - (i % g);
      vals.add('(@t, @team$i, @g$i)');
      params['t'] = id;
      params['team$i'] = teamIds[i];
      params['g$i'] = idx + 1;
    }
    await Db.execute(
      'INSERT INTO tournament_teams (tournament_id, team_id, group_no) '
      'VALUES ${vals.join(',')} ON CONFLICT DO NOTHING',
      params: params,
    );
  }

  /// Jadwal round-robin per grup, urut waktu mulai.
  static Future<void> _schedule(
    int id,
    DateTime start,
    int minutes,
    int rest,
  ) async {
    final rows = await Db.query(
      'SELECT team_id, group_no FROM tournament_teams WHERE tournament_id=@t '
      'ORDER BY group_no, team_id',
      params: {'t': id},
    );
    final byGroup = <int, List<int>>{};
    for (final r in rows) {
      (byGroup[r['group_no'] as int] ??= []).add(r['team_id'] as int);
    }
    final vals = <String>[];
    final params = <String, Object?>{};
    var slot = 0;
    for (final entry in byGroup.entries) {
      for (final (round, home, away) in roundRobin(entry.value)) {
        vals.add('(@t$slot, @g$slot, @r$slot, @s$slot, @h$slot, @a$slot, @k$slot)');
        params['t$slot'] = id;
        params['g$slot'] = entry.key;
        params['r$slot'] = round;
        params['s$slot'] = slot + 1;
        params['h$slot'] = home;
        params['a$slot'] = away;
        params['k$slot'] = start.add(Duration(minutes: slot * (minutes + rest))).toUtc();
        slot++;
      }
    }
    if (vals.isEmpty) return;
    await Db.execute(
      '''INSERT INTO tournament_matches
           (tournament_id, group_no, round, slot, home_team_id, away_team_id, kickoff)
         VALUES ${vals.join(',')} ON CONFLICT DO NOTHING''',
      params: params,
    );
  }

  /// Status mengikuti hasil: draft sampai ada skor, berjalan selama masih ada
  /// laga kosong, selesai begitu semua laga terisi. Tanpa ini turnamen yang
  /// sudah habis tetap tertulis "Berjalan" selamanya.
  ///
  /// Turnamen tanpa laga sama sekali kembali ke draft — itu keadaan setelah
  /// timnya dihapus dan `ON DELETE CASCADE` membuang seluruh jadwalnya.
  static Future<void> syncStatus(int id) => Db.execute(
        '''UPDATE tournaments SET status = CASE
             WHEN EXISTS (SELECT 1 FROM tournament_matches
                          WHERE tournament_id=@t AND status <> 'done')
               THEN CASE WHEN EXISTS (SELECT 1 FROM tournament_matches
                                       WHERE tournament_id=@t AND status='done')
                         THEN 'running' ELSE 'draft' END
             WHEN EXISTS (SELECT 1 FROM tournament_matches WHERE tournament_id=@t)
               THEN 'done'
             ELSE 'draft' END
           WHERE id=@t''',
        params: {'t': id},
      );

  static Future<void> delete(int id) =>
      Db.execute('DELETE FROM tournaments WHERE id=@id', params: {'id': id});

  /// Klasemen turnamen, dikelompokkan per grup.
  static Future<Map<int, List<Standing>>> standingsByGroup(int id) async {
    final teams = await Team.forTournament(id);
    final matches = await TournamentMatch.forTournament(id);
    final out = <int, List<Standing>>{};
    for (final group in teams.map((t) => t.groupNo).toSet()) {
      final groupTeams = teams.where((t) => t.groupNo == group).toList();
      final groupMatches = matches.where((m) => m.groupNo == group).toList();
      out[group] = Standing.compute(groupTeams, groupMatches);
    }
    return out;
  }
}

/// Tim klub. 7-8 pemain per tim, dipakai di semua tanding dan turnamen.
class Team {
  final int id;
  final String name;

  /// Hanya terisi saat tim dibaca lewat konteks turnamen.
  final int groupNo;

  Team({required this.id, required this.name, this.groupNo = 1});

  factory Team.fromMap(Map<String, dynamic> m) => Team(
        id: m['id'] as int,
        name: m['name'] as String,
        groupNo: (m['group_no'] as int?) ?? 1,
      );

  static Future<List<Team>> all() async {
    final rows = await Db.query('SELECT * FROM teams ORDER BY name');
    return rows.map(Team.fromMap).toList();
  }

  /// Tim yang ikut satu turnamen, lengkap dengan nomor grupnya.
  static Future<List<Team>> forTournament(int id) async {
    final rows = await Db.query(
      '''SELECT t.*, tt.group_no FROM tournament_teams tt
         JOIN teams t ON t.id = tt.team_id
         WHERE tt.tournament_id=@t ORDER BY tt.group_no, t.name''',
      params: {'t': id},
    );
    return rows.map(Team.fromMap).toList();
  }

  /// Pemain per tim: {teamId: [Member...]}.
  static Future<Map<int, List<Member>>> players({int? tournamentId}) async {
    final rows = await Db.query(
      '''SELECT tp.team_id, m.* FROM team_players tp
         JOIN members m ON m.id = tp.member_id
         ${tournamentId == null ? '' : 'JOIN tournament_teams tt ON tt.team_id = tp.team_id'}
         ${tournamentId == null ? '' : 'WHERE tt.tournament_id=@t'}
         ORDER BY m.name''',
      params: tournamentId == null ? const {} : {'t': tournamentId},
    );
    final out = <int, List<Member>>{};
    for (final r in rows) {
      (out[r['team_id'] as int] ??= []).add(Member.fromMap(r));
    }
    return out;
  }

  static Future<int> insert(String name) async {
    final rows = await Db.query(
      'INSERT INTO teams (name) VALUES (@n) RETURNING id',
      params: {'n': name},
    );
    return rows.first['id'] as int;
  }

  static Future<void> rename(int id, String name) => Db.execute(
        'UPDATE teams SET name=@n WHERE id=@id',
        params: {'id': id, 'n': name},
      );

  static Future<void> addPlayer(int teamId, int memberId) => Db.execute(
        'INSERT INTO team_players (team_id, member_id) VALUES (@t, @m) ON CONFLICT DO NOTHING',
        params: {'t': teamId, 'm': memberId},
      );

  static Future<void> removePlayer(int teamId, int memberId) => Db.execute(
        'DELETE FROM team_players WHERE team_id=@t AND member_id=@m',
        params: {'t': teamId, 'm': memberId},
      );

  /// Dampak hapus tim. Laga internal tetap ada tanpa nama (`ON DELETE SET
  /// NULL`), tapi laga turnamen ikut terhapus (`ON DELETE CASCADE`) dan
  /// klasemen turnamen berubah — pemanggil perlu menyebut angka ini, bukan
  /// menulis "riwayat tetap ada" untuk keduanya.
  static Future<(int, int)> deletionImpact(int id) async {
    final rows = await Db.query(
      '''SELECT (SELECT count(*)::int FROM matches
                WHERE home_team_id=@id OR away_team_id=@id) AS internal,
              (SELECT count(*)::int FROM tournament_matches
                WHERE home_team_id=@id OR away_team_id=@id) AS tournament''',
      params: {'id': id},
    );
    final r = rows.first;
    return (r['internal'] as int, r['tournament'] as int);
  }

  /// Hapus tim beserta jadwal turnamennya (`ON DELETE CASCADE`). Status
  /// turnamen yang kehilangan laga harus dihitung ulang: tanpa ini turnamen
  /// bisa tetap tertulis "Berjalan" padahal semua laganya sudah ikut hilang.
  static Future<void> delete(int id) async {
    final rows = await Db.query(
      '''SELECT DISTINCT tournament_id FROM tournament_matches
         WHERE home_team_id=@id OR away_team_id=@id''',
      params: {'id': id},
    );
    final affected = rows.map((r) => r['tournament_id'] as int).toList();
    await Db.execute('DELETE FROM teams WHERE id=@id', params: {'id': id});
    for (final t in affected) {
      await Tournament.syncStatus(t);
    }
  }

  /// Klasemen abadi semua tim dari laga internal yang selesai.
  ///
  /// Semua kolom angka di `v_team_standings` bertipe **bigint** (hasil
  /// `COUNT`), dan driver Neon mengirim bigint sebagai String supaya angka
  /// besar tidak kehilangan presisi. Membacanya dengan `as int` melempar
  /// "type 'String' is not a subtype of type 'int'" — itu mematikan klasemen
  /// begitu ada satu laga selesai. Pakai `_int()` yang menerima keduanya.
  static Future<List<Standing>> standings() async {
    final rows = await Db.query(
      '''SELECT * FROM v_team_standings
         ORDER BY points DESC, (goals_for - goals_against) DESC, goals_for DESC, name''',
    );
    return rows
        .map((r) => Standing(_int(r['team_id']), r['name'] as String)
          ..played = _int(r['played'])
          ..won = _int(r['won'])
          ..drawn = _int(r['drawn'])
          ..lost = _int(r['lost'])
          ..goalsFor = _int(r['goals_for'])
          ..goalsAgainst = _int(r['goals_against']))
        .toList();
  }
}

class TournamentMatch {
  final int id;
  final int tournamentId;
  final int groupNo;
  final int round;
  final int slot;
  final int homeTeamId;
  final int awayTeamId;
  final DateTime kickoff;
  final int? scoreHome;
  final int? scoreAway;
  final String status; // scheduled | done

  TournamentMatch({
    required this.id,
    required this.tournamentId,
    this.groupNo = 1,
    required this.round,
    required this.slot,
    required this.homeTeamId,
    required this.awayTeamId,
    required this.kickoff,
    this.scoreHome,
    this.scoreAway,
    required this.status,
  });

  factory TournamentMatch.fromMap(Map<String, dynamic> m) => TournamentMatch(
        id: m['id'] as int,
        tournamentId: m['tournament_id'] as int,
        groupNo: (m['group_no'] as int?) ?? 1,
        round: (m['round'] as int?) ?? 1,
        slot: (m['slot'] as int?) ?? 1,
        homeTeamId: m['home_team_id'] as int,
        awayTeamId: m['away_team_id'] as int,
        kickoff: _dt(m['kickoff']),
        scoreHome: m['score_home'] as int?,
        scoreAway: m['score_away'] as int?,
        status: (m['status'] as String?) ?? 'scheduled',
      );

  bool get done => status == 'done' && scoreHome != null && scoreAway != null;

  static Future<List<TournamentMatch>> forTournament(int id) async {
    final rows = await Db.query(
      'SELECT * FROM tournament_matches WHERE tournament_id=@t ORDER BY slot',
      params: {'t': id},
    );
    return rows.map(TournamentMatch.fromMap).toList();
  }

  Future<void> saveScore(int home, int away) async {
    await Db.execute(
      '''UPDATE tournament_matches SET score_home=@h, score_away=@a, status='done'
         WHERE id=@id''',
      params: {'id': id, 'h': home, 'a': away},
    );
    await Tournament.syncStatus(tournamentId);
  }

  Future<void> clearScore() async {
    await Db.execute(
      '''UPDATE tournament_matches SET score_home=NULL, score_away=NULL,
         status='scheduled' WHERE id=@id''',
      params: {'id': id},
    );
    await Tournament.syncStatus(tournamentId);
  }
}

class Standing {
  final int teamId;
  final String name;
  int played = 0, won = 0, drawn = 0, lost = 0, goalsFor = 0, goalsAgainst = 0;

  Standing(this.teamId, this.name);

  int get goalDiff => goalsFor - goalsAgainst;
  int get points => won * kPointsWin + drawn * kPointsDraw;

  /// Klasemen dari daftar laga. Dipisah dari DB biar gampang dites.
  /// Hanya laga berstatus `done` yang dihitung, sama seperti `v_standings`:
  /// skor tanpa status selesai (data lama) tidak boleh menaikkan poin.
  static List<Standing> compute(List<Team> teams, List<TournamentMatch> matches) {
    final map = {for (final t in teams) t.id: Standing(t.id, t.name)};
    for (final m in matches) {
      if (!m.done) continue;
      final h = map[m.homeTeamId], a = map[m.awayTeamId];
      final hs = m.scoreHome, aw = m.scoreAway;
      if (h == null || a == null || hs == null || aw == null) continue;
      h.played++;
      a.played++;
      h.goalsFor += hs;
      h.goalsAgainst += aw;
      a.goalsFor += aw;
      a.goalsAgainst += hs;
      if (hs > aw) {
        h.won++;
        a.lost++;
      } else if (hs < aw) {
        a.won++;
        h.lost++;
      } else {
        h.drawn++;
        a.drawn++;
      }
    }
    return map.values.toList()
      ..sort((x, y) {
        final p = y.points.compareTo(x.points);
        if (p != 0) return p;
        final g = y.goalDiff.compareTo(x.goalDiff);
        if (g != 0) return g;
        final f = y.goalsFor.compareTo(x.goalsFor);
        if (f != 0) return f;
        return x.name.compareTo(y.name);
      });
  }
}

/// Kolom DATE dikirim sebagai string, bukan ISO timestamp.
String _dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Neon mengembalikan NUMERIC sebagai String (biar presisi).
double _num(dynamic v) => switch (v) {
      null => 0,
      num n => n.toDouble(),
      String s => double.tryParse(s) ?? 0,
      _ => 0,
    };

/// Bilangan bulat dari DB.
///
/// Tiga bentuk bisa datang untuk kolom yang sama, tergantung tipenya:
/// `int` untuk `integer`, **String** untuk `bigint` (COUNT/SUM — driver
/// mengirimnya sebagai string agar presisi tidak hilang) dan untuk NUMERIC,
/// serta `double` kalau ada yang sudah dikonversi. `as int` hanya aman untuk
/// bentuk pertama, jadi semua pembacaan angka bulat lewat sini.
int _int(dynamic v) => switch (v) {
      null => 0,
      int n => n,
      num n => n.toInt(),
      String s => int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? 0,
      _ => 0,
    };

