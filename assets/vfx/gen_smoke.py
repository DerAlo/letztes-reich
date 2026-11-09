"""Erzeugt die Rauch-Texturen (selbst generiert, CC0) - ersetzt gen_smoke.gd (Runde 2, 128 px).

Aufruf (Projektordner):  python assets/vfx/gen_smoke.py
Benoetigt numpy + Pillow.

smoke_flipbook.png  2048x2048, 8x8 Frames a 256 px
    Pro Frame eine Rauchwolke: gelappte Grobform (mehrere weiche Teilballen, deren Lage/Groesse
    langsam ueber die Frames driftet) x mehrskaliges, domain-gewarptes "billow"-fBm. Das Rauschen
    frisst vor allem die Raender an (zerfaserte Kanten statt Kreisscheibe), der Kern bleibt dicht.
    Benachbarte Frames sind Schnitte durch dasselbe 3D-Noise mit kleinem z-Versatz -> der Shader
    kann waehrend der Lebenszeit ueber Folge-Frames blenden (Rauch "quillt").
    Kanaele: R,G = Normale (x,y; Bildraum, y nach unten) aus der geglaetteten Dichte ("Kuppel"),
             B = geglaettete Dichte (Dicke, fuer Selbstschatten/Streuung), A = Dichte.
smoke_detail.png    256x256, kachelbar
    R,G = Verzerrungsvektor (Curl-artig, aus Noise-Gradient), B = feines Billow-Noise (Erosion),
    A = mittelfeines fBm. Wird im Shader animiert ueber die Partikel gelegt.
"""
import os
import time
import numpy as np
from PIL import Image

OUT = os.path.dirname(os.path.abspath(__file__))
CELL = 256
GRID = 8
RNG = np.random.default_rng(1337)
SHAPE_GAIN = 1.0
BIL_GAIN = 0.75
D_RANGE = 1.0

# ------------------------------------------------------------------ periodisches 3D-Gradient-Noise

def _grad_table(seed: int, n: int = 256) -> np.ndarray:
    r = np.random.default_rng(seed)
    v = r.normal(size=(n, 3))
    return v / np.linalg.norm(v, axis=1, keepdims=True)


class Perlin3:
    def __init__(self, seed: int):
        r = np.random.default_rng(seed)
        self.perm = np.concatenate([r.permutation(256)] * 2)
        self.g = _grad_table(seed + 1)

    def _h(self, xi, yi, zi):
        p = self.perm
        return p[p[p[xi & 255] + (yi & 255)] + (zi & 255)]

    def __call__(self, x, y, z, period=None):
        xf = np.floor(x).astype(np.int64)
        yf = np.floor(y).astype(np.int64)
        zf = np.floor(z).astype(np.int64)
        fx, fy, fz = x - xf, y - yf, z - zf
        u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
        v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
        w = fz * fz * fz * (fz * (fz * 6 - 15) + 10)
        out = 0.0
        acc = {}
        for dx in (0, 1):
            for dy in (0, 1):
                for dz in (0, 1):
                    xi, yi = xf + dx, yf + dy
                    if period is not None:
                        xi = xi % period
                        yi = yi % period
                    g = self.g[self._h(xi, yi, zf + dz)]
                    d = g[..., 0] * (fx - dx) + g[..., 1] * (fy - dy) + g[..., 2] * (fz - dz)
                    acc[(dx, dy, dz)] = d
        lerp = lambda a, b, t: a + (b - a) * t
        x00 = lerp(acc[(0, 0, 0)], acc[(1, 0, 0)], u)
        x10 = lerp(acc[(0, 1, 0)], acc[(1, 1, 0)], u)
        x01 = lerp(acc[(0, 0, 1)], acc[(1, 0, 1)], u)
        x11 = lerp(acc[(0, 1, 1)], acc[(1, 1, 1)], u)
        out = lerp(lerp(x00, x10, v), lerp(x01, x11, v), w)
        return out * 1.6  # ~[-1, 1]


