// Tes penambal cache offline (`row_patch.dart`).
//
// Penambal inilah yang membuat "isi data saat offline langsung terlihat".
// Kalau salah, pengguna melihat data karangan — lebih buruk daripada tidak
// menampilkan apa-apa. Karena itu setiap bentuk SQL yang dipakai app diuji
// dengan string aslinya, bukan versi yang disederhanakan.
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/core/row_patch.dart';

void main() {
  group('parseWrite: INSERT', () {
    test('kolom + parameter terbaca', () {
      final op = parseWrite(
        'INSERT INTO members (name, phone, position, jersey) '
        'VALUES (@name, @phone, @position, @jersey)',
        {'name': 'Budi', 'phone': '0812', 'position': 'Kiper', 'jersey': 1},
      )!;
      expect(op.kind, 'insert');
      expect(op.table, 'members');
      expect(op.patchable, isTrue);
      expect(op.values, {
        'name': 'Budi',
        'phone': '0812',
        'position': 'Kiper',
        'jersey': 1,
      });
    });

    test('literal string dan NULL ikut terbaca', () {
      final op = parseWrite(
        "INSERT INTO transactions (kind, category, amount, note, booking_id) "
        "VALUES ('expense', 'sewa', @amount, @note, @booking)",
        {'amount': 350000, 'note': "Sewa O'Brien", 'booking': 7},
      )!;
      expect(op.values['kind'], 'expense');
      expect(op.values['category'], 'sewa');
      expect(op.values['amount'], 350000);
      // Nama kolom `booking_id`, nama parameter `@booking` — keduanya berbeda
      // dan tidak boleh tertukar.
      expect(op.values['booking_id'], 7);
      expect(op.values['note'], "Sewa O'Brien",
          reason: 'kutip di dalam teks tidak boleh memotong nilai');
    });

    test('RETURNING id dikenali', () {
      final op = parseWrite(
        'INSERT INTO teams (name) VALUES (@n) RETURNING id',
        {'n': 'Tim A'},
      )!;
      expect(op.returnsId, isTrue);
    });

    test('ON CONFLICT (kolom) menyimpan kunci upsert', () {
      final op = parseWrite(
        'INSERT INTO match_sessions (match_id, session_no, score_home) '
        'VALUES (@m, @sn, @h) ON CONFLICT (match_id, session_no) DO UPDATE SET score_home=@h',
        {'m': 1, 'sn': 2, 'h': 3},
      )!;
      expect(op.conflictCols, ['match_id', 'session_no']);
    });

    test('INSERT banyak baris tidak ditambal (bukan urusan penambal)', () {
      final op = parseWrite(
        'INSERT INTO tournament_teams (tournament_id, team_id, group_no) '
        'VALUES (@t, @team0, @g0),(@t, @team1, @g1) ON CONFLICT DO NOTHING',
        {'t': 1, 'team0': 1, 'g0': 1, 'team1': 2, 'g1': 2},
      )!;
      expect(op.patchable, isFalse);
    });

    test('nilai yang tidak bisa dihitung di klien → tidak ditambal', () {
      final op = parseWrite(
        "INSERT INTO transactions (kind, amount, occurred_at) "
        "VALUES ('expense', @a, CURRENT_DATE + interval '1 day')",
        {'a': 1000},
      )!;
      expect(op.patchable, isFalse,
          reason: 'ekspresi SQL tidak boleh ditebak nilainya');
    });
  });

  group('parseWrite: UPDATE', () {
    test('SET + WHERE kesamaan', () {
      final op = parseWrite(
        'UPDATE members SET name=@name, phone=@phone, position=@position, '
        'jersey=@jersey, active=@active WHERE id=@id',
        {
          'name': 'Ani', 'phone': null, 'position': 'Bek',
          'jersey': 5, 'active': true, 'id': 3,
        },
      )!;
      expect(op.kind, 'update');
      expect(op.table, 'members');
      expect(op.values['name'], 'Ani');
      expect(op.values['active'], true);
      expect(op.whereEq, {'id': 3});
      expect(op.patchable, isTrue);
    });

    test('UPDATE dengan subquery → tidak ditambal', () {
      final op = parseWrite(
        'UPDATE matches SET goals_for = COALESCE((SELECT sum(score_home) '
        'FROM match_sessions WHERE match_id=@m), 0) WHERE id=@m',
        {'m': 1},
      )!;
      expect(op.patchable, isFalse);
    });

    test('WHERE dengan kesamaan ganda tetap ditambal', () {
      // `Match.start()`: hanya laga yang masih `scheduled` yang boleh jadi
      // `ongoing`. Ini konjungsi kesamaan, jadi aman ditambal persis.
      final op = parseWrite(
        "UPDATE matches SET status='ongoing' WHERE id=@id AND status='scheduled'",
        {'id': 1},
      )!;
      expect(op.patchable, isTrue);
      expect(op.whereEq, {'id': 1, 'status': 'scheduled'});
    });

    test('WHERE berupa perbandingan → tidak ditambal', () {
      final op = parseWrite(
        'UPDATE matches SET status=@s WHERE goals_for > @n',
        {'s': 'finished', 'n': 0},
      )!;
      expect(op.patchable, isFalse,
          reason: 'hanya WHERE kesamaan yang aman ditambal');
    });
  });

  group('parseWrite: DELETE', () {
    test('WHERE id', () {
      final op = parseWrite('DELETE FROM members WHERE id=@id', {'id': 9})!;
      expect(op.kind, 'delete');
      expect(op.whereEq, {'id': 9});
      expect(op.patchable, isTrue);
    });

    test('DELETE tanpa WHERE tidak menghapus semua baris cache', () {
      final op = parseWrite('DELETE FROM members', {})!;
      expect(op.patchable, isFalse);
    });
  });

  group('applyOp', () {
    final members = [
      {'id': 1, 'name': 'Ani', 'active': true},
      {'id': 2, 'name': 'Budi', 'active': true},
    ];

    test('INSERT menambah baris di akhir', () {
      final op = parseWrite(
        'INSERT INTO members (name, active) VALUES (@name, @active)',
        {'name': 'Citra', 'active': true},
      )!;
      final out = applyOp(members, op, querySql: 'SELECT * FROM members ORDER BY name');
      expect(out, hasLength(3));
      expect(out.last['name'], 'Citra');
    });

    test('INSERT dengan id sementara supaya UI punya pegangan', () {
      final op = parseWrite(
        'INSERT INTO teams (name) VALUES (@n) RETURNING id',
        {'n': 'Tim Baru'},
      )!;
      final out = applyOp(const [], op, querySql: 'SELECT * FROM teams', tempId: -1);
      expect(out.single['id'], -1);
      expect(out.single['name'], 'Tim Baru');
    });

    test('upsert memperbarui baris yang kuncinya sama', () {
      final op = parseWrite(
        'INSERT INTO match_sessions (match_id, session_no, score_home) '
        'VALUES (@m, @sn, @h) ON CONFLICT (match_id, session_no) DO UPDATE SET score_home=@h',
        {'m': 1, 'sn': 1, 'h': 5},
      )!;
      final rows = [
        {'id': 10, 'match_id': 1, 'session_no': 1, 'score_home': 2},
      ];
      final out = applyOp(rows, op, querySql: 'SELECT * FROM match_sessions WHERE match_id=@m');
      expect(out, hasLength(1), reason: 'tidak boleh menambah baris kedua');
      expect(out.single['score_home'], 5);
    });

    test('UPDATE hanya mengubah baris yang cocok', () {
      final op = parseWrite(
        'UPDATE members SET name=@name WHERE id=@id',
        {'name': 'Ani Baru', 'id': 1},
      )!;
      final out = applyOp(members, op, querySql: 'SELECT * FROM members ORDER BY name');
      expect(out[0]['name'], 'Ani Baru');
      expect(out[1]['name'], 'Budi');
    });

    test('DELETE membuang baris yang cocok', () {
      final op = parseWrite('DELETE FROM members WHERE id=@id', {'id': 2})!;
      final out = applyOp(members, op, querySql: 'SELECT * FROM members');
      expect(out, hasLength(1));
      expect(out.single['id'], 1);
    });

    test('query yang tidak menyentuh tabel itu tidak diubah', () {
      final op = parseWrite(
        'INSERT INTO members (name) VALUES (@name)',
        {'name': 'X'},
      )!;
      final out = applyOp(members, op, querySql: 'SELECT * FROM teams');
      expect(identical(out, members), isTrue);
    });

    group('query ringkasan (agregat) tidak ditambal', () {
      // Baris tabel tidak boleh disisipkan ke hasil count/sum/GROUP BY: angka
      // ringkasannya tidak ikut berubah, jadi yang muncul hanyalah baris
      // sampah — mis. anggota baru tampil sebagai "pencetak gol" palsu.
      test('count(*) dibiarkan apa adanya', () {
        final op = parseWrite(
          'INSERT INTO members (name) VALUES (@name)',
          {'name': 'Baru'},
        )!;
        final rows = [
          {'c': 2},
        ];
        final out = applyOp(
          rows,
          op,
          querySql: 'SELECT count(*)::int AS c FROM members WHERE active',
          tempId: -1,
        );
        expect(identical(out, rows), isTrue);
        expect(out, hasLength(1));
        expect(out.single['c'], 2);
      });

      test('GROUP BY dibiarkan apa adanya', () {
        final op = parseWrite(
          'INSERT INTO payments (member_id, amount, period, note) '
          'VALUES (@mid, @amt, @period, @note)',
          {'mid': 1, 'amt': 150000, 'period': '2026-10', 'note': null},
        )!;
        final rows = [
          {'amount': 150000, 'n': 3},
        ];
        final out = applyOp(
          rows,
          op,
          querySql: 'SELECT amount, count(*)::int AS n FROM payments '
              'GROUP BY amount ORDER BY n DESC, amount DESC LIMIT 1',
          tempId: -1,
        );
        expect(identical(out, rows), isTrue);
      });

      test('daftar pencetak gol (count FILTER) tidak ketambahan baris', () {
        final op = parseWrite(
          'INSERT INTO members (name) VALUES (@name)',
          {'name': 'Baru'},
        )!;
        final rows = [
          {'name': 'Ani', 'goals': 4},
        ];
        final out = applyOp(
          rows,
          op,
          querySql: "SELECT coalesce(m.name, '(mantan anggota)') AS name, "
              "count(*) FILTER (WHERE e.type='goal')::int AS goals "
              'FROM match_events e LEFT JOIN members m ON m.id = e.member_id '
              'GROUP BY m.name ORDER BY goals DESC',
          tempId: -1,
        );
        expect(identical(out, rows), isTrue);
        expect(out, hasLength(1), reason: 'tidak boleh ada pencetak gol palsu');
      });

      test('DELETE pada query agregat juga tidak mengubah baris', () {
        final op = parseWrite('DELETE FROM members WHERE id=@id', {'id': 1})!;
        final rows = [
          {'c': 5},
        ];
        final out = applyOp(
          rows,
          op,
          querySql: 'SELECT count(*)::int AS c FROM members WHERE active',
        );
        expect(identical(out, rows), isTrue);
      });

      test('query daftar biasa tetap ditambal', () {
        // Kontrol: penjagaan agregat tidak boleh mematikan penambalan normal.
        final op = parseWrite(
          'INSERT INTO members (name) VALUES (@name)',
          {'name': 'Baru'},
        )!;
        final out = applyOp(
          const [],
          op,
          querySql: 'SELECT * FROM members WHERE active ORDER BY name',
          tempId: -1,
        );
        expect(out, hasLength(1));
      });
    });

    test('id dari JSON (String) cocok dengan parameter int', () {
      // Neon mengirim integer besar sebagai String; WHERE harus tetap cocok.
      final op = parseWrite('DELETE FROM members WHERE id=@id', {'id': 1})!;
      final rows = [
        {'id': '1', 'name': 'Ani'},
        {'id': '2', 'name': 'Budi'},
      ];
      final out = applyOp(rows, op, querySql: 'SELECT * FROM members');
      expect(out, hasLength(1));
      expect(out.single['name'], 'Budi');
    });
  });

  group('sortLikeQuery / trimLikeQuery', () {
    test('ORDER BY DESC menaruh yang terbaru di atas', () {
      final rows = [
        {'id': 1, 'played_at': '2026-01-01'},
        {'id': 2, 'played_at': '2026-03-01'},
        {'id': 3, 'played_at': '2026-02-01'},
      ];
      final out = sortLikeQuery(
        rows,
        'SELECT * FROM matches ORDER BY played_at DESC LIMIT @limit',
      );
      expect(out.map((r) => r['id']).toList(), [2, 3, 1]);
    });

    test('ORDER BY berkualifikasi tabel (m.played_at) tetap dikenali', () {
      final rows = [
        {'id': 1, 'played_at': '2026-01-01'},
        {'id': 2, 'played_at': '2026-02-01'},
      ];
      final out = sortLikeQuery(rows, 'SELECT m.* FROM matches m ORDER BY m.played_at DESC');
      expect(out.map((r) => r['id']).toList(), [2, 1]);
    });

    test('ORDER BY ekspresi dilewati, urutan asli dipertahankan', () {
      final rows = [
        {'id': 1, 'points': 3},
        {'id': 2, 'points': 6},
      ];
      final out = sortLikeQuery(rows, 'SELECT * FROM v ORDER BY (a - b) DESC');
      expect(out.map((r) => r['id']).toList(), [1, 2]);
    });

    test('LIMIT memotong hasil tambahan', () {
      final rows = [for (var i = 0; i < 30; i++) {'id': i}];
      final out = trimLikeQuery(rows, 'SELECT * FROM matches LIMIT @limit', {'limit': 20});
      expect(out, hasLength(20));
    });

    test('LIMIT berupa angka literal', () {
      final rows = [for (var i = 0; i < 10; i++) {'id': i}];
      expect(trimLikeQuery(rows, 'SELECT * FROM x LIMIT 5', {}), hasLength(5));
    });
  });
}
