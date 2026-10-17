import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'announcements.dart';
import 'bookings.dart';
import 'settings.dart';
import 'stats.dart';
import 'users.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = ShadTheme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Text('Lainnya', style: t.textTheme.h3),
            const SizedBox(height: 4),
            Text('Fitur klub lainnya', style: t.textTheme.small),
            const SizedBox(height: 20),
            _Tile(
              icon: Icons.stadium_outlined,
              title: 'Booking lapangan',
              subtitle: 'Jadwal sewa & biaya',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BookingsPage())),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.colorScheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.colorScheme.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: t.colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: t.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: t.textTheme.small),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: t.colorScheme.mutedForeground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
