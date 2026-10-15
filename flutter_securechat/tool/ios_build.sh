#!/usr/bin/env bash
# Mac'te iOS derlemesini tek komutla hazirlar ve kosturur (2026-10-15).
#
# Elle yapilacak adimlarin hepsi burada: depoyu main'e getirme, Xcode
# dizini, Rust ve iOS hedefleri, testler icin SQLCipher, canli sunucu
# girdileri, kripto cekirdegi ve derleme.
#
# Kullanim:
#   ./tool/ios_build.sh                       # tam kapi: test + release derleme + simulator XCTest
#   ./tool/ios_build.sh install               # bagli iPhone'a canli sunucuyla kur
#   ./tool/ios_build.sh install --personal X  # ucretsiz Apple ID: bundle ID'ye .X eki, push kapali
#
# Ortam:
#   SKIP_GIT_UPDATE=1   depoya dokunma (main'e gecme / pull yok)
#   IOS_SIMULATOR_NAME  kapi icin belirli simulator
#   IOS_BUILD_NO_UPLOAD=1  hata kaydini GitHub'a gonderme
#
# Hata olursa tum cikti `ios-build-logs` dalina `logs/<zaman>-<mod>-<commit>.txt`
# olarak gonderilir (main'e dokunmaz); Linux tarafi oradan okur:
#   git fetch github-codemagic ios-build-logs && git show FETCH_HEAD:logs/<dosya>
#
# Bu derleme `com.securechat.app` kimligiyle cikar: deneme icindir, hicbir
# magazaya yuklenmez. Ilk yukleme `com.elcim.app` ile olacak.
set -euo pipefail

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[32m    OK\033[0m %s\n' "$1"; }
die()  { printf '\033[31m    HATA\033[0m %s\n' "$1" >&2; exit 1; }
note() { printf '         %s\n' "$1"; }

[[ "$(uname -s)" == "Darwin" ]] || die "Bu betik macOS icin."

original_args=("$@")
mode="gate"
personal_suffix=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    install) mode="install" ;;
    gate) mode="gate" ;;
    --personal)
      [[ $# -ge 2 ]] || die "--personal bir ek ister, ornek: --personal grj"
      personal_suffix="$2"
      shift
      ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) die "Bilinmeyen arguman: $1  (yardim: $0 --help)" ;;
  esac
  shift
done
[[ -z "$personal_suffix" || "$mode" == "install" ]] \
  || die "--personal yalniz install ile kullanilir."

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
cd "$project_directory"

# Canli sunucu (185.22.184.114). Pinler sunucunun sundugu sertifikanin ve
# yedek anahtarin SPKI ozetleri; Android release ile ayni degerler.
export SECURECHAT_FIREBASE_IOS_APP_ID="${SECURECHAT_FIREBASE_IOS_APP_ID:-1:791820453236:ios:989a9c79e4e79ec3685821}"
export SECURECHAT_API_BASE_URL="${SECURECHAT_API_BASE_URL:-https://185.22.184.114}"
export SECURECHAT_SIGNALING_URL="${SECURECHAT_SIGNALING_URL:-wss://185.22.184.114}"
export SECURECHAT_CERT_PIN_HOST="${SECURECHAT_CERT_PIN_HOST:-185.22.184.114}"
export SECURECHAT_CERT_PIN_SHA256="${SECURECHAT_CERT_PIN_SHA256:-HiU372IT5EOlaX+olSXZOLLwzzl2n8GVydF3eVeLLd0=}"
export SECURECHAT_CERT_PIN_SHA256_BACKUP="${SECURECHAT_CERT_PIN_SHA256_BACKUP:-4oaRg+Six29KZ2tcFLyoYT+FKUZhYPzp1pI5BoK5RI4=}"

signing_files=(ios/Runner/Runner.entitlements ios/Runner.xcodeproj/project.pbxproj)

# `origin` Mac'te LAN adresini gosterebilir; yalniz GitHub kullanilir.
github_remote() {
  local remote
  remote="$(git remote -v | awk '/victorosimani112233\/securechat/ {print $1; exit}')"
  if [[ -z "$remote" ]]; then
    remote="github"
    git remote add "$remote" https://github.com/victorosimani112233/securechat.git
  fi
  echo "$remote"
}

# --- Hata kaydi ---------------------------------------------------------------
# Tum cikti hem ekrana hem dosyaya yazilir. Betik hatayla biterse kayit
# `ios-build-logs` dalina ayri bir commit olarak gonderilir. Calisma agaci,
# index ve main'e dokunulmaz: commit gecici bir index ile kurulur.
log_directory="${TMPDIR:-/tmp}/securechat-ios-build"
mkdir -p "$log_directory"
log_file="$log_directory/$(date +%Y%m%d-%H%M%S)-$mode.txt"
exec 3>&1 4>&2
exec > >(tee -a "$log_file") 2>&1
{
  echo "# ios_build.sh ${original_args[*]+${original_args[*]}} (mod: $mode)"
  echo "# baslangic $(date '+%Y-%m-%d %H:%M:%S %z'), $(sw_vers -productName 2>/dev/null) $(sw_vers -productVersion 2>/dev/null), $(uname -m)"
  echo "# commit $(git rev-parse --short HEAD 2>/dev/null) dal $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
} >> "$log_file"

upload_log() {
  local remote branch="ios-build-logs" parent="" name blob tree commit index_dir
  remote="$(github_remote)" || return 1
  name="logs/$(basename "$log_file" .txt)-$(git rev-parse --short HEAD).txt"
  if git fetch --quiet "$remote" "$branch" 2>/dev/null; then
    parent="$(git rev-parse FETCH_HEAD)"
  fi
  blob="$(git hash-object -w "$log_file")" || return 1
  index_dir="$(mktemp -d)"
  (
    export GIT_INDEX_FILE="$index_dir/index"
    if [[ -n "$parent" ]]; then git read-tree "$parent"; else git read-tree --empty; fi
    git update-index --add --cacheinfo "100644,$blob,$name"
    git write-tree
  ) > "$index_dir/tree" || { rm -rf "$index_dir"; return 1; }
  tree="$(cat "$index_dir/tree")"
  rm -rf "$index_dir"
  commit="$(
    GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-$(git config user.name || echo ios-build)}" \
    GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-$(git config user.email || echo ios-build@localhost)}" \
    GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$(git config user.name || echo ios-build)}" \
    GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$(git config user.email || echo ios-build@localhost)}" \
    git commit-tree "$tree" ${parent:+-p "$parent"} -m "log: ios_build.sh $mode failed ($(git rev-parse --short HEAD))"
  )" || return 1
  git push --quiet "$remote" "$commit:refs/heads/$branch" || return 1
  echo "$name"
}

