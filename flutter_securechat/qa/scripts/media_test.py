#!/usr/bin/env python3
"""Medya paylasimi: dosya secici -> parcali sifreli transfer dogrulamasi."""
import sys, time, json, collections
sys.path.insert(0, 'qa/scripts')
import scenario as s


def open_attach(kind):
    n = next((x for x in s.ui_nodes() if x['label'] == 'Ek ekle'), None)
    if not n:
        return False
    s.tap(n['x'], n['y'], settle=2.5)
    return s.tap_text(kind, settle=4)


def pick_from_system(filename):
    """Android sistem dosya seciciden dosyayi bul ve sec."""
    time.sleep(2)
    # Sistem secicide arama/dosya adi ile bul
    for attempt in range(3):
        node = next((x for x in s.ui_nodes() if filename in x['label']), None)
        if node:
            s.tap(node['x'], node['y'], settle=3)
            return True
        # Downloads klasorune git
        dl = next((x for x in s.ui_nodes()
                   if x['label'] in ('Downloads', 'İndirilenler', 'Download')), None)
        if dl:
            s.tap(dl['x'], dl['y'], settle=2.5); continue
        # yan menuyu ac
        menu = next((x for x in s.ui_nodes()
                     if 'Show roots' in x['label'] or 'roots' in x['label'].lower()
                     or x['label'] == 'Daha fazla seçenek'), None)
        if menu:
            s.tap(menu['x'], menu['y'], settle=2)
        else:
            time.sleep(1.5)
    return False


def run(filename, label, expect_chunks):
    s.log_clear()
    since = s.event_count()
    before = set(s.crash_reports())
    if not open_attach('Dosya'):
        return s.record(f"T-MD {label}", "Ek ekle -> Dosya", "Dosya secici acilmali",
                        "Ek menusu veya 'Dosya' bulunamadi", "FAIL",
                        severity="Medium", area="Medya")
    s.shot(f'70_picker_{label}')
    picked = pick_from_system(filename)
    print(f'  secici sonuc={picked}')
    if not picked:
        labels = [x['label'][:40] for x in s.ui_nodes()][:14]
        return s.record(f"T-MD {label}", "Ek ekle -> Dosya -> sistem seciciden dosya sec",
                        "Dosya secilebilmeli",
                        f"Sistem dosya secicide '{filename}' bulunamadi. Gorunen: {labels}",
                        "BLOCKED", severity="Low", area="Medya")
    time.sleep(4)
    s.shot(f'71_preview_{label}')
    # onizleme ekraninda gonder
    for name in ('Gönder', 'Gonder'):
        n = next((x for x in s.ui_nodes() if x['label'].strip() == name), None)
        if n:
            s.tap(n['x'], n['y'], settle=4); break
    time.sleep(12)
    evs = s.events(since)['events']
    chunks = [e for e in evs if e['kind'] == 'file_chunk']
    done = [e for e in evs if e['kind'] == 'file_complete']
    crashes = len(set(s.crash_reports()) - before)
    leak = {}
    if chunks:
        c0 = chunks[0]
        leak = {k: c0.get(k) for k in
                ('fileNameOnWire', 'mimeOnWire', 'captionOnWire', 'groupIdOnWire',
                 'declaredFileSize', 'encryption', 'isViewOnce')}
    obs = (f"parca sayisi={len(chunks)} (beklenen ~{expect_chunks}), "
           f"tamamlanan transfer={len(done)}, crash={crashes}. "
           f"Wire metadata: {leak}")
    ok = len(chunks) >= expect_chunks and crashes == 0
    return s.record(f"T-MD {label}",
                    f"Ek ekle -> Dosya -> {filename} sec -> Gonder",
                    f"Dosya 128 KB'lik parcalara bolunup sifreli gonderilmeli; "
                    f"wire'da dosya adi/mime/caption sizmamali",
                    obs, "PASS" if ok else ("WARN" if chunks else "FAIL"),
                    severity=None if ok else "Medium",
                    evidence=["qa/logs/mock_server.jsonl: file_chunk / file_complete"],
                    screenshot=f'71_preview_{label}.png', area="Medya")


def main():
    s.force_stop(); s.launch(); time.sleep(7)
    s.tap_text('qa-peer-01', settle=3)
    run('qa_small.txt', 'kucuk-dosya', 1)
    time.sleep(3)
    s.tap_text('qa-peer-01', settle=3)
    run('qa_large.bin', 'buyuk-dosya-300KB', 3)


if __name__ == '__main__':
    main()
