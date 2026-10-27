import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'api.dart';
import 'db.dart';

/// Satu-satunya jalur DB: Vercel Function `api/sql.js` (Neon HTTP driver).
/// Dipakai web maupun APK — kredensial Postgres tidak pernah ada di klien.
const usesProxy = true;

/// Batas tunggu satu permintaan. Tanpa ini, jaringan buruk membuat layar
/// berputar selamanya tanpa jalan keluar.
const _timeout = Duration(seconds: 20);

/// Jendela penggabungan.
///
/// Satu layar biasanya meminta beberapa sumber sekaligus (`Future.wait`).
/// Tanpa penggabungan, tiap query menjadi satu perjalanan pulang-pergi
/// jaringan sendiri: Beranda = 10 permintaan. Di HP dengan RTT 100 ms itu
/// berarti satu detik penuh hanya untuk menunggu jaringan, sebelum satu byte
/// data klub terbaca.
///
/// Semua query yang dimulai dalam jendela ini dikirim sebagai SATU permintaan
/// (`{queries:[…]}`); server menjalankannya paralel dan menjawab per item.
/// 6 ms tidak terasa, tetapi cukup untuk menampung satu gelombang `Future.wait`.
const _coalesceWindow = Duration(milliseconds: 6);

/// Harus sama dengan batas di `api/sql.js`.
const _maxBatch = 20;

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

/// Satu query yang menunggu dikirim.
class _Pending {
  _Pending(this.sql, this.params, this.writeId);

  final String sql;
  final Map<String, Object?> params;
  final String? writeId;
  final Completer<Map<String, dynamic>> done = Completer<Map<String, dynamic>>();
}

final List<_Pending> _queue = <_Pending>[];
Timer? _flushTimer;

/// Kirim query, gabungkan dengan query lain yang dimulai bersamaan.
Future<Map<String, dynamic>> _post(
  String sql,
  Map<String, Object?> params, {
  String? writeId,
}) {
  final p = _Pending(sql, params, writeId);
  _queue.add(p);
  _flushTimer ??= Timer(_coalesceWindow, _flush);
  return p.done.future;
}

void _flush() {
  _flushTimer = null;
  if (_queue.isEmpty) return;

  final batch = _queue.take(_maxBatch).toList();
  _queue.removeRange(0, batch.length);
  if (_queue.isNotEmpty) _flushTimer = Timer(Duration.zero, _flush);

  if (batch.length == 1) {
    _sendSingle(batch.single);
  } else {
    _sendBatch(batch);
  }
}

Map<String, Object?> _wireParams(Map<String, Object?> params) => {
      for (final e in params.entries)
        e.key: e.value is DateTime
            // Neon HTTP tidak kenal tipe DateTime; kirim sebagai ISO-8601.
            ? (e.value as DateTime).toUtc().toIso8601String()
            : e.value,
    };

Future<http.Response> _send(Object body) {
  final token = Db.authToken;
  return _client
      .post(
        Uri.parse(kSqlEndpoint),
        headers: {
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      )
      .timeout(_timeout);
}

/// Ubah kegagalan transport menjadi pesan yang bisa ditampilkan.
Object _transportError(Object e) {
  if (e is TimeoutException) {
    return ApiException('Server tidak merespons. Periksa koneksi lalu coba lagi.');
  }
  if (e is http.ClientException) {
    return ApiException('Tidak bisa menghubungi server. Periksa koneksi internet.');
  }
  return e;
}

Map<String, dynamic> _decode(http.Response res) {
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
    throw ApiException('Balasan server tidak berisi data.');
  }
  return body;
}

Future<void> _sendSingle(_Pending p) async {
  try {
    final res = await _send({
      'sql': p.sql,
      'params': _wireParams(p.params),
      if (p.writeId != null) 'writeId': p.writeId,
    });
    p.done.complete(_decode(res));
  } catch (e) {
    p.done.completeError(_transportError(e));
  }
}

Future<void> _sendBatch(List<_Pending> batch) async {
  try {
    final res = await _send({
      'queries': [
        for (final p in batch)
          {
            'sql': p.sql,
            'params': _wireParams(p.params),
            if (p.writeId != null) 'writeId': p.writeId,
          },
      ],
    });
    final body = _decode(res);
    final results = body['results'];
    if (results is! List || results.length != batch.length) {
      // Bentuk balasan tidak dikenal: jangan menebak — semua gagal, lalu
      // `Db` menanganinya seperti gangguan jaringan (cache/antrean).
      throw ApiException('Balasan server tidak berisi data.');
    }
    for (var i = 0; i < batch.length; i++) {
      final item = results[i];
      final p = batch[i];
      if (p.done.isCompleted) continue;
      if (item is Map && item['error'] is String) {
        p.done.completeError(ApiException(item['error'] as String));
      } else if (item is Map) {
        p.done.complete(Map<String, dynamic>.from(item));
      } else {
        p.done.completeError(ApiException('Balasan server tidak berisi data.'));
      }
    }
  } catch (e) {
    // Server versi lama (belum ikut di-deploy) tidak mengenal bentuk batch:
    // `body.sql` kosong, jadi dijawab "sql required". Kirim ulang satu per
    // satu supaya aplikasi baru tetap jalan sebelum server diperbarui.
    if (e is ApiException && e.message == 'sql required') {
      for (final p in batch) {
        await _sendSingle(p);
      }
      return;
    }
    final err = _transportError(e);
    for (final p in batch) {
      if (!p.done.isCompleted) p.done.completeError(err);
    }
  }
}

/// Acak 96-bit, cukup unik untuk idempoten tulis tanpa menambah dependensi.
String _randomId() {
  final r = math.Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < 12; i++) {
    b.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return 'w${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${b.toString()}';
}

Future<List<Map<String, dynamic>>> query(
  String sql, {
  Map<String, Object?> params = const {},
  String? writeId,
}) async {
  final body = await _post(sql, params, writeId: writeId);
  final rows = body['rows'];
  if (rows is! List) throw ApiException('Balasan server tidak berisi data.');
  return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
}

Future<int> execute(
  String sql, {
  Map<String, Object?> params = const {},
  String? writeId,
}) async {
  final body = await _post(sql, params, writeId: writeId);
  return (body['rowCount'] as int?) ?? 0;
}

Future<void> close() async {}

/// Id untuk tulis idempoten. Diekspor supaya antrean offline memakai id yang
/// sama dengan percobaan Online yang mungkin sudah sampai ke server.
String newWriteId() => _randomId();