import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/data/models.dart';
import 'package:minisoccer_club/ui/fmt.dart';

void main() {
  test('format uang & periode', () {
    expect(fmtMoney(100000), 'Rp 100.000');
    expect(fmtMoney(0), 'Rp 0');
    expect(periodLabel('2026-03'), 'Maret 2026');
    expect(periodLabel('bad'), 'bad');
    expect(fmtDate(DateTime(2026, 1, 5)), '5 Jan 2026');
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
      Team(id: 1, tournamentId: 1, name: 'A'),
      Team(id: 2, tournamentId: 1, name: 'B'),
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
        period: '2026-10',
        paidAt: DateTime(2026, 10, 5),
      ),
      Payment(
        id: 2,
        memberId: 2,
        memberName: 'Bagas',
        amount: 75000,
        period: '2026-10',
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
}
