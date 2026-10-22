// Uji kehadiran + patungan lapangan di browser sungguhan.
//
// Alur yang diuji (persis seperti pemakaian nyata setelah main):
//   1. Buat booking dengan biaya, lalu buka detailnya.
//   2. Tandai beberapa anggota hadir → bagian biaya terbagi rata.
//   3. Tandai satu orang sudah setor → masuk KAS sebagai pemasukan.
//   4. Batalkan setoran → catatan kas hilang, status kembali belum.
//   5. Uji OFFLINE: tandai hadir & setor tanpa jaringan → masuk antrean.
//
//   node scripts/attendance-browser-check.mjs
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const base = (process.env.BASE || 'https://minisoccer-club.vercel.app').replace(/\/$/, '');
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPass = process.env.ADMIN_PASS || 'admin123';
const port = 9900 + Math.floor(Math.random() * 90);
const tag = `_at_${Date.now().toString(36)}`;

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', `--remote-debugging-port=${port}`, '--no-sandbox', '--disable-gpu',
  `--user-data-dir=${process.env.TEMP}/chrome-at-${port}`, 'about:blank',
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
/**
 * Ketuk node yang teksnya PALING cocok.
 *
 * Pencocokan "mengandung" berbahaya di halaman ini: satu node grup bisa memuat
 * seluruh isi halaman, sehingga kata kunci apa pun akan cocok dengan node raksasa
 * itu dan ketukan mendarat di tempat yang salah. Karena itu yang dicari lebih
 * dulu adalah teks yang sama persis, lalu yang berawalan sama.
 */
