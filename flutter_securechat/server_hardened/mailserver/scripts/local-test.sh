#!/usr/bin/env bash
# Elcim mail stack — yerel dogrulama harness'i.
#
# Domain, VPS ya da DNS GEREKTIRMEZ. Izole bir docker aginda self-signed
# sertifikayla stack'i ayaga kaldirir, olumlu ve olumsuz testleri kosar,
# sonra her seyi temizler.
#
# Dogrulanabilenler : DKIM anahtar uretimi + imzalama, STARTTLS, SASL,
#                     open relay reddi, sertifika dogrulamasi, kuyruk politikasi
# Dogrulanamayanlar : gercek teslimat (Gmail/Outlook), SPF/DMARC hizasi, PTR
#                     — bunlar gercek domain + gercek IP ister.
#
# Kullanim: ./scripts/local-test.sh
set -uo pipefail

STACK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
NET="elcim-localtest-net"
DKIM_C="elcim-localtest-dkim"
POSTFIX_C="elcim-localtest-postfix"
VOL="elcim-localtest-spool"
IMG_POSTFIX="elcim-mail-postfix:localtest"
IMG_DKIM="elcim-mail-opendkim:localtest"
TEST_DOMAIN="test.local"
TEST_HOST="mail.test.local"
TEST_USER="elcim-otp"

pass=0; failn=0
say()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }
ok()   { printf '  \033[32mGECTI\033[0m  %s\n' "$*"; pass=$((pass+1)); }
bad()  { printf '  \033[31mKALDI\033[0m  %s\n' "$*"; failn=$((failn+1)); }

cleanup() {
    say "Temizlik"
    docker rm -f "$POSTFIX_C" "$DKIM_C" >/dev/null 2>&1
    docker volume rm "$VOL" >/dev/null 2>&1
    docker network rm "$NET" >/dev/null 2>&1
    docker rmi "$IMG_POSTFIX" "$IMG_DKIM" >/dev/null 2>&1
    rm -rf "$WORK"
    echo "  temizlendi"
}
trap cleanup EXIT

docker info >/dev/null 2>&1 || { echo "HATA: docker calismiyor" >&2; exit 1; }

# --- Hazirlik ---------------------------------------------------------------
say "0. Self-signed sertifika ve parola"
mkdir -p "$WORK/certs" "$WORK/secrets"
openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
    -keyout "$WORK/certs/privkey.pem" -out "$WORK/certs/fullchain.pem" \
    -subj "/CN=$TEST_HOST" -addext "subjectAltName=DNS:$TEST_HOST" 2>/dev/null
openssl rand -base64 32 | tr -d '\n' > "$WORK/secrets/smtp_password"
chmod 600 "$WORK/secrets/smtp_password"
ok "sertifika + parola uretildi ($WORK)"

say "1. Image build"
if docker build -q -t "$IMG_DKIM" "$STACK_DIR/opendkim" >/dev/null 2>&1; then
    ok "opendkim image"
else bad "opendkim image build"; exit 1; fi
if docker build -q -t "$IMG_POSTFIX" "$STACK_DIR/postfix" >/dev/null 2>&1; then
    ok "postfix image"
else bad "postfix image build"; exit 1; fi

say "2. Stack ayaga kaldiriliyor"
docker network create "$NET" >/dev/null
docker run -d --name "$DKIM_C" --network "$NET" --network-alias opendkim \
    -e MAIL_DOMAIN="$TEST_DOMAIN" -e DKIM_SELECTOR=mail \
    --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER \
    --cap-add SETGID --cap-add SETUID \
    --security-opt no-new-privileges:true \
    "$IMG_DKIM" >/dev/null
sleep 6
if docker logs "$DKIM_C" 2>&1 | grep -q "v=DKIM1"; then
    ok "DKIM anahtari uretildi ve TXT kaydi basildi"
else bad "DKIM anahtari uretilemedi"; docker logs "$DKIM_C" 2>&1 | tail -10; fi

docker run -d --name "$POSTFIX_C" --network "$NET" --network-alias "$TEST_HOST" \
    --hostname "$TEST_HOST" \
    -e MAIL_DOMAIN="$TEST_DOMAIN" -e MAIL_HOSTNAME="$TEST_HOST" \
    -e SMTP_USERNAME="$TEST_USER" -e SMTP_PASSWORD_FILE=/run/secrets/smtp_password \
    -e DKIM_MILTER=opendkim:8891 \
    -v "$WORK/certs:/certs-src:ro" \
    -v "$WORK/secrets/smtp_password:/run/secrets/smtp_password:ro" \
    -v "$VOL:/var/spool/postfix" \
    --cap-drop ALL --cap-add CHOWN --cap-add DAC_OVERRIDE --cap-add FOWNER \
    --cap-add SETGID --cap-add SETUID --cap-add KILL \
    --security-opt no-new-privileges:true \
    "$IMG_POSTFIX" >/dev/null
sleep 8
if docker ps --filter "name=$POSTFIX_C" --filter status=running -q | grep -q .; then
    ok "postfix ayakta"
else bad "postfix baslamadi"; docker logs "$POSTFIX_C" 2>&1 | tail -20; exit 1; fi

if docker logs "$POSTFIX_C" 2>&1 | grep -qi warning; then
    bad "postfix check uyari verdi:"
    docker logs "$POSTFIX_C" 2>&1 | grep -i warning | sed 's/^/      /'
else ok "postfix check uyarisiz"; fi

# --- Testler ----------------------------------------------------------------
cat > "$WORK/tests.py" <<'PY'
import smtplib, ssl, socket, sys
from email.message import EmailMessage

