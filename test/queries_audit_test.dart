// Merekam SQL asli yang dikirim SETIAP method di lib/data/models.dart.
//
// Kenapa begini, bukan menyalin query ke daftar manual? Salinan manual bisa
// berbeda dari yang benar-benar dikirim app (itu persis yang dulu terjadi:
// daftar tes lolos, produksi gagal). Di sini mock HTTP mencegat permintaan
// pada lapisan transport, jadi yang terekam adalah string final setelah
// interpolasi `_select`, `WHERE active`, dan sebagainya.
//
// Hasilnya ditulis ke `.audit/queries.json`, lalu `scripts/audit-queries.mjs`
// menjalankannya ke server sungguhan. Dua tahap dipisah supaya tes ini tetap
// bisa jalan tanpa jaringan.
//
//   flutter test test/queries_audit_test.dart
//   node scripts/audit-queries.mjs
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';
import 'package:minisoccer_club/data/models.dart';

/// Satu query yang terekam.
class Recorded {
  Recorded(this.label, this.sql, this.params);
  final String label;
  final String sql;
  final Map<String, dynamic> params;

  Map<String, dynamic> toJson() => {'label': label, 'sql': sql, 'params': params};
}

final recorded = <Recorded>[];
String _label = '?';

/// Jalankan [body] sambil merekam setiap permintaan SQL yang dikirim.
///
/// Kegagalan dari model diabaikan: yang diuji di sini adalah *query yang
/// dikirim*, bukan hasilnya. Mock membalas baris kosong, jadi method yang
/// memakai `rows.first` (countActive, stats, ...) memang akan melempar —
/// SQL-nya sudah terekam sebelum itu terjadi.
Future<void> capture(String label, Future<void> Function() body) async {
  _label = label;
  try {
    await body();
  } catch (_) {
    // diabaikan dengan sengaja
  }
}

/// Instance contoh untuk method non-static.
Member get _member => Member(
      id: 1,
      name: '_audit',
      phone: '0800',
      position: 'Bebas',
      jersey: 9,
      active: true,
      joinedAt: DateTime.utc(2026, 1, 1),
    );

Match get _match => Match(
      id: 1,
      playedAt: DateTime.utc(2026, 1, 1),
      venue: '_audit',
      status: 'scheduled',
      goalsFor: 0,
      goalsAgainst: 0,
      homeTeamId: 1,
      awayTeamId: 2,
    );

Transaction get _tx => Transaction(
      id: 1,
      kind: 'income',
      category: 'lain',
      amount: 1000,
      occurredAt: DateTime.utc(2026, 1, 1),
      note: '_audit',
    );

Booking get _booking => Booking(
      id: 1,
      title: '_audit',
      startsAt: DateTime.utc(2026, 1, 1),
      durationMin: 90,
      cost: 0,
      status: 'booked',
    );

Announcement get _ann => Announcement(
      id: 1,
      title: '_audit',
      body: '_audit',
      createdAt: DateTime.utc(2026, 1, 1),
    );

TournamentMatch get _tm => TournamentMatch(
      id: 1,
      tournamentId: 1,
      groupNo: 1,
      round: 1,
      slot: 1,
      homeTeamId: 1,
      awayTeamId: 2,
      kickoff: DateTime.utc(2026, 1, 1),
      scoreHome: null,
      scoreAway: null,
      status: 'scheduled',
    );

