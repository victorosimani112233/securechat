#!/bin/sh
# Send-only Postfix container entrypoint.
#
# Sorumluluk:
#   1. Zorunlu env dogrulamasi (fail-closed)
#   2. main.cf sablonunu doldur
#   3. TLS sertifikalarini read-only mount'tan kopyalayip sahipligini duzelt
#   4. SASL kullanicisini sasldb2'ye yaz
#   5. postfix'i on planda calistir
set -eu

log() { printf '[postfix-entrypoint] %s\n' "$*" >&2; }
die() { log "HATA: $*"; exit 1; }

# --- 1. Env dogrulama -------------------------------------------------------
: "${MAIL_DOMAIN:?MAIL_DOMAIN zorunlu (ornek: elcim.app)}"
: "${MAIL_HOSTNAME:?MAIL_HOSTNAME zorunlu (ornek: mail.elcim.app) — PTR ile ayni olmali}"
: "${SMTP_USERNAME:?SMTP_USERNAME zorunlu}"
: "${DKIM_MILTER:=opendkim:8891}"
: "${MAIL_RATE_LIMIT:=100}"
: "${TLS_SOURCE_DIR:=/certs-src}"

# Parola dosyadan da okunabilsin (docker secret / compose secrets).
if [ -n "${SMTP_PASSWORD_FILE:-}" ]; then
    [ -r "$SMTP_PASSWORD_FILE" ] || die "SMTP_PASSWORD_FILE okunamiyor: $SMTP_PASSWORD_FILE"
    SMTP_PASSWORD="$(cat "$SMTP_PASSWORD_FILE")"
fi
: "${SMTP_PASSWORD:?SMTP_PASSWORD veya SMTP_PASSWORD_FILE zorunlu}"
[ "${#SMTP_PASSWORD}" -ge 16 ] || die "SMTP_PASSWORD en az 16 karakter olmali"

case "$MAIL_HOSTNAME" in
    *.*) : ;;
    *) die "MAIL_HOSTNAME tam nitelikli olmali (FQDN), ornek: mail.$MAIL_DOMAIN" ;;
esac

# --- 2. main.cf uret --------------------------------------------------------
# envsubst'e ACIK degisken listesi veriliyor; boylece Postfix'in kendi
# $myhostname / $mydomain / ${data_directory} referanslari BOZULMAZ.
export MAIL_DOMAIN MAIL_HOSTNAME DKIM_MILTER MAIL_RATE_LIMIT
envsubst '${MAIL_HOSTNAME} ${MAIL_DOMAIN} ${DKIM_MILTER} ${MAIL_RATE_LIMIT}' \
    < /usr/local/share/elcim/main.cf.tmpl > /etc/postfix/main.cf
log "main.cf uretildi (myhostname=$MAIL_HOSTNAME)"

# --- 2b. Opsiyonel smarthost (relay) ----------------------------------------
# VPS saglayicisi giden 25/tcp'yi bloklarsa dogrudan teslimat imkansizdir.
# MAIL_RELAYHOST verilirse Postfix mailleri o relay uzerinden gonderir;
# domain, DKIM imzasi ve SPF/DMARC hizasi yine bize aittir.
#   ornek: MAIL_RELAYHOST="[smtp.saglayici.com]:587"
if [ -n "${MAIL_RELAYHOST:-}" ]; then
    [ -n "${RELAY_USERNAME:-}" ] || die "MAIL_RELAYHOST ile RELAY_USERNAME zorunlu"
    if [ -n "${RELAY_PASSWORD_FILE:-}" ]; then
        [ -r "$RELAY_PASSWORD_FILE" ] || die "RELAY_PASSWORD_FILE okunamiyor"
        RELAY_PASSWORD="$(cat "$RELAY_PASSWORD_FILE")"
    fi
    [ -n "${RELAY_PASSWORD:-}" ] || die "RELAY_PASSWORD veya RELAY_PASSWORD_FILE zorunlu"

    umask 077
    printf '%s %s:%s\n' "$MAIL_RELAYHOST" "$RELAY_USERNAME" "$RELAY_PASSWORD" \
        > /etc/postfix/relay_passwd
    postmap hash:/etc/postfix/relay_passwd
    chmod 0600 /etc/postfix/relay_passwd /etc/postfix/relay_passwd.db
    umask 022
    unset RELAY_PASSWORD

    # Relay blogu bazi ayarlari yeniden tanimlar. Ayni anahtari iki kez
    # yazmak postfix'te "overriding earlier entry" uyarisi uretir; taban
    # degerleri once siliyoruz.
    sed -i -E '/^[[:space:]]*(smtp_tls_security_level|smtp_tls_mandatory_ciphers)[[:space:]]*=/d' \
        /etc/postfix/main.cf

    cat >> /etc/postfix/main.cf <<RELAYCF

