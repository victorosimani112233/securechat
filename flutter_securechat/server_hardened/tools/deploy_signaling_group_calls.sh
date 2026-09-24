#!/usr/bin/env bash
set +x
set -euo pipefail
umask 077

if [[ ${EUID} -ne 0 ]]; then
  echo 'Bu betigi sunucuda root olarak calistirin.' >&2
  exit 1
fi

cd /root/securechat
jar=kaynak/server_hardened/signaling-server/build/libs/signaling-server-all.jar
incoming=signaling-server-all.jar.new
expected=7a15cfe4d0b1d89ba96bd360549b42669a124d707cf020e79af3ca17ebc5f343

for command in java curl python3 sha256sum pgrep flock nohup; do
  command -v "$command" >/dev/null
done
exec 9>.signaling-deploy.lock
flock -n 9 || { echo 'Baska bir dagitim devam ediyor.' >&2; exit 1; }

for file in "$incoming" "$jar" collect_push_diagnostics.py /root/.securechat-dev/dev.env; do
  if [[ ! -r "$file" ]]; then
    echo "Gerekli dosya bulunamadi veya okunamiyor: $file" >&2
    exit 1
  fi
done
printf '%s  %s\n' "$expected" "$incoming" | sha256sum -c -

# Reuse existing secrets and recovery keys without printing or replacing them.
set -a
source /root/.securechat-dev/dev.env
set +a
set +x
port=${PORT:-8080}
if [[ ! "$port" =~ ^[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > 65535 )); then
  echo 'PORT gecersiz; sunucuya dokunulmadi.' >&2
  exit 1
fi

pattern='^java -jar (/root/securechat/)?kaynak/server_hardened/signaling-server/build/libs/signaling-server-all[.]jar$'
mapfile -t old_pids < <(pgrep -f "$pattern" || true)
if (( ${#old_pids[@]} != 1 )); then
  echo 'Beklenen tek java -jar sureci bulunamadi; hicbir surec durdurulmadi.' >&2
  echo 'Systemd/Docker veya farkli bir baslatma komutu varsa bu betikle devam etmeyin.' >&2
  exit 1
fi

backup="$jar.bak.$(date +%Y%m%d-%H%M%S).$$"
cp -p "$jar" "$backup"
echo "Onceki JAR yedeklendi: $backup"
kill -TERM "${old_pids[0]}"
for ((i = 0; i < 60; i++)); do
  kill -0 "${old_pids[0]}" 2>/dev/null || break
  sleep 1
done
if kill -0 "${old_pids[0]}" 2>/dev/null || pgrep -f "$pattern" >/dev/null; then
  echo 'Eski sunucu kapanmadi veya yeniden baslatildi; JAR degistirilmedi.' >&2
  exit 1
fi

mv "$incoming" "$jar"
nohup java -jar "$jar" >> sunucu.log 2>&1 < /dev/null 9>&- &
pid=$!
echo "Yeni sunucu baslatildi; PID: $pid"

for ((i = 0; i < 60; i++)); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "Yeni sunucu kapandi. Yedek: $backup" >&2
    echo 'Kontrol: tail -n 40 /root/securechat/sunucu.log' >&2
    exit 1
  fi
  if curl --fail --silent --noproxy '*' --max-time 2 \
    "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
    echo 'HTTP health: OK. Beklenen build: d511597-dirty-group-calls-20260924'
    if ! python3 collect_push_diagnostics.py; then
      echo 'Saglik kontrolu gecti, tani kontrolu basarisiz. Ciktiyi paylasin.' >&2
      exit 1
    fi
    exit 0
  fi
  sleep 1
done

echo "Saglik kontrolu zaman asimina ugradi. Yedek: $backup" >&2
echo 'Otomatik geri alma yapilmadi. Kontrol: tail -n 40 /root/securechat/sunucu.log' >&2
exit 1
