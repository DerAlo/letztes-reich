#!/usr/bin/env python3
"""Synthetische Sounds fuer Level 'gunship' (Waechter, selbst erzeugt, CC0).

Aufruf (im Projektordner):  python assets/environment/gunship/gen_sfx.py
Schreibt assets/sfx/gunship_*.ogg (Mono, 44.1 kHz, OGG Vorbis via ffmpeg).
Schleifen (engine, gatling, warn) sind nahtlos (Kreuzblende Ende -> Anfang).
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
rng = np.random.default_rng(1130)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def bp(x, lo, hi, order=4):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lp(x, hi, order=4):
    return sosfilt(butter(order, hi, btype="low", fs=SR, output="sos"), x)


def hp(x, lo, order=4):
    return sosfilt(butter(order, lo, btype="high", fs=SR, output="sos"), x)


def env_ad(n, a, d):
    t = np.arange(n) / SR
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4))


def noise(n):
    return rng.standard_normal(n)


def norm(x, peak=0.89):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def seamless(x, xf=0.4):
    """Macht eine Schleife nahtlos: das Ende wird in den Anfang geblendet."""
    n = int(xf * SR)
    head = x[:n].copy()
    tail = x[-n:]
    w = np.linspace(0, 1, n)
    out = x[: len(x) - n].copy()
    out[:n] = tail * (1 - w) + head * w
    return out


def save(name, x, peak=0.89, fade=0.006, loop=False):
    x = norm(x, peak)
    nf = int(fade * SR)
    if not loop and nf > 0 and len(x) > 2 * nf:
        x[:nf] *= np.linspace(0, 1, nf)
        x[-nf:] *= np.linspace(1, 0, nf)
    with tempfile.TemporaryDirectory() as td:
        wav = os.path.join(td, "a.wav")
        wavfile.write(wav, SR, (x * 32767).astype(np.int16))
        dst = os.path.join(OUT, "gunship_" + name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
    print("ok", name)


def boom(sec, f0, decay, crack=0.0, rumble=1.0):
    """Abschuss/Detonation: Druckstoss + Rauschen + Nachhall."""
    n = int(sec * SR)
    t = t_axis(sec)
    thump = np.sin(2 * np.pi * f0 * t * (1 + 1.5 * np.exp(-t * 18))) * env_ad(n, 0.002, decay * 0.35)
    body = lp(noise(n), 900) * env_ad(n, 0.003, decay)
    low = lp(noise(n), 160) * env_ad(n, 0.01, decay * 1.6) * rumble
    x = thump * 1.4 + body + low * 1.6
    if crack > 0:
        x += hp(noise(n), 2500) * env_ad(n, 0.0005, 0.02) * crack
    return x


def engine():
    sec = 8.4
    t = t_axis(sec)
    n = len(t)
    x = np.zeros(n)
    # vier Propfans, Blattfolge ~ 98..104 Hz, leichte Schwebung
    for i, f in enumerate([98.0, 99.3, 101.1, 102.4]):
        ph = rng.uniform(0, 6.28)
        sig = np.zeros(n)
        for h in range(1, 7):
            sig += np.sin(2 * np.pi * f * h * t + ph * h) / (h ** 1.25)
        x += sig * (0.8 + 0.2 * np.sin(2 * np.pi * (0.13 + i * 0.05) * t))
    x = lp(x, 900) * 0.35
    rumble = lp(noise(n), 220) * 1.4
    air = bp(noise(n), 400, 3000) * 0.25
    whine = np.sin(2 * np.pi * 1830 * t) * 0.02 + np.sin(2 * np.pi * 2410 * t) * 0.012
    return seamless(x + rumble + air + whine, 0.6)


def gatling():
    rate = 1.0 / 0.075
    sec = 3.0 + 0.4
    n = int(sec * SR)
    x = np.zeros(n)
    period = int(SR / rate)
    shot = boom(0.12, 120, 0.035, crack=0.8, rumble=0.4)
    for k in range(0, n - len(shot), period):
        j = k + int(rng.integers(-60, 60))
        j = max(0, j)
        x[j:j + len(shot)] += shot * rng.uniform(0.85, 1.0)
    mech = bp(noise(n), 300, 1800) * 0.18 * (1 + 0.5 * np.sin(2 * np.pi * rate * t_axis(sec)))
    x = x + mech + lp(noise(n), 120) * 0.5
    return seamless(x, 0.4)


def gun40():
    x = boom(0.9, 70, 0.22, crack=1.0, rumble=0.8)
    n = len(x)
    clank = bp(noise(n), 1500, 4500) * env_ad(n, 0.001, 0.03)
    clank2 = np.roll(bp(noise(n), 1200, 3800) * env_ad(n, 0.001, 0.025), int(0.18 * SR)) * 0.7
    return x + clank * 0.5 + clank2 * 0.4


def gun105():
    x = boom(2.4, 42, 0.6, crack=1.2, rumble=1.4)
    n = len(x)
    # Rumpf-Resonanz und Rasseln
    t = t_axis(2.4)
    res = np.sin(2 * np.pi * 63 * t) * env_ad(n, 0.01, 0.5) * 0.6
    rattle = bp(noise(n), 2000, 6000) * env_ad(n, 0.05, 0.35) * 0.18 * (np.sin(2 * np.pi * 31 * t) > 0)
    breech = np.roll(bp(noise(n), 900, 3500) * env_ad(n, 0.001, 0.05), int(0.9 * SR)) * 0.45
    return x + res + rattle + breech


def impact(big):
    sec = 2.6 if big else 1.4
    x = boom(sec, 34 if big else 55, 0.7 if big else 0.3, crack=0.0, rumble=1.8)
    return lp(x, 700 if big else 1100)


def reload_snd():
    n = int(1.2 * SR)
    x = np.zeros(n)
    for at, f, a in [(0.0, 1400, 1.0), (0.32, 900, 0.8), (0.55, 2200, 0.6), (0.9, 1100, 0.9)]:
        c = bp(noise(n), f * 0.6, f * 1.6) * env_ad(n, 0.001, 0.04) * a
        x += np.roll(c, int(at * SR))
    return x


def reload_done():
    n = int(0.35 * SR)
    x = bp(noise(n), 1500, 5000) * env_ad(n, 0.0005, 0.02)
    x += np.roll(bp(noise(n), 700, 2400) * env_ad(n, 0.0005, 0.04), int(0.08 * SR)) * 1.2
    return x


def warn():
    # Raketenwarner: schneller Zweiton, 4 Zyklen
    sec = 1.2
    t = t_axis(sec)
    f = np.where((t * 10) % 2 < 1, 1250.0, 950.0)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sign(np.sin(ph)) * 0.3 + np.sin(ph) * 0.7
    gate = ((t * 10) % 1 < 0.82).astype(float)
    return lp(x * gate, 5000)


def launch():
    sec = 2.8
    n = int(sec * SR)
    t = t_axis(sec)
    roar = bp(noise(n), 150, 2500) * env_ad(n, 0.25, 1.4)
    hiss = hp(noise(n), 3000) * env_ad(n, 0.05, 0.5) * 0.4
    return lp(roar + hiss, 2200) * (1 - 0.3 * t / sec)


def flare():
    n = int(1.6 * SR)
    x = np.zeros(n)
    for k in range(6):
        pop = hp(noise(n), 800) * env_ad(n, 0.0005, 0.03) + lp(noise(n), 400) * env_ad(n, 0.001, 0.06)
        x += np.roll(pop, int(k * 0.11 * SR)) * rng.uniform(0.7, 1.0)
    x += bp(noise(n), 1500, 6000) * env_ad(n, 0.05, 0.6) * 0.3
    return x


def hit():
    x = boom(2.0, 48, 0.5, crack=1.5, rumble=1.6)
    n = len(x)
    metal = bp(noise(n), 2500, 7000) * env_ad(n, 0.002, 0.4) * 0.5
    t = t_axis(2.0)
    groan = np.sin(2 * np.pi * (180 - 60 * t) * t) * env_ad(n, 0.1, 0.6) * 0.3
    return x + metal + groan


def switch():
    n = int(0.12 * SR)
    return bp(noise(n), 2000, 7000) * env_ad(n, 0.0003, 0.008) + np.roll(bp(noise(n), 1500, 5000) * env_ad(n, 0.0003, 0.01), int(0.03 * SR))


def zoom():
    sec = 0.35
    t = t_axis(sec)
    n = len(t)
    f = 600 + 900 * t / sec
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env_ad(n, 0.02, 0.15) * 0.2
    return s + bp(noise(n), 3000, 8000) * env_ad(n, 0.01, 0.1) * 0.15


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("engine", engine(), 0.7, loop=True)
    save("gatling", gatling(), 0.85, loop=True)
    save("warn", warn(), 0.6, loop=True)
    save("gun40", gun40())
    save("gun105", gun105(), 0.95)
    save("impact40", impact(False))
    save("impact105", impact(True), 0.95)
    save("reload", reload_snd(), 0.6)
    save("reload_done", reload_done(), 0.6)
    save("launch", launch(), 0.8)
    save("flare", flare(), 0.7)
    save("hit", hit(), 0.95)
    save("switch", switch(), 0.5)
    save("zoom", zoom(), 0.4)
