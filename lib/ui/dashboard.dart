import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'finance.dart';
import 'fmt.dart';
import 'forms.dart';
import 'matches.dart';
import 'theme.dart';
import 'tournament.dart';
import 'widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardData {
  final List<Match> upcoming;
  final List<Match> recent;
  final List<int> stats;
  final int members;
  final double income;
  final CashSummary cash;
  final List<ScorerRow> scorers;
  final List<Announcement> news;
  final List<Member> unpaid;
  final double? dues;

  _DashboardData({
    required this.upcoming,
    required this.recent,
    required this.stats,
    required this.members,
    required this.income,
    required this.cash,
    required this.scorers,
    required this.news,
    required this.unpaid,
    required this.dues,
  });

  static Future<_DashboardData> load() async {
    final period = periodNow();
    final results = await Future.wait([
      Match.upcoming(),
      Match.recentFinished(),
      Match.stats(),
      Member.countActive(),
      ScorerRow.top(),
      Announcement.all(),
      Member.all(activeOnly: true),
      Payment.all(period: period),
      Transaction.all(period: period),
      Payment.standardAmount(),
    ]);
    final active = results[6] as List<Member>;
    final payments = results[7] as List<Payment>;
    final paid = {for (final p in payments) p.memberId};
    final cash = CashSummary.fromEntries(mergeCashLedger(
      payments: payments,
      transactions: results[8] as List<Transaction>,
    ));
    return _DashboardData(
      upcoming: results[0] as List<Match>,
      recent: results[1] as List<Match>,
      stats: results[2] as List<int>,
      members: results[3] as int,
      income: cash.dues,
      cash: cash,
      scorers: results[4] as List<ScorerRow>,
      news: results[5] as List<Announcement>,
      unpaid: active.where((m) => !paid.contains(m.id)).toList(),
      dues: results[9] as double?,
    );
  }
}

class _DashboardPageState extends State<DashboardPage> with SingleTickerProviderStateMixin {
  late Future<_DashboardData> _future;
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  @override
  void initState() {
    super.initState();
    _future = _DashboardData.load();
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final f = _DashboardData.load();
    setState(() => _future = f);
    _in.forward(from: 0);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Halo, Klub',
      subtitle: fmtDate(DateTime.now()),
      actions: [iconAction(context, Icons.refresh, _reload, tooltip: 'Muat ulang')],
      child: AsyncView<_DashboardData>(
        future: _future,
        onRefresh: _reload,
        builder: (d) => LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 880;
            final main = _MainColumn(data: d, anim: _in, onChanged: _reload);
            if (!wide) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [main],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: main),
                    const SizedBox(width: 28),
                    Expanded(flex: 2, child: _RailColumn(data: d, anim: _in)),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Fade + naik sedikit saat data siap. Satu kali per muat, bukan per scroll.
class _In extends StatelessWidget {
  const _In({required this.anim, required this.begin, required this.child});

  final Animation<double> anim;
  final double begin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final a = CurvedAnimation(
      parent: anim,
      curve: Interval(begin.clamp(0, 0.7), (begin + 0.3).clamp(0.3, 1), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
        child: child,
      ),
    );
  }
}

class _MainColumn extends StatelessWidget {
  const _MainColumn({required this.data, required this.anim, required this.onChanged});

