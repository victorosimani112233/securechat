#!/usr/bin/env python3
"""qa/reports/results.jsonl + olcumlerden tek markdown rapor uretir."""
import json
import collections
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "reports" / "results.jsonl"
PERF = ROOT / "reports" / "perf.json"
OUT = ROOT / "reports" / "QA_RAPORU.md"

SEV_ORDER = {"Critical": 0, "High": 1, "Medium": 2, "Low": 3, None: 4}
STATUS_ICON = {"PASS": "PASS", "FAIL": "FAIL", "WARN": "WARN", "BLOCKED": "BLOCKED"}


def rows():
    if not RESULTS.exists():
        return []
    out = []
    for line in RESULTS.read_text().splitlines():
        if line.strip():
            out.append(json.loads(line))
    return out


def esc(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def main():
    data = rows()
    counts = collections.Counter(r["status"] for r in data)
    bugs = [r for r in data if r["severity"] and r["status"] in ("FAIL", "WARN", "BLOCKED")]
    bugs.sort(key=lambda r: SEV_ORDER.get(r["severity"], 4))
    by_area = collections.defaultdict(list)
    for r in data:
        by_area[r["area"] or "Diger"].append(r)

    perf = json.loads(PERF.read_text()) if PERF.exists() else {}

    L = []
    add = L.append
    add("# SecureChat (elçim) — Cihaz Üzerinde QA Raporu")
    add("")
    add("## Kapsam ve ortam")
    add("")
    add("| Alan | Değer |")
    add("|---|---|")
    add("| Cihaz | Samsung SM-S921B (Galaxy S24), Android 14, API 34 |")
    add("| Ekran | 1080x2340 @480dpi |")
    add("| ADB seri | RFCY601MDPT |")
    add("| Paket | `com.securechat.app.debug` v1.0.76-debug (versionCode 76) |")
    add("| Uygulama tipi | Flutter (122 dart dosyası, ~41.8k satır) |")
    add("| Sunucu | Yok — yerine çok istemcili lokal mock (TLS, pinlenmiş) |")
    add("| Mock adresi | `https://127.0.0.1:18444` (adb reverse) |")
    add("| Kaynak değişikliği | **Yok** — yalnızca `--dart-define` build bayrakları |")
    add("")
    add("### Senaryo özeti")
    add("")
    add("| Sonuç | Adet |")
    add("|---|---|")
    for k in ("PASS", "FAIL", "WARN", "BLOCKED"):
        add(f"| {k} | {counts.get(k, 0)} |")
    add(f"| **Toplam** | **{len(data)}** |")
    add("")

    if bugs:
        add("## Bulgular (önem sırasına göre)")
        add("")
        for i, b in enumerate(bugs, 1):
            add(f"### {i}. {b['name']}")
            add("")
            add(f"- **Önem:** {b['severity']}  ·  **Sonuç:** {b['status']}  ·  **Alan:** {b['area']}")
            add(f"- **Tekrar üretme:** {b['steps']}")
            add(f"- **Beklenen:** {b['expected']}")
            add(f"- **Gözlenen:** {b['observed']}")
            if b.get("evidence"):
                add("- **Kanıt:**")
                for e in b["evidence"]:
                    add(f"  - `{e}`")
            if b.get("screenshot"):
                add(f"- **Ekran görüntüsü:** `qa/screenshots/{b['screenshot']}`")
            add("")

    add("## Senaryo detayları")
    add("")
    for area in sorted(by_area):
        add(f"### {area}")
        add("")
        add("| Senaryo | Beklenen | Gözlenen | Sonuç |")
        add("|---|---|---|---|")
        for r in by_area[area]:
            add(f"| {esc(r['name'])} | {esc(r['expected'])[:150]} | {esc(r['observed'])[:260]} | {STATUS_ICON.get(r['status'], r['status'])} |")
        add("")

    if perf:
        add("## Performans ölçümleri")
        add("")
        if perf.get("startup"):
            add("### Başlatma süresi")
            add("")
            add("| Senaryo | TotalTime (ms) | Eşik önerisi |")
            add("|---|---|---|")
            for k, v in perf["startup"].items():
                add(f"| {k} | {v} | < 2000 (debug), < 1000 (release) |")
            add("")
        if perf.get("memory"):
            add("### Bellek (dumpsys meminfo)")
            add("")
            add("| Durum | PSS (MB) | Native (MB) | Dalvik (MB) | Graphics (MB) | Views |")
            add("|---|---|---|---|---|---|")
            for k, v in perf["memory"].items():
                add(f"| {k} | {v['pss_kb']//1024} | {v['native_kb']//1024} | "
                    f"{v['dalvik_kb']//1024} | {v['graphics_kb']//1024} | {v['views']} |")
            add("")
        if perf.get("jank"):
            add("### Grafik / jank (SurfaceFlinger timestats)")
            add("")
            add("| Senaryo | Ekran | Hedef kare (ms) | Ölçülen kare | Akıcı | Geçen | Jank % | missedFrames |")
            add("|---|---|---|---|---|---|---|---|")
            for k, v in perf["jank"].items():
                add(f"| {k} | {v.get('refreshHz','-')} Hz | {v.get('hedefKareSuresiMs','-')} | "
                    f"{v.get('olculenKare','-')} | {v.get('akiciKare','-')} | {v.get('geckenKare','-')} | "
                    f"{v.get('jankYuzdesi','-')} | {v.get('missedFrames','-')} |")
            add("")
        if perf.get("leak_cycle_kb") or perf.get("memory_trend_kb"):
            add("### Bellek sızıntısı trendi")
            add("")
            add("| Ölçüm | Değerler (KB) | Yorum |")
            add("|---|---|---|")
            if perf.get("memory_trend_kb"):
                t = perf["memory_trend_kb"]
                add(f"| 10 mesaj gönderimi | {t} | {'düz, artış yok' if t[-1] <= t[0]*1.02 else 'artış var'} |")
            if perf.get("leak_cycle_kb"):
                t = perf["leak_cycle_kb"]
                add(f"| 12x sohbet aç/kapat | {t} | {'birikme yok' if t[-1] <= t[0]*1.02 else 'artış var'} |")
            add("")

        if perf.get("cpu"):
            add("### CPU (top)")
            add("")
            add("| Durum | %CPU |")
            add("|---|---|")
            for k, v in perf["cpu"].items():
                add(f"| {k} | {v} |")
            add("")
        if perf.get("notes"):
            for n in perf["notes"]:
                add(f"> {n}")
            add("")

    add("## Kapsam özeti")
    add("")
    add("| Özellik alanı | Durum | Not |")
    add("|---|---|---|")
    for area in sorted(by_area):
        rs = by_area[area]
        n_pass = sum(1 for r in rs if r["status"] == "PASS")
        n_fail = sum(1 for r in rs if r["status"] == "FAIL")
        n_warn = sum(1 for r in rs if r["status"] == "WARN")
        n_blk = sum(1 for r in rs if r["status"] == "BLOCKED")
        if n_fail:
            verdict = "açık bulgu var"
        elif n_blk:
            verdict = "kısmi (engelli)"
        elif n_warn:
            verdict = "kapandı (uyarılı)"
        else:
            verdict = "kapandı"
        add(f"| {area} | {verdict} | {n_pass} PASS, {n_fail} FAIL, {n_warn} WARN, {n_blk} BLOCKED |")
    add("")

    add("## Açık riskler")
    add("")
    for line in [
        "**Oturum kurtarma yok (BUG-009, Critical).** Karşı taraf uygulamayı yeniden kurarsa "
        "o sohbet kalıcı olarak ölüyor ve kullanıcı hiçbir uyarı almıyor (BUG-010, BUG-011). "
        "Üretimde en yüksek etkili bulgu bu; tek bir kişinin telefon değiştirmesi sohbeti bitiriyor.",
        "**Sessiz veri kaybı (BUG-011, High).** Çözülemeyen gelen mesaj hiçbir iz bırakmadan "
        "düşüyor: log yok, crash raporu yok, sayaç yok. Üretimde bu sınıf hatayı teşhis etmek "
        "imkânsız olur.",
        "**Tek-gösterim garantisi listede deliniyor (BUG-013, High).** Açılmamış mesajın düz "
        "metni sohbet listesi önizlemesinde görünüyor.",
        "**Gözlemlenebilirlik neredeyse sıfır.** 41.8k satırda tek bir `debugPrint` var ve o da "
        "yalnızca `kDebugMode`. Crash raporu halkası 20 dosyada sınırlı; bu oturumda halka doldu "
        "ve önceki kanıtlar tahliye oldu. Üretim teşhisi için yetersiz.",
        "**Cihaz saati 18 ay geride (BUG-002).** Kaybolan mesaj zamanlayıcısı, JWT süresi ve "
        "mesaj sıralaması bu ortamda güvenilir test edilemedi.",
    ]:
        add(f"- {line}")
    add("")

    add("## Sunucu geldiğinde ek olarak test edilmesi gerekenler")
    add("")
    for line in [
        "Gerçek OTP e-postası ile kayıt akışı; SMTP kapalı ve rate-limit yollarının canlı doğrulaması.",
        "Refresh token rotasyonu ve `1008` sonrası gerçek yeniden yetkilendirme.",
        "Gerçek FCM push ile uyandırma (bu cihazda Play Services `241518038` < gerekli `261200000`; "
        "ayrıca `google-services.json` bu derlemede yok).",
        "Sunucu tarafı prekey havuzu tükenmesi ve `prekeys/refresh` davranışı.",
        "Janus SFU ile gerçek grup çağrısı medya yolu (`sfu_room_created`, `janusWsUrl`).",
        "TURN/STUN üzerinden NAT arkası gerçek ICE bağlantısı.",
        "Sunucu tarafı hesap silme ve `account/delete` sonrası gerçek veri temizliği.",
        "Private directory'nin production anahtar rotasyonu (`DirectoryKeyChangedException` yolu).",
    ]:
        add(f"- {line}")
    add("")

    add("## Gerçek ikinci cihazla tekrar doğrulanması gerekenler")
    add("")
    add("Aşağıdaki sonuçlar **simüle karşı taraf** (mock sunucudaki sanal peer) ile alındı. "
        "Sanal peer gerçek `libsignal_protocol_dart` kimliği taşır ve X3DH/Double Ratchet'i "
        "gerçekten çalıştırır, ancak WebRTC medya düzlemi gerçek değildir.")
    add("")
    for line in [
        "1:1 sesli/görüntülü çağrıda gerçek DTLS/SRTP kurulumu ve iki yönlü medya akışı "
        "(bu turda çağrı 'Bağlanıyor…' aşamasında kaldı — sanal peer gerçek medya üretemiyor).",
        "Grup çağrısı mesh/SFU davranışı, katılımcı ekleme-çıkarma.",
        "Gerçek karşı tarafta mesaj teslim/okundu makbuzlarının uçtan uca doğrulanması.",
        "Sender-key dağıtımının gerçek ikinci istemcide çözülmesi ve grup mesajının okunması.",
        "Tek-gösterim medyanın karşı tarafta ekran görüntüsü engeli (release build gerekir).",
        "Dosya transferinin karşı tarafta yeniden birleştirilmesi ve açılması.",
    ]:
        add(f"- {line}")
    add("")

    add("## Test altyapısı (yeniden kullanım için)")
    add("")
    add("| Bileşen | Yol | Not |")
    add("|---|---|---|")
    add("| Mock sunucu (TLS, çok istemcili) | `qa/mock/bin/server.dart` | Sanal peer'ler gerçek Signal kimliği taşır |")
    add("| Private directory (blind-RSA OPRF) | `qa/mock/bin/directory.dart` | RSA-3072, istemciyle bit-uyumlu |")
    add("| Sözleşme probu | `qa/mock/bin/probe.dart` | Cihaza dokunmadan 17 kontrat kontrolü |")
    add("| Senaryo koşucusu | `qa/scripts/scenario.py` | UI + log + mock olayı + kanıt kaydı |")
    add("| Cihaz yardımcıları | `qa/scripts/dev.sh` | Tümü `-s <serial>` parametreli |")
    add("| QA APK derleme | `qa/scripts/build_qa_apk.sh` | Kaynak değişikliği yok, sadece dart-define |")
    add("| Mock yaşam döngüsü | `qa/scripts/mock.sh` | start/stop/restart/rebuild/status |")
    add("| Jank ölçümü | `qa/scripts/jank.py` | SurfaceFlinger timestats (gfxinfo Flutter'da geçersiz) |")
    add("")
    add("**İkinci fiziksel cihaz eklemek için:** `SC_SERIAL=<seri> adb -s <seri> reverse "
        "tcp:18444 tcp:18444` ve aynı QA APK'yı kur. Sunucuda değişiklik gerekmez — "
        "her istemci kendi `userId`'siyle kaydolur ve mesajlar gerçekten yönlendirilir.")
    add("")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(L))
    print(f"rapor yazildi: {OUT}  ({len(data)} senaryo, {len(bugs)} bulgu)")


if __name__ == "__main__":
    main()
