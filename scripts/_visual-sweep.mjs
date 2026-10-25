// Sapuan visual: buka SETIAP tab & halaman di produksi, potret, dan periksa
// hal yang hanya terlihat di layar: error konsol, overflow horizontal, dan
// teks yang terpotong. Berbeda dari uji fungsi — di sini yang dinilai
// tampilannya.
//
//   node scripts/_visual-sweep.mjs
//   BASE=https://airevo-digital.my.id/minisoccer/ node scripts/_visual-sweep.mjs
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import { writeFileSync, mkdirSync } from 'node:fs';

import { adminCredentials } from './_admin-auth.mjs';

// Alamat aplikasi HARUS berakhir dengan garis miring: `<base href>` build
// menunjuk ke `/minisoccer/`, jadi tanpa garis miring aset relatif jatuh ke
// akar domain. URL tanpa garis miring diuji terpisah di bawah.
const base = (process.env.BASE || 'https://airevo-digital.my.id/minisoccer/').replace(/\/$/, '') + '/';
const apiBase = (process.env.API_BASE || base).replace(/\/$/, '');
const OUT = process.env.OUT || 'design/sweep';
mkdirSync(OUT, { recursive: true });

const viewports = [
  { name: 'hp-kecil', width: 320, height: 640, mobile: true },
  { name: 'hp', width: 390, height: 844, mobile: true },
  { name: 'desktop', width: 1440, height: 900, mobile: false },
];

const port = 9100 + Math.floor(Math.random() * 80);
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', `--remote-debugging-port=${port}`, '--no-sandbox', '--disable-gpu',
  `--user-data-dir=${process.env.TEMP}/chrome-sweep-${port}-${Date.now()}`, 'about:blank',
]);

let ws; let msgId = 0; const pending = new Map();
const consoleErrors = [];
/// Permintaan yang gagal (4xx/5xx), lengkap dengan URL-nya. Tanpa URL, pesan
/// "Failed to load resource" tidak bisa ditindaklanjuti.
const failedRequests = [];
const send = (m, p = {}) => new Promise((r) => { const id = ++msgId; pending.set(id, r); ws.send(JSON.stringify({ id, method: m, params: p })); });
const evaluate = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }))?.result?.value;

async function clickAt(x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(70);
  }
  await sleep(900);
}
async function nodes() {
  return (await evaluate(`(() => { const out = [];
    for (const el of document.querySelectorAll('[aria-label], [role]')) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      out.push({ label: el.getAttribute('aria-label') || '', role: el.getAttribute('role') || '',
        text: (el.textContent || '').slice(0, 200), x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) });
    } return out; })()`)) ?? [];
}
const textOf = (n) => (n.label || n.text || '').trim();
/// Ketuk elemen berteks [needle]. `last: true` memilih yang paling bawah —
/// dipakai untuk tombol kirim di form, karena bilah "Masuk" di atas layar
/// memakai teks yang sama dan ketukan pertama akan menutup form.
async function tap(needle, { role = null, last = false } = {}) {
  const list = (await nodes()).filter((n) => role == null || n.role === role);
  let hits = list.filter((n) => textOf(n) === needle);
  if (!hits.length) hits = list.filter((n) => textOf(n).startsWith(needle));
  if (!hits.length) hits = list.filter((n) => textOf(n).includes(needle));
  if (!hits.length) return false;
  const hit = last ? hits.reduce((a, b) => (a.y >= b.y ? a : b)) : hits[0];
  await clickAt(hit.x, hit.y);
  return true;
}
async function screenText() {
  const ax = await send('Accessibility.getFullAXTree');
  return (ax?.nodes ?? []).flatMap((n) => [n.name?.value, n.value?.value])
    .filter((v) => typeof v === 'string' && v.trim()).join('\n');
}

