// Back di dalam form tulis tidak boleh membuang isian diam-diam.
//
// Dulu Back langsung menutup dialog: alasan tersering menekan Back di tengah
// form justru ingin menutup keyboard, dan semua yang diketik hilang. Sekarang
// Back (dan tombol Batal) meminta konfirmasi kalau ada isian.
//
// Waktu tidak dimajukan dengan `pumpAndSettle`: skeleton beranda memutar
// animasi tanpa henti di halaman lain, jadi helper `_settle` dipakai.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';
import 'package:minisoccer_club/data/auth.dart';
import 'package:minisoccer_club/ui/shell.dart';
import 'package:minisoccer_club/ui/theme.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  expect(f, findsWidgets, reason: 'target ketukan harus terlihat');
  await tester.tap(f.first);
  await _settle(tester);
}

/// Buka halaman Anggota lalu form tambah anggota.
Future<void> _openMemberForm(WidgetTester tester) async {
  await _tap(tester, find.text('Lainnya'));
  await _tap(tester, find.text('Anggota'));
  await _tap(tester, find.byIcon(Icons.person_add_alt_1));
  expect(find.text('Tambah anggota'), findsOneWidget);
}

void main() {
  setUp(() {
    useClient(MockClient((_) async => http.Response('{"rows":[],"rowCount":0}', 200)));
    Db.cacheScope = 'admin';
    Auth.username = 'admin';
    Auth.role = 'admin';
  });

  tearDown(() {
    useClient(http.Client());
    Auth.username = null;
    Auth.role = null;
    Db.authToken = null;
  });

  testWidgets('Back pada form kosong menutup form tanpa bertanya', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ShadApp(theme: AppThemes.dark, home: const HomeShell()));
    await _settle(tester);
    await _openMemberForm(tester);

    await tester.binding.handlePopRoute();
    await _settle(tester);

    expect(find.text('Tambah anggota'), findsNothing, reason: 'form tertutup');
    expect(find.text('Buang isian?'), findsNothing, reason: 'tidak perlu bertanya');
    expect(find.text('Anggota'), findsOneWidget, reason: 'tetap di halaman Anggota');
  });

  testWidgets('Back pada form terisi bertahan, minta konfirmasi', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ShadApp(theme: AppThemes.dark, home: const HomeShell()));
    await _settle(tester);
    await _openMemberForm(tester);

    await tester.enterText(find.descendant(of: find.byType(ShadDialog), matching: find.byType(ShadInput)).first, 'Joko');
    await _settle(tester);

    await tester.binding.handlePopRoute();
    await _settle(tester);

    expect(find.text('Buang isian?'), findsOneWidget, reason: 'konfirmasi muncul');
    expect(find.text('Tambah anggota'), findsOneWidget, reason: 'form masih terbuka');

    // "Batal" pada konfirmasi = tetap di form, isian utuh. `last`: dialog
    // konfirmasi menumpuk di atas form, jadi tombol Batal-nya yang terakhir.
    await _tap(tester, find.text('Batal').last);
    expect(find.text('Tambah anggota'), findsOneWidget);
    expect(find.text('Joko'), findsOneWidget, reason: 'isian tidak hilang');
  });

  testWidgets('konfirmasi "Buang" menutup form', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ShadApp(theme: AppThemes.dark, home: const HomeShell()));
    await _settle(tester);
    await _openMemberForm(tester);

    await tester.enterText(find.descendant(of: find.byType(ShadDialog), matching: find.byType(ShadInput)).first, 'Joko');
    await _settle(tester);

    await tester.binding.handlePopRoute();
    await _settle(tester);
    await _tap(tester, find.text('Buang'));

    expect(find.text('Tambah anggota'), findsNothing, reason: 'form tertutup');
    expect(find.text('Buang isian?'), findsNothing);
  });

  testWidgets('tombol Batal pada form terisi juga bertanya', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ShadApp(theme: AppThemes.dark, home: const HomeShell()));
    await _settle(tester);
    await _openMemberForm(tester);

    await tester.enterText(find.descendant(of: find.byType(ShadDialog), matching: find.byType(ShadInput)).first, 'Joko');
    await _settle(tester);

    await _tap(tester, find.text('Batal'));
    expect(find.text('Buang isian?'), findsOneWidget);
    expect(find.text('Tambah anggota'), findsOneWidget);
  });
}
