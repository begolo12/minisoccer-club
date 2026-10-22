// Patungan lapangan saat OFFLINE.
//
// Pembagian biaya dikirim sebagai satu `UPDATE ... FROM (VALUES ...)` massal.
// Penambal cache tidak mengenali bentuk itu, jadi dulu baris di cache tetap
// memakai angka lama: orang yang baru ditambahkan tampil dengan bagian Rp 0,
// dan tombol "sudah setor" mencatat Rp 0 ke kas. Tes ini menjaga agar angka di
// layar (cache) sama dengan yang dikirim ke server.
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

/// SQL yang sama dengan `BookingAttendance.forBooking`, karena cache dikunci
/// oleh teks query + parameternya.
const _selectForBooking = '''
    SELECT a.*, m.name AS member_name, t.id AS transaction_id,
           b.title AS booking_title, b.starts_at AS booking_starts_at
    FROM booking_attendance a
    JOIN members m ON m.id = a.member_id
    JOIN bookings b ON b.id = a.booking_id
    LEFT JOIN transactions t ON t.attendance_id = a.id WHERE a.booking_id=@bid ORDER BY m.name''';

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
  void seed(List<Map<String, Object?>> rows) {
    const params = {'bid': 1};
    store.entries[cacheKey(_selectForBooking, params)] = CacheEntry(
      key: cacheKey(_selectForBooking, params),
      sql: _selectForBooking,
      params: params,
      rows: rows,
      savedAt: DateTime.now(),
    );
  }

  test('menambah peserta saat offline membagi ulang bagian di cache', () async {
    seed([_row(1, 10, 150000), _row(2, 11, 150000)]);

    await BookingAttendance.add(1, 12, 300000);

    final rows = await BookingAttendance.forBooking(1);
    final shares = rows.map((r) => r.share).toList();
    expect(rows, hasLength(3));
    expect(shares, everyElement(100000),
        reason: 'tiga orang menanggung 300.000; bagian: $shares');
    expect(shares.fold<double>(0, (a, b) => a + b), 300000);
  });

  test('mengeluarkan peserta saat offline membagi ulang sisanya', () async {
    seed([_row(1, 10, 100000), _row(2, 11, 100000), _row(3, 12, 100000)]);

    await BookingAttendance.remove(3, 1, 300000);

    final rows = await BookingAttendance.forBooking(1);
    expect(rows.map((r) => r.id), [1, 2]);
    expect(rows.map((r) => r.share), everyElement(150000));
  });

  test('setoran saat offline memakai bagian yang benar, bukan nol', () async {
    seed([_row(1, 10, 150000), _row(2, 11, 150000)]);
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
}
