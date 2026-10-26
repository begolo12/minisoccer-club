import { neon } from '@neondatabase/serverless';

// GET /api/health — apakah server dan database masih hidup.
//
// Tanpa ini, satu-satunya cara tahu aplikasi rusak adalah pengguna menelepon.
// Sengaja publik dan tanpa token: yang diperiksa hanya "bisa konek atau tidak",
// bukan isi data. Tidak menyebut host, versi, atau pesan error database —
// itu bocoran yang berguna untuk penyerang.
const sql = process.env.DATABASE_URL_WEB || process.env.DATABASE_URL
  ? neon(process.env.DATABASE_URL_WEB || process.env.DATABASE_URL)
  : null;

export default async function handler(req, res) {
  res.setHeader('cache-control', 'no-store');
  if (req.method !== 'GET') return res.status(405).json({ error: 'GET only' });

  const started = Date.now();
  if (!sql) {
    return res.status(503).json({ ok: false, db: 'unset' });
  }
  try {
    await sql('SELECT 1');
    return res.status(200).json({ ok: true, db: 'ok', ms: Date.now() - started });
  } catch {
    return res.status(503).json({ ok: false, db: 'error' });
  }
}
