import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/db.dart';
import '../core/soft.dart';
import '../core/update.dart';
import '../core/version.dart';
import '../data/auth.dart';
import '../data/models.dart';
import 'announcements.dart';
import 'bookings.dart';
import 'finance.dart';
import 'fmt.dart';
import 'login.dart';
import 'members.dart';
import 'my_account.dart';
import 'settings.dart';
import 'stats.dart';
import 'tournament.dart';
import 'users.dart';
import 'widgets.dart';

/// Angka ringkas untuk halaman Lainnya. Dulu tiap baris hanya menjelaskan
/// isi menunya ("Data pemain, posisi & nomor punggung"); sekarang baris yang
/// sama menjawab pertanyaan yang sebenarnya dibawa orang ke sini: berapa
/// anggota aktif, kapan sewa berikutnya, berapa saldo, turnamen mana yang
/// sedang jalan, dan apakah ada yang belum bayar.
class _Counts {
  const _Counts({
    required this.active,
    required this.inactive,
    required this.nextBooking,
    required this.saldo,
    required this.unpaid,
    required this.playing,
    required this.tournaments,
    required this.played,
    required this.news,
    required this.lastNews,
    required this.failures,
  });

  final int active;
  final int inactive;
  final Booking? nextBooking;
  final double saldo;
  final int unpaid;
  final int playing;
  final int tournaments;
  final int played;
  final int news;
  final Announcement? lastNews;

  /// Sumber yang gagal dimuat. Subjudul baris sudah jatuh ke teks statis saat
  /// angka tidak tersedia; daftar ini hanya memberi tahu *apa* yang gagal.
  final List<String> failures;

  static Future<_Counts> load() async {
    final period = periodNow();
    final r = await Future.wait<Soft<Object?>>([
      soft('Anggota', Member.all, fallback: const <Member>[]),
      soft('Sewa lapangan', Booking.upcoming, fallback: const <Booking>[]),
      soft('Iuran bulan ini', () => Payment.inMonth(DateTime.now()), fallback: const <Payment>[]),
      soft('Kas bulan ini', () => Transaction.all(period: period), fallback: const <Transaction>[]),
      soft('Turnamen', Tournament.all, fallback: const <Tournament>[]),
      soft('Rekap laga', Match.stats, fallback: const [0, 0, 0, 0, 0]),
      soft('Pengumuman', Announcement.all, fallback: const <Announcement>[]),
    ]);
    final failures = settle(r);
    final members = r[0].value! as List<Member>;
    final active = members.where((m) => m.active).toList();
    final cash = CashSummary.fromEntries(mergeCashLedger(
      payments: r[2].value! as List<Payment>,
      transactions: r[3].value! as List<Transaction>,
    ));
    final tours = r[4].value! as List<Tournament>;
    final stats = r[5].value! as List<int>;
    final news = r[6].value! as List<Announcement>;
    final bookings = r[1].value! as List<Booking>;

    // "Belum bayar" mengikuti turnamen aktif (yang sedang berjalan, atau yang
    // terdekat). Iuran ditarik per turnamen, jadi menghitungnya dari seluruh
    // anggota tidak lagi bermakna: peserta tiap turnamen berbeda.
    Tournament? activeTour;
    for (final t in tours) {
      if (t.status == 'running') {
        activeTour = t;
        break;
      }
    }
    if (activeTour == null) {
      for (final t in tours) {
        if (t.status == 'draft') {
          activeTour = t;
          break;
        }
      }
    }
    activeTour ??= tours.isEmpty ? null : tours.first;

    var unpaid = 0;
    if (activeTour != null) {
      final b = await soft('Iuran turnamen', () => Payment.bill(activeTour!.id),
          fallback: const <DuesRow>[]);
      failures.addAll(settle([b]));
      unpaid = b.value!.where((r) => !r.paid).length;
    }

    return _Counts(
      active: active.length,
      inactive: members.length - active.length,
      nextBooking: bookings.isEmpty ? null : bookings.first,
      saldo: cash.balance,
      unpaid: unpaid,
      playing: tours.where((t) => t.status == 'running').length,
      tournaments: tours.length,
      played: stats[0] + stats[1] + stats[2],
      news: news.length,
      lastNews: news.isEmpty ? null : news.first,
      failures: failures,
    );
  }
}

/// Semua fitur yang tidak muat di lima tab, dikelompokkan menurut tujuan:
/// mengelola klub, kompetisi, informasi, lalu akun.
///
/// Tiap baris membawa satu angka hidup sebagai subjudul. Kalau datanya belum
/// termuat (atau gagal), subjudul jatuh ke teks statis — halaman ini tidak
/// boleh kosong hanya karena satu permintaan gagal.
class MorePage extends StatefulWidget {
  const MorePage({super.key});

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  late Future<_Counts> _future;

