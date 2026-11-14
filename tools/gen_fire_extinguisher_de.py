# Feuerloescher (Poly Haven korean_fire_extinguisher_01, CC0) -> deutsche Beschriftung, Kopie in fire_extinguisher_de/
import os, shutil, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageOps
import numpy as np
SRC = "D:/project_alo/assets/environment/interior/models/korean_fire_extinguisher_01"
DST = "D:/project_alo/assets/environment/interior/models/fire_extinguisher_de"
os.makedirs(DST + "/textures", exist_ok=True)
OLD, NEW = "korean_fire_extinguisher_01", "fire_extinguisher_de"
g = open(f"{SRC}/{OLD}.gltf", encoding="utf-8").read().replace(OLD, NEW)
open(f"{DST}/{NEW}.gltf", "w", encoding="utf-8", newline="\n").write(g)
shutil.copyfile(f"{SRC}/{OLD}.bin", f"{DST}/{NEW}.bin")
def T(part, kind): return f"{SRC}/textures/{OLD}_{part}_{kind}_1k.jpg"
def O(part, kind): return f"{DST}/textures/{NEW}_{part}_{kind}_1k.jpg"
random.seed(7)
F = "C:/Windows/Fonts/bahnschrift.ttf"
HAND = "C:/Windows/Fonts/Inkfree.ttf"
def font(sz, var="Bold Condensed"):
    f = ImageFont.truetype(F, sz)
    try:
        f.set_variation_by_name(var)
    except Exception:
        pass
    return f

