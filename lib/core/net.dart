/// Klasifikasi kegagalan jaringan.
///
/// Dipisah dari `db.dart` supaya bisa dipakai juga oleh antrean offline tanpa
/// impor melingkar. Yang dianggap "jaringan mati": server tidak terjangkau,
/// timeout, DNS gagal, koneksi ditolak. Jawaban server (400/403, "Query gagal
/// dijalankan") **bukan** kegagalan jaringan — itu keputusan server, dan
/// menulis ulang ke antrean offline hanya akan mengulang penolakan yang sama.
library;

bool isNetworkFailure(Object e) {
  final msg = e.toString();
  return msg.contains('Tidak bisa menghubungi server') ||
      msg.contains('Server tidak merespons') ||
      msg.contains('SocketException') ||
      msg.contains('Failed host lookup') ||
      msg.contains('Connection refused') ||
      msg.contains('ClientException');
}
