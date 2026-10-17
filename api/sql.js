import { neon } from '@neondatabase/serverless';

// POST /api/sql  { sql, params }
// Satu-satunya pintu DB untuk versi web (browser tidak bisa buka TCP ke Postgres).
// Dilindungi header `x-app-key` yang harus sama dengan env APP_KEY.

const sql = neon(process.env.DATABASE_URL);

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  if (process.env.APP_KEY && req.headers['x-app-key'] !== process.env.APP_KEY) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body || {};
  const { sql: text, params = {} } = body;
  if (!text) return res.status(400).json({ error: 'sql required' });

  try {
    const { text: query, values } = toPositional(text, params);
    const rows = await sql.query(query, values);
    return res.status(200).json({ rows, rowCount: rows.length });
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
