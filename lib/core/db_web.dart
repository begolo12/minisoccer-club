import 'dart:convert';

import 'package:http/http.dart' as http;

import 'db.dart';

/// Driver web: browser tidak bisa buka TCP ke Postgres, jadi query dikirim
/// ke Vercel Function `api/sql.js` (Neon HTTP driver).
const usesProxy = true;

/// Default same-origin — cocok saat di-host di Vercel.
const _endpoint = String.fromEnvironment('API_URL', defaultValue: '/api/sql');

Future<Map<String, dynamic>> _post(String sql, Map<String, Object?> params) async {
  final token = Db.authToken;
  final res = await http.post(
    Uri.parse(_endpoint),
    headers: {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    },
    // Neon HTTP tidak kenal tipe DateTime; kirim sebagai ISO-8601.
    body: jsonEncode({
      'sql': sql,
      'params': {
        for (final e in params.entries)
          e.key: e.value is DateTime ? (e.value as DateTime).toUtc().toIso8601String() : e.value,
      },
    }),
  );
  if (res.statusCode == 401) throw Unauthorized();
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
  return (body['rows'] as List).map((r) => Map<String, dynamic>.from(r as Map)).toList();
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
