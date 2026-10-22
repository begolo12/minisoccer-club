import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

/// Riwayat iuran satu anggota.
///
/// Halaman ini menjawab "saya sudah bayar apa saja, dan apa yang masih
/// kurang?" — pertanyaan yang paling sering muncul di grup WhatsApp dan
/// sebelumnya hanya bisa dijawab dengan membuka turnamen satu per satu.
///
/// Dua bagian sengaja dipisah: **tunggakan** di atas (yang perlu ditindak) dan
/// **riwayat** di bawah (yang sudah beres). Menggabungkannya membuat bendahara
/// harus membaca seluruh daftar untuk menemukan siapa yang belum bayar.
class MemberDuesPage extends StatefulWidget {
  const MemberDuesPage({super.key, required this.member});

  final Member member;

  @override
  State<MemberDuesPage> createState() => _MemberDuesPageState();
}

class _MemberDuesPageState extends State<MemberDuesPage> {
  late Future<_DuesHistory> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DuesHistory> _load() async {
    // Ketiga bacaan dijalankan bersama: halaman ini dibuka untuk satu orang,
    // jadi menunggunya berurutan hanya menambah waktu tunggu tanpa manfaat.
    final results = await Future.wait<Object?>([
      Payment.forMember(widget.member.id),
      Payment.unpaidForMember(widget.member.id),
      BookingAttendance.forMember(widget.member.id),
      Payment.pendingTournamentIds(widget.member.id),
    ]);
    final pending = results[3] as Set<int>;
    return _DuesHistory(
      payments: (results[0] as List).cast<Payment>(),
      // Iuran yang masih di antrean belum ada di server, dan daftar tunggakan
      // adalah query ringkasan yang tidak ditambal di cache — tanpa saringan
      // ini orang yang baru dibayar tetap tampil menunggak.
      unpaid: (results[1] as List)
          .cast<Tournament>()
          .where((t) => !pending.contains(t.id))
          .toList(),
      attendance: (results[2] as List).cast<BookingAttendance>(),
    );
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final m = widget.member;

    return PageScaffold(
      title: m.name,
      subtitle: '${m.position}${m.phone != null ? ' • ${m.phone}' : ''}'
          '${m.active ? '' : ' • nonaktif'}',
      child: AsyncView<_DuesHistory>(
        future: _future,
        onRefresh: _reload,
        builder: (d) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              StatStrip(
                children: [
                  StatTile(
                    label: 'Total iuran',
                    value: fmtMoney(d.totalPaid),
                    hint: '${d.payments.length} pembayaran',
                    color: AppThemes.money(context),
                  ),
                  StatTile(
                    label: 'Tunggakan',
                    value: fmtMoney(d.totalUnpaid),
                    hint: d.unpaid.isEmpty ? 'tidak ada' : '${d.unpaid.length} turnamen',
                    color: d.unpaid.isEmpty
                        ? t.colorScheme.mutedForeground
                        : AppThemes.bad(context),
                  ),
                ],
              ),
              if (d.unpaid.isNotEmpty) ...[
                const SectionTitle('Belum dibayar'),
                for (final tour in d.unpaid)
                  RowItem(
                    leading: Icon(Icons.error_outline,
                        size: 18, color: AppThemes.bad(context)),
                    title: tour.name,
                    subtitle: tour.entryFee > 0
                        ? 'Iuran ${fmtMoney(tour.entryFee)}'
                        : 'Tanpa nominal',
                    trailing: Auth.canWrite
                        ? iconAction(context, Icons.payments_outlined, () async {
                            if (await showPaymentForm(
                              context,
                              tournamentId: tour.id,
                              memberId: m.id,
                              entryFee: tour.entryFee,
                            )) {
                              await _reload();
                            }
                          }, tooltip: 'Catat pembayaran')
                        : null,
                  ),
              ],
              const SectionTitle('Riwayat iuran'),
              if (d.payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text('Belum ada iuran tercatat.', style: t.textTheme.muted),
                )
              else
                for (final p in d.payments)
                  RowItem(
                    leading: Icon(Icons.check_circle_outline,
                        size: 18, color: t.colorScheme.primary),
                    title: p.tournamentName.isEmpty
                        ? 'Iuran'
                        : p.tournamentName,
                    subtitle: '${fmtDate(p.paidAt)}'
                        '${p.note == null || p.note!.isEmpty ? '' : ' • ${p.note}'}',
                    trailing: Text(
                      fmtMoney(p.amount),
                      style: t.textTheme.table.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppThemes.money(context),
                        fontFeatures: AppThemes.tabular,
                      ),
                    ),
                  ),
              if (d.attendance.isNotEmpty) ...[
                const SectionTitle('Patungan lapangan'),
                for (final a in d.attendance)
                  RowItem(
                    leading: Icon(
                      a.paid ? Icons.check_circle_outline : Icons.schedule,
                      size: 18,
                      color: a.paid
                          ? t.colorScheme.primary
                          : t.colorScheme.mutedForeground,
                    ),
                    title: a.bookingTitle.isEmpty ? 'Patungan lapangan' : a.bookingTitle,
                    subtitle: a.bookingStartsAt == null
                        ? (a.paid ? 'Sudah setor' : 'Belum setor')
                        : '${fmtDate(a.bookingStartsAt!)} • '
                            '${a.paid ? 'sudah setor' : 'belum setor'}',
                    trailing: Text(
                      fmtMoney(a.share),
                      style: t.textTheme.table.copyWith(
                        fontWeight: FontWeight.w600,
                        color: a.paid
                            ? AppThemes.money(context)
                            : t.colorScheme.mutedForeground,
                        fontFeatures: AppThemes.tabular,
                      ),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DuesHistory {
  const _DuesHistory({
    required this.payments,
    required this.unpaid,
    required this.attendance,
  });

  final List<Payment> payments;
  final List<Tournament> unpaid;
  final List<BookingAttendance> attendance;

  double get totalPaid => payments.fold<double>(0, (s, p) => s + p.amount);

  /// Nominal turnamen yang belum dibayar. Turnamen tanpa nominal tidak
  /// menambah angka, tetapi tetap muncul di daftar supaya terlihat.
  double get totalUnpaid => unpaid.fold<double>(0, (s, t) => s + t.entryFee);
}
