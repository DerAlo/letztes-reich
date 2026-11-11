# Texturen fuer die realistischen VIP-Figuren aus MakeHuman-CC0-Assets vorbereiten (verkleinern, umfaerben)
# Aufruf: python prep_vip.py <tex_dir> <kind>   (kind: riedhammer|weber|weber_uniform|falk|graumantel)
import sys, os
import numpy as np
from PIL import Image, ImageFilter

D = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/.user/user_default/mpfb/data"
OUT = sys.argv[1]
KIND = sys.argv[2] if len(sys.argv) > 2 else "riedhammer"
HERE = os.path.dirname(os.path.abspath(__file__))
CAMO = os.path.join(HERE, "..", "..", "assets", "characters", "textures", "camo_reich_urban.png")
os.makedirs(OUT, exist_ok=True)

def arr(p, mode="RGB"):
    return np.asarray(Image.open(p).convert(mode)).astype(np.float32) / 255.0

def save(a, name, size, q=90):
    im = Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8))
    if im.size[0] != size:
        im = im.resize((size, size), Image.LANCZOS)
    p = os.path.join(OUT, name)
    if name.endswith(".jpg"):
        im.save(p, quality=q)
    else:
        im.save(p, optimize=True)

# Haut: mittelalter hellhaeutiger Mann, mit "old"-Haut gemischt (Falten, Altersflecken) je nach Figur
OLD = {"riedhammer": 0.55, "weber": 0.6, "weber_uniform": 0.6, "falk": 0.25, "graumantel": 0.15}[KIND]
skin = arr(D + "/skins/middleage_caucasian_male/middleage_lightskinned_male_diffuse.png")
old = arr(D + "/skins/old_caucasian_male/old_lightskinned_male_diffuse.png")
skin = skin * (1 - OLD) + old * OLD
save(skin, "skin.jpg", 2048)

def close_mask(m, grow=21, shrink=15, blur=1.5):
    im = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(grow)).filter(ImageFilter.MinFilter(shrink))
    return (np.asarray(im.filter(ImageFilter.GaussianBlur(blur))).astype(np.float32) / 255.0)[..., None]

