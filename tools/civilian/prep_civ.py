# Texturen fuer die Zivil-Reisenden (Nachtzug) aus MakeHuman-CC0-Assets vorbereiten (verkleinern, umfaerben).
# Aufruf: python prep_civ.py <tex_dir> <kind>
#   (kind: mantel|jacke|alt|frau|frau2 – Nachtzug; voss|kaempfer|praesidentin|abgeordneter – Curfew/Kanzleramt)
# Ausgabe: skin.jpg, eye.jpg, brow.png, lash.png, hair.png, suit.jpg, shoes.jpg
import sys, os
import numpy as np
from PIL import Image, ImageFilter

D = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/.user/user_default/mpfb/data"
OUT = sys.argv[1]
KIND = sys.argv[2]
os.makedirs(OUT, exist_ok=True)

def arr(p, mode="RGB"):
    return np.asarray(Image.open(p).convert(mode)).astype(np.float32) / 255.0

def save(a, name, size, q=88):
    im = Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8))
    if im.size[0] != size:
        im = im.resize((size, size), Image.LANCZOS)
    p = os.path.join(OUT, name)
    if name.endswith(".jpg"):
        im.save(p, quality=q)
    else:
        im.save(p, optimize=True)

def close_mask(m, grow=21, shrink=15, blur=1.5):
    im = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(grow)).filter(ImageFilter.MinFilter(shrink))
    return (np.asarray(im.filter(ImageFilter.GaussianBlur(blur))).astype(np.float32) / 255.0)[..., None]

def shade_of(rgb, alpha=None, blur=0.0, lo=0.45, hi=1.5):
    lum = rgb.mean(axis=2)
    if blur > 0:
        lum = np.asarray(Image.fromarray((lum * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur))).astype(np.float32) / 255.0
    sel = lum[alpha > 0.5] if alpha is not None and (alpha > 0.5).any() else lum
    return np.clip(lum / max(1e-3, float(np.percentile(sel, 50))), lo, hi)[..., None]

C = D + "/clothes/"
SK = D + "/skins/"
# ------------------------------------------------------------------ Steckbriefe
CFG = {
    "mantel": {"skin": [(SK + "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png", 1.0)],
               "eye": "brown", "hair": "short02", "haircol": (0.2, 0.14, 0.09), "browcol": (0.18, 0.13, 0.09),
               "shoes": C + "shoes01/shoes01_diffuse.png", "shoecol": (0.07, 0.05, 0.04)},
    "jacke": {"skin": [(SK + "young_caucasian_male/young_lightskinned_male_diffuse.png", 1.0)],
              "eye": "blue", "hair": "short03", "haircol": (0.5, 0.38, 0.22), "browcol": (0.33, 0.25, 0.16),
              "shoes": C + "toigo_ankle_boots_male/BootsAnkleM.png", "shoecol": (0.16, 0.1, 0.06)},
    "alt": {"skin": [(SK + "old_caucasian_male/old_lightskinned_male_diffuse.png", 0.8),
                     (SK + "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png", 0.2)],
            "eye": "grey", "hair": "short01", "haircol": (0.62, 0.61, 0.6), "browcol": (0.5, 0.49, 0.48),
            "shoes": C + "shoes01/shoes01_diffuse.png", "shoecol": (0.05, 0.04, 0.035)},
    "frau": {"skin": [(SK + "middleage_caucasian_female/middleage_lightskinned_female_diffuse.png", 1.0)],
             "eye": "green", "hair": "bob01", "haircol": (0.32, 0.16, 0.09), "browcol": (0.25, 0.14, 0.09),
             "shoes": C + "toigo_ankle_boots_female/BootsAnkle.png", "shoecol": (0.05, 0.04, 0.04)},
    "frau2": {"skin": [(SK + "young_african_female/young_darkskinned_female_diffuse.png", 1.0)],
              "eye": "brown", "hair": "ponytail01", "haircol": (0.05, 0.04, 0.035), "browcol": (0.05, 0.04, 0.035),
              "shoes": C + "toigo_ankle_boots_female/BootsAnkle.png", "shoecol": (0.1, 0.07, 0.05)},
    # Konrad Voss (Widerstand): Ende 50, ergrautes Haar, dunkler Zweireiher als Mantel
    "voss": {"skin": [(SK + "old_caucasian_male/old_lightskinned_male_diffuse.png", 0.45),
                      (SK + "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png", 0.55)],
             "eye": "grey", "hair": "short04", "haircol": (0.36, 0.34, 0.32), "browcol": (0.3, 0.28, 0.26),
             "shoes": C + "toigo_ankle_boots_male/BootsAnkleM.png", "shoecol": (0.08, 0.06, 0.045)},
    # Widerstandskaempfer: Arbeitshemd (gedecktes Oliv) + dunkle Hose, Stiefeletten
    "kaempfer": {"skin": [(SK + "young_caucasian_male/young_lightskinned_male_diffuse.png", 0.6),
                          (SK + "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png", 0.4)],
                 "eye": "brown", "hair": "short02", "haircol": (0.12, 0.09, 0.06), "browcol": (0.1, 0.08, 0.06),
                 "shoes": C + "toigo_ankle_boots_male/BootsAnkleM.png", "shoecol": (0.09, 0.065, 0.045)},
    # Praesidentin Hartmann: Anfang 60, graues Haar (Bob), bordeauxroter Hosenanzug, dunkle Bluse
    "praesidentin": {"skin": [(SK + "old_caucasian_female/old_lightskinned_female_diffuse.png", 0.55),
                              (SK + "middleage_caucasian_female/middleage_lightskinned_female_diffuse.png", 0.45)],
                     "eye": "bluegreen", "hair": "ponytail01", "haircol": (0.6, 0.59, 0.57), "browcol": (0.42, 0.4, 0.38),
                     "shoes": C + "toigo_ankle_boots_female/BootsAnkle.png", "shoecol": (0.04, 0.035, 0.035)},
    # Abgeordneter: dunkelblauer Anzug mit Krawatte
    "abgeordneter": {"skin": [(SK + "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png", 0.8),
                              (SK + "old_caucasian_male/old_lightskinned_male_diffuse.png", 0.2)],
                     "eye": "brownlight", "hair": "short01", "haircol": (0.24, 0.2, 0.16), "browcol": (0.2, 0.17, 0.13),
                     "shoes": C + "shoes01/shoes01_diffuse.png", "shoecol": (0.04, 0.035, 0.03)},
}[KIND]

