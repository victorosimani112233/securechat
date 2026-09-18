#!/usr/bin/env bash
# nginx + TLS sonlandirma. Sunucuda, KUR.sh'tan SONRA calistirilir.
#
#   sudo bash TLS_KUR.sh
#
# Istemci sertifikayi SPKI pini ile dogrular (`onBadCertificate` pin
# eslesince kabul eder), bu yuzden IP icin self-signed sertifika yeterlidir;
# alan adi ve certbot gerekmez. Guvenligi saglayan sey CA zinciri degil,
# uygulamaya gomulu pindir.
#
# Betik iki anahtar uretir: biri aktif, biri yedek. Istemci en az iki pin
# ister; yedek olmadan sertifika yenilemesi uygulamayi kilitler.
set -euo pipefail

public_host="${SECURECHAT_PUBLIC_HOST:-}"
upstream_port="${DEV_APP_PORT:-8080}"
cert_dir="/etc/securechat-tls"

say()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[1;31mHATA: %s\033[0m\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "root gerekli:  sudo bash TLS_KUR.sh"

if [[ -z "$public_host" ]]; then
  public_host="$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$public_host" ]] || die "SECURECHAT_PUBLIC_HOST verin (IP veya alan adi)"
fi
info "genel adres: $public_host"

say "1/5  nginx"
if ! command -v nginx >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq && apt-get install -y -qq nginx >/dev/null
fi
info "hazir"

say "2/5  Sertifikalar"
mkdir -p "$cert_dir"; chmod 700 "$cert_dir"

spki_pin() {
  openssl x509 -in "$1" -pubkey -noout |
    openssl pkey -pubin -outform der |
    openssl dgst -sha256 -binary | base64
}

# IP adresleri SAN'da `IP:` olarak gecmelidir; `CN` tek basina modern
# istemcilerde yok sayilir. Pin devrede olsa da sertifikayi dogru uretmek
# ileride alan adina gecerken sorun cikmasini onler.
san="DNS:$public_host"
[[ "$public_host" =~ ^[0-9.]+$ ]] && san="IP:$public_host"

