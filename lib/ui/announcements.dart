import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'widgets.dart';

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  late Future<List<Announcement>> _future;

  /// Id pengumuman terbesar yang sudah dilihat saat halaman dibuka — yang
  /// lebih baru daripadanya mendapat badge "baru". Null = akun ini belum
  /// pernah membuka halaman ini di perangkat ini; badge tidak dinyalakan
  /// sama sekali, karena melabeli seluruh daftar sebagai "baru" hanya
  /// menjadi derau, bukan informasi.
  int? _seenId;

  @override
  void initState() {
    super.initState();
    // HARUS sinkron: build pertama jalan sebelum await pertama selesai, dan
    // `late _future` yang belum terisi melempar LateInitializationError di
    // frame itu (error konsol di produksi, halaman berkedip merah).
    _future = _fetch();
  }

  Future<List<Announcement>> _fetch() async {
    // Penanda dibaca SEBELUM daftar dimuat: `mark` di bawah memperbaruinya,
    // dan kalau urutannya terbalik setiap pengumuman sudah terhitung
    // "dibaca" sebelum sempat ditampilkan — badge tidak pernah muncul.
    final seen = await AnnouncementSeen.lastId();
    if (mounted) setState(() => _seenId = seen);
    final items = await Announcement.all();
    unawaited(AnnouncementSeen.mark(items));
    return items;
  }

  Future<void> _reload() async {
    final f = _fetch();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Pengumuman',
      subtitle: 'Info klub untuk anggota',
      actions: [
        if (Auth.canWrite)
          iconAction(context, Icons.add, () async {
            if (await showAnnouncementForm(context)) _reload();
          }, tooltip: 'Buat pengumuman'),
      ],
      child: AsyncView<List<Announcement>>(
        future: _future,
        onRefresh: _reload,
        builder: (items) {
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.campaign_outlined,
                  title: 'Belum ada pengumuman',
                  message: 'Bagikan info latihan, iuran, atau acara klub.',
                  actionLabel: Auth.canWrite ? 'Buat pengumuman' : null,
                  onAction: Auth.canWrite
                      ? () async {
                          if (await showAnnouncementForm(context)) _reload();
                        }
                      : null,
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              for (final a in items)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: t.colorScheme.border),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.title, style: t.textTheme.large),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    if (a.pinned) ...[
                                      Semantics(
                                        label: 'Disematkan',
                                        child: Icon(
                                          Icons.push_pin,
                                          size: 12,
                                          color: t.colorScheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(fmtDate(a.createdAt),
                                        style: t.textTheme.small),
                                    if (_seenId != null && a.id > _seenId!) ...[
                                      const SizedBox(width: 8),
                                      Pill('Baru', color: t.colorScheme.primary),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (Auth.canWrite) ...[
                            iconAction(context, Icons.edit_outlined, () async {
                              if (await showAnnouncementForm(context, announcement: a)) {
                                _reload();
                              }
                            }, tooltip: 'Ubah'),
                            const SizedBox(width: 4),
                            iconAction(context, Icons.delete_outline, () async {
                              if (await confirm(context, 'Hapus pengumuman?', a.title)) {
                                if (!context.mounted) return;
                                if (await attempt(context, () => Announcement.delete(a.id), fail: 'Gagal menghapus')) {
                                  _reload();
                                }
                              }
                            }, tooltip: 'Hapus'),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(a.body, style: t.textTheme.muted),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
