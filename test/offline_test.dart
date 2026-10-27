// Tes antrean tulis offline (`offline.dart`).
//
// Yang diuji adalah perilaku yang menentukan apakah data offline benar-benar
// sampai ke cloud: urutan kirim, pemetaan id sementara, dan pemisahan antara
// "masih offline" (coba lagi) vs "server menolak" (jangan blokir antrean).
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/core/offline.dart';

/// Server palsu yang bisa diatur gagal/berhasil.
class FakeServer {
  FakeServer();

  final List<(String, Map<String, Object?>)> received = [];
  bool offline = false;
  final Set<String> reject = {};

  Future<List<Map<String, dynamic>>> query(
    String sql,
    Map<String, Object?> params, {
    String? writeId,
  }) async {
    if (offline) throw Exception('Tidak bisa menghubungi server');
    if (reject.any((r) => sql.contains(r))) {
      throw Exception('Query gagal dijalankan');
    }
    received.add((sql, params));
    // Tiru INSERT ... RETURNING id: id asli berurutan.
    if (RegExp(r'returning\s+id', caseSensitive: false).hasMatch(sql)) {
      return [
        {'id': received.length},
      ];
    }
    return const [];
  }

  Future<int> execute(
    String sql,
    Map<String, Object?> params, {
    String? writeId,
  }) async {
    if (offline) throw Exception('Tidak bisa menghubungi server');
    if (reject.any((r) => sql.contains(r))) {
      throw Exception('Query gagal dijalankan');
    }
    received.add((sql, params));
    return 1;
  }

  Future<SyncResult> flush() => Outbox.flush(query: query, execute: execute);
}

void main() {
  setUp(Outbox.resetForTest);

  test('tulis masuk antrean dan mengembalikan id sementara untuk RETURNING id',
      () async {
    final tempId = await Outbox.enqueue('INSERT INTO teams (name) VALUES (@n) RETURNING id', {
      'n': 'Tim A',
    });
    expect(tempId, isNotNull);
    expect(tempId! < 0, isTrue, reason: 'id sementara harus negatif');
    expect(Outbox.pending.value, 1);
  });

  test('tulis biasa tidak dapat id sementara', () async {
    final tempId = await Outbox.enqueue(
      'INSERT INTO members (name) VALUES (@n)',
      {'n': 'Budi'},
    );
    expect(tempId, isNull);
  });

  test('sinkron mengirim berurutan dan mengosongkan antrean', () async {
    await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'A'});
    await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'B'});
    final server = FakeServer();

    final result = await server.flush();

    expect(result.sent, 2);
    expect(result.remaining, 0);
    expect(Outbox.pending.value, 0);
    expect(server.received.map((e) => e.$2['n']).toList(), ['A', 'B'],
        reason: 'urutan asli harus dipertahankan');
  });

  test('id sementara diganti id asli pada tulis berikutnya', () async {
    // Skenario nyata: buat tim offline, lalu tambah pemain ke tim itu.
    final teamTemp = await Outbox.enqueue(
      'INSERT INTO teams (name) VALUES (@n) RETURNING id',
      {'n': 'Tim Baru'},
    );
    await Outbox.enqueue(
      'INSERT INTO team_players (team_id, member_id) VALUES (@t, @m)',
      {'t': teamTemp, 'm': 5},
    );

    final server = FakeServer();
    await server.flush();

    final playerInsert = server.received.last;
    expect(playerInsert.$2['t'], 1,
        reason: 'id sementara $teamTemp harus diganti id asli dari server');
    expect(playerInsert.$2['m'], 5);
  });

  test('pemetaan id bertahan untuk rantai tiga tulis', () async {
    final teamTemp = await Outbox.enqueue(
      'INSERT INTO teams (name) VALUES (@n) RETURNING id',
      {'n': 'Tim X'},
    );
    await Outbox.enqueue(
      'INSERT INTO team_players (team_id, member_id) VALUES (@t, @m)',
      {'t': teamTemp, 'm': 1},
    );
    await Outbox.enqueue(
      'UPDATE teams SET name=@n WHERE id=@id',
      {'n': 'Tim X Baru', 'id': teamTemp},
    );

    final server = FakeServer();
    await server.flush();

    expect(server.received[1].$2['t'], 1);
    expect(server.received[2].$2['id'], 1,
        reason: 'UPDATE juga harus memakai id asli, bukan id sementara');
  });

  test('masih offline: antrean tetap utuh dan tidak ada yang hilang', () async {
    await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'A'});
    await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'B'});
    final server = FakeServer()..offline = true;

    final result = await server.flush();

    expect(result.sent, 0);
    expect(result.offline, isTrue);
    expect(result.remaining, 2);
    expect(Outbox.pending.value, 2);
  });

  test('server menolak satu tulis: ditandai gagal, sisanya tetap dikirim',
      () async {
    await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'A'});
    await Outbox.enqueue('INSERT INTO bad_table (x) VALUES (@n)', {'n': 'B'});
    await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'C'});
    final server = FakeServer()..reject.add('bad_table');

    final result = await server.flush();

    expect(result.sent, 2, reason: 'satu tulis rusak tidak boleh memblokir sisanya');
    expect(result.failed, 1);
    expect(result.remaining, 1);
    expect(Outbox.failedCount, 1);
    expect(Outbox.items.single.lastError, isNotNull);
  });

  test('tulis yang gagal permanen tidak dikirim ulang', () async {
    await Outbox.enqueue('INSERT INTO bad_table (x) VALUES (@n)', {'n': 'B'});
    final server = FakeServer()..reject.add('bad_table');
    await server.flush();
    final firstCount = server.received.length;

    server.reject.clear(); // server "diperbaiki"
    final second = await server.flush();

    expect(second.sent, 0);
    expect(server.received.length, firstCount,
        reason: 'yang sudah ditandai gagal tidak boleh dicoba otomatis lagi');
  });

  test('tulis gagal bisa dibuang pengguna', () async {
    await Outbox.enqueue('INSERT INTO bad_table (x) VALUES (@n)', {'n': 'B'});
    final server = FakeServer()..reject.add('bad_table');
    await server.flush();
    expect(Outbox.pending.value, 1);

    await Outbox.removeFailed();
    expect(Outbox.pending.value, 0);
  });

  test('clear membuang seluruh antrean', () async {
    await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'A'});
    await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'B'});
    await Outbox.clear();
    expect(Outbox.pending.value, 0);
    expect(Outbox.items, isEmpty);
  });

  test('flush saat antrean kosong tidak menyentuh server', () async {
    final server = FakeServer();
    final result = await server.flush();
    expect(result.sent, 0);
    expect(server.received, isEmpty);
  });
}
