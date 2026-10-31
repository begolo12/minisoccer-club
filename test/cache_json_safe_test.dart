// Tes regresi bug produksi 2026-11-01: bagian "Iuran bulan ini" di beranda
// web gagal dimuat padahal server menjawab 200.
//
// Rantai kejadiannya: `Payment.inMonth` mengirim parameter `DateTime`
// (`@from`/`@to`) → entri cache web meng-`jsonEncode` params mentah →
// `jsonEncode` melempar untuk `DateTime` → lemparan itu melewati `writeEntry`
// (di luar `try`) dan `Db.query` meng-`await` tanpa penjaga → query yang
// datanya sudah di tangan dilaporkan gagal ke layar.
//
// Tiga penjaga sekaligus diuji di sini:
//   1. `Db.query` tidak jatuh walau penyimpanan cache melempar apa pun,
//   2. params yang disimpan ke entri cache sudah aman-JSON (`DateTime`
//      menjadi ISO-8601 UTC — bentuk yang sama dikirim ke server),
//   3. `jsonSafeParams` menangani `DateTime` bersarang di List/Map.
// Tanpa penjaga #2, di web entri tidak pernah tersimpan dan di Android
// tersimpan senyap-senyap dibuang — artinya query ber-rentang tanggal
// tidak punya cache offline sama sekali.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minisoccer_club/core/cache.dart';
import 'package:minisoccer_club/core/cache_store.dart';
import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';

/// Store yang meniru kegagalan penyimpanan web: `jsonEncode` params mentah
/// DI LUAR `try` — bentuk yang persis menabrak bug produksi.
class ThrowingEncodeCacheStore implements CacheStore {
  final List<CacheEntry> written = [];

  @override
  Future<void> writeEntry(CacheEntry entry) async {
    // Kalau params masih berisi `DateTime`, jsonEncode melempar sebelum
    // sempat menyimpan — dan tanpa penjaga di Db, query ikut mati.
    jsonEncode({'params': entry.params, 'rows': entry.rows});
    written.add(entry);
  }

  @override
  Future<List<CacheEntry>> listEntries() async => written;

  @override
  Future<CachedRows?> readRows(String key) async => null;

  @override
  Future<int> clear() async => 0;
}

void main() {
  setUp(() {
    Db.authToken = null;
    Db.offline.value = false;
    Db.offlineSince = null;
  });

  tearDown(() {
    useClient(http.Client());
    resetCacheStore();
  });

  group('jsonSafeParams', () {
    test('DateTime menjadi ISO-8601 UTC, bentuk yang sama dikirim ke server', () {
      final out = jsonSafeParams({
        'from': DateTime.utc(2026, 11, 1),
        'to': DateTime.utc(2026, 12, 1),
      });
      expect(out['from'], '2026-11-01T00:00:00.000Z');
      expect(out['to'], '2026-12-01T00:00:00.000Z');
    });

    test('DateTime bersarang di List dan Map ikut dikonversi', () {
      final out = jsonSafeParams({
        'rentang': [DateTime.utc(2026, 11, 1), DateTime.utc(2026, 11, 30)],
        'filter': {'dari': DateTime.utc(2026, 11, 1)},
      });
      expect(out['rentang'], ['2026-11-01T00:00:00.000Z', '2026-11-30T00:00:00.000Z']);
      expect((out['filter'] as Map)['dari'], '2026-11-01T00:00:00.000Z');
      // Harus bisa di-encode dua lapis tanpa melempar.
      expect(() => jsonEncode(out), returnsNormally);
    });

    test('idempoten: hasil encode tidak berubah jika dinormalkan lagi', () {
      final sekali = jsonSafeParams({'from': DateTime.utc(2026, 11, 1)});
      final dua = jsonSafeParams(sekali);
      expect(dua, sekali);
    });
  });

  group('Db.query dengan parameter DateTime', () {
    test('query tetap berhasil walau penyimpanan cache melempar', () async {
      useClient(MockClient((req) async => http.Response(
            jsonEncode({'rows': [
              {'id': 1, 'amount': 50000},
            ], 'rowCount': 1}),
            200,
            headers: {'content-type': 'application/json'},
          )));
      useCacheStore(ThrowingEncodeCacheStore());

      final rows = await Db.query(
        'SELECT id, amount FROM payments WHERE paid_at >= @from AND paid_at < @to',
        params: {'from': DateTime(2026, 11, 1), 'to': DateTime(2026, 12, 1)},
      );

      expect(rows, hasLength(1));
      expect(rows.first['amount'], 50000);
    });

    test('params yang masuk entri cache sudah aman-JSON', () async {
      final entries = <CacheEntry>[];
      useClient(MockClient((req) async => http.Response(
            jsonEncode({'rows': [
              {'id': 1},
            ], 'rowCount': 1}),
            200,
            headers: {'content-type': 'application/json'},
          )));
      useCacheStore(_RecordingCacheStore(entries));

      await Db.query(
        'SELECT id FROM payments WHERE paid_at >= @from AND paid_at < @to',
        params: {'from': DateTime(2026, 11, 1), 'to': DateTime(2026, 12, 1)},
      );

      expect(entries, hasLength(1));
      // Inilah yang dulu melempar di penyimpanan web dan mematikan query.
      expect(() => jsonEncode({'params': entries.first.params}), returnsNormally);
      expect(entries.first.params['from'], isA<String>());
    });
  });
}

class _RecordingCacheStore implements CacheStore {
  final List<CacheEntry> entries;
  _RecordingCacheStore(this.entries);

  @override
  Future<void> writeEntry(CacheEntry entry) async => entries.add(entry);

  @override
  Future<List<CacheEntry>> listEntries() async => entries;

  @override
  Future<CachedRows?> readRows(String key) async => null;

  @override
  Future<int> clear() async => 0;
}
