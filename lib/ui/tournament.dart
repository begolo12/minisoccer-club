import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'theme.dart';
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
      subtitle: 'Semua bertemu semua • klasemen grup',
      actions: [
        if (Auth.canWrite) iconAction(context, Icons.add, _create, tooltip: 'Turnamen baru'),
      ],
      child: AsyncView<List<Tournament>>(
        future: _future,
        onRefresh: _reload,
        builder: (items) {
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                EmptyState(
                  icon: Icons.emoji_events_outlined,
                  title: 'Belum ada turnamen',
                  message: 'Buat turnamen 4 tim. Jadwal, pembagian tim, dan '
                      'klasemen dibuat otomatis.',
                  actionLabel: Auth.canWrite ? 'Buat turnamen' : null,
                  onAction: Auth.canWrite ? _create : null,
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
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
    return RowItem(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TournamentDetailPage(tournament: tournament)),
      ).then((_) => onChanged()),
      leading: Icon(Icons.emoji_events_outlined, size: 18, color: t.colorScheme.primary),
      title: tournament.name,
      subtitle: [
        Tournament.statusLabels[tournament.status] ?? tournament.status,
        fmtDateTime(tournament.startsAt),
        if (tournament.venue?.isNotEmpty ?? false) tournament.venue!,
      ].join(' • '),
      trailing: Icon(Icons.chevron_right, size: 18, color: t.colorScheme.mutedForeground),
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
    if (!mounted) return;
    if (!await attempt(context, () => Tournament.delete(widget.tournament.id), fail: 'Gagal menghapus')) {
      return;
    }
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
      actions: [
        if (Auth.canWrite) iconAction(context, Icons.delete_outline, _delete, tooltip: 'Hapus'),
      ],
      child: AsyncView<_Data>(
        future: _future,
        onRefresh: _reload,
        builder: (d) {
          final last = d.matches.isEmpty ? null : d.matches.last.kickoff;
          final end = last?.add(Duration(minutes: widget.tournament.matchMinutes));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
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
                action: Auth.canWrite
                    ? TextButton(
                        onPressed: () async {
                          if (!await confirm(context, 'Bagi ulang tim?',
                              'Semua pemain dibagi ulang secara acak dan merata.')) {
                            return;
                          }
                          if (!context.mounted) return;
                          if (await attempt(context,
                              () => Tournament.autoAssign(widget.tournament.id),
                              fail: 'Gagal membagi tim')) {
                            _reload();
                          }
                        },
                        child: const Text('Acak ulang'),
                      )
                    : null,
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
    final head = t.textTheme.h4.copyWith(fontSize: 11, letterSpacing: 0.9);
    final cell = t.textTheme.table;
    // Di HP kolom ringkas (M, SG, Poin); di layar lebar semua kolom muat.
    final wide = MediaQuery.sizeOf(context).width >= 640;

    Widget num(String text, {TextStyle? style}) => Text(
          text,
          textAlign: TextAlign.right,
          style: (style ?? cell).copyWith(fontFeatures: AppThemes.tabular),
        );

    Widget headCell(String text) => Text(text.toUpperCase(), style: head);

    final cols = wide
        ? ['#', 'Tim', 'M', 'W', 'D', 'L', 'GM', 'GK', 'SG', 'Poin']
        : ['#', 'Tim', 'M', 'SG', 'Poin'];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.colorScheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.colorScheme.border)),
            ),
            child: Row(
              children: [
                SizedBox(width: 22, child: headCell(cols[0])),
                Expanded(child: headCell(cols[1])),
                for (final c in cols.skip(2))
                  SizedBox(width: 42, child: Align(alignment: Alignment.centerRight, child: headCell(c))),
              ],
            ),
          ),
          for (var i = 0; i < standings.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: i == 0 ? t.colorScheme.primary.withValues(alpha: 0.07) : null,
                border: i == standings.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: t.colorScheme.border.withValues(alpha: 0.6))),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${i + 1}',
                      style: cell.copyWith(
                        fontFamily: AppThemes.display,
                        fontSize: 15,
                        color: i == 0 ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      standings[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: cell.copyWith(fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w500),
                    ),
                  ),
                  SizedBox(width: 42, child: Align(alignment: Alignment.centerRight, child: num('${standings[i].played}'))),
                  if (wide) ...[
                    SizedBox(width: 42, child: Align(alignment: Alignment.centerRight, child: num('${standings[i].won}'))),
                    SizedBox(width: 42, child: Align(alignment: Alignment.centerRight, child: num('${standings[i].drawn}'))),
                    SizedBox(width: 42, child: Align(alignment: Alignment.centerRight, child: num('${standings[i].lost}'))),
                    SizedBox(width: 42, child: Align(alignment: Alignment.centerRight, child: num('${standings[i].goalsFor}'))),
                    SizedBox(width: 42, child: Align(alignment: Alignment.centerRight, child: num('${standings[i].goalsAgainst}'))),
                  ],
                  SizedBox(
                    width: 42,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: num(
                        '${standings[i].goalDiff}',
                        style: cell.copyWith(
                          color: standings[i].goalDiff >= 0
                              ? t.colorScheme.foreground
                              : t.colorScheme.mutedForeground,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${standings[i].points}',
                        style: cell.copyWith(
                          fontFamily: AppThemes.display,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: t.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
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
    if (!context.mounted) return;
    if (action == 'reset') {
      await attempt(context, () => match.clearScore(), fail: 'Gagal menyimpan skor');
    } else if (action is (int, int)) {
      await attempt(context, () => match.saveScore(action.$1, action.$2),
          fail: 'Gagal menyimpan skor');
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: Auth.canWrite ? () => _openScore(context) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.colorScheme.border.withValues(alpha: 0.7))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 46,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fmtTime(match.kickoff),
                      style: t.textTheme.table.copyWith(fontWeight: FontWeight.w600),
                    ),
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
                    fontSize: 13.5,
                    fontWeight: homeWin ? FontWeight.w600 : FontWeight.w500,
                    color: homeWin ? t.colorScheme.primary : t.colorScheme.foreground,
                  ),
                ),
              ),
              SizedBox(
                width: 62,
                child: Text(
                  done ? '${match.scoreHome}–${match.scoreAway}' : 'vs',
                  textAlign: TextAlign.center,
                  style: done
                      ? t.textTheme.h2.copyWith(
                          fontSize: 20,
                          color: homeWin || awayWin ? t.colorScheme.foreground : t.colorScheme.mutedForeground,
                        )
                      : t.textTheme.small,
                ),
              ),
              Expanded(
                child: Text(
                  data.name(match.awayTeamId),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: awayWin ? FontWeight.w600 : FontWeight.w500,
                    color: awayWin ? t.colorScheme.primary : t.colorScheme.foreground,
                  ),
                ),
              ),
            ],
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
              if (await attempt(ctx, () => Team.rename(team.id, v), fail: 'Gagal mengganti nama')) {
                if (ctx.mounted) Navigator.pop(ctx, true);
              }
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
    if (!context.mounted) return;
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
    if (!context.mounted) return;
    if (await attempt(context, () => Team.addPlayer(team.id, picked.id), fail: 'Gagal menambah pemain')) {
      await onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: Auth.canWrite ? () => _rename(context) : null,
                    child: Row(children: [
                      Flexible(
                        child: Text(
                          team.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (Auth.canWrite) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.edit_outlined, size: 12, color: t.colorScheme.mutedForeground),
                      ],
                    ]),
                  ),
                ),
                Text('${players.length} pemain', style: t.textTheme.small),
                if (Auth.canWrite)
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
                      onDeleted: Auth.canWrite
                          ? () async {
                              if (await attempt(context,
                                  () => Team.removePlayer(team.id, p.id),
                                  fail: 'Gagal mengeluarkan pemain')) {
                                await onChanged();
                              }
                            }
                          : null,
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
