import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'fmt.dart';
import 'forms.dart';
import 'widgets.dart';

class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> {
  late Future<List<Match>> _future;

  @override
  void initState() {
    super.initState();
    _future = Match.all();
  }

  Future<void> _reload() async {
    final f = Match.all();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {

    return PageScaffold(
      title: 'Tanding',
      subtitle: 'Jadwal & hasil pertandingan',
      actions: [
        iconAction(context, Icons.add, () async {
          if (await showMatchForm(context)) _reload();
        }, tooltip: 'Jadwal baru'),
      ],
      child: AsyncView<List<Match>>(
        future: _future,
        onRefresh: _reload,
        builder: (matches) {
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MatchDetailPage(match: match)),
          ).then((_) => onChanged()),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.colorScheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: finished && win ? t.colorScheme.primary.withValues(alpha: 0.5) : t.colorScheme.border,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: finished
                        ? (win
                            ? t.colorScheme.primary.withValues(alpha: 0.16)
                            : t.colorScheme.muted)
                        : t.colorScheme.secondary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: finished
                      ? Text(
                          '${match.goalsFor}-${match.goalsAgainst}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: win ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                          ),
                        )
                      : Icon(Icons.schedule, size: 18, color: t.colorScheme.mutedForeground),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'vs ${match.opponent}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${fmtDateTime(match.playedAt)}${match.venue != null ? " • ${match.venue}" : ""}',
                        style: t.textTheme.small,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (finished)
                  ShadBadge.outline(
                    child: Text(win ? 'Menang' : (draw ? 'Draw' : 'Kalah'), style: t.textTheme.small),
                  )
                else
                  ShadBadge.secondary(child: Text(match.isHome ? 'Kandang' : 'Tandang', style: t.textTheme.small)),
              ],
            ),
          ),
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

  @override
  void initState() {
    super.initState();
    _events = MatchEvent.forMatch(widget.match.id);
  }

  Future<void> _reload() async {
    final f = MatchEvent.forMatch(widget.match.id);
    setState(() => _events = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final m = widget.match;
    final finished = m.status == 'finished';
    return Scaffold(
      appBar: AppBar(title: Text('vs ${m.opponent}'), backgroundColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.colorScheme.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.colorScheme.border),
            ),
            child: Column(
              children: [
                Text('${fmtDateTime(m.playedAt)}${m.venue != null ? "\n${m.venue}" : ""}',
                    textAlign: TextAlign.center, style: t.textTheme.small),
                const SizedBox(height: 14),
                Text(
                  finished ? '${m.goalsFor} — ${m.goalsAgainst}' : 'VS',
                  style: t.textTheme.h1Large,
                ),
                const SizedBox(height: 6),
                Text(finished ? m.resultLabel : 'Belum dimainkan', style: t.textTheme.muted),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ShadButton.outline(
                        onPressed: () async {
                          if (await showFinishMatch(context, m)) {
                            Navigator.pop(context, true);
                          }
                        },
                        child: Text(finished ? 'Ubah skor' : 'Isi hasil'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ShadButton.destructive(
                      onPressed: () async {
                        if (await confirm(context, 'Hapus pertandingan?', 'Semua catatan gol ikut terhapus.')) {
                          await Match.delete(m.id);
                          if (context.mounted) Navigator.pop(context, true);
                        }
                      },
                      child: const Icon(Icons.delete_outline, size: 16),
                    ),
                  ],
                ),
              ],
            ),
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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: t.colorScheme.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: t.colorScheme.border),
                        ),
                        child: Row(
                          children: [
                            Icon(_icon(e.type), size: 16, color: _color(e.type, t)),
                            const SizedBox(width: 10),
                            Expanded(child: Text(e.memberName)),
                            if (e.minute != null)
                              Text("${e.minute}'", style: t.textTheme.small),
                            const SizedBox(width: 8),
                            ShadBadge.outline(
                              child: Text(MatchEvent.typeLabels[e.type] ?? e.type, style: t.textTheme.small),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 15),
                              onPressed: () async {
                                await MatchEvent.delete(e.id);
                                _reload();
                              },
                            ),
                          ],
                        ),
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

  Future<bool> _addEvent(BuildContext context) async {
    final members = await Member.all();
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
