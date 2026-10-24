import 'package:flutter/foundation.dart' show kIsWeb;

/// Alamat server API.
///
/// Kosong = same-origin, dipakai versi web di Vercel.
/// APK wajib di-build dengan `--dart-define=API_BASE=https://...` supaya
/// tahu ke mana harus memanggil (APK tidak menyimpan kredensial Postgres).
const _apiBase = String.fromEnvironment('API_BASE', defaultValue: '');

/// Prefiks jalur tempat aplikasi web disajikan, tanpa garis miring di ujung.
///
/// Web bisa dipasang di akar domain (`https://minisoccer-club.vercel.app/`)
/// atau di bawah jalur portal (`https://airevo-digital.my.id/minisoccer/`).
/// Di kasus kedua `web/index.html` dibangun dengan `<base href="/minisoccer/">`,
/// dan panggilan `/api/sql` yang absolut akan mendarat di domain portal —
/// proyek lain, tanpa fungsi itu — sehingga aplikasi gagal memuat data.
///
/// `Uri.base` di web berisi `self.location.href`; jalur dokumen itu dipakai
/// sebagai prefiks. APK tidak punya dokumen, jadi prefiks hanya dihitung di
/// web dan hanya saat `API_BASE` kosong (APK selalu mengisinya absolut).
String get _pathPrefix {
  if (!kIsWeb || _apiBase.isNotEmpty) return '';
  var path = Uri.base.path;
  if (!path.endsWith('/')) path = path.substring(0, path.lastIndexOf('/') + 1);
  return path == '/' ? '' : path.substring(0, path.length - 1);
}

/// Basis API. Kosong di akar domain, `/minisoccer` saat dipasang di portal,
/// atau URL absolut untuk APK.
String get kApiBase => '$_apiBase$_pathPrefix';

String get kSqlEndpoint => '$kApiBase/api/sql';
String get kAuthEndpoint => '$kApiBase/api/auth';

/// Alamat publik aplikasi versi web — yang dibagikan ke orang lain.
///
/// Bukan `API_BASE`: APK memanggil API langsung ke host Vercel, tetapi alamat
/// yang dibagikan ke calon anggota harus alamat yang memang dipakai klub.
/// Selama keduanya disamakan, tautan pendaftaran yang disalin dari APK berbunyi
/// `minisoccer-club.vercel.app` — host teknis yang tidak dikenal siapa pun.
///
/// Bisa diganti saat build (`--dart-define=PUBLIC_WEB_URL=https://…`) untuk
/// pemasangan di domain lain; nilai bawaan adalah alamat resmi klub.
const _publicWebOverride = String.fromEnvironment('PUBLIC_WEB_URL', defaultValue: '');
const kPublicWebUrl = _publicWebOverride != ''
    ? _publicWebOverride
    : 'https://airevo-digital.my.id/minisoccer';

/// Tautan pendaftaran yang bisa dibagikan.
String get kRegistrationUrl => '$kPublicWebUrl/daftar';
