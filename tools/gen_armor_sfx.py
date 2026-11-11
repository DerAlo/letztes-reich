"""Synthetische Panzerungs-/Juggernaut-Sounds (eigene Arbeit, CC0) -> assets/sfx/*.wav

  python tools/gen_armor_sfx.py

armor_ping_1..3: Kugel prallt an Stahlplatte ab (heller, kurzer "Ping")
armor_break: Platte bricht/faellt ab (Knacken + Scheppern)
visor_crack: Panzerglas-Visier splittert
jugg_step_1..3: schwerer Schritt im Bombenanzug (Wumms + Plattenklappern)
jugg_spinup: Motor des MG-Laufbuendels laeuft an (~1.1 s)
jugg_collapse: Koloss bricht zusammen (Aufprall + Metallscheppern)
jugg_pack_burst: Tornister (Treibstoff/Munition) reisst auf - Zischen + Knall
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = np.random.default_rng(31)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), hi / (SR / 2)], btype="band")
    return lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = butter(order, f / (SR / 2), btype="low")
    return lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = butter(order, f / (SR / 2), btype="high")
    return lfilter(b, a, x)


def save(name, x, peak=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = min(len(x), int(SR * 0.01))
    x[-fade:] *= np.linspace(1, 0, fade)
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
    print("wrote", name)


def place(dst, src, at):
    i = int(at * SR)
    n = min(len(src), len(dst) - i)
    if n > 0:
        dst[i:i + n] += src[:n]


def metal_ring(sec, base, partials, decay, jitter=0.02):
    t = t_axis(sec)
    x = np.zeros_like(t)
    for k, (ratio, amp) in enumerate(partials):
        f = base * ratio * (1 + rng.uniform(-jitter, jitter))
        d = decay * (1.0 - 0.12 * k)
        x += amp * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / max(d, 0.01))
    return x


def armor_ping(i):
    sec = 0.55
    t = t_axis(sec)
    base = [1780.0, 2050.0, 1620.0][i]
    ring = metal_ring(sec, base, [(1.0, 1.0), (1.58, 0.7), (2.41, 0.55), (3.37, 0.35), (4.6, 0.2)], 0.16)
    click = hp(rng.standard_normal(len(t)), 3000) * np.exp(-t / 0.004) * 1.6
    thunk = lp(rng.standard_normal(len(t)), 900) * np.exp(-t / 0.012) * 0.8
    # Abpraller: kurzer Pfeifton, der nach unten gleitet
    f = 3400 - 1800 * np.clip(t / 0.18, 0, 1)
    whine = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.07) * 0.25 * (t > 0.015)
    save("armor_ping_%d" % (i + 1), ring * 0.8 + click + thunk + whine, 0.85)


def armor_break():
    sec = 1.6
    t = t_axis(sec)
    x = np.zeros_like(t)
    crack = bp(rng.standard_normal(len(t)), 600, 6000) * np.exp(-t / 0.03) * 1.5
    x += crack
    x += lp(rng.standard_normal(len(t)), 300) * np.exp(-t / 0.05) * 1.2
    # Platte faellt: drei Aufschlaege mit Klirren
    for k, (at, g) in enumerate([(0.32, 0.9), (0.55, 0.6), (0.68, 0.4), (0.8, 0.25)]):
        r = metal_ring(0.6, 520 + 90 * k, [(1.0, 1.0), (2.2, 0.6), (3.9, 0.4), (5.1, 0.25)], 0.09)
        r += bp(rng.standard_normal(len(r)), 1500, 7000) * np.exp(-t_axis(0.6) / 0.01) * 0.6
        place(x, r * g, at)
    save("armor_break", x, 0.9)


def visor_crack():
    sec = 0.7
    t = t_axis(sec)
    x = np.zeros_like(t)
    for k in range(9):
        at = 0.003 + rng.uniform(0, 0.12) * (k / 8.0)
        n = hp(rng.standard_normal(int(SR * 0.05)), 2500) * np.exp(-t_axis(0.05) / 0.004)
        place(x, n * rng.uniform(0.4, 1.0), at)
    tink = metal_ring(sec, 3900, [(1.0, 1.0), (1.71, 0.6), (2.9, 0.4)], 0.08)
    x += tink * 0.35
    x += lp(rng.standard_normal(len(t)), 600) * np.exp(-t / 0.015) * 0.7
    save("visor_crack", x, 0.85)


def jugg_step(i):
    sec = 0.8
    t = t_axis(sec)
    f0 = [52.0, 47.0, 57.0][i]
    thud = np.sin(2 * np.pi * f0 * t * (1 + 0.25 * np.exp(-t / 0.05))) * np.exp(-t / 0.13) * 1.4
    body = lp(rng.standard_normal(len(t)), 260) * np.exp(-t / 0.06) * 1.3
    grit = bp(rng.standard_normal(len(t)), 1200, 5000) * np.exp(-t / 0.02) * 0.35
    x = thud + body + grit
    # Plattenklappern kurz nach dem Aufsetzen
    for k, at in enumerate([0.045, 0.09 + 0.02 * i]):
        r = metal_ring(0.35, 760 + 140 * k + 60 * i, [(1.0, 1.0), (2.7, 0.5), (4.3, 0.3)], 0.05)
        place(x, r * (0.28 - 0.08 * k), at)
    save("jugg_step_%d" % (i + 1), x, 0.9)


def jugg_spinup():
    sec = 1.25
    t = t_axis(sec)
    prog = np.clip(t / 1.05, 0, 1) ** 0.7
    f = 90 + 520 * prog
    ph = 2 * np.pi * np.cumsum(f) / SR
    motor = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3.02 * ph) + 0.15 * np.sign(np.sin(6 * ph)) * 0.4)
    motor *= (0.25 + 0.75 * prog)
    x = motor * 0.5
    # Ratschen des Laufbuendels: Klicks immer schneller
    rate = 8 + 70 * prog
    clicks = np.zeros_like(t)
    acc = 0.0
    for j in range(len(t)):
        acc += rate[j] / SR
        if acc >= 1.0:
            acc -= 1.0
            n = min(300, len(t) - j)
            clicks[j:j + n] += hp(rng.standard_normal(n), 2000) * np.exp(-np.arange(n) / 40.0)
    x += clicks * 0.35
    x += bp(rng.standard_normal(len(t)), 300, 2500) * prog * 0.12
    env = np.minimum(1.0, t / 0.05)
    save("jugg_spinup", x * env, 0.8)


def jugg_collapse():
    sec = 2.6
    t = t_axis(sec)
    x = np.zeros_like(t)
    # Knie auf Boden, dann Oberkoerper
    for at, f0, g in [(0.0, 60.0, 0.8), (0.55, 44.0, 1.3)]:
        tt = t_axis(1.2)
        th = np.sin(2 * np.pi * f0 * tt * (1 + 0.3 * np.exp(-tt / 0.06))) * np.exp(-tt / 0.22)
        th += lp(rng.standard_normal(len(tt)), 220) * np.exp(-tt / 0.1) * 1.2
        place(x, th * g, at)
    for k in range(10):
        at = 0.05 + rng.uniform(0, 1.6)
        r = metal_ring(0.7, rng.uniform(380, 1400), [(1.0, 1.0), (2.3, 0.6), (3.7, 0.35), (5.2, 0.2)], 0.12)
        r += bp(rng.standard_normal(len(r)), 1200, 6000) * np.exp(-t_axis(0.7) / 0.01) * 0.5
        place(x, r * rng.uniform(0.15, 0.45), at)
    save("jugg_collapse", x, 0.9)


def jugg_pack_burst():
    sec = 1.8
    t = t_axis(sec)
    hiss = bp(rng.standard_normal(len(t)), 1800, 9000) * np.exp(-t / 0.5) * (t < 1.4) * 0.6
    pop = lp(rng.standard_normal(len(t)), 400) * np.exp(-t / 0.08) * 1.6
    crack = bp(rng.standard_normal(len(t)), 500, 4000) * np.exp(-t / 0.025) * 1.2
    x = hiss + pop + crack
    for k in range(6):
        c = hp(rng.standard_normal(int(SR * 0.03)), 1500) * np.exp(-t_axis(0.03) / 0.004)
        place(x, c * rng.uniform(0.3, 0.7), 0.1 + rng.uniform(0, 0.9))
    save("jugg_pack_burst", x, 0.9)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for i in range(3):
        armor_ping(i)
        jugg_step(i)
    armor_break()
    visor_crack()
    jugg_spinup()
    jugg_collapse()
    jugg_pack_burst()