def fbm(noise, x, y, z, octaves=5, lac=2.0, gain=0.5, period=None, billow=False):
    s, amp, norm = 0.0, 1.0, 0.0
    f = 1.0
    for o in range(octaves):
        p = None if period is None else int(period * f)
        n = noise(x * f, y * f, z * f + o * 17.3, p)
        if billow:
            n = 1.0 - 2.0 * np.abs(n)       # weiche Ballen (invertiert "ridged")
        s = s + n * amp
        norm += amp
        amp *= gain
        f *= lac
    return s / norm


def blur(a: np.ndarray, sigma: float) -> np.ndarray:
    rad = int(sigma * 3)
    k = np.exp(-0.5 * (np.arange(-rad, rad + 1) / sigma) ** 2)
    k /= k.sum()
    pad = np.pad(a, rad, mode="edge")
    t = np.apply_along_axis(lambda r: np.convolve(r, k, mode="valid"), 1, pad)
    return np.apply_along_axis(lambda c: np.convolve(c, k, mode="valid"), 0, t)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)

# ------------------------------------------------------------------ Flipbook

def gen_flipbook(frames: int = GRID * GRID, name: str = "smoke_flipbook.png"):
    t0 = time.time()
    n_detail = Perlin3(11)
    n_warp_x = Perlin3(77)
    n_warp_y = Perlin3(91)
    n_shape = Perlin3(5)
    n_lobe = Perlin3(23)
    img = np.zeros((CELL * GRID, CELL * GRID, 4), dtype=np.float32)
    ys, xs = np.mgrid[0:CELL, 0:CELL].astype(np.float32)
    u = (xs + 0.5) / CELL * 2.0 - 1.0
    v = (ys + 0.5) / CELL * 2.0 - 1.0
    # Teilballen: Basislage auf einem Ring + Kern; driften langsam mit z (n_lobe)
    K = 6
    base_ang = np.linspace(0, 2 * np.pi, K, endpoint=False) + RNG.uniform(0, 1, K)
    for f in range(frames):
        z = f * 0.11                       # z-Versatz pro Frame (Noise-Einheiten)
        # --- Grobform: weiche, stark verzerrte Huellkurve (keine runde Scheibe, kein Plateau)
        # Teilballen nur noch als leichte Unregelmaessigkeit der Huelle
        lob = np.zeros_like(u)
        for k in range(K):
            a = base_ang[k] + 0.9 * n_lobe(np.float32(k * 3.1), np.float32(0.0), np.float32(z * 1.1))
            d = 0.36 + 0.14 * n_lobe(np.float32(k * 3.1 + 40.0), np.float32(1.0), np.float32(z * 1.1))
            cx, cy = np.cos(a) * d, np.sin(a) * d * 0.85
            rr = 0.20 + 0.08 * (n_lobe(np.float32(k * 7.7), np.float32(2.0), np.float32(z * 1.1)) + 1.0)
            lob += np.exp(-((u - cx) ** 2 + (v - cy) ** 2) / (rr * rr) * 2.0)
        wx = fbm(n_warp_x, xs / 70.0, ys / 70.0, z, octaves=3) * 0.32
        wy = fbm(n_warp_y, xs / 70.0, ys / 70.0, z, octaves=3) * 0.32
        r = np.sqrt((u + wx) ** 2 + (v + wy) ** 2)
        env = np.exp(-(r / 0.5) ** 2) * 0.7 + np.clip(lob, 0, 1.2) * 0.3
        env *= 1.0 - smoothstep(0.55, 0.95, r)
        # --- Detail: stark domain-gewarptes fBm -> Schlieren/Faeden statt Watte
        dx = fbm(n_warp_x, xs / 34.0, ys / 34.0, z * 1.4 + 9.0, octaves=4) * 22.0
        dy = fbm(n_warp_y, xs / 34.0, ys / 34.0, z * 1.4 + 9.0, octaves=4) * 22.0
        n1 = fbm(n_detail, (xs + dx) / 46.0, (ys + dy) / 46.0, z * 1.6, octaves=6, gain=0.58)
        wisp = np.clip(n1 * 1.25 + 0.5, 0.0, 1.0)                  # 0..1, weich
        fil = np.clip(1.0 - np.abs(n1) * 3.2, 0.0, 1.0) ** 2        # duenne Faeden (Nulldurchgaenge)
        fine = np.clip(fbm(n_shape, (xs + dx * 0.5) / 11.0, (ys + dy * 0.5) / 11.0, z * 2.2 + 3.0, octaves=3) * 1.4 + 0.5, 0.0, 1.0)
        # innen: wolkige Dichte, aussen: nur noch Faeden/Schlieren
        core = smoothstep(0.15, 0.75, env)
        tex = (wisp ** 1.6) * (0.55 + 0.45 * core) + fil * 0.35 * (1.0 - core)
        d = env * tex * (0.75 + 0.5 * fine)
        d = 1.0 - np.exp(-d * 1.9)                                  # weiche Saettigung, kein Plateau
        # harte Garantie: Rand der Zelle ist leer (kein Bluten in Nachbar-Frames / Mipmaps)
        em = np.maximum(np.abs(u), np.abs(v))
        d *= 1.0 - smoothstep(0.86, 0.97, em)
        sm = blur(d, 7.0)
        gy, gx = np.gradient(blur(d, 4.0) * 0.4 + sm * 0.6)
        nx, ny = -gx * 16.0, -gy * 16.0
        nz = np.ones_like(nx)
        ln = np.sqrt(nx * nx + ny * ny + nz * nz)
        cx0 = (f % GRID) * CELL
        cy0 = (f // GRID) * CELL
        img[cy0:cy0 + CELL, cx0:cx0 + CELL, 0] = nx / ln * 0.5 + 0.5
        img[cy0:cy0 + CELL, cx0:cx0 + CELL, 1] = ny / ln * 0.5 + 0.5
        img[cy0:cy0 + CELL, cx0:cx0 + CELL, 2] = np.clip(sm * 1.15, 0, 1)
        img[cy0:cy0 + CELL, cx0:cx0 + CELL, 3] = d
    out = (np.clip(img, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, name))
    print("smoke_flipbook.png ok (%.1f s)" % (time.time() - t0))

# ------------------------------------------------------------------ Detail-Noise (kachelbar)

def gen_detail():
    S = 256
    P = 8                                   # Gitterperiode bei Grundfrequenz (S/P px pro Zelle)
    ys, xs = np.mgrid[0:S, 0:S].astype(np.float32)
    x = xs / S * P
    y = ys / S * P
    z = np.zeros_like(x)
    pot = fbm(Perlin3(3), x, y, z, octaves=3, period=P)
    gy, gx = np.gradient(pot)
    # Curl (rotiert): wirbelnde Verzerrung statt reinem Schieben
    cx, cy = gy, -gx
    m = max(np.abs(cx).max(), np.abs(cy).max())
    cx, cy = cx / m, cy / m
    bil = fbm(Perlin3(4), x * 2, y * 2, z, octaves=4, period=P * 2, billow=True) * 0.5 + 0.5
    mid = fbm(Perlin3(6), x, y, z + 5.0, octaves=4, period=P) * 0.5 + 0.5
    bil = (bil - bil.min()) / (bil.max() - bil.min())
    mid = (mid - mid.min()) / (mid.max() - mid.min())
    out = np.stack([cx * 0.5 + 0.5, cy * 0.5 + 0.5, bil, mid], axis=-1)
    Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, "smoke_detail.png"))
    print("smoke_detail.png ok")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "preview":
        gen_flipbook(16, sys.argv[2])
    else:
        gen_detail()
        gen_flipbook()
