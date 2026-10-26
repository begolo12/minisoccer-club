// Data uang klub tidak terbuka untuk tamu — sisi klien.
//
// Server sudah menolak membacanya (`api/_guard.js`), tapi kalau halaman tetap
// meminta, pengguna melihat baris "gagal dimuat" yang terbaca seperti
// kerusakan. Yang benar: halaman menjelaskan bahwa bagian ini khusus anggota,
// dan menyediakan tombol masuk.
//
// Yang diuji:
//   1. Tamu: Iuran, Kas, Sewa lapangan, dan riwayat iuran menampilkan
//      penjelasan + tombol Masuk, TANPA meminta data uang ke server.
//   2. Sudah masuk: tidak ada lagi layar terkunci.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';
import 'package:minisoccer_club/data/auth.dart';
import 'package:minisoccer_club/data/models.dart';
import 'package:minisoccer_club/ui/bookings.dart';
import 'package:minisoccer_club/ui/finance.dart';
import 'package:minisoccer_club/ui/member_dues.dart';
import 'package:minisoccer_club/ui/payments.dart';
import 'package:minisoccer_club/ui/theme.dart';

Widget _wrap(Widget child) => ShadApp(theme: AppThemes.dark, home: child);

/// Hitung permintaan ke `/api/sql` supaya bisa dibuktikan bahwa halaman
/// terkunci tidak memanggil server sama sekali.
int requests = 0;

void _fakeServer() {
  useClient(MockClient((_) async {
    requests++;
    return http.Response('{"rows":[],"rowCount":0}', 200);
  }));
}

void main() {
  setUp(() {
    requests = 0;
    _fakeServer();
    Db.cacheScope = 'public';
  });

  tearDown(() {
    useClient(http.Client());
    Auth.username = null;
    Auth.role = null;
    Db.authToken = null;
  });

  const locked = 'Khusus anggota klub';

  testWidgets('tamu: Iuran terkunci dan tidak memanggil server', (tester) async {
    await tester.pumpWidget(_wrap(const PaymentsPage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(locked), findsOneWidget);
    expect(find.text('Masuk'), findsWidgets);
    expect(requests, 0, reason: 'data uang tidak boleh diminta tanpa sesi');
  });

  testWidgets('tamu: Kas klub terkunci', (tester) async {
    await tester.pumpWidget(_wrap(const FinancePage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(locked), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('tamu: Sewa lapangan terkunci', (tester) async {
    await tester.pumpWidget(_wrap(const BookingsPage()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(locked), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('tamu: riwayat iuran anggota terkunci', (tester) async {
    final member = Member(
      id: 1,
      name: 'Irvan',
      position: 'Bek',
      active: true,
      joinedAt: DateTime(2026, 1, 1),
    );
    await tester.pumpWidget(_wrap(MemberDuesPage(member: member)));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(locked), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('sudah masuk: Iuran tidak lagi terkunci', (tester) async {
    Auth.username = 'urip';
    Auth.role = 'member';
    Db.cacheScope = 'member';

    await tester.pumpWidget(_wrap(const PaymentsPage()));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(locked), findsNothing);
    expect(requests, greaterThan(0), reason: 'data boleh diminta setelah masuk');
  });
}
