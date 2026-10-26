import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'export.dart' show copyText;
import 'fmt.dart';
import 'widgets.dart';

/// Panel kredensial: daftar akun yang bisa masuk ke aplikasi, siapa pemiliknya,
/// dan semua yang boleh diubah admin.
///
/// Soal "melihat password": password TIDAK disimpan dalam bentuk terbaca.
/// Server menyimpannya sebagai bcrypt satu arah (`crypt` + `gen_salt('bf')`),
/// jadi tidak ada jalan untuk menampilkannya kembali — termasuk bagi admin,
/// termasuk lewat database. Yang bisa dilakukan admin (dan cukup untuk semua
/// kebutuhan nyata) ada di sini: melihat id & username tiap akun, tahu akun
/// mana yang belum punya password, dan **menyetel password baru** yang
/// ditampilkan sekali dengan tombol salin untuk dikirim ke pemiliknya.
///
/// Kenapa bcrypt dan bukan yang bisa dibaca: kalau admin bisa membaca password
/// semua orang, satu kebocoran database atau satu layar yang difoto membuka
/// SEMUA akun — termasuk akun admin lain. Menyetel ulang memberi hasil yang
/// sama (pemilik bisa masuk lagi) tanpa menyimpan rahasia yang bisa dicuri.
///
/// Hanya admin. Server menolak role lain di `/api/auth` (action `list`,
/// `create`, `reset`, `update`, `setActive`, `delete`), jadi halaman ini bukan
/// satu-satunya pengaman.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late Future<List<AppUser>> _future;

  static const roleLabels = {
    'admin': 'Admin',
    'treasurer': 'Bendahara',
    'member': 'Anggota',
  };

  /// Id akun yang sedang masuk — dipakai untuk menandai baris "kamu".
  ///
  /// Dicari lewat ID, bukan nama: nama bisa diubah admin, dan kalau
  /// dibandingkan dengan nama, baris "kamu" hilang begitu namanya diganti.
  int? get _selfId => Auth.userId;

  @override
  void initState() {
    super.initState();
    _future = AppUser.all();
  }

  Future<void> _reload() async {
    final f = AppUser.all();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    if (!Auth.isAdmin) {
      return PageScaffold(
        title: 'Akun & akses',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'Khusus admin',
          message: 'Akun ${Auth.username ?? ''} tidak punya akses ke daftar akun.',
        ),
      );
    }
    return PageScaffold(
      title: 'Akun & akses',
      subtitle: 'Hanya admin — id, password, dan hak akses',
      actions: [
        iconAction(context, Icons.person_add_alt, () async {
          if (await _create(context)) _reload();
        }, tooltip: 'Tambah akun'),
      ],
      child: AsyncView<List<AppUser>>(
        future: _future,
        onRefresh: _reload,
        builder: (users) {
          if (users.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              EmptyState(
                icon: Icons.people_outline,
                title: 'Belum ada akun',
                message: 'Tambah admin atau bendahara klub.',
                actionLabel: 'Tambah akun',
                onAction: () async {
                  if (await _create(context)) _reload();
                },
              ),
            ]);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            children: [
              for (final u in users)
                RowItem(
                  leading: Icon(
                    u.role == 'admin' ? Icons.shield_outlined : Icons.person_outline,
                    size: 17,
                    color: u.active ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                  ),
                  title: u.id == _selfId ? '${u.username} (kamu)' : u.username,
                  // Satu baris menjawab "akun siapa ini": id (untuk menyebut
                  // akun saat melapor), role, anggota yang tertaut, dan
                  // apakah passwordnya sudah diset.
                  subtitle: [
                    '#${u.id}',
                    roleLabels[u.role] ?? u.role,
                    if (u.memberId != null) 'anggota #${u.memberId}',
                    if (!u.active) 'nonaktif',
                    if (!u.hasPassword) 'password belum diset',
                  ].join(' • '),
                  // Satu pintu: semua ubahan ada di panel akun. Lima tombol
                  // ikon berjajar tidak muat di layar 320px dan paling
                  // sering salah ketuk.
                  trailing: Icon(Icons.chevron_right,
                      size: 20, color: t.colorScheme.mutedForeground),
                  onTap: () async {
                    if (await _manage(context, u)) _reload();
                  },
                ),
              const SizedBox(height: 14),
              Text(
                'Password disimpan terenkripsi satu arah (bcrypt) dan tidak bisa '
                'dibaca lagi — termasuk oleh admin. Untuk memberi akses, setel '
                'password baru lalu kirimkan ke pemiliknya.',
                style: t.textTheme.small,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Panel satu akun: identitas, tautan anggota, role, status, password.
  Future<bool> _manage(BuildContext context, AppUser u) async {
    var changed = false;
    final ok = await showShadDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _AccountPanel(
        user: u,
        isSelf: u.id == _selfId,
        onChanged: () => changed = true,
      ),
    );
    return (ok ?? false) || changed;
  }

  /// Tambah akun baru (username + password awal + role).
  Future<bool> _create(BuildContext context) async {
    final username = TextEditingController();
    final password = TextEditingController(text: suggestPassword());
    var role = 'member';
    var saving = false;

    final ok = await showShadDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ShadDialog(
          title: const Text('Tambah akun'),
          description: const Text(
            'Password awal terisi otomatis dan bisa diganti. Salin dulu sebelum '
            'menyimpan — setelah tersimpan tidak bisa dibaca lagi.',
          ),
          actions: [
            ShadButton.outline(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ShadButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (username.text.trim().isEmpty) {
                        toast(ctx, 'Nama pengguna wajib diisi');
                        return;
                      }
                      if (password.text.length < 8) {
                        toast(ctx, 'Password minimal 8 karakter');
                        return;
                      }
                      setLocal(() => saving = true);
                      try {
                        await AppUser.insert(username.text, role, password: password.text);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) {
                          setLocal(() => saving = false);
                          toast(ctx, writeFailText(e, fail: 'Gagal simpan'));
                        }
                      }
                    },
              child: Text(saving ? 'Menyimpan…' : 'Simpan'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadInput(
                controller: username,
                placeholder: const Text('Nama pengguna'),
                autocorrect: false,
              ),
              const SizedBox(height: 10),
              ShadInput(
                controller: password,
                placeholder: const Text('Password (min. 8 karakter)'),
                obscureText: true,
              ),
              const SizedBox(height: 10),
              ShadSelect<String>(
                placeholder: const Text('Hak akses'),
                initialValue: role,
                options: AppUser.roles
                    .map((r) => ShadOption(value: r, child: Text(roleLabels[r] ?? r)))
                    .toList(),
                selectedOptionBuilder: (c, v) => Text(roleLabels[v] ?? v),
                onChanged: (v) => setLocal(() => role = v ?? 'member'),
              ),
            ],
          ),
        ),
      ),
    );
    username.dispose();
    password.dispose();
    return ok ?? false;
  }
}

