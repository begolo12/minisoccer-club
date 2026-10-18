// Mock backend buat preview UI tanpa DB (design work only, tidak ikut deploy).
// Jalankan: node design/mock/server.mjs  → http://localhost:8099
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../../build/preview/', import.meta.url));
const PORT = 8099;
const now = Date.now();
const iso = (msAgo) => new Date(now - msAgo).toISOString();
const day = 86_400_000;
// Jam tetap supaya screenshot tidak menampilkan jadwal jam 01.29.
const at = (daysFromNow, hour, minute = 0) => {
  const d = new Date(now + daysFromNow * day);
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
};

const members = [
  ['Rizky Pratama', 'Striker', 9], ['Bagas Saputra', 'Gelandang', 8],
  ['Dimas Anggara', 'Bek', 4], ['Fajar Nugroho', 'Kiper', 1],
  ['Hendra Wijaya', 'Gelandang', 10], ['Ilham Maulana', 'Striker', 7],
  ['Joko Susilo', 'Bek', 5], ['Kevin Ardian', 'Sayap', 11],
  ['Lukman Hakim', 'Gelandang', 6], ['M. Reza', 'Bek', 3],
  ['Naufal Zaki', 'Sayap', 17], ['Oki Setiawan', 'Kiper', 12],
  ['Putra Aditya', 'Striker', 19], ['Rangga Yudha', 'Gelandang', 14],
].map(([name, position, jersey], i) => ({
  id: i + 1, name, position, jersey,
  phone: `0812${String(3456_0000 + i * 137)}`, active: i !== 13,
  joined_at: iso(day * (200 - i * 5)),
}));

const matches = [
  { id: 1, opponent: 'Garuda FC', played_at: at(2, 20), venue: 'Lapangan Cimahi', is_home: true, status: 'scheduled', goals_for: 0, goals_against: 0, notes: null },
  { id: 6, opponent: 'Cimahi United', played_at: at(0, 20), venue: 'Lapangan Cimahi', is_home: true, status: 'ongoing', goals_for: 1, goals_against: 1, notes: null },
  { id: 2, opponent: 'Putra Mandiri', played_at: at(-6, 20), venue: 'Mini Soccer Arcamanik', is_home: false, status: 'finished', goals_for: 5, goals_against: 3, notes: null },
  { id: 3, opponent: 'Bintang Timur', played_at: at(-13, 20), venue: 'Lapangan Cimahi', is_home: true, status: 'finished', goals_for: 2, goals_against: 2, notes: null },
  { id: 4, opponent: 'SSB Jayakarta', played_at: at(-20, 16), venue: 'Lapangan UPI', is_home: false, status: 'finished', goals_for: 1, goals_against: 4, notes: null },
  { id: 5, opponent: 'Anak Kolong FC', played_at: at(-27, 20), venue: 'Lapangan Cimahi', is_home: true, status: 'finished', goals_for: 4, goals_against: 1, notes: null },
];

const events = [
  [2, 1, 12, 'goal'], [2, 5, 25, 'goal'], [2, 9, 33, 'assist'], [2, 6, 51, 'goal'],
  [2, 1, 60, 'goal'], [2, 11, 77, 'goal'], [2, 3, 40, 'yellow'],
  [3, 6, 18, 'goal'], [3, 14, 66, 'goal'], [3, 10, 22, 'assist'],
  [4, 13, 9, 'goal'], [5, 1, 14, 'goal'], [5, 1, 44, 'goal'], [5, 9, 70, 'goal'],
  [5, 5, 81, 'goal'], [5, 5, 30, 'assist'], [5, 1, 55, 'assist'],
  [6, 1, 8, 'goal'], [6, 6, 17, 'assist'],
].map(([match_id, member_id, minute, type], i) => ({
  id: i + 1, match_id, member_id, minute, type,
}));

const sessions = [
  [2, 1, 2, 1], [2, 2, 3, 2], [3, 1, 1, 1], [3, 2, 1, 1], [4, 1, 1, 4], [5, 1, 4, 1],
  [6, 1, 1, 1],
].map(([match_id, session_no, score_home, score_away], i) => ({
  id: i + 1, match_id, session_no, score_home, score_away,
  winner: score_home > score_away ? 'home' : score_home < score_away ? 'away' : 'draw',
  ended_at: iso(day * 5),
}));

const payments = [
  [1, 75000], [2, 75000], [3, 75000], [4, 50000], [5, 75000], [6, 75000],
  [7, 75000], [9, 75000], [10, 50000], [11, 75000], [12, 75000],
].map(([member_id, amount], i) => ({
  id: i + 1, member_id, amount, period: '2026-10',
  paid_at: iso(day * (2 + i)), note: null,
}));

const bookings = [
  ['Sewa lapangan — latihan rutin', at(1, 20), 90, 350000, 'booked'],
  ['Sewa lapangan — uji coba', at(4, 19, 30), 120, 450000, 'booked'],
  ['Sewa lapangan — latihan rutin', at(-5, 20), 90, 350000, 'done'],
].map(([title, starts_at, duration_min, cost, status], i) => ({
  id: i + 1, title, starts_at, duration_min, cost, status,
}));

