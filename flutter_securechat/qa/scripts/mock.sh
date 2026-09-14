#!/usr/bin/env bash
# Mock sunucu yasam dongusu. PID dosyasi kullanir; kendi kabugunu asla oldurmez.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$(dirname "$ROOT")"
DART=/home/user497/flutter/bin/dart
AOTRT=/home/user497/flutter/bin/cache/dart-sdk/bin/dartaotruntime
PIDFILE="$ROOT/mock/server.pid"
BIN="$ROOT/mock/server.aot"

start() {
  cd "$PROJECT"
  [ -f "$BIN" ] || { echo "build first"; return 1; }
  setsid nohup "$AOTRT" "$BIN" \
    --port 18444 \
    --cert qa/mock/tls/primary.cert.pem \
    --key qa/mock/tls/primary.key.pem \
    --directory qa/mock/tls/directory.json \
    --state qa/mock/state \
    --log qa/logs/mock_server.jsonl \
    >> qa/logs/mock_stdout.log 2>&1 < /dev/null &
  echo $! > "$PIDFILE"
  for _ in $(seq 1 30); do
    sleep 1
    if curl -sk -m 2 https://127.0.0.1:18444/__qa/state >/dev/null 2>&1; then
      echo "mock up pid=$(cat "$PIDFILE")"; return 0
    fi
  done
  echo "MOCK FAILED TO START"; tail -15 "$ROOT/logs/mock_stdout.log"; return 1
}

stop() {
  # Port sahibini oldur: dart run / AOT farkli comm adlari kullaniyor,
  # bu yuzden PID dosyasina guvenmek yetmiyor.
  local owners
  owners=$(ss -tlnp 2>/dev/null | awk '/127.0.0.1:18444/ {print $0}' \
           | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
  if [ -f "$PIDFILE" ]; then owners="$owners $(cat "$PIDFILE")"; fi
  for p in $owners; do
    kill "$p" 2>/dev/null && echo "stopped pid=$p"
  done
  rm -f "$PIDFILE"
  for _ in $(seq 1 15); do
    ss -tln 2>/dev/null | grep -q "127.0.0.1:18444" || break
    sleep 1
  done
  if ss -tln 2>/dev/null | grep -q "127.0.0.1:18444"; then
    for p in $owners; do kill -9 "$p" 2>/dev/null; done
    sleep 2
  fi
  echo "port 18444 free: $(ss -tln 2>/dev/null | grep -c '127.0.0.1:18444' | tr 1 N | tr 0 Y)"
}

build() {
  cd "$PROJECT"
  "$DART" compile aot-snapshot qa/mock/bin/server.dart -o "$BIN" 2>&1 | tail -3
}

status() {
  if curl -sk -m 3 https://127.0.0.1:18444/__qa/state 2>/dev/null; then echo; else echo "DOWN"; fi
}

case "${1:-status}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  build) build ;;
  rebuild) build && stop && start ;;
  status) status ;;
  *) echo "usage: mock.sh {start|stop|restart|build|rebuild|status}" ;;
esac
