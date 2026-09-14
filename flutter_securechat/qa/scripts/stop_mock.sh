#!/usr/bin/env bash
set -uo pipefail
SELF=$$
for p in $(pgrep -x dart 2>/dev/null); do
  [ "$p" = "$SELF" ] && continue
  cmd=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null) || continue
  case "$cmd" in *server.dart*) kill "$p" 2>/dev/null && echo "stopped $p";; esac
done
