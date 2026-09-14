#!/usr/bin/env python3
"""Senaryo kosucusu: UI aksiyonu -> log toplama -> assert -> kanit kaydi.

Her senaryo qa/reports/results.jsonl icine tek satir yazar. Rapor bu
dosyadan uretilir, boylece sohbet ciktisi kirlenmez.
"""
import json
import os
import re
import subprocess
import time
import urllib.request
import ssl
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOGS = ROOT / "logs"
SHOTS = ROOT / "screenshots"
REPORTS = ROOT / "reports"
for d in (LOGS, SHOTS, REPORTS):
    d.mkdir(parents=True, exist_ok=True)

PKG = os.environ.get("SC_PKG", "com.securechat.app.debug")
ACTIVITY = f"{PKG}/com.securechat.app.MainActivity"
MOCK = os.environ.get("SC_MOCK", "https://127.0.0.1:18444")
RESULTS = REPORTS / "results.jsonl"

_ctx = ssl.create_default_context()
_ctx.check_hostname = False
_ctx.verify_mode = ssl.CERT_NONE


def serial():
    if os.environ.get("SC_SERIAL"):
        return os.environ["SC_SERIAL"]
    out = subprocess.run(["adb", "devices"], capture_output=True, text=True).stdout
    for line in out.splitlines()[1:]:
        if line.strip().endswith("device"):
            return line.split()[0]
    raise RuntimeError("no authorized device")


SERIAL = serial()


def adb(*args, binary=False, timeout=120):
    r = subprocess.run(["adb", "-s", SERIAL, *args], capture_output=True, timeout=timeout)
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def sh(cmd, timeout=120):
    return adb("shell", cmd, timeout=timeout)


def pid():
    return sh(f"pidof {PKG}").strip().split(" ")[0] if sh(f"pidof {PKG}").strip() else ""


# ---- UI ----
def tap(x, y, settle=1.2):
    adb("shell", "input", "tap", str(x), str(y)); time.sleep(settle)


def swipe(x1, y1, x2, y2, ms=300, settle=1.0):
    adb("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(ms)); time.sleep(settle)


def typetext(s, settle=0.8):
    # adb input text bosluk ve ozel karakterleri escape ister.
    esc = s.replace("%", "%%").replace(" ", "%s").replace("'", "\\'").replace('"', '\\"')
    adb("shell", "input", "text", esc); time.sleep(settle)


def key(k, settle=0.8):
    adb("shell", "input", "keyevent", str(k)); time.sleep(settle)


def shot(name):
    data = adb("exec-out", "screencap", "-p", binary=True)
    path = SHOTS / f"{name}.png"
    path.write_bytes(data)
    return path.name


def ui_nodes():
    """uiautomator semantics agacini eleman listesine cevirir."""
    import xml.etree.ElementTree as ET
    for _ in range(3):
        adb("shell", "uiautomator", "dump", "/sdcard/qa_ui.xml")
        xml = sh("cat /sdcard/qa_ui.xml")
        start = xml.find("<?xml")
        if start < 0 or "</hierarchy>" not in xml:
            time.sleep(0.6); continue
        xml = xml[start:xml.rindex("</hierarchy>") + len("</hierarchy>")]
        try:
            root = ET.fromstring(xml)
        except ET.ParseError:
            time.sleep(0.6); continue
        out = []
        for n in root.iter("node"):
            label = (n.get("text") or "").strip() or (n.get("content-desc") or "").strip()
            m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n.get("bounds", ""))
            if not label or not m:
                continue
            x1, y1, x2, y2 = map(int, m.groups())
            out.append({
                "label": label, "x": (x1 + x2) // 2, "y": (y1 + y2) // 2,
                "w": x2 - x1, "h": y2 - y1,
                "class": (n.get("class") or "").split(".")[-1],
                "clickable": n.get("clickable") == "true",
                "checked": n.get("checked") == "true",
                "selected": n.get("selected") == "true",
                "checkable": n.get("checkable") == "true",
            })
        return out
    return []


def find(needle, clickable=None, nodes=None):
    needle = needle.lower()
    for n in (nodes if nodes is not None else ui_nodes()):
        if needle in n["label"].lower() and (clickable is None or n["clickable"] == clickable):
            return n
    return None


