// Uji riwayat iuran per anggota di browser sungguhan.
//
//   node scripts/member-dues-browser-check.mjs
import { spawn } from 'node:child_process';
import { adminCredentials } from './_admin-auth.mjs';
import { setTimeout as sleep } from 'node:timers/promises';

const base = (process.env.BASE || 'https://airevo-digital.my.id/minisoccer').replace(/\/$/, '');
const { user: adminUser, pass: adminPass } = adminCredentials();
const port = 9300 + Math.floor(Math.random() * 90);
const tag = `_md_${Date.now().toString(36)}`;

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', `--remote-debugging-port=${port}`, '--no-sandbox', '--disable-gpu',
  `--user-data-dir=${process.env.TEMP}/chrome-md-${port}`, 'about:blank',
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
/** Ketuk teks yang paling cocok: sama persis, lalu berawalan, baru mengandung. */
async function clickText(needle, { role = 'button' } = {}) {
  const list = (await nodes()).filter((n) => role == null || n.role === role);
  const t = (n) => (n.label || n.text || '').trim();
  const hit = list.find((n) => t(n) === needle)
    ?? list.find((n) => t(n).startsWith(needle))
    ?? list.find((n) => (n.label || '').includes(needle) || (n.text || '').includes(needle));
  if (!hit) return false;
  await clickAt(hit.x, hit.y);
  return true;
}
async function clickNav(label) {
  const list = await nodes();
  const t = (n) => (n.label || n.text || '').trim();
  const hit = list.find((n) => t(n) === label) ?? list.find((n) => t(n).startsWith(label));
  if (!hit) return false;
  await clickAt(hit.x, hit.y);
  return true;
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

  // Data uji: satu anggota, dua turnamen yang dia ikuti.
  const mem = await api('INSERT INTO members (name, position) VALUES (@n,@p) RETURNING id',
    { n: `${tag}_budi`, p: 'Bek' }, token);
  const memberId = mem.rows?.[0]?.id;
  const team = await api('INSERT INTO teams (name) VALUES (@n) RETURNING id', { n: `${tag}_tim` }, token);
  const teamId = team.rows?.[0]?.id;
  await api('INSERT INTO team_players (team_id, member_id) VALUES (@t,@m)', { t: teamId, m: memberId }, token);

  const t1 = await api(
    `INSERT INTO tournaments (name, starts_at, entry_fee, status)
     VALUES (@n, now() - interval '10 days', 60000, 'done') RETURNING id`,
    { n: `${tag}_lunas` }, token);
  const t2 = await api(
    `INSERT INTO tournaments (name, starts_at, entry_fee, status)
     VALUES (@n, now(), 75000, 'running') RETURNING id`,
    { n: `${tag}_belum` }, token);
  const t1Id = t1.rows?.[0]?.id, t2Id = t2.rows?.[0]?.id;
  for (const tid of [t1Id, t2Id]) {
    await api('INSERT INTO tournament_teams (tournament_id, team_id, group_no) VALUES (@t,@tm,1)',
      { t: tid, tm: teamId }, token);
  }
  // Sudah bayar untuk turnamen pertama saja.
  await api('INSERT INTO payments (member_id, amount, tournament_id) VALUES (@m,@a,@t)',
    { m: memberId, a: 60000, t: t1Id }, token);
  check('data uji siap (1 anggota, 2 turnamen, 1 lunas)', Boolean(memberId) && Boolean(t1Id) && Boolean(t2Id));

  // --- buka app ---
  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(300);
    try { const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); target = list.find(t => t.type === 'page'); } catch { /* belum */ }
  }
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener('open', r, { once: true }));
  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg.result ?? msg.error); pending.delete(msg.id); return; }
    if (msg.method === 'Runtime.exceptionThrown') errors.push(msg.params.exceptionDetails?.text ?? 'exception');
  });
  await send('Page.enable'); await send('Runtime.enable'); await send('Network.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: base });
  await sleep(9000);
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
  await sleep(1500);

  await clickText('Masuk'); await sleep(2500);
  // Tunggu input muncul: di mesin lambat daftar input masih kosong dan `li[0]`
  // akan melempar "undefined (reading 'x')".
  let li = [];
  for (let i = 0; i < 20; i++) {
    li = await evaluate(`[...document.querySelectorAll('input')].map(el=>{const r=el.getBoundingClientRect();return {x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)}})`);
    if (li && li.length >= 2) break;
    await sleep(1000);
  }
  if (!li || li.length < 2) throw new Error('form masuk tidak muncul');
  await clickAt(li[0].x, li[0].y); await send('Input.insertText', { text: adminUser });
  await clickAt(li[1].x, li[1].y); await send('Input.insertText', { text: adminPass });
  await clickText('Masuk', { role: 'button' }); await sleep(4500);

  // Buka halaman Anggota lewat tab Lainnya.
  await clickNav('Lainnya'); await sleep(2500);
  check('halaman Lainnya terbuka', (await pageText()).includes('Anggota'));
  await clickText('Anggota', { role: null }); await sleep(3000);

  let text = await pageText();
  check('halaman Anggota terbuka', text.includes(`${tag}_budi`), text.slice(0, 80).replace(/\n/g, ' '));

  // Ketuk baris anggota uji: baris membuka riwayat iuran untuk semua role.
  //
  // Jangan mencari ikon: baris lain di daftar memakai ikon yang sama, dan
  // mengambil tombol pertama akan membuka anggota lain sehingga halaman tampak
  // kosong padahal datanya ada.
  const row = (await nodes()).find((n) => `${n.label || ''}${n.text || ''}`.includes(`${tag}_budi`));
  let opened = false;
  if (row) {
    // Ketuk di tengah teks baris, bukan di ujung kanan yang berisi ikon aksi.
    await clickAt(row.x - 200, row.y);
    opened = true;
    await sleep(3500);
  }
  check('riwayat iuran anggota terbuka', opened);

  text = await pageText();
  check('menyebut total iuran', /TOTAL IURAN|Total iuran/i.test(text),
    text.slice(0, 90).replace(/\n/g, ' '));
  check('menyebut tunggakan', /TUNGGAKAN|Tunggakan/i.test(text));
  check('turnamen yang sudah dibayar tampil di riwayat', text.includes(`${tag}_lunas`));
  check('turnamen yang belum dibayar tampil sebagai tunggakan', text.includes(`${tag}_belum`));
  check('nominal iuran terbaca', text.includes('60.000') && text.includes('75.000'),
    text.match(/Rp [\d.]+/g)?.slice(0, 6).join(', ') ?? 'tidak ada');

  check('tidak ada error JavaScript', errors.length === 0, errors.slice(0, 2).join(' | '));

  // --- bersihkan ---
  await api('DELETE FROM payments WHERE member_id=@m', { m: memberId }, token);
  for (const tid of [t1Id, t2Id]) {
    await api('DELETE FROM tournament_teams WHERE tournament_id=@t', { t: tid }, token);
    await api('DELETE FROM tournaments WHERE id=@t', { t: tid }, token);
  }
  await api('DELETE FROM team_players WHERE team_id=@t', { t: teamId }, token);
  await api('DELETE FROM teams WHERE id=@t', { t: teamId }, token);
  await api('DELETE FROM members WHERE name LIKE @p', { p: `${tag}%` }, token);
  const left = await api('SELECT count(*)::int AS n FROM members WHERE name LIKE @p', { p: `${tag}%` }, token);
  check('data uji dibersihkan', (left.rows?.[0]?.n ?? 0) === 0, JSON.stringify(left.rows));

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
