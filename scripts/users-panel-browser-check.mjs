// Verifikasi UI panel "Akun & akses" dengan akun percobaan.
//
// Yang dibuktikan (bukan diklaim):
//   1. Admin melihat ID akun di daftar.
//   2. Panel akun memuat tautan anggota, status "bisa masuk", dan tombol
//      "Setel password baru".
//   3. Setelah password disetel, password barunya TAMPIL di layar dan
//      benar-benar berlaku untuk masuk.
//
// Akun yang dipakai adalah akun sementara yang dibuat lewat API dan dihapus
// lagi di akhir, jadi tidak ada akun nyata yang passwordnya berubah.
//
//   node scripts/users-panel-browser-check.mjs
//   BASE=http://127.0.0.1:8099/minisoccer/ node scripts/users-panel-browser-check.mjs
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';
import { writeFileSync, mkdirSync } from 'node:fs';

import { adminCredentials } from './_admin-auth.mjs';

const base = (process.env.BASE || 'https://airevo-digital.my.id/minisoccer/').replace(/\/$/, '') + '/';
const apiBase = (process.env.API_BASE || base).replace(/\/$/, '');
const OUT = process.env.OUT || 'design/sweep-local';
mkdirSync(OUT, { recursive: true });

const port = 9600 + Math.floor(Math.random() * 100);
const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', `--remote-debugging-port=${port}`, '--no-sandbox', '--disable-gpu',
  `--user-data-dir=${process.env.TEMP}/chrome-users-${port}-${Date.now()}`, 'about:blank',
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

async function clickAt(x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(70);
  }
  await sleep(900);
}

async function tap(needle, { role = null, last = false, exact = false } = {}) {
  const list = (await nodes()).filter((n) => role == null || n.role === role);
  // Elemen grup membawa SELURUH teks halaman, jadi `includes` selalu
  // menemukannya lebih dulu dan ketukan mendarat di tempat yang salah
  // (halaman Statistik terbuka saat yang diminta "Akun & akses"). Buang
  // node yang teksnya jauh lebih panjang dari yang dicari, lalu utamakan
  // tombol dan teks terpendek.
  const hits = (exact
    ? list.filter((n) => textOf(n) === needle)
    : list.filter((n) => textOf(n).includes(needle)))
    .filter((n) => exact || textOf(n).length <= needle.length + 60);
  if (!hits.length) return false;
  const score = (n) => (n.role === 'button' || n.role === 'tab' ? 0 : 1) * 1000 + textOf(n).length;
  hits.sort((a, b) => score(a) - score(b));
  const hit = last ? hits.reduce((a, b) => (a.y >= b.y ? a : b)) : hits[0];
  await clickAt(hit.x, hit.y);
  return true;
}

/// Gulir daftar ke bawah.
///
/// Titik gulir di TENGAH jendela, bukan x=195: di layar lebar isi halaman
/// dipusatkan (maks ±720px), jadi roda di x=195 jatuh di luar kolom dan tidak
/// menggerakkan apa pun — baris yang dicari tidak pernah masuk layar.
async function scrollDown(times = 1) {
  const w = (await evaluate('window.innerWidth')) || 390;
  const h = (await evaluate('window.innerHeight')) || 844;
  for (let i = 0; i < times; i++) {
    await send('Input.dispatchMouseEvent', {
      type: 'mouseWheel', x: Math.round(w / 2), y: Math.round(h / 2),
      deltaX: 0, deltaY: 280, button: 'none',
    });
    await sleep(500);
  }
}

