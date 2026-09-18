#!/bin/sh
# OpenDKIM container entrypoint.
#
# Anahtar kalici volume'da tutulur. Varsa DOKUNULMAZ: DNS'te yayimlanmis
# public key ile private key'in ayrilmasi butun mailleri DKIM'den dusurur.
set -eu

log() { printf '[opendkim-entrypoint] %s\n' "$*" >&2; }

: "${MAIL_DOMAIN:?MAIL_DOMAIN zorunlu}"
: "${DKIM_SELECTOR:=mail}"

KEY_DIR="/var/lib/opendkim/keys/${MAIL_DOMAIN}"
PRIVATE_KEY="${KEY_DIR}/${DKIM_SELECTOR}.private"
PUBLIC_TXT="${KEY_DIR}/${DKIM_SELECTOR}.txt"

mkdir -p "$KEY_DIR" /run/opendkim

if [ ! -f "$PRIVATE_KEY" ]; then
    log "DKIM anahtari yok — 2048-bit uretiliyor (selector=$DKIM_SELECTOR)"
    opendkim-genkey -b 2048 -d "$MAIL_DOMAIN" -s "$DKIM_SELECTOR" -D "$KEY_DIR"
else
    log "Mevcut DKIM anahtari kullaniliyor: $PRIVATE_KEY"
fi

chown -R opendkim:opendkim /var/lib/opendkim /run/opendkim
chmod 0600 "$PRIVATE_KEY"

export MAIL_DOMAIN DKIM_SELECTOR
envsubst '${MAIL_DOMAIN} ${DKIM_SELECTOR}' < /etc/opendkim.conf.tmpl > /etc/opendkim.conf

# Yayimlanmasi gereken DNS kaydini her aciliste logla — operator
# `docker compose logs opendkim` ile kaydi bulabilsin.
if [ -f "$PUBLIC_TXT" ]; then
    log "----- DNS'e eklenecek DKIM TXT kaydi -----"
    log "Ad : ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}"
    log "Deger (tirnaklar birlestirilerek tek string):"
    sed -e 's/^/    /' "$PUBLIC_TXT" >&2
    log "-----------------------------------------"
fi

log "opendkim baslatiliyor (milter :8891)"
exec opendkim -f -x /etc/opendkim.conf
