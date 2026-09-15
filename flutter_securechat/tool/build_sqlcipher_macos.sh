#!/usr/bin/env bash
# Depodaki gomulu SQLCipher kaynagindan macOS icin bir kutuphane uretir.
#
# NE ZAMAN GEREKIR: `flutter test` ana makinede gercek bir sifreli veritabani
# aciyor ve bunun icin sistemde SQLCipher bulunmasi gerekiyor. Alisildik yol
# `brew install sqlcipher`, ama Homebrew kurulumu ag ister. Kisitli
# baglantida bu betik ayni isi indirme yapmadan yapar: kaynak zaten depoda
# (`ios/SQLCipher/`), derleyici zaten Xcode ile geliyor.
#
# iOS UYGULAMASINI ETKILEMEZ. Uygulama kendi gomulu kopyasini kullaniyor;
# burada uretilen dosya yalniz gelistirme makinesindeki testler icin.
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
readonly source_file="$project_directory/ios/SQLCipher/Sources/CSQLCipher/sqlite3.c"
readonly output_directory="${SECURECHAT_LIB_DIR:-$HOME/.securechat/lib}"
readonly output_file="$output_directory/libsqlcipher.dylib"

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "Bu betik macOS icin." >&2
  exit 2
}
[[ -f "$source_file" ]] || {
  echo "Gomulu kaynak yok: $source_file" >&2
  echo "./tool/vendor_sqlcipher.sh ile uretilebilir." >&2
  exit 1
}
command -v cc >/dev/null || {
  echo "Derleyici yok. Xcode Command Line Tools kurun:" >&2
  echo "  xcode-select --install" >&2
  exit 2
}

# Tanimlar ios/SQLCipher/Package.swift ile AYNI olmali. Ayrisirsa testler
# uygulamadan farkli bir SQLCipher davranisini sinar ve fark gec fark edilir.
# Guvenlik acisindan kritik olan ikisi: TEMP_STORE=2 (gecici tablolar diske
# duz metin yazilmaz) ve OMIT_LOAD_EXTENSION.
readonly defines=(
  # ZORUNLU: assert() govdeleri yalniz SQLITE_DEBUG tanimliyken var olan
  # alanlara basvuruyor. Amalgamation NDEBUG'i kendi tanimliyor ama
  # <assert.h> daha once dahil edilmisse gec kaliyor.
  -DNDEBUG=1
  -DSQLITE_HAS_CODEC
  -DSQLCIPHER_CRYPTO_CC
  -DSQLITE_TEMP_STORE=2
  -DSQLITE_THREADSAFE=1
  -DHAVE_USLEEP=1
  -DSQLITE_OMIT_LOAD_EXTENSION
)

mkdir -p "$output_directory"
echo "Derleniyor (birkac dakika surebilir)..."
cc -O2 -dynamiclib \
  "${defines[@]}" \
  -framework Security \
  -framework CoreFoundation \
  -o "$output_file" \
  "$source_file"

# Uretilen dosyanin gercekten SQLCipher oldugunu dogrula. Duz SQLite
# `PRAGMA cipher_version` icin HIC SATIR dondurmez; bu ayrim Dart tarafindaki
# `assertCipherAvailable` denetiminin de dayandigi olcut.
probe_directory="$(mktemp -d)"
trap 'rm -rf "$probe_directory"' EXIT
cat > "$probe_directory/probe.c" <<'PROBE'
#include <stdio.h>
#include "sqlite3.h"
int main(void) {
  sqlite3 *database;
  sqlite3_stmt *statement;
  if (sqlite3_open(":memory:", &database) != SQLITE_OK) return 1;
  if (sqlite3_prepare_v2(database, "PRAGMA cipher_version;", -1, &statement, 0)
      != SQLITE_OK) return 1;
  if (sqlite3_step(statement) != SQLITE_ROW) return 1;
  printf("%s\n", sqlite3_column_text(statement, 0));
  return 0;
}
PROBE
cc -O0 -o "$probe_directory/probe" "$probe_directory/probe.c" \
  -I "$project_directory/ios/SQLCipher/Sources/CSQLCipher/include" \
  "$output_file"
version="$("$probe_directory/probe")" || {
  echo "Uretilen kutuphane SQLCipher gibi davranmiyor." >&2
  exit 1
}

echo
echo "Hazir: $output_file"
echo "SQLCipher surumu: $version"
echo
echo "Kabuk oturumunuza tanitin (kalici olmasi icin ~/.zshrc icine yazin):"
echo
echo "  export SECURECHAT_SQLCIPHER_PATH=\"$output_file\""
echo
echo "Sonra:  flutter test"
