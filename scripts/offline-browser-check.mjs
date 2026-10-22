// Uji offline-first di BROWSER SUNGGUHAN terhadap produksi.
//
// Bedanya dengan `test/offline_first_test.dart`: di sana jaringan dipalsukan
// lewat mock HTTP. Di sini Chrome benar-benar dimatikan jaringannya
// (`Network.emulateNetworkConditions offline`), app yang dipakai adalah build
// produksi, dan penyimpanannya localStorage asli.
//
// Alur yang dibuktikan:
//   1. Login sebagai admin, buka halaman Anggota.
//   2. Tambah anggota saat ONLINE → tersimpan ke server.
//   3. Matikan jaringan → tambah anggota → harus tetap tersimpan dan terlihat.
//   4. Muat ulang halaman (masih offline) → data tadi harus masih ada
//      (membuktikan antrean disimpan, bukan hanya di memori).
//   5. Nyalakan jaringan → tekan Sinkron → anggota harus ada di database.
//   6. Bersihkan data uji.
//
//   node scripts/offline-browser-check.mjs
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const base = (process.env.BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPass = process.env.ADMIN_PASS || 'admin123';
const port = 9600 + Math.floor(Math.random() * 300);
const tag = `_ob_${Date.now().toString(36)}`;

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new',
  `--remote-debugging-port=${port}`,
  '--no-sandbox',
  '--disable-gpu',
  `--user-data-dir=${process.env.TEMP}/chrome-offline-${port}`,
  'about:blank',
]);

let ws;
let msgId = 0;
const pending = new Map();

async function connect() {
  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(300);
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      target = list.find((t) => t.type === 'page');
    } catch {
      /* chrome belum siap */
    }
  }
  if (!target) throw new Error('chrome target tidak ditemukan');
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));
  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg.result ?? msg.error);
      pending.delete(msg.id);
    }
  });
}

