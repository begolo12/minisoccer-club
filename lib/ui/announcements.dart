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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengumuman'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              if (await showAnnouncementForm(context)) _reload();
            },
          ),
        ],
      ),
      body: AsyncView<List<Announcement>>(
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
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final a = items[i];
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.colorScheme.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.colorScheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 16, color: t.colorScheme.mutedForeground),
                          onPressed: () async {
                            if (await confirm(context, 'Hapus pengumuman?', a.title)) {
                              await Announcement.delete(a.id);
                              _reload();
                            }
                          },
                        ),
                      ],
                    ),
                    Text(fmtDate(a.createdAt), style: t.textTheme.small),
                    const SizedBox(height: 8),
                    Text(a.body),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
