import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/api.dart';

import '../core/registration.dart';
import '../data/auth.dart';
import 'fmt.dart';
import 'theme.dart';

/// Formulir pendaftaran anggota yang bisa dibuka tanpa masuk.
///
/// Bentuknya mengikuti formulir daring yang sudah dikenal orang: satu kolom,
/// label di atas isian, tanda bintang merah untuk yang wajib, lalu satu tombol
/// kirim di bawah. Tidak ada navigasi klub di sini — orang yang membuka tautan
/// ini belum tentu tahu aplikasinya, dan menu hanya akan mengalihkan perhatian
/// dari satu tugas: mengisi data.
///
/// Nama depan dipakai sebagai username, jadi isian pertama menjelaskannya
/// sebelum orang mengetik, bukan setelah akunnya dibuat.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, this.onDone});

  /// Dipanggil saat pendaftar memilih masuk ke aplikasi. Null = halaman
  /// dibuka sebagai layar tersendiri (mis. dari layar masuk).
  final VoidCallback? onDone;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  String? _position;

  bool _saving = false;
  String? _error;

  /// Terisi setelah pendaftaran berhasil; form diganti kartu ringkasan.
  RegistrationResult? _result;

  /// Kesalahan per isian, baru ditampilkan setelah orang mencoba mengirim.
  /// Menyalahkan isian yang belum sempat diisi terasa seperti mesin, bukan
  /// formulir.
  bool _touched = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  String? get _nameErr => nameError(_name.text);
  String? get _phoneErr => phoneError(_phone.text);
  String? get _addressErr => addressError(_address.text);
  String? get _positionErr => positionError(_position);

  bool get _valid =>
      _nameErr == null && _phoneErr == null && _addressErr == null && _positionErr == null;

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _touched = true;
      _error = null;
    });
    if (!_valid) {
      // Fokuskan isian pertama yang bermasalah supaya di HP tidak perlu
      // menggulir mencari mana yang kurang.
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await Auth.registerMember(
        name: cleanName(_name.text),
        phone: normalizePhone(_phone.text) ?? _phone.text.trim(),
        address: cleanName(_address.text),
        position: _position!,
      );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('ApiException: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(compact: MediaQuery.sizeOf(context).width < 520),
                  const SizedBox(height: 18),
                  if (_result != null)
                    _SuccessCard(result: _result!, onDone: widget.onDone)
                  else
                    _buildForm(t),
                  const SizedBox(height: 18),
                  Text(
                    'Data ini dipakai untuk administrasi klub: daftar anggota, '
                    'iuran turnamen, dan pembagian biaya sewa lapangan.',
                    textAlign: TextAlign.center,
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

  Widget _buildForm(ShadThemeData t) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: t.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.colorScheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Label('Nama lengkap', required: true),
          Semantics(
            label: 'Nama lengkap',
            child: ShadInput(
            controller: _name,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            placeholder: const Text('mis. Irvan Nur Cahyo'),
            onChanged: (_) => setState(() {}),
          ),
          ),
          _Hint('Nama depan jadi username kamu: "irvan".'),
          if (_touched && _nameErr != null) _ErrorText(_nameErr!),
          const SizedBox(height: 18),

          _Label('Nomor HP', required: true),
          Semantics(
            label: 'Nomor HP',
            child: ShadInput(
            controller: _phone,
            enabled: !_saving,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            placeholder: const Text('081234567890'),
            onChanged: (_) => setState(() {}),
          ),
          ),
          _Hint('Dipakai juga sebagai password awal. Bisa diganti setelah masuk.'),
          if (_touched && _phoneErr != null) _ErrorText(_phoneErr!),
          const SizedBox(height: 18),

          _Label('Alamat', required: true),
          Semantics(
            label: 'Alamat',
            child: ShadInput(
            controller: _address,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            maxLines: 3,
            placeholder: const Text('Jalan, nomor rumah, kelurahan, kota'),
            onChanged: (_) => setState(() {}),
          ),
          ),
          if (_touched && _addressErr != null) _ErrorText(_addressErr!),
          const SizedBox(height: 18),

          _Label('Posisi bermain', required: true),
          const SizedBox(height: 2),
          // Radio, bukan dropdown: di HP semua pilihan langsung terlihat dan
          // cukup satu ketukan. Dropdown menyembunyikan pilihan di balik satu
          // ketukan lagi, dan formulir ini diisi sambil berdiri.
          Material(
            type: MaterialType.transparency,
            // RadioGroup mengelola nilai terpilih untuk semua Radio di
            // dalamnya; sejak Flutter 3.32 `groupValue` per-Radio sudah
            // deprecated.
            child: RadioGroup<String>(
              groupValue: _position,
              onChanged: (v) {
                if (!_saving) setState(() => _position = v);
              },
              child: Column(
                children: [
                  for (final p in kPositions)
                    InkWell(
                      onTap: _saving ? null : () => setState(() => _position = p),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Radio<String>(
                              value: p,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            const SizedBox(width: 8),
                            Text(p, style: t.textTheme.large.copyWith(fontSize: 14)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_touched && _positionErr != null) _ErrorText(_positionErr!),

          if (_error != null) ...[
            const SizedBox(height: 16),
            ShadAlert.destructive(
              icon: const Icon(Icons.error_outline, size: 16),
              description: Text(_error!, style: const TextStyle(fontSize: 12.5, height: 1.45)),
            ),
          ],

          const SizedBox(height: 22),
          ShadButton(
            height: 44,
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kirim pendaftaran', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          Text(
            'Semua isian wajib diisi.',
            style: t.textTheme.small.copyWith(fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: t.colorScheme.primary, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.sports_soccer, size: 16, color: t.colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Text(
              'MINISOCCER CLUB',
              style: TextStyle(
                fontFamily: AppThemes.display,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.2,
                color: t.colorScheme.mutedForeground,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          'Pendaftaran anggota',
          style: t.textTheme.h1Large.copyWith(fontSize: compact ? 34 : 42, height: 1.05),
        ),
        const SizedBox(height: 8),
        Text(
          'Isi data di bawah untuk mendaftar sebagai anggota klub. '
          'Akun masuk dibuat otomatis dari nama depan kamu.',
          style: t.textTheme.muted,
        ),
      ],
    );
  }
}

/// Ringkasan setelah berhasil. Username dan password awal hanya muncul di
/// sini, jadi keduanya harus bisa dibaca ulang dengan tenang (bukan toast yang
/// hilang sendiri).
class _SuccessCard extends StatefulWidget {
  const _SuccessCard({required this.result, this.onDone});

  final RegistrationResult result;
  final VoidCallback? onDone;

  @override
  State<_SuccessCard> createState() => _SuccessCardState();
}

class _SuccessCardState extends State<_SuccessCard> {
  bool _busy = false;

  /// Masuk langsung memakai kredensial yang barusan dibuat.
  ///
  /// Tanpa ini pendaftar harus menyalin username dan nomor HP ke layar masuk
  /// yang kosong — padahal keduanya sudah ada di tangan dan baru saja
  /// ditampilkan. Satu ketukan, langsung masuk.
  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await Auth.login(widget.result.username, widget.result.password);
      widget.onDone?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, 'Gagal masuk otomatis: ${errText(e)}. Coba masuk manual.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final onDone = widget.onDone;
    final t = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: t.colorScheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.colorScheme.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 20, color: t.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Pendaftaran terkirim', style: t.textTheme.h3.copyWith(fontSize: 20)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Terima kasih, ${result.name}. Akun kamu sudah dibuat. '
            'Simpan dua baris di bawah untuk masuk ke aplikasi.',
            style: t.textTheme.small,
          ),
          const SizedBox(height: 16),
          _CredentialRow(label: 'Username', value: result.username),
          const SizedBox(height: 8),
          _CredentialRow(label: 'Password awal', value: result.password),
          const SizedBox(height: 14),
          Text(
            'Segera ganti password setelah masuk, lewat menu Pengaturan → '
            'Ganti password. Nomor HP mudah diketahui orang lain.',
            style: t.textTheme.small,
          ),
          if (onDone != null) ...[
            const SizedBox(height: 20),
            ShadButton(
              height: 44,
              onPressed: _busy ? null : _signIn,
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Masuk sekarang', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : onDone,
              child: const Text('Lihat dulu tanpa masuk'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CredentialRow extends StatelessWidget {
  const _CredentialRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.colorScheme.muted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(label, style: t.textTheme.small),
          ),
          Expanded(
            child: SelectableText(
              value,
              // Tanpa ini isinya tidak terbaca pembaca layar: SelectableText
              // tidak mengekspos teksnya ke pohon aksesibilitas seperti Text.
              // Padahal justru inilah dua baris yang harus dibaca pendaftar.
              semanticsLabel: '$label: $value',
              style: TextStyle(
                fontFamily: AppThemes.display,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: t.colorScheme.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Label isian. Tanda bintang merah menandai wajib isi, seperti pada formulir
/// daring pada umumnya.
class _Label extends StatelessWidget {
  const _Label(this.text, {this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      // Text.rich (bukan RichText) supaya labelnya ikut masuk ke pohon
      // aksesibilitas: pembaca layar dan uji otomatis memakai jalur yang sama,
      // dan RichText biasa tidak mengekspos teksnya.
      child: Text.rich(
        TextSpan(
          text: text,
          style: t.textTheme.large.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
          children: [
            if (required)
              TextSpan(
                text: ' *',
                style: TextStyle(color: AppThemes.bad(context), fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(text, style: t.textTheme.small.copyWith(fontSize: 11.5, height: 1.4)),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        text,
        style: t.textTheme.small.copyWith(fontSize: 11.5, color: AppThemes.bad(context)),
      ),
    );
  }
}


/// Alamat formulir pendaftaran untuk dibagikan.
///
/// Di web dipakai origin halaman yang sedang dibuka (termasuk prefiks portal,
/// mis. `/minisoccer`), supaya tautannya tidak menunjuk ke domain lain. Di APK
/// tidak ada halaman, jadi dipakai alamat server API — di sanalah versi web
/// dipasang.
String registrationLink() {
  if (kIsWeb) {
    final base = Uri.base;
    final segs = base.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isNotEmpty && segs.last == 'daftar') segs.removeLast();
    final prefix = segs.isEmpty ? '' : '/${segs.join('/')}';
    return '${base.origin}$prefix/daftar';
  }
  return kApiBase.startsWith('http') ? '$kApiBase/daftar' : '';
}

/// Dialog berisi tautan pendaftaran + tombol salin.
///
/// Ditaruh di sini (bukan di Pengaturan saja) supaya bisa dibuka dari halaman
/// Anggota, tempat admin biasanya sedang menambah orang.
Future<void> showRegistrationLinkDialog(BuildContext context) async {
  final link = registrationLink();
  final t = ShadTheme.of(context);
  await showShadDialog<void>(
    context: context,
    builder: (ctx) => ShadDialog(
      title: const Text('Tautan pendaftaran'),
      description: const Text(
        'Bagikan tautan ini ke calon anggota. Mereka mengisi nama, nomor HP, '
        'alamat, dan posisi sendiri. Nama depan menjadi username, dan akunnya '
        'langsung dibuat.',
      ),
      actions: [
        ShadButton.outline(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Tutup'),
        ),
        ShadButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: link));
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) toast(context, 'Tautan disalin');
          },
          child: const Text('Salin tautan'),
        ),
      ],
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: t.colorScheme.muted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SelectableText(
          link,
          style: t.textTheme.small.copyWith(fontSize: 13, height: 1.5),
        ),
      ),
    ),
  );
}
