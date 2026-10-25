/// Prefiks jalur aplikasi di web, diambil dari `<base href>` halaman.
///
/// Kenapa bukan `Uri.base`: `Uri.base` adalah `location.href`, yaitu alamat
/// yang sedang dibuka — termasuk nama rute. Saat pengguna membuka
/// `/minisoccer/daftar`, prefiks yang dihitung dari situ akan ikut memuat
/// `daftar`, dan panggilan API mendarat di `/minisoccer/daftar/api/sql`
/// (404). `<base href>` justru menyatakan dengan tepat di mana aplikasi
/// dipasang, dan sudah diisi oleh `flutter build web --base-href`.
library;

import 'package:web/web.dart' as web;

/// Contoh hasil: `/minisoccer`, atau kosong kalau dipasang di akar domain.
String documentPathPrefix() {
  var path = Uri.parse(web.document.baseURI).path;
  // `<base href>` selalu berakhir dengan garis miring; buang supaya
  // penggabungan dengan `/api/...` tidak menghasilkan garis miring ganda.
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  return path == '/' ? '' : path;
}
