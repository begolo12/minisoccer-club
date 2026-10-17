import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'widgets.dart';

/// Turnamen internal: 4 tim, round-robin, semua laga dalam satu blok waktu
/// (default 6 laga × 20 menit = 2 jam), plus klasemen grup.
class TournamentsPage extends StatefulWidget {
  const TournamentsPage({super.key});

  @override
  State<TournamentsPage> createState() => _TournamentsPageState();
}

class _TournamentsPageState extends State<TournamentsPage> {
  late Future<List<Tournament>> _future;

  @override
  void initState() {
    super.initState();
    _future = Tournament.all();
  }

  Future<void> _reload() async {
    final f = Tournament.all();
    setState(() => _future = f);
    await f;
  }

  Future<void> _create() async {
    if (await showTournamentForm(context)) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Turnamen internal',
      subtitle: '4 tim • semua bertemu semua • klasemen grup',
      actions: [iconAction(context, Icons.add, _create, tooltip: 'Turnamen baru')],
      child: AsyncView<List<Tournament>>(
        future: _future,
        onRefresh: _reload,
        builder: (items) {
          if (items.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              EmptyState(
                icon: Icons.emoji_events_outlined,
                title: 'Belum ada turnamen',
                message: 'Buat turnamen 4 tim. Jadwal, pembagian tim, dan '
                    'klasemen dibuat otomatis.',
                actionLabel: 'Buat turnamen',
                onAction: _create,
              ),
            ]);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              for (final t in items)
                _TournamentTile(tournament: t, onChanged: _reload),
            ],
          );
        },
      ),
    );
  }
}

class _TournamentTile extends StatelessWidget {
  const _TournamentTile({required this.tournament, required this.onChanged});

  final Tournament tournament;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final running = tournament.status == 'running';
    return OilCard(
      highlight: running,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TournamentDetailPage(tournament: tournament)),
      ).then((_) => onChanged()),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: t.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.emoji_events_outlined, size: 18, color: t.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tournament.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Pill(
                      Tournament.statusLabels[tournament.status] ?? tournament.status,
                      color: running ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        [
                          fmtDateTime(tournament.startsAt),
                          if (tournament.venue?.isNotEmpty ?? false) tournament.venue!,
                        ].join(' • '),
                        style: t.textTheme.small,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: t.colorScheme.mutedForeground),
        ],
      ),
    );
  }
}

// ---------- Detail ----------

class _Data {
  _Data({required this.standings, required this.matches, required this.teams, required this.players});

  final List<Standing> standings;
  final List<TournamentMatch> matches;
  final List<Team> teams;
  final Map<int, List<Member>> players;

  Team? team(int id) {
    for (final t in teams) {
      if (t.id == id) return t;
    }
    return null;
  }

  String name(int id) => team(id)?.name ?? '—';
}

class TournamentDetailPage extends StatefulWidget {
  const TournamentDetailPage({super.key, required this.tournament});

  final Tournament tournament;

  @override
  State<TournamentDetailPage> createState() => _TournamentDetailPageState();
}

