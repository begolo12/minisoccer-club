import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/soft.dart';
import '../data/auth.dart';
import '../data/models.dart';
import 'announcements.dart';
import 'bookings.dart';
import 'finance.dart';
import 'teams.dart';
import 'fmt.dart';
import 'login_gate.dart';
import 'forms.dart';
import 'matches.dart';
import 'members.dart';
import 'theme.dart';
import 'tournament.dart';
import 'widgets.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardData {
  final List<Match> upcoming;
  final List<Tournament> tournaments;
  final List<int> stats;
  final int members;
  final double income;
  final CashSummary cash;
  final List<Announcement> news;
  final List<Member> unpaid;
  final double? dues;

  /// Turnamen yang tagihannya ditampilkan di beranda (yang sedang berjalan,
  /// atau yang terdekat). Iuran ditarik per turnamen, jadi "belum bayar"
  /// selalu merujuk ke satu turnamen tertentu.
  final Tournament? activeTournament;
  final List<Team> teams;
  final Map<int, String> teamNames;

  /// Berapa tim yang sudah punya minimal satu pemain. Dipakai beranda untuk
  /// menuntun ke langkah yang benar, bukan menyuruh membuat turnamen pada klub
  /// yang timnya masih kosong.
  final int teamsReady;

  /// Sumber yang gagal dimuat; beranda tetap tampil dengan data lain.
  final List<String> failures;

  /// False kalau daftar iuran bulan ini gagal dimuat. Dipakai supaya
  /// "belum bayar" tidak disimpulkan dari daftar kosong: saat query gagal,
  /// semua anggota akan tampak menunggak padahal datanya tidak diketahui.
  final bool paymentsKnown;

  /// False kalau daftar anggota aktif gagal dimuat. Kebalikannya berbahaya:
  /// daftar kosong membuat beranda menulis "semua anggota sudah lunas".
  final bool membersKnown;

  /// False kalau iuran atau kas bulan ini gagal dimuat. "Belum ada pemasukan"
  /// hanya boleh dikatakan kalau kedua sumber itu benar-benar terbaca.
  final bool cashKnown;

  /// True kalau pengguna belum masuk, sehingga kas & iuran TIDAK diminta.
  ///
  /// Server menolak membacanya tanpa sesi (`api/_guard.js`), jadi meminta
  /// hanya menghasilkan 403 dan baris "gagal dimuat" — padahal tidak ada
  /// yang rusak. Beranda menampilkan ajakan masuk di tempat angka uang.
  final bool moneyLocked;

  _DashboardData({
    required this.upcoming,
    required this.tournaments,
    required this.stats,
    required this.members,
    required this.income,
    required this.cash,
    required this.news,
    required this.unpaid,
    required this.dues,
    this.activeTournament,
    required this.teams,
    required this.teamNames,
    this.teamsReady = 0,
    this.failures = const [],
    this.paymentsKnown = true,
    this.membersKnown = true,
    this.cashKnown = true,
    this.moneyLocked = false,
  });

  /// Laga yang sedang berlangsung — satu-satunya laga yang layak jadi papan
  /// skor di beranda. Jadwal lain dibaca lewat turnamen.
  Match? get liveMatch {
    for (final m in upcoming) {
      if (m.ongoing) return m;
    }
    return null;
  }

  /// Turnamen terakhir: yang sedang berjalan, kalau tidak ada, yang paling
  /// baru selesai. Draft tidak dihitung — belum ada hasil untuk ditampilkan.
  Tournament? get lastTournament {
    for (final t in tournaments) {
      if (t.status == 'running') return t;
    }
    for (final t in tournaments) {
      if (t.status == 'done') return t;
    }
    return null;
  }

  /// Turnamen terdekat yang belum dimulai. Draft ikut dihitung: turnamen
  /// memang disiapkan lebih dulu, dan justru itu yang perlu diumumkan.
  Tournament? get nextTournament {
    final now = DateTime.now();
    Tournament? best;
    for (final t in tournaments) {
      // Turnamen yang sudah berjalan sedang tampil di kartu "terakhir";
      // menampilkannya lagi sebagai "berikutnya" cuma mengulang.
      if (t.status == 'running' || t.status == 'done') continue;
      if (!t.startsAt.isAfter(now)) continue;
      if (best == null || t.startsAt.isBefore(best.startsAt)) best = t;
    }
    return best;
  }

  /// Muat semua sumber. Satu sumber yang gagal (izin DB, tabel belum ada,
  /// jaringan putus sesaat) tidak mematikan seluruh beranda: yang berhasil
  /// tetap tampil, dan [failures] menyebut sumber mana yang bermasalah.
  ///
  /// Semua permintaan dijalankan paralel: beranda punya 13 sumber, dan
  /// menjalankannya berurutan berarti 13 kali bolak-balik ke server sebelum
  /// layar terisi.
  static Future<_DashboardData> load() async {
    final period = periodNow();
    // Uang klub hanya untuk yang sudah masuk. Sumbernya tetap dijalankan
    // (dengan nilai kosong) supaya indeks di bawah tidak berubah; yang
    // berbeda adalah tidak ada permintaan ke server untuk tamu.
    final money = Auth.signedIn;
    final r = await Future.wait<Soft<Object?>>([
      soft('Jadwal laga', Match.upcoming, fallback: const <Match>[]),
      soft('Turnamen', Tournament.all, fallback: const <Tournament>[]),
      soft('Rekap laga', Match.stats, fallback: const [0, 0, 0, 0, 0]),
      soft('Jumlah anggota', Member.countActive, fallback: 0),
      soft('Pengumuman', Announcement.all, fallback: const <Announcement>[]),
      soft('Iuran bulan ini',
          () => money ? Payment.inMonth(DateTime.now()) : Future.value(const <Payment>[]),
          fallback: const <Payment>[]),
      soft('Kas bulan ini',
          () => money ? Transaction.all(period: period) : Future.value(const <Transaction>[]),
          fallback: const <Transaction>[]),
      soft('Daftar tim', Team.all, fallback: const <Team>[]),
      // Jumlah pemain per tim: menentukan apakah klub sudah siap membuat
      // turnamen. Tanpa ini beranda menyuruh "Susun turnamen" pada klub yang
      // timnya masih kosong, dan turnamennya berakhir tanpa peserta tagihan.
      soft('Pemain per tim', Team.playerCounts, fallback: const <int, int>{}),
    ]);
    // Semua sumber gagal = server/jaringan mati, bukan satu tabel: layar error
    // penuh dengan tombol coba lagi lebih jelas daripada beranda kosong.
    final failures = settle(r);

    final upcoming = r[0].value! as List<Match>;
    final tournaments = r[1].value! as List<Tournament>;
    final stats = r[2].value! as List<int>;
    final memberCount = r[3].value! as int;
    final news = r[4].value! as List<Announcement>;
    final payments = r[5].value! as List<Payment>;
    final transactions = r[6].value! as List<Transaction>;
    final teams = r[7].value! as List<Team>;
    final playerCounts = r[8].value! as Map<int, int>;

    // Tagihan "belum bayar" mengikuti TURNAMEN AKTIF, bukan bulan: iuran
    // ditarik per turnamen dan pesertanya berbeda-beda tiap turnamen.
    // Turnamen aktif = yang sedang berjalan, kalau tidak ada yang paling
    // dekat jadwalnya di antara draft, kalau tidak ada yang terakhir selesai.
    Tournament? active;
    for (final t in tournaments) {
      if (t.status == 'running') {
        active = t;
        break;
      }
    }
    if (active == null) {
      for (final t in tournaments) {
        if (t.status == 'draft') {
          active = t;
          break;
        }
      }
    }
    active ??= tournaments.isEmpty ? null : tournaments.first;

    var bill = const <DuesRow>[];
    var billKnown = true;
    if (active != null && money) {
      final b = await soft('Iuran turnamen', () => Payment.bill(active!.id),
          fallback: const <DuesRow>[]);
      failures.addAll(settle([b]));
      bill = b.value!;
      billKnown = b.ok;
    }

    final cash = CashSummary.fromEntries(mergeCashLedger(
      payments: payments,
      transactions: transactions,
    ));
    return _DashboardData(
      upcoming: upcoming,
      tournaments: tournaments,
      stats: stats,
      members: memberCount,
      income: cash.dues,
      cash: cash,
      news: news,
      unpaid: bill.where((r) => !r.paid).map((r) => r.member).toList(),
      dues: active?.entryFee,
      activeTournament: active,
      teams: teams,
      teamNames: {for (final t in teams) t.id: t.name},
      teamsReady: teams.where((t) => (playerCounts[t.id] ?? 0) > 0).length,
      failures: failures,
      // `r[5]` = iuran bulan ini. Kalau gagal, daftar kosongnya BUKAN fakta:
      // jangan menuduh semua orang menunggak, dan jangan menulis "semua lunas".
      paymentsKnown: r[5].ok,
      // Daftar tagihan turnamen juga bisa gagal sendiri (mis. tabel peserta
      // kosong); tanpa flag ini semua anggota akan tampak menunggak.
      membersKnown: billKnown,
      // Kas = iuran + transaksi; kalau salah satu gagal, angkanya bukan nol
      // yang sebenarnya melainkan nol yang tidak diketahui.
      cashKnown: money && r[5].ok && r[6].ok,
      moneyLocked: !money,
    );
  }
}

