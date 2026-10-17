import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Tema app — shadcn, dark default, light tersedia.
/// Aksen: hijau lapangan.
class AppThemes {
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
      );
}
