// Pemindai rahasia: memastikan tidak ada kredensial yang ikut ter-commit.
//
// Repo ini PUBLIK. Satu connection string Neon atau satu token yang lolos ke
// sebuah commit langsung menjadi milik semua orang — dan riwayat git tetap
// menyimpannya walau filenya dihapus kemudian. Karena itu pemeriksaan ini
// dijalankan otomatis (CI + `npm run check:secrets`), bukan saat ingat saja.
//
// Dua lapis:
//   1. Pohon kerja — file yang TERLACAK git (bukan semua file di disk:
//      `.env` memang ada di mesin pengembang dan tidak pernah ikut).
//   2. Riwayat — setiap blob yang pernah di-commit. Kredensial yang dihapus
//      di commit berikutnya masih bisa dibaca dari `git show`, jadi
//      pemeriksaan pohon kerja saja tidak cukup.
//
// Yang dicetak HANYA lokasi dan pola yang cocok, dengan nilainya disamarkan.
// Pemindai yang mencetak rahasianya sendiri akan mengubah satu kebocoran
// menjadi dua (log CI bisa dibaca siapa pun yang punya akses repo).
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

/// Placeholder yang sengaja ada di dokumentasi dan `.env.example`.
const PLACEHOLDER = [
  'xxx', 'cool-name', 'user:pass', 'user:password', 'ganti-dengan',
  '<', 'contoh', 'example', 'your-', 'changeme', 'placeholder',
];

