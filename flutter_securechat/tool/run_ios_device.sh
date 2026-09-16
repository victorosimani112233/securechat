#!/usr/bin/env bash
# Uygulamayi mock sunucuyla birlikte fiziksel bir iPhone'a kurar.
#
# NEDEN: bu akista birbirinden bagimsiz bes sey ayni anda dogru olmak
# zorunda ve herhangi biri yanlissa uygulama TEK bir mesaj veriyor:
# "baglanti kurulamadi". Sebep hicbir yerde gorunmuyor.
#
#   1. Sunucu calisiyor olmali
#   2. Sunucu LOOPBACK degil LAN adresinde dinlemeli
#   3. Guvenlik duvari baglantiyi gecirmeli
#   4. Sertifika LAN adresi icin uretilmis olmali
#   5. Uygulamaya gomulen PIN, sunucunun SUNDUGU sertifikayla ayni olmali
#
# 5. madde en sinsisi: pin derleme aninda gomuluyor. Sertifika sonradan
# yenilenirse uygulamadaki pin eskiyor. Bu betik pinleri calisma aninda
# dosyadan okudugu icin o sinif hata olusamaz.
#
# Kullanim:
#   ./tool/run_ios_device.sh              # profile modu (ikondan acilir)
#   MODE=debug ./tool/run_ios_device.sh   # debug modu (Dart yigin izi verir)
set -uo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
cd "$project_directory"

readonly port="${MOCK_PORT:-8443}"
readonly mode="${MODE:-profile}"
readonly tls_directory="qa/mock/tls"
readonly log_file="/tmp/securechat-mock.log"

step()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()    { printf '\033[32m    OK\033[0m %s\n' "$1"; }
die()   { printf '\033[31m    HATA\033[0m %s\n' "$1" >&2; exit 1; }
note()  { printf '         %s\n' "$1"; }

[[ "$(uname -s)" == "Darwin" ]] || die "Bu betik macOS icin."

# --- 1. LAN adresi ----------------------------------------------------------
step "LAN adresi"
lan=""
for interface in en0 en1 en2; do
  lan="$(ipconfig getifaddr "$interface" 2>/dev/null || true)"
  [[ -n "$lan" ]] && break
done
[[ -n "$lan" ]] || die "Wi-Fi adresi bulunamadi. Mac agda mi?"
ok "$lan"
note "Telefon AYNI agda olmali."

# --- 2. Sertifika -----------------------------------------------------------
step "Sertifika"
./qa/mock/setup_tls.sh "$lan" >/dev/null || die "Sertifika uretilemedi."
primary_pin="$(cat "$tls_directory/primary.pin")"
backup_pin="$(cat "$tls_directory/backup.pin")"
[[ -n "$primary_pin" && -n "$backup_pin" ]] || die "Pin dosyalari bos."
[[ -f "$tls_directory/directory.json" ]] \
  || die "Rehber anahtari yok: $tls_directory/directory.json"
ok "primary $primary_pin"
ok "rehber anahtari hazir"

# --- 3. Sunucu --------------------------------------------------------------
step "Mock sunucu"
listening="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
if [[ -n "$listening" ]]; then
  if grep -q "127.0.0.1:$port" <<<"$listening"; then
    die "Sunucu yalniz loopback dinliyor. Durdurup bu betigi tekrar calistirin."
  fi
  ok "zaten calisiyor"
else
  # `--directory` ZORUNLU: uygulama kayittan hemen sonra
  # /api/v1/directory/config cagiriyor ve modul yuklu degilse sunucu 501
  # donuyor. Uygulama bunu dogru sekilde hata sayiyor (guvensiz yedege
  # dusmuyor), ama onboarding orada tikaniyor ve ekranda "kod hatali veya
  # suresi dolmus" yaziyor — sebep OTP degil.
  nohup dart run qa/mock/bin/server.dart \
    --port "$port" \
    --cert "$tls_directory/primary.cert.pem" \
    --key "$tls_directory/primary.key.pem" \
    --directory "$tls_directory/directory.json" \
    --state qa/mock/state > "$log_file" 2>&1 &
  note "baslatiliyor (gunluk: $log_file)"
  for _ in $(seq 1 30); do
    sleep 1
    lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 && break
  done
  lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1 \
    || die "Sunucu ayaga kalkmadi. Gunluge bakin: $log_file"
  ok "baslatildi"
fi

# --- 4. LAN'dan erisim ------------------------------------------------------
step "LAN erisimi"
code="$(curl -sk -o /dev/null -m 10 -w '%{http_code}' "https://$lan:$port/api/v1/health" 2>/dev/null || true)"
if [[ "$code" == "000" || -z "$code" ]]; then
  firewall="$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true)"
  note "$firewall"
  die "https://$lan:$port yanit vermiyor. Guvenlik duvari engelliyor olabilir:
         Sistem Ayarlari > Ag > Guvenlik Duvari"
fi
ok "https://$lan:$port -> HTTP $code"

# --- 5. Pin gercekten esliyor mu -------------------------------------------
# Sunucunun SUNDUGU sertifikadan pin hesaplanip dosyadakiyle karsilastirilir.
# Uygulamaya gomulecek deger dosyadan geldigi icin bu esitlik sarttir.
step "Pin dogrulamasi"
served_pin="$(echo | openssl s_client -connect "$lan:$port" 2>/dev/null \
  | openssl x509 -pubkey -noout 2>/dev/null \
  | openssl pkey -pubin -outform der 2>/dev/null \
  | openssl dgst -sha256 -binary 2>/dev/null \
  | openssl enc -base64 2>/dev/null)"
[[ -n "$served_pin" ]] || die "Sunucunun sertifikasi okunamadi."
[[ "$served_pin" == "$primary_pin" ]] \
  || die "Sunucunun sundugu pin dosyadakiyle AYNI DEGIL.
         sunulan: $served_pin
         dosyada: $primary_pin
         Sunucuyu durdurup betigi tekrar calistirin."
ok "sunulan pin dosyadakiyle ayni"

# --- 6. Cihaz ---------------------------------------------------------------
step "Cihaz"
device="$(flutter devices --machine 2>/dev/null \
  | python3 -c "
import json,sys
try: devices = json.load(sys.stdin)
except Exception: devices = []
for d in devices:
    if d.get('targetPlatform','').startswith('ios') and not d.get('emulator', False):
        print(d['id']); break
" 2>/dev/null || true)"
[[ -n "$device" ]] || die "Bagli iPhone bulunamadi. USB baglantisini ve cihazdaki guven onayini kontrol edin."
ok "$device"

# --- 7. Calistir ------------------------------------------------------------
step "Uygulama kuruluyor ($mode)"
note "OTP kodu: 123456  (sunucu her adresi kabul eder)"
exec flutter run "--$mode" -d "$device" \
  --dart-define=SECURECHAT_API_BASE_URL="https://$lan:$port" \
  --dart-define=SECURECHAT_SIGNALING_URL="wss://$lan:$port" \
  --dart-define=SECURECHAT_CERT_PIN_HOST="$lan" \
  --dart-define=SECURECHAT_CERT_PIN_SHA256="$primary_pin" \
  --dart-define=SECURECHAT_CERT_PIN_SHA256_BACKUP="$backup_pin" \
  --dart-define=SECURECHAT_FIREBASE_IOS_APP_ID=1:791820453236:ios:989a9c79e4e79ec3685821