/// Ketuk [needle], gulir dulu kalau elemennya di luar layar.
///
/// `tap()` mencocokkan pohon aksesibilitas, yang juga memuat elemen di luar
/// viewport. Mengklik koordinat di luar layar tidak melakukan apa pun —
/// itulah yang dulu membuat panel akun "tidak terbuka" padahal barisnya
/// ditemukan: daftar bertambah panjang dan baris yang dicari berada di bawah
/// lipatan.
async function tapScroll(needle, opts = {}) {
  for (let i = 0; i < 10; i++) {
    const list = (await nodes()).filter((n) => opts.role == null || n.role === opts.role);
    const hits = list
      .filter((n) => textOf(n).includes(needle))
      .filter((n) => textOf(n).length <= needle.length + 60);
    if (hits.length) {
      const score = (n) => (n.role === 'button' || n.role === 'tab' ? 0 : 1000) + textOf(n).length;
      hits.sort((a, b) => score(a) - score(b));
      const hit = opts.last ? hits.reduce((a, b) => (a.y >= b.y ? a : b)) : hits[0];
      const h = await evaluate('window.innerHeight');
      // Batasnya 0..h, bukan 60..h-60: tombol "Masuk" di bilah status memang
      // duduk di y≈16, dan menganggapnya "di luar layar" membuat pencarian
      // menggulir ke atas tanpa pernah menekannya.
      if (hit.y >= 4 && hit.y <= h - 4) {
        await clickAt(hit.x, hit.y);
        return true;
      }
      // Di luar layar: geser ke arah yang benar.
      const dir = hit.y < 4 ? -1 : 1;
      const w = (await evaluate('window.innerWidth')) || 390;
      await send('Input.dispatchMouseEvent', {
        type: 'mouseWheel', x: Math.round(w / 2), y: Math.round(h / 2),
        deltaX: 0, deltaY: dir * 300, button: 'none',
      });
      await sleep(600);
      continue;
    }
    await scrollDown();
  }
  return false;
}


/// Isi satu kolom Flutter di dalam kanvas, dan pastikan nilainya benar-benar
/// sampai ke pengendali teks.
///
/// `Input.insertText` saja tidak cukup: pada sebagian build teks tidak pernah
/// masuk ke `TextEditingController`, form terlihat terisi, lalu server
/// menjawab "Username atau password salah". Jadi nilainya diperiksa dan
/// diketik ulang dengan event papan ketik bila perlu.
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
    const ok2 = await evaluate(`(() => {
      const el = [...document.querySelectorAll('input')].find((e) => {
        const r = e.getBoundingClientRect();
        return Math.abs(r.x + r.width / 2 - ${point.x}) < 40 && Math.abs(r.y + r.height / 2 - ${point.y}) < 40;
      });
      return el ? el.value === ${JSON.stringify(text)} : false;
    })()`);
    if (ok2) return true;
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
  writeFileSync(`${OUT}/users-panel--${page}.png`, Buffer.from(r.data, 'base64'));
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
const tempName = `zz-ui-${Date.now().toString(36)}`;
const created = await api({ action: 'create', username: tempName, role: 'member', password: 'awal123456' }, adminToken);
check('akun percobaan dibuat', created.code === 200, `id ${created.json.id}`);

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
// Desktop 1440×900: panel admin memang dipakai di layar lebar, dan pohon
// aksesibilitas Flutter di Chrome headless paling stabil pada ukuran ini.
// Tampilan HP dari widget yang sama diuji `scripts/_visual-sweep.mjs`.
await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 900, deviceScaleFactor: 1, mobile: false });
// Muat dua kali seperti pengguna sungguhan yang membuka tautan tanpa garis
// miring lalu diarahkan ulang: pemuatan dingin pertama sering belum
// menggambar kanvas di Chrome headless.
await send('Page.navigate', { url: base.replace(/\/$/, '') });
await sleep(6000);
await send('Page.navigate', { url: base });
await sleep(9000);
for (let i = 0; i < 12; i++) {
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
  await sleep(900);
  if ((await nodes()).length > 0) break;
}

