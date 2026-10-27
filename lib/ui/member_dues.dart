import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/soft.dart';
import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'login_gate.dart';
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

  /// Riwayat iuran satu orang = data uang; tamu tidak boleh membacanya.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Auth.session.addListener(_onAuth);
    _ensureLoaded();
  }

  void _ensureLoaded() {
    if (!Auth.signedIn || _loaded) return;
    _loaded = true;
    _future = _load();
  }

  void _onAuth() {
    if (!mounted) return;
    setState(() {
      _loaded = false;
      _ensureLoaded();
    });
  }

  @override
  void dispose() {
    Auth.session.removeListener(_onAuth);
    super.dispose();
  }

  Future<_DuesHistory> _load() async {
    // Empat bacaan dijalankan bersama dan masing-masing boleh gagal sendiri:
    // satu query gagal tidak boleh membuang riwayat yang sudah terbaca.
    // Semua gagal = server/jaringan mati; `settle` melempar untuk itu supaya
    // layar error penuh dengan tombol coba lagi yang tampil.
    final r = await Future.wait<Soft<Object?>>([
      soft('Riwayat iuran', () => Payment.forMember(widget.member.id),
          fallback: const <Payment>[]),
      soft('Tunggakan', () => Payment.unpaidForMember(widget.member.id),
          fallback: const <Tournament>[]),
      soft('Patungan lapangan', () => BookingAttendance.forMember(widget.member.id),
          fallback: const <BookingAttendance>[]),
      soft('Iuran di antrean', () => Payment.pendingTournamentIds(widget.member.id),
          fallback: const <int>{}),
    ]);
    final failures = settle(r);
    final pending = r[3].value! as Set<int>;
    return _DuesHistory(
      payments: (r[0].value! as List).cast<Payment>(),
      // Iuran yang masih di antrean belum ada di server, dan daftar tunggakan
      // adalah query ringkasan yang tidak ditambal di cache — tanpa saringan
      // ini orang yang baru dibayar tetap tampil menunggak.
      unpaid: (r[1].value! as List)
          .cast<Tournament>()
          .where((t) => !pending.contains(t.id))
          .toList(),
      attendance: (r[2].value! as List).cast<BookingAttendance>(),
      failures: failures,
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

    if (!Auth.signedIn) return const LockedMoney(title: 'Riwayat iuran');
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
              if (d.failures.isNotEmpty)
                DegradedNotice(failures: d.failures, onRetry: _reload),
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
                    subtitle: 'Iuran ${fmtMoney(tour.entryFee)}',
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
    required this.failures,
  });

  final List<Payment> payments;
  final List<Tournament> unpaid;
  final List<BookingAttendance> attendance;

  /// Sumber yang gagal dimuat; bagian yang berhasil tetap ditampilkan.
  final List<String> failures;

  double get totalPaid => payments.fold<double>(0, (s, p) => s + p.amount);

  /// Nominal turnamen yang belum dibayar. Turnamen tanpa nominal tidak
  /// menambah angka, tetapi tetap muncul di daftar supaya terlihat.
  double get totalUnpaid => unpaid.fold<double>(0, (s, t) => s + t.entryFee);
}
