"""Erzeugt Schilder/Aufkleber fuer die Nachtzug-Waggons (nur erfundene Schriftzuege, CC0).
Ausgabe: assets/environment/train/signs/*.png"""
import os, random
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "environment", "train", "signs")
F = "C:/Windows/Fonts/"

def font(sz, bold=True):
    for n in (["arialbd.ttf", "segoeuib.ttf"] if bold else ["arial.ttf", "segoeui.ttf"]):
        try:
            return ImageFont.truetype(F + n, sz)
        except OSError:
            pass
    return ImageFont.load_default()

def wear(im, amount=0.12, seed=1):
    """Leichte Abnutzung: Rauschen, Kratzer, abgeriebene Ecken."""
    r = random.Random(seed)
    d = ImageDraw.Draw(im)
    w, h = im.size
    for _ in range(int(18 * amount * 10)):
        x, y = r.randrange(w), r.randrange(h)
        l = r.randrange(6, 40)
        a = r.uniform(-0.6, 0.6)
        c = r.randrange(160, 235)
        d.line([(x, y), (x + l, y + l * a)], fill=(c, c, c, r.randrange(12, 40)), width=1)
    for _ in range(int(400 * amount)):
        x, y = r.randrange(w), r.randrange(h)
        d.point((x, y), fill=(60, 55, 50, r.randrange(20, 70)))
    return im

def center(d, xy, text, f, fill):
    b = d.textbbox((0, 0), text, font=f)
    d.text((xy[0] - (b[2] - b[0]) / 2 - b[0], xy[1] - (b[3] - b[1]) / 2 - b[1]), text, font=f, fill=fill)

def notbremse():
    im = Image.new("RGBA", (512, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([4, 4, 507, 251], 18, fill=(196, 22, 20, 255), outline=(240, 240, 235, 255), width=6)
    center(d, (256, 70), "NOTBREMSE", font(78), (250, 250, 245, 255))
    d.rectangle([40, 125, 471, 129], fill=(250, 250, 245, 255))
    center(d, (256, 163), "Nur bei Gefahr ziehen", font(34, False), (250, 250, 245, 255))
    center(d, (256, 210), "Missbrauch wird verfolgt", font(30, False), (250, 250, 245, 255))
    im.save(os.path.join(OUT, "notbremse.png"))

def fahrplan():
    im = Image.new("RGBA", (512, 704), (236, 232, 218, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 511, 96], fill=(22, 44, 92, 255))
    center(d, (256, 34), "ALPEN-DONAU-BAHN", font(40), (245, 240, 225, 255))
    center(d, (256, 74), "Nachtzug ADB 466  ·  Kurswagen 2", font(26, False), (215, 205, 175, 255))
    rows = [("Innsbruck Hbf", "22:15", ""), ("Jenbach", "22:36", "22:38"), ("Wörgl", "22:52", "22:54"),
            ("Kufstein Grenzbf.", "23:07", "23:15"), ("Bischofshofen", "00:41", "00:44"),
            ("Vöcklabruck", "01:58", "02:00"), ("Linz Hbf", "02:41", "02:49"), ("Amstetten", "03:27", "03:29"),
            ("St. Pölten Hbf", "04:06", "04:08"), ("Wien Westbf.", "04:39", "")]
    f, fb = font(25, False), font(25)
    d.text((24, 112), "Bahnhof", font=fb, fill=(30, 30, 30, 255))
    d.text((330, 112), "an", font=fb, fill=(30, 30, 30, 255))
    d.text((420, 112), "ab", font=fb, fill=(30, 30, 30, 255))
    d.line([(20, 146), (492, 146)], fill=(40, 40, 40, 255), width=2)
    for i, (s, a, b) in enumerate(rows):
        y = 160 + i * 48
        if i % 2 == 0:
            d.rectangle([16, y - 6, 496, y + 36], fill=(225, 220, 202, 255))
        d.text((24, y), s, font=f, fill=(25, 25, 25, 255))
        d.text((324, y), a if b else (a if i else ""), font=f, fill=(25, 25, 25, 255))
        d.text((414, y), b if b else (a if i == 0 else ""), font=f, fill=(25, 25, 25, 255))
    d.text((24, 652), "Änderungen vorbehalten · Stand Juni 2030", font=font(18, False), fill=(80, 80, 80, 255))
    wear(im, 0.15, 7)
    im.save(os.path.join(OUT, "fahrplan.png"))

def rauchverbot():
    im = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([8, 8, 247, 247], fill=(245, 243, 238, 255), outline=(200, 25, 25, 255), width=22)
    d.rectangle([52, 118, 186, 142], fill=(30, 30, 30, 255))
    d.rectangle([186, 118, 204, 142], fill=(200, 90, 40, 255))
    for k in range(3):
        d.arc([196 + k * 2, 60 + k * 12, 226, 112], 200, 320, fill=(90, 90, 90, 255), width=4)
    d.line([(52, 52), (204, 204)], fill=(200, 25, 25, 255), width=22)
    wear(im, 0.06, 3)
    im.save(os.path.join(OUT, "rauchverbot.png"))

def aufkleber():
    """Abgewetzter Reiseaufkleber (erfundenes Hostel/Skigebiet)."""
    im = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([10, 10, 245, 245], fill=(240, 196, 52, 255), outline=(30, 60, 110, 255), width=10)
    d.polygon([(40, 170), (100, 80), (130, 120), (160, 70), (216, 170)], fill=(30, 60, 110, 255))
    d.polygon([(100, 80), (115, 102), (88, 100)], fill=(250, 250, 250, 255))
    d.polygon([(160, 70), (176, 96), (146, 92)], fill=(250, 250, 250, 255))
    center(d, (128, 200), "HOCHALM", font(34), (30, 60, 110, 255))
    im = wear(im, 0.4, 11)
    a = im.split()[3].point(lambda v: v)
    r = random.Random(5)
    dm = ImageDraw.Draw(a)
    for _ in range(30):
        x, y = r.randrange(256), r.randrange(256)
        dm.ellipse([x, y, x + r.randrange(3, 14), y + r.randrange(2, 8)], fill=0)
    im.putalpha(a)
    im.save(os.path.join(OUT, "aufkleber.png"))

def hinweis():
    """Kleines Hinweisschild am Fenster (Piktogramm + Text)."""
    im = Image.new("RGBA", (512, 128), (238, 236, 228, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 511, 127], outline=(40, 40, 40, 255), width=4)
    d.rectangle([14, 14, 112, 113], fill=(22, 44, 92, 255))
    d.rectangle([34, 30, 92, 98], outline=(245, 245, 245, 255), width=6)
    d.line([(34, 64), (92, 64)], fill=(245, 245, 245, 255), width=5)
    d.text((130, 22), "Fenster während der Fahrt", font=font(30, False), fill=(25, 25, 25, 255))
    d.text((130, 66), "nicht öffnen", font=font(30), fill=(25, 25, 25, 255))
    wear(im, 0.1, 9)
    im.save(os.path.join(OUT, "hinweis.png"))

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    notbremse(); fahrplan(); rauchverbot(); aufkleber(); hinweis()
    print("ok")
