import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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
      subtitle: '${_activeOnly ? "Aktif" : "Semua"} • ketuk untuk edit',
      actions: [
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
                        actionLabel: _query.isEmpty ? 'Tambah anggota' : null,
                        onAction: _query.isEmpty
                            ? () async {
                                if (await showMemberForm(context)) _reload();
                              }
                            : null,
                      ),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final m = filtered[i];
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          if (await showMemberForm(context, member: m)) _reload();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: t.colorScheme.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: t.colorScheme.border),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: m.active
                                    ? t.colorScheme.primary.withValues(alpha: 0.16)
                                    : t.colorScheme.muted,
                                child: Text(
                                  m.jersey?.toString() ?? m.name.characters.first.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: m.active ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            m.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        if (!m.active) ...[
                                          const SizedBox(width: 6),
                                          ShadBadge.secondary(child: Text('nonaktif', style: t.textTheme.small)),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${m.position}${m.phone != null ? " • ${m.phone}" : ""}',
                                      style: t.textTheme.small,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Hapus',
                                icon: Icon(Icons.delete_outline, size: 18, color: t.colorScheme.mutedForeground),
                                onPressed: () async {
                                  if (await confirm(context, 'Hapus anggota?', '${m.name} akan dihapus permanen.')) {
                                    await Member.delete(m.id);
                                    _reload();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
