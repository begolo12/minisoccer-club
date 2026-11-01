// Sematan pengumuman + penanda "sudah dilihat" per akun.
//
// Yang dijaga di sini:
//   * `pinned_at` terbaca model (null = tidak disematkan),
//   * query daftar benar-benar mengurutkan sematan ke atas (SQL-nya diperiksa
//     lewat pencegatan transport, bukan diasumsikan),
//   * penanda dibaca per akun — akun lain di perangkat yang sama tidak ikut
//     "sudah melihat", dan akun baru tidak menyalakan badge untuk SEMUA
//     pengumuman (itu derau, bukan informasi),
//   * id sementara dari tulis offline (negatif) tidak pernah jadi penanda.
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';
import 'package:minisoccer_club/data/models.dart';

Announcement _ann(int id, {String? pinnedAt}) => Announcement(
      id: id,
      title: 't$id',
      body: 'b',
      pinnedAt: pinnedAt == null ? null : DateTime.parse(pinnedAt),
      createdAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Announcement.fromMap', () {
    test('pinned_at null berarti tidak disematkan', () {
      final a = Announcement.fromMap({
        'id': 1,
        'title': 't',
        'body': 'b',
        'pinned_at': null,
        'created_at': '2026-10-01T00:00:00.000Z',
      });
      expect(a.pinned, isFalse);
      expect(a.pinnedAt, isNull);
    });

    test('pinned_at ISO terurai jadi waktu', () {
      final a = Announcement.fromMap({
        'id': 1,
        'title': 't',
        'body': 'b',
        'pinned_at': '2026-10-02T03:04:05.000Z',
        'created_at': '2026-10-01T00:00:00.000Z',
      });
      expect(a.pinned, isTrue);
      // `_dt` menormalkan ke waktu lokal (konvensi model); bandingkan
      // momennya, bukan representasi zona waktunya.
      expect(a.pinnedAt!.toUtc(), DateTime.utc(2026, 10, 2, 3, 4, 5));
    });

    test('baris lama tanpa kolom pinned_at tetap terbaca', () {
      // Cache offline dari versi sebelum fitur ini tidak punya kuncinya sama
      // sekali; fromMap tidak boleh menuntut kolomnya ada.
      final a = Announcement.fromMap({
        'id': 1,
        'title': 't',
        'body': 'b',
        'created_at': '2026-10-01T00:00:00.000Z',
      });
      expect(a.pinned, isFalse);
    });
  });

  group('Announcement.all', () {
    test('query mengurutkan sematan ke atas, lalu tanggal terbit', () async {
      String? sql;
      useClient(MockClient((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        sql = body['sql'] as String;
        return http.Response('{"rows":[],"rowCount":0}', 200);
      }));
      addTearDown(() => useClient(http.Client()));
      await Announcement.all();
      expect(sql, contains('pinned_at DESC NULLS LAST'));
      expect(sql, contains('created_at DESC'));
    });
  });

  group('AnnouncementSeen', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      Db.cacheScope = 'admin:7';
    });
    tearDown(() => Db.cacheScope = 'public');

    test('tanpa riwayat: null, bukan 0 — badge tidak menyala untuk semua',
        () async {
      expect(await AnnouncementSeen.lastId(), isNull);
    });

    test('mark pertama memasang penanda di id terbesar', () async {
      await AnnouncementSeen.mark([_ann(5), _ann(3)]);
      expect(await AnnouncementSeen.lastId(), 5);
    });

    test('penanda hanya maju: pengumuman dihapus tidak memundurkan', () async {
      await AnnouncementSeen.mark([_ann(9)]);
      await AnnouncementSeen.mark([_ann(4)]);
      expect(await AnnouncementSeen.lastId(), 9);
    });

    test('id sementara offline (negatif) diabaikan', () async {
      await AnnouncementSeen.mark([_ann(-1), _ann(2)]);
      expect(await AnnouncementSeen.lastId(), 2);
      // Hanya id negatif: tidak ada yang layak ditandai, penanda tetap.
      await AnnouncementSeen.mark([_ann(-5)]);
      expect(await AnnouncementSeen.lastId(), 2);
    });

    test('daftar kosong tidak menghapus penanda', () async {
      await AnnouncementSeen.mark([_ann(6)]);
      await AnnouncementSeen.mark(const []);
      expect(await AnnouncementSeen.lastId(), 6);
    });

    test('penanda terpisah per akun pada perangkat yang sama', () async {
      Db.cacheScope = 'admin:1';
      await AnnouncementSeen.mark([_ann(10)]);

      Db.cacheScope = 'member:2';
      expect(await AnnouncementSeen.lastId(), isNull,
          reason: 'akun lain tidak mewarisi status baca');
      await AnnouncementSeen.mark([_ann(4)]);
      expect(await AnnouncementSeen.lastId(), 4);

      Db.cacheScope = 'admin:1';
      expect(await AnnouncementSeen.lastId(), 10);
    });

    test('nilai rusak di penyimpanan dibaca sebagai null, bukan melempar',
        () async {
      FlutterSecureStorage.setMockInitialValues({
        'announcements_seen:admin:7': 'bukan-angka',
      });
      expect(await AnnouncementSeen.lastId(), 0);
    });
  });
}
