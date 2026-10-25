/// Penyimpanan antrean tulis offline untuk web (localStorage).
library;

import 'package:web/web.dart' as web;

const _key = 'outbox:v1';

/// Kontrak: null HANYA berarti "belum pernah ada antrean". Kegagalan baca
/// (mode privat, penyimpanan diblokir) dilempar supaya pemanggil tidak
/// menimpa antrean yang belum terbaca.
Future<String?> readOutbox() async {
  return web.window.localStorage.getItem(_key);
}

/// Kegagalan tulis (kuota penuh, mode privat) DILEMPAR: `Outbox._persist`
/// mencatatnya ke `Outbox.loadError` supaya kehilangan tidak terjadi diam.
Future<void> writeOutbox(String json) async {
  web.window.localStorage.setItem(_key, json);
}
