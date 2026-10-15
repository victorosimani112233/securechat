#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Bu gate Xcode gerektirdigi icin yalniz macOS uzerinde calisir." >&2
  exit 2
fi

for command_name in flutter dart xcodebuild xcrun plutil shasum cargo rustup nm; do
  command -v "$command_name" >/dev/null || {
    echo "Eksik arac: $command_name" >&2
    exit 2
  }
done

required_build_inputs=(
  SECURECHAT_FIREBASE_IOS_APP_ID
  SECURECHAT_API_BASE_URL
  SECURECHAT_SIGNALING_URL
  SECURECHAT_CERT_PIN_HOST
  SECURECHAT_CERT_PIN_SHA256
  SECURECHAT_CERT_PIN_SHA256_BACKUP
)
dart_defines=()
for name in "${required_build_inputs[@]}"; do
  value="${!name:-}"
  if [[ -z "$value" ]]; then
    echo "$name production iOS build girdisi olarak zorunludur." >&2
    exit 2
  fi
  dart_defines+=("--dart-define=$name=$value")
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
cd "$project_directory"

offline_mode="${IOS_OFFLINE:-0}"
if [[ "$offline_mode" == "1" ]]; then
  flutter pub get --offline
else
  flutter config --enable-swift-package-manager
  flutter precache --ios
  flutter pub get
fi

# Kripto cekirdegi (Rust) Xcode'da derlenmez: XCFramework'u once uret.
# Artifacts/ bos kalirsa SecureChatCrypto paketi cozumlenmez; eski bir
# artefakt kalirsa Dart'in bekledigi ABI ile uyusmayabilir.
SECURECHAT_OFFLINE="$offline_mode" tool/build_native_crypto.sh ios

resolved_live="$project_directory/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
resolved_lock="$project_directory/ios/Package.resolved.lock"
mkdir -p "$(dirname "$resolved_live")"

remote_package_refs="$(
  find ios/Flutter/ephemeral/Packages -type f -name Package.swift \
    -exec grep -lE '\.package[[:space:]]*\([^)]*(url:|id:)' {} + 2>/dev/null || true
)"

package_flags=()
if [[ "$offline_mode" == "1" ]]; then
  if [[ -n "$remote_package_refs" ]]; then
    if [[ ! -f "$resolved_lock" ]]; then
      echo "Remote Swift package var ancak ios/Package.resolved.lock yok." >&2
      exit 2
    fi
    cp "$resolved_lock" "$resolved_live"
    package_flags+=(
      -disableAutomaticPackageResolution
      -onlyUsePackageVersionsFromResolvedFile
    )
  else
    package_flags+=(-disableAutomaticPackageResolution)
  fi
  xcodebuild -resolvePackageDependencies \
    -project ios/Runner.xcodeproj \
    -scheme Runner \
    "${package_flags[@]}"
else
  xcodebuild -resolvePackageDependencies \
    -project ios/Runner.xcodeproj \
    -scheme Runner
  if [[ -f "$resolved_live" ]]; then
    cp "$resolved_live" "$resolved_lock"
  elif [[ -n "$remote_package_refs" ]]; then
    echo "Remote Swift package resolve edildi ancak Package.resolved uretilmedi." >&2
    exit 2
  fi
fi

if [[ -f "$resolved_lock" ]]; then
  dart tool/validate_swift_package_lock.dart "$resolved_lock"
  shasum -a 256 "$resolved_lock"
fi

dart tool/audit_ios_readiness.dart
plutil -lint ios/Runner/Info.plist
plutil -lint ios/Runner/Runner.entitlements
plutil -lint ios/Runner/PrivacyInfo.xcprivacy
if [[ "${IOS_SKIP_FLUTTER_CHECKS:-0}" != "1" ]]; then
  # Kripto testleri host kutuphanesini (macOS'ta .dylib) arar; yoksa
  # sessizce degil ama ATLANIR. Gate'te atlanmasinlar.
  cargo_offline=()
  [[ "$offline_mode" == "1" ]] && cargo_offline=(--offline)
  ( cd native/securechat_crypto && cargo build --release --locked ${cargo_offline[@]+"${cargo_offline[@]}"} )
  flutter analyze
  flutter test
