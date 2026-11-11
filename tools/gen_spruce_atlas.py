"""Erzeugt den Fichtenzweig-Atlas (eigene prozedurale Arbeit, CC0) fuer die Nadelbaeume.
Links (u 0..0.5): Zweigspray mit Alpha, Spitze oben, Ansatz unten.  Rechts (u 0.5..1): Rinde
(Poly Haven pine_bark, CC0) als Kachel. Ausgabe: albedo (RGBA) und normal (RGB, OpenGL)."""
import math, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
BARK = sys.argv[2]
R = 2048          # Arbeitsaufloesung der Zweig-Kachel (wird auf 1024 verkleinert)
T = 1024
rnd = random.Random(1234)

alb = Image.new("RGBA", (R, R), (0, 0, 0, 0))
hgt = Image.new("L", (R, R), 0)
da = ImageDraw.Draw(alb)
dh = ImageDraw.Draw(hgt)

def env(t):
    """Halbe Breite des Sprays (in Kachelbreiten) entlang der Laenge t (0 Ansatz .. 1 Spitze)."""
    return 0.04 + 0.4 * math.sin(math.pi * min(t, 1.0) ** 0.75) ** 0.8

def needle_col(k):
    # Fichte: dunkles, leicht blaeuliches Gruen, Spitzen heller
    g = rnd.uniform(0.75, 1.2)
    base = (int(22 * g), int(40 * g), int(30 * g))
    tip = (int(48 * g), int(78 * g), int(55 * g))
    return base, tip

def draw_twig(p0, p1, w0, w1, needles=True, nlen=36.0, dens=5.0, ang=58.0):
    x0, y0 = p0
    x1, y1 = p1
    L = math.hypot(x1 - x0, y1 - y0)
    if L < 2:
        return
    dx, dy = (x1 - x0) / L, (y1 - y0) / L
    n = max(2, int(L / 6))
    pts = [(x0 + dx * L * i / n, y0 + dy * L * i / n) for i in range(n + 1)]
    if needles:
        steps = int(L / dens)
        for i in range(steps):
            f = (i + rnd.random()) / max(steps, 1)
            cx, cy = x0 + dx * L * f, y0 + dy * L * f
            for side in (-1, 1):
                for layer in range(2):
                    a = math.radians(ang + rnd.uniform(-14, 14)) * side
                    ca, sa = math.cos(a), math.sin(a)
                    ndx = dx * ca - dy * sa
                    ndy = dx * sa + dy * ca
                    ln = nlen * rnd.uniform(0.75, 1.15) * (0.6 + 0.4 * min(1.0, f * 3 + 0.3)) * (1.0 - 0.35 * layer)
                    ex, ey = cx + ndx * ln, cy + ndy * ln
                    base, tip = needle_col(0)
                    mx, my = cx + ndx * ln * 0.55, cy + ndy * ln * 0.55
                    da.line([(cx, cy), (mx, my)], fill=base + (255,), width=4)
                    da.line([(mx, my), (ex, ey)], fill=tip + (255,), width=3)
                    dh.line([(cx, cy), (ex, ey)], fill=150 + layer * 60, width=4)
    for i in range(n):
        w = w0 + (w1 - w0) * i / n
        da.line([pts[i], pts[i + 1]], fill=(46, 32, 22, 255), width=max(2, int(w)))
        dh.line([pts[i], pts[i + 1]], fill=200, width=max(2, int(w)))

# Hauptachse von unten (Ansatz) nach oben (Spitze), leicht geschwungen
cx = R * 0.5
main = []
N = 40
for i in range(N + 1):
    t = i / N
    x = cx + math.sin(t * 2.6 + 0.4) * R * 0.018
    y = R * (0.995 - 0.975 * t)
    main.append((x, y))
# Seitenzweige (abwechselnd), mit Zweigen 2. Ordnung
side_sign = 1
t = 0.07
twigs = []
while t < 0.96:
    i = int(t * N)
    px, py = main[i]
    hw = env(t) * R
    ad = rnd.uniform(48, 62)
    ln = hw / math.sin(math.radians(ad)) * rnd.uniform(0.85, 1.05)
    ln = min(ln, (py - R * 0.03) / math.cos(math.radians(ad)))
    a = math.radians(ad) * side_sign
    ex = px + math.sin(a) * ln
    ey = py - math.cos(a) * ln
    twigs.append(((px, py), (ex, ey), t))
    side_sign = -side_sign
    t += rnd.uniform(0.03, 0.042)
