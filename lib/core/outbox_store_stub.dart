/// Penyimpanan antrean tulis offline untuk web (localStorage).
library;

import 'package:web/web.dart' as web;

const _key = 'outbox:v1';

Future<String?> readOutbox() async {
  try {
    return web.window.localStorage.getItem(_key);
  } catch (_) {
    return null;
  }
}

Future<void> writeOutbox(String json) async {
  try {
    web.window.localStorage.setItem(_key, json);
  } catch (_) {
    // Kuota penuh / mode privat.
  }
}
