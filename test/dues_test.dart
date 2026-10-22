// Tes iuran per turnamen.
//
// Perubahan sistem: iuran dulu per BULAN (`payments.period`), sekarang per
// TURNamen (`payments.tournament_id`) karena tim yang ikut tiap turnamen
// berbeda. Yang diuji di sini adalah hal-hal yang kalau salah membuat uang
// tercatat di tempat yang salah atau tagihan menuduh orang yang tidak ikut.
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

/// Server palsu yang mengembalikan baris sesuai bentuk query.
class FakeServer {
  final List<String> queries = [];
  final List<Map<String, Object?>> inserted = [];

  http.Client get client => MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final sql = (body['sql'] as String).trim();
        final params = (body['params'] as Map?)?.cast<String, Object?>() ?? const {};
        queries.add(sql.replaceAll(RegExp(r'\s+'), ' '));

        if (sql.toUpperCase().startsWith('INSERT INTO PAYMENTS')) {
          inserted.add(params);
          return http.Response('{"rows":[{"id":1}],"rowCount":1}', 200);
        }
        if (RegExp(r'SELECT 1 AS ok FROM payments').hasMatch(sql)) {
          return http.Response('{"rows":[],"rowCount":0}', 200);
        }
        if (RegExp(r'SELECT COALESCE\(sum\(amount\)').hasMatch(sql)) {
          return http.Response('{"rows":[{"total":"150000"}],"rowCount":1}', 200);
        }
        // Tagihan: satu anggota sudah bayar, satu belum.
        if (sql.contains('payment_id')) {
          return http.Response(
            jsonEncode({
              'rows': [
                {
                  'id': 1, 'name': 'Ani', 'phone': null, 'position': 'Bek',
                  'jersey': 4, 'active': true,
                  'joined_at': '2026-01-01T00:00:00.000Z',
                  'payment_id': 9, 'paid_amount': '50000',
                  'paid_at': '2026-10-20T00:00:00.000Z', 'paid_note': null,
                },
                {
                  'id': 2, 'name': 'Budi', 'phone': null, 'position': 'Kiper',
                  'jersey': 1, 'active': true,
                  'joined_at': '2026-01-01T00:00:00.000Z',
                  'payment_id': null, 'paid_amount': null,
                  'paid_at': null, 'paid_note': null,
                },
              ],
              'rowCount': 2,
            }),
            200,
          );
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
  });

  tearDown(() {
    useClient(http.Client());
    resetCacheStore();
    Outbox.resetForTest();
  });

  group('tagihan turnamen', () {
    test('memisahkan yang sudah bayar dan yang belum', () async {
      final bill = await Payment.bill(7);

      expect(bill, hasLength(2));
      final ani = bill.firstWhere((r) => r.member.name == 'Ani');
      final budi = bill.firstWhere((r) => r.member.name == 'Budi');
      expect(ani.paid, isTrue);
      expect(ani.paidAmount, 50000);
      expect(budi.paid, isFalse, reason: 'payment_id null = belum bayar');
      expect(budi.paidAmount, 0);
    });

    test('query tagihan memakai turnamen, bukan periode', () async {
      await Payment.bill(7);
      final q = server.queries.firstWhere((s) => s.contains('payment_id'));
      expect(q, contains('tournament_id'));
      expect(q, isNot(contains('period')));
    });

    test('uang terkumpul dijumlahkan dari database', () async {
      expect(await Payment.collectedFor(7), 150000);
    });
  });

  group('catat iuran', () {
    test('menyimpan tournament_id, bukan period', () async {
      await Payment.insert(memberId: 2, amount: 50000, tournamentId: 7);

      expect(server.inserted, hasLength(1));
      expect(server.inserted.single['t'], 7);
      expect(server.inserted.single.containsKey('period'), isFalse);
    });

    test('cek duplikat memakai anggota + turnamen', () async {
      // existsFor mengembalikan false di server palsu, jadi insert lanjut.
      await Payment.existsFor(2, 7);
      final q = server.queries.firstWhere((s) => s.contains('SELECT 1 AS ok'));
      expect(q, contains('member_id=@mid'));
      expect(q, contains('tournament_id=@t'));
    });
  });

  group('Tournament.entryFee', () {
    test('dibaca dari kolom entry_fee', () {
      final t = Tournament.fromMap({
        'id': 1, 'name': 'Turnamen A', 'venue': null,
        'starts_at': '2026-11-01T10:00:00.000Z',
        'match_minutes': 20, 'break_minutes': 0, 'groups': 1,
        'entry_fee': '75000', 'status': 'draft',
      });
      expect(t.entryFee, 75000);
    });

    test('database lama tanpa entry_fee tidak melempar', () {
      // Baris dari database yang belum dimigrasi: kolom tidak ada → 0.
      final t = Tournament.fromMap({
        'id': 1, 'name': 'Turnamen A', 'venue': null,
        'starts_at': '2026-11-01T10:00:00.000Z',
        'match_minutes': 20, 'break_minutes': 0, 'groups': 1,
        'status': 'draft',
      });
      expect(t.entryFee, 0);
    });
  });

  group('iuran dan kas', () {
    test('pembayaran punya nama turnamen untuk ditampilkan', () {
      final p = Payment.fromMap({
        'id': 1, 'member_id': 2, 'member_name': 'Budi',
        'amount': '50000', 'tournament_id': 7,
        'tournament_name': 'Turnamen Akhir Tahun',
        'paid_at': '2026-10-20T00:00:00.000Z', 'note': null,
      });
      expect(p.tournamentId, 7);
      expect(p.tournamentName, 'Turnamen Akhir Tahun');
    });

    test('pembayaran lama tanpa turnamen tidak melempar', () {
      final p = Payment.fromMap({
        'id': 1, 'member_id': 2, 'member_name': 'Budi',
        'amount': '50000', 'tournament_id': null,
        'tournament_name': null,
        'paid_at': '2026-10-20T00:00:00.000Z', 'note': null,
      });
      expect(p.tournamentId, isNull);
      expect(p.tournamentName, '');
    });

    test('kas bulanan memfilter dari paid_at, bukan periode', () async {
      await Payment.inMonth(DateTime(2026, 10));
      final q = server.queries.firstWhere((s) => s.contains('p.paid_at >='));
      expect(q, contains('paid_at'));
      expect(q, isNot(contains('period')));
    });
  });
}
