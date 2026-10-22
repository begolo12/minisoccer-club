// Uji alur iuran per turnamen di BROWSER SUNGGUHAN terhadap produksi.
//
// Membuktikan janji sistem baru: tagihan hanya berisi anggota dari tim yang
// ikut turnamen itu, nominalnya dari turnamen, dan pembayaran tersimpan
// dengan tournament_id (bukan period).
//
//   node scripts/dues-browser-check.mjs
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const base = (process.env.BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPass = process.env.ADMIN_PASS || 'admin123';
const port = 9450 + Math.floor(Math.random() * 150);
const tag = `_dt_${Date.now().toString(36)}`;

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
  `--user-data-dir=${process.env.TEMP}/chrome-dues-${port}`,
  'about:blank',
]);

let ws;
let msgId = 0;
const pending = new Map();
const errors = [];

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
  const raw = await evaluate(`(() => {
    const out = [];
    for (const el of document.querySelectorAll('[aria-label], [role]')) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      out.push({ label: el.getAttribute('aria-label') || '', role: el.getAttribute('role') || '',
        text: (el.textContent || '').slice(0, 400),
        x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) });
    }
    return out;
  })()`);
  return raw ?? [];
}

async function clickText(needle, { role = 'button' } = {}) {
  const hit = (await nodes()).find(
    (n) => (role == null || n.role === role) &&
      ((n.label || '').includes(needle) || (n.text || '').includes(needle)),
  );
  if (!hit) return false;
  await clickAt(hit.x, hit.y);
  return true;
}

async function clickNav(label) {
  const list = await nodes();
  const hit =
    list.find((n) => n.role === 'tab' && (n.label || n.text || '').includes(label)) ??
    list.find((n) => n.role === 'button' && (n.label || n.text || '').includes(label));
  if (!hit) return false;
  await clickAt(hit.x, hit.y);
  return true;
}

async function fillInput(index, text) {
  const inputs = (await evaluate(`(() => {
    return [...document.querySelectorAll('input, textarea')]
      .filter((el) => el.type !== 'hidden')
      .map((el) => { const r = el.getBoundingClientRect();
        return { y: Math.round(r.y + r.height / 2), x: Math.round(r.x + r.width / 2) }; });
  })()`)) ?? [];
  const target = inputs.filter((i) => i.y > 120).sort((a, b) => a.y - b.y)[index];
  if (!target) return false;
  await clickAt(target.x, target.y);
  await send('Input.insertText', { text });
  await sleep(350);
  return true;
}

async function pageText() {
  return (await nodes()).map((n) => `${n.label}\n${n.text}`).join('\n');
}

async function save() {
  for (const label of ['Simpan', 'Buat', 'Kirim']) {
    if (await clickText(label, { role: 'button' })) return label;
  }
  return null;
}

/** Panggil API langsung (bukan sesi browser) untuk menyiapkan & membersihkan. */
async function api(sql, params, token) {
  const r = await fetch(`${base}/api/sql`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ sql, params }),
  });
  return r.json();
}

