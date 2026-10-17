import { neon } from '@neondatabase/serverless';
import { issueToken } from './_auth.js';

// POST /api/auth  { action: 'login' | 'register', username, password, role? }
// Password di-hash bcrypt oleh Postgres (pgcrypto), tidak pernah disimpan di app.

const sql = neon(process.env.DATABASE_URL);

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
  const { action, username, password, role } = body;
  const user = String(username || '').trim();
  const pass = String(password || '');

  // Cek apakah DB masih kosong (belum ada user) — dipakai layar login.
  if (action === 'status') {
    try {
      const [{ n }] = await sql('SELECT count(*)::int AS n FROM users');
      return res.status(200).json({ bootstrap: n === 0 });
    } catch (e) {
      return res.status(400).json({ error: e.message });
    }
  }

  if (!user || pass.length < 6) {
    return res.status(400).json({ error: 'Username wajib, password minimal 6 karakter' });
  }

  try {
    if (action === 'register') {
      const [{ n }] = await sql('SELECT count(*)::int AS n FROM users');
      const bootstrapKey = req.headers['x-bootstrap-key'];
      const allowed = n === 0 || (process.env.APP_KEY && bootstrapKey === process.env.APP_KEY);
      if (!allowed) return res.status(403).json({ error: 'Pendaftaran hanya lewat admin' });

      const rows = await sql(
        `INSERT INTO users (username, role, password_hash)
         VALUES ($1, $2, crypt($3, gen_salt('bf', 10)))
         ON CONFLICT (username) DO NOTHING
         RETURNING id, username, role`,
        [user, role === 'admin' || role === 'treasurer' ? role : 'member', pass],
      );
      if (!rows.length) return res.status(409).json({ error: 'Username sudah dipakai' });
      return res.status(200).json({ ...rows[0], token: issueToken(rows[0]) });
    }

    // login
    const rows = await sql(
      `SELECT id, username, role FROM users
       WHERE username = $1 AND active AND password_hash IS NOT NULL
         AND password_hash = crypt($2, password_hash)`,
      [user, pass],
    );
    if (!rows.length) return res.status(401).json({ error: 'Username atau password salah' });
    return res.status(200).json({ ...rows[0], token: issueToken(rows[0]) });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
}
