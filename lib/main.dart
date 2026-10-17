import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/db.dart';
import 'data/auth.dart';
import 'ui/theme.dart';
import 'ui/login.dart';
import 'ui/shell.dart';

void main({int initialTab = 0}) => runApp(App(initialTab: initialTab));

class App extends StatefulWidget {
  const App({super.key, this.initialTab = 0});

  /// Tab awal saat dibuka. Dipakai preview UI; app normal selalu 0.
  final int initialTab;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  ThemeMode _mode = ThemeMode.dark;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final v = await SecureStore.read('theme');
    if (!mounted) return;
    setState(() => _mode = v == 'light' ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return ShadApp(
      title: 'Minisoccer Club',
      debugShowCheckedModeBanner: false,
      theme: AppThemes.light,
      darkTheme: AppThemes.dark,
      themeMode: _mode,
      home: ShadSonner(child: Bootstrap(initialTab: widget.initialTab)),
    );
  }
}

/// Cek koneksi DB, lalu gerbang login.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  bool? _ready;
  bool _signedIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Auth.session.addListener(_onSession);
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
    await Auth.restore();

    // Belum ada sesi: jangan sentuh DB (butuh token). Langsung ke login.
    if (!Auth.signedIn) {
      if (mounted) {
        setState(() {
          _ready = true;
          _signedIn = false;
        });
      }
      return;
    }

    try {
      await Db.query('SELECT 1');
      if (mounted) {
        setState(() {
          _ready = true;
          _signedIn = true;
        });
      }
    } catch (e) {
      if (e is Unauthorized) {
        await Auth.logout();
        if (mounted) {
          setState(() {
            _ready = true;
            _signedIn = false;
          });
        }
        return;
      }
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == null) {
      return const Scaffold(
        body: Center(
          child: SizedBox(width: 180, child: ShadProgress(minHeight: 4)),
        ),
      );
    }
    if (!_signedIn) {
      return LoginPage(
        onSignedIn: () => setState(() => _signedIn = true),
        error: _error,
      );
    }
    return HomeShell(initialTab: widget.initialTab);
  }
}
