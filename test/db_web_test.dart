import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:minisoccer_club/core/db.dart';
import 'package:minisoccer_club/core/db_web.dart';

void main() {
  tearDown(() {
    useClient(http.Client());
    Db.authToken = null;
    Db.onSessionExpired = null;
  });

  test('token ditolak: lempar Unauthorized dan panggil handler sesi', () async {
    var expired = 0;
    Db.onSessionExpired = () async => expired++;
    useClient(MockClient((_) async => http.Response('{"error":"x"}', 401)));

    await expectLater(Db.query('SELECT 1'), throwsA(isA<Unauthorized>()));
    expect(expired, 1);
  });

  test('tulis yang ditolak tidak menaikkan penghitung perubahan', () async {
    useClient(MockClient((_) async => http.Response('{"error":"x"}', 401)));
    final before = Db.writes.value;

    await expectLater(
      Db.execute("INSERT INTO members (name) VALUES ('A')"),
      throwsA(isA<Unauthorized>()),
    );
    expect(Db.writes.value, before);
  });

  test('tulis berhasil menaikkan penghitung perubahan, baca tidak', () async {
    useClient(MockClient((_) async => http.Response('{"rows":[],"rowCount":1}', 200)));
    final before = Db.writes.value;

    await Db.query('SELECT * FROM members');
    expect(Db.writes.value, before);

    await Db.execute("INSERT INTO members (name) VALUES ('A')");
    expect(Db.writes.value, before + 1);
  });

  test('pesan error server diteruskan apa adanya', () async {
    useClient(MockClient(
      (_) async => http.Response('{"error":"Akun member hanya bisa melihat data"}', 403),
    ));

    await expectLater(
      Db.execute("INSERT INTO members (name) VALUES ('A')"),
      throwsA(isA<ApiException>().having(
        (e) => e.message,
        'message',
        'Akun member hanya bisa melihat data',
      )),
    );
  });

  test('balasan bukan JSON tidak membuat app crash', () async {
    useClient(MockClient((_) async => http.Response('<html>502</html>', 502)));

    await expectLater(
      Db.query('SELECT 1'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('502'))),
    );
  });

  test('token dikirim sebagai bearer dan DateTime jadi ISO-8601', () async {
    Db.authToken = 'abc';
    Map<String, dynamic>? sent;
    useClient(MockClient((req) async {
      expect(req.headers['authorization'], 'Bearer abc');
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response('{"rows":[],"rowCount":1}', 200);
    }));

    await Db.execute(
      'UPDATE matches SET played_at=@at WHERE id=@id',
      params: {'at': DateTime.utc(2026, 10, 19, 13), 'id': 3},
    );

    final params = sent!['params'] as Map<String, dynamic>;
    expect(params['at'], '2026-10-19T13:00:00.000Z');
    expect(params['id'], 3);
  });
}
