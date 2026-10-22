/// Tawaran pembaruan tepat setelah aplikasi dibuka.
///
/// Kenapa perlu: sebelumnya pembaruan hanya terlihat sebagai titik hijau pada
/// baris "Pengaturan" di tab Lainnya. Pengguna yang tidak pernah membuka tab
/// itu tidak akan tahu ada versi baru — jadi pembaruan praktis tidak pernah
/// terpasang, dan aplikasi lama terus dipakai.
///
/// Alur: cek di latar → kalau ada versi baru yang belum pernah ditutup →
/// dialog → satu ketukan "Perbarui sekarang" langsung mengunduh dan membuka
/// installer. Android tetap meminta konfirmasi "Pasang" (tidak bisa dilewati
/// aplikasi biasa), jadi ini semaksimal yang diizinkan sistem.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/update.dart';
import 'fmt.dart';

/// Tampilkan tawaran pembaruan kalau memang ada. Aman dipanggil kapan saja:
/// tidak melakukan apa pun di web, di luar Android, atau kalau tidak ada
/// pembaruan.
Future<void> maybePromptUpdate(BuildContext context) async {
  // Web tidak memasang APK: versi baru terpakai sendiri saat halaman dimuat
  // ulang. Platform lain (iOS/desktop) juga tidak bisa memasang sendiri.
  if (kIsWeb || !canSelfUpdate) return;

  final check = UpdateService.latest.value;
  final release = check?.release;
  if (check == null || release == null) return;

  final dismissed = await UpdateService.dismissedVersion();
  if (!shouldOfferUpdate(check, dismissed)) return;
  if (!context.mounted) return;

  final go = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => ShadDialog(
      title: Text('Versi ${release.version} tersedia'),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Versi terpasang: v${check.current} • ${fmtBytes(release.sizeBytes)}'),
          if (release.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Catatan rilis dipotong: dialog bukan tempat membaca changelog
            // panjang, dan tombolnya bisa terdorong keluar layar.
            Text(
              _shortNotes(release.notes),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Nanti'),
        ),
        ShadButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Perbarui sekarang'),
        ),
      ],
    ),
  );

  if (go != true) {
    // "Nanti" menunda versi INI saja; versi berikutnya tetap ditawarkan.
    await UpdateService.dismiss(release.version);
    return;
  }
  if (!context.mounted) return;

  final message = await showShadDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _InstallDialog(release: release),
  );
  if (message != null && context.mounted) toast(context, message);
}

/// Ambil beberapa baris pertama catatan rilis.
String _shortNotes(String notes) {
  final lines = notes
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .take(4)
      .join('\n');
  return lines.isEmpty ? notes : lines;
}

/// Unduh + buka installer, dengan progres. Menutup diri sendiri saat selesai
/// dan mengembalikan pesan untuk ditampilkan pemanggil.
class _InstallDialog extends StatefulWidget {
  const _InstallDialog({required this.release});

  final ReleaseInfo release;

  @override
  State<_InstallDialog> createState() => _InstallDialogState();
}

class _InstallDialogState extends State<_InstallDialog> {
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Dijalankan setelah frame pertama supaya dialog sempat tampil; unduhan
    // 58 MB butuh beberapa detik dan layar kosong terlihat seperti hang.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final path = await downloadApk(
        widget.release,
        onProgress: (got, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = (got / total).clamp(0.0, 1.0));
        },
      );
      if (!mounted) return;
      final outcome = await installApk(path);
      if (!mounted) return;
      Navigator.of(context).pop(switch (outcome) {
        InstallOutcome.started => 'Installer terbuka. Ketuk "Pasang" untuk menyelesaikan.',
        InstallOutcome.needsPermission =>
          'Izinkan "Pasang aplikasi tak dikenal" untuk Minisoccer, lalu ulangi.',
        InstallOutcome.failed => 'Installer tidak bisa dibuka. Unduh manual dari GitHub.',
      });
    } catch (e) {
      if (!mounted) return;
      // Kegagalan unduhan (jaringan putus, sha256 tidak cocok) ditampilkan di
      // dalam dialog: menutupnya lalu menampilkan toast membuat pengguna tidak
      // tahu apa yang terjadi.
      setState(() => _error = errText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final error = _error;
    return ShadDialog(
      title: Text('Memperbarui ke v${widget.release.version}'),
      description: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null) ...[
            Text(error),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Tutup'),
                ),
              ],
            ),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 8,
                color: t.colorScheme.primary,
                backgroundColor: t.colorScheme.muted,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _progress == 0
                  ? 'Mengunduh…'
                  : '${(_progress * 100).round()}% • jangan tutup aplikasi',
            ),
          ],
        ],
      ),
    );
  }
}