  final _DashboardData data;
  final Animation<double> anim;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final d = data;
    final played = d.stats[0] + d.stats[1] + d.stats[2];
    final m = d.upcoming.isNotEmpty ? d.upcoming.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _In(
          anim: anim,
          begin: 0,
          child: _FixtureStrip(match: m, onChanged: onChanged),
        ),
        const SizedBox(height: 10),
        _In(
          anim: anim,
          begin: 0.08,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: t.colorScheme.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: StatTile(label: 'Anggota', value: '${d.members}', hint: 'aktif')),
                _divider(t),
                Expanded(
                  child: StatTile(
                    label: 'Main',
                    value: '$played',
                    hint: '${d.stats[0]}M ${d.stats[1]}S ${d.stats[2]}K',
                  ),
                ),
                _divider(t),
                Expanded(
                  child: StatTile(
                    label: 'Iuran',
                    value: fmtMoney(d.income),
                    color: AppThemes.money(context),
                    hint: '${d.members - d.unpaid.length}/${d.members} lunas',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        _In(
          anim: anim,
          begin: 0.12,
          child: _CashBlock(cash: d.cash, onChanged: onChanged),
        ),
        if (Auth.canWrite)
          _In(
            anim: anim,
            begin: 0.16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('Aksi cepat'),
                _QuickGrid(
                  actions: [
                    _QuickAction(Icons.person_add_alt, 'Anggota', () async {
                      if (await showMemberForm(context)) onChanged();
                    }),
                    _QuickAction(Icons.event, 'Tanding', () async {
                      if (await showMatchForm(context)) onChanged();
                    }),
                    _QuickAction(Icons.emoji_events_outlined, 'Turnamen', () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TournamentsPage()),
                      );
                      onChanged();
                    }),
                    _QuickAction(Icons.payments, 'Iuran', () async {
                      if (await showPaymentForm(context)) onChanged();
                    }),
                    _QuickAction(Icons.stadium_outlined, 'Booking', () async {
                      if (await showBookingForm(context)) onChanged();
                    }),
                    _QuickAction(Icons.campaign_outlined, 'Umumkan', () async {
                      if (await showAnnouncementForm(context)) onChanged();
                    }),
                  ],
                ),
              ],
            ),
          ),
        _In(
          anim: anim,
          begin: 0.24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('Pertandingan terakhir'),
              if (d.recent.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Belum ada pertandingan.', style: t.textTheme.muted),
                )
              else
                for (final r in d.recent.take(4))
                  RowItem(
                    leading: _Score(match: r),
                    title: 'vs ${r.opponent}',
                    subtitle: '${fmtDate(r.playedAt)}${r.venue == null ? '' : ' • ${r.venue}'}',
                    trailing: _ResultTag(match: r),
                  ),
            ],
          ),
        ),
        _In(
          anim: anim,
          begin: 0.32,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('Pengumuman'),
              if (d.news.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Belum ada pengumuman.', style: t.textTheme.muted),
                )
              else
                for (final a in d.news.take(2))
                  RowItem(
                    title: a.title,
                    subtitle: '${fmtDate(a.createdAt)} • ${a.body}',
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider(ShadThemeData t) => Container(
        width: 1,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: t.colorScheme.border,
      );
}

/// Ringkasan kas bulan ini. Ketuk untuk membuka buku kas lengkap.
class _CashBlock extends StatelessWidget {
  const _CashBlock({required this.cash, required this.onChanged});

  final CashSummary cash;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Kas bulan ini',
          action: TextButton(
            onPressed: () => _open(context),
            child: const Text('Buka'),
          ),
        ),
        InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: StatTile(label: 'Masuk', value: fmtMoney(cash.income))),
                _divider(t),
                Expanded(child: StatTile(label: 'Keluar', value: fmtMoney(cash.expense))),
                _divider(t),
                Expanded(
                  child: StatTile(
                    label: 'Saldo',
                    value: fmtMoney(cash.balance),
                    color: cash.balance < 0
                        ? AppThemes.bad(context)
                        : AppThemes.money(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (cash.income == 0 && cash.expense == 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Belum ada pemasukan atau pengeluaran tercatat bulan ini.',
              style: t.textTheme.small,
            ),
          ),
      ],
    );
  }

  Future<void> _open(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FinancePage()),
    );
    await onChanged();
  }

  Widget _divider(ShadThemeData t) => Container(
        width: 1,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: t.colorScheme.border,
      );
}

/// Kolom kanan di layar lebar: uang dan top skor. Di HP ikut alur utama.
class _RailColumn extends StatelessWidget {
  const _RailColumn({required this.data, required this.anim});

