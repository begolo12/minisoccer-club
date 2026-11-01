import 'package:flutter_test/flutter_test.dart';

import 'package:minisoccer_club/data/models.dart';
import 'package:minisoccer_club/ui/export.dart';

void main() {
  group('csvCell()', () {
    test('nominal uang tanpa desimal tidak membawa koma', () {
      // 75000.0 → "75000": Excel/Sheets harus mengenalinya sebagai angka.
      expect(csvCell(75000.0), '75000');
      expect(csvCell(1250.5), '1250.5');
    });

    test('sel biasa lewat tanpa kutip', () {
      expect(csvCell('Iuran'), 'Iuran');
      expect(csvCell(null), '');
      expect(csvCell(12), '12');
    });

    test('pemisah titik-koma memaksa kutip ganda', () {
      // Keterangan bisa berisi titik-koma; tanpa kutip, baris CSV-nya
      // meleset kolom dan laporan kas jadi salah baca.
      expect(csvCell('Latihan; rutin'), '"Latihan; rutin"');
    });

    test('kutip dalam teks digandakan', () {
      expect(csvCell('Piala "Rezki"'), '"Piala ""Rezki"""');
    });

    test('baris baru memaksa kutip', () {
      expect(csvCell('dua\nbaris'), '"dua\nbaris"');
    });
  });

  group('buildCsv()', () {
    test('berawalan BOM supaya Excel membaca UTF-8', () {
      final csv = buildCsv([
        ['Tanggal', 'Masuk'],
        ['2026-10-25', 50000],
      ]);
      expect(csv.startsWith('\uFEFF'), isTrue);
    });

    test('pemisah baris CRLF dan kolom titik-koma', () {
      final csv = buildCsv([
        ['a', 'b'],
        ['c', 'd'],
      ]);
      expect(csv.split('\uFEFF').last, 'a;b\r\nc;d');
    });

    test('baris tunggal tanpa CRLF tambahan', () {
      final csv = buildCsv([['satu']]);
      expect(csv, '\uFEFFsatu');
    });
  });

  group('memberCsvRows()', () {
    Member m({
      String name = 'Budi',
      String? phone = '0800111',
      String? address = 'Jl. Merdeka 1',
      bool active = true,
    }) =>
        Member(
          id: 1,
          name: name,
          phone: phone,
          address: address,
          position: 'Bebas',
          jersey: 9,
          active: active,
          joinedAt: DateTime.utc(2026, 3, 7),
        );

    test('baris pertama adalah kepala kolom', () {
      final rows = memberCsvRows([m()]);
      expect(rows.first,
          ['Nama', 'Posisi', 'Punggung', 'HP', 'Alamat', 'Status', 'Bergabung']);
    });

    test('status mengikuti active, tanggal bergabung ISO', () {
      final rows = memberCsvRows([m(), m(name: 'Ani', active: false)]);
      expect(rows[1][5], 'Aktif');
      expect(rows[2][5], 'Nonaktif');
      // ISO, bukan format lokal: Excel/Sheets mengenalinya sebagai tanggal.
      expect(rows[1][6], '2026-03-07');
    });

    test('HP/alamat kosong jadi sel kosong (bukan "null")', () {
      final rows = memberCsvRows([m(phone: null, address: null)]);
      expect(rows[1][3], isNull);
      expect(rows[1][4], isNull);
      expect(buildCsv(rows), isNot(contains('null')));
    });
  });
}