const announcements = [
  ['Latihan pindah ke jam 20.00', 'Mulai minggu ini latihan rutin maju satu jam. Jangan lupa bawa rompi dan air minum sendiri.'],
  ['Iuran Oktober sudah dibuka', 'Iuran bulan ini Rp 75.000. Bisa transfer ke bendahara atau bayar langsung setelah latihan.'],
].map(([title, body], i) => ({
  id: i + 1, title, body, created_at: iso(day * (3 + i * 4)),
}));

const transactions = [
  ['expense', 'sewa', 350000, 2, 'Sewa lapangan latihan rutin'],
  ['expense', 'wasit', 200000, 4, 'Wasit laga vs Putra Mandiri'],
  ['income', 'sponsor', 1500000, 8, 'Sponsor kaos musim ini'],
  ['expense', 'perlengkapan', 480000, 12, 'Bola baru + rompi'],
  ['income', 'lain', 250000, 16, 'Hasil penjualan minuman'],
].map(([kind, category, amount, daysAgo, note], i) => ({
  id: i + 1, kind, category, amount, occurred_at: iso(day * daysAgo).slice(0, 10), note,
}));

const users = [
  { id: 1, username: 'admin', role: 'admin', active: true },
  { id: 2, username: 'bendahara', role: 'treasurer', active: true },
  { id: 3, username: 'rizky', role: 'member', active: true },
  { id: 4, username: 'oki', role: 'member', active: false },
];

const tournaments = [{
  id: 1, name: 'Turnamen Internal Oktober', venue: 'Lapangan Cimahi',
  starts_at: at(0, 19), match_minutes: 20, break_minutes: 0, status: 'running',
}];
const teams = ['Tim A', 'Tim B', 'Tim C', 'Tim D'].map((name, i) => ({
  id: i + 1, tournament_id: 1, name,
}));
const team_players = [];
members.filter((m) => m.active).forEach((m, i) => {
  const round = Math.floor(i / 4);
  const idx = round % 2 === 0 ? i % 4 : 3 - (i % 4);
  team_players.push({ team_id: idx + 1, member_id: m.id });
});
const tmatches = [
  [1, 1, 1, 1, 2, 2, 1], [1, 1, 2, 3, 4, 1, 1], [1, 2, 3, 1, 3, 3, 0],
  [1, 2, 4, 2, 4, 1, 2], [1, 3, 5, 1, 4, null, null], [1, 3, 6, 2, 3, null, null],
].map(([tournament_id, round, slot, home_team_id, away_team_id, score_home, score_away], i) => ({
  id: i + 1, tournament_id, round, slot, home_team_id, away_team_id,
  kickoff: at(0, 19, i * 20), score_home, score_away,
  status: score_home == null ? 'scheduled' : 'done',
}));