function send(method, params = {}) {
  return new Promise((resolve) => {
    const id = ++msgId;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
}

async function evaluate(expression) {
  const r = await send('Runtime.evaluate', {
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  return r?.result?.value;
}

/** Semua node semantics yang terlihat: label, peran, dan titik tengahnya. */
async function nodes() {
  return (
    (await evaluate(`(() => {
      const out = [];
      for (const el of document.querySelectorAll('[aria-label], [role]')) {
        const r = el.getBoundingClientRect();
        if (r.width === 0 || r.height === 0) continue;
        out.push({
          label: el.getAttribute('aria-label') || '',
          role: el.getAttribute('role') || '',
          text: (el.textContent || '').slice(0, 300),
          x: Math.round(r.x + r.width / 2),
          y: Math.round(r.y + r.height / 2),
        });
      }
      return out;
    })()`)) ?? []
  );
}

/**
 * Kolom input yang benar-benar ada di DOM.
 *
 * Flutter web menaruh `<input>` sungguhan untuk setiap kolom teks, jadi
 * mengisinya lewat `Input.insertText` setelah fokus adalah cara yang sama
 * dengan mengetik oleh pengguna — bukan memalsukan state widget.
 */
async function textInputs() {
  return (
    (await evaluate(`(() => {
      return [...document.querySelectorAll('input, textarea')]
        .filter((el) => el.type !== 'hidden')
        .map((el) => {
          const r = el.getBoundingClientRect();
          return {
            type: el.type,
            x: Math.round(r.x + r.width / 2),
            y: Math.round(r.y + r.height / 2),
            w: Math.round(r.width),
            h: Math.round(r.height),
          };
        });
    })()`)) ?? []
  );
}

async function clickAt(x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(70);
  }
  await sleep(700);
}

/**
 * Klik tombol pertama yang teks/labelnya cocok.
 *
 * Selalu dibatasi ke `role=button`: node `group` memuat seluruh teks halaman,
 * jadi tanpa batas ini pencarian bisa "menemukan" kata di mana saja lalu
 * mengklik tengah area konten — bukan tombol yang dimaksud.
 */
async function clickText(needle, { role = 'button' } = {}) {
  const list = await nodes();
  const hit = list.find(
    (n) =>
      (role == null || n.role === role) &&
      ((n.label || '').includes(needle) || (n.text || '').includes(needle)),
  );
  if (!hit) return false;
  await clickAt(hit.x, hit.y);
  return true;
}

/** Isi kolom input ke-[index] (0 = pertama) dengan teks. */
async function fillInput(index, text) {
  const inputs = await textInputs();
  const target = inputs[index];
  if (!target) return false;
  await clickAt(target.x, target.y);
  await send('Input.insertText', { text });
  await sleep(400);
  return true;
}

async function typeText(text) {
  await send('Input.insertText', { text });
  await sleep(400);
}

/** Apakah ada tombol dengan teks tertentu? */
async function hasButton(text) {
  const list = await nodes();
  return list.some(
    (n) => n.role === 'button' && ((n.label || '').includes(text) || (n.text || '').includes(text)),
  );
}

/** Seluruh teks yang tampil di halaman (untuk memeriksa isi daftar). */
async function pageText() {
  const list = await nodes();
  return list.map((n) => `${n.label}\n${n.text}`).join('\n');
}

async function setOffline(offline) {
  await send('Network.emulateNetworkConditions', {
    offline,
    latency: 0,
    downloadThroughput: offline ? 0 : -1,
    uploadThroughput: offline ? 0 : -1,
  });
  await sleep(400);
}

async function main() {
  await connect();
  await send('Page.enable');
  await send('Runtime.enable');
  await send('Network.enable');
  await send('Emulation.setDeviceMetricsOverride', {
    width: 1440,
    height: 900,
    deviceScaleFactor: 1,
    mobile: false,
  });

  await send('Page.navigate', { url: base });
  await sleep(9000);
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
  await sleep(1500);

  // ---------- 1. login ----------
  await clickText('Masuk');
  await sleep(2500);
  // Dua kolom: username lalu password. Keduanya <input> sungguhan.
  const okUser = await fillInput(0, adminUser);
  const okPass = await fillInput(1, adminPass);
  if (okUser && okPass) {
    await clickText('Masuk', { role: 'button' });
    await sleep(4000);
  }
  const afterLogin = await pageText();
  check(
    'login sebagai admin',
    afterLogin.includes('Buat turnamen') && !afterLogin.includes('Masuk ke klub'),
    afterLogin.slice(0, 70).replace(/\n/g, ' '),
  );

  // ---------- 2. buka halaman Anggota ----------
  await clickText('Lainnya');
  await sleep(2000);
  await clickText('Anggota');
  await sleep(2500);
  const memberPage = await pageText();
  check(
    'halaman Anggota terbuka',
    memberPage.includes('anggota aktif') || memberPage.includes('Tambah anggota'),
    memberPage.slice(0, 70).replace(/\n/g, ' '),
  );

  // ---------- 3. tambah anggota ONLINE ----------
  const onlineName = `${tag}_online`;
  const addedOnline = await addMember(onlineName);
  check('tambah anggota saat online', addedOnline);
  await sleep(1200);
  check(
    'anggota online muncul di daftar',
    (await pageText()).includes(onlineName),
  );

  // ---------- 4. matikan jaringan, tambah anggota ----------
  await setOffline(true);
  const offlineName = `${tag}_offline`;
  const addedOffline = await addMember(offlineName);
  check('tambah anggota saat offline tidak gagal', addedOffline);
  await sleep(1500);

  // Diagnostik: isi antrean & cache yang benar-benar tersimpan di browser.
  const storage = await evaluate(`(() => {
    const outbox = localStorage.getItem('outbox:v1');
    let items = 0;
    if (outbox) { try { items = (JSON.parse(outbox).items || []).length; } catch {} }
    let cacheKeys = 0;
    for (let i = 0; i < localStorage.length; i++) {
      if ((localStorage.key(i) || '').startsWith('qcache:')) cacheKeys++;
    }
    return { items, cacheKeys, offline: window.navigator.onLine };
  })()`);
  console.log(`  [diagnostik] antrean=${storage?.items} cache=${storage?.cacheKeys} online=${storage?.offline}`);

  const offlinePage = await pageText();
  check('anggota offline langsung terlihat', offlinePage.includes(offlineName));
  // Simpan bukti visual supaya kalau gagal, penyebabnya bisa dilihat.
  if (!offlinePage.includes(offlineName)) {
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    if (shot?.data) {
      const { writeFileSync } = await import('node:fs');
      writeFileSync('.shots/offline-fail.png', Buffer.from(shot.data, 'base64'));
      console.log('  [diagnostik] screenshot: .shots/offline-fail.png');
    }
  }
  check(
    'antrean offline terisi',
    (storage?.items ?? 0) > 0,
    `items=${storage?.items}`,
  );
  // Indikator offline: tombol "Sinkron" hanya muncul saat ada perubahan
  // menunggu. Teks kalimatnya sendiri tidak diekspos ke accessibility tree
  // Flutter, jadi keberadaan tombol inilah bukti yang bisa diperiksa.
  check(
    'banner menampilkan perubahan menunggu',
    (await hasButton('Sinkron')),
    offlinePage.slice(0, 80).replace(/\n/g, ' '),
  );

  // ---------- 5. tutup app (muat ulang), lalu buka lagi ----------
  // Yang diuji: antrean tersimpan di localStorage, jadi tidak hilang saat app
  // ditutup — dan saat app dibuka lagi (jaringan tersedia) sinkron berjalan
  // otomatis tanpa perlu menekan tombol apa pun.
  //
  // Catatan: muat ulang TIDAK dilakukan saat emulasi offline menyala, karena
  // emulasi CDP memblokir request dokumen sebelum service worker sempat
  // mencegat — itu keterbatasan alat uji, bukan bug aplikasi. Kemampuan
  // membuka app tanpa jaringan diuji terpisah oleh scripts/sw-offline-test.mjs
  // yang benar-benar mematikan server.
  const outboxBeforeReload = await evaluate(`(() => {
    const raw = localStorage.getItem('outbox:v1');
    if (!raw) return 0;
    try { return (JSON.parse(raw).items || []).length; } catch { return 0; }
  })()`);
  check('antrean tersimpan di localStorage', (outboxBeforeReload ?? 0) > 0, `items=${outboxBeforeReload}`);

  await setOffline(false);
  await sleep(800);
  await send('Page.reload');
  await sleep(10000);
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
  await sleep(2500);

  // Sinkron otomatis saat app dibuka: tunggu sampai antrean habis.
  let autoSynced = false;
  for (let i = 0; i < 12; i++) {
    const left = await evaluate(`(() => {
      const raw = localStorage.getItem('outbox:v1');
      if (!raw) return 0;
      try { return (JSON.parse(raw).items || []).length; } catch { return 0; }
    })()`);
    if ((left ?? 0) === 0) {
      autoSynced = true;
      break;
    }
    await sleep(2000);
  }
  check('antrean terkirim otomatis saat app dibuka lagi', autoSynced);

  const remote = await fetch(`${base}/api/sql`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      sql: 'SELECT name FROM members WHERE name LIKE @p ORDER BY name',
      params: { p: `${tag}%` },
    }),
  }).then((r) => r.json());

  const names = (remote.rows ?? []).map((r) => r.name);
  check('anggota offline terkirim ke database', names.includes(offlineName), JSON.stringify(names));
  check('anggota online tetap ada', names.includes(onlineName));

  // ---------- 7. bersihkan ----------
  // Pembersihan butuh token: hapus anggota hanya boleh oleh admin, dan
  // permintaan dari Node ini bukan sesi browser.
  const auth = await fetch(`${base}/api/auth`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'login', username: adminUser, password: adminPass }),
  }).then((r) => r.json());

  const del = await fetch(`${base}/api/sql`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(auth.token ? { authorization: `Bearer ${auth.token}` } : {}),
    },
    body: JSON.stringify({
      sql: 'DELETE FROM members WHERE name LIKE @p',
      params: { p: `${tag}%` },
    }),
  }).then((r) => r.json());
  check('data uji dibersihkan', !del.error, JSON.stringify(del));

  const bad = results.filter((x) => !x.ok).length;
  console.log(`\nTarget: ${base}`);
  console.log(`${results.length - bad}/${results.length} lulus.`);
  process.exit(bad ? 1 : 0);
}

/** Buka form tambah anggota dan isi namanya. */
async function addMember(name) {
  const before = await nodes();
  // Tombol "+" (tambah anggota) adalah ikon tanpa teks; cari tombol kecil di
  // kanan atas area konten.
  const addBtn = before.find((n) => n.role === 'button' && n.y < 120 && n.x > 1200);
  if (addBtn) {
    await clickAt(addBtn.x, addBtn.y);
  } else if (!(await clickText('Tambah anggota'))) {
    return false;
  }
  await sleep(2200);

  // Form anggota: kolom pertama = nama.
  if (!(await fillInput(0, name))) return false;
  if (!(await clickText('Simpan', { role: 'button' }))) return false;
  await sleep(2600);
  return true;
}

try {
  await main();
} catch (e) {
  console.error('GAGAL:', e.message);
  process.exit(1);
} finally {
  chrome.kill();
}