/// Password awal yang mudah dibacakan lewat telepon/WhatsApp.
///
/// Tanpa karakter yang mirip (0/O, 1/l/I) karena password ini akan disalin
/// manual oleh pemiliknya, dan tanpa simbol supaya tidak rusak saat dikirim
/// lewat pesan. 12 karakter dari 30 huruf/angka ≈ 59 bit — jauh di atas
/// cukup untuk akun klub, dan tetap aman kalau layarnya sempat difoto.
String suggestPassword() {
  const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(12, (_) => alphabet[r.nextInt(alphabet.length)]).join();
}

/// Isi panel akun: semua yang boleh diubah admin dalam satu tempat.
class _AccountPanel extends StatefulWidget {
  const _AccountPanel({
    required this.user,
    required this.isSelf,
    required this.onChanged,
  });

  final AppUser user;
  final bool isSelf;
  final VoidCallback onChanged;

  @override
  State<_AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<_AccountPanel> {
  late final TextEditingController _name;
  late String _role;
  late int? _memberId;
  late bool _active;

  /// Password yang baru disetel — hanya ada di layar ini, tidak pernah
  /// dikirim balik oleh server.
  String? _freshPassword;

  bool _saving = false;
  late Future<List<Member>> _members;

  /// Kata kunci pencarian anggota di pemilih tautan.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.user.username);
    _role = widget.user.role;
    _memberId = widget.user.memberId;
    _active = widget.user.active;
    // Daftar anggota untuk pemilih tautan. Dimuat sekali saat panel dibuka;
    // kalau gagal (offline), pemilihnya kosong tapi sisa panel tetap jalan.
    _members = Member.all().catchError((_) => <Member>[]);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, 'Nama pengguna tidak boleh kosong');
      return;
    }
    setState(() => _saving = true);
    try {
      await AppUser.update(
        widget.user.id,
        username: name,
        role: _role,
        memberId: _memberId,
        touchMember: _memberId != widget.user.memberId,
      );
      if (_active != widget.user.active) {
        await AppUser.setActive(widget.user.id, _active);
      }
      // Akun sendiri: sesi ikut diperbarui supaya nama di shell tidak
      // tertinggal sampai aplikasi ditutup.
      if (widget.isSelf && name != widget.user.username) {
        await Auth.renameSelf(name);
      }
      widget.onChanged();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        toast(context, writeFailText(e, fail: 'Gagal menyimpan'));
      }
    }
  }

  /// Setel password baru, tampilkan SEKALI, sediakan tombol salin.
  ///
  /// Server hanya menerima password baru; yang lama tidak bisa diminta
  /// kembali karena disimpan sebagai hash. Jadi alurnya: buat, tampilkan,
  /// salin, kirim ke pemilik akun.
  Future<void> _setPassword() async {
    final next = suggestPassword();
    if (!await confirm(
      context,
      'Setel password baru?',
      'Password lama ${widget.user.username} langsung tidak berlaku. '
          'Password baru akan ditampilkan sekali untuk disalin.',
      confirmLabel: 'Setel',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await attempt(
      context,
      () => AppUser.setPassword(widget.user.id, next),
      fail: 'Gagal menyetel password',
    );
    if (!ok || !mounted) return;
    setState(() => _freshPassword = next);
    widget.onChanged();
  }

  Future<void> _delete() async {
    if (!await confirm(
      context,
      'Hapus akun ${widget.user.username}?',
      'Akun tidak bisa masuk lagi. Data klub yang pernah dicatatnya tetap ada. '
          'Kalau hanya ingin menutup akses sementara, nonaktifkan saja.',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await attempt(
      context,
      () => AppUser.delete(widget.user.id),
      fail: 'Gagal menghapus',
    );
    if (!ok || !mounted) return;
    widget.onChanged();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final u = widget.user;
    return ShadDialog(
      title: Text('Akun ${u.username}'),
      description: Text(
        'ID #${u.id}${u.createdAt == null ? '' : ' • dibuat ${fmtDate(u.createdAt!)}'}',
      ),
      actions: [
        ShadButton.outline(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Tutup'),
        ),
        ShadButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Menyimpan…' : 'Simpan'),
        ),
      ],
      // Panel ini lebih tinggi dari dialog biasa: pengguna HP kecil perlu
      // menggulir, bukan memaksa semuanya muat.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadInput(
              controller: _name,
              placeholder: const Text('Nama pengguna'),
              autocorrect: false,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            ShadSelect<String>(
              placeholder: const Text('Hak akses'),
              initialValue: _role,
              options: AppUser.roles
                  .map((r) => ShadOption(value: r, child: Text(_UsersPageState.roleLabels[r] ?? r)))
                  .toList(),
              selectedOptionBuilder: (c, v) => Text(_UsersPageState.roleLabels[v] ?? v),
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            const SizedBox(height: 10),
            // Tautan ke baris anggota. Menentukan "Akun saya" (iuran sendiri)
            // dan siapa yang tercatat saat absensi — jadi admin harus bisa
            // memperbaikinya, bukan hanya melihatnya.
            FutureBuilder<List<Member>>(
              future: _members,
              builder: (c, snap) {
                final list = snap.data ?? const <Member>[];
                if (list.isEmpty) {
                  return _InfoLine(
                    label: 'Anggota tertaut',
                    value: _memberId == null ? 'Tidak tertaut' : '#$_memberId',
                  );
                }
                final valid = list.any((m) => m.id == _memberId) ? _memberId : null;
                // `T` sengaja `int`, bukan `int?`: shadcn memanggil
                // `initialValue!` saat membangun opsi, jadi `ShadOption` dengan
                // nilai null melempar "Null check operator used on a null
                // value" dan daftar pilihan tampil sebagai kotak abu-abu
                // kosong. "Tidak tertaut" diwakili 0.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Varian pencarian + tinggi terbatas: klub bisa punya
                    // puluhan anggota, dan daftar setinggi layar di dalam
                    // dialog membuat pilihannya tidak terjangkau. Dengan
                    // pencarian, menautkan akun cukup mengetik namanya.
                    ShadSelect<int>.withSearch(
                      placeholder: const Text('Anggota tertaut'),
                      initialValue: valid ?? 0,
                      maxHeight: 260,
                      searchPlaceholder: const Text('Cari anggota'),
                      onSearchChanged: (q) => setState(() => _query = q),
                      options: [
                        const ShadOption(value: 0, child: Text('Tidak tertaut')),
                        for (final m in list)
                          if (_query.isEmpty ||
                              m.name.toLowerCase().contains(_query.toLowerCase()) ||
                              '${m.id}' == _query)
                            ShadOption(value: m.id, child: Text('${m.name} (#${m.id})')),
                      ],
                      selectedOptionBuilder: (c, v) {
                        final m = list.where((m) => m.id == v).firstOrNull;
                        return Text(m == null ? 'Tidak tertaut' : '${m.name} (#${m.id})');
                      },
                      onChanged: (v) =>
                          setState(() => _memberId = (v == null || v == 0) ? null : v),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            // Status akun. Akun sendiri tidak bisa dinonaktifkan (server juga
            // menolaknya) supaya admin tidak mengunci dirinya sendiri.
            //
            // Memakai `ShadSwitch`, bukan `SwitchListTile`: ListTile adalah
            // widget Material yang membawa `Material` sendiri, dan di dalam
            // dialog shadcn ia merenggang memenuhi sisa tinggi — panel ini
            // dulu menampilkan kotak abu-abu raksasa dengan tombol password
            // terdorong ke luar layar.
            ShadSwitch(
              value: _active,
              label: Text(widget.isSelf ? 'Bisa masuk (akun sendiri)' : 'Bisa masuk'),
              onChanged: widget.isSelf ? null : (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 4),
            Text(
              widget.isSelf
                  ? 'Akun yang sedang dipakai tidak bisa dinonaktifkan.'
                  : 'Nonaktif = pintu masuk ditutup, riwayat tetap ada.',
              style: t.textTheme.small,
            ),
            const Divider(height: 20),
            Text('Password', style: t.textTheme.large),
            const SizedBox(height: 4),
            Text(
              u.hasPassword
                  ? 'Tersimpan sebagai hash satu arah — isinya tidak bisa '
                      'ditampilkan, hanya bisa diganti.'
                  : 'Akun ini belum punya password. Setel satu supaya bisa masuk.',
              style: t.textTheme.small,
            ),
            const SizedBox(height: 8),
            if (_freshPassword != null) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                decoration: BoxDecoration(
                  color: t.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: t.colorScheme.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _freshPassword!,
                        style: t.textTheme.large.copyWith(letterSpacing: 1.5),
                      ),
                    ),
                    iconAction(
                      context,
                      Icons.copy_all_outlined,
                      () => copyText(
                        context,
                        '${u.username} / ${_freshPassword!}',
                        message: 'Username & password disalin',
                      ),
                      tooltip: 'Salin',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Ditampilkan sekali. Salin sekarang lalu kirim ke pemilik akun.',
                style: t.textTheme.small,
              ),
              const SizedBox(height: 8),
            ],
            ShadButton.outline(
              onPressed: _saving ? null : _setPassword,
              child: const Text('Setel password baru'),
            ),
            if (!widget.isSelf) ...[
              const SizedBox(height: 18),
              ShadButton.destructive(
                onPressed: _saving ? null : _delete,
                child: const Text('Hapus akun'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Baris "label — nilai" sederhana untuk fakta yang tidak bisa diubah.
class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: t.textTheme.small)),
        Text(value, style: t.textTheme.small),
      ],
    );
  }
}
