#!/usr/bin/env python3
"""Bildirim seslerini uretir.

NEDEN URETIYORUZ, INDIRMIYORUZ: Apple'in sistem sesleri (Tri-tone, Chime,
...) telifli ve yalnizca Apple isletim sistemleri icinde kullanilmak uzere
lisansli. Uygulamaya gomulmeleri hem ihlal olur hem magaza incelemesinde
takilir. Internette dolasan "iOS notification sound" dosyalarinin buyuk
kismi bunlarin kopyasi.

Buradaki sesler sifirdan sentezleniyor: telif sahibi yok, lisans kisiti yok.
Bildirim sesleri zaten neredeyse her zaman sentezlenmis tonlardir.

BICIM: 44.1 kHz, 16-bit, mono WAV. Hem iOS (`UNNotificationSound`) hem
Android (raw kaynak) WAV kabul ediyor, yani tek dosya iki platforma yetiyor.
iOS 30 saniye siniri koyuyor; buradakiler 1,5 saniyenin altinda.

Kullanim:  python3 tool/generate_notification_sounds.py
"""

import math
import os
import struct
import wave

import numpy as np

RATE = 44100
PEAK = 0.72  # Kirpilmaya pay birakir; -2.8 dBFS civari.


def envelope(length, attack, decay, curve=4.0):
    """Hizli atak, ussel sonum.

    Dogrusal sonum yapay duyuluyor; gercek bir cisim titresirken enerjisini
    ussel kaybeder. `curve` ne kadar buyukse sonum o kadar kisa algilaniyor.
    """
    result = np.ones(length)
    attack_samples = max(1, int(attack * RATE))
    result[:attack_samples] = np.linspace(0.0, 1.0, attack_samples)
    decay_samples = length - attack_samples
    if decay_samples > 0:
        t = np.linspace(0.0, 1.0, decay_samples)
        result[attack_samples:] = np.exp(-curve * t) * (1.0 - t) ** 0.5
    return result


def partials(frequency, duration, ratios, gains, attack=0.004, curve=4.0):
    """Bir notayi ust seslerinin toplami olarak uretir.

    Tek bir sinus 'bilgisayar sesi' gibi duyuluyor. Cana ya da tahtaya
    vuruldugunda olusan ses, temel frekansin katlarinda OLMAYAN ust
    seslerden olusur; asagidaki oranlar bu yuzden tam sayi degil.
    """
    length = int(duration * RATE)
    t = np.linspace(0.0, duration, length, endpoint=False)
    signal = np.zeros(length)
    for ratio, gain in zip(ratios, gains):
        # Yuksek ust sesler daha cabuk soner: parlaklik once kaybolur.
        partial_curve = curve * (1.0 + 0.55 * math.log2(max(ratio, 1.0) + 1.0))
        signal += gain * np.sin(2 * np.pi * frequency * ratio * t) * envelope(
            length, attack, duration, partial_curve
        )
    return signal


def sequence(notes, total):
    """Notalari zaman ekseninde ust uste bindirir."""
    out = np.zeros(int(total * RATE))
    for offset, signal in notes:
        start = int(offset * RATE)
        end = min(len(out), start + len(signal))
        out[start:end] += signal[: end - start]
    return out


def normalise(signal):
    peak = float(np.max(np.abs(signal)))
    if peak == 0:
        return signal
    return signal / peak * PEAK


def write(path, signal):
    data = normalise(signal)
    # Son 5 ms'i sifira indir: ani kesilme 'tik' sesi uretir.
    fade = int(0.005 * RATE)
    if len(data) > fade:
        data[-fade:] *= np.linspace(1.0, 0.0, fade)
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, sample)) * 32767))
        for sample in data
    )
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(frames)
    return len(data) / RATE


# --- Sesler -----------------------------------------------------------------
# Araliklar bilerek uyumlu secildi: yukselen beste (C6 -> E6) ve tam bese
# (C6 -> G6) kulakta 'olumlu bildirim' olarak yerlesmis araliklardir.

def chime():
    """Iki notali yukselen can. Varsayilan."""
    bell = [1.0, 2.01, 3.03, 4.21], [1.0, 0.45, 0.22, 0.10]
    return sequence(
        [
            (0.00, partials(1046.50, 1.10, *bell, curve=3.2)),          # C6
            (0.13, partials(1567.98, 1.20, *bell, curve=3.0) * 0.85),   # G6
        ],
        1.40,
    )


def pluck():
    """Kisa, tahta tinili tek nota. Marimbanin karakteri 4. ust sestir."""
    return partials(
        880.00,  # A5
        0.70,
        [1.0, 3.98, 9.2],
        [1.0, 0.30, 0.08],
        attack=0.002,
        curve=7.0,
    )


def ripple():
    """Uc hizli yukselen nota. Dikkat ceker ama sert degil."""
    tone = [1.0, 2.0, 3.0], [1.0, 0.26, 0.09]
    return sequence(
        [
            (0.00, partials(783.99, 0.45, *tone, curve=6.0)),          # G5
            (0.075, partials(987.77, 0.45, *tone, curve=6.0) * 0.9),   # B5
            (0.150, partials(1318.51, 0.70, *tone, curve=4.5) * 0.8),  # E6
        ],
        0.95,
    )


def pulse():
    """Alcak, iki vurusluk. Toplanti ve gece icin dikkat cekmeyen secenek."""
    tone = [1.0, 2.0], [1.0, 0.18]
    return sequence(
        [
            (0.00, partials(329.63, 0.30, *tone, attack=0.006, curve=8.0)),
            (0.16, partials(329.63, 0.34, *tone, attack=0.006, curve=8.0) * 0.8),
        ],
        0.62,
    )


SOUNDS = {
    "elcim_chime": chime,
    "elcim_pluck": pluck,
    "elcim_ripple": ripple,
    "elcim_pulse": pulse,
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
            path = os.path.join(directory, f"{name}.wav")
            duration = write(path, signal)
        print(f"{name}.wav  {duration:.2f} s")
    print(f"\nUretildi: {', '.join(os.path.relpath(d, root) for d in targets)}")


if __name__ == "__main__":
    main()
