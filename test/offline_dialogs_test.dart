// Tes: dialog-dialog yang dipakai di lapangan harus tetap terbuka saat offline.
//
// Semua bug di sini berasal dari pola yang sama: sebuah dialog melakukan
// pembacaan ke server SEBELUM menyimpan (untuk mengisi nilai awal atau memeriksa
// duplikat). Saat offline, bacaan itu melempar, lalu dialognya menampilkan
// "Gagal ..." dan tidak pernah membuka form — sehingga pencatatan yang
// seharusnya masuk antrean malah gagal total.
//
// Yang diuji di lapisan data: setiap operasi tulis harus berhasil (masuk
// antrean) walau pembacaan pendukungnya gagal.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minisoccer_club/core/cache.dart';
import 'package:minisoccer_club/core/cache_store.dart';
import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';
import 'package:minisoccer_club/core/offline.dart';
import 'package:minisoccer_club/data/models.dart' as model;

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

/// Server yang SELALU offline (meniru lapangan tanpa sinyal).
http.Client offlineClient() => MockClient((req) async {
      throw http.ClientException('Connection refused');
    });

void main() {
  setUp(() {
    useClient(offlineClient());
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

  group('tulis tetap berhasil walau pembacaan pendukung gagal', () {
    test('catat iuran: pemeriksaan duplikat gagal → tetap masuk antrean', () async {
      // Inilah bug yang membuat "Catat iuran" gagal total saat offline:
      // existsFor() melempar sebelum insert dijalankan.
      await model.Payment.insert(memberId: 5, amount: 60000, tournamentId: 7);

      expect(Outbox.pending.value, 1, reason: 'harus masuk antrean');
      final w = Outbox.items.single;
      expect(w.sql, contains('INSERT INTO payments'));
      expect(w.params['t'], 7);
      expect(w.params['amt'], 60000);
    });

    test('catat iuran berulang saat offline tidak melempar', () async {
      // Tanpa server, duplikat tidak bisa diperiksa. Yang penting: tidak
      // melempar, dan database tetap punya index unik sebagai penjaga.
      await model.Payment.insert(memberId: 5, amount: 60000, tournamentId: 7);
      await model.Payment.insert(memberId: 5, amount: 60000, tournamentId: 7);
      expect(Outbox.pending.value, 2);
    });

    test('selesaikan laga: rincian sesi gagal dibaca → tetap masuk antrean', () async {
      final match = model.Match(
        id: 9,
        playedAt: DateTime(2026, 10, 1),
        status: 'ongoing',
        goalsFor: 1,
        goalsAgainst: 1,
      );

      await match.finish(gf: 2, ga: 0);

      expect(Outbox.pending.value, 1);
      expect(Outbox.items.single.params['gf'], 2,
          reason: 'angka dari dialog dipakai saat rincian tidak terbaca');
      expect(Outbox.items.single.params['ga'], 0);
    });

    test('ubah jadwal laga: cek status gagal → tetap masuk antrean', () async {
      final match = model.Match(
        id: 9,
        playedAt: DateTime(2026, 10, 1),
        status: 'scheduled',
        goalsFor: 0,
        goalsAgainst: 0,
        homeTeamId: 1,
        awayTeamId: 2,
      );

      await match.update(
        homeTeamId: 3,
        awayTeamId: 4,
        playedAt: DateTime(2026, 10, 2),
      );

      expect(Outbox.pending.value, 1);
      expect(Outbox.items.single.sql, contains('UPDATE matches'));
    });

    test('baca yang gagal tetap melempar (tidak diam-diam kosong)', () async {
      // Kebalikannya juga penting: pembacaan tidak boleh menelan kegagalan dan
      // mengembalikan daftar kosong, karena halaman akan menampilkan
      // "belum ada data" padahal datanya ada.
      await expectLater(model.Payment.bill(7), throwsA(isA<ApiException>()));
      await expectLater(model.Member.all(), throwsA(isA<ApiException>()));
    });
  });

  group('iuran offline: tidak dobel, tidak bocor', () {
    test('iuran offline muncul di antrean dengan turnamen yang benar', () async {
      await model.Payment.insert(memberId: 11, amount: 75000, tournamentId: 3);
      final w = Outbox.items.single;
      expect(w.params['t'], 3);
      expect(w.params['mid'], 11);
    });
  });
}
