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
# ENV_FILE mutlak da olabilir goreli de. Cikplak `. dosya` goreli yolu
# PATH'te arar; bu yuzden goreli olani acikca ./ ile niteliyoruz.
# shellcheck disable=SC1090
case "$ENV_FILE" in
    /*) set -a; . "$ENV_FILE"; set +a ;;
    *)  set -a; . "./$ENV_FILE"; set +a ;;
esac

: "${MAIL_DOMAIN:?}"
: "${MAIL_HOSTNAME:?}"
DKIM_SELECTOR="${DKIM_SELECTOR:-mail}"
DMARC_RUA="${DMARC_RUA:-postmaster@${MAIL_DOMAIN}}"

COMPOSE=(docker compose --env-file "$ENV_FILE" -f compose.mail.yml)

SERVER_IP="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || echo '<SUNUCU_IP>')"

# --- SPF: dogrudan teslimat mi, relay uzerinden mi --------------------------
# Relay kullaniliyorsa gonderen IP bizim sunucumuz DEGIL, relay'in
# sunuculari olur; SPF'in onlari yetkilendirmesi gerekir.
if [ -n "${MAIL_RELAYHOST:-}" ]; then
    case "$MAIL_RELAYHOST" in
        *brevo*|*sendinblue*) spf_mech="include:spf.brevo.com" ;;
        *mailjet*)            spf_mech="include:spf.mailjet.com" ;;
        *sendgrid*)           spf_mech="include:sendgrid.net" ;;
        *mailersend*)         spf_mech="include:_spf.mailersend.net" ;;
        *smtp2go*)            spf_mech="include:spf.smtp2go.com" ;;
        *)                    spf_mech="include:<RELAY_SAGLAYICININ_SPF_INCLUDE_DEGERI>" ;;
    esac
    spf_value="v=spf1 ${spf_mech} ~all"
    spf_why="relay ($MAIL_RELAYHOST) uzerinden gonderiyorsun"
    spf_extra="   ONEMLI: Bu deger relay saglayicisina goredir. Kesin degeri
           saglayicinin kendi \"domain authentication\" sayfasindan al —
           include adresleri degisebiliyor."
else
    spf_value="v=spf1 a:${MAIL_HOSTNAME} -all"
    spf_why="dogrudan teslimat yapiyorsun (relay yok)"
    spf_extra="   -all = kati. Baska bir servisten de gonderiyorsan once ~all ile basla."
fi

# --- A ve PTR bolumu: relay varsa bunlar GEREKMEZ ---------------------------
# Relay uzerinden gonderirken alici MX bizim sunucumuza hic baglanmaz;
# gorunen IP ve PTR relay'e aittir. Kendi makinemizin IP'sini yayimlamak
# hem gereksiz hem yaniltici olur.
if [ -n "${MAIL_RELAYHOST:-}" ]; then
    relay_section="1) A  ve  2) PTR  —  BU KURULUMDA GEREKMEZ
--------------------------------------------------------------------------------
   Relay ($MAIL_RELAYHOST) uzerinden gonderiyorsun. Alici sunucular senin
   makinene hic baglanmaz; gorunen IP ve PTR relay saglayicisina aittir.
   ${MAIL_HOSTNAME} icin A kaydi EKLEME — bu makinenin IP'si disaridan
   mail icin kullanilmiyor.

   Sertifika zaten DNS-01 ile alindi, A kaydi ona da gerekmez.

   >>> AYRICA: relay saglayicisinin kendi \"domain authentication\"
       adimini da tamamla. Verdigi DKIM/dogrulama kayitlarini DNS'e ekle;
       aksi halde relay gonderen adresini yeniden yazabilir ve DMARC duser."
else
    relay_section="1) A  —  mail sunucusunun adresi
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
   Eksikse Gmail ve Outlook mesaji reddeder."
fi

# --- Mevcut SPF kaydi var mi (cakisma kontrolu) -----------------------------
existing_spf=""
if command -v dig >/dev/null 2>&1; then
    existing_spf="$(dig +short TXT "$MAIL_DOMAIN" 2>/dev/null \
        | tr -d '"' | grep -i '^v=spf1' | head -1)"
fi

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

${relay_section}
3) SPF  —  ${MAIL_DOMAIN} adina kimin gonderebilecegini bildirir
--------------------------------------------------------------------------------
   Tip   : TXT
   Ad    : ${MAIL_DOMAIN}        (kok domain, "@")
   Deger : ${spf_value}

   Bu deger secildi cunku ${spf_why}.
${spf_extra}

   TEK BIR SPF KAYDI OLMALI. Ikinci bir v=spf1 kaydi eklersen SPF
   tamamen gecersiz olur (permerror) ve DMARC'i de dusurur.
${existing_spf:+   >>> DIKKAT: Bu domainde ZATEN bir SPF kaydi var:
       $existing_spf
       YENISINI EKLEME. Mevcut kaydi duzenleyip iki tarafi birlestir, ornek:
       v=spf1 $(printf '%s' "${existing_spf#v=spf1 }" | sed 's/ [~-]all$//') ${spf_value#v=spf1 }
}

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
