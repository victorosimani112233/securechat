#!/usr/bin/env python3
"""Bildirim seslerini uretir.

NEDEN URETIYORUZ, INDIRMIYORUZ: Apple'in sistem sesleri telifli ve yalnizca
Apple isletim sistemleri icinde kullanilmak uzere lisansli. Internette
dolasan "iOS notification sound" dosyalarinin buyuk kismi bunlarin kopyasi.

TASARIM — olculmus bir referanstan cikarildi

Ilk uc tur vurmali sentezle yapildi (marimba/can modelleri, uyumsuz ust
sesler, 8-18 ms atak, aninda ussel sonum) ve hepsi yapay, 'oyun sesi' gibi
bulundu. Begenilen bir referans olculunce sebep netlesti: aranan ses
vurmali DEGIL, SURDURULEN bir ses ve neredeyse SAF SINUS.

Referanstan cikan sayilar:

    atak      96 ms      (vurmali seslerde 8-18 ms idi)
    plato    188 ms      (vurmali seste hic yok)
    birakis  168 ms
    2. harmonik / temel = 0.004   -> pratikte saf sinus
    zarf dalgalanmasi ~4.4 Hz     -> cok hafif tremolo
    iki nota, tam dortlu aralik (930 -> 1242 Hz)
    enerjinin %82'si 500-2000 Hz araliginda

Buradaki motor bunu izliyor: yavas kabaran, tutan, yumusak birakan temiz
tonlar. 'Premium' hissin kaynagi zenginlik degil, SADELIK ve yumusak zarf.

BICIM: 44.1 kHz, 16-bit, mono WAV. Hem iOS (`UNNotificationSound`) hem
Android (raw kaynak) kabul ediyor.

Kullanim:  python3 tool/generate_notification_sounds.py
"""

import os
import struct
import wave

import numpy as np

RATE = 44100
# Referansin tepe degeri -7.9 dBFS. Bildirim sesleri sistem sesleriyle ayni
# seviyede durmali; sonuna kadar doldurmak bagirir.
PEAK = 0.40


def voice(frequency, attack, sustain, release, tremolo=4.4, depth=0.05,
          colour=0.006, detune=0.12):
    """Yavas kabaran, tutan, yumusak birakan temiz ton.

    `colour` 2. ve 4. harmonigin miktari. Referansta 0.004 civari, yani
    neredeyse hic. Sifir birakilmiyor: cok az ust ses, sesi 'olu' olmaktan
    cikariyor.

    `detune` ikinci bir sesin birkac sent uzaga konmasi. Iki ses arasindaki
    yavas vuru, tek bir osilatorun duz tinisini canlandiriyor — koro
    etkisinin en yalin hali.
    """
    length = int((attack + sustain + release) * RATE)
    t = np.linspace(0.0, length / RATE, length, endpoint=False)

    attack_samples = max(1, int(attack * RATE))
    sustain_samples = max(1, int(sustain * RATE))
    release_samples = max(1, length - attack_samples - sustain_samples)
    envelope = np.concatenate([
        # Yarim kosinus: dogrusal kabarma mekanik duyuluyor.
        0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, attack_samples)),
        np.ones(sustain_samples),
        # Birakisin sonu ussel: dogrusal kesilme kulaga ani geliyor.
        np.exp(-np.linspace(0.0, 3.6, release_samples)),
    ])[:length]

    # Cok hafif tremolo; varligi ancak yoklugunda fark edilir.
    envelope = envelope * (1.0 - depth + depth * np.cos(2 * np.pi * tremolo * t))

    signal = np.sin(2 * np.pi * frequency * t)
    signal += 0.55 * np.sin(2 * np.pi * (frequency + detune) * t)
    signal += colour * np.sin(2 * np.pi * frequency * 2 * t)
    signal += colour * 0.6 * np.sin(2 * np.pi * frequency * 4 * t)
    return signal * envelope


