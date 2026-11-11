# Texturen fuer die realistischen Gegner-Soldaten aus MakeHuman-CC0-Assets vorbereiten.
# Aufruf: python prep_soldier.py <tex_dir> <helmet_dir>
#   helmet_dir = entpackter Ordner clothes/mrgreaterthan_m1_helmet aus dem CC0-Paket hats02
# Ausgabe (tex_dir): skin_a/b/c.jpg, eye.jpg, brow.png, lash.png, hair.png, suit.jpg, suit_n.jpg,
#                    boots.jpg, helmet.jpg, helmet_n.jpg
# suit.jpg ist KEINE fertige Farbe, sondern eine Detailkarte fuer game/enemies/soldier_mh_cloth.gdshader:
#   R = Stoff-Helligkeit (0.5 = Mittelwert, inkl. AO), G = Hosen-Maske, B = frei (0)
# Das Tarnmuster/die Fraktionsfarbe wird erst zur Laufzeit aufgebracht (eine Textur fuer alle Fraktionen).
import sys, os
import numpy as np
from PIL import Image, ImageFilter

D = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/.user/user_default/mpfb/data"
OUT = sys.argv[1]
HELM = sys.argv[2]
os.makedirs(OUT, exist_ok=True)

def arr(p, mode="RGB"):
    return np.asarray(Image.open(p).convert(mode)).astype(np.float32) / 255.0

def save(a, name, size, q=90):
    im = Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8))
    if im.size[0] != size:
        im = im.resize((size, size), Image.LANCZOS)
    p = os.path.join(OUT, name)
    if name.endswith(".jpg"):
        im.save(p, quality=q, subsampling=0)
    else:
        im.save(p, optimize=True)

def blur(a, r):
    im = Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r))).astype(np.float32) / 255.0

# ---------------------------------------------------------------- Haut (drei Gesichter)
SK = D + "/skins/"
young = arr(SK + "young_caucasian_male/young_lightskinned_male_diffuse.png")
young2 = arr(SK + "young_caucasian_male2/young_lightskinned_male_diffuse2.png")
mid = arr(SK + "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png")
# leichter Bartschatten/Feldschmutz: Haut minimal entsaettigt und abgedunkelt (Soldaten im Einsatz)
def weathered(s, k):
    l = s.mean(axis=2, keepdims=True)
    return np.clip((l + (s - l) * (1.0 - 0.12 * k)) * (1.0 - 0.06 * k), 0, 1)
save(weathered(young, 1.0), "skin_a.jpg", 2048)
save(weathered(mid * 0.7 + young * 0.3, 1.0), "skin_b.jpg", 2048)
save(weathered(young2 * 0.85 + mid * 0.15, 1.2) * np.array([0.97, 0.95, 0.93]), "skin_c.jpg", 2048)

# ---------------------------------------------------------------- Uniform (Freizeitanzug 01 -> Feldhemd + Feldhose)
C1 = D + "/clothes/male_casualsuit01/male_casualsuit01_"
sa = arr(C1 + "diffuse.png", "RGBA")
s = sa[..., :3]
alpha = sa[..., 3]
ao = arr(C1 + "ao.png", "L") if os.path.isfile(C1 + "ao.png") else np.ones(alpha.shape, np.float32)
if ao.shape != alpha.shape:
    ao = np.asarray(Image.fromarray((ao * 255).astype(np.uint8)).resize(alpha.shape[::-1], Image.LANCZOS)).astype(np.float32) / 255.0
lum = s.mean(axis=2)
h, w = lum.shape
uu = (np.arange(w, dtype=np.float32) + 0.5) / w
vv = (np.arange(h, dtype=np.float32) + 0.5) / h
U, V = np.meshgrid(uu, vv)
# Hose = mittlere Spalte der UV-Karte (Jeans), Rest = Hemd; Schuhe (oben links) werden geometrisch entfernt
trou = ((U > 0.355) & (U < 0.715)).astype(np.float32)
inside = alpha > 0.5
# Hintergrund (Blau ausserhalb der Inseln) zaehlt nicht fuer die Normierung
bg = np.abs(s - s[4, w // 2]).sum(axis=2) < 0.03
valid = inside & ~bg
shade = np.ones_like(lum)
for m in (trou > 0.5, trou < 0.5):
    sel = valid & m
    med = float(np.median(lum[sel])) if sel.any() else 0.3
    shade[m] = lum[m] / max(med, 1e-3)
# Grosse Helligkeitsverlaeufe der Jeans (verwaschen) daempfen, Falten/Naehte behalten
low = blur(shade, 18)
shade = np.clip(shade / np.maximum(low, 0.2) * (0.75 + 0.25 * low), 0.35, 1.7)
shade = shade * (0.55 + 0.45 * ao)
out = np.stack([np.clip(shade * 0.5, 0, 1), blur(trou, 2), np.zeros_like(shade)], axis=2)
out[bg & ~inside] = (0.5, 0.0, 0.0)
save(out, "suit.jpg", 2048, 92)
save(arr(C1 + "normal.png"), "suit_n.jpg", 2048, 92)

# ---------------------------------------------------------------- Stiefel: schwarzes, abgetragenes Leder
ba = arr(D + "/clothes/culturalibre_hero_boots_2/blue.png", "RGBA")
b = ba[..., :3]
bl = b.max(axis=2, keepdims=True)
binside = ba[..., 3] > 0.5
bl = bl / max(1e-3, float(np.percentile(bl[binside], 60)))
boot = np.clip(bl * 0.07, 0, 0.35) * np.array([1.0, 0.96, 0.9])
save(boot, "boots.jpg", 1024)

# ---------------------------------------------------------------- Helm M1 (MrGreaterThan, CC0): Graustufen-Detail
hd = arr(os.path.join(HELM, "M1Helmet_diffuse.png"))
hl = hd.mean(axis=2, keepdims=True)
hin = hl[..., 0] > 0.02
hl = hl / max(1e-3, float(np.median(hl[hin]))) * 0.5
save(np.clip(np.concatenate([hl, hl, hl], axis=2), 0, 1), "helmet.jpg", 1024)
save(arr(os.path.join(HELM, "M1Helmet_normal.png")), "helmet_n.jpg", 1024, 92)

# ---------------------------------------------------------------- Augen, Brauen, Wimpern, Haar
e = arr(D + "/eyes/materials/brown_eye.png"); el = e.mean(axis=2, keepdims=True)
save(np.clip(el + (e - el) * 0.5, 0, 1) * 0.9, "eye.jpg", 512)
for src, name, size, col in [
    (D + "/eyebrows/eyebrow001/eyebrow001.png", "brow.png", 256, (0.2, 0.17, 0.14)),
    (D + "/eyelashes/eyelashes01/eyelashes01.png", "lash.png", 256, (0.05, 0.04, 0.035)),
    (D + "/hair/short02/short02_diffuse.png", "hair.png", 1024, (0.15, 0.125, 0.1)),
]:
    a = arr(src, "RGBA")
    l = a[..., :3].mean(axis=2, keepdims=True)
    l = l / max(1e-3, float(np.percentile(l[a[..., 3] > 0.5], 60))) if (a[..., 3] > 0.5).any() else l
    rgb = np.clip(l * np.array(col), 0, 1)
    save(np.concatenate([rgb, a[..., 3:4]], axis=2), name, size)
print("ok", sorted(os.listdir(OUT)))
