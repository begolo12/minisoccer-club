import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/soft.dart';
import '../data/auth.dart';
import '../data/models.dart';
import 'fmt.dart';
import 'members.dart';
import 'money_input.dart';
import 'teams.dart';
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
    final id = await showTournamentForm(context);
    await _reload();
    if (id == null || !mounted) return;
    // Buka turnamen yang BARU dibuat (bukan draft pertama): jadwalnya sudah
    // ada di sana, dan tanpa ini pengguna hanya melihat daftar bertambah tanpa
    // tanda bahwa jadwalnya sudah terbentuk.
    final created = await Tournament.byId(id);
    if (created == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TournamentDetailPage(tournament: created)),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Turnamen internal',
      subtitle: 'Tim klub • klasemen per grup',
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
                  message: 'Pilih tim klub, bagi ke grup, dan jadwalnya dibuat otomatis: '
                      'semua tim saling bertemu sekali.',
                  actionLabel: Auth.canWrite ? 'Buat turnamen' : null,
                  onAction: Auth.canWrite ? _create : null,
                ),
              ],
            );
          }
          final running = items.where((t) => t.status == 'running').length;
          final done = items.where((t) => t.status == 'done').length;
          // Satu daftar panjang hanya dibedakan pil kecil di tepi kanan, jadi
          // status tidak terbaca saat memindai. Dikelompokkan: yang berjalan,
          // yang belum dimulai, lalu yang selesai (urutan `Tournament.all`).
          const groups = [
            ('running', 'Berjalan'),
            ('draft', 'Akan datang'),
            ('done', 'Selesai'),
          ];
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              StatStrip(
                children: [
                  StatTile(label: 'Turnamen', value: '${items.length}'),
                  StatTile(
                    label: 'Berjalan',
                    value: '$running',
                    color: ShadTheme.of(context).colorScheme.primary,
                  ),
                  StatTile(label: 'Selesai', value: '$done'),
                ],
              ),
              for (final (status, label) in groups)
                if (items.any((t) => t.status == status)) ...[
                  SectionTitle(label),
                  for (final t in items.where((t) => t.status == status))
                    _TournamentTile(tournament: t, onChanged: _reload),
                ],
              // Status lain (mis. nilai baru dari server) tetap tampil, jangan
              // hilang hanya karena tidak ada di daftar grup di atas.
              for (final t in items.where(
                  (t) => !groups.any((g) => g.$1 == t.status)))
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
    final draft = tournament.status == 'draft';
    // Draft sengaja netral: belum ada yang bisa dikerjakan di sana. Selesai
    // tetap hijau supaya turnamen yang sudah tuntas tidak terbaca "mati".
    final statusColor = draft ? t.colorScheme.mutedForeground : t.colorScheme.primary;
    return RowItem(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TournamentDetailPage(tournament: tournament)),
      ).then((_) => onChanged()),
      leading: Icon(
        draft ? Icons.emoji_events_outlined : Icons.emoji_events,
        size: 18,
        color: statusColor,
      ),
      title: tournament.name,
      // Yang dicari saat melihat daftar: kapan dan di mana. Jumlah grup
      // cukup satu kata supaya tetap muat satu baris di HP.
      subtitle: [
        if (tournament.groups > 1) '${tournament.groups} grup',
        '${fmtShortDate(tournament.startsAt)} ${fmtTime(tournament.startsAt)}',
        if (tournament.venue?.isNotEmpty ?? false) tournament.venue!,
      ].join(' • '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pill(
            Tournament.statusLabels[tournament.status] ?? tournament.status,
            color: statusColor,
          ),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, size: 18, color: t.colorScheme.mutedForeground),
        ],
      ),
    );
  }
}

// ---------- Detail ----------

class _Data {
  _Data({
    required this.groups,
    required this.matches,
    required this.teams,
    required this.players,
    this.failures = const [],
  });

  /// Klasemen per grup: {groupNo: [Standing...]}.
  final Map<int, List<Standing>> groups;
  final List<TournamentMatch> matches;
  final List<Team> teams;
  final Map<int, List<Member>> players;

