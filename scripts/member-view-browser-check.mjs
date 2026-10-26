// Bukti bahwa anggota biasa hanya melihat data klub.
//
// Yang diperiksa di Chrome sungguhan dengan akun anggota sementara:
//   1. Menu Lainnya tidak memuat "Akun & akses" (panel kredensial admin).
//   2. Pengaturan tidak memuat bagian teknis: sambungan data, tes koneksi,
//      data tanpa internet, tautan pendaftaran.
//   3. Tidak ada tombol tulis di tab mana pun (Buat/Tambah/Umumkan/Catat).
//   4. Beranda tidak menyuruh anggota melakukan tugas pengurus
//      ("Isi pemain ke tim" / "Susun turnamen").
//   5. Server tetap menolak: /api/auth action list → 403.
//
// Akun percobaan dibuat lewat API dan dihapus lagi di akhir.
//
//   node scripts/member-view-browser-check.mjs
//   BASE=http://127.0.0.1:8099/minisoccer/ node scripts/member-view-browser-check.mjs
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import { writeFileSync, mkdirSync } from 'node:fs';

import { adminCredentials } from './_admin-auth.mjs';

const base = (process.env.BASE || 'https://airevo-digital.my.id/minisoccer/').replace(/\/$/, '') + '/';
const apiBase = (process.env.API_BASE || base).replace(/\/$/, '');
const OUT = process.env.OUT || 'design/sweep-local';
mkdirSync(OUT, { recursive: true });

const port = 9700 + Math.floor(Math.random() * 90);
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', `--remote-debugging-port=${port}`, '--no-sandbox', '--disable-gpu',
  `--user-data-dir=${process.env.TEMP}/chrome-member-${port}-${Date.now()}`, 'about:blank',
]);

let ws; let msgId = 0; const pending = new Map();
const send = (m, p = {}) => new Promise((r) => { const id = ++msgId; pending.set(id, r); ws.send(JSON.stringify({ id, method: m, params: p })); });
const evaluate = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }))?.result?.value;

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

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

/// Seluruh teks halaman yang pernah terlihat sambil menggulir.
///
/// Daftar di halaman ini bisa lebih panjang dari layar; bagian bawah hanya
/// dibangun setelah digulir, jadi "tidak ada" tanpa menggulir tidak berarti
/// apa-apa.
async function fullText() {
  const seen = new Set();
  const collect = async () => {
    const ax = await send('Accessibility.getFullAXTree');
    for (const n of ax?.nodes ?? []) {
      for (const v of [n.name?.value, n.value?.value]) {
        if (typeof v === 'string' && v.trim()) seen.add(v.trim());
      }
    }
  };
  await collect();
  for (let i = 0; i < 8; i++) {
    await send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 195, y: 500, deltaX: 0, deltaY: 300, button: 'none' });
    await sleep(450);
    await collect();
  }
  return [...seen].join('\n');
}

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
  for (let i = 0; i < 6; i++) {
    if (await tap(needle, opts)) return true;
    await send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 195, y: 500, deltaX: 0, deltaY: 300, button: 'none' });
    await sleep(500);
  }
  return false;
}

async function fillInput(point, text) {
  for (let attempt = 0; attempt < 3; attempt++) {
    await clickAt(point.x, point.y);
    await send('Input.insertText', { text });
    await sleep(300);
    const ok = await evaluate(`(() => {
      const el = [...document.querySelectorAll('input')].find((e) => {
        const r = e.getBoundingClientRect();
        return Math.abs(r.x + r.width / 2 - ${point.x}) < 40 && Math.abs(r.y + r.height / 2 - ${point.y}) < 40;
      });
      return el ? el.value === ${JSON.stringify(text)} : false;
    })()`);
    if (ok) return true;
    for (const ch of text) {
      await send('Input.dispatchKeyEvent', { type: 'char', text: ch });
      await sleep(12);
    }
    await sleep(300);
  }
  return false;
}

async function shot(page) {
  const r = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(`${OUT}/member-view--${page}.png`, Buffer.from(r.data, 'base64'));
}

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
const tempName = `zz-mv-${Date.now().toString(36).slice(-6)}`;
const tempPass = 'anggota123456';
const created = await api({ action: 'create', username: tempName, role: 'member', password: tempPass }, adminToken);
check('akun anggota percobaan dibuat', created.code === 200, `id ${created.json.id}`);

