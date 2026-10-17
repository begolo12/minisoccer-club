import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'widgets.dart';

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key});

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  late Future<List<Booking>> _future;

  @override
  void initState() {
    super.initState();
    _future = Booking.all();
  }

  Future<void> _reload() async {
    final f = Booking.all();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking lapangan'),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              if (await showBookingForm(context)) _reload();
            },
          ),
        ],
      ),
      body: AsyncView<List<Booking>>(
        future: _future,
        onRefresh: _reload,
        builder: (items) {
          if (items.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              EmptyState(
                icon: Icons.stadium_outlined,
                title: 'Belum ada booking',
                message: 'Catat jadwal sewa lapangan supaya tidak bentrok.',
                actionLabel: 'Booking lapangan',
                onAction: () async {
                  if (await showBookingForm(context)) _reload();
                },
              ),
            ]);
          }
          final total = items.where((b) => b.status != 'canceled').fold<double>(0, (s, b) => s + b.cost);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              StatTile(label: 'Total biaya sewa', value: fmtMoney(total), icon: Icons.receipt_long_outlined),
              const SizedBox(height: 16),
              for (final b in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
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
                              child: Text(b.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                            ShadBadge.outline(
                              child: Text(Booking.statusLabels[b.status] ?? b.status, style: t.textTheme.small),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('${fmtDateTime(b.startsAt)} • ${b.durationMin} menit', style: t.textTheme.small),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(fmtMoney(b.cost), style: const TextStyle(fontWeight: FontWeight.w600)),
                            const Spacer(),
                            if (b.status == 'booked') ...[
                              ShadButton.ghost(
                                size: ShadButtonSize.sm,
                                onPressed: () async {
                                  await b.setStatus('done');
                                  _reload();
                                },
                                child: const Text('Selesai'),
                              ),
                              ShadButton.ghost(
                                size: ShadButtonSize.sm,
                                onPressed: () async {
                                  await b.setStatus('canceled');
                                  _reload();
                                },
                                child: const Text('Batal'),
                              ),
                            ],
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 16, color: t.colorScheme.mutedForeground),
                              onPressed: () async {
                                if (await confirm(context, 'Hapus booking?', b.title)) {
                                  await Booking.delete(b.id);
                                  _reload();
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
