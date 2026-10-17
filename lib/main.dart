import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/db.dart';
import 'data/auth.dart';
import 'ui/theme.dart';
import 'ui/login.dart';
import 'ui/onboarding.dart';
import 'ui/shell.dart';

void main() => runApp(const App());

class App extends StatefulWidget {
  const App({super.key});

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
      home: const Bootstrap(),
    );
  }
}

/// Cek koneksi DB, lalu gerbang login.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

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
    if (Db.needsUrl) {
      final saved = await SecureStore.read('neon_url');
      if (saved == null || saved.trim().isEmpty) {
        if (mounted) setState(() => _ready = false);
        return;
      }
    }
    try {
      await Db.query('SELECT 1');
      await Auth.restore();
      if (mounted) {
        setState(() {
          _ready = true;
          _signedIn = Auth.signedIn;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_ready == false) {
      return Onboarding(error: _error, onDone: () => setState(() => _ready = true));
    }
    if (!_signedIn) {
      return LoginPage(onSignedIn: () => setState(() => _signedIn = true));
    }
    return const HomeShell();
  }
}
