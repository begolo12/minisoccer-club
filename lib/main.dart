import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/db.dart';
import 'data/auth.dart';
import 'ui/theme.dart';
import 'ui/login.dart';
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
      builder: (context, mode, _) => ShadApp(
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
    await Auth.restore();

    // Belum ada sesi: jangan sentuh DB (butuh token). Langsung ke login.
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
      if (mounted) {
        setState(() {
          _checking = false;
          _error = e.toString();
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
    if (!_signedIn) {
      return LoginPage(onSignedIn: () => setState(() => _signedIn = true));
    }
    return HomeShell(initialTab: widget.initialTab);
  }
}
