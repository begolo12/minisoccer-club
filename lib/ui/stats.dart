import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/soft.dart';
import '../data/models.dart';
import 'widgets.dart';

class _Stats {
  final List<int> overall;
  final List<ScorerRow> scorers;
  final List<Standing> standings;

  /// Sumber yang gagal dimuat. Halaman tetap tampil dengan bagian yang
  /// berhasil; tanpa ini satu view yang izinnya belum ada mematikan seluruh
  /// halaman Statistik.
  final List<String> failures;

  _Stats(this.overall, this.scorers, this.standings, this.failures);

  static Future<_Stats> load() async {
    final r = await Future.wait<Soft<Object?>>([
      soft('Rekap laga', Match.stats, fallback: const [0, 0, 0, 0, 0]),
      soft('Pencetak gol', ScorerRow.top, fallback: const <ScorerRow>[]),
      soft('Klasemen tim', Team.standings, fallback: const <Standing>[]),
    ]);
    final failures = settle(r);
    return _Stats(
      r[0].value! as List<int>,
      r[1].value! as List<ScorerRow>,
      r[2].value! as List<Standing>,
      failures,
    );
  }
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late Future<_Stats> _future;

  /// Daftar pencetak gol bisa panjang (semua yang pernah mencetak sekali).
  /// Lima teratas cukup untuk dibaca; sisanya dibuka kalau dicari.
  static const _scorerLimit = 5;
  bool _allScorers = false;

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
      subtitle: 'Rekap hasil & pencetak gol',
      child: AsyncView<_Stats>(
        future: _future,
        onRefresh: _reload,
        builder: (s) {
          final played = s.overall[0] + s.overall[1] + s.overall[2];
          // `goals_for` hanya gol tim home dan `goals_against` gol tim away.
          // Di laga internal keduanya sama-sama gol klub, jadi totalnya
          // dijumlah — bukan dikurangkan seperti selisih dua tim.
          final goals = s.overall[3] + s.overall[4];
          final perMatch = played == 0 ? null : goals / played;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              if (s.failures.isNotEmpty) DegradedNotice(failures: s.failures, onRetry: _reload),
              StatStrip(
                children: [
                  StatTile(
                    label: 'Main',
                    value: '$played',
                    hint: 'laga selesai',
                  ),
                  StatTile(
                    label: 'Gol',
                    value: '$goals',
                    hint: perMatch == null
                        ? 'belum ada laga'
                        : '${perMatch.toStringAsFixed(1)} per laga',
                  ),
                  StatTile(
                    label: 'Seri',
                    value: '${s.overall[1]}',
                    hint: played == 0
                        ? 'belum ada laga'
                        : '${(s.overall[1] * 100 / played).round()}% laga',
                    color: t.colorScheme.primary,
                  ),
                ],
              ),
              SectionTitle(
                'Pencetak gol',
                action: s.scorers.length > _scorerLimit
                    ? TextButton(
                        onPressed: () => setState(() => _allScorers = !_allScorers),
                        child: Text(_allScorers ? 'Ringkas' : 'Semua ${s.scorers.length}'),
                      )
                    : null,
              ),
              if (s.scorers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Belum ada catatan gol. Isi lewat detail pertandingan.',
                    style: t.textTheme.muted,
                  ),
                )
              else
                for (var i = 0;
                    i < (_allScorers ? s.scorers.length : s.scorers.length.clamp(0, _scorerLimit));
                    i++)
                  _ScorerRow(index: i, row: s.scorers[i], topGoals: s.scorers.first.goals),
              if (s.standings.isNotEmpty) ...[
                const SectionTitle('Klasemen tim'),
                StandingsTable(standings: s.standings, top: 1),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Baris pencetak gol dengan batang proporsional terhadap pemuncak, supaya
/// selisih gol terbaca tanpa harus membandingkan angka.
class _ScorerRow extends StatelessWidget {
  const _ScorerRow({required this.index, required this.row, required this.topGoals});

  final int index;
  final ScorerRow row;
  final int topGoals;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final ratio = topGoals == 0 ? 0.0 : row.goals / topGoals;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                '${index + 1}',
                style: t.textTheme.h2.copyWith(
                  fontSize: 19,
                  height: 1,
                  color: index == 0 ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.name,
                        style: t.textTheme.large,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (row.assists > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text('${row.assists} assist', style: t.textTheme.small),
                      ),
                    Text(
                      '${row.goals}',
                      style: t.textTheme.h2.copyWith(
                        fontSize: 22,
                        color: index == 0 ? t.colorScheme.primary : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 3,
                    backgroundColor: t.colorScheme.muted,
                    valueColor: AlwaysStoppedAnimation(
                      index == 0
                          ? t.colorScheme.primary
                          : t.colorScheme.primary.withValues(alpha: 0.45),
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
