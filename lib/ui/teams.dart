import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/soft.dart';
import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'members.dart';
import 'matches.dart';
import 'widgets.dart';

/// Data halaman Tim. `standings` dimuat terpisah dari tim & pemain karena
/// view klasemen bisa belum punya izin di server; kegagalannya dicatat di
/// [failures] supaya daftar tim tetap tampil.
typedef _TeamsData = (List<Team>, Map<int, List<Member>>, List<Standing>, List<String>);

/// Tim klub: 7-8 pemain per tim. Semua tanding dan turnamen memakai tim ini.
class TeamsPage extends StatefulWidget {
  const TeamsPage({super.key});

  @override
  State<TeamsPage> createState() => _TeamsPageState();
}

class _TeamsPageState extends State<TeamsPage> {
  late Future<_TeamsData> _future;

  Future<_TeamsData> _load() async {
    final r = await Future.wait<Soft<Object?>>([
      soft('Daftar tim', Team.all, fallback: const <Team>[]),
      soft('Pemain per tim', Team.players, fallback: const <int, List<Member>>{}),
      soft('Klasemen tim', Team.standings, fallback: const <Standing>[]),
    ]);
    final failures = settle(r);
    return (
      r[0].value! as List<Team>,
      r[1].value! as Map<int, List<Member>>,
      r[2].value! as List<Standing>,
      failures,
    );
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

  Future<void> _addTeam() async {
    final next = await _teamCount();
    if (!mounted) return;
    final name = TextEditingController(text: 'Tim ${String.fromCharCode(65 + next)}');
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: const Text('Tim baru'),
        description: const Text('Satu tim berisi 7-8 pemain. Tambah pemain setelah tim dibuat.'),
        actions: [
          ShadButton.outline(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ShadButton(
            onPressed: () async {
              final v = name.text.trim();
              if (v.isEmpty) {
                toast(ctx, 'Nama tim wajib diisi');
                return;
              }
              try {
                await Team.insert(v);
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) toast(ctx, 'Gagal: ${errText(e)}');
              }
            },
            child: const Text('Simpan'),
          ),
        ],
        child: ShadInput(controller: name, placeholder: const Text('Nama tim')),
      ),
    );
    if (ok ?? false) await _reload();
  }

  Future<int> _teamCount() async {
    final f = _future;
    try {
      return (await f).$1.length;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Tim',
      subtitle: '7–8 pemain per tim • dasar semua tanding',
      actions: [
        if (Auth.canWrite)
          iconAction(context, Icons.add, _addTeam, tooltip: 'Tim baru'),
      ],
      child: AsyncView<_TeamsData>(
        future: _future,
        onRefresh: _reload,
        builder: (data) {
          final teams = data.$1;
          final players = data.$2;
          final standings = data.$3;
          final failures = data.$4;
          if (teams.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 60),
                // Gagal memuat ≠ belum ada tim. Tanpa pembeda ini, tim yang
                // sebenarnya ada terlihat seperti hilang dan admin tergoda
                // membuat ulang.
                if (failures.isNotEmpty)
                  DegradedNotice(failures: failures, onRetry: _reload)
                else
                  EmptyState(
                    icon: Icons.shield_outlined,
                    title: 'Belum ada tim',
                    message: 'Buat 2 tim (masing-masing 7–8 pemain) supaya bisa tanding internal.',
                    actionLabel: Auth.canWrite ? 'Buat tim pertama' : null,
                    onAction: Auth.canWrite ? _addTeam : null,
                  ),
              ],
            );
          }
          final byId = {for (final s in standings) s.teamId: s};
          final totalPlayers = players.values.fold<int>(0, (s, p) => s + p.length);
          final ready = teams.where((t) => (players[t.id]?.length ?? 0) >= 7).length;
          final hasResults = standings.any((s) => s.played > 0);
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              if (failures.isNotEmpty) DegradedNotice(failures: failures, onRetry: _reload),
              StatStrip(
                children: [
                  StatTile(label: 'Tim', value: '${teams.length}', hint: 'terdaftar'),
                  StatTile(
                    label: 'Pemain',
                    value: '$totalPlayers',
                    hint: 'anggota aktif',
                  ),
                  StatTile(
                    label: 'Siap main',
                    value: '$ready/${teams.length}',
                    hint: 'min. 7 pemain',
                    color: ready == teams.length ? t.colorScheme.primary : null,
                  ),
                ],
              ),
              if (hasResults) ...[
                const SectionTitle('Klasemen'),
                StandingsTable(standings: standings, top: 1),
              ],
              const SectionTitle('Daftar tim'),
              for (final team in teams)
                _TeamTile(
                  team: team,
                  players: players[team.id] ?? const [],
                  standing: byId[team.id],
                  onChanged: _reload,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({
    required this.team,
    required this.players,
    required this.standing,
    required this.onChanged,
  });

  final Team team;
  final List<Member> players;
  final Standing? standing;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final count = players.length;
    // 7-8 pemain adalah target. Kurang pemain bukan error, jadi ditandai
    // netral — merah hanya untuk hal yang gagal/tunggakan.
    final short = count < 7;
    final ready = count >= 7;
    return RowItem(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TeamDetailPage(team: team)),
        );
        await onChanged();
      },
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: ready ? t.colorScheme.primary.withValues(alpha: 0.5) : t.colorScheme.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$count',
          style: t.textTheme.h2.copyWith(
            fontSize: 18,
            color: ready ? t.colorScheme.primary : t.colorScheme.mutedForeground,
          ),
        ),
      ),
      title: team.name,
      subtitle: '$count pemain${short ? ' • kurang ${7 - count} untuk 7' : ''}'
          '${standing == null || standing!.played == 0 ? '' : ' • ${standing!.won}M ${standing!.drawn}S ${standing!.lost}K'}',
      trailing: Icon(Icons.chevron_right, size: 18, color: t.colorScheme.mutedForeground),
    );
  }
}

