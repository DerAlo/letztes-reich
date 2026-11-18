"""Wand-Decals fuer wall_grime.gd (Bunker/Kanzleramt), eigene Erzeugung (CC0).

Erzeugt nach assets/environment/decals/:
  rust_streak.png  (256x512) Rost-/Sickerfahnen: oben (Austritt an Decke/Anker) dicht, nach unten in
                   einzelne Laufspuren ausduennend; Farbe Rostbraun -> Ocker. Oben = Bildoberkante.
  damp_stain.png   (512x512) Feuchtefleck mit unregelmaessigen Trocknungsraendern, nach unten auslaufend.
  floor_grime.png  (512x128) Schmutzkante ueber dem Boden (unten dicht, nach oben ausfransend, Spritzer).
Aufruf: python tools/gen_wall_grime_decals.py
"""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "environment", "decals")


def fractal(rng, w, h, octaves=5, base=4):
    out = np.zeros((h, w), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        sx = max(2, int(base * 2 ** o * w / max(w, h)))
        sy = max(2, int(base * 2 ** o * h / max(w, h)))
        g = rng.random((sy, sx)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += np.asarray(img, np.float32) / 255.0 * amp
        tot += amp
        amp *= 0.5
    return out / tot


def save(name, rgb, a):
    a = np.clip(a, 0.0, 1.0)
    img = np.dstack([np.clip(rgb, 0, 1), a])
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))
    print("geschrieben:", name)


def rust_streak(rng):
    w, h = 256, 512
    x = np.linspace(-1, 1, w)[None, :]
    y = np.linspace(0, 1, h)[:, None]   # 0 = oben
    a = np.zeros((h, w), np.float32)
    # einzelne Laufspuren unterschiedlicher Laenge/Breite, leicht pendelnd
    for _ in range(26):
        cx = rng.normal(0.0, 0.32)
        length = rng.uniform(0.25, 1.0)
        width = rng.uniform(0.012, 0.05)
        strength = rng.uniform(0.35, 1.0)
        wob = rng.uniform(0.0, 0.03)
        ph = rng.uniform(0, 6.28)
        xc = cx + wob * np.sin(y * rng.uniform(6, 14) + ph)
        prof = np.exp(-((x - xc) / width) ** 2)
        fall = np.clip(1.0 - y / length, 0.0, 1.0) ** rng.uniform(0.6, 1.4)
        a = np.maximum(a, prof * fall * strength)
    # Austrittsbereich oben: breiter Fleck
    top = np.exp(-(x / 0.42) ** 2) * np.exp(-(y / 0.12) ** 2)
    a = np.maximum(a, top * 0.9)
    n = fractal(rng, w, h, 6, 4)
    a *= 0.55 + 0.75 * n
    a *= np.clip((1.0 - np.abs(x)) * 4.0, 0, 1)        # Raender sauber auslaufen
    a *= np.clip((1.0 - y) * 12.0, 0, 1)
    a = np.clip(a * 1.1, 0, 1)
    # Farbe: oben dunkles Rostbraun, Laufspuren heller/ockerfarben
    dark = np.array([0.22, 0.14, 0.09])
    ochre = np.array([0.40, 0.28, 0.17])
    t = np.clip(y * 1.3 + (n - 0.5) * 0.4, 0, 1)[..., None]
    rgb = dark * (1 - t) + ochre * t
    rgb = rgb * (0.8 + 0.4 * n[..., None])
    save("rust_streak.png", rgb, a)


def damp_stain(rng):
    w = h = 512
    x = np.linspace(-1, 1, w)[None, :]
    y = np.linspace(-1, 1, h)[:, None]   # -1 = oben
    n1 = fractal(rng, w, h, 6, 3)
    n2 = fractal(rng, w, h, 5, 6)
    # nach unten gezogene, unregelmaessige Form
    r = np.sqrt((x / 0.75) ** 2 + ((y + 0.15) / np.where(y > -0.15, 1.05, 0.6)) ** 2)
    f = r + (n1 - 0.5) * 1.1 + (n2 - 0.5) * 0.25
    body = np.clip((0.85 - f) / 0.35, 0, 1)
    # Trocknungsraender (mehrere Isolinien)
    rings = np.zeros_like(f)
    for lv, s in [(0.8, 0.4), (0.6, 0.16), (0.42, 0.1)]:
        rings = np.maximum(rings, np.exp(-((f - lv) / 0.018) ** 2) * s)
    a = body * (0.25 + 0.35 * n2) + rings
    a *= np.clip((1.0 - np.maximum(np.abs(x), np.abs(y))) * 8.0, 0, 1)
    base = np.array([0.36, 0.33, 0.27])
    edge = np.array([0.42, 0.33, 0.2])
    t = np.clip(rings * 2.0, 0, 1)[..., None]
    rgb = base * (1 - t) + edge * t
    rgb = rgb * (0.85 + 0.3 * n2[..., None])
    save("damp_stain.png", rgb, a)


def floor_grime(rng):
    w, h = 512, 128
    x = np.linspace(0, 1, w)[None, :]
    y = np.linspace(0, 1, h)[:, None]    # 0 = oben, 1 = Boden
    n1 = fractal(rng, w, h, 6, 6)
    n2 = fractal(rng, w, h, 4, 16)
    edge = 0.45 + (n1 - 0.5) * 0.6       # obere Kante ausgefranst
    a = np.clip((y - edge) / 0.35, 0, 1) ** 1.3
    a = np.maximum(a, np.clip((y - 0.85) / 0.15, 0, 1))    # dichter Fussstreifen
    a = a * (0.55 + 0.5 * n2)
    a *= np.clip(np.minimum(x, 1 - x) * 14.0, 0, 1)
    rgb = np.array([0.17, 0.15, 0.12]) * (0.8 + 0.4 * n1[..., None])
    save("floor_grime.png", rgb, np.clip(a, 0, 1))


if __name__ == "__main__":
    rng = np.random.default_rng(2030)
    rust_streak(rng)
    damp_stain(rng)
    floor_grime(rng)
