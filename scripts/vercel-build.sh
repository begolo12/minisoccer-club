#!/usr/bin/env bash
# Build web untuk deploy Vercel.
#
# Kenapa ada skrip ini: `build/web` tidak pernah masuk git (60 MB artefak),
# jadi Vercel Git deploy dulu selalu gagal dalam 3 detik karena
# `outputDirectory` tidak ada. Sekarang Vercel yang membangun sendiri.
#
# Dua jalur:
#   1. Cepat  — `build/web/index.html` sudah ada (deploy dari CLI yang
#               meng-upload artefak lokal lewat .vercelignore). Tidak
#               menyentuh jaringan, selesai < 1 detik.
#   2. Cloud  — unduh Flutter SDK (di-cache di /tmp antar build), lalu
#               `flutter build web --release`.
#
# Versi Flutter dipatok supaya build di cloud sama dengan mesin lokal.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
OUT="build/web"

# Aplikasi disajikan di jalur `/minisoccer/` pada domain portal
# (airevo-digital.my.id/minisoccer), jadi semua aset harus memakai prefiks itu.
# Base href salah = index.html memuat, tetapi seluruh aset 404.
BASE_HREF="/minisoccer/"

if [ -f "$OUT/index.html" ] && [ -f "$OUT/main.dart.js" ] &&
  grep -q "<base href=\"$BASE_HREF\">" "$OUT/index.html"; then
  echo "build/web sudah ada (deploy dari CLI) — lewati build."
  # Daftar precache service worker harus mengikuti artefak yang benar-benar
  # diunggah, jadi dibuat di sini juga (bukan hanya setelah flutter build).
  node scripts/prune-web.mjs
  node scripts/disable-flutter-sw.mjs
  node scripts/gen-sw-manifest.mjs
  exit 0
fi

echo "== Menyiapkan Flutter $FLUTTER_VERSION =="
# Di bawah ~/.cache supaya ikut build cache Vercel antar deploy.
SDK_ROOT="${HOME}/.cache/flutter-sdk"
SDK_DIR="${SDK_ROOT}/flutter"

if [ ! -x "${SDK_DIR}/bin/flutter" ]; then
  mkdir -p "$SDK_ROOT"
  # Flutter SDK ~1,5 GB terkompresi / ~3,3 GB setelah ekstrak. Berhenti lebih
  # awal dengan pesan jelas daripada gagal di tengah tar karena disk penuh.
  FREE_KB=$(df -Pk "$SDK_ROOT" | awk 'NR==2 {print $4}')
  NEED_KB=$((4 * 1024 * 1024))
  if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt "$NEED_KB" ]; then
    echo "disk $((FREE_KB / 1024)) MB < 4 GB yang dibutuhkan Flutter SDK" >&2
    exit 1
  fi
  ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${ARCHIVE}"
  echo "unduh ${URL}"
  curl -fsSL --retry 3 --retry-delay 5 -o "/tmp/${ARCHIVE}" "$URL"
  tar -xJf "/tmp/${ARCHIVE}" -C "$SDK_ROOT"
  rm -f "/tmp/${ARCHIVE}"
fi

export PATH="${SDK_DIR}/bin:${PATH}"
# Jangan ikut meng-update channel; versi sudah dipatok.
git config --global --add safe.directory "$SDK_DIR" || true
flutter --version

echo "== flutter pub get =="
flutter pub get

echo "== flutter build web =="
# --no-web-resources-cdn: CanvasKit disajikan dari domain sendiri (CSP
# produksi tidak mengizinkan unpkg/jsdelivr).
flutter build web --release --no-web-resources-cdn --base-href "$BASE_HREF"

# Matikan service worker bawaan Flutter (stub yang memuat ulang tab dan
# bertabrakan dengan web/sw.js), lalu susun daftar precache-nya.
node scripts/prune-web.mjs
node scripts/disable-flutter-sw.mjs
node scripts/gen-sw-manifest.mjs

test -f "$OUT/index.html" || { echo "build/web/index.html tidak terbentuk"; exit 1; }
echo "selesai: $(du -sh "$OUT" | cut -f1) di $OUT"