const RULES = [
  {
    name: 'connection string Postgres',
    // Password dan host nyata. Placeholder disaring setelah cocok, karena
    // polanya sendiri tidak bisa membedakan keduanya.
    re: /postgres(?:ql)?:\/\/[^\s"'<>`\\]{12,}/g,
  },
  { name: 'Neon API key', re: /\bnpg_[A-Za-z0-9]{12,}/g },
  { name: 'GitHub token', re: /\bgh[pousr]_[A-Za-z0-9]{20,}/g },
  { name: 'token gaya OpenAI/Anthropic', re: /\bsk-[A-Za-z0-9_-]{20,}/g },
  { name: 'kunci Firebase', re: /\bAIza[0-9A-Za-z_-]{30,}/g },
  { name: 'private key', re: /-----BEGIN [A-Z ]*PRIVATE KEY-----/g },
  // Variabel yang namanya sudah menyatakan rahasia: nilainya tidak boleh
  // berupa apa pun selain placeholder.
  { name: 'AUTH_SECRET terisi', re: /\bAUTH_SECRET\s*=\s*["']?([A-Za-z0-9_\-+/=]{16,})/g },
  { name: 'ADMIN_PASS terisi', re: /\bADMIN_PASS\s*=\s*["']?([^\s"'`]{4,})/g },
  { name: 'VERCEL_TOKEN terisi', re: /\bVERCEL_TOKEN\s*=\s*["']?([A-Za-z0-9_\-]{10,})/g },
  { name: 'DATABASE_URL terisi', re: /\bDATABASE_URL(?:_WEB)?\s*=\s*["']?(postgres[^\s"'`]{10,})/g },
];

/// File yang tidak mungkin berisi rahasia aplikasi dan terlalu besar untuk
/// dipindai kata per kata: biner, kunci paket, dan font.
const SKIP_EXT = /\.(png|jpe?g|webp|gif|ico|ttf|otf|woff2?|apk|aab|jar|zip|so|dex|wasm|pdf)$/i;
const SKIP_PATH = /^(build\/|\.dart_tool\/|node_modules\/)/;

/// Apakah nilai yang cocok hanya placeholder dokumentasi.
function isPlaceholder(text) {
  const low = text.toLowerCase();
  return PLACEHOLDER.some((p) => low.includes(p));
}

/// Samarkan nilai supaya log tidak ikut membocorkan apa pun.
function mask(value) {
  const v = value.trim();
  if (v.length <= 8) return '*'.repeat(v.length);
  return `${v.slice(0, 4)}${'*'.repeat(Math.min(24, v.length - 8))}${v.slice(-4)}`;
}

/// Pindai satu teks; kembalikan temuan (tanpa nilai mentah).
function scanText(text, where) {
  const out = [];
  for (const rule of RULES) {
    rule.re.lastIndex = 0;
    let m;
    while ((m = rule.re.exec(text))) {
      const value = m[0];
      if (isPlaceholder(value)) continue;
      // Nomor baris dihitung dari awal teks supaya pesannya bisa langsung
      // dibuka di editor.
      const line = text.slice(0, m.index).split('\n').length;
      out.push({ where, line, rule: rule.name, sample: mask(value) });
    }
  }
  return out;
}

function trackedFiles() {
  return execFileSync('git', ['ls-files', '-z'], { encoding: 'utf8' })
    .split('\0')
    .filter(Boolean)
    .filter((f) => !SKIP_EXT.test(f) && !SKIP_PATH.test(f));
}

/// Semua blob yang pernah ada di riwayat, dikelompokkan supaya `cat-file
/// --batch` tidak dipanggil per objek (ribuan proses = lambat).
function historyBlobs() {
  const list = execFileSync('git', ['rev-list', '--objects', '--all'], { encoding: 'utf8' })
    .split('\n')
    .filter(Boolean)
    .map((l) => l.split(' ')[0]);
  const seen = new Set();
  const blobs = [];
  for (let i = 0; i < list.length; i += 400) {
    const chunk = list.slice(i, i + 400).join('\n');
    const buf = execFileSync('git', ['cat-file', '--batch'], {
      input: chunk,
      maxBuffer: 512 * 1024 * 1024,
    });
    // Satu objek: header "sha type size\n" lalu isi sepanjang size byte.
    let pos = 0;
    while (pos < buf.length) {
      const nl = buf.indexOf(10, pos);
      if (nl === -1) break;
      const header = buf.slice(pos, nl).toString();
      const [sha, type, size] = header.split(' ');
      const len = Number(size);
      const body = buf.slice(nl + 1, nl + 1 + len);
      pos = nl + 1 + len + 1;
      if (type !== 'blob' || !Number.isFinite(len)) continue;
      if (seen.has(sha)) continue;
      seen.add(sha);
      // Lewati biner: byte NUL di 4 KB pertama menandakan bukan teks.
      if (body.slice(0, 4096).includes(0)) continue;
      blobs.push({ sha: sha.slice(0, 8), text: body.toString('utf8') });
    }
  }
  return blobs;
}

function main() {
  const findings = [];

  for (const file of trackedFiles()) {
    let text;
    try {
      text = readFileSync(file, 'utf8');
    } catch {
      continue; // bukan teks
    }
    findings.push(...scanText(text, file));
  }

  const treeHits = findings.length;
  if (process.env.SECRET_SCAN_HISTORY !== '0') {
    for (const blob of historyBlobs()) {
      findings.push(...scanText(blob.text, `git:${blob.sha}`));
    }
  }

  if (findings.length === 0) {
    console.log('OK — tidak ada kredensial di file terlacak maupun riwayat git.');
    return 0;
  }

  // Satu temuan bisa muncul di beberapa commit (file yang sama, versi sama).
  // Ringkas per aturan supaya keluarannya bisa dibaca.
  const byRule = new Map();
  for (const f of findings) {
    if (!byRule.has(f.rule)) byRule.set(f.rule, []);
    byRule.get(f.rule).push(f);
  }
  console.error(`DITEMUKAN ${findings.length} nilai yang tampak seperti rahasia:`);
  for (const [rule, list] of byRule) {
    console.error(`\n  ${rule} (${list.length})`);
    for (const f of list.slice(0, 8)) {
      console.error(`    ${f.where}:${f.line}  ${f.sample}`);
    }
    if (list.length > 8) console.error(`    … ${list.length - 8} lainnya`);
  }
  console.error(
    '\nJangan commit nilainya. Rotasi kredensial yang sudah terlanjur masuk, ' +
      'lalu hapus dari riwayat (git filter-repo) bila perlu.',
  );
  // Temuan di pohon kerja = gagal keras: itu yang akan ter-push berikutnya.
  // Temuan HANYA di riwayat dilaporkan, tapi tidak menggagalkan build lama
  // yang isinya sudah dirotasi — kalau digagalkan, CI merah selamanya.
  const treeOnly = findings.filter((f) => !f.where.startsWith('git:'));
  return treeOnly.length > 0 ? 1 : 0;
}

process.exit(main());