  /// Data anggota milik akun yang sedang masuk (untuk "Akun saya").
  ///
  /// Null kalau akun ini bukan anggota klub (admin/bendahara) atau kalau
  /// pemuatannya gagal — barisnya lalu disembunyikan, bukan menampilkan
  /// halaman kosong.
  Future<Member?>? _meFuture;

  /// Nilai `Db.writes` saat angka terakhir dimuat.
  int _seenWrites = Db.writes.value;

  @override
  void initState() {
    super.initState();
    _future = _Counts.load();
    _meFuture = _loadMe();
    Db.writes.addListener(_onWrites);
  }

  Future<Member?> _loadMe() async {
    final id = Auth.memberId;
    if (id == null) return null;
    try {
      return await Member.byId(id);
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    Db.writes.removeListener(_onWrites);
    super.dispose();
  }

  /// Angka di halaman ini harus ikut berubah setelah ada tulis.
  ///
  /// Dulu `_Counts` hanya dimuat di `initState`, jadi setelah menambah anggota
  /// lewat Lainnya → Anggota (halaman yang di-push, bukan tab lain), subjudul
  /// tetap menampilkan angka lama — "1 aktif" padahal daftarnya sudah kosong.
  /// Pengguna melihat dua halaman yang saling bertentangan.
  void _onWrites() {
    if (!mounted || Db.writes.value == _seenWrites) return;
    _seenWrites = Db.writes.value;
    _reload();
  }

  Future<void> _reload() async {
    final f = _Counts.load();
    final me = _loadMe();
    setState(() {
      _future = f;
      _meFuture = me;
    });
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return PageScaffold(
      title: 'Lainnya',
      subtitle: 'Kelola klub & akun',
      // Tarik untuk menyegarkan: angka di baris ini bisa berubah dari tab
      // lain (iuran baru, booking baru), dan halaman ini tidak punya tombol
      // muat ulang sendiri.
      child: RefreshIndicator(
        onRefresh: _reload,
        child: FutureBuilder<_Counts>(
          future: _future,
          builder: (context, snap) {
            final c = snap.data;
            // Semua sumber gagal = server/jaringan bermasalah. Tanpa cabang
            // ini halaman tetap tampil dengan subjudul statis ("Belum ada
            // jadwal sewa"), sehingga gangguan server terbaca seperti data
            // kosong dan tidak ada cara mencoba lagi.
            final error = snap.hasError ? snap.error : null;
            return ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
            children: [
              _AccountStrip(),
              if (error != null)
                DegradedNotice(
                  failures: ['Data klub: ${errText(error)}'],
                  onRetry: _reload,
                ),
              if (c != null && c.failures.isNotEmpty)
                DegradedNotice(failures: c.failures, onRetry: _reload),
              if (Auth.isGuest)
                _Tile(
                  icon: Icons.login,
                  title: 'Masuk',
                  subtitle: 'Admin/bendahara bisa mengubah data setelah masuk',
                  highlight: true,
                  onTap: () async {
                    final ok = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (ctx) => LoginPage(onSignedIn: () => Navigator.pop(ctx, true)),
                      ),
                    );
                    if (ok == true && context.mounted) _reload();
                  },
                ),
              const SectionTitle('Kelola klub'),
              _Tile(
                icon: Icons.groups_outlined,
                title: 'Anggota',
                subtitle: c == null
                    ? 'Data pemain, posisi & nomor punggung'
                    : '${c.active} aktif'
                        '${c.inactive > 0 ? ' • ${c.inactive} nonaktif' : ''}',
                onTap: () => _open(context, const MembersPage()),
              ),
              _Tile(
                icon: Icons.stadium_outlined,
                title: 'Sewa lapangan',
                subtitle: c?.nextBooking == null
                    ? 'Belum ada jadwal sewa'
                    : 'Berikutnya ${fmtShortDate(c!.nextBooking!.startsAt)} '
                        '${fmtTime(c.nextBooking!.startsAt)}',
                onTap: () => _open(context, const BookingsPage()),
              ),
              _Tile(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Kas klub',
                subtitle: c == null
                    ? 'Pemasukan, pengeluaran & saldo'
                    : 'Saldo ${fmtShortMoney(c.saldo)} bulan ini'
                        '${c.saldo < 0 ? ' • defisit' : ''}',
                onTap: () => _open(context, const FinancePage()),
              ),
              const SectionTitle('Kompetisi'),
              _Tile(
                icon: Icons.emoji_events_outlined,
                title: 'Turnamen internal',
                subtitle: c == null
                    ? 'Semua tim saling bertemu, klasemen per grup'
                    : (c.playing > 0
                        ? '${c.playing} berjalan • ${c.tournaments} tersimpan'
                        : '${c.tournaments} tersimpan • tidak ada yang berjalan'),
                onTap: () => _open(context, const TournamentsPage()),
              ),
              _Tile(
                icon: Icons.leaderboard_outlined,
                title: 'Statistik',
                subtitle: c == null
                    ? 'Rekap hasil, pencetak gol & klasemen'
                    : '${c.played} laga selesai • pencetak gol & klasemen',
                onTap: () => _open(context, const StatsPage()),
              ),
              const SectionTitle('Informasi'),
              _Tile(
                icon: Icons.campaign_outlined,
                title: 'Pengumuman',
                subtitle: c == null || c.news == 0
                    ? 'Belum ada pengumuman'
                    : '${c.news} terbit • terakhir ${fmtShortDate(c.lastNews!.createdAt)}',
                onTap: () => _open(context, const AnnouncementsPage()),
              ),
              const SectionTitle('Akun'),
              // Halaman milik anggota sendiri. Role anggota adalah mayoritas
              // pengguna app ini, dan sebelumnya tidak punya tempat untuk
              // melihat "saya sudah bayar apa" tanpa mencari namanya di
              // daftar anggota.
              FutureBuilder<Member?>(
                future: _meFuture,
                builder: (context, snap) {
                  final m = snap.data;
                  if (m == null) return const SizedBox.shrink();
                  return _Tile(
                    icon: Icons.person_outline,
                    title: 'Akun saya',
                    subtitle: 'Iuran saya, tunggakan, jadwal main',
                    onTap: () => _open(context, MyAccountPage(member: m)),
                  );
                },
              ),
              if (Auth.isAdmin)
                _Tile(
                  icon: Icons.people_outline,
                  title: 'Pengguna',
                  subtitle: 'Akun & hak akses admin/bendahara',
                  onTap: () => _open(context, const UsersPage()),
                ),
              // Baris ini satu-satunya tempat pembaruan terlihat tanpa
              // membuka Pengaturan: kalau ada versi baru, subjudulnya berubah
              // dan ikonnya diberi titik hijau.
              ValueListenableBuilder<UpdateCheck?>(
                valueListenable: UpdateService.latest,
                builder: (context, check, _) {
                  final release = check?.release;
                  return _Tile(
                    icon: Icons.settings_outlined,
                    title: 'Pengaturan',
                    subtitle: release == null
                        ? 'Tema, server, pembaruan'
                        : 'Versi ${release.version} tersedia — ketuk untuk memasang',
                    highlight: release != null,
                    onTap: () => _open(context, const SettingsPage()),
                  );
                },
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'Minisoccer Club v$kAppVersion',
                  style: t.textTheme.small.copyWith(letterSpacing: 0.2),
                ),
              ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }
}

/// Siapa yang sedang masuk dan boleh berbuat apa. Ketuk untuk ke Pengaturan.
class _AccountStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final role = switch (Auth.role) {
      'admin' => 'Admin',
      'treasurer' => 'Bendahara',
      _ => 'Anggota',
    };
    final canWrite = Auth.canWrite;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            border: Border.all(color: t.colorScheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.colorScheme.muted,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  (Auth.username ?? '?').substring(0, 1).toUpperCase(),
                  style: t.textTheme.h2.copyWith(fontSize: 20, color: t.colorScheme.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Auth.username ?? 'Belum masuk',
                      style: t.textTheme.large,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    // Role sudah ada di pill kanan; di sini cukup hak aksesnya.
                    // Dulu barisnya mengulang role dan melipat dua baris di 320px.
                    Text(
                      canWrite ? 'Bisa mengubah data' : 'Hanya membaca',
                      style: t.textTheme.small,
                    ),
                  ],
                ),
              ),
              Pill(role, color: canWrite ? t.colorScheme.primary : null),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, size: 18, color: t.colorScheme.mutedForeground),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Baris yang butuh perhatian (mis. ada versi baru): subjudul hijau dan
  /// ikon diberi titik.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return RowItem(
      onTap: onTap,
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(
            color: highlight ? t.colorScheme.primary : t.colorScheme.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 17, color: t.colorScheme.primary),
      ),
      title: title,
      subtitle: subtitle,
      trailing: Icon(Icons.chevron_right, size: 18, color: t.colorScheme.mutedForeground),
    );
  }
}
