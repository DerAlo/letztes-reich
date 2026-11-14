"""Erzeugt die Blut-Texturen (selbst generiert, CC0).

Aufruf (Projektordner):  python assets/vfx/gen_blood.py
Benoetigt numpy + scipy + Pillow.

blood_drop.png          64x64   Partikel-Tropfen (weicher, runder Kern, A = Deckkraft)
blood_splat_0..3.png    512x512 gerichtete Spritzer fuer Waende/Boden hinter dem Ziel.
                        Einschlagzentrum unten Mitte, Flugrichtung = Texturoben (v klein):
                        unregelmaessiger Hauptfleck, gestreckte Satelliten-Tropfen mit Schweif
                        ("Ausrufezeichen"), duenne Schlieren, feiner Spruehnebel.
blood_drip_0..1.png     256x256 runde Tropfflecken (senkrecht gefallen, kleiner Kronenrand)
blood_pool.png          512x512 Lache unter Toten (weiche Metaball-Lappen, dunkler Kern)
blood_*_n.png           Normalmaps aus der Blutdicke (gewoelbter Rand -> Glanzkante)
blood_orm.png           4x4 ORM (AO 1, Rauheit ~0.12, Metall 0) - frisches Blut glaenzt

Farbe: arterielles Dunkelrot; dicke Stellen fast schwarzrot, duenne Ausfransungen etwas heller.
"""
import os
import numpy as np
from PIL import Image
from scipy import ndimage

OUT = os.path.dirname(os.path.abspath(__file__))
RNG = np.random.default_rng(1312)

THIN = np.array([150.0, 10.0, 8.0])    # duenner Film (sRGB)
THICK = np.array([62.0, 2.0, 2.0])     # dicke, geronnene Stellen


def noise2(h, w, cells):
    g = RNG.random((cells + 3, cells + 3))
    z = ndimage.zoom(g, ((h + 3 * h / cells) / g.shape[0], (w + 3 * w / cells) / g.shape[1]), order=3)
    o = int(h / cells)
    return np.clip(z[o:o + h, o:o + w], 0.0, 1.0)


def fbm(h, w, base, octaves=4, gain=0.5):
    acc = np.zeros((h, w))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        acc += noise2(h, w, base * 2 ** o) * amp
        tot += amp
        amp *= gain
    return acc / tot


def stamp_ellipse(field, cx, cy, rx, ry, ang, val=1.0):
    """Antialiasierte, gedrehte Ellipse (max-Blend) in field."""
    h, w = field.shape
    r = max(rx, ry) + 2
    x0, x1 = int(max(cx - r, 0)), int(min(cx + r + 1, w))
    y0, y1 = int(max(cy - r, 0)), int(min(cy + r + 1, h))
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float64)
    dx, dy = xx - cx, yy - cy
    c, s = np.cos(ang), np.sin(ang)
    u = (dx * c + dy * s) / max(rx, 0.3)
    v = (-dx * s + dy * c) / max(ry, 0.3)
    d = np.sqrt(u * u + v * v)
    a = np.clip((1.0 - d) * min(rx, ry) * 1.6 + 0.5, 0.0, 1.0) * val
    field[y0:y1, x0:x1] = np.maximum(field[y0:y1, x0:x1], a)


def blob(field, cx, cy, r, rough=0.35, lobes=9):
    """Unregelmaessiger Fleck (Radius moduliert ueber den Winkel)."""
    h, w = field.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float64)
    dx, dy = xx - cx, yy - cy
    ang = np.arctan2(dy, dx)
    rad = np.sqrt(dx * dx + dy * dy)
    mod = np.ones_like(ang)
    for k in range(2, lobes + 2):
        mod += RNG.uniform(-rough, rough) / k ** 0.7 * np.cos(k * ang + RNG.uniform(0, 6.28))
    rr = r * mod
    a = np.clip((rr - rad) * 0.8 + 0.5, 0.0, 1.0)
    np.maximum(field, a, out=field)


