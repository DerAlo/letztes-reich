#!/usr/bin/env python3
"""Selbst erzeugte Fahrzeug-Texturen (CC0). Aufruf im Projektordner:
    python assets/vehicles/gen_textures.py
-> assets/vehicles/textures/vehicle_noise.png  (512x512, kachelbar; R = Tarnflecken, G = Schmutz/Flecken, B = feine Abplatzer)
-> assets/vehicles/textures/tac_numbers.png    (512x512, 2x2-Atlas, weisse Schablonen-Nummern auf transparent)
-> assets/vehicles/textures/stripe_amber.png   (64x64, Amber-Warnstreifen fuer die Ordnungsfront-Lackierung)
Kachelbares Rauschen ueber FFT-Tiefpass (automatisch periodisch), Ziffern aus Rechtecken (Schablonen-Stil).
"""
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "vehicles", "textures")


def pnoise(n, cutoff, seed, aniso=(1.0, 1.0)):
    """Periodisches Rauschen 0..1: weisses Rauschen, Gauss-Tiefpass im Frequenzraum."""
    rng = np.random.default_rng(seed)
    w = rng.standard_normal((n, n))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(n)[:, None] * n * aniso[1]
    kx = np.fft.fftfreq(n)[None, :] * n * aniso[0]
    k2 = kx * kx + ky * ky
    f *= np.exp(-k2 / (2.0 * cutoff * cutoff))
    r = np.real(np.fft.ifft2(f))
    # Rang-Normalisierung -> gleichverteilt (Schwellen in Shadern bleiben vorhersagbar)
    flat = r.ravel()
    order = flat.argsort()
    ranks = np.empty_like(order)
    ranks[order] = np.arange(flat.size)
    return (ranks / (flat.size - 1)).reshape(n, n)


def noise_tex():
    n = 512
    camo = pnoise(n, 5.0, 11) * 0.8 + pnoise(n, 14.0, 12) * 0.2
    grime = pnoise(n, 9.0, 21) * 0.6 + pnoise(n, 40.0, 22) * 0.4
    chips = pnoise(n, 70.0, 31) * 0.7 + pnoise(n, 160.0, 32) * 0.3

    def norm(a):
        a = a - a.min()
        return a / max(a.max(), 1e-6)

    img = np.stack([norm(camo), norm(grime), norm(chips)], axis=-1)
    Image.fromarray((img * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "vehicle_noise.png"))


# 7-Segment-Schablonenziffern: Segmente a,b,c,d,e,f,g
SEG = {
    "0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
    "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg",
}


def digit(d, x, y, w, h, t, col):
    gap = t * 0.6   # Schablonen-Stege
    segs = {
        "a": (x + gap, y, x + w - gap, y + t),
        "g": (x + gap, y + h / 2 - t / 2, x + w - gap, y + h / 2 + t / 2),
        "d": (x + gap, y + h - t, x + w - gap, y + h),
        "f": (x, y + gap, x + t, y + h / 2 - gap),
        "b": (x + w - t, y + gap, x + w, y + h / 2 - gap),
        "e": (x, y + h / 2 + gap, x + t, y + h - gap),
        "c": (x + w - t, y + h / 2 + gap, x + w, y + h - gap),
    }
    for s in SEG[d]:
        d_.rectangle(segs[s], fill=col)


def numbers_tex():
    global d_
    S = 512
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d_ = ImageDraw.Draw(im)
    nums = ["214", "327", "105", "432"]
    col = (235, 235, 228, 255)
    for i, num in enumerate(nums):
        cx = (i % 2) * 256
        cy = (i // 2) * 256
        w, h, t = 52, 110, 15
        x0 = cx + (256 - (3 * w + 2 * 18)) / 2
        y0 = cy + (256 - h) / 2
        for k, ch in enumerate(num):
            digit(ch, x0 + k * (w + 18), y0, w, h, t, col)
    # leicht abgenutzt: zufaellige Alpha-Loecher
    a = np.array(im)
    wear = pnoise(S, 90.0, 5)
    a[..., 3] = np.where(wear > 0.86, 0, a[..., 3])
    Image.fromarray(a, "RGBA").save(os.path.join(OUT, "tac_numbers.png"))


def stripe_tex():
    S = 64
    im = Image.new("RGBA", (S, S), (255, 168, 38, 255))
    a = np.array(im)
    wear = pnoise(S, 12.0, 9)
    a[..., 3] = np.where(wear > 0.9, 0, 255)
    Image.fromarray(a, "RGBA").save(os.path.join(OUT, "stripe_amber.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    noise_tex()
    numbers_tex()
    stripe_tex()
    print("ok", OUT)
