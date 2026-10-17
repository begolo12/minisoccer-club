/// Alamat server API.
///
/// Kosong = same-origin, dipakai versi web di Vercel.
/// APK wajib di-build dengan `--dart-define=API_BASE=https://...` supaya
/// tahu ke mana harus memanggil (APK tidak menyimpan kredensial Postgres).
const kApiBase = String.fromEnvironment('API_BASE', defaultValue: '');
const kSqlEndpoint = '$kApiBase/api/sql';
const kAuthEndpoint = '$kApiBase/api/auth';
