"""Militaer-Lackierung fuer die echten Hubschraubermodelle (Kopien der Original-Texturen).

Mi-8 (EU/Brandt):  mattes Oliv/Graugruen, Aeroflot-Streifen/-Schriftzug/-Emblem und "CCCP"-Kennung entfernt,
                   Schmutz, Rost-Sprenkel, Nieten und Russ bleiben als Helligkeitsdetail erhalten.
Mi-28N (Garde):    dunkles Grau/Anthrazit, Tarnflecken nur noch als leichte Helligkeitsvariation.
Rotor (Mi-8):      entsaettigt, dunkles Grau (Blattspitzen-Markierung bleibt als Helligkeitsband).

Aufruf: python tools/paint_heli_textures.py   (danach Godot einmal importieren lassen)
Die Laufzeit-Zuordnung (Material -> Textur, metallic/roughness) steht in game/vehicles/models/heli_real.gd.
"""
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MI8 = ROOT / "assets/models/vehicles/mi8/textures"
MI28 = ROOT / "assets/models/vehicles/mi28n/textures"

# Markierungen in texture1_baseColor.png (2048^2): (x0, y0, x1, y1)
MI8_TEXT_BOXES = [
    (40, 225, 104, 610),     # "AEROFLOT" links
    (38, 125, 104, 212),     # Aeroflot-Fluegelemblem links
    (505, 515, 570, 910),    # "AEROFLOT" rechts
    (510, 395, 570, 488),    # Aeroflot-Fluegelemblem rechts
    (1290, 30, 1390, 400),   # "CCCP-42333" Heckausleger
    (1036, 855, 1170, 1215), # "CCCP-42333" Heckausleger (andere Seite)
]
# Blauer Fensterstreifen (Spalten) – nur blaue Pixel darin werden umgefaerbt
MI8_STRIPE_BOXES = [(135, 0, 236, 760), (620, 370, 716, 1130)]


def _lum(a: np.ndarray) -> np.ndarray:
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def _remove_markings(a: np.ndarray) -> np.ndarray:
    """Schrift/Embleme per Inpainting aus der Umgebung uebermalen, blauen Streifen an den Rumpf angleichen."""
    img = a.astype(np.uint8).copy()
    h, w, _ = img.shape
    f = img.astype(np.float32)
    lum = _lum(f)
    # Blauer Streifen: Farbe raus, Helligkeit auf Rumpfniveau anheben (Bullaugen bleiben dunkel)
    blue = (f[..., 2] > f[..., 0] * 1.18) & (f[..., 2] > 60)
    for x0, y0, x1, y1 in MI8_STRIPE_BOXES:
        sub = np.zeros_like(blue)
        sub[y0:y1, x0:x1] = True
        m = blue & sub
        if not m.any():
            continue
        ring = sub & ~blue & (lum > 90)
        body = np.median(lum[ring]) if ring.any() else 150.0
        stripe = np.median(lum[m])
        g = lum[m] * (body / max(stripe, 1.0))
        # dunkle Bullaugen (Glas) nicht aufhellen
        dark = lum[m] < stripe * 0.55
        g = np.where(dark, lum[m], g)
        for c in range(3):
            ch = f[..., c]
            ch[m] = g
    # Schrift/Embleme: dunkle oder blaue Pixel in den Boxen -> Maske -> Inpainting
    lum = _lum(f)
    blur = cv2.medianBlur(np.clip(lum, 0, 255).astype(np.uint8), 31).astype(np.float32)
    mask = np.zeros((h, w), np.uint8)
    for x0, y0, x1, y1 in MI8_TEXT_BOXES:
        box = np.zeros((h, w), bool)
        box[y0:y1, x0:x1] = True
        ink = box & ((lum < blur - 18) | ((f[..., 2] > f[..., 0] * 1.12) & (f[..., 2] > 50)))
        mask[ink] = 255
    mask = cv2.dilate(mask, np.ones((5, 5), np.uint8), iterations=2)
    out = cv2.inpaint(np.clip(f, 0, 255).astype(np.uint8), mask, 9, cv2.INPAINT_TELEA)
    # Inpainting glaettet: etwas Rauschen der Umgebung wieder einstreuen, damit die Flaeche nicht "neu" wirkt
    rng = np.random.default_rng(7)
    noise = rng.normal(0.0, 6.0, (h, w, 1)).astype(np.float32)
    mf = (cv2.GaussianBlur(mask.astype(np.float32) / 255.0, (0, 0), 3.0))[..., None]
    out = np.clip(out.astype(np.float32) + noise * mf, 0, 255)
    return out


def _tint(a: np.ndarray, base_rgb, ref_lum: float, contrast: float, keep_chroma: float, strength: float = 1.0) -> np.ndarray:
    """Helligkeitsdetail behalten, Farbe auf base_rgb bringen. ref_lum = Helligkeit, die auf base_rgb abgebildet wird."""
    f = a.astype(np.float32)
    lum = _lum(f)
    rel = np.power(np.clip(lum / ref_lum, 0.0, 4.0), contrast)
    base = np.array(base_rgb, np.float32)[None, None, :]
    painted = base * rel[..., None]
    # Rest-Buntheit (Rost, Oel) leicht erhalten
    chroma = f - lum[..., None]
    painted += chroma * keep_chroma * (painted.mean(2, keepdims=True) / np.maximum(lum[..., None], 1.0))
    out = painted * strength + f * (1.0 - strength)
    return np.clip(out, 0, 255)


def _save(arr: np.ndarray, path: Path) -> None:
    Image.fromarray(arr.astype(np.uint8), "RGB").save(path, optimize=True)
    print("geschrieben:", path.relative_to(ROOT))


def main() -> None:
    olive = (86, 92, 68)          # mattes Oliv/Graugruen (sRGB, Rumpf-Mittelwert)
    t1 = np.asarray(Image.open(MI8 / "texture1_baseColor.png").convert("RGB")).astype(np.float32)
    t1 = _remove_markings(t1)
    ref1 = float(np.percentile(_lum(t1), 75))
    _save(_tint(t1, olive, ref1, 0.75, 0.35), MI8 / "texture1_baseColor_mil.png")

    t2 = np.asarray(Image.open(MI8 / "texture2_baseColor.png").convert("RGB")).astype(np.float32)
    ref2 = float(np.percentile(_lum(t2), 75))
    _save(_tint(t2, olive, ref2, 0.8, 0.3, 0.85), MI8 / "texture2_baseColor_mil.png")

    rt = np.asarray(Image.open(MI8 / "rotor_baseColor.jpeg").convert("RGB")).astype(np.float32)
    refr = float(np.percentile(_lum(rt), 75))
    _save(_tint(rt, (70, 72, 66), refr, 0.8, 0.15), MI8 / "rotor_baseColor_mil.png")

    b = np.asarray(Image.open(MI28 / "Body_baseColor.png").convert("RGB")).astype(np.float32)
    # Tarnflecken (grossflaechig) fast ganz einebnen, Paneel-/Nietendetail (kleinflaechig) behalten
    lum = np.maximum(_lum(b), 1.0)
    low = np.maximum(cv2.GaussianBlur(lum, (0, 0), 18.0), 1.0)
    detail = np.power(lum / low, 0.85)
    ref_low = float(np.percentile(low, 60))
    flat = np.power(low / ref_low, 0.12) * detail
    out = np.array((47, 50, 52), np.float32)[None, None, :] * flat[..., None]
    _save(np.clip(out, 0, 255), MI28 / "Body_baseColor_garde.png")


if __name__ == "__main__":
    main()
