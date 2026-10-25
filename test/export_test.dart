import 'package:flutter_test/flutter_test.dart';

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
}
