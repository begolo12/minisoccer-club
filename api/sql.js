import { neon } from '@neondatabase/serverless';

// POST /api/sql  { sql, params }
// Satu-satunya pintu DB untuk versi web (browser tidak bisa TCP ke Postgres).
// Dilindungi header `x-app-key` == env APP_KEY.

const APP_KEY = process.env.APP_KEY;

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'POST only' });
  }
  if (APP_KEY && req.headers['x-app-key'] !== APP_KEY) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : req.body ?? {};
  const { sql, params = {} } = body;
  if (typeof sql !== 'string' || !sql.trim()) {
    return res.status(400).json({ error: 'sql required' });
  }

  try {
    const { text, values } = toPositional(sql, params);
    const rows = await neon(process.env.DATABASE_URL).query(text, values);
    return res.status(200).json({ rows, rowCount: rows.length });
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
}

// `@nama` -> `$1`, nilai diurutkan sesuai kemunculan pertama.
function toPositional(sql, params) {
  const order = [];
  const text = sql.replace(/@([a-zA-Z_][a-zA-Z0-9_]*)/g, (_, name) => {
    let i = order.indexOf(name);
    if (i === -1) {
      order.push(name);
      i = order.length - 1;
    }
    return `$${i + 1}`;
  });
  return { text, values: order.map((n) => params[n] ?? null) };
}
