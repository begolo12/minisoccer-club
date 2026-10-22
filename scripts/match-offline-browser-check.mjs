// Uji alur lapangan: MENYELESAIKAN LAGA saat offline.
//
// Skenario nyata: laga selesai di lapangan, tidak ada sinyal. Sebelum
// diperbaiki, dialog "Selesai" tidak terbuka sama sekali karena membaca
// rincian sesi lebih dulu, dan penyelesaian laga gagal total.
//
//   node scripts/match-offline-browser-check.mjs
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const base = (process.env.BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPass = process.env.ADMIN_PASS || 'admin123';
const port = 9800 + Math.floor(Math.random() * 100);
const tag = `_mo_${Date.now().toString(36)}`;

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', `--remote-debugging-port=${port}`, '--no-sandbox', '--disable-gpu',
  `--user-data-dir=${process.env.TEMP}/chrome-mo-${port}`, 'about:blank',
]);

let ws; let msgId = 0; const pending = new Map(); const errors = [];
const send = (m, p = {}) => new Promise((r) => { const id = ++msgId; pending.set(id, r); ws.send(JSON.stringify({ id, method: m, params: p })); });
const evaluate = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }))?.result?.value;

async function clickAt(x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(70);
  }
  await sleep(800);
}
async function nodes() {
  const raw = await evaluate(`(() => { const out = [];
    for (const el of document.querySelectorAll('[aria-label], [role]')) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      out.push({ label: el.getAttribute('aria-label') || '', role: el.getAttribute('role') || '',
        text: (el.textContent || '').slice(0, 300), x: Math.round(r.x+r.width/2), y: Math.round(r.y+r.height/2) });
    } return out; })()`);
  return raw ?? [];
}
async function clickText(needle, { role = 'button' } = {}) {
  const hit = (await nodes()).find((n) => (role == null || n.role === role) &&
    ((n.label || '').includes(needle) || (n.text || '').includes(needle)));
  if (!hit) return false; await clickAt(hit.x, hit.y); return true;
}
async function clickNav(label) {
  const list = await nodes();
  const hit = list.find((n) => n.role === 'tab' && (n.label || n.text || '').includes(label))
    ?? list.find((n) => n.role === 'button' && (n.label || n.text || '').includes(label));
  if (!hit) return false; await clickAt(hit.x, hit.y); return true;
}
async function pageText() { return (await nodes()).map(n => `${n.label}\n${n.text}`).join('\n'); }
async function api(sql, params, token) {
  const r = await fetch(`${base}/api/sql`, { method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ sql, params }) });
  return r.json();
}

