import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api.dart';
import 'db.dart';

/// Satu-satunya jalur DB: Vercel Function `api/sql.js` (Neon HTTP driver).
/// Dipakai web maupun APK — kredensial Postgres tidak pernah ada di klien.
const usesProxy = true;

/// Batas tunggu satu permintaan. Tanpa ini, jaringan buruk membuat layar
/// berputar selamanya tanpa jalan keluar.
const _timeout = Duration(seconds: 20);

/// Klien HTTP. Bisa diganti di tes (`useClient`) supaya jalur 401 dan timeout
/// diuji tanpa jaringan.
http.Client _client = http.Client();

void useClient(http.Client client) => _client = client;

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<Map<String, dynamic>> _post(String sql, Map<String, Object?> params) async {
  final token = Db.authToken;
  late final http.Response res;
  try {
    res = await _client
        .post(
          Uri.parse(kSqlEndpoint),
          headers: {
            'content-type': 'application/json',
            if (token != null) 'authorization': 'Bearer $token',
          },
          // Neon HTTP tidak kenal tipe DateTime; kirim sebagai ISO-8601.
          body: jsonEncode({
            'sql': sql,
            'params': {
              for (final e in params.entries)
                e.key: e.value is DateTime
                    ? (e.value as DateTime).toUtc().toIso8601String()
                    : e.value,
            },
          }),
        )
        .timeout(_timeout);
  } on TimeoutException {
    throw ApiException('Server tidak merespons. Periksa koneksi lalu coba lagi.');
  } on http.ClientException {
    throw ApiException('Tidak bisa menghubungi server. Periksa koneksi internet.');
  }

  if (res.statusCode == 401) throw Unauthorized();

  dynamic body;
  try {
    body = jsonDecode(res.body);
  } catch (_) {
    body = null;
  }

  if (res.statusCode != 200) {
    final message = body is Map ? body['error'] : null;
    throw ApiException(
      message is String && message.isNotEmpty ? message : 'Permintaan gagal (${res.statusCode})',
    );
  }
  if (body is! Map<String, dynamic>) {
    throw ApiException('Balasan server tidak dikenali.');
  }
  return body;
}

Future<List<Map<String, dynamic>>> query(
  String sql, {
  Map<String, Object?> params = const {},
}) async {
  final body = await _post(sql, params);
  final rows = body['rows'];
  if (rows is! List) throw ApiException('Balasan server tidak berisi data.');
  return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
}

Future<int> execute(
  String sql, {
  Map<String, Object?> params = const {},
}) async {
  final body = await _post(sql, params);
  return (body['rowCount'] as int?) ?? 0;
}

Future<void> close() async {}
