// Uji fitur lintas halaman di produksi, dengan jaringan sungguhan.
//
// Fokus: memastikan setiap halaman utama terbuka tanpa error dan menampilkan
// datanya, plus satu tulis nyata di beberapa halaman. Ini menangkap regresi
// yang tidak terlihat oleh tes unit (mis. query gagal karena kolom berubah).
//
//   node scripts/features-browser-check.mjs
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const base = (process.env.BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPass = process.env.ADMIN_PASS || 'admin123';
const port = 9400 + Math.floor(Math.random() * 200);
const tag = `_ft_${Date.now().toString(36)}`;

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
  `--user-data-dir=${process.env.TEMP}/chrome-feat-${port}`,
  'about:blank',
]);

let ws;
let msgId = 0;
const pending = new Map();
const consoleErrors = [];

const send = (method, params = {}) =>
  new Promise((resolve) => {
    const id = ++msgId;
    pending.set(id, resolve);
    ws.send(JSON.stringify({ id, method, params }));
  });
const evaluate = async (expression) =>
  (await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }))
    ?.result?.value;

async function clickAt(x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(70);
  }
  await sleep(800);
}

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
          text: (el.textContent || '').slice(0, 400),
          x: Math.round(r.x + r.width / 2),
          y: Math.round(r.y + r.height / 2),
        });
      }
      return out;
    })()`)) ?? []
  );
}

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
          };
        });
    })()`)) ?? []
  );
}

async function fillInput(index, text) {
  const inputs = await textInputs();
  const t = inputs[index];
  if (!t) return false;
  await clickAt(t.x, t.y);
  await send('Input.insertText', { text });
  await sleep(350);
  return true;
}

async function pageText() {
  const list = await nodes();
  return list.map((n) => `${n.label}\n${n.text}`).join('\n');
}

/**
 * Buka form tambah di sebuah halaman.
 *
 * Halaman memakai dua bentuk: tombol ikon "+" di kanan atas (Anggota, Booking),
 * atau tombol berteks di header/empty state (Pengumuman: "Buat pengumuman").
 * Keduanya dicoba supaya tes tidak rapuh terhadap perbedaan ini.
 */
async function openAddForm(textFallback) {
  const icon = (await nodes()).find((n) => n.role === 'button' && n.y < 130 && n.x > 1200);
  if (icon) {
    await clickAt(icon.x, icon.y);
    return true;
  }
  return clickText(textFallback);
}

/**
 * Tekan tombol simpan pada dialog.
 *
 * Labelnya berbeda per form ("Simpan" untuk anggota/transaksi, "Kirim" untuk
 * pengumuman), jadi keduanya dicoba.
 */
async function saveDialog() {
  for (const label of ['Simpan', 'Kirim', 'Tambah', 'Catat']) {
    if (await clickText(label, { role: 'button' })) return label;
  }
  return null;
}

/** Tandai halaman error yang tidak boleh muncul. */
function looksBroken(text) {
  return /Gagal memuat|Query gagal dijalankan|Terjadi kesalahan|TypeError|Uncaught/.test(text);
}

async function main() {
  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(300);
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
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
      return;
    }
    if (msg.method === 'Runtime.consoleAPICalled' && msg.params.type === 'error') {
      consoleErrors.push(
        (msg.params.args ?? []).map((a) => a.value ?? a.description ?? '').join(' '),
      );
    }
    if (msg.method === 'Runtime.exceptionThrown') {
      consoleErrors.push(msg.params.exceptionDetails?.text ?? 'exception');
    }
  });

  await send('Page.enable');
  await send('Runtime.enable');
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

  // ---------- login ----------
  await clickText('Masuk');
  await sleep(2500);
  await fillInput(0, adminUser);
  await fillInput(1, adminPass);
  await clickText('Masuk', { role: 'button' });
  await sleep(4000);
  check('login admin', (await pageText()).includes('Buat turnamen'));

  // ---------- setiap tab utama ----------
  const tabs = [
    ['Beranda', ['ANGGOTA', 'MAIN']],
    ['Tanding', ['Jadwal']],
    ['Tim', ['Tim']],
    ['Iuran', ['Iuran']],
  ];
  for (const [tab, expects] of tabs) {
    await clickText(tab);
    await sleep(2600);
    const text = await pageText();
    check(`tab ${tab} terbuka tanpa error`, !looksBroken(text), text.slice(0, 60).replace(/\n/g, ' '));
    for (const e of expects) {
      check(`  ${tab}: menampilkan "${e}"`, text.includes(e));
    }
  }

  // ---------- halaman di menu Lainnya ----------
  const pages = [
    'Anggota',
    'Booking lapangan',
    'Kas klub',
    'Turnamen internal',
    'Statistik',
    'Pengumuman',
    'Pengguna',
    'Pengaturan',
  ];
  for (const page of pages) {
    await clickText('Lainnya');
    await sleep(1600);
    const opened = await clickText(page);
    await sleep(2400);
    const text = await pageText();
    check(`halaman ${page} terbuka tanpa error`, opened && !looksBroken(text),
        text.slice(0, 60).replace(/\n/g, ' '));
    // Kembali ke menu Lainnya untuk halaman berikutnya.
    if (!(await clickText('Kembali'))) {
      await clickText('Lainnya');
    }
    await sleep(1200);
  }

  // ---------- tulis nyata: pengumuman ----------
  await clickText('Lainnya');
  await sleep(1600);
  await clickText('Pengumuman');
  await sleep(2200);
  const title = `${tag} pengumuman`;
  let wrote = false;
  if (await openAddForm('Buat pengumuman')) {
    await sleep(1800);
    if (await fillInput(0, title)) {
      await fillInput(1, 'Isi pengumuman uji otomatis');
      if (await saveDialog()) {
        await sleep(2600);
        wrote = true;
      }
    }
  }
  check('tambah pengumuman', wrote);
  if (wrote) {
    check('pengumuman muncul di daftar', (await pageText()).includes(title));
  }

  // ---------- verifikasi lewat API ----------
  const q = await fetch(`${base}/api/sql`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      sql: 'SELECT title FROM announcements WHERE title LIKE @p',
      params: { p: `${tag}%` },
    }),
  }).then((r) => r.json());
  check('pengumuman tersimpan di database', (q.rows ?? []).some((r) => r.title === title),
      JSON.stringify(q.rows));

  // ---------- bersihkan ----------
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
      sql: 'DELETE FROM announcements WHERE title LIKE @p',
      params: { p: `${tag}%` },
    }),
  }).then((r) => r.json());
  check('data uji dibersihkan', !del.error, JSON.stringify(del));

  const realErrors = consoleErrors.filter(
    (e) => !/favicon|manifest|DevTools|third-party cookie/i.test(e),
  );
  check('tidak ada error JavaScript', realErrors.length === 0, realErrors.slice(0, 2).join(' | '));

  const bad = results.filter((r) => !r.ok).length;
  console.log(`\nTarget: ${base}`);
  console.log(`${results.length - bad}/${results.length} lulus.`);
  process.exit(bad ? 1 : 0);
}

try {
  await main();
} catch (e) {
  console.error('GAGAL:', e.message);
  process.exit(1);
} finally {
  chrome.kill();
}