class _DashboardPageState extends State<DashboardPage> with SingleTickerProviderStateMixin {
  late Future<_DashboardData> _future;

  /// Naik tiap muat ulang; kartu turnamen memakainya untuk memuat hasil lagi.
  int _gen = 0;
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..forward();

  @override
  void initState() {
    super.initState();
    _future = _DashboardData.load();
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final f = _DashboardData.load();
    setState(() {
      _future = f;
      _gen++;
    });
    _in.forward(from: 0);
    await f;
  }

  /// Nama yang disapa: username dari sesi, kapital di huruf pertama.
  String _name() {
    final u = Auth.username?.trim();
    if (u == null || u.isEmpty) return 'Klub';
    return u[0].toUpperCase() + u.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Halo, ${_name()}',
      subtitle: fmtDate(DateTime.now()),
      actions: [iconAction(context, Icons.refresh, _reload, tooltip: 'Muat ulang')],
      child: AsyncView<_DashboardData>(
        future: _future,
        onRefresh: _reload,
        builder: (d) => LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth >= 880;
            final main = _MainColumn(data: d, anim: _in, gen: _gen, onChanged: _reload);
            final notice = d.failures.isEmpty
                ? null
                : DegradedNotice(failures: d.failures, onRetry: _reload);
            if (!wide) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                children: [?notice, main],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              children: [
                ?notice,
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: main),
                    const SizedBox(width: 28),
                    Expanded(
                      flex: 2,
                      // `key` mengikuti `_gen`: tanpa itu, "Muat ulang"
                      // memperbarui kolom utama tetapi klasemen/pencetak gol
                      // tetap angka lama karena future-nya sudah selesai.
                      child: _RailColumn(
                        key: ValueKey('rail-$_gen'),
                        data: d,
                        anim: _in,
                        onChanged: _reload,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Fade + naik sedikit saat data siap. Satu kali per muat, bukan per scroll.
class _In extends StatelessWidget {
  const _In({required this.anim, required this.begin, required this.child});

  final Animation<double> anim;
  final double begin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Animasi masuk dilewati kalau sistem meminta animasi dikurangi, dan di
    // perangkat yang melaporkan animasi dimatikan (mode pengembang / hemat
    // baterai ekstrem). Fade + slide per bagian berarti beberapa layer
    // compositing sekaligus; di HP lama itu justru yang membuat gulir pertama
    // terasa tersendat, padahal isinya sudah siap ditampilkan.
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final a = CurvedAnimation(
      parent: anim,
      curve: Interval(begin.clamp(0, 0.7), (begin + 0.3).clamp(0.3, 1), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a),
        child: child,
      ),
    );
  }
}

class _MainColumn extends StatelessWidget {
  const _MainColumn({
    required this.data,
    required this.anim,
    required this.gen,
    required this.onChanged,
  });

  final _DashboardData data;
  final Animation<double> anim;
  final int gen;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final d = data;
    final played = d.stats[0] + d.stats[1] + d.stats[2];
    final live = d.liveMatch;
    final next = d.nextTournament;
    final last = d.lastTournament;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _In(
          anim: anim,
          begin: 0,
          // Hero kosong ("Susun turnamen") hanya untuk klub yang benar-benar
          // belum punya turnamen. Kalau sudah ada turnamen selesai, kartu
          // "Turnamen terakhir" di bawah sudah menjawab keadaannya — menampilkan
          // keduanya membuat beranda terlihat kosong padahal ada riwayat.
          child: live != null
              ? _FixtureStrip(match: live, onChanged: onChanged)
              : next != null
                  ? _NextTournamentHero(tournament: next, onChanged: onChanged)
                  : last == null
                      ? _EmptyHero(
                          onChanged: onChanged,
                          members: d.members,
                          teams: d.teams.length,
                          teamsReady: d.teamsReady,
                        )
                      : _LastTournamentHero(tournament: last, onChanged: onChanged),
        ),
        if (live != null && next != null) ...[
          const SectionTitle('Turnamen berikutnya', top: 14),
          _In(
            anim: anim,
            begin: 0.03,
            child: _TournamentRow(tournament: next, onChanged: onChanged),
          ),
        ],
        if (last != null) ...[
          SectionTitle(
            'Turnamen terakhir',
            action: TextButton(
              style: AppThemes.sectionAction(),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TournamentsPage()),
                );
                await onChanged();
              },
              child: const Text('Semua'),
            ),
          ),
          _In(
            anim: anim,
            begin: 0.06,
            child: _LastTournamentCard(
              tournament: last,
              teamNames: d.teamNames,
              gen: gen,
              onChanged: onChanged,
            ),
          ),
        ],
        const SizedBox(height: 10),
        _In(
          anim: anim,
          begin: 0.1,
          child: StatStrip(
            children: [
              StatTile(
                label: 'Anggota',
                value: '${d.members}',
                hint: '${d.teams.length} tim',
              ),
              StatTile(
                label: 'Main',
                value: '$played',
                hint: 'laga selesai',
              ),
              StatTile(
                label: 'Iuran',
                // Angka uang tidak ditampilkan untuk tamu: bukan karena
                // gagal dimuat, tapi karena memang tidak boleh dibaca.
                value: d.moneyLocked ? '—' : fmtMoney(d.income),
                color: AppThemes.money(context),
                // Lunas dihitung dari daftar peserta turnamen aktif. Kalau
                // sumbernya gagal, angkanya tidak bermakna — jangan diklaim.
                hint: d.moneyLocked
                    ? 'masuk untuk lihat'
                    : (d.paymentsKnown && d.membersKnown)
                        ? '${d.unpaid.isEmpty ? 'semua' : '${d.unpaid.length} belum'} lunas'
                        : 'data belum lengkap',
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        _In(
          anim: anim,
          begin: 0.14,
          child: d.moneyLocked
              ? _LockedCash(onChanged: onChanged)
              : _CashBlock(cash: d.cash, known: d.cashKnown, onChanged: onChanged),
        ),
        if (Auth.canWrite)
          _In(
            anim: anim,
            begin: 0.18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('Aksi cepat'),
                _QuickGrid(
                  actions: [
                    _QuickAction(Icons.shield_outlined, 'Tim', () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TeamsPage()),
                      );
                      onChanged();
                    }),
                    _QuickAction(Icons.event, 'Jadwal', () async {
                      if (await showMatchForm(context)) onChanged();
                    }),
                    _QuickAction(Icons.emoji_events_outlined, 'Turnamen', () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const TournamentsPage()),
                      );
                      onChanged();
                    }),
                    _QuickAction(Icons.payments, 'Iuran', () async {
                      final t = d.activeTournament;
                      if (t == null) {
                        toast(context, 'Buat turnamen dulu — iuran ditarik per turnamen');
                        return;
                      }
                      if (await showPaymentForm(context,
                          tournamentId: t.id, entryFee: t.entryFee)) {
                        onChanged();
                      }
                    }),
                    _QuickAction(Icons.person_add_alt, 'Anggota', () async {
                      if (await showMemberForm(context)) onChanged();
                    }),
                    _QuickAction(Icons.campaign_outlined, 'Umumkan', () async {
                      if (await showAnnouncementForm(context)) onChanged();
                    }),
                  ],
                ),
              ],
            ),
          ),
        _In(
          anim: anim,
          begin: 0.26,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                'Pengumuman',
                action: TextButton(
                  style: AppThemes.sectionAction(),
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AnnouncementsPage()),
                    );
                    await onChanged();
                  },
                  child: const Text('Semua'),
                ),
              ),
              if (d.news.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Belum ada pengumuman.', style: t.textTheme.muted),
                )
              else
                for (final a in d.news.take(2))
                  RowItem(
                    title: a.title,
                    subtitle: '${fmtDate(a.createdAt)} • ${a.body}',
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "3 hari lagi" — jarak yang lebih berguna daripada tanggal mentah saat
/// turnamen masih dekat.
String _countdown(DateTime d) {
  final now = DateTime.now();
  final days = DateTime(d.year, d.month, d.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  if (days < 0) return '${-days} hari lalu';
  if (days == 0) return 'hari ini';
  if (days == 1) return 'besok';
  return '$days hari lagi';
}

/// Turnamen terdekat sebagai kartu utama beranda.
class _NextTournamentHero extends StatelessWidget {
  const _NextTournamentHero({required this.tournament, required this.onChanged});

  final Tournament tournament;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final dark = t.brightness == Brightness.dark;
    final when = _countdown(tournament.startsAt);
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0C1A12) : const Color(0xFFEAF6EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.colorScheme.primary.withValues(alpha: dark ? 0.45 : 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill('Turnamen berikutnya', color: t.colorScheme.primary),
              const Spacer(),
              if (tournament.venue?.isNotEmpty ?? false) Pill(tournament.venue!),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tournament.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.h1.copyWith(fontSize: 32, height: 1.05),
          ),
          const SizedBox(height: 6),
          Text(
            [
              fmtDateTime(tournament.startsAt),
              when,
              if (tournament.groups > 1) '${tournament.groups} grup',
            ].join(' • '),
            style: t.textTheme.small.copyWith(color: t.colorScheme.foreground),
          ),
          const SizedBox(height: 14),
          ShadButton(
            height: AppThemes.minTap,
            backgroundColor: t.colorScheme.primary,
            foregroundColor: t.colorScheme.primaryForeground,
            hoverBackgroundColor: t.colorScheme.primary.withValues(alpha: 0.88),
            onPressed: () => _open(context),
            leading: const Icon(Icons.emoji_events_outlined, size: 16),
            child: const Text('Lihat turnamen'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TournamentDetailPage(tournament: tournament)),
    );
    await onChanged();
  }
}

/// Hero untuk klub yang sudah punya turnamen selesai tapi tidak ada yang
/// berjalan atau akan datang. Tanpa ini, beranda menampilkan ajakan "Susun
/// turnamen" padahal riwayat turnamennya ada — terlihat seperti data hilang.
class _LastTournamentHero extends StatelessWidget {
  const _LastTournamentHero({required this.tournament, required this.onChanged});

  final Tournament tournament;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final dark = t.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0C1A12) : const Color(0xFFEAF6EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.colorScheme.primary.withValues(alpha: dark ? 0.45 : 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pill(
                tournament.status == 'running' ? 'Turnamen berjalan' : 'Turnamen terakhir',
                color: t.colorScheme.primary,
              ),
              const Spacer(),
              if (tournament.venue?.isNotEmpty ?? false) Pill(tournament.venue!),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            tournament.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.textTheme.h1.copyWith(fontSize: 32, height: 1.05),
          ),
          const SizedBox(height: 6),
          Text(
            [
              fmtDateTime(tournament.startsAt),
              Tournament.statusLabels[tournament.status] ?? tournament.status,
              if (tournament.groups > 1) '${tournament.groups} grup',
            ].join(' • '),
            style: t.textTheme.small.copyWith(color: t.colorScheme.foreground),
          ),
          const SizedBox(height: 14),
          ShadButton(
            height: AppThemes.minTap,
            backgroundColor: t.colorScheme.primary,
            foregroundColor: t.colorScheme.primaryForeground,
            hoverBackgroundColor: t.colorScheme.primary.withValues(alpha: 0.88),
            onPressed: () => _open(context),
            leading: const Icon(Icons.emoji_events_outlined, size: 16),
            child: const Text('Lihat turnamen'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TournamentDetailPage(tournament: tournament)),
    );
    await onChanged();
  }
}

