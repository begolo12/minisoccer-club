// Tes input nominal uang bertitik ribuan.
//
// Formatter ini menyentuh dua hal yang mudah salah dan sulit dilihat di layar:
// bentuk teks dan POSISI KURSOR. Kalau kursornya salah, pengguna yang mengetik
// di tengah angka akan melihat kursor meloncat ke ujung — terasa seperti app
// rusak. Karena itu posisi kursor diuji eksplisit, bukan hanya isi teksnya.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/ui/money_input.dart';

void main() {
  group('groupThousands', () {
    test('mengelompokkan tiap 3 digit', () {
      expect(groupThousands('1'), '1');
      expect(groupThousands('12'), '12');
      expect(groupThousands('123'), '123');
      expect(groupThousands('1234'), '1.234');
      expect(groupThousands('12345'), '12.345');
      expect(groupThousands('123456'), '123.456');
      expect(groupThousands('1234567'), '1.234.567');
      expect(groupThousands('1000000'), '1.000.000');
    });
  });

  group('formatMoneyText', () {
    test('angka mentah jadi bertitik', () {
      expect(formatMoneyText('1500000'), '1.500.000');
      expect(formatMoneyText('350000'), '350.000');
    });

    test('ketikan yang sudah bertitik tidak jadi dobel titik', () {
      // Titik hasil format sendiri harus diabaikan, bukan dianggap desimal.
      expect(formatMoneyText('1.500.000'), '1.500.000');
      expect(formatMoneyText('1.234.567'), '1.234.567');
    });

    test('nol di depan dibuang', () {
      expect(formatMoneyText('05'), '5');
      expect(formatMoneyText('000'), '0');
      expect(formatMoneyText('0'), '0');
    });

    test('koma = sen, maksimal 2 digit', () {
      expect(formatMoneyText('1500,5'), '1.500,5');
      expect(formatMoneyText('1500,50'), '1.500,50');
      expect(formatMoneyText('1500,505'), '1.500,50');
    });

    test('teks kosong jadi kosong, bukan nol', () {
      expect(formatMoneyText(''), '');
      expect(formatMoneyText('abc'), '');
    });

    test('tempel "Rp 1.500.000" tetap terbaca', () {
      expect(formatMoneyText('Rp 1.500.000'), '1.500.000');
      expect(formatMoneyText(' Rp 1 500 000 '), '1.500.000');
    });

    test('allowDecimal=false mengabaikan koma (kolom bilangan bulat)', () {
      expect(formatMoneyText('1500,50', hadDecimal: false), '1.500');
    });
  });

  group('parseFormattedMoney', () {
    test('membaca teks bertitik', () {
      expect(parseFormattedMoney('1.500.000'), 1500000);
      expect(parseFormattedMoney('350.000'), 350000);
    });

    test('membaca sen', () {
      expect(parseFormattedMoney('1.500,50'), 1500.5);
      expect(parseFormattedMoney('0,05'), 0.05);
      expect(parseFormattedMoney('1.500,5'), 1500.5);
    });

    test('kosong = 0', () {
      expect(parseFormattedMoney(''), 0);
      expect(parseFormattedMoney('   '), 0);
    });

    test('bolak-balik format lalu baca menghasilkan nilai sama', () {
      for (final value in [1, 999, 1000, 1500, 350000, 1000000, 12345678]) {
        final text = formatMoneyText('$value');
        expect(parseFormattedMoney(text), value.toDouble(),
            reason: 'nilai $value berubah setelah diformat "$text"');
      }
    });
  });

  group('MoneyInputFormatter: posisi kursor', () {
    final f = MoneyInputFormatter();

    TextEditingValue apply(String oldText, String newText, int cursor) {
      return f.formatEditUpdate(
        TextEditingValue(
          text: oldText,
          selection: TextSelection.collapsed(offset: oldText.length),
        ),
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: cursor),
        ),
      );
    }

    test('mengetik di ujung: kursor tetap di ujung', () {
      final r = apply('', '1', 1);
      expect(r.text, '1');
      expect(r.selection.baseOffset, 1);

      final r2 = apply('1', '15', 2);
      expect(r2.text, '15');
      expect(r2.selection.baseOffset, 2);
    });

    test('titik muncul saat digit ke-4, kursor tetap setelah digit terakhir', () {
      final r = apply('123', '1234', 4);
      expect(r.text, '1.234');
      expect(r.selection.baseOffset, 5,
          reason: 'kursor harus di ujung (setelah "4"), bukan di tengah titik');
    });

    test('mengetik di tengah angka tidak meloncat ke ujung', () {
      // "1.234" lalu sisipkan "9" setelah "1" → "19.234", kursor setelah "9".
      final r = apply('1.234', '19.234', 2);
      expect(r.text, '19.234');
      expect(r.selection.baseOffset, 2,
          reason: 'kursor harus tepat setelah digit yang baru diketik');
    });

    test('menghapus digit mempertahankan posisi yang wajar', () {
      // Hapus "4" dari "1.234" → "123".
      final r = apply('1.234', '1.23', 4);
      expect(r.text, '123');
      expect(r.selection.baseOffset, 3);
    });

    test('menghapus titik saja tidak menghapus angka', () {
      // Pengguna menekan backspace tepat setelah "1" (titik ikut terhapus):
      // teks mentah jadi "1234", dan formatter harus mengembalikan titiknya
      // tanpa memindahkan kursor.
      final r = apply('1.234', '1234', 1);
      expect(r.text, '1.234', reason: 'titik harus kembali muncul');
      expect(r.selection.baseOffset, 1,
          reason: 'kursor tetap setelah "1", tempat pengguna menghapus');
    });

    test('semua dihapus → kosong dengan kursor 0', () {
      final r = apply('1.234', '', 0);
      expect(r.text, '');
      expect(r.selection.baseOffset, 0);
    });

    test('kursor di awal tetap di awal', () {
      final r = apply('', '5', 0);
      expect(r.text, '5');
      expect(r.selection.baseOffset, 0);
    });
  });
}
