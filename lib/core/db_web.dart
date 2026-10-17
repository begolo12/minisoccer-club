import 'dart:convert';

import 'package:http/http.dart' as http;

/// Driver web: browser tidak bisa buka TCP ke Postgres, jadi semua query
/// lewat Vercel Function `api/sql.js` (Neon HTTP driver).
const usesProxy = true;

/// Kosong = same-origin (`/api/sql`) — cocok kalau web di-host di Vercel.
const _endpoint = String.fromEnvironment('API_URL', defaultValue: '/api/sql');

/// Harus sama dengan env `APP_KEY` di Vercel. Isi lewat --dart-define saat build.
const _appKey = String.fromEnvironment('APP_KEY');

/// Neon HTTP tidak menerima named params, konversinya di server.
/// Nilai non-JSON (DateTime) diubah ke ISO string.
Map<String, dynamic> _jsonParams(Map<String, Object?> params) => {
      for (final e in params.entries)
        e.key: e.value is DateTime
            ? (e.value as DateTime).toUtc().toIso8601String()
            : e.value,
    };

Future<Map<String, dynamic>> _post(
  String sql,
  Map<String, Object?> params,
) async {
  final res = await http.post(
    Uri.parse(_endpoint),
    headers: {
      'content-type': 'application/json',
      if (_appKey.isNotEmpty) 'x-app-key': _appKey,
    },
    body: jsonEncode({'sql': sql, 'params': _jsonParams(params)}),
  );
  final body = jsonDecode(res.body);
  if (res.statusCode != 200) {
    throw Exception(body is Map ? (body['error'] ?? res.statusCode) : res.statusCode);
  }
  return body as Map<String, dynamic>;
}

Future<List<Map<String, dynamic>>> query(
  String sql, {
  required String url,
  Map<String, Object?> params = const {},
}) async {
  final body = await _post(sql, params);
  return (body['rows'] as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();
}

Future<int> execute(
  String sql, {
  required String url,
  Map<String, Object?> params = const {},
}) async {
  final body = await _post(sql, params);
  return (body['rowCount'] as int?) ?? 0;
}

Future<void> close() async {}
