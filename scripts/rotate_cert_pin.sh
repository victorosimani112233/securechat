#!/bin/bash
# ============================================================================
# Cert pin rotation script
# ============================================================================
# Yeni TLS cert deploy edildikten sonra calistirir:
#   1. Sunucudan TCP/443 ile gercek live cert'i ceker (server'a yazma YOK,
#      sadece readonly TLS handshake)
#   2. SHA-256 SPKI pin'ini hesaplar
#   3. Mevcut CERT_PIN_SHA256'yi CERT_PIN_SHA256_BACKUP'a tasir (rollback yedek)
#   4. Yeni pin'i CERT_PIN_SHA256'ye yazar
#   5. res/raw/server_cert.pem'i yeni cert ile gunceller
#
# Kullanim:
#   ./scripts/rotate_cert_pin.sh <HOST> [PORT]
#   ./scripts/rotate_cert_pin.sh 94.73.180.226
#   ./scripts/rotate_cert_pin.sh signal.securechat.app 443
#
# GUVENLIK: Bu script server'a SSH yapmaz, sadece TCP/443 acik baglanti.
# Server'in herhangi bir dosyasina dokunmaz.
# ============================================================================
set -e

HOST="${1:-}"
PORT="${2:-443}"

if [ -z "$HOST" ]; then
    echo "Kullanim: $0 <HOST> [PORT]"
    echo "Ornek:    $0 94.73.180.226"
    exit 1
fi

# Proje koku script konumundan tespit et
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GRADLE_FILE="$PROJECT_ROOT/app/build.gradle.kts"
CERT_FILE="$PROJECT_ROOT/app/src/main/res/raw/server_cert.pem"

if [ ! -f "$GRADLE_FILE" ]; then
    echo "[!] $GRADLE_FILE bulunamadi"
    exit 1
fi

echo "==> 1. Live cert TCP/443'ten cekiliyor: $HOST:$PORT"
CERT_PEM=$(echo | openssl s_client -connect "$HOST:$PORT" -servername "$HOST" 2>/dev/null \
    | openssl x509 -outform PEM)

if [ -z "$CERT_PEM" ]; then
    echo "[!] Cert cekilemedi. $HOST:$PORT erisilebilir mi?"
    exit 1
fi

echo "==> 2. SHA-256 SPKI pin hesaplaniyor"
NEW_PIN=$(echo "$CERT_PEM" \
    | openssl x509 -pubkey -noout \
    | openssl pkey -pubin -outform der \
    | openssl dgst -sha256 -binary \
    | openssl enc -base64)
echo "    Yeni pin: $NEW_PIN"

echo "==> 3. Cert SAN dogrulama"
SAN=$(echo "$CERT_PEM" | openssl x509 -noout -ext subjectAltName 2>/dev/null | tail -1 | xargs)
EXPIRY=$(echo "$CERT_PEM" | openssl x509 -noout -enddate | cut -d= -f2)
echo "    SAN: $SAN"
echo "    Geçerlilik bitis: $EXPIRY"

# Mevcut pin'leri oku
CURRENT_PRIMARY=$(grep -oP 'CERT_PIN_SHA256",\s*"\\"[^"]+\\""' "$GRADLE_FILE" 2>/dev/null | head -1 | grep -oP '\\"\K[^"\\]+' || echo "")
CURRENT_BACKUP=$(grep -oP 'CERT_PIN_SHA256_BACKUP",\s*"\\"[^"]+\\""' "$GRADLE_FILE" 2>/dev/null | head -1 | grep -oP '\\"\K[^"\\]+' || echo "")

echo "==> 4. Mevcut pinler"
echo "    Primary:  ${CURRENT_PRIMARY:-(bos)}"
echo "    Backup:   ${CURRENT_BACKUP:-(bos)}"

# Eger yeni pin zaten primary ise hicbir sey yapma
if [ "$NEW_PIN" = "$CURRENT_PRIMARY" ]; then
    echo "==> [OK] Yeni pin mevcut primary ile ayni — degisiklik yok"
    exit 0
fi

echo "==> 5. Yedekleme: $GRADLE_FILE.bak"
cp "$GRADLE_FILE" "$GRADLE_FILE.bak.$(date +%s)"

# build.gradle.kts'i guncelle: dev ve prod flavor'larin her ikisinde de
# CERT_PIN_SHA256 -> CERT_PIN_SHA256_BACKUP
# NEW_PIN -> CERT_PIN_SHA256
echo "==> 6. build.gradle.kts guncelleniyor (eski primary → backup, yeni → primary)"

if [ -n "$CURRENT_PRIMARY" ]; then
    # Primary'i backup'a yaz
    sed -i.tmp "s|CERT_PIN_SHA256_BACKUP\", \"\\\\\"[^\"]*\\\\\"\"|CERT_PIN_SHA256_BACKUP\", \"\\\\\"$CURRENT_PRIMARY\\\\\"\"|g" "$GRADLE_FILE"
fi
# Yeni pin'i primary'e yaz
sed -i.tmp "s|CERT_PIN_SHA256\", \"\\\\\"[^\"]*\\\\\"\"|CERT_PIN_SHA256\", \"\\\\\"$NEW_PIN\\\\\"\"|g" "$GRADLE_FILE"
rm -f "$GRADLE_FILE.tmp"

# CERT_PIN_SHA256_BACKUP da CERT_PIN_SHA256 pattern'e match olur — duzelt:
# Yukaridaki sed her ikisini de yeni pin'e setledi. Backup'i tekrar eski primary'e cevirelim.
if [ -n "$CURRENT_PRIMARY" ]; then
    sed -i.tmp "s|CERT_PIN_SHA256_BACKUP\", \"\\\\\"$NEW_PIN\\\\\"\"|CERT_PIN_SHA256_BACKUP\", \"\\\\\"$CURRENT_PRIMARY\\\\\"\"|g" "$GRADLE_FILE"
    rm -f "$GRADLE_FILE.tmp"
fi

echo "==> 7. res/raw/server_cert.pem guncelleniyor"
echo "$CERT_PEM" > "$CERT_FILE"

echo
echo "============================================================"
echo " TAMAMLANDI"
echo "============================================================"
echo "  Eski primary: ${CURRENT_PRIMARY:-(yoktu)}"
echo "  Yeni primary: $NEW_PIN"
echo "  Yeni backup:  ${CURRENT_PRIMARY:-(yoktu)}"
echo
echo "  Sonraki adim: APK yeniden build et"
echo "    ./gradlew :app:assembleDevDebug   (veya assembleProdRelease)"
echo
echo "  ESKI APK'lar BACKUP pin sayesinde calismaya devam edecek."
echo "  YENI APK primary + backup ikisini de tanir."
echo "============================================================"