on_exit() {
  local status=$?
  # tee'ye giden boruyu kapat ve kaydin diske yazilmasini bekle.
  exec 1>&3 2>&4
  sleep 1
  [[ $status -eq 0 ]] && return
  echo "# cikis kodu $status, $(date '+%H:%M:%S')" >> "$log_file"
  echo
  echo "Kayit: $log_file"
  if [[ "${IOS_BUILD_NO_UPLOAD:-0}" == "1" ]]; then
    return
  fi
  local uploaded
  if uploaded="$(upload_log 2>&1 | tail -1)" && [[ "$uploaded" == logs/* ]]; then
    printf '\033[33m    Hata kaydi GitHub ios-build-logs dalina gonderildi: %s\033[0m\n' "$uploaded"
    echo "         Claude'a \"kayda bak\" demen yeterli."
  else
    echo "    Kayit GitHub'a gonderilemedi ($uploaded). Dosyayi elle gonderin: $log_file"
  fi
}
trap on_exit EXIT

# --- 1. Depo ----------------------------------------------------------------
step "Depo"
if [[ "${SKIP_GIT_UPDATE:-0}" == "1" ]]; then
  ok "atlandi (SKIP_GIT_UPDATE=1) — $(git rev-parse --abbrev-ref HEAD) $(git rev-parse --short HEAD)"
else
  # Bu iki dosyadaki yerel degisiklikler kisisel imza betiginin ya da
  # Xcode'un yazdigi takim ayaridir ve atilabilir (Flutter takimi
  # anahtar zincirindeki gelistirici sertifikasindan kendisi bulur).
  # Baska bir degisiklik varsa kullanicinin isini ezmemek icin dur.
  if [[ -n "$(git status --porcelain -- "${signing_files[@]}")" ]]; then
    git checkout -- "${signing_files[@]}"
    note "onceki kisisel imza ayari geri alindi"
  fi
  dirty="$(git status --porcelain --untracked-files=no)"
  if [[ -n "$dirty" ]]; then
    echo "$dirty" >&2
    die "Depoda commitlenmemis degisiklik var; ezmemek icin durdum.
         Saklamak icin: git stash   — sonra betigi tekrar calistirin."
  fi
  remote="$(github_remote)"
  git fetch --prune --quiet "$remote" main || die "GitHub'dan cekilemedi ($remote). Ag/kimlik bilgisini kontrol edin."
  upstream="$remote/main"
  if [[ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]]; then
    if git show-ref --verify --quiet refs/heads/main; then
      git checkout --quiet main
    else
      git checkout --quiet -b main --track "$upstream"
    fi
  fi
  before="$(git rev-parse HEAD)"
  git merge --ff-only --quiet "$upstream" \
    || die "main, $upstream ile ileri sarilamiyor (yerel commit var). Elle bakin."
  ok "main $(git rev-parse --short HEAD) ($upstream ile ayni)"
  # Betigin kendisi guncellendiyse yeni surumu kostur; eski surum yeni
  # depoda yanlis adimlar atabilir.
  if ! git diff --quiet "$before" HEAD -- tool/ios_build.sh; then
    note "betik guncellendi, yeni surumle yeniden baslatiliyor"
    trap - EXIT
    exec 1>&3 2>&4
    sleep 1
    rm -f "$log_file"
    SKIP_GIT_UPDATE=1 exec "$script_directory/ios_build.sh" ${original_args[@]+"${original_args[@]}"}
  fi
fi

# --- 2. Xcode ---------------------------------------------------------------
step "Xcode"
developer_directory="$(xcode-select -p 2>/dev/null || true)"
if [[ "$developer_directory" != *Xcode*.app* ]]; then
  xcode_app="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
  [[ -n "$xcode_app" ]] || die "Xcode bulunamadi. App Store'dan kurun."
  note "aktif dizin $developer_directory — Xcode'a cevriliyor (parola sorabilir)"
  sudo xcode-select -s "$xcode_app/Contents/Developer"
fi
xcodebuild -version >/dev/null 2>&1 || {
  note "Xcode lisansi kabul edilmemis olabilir (parola sorabilir)"
  sudo xcodebuild -license accept
}
ok "$(xcodebuild -version | head -1)"
xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1 \
  || die "iPhoneOS SDK yok. Calistirin: xcodebuild -downloadPlatform iOS"
ok "iPhoneOS SDK"

# --- 3. Flutter -------------------------------------------------------------
step "Flutter"
if ! command -v flutter >/dev/null && [[ -x "$HOME/securechat-dev/flutter/bin/flutter" ]]; then
  export PATH="$HOME/securechat-dev/flutter/bin:$PATH"
fi
command -v flutter >/dev/null || die "flutter bulunamadi (PATH'e ekleyin)."
ok "$(flutter --version 2>/dev/null | head -1)"
flutter config --enable-swift-package-manager >/dev/null

# --- 4. Rust ----------------------------------------------------------------
# Sifreleme cekirdegi Rust; Xcode onu derlemez.
step "Rust"
if [[ -f "$HOME/.cargo/env" ]]; then source "$HOME/.cargo/env"; fi
if ! command -v rustup >/dev/null; then
  note "rustup kuruluyor"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --no-modify-path
  source "$HOME/.cargo/env"
fi
rustup target add aarch64-apple-ios aarch64-apple-ios-sim >/dev/null
ok "$(rustc --version), hedefler aarch64-apple-ios(-sim)"

# --- 5. Calistir ------------------------------------------------------------
if [[ "$mode" == "gate" ]]; then
  # `flutter test` ana makinede gercek bir sifreli veritabani acar.
  step "SQLCipher (yalniz testler)"
  sqlcipher=""
  for candidate in "${SECURECHAT_SQLCIPHER_PATH:-}" \
      /opt/homebrew/lib/libsqlcipher.dylib \
      /opt/homebrew/opt/sqlcipher/lib/libsqlcipher.dylib \
      /usr/local/lib/libsqlcipher.dylib \
      /usr/local/opt/sqlcipher/lib/libsqlcipher.dylib \
      "$HOME/.securechat/lib/libsqlcipher.dylib"; do
    if [[ -n "$candidate" && -f "$candidate" ]]; then sqlcipher="$candidate"; break; fi
  done
  if [[ -z "$sqlcipher" ]]; then
    note "bulunamadi; depodaki kaynaktan derleniyor"
    ./tool/build_sqlcipher_macos.sh >/dev/null
    sqlcipher="$HOME/.securechat/lib/libsqlcipher.dylib"
    [[ -f "$sqlcipher" ]] || die "SQLCipher derlenemedi: ./tool/build_sqlcipher_macos.sh"
  fi
  export SECURECHAT_SQLCIPHER_PATH="$sqlcipher"
  ok "$sqlcipher"

  step "iOS kapisi (analiz, testler, release derleme, simulator XCTest)"
  ./tool/verify_ios_on_macos.sh
  exit 0
fi

if [[ -n "$personal_suffix" ]]; then
  step "Kisisel imza (.$personal_suffix)"
  ./tool/ios_personal_signing.sh "$personal_suffix" >/dev/null
  ok "bundle ID com.securechat.app.$personal_suffix, push kapali (bildirim gelmez)"
  note "Bu degisiklikleri commitlemeyin; betigin bir sonraki kosusu geri alir."
fi

step "Cihaz"
device="$(flutter devices --machine 2>/dev/null | python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)
except Exception:
    devices = []
for d in devices:
    if d.get("targetPlatform", "").startswith("ios") and not d.get("emulator", False):
        print(d["id"]); break
' || true)"
[[ -n "$device" ]] || die "Bagli iPhone yok. USB ile baglayin, telefonda 'Guven' deyin,
         Ayarlar > Gizlilik ve Guvenlik > Gelistirici Modu acik olmali."
ok "$device"

step "Paketler ve kripto cekirdegi"
flutter pub get >/dev/null
./tool/build_native_crypto.sh ios
ok "SecureChatCrypto.xcframework hazir"

step "Release derleme (canli sunucu)"
if ! flutter build ios --release \
    --dart-define=SECURECHAT_API_BASE_URL="$SECURECHAT_API_BASE_URL" \
    --dart-define=SECURECHAT_SIGNALING_URL="$SECURECHAT_SIGNALING_URL" \
    --dart-define=SECURECHAT_CERT_PIN_HOST="$SECURECHAT_CERT_PIN_HOST" \
    --dart-define=SECURECHAT_CERT_PIN_SHA256="$SECURECHAT_CERT_PIN_SHA256" \
    --dart-define=SECURECHAT_CERT_PIN_SHA256_BACKUP="$SECURECHAT_CERT_PIN_SHA256_BACKUP" \
    --dart-define=SECURECHAT_FIREBASE_IOS_APP_ID="$SECURECHAT_FIREBASE_IOS_APP_ID"; then
  cat >&2 <<HELP

Derleme basarisiz. Hata "Signing" / "Development Team" / "provisioning"
iceriyorsa takim secilmemis demektir:
  open ios/Runner.xcworkspace
  Runner > Signing & Capabilities > Team secin, Xcode'u kapatin,
  betigi tekrar calistirin. Ucretsiz Apple ID ise ya da hata bundle ID'nin
  kullanilamadigini soyluyorsa: $0 install --personal <ek>
Baska bir hataysa ciktiyi gonderin.
HELP
  exit 1
fi

# Dart cekirdegi dlsym ile arar: simge eksikse derleme gecer, uygulama ilk
# sifrelemede coker. Kurmadan once denetle.
runner_binary="build/ios/iphoneos/Runner.app/Runner"
expected_symbols="$(grep -oE 'sc_[a-z_0-9]+[[:space:]]*\(' \
  native/securechat_crypto/include/securechat_crypto.h | tr -d ' (' | sort -u)"
exported_symbols="$(nm -gU "$runner_binary" | awk '{print $NF}' \
  | sed -n 's/^_\(sc_[a-z_0-9]*\)$/\1/p' | sort -u)"
missing_symbols="$(comm -23 <(echo "$expected_symbols") <(echo "$exported_symbols"))"
[[ -z "$missing_symbols" ]] || die "Kripto cekirdegi simgeleri Runner'da yok:
$missing_symbols"
ok "kripto cekirdegi: $(echo "$expected_symbols" | wc -l | tr -d ' ') simge Runner'da"

step "iPhone'a kurulum"
flutter install --release -d "$device"
ok "kuruldu"
cat <<INFO

Telefonda ilk acilista "Guvenilmeyen gelistirici" cikarsa:
  Ayarlar > Genel > VPN ve Cihaz Yonetimi > gelistirici hesabi > Guven
QA hesaplariyla (Android telefonlardaki numaralar) giris yapmayin; hesap
o telefonlardan bu iPhone'a gecer.
INFO
