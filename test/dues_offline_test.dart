// Tes: catat iuran saat OFFLINE, lalu baca kembali dari cache.
//
// Jalur ini belum pernah diuji dan paling mudah rusak: baris hasil tambalan
// cache hanya berisi kolom yang disebut INSERT, sedangkan `Payment.fromMap`
// mengharapkan `member_name` dan `tournament_name` dari JOIN. Kalau kosong,
// riwayat iuran menampilkan baris tanpa nama — pengguna mengira datanya rusak.
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

/// Server yang bisa diputus; saat online mengembalikan baris dengan JOIN.
class FakeServer {
  bool offline = false;

  http.Client get client => MockClient((req) async {
        if (offline) throw http.ClientException('Connection refused');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final sql = (body['sql'] as String).trim();

        if (sql.toUpperCase().startsWith('INSERT')) {
          return http.Response('{"rows":[{"id":1}],"rowCount":1}', 200);
        }
        if (RegExp(r'SELECT 1 AS ok FROM payments').hasMatch(sql)) {
          return http.Response('{"rows":[],"rowCount":0}', 200);
        }
        if (sql.contains('payment_id')) {
          return http.Response(
            jsonEncode({
              'rows': [
                {
                  'id': 5, 'name': 'Ani', 'phone': null, 'position': 'Bek',
                  'jersey': 4, 'active': true,
                  'joined_at': '2026-01-01T00:00:00.000Z',
                  'payment_id': null, 'paid_amount': null,
                  'paid_at': null, 'paid_note': null,
                },
              ],
              'rowCount': 1,
            }),
            200,
          );
        }
        // Riwayat pembayaran (Payment.all): baris kosong saat online.
        if (sql.contains('FROM payments p')) {
          return http.Response('{"rows":[],"rowCount":0}', 200);
        }
        return http.Response('{"rows":[],"rowCount":0}', 200);
      });
}

void main() {
  late FakeServer server;

  setUp(() {
    server = FakeServer();
    useClient(server.client);
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

  test('iuran offline masuk antrean dan langsung terlihat di riwayat', () async {
    // 1. Online dulu supaya riwayat (kosong) tersimpan di cache.
    final before = await Payment.all(tournamentId: 7);
    expect(before, isEmpty);

    // 2. Jaringan mati, catat iuran.
    server.offline = true;
    await Payment.insert(memberId: 5, amount: 60000, tournamentId: 7);
    expect(Outbox.pending.value, 1);

    // 3. Baca ulang: baris baru harus muncul DAN bisa dibaca model.
    final after = await Payment.all(tournamentId: 7);
    expect(after, hasLength(1), reason: 'iuran offline harus langsung terlihat');

    // Yang paling penting: tidak ada baris tanpa nama.
    final p = after.single;
    expect(p.memberName, isNotEmpty,
        reason: 'nama anggota kosong membuat riwayat tampak rusak');
    expect(p.amount, 60000);
    expect(p.tournamentId, 7);
    expect(p.tournamentName, isNotEmpty,
        reason: 'nama turnamen kosong membuat riwayat membingungkan');
  });

  test('iuran offline tidak merusak daftar tagihan', () async {
    // Cache tagihan (query dengan payment_id) tersimpan saat online.
    final bill = await Payment.bill(7);
    expect(bill, hasLength(1));
    expect(bill.single.paid, isFalse);

    server.offline = true;
    await Payment.insert(memberId: 5, amount: 60000, tournamentId: 7);

    // Baca tagihan lagi: tidak boleh melempar, dan tidak boleh ada baris
    // sampah tanpa nama (penambal tidak boleh menyisipkan baris ke hasil
    // ringkasan/GROUP BY).
    final after = await Payment.bill(7);
    expect(after, hasLength(1), reason: 'tidak boleh ada baris tambahan');
    expect(after.single.member.name, 'Ani');
  });

  test('iuran offline langsung menandai lunas di daftar tagihan', () async {
    // Cache tagihan saat online: Ani belum bayar.
    final before = await Payment.bill(7);
    expect(before.single.paid, isFalse);

    server.offline = true;
    await Payment.insert(memberId: 5, amount: 60000, tournamentId: 7);

    // Hasil tagihan adalah query ringkasan (GROUP BY) yang sengaja tidak
    // ditambal, jadi penggabungan dari antrean inilah yang membuat statusnya
    // berubah. Tanpa itu, pengguna mencatat iuran yang sama dua kali.
    final after = await Payment.bill(7);
    expect(after.single.paid, isTrue,
        reason: 'anggota yang baru dibayar offline tidak boleh tampil belum bayar');
    expect(after.single.paidAmount, 60000);
  });

  test('riwayat iuran offline tidak bocor ke turnamen lain', () async {
    // Panaskan cache untuk KEDUA turnamen saat online.
    await Payment.all(tournamentId: 7);
    await Payment.all(tournamentId: 9);

    server.offline = true;
    await Payment.insert(memberId: 5, amount: 60000, tournamentId: 7);

    // Query untuk turnamen 9 tidak boleh ketambahan baris turnamen 7.
    final other = await Payment.all(tournamentId: 9);
    expect(other, isEmpty,
        reason: 'iuran turnamen 7 tidak boleh muncul di turnamen 9');

    // Dan turnamen 7 tetap melihat barisnya.
    final mine = await Payment.all(tournamentId: 7);
    expect(mine, hasLength(1));
    expect(mine.single.tournamentId, 7);
  });
}
