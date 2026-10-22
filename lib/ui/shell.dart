import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../core/db.dart';
import 'dashboard.dart';
import 'fmt.dart';
import 'login.dart';
import 'matches.dart';
import 'payments.dart';
import 'more.dart';
import 'teams.dart';
import 'theme.dart';

/// Navigasi utama. Di HP: bar bawah. Di layar lebar: rail kiri, karena bar
/// bawah yang melar 1400px adalah tanda layout mobile yang tidak disesuaikan.
///
/// Tab dibangun saat pertama kali dibuka (bukan semuanya saat start), dan
/// dimuat ulang saat dibuka lagi setelah ada data yang berubah — jadi tab
/// lain tidak menampilkan angka lama.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0, this.readOnly = false});

  final int initialTab;

  /// Belum masuk: aplikasi terbuka sebagai tamu. Data terlihat, tombol tulis
  /// disembunyikan oleh `Auth.canWrite`, dan bilah mode publik menawarkan
  /// "Masuk" — layar login tidak lagi menghadang di depan.
  final bool readOnly;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _pages = [
    DashboardPage(),
    MatchesPage(),
    TeamsPage(),
    PaymentsPage(),
    MorePage(),
  ];

  static const _dest = [
    (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
    (Icons.sports_soccer_outlined, Icons.sports_soccer, 'Tanding'),
    (Icons.shield_outlined, Icons.shield_rounded, 'Tim'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Iuran'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Lainnya'),
  ];

  late int _index = widget.initialTab.clamp(0, _pages.length - 1);
  late bool _readOnly = widget.readOnly;
  final Set<int> _built = {};
  final List<int> _version = List.filled(_pages.length, 0);
  int _seenWrites = Db.writes.value;

  @override
  void initState() {
    super.initState();
    _built.add(_index);
  }

  @override
  void didUpdateWidget(HomeShell old) {
    super.didUpdateWidget(old);
    // Bootstrap membangun ulang HomeShell saat status sesi berubah. Tanpa ini
    // `_readOnly` tetap nilai pertama: login lewat halaman Lainnya/Pengaturan
    // meninggalkan bilah "Mode publik" (padahal sudah masuk), dan sebaliknya
    // sesi yang habis tidak memunculkan tombol Masuk lagi.
    if (widget.readOnly != old.readOnly && widget.readOnly != _readOnly) {
      setState(() => _readOnly = widget.readOnly);
    }
  }

  Future<void> _openLogin() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (ctx) => LoginPage(onSignedIn: () => Navigator.pop(ctx, true))),
    );
    if (!mounted || ok != true) return;
    setState(() {
      _readOnly = false;
      // Semua tab dimuat ulang: data publik bisa berbeda dengan data akun
      // (mis. iuran yang hanya boleh dilihat bendahara).
      for (var i = 0; i < _version.length; i++) {
        _version[i]++;
      }
    });
  }

  void _select(int i) {
    setState(() {
      // Ada tulis di tab lain? Muat ulang tab yang akan dibuka.
      if (Db.writes.value != _seenWrites) {
        _version[i]++;
        _seenWrites = Db.writes.value;
      }
      _index = i;
      _built.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _pages.length; i++)
          if (_built.contains(i))
            KeyedSubtree(key: ValueKey('page-$i-${_version[i]}'), child: _pages[i])
          else
            const SizedBox.shrink(),
      ],
    );

    // Bilah status di atas isi: mode publik (ada tombol Masuk) dan/atau
    // mode offline (data dari cache). Keduanya tidak menutupi halaman.
    final strip = _StatusStrip(
      readOnly: _readOnly,
      onLogin: _openLogin,
    );

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 216,
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: t.colorScheme.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MINISOCCER',
                            style: TextStyle(
                              fontFamily: AppThemes.display,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                              color: t.colorScheme.foreground,
                            ),
                          ),
                          Text('CLUB', style: t.textTheme.h4),
                        ],
                      ),
                    ),
                    for (var i = 0; i < _dest.length; i++)
                      _RailItem(
                        icon: _dest[i].$1,
                        selectedIcon: _dest[i].$2,
                        label: _dest[i].$3,
                        selected: _index == i,
                        onTap: () => _select(i),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [strip, Expanded(child: body)],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [strip, Expanded(child: body)],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.colorScheme.border)),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: t.colorScheme.background,
            indicatorColor: t.colorScheme.primary.withValues(alpha: 0.14),
            indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (s) => TextStyle(
                fontFamily: AppThemes.body,
                fontSize: 10.5,
                fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
                color: s.contains(WidgetState.selected)
                    ? t.colorScheme.primary
                    : t.colorScheme.mutedForeground,
              ),
            ),
            iconTheme: WidgetStateProperty.resolveWith(
              (s) => IconThemeData(
                size: 21,
                color: s.contains(WidgetState.selected)
                    ? t.colorScheme.primary
                    : t.colorScheme.mutedForeground,
              ),
            ),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
          ),
          child: NavigationBar(
            height: 60,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              for (final d in _dest)
                NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: selected ? t.colorScheme.primary.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 18,
                  color: selected ? t.colorScheme.primary : t.colorScheme.mutedForeground,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? t.colorScheme.foreground : t.colorScheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bilah tipis di atas isi: "Mode publik" (dengan tombol Masuk) dan/atau
/// "Offline" (data dari cache).
///
/// Dua keadaan ini bisa terjadi bersamaan (tamu membuka app tanpa jaringan),
/// jadi keduanya ditampilkan sebagai dua baris, bukan saling menimpa.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.readOnly, required this.onLogin});

  final bool readOnly;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: Db.offline,
      builder: (context, offline, _) {
        if (!readOnly && !offline) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (offline)
              Container(
                color: t.colorScheme.muted,
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, size: 14, color: t.colorScheme.mutedForeground),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        Db.offlineSince == null
                            ? 'Offline — menampilkan data tersimpan'
                            : 'Offline — data tersimpan ${fmtDate(Db.offlineSince!)} '
                                '${fmtTime(Db.offlineSince!)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.small,
                      ),
                    ),
                  ],
                ),
              ),
            if (readOnly)
              Container(
                decoration: BoxDecoration(
                  color: t.colorScheme.primary.withValues(alpha: 0.10),
                  border: Border(
                    bottom: BorderSide(color: t.colorScheme.border),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined, size: 14, color: t.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mode publik — hanya lihat',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.small.copyWith(color: t.colorScheme.foreground),
                      ),
                    ),
                    TextButton(
                      onPressed: onLogin,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Masuk'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