/// Overflow horizontal yang NYATA: halaman bisa digeser ke samping.
///
/// Bukan sekadar "ada elemen yang lebih lebar dari layar": Flutter menaruh
/// elemen pengukur teks tersembunyi selebar ribuan piksel, dan daftar
/// horizontal (chip periode) memang menyimpan isinya di luar layar. Keduanya
/// bukan cacat. Yang benar-benar mengganggu pengguna adalah halaman yang bisa
/// digeser menyamping, dan itu diukur dari dokumen.
async function overflow() {
  return await evaluate(`(() => {
    const w = window.innerWidth;
    const scroll = document.documentElement.scrollWidth;
    // Teks yang keluar dari kotaknya sendiri (terpotong tanpa elipsis) —
    // dicek hanya pada elemen yang benar-benar terlihat.
    const clipped = [];
    for (const el of document.querySelectorAll('flt-semantics, [role="button"], [role="tab"]')) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) continue;
      if (r.left < -2 || r.right > w + 2) continue; // di luar layar: bagian dari scroller
      if (el.scrollWidth > el.clientWidth + 2 && el.clientWidth > 0) {
        const t = (el.textContent || '').trim().slice(0, 30);
        if (t) clipped.push(t);
      }
    }
    return { w, scroll, pageOverflow: Math.max(0, scroll - w), clipped: clipped.slice(0, 3) };
  })()`);
}

/// Tap target terlalu kecil: tombol yang sulit dikenai jari.
async function smallTargets() {
  return await evaluate(`(() => {
    const bad = [];
    for (const el of document.querySelectorAll('[role="button"], [role="tab"]')) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 || r.height === 0) continue;
      if (r.top < 0 || r.bottom > window.innerHeight) continue;
      if (r.width < 40 || r.height < 40) {
        const t = (el.textContent || el.getAttribute('aria-label') || '').trim().slice(0, 24);
        if (t) bad.push({ t, w: Math.round(r.width), h: Math.round(r.height) });
      }
    }
    return bad.slice(0, 4);
  })()`);
}

const results = [];
function record(name, ok, detail = '') {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
}

async function shot(view, page) {
  const r = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(`${OUT}/${view}--${page}.png`, Buffer.from(r.data, 'base64'));
}

