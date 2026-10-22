// Tes integrasi mode offline-first di lapisan `Db`.
//
// Ini yang membuktikan janji ke pengguna: **data bisa diisi saat offline,
// langsung terlihat, lalu terkirim otomatis saat online — dan data offline
// yang menang atas data cloud.**
//
// Jaringan dipalsukan lewat `useClient` (mock HTTP), cache lewat store memori,
// dan antrean direset tiap tes. Jadi yang diuji adalah jalur kode yang sama
// dengan yang dipakai di HP.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minisoccer_club/core/cache.dart';
import 'package:minisoccer_club/core/cache_store.dart';
import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';
import 'package:minisoccer_club/core/offline.dart';

/// Cache di memori: cukup untuk menguji penambalan tanpa filesystem.
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

/// Server palsu: bisa offline, bisa menolak tabel tertentu, dan mencatat
/// tulis yang diterima.
class FakeServer {
  bool offline = false;

  /// Nama tabel yang ditolak server (meniru `Query gagal dijalankan`).
  final Set<String> reject = {};
  final List<(String, Map<String, Object?>)> writes = [];
  final List<Map<String, dynamic>> members = [];
  int _nextId = 1;

  http.Client get client => MockClient((req) async {
        if (offline) {
          // Meniru kegagalan jaringan yang dikenali `isNetworkFailure`.
          throw http.ClientException('Connection refused');
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final sql = (body['sql'] as String).trim();
        final params = (body['params'] as Map?)?.cast<String, Object?>() ?? const {};
        final upper = sql.toUpperCase();

        for (final t in reject) {
          if (upper.contains(t.toUpperCase())) {
            return http.Response('{"error":"Query gagal dijalankan"}', 400);
          }
        }

        if (upper.startsWith('INSERT') || upper.startsWith('UPDATE') || upper.startsWith('DELETE')) {
          writes.add((sql, params));
          if (upper.contains('INSERT INTO MEMBERS')) {
            final row = <String, dynamic>{
              'id': _nextId++,
              'name': params['name'],
              'active': true,
            };
            members.add(row);
            return http.Response(
              jsonEncode({
                'rows': upper.contains('RETURNING') ? [row] : [],
                'rowCount': 1,
              }),
              200,
            );
          }
          return http.Response('{"rows":[],"rowCount":1}', 200);
        }

        // SELECT
        if (upper.contains('FROM MEMBERS')) {
          return http.Response(jsonEncode({'rows': members, 'rowCount': members.length}), 200);
        }
        return http.Response('{"rows":[],"rowCount":0}', 200);
      });
}

void main() {
  late FakeServer server;
  late MemoryCacheStore cache;

  setUp(() {
    server = FakeServer();
    cache = MemoryCacheStore();
    useCacheStore(cache);
    useClient(server.client);
    Outbox.resetForTest();
    Db.authToken = null;
    Db.offline.value = false;
    Db.offlineSince = null;
  });

  tearDown(() {
    useClient(http.Client());
    resetCacheStore();
    Outbox.resetForTest();
  });

  const selectMembers = 'SELECT * FROM members WHERE active ORDER BY name';
  const insertMember =
      'INSERT INTO members (name, phone, position, jersey) VALUES (@name, @phone, @position, @jersey)';

  test('online: tulis langsung ke server, tanpa antrean', () async {
    await Db.execute(insertMember, params: {
      'name': 'Ani', 'phone': null, 'position': 'Bek', 'jersey': 4,
    });

    expect(server.writes, hasLength(1));
    expect(Outbox.pending.value, 0);
    expect(Db.offline.value, isFalse);
  });

  test('offline: tulis masuk antrean, tidak hilang', () async {
    server.offline = true;

    await Db.execute(insertMember, params: {
      'name': 'Budi', 'phone': null, 'position': 'Kiper', 'jersey': 1,
    });

    expect(server.writes, isEmpty, reason: 'server tidak boleh menerima apa pun');
    expect(Outbox.pending.value, 1);
    expect(Db.offline.value, isTrue);
    expect(Db.pendingWrites, 1);
  });

  test('offline: data yang diisi langsung terlihat di halaman', () async {
    // 1. Online dulu supaya cache berisi daftar anggota.
    await Db.query(selectMembers);
    expect(cache.entries, isNotEmpty, reason: 'hasil baca harus tersimpan');

    // 2. Jaringan mati, lalu tambah anggota.
    server.offline = true;
    await Db.execute(insertMember, params: {
      'name': 'Citra', 'phone': null, 'position': 'Striker', 'jersey': 9,
    });

    // 3. Baca ulang: cache sudah ditambal, jadi Citra muncul.
    final rows = await Db.query(selectMembers);
    expect(rows.map((r) => r['name']), contains('Citra'),
        reason: 'tambahan offline harus langsung terlihat');
  });

  test('offline: INSERT ... RETURNING id memberi id sementara', () async {
    server.offline = true;

    final rows = await Db.query(
      'INSERT INTO teams (name) VALUES (@n) RETURNING id',
      params: {'n': 'Tim Offline'},
    );

    expect(rows, hasLength(1));
    final id = rows.first['id'] as int;
    expect(id < 0, isTrue, reason: 'id sementara harus negatif');
  });

  test('online kembali: antrean terkirim dan cache dibersihkan', () async {
    // Cache dulu saat online, supaya ada data untuk ditampilkan offline.
    await Db.query(selectMembers);

    server.offline = true;
    await Db.execute(insertMember, params: {
      'name': 'Dewi', 'phone': null, 'position': 'Bek', 'jersey': 3,
    });
    expect(Outbox.pending.value, 1);
    // Selama offline, anggota baru terlihat dari cache yang ditambal.
    final offlineRows = await Db.query(selectMembers);
    expect(offlineRows.map((r) => r['name']), contains('Dewi'));

    // Jaringan pulih.
    server.offline = false;
    final result = await Db.sync();

    expect(result.sent, 1);
    expect(result.remaining, 0);
    expect(Outbox.pending.value, 0);
    expect(server.writes, hasLength(1), reason: 'tulis offline harus sampai ke server');
    expect(server.members.map((m) => m['name']), contains('Dewi'));
    expect(cache.entries, isEmpty,
        reason: 'cache dibuang supaya pembacaan berikutnya ambil keadaan server');
    expect(Db.offline.value, isFalse);
  });

  test('sinkron gagal saat masih offline: antrean tetap ada', () async {
    server.offline = true;
    await Db.execute(insertMember, params: {
      'name': 'Eka', 'phone': null, 'position': 'Bek', 'jersey': 2,
    });

    final result = await Db.sync();

    expect(result.sent, 0);
    expect(result.offline, isTrue);
    expect(Outbox.pending.value, 1, reason: 'jangan sampai data pengguna hilang');
  });

  test('beberapa tulis offline terkirim berurutan saat online', () async {
    server.offline = true;
    for (final name in ['Fajar', 'Gita', 'Hadi']) {
      await Db.execute(insertMember, params: {
        'name': name, 'phone': null, 'position': 'Bebas', 'jersey': null,
      });
    }
    expect(Outbox.pending.value, 3);

    server.offline = false;
    final result = await Db.sync();

    expect(result.sent, 3);
    expect(server.members.map((m) => m['name']).toList(), ['Fajar', 'Gita', 'Hadi'],
        reason: 'urutan pengisian harus dipertahankan');
  });

  test('data offline menimpa data cloud (lokal diutamakan)', () async {
    // Cloud sudah punya nama lama.
    server.members.add({'id': 1, 'name': 'Nama Lama', 'active': true});

    // Offline: pengguna mengubah nama.
    server.offline = true;
    await Db.execute('UPDATE members SET name=@n WHERE id=@id', params: {
      'n': 'Nama Baru', 'id': 1,
    });
    expect(Outbox.pending.value, 1);

    // Online: antrean dikirim setelah keadaan cloud, jadi menimpa.
    server.offline = false;
    await Db.sync();

    expect(server.writes.last.$2['n'], 'Nama Baru');
    expect(server.writes.last.$1, contains('UPDATE members'));
  });

  test('tulis offline yang ditolak server ditandai, tidak memblokir', () async {
    server.offline = true;
    await Db.execute(insertMember, params: {
      'name': 'Iwan', 'phone': null, 'position': 'Bek', 'jersey': 1,
    });
    await Db.execute('INSERT INTO tabel_tidak_ada (x) VALUES (@x)', params: {'x': 1});
    expect(Outbox.pending.value, 2);

    server.offline = false;
    server.reject.add('tabel_tidak_ada');
    final result = await Db.sync();

    expect(result.sent, 1);
    expect(result.failed, 1);
    expect(Outbox.pending.value, 1, reason: 'yang gagal disimpan untuk dilihat pengguna');
    expect(Outbox.failedCount, 1);
  });

  test('baca yang tidak pernah di-cache saat offline tetap melempar', () async {
    server.offline = true;
    await expectLater(
      Db.query('SELECT * FROM something_never_read'),
      throwsA(isA<ApiException>()),
    );
  });

  test('tulis biasa (bukan RETURNING) offline tidak mengembalikan id', () async {
    server.offline = true;
    final rows = await Db.query(insertMember, params: {
      'name': 'Joko', 'phone': null, 'position': 'Bek', 'jersey': 5,
    });
    expect(rows, isEmpty);
  });

  test('antrean dibersihkan pengguna', () async {
    server.offline = true;
    await Db.execute(insertMember, params: {
      'name': 'Kiki', 'phone': null, 'position': 'Bek', 'jersey': 6,
    });
    expect(Outbox.pending.value, 1);

    await Db.clearOutbox();
    expect(Outbox.pending.value, 0);
    expect(Db.offline.value, isFalse);
  });
}
