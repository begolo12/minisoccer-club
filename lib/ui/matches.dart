import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> {
  late Future<(List<Match>, List<int>)> _future;

  Future<(List<Match>, List<int>)> _load() async {
    final r = await Future.wait([Match.all(), Match.stats()]);
    return (r[0] as List<Match>, r[1] as List<int>);
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Tanding',
      subtitle: 'Jadwal & hasil pertandingan',
      actions: [
        iconAction(context, Icons.add, () async {
          if (await showMatchForm(context)) _reload();
        }, tooltip: 'Jadwal baru'),
      ],
      child: AsyncView<(List<Match>, List<int>)>(
        future: _future,
        onRefresh: _reload,
        builder: (data) {
          final matches = data.$1;
          final stats = data.$2;
          if (matches.isEmpty) {
            return ListView(children: [
              const SizedBox(height: 80),
              EmptyState(
                icon: Icons.sports_soccer_outlined,
                title: 'Belum ada pertandingan',
                message: 'Buat jadwal tanding pertama.',
                actionLabel: 'Buat jadwal',
                onAction: () async {
                  if (await showMatchForm(context)) _reload();
                },
              ),
            ]);
          }
          final scheduled = matches.where((m) => m.status == 'scheduled').toList();
          final finished = matches.where((m) => m.status == 'finished').toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: t.colorScheme.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Menang',
                        value: '${stats[0]}',
                        color: t.colorScheme.primary,
                      ),
                    ),
                    _rule(t),
                    Expanded(child: StatTile(label: 'Seri', value: '${stats[1]}')),
                    _rule(t),
                    Expanded(
                      child: StatTile(
                        label: 'Kalah',
                        value: '${stats[2]}',
                        color: AppThemes.bad(context),
                      ),
                    ),
                    _rule(t),
                    Expanded(child: StatTile(label: 'Gol', value: '${stats[3]}')),
                    _rule(t),
                    Expanded(child: StatTile(label: 'Bobol', value: '${stats[4]}')),
                  ],
                ),
              ),
              if (scheduled.isNotEmpty) ...[
                const SectionTitle('Akan datang'),
                ...scheduled.map((m) => _MatchTile(match: m, onChanged: _reload)),
                const SizedBox(height: 18),
              ],
              if (finished.isNotEmpty) ...[
                const SectionTitle('Selesai'),
                ...finished.map((m) => _MatchTile(match: m, onChanged: _reload)),
              ],
            ],
          );
        },
      ),
    );
  }
}

Widget _rule(ShadThemeData t) => Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: t.colorScheme.border,
    );

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.onChanged});

  final Match match;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final finished = match.status == 'finished';
    final win = finished && match.goalsFor > match.goalsAgainst;
    final draw = finished && match.goalsFor == match.goalsAgainst;

    return RowItem(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MatchDetailPage(match: match)),
      ).then((_) => onChanged()),
      leading: finished
          ? SizedBox(
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
            )
          : const SizedBox(
              width: 52,
              child: Icon(Icons.schedule, size: 18),
            ),
      title: 'vs ${match.opponent}',
      subtitle: '${fmtDateTime(match.playedAt)}${match.venue != null ? " • ${match.venue}" : ""}',
      trailing: Text(
        finished ? (win ? 'MENANG' : (draw ? 'SERI' : 'KALAH')) : (match.isHome ? 'KANDANG' : 'TANDANG'),
        style: TextStyle(
          fontFamily: AppThemes.display,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
          color: finished
              ? (win ? t.colorScheme.primary : (draw ? t.colorScheme.mutedForeground : AppThemes.bad(context)))
              : t.colorScheme.mutedForeground,
        ),
      ),
    );
  }
}

class MatchDetailPage extends StatefulWidget {
  const MatchDetailPage({super.key, required this.match});

  final Match match;

  @override
  State<MatchDetailPage> createState() => _MatchDetailPageState();
}

class _MatchDetailPageState extends State<MatchDetailPage> {
  late Future<List<MatchEvent>> _events;
  late Future<List<MatchSession>> _sessions;

  @override
  void initState() {
    super.initState();
    _events = MatchEvent.forMatch(widget.match.id);
    _sessions = MatchSession.forMatch(widget.match.id);
  }