/// Beranda tanpa turnamen sama sekali: satu ajakan, bukan kotak kosong.
///
/// Ajakan itu mengikuti kesiapan klub. Klub yang baru punya satu anggota tidak
/// bisa langsung menyusun turnamen: timnya kosong, jadi turnamennya akan
/// berjalan tanpa peserta dan iurannya tidak bisa ditagih. Sebelumnya kartu ini
/// selalu berbunyi "Susun turnamen" — mengarahkan ke langkah yang belum bisa
/// dijalankan.
class _EmptyHero extends StatelessWidget {
  const _EmptyHero({
    required this.onChanged,
    required this.members,
    required this.teams,
    required this.teamsReady,
  });

  final Future<void> Function() onChanged;
  final int members;
  final int teams;
  final int teamsReady;

  /// Langkah yang benar-benar bisa dilakukan sekarang.
  ({String pill, String title, String body, String action, IconData icon, void Function(BuildContext) run})
      get _next {
    if (members == 0) {
      return (
        pill: 'Langkah pertama',
        title: 'Tambah anggota',
        body: 'Semua bermula dari daftar anggota: mereka yang mengisi tim, '
            'membayar iuran, dan tercatat di kas.',
        action: 'Tambah anggota',
        icon: Icons.person_add_alt_1,
        run: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const MembersPage())),
      );
    }
    if (teamsReady < 2) {
      return (
        pill: 'Belum siap bertanding',
        title: 'Isi pemain ke tim',
        body: teams == 0
            ? 'Buat dua tim dulu, lalu masukkan anggota ke dalamnya. '
                'Turnamen dan laga dibentuk dari tim.'
            : '$teamsReady dari $teams tim sudah punya pemain. Turnamen butuh '
                'minimal dua tim berisi pemain supaya iurannya bisa ditagih.',
        action: 'Buka Tim',
        icon: Icons.shield_outlined,
        run: (ctx) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => const TeamsPage())),
      );
    }
    return (
      pill: 'Belum ada turnamen',
      title: 'Susun turnamen',
      body: 'Pilih tim klub, bagi ke grup, lalu jadwalnya dibuat otomatis: '
          'semua tim saling bertemu sekali.',
      action: 'Buat turnamen',
      icon: Icons.add,
      run: (ctx) async {
        if (await showTournamentForm(ctx) != null) await onChanged();
      },
    );
  }

  /// Kalimat untuk pembaca yang tidak boleh mengubah apa pun.
  ///
  /// `_next` adalah AJAKAN ("Isi pemain ke tim", "Susun turnamen"). Untuk
  /// anggota biasa ajakan itu salah alamat: mereka tidak bisa membuka form
  /// tim atau turnamen, jadi yang tersisa hanya perintah tanpa tombol — dan
  /// itu terbaca seperti tugas yang belum mereka kerjakan. Versi ini
  /// melaporkan keadaan klub, bukan meminta.
  ({String pill, String title, String body})
      get _status {
    if (members == 0) {
      return (
        pill: 'Info klub',
        title: 'Belum ada anggota',
        body: 'Daftar anggota klub belum diisi pengurus.',
      );
    }
    if (teamsReady < 2) {
      return (
        pill: 'Belum siap bertanding',
        title: 'Turnamen belum disusun',
        body: teams == 0
            ? 'Pengurus belum membuat tim. Turnamen dan laga dibentuk dari tim.'
            : '$teamsReady dari $teams tim sudah punya pemain. Turnamen disusun '
                'setelah minimal dua tim berisi pemain.',
      );
    }
    return (
      pill: 'Belum ada turnamen',
      title: 'Turnamen belum disusun',
      body: 'Pengurus belum membuat turnamen. Jadwal, klasemen, dan tagihan '
          'iuran muncul di sini setelahnya.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final n = _next;
    final s = _status;
    final pill = Auth.canWrite ? n.pill : s.pill;
    final title = Auth.canWrite ? n.title : s.title;
    final body = Auth.canWrite ? n.body : s.body;
    return Panel(
      highlight: true,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Pill(pill, color: t.colorScheme.primary),
          const SizedBox(height: 8),
          Text(title, style: t.textTheme.h1.copyWith(fontSize: 32)),
          const SizedBox(height: 4),
          Text(body, style: t.textTheme.small),
          if (Auth.canWrite) ...[
            const SizedBox(height: 14),
            ShadButton(
              height: AppThemes.minTap,
              backgroundColor: t.colorScheme.primary,
              foregroundColor: t.colorScheme.primaryForeground,
              hoverBackgroundColor: t.colorScheme.primary.withValues(alpha: 0.88),
              onPressed: () => n.run(context),
              leading: Icon(n.icon, size: 16),
              child: Text(n.action),
            ),
          ],
        ],
      ),
    );
  }
}

