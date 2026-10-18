import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'widgets.dart';

class MembersPage extends StatefulWidget {
  const MembersPage({super.key});

  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  late Future<List<Member>> _future;
  final _search = TextEditingController();
  String _query = '';
  bool _activeOnly = true;

  @override
  void initState() {
    super.initState();
    _future = Member.all(activeOnly: _activeOnly);
  }

  Future<void> _reload() async {
    final f = Member.all(activeOnly: _activeOnly);
    setState(() => _future = f);
    await f;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Anggota',
      subtitle: '${_activeOnly ? "Aktif" : "Semua"} • ${Auth.canWrite ? "ketuk untuk edit" : "hanya baca"}',
      actions: [
        if (Auth.canWrite)
          iconAction(context, Icons.person_add_alt_1, () async {
            if (await showMemberForm(context)) _reload();
          }, tooltip: 'Tambah anggota'),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: ShadInput(
                    controller: _search,
                    placeholder: const Text('Cari nama…'),
                    onChanged: (v) => setState(() => _query = v.toLowerCase()),
                    leading: const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Icon(Icons.search, size: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Tooltip(
                  message: _activeOnly ? 'Tampilkan semua' : 'Hanya aktif',
                  child: ShadButton.outline(
                    onPressed: () {
                      setState(() => _activeOnly = !_activeOnly);
                      _reload();
                    },
                    child: Icon(_activeOnly ? Icons.filter_alt : Icons.filter_alt_off, size: 16),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: AsyncView<List<Member>>(
              future: _future,
              onRefresh: _reload,
              builder: (members) {
                final filtered = _query.isEmpty
                    ? members
                    : members.where((m) => m.name.toLowerCase().contains(_query)).toList();
                if (filtered.isEmpty) {
                  return ListView(
                    children: [
                      const SizedBox(height: 80),
                      EmptyState(
                        icon: Icons.groups_outlined,
                        title: _query.isEmpty ? 'Belum ada anggota' : 'Tidak ditemukan',
                        message: _query.isEmpty
                            ? 'Tambahkan pemain pertama klub kamu.'
                            : 'Coba kata kunci lain.',
                        actionLabel: _query.isEmpty && Auth.canWrite ? 'Tambah anggota' : null,
                        onAction: _query.isEmpty && Auth.canWrite
                            ? () async {
                                if (await showMemberForm(context)) _reload();
                              }
                            : null,
                      ),
                    ],
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  children: [
                    for (final m in filtered)
                      RowItem(
                        onTap: Auth.canWrite
                            ? () async {
                                if (await showMemberForm(context, member: m)) _reload();
                              }
                            : null,
                        leading: Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: m.active
                                  ? t.colorScheme.primary.withValues(alpha: 0.5)
                                  : t.colorScheme.border,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${m.jersey ?? '-'}',
                            style: t.textTheme.h2.copyWith(
                              fontSize: 20,
                              color: m.active ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                            ),
                          ),
                        ),
                        title: m.name,
                        subtitle: '${m.position}${m.phone != null ? " • ${m.phone}" : ""}'
                            '${m.active ? '' : ' • nonaktif'}',
                        trailing: Auth.canWrite
                            ? iconAction(context, Icons.delete_outline, () async {
                                if (await confirm(context, 'Hapus anggota?',
                                    '${m.name} beserta riwayat iuran dan catatan pertandingannya akan dihapus permanen.')) {
                                  if (!context.mounted) return;
                                  if (await attempt(context, () => Member.delete(m.id), fail: 'Gagal menghapus')) {
                                    _reload();
                                  }
                                }
                              }, tooltip: 'Hapus')
                            : null,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
