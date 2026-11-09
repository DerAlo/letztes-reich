#!/usr/bin/env python3
"""Synthetische Sounds fuer Story-System und Level 'berlin' (selbst erzeugt, CC0).

Aufruf (im Projektordner):  python assets/environment/berlin/gen_sfx.py
Schreibt assets/sfx/story_*.ogg und assets/sfx/berlin_*.ogg (Mono, 44.1 kHz, OGG Vorbis via ffmpeg).
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "assets", "sfx")
rng = np.random.default_rng(2030)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def bp(x, lo, hi, order=4):
    sos = butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


def lp(x, hi, order=4):
    return sosfilt(butter(order, hi, btype="low", fs=SR, output="sos"), x)


def hp(x, lo, order=4):
    return sosfilt(butter(order, lo, btype="high", fs=SR, output="sos"), x)


def env_ad(n, a, d):
    """Attack/Decay-Huellkurve (Sekunden)."""
    t = np.arange(n) / SR
    e = np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4))
    return e


def norm(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def save(name, x, peak=0.89, fade=0.01):
    x = norm(x, peak)
    nf = int(fade * SR)
    if nf > 0 and len(x) > 2 * nf:
        x[:nf] *= np.linspace(0, 1, nf)
        x[-nf:] *= np.linspace(1, 0, nf)
    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, "a.wav")
        wavfile.write(wav, SR, (x * 32767).astype(np.int16))
        dst = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
    print("geschrieben:", name)


def click(n=int(0.012 * SR)):
    c = rng.standard_normal(n) * env_ad(n, 0.0005, 0.002)
    return hp(c, 1500)


def radio_static(sec, lo=700, hi=4200):
    n = int(sec * SR)
    s = bp(rng.standard_normal(n), lo, hi)
    # Knistern
    crack = (rng.random(n) < 0.002) * rng.standard_normal(n) * 6.0
    return s + bp(crack, 1000, 6000)


def story_radio_on():
    st = radio_static(0.32) * env_ad(int(0.32 * SR), 0.01, 0.09)
    c = np.zeros_like(st)
    k = click()
    c[: len(k)] += k * 2.5
    # kurzer Quittungston
    t = t_axis(0.32)
    beep = np.sin(2 * np.pi * 1750 * t) * ((t > 0.02) & (t < 0.09)) * 0.25
    return c + st * 0.6 + beep


def story_radio_off():
    n = int(0.16 * SR)
    st = radio_static(0.16) * env_ad(n, 0.003, 0.05)
    k = click()
    st[: len(k)] += k * 2.0
    return st


def story_type():
    n = int(0.05 * SR)
    k = rng.standard_normal(n) * env_ad(n, 0.0004, 0.006)
    body = np.sin(2 * np.pi * 380 * t_axis(0.05)) * env_ad(n, 0.0005, 0.012) * 0.6
    return bp(k, 900, 7000) + body


def story_drone():
    """Dunkler Dauerton fuer Schwarzblende / Ende (8 s)."""
    t = t_axis(8.0)
    x = np.zeros_like(t)
    for f, a in [(43.0, 1.0), (43.6, 0.8), (86.5, 0.35), (129.0, 0.18), (64.8, 0.3)]:
        x += a * np.sin(2 * np.pi * f * t + rng.random() * 6.28)
    noise = lp(rng.standard_normal(len(t)), 220) * 0.6
    x = x + noise
    swell = np.minimum(t / 2.5, 1.0) * np.minimum((8.0 - t) / 2.0, 1.0)
    return x * swell


def berlin_crowd():
    """Menschenmenge (12 s, loopbar): viele formantgefilterte 'Stimmen' + Jubel-Wellen."""
    sec = 12.0
    n = int(sec * SR)
    t = t_axis(sec)
    x = np.zeros(n)
    for i in range(60):
        f0 = rng.uniform(300, 1300)
        v = bp(rng.standard_normal(n), f0, f0 * rng.uniform(1.4, 2.2), 2)
        rate = rng.uniform(2.0, 5.0)
        am = np.clip(np.sin(2 * np.pi * rate * t + rng.random() * 6.28) + rng.uniform(-0.3, 0.5), 0, None)
        x += v * am * rng.uniform(0.4, 1.0)
    # Jubel-Wellen (periodisch, damit es loopt)
    cheer = bp(rng.standard_normal(n), 900, 4500, 2)
    wave = 0.5 + 0.5 * np.sin(2 * np.pi * t / sec * 2 - 1.2)
    x = x * 0.7 + cheer * wave ** 3 * 1.6
    # Crossfade fuer nahtlosen Loop
    k = int(0.5 * SR)
    head = x[:k].copy()
    x[-k:] = x[-k:] * np.linspace(1, 0, k) + head * np.linspace(0, 1, k)
    return x[k // 2:]


def berlin_firework_launch():
    t = t_axis(1.3)
    f = 900 + 1700 * (t / 1.3) ** 1.4
    ph = 2 * np.pi * np.cumsum(f) / SR
    whistle = np.sin(ph) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * t))
    hiss = bp(rng.standard_normal(len(t)), 2500, 9000) * 0.5
    e = np.minimum(t / 0.05, 1.0) * np.clip((1.3 - t) / 0.2, 0, 1)
    return (whistle * 0.5 + hiss) * e


def berlin_firework_burst():
    sec = 2.8
    n = int(sec * SR)
    t = t_axis(sec)
    boom = lp(rng.standard_normal(n), 300) * env_ad(n, 0.002, 0.35) * 5.0
    boom += np.sin(2 * np.pi * 55 * t) * env_ad(n, 0.002, 0.25) * 0.8
    crackle = np.zeros(n)
    for _ in range(260):
        p = int(rng.uniform(0.25, 2.5) * SR)
        k = min(int(0.006 * SR), n - p)
        crackle[p:p + k] += rng.standard_normal(k) * env_ad(k, 0.0003, 0.0015) * rng.uniform(0.3, 1.0)
    crackle = hp(crackle, 1800) * 3.0 * np.clip((2.8 - t) / 1.0, 0, 1)
    return boom + crackle


def berlin_screen_buzz():
    """Elektrisches Brummen mit Knacksern (2 s, loopbar)."""
    sec = 2.0
    t = t_axis(sec)
    x = np.zeros_like(t)
    for h, a in [(1, 1.0), (2, 0.5), (3, 0.45), (5, 0.25), (7, 0.15)]:
        x += a * np.sign(np.sin(2 * np.pi * 50 * h * t)) * 0.3 + a * np.sin(2 * np.pi * 50 * h * t)
    x = lp(x, 2400)
    pops = (rng.random(len(t)) < 0.0012) * rng.standard_normal(len(t)) * 8.0
    x += hp(pops, 2000)
    return x


def berlin_glass():
    sec = 1.6
    n = int(sec * SR)
    t = t_axis(sec)
    x = hp(rng.standard_normal(n), 2500) * env_ad(n, 0.001, 0.18) * 1.5
    for _ in range(40):
        f = rng.uniform(2500, 7500)
        d = rng.uniform(0.0, 0.9)
        pings = np.sin(2 * np.pi * f * t) * np.exp(-np.maximum(t - d, 0) / rng.uniform(0.04, 0.2)) * (t >= d)
        x += pings * rng.uniform(0.05, 0.25)
    thump = lp(rng.standard_normal(n), 250) * env_ad(n, 0.001, 0.06) * 2.0
    return x + thump


def berlin_pa_feedback():
    """Lautsprecher-Rueckkopplung, dann abgerissen (1.8 s)."""
    t = t_axis(1.8)
    f = 2900 + 140 * np.sin(2 * np.pi * 0.7 * t)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR)
    e = np.minimum(t / 0.9, 1.0) ** 2 * (t < 1.6)
    hum = np.sin(2 * np.pi * 50 * t) * 0.3 + np.sin(2 * np.pi * 100 * t) * 0.15
    return tone * e * 0.7 + hum * (t < 1.6)


def berlin_speech():
    """Unverstaendliche, hallige Lautsprecherstimme (8 s, loopbar) - nur Klangteppich, keine Worte."""
    sec = 8.0
    n = int(sec * SR)
    t = t_axis(sec)
    # Silben: Impulse mit Grundton + Formanten
    x = np.zeros(n)
    pos = 0.0
    while pos < sec - 0.4:
        dur = rng.uniform(0.12, 0.3)
        a = int(pos * SR)
        b = min(int((pos + dur) * SR), n)
        tt = np.arange(b - a) / SR
        f0 = rng.uniform(105, 135)
        src = np.sign(np.sin(2 * np.pi * f0 * tt)) * 0.6 + rng.standard_normal(b - a) * 0.15
        f1 = rng.uniform(400, 850)
        f2 = rng.uniform(1100, 2200)
        syl = bp(src, f1 * 0.8, f1 * 1.2, 2) + 0.6 * bp(src, f2 * 0.85, f2 * 1.15, 2)
        syl *= np.sin(np.pi * tt / dur) ** 0.7
        x[a:b] += syl
        pos += dur + (rng.uniform(0.25, 0.6) if rng.random() < 0.18 else rng.uniform(0.02, 0.07))
    x = bp(x, 300, 3500)  # Megafon-Band
    # Hall: einfache Echos
    y = x.copy()
    for d, g in [(0.09, 0.45), (0.21, 0.32), (0.37, 0.22), (0.6, 0.14)]:
        k = int(d * SR)
        y[k:] += x[:-k] * g
    return y


def main():
    os.makedirs(OUT, exist_ok=True)
    save("story_radio_on", story_radio_on(), 0.7)
    save("story_radio_off", story_radio_off(), 0.55)
    save("story_type", story_type(), 0.5, 0.0)
    save("story_drone", story_drone(), 0.8, 0.2)
    save("berlin_crowd", berlin_crowd(), 0.8, 0.0)
    save("berlin_firework_launch", berlin_firework_launch(), 0.6)
    save("berlin_firework_burst", berlin_firework_burst(), 0.9)
    save("berlin_screen_buzz", berlin_screen_buzz(), 0.5, 0.0)
    save("berlin_glass", berlin_glass(), 0.85)
    save("berlin_pa_feedback", berlin_pa_feedback(), 0.6)
    save("berlin_speech", berlin_speech(), 0.75, 0.0)


if __name__ == "__main__":
    main()