/// Satu baris turnamen — dipakai saat papan skor laga hidup sudah memakai
/// ruang utama, jadi turnamen berikutnya cukup satu baris.
class _TournamentRow extends StatelessWidget {
  const _TournamentRow({required this.tournament, required this.onChanged});

  final Tournament tournament;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return RowItem(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => TournamentDetailPage(tournament: tournament)),
        );
        await onChanged();
      },
      leading: Icon(Icons.emoji_events_outlined, size: 18, color: t.colorScheme.primary),
      title: tournament.name,
      // Tanggal pendek + hitung mundur: satu baris di HP. Lokasi ada di detail.
      subtitle: [
        '${fmtDay(tournament.startsAt)}, ${fmtShortDate(tournament.startsAt)}',
        fmtTime(tournament.startsAt),
        _countdown(tournament.startsAt),
      ].join(' • '),
      trailing: Icon(Icons.chevron_right, size: 18, color: t.colorScheme.mutedForeground),
    );
  }
}

/// Turnamen terakhir: ringkas saat tertutup, hasil pertandingannya muncul
/// setelah diketuk. Di luar tetap tenang; detail hanya saat diminta.
class _LastTournamentCard extends StatefulWidget {
  const _LastTournamentCard({
    required this.tournament,
    required this.teamNames,
    required this.gen,
    required this.onChanged,
  });

