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
# ENV_FILE mutlak da olabilir goreli de. Cikplak `. dosya` goreli yolu
# PATH'te arar; bu yuzden goreli olani acikca ./ ile niteliyoruz.
# shellcheck disable=SC1090
case "$ENV_FILE" in
    /*) set -a; . "$ENV_FILE"; set +a ;;
    *)  set -a; . "./$ENV_FILE"; set +a ;;
esac

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
msg["Subject"] = "Elcim dogrulama kodunuz"

# Govde bilerek gercek bir OTP maili gibi. Cok kisa HTML govdeler
# SpamAssassin'in HTML_IMAGE_ONLY kuralini tetikler (ozellikle relay bir
# takip pikseli ekliyorsa): az metin + bir gorsel = spam sinyali.
TEXT = """Elcim dogrulama kodunuz: 452 918

Bu kodu Elcim uygulamasindaki dogrulama ekranina girin.
Kod 10 dakika boyunca gecerlidir ve yalnizca bir kez kullanilabilir.

Bu istegi siz yapmadiysaniz bu e-postayi yok sayabilirsiniz;
hesabinizda herhangi bir degisiklik yapilmaz. Kodu kimseyle
paylasmayin. Elcim ekibi sizden asla dogrulama kodu istemez.

-- Elcim
Bu otomatik bir mesajdir, yanitlamayin.
"""

HTML = """\
<div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;
            max-width:520px;color:#1a1a1a;line-height:1.6">
  <h2 style="margin:0 0 16px">Dogrulama kodunuz</h2>
  <p style="margin:0 0 16px">
    Elcim hesabiniza giris yapmak icin asagidaki kodu dogrulama ekranina girin.
  </p>
  <p style="font-size:28px;letter-spacing:6px;font-weight:700;
            margin:0 0 16px">452 918</p>
  <p style="margin:0 0 16px">
    Kod <strong>10 dakika</strong> boyunca gecerlidir ve yalnizca bir kez
    kullanilabilir.
  </p>
  <p style="margin:0 0 16px">
    Bu istegi siz yapmadiysaniz bu e-postayi yok sayabilirsiniz; hesabinizda
    herhangi bir degisiklik yapilmaz. Kodu kimseyle paylasmayin &mdash; Elcim
    ekibi sizden asla dogrulama kodu istemez.
  </p>
  <hr style="border:none;border-top:1px solid #e5e5e5;margin:24px 0">
  <p style="font-size:13px;color:#666;margin:0">
    Bu otomatik bir mesajdir, yanitlamayin.
  </p>
</div>
"""

msg.set_content(TEXT)
msg.add_alternative(HTML, subtype="html")

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