  /// Sumber yang gagal dimuat; jadwal tetap tampil walau klasemen bermasalah.
  final List<String> failures;

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

  /// Salinan turnamen yang bisa diperbarui. `widget.tournament` tidak pernah
  /// berubah, jadi setelah nominal iuran diubah, tampilan akan tetap
  /// menampilkan angka lama kalau hanya membaca dari widget.
  late Tournament _t = widget.tournament;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Data> _load() async {
    final id = widget.tournament.id;
    final results = await Future.wait<Soft<Object?>>([
      soft('Jadwal turnamen', () => TournamentMatch.forTournament(id),
          fallback: const <TournamentMatch>[]),
      soft('Tim peserta', () => Team.forTournament(id), fallback: const <Team>[]),
      soft('Pemain tim', () => Team.players(tournamentId: id),
          fallback: const <int, List<Member>>{}),
      soft('Klasemen grup', () => Tournament.standingsByGroup(id),
          fallback: const <int, List<Standing>>{}),
      soft('Turnamen', () => Tournament.byId(id), fallback: null),
    ]);
    final failures = settle(results);
    final fresh = results[4].value as Tournament?;
    if (fresh != null) _t = fresh;
    return _Data(
      groups: results[3].value! as Map<int, List<Standing>>,
      matches: results[0].value! as List<TournamentMatch>,
      teams: results[1].value! as List<Team>,
      players: results[2].value! as Map<int, List<Member>>,
      failures: failures,
    );
  }

  Future<void> _reload() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  /// Tambah/lepas tim setelah turnamen dibuat. `Tournament.updateTeams`
  /// menolak kalau sudah ada laga berskor — jadwal baru akan menempelkan
  /// hasil lama ke pasangan tim yang berbeda.
  Future<void> _manageTeams() async {
    // Await sebelum dialog bisa gagal; tanpa try/catch tombol "Kelola tim"
    // diam saja saat jaringan/server bermasalah.
    final List<Team> all;
    final List<Team> current;
    try {
      all = await Team.all();
      if (!mounted) return;
      current = await Team.forTournament(widget.tournament.id);
    } catch (e) {
      if (mounted) toast(context, 'Gagal memuat tim: ${errText(e)}');
      return;
    }
    if (!mounted) return;
    // Jumlah grup dibaca dari data terbaru (tim peserta), bukan dari
    // `widget.tournament` yang tidak pernah dimuat ulang setelah
    // `updateTeams` mengubah kolom `groups`.
    final groupsNow = current.isEmpty
        ? widget.tournament.groups
        : current.map((t) => t.groupNo).reduce((a, b) => a > b ? a : b);
    final ok = await showTournamentTeamsForm(
      context,
      allTeams: all,
      selected: current.map((t) => t.id).toSet(),
      groups: groupsNow,
      startsAt: widget.tournament.startsAt,
      matchMinutes: widget.tournament.matchMinutes,
      breakMinutes: widget.tournament.breakMinutes,
      onSave: (ids, groups) => Tournament.updateTeams(
        widget.tournament.id,
        ids,
        startsAt: widget.tournament.startsAt,
        matchMinutes: widget.tournament.matchMinutes,
        breakMinutes: widget.tournament.breakMinutes,
        groups: groups,
      ),
    );
    if (ok) await _reload();
  }

