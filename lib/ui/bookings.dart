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
      // Ketuk baris untuk membuka kehadiran & patungan. Ini alur yang paling
      // sering dipakai setelah main: "siapa datang, siapa sudah setor".
      onTap: canceled
          ? null
          : () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => BookingDetailPage(booking: b)),
              );
              await onChanged();
            },
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
              // Membatalkan booking ikut menghapus pengeluaran sewanya dan
              // setoran patungan yang sudah tercatat, jadi sebutkan akibatnya
              // sebelum jalan.
              if (b.cost > 0) {
                final message = b.inCash
                    ? 'Catatan kas ${fmtMoney(b.cost)} untuk sewa ini ikut '
                        'dihapus, begitu juga setoran patungan yang sudah tercatat.'
                    : 'Setoran patungan yang sudah tercatat untuk sewa ini ikut dihapus.';
                if (!await confirm(
                  context,
                  'Batalkan booking?',
                  message,
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

/// Kehadiran & patungan biaya untuk satu sesi main.
///
/// Dua pertanyaan yang dijawab halaman ini, dan keduanya muncul setiap selesai
/// main: **siapa yang datang** dan **siapa yang sudah setor bagiannya**.
///
/// Biaya sewa sudah keluar dari kas saat booking dibuat. Tanpa halaman ini kas
/// hanya mencatat uang keluarnya, sehingga saldo selalu terlihat minus sebesar
/// total sewa padahal uangnya sudah dikumpulkan dari pemain.
class BookingDetailPage extends StatefulWidget {
  const BookingDetailPage({super.key, required this.booking});

  final Booking booking;

  @override
  State<BookingDetailPage> createState() => _BookingDetailPageState();
}

class _BookingDetailPageState extends State<BookingDetailPage> {
  late Future<_SplitData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SplitData> _load() async {
    final split = await BookingAttendance.splitFor(widget.booking);
    // Daftar anggota untuk dialog "tambah yang hadir". Kegagalan di sini tidak
    // boleh menggagalkan halaman: kehadiran yang sudah ada tetap bisa dilihat
    // dan disetor walau daftar anggota belum tersimpan di perangkat.
    var members = const <Member>[];
    try {
      members = await Member.all(activeOnly: true);
    } catch (_) {
      members = const [];
    }
    return _SplitData(split: split, members: members);
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  Future<void> _addAttendees(List<Member> candidates) async {
    final picked = await _pickMembers(context, candidates);
    if (picked.isEmpty) return;
    final names = {for (final m in candidates) m.id: m.name};
    for (final id in picked) {
      await BookingAttendance.add(
        widget.booking.id,
        id,
        widget.booking.cost,
        memberName: names[id] ?? '',
      );
    }
    await _reload();
  }

  Future<void> _pay(BookingAttendance row) async {
    final ok = await attempt(
      context,
      () => BookingAttendance.pay(
        attendanceId: row.id,
        memberId: row.memberId,
        amount: row.share,
        // Tanggal setoran = hari uangnya diterima, bukan tanggal main. Orang
        // bisa menyetor beberapa hari sebelumnya, dan kas harus masuk ke bulan
        // saat uangnya benar-benar ada.
        occurredAt: DateTime.now(),
        note: 'Patungan ${widget.booking.title} ${fmtShortDate(widget.booking.startsAt)}',
      ),
      fail: 'Gagal menyimpan setoran',
    );
    if (ok) await _reload();
  }

  Future<void> _unpay(BookingAttendance row) async {
    if (!await confirm(
      context,
      'Batalkan setoran?',
      'Setoran ${fmtMoney(row.share)} dari ${row.memberName} dihapus dari kas, '
          'dan statusnya kembali belum bayar.',
      confirmLabel: 'Batalkan setoran',
    )) {
      return;
    }
    if (!mounted) return;
    final ok = await attempt(
      context,
      () => BookingAttendance.unpay(row.id),
      fail: 'Gagal membatalkan setoran',
    );
    if (ok) await _reload();
  }

  Future<void> _remove(BookingAttendance row) async {
    // Menghapus baris kehadiran ikut menghapus setorannya (CASCADE). Kalau
    // orang itu sudah menyetor, uangnya hilang dari kas — sebutkan.
    if (row.paid) {
      if (!await confirm(
        context,
        'Keluarkan ${row.memberName}?',
        'Dia sudah menyetor ${fmtMoney(row.share)}. Setoran itu ikut dihapus '
            'dari kas dan saldo berubah.',
        confirmLabel: 'Keluarkan',
      )) {
        return;
      }
    } else {
      if (!await confirm(context, 'Keluarkan ${row.memberName}?',
          'Dia tidak lagi dihitung hadir dan bagian biaya orang lain dihitung ulang.')) {
        return;
      }
    }
    if (!mounted) return;
    final ok = await attempt(
      context,
      () => BookingAttendance.remove(row.id, widget.booking.id, widget.booking.cost),
      fail: 'Gagal mengeluarkan',
    );
    if (ok) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final b = widget.booking;

    return PageScaffold(
      title: b.title,
      subtitle: '${fmtDate(b.startsAt)} • ${fmtTime(b.startsAt)} • ${b.durationMin} menit',
      child: AsyncView<_SplitData>(
        future: _future,
        onRefresh: _reload,
        builder: (d) {
          final s = d.split;
          final available = d.members.where((m) => !s.rows.any((r) => r.memberId == m.id)).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              StatStrip(
                children: [
                  StatTile(
                    label: 'Biaya sewa',
                    value: fmtMoney(b.cost),
                    hint: b.inCash ? 'sudah di kas' : 'belum di kas',
                    color: AppThemes.money(context),
                  ),
                  StatTile(
                    label: 'Terkumpul',
                    value: fmtMoney(s.collected),
                    hint: '${s.paidCount}/${s.rows.length} orang',
                    color: AppThemes.money(context),
                  ),
                  StatTile(
                    label: 'Kurang',
                    value: fmtMoney(s.outstanding),
                    hint: s.rows.isEmpty ? 'belum ada yang hadir' : '${s.unpaidCount} orang',
                    color: s.outstanding > 0 ? AppThemes.bad(context) : t.colorScheme.mutedForeground,
                  ),
                ],
              ),
              if (s.rows.isNotEmpty && b.cost > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Dibagi rata: '
                    '${s.uneven ? '${fmtMoney(s.perPersonMin)}–${fmtMoney(s.perPerson)}' : fmtMoney(s.perPerson)}'
                    ' per orang (${s.rows.length} yang hadir)',
                    style: t.textTheme.small,
                  ),
                ),
              if (s.uncovered > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Belum ada yang hadir, jadi biaya ${fmtMoney(s.uncovered)} '
                    'sepenuhnya ditanggung kas.',
                    style: t.textTheme.small.copyWith(color: AppThemes.bad(context)),
                  ),
                )
              else if (s.shortfall > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Masih kurang ${fmtMoney(s.shortfall)} dari biaya sewa. '
                    'Setoran yang sudah masuk tidak diubah otomatis; '
                    'kekurangannya ditanggung kas sampai ditagih.',
                    style: t.textTheme.small.copyWith(color: AppThemes.bad(context)),
                  ),
                ),
              const SectionTitle('Yang hadir'),
              if (s.rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    d.members.isEmpty
                        ? 'Daftar anggota belum tersimpan di perangkat. Buka halaman '
                            'Anggota sekali saat online.'
                        : 'Belum ada yang dicatat hadir.',
                    style: t.textTheme.muted,
                  ),
                )
              else
                for (final r in s.rows)
                  _AttendeeRow(
                    row: r,
                    canWrite: Auth.canWrite,
                    // Booking tanpa biaya tidak punya bagian untuk disetor;
                    // tombol setor hanya akan mencatat pemasukan Rp 0 ke kas.
                    canPay: Auth.canWrite && b.cost > 0,
                    onPay: () => _pay(r),
                    onUnpay: () => _unpay(r),
                    onRemove: () => _remove(r),
                  ),
              if (Auth.canWrite && available.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: () => _addAttendees(d.members),
                    child: const Text('Tambah yang hadir'),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                b.cost > 0
                    ? 'Biaya sewa ${fmtMoney(b.cost)} dibagi rata ke semua yang hadir. '
                        'Setoran yang dicatat di sini masuk ke Kas sebagai pemasukan '
                        '"Patungan lapangan".'
                    : 'Booking ini tanpa biaya, jadi tidak ada yang perlu dibagi.',
                style: t.textTheme.small,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SplitData {
  const _SplitData({required this.split, required this.members});

  final BookingSplit split;
  final List<Member> members;
}

class _AttendeeRow extends StatelessWidget {
  const _AttendeeRow({
    required this.row,
    required this.canWrite,
    required this.canPay,
    required this.onPay,
    required this.onUnpay,
    required this.onRemove,
  });

  final BookingAttendance row;
  final bool canWrite;
  final bool canPay;
  final VoidCallback onPay;
  final VoidCallback onUnpay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return RowItem(
      leading: Icon(
        row.paid ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 20,
        color: row.paid ? t.colorScheme.primary : t.colorScheme.mutedForeground,
      ),
      title: row.memberName,
      subtitle: row.paid
          ? (row.cash + 0.005 < row.share
              ? 'Sudah setor ${fmtMoney(row.cash)}, kurang ${fmtMoney(row.share - row.cash)}'
              : 'Sudah setor')
          : 'Belum setor',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            fmtMoney(row.share),
            style: t.textTheme.table.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: AppThemes.tabular,
              color: row.paid ? t.colorScheme.primary : t.colorScheme.foreground,
            ),
          ),
          if (canPay) ...[
            const SizedBox(width: 6),
            iconAction(
              context,
              row.paid ? Icons.undo : Icons.payments_outlined,
              row.paid ? onUnpay : onPay,
              tooltip: row.paid ? 'Batalkan setoran' : 'Tandai sudah setor',
            ),
          ],
          if (canWrite) ...[
            const SizedBox(width: 6),
            iconAction(context, Icons.person_remove_outlined, onRemove,
                tooltip: 'Keluarkan dari daftar hadir'),
          ],
        ],
      ),
    );
  }
}

/// Dialog pilih anggota yang hadir. Mengembalikan id yang dipilih.
Future<Set<int>> _pickMembers(BuildContext context, List<Member> members) async {
  final selected = <int>{};
  final result = await showShadDialog<Set<int>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => ShadDialog(
        title: const Text('Siapa yang hadir?'),
        description: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (members.isEmpty)
              Text(
                'Daftar anggota belum tersimpan di perangkat. Buka halaman '
                'Anggota sekali saat online.',
                style: ShadTheme.of(ctx).textTheme.small,
              )
            else
              // ShadDialog tidak menyediakan Material: tanpa ini checkbox
              // tampil sebagai kotak abu-abu tanpa teks.
              Material(
                type: MaterialType.transparency,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 280),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final m in members)
                        InkWell(
                          onTap: () => setLocal(() {
                            if (!selected.remove(m.id)) selected.add(m.id);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: selected.contains(m.id),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onChanged: (v) => setLocal(() {
                                    if (v == true) {
                                      selected.add(m.id);
                                    } else {
                                      selected.remove(m.id);
                                    }
                                  }),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    m.name,
                                    style: const TextStyle(fontSize: 13.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(ctx).pop(<int>{}),
            child: const Text('Batal'),
          ),
          ShadButton(
            onPressed: members.isEmpty
                ? null
                : () => Navigator.of(ctx).pop(selected.toSet()),
            child: Text(selected.isEmpty ? 'Tambah' : 'Tambah ${selected.length}'),
          ),
        ],
      ),
    ),
  );
  return result ?? <int>{};
}
