// Daftar objek DB yang boleh disentuh koneksi web (`app_web`).
//
// Satu sumber kebenaran: dipakai `scripts/harden-db.mjs` untuk GRANT dan
// `api/_app-queries.test.mjs` untuk memastikan setiap tabel/view yang dipanggil
// app benar-benar punya izin. Tanpa ini, query baru lolos tes filter SQL tapi
// gagal `permission denied` di Neon — persis yang terjadi pada
// `tournament_teams` dan `v_team_standings`.
export const APP_WEB_TABLES = [
  'members',
  'matches',
  'match_sessions',
  'match_events',
  'transactions',
  'payments',
  'bookings',
  'booking_attendance',
  'announcements',
  'settings',
  'tournaments',
  'tournament_teams',
  'tournament_matches',
  'teams',
  'team_players',
  // Ditulis server (bukan klien) untuk tulis idempoten; lihat api/sql.js.
  'applied_writes',
];

export const APP_WEB_VIEWS = ['v_team_standings'];