  /// Ubah nominal iuran turnamen.
  ///
  /// Dipisah dari form "atur tim" karena nominal bisa perlu dikoreksi kapan
  /// saja — termasuk saat turnamen sudah berjalan, ketika jadwal tidak boleh
  /// diubah lagi.
  Future<void> _editFee() async {
    final fee = TextEditingController(
      text: _t.entryFee > 0
          ? fmtNumber(_t.entryFee)
          : '',
    );
    var saving = false;
  final ok = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Future<void> save() async {
            setLocal(() => saving = true);
            final value = parseFormattedMoney(fee.text);
            try {
              await Tournament.setEntryFee(widget.tournament.id, value);
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) {
              if (ctx.mounted) toast(ctx, 'Gagal menyimpan: ${errText(e)}');
            } finally {
              if (ctx.mounted) setLocal(() => saving = false);
            }
          }

          return ShadDialog(
            title: const Text('Iuran turnamen'),
            description: const Text('Nominal per anggota untuk turnamen ini.'),
            actions: [
              ShadButton.outline(
                onPressed: saving ? null : () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              SaveButton(saving: saving, onPressed: save),
            ],
            child: MoneyField(controller: fee, autofocus: true),
          );
        },
      ),
    );
    if (ok == true) await _reload();
  }

  Future<void> _delete() async {
    // Peringatan harus jujur soal uang: `payments.tournament_id` memakai
    // ON DELETE CASCADE, jadi catatan iuran turnamen ini ikut terhapus dan
    // pemasukan iuran di Kas bulan-bulan lalu berkurang. Tanpa kalimat itu,
    // bendahara bisa menghapus turnamen lama dan mendapati saldo kas berubah
    // tanpa tahu sebabnya. (Pola yang sama sudah dipakai saat menghapus
    // anggota.)
    if (!await confirm(
      context,
      'Hapus turnamen?',
      'Jadwal, skor, dan CATATAN IURAN turnamen ini ikut terhapus, sehingga '
          'pemasukan iuran di Kas bulan lalu berkurang. Tim klub tetap ada. '
          'Kalau hanya ingin menutup turnamen, ubah statusnya jadi Selesai.',
    )) {
      return;
    }
    if (!mounted) return;
    if (!await attempt(context, () => Tournament.delete(widget.tournament.id), fail: 'Gagal menghapus')) {
      return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: widget.tournament.name,
      subtitle: [
        // Status disebut di sini: daftar mengelompokkannya, dan halaman detail
        // yang dibuka dari tautan mana pun harus menyebut keadaannya sendiri.
        Tournament.statusLabels[widget.tournament.status] ?? widget.tournament.status,
        fmtDateTime(widget.tournament.startsAt),
        if (widget.tournament.venue?.isNotEmpty ?? false) widget.tournament.venue!,
      ].join(' • '),
      actions: [
        if (Auth.canWrite)
          iconAction(context, Icons.group_add_outlined, _manageTeams, tooltip: 'Kelola tim'),
        if (Auth.canWrite) iconAction(context, Icons.delete_outline, _delete, tooltip: 'Hapus'),
      ],
      child: AsyncView<_Data>(
        future: _future,
        onRefresh: _reload,
        builder: (d) {
          final last = d.matches.isEmpty ? null : d.matches.last.kickoff;
          final end = last?.add(Duration(minutes: widget.tournament.matchMinutes));
          final doneCount = d.matches.where((m) => m.done).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              if (d.failures.isNotEmpty) DegradedNotice(failures: d.failures, onRetry: _reload),
              StatStrip(
                children: [
                  StatTile(label: 'Tim', value: '${d.teams.length}'),
                  StatTile(
                    label: 'Laga',
                    value: '$doneCount/${d.matches.length}',
                    hint: 'selesai',
                  ),
                  // Sebelum turnamen usai, jam ini baru perkiraan — jangan
                  // diberi label "Selesai" seolah sudah lewat. Status diambil
                  // dari hasil laga, bukan dari objek yang dibuka halaman ini,
                  // supaya label ikut berubah begitu laga terakhir diisi.
                  StatTile(
                    label: d.matches.isNotEmpty && doneCount == d.matches.length
                        ? 'Selesai'
                        : 'Perkiraan selesai',
                    value: end == null ? '—' : fmtTime(end),
                    hint: '${widget.tournament.matchMinutes} menit/laga',
                    color: t.colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: d.matches.isEmpty ? 0 : doneCount / d.matches.length,
                  minHeight: 5,
                  backgroundColor: t.colorScheme.muted,
                  color: t.colorScheme.primary,
                ),
              ),
              // Iuran turnamen: nominal per anggota. Bisa diubah kapan saja,
              // termasuk saat turnamen sudah berjalan — nominal yang salah
              // ketik tidak boleh memaksa jadwal dibuat ulang.
              RowItem(
                leading: Icon(Icons.payments_outlined, size: 15, color: t.colorScheme.mutedForeground),
                title: 'Iuran per anggota',
                subtitle: _t.entryFee > 0
                    ? fmtMoney(_t.entryFee)
                    : 'Belum diisi',
                trailing: Auth.canWrite
                    ? TextButton(
                        onPressed: () => _editFee(),
                        child: const Text('Ubah'),
                      )
                    : null,
              ),
              // Belum ada laga selesai = semua angka nol. Tabel kosong seperti
              // itu tidak memberi informasi; satu baris cukup sampai skor
              // pertama diisi.
              if (doneCount == 0) ...[
                const SectionTitle('Klasemen'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Klasemen muncul setelah laga pertama selesai.',
                    style: t.textTheme.muted,
                  ),
                ),
              ] else
                for (final entry in d.groups.entries) ...[
                  SectionTitle(d.groups.length > 1 ? 'Klasemen grup ${entry.key}' : 'Klasemen'),
                  StandingsTable(standings: entry.value, top: 2),
                ],
              const SectionTitle('Jadwal'),
              if (d.matches.isEmpty)
                Text('Belum ada jadwal.', style: t.textTheme.muted)
              else
                for (final m in d.matches)
                  _MatchTile(match: m, data: d, onChanged: _reload),
              const SectionTitle('Pemain per tim'),
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

class _MatchTile extends StatelessWidget {
  const _MatchTile({required this.match, required this.data, required this.onChanged});

  final TournamentMatch match;
  final _Data data;
  final Future<void> Function() onChanged;

  Future<void> _openScore(BuildContext context) async {
    final homeName = data.name(match.homeTeamId);
    final awayName = data.name(match.awayTeamId);
    final action = await showScoreForm(
      context,
      title: '$homeName vs $awayName',
      subtitle: 'Grup ${match.groupNo} • Babak ${match.round} • ${fmtTime(match.kickoff)}',
      home: match.scoreHome,
      away: match.scoreAway,
      canReset: match.done,
      homeName: homeName,
      awayName: awayName,
    );
    if (!context.mounted) return;
    if (action == 'reset') {
      await attempt(context, () => match.clearScore(), fail: 'Gagal menyimpan skor');
    } else if (action is (int, int)) {
      // Toast sukses hanya kalau simpan benar-benar berhasil. Sebelumnya
      // pesan "Hasil tersimpan" tetap muncul saat gagal dan menimpa pesan
      // error dari attempt(), jadi user mengira skor tersimpan.
      final saved = await attempt(context, () => match.saveScore(action.$1, action.$2),
          fail: 'Gagal menyimpan skor');
      if (!saved) {
        await onChanged();
        return;
      }
      if (context.mounted) toast(context, 'Hasil tersimpan · klasemen diperbarui');
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
            border: Border(bottom: BorderSide(color: t.colorScheme.border)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fmtTime(match.kickoff),
                      style: t.textTheme.table.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text('G${match.groupNo} • B${match.round}', style: t.textTheme.small),
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
                width: 58,
                child: Text(
                  done ? '${match.scoreHome}–${match.scoreAway}' : 'vs',
                  textAlign: TextAlign.center,
                  style: done
                      ? t.textTheme.h2.copyWith(
                          fontSize: 19,
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
              // Laga yang belum ada skornya dapat tombol langsung, supaya
              // menyelesaikan pertandingan tidak perlu menebak baris bisa ditekan.
              if (Auth.canWrite && !done) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Selesai pertandingan',
                  child: Material(
                    color: t.colorScheme.muted.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(7),
                    child: InkWell(
                      onTap: () => _openScore(context),
                      borderRadius: BorderRadius.circular(7),
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: Icon(Icons.check, size: 16, color: t.colorScheme.foreground),
                      ),
                    ),
                  ),
                ),
              ],
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

  Future<void> _addPlayer(BuildContext context) async {
    // Tanpa try/catch, tombol ini diam total saat jaringan bermasalah — dan
    // justru di halaman inilah orang melengkapi pemain.
    final List<Member> all;
    try {
      all = await Member.all(activeOnly: true);
    } catch (e) {
      if (context.mounted) toast(context, 'Gagal memuat anggota: ${errText(e)}');
      return;
    }
    if (!context.mounted) return;
    final taken = players.map((p) => p.id).toSet();
    final free = all.where((m) => !taken.contains(m.id)).toList();
    if (free.isEmpty) {
      // Dua sebab berbeda, dan keduanya butuh jalan keluar yang bisa diketuk.
      final add = await showShadDialog<bool>(
        context: context,
        builder: (ctx) => ShadDialog(
          title: Text(all.isEmpty ? 'Belum ada anggota' : 'Semua anggota sudah masuk'),
          description: Text(
            all.isEmpty
                ? 'Tim diisi dari daftar anggota klub. Tambah anggota dulu, lalu '
                    'kembali ke sini untuk memasukkannya ke ${team.name}.'
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
      if (add == true && context.mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MembersPage()));
      }
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
          // Tanpa lebar tetap: 320px + padding dialog meluber di layar 320px.
          // Dialog mengikuti lebar maksimum bawaan, sama seperti pemilih
          // pemain di halaman Tim.
          height: 320,
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
    if (picked == null) return;
    if (!context.mounted) return;
    if (await attempt(context, () => Team.addPlayer(team.id, picked.id), fail: 'Gagal menambah pemain')) {
      await onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    // Dulu: Panel bertepi berisi chip bertepi. Dua tingkat garis untuk satu
    // daftar nama, dan tiap pemain membawa kotak × sendiri. Sekarang satu
    // tingkat: kepala tim, lalu baris bergaris per pemain.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Row(
            children: [
              Expanded(
                child: Row(children: [
                  Flexible(
                    child: Text(
                      team.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('Grup ${team.groupNo}', style: t.textTheme.small),
                ]),
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
        ),
        if (players.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Belum ada pemain', style: t.textTheme.small),
          )
        else
          for (final p in players)
            RowItem(
              title: p.name,
              subtitle: [p.position, if (p.jersey != null) '#${p.jersey}'].join(' • '),
              trailing: Auth.canWrite
                  ? iconAction(
                      context,
                      Icons.close,
                      () async {
                        if (await attempt(context,
                            () => Team.removePlayer(team.id, p.id),
                            fail: 'Gagal mengeluarkan pemain')) {
                          await onChanged();
                        }
                      },
                      tooltip: 'Keluarkan dari tim',
                      bordered: false,
                    )
                  : null,
            ),
      ],
    );
  }
}

// ---------- Form ----------

/// Batas jumlah grup: tiap grup minimal 2 tim, maksimal 4 grup. 3 tim hanya
/// bisa 1 grup — grup berisi 1 tim tidak akan pernah mendapat laga.
int groupCap(int teams) => teams < 4 ? 1 : (teams ~/ 2).clamp(1, 4);

/// Form buat turnamen. Return id turnamen yang baru dibuat, atau null kalau
/// dibatalkan.
///
/// Id (bukan `true`) supaya pemanggil bisa langsung membuka turnamen itu:
/// sebelumnya `_create` menebak lewat "draft pertama", sehingga klub yang sudah
/// punya draft lama mendarat di turnamen yang salah.
Future<int?> showTournamentForm(BuildContext context) async {
  final List<Team> teams;
  try {
    teams = await Team.all();
  } catch (e) {
    // Tanpa ini tombol "Buat turnamen" diam total saat jaringan bermasalah.
    if (context.mounted) toast(context, 'Gagal memuat tim: ${errText(e)}');
    return null;
  }
  if (!context.mounted) return null;
  if (teams.length < 2) {
    // Toast hilang sendiri dan tidak bisa diklik. Klub baru justru berhenti di
    // sini, jadi tawarkan jalan ke halaman yang menyelesaikannya.
    final go = await showShadDialog<bool>(
      context: context,
      builder: (ctx) => ShadDialog(
        title: const Text('Butuh minimal 2 tim'),
        description: Text(
          'Turnamen mempertemukan tim satu sama lain, jadi butuh minimal dua tim. '
          'Saat ini klub punya ${teams.length} tim.',
        ),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Nanti'),
          ),
          ShadButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Buat tim'),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const TeamsPage()));
    }
    return null;
  }

  // Jumlah pemain per tim: prasyarat penagihan iuran, tetapi tidak pernah
  // terlihat di form ini sebelumnya.
  Map<int, int> counts = const {};
  try {
    counts = await Team.playerCounts();
  } catch (_) {
    // Tidak menghalangi pembuatan turnamen; baris tim tampil tanpa angka.
  }
  if (!context.mounted) return null;
  final name = TextEditingController(
    text: 'Turnamen Internal ${fmtDate(DateTime.now())}',
  );
  final venue = TextEditingController();
  final fee = TextEditingController();
  final minutes = TextEditingController(text: '20');
  final breakMin = TextEditingController(text: '0');
  var selected = teams.map((t) => t.id).toSet();
  var groups = 1;
  var date = DateTime.now().add(const Duration(days: 1));
  var time = const TimeOfDay(hour: 20, minute: 0);
  var saving = false;
  int? createdId;

  final ok = await showShadDialog<bool>(
    context: context,
    // Form tulis: barrier tidak boleh menutup dialog di tengah simpan.
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        // Durasi dijepit, bukan dipercaya: kolom angka ini bisa diisi 0 atau
        // negatif, dan jadwal yang lahir dari situ menyusut/k mundur —
        // semua laga kickoff di menit yang sama. Non-numerik jatuh ke 20.
        final per = (int.tryParse(minutes.text) ?? 20).clamp(1, 180);
        final rest = (int.tryParse(breakMin.text) ?? 0).clamp(0, 60);
        final count = selected.length;
        // Tiap grup butuh minimal 2 tim; 3 tim tidak bisa dibagi 2 grup.
        final maxGroups = groupCap(count);
        final groupCount = groups.clamp(1, maxGroups);
        // `assignGroups` membagi tim dengan pola snake: grup di depan dapat
        // satu tim lebih banyak kalau jumlahnya tidak habis dibagi. Estimasi
        // harus memakai ukuran grup sebenarnya, bukan rata-rata — 5 tim /
        // 2 grup menghasilkan 3+2 tim, yaitu 4 laga, bukan 2.
        final matches = count < 2
            ? 0
            : () {
                var n = 0;
                for (var g = 0; g < groupCount; g++) {
                  final size = count ~/ groupCount + (g < count % groupCount ? 1 : 0);
                  n += size * (size - 1) ~/ 2;
                }
                return n;
              }();
        // Laga terakhir tidak diikuti jeda, jadi jeda dihitung (laga - 1).
        final total = matches == 0 ? 0 : matches * per + (matches - 1) * rest;

        Future<void> save() async {
          if (name.text.trim().isEmpty) {
            toast(ctx, 'Nama turnamen tidak boleh kosong');
            return;
          }
          if (selected.length < 2) {
            toast(ctx, 'Pilih minimal 2 tim');
            return;
          }
          if (matches == 0) {
            toast(ctx, 'Tiap grup butuh minimal 2 tim');
            return;
          }
          setLocal(() => saving = true);
          try {
            final start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
            createdId = await Tournament.create(
              name: name.text.trim(),
              venue: venue.text.trim().isEmpty ? null : venue.text.trim(),
              startsAt: start,
              teamIds: selected.toList(),
              matchMinutes: per,
              breakMinutes: rest,
              groups: groupCount,
              entryFee: parseFormattedMoney(fee.text),
            );
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) toast(ctx, 'Gagal buat turnamen: ${errText(e)}');
          } finally {
            if (ctx.mounted) setLocal(() => saving = false);
          }
        }

        return ShadDialog(
          title: const Text('Turnamen baru'),
          description: Text('$count tim • $groupCount grup • $matches laga • '
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
                ShadInput(controller: name, placeholder: const Text('Nama turnamen'), autofocus: true, textInputAction: TextInputAction.next),
                const SizedBox(height: 10),
                ShadInput(controller: venue, placeholder: const Text('Lokasi (opsional)'), textInputAction: TextInputAction.next),
                const SizedBox(height: 10),
                // Iuran per anggota untuk turnamen ini. Beda tiap turnamen
                // karena biaya pendaftaran dan jumlah pemainnya berbeda.
                MoneyField(
                  controller: fee,
                  placeholder: const Text('Iuran per anggota (opsional)'),
                ),
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
                  placeholder: const Text('Jumlah grup'),
                  initialValue: groups,
                  // Tiap grup butuh minimal 2 tim. Grup berisi 1 tim tidak
                  // pernah mendapat laga, jadi pilihannya dibatasi — 3 tim
                  // hanya bisa 1 grup.
                  options: [
                    for (var g = 1; g <= maxGroups; g++)
                      ShadOption(value: g, child: Text('$g grup')),
                  ],
                  selectedOptionBuilder: (c, v) => Text('$v grup'),
                  onChanged: (v) => setLocal(() => groups = v ?? 1),
                ),
                const SizedBox(height: 14),
                Text('Pilih tim yang ikut', style: ShadTheme.of(ctx).textTheme.small),
                const SizedBox(height: 4),
                // ShadDialog tidak menyediakan Material: tanpa ini CheckboxListTile
                // tampil sebagai kotak abu-abu tanpa teks.
                Material(
                  type: MaterialType.transparency,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final team in teams)
                          InkWell(
                            onTap: () => setLocal(() {
                              if (selected.contains(team.id)) {
                                selected.remove(team.id);
                              } else {
                                selected.add(team.id);
                              }
                              if (groups > groupCap(selected.length)) {
                                groups = groupCap(selected.length);
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: selected.contains(team.id),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (v) => setLocal(() {
                                      if (v == true) {
                                        selected.add(team.id);
                                      } else {
                                        selected.remove(team.id);
                                      }
                                      if (groups > groupCap(selected.length)) {
                                        groups = groupCap(selected.length);
                                      }
                                    }),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            team.name,
                                            style: const TextStyle(fontSize: 13.5),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Tim tanpa pemain tidak bisa ditagih
                                        // iurannya; sebutkan di sini, bukan
                                        // setelah turnamen dibuat.
                                        Text(
                                          '${counts[team.id] ?? 0} pemain',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: (counts[team.id] ?? 0) == 0
                                                ? AppThemes.bad(ctx)
                                                : ShadTheme.of(ctx).colorScheme.mutedForeground,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Jadwal dibuat otomatis di tiap grup: semua tim saling bertemu '
                  'sekali. Pemain tiap tim diatur di menu Tim.',
                  style: ShadTheme.of(ctx).textTheme.small,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  return (ok ?? false) ? createdId : null;
}

/// Dialog skor. Return `(home, away)`, string `'reset'`, atau null kalau batal.
/// Skor diatur lewat stepper: tidak perlu membuka keyboard untuk 0–5 gol.
Future<Object?> showScoreForm(
  BuildContext context, {
  required String title,
  required String subtitle,
  int? home,
  int? away,
  bool canReset = false,
  String homeName = 'Tuan rumah',
  String awayName = 'Tamu',
}) async {
  var h = home ?? 0;
  var a = away ?? 0;
  // Sama seperti laga internal: 0–0 pada laga yang belum punya skor harus
  // dikonfirmasi sekali lagi, karena satu ketukan tidak boleh mengubah
  // klasemen menjadi seri.
  var confirmZero = false;

  final result = await showShadDialog<Object>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final t = ShadTheme.of(ctx);
        final done = home != null && away != null;
        return ShadDialog(
          title: Text(title),
          description: Text(subtitle),
          actions: [
            if (canReset)
              ShadButton.ghost(
                onPressed: () => Navigator.pop(ctx, 'reset'),
                child: const Text('Atur ulang'),
              ),
            ShadButton.outline(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ShadButton(
              onPressed: () {
                if (!done && h == 0 && a == 0 && !confirmZero) {
                  setLocal(() => confirmZero = true);
                  return;
                }
                Navigator.pop(ctx, (h, a));
              },
              leading: const Icon(Icons.check, size: 16),
              child: Text(
                confirmZero ? 'Yakin 0–0?' : (done ? 'Simpan koreksi' : 'Selesai pertandingan'),
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScoreStepper(
                name: homeName,
                value: h,
                onChanged: (v) => setLocal(() {
                  h = v;
                  confirmZero = false;
                }),
              ),
              const SizedBox(height: 8),
              ScoreStepper(
                name: awayName,
                value: a,
                onChanged: (v) => setLocal(() {
                  a = v;
                  confirmZero = false;
                }),
              ),
              if (confirmZero) ...[
                const SizedBox(height: 10),
                Text(
                  'Tekan sekali lagi untuk mencatat hasil 0–0 sebagai seri.',
                  textAlign: TextAlign.center,
                  style: t.textTheme.small.copyWith(color: t.colorScheme.destructive),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: t.colorScheme.muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Text(
                      scoreOutcome(homeName, awayName, h, a),
                      textAlign: TextAlign.center,
                      style: t.textTheme.large.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Menang 3 poin · seri 1 poin · kalah 0',
                      textAlign: TextAlign.center,
                      style: t.textTheme.small,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (result is (int, int) || result == 'reset') return result;
  return null;
}

/// Dialog kelola tim turnamen yang sudah ada. Memakai pemilih yang sama
/// dengan form pembuatan (checkbox + jumlah grup), tapi menyimpan lewat
/// [onSave] supaya aturan "sudah ada skor" dicek di model, bukan di UI.
Future<bool> showTournamentTeamsForm(
  BuildContext context, {
  required List<Team> allTeams,
  required Set<int> selected,
  required int groups,
  required DateTime startsAt,
  required int matchMinutes,
  required int breakMinutes,
  required Future<void> Function(List<int> teamIds, int groups) onSave,
}) async {
  var picked = {...selected};
  var groupCount = groups.clamp(1, groupCap(picked.length));
  var saving = false;

  final ok = await showShadDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final cap = groupCap(picked.length);
        if (groupCount > cap) groupCount = cap;
        final count = picked.length;
        final matches = count < 2
            ? 0
            : () {
                var n = 0;
                for (var g = 0; g < groupCount; g++) {
                  final size = count ~/ groupCount + (g < count % groupCount ? 1 : 0);
                  n += size * (size - 1) ~/ 2;
                }
                return n;
              }();

        Future<void> save() async {
          if (count < 2) {
            toast(ctx, 'Pilih minimal 2 tim');
            return;
          }
          setLocal(() => saving = true);
          try {
            await onSave(picked.toList(), groupCount);
            if (ctx.mounted) Navigator.pop(ctx, true);
          } catch (e) {
            if (ctx.mounted) {
              setLocal(() => saving = false);
              toast(ctx, errText(e));
            }
          }
        }

        final t = ShadTheme.of(ctx);
        return ShadDialog(
          title: const Text('Kelola tim'),
          description: Text(
            '$count tim • $groupCount grup • $matches laga. '
            'Jadwal dibuat ulang dari awal.',
          ),
          actions: [
            ShadButton.outline(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            ShadButton(
              onPressed: saving ? null : save,
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Buat ulang jadwal'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ShadSelect<int>(
                placeholder: const Text('Jumlah grup'),
                initialValue: groupCount,
                options: [
                  for (var g = 1; g <= cap; g++)
                    ShadOption(value: g, child: Text('$g grup')),
                ],
                selectedOptionBuilder: (c, v) => Text('$v grup'),
                onChanged: saving ? null : (v) => setLocal(() => groupCount = v ?? 1),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 260,
                child: Material(
                  type: MaterialType.transparency,
                  child: ListView(
                    children: [
                      for (final team in allTeams)
                        CheckboxListTile(
                          value: picked.contains(team.id),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(team.name, style: const TextStyle(fontSize: 13.5)),
                          onChanged: saving
                              ? null
                              : (v) => setLocal(() {
                                    if (v == true) {
                                      picked.add(team.id);
                                    } else {
                                      picked.remove(team.id);
                                    }
                                    final nextCap = groupCap(picked.length);
                                    if (groupCount > nextCap) groupCount = nextCap;
                                  }),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Laga yang sudah punya skor tidak bisa dijadwalkan ulang. '
                'Atur ulang skornya dulu di daftar jadwal.',
                style: t.textTheme.small,
              ),
            ],
          ),
        );
      },
    ),
  );
  return ok ?? false;
}
