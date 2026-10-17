import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Tema app — shadcn, dark default, light tersedia.
/// Aksen: hijau lapangan + sheen "oil" (ungu/biru tipis) di kartu.
class AppThemes {
  /// Warna sheen oil. Dipakai OilCard supaya identitas visual konsisten.
  static const oilA = Color(0xFF22C55E); // hijau
  static const oilB = Color(0xFF38BDF8); // biru
  static const oilC = Color(0xFFA78BFA); // ungu

  static ShadThemeData get dark => ShadThemeData(
        brightness: Brightness.dark,
        colorScheme: ShadColorScheme(
          background: const Color(0xFF0B0F14),
          foreground: const Color(0xFFF1F5F9),
          card: const Color(0xFF111821),
          cardForeground: const Color(0xFFF1F5F9),
          popover: const Color(0xFF111821),
          popoverForeground: const Color(0xFFF1F5F9),
          primary: const Color(0xFF22C55E),
          primaryForeground: const Color(0xFF052E16),
          secondary: const Color(0xFF1E293B),
          secondaryForeground: const Color(0xFFF8FAFC),
          muted: const Color(0xFF1A2330),
          mutedForeground: const Color(0xFF94A3B8),
          accent: const Color(0xFF1E293B),
          accentForeground: const Color(0xFFF8FAFC),
          destructive: const Color(0xFFEF4444),
          destructiveForeground: const Color(0xFFFEF2F2),
          border: const Color(0xFF243040),
          input: const Color(0xFF1A2330),
          ring: const Color(0xFF22C55E),
          selection: const Color(0xFF14532D),
        ),
        textTheme: _text(dark: true),
      );

  static ShadThemeData get light => ShadThemeData(
        brightness: Brightness.light,
        colorScheme: ShadColorScheme(
          background: const Color(0xFFF7F9FB),
          foreground: const Color(0xFF0F172A),
          card: const Color(0xFFFFFFFF),
          cardForeground: const Color(0xFF0F172A),
          popover: const Color(0xFFFFFFFF),
          popoverForeground: const Color(0xFF0F172A),
          primary: const Color(0xFF16A34A),
          primaryForeground: const Color(0xFFF0FDF4),
          secondary: const Color(0xFFF1F5F9),
          secondaryForeground: const Color(0xFF0F172A),
          muted: const Color(0xFFF1F5F9),
          mutedForeground: const Color(0xFF64748B),
          accent: const Color(0xFFF1F5F9),
          accentForeground: const Color(0xFF0F172A),
          destructive: const Color(0xFFDC2626),
          destructiveForeground: const Color(0xFFFEF2F2),
          border: const Color(0xFFE2E8F0),
          input: const Color(0xFFE2E8F0),
          ring: const Color(0xFF16A34A),
          selection: const Color(0xFFDCFCE7),
        ),
        textTheme: _text(dark: false),
      );

  /// Judul lebih rapat + tebal; teks kecil sedikit lebih lega.
  static ShadTextTheme _text({required bool dark}) {
    final fg = dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    return ShadTextTheme(
      h3: TextStyle(
        fontSize: 26,
        height: 1.15,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: fg,
      ),
      h4: TextStyle(
        fontSize: 19,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: fg,
      ),
      large: TextStyle(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: fg,
      ),
      small: TextStyle(
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      ),
    );
  }
}