void main() {
  setUp(() {
    recorded.clear();
    useClient(MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      recorded.add(Recorded(
        _label,
        body['sql'] as String,
        (body['params'] as Map?)?.cast<String, dynamic>() ?? const {},
      ));
      // `INSERT ... RETURNING id` butuh baris berisi id, kalau tidak method
      // yang memakai `rows.first` berhenti sebelum mengirim query lanjutan
      // (mis. Booking.insert → INSERT transactions). Query lain cukup kosong.
      final sql = body['sql'] as String;
      final rows = RegExp(r'returning\s+id', caseSensitive: false).hasMatch(sql)
          ? '[{"id":1}]'
          : '[]';
      return http.Response('{"rows":$rows,"rowCount":${rows == '[]' ? 0 : 1}}', 200);
    }));
  });

  tearDown(() {
    useClient(http.Client());
    Db.authToken = null;
  });

  test('rekam semua query model', () async {
    // ---- Member ----
    await capture('Member.all', () => Member.all());
    await capture('Member.all(activeOnly)', () => Member.all(activeOnly: true));
    await capture('Member.insert', () => Member.insert(
          name: '_audit',
          phone: '0800',
          position: 'Bebas',
          jersey: 9,
        ));
    await capture('Member.update', () => _member.update(
          name: '_audit',
          phone: '0800',
          position: 'Bebas',
          jersey: 9,
          active: true,
        ));
    await capture('Member.delete', () => Member.delete(1));
    await capture('Member.countActive', () => Member.countActive());

    // ---- Match ----
    await capture('Match.all', () => Match.all());
    await capture('Match.all(limit)', () => Match.all(limit: 5));
    await capture('Match.byId', () => Match.byId(1));
    await capture('Match.upcoming', () => Match.upcoming());
    await capture('Match.recentFinished', () => Match.recentFinished());
    await capture('Match.forTeam', () => Match.forTeam(1));
    await capture('Match.insert', () => Match.insert(
          homeTeamId: 1,
          awayTeamId: 2,
          playedAt: DateTime.utc(2026, 1, 1),
          venue: '_audit',
        ));
    await capture('Match.update', () => _match.update(
          homeTeamId: 1,
          awayTeamId: 2,
          playedAt: DateTime.utc(2026, 1, 1),
          venue: '_audit',
        ));
    await capture('Match.start', () => _match.start());
    await capture('Match.finish', () => _match.finish(gf: 2, ga: 1));
    await capture('Match.reopen', () => _match.reopen());
    await capture('Match.delete', () => Match.delete(1));
    await capture('Match.stats', () => Match.stats());
    await capture('Match.statsForTeam', () => Match.statsForTeam(1));

    // ---- MatchEvent ----
    await capture('MatchEvent.forMatch', () => MatchEvent.forMatch(1));
    await capture('MatchEvent.insert', () => MatchEvent.insert(
          matchId: 1,
          memberId: 1,
          minute: 10,
          type: 'goal',
        ));
    await capture('MatchEvent.delete', () => MatchEvent.delete(1));

    // ---- Payment (iuran per turnamen) ----
    await capture('Payment.all', () => Payment.all());
    await capture('Payment.all(tournament)', () => Payment.all(tournamentId: 1));
    await capture('Payment.inMonth', () => Payment.inMonth(DateTime(2026, 10)));
    await capture('Payment.existsFor', () => Payment.existsFor(1, 1));
    await capture('Payment.insert', () => Payment.insert(
          memberId: 1,
          amount: 50000,
          tournamentId: 1,
          note: '_audit',
        ));
    await capture('Payment.delete', () => Payment.delete(1));
    await capture('Payment.bill', () => Payment.bill(1));
    await capture('Payment.collectedFor', () => Payment.collectedFor(1));
    await capture('Payment.usualAmountFor', () => Payment.usualAmountFor(1));

    // ---- Transaction ----
    await capture('Transaction.all', () => Transaction.all());
    await capture('Transaction.all(period)', () => Transaction.all(period: '2026-10'));
    await capture('Transaction.insert', () => Transaction.insert(
          kind: 'income',
          category: 'lain',
          amount: 1000,
          occurredAt: DateTime.utc(2026, 1, 1),
          note: '_audit',
        ));
    await capture('Transaction.update', () => _tx.update(
          kind: 'income',
          category: 'lain',
          amount: 1000,
          occurredAt: DateTime.utc(2026, 1, 1),
          note: '_audit',
        ));
    await capture('Transaction.delete', () => Transaction.delete(1));

    // ---- Booking ----
    await capture('Booking.all', () => Booking.all());
    await capture('Booking.upcoming', () => Booking.upcoming());
    await capture('Booking.insert', () => Booking.insert(
          title: '_audit',
          startsAt: DateTime.utc(2026, 1, 1),
          durationMin: 90,
          cost: 350000,
          postToCash: true,
        ));
    await capture('Booking.insert(no cash)', () => Booking.insert(
          title: '_audit',
          startsAt: DateTime.utc(2026, 1, 1),
          durationMin: 90,
          cost: 0,
          postToCash: false,
        ));
    await capture('Booking.setStatus', () => _booking.setStatus('done'));
    await capture('Booking.delete', () => Booking.delete(1));

    // ---- Announcement ----
    await capture('Announcement.all', () => Announcement.all());
    await capture('Announcement.insert', () => Announcement.insert(title: '_audit', body: '_audit'));
    await capture('Announcement.update', () => _ann.update(title: '_audit', body: '_audit'));
    await capture('Announcement.delete', () => Announcement.delete(1));

    // ---- MatchSession ----
    await capture('MatchSession.forMatch', () => MatchSession.forMatch(1));
    // Dua cabang: INSERT ... ON CONFLICT (id null) dan UPDATE (id terisi).
    await capture('MatchSession.save(insert)', () => MatchSession.save(
          matchId: 1,
          sessionNo: 1,
          home: 1,
          away: 0,
        ));
    await capture('MatchSession.save(update)', () => MatchSession.save(
          id: 1,
          matchId: 1,
          sessionNo: 1,
          home: 1,
          away: 0,
        ));
    await capture('MatchSession.delete', () => MatchSession.delete(1, 1));

    // ---- ScorerRow ----
    await capture('ScorerRow.top', () => ScorerRow.top());

    // ---- Tournament ----
    await capture('Tournament.all', () => Tournament.all());
    await capture('Tournament.create', () => Tournament.create(
          name: '_audit',
          venue: '_audit',
          startsAt: DateTime.utc(2026, 1, 1),
          teamIds: const [1, 2],
          matchMinutes: 20,
          breakMinutes: 0,
          groups: 1,
        ));
    await capture('Tournament.updateTeams', () => Tournament.updateTeams(
          1,
          const [1, 2],
          startsAt: DateTime.utc(2026, 1, 1),
          matchMinutes: 20,
          breakMinutes: 0,
          groups: 1,
        ));
    await capture('Tournament.syncStatus', () => Tournament.syncStatus(1));
    await capture('Tournament.delete', () => Tournament.delete(1));
    await capture('Tournament.standingsByGroup', () => Tournament.standingsByGroup(1));

    // ---- Team ----
    await capture('Team.all', () => Team.all());
    await capture('Team.forTournament', () => Team.forTournament(1));
    await capture('Team.players', () => Team.players());
    await capture('Team.players(tournament)', () => Team.players(tournamentId: 1));
    await capture('Team.insert', () => Team.insert('_audit'));
    await capture('Team.rename', () => Team.rename(1, '_audit'));
    await capture('Team.addPlayer', () => Team.addPlayer(1, 1));
    await capture('Team.removePlayer', () => Team.removePlayer(1, 1));
    await capture('Team.deletionImpact', () => Team.deletionImpact(1));
    await capture('Team.delete', () => Team.delete(1));
    await capture('Team.standings', () => Team.standings());

    // ---- TournamentMatch ----
    await capture('TournamentMatch.forTournament', () => TournamentMatch.forTournament(1));
    await capture('TournamentMatch.saveScore', () => _tm.saveScore(2, 1));
    await capture('TournamentMatch.clearScore', () => _tm.clearScore());

    // ---- tulis hasil ----
    expect(recorded, isNotEmpty, reason: 'tidak ada query terekam');
    final dir = Directory('.audit');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File('.audit/queries.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'count': recorded.length,
        'queries': recorded.map((r) => r.toJson()).toList(),
      }),
    );
    // ignore: avoid_print
    print('terekam ${recorded.length} query -> .audit/queries.json');
  });
}