// Tautkan ke anggota pertama supaya "Akun saya" ikut tampil (bagian yang
// memang milik anggota).
const sqlAs = async (sql) => {
  const r = await fetch(`${apiBase}/api/sql`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${adminToken}` },
    body: JSON.stringify({ sql, params: {} }),
  });
  return r.json();
};
const first = (await sqlAs('SELECT id, name FROM members ORDER BY id LIMIT 1')).rows?.[0];
if (first) {
  await api({ action: 'update', id: created.json.id, member_id: first.id }, adminToken);
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

// Masuk sebagai anggota.
await tapScroll('Masuk');
let inputs = [];
for (let i = 0; i < 12; i++) {
  inputs = (await evaluate(`[...document.querySelectorAll('input')].map(el => { const r = el.getBoundingClientRect(); return { x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2) }; }).filter(p => p.y > 0 && p.y < window.innerHeight)`)) ?? [];
  if (inputs.length >= 2) break;
  await send('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 195, y: 500, deltaX: 0, deltaY: 260, button: 'none' });
  await sleep(800);
}
if (inputs.length >= 2) {
  await fillInput(inputs[0], tempName);
  await fillInput(inputs[1], tempPass);
  await tap('Masuk', { role: 'button', last: true });
  await sleep(6000);
}
{
  let after = await nodes();
  for (let i = 0; i < 15 && !after.some((n) => textOf(n) === 'Lainnya'); i++) {
    await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
    await sleep(1200);
    after = await nodes();
  }
  check('masuk sebagai anggota', after.some((n) => textOf(n) === 'Lainnya'),
    after.length === 0 ? 'pohon aksesibilitas kosong' : after.map(textOf).slice(0, 5).join(' / '));
}

// ---------- 1. Beranda tidak menyuruh tugas pengurus ----------
const homeText = await fullText();
check('beranda anggota tidak menyuruh "Isi pemain ke tim"',
  !homeText.includes('Isi pemain ke tim'), homeText.split('\n').slice(0, 3).join(' | '));
check('beranda anggota tidak menyuruh "Susun turnamen"',
  !homeText.includes('Susun turnamen'));
await shot('beranda');

// ---------- 2. Menu Lainnya tanpa panel admin ----------
await tap('Lainnya');
await sleep(2000);
const moreText = await fullText();
check('menu Lainnya tanpa "Akun & akses"', !moreText.includes('Akun & akses'),
  moreText.split('\n').filter((l) => l.includes('Akun')).slice(0, 3).join(' | '));
check('menu Lainnya tetap memuat data klub',
  moreText.includes('Anggota') && moreText.includes('Kas klub') && moreText.includes('Turnamen internal'));
await shot('lainnya');

// ---------- 3. Pengaturan tanpa bagian teknis ----------
check('Pengaturan bisa dibuka', await tapScroll('Pengaturan'));
await sleep(2500);
const setText = await fullText();
for (const label of ['Sambungan data', 'Tes koneksi', 'Data tanpa internet',
  'Pendaftaran anggota', 'Tautan pendaftaran', 'Neon Postgres']) {
  check(`Pengaturan anggota tanpa "${label}"`, !setText.includes(label));
}
// Judul bagian ditulis kapital oleh `SectionTitle` ("AKUN"), jadi
// perbandingan tidak peduli huruf besar/kecil.
const setLower = setText.toLowerCase();
check('Pengaturan anggota tetap punya tema & akun',
  setLower.includes('tema') && setLower.includes('akun') && setLower.includes('keluar'),
  setText.split('\n').filter((l) => /tema|akun|keluar/i.test(l)).slice(0, 4).join(' | '));
await shot('pengaturan');

// ---------- 4. Tab tanpa tombol tulis ----------
const writeLabels = ['Buat turnamen', 'Tambah anggota', 'Buat tim', 'Umumkan',
  'Catat transaksi', 'Sewa lapangan', 'Jadwalkan laga', 'Catat', 'Simpan hasil'];
for (const tab of ['Beranda', 'Tanding', 'Tim', 'Iuran', 'Lainnya']) {
  await tap(tab);
  await sleep(2000);
  const t = await fullText();
  const leaked = writeLabels.filter((l) => t.includes(l));
  check(`tab ${tab} tanpa tombol tulis`, leaked.length === 0, leaked.join(', '));
}

// ---------- 5. Server tetap menolak ----------
const memberLogin = await api({ action: 'login', username: tempName, password: tempPass });
const denied = await api({ action: 'list' }, memberLogin.json.token);
check('anggota ditolak server saat minta daftar akun', denied.code === 403, `code ${denied.code}`);

// ---------- Bersihkan ----------
const del = await api({ action: 'delete', id: created.json.id }, adminToken);
check('akun percobaan dihapus', del.code === 200, JSON.stringify(del.json));

const bad = results.filter((r) => !r.ok).length;
console.log(`\n${results.length - bad}/${results.length} lulus · ${OUT}`);
chrome.kill();
process.exit(bad ? 1 : 0);
