// Telusuri urutan tulis saat menambah peserta patungan satu per satu.
//
// Gejala di produksi: menambah 3 orang menghasilkan bagian 100.000, 100.000,
// dan 0 — orang terakhir tidak pernah mendapat bagiannya, sehingga jumlah
// semua bagian (200.000) tidak sama dengan biaya sewa (300.000).
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minisoccer_club/core/cache.dart';
import 'package:minisoccer_club/core/cache_store.dart';
import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';
import 'package:minisoccer_club/core/offline.dart';
import 'package:minisoccer_club/data/models.dart';

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

/// Server tiruan yang menyimpan baris kehadiran di memori, supaya urutan
/// INSERT/UPDATE/SELECT benar-benar dijalankan seperti di database.
class FakeDb {
  final List<Map<String, Object?>> rows = [];
  int _nextId = 1;
  final List<String> log = [];

  http.Client get client => MockClient((req) async {
        final body = (req.body.isEmpty ? '{}' : req.body);
        final sql = RegExp(r'"sql"\s*:\s*"((?:[^"\\]|\\.)*)"')
                .firstMatch(body)
                ?.group(1)
                ?.replaceAll(r'\n', ' ')
                .replaceAll(r'\"', '"') ??
            '';
        final upper = sql.toUpperCase();
        log.add(sql.replaceAll(RegExp(r'\s+'), ' ').trim());

        if (upper.startsWith('INSERT INTO BOOKING_ATTENDANCE')) {
          final b = _num(body, 'bid');
          final m = _num(body, 'm');
          final exists = rows.any((r) => r['booking_id'] == b && r['member_id'] == m);
          if (!exists) {
            rows.add({
              'id': _nextId++,
              'booking_id': b,
              'member_id': m,
              'share_amount': 0,
              'paid_at': null,
              'note': null,
              'created_at': '2026-10-01T00:00:00.000Z',
              'member_name': 'Anggota $m',
              'booking_title': 'Futsal',
              'booking_starts_at': '2026-10-01T20:00:00.000Z',
              'transaction_id': null,
            });
          }
          return _ok('{"rows":[],"rowCount":1}');
        }
        if (upper.startsWith('UPDATE BOOKING_ATTENDANCE SET SHARE_AMOUNT = V.SHARE')) {
          // Satu pernyataan untuk semua baris:
          //   FROM (VALUES (@id0, @s0), (@id1, @s1)) AS v(id, share)
          for (final m in RegExp(r'\(@id(\d+)::int,\s*@s(\d+)::numeric\)').allMatches(sql)) {
            final id = _num(body, 'id${m.group(1)}');
            final share = _num(body, 's${m.group(2)}');
            for (final r in rows) {
              if (r['id'] == id) r['share_amount'] = share;
            }
          }
          return _ok('{"rows":[],"rowCount":1}');
        }
        if (upper.startsWith('UPDATE BOOKING_ATTENDANCE SET SHARE_AMOUNT')) {
          final share = _num(body, 'share');
          final id = _num(body, 'id');
          for (final r in rows) {
            if (r['id'] == id) r['share_amount'] = share;
          }
          return _ok('{"rows":[],"rowCount":1}');
        }
        if (upper.startsWith('DELETE FROM BOOKING_ATTENDANCE')) {
          final id = _num(body, 'id');
          rows.removeWhere((r) => r['id'] == id);
          return _ok('{"rows":[],"rowCount":1}');
        }
        if (upper.contains('FROM BOOKING_ATTENDANCE A')) {
          final b = _num(body, 'bid');
          final list = rows.where((r) => r['booking_id'] == b).toList()
            ..sort((x, y) => '${x['member_name']}'.compareTo('${y['member_name']}'));
          final encoded = list
              .map((r) => '{${r.entries.map((e) => '"${e.key}":${e.value == null ? 'null' : (e.value is num ? e.value : '"${e.value}"')}').join(',')}}')
              .join(',');
          return _ok('{"rows":[$encoded],"rowCount":${list.length}}');
        }
        return _ok('{"rows":[],"rowCount":0}');
      });

  http.Response _ok(String body) => http.Response(body, 200,
      headers: {'content-type': 'application/json'});

  int _num(String body, String key) {
    final m = RegExp('"$key"\\s*:\\s*(-?[0-9.]+)').firstMatch(body);
    return m == null ? 0 : (double.tryParse(m.group(1)!) ?? 0).toInt();
  }
}

void main() {
  late FakeDb fake;

  setUp(() {
    fake = FakeDb();
    useClient(fake.client);
    useCacheStore(MemoryCacheStore());
    Outbox.resetForTest();
    Db.offline.value = false;
    Db.offlineSince = null;
  });

  tearDown(() {
    useClient(http.Client());
    resetCacheStore();
    Outbox.resetForTest();
  });

  test('menambah 3 peserta satu per satu membagi biaya ke KETIGANYA', () async {
    await BookingAttendance.add(1, 10, 300000);
    await BookingAttendance.add(1, 11, 300000);
    await BookingAttendance.add(1, 12, 300000);

    final shares = fake.rows.map((r) => (r['share_amount'] as num).toDouble()).toList();
    expect(fake.rows, hasLength(3));
    expect(shares.fold<double>(0, (a, b) => a + b), 300000,
        reason: 'jumlah bagian harus sama dengan biaya sewa; bagian: $shares');
    expect(shares, everyElement(100000),
        reason: 'tiga orang dengan biaya 300.000 seharusnya 100.000 masing-masing');
  });

  test('pembagian dikirim sebagai SATU pernyataan, bukan satu per orang', () async {
    // Kalau dikirim satu per satu, ada saat ketika sebagian baris sudah dibagi
    // dan sisanya belum — layar yang memuat ulang tepat saat itu menampilkan
    // angka setengah jadi.
    await BookingAttendance.add(1, 10, 300000);
    await BookingAttendance.add(1, 11, 300000);
    await BookingAttendance.add(1, 12, 300000);

    final rebalances =
        fake.log.where((s) => s.startsWith('UPDATE booking_attendance SET share_amount = v.share')).toList();
    expect(rebalances, isNotEmpty, reason: 'pembagian harus lewat pernyataan massal');

    // Yang terakhir membagi tiga baris sekaligus.
    final last = rebalances.last;
    expect(RegExp(r'\(@id\d+::int, @s\d+::numeric\)').allMatches(last).length, 3,
        reason: 'tiga baris dibagi dalam satu pernyataan; dapat: $last');
  });

  test('mengeluarkan peserta membagi ulang sisanya', () async {
    await BookingAttendance.add(1, 10, 300000);
    await BookingAttendance.add(1, 11, 300000);
    await BookingAttendance.add(1, 12, 300000);

    final first = fake.rows.firstWhere((r) => r['member_id'] == 10);
    await BookingAttendance.remove(first['id']! as int, 1, 300000);

    final shares = fake.rows.map((r) => (r['share_amount'] as num).toDouble()).toList();
    expect(fake.rows, hasLength(2));
    expect(shares, everyElement(150000),
        reason: 'dua orang menanggung 300.000 berarti 150.000 masing-masing');
    expect(shares.fold<double>(0, (a, b) => a + b), 300000);
  });

  test('menambah peserta tanpa biaya tidak menghasilkan bagian', () async {
    await BookingAttendance.add(1, 10, 0);
    expect(fake.rows.single['share_amount'], 0);
  });
}
