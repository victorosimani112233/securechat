#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="$(basename "$ROOT")"
OUT="${1:-$ROOT/build/offline_bundle}"
FLUTTER_SDK="${FLUTTER_SDK:-/tmp/flutter-sdk}"
PUB_CACHE="${PUB_CACHE:-$HOME/.pub-cache}"
GRADLE_HOME="${GRADLE_USER_HOME:-$HOME/.gradle}"
ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
LOCAL_MAVEN_REPO="${LOCAL_MAVEN_REPO:-$ROOT/../local-repo}"

mkdir -p "$OUT"

# Bilinen ciktilari acik hedeflerle yenile; onceki surumden stale APK veya
# manifest kalmasina izin verme. OUT'un baska kullanici dosyalarina dokunulmaz.
rm -f \
  "$OUT/flutter_securechat_source.tar.gz" \
  "$OUT/flutter_sdk.tar.gz" \
  "$OUT/pub_cache.tar.gz" \
  "$OUT/gradle_cache.tar.gz" \
  "$OUT/maven_local_repo.tar.gz" \
  "$OUT/android_sdk_build.tar.gz" \
  "$OUT/app-debug.apk" \
  "$OUT/app-release-unsigned.apk" \
  "$OUT/README.md" \
  "$OUT/FILES.txt" \
  "$OUT/SHA256SUMS.txt"

echo "[bundle] project source"
tar --exclude="$PROJECT_NAME/build" \
  --exclude="$PROJECT_NAME/.dart_tool" \
  --exclude="$PROJECT_NAME/.flutter-plugins-dependencies" \
  --exclude="$PROJECT_NAME/.idea" \
  --exclude="$PROJECT_NAME/android/.gradle" \
  --exclude="$PROJECT_NAME/android/local.properties" \
  --exclude="$PROJECT_NAME/ios/Pods" \
  --exclude="$PROJECT_NAME/ios/.symlinks" \
  --exclude="$PROJECT_NAME/ios/Flutter/ephemeral" \
  --exclude="$PROJECT_NAME/ios/Flutter/Generated.xcconfig" \
  --exclude="$PROJECT_NAME/ios/Flutter/flutter_export_environment.sh" \
  -czf "$OUT/flutter_securechat_source.tar.gz" \
  -C "$ROOT/.." \
  "$PROJECT_NAME" \
  app/src/main/res/values/strings.xml \
  app/src/main/res/values-en/strings.xml

if [[ -d "$FLUTTER_SDK" ]]; then
  echo "[bundle] flutter sdk"
  tar -czf "$OUT/flutter_sdk.tar.gz" -C "$(dirname "$FLUTTER_SDK")" "$(basename "$FLUTTER_SDK")"
else
  echo "[bundle] skip flutter sdk: $FLUTTER_SDK not found" >&2
fi

if [[ -d "$PUB_CACHE" ]]; then
  echo "[bundle] pub cache"
  tar -czf "$OUT/pub_cache.tar.gz" -C "$(dirname "$PUB_CACHE")" "$(basename "$PUB_CACHE")"
else
  echo "[bundle] skip pub cache: $PUB_CACHE not found" >&2
fi

if [[ -d "$GRADLE_HOME" ]]; then
  echo "[bundle] gradle cache"
  tar -czf "$OUT/gradle_cache.tar.gz" -C "$(dirname "$GRADLE_HOME")" "$(basename "$GRADLE_HOME")"
else
  echo "[bundle] skip gradle cache: $GRADLE_HOME not found" >&2
fi

if [[ -d "$LOCAL_MAVEN_REPO" ]]; then
  echo "[bundle] hardened server local Maven repository"
  tar -czf "$OUT/maven_local_repo.tar.gz" -C "$LOCAL_MAVEN_REPO" .
else
  echo "[bundle] required local Maven repository not found: $LOCAL_MAVEN_REPO" >&2
  exit 2
fi

if [[ -d "$ANDROID_SDK" ]]; then
  echo "[bundle] android sdk build subset"
  tar -czf "$OUT/android_sdk_build.tar.gz" -C "$ANDROID_SDK" \
    licenses \
    platform-tools \
    platforms/android-34 \
    platforms/android-35 \
    platforms/android-36 \
    build-tools/36.0.0 \
    ndk/28.2.13676358
else
  echo "[bundle] skip android sdk: $ANDROID_SDK not found" >&2
fi

