#!/usr/bin/env python3
"""Bildirim seslerini uretir.

NEDEN URETIYORUZ, INDIRMIYORUZ: Apple'in sistem sesleri telifli ve yalnizca
Apple isletim sistemleri icinde kullanilmak uzere lisansli. Uygulamaya
gomulmeleri hem ihlal olur hem magaza incelemesinde takilir. Internette
dolasan "iOS notification sound" dosyalarinin buyuk kismi bunlarin kopyasi.
Buradakiler sifirdan sentezleniyor.

BICIM: 44.1 kHz, 16-bit, mono WAV. Hem iOS (`UNNotificationSound`) hem
Android (raw kaynak) WAV kabul ediyor.

TASARIM NOTU — 'oyun sesi' ile 'premium' arasindaki fark

Ilk denemede sesler yapay ve oyun sesi gibi cikti. Sebepleri tek tek:

  - PERDE DUSUSU. Bir sesin frekansini calarken kaydirmak oyunlarin
    imzasidir; akustik bir cisim bunu yapmaz. Burada tamamen kaldirildi.
  - DERIN MODULASYON. Zengin gorunsun diye buyulen FM indeksi metalik ve
    sentetik bir renk uretiyor. Yerine gercek cisimlerin OLCULMUS ust ses
    oranlari kullaniliyor: marimba cubugu 1 : 3.93 : 9.55, boru can
    1 : 2.76 : 5.40 : 8.93. Bir sesi 'gercek' yapan sey bu oranlardir.
  - SERT ATAK. 1-3 ms atak tik gibi duyuluyor. Yumusak bir tokmak 8-20 ms
    surer.
  - KISA KUYRUK. Premium hissin buyuk kismi sonrasindaki havadan geliyor.
    Sesler uzatildi ve yanki payi artirildi.
  - FAZLA PARLAKLIK. Temel frekanslar dusuruldu; sertlik 4 kHz ustunde.

Kullanim:  python3 tool/generate_notification_sounds.py
"""

import os
import struct
import wave

import numpy as np

RATE = 44100
PEAK = 0.72

# Gercek cisimlerden olculmus ust ses oranlari. Tam sayi olmamalari
# tesadufi degil: bir cubugun ya da canin titresim kiplerinin frekanslari
# temel frekansin tam katlari DEGILDIR.
MARIMBA = ([1.0, 3.93, 9.55], [1.00, 0.20, 0.05])
BELL = ([1.0, 2.76, 5.40, 8.93], [1.00, 0.42, 0.18, 0.07])
GLASS = ([1.0, 2.40, 4.10, 6.80], [1.00, 0.30, 0.12, 0.05])


def tone(frequency, duration, shape, decay, attack=0.012, brightness=1.0):
    """Bir notayi ust seslerinin toplami olarak uretir.

    Yuksek ust sesler daha hizli soner: parlaklik sesten ONCE cekilir.
    Gercek bir cismin davranisi budur ve 'dogal' algisinin buyuk kismi
    buradan gelir.
    """
    ratios, gains = shape
    length = int(duration * RATE)
    t = np.linspace(0.0, duration, length, endpoint=False)
    attack_samples = max(1, int(attack * RATE))
    # Yarim kosinus atak: dogrusaldan yumusak, tik uretmiyor.
    attack_curve = 0.5 - 0.5 * np.cos(
        np.linspace(0.0, np.pi, attack_samples)
    )

    signal = np.zeros(length)
    for ratio, gain in zip(ratios, gains):
        partial_decay = decay * (1.0 + 0.9 * (ratio - 1.0) ** 0.6)
        envelope = np.exp(-partial_decay * t)
        envelope[:attack_samples] *= attack_curve
        signal += gain * (brightness ** (ratio - 1.0)) * np.sin(
            2.0 * np.pi * frequency * ratio * t
        ) * envelope
    return signal


