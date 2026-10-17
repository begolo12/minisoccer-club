import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/models.dart';
import 'theme.dart';
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
    return PageScaffold(
      title: 'Statistik',
      subtitle: 'Rekap hasil & top skor',
      child: AsyncView<_Stats>(
        future: _future,
        onRefresh: _reload,
        builder: (s) {
          final played = s.overall[0] + s.overall[1] + s.overall[2];
          final pts = s.overall[0] * 3 + s.overall[1];
          final diff = s.overall[3] - s.overall[4];
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
                    Expanded(child: StatTile(label: 'Main', value: '$played')),
                    Expanded(
                      child: StatTile(
                        label: 'Poin',
                        value: '$pts',
                        hint: '3 poin per menang',
                        color: t.colorScheme.primary,
                      ),
                    ),
                    Expanded(
                      child: StatTile(
                        label: 'Selisih gol',
                        value: diff > 0 ? '+$diff' : '$diff',
                        color: diff >= 0 ? t.colorScheme.primary : AppThemes.bad(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
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
                        value: '${s.overall[0]}',
                        color: t.colorScheme.primary,
                      ),
                    ),
                    Expanded(child: StatTile(label: 'Seri', value: '${s.overall[1]}')),
                    Expanded(
                      child: StatTile(
                        label: 'Kalah',
                        value: '${s.overall[2]}',
                        color: AppThemes.bad(context),
                      ),
                    ),
                    Expanded(child: StatTile(label: 'Gol', value: '${s.overall[3]}')),
                    Expanded(child: StatTile(label: 'Bobol', value: '${s.overall[4]}')),
                  ],
                ),
              ),
              const SectionTitle('Pencetak gol'),
              if (s.scorers.isEmpty)
                Text('Belum ada catatan gol. Isi lewat detail pertandingan.', style: t.textTheme.muted)
              else
                for (var i = 0; i < s.scorers.length; i++)
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
                    title: s.scorers[i].name,
                    subtitle: '${s.scorers[i].assists} assist',
                    trailing: Text(
                      '${s.scorers[i].goals} gol',
                      style: t.textTheme.h2.copyWith(fontSize: 20),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
