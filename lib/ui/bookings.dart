import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'theme.dart';
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
    return PageScaffold(
      title: 'Booking lapangan',
      subtitle: 'Sewa lapangan & biaya',
      actions: [
        if (Auth.canWrite)
          iconAction(context, Icons.add, () async {
            if (await showBookingForm(context)) _reload();
          }, tooltip: 'Booking baru'),
      ],
      child: AsyncView<List<Booking>>(
        future: _future,
        onRefresh: _reload,
        builder: (items) {
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.stadium_outlined,
                  title: 'Belum ada booking',
                  message: 'Catat jadwal sewa lapangan supaya tidak bentrok.',
                  actionLabel: Auth.canWrite ? 'Booking lapangan' : null,
                  onAction: Auth.canWrite
                      ? () async {
                          if (await showBookingForm(context)) _reload();
                        }
                      : null,
                ),
              ],
            );
          }
          final now = DateTime.now();
          final active = items.where((b) => b.status != 'canceled').toList();
          final total = active.fold<double>(0, (s, b) => s + b.cost);
          final next = items
              .where((b) => b.status == 'booked' && b.startsAt.isAfter(now))
              .toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
          final past = items.where((b) => !next.contains(b)).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              StatStrip(
                children: [
                  StatTile(
                    label: 'Total sewa',
                    value: fmtMoney(total),
                    hint: '${active.length} booking',
                    color: AppThemes.money(context),
                  ),
                  StatTile(
                    label: 'Berikutnya',
                    value: next.isEmpty ? '—' : fmtShortDate(next.first.startsAt),
                    hint: next.isEmpty ? 'belum ada' : fmtTime(next.first.startsAt),
                  ),
                ],
              ),
              if (next.isNotEmpty) ...[
                const SectionTitle('Akan datang'),
                for (final b in next) _BookingRow(booking: b, onChanged: _reload, upcoming: true),
              ],
              const SectionTitle('Riwayat'),
              if (past.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Belum ada booking sebelumnya.', style: ShadTheme.of(context).textTheme.muted),
                )
              else
                for (final b in past) _BookingRow(booking: b, onChanged: _reload),
            ],
          );
        },
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.booking, required this.onChanged, this.upcoming = false});

  final Booking booking;
  final Future<void> Function() onChanged;
  final bool upcoming;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final b = booking;
    final canceled = b.status == 'canceled';
    final statusColor = switch (b.status) {
      'done' => t.colorScheme.mutedForeground,
      'canceled' => AppThemes.bad(context),
      _ => upcoming ? t.colorScheme.primary : t.colorScheme.mutedForeground,
    };

    return RowItem(
      leading: SizedBox(
        width: 52,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              fmtShortDate(b.startsAt),
              maxLines: 1,
              style: t.textTheme.small.copyWith(
                fontFeatures: AppThemes.tabular,
                color: statusColor,
              ),
            ),
            Text(
              fmtTime(b.startsAt),
              maxLines: 1,
              style: t.textTheme.h1.copyWith(fontSize: 21, color: statusColor),
            ),
          ],
        ),
      ),
      title: b.title,
      subtitle: '${b.durationMin} menit • ${Booking.statusLabels[b.status] ?? b.status}'
          '${b.cost <= 0 ? '' : (b.inCash ? ' • sudah di kas' : ' • belum di kas')}',
      trailingBelow: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            fmtMoney(b.cost),
            style: t.textTheme.table.copyWith(
              fontWeight: FontWeight.w600,
              color: canceled ? t.colorScheme.mutedForeground : AppThemes.money(context),
              decoration: canceled ? TextDecoration.lineThrough : null,
            ),
          ),
          if (Auth.canWrite && b.status == 'booked') ...[
            const SizedBox(width: 8),
            iconAction(context, Icons.check, () async {
              if (await attempt(context, () => b.setStatus('done'), fail: 'Gagal menyimpan')) {
                await onChanged();
              }
            }, tooltip: 'Tandai selesai'),
            const SizedBox(width: 6),
            iconAction(context, Icons.block, () async {
              // Membatalkan booking ikut menghapus pengeluaran sewanya dari
              // kas, jadi sebutkan akibatnya sebelum jalan.
              if (b.cost > 0 && b.inCash) {
                if (!await confirm(
                  context,
                  'Batalkan booking?',
                  'Catatan kas ${fmtMoney(b.cost)} untuk sewa ini ikut dihapus.',
                  confirmLabel: 'Batalkan',
                )) {
                  return;
                }
                if (!context.mounted) return;
              }
              if (await attempt(context, () => b.setStatus('canceled'), fail: 'Gagal menyimpan')) {
                await onChanged();
              }
            }, tooltip: 'Batalkan'),
          ],
          if (Auth.canWrite) ...[
            const SizedBox(width: 6),
            iconAction(context, Icons.delete_outline, () async {
              if (await confirm(context, 'Hapus booking?', b.title)) {
                if (!context.mounted) return;
                if (await attempt(context, () => Booking.delete(b.id), fail: 'Gagal menghapus')) {
                  await onChanged();
                }
              }
            }, tooltip: 'Hapus'),
          ],
        ],
      ),
    );
  }
}
