import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'dashboard.dart';
import 'members.dart';
import 'matches.dart';
import 'payments.dart';
import 'more.dart';
import 'theme.dart';

/// Navigasi utama. Di HP: bar bawah. Di layar lebar: rail kiri, karena bar
/// bawah yang melar 1400px adalah tanda layout mobile yang tidak disesuaikan.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _index = widget.initialTab.clamp(0, _pages.length - 1);

  static const _pages = [
    DashboardPage(),
    MembersPage(),
    MatchesPage(),
    PaymentsPage(),
    MorePage(),
  ];

  static const _dest = [
    (Icons.home_outlined, Icons.home_rounded, 'Beranda'),
    (Icons.groups_outlined, Icons.groups_rounded, 'Anggota'),
    (Icons.sports_soccer_outlined, Icons.sports_soccer, 'Tanding'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, 'Iuran'),
    (Icons.grid_view_outlined, Icons.grid_view_rounded, 'Lainnya'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final body = IndexedStack(index: _index, children: _pages);

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
                    for (var i = 0; i < _dest.length; i++) _RailItem(
                      icon: _dest[i].$1,
                      selectedIcon: _dest[i].$2,
                      label: _dest[i].$3,
                      selected: _index == i,
                      onTap: () => setState(() => _index = i),
                    ),
                  ],
                ),
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: body,
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
            onDestinationSelected: (i) => setState(() => _index = i),
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
