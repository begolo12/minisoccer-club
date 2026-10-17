import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'theme.dart';
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
    return PageScaffold(
      title: 'Booking lapangan',
      subtitle: 'Sewa lapangan & biaya',
      actions: [
        iconAction(context, Icons.add, () async {
          if (await showBookingForm(context)) _reload();
        }, tooltip: 'Booking baru'),
      ],
      child: AsyncView<List<Booking>>(
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              StatTile(
                label: 'Total biaya sewa',
                value: fmtMoney(total),
                color: AppThemes.money(context),
              ),
              for (final b in items)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: t.colorScheme.border.withValues(alpha: 0.7)),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: t.textTheme.large,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${fmtDateTime(b.startsAt)} • ${b.durationMin} menit'
                              ' • ${Booking.statusLabels[b.status] ?? b.status}',
                              style: t.textTheme.small,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            fmtMoney(b.cost),
                            style: t.textTheme.table.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppThemes.money(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (b.status == 'booked') ...[
                                iconAction(context, Icons.check, () async {
                                  await b.setStatus('done');
                                  _reload();
                                }, tooltip: 'Tandai selesai'),
                                const SizedBox(width: 6),
                                iconAction(context, Icons.block, () async {
                                  await b.setStatus('canceled');
                                  _reload();
                                }, tooltip: 'Batalkan'),
                                const SizedBox(width: 6),
                              ],
                              iconAction(context, Icons.delete_outline, () async {
                                if (await confirm(context, 'Hapus booking?', b.title)) {
                                  await Booking.delete(b.id);
                                  _reload();
                                }
                              }, tooltip: 'Hapus'),
                            ],
                          ),
                        ],
                      ),
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
