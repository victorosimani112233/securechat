#!/usr/bin/env bash
# ${MAIL_HOSTNAME} icin Let's Encrypt sertifikasi alir ve yenilenme
# sonrasi postfix container'ini yeniden baslatacak deploy hook'u kurar.
#
# Sertifika ZORUNLUDUR: uygulama tarafi (jakarta.mail) STARTTLS'i
# `starttls.required=true` ile kullanir ve hostname dogrulamasi yapar.
# Self-signed sertifika ile OTP gonderimi calismaz.
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env.mail}"
[ -r "$ENV_FILE" ] || { echo "HATA: $ENV_FILE okunamiyor" >&2; exit 1; }
# shellcheck disable=SC1090
set -a; . "./$ENV_FILE"; set +a

: "${MAIL_HOSTNAME:?}"
CERT_EMAIL="${CERT_EMAIL:?CERT_EMAIL ver (Let's Encrypt bildirimleri icin)}"
# standalone : 80/tcp'yi certbot gecici olarak acar (baska web sunucusu YOKSA)
# webroot    : calisan nginx varsa; NGINX_WEBROOT ver
CERTBOT_MODE="${CERTBOT_MODE:-standalone}"

command -v certbot >/dev/null 2>&1 || {
    echo "certbot yok. Kur: apt-get update && apt-get install -y certbot" >&2
    exit 1
}

case "$CERTBOT_MODE" in
  standalone)
    echo "==> standalone mod: 80/tcp gecici olarak certbot'a veriliyor"
    certbot certonly --standalone \
        -d "$MAIL_HOSTNAME" \
        --agree-tos -m "$CERT_EMAIL" --non-interactive \
        --key-type ecdsa
    ;;
  webroot)
    : "${NGINX_WEBROOT:?webroot modunda NGINX_WEBROOT zorunlu}"
    echo "==> webroot mod: $NGINX_WEBROOT"
    certbot certonly --webroot -w "$NGINX_WEBROOT" \
        -d "$MAIL_HOSTNAME" \
        --agree-tos -m "$CERT_EMAIL" --non-interactive \
        --key-type ecdsa
    ;;
  *)
    echo "HATA: CERTBOT_MODE 'standalone' veya 'webroot' olmali" >&2
    exit 1
    ;;
esac

LIVE_DIR="/etc/letsencrypt/live/$MAIL_HOSTNAME"
[ -r "$LIVE_DIR/fullchain.pem" ] || { echo "HATA: $LIVE_DIR uretilmedi" >&2; exit 1; }

# --- Yenilenme hook'u -------------------------------------------------------
# Postfix sertifikayi aciliste kopyalar; yenilenince yeniden baslatilmali.
HOOK_DIR=/etc/letsencrypt/renewal-hooks/deploy
mkdir -p "$HOOK_DIR"
STACK_DIR="$(pwd)"
cat > "$HOOK_DIR/restart-elcim-postfix.sh" <<HOOK
#!/bin/sh
# Let's Encrypt yenilemesinden sonra postfix'i yeni sertifikayla yeniden baslat.
set -e
case "\$RENEWED_LINEAGE" in
  */$MAIL_HOSTNAME) ;;
  *) exit 0 ;;
esac
cd "$STACK_DIR"
docker compose --env-file "$ENV_FILE" -f compose.mail.yml restart postfix
HOOK
chmod 0755 "$HOOK_DIR/restart-elcim-postfix.sh"

cat <<EOF

Sertifika hazir: $LIVE_DIR
.env.mail icinde su satirin bu dizini gosterdigini dogrula:
    MAIL_TLS_DIR=$LIVE_DIR

Yenilenme hook'u kuruldu: $HOOK_DIR/restart-elcim-postfix.sh
Test:  certbot renew --dry-run
EOF
