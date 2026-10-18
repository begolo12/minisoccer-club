import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../data/auth.dart';
import 'announcements.dart';
import 'bookings.dart';
import 'finance.dart';
import 'settings.dart';
import 'stats.dart';
import 'tournament.dart';
import 'users.dart';
import 'widgets.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Lainnya',
      subtitle: 'Fitur klub lainnya',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          _Tile(
            icon: Icons.emoji_events_outlined,
            title: 'Turnamen internal',
            subtitle: 'Round-robin, klasemen grup',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TournamentsPage())),
          ),
          _Tile(
            icon: Icons.stadium_outlined,
            title: 'Booking lapangan',
            subtitle: 'Jadwal sewa & biaya',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingsPage())),
          ),
          _Tile(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Kas klub',
            subtitle: 'Pemasukan, pengeluaran & saldo',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinancePage())),
          ),
          _Tile(
            icon: Icons.campaign_outlined,
            title: 'Pengumuman',
            subtitle: 'Info untuk anggota',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementsPage())),
          ),
          _Tile(
            icon: Icons.leaderboard_outlined,
            title: 'Statistik',
            subtitle: 'Rekap hasil & top skor',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsPage())),
          ),
          if (Auth.isAdmin)
            _Tile(
              icon: Icons.people_outline,
              title: 'Pengguna',
              subtitle: 'Akun & role admin/bendahara',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersPage())),
            ),
          _Tile(
            icon: Icons.settings_outlined,
            title: 'Pengaturan',
            subtitle: 'Tema, database, tentang',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return RowItem(
      onTap: onTap,
      leading: Icon(icon, size: 18, color: t.colorScheme.primary),
      title: title,
      subtitle: subtitle,
      trailing: Icon(Icons.chevron_right, size: 18, color: t.colorScheme.mutedForeground),
    );
  }
}
