import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import 'theme.dart';
import 'widgets.dart';

/// Layar masuk. Kalau belum ada user sama sekali, tampilkan form buat admin.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool? _bootstrap;
  String? _err;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final need = await Auth.needsBootstrap();
      if (mounted) setState(() => _bootstrap = need);
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      if (_bootstrap == true) {
        await Auth.register(_user.text, _pass.text);
      } else {
        await Auth.login(_user.text, _pass.text);
      }
      if (mounted) widget.onSignedIn();
    } catch (e) {
      if (mounted) setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final dark = t.brightness == Brightness.dark;
    final firstRun = _bootstrap == true;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              t.colorScheme.primary.withValues(alpha: dark ? 0.10 : 0.08),
              t.colorScheme.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppThemes.oilA, Color(0xFF0F7A3D)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: AppThemes.oilA.withValues(alpha: 0.35),
                              blurRadius: 22,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.sports_soccer, color: Colors.white, size: 30),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(child: Text('Minisoccer Club', style: t.textTheme.h2)),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        firstRun ? 'Buat akun admin pertama' : 'Masuk untuk mengelola klub',
                        style: t.textTheme.small,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 26),
                    if (_bootstrap == null && _err == null)
                      const Center(child: CircularProgressIndicator())
                    else
                      OilCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ShadInput(
                              controller: _user,
                              placeholder: const Text('Username'),
                              autocorrect: false,
                              enabled: !_busy,
                            ),
                            const SizedBox(height: 10),
                            ShadInput(
                              controller: _pass,
                              placeholder: Text(firstRun ? 'Password (min. 6 karakter)' : 'Password'),
                              obscureText: true,
                              enabled: !_busy,
                              onSubmitted: (_) => _busy ? null : _submit(),
                            ),
                            if (_err != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _err!,
                                style: TextStyle(color: t.colorScheme.destructive, fontSize: 12.5),
                              ),
                            ],
                            const SizedBox(height: 16),
                            ShadButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(firstRun ? 'Buat akun & masuk' : 'Masuk'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),
                    Text(
                      firstRun
                          ? 'Akun ini jadi admin. Password disimpan sebagai hash bcrypt di database — '
                              'tidak pernah dikirim ke mana pun selain server.'
                          : 'Lupa password? Minta admin mengatur ulang lewat menu Pengguna.',
                      style: t.textTheme.small,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
