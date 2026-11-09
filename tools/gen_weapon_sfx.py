"""Synthetische Waffen-/Pickup-Sounds (eigene Arbeit, CC0) -> assets/sfx/*.wav

  python tools/gen_weapon_sfx.py

rocket_launch: Panzerfaust-Abschuss (Knall + Zischen), rocket_fly: Raketen-Schub (loopbar, 2 s),
shell_drop: Hülse auf Boden (Klingeln), ammo_pickup: Magazin/Munition aufnehmen (Klacken).
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
rng = np.random.default_rng(7)


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
    wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
    print("wrote", name)


def rocket_launch():
    t = t_axis(1.6)
    n = rng.standard_normal(t.size)
    boom = lp(n, 900) * np.exp(-t * 9.0) * 1.6
    thump = np.sin(2 * np.pi * (55 + 40 * np.exp(-t * 20)) * t) * np.exp(-t * 7.0)
    hiss = bp(n, 1800, 7000) * (1 - np.exp(-t * 30)) * np.exp(-t * 2.2) * 0.6
    crack = hp(n, 2500) * np.exp(-t * 60.0) * 1.2
    save("rocket_launch", boom + thump + hiss + crack)


def rocket_fly():
    t = t_axis(2.0)
    n = rng.standard_normal(t.size)
    roar = bp(n, 300, 2600) * (0.8 + 0.2 * np.sin(2 * np.pi * 13 * t))
    hiss = bp(n, 3000, 9000) * 0.35
    x = roar + hiss
    # loopbar: kurze Überblendung Anfang/Ende
    f = int(SR * 0.08)
    x[:f] = x[:f] * np.linspace(0, 1, f) + x[-f:] * np.linspace(1, 0, f)
    x = x[:-f]
    save("rocket_fly", x, 0.7)


def shell_drop():
    t = t_axis(0.5)
    x = np.zeros(t.size)
    for k, (dt, a) in enumerate([(0.0, 1.0), (0.09, 0.5), (0.16, 0.28), (0.21, 0.15)]):
        tt = np.clip(t - dt, 0, None)
        on = (t >= dt).astype(float)
        ring = sum(np.sin(2 * np.pi * f * tt) * w for f, w in [(4200, 1.0), (6900, 0.6), (9800, 0.35), (3100, 0.4)])
        x += on * ring * np.exp(-tt * (28 + 6 * k)) * a
    x += hp(rng.standard_normal(t.size), 3000) * np.exp(-t * 80) * 0.3
    save("shell_drop", x, 0.6)


def ammo_pickup():
    t = t_axis(0.35)
    x = np.zeros(t.size)
    for dt, a, f in [(0.0, 1.0, 1800), (0.11, 0.8, 2600)]:
        tt = np.clip(t - dt, 0, None)
        on = (t >= dt).astype(float)
        x += on * (bp(rng.standard_normal(t.size), f * 0.6, f * 2.2) * np.exp(-tt * 70)
                   + np.sin(2 * np.pi * f * 0.5 * tt) * np.exp(-tt * 45) * 0.5) * a
    save("ammo_pickup", x, 0.7)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    rocket_launch()
    rocket_fly()
    shell_drop()
    ammo_pickup()