async function main() {
  const auth = await fetch(`${base}/api/auth`, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'login', username: adminUser, password: adminPass }) }).then(r => r.json());
  const token = auth.token;
  check('login admin (API)', Boolean(token), auth.error ?? '');

  // Siapkan dua tim + satu laga berjalan.
  const a = await api('INSERT INTO teams (name) VALUES (@n) RETURNING id', { n: `${tag}_A` }, token);
  const b = await api('INSERT INTO teams (name) VALUES (@n) RETURNING id', { n: `${tag}_B` }, token);
  const tA = a.rows?.[0]?.id, tB = b.rows?.[0]?.id;
  const m = await api(
    `INSERT INTO matches (home_team_id, away_team_id, played_at, status)
     VALUES (@h, @a, now(), 'ongoing') RETURNING id`,
    { h: tA, a: tB }, token);
  const matchId = m.rows?.[0]?.id;
  check('laga uji siap (status berjalan)', Boolean(matchId), JSON.stringify(m));

  // ---------- buka app ----------
  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(300);
    try { const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); target = list.find(t => t.type === 'page'); } catch { /* belum siap */ }
  }
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener('open', r, { once: true }));
  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg.result ?? msg.error); pending.delete(msg.id); return; }
    if (msg.method === 'Runtime.exceptionThrown') errors.push(msg.params.exceptionDetails?.text ?? 'exception');
  });

  await send('Page.enable');
  await send('Runtime.enable');
  await send('Network.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: base });
  await sleep(9000);
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
  await sleep(1500);

  await clickText('Masuk'); await sleep(2500);
  const li = await evaluate(`[...document.querySelectorAll('input')].map(el=>{const r=el.getBoundingClientRect();return {x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)}})`);
  await clickAt(li[0].x, li[0].y); await send('Input.insertText', { text: adminUser });
  await clickAt(li[1].x, li[1].y); await send('Input.insertText', { text: adminPass });
  await clickText('Masuk', { role: 'button' }); await sleep(4500);

  // Buka halaman Tanding supaya daftar laga (dan sesinya) masuk cache.
  await clickNav('Tanding');
  await sleep(3000);
  let text = await pageText();
  check('laga uji tampil di halaman Tanding', text.includes(`${tag}_A`) || text.includes(`${tag}_B`),
    text.slice(0, 90).replace(/\n/g, ' '));

  // ---------- putus jaringan ----------
  await send('Network.emulateNetworkConditions', { offline: true, latency: 0, downloadThroughput: 0, uploadThroughput: 0 });
  await sleep(800);
  const probe = await evaluate(
    `fetch('/api/sql',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({sql:'SELECT 1'})}).then(r=>'HTTP '+r.status).catch(()=> 'GAGAL')`,
  );
  check('jaringan benar-benar diputus', probe === 'GAGAL', String(probe));

  // Buka detail laga lalu tekan Selesai.
  await clickNav('Tanding');
  await sleep(2000);
  const row = (await nodes()).find((n) => (n.text || '').includes(`${tag}_A`) || (n.text || '').includes(`${tag}_B`));
  let opened = false;
  if (row) { await clickAt(row.x, row.y); opened = true; await sleep(2500); }
  check('detail laga terbuka saat offline', opened);

  // Cari tombol "Selesai".
  let finishClicked = await clickText('Selesai', { role: 'button' });
  if (!finishClicked) finishClicked = await clickText('Selesai', { role: null });
  check('tombol Selesai bisa ditekan saat offline', finishClicked);
  await sleep(2500);

  // Dialog harus terbuka (ada tombol Simpan/konfirmasi), bukan gagal diam.
  const dialogText = await pageText();
  const dialogOpen = /Simpan|Yakin 0–0|Selesai pertandingan/i.test(dialogText);
  check('dialog penyelesaian laga terbuka tanpa jaringan', dialogOpen,
    dialogText.slice(0, 100).replace(/\n/g, ' '));

  // Simpan.
  const saved = (await clickText('Simpan', { role: 'button' })) ||
    (await clickText('Selesai pertandingan', { role: 'button' }));
  check('simpan hasil laga saat offline', saved);
  await sleep(2500);

  const outbox = await evaluate(`(() => {
    const raw = localStorage.getItem('outbox:v1');
    if (!raw) return 0;
    try { return (JSON.parse(raw).items || []).length; } catch { return 0; }
  })()`);
  check('penyelesaian laga masuk antrean', (outbox ?? 0) > 0, `items=${outbox}`);

  // ---------- online: kirim ----------
  await send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
  await sleep(1500);
  await clickNav('Beranda');
  await sleep(1500);
  let clicked = await clickText('Sinkron', { role: 'button' });
  if (!clicked) {
    await clickNav('Lainnya'); await sleep(1500);
    await clickText('Pengaturan'); await sleep(2000);
    clicked = await clickText('Sinkron sekarang', { role: 'button' });
  }
  let synced = false;
  for (let i = 0; i < 15; i++) {
    const left = await evaluate(`(() => {
      const raw = localStorage.getItem('outbox:v1');
      if (!raw) return 0;
      try { return (JSON.parse(raw).items || []).length; } catch { return 0; }
    })()`);
    if ((left ?? 0) === 0) { synced = true; break; }
    await sleep(2000);
  }
  check('antrean terkirim saat online', synced);

  const after = await api('SELECT status, goals_for, goals_against FROM matches WHERE id=@id', { id: matchId }, token);
  check('laga berstatus selesai di database', after.rows?.[0]?.status === 'finished',
    JSON.stringify(after.rows));

  check('tidak ada error JavaScript', errors.length === 0, errors.slice(0, 2).join(' | '));

  // Bersihkan.
  await api('DELETE FROM match_sessions WHERE match_id=@m', { m: matchId }, token);
  await api('DELETE FROM match_events WHERE match_id=@m', { m: matchId }, token);
  await api('DELETE FROM matches WHERE id=@id', { id: matchId }, token);
  await api('DELETE FROM teams WHERE name LIKE @p', { p: `${tag}%` }, token);

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
