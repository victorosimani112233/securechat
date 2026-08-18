#!/usr/bin/env bash
set -euo pipefail

deploy_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
server_root="$(cd -- "$deploy_dir/.." && pwd)"

require_digest() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[a-zA-Z0-9._/:@-]+@sha256:[a-f0-9]{64}$ ]]; then
    echo "$name must be an immutable image@sha256 digest" >&2
    exit 2
  fi
}

: "${JRE_IMAGE:?Set JRE_IMAGE to an approved immutable image@sha256 digest}"
: "${SIGNALING_IMAGE_TAG:?Set the local signaling output tag}"
: "${BOT_API_IMAGE_TAG:?Set the local bot-api output tag}"
require_digest JRE_IMAGE "$JRE_IMAGE"

(cd "$server_root/.." && \
  "${DART_BIN:-dart}" tool/audit_server_deployment_privacy.dart)

# Artefakt kimligi image'a gomulur; canli ucun hangi commit oldugu boylece
# deploy kaydiyla karsilastirilabilir.
: "${SOURCE_COMMIT:?Set SOURCE_COMMIT to the exact commit being released}"
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
  { echo "SOURCE_COMMIT must be a full 40-hex commit id" >&2; exit 2; }
SOURCE_BUILT_AT="${SOURCE_BUILT_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

(cd "$server_root" && ./gradlew \
  :signaling-server:fatJar :bot-api:installDist \
  -PsourceCommit="$SOURCE_COMMIT" -PsourceBuiltAt="$SOURCE_BUILT_AT" \
  --offline --no-daemon)

docker build \
  --build-arg "RUNTIME_IMAGE=$JRE_IMAGE" \
  --file "$deploy_dir/Dockerfile.signaling" \
  --tag "$SIGNALING_IMAGE_TAG" \
  "$server_root"

docker build \
  --build-arg "RUNTIME_IMAGE=$JRE_IMAGE" \
  --file "$deploy_dir/Dockerfile.bot-api" \
  --tag "$BOT_API_IMAGE_TAG" \
  "$server_root"

echo "Images built locally. Push them to the private registry and deploy only"
echo "their registry image@sha256 digests; mutable tags are not release inputs."
