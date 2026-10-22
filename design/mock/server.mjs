// Mock backend buat preview UI tanpa DB (design work only, tidak ikut deploy).
// Jalankan: node design/mock/server.mjs  → http://localhost:8099
import { createServer } from 'node:http';
import { existsSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = fileURLToPath(new URL('../../build/preview/', import.meta.url));
const BROKEN_FLAG = fileURLToPath(new URL('./.broken', import.meta.url));
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
const today = new Date(now);
const period = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}`;

// ---- Tim & anggota ----
const teamNames = ['Tim A', 'Tim B', 'Tim C', 'Tim D'];
const teams = teamNames.map((name, i) => ({ id: i + 1, name }));

const roster = [
  ['Rizky Pratama', 'Striker', 9], ['Bagas Saputra', 'Gelandang', 8],
  ['Dimas Anggara', 'Bek', 4], ['Fajar Nugroho', 'Kiper', 1],
  ['Hendra Wijaya', 'Gelandang', 10], ['Ilham Maulana', 'Striker', 7],
  ['Joko Susilo', 'Bek', 5], ['Kevin Ardian', 'Sayap', 11],
  ['Lukman Hakim', 'Gelandang', 6], ['M. Reza', 'Bek', 3],
  ['Naufal Zaki', 'Sayap', 17], ['Oki Setiawan', 'Kiper', 12],
  ['Putra Aditya', 'Striker', 19], ['Rangga Yudha', 'Gelandang', 14],
  ['Sandi Permana', 'Bek', 2], ['Tegar Firmansyah', 'Sayap', 21],
  ['Umar Faruq', 'Kiper', 30], ['Vino Bastian', 'Bek', 13],
  ['Wahyu Hidayat', 'Gelandang', 18], ['Yoga Pratama', 'Striker', 22],
  ['Zaki Ramadhan', 'Bek', 15], ['Arif Setiawan', 'Sayap', 16],
  ['Bayu Nugraha', 'Gelandang', 20], ['Candra Wijaya', 'Kiper', 31],
  ['Dedi Kurniawan', 'Bek', 23], ['Eko Prasetyo', 'Striker', 24],
  ['Farhan Maulana', 'Gelandang', 25], ['Gilang Ramadhan', 'Bek', 26],
  ['Hafiz Alfarizi', 'Sayap', 27], ['Iqbal Fauzi', 'Kiper', 28],
  ['Jefri Kurnia', 'Bek', 29], ['Krisna Bayu', 'Gelandang', 32],
];
const members = roster.map(([name, position, jersey], i) => ({
  id: i + 1, name, position, jersey,
  phone: `0812${String(3456_0000 + i * 137)}`,
  active: i !== 31,
  joined_at: iso(day * (200 - i * 4)),
}));
const team_players = members
  .filter((m) => m.active)
  .map((m) => ({ team_id: Math.floor((m.id - 1) / 8) + 1, member_id: m.id }));

const teamName = (id) => teams.find((t) => t.id === id)?.name ?? '—';

// ---- Laga internal ----
const matches = [
  { id: 1, home_team_id: 1, away_team_id: 2, played_at: at(2, 20), venue: 'Lapangan Cimahi', is_home: true, status: 'scheduled', goals_for: 0, goals_against: 0, notes: null },
  { id: 2, home_team_id: 3, away_team_id: 4, played_at: at(0, 20), venue: 'Lapangan Cimahi', is_home: true, status: 'ongoing', goals_for: 1, goals_against: 1, notes: null },
  { id: 3, home_team_id: 1, away_team_id: 3, played_at: at(-6, 20), venue: 'Mini Soccer Arcamanik', is_home: false, status: 'finished', goals_for: 5, goals_against: 3, notes: null },
  { id: 4, home_team_id: 2, away_team_id: 4, played_at: at(-13, 20), venue: 'Lapangan Cimahi', is_home: true, status: 'finished', goals_for: 2, goals_against: 2, notes: null },
  { id: 5, home_team_id: 1, away_team_id: 4, played_at: at(-20, 16), venue: 'Lapangan UPI', is_home: false, status: 'finished', goals_for: 1, goals_against: 4, notes: null },
  { id: 6, home_team_id: 2, away_team_id: 3, played_at: at(-27, 20), venue: 'Lapangan Cimahi', is_home: true, status: 'finished', goals_for: 4, goals_against: 1, notes: null },
];

const events = [
  [3, 1, 12, 'goal'], [3, 5, 25, 'goal'], [3, 9, 33, 'assist'], [3, 6, 51, 'goal'],
  [3, 1, 60, 'goal'], [3, 11, 77, 'goal'], [3, 19, 40, 'yellow'],
  [4, 9, 18, 'goal'], [4, 14, 66, 'goal'], [4, 26, 22, 'assist'],
  [5, 1, 14, 'goal'], [5, 25, 44, 'goal'], [5, 30, 70, 'goal'],
  [5, 28, 81, 'goal'], [5, 27, 30, 'assist'], [5, 1, 55, 'assist'],
  [6, 9, 8, 'goal'], [6, 12, 17, 'assist'], [6, 9, 62, 'goal'],
  [6, 15, 74, 'goal'], [6, 17, 88, 'goal'],
].map(([match_id, member_id, minute, type], i) => ({
  id: i + 1, match_id, member_id, minute, type,
}));

const sessions = [
  [3, 1, 2, 1], [3, 2, 3, 2], [4, 1, 1, 1], [4, 2, 1, 1], [5, 1, 1, 4], [6, 1, 4, 1],
  [2, 1, 1, 1],
].map(([match_id, session_no, score_home, score_away], i) => ({
  id: i + 1, match_id, session_no, score_home, score_away,
  winner: score_home > score_away ? 'home' : score_home < score_away ? 'away' : 'draw',
  ended_at: iso(day * 5),
}));

const payments = members
  .filter((m) => m.active && m.id <= 26)
  .map((m, i) => ({
    id: i + 1, member_id: m.id, amount: 75000, period,
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
  ['expense', 'wasit', 200000, 4, 'Wasit laga vs Tim C'],
  ['income', 'sponsor', 1500000, 8, 'Sponsor kaos musim ini'],
  ['expense', 'perlengkapan', 480000, 12, 'Bola baru + rompi'],
  ['income', 'lain', 250000, 16, 'Hasil penjualan minuman'],
].map(([kind, category, amount, daysAgo, note], i) => ({
  id: i + 1, kind, category, amount,
  occurred_at: iso(day * daysAgo).slice(0, 10), note,
  // Booking #1 sudah tercatat ke kas; dua lainnya belum — contoh nyata
  // keadaan setelah fitur tautan kas dipasang pada data lama.
  booking_id: i === 0 ? 1 : null,
}));

const users = [
  { id: 1, username: 'admin', role: 'admin', active: true },
  { id: 2, username: 'bendahara', role: 'treasurer', active: true },
  { id: 3, username: 'rizky', role: 'member', active: true },
  { id: 4, username: 'oki', role: 'member', active: false },
];

// ---- Turnamen ----
const tournaments = [
  {
    id: 1, name: 'Turnamen Internal Oktober', venue: 'Lapangan Cimahi',
    starts_at: at(0, 19), match_minutes: 20, break_minutes: 0, groups: 1, status: 'running',
  },
  {
    id: 2, name: 'Turnamen Akhir Pekan', venue: 'Lapangan UPI',
    starts_at: at(6, 19), match_minutes: 15, break_minutes: 5, groups: 2, status: 'draft',
  },
];
const tournament_teams = [
  ...teams.map((t) => ({ tournament_id: 1, team_id: t.id, group_no: 1 })),
  { tournament_id: 2, team_id: 1, group_no: 1 },
  { tournament_id: 2, team_id: 2, group_no: 1 },
  { tournament_id: 2, team_id: 3, group_no: 2 },
  { tournament_id: 2, team_id: 4, group_no: 2 },
];
// [turnamen, grup, babak, urutan, tim tuan rumah, tim tamu, skor kandang, skor tamu]
const tmatches = [
  [1, 1, 1, 1, 1, 2, 3, 1], [1, 1, 1, 2, 3, 4, 1, 1],
  [1, 1, 2, 3, 1, 3, 2, 0], [1, 1, 2, 4, 2, 4, 1, 2],
  [1, 1, 3, 5, 1, 4, null, null], [1, 1, 3, 6, 2, 3, null, null],
  [2, 1, 1, 1, 1, 2, null, null], [2, 2, 1, 2, 3, 4, null, null],
].map(([tournament_id, group_no, round, slot, home_team_id, away_team_id, score_home, score_away], i) => ({
  id: i + 1, tournament_id, group_no, round, slot, home_team_id, away_team_id,
  kickoff: tournament_id === 1
    ? at(0, 19, (slot - 1) * 20)
    : at(6, 19, (slot - 1) * 20),
  score_home, score_away,
  status: score_home == null ? 'scheduled' : 'done',
}));

// Klasemen abadi: semua laga internal yang selesai.
function teamStandings() {
  return teams.map((t) => {
    const done = matches.filter(
      (m) => m.status === 'finished' && (m.home_team_id === t.id || m.away_team_id === t.id),
    );
    let won = 0, drawn = 0, lost = 0, gf = 0, ga = 0;
    for (const m of done) {
      const home = m.home_team_id === t.id;
      const own = home ? m.goals_for : m.goals_against;
      const opp = home ? m.goals_against : m.goals_for;
      gf += own;
      ga += opp;
      if (own > opp) won++;
      else if (own < opp) lost++;
      else drawn++;
    }
    return {
      team_id: t.id, name: t.name, played: done.length, won, drawn, lost,
      goals_for: gf, goals_against: ga, points: won * 3 + drawn,
    };
  }).sort((a, b) =>
    b.points - a.points ||
    (b.goals_for - b.goals_against) - (a.goals_for - a.goals_against) ||
    b.goals_for - a.goals_for ||
    a.name.localeCompare(b.name));
}

const withNames = (m) => ({
  ...m,
  // Tim yang sudah dihapus mengirim nama NULL, sama seperti LEFT JOIN di DB,
  // supaya fallback "Tim dihapus" di app ikut teruji.
  home_name: teams.some((t) => t.id === m.home_team_id) ? teamName(m.home_team_id) : null,
  away_name: teams.some((t) => t.id === m.away_team_id) ? teamName(m.away_team_id) : null,
});

function rowsFor(sql, params = {}) {
  const q = sql.toLowerCase().replace(/\s+/g, ' ');
  const limit = Number(q.match(/limit\s+(\d+)/)?.[1] ?? 100);
  if (/count\(\*\)::int as c from members/.test(q)) return [{ c: members.filter((m) => m.active).length }];
  // Rekap satu tim (`Match.statsForTeam`). WAJIB dicek sebelum rekap klub di
  // bawah: query ini juga memuat `count(*) FILTER (WHERE goals_for =
  // goals_against)`, jadi pola rekap klub ikut cocok dan cabang yang lebih
  // awal akan menangkapnya — akibatnya halaman tim menampilkan "MAIN 0"
  // padahal golnya terisi.
  if (/count\(\*\)::int as played/.test(q)) {
    const done = matches.filter(
      (m) =>
        m.status === 'finished' &&
        !(m.home_team_id == null && m.away_team_id == null) &&
        (m.home_team_id === params.t || m.away_team_id === params.t),
    );
    let won = 0;
    let drawn = 0;
    let lost = 0;
    let gf = 0;
    let ga = 0;
    for (const m of done) {
      const home = m.home_team_id === params.t;
      const own = home ? m.goals_for : m.goals_against;
      const opp = home ? m.goals_against : m.goals_for;
      gf += own;
      ga += opp;
      if (own > opp) won++;
      else if (own === opp) drawn++;
      else lost++;
    }
    return [{ played: done.length, won, drawn, lost, gf, ga }];
  }
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
  if (/from match_events e/.test(q) && /as member_name/.test(q)) {
    return events.filter((e) => params.mid == null || e.match_id === params.mid).map((e) => ({
      ...e, member_name: members.find((m) => m.id === e.member_id)?.name ?? '(mantan anggota)',
    }));
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
  if (/from v_team_standings/.test(q)) return teamStandings();
  if (/from matches/.test(q)) {
    // Laga warisan schema v1 (kedua kolom tim NULL) tidak ditampilkan app;
    // menirunya di sini supaya preview sama dengan produksi.
    let rows = matches.filter((m) => !(m.home_team_id == null && m.away_team_id == null));
    if (/m\.id=@id/.test(q)) {
      return rows.filter((m) => m.id === params.id).map(withNames);
    }
    if (/m\.status='ongoing' or \(m\.status='scheduled'|status in \('scheduled', 'ongoing'\)/.test(q)) {
      // Laga berjalan selalu ikut; laga terjadwal hanya yang belum lewat 3 jam.
      const cutoff = new Date(now - 3 * 60 * 60 * 1000).toISOString();
      rows = rows.filter(
        (m) => m.status === 'ongoing' || (m.status === 'scheduled' && m.played_at >= cutoff),
      );
      rows = [...rows].sort((a, b) => a.played_at.localeCompare(b.played_at)).slice(0, 5);
    } else if (/m\.status='finished'/.test(q)) {
      rows = rows.filter((m) => m.status === 'finished');
      rows = [...rows].sort((a, b) => b.played_at.localeCompare(a.played_at)).slice(0, limit);
    } else if (/m\.home_team_id=@t or m\.away_team_id=@t/.test(q)) {
      rows = rows.filter((m) => m.home_team_id === params.t || m.away_team_id === params.t);
      rows = [...rows].sort((a, b) => b.played_at.localeCompare(a.played_at)).slice(0, limit);
    } else {
      rows = [...rows].sort((a, b) => b.played_at.localeCompare(a.played_at)).slice(0, limit);
    }
    return rows.map(withNames);
  }
  if (/from \( select 1 from payments group by member_id, period having/.test(q)) {
    const groups = new Map();
    for (const p of payments) {
      const k = `${p.member_id}|${p.period}`;
      groups.set(k, (groups.get(k) ?? 0) + 1);
    }
    return [{ n: [...groups.values()].filter((n) => n > 1).length }];
  }
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
    let rows = payments;
    if (params.p != null) rows = rows.filter((p) => p.period === params.p);
    if (params.mid != null) rows = rows.filter((p) => p.member_id === params.mid);
    return rows.map((p) => ({
      ...p, member_name: members.find((m) => m.id === p.member_id)?.name ?? '',
    }));
  }
  if (/from bookings b/.test(q)) {
    let rows = [...bookings]
      .sort((a, b) => b.starts_at.localeCompare(a.starts_at))
      .map((b) => ({
        ...b,
        transaction_id: transactions.find((t) => t.booking_id === b.id)?.id ?? null,
      }));
    // `npm run db:fix` mencari booking berbiaya yang belum masuk kas.
    if (/t\.id is null/.test(q)) rows = rows.filter((b) => b.transaction_id === null);
    if (/b\.cost > 0/.test(q)) rows = rows.filter((b) => b.cost > 0);
    return rows;
  }
  if (/from bookings where status='booked'/.test(q)) {
    return bookings.filter((b) => b.status === 'booked' && b.starts_at >= new Date(now).toISOString());
  }
  if (/from bookings/.test(q)) {
    return [...bookings].sort((a, b) => b.starts_at.localeCompare(a.starts_at));
  }
  if (/from transactions/.test(q)) {
    return params.p == null
      ? transactions
      : transactions.filter((t) => t.occurred_at.startsWith(params.p));
  }
  if (/from announcements/.test(q)) return announcements;
  if (/from users/.test(q)) return users.map(({ id, username, role, active }) => ({ id, username, role, active }));
  if (/from team_players/.test(q)) {
    let rows = team_players;
    if (params.t != null) {
      const ids = tournament_teams.filter((tt) => tt.tournament_id === params.t).map((tt) => tt.team_id);
      rows = rows.filter((tp) => ids.includes(tp.team_id));
    }
    return rows
      .map((tp) => ({ ...tp, ...members.find((m) => m.id === tp.member_id) }))
      .sort((a, b) => a.name.localeCompare(b.name));
  }
  if (/from tournament_teams/.test(q)) {
    if (/select team_id, group_no/.test(q)) {
      return tournament_teams
        .filter((tt) => params.t == null || tt.tournament_id === params.t)
        .sort((a, b) => a.group_no - b.group_no || a.team_id - b.team_id);
    }
    const ids = tournament_teams
      .filter((tt) => params.t == null || tt.tournament_id === params.t);
    return ids
      .map((tt) => ({ ...teams.find((t) => t.id === tt.team_id), group_no: tt.group_no }))
      .sort((a, b) => a.group_no - b.group_no || a.name.localeCompare(b.name));
  }
  if (/from teams/.test(q)) return teams;
  if (/count\(\*\)::int as n from tournament_matches/.test(q) && /status='done'/.test(q)) {
    return [{
      n: tmatches.filter((m) => m.tournament_id === params.t && m.status === 'done').length,
    }];
  }
  if (/^\s*select\s+distinct\s+tournament_id\s+from\s+tournament_matches/.test(q)) {
    const ids = new Set();
    for (const m of tmatches) {
      if (m.home_team_id === params.id || m.away_team_id === params.id) ids.add(m.tournament_id);
    }
    return [...ids].map((tournament_id) => ({ tournament_id }));
  }
  if (/from tournament_matches/.test(q)) {
    return tmatches
      .filter((m) => params.t == null || m.tournament_id === params.t)
      .sort((a, b) => a.tournament_id - b.tournament_id || a.slot - b.slot);
  }
  if (/from tournaments/.test(q)) {
    return [...tournaments].sort((a, b) => b.starts_at.localeCompare(a.starts_at));
  }
  if (/from members/.test(q)) {
    return q.includes('where active')
      ? members.filter((m) => m.active)
      : [...members].sort((a, b) => a.name.localeCompare(b.name));
  }
  return [];
}

const writeCount = (sql) => (/^\s*(insert|update|delete)/i.test(sql) ? 1 : 0);

/// Tulis minimal supaya preview bisa membuktikan alur simpan/hapus.
function applyWrite(sql, params) {
  const q = sql.toLowerCase();
  if (/^\s*insert\s+into\s+transactions/.test(q)) {
    transactions.unshift({
      id: Math.max(0, ...transactions.map((t) => t.id)) + 1,
      kind: params.kind, category: params.category,
      amount: params.amount, occurred_at: params.date, note: params.note,
      booking_id: params.booking ?? null,
    });
    return 1;
  }
  if (/^\s*update\s+transactions/.test(q)) {
    const t = transactions.find((x) => x.id === params.id);
    if (!t) return 0;
    Object.assign(t, {
      kind: params.kind, category: params.category, amount: params.amount,
      occurred_at: params.date, note: params.note ?? null,
    });
    return 1;
  }
  if (/^\s*delete\s+from\s+transactions/.test(q)) {
    const i = transactions.findIndex((t) => t.id === params.id);
    if (i >= 0) transactions.splice(i, 1);
    return i >= 0 ? 1 : 0;
  }
  if (/^\s*insert\s+into\s+payments/.test(q)) {
    payments.unshift({
      id: payments.length + 1, member_id: params.mid, amount: params.amt,
      period: params.period, paid_at: new Date().toISOString(), note: params.note ?? null,
    });
    return 1;
  }
  if (/^\s*delete\s+from\s+payments/.test(q)) {
    const i = payments.findIndex((p) => p.id === params.id);
    if (i >= 0) payments.splice(i, 1);
    return i >= 0 ? 1 : 0;
  }
  if (/^\s*insert\s+into\s+bookings/.test(q)) {
    const id = Math.max(0, ...bookings.map((b) => b.id)) + 1;
    bookings.unshift({
      id, title: params.t, starts_at: params.s,
      duration_min: params.d, cost: params.c, status: 'booked',
    });
    return [{ id }];
  }
  if (/^\s*update\s+bookings/.test(q)) {
    const b = bookings.find((x) => x.id === params.id);
    if (b) b.status = params.s;
    return b ? 1 : 0;
  }
  if (/^\s*delete\s+from\s+bookings/.test(q)) {
    const i = bookings.findIndex((b) => b.id === params.id);
    if (i >= 0) bookings.splice(i, 1);
    for (let j = transactions.length - 1; j >= 0; j--) {
      if (transactions[j].booking_id === params.id) transactions.splice(j, 1);
    }
    return i >= 0 ? 1 : 0;
  }
  if (/^\s*insert\s+into\s+announcements/.test(q)) {
    announcements.unshift({
      id: announcements.length + 1, title: params.t, body: params.b,
      created_at: new Date().toISOString(),
    });
    return 1;
  }
  if (/^\s*update\s+announcements/.test(q)) {
    const a = announcements.find((x) => x.id === params.id);
    if (!a) return 0;
    a.title = params.t;
    a.body = params.b;
    return 1;
  }
  if (/^\s*delete\s+from\s+announcements/.test(q)) {
    const i = announcements.findIndex((a) => a.id === params.id);
    if (i >= 0) announcements.splice(i, 1);
    return i >= 0 ? 1 : 0;
  }
  if (/^\s*update\s+tournaments\s+set\s+status\s*=\s*case/.test(q)) {
    const tour = tournaments.find((t) => t.id === params.t);
    if (!tour) return 0;
    const list = tmatches.filter((m) => m.tournament_id === params.t);
    const done = list.filter((m) => m.status === 'done').length;
    tour.status = list.length === 0
      ? 'draft'
      : done === 0
        ? 'draft'
        : done === list.length
          ? 'done'
          : 'running';
    return 1;
  }
  if (/^\s*update\s+tournament_matches/.test(q)) {
    const m = tmatches.find((x) => x.id === params.id);
    if (!m) return 0;
    if (params.h == null) {
      m.score_home = null;
      m.score_away = null;
      m.status = 'scheduled';
    } else {
      m.score_home = params.h;
      m.score_away = params.a;
      m.status = 'done';
    }
    return 1;
  }
  if (/^\s*insert\s+into\s+team_players/.test(q)) {
    team_players.push({ team_id: params.t, member_id: params.m });
    return 1;
  }
  if (/^\s*delete\s+from\s+team_players/.test(q)) {
    const i = team_players.findIndex(
      (tp) => tp.team_id === params.t && tp.member_id === params.m,
    );
    if (i >= 0) team_players.splice(i, 1);
    return i >= 0 ? 1 : 0;
  }
  if (/^\s*insert\s+into\s+matches/.test(q)) {
    matches.unshift({
      id: Math.max(0, ...matches.map((m) => m.id)) + 1,
      home_team_id: params.h, away_team_id: params.a, played_at: params.t,
      venue: params.v ?? null, is_home: true, status: 'scheduled',
      goals_for: 0, goals_against: 0, notes: null,
    });
    return 1;
  }
  // Tombol "Selesai": skor dikunci, klasemen langsung ikut menghitungnya.
  // Kalau ada sesi, jumlah sesi yang menang — sama seperti `Match.finish`.
  if (/^\s*update\s+matches\s+set\s+status='finished'/.test(q)) {
    const m = matches.find((x) => x.id === params.id);
    if (!m) return 0;
    const own = sessions.filter((s) => s.match_id === params.id);
    m.status = 'finished';
    m.goals_for = own.length ? own.reduce((sum, s) => sum + s.score_home, 0) : params.gf;
    m.goals_against = own.length ? own.reduce((sum, s) => sum + s.score_away, 0) : params.ga;
    return 1;
  }
  // Ubah jadwal laga (tim/tanggal/lokasi).
  if (/^\s*update\s+matches\s+set\s+home_team_id/.test(q)) {
    const m = matches.find((x) => x.id === params.id);
    if (!m) return 0;
    Object.assign(m, {
      home_team_id: params.h, away_team_id: params.a,
      played_at: params.t, venue: params.v ?? null,
    });
    return 1;
  }
  // Mulai laga (0–0) tanpa menunggu sesi.
  if (/^\s*update\s+matches\s+set\s+status='ongoing'/.test(q)) {
    const m = matches.find((x) => x.id === params.id);
    if (!m || m.status !== 'scheduled') return 0;
    m.status = 'ongoing';
    return 1;
  }
  // Buka lagi laga yang sudah dikunci.
  if (/^\s*update\s+matches\s+set\s+status\s*=\s*case\s+when\s+exists/.test(q)) {
    const m = matches.find((x) => x.id === params.id);
    if (!m) return 0;
    const own = sessions.filter((s) => s.match_id === params.id);
    m.status = own.length ? 'ongoing' : 'scheduled';
    return 1;
  }
  // Skor laga = jumlah sesi. Tanpa sesi: laga selesai mempertahankan hasil,
  // laga lain dikosongkan; status bergerak scheduled <-> ongoing mengikuti
  // ada/tidaknya sesi.
  if (/^\s*update\s+matches\s+set\s+goals_for\s*=\s*coalesce/.test(q)) {
    const m = matches.find((x) => x.id === params.m);
    if (!m) return 0;
    const own = sessions.filter((s) => s.match_id === params.m);
    if (own.length) {
      m.goals_for = own.reduce((sum, s) => sum + s.score_home, 0);
      m.goals_against = own.reduce((sum, s) => sum + s.score_away, 0);
    } else if (m.status !== 'finished') {
      m.goals_for = 0;
      m.goals_against = 0;
    }
    if (m.status === 'scheduled' && own.length) m.status = 'ongoing';
    if (m.status === 'ongoing' && !own.length) m.status = 'scheduled';
    return 1;
  }
  if (/^\s*delete\s+from\s+matches/.test(q)) {
    const i = matches.findIndex((m) => m.id === params.id);
    if (i < 0) return 0;
    matches.splice(i, 1);
    for (let j = events.length - 1; j >= 0; j--) if (events[j].match_id === params.id) events.splice(j, 1);
    for (let j = sessions.length - 1; j >= 0; j--) if (sessions[j].match_id === params.id) sessions.splice(j, 1);
    return 1;
  }
  if (/^\s*insert\s+into\s+match_events/.test(q)) {
    events.push({
      id: Math.max(0, ...events.map((e) => e.id)) + 1,
      match_id: params.mid, member_id: params.mem ?? null,
      minute: params.min ?? null, type: params.type,
    });
    return 1;
  }
  if (/^\s*delete\s+from\s+match_events/.test(q)) {
    const i = events.findIndex((e) => e.id === params.id);
    if (i >= 0) events.splice(i, 1);
    return i >= 0 ? 1 : 0;
  }
  if (/^\s*insert\s+into\s+match_sessions/.test(q)) {
    const existing = sessions.find((s) => s.match_id === params.m && s.session_no === params.sn);
    if (existing) {
      existing.score_home = params.h;
      existing.score_away = params.a;
      existing.winner = params.w;
      return 1;
    }
    sessions.push({
      id: Math.max(0, ...sessions.map((s) => s.id)) + 1,
      match_id: params.m, session_no: params.sn,
      score_home: params.h, score_away: params.a, winner: params.w,
      ended_at: new Date().toISOString(),
    });
    return 1;
  }
  if (/^\s*update\s+match_sessions/.test(q)) {
    const s = sessions.find((x) => x.id === params.id);
    if (!s) return 0;
    s.score_home = params.h;
    s.score_away = params.a;
    s.winner = params.w;
    return 1;
  }
  if (/^\s*delete\s+from\s+match_sessions/.test(q)) {
    const i = sessions.findIndex((s) => s.id === params.id);
    if (i >= 0) sessions.splice(i, 1);
    return i >= 0 ? 1 : 0;
  }
  if (/^\s*insert\s+into\s+members/.test(q)) {
    const id = Math.max(0, ...members.map((m) => m.id)) + 1;
    members.push({
      id, name: params.name, phone: params.phone ?? null,
      position: params.position ?? 'Bebas', jersey: params.jersey ?? null,
      active: true, joined_at: new Date().toISOString(),
    });
    return 1;
  }
  if (/^\s*update\s+members/.test(q)) {
    const m = members.find((x) => x.id === params.id);
    if (!m) return 0;
    Object.assign(m, {
      name: params.name, phone: params.phone ?? null,
      position: params.position ?? m.position,
      jersey: params.jersey ?? null,
      active: params.active ?? m.active,
    });
    return 1;
  }
  if (/^\s*delete\s+from\s+members/.test(q)) {
    const i = members.findIndex((m) => m.id === params.id);
    if (i < 0) return 0;
    members.splice(i, 1);
    for (let j = team_players.length - 1; j >= 0; j--) {
      if (team_players[j].member_id === params.id) team_players.splice(j, 1);
    }
    return 1;
  }
  if (/^\s*insert\s+into\s+teams/.test(q)) {
    const id = Math.max(0, ...teams.map((t) => t.id)) + 1;
    teams.push({ id, name: params.n });
    return [{ id }];
  }
  if (/^\s*update\s+teams\s+set\s+name/.test(q)) {
    const t = teams.find((x) => x.id === params.id);
    if (!t) return 0;
    t.name = params.n;
    return 1;
  }
  if (/^\s*delete\s+from\s+teams/.test(q)) {
    const i = teams.findIndex((t) => t.id === params.id);
    if (i < 0) return 0;
    teams.splice(i, 1);
    for (const m of matches) {
      if (m.home_team_id === params.id) m.home_team_id = null;
      if (m.away_team_id === params.id) m.away_team_id = null;
    }
    for (let j = tournament_teams.length - 1; j >= 0; j--) {
      if (tournament_teams[j].team_id === params.id) tournament_teams.splice(j, 1);
    }
    // ON DELETE CASCADE: jadwal turnamen tim ini ikut hilang.
    for (let j = tmatches.length - 1; j >= 0; j--) {
      const m = tmatches[j];
      if (m.home_team_id === params.id || m.away_team_id === params.id) tmatches.splice(j, 1);
    }
    return 1;
  }
  if (/^\s*update\s+tournaments\s+set\s+groups/.test(q)) {
    const tour = tournaments.find((x) => x.id === params.t);
    if (!tour) return 0;
    Object.assign(tour, {
      groups: params.g, match_minutes: params.mm, break_minutes: params.bm,
    });
    return 1;
  }
  if (/^\s*insert\s+into\s+tournaments/.test(q)) {
    const id = Math.max(0, ...tournaments.map((t) => t.id)) + 1;
    tournaments.push({
      id, name: params.n, venue: params.v ?? null, starts_at: params.s,
      match_minutes: params.mm ?? 20, break_minutes: params.bm ?? 0,
      groups: params.g ?? 1, status: 'draft',
    });
    return [{ id }];
  }
  if (/^\s*delete\s+from\s+tournaments/.test(q)) {
    const i = tournaments.findIndex((t) => t.id === params.id);
    if (i < 0) return 0;
    tournaments.splice(i, 1);
    for (const list of [tournament_teams, tmatches]) {
      for (let j = list.length - 1; j >= 0; j--) {
        if (list[j].tournament_id === params.id) list.splice(j, 1);
      }
    }
    return 1;
  }
  if (/^\s*delete\s+from\s+tournament_matches/.test(q)) {
    for (let j = tmatches.length - 1; j >= 0; j--) {
      if (tmatches[j].tournament_id === params.t) tmatches.splice(j, 1);
    }
    return 1;
  }
  if (/^\s*delete\s+from\s+tournament_teams/.test(q)) {
    for (let j = tournament_teams.length - 1; j >= 0; j--) {
      if (tournament_teams[j].tournament_id === params.t) tournament_teams.splice(j, 1);
    }
    return 1;
  }
  if (/^\s*insert\s+into\s+tournament_teams/.test(q)) {
    // Nilai dikirim per tim: @team0..@teamN dan @g0..@gN.
    for (let i = 0; params[`team${i}`] != null; i++) {
      const teamId = params[`team${i}`];
      const exists = tournament_teams.some(
        (tt) => tt.tournament_id === params.t && tt.team_id === teamId,
      );
      if (!exists) {
        tournament_teams.push({
          tournament_id: params.t, team_id: teamId, group_no: params[`g${i}`] ?? 1,
        });
      }
    }
    return 1;
  }
  if (/^\s*insert\s+into\s+tournament_matches/.test(q)) {
    // Satu slot per pasangan @t0..@kN.
    for (let i = 0; params[`s${i}`] != null; i++) {
      tmatches.push({
        id: Math.max(0, ...tmatches.map((m) => m.id)) + 1,
        tournament_id: params[`t${i}`], group_no: params[`g${i}`],
        round: params[`r${i}`], slot: params[`s${i}`],
        home_team_id: params[`h${i}`], away_team_id: params[`a${i}`],
        kickoff: params[`k${i}`], score_home: null, score_away: null,
        status: 'scheduled',
      });
    }
    return 1;
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

const server = createServer(async (req, res) => {
  if (req.method === 'POST' && req.url.startsWith('/api/auth')) {
    const body = await readBody(req);
    if (body.action === 'status') return json(res, 200, { bootstrap: false });
    if (body.action === 'login') {
      return json(res, 200, {
        id: 1, username: body.username || 'admin',
        role: body.username === 'rizky' ? 'member' : 'admin', token: 'mock-token',
      });
    }
    return json(res, 200, { ok: true });
  }
  if (req.method === 'POST' && req.url.startsWith('/api/sql')) {
    const { sql = '', params = {} } = await readBody(req);
    // Berkas `design/mock/.broken` meniru produksi saat view/tabel belum
    // punya izin: query tertentu dibalas 400 seperti Postgres, supaya UI
    // "sebagian data gagal dimuat" bisa diuji tanpa menyentuh Neon.
    //   touch design/mock/.broken   → aktif
    //   rm design/mock/.broken      → normal
    const broken = existsSync(BROKEN_FLAG)
      ? ['v_team_standings', 'tournament_teams']
      : [];
    if (broken.some((name) => sql.toLowerCase().includes(name))) {
      return json(res, 400, { error: 'Query gagal dijalankan' });
    }
    // applyWrite mengembalikan array untuk INSERT ... RETURNING (id baris
    // baru), angka untuk tulis biasa. Tanpa ini form "Tim"/"Turnamen" gagal
    // membaca id dan tidak bisa melanjutkan ke langkah berikutnya.
    const out = applyWrite(sql, params);
    const rows = Array.isArray(out) ? out : rowsFor(sql, params);
    return json(res, 200, { rows, rowCount: Array.isArray(out) ? out.length : out });
  }
  const path = normalize(decodeURIComponent(req.url.split('?')[0]));
  const file = join(ROOT, path === '/' ? 'index.html' : path);
  try {
    const data = await readFile(file);
    res.writeHead(200, { 'content-type': MIME[extname(file)] ?? 'application/octet-stream' });
    res.end(data);
  } catch {
    // Berkas aset (.js/.wasm/.json) yang hilang JANGAN dibalas index.html:
    // browser menerimanya sebagai skrip lalu melempar
    // "SyntaxError: Unexpected token '<'" dan layar jadi hitam tanpa
    // petunjuk. Hanya rute navigasi yang boleh jatuh ke SPA fallback.
    // Cek ini HARUS di cabang luar: kalau ditaruh setelah fallback
    // index.html, ia tidak pernah tercapai selama index.html ada.
    const ext = extname(path).toLowerCase();
    if (ext && ext !== '.html') {
      json(res, 404, { error: `aset tidak ada: ${path}` });
      return;
    }
    try {
      const data = await readFile(join(ROOT, 'index.html'));
      res.writeHead(200, { 'content-type': 'text/html' });
      res.end(data);
    } catch {
      // Penyebab tersering: `build/preview/` belum ada (folder ini tidak
      // masuk git dan hilang setelah `flutter clean`). Balas dengan pesan
      // yang menyebut perintahnya, bukan 404 tanpa petunjuk.
      if (!existsSync(join(ROOT, 'index.html'))) {
        res.writeHead(503, { 'content-type': 'text/plain; charset=utf-8' });
        res.end(
          'build/preview/ belum ada.\n\n' +
            '  npm run preview:build     (flutter build web -t lib/preview_main.dart)\n' +
            '  npm run preview           (server ini)\n',
        );
        return;
      }
      json(res, 404, { error: 'not found' });
    }
  }
}).listen(PORT, () => console.log(`mock: http://localhost:${PORT}`));

// Port sudah dipakai (biasanya instance lama yang belum dimatikan). Berhenti
// dengan pesan yang menyebut PID-nya, bukan stack trace EADDRINUSE — proses
// pembungkus yang gagal start adalah penyebab "exit 127" berulang di
// supervisor.
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(
      `port ${PORT} sudah dipakai. Matikan instance lama dulu:\n` +
        `  netstat -ano | findstr :${PORT}\n` +
        `  taskkill /F /PID <pid>`,
    );
    process.exit(0);
  }
  throw err;
});