class _TournamentDetailPageState extends State<TournamentDetailPage> {
  late Future<_Data> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Data> _load() async {
    final id = widget.tournament.id;
    final results = await Future.wait([
      TournamentMatch.forTournament(id),
      Team.forTournament(id),
      Team.players(id),
    ]);
    final matches = results[0] as List<TournamentMatch>;
    final teams = results[1] as List<Team>;
    return _Data(
      standings: Standing.compute(teams, matches),
      matches: matches,
      teams: teams,
      players: results[2] as Map<int, List<Member>>,
    );
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Hapus turnamen?', 'Semua tim, jadwal, dan skor ikut terhapus.')) return;
    await Tournament.delete(widget.tournament.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: widget.tournament.name,
      subtitle: [
        fmtDateTime(widget.tournament.startsAt),
        if (widget.tournament.venue?.isNotEmpty ?? false) widget.tournament.venue!,
      ].join(' • '),
      actions: [iconAction(context, Icons.delete_outline, _delete, tooltip: 'Hapus')],
      child: AsyncView<_Data>(
        future: _future,
        onRefresh: _reload,
        builder: (d) {
          final last = d.matches.isEmpty ? null : d.matches.last.kickoff;
          final end = last?.add(Duration(minutes: widget.tournament.matchMinutes));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                '${d.teams.length} tim • ${d.matches.length} laga • '
                '${widget.tournament.matchMinutes} menit/laga'
                '${end == null ? '' : ' • selesai ${fmtTime(end)}'}',
                style: ShadTheme.of(context).textTheme.small,
              ),
              const SizedBox(height: 16),
              const SectionTitle('Klasemen'),
              _StandingsTable(standings: d.standings),
              const SizedBox(height: 18),
              const SectionTitle('Jadwal'),
              for (final m in d.matches)
                _MatchTile(match: m, data: d, onChanged: _reload),
              const SizedBox(height: 18),
              SectionTitle(
                'Pembagian tim',
                action: TextButton(
                  onPressed: () async {
                    if (!await confirm(context, 'Bagi ulang tim?',
                        'Semua pemain dibagi ulang secara acak dan merata.')) {
                      return;
                    }
                    await Tournament.autoAssign(widget.tournament.id);
                    _reload();
                  },
                  child: const Text('Acak ulang'),
                ),
              ),
              for (final team in d.teams)
                _TeamCard(
                  team: team,
                  players: d.players[team.id] ?? const [],
                  onChanged: _reload,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({required this.standings});

  final List<Standing> standings;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final head = t.textTheme.small.copyWith(fontWeight: FontWeight.w700);
    final cell = t.textTheme.small;

    return OilCard(
      padding: EdgeInsets.zero,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 42,
          dataRowMaxHeight: 46,
          horizontalMargin: 12,
          columnSpacing: 18,
          headingTextStyle: head,
          dataTextStyle: cell,
          columns: const [
            DataColumn(label: Text('#'), numeric: true),
            DataColumn(label: Text('Tim')),
            DataColumn(label: Text('M'), numeric: true),
            DataColumn(label: Text('W'), numeric: true),
            DataColumn(label: Text('D'), numeric: true),
            DataColumn(label: Text('L'), numeric: true),
            DataColumn(label: Text('GM'), numeric: true),
            DataColumn(label: Text('GK'), numeric: true),
            DataColumn(label: Text('SG'), numeric: true),
            DataColumn(label: Text('Poin'), numeric: true),
          ],
          rows: [
            for (var i = 0; i < standings.length; i++)
              DataRow(
                color: i == 0
                    ? WidgetStatePropertyAll(t.colorScheme.primary.withValues(alpha: 0.08))
                    : null,
                cells: [
                DataCell(Text('${i + 1}',
                    style: cell.copyWith(
                      fontWeight: FontWeight.w700,
                      color: i == 0 ? t.colorScheme.primary : null,
                    ))),
                DataCell(Row(children: [
                  if (i == 0) ...[
                    Icon(Icons.emoji_events, size: 13, color: t.colorScheme.primary),
                    const SizedBox(width: 4),
                  ],
                  Text(standings[i].name,
                      style: cell.copyWith(fontWeight: i == 0 ? FontWeight.w700 : null)),
                ])),
                DataCell(Text('${standings[i].played}')),
                DataCell(Text('${standings[i].won}')),
                DataCell(Text('${standings[i].drawn}')),
                DataCell(Text('${standings[i].lost}')),
                DataCell(Text('${standings[i].goalsFor}')),
                DataCell(Text('${standings[i].goalsAgainst}')),
                DataCell(Text('${standings[i].goalDiff}')),
                DataCell(Text('${standings[i].points}',
                    style: cell.copyWith(
                      fontWeight: FontWeight.w800,
                      color: t.colorScheme.primary,
                    ))),
              ]),
          ],
        ),
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.data, required this.onChanged});

  final TournamentMatch match;
  final _Data data;
  final Future<void> Function() onChanged;

  Future<void> _openScore(BuildContext context) async {
    final action = await showScoreForm(
      context,
      title: '${data.name(match.homeTeamId)} vs ${data.name(match.awayTeamId)}',
      subtitle: 'Babak ${match.round} • ${fmtTime(match.kickoff)}',
      home: match.scoreHome,
      away: match.scoreAway,
      canReset: match.done,
    );
    if (action == 'reset') {
      await match.clearScore();
    } else if (action is (int, int)) {
      await match.saveScore(action.$1, action.$2);
    } else {
      return;
    }
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final done = match.done;
    final homeWin = done && match.scoreHome! > match.scoreAway!;
    final awayWin = done && match.scoreAway! > match.scoreHome!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _openScore(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: t.colorScheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.colorScheme.border),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fmtTime(match.kickoff),
                          style: t.textTheme.small.copyWith(fontWeight: FontWeight.w700)),
                      Text('B${match.round}', style: t.textTheme.small),
                    ],
                  ),
                ),
                Expanded(
                  child: Text(
                    data.name(match.homeTeamId),
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: homeWin ? FontWeight.w800 : FontWeight.w500,
                      color: homeWin ? t.colorScheme.primary : null,
                    ),
                  ),
                ),
                Container(
                  width: 58,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done ? t.colorScheme.primary.withValues(alpha: 0.14) : t.colorScheme.muted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    done ? '${match.scoreHome} - ${match.scoreAway}' : 'vs',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: done ? 14 : 11,
                      color: done ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    data.name(match.awayTeamId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: awayWin ? FontWeight.w800 : FontWeight.w500,
                      color: awayWin ? t.colorScheme.primary : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.team, required this.players, required this.onChanged});

  final Team team;
  final List<Member> players;
  final Future<void> Function() onChanged;

  Future<void> _rename(BuildContext context) async {
    final c = TextEditingController(text: team.name);
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: const Text('Nama tim'),
        actions: [
          ShadButton.outline(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ShadButton(
            onPressed: () async {
              final v = c.text.trim();
              if (v.isEmpty) return;
              await Team.rename(team.id, v);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('Simpan'),
          ),
        ],
        child: ShadInput(controller: c, placeholder: const Text('Nama tim')),
      ),
    );
    if (ok ?? false) await onChanged();
  }

  Future<void> _addPlayer(BuildContext context) async {
    final all = await Member.all(activeOnly: true);
    final taken = players.map((p) => p.id).toSet();
    final free = all.where((m) => !taken.contains(m.id)).toList();
    if (free.isEmpty) {
      toast(context, 'Semua pemain aktif sudah masuk tim');
      return;
    }
    final picked = await showShadDialog<Member>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: Text('Tambah ke ${team.name}'),
        actions: [
          ShadButton.outline(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
        child: SizedBox(
          height: 320,
          width: 320,
          child: ListView(
            children: [
              for (final m in free)
                ListTile(
                  dense: true,
                  title: Text(m.name),
                  subtitle: Text('${m.position}${m.jersey == null ? '' : ' • #${m.jersey}'}'),
                  onTap: () => Navigator.pop(ctx, m),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await Team.addPlayer(team.id, picked.id);
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return OilCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _rename(context),
                    child: Row(children: [
                      Text(team.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      Icon(Icons.edit_outlined, size: 12, color: t.colorScheme.mutedForeground),
                    ]),
                  ),
                ),
                Text('${players.length} pemain', style: t.textTheme.small),
                IconButton(
                  onPressed: () => _addPlayer(context),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  tooltip: 'Tambah pemain',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (players.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Belum ada pemain', style: t.textTheme.small),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in players)
                    InputChip(
                      label: Text(p.name, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onDeleted: () async {
                        await Team.removePlayer(team.id, p.id);
                        await onChanged();
                      },
                    ),
                ],
              ),
          ],
        ),
    );
  }
}

// ---------- Form ----------

/// Form buat turnamen. Return true kalau berhasil dibuat.
Future<bool> showTournamentForm(BuildContext context) async {
  final name = TextEditingController(
    text: 'Turnamen Internal ${fmtDate(DateTime.now())}',
  );
  final venue = TextEditingController();
  final minutes = TextEditingController(text: '20');
  final breakMin = TextEditingController(text: '0');
  var teams = 4;
  var date = DateTime.now().add(const Duration(days: 1));
  var time = const TimeOfDay(hour: 20, minute: 0);
  var saving = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final per = int.tryParse(minutes.text) ?? 20;
        final rest = int.tryParse(breakMin.text) ?? 0;
        final matches = teams * (teams - 1) ~/ 2;
        final total = matches * (per + rest);

        Future<void> save() async {
          if (name.text.trim().isEmpty) {
            toast(ctx, 'Nama turnamen tidak boleh kosong');
            return;
          }
          if (teams < 2) {
            toast(ctx, 'Minimal 2 tim');
            return;
          }
          setLocal(() => saving = true);
          try {
            final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
            await Tournament.create(
              name: name.text.trim(),
              venue: venue.text.trim().isEmpty ? null : venue.text.trim(),
              startsAt: start,
              teamCount: teams,
              matchMinutes: per,
              breakMinutes: rest,
            );
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal buat turnamen: $e');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: const Text('Turnamen baru'),
          description: Text('$teams tim • $matches laga • '
              '${total ~/ 60}j ${total % 60}m total'),
          actions: [
            ShadButton.outline(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ShadButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Buat'),
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShadInput(controller: name, placeholder: const Text('Nama turnamen')),
                const SizedBox(height: 10),
                ShadInput(controller: venue, placeholder: const Text('Lokasi (opsional)')),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: date,
                            firstDate: DateTime.now().subtract(const Duration(days: 30)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setLocal(() => date = picked);
                        },
                        icon: const Icon(Icons.event, size: 16),
                        label: Text(fmtDate(date)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showTimePicker(context: ctx, initialTime: time);
                          if (picked != null) setLocal(() => time = picked);
                        },
                        icon: const Icon(Icons.schedule, size: 16),
                        label: Text(time.format(ctx)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ShadInput(
                        controller: minutes,
                        placeholder: const Text('Menit/laga'),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setLocal(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ShadInput(
                        controller: breakMin,
                        placeholder: const Text('Jeda (menit)'),
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setLocal(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ShadSelect<int>(
                  placeholder: const Text('Jumlah tim'),
                  initialValue: teams,
                  options: const [2, 3, 4, 5, 6]
                      .map((n) => ShadOption(value: n, child: Text('$n tim')))
                      .toList(),
                  selectedOptionBuilder: (c, v) => Text('$v tim'),
                  onChanged: (v) => setLocal(() => teams = v ?? 4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Pemain aktif dibagi otomatis ke tim (acak, merata). '
                  'Bisa diubah di halaman turnamen.',
                  style: ShadTheme.of(ctx).textTheme.small,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  return ok ?? false;
}

/// Dialog skor. Return `(home, away)`, string `'reset'`, atau null kalau batal.
Future<Object?> showScoreForm(
  BuildContext context, {
  required String title,
  required String subtitle,
  int? home,
  int? away,
  bool canReset = false,
}) async {
  final h = TextEditingController(text: home?.toString() ?? '');
  final a = TextEditingController(text: away?.toString() ?? '');

  final result = await showShadDialog<Object>(
    context: context,
    builder: (ctx) => ShadDialog(
      title: Text(title),
      description: Text(subtitle),
      actions: [
        if (canReset)
          ShadButton.ghost(
            onPressed: () => Navigator.pop(ctx, 'reset'),
            child: const Text('Reset'),
          ),
        ShadButton.outline(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        ShadButton(
          onPressed: () => Navigator.pop(
            ctx,
            (int.tryParse(h.text) ?? 0, int.tryParse(a.text) ?? 0),
          ),
          child: const Text('Simpan'),
        ),
      ],
      child: Row(
        children: [
          Expanded(
            child: ShadInput(
              controller: h,
              placeholder: const Text('0'),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('-', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: ShadInput(
              controller: a,
              placeholder: const Text('0'),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
  );
  if (result is (int, int) || result == 'reset') return result;
  return null;
}
