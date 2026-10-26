// Bukti bahwa uang klub tidak terbaca orang luar.
//
// Repo ini publik dan aplikasinya bisa dibuka tanpa akun. Yang diuji di sini
// adalah batasnya:
//   1. Server: tamu (tanpa token) ditolak 403 untuk `payments`,
//      `transactions`, `bookings`, `booking_attendance`, dan `settings`;
//      data pertandingan tetap 200.
//   2. Layar: tamu yang membuka Iuran / Kas / Sewa lapangan / riwayat iuran
//      melihat penjelasan "Khusus anggota klub", bukan angka nol atau baris
//      "gagal dimuat".
//   3. Beranda tamu tidak menampilkan angka kas.
//   4. Setelah masuk sebagai anggota, halaman yang sama menampilkan data.
//
// Akun anggota dibuat lewat API lalu dihapus lagi di akhir.
//
//   node scripts/guest-lock-browser-check.mjs
//   BASE=http://127.0.0.1:8099/minisoccer/ node scripts/guest-lock-browser-check.mjs
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import { writeFileSync, mkdirSync } from 'node:fs';

import { adminCredentials } from './_admin-auth.mjs';

const base = (process.env.BASE || 'https://airevo-digital.my.id/minisoccer/').replace(/\/$/, '') + '/';
const apiBase = (process.env.API_BASE || base).replace(/\/$/, '');
const OUT = process.env.OUT || 'design/sweep-local';
mkdirSync(OUT, { recursive: true });

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

// ---------- 1. Server: siapa boleh membaca apa ----------
const sqlAs = async (sql, token) => {
  const r = await fetch(`${apiBase}/api/sql`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ sql, params: {} }),
  });
  return { code: r.status, json: await r.json().catch(() => ({})) };
};

const MONEY = [
  ['kas', 'SELECT * FROM transactions LIMIT 1'],
  ['iuran', 'SELECT * FROM payments LIMIT 1'],
  ['sewa lapangan', 'SELECT * FROM bookings LIMIT 1'],
  ['patungan', 'SELECT * FROM booking_attendance LIMIT 1'],
  ['settings', 'SELECT * FROM settings LIMIT 1'],
];
const MATCH_DATA = [
  ['anggota', 'SELECT id, name, position, jersey FROM members LIMIT 1'],
  ['tim', 'SELECT * FROM teams LIMIT 1'],
  ['turnamen', 'SELECT * FROM tournaments LIMIT 1'],
  ['laga', 'SELECT * FROM matches LIMIT 1'],
  ['pengumuman', 'SELECT * FROM announcements LIMIT 1'],
];

for (const [label, sql] of MONEY) {
  const r = await sqlAs(sql, null);
  check(`tamu ditolak membaca ${label}`, r.code === 403, `code ${r.code}`);
}
for (const [label, sql] of MATCH_DATA) {
  const r = await sqlAs(sql, null);
  check(`tamu masih bisa membaca ${label}`, r.code === 200, `code ${r.code}`);
}
{
  const r = await sqlAs('SELECT name, phone FROM members LIMIT 1', null);
  check('tamu tetap tidak bisa membaca nomor HP', r.code === 403, `code ${r.code}`);
}

// ---------- 2. Layar ----------
const { user: adminUser, pass: adminPass } = adminCredentials();
const api = async (body, token) => {
  const r = await fetch(`${apiBase}/api/auth`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });
  return { code: r.status, json: await r.json().catch(() => ({})) };
};
const adminToken = (await api({ action: 'login', username: adminUser, password: adminPass })).json.token;
const tempName = `zz-lock-${Date.now().toString(36).slice(-6)}`;
const tempPass = 'anggota123456';
const created = await api({ action: 'create', username: tempName, role: 'member', password: tempPass }, adminToken);

const port = 9850 + Math.floor(Math.random() * 60);
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', `--remote-debugging-port=${port}`, '--no-sandbox', '--disable-gpu',
  `--user-data-dir=${process.env.TEMP}/chrome-lock-${port}-${Date.now()}`, 'about:blank',
]);

let ws; let msgId = 0; const pending = new Map();
const send = (m, p = {}) => new Promise((r) => { const id = ++msgId; pending.set(id, r); ws.send(JSON.stringify({ id, method: m, params: p })); });
const evaluate = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }))?.result?.value;

async function nodes() {
  return (await evaluate(`(() => { const out = [];
    for (const el of document.querySelectorAll('[aria-label], [role]')) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      out.push({ label: el.getAttribute('aria-label') || '', role: el.getAttribute('role') || '',
        text: (el.textContent || '').slice(0, 300),
        x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) });
    } return out; })()`)) ?? [];
}
const textOf = (n) => (n.label || n.text || '').trim();

async function clickAt(x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(70);
  }
  await sleep(900);
}

async function tap(needle, { role = null, last = false } = {}) {
  const list = (await nodes()).filter((n) => role == null || n.role === role);
  const hits = list
    .filter((n) => textOf(n).includes(needle))
    .filter((n) => textOf(n).length <= needle.length + 60);
  if (!hits.length) return false;
  const score = (n) => (n.role === 'button' || n.role === 'tab' ? 0 : 1000) + textOf(n).length;
  hits.sort((a, b) => score(a) - score(b));
  const hit = last ? hits.reduce((a, b) => (a.y >= b.y ? a : b)) : hits[0];
  await clickAt(hit.x, hit.y);
  return true;
}