if [[ ! -f "$cert_dir/server.crt" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
    -subj "/CN=$public_host" -addext "subjectAltName=$san" \
    -keyout "$cert_dir/server.key" -out "$cert_dir/server.crt" 2>/dev/null
  chmod 600 "$cert_dir/server.key"
  info "aktif sertifika uretildi"
else
  info "aktif sertifika korunuyor"
fi

if [[ ! -f "$cert_dir/backup.crt" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 1825 \
    -subj "/CN=$public_host-backup" -addext "subjectAltName=$san" \
    -keyout "$cert_dir/backup.key" -out "$cert_dir/backup.crt" 2>/dev/null
  chmod 600 "$cert_dir/backup.key"
  info "yedek anahtar uretildi (kullanilmiyor, yalniz pinlenecek)"
fi

say "3/5  nginx yapilandirmasi"
# HTTP/2 direktifi nginx 1.25.1'de degisti: oncesinde `listen ... http2`,
# sonrasinda ayri bir `http2 on;`. Yanlis olani "unknown directive" ile
# yapilandirmayi tumden reddettirir.
nginx_version="$(nginx -v 2>&1 | sed -E 's/.*\/([0-9]+)\.([0-9]+)\.([0-9]+).*/\1 \2 \3/')"
read -r nv_major nv_minor nv_patch <<<"$nginx_version"
if (( nv_major > 1 )) ||
   (( nv_major == 1 && nv_minor > 25 )) ||
   (( nv_major == 1 && nv_minor == 25 && nv_patch >= 1 )); then
  listen_line="    listen 443 ssl;\n    http2 on;"
else
  listen_line="    listen 443 ssl http2;"
fi
info "nginx $nv_major.$nv_minor.$nv_patch"
# Uc davranis zorunludur:
#  - access log kapali: container log'u kapali olsa da proxy kendi kaydini
#    tutar ve bu, mesaj zaman cizelgesini geri getirir.
#  - WebSocket upgrade'inde Authorization header'i korunur.
#  - `token=` query parametresi tasiyan istekler reddedilir: token proxy ve
#    WAF loglarina girer ve saatlerce hesap yetkisi verir.
cat > /etc/nginx/sites-available/securechat <<NGINX
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    server_name $public_host;
    return 301 https://\$host\$request_uri;
}

server {
LISTEN_PLACEHOLDER
    server_name $public_host;

    ssl_certificate     $cert_dir/server.crt;
    ssl_certificate_key $cert_dir/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    access_log off;
    error_log  /var/log/nginx/securechat_error.log crit;

    client_max_body_size 1m;

    # Token query stringde tasinamaz.
    if (\$args ~* "(^|&)token=") { return 400; }

    location /ws {
        proxy_pass http://127.0.0.1:$upstream_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Authorization \$http_authorization;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location / {
        proxy_pass http://127.0.0.1:$upstream_port;
        proxy_http_version 1.1;
        proxy_set_header Authorization \$http_authorization;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
}
NGINX

# Placeholder, surume gore dogru listen satirlariyla degistirilir.
sed -i "s|^LISTEN_PLACEHOLDER\$|$listen_line|" /etc/nginx/sites-available/securechat

ln -sf /etc/nginx/sites-available/securechat /etc/nginx/sites-enabled/securechat
rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 || { nginx -t; die "nginx yapilandirmasi gecersiz"; }
# systemd yoksa (konteyner, minimal imaj) dogrudan nginx'in kendi sinyali
# kullanilir; hicbiri yoksa surec elle baslatilir.
if command -v systemctl >/dev/null 2>&1 && systemctl list-units >/dev/null 2>&1; then
  systemctl enable --now nginx >/dev/null 2>&1 || true
  systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1 || true
elif pgrep -x nginx >/dev/null 2>&1; then
  nginx -s reload
else
  nginx
fi
pgrep -x nginx >/dev/null 2>&1 || die "nginx baslatilamadi"
info "nginx calisiyor"

say "4/5  Firewall"
if command -v ufw >/dev/null 2>&1; then
  ufw allow 443/tcp >/dev/null 2>&1 || true
  ufw allow 3478/tcp >/dev/null 2>&1 || true
  ufw allow 3478/udp >/dev/null 2>&1 || true
  ufw allow 5349/tcp >/dev/null 2>&1 || true
  ufw allow 5349/udp >/dev/null 2>&1 || true
  ufw allow 49160:49200/udp >/dev/null 2>&1 || true
  info "443 + TURN portlari acildi"
else
  info "ufw yok — port acmayi kendiniz yapin"
fi

say "5/5  Dogrulama"
health="$(curl -fsSk --max-time 5 "https://$public_host/health" 2>/dev/null || true)"
[[ -n "$health" ]] || die "https://$public_host/health yanit vermedi. KUR.sh calisiyor mu? SECURECHAT_BIND_HOST=127.0.0.1 olmali ve nginx ayni makinede."

primary="$(spki_pin "$cert_dir/server.crt")"
backup="$(spki_pin "$cert_dir/backup.crt")"

cat <<SUMMARY

  saglik : $health

  Flutter derleme parametreleri — birebir kopyalayin:

    flutter build apk --release \\
      --dart-define=SECURECHAT_API_BASE_URL=https://$public_host \\
      --dart-define=SECURECHAT_SIGNALING_URL=wss://$public_host \\
      --dart-define=SECURECHAT_CERT_PIN_HOST=$public_host \\
      --dart-define=SECURECHAT_CERT_PIN_SHA256=$primary \\
      --dart-define=SECURECHAT_CERT_PIN_SHA256_BACKUP=$backup

  Sertifikalar: $cert_dir
  Yedek anahtar simdi kullanilmiyor; aktif sertifika degistiginde devreye
  alinir ve uygulama guncellemesi gerekmez. Ikisini de saklayin.

SUMMARY
