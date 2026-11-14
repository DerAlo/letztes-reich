# Texturen fuer die Nachtzug-Reisenden (skinned, mit Idle-Animationen; build_civ_nz.py) aus MakeHuman-CC0-Assets.
# Aufruf: python prep_civ_nz.py <tex_dir> <kind>
#   kind: tweed|pulli|hemd|jacke|anzug|blazer|bluse|dame|alt|kostuem|schlaf_m|schlaf_f
# Ausgabe: skin.jpg, eye.jpg, brow.png, lash.png, hair.png, suit.jpg, suit_n.png (Kleidungs-Normalmap), shoes.jpg,
#          shoes_n.png (falls vorhanden), hair_n.png (falls vorhanden)
# Stoffe werden umgefaerbt; Logos (MakeHuman-T-Shirts) verschwinden, weil die Faerbung nur die weichgezeichnete
# Helligkeit des Originals uebernimmt. Webmuster (Fischgrat, Strick, Melange) prozedural in UV-Pixeln.
import sys, os
import numpy as np
from PIL import Image, ImageFilter

D = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/.user/user_default/mpfb/data"
OUT = sys.argv[1]
KIND = sys.argv[2]
os.makedirs(OUT, exist_ok=True)
C = D + "/clothes/"
SK = D + "/skins/"
RNG = np.random.default_rng(abs(hash(KIND)) % (2 ** 31))

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

def blur(a, r):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(r))).astype(np.float32) / 255.0

def close_mask(m, grow=21, shrink=15, b=1.5):
    im = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(grow)).filter(ImageFilter.MinFilter(shrink))
    return (np.asarray(im.filter(ImageFilter.GaussianBlur(b))).astype(np.float32) / 255.0)[..., None]

def shade_of(rgb, alpha=None, r=0.0, lo=0.5, hi=1.4):
    lum = rgb.mean(axis=2)
    if r > 0:
        lum = blur(lum, r)
    sel = lum[alpha > 0.5] if alpha is not None and (alpha > 0.5).any() else lum
    return np.clip(lum / max(1e-3, float(np.percentile(sel, 50))), lo, hi)[..., None]

def grid(n):
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    return xs, ys