def tail(signal, amount, seconds, damping=2400.0):
    """Yumusak kuyruk. Hicbir ses bosluga dogmaz."""
    n = int(seconds * RATE)
    rng = np.random.default_rng(23)
    impulse = rng.standard_normal(n) * np.exp(-np.linspace(0.0, 6.0, n))
    alpha = 1.0 - np.exp(-2.0 * np.pi * damping / RATE)
    accumulator = 0.0
    for index in range(n):
        accumulator += alpha * (impulse[index] - accumulator)
        impulse[index] = accumulator

    total = len(signal) + n
    dry = np.zeros(total)
    dry[: len(signal)] = signal
    wet = np.zeros(total)
    convolved = np.convolve(signal, impulse)[:total]
    wet[: len(convolved)] = convolved
    peak = float(np.max(np.abs(wet)))
    if peak > 0:
        wet *= float(np.max(np.abs(signal))) / peak
    return dry * (1.0 - amount) + wet * amount


def soften(signal, cutoff=4200.0):
    """Ust uclari yumusatir. Sertligin buyuk kismi 4 kHz ustunde."""
    alpha = 1.0 - np.exp(-2.0 * np.pi * cutoff / RATE)
    out = np.empty_like(signal)
    accumulator = 0.0
    for index, sample in enumerate(signal):
        accumulator += alpha * (sample - accumulator)
        out[index] = accumulator
    return out


def layer(parts, total):
    out = np.zeros(int(total * RATE))
    for offset, signal in parts:
        start = int(offset * RATE)
        end = min(len(out), start + len(signal))
        if end > start:
            out[start:end] += signal[: end - start]
    return out


def write(path, signal):
    data = soften(signal)
    peak = float(np.max(np.abs(data)))
    if peak > 0:
        data = data / peak * PEAK
    fade = int(0.008 * RATE)
    if len(data) > fade:
        data[-fade:] *= np.linspace(1.0, 0.0, fade) ** 0.5
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in data
    )
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(frames)
    return len(data) / RATE


# --- Sesler -----------------------------------------------------------------
# Araliklar uyumlu: buyuk ucluler ve tam besliler. Perde hareketi YOK.

def note():
    """Tek yumusak marimba notasi, uzun havali kuyruk. Varsayilan aday."""
    return tail(tone(587.33, 1.05, MARIMBA, decay=4.4, attack=0.010), 0.32, 0.55)


def chord():
    """Yumusak buyuk akor, hafif yayilmis. Sicak ve tanidik."""
    return tail(
        layer(
            [
                (0.000, tone(523.25, 1.00, MARIMBA, decay=4.6)),          # C5
                (0.055, tone(659.25, 0.95, MARIMBA, decay=4.8) * 0.80),   # E5
                (0.110, tone(783.99, 0.90, MARIMBA, decay=5.0) * 0.62),   # G5
            ],
            1.05,
        ),
        0.34,
        0.60,
    )


def glass():
    """Cam tinili tek nota. Parlak ama sert degil."""
    return tail(
        tone(880.00, 0.95, GLASS, decay=5.2, attack=0.008, brightness=0.9),
        0.36,
        0.55,
    )


def calm():
    """Iki alcak nota, yukselen tam besli. Sakin ve resmi."""
    return tail(
        layer(
            [
                (0.00, tone(392.00, 0.85, BELL, decay=5.0, attack=0.016)),      # G4
                (0.15, tone(587.33, 0.95, BELL, decay=4.6, attack=0.016) * .85),# D5
            ],
            1.10,
        ),
        0.30,
        0.55,
    )


def hush():
    """Alcak, tek vurus. Toplanti ve gece icin dikkat cekmeyen secenek."""
    return tail(
        tone(329.63, 0.60, MARIMBA, decay=7.0, attack=0.018, brightness=0.75),
        0.18,
        0.30,
    )


# --- Tok sesler -------------------------------------------------------------
#
# TELEFON HOPARLORU TUZAGI: kucuk hoparlorler ~300 Hz altini neredeyse hic
# basmaz. Temel frekansi dusurmek tek basina sesi tok YAPMAZ, tersine
# inceltir — hoparlorden yalniz ust sesler cikar.
#
# Tok his icin agirlik 200-500 Hz bandina konur ve ust sesler guclu
# tutulur; kulak eksik temeli bu harmoniklerden cikarir (eksik temel
# olgusu). Asagidaki oranlarda 2. ve 3. ust ses bilerek yuksek tutuldu.