def tail(signal, amount=0.22, seconds=0.45, damping=3200.0):
    """Kisa, yumusak kuyruk. Sesin bosluga dogmadigini duyurur."""
    n = int(seconds * RATE)
    rng = np.random.default_rng(29)
    impulse = rng.standard_normal(n) * np.exp(-np.linspace(0.0, 6.5, n))
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


def layer(parts):
    total = max(int(offset * RATE) + len(signal) for offset, signal in parts)
    out = np.zeros(total)
    for offset, signal in parts:
        start = int(offset * RATE)
        out[start : start + len(signal)] += signal
    return out


def write(path, signal):
    peak = float(np.max(np.abs(signal)))
    data = signal / peak * PEAK if peak > 0 else signal
    fade = int(0.010 * RATE)
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
# Araliklar uyumlu: tam dortlu, tam besli, buyuk uclu. Ikinci nota birincinin
# platosunda basliyor; kopuk iki olay degil, tek bir hareket duyuluyor.

def rise():
    """Yukselen tam dortlu. Referansin dogrudan karsiligi."""
    return tail(layer([
        (0.00, voice(932.33, 0.090, 0.150, 0.170)),   # Bb5
        (0.19, voice(1244.51, 0.080, 0.150, 0.200)),  # Eb6
    ]))


def lift():
    """Yukselen tam besli. Biraz daha genis ve iyimser."""
    return tail(layer([
        (0.00, voice(783.99, 0.085, 0.140, 0.170)),   # G5
        (0.18, voice(1174.66, 0.075, 0.160, 0.210)),  # D6
    ]))


def settle():
    """Inen buyuk uclu. 'Tamamlandi' hissi; daha sakin."""
    return tail(layer([
        (0.00, voice(987.77, 0.080, 0.140, 0.160)),   # B5
        (0.18, voice(783.99, 0.080, 0.170, 0.230)),   # G5
    ]))


def arc():
    """Uc nota, yukselen buyuk akor. En belirgin secenek."""
    return tail(layer([
        (0.00, voice(698.46, 0.080, 0.120, 0.150)),   # F5
        (0.155, voice(880.00, 0.070, 0.120, 0.150)),  # A5
        (0.310, voice(1046.50, 0.075, 0.160, 0.220)), # C6
    ]), amount=0.24, seconds=0.50)


def halo():
    """Iki nota ust uste, ayni anda acilan. Yumusak ve havali."""
    return tail(layer([
        (0.00, voice(659.25, 0.130, 0.170, 0.240, depth=0.04)),  # E5
        (0.06, voice(987.77, 0.140, 0.150, 0.230, depth=0.04) * 0.62),
    ]), amount=0.30, seconds=0.55)


def warm():
    """Alcak yukselen tam dortlu. Tok isteyenler icin."""
    return tail(layer([
        (0.00, voice(440.00, 0.095, 0.160, 0.190)),   # A4
        (0.20, voice(587.33, 0.085, 0.170, 0.230)),   # D5
    ]), damping=2400.0)


def calm():
    """Alcak, tek uzun nota. Dikkat cekmeyen sade secenek."""
    return tail(voice(523.25, 0.120, 0.200, 0.280, depth=0.04),
                amount=0.26, seconds=0.50, damping=2600.0)


def bright():
    """Tiz ve kisa. Gurultulu ortamda duyulur."""
    return tail(layer([
        (0.00, voice(1174.66, 0.060, 0.100, 0.130)),  # D6
        (0.145, voice(1567.98, 0.055, 0.120, 0.170)), # G6
    ]), amount=0.20, seconds=0.40, damping=4200.0)


SOUNDS = {
    "elcim_rise": rise,
    "elcim_lift": lift,
    "elcim_settle": settle,
    "elcim_arc": arc,
    "elcim_halo": halo,
    "elcim_warm": warm,
    "elcim_calm": calm,
    "elcim_bright": bright,
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
