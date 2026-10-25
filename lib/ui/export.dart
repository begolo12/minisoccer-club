/// Ekspor & bagikan data ke luar aplikasi.
///
/// Klub mengelola uang bersama, dan luaran pengelolaannya hampir selalu
/// dikonsumsi DI LUAR aplikasi: bendahara menempel laporan kas ke grup
/// WhatsApp, membuka CSV di Excel/Sheets, atau menyebarkan daftar yang
/// belum bayar. Aplikasi yang tidak punya jalan keluar memaksa orang
/// menyalin angka satu per satu dengan tangan.
///
/// Jalur yang dipakai sengaja minim: clipboard (semua platform, tanpa
/// izin) dan unduhan berkas (web saja — APK tidak punya sheet berbagi
/// tanpa dependensi tambahan).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/save_file.dart';
import 'fmt.dart';
import 'theme.dart';

/// Satu sel CSV: apit kutip dan gandakan kutip dalam bila berisi pemisah,
/// baris baru, atau kutip. Nominal tetap angka polos supaya Excel/Sheets
/// langsung mengenalinya sebagai angka, bukan teks.
String csvCell(Object? v) {
  final s = switch (v) {
    null => '',
    double d => d % 1 == 0 ? d.toInt().toString() : d.toString(),
    _ => '$v',
  };
  final needsQuote = s.contains(';') || s.contains('"') || s.contains('\n') || s.contains('\r');
  if (!needsQuote) return s;
  return '"${s.replaceAll('"', '""')}"';
}

/// Gabungkan baris jadi CSV. Pemisah `;` dan baris `\r\n`: Excel Indonesia
/// memakai daftar pemisah titik-koma (desimal koma), jadi CSV koma malah
/// masuk satu kolom. Konten diawali BOM agar Excel membacanya UTF-8.
String buildCsv(List<List<Object?>> rows) {
  final buf = StringBuffer('\uFEFF');
  for (var i = 0; i < rows.length; i++) {
    buf.write(rows[i].map(csvCell).join(';'));
    if (i < rows.length - 1) buf.write('\r\n');
  }
  return buf.toString();
}

/// Salin teks ke clipboard lalu beri tahu. Kegagalan clipboard jarang, tapi
/// jangan diam: tanpa pesan, tombol yang tampak gagal sama saja dengan
/// tombol rusak.
Future<void> copyText(BuildContext context, String text, {String message = 'Disalin'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) toast(context, message);
}

/// Dialog ekspor CSV: pratinjau ringkas, salin ke clipboard, dan di web
/// tersedia unduhan berkas.
Future<void> showCsvExport(
  BuildContext context, {
  required String title,
  required String description,
  required String filename,
  required String csv,
}) {
  return showShadDialog<void>(
    context: context,
    builder: (ctx) {
      final t = ShadTheme.of(ctx);
      return ShadDialog(
        title: Text(title),
        description: Text(description),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.colorScheme.muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.colorScheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PRATINJAU',
                    style: t.textTheme.h4.copyWith(fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    // Cukup dua baris pertama sebagai contoh bentuknya.
                    csv
                        .split('\n')
                        .take(3)
                        .join('\n')
                        .replaceAll('\uFEFF', ''),
                    maxLines: 3,
                    style: t.textTheme.small.copyWith(fontFeatures: AppThemes.tabular),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ShadButton.outline(
                  onPressed: () async {
                    await copyText(ctx, csv, message: 'CSV disalin — tempel di Excel/Sheets');
                  },
                  leading: const Icon(Icons.copy_rounded, size: 15),
                  child: const Text('Salin CSV'),
                ),
                if (canSaveFile)
                  ShadButton(
                    onPressed: () async {
                      try {
                        await saveTextFile(filename, 'text/csv;charset=utf-8', csv);
                      } catch (e) {
                        if (ctx.mounted) toast(ctx, 'Gagal mengunduh: ${errText(e)}');
                      }
                    },
                    leading: const Icon(Icons.download_rounded, size: 15),
                    child: Text('Unduh $filename'),
                  ),
              ],
            ),
            if (!canSaveFile) ...[
              const SizedBox(height: 8),
              Text(
                'Di HP, salin CSV lalu tempel ke Sheets/Excel — kolomnya otomatis terpisah.',
                style: t.textTheme.small,
              ),
            ],
          ],
        ),
      );
    },
  );
}

/// Dialog pratinjau teks siap-tempel (pesan tunggakan, hasil laga).
/// Pratinjunya bisa diseleksi supaya pengguna bisa mengambil sebagian.
Future<void> showTextShare(
  BuildContext context, {
  required String title,
  required String description,
  required String text,
}) {
  return showShadDialog<void>(
    context: context,
    builder: (ctx) {
      final t = ShadTheme.of(ctx);
      return ShadDialog(
        title: Text(title),
        description: Text(description),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
          ShadButton(
            onPressed: () async {
              await copyText(ctx, text, message: 'Pesan disalin — tempel di grup');
              if (ctx.mounted) Navigator.pop(ctx);
            },
            leading: const Icon(Icons.copy_rounded, size: 15),
            child: const Text('Salin pesan'),
          ),
        ],
        child: Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: t.colorScheme.muted.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: t.colorScheme.border),
          ),
          child: SelectableText(
            text,
            style: t.textTheme.small.copyWith(height: 1.6),
          ),
        ),
      );
    },
  );
}