def colorize(alpha, thick, size):
    """RGBA aus Deckkraft + Dicke. Dicke -> dunkler, Rand -> etwas heller/transparenter."""
    t = np.clip(thick, 0.0, 1.0)[..., None]
    var = (fbm(size, size, 6) - 0.5)[..., None] * 0.25
    rgb = THIN * (1.0 - t) + THICK * t
    rgb = rgb * (1.0 + var)
    a = np.clip(alpha, 0.0, 1.0)
    # duenne Ausfransungen leicht durchscheinend, Kern deckend
    a = a * (0.72 + 0.28 * np.clip(thick * 2.0, 0.0, 1.0))
    img = np.dstack([np.clip(rgb, 0, 255), a * 255.0]).astype(np.uint8)
    return img


def normal_from(height, strength):
    gy, gx = np.gradient(ndimage.gaussian_filter(height, 1.2))
    nx, ny = -gx * strength, -gy * strength
    nz = np.ones_like(nx)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.dstack([nx / l, -ny / l, nz / l])      # OpenGL-Konvention (Godot): +Y = oben
    return ((n * 0.5 + 0.5) * 255.0).astype(np.uint8)


def save(name, arr):
    Image.fromarray(arr).save(os.path.join(OUT, name))
    print("geschrieben:", name)


def splatter(seed, size=512):
    global RNG
    RNG = np.random.default_rng(seed)
    f = np.zeros((size, size))
    cx, cy = size * 0.5 + RNG.uniform(-12, 12), size * 0.72
    # Hauptfleck + angehaengte Nebenflecken
    blob(f, cx, cy, RNG.uniform(22, 32), 0.5)
    for _ in range(RNG.integers(2, 5)):
        a = -np.pi / 2 + RNG.normal(0, 0.7)
        d = RNG.uniform(18, 50)
        blob(f, cx + np.cos(a) * d, cy + np.sin(a) * d, RNG.uniform(7, 16), 0.45)
    # Satelliten: gestreckt entlang der Flugrichtung (nach oben, Kegel)
    n_sat = int(RNG.integers(70, 120))
    for _ in range(n_sat):
        a = -np.pi / 2 + RNG.normal(0, 0.55)
        d = 40 + RNG.exponential(85)
        if d > size * 0.66:
            continue
        x, y = cx + np.cos(a) * d, cy + np.sin(a) * d
        r = max(0.8, RNG.uniform(2.0, 9.0) * np.exp(-d / 260.0))
        el = 1.0 + d / 70.0 * RNG.uniform(0.6, 1.4)
        stamp_ellipse(f, x, y, r * el, r, a)
        if r > 2.0 and RNG.random() < 0.55:
            # Schweif/Ausrufezeichen: kleiner Tropfen weiter aussen
            d2 = d + r * el * RNG.uniform(1.6, 2.8)
            stamp_ellipse(f, cx + np.cos(a) * d2, cy + np.sin(a) * d2, r * 0.6 * el * 0.6, r * 0.45, a)
    # Schlieren
    for _ in range(int(RNG.integers(4, 9))):
        a = -np.pi / 2 + RNG.normal(0, 0.4)
        length = RNG.uniform(60, 190)
        w = RNG.uniform(1.0, 3.0)
        steps = int(length / 2)
        for i in range(steps):
            t = i / steps
            d = 30 + t * length
            stamp_ellipse(f, cx + np.cos(a) * d, cy + np.sin(a) * d, w * 1.8 * (1 - t * 0.6), w * (1 - t * 0.7) + 0.4, a)
    # feiner Spruehnebel
    for _ in range(int(RNG.integers(250, 420))):
        a = -np.pi / 2 + RNG.normal(0, 0.8)
        d = 20 + RNG.exponential(120)
        r = RNG.uniform(0.6, 1.8)
        stamp_ellipse(f, cx + np.cos(a) * d, cy + np.sin(a) * d, r * 1.3, r, a, RNG.uniform(0.5, 1.0))
    # ausgefranste Kanten (Rauschen moduliert die Schwelle leicht)
    nz = fbm(size, size, 24)
    f = np.clip(f * (0.85 + 0.3 * nz), 0, 1)
    thick = ndimage.gaussian_filter(f, 6.0) * 1.4
    edge = np.clip(1.0 - np.abs(np.arange(size) - size / 2) / (size / 2), 0, 1)
    f *= np.clip(edge[None, :] * 6, 0, 1) * np.clip(edge[:, None] * 6, 0, 1)
    rgba = colorize(f, thick, size)
    nrm = normal_from(f * 0.6 + thick * 0.4, 6.0)
    return rgba, nrm