async function tapScroll(needle, opts = {}) {
  for (let i = 0; i < 8; i++) {
    const list = (await nodes()).filter((n) => opts.role == null || n.role === opts.role);
    const hits = list
      .filter((n) => textOf(n).includes(needle))
      .filter((n) => textOf(n).length <= needle.length + 60);
    if (hits.length) {
      const score = (n) => (n.role === 'button' || n.role === 'tab' ? 0 : 1000) + textOf(n).length;
      hits.sort((a, b) => score(a) - score(b));
      const hit = opts.last ? hits.reduce((a, b) => (a.y >= b.y ? a : b)) : hits[0];
      const h = await evaluate('window.innerHeight');
      if (hit.y >= 4 && hit.y <= h - 4) { await clickAt(hit.x, hit.y); return true; }
      const w = await evaluate('window.innerWidth');
      await send('Input.dispatchMouseEvent', {
        type: 'mouseWheel', x: Math.round(w / 2), y: Math.round(h / 2),
        deltaX: 0, deltaY: (hit.y < 4 ? -1 : 1) * 300, button: 'none',
      });
      await sleep(600);
      continue;
    }
    const w = await evaluate('window.innerWidth');
    const h = await evaluate('window.innerHeight');
    await send('Input.dispatchMouseEvent', {
      type: 'mouseWheel', x: Math.round(w / 2), y: Math.round(h / 2), deltaX: 0, deltaY: 280, button: 'none',
    });
    await sleep(500);
  }
  return false;
}

async function screenText() {
  const ax = await send('Accessibility.getFullAXTree');
  return (ax?.nodes ?? []).flatMap((n) => [n.name?.value, n.value?.value])
    .filter((v) => typeof v === 'string' && v.trim()).join('\n');
}

async function shot(page) {
  const r = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(`${OUT}/guest-lock--${page}.png`, Buffer.from(r.data, 'base64'));
}

let target = null;
for (let i = 0; i < 60 && !target; i++) {
  await sleep(300);
  try { const l = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); target = l.find((t) => t.type === 'page'); } catch {}
}
ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r, { once: true }));
ws.addEventListener('message', (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result ?? m.error); pending.delete(m.id); }
});
await send('Page.enable'); await send('Runtime.enable'); await send('Accessibility.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
await send('Page.navigate', { url: base });
await sleep(9000);
for (let i = 0; i < 12; i++) {
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
  await sleep(900);
  if ((await nodes()).length > 0) break;
}

const LOCK = 'Khusus anggota klub';

// Beranda tamu: tidak ada angka kas, ada ajakan masuk.
{
  const t = await screenText();
  check('beranda tamu tidak menampilkan angka kas', !/SALDO\s*\n\s*Rp/.test(t) && !t.includes('Kas bulan ini\nRp'),
    t.split('\n').filter((l) => /kas|saldo/i.test(l)).slice(0, 2).join(' | '));
  check('beranda tamu menawarkan masuk untuk kas', t.includes('Masuk untuk melihat') || t.includes('masuk untuk lihat'));
  await shot('beranda');
}

// Tab Iuran.
await tap('Iuran');
await sleep(2200);
{
  const t = await screenText();
  check('tab Iuran terkunci untuk tamu', t.includes(LOCK), t.split('\n').slice(0, 2).join(' | '));
  check('tab Iuran tidak menampilkan "gagal dimuat"', !/gagal dimuat|FormatException/i.test(t));
  await shot('iuran');
}

// Kas klub + Sewa lapangan lewat Lainnya.
for (const [label, file] of [['Kas klub', 'kas'], ['Sewa lapangan', 'sewa']]) {
  await tap('Lainnya');
  await sleep(1800);
  const opened = await tapScroll(label);
  await sleep(2200);
  const t = await screenText();
  check(`${label} terkunci untuk tamu`, opened && t.includes(LOCK), t.split('\n').slice(0, 2).join(' | '));
  await shot(file);
  await tap('Kembali', { role: 'button' });
  await sleep(1200);
}

// Setelah masuk sebagai anggota, halaman yang sama terbuka.
await tap('Lainnya');
await sleep(1600);
await tapScroll('Masuk');
await sleep(1500);
{
  const inputs = await evaluate(`[...document.querySelectorAll('input')].map(el => { const r = el.getBoundingClientRect(); return { x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2) }; }).filter(p => p.y > 0 && p.y < window.innerHeight)`);
  if (inputs.length >= 2) {
    for (const [i, text] of [[0, tempName], [1, tempPass]]) {
      await clickAt(inputs[i].x, inputs[i].y);
      await send('Input.insertText', { text });
      await sleep(250);
    }
    await tap('Masuk', { role: 'button', last: true });
    await sleep(6000);
  }
}
{
  let ok = false;
  for (let i = 0; i < 15 && !ok; i++) {
    await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
    await sleep(1200);
    ok = (await nodes()).some((n) => textOf(n) === 'Lainnya');
  }
  check('masuk sebagai anggota', ok);
}
await tap('Iuran');
await sleep(2600);
{
  const t = await screenText();
  check('setelah masuk, Iuran tidak lagi terkunci', !t.includes(LOCK), t.split('\n').slice(0, 2).join(' | '));
  await shot('iuran-setelah-masuk');
}

// Bersihkan akun percobaan.
const del = await api({ action: 'delete', id: created.json.id }, adminToken);
check('akun percobaan dihapus', del.code === 200, JSON.stringify(del.json));

const bad = results.filter((r) => !r.ok).length;
console.log(`\n${results.length - bad}/${results.length} lulus · ${OUT}`);
chrome.kill();
process.exit(bad ? 1 : 0);
