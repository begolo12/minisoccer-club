import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'widgets.dart';

/// Daftar akun pengguna app + role. Hanya admin; server juga menolak
/// permintaan dari role lain (lihat api/sql.js dan api/auth.js).
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late Future<List<AppUser>> _future;

  static const roleLabels = {'admin': 'Admin', 'treasurer': 'Bendahara', 'member': 'Anggota'};

  /// Id akun yang sedang masuk — dipakai untuk menandai baris "kamu".
  ///
  /// Dicari lewat ID, bukan nama: nama bisa diubah admin (dan kalau
  /// comparesbynama, baris "kamu" akan hilang begitu namanya diganti).
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
        title: 'Pengguna',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'Khusus admin',
          message: 'Akun ${Auth.username ?? ''} tidak punya akses ke daftar pengguna.',
        ),
      );
    }
    return PageScaffold(
      title: 'Pengguna',
      subtitle: 'Akun & hak akses',
      actions: [
        iconAction(context, Icons.person_add_alt, () async {
          if (await _form(context)) _reload();
        }, tooltip: 'Tambah pengguna'),
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
                title: 'Belum ada pengguna',
                message: 'Tambah admin atau bendahara klub.',
                actionLabel: 'Tambah pengguna',
                onAction: () async {
                  if (await _form(context)) _reload();
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
                  subtitle: [
                    roleLabels[u.role] ?? u.role,
                    if (!u.active) 'nonaktif',
                  ].join(' • '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ubah username & role: username anggota dibuat dari
                      // nama depan, jadi koreksi nama (atau role yang keliru)
                      // harus bisa tanpa hapus-buat-ulang.
                      iconAction(context, Icons.edit_outlined, () async {
                        if (await _editUser(context, u)) _reload();
                      }, tooltip: 'Ubah akun'),
                      iconAction(context, Icons.key_outlined, () async {
                        if (await _resetPassword(context, u)) _reload();
                      }, tooltip: 'Atur ulang password'),
                      if (u.id != _selfId) ...[
                        const SizedBox(width: 6),
                        // Nonaktifkan/aktifkan: pintu masuk yang bisa dibuka
                        // lagi. Menghapus akun mengunci riwayat lama; ini
                        // cukup untuk anggota yang berhenti datang.
                        iconAction(
                          context,
                          u.active ? Icons.person_off_outlined : Icons.how_to_reg_outlined,
                          () async {
                            if (u.active) {
                              if (!await confirm(
                                context,
                                'Nonaktifkan ${u.username}?',
                                'Akun tidak bisa masuk sampai diaktifkan lagi. '
                                    'Riwayat datanya tetap ada.',
                                confirmLabel: 'Nonaktifkan',
                              )) {
                                return;
                              }
                            }
                            if (!context.mounted) return;
                            if (await attempt(
                              context,
                              () => AppUser.setActive(u.id, !u.active),
                              fail: 'Gagal menyimpan',
                            )) {
                              _reload();
                            }
                          },
                          tooltip: u.active ? 'Nonaktifkan' : 'Aktifkan',
                        ),
                        const SizedBox(width: 6),
                        iconAction(context, Icons.delete_outline, () async {
                          if (await confirm(context, 'Hapus pengguna?', u.username)) {
                            if (!context.mounted) return;
                            if (await attempt(context, () => AppUser.delete(u.id), fail: 'Gagal menghapus')) {
                              _reload();
                            }
                          }
                        }, tooltip: 'Hapus'),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Ubah username dan role satu akun.
  ///
  /// Nama anggota dibuat otomatis dari nama depan ("irvan", "irvan2"), jadi
  /// ada kalanya perlu dikoreksi — dan role yang keliru (mis. anggota dibuat
  /// jadi bendahara) harus bisa diperbaiki tanpa menghapus akun.
  Future<bool> _editUser(BuildContext context, AppUser u) async {
    final name = TextEditingController(text: u.username);
    var role = u.role;
    var saving = false;

    final ok = await showShadDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ShadDialog(
          title: Text('Ubah akun — ${u.username}'),
          description: const Text(
            'Nama pengguna dipakai untuk masuk. Role menentukan bisa menulis '
            'data klub atau tidak.',
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
                      final v = name.text.trim();
                      if (v.isEmpty) {
                        toast(ctx, 'Nama pengguna tidak boleh kosong');
                        return;
                      }
                      setLocal(() => saving = true);
                      try {
                        await AppUser.update(u.id, username: v, role: role);
                        // Kalau yang diubah akun sendiri, sesi ikut
                        // diperbarui — kalau tidak, app masih menampilkan
                        // nama lama sampai ditutup.
                        if (u.id == _selfId) await Auth.renameSelf(v);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) {
                          setLocal(() => saving = false);
                          toast(ctx, writeFailText(e, fail: 'Gagal menyimpan'));
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
                controller: name,
                placeholder: const Text('Nama pengguna'),
                autocorrect: false,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 10),
              ShadSelect<String>(
                placeholder: const Text('Hak akses'),
                initialValue: role,
                options: AppUser.roles
                    .map((r) => ShadOption(value: r, child: Text(roleLabels[r] ?? r)))
                    .toList(),
                selectedOptionBuilder: (c, v) => Text(roleLabels[v] ?? v),
                onChanged: (v) => setLocal(() => role = v ?? role),
              ),
            ],
          ),
        ),
      ),
    );
    name.dispose();
    return ok ?? false;
  }

  Future<bool> _resetPassword(BuildContext context, AppUser u) async {
    final ctrl = TextEditingController();
    var saving = false;
    final ok = await showShadDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ShadDialog(
          title: Text('Password baru — ${u.username}'),
          description: const Text('Minimal 6 karakter. Beri tahu pemiliknya setelah disimpan.'),
          actions: [
            ShadButton.outline(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ShadButton(
              // Guard busy: tanpa ini dua ketukan cepat mengirim dua reset.
              onPressed: saving
                  ? null
                  : () async {
                      if (ctrl.text.length < 6) {
                        toast(ctx, 'Password minimal 6 karakter');
                        return;
                      }
                      setLocal(() => saving = true);
                      try {
                        await AppUser.setPassword(u.id, ctrl.text);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) {
                          setLocal(() => saving = false);
                          toast(ctx, writeFailText(e, fail: 'Gagal'));
                        }
                      }
                    },
              child: Text(saving ? 'Menyimpan…' : 'Simpan'),
            ),
          ],
          child: ShadInput(
            controller: ctrl,
            placeholder: const Text('Password baru'),
            obscureText: true,
          ),
        ),
      ),
    );
    ctrl.dispose();
    return ok ?? false;
  }

  Future<bool> _form(BuildContext context) async {
    final username = TextEditingController();
    final password = TextEditingController();
    var role = 'member';
    var saving = false;

    final ok = await showShadDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ShadDialog(
          title: const Text('Tambah pengguna'),
          description: const Text('Kata sandi dipakai untuk masuk. Bisa diubah kapan saja.'),
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
                        toast(ctx, 'Username wajib diisi');
                        return;
                      }
                      if (password.text.length < 6) {
                        toast(ctx, 'Password minimal 6 karakter');
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
              child: const Text('Simpan'),
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
                placeholder: const Text('Password (min. 6 karakter)'),
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
    return ok ?? false;
  }
}