  final Tournament tournament;
  final Map<int, String> teamNames;

  /// Berubah setiap beranda dimuat ulang, supaya hasil dimuat lagi.
  final int gen;
  final Future<void> Function() onChanged;

  @override
  State<_LastTournamentCard> createState() => _LastTournamentCardState();
}

class _LastTournamentCardState extends State<_LastTournamentCard> {
  bool _open = false;
  late Future<List<TournamentMatch>> _matches;

  @override
  void initState() {
    super.initState();
    // Dimuat sejak awal: kartu tertutup pun sudah bisa menunjukkan "3/6 laga".
    _matches = TournamentMatch.forTournament(widget.tournament.id);
  }

  @override
  void didUpdateWidget(_LastTournamentCard old) {
    super.didUpdateWidget(old);
    if (old.tournament.id != widget.tournament.id || old.gen != widget.gen) {
      _matches = TournamentMatch.forTournament(widget.tournament.id);
    }
  }

  void _toggle() => setState(() => _open = !_open);

  /// Hasil gagal dimuat hanya bisa dicoba lagi dari sini: kartu ini memegang
  /// future-nya sendiri, jadi "Muat ulang" beranda tidak menyentuhnya selama
  /// turnamen dan generasinya tidak berubah.
  void _retryMatches() => setState(() {
        _matches = TournamentMatch.forTournament(widget.tournament.id);
      });

