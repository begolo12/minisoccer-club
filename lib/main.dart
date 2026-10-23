import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/db.dart';
import 'core/registration.dart';
import 'core/update.dart';
import 'data/auth.dart';
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
    if (kIsWeb && isRegisterLocation(Uri.base)) {
      _register = true;
    }
    await Auth.restore();
    // Antrean tulis offline dibaca dari disk sebelum layar apa pun tampil,
    // supaya banner "N perubahan menunggu" langsung benar.
    await Db.loadOffline();

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

    try {
      await Db.query('SELECT 1');
      if (mounted) {
        setState(() {
          _checking = false;
          _signedIn = true;
          _error = null;
        });
      }
      // Cek versi di latar (maks. sekali per 12 jam). Tidak di-await dan
      // tidak pernah melempar, jadi layar utama tidak menunggu jaringan.
      UpdateService.autoCheck();
    } catch (e) {
      if (e is Unauthorized) {
        await Auth.expire();
        if (mounted) {
          setState(() {
            _checking = false;
            _signedIn = false;
            _error = null;
          });
        }
        return;
      }
      // Offline tapi punya sesi: jangan hadang dengan layar error. Masuk ke
      // shell; setiap pembacaan akan jatuh ke cache (Db.query) dan bilah
      // "Offline" menyala. Layar error hanya untuk kasus tanpa cache sama
      // sekali, yang akan terlihat sebagai error di dalam shell.
      if (mounted) {
        setState(() {
          _checking = false;
          _signedIn = true;
          _error = null;
        });
      }
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
