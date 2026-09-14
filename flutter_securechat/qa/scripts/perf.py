#!/usr/bin/env python3
import sys, time, json, statistics
sys.path.insert(0, 'qa/scripts')
import scenario as s

perf = {"startup": {}, "memory": {}, "jank": {}, "cpu": {}, "notes": []}

# --- 1. Soguk baslatma (3 tur) ---
cold = []
for i in range(3):
    s.force_stop(); time.sleep(2)
    s.sh("am kill-all")
    t = s.launch(); time.sleep(4)
    cold.append(t)
perf["startup"]["Soguk baslatma (3 tur medyan)"] = int(statistics.median(cold))
perf["startup"]["Soguk baslatma (min/maks)"] = f"{min(cold)} / {max(cold)}"

# --- 2. Sicak baslatma ---
warm = []
for i in range(3):
    s.key(3); time.sleep(2)          # HOME
    t = s.launch(); time.sleep(3)
    warm.append(t)
perf["startup"]["Sicak baslatma (3 tur medyan)"] = int(statistics.median(warm))

# --- 3. Bellek: bosta ---
time.sleep(3)
perf["memory"]["Bosta (ana ekran)"] = s.meminfo()
perf["cpu"]["Bosta"] = s.cpu()

# --- 4. Jank: sohbet listesi kaydirma ---
s.gfx_reset()
for _ in range(8):
    s.swipe(540, 1600, 540, 600, 250); time.sleep(0.35)
    s.swipe(540, 600, 540, 1600, 250); time.sleep(0.35)
perf["jank"]["Sohbet listesi kaydirma"] = s.gfxinfo()

# --- 5. Sohbette: mesaj gonderme dongusu + bellek trendi (sizinti) ---
s.tap_text('qa-peer-01', settle=3)
s.gfx_reset()
trend = []
for i in range(10):
    s.send_message(f"perf-{i}", settle=1.2)
    if i % 3 == 0:
        trend.append(s.meminfo()["pss_kb"])
perf["jank"]["Sohbet ekrani (10 mesaj gonderimi)"] = s.gfxinfo()
perf["memory"]["Mesajlasma sirasinda"] = s.meminfo()
perf["cpu"]["Mesajlasma sirasinda"] = s.cpu()
perf["memory_trend_kb"] = trend

# --- 6. Sohbet ac/kapat dongusu (sizinti avi) ---
s.key(4, settle=2)
leak = []
for i in range(12):
    s.tap_text('qa-peer-01', settle=1.4)
    s.key(4, settle=1.2)
    if i % 3 == 0:
        leak.append(s.meminfo()["pss_kb"])
perf["memory"]["12x sohbet ac/kapat sonrasi"] = s.meminfo()
perf["leak_cycle_kb"] = leak

json.dump(perf, open('qa/reports/perf.json', 'w'), indent=1)
print(json.dumps(perf, indent=1)[:2200])