  Future<void> _openDetail() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TournamentDetailPage(tournament: widget.tournament)),
    );
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final tour = widget.tournament;
    // Hijau = turnamen yang benar-benar berjalan atau sudah tuntas; abu-abu
    // hanya untuk draft. Dulu yang selesai ikut abu-abu sehingga kartu
    // "Turnamen terakhir" yang penuh hasil terlihat seperti nonaktif.
    final statusColor = tour.status == 'draft'
        ? t.colorScheme.mutedForeground
        : t.colorScheme.primary;

    return Panel(
      padding: EdgeInsets.zero,
      onTap: _toggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.emoji_events_outlined, size: 18, color: statusColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tour.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.large.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    // Chevron saja tidak terbaca sebagai "ketuk untuk hasil".
                    // Di 320px label ini memakan ruang nama turnamen, jadi
                    // hanya ditampilkan kalau lebarnya cukup.
                    if (MediaQuery.sizeOf(context).width >= 360) ...[
                      Text(_open ? 'Tutup' : 'Hasil', style: t.textTheme.small),
                      const SizedBox(width: 2),
                    ],
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.expand_more, size: 20, color: t.colorScheme.mutedForeground),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 26),
                  child: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Pill(Tournament.statusLabels[tour.status] ?? tour.status, color: statusColor),
                      Text(
                        [
                          fmtDate(tour.startsAt),
                          if (tour.venue?.isNotEmpty ?? false) tour.venue!,
                          if (tour.groups > 1) '${tour.groups} grup',
                        ].join(' • '),
                        style: t.textTheme.small,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 26),
                  child: _Progress(matches: _matches, tournament: tour, color: statusColor),
                ),
              ],
            ),
          ),
          if (_open) ...[
            Divider(height: 1, color: t.colorScheme.border),
            FutureBuilder<List<TournamentMatch>>(
              future: _matches,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Gagal memuat hasil: ${errText(snap.error!)}',
                            style: t.textTheme.small,
                          ),
                        ),
                        TextButton(
                          onPressed: _retryMatches,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  );
                }
                final all = snap.data;
                if (all == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  );
                }
                final done = all.where((m) => m.done).toList();
                final left = all.length - done.length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (done.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text('Belum ada hasil pertandingan.', style: t.textTheme.muted),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                        child: Text('HASIL PERTANDINGAN', style: t.textTheme.h4.copyWith(fontSize: 10.5)),
                      ),
                      for (final m in done)
                        _ResultLine(match: m, names: widget.teamNames),
                      if (left > 0)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text('$left laga belum dimainkan.', style: t.textTheme.small),
                        ),
                    ],
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _openDetail,
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          label: const Text('Buka detail turnamen'),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// "3/6 laga" + bar tipis. Sebelum hasil dimuat, hanya teks yang tampil.
class _Progress extends StatelessWidget {
  const _Progress({required this.matches, required this.tournament, required this.color});

  final Future<List<TournamentMatch>>? matches;
  final Tournament tournament;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return FutureBuilder<List<TournamentMatch>>(
      future: matches,
      builder: (context, snap) {
        final all = snap.data;
        if (all == null) {
          return Text('${tournament.matchMinutes} menit/laga', style: t.textTheme.small);
        }
        final done = all.where((m) => m.done).length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  '$done/${all.length} laga',
                  style: t.textTheme.table.copyWith(fontFeatures: AppThemes.tabular),
                ),
                const Spacer(),
                Text('${tournament.matchMinutes} menit/laga', style: t.textTheme.small),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: all.isEmpty ? 0 : done / all.length,
                minHeight: 4,
                backgroundColor: t.colorScheme.muted,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Satu hasil: jam, tim kiri, skor, tim kanan. Tim pemenang ditebalkan.
class _ResultLine extends StatelessWidget {
  const _ResultLine({required this.match, required this.names});

  final TournamentMatch match;
  final Map<int, String> names;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final homeWin = match.scoreHome! > match.scoreAway!;
    final awayWin = match.scoreAway! > match.scoreHome!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.colorScheme.border.withValues(alpha: 0.6))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(fmtTime(match.kickoff), style: t.textTheme.small),
          ),
          Expanded(
            child: Text(
              names[match.homeTeamId] ?? '—',
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: homeWin ? FontWeight.w600 : FontWeight.w400,
                color: homeWin ? t.colorScheme.primary : t.colorScheme.foreground,
              ),
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(
              '${match.scoreHome}–${match.scoreAway}',
              textAlign: TextAlign.center,
              style: t.textTheme.h2.copyWith(fontSize: 18, fontFeatures: AppThemes.tabular),
            ),
          ),
          Expanded(
            child: Text(
              names[match.awayTeamId] ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: awayWin ? FontWeight.w600 : FontWeight.w400,
                color: awayWin ? t.colorScheme.primary : t.colorScheme.foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pengganti blok kas untuk tamu.
///
/// Menampilkan "Rp 0" akan menjadi kebohongan: angkanya bukan nol, hanya
/// tidak boleh dibaca tanpa masuk. Jadi yang ditampilkan adalah alasannya
/// plus satu tombol untuk masuk.
class _LockedCash extends StatelessWidget {
  const _LockedCash({required this.onChanged});

  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Kas bulan ini'),
        Panel(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: t.colorScheme.mutedForeground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Kas dan iuran hanya untuk anggota klub. Masuk untuk melihat.',
                  style: t.textTheme.small,
                ),
              ),
              const SizedBox(width: 8),
              ShadButton.outline(
                height: AppThemes.minTap,
                onPressed: () async {
                  if (await openLogin(context)) await onChanged();
                },
                child: const Text('Masuk'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ringkasan kas bulan ini. Ketuk untuk membuka buku kas lengkap.
class _CashBlock extends StatelessWidget {
  const _CashBlock({required this.cash, required this.known, required this.onChanged});

  final CashSummary cash;

  /// False kalau iuran atau kas gagal dimuat. Angka nol saat itu berarti
  /// "tidak diketahui", bukan "belum ada transaksi".
  final bool known;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Kas bulan ini',
          action: TextButton(
            style: AppThemes.sectionAction(),
            onPressed: () => _open(context),
            child: const Text('Buka'),
          ),
        ),
        InkWell(
          onTap: () => _open(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: StatStrip(
              children: [
                StatTile(label: 'Masuk', value: fmtMoney(cash.income), color: AppThemes.money(context)),
                StatTile(label: 'Keluar', value: fmtMoney(cash.expense), color: AppThemes.money(context)),
                StatTile(
                  label: 'Saldo',
                  value: fmtMoney(cash.balance),
                  color: cash.balance < 0
                      ? AppThemes.bad(context)
                      : AppThemes.money(context),
                ),
              ],
            ),
          ),
        ),
        if (cash.income == 0 && cash.expense == 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              // "Belum ada" hanya boleh dikatakan kalau datanya benar-benar
              // terbaca; saat gagal, yang benar adalah "tidak diketahui".
              known
                  ? 'Belum ada pemasukan atau pengeluaran tercatat bulan ini.'
                  : 'Data kas bulan ini belum bisa dimuat.',
              style: t.textTheme.small,
            ),
          ),
      ],
    );
  }