async function main() {
  // Login admin sekali (lewat API) supaya semua tombol tulis terlihat.
  // Kredensial dari env/.env — tidak ada default (repo ini publik).
  const { user: adminUser, pass: adminPass } = adminCredentials();
  const auth = await fetch(`${apiBase}/api/auth`, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'login', username: adminUser, password: adminPass }) }).then((r) => r.json());
  record('login admin (API)', Boolean(auth.token), auth.error ?? '');

  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(300);
    try { const l = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); target = l.find((t) => t.type === 'page'); } catch {}
  }
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));
  ws.addEventListener('message', (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result ?? m.error); pending.delete(m.id); return; }
    if (m.method === 'Runtime.exceptionThrown') {
      const d = m.params.exceptionDetails;
      consoleErrors.push(d?.exception?.description ?? d?.text ?? 'exception');
    }
    if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') {
      consoleErrors.push(m.params.entry.text ?? 'log error');
    }
    if (m.method === 'Network.responseReceived' && m.params.response.status >= 400) {
      failedRequests.push(`${m.params.response.status} ${m.params.response.url}`);
    }
  });
  await send('Page.enable'); await send('Runtime.enable'); await send('Log.enable');
  await send('Network.enable'); await send('Accessibility.enable');

  // Alamat tanpa garis miring di akhir: orang mengetiknya seperti itu, dan
  // sebelumnya hasilnya layar kosong karena aset relatif jatuh ke akar domain.
  {
    const noSlash = base.replace(/\/$/, '');
    await send('Page.navigate', { url: noSlash });
    await sleep(11000);
    const booted = await evaluate(`!!document.querySelector('canvas, flt-glass-pane, flutter-view')`);
    record(`alamat tanpa "/" di akhir tetap membuka aplikasi (${noSlash})`, Boolean(booted));
  }

  for (const vp of viewports) {
    await send('Emulation.setDeviceMetricsOverride', {
      width: vp.width, height: vp.height, deviceScaleFactor: 1, mobile: vp.mobile,
    });
    await send('Page.navigate', { url: base });
    await sleep(9000);
    // Pohon aksesibilitas Flutter tidak langsung terisi: pada pemuatan pertama
    // placeholder-nya belum ada, dan satu ketukan saja sering tidak cukup.
    // Tanpa pengulangan, seluruh sapuan melaporkan "tidak ada apa-apa" padahal
    // aplikasinya normal.
    let ready = false;
    for (let i = 0; i < 12; i++) {
      await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
      await sleep(1200);
      if ((await nodes()).length > 0) { ready = true; break; }
    }
    if (!ready) {
      const diag = await evaluate(`({ url: location.href, ready: document.readyState,
        canvas: !!document.querySelector('flt-glass-pane, flutter-view, canvas'),
        title: document.title })`).catch(() => null);
      record(`[${vp.name}] aplikasi ter-render`, false, JSON.stringify(diag));
    } else {
      record(`[${vp.name}] aplikasi ter-render`, true);
    }

    // Masuk supaya tombol tulis ikut dinilai. Tunggu form-nya benar-benar ada:
    // pada 320px layar masuk butuh waktu lebih lama untuk ter-render.
    await tap('Masuk');
    let inputs = [];
    for (let i = 0; i < 15; i++) {
      inputs = (await evaluate(`[...document.querySelectorAll('input')].map(el => { const r = el.getBoundingClientRect(); return { x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2) }; })`)) ?? [];
      if (inputs.length >= 2) break;
      await sleep(800);
    }
    if (inputs.length >= 2) {
      await clickAt(inputs[0].x, inputs[0].y); await send('Input.insertText', { text: 'admin' });
      await clickAt(inputs[1].x, inputs[1].y); await send('Input.insertText', { text: adminPass });
      // Tombol kirim ada di bawah form; bilah "Masuk" di atas memakai teks sama.
      await tap('Masuk', { role: 'button', last: true });
      await sleep(5000);
    }
    const loggedIn = (await nodes()).some((n) => textOf(n) === 'Lainnya');
    record(`[${vp.name}] masuk sebagai admin`, loggedIn);

    // Ukuran tap target diukur sekali per viewport, di Beranda.
    const small = await smallTargets();
    record(`[${vp.name}] tap target >= 40px di Beranda`, small.length === 0,
      small.length === 0 ? '' : JSON.stringify(small));

    const tabs = ['Beranda', 'Tanding', 'Tim', 'Iuran', 'Lainnya'];
    for (const tab of tabs) {
      const opened = await tap(tab);
      await sleep(2600);
      const ov = await overflow();
      await shot(vp.name, `tab-${tab.toLowerCase()}`);
      record(`[${vp.name}] tab ${tab}`, opened && ov.pageOverflow === 0,
        ov.pageOverflow === 0 ? '' : `halaman bisa digeser ${ov.pageOverflow}px`);
    }

    // Halaman turunan.
    const pages = ['Anggota', 'Sewa lapangan', 'Kas klub', 'Turnamen internal',
      'Statistik', 'Pengumuman', 'Pengguna', 'Pengaturan'];
    for (const page of pages) {
      await tap('Lainnya');
      await sleep(1400);
      const opened = await tap(page);
      await sleep(2400);
      const ov = await overflow();
      await shot(vp.name, `page-${page.toLowerCase().replace(/\s+/g, '-')}`);
      record(`[${vp.name}] halaman ${page}`, opened && ov.pageOverflow === 0,
        ov.pageOverflow === 0 ? '' : `halaman bisa digeser ${ov.pageOverflow}px`);
      await tap('Kembali', { role: 'button' });
      await sleep(1200);
    }
  }

  const real = consoleErrors.filter((e) => !/favicon|manifest|DevTools|third-party cookie|base-uri/i.test(e));
  record('tidak ada error konsol', real.length === 0, real.slice(0, 2).join(' | '));
  const badReq = [...new Set(failedRequests)]
    .filter((u) => !/favicon|manifest\.json/i.test(u));
  record('tidak ada permintaan yang gagal', badReq.length === 0, badReq.slice(0, 4).join(' | '));

  const bad = results.filter((r) => !r.ok).length;
  writeFileSync(`${OUT}/report.json`, JSON.stringify({ base, results }, null, 2));
  console.log(`\n${results.length - bad}/${results.length} lulus · ${OUT}`);
  process.exit(bad ? 1 : 0);
}

try { await main(); } catch (e) { console.error('GAGAL:', e.message); process.exit(1); } finally { chrome.kill(); }
