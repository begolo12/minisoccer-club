import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/soft.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'member_dues.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Akun saya" untuk role anggota.
///
///(application ini dipakai club, dan role anggota adalah MOST of the users
/// yang membuka app tiap minggu. Duranteini mereka tidak punya halaman
/// sendiri: mereka harus mencari namanya di daftar anggota untuk melihat
/// iuran mereka, dan tidak bisa tahu kapan main berikutnya tanpa membuka
/// Turnamen lalu mencari jadwal timnya sendiri.
///
/// Halaman ini menjawab tiga pertanyaan yang paling sering muncul di grup
/// WhatsApp:
///   * "Sudah bayar belum?"  → riwayat iuran + tunggakan
///   * "Mainnya kapan?"       → jadwal berikutnya
///   * "Tunggakan saya?"     → nominal yang belum dibayar
class MyAccountPage extends StatefulWidget {
  const MyAccountPage({super.key, required this.member});

  final Member member;

  @override
  State<MyAccountPage> createState() => _MyAccountPageState();
}

class _MyAccountPageState extends State<MyAccountPage> {
  late Future<_MyData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MyData> _load() async {
    final id = widget.member.id;
    // Tiga bacaan sekaligus: halaman ini dibuka untuk satu orang, jadi
    // menunggu berurutan hanya menambah waktu tanpa manfaat.
    final r = await Future.wait<Soft<Object?>>([
      soft('Iuran saya', () => Payment.forMember(id), fallback: const <Payment>[]),
      soft(
        'Tunggakan saya',
        () => Payment.unpaidForMember(id),
        fallback: const <Tournament>[],
      ),
      soft('Jadwal main', () => _upcomingMatches(id), fallback: const <Match>[]),
    ]);
    final failures = settle(r);
    return _MyData(
      payments: r[0].value! as List<Payment>,
      unpaid: r[1].value! as List<Tournament>,
      matches: r[2].value! as List<Match>,
      failures: failures,
    );
  }

  /// Laga yang akan datang — lewat tim yang dimasuki anggota ini.
  Future<List<Match>> _upcomingMatches(int memberId) async {
    final players = await Team.players();
    final teamIds = players.entries
        .where((e) => e.value.any((m) => m.id == memberId))
        .map((e) => e.key)
        .toSet();
    if (teamIds.isEmpty) return const [];
    final all = await Match.all();
    return all
        .where((m) =>
            !m.finished &&
            (teamIds.contains(m.homeTeamId) || teamIds.contains(m.awayTeamId)))
        .toList()
      ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
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
      title: 'Akun saya',
      subtitle: '${m.name} • ${m.position}',
      child: AsyncView<_MyData>(
        future: _future,
        onRefresh: _reload,
        builder: (d) {
          final totalPaid = d.payments.fold<double>(0, (s, p) => s + p.amount);
          final unpaid = d.unpaid.fold<double>(0, (s, t) => s + t.entryFee);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              if (d.failures.isNotEmpty)
                DegradedNotice(failures: d.failures, onRetry: _reload),
              StatStrip(
                children: [
                  StatTile(
                    label: 'Sudah bayar',
                    value: fmtMoney(totalPaid),
                    hint: '${d.payments.length} pembayaran',
                    color: AppThemes.money(context),
                  ),
                  StatTile(
                    label: 'Tunggakan',
                    value: fmtMoney(unpaid),
                    hint: d.unpaid.isEmpty ? 'tidak ada' : '${d.unpaid.length} turnamen',
                    color: d.unpaid.isEmpty
                        ? t.colorScheme.mutedForeground
                        : AppThemes.bad(context),
                  ),
                ],
              ),
              if (d.matches.isNotEmpty) ...[
                const SectionTitle('Main berikutnya'),
                for (final match in d.matches.take(3))
                  MatchRow(match: match),
              ],
              if (d.unpaid.isNotEmpty) ...[
                const SectionTitle('Belum dibayar'),
                for (final tour in d.unpaid)
                  RowItem(
                    leading: Icon(Icons.error_outline,
                        size: 18, color: AppThemes.bad(context)),
                    title: tour.name,
                    subtitle: 'Iuran ${fmtMoney(tour.entryFee)}',
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
                    title: p.tournamentName.isEmpty ? 'Iuran' : p.tournamentName,
                    subtitle: fmtDate(p.paidAt),
                    trailing: Text(
                      fmtMoney(p.amount),
                      style: t.textTheme.table.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppThemes.money(context),
                        fontFeatures: AppThemes.tabular,
                      ),
                    ),
                  ),
              const SizedBox(height: 18),
              // Riwayat lengkap satu anggota (patungan lapangan ikut di sana)
              // tersedia lewat halaman yang sama dengan yang dipakai admin.
              Align(
                alignment: Alignment.centerLeft,
                child: ShadButton.outline(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MemberDuesPage(member: widget.member),
                    ),
                  ),
                  child: const Text('Rincian lengkap'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MyData {
  const _MyData({
    required this.payments,
    required this.unpaid,
    required this.matches,
    required this.failures,
  });

  final List<Payment> payments;
  final List<Tournament> unpaid;
  final List<Match> matches;
  final List<String> failures;
}