# ---------------- Koerper: Schriftfeld oben links + Etikett
TXT = (14, 28, 326, 106)          # Bereich der koreanischen Buchstaben im Schriftfeld
PATCH = (40, 330)                 # glatte rote Flaeche am Zylinder (gleiche Groesse)
LABEL = (195, 600, 432, 688)
for kind in ["diff", "nor_gl", "arm"]:
    im = Image.open(T("body", kind)).convert("RGB")
    w, h = TXT[2] - TXT[0], TXT[3] - TXT[1]
    im.paste(im.crop((PATCH[0], PATCH[1], PATCH[0] + w, PATCH[1] + h)), TXT[:2])
    if kind == "diff":
        mask = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(mask)
        f = font(66)
        bb = d.textbbox((0, 0), "FEUERLÖSCHER", font=f)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        sx = min(1.0, (w - 16) / tw)
        big = Image.new("L", (tw + 4, th + 4), 0)
        ImageDraw.Draw(big).text((2 - bb[0], 2 - bb[1]), "FEUERLÖSCHER", font=f, fill=255)
        big = big.resize((int(big.width * sx), big.height))
        mask.paste(big, ((w - big.width) // 2, (h - big.height) // 2))
        n = np.asarray(mask).astype(float) / 255.0
        noise = np.random.default_rng(3).random((h, w))
        n *= np.clip(0.75 + 0.35 * noise, 0, 1)
        n[noise > 0.93] *= 0.3
        base = np.asarray(im.crop(TXT)).astype(float)
        col = np.array([205, 205, 198], float) * (0.85 + 0.15 * noise[..., None])
        out = base * (1 - n[..., None]) + col * n[..., None]
        im.paste(Image.fromarray(out.astype(np.uint8)), TXT[:2])
        # Etikett
        lw, lh = LABEL[2] - LABEL[0], LABEL[3] - LABEL[1]
        S = 3
        L = Image.new("RGB", (lw * S, lh * S), (236, 234, 226))
        d = ImageDraw.Draw(L)
        d.rectangle((0, 0, lw * S, 17 * S), fill=(196, 28, 30))
        d.text((6 * S, 1 * S), "FEUERLÖSCHER", font=font(15 * S), fill=(250, 250, 245))
        d.text((112 * S, 3 * S), "ABC-Pulver  6 kg", font=font(11 * S, "SemiBold Condensed"), fill=(250, 250, 245))
        d.text((6 * S, 20 * S), "PG 6  -  DIN EN 3", font=font(10 * S), fill=(30, 30, 34))
        for k in range(7):
            y = (34 + k * 6) * S
            ww = random.randint(60, 100)
            d.rectangle((6 * S, y, (6 + ww) * S, y + 2 * S), fill=(110, 110, 112))
        for i, c in enumerate([(196, 28, 30), (30, 70, 150), (196, 28, 30)]):
            x = (118 + i * 26) * S
            d.rectangle((x, 26 * S, x + 22 * S, 48 * S), outline=c, width=2 * S)
            d.text((x + 6 * S, 28 * S), "ABC"[i], font=font(16 * S), fill=c)
        d.text((118 * S, 54 * S), "Gebrauchsanweisung", font=font(9 * S, "SemiBold Condensed"), fill=(30, 30, 34))
        for k in range(4):
            y = (66 + k * 5) * S
            d.rectangle((118 * S, y, (118 + random.randint(50, 70)) * S, y + 2 * S), fill=(120, 120, 122))
        d.rectangle((196 * S, 54 * S, 228 * S, 84 * S), outline=(40, 40, 40), width=S)
        d.text((199 * S, 62 * S), "2029", font=font(10 * S), fill=(40, 40, 40))
        L = L.resize((lw, lh), Image.LANCZOS)
        old = ImageOps.grayscale(im.crop(LABEL)).filter(ImageFilter.GaussianBlur(6))
        ga = np.asarray(old).astype(float)
        ga = 0.85 + 0.15 * (ga / max(ga.max(), 1))
        La = np.asarray(L).astype(float) * ga[..., None]
        im.paste(Image.fromarray(np.clip(La, 0, 255).astype(np.uint8)), LABEL[:2])
    im.save(O("body", kind), quality=92)

# ---------------- Pruefkarte
FR = (16, 18)
BK = (519, 353, 992, 999)
for kind in ["diff", "nor_gl", "arm"]:
    im = Image.open(T("paper", kind)).convert("RGB")
    im.paste(ImageOps.mirror(im.crop(BK)), FR)
    if kind == "diff":
        d = ImageDraw.Draw(im)
        x0, y0 = FR[0] + 30, FR[1] + 70
        cw = BK[2] - BK[0] - 60
        d.rectangle((x0, y0, x0 + cw, y0 + 78), fill=(200, 40, 38))
        d.text((x0 + 24, y0 + 8), "PRÜFNACHWEIS", font=font(58), fill=(245, 240, 235))
        y = y0 + 100
        for lab, val in [("Standort", "Flur 2"), ("Nr.", "F-17")]:
            d.text((x0 + 6, y), lab, font=font(30, "SemiBold Condensed"), fill=(60, 30, 30))
            d.text((x0 + 170, y - 4), val, font=ImageFont.truetype(HAND, 36), fill=(40, 40, 70))
            d.line((x0, y + 40, x0 + cw, y + 40), fill=(170, 60, 60), width=2)
            y += 54
        y += 10
        ytab = y
        for xx, lab in [(x0 + 6, "Datum"), (x0 + 170, "Prüfer"), (x0 + 320, "Befund")]:
            d.text((xx, y), lab, font=font(28, "SemiBold Condensed"), fill=(60, 30, 30))
        y += 40
        hand = ImageFont.truetype(HAND, 32)
        for dt, pr, bf in [("03/27", "Brandt", "i.O."), ("03/28", "Brandt", "i.O."), ("02/29", "Weiß", "i.O."), ("", "", ""), ("", "", "")]:
            d.line((x0, y + 38, x0 + cw, y + 38), fill=(170, 60, 60), width=2)
            d.text((x0 + 8, y), dt, font=hand, fill=(35, 35, 75))
            d.text((x0 + 172, y), pr, font=hand, fill=(35, 35, 75))
            d.text((x0 + 322, y), bf, font=hand, fill=(35, 35, 75))
            y += 46
        for xx in (x0 + 160, x0 + 310):
            d.line((xx, ytab, xx, y), fill=(170, 60, 60), width=2)
    im.save(O("paper", kind), quality=92)
for kind in ["diff", "nor_gl", "arm"]:
    shutil.copyfile(T("glass", kind), O("glass", kind))
print("ok")
