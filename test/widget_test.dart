import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/data/models.dart';
import 'dart:io';

import 'package:minisoccer_club/core/db_web.dart' show ApiException;
import 'package:minisoccer_club/core/cache.dart';
import 'package:minisoccer_club/core/soft.dart';
import 'package:minisoccer_club/core/version.dart';
import 'package:minisoccer_club/ui/fmt.dart';
import 'package:minisoccer_club/ui/tournament.dart';

void main() {
  test('format uang & periode', () {
    expect(fmtMoney(100000), 'Rp 100.000');
    expect(fmtMoney(0), 'Rp 0');
    expect(fmtMoney(-350000), '-Rp 350.000');
    expect(fmtNumber(-1500), '-1.500');
    expect(periodLabel('2026-03'), 'Maret 2026');
    expect(periodLabel('bad'), 'bad');
    expect(fmtDate(DateTime(2026, 1, 5)), '5 Jan 2026');
    expect(fmtShortDate(DateTime(2026, 10, 21)), '21 Okt');
  });

  test('nominal ringkas untuk label sempit', () {
    expect(fmtShortMoney(75000), 'Rp 75 rb');
    expect(fmtShortMoney(1950000), 'Rp 1,95 jt');
    expect(fmtShortMoney(2500000000), 'Rp 2,50 M');
    expect(fmtShortMoney(7500), 'Rp 7.500');
    expect(fmtShortMoney(-350000), '-Rp 350 rb');
  });

  test('fmtShortMoney tidak melewati ambang satuan', () {
    // Regresi: 999.999 dulu jadi "Rp 1000 rb" dan 999.999.999 jadi
    // "Rp 1000,00 jt" — angka benar tapi satuannya salah, dan "1000 rb"
    // terbaca seperti nominal berbeda.
    expect(fmtShortMoney(999999), 'Rp 1,00 jt');
    expect(fmtShortMoney(999999999), 'Rp 1,00 M');
    expect(fmtShortMoney(999499), 'Rp 999 rb');
    expect(fmtShortMoney(9999), 'Rp 10 rb');
    expect(fmtShortMoney(9499), 'Rp 9.499');
  });

  test('poin baris laga dari sudut pandang tim, bukan poin pemenang', () {
    // Regresi: baris tim yang KALAH dulu berbunyi "KALAH · 3 POIN" karena
    // memakai `pointsForWinner` (selalu 3 untuk laga selesai).
    final menang = Match(
      id: 1, playedAt: DateTime(2026, 1, 1), status: 'finished',
      goalsFor: 3, goalsAgainst: 1, homeTeamId: 1, awayTeamId: 2,
      homeName: 'Tim A', awayName: 'Tim B',
    );
    expect(menang.pointsForWinner, kPointsWin);

    // Tim away yang menang: golnya ada di goals_against.
    final awayMenang = Match(
      id: 2, playedAt: DateTime(2026, 1, 1), status: 'finished',
      goalsFor: 1, goalsAgainst: 3, homeTeamId: 1, awayTeamId: 2,
      homeName: 'Tim A', awayName: 'Tim B',
    );
    expect(awayMenang.goalsForTeam(2), 3, reason: 'tim away mencetak 3');
    expect(awayMenang.goalsAgainstTeam(2), 1);
    expect(awayMenang.goalsForTeam(1), 1, reason: 'tim home mencetak 1');

    // Seri: kedua tim dapat 1 poin.
    final seri = Match(
      id: 3, playedAt: DateTime(2026, 1, 1), status: 'finished',
      goalsFor: 2, goalsAgainst: 2, homeTeamId: 1, awayTeamId: 2,
    );
    expect(seri.pointsForWinner, kPointsDraw);
  });

  test('parseMoney: gaya Indonesia dan gaya lain', () {
    // Gaya Indonesia: titik ribuan, koma desimal.
    expect(parseMoney('1.500.000'), 1500000);
    expect(parseMoney('1500000'), 1500000);
    expect(parseMoney('1.500'), 1500, reason: 'kebiasaan Indonesia: 1.500 = seribu lima ratus');
    expect(parseMoney('1.500,50'), 1500.5);
    expect(parseMoney('100000,50'), 100000.5);

    // Regresi: "100000.50" dulu dibaca 10000050 (100x lebih besar) karena
    // semua titik dibuang lebih dulu. Titik di sini desimal, bukan ribuan.
    expect(parseMoney('100000.50'), 100000.5);
    expect(parseMoney('12.75'), 12.75);

    // Titik + koma: yang paling kanan adalah desimal.
    expect(parseMoney('1.234.567,89'), 1234567.89);

    // Boleh ada spasi/awalan Rp dan tanda minus.
    expect(parseMoney(' Rp 25.000 '), 25000);
    expect(parseMoney('-5000'), -5000);

    // Input tak terbaca harus null (pemanggil menampilkan pesan), bukan 0
    // yang diam-diam tersimpan.
    expect(parseMoney(''), isNull);
    expect(parseMoney('abc'), isNull);
    expect(parseMoney('12abc'), isNull);
    expect(parseMoney('1,2,3'), isNull, reason: 'pemisah ganda ambigu');
    expect(parseMoney('-'), isNull);
  });

  test('pemenang sesi dari skor', () {
    expect(sessionWinner(2, 1), 'home');
    expect(sessionWinner(0, 3), 'away');
    expect(sessionWinner(1, 1), 'draw');
  });

  test('round-robin 4 tim = 6 laga, semua pasangan sekali', () {
    final f = roundRobin([1, 2, 3, 4]);
    expect(f.length, 6);
    final pairs = f.map((e) => '${e.$2}-${e.$3}').toSet();
    expect(pairs.length, 6);
    for (final (_, h, a) in f) {
      expect(h, isNot(a));
    }
    // Tiap tim main 3 kali.
    for (final id in [1, 2, 3, 4]) {
      expect(f.where((e) => e.$2 == id || e.$3 == id).length, 3);
    }
  });

  test('klasemen: menang 3, seri 1, kalah 0 + GM/GK', () {
    final teams = [
      Team(id: 1, name: 'A'),
      Team(id: 2, name: 'B'),
    ];
    final matches = [
      TournamentMatch(
        id: 1, tournamentId: 1, round: 1, slot: 1,
        homeTeamId: 1, awayTeamId: 2, kickoff: DateTime(2026),
        scoreHome: 3, scoreAway: 1, status: 'done',
      ),
      TournamentMatch(
        id: 2, tournamentId: 1, round: 2, slot: 2,
        homeTeamId: 2, awayTeamId: 1, kickoff: DateTime(2026),
        scoreHome: 0, scoreAway: 0, status: 'done',
      ),
    ];
    final s = Standing.compute(teams, matches);
    expect(s.first.name, 'A');
    expect(s.first.points, 4); // menang 3 + seri 1
    expect(s.first.goalsFor, 3);
    expect(s.first.goalsAgainst, 1);
    expect(s.first.goalDiff, 2);
    expect(s.last.points, 1);
    expect(s.last.goalsFor, 1);
    expect(s.last.goalsAgainst, 3);
  });

  test('buku kas: iuran + transaksi, saldo dan urutan', () {
    final payments = [
      Payment(
        id: 1,
        memberId: 1,
        memberName: 'Rizky',
        amount: 75000,
        tournamentId: 1,
        tournamentName: 'Turnamen Internal',
        paidAt: DateTime(2026, 10, 5),
      ),
      Payment(
        id: 2,
        memberId: 2,
        memberName: 'Bagas',
        amount: 75000,
        tournamentId: 1,
        tournamentName: 'Turnamen Internal',
        paidAt: DateTime(2026, 10, 6),
      ),
    ];
    final txs = [
      Transaction(
        id: 1,
        kind: 'expense',
        category: 'sewa',
        amount: 350000,
        occurredAt: DateTime(2026, 10, 7),
        note: 'Sewa lapangan',
      ),
      Transaction(
        id: 2,
        kind: 'income',
        category: 'sponsor',
        amount: 500000,
        occurredAt: DateTime(2026, 10, 8),
        note: 'Sponsor',
      ),
    ];

    final entries = mergeCashLedger(payments: payments, transactions: txs);
    expect(entries.length, 4);
    expect(entries.first.label, 'Sponsor'); // terbaru di atas
    expect(entries.first.amount, 500000);
    expect(entries[1].amount, -350000);
    expect(entries.last.date, DateTime(2026, 10, 5));

    final s = CashSummary.fromEntries(entries);
    expect(s.dues, 150000);
    expect(s.otherIncome, 500000);
    expect(s.expense, 350000);
    expect(s.income, 650000);
    expect(s.balance, 300000);
  });

  test('poin untuk pemenang tidak bergantung sisi home/away', () {
    Match m(int gf, int ga, {String status = 'finished'}) => Match(
          id: 1,
          playedAt: DateTime(2026, 10, 21),
          status: status,
          goalsFor: gf,
          goalsAgainst: ga,
        );
    expect(m(2, 1).pointsForWinner, 3);
    expect(m(1, 2).pointsForWinner, 3, reason: 'menang di kandang lawan tetap 3');
    expect(m(1, 1).pointsForWinner, 1);
    expect(m(0, 0, status: 'ongoing').pointsForWinner, isNull);
  });

  test('skor dari sudut pandang tim, bukan hanya tim home', () {
    final m = Match(
      id: 1,
      playedAt: DateTime(2026, 10, 21),
      status: 'finished',
      goalsFor: 1,
      goalsAgainst: 4,
      homeTeamId: 1,
      awayTeamId: 4,
    );
    expect(m.goalsForTeam(1), 1);
    expect(m.goalsAgainstTeam(1), 4);
    expect(m.goalsForTeam(4), 4, reason: 'tim away mencetak 4');
    expect(m.goalsAgainstTeam(4), 1);
  });

  test('klasemen turnamen mengabaikan skor tanpa status done', () {
    final teams = [Team(id: 1, name: 'A'), Team(id: 2, name: 'B')];
    final matches = [
      TournamentMatch(
        id: 1, tournamentId: 1, round: 1, slot: 1,
        homeTeamId: 1, awayTeamId: 2, kickoff: DateTime(2026),
        scoreHome: 3, scoreAway: 0, status: 'done',
      ),
      // Skor ada tetapi status belum selesai: data lama seperti ini tidak
      // boleh menambah poin, karena UI pun menampilkannya sebagai "vs".
      TournamentMatch(
        id: 2, tournamentId: 1, round: 2, slot: 2,
        homeTeamId: 2, awayTeamId: 1, kickoff: DateTime(2026),
        scoreHome: 5, scoreAway: 0, status: 'scheduled',
      ),
    ];
    final s = Standing.compute(teams, matches);
    expect(s.first.name, 'A');
    expect(s.first.points, 3);
    expect(s.first.played, 1);
    expect(s.last.points, 0);
    expect(s.last.played, 1);
    expect(s.last.goalsFor, 0, reason: 'skor laga non-done tidak dihitung');
  });

  test('round-robin per grup: 5 tim / 2 grup = 3+2 tim, 4 laga', () {
    // `assignGroups` memakai snake, jadi grup tidak selalu sama besar.
    final groups = <int, List<int>>{1: [1, 2, 3], 2: [4, 5]};
    final total = groups.values.fold<int>(0, (s, ids) => s + roundRobin(ids).length);
    expect(total, 4, reason: '3 tim = 3 laga, 2 tim = 1 laga');
    expect(roundRobin([4, 5]).length, 1);
    expect(roundRobin([1]).length, 0, reason: 'grup 1 tim tidak punya laga');
  });

  test('soft() memakai fallback saat gagal, tidak meninggalkan null', () async {
    // Regresi produksi: `v_team_standings` gagal di server, `soft` dulu
    // mengembalikan value null, lalu `standings.value!` melempar
    // "Null check operator used on a null value" dan mematikan beranda.
    final failed = await soft<int>(
      'Klasemen',
      () async => throw Exception('permission denied'),
      fallback: 0,
    );
    expect(failed.ok, isFalse);
    expect(failed.value, 0, reason: 'fallback harus dipakai');
    expect(failed.value, isNotNull);

    final ok = await soft<int>('X', () async => 7, fallback: 0);
    expect(ok.ok, isTrue);
    expect(ok.value, 7);
    expect(ok.error, isNull);
  });

  test('settle(): sebagian gagal tetap tampil, semua gagal jadi layar error', () async {
    // Halaman memakai `settle` untuk memutuskan: sebagian sumber gagal →
    // tampilkan sisanya + DegradedNotice; semua gagal → layar error penuh
    // dengan tombol coba lagi (bukan halaman kosong yang terlihat "belum ada
    // data"). Dua perilaku itu yang diuji di sini.
    final partial = await Future.wait<Soft<Object?>>([
      soft('Laga', () async => const <int>[1], fallback: const <int>[]),
      soft('Klasemen', () async => throw Exception('Query gagal dijalankan'), fallback: const <int>[]),
    ]);
    final failures = settle(partial);
    expect(failures, hasLength(1));
    expect(failures.first, contains('Klasemen'));
    expect(failures.first, contains('Query gagal dijalankan'));
    expect(partial[0].value, const <int>[1], reason: 'sumber yang berhasil tetap dipakai');

    final allFailed = await Future.wait<Soft<Object?>>([
      soft('Laga', () async => throw Exception('offline'), fallback: const <int>[]),
      soft('Klasemen', () async => throw Exception('offline'), fallback: const <int>[]),
    ]);
    expect(() => settle(allFailed), throwsException);
  });

  test('failuresOf(): satu baris per sumber, format "Label: pesan"', () async {
    final items = await Future.wait<Soft<Object?>>([
      soft('A', () async => 1, fallback: 0),
      soft('B', () async => throw Exception('rusak'), fallback: 0),
      soft('C', () async => throw Exception('putus'), fallback: 0),
    ]);
    expect(failuresOf(items), ['B: rusak', 'C: putus']);
  });

  test('cache offline: kunci berbeda per parameter', () {
    final a = cacheKey('SELECT * FROM matches WHERE id=@id', {'id': 1});
    final b = cacheKey('SELECT * FROM matches WHERE id=@id', {'id': 2});
    final c = cacheKey('SELECT  *  FROM matches WHERE id=@id', {'id': 1});
    expect(a, isNot(b), reason: 'parameter berbeda harus beda kunci');
    expect(a, c, reason: 'spasi berlebih tidak mengubah kunci');
    expect(a.length, 32);
  });

  test('versi di app sama dengan pubspec.yaml', () {
    // Release GitHub dibuat dari tag vX.Y.Z; kalau label di app tertinggal,
    // APK baru terbit dengan nomor versi lama dan tidak ada yang menyadari.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9.]+)\+', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull, reason: 'pubspec tanpa baris version: x.y.z+build');
    expect(m!.group(1), kAppVersion);
  });

  test('pesan error user tidak membawa prefix kelas', () {
    expect(errText(Exception('Sudah ada laga dengan skor')), 'Sudah ada laga dengan skor');
    expect(errText(ApiException('Server tidak merespons')), 'Server tidak merespons');
    expect(errText('  teks biasa  '), 'teks biasa');
  });

  test('batas grup: tiap grup minimal 2 tim', () {
    expect(groupCap(3), 1, reason: '3 tim tidak bisa dibagi 2 grup');
    expect(groupCap(4), 2);
    expect(groupCap(5), 2);
    expect(groupCap(8), 4);
    expect(groupCap(12), 4, reason: 'maksimal 4 grup');
  });
}
