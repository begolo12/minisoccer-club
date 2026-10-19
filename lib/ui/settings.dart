import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/db.dart';
import 'bootstrap.dart';
import 'fmt.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _dark = true;
  String? _url;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final theme = await SecureStore.read('theme');
    final url = await SecureStore.read('neon_url');
    if (mounted) {
      setState(() {
        _dark = theme != 'light';
        _url = url;
      });
    }
  }

  Future<void> _setDark(bool v) async {
    setState(() => _dark = v);
    await SecureStore.write('theme', v ? 'dark' : 'light');
    toast(context, 'Tema ${v ? "gelap" : "terang"} — buka ulang app untuk terapkan');
  }

  /// Sembunyikan password pada connection string.
  String _masked(String url) {
    final i = url.indexOf('://');
    final at = url.lastIndexOf('@');
    if (i < 0 || at < 0) return url;
    final userInfo = url.substring(i + 3, at);
    final colon = userInfo.indexOf(':');
    if (colon < 0) return url;
    return url.replaceFirst(userInfo, '${userInfo.substring(0, colon)}:••••');
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan'), backgroundColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          const SectionTitle('Tampilan'),
          Container(
            decoration: BoxDecoration(
              color: t.colorScheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.colorScheme.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: ShadSwitch(
              value: _dark,
              label: const Text('Mode gelap'),
              sublabel: const Text('Nyaman dipakai malam hari'),
              onChanged: _setDark,
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Database'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.colorScheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.colorScheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Neon Postgres', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  _url == null ? 'Belum terhubung' : _masked(_url!),
                  style: t.textTheme.small,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ShadButton.outline(
                        onPressed: () async {
                          await SecureStore.delete('neon_url');
                          await Db.close();
                          if (!context.mounted) return;
                          // Ganti seluruh root dengan Bootstrap baru. Versi lama
                          // memanggil Navigator.pop() pada context Settings yang
                          // sudah dihapus -> "Null check operator used on a null
                          // value" (Navigator.of: navigator!) setelah connect
                          // berhasil, lalu URL ikut terhapus.
                          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const Bootstrap()),
                            (_) => false,
                          );
                        },
                        child: const Text('Ganti koneksi'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ShadButton.ghost(
                      onPressed: () async {
                        try {
                          await Db.query('SELECT 1');
                          if (context.mounted) toast(context, 'Koneksi OK ✓');
                        } catch (e) {
                          if (context.mounted) toast(context, 'Gagal: $e');
                        }
                      },
                      child: const Text('Tes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionTitle('Tentang'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.colorScheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.colorScheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Minisoccer Club v1.0.0', style: const TextStyle(fontWeight: FontWeight.w600)),
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
