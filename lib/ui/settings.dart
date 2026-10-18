import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/api.dart';
import '../core/db.dart';
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
                        if (context.mounted) toast(context, 'Gagal: $e');
                      }
                    },
                    child: const Text('Tes koneksi'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Akun'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(Auth.username ?? '—',
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            switch (Auth.role) {
                              'admin' => 'Admin',
                              'treasurer' => 'Bendahara',
                              _ => 'Anggota',
                            },
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
                const SizedBox(height: 12),
                ShadButton.outline(
                  onPressed: () async {
                    if (!await confirm(context, 'Keluar?', 'Kamu perlu login lagi untuk masuk.')) return;
                    await Auth.logout();
                    if (!context.mounted) return;
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                  child: const Text('Keluar'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Tentang'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Minisoccer Club v1.6.0', style: const TextStyle(fontWeight: FontWeight.w600)),
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
