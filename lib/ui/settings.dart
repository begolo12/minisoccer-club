import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/api.dart';
import '../core/db.dart';
import '../core/offline.dart';
import '../core/update.dart';
import 'login.dart';
import 'register.dart';
import '../core/version.dart';
import '../data/auth.dart';
import 'audit.dart';
import 'fmt.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  ThemeMode _mode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final theme = await SecureStore.read('theme');
    if (!mounted) return;
    setState(() => _mode = switch (theme) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        });
  }

  Future<void> _setMode(ThemeMode m) async {
    setState(() => _mode = m);
    await ThemeController.setMode(m);
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    // Halaman ini dipakai semua role, tapi tidak semua isinya urusan semua
    // orang. Yang teknis (alamat server, tes koneksi, antrean offline,
    // tautan pembuat akun, diagnostik layar) hanya untuk admin: anggota dan
    // tamu cukup melihat data klub, dan angka/istilah teknis di sana hanya
    // membingungkan atau membocorkan hal yang tidak perlu mereka tahu.
    //
    // Yang TETAP ada untuk semua: tema (selera perangkat masing-masing),
    // akun sendiri (ganti password, keluar), dan pembaruan aplikasi — kalau
    // ini disembunyikan, anggota yang memakai APK lama tidak punya jalan
    // untuk memperbarui.
    final admin = Auth.isAdmin;
    return PageScaffold(
      title: 'Pengaturan',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const SectionTitle('Tampilan'),
          Panel(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tema', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  // "Ikuti sistem" penting untuk pengguna yang menjadwalkan
                  // gelap otomatis di HP: app berubah sendiri tanpa dibuka.
                  'Ikuti sistem = gelap/terang mengikuti setelan HP.',
                  style: t.textTheme.small,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final (m, label) in [
                      (ThemeMode.system, 'Sistem'),
                      (ThemeMode.dark, 'Gelap'),
                      (ThemeMode.light, 'Terang'),
                    ]) ...[
                      if (m != ThemeMode.system) const SizedBox(width: 8),
                      Expanded(
                        child: _ThemeOption(
                          label,
                          selected: _mode == m,
                          onTap: () => _setMode(m),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (admin) ...[
            const SizedBox(height: 22),
            const SectionTitle('Sambungan data'),
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
            const SectionTitle('Data tanpa internet'),
            _OfflinePanel(),
            const SizedBox(height: 22),
            const SectionTitle('Jejak audit'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Mencatat siapa menambah, mengubah, dan menghapus data. '
                    'Berguna saat angka kas tidak cocok.',
                    style: t.textTheme.small,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ShadButton.outline(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AuditPage()),
                      ),
                      child: const Text('Buka jejak audit'),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                  // Password awal dari pendaftaran adalah nomor HP, jadi
                  // pemilik akun harus bisa menggantinya sendiri.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ShadButton.outline(
                      onPressed: () => showShadDialog<bool>(
                        context: context,
                        // Menutup dialog di tengah simpan membuat hasilnya
                        // tidak pernah tampil; pengguna bisa mengira
                        // passwordnya sudah berganti.
                        barrierDismissible: false,
                        builder: (_) => const _PasswordDialog(),
                      ),
                      child: const Text('Ganti password'),
                    ),
                  ),
                  const SizedBox(height: 8),
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
          if (admin) ...[
            const SizedBox(height: 22),
            const SectionTitle('Pendaftaran anggota'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Tautan pendaftaran', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Bagikan tautan ini ke calon anggota. Mereka mengisi nama, nomor HP, '
                    'alamat, dan posisi sendiri. Nama depan menjadi username, dan akun '
                    'langsung dibuat tanpa perlu ditambah manual di menu Anggota.',
                    style: t.textTheme.small,
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    registrationLink(),
                    style: t.textTheme.small.copyWith(
                      fontFamily: AppThemes.display,
                      fontSize: 13,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ShadButton.outline(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: registrationLink()));
                        if (context.mounted) toast(context, 'Tautan disalin');
                      },
                      child: const Text('Salin tautan'),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                  admin
                      ? 'Dibuat dengan Flutter + shadcn UI + Neon Postgres.\n'
                          'Data tersimpan langsung di database Neon kamu.'
                      : 'Aplikasi klub mini soccer: anggota, jadwal, iuran, '
                          'turnamen, dan kas.',
                  style: t.textTheme.small,
                ),
                // Diagnostik layar hanya untuk admin: angka refresh rate dan
                // nama teknologi adalah urusan pengurus, bukan anggota yang
                // cuma ingin melihat jadwal dan iurannya.
                if (admin) ...[
                  const SizedBox(height: 10),
                  // Angka nyata dari sistem, bukan klaim: kalau HP 120 Hz masih
                  // tertulis 60 di sini, yang membatasi adalah setelan perangkat
                  // (mode hemat daya / "refresh rate" di Pengaturan Android),
                  // bukan aplikasinya.
                  Text(_screenLine(context), style: t.textTheme.small),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Satu pilihan tema: segmen yang sama dengan pemilih tim di papan catat.
/// Ukuran 40px mengikuti pedoman sentuh — tiga pilihan di 320px tetap muat
/// satu baris karena tiap segmen memakai Expanded.
class _ThemeOption extends StatelessWidget {
  const _ThemeOption(this.label, {required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Material(
      color: selected ? t.colorScheme.primary : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? t.colorScheme.primary : t.colorScheme.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? t.colorScheme.primaryForeground : t.colorScheme.foreground,
              ),
            ),
          ),
        ),
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
                      // Di web tidak ada yang perlu diperiksa: halaman selalu
                      // memuat versi terbaru. Sebutkan itu, jangan "Belum
                      // diperiksa" yang terdengar seperti tugas yang tertunda.
                      kIsWeb
                          ? 'Versi web selalu yang terbaru setelah halaman dimuat ulang.'
                          : (_checking
                              ? 'Memeriksa GitHub…'
                              : (check == null ? 'Belum diperiksa' : check.status)),
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
          // Di web, pemeriksaan APK tidak ada gunanya: CSP produksi memblokir
          // api.github.com, dan versi web selalu yang terbaru setelah halaman
          // dimuat ulang. Tombolnya disembunyikan supaya tidak menampilkan
          // error yang tidak bisa ditindaklanjuti pengguna.
          if (!kIsWeb)
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

  Future<void> _clearCache() async {
    if (!await confirm(
      context,
      'Kosongkan data sementara?',
      'Data tersimpan untuk dibaca tanpa internet akan dihapus. Perubahan yang '
          'belum terkirim TIDAK terpengaruh. Halaman akan memuat ulang dari server.',
    )) {
      return;
    }
    final removed = await Db.clearOfflineCache();
    if (mounted) {
      setState(() {});
      toast(context, '$removed data sementara dihapus');
    }
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
                  // Antrean yang gagal dibaca/ditulis ke disk: data hanya di
                  // memori. Tanpa baris ini pengguna tidak tahu bahwa menutup
                  // app bisa menghilangkan perubahan yang tampak aman.
                  if (Outbox.loadError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${Outbox.loadError} Coba sinkron sekarang, lalu '
                        'buka ulang aplikasi.',
                        style: t.textTheme.small.copyWith(color: AppThemes.bad(context)),
                      ),
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
                      // Cache dibaca saat offline. Kalau isinya sudah tidak
                      // relevan (mis. setelah membuang antrean), pengguna harus
                      // punya cara membersihkannya tanpa menunggu restart.
                      ShadButton.outline(
                        onPressed: _busy ? null : _clearCache,
                        leading: const Icon(Icons.cleaning_services_outlined, size: 15),
                        child: const Text('Kosongkan data sementara'),
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

/// Baris diagnostik layar: refresh rate yang benar-benar dipakai sistem.
///
/// Ditampilkan supaya klaim "120 Hz" bisa diperiksa langsung di HP, bukan
/// dipercaya dari deskripsi. Angkanya berasal dari `FlutterView.display`, yaitu
/// sumber yang sama dengan yang dipakai engine untuk vsync — kalau di sini
/// tertulis 60 pada HP 120 Hz, yang membatasi adalah setelan perangkat
/// (mode hemat daya atau "refresh rate" di Pengaturan Android), bukan app.
String _screenLine(BuildContext context) {
  final display = View.of(context).display;
  final size = display.size;
  final dims = '${size.width.round()}×${size.height.round()}';
  final hz = display.refreshRate.round();
  if (hz <= 0) return 'Layar: $dims';
  final note = hz < 90 ? ' · dibatasi setelan perangkat' : '';
  return 'Layar: $dims · $hz Hz$note';
}

/// Dialog ganti password akun sendiri.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _saving = false;
  String? _err;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _err = null);
    if (_next.text.length < 8) {
      setState(() => _err = 'Password baru minimal 8 karakter');
      return;
    }
    if (_next.text != _again.text) {
      setState(() => _err = 'Ulangi password baru dengan sama');
      return;
    }
    setState(() => _saving = true);
    try {
      await Auth.changePassword(current: _current.text, next: _next.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _err = writeFailText(e, fail: 'Gagal mengganti password'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return ShadDialog(
      title: const Text('Ganti password'),
      description: const Text('Masukkan password lama, lalu password baru.'),
      actions: [
        ShadButton.outline(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Batal'),
        ),
        ShadButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Simpan'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadInput(
            controller: _current,
            obscureText: true,
            enabled: !_saving,
            autofocus: true,
            placeholder: const Text('Password lama'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          ShadInput(
            controller: _next,
            obscureText: true,
            enabled: !_saving,
            placeholder: const Text('Password baru (minimal 8 karakter)'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          ShadInput(
            controller: _again,
            obscureText: true,
            enabled: !_saving,
            placeholder: const Text('Ulangi password baru'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          if (_err != null) ...[
            const SizedBox(height: 12),
            ShadAlert.destructive(
              icon: const Icon(Icons.error_outline, size: 16),
              description: Text(_err!, style: const TextStyle(fontSize: 12.5, height: 1.45)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Sesi lain yang sedang masuk tidak ikut keluar; tokennya berlaku '
            'sampai kedaluwarsa (12 jam).',
            style: t.textTheme.small.copyWith(fontSize: 11.5, height: 1.4),
          ),
        ],
      ),
    );
  }
}
