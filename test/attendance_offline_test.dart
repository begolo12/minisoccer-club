// Patungan lapangan saat OFFLINE.
//
// Pembagian biaya dikirim sebagai satu `UPDATE ... FROM (VALUES ...)` massal.
// Penambal cache tidak mengenali bentuk itu, jadi dulu baris di cache tetap
// memakai angka lama: orang yang baru ditambahkan tampil dengan bagian Rp 0,
// dan tombol "sudah setor" mencatat Rp 0 ke kas. Tes ini menjaga agar angka di
// layar (cache) sama dengan yang dikirim ke server.
import 'dart:convert';

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

/// Isi cache lewat jalur yang sesungguhnya: satu pembacaan online berhasil,
/// hasilnya disimpan `Db` ke cache. Menulis entri cache dengan teks SQL
/// salinan sendiri rapuh — begitu `_select` di model berubah (mis. kolom baru),
/// kuncinya tidak cocok lagi dan tes gagal dengan "tidak bisa menghubungi
/// server" padahal logikanya benar.
Future<void> _seedOnline(List<Map<String, Object?>> rows) async {
  useClient(MockClient((_) async => http.Response(
        jsonEncode({'rows': rows, 'rowCount': rows.length}),
        200,
        headers: {'content-type': 'application/json'},
      )));
  await BookingAttendance.forBooking(1);
  // Kembali ke keadaan offline: setiap permintaan gagal seperti HP tanpa sinyal.
  useClient(MockClient(
      (_) async => throw http.ClientException('Failed host lookup: api')));
}

Map<String, Object?> _row(int id, int memberId, double share) => {
      'id': id,
      'booking_id': 1,
      'member_id': memberId,
      'member_name': 'Anggota $memberId',
      'share_amount': share,
      'paid_at': null,
      'note': null,
      'booking_title': 'Futsal',
      'booking_starts_at': '2026-10-01T20:00:00.000Z',
      'transaction_id': null,
    };

void main() {
  late MemoryCacheStore store;

  setUp(() {
    store = MemoryCacheStore();
    useCacheStore(store);
    Outbox.resetForTest();
    Db.offline.value = false;
    Db.offlineSince = null;
    // Jaringan mati: setiap permintaan gagal seperti HP tanpa sinyal.
    useClient(MockClient((_) async =>
        throw http.ClientException('Failed host lookup: api')));
  });

  tearDown(() {
    useClient(http.Client());
    resetCacheStore();
    Outbox.resetForTest();
    Db.offline.value = false;
    Db.offlineSince = null;
  });

  /// Isi cache seperti setelah halaman detail dimuat saat online.
  Future<void> seed(List<Map<String, Object?>> rows) => _seedOnline(rows);

  test('menambah peserta saat offline membagi ulang bagian di cache', () async {
    await seed([_row(1, 10, 150000), _row(2, 11, 150000)]);

    await BookingAttendance.add(1, 12, 300000);

    final rows = await BookingAttendance.forBooking(1);
    final shares = rows.map((r) => r.share).toList();
    expect(rows, hasLength(3));
    expect(shares, everyElement(100000),
        reason: 'tiga orang menanggung 300.000; bagian: $shares');
    expect(shares.fold<double>(0, (a, b) => a + b), 300000);
  });

  test('mengeluarkan peserta saat offline membagi ulang sisanya', () async {
    await seed([_row(1, 10, 100000), _row(2, 11, 100000), _row(3, 12, 100000)]);

    await BookingAttendance.remove(3, 1, 300000);

    final rows = await BookingAttendance.forBooking(1);
    expect(rows.map((r) => r.id), [1, 2]);
    expect(rows.map((r) => r.share), everyElement(150000));
  });

  test('setoran saat offline memakai bagian yang benar, bukan nol', () async {
    await seed([_row(1, 10, 150000), _row(2, 11, 150000)]);
    await BookingAttendance.add(1, 12, 300000);

    // Persis yang dilakukan halaman detail: nominal diambil dari baris.
    final row = (await BookingAttendance.forBooking(1)).first;
    await BookingAttendance.pay(
      attendanceId: row.id,
      memberId: row.memberId,
      amount: row.share,
      occurredAt: DateTime.utc(2026, 10, 21, 20),
      note: 'Patungan',
    );

    final cash = Outbox.items
        .where((w) => w.sql.contains('INSERT INTO transactions'))
        .toList();
    expect(cash, hasLength(1));
    expect(cash.single.params['amount'], 100000,
        reason: 'yang masuk kas harus bagian orang itu, bukan 0');

    final after = (await BookingAttendance.forBooking(1))
        .firstWhere((r) => r.id == row.id);
    expect(after.paid, isTrue, reason: 'status di layar harus langsung berubah');
  });

  test('antrean kehadiran terkirim memakai id asli, bukan id sementara',
      () async {
    await seed([]);
    await BookingAttendance.add(1, 12, 300000, memberName: 'Anggota 12');
    expect(Outbox.items, hasLength(2),
        reason: 'satu INSERT kehadiran + satu pembagian biaya');

    final shares = <Map<String, Object?>>[];
    useClient(MockClient((req) async {
      final body = req.body;
      if (body.contains('INSERT INTO booking_attendance')) {
        return http.Response('{"rows":[{"id":77}],"rowCount":1}', 200,
            headers: {'content-type': 'application/json'});
      }
      if (body.contains('SET share_amount = v.share')) {
        shares.add((jsonDecode(body)['params'] as Map).cast<String, Object?>());
      }
      return http.Response('{"rows":[],"rowCount":1}', 200,
          headers: {'content-type': 'application/json'});
    }));

    final r = await Db.sync();
    expect(r.remaining, 0, reason: 'antrean harus habis, bukan menyisakan gagal');
    expect(r.failed, 0);
    expect(shares, hasLength(1));
    expect(shares.single['id0'], 77,
        reason: 'pembagian harus menunjuk id asli dari server');
    expect(shares.single['s0'], 300000);
  });
}