  Future<void> _reload() async {
    final e = MatchEvent.forMatch(widget.match.id);
    final s = MatchSession.forMatch(widget.match.id);
    setState(() {
      _events = e;
      _sessions = s;
    });
    await Future.wait([e, s]);
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final m = widget.match;
    final finished = m.status == 'finished';
    return PageScaffold(
      title: 'vs ${m.opponent}',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: t.colorScheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.colorScheme.border),
            ),
            child: Column(
              children: [
                Text('${fmtDateTime(m.playedAt)}${m.venue != null ? " • ${m.venue}" : ""}',
                    textAlign: TextAlign.center, style: t.textTheme.small),
                const SizedBox(height: 10),
                Text(
                  finished ? '${m.goalsFor}–${m.goalsAgainst}' : 'VS',
                  style: t.textTheme.h1Large.copyWith(
                    fontSize: 56,
                    color: finished
                        ? (m.goalsFor > m.goalsAgainst
                            ? t.colorScheme.primary
                            : (m.goalsFor == m.goalsAgainst
                                ? t.colorScheme.mutedForeground
                                : AppThemes.bad(context)))
                        : t.colorScheme.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  finished
                      ? (m.goalsFor > m.goalsAgainst
                          ? 'Menang'
                          : (m.goalsFor == m.goalsAgainst ? 'Seri' : 'Kalah'))
                      : 'Belum dimainkan',
                  style: t.textTheme.muted,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ShadButton.outline(
                        onPressed: () async {
                          if (await showFinishMatch(context, m)) {
                            if (!context.mounted) return;
                            Navigator.pop(context, true);
                          }
                        },
                        child: Text(finished ? 'Ubah skor' : 'Isi hasil'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    iconAction(context, Icons.delete_outline, () async {
                      if (await confirm(context, 'Hapus pertandingan?', 'Semua catatan gol ikut terhapus.')) {
                        await Match.delete(m.id);
                        if (context.mounted) Navigator.pop(context, true);
                      }
                    }, tooltip: 'Hapus pertandingan'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionTitle(
            'Sesi & pemenang',
            action: ShadButton.ghost(
              size: ShadButtonSize.sm,
              onPressed: () async {
                if (await _sessionForm(context)) _reload();
              },
              child: const Row(
                children: [Icon(Icons.add, size: 14), SizedBox(width: 4), Text('Sesi')],
              ),
            ),
          ),
          AsyncView<List<MatchSession>>(
            future: _sessions,
            onRefresh: _reload,
            builder: (sessions) {
              if (sessions.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text('Belum ada sesi. Skor laga = jumlah semua sesi.',
                        textAlign: TextAlign.center, style: t.textTheme.muted),
                  ),
                );
              }
              final won = sessions.where((s) => s.winner == 'home').length;
              final lost = sessions.where((s) => s.winner == 'away').length;
              final drew = sessions.where((s) => s.winner == 'draw').length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Pill('$won menang', color: t.colorScheme.primary),
                      const SizedBox(width: 12),
                      Pill('$drew seri'),
                      const SizedBox(width: 12),
                      Pill('$lost kalah', color: AppThemes.bad(context)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final s in sessions)
                    RowItem(
                      onTap: () async {
                        if (await _sessionForm(context, session: s)) _reload();
                      },
                      leading: Text('S${s.sessionNo}', style: t.textTheme.h4.copyWith(fontSize: 12)),
                      title: '${s.scoreHome}–${s.scoreAway}',
                      trailing: Text(
                        (MatchSession.winnerLabels[s.winner] ?? s.winner).toUpperCase(),
                        style: TextStyle(
                          fontFamily: AppThemes.display,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                          color: s.winner == 'home'
                              ? t.colorScheme.primary
                              : (s.winner == 'away' ? AppThemes.bad(context) : t.colorScheme.mutedForeground),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          SectionTitle(
            'Catatan pertandingan',
            action: ShadButton.ghost(
              size: ShadButtonSize.sm,
              onPressed: () async {
                if (await _addEvent(context)) _reload();
              },
              child: const Row(
                children: [Icon(Icons.add, size: 14), SizedBox(width: 4), Text('Tambah')],
              ),
            ),
          ),
          AsyncView<List<MatchEvent>>(
            future: _events,
            onRefresh: _reload,
            builder: (events) {
              if (events.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text('Belum ada gol/assist/kartu.', style: t.textTheme.muted),
                  ),
                );
              }
              return Column(
                children: [
                  for (final e in events)
                    RowItem(
                      leading: Icon(_icon(e.type), size: 16, color: _color(e.type, t)),
                      title: e.memberName,
                      subtitle: MatchEvent.typeLabels[e.type] ?? e.type,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (e.minute != null)
                            Text("${e.minute}'", style: t.textTheme.table),
                          const SizedBox(width: 8),
                          iconAction(context, Icons.close, () async {
                            await MatchEvent.delete(e.id);
                            _reload();
                          }, tooltip: 'Hapus catatan'),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  IconData _icon(String type) => switch (type) {
        'goal' => Icons.sports_soccer,
        'assist' => Icons.handshake_outlined,
        'yellow' => Icons.square_rounded,
        _ => Icons.square_rounded,
      };

  Color _color(String type, ShadThemeData t) => switch (type) {
        'goal' => t.colorScheme.primary,
        'yellow' => const Color(0xFFFACC15),
        'red' => t.colorScheme.destructive,
        _ => t.colorScheme.mutedForeground,
      };

  Future<bool> _sessionForm(BuildContext context, {MatchSession? session}) async {
    final existing = await MatchSession.forMatch(widget.match.id);
    if (!context.mounted) return false;
    final nextNo = session?.sessionNo ??
        (existing.isEmpty
            ? 1
            : existing.map((s) => s.sessionNo).reduce((a, b) => a > b ? a : b) + 1);
    final home = TextEditingController(text: '${session?.scoreHome ?? 0}');
    final away = TextEditingController(text: '${session?.scoreAway ?? 0}');
    var saving = false;

    final ok = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ShadDialog(
          title: Text('Sesi $nextNo'),
          description: Text(session == null
              ? 'Skor sesi ini. Pemenang dihitung otomatis.'
              : 'Ubah skor sesi. Pemenang dihitung ulang.'),
          actions: [
            if (session != null)
              ShadButton.destructive(
                onPressed: saving
                    ? null
                    : () async {
                        setLocal(() => saving = true);
                        await MatchSession.delete(session.id, widget.match.id);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      },
                child: const Text('Hapus'),
              ),
            ShadButton.outline(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ShadButton(
              onPressed: saving
                  ? null
                  : () async {
                      setLocal(() => saving = true);
                      try {
                        await MatchSession.save(
                          id: session?.id,
                          matchId: widget.match.id,
                          sessionNo: nextNo,
                          home: int.tryParse(home.text) ?? 0,
                          away: int.tryParse(away.text) ?? 0,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) {
                          setLocal(() => saving = false);
                          toast(ctx, 'Gagal simpan: $e');
                        }
                      }
                    },
              child: const Text('Simpan'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ShadInput(
                      controller: home,
                      placeholder: const Text('Skor kita'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('—'),
                  ),
                  Expanded(
                    child: ShadInput(
                      controller: away,
                      placeholder: const Text('Skor lawan'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return ok ?? false;
  }

  Future<bool> _addEvent(BuildContext context) async {
    final members = await Member.all();
    if (!context.mounted) return false;
    if (members.isEmpty) {
      toast(context, 'Tambah anggota dulu');
      return false;
    }
    var memberId = members.first.id;
    var type = 'goal';
    final minute = TextEditingController();
    var saving = false;

    final ok = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ShadDialog(
          title: const Text('Catatan baru'),
          actions: [
            ShadButton.outline(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            ShadButton(
              onPressed: saving
                  ? null
                  : () async {
                      setLocal(() => saving = true);
                      try {
                        await MatchEvent.insert(
                          matchId: widget.match.id,
                          memberId: memberId,
                          minute: int.tryParse(minute.text),
                          type: type,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) toast(ctx, 'Gagal: $e');
                      } finally {
                        if (ctx.mounted) setLocal(() => saving = false);
                      }
                    },
              child: const Text('Simpan'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadSelect<int>(
                placeholder: const Text('Pemain'),
                initialValue: memberId,
                options: members.map((m) => ShadOption(value: m.id, child: Text(m.name))).toList(),
                selectedOptionBuilder: (c, v) => Text(members.firstWhere((m) => m.id == v).name),
                onChanged: (v) => setLocal(() => memberId = v ?? memberId),
              ),
              const SizedBox(height: 10),
              ShadSelect<String>(
                placeholder: const Text('Jenis'),
                initialValue: type,
                options: MatchEvent.typeLabels.entries
                    .map((e) => ShadOption(value: e.key, child: Text(e.value)))
                    .toList(),
                selectedOptionBuilder: (c, v) => Text(MatchEvent.typeLabels[v] ?? v),
                onChanged: (v) => setLocal(() => type = v ?? type),
              ),
              const SizedBox(height: 10),
              ShadInput(
                controller: minute,
                placeholder: const Text('Menit (opsional)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
    );
    return ok ?? false;
  }
}
