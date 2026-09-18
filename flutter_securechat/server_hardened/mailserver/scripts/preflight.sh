#!/usr/bin/env bash
# Elcim mail server — kurulum oncesi uygunluk kontrolu.
#
# YENI SUNUCUDA, MAIL STACK'INI KURMADAN ONCE CALISTIR.
# VPS saglayicilarinin cogu giden 25/tcp'yi bloklar. Blokluysa
# kendi mail sunucundan dogrudan teslimat MUMKUN DEGILDIR ve
# saglayiciyi degistirmen ya da acmalarini istemen gerekir.
#
# Kullanim:  MAIL_HOSTNAME=mail.elcim.app ./preflight.sh
set -uo pipefail

MAIL_HOSTNAME="${MAIL_HOSTNAME:-}"
fail=0

blue() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()   { printf '  \033[32mGECTI\033[0m  %s\n' "$*"; }
bad()  { printf '  \033[31mKALDI\033[0m  %s\n' "$*"; fail=1; }
warn() { printf '  \033[33mUYARI\033[0m  %s\n' "$*"; }

need() { command -v "$1" >/dev/null 2>&1; }

blue "0. Gerekli araclar"
for t in dig openssl curl; do
    if need "$t"; then ok "$t bulundu"; else
        bad "$t yok — kur: apt-get install -y dnsutils openssl curl"
    fi
done
[ "$fail" -eq 0 ] || { printf '\nAraclari kurup tekrar calistir.\n'; exit 1; }

blue "1. Genel IP adresi"
PUBLIC_IP="$(curl -fsS --max-time 10 https://api.ipify.org || true)"
if [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ok "Genel IP: $PUBLIC_IP"
else
    bad "Genel IP tespit edilemedi"
    PUBLIC_IP=""
fi

blue "2. Giden 25/tcp (EN KRITIK KONTROL)"
# Gmail ve Outlook MX'lerine dogrudan baglanabilmeliyiz.
declare -a MX_HOSTS=(
    "gmail-smtp-in.l.google.com"
    "outlook-com.olc.protection.outlook.com"
)
open25=0
for h in "${MX_HOSTS[@]}"; do
    if timeout 12 bash -c "exec 3<>/dev/tcp/$h/25" 2>/dev/null; then
        ok "$h:25 ulasilabilir"
        open25=1
    else
        bad "$h:25 ENGELLI"
    fi
done
if [ "$open25" -eq 0 ]; then
    cat <<'MSG'

  --> Giden 25/tcp kapali. Secenekler:
      a) VPS saglayicisindan acmasini iste (Hetzner/Contabo: ticket ile acilir)
      b) 25/tcp'yi varsayilan acik tutan saglayiciya gec (OVH, Netcup)
      c) Kendi Postfix'ini bir SMTP relay'e (smarthost) bagla
         -> bu durumda bu stack yine kullanilir, sadece main.cf'e
            `relayhost` + relay kimlik dogrulamasi eklenir
MSG
fi

blue "3. PTR (reverse DNS)"
if [ -n "$PUBLIC_IP" ]; then
    PTR="$(dig +short -x "$PUBLIC_IP" 2>/dev/null | sed 's/\.$//' | head -1)"
    if [ -z "$PTR" ]; then
        bad "PTR kaydi YOK — VPS panelinden $MAIL_HOSTNAME olarak ayarla"
    elif [ -n "$MAIL_HOSTNAME" ] && [ "$PTR" != "$MAIL_HOSTNAME" ]; then
        bad "PTR '$PTR', beklenen '$MAIL_HOSTNAME' — VPS panelinden duzelt"
    else
        ok "PTR: $PTR"
    fi
fi

blue "4. Ileri/geri DNS tutarliligi"
if [ -n "$MAIL_HOSTNAME" ]; then
    A_REC="$(dig +short A "$MAIL_HOSTNAME" | tail -1)"
    if [ -z "$A_REC" ]; then
        bad "$MAIL_HOSTNAME icin A kaydi yok"
    elif [ -n "$PUBLIC_IP" ] && [ "$A_REC" != "$PUBLIC_IP" ]; then
        bad "A kaydi $A_REC, sunucu IP'si $PUBLIC_IP — uyusmuyor"
    else
        ok "A kaydi: $MAIL_HOSTNAME -> $A_REC"
    fi
else
    warn "MAIL_HOSTNAME verilmedi, A kaydi kontrolu atlandi"
fi

blue "5. IP itibar / blocklist"
if [ -n "$PUBLIC_IP" ]; then
    IFS='.' read -r o1 o2 o3 o4 <<<"$PUBLIC_IP"
    rev="$o4.$o3.$o2.$o1"
    for bl in zen.spamhaus.org bl.spamcop.net b.barracudacentral.org; do
        res="$(dig +short +time=3 +tries=1 "$rev.$bl" A 2>/dev/null)"
        if [ -z "$res" ]; then
            ok "$bl: listede degil"
        else
            bad "$bl: LISTELI ($res) — bu IP ile mail gonderme, degistir"
        fi
    done
    warn "Spamhaus, genel DNS resolver'lardan (8.8.8.8 vb.) gelen sorgulari"
    warn "reddeder. Sonuc bos ciktiysa sunucunun kendi resolver'i ile test et."
fi

blue "6. 587/tcp bos mu"
if timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/587" 2>/dev/null; then
    warn "127.0.0.1:587 zaten dinleniyor — baska bir MTA kurulu olabilir"
else
    ok "587/tcp bos"
fi

printf '\n'
if [ "$fail" -eq 0 ]; then
    printf '\033[32mTum kontroller gecti. Mail stack kurulabilir.\033[0m\n'
    exit 0
fi
printf '\033[31mEn az bir kontrol basarisiz. Yukaridaki maddeleri duzelt.\033[0m\n'
exit 1
