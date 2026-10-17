import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
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
  final List<ScorerRow> scorers;
  final List<Announcement> news;

  _DashboardData({
    required this.upcoming,
    required this.recent,
    required this.stats,
    required this.members,
    required this.income,
    required this.scorers,
    required this.news,
  });

  static Future<_DashboardData> load() async {
    final results = await Future.wait([
      Match.upcoming(),
      Match.all(limit: 5),
      Match.stats(),
      Member.countActive(),
      Payment.totalForPeriod(periodNow()),
      ScorerRow.top(),
      Announcement.all(),
    ]);
    return _DashboardData(
      upcoming: results[0] as List<Match>,
      recent: results[1] as List<Match>,
      stats: results[2] as List<int>,
      members: results[3] as int,
      income: results[4] as double,
      scorers: results[5] as List<ScorerRow>,
      news: results[6] as List<Announcement>,
    );
  }
}

class _DashboardPageState extends State<DashboardPage> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _DashboardData.load();
  }

  Future<void> _reload() async {
    final f = _DashboardData.load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Halo, Klub! 👋',
      subtitle: fmtDate(DateTime.now()),
      actions: [
        iconAction(context, Icons.refresh, _reload, tooltip: 'Muat ulang'),
      ],
      child: AsyncView<_DashboardData>(
        future: _future,
        onRefresh: _reload,
        builder: (d) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            _NextMatchCard(match: d.upcoming.isNotEmpty ? d.upcoming.first : null, onChanged: _reload),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: StatTile(label: 'Anggota aktif', value: '${d.members}', icon: Icons.groups_rounded)),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Main',
                    value: '${d.stats[0] + d.stats[1] + d.stats[2]}',
                    hint: '${d.stats[0]}M ${d.stats[1]}D ${d.stats[2]}K',
                    icon: Icons.sports_soccer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatTile(
                    label: 'Iuran bulan ini',
                    value: fmtMoney(d.income),
                    icon: Icons.payments_outlined,
                    color: t.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const SectionTitle('Aksi cepat'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickAction(Icons.person_add_alt, 'Anggota', () async {
                  if (await showMemberForm(context)) _reload();
                }),
                _QuickAction(Icons.event, 'Tanding', () async {
                  if (await showMatchForm(context)) _reload();
                }),
                _QuickAction(Icons.payments, 'Iuran', () async {
                  if (await showPaymentForm(context)) _reload();
                }),
                _QuickAction(Icons.stadium_outlined, 'Booking', () async {
                  if (await showBookingForm(context)) _reload();
                }),
                _QuickAction(Icons.campaign_outlined, 'Umumkan', () async {
                  if (await showAnnouncementForm(context)) _reload();
                }),
              ],
            ),
            if (d.news.isNotEmpty) ...[
              const SizedBox(height: 22),
              const SectionTitle('Pengumuman'),
              ...d.news.take(2).map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ShadCard(
                      title: Text(a.title),
                      description: Text('${fmtDate(a.createdAt)}\n${a.body}'),
                    ),
                  )),
            ],
            if (d.scorers.isNotEmpty) ...[
              const SizedBox(height: 22),
              const SectionTitle('Top skor'),
              ShadCard(
                child: Column(
                  children: [
                    for (var i = 0; i < d.scorers.length && i < 5; i++)
                      Padding(
                        padding: EdgeInsets.only(bottom: i == 4 || i == d.scorers.length - 1 ? 0 : 12),
                        child: Row(
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: i == 0 ? t.colorScheme.primary : t.colorScheme.muted,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: i == 0 ? t.colorScheme.primaryForeground : t.colorScheme.mutedForeground,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(d.scorers[i].name)),
                            ShadBadge.outline(child: Text('${d.scorers[i].goals} gol')),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            SectionTitle(
              'Pertandingan terakhir',
              action: TextButton(
                onPressed: () {},
                child: const Text('Lihat di tab Tanding'),
              ),
            ),
            if (d.recent.isEmpty)
              Text('Belum ada pertandingan.', style: t.textTheme.muted)
            else
              ...d.recent.take(3).map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.colorScheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.colorScheme.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            m.status == 'finished'
                                ? (m.goalsFor > m.goalsAgainst ? Icons.emoji_events : (m.goalsFor == m.goalsAgainst ? Icons.remove : Icons.sentiment_dissatisfied))
                                : Icons.schedule,
                            size: 18,
                            color: m.status == 'finished'
                                ? (m.goalsFor > m.goalsAgainst ? t.colorScheme.primary : t.colorScheme.mutedForeground)
                                : t.colorScheme.mutedForeground,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('vs ${m.opponent}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                Text(fmtDate(m.playedAt), style: t.textTheme.small),
                              ],
                            ),
                          ),
                          Text(m.resultLabel, style: t.textTheme.small),
                        ],
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}

class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({required this.match, required this.onChanged});

  final Match? match;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final m = match;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.colorScheme.primary, const Color(0xFF15803D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            m == null ? 'BELUM ADA JADWAL' : 'JADWAL BERIKUTNYA',
            style: TextStyle(
              color: t.colorScheme.primaryForeground.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            m == null ? 'Ayo atur jadwal tanding' : 'vs ${m.opponent}',
            style: TextStyle(
              color: t.colorScheme.primaryForeground,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (m != null) ...[
            const SizedBox(height: 6),
            Text(
              '${fmtDateTime(m.playedAt)}${m.venue != null ? ' • ${m.venue}' : ''}',
              style: TextStyle(color: t.colorScheme.primaryForeground.withValues(alpha: 0.9), fontSize: 13),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: () async {
                  if (m == null) {
                    if (await showMatchForm(context)) onChanged();
                  } else {
                    if (await showFinishMatch(context, m)) onChanged();
                  }
                },
                icon: Icon(m == null ? Icons.add : Icons.scoreboard, size: 16),
                label: Text(m == null ? 'Buat jadwal' : 'Isi hasil'),
                style: FilledButton.styleFrom(
                  backgroundColor: t.colorScheme.primaryForeground,
                  foregroundColor: t.colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (m != null)
                ShadBadge.secondary(child: Text(m.isHome ? 'Kandang' : 'Tandang')),
            ],
          ),
        ],
      ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.colorScheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.colorScheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: t.colorScheme.primary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
