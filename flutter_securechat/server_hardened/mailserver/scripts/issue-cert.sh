#!/usr/bin/env bash
# ${MAIL_HOSTNAME} icin Let's Encrypt sertifikasi alir ve yenilenme
# sonrasi postfix container'ini yeniden baslatacak deploy hook'u kurar.
#
# Sertifika ZORUNLUDUR: uygulama tarafi (jakarta.mail) STARTTLS'i
# starttls.required=true ile kullanip hostname dogrular. Self-signed
# sertifikayla OTP gonderimi calismaz.
#
# CERTBOT_MODE secenekleri:
#   standalone     80/tcp'yi certbot gecici olarak acar. Baska web sunucusu YOKSA.
#   webroot        Calisan bir nginx varsa. NGINX_WEBROOT zorunlu.
#   dns-cloudflare DNS-01 dogrulama. PUBLIC SUNUCU GEREKTIRMEZ; sertifikayi
#                  kendi makinende alabilirsin. CF_API_TOKEN_FILE zorunlu.
#   dns-manual     DNS-01, TXT kaydini elle eklersin. Etkilesimlidir ve
#                  OTOMATIK YENILENEMEZ; yalniz kisa sureli test icin.
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env.mail}"
[ -r "$ENV_FILE" ] || { echo "HATA: $ENV_FILE okunamiyor" >&2; exit 1; }
# ENV_FILE mutlak da olabilir goreli de. Cikplak `. dosya` goreli yolu
# PATH'te arar; bu yuzden goreli olani acikca ./ ile niteliyoruz.
# shellcheck disable=SC1090
case "$ENV_FILE" in
    /*) set -a; . "$ENV_FILE"; set +a ;;
    *)  set -a; . "./$ENV_FILE"; set +a ;;
esac

: "${MAIL_HOSTNAME:?}"
# DIKKAT: kontrolu `${CERT_EMAIL:?...}` ile YAPMA. Bash, ${...} icindeki
# kesme isaretini alinti baslangici sayar; "Let's" gibi bir metin dosyanin
# geri kalanini sessizce yanlis ayristirir.
CERT_EMAIL="${CERT_EMAIL:-}"
[ -n "$CERT_EMAIL" ] || {
    echo "HATA: CERT_EMAIL zorunlu (Let's Encrypt bildirimleri icin)" >&2
    exit 1
}
CERTBOT_MODE="${CERTBOT_MODE:-standalone}"

# --- certbot nasil calistirilacak -------------------------------------------
# system : PATH'teki certbot
# docker : resmi certbot imaji. Sistem certbot'u yoksa ya da bozuksa
#          (Ubuntu'nun eski paketi zope.interface catismasiyla cokuyor)
#          bu mod sudo ve apt gerektirmeden calisir.
# auto   : calisan bir sistem certbot'u varsa onu, yoksa docker'i sec.
CERTBOT_RUNTIME="${CERTBOT_RUNTIME:-auto}"

system_certbot_works() {
    command -v certbot >/dev/null 2>&1 && certbot --version >/dev/null 2>&1
}

if [ "$CERTBOT_RUNTIME" = "auto" ]; then
    if system_certbot_works; then
        CERTBOT_RUNTIME=system
    elif docker info >/dev/null 2>&1; then
        CERTBOT_RUNTIME=docker
    else
        echo "Ne calisan bir certbot ne de docker var." >&2
        echo "Kur: apt-get install -y certbot python3-certbot-dns-cloudflare" >&2
        exit 1
    fi
fi

case "$CERTBOT_RUNTIME" in
    system)
        system_certbot_works || {
            echo "certbot yok ya da calismiyor: certbot --version" >&2
            echo "CERTBOT_RUNTIME=docker ile deneyebilirsin." >&2
            exit 1
        }
        # Sistem certbot'u varsayilan dizinleri kullanir.
        LE_CONFIG_DIR="${LE_CONFIG_DIR:-/etc/letsencrypt}"
        ;;
    docker)
        docker info >/dev/null 2>&1 || { echo "docker calismiyor" >&2; exit 1; }
        # Root'a ait /etc/letsencrypt yerine kullaniciya ait bir dizin:
        # boylece sudo gerekmez ve docker compose secret/mount'lari okuyabilir.
        LE_CONFIG_DIR="${LE_CONFIG_DIR:-$HOME/.elcim/letsencrypt}"
        LE_WORK_DIR="${LE_WORK_DIR:-$HOME/.elcim/letsencrypt-work}"
        LE_LOGS_DIR="${LE_LOGS_DIR:-$HOME/.elcim/letsencrypt-logs}"
        mkdir -p "$LE_CONFIG_DIR" "$LE_WORK_DIR" "$LE_LOGS_DIR"
        ;;
    *)
        echo "HATA: CERTBOT_RUNTIME 'system', 'docker' veya 'auto' olmali" >&2
        exit 1
        ;;
esac

# Secilen calistirma bicimine gore certbot'u cagirir.
# Docker modunda konteyner cagiran kullanicinin kimligiyle kosar; boylece
# uretilen sertifika dosyalari root'a degil kullaniciya ait olur.
certbot_run() {
    if [ "$CERTBOT_RUNTIME" = "system" ]; then
        certbot "$@"
        return
    fi
    docker run --rm \
        --user "$(id -u):$(id -g)" \
        -v "$LE_CONFIG_DIR:/etc/letsencrypt" \
        -v "$LE_WORK_DIR:/var/lib/letsencrypt" \
        -v "$LE_LOGS_DIR:/var/log/letsencrypt" \
        ${CF_INI:+-v "$CF_INI:/cloudflare.ini:ro"} \
        "${CERTBOT_IMAGE:-certbot/dns-cloudflare:latest}" "$@"
}

CF_INI=""
cleanup() { [ -n "$CF_INI" ] && rm -f "$CF_INI"; }
trap cleanup EXIT

run_standalone() {
    echo "==> standalone mod: 80/tcp gecici olarak certbot'a veriliyor"
    certbot_run certonly --standalone \
        -d "$MAIL_HOSTNAME" \
        --agree-tos -m "$CERT_EMAIL" --non-interactive \
        --key-type ecdsa
}

run_webroot() {
    : "${NGINX_WEBROOT:?webroot modunda NGINX_WEBROOT zorunlu}"
    echo "==> webroot mod: $NGINX_WEBROOT"
    certbot_run certonly --webroot -w "$NGINX_WEBROOT" \
        -d "$MAIL_HOSTNAME" \
        --agree-tos -m "$CERT_EMAIL" --non-interactive \
        --key-type ecdsa
}

run_dns_cloudflare() {
    # DNS-01: dogrulama DNS'e konan bir TXT kaydiyla yapilir. 80/443'un
    # disaridan erisilebilir olmasi gerekmez, yani sunucu almadan once
    # sertifikayi kendi makinende alabilirsin.
    : "${CF_API_TOKEN_FILE:?dns-cloudflare modunda CF_API_TOKEN_FILE zorunlu}"
    [ -r "$CF_API_TOKEN_FILE" ] || {
        echo "HATA: $CF_API_TOKEN_FILE okunamiyor" >&2
        exit 1
    }
    python3 -c 'import certbot_dns_cloudflare' 2>/dev/null || {
        echo "certbot Cloudflare eklentisi yok." >&2
        echo "Kur: apt-get install -y python3-certbot-dns-cloudflare" >&2
        exit 1
    }

    # certbot kimlik dosyasinin baskalarinca okunabilir olmamasini sart kosar.
    CF_INI="$(mktemp)"
    chmod 600 "$CF_INI"
    local token
    token="$(tr -d '[:space:]' < "$CF_API_TOKEN_FILE")"
    printf 'dns_cloudflare_api_token = %s\n' "$token" > "$CF_INI"

    # Kimlik dosyasinin yolu calistirma bicimine gore degisir: docker
    # modunda dosya konteynere /cloudflare.ini olarak baglanir.
    local cred_path="$CF_INI"
    [ "$CERTBOT_RUNTIME" = "docker" ] && cred_path="/cloudflare.ini"

    echo "==> dns-cloudflare mod: DNS-01, public sunucu gerekmiyor ($CERTBOT_RUNTIME)"
    certbot_run certonly --dns-cloudflare \
        --dns-cloudflare-credentials "$cred_path" \
        --dns-cloudflare-propagation-seconds "${CF_PROPAGATION_SECONDS:-30}" \
        -d "$MAIL_HOSTNAME" \
        --agree-tos -m "$CERT_EMAIL" --non-interactive \
        --key-type ecdsa ${CERTBOT_EXTRA_ARGS:-}
}

run_dns_manual() {
    echo "==> dns-manual mod: istenen TXT kaydini DNS'e elle ekleyeceksin"
    echo "    UYARI: bu mod otomatik yenilenemez"
    certbot_run certonly --manual --preferred-challenges dns \
        -d "$MAIL_HOSTNAME" \
        --agree-tos -m "$CERT_EMAIL" \
        --key-type ecdsa
}

case "$CERTBOT_MODE" in
    standalone)     run_standalone ;;
    webroot)        run_webroot ;;
    dns-cloudflare) run_dns_cloudflare ;;
    dns-manual)     run_dns_manual ;;
    *)
        echo "HATA: CERTBOT_MODE su degerlerden biri olmali:" >&2
        echo "      standalone | webroot | dns-cloudflare | dns-manual" >&2
        exit 1
        ;;
esac

# --dry-run staging'e karsi simulasyon yapar ve DISKE SERTIFIKA YAZMAZ.
# Bu durumda live dizini kontrolu ve yenilenme hook'u anlamsizdir.
case "${CERTBOT_EXTRA_ARGS:-}" in
    *--dry-run*)
        echo
        echo "Dry run tamamlandi: DNS-01 dogrulamasi ve Cloudflare token'i calisiyor."
        echo "Gercek sertifika icin CERTBOT_EXTRA_ARGS olmadan tekrar calistir."
        exit 0
        ;;
esac

LIVE_DIR="$LE_CONFIG_DIR/live/$MAIL_HOSTNAME"
[ -r "$LIVE_DIR/fullchain.pem" ] || {
    echo "HATA: $LIVE_DIR uretilmedi" >&2
    exit 1
}

# --- Yenilenme hook'u -------------------------------------------------------
# Postfix sertifikayi aciliste kopyalar; yenilendiginde yeniden baslatilmali.
# Docker modunda /etc/letsencrypt sistemde yoktur ve yenilemeyi zamanlanmis
# bir `docker run ... renew` yapar; hook'u ayni config dizinine koyuyoruz.
HOOK_DIR="$LE_CONFIG_DIR/renewal-hooks/deploy"
mkdir -p "$HOOK_DIR" 2>/dev/null || {
    echo "UYARI: $HOOK_DIR olusturulamadi, yenilenme hook'u atlandi" >&2
    HOOK_DIR=""
}
STACK_DIR="$(pwd)"
if [ -n "$HOOK_DIR" ]; then
cat > "$HOOK_DIR/restart-elcim-postfix.sh" <<HOOK
#!/bin/sh
# Let's Encrypt yenilemesinden sonra postfix'i yeni sertifikayla baslat.
set -e
case "\$RENEWED_LINEAGE" in
  */$MAIL_HOSTNAME) ;;
  *) exit 0 ;;
esac
cd "$STACK_DIR"
docker compose --env-file "$ENV_FILE" -f compose.mail.yml restart postfix
HOOK
chmod 0755 "$HOOK_DIR/restart-elcim-postfix.sh"
fi

cat <<EOF

Sertifika hazir: $LIVE_DIR
.env.mail icinde su satirin bu dizini gosterdigini dogrula:
    MAIL_TLS_DIR=$LIVE_DIR

Yenilenme hook'u kuruldu: $HOOK_DIR/restart-elcim-postfix.sh
Test:  certbot renew --dry-run
EOF

if [ "$CERTBOT_MODE" = "dns-manual" ]; then
    cat <<'EOF'

UYARI: dns-manual modu otomatik YENILENEMEZ. Sertifika 90 gun gecerlidir;
suresi dolmadan bu scripti tekrar calistirman gerekir. Kalici kurulum icin
dns-cloudflare, standalone ya da webroot moduna gec.
EOF
fi
