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
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: t.colorScheme.border.withValues(alpha: 0.7)),
          ),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: dark ? const Color(0xFF0E141C) : Colors.white,
            indicatorColor: t.colorScheme.primary.withValues(alpha: 0.16),
            indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            labelTextStyle: WidgetStateProperty.resolveWith(
              (s) => t.textTheme.small.copyWith(
                fontSize: 10.5,
                fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
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
            height: 62,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
      ),
    );
  }
}
