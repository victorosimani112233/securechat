#!/usr/bin/env bash
# Mac gelistirme makinesinin bu depoyu derlemeye hazir olup olmadigini denetler.
#
# Hicbir sey KURMAZ, hicbir dosyayi degistirmez. Eksik olan her sey icin
# calistirilacak komutu yazar.
set -uo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
cd "$project_directory"

readonly EXPECTED_FLUTTER="3.44.9"
readonly EXPECTED_DART="3.12.2"

problems=0
note() { printf '  %s\n' "$1"; }
ok()   { printf '\033[32m  OK\033[0m    %s\n' "$1"; }
fail() { printf '\033[31m  EKSIK\033[0m %s\n' "$1"; problems=$((problems + 1)); }
warn() { printf '\033[33m  UYARI\033[0m %s\n' "$1"; }

echo
echo "SecureChat — macOS hazirlik denetimi"
echo

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Bu betik macOS icin. Su anki sistem: $(uname -s)"
  exit 2
fi
printf 'Mimari: %s\n\n' "$(uname -m)"

echo "Flutter araç zinciri"
if command -v flutter >/dev/null; then
  flutter_version="$(flutter --version 2>/dev/null | head -1 | awk '{print $2}')"
  if [[ "$flutter_version" == "$EXPECTED_FLUTTER" ]]; then
    ok "Flutter $flutter_version"
  else
    warn "Flutter $flutter_version — bu depo $EXPECTED_FLUTTER ile doğrulandı"
    note "Sürüm farkı pub çözümlemesini değiştirebilir; pubspec sürümleri tam pinli."
  fi
else
  fail "flutter bulunamadı"
  note "https://docs.flutter.dev/get-started/install/macos"
fi

if command -v dart >/dev/null; then
  dart_version="$(dart --version 2>&1 | awk '{print $4}')"
  [[ "$dart_version" == "$EXPECTED_DART" ]] \
    && ok "Dart $dart_version" \
    || warn "Dart $dart_version — beklenen $EXPECTED_DART"
else
  fail "dart bulunamadı (normalde Flutter ile gelir)"
fi

echo
echo "iOS araç zinciri"
if command -v xcodebuild >/dev/null; then
  ok "Xcode $(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')"
else
  fail "xcodebuild bulunamadı — App Store'dan Xcode kurun"
  note "Kurulum sonrası: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
fi
if xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  ok "iOS SDK"
else
  fail "iOS SDK yok — Xcode > Settings > Platforms"
fi

echo
echo "SQLCipher"
# Dart tarafındaki macOS aday listesiyle AYNI olmalı:
# lib/src/storage/encrypted_record_store.dart → _resolveLibrary
dylib_found=""
for candidate in \
  /opt/homebrew/lib/libsqlcipher.dylib \
  /opt/homebrew/opt/sqlcipher/lib/libsqlcipher.dylib \
  /usr/local/lib/libsqlcipher.dylib \
  /usr/local/opt/sqlcipher/lib/libsqlcipher.dylib
do
  if [[ -f "$candidate" ]]; then
    dylib_found="$candidate"
    break
  fi
done
if [[ -n "$dylib_found" ]]; then
  ok "libsqlcipher.dylib → $dylib_found"
else
  fail "libsqlcipher.dylib yok — ana makinedeki testler veritabanını açamaz"
  note "brew install sqlcipher"
  note "Bu yalnız 'flutter test' için gerekli; iOS uygulaması gömülü kopyayı kullanır."
fi

if [[ -f ios/SQLCipher/Sources/CSQLCipher/sqlite3.c ]]; then
  ok "Gömülü SQLCipher amalgamation ($(wc -c < ios/SQLCipher/Sources/CSQLCipher/sqlite3.c) bayt)"
else
  fail "ios/SQLCipher/Sources/CSQLCipher/sqlite3.c yok — iOS derlemesi şifresiz veritabanı üretir"
fi

echo
echo "Android araç zinciri (isteğe bağlı — yalnız Android derlemesi için)"
if command -v java >/dev/null; then
  ok "Java $(java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/')"
else
  warn "java bulunamadı — Android derlemesi çalışmaz (iOS etkilenmez)"
  note "brew install --cask temurin@21"
fi
if [[ -n "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}" ]]; then
  ok "Android SDK: ${ANDROID_HOME:-$ANDROID_SDK_ROOT}"
else
  warn "ANDROID_HOME tanımlı değil — Android derlemesi çalışmaz (iOS etkilenmez)"
fi

echo
echo "Depo"
if git rev-parse --git-dir >/dev/null 2>&1; then
  ok "git deposu — dal: $(git rev-parse --abbrev-ref HEAD)"
  unpushed="$(git log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$unpushed" == "0" ]] \
    && ok "Uzak sunucuya gönderilmemiş commit yok" \
    || warn "$unpushed commit hiçbir remote'ta yok"
else
  fail "git deposu değil"
fi
# local.properties makineye özeldir ve sürüm kontrolünde tutulmaz; Flutter
# kendisi üretir, taşınan bir kopya Linux yollarını taşıyacağı için zararlıdır.
if [[ -f android/local.properties ]]; then
  if grep -qE '^(sdk|flutter)\.dir=/home/' android/local.properties 2>/dev/null; then
    fail "android/local.properties Linux yolları içeriyor — silin, Flutter yeniden üretir"
    note "rm android/local.properties"
  else
    ok "android/local.properties"
  fi
fi

echo
echo "Doğrulama"
if [[ -x tool/verify_ios_on_macos.sh ]]; then
  ok "tool/verify_ios_on_macos.sh çalıştırılabilir"
else
  warn "tool/verify_ios_on_macos.sh çalıştırılabilir değil (chmod +x)"
fi

echo
if [[ "$problems" == "0" ]]; then
  echo "Hazır. Sıradaki adımlar:"
  echo "  flutter pub get"
  echo "  flutter test"
  echo "  dart tool/audit_ios_readiness.dart"
  echo "  flutter build ios --release --no-codesign   # imzasız derleme denemesi"
  exit 0
fi
echo "$problems zorunlu eksik var; yukarıdaki komutları çalıştırın."
exit 1
