#!/usr/bin/env bash
# Elcim kripto cekirdegini (native/securechat_crypto) teslim hedeflerine
# derler ve artefaktlari depoya vendor'lar.
#
# Android uc ABI icin paylasimli kutuphane uretir; `jniLibs` AGP'nin
# varsayilan yolu oldugu icin ayrica Gradle yapilandirmasi gerekmez.
#
# iOS icin cihaz ve simulator statik kutuphanelerini birlestirip bir
# XCFramework uretir. Bu adim YALNIZ macOS'ta kosar: Xcode toolchain'i
# olmadan Apple hedefleri baglanamaz. Linux'ta Android kismi kosar ve iOS
# kismi atlanir.
#
# NEDEN ARTEFAKTLAR DEPODA: proje bagimliliklari vendor'luyor
# (`local-repo/` altindaki AAR'lar, `ios/SQLCipher/Sources` altindaki
# amalgamation). Ciktilari depoya koymazsak `flutter build apk` scripti
# kosmayi unutan herkeste kutuphanesiz bir APK uretir ve uygulama
# `DynamicLibrary.open` sirasinda cokerdi. Uretilebilirlik, kaydedilen
# SHA-256 toplamlari ve pinli `Cargo.lock` ile saglanir.
#
# Kullanim:
#   tool/build_native_crypto.sh              # butun hedefler
#   tool/build_native_crypto.sh android      # yalniz Android
#   SECURECHAT_OFFLINE=1 tool/build_native_crypto.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRATE_DIR="$PROJECT_DIR/native/securechat_crypto"
JNI_DIR="$PROJECT_DIR/android/app/src/main/jniLibs"
IOS_VENDOR_DIR="$PROJECT_DIR/ios/SecureChatCrypto/Artifacts"
LIB_NAME="libsecurechat_crypto"
TARGETS="${1:-all}"

CARGO_FLAGS=()
if [[ "${SECURECHAT_OFFLINE:-0}" == "1" ]]; then
  CARGO_FLAGS+=(--offline)
fi

log() { printf '\n== %s\n' "$*"; }
die() { printf 'HATA: %s\n' "$*" >&2; exit 1; }

command -v cargo >/dev/null 2>&1 || die "cargo bulunamadi (rustup kurulumu gerekli)"

# Cargo.lock'un sessizce kaymamasi gerekiyor: kripto cekirdeginin bagimlilik
# agaci pinli kalmali.
( cd "$CRATE_DIR" && cargo metadata --locked --format-version 1 >/dev/null ) \
  || die "Cargo.lock guncel degil; 'cargo update' kosup degisikligi inceleyin"

