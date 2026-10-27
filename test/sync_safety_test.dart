// Tes keamanan sinkron: hal-hal yang kalau salah membuat data pengguna HILANG
// tanpa pesan. Semua kasus di sini berasal dari audit dan pernah berpotensi
// terjadi pada kode sebelumnya.
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/core/offline.dart';

/// Server palsu dengan kendali penuh atas hasil tiap tulis.
class FakeServer {
  bool offline = false;

  /// Tabel yang ditolak permanen (meniru galat dari server).
  final Set<String> reject = {};

  /// Berapa baris yang "terkena" UPDATE/DELETE. 0 meniru baris yang sudah
  /// tidak ada di cloud.
  int affectedRows = 1;

  final List<(String, Map<String, Object?>)> received = [];

  Future<List<Map<String, dynamic>>> query(
    String sql,
    Map<String, Object?> params, {
    String? writeId,
  }) async {
    if (offline) throw Exception('Tidak bisa menghubungi server');
    for (final t in reject) {
      if (sql.toLowerCase().contains(t.toLowerCase())) {
        throw Exception('Query gagal dijalankan');
      }
    }
    received.add((sql, params));
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
    for (final t in reject) {
      if (sql.toLowerCase().contains(t.toLowerCase())) {
        throw Exception('Query gagal dijalankan');
      }
    }
    received.add((sql, params));
    return affectedRows;
  }

  Future<SyncResult> flush({bool Function(Object)? isAuthExpired}) => Outbox.flush(
        query: query,
        execute: execute,
        isAuthExpired: isAuthExpired,
      );
}

void main() {
  setUp(Outbox.resetForTest);

  group('id sementara yang tidak punya padanan tidak dikirim ke server', () {
    test('anak dari insert yang gagal ditandai gagal, bukan dikirim', () async {
      // Induk (tim) ditolak server → tidak ada id asli.
      final teamTemp = await Outbox.enqueue(
        'INSERT INTO teams (name) VALUES (@n) RETURNING id',
        {'n': 'Tim Baru'},
      );
      // Anak menunjuk id sementara itu.
      await Outbox.enqueue(
        'INSERT INTO team_players (team_id, member_id) VALUES (@t, @m)',
        {'t': teamTemp, 'm': 1},
      );

      final server = FakeServer()..reject.add('teams');
      final result = await server.flush();

      expect(result.failed, 2, reason: 'induk dan anaknya sama-sama gagal');
      expect(result.remaining, 2);

      // Yang penting: anak TIDAK pernah dikirim dengan id negatif.
      final sentPlayer = server.received.where(
        (r) => r.$1.toLowerCase().contains('team_players'),
      );
      expect(sentPlayer, isEmpty,
          reason: 'mengirim id negatif hanya akan ditolak FK dan membingungkan');
      expect(Outbox.items.last.lastError, contains('induk'));
    });

    test('rantai yang berhasil tetap terkirim dengan id asli', () async {
      final teamTemp = await Outbox.enqueue(
        'INSERT INTO teams (name) VALUES (@n) RETURNING id',
        {'n': 'Tim A'},
      );
      await Outbox.enqueue(
        'INSERT INTO team_players (team_id, member_id) VALUES (@t, @m)',
        {'t': teamTemp, 'm': 5},
      );

      final result = await FakeServer().flush();

      expect(result.sent, 2);
      expect(result.failed, 0);
    });
  });

  group('UPDATE/DELETE yang tidak mengenai baris apa pun', () {
    test('ditandai gagal, bukan dilaporkan terkirim', () async {
      await Outbox.enqueue(
        'UPDATE members SET name=@n WHERE id=@id',
        {'n': 'Nama Baru', 'id': 7},
      );
      // Server bilang 0 baris terpengaruh: barisnya sudah dihapus admin lain.
      final server = FakeServer()..affectedRows = 0;
      final result = await server.flush();

      expect(result.sent, 0, reason: 'jangan bilang "terkirim" kalau tidak ada yang berubah');
      expect(result.failed, 1);
      expect(Outbox.items.single.lastError, contains('tidak ada di server'));
    });

    test('UPDATE yang mengenai baris tetap dihitung terkirim', () async {
      await Outbox.enqueue(
        'UPDATE members SET name=@n WHERE id=@id',
        {'n': 'Nama Baru', 'id': 7},
      );
      final server = FakeServer()..affectedRows = 1;
      final result = await server.flush();

      expect(result.sent, 1);
      expect(result.failed, 0);
    });

    test('INSERT tidak terpengaruh aturan rowCount', () async {
      await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'A'});
      // INSERT mengembalikan rowCount 0 pada beberapa driver; itu bukan alasan
      // menandai gagal.
      final server = FakeServer()..affectedRows = 0;
      final result = await server.flush();

      expect(result.sent, 1);
      expect(result.failed, 0);
    });
  });

  group('sesi habis saat sinkron', () {
    test('dilaporkan authExpired, antrean tetap utuh', () async {
      await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'A'});

      final server = FakeServer()..offline = true;
      // Tiru Unauthorized: bukan kegagalan jaringan, tapi harus dicoba lagi
      // nanti (setelah pengguna masuk).
      final result = await Outbox.flush(
        query: (sql, params, {String? writeId}) async =>
            throw Exception('Sesi habis, silakan login ulang'),
        execute: (sql, params, {String? writeId}) async =>
            throw Exception('Sesi habis, silakan login ulang'),
        isRetryable: (e) => e.toString().contains('Sesi habis'),
        isAuthExpired: (e) => e.toString().contains('Sesi habis'),
      );

      expect(result.authExpired, isTrue);
      expect(result.offline, isFalse,
          reason: 'pengguna harus tahu ia perlu masuk lagi, bukan menunggu sinyal');
      expect(result.remaining, 1, reason: 'antrean tidak boleh dibuang');
      expect(server.received, isEmpty);
    });
  });

  group('antrean bercampur: sebagian gagal, sebagian berhasil', () {
    test('yang berhasil terkirim, yang gagal disimpan untuk dilihat', () async {
      await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'A'});
      await Outbox.enqueue('INSERT INTO tabel_rusak (x) VALUES (@x)', {'x': 1});
      await Outbox.enqueue('INSERT INTO members (name) VALUES (@n)', {'n': 'B'});

      final server = FakeServer()..reject.add('tabel_rusak');
      final result = await server.flush();

      expect(result.sent, 2);
      expect(result.failed, 1);
      expect(Outbox.pending.value, 1);
      expect(Outbox.failedCount, 1);
      // Urutan tulis yang berhasil harus tetap A lalu B.
      final names = server.received
          .where((r) => r.$1.contains('members'))
          .map((r) => r.$2['n'])
          .toList();
      expect(names, ['A', 'B']);
    });
  });
}