# Kutuk davul / alcak tahta: temel zayif kalsa bile govdeyi 2. ve 3. ust ses
# tasir.
LOG = ([1.0, 2.0, 3.0, 4.6], [1.00, 0.62, 0.34, 0.12])
# Alcak can: yakin araliklarla vuru uretir, 'agirlik' hissini buyutur.
LOW_BELL = ([1.0, 2.02, 2.76, 4.10], [1.00, 0.55, 0.30, 0.10])


def body(signal, frequency, amount=0.35, decay=9.0):
    """Temel frekansin bir oktav ustune sicak bir katman ekler.

    Hoparlorun basamadigi temeli telafi eder: ayni notanin oktavi kucuk
    hoparlorde duyulur ve kulak asil temeli ondan cikarir.
    """
    length = len(signal)
    t = np.linspace(0.0, length / RATE, length, endpoint=False)
    layer_signal = np.sin(2.0 * np.pi * frequency * 2.0 * t) * np.exp(-decay * t)
    attack = max(1, int(0.012 * RATE))
    layer_signal[:attack] *= 0.5 - 0.5 * np.cos(
        np.linspace(0.0, np.pi, attack)
    )
    return signal + layer_signal * amount


def deep():
    """Alcak kutuk davul. Tok ve kisa; varsayilan tok aday."""
    base = tone(196.00, 0.90, LOG, decay=6.0, attack=0.014)          # G3
    return tail(body(base, 196.00, 0.30), 0.22, 0.40, damping=1600.0)


def knock():
    """Tahta kapi vurusu. Kuru, agir, cok kisa."""
    base = tone(146.83, 0.55, LOG, decay=10.0, attack=0.010, brightness=0.85)
    return tail(body(base, 146.83, 0.38, decay=14.0), 0.14, 0.24,
                damping=1300.0)


def gong():
    """Yumusak alcak can. Uzun kuyruk, agir govde."""
    base = tone(164.81, 1.40, LOW_BELL, decay=3.4, attack=0.020)     # E3
    return tail(body(base, 164.81, 0.26, decay=5.0), 0.34, 0.75,
                damping=1500.0)


def thud():
    """Alcak cift vurus. Sessiz ortamda bile duyulur ama rahatsiz etmez."""
    def hit(gain):
        return body(
            tone(130.81, 0.42, LOG, decay=12.0, attack=0.012, brightness=0.8),
            130.81, 0.40, decay=16.0,
        ) * gain                                                      # C3
    return tail(layer([(0.00, hit(1.0)), (0.16, hit(0.70))], 0.70), 0.16,
                0.26, damping=1200.0)


def warm():
    """Iki alcak nota, yukselen. Tok ama melodik."""
    return tail(
        layer(
            [
                (0.00, tone(174.61, 0.90, LOW_BELL, decay=5.4, attack=0.018)),
                (0.16, tone(261.63, 1.00, LOW_BELL, decay=4.8, attack=0.018)
                 * 0.88),
            ],
            1.20,
        ),
        0.28,
        0.55,
        damping=1700.0,
    )


SOUNDS = {
    # Tiz / parlak
    "elcim_note": note,
    "elcim_chord": chord,
    "elcim_glass": glass,
    "elcim_calm": calm,
    "elcim_hush": hush,
    # Tok / alcak
    "elcim_deep": deep,
    "elcim_knock": knock,
    "elcim_gong": gong,
    "elcim_thud": thud,
    "elcim_warm": warm,
}


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    targets = [
        os.path.join(root, "ios", "Runner", "Sounds"),
        os.path.join(root, "android", "app", "src", "main", "res", "raw"),
    ]
    for directory in targets:
        os.makedirs(directory, exist_ok=True)
    for name, builder in SOUNDS.items():
        signal = builder()
        for directory in targets:
            duration = write(os.path.join(directory, f"{name}.wav"), signal)
        print(f"{name}.wav  {duration:.2f} s")


if __name__ == "__main__":
    main()
