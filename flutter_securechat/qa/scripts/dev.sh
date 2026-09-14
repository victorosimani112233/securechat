#!/usr/bin/env bash
# SecureChat QA device helper. All adb access goes through here so a second
# physical device only needs SC_SERIAL=<serial> to join the test run.
set -uo pipefail

SC_SERIAL="${SC_SERIAL:-$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')}"
SC_PKG="${SC_PKG:-com.securechat.app.debug}"
SC_ACTIVITY="${SC_ACTIVITY:-com.securechat.app.MainActivity}"
QA_ROOT="${QA_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

a()      { adb -s "$SC_SERIAL" "$@"; }
ash()    { adb -s "$SC_SERIAL" shell "$@"; }
pid()    { adb -s "$SC_SERIAL" shell pidof "$SC_PKG" | tr -d '\r' | awk '{print $1}'; }
launch() { adb -s "$SC_SERIAL" shell am start -W -n "$SC_PKG/$SC_ACTIVITY"; }
stop()   { adb -s "$SC_SERIAL" shell am force-stop "$SC_PKG"; }
shot()   { adb -s "$SC_SERIAL" exec-out screencap -p > "$QA_ROOT/screenshots/$1.png"; }
dump()   { adb -s "$SC_SERIAL" shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb -s "$SC_SERIAL" shell cat /sdcard/ui.xml; }
tap()    { adb -s "$SC_SERIAL" shell input tap "$1" "$2"; }
swipe()  { adb -s "$SC_SERIAL" shell input swipe "$1" "$2" "$3" "$4" "${5:-300}"; }
text()   { adb -s "$SC_SERIAL" shell input text "$1"; }
key()    { adb -s "$SC_SERIAL" shell input keyevent "$1"; }
logclr() { adb -s "$SC_SERIAL" logcat -c; }
logsave(){ adb -s "$SC_SERIAL" logcat -d > "$QA_ROOT/logs/$1.log"; echo "$QA_ROOT/logs/$1.log"; }

# PID-scoped app log + the system tags that matter for crash/ANR/native/WebRTC.
logapp() {
  local out="$QA_ROOT/logs/$1.log"; local p; p=$(pid)
  { [ -n "$p" ] && adb -s "$SC_SERIAL" logcat -d --pid="$p" 2>/dev/null
    adb -s "$SC_SERIAL" logcat -d -s AndroidRuntime:E DEBUG:F libc:F ActivityManager:E \
        WindowManager:E StrictMode:* flutter:* FlutterJNI:* org.webrtc:* libwebrtc:* \
        WebRtcAudioTrack:* WebRtcAudioRecord:* FirebaseMessaging:* 2>/dev/null
  } > "$out"; echo "$out"
}
# Signal scan: what matters in a captured log.
scan() {
  local f="$QA_ROOT/logs/$1.log"
  echo "--- signals in $1 ---"
  grep -anEi "FATAL|AndroidRuntime|ANR in|Exception|StrictMode|OutOfMemory|native crash|SIGSEGV|SIGABRT|E/flutter|Diagnostics event=|ICE|PeerConnection|DTLS|libsignal|Signal(Protocol)?|Unhandled" "$f" \
    | grep -avE "ExceptionHandler installed" | head -${2:-40}
  echo "--- (total lines: $(wc -l < "$f")) ---"
}
