import 'package:flutter/material.dart';

import '../core/db.dart';
import 'onboarding.dart';
import 'shell.dart';

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
    final saved = await SecureStore.read('neon_url');
    if (saved == null || saved.trim().isEmpty) {
      if (mounted) setState(() => _ready = false);
      return;
    }
    try {
      await Db.query('SELECT 1');
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      // Tanpa ini _ready tetap null -> spinner selamanya, user tidak pernah
      // bisa kembali ke layar onboarding.
      if (mounted) {
        setState(() {
          _error = e.toString();
          _ready = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_ready == false) {
      return Onboarding(
        error: _error,
        onDone: () => setState(() {
          _ready = true;
          _error = null;
        }),
      );
    }
    return const HomeShell();
  }
}
