import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'widgets.dart';

/// Daftar akun pengguna app + role. Belum ada login; ini direktori akses.
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengguna'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            onPressed: () async {
              if (await _form(context)) _reload();
            },
          ),
        ],
      ),
      body: AsyncView<List<AppUser>>(
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
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            itemCount: users.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final u = users[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: t.colorScheme.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.colorScheme.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      u.role == 'admin' ? Icons.shield_outlined : Icons.person_outline,
                      size: 18,
                      color: t.colorScheme.mutedForeground,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(u.username, style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    ShadBadge.secondary(child: Text(u.role, style: t.textTheme.small)),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 16, color: t.colorScheme.mutedForeground),
                      onPressed: () async {
                        if (await confirm(context, 'Hapus pengguna?', u.username)) {
                          await AppUser.delete(u.id);
                          _reload();
                        }
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<bool> _form(BuildContext context) async {
    final username = TextEditingController();
    var role = 'member';
    var saving = false;

    final ok = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ShadDialog(
          title: const Text('Tambah pengguna'),
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
                      setLocal(() => saving = true);
                      try {
                        await AppUser.insert(username.text, role);
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
