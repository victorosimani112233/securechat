#!/usr/bin/env bash
# Elcim mail server — yayimlanmasi gereken DNS kayitlarini basar.
#
# Once stack'i ayaga kaldir (DKIM anahtari ilk aciliste uretilir):
#   docker compose --env-file .env.mail -f compose.mail.yml up -d --build
# Sonra:
#   ./scripts/print-dns-records.sh
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env.mail}"
[ -r "$ENV_FILE" ] || { echo "HATA: $ENV_FILE okunamiyor" >&2; exit 1; }
# shellcheck disable=SC1090
set -a; . "./$ENV_FILE"; set +a

: "${MAIL_DOMAIN:?}"
: "${MAIL_HOSTNAME:?}"
DKIM_SELECTOR="${DKIM_SELECTOR:-mail}"
DMARC_RUA="${DMARC_RUA:-postmaster@${MAIL_DOMAIN}}"

COMPOSE=(docker compose --env-file "$ENV_FILE" -f compose.mail.yml)

SERVER_IP="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || echo '<SUNUCU_IP>')"

# --- DKIM public key'i container'dan al ve tek satira indir ------------------
raw_txt="$("${COMPOSE[@]}" exec -T opendkim \
    cat "/var/lib/opendkim/keys/${MAIL_DOMAIN}/${DKIM_SELECTOR}.txt" 2>/dev/null || true)"

if [ -z "$raw_txt" ]; then
    dkim_value="<opendkim container calismyor — once 'up -d' yap>"
else
    # opendkim-genkey ciktisi:  sel._domainkey IN TXT ( "v=DKIM1; ..." "MIIB..." )
    # Tirnak icindeki parcalari birlestirip tek bir deger uretiyoruz.
    dkim_value="$(printf '%s' "$raw_txt" | tr -d '\n' \
        | grep -o '"[^"]*"' | tr -d '"' | tr -d ' ' | paste -sd '' -)"
fi

cat <<EOF

================================================================================
 ${MAIL_DOMAIN} — DNS KAYITLARI
 Hepsini DNS saglayicina (Cloudflare / registrar paneli) ekle.
================================================================================

1) A  —  mail sunucusunun adresi
--------------------------------------------------------------------------------
   Tip   : A
   Ad    : ${MAIL_HOSTNAME}
   Deger : ${SERVER_IP}
   Proxy : KAPALI (Cloudflare kullaniyorsan turuncu bulut KAPALI olmali;
           proxy IP'yi gizler ve SMTP calismaz)

2) PTR  —  reverse DNS   [DNS PANELINDEN DEGIL, VPS PANELINDEN]
--------------------------------------------------------------------------------
   ${SERVER_IP}  ->  ${MAIL_HOSTNAME}
   Hetzner: Cloud Console > Server > Networking > Reverse DNS
   OVH    : Manager > IP > Reverse DNS
   Eksikse Gmail ve Outlook mesaji reddeder.

3) SPF  —  bu IP'nin ${MAIL_DOMAIN} adina gondermeye yetkili oldugunu bildirir
--------------------------------------------------------------------------------
   Tip   : TXT
   Ad    : ${MAIL_DOMAIN}        (kok domain, "@")
   Deger : v=spf1 a:${MAIL_HOSTNAME} -all

   NOT: Domain'de zaten bir SPF TXT kaydi varsa YENISINI EKLEME —
        mevcut olani duzenle. Iki SPF kaydi SPF'i tamamen gecersiz kilar.
   NOT: -all = katı (yetkisiz gonderen reddedilsin). Baska bir servisten
        (ornek: pazarlama maili) de gonderiyorsan once ~all ile basla.

4) DKIM  —  imza dogrulama anahtari
--------------------------------------------------------------------------------
   Tip   : TXT
   Ad    : ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}
   Deger :
${dkim_value}

   NOT: Deger 255 karakterden uzun. Cloudflare ve cogu panel bunu otomatik
        boler; elle bolme, tek parca yapistir.

5) DMARC  —  politika ve raporlama
--------------------------------------------------------------------------------
   Tip   : TXT
   Ad    : _dmarc.${MAIL_DOMAIN}
   Deger : v=DMARC1; p=none; rua=mailto:${DMARC_RUA}; adkim=s; aspf=s; pct=100

   NOT: p=none ile BASLA. Birkac gun rapor topla, SPF+DKIM'in hizali
        gectigini dogrula, sonra p=quarantine, en son p=reject yap.
   NOT: rua adresi gercekten okunabilir olmali. Bu stack gelen mail
        kabul etmedigi icin baska bir kutu adresi ver.

6) MX  —  GEREKMEZ
--------------------------------------------------------------------------------
   Bu sunucu send-only. Gelen mail kabul etmedigi icin MX kaydina
   ihtiyac yok. (Domain'e mail ALMAK istersen ayri bir konu.)

================================================================================
 Yayildiktan sonra dogrula (TTL kadar bekle):
   dig +short TXT ${MAIL_DOMAIN}
   dig +short TXT ${DKIM_SELECTOR}._domainkey.${MAIL_DOMAIN}
   dig +short TXT _dmarc.${MAIL_DOMAIN}
   dig +short -x ${SERVER_IP}
================================================================================

EOF
