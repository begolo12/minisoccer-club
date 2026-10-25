/// Unduh berkas di web: Blob + `<a download>`, lalu revoke URL-nya.
///
/// Dipakai ekspor CSV buku kas. `download` membuat browser menyimpan berkas
/// alih-alih menavigasi, dan nama berkasnya ikut ditetapkan di sini —
/// `kas-2026-10.csv`, bukan UUID dari server.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool get canSaveFile => true;

Future<void> saveTextFile(String name, String mime, String content) async {
  final bytes = utf8.encode(content).toJS;
  final blob = web.Blob([bytes].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
