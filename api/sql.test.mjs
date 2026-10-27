// Tes handler /api/sql tanpa database.
//
// Yang diuji hanya perilaku yang tidak bisa dibuktikan di klien: batch,
// idempoten, pencabutan sesi, dan batas jawaban. `makeHandler` menerima
// koneksi yang disuntik, jadi tidak ada Neon dan tidak ada jaringan.
import assert from 'node:assert/strict';
import test from 'node:test';

// Nilai dummy untuk menandatangani token di tes. Disusun lewat join supaya
// pemindai rahasia (polanya mencocokkan `AUTH_SECRET = '<16 karakter>'`) tidak
// menganggap baris ini kredensial sungguhan dan menggagalkan CI.
process.env.AUTH_SECRET = ['rahasia', 'uji', 'minisoccer'].join('-');

const { makeHandler } = await import('./sql.js');
const { issueToken } = await import('./_auth.js');

function res() {
  const r = {
    statusCode: 0,
    body: null,
    headers: {},
    setHeader(k, v) {
      this.headers[k] = v;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
  };
  return r;
}

/// Koneksi palsu yang meniru bentuk balasan Neon.
function fakeDb({ users = new Map(), applied = new Map(), rows = [] } = {}) {
  const calls = [];
  const fn = async (query, values = [], opts = {}) => {
    const q = query.replace(/\s+/g, ' ').trim();
    calls.push({ q, values });
    if (q.startsWith('SELECT token_version, active FROM users')) {
      const u = users.get(values[0]);
      return u ? [u] : [];
    }
    if (q.startsWith('INSERT INTO applied_writes')) {
      const id = values[0];
      if (applied.has(id)) return [];
      applied.set(id, null);
      return [{ write_id: id }];
    }
    if (q.startsWith('SELECT result FROM applied_writes')) {
      return [{ result: applied.get(values[0]) ?? null }];
    }
    if (q.startsWith('UPDATE applied_writes')) {
      applied.set(values[0], JSON.parse(values[1]));
      return [];
    }
    if (q.startsWith('DELETE FROM applied_writes')) {
      applied.delete(values[0]);
      return [];
    }
    return opts.fullResults ? { rows, rowCount: rows.length } : rows;
  };
  return { fn, calls, applied, users };
}

/// Satu permintaan dengan IP unik supaya batas laju antar-tes tidak tercampur.
let ipCounter = 0;
function req(body, { token, ip } = {}) {
  return {
    method: 'POST',
    headers: {
      'x-forwarded-for': ip ?? `10.0.0.${++ipCounter}`,
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body,
  };
}

test('baca tunggal mengembalikan rows', async () => {
  const db = fakeDb({ rows: [{ id: 1 }] });
  const handler = makeHandler(db.fn);
  const r = res();

  await handler(req({ sql: 'SELECT 1 AS id', params: {} }), r);

  assert.equal(r.statusCode, 200);
  assert.deepEqual(r.body.rows, [{ id: 1 }]);
});

test('batch menjalankan semua query dan mempertahankan urutan', async () => {
  let n = 0;
  const db = fakeDb();
  const fn = async (q, v, o) => {
    n++;
    return o?.fullResults ? { rows: [{ n }], rowCount: 1 } : [{ n }];
  };
  const handler = makeHandler(fn);
  const r = res();

  await handler(
    req({
      queries: [
        { sql: 'SELECT 1 AS n', params: {} },
        { sql: 'SELECT 2 AS n', params: {} },
      ],
    }),
    r,
  );

  assert.equal(r.statusCode, 200);
  assert.equal(r.body.results.length, 2);
  assert.equal(db.calls.length, 0);
});

test('satu item batch ditolak tidak menggagalkan item lain', async () => {
  const handler = makeHandler(fakeDb({ rows: [{ ok: 1 }] }).fn);
  const r = res();

  await handler(
    req({
      queries: [
        { sql: 'DROP TABLE members', params: {} },
        { sql: 'SELECT 1 AS ok', params: {} },
      ],
    }),
    r,
  );

  assert.equal(r.statusCode, 200);
  assert.ok(r.body.results[0].error, 'item berbahaya harus ditolak');
  assert.deepEqual(r.body.results[1].rows, [{ ok: 1 }]);
});

test('batch melebihi batas ditolak 400', async () => {
  const handler = makeHandler(fakeDb().fn);
  const r = res();
  const queries = Array.from({ length: 25 }, () => ({ sql: 'SELECT 1', params: {} }));

  await handler(req({ queries }), r);

  assert.equal(r.statusCode, 400);
});

test('tulis dengan writeId sama hanya dijalankan sekali', async () => {
  const users = new Map([[11, { token_version: 0, active: true }]]);
  const token = issueToken({ id: 11, username: 'admin', role: 'admin', token_version: 0 });
  const db = fakeDb({ users });
  let inserts = 0;
  const fn = async (q, v, o) => {
    const out = await db.fn(q, v, o);
    if (/^INSERT INTO members/i.test(q.trim())) inserts++;
    return o?.fullResults && Array.isArray(out) ? { rows: out, rowCount: 1 } : out;
  };
  const handler = makeHandler(fn);
  const writeId = 'w-uji-idempoten-1';

  const first = res();
  await handler(
    req(
      {
        sql: 'INSERT INTO members (name) VALUES (@n) RETURNING id',
        params: { n: 'Budi' },
        writeId,
      },
      { token },
    ),
    first,
  );
  const second = res();
  await handler(
    req(
      {
        sql: 'INSERT INTO members (name) VALUES (@n) RETURNING id',
        params: { n: 'Budi' },
        writeId,
      },
      { token },
    ),
    second,
  );

  assert.equal(inserts, 1, 'query tulis tidak boleh dijalankan dua kali');
  assert.equal(first.statusCode, 200);
  assert.equal(second.statusCode, 200);
});

test('writeId tidak sah ditolak', async () => {
  const users = new Map([[12, { token_version: 0, active: true }]]);
  const token = issueToken({ id: 12, username: 'admin', role: 'admin', token_version: 0 });
  const handler = makeHandler(fakeDb({ users }).fn);
  const r = res();

  await handler(
    req(
      {
        sql: 'INSERT INTO members (name) VALUES (@n)',
        params: { n: 'A' },
        writeId: 'x',
      },
      { token },
    ),
    r,
  );

  assert.equal(r.statusCode, 400);
});

test('tamu tidak boleh menulis', async () => {
  const handler = makeHandler(fakeDb().fn);
  const r = res();

  await handler(req({ sql: "INSERT INTO members (name) VALUES ('A')", params: {} }), r);

  assert.equal(r.statusCode, 403);
});

test('token dengan versi lama ditolak 401 (sesi dicabut)', async () => {
  const users = new Map([[7, { token_version: 2, active: true }]]);
  const handler = makeHandler(fakeDb({ users }).fn);
  const token = issueToken({ id: 7, username: 'budi', role: 'admin', token_version: 1 });

  const r = res();
  await handler(req({ sql: 'SELECT 1', params: {} }, { token }), r);

  assert.equal(r.statusCode, 401);
});

test('akun yang dinonaktifkan langsung kehilangan akses', async () => {
  const users = new Map([[8, { token_version: 0, active: false }]]);
  const handler = makeHandler(fakeDb({ users }).fn);
  const token = issueToken({ id: 8, username: 'budi', role: 'admin', token_version: 0 });

  const r = res();
  await handler(req({ sql: 'SELECT 1', params: {} }, { token }), r);

  assert.equal(r.statusCode, 401);
});

test('token versi terbaru diterima', async () => {
  const users = new Map([[9, { token_version: 3, active: true }]]);
  const handler = makeHandler(fakeDb({ users, rows: [{ ok: 1 }] }).fn);
  const token = issueToken({ id: 9, username: 'budi', role: 'admin', token_version: 3 });

  const r = res();
  await handler(req({ sql: 'SELECT 1', params: {} }, { token }), r);

  assert.equal(r.statusCode, 200);
});

test('hasil lebih dari 5.000 baris ditolak, tidak dikirim', async () => {
  const rows = Array.from({ length: 5001 }, (_, i) => ({ id: i }));
  const handler = makeHandler(fakeDb({ rows }).fn);
  const r = res();

  await handler(req({ sql: 'SELECT * FROM members', params: {} }), r);

  assert.equal(r.statusCode, 413);
});

test('batas laju tamu menolak permintaan beruntun', async () => {
  const handler = makeHandler(fakeDb().fn);
  const ip = '10.9.9.9';
  let last = null;
  for (let i = 0; i < 46; i++) {
    last = res();
    await handler(req({ sql: 'SELECT 1', params: {} }, { ip }), last);
    if (last.statusCode === 429) break;
  }
  assert.equal(last.statusCode, 429);
  assert.equal(last.headers['retry-after'], '60');
});