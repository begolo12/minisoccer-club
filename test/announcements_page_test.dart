// Regresi frame pertama halaman Pengumuman + perilaku badge & sematan.
//
// Bug yang dicegah (ketahuan dari check:features di produksi 1.17.0, lolos
// 308 tes unit): `initState` melepas pembacaan penanda "sudah dilihat" lewat
// `await` SEBELUM mengisi `late _future`, sehingga build pertama — yang jalan
// sebelum await selesai — melempar LateInitializationError. Di web jadi error
// konsol, di HP halaman berkedip merah satu frame. Kelas bug ini hanya
// tertangkap oleh tes yang benar-benar mem-pump widget-nya.
//
// Cache store diganti versi memori: `cache_io` di mesin pengembang melakukan
// I/O berkas sungguhan yang tidak pernah selesai di zona fake-async
// `testWidgets` — halaman akan macet di skeleton selamanya.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:minisoccer_club/core/cache.dart';
import 'package:minisoccer_club/core/cache_store.dart';
import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';
import 'package:minisoccer_club/data/auth.dart';
import 'package:minisoccer_club/ui/announcements.dart';
import 'package:minisoccer_club/ui/theme.dart';

class MemoryCacheStore implements CacheStore {
  final Map<String, CacheEntry> entries = {};
  @override
  Future<void> writeEntry(CacheEntry entry) async => entries[entry.key] = entry;
  @override
  Future<List<CacheEntry>> listEntries() async => entries.values.toList();
  @override
  Future<CachedRows?> readRows(String key) async {
    final e = entries[key];
    return e == null ? null : CachedRows(e.rows, e.savedAt);
  }

  @override
  Future<int> clear() async {
    final n = entries.length;
    entries.clear();
    return n;
  }
}

Widget _app() => ShadApp(theme: AppThemes.dark, home: const AnnouncementsPage());

/// `pumpAndSettle` tidak dipakai: skeleton memutar animasi tanpa henti
/// (pelajaran dari nav_shell_test) — waktu dimajukan dengan pump biasa.
/// 6 ms pertama penting: transport DB menggabungkan query dalam jendela itu.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

String _response(List<Map<String, Object?>> rows) =>
    '{"rows":${jsonEncode(rows)},"rowCount":${rows.length}}';

Map<String, Object?> _ann(int id, String title, {String? pinnedAt}) => {
      'id': id,
      'title': title,
      'body': 'isi $title',
      'pinned_at': pinnedAt,
      'created_at': '2026-10-2${id}T00:00:00.000Z',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    useCacheStore(MemoryCacheStore());
    Db.cacheScope = 'public';
  });
  tearDown(() {
    useClient(http.Client());
    resetCacheStore();
    Auth.username = null;
    Auth.role = null;
    Db.authToken = null;
  });

  testWidgets('frame pertama tidak melempar (regresi LateInitializationError)',
      (tester) async {
    useClient(MockClient((_) async => http.Response(_response([]), 200)));
    await tester.pumpWidget(_app());
    // Frame pertama persis seperti di produksi: initState sudah jalan,
    // await pertama belum selesai.
    await tester.pump();
    expect(tester.takeException(), isNull);
    await _settle(tester);
    expect(find.text('Belum ada pengumuman'), findsOneWidget);
  });

  testWidgets('tanpa riwayat baca: daftar tampil, tidak ada badge BARU',
      (tester) async {
    useClient(MockClient((_) async => http.Response(
        _response([_ann(7, 'Latihan besok'), _ann(3, 'Iuran dibuka')]), 200)));
    await tester.pumpWidget(_app());
    await _settle(tester);
    expect(find.text('Latihan besok'), findsOneWidget);
    expect(find.text('Iuran dibuka'), findsOneWidget);
    // Akun belum pernah membuka halaman: semua badge menyala = derau.
    expect(find.text('BARU'), findsNothing);
  });

  testWidgets('badge BARU hanya untuk pengumuman di atas penanda',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({'announcements_seen:public': '5'});
    useClient(MockClient((_) async => http.Response(
        _response([_ann(7, 'Latihan besok'), _ann(3, 'Iuran dibuka')]), 200)));
    await tester.pumpWidget(_app());
    await _settle(tester);
    expect(find.text('BARU'), findsOneWidget,
        reason: 'hanya id 7 yang lebih baru dari penanda 5');
  });

  testWidgets('pengumuman disematkan punya ikon bersemantik', (tester) async {
    useClient(MockClient((_) async => http.Response(
        _response([
          _ann(9, 'Jadwal berubah', pinnedAt: '2026-10-30T00:00:00.000Z'),
        ]),
        200)));
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    await _settle(tester);
    expect(find.text('Jadwal berubah'), findsOneWidget);
    // Label semantik icon menyatu ke node barisnya (bukan node sendiri),
    // jadi dicocokkan dengan RegExp seperti nav_shell_test.
    expect(find.bySemanticsLabel(RegExp('Disematkan')), findsWidgets);
    handle.dispose();
  });

  testWidgets('membuka halaman memasang penanda untuk kunjungan berikut',
      (tester) async {
    useClient(MockClient((_) async => http.Response(
        _response([_ann(7, 'Latihan besok')]), 200)));
    await tester.pumpWidget(_app());
    await _settle(tester);
    // Pembacaan storage sungguhan harus keluar dari zona fake-async, kalau
    // tidak round-trip channel-nya tidak pernah delivered.
    final stored = await tester.runAsync(() =>
        const FlutterSecureStorage().read(key: 'announcements_seen:public'));
    expect(stored, '7');
  });
}
