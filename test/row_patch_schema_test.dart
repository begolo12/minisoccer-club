// Tes bahwa baris hasil tambalan offline bisa dibaca model sungguhan.
//
// Bug yang dicegah: baris hasil `applyOp` hanya berisi kolom yang disebut
// INSERT. `Member.fromMap` membaca `m['id'] as int` dan `_dt(m['joined_at'])`,
// jadi baris tanpa `id`/`joined_at` membuat SELURUH daftar gagal dibaca —
// pengguna melihat "data tidak tersimpan" padahal antreannya benar.
//
// Karena itu di sini baris tambalan dilempar ke `fromMap` model yang asli,
// bukan diperiksa kolomnya satu per satu.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/core/row_patch.dart';
import 'package:minisoccer_club/data/models.dart';

void main() {
  group('baris tambalan bisa dibaca model', () {
    test('INSERT anggota (tanpa RETURNING) tetap punya id & joined_at', () {
      final op = parseWrite(
        'INSERT INTO members (name, phone, position, jersey) '
        'VALUES (@name, @phone, @position, @jersey)',
        {'name': 'Budi', 'phone': null, 'position': 'Bebas', 'jersey': null},
      )!;
      final rows = applyOp(const [], op, querySql: 'SELECT * FROM members ORDER BY name',
          tempId: -1);

      // Tidak boleh melempar — inilah bug yang dilaporkan.
      final member = Member.fromMap(rows.single);
      expect(member.id, -1);
      expect(member.name, 'Budi');
      expect(member.active, isTrue, reason: 'DEFAULT TRUE dari skema');
      expect(member.position, 'Bebas');
      expect(member.joinedAt.year, greaterThan(2000));
    });

    test('INSERT anggota dengan RETURNING id memakai id sementara', () {
      final op = parseWrite(
        'INSERT INTO members (name, position) VALUES (@n, @p) RETURNING id',
        {'n': 'Ani', 'p': 'Kiper'},
      )!;
      final rows = applyOp(const [], op, querySql: 'SELECT * FROM members', tempId: -7);
      expect(Member.fromMap(rows.single).id, -7);
    });

    test('baris anggota ikut terbaca bersama baris dari server', () {
      final existing = [
        {
          'id': 1,
          'name': 'Ani',
          'phone': null,
          'position': 'Bek',
          'jersey': 4,
          'active': true,
          'joined_at': '2026-01-01T00:00:00.000Z',
        },
      ];
      final op = parseWrite(
        'INSERT INTO members (name, phone, position, jersey) '
        'VALUES (@name, @phone, @position, @jersey)',
        {'name': 'Zaki', 'phone': null, 'position': 'Bebas', 'jersey': null},
      )!;
      final rows = applyOp(existing, op,
          querySql: 'SELECT * FROM members ORDER BY name', tempId: -2);

      // Diurutkan ulang seperti query aslinya, lalu dibaca model.
      final sorted = sortLikeQuery(rows, 'SELECT * FROM members ORDER BY name');
      final members = sorted.map(Member.fromMap).toList();
      expect(members.map((m) => m.name).toList(), ['Ani', 'Zaki']);
    });

    test('INSERT pembayaran punya paid_at', () {
      final op = parseWrite(
        'INSERT INTO payments (member_id, amount, period, note) '
        'VALUES (@mid, @amt, @period, @note)',
        {'mid': 1, 'amt': 150000, 'period': '2026-10', 'note': null},
      )!;
      final rows = applyOp(const [], op, querySql: 'SELECT * FROM payments', tempId: -1);
      final payment = Payment.fromMap(rows.single);
      expect(payment.memberId, 1);
      expect(payment.amount, 150000);
      expect(payment.paidAt.year, greaterThan(2000));
    });

    test('INSERT pengumuman punya created_at', () {
      final op = parseWrite(
        'INSERT INTO announcements (title, body) VALUES (@t, @b)',
        {'t': 'Latihan', 'b': 'Sabtu pagi'},
      )!;
      final rows = applyOp(const [], op, querySql: 'SELECT * FROM announcements', tempId: -1);
      final a = Announcement.fromMap(rows.single);
      expect(a.title, 'Latihan');
      expect(a.createdAt.year, greaterThan(2000));
    });
  });

  group('default kolom sama dengan db/schema.sql', () {
    // Kalau skema berubah (kolom NOT NULL baru dengan DEFAULT), peta default
    // di penambal harus ikut berubah — kalau tidak, baris offline akan
    // berbentuk beda dengan baris server. Tes ini yang menjaganya.
    final schema = File('db/schema.sql').readAsStringSync();

    /// Kolom + nilai DEFAULT per tabel, dibaca langsung dari skema.
    Map<String, Map<String, String>> parseSchemaDefaults(String sql) {
      final out = <String, Map<String, String>>{};
      final tableRe = RegExp(r'CREATE TABLE IF NOT EXISTS (\w+) \(([\s\S]*?)\n\);');
      for (final m in tableRe.allMatches(sql)) {
        final table = m.group(1)!;
        final cols = <String, String>{};
        for (final rawLine in m.group(2)!.split('\n')) {
          final line = rawLine.replaceAll(RegExp(r'--.*$'), '').trim();
          if (line.isEmpty) continue;
          if (RegExp(r'^(PRIMARY|UNIQUE|FOREIGN|CONSTRAINT|CHECK)\b', caseSensitive: false)
              .hasMatch(line)) {
            continue;
          }
          final cm = RegExp(r'^(\w+)\s+([A-Z]+[A-Z0-9_()]*)([\s\S]*)$').firstMatch(line);
          if (cm == null) continue;
          final d = RegExp(r'DEFAULT\s+([^,]+?)(?:\s+NOT NULL|,|$)', caseSensitive: false)
              .firstMatch(cm.group(3)!);
          if (d != null) cols[cm.group(1)!] = d.group(1)!.trim();
        }
        if (cols.isNotEmpty) out[table] = cols;
      }
      return out;
    }

    test('setiap DEFAULT di skema dikenali penambal', () {
      final defaults = parseSchemaDefaults(schema);
      final problems = <String>[];

      for (final entry in defaults.entries) {
        // Tabel khusus server: klien tidak bisa menulisnya (`audit_log` ditolak
        // api/_guard.js, `auth_throttle` hanya disentuh api/auth.js), jadi
        // penambal offline tidak pernah membuat baris untuk tabel ini.
        if (const {'audit_log', 'auth_throttle'}.contains(entry.key)) continue;
        final table = entry.key;
        final autoCols = debugAutoTimestampCols(table);
        final mapped = debugColumnDefaults()[table] ?? const {};

        for (final col in entry.value.entries) {
          final value = col.value.toLowerCase();
          final isNow = value.startsWith('now()');
          final isToday = value.startsWith('current_date');

          if (isNow) {
            if (!autoCols.contains(col.key)) {
              problems.add('$table.${col.key}: DEFAULT now() tidak ada di _autoTimestamps');
            }
          } else if (isToday) {
            if (!mapped.containsKey(col.key)) {
              problems.add('$table.${col.key}: DEFAULT CURRENT_DATE tidak ada di _columnDefaults');
            }
          } else if (!mapped.containsKey(col.key)) {
            problems.add('$table.${col.key}: DEFAULT $value tidak ada di _columnDefaults');
          }
        }
      }

      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    test('peta tidak memuat kolom yang sudah tidak ada di skema', () {
      final defaults = parseSchemaDefaults(schema);
      final problems = <String>[];
      for (final entry in debugColumnDefaults().entries) {
        final schemaCols = defaults[entry.key];
        if (schemaCols == null) {
          problems.add('tabel ${entry.key} tidak ada di skema');
          continue;
        }
        for (final col in entry.value.keys) {
          if (!schemaCols.containsKey(col)) {
            problems.add('${entry.key}.$col tidak punya DEFAULT di skema');
          }
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  });
}
