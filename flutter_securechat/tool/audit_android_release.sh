#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AAB="${1:-$PROJECT_DIR/build/app/outputs/bundle/release/app-release.aab}"
SYMBOL_DIR="${SECURECHAT_SYMBOL_DIR:-$PROJECT_DIR/build/private_symbols/android}"

for command_name in unzip readelf rg sha256sum; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Release audit araci eksik: $command_name" >&2
    exit 2
  fi
done

if [[ ! -f "$AAB" ]]; then
  echo "Release AAB bulunamadi: $AAB" >&2
  exit 2
fi

AUDIT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/securechat-aab-audit.XXXXXX")"
cleanup() {
  rm -rf -- "$AUDIT_DIR"
}
trap cleanup EXIT

unzip -q "$AAB" -d "$AUDIT_DIR"

native_count=0
while IFS= read -r -d '' library; do
  native_count=$((native_count + 1))
  if readelf -SW "$library" | awk '$2 ~ /^\.debug/ || $2 == ".symtab" { found=1 } END { exit !found }'; then
    echo "Teslim native kutuphanesinde debug sembolu kaldi: ${library#"$AUDIT_DIR"/}" >&2
    exit 3
  fi
done < <(find "$AUDIT_DIR/base/lib" -type f -name '*.so' -print0)

if (( native_count == 0 )); then
  echo "AAB icinde native kutuphane bulunamadi; paket yapisi beklenmiyor." >&2
  exit 3
fi

for required_entry in \
  "base/assets/flutter_assets/NOTICES.Z" \
  "BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map"; do
  if [[ ! -f "$AUDIT_DIR/$required_entry" ]]; then
    echo "Release kaniti eksik: $required_entry" >&2
    exit 4
  fi
done

for symbol_name in \
  app.android-arm.symbols \
  app.android-arm64.symbols \
  app.android-x64.symbols \
  r8-mapping.txt \
  SHA256SUMS; do
  if [[ ! -s "$SYMBOL_DIR/$symbol_name" ]]; then
    echo "Private symbol arsivi eksik: $SYMBOL_DIR/$symbol_name" >&2
    exit 4
  fi
done

if find "$AUDIT_DIR" -type f \
  \( -name '*.jks' -o -name '*.keystore' -o -name '*.p12' -o \
     -name '*.pfx' -o -name 'signing.properties' -o -name '.env' \) \
  -print -quit | grep -q .; then
  echo "AAB icinde credential/signing dosyasi bulundu." >&2
  exit 5
fi

if rg -a -l \
  'DIRECTORY_OPRF_PRIVATE_KEY=|OFFLINE_QUEUE_ENCRYPTION_KEY=|JWT_SECRET=|POSTGRES_PASSWORD=|REDIS_PASSWORD=' \
  "$AUDIT_DIR" >/dev/null; then
  echo "AAB icinde yasak server-secret izi bulundu." >&2
  exit 5
fi

# Apache Tika gibi MIME veritabanlari PEM baslik metnini dosya imzasi olarak
# tasiyabilir. Yalniz basligi degil, arkasindan gercek key body gorunmesini
# reddederek bu guvenli resource'u private-key false positive'i yapmayiz.
if rg -a -U -l --pcre2 \
  -- '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=]{40,}' \
  "$AUDIT_DIR" >/dev/null; then
  echo "AAB icinde gomulu private key bulundu." >&2
  exit 5
fi

sha256sum "$AAB"
echo "Android release audit: PASS ($native_count stripped native library)"
echo "Not: AAB, Play icin obfuscation/debug metadata tasir ve private tutulmalidir; cihaz APK'larina bu BUNDLE-METADATA teslim edilmez."
