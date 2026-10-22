// Server API lokal untuk dev & uji e2e: meniru kontrak Vercel Functions
// (`res.status().json()`, `req.body` sudah di-parse) supaya `api/sql.js` dan
// `api/auth.js` bisa dijalankan apa adanya tanpa `vercel dev`.
//
//   node scripts/dev-api.mjs            # http://localhost:3000
//   PORT=4000 node scripts/dev-api.mjs
//
// Env dibaca dari `.env` di root repo (DATABASE_URL, DATABASE_URL_WEB,
// AUTH_SECRET). Tidak ada kredensial yang ditulis ke file ini.
import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';

// ---- .env minimal (tanpa dependensi tambahan) ----
if (existsSync(new URL('../.env', import.meta.url))) {
  const raw = readFileSync(new URL('../.env', import.meta.url), 'utf8');
  for (const line of raw.split(/\r?\n/)) {
    const m = /^\s*([A-Z0-9_]+)\s*=\s*(.*)$/.exec(line);
    if (!m) continue;
    const value = m[2].trim().replace(/^["']|["']$/g, '');
    if (!(m[1] in process.env)) process.env[m[1]] = value;
  }
}

const MAX_BODY = 256 * 1024;

/** Tempelkan helper `status()`/`json()` ala Express ke ServerResponse. */
function decorate(res) {
  res.status = (code) => {
    res.statusCode = code;
    return res;
  };
  res.json = (payload) => {
    if (!res.headersSent) res.setHeader('content-type', 'application/json; charset=utf-8');
    res.end(JSON.stringify(payload));
    return res;
  };
  return res;
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY) throw new Error('body terlalu besar');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

const routes = {
  '/api/sql': () => import('../api/sql.js'),
  '/api/auth': () => import('../api/auth.js'),
};

const server = createServer(async (req, res) => {
  decorate(res);
  const url = new URL(req.url, 'http://localhost');
  const load = routes[url.pathname];
  if (!load) {
    res.setHeader('access-control-allow-origin', '*');
    return res.status(404).json({ error: 'not found' });
  }

  // CORS: app web dev berjalan di port lain (flutter run -d chrome).
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-headers', 'content-type, authorization');
  res.setHeader('access-control-allow-methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();

  try {
    const raw = await readBody(req);
    req.body = raw ? JSON.parse(raw) : {};
  } catch {
    return res.status(400).json({ error: 'Body bukan JSON' });
  }

  try {
    const mod = await load();
    await mod.default(req, res);
  } catch (e) {
    console.error('[dev-api]', e);
    if (!res.headersSent) res.status(500).json({ error: 'Server sedang bermasalah. Coba lagi.' });
  }
});

const port = Number(process.env.PORT || 3000);
server.listen(port, () => {
  console.log(`API lokal siap di http://localhost:${port}`);
  console.log(`  DATABASE_URL     : ${process.env.DATABASE_URL ? 'ada' : 'KOSONG'}`);
  console.log(`  DATABASE_URL_WEB : ${process.env.DATABASE_URL_WEB ? 'ada' : 'KOSONG (fallback owner)'}`);
  console.log(`  AUTH_SECRET      : ${process.env.AUTH_SECRET ? 'ada' : 'KOSONG (token ditolak)'}`);
});