def tap_text(needle, settle=1.4, clickable=None):
    n = find(needle, clickable=clickable)
    if not n:
        return False
    tap(n["x"], n["y"], settle)
    return True


def labels():
    return [n["label"].replace("\n", " | ") for n in ui_nodes()]


# ---- lifecycle ----
def force_stop():
    adb("shell", "am", "force-stop", PKG); time.sleep(1.5)


def launch(wait=True):
    out = adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    m = re.search(r"TotalTime:\s*(\d+)", out)
    if wait:
        time.sleep(5)
    return int(m.group(1)) if m else -1


# ---- logs ----
def log_clear():
    adb("logcat", "-c")


def log_save(name):
    p = pid()
    parts = []
    if p:
        parts.append(adb("logcat", "-d", f"--pid={p}"))
    parts.append(adb("logcat", "-d", "-s",
                     "AndroidRuntime:E", "DEBUG:F", "libc:F", "ActivityManager:E",
                     "StrictMode:*", "flutter:*", "org.webrtc:*", "libwebrtc:*",
                     "FirebaseMessaging:*", "SecureChat:*", "Telecom:*"))
    path = LOGS / f"{name}.log"
    path.write_text("\n".join(parts), errors="replace")
    return path


SIGNAL_RE = re.compile(
    r"FATAL|AndroidRuntime|ANR in|E/flutter|Unhandled|StrictMode|"
    r"OutOfMemory|SIGSEGV|SIGABRT|Exception|Diagnostics event=", re.I)


def log_signals(path, limit=25):
    hits = []
    for i, line in enumerate(path.read_text(errors="replace").splitlines(), 1):
        if SIGNAL_RE.search(line) and "ExceptionHandler installed" not in line:
            hits.append(f"{path.name}:{i}: {line.strip()[:220]}")
        if len(hits) >= limit:
            break
    return hits


# ---- crash reports on device ----
def crash_reports():
    out = sh(f"run-as {PKG} ls /data/data/{PKG}/files/crash_logs/ 2>/dev/null")
    return [f for f in out.split() if f.startswith("crash_")]


def read_crash(name):
    raw = sh(f"run-as {PKG} cat /data/data/{PKG}/files/crash_logs/{name}")
    try:
        return json.loads(raw)
    except Exception:
        return {"raw": raw[:2000]}


# ---- mock server ----
def mock(path, payload=None):
    url = f"{MOCK}{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        url, data=data,
        headers={"Content-Type": "application/json", "Authorization": "Bearer qa"},
        method="POST" if data else "GET")
    with urllib.request.urlopen(req, context=_ctx, timeout=15) as r:
        body = r.read().decode()
    return json.loads(body) if body else {}


def events(since=0):
    return mock(f"/__qa/events?since={since}")


def event_count():
    return mock("/__qa/state")["events"]


