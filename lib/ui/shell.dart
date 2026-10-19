import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'dashboard.dart';
import 'members.dart';
import 'matches.dart';
import 'payments.dart';
import 'more.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [
    DashboardPage(),
    MembersPage(),
    MatchesPage(),
    PaymentsPage(),
    MorePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final dark = t.brightness == Brightness.dark;
    return Scaffold(
      // IndexedStack membangun kelima tab saat start: tab lain menyimpan
      // Future lama sehingga data yang ditulis di Beranda tidak pernah muncul
      // di Anggota/Iuran sampai app di-restart. Bangun hanya tab aktif supaya
      // tiap tab mengambil data saat dibuka.
      body: _pages[_index],
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: dark ? const Color(0xFF0E141C) : Colors.white,
          indicatorColor: t.colorScheme.primary.withValues(alpha: 0.18),
          labelTextStyle: WidgetStatePropertyAll(t.textTheme.small),
          iconTheme: WidgetStateProperty.resolveWith(
            (s) => IconThemeData(
              size: 22,
              color: s.contains(WidgetState.selected)
                  ? t.colorScheme.primary
                  : t.colorScheme.mutedForeground,
            ),
          ),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        child: NavigationBar(
          height: 64,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Beranda'),
            NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'Anggota'),
            NavigationDestination(icon: Icon(Icons.sports_soccer_outlined), selectedIcon: Icon(Icons.sports_soccer), label: 'Tanding'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Iuran'),
            NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Lainnya'),
          ],
        ),
      ),
    );
  }
}
