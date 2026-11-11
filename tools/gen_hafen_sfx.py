"""Synthetische Sounds für Mission "Kräne" (hafen) – eigene Arbeit, CC0 -> assets/sfx/hafen_*.ogg

  python tools/gen_hafen_sfx.py

Nutzt die Helfer aus gen_overwatch_sfx.py (Filter, Hall, Loop, Speichern via ffmpeg).

  hafen_mg             ein Schuss des Bord-MG (7.62) aus Schützensicht: harter Knall, Mechanik, Wasserecho
  hafen_boat_engine    Außenbord-/Jetantrieb, tiefes Brummen mit Harmonischen, nahtlos loopbar (4 s)
  hafen_water_hull     Rumpf schlägt auf kurze Wellen, Gischtrauschen, nahtlos loopbar (6 s)
  hafen_horn           tiefes Schiffshorn eines Frachters, weit entfernt (~6 s)
  hafen_amb_harbour    Hafen bei Nacht im Regen: fernes Brummen, Kettenklirren, Möwen-arm, Loop (20 s)
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from gen_overwatch_sfx import (SR, t_axis, bp, lp, hp, reverb_ir, convolve, scaled, distant,  # noqa: E402
                               fade, softlimit, make_loop, save, shifted)


def mg_shot():
    rng = np.random.default_rng(7301)
    t = t_axis(1.4)
    n = rng.standard_normal(t.size)
    # Mündungsknall: kurzer breitbandiger Transient + tiefer Druckstoss
    crack = hp(n, 900) * np.exp(-t / 0.006)
    boom = lp(n, 260) * np.exp(-t / 0.045) * 2.2
    body = bp(n, 250, 1800) * np.exp(-t / 0.02) * 1.2
    thump = np.sin(2 * np.pi * 62 * t) * np.exp(-t / 0.05) * 0.9
    # Verschluss/Gurt: zwei kleine metallische Klicks
    tt, on = shifted(t, 0.035)
    clk = bp(rng.standard_normal(t.size), 2500, 7000) * np.exp(-tt / 0.004) * on * 0.25
    tt2, on2 = shifted(t, 0.058)
    clk += bp(rng.standard_normal(t.size), 1800, 5000) * np.exp(-tt2 / 0.005) * on2 * 0.18
    x = crack + boom + body + thump + clk
    # offenes Wasser: kurzer Hall, Rückwurf von Kaimauer/Containern
    ir = reverb_ir(1.2, 1.0, 0.7, 0.25, rng, onset=0.01)
    y = x + scaled(convolve(lp(x, 2500), ir), x, 0.35)
    k = int(SR * 0.21)
    e = np.zeros_like(y)
    e[k:] = lp(y, 1200)[: y.size - k] * 0.25
    y = softlimit(y + e, 2.2)
    save("hafen_mg", fade(y, 0, 0.3), peak=0.92)


def boat_engine():
    rng = np.random.default_rng(7302)
    sec = 4.0
    t = t_axis(sec + 0.5)
    # Grundton ~38 Hz (V8 bei mittlerer Drehzahl), leicht schwankend, ganzzahlig loopbar
    f0 = 38.0 + 0.6 * np.sin(2 * np.pi * 0.5 * t)
    ph = 2 * np.pi * np.cumsum(f0) / SR
    x = np.zeros_like(t)
    for k, a in [(1, 1.0), (2, 0.7), (3, 0.45), (4, 0.3), (6, 0.18), (8, 0.1)]:
        x += a * np.sin(k * ph + rng.uniform(0, 6.28))
    # Zuendungen als Pulse
    puls = (np.sin(ph * 4) > 0.6).astype(float)
    x += lp(puls * rng.standard_normal(t.size), 600) * 0.6
    # Ansaug-/Auspuffrauschen und Wasser am Jet
    x += bp(rng.standard_normal(t.size), 300, 1400) * 0.25
    x += hp(rng.standard_normal(t.size), 2500) * 0.05
    x = lp(x, 2200)
    x = softlimit(x, 1.6)
    y = make_loop(x, 0.5)
    save("hafen_boat_engine", y, peak=0.8, loop=True)


def water_hull():
    rng = np.random.default_rng(7303)
    sec = 6.0
    t = t_axis(sec + 0.6)
    n = rng.standard_normal(t.size)
    # Dauer-Gischt: gefiltertes Rauschen, Pegel atmet mit den Wellen
    env = 0.6 + 0.4 * np.sin(2 * np.pi * 0.7 * t + 1.0) * np.sin(2 * np.pi * 0.23 * t)
    x = bp(n, 400, 5000) * env * 0.5 + lp(n, 250) * 0.4
    # Schlaege des Rumpfes auf kurze Wellen (zufaellig, ~1.5/s)
    hits = np.sort(rng.uniform(0.1, sec + 0.4, int(sec * 1.5)))
    for h in hits:
        tt, on = shifted(t, h)
        a = rng.uniform(0.5, 1.0)
        x += lp(rng.standard_normal(t.size), 180) * np.exp(-tt / 0.07) * on * 2.0 * a
        x += bp(rng.standard_normal(t.size), 800, 4000) * np.exp(-tt / 0.25) * on * 0.5 * a
    x = softlimit(x, 1.4)
    y = make_loop(x, 0.6)
    save("hafen_water_hull", y, peak=0.8, loop=True)


def horn():
    rng = np.random.default_rng(7304)
    t = t_axis(7.0)
    dur = 4.2
    env = np.clip(t / 0.25, 0, 1) * np.clip((dur - t) / 0.6, 0, 1)
    f0 = 73.0 * (1 + 0.004 * np.sin(2 * np.pi * 5 * t))
    ph = 2 * np.pi * np.cumsum(f0) / SR
    x = np.zeros_like(t)
    for k, a in [(1, 1.0), (2, 0.8), (3, 0.6), (4, 0.4), (5, 0.3), (6, 0.2), (7, 0.12)]:
        x += a * np.sin(k * ph)
    x = softlimit(x * env, 1.8)
    x += bp(rng.standard_normal(t.size), 200, 900) * env * 0.05
    y = distant(x, 900, 4.0, 3.0, 0.9, rng, slap=(0.9, 0.35))
    save("hafen_horn", fade(y, 0, 1.2), peak=0.9)


def amb_harbour():
    rng = np.random.default_rng(7305)
    sec = 20.0
    t = t_axis(sec + 2.0)
    n = rng.standard_normal(t.size)
    # fernes Industriebrummen (Kuehlaggregate der Reefer-Container) + Wind
    x = lp(n, 120) * 0.6
    for f in (50.0, 100.0, 150.0):
        x += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * 0.05
    wind = bp(rng.standard_normal(t.size), 200, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * t) ** 2) * 0.35
    x += wind
    # Ketten/Stahl in der Ferne
    for _ in range(9):
        t0 = rng.uniform(0.5, sec)
        tt, on = shifted(t, t0)
        for j in range(rng.integers(2, 6)):
            tj, oj = shifted(t, t0 + j * rng.uniform(0.07, 0.15))
            f = rng.uniform(900, 2400)
            x += np.sin(2 * np.pi * f * tj) * np.exp(-tj / 0.12) * oj * 0.08
    # ferne Rangierlok/Schiffsdiesel: tiefes Pulsieren
    x += np.sin(2 * np.pi * 31 * t) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.31 * t)) * 0.12
    x = distant(x, 1500, 3.0, 2.5, 0.6, rng)
    y = make_loop(x, 2.0)
    save("hafen_amb_harbour", y, peak=0.6, loop=True)


if __name__ == "__main__":
    mg_shot()
    boat_engine()
    water_hull()
    horn()
    amb_harbour()
