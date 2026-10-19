import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/db.dart';
import 'ui/theme.dart';
import 'ui/bootstrap.dart';

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