# Haut
skin = None
for p, w in CFG["skin"]:
    a = arr(p)
    skin = a * w if skin is None else skin + a * w
save(skin, "skin.jpg", 1024)

# Kleidung
if KIND in ("mantel", "alt", "frau", "voss", "praesidentin", "abgeordneter"):
    # Anzug/Mantel (Toigo): Stoff umfaerben, Hemd hell lassen, Krawatte/Akzente dunkel einfaerben
    src = {"mantel": C + "toigo_male_double-breasted_suit/DB-suit.png",
           "alt": C + "toigo_male_suit_3/NewSuit3.png",
           "frau": C + "toigo_female_suit/MHSuitsFem-diff.png",
           "voss": C + "toigo_male_double-breasted_suit/DB-suit.png",
           "praesidentin": C + "toigo_female_double-breasted_suit/DB-suit-Fem.png",
           "abgeordneter": C + "toigo_male_suit_tie_and_jacket/Suit-tie-Jacket-diff.png"}[KIND]
    sa = arr(src, "RGBA"); s = sa[..., :3]
    lum = s.mean(axis=2, keepdims=True)
    sat = s.max(axis=2, keepdims=True) - s.min(axis=2, keepdims=True)
    if KIND == "praesidentin":
        # violettgrauer Stoff ist selbst gesaettigt: Akzente nur, wo Rot deutlich ueberwiegt (Halstuch)
        acc_m = ((s[..., 0] - s[..., 2]) > 0.15) & ((s[..., 0] - s[..., 1]) > 0.2)
    else:
        acc_m = sat[..., 0] > 0.2
    w_acc = np.clip(close_mask(acc_m.astype(np.float32), 15, 11, 1.5), 0, 1)
    w_shirt = np.clip((lum - 0.55) / 0.15, 0, 1) * (1 - w_acc)
    fabc = {"mantel": (0.16, 0.12, 0.085), "alt": (0.2, 0.19, 0.16), "frau": (0.2, 0.055, 0.07),
            "voss": (0.12, 0.12, 0.11), "praesidentin": (0.36, 0.065, 0.08), "abgeordneter": (0.06, 0.075, 0.12)}[KIND]
    accc = {"mantel": (0.12, 0.03, 0.03), "alt": (0.08, 0.1, 0.16), "frau": (0.6, 0.55, 0.45),
            "voss": (0.1, 0.1, 0.1), "praesidentin": (0.08, 0.07, 0.07), "abgeordneter": (0.3, 0.06, 0.06)}[KIND]
    fab = shade_of(s, sa[..., 3]) * np.array(fabc)
    acc = np.clip(lum / 0.5, 0.6, 1.2) * np.array(accc)
    shirtc = {"voss": (0.32, 0.31, 0.29), "praesidentin": (0.09, 0.085, 0.09)}.get(KIND, (0.78, 0.78, 0.76))
    shirt = np.array(shirtc) * np.clip(lum + 0.1, 0, 1)
    out = fab * (1 - w_shirt - w_acc) + shirt * w_shirt + acc * w_acc
