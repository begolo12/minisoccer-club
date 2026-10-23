// Aturan formulir pendaftaran di sisi klien.
//
// Sama dengan `api/register.js`: salinan ini hanya supaya kesalahan ketahuan
// sebelum dikirim. Kalau keduanya berbeda, pengguna melihat "berhasil" di
// layar lalu ditolak server — atau sebaliknya, isian yang sah diblokir.
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/core/registration.dart';

void main() {
  group('normalizePhone', () {
    test('semua penulisan nomor HP menjadi satu bentuk', () {
      expect(normalizePhone('0812-3456-7890'), '081234567890');
      expect(normalizePhone('+62 812 3456 7890'), '081234567890');
      expect(normalizePhone('6281234567890'), '081234567890');
      expect(normalizePhone('8123456789'), '08123456789');
    });

    test('nomor yang tidak masuk akal ditolak', () {
      expect(normalizePhone(''), isNull);
      expect(normalizePhone('12345'), isNull);
      expect(normalizePhone('0812'), isNull);
      expect(normalizePhone('0812345678901234567'), isNull);
    });
  });

  group('usernameBase', () {
    test('nama depan dipakai apa adanya dalam huruf kecil', () {
      expect(usernameBase('Irvan Nur Cahyo'), 'irvan');
      expect(usernameBase('IRVAN'), 'irvan');
    });

    test('nama depan terlalu pendek: pakai nama lengkap', () {
      expect(usernameBase('M. Rizky'), 'mrizky');
    });

    test('nama kosong tetap menghasilkan username yang bisa diketik', () {
      expect(usernameBase(''), 'anggota');
    });
  });

  group('validasi isian', () {
    test('nama wajib minimal 3 huruf', () {
      expect(nameError(''), isNotNull);
      expect(nameError('Ir'), isNotNull);
      expect(nameError('Irvan'), isNull);
      expect(nameError("M. Irvan-Ash"), isNull);
      expect(nameError('Irvan123'), isNotNull);
    });

    test('nomor HP wajib dan harus berbentuk nomor Indonesia', () {
      expect(phoneError(''), isNotNull);
      expect(phoneError('0812'), isNotNull);
      expect(phoneError('081234567890'), isNull);
      expect(phoneError('+62 812 3456 7890'), isNull);
    });

    test('alamat wajib minimal 5 huruf', () {
      expect(addressError(''), isNotNull);
      expect(addressError('Jl'), isNotNull);
      expect(addressError('Jl. Melati 12'), isNull);
    });

    test('posisi wajib dipilih dari daftar', () {
      expect(positionError(null), isNotNull);
      expect(positionError('Striker'), isNotNull);
      for (final p in kPositions) {
        expect(positionError(p), isNull, reason: p);
      }
    });
  });

  group('isRegisterLocation', () {
    test('mengenali tautan di akar domain, sub-jalur, dan mode hash', () {
      expect(isRegisterLocation(Uri.parse('https://klub.test/daftar')), isTrue);
      expect(isRegisterLocation(Uri.parse('https://klub.test/minisoccer/daftar')), isTrue);
      expect(isRegisterLocation(Uri.parse('https://klub.test/minisoccer/daftar/')), isTrue);
      expect(isRegisterLocation(Uri.parse('https://klub.test/#/daftar')), isTrue);
      expect(isRegisterLocation(Uri.parse('https://klub.test/minisoccer/')), isFalse);
      expect(isRegisterLocation(Uri.parse('https://klub.test/')), isFalse);
    });
  });
}
