// Laporan kas per kategori: angka laporan HARUS sama dengan baris buku kas
// yang tampil, karena keduanya dihitung dari daftar CashEntry yang sama.
// Bug yang dicegah: laporan pengurus menyebut total yang tidak bisa dicocokkan
// dengan halaman Kas — sekali itu terjadi, laporannya tidak dipercaya lagi.
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/data/models.dart';
import 'package:minisoccer_club/ui/export.dart';

CashEntry _income(String label, double amount, {bool dues = false}) => CashEntry(
      date: DateTime(2026, 10, 5),
      label: label,
      detail: '',
      amount: amount,
      dues: dues,
    );

/// Pengeluaran disimpan negatif di buku kas (lihat `mergeCashLedger`).
CashEntry _expense(String label, double amount) => CashEntry(
      date: DateTime(2026, 10, 6),
      label: label,
      detail: '',
      amount: -amount,
    );

void main() {
  group('summarizeCashByCategory', () {
    test('kategori sama digabung, urutan menurun, jumlah catatan ikut', () {
      final by = summarizeCashByCategory([
        _expense('Sewa lapangan', 300000),
        _expense('Wasit', 400000),
        _expense('Sewa lapangan', 200000),
      ]);
      expect(by.expense.map((c) => c.label).toList(), ['Sewa lapangan', 'Wasit']);
      expect(by.expense.first.total, 500000);
      expect(by.expense.first.count, 2);
      expect(by.income, isEmpty);
    });

    test('iuran dan pemasukan lain dikelompokkan per labelnya', () {
      final by = summarizeCashByCategory([
        _income('Iuran', 75000, dues: true),
        _income('Iuran', 75000, dues: true),
        _income('Patungan lapangan', 100000),
        _expense('Konsumsi', 50000),
      ]);
      expect(by.income.first.label, 'Iuran');
      expect(by.income.first.total, 150000);
      expect(by.income.first.count, 2);
      expect(by.income.last.label, 'Patungan lapangan');
      expect(by.expense.single.label, 'Konsumsi');
    });

    test('total kategori sama dengan CashSummary dari entri yang sama', () {
      final entries = [
        _income('Iuran', 150000, dues: true),
        _income('Sponsor', 500000),
        _expense('Sewa lapangan', 350000),
        _expense('Wasit', 200000),
        _expense('Perlengkapan', 125000),
      ];
      final s = CashSummary.fromEntries(entries);
      final by = summarizeCashByCategory(entries);
      final incSum = by.income.fold<double>(0, (a, c) => a + c.total);
      final expSum = by.expense.fold<double>(0, (a, c) => a + c.total);
      expect(incSum, closeTo(s.income, 0.001));
      expect(expSum, closeTo(s.expense, 0.001));
      expect(incSum - expSum, closeTo(s.balance, 0.001));
    });
  });

  group('buildCashReportText', () {
    String report(List<CashEntry> entries, {String period = 'Oktober 2026'}) =>
        buildCashReportText(
          periodName: period,
          summary: CashSummary.fromEntries(entries),
          byCategory: summarizeCashByCategory(entries),
        );

    test('berisi periode, baris per kategori, total, dan selisih', () {
      final text = report([
        _income('Iuran', 150000, dues: true),
        _expense('Sewa lapangan', 100000),
      ]);
      expect(text, contains('LAPORAN KAS — OKTOBER 2026'));
      expect(text, contains('Iuran: Rp 150.000 (1 catatan)'));
      expect(text, contains('Sewa lapangan: Rp 100.000 (1 catatan)'));
      expect(text, contains('Total masuk: Rp 150.000'));
      expect(text, contains('Total keluar: Rp 100.000'));
      // Selisih = 50.000; muncul tepat sekali sebagai angka tersendiri.
      expect('Rp 50.000'.allMatches(text).length, 1);
    });

    test('bagian tanpa catatan dinyatakan eksplisit, bukan hilang diam-diam',
        () {
      final text = report([_income('Iuran', 50000, dues: true)]);
      expect(text, contains('PENGELUARAN'));
      expect(text, contains('Tidak ada catatan.'));
      expect(text, contains('Total keluar: Rp 0'));
    });

    test('selisih negatif memakai tanda minus dari fmtMoney', () {
      final text = report([_expense('Konsumsi', 200000)]);
      expect(text, contains('-Rp 200.000'));
    });
  });
}
