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
#   - sealed sender ucusu      (cevrimdisi makinede SealedSenderOfflineKeygen)
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
  janus_api_secret \
  janus_admin_secret \
  bot_master_key \
  bot_queue_key \
  bot_admin_token \
  bot_metrics_token \
  directory_hsm_pin
do
  new_key "$name"
done

# Bot servis kimligi: Ed25519 PKCS#8 private + X.509 public, base64 tek satir.
# Deploy preflight ciftin gercekten eslestigini openssl ile dogrular.
tmp_key="$(mktemp)"
trap 'rm -f -- "$tmp_key"' EXIT
openssl genpkey -algorithm Ed25519 -outform DER -out "$tmp_key" 2>/dev/null
base64 -w0 < "$tmp_key" > "$target/bot_service_private_key"
openssl pkey -inform DER -in "$tmp_key" -pubout -outform DER 2>/dev/null |
  base64 -w0 > "$target/bot_service_public_key"
chmod 0600 "$target/bot_service_private_key" "$target/bot_service_public_key"

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
  sealed_sender_server_certificate    ) cevrimdisi makinede
  sealed_sender_trust_root_public_key ) SealedSenderOfflineKeygen
  sealed_sender_server_private_key    ) ciktisindan kopyala

directory_hsm_pin degeri SoftHSM token'i olustururken --pin olarak
kullanilacak ayni deger olmalidir.
EOF
