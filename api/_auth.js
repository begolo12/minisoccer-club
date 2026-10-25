import { createHmac, timingSafeEqual } from 'node:crypto';

// Token sesi: base64url(payload).base64url(hmac) — stateless, tanpa tabel sesi.
// Secret dari env AUTH_SECRET (wajib di produksi).
const SECRET = process.env.AUTH_SECRET || '';
export const TTL_SECONDS = 60 * 60 * 12; // 12 jam

const b64 = (s) => Buffer.from(s).toString('base64url');

function sign(payload) {
  return createHmac('sha256', SECRET).update(payload).digest('base64url');
}

export function issueToken({ id, username, role, member_id }) {
  if (!SECRET) throw new Error('AUTH_SECRET belum diset di server');
  const payload = b64(
    JSON.stringify({
      id,
      u: username,
      r: role,
      // Id anggota yang tertaut dengan akun ini (null untuk admin/bendahara
      // yang bukan anggota klub). Dipakai supaya role anggota bisa melihat
      // "saya" — iuran dan patungan miliknya sendiri — tanpa perlu mencari
      // namanya di daftar anggota.
      m: member_id ?? null,
      exp: Math.floor(Date.now() / 1000) + TTL_SECONDS,
    }),
  );
  return `${payload}.${sign(payload)}`;
}

/// Return payload kalau valid, null kalau tidak.
export function verifyToken(token) {
  if (!SECRET || typeof token !== 'string') return null;
  const [payload, mac] = token.split('.');
  if (!payload || !mac) return null;

  const expected = sign(payload);
  const a = Buffer.from(mac);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a, b)) return null;

  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'));
    if (!data.exp || data.exp < Math.floor(Date.now() / 1000)) return null;
    return data;
  } catch {
    return null;
  }
}

export function bearer(req) {
  const h = req.headers['authorization'] || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}
