#!/usr/bin/env bash
# Test dagitimi icin gereken secret dosyalarini uretir.
#
# Deploy preflight'i her secret dosyasinin mutlak yol, regular dosya,
# <=64 KiB, group/world izni kapali ve **birbirinden farkli** olmasini
# dogrular. Elle uretimde en sik yapilan hata ayni degeri iki amaca vermek
# oldugu icin butun degerler burada bagimsiz rastgele uretilir.
#
# Uretmedigi uc girdi vardir, cunku disaridan gelirler:
#   - smtp_password            (e-posta saglayicin)
#   - firebase_service_account (Firebase konsolundan inen JSON)
set -euo pipefail

target="${1:-}"
if [[ -z "$target" ]]; then
  echo "kullanim: $0 <secret-dizini>" >&2
  exit 2
fi
[[ "$target" == /* ]] || { echo "dizin mutlak yol olmali" >&2; exit 2; }

command -v openssl >/dev/null 2>&1 || { echo "openssl gerekli" >&2; exit 2; }

install -d -m 0700 "$target"

# Var olan bir dosyanin uzerine yazmak, hala kullanimda olan bir anahtari
# sessizce kaybetmek demektir.
for existing in "$target"/*; do
  [[ -e "$existing" ]] || continue
  echo "dizin bos degil: $existing" >&2
  exit 2
done

# 32 rastgele byte, base64. PRIVACY_INDEX_KEY gibi girdiler decode sonrasi
# tam 32 byte ister; JWT/TURN gibi girdiler ise en az 32 UTF-8 byte ve
# yeterli sembol cesitliligi ister. Base64(32 byte) ikisini de karsilar.
new_key() {
  openssl rand -base64 32 | tr -d '\n' > "$target/$1"
  chmod 0600 "$target/$1"
}

for name in \
  database_password \
  redis_password \
  turn_secret \
  jwt_secret \
  privacy_index_key \
  offline_queue_key \
  fcm_token_key \
  metrics_token \
  directory_hsm_pin
do
  new_key "$name"
done

# Butun degerlerin gercekten farkli oldugunu burada dogrula; preflight'ta
# ogrenmek yerine uretim aninda yakala.
duplicates="$(sha256sum "$target"/* | awk '{print $1}' | sort | uniq -d)"
[[ -z "$duplicates" ]] || { echo "ayni degere sahip iki secret uretildi" >&2; exit 1; }

cat <<EOF
Secret dosyalari yazildi: $target

Uretilenler (0600):
$(cd "$target" && ls -1 | sed 's/^/  /')

Hala elle konmasi gerekenler:
  smtp_password             e-posta saglayicinin SMTP sifresi
  firebase_service_account  Firebase konsolundan inen JSON

directory_hsm_pin degeri SoftHSM token'i olustururken --pin olarak
kullanilacak ayni deger olmalidir.
EOF