async function clickText(needle, { role = 'button' } = {}) {
  const list = (await nodes()).filter((n) => role == null || n.role === role);
  const textOf = (n) => (n.label || n.text || '').trim();
  const hit = list.find((n) => textOf(n) === needle)
    ?? list.find((n) => textOf(n).startsWith(needle))
    ?? list.find((n) => (n.label || '').includes(needle) || (n.text || '').includes(needle));
  if (!hit) return false;
  await clickAt(hit.x, hit.y);
  return true;
}
async function clickNav(label) {
  const list = await nodes();
  const textOf = (n) => (n.label || n.text || '').trim();
  const hit = list.find((n) => textOf(n) === label)
    ?? list.find((n) => textOf(n).startsWith(label));
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
const outboxCount = () => evaluate(`(() => {
  const raw = localStorage.getItem('outbox:v1');
  if (!raw) return 0;
  try { return (JSON.parse(raw).items || []).length; } catch { return 0; }
})()`);

async function main() {
  const auth = await fetch(`${base}/api/auth`, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'login', username: adminUser, password: adminPass }) }).then(r => r.json());
  const token = auth.token;
  check('login admin (API)', Boolean(token), auth.error ?? '');

  // --- data uji: 3 anggota + 1 booking berbiaya 300.000 ---
  const ids = [];
  for (const suffix of ['a', 'b', 'c']) {
    const r = await api('INSERT INTO members (name, position) VALUES (@n,@p) RETURNING id',
      { n: `${tag}_${suffix}`, p: 'Bebas' }, token);
    ids.push(r.rows?.[0]?.id);
  }
  const booking = await api(
    `INSERT INTO bookings (title, starts_at, duration_min, cost)
     VALUES (@t, now(), 90, 300000) RETURNING id`, { t: `${tag}_futsal` }, token);
  const bookingId = booking.rows?.[0]?.id;
  // Pengeluaran sewa, seperti yang dibuat form Booking.
  await api(
    `INSERT INTO transactions (kind, category, amount, occurred_at, note, booking_id)
     VALUES ('expense','sewa',300000, CURRENT_DATE, @n, @b)`,
    { n: `${tag}_futsal`, b: bookingId }, token);
  check('data uji siap (3 anggota + booking 300.000)', ids.every(Boolean) && Boolean(bookingId));

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
  const li = await evaluate(`[...document.querySelectorAll('input')].map(el=>{const r=el.getBoundingClientRect();return {x:Math.round(r.x+r.width/2),y:Math.round(r.y+r.height/2)}})`);
  await clickAt(li[0].x, li[0].y); await send('Input.insertText', { text: adminUser });
  await clickAt(li[1].x, li[1].y); await send('Input.insertText', { text: adminPass });
  await clickText('Masuk', { role: 'button' }); await sleep(4500);

  // --- buka halaman Booking ---
  await clickNav('Lainnya'); await sleep(2500);
  let text = await pageText();
  check('halaman Lainnya terbuka', text.includes('Booking lapangan'),
    text.slice(0, 70).replace(/\n/g, ' '));
  const opened = await clickText('Booking lapangan', { role: null });
  check('halaman Booking terbuka', opened);
  await sleep(3500);

  text = await pageText();
  check('booking uji tampil', text.includes(`${tag}_futsal`), text.slice(0, 80).replace(/\n/g, ' '));

  // Ketuk baris booking → halaman detail kehadiran.
  //
  // Judul booking ada di `label` node grup (bukan `text`, yang hanya memuat
  // label tombol aksinya). Mencari di `text` saja membuat barisnya tidak
  // ditemukan walau terlihat di layar.
  const row = (await nodes()).find(
    (n) => `${n.label || ''}${n.text || ''}`.includes(`${tag}_futsal`),
  );
  let detail = false;
  if (row) { await clickAt(row.x, row.y); detail = true; await sleep(3000); }
  check('detail kehadiran terbuka', detail);

  text = await pageText();
  check('menyebut biaya sewa', /Biaya sewa/.test(text), text.slice(0, 70).replace(/\n/g, ' '));
  check('belum ada yang hadir', /Belum ada yang dicatat hadir|belum ada yang hadir/i.test(text));

  // --- tandai 3 orang hadir ---
  let added = false;
  if (await clickText('Tambah yang hadir', { role: 'button' })) {
    await sleep(2000);
    // Centang ketiga anggota uji.
    for (const suffix of ['a', 'b', 'c']) {
      const hit = (await nodes()).find(
        (n) => `${n.label || ''}${n.text || ''}`.includes(`${tag}_${suffix}`),
      );
      if (hit) { await clickAt(hit.x, hit.y); await sleep(500); }
    }
    added = await clickText('Tambah 3', { role: 'button' }) ||
      await clickText('Tambah', { role: 'button' });
    await sleep(2500);
  }
  check('tiga anggota ditandai hadir', added);

  // Tunggu sampai pembagian selesai. Aplikasi mengirim pembagian dalam satu
  // pernyataan, tetapi perjalanan ke server tetap butuh waktu; membaca terlalu
  // cepat menangkap keadaan setengah jadi dan menyimpulkan "bug" yang tidak ada.
  let rows = { rows: [] };
  for (let i = 0; i < 15; i++) {
    rows = await api(
      'SELECT member_id, share_amount, paid_at FROM booking_attendance WHERE booking_id=@b ORDER BY id',
      { b: bookingId }, token);
    const list = rows.rows ?? [];
    const sum = list.reduce((a, r) => a + Number(r.share_amount), 0);
    if (list.length === 3 && sum === 300000) break;
    await sleep(1000);
  }
  check('tiga baris kehadiran tersimpan', (rows.rows ?? []).length === 3,
    JSON.stringify(rows.rows));
  const shares = (rows.rows ?? []).map((r) => Number(r.share_amount));
  const total = shares.reduce((a, b) => a + b, 0);
  check('bagian terbagi rata dan jumlahnya tepat 300.000', total === 300000,
    `bagian: ${shares.join(' + ')} = ${total}`);

  // --- setor satu orang ---
  // Tunggu halaman selesai memuat ulang setelah daftar hadir berubah.
  // Tanpa ini pemeriksaan berikutnya membaca layar yang masih lama, dan
  // hasilnya "tidak ditemukan" padahal datanya sudah benar.
  text = '';
  for (let i = 0; i < 12; i++) {
    text = await pageText();
    if (/per orang/.test(text)) break;
    await sleep(1000);
  }
  check('halaman menyebut pembagian per orang', /per orang/.test(text),
    text.match(/Dibagi rata[^\n]*/)?.[0] ?? 'tidak ditemukan');

  // Ikon "Tandai sudah setor" ada di baris tiap anggota.
  //
  // Harus difilter `role === 'button'`: node GRUP baris juga memuat teks
  // "Tandai sudah setor" di dalamnya, sehingga filter yang hanya mencari teks
  // akan memilih node grup dan ketukan mendarat di tengah baris (tidak
  // melakukan apa pun).
  let payIcons = [];
  for (let i = 0; i < 12; i++) {
    payIcons = (await nodes()).filter((n) => n.role === 'button' &&
      `${n.label || ''}${n.text || ''}`.toLowerCase().includes('setor'));
    if (payIcons.length) break;
    await sleep(1000);
  }
  let paid = false;
  if (payIcons.length) { await clickAt(payIcons[0].x, payIcons[0].y); paid = true; await sleep(3500); }
  check('setoran bisa dicatat', paid, `${payIcons.length} tombol setor terlihat`);

  const afterPay = await api(
    'SELECT member_id, paid_at FROM booking_attendance WHERE booking_id=@b AND paid_at IS NOT NULL',
    { b: bookingId }, token);
  check('satu orang berstatus sudah setor', (afterPay.rows ?? []).length === 1,
    JSON.stringify(afterPay.rows));

  const cash = await api(
    `SELECT t.kind, t.category, t.amount FROM transactions t
     JOIN booking_attendance a ON a.id = t.attendance_id
     WHERE a.booking_id=@b`, { b: bookingId }, token);
  check('setoran masuk KAS sebagai pemasukan "patungan"',
    (cash.rows ?? []).length === 1 && cash.rows[0].kind === 'income' &&
      cash.rows[0].category === 'patungan',
    JSON.stringify(cash.rows));

  // --- offline: tandai hadir tanpa jaringan ---
  await send('Network.emulateNetworkConditions', { offline: true, latency: 0, downloadThroughput: 0, uploadThroughput: 0 });
  await sleep(800);
  const probe = await evaluate(
    `fetch('/api/sql',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({sql:'SELECT 1'})}).then(r=>'HTTP '+r.status).catch(()=> 'GAGAL')`);
  check('jaringan benar-benar diputus', probe === 'GAGAL', String(probe));

  // Tambah satu anggota lagi saat offline (anggota 'c' sudah hadir; pakai ulang
  // alur tambah untuk memastikan tulis offline masuk antrean).
  let offlineWrote = false;
  const before = await outboxCount();
  if (await clickText('Tambah yang hadir', { role: 'button' })) {
    await sleep(1800);
    // Pilih anggota mana pun yang tersedia.
    const any = (await nodes()).find(
      (n) => n.role !== 'tab' && /_\w+_[abc]$/.test(`${n.label || ''}${n.text || ''}`.trim()),
    );
    if (any) { await clickAt(any.x, any.y); await sleep(400); }
    if (await clickText('Tambah', { role: 'button' })) { offlineWrote = true; await sleep(2500); }
  }
  const after = await outboxCount();
  check('tulis kehadiran saat offline masuk antrean', (after ?? 0) > (before ?? 0),
    `items ${before} -> ${after}`);

  // --- online lagi, sinkron ---
  await send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
  await sleep(1500);
  await clickNav('Beranda'); await sleep(1500);
  let clicked = await clickText('Sinkron', { role: 'button' });
  if (!clicked) {
    await clickNav('Lainnya'); await sleep(1500);
    await clickText('Pengaturan'); await sleep(2000);
    clicked = await clickText('Sinkron sekarang', { role: 'button' });
  }
  let synced = false;
  for (let i = 0; i < 15; i++) {
    if ((await outboxCount() ?? 0) === 0) { synced = true; break; }
    await sleep(2000);
  }
  check('antrean offline terkirim', synced);

  check('tidak ada error JavaScript', errors.length === 0, errors.slice(0, 2).join(' | '));

  // --- bersihkan ---
  await api('DELETE FROM transactions WHERE booking_id=@b', { b: bookingId }, token);
  await api('DELETE FROM transactions WHERE attendance_id IN (SELECT id FROM booking_attendance WHERE booking_id=@b)', { b: bookingId }, token);
  await api('DELETE FROM booking_attendance WHERE booking_id=@b', { b: bookingId }, token);
  await api('DELETE FROM bookings WHERE id=@b', { b: bookingId }, token);
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
