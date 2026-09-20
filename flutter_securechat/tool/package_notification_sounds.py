#!/usr/bin/env python3
"""Secilen ses dosyalarini bildirim sesi olarak paketler.

NEDEN BU ARAC VAR: sesler once sifirdan sentezlendi (dort tur, farkli
yaklasimlarla) ve hicbiri begenilmedi. Sentezin olculebilir ozellikleri
referansla eslestirilebiliyor ama 'hosa gidiyor mu' oyle olculmuyor.
Dogru is bolumu: sesi INSAN secer, arac hazirlar.

NE YAPAR
  - Herhangi bir ses bicimini (mp3, m4a, wav, ...) mono 44.1 kHz WAV'a cevirir.
    Hem iOS (`UNNotificationSound`) hem Android (raw kaynak) WAV kabul ediyor,
    yani tek dosya iki platforma yetiyor ve CAF donusumu gerekmiyor.
  - Bastaki sessizligi kirpar. Bildirim sesi gecikmeli baslamamali; indirilen
    dosyalarda cogu zaman 100 ms'e varan bosluk oluyor.
  - Seviyeyi -8 dBFS tepeye esitler. Bildirim sesleri sistem sesleriyle ayni
    seviyede durmali; sonuna kadar doldurulmus bir dosya bagiriyor. Ayrica
    listedeki sesler birbirine gore esit yuksek olmali, yoksa secim yaparken
    en yuksek olan 'daha iyi' saniliyor.
  - Sonu 10 ms sondurur: ani kesilme 'tik' sesi uretir.
  - 30 saniyeyi asan dosyayi reddeder (iOS siniri).

LISANS: eklenen her sesin kullanim hakki DOGRULANMALI. Apple'in sistem
sesleri telifli; internette dolasan "iOS notification sound" dosyalarinin
buyuk kismi bunlarin kopyasi ve uygulamaya gomulmeleri hem ihlal olur hem
magaza incelemesinde takilir.

Kullanim:
    python3 tool/package_notification_sounds.py <ad>=<dosya> [<ad>=<dosya> ...]

Ornek:
    python3 tool/package_notification_sounds.py \\
        elcim_chime=~/Downloads/secilen.mp3 elcim_bell=~/Downloads/digeri.mp3
"""

import os
import struct
import subprocess
import sys
import wave

import numpy as np

RATE = 44100
TARGET_PEAK = 0.40      # -8 dBFS
MAX_SECONDS = 30.0      # iOS siniri


def prepare(source):
    temporary = "/tmp/_notification_sound.wav"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-i", source, "-ac", "1", "-ar", str(RATE),
         "-y", temporary],
        check=True,
    )
    with wave.open(temporary) as handle:
        data = np.frombuffer(
            handle.readframes(handle.getnframes()), dtype="<i2"
        ).astype(float) / 32768.0
    os.remove(temporary)

    peak = float(np.max(np.abs(data)))
    if peak == 0:
        raise ValueError("dosya sessiz")

    # Bastaki ve sondaki sessizligi kirp.
    loud = np.where(np.abs(data) > peak * 0.02)[0]
    start = max(0, loud[0] - int(0.005 * RATE))
    end = min(len(data), loud[-1] + int(0.02 * RATE))
    data = data[start:end]

    if len(data) / RATE > MAX_SECONDS:
        raise ValueError(f"{len(data) / RATE:.1f} s — iOS siniri {MAX_SECONDS} s")

    data = data / float(np.max(np.abs(data))) * TARGET_PEAK
    fade = int(0.010 * RATE)
    if len(data) > fade:
        data[-fade:] *= np.linspace(1.0, 0.0, fade) ** 0.5
    return data


def write(path, data):
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in data
    )
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(frames)


def main(arguments):
    if not arguments:
        print(__doc__)
        return 2
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    targets = [
        os.path.join(root, "ios", "Runner", "Sounds"),
        os.path.join(root, "android", "app", "src", "main", "res", "raw"),
    ]
    for directory in targets:
        os.makedirs(directory, exist_ok=True)

    for argument in arguments:
        if "=" not in argument:
            print(f"Beklenen bicim <ad>=<dosya>: {argument}", file=sys.stderr)
            return 2
        name, source = argument.split("=", 1)
        # Android raw kaynak adlari: yalniz kucuk harf, rakam ve alt cizgi.
        if not name.replace("_", "").isalnum() or not name.islower():
            print(f"Ad kucuk harf, rakam ve alt cizgi olmali: {name}",
                  file=sys.stderr)
            return 2
        data = prepare(os.path.expanduser(source))
        for directory in targets:
            write(os.path.join(directory, f"{name}.wav"), data)
        print(f"{name}.wav  {len(data) / RATE:.2f} s  tepe -8.0 dBFS")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
