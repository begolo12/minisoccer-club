// Tes klasifikasi kegagalan jaringan.
//
// Ini penentu apakah tulis masuk antrean offline atau gagal. Kalau pesan yang
// muncul di HP tidak dikenali, pengguna melihat "gagal menyimpan" padahal
// datanya seharusnya tersimpan dan tersinkron nanti — jadi setiap pesan nyata
// dari Android, iOS, dan browser diuji di sini.
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/core/net.dart';

void main() {
  group('dianggap kegagalan jaringan (harus masuk antrean offline)', () {
    // Pesan yang benar-benar muncul di lapangan.
    const cases = <String, String>{
      'pesan sendiri (web)': 'Tidak bisa menghubungi server. Periksa koneksi internet.',
      'timeout sendiri': 'Server tidak merespons. Coba lagi.',
      'dart:io tanpa jaringan':
          'SocketException: Failed host lookup: \'minisoccer-club.vercel.app\'',
      'DNS Android': 'SocketException: No address associated with hostname (errno = 7)',
      'koneksi ditolak': 'SocketException: Connection refused (OS Error: Connection refused, errno = 111)',
      'jaringan seluler mati':
          'SocketException: Network is unreachable (OS Error: Network is unreachable, errno = 101)',
      'reset oleh server': 'SocketException: Connection reset by peer (errno = 104)',
      'putus di tengah respons':
          'Connection closed before full header was received',
      'putus saat menerima': 'Connection closed while receiving data',
      'abort (iOS)': 'SocketException: Software caused connection abort',
      'pipe putus': 'Broken pipe',
      'TLS diblokir': 'HandshakeException: Connection terminated during handshake',
      'sertifikat': 'HandshakeException: CERTIFICATE_VERIFY_FAILED',
      'timeout dart': 'TimeoutException after 0:00:20.000000: Future not completed',
      'timeout teks': 'The request timed out',
      'http client': 'ClientException: Failed to fetch, uri=https://example.com/api/sql',
      'browser fetch': 'Failed to fetch',
      'XMLHttpRequest': 'XMLHttpRequest error.',
      'Safari': 'Load failed',
      'NetworkError': 'NetworkError when attempting to fetch resource.',
    };

    cases.forEach((name, message) {
      test(name, () {
        expect(isNetworkFailure(Exception(message)), isTrue,
            reason: 'pesan ini harus dikenali sebagai gangguan jaringan: "$message"');
      });
    });

    test('dibungkus Exception tetap dikenali', () {
      expect(
        isNetworkFailure(Exception('SocketException: Failed host lookup')),
        isTrue,
      );
    });

    test('objek apa pun yang toString-nya memuat pola', () {
      // Beberapa paket melempar objek khusus, bukan Exception.
      expect(isNetworkFailure('Failed to fetch'), isTrue);
    });
  });

  group('BUKAN kegagalan jaringan (jangan masuk antrean)', () {
    // Menulis ulang ke antrean untuk penolakan server hanya akan mengulang
    // penolakan yang sama, dan menyembunyikan bug dari pengguna.
    const cases = <String, String>{
      'query ditolak': 'ApiException: Query gagal dijalankan',
      'izin': 'Mode publik hanya bisa melihat data. Masuk untuk mengubah.',
      'sesi habis': 'Sesi habis, silakan login ulang',
      'validasi': 'Exception: Sudah ada laga dengan skor',
      'duplikat': 'Exception: Iuran periode ini sudah dicatat.',
      'not found': 'ApiException: Tidak ditemukan',
      'galat program': 'TypeError: Null check operator used on a null value',
      'tipe salah': "type 'String' is not a subtype of type 'int'",
    };

    cases.forEach((name, message) {
      test(name, () {
        expect(isNetworkFailure(Exception(message)), isFalse,
            reason: 'pesan ini BUKAN gangguan jaringan: "$message"');
      });
    });
  });

  test('daftar pola tidak memuat pola kosong', () {
    for (final p in debugNetworkPatterns()) {
      expect(p.trim(), isNotEmpty);
    }
  });
}