# --- Smarthost (entrypoint tarafindan eklendi) ------------------------------
relayhost = $MAIL_RELAYHOST
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/relay_passwd
smtp_sasl_security_options = noanonymous
smtp_sasl_mechanism_filter = plain, login
# Relay bize ait olmayan bir taraf: TLS burada opportunistic degil ZORUNLU.
smtp_tls_security_level = encrypt
smtp_tls_mandatory_ciphers = high
RELAYCF
    log "Smarthost etkin: $MAIL_RELAYHOST (kullanici: $RELAY_USERNAME)"
else
    log "Dogrudan teslimat modu (relay yok) — giden 25/tcp acik olmali"
fi

# --- 3. TLS sertifikalari ---------------------------------------------------
# Let's Encrypt privkey.pem root:root 0600'dur ve mount read-only gelir.
# Postfix smtpd'nin okuyabilmesi icin container-yerel bir kopya cikariyoruz.
mkdir -p /etc/postfix/certs

# Iki yerlesim desteklenir:
#   a) duz dizin        -> <mount>/fullchain.pem
#   b) letsencrypt koku -> <mount>/live/<host>/fullchain.pem
#
# (b) sart cunku certbot'un live/ dizinindeki dosyalar archive/ icine
# giden SEMBOLIK LINK'lerdir. Yalniz live/<host> mount edilirse linkler
# mount disini gosterir ve konteyner icinde kirilir; koku mount etmek
# her iki tarafi da kapsar.
if [ -r "$TLS_SOURCE_DIR/fullchain.pem" ]; then
    cert_dir="$TLS_SOURCE_DIR"
elif [ -r "$TLS_SOURCE_DIR/live/$MAIL_HOSTNAME/fullchain.pem" ]; then
    cert_dir="$TLS_SOURCE_DIR/live/$MAIL_HOSTNAME"
else
    die "Sertifika bulunamadi. Bakilan yerler:
       $TLS_SOURCE_DIR/fullchain.pem
       $TLS_SOURCE_DIR/live/$MAIL_HOSTNAME/fullchain.pem
     MAIL_TLS_DIR certbot'un config kokunu (live/ ve archive/ iceren dizin)
     ya da gercek dosyalarin bulundugu bir dizini gostermeli."
fi
[ -r "$cert_dir/privkey.pem" ] || die "$cert_dir/privkey.pem okunamiyor"
log "Sertifika kaynagi: $cert_dir"

# cp -L: sembolik linkleri izleyip GERCEK icerigi kopyalar.
cp -L "$cert_dir/fullchain.pem" /etc/postfix/certs/fullchain.pem
cp -L "$cert_dir/privkey.pem"   /etc/postfix/certs/privkey.pem
chown root:postfix /etc/postfix/certs/privkey.pem /etc/postfix/certs/fullchain.pem
chmod 0640 /etc/postfix/certs/privkey.pem
chmod 0644 /etc/postfix/certs/fullchain.pem

# Sertifikanin MAIL_HOSTNAME'i gercekten kapsadigini dogrula. Kapsamiyorsa
# istemci tarafi `starttls.required=true` ile baglanti kuramaz ve OTP
# gonderimi sessizce basarisiz olur — burada fail-closed davraniyoruz.
if command -v openssl >/dev/null 2>&1; then
    cert_names="$(openssl x509 -in /etc/postfix/certs/fullchain.pem -noout -text 2>/dev/null \
        | tr ',' '\n' | sed -n 's/.*DNS://p' | tr -d ' ')"
    if [ -n "$cert_names" ] && ! printf '%s\n' "$cert_names" | grep -qx "$MAIL_HOSTNAME"; then
        die "Sertifika $MAIL_HOSTNAME icin gecerli degil. Kapsanan adlar: $(printf '%s ' $cert_names)"
    fi
fi
log "TLS sertifikalari yerlestirildi"

# --- 4. SASL kullanicisi ----------------------------------------------------
rm -f /etc/sasldb2
printf '%s' "$SMTP_PASSWORD" | saslpasswd2 -p -c -u "$MAIL_DOMAIN" "$SMTP_USERNAME"
chown root:postfix /etc/sasldb2
chmod 0640 /etc/sasldb2
unset SMTP_PASSWORD
log "SASL kullanicisi hazir: $SMTP_USERNAME@$MAIL_DOMAIN"

# --- 5. Kuyruk dizinleri ve calistirma --------------------------------------
# data_directory postfix kullanicisinin olmali (TLS session cache buraya yazilir).
mkdir -p /var/lib/postfix
chown postfix:postfix /var/lib/postfix
chmod 0700 /var/lib/postfix

# `postfix set-permissions` BILEREK CALISTIRILMIYOR.
# Container cap_drop:[ALL] ile calisir ve CAP_FSETID yoktur; set-permissions'in
# yaptigi `chmod g+s /usr/sbin/postqueue` sessizce duser, setgid biti KAYBOLUR
# ve her aciliste "not set-gid" uyarisi alinir. Dogru izinler zaten image
# build'inde sabitleniyor (bkz. Dockerfile).
postfix check || die "postfix check basarisiz"

log "postfix baslatiliyor (send-only, submission=587)"
exec postfix start-fg
