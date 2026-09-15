#!/usr/bin/env bash
# SQLCipher amalgamation'ini kaynaktan yeniden uretir.
#
# `ios/SQLCipher/Sources/CSQLCipher/` altindaki dosyalar depoya gomulu. Gomulu
# bir ikili/kaynak blob'un denetlenebilir olmasi icin nereden geldigi ve nasil
# uretildigi tekrar edilebilir olmali. Bu betik tam olarak onu yapar: ayni
# surum ve ayni saglama toplamiyla ayni dosyalari uretir.
#
# Kullanim:  ./tool/vendor_sqlcipher.sh [--check]
#   --check  Uretilen dosyalari depodakilerle KARSILASTIRIR, uzerine yazmaz.
set -euo pipefail

# Android tarafi `net.zetetic:sqlcipher-android:4.5.6` kullaniyor
# (android/app/build.gradle.kts). Iki platform ayni SQLCipher surumunde
# kalsin diye bu deger ona baglidir.
readonly SQLCIPHER_VERSION="4.5.6"
readonly SOURCE_SHA256="e4a527e38e67090c1d2dc41df28270d16c15f7ca5210a3e7ec4c4b8fda36e28f"
readonly SOURCE_URL="https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v${SQLCIPHER_VERSION}.tar.gz"

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
readonly vendor_directory="$project_directory/ios/SQLCipher/Sources/CSQLCipher"

check_only=0
if [[ "${1:-}" == "--check" ]]; then
  check_only=1
elif [[ $# -gt 0 ]]; then
  echo "Bilinmeyen argüman: $1" >&2
  exit 2
fi

for command_name in curl tar tclsh make gcc shasum; do
  command -v "$command_name" >/dev/null || {
    echo "Eksik araç: $command_name" >&2
    exit 2
  }
done

work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT

echo "SQLCipher $SQLCIPHER_VERSION indiriliyor..."
curl -sSL -o "$work_directory/source.tar.gz" "$SOURCE_URL"

actual_sha256="$(shasum -a 256 "$work_directory/source.tar.gz" | awk '{print $1}')"
if [[ "$actual_sha256" != "$SOURCE_SHA256" ]]; then
  echo "Kaynak arşivinin sha256 değeri beklenenden farklı." >&2
  echo "  beklenen: $SOURCE_SHA256" >&2
  echo "  bulunan : $actual_sha256" >&2
  exit 1
fi

tar xzf "$work_directory/source.tar.gz" -C "$work_directory"
cd "$work_directory/sqlcipher-$SQLCIPHER_VERSION"

# Şifreleme sağlayıcısı (CommonCrypto / OpenSSL) amalgamation üretilirken
# değil, derlenirken seçilir. Buradaki OpenSSL seçimi yalnızca configure'ün
# tamamlanması için; üretilen sqlite3.c her iki sağlayıcıyı da destekler.
echo "Amalgamation üretiliyor (birkaç dakika sürebilir)..."
./configure --enable-tempstore=yes CFLAGS="-DSQLITE_HAS_CODEC" LDFLAGS="-lcrypto" >/dev/null
make sqlite3.c >/dev/null

if [[ "$check_only" == "1" ]]; then
  status=0
  for name in sqlite3.c; do
    if ! cmp -s "$name" "$vendor_directory/$name"; then
      echo "FARKLI: $name" >&2
      status=1
    fi
  done
  for name in sqlite3.h sqlite3ext.h; do
    if ! cmp -s "$name" "$vendor_directory/include/$name"; then
      echo "FARKLI: include/$name" >&2
      status=1
    fi
  done
  if [[ "$status" == "0" ]]; then
    echo "Depodaki dosyalar SQLCipher $SQLCIPHER_VERSION kaynağıyla birebir aynı."
  fi
  exit "$status"
fi

cp sqlite3.c "$vendor_directory/sqlite3.c"
cp sqlite3.h sqlite3ext.h "$vendor_directory/include/"
echo "Güncellendi: $vendor_directory"
shasum -a 256 "$vendor_directory/sqlite3.c" "$vendor_directory/include/"*.h
