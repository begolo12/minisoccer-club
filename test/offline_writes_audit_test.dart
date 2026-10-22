// Setiap tulis di aplikasi harus punya perilaku offline yang DISENGAJA.
//
// Sumber datanya bukan SQL karangan: `scripts/audit-queries.mjs` menjalankan
// setiap method model dengan mock HTTP dan merekam SQL yang benar-benar
// dikirim. Berkas `.audit/queries.json` (43 tulis, 82 query) itu yang dibaca
// di sini.
//
// Yang diperiksa:
//   1. Setiap tulis dikenali `parseWrite` (tabel + jenis operasi terbaca).
//   2. Tulis yang ditambal benar-benar menghasilkan baris yang bisa dibaca
//      model, atau kalau tidak bisa ditambal, alasannya jelas.
//   3. Tidak ada tulis yang "setengah dikenali": dikira bisa ditambal padahal
//      WHERE-nya tidak bisa dievaluasi di klien.
//
// Kalau tes ini gagal setelah menambah fitur tulis baru, itu memang tujuannya:
// penambal offline perlu tahu cara menangani tulis tersebut.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/core/row_patch.dart';

/// Tulis yang sengaja TIDAK ditambal, beserta alasannya.
///
/// Daftar ini harus pendek dan setiap entri harus bisa dijelaskan. Kalau
/// sebuah tulis masuk sini, artinya saat offline perubahannya baru terlihat
/// setelah sinkron — bukan langsung.
const _intentionallyUnpatched = <String, String>{
  'UPDATE matches SET goals_for = COALESCE':
      'skor laga dihitung ulang dari seluruh sesi (COALESCE + subquery agregat); '
          'angkanya tidak boleh ditebak di klien',
  'UPDATE matches SET status = CASE':
      'menghitung ulang skor dari sesi (CASE + subquery) — angka tidak boleh ditebak',
  'UPDATE tournaments SET status = CASE':
      'status turnamen dihitung dari jadwal (CASE + EXISTS)',
  'INSERT INTO tournament_teams':
      'INSERT banyak baris sekaligus (satu VALUES per tim)',
  'INSERT INTO tournament_matches':
      'INSERT banyak baris sekaligus (seluruh jadwal round-robin)',
  'UPDATE match_sessions SET score_home=@h, score_away=@a, winner=@w, ended_at=now()':
      'ended_at=now() ditulis sebagai literal SQL, bukan parameter',
};

void main() {
  final file = File('.audit/queries.json');
  if (!file.existsSync()) {
    // Berkas ini dibuat oleh `test/queries_audit_test.dart` (bukan oleh
    // `npm run check:audit`, yang justru MEMBACA berkas yang sama). Kalau
    // hilang, tes ini tidak bisa menilai apa pun — tapi menggagalkan seluruh
    // suite hanya karena berkas turunan belum dibuat akan membuat
    // `flutter test` di clone baru tampak rusak.
    test('data audit tulis tersedia (dibuat queries_audit_test.dart)', () {
      // ignore: avoid_print
      print(
        'Dilewati: `.audit/queries.json` belum ada. Jalankan '
        '`flutter test test/queries_audit_test.dart` lebih dulu.',
      );
    }, skip: '`.audit/queries.json` belum dibuat — lihat pesan di atas');
    return;
  }

  final raw = jsonDecode(file.readAsStringSync());
  final list = (raw is List ? raw : (raw as Map)['queries'] as List)
      .cast<Map<String, dynamic>>();
  final writes = list.where((q) {
    final sql = (q['sql'] as String? ?? '').trimLeft().toUpperCase();
    return sql.startsWith('INSERT') || sql.startsWith('UPDATE') || sql.startsWith('DELETE');
  }).toList();

  test('data audit memuat tulis', () {
    expect(writes.length, greaterThan(30),
        reason: 'audit harus merekam puluhan tulis, bukan beberapa');
  });

  test('setiap tulis dikenali jenis & tabelnya', () {
    final problems = <String>[];
    for (final w in writes) {
      final label = w['label'] as String? ?? '(tanpa label)';
      final sql = w['sql'] as String;
      final params = (w['params'] as Map?)?.cast<String, Object?>() ?? const {};
      final op = parseWrite(sql, params);
      if (op == null) {
        problems.add('$label: parseWrite mengembalikan null');
        continue;
      }
      if (op.table.isEmpty) {
        problems.add('$label: tabel tidak terbaca');
      }
      // Jenis harus sesuai kata kunci pertama.
      final head = sql.trimLeft().toUpperCase();
      final expected = head.startsWith('INSERT')
          ? 'insert'
          : head.startsWith('UPDATE')
              ? 'update'
              : 'delete';
      if (op.kind != expected) {
        problems.add('$label: jenis ${op.kind}, seharusnya $expected');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('tulis yang tidak ditambal memang disengaja', () {
    final unexpected = <String>[];
    for (final w in writes) {
      final label = w['label'] as String? ?? '(tanpa label)';
      final sql = w['sql'] as String;
      final params = (w['params'] as Map?)?.cast<String, Object?>() ?? const {};
      final op = parseWrite(sql, params);
      if (op == null || op.patchable) continue;

      // Cari alasan yang cocok dengan awal SQL-nya.
      final normalized = sql.replaceAll(RegExp(r'\s+'), ' ').trim();
      final excused = _intentionallyUnpatched.keys.any(
        (k) => normalized.toLowerCase().startsWith(k.toLowerCase()),
      );
      if (!excused) {
        unexpected.add('$label\n  SQL: ${normalized.substring(0, normalized.length.clamp(0, 110))}');
      }
    }
    expect(
      unexpected,
      isEmpty,
      reason: 'Tulis berikut tidak bisa ditambal offline dan belum ada '
          'alasannya di _intentionallyUnpatched:\n${unexpected.join('\n')}',
    );
  });

  test('tulis yang ditambal menghasilkan efek yang masuk akal', () {
    final problems = <String>[];
    for (final w in writes) {
      final label = w['label'] as String? ?? '(tanpa label)';
      final sql = w['sql'] as String;
      final params = (w['params'] as Map?)?.cast<String, Object?>() ?? const {};
      final op = parseWrite(sql, params);
      if (op == null || !op.patchable) continue;

      // Baris awal kosong; tambalan tidak boleh melempar untuk bentuk apa pun.
      List<Map<String, dynamic>> result;
      try {
        result = applyOp(const [], op, querySql: 'SELECT * FROM ${op.table}', tempId: -1);
      } catch (e) {
        problems.add('$label: applyOp melempar ($e)');
        continue;
      }

      if (op.isInsert) {
        if (result.isEmpty) {
          problems.add('$label: INSERT tidak menambah baris');
        } else {
          final row = result.single;
          if (!row.containsKey('id')) {
            problems.add('$label: baris baru tanpa id (UI tidak bisa mengenalinya)');
          }
        }
      }
      if (op.isUpdate && op.whereEq.isEmpty) {
        problems.add('$label: UPDATE tanpa WHERE yang bisa dievaluasi');
      }
      if (op.isDelete && op.whereEq.isEmpty) {
        problems.add('$label: DELETE tanpa WHERE (akan mengosongkan tampilan)');
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('penolakan daftar: setiap alasan tertulis jelas', () {
    for (final e in _intentionallyUnpatched.entries) {
      expect(e.value.trim(), isNotEmpty, reason: '${e.key} tanpa alasan');
      expect(e.value.length, greaterThan(15),
          reason: '${e.key}: alasan terlalu pendek untuk berguna');
    }
  });
}
