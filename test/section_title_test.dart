// Tinggi aksi di judul bagian harus memenuhi target sentuh minimum.
//
// Dulu tombol teks ("Semua", "Buka") hanya ~29px: satu-satunya pintu ke
// halaman lain dari beranda, dan yang paling sering meleset ditekan.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/ui/theme.dart';
import 'package:minisoccer_club/ui/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('aksi SectionTitle minimal setinggi minTap', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ShadApp(
      theme: AppThemes.light,
      home: Scaffold(
        body: SectionTitle(
          'Pengumuman',
          action: TextButton(onPressed: () {}, child: const Text('Semua')),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byType(TextButton));
    expect(size.height, greaterThanOrEqualTo(AppThemes.minTap),
        reason: 'tombol aksi judul bagian adalah pintu ke halaman lain');
  });
  testWidgets('chip periode punya area sentuh minTap', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ShadApp(
      theme: AppThemes.light,
      home: Scaffold(
        body: PeriodChips(
          periods: const ['2026-11', '2026-10', '2026-09'],
          selected: '2026-10',
          all: true,
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Yang diukur adalah area yang menerima ketukan (InkWell), bukan pil
    // visualnya: itulah yang dirasakan jari.
    // Chip digulir otomatis ke pilihan aktif, jadi yang diukur chip pertama
    // yang benar-benar terbangun di layar.
    final tap = tester.getSize(find.byType(InkWell).first);
    expect(tap.height, greaterThanOrEqualTo(AppThemes.minTap),
        reason: 'chip periode dipilih dengan jari, sering sambil berdiri');
  });
}