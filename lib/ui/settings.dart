import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/api.dart';
import '../core/db.dart';
import '../core/offline.dart';
import '../core/update.dart';
import 'login.dart';
import '../core/version.dart';
import '../data/auth.dart';
import 'fmt.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _dark = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final theme = await SecureStore.read('theme');
    if (mounted) setState(() => _dark = theme != 'light');
  }

  Future<void> _setDark(bool v) async {
    setState(() => _dark = v);
    await ThemeController.setDark(v);
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Pengaturan',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const SectionTitle('Tampilan'),
          Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: ShadSwitch(
              value: _dark,
              label: const Text('Mode gelap'),
              sublabel: const Text('Nyaman dipakai malam hari'),
              onChanged: _setDark,
              padding: const EdgeInsetsDirectional.only(start: 12),
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Server'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Neon Postgres', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  kApiBase.isEmpty ? 'Host web ini (same-origin)' : kApiBase,
                  style: t.textTheme.small,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'Kredensial database hanya ada di server. Aplikasi tidak menyimpannya.',
                  style: t.textTheme.small,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ShadButton.outline(
                    onPressed: () async {
                      try {
                        await Db.query('SELECT 1');
                        if (context.mounted) toast(context, 'Koneksi OK');
                      } catch (e) {
                        if (context.mounted) toast(context, 'Gagal: ${errText(e)}');
                      }
                    },
                    child: const Text('Tes koneksi'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Data offline'),
          _OfflinePanel(),
          const SizedBox(height: 22),
          const SectionTitle('Akun'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (Auth.isGuest) ...[
                  Text(
                    'Kamu sedang memakai mode publik',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Semua data klub bisa dilihat. Untuk menambah atau mengubah '
                    'data, masuk dengan akun admin atau bendahara.',
                    style: t.textTheme.small,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ShadButton(
                      onPressed: () async {
                        final ok = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => LoginPage(
                              onSignedIn: () => Navigator.pop(ctx, true),
                            ),
                          ),
                        );
                        if (ok == true && context.mounted) {
                          setState(() {});
                          toast(context, 'Masuk sebagai ${Auth.username}');
                        }
                      },
                      leading: const Icon(Icons.login, size: 16),
                      child: const Text('Masuk ke akun'),
                    ),
                  ),
                ] else
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(Auth.username ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          // Role sudah tampil di label kanan; baris ini
                          // menjelaskan artinya, bukan mengulang namanya.
                          Text(
                            Auth.canWrite ? 'Bisa mengubah data' : 'Hanya membaca',
                            style: t.textTheme.small,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      switch (Auth.role) {
                        'admin' => 'ADMIN',
                        'treasurer' => 'BENDAHARA',
                        _ => 'ANGGOTA',
                      },
                      style: TextStyle(
                        fontFamily: AppThemes.display,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: t.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                if (!Auth.isGuest) ...[
                  const SizedBox(height: 12),
                  ShadButton.outline(
                    onPressed: () async {
                      if (!await confirm(context, 'Keluar?',
                          'Kamu akan kembali ke mode publik (hanya melihat).',
                          confirmLabel: 'Keluar')) {
                        return;
                      }
                      await Auth.logout();
                      if (!context.mounted) return;
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    child: const Text('Keluar'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Pembaruan'),
          _UpdatePanel(),
          const SizedBox(height: 22),
          const SectionTitle('Tentang'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Minisoccer Club v$kAppVersion', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  'Dibuat dengan Flutter + shadcn UI + Neon Postgres.\n'
                  'Data tersimpan langsung di database Neon kamu.',
                  style: t.textTheme.small,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu pembaruan: cek versi terbaru di GitHub, unduh APK, lalu buka
/// installer sistem.
///
/// Android tidak mengizinkan aplikasi biasa memasang APK tanpa konfirmasi,
/// jadi "otomatis" di sini berarti: cek otomatis saat app dibuka, unduh
/// otomatis saat ditekan, dan installer langsung terbuka. Ketukan "Pasang"
/// terakhir milik user.
class _UpdatePanel extends StatefulWidget {
  @override
  State<_UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<_UpdatePanel> {
  UpdateCheck? _check;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String? _readyPath;

  @override
  void initState() {
    super.initState();
    _check = UpdateService.latest.value;
    UpdateService.latest.addListener(_onShared);
    // Kalau pemeriksaan latar belum jalan (mis. dibuka dari deep link),
    // jalankan di sini.
    if (_check == null) _auto();
  }

  @override
  void dispose() {
    UpdateService.latest.removeListener(_onShared);
    super.dispose();
  }

  void _onShared() {
    if (!mounted) return;
    final next = UpdateService.latest.value;
    if (next != null) setState(() => _check = next);
  }

  Future<void> _auto() async {
    await UpdateService.autoCheck();
    if (mounted) setState(() => _check = UpdateService.latest.value);
  }

  Future<void> _runCheck() async {
    setState(() {
      _checking = true;
      _readyPath = null;
    });
    final result = await UpdateService.checkNow();
    if (!mounted) return;
    setState(() {
      _check = result;
      _checking = false;
    });
    if (result.error != null) {
      toast(context, errText(result.error!));
    } else if (!result.hasUpdate) {
      toast(context, 'Sudah versi terbaru (v${result.current})');
    }
  }

  Future<void> _download(ReleaseInfo release) async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      final path = await downloadApk(
        release,
        onProgress: (got, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = (got / total).clamp(0, 1));
        },
      );
      if (!mounted) return;
      setState(() => _readyPath = path);
      await _install(path);
    } catch (e) {
      if (mounted) toast(context, errText(e));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _install(String path) async {
    final outcome = await installApk(path);
    if (!mounted) return;
    switch (outcome) {
      case InstallOutcome.started:
        toast(context, 'Installer terbuka. Ketuk "Pasang" untuk menyelesaikan.');
      case InstallOutcome.needsPermission:
        toast(context, 'Izinkan "Pasang aplikasi tak dikenal" untuk Minisoccer, lalu ulangi.');
      case InstallOutcome.failed:
        toast(context, 'Installer tidak bisa dibuka. Unduh manual dari GitHub.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final check = _check;
    final release = check?.release;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Versi terpasang v$kAppVersion',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _checking
                          ? 'Memeriksa GitHub…'
                          : (check == null ? 'Belum diperiksa' : check.status),
                      style: t.textTheme.small,
                    ),
                  ],
                ),
              ),
              if (check != null && check.hasUpdate)
                Pill('v${release!.version}', color: t.colorScheme.primary),
            ],
          ),
          if (release != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.colorScheme.muted.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${release.tag} • ${fmtBytes(release.sizeBytes)} • '
                    '${fmtDate(release.publishedAt)}',
                    style: t.textTheme.small,
                  ),
                  if (release.notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      release.notes,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.small.copyWith(color: t.colorScheme.foreground),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_downloading) ...[
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                minHeight: 5,
                backgroundColor: t.colorScheme.muted,
                color: t.colorScheme.primary,
              ),
              const SizedBox(height: 6),
              Text(
                'Mengunduh ${(_progress * 100).round()}%',
                style: t.textTheme.small,
              ),
              const SizedBox(height: 8),
            ],
            if (canSelfUpdate)
              ShadButton(
                onPressed: _downloading
                    ? null
                    : (_readyPath != null
                        ? () => _install(_readyPath!)
                        : () => _download(release)),
                leading: Icon(
                  _readyPath != null ? Icons.install_desktop : Icons.system_update_alt,
                  size: 16,
                ),
                child: Text(
                  _readyPath != null
                      ? 'Buka installer'
                      : 'Unduh & pasang v${release.version}',
                ),
              )
            else
              Text(
                'Pembaruan APK hanya bisa dipasang dari aplikasi Android. '
                'Di web, versi baru otomatis terpakai saat halaman dimuat ulang.',
                style: t.textTheme.small,
              ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: ShadButton.outline(
              onPressed: _checking || _downloading ? null : _runCheck,
              leading: const Icon(Icons.refresh, size: 15),
              child: Text(_checking ? 'Memeriksa…' : 'Cek pembaruan'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Panel mode offline: berapa perubahan menunggu, tombol sinkron, dan cara
/// membuang antrean. Ini satu-satunya tempat pengguna bisa melihat apa yang
/// belum terkirim — penting karena data itu belum ada di cloud.
class _OfflinePanel extends StatefulWidget {
  const _OfflinePanel();

  @override
  State<_OfflinePanel> createState() => _OfflinePanelState();
}

class _OfflinePanelState extends State<_OfflinePanel> {
  bool _busy = false;

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final r = await Db.sync();
      if (!mounted) return;
      if (r.sent > 0) {
        toast(context, '${r.sent} perubahan terkirim');
      } else if (r.offline) {
        toast(context, 'Masih offline — coba lagi nanti');
      } else if (r.remaining == 0) {
        toast(context, 'Tidak ada yang perlu dikirim');
      }
      if (r.failed > 0 && mounted) {
        toast(context, '${r.failed} perubahan ditolak server');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discardFailed() async {
    final n = Outbox.failedCount;
    if (n == 0) return;
    if (!await confirm(
      context,
      'Buang $n perubahan?',
      'Perubahan yang ditolak server akan dihapus dari antrean. '
          'Data di cloud tidak terpengaruh.',
    )) {
      return;
    }
    await Db.dropFailedWrites();
    if (mounted) setState(() {});
  }

  Future<void> _discardAll() async {
    final n = Outbox.pending.value;
    if (n == 0) return;
    if (!await confirm(
      context,
      'Buang semua perubahan offline?',
      '$n perubahan yang belum terkirim akan hilang dan tidak bisa dikembalikan.',
    )) {
      return;
    }
    await Db.clearOutbox();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return ValueListenableBuilder<int>(
      valueListenable: Outbox.pending,
      builder: (context, pending, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: Db.offline,
          builder: (context, offline, _) {
            return Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        offline ? Icons.cloud_off : Icons.cloud_done_outlined,
                        size: 16,
                        color: offline ? t.colorScheme.mutedForeground : t.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          offline ? 'Offline' : 'Tersambung',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (pending > 0)
                        Pill('$pending menunggu', color: t.colorScheme.primary),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    pending == 0
                        ? 'Semua perubahan sudah tersimpan di server. '
                            'Data klub tetap bisa dibaca saat offline.'
                        : '$pending perubahan tersimpan di HP dan akan dikirim '
                            'otomatis saat tersambung. Data offline diutamakan '
                            'dan akan menimpa data cloud.',
                    style: t.textTheme.small,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ShadButton.outline(
                        onPressed: _busy || pending == 0 ? null : _sync,
                        leading: const Icon(Icons.sync, size: 15),
                        child: Text(_busy ? 'Mengirim…' : 'Sinkron sekarang'),
                      ),
                      if (Outbox.failedCount > 0)
                        ShadButton.outline(
                          onPressed: _busy ? null : _discardFailed,
                          leading: const Icon(Icons.delete_outline, size: 15),
                          child: Text('Buang ${Outbox.failedCount} yang gagal'),
                        ),
                      if (pending > 0)
                        ShadButton.outline(
                          onPressed: _busy ? null : _discardAll,
                          child: const Text('Buang semua'),
                        ),
                    ],
                  ),
                  if (Outbox.failedCount > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Sebagian perubahan ditolak server (mis. datanya sudah '
                      'dihapus di cloud). Periksa lalu buang agar tidak menumpuk.',
                      style: t.textTheme.small.copyWith(color: AppThemes.bad(context)),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
