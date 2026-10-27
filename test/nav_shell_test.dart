// Halaman turunan harus tetap di dalam shell.
//
// Dulu "Kas klub", "Turnamen", detail laga, dan kawan-kawan di-push ke
// navigator akar sehingga menutupi `Scaffold` shell: bar bawah dan rail kiri
// hilang, dan satu-satunya jalan kembali adalah tombol panah. Yang diuji:
//   1. Di layar lebar, rail tetap ada setelah halaman turunan dibuka.
//   2. Di HP, bar bawah tetap ada.
//   3. Memilih tab lain menutup halaman turunan (tidak tertinggal di atasnya).
//
// `pumpAndSettle` tidak dipakai: skeleton memutar animasi tanpa henti, jadi
// "settle" tidak pernah tercapai. Waktu dimajukan dengan `pump` biasa.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';
import 'package:minisoccer_club/data/auth.dart';
import 'package:minisoccer_club/ui/finance.dart';
import 'package:minisoccer_club/ui/shell.dart';
import 'package:minisoccer_club/ui/theme.dart';

Widget _app() => ShadApp(theme: AppThemes.dark, home: const HomeShell());

/// Server tiruan: semua query dijawab kosong. Shell hanya butuh "tidak error".
void _fakeServer() {
  useClient(MockClient((_) async => http.Response('{"rows":[],"rowCount":0}', 200)));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  expect(f, findsWidgets, reason: '"$text" harus terlihat');
  await tester.tap(f.first);
  await _settle(tester);
}

void main() {
  setUp(() {
    _fakeServer();
    Db.cacheScope = 'public';
  });

  tearDown(() {
    useClient(http.Client());
    Auth.username = null;
    Auth.role = null;
    Db.authToken = null;
  });

  testWidgets('layar lebar: rail tetap ada saat halaman turunan dibuka', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await _settle(tester);

    await _tapText(tester, 'Lainnya');
    await _tapText(tester, 'Kas klub');

    expect(find.byType(FinancePage), findsOneWidget, reason: 'Kas terbuka');
    expect(find.text('MINISOCCER'), findsOneWidget, reason: 'rail tidak ikut tertutup');
  });

  testWidgets('HP: bar bawah tetap ada saat halaman turunan dibuka', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await _settle(tester);

    await _tapText(tester, 'Lainnya');
    await _tapText(tester, 'Kas klub');

    expect(find.byType(FinancePage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'bar bawah tidak ikut tertutup');
  });

  testWidgets('memilih tab lain menutup halaman turunan', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app());
    await _settle(tester);

    await _tapText(tester, 'Lainnya');
    await _tapText(tester, 'Kas klub');
    expect(find.byType(FinancePage), findsOneWidget);

    // Ketuk "Beranda" di bar bawah: Kas harus tertutup, bukan tertinggal.
    final nav = find.byType(NavigationBar);
    await tester.tap(find.descendant(of: nav, matching: find.text('Beranda')));
    await _settle(tester);

    expect(find.byType(FinancePage), findsNothing);
  });
}