  Future<void> _open(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FinancePage()),
    );
    await onChanged();
  }
}

/// Kolom kanan di layar lebar: uang dan top skor. Di HP ikut alur utama.
/// Data yang HANYA tampil di kolom samping (layar lebar): klasemen, pencetak
/// gol, dan sewa lapangan berikutnya.
///
/// Dimuat terpisah dari data utama karena di HP kolom ini tidak dirender sama
/// sekali. Sebelumnya ketiga query itu tetap dijalankan di setiap muat
/// beranda — tiga perjalanan ke server untuk data yang tidak pernah dilihat.
class _RailData {
  const _RailData({
    required this.scorers,
    required this.standings,
    required this.bookings,
    required this.failures,
  });

  final List<ScorerRow> scorers;
  final List<Standing> standings;
  final List<Booking> bookings;

  /// Sumber yang gagal dimuat. Sebagian gagal = bagian lain tetap tampil,
  /// dan nama sumbernya disebut supaya tidak terbaca sebagai "belum ada data".
  final List<String> failures;

  static Future<_RailData> load() async {
    // Sewa lapangan memuat biaya, jadi termasuk data uang: tamu tidak
    // memintanya ke server sama sekali.
    final money = Auth.signedIn;
    final r = await Future.wait<Soft<Object?>>([
      soft('Pencetak gol', ScorerRow.top, fallback: const <ScorerRow>[]),
      soft('Klasemen tim', Team.standings, fallback: const <Standing>[]),
      soft('Sewa lapangan',
          () => money ? Booking.upcoming() : Future.value(const <Booking>[]),
          fallback: const <Booking>[]),
    ]);
    final failures = settle(r);
    return _RailData(
      scorers: r[0].value! as List<ScorerRow>,
      standings: r[1].value! as List<Standing>,
      bookings: r[2].value! as List<Booking>,
      failures: failures,
    );
  }
}

