import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'widgets.dart';

class _Stats {
  final List<int> overall;
  final List<ScorerRow> scorers;

  _Stats(this.overall, this.scorers);

  static Future<_Stats> load() async {
    final r = await Future.wait([Match.stats(), ScorerRow.top()]);
    return _Stats(r[0] as List<int>, r[1] as List<ScorerRow>);
  }
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late Future<_Stats> _future;

  @override
  void initState() {
    super.initState();
    _future = _Stats.load();
  }

  Future<void> _reload() async {
    final f = _Stats.load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Statistik'), backgroundColor: Colors.transparent),
      body: AsyncView<_Stats>(
        future: _future,
        onRefresh: _reload,
        builder: (s) {
          final played = s.overall[0] + s.overall[1] + s.overall[2];
          final pts = s.overall[0] * 3 + s.overall[1];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Row(
                children: [
                  Expanded(child: StatTile(label: 'Main', value: '$played', icon: Icons.sports_soccer)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'Poin',
                      value: '$pts',
                      hint: '3 poin / kemenangan',
                      color: t.colorScheme.primary,
                      icon: Icons.military_tech_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: StatTile(label: 'Menang', value: '${s.overall[0]}', color: t.colorScheme.primary)),
                  const SizedBox(width: 10),
                  Expanded(child: StatTile(label: 'Draw', value: '${s.overall[1]}')),
                  const SizedBox(width: 10),
                  Expanded(child: StatTile(label: 'Kalah', value: '${s.overall[2]}', color: t.colorScheme.destructive)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: StatTile(label: 'Gol kita', value: '${s.overall[3]}')),
                  const SizedBox(width: 10),
                  Expanded(child: StatTile(label: 'Gol lawan', value: '${s.overall[4]}')),
                  const SizedBox(width: 10),
                  Expanded(
                    child: StatTile(
                      label: 'Selisih',
                      value: '${s.overall[3] - s.overall[4]}',
                      color: s.overall[3] >= s.overall[4] ? t.colorScheme.primary : t.colorScheme.destructive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const SectionTitle('Pencetak gol'),
              if (s.scorers.isEmpty)
                Text('Belum ada catatan gol. Isi lewat detail pertandingan.', style: t.textTheme.muted)
              else
                Container(
                  decoration: BoxDecoration(
                    color: t.colorScheme.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.colorScheme.border),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < s.scorers.length; i++)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            border: i == s.scorers.length - 1
                                ? null
                                : Border(bottom: BorderSide(color: t.colorScheme.border)),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                child: Text('${i + 1}', style: t.textTheme.small),
                              ),
                              Expanded(child: Text(s.scorers[i].name)),
                              Text('${s.scorers[i].goals} gol', style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(width: 10),
                              Text('${s.scorers[i].assists} assist', style: t.textTheme.small),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
