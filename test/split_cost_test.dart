// Tes pembagian biaya lapangan (patungan).
//
// Aturan yang dijaga: JUMLAH semua bagian harus tepat sama dengan biaya sewa.
// Pembagian naif (`total / n`) meleset satu-dua rupiah karena pembulatan, dan
// itu cukup untuk membuat "terkumpul" tidak pernah menyamai "target" — angka
// yang terlihat seperti bug di layar, padahal uangnya benar.
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/data/models.dart';

double sum(List<double> xs) => xs.fold<double>(0, (a, b) => a + b);

void main() {
  group('splitEvenly', () {
    test('membagi habis saat angkanya pas', () {
      expect(splitEvenly(300000, 6), [50000, 50000, 50000, 50000, 50000, 50000]);
    });

    test('jumlahnya SELALU tepat walau tidak habis dibagi', () {
      // 300.000 / 7 = 42.857,142… — kasus nyata sewa lapangan.
      final parts = splitEvenly(300000, 7);
      expect(parts, hasLength(7));
      expect(sum(parts), closeTo(300000, 0.001));
    });

    test('sisa pembulatan dibagikan satu rupiah ke orang pertama', () {
      final parts = splitEvenly(100000, 3);
      expect(sum(parts), closeTo(100000, 0.001));
      // 100.000 / 3 = 33.333,33 → satu orang 33.334, dua orang 33.333.
      expect(parts.where((p) => p == 33334).length, 1);
      expect(parts.where((p) => p == 33333).length, 2);
    });

    test('selisih antar orang tidak lebih dari satu rupiah', () {
      for (final total in [100000.0, 175000.0, 300000.0, 425000.0]) {
        for (final n in [2, 3, 5, 7, 9, 11, 13]) {
          final parts = splitEvenly(total, n);
          expect(sum(parts), closeTo(total, 0.001), reason: '$total dibagi $n');
          final lo = parts.reduce((a, b) => a < b ? a : b);
          final hi = parts.reduce((a, b) => a > b ? a : b);
          expect(hi - lo, lessThanOrEqualTo(1.0), reason: '$total dibagi $n');
        }
      }
    });

    test('biaya berkoma dibulatkan ke rupiah, bukan dipecah jadi sen', () {
      // Aplikasi ini tidak mengenal sen: input nominal menolak desimal. Jadi
      // yang benar adalah membulatkan totalnya, bukan menyuruh orang menyetor
      // 33.333,50.
      final parts = splitEvenly(100000.50, 3);
      expect(parts.every((p) => p == p.roundToDouble()), isTrue);
      expect(sum(parts), 100001);
    });

    test('tanpa peserta tidak ada bagian', () {
      expect(splitEvenly(300000, 0), isEmpty);
      expect(splitEvenly(300000, -1), isEmpty);
    });

    test('biaya nol menghasilkan nol untuk semua orang', () {
      expect(splitEvenly(0, 4), [0, 0, 0, 0]);
    });

    test('satu orang menanggung seluruh biaya', () {
      expect(splitEvenly(300000, 1), [300000]);
    });
  });

  group('BookingSplit', () {
    Booking booking({double cost = 300000}) => Booking(
          id: 1,
          title: 'Futsal Rabu',
          startsAt: DateTime(2026, 10, 21, 20),
          durationMin: 90,
          cost: cost,
          status: 'done',
        );

    BookingAttendance row({
      required int id,
      double share = 50000,
      bool paid = false,
    }) =>
        BookingAttendance(
          id: id,
          bookingId: 1,
          memberId: id,
          memberName: 'Anggota $id',
          share: share,
          paidAt: paid ? DateTime(2026, 10, 21) : null,
        );

    test('tanpa yang hadir, seluruh biaya ditanggung kas', () {
      final s = BookingSplit(booking: booking(), rows: const []);
      expect(s.hasAttendees, isFalse);
      expect(s.uncovered, 300000);
      expect(s.collected, 0);
      expect(s.outstanding, 0);
    });

    test('menghitung terkumpul dan kurang dari status setoran', () {
      final s = BookingSplit(booking: booking(), rows: [
        row(id: 1, paid: true),
        row(id: 2, paid: true),
        row(id: 3),
      ]);
      expect(s.collected, 100000);
      expect(s.outstanding, 50000);
      expect(s.paidCount, 2);
      expect(s.unpaidCount, 1);
      expect(s.uncovered, 0);
    });

    test('semua lunas berarti tidak ada kekurangan', () {
      final s = BookingSplit(booking: booking(), rows: [
        row(id: 1, paid: true),
        row(id: 2, paid: true),
      ]);
      expect(s.outstanding, 0);
      expect(s.unpaid, isEmpty);
    });

    test('bagian per orang mengikuti biaya dan jumlah hadir', () {
      final s = BookingSplit(booking: booking(), rows: [
        row(id: 1, share: 100000),
        row(id: 2, share: 100000),
        row(id: 3, share: 100000),
      ]);
      expect(s.perPerson, 100000);
    });

    test('booking tanpa biaya tidak menimbulkan tanggungan', () {
      final s = BookingSplit(booking: booking(cost: 0), rows: const []);
      expect(s.uncovered, 0);
      expect(s.outstanding, 0);
    });
  });
}
