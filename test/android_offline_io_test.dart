// Tes jalur berkas offline yang dipakai di ANDROID.
//
// Kenapa tes ini penting: web menyimpan cache di localStorage, sementara
// Android memakai berkas JSON (`cache_io.dart`, `outbox_store_io.dart`).
// Sebelum tes ini ada, kode tersebut belum pernah dijalankan sama sekali di
// lingkungan mana pun — unit test memakai cache memori, dan uji browser hanya
// menguji web. Artinya bug di jalur Android (mis. JSON tidak terbaca lagi,
// antrean hilang saat app ditutup) tidak akan ketahuan sampai dipakai di HP.
//
// Di sini `getApplicationSupportDirectory` dipalsukan ke direktori sementara,
// jadi yang berjalan adalah kode Android yang sesungguhnya: tulis berkas, baca
// berkas, dan pemulihan setelah "app ditutup".
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minisoccer_club/core/cache.dart';
import 'package:minisoccer_club/core/cache_io.dart';
import 'package:minisoccer_club/core/cache_store.dart';
import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';
import 'package:minisoccer_club/core/offline.dart';
import 'package:minisoccer_club/core/outbox_store_io.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// `path_provider` palsu: mengarahkan direktori app ke folder sementara.
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

/// Server palsu untuk menguji sinkron.
class _FakeServer {
  bool offline = false;
  final List<(String, Map<String, Object?>)> writes = [];

  http.Client get client => MockClient((req) async {
        if (offline) throw http.ClientException('Connection refused');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final sql = (body['sql'] as String).trim();
        final params = (body['params'] as Map?)?.cast<String, Object?>() ?? const {};
        final upper = sql.toUpperCase();
        if (upper.startsWith('INSERT') || upper.startsWith('UPDATE') || upper.startsWith('DELETE')) {
          writes.add((sql, params));
          return http.Response('{"rows":[],"rowCount":1}', 200);
        }
        return http.Response('{"rows":[],"rowCount":0}', 200);
      });
}