/// Kerangka kolom samping selama datanya diambil. Tanpa ini kolom kanan
/// kosong beberapa ratus milidetik, dan di layar lebar itu terbaca sebagai
/// "tidak ada klasemen" — bukan "sedang dimuat".
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    Widget block(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: t.colorScheme.muted,
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final w in const [92.0, 68.0, 80.0]) ...[
          block(w, 11),
          const SizedBox(height: 10),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: block(double.infinity, 40),
            ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _RailColumn extends StatefulWidget {
  const _RailColumn({super.key, required this.data, required this.anim, required this.onChanged});

  /// Data utama beranda: dipakai kolom ini untuk bagian "belum bayar", yang
  /// memang sudah dimuat untuk kartu ringkasan di kolom utama.
  final _DashboardData data;
  final Animation<double> anim;
  final Future<void> Function() onChanged;

  @override
  State<_RailColumn> createState() => _RailColumnState();
}

class _RailColumnState extends State<_RailColumn> {
  late Future<_RailData> _future = _RailData.load();

  void _retry() => setState(() => _future = _RailData.load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_RailData>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        // Kolom ini hanya ada di layar lebar, dan isinya (klasemen, pencetak
        // gol, sewa) tidak muncul di tempat lain. Dulu kegagalan memuatnya
        // menghasilkan kotak kosong: pengguna mengira klub belum punya
        // klasemen. Sekarang kegagalan disebut, dengan tombol coba lagi.
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 18),
            child: DegradedNotice(
              failures: ['Klasemen, pencetak gol & sewa: ${errText(snap.error!)}'],
              onRetry: _retry,
            ),
          );
        }
        if (d == null) return const _RailSkeleton();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (d.failures.isNotEmpty)
              DegradedNotice(failures: d.failures, onRetry: _retry),
            _rail(context, d),
          ],
        );
      },
    );
  }

  Widget _rail(BuildContext context, _RailData d) {
    final t = ShadTheme.of(context);
    final anim = widget.anim;
    final onChanged = widget.onChanged;
    // `main` = data beranda yang sudah dimuat; `d` = data khusus kolom ini.
    final main = widget.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _In(
          anim: anim,
          begin: 0.1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                main.activeTournament == null
                    ? 'Belum bayar'
                    : 'Belum bayar — ${main.activeTournament!.name}',
                top: 0,
              ),
              // Tanpa daftar peserta yang terbaca, daftar kosong BUKAN berarti
              // "semua lunas".
              if (!main.paymentsKnown || !main.membersKnown)
                Text('Data iuran belum bisa dimuat.', style: t.textTheme.muted)
              else if (main.activeTournament == null)
                Text(
                  'Belum ada turnamen. Iuran ditarik per turnamen.',
                  style: t.textTheme.muted,
                )
              else if (main.unpaid.isEmpty)
                Text(
                  main.dues != null && main.dues! > 0
                      ? 'Semua peserta sudah lunas untuk turnamen ini.'
                      : 'Belum ada peserta yang perlu ditagih.',
                  style: t.textTheme.muted,
                )
              else
                for (final m in main.unpaid.take(6))
                  RowItem(
                    title: m.name,
                    subtitle: m.position,
                    trailing: Text(
                      (main.dues ?? 0) > 0 ? fmtMoney(main.dues!) : 'Belum bayar',
                      style: t.textTheme.table.copyWith(color: AppThemes.bad(context)),
                    ),
                  ),
            ],
          ),
        ),
        if (d.standings.any((s) => s.played > 0))
          _In(
            anim: anim,
            begin: 0.14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('Klasemen'),
                StandingsTable(standings: d.standings.take(4).toList(), top: 1),
              ],
            ),
          ),
        _In(
          anim: anim,
          begin: 0.2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionTitle('Pencetak gol'),
              if (d.scorers.isEmpty)
                Text('Belum ada gol tercatat.', style: t.textTheme.muted)
              else
                for (var i = 0; i < d.scorers.length && i < 6; i++)
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
                    title: d.scorers[i].name,
                    subtitle: d.scorers[i].assists > 0
                        ? '${d.scorers[i].assists} umpan gol'
                        : 'pencetak gol',
                    trailing: Text('${d.scorers[i].goals}', style: t.textTheme.h2.copyWith(fontSize: 20)),
                  ),
            ],
          ),
        ),
        if (d.bookings.isNotEmpty)
          _In(
            anim: anim,
            begin: 0.26,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle(
                  'Sewa lapangan',
                  action: TextButton(
                    style: AppThemes.sectionAction(),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BookingsPage()),
                      );
                      onChanged();
                    },
                    child: const Text('Semua'),
                  ),
                ),
                for (final b in d.bookings.take(3))
                  RowItem(
                    title: b.title,
                    subtitle: fmtDateTime(b.startsAt),
                    trailing: Text(
                      fmtMoney(b.cost),
                      style: t.textTheme.table.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppThemes.money(context),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Laga yang sedang berlangsung sebagai papan skor: dua nama tim mengapit
/// skor, seperti papan stadion — bukan kartu gradien. Hanya muncul kalau
/// memang ada laga hidup; jadwal lain dibaca lewat turnamen.
class _FixtureStrip extends StatelessWidget {
  const _FixtureStrip({required this.match, required this.onChanged});

  final Match match;
  final Future<void> Function() onChanged;

  Future<void> _open(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MatchDetailPage(match: match)),
    );
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final dark = t.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF0C1A12) : const Color(0xFFEAF6EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.colorScheme.primary.withValues(alpha: dark ? 0.45 : 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Pill('Sedang berlangsung', color: t.colorScheme.primary),
                const Spacer(),
                Pill(match.venue ?? 'Internal'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    match.homeName,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.h2.copyWith(fontSize: 22, height: 1.1),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '${match.goalsFor}–${match.goalsAgainst}',
                    style: t.textTheme.h1Large.copyWith(
                      fontSize: 40,
                      color: t.colorScheme.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    match.awayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.h2.copyWith(fontSize: 22, height: 1.1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${fmtDateTime(match.playedAt)}${match.venue == null ? '' : ' • ${match.venue}'}',
              style: t.textTheme.small,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (Auth.canWrite) ...[
                  Expanded(
                    child: ShadButton(
                      height: AppThemes.minTap,
                      backgroundColor: t.colorScheme.primary,
                      foregroundColor: t.colorScheme.primaryForeground,
                      hoverBackgroundColor: t.colorScheme.primary.withValues(alpha: 0.88),
                      onPressed: () async {
                        if (!await showFinishMatch(context, match)) return;
                        // Toast dulu: onChanged() membuang context kartu ini.
                        if (context.mounted) {
                          toast(context, 'Hasil tersimpan · poin klasemen diperbarui');
                        }
                        await onChanged();
                      },
                      leading: const Icon(Icons.check, size: 16),
                      child: const Text('Selesai'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: ShadButton.outline(
                    height: AppThemes.minTap,
                    onPressed: () => _open(context),
                    leading: const Icon(Icons.scoreboard, size: 16),
                    child: Text(Auth.canWrite ? 'Detail' : 'Lihat detail'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Aksi cepat dalam kisi tiga kolom yang lebarnya selalu pas: tiap tombol
/// memakai Expanded, jadi tidak ada baris yang menggantung atau meluber di
/// layar 320px.
class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        // Di bawah 360px tiga kolom memaksa label jadi "Angg…"; dua kolom
        // lebih penting daripada jumlah baris.
        final columns = c.maxWidth < 340 ? 2 : 3;
        final rows = <Widget>[];
        for (var i = 0; i < actions.length; i += columns) {
          final slice = actions.sublist(i, (i + columns).clamp(0, actions.length));
          rows.add(Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: Row(
              children: [
                for (var j = 0; j < slice.length; j++) ...[
                  if (j > 0) const SizedBox(width: 8),
                  Expanded(child: slice[j]),
                ],
              ],
            ),
          ));
        }
        return Column(children: rows);
      },
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.icon, this.label, this.onTap);

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          // Aksi cepat paling sering ditekan sambil berdiri/lari, jadi
          // targetnya memakai AppThemes.minTap — bukan lagi 40px yang masih
          // di bawah pedoman sentuh Android/iOS.
          height: AppThemes.minTap,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            border: Border.all(color: t.colorScheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: t.colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

