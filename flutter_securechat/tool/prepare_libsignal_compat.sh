#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${SECURECHAT_LIBSIGNAL_COMPAT_DIR:-$ROOT/.dart_tool/libsignal_compat}"
MAVEN_BASE="https://repo.maven.apache.org/maven2"

mkdir -p "$TARGET"

fetch_verified() {
  local relative_path="$1"
  local expected_sha256="$2"
  local name="${relative_path##*/}"
  local destination="$TARGET/$name"
  local temporary="$destination.part"
  local actual_sha256

  if [[ -f "$destination" ]]; then
    actual_sha256="$(shasum -a 256 "$destination" | awk '{print $1}')"
    if [[ "$actual_sha256" == "$expected_sha256" ]]; then
      return
    fi
    rm -f "$destination"
  fi

  rm -f "$temporary"
  curl --fail --location --silent --show-error \
    --proto '=https' --tlsv1.2 --retry 3 \
    "$MAVEN_BASE/$relative_path" \
    --output "$temporary"
  actual_sha256="$(shasum -a 256 "$temporary" | awk '{print $1}')"
  if [[ "$actual_sha256" != "$expected_sha256" ]]; then
    rm -f "$temporary"
    echo "$name SHA-256 mismatch" >&2
    exit 2
  fi
  mv "$temporary" "$destination"
}

fetch_verified \
  "org/whispersystems/signal-protocol-java/2.8.1/signal-protocol-java-2.8.1.jar" \
  "b19db36839ab008fdccefc7f8c005f2ea43dc7c7298a209bc424e6f9b6d5617b"
fetch_verified \
  "org/whispersystems/curve25519-java/0.5.0/curve25519-java-0.5.0.jar" \
  "0aadd43cf01d11e9b58f867b3c4f25c3194e8b0623d1953d32dfbfbee009e38d"
fetch_verified \
  "com/google/protobuf/protobuf-javalite/3.10.0/protobuf-javalite-3.10.0.jar" \
  "215a94dbe100130295906b531bb72a26965c7ac8fcd9a75bf8054a8ac2abf4b4"

echo "libsignal compatibility fixtures: PASS"
