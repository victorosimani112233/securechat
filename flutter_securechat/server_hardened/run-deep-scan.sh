#!/usr/bin/env bash
#
# Tek komutla deep tarama: dummy signaling sunucusunu ayaga kaldirir, taze
# token'la instruction'i kurar, strix deep taramasini interaktif calistirir,
# bitince sunucuyu durdurur. Baska hicbir sey yapman gerekmez.
#
#   bash run-deep-scan.sh
#
set -uo pipefail

SP=/tmp/claude-1000/-home-user497-securechat-flutter-securechat/6716a3db-e279-439d-8c26-f871ae8cf2c2/scratchpad
PROJ=/home/user497/securechat/flutter_securechat/server_hardened
STRIX="$SP/strix-venv/bin/strix-claude-cli"
PORT=8090
LOG="$SP/dummy-runme.log"
INSTR="$SP/deep-runme-instruction.txt"
REPORT="$HOME/strix-deep-user.md"

command -v docker >/dev/null || { echo "docker yok"; exit 1; }
[ -x "$STRIX" ] || { echo "strix kurulu degil: $STRIX"; exit 1; }
[ -f "$SP/scan-instruction.txt" ] || { echo "temel instruction yok: $SP/scan-instruction.txt"; exit 1; }

DUMMY_PGID=""
cleanup() {
  echo
  echo "[temizlik] dummy sunucu durduruluyor..."
  [ -n "$DUMMY_PGID" ] && kill -- "-$DUMMY_PGID" 2>/dev/null
  docker ps -aq --filter "label=strix-cli-scan-id" | xargs -r docker rm -f >/dev/null 2>&1
  echo "[temizlik] bitti."
}
trap cleanup EXIT INT TERM

echo "==> [1/4] dummy signaling sunucusu baslatiliyor (port $PORT)..."
: > "$LOG"
cd "$PROJ"
setsid env DUMMY_BIND_HOST=0.0.0.0 DUMMY_BIND_PORT="$PORT" \
  ./gradlew :signaling-server:runDummyServer --offline --no-daemon >> "$LOG" 2>&1 &
DUMMY_PGID=$!

echo "    hazir olmasi bekleniyor (Postgres + Redis konteynerleri kalkiyor)..."
for i in $(seq 1 150); do
  grep -q "Signaling sunucusu hazir" "$LOG" 2>/dev/null && break
  grep -q "BUILD FAILED" "$LOG" 2>/dev/null && { echo "HATA: dummy baslamadi"; tail -20 "$LOG"; exit 1; }
  sleep 2
done
if ! curl -sf -o /dev/null "http://127.0.0.1:$PORT/health"; then
  echo "HATA: sunucu $PORT portunda yanit vermiyor"; tail -20 "$LOG"; exit 1
fi
echo "    OK: http://127.0.0.1:$PORT/health = 200"

echo "==> [2/4] taze token ile instruction hazirlaniyor..."
TOK=$(grep -m1 'SCAN-CREDENTIALS user=' "$LOG" | sed 's/.*token=//')
U=$(grep -m1 'SCAN-CREDENTIALS user=' "$LOG" | sed 's/SCAN-CREDENTIALS user=//; s/ token=.*//')
[ -n "$TOK" ] || { echo "HATA: token uretilemedi"; exit 1; }
sed "s#user_id=.*#user_id=$U#; s#access_token=.*#access_token=$TOK#" "$SP/scan-instruction.txt" \
  | sed "s#host.docker.internal:8080#host.docker.internal:$PORT#g; s#:8080#:$PORT#g" > "$INSTR"
SNAP=$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOK" \
  "http://127.0.0.1:$PORT/api/v1/directory/snapshot")
echo "    token gecerli mi (snapshot): $SNAP  (200 olmali)"

echo "==> [3/4] deep tarama basliyor (interaktif). Cikinca rapor yazilir."
echo "    hedef: http://host.docker.internal:$PORT"
echo "    ------------------------------------------------------------"
"$STRIX" \
  -t "http://host.docker.internal:$PORT" \
  -m deep \
  --instruction-file "$INSTR" \
  -o "$REPORT" \
  --scan-id user-deep
RC=$?

echo "==> [4/4] tarama bitti (cikis kodu $RC)."
if [ -f "$REPORT" ]; then
  echo "    RAPOR: $REPORT  ($(wc -c < "$REPORT") byte)"
  echo "    Bu dosyayi Claude'a yapistir; bulgularini inceleyip duzeltir."
else
  echo "    Rapor yazilmadi. Muhtemelen nested ajan [cyber] guvenlik korumasina"
  echo "    takildi (deep modun bilinen davranisi). Log: $SP/ (scan ciktisi)."
fi
