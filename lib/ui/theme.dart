import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Tema "Papan Skor": papan LED stadion, bukan dashboard SaaS.
///
/// Aturan yang dipakai di seluruh app:
/// - Angka dan skor pakai Barlow Condensed (sempit, tebal), tabular.
/// - Teks pakai Inter; label kecil HURUF BESAR dengan tracking lega.
/// - Satu aksen hijau lapangan. Amber hanya untuk uang, merah hanya untuk
///   tunggakan/gagal. Tidak ada gradien dekoratif.
/// - Permukaan datar + garis rambut; hierarki dari ukuran dan jarak, bukan
///   dari bayangan dan warna kartu.
class AppThemes {
  // ---- token warna ----
  static const ink = Color(0xFF080B09); // dasar gelap
  static const pitch = Color(0xFF35D07F); // hijau lapangan
  static const amber = Color(0xFFF5B841); // uang
  static const danger = Color(0xFFFF5A5A); // tunggakan / gagal
  static const chalk = Color(0xFFE8F0EA); // teks di atas gelap

  static const pitchLight = Color(0xFF0A7D43);
  static const amberLight = Color(0xFF7A5C00);
  static const dangerLight = Color(0xFFB3261E);

  /// Warna yang aman di kedua mode. Amber terang gagal kontras di atas putih.
  static Color money(BuildContext context) =>
      ShadTheme.of(context).brightness == Brightness.dark ? amber : amberLight;

  static Color bad(BuildContext context) =>
      ShadTheme.of(context).brightness == Brightness.dark ? danger : dangerLight;

  /// Font angka/skor.
  static const display = 'BarlowCondensed';
  static const body = 'Inter';

  /// Angka rata kolom: dipakai semua nominal dan tabel.
  static const tabular = [FontFeature.tabularFigures()];

  static ShadThemeData get dark => ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: ShadColorScheme(
          background: ink,
          foreground: chalk,
          card: const Color(0xFF0E1512),
          cardForeground: chalk,
          popover: const Color(0xFF111A15),
          popoverForeground: chalk,
          primary: pitch,
          primaryForeground: const Color(0xFF04150C),
          secondary: const Color(0xFF16211B),
          secondaryForeground: chalk,
          muted: const Color(0xFF141D18),
          mutedForeground: const Color(0xFF8FA096),
          accent: const Color(0xFF1B2820),
          accentForeground: chalk,
          destructive: danger,
          destructiveForeground: const Color(0xFF1A0505),
          border: const Color(0xFF202C25),
          input: const Color(0xFF141D18),
          ring: pitch,
          selection: const Color(0xFF123D27),
        ),
        textTheme: _text(dark: true),
      );

  static ShadThemeData get light => ShadThemeData(
        brightness: Brightness.light,
        colorScheme: ShadColorScheme(
          background: const Color(0xFFF2F5F1),
          foreground: const Color(0xFF0C120E),
          card: const Color(0xFFFFFFFF),
          cardForeground: const Color(0xFF0C120E),
          popover: const Color(0xFFFFFFFF),
          popoverForeground: const Color(0xFF0C120E),
          primary: pitchLight,
          primaryForeground: const Color(0xFFF2FBF5),
          secondary: const Color(0xFFE7EDE6),
          secondaryForeground: const Color(0xFF0C120E),
          muted: const Color(0xFFE7EDE6),
          mutedForeground: const Color(0xFF5F6F65),
          accent: const Color(0xFFE7EDE6),
          accentForeground: const Color(0xFF0C120E),
          destructive: dangerLight,
          destructiveForeground: const Color(0xFFFFF5F4),
          border: const Color(0xFFD8E0D9),
          input: const Color(0xFFE7EDE6),
          ring: pitchLight,
          selection: const Color(0xFFD6F2E0),
        ),
        textTheme: _text(dark: false),
      );

  /// Peran teks. Skor/angka besar pakai [display]; sisanya Inter.
  static ShadTextTheme _text({required bool dark}) {
    final fg = dark ? chalk : const Color(0xFF0C120E);
    final muted = dark ? const Color(0xFF8FA096) : const Color(0xFF5F6F65);
    return ShadTextTheme(
      family: body,
      h1Large: TextStyle(
        fontFamily: display,
        fontSize: 64,
        height: 0.95,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        fontFeatures: tabular,
        color: fg,
      ),
      h1: TextStyle(
        fontFamily: display,
        fontSize: 40,
        height: 1,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        fontFeatures: tabular,
        color: fg,
      ),
      h2: TextStyle(
        fontFamily: display,
        fontSize: 28,
        height: 1.05,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        fontFeatures: tabular,
        color: fg,
      ),
      // Judul halaman.
      h3: TextStyle(
        fontSize: 21,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: fg,
      ),
      // Judul bagian.
      h4: TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: muted,
      ),
      p: TextStyle(fontSize: 14, height: 1.5, color: fg),
      large: TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w600, color: fg),
      small: TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w500, color: muted),
      muted: TextStyle(fontSize: 13.5, height: 1.5, color: muted),
      lead: TextStyle(fontSize: 16, height: 1.45, color: fg),
      table: TextStyle(fontSize: 13.5, height: 1.4, fontFeatures: tabular, color: fg),
    );
  }
}
