import 'dart:async';

import 'package:postgres/postgres.dart';

/// Driver native (Android/iOS/desktop): koneksi TCP langsung ke Neon.
const usesProxy = false;

/// ponytail: satu koneksi dipakai bersama — cukup untuk klub kecil (<10 user).
/// Kalau nanti butuh request paralel tinggi, ganti ke Pool.
Connection? _conn;
Completer<Connection>? _connecting;

Future<Connection> _instance(String url) async {
  final existing = _conn;
  if (existing != null) return existing;
  if (_connecting != null) return _connecting!.future;

  final completer = Completer<Connection>();
  _connecting = completer;
  try {
    final c = await Connection.openFromUrl(url);
    _conn = c;
    completer.complete(c);
    return c;
  } catch (e, st) {
    _connecting = null;
    completer.completeError(e, st);
    rethrow;
  }
}

Future<List<Map<String, dynamic>>> query(
  String sql, {
  required String url,
  Map<String, Object?> params = const {},
}) async {
  final c = await _instance(url);
  final result = await c.execute(Sql.named(sql), parameters: params);
  return result.map((r) => r.toColumnMap()).toList();
}

Future<int> execute(
  String sql, {
  required String url,
  Map<String, Object?> params = const {},
}) async {
  final c = await _instance(url);
  final result = await c.execute(Sql.named(sql), parameters: params);
  return result.affectedRows;
}

Future<void> close() async {
  try {
    await _conn?.close();
  } finally {
    _conn = null;
    _connecting = null;
  }
}
