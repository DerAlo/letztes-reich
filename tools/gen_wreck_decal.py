"""Brandfleck-Decal fuer ausgebrannte Fahrzeugwracks (LevelProps / WreckModel.scorch).

Quelle: Poly Haven "burned_ground_01" (CC0) unter assets/vehicles/wrecks/textures/burned_ground_01/.
Erzeugt assets/vehicles/wrecks/textures/scorch_decal.png (RGBA) und scorch_decal_normal.png:
ausgefranster, zur Mitte dunkler werdender Russfleck + verstreute Glaskruemel (Scheiben zerplatzt).
Aufruf: python tools/gen_wreck_decal.py
"""
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "vehicles", "wrecks", "textures")
SRC = os.path.join(ROOT, "burned_ground_01")
N = 512


def fractal(rng, n, octaves=5):
    out = np.zeros((n, n), np.float32)
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        s = 4 * 2 ** o
        g = rng.random((s, s)).astype(np.float32)
        img = Image.fromarray((g * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
        out += np.asarray(img, np.float32) / 255.0 * amp
        tot += amp
        amp *= 0.5
    return out / tot


def main():
    rng = np.random.default_rng(7)
    dif = np.asarray(Image.open(os.path.join(SRC, "diffuse.jpg")).convert("RGB").resize((N, N), Image.LANCZOS), np.float32) / 255.0
    nor = np.asarray(Image.open(os.path.join(SRC, "normal.jpg")).convert("RGB").resize((N, N), Image.LANCZOS), np.float32) / 255.0
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    u = (x + 0.5) / N * 2.0 - 1.0
    v = (y + 0.5) / N * 2.0 - 1.0
    r = np.sqrt(u * u + v * v)
    f = fractal(rng, N)
    f2 = fractal(rng, N, 6)
    edge = r + (f - 0.5) * 0.45
    alpha = np.clip((0.92 - edge) / 0.3, 0.0, 1.0) ** 1.4
    core = np.clip((0.6 - edge) / 0.4, 0.0, 1.0)
    # Farbe: Brandboden abgedunkelt, Mitte fast schwarz (Asche/Russ), aussen braeunlicher Rand
    col = dif * (0.75 - 0.45 * core[..., None])
    col = col * (0.85 + 0.3 * f2[..., None])
    soot = np.array([0.03, 0.028, 0.026], np.float32)
    col = col * (1.0 - 0.8 * core[..., None]) + soot * 0.8 * core[..., None]
    # graue Ascheflecken (verbrannte Reifen/Innenraum) im Kern
    f3 = fractal(rng, N, 6)
    ash = np.clip((f3 - 0.52) / 0.12, 0.0, 1.0) * core
    ash_col = np.array([0.36, 0.345, 0.32], np.float32) * (0.8 + 0.4 * f2[..., None])
    col = col * (1.0 - ash[..., None]) + ash_col * ash[..., None]
    alpha = np.clip(alpha * (0.85 + 0.25 * f2) * 1.1, 0.0, 1.0)
    # Glaskruemel: kleine helle Punkte, gehaeuft im Ring unter den Fenstern
    count = 2600
    ang = rng.random(count) * np.pi * 2.0
    rad = np.clip(rng.normal(0.5, 0.17, count), 0.05, 0.95)
    px = ((np.cos(ang) * rad + 1.0) * 0.5 * N).astype(int)
    py = ((np.sin(ang) * rad + 1.0) * 0.5 * N).astype(int)
    for i in range(count):
        s = 1 if rng.random() < 0.8 else 2
        x0, y0 = px[i], py[i]
        if x0 < 1 or y0 < 1 or x0 >= N - 2 or y0 >= N - 2:
            continue
        g = 0.55 + rng.random() * 0.35
        tint = np.array([g * 0.92, g, g * 0.95], np.float32)
        col[y0:y0 + s, x0:x0 + s] = tint
        alpha[y0:y0 + s, x0:x0 + s] = np.maximum(alpha[y0:y0 + s, x0:x0 + s], 0.9)
        nor[y0:y0 + s, x0:x0 + s] = np.array([0.5, 0.5, 1.0], np.float32)
    rgba = np.dstack([np.clip(col, 0, 1), np.clip(alpha, 0, 1)])
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(ROOT, "scorch_decal.png"))
    nrgba = np.dstack([nor, np.clip(alpha, 0, 1)])
    Image.fromarray((nrgba * 255).astype(np.uint8), "RGBA").save(os.path.join(ROOT, "scorch_decal_normal.png"))
    print("ok", ROOT)


if __name__ == "__main__":
    main()