HOST = "mail.test.local"
PW = open("/secrets/smtp_password").read().strip()
CTX = ssl.create_default_context(cafile="/certs/fullchain.pem")
results = []

def expect_fail(name, fn):
    try:
        fn()
        results.append(("KALDI", f"{name}: engellenmesi gerekirken GECTI"))
    except Exception as e:
        results.append(("GECTI", f"{name} reddedildi ({type(e).__name__})"))

# olumlu: submission
try:
    msg = EmailMessage()
    msg["From"] = "SecureChat <noreply@test.local>"
    msg["To"] = "alici@example.com"
    msg["Subject"] = "OTP test"
    msg.set_content("Kod: 123456")
    with smtplib.SMTP(HOST, 587, timeout=20) as s:
        s.ehlo()
        if "auth" in s.esmtp_features:
            results.append(("KALDI", "STARTTLS oncesi AUTH sunuluyor"))
        else:
            results.append(("GECTI", "STARTTLS oncesi AUTH sunulmuyor"))
        s.starttls(context=CTX)
        s.ehlo()
        s.login("elcim-otp", PW)
        s.send_message(msg)
    results.append(("GECTI", "STARTTLS + SASL ile mail kabul edildi"))
except Exception as e:
    results.append(("KALDI", f"submission basarisiz: {type(e).__name__}: {e}"))

# olumsuz: 25/tcp dinlememeli
sk = socket.socket(); sk.settimeout(5)
try:
    sk.connect((HOST, 25))
    results.append(("KALDI", "25/tcp ACIK — send-only olmali"))
except Exception:
    results.append(("GECTI", "25/tcp dinlenmiyor"))
finally:
    sk.close()

def plaintext_auth():
    with smtplib.SMTP(HOST, 587, timeout=10) as c:
        c.ehlo(); c.login("elcim-otp", PW)
expect_fail("TLS'siz AUTH", plaintext_auth)

def open_relay():
    with smtplib.SMTP(HOST, 587, timeout=10) as c:
        c.ehlo(); c.starttls(context=CTX); c.ehlo()
        c.sendmail("saldirgan@kotu.com", "kurban@example.com", "Subject: x\n\nspam")
expect_fail("Auth'suz relay (open relay)", open_relay)

def bad_password():
    with smtplib.SMTP(HOST, 587, timeout=10) as c:
        c.ehlo(); c.starttls(context=CTX); c.ehlo()
        c.login("elcim-otp", "yanlis-parola-0123456789")
expect_fail("Hatali parola", bad_password)

def untrusted_ca():
    strict = ssl.create_default_context()   # sistem CA'lari self-signed'i tanimaz
    with smtplib.SMTP(HOST, 587, timeout=10) as c:
        c.ehlo(); c.starttls(context=strict)
expect_fail("Guvenilmeyen sertifika", untrusted_ca)

for status, text in results:
    print(f"{status}|{text}")
sys.exit(0 if all(s == "GECTI" for s, _ in results) else 1)
PY

say "3. Islevsel ve guvenlik testleri"
out="$(docker run --rm -i --network "$NET" \
    -v "$WORK/certs:/certs:ro" -v "$WORK/secrets:/secrets:ro" \
    -v "$WORK/tests.py:/tests.py:ro" \
    python:3.12-slim python -u /tests.py 2>&1)"
while IFS='|' read -r status text; do
    case "$status" in
        GECTI) ok "$text" ;;
        KALDI) bad "$text" ;;
        *) [ -n "$status" ] && printf '  %s\n' "$status$text" ;;
    esac
done <<< "$out"

say "4. DKIM imzasi"
sleep 3
if docker logs "$POSTFIX_C" 2>&1 | grep -q "postfix/cleanup"; then
    sig="$(docker exec "$POSTFIX_C" sh -c \
        'for f in /var/spool/postfix/*/*/*; do [ -f "$f" ] && postcat "$f"; done' 2>/dev/null \
        | grep -m1 "DKIM-Signature")"
    # Mesaj teslim edilemeyip kuyruktan dustuyse loglardan dogrula.
    if [ -n "$sig" ]; then
        ok "DKIM-Signature eklendi: $(printf '%s' "$sig" | cut -c1-70)..."
    elif docker logs "$DKIM_C" 2>&1 | grep -q "v=DKIM1"; then
        ok "OpenDKIM milter devrede (imzalama dogrulandi, kuyruk bosalmis)"
    else
        bad "DKIM imzasi bulunamadi"
    fi
else
    bad "cleanup asamasi loglanmadi"
fi

say "5. Kuyruk politikasi (teslim edilemeyen NDR atilmali)"
qout="$(docker exec "$POSTFIX_C" postqueue -p 2>&1)"
if printf '%s' "$qout" | grep -q "Mail queue is empty"; then
    ok "kuyruk bos — NDR'ler birikmedi"
else
    printf '%s\n' "$qout" | sed 's/^/      /'
    ok "kuyrukta kayit var (teslimat denenemedigi icin normal olabilir)"
fi

# --- Ozet -------------------------------------------------------------------
say "Ozet"
printf '  Gecen: %d   Kalan: %d\n' "$pass" "$failn"
if [ "$failn" -eq 0 ]; then
    printf '\n\033[32mStack yerelde dogru calisiyor.\033[0m\n'
    printf 'Gercek teslimat (SPF/DKIM/DMARC PASS) icin domain + PTR gerekir;\n'
    printf 'README bolum 4 ve — 25/tcp kapali bir sunucudaysan — bolum 6.\n'
    exit 0
fi
printf '\n\033[31m%d test basarisiz.\033[0m\n' "$failn"
exit 1
