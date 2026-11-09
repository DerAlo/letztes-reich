#!/usr/bin/env python3
"""Selbst erzeugte Tarnmuster fuer die Soldaten-Uniformen (CC0). Aufruf im Projektordner:
    python assets/characters/textures/gen_camo.py
-> camo_ru_digital.png   (512x512, kachelbar) Pixel-Tarnung im Stil "Tsifra"/EMR: Oliv-Grau, Gruen, Braun, Schwarzgruen
-> camo_reich_urban.png  (512x512, kachelbar) fiktive Ordnungsfront-Stadttarnung: Stahlgrau, Anthrazit, Schwarz
Ein Musterzyklus deckt im Shader ~0.8 m ab (64 Pixelzellen -> ~1.25 cm je Zelle).
Kachelbares Rauschen ueber FFT-Tiefpass, auf ein 64er-Raster gerechnet und pixelgenau hochskaliert.
"""
import os

import numpy as np
from PIL import Image

OUT = os.path.dirname(os.path.abspath(__file__))


def pnoise(n, cutoff, seed):
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((n, n)))
    k = np.fft.fftfreq(n) * n
    k2 = k[:, None] ** 2 + k[None, :] ** 2
    f *= np.exp(-k2 / (2.0 * cutoff * cutoff))
    r = np.real(np.fft.ifft2(f)).ravel()
    order = r.argsort()
    ranks = np.empty_like(order)
    ranks[order] = np.arange(r.size)
    return (ranks / (r.size - 1)).reshape(n, n)


def digital(cells, layers, base, seed):
    """layers: [(farbe, cutoff, schwelle)] -> Pixelmuster, spaetere Lagen ueberdecken fruehere."""
    img = np.zeros((cells, cells, 3))
    img[:] = base
    for i, (col, cut, thr) in enumerate(layers):
        m = pnoise(cells, cut, seed + i * 7) * 0.8 + pnoise(cells, cut * 3.0, seed + i * 7 + 1) * 0.2
        img[m > thr] = col
    return img


def save(img, name, scale, seed):
    big = np.kron(img, np.ones((scale, scale, 1)))
    n = big.shape[0]
    var = (pnoise(n, 60.0, seed) - 0.5) * 0.06 + (pnoise(n, 6.0, seed + 1) - 0.5) * 0.08
    big = np.clip(big * (1.0 + var[:, :, None]), 0.0, 1.0)
    Image.fromarray((big * 255.0 + 0.5).astype(np.uint8), "RGB").save(os.path.join(OUT, name))
    print("geschrieben:", name)


def c(*v):
    return np.array(v) / 255.0


if __name__ == "__main__":
    ru = digital(64, [
        (c(86, 98, 62), 5.0, 0.52),     # Gruen
        (c(92, 74, 52), 6.0, 0.70),     # Braun
        (c(38, 42, 31), 7.0, 0.80),     # Schwarzgruen
    ], c(128, 128, 104), 101)
    save(ru, "camo_ru_digital.png", 8, 201)
    reich = digital(64, [
        (c(84, 87, 91), 4.5, 0.45),     # Mittelgrau
        (c(46, 48, 52), 6.0, 0.66),     # Anthrazit
        (c(20, 21, 23), 8.0, 0.82),     # Schwarz
    ], c(118, 120, 123), 301)
    save(reich, "camo_reich_urban.png", 8, 401)