// Masuk sebagai admin.
await tapScroll('Masuk');
let inputs = [];
for (let i = 0; i < 12; i++) {
  inputs = (await evaluate(`[...document.querySelectorAll('input')].map(el => { const r = el.getBoundingClientRect(); return { x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2) }; }).filter(p => p.y > 0 && p.y < window.innerHeight)`)) ?? [];
  if (inputs.length >= 2) break;
  await scrollDown();
  await sleep(800);
}
if (inputs.length >= 2) {
  await fillInput(inputs[0], adminUser);
  await fillInput(inputs[1], adminPass);
  await tap('Masuk', { role: 'button', last: true });
  await sleep(5000);
}
{
  let after = await nodes();
  for (let i = 0; i < 15 && !after.some((n) => textOf(n) === 'Lainnya'); i++) {
    await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
    await sleep(1200);
    after = await nodes();
  }
  check('masuk sebagai admin', after.some((n) => textOf(n) === 'Lainnya'),
    after.length === 0 ? 'pohon aksesibilitas kosong' : after.map((n) => textOf(n)).slice(0, 6).join(' / '));
}

// Buka Lainnya → Akun & akses.
await tap('Lainnya');
await sleep(1500);
check('baris "Akun & akses" ada di menu', await tapScroll('Akun & akses'));
await sleep(2500);
await shot('daftar');

const listText = await screenText();
check('daftar menampilkan ID akun', /#\d+/.test(listText), (listText.match(/#\d+/) ?? [''])[0]);
check('daftar menyebut batas password', /bcrypt|tidak bisa\s+dibaca/i.test(listText));

// Buka akun percobaan.
check('baris akun percobaan bisa dibuka', await tapScroll(tempName));
check('panel akun benar-benar terbuka', (await screenText()).includes('ID #'), '');
await sleep(2000);
await shot('panel');

const panelText = await screenText();
if (process.env.DEBUG) console.log('--- panel ---\n' + panelText.slice(0, 1200));
check('panel menyebut ID akun', new RegExp(`#${created.json.id}\\b`).test(panelText));
check('panel punya pilihan anggota tertaut', /Tidak tertaut|Anggota tertaut/.test(panelText));
check('panel punya tombol setel password', /Setel password baru/i.test(panelText));
check('panel punya status masuk', /Bisa masuk/i.test(panelText));

// Setel password baru lewat UI.
check('tombol "Setel password baru" bisa ditekan', await tap('Setel password baru'));
await sleep(1200);
check('konfirmasi muncul', await tap('Setel', { exact: true }));
await sleep(3000);
await shot('password-baru');

// Password yang tampil dicari sebagai KATA utuh 12 karakter dari alfabet
// yang dipakai `suggestPassword`. Regex bebas seperti /[a-z2-9]{12}/ juga
// cocok dengan kata biasa ("pertandingan"), jadi kandidat diuji satu per
// satu ke server: yang benar-benar berlaku itulah password barunya.
// Password baru dibuktikan lewat tombol "Salin": Flutter menaruh
// "username / password" ke clipboard, jadi isinya bisa dibaca kembali dan
// diuji ke server. Membaca teks di layar tidak bisa diandalkan —
// `SelectableText` tidak mengekspos isinya ke pohon aksesibilitas.
await send('Browser.grantPermissions', {
  origin: new URL(base).origin,
  permissions: ['clipboardReadWrite', 'clipboardSanitizedWrite'],
});
check('tombol salin ada', await tap('Salin'));
await sleep(1200);
const clip = await evaluate(`navigator.clipboard.readText().catch((e) => 'ERR ' + e.message)`);
const shown = String(clip || '').split('/').pop().trim();
const candidates = /^[a-z2-9]{12}$/.test(shown) ? [shown] : [];
let working = null;
for (const c of candidates) {
  const login = await api({ action: 'login', username: tempName, password: c });
  if (login.code === 200) { working = c; break; }
}
check('password baru tampil (tersalin) & benar-benar berlaku', Boolean(working),
  working ? working : `clipboard: ${JSON.stringify(String(clip).slice(0, 60))}`);

// Bersihkan: akun percobaan dihapus lagi.
const del = await api({ action: 'delete', id: created.json.id }, adminToken);
check('akun percobaan dihapus', del.code === 200, JSON.stringify(del.json));

const bad = results.filter((r) => !r.ok).length;
console.log(`\n${results.length - bad}/${results.length} lulus · ${OUT}`);
chrome.kill();
process.exit(bad ? 1 : 0);
