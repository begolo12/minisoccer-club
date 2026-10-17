import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/db.dart';
import 'ui/theme.dart';
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

/// Cek apakah koneksi DB sudah dikonfigurasi & hidup.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key});

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<Bootstrap> {
  bool? _ready;
  String? _error;

  @override
  void initState() {
    super.initState();
    _check();
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
      if (mounted) setState(() => _ready = true);
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
    return const HomeShell();
  }
}
