// Tes: kapan pembaruan ditawarkan ke pengguna.
//
// Latar belakang: dulu pembaruan hanya terlihat sebagai titik hijau di tab
// "Lainnya". Pengguna yang tidak membuka tab itu tidak pernah tahu ada versi
// baru, sehingga aplikasi lama terus dipakai. Sekarang ada tawaran saat app
// dibuka — dan aturan "sekali per versi" inilah yang menjaga agar dialog tidak
// muncul setiap kali aplikasi dibuka.
import 'package:flutter_test/flutter_test.dart';
import 'package:minisoccer_club/core/update.dart';

ReleaseInfo _release(String version) => ReleaseInfo(
      tag: 'v$version',
      version: version,
      notes: 'catatan',
      apkUrl: 'https://example.com/app.apk',
      sizeBytes: 60 * 1024 * 1024,
      publishedAt: DateTime(2026, 10, 1),
    );

UpdateCheck _check({String? version, String current = '1.9.3', String? error}) =>
    UpdateCheck(
      current: current,
      release: version == null ? null : _release(version),
      error: error,
    );

void main() {
  group('shouldOfferUpdate', () {
    test('tidak menawarkan kalau tidak ada versi baru', () {
      expect(shouldOfferUpdate(null, null), isFalse);
      expect(shouldOfferUpdate(_check(), null), isFalse);
    });

    test('tidak menawarkan saat pemeriksaan gagal', () {
      expect(shouldOfferUpdate(_check(error: 'GitHub membalas 403'), null), isFalse);
    });

    test('menawarkan versi baru yang belum pernah ditutup', () {
      expect(shouldOfferUpdate(_check(version: '1.9.4'), null), isTrue);
    });

    test('tidak menawarkan lagi versi yang sudah ditutup dengan "Nanti"', () {
      expect(shouldOfferUpdate(_check(version: '1.9.4'), '1.9.4'), isFalse);
    });

    test('versi yang lebih baru tetap ditawarkan walau versi lama ditutup', () {
      // Inilah yang membuat "Nanti" tidak mematikan pembaruan selamanya.
      expect(shouldOfferUpdate(_check(version: '1.9.5'), '1.9.4'), isTrue);
    });
  });

  group('compareVersions', () {
    test('membandingkan per komponen angka, bukan per teks', () {
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('1.9.0', '1.10.0'), lessThan(0));
      expect(compareVersions('1.9.3', '1.9.3'), 0);
    });

    test('mengabaikan awalan v dan jumlah komponen berbeda', () {
      expect(compareVersions('v1.9.4', '1.9.3'), greaterThan(0));
      expect(compareVersions('1.9', '1.9.0'), 0);
      expect(compareVersions('2', '1.9.9'), greaterThan(0));
    });
  });

  group('parseRelease', () {
    Map<String, dynamic> json({String? digest, String? apkName = 'app-release.apk'}) => {
          'tag_name': 'v1.9.4',
          'body': 'Perbaikan kecil',
          'published_at': '2026-10-23T00:00:00Z',
          'assets': [
            if (apkName != null)
              {
                'name': apkName,
                'browser_download_url': 'https://example.com/app.apk',
                'size': 61000000,
                'digest': ?digest,
              },
          ],
        };

    test('membaca tag, versi, dan ukuran', () {
      final r = parseRelease(json())!;
      expect(r.tag, 'v1.9.4');
      expect(r.version, '1.9.4', reason: 'awalan v dibuang supaya bisa dibandingkan');
      expect(r.sizeBytes, 61000000);
    });

    test('membaca digest sha256 untuk verifikasi unduhan', () {
      final r = parseRelease(json(digest: 'sha256:abc123'))!;
      expect(r.sha256, 'abc123');
    });

    test('digest kosong berarti verifikasi dilewati, bukan gagal', () {
      expect(parseRelease(json())!.sha256, isNull);
    });

    test('rilis tanpa aset APK diabaikan', () {
      // Lebih baik "tidak ada pembaruan" daripada tombol unduh yang menunjuk
      // berkas yang salah.
      expect(parseRelease(json(apkName: null)), isNull);
      expect(parseRelease(json(apkName: 'catatan.txt')), isNull);
    });
  });

  test('fmtBytes memakai koma desimal seperti format Indonesia', () {
    expect(fmtBytes(61000000), '58,2 MB');
    expect(fmtBytes(500 * 1024), '500 KB');
    expect(fmtBytes(0), '—');
  });
}
