#!/usr/bin/env python3
"""Flutter SurfaceView icin jank olcumu (SurfaceFlinger timestats).

dumpsys gfxinfo Flutter'da 0 kare dondurur (HWUI bypass), --latency ise
Android 13+ uzerinde bos donuyor. timestats her ikisinin yerine gecer.
"""
import sys, time, re, json
sys.path.insert(0, 'qa/scripts')
import scenario as s


def reset():
    s.sh('dumpsys SurfaceFlinger --timestats -clear')
    s.sh('dumpsys SurfaceFlinger --timestats -enable')
    time.sleep(0.5)


def collect():
    out = s.sh('dumpsys SurfaceFlinger --timestats -dump')
    def num(key, cast=int):
        m = re.search(rf'^{key}\s*=\s*([\d.]+)', out, re.M)
        return cast(m.group(1)) if m else -1
    hist = {}
    m = re.search(r'presentToPresent histogram is as below:\n(.+)', out)
    if m:
        for tok in m.group(1).split():
            k, _, v = tok.partition('=')
            if v.isdigit() and int(v) > 0:
                hist[int(k.replace('ms', ''))] = int(v)
    return {
        'totalFrames': num('totalFrames'),
        'missedFrames': num('missedFrames'),
        'refreshHz': num('displayRefreshRate'),
        'avgFrameDurationMs': num('averageFrameDuration', float),
        'presentToPresent': hist,
    }


def summarise(raw, label):
    hz = raw['refreshHz'] if raw['refreshHz'] > 0 else 60
    target = 1000.0 / hz
    hist = raw['presentToPresent']
    # Jest araligi bosluklarini (>200ms) hariç tut: bunlar jank degil, bosta bekleme.
    active = {k: v for k, v in hist.items() if k <= 200}
    total = sum(active.values())
    smooth = sum(v for k, v in active.items() if k <= target * 1.5)
    dropped = sum(v for k, v in active.items() if k > target * 1.5)
    return {
        'label': label,
        'refreshHz': hz,
        'hedefKareSuresiMs': round(target, 2),
        'olculenKare': total,
        'akiciKare': smooth,
        'geckenKare': dropped,
        'jankYuzdesi': round(100.0 * dropped / total, 2) if total else 0,
        'missedFrames': raw['missedFrames'],
        'ortKareSuresiMs': raw['avgFrameDurationMs'],
        'histogramMs': dict(sorted(active.items())),
    }


def run(label, action):
    reset()
    action()
    time.sleep(0.6)
    return summarise(collect(), label)


def main():
    results = []

    def scroll_list():
        for _ in range(12):
            s.swipe(540, 1600, 540, 600, 200); time.sleep(0.15)
            s.swipe(540, 600, 540, 1600, 200); time.sleep(0.15)
    results.append(run('Sohbet listesi kaydirma', scroll_list))

    s.tap_text('qa-peer-01', settle=2.5)

    def scroll_chat():
        for _ in range(12):
            s.swipe(540, 1500, 540, 700, 200); time.sleep(0.15)
            s.swipe(540, 700, 540, 1500, 200); time.sleep(0.15)
    results.append(run('Sohbet ekrani kaydirma', scroll_chat))
    s.key(4, settle=2)

    def tabs():
        for _ in range(8):
            for x in (135, 405, 675, 945):
                s.tap(x, 2226, settle=0.45)
    results.append(run('Sekme gecisleri', tabs))

    perf = json.load(open('qa/reports/perf.json'))
    perf['jank'] = {r['label']: r for r in results}
    json.dump(perf, open('qa/reports/perf.json', 'w'), indent=1)
    for r in results:
        print(f"{r['label']:<28} {r['refreshHz']}Hz hedef={r['hedefKareSuresiMs']}ms "
              f"kare={r['olculenKare']} akici={r['akiciKare']} gecen={r['geckenKare']} "
              f"jank=%{r['jankYuzdesi']} missedFrames={r['missedFrames']}")


if __name__ == '__main__':
    main()