fi
flutter build ios --release --no-codesign \
  "${dart_defines[@]}"

# Dart kripto cekirdegini dlsym ile arar; derleme simgeler olmadan da gecer
# ve uygulama ancak ilk sifreleme cagrisinda coker. Her C ABI simgesi ana
# ikilide disa acik olmali.
runner_binary="build/ios/iphoneos/Runner.app/Runner"
expected_symbols="$(grep -oE 'sc_[a-z_0-9]+[[:space:]]*\(' \
  native/securechat_crypto/include/securechat_crypto.h | tr -d ' (' | sort -u)"
exported_symbols="$(nm -gU "$runner_binary" | awk '{print $NF}' \
  | sed -n 's/^_\(sc_[a-z_0-9]*\)$/\1/p' | sort -u)"
missing_symbols="$(comm -23 <(echo "$expected_symbols") <(echo "$exported_symbols"))"
if [[ -n "$missing_symbols" ]]; then
  echo "Kripto cekirdegi simgeleri Runner ikilisinde yok:" >&2
  echo "$missing_symbols" >&2
  exit 1
fi
echo "Kripto cekirdegi: $(echo "$expected_symbols" | wc -l | tr -d ' ') simge Runner'da."

# Simulator adi Xcode surumune gore degisir: her Xcode kendi cihaz
# kumesiyle gelir ve eski model adlari kaybolur. Sabit bir ad ("iPhone 16
# Pro") yazmak, gate'i Xcode yukseltmesinde kiriyordu — ustelik hatasi
# "Unable to find a device matching the provided destination" oldugu icin
# sorunun simulator adi oldugu anlasilmiyordu.
#
# IOS_SIMULATOR_NAME verilirse o kullanilir; verilmezse kurulu olanlardan
# ilki secilir. Runner XCTest'i cihaz modelinden bagimsiz oldugu icin
# hangisi oldugu onemli degil, VAR OLMASI onemli.
if [[ -n "${IOS_SIMULATOR_NAME:-}" ]]; then
  simulator_name="$IOS_SIMULATOR_NAME"
else
  # `simctl list devices available` yalniz calistirilabilir cihazlari
  # listeler; runtime'i indirilmemis olanlar bu listede yer almaz.
  simulator_name="$(
    xcrun simctl list devices available 2>/dev/null \
      | sed -nE 's/^[[:space:]]+(iPhone[^(]*[^ (])[[:space:]]+\([0-9A-F-]{36}\).*/\1/p' \
      | head -1
  )"
  if [[ -z "$simulator_name" ]]; then
    echo "Kurulu iPhone simulatoru yok; Runner XCTest kosulamaz." >&2
    echo "Xcode > Settings > Components uzerinden bir iOS Simulator" >&2
    echo "runtime'i indirin, ya da elinizdeki .dmg icin:" >&2
    echo "  xcodebuild -importPlatform <iOS_Simulator_Runtime.dmg>" >&2
    echo "Belirli bir cihaz kullanmak icin: IOS_SIMULATOR_NAME=\"...\"" >&2
    exit 2
  fi
fi
echo "Simulator: $simulator_name  (Xcode $(xcodebuild -version | head -1 | awk '{print $2}'))"
if [[ "$offline_mode" == "1" ]]; then
  xcodebuild test \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,OS=latest,name=$simulator_name" \
    "${package_flags[@]}" \
    CODE_SIGNING_ALLOWED=NO
else
  xcodebuild test \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -sdk iphonesimulator \
    -destination "platform=iOS Simulator,OS=latest,name=$simulator_name" \
    CODE_SIGNING_ALLOWED=NO
fi

if [[ "${IOS_SIGNED_BUILD:-0}" == "1" ]]; then
  flutter build ipa --release \
    "${dart_defines[@]}"
fi

echo "iOS release compile ve Runner XCTest gate basarili."