def wait_event(since, predicate, timeout=20, poll=0.7):
    """Belirli bir mock olayi gelene kadar bekler."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        evs = events(since)["events"]
        for e in evs:
            if predicate(e):
                return e
        time.sleep(poll)
    return None


# ---- perf ----
def meminfo():
    out = sh(f"dumpsys meminfo {PKG}")
    m = re.search(r"TOTAL PSS:\s*(\d+)", out)
    n = re.search(r"^\s*Native Heap\s+(\d+)", out, re.M)
    d = re.search(r"^\s*Dalvik Heap\s+(\d+)", out, re.M)
    g = re.search(r"Graphics:\s*(\d+)", out)
    v = re.search(r"Views:\s*(\d+)", out)
    return {
        "pss_kb": int(m.group(1)) if m else -1,
        "native_kb": int(n.group(1)) if n else -1,
        "dalvik_kb": int(d.group(1)) if d else -1,
        "graphics_kb": int(g.group(1)) if g else -1,
        "views": int(v.group(1)) if v else -1,
    }


def gfx_reset():
    sh(f"dumpsys gfxinfo {PKG} reset")


def gfxinfo():
    out = sh(f"dumpsys gfxinfo {PKG}")
    def grab(pat, cast=float):
        m = re.search(pat, out)
        return cast(m.group(1)) if m else -1
    return {
        "frames": grab(r"Total frames rendered: (\d+)", int),
        "janky": grab(r"Janky frames: (\d+)", int),
        "janky_pct": grab(r"Janky frames: \d+ \(([\d.]+)%\)"),
        "p50": grab(r"50th percentile: (\d+)ms", int),
        "p90": grab(r"90th percentile: (\d+)ms", int),
        "p95": grab(r"95th percentile: (\d+)ms", int),
        "p99": grab(r"99th percentile: (\d+)ms", int),
        "missed_vsync": grab(r"Number Missed Vsync: (\d+)", int),
    }


def cpu():
    """Uygulama surecinin %CPU degeri. top ciktisinda PID ile baslayan satiri
    bulur ve S (state) sutunundan sonraki alani okur."""
    p = pid()
    if not p:
        return -1.0
    out = sh(f"top -b -n 1 -p {p}")
    for line in out.splitlines():
        parts = line.split()
        if len(parts) > 9 and parts[0] == p:
            for token in parts[7:]:
                try:
                    return float(token)
                except ValueError:
                    continue
    return -1.0


# ---- results ----
def record(name, steps, expected, observed, status, evidence=None, severity=None,
           screenshot=None, area=None):
    entry = {
        "name": name, "area": area or "", "steps": steps, "expected": expected,
        "observed": observed, "status": status,
        "evidence": evidence or [], "severity": severity,
        "screenshot": screenshot, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
    }
    with RESULTS.open("a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    mark = {"PASS": "PASS", "FAIL": "FAIL", "BLOCKED": "BLOCKED", "WARN": "WARN"}.get(status, status)
    print(f"[{mark}] {name}  -- {observed[:150]}")
    return entry


# ---- sohbet yardimcilari ----
def composer_focus():
    """Composer'a odaklan; klavye acilana kadar dener."""
    for x, y in ((400, 2097), (300, 2094), (500, 2090)):
        tap(x, y, settle=1.4)
        if "true" in sh("dumpsys input_method | grep mInputShown").lower():
            return True
    return False


def clear_composer(max_chars=2400):
    """Composer'da artik metin kalmasin diye secip siler."""
    if not composer_focus():
        return
    # Ctrl+A (keyevent 29 with meta) guvenilir degil; DEL ile temizle.
    adb("shell", "input", "keyevent", "--longpress", *(["67"] * 60))
    for _ in range(max_chars // 60):
        if not find("Gönder"):
            return
        adb("shell", "input", "keyevent", *(["67"] * 60))
    return


def send_message(text, settle=3.0, retries=3):
    """Composer'a yaz ve Gonder'e bas. Basarili ise True."""
    if not composer_focus():
        return False
    esc = text.replace("%", "%%").replace(" ", "%s")
    # cok uzun metinleri parcali gonder: adb input text tek seferde bogulabiliyor
    for i in range(0, len(esc), 500):
        adb("shell", "input", "text", esc[i:i + 500])
        time.sleep(0.5)
    time.sleep(1.4)
    for attempt in range(retries):
        node = send_button()
        if node is not None:
            tap(node["x"], node["y"], settle=settle)
            return True
        time.sleep(1.2)
    return False


def send_button(nodes=None):
    """Gonder butonu: tam esleme + composer bolgesi. 'Gonderildi' baloncugu ile
    karistirmamak icin ikisi de gerekli."""
    for n in (nodes if nodes is not None else ui_nodes()):
        if n["label"].strip() == "Gönder" and n["class"] == "Button":
            return n
    return None


def bubbles():
    """Sohbet baloncuklarinin metinleri."""
    skip = ("Geri", "Sesli ara", "Görüntülü ara", "Daha Fazla", "Ek ekle",
            "Tek gösterim", "Sesli mesaj kaydet", "Gönder", "En yeni mesaja git")
    out = []
    for n in ui_nodes():
        label = n["label"]
        if any(label.startswith(s) for s in skip):
            continue
        if n["y"] < 260 or n["y"] > 1990:
            continue
        out.append(label.replace("\n", " | "))
    return out
