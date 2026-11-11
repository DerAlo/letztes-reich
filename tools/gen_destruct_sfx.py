"""Prozedurale Sounds fuer zerstoerbare Deckung (Runde 7, Welle 4, systeme-c).

Erzeugt assets/sfx/destruct_*.ogg:
  destruct_wood_hit       Kugel in Holz (trockener Knock + Splittern)
  destruct_wood_break     Brett/Kiste bricht (Krachen, Splittern, nachfallende Latten)
  destruct_glass          Scheibe zerspringt (heller Bruch + klirrende Scherben)
  destruct_brick_crumble  Ziegelfeld bricht heraus (Bröckeln, kleine Steine)
  destruct_collapse       Mauer/Stellung stuerzt ein (tiefes Poltern, Geroell, Staub)
  destruct_sand_burst     Sandsack platzt (dumpfer Schlag + rieselnder Sand)

Danach headless importieren:
  tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from gen_overwatch_sfx import SR, t_axis, bp, lp, hp, reverb_ir, convolve, scaled, fade, softlimit, save  # noqa: E402


def env_exp(t, t0, tau):
    e = np.exp(-np.clip(t - t0, 0, None) / tau)
    e[t < t0] = 0.0
    return e


def clicks(t, rng, n, t0, t1, dur_lo, dur_hi, lo, hi, amp_lo=0.3, amp_hi=1.0, decay=None):
    """n kurze bandpass-gefilterte Rauschbursts zwischen t0..t1 (Splitter, Scherben, Steinchen)."""
    out = np.zeros_like(t)
    for _ in range(n):
        s = rng.uniform(t0, t1)
        d = rng.uniform(dur_lo, dur_hi)
        i0 = int(s * SR)
        L = int(d * SR)
        if i0 + L >= t.size:
            continue
        b = rng.standard_normal(L) * np.exp(-np.linspace(0, 6, L))
        f = rng.uniform(lo, hi)
        b = bp(b, f * 0.7, min(f * 1.4, SR * 0.45))
        a = rng.uniform(amp_lo, amp_hi)
        if decay:
            a *= np.exp(-(s - t0) / decay)
        out[i0:i0 + L] += b * a / (np.max(np.abs(b)) + 1e-9)
    return out


def room(x, rng, sec=0.6, wet=0.25):
    ir = reverb_ir(sec, 0.5, 0.35, 0.2, rng)
    return x + scaled(convolve(x, ir, len(x)), x, wet)


def wood_hit():
    rng = np.random.default_rng(71)
    t = t_axis(0.35)
    knock = np.sin(2 * np.pi * 210 * t) * env_exp(t, 0, 0.018) + 0.6 * np.sin(2 * np.pi * 470 * t) * env_exp(t, 0, 0.01)
    crack = bp(rng.standard_normal(t.size), 1200, 6000) * env_exp(t, 0, 0.012)
    spl = clicks(t, rng, 7, 0.005, 0.08, 0.004, 0.015, 1500, 5000, 0.2, 0.6, decay=0.05)
    x = 0.9 * knock + 0.8 * crack + 0.5 * spl
    save("destruct_wood_hit", room(x, rng, 0.4, 0.15), 0.85)


def wood_break():
    rng = np.random.default_rng(72)
    t = t_axis(1.2)
    crack = bp(rng.standard_normal(t.size), 300, 4500) * (env_exp(t, 0, 0.05) + 0.6 * env_exp(t, 0.03, 0.08))
    body = lp(rng.standard_normal(t.size), 400) * env_exp(t, 0, 0.12) * 1.5
    spl = clicks(t, rng, 28, 0.0, 0.35, 0.005, 0.03, 900, 5500, 0.2, 1.0, decay=0.2)
    clatter = clicks(t, rng, 9, 0.25, 0.95, 0.02, 0.06, 250, 1200, 0.2, 0.7, decay=0.4)
    x = 1.0 * crack + 0.8 * body + 0.6 * spl + 0.5 * clatter
    save("destruct_wood_break", room(softlimit(x, 1.5), rng, 0.7, 0.25), 0.9)


def glass():
    rng = np.random.default_rng(73)
    t = t_axis(1.6)
    smash = hp(rng.standard_normal(t.size), 2500) * env_exp(t, 0, 0.04)
    ring = np.zeros_like(t)
    for f in rng.uniform(2800, 7500, 10):
        ring += np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) * env_exp(t, rng.uniform(0, 0.02), rng.uniform(0.05, 0.25)) * rng.uniform(0.1, 0.3)
    tinkle = clicks(t, rng, 45, 0.02, 1.2, 0.003, 0.02, 3000, 9000, 0.1, 0.8, decay=0.45)
    x = 1.0 * smash + 0.6 * ring + 0.7 * tinkle
    save("destruct_glass", room(x, rng, 0.8, 0.2), 0.9)


def brick_crumble():
    rng = np.random.default_rng(74)
    t = t_axis(1.3)
    thud = lp(rng.standard_normal(t.size), 220) * env_exp(t, 0, 0.09) * 2.0
    crack = bp(rng.standard_normal(t.size), 600, 3500) * env_exp(t, 0, 0.03)
    stones = clicks(t, rng, 30, 0.02, 1.0, 0.006, 0.03, 700, 3500, 0.15, 0.9, decay=0.35)
    grit = bp(rng.standard_normal(t.size), 1500, 6000) * env_exp(t, 0.05, 0.4) * 0.12
    x = 1.0 * thud + 0.8 * crack + 0.6 * stones + grit
    save("destruct_brick_crumble", room(softlimit(x, 1.4), rng, 0.8, 0.3), 0.9)


def collapse():
    rng = np.random.default_rng(75)
    t = t_axis(3.2)
    rumble = lp(rng.standard_normal(t.size), 120, 4) * (env_exp(t, 0, 0.6) + 0.5 * env_exp(t, 0.25, 0.9)) * 3.0
    boom = lp(rng.standard_normal(t.size), 300) * env_exp(t, 0, 0.15) * 2.0
    crack = bp(rng.standard_normal(t.size), 500, 4000) * (env_exp(t, 0, 0.05) + 0.5 * env_exp(t, 0.12, 0.06))
    chunks = clicks(t, rng, 26, 0.05, 1.8, 0.03, 0.1, 150, 900, 0.3, 1.0, decay=0.9)
    stones = clicks(t, rng, 60, 0.1, 2.6, 0.006, 0.03, 800, 4000, 0.1, 0.6, decay=1.0)
    hiss = bp(rng.standard_normal(t.size), 2000, 8000) * env_exp(t, 0.2, 1.0) * 0.08
    x = rumble + boom + 0.8 * crack + 0.7 * chunks + 0.5 * stones + hiss
    x = fade(x, 0.0, 0.4)
    save("destruct_collapse", room(softlimit(x, 1.6), rng, 1.4, 0.35), 0.92)


def sand_burst():
    rng = np.random.default_rng(76)
    t = t_axis(1.1)
    thump = lp(rng.standard_normal(t.size), 180) * env_exp(t, 0, 0.06) * 2.0
    rip = bp(rng.standard_normal(t.size), 900, 3500) * env_exp(t, 0, 0.025) * 0.6
    pour = bp(rng.standard_normal(t.size), 1800, 7000) * env_exp(t, 0.03, 0.35) * 0.35
    pour *= 1.0 + 0.5 * bp(rng.standard_normal(t.size), 8, 40) * 4
    x = thump + rip + pour
    save("destruct_sand_burst", room(x, rng, 0.5, 0.15), 0.85)


if __name__ == "__main__":
    wood_hit()
    wood_break()
    glass()
    brick_crumble()
    collapse()
    sand_burst()
