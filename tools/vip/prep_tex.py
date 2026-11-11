# Texturen fuer Riedhammer aus MakeHuman-CC0-Assets vorbereiten (verkleinern, umfaerben)
import sys, os
import numpy as np
from PIL import Image, ImageFilter

D = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/.user/user_default/mpfb/data"
OUT = sys.argv[1]
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

# Haut: mittelalter hellhaeutiger Mann, leicht waermer + Bartschatten-frei
skin = arr(D + "/skins/middleage_caucasian_male/middleage_lightskinned_male_diffuse.png")
save(skin, "skin.jpg", 2048)

# Anzug -> Feldgrau (Stoff), Hemd bleibt hell, Krawatte dunkel
s = arr(D + "/clothes/male_elegantsuit01/male_elegantsuit01_diffuse.png")
lum = s.mean(axis=2, keepdims=True)
sat = s.max(axis=2, keepdims=True) - s.min(axis=2, keepdims=True)
field = np.array([0.33, 0.36, 0.315], np.float32)   # Feldgrau (sRGB)
# Stoffhelligkeit normalisieren: Original ~0.18-0.25 -> Faktor
fab = np.clip(lum / 0.22, 0.0, 1.6) * field
shirt = np.clip(lum * np.array([0.86, 0.86, 0.80]), 0, 1)
w_shirt = np.clip((lum - 0.45) / 0.2, 0, 1)
# Krawatte: blau mit weissen Streifen -> Blau-Maske schliessen (Streifen fuellen), dann einfarbig dunkel
blue = ((s[..., 2] - s[..., 0]) > 0.06).astype(np.uint8) * 255
m = Image.fromarray(blue).filter(ImageFilter.MaxFilter(21)).filter(ImageFilter.MinFilter(15))
w_tie = (np.asarray(m.filter(ImageFilter.GaussianBlur(1.5))).astype(np.float32) / 255.0)[..., None]
tie = np.clip(lum / 0.3, 0.6, 1.2) * np.array([0.085, 0.09, 0.085])
out = fab * (1 - w_shirt) + shirt * w_shirt
out = out * (1 - w_tie) + tie * w_tie
save(out, "suit.jpg", 2048)

# Stiefel: schwarzes Glattleder
ba = arr(D + "/clothes/culturalibre_hero_boots_2/blue.png", "RGBA"); b = ba[..., :3]
bl = b.max(axis=2, keepdims=True)
inside = ba[..., 3] > 0.5
bl = bl / max(1e-3, float(np.percentile(bl[inside], 60)))
boot = np.clip(bl * 0.06, 0, 0.35) * np.array([1.0, 0.96, 0.92])
save(boot, "boots.jpg", 1024)

# Augen
e = arr(D + "/eyes/materials/lightblue_eye.png"); el = e.mean(axis=2, keepdims=True)
save(np.clip(el + (e - el) * 0.45, 0, 1) * 0.92, "eye.jpg", 512)

# Brauen / Wimpern / Haar (RGBA), Haar dunkelbraun-grau
for src, name, size, col in [
    (D + "/eyebrows/eyebrow001/eyebrow001.png", "brow.png", 256, (0.24, 0.21, 0.18)),
    (D + "/eyelashes/eyelashes01/eyelashes01.png", "lash.png", 256, (0.05, 0.04, 0.035)),
    (D + "/hair/short02/short02_diffuse.png", "hair.png", 1024, (0.36, 0.34, 0.32)),
]:
    a = arr(src, "RGBA")
    l = a[..., :3].mean(axis=2, keepdims=True)
    l = l / max(1e-3, float(np.percentile(l[a[..., 3] > 0.5], 60))) if (a[..., 3] > 0.5).any() else l
    rgb = np.clip(l * np.array(col), 0, 1)
    save(np.concatenate([rgb, a[..., 3:4]], axis=2), name, size)
print("ok", os.listdir(OUT))
