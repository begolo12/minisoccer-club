// Siapa yang boleh melihat apa di halaman Pengaturan.
//
// Aturan produk: anggota biasa hanya melihat data klub dan pengaturan
// perangkatnya sendiri. Bagian teknis — alamat server, tes koneksi, antrean
// offline, tautan pembuat akun, diagnostik layar — hanya untuk admin.
//
// Yang TIDAK boleh hilang untuk anggota: tema, akun sendiri (ganti password,
// keluar), dan panel pembaruan aplikasi. Menyembunyikan pembaruan berarti
// anggota yang memakai APK lama tidak punya jalan memperbaruinya.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:minisoccer_club/data/auth.dart';
import 'package:minisoccer_club/ui/settings.dart';
import 'package:minisoccer_club/ui/theme.dart';

Widget _wrap(Widget child) => ShadApp(
      theme: AppThemes.dark,
      home: child,
    );

/// Semua teks yang pernah terlihat sambil menggulir daftar sampai ujung.
///
/// `ListView` membangun anaknya dengan malas: item yang jauh di bawah belum
/// ada di pohon widget, dan item yang sudah lewat dibuang lagi. Jadi
/// "tidak ditemukan" tanpa menggulir hanya berarti "belum dibangun", bukan
/// "tidak ada" — dan memeriksa setelah menggulir ke ujung malah kehilangan
/// bagian atas. Mengumpulkan sepanjang gulir menutup keduanya.
Future<Set<String>> _textsWhileScrolling(WidgetTester tester) async {
  // Judul bagian ditulis kapital oleh `SectionTitle`, jadi perbandingan
  // dilakukan tanpa peduli huruf besar/kecil.
  final seen = <String>{};
  void collect() {
    for (final w in tester.widgetList<Text>(find.byType(Text))) {
      final d = w.data;
      if (d != null) seen.add(d.toLowerCase());
    }
  }

  collect();
  for (var i = 0; i < 12; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pump(const Duration(milliseconds: 120));
    collect();
  }
  return seen;
}

void main() {
  tearDown(() {
    Auth.role = null;
    Auth.username = null;
  });

  const technical = [
    'Sambungan data',
    'Neon Postgres',
    'Tes koneksi',
    'Data tanpa internet',
    'Kosongkan data sementara',
    'Pendaftaran anggota',
    'Tautan pendaftaran',
  ];

  testWidgets('anggota tidak melihat bagian teknis di Pengaturan', (tester) async {
    Auth.role = 'member';
    Auth.username = 'urip';
    await tester.pumpWidget(_wrap(const SettingsPage()));
    await tester.pump(const Duration(seconds: 1));

    final texts = await _textsWhileScrolling(tester);

    for (final label in technical) {
      expect(texts.contains(label.toLowerCase()), isFalse,
          reason: 'anggota melihat "$label"');
    }

    // Yang harus tetap ada untuk anggota.
    expect(texts.contains('tampilan'), isTrue);
    expect(texts.contains('tema'), isTrue);
    expect(texts.contains('akun'), isTrue);
    expect(texts.contains('pembaruan'), isTrue);
    expect(texts.contains('tentang'), isTrue);
    expect(texts.contains('keluar'), isTrue);
  });

  testWidgets('tamu juga tidak melihat bagian teknis', (tester) async {
    Auth.role = null;
    Auth.username = null;
    await tester.pumpWidget(_wrap(const SettingsPage()));
    await tester.pump(const Duration(seconds: 1));

    final texts = await _textsWhileScrolling(tester);

    for (final label in technical) {
      expect(texts.contains(label.toLowerCase()), isFalse,
          reason: 'tamu melihat "$label"');
    }
    // Tamu punya pintu masuk sendiri.
    expect(texts.contains('masuk ke akun'), isTrue);
  });

  testWidgets('admin melihat bagian teknis', (tester) async {
    Auth.role = 'admin';
    Auth.username = 'admin';
    await tester.pumpWidget(_wrap(const SettingsPage()));
    await tester.pump(const Duration(seconds: 1));

    final texts = await _textsWhileScrolling(tester);

    for (final label in technical) {
      expect(texts.contains(label.toLowerCase()), isTrue,
          reason: 'admin tidak melihat "$label"');
    }
  });

  testWidgets('bendahara: teknis disembunyikan, hak tulis tetap', (tester) async {
    Auth.role = 'treasurer';
    Auth.username = 'bendahara';
    await tester.pumpWidget(_wrap(const SettingsPage()));
    await tester.pump(const Duration(seconds: 1));

    final texts = await _textsWhileScrolling(tester);

    expect(Auth.canWrite, isTrue);
    for (final label in technical) {
      expect(texts.contains(label.toLowerCase()), isFalse,
          reason: 'bendahara melihat "$label"');
    }
    expect(texts.contains('keluar'), isTrue);
  });
}