for (p0, p1, tt) in twigs:
    L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
    dx, dy = (p1[0] - p0[0]) / L, (p1[1] - p0[1]) / L
    # 2. Ordnung
    s = 0.25
    sg = 1
    while s < 0.85 and L > 90:
        bx, by = p0[0] + dx * L * s, p0[1] + dy * L * s
        a = math.radians(rnd.uniform(40, 55)) * sg
        ca, sa = math.cos(a), math.sin(a)
        ndx, ndy = dx * ca - dy * sa, dx * sa + dy * ca
        sl = L * (1.0 - s) * rnd.uniform(0.35, 0.5)
        draw_twig((bx, by), (bx + ndx * sl, by + ndy * sl), 4, 2, nlen=40.0, dens=4.5)
        sg = -sg
        s += rnd.uniform(0.1, 0.15)
    draw_twig(p0, p1, 7, 3, nlen=46.0, dens=4.0)
for i in range(N):
    draw_twig(main[i], main[i + 1], 12 - 8 * i / N, 12 - 8 * (i + 1) / N, nlen=50.0, dens=4.0)

# Verkleinern mit vormultipliziertem Alpha
a = np.asarray(alb).astype(np.float32) / 255.0
rgb = a[..., :3] * a[..., 3:4]
pm = np.concatenate([rgb, a[..., 3:4]], axis=2)
pm_img = Image.fromarray((pm * 255).astype(np.uint8), "RGBA").resize((T, T), Image.LANCZOS)
pm = np.asarray(pm_img).astype(np.float32) / 255.0
al = pm[..., 3:4]
col = np.where(al > 1e-3, pm[..., :3] / np.maximum(al, 1e-3), 0.0)
# Farbe in transparente Bereiche ausbluten (keine dunklen Saeume in den Mipmaps)
mask = (al[..., 0] > 0.05).astype(np.float32)
c = col * mask[..., None]
m = mask.copy()
for _ in range(10):
    cimg = Image.fromarray(np.clip(c * 255, 0, 255).astype(np.uint8), "RGB").filter(ImageFilter.BoxBlur(3))
    mimg = Image.fromarray((m * 255).astype(np.uint8), "L").filter(ImageFilter.BoxBlur(3))
    cb = np.asarray(cimg).astype(np.float32) / 255.0
    mb = np.asarray(mimg).astype(np.float32) / 255.0
    fill = cb / np.maximum(mb[..., None], 1e-3)
    sel = (m < 0.5) & (mb > 0.02)
    col = np.where(sel[..., None], fill, col)
    c = np.where(sel[..., None], fill * 1.0, c)
    m = np.where(sel, 1.0, m)
col = np.where(m[..., None] > 0.5, col, np.array([0.1, 0.16, 0.11]))
# Alpha etwas schaerfen (Kanten sauber fuer Alpha-Scissor)
alpha = np.clip((al[..., 0] - 0.5) * 1.6 + 0.5, 0.0, 1.0)
leaf_rgba = np.concatenate([col, alpha[..., None]], axis=2)

# Hoehe -> Normalen (OpenGL, +Y oben)
h = np.asarray(hgt.filter(ImageFilter.GaussianBlur(2.2)).resize((T, T), Image.LANCZOS)).astype(np.float32) / 255.0
gx = np.zeros_like(h); gy = np.zeros_like(h)
gx[:, 1:-1] = (h[:, 2:] - h[:, :-2]) * 0.5
gy[1:-1, :] = (h[2:, :] - h[:-2, :]) * 0.5
strength = 6.0
nx = -gx * strength
ny = gy * strength      # Bild-y nach unten -> OpenGL-Normal y nach oben
nz = np.ones_like(h)
ln = np.sqrt(nx * nx + ny * ny + nz * nz)
leaf_n = np.stack([nx / ln, ny / ln, nz / ln], axis=2) * 0.5 + 0.5

# Rinde
bark = np.asarray(Image.open(BARK + "/diffuse.jpg").convert("RGB").resize((T, T), Image.LANCZOS)).astype(np.float32) / 255.0
bark_n = np.asarray(Image.open(BARK + "/normal.jpg").convert("RGB").resize((T, T), Image.LANCZOS)).astype(np.float32) / 255.0
bark_rgba = np.concatenate([bark, np.ones((T, T, 1), np.float32)], axis=2)

atlas = np.concatenate([leaf_rgba, bark_rgba], axis=1)
atlas_n = np.concatenate([leaf_n, bark_n], axis=1)
Image.fromarray(np.clip(atlas * 255, 0, 255).astype(np.uint8), "RGBA").save(OUT + "/spruce_atlas_albedo.png", optimize=True)
Image.fromarray(np.clip(atlas_n * 255, 0, 255).astype(np.uint8), "RGB").save(OUT + "/spruce_atlas_normal.png", optimize=True)
# Vorschau auf grauem Grund
prev = Image.new("RGB", (T, T), (128, 128, 128))
prev.paste(Image.fromarray(np.clip(leaf_rgba * 255, 0, 255).astype(np.uint8), "RGBA"), (0, 0), Image.fromarray((alpha * 255).astype(np.uint8), "L"))
prev.save(OUT + "/_preview_leaf.png")
print("ok", float(alpha.mean()))
