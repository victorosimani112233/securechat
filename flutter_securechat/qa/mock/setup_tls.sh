#!/usr/bin/env bash
# Mock sunucu icin TLS sertifikasi uretir ve pin degerlerini yazar.
#
# NEDEN GEREKLI: uygulama `https`/`wss` disini kabul etmiyor
# (`lib/src/config/app_config.dart`, fail-closed) ve baglantiyi kendi
# SPKI pin dogrulamasiyla kuruyor. Yani mock sunucu TLS konusmak zorunda ve
# istemciye o sertifikanin pin'i verilmeli.
#
# Sertifikalar ve ozel anahtarlar `.gitignore`'da: depoya girmemeleri gerek.
# Bu betik onlari yeniden uretilebilir kiliyor.
#
# Kullanim:
#   ./qa/mock/setup_tls.sh 192.168.1.42     # telefondan erisim icin LAN adresi
#   ./qa/mock/setup_tls.sh 127.0.0.1        # yalniz ayni makineden
set -euo pipefail

host="${1:-}"
[[ -n "$host" ]] || {
  echo "Kullanim: $0 <ip-veya-hostname>" >&2
  echo >&2
  echo "Telefondan baglanacaksan Mac'in LAN adresini ver:" >&2
  echo "  ipconfig getifaddr en0" >&2
  exit 2
}

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tls_directory="$script_directory/tls"
mkdir -p "$tls_directory"

# SAN zorunlu: yalnizca CN yazan sertifikalari modern TLS yiginlari
# reddediyor. IP adresi icin `IP:`, ad icin `DNS:` girdisi gerekiyor.
if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  subject_alt="IP:$host"
else
  subject_alt="DNS:$host"
fi

# Var olan sertifika ayni host icinse DOKUNMA.
#
# Her kosumda yeniden uretmek pin'i degistiriyor. Uygulama pin'i derleme
# aninda gomuyor; sertifika sonradan yenilenirse uygulamadaki pin eskiyor ve
# baglanti "baglanti kurulamadi" diye sessizce dusuyor — sebebi hicbir yerde
# gorunmuyor. Yeniden uretmek icin FORCE=1 verin.
# `-addext` sozdizimi `IP:1.2.3.4`, ama `x509 -text` ciktisi
# `IP Address:1.2.3.4` yaziyor. Ikisini birbirine cevirmeden yapilan
# karsilastirma HER ZAMAN basarisiz oluyor ve sertifika sessizce yeniden
# uretiliyordu — yani pin her kosumda degisiyordu.
matches_host() {
  local certificate="$tls_directory/$1.cert.pem"
  [[ -f "$certificate" ]] || return 1
  local printed="${subject_alt/IP:/IP Address:}"
  openssl x509 -in "$certificate" -noout -text 2>/dev/null \
    | grep -q "$printed"
}

generate() {
  local name="$1"
  local certificate="$tls_directory/$name.cert.pem"
  local key="$tls_directory/$name.key.pem"

  if [[ "${FORCE:-0}" != "1" ]] && matches_host "$name"; then
    echo "Var olan sertifika kullaniliyor: $name ($subject_alt)"
    return
  fi

  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$key" -out "$certificate" \
    -days 365 -subj "/CN=$host" \
    -addext "subjectAltName=$subject_alt" \
    2>/dev/null
  chmod 600 "$key"

  # Pin, sertifikanin degil PUBLIC KEY'inin (SPKI) SHA-256'si. Sertifika
  # yenilendiginde ayni anahtar kullanilirsa pin degismez; istemciyi
  # guncellemeden sertifika yenileyebilmenin yolu bu.
  openssl x509 -in "$certificate" -pubkey -noout \
    | openssl pkey -pubin -outform der \
    | openssl dgst -sha256 -binary \
    | openssl enc -base64 > "$tls_directory/$name.pin"
}

generate primary
# Yedek pin ayri bir anahtar: birincil anahtar ele gecerse ya da
# degistirilmesi gerekirse istemci guncellemesi beklemeden gecilebilsin.
generate backup

primary_pin="$(cat "$tls_directory/primary.pin")"
backup_pin="$(cat "$tls_directory/backup.pin")"
port="${MOCK_PORT:-8443}"

cat <<INFO

Sertifikalar hazir: $tls_directory
  host/SAN : $host ($subject_alt)
  primary  : $primary_pin
  backup   : $backup_pin

1) Sunucuyu baslat (ayri bir terminalde, depo kokunde):

   dart run qa/mock/bin/server.dart \\
     --port $port \\
     --cert qa/mock/tls/primary.cert.pem \\
     --key qa/mock/tls/primary.key.pem \\
     --state qa/mock/state

2) Uygulamayi cihaza kur:

   flutter run --debug \\
     --dart-define=SECURECHAT_API_BASE_URL=https://$host:$port \\
     --dart-define=SECURECHAT_SIGNALING_URL=wss://$host:$port \\
     --dart-define=SECURECHAT_CERT_PIN_HOST=$host \\
     --dart-define=SECURECHAT_CERT_PIN_SHA256=$primary_pin \\
     --dart-define=SECURECHAT_CERT_PIN_SHA256_BACKUP=$backup_pin \\
     --dart-define=SECURECHAT_FIREBASE_IOS_APP_ID=1:791820453236:ios:989a9c79e4e79ec3685821

   Telefon ve Mac ayni Wi-Fi agdinda olmali.

3) E-posta dogrulama ekraninda OTP kodu: 123456
   Sunucu her adresi kabul eder, gercek mail gondermez.

INFO
