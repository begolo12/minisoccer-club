// Service worker: membuat aplikasi web bisa DIBUKA dan DIPAKAI saat offline.
//
// Kenapa perlu: Flutter 3.47 tidak lagi membuat service worker (opsi
// `--pwa-strategy` sudah dihapus; `flutter_service_worker.js` yang dihasilkan
// hanya stub). Tanpa service worker, membuka atau memuat ulang halaman saat
// jaringan mati menampilkan halaman error browser — padahal antrean tulis
// offline tersimpan di localStorage dan seharusnya tetap bisa diakses.
//
// Strategi:
//   * Install: precache SEMUA berkas dari `sw-manifest.json` (dibuat saat
//     build oleh `scripts/gen-sw-manifest.mjs`). Ini wajib: pada pemuatan
//     pertama SW baru aktif setelah halaman selesai memuat asetnya, jadi tanpa
//     precache, canvaskit/potongan main.dart.js tidak pernah masuk cache dan
//     aplikasi tidak bisa start offline.
//   * Navigasi & aset → cache-first, lalu perbarui di latar
//     (stale-while-revalidate).
//   * `/version.json` → selalu dari jaringan, supaya pemeriksaan pembaruan
//     tetap melihat versi server sebenarnya.
//   * `/api/*` → tidak disentuh. Data klub tidak dilayani dari cache HTTP;
//     cache data ada di localStorage (`qcache:`) dan dikelola aplikasi.

const CACHE = 'msc-shell-v2';

// Berkas minimum kalau manifest tidak tersedia (mis. dibuka dari file://).
const FALLBACK = ['index.html', 'flutter_bootstrap.js', 'main.dart.js', 'manifest.json'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE);
      let files = FALLBACK;
      try {
        const res = await fetch('sw-manifest.json', { cache: 'no-store' });
        if (res.ok) {
          const list = await res.json();
          if (Array.isArray(list) && list.length) files = list;
        }
      } catch {
        // Manifest tidak ada: pakai daftar minimum.
      }

      // Simpan berurutan dalam beberapa kumpulan. `cache.addAll` membatalkan
      // seluruh instalasi bila satu berkas gagal, jadi tiap berkas disimpan
      // sendiri-sendiri dan kegagalannya ditoleransi.
      const batch = 8;
      for (let i = 0; i < files.length; i += batch) {
        await Promise.all(
          files.slice(i, i + batch).map(async (url) => {
            try {
              await cache.add(new Request(url, { cache: 'reload' }));
            } catch {
              // Satu berkas gagal tidak boleh menggagalkan instalasi.
            }
          }),
        );
      }
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(
        names
          .filter((n) => n.startsWith('msc-shell-') && n !== CACHE)
          .map((n) => caches.delete(n)),
      );
      await self.clients.claim();
    })(),
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // Data klub: lewat aplikasi (localStorage + antrean), bukan cache HTTP.
  if (url.pathname.startsWith('/api/')) return;

  // Versi harus selalu segar: dipakai untuk mendeteksi pembaruan.
  if (url.pathname.endsWith('/version.json')) {
    event.respondWith(fetch(req, { cache: 'no-store' }).catch(() => caches.match(req)));
    return;
  }

  // Navigasi: sajikan shell dari cache bila offline.
  if (req.mode === 'navigate') {
    event.respondWith(
      (async () => {
        const cache = await caches.open(CACHE);
        const cached = await cache.match('index.html');
        const network = fetch(req)
          .then((res) => {
            if (res && res.ok) cache.put('index.html', res.clone());
            return res;
          })
          .catch(() => null);
        return cached ?? (await network) ?? Response.error();
      })(),
    );
    return;
  }

  // Aset: cache-first, perbarui di latar.
  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const cached = await cache.match(req);
      const network = fetch(req)
        .then((res) => {
          if (res && res.ok && res.type === 'basic') cache.put(req, res.clone());
          return res;
        })
        .catch(() => null);
      return cached ?? (await network) ?? Response.error();
    })(),
  );
});
