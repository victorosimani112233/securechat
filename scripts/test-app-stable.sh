#!/bin/bash
# App modulundeki testleri stabil sirayla calistirir.
#
# NEDEN: ":app:testDevDebugUnitTest" full komutu mockk JVM agent ile JPLISAgent
# assertion ("can't create name string") cokuyor, paralel test runner sonraki
# testleri de yutuyor. Paket-bazli ayri JVM'ler ile sirali calisma deterministik.
#
# Test runner JVM crash root cause Sprint 5+ icin actık — bu script gunluk
# CI/yerel calistirma icin gecici cozum.
#
# Kullanim: ./scripts/test-app-stable.sh
# CI: bu script'i `./gradlew :storage:test :crypto:test :media:test :network:test`
# komutundan SONRA calistir.
set -euo pipefail
cd "$(dirname "$0")/.."

GROUPS=(
  "com.securechat.app.diagnostics.*"
  "com.securechat.app.ui.util.*"
  "com.securechat.app.ui.components.*"
  "com.securechat.app.domain.usecase.*"
  "com.securechat.app.util.*"
  "com.securechat.app.data.incoming.*"
  "com.securechat.app.scheduler.*"
  "com.securechat.app.data.PendingTimerFlusherTest"
  "com.securechat.app.data.IncomingMessageHandlerTest"
  "com.securechat.app.ui.viewmodel.CallViewModelTest"
  "com.securechat.app.ui.viewmodel.ContactsViewModelTest"
  "com.securechat.app.ui.viewmodel.ConversationsViewModelTest"
  "com.securechat.app.ui.viewmodel.CreateGroupViewModelTest"
  "com.securechat.app.ui.viewmodel.GroupInfoViewModelTest"
  # ChatViewModelTest @Ignore'da — refactor sonrasi yeniden yazilacak
)

PASS=0
FAIL=0
for g in "${GROUPS[@]}"; do
  echo
  echo "=== $g ==="
  if ./gradlew :app:testDevDebugUnitTest --tests "$g" --rerun-tasks 2>&1 | tail -3; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    echo "FAIL: $g"
  fi
done

echo
echo "===================="
echo "SONUC: $PASS gecti / $FAIL basarisiz / toplam ${#GROUPS[@]}"
[ "$FAIL" -eq 0 ]
