import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/db.dart';

/// Layar pertama: hubungkan ke Neon.
/// Cukup tempel connection string — schema dibuat otomatis.
class Onboarding extends StatefulWidget {
  const Onboarding({super.key, this.error, required this.onDone});

  final String? error;
  final VoidCallback onDone;

  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _ctrl.text.trim();
    if (!url.startsWith('postgres')) {
      setState(() => _err = 'URL harus diawali postgresql://');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await SecureStore.write('neon_url', url);
      await Db.close();
      await Db.query('SELECT 1');

      // Setup schema otomatis (idempotent).
      final sql = await rootBundle.loadString('db/schema.sql');
      for (final stmt in sql.split(';')) {
        final clean = stmt
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('--'))
            .join('\n')
            .trim();
        if (clean.isEmpty) continue;
        await Db.execute(clean);
      }
      widget.onDone();
    } catch (e) {
      await SecureStore.delete('neon_url');
      if (mounted) {
        setState(() => _err = 'Gagal terhubung. Cek URL & koneksi internet.\n\n$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('⚽', style: TextStyle(fontSize: 30)),
                  ),
                  const SizedBox(height: 24),
                  Text('Minisoccer Club', style: t.textTheme.h2),
                  const SizedBox(height: 8),
                  Text(
                    'Satu tempat untuk anggota, jadwal tanding, iuran, dan booking lapangan.',
                    style: t.textTheme.muted,
                  ),
                  const SizedBox(height: 28),
                  ShadCard(
                    title: const Text('Hubungkan database'),
                    description: const Text(
                      'Tempel connection string Neon dari dashboard Vercel / Neon. '
                      'Tabel dibuat otomatis, tidak perlu SQL manual.',
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ShadInput(
                          controller: _ctrl,
                          placeholder: const Text('postgresql://user:pass@ep-xxx.neon.tech/neondb'),
                          maxLines: 3,
                          minLines: 3,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enabled: !_busy,
                        ),
                        if (_err != null) ...[
                          const SizedBox(height: 12),
                          Text(_err!, style: TextStyle(color: t.colorScheme.destructive, fontSize: 13)),
                        ],
                        const SizedBox(height: 16),
                        ShadButton(
                          onPressed: _busy ? null : _connect,
                          child: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Hubungkan & siapkan'),
                        ),
                      ],
                    ),
                  ),
                  if (widget.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Koneksi terakhir gagal:\n${widget.error}',
                      style: TextStyle(color: t.colorScheme.destructive, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    'Tips: buka console.neon.tech → Connection Details → copy "Connection string". '
                    'Pastikan ada ?sslmode=require.',
                    style: t.textTheme.small,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
