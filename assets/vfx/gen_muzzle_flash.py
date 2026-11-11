"""Erzeugt die Muendungsfeuer-Texturen (selbst generiert, CC0).

Aufruf (Projektordner):  python assets/vfx/gen_muzzle_flash.py
Benoetigt numpy + scipy + Pillow.

muzzle_flash_front.png  512x512, 2x2 Varianten a 256 px
    Blick in/entlang der Laufachse: kleiner, weissglühender Kern, 4-7 unregelmaessige, gewundene
    Flammenzungen ("Bluetenblaetter") unterschiedlicher Laenge, feine radiale Gasstreifen, fBm-Aufbruch.
muzzle_flash_side.png   512x384, 4 Varianten a 128x384 nebeneinander
    Seitenansicht: Wurzel unten (Muendung), Flamme nach oben. Heller Muendungskern, zerrissene
    Zwischenflamme (Gasball), turbulente, verjuengte Zunge, seitliche Strahlen aus dem Feuerdaempfer.

Kanaele: RGB = Farbe nach "Temperatur" (weiss -> gelb -> orange -> dunkelrot), A = Intensitaet.
Gedacht fuer additive Darstellung (Ergebnis = RGB * A * Energie); der Shader erodiert mit dem Alter
die schwachen Bereiche zuerst (Kern bleibt am laengsten).
"""
import os
import numpy as np
from PIL import Image
from scipy import ndimage

OUT = os.path.dirname(os.path.abspath(__file__))
RNG = np.random.default_rng(4711)


def noise2(h, w, cells_y, cells_x):
    """Glattes Wertrauschen 0..1 (bikubisch hochskaliertes Zufallsgitter)."""
    g = RNG.random((cells_y + 3, cells_x + 3))
    z = ndimage.zoom(g, ((h + 3 * h / cells_y) / g.shape[0], (w + 3 * w / cells_x) / g.shape[1]), order=3)
    oy = int(h / cells_y)
    ox = int(w / cells_x)
    return np.clip(z[oy:oy + h, ox:ox + w], 0.0, 1.0)


def fbm(h, w, base, octaves=5, gain=0.55):
    acc = np.zeros((h, w))
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        c = base * (2 ** o)
        acc += amp * noise2(h, w, max(2, int(c)), max(2, int(c)))
        tot += amp
        amp *= gain
    return acc / tot