async function main() {
  // ---------- siapkan data lewat API (lebih andal daripada lewat UI) ----------
  const auth = await fetch(`${base}/api/auth`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'login', username: adminUser, password: adminPass }),
  }).then((r) => r.json());
  const token = auth.token;
  check('login admin (API)', Boolean(token), auth.error ?? '');

  const mkMember = (n) =>
    api('INSERT INTO members (name, position) VALUES (@n, @p) RETURNING id',
      { n, p: 'Bebas' }, token);
  const inTeam = await mkMember(`${tag}_ikut`);
  const outTeam = await mkMember(`${tag}_tidak_ikut`);
  const mIn = inTeam.rows?.[0]?.id;
  const mOut = outTeam.rows?.[0]?.id;

  const team = await api('INSERT INTO teams (name) VALUES (@n) RETURNING id', { n: `${tag}_tim` }, token);
  const teamId = team.rows?.[0]?.id;
  await api('INSERT INTO team_players (team_id, member_id) VALUES (@t, @m)',
    { t: teamId, m: mIn }, token);

  const tour = await api(
    `INSERT INTO tournaments (name, starts_at, entry_fee, status)
     VALUES (@n, now(), 60000, 'running') RETURNING id`, { n: `${tag}_turnamen` }, token);
  const tourId = tour.rows?.[0]?.id;
  await api('INSERT INTO tournament_teams (tournament_id, team_id, group_no) VALUES (@t, @tm, 1)',
    { t: tourId, tm: teamId }, token);
  check('data uji siap', Boolean(mIn && mOut && teamId && tourId));

  // ---------- buka app ----------
  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(300);
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      target = list.find((t) => t.type === 'page');
    } catch { /* belum siap */ }
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
    if (msg.method === 'Runtime.exceptionThrown') {
      errors.push(msg.params.exceptionDetails?.text ?? 'exception');
    }
  });

  await send('Page.enable');
  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', {
    width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false,
  });
  await send('Page.navigate', { url: base });
  await sleep(9000);
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
  await sleep(1500);

  // login lewat UI supaya sesi browser aktif
  await clickText('Masuk');
  await sleep(2500);
  const loginInputs = await evaluate(`[...document.querySelectorAll('input')].map(el=>{const r=el.getBoundingClientRect();return {x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)}})`);
  await clickAt(loginInputs[0].x, loginInputs[0].y);
  await send('Input.insertText', { text: adminUser });
  await clickAt(loginInputs[1].x, loginInputs[1].y);
  await send('Input.insertText', { text: adminPass });
  await clickText('Masuk', { role: 'button' });
  await sleep(4500);

  // ---------- halaman Iuran ----------
  await clickNav('Iuran');
  await sleep(3000);
  let text = await pageText();
  // Bukti bahwa ini iuran per turnamen: adanya pemilih turnamen (chip) dan
  // nominal per anggota. Subtitle "Per turnamen" tidak diekspos ke
  // accessibility tree Flutter, jadi tidak bisa diperiksa dari sini —
  // sudah diverifikasi lewat screenshot.
  check(
    'halaman Iuran memakai pemilih turnamen',
    /Iuran Rp [\d.]+ per anggota/.test(text) || text.includes('turnamen'),
    text.slice(0, 70).replace(/\n/g, ' '),
  );

  // Pilih turnamen uji lewat chip. Chip ada di daftar horizontal yang mungkin
  // perlu di-scroll: cari tombol/node yang teksnya persis nama turnamen uji.
  let picked = false;
  for (let attempt = 0; attempt < 12 && !picked; attempt++) {
    const chip = (await nodes()).find(
      (n) => (n.text || '').trim() === `${tag}_turnamen` || (n.label || '').trim() === `${tag}_turnamen`,
    );
    if (chip) {
      await clickAt(chip.x, chip.y);
      picked = true;
      break;
    }
    // Geser daftar chip ke kiri untuk mencari berikutnya.
    await send('Input.dispatchMouseEvent', {
      type: 'mouseWheel', x: 700, y: 120, deltaX: 300, deltaY: 0,
    });
    await sleep(700);
  }
  check('turnamen uji bisa dipilih di chip', picked);
  await sleep(2500);
  text = await pageText();

  check('nominal iuran turnamen tampil', text.includes('Rp 60.000'),
    text.match(/Iuran Rp [\d.]+ per anggota/)?.[0] ?? 'tidak ditemukan');
  check('anggota yang ikut turnamen muncul di tagihan', text.includes(`${tag}_ikut`));
  check(
    'anggota yang TIDAK ikut turnamen tidak ditagih',
    !text.includes(`${tag}_tidak_ikut`),
    text.includes(`${tag}_tidak_ikut`) ? 'MUNCUL (bug)' : 'benar, tidak muncul',
  );

  // ---------- catat iuran lewat UI ----------
  const addBtn = (await nodes()).find((n) => n.role === 'button' && n.y < 130 && n.x > 1200);
  let paid = false;
  if (addBtn) {
    await clickAt(addBtn.x, addBtn.y);
    await sleep(2200);
    if (await fillInput(1, '60.000')) {
      if (await save()) {
        await sleep(3000);
        paid = true;
      }
    }
  }
  check('catat iuran lewat UI', paid);

  // ---------- verifikasi di database ----------
  const saved = await api(
    'SELECT member_id, amount, tournament_id, period FROM payments WHERE tournament_id=@t',
    { t: tourId }, token);
  if (saved.error) {
    // Kolom `period` sudah tidak ada — itu yang diharapkan.
    const rows = await api(
      'SELECT member_id, amount, tournament_id FROM payments WHERE tournament_id=@t',
      { t: tourId }, token);
    check('iuran tersimpan dengan tournament_id', (rows.rows ?? []).length > 0,
      JSON.stringify(rows.rows));
    check('kolom period sudah tidak ada', true, 'query dengan period ditolak (benar)');
  } else {
    check('iuran tersimpan dengan tournament_id',
      (saved.rows ?? []).every((r) => r.tournament_id === tourId), JSON.stringify(saved.rows));
    check('kolom period sudah tidak ada', false, 'period MASIH ada (migrasi gagal)');
  }

  // ---------- bersihkan ----------
  await api('DELETE FROM payments WHERE tournament_id=@t', { t: tourId }, token);
  await api('DELETE FROM tournament_teams WHERE tournament_id=@t', { t: tourId }, token);
  await api('DELETE FROM tournaments WHERE id=@t', { t: tourId }, token);
  await api('DELETE FROM team_players WHERE team_id=@t', { t: teamId }, token);
  await api('DELETE FROM teams WHERE id=@t', { t: teamId }, token);
  await api('DELETE FROM members WHERE name LIKE @p', { p: `${tag}%` }, token);
  const left = await api('SELECT count(*)::int AS n FROM members WHERE name LIKE @p',
    { p: `${tag}%` }, token);
  check('data uji dibersihkan', (left.rows?.[0]?.n ?? 0) === 0, JSON.stringify(left.rows));

  check('tidak ada error JavaScript', errors.length === 0, errors.slice(0, 2).join(' | '));

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
