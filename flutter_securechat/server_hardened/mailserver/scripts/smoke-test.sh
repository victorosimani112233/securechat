#!/usr/bin/env bash
# Uctan uca gonderim testi: uygulama sunucusunun gordugu yoldan
# (app-egress agi -> mail.<domain>:587 -> STARTTLS -> SASL) bir mail atar.
#
# Kullanim:
#   ./scripts/smoke-test.sh alici@gmail.com
set -euo pipefail

TO_ADDR="${1:-}"
[ -n "$TO_ADDR" ] || { echo "Kullanim: $0 <alici-eposta>" >&2; exit 1; }

cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env.mail}"
[ -r "$ENV_FILE" ] || { echo "HATA: $ENV_FILE okunamiyor" >&2; exit 1; }
# shellcheck disable=SC1090
set -a; . "./$ENV_FILE"; set +a

: "${MAIL_DOMAIN:?}"; : "${MAIL_HOSTNAME:?}"; : "${SMTP_USERNAME:?}"
: "${SMTP_PASSWORD_FILE:?}"
[ -r "$SMTP_PASSWORD_FILE" ] || { echo "HATA: $SMTP_PASSWORD_FILE okunamiyor" >&2; exit 1; }
SMTP_PASSWORD="$(cat "$SMTP_PASSWORD_FILE")"
NET="${APP_NETWORK:-securechat-hardened_securechat-egress}"
FROM_ADDR="${SMTP_FROM:-noreply@${MAIL_DOMAIN}}"

echo "==> $NET agindan $MAIL_HOSTNAME:587 uzerinden $TO_ADDR adresine test maili"

# -i sart: onsuz `docker run` stdin'i attach etmez, `python -` bos program
# okur ve script sessizce hicbir sey yapmadan basariyla cikar.
docker run --rm -i --network "$NET" \
  -e SMTP_HOST="$MAIL_HOSTNAME" \
  -e SMTP_USERNAME="$SMTP_USERNAME" \
  -e SMTP_PASSWORD="$SMTP_PASSWORD" \
  -e FROM_ADDR="$FROM_ADDR" \
  -e TO_ADDR="$TO_ADDR" \
  python:3.12-slim python -u - <<'PY'
import os, smtplib, ssl, sys
from email.message import EmailMessage

host = os.environ["SMTP_HOST"]
msg = EmailMessage()
msg["From"] = f"SecureChat <{os.environ['FROM_ADDR']}>"
msg["To"] = os.environ["TO_ADDR"]
msg["Subject"] = "Elcim mail server smoke test"
msg.set_content("Duz metin govde. Bu bir teslimat testidir.")
msg.add_alternative("<p>HTML govde. Bu bir <b>teslimat testi</b>dir.</p>", subtype="html")

# Uygulama tarafiyla ayni sertlik: STARTTLS zorunlu, sertifika dogrulanir.
ctx = ssl.create_default_context()
ctx.check_hostname = True
ctx.verify_mode = ssl.CERT_REQUIRED

try:
    with smtplib.SMTP(host, 587, timeout=20) as s:
        s.set_debuglevel(1)
        s.ehlo()
        s.starttls(context=ctx)
        s.ehlo()
        s.login(os.environ["SMTP_USERNAME"], os.environ["SMTP_PASSWORD"])
        s.send_message(msg)
except Exception as exc:
    print(f"\nBASARISIZ: {type(exc).__name__}: {exc}", file=sys.stderr)
    sys.exit(1)
print("\nOK: mail submission kabul edildi (kuyruga alindi).")
PY

cat <<EOF

Kuyruk / teslimat gunlugu:
  docker compose --env-file $ENV_FILE -f compose.mail.yml logs -f postfix
  docker compose --env-file $ENV_FILE -f compose.mail.yml exec postfix postqueue -p

Teslimat kalitesini olcmek icin:
  1) https://www.mail-tester.com  adresinden bir test adresi al,
     bu scripti o adrese calistir, 10/10 hedefle.
  2) Gmail'de gelen maili ac > "Orijinali goster":
     SPF: PASS, DKIM: PASS, DMARC: PASS gormelisin.
EOF
