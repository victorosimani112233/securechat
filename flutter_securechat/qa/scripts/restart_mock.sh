#!/usr/bin/env bash
# Mock sunucusunu yeniden baslatir. Kendi kabugunu oldurmemek icin PID'leri
# /proc uzerinden dogrular.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$(dirname "$ROOT")"
DART=/home/user497/flutter/bin/dart
SELF=$$

for p in $(pgrep -x dart 2>/dev/null); do
  [ "$p" = "$SELF" ] && continue
  cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null) || continue
  case "$cmd" in
    *server.dart*) kill "$p" 2>/dev/null && echo "stopped mock pid=$p" ;;
  esac
done
sleep 2

cd "$PROJECT"
setsid nohup "$DART" run qa/mock/bin/server.dart \
  --port 18444 \
  --cert qa/mock/tls/primary.cert.pem \
  --key qa/mock/tls/primary.key.pem \
  --directory qa/mock/tls/directory.json \
  --state qa/mock/state \
  --log qa/logs/mock_server.jsonl \
  > qa/logs/mock_stdout.log 2>&1 < /dev/null &
disown
sleep 11
if grep -q server_start qa/logs/mock_server.jsonl 2>/dev/null; then
  tail -1 <(grep server_start qa/logs/mock_server.jsonl)
else
  echo "MOCK FAILED TO START"; tail -20 qa/logs/mock_stdout.log
fi
