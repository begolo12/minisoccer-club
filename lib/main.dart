import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/db.dart';
import 'core/registration.dart';
import 'core/update.dart';
import 'data/auth.dart';
import 'ui/fmt.dart';
import 'ui/register.dart';
import 'ui/theme.dart';
import 'ui/shell.dart';
import 'ui/widgets.dart';

void main({int initialTab = 0}) => runApp(App(initialTab: initialTab));

class App extends StatefulWidget {
  const App({super.key, this.initialTab = 0});

  /// Tab awal saat dibuka. Dipakai preview UI; app normal selalu 0.
  final int initialTab;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    ThemeController.load();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) {
        // Sejak Android 15 (targetSdk 36) aplikasi wajib edge-to-edge: isi
        // jendela digambar sampai bawah bilah sistem. Ikon jam/baterai harus
        // diset terang atau gelap mengikuti tema, kalau tidak di tema terang
        // ikonnya putih di atas latar terang dan tidak terbaca.
        final dark = mode == ThemeMode.dark ||
            (mode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            // Kontras ikon bilah navigasi tetap terjaga di kedua tema.
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
          ),
          child: ShadApp(
            title: 'Minisoccer Club',
            debugShowCheckedModeBanner: false,
            theme: AppThemes.light,
            darkTheme: AppThemes.dark,
            themeMode: mode,
            locale: const Locale('id', 'ID'),
            supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            scrollBehavior: const AppScrollBehavior(),
            home: ShadSonner(child: Bootstrap(initialTab: widget.initialTab)),
          ),
        );
      },
    );
  }
}

/// Cek sesi tersimpan, lalu gerbang login.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  bool _checking = true;
  bool _signedIn = false;
  String? _error;

  /// Tautan publik `/daftar` membuka formulir pendaftaran, bukan aplikasi.
  ///
  /// Hanya di web: APK tidak punya URL, dan pendaftaran di sana dilakukan
  /// admin lewat menu Anggota.
  bool _register = false;

  @override
  void initState() {
    super.initState();
    Auth.session.addListener(_onSession);
    Db.onSessionExpired = Auth.expire;
    _check();
  }

  @override
  void dispose() {
    Auth.session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() => _signedIn = Auth.session.value);
  }

  Future<void> _check() async {
    if (mounted) setState(() => _checking = true);
    try {
      if (kIsWeb && isRegisterLocation(Uri.base)) {
        _register = true;
      }
      await Auth.restore();
      // Antrean tulis offline dibaca dari disk sebelum layar apa pun tampil,
      // supaya banner "N perubahan menunggu" langsung benar.
      await Db.loadOffline();
    } catch (e) {
      // Jalur start yang gagal (penyimpanan rusak, dsb.) tidak boleh menjadi
      // spinner abadi: layar error dengan jalan keluar adalah fallback terakhir.
      if (mounted) {
        setState(() {
          _checking = false;
          _error = errText(e);
        });
      }
      return;
    }

    // Belum ada sesi: mode publik. Aplikasi langsung terbuka dalam mode
    // baca-saja; layar masuk hanya muncul saat tombol "Masuk" ditekan.
    if (!Auth.signedIn) {
      if (mounted) {
        setState(() {
          _checking = false;
          _signedIn = false;
          _error = null;
        });
      }
      return;
    }

    // Sesi ada di perangkat: langsung buka shell, JANGAN menunggu server.
    //
    // Dulu ada `await Db.query('SELECT 1')` di sini, dan itu menahan layar
    // selama satu perjalanan penuh ke server — di jaringan 3G lambat bisa
    // terasa beberapa detik dengan layar hanya menampilkan spinner. Padahal
    // sesi sudah tersimpan lokal dan halaman pertama akan memanggil server
    // sendiri.
    //
    // Pemeriksaan sesi tetap dilakukan, tapi di latar: kalau token ditolak,
    // `Db.onSessionExpired` (Auth.expire) memicu listener `Auth.session` dan
    // layar kembali ke mode publik. Pengguna melihat konten, bukan spinner.
    if (mounted) {
      setState(() {
        _checking = false;
        _signedIn = true;
        _error = null;
      });
    }
    UpdateService.autoCheck();
    unawaited(_validateSession());
  }

  /// Pastikan token masih berlaku, tanpa menahan tampilan.
  ///
  /// Kegagalan jaringan diabaikan: sesi yang tersimpan tetap dipakai dan
  /// pembacaan data akan jatuh ke cache. Yang perlu ditindak hanya penolakan
  /// server (401), yang sudah ditangani `Db` lewat `onSessionExpired`.
  Future<void> _validateSession() async {
    try {
      await Db.query('SELECT 1');
    } catch (_) {
      // Offline atau server sibuk: bukan alasan menghalangi pengguna.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: SizedBox(width: 180, child: ShadProgress(minHeight: 4)),
        ),
      );
    }
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: ErrorState(
            error: _error!,
            title: 'Server belum bisa dihubungi',
            onRetry: _check,
            extra: TextButton(
              onPressed: () async {
                await Auth.logout();
                if (mounted) setState(() => _error = null);
              },
              child: const Text('Keluar dari akun'),
            ),
          ),
        ),
      );
    }
    if (_register) {
      return RegisterPage(
        onDone: () => setState(() => _register = false),
      );
    }
    // Shell selalu tampil; tamu melihat data tanpa tombol tulis, dan
    // "Masuk" ada di bilah mode publik.
    return HomeShell(
      initialTab: widget.initialTab,
      readOnly: !_signedIn,
    );
  }
}
