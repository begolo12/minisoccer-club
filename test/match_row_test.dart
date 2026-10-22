// Tes render untuk baris laga (`MatchRow`).
//
// Kenapa perlu tes widget, bukan hanya tes data: bug "KALAH · 3 POIN" lahir di
// penyusunan teks di dalam `build()`, bukan di model. Tes unit pada `Match`
// tidak akan menangkapnya — poin dihitung ulang di widget, dari sudut pandang
// tim yang sedang dibuka.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/data/models.dart';
import 'package:minisoccer_club/ui/theme.dart';
import 'package:minisoccer_club/ui/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Match _match({
  required int goalsFor,
  required int goalsAgainst,
  String status = 'finished',
}) =>
    Match(
      id: 1,
      playedAt: DateTime(2026, 1, 1),
      status: status,
      goalsFor: goalsFor,
      goalsAgainst: goalsAgainst,
      homeTeamId: 1,
      awayTeamId: 2,
      homeName: 'Tim A',
      awayName: 'Tim B',
    );

/// Bungkus MatchRow dengan tema app supaya `ShadTheme.of` tersedia.
Widget _wrap(Widget child) => ShadApp(
      theme: AppThemes.dark,
      darkTheme: AppThemes.dark,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('tim yang kalah mendapat 0 poin, bukan 3', (tester) async {
    // Regresi produksi: baris memakai `pointsForWinner` (selalu 3 untuk laga
    // selesai), sehingga tim yang kalah pun tertulis "KALAH · 3 POIN".
    // `showResult: false` = bentuk yang dipakai halaman detail tim.
    await tester.pumpWidget(_wrap(MatchRow(
      match: _match(goalsFor: 1, goalsAgainst: 3),
      forTeamId: 1, // tim home kalah 1–3
      showResult: false,
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('KALAH'), findsOneWidget);
    expect(find.textContaining('0 POIN'), findsOneWidget);
    expect(find.textContaining('3 POIN'), findsNothing);
  });

  testWidgets('tim away yang menang mendapat 3 poin', (tester) async {
    // Tim away menang: golnya ada di goals_against (3), kebobolan 1.
    await tester.pumpWidget(_wrap(MatchRow(
      match: _match(goalsFor: 1, goalsAgainst: 3),
      forTeamId: 2, // tim away menang 3–1
      showResult: false,
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('MENANG'), findsOneWidget);
    expect(find.textContaining('3 POIN'), findsOneWidget);
  });

  testWidgets('seri: kedua tim dapat 1 poin', (tester) async {
    await tester.pumpWidget(_wrap(MatchRow(
      match: _match(goalsFor: 2, goalsAgainst: 2),
      forTeamId: 1,
      showResult: false,
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('SERI'), findsOneWidget);
    expect(find.textContaining('1 POIN'), findsOneWidget);
  });

  testWidgets('nama pemenang dari sudut pandang tim, bukan selalu tim home',
      (tester) async {
    // showResult: tim away menang, jadi yang MENANG adalah Tim B — bukan
    // Tim A hanya karena ia tim home.
    await tester.pumpWidget(_wrap(MatchRow(
      match: _match(goalsFor: 1, goalsAgainst: 3),
      forTeamId: 2,
      showResult: true,
    )));
    await tester.pumpAndSettle();

    expect(find.textContaining('Tim B MENANG'), findsOneWidget);
    expect(find.textContaining('Tim A MENANG'), findsNothing);
  });

  testWidgets('skor dibaca dari sudut pandang tim', (tester) async {
    // Tim away mencetak 3, kebobolan 1 → "3–1", bukan "1–3".
    await tester.pumpWidget(_wrap(MatchRow(
      match: _match(goalsFor: 1, goalsAgainst: 3),
      forTeamId: 2,
      showResult: false,
    )));
    await tester.pumpAndSettle();

    expect(find.text('3–1'), findsOneWidget);
  });
}
