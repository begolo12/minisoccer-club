// Koneksi Neon lewat endpoint HTTP, dengan IPv4 dipaksa.
//
// Kenapa tidak `@neondatabase/serverless`? Di sebagian jaringan, DNS
// mengembalikan alamat IPv6 duluan dan `fetch` Node gagal connect
// (ETIMEDOUT). Endpoint HTTP Neon sama saja, jadi kita resolve A record
// sendiri lalu sambung ke IP itu.
import { request } from 'node:https';
import { resolve4 } from 'node:dns/promises';

/**
 * Runner untuk satu connection string.
 * @param {string} conn postgresql://... (owner atau app_web)
 * @returns {(query: string, params?: unknown[]) => Promise<{rows: any[], rowCount: number}>}
 */
export async function makeRunner(conn) {
  if (!conn) throw new Error('Connection string kosong. Set DATABASE_URL dulu.');

  const host = new URL(conn).hostname;
  const [ip] = await resolve4(host);
  const lookup = (_h, o, cb) =>
    o.all ? cb(null, [{ address: ip, family: 4 }]) : cb(null, ip, 4);

  return (query, params = []) => {
    const body = JSON.stringify({ query, params });
    return new Promise((resolve, reject) => {
      const req = request(
        {
          host,
          servername: host,
          lookup,
          family: 4,
          path: '/sql',
          method: 'POST',
          timeout: 30000,
          headers: {
            'content-type': 'application/json',
            'content-length': Buffer.byteLength(body),
            'neon-connection-string': conn,
            'neon-pooler': 'true',
          },
        },
        (res) => {
          let raw = '';
          res.on('data', (d) => (raw += d));
          res.on('end', () => {
            let json = {};
            try {
              json = JSON.parse(raw);
            } catch {
              return reject(new Error(`HTTP ${res.statusCode}: ${raw.slice(0, 200)}`));
            }
            if (res.statusCode !== 200) return reject(new Error(json.message || raw));
            resolve(json);
          });
        },
      );
      req.on('timeout', () => req.destroy(new Error('timeout')));
      req.on('error', reject);
      req.end(body);
    });
  };
}

/**
 * Pecah schema.sql jadi statement, sadar string, komentar, dan dollar-quote.
 *
 * Pemisah `;` naif akan memotong blok `DO $$ ... ; ... $$` dan literal
 * bertanda kutip — schema memakai keduanya (index bersyarat, default teks).
 */
export function splitStatements(raw) {
  const out = [];
  let buf = '';
  let i = 0;

  const flush = () => {
    const s = buf.trim();
    if (s) out.push(s);
    buf = '';
  };

  while (i < raw.length) {
    const c = raw[i];

    // -- komentar baris
    if (c === '-' && raw[i + 1] === '-') {
      const nl = raw.indexOf('\n', i);
      i = nl === -1 ? raw.length : nl + 1;
      continue;
    }

    // /* komentar blok */
    if (c === '/' && raw[i + 1] === '*') {
      const end = raw.indexOf('*/', i + 2);
      i = end === -1 ? raw.length : end + 2;
      continue;
    }

    // 'string'
    if (c === "'") {
      let j = i + 1;
      while (j < raw.length) {
        if (raw[j] === "'") {
          if (raw[j + 1] === "'") {
            j += 2;
            continue;
          }
          j++;
          break;
        }
        j++;
      }
      buf += raw.slice(i, j);
      i = j;
      continue;
    }

    // "identifier"
    if (c === '"') {
      let j = i + 1;
      while (j < raw.length) {
        if (raw[j] === '"') {
          if (raw[j + 1] === '"') {
            j += 2;
            continue;
          }
          j++;
          break;
        }
        j++;
      }
      buf += raw.slice(i, j);
      i = j;
      continue;
    }

    // $tag$ ... $tag$
    if (c === '$') {
      const m = /^\$[A-Za-z_]*\$/.exec(raw.slice(i));
      if (m) {
        const tag = m[0];
        const end = raw.indexOf(tag, i + tag.length);
        const stop = end === -1 ? raw.length : end + tag.length;
        buf += raw.slice(i, stop);
        i = stop;
        continue;
      }
    }

    if (c === ';') {
      flush();
      i++;
      continue;
    }

    buf += c;
    i++;
  }

  flush();
  return out;
}
