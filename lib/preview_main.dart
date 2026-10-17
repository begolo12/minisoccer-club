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
import 'ui/matches.dart';
import 'ui/settings.dart';
import 'ui/stats.dart';
import 'ui/theme.dart';
import 'ui/tournament.dart';
import 'ui/users.dart';
import 'data/models.dart';

Future<void> main() async {
  final q = Uri.base.queryParameters;
  if (q['login'] != '1') {
    Auth.username = 'admin';
    Auth.role = 'admin';
    Auth.token = 'preview';
    Db.authToken = 'preview';
    Auth.session.value = true;
  }
  if (q['theme'] == 'light') await SecureStore.write('theme', 'light');
  if (q['theme'] == 'dark') await SecureStore.write('theme', 'dark');

  final page = q['page'];
  if (page == null) {
    app.main(initialTab: int.tryParse(q['tab'] ?? '') ?? 0);
    return;
  }

  final dark = q['theme'] != 'light';
  runApp(
    ShadApp(
      title: 'Minisoccer Club',
      debugShowCheckedModeBanner: false,
      theme: AppThemes.light,
      darkTheme: AppThemes.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: ShadSonner(child: _Page(name: page)),
    ),
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return switch (name) {
      'bookings' => const BookingsPage(),
      'announcements' => const AnnouncementsPage(),
      'stats' => const StatsPage(),
      'users' => const UsersPage(),
      'settings' => const SettingsPage(),
      'tournaments' => const TournamentsPage(),
      'match' => FutureBuilder<List<Match>>(
          future: Match.all(),
          builder: (context, s) {
            final all = s.data ?? const <Match>[];
            final m = all.where((m) => m.status == 'finished').firstOrNull ?? all.firstOrNull;
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
