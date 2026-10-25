// Tes kegagalan di tengah Booking.insert: booking tersimpan, leg kasnya
// ditolak server.
//
// Kegagalan JARINGAN pada leg kas sudah ditangani Db (masuk antrean otomatis).
// Yang diuji di sini adalah penolakan SERVER (bukan jaringan) — jalur yang
// dulu menyisakan booking tanpa catatan kas sambil menampilkan "Gagal simpan",
// mendorong pengguna menekan Simpan lagi dan membuat dua booking.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minisoccer_club/core/db_web.dart' show useClient;
import 'package:minisoccer_club/core/offline.dart';
import 'package:minisoccer_club/data/models.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

void main() {
  late Directory temp;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('msc_booking_partial_');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
  });

  tearDownAll(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() {
    final outbox = File('${temp.path}/outbox.json');
    if (outbox.existsSync()) outbox.deleteSync();
    Outbox.resetForTest();
  });

  tearDown(() {
    useClient(http.Client());
    Outbox.resetForTest();
  });

  test('leg kas yang ditolak server masuk antrean + dilempar sebagai parsial', () async {
    useClient(MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final sql = (body['sql'] as String).trim();
      if (sql.startsWith('INSERT INTO bookings')) {
        return http.Response('{"rows":[{"id":7}],"rowCount":1}', 200);
      }
      if (sql.startsWith('INSERT INTO transactions')) {
        return http.Response('{"error":"ditolak server"}', 500);
      }
      return http.Response('{"rows":[],"rowCount":0}', 200);
    }));

    await expectLater(
      Booking.insert(
        title: 'Sewa A',
        startsAt: DateTime(2026, 11, 1, 20),
        durationMin: 90,
        cost: 150000,
      ),
      throwsA(isA<BookingPartialException>()),
    );

    expect(Outbox.pending.value, 1,
        reason: 'leg kas yang gagal diantrekan, bukan hilang diam-diam');
    expect(Outbox.items.single.params['booking'], 7,
        reason: 'antrean memakai id booking ASLI (bukan sementara) supaya '
            'sinkron berikutnya langsung sah');
    expect(Outbox.loadError, isNull);
  });

  test('leg kas yang berhasil tidak memicu apa pun yang parsial', () async {
    useClient(MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final sql = (body['sql'] as String).trim();
      if (sql.startsWith('INSERT INTO bookings')) {
        return http.Response('{"rows":[{"id":8}],"rowCount":1}', 200);
      }
      return http.Response('{"rows":[],"rowCount":1}', 200);
    }));

    await Booking.insert(
      title: 'Sewa B',
      startsAt: DateTime(2026, 11, 2, 20),
      durationMin: 60,
      cost: 100000,
    );
    expect(Outbox.pending.value, 0);
  });

  test('tanpa catat kas (postToCash false), tabel kas tidak disentuh', () async {
    final touched = <String>[];
    useClient(MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final sql = (body['sql'] as String).trim();
      touched.add(sql);
      return http.Response('{"rows":[{"id":9}],"rowCount":1}', 200);
    }));

    await Booking.insert(
      title: 'Sewa C',
      startsAt: DateTime(2026, 11, 3, 20),
      durationMin: 60,
      cost: 0,
    );
    expect(touched, hasLength(1), reason: 'hanya INSERT bookings');
    expect(touched.single, contains('INSERT INTO bookings'));
    expect(Outbox.pending.value, 0);
  });
}
