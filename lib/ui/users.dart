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
                  title: u.username,
                  subtitle: [
                    switch (u.role) {
                      'admin' => 'Admin',
                      'treasurer' => 'Bendahara',
                      _ => 'Anggota',
                    },
                    if (!u.active) 'nonaktif',
                  ].join(' • '),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      iconAction(context, Icons.key_outlined, () async {
                        if (await _resetPassword(context, u)) _reload();
                      }, tooltip: 'Atur ulang password'),
                      const SizedBox(width: 6),
                      iconAction(context, Icons.delete_outline, () async {
                        if (await confirm(context, 'Hapus pengguna?', u.username)) {
                          await AppUser.delete(u.id);
                          _reload();
                        }
                      }, tooltip: 'Hapus'),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _resetPassword(BuildContext context, AppUser u) async {
    final ctrl = TextEditingController();
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: Text('Password baru — ${u.username}'),
        description: const Text('Minimal 6 karakter. Beri tahu pemiliknya setelah disimpan.'),
        actions: [
          ShadButton.outline(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ShadButton(
            onPressed: () async {
              if (ctrl.text.length < 6) {
                toast(ctx, 'Password minimal 6 karakter');
                return;
              }
              await AppUser.setPassword(u.id, ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Simpan'),
          ),
        ],
        child: ShadInput(
          controller: ctrl,
          placeholder: const Text('Password baru'),
          obscureText: true,
        ),
      ),
    );
    return ok ?? false;
  }

  Future<bool> _form(BuildContext context) async {
    final username = TextEditingController();
    final password = TextEditingController();
    var role = 'member';
    var saving = false;

    final ok = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ShadDialog(
          title: const Text('Tambah pengguna'),
          description: const Text('Password dipakai untuk login. Bisa diubah kapan saja.'),
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
                          toast(ctx, 'Gagal simpan: $e');
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
                placeholder: const Text('Username'),
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
                placeholder: const Text('Role'),
                initialValue: role,
                options: AppUser.roles
                    .map((r) => ShadOption(value: r, child: Text(r)))
                    .toList(),
                selectedOptionBuilder: (c, v) => Text(v),
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
