import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'member_dues.dart';
import 'register.dart';
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

  /// Satu baris anggota. Dipisah dari `build` supaya bisa dipanggil
  /// `ListView.builder` per baris.
  Widget _memberRow(Member m, ShadThemeData t) {
    return RowItem(
      // Ketuk baris = lihat, ikon = ubah. Aturan ini sama untuk semua role;
      // sebelumnya baris membuka form edit untuk admin tetapi riwayat iuran
      // untuk anggota, jadi satu ketukan berarti dua hal berbeda.
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MemberDuesPage(member: m),
        ));
      },
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (Auth.canWrite) ...[
            iconAction(context, Icons.edit_outlined, () async {
              if (await showMemberForm(context, member: m)) _reload();
            }, tooltip: 'Ubah anggota'),
            const SizedBox(width: 6),
            iconAction(context, Icons.delete_outline, () async {
              // Anggota yang pernah membayar iuran TIDAK dihapus: baris
              // iurannya memakai ON DELETE CASCADE, jadi menghapusnya ikut
              // membuang catatan uang dan mengubah saldo kas bulan lalu.
              // Yang benar untuk orang yang berhenti bermain: nonaktifkan.
              final hasMoney = await Member.hasFinance(m.id);
              if (!mounted) return;
              if (hasMoney) {
                if (await confirm(
                  context,
                  'Tidak bisa dihapus',
                  '${m.name} sudah punya catatan iuran atau patungan. '
                      'Menghapusnya akan menghapus uang klub yang pernah masuk. '
                      'Nonaktifkan saja — namanya tetap muncul di riwayat, '
                      'tapi tidak ikut ditagih lagi.',
                  confirmLabel: 'Nonaktifkan',
                )) {
                  if (!mounted) return;
                  if (await attempt(context, () => m.update(
                        name: m.name,
                        phone: m.phone,
                        address: m.address,
                        position: m.position,
                        jersey: m.jersey,
                        active: false,
                      ), fail: 'Gagal menonaktifkan')) {
                    _reload();
                  }
                }
                return;
              }
              if (await confirm(context, 'Hapus anggota?',
                  '${m.name} belum punya catatan iuran, jadi aman dihapus. '
                  'Catatan golnya tetap ada tanpa nama.')) {
                if (!mounted) return;
                if (await attempt(context, () => Member.delete(m.id), fail: 'Gagal menghapus')) {
                  _reload();
                }
              }
            }, tooltip: 'Hapus'),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Anggota',
      // Subjudul harus jujur: baris membuka riwayat iuran, ikon pensil yang
      // membuka form edit. Dulu tertulis "ketuk untuk edit" padahal ketukan
      // pada baris membuka halaman lain.
      // Riwayat iuran hanya untuk yang sudah masuk, jadi jangan menjanjikan
      // ketukan itu kepada tamu.
      subtitle: Auth.signedIn
          ? '${_activeOnly ? "Aktif" : "Semua"} • ketuk untuk riwayat iuran'
          : '${_activeOnly ? "Aktif" : "Semua"} • daftar anggota klub',
      actions: [
        // Tautan pendaftaran dibuka dari sini karena di halaman inilah admin
        // biasanya sedang menambah orang — tidak perlu masuk Pengaturan.
        if (Auth.isAdmin)
          iconAction(context, Icons.link, () => showRegistrationLinkDialog(context),
              tooltip: 'Tautan pendaftaran'),
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
                    // `trim` penting: spasi di awal/akhir (sering ikut terketik
                    // atau ter-tempel) membuat pencarian gagal padahal datanya
                    // ada, dan pengguna melihat "Tidak ditemukan".
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
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
                            ? 'Tambahkan anggota pertama klub kamu.'
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
                // `ListView.builder`, bukan `children: [...]`: daftar anggota
                // klub bisa puluhan baris, dan membangun semuanya sekaligus
                // membuat layar pertama terasa berat di HP lama. Dengan builder
                // hanya baris yang terlihat yang dibuat.
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _memberRow(filtered[i], t),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