# ---------------------------------------------------------------------------
# Android
# ---------------------------------------------------------------------------
build_android() {
  command -v cargo-ndk >/dev/null 2>&1 \
    || die "cargo-ndk bulunamadi: cargo install cargo-ndk --locked"

  local ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
  if [[ -z "$ndk" ]]; then
    # Flutter'in kullandigi SDK yolundan en yuksek NDK'yi sec.
    local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
    ndk="$(find "$sdk/ndk" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V | tail -1)"
  fi
  [[ -n "$ndk" && -d "$ndk" ]] || die "NDK bulunamadi; ANDROID_NDK_HOME ayarlayin"
  export ANDROID_NDK_HOME="$ndk"
  log "NDK: $ANDROID_NDK_HOME"

  # ABI adlari Android'in jniLibs duzeniyle ayni olmali; cargo-ndk Rust
  # target'ina kendisi cevirir.
  local abis=(arm64-v8a armeabi-v7a x86_64)

  log "Android derlemesi: ${abis[*]}"
  (
    cd "$CRATE_DIR"
    cargo ndk \
      $(printf -- '-t %s ' "${abis[@]}") \
      -o "$JNI_DIR" \
      build --release ${CARGO_FLAGS[@]+"${CARGO_FLAGS[@]}"}
  )

  # Teslim edilen her native kutuphanede debug sembolu KALMAMALI:
  # `tool/audit_android_release.sh` bunu sart kosuyor ve bulursa release'i
  # reddediyor. `Cargo.toml` release profilinde `strip = true` var; burada
  # sonuc ayrica dogrulanir, cunku bir profil degisikligi sessizce gecmemeli.
  local readelf
  readelf="$(command -v llvm-readelf || command -v readelf)" \
    || die "readelf bulunamadi"

  local abi so
  for abi in "${abis[@]}"; do
    so="$JNI_DIR/$abi/$LIB_NAME.so"
    [[ -f "$so" ]] || die "uretilemedi: $so"
    if "$readelf" -SW "$so" \
      | awk '$2 ~ /^\.debug/ || $2 == ".symtab" { found=1 } END { exit !found }'
    then
      die "debug sembolu kaldi: $abi/$LIB_NAME.so"
    fi
    printf '  %-14s %6s KB\n' "$abi" "$(( $(stat -c%s "$so") / 1024 ))"
  done

  # Disa acilan C sembolleri gercekten var mi: bos bir kutuphane sessizce
  # teslim edilmesin.
  local nm
  nm="$(command -v llvm-nm || command -v nm)"
  "$nm" -D --defined-only "$JNI_DIR/arm64-v8a/$LIB_NAME.so" 2>/dev/null \
    | grep -q 'sc_abi_version' \
    || die "sc_abi_version sembolu bulunamadi; yanlis artefakt uretilmis olabilir"

  ( cd "$JNI_DIR" && find . -name "$LIB_NAME.so" -print0 \
      | sort -z | xargs -0 sha256sum > SHA256SUMS )
  log "Android tamam. Toplamlar: $JNI_DIR/SHA256SUMS"
}

# ---------------------------------------------------------------------------
# iOS — yalniz macOS
# ---------------------------------------------------------------------------
build_ios() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    log "iOS atlandi: Apple hedefleri icin macOS ve Xcode gerekir"
    return 0
  fi
  command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild bulunamadi"

  rustup target add aarch64-apple-ios aarch64-apple-ios-sim >/dev/null

  log "iOS derlemesi: cihaz + simulator"
  (
    cd "$CRATE_DIR"
    cargo build --release --target aarch64-apple-ios ${CARGO_FLAGS[@]+"${CARGO_FLAGS[@]}"}
    cargo build --release --target aarch64-apple-ios-sim ${CARGO_FLAGS[@]+"${CARGO_FLAGS[@]}"}
  )

  local device="$CRATE_DIR/target/aarch64-apple-ios/release/$LIB_NAME.a"
  local simulator="$CRATE_DIR/target/aarch64-apple-ios-sim/release/$LIB_NAME.a"
  [[ -f "$device" ]] || die "uretilemedi: $device"
  [[ -f "$simulator" ]] || die "uretilemedi: $simulator"

  # Basliklar XCFramework icin gerekli; C ABI'nin tek basligi elle tutulur.
  local headers="$CRATE_DIR/include"
  [[ -f "$headers/securechat_crypto.h" ]] \
    || die "baslik bulunamadi: $headers/securechat_crypto.h"

  rm -rf "$IOS_VENDOR_DIR/SecureChatCrypto.xcframework"
  mkdir -p "$IOS_VENDOR_DIR"
  xcodebuild -create-xcframework \
    -library "$device" -headers "$headers" \
    -library "$simulator" -headers "$headers" \
    -output "$IOS_VENDOR_DIR/SecureChatCrypto.xcframework"

  ( cd "$IOS_VENDOR_DIR" \
      && find SecureChatCrypto.xcframework -type f -print0 \
      | sort -z | xargs -0 shasum -a 256 > SHA256SUMS )
  log "iOS tamam: $IOS_VENDOR_DIR/SecureChatCrypto.xcframework"
}

case "$TARGETS" in
  android) build_android ;;
  ios)     build_ios ;;
  all)     build_android; build_ios ;;
  *)       die "bilinmeyen hedef: $TARGETS (android | ios | all)" ;;
esac

log "Bitti"