/// Detail satu tim: pemain + riwayat laga + aksi kelola.
class TeamDetailPage extends StatefulWidget {
  const TeamDetailPage({super.key, required this.team});

  final Team team;

  @override
  State<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends State<TeamDetailPage> {
  late Future<(List<Member>, List<Match>, List<int>, List<String>)> _future;

  /// Nama tim yang sedang tampil. `widget.team` adalah objek beku dari daftar
  /// sebelumnya: setelah "Ganti nama" berhasil, judul halaman dan dialog
  /// "Tambah ke ..." masih menyebut nama lama sepanjang halaman ini terbuka.
  late String _name = widget.team.name;

  /// Statistik tim dihitung dari SEMUA laga selesai (lihat
  /// `Match.statsForTeam`), bukan dari riwayat yang ditampilkan — riwayat
  /// dibatasi supaya halaman tidak memanjang tanpa ujung.
  ///
  /// Statistik ikut di dalam hasil Future, bukan field terpisah yang diisi
  /// sebagai efek samping: field seperti itu bisa terbaca sebelum terisi
  /// (halaman sempat menampilkan "MAIN 0" padahal ada hasil), dan membuat
  /// builder bergantung pada urutan eksekusi.
  Future<(List<Member>, List<Match>, List<int>, List<String>)> _load() async {
    final r = await Future.wait<Soft<Object?>>([
      soft('Pemain tim', _players, fallback: const <Member>[]),
      soft('Riwayat laga', () => Match.forTeam(widget.team.id), fallback: const <Match>[]),
      soft('Statistik tim', () => Match.statsForTeam(widget.team.id),
          fallback: const <int>[0, 0, 0, 0, 0, 0]),
    ]);
    return (
      r[0].value! as List<Member>,
      r[1].value! as List<Match>,
      r[2].value! as List<int>,
      settle(r),
    );
  }

  Future<List<Member>> _players() async {
    final map = await Team.players();
    return map[widget.team.id] ?? const [];
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

  Future<void> _rename() async {
    final c = TextEditingController(text: _name);
    final ok = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: const Text('Nama tim'),
        actions: [
          ShadButton.outline(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ShadButton(
            onPressed: () async {
              final v = c.text.trim();
              if (v.isEmpty) {
                toast(ctx, 'Nama tim wajib diisi');
                return;
              }
              if (await attempt(ctx, () => Team.rename(widget.team.id, v), fail: 'Gagal mengganti nama')) {
                if (ctx.mounted) Navigator.pop(ctx, true);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
        child: ShadInput(controller: c, placeholder: const Text('Nama tim')),
      ),
    );
    if (ok ?? false) {
      // Nama baru dipakai judul halaman & dialog berikutnya.
      final v = c.text.trim();
      if (v.isNotEmpty) setState(() => _name = v);
      await _reload();
    }
    c.dispose();
  }

  Future<void> _addPlayer(List<Member> current) async {
    // Await sebelum dialog bisa gagal; tanpa try/catch tombol tambah pemain
    // diam saja saat jaringan/server bermasalah.
    final List<Member> all;
    try {
      all = await Member.all(activeOnly: true);
    } catch (e) {
      if (mounted) toast(context, 'Gagal memuat anggota: ${errText(e)}');
      return;
    }
    if (!mounted) return;
    final taken = current.map((p) => p.id).toSet();
    final free = all.where((m) => !taken.contains(m.id)).toList();
    if (free.isEmpty) {
      // Toast hilang sendiri dan tidak bisa diketuk. Ini ujung rantai dari
      // "isi pemain tim", jadi tawarkan tombol yang benar-benar menyelesaikan.
      final add = await showShadDialog<bool>(
        context: context,
        builder: (ctx) => ShadDialog(
          title: Text(all.isEmpty ? 'Belum ada anggota' : 'Semua anggota sudah masuk'),
          description: Text(
            all.isEmpty
                ? 'Tim diisi dari daftar anggota klub. Tambah anggota dulu, lalu '
                    'kembali ke sini untuk memasukkannya ke ${widget.team.name}.'
                : 'Semua anggota aktif sudah ada di tim ini. Tambah anggota baru '
                    'kalau ingin mengisi lebih banyak pemain.',
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Nanti'),
            ),
            ShadButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Buka Anggota'),
            ),
          ],
        ),
      );
      if (add == true && mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MembersPage()));
        if (mounted) await _reload();
      }
      return;
    }
    final picked = await showShadDialog<Member>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: Text('Tambah ke ${widget.team.name}'),
        actions: [
          ShadButton.outline(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
        child: SizedBox(
          height: 340,
          child: Material(
            type: MaterialType.transparency,
            child: ListView(
              children: [
                for (final m in free)
                  RowItem(
                    title: m.name,
                    subtitle: '${m.position}${m.jersey == null ? '' : ' • #${m.jersey}'}',
                    onTap: () => Navigator.pop(ctx, m),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (await attempt(context, () => Team.addPlayer(widget.team.id, picked.id), fail: 'Gagal menambah pemain')) {
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: widget.team.name,
      subtitle: 'Tim klub',
      actions: [
        if (Auth.canWrite) ...[
          iconAction(context, Icons.edit_outlined, _rename, tooltip: 'Ganti nama'),
          iconAction(context, Icons.delete_outline, () async {
            final (internal, tour) = await Team.deletionImpact(widget.team.id);
            if (!context.mounted) return;
            final parts = <String>[
              if (internal > 0)
                '$internal laga internal tetap ada tanpa nama tim',
              if (tour > 0)
                '$tour laga turnamen IKUT TERHAPUS dan klasemennya berubah',
              if (internal == 0 && tour == 0) 'Tim belum punya laga.',
            ];
            if (await confirm(
              context,
              'Hapus ${widget.team.name}?',
              '${parts.join('. ')}. Tindakan ini tidak bisa dibatalkan.',
            )) {
              if (!context.mounted) return;
              if (await attempt(context, () => Team.delete(widget.team.id), fail: 'Gagal menghapus')) {
                if (context.mounted) Navigator.pop(context);
              }
            }
          }, tooltip: 'Hapus tim'),
        ],
      ],
      child: AsyncView<(List<Member>, List<Match>, List<int>, List<String>)>(
        future: _future,
        onRefresh: _reload,
        builder: (data) {
          final players = data.$1;
          final matches = data.$2;
          final stats = data.$3;
          final failures = data.$4;
          final done = matches.where((m) => m.finished).toList();
          final upcoming = matches.where((m) => !m.finished).toList()
            ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
          // Statistik dari agregat DB (semua laga selesai), bukan dari daftar
          // riwayat: riwayat dibatasi supaya halaman tidak memanjang, jadi
          // "Main" di sini bisa lebih kecil dari klasemen kalau memakainya.
          final played = stats[0];
          final won = stats[1];
          final drawn = stats[2];
          final lost = stats[3];
          final gf = stats[4];
          final ga = stats[5];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              if (failures.isNotEmpty) DegradedNotice(failures: failures, onRetry: _reload),
              StatStrip(
                children: [
                  StatTile(
                    label: 'Pemain',
                    value: '${players.length}',
                    hint: players.length < 7 ? 'butuh 7–8' : 'cukup',
                  ),
                  StatTile(
                    label: 'Main',
                    value: '$played',
                    hint: '${won}M ${drawn}S ${lost}K',
                  ),
                  StatTile(
                    label: 'Gol',
                    value: '$gf–$ga',
                    hint: 'memasukkan–kebobolan',
                    color: gf >= ga ? t.colorScheme.primary : null,
                  ),
                ],
              ),
              SectionTitle(
                'Pemain',
                action: Auth.canWrite
                    ? ShadButton.ghost(
                        size: ShadButtonSize.sm,
                        onPressed: () => _addPlayer(players),
                        child: const Row(
                          children: [Icon(Icons.person_add_alt, size: 14), SizedBox(width: 4), Text('Tambah')],
                        ),
                      )
                    : null,
              ),
              if (players.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('Belum ada pemain di tim ini.', style: t.textTheme.muted),
                )
              else
                for (final p in players)
                  RowItem(
                    leading: SizedBox(
                      width: 30,
                      child: Text(
                        p.jersey == null ? '–' : '${p.jersey}',
                        style: t.textTheme.h2.copyWith(fontSize: 17, color: t.colorScheme.primary),
                      ),
                    ),
                    title: p.name,
                    subtitle: p.position,
                    trailing: Auth.canWrite
                        ? iconAction(context, Icons.close, () async {
                            if (await attempt(context, () => Team.removePlayer(widget.team.id, p.id),
                                fail: 'Gagal mengeluarkan pemain')) {
                              await _reload();
                            }
                          }, tooltip: 'Keluarkan dari tim')
                        : null,
                  ),
              // Laga terjadwal bukan riwayat. Tanpa pemisahan ini judul
              // "Riwayat laga" menaungi baris "AKAN DATANG".
              if (upcoming.isNotEmpty) ...[
                const SectionTitle('Laga berikutnya'),
                for (final m in upcoming) _matchRow(context, m),
              ],
              const SectionTitle('Riwayat laga'),
              if (done.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    upcoming.isEmpty
                        ? 'Belum ada laga untuk tim ini.'
                        : 'Belum ada laga selesai.',
                    style: t.textTheme.muted,
                  ),
                )
              else
                for (final m in done) _matchRow(context, m),
            ],
          );
        },
      ),
    );
  }

  Widget _matchRow(BuildContext context, Match m) => MatchRow(
        match: m,
        showResult: false,
        forTeamId: widget.team.id,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => MatchDetailPage(match: m)),
          );
          await _reload();
        },
      );
}