def drip(seed, size=256):
    global RNG
    RNG = np.random.default_rng(seed)
    f = np.zeros((size, size))
    for _ in range(int(RNG.integers(2, 5))):
        x, y = RNG.uniform(70, 186, 2)
        r = RNG.uniform(10, 26)
        blob(f, x, y, r, 0.12, 5)
        # Kronenrand: kleine Zacken + Spritzer
        for _ in range(int(RNG.integers(6, 14))):
            a = RNG.uniform(0, 6.28)
            d = r * RNG.uniform(1.05, 1.9)
            rr = RNG.uniform(0.8, 2.6)
            stamp_ellipse(f, x + np.cos(a) * d, y + np.sin(a) * d, rr * 1.6, rr, a)
    thick = ndimage.gaussian_filter(f, 4.0) * 1.5
    return colorize(f, thick, size), normal_from(f * 0.5 + thick * 0.5, 5.0)


def pool(seed, size=512):
    global RNG
    RNG = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    acc = np.zeros((size, size))
    c = size / 2
    flow = RNG.uniform(0, 6.28)
    for i in range(14):
        if i == 0:
            x, y, r = c, c, size * 0.13
            sx, sy = r, r
        else:
            a = flow + RNG.normal(0, 0.9) + (np.pi if RNG.random() < 0.3 else 0.0)
            d = RNG.uniform(0.06, 0.3) * size
            x, y = c + np.cos(a) * d, c + np.sin(a) * d
            sx, sy = RNG.uniform(0.05, 0.11) * size, RNG.uniform(0.03, 0.07) * size
        ca, sa = np.cos(flow), np.sin(flow)
        u = (xx - x) * ca + (yy - y) * sa
        v = -(xx - x) * sa + (yy - y) * ca
        acc += np.exp(-(u * u) / (2 * sx * sx) - (v * v) / (2 * sy * sy))
    acc *= 0.8 + 0.4 * fbm(size, size, 8)
    f = np.clip((acc - 0.5) * 22.0, 0, 1)
    # Raender mit kleinen Ausbuchtungen
    thick = np.clip((acc - 0.5) * 1.4, 0, 1)
    thick = ndimage.gaussian_filter(thick, 3)
    rgba = colorize(f, 0.35 + thick * 1.2, size)
    # Meniskus: Hoehe steigt am Rand steil an, innen flach -> Glanzkante
    h = ndimage.gaussian_filter(f, 4.0)
    return rgba, normal_from(h, 9.0)


def drop(size=64):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float64)
    c = (size - 1) / 2
    d = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (size / 2)
    a = np.clip((1.0 - d) * 3.5, 0, 1) ** 1.2
    rgb = np.full((size, size, 3), 255.0)          # Farbe kommt aus dem Shader
    return np.dstack([rgb, a * 255]).astype(np.uint8)


if __name__ == "__main__":
    save("blood_drop.png", drop())
    for i in range(4):
        rgba, nrm = splatter(100 + i * 17)
        save("blood_splat_%d.png" % i, rgba)
        save("blood_splat_%d_n.png" % i, nrm)
    for i in range(2):
        rgba, nrm = drip(300 + i * 11)
        save("blood_drip_%d.png" % i, rgba)
        save("blood_drip_%d_n.png" % i, nrm)
    rgba, nrm = pool(777)
    save("blood_pool.png", rgba)
    save("blood_pool_n.png", nrm)
    orm = np.zeros((4, 4, 3), np.uint8)
    orm[..., 0] = 255
    orm[..., 1] = 30
    orm[..., 2] = 0
    save("blood_orm.png", orm)
