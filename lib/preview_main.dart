// Entrypoint khusus preview UI (design tooling, tidak ikut deploy).
// Langsung masuk sebagai admin tanpa backend asli, dan bisa membuka satu
// halaman langsung supaya tiap layar bisa di-screenshot:
//   flutter build web --release -t lib/preview_main.dart -o build/preview
//   node design/mock/server.mjs
//   http://localhost:8099/?tab=2&theme=light&page=bookings
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'core/db.dart';
import 'data/auth.dart';
import 'main.dart' as app;
import 'ui/announcements.dart';
import 'ui/bookings.dart';
import 'ui/finance.dart';
import 'ui/matches.dart';
import 'ui/members.dart';
import 'ui/settings.dart';
import 'ui/stats.dart';
import 'ui/teams.dart';
import 'ui/theme.dart';
import 'ui/tournament.dart';
import 'ui/users.dart';
import 'ui/widgets.dart';
import 'data/models.dart';

Future<void> main() async {
  final q = Uri.base.queryParameters;
  // ?guest=1 membuka mode publik (tanpa sesi) seperti app asli sebelum masuk.
  final guest = q['guest'] == '1';
  if (!guest && q['login'] != '1') {
    Auth.username = 'admin';
    Auth.role = 'admin';
    Auth.token = 'preview';
    Db.authToken = 'preview';
    Auth.session.value = true;
  }
  // ?role=member|treasurer untuk memeriksa tampilan tanpa hak tulis.
  final role = q['role'];
  if (role != null && (role == 'member' || role == 'treasurer')) {
    Auth.username = 'anggota';
    Auth.role = role;
  }
  if (q['theme'] == 'light') {
    await SecureStore.write('theme', 'light');
    ThemeController.mode.value = ThemeMode.light;
  }
  if (q['theme'] == 'dark') {
    await SecureStore.write('theme', 'dark');
    ThemeController.mode.value = ThemeMode.dark;
  }

  final page = q['page'];
  if (page == null) {
    app.main(initialTab: int.tryParse(q['tab'] ?? '') ?? 0);
    return;
  }

  runApp(
    ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.mode,
      builder: (context, mode, _) => ShadApp(
        title: 'Minisoccer Club',
        debugShowCheckedModeBanner: false,
        theme: AppThemes.light,
        darkTheme: AppThemes.dark,
        themeMode: mode,
        locale: const Locale('id', 'ID'),
        supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
        scrollBehavior: const AppScrollBehavior(),
        home: ShadSonner(child: _Page(name: page, id: int.tryParse(q['id'] ?? ''))),
      ),
    ),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.name, required this.id});

  final String name;

  /// `?id=` memilih baris tertentu (tim/laga) supaya halaman yang hanya
  /// menampilkan data pertama tetap bisa diperiksa untuk baris lain.
  final int? id;

  @override
  Widget build(BuildContext context) {
    return switch (name) {
      'bookings' => const BookingsPage(),
      'members' => const MembersPage(),
      'finance' => const FinancePage(),
      'announcements' => const AnnouncementsPage(),
      'stats' => const StatsPage(),
      'users' => const UsersPage(),
      'settings' => const SettingsPage(),
      'tournaments' => const TournamentsPage(),
      'team' => FutureBuilder<List<Team>>(
          future: Team.all(),
          builder: (context, s) {
            final all = s.data ?? const <Team>[];
            final t = all.where((t) => t.id == id).firstOrNull ?? all.firstOrNull;
            if (t == null) return const SizedBox.shrink();
            return TeamDetailPage(team: t);
          },
        ),
      'match' => FutureBuilder<List<Match>>(
          future: Match.all(),
          builder: (context, s) {
            final all = s.data ?? const <Match>[];
            final m = all.where((m) => m.id == id).firstOrNull ??
                all.where((m) => m.status == 'finished').firstOrNull ??
                all.firstOrNull;
            if (m == null) return const SizedBox.shrink();
            return MatchDetailPage(match: m);
          },
        ),
      'tournament' => FutureBuilder<List<Tournament>>(
          future: Tournament.all(),
          builder: (context, s) {
            final t = s.data?.firstOrNull;
            if (t == null) return const SizedBox.shrink();
            return TournamentDetailPage(tournament: t);
          },
        ),
      _ => const SizedBox.shrink(),
    };
  }
}
