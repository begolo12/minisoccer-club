import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

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

  @override
  void initState() {
    super.initState();
    _future = Announcement.all();
  }

  Future<void> _reload() async {
    final f = Announcement.all();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Pengumuman',
      actions: [
        iconAction(context, Icons.add, () async {
          if (await showAnnouncementForm(context)) _reload();
        }, tooltip: 'Buat pengumuman'),
      ],
      child: AsyncView<List<Announcement>>(
        future: _future,
        onRefresh: _reload,
        builder: (items) {
          if (items.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              EmptyState(
                icon: Icons.campaign_outlined,
                title: 'Belum ada pengumuman',
                message: 'Bagikan info latihan, iuran, atau acara klub.',
                actionLabel: 'Buat pengumuman',
                onAction: () async {
                  if (await showAnnouncementForm(context)) _reload();
                },
              ),
            ]);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              for (final a in items)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: t.colorScheme.border.withValues(alpha: 0.7)),
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
                                Text(fmtDate(a.createdAt), style: t.textTheme.small),
                              ],
                            ),
                          ),
                          iconAction(context, Icons.delete_outline, () async {
                            if (await confirm(context, 'Hapus pengumuman?', a.title)) {
                              await Announcement.delete(a.id);
                              _reload();
                            }
                          }, tooltip: 'Hapus'),
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
