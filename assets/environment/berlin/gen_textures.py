#!/usr/bin/env python3
"""Erfundenes Emblem der fiktiven 'Ordnungsfront' (gebrochener Ring + senkrechte Klinge) als Texturen.
Bewusst frei erfunden, ohne Bezug zu realen Symbolen. Selbst erzeugt, CC0.

Aufruf (im Projektordner):  python assets/environment/berlin/gen_textures.py
-> assets/environment/berlin/emblem.png        (1024x1024, transparent, Amber)
-> assets/environment/berlin/emblem_mask.png   (1024x1024, weiss auf transparent, fuer Einfaerbung/Emission)
-> assets/characters/faction/reich_armband.png (512x128, Armbinde Amber mit schwarzem Emblem)
-> assets/environment/berlin/eu_flag.png       (512x340, Europaflagge fuer die Siegesfeier)
"""
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
AMBER = (255, 168, 38, 255)
BLACK = (14, 14, 16, 255)


def emblem(size, color, ss=4):
    """Gebrochener Ring (eine schraege Luecke oben rechts) mit senkrechter Klinge."""
    S = size * ss
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = cy = S / 2
    r_out = S * 0.36
    r_in = S * 0.27
    # Ring als Polygon-Band mit Luecke von 20..62 Grad (mathematisch, 0 = rechts, gegen den Uhrzeigersinn)
    gap_a, gap_b = 18.0, 64.0
    pts_out, pts_in = [], []
    steps = 180
    span = 360.0 - (gap_b - gap_a)
    for i in range(steps + 1):
        a = math.radians(gap_b + span * i / steps)
        pts_out.append((cx + math.cos(a) * r_out, cy - math.sin(a) * r_out))
        pts_in.append((cx + math.cos(a) * r_in, cy - math.sin(a) * r_in))
    d.polygon(pts_out + pts_in[::-1], fill=color)
    # Bruchkanten schraeg anschneiden (Splitter)
    a = math.radians(gap_b)
    tip = (cx + math.cos(a + 0.12) * (r_out + r_in) / 2, cy - math.sin(a + 0.12) * (r_out + r_in) / 2)
    d.polygon([pts_out[0], tip, pts_in[0]], fill=(0, 0, 0, 0))
    # Klinge: lange schmale Raute, oben laenger als unten, mit Parierstange
    w = S * 0.055
    top = cy - S * 0.47
    bot = cy + S * 0.40
    mid = cy + S * 0.08
    d.polygon([(cx, top), (cx + w, mid - S * 0.12), (cx + w * 0.7, mid), (cx, bot), (cx - w * 0.7, mid), (cx - w, mid - S * 0.12)], fill=color)
    # Parierstange (kurz, waagerecht)
    d.rectangle([cx - S * 0.12, mid + S * 0.005, cx + S * 0.12, mid + S * 0.04], fill=color)
    # Hohlschliff (dunkle Mittellinie) nur bei farbigem Emblem
    return im.resize((size, size), Image.LANCZOS)


def star(d, cx, cy, r, color):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rr = r if i % 2 == 0 else r * 0.382
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=color)


def eu_flag(w=512, h=340, ss=4):
    W, H = w * ss, h * ss
    im = Image.new("RGB", (W, H), (0, 51, 153))
    d = ImageDraw.Draw(im)
    R = H / 3
    for i in range(12):
        a = -math.pi / 2 + i * math.tau / 12
        star(d, W / 2 + math.cos(a) * R, H / 2 + math.sin(a) * R, H / 18, (255, 204, 0))
    return im.resize((w, h), Image.LANCZOS)


def main():
    out_env = os.path.join(ROOT, "assets", "environment", "berlin")
    out_chr = os.path.join(ROOT, "assets", "characters", "faction")
    os.makedirs(out_env, exist_ok=True)
    os.makedirs(out_chr, exist_ok=True)
    emblem(1024, AMBER).save(os.path.join(out_env, "emblem.png"))
    emblem(1024, (255, 255, 255, 255)).save(os.path.join(out_env, "emblem_mask.png"))
    # Armbinde: Amber, schwarze Kanten, zwei schwarze Embleme (vorne/hinten)
    W, H = 512, 128
    band = Image.new("RGBA", (W, H), AMBER)
    d = ImageDraw.Draw(band)
    d.rectangle([0, 0, W, 9], fill=BLACK)
    d.rectangle([0, H - 10, W, H], fill=BLACK)
    em = emblem(104, BLACK)
    for u in (0.25, 0.75):
        band.alpha_composite(em, (int(W * u - 52), int(H / 2 - 52)))
    band.convert("RGB").save(os.path.join(out_chr, "reich_armband.png"))
    eu_flag().save(os.path.join(out_env, "eu_flag.png"))
    print("Texturen geschrieben")


if __name__ == "__main__":
    main()
