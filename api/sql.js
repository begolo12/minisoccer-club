import { neon } from '@neondatabase/serverless';
import { bearer, verifyToken } from './_auth.js';

// POST /api/sql  { sql, params }
// Satu-satunya pintu DB untuk versi web (browser tidak bisa buka TCP ke Postgres).
// Wajib header `Authorization: Bearer <token>` dari /api/auth.

const sql = neon(process.env.DATABASE_URL);

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });

  const session = verifyToken(bearer(req));
  if (!session) return res.status(401).json({ error: 'Sesi habis, silakan login ulang' });

  const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
  const { sql: text, params = {} } = body;
  if (!text) return res.status(400).json({ error: 'sql required' });

  try {
    const { text: query, values } = toPositional(text, params);
    const result = await sql(query, values, { fullResults: true });
    return res.status(200).json({ rows: result.rows, rowCount: result.rowCount });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
}

// `@nama` -> `$1` (driver Neon hanya menerima positional).
function toPositional(text, params) {
  const order = [];
  const sqlText = text.replace(/@([a-zA-Z_][a-zA-Z0-9_]*)/g, (_, name) => {
    let i = order.indexOf(name);
    if (i === -1) {
      order.push(name);
      i = order.length - 1;
    }
    return `$${i + 1}`;
  });
  return { text: sqlText, values: order.map((n) => params[n] ?? null) };
}