def periodic1d(n, freq_lo, freq_hi):
    """Periodisches 1D-Rauschen (fuer Winkel), Bandpass im Frequenzraum, normiert 0..1."""
    spec = np.zeros(n // 2 + 1, dtype=complex)
    k = np.arange(n // 2 + 1)
    band = (k >= freq_lo) & (k <= freq_hi)
    spec[band] = (RNG.normal(size=band.sum()) + 1j * RNG.normal(size=band.sum())) / np.sqrt(k[band] + 1.0)
    s = np.fft.irfft(spec, n)
    s -= s.min()
    return s / max(s.max(), 1e-6)


def heat(i):
    """Intensitaet -> Farbe (Schwarzkoerper-artig)."""
    stops = np.array([0.0, 0.18, 0.4, 0.62, 0.82, 1.0])
    cols = np.array([
        [0.60, 0.12, 0.02],
        [0.95, 0.36, 0.06],
        [1.00, 0.60, 0.18],
        [1.00, 0.76, 0.40],
        [1.00, 0.91, 0.68],
        [1.00, 0.99, 0.95],
    ])
    out = np.zeros(i.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(i, stops, cols[:, c])
    return out


def to_rgba(intensity):
    i = np.clip(intensity, 0.0, 1.0)
    rgb = heat(i)
    a = np.clip(i * 1.1, 0.0, 1.0) ** 1.6
    return np.dstack([rgb, a])


def front_cell(n=256):
    y, x = np.mgrid[0:n, 0:n]
    x = (x + 0.5) / n * 2.0 - 1.0
    y = (y + 0.5) / n * 2.0 - 1.0
    # leichte Domain-Warp -> keine perfekten Kreise
    wx = (fbm(n, n, 3, 4) - 0.5) * 0.18
    wy = (fbm(n, n, 3, 4) - 0.5) * 0.18
    xw = x + wx * np.sqrt(x * x + y * y)
    yw = y + wy * np.sqrt(x * x + y * y)
    r = np.sqrt(xw * xw + yw * yw)
    th = np.arctan2(yw, xw)
    # Kern
    core = np.exp(-(r / 0.06) ** 2) * 1.1 + np.exp(-(r / 0.15) ** 2) * 0.55
    # Flammenzungen
    petals = np.zeros_like(r)
    cnt = int(RNG.integers(3, 7))
    base = RNG.random() * np.pi * 2
    for k in range(cnt):
        a = base + k * 2 * np.pi / cnt + RNG.normal(0, 0.45)
        length = RNG.uniform(0.5, 0.95)
        aw0 = RNG.uniform(0.36, 0.7)
        amp = RNG.uniform(0.45, 1.0)
        wig_f = RNG.uniform(5.0, 11.0)
        wig_p = RNG.random() * 6.28
        wig = 0.3 * np.sin(r * wig_f + wig_p) * r
        d = np.angle(np.exp(1j * (th - a - wig)))
        aw = aw0 * np.clip(1.0 - 0.75 * r / length, 0.08, 1.0) + 0.02
        t = np.clip(r / length, 0.0, 1.0)
        prof = (1.0 - t) ** 1.5 * (0.55 + 0.6 * np.exp(-((t - 0.3) / 0.25) ** 2))
        petals += np.exp(-(d / aw) ** 2) * prof * amp
    # feine radiale Gasstreifen (periodisch im Winkel)
    nang = 2048
    s1 = periodic1d(nang, 30, 140)
    s2 = periodic1d(nang, 8, 40)
    idx = ((th + np.pi) / (2 * np.pi) * nang).astype(int) % nang
    streak = s1[idx] ** 3
    lobes = s2[idx]
    streaks = streak * np.exp(-r / 0.25) * 0.3 * (0.4 + lobes)
    halo = np.exp(-r / 0.22) * 0.4 * (0.4 + lobes)
    body = petals * (0.75 + 0.4 * s1[idx]) + streaks + halo
    # Aufbruch
    br = fbm(n, n, 5, 5)
    bil = 1.0 - np.abs(fbm(n, n, 9, 4) - 0.5) * 2.0   # "billow": wulstige Flammenstruktur
    body *= np.clip(0.1 + 1.1 * br + 0.6 * bil ** 2, 0.0, 1.5)
    inten = core + body
    inten *= np.clip((1.0 - r) / 0.2, 0.0, 1.0)  # Rand sauber auf 0
    inten = 1.0 - np.exp(-inten * 1.6)            # weiche Saettigung
    return to_rgba(inten)


def side_cell(w=128, h=384):
    yy, xx = np.mgrid[0:h, 0:w]
    u = (xx + 0.5) / w * 2.0 - 1.0          # quer, -1..1
    v = 1.0 - (yy + 0.5) / h                 # entlang Lauf, 0 = Muendung (unten)
    # Silhouette: wellige Mittellinie + Breitenprofil mit Gasball
    warp_lo = (fbm(h, w, 3, 3) - 0.5)
    warp_hi = (fbm(h, w, 8, 4) - 0.5)
    uc = u - 0.35 * warp_lo * v * 2.0 - 0.3 * warp_hi * v
    ball_c = RNG.uniform(0.22, 0.34)
    ball_w = RNG.uniform(0.10, 0.16)
    ball_a = RNG.uniform(0.35, 0.6)
    tip = RNG.uniform(0.78, 0.98)
    t = np.clip(v / tip, 0.0, 1.0)
    width = 0.16 + ball_a * np.exp(-((v - ball_c) / ball_w) ** 2) + 0.18 * np.exp(-((v - ball_c - 0.25) / 0.12) ** 2)
    width *= (1.0 - t) ** 0.55 + 0.02
    width *= 0.85 + 0.4 * warp_hi
    plume = np.exp(-(uc / np.maximum(width, 0.02)) ** 2 * 1.6)
    along = (1.0 - t) ** 1.2 * (0.6 + 0.5 * np.exp(-((v - ball_c) / 0.2) ** 2))
    plume *= along
    # laengsgestreckte Gasstreifen (Rauschen in u hochfrequent, in v niederfrequent)
    st = noise2(h, w, 6, 18)
    plume *= 0.45 + 0.9 * st
    # Aufbruch, vor allem aussen und zur Spitze
    br = fbm(h, w, 7, 5)
    bil = 1.0 - np.abs(fbm(h, w, 10, 4) - 0.5) * 2.0
    plume *= np.clip(0.05 + 1.2 * br + 0.6 * bil ** 2 - 0.45 * t, 0.0, 1.6)
    # heller Muendungskern + Mach-Scheibe
    core = np.exp(-(u / 0.14) ** 2) * np.exp(-(v / 0.06) ** 2) * 1.2
    mach = np.exp(-(uc / 0.22) ** 2) * np.exp(-((v - ball_c * 0.7) / 0.05) ** 2) * RNG.uniform(0.3, 0.7)
    # seitliche Strahlen aus dem Feuerdaempfer (schraeg nach vorn)
    jets = np.zeros_like(u)
    for sgn in (-1.0, 1.0):
        ang = np.radians(RNG.uniform(22, 38))
        dx, dy = np.sin(ang) * sgn, np.cos(ang)
        px, py = u * 0.33, v                 # u auf etwa gleiche Masse wie v bringen (128/384)
        along_j = px * dx + py * dy
        perp = px * dy - py * dx
        lj = RNG.uniform(0.12, 0.22)
        tj = np.clip(along_j / lj, 0.0, 1.0)
        jets += np.exp(-(perp / (0.018 + 0.03 * tj)) ** 2) * (1.0 - tj) ** 1.5 * (along_j > 0) * RNG.uniform(0.35, 0.7)
    jets *= 0.5 + 0.8 * st
    inten = plume + core + mach + jets
    inten *= np.clip((1.0 - np.abs(u)) / 0.15, 0.0, 1.0) * np.clip((1.0 - v) / 0.06, 0.0, 1.0)
    inten = 1.0 - np.exp(-inten * 1.7)
    return to_rgba(inten)


def save(arr, name):
    img = Image.fromarray((np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGBA")
    img.save(os.path.join(OUT, name))
    print("geschrieben:", name, img.size)


def main():
    front = np.zeros((512, 512, 4))
    for i in range(4):
        cy, cx = divmod(i, 2)
        front[cy * 256:(cy + 1) * 256, cx * 256:(cx + 1) * 256] = front_cell()
    save(front, "muzzle_flash_front.png")
    side = np.zeros((384, 512, 4))
    for i in range(4):
        side[:, i * 128:(i + 1) * 128] = side_cell()
    save(side, "muzzle_flash_side.png")


if __name__ == "__main__":
    main()
