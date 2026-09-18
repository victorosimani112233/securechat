#!/usr/bin/env bash
# Yerel gelistirme sunucusunu tek komutla ayaga kaldirir.
#
# Gelistirme profili yalniz ALTYAPI kapilarini gevsetir: HSM yerine dosya
# anahtari, TLS'siz yerel PostgreSQL, TLS'siz yerel SMTP, process icinde
# uretilen Sealed Sender sertifikasi. Mesaj gizliligi kapilari aynen calisir —
# anahtarlar zorunlu ve amac-ayrimli, offline kuyruk AEAD ile sifreli,
# Sealed Sender gercek libsignal.
#
# Bu betik production'da kullanilmaz; urettigi her sey gecicidir.
set -euo pipefail

deploy_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
server_root="$(cd -- "$deploy_dir/.." && pwd)"
state_dir="${SECURECHAT_DEV_STATE:-$HOME/.securechat-dev}"
env_file="$state_dir/dev.env"
jar="$server_root/signaling-server/build/libs/signaling-server-all.jar"

pg_port="${DEV_PG_PORT:-55440}"
redis_port="${DEV_REDIS_PORT:-63790}"
app_port="${DEV_APP_PORT:-8080}"

for tool in docker openssl java; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool gerekli" >&2; exit 2; }
done

mkdir -p "$state_dir"
chmod 0700 "$state_dir"

# --- 1. Anahtarlar: bir kez uretilir, sonraki calistirmalarda korunur ---
# Her calistirmada yeniden uretmek, onceki kuyruk ve token'lari okunamaz
# hale getirir; kayitli test hesaplari da gecersizlesir.
if [[ ! -f "$env_file" ]]; then
  echo "[1/4] Gelistirme anahtarlari uretiliyor: $env_file"
  # `genpkey -outform DER` bazi OpenSSL surumlerinde PKCS#1 uretir; sunucu
  # PKCS#8 bekledigi icin donusum acikca yapilir.
  oprf_pem="$(mktemp)"
  oprf_der="$(mktemp)"
  trap 'rm -f -- "$oprf_pem" "$oprf_der"' EXIT
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$oprf_pem" 2>/dev/null
  openssl pkcs8 -topk8 -nocrypt -in "$oprf_pem" -outform DER -out "$oprf_der" 2>/dev/null

  umask 077
  cat > "$env_file" <<ENV
SECURECHAT_PROFILE=development

JWT_SECRET=$(openssl rand -base64 32)
PRIVACY_INDEX_KEY=$(openssl rand -base64 32)
OFFLINE_QUEUE_ENCRYPTION_KEY=$(openssl rand -base64 32)
FCM_TOKEN_ENCRYPTION_KEY=$(openssl rand -base64 32)
TURN_SECRET=$(openssl rand -base64 32)
METRICS_BEARER_TOKEN=$(openssl rand -base64 32)
SEALED_SENDER_TRUST_ROOT_PRIVATE_KEY=$(openssl rand -base64 32)
SEALED_SENDER_SERVER_PRIVATE_KEY=$(openssl rand -base64 32)
DIRECTORY_OPRF_PRIVATE_KEY=$(base64 -w0 < "$oprf_der")

DATABASE_URL=jdbc:postgresql://127.0.0.1:${pg_port}/securechat
DATABASE_USER=securechat
DATABASE_PASSWORD=devpass
REDIS_HOST=127.0.0.1
REDIS_PORT=${redis_port}

SMTP_HOST=127.0.0.1
SMTP_PORT=1025
SMTP_FROM=dev@localhost
SMTP_TLS=none

TURN_HOST=127.0.0.1
HOST=127.0.0.1
PORT=${app_port}
ENV
else
  echo "[1/4] Mevcut anahtarlar kullaniliyor: $env_file"
fi

# --- 2. Yerel altyapi ---
echo "[2/4] PostgreSQL ve Redis baslatiliyor"
docker rm -f securechat-dev-pg securechat-dev-redis >/dev/null 2>&1 || true
docker run -d --name securechat-dev-pg \
  -e POSTGRES_PASSWORD=devpass -e POSTGRES_USER=securechat -e POSTGRES_DB=securechat \
  -p "127.0.0.1:${pg_port}:5432" postgres:16 >/dev/null

# Gelistirmede de tahliye kapalidir: sessizce kaybolan bir mesaji yerelde
# yakalamak, production'da yakalamaktan cok daha ucuzdur.
docker run -d --name securechat-dev-redis \
  -p "127.0.0.1:${redis_port}:6379" redis:7-alpine \
  redis-server --appendonly no --save '' --maxmemory 256mb --maxmemory-policy noeviction >/dev/null

printf '      PostgreSQL bekleniyor'
for _ in $(seq 1 60); do
  if docker exec securechat-dev-pg pg_isready -U securechat >/dev/null 2>&1; then
    printf ' hazir\n'; break
  fi
  printf '.'; sleep 1
done

# --- 3. Artefakt ---
if [[ ! -f "$jar" ]]; then
  echo "[3/4] Fat JAR bulunamadi, derleniyor"
  (cd "$server_root" && ./gradlew :signaling-server:fatJar -q)
else
  echo "[3/4] Mevcut JAR kullaniliyor (yeniden derlemek icin: ./gradlew :signaling-server:fatJar)"
fi

# --- 4. Calistir ---
echo "[4/4] Sunucu baslatiliyor — http://127.0.0.1:${app_port}"
echo
echo "      Saglik : curl -s http://127.0.0.1:${app_port}/health"
echo "      Hazirlik: curl -s -H \"Authorization: Bearer \$(grep ^METRICS_BEARER_TOKEN= $env_file | cut -d= -f2-)\" http://127.0.0.1:${app_port}/ready"
echo "      Durdur  : Ctrl-C  (container'lar icin: docker rm -f securechat-dev-pg securechat-dev-redis)"
echo

set -a
# shellcheck disable=SC1090
. "$env_file"
set +a
exec java -jar "$jar"
