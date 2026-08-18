#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-flutter}"
SYMBOL_DIR="${SECURECHAT_SYMBOL_DIR:-$PROJECT_DIR/build/private_symbols/android}"

cd "$PROJECT_DIR"
mkdir -p "$SYMBOL_DIR"

if [[ "${SECURECHAT_OFFLINE:-0}" == "1" ]]; then
  "$FLUTTER_BIN" pub get --offline
else
  "$FLUTTER_BIN" pub get
fi

defines=()
for name in \
  SECURECHAT_API_BASE_URL \
  SECURECHAT_SIGNALING_URL \
  SECURECHAT_CERT_PIN_HOST \
  SECURECHAT_CERT_PIN_SHA256 \
  SECURECHAT_CERT_PIN_SHA256_BACKUP; do
  if [[ -n "${!name:-}" ]]; then
    defines+=("--dart-define=$name=${!name}")
  fi
done

"$FLUTTER_BIN" build appbundle \
  --release \
  --obfuscate \
  --split-debug-info="$SYMBOL_DIR" \
  "${defines[@]}"

AAB="$PROJECT_DIR/build/app/outputs/bundle/release/app-release.aab"
if [[ ! -f "$AAB" ]]; then
  echo "Release AAB bulunamadi: $AAB" >&2
  exit 1
fi
R8_MAPPING="$PROJECT_DIR/build/app/outputs/mapping/release/mapping.txt"
if [[ -f "$R8_MAPPING" ]]; then
  cp "$R8_MAPPING" "$SYMBOL_DIR/r8-mapping.txt"
fi
sha256sum "$AAB" > "$AAB.sha256"
(
  cd "$SYMBOL_DIR"
  find . -maxdepth 1 -type f ! -name 'SHA256SUMS' -printf '%P\n' \
    | sort \
    | xargs -r sha256sum > SHA256SUMS
)

"$PROJECT_DIR/tool/audit_android_release.sh" "$AAB"

echo "AAB: $AAB"
echo "SHA-256: $AAB.sha256"
echo "Private Dart/R8 sembolleri: $SYMBOL_DIR"