function rowsFor(sql, params = {}) {
  const q = sql.toLowerCase();
  const limit = Number(q.match(/limit\s+(\d+)/)?.[1] ?? 100);
  if (/count\(\*\)::int as c from members/.test(q)) return [{ c: members.filter((m) => m.active).length }];
  if (/count\(\*\) filter \(where goals_for/.test(q)) {
    const done = matches.filter((m) => m.status === 'finished');
    return [{
      w: done.filter((m) => m.goals_for > m.goals_against).length,
      d: done.filter((m) => m.goals_for === m.goals_against).length,
      l: done.filter((m) => m.goals_for < m.goals_against).length,
      gf: done.reduce((s, m) => s + m.goals_for, 0),
      ga: done.reduce((s, m) => s + m.goals_against, 0),
    }];
  }
  if (/from match_events e left join members/.test(q) || /group by 1 having/.test(q)) {
    return members.map((m) => ({
      name: m.name,
      goals: events.filter((e) => e.member_id === m.id && e.type === 'goal').length,
      assists: events.filter((e) => e.member_id === m.id && e.type === 'assist').length,
    })).filter((r) => r.goals > 0).sort((a, b) => b.goals - a.goals || b.assists - a.assists);
  }
  if (/from match_events e/.test(q)) {
    return events.filter((e) => params.mid == null || e.match_id === params.mid).map((e) => ({
      ...e, member_name: members.find((m) => m.id === e.member_id)?.name ?? '(mantan anggota)',
    }));
  }
  if (/from match_sessions/.test(q)) {
    return sessions.filter((x) => params.m == null || x.match_id === params.m);
  }
  if (/from matches where status='scheduled'/.test(q)) {
    return matches.filter((m) => m.status === 'scheduled').sort((a, b) => a.played_at.localeCompare(b.played_at));
  }
  if (/from matches where status in \('scheduled', 'ongoing'\)/.test(q)) {
    return matches
      .filter((m) => m.status === 'scheduled' || m.status === 'ongoing')
      .sort((a, b) => a.played_at.localeCompare(b.played_at))
      .slice(0, limit);
  }
  if (/from matches where status='finished'/.test(q)) {
    return matches
      .filter((m) => m.status === 'finished')
      .sort((a, b) => b.played_at.localeCompare(a.played_at))
      .slice(0, limit);
  }
  if (/from matches/.test(q)) return [...matches].sort((a, b) => b.played_at.localeCompare(a.played_at)).slice(0, limit);
  if (/from payments/.test(q)) {
    if (/group by amount/.test(q)) {
      const counts = new Map();
      for (const p of payments) counts.set(p.amount, (counts.get(p.amount) ?? 0) + 1);
      const [amount, n] = [...counts.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0])[0] ?? [0, 0];
      return [{ amount, n }];
    }
    if (/coalesce\(sum\(amount\)/.test(q)) {
      return [{ total: payments.reduce((s, p) => s + p.amount, 0) }];
    }
    const rows = params.p == null ? payments : payments.filter((p) => p.period === params.p);
    return rows.map((p) => ({
      ...p, member_name: members.find((m) => m.id === p.member_id)?.name ?? '',
    }));
  }
  if (/from bookings where status='booked'/.test(q)) {
    return bookings.filter((b) => b.status === 'booked');
  }
  if (/from bookings/.test(q)) return bookings;
  if (/from transactions/.test(q)) {
    return params.p == null
      ? transactions
      : transactions.filter((t) => t.occurred_at.startsWith(params.p));
  }
  if (/from announcements/.test(q)) return announcements;
  if (/from users/.test(q)) return users.map(({ id, username, role, active }) => ({ id, username, role, active }));
  if (/from team_players/.test(q)) {
    return team_players.map((tp) => ({
      ...tp, ...members.find((m) => m.id === tp.member_id),
    }));
  }
  if (/from teams/.test(q)) return teams;
  if (/from tournament_matches/.test(q)) return tmatches;
  if (/from tournaments/.test(q)) return tournaments;
  if (/from members/.test(q)) {
    return q.includes('where active') ? members.filter((m) => m.active) : [...members].sort((a, b) => a.name.localeCompare(b.name));
  }
  return [];
}

const writeCount = (sql) => (/^\s*(insert|update|delete)/i.test(sql) ? 1 : 0);

/// Tulis minimal supaya preview bisa membuktikan alur simpan/hapus.
/// Hanya tabel transaksi; sisanya tetap read-only.
function applyWrite(sql, params) {
  if (/^\s*insert\s+into\s+transactions/i.test(sql)) {
    transactions.unshift({
      id: transactions.length + 1,
      kind: params.kind,
      category: params.category,
      amount: params.amount,
      occurred_at: params.date,
      note: params.note,
    });
    return 1;
  }
  if (/^\s*delete\s+from\s+transactions/i.test(sql)) {
    const i = transactions.findIndex((t) => t.id === params.id);
    if (i >= 0) transactions.splice(i, 1);
    return i >= 0 ? 1 : 0;
  }
  return writeCount(sql);
}

const json = (res, code, body) => {
  res.writeHead(code, { 'content-type': 'application/json', 'cache-control': 'no-store' });
  res.end(JSON.stringify(body));
};

const readBody = (req) =>
  new Promise((resolve) => {
    let raw = '';
    req.on('data', (c) => (raw += c));
    req.on('end', () => {
      try { resolve(JSON.parse(raw || '{}')); } catch { resolve({}); }
    });
  });

const MIME = {
  '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json',
  '.png': 'image/png', '.wasm': 'application/wasm', '.css': 'text/css',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff2': 'font/woff2', '.svg': 'image/svg+xml',
};

createServer(async (req, res) => {
  if (req.method === 'POST' && req.url.startsWith('/api/auth')) {
    const body = await readBody(req);
    if (body.action === 'status') return json(res, 200, { bootstrap: false });
    if (body.action === 'login') {
      return json(res, 200, { id: 1, username: body.username || 'admin', role: 'admin', token: 'mock-token' });
    }
    return json(res, 200, { ok: true });
  }
  if (req.method === 'POST' && req.url.startsWith('/api/sql')) {
    const { sql = '', params = {} } = await readBody(req);
    return json(res, 200, { rows: rowsFor(sql, params), rowCount: applyWrite(sql, params) });
  }
  const path = normalize(decodeURIComponent(req.url.split('?')[0]));
  const file = join(ROOT, path === '/' ? 'index.html' : path);
  try {
    const data = await readFile(file);
    res.writeHead(200, { 'content-type': MIME[extname(file)] ?? 'application/octet-stream' });
    res.end(data);
  } catch {
    try {
      const data = await readFile(join(ROOT, 'index.html'));
      res.writeHead(200, { 'content-type': 'text/html' });
      res.end(data);
    } catch {
      json(res, 404, { error: 'not found' });
    }
  }
}).listen(PORT, () => console.log(`mock: http://localhost:${PORT}`));