  final _DashboardData data;
  final Animation<double> anim;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final d = data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _In(
          anim: anim,
          begin: 0.1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('Belum bayar', top: 0),
              if (d.unpaid.isEmpty)
                Text('Semua anggota aktif sudah lunas bulan ini.', style: t.textTheme.muted)
              else
                for (final m in d.unpaid.take(6))
                  RowItem(
                    title: m.name,
                    subtitle: m.position,
                    trailing: Text(
                      d.dues == null ? 'Belum bayar' : fmtMoney(d.dues!),
                      style: t.textTheme.table.copyWith(color: AppThemes.bad(context)),
                    ),
                  ),
            ],
          ),
        ),
        _In(
          anim: anim,
          begin: 0.2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('Top skor'),
              if (d.scorers.isEmpty)
                Text('Belum ada gol tercatat.', style: t.textTheme.muted)
              else
                for (var i = 0; i < d.scorers.length && i < 6; i++)
                  RowItem(
                    leading: SizedBox(
                      width: 20,
                      child: Text(
                        '${i + 1}',
                        style: t.textTheme.h2.copyWith(
                          fontSize: 20,
                          color: i == 0 ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                    title: d.scorers[i].name,
                    subtitle: '${d.scorers[i].assists} assist',
                    trailing: Text('${d.scorers[i].goals}', style: t.textTheme.h2.copyWith(fontSize: 20)),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Laga berikutnya sebagai papan skor, bukan kartu gradien.
class _FixtureStrip extends StatelessWidget {
  const _FixtureStrip({required this.match, required this.onChanged});

  final Match? match;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final dark = t.brightness == Brightness.dark;
    final m = match;

    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0C1A12) : const Color(0xFFEAF6EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.colorScheme.primary.withValues(alpha: dark ? 0.45 : 0.35)),
      ),
      child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Pill(
                      m == null
                          ? 'Belum ada jadwal'
                          : (m.status == 'ongoing' ? 'Sedang berlangsung' : 'Laga berikutnya'),
                      color: t.colorScheme.primary,
                    ),
                    const Spacer(),
                    if (m != null) Pill(m.isHome ? 'Kandang' : 'Tandang'),
                  ],
                ),
                const SizedBox(height: 8),
                Text.rich(
                  TextSpan(
                    children: [
                      if (m != null)
                        TextSpan(
                          text: 'vs ',
                          style: t.textTheme.h2.copyWith(
                            fontSize: 24,
                            color: t.colorScheme.mutedForeground,
                          ),
                        ),
                      TextSpan(text: m == null ? 'Atur jadwal tanding' : m.opponent),
                    ],
                  ),
                  style: t.textTheme.h1.copyWith(fontSize: 38),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  m == null
                      ? 'Belum ada laga terjadwal. Buat satu supaya anggota tahu.'
                      : '${fmtDateTime(m.playedAt)}${m.venue == null ? '' : ' • ${m.venue}'}',
                  style: t.textTheme.small,
                ),
                const SizedBox(height: 14),
                if (Auth.canWrite)
                  ShadButton(
                    height: 38,
                    backgroundColor: t.colorScheme.primary,
                    foregroundColor: t.colorScheme.primaryForeground,
                    hoverBackgroundColor: t.colorScheme.primary.withValues(alpha: 0.88),
                    onPressed: () async {
                      if (m == null) {
                        if (await showMatchForm(context)) onChanged();
                      } else {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => MatchDetailPage(match: m)),
                        );
                        await onChanged();
                      }
                    },
                    leading: Icon(m == null ? Icons.add : Icons.scoreboard, size: 16),
                    child: Text(m == null ? 'Buat jadwal' : 'Isi hasil'),
                  )
                else if (m != null)
                  ShadButton.outline(
                    height: 38,
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => MatchDetailPage(match: m)),
                      );
                      await onChanged();
                    },
                    child: const Text('Lihat detail'),
                  ),
              ],
            ),
          ),
    );
  }
}

/// Skor sebagai angka sempit, di depan baris. Sama seperti halaman Tanding.
class _Score extends StatelessWidget {
  const _Score({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    if (match.status != 'finished') {
      return const SizedBox(width: 52, child: Icon(Icons.schedule, size: 17));
    }
    final win = match.goalsFor > match.goalsAgainst;
    final draw = match.goalsFor == match.goalsAgainst;
    return SizedBox(
      width: 52,
      child: Text(
        '${match.goalsFor}–${match.goalsAgainst}',
        style: t.textTheme.h1.copyWith(
          fontSize: 26,
          color: win
              ? t.colorScheme.primary
              : (draw ? t.colorScheme.mutedForeground : AppThemes.bad(context)),
        ),
      ),
    );
  }
}

class _ResultTag extends StatelessWidget {
  const _ResultTag({required this.match});

  final Match match;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    if (match.status != 'finished') {
      return Text(
        match.status == 'ongoing' ? 'BERLANGSUNG' : 'TERJADWAL',
        style: t.textTheme.small.copyWith(
          fontFamily: AppThemes.display,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final win = match.goalsFor > match.goalsAgainst;
    final draw = match.goalsFor == match.goalsAgainst;
    return Text(
      win ? 'MENANG' : (draw ? 'SERI' : 'KALAH'),
      style: TextStyle(
        fontFamily: AppThemes.display,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: win
            ? t.colorScheme.primary
            : (draw ? t.colorScheme.mutedForeground : AppThemes.bad(context)),
      ),
    );
  }
}

/// Aksi cepat dalam kisi tiga kolom yang lebarnya selalu pas: tiap tombol
/// memakai Expanded, jadi tidak ada baris yang menggantung atau meluber di
/// layar 320px.
class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Di bawah 360px tiga kolom memaksa label jadi "Angg…"; dua kolom
        // lebih penting daripada jumlah baris.
        final columns = c.maxWidth < 340 ? 2 : 3;
        final rows = <Widget>[];
        for (var i = 0; i < actions.length; i += columns) {
          final slice = actions.sublist(i, (i + columns).clamp(0, actions.length));
          rows.add(Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Row(
              children: [
                for (var j = 0; j < slice.length; j++) ...[
                  if (j > 0) const SizedBox(width: 8),
                  Expanded(child: slice[j]),
                ],
              ],
            ),
          ));
        }
        return Column(children: rows);
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            border: Border.all(color: t.colorScheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: t.colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
