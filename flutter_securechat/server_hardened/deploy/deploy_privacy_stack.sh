#!/usr/bin/env bash
set -euo pipefail

deploy_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd -- "$deploy_dir/../.." && pwd)"
compose_file="$deploy_dir/compose.privacy.yml"
mode="${1:---check-only}"

usage() {
  echo "Usage: $0 [--check-only|--apply]" >&2
}

fail() {
  echo "privacy deployment check failed: $1" >&2
  exit 2
}

require_digest() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[a-zA-Z0-9._/:@-]+@sha256:[a-f0-9]{64}$ ]]; then
    fail "$name must be an immutable image@sha256 digest"
  fi
}

require_secret_file() {
  local name="$1"
  local path="${!name:-}"
  [[ -n "$path" ]] || fail "$name is required"
  [[ "$path" == /* ]] || fail "$name must be an absolute path"
  [[ ! -L "$path" ]] || fail "$name must not be a symbolic link"
  [[ -f "$path" ]] || fail "$name must point to a regular file"
  [[ -s "$path" ]] || fail "$name must not be empty"

  local size
  size="$(stat -c '%s' -- "$path")"
  (( size <= 65536 )) || fail "$name exceeds the 65536-byte secret limit"

  local raw_mode
  raw_mode="$(stat -c '%a' -- "$path")"
  local numeric_mode=$((8#$raw_mode))
  (( (numeric_mode & 077) == 0 )) ||
    fail "$name must not grant group or world permissions"
}

case "$mode" in
  --check-only | --apply) ;;
  *)
    usage
    exit 2
    ;;
esac

command -v docker >/dev/null 2>&1 || fail "docker is required"
docker compose version >/dev/null 2>&1 || fail "docker compose v2 is required"
command -v sha256sum >/dev/null 2>&1 || fail "sha256sum is required"

: "${REDIS_IMAGE:?Set REDIS_IMAGE to an immutable image@sha256 digest}"
: "${SIGNALING_IMAGE:?Set SIGNALING_IMAGE to an immutable image@sha256 digest}"
require_digest REDIS_IMAGE "$REDIS_IMAGE"
require_digest SIGNALING_IMAGE "$SIGNALING_IMAGE"

: "${DATABASE_URL:?Set the PostgreSQL JDBC URL}"
[[ "$DATABASE_URL" == jdbc:postgresql://* ]] ||
  fail "DATABASE_URL must use the PostgreSQL JDBC scheme"
[[ "$DATABASE_URL" == *"sslmode=verify-full"* ]] ||
  fail "DATABASE_URL must authenticate PostgreSQL TLS with sslmode=verify-full"
[[ "${DATABASE_URL,,}" != *"password="* ]] ||
  fail "DATABASE_URL must not embed a database password"
[[ ! "$DATABASE_URL" =~ ^jdbc:postgresql://[^/@]+@ ]] ||
  fail "DATABASE_URL must not embed user-info credentials"

secret_file_variables=(
  DATABASE_PASSWORD_FILE
  REDIS_PASSWORD_FILE
  TURN_SECRET_FILE
  JWT_SECRET_FILE
  PRIVACY_INDEX_KEY_FILE
  OFFLINE_QUEUE_KEY_FILE
  FCM_TOKEN_KEY_FILE
  METRICS_TOKEN_FILE
  SMTP_PASSWORD_FILE
  FIREBASE_SERVICE_ACCOUNT_FILE
  DIRECTORY_HSM_PIN_FILE
)
declare -A secret_fingerprints=()
for variable in "${secret_file_variables[@]}"; do
  require_secret_file "$variable"
  fingerprint="$(sha256sum -- "${!variable}" | cut -d ' ' -f 1)"
  previous="${secret_fingerprints[$fingerprint]:-}"
  [[ -z "$previous" ]] ||
    fail "$variable reuses secret material assigned to $previous"
  secret_fingerprints["$fingerprint"]="$variable"
done

(cd -- "$project_root" &&
  "${DART_BIN:-dart}" tool/audit_server_deployment_privacy.dart)
docker compose --file "$compose_file" config --quiet

if [[ "$mode" == "--check-only" ]]; then
  echo "Hardened privacy deployment preflight: PASS (no containers changed)"
  exit 0
fi

: "${SECURECHAT_DEPLOY_CONFIRMATION:?Set SECURECHAT_DEPLOY_CONFIRMATION=deploy-hardened-privacy-stack}"
[[ "$SECURECHAT_DEPLOY_CONFIRMATION" == "deploy-hardened-privacy-stack" ]] ||
  fail "deployment confirmation value is invalid"

for image in "$REDIS_IMAGE" "$SIGNALING_IMAGE"; do
  docker image inspect "$image" >/dev/null 2>&1 ||
    fail "a required digest-pinned image is not present locally"
done

docker compose --file "$compose_file" up --detach --remove-orphans