elif KIND == "kaempfer":
    # Freizeitanzug 01 (Hemd + Jeans): Hemd -> verwaschenes Oliv, Jeans -> dunkle Arbeitshose
    sa = arr(C + "male_casualsuit01/male_casualsuit01_diffuse.png", "RGBA"); s = sa[..., :3]
    sh = shade_of(s, sa[..., 3])
    hh, ww = s.shape[:2]
    xs = (np.arange(ww, dtype=np.float32) / ww)[None, :, None]
    ys = (np.arange(hh, dtype=np.float32) / hh)[:, None, None]
    # Jeans liegen im UV-Layout als mittlere Spalte (x ~0.18..0.46), Hemd links/rechts davon
    pants = np.clip((xs - 0.17) / 0.02, 0, 1) * np.clip((0.47 - xs) / 0.02, 0, 1) * np.ones_like(ys)
    out = np.array([0.2, 0.21, 0.15]) * sh * (1 - pants) + np.array([0.11, 0.1, 0.09]) * sh * pants
elif KIND == "jacke":
    # Freizeitanzug 05 (Jacke, Ringelhemd, Jeans): braune Jacke, dunkles Hemd, dunkle Hose
    sa = arr(C + "male_casualsuit05/male_casualsuit05_diffuse.png", "RGBA"); s = sa[..., :3]
    jeans = close_mask((s[..., 2] - s[..., 0] > 0.08).astype(np.float32), 9, 7, 1.0)
    shirt = close_mask(((s[..., 0] - s[..., 1]) > 0.12).astype(np.float32), 25, 17, 1.5)
    sh = shade_of(s, sa[..., 3])
    out = np.array([0.24, 0.16, 0.1]) * sh * (1 - jeans - shirt) + np.array([0.1, 0.11, 0.13]) * sh * jeans \
        + np.array([0.3, 0.29, 0.26]) * sh * shirt
else:
    # Bluse (gestreift) + Rock: Bluse -> dunkelgruener Pullover (Streifen weichgezeichnet), Rock dunkelgrau
    sa = arr(C + "female_elegantsuit01/female_elegantsuit01_diffuse.png", "RGBA"); s = sa[..., :3]
    red = close_mask(((s[..., 0] - s[..., 1]) > 0.06).astype(np.float32), 31, 21, 2.0)
    sh_soft = shade_of(s, sa[..., 3], blur=6.0)
    sh = shade_of(s, sa[..., 3])
    out = np.array([0.08, 0.17, 0.14]) * sh_soft * red + np.array([0.12, 0.12, 0.13]) * sh * (1 - red)
save(np.clip(out, 0, 1), "suit.jpg", 1024)

# Schuhe: dunkles Leder (Socken-Teile dunkel)
ba = arr(CFG["shoes"], "RGBA"); b = ba[..., :3]
bl = b.max(axis=2, keepdims=True)
inside = ba[..., 3] > 0.5
bl = bl / max(1e-3, float(np.percentile(bl[inside] if inside.any() else bl, 60)))
save(np.clip(bl * np.array(CFG["shoecol"]) * 1.4, 0, 0.5), "shoes.jpg", 512)

# Augen
e = arr(D + "/eyes/materials/%s_eye.png" % CFG["eye"]); el = e.mean(axis=2, keepdims=True)
save(np.clip(el + (e - el) * 0.55, 0, 1) * 0.92, "eye.jpg", 256)

hair_src = {"ponytail01": "ponytail01/ponytail01_diffuse.png"}.get(CFG["hair"], "%s/%s_diffuse.png" % (CFG["hair"], CFG["hair"]))
for src, name, size, col in [
    (D + "/eyebrows/eyebrow001/eyebrow001.png", "brow.png", 256, CFG["browcol"]),
    (D + "/eyelashes/eyelashes01/eyelashes01.png", "lash.png", 256, (0.05, 0.04, 0.035)),
    (D + "/hair/" + hair_src, "hair.png", 1024, CFG["haircol"]),
]:
    a = arr(src, "RGBA")
    l = a[..., :3].mean(axis=2, keepdims=True)
    l = l / max(1e-3, float(np.percentile(l[a[..., 3] > 0.5], 60))) if (a[..., 3] > 0.5).any() else l
    rgb = np.clip(l * np.array(col), 0, 1)
    save(np.concatenate([rgb, a[..., 3:4]], axis=2), name, size)
print("ok", KIND, os.listdir(OUT))
