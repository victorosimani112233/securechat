#!/usr/bin/env bash
# QA APK: loopback TLS mock sunucusuna pinlenmiş debug build.
# Kaynak kodda DEĞİŞİKLİK YOK — tüm ayar derleme zamanı dart-define ile.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
export PATH="$PATH:/home/user497/flutter/bin"
flutter build apk --debug \
  --dart-define=SECURECHAT_API_BASE_URL=https://127.0.0.1:18444 \
  --dart-define=SECURECHAT_SIGNALING_URL=wss://127.0.0.1:18444 \
  --dart-define=SECURECHAT_CERT_PIN_HOST=127.0.0.1 \
  --dart-define=SECURECHAT_CERT_PIN_SHA256=vH/j/4XeUzHpmYrVZovWJHT+TBf5gdkeO5l3ukZuIWI= \
  --dart-define=SECURECHAT_CERT_PIN_SHA256_BACKUP=BtsBlSLKt11iuRRaNnwJbIQGHpEef0g0tAaMGRGEKDw=
