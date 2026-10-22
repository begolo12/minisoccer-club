/// Klasifikasi kegagalan jaringan.
///
/// Dipisah dari `db.dart` supaya bisa dipakai juga oleh antrean offline tanpa
/// impor melingkar.
///
/// **Kenapa daftar ini panjang.** Ini penentu apakah sebuah tulis masuk antrean
/// offline atau gagal begitu saja. Kalau pesan error tidak dikenali, pengguna
/// melihat "gagal menyimpan" padahal seharusnya datanya masuk antrean — dan di
/// HP, pesan yang muncul berbeda-beda menurut OS, operator, dan jenis putusnya
/// koneksi. Karena itu yang dicocokkan adalah POLA, bukan satu kalimat:
///
///   * Android/iOS tanpa jaringan: "Failed host lookup", "No address associated
///     with hostname", "Network is unreachable", "Connection refused";
///   * koneksi diputus di tengah jalan: "Connection closed before full header",
///     "Connection reset by peer", "Software caused connection abort";
///   * TLS di jaringan yang memblokir: "HandshakeException", "CERTIFICATE_VERIFY_FAILED";
///   * timeout: "TimeoutException", "timed out", "Server tidak merespons";
///   * WebView/browser: "ClientException", "Failed to fetch", "XMLHttpRequest error",
///     "Load failed" (Safari), "NetworkError".
///
/// Yang **bukan** kegagalan jaringan: jawaban server (400/403, "Query gagal
/// dijalankan", "Sesi habis"). Itu keputusan server; menulis ulang ke antrean
/// offline hanya akan mengulang penolakan yang sama.
library;

const _patterns = <String>[
  // Pesan sendiri (dibuat `db_web.dart`).
  'Tidak bisa menghubungi server',
  'Server tidak merespons',
  // dart:io / SocketException.
  'SocketException',
  'Failed host lookup',
  'No address associated with hostname',
  'Network is unreachable',
  'Connection refused',
  'Connection reset by peer',
  'Connection closed before full header',
  'Connection closed while receiving data',
  'Software caused connection abort',
  'Broken pipe',
  'OS Error: Network is down',
  // TLS.
  'HandshakeException',
  'CERTIFICATE_VERIFY_FAILED',
  // Waktu habis.
  'TimeoutException',
  'timed out',
  'Timeout',
  // Klien HTTP.
  'ClientException',
  'Failed to fetch',
  'XMLHttpRequest error',
  'NetworkError',
  'Load failed',
];

bool isNetworkFailure(Object e) {
  final msg = e.toString();
  for (final p in _patterns) {
    if (msg.contains(p)) return true;
  }
  return false;
}

/// Untuk tes: daftar pola yang dikenali.
List<String> debugNetworkPatterns() => List.unmodifiable(_patterns);