def camo_tiled(size, reps):
    c = Image.open(CAMO).convert("RGB")
    t = c.resize((size // reps, size // reps), Image.LANCZOS)
    big = Image.new("RGB", (size, size))
    for i in range(reps):
        for j in range(reps):
            big.paste(t, (i * (size // reps), j * (size // reps)))
    return np.asarray(big).astype(np.float32) / 255.0

if KIND in ("riedhammer", "weber_uniform"):
    # Elegant-Anzug -> Feldgrau-Waffenrock; Hemd + Krawatte ebenfalls Feldgrau (geschlossener Rock mit Stehkragen)
    s = arr(D + "/clothes/male_elegantsuit01/male_elegantsuit01_diffuse.png")
    lum = s.mean(axis=2, keepdims=True)
    field = np.array([0.33, 0.36, 0.315], np.float32)
    fab = np.clip(lum / 0.22, 0.0, 1.6) * field
    w_shirt = np.clip((lum - 0.45) / 0.2, 0, 1)
    blue = ((s[..., 2] - s[..., 0]) > 0.06).astype(np.float32)
    w_v = np.clip(close_mask(np.maximum(blue, w_shirt[..., 0]), 25, 15, 2.0), 0, 1)
    # Ausschnitt: gleicher Stoff, leicht dunkler (Rockvorderteil im Schatten des Kragens)
    sel = (w_v[..., 0] < 0.05) & (arr(D + "/clothes/male_elegantsuit01/male_elegantsuit01_diffuse.png", "RGBA")[..., 3] > 0.5)
    kmed = float(np.median(np.clip(lum[..., 0][sel] / 0.22, 0.0, 1.6)))
    print("Stoff-Median", kmed)
    out = fab * (1 - w_v) + field * kmed * 0.95 * w_v
    save(out, "suit.jpg", 2048)
elif KIND == "weber":
    # Anzug mit Krawatte -> Anthrazit, Krawatte dunkelrot einfarbig, Hemd weiss
    sa = arr(D + "/clothes/toigo_male_suit_tie_and_jacket/Suit-tie-Jacket-diff.png", "RGBA"); s = sa[..., :3]
    lum = s.mean(axis=2, keepdims=True)
    sat = s.max(axis=2, keepdims=True) - s.min(axis=2, keepdims=True)
    w_tie = np.clip(close_mask((sat[..., 0] > 0.18).astype(np.float32), 15, 11, 1.5), 0, 1)
    w_shirt = np.clip((lum - 0.6) / 0.15, 0, 1) * (1 - w_tie)
    fab = np.clip(lum / max(1e-3, float(np.percentile(lum, 50))), 0.5, 1.5) * np.array([0.085, 0.088, 0.095])
    tie = np.clip(lum / 0.5, 0.6, 1.2) * np.array([0.22, 0.04, 0.05])
    shirt = np.array([0.82, 0.83, 0.84]) * np.clip(lum + 0.1, 0, 1)
    out = fab * (1 - w_shirt - w_tie) + shirt * w_shirt + tie * w_tie
    save(np.clip(out, 0, 1), "suit.jpg", 2048)
else:
    # Freizeitanzug 05 (Jacke, Ringelhemd, Jeans): Falk -> Reich-Stadttarnung, Graumantel -> grauer Mantel
    sa = arr(D + "/clothes/male_casualsuit05/male_casualsuit05_diffuse.png", "RGBA"); s = sa[..., :3]
    lum = s.mean(axis=2, keepdims=True)
    jeans = close_mask((s[..., 2] - s[..., 0] > 0.08).astype(np.float32), 9, 7, 1.0)
    shirt = close_mask(((s[..., 0] - s[..., 1]) > 0.12).astype(np.float32), 25, 17, 1.5)
    shade = np.clip(lum / max(1e-3, float(np.percentile(lum[sa[..., 3:4] > 0.5], 50))), 0.45, 1.5)
    if KIND == "falk":
        camo = camo_tiled(2048, 6)
        camo = camo * 0.48 + 0.03   # Stadt-Tarn gedaempft (Original sehr hell)
        top = camo * shade * 0.95
        trou = camo * shade * 0.9
        under = np.array([0.06, 0.065, 0.06]) * shade
    else:
        top = np.array([0.28, 0.29, 0.29]) * shade
        trou = np.array([0.13, 0.14, 0.13]) * shade
        under = np.array([0.08, 0.08, 0.08]) * shade
    out = top * (1 - jeans - shirt) + trou * jeans + under * shirt
    save(np.clip(out, 0, 1), "suit.jpg", 2048)

# Stiefel: schwarzes Glattleder
BOOTSRC = {"weber": "/clothes/toigo_ankle_boots_male/BootsAnkleM.png"}.get(KIND, "/clothes/culturalibre_hero_boots_2/blue.png")
ba = arr(D + BOOTSRC, "RGBA"); b = ba[..., :3]
bl = b.max(axis=2, keepdims=True)
inside = ba[..., 3] > 0.5
bl = bl / max(1e-3, float(np.percentile(bl[inside], 60)))
boot = np.clip(bl * 0.06, 0, 0.35) * np.array([1.0, 0.96, 0.92])
save(boot, "boots.jpg", 1024)

# Augen
e = arr(D + "/eyes/materials/lightblue_eye.png"); el = e.mean(axis=2, keepdims=True)
save(np.clip(el + (e - el) * 0.45, 0, 1) * 0.92, "eye.jpg", 512)

HAIR = {"weber": "short01", "weber_uniform": "short01"}.get(KIND, "short02")
HAIRCOL = {"riedhammer": (0.44, 0.43, 0.42), "weber": (0.52, 0.51, 0.5), "weber_uniform": (0.52, 0.51, 0.5),
           "falk": (0.16, 0.14, 0.12), "graumantel": (0.25, 0.2, 0.15)}[KIND]
# Brauen / Wimpern / Haar (RGBA), Haar dunkelbraun-grau
for src, name, size, col in [
    (D + "/eyebrows/eyebrow001/eyebrow001.png", "brow.png", 256, (0.24, 0.21, 0.18)),
    (D + "/eyelashes/eyelashes01/eyelashes01.png", "lash.png", 256, (0.05, 0.04, 0.035)),
    (D + "/hair/%s/%s_diffuse.png" % (HAIR, HAIR), "hair.png", 1024, HAIRCOL),
]:
    a = arr(src, "RGBA")
    l = a[..., :3].mean(axis=2, keepdims=True)
    l = l / max(1e-3, float(np.percentile(l[a[..., 3] > 0.5], 60))) if (a[..., 3] > 0.5).any() else l
    rgb = np.clip(l * np.array(col), 0, 1)
    save(np.concatenate([rgb, a[..., 3:4]], axis=2), name, size)
print("ok", os.listdir(OUT))
