import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/soft.dart';
import '../data/auth.dart';
import '../data/models.dart';
import 'export.dart';
import 'fmt.dart';
import 'tournament.dart';
import 'forms.dart';
import 'theme.dart';
import 'widgets.dart';

class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key});

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

/// (laga, rekap, klasemen, peringatan). Setiap sumber dimuat terpisah supaya
/// satu tabel/view yang belum punya izin tidak mematikan seluruh halaman
/// Tanding — dulu `Future.wait` biasa membuat layar hanya menampilkan
/// "Gagal memuat data" padahal daftar laga sendiri berhasil dibaca.
typedef _MatchesData = (List<Match>, List<int>, List<Standing>, List<String>);

class _MatchesPageState extends State<MatchesPage> {
  late Future<_MatchesData> _future;

  Future<_MatchesData> _load() async {
    final r = await Future.wait<Soft<Object?>>([
      soft('Daftar laga', Match.all, fallback: const <Match>[]),
      soft('Rekap laga', Match.stats, fallback: const [0, 0, 0, 0, 0]),
      soft('Klasemen tim', Team.standings, fallback: const <Standing>[]),
    ]);
    final failures = settle(r);
    return (
      r[0].value! as List<Match>,
      r[1].value! as List<int>,
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

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Tanding',
      subtitle: 'Laga internal antar tim klub',
      actions: [
        if (Auth.canWrite)
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: () async {
              if (await showMatchForm(context)) _reload();
            },
            leading: const Icon(Icons.add, size: 15),
            child: const Text('Jadwal'),
          ),
      ],
      child: AsyncView<_MatchesData>(
        future: _future,
        onRefresh: _reload,
        builder: (data) {
          final matches = data.$1;
          final stats = data.$2;
          final standings = data.$3;
          final failures = data.$4;
          // Kosong = belum ada laga SAMA SEKALI. Klasemen yang masih nol tidak
          // dihitung "ada isi": sebelumnya tabel empat tim dengan angka 0
          // membuat halaman tampak terisi, padahal tidak ada satu laga pun dan
          // tidak ada petunjuk apa yang harus dilakukan.
          if (matches.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                if (failures.isNotEmpty)
                  DegradedNotice(failures: failures, onRetry: _reload)
                else ...[
                  const SizedBox(height: 40),
                  EmptyState(
                    icon: Icons.sports_soccer_outlined,
                    title: 'Belum ada laga',
                    message: 'Laga bisa dibuat dua cara: jadwalkan satu per satu di '
                        'sini, atau buat turnamen internal supaya jadwalnya dibuat '
                        'otomatis untuk semua tim.',
                    actionLabel: Auth.canWrite ? 'Jadwalkan laga' : null,
                    onAction: Auth.canWrite
                        ? () async {
                            if (await showMatchForm(context)) _reload();
                          }
                        : null,
                  ),
                  if (Auth.canWrite) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const TournamentsPage()),
                          );
                          _reload();
                        },
                        child: const Text('Buat turnamen (jadwal otomatis)'),
                      ),
                    ),
                  ],
                ],
              ],
            );
          }
          final live = matches.where((m) => m.status != 'finished').toList()
            ..sort((a, b) => a.playedAt.compareTo(b.playedAt));
          final done = matches.where((m) => m.status == 'finished').toList();
          final ongoing = live.where((m) => m.ongoing).toList();
          final scheduled = live.where((m) => !m.ongoing).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              if (failures.isNotEmpty) DegradedNotice(failures: failures, onRetry: _reload),
              _StatsStrip(stats: stats),
              if (ongoing.isNotEmpty) ...[
                const SectionTitle('Sedang berlangsung'),
                for (final m in ongoing) _MatchTile(match: m, onChanged: _reload),
              ],
              if (scheduled.isNotEmpty) ...[
                const SectionTitle('Jadwal berikutnya'),
                for (final m in scheduled) _MatchTile(match: m, onChanged: _reload),
              ],
              // Klasemen yang seluruhnya nol tidak menambah informasi: semua
              // tim 0 poin karena belum ada laga. Tabel kosong hanya membuat
              // halaman terlihat "terisi" padahal tidak ada hasil apa pun.
              if (standings.any((s) => s.played > 0)) ...[
                const SectionTitle('Klasemen tim'),
                StandingsTable(standings: standings, top: 1),
              ],
              if (done.isNotEmpty) ...[
                const SectionTitle('Riwayat hasil'),
                for (final m in done) _MatchTile(match: m, onChanged: _reload),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Ringkasan seluruh laga internal. W/D/L sengaja tidak ditampilkan: semua
/// laga mempertemukan dua tim klub, jadi setiap laga selalu punya pemenang
/// dan pecundang — "2M 1S 1K" di level klub tidak berarti apa-apa.
class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats});

  final List<int> stats;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final played = stats[0] + stats[1] + stats[2];
    // `goals_for` = gol tim home, `goals_against` = gol tim away. Keduanya
    // gol klub di laga internal, jadi total gol adalah jumlahnya.
    final goals = stats[3] + stats[4];
    final perMatch = played == 0 ? null : goals / played;
    return StatStrip(
      children: [
        StatTile(
          label: 'Main',
          value: '$played',
          hint: 'laga selesai',
        ),
        StatTile(
          label: 'Gol',
          value: '$goals',
          hint: perMatch == null ? 'belum ada laga' : '${perMatch.toStringAsFixed(1)} per laga',
        ),
        StatTile(
          label: 'Seri',
          value: '${stats[1]}',
          hint: played == 0 ? 'belum ada laga' : '${(stats[1] * 100 / played).round()}% laga',
          color: t.colorScheme.primary,
        ),
      ],
    );
  }
}

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.onChanged});

  final Match match;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    return MatchRow(
      match: match,
      // Hasil bisa dikunci langsung dari daftar: satu ketukan ke dialog skor,
      // tanpa membuka detail laga dulu.
      onFinish: Auth.canWrite && !match.finished
          ? () async {
              if (!await showFinishMatch(context, match)) return;
              // Toast dulu, baru muat ulang: reload membuang context baris ini.
              if (context.mounted) toast(context, 'Hasil tersimpan · poin klasemen diperbarui');
              await onChanged();
            }
          : null,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MatchDetailPage(match: match)),
      ).then((_) => onChanged()),
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

  /// Salinan laga yang selalu ikut diperbarui. Tanpa ini header tetap
  /// menampilkan skor saat halaman dibuka, walau sesi baru menaikkan totalnya.
  late Match _match = widget.match;

  @override
  void initState() {
    super.initState();
    _events = MatchEvent.forMatch(widget.match.id);
    _sessions = MatchSession.forMatch(widget.match.id);
  }

  Future<void> _reload() async {
    final e = MatchEvent.forMatch(widget.match.id);
    final s = MatchSession.forMatch(widget.match.id);
    final fresh = Match.byId(widget.match.id);
    setState(() {
      _events = e;
      _sessions = s;
    });
    final results = await Future.wait([e, s, fresh]);
    if (!mounted) return;
    setState(() {
      final m = results[2] as Match?;
      if (m != null) _match = m;
      _events = Future.value(results[0] as List<MatchEvent>);
      _sessions = Future.value(results[1] as List<MatchSession>);
    });
  }

  /// Salin hasil/jadwal sebagai teks siap-tempel ke grup.
  ///
  /// Papan skor yang bagus tetap tidak bisa dikutip: pengumuman hasil di
  /// grup WhatsApp selalu diketik ulang. Teksnya mengikuti bentuk yang
  /// biasa dipakai orang — "HASIL", satu baris skor, satu baris waktu.
  Future<void> _share(Match m) async {
    final finished = m.status == 'finished';
    final head = finished ? 'HASIL' : (m.ongoing ? 'SEDANG BERLANGSUNG' : 'JADWAL LAGA');
    final score = finished || m.ongoing ? '${m.goalsFor}–${m.goalsAgainst}' : '–';
    final text = [
      '⚽ $head',
      '${m.homeName} $score ${m.awayName}',
      '${fmtDateTime(m.playedAt)}${m.venue == null ? '' : ' • ${m.venue}'}',
    ].join('\n');
    await showTextShare(
      context,
      title: finished ? 'Salin hasil' : 'Salin laga',
      description: 'Tempel ke grup WhatsApp.',
      text: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final m = _match;
    final finished = m.status == 'finished';
    return PageScaffold(
      title: '${m.homeName} lawan ${m.awayName}',
      // Ubah jadwal & hapus ada di kepala halaman, bukan di dalam kartu skor:
      // di 320px dua tombol ikon tambahan di kartu membuat baris aksi pecah
      // ke baris kedua sendirian.
      actions: [
        iconAction(context, Icons.ios_share, () => _share(m), tooltip: 'Salin hasil'),
        if (Auth.canWrite)
          iconAction(context, Icons.edit_outlined, () async {
            if (await showMatchForm(context, match: m)) {
              if (!context.mounted) return;
              await _reload();
            }
          }, tooltip: 'Ubah jadwal'),
        if (Auth.canWrite)
          iconAction(context, Icons.delete_outline, () async {
            if (await confirm(context, 'Hapus laga?', 'Semua catatan gol ikut terhapus.')) {
              if (!context.mounted) return;
              if (await attempt(context, () => Match.delete(m.id), fail: 'Gagal menghapus')) {
                if (context.mounted) Navigator.pop(context, true);
              }
            }
          }, tooltip: 'Hapus pertandingan'),
      ],
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.homeName,
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        finished || m.ongoing ? '${m.goalsFor}–${m.goalsAgainst}' : '–',
                        style: t.textTheme.h1Large.copyWith(
                          fontSize: 44,
                          color: finished
                              ? (m.goalsFor > m.goalsAgainst
                                  ? t.colorScheme.primary
                                  : (m.goalsFor == m.goalsAgainst
                                      ? t.colorScheme.mutedForeground
                                      : AppThemes.bad(context)))
                              : (m.ongoing
                                  ? t.colorScheme.primary
                                  : t.colorScheme.foreground),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        m.awayName,
                        maxLines: 2,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  finished
                      ? (m.goalsFor > m.goalsAgainst
                          ? '${m.homeName} menang'
                          : (m.goalsFor == m.goalsAgainst ? 'Seri' : '${m.awayName} menang'))
                      : (m.status == 'ongoing' ? 'Sedang berlangsung' : 'Belum dimainkan'),
                  style: t.textTheme.muted,
                ),
                const SizedBox(height: 16),
                if (Auth.canWrite)
                  FutureBuilder<List<MatchSession>>(
                    future: _sessions,
                    builder: (context, snap) {
                      final hasSessions = (snap.data ?? const <MatchSession>[]).isNotEmpty;
                      return Column(
                        children: [
                          // `Wrap`, bukan `Row`: di 320px tombol "Selesai"
                          // + "Mulai" + dua ikon tidak muat satu baris dan
                          // tombol hapus terpotong tepi kartu.
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              // Tombol tetap ada walau skor berasal dari sesi:
                              // menyelesaikan laga tidak boleh memaksa user
                              // kembali ke daftar dulu.
                              ShadButton.outline(
                                onPressed: () async {
                                  if (await showFinishMatch(context, m)) {
                                    if (!context.mounted) return;
                                    Navigator.pop(context, true);
                                  }
                                },
                                child: Text(finished ? 'Ubah hasil' : 'Selesaikan'),
                              ),
                              if (m.status == 'scheduled')
                                // Papan skor beranda hanya menampilkan laga
                                // `ongoing`; tanpa tombol ini laga 0–0 yang
                                // baru dimulai tidak bisa tampil sebagai laga
                                // hidup sebelum ada gol.
                                ShadButton(
                                  onPressed: () async {
                                    if (await attempt(context, m.start, fail: 'Gagal memulai')) {
                                      await _reload();
                                    }
                                  },
                                  leading: const Icon(Icons.play_arrow_rounded, size: 16),
                                  child: const Text('Mulai'),
                                ),
                            ],
                          ),
                          if (hasSessions)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Skor = jumlah ${snap.data!.length} sesi di bawah',
                                style: t.textTheme.small,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SectionTitle(
            'Sesi & pemenang',
            action: Auth.canWrite
                ? ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: () async {
                      if (await _sessionForm(context)) _reload();
                    },
                    child: const Row(
                      children: [Icon(Icons.add, size: 14), SizedBox(width: 4), Text('Sesi')],
                    ),
                  )
                : null,
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
                      onTap: Auth.canWrite
                          ? () async {
                              if (await _sessionForm(context, session: s)) _reload();
                            }
                          : null,
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
            // Judul menyebut sendiri bahwa ini bukan sumber skor: 2 gol di
            // daftar bawah tidak menggeser papan skor, karena skor laga
            // dihitung dari sesi. Tanpa keterangan ini angkanya terlihat
            // seperti bug.
            'Catatan pertandingan',
            action: Auth.canWrite
                ? ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    onPressed: () async {
                      if (await _openEventPad(context)) _reload();
                    },
                    child: const Row(
                      children: [Icon(Icons.touch_app_outlined, size: 14), SizedBox(width: 4), Text('Catat')],
                    ),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Catatan pemain (gol/umpan gol/kartu). Skor laga tetap dari sesi.',
              style: t.textTheme.small,
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
                    child: Text('Belum ada gol/umpan gol/kartu.', style: t.textTheme.muted),
                  ),
                );
              }
              return Column(
                children: [
                  for (final e in events)
                    RowItem(
                      leading: Icon(_icon(e.type), size: 16, color: _color(e.type, context)),
                      title: e.memberName,
                      subtitle: MatchEvent.typeLabels[e.type] ?? e.type,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (e.minute != null)
                            Text("${e.minute}'", style: t.textTheme.table),
                          if (Auth.canWrite) ...[
                            const SizedBox(width: 8),
                            iconAction(context, Icons.close, () async {
                              if (await attempt(context, () => MatchEvent.delete(e.id), fail: 'Gagal menghapus')) {
                                _reload();
                              }
                            }, tooltip: 'Hapus catatan'),
                          ],
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
        // Kuning kotak garis, merah kotak penuh: keduanya dibedakan bentuk,
        // bukan hanya warna — kartu merah yang salah baca adalah catatan
        // disiplin yang salah orang.
        'yellow' => Icons.square_outlined,
        _ => Icons.square_rounded,
      };

  // Butuh context: kuning kartu punya versi khusus tema terang, karena
  // kuning aslinya di atas latar putih hampir tidak terlihat.
  Color _color(String type, BuildContext context) {
    final t = ShadTheme.of(context);
    return switch (type) {
      'goal' => t.colorScheme.primary,
      'yellow' => AppThemes.cardYellow(context),
      'red' => t.colorScheme.destructive,
      _ => t.colorScheme.mutedForeground,
    };
  }

  Future<bool> _sessionForm(BuildContext context, {MatchSession? session}) async {
    // Daftar sesi dipakai untuk menentukan nomor sesi berikutnya. Saat offline
    // bacaan ini bisa gagal; dulu dialognya tidak terbuka sama sekali sehingga
    // mencatat babak tidak mungkin dilakukan tanpa sinyal.
    var existing = const <MatchSession>[];
    try {
      existing = await MatchSession.forMatch(widget.match.id);
    } catch (_) {
      existing = const <MatchSession>[];
    }
    if (!context.mounted) return false;
    final nextNo = session?.sessionNo ??
        (existing.isEmpty
            ? 1
            : existing.map((s) => s.sessionNo).reduce((a, b) => a > b ? a : b) + 1);
    // Stepper yang sama dengan dialog hasil laga: memasukkan skor di aplikasi
    // ini selalu lewat tombol −/+, tidak pernah keyboard angka.
    var home = session?.scoreHome ?? 0;
    var away = session?.scoreAway ?? 0;
    var saving = false;

    final ok = await showShadDialog<bool>(
      context: context,
      barrierDismissible: false,
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
                        // Sesi adalah sumber skor laga, jadi menghapusnya
                        // langsung mengubah hasil dan klasemen. Dulu satu
                        // ketukan cukup dan skor lama hilang tanpa bisa
                        // dibatalkan.
                        if (!await confirm(
                          ctx,
                          'Hapus sesi $nextNo?',
                          'Skor sesi ini dihapus dan skor laga ikut berubah. '
                              'Catatan gol tetap ada.',
                        )) {
                          return;
                        }
                        if (!ctx.mounted) return;
                        setLocal(() => saving = true);
                        final ok = await attempt(
                          ctx,
                          () => MatchSession.delete(session.id, widget.match.id),
                          fail: 'Gagal menghapus sesi',
                        );
                        if (ctx.mounted) Navigator.pop(ctx, ok);
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
                          home: home,
                          away: away,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) {
                          setLocal(() => saving = false);
                          toast(ctx, writeFailText(e, fail: 'Gagal simpan'));
                        }
                      }
                    },
              child: const Text('Simpan'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScoreStepper(
                name: _match.homeName,
                value: home,
                onChanged: saving ? null : (v) => setLocal(() => home = v),
              ),
              const SizedBox(height: 8),
              ScoreStepper(
                name: _match.awayName,
                value: away,
                onChanged: saving ? null : (v) => setLocal(() => away = v),
              ),
              const SizedBox(height: 12),
              Text(
                scoreOutcome(_match.homeName, _match.awayName, home, away),
                textAlign: TextAlign.center,
                style: ShadTheme.of(ctx).textTheme.small,
              ),
            ],
          ),
        ),
      ),
    );
    return ok ?? false;
  }

  /// Papan catat cepat: daftar pemain kedua tim dengan empat tombol per
  /// baris (gol/assist/kuning/merah). Satu ketukan = satu catatan; dialog
  /// tetap terbuka supaya rentetan kejadian dalam satu laga tidak perlu
  /// membuka dialog berkali-kali.
  Future<bool> _openEventPad(BuildContext context) async {
    Map<int, List<Member>> players;
    List<Member> all;
    // Skenario utama papan catat adalah di lapangan, tepat saat sinyal
    // paling buruk. Tanpa guard, kegagalan muat pemain matikan tombol ini
    // tanpa suara — pengguna mengira app rusak. Sesi menit terakhir tetap
    // bisa dicatat begitu sinyal kembali, jadi cukup beri tahu dan batal.
    try {
      players = await Team.players();
      all = await Member.all(activeOnly: true);
    } catch (e) {
      if (!context.mounted) return false;
      toast(context, 'Daftar pemain belum bisa dimuat: ${errText(e)}');
      return false;
    }
    if (!context.mounted) return false;
    if (all.isEmpty) {
      toast(context, 'Tambah anggota dulu');
      return false;
    }

    final m = _match;
    final groups = <(String, List<Member>)>[];
    final home = m.homeTeamId == null ? null : players[m.homeTeamId];
    final away = m.awayTeamId == null ? null : players[m.awayTeamId];
    if (home != null && home.isNotEmpty) groups.add((m.homeName, home));
    if (away != null && away.isNotEmpty) groups.add((m.awayName, away));
    if (groups.isEmpty) groups.add(('Pemain', all));

    var minute = '';
    var minuteError = '';
    var recorded = 0;
    var last = '';
    // Satu tim sekaligus: 8 pemain sudah memenuhi tinggi dialog, dan daftar
    // gabungan dua tim menuntut scroll di dalam dialog — di HP itu gesekan
    // yang tidak perlu saat mencatat sambil menonton.
    var group = 0;
    final minuteCtrl = TextEditingController();

    final ok = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> add(Member member, String type) async {
            // Menit di luar 1–120 bukan sekadar salah ketik: "900" yang
            // dimaksud "9" menaruh kejadian di babak yang tidak pernah ada.
            if (minuteError.isNotEmpty) return;
            try {
              await MatchEvent.insert(
                matchId: m.id,
                memberId: member.id,
                minute: int.tryParse(minute),
                type: type,
              );
              setLocal(() {
                recorded++;
                // Menit dihapus setiap catatan masuk: tanpa itu, gol ke-2
                // dan ke-3 ikut tercatat di menit gol pertama — kesalahan
                // yang tidak terlihat sampai riwayat dibuka.
                minuteCtrl.clear();
                minute = '';
                minuteError = '';
                last = '${MatchEvent.typeLabels[type] ?? type} ${member.name}';
              });
            } catch (e) {
              if (ctx.mounted) toast(ctx, writeFailText(e, fail: 'Gagal'));
            }
          }

          final t = ShadTheme.of(ctx);
          return ShadDialog(
            title: const Text('Catat kejadian'),
            description: Text(
              'Ketuk tombol di baris pemain. Menit opsional — kosongkan kalau '
              'tidak dicatat.',
            ),
            actions: [
              ShadButton(
                onPressed: () => Navigator.pop(ctx, recorded > 0),
                child: Text(recorded == 0 ? 'Tutup' : 'Selesai ($recorded)'),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FieldLabel('Menit kejadian'),
                Row(
                  children: [
                    SizedBox(
                      width: 96,
                      child: ShadInput(
                        controller: minuteCtrl,
                        placeholder: const Text('Menit'),
                        keyboardType: TextInputType.number,
                        // Huruf dan tanda minus tidak bisa masuk sama sekali,
                        // lalu rentangnya diperiksa saat mengetik supaya
                        // pesannya muncul sebelum tombol pemain ditekan.
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        onChanged: (v) => setLocal(() {
                          minute = v;
                          final n = int.tryParse(v);
                          minuteError = v.isEmpty || (n != null && n >= 1 && n <= 120)
                              ? ''
                              : 'Menit 1–120';
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        recorded == 0
                            ? 'Belum ada catatan baru'
                            : '$recorded catatan • terakhir: $last',
                        style: t.textTheme.small.copyWith(
                          color: recorded == 0
                              ? t.colorScheme.mutedForeground
                              : t.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (minuteError.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Semantics(
                      label: 'Menit, $minuteError',
                      child: Text(
                        minuteError,
                        style: t.textTheme.small.copyWith(color: AppThemes.bad(ctx)),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  'Catatan ini tidak mengubah skor — skor laga diisi lewat sesi.',
                  style: t.textTheme.small.copyWith(color: t.colorScheme.mutedForeground),
                ),
                if (groups.length > 1) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 0; i < groups.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _PadTab(
                            label: groups[i].$1,
                            selected: group == i,
                            onTap: () => setLocal(() => group = i),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                // Daftar satu tim (maks 8 pemain) muat tanpa scroll; kalau
                // timnya lebih besar, list ini tetap bisa digeser.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 330),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final p in groups[group].$2)
                          _EventPadRow(member: p, onTap: (type) => add(p, type)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    minuteCtrl.dispose();
    return ok ?? false;
  }
}

/// Satu baris papan catat: nama pemain + empat tombol kejadian.
///
/// Tombol dibuat 44px (area sentuh minimum) dan ikonnya berbeda bentuk
/// (bola, tangan, kotak) supaya bisa ditekan cepat tanpa membaca, termasuk
/// saat mencatat sambil menonton.
class _EventPadRow extends StatelessWidget {
  const _EventPadRow({required this.member, required this.onTap});

  final Member member;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              member.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          _PadButton(
            icon: Icons.sports_soccer,
            color: t.colorScheme.primary,
            label: 'Gol ${member.name}',
            onTap: () => onTap('goal'),
          ),
          _PadButton(
            icon: Icons.handshake_outlined,
            color: t.colorScheme.mutedForeground,
            label: 'Umpan gol ${member.name}',
            onTap: () => onTap('assist'),
          ),
          _PadButton(
            icon: Icons.square_outlined,
            color: AppThemes.cardYellow(context),
            label: 'Kartu kuning ${member.name}',
            onTap: () => onTap('yellow'),
          ),
          _PadButton(
            icon: Icons.square_rounded,
            color: t.colorScheme.destructive,
            label: 'Kartu merah ${member.name}',
            onTap: () => onTap('red'),
          ),
        ],
      ),
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            // 44px = area sentuh minimum: tombol ini ditekan cepat sambil
            // menonton, sering satu tangan dan kadang dengan sarung tangan.
            child: SizedBox(
              width: AppThemes.minTap,
              height: AppThemes.minTap,
              child: Icon(icon, size: 17, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tab pemilih tim di papan catat. Lebar penuh, dua tombol saja.
class _PadTab extends StatelessWidget {
  const _PadTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Material(
      color: selected ? t.colorScheme.primary : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? t.colorScheme.primary : t.colorScheme.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: AppThemes.minTap,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? t.colorScheme.primaryForeground : t.colorScheme.foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
