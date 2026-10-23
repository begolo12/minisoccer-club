// Uji nyata: apakah web bisa dibuka tanpa jaringan?
//
// Emulasi offline lewat CDP (`Network.emulateNetworkConditions`) tidak bisa
// dipakai untuk menguji service worker: request dokumen gagal di lapisan
// jaringan sebelum SW sempat mencegat, jadi hasilnya selalu "gagal" walau SW
// benar. Di sini jaringannya benar-benar diputus: server statis dimatikan,
// lalu halaman dimuat ulang. Kalau SW bekerja, app tetap terbuka.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { extname, join, normalize } from 'node:path';
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const root = 'build/web';
const port = 8300 + Math.floor(Math.random() * 200);
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.css': 'text/css; charset=utf-8',
};

// Aplikasi dipasang di sub-jalur (`/minisoccer/`), jadi uji ini juga harus
// menyajikannya di sana: `<base href>` menentukan tempat service worker
// mencari aset, dan menyajikan di akar akan menguji konfigurasi yang tidak
// pernah dipakai pengguna.
const PREFIX = '/minisoccer';

const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === PREFIX) {
    res.writeHead(302, { location: `${PREFIX}/` });
    return res.end();
  }
  // Prefiks dibuang SEBELUM `normalize`: di Windows, `normalize` mengubah
  // garis miring menjadi backslash sehingga pencocokan prefiks tidak pernah
  // kena — berkas selalu dianggap tidak ada dan server mengembalikan
  // index.html. Service worker lalu ditolak browser karena MIME-nya HTML.
  let p = decodeURIComponent(url.pathname);
  if (p.startsWith(PREFIX + '/')) p = p.slice(PREFIX.length);
  p = normalize(p).replace(/^([/\\])+/, '');
  if (p === '' || !existsSync(join(root, p))) p = 'index.html';
  try {
    const body = await readFile(join(root, p));
    res.writeHead(200, {
      'content-type': types[extname(p)] ?? 'application/octet-stream',
      // Service worker butuh scope dari root.
      'service-worker-allowed': '/',
      'cache-control': 'no-cache',
    });
    res.end(body);
  } catch {
    res.writeHead(404).end('not found');
  }
});

await new Promise((r) => server.listen(port, r));
const base = `http://localhost:${port}${PREFIX}/`;
console.log(`server: ${base}`);

const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new',
  `--remote-debugging-port=${port + 400}`,
  '--no-sandbox',
  '--disable-gpu',
  `--user-data-dir=${process.env.TEMP}/chrome-swlocal-${port}`,
  'about:blank',
]);

let ws;
let msgId = 0;
const pending = new Map();
const send = (method, params = {}) =>
  new Promise((resolve) => {
    const id = ++msgId;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
const evaluate = async (expression) =>
  (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }))
    ?.result?.value;

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

try {
  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(300);
    try {
      const list = await (await fetch(`http://127.0.0.1:${port + 400}/json/list`)).json();
      target = list.find((t) => t.type === 'page');
    } catch {
      /* belum siap */
    }
  }
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));
  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg.result ?? msg.error);
      pending.delete(msg.id);
    }
  });

  await send('Page.enable');
  await send('Runtime.enable');
  await send('Page.navigate', { url: base });
  await sleep(11000);

  const before = await evaluate(`(async () => {
    const regs = await navigator.serviceWorker.getRegistrations();
    return {
      active: regs.some((r) => r.active && r.active.state === 'activated'),
      controller: !!navigator.serviceWorker.controller,
      caches: await caches.keys(),
    };
  })()`);
  check('service worker aktif saat online', before?.active === true, JSON.stringify(before));
  check('halaman dikendalikan service worker', before?.controller === true);
  check(
    'shell tersimpan di cache',
    (before?.caches ?? []).some((c) => c.startsWith('msc-shell-')),
    JSON.stringify(before?.caches),
  );

  // ---------- matikan server: jaringan benar-benar putus ----------
  await new Promise((r) => server.close(r));
  console.log('server dimatikan — sekarang benar-benar offline');
  await sleep(1200);

  await send('Page.reload');
  await sleep(9000);

  const url = await evaluate('location.href');
  const isError = (url ?? '').startsWith('chrome-error://');
  check('halaman dimuat ulang tanpa server', !isError, url);

  const hasApp = await evaluate(
    `!!document.querySelector('flt-glass-pane') || !!document.querySelector('flutter-view') || !!document.querySelector('flt-semantics-placeholder')`,
  );
  check('aplikasi Flutter benar-benar jalan dari cache', hasApp === true);

  // localStorage (antrean + cache data) harus tetap ada setelah reload offline.
  const storage = await evaluate(`(() => {
    let cacheKeys = 0;
    for (let i = 0; i < localStorage.length; i++) {
      if ((localStorage.key(i) || '').startsWith('qcache:')) cacheKeys++;
    }
    return { cacheKeys, outbox: localStorage.getItem('outbox:v1') };
  })()`);
  console.log(`  [info] entri cache data: ${storage?.cacheKeys}`);
} finally {
  chrome.kill();
  try {
    server.close();
  } catch {
    /* sudah ditutup */
  }
  const bad = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - bad}/${results.length} lulus.`);
  process.exit(bad ? 1 : 0);
}