if [[ -f "$ROOT/build/app/outputs/flutter-apk/app-debug.apk" ]]; then
  echo "[bundle] debug apk"
  cp "$ROOT/build/app/outputs/flutter-apk/app-debug.apk" "$OUT/app-debug.apk"
fi

if [[ -f "$ROOT/build/app/outputs/flutter-apk/app-release.apk" ]]; then
  echo "[bundle] unsigned release apk"
  cp "$ROOT/build/app/outputs/flutter-apk/app-release.apk" "$OUT/app-release-unsigned.apk"
fi

cat > "$OUT/README.md" <<'EOF'
# SecureChat Flutter Offline Bundle

Icerik:

- `flutter_securechat_source.tar.gz`: Flutter tasima kaynaklari ve localization parite testi icin iki Kotlin string katalog fixture'i
- `flutter_sdk.tar.gz`: Flutter SDK ve engine cache
- `pub_cache.tar.gz`: Pub hosted paket cache'i
- `gradle_cache.tar.gz`: Gradle wrapper/module cache'i
- `maven_local_repo.tar.gz`: Hardened signaling/bot build'inin air-gapped Maven deposu
- `android_sdk_build.tar.gz`: Android SDK build subset'i (`platforms/android-34`, `platforms/android-35`, `platforms/android-36`, `build-tools/36.0.0`, `ndk/28.2.13676358`, licenses)
- `app-debug.apk`: Bu ortamda uretilen debug APK, varsa
- `app-release-unsigned.apk`: Bu ortamda uretilen release APK; dagitim anahtariyla imzalanmamistir
- `FILES.txt`: Bundle dosya ve byte boyutu listesi
- `SHA256SUMS.txt`: Tum teslim artefaktlarinin SHA-256 ozeti

Airgapped ortamda:

```bash
tar -xzf flutter_sdk.tar.gz -C /opt
tar -xzf pub_cache.tar.gz -C "$HOME"
tar -xzf gradle_cache.tar.gz -C "$HOME"
mkdir -p "$HOME/Android/Sdk"
tar -xzf android_sdk_build.tar.gz -C "$HOME/Android/Sdk"
tar -xzf flutter_securechat_source.tar.gz
cd flutter_securechat
mkdir -p server_hardened/local-repo
tar -xzf ../maven_local_repo.tar.gz -C server_hardened/local-repo
export FLUTTER_ROOT=/opt/flutter-sdk
export PATH="$FLUTTER_ROOT/bin:$PATH"
export PUB_CACHE="$HOME/.pub-cache"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export GRADLE_USER_HOME="$HOME/.gradle"
flutter config --android-sdk "$ANDROID_HOME"
flutter pub get --offline
flutter test
printf 'sdk.dir=%s\nflutter.sdk=%s\n' "$ANDROID_HOME" "$FLUTTER_ROOT" > android/local.properties
cd android
./gradlew assembleDebug --offline
./gradlew assembleRelease --offline
cd ../server_hardened
./gradlew :signaling-server:test :bot-api:test --offline --no-daemon
```

Gradle wrapper dagitimlari `distributionSha256Sum` ile, Android ve hardened
server Maven artefaktlari ise `gradle/verification-metadata.xml` icindeki
SHA-256 kayitlariyla fail-closed dogrulanir. `pubspec.lock` hosted Pub
artefaktlarinin SHA-256 ozetlerini tasir.

`app-release-unsigned.apk` dogrudan magaza dagitimi icin degildir. Air-gapped
ortamda kuruma ait Android release keystore/signing ayarlariyla yeniden
imzalanmalidir.

iOS build icin macOS + Xcode + CocoaPods/SwiftPM cache gerekir. Bu Linux ortaminda iOS archive uretilemez; Apple signing/provisioning ve PushKit entitlement bu bundle'a dahil degildir.

Uyari: `flutter_sdk.tar.gz` Linux host icindir. macOS'ta iOS build icin bunu
kullanmayin; ayni Flutter surumunun macOS/Apple Silicon SDK'sini kurup
`docs/MACOS_IOS_BUILD.md` adimlariyla ayri iOS cache supplement'i uretin.
EOF

(
  cd "$OUT"
  find . -maxdepth 1 -type f \
    ! -name 'FILES.txt' \
    ! -name 'SHA256SUMS.txt' \
    -printf '%f %s bytes\n' | sort > FILES.txt
  find . -maxdepth 1 -type f \
    ! -name 'SHA256SUMS.txt' \
    -printf '%f\0' | sort -z | xargs -0 sha256sum > SHA256SUMS.txt
)

echo "[bundle] wrote $OUT"
