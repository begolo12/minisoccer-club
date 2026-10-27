import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import 'register.dart';
import 'theme.dart';
import 'widgets.dart';

/// Layar masuk. Kalau belum ada user sama sekali, tampilkan form buat admin.
///
/// Arah "Papan skor": wordmark sempit besar di kiri, form di panel bergaris
/// di kanan. Latar cuma garis lapangan tipis, tanpa cahaya dan gradien.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSignedIn});

  final VoidCallback onSignedIn;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _userFocus = FocusNode();
  bool _busy = false;
  bool _showPass = false;
  bool? _bootstrap;
  String? _err;

  /// `onSignedIn` hanya boleh sekali.
  ///
  /// Dua jalur memanggilnya: listener sesi (untuk alur pendaftaran) dan
  /// `_submit` setelah `Auth.login` selesai. `Auth.login` menyalakan sesi
  /// SEBELUM ia kembali, jadi pada login biasa keduanya menyala berdekatan —
  /// dua `Navigator.pop` beruntun, dan yang kedua mem-pop shell itu sendiri:
  /// layar jadi kosong (hanya latar) sampai halaman dimuat ulang. Itu yang
  /// terjadi di HP: login berhasil, lalu app menghilang.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _check();
    // Sesi bisa terbuka dari alur lain yang dipush DI ATAS halaman ini
    // (pendaftaran mandiri: daftar → langsung masuk). Tanpa listener,
    // kembali dari sana tetap menampilkan form masuk — jalan buntu: app di
    // belakang sudah masuk, tapi pengguna melihat layar login lagi.
    Auth.session.addListener(_onSession);
  }

  void _onSession() {
    if (!mounted || !Auth.session.value) return;
    Auth.session.removeListener(_onSession);
    _finish();
  }

  /// Tutup layar masuk, tepat satu kali.
  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onSignedIn();
  }

  @override
  void dispose() {
    Auth.session.removeListener(_onSession);
    _user.dispose();
    _pass.dispose();
    _userFocus.dispose();
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
    if (_busy) return;
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
      if (mounted) _finish();
    } catch (e) {
      if (mounted) setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstRun = _bootstrap == true;
    // Layar ini sekarang dibuka dari tombol "Masuk" (bukan gerbang wajib),
    // jadi harus ada jalan kembali ke mode publik.
    final canPop = Navigator.canPop(context);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _PitchPainter(_lineColor(context)))),
          if (canPop)
            Positioned(
              top: 8,
              right: 8,
              child: SafeArea(
                child: IconButton(
                  tooltip: 'Kembali ke mode publik',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 940),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final wide = c.maxWidth >= 800;
                      final form = _FormPanel(
                        firstRun: firstRun,
                        busy: _busy,
                        showPass: _showPass,
                        error: _err,
                        user: _user,
                        pass: _pass,
                        userFocus: _userFocus,
                        // Status bootstrap gagal diperiksa (jaringan): tanpa
                        // tombol ini, klub yang benar-benar baru tidak pernah
                        // sampai ke form "Admin pertama" — pesannya cuma error
                        // mentah dan tidak ada yang bisa ditekan.
                        onRetryCheck: _bootstrap == null
                            ? () {
                                setState(() => _err = null);
                                _check();
                              }
                            : null,
                        onTogglePass: () => setState(() => _showPass = !_showPass),
                        onSubmit: _submit,
                        onRegister: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => RegisterPage(
                              onDone: () => Navigator.pop(ctx),
                            ),
                          ),
                        ),
                      );

                      if (!wide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _Brand(compact: true),
                            const SizedBox(height: 20),
                            form,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Expanded(flex: 6, child: _Brand(compact: false)),
                          const SizedBox(width: 48),
                          Expanded(flex: 4, child: form),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _lineColor(BuildContext context) {
  final t = ShadTheme.of(context);
  return t.brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.black.withValues(alpha: 0.05);
}

/// Garis lapangan: satu garis tengah + lingkaran tengah, sangat tipis.
class _PitchPainter extends CustomPainter {
  const _PitchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;

    final cx = size.width * 0.24;
    canvas.drawCircle(Offset(cx, size.height * 0.42), size.width * 0.17, paint);
    canvas.drawLine(Offset(0, size.height * 0.42), Offset(size.width, size.height * 0.42), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Brand extends StatelessWidget {
  const _Brand({required this.compact});

  final bool compact;

  static const _points = [
    ('01', 'Jadwal & hasil', 'Sesi per babak, pemenang dihitung dari skor'),
    ('02', 'Kas klub', 'Iuran bulanan, siapa yang belum, total terkumpul'),
    ('03', 'Turnamen internal', 'Empat tim saling bertemu, klasemen otomatis'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: t.colorScheme.primary, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.sports_soccer, size: 18, color: t.colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Text(
              'MINISOCCER CLUB',
              style: TextStyle(
                fontFamily: AppThemes.display,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.4,
                color: t.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 18 : 26),
        Text(
          'Kelola klub\ndalam satu papan.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: t.textTheme.h1Large.copyWith(
            fontSize: compact ? 44 : 62,
            height: 0.95,
            color: t.colorScheme.foreground,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Anggota, jadwal tanding, iuran, dan turnamen internal.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: t.textTheme.muted,
        ),
        if (!compact) ...[
          const SizedBox(height: 30),
          for (final p in _points)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.$1,
                    style: TextStyle(
                      fontFamily: AppThemes.display,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: t.colorScheme.primary,
                      fontFeatures: AppThemes.tabular,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.$2, style: t.textTheme.large),
                        const SizedBox(height: 1),
                        Text(p.$3, style: t.textTheme.small),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Form masuk / buat admin pertama.
class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.firstRun,
    required this.busy,
    required this.showPass,
    required this.error,
    required this.user,
    required this.pass,
    required this.userFocus,
    required this.onTogglePass,
    required this.onSubmit,
    required this.onRegister,
    this.onRetryCheck,
  });

  final bool firstRun;
  final bool busy;
  final bool showPass;
  final String? error;
  final TextEditingController user;
  final TextEditingController pass;
  final FocusNode userFocus;
  final VoidCallback onTogglePass;
  final VoidCallback onSubmit;
  final VoidCallback onRegister;

  /// Terisi hanya kalau pemeriksaan "belum ada akun?" gagal — pengguna bisa
  /// mencoba lagi tanpa menutup layar.
  final VoidCallback? onRetryCheck;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pill(firstRun ? 'Admin pertama' : 'Masuk', color: t.colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            firstRun ? 'Belum ada akun' : 'Masuk ke klub',
            style: t.textTheme.h3.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 4),
          Text(
            firstRun
                ? 'Buat admin pertama untuk mulai mengelola klub.'
                : 'Pakai akun yang diberikan admin klub.',
            style: t.textTheme.small,
          ),
          const SizedBox(height: 20),
          _Field(
            label: 'Nama pengguna',
            child: ShadInput(
              controller: user,
              focusNode: userFocus,
              enabled: !busy,
              autocorrect: false,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              placeholder: const Text('mis. budi'),
              onSubmitted: (_) {
                if (pass.text.isNotEmpty) onSubmit();
              },
            ),
          ),
          const SizedBox(height: 14),
          _Field(
            label: 'Kata sandi',
            child: ShadInput(
              controller: pass,
              enabled: !busy,
              obscureText: !showPass,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              placeholder: Text(firstRun ? 'Minimal 6 karakter' : 'Kata sandi'),
              onSubmitted: (_) => onSubmit(),
              // Tombol mata tidak boleh mencuri fokus dari field.
              trailing: ExcludeFocus(
                child: IconButton(
                  splashRadius: 18,
                  tooltip: showPass ? 'Sembunyikan' : 'Tampilkan',
                  icon: Icon(
                    showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 17,
                    color: t.colorScheme.mutedForeground,
                  ),
                  onPressed: onTogglePass,
                ),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 14),
            ShadAlert.destructive(
              icon: const Icon(Icons.error_outline, size: 16),
              description: Text(error!, style: const TextStyle(fontSize: 12.5, height: 1.45)),
            ),
            if (onRetryCheck != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: busy ? null : onRetryCheck,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, AppThemes.minTap),
                    visualDensity: VisualDensity.standard,
                  ),
                  child: const Text('Coba periksa lagi'),
                ),
              ),
          ],
          const SizedBox(height: 20),
          ShadButton(
            height: AppThemes.minTap,
            onPressed: busy ? null : onSubmit,
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        firstRun ? 'Buat akun & masuk' : 'Masuk',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 16),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            firstRun
                ? 'Kata sandi disimpan dalam bentuk teracak. Tidak ada yang bisa membacanya.'
                : 'Lupa kata sandi? Minta admin klub menyetel kata sandi baru lewat '
                'Lainnya → Akun & akses.',
            textAlign: TextAlign.start,
            style: t.textTheme.small.copyWith(fontSize: 11.5, height: 1.5),
          ),
          if (!firstRun) ...[
            const SizedBox(height: 6),
            // Pendaftaran lewat tautan publik: anggota baru mengisi sendiri
            // namanya, nomor HP, alamat, dan posisi, lalu langsung dapat akun.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy ? null : onRegister,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, AppThemes.minTap),
                  visualDensity: VisualDensity.standard,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: const Text('Belum punya akun? Daftar di sini'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Label kecil huruf besar di atas field.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label.toUpperCase(),
            style: t.textTheme.h4.copyWith(fontSize: 11, letterSpacing: 1),
          ),
        ),
        child,
      ],
    );
  }
}
