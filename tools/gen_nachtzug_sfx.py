"""Synthetische Sounds für Mission "Nachtzug" (nachtzug) – eigene Arbeit, CC0 -> assets/sfx/nachtzug_*.ogg

  python tools/gen_nachtzug_sfx.py

Nutzt die Helfer aus gen_overwatch_sfx.py (Filter, Hall, Loop, Speichern via ffmpeg).

  nachtzug_rail_loop       Rollgeräusch im Waggon: tiefes Dröhnen, Radsatz-Rauschen, Pendelbrummen, Loop (8 s)
  nachtzug_clack           Schienenstoß: zwei Drehgestelle, je zwei Achsen (da-dam ... da-dam)
  nachtzug_wind_roof       Fahrtwind auf dem Dach: Rauschen, Böen, Pfeifen, Loop (10 s)
  nachtzug_tunnel_whoosh   Tunneleinfahrt: Druckschlag, Dröhnen, nachhallendes Rauschen (~4 s)
  nachtzug_brake           Bremsen: Quietschen der Klötze, Schleifen, Ausrollen (~16 s)
  nachtzug_spark           Funke an der Oberleitung: elektrischer Knall mit Brummen
  nachtzug_chime           Zuggong vor einer Durchsage (drei Töne)
  nachtzug_crossing_bell   Bahnübergangsglocke, kurz vorbeiziehend (~3 s)
  nachtzug_door            Schiebetür zwischen den Waggons: Entriegeln, Rollen, Anschlag
  nachtzug_coupling        Kupplung löst sich: Bolzen, Druckluftzischen, schwerer Stahlschlag
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from gen_overwatch_sfx import (SR, t_axis, bp, lp, hp, reverb_ir, convolve, scaled, distant,  # noqa: E402
                               fade, softlimit, make_loop, save, shifted)


def _knock(t, t0, rng, f_lo=60.0, f_hi=900.0, dec=0.03, amp=1.0):
    tt, on = shifted(t, t0)
    n = rng.standard_normal(t.size)
    x = lp(n, f_hi) * np.exp(-tt / dec) * on * amp
    x += np.sin(2 * np.pi * f_lo * tt) * np.exp(-tt / (dec * 1.6)) * on * amp * 0.9
    x += bp(n, 1500, 4500) * np.exp(-tt / 0.008) * on * amp * 0.25
    return x


def rail_loop():
    rng = np.random.default_rng(8101)
    sec = 8.0
    t = t_axis(sec + 0.8)
    n = rng.standard_normal(t.size)
    # Dröhnen des Wagenkastens + Rad-Schiene-Rauschen
    x = lp(n, 140) * 0.9
    x += bp(n, 180, 900) * 0.35 * (0.8 + 0.2 * np.sin(2 * np.pi * 0.37 * t))
    x += bp(rng.standard_normal(t.size), 1800, 4200) * 0.05
    # Pendelbrummen der Lok/Umrichter, gedämpft durch den Zug
    for f, a in [(33.0, 0.25), (66.0, 0.12), (100.0, 0.06)]:
        x += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * a
    # leises Klappern im Wagen (Innenausstattung)
    for _ in range(14):
        t0 = rng.uniform(0.2, sec)
        tt, on = shifted(t, t0)
        x += bp(rng.standard_normal(t.size), 1200, 3800) * np.exp(-tt / 0.01) * on * 0.12
    x = softlimit(x, 1.3)
    y = make_loop(x, 0.8)
    save("nachtzug_rail_loop", y, peak=0.75, loop=True)


def clack():
    rng = np.random.default_rng(8102)
    t = t_axis(1.6)
    x = np.zeros_like(t)
    # Drehgestell 1: zwei Achsen kurz hintereinander, Drehgestell 2 nach ~0.55 s
    for t0, a in [(0.0, 1.0), (0.085, 0.85), (0.56, 0.75), (0.645, 0.65)]:
        x += _knock(t, t0, rng, 70.0, 1200.0, 0.028, a)
    ir = reverb_ir(0.6, 0.8, 0.6, 0.3, rng, onset=0.005)
    y = x + scaled(convolve(lp(x, 1800), ir), x, 0.25)
    y = softlimit(y, 1.8)
    save("nachtzug_clack", fade(y, 0, 0.2), peak=0.9)


def wind_roof():
    rng = np.random.default_rng(8103)
    sec = 10.0
    t = t_axis(sec + 1.0)
    n = rng.standard_normal(t.size)
    gust = 0.65 + 0.35 * np.sin(2 * np.pi * 0.21 * t) * np.sin(2 * np.pi * 0.53 * t + 0.7)
    x = lp(n, 400) * 0.9 * gust
    x += bp(n, 500, 3000) * 0.4 * gust
    x += hp(rng.standard_normal(t.size), 3500) * 0.08 * gust
    # Pfeifen an Kanten (schmalbandig, wandert)
    f = 900 + 160 * np.sin(2 * np.pi * 0.13 * t)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x += np.sin(ph) * 0.03 * gust
    # Kleidung flattert: tiefes, schnelles Knattern
    flap = (np.sin(2 * np.pi * 11.0 * t) > 0.75).astype(float)
    x += lp(flap * rng.standard_normal(t.size), 300) * 0.25 * gust
    x = softlimit(x, 1.4)
    y = make_loop(x, 1.0)
    save("nachtzug_wind_roof", y, peak=0.8, loop=True)


def tunnel_whoosh():
    rng = np.random.default_rng(8104)
    t = t_axis(4.5)
    n = rng.standard_normal(t.size)
    # Druckschlag beim Eintauchen, dann dichtes Dröhnen
    slam = lp(n, 200) * np.exp(-t / 0.12) * 2.0
    rise = np.clip(t / 0.05, 0, 1)
    body = (lp(n, 600) * 0.9 + bp(n, 600, 3000) * 0.4) * rise * np.exp(-t / 2.2)
    x = slam + body
    ir = reverb_ir(2.0, 1.6, 0.8, 0.2, rng, onset=0.02)
    y = x + scaled(convolve(lp(x, 2500), ir), x, 0.6)
    y = softlimit(y, 1.6)
    save("nachtzug_tunnel_whoosh", fade(y, 0.01, 1.0), peak=0.9)


def brake():
    rng = np.random.default_rng(8105)
    sec = 16.0
    t = t_axis(sec)
    n = rng.standard_normal(t.size)
    env = np.clip(t / 0.6, 0, 1) * np.clip((sec - t) / 2.5, 0, 1)
    # Quietschen: mehrere schmale, wandernde Töne
    x = np.zeros_like(t)
    for f0, a, wob in [(2350.0, 0.25, 40.0), (3120.0, 0.18, 60.0), (1730.0, 0.12, 25.0)]:
        f = f0 + wob * np.sin(2 * np.pi * rng.uniform(0.2, 0.6) * t + rng.uniform(0, 6))
        ph = 2 * np.pi * np.cumsum(f) / SR
        am = 0.6 + 0.4 * np.sin(2 * np.pi * rng.uniform(1.5, 4.0) * t) ** 2
        x += np.sin(ph) * a * am
    # Schleifen und Rollen, wird langsamer und leiser
    slow = np.clip(1.0 - t / sec, 0.05, 1.0)
    x += bp(n, 300, 2500) * 0.35 * slow
    x += lp(n, 120) * 0.6 * slow
    x *= env
    x = softlimit(x, 1.5)
    save("nachtzug_brake", fade(x, 0.05, 1.5), peak=0.85)


def spark():
    rng = np.random.default_rng(8106)
    t = t_axis(1.2)
    n = rng.standard_normal(t.size)
    snap = hp(n, 1500) * np.exp(-t / 0.01) * 1.6
    crackle = np.zeros_like(t)
    for _ in range(18):
        t0 = rng.uniform(0.0, 0.35)
        tt, on = shifted(t, t0)
        crackle += hp(rng.standard_normal(t.size), 2500) * np.exp(-tt / 0.003) * on * rng.uniform(0.3, 1.0)
    hum = np.sign(np.sin(2 * np.pi * 50.0 * t)) * np.exp(-t / 0.15) * 0.25
    x = snap + crackle * 0.6 + lp(hum, 1500)
    x = softlimit(x, 2.0)
    save("nachtzug_spark", fade(x, 0, 0.3), peak=0.85)


def chime():
    t = t_axis(3.2)
    x = np.zeros_like(t)
    for i, f in enumerate([659.3, 523.3, 784.0]):
        tt, on = shifted(t, i * 0.42)
        tone = np.sin(2 * np.pi * f * tt) + 0.35 * np.sin(2 * np.pi * 2 * f * tt) + 0.12 * np.sin(2 * np.pi * 3.01 * f * tt)
        x += tone * np.exp(-tt / 0.7) * on * np.clip(tt / 0.004, 0, 1)
    # kleiner Lautsprecher: Bandpass, leicht verzerrt
    x = bp(x, 350, 4500)
    x = softlimit(x * 1.3, 1.4)
    save("nachtzug_chime", fade(x, 0, 0.4), peak=0.8)


def crossing_bell():
    rng = np.random.default_rng(8108)
    t = t_axis(3.4)
    x = np.zeros_like(t)
    k = 0.0
    while k < 3.0:
        tt, on = shifted(t, k)
        for f, a in [(1180.0, 1.0), (2810.0, 0.4), (4020.0, 0.2)]:
            x += np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.12) * on * a
        k += 0.27
    # Vorbeifahrt: anschwellen, abschwellen
    env = np.exp(-((t - 1.3) / 0.9) ** 2)
    x = x * env
    y = distant(x, 3500, 1.2, 1.0, 0.3, rng)
    save("nachtzug_crossing_bell", fade(y, 0.05, 0.4), peak=0.7)


def door():
    rng = np.random.default_rng(8109)
    t = t_axis(1.4)
    x = _knock(t, 0.0, rng, 180.0, 2500.0, 0.012, 0.6)            # Riegel
    tt, on = shifted(t, 0.08)
    roll = bp(rng.standard_normal(t.size), 250, 1600) * on * np.clip(tt / 0.05, 0, 1) * np.clip((0.6 - tt) / 0.1, 0, 1)
    x += roll * 0.5
    x += _knock(t, 0.68, rng, 90.0, 1400.0, 0.04, 0.9)            # Anschlag
    ir = reverb_ir(0.5, 0.6, 0.6, 0.3, rng, onset=0.004)
    y = x + scaled(convolve(x, ir), x, 0.2)
    save("nachtzug_door", fade(softlimit(y, 1.6), 0, 0.2), peak=0.85)


def coupling():
    rng = np.random.default_rng(8110)
    t = t_axis(4.5)
    x = _knock(t, 0.0, rng, 140.0, 3000.0, 0.02, 0.7)             # Bolzen
    x += _knock(t, 0.18, rng, 60.0, 900.0, 0.12, 1.4)             # Stahlschlag
    tt, on = shifted(t, 0.3)
    hiss = hp(rng.standard_normal(t.size), 1800) * on * np.exp(-tt / 1.1) * 0.8   # Bremsleitung reisst
    x += hiss
    # metallisches Nachklingen
    for f in (310.0, 517.0, 893.0):
        tt2, on2 = shifted(t, 0.18)
        x += np.sin(2 * np.pi * f * tt2) * np.exp(-tt2 / 0.6) * on2 * 0.12
    ir = reverb_ir(1.0, 1.0, 0.7, 0.25, rng, onset=0.01)
    y = x + scaled(convolve(lp(x, 3000), ir), x, 0.3)
    save("nachtzug_coupling", fade(softlimit(y, 1.8), 0, 0.6), peak=0.9)


if __name__ == "__main__":
    rail_loop()
    clack()
    wind_roof()
    tunnel_whoosh()
    brake()
    spark()
    chime()
    crossing_bell()
    door()
    coupling()