def noise(n, scale, amp):
    small = RNG.standard_normal((max(2, n // scale), max(2, n // scale))).astype(np.float32)
    im = Image.fromarray(((np.clip(small * 0.25 + 0.5, 0, 1)) * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
    return 1.0 + (np.asarray(im).astype(np.float32) / 255.0 - 0.5) * 2.0 * amp

def pattern(kind, n):
    """Helligkeits-Modulation (um 1.0) fuer das Webmuster."""
    xs, ys = grid(n)
    if kind == "herringbone":
        # Fischgrat: diagonale Koeper-Rippen, Richtung wechselt in Streifen von 10 px
        band = (np.floor(xs / 10.0) % 2) * 2 - 1
        rib = np.sin((xs * band + ys) * (2 * np.pi / 3.2))
        p = 1.0 + 0.11 * rib + 0.05 * (RNG.random((n, n)).astype(np.float32) - 0.5)
        return p * noise(n, 24, 0.06) * noise(n, 6, 0.04)
    if kind == "knit":
        # Strick: senkrechte Rippen (Maschenreihen) + feine Querstruktur + Melange
        rib = np.sin(xs * (2 * np.pi / 5.0))
        row = np.sin(ys * (2 * np.pi / 3.0) + np.sign(np.sin(xs * np.pi / 5.0)) * 0.9)
        p = 1.0 + 0.13 * rib + 0.05 * row
        return p * noise(n, 3, 0.07) * noise(n, 40, 0.05)
    if kind == "melange":
        return noise(n, 2, 0.09) * noise(n, 12, 0.05) * noise(n, 60, 0.04)
    if kind == "twill":
        rib = np.sin((xs + ys) * (2 * np.pi / 2.6))
        return (1.0 + 0.06 * rib) * noise(n, 3, 0.04) * noise(n, 50, 0.04)
    if kind == "jersey":
        return (1.0 + 0.04 * np.sin(xs * (2 * np.pi / 2.5))) * noise(n, 2, 0.05) * noise(n, 40, 0.04)
    return np.ones((n, n), np.float32)

def fabric(sh, col, pat, n):
    return sh * np.array(col, np.float32) * pattern(pat, n)[..., None]

# ------------------------------------------------------------------ Steckbriefe
CFG = {
    "tweed": {"skin": [(SK + "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png", 0.7),
                       (SK + "old_caucasian_male/old_lightskinned_male_diffuse.png", 0.3)],
              "eye": "brown", "hair": "short02", "haircol": (0.3, 0.27, 0.24), "browcol": (0.24, 0.2, 0.17),
              "shoes": "shoes01", "shoecol": (0.16, 0.09, 0.05)},
    "pulli": {"skin": [(SK + "young_caucasian_male/young_lightskinned_male_diffuse.png", 0.5),
                       (SK + "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png", 0.5)],
              "eye": "blue", "hair": "short03", "haircol": (0.42, 0.32, 0.2), "browcol": (0.3, 0.23, 0.15),
              "shoes": "boots_m", "shoecol": (0.2, 0.12, 0.07)},
    "hemd": {"skin": [(SK + "young_asian_male/young_lightskinned_male_diffuse3.png", 1.0)],
             "eye": "brown", "hair": "short04", "haircol": (0.04, 0.035, 0.03), "browcol": (0.04, 0.035, 0.03),
             "shoes": "shoes04", "shoecol": (0.12, 0.12, 0.12)},
    "jacke": {"skin": [(SK + "middleage_african_male/middleage_darkskinned_male_diffuse.png", 1.0)],
              "eye": "brown", "hair": "short01", "haircol": (0.04, 0.035, 0.03), "browcol": (0.04, 0.035, 0.03),
              "shoes": "boots_m", "shoecol": (0.1, 0.07, 0.05)},
    "anzug": {"skin": [(SK + "middleage_caucasian_male/middleage_lightskinned_male_diffuse.png", 1.0)],
              "eye": "grey", "hair": "short04", "haircol": (0.16, 0.12, 0.08), "browcol": (0.14, 0.1, 0.07),
              "shoes": "shoes01", "shoecol": (0.04, 0.035, 0.03)},
    "blazer": {"skin": [(SK + "middleage_caucasian_female/middleage_lightskinned_female_diffuse.png", 1.0)],
               "eye": "green", "hair": "bob02", "haircol": (0.36, 0.17, 0.09), "browcol": (0.27, 0.15, 0.09),
               "shoes": "boots_f", "shoecol": (0.13, 0.08, 0.05)},
    "bluse": {"skin": [(SK + "young_african_female/young_darkskinned_female_diffuse.png", 1.0)],
              "eye": "brown", "hair": "ponytail01", "haircol": (0.045, 0.035, 0.03), "browcol": (0.04, 0.03, 0.03),
              "shoes": "boots_f", "shoecol": (0.06, 0.05, 0.05)},
    "dame": {"skin": [(SK + "old_caucasian_female/old_lightskinned_female_diffuse.png", 0.7),
                      (SK + "middleage_caucasian_female/middleage_lightskinned_female_diffuse.png", 0.3)],
             "eye": "bluegreen", "hair": "bob01", "haircol": (0.66, 0.65, 0.63), "browcol": (0.45, 0.43, 0.41),
             "shoes": "boots_f", "shoecol": (0.08, 0.06, 0.05)},
    "alt": {"skin": [(SK + "old_caucasian_male/old_lightskinned_male_diffuse.png", 1.0)],
            "eye": "grey", "hair": "short01", "haircol": (0.72, 0.71, 0.69), "browcol": (0.6, 0.59, 0.57),
            "shoes": "shoes01", "shoecol": (0.07, 0.05, 0.04)},
    "kostuem": {"skin": [(SK + "middleage_asian_female/middleage_lightskinned_female_diffuse2.png", 1.0)],
                "eye": "brown", "hair": "long01", "haircol": (0.05, 0.04, 0.035), "browcol": (0.05, 0.04, 0.035),
                "shoes": "boots_f", "shoecol": (0.05, 0.045, 0.045)},
    "schlaf_m": {"skin": [(SK + "young_caucasian_male2/young_lightskinned_male_diffuse2.png", 1.0)],
                 "eye": "blue", "hair": "short02", "haircol": (0.22, 0.15, 0.09), "browcol": (0.2, 0.14, 0.09),
                 "shoes": "shoes01", "shoecol": (0.1, 0.1, 0.1)},
    "schlaf_f": {"skin": [(SK + "young_caucasian_female/young_lightskinned_female_diffuse.png", 1.0)],
                 "eye": "blue", "hair": "ponytail01", "haircol": (0.5, 0.36, 0.2), "browcol": (0.32, 0.23, 0.14),
                 "shoes": "boots_f", "shoecol": (0.1, 0.1, 0.1)},
}[KIND]

SHOES = {"shoes01": (C + "shoes01/shoes01_diffuse.png", C + "shoes01/shoes01_normal.png"),
         "shoes04": (C + "shoes04/shoes04_diffuse.png", C + "shoes04/shoes04_normal.png"),
         "boots_m": (C + "toigo_ankle_boots_male/BootsAnkleM.png", C + "toigo_ankle_boots_male/BootsNormals.jpg"),
         "boots_f": (C + "toigo_ankle_boots_female/BootsAnkle.png", C + "toigo_ankle_boots_female/BootsNormals.jpg")}

# Haut (2K: Gesichter in Nahaufnahmen)
skin = None
for p, w in CFG["skin"]:
    a = arr(p)
    skin = a * w if skin is None else skin + a * w
save(skin, "skin.jpg", 2048)

N = 2048
NORMAL = None
xs, ys = grid(N)
u = xs / N
v = ys / N

def toigo(src, fabc, pat, shirtc=(0.8, 0.8, 0.78), accc=(0.1, 0.1, 0.1), acc_rule=None, soft=2.5):
    sa = arr(src, "RGBA"); s = sa[..., :3]
    lum = s.mean(axis=2, keepdims=True)
    sat = s.max(axis=2, keepdims=True) - s.min(axis=2, keepdims=True)
    acc_m = acc_rule(s) if acc_rule is not None else (sat[..., 0] > 0.2)
    w_acc = np.clip(close_mask(acc_m.astype(np.float32), 15, 11, 1.5), 0, 1)
    w_shirt = np.clip((lum - 0.55) / 0.15, 0, 1) * (1 - w_acc)
    sh = shade_of(s, sa[..., 3], r=soft)
    fab = fabric(sh, fabc, pat, s.shape[0])
    acc = np.clip(lum / 0.5, 0.6, 1.2) * np.array(accc)
    shirt = np.array(shirtc) * np.clip(lum + 0.1, 0, 1) * pattern("jersey", s.shape[0])[..., None]
    return fab * (1 - w_shirt - w_acc) + shirt * w_shirt + acc * w_acc

if KIND == "tweed":
    src = C + "toigo_male_double-breasted_suit/DB-suit.png"
    out = toigo(src, (0.25, 0.2, 0.15), "herringbone", shirtc=(0.66, 0.71, 0.78), accc=(0.12, 0.17, 0.11))
    NORMAL = C + "toigo_male_double-breasted_suit/DB-suit-norm.png"
elif KIND == "alt":
    src = C + "toigo_male_suit_3/NewSuit3.png"
    out = toigo(src, (0.24, 0.235, 0.22), "twill", shirtc=(0.8, 0.79, 0.74), accc=(0.25, 0.08, 0.07))
    NORMAL = C + "toigo_male_suit_3/NewSuit3-norm.png"
elif KIND == "dame":
    src = C + "toigo_female_double-breasted_suit/DB-suit-Fem.png"
    out = toigo(src, (0.07, 0.15, 0.14), "melange", shirtc=(0.78, 0.76, 0.7), accc=(0.5, 0.42, 0.25),
                acc_rule=lambda s: ((s[..., 0] - s[..., 2]) > 0.15) & ((s[..., 0] - s[..., 1]) > 0.2))
    NORMAL = C + "toigo_female_double-breasted_suit/DB-suit-Fem-norm.png"
elif KIND == "kostuem":
    # grauer Nadelstreifen-Rockanzug -> dunkelblaues Wollkostuem (Nadelstreifen weichgezeichnet), weisse Bluse
    src = C + "toigo_female_suit/MHSuitsFem-diff.png"
    out = toigo(src, (0.1, 0.11, 0.15), "melange", shirtc=(0.84, 0.83, 0.8), accc=(0.45, 0.38, 0.22), soft=10.0)
elif KIND == "blazer":
    # pinker Hosenanzug -> kamelfarbener Wollblazer + Hose, weisse Bluse bleibt
    sa = arr(C + "toigo_female_suit_2/Fsuit2.png", "RGBA"); s = sa[..., :3]
    lum = s.mean(axis=2, keepdims=True)
    sat = s.max(axis=2, keepdims=True) - s.min(axis=2, keepdims=True)
    pink = ((s[..., 0] - s[..., 1]) > 0.15) & ((s[..., 2] - s[..., 1]) > 0.08)
    w_fab = close_mask(pink.astype(np.float32), 7, 7, 1.0)
    w_shirt = np.clip((lum - 0.6) / 0.15, 0, 1) * (sat < 0.15) * (1 - w_fab)
    sh = shade_of(s, None, r=2.5)
    fab = fabric(np.clip(lum / max(1e-3, float(np.percentile(lum[pink], 50))), 0.6, 1.3) if pink.any() else sh,
                 (0.4, 0.29, 0.18), "twill", s.shape[0])
    shirt = np.array((0.82, 0.8, 0.76)) * np.clip(lum + 0.05, 0, 1)
    other = np.array((0.12, 0.1, 0.09)) * shade_of(s, None, r=1.0)
    out = fab * w_fab + shirt * w_shirt + other * np.clip(1 - w_fab - w_shirt, 0, 1)
    NORMAL = C + "toigo_female_suit_2/Fsuit2-norm.png"
elif KIND == "anzug":
    # schwarzer Anzug -> mittelgrauer Flanell (Business-Pendler), Hemd hellblau
    sa = arr(C + "male_elegantsuit01/male_elegantsuit01_diffuse.png", "RGBA"); s = sa[..., :3]
    lum = s.mean(axis=2, keepdims=True)
    w_shirt = np.clip((lum - 0.45) / 0.15, 0, 1)
    sh = np.clip(lum / max(1e-3, float(np.percentile(lum, 50))), 0.5, 1.6)
    fab = fabric(sh, (0.2, 0.21, 0.23), "melange", N)
    out = fab * (1 - w_shirt) + np.array((0.6, 0.67, 0.76)) * np.clip(lum + 0.1, 0, 1) * w_shirt
elif KIND == "pulli":
    # Langarmshirt 02 -> marineblauer Strickpullover, Jeans dunkler (raw denim)
    sa = arr(C + "male_casualsuit02/male_casualsuit02_diffuse.png", "RGBA"); s = sa[..., :3]
    jeans = ((u < 0.76) & (v > 0.42)).astype(np.float32)[..., None]
    sh_top = shade_of(s, None, r=24.0, lo=0.9, hi=1.1)
    top = fabric(sh_top, (0.1, 0.13, 0.21), "knit", N)
    den = s * np.array((0.55, 0.6, 0.7)) * 0.9
    out = top * (1 - jeans) + den * jeans
    NORMAL = C + "male_casualsuit02/male_casualsuit02_normal.png"
elif KIND == "hemd":
    # Streifenhemd 03 -> hellblau/weiss gestreift, Jeans original
    sa = arr(C + "male_casualsuit03/male_casualsuit03_diffuse.png", "RGBA"); s = sa[..., :3]
    stripe_red = np.clip((s[..., 0] - s[..., 2] - 0.05) / 0.15, 0, 1)[..., None]
    shirt_m = close_mask(((s[..., 0] - s[..., 2]) > 0.08).astype(np.float32), 25, 17, 1.5)
    base = s.mean(axis=2, keepdims=True)
    sh = shade_of(s, None, r=6.0, lo=0.7, hi=1.2)
    shirt = sh * (np.array((0.78, 0.8, 0.82)) * (1 - stripe_red) + np.array((0.32, 0.42, 0.6)) * stripe_red) * pattern("jersey", N)[..., None]
    out = shirt * shirt_m + s * (1 - shirt_m)
    NORMAL = C + "male_casualsuit03/male_casualsuit03_normal.png"
elif KIND == "jacke":
    sa = arr(C + "male_casualsuit05/male_casualsuit05_diffuse.png", "RGBA"); s = sa[..., :3]
    jeans = close_mask((s[..., 2] - s[..., 0] > 0.08).astype(np.float32), 9, 7, 1.0)
    shirt = close_mask(((s[..., 0] - s[..., 1]) > 0.12).astype(np.float32), 25, 17, 1.5)
    sh = shade_of(s, sa[..., 3])
    out = fabric(sh, (0.2, 0.22, 0.17), "twill", N) * (1 - jeans - shirt) + s * np.array((0.6, 0.65, 0.75)) * jeans \
        + fabric(shade_of(s, None, r=6.0), (0.55, 0.52, 0.46), "jersey", N) * shirt
    NORMAL = C + "male_casualsuit05/male_casualsuit05_normal.png"
elif KIND == "bluse":
    # Bluse (gestreift) + Rock -> weinroter Feinstrickpullover, dunkelgrauer Rock.
    # 14.11.: Die Originalstreifen schlugen durch (Blur 8 px < Streifenabstand) und die Strickrippen
    # (5 px, quer ueber Rumpf und Aermel) wirkten selbst wie Streifen -> Schattierung nur grossflaechig,
    # feines Jersey statt Rippenstrick.
    sa = arr(C + "female_elegantsuit01/female_elegantsuit01_diffuse.png", "RGBA"); s = sa[..., :3]
    red = close_mask(((s[..., 0] - s[..., 1]) > 0.06).astype(np.float32), 45, 31, 2.0)
    sh_soft = shade_of(s, sa[..., 3], r=28.0, lo=0.9, hi=1.1)
    sh = shade_of(s, sa[..., 3], r=1.5)
    knit = fabric(sh_soft, (0.3, 0.08, 0.1), "jersey", N) * noise(N, 3, 0.04)[..., None]
    out = knit * red + fabric(sh, (0.13, 0.13, 0.14), "twill", N) * (1 - red)
    NORMAL = C + "female_elegantsuit01/female_elegantsuit01_normal.png"
elif KIND == "schlaf_m":
    # weisses T-Shirt 06 (Logo weg) -> hellgraues Schlafshirt
    sa = arr(C + "male_casualsuit06/male_casualsuit06_diffuse.png", "RGBA"); s = sa[..., :3]
    jeans = ((u < 0.72) & (v > 0.48)).astype(np.float32)[..., None]
    sh = shade_of(s, None, r=24.0, lo=0.9, hi=1.1)
    out = fabric(sh, (0.62, 0.62, 0.6), "melange", N) * (1 - jeans) + s * 0.6 * jeans
    NORMAL = C + "male_casualsuit06/male_casualsuit06_normal.png"
else:  # schlaf_f
    sa = arr(C + "female_casualsuit01/female_casualsuit01_diffuse.png", "RGBA"); s = sa[..., :3]
    jeans = ((u < 0.72) & (v > 0.45)).astype(np.float32)[..., None]
    sh = shade_of(s, None, r=24.0, lo=0.9, hi=1.1)
    out = fabric(sh, (0.5, 0.4, 0.42), "melange", N) * (1 - jeans) + s * 0.6 * jeans
    NORMAL = C + "female_casualsuit01/female_casualsuit01_normal.png"
save(np.clip(out, 0, 1), "suit.jpg", 2048)
if NORMAL and os.path.isfile(NORMAL):
    save(arr(NORMAL), "suit_n.png", 1024)

# Schuhe: Leder mit Original-Struktur
sd, sn = SHOES[CFG["shoes"]]
ba = arr(sd, "RGBA"); b = ba[..., :3]
bl = b.max(axis=2, keepdims=True)
inside = ba[..., 3] > 0.5
bl = bl / max(1e-3, float(np.percentile(bl[inside] if inside.any() else bl, 60)))
save(np.clip(bl * np.array(CFG["shoecol"]) * 1.4, 0, 0.6), "shoes.jpg", 512)
if os.path.isfile(sn):
    save(arr(sn), "shoes_n.png", 512)

# Augen
e = arr(D + "/eyes/materials/%s_eye.png" % CFG["eye"]); el = e.mean(axis=2, keepdims=True)
save(np.clip(el + (e - el) * 0.6, 0, 1) * 0.92, "eye.jpg", 256)

hair_dir = D + "/hair/%s/" % CFG["hair"]
hair_src = [f for f in os.listdir(hair_dir) if f.endswith("_diffuse.png")][0]
for src, name, size, col in [
    (D + "/eyebrows/eyebrow001/eyebrow001.png", "brow.png", 256, CFG["browcol"]),
    (D + "/eyelashes/eyelashes01/eyelashes01.png", "lash.png", 256, (0.05, 0.04, 0.035)),
    (hair_dir + hair_src, "hair.png", 1024, CFG["haircol"]),
]:
    a = arr(src, "RGBA")
    l = a[..., :3].mean(axis=2, keepdims=True)
    l = l / max(1e-3, float(np.percentile(l[a[..., 3] > 0.5], 60))) if (a[..., 3] > 0.5).any() else l
    # Straehnen: Helligkeitsspreizung etwas verstaerken, damit Haar nicht wie eine Kappe wirkt
    l = np.clip(1.0 + (l - 1.0) * 1.35, 0.25, 1.6)
    rgb = np.clip(l * np.array(col), 0, 1)
    save(np.concatenate([rgb, a[..., 3:4]], axis=2), name, size)
hn = [f for f in os.listdir(hair_dir) if f.endswith("_normal.png")]
if hn:
    save(arr(hair_dir + hn[0]), "hair_n.png", 1024)
print("ok", KIND, sorted(os.listdir(OUT)))