void main() {
  late Directory temp;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('msc_io_test_');
    PathProviderPlatform.instance = _FakePathProvider(temp.path);
  });

  tearDownAll(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {
      // Sisa berkas tidak menggagalkan tes.
    }
  });

  setUp(() {
    // Mulai bersih: direktori cache dan berkas antrean dihapus tiap tes.
    final cacheDir = Directory('${temp.path}/query_cache');
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
    final outbox = File('${temp.path}/outbox.json');
    if (outbox.existsSync()) outbox.deleteSync();
    final tmpOutbox = File('${temp.path}/outbox.json.tmp');
    if (tmpOutbox.existsSync()) tmpOutbox.deleteSync();

    useCacheStore(FileCacheStore());
    Outbox.resetForTest();
    Db.offline.value = false;
    Db.offlineSince = null;
  });

  tearDown(() {
    useClient(http.Client());
    resetCacheStore();
    Outbox.resetForTest();
  });

  group('FileCacheStore (berkas JSON di Android)', () {
    final entry = CacheEntry(
      key: 'k1',
      sql: 'SELECT * FROM members ORDER BY name',
      params: const {'active': true},
      rows: [
        {'id': 1, 'name': 'Ani'},
      ],
      savedAt: DateTime.now(),
    );

    test('tulis lalu baca kembali dari disk', () async {
      final store = FileCacheStore();
      await store.writeEntry(entry);

      // Instance BARU: membaca dari berkas, bukan dari memori.
      final fresh = FileCacheStore();
      final hit = await fresh.readRows('k1');
      expect(hit, isNotNull);
      expect(hit!.rows.single['name'], 'Ani');
    });

    test('listEntries mengembalikan sql & params asli (bahan penambal)', () async {
      await FileCacheStore().writeEntry(entry);
      final list = await FileCacheStore().listEntries();
      expect(list, hasLength(1));
      expect(list.single.sql, entry.sql);
      expect(list.single.params['active'], true);
      expect(list.single.key, 'k1');
    });

    test('entri lama tanpa sql dilewati (tidak bisa ditambal)', () async {
      final dir = Directory('${temp.path}/query_cache')..createSync(recursive: true);
      File('${dir.path}/legacy.json').writeAsStringSync(
        jsonEncode({
          'saved_at': DateTime.now().toIso8601String(),
          'rows': [
            {'id': 1},
          ],
        }),
      );
      final list = await FileCacheStore().listEntries();
      expect(list, isEmpty, reason: 'entri tanpa sql tidak boleh ikut ditambal');
    });

    test('berkas rusak tidak menggagalkan entri lain', () async {
      await FileCacheStore().writeEntry(entry);
      final dir = Directory('${temp.path}/query_cache');
      File('${dir.path}/rusak.json').writeAsStringSync('{ bukan json');

      final list = await FileCacheStore().listEntries();
      expect(list, hasLength(1), reason: 'satu berkas rusak tidak boleh menghapus sisanya');
      expect(list.single.key, 'k1');
    });

    test('clear membuang semua berkas cache', () async {
      final store = FileCacheStore();
      await store.writeEntry(entry);
      final removed = await store.clear();
      expect(removed, greaterThan(0));
      expect(await FileCacheStore().listEntries(), isEmpty);
      expect(await FileCacheStore().readRows('k1'), isNull);
    });

    test('readRows untuk kunci yang tidak ada mengembalikan null', () async {
      expect(await FileCacheStore().readRows('tidak-ada'), isNull);
    });
  });

  group('outbox_store_io (antrean di berkas)', () {
    test('tulis lalu baca kembali', () async {
      await writeOutbox('{"items":[],"seq":3}');
      expect(await readOutbox(), '{"items":[],"seq":3}');
    });

    test('tidak meninggalkan berkas .tmp setelah menulis', () async {
      await writeOutbox('{"items":[]}');
      expect(File('${temp.path}/outbox.json.tmp').existsSync(), isFalse,
          reason: 'berkas sementara harus sudah di-rename');
    });

    test('belum pernah menulis → null, bukan error', () async {
      expect(await readOutbox(), isNull);
    });
  });

  group('antrean offline bertahan setelah app ditutup (Android)', () {
    const insertMember = 'INSERT INTO members (name, phone, position, jersey) '
        'VALUES (@name, @phone, @position, @jersey)';

    test('tulis offline tersimpan ke disk dan pulih setelah restart', () async {
      final server = _FakeServer()..offline = true;
      useClient(server.client);

      await Db.execute(insertMember, params: {
        'name': 'Budi', 'phone': null, 'position': 'Bek', 'jersey': 4,
      });
      expect(Outbox.pending.value, 1);

      // Simulasikan app ditutup: lupakan memori, baca ulang dari berkas.
      Outbox.reloadFromDiskForTest();
      await Outbox.load();

      expect(Outbox.pending.value, 1,
          reason: 'antrean harus terbaca lagi dari berkas setelah app dibuka ulang');
      expect(Outbox.items.single.sql, insertMember);
      expect(Outbox.items.single.params['name'], 'Budi');
    });

    test('setelah restart, antrean tetap bisa dikirim saat online', () async {
      final server = _FakeServer()..offline = true;
      useClient(server.client);
      await Db.execute(insertMember, params: {
        'name': 'Citra', 'phone': null, 'position': 'Kiper', 'jersey': 1,
      });

      Outbox.reloadFromDiskForTest();
      await Outbox.load();

      server.offline = false;
      final result = await Db.sync();

      expect(result.sent, 1);
      expect(server.writes.single.$2['name'], 'Citra');
      expect(Outbox.pending.value, 0);
    });

    test('cache yang ditambal tersimpan di disk, bukan hanya di memori', () async {
      final server = _FakeServer();
      useClient(server.client);

      // Online dulu: cache daftar anggota tersimpan ke berkas.
      const selectMembers = 'SELECT * FROM members ORDER BY name';
      await Db.query(selectMembers);
      expect(await FileCacheStore().listEntries(), isNotEmpty);

      // Offline: tambah anggota.
      server.offline = true;
      await Db.execute(insertMember, params: {
        'name': 'Dewi', 'phone': null, 'position': 'Bebas', 'jersey': null,
      });

      // Baca lewat store BARU (dari disk) — inilah yang terjadi saat app dibuka
      // lagi di HP: cache dimuat dari berkas, bukan dari memori.
      final entries = await FileCacheStore().listEntries();
      final memberEntry = entries.firstWhere((e) => e.sql == selectMembers);
      expect(
        memberEntry.rows.map((r) => r['name']),
        contains('Dewi'),
        reason: 'tambahan offline harus ikut tersimpan di berkas cache',
      );
      // Dan barisnya harus lengkap: id + joined_at, supaya bisa dibaca model.
      final added = memberEntry.rows.firstWhere((r) => r['name'] == 'Dewi');
      expect(added['id'], isNotNull);
      expect(added['joined_at'], isNotNull);
    });

    test('sinkron berhasil membuang cache di disk', () async {
      final server = _FakeServer();
      useClient(server.client);

      // Online dulu supaya ada cache yang tersimpan di disk.
      await Db.query('SELECT * FROM members ORDER BY name');
      expect(await FileCacheStore().listEntries(), isNotEmpty);

      // Lalu offline dan menulis.
      server.offline = true;
      await Db.execute(insertMember, params: {
        'name': 'Eka', 'phone': null, 'position': 'Bek', 'jersey': 2,
      });

      server.offline = false;
      await Db.sync();

      expect(await FileCacheStore().listEntries(), isEmpty,
          reason: 'cache lama harus dibuang supaya pembacaan berikutnya dari server');
    });

    test('antrean kosong setelah sinkron tidak tersisa di berkas', () async {
      final server = _FakeServer()..offline = true;
      useClient(server.client);
      await Db.execute(insertMember, params: {
        'name': 'Fajar', 'phone': null, 'position': 'Bebas', 'jersey': null,
      });

      server.offline = false;
      await Db.sync();

      Outbox.reloadFromDiskForTest();
      await Outbox.load();
      expect(Outbox.pending.value, 0,
          reason: 'berkas antrean harus benar-benar kosong, bukan hanya memorinya');
    });
  });
}
