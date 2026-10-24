// Uji tautan pendaftaran anggota di browser sungguhan.
//
// Yang dibuktikan:
//   1. Tautan /daftar terbuka tanpa login dan menampilkan formulir.
//   2. Semua isian wajib: mengirim kosong memunculkan pesan per isian.
//   3. Isian lengkap membuat anggota + akun, dan nama depan jadi username.
//   4. Akun itu benar-benar bisa dipakai masuk.
//   5. Nomor HP yang sama tidak bisa didaftarkan dua kali.
//
//   BASE=https://minisoccer-club.vercel.app/minisoccer/ node scripts/register-browser-check.mjs
//   BASE=http://127.0.0.1:8123/minisoccer/ node scripts/register-browser-check.mjs
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const base = (process.env.BASE || 'https://airevo-digital.my.id/minisoccer/').replace(/\/$/, '');
// API dipanggil lewat jalur yang SAMA dengan aplikasi: di portal itu
// `/minisoccer/api/sql`, di Vercel jalurnya diteruskan rewrite. Dulu prefiks
// `/minisoccer` dibuang, sehingga uji ini menembak `/api/sql` di akar portal —
// proyek lain, tanpa fungsi itu.
const apiBase = (process.env.API_BASE || base).replace(/\/$/, '');
const adminUser = process.env.ADMIN_USER || 'admin';
const adminPass = process.env.ADMIN_PASS || 'admin123';
const port = 9500 + Math.floor(Math.random() * 90);
// Nama hanya boleh huruf, jadi penanda uji dibuat dari huruf saja.
const tag = `Rg${Math.random().toString(36).replace(/[^a-z]/g, '').slice(0, 6)}`;
const fullName = `${tag} Budi`;
const phone = `0812${String(Date.now()).slice(-8)}`;

const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? `  (${detail})` : ''}`);
};

const chrome = spawn('C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', `--remote-debugging-port=${port}`, '--no-sandbox', '--disable-gpu',
  `--user-data-dir=${process.env.TEMP}/chrome-rg-${port}`, 'about:blank',
]);

let ws; let msgId = 0; const pending = new Map(); const errors = [];
const send = (m, p = {}) => new Promise((r) => { const id = ++msgId; pending.set(id, r); ws.send(JSON.stringify({ id, method: m, params: p })); });
const evaluate = async (e) => (await send('Runtime.evaluate', { expression: e, returnByValue: true, awaitPromise: true }))?.result?.value;

async function clickAt(x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
    await sleep(70);
  }
  await sleep(700);
}
async function nodes() {
  const raw = await evaluate(`(() => { const out = [];
    for (const el of document.querySelectorAll('[aria-label], [role]')) {
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      out.push({ label: el.getAttribute('aria-label') || '', role: el.getAttribute('role') || '',
        text: (el.textContent || '').slice(0, 300), x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) });
    } return out; })()`);
  return raw ?? [];
}
const textOf = (n) => (n.label || n.text || '').trim();
async function clickText(needle, { role = 'button' } = {}) {
  const list = (await nodes()).filter((n) => role == null || n.role === role);
  const hit = list.find((n) => textOf(n) === needle)
    ?? list.find((n) => textOf(n).startsWith(needle))
    ?? list.find((n) => textOf(n).includes(needle));
  if (!hit) return false;
  await clickAt(hit.x, hit.y);
  return true;
}
/// Seluruh teks yang terlihat, termasuk label dan pesan kesalahan.
///
/// Pohon aksesibilitas dipakai, bukan `document.body.innerText`: Flutter web
/// menggambar ke canvas, jadi teks yang terlihat hanya muncul di sana lewat
/// node semantik. `pageText()` biasa melewatkan pesan kesalahan per isian
/// karena node-nya tidak punya `role`/`aria-label`.
async function pageText() {
  const ax = await send('Accessibility.getFullAXTree');
  // `name` memuat teks statis; `value` memuat isi isian dan teks yang bisa
  // dipilih (SelectableText, mis. username & password di layar berhasil).
  const fromAx = (ax?.nodes ?? [])
    .flatMap((n) => [n.name?.value, n.value?.value])
    .filter((v) => typeof v === 'string' && v.trim().length > 0)
    .join('\n');
  return `${(await nodes()).map((n) => `${n.label}\n${n.text}`).join('\n')}\n${fromAx}`;
}

/// Isian teks yang terlihat, urut seperti di layar.
async function fields() {
  return (await evaluate(`[...document.querySelectorAll('input, textarea')]
    .filter(el => el.type !== 'hidden')
    .map(el => { const r = el.getBoundingClientRect();
      return { tag: el.tagName.toLowerCase(), x: Math.round(r.x + r.width / 2), y: Math.round(r.y + r.height / 2) }; })`)) ?? [];
}
async function fill(index, text) {
  const f = (await fields())[index];
  if (!f) return false;
  await clickAt(f.x, f.y);
  await send('Input.insertText', { text });
  await sleep(250);
  return true;
}
async function api(sql, params, token) {
  const r = await fetch(`${apiBase}/api/sql`, { method: 'POST',
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify({ sql, params }) });
  return r.json();
}

async function main() {
  const auth = await fetch(`${apiBase}/api/auth`, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'login', username: adminUser, password: adminPass }) }).then((r) => r.json());
  const token = auth.token;
  check('login admin (API)', Boolean(token), auth.error ?? '');

  let target = null;
  for (let i = 0; i < 60 && !target; i++) {
    await sleep(300);
    try { const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json(); target = list.find((t) => t.type === 'page'); } catch { /* belum */ }
  }
  ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));
  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg.result ?? msg.error); pending.delete(msg.id); return; }
    if (msg.method === 'Runtime.exceptionThrown') errors.push(msg.params.exceptionDetails?.text ?? 'exception');
  });
  await send('Page.enable'); await send('Runtime.enable'); await send('Accessibility.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 900, height: 1100, deviceScaleFactor: 1, mobile: false });

  // --- tautan pendaftaran, tanpa login ---
  await send('Page.navigate', { url: `${base}/daftar` });
  await sleep(9000);
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
  await sleep(1500);

  let text = '';
  for (let i = 0; i < 15; i++) {
    text = await pageText();
    if (/Pendaftaran anggota/.test(text)) break;
    await sleep(1000);
  }
  check('tautan /daftar membuka formulir tanpa login', /Pendaftaran anggota/.test(text),
    text.slice(0, 80).replace(/\n/g, ' '));
  check('formulir menanyakan nama, nomor HP, alamat, dan posisi',
    /Nama lengkap/.test(text) && /Nomor HP/.test(text) && /Alamat/.test(text) && /Posisi bermain/.test(text));
  // Istilah yang dipakai UI sekarang "nama pengguna"; "username" hanya
  // muncul di kartu hasil (label teknis untuk login).
  check('menjelaskan nama depan jadi nama pengguna', /nama pengguna/i.test(text));

  // --- kirim kosong: semua isian wajib ---
  await clickText('Kirim pendaftaran');
  await sleep(1500);
  text = await pageText();
  check('mengirim kosong ditolak dengan pesan per isian',
    /minimal 3 huruf/.test(text) && /Nomor HP wajib/.test(text) && /Alamat wajib/.test(text) && /Pilih posisi/.test(text),
    text.slice(0, 100).replace(/\n/g, ' '));

  // --- isi lengkap ---
  check('isian nama terisi', await fill(0, fullName));
  check('isian nomor HP terisi', await fill(1, phone));
  check('isian alamat terisi', await fill(2, 'Jl. Melati 12, Bandung'));
  // Radio di Flutter web: node `role="radio"` tidak punya label, sedangkan
  // baris yang bisa diketuk adalah node grup berlabel nama posisi. Jadi yang
  // diketuk grupnya, lalu status terpilih dibaca dari `aria-checked` —
  // bukan diasumsikan dari "tidak ada error".
  const positionRow = (await nodes()).find((n) => n.role === 'group' && textOf(n) === 'Bek');
  if (positionRow) await clickAt(positionRow.x, positionRow.y);
  await sleep(600);
  const checked = await evaluate(`(() => {
    const radios = [...document.querySelectorAll('[role=radio]')];
    const idx = radios.findIndex((r) => r.getAttribute('aria-checked') === 'true');
    const row = radios[idx]?.parentElement?.textContent || '';
    return { idx, row };
  })()`);
  check('posisi bisa dipilih', Boolean(positionRow) && checked?.idx >= 0,
    `radio terpilih index ${checked?.idx ?? -1}`);

  await clickText('Kirim pendaftaran');
  // Tunggu sampai kartu berhasil benar-benar memuat dua baris kredensialnya.
  // Judul "Pendaftaran terkirim" muncul lebih dulu, sedangkan username dan
  // password dirender di baris terpisah beberapa frame setelahnya.
  let success = '';
  for (let i = 0; i < 15; i++) {
    success = await pageText();
    if (/Pendaftaran terkirim/.test(success) && success.includes(phone)) break;
    await sleep(1000);
  }
  check('pendaftaran berhasil', /Pendaftaran terkirim/.test(success),
    success.slice(0, 100).replace(/\n/g, ' '));

  const expectedUser = tag.toLowerCase();
  // Username tampil di baris "Username" pada kartu berhasil; dicocokkan
  // sebagai kata utuh supaya tidak tertukar dengan bagian lain kalimat.
  // Diperiksa pada kartu berhasil saja. Mencocokkan seluruh teks layar berbahaya:
  // isian formulir masih memuat nama dan nomor HP yang sama, jadi pemeriksaan
  // akan lolos walau pendaftarannya gagal.
  const card = success.slice(success.indexOf('Pendaftaran terkirim'));
  check('username = nama depan',
    new RegExp(`\\b${expectedUser}\\b`).test(card.toLowerCase()),
    `mencari "${expectedUser}" di kartu berhasil`);
  check('password awal (nomor HP) ditampilkan', card.includes(phone), phone);

  // --- data benar-benar tersimpan ---
  const member = await api('SELECT id, name, phone, address, position FROM members WHERE name = @n',
    { n: fullName }, token);
  const row = (member.rows ?? [])[0];
  check('anggota tersimpan dengan alamat dan posisi',
    Boolean(row) && row.address === 'Jl. Melati 12, Bandung' && row.position === 'Bek',
    JSON.stringify(row));
  check('nomor HP disimpan dalam bentuk baku', row?.phone === phone, row?.phone ?? '');

  const user = await api('SELECT username, role, member_id FROM users WHERE username = @u',
    { u: expectedUser }, token);
  const urow = (user.rows ?? [])[0];
  check('akun dibuat dengan username nama depan',
    Boolean(urow) && urow.role === 'member' && urow.member_id === row?.id,
    JSON.stringify(urow));

  // --- akun itu bisa dipakai masuk ---
  const login = await fetch(`${apiBase}/api/auth`, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'login', username: expectedUser, password: phone }) }).then((r) => r.json());
  check('akun baru bisa masuk dengan password awal', Boolean(login.token), login.error ?? '');

  // --- nomor HP yang sama tidak bisa dua kali ---
  await send('Page.navigate', { url: `${base}/daftar` });
  await sleep(8000);
  await evaluate(`document.querySelector('flt-semantics-placeholder')?.click()`);
  await sleep(1500);
  await fill(0, `${tag} Siti`);
  await fill(1, phone);
  await fill(2, 'Jl. Kenanga 3, Bandung');
  const kiperRow = (await nodes()).find((n) => n.role === 'group' && textOf(n) === 'Kiper');
  if (kiperRow) await clickAt(kiperRow.x, kiperRow.y);
  await sleep(400);
  await clickText('Kirim pendaftaran');
  // Pesan penolakan muncul sebagai ShadAlert di dalam formulir; tunggu sampai
  // teksnya benar-benar ter-render, bukan hanya sampai tombol tertekan.
  let dup = '';
  for (let i = 0; i < 20; i++) {
    dup = await pageText();
    if (/sudah terdaftar/.test(dup)) break;
    await sleep(1000);
  }
  check('nomor HP ganda ditolak', /sudah terdaftar/.test(dup),
    dup.slice(0, 100).replace(/\n/g, ' '));

  // --- hapus anggota mencabut akses akunnya ---
  //
  // Menghapus anggota hanya melepas tautan `users.member_id` (FK ON DELETE SET
  // NULL), jadi tanpa trigger akunnya tetap aktif dan bisa masuk — termasuk
  // hak tulis kalau dulu dia bendahara. Trigger `members_deactivate_account`
  // yang menutup celah itu; diuji di sini lewat pernyataan yang sama dengan
  // yang dikirim aplikasi saat menekan Hapus.
  const delRes = await api('DELETE FROM members WHERE id=@id', { id: row.id }, token);
  const afterDel = await api('SELECT username, active FROM users WHERE username = @u',
    { u: expectedUser }, token);
  const relogin = await fetch(`${apiBase}/api/auth`, { method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ action: 'login', username: expectedUser, password: phone }) }).then((r) => r.json());
  check('hapus anggota menonaktifkan akunnya',
    delRes.rowCount === 1 && afterDel.rows?.[0]?.active === false && !relogin.token,
    `aktif=${afterDel.rows?.[0]?.active}, login=${relogin.token ? 'masih bisa' : 'ditolak'}`);

  check('tidak ada error JavaScript', errors.length === 0, errors.slice(0, 2).join(' | '));

  // --- bersihkan ---
  //
  // `users` TIDAK bisa dihapus lewat /api/sql (guard menolaknya, dan itu
  // memang aturannya); jalurnya /api/auth. Dulu skrip ini mencoba lewat SQL,
  // gagal tanpa suara, dan setiap kali dijalankan meninggalkan satu akun uji
  // yang menumpuk di daftar Pengguna.
  const usersLeft = await api('SELECT id, username FROM users WHERE username LIKE @p',
    { p: `${tag.toLowerCase()}%` }, token);
  for (const u of usersLeft.rows ?? []) {
    await fetch(`${apiBase}/api/auth`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
      body: JSON.stringify({ action: 'delete', id: u.id }),
    });
  }
  await api('DELETE FROM members WHERE name LIKE @p', { p: `${tag}%` }, token);

  const leftMembers = await api('SELECT count(*)::int AS n FROM members WHERE name LIKE @p',
    { p: `${tag}%` }, token);
  const leftUsers = await api('SELECT count(*)::int AS n FROM users WHERE username LIKE @p',
    { p: `${tag.toLowerCase()}%` }, token);
  check('data uji dibersihkan (anggota + akun)',
    (leftMembers.rows?.[0]?.n ?? 0) === 0 && (leftUsers.rows?.[0]?.n ?? 0) === 0,
    `anggota ${leftMembers.rows?.[0]?.n}, akun ${leftUsers.rows?.[0]?.n}`);

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
