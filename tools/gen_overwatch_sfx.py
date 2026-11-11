"""Synthetische Sounds für die Scharfschützen-Mission "Overwatch" (eigene Arbeit, CC0) -> assets/sfx/*.ogg

  python tools/gen_overwatch_sfx.py

Alle Dateien beginnen mit "overwatch_", Varianten mit _2/_3. Statt einfacher Pieptöne werden
Rauschbursts, gefilterte Transienten, Resonanzen und Faltung mit synthetischen Hall-/Echo-
Impulsantworten geschichtet; Varianten unterscheiden sich durch eigene Zufalls-Seeds.

  dmr_fire(_2,_3)      7.62x51-DMR-Schuss aus Schützensicht: Überschallknall, tiefer Mündungsknall,
                       Verschluss-Klacken, langes rollendes Echo an Stahl-/Betonbauten (~3.5 s)
  impact_flesh(_2)     dumpfer Fleischtreffer aus ~150 m
  impact_metal(_2)     Querschläger/Ping auf Stahl aus der Ferne
  scope_zoom           zwei Rastklicks des Vergrößerungsrings
  breath_in/out        Luft anhalten / gepresst ausatmen
  heartbeat            ein langsamer, tiefer Herzschlag (lub-dub)
  mortar_launch        ferner Mörserabschuss (~400 m)
  mortar_whistle       einfliegende Mörsergranate, fallende Tonhöhe, bricht abrupt ab
  steam_loop           Dampfventil-Zischen, nahtlos loopbar (6 s)
  amb_works            Stahlwerk im Morgennebel, nahtlos loopbar (20 s)
  glint                sehr leises, hohes Schimmern (feindliches Zielfernrohr blitzt)
  door_slam            schwere Panzerfahrzeug-Tür aus ~150 m
"""
import os
import subprocess
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt, fftconvolve

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def _sos(kind, f, order):
    nyq = SR / 2
    if kind == "band":
        f = [max(f[0], 5.0) / nyq, min(f[1], nyq * 0.98) / nyq]
    else:
        f = min(f, nyq * 0.98) / nyq
    return butter(order, f, btype=kind, output="sos")


def bp(x, lo, hi, order=2):
    return sosfilt(_sos("band", [lo, hi], order), x)


def lp(x, f, order=2):
    return sosfilt(_sos("low", f, order), x)


def hp(x, f, order=2):
    return sosfilt(_sos("high", f, order), x)


def shifted(t, t0):
    """Zeitachse ab t0 (davor 0) und Einschaltmaske."""
    tt = t - t0
    on = (tt >= 0).astype(float)
    return np.clip(tt, 0, None), on


def sweep(f_inst):
    """Sinus mit momentaner Frequenz f_inst (Array)."""
    return np.sin(2 * np.pi * np.cumsum(f_inst) / SR)


def reverb_ir(sec, rt_low, rt_mid, rt_high, rng, onset=0.004):
    """Synthetische Impulsantwort: frequenzabhängig abklingendes Rauschen (Höhen sterben zuerst)."""
    t = t_axis(sec)
    n = rng.standard_normal(t.size)
    ir = (lp(n, 450) * np.exp(-6.9 * t / rt_low)
          + bp(n, 450, 2500) * np.exp(-6.9 * t / rt_mid)
          + hp(n, 2500) * np.exp(-6.9 * t / rt_high) * 0.6)
    ir *= 1 - np.exp(-t / onset)
    return ir / (np.sqrt(np.sum(ir ** 2)) + 1e-9)


def convolve(x, ir, length=None):
    y = fftconvolve(x, ir)
    return y[: (length or x.size)]


def scaled(x, ref, rel):
    """x so skalieren, dass max|x| = rel * max|ref|."""
    return x / (np.max(np.abs(x)) + 1e-12) * rel * np.max(np.abs(ref))


def distant(x, cutoff, rev_sec, rt, wet, rng, slap=None):
    """Entfernung: Luftdämpfung (Tiefpass), Raum-/Außenhall, optional Rückwurf (Zeit, Pegel)."""
    dry = lp(lp(x, cutoff), cutoff * 1.4)
    ir = reverb_ir(rev_sec, rt, rt * 0.6, rt * 0.25, rng, onset=0.012)
    y = dry + scaled(convolve(dry, ir), dry, wet)
    if slap:
        d, g = slap
        k = int(SR * d)
        e = np.zeros_like(y)
        e[k:] = lp(y, cutoff * 0.6)[: y.size - k]
        y = y + e * g
    return y


def fade(x, fin=0.0, fout=0.0):
    x = x.copy()
    if fin > 0:
        k = int(SR * fin)
        x[:k] *= np.linspace(0, 1, k)
    if fout > 0:
        k = int(SR * fout)
        x[-k:] *= np.linspace(1, 0, k) ** 2
    return x


def softlimit(x, drive):
    x = x / (np.max(np.abs(x)) + 1e-12)
    return np.tanh(drive * x) / np.tanh(drive)


def make_loop(x, xf_sec):
    """Nahtloser Loop: Ende per Equal-Power-Blende in den Anfang überführen."""
    k = int(SR * xf_sec)
    a = np.linspace(0, np.pi / 2, k)
    head = x[:k] * np.sin(a) + x[-k:] * np.cos(a)
    y = np.concatenate([head, x[k:-k]])
    return y - np.mean(y)


def save(name, x, peak=0.9, loop=False):
    x = np.asarray(x, dtype=float)
    if not loop:
        x = hp(x, 20)                   # DC/Infraschall raus (kausal, kein Klick am Anfang)
        x = fade(x, 0.0, 0.01)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    pcm = np.clip(np.round(x * 32767), -32767, 32767).astype(np.int16)
    wav = os.path.join(OUT, name + ".wav")
    wavfile.write(wav, SR, pcm)
    # Spiel laedt 3D-Sounds nur als .ogg (world_audio.gd) -> per ffmpeg umwandeln, wav entfernen
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "6",
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(wav)
    f = pcm / 32767.0
    print(f"wrote {name:28s} {f.size / SR:6.2f} s  peak {np.max(np.abs(f)):.3f}  "
          f"rms {np.sqrt(np.mean(f ** 2)):.4f}  dc {np.mean(f):+.5f}"
          + (f"  loop-seam {abs(f[0] - f[-1]):.4f}" if loop else ""))


# ---------------------------------------------------------------- Schuss

def dmr_fire(name, seed):
    rng = np.random.default_rng(seed)
    T = 3.6
    t = t_axis(T)
    N = t.size
    n = rng.standard_normal(N)

    # Überschallknall: N-Welle (~0.6 ms) + sehr kurzes, helles Rauschen
    crack = np.zeros(N)
    nd = int(SR * rng.uniform(0.0005, 0.0007))
    crack[:nd] = 1 - 2 * np.arange(nd) / nd
    crack = crack * 1.0 + hp(n, 3000) * np.exp(-t / 0.0014) * 0.9
    crack = lp(crack, 14000)

    # Mündungsknall: breitbandiger Druckstoß + tiefer Körper + Thump mit Tonhöhenabfall
    att = 1 - np.exp(-t / 0.0006)
    blast = lp(n, 2400) * att * np.exp(-t / 0.020) * 1.3
    body = bp(rng.standard_normal(N), 70, 450) * att * np.exp(-t / 0.055) * 2.2
    f0 = rng.uniform(44, 52)
    thump = sweep(f0 + 85 * np.exp(-t / 0.012)) * (1 - np.exp(-t / 0.0025)) * np.exp(-t / 0.10) * 1.1
    lowmid = sweep(rng.uniform(115, 135) + 60 * np.exp(-t / 0.008)) * att * np.exp(-t / 0.035) * 0.5
    muzzle = blast + body + thump + lowmid
    # Bodenreflexion direkt nach dem Knall (Schütze liegt)
    k = int(SR * rng.uniform(0.004, 0.007))
    refl = np.zeros(N)
    refl[k:] = lp(muzzle, 2500)[: N - k] * 0.45
    muzzle = muzzle + refl
    muzzle = softlimit(muzzle, 2.2) * np.max(np.abs(muzzle))  # Punch/Kompression

    # Mechanik: Verschluss zurück (~40 ms) und vor (~75 ms)
    mech = np.zeros(N)
    for t0, a in [(0.040 + rng.uniform(-0.004, 0.004), 1.0), (0.078 + rng.uniform(-0.006, 0.006), 0.6)]:
        tt, on = shifted(t, t0)
        click = bp(rng.standard_normal(N), 1500, 7500) * np.exp(-tt / 0.0035)
        ring = sum(np.sin(2 * np.pi * f * rng.uniform(0.97, 1.03) * tt) * w
                   for f, w in [(1850, 1.0), (3250, 0.7), (4700, 0.45), (920, 0.5)])
        mech += on * (click * 0.9 + ring * np.exp(-tt / 0.022) * 0.25) * a
    mech = scaled(mech, muzzle, 0.13)

    dry = crack * 0.75 * np.max(np.abs(muzzle)) + muzzle

    # Echoquelle: Knall ohne Mechanik, leicht abgedunkelt
    src = lp(muzzle + crack * 0.25 * np.max(np.abs(muzzle)), 5000)

    # diskrete Rückwürfe an Stahl-/Betonstrukturen (Hallen, Hochöfen, Silos)
    echoes = np.zeros(N)
    base_t = [0.27, 0.41, 0.58, 0.77, 0.98, 1.19, 1.52, 1.95]
    base_g = [0.40, 0.27, 0.33, 0.21, 0.17, 0.12, 0.07, 0.045]
    for i, (et, eg) in enumerate(zip(base_t, base_g)):
        et *= rng.uniform(0.92, 1.08)
        eg *= rng.uniform(0.8, 1.2)
        cut = 3800 * (0.78 ** i)
        e = lp(lp(src, cut), cut * 1.3)
        smear = reverb_ir(rng.uniform(0.05, 0.12), 0.08, 0.06, 0.03, rng, onset=0.002)
        smear[0] += 1.2                                   # harter Anteil + Flatterecho-Schmierung
        e = convolve(e, smear)
        e = e / (np.max(np.abs(e)) + 1e-12) * np.max(np.abs(src)) * eg
        k = int(SR * et)
        echoes[k:] += e[: N - k]

    # diffuser, rollender Nachhall (langsam aufbauend, tief, ~3 s)
    ir = reverb_ir(3.6, rng.uniform(6.0, 7.0), 3.2, 0.8, rng, onset=0.12)
    tail = convolve(lp(src, 3500), ir)
    roll = lp(rng.standard_normal(N), 3.5)
    roll = 1 + 0.45 * roll / (np.max(np.abs(roll)) + 1e-12)
    tail = scaled(tail * roll, dry, 0.2)

    x = dry + mech + echoes + tail
    x = fade(x, 0, 0.35)
    save(name, softlimit(x, 1.6), 0.95)


# ---------------------------------------------------------------- Treffer

def impact_flesh(name, seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.7)
    N = t.size
    n = rng.standard_normal(N)
    att = 1 - np.exp(-t / 0.0008)
    slap = bp(n, 350, 1600) * att * np.exp(-t / 0.006) * 0.8
    meat = lp(rng.standard_normal(N), 700) * att * np.exp(-t / 0.018) * 1.6
    thud = sweep(rng.uniform(95, 125) + 60 * np.exp(-t / 0.01)) * att * np.exp(-t / 0.045) * 0.9
    squish = bp(rng.standard_normal(N), 600, 1400) * np.exp(-shifted(t, 0.012)[0] / 0.02) * shifted(t, 0.012)[1] * 0.25
    x = slap + meat + thud + squish
    x = distant(x, 1800, 0.6, 0.45, 0.35, rng, slap=(rng.uniform(0.09, 0.14), 0.2))
    save(name, x, 0.8)


def impact_metal(name, seed):
    rng = np.random.default_rng(seed)
    t = t_axis(1.1)
    N = t.size
    tick = hp(rng.standard_normal(N), 2000) * np.exp(-t / 0.0015)
    partials = [(2350, 1.0, 0.09), (3790, 0.75, 0.07), (5210, 0.5, 0.05), (6980, 0.3, 0.035), (1420, 0.35, 0.12)]
    s = rng.uniform(0.9, 1.12)
    ping = sum(np.sin(2 * np.pi * f * s * t + rng.uniform(0, 6.28)) * a * np.exp(-t / d)
               for f, a, d in partials)
    # leises Querschläger-Sirren, fallend
    tt, on = shifted(t, 0.01)
    whine_f = rng.uniform(2800, 3600) * (1 - 0.45 * np.clip(tt / 0.35, 0, 1))
    whine = sweep(whine_f) * on * np.exp(-tt / 0.12) * (1 - np.exp(-tt / 0.02)) * 0.18
    x = tick * 0.8 + ping * 0.6 + whine
    x = distant(x, 6500, 0.9, 0.7, 0.45, rng, slap=(rng.uniform(0.18, 0.28), 0.25))
    save(name, x, 0.75)


# ---------------------------------------------------------------- Zielfernrohr / Körper

def scope_zoom():
    rng = np.random.default_rng(31)
    t = t_axis(0.28)
    N = t.size
    x = np.zeros(N)
    for t0, a, s in [(0.005, 1.0, 1.0), (0.085, 0.85, 1.04)]:
        tt, on = shifted(t, t0)
        snap = hp(rng.standard_normal(N), 4000) * np.exp(-tt / 0.0007)
        ring = sum(np.sin(2 * np.pi * f * s * tt) * w * np.exp(-tt / d)
                   for f, w, d in [(3150, 1.0, 0.006), (5480, 0.7, 0.004), (8100, 0.4, 0.003)])
        body = bp(rng.standard_normal(N), 700, 1800) * np.exp(-tt / 0.004) * 0.5
        x += on * (snap * 1.2 + ring * 0.6 + body) * a
    # winziger Gehäuseraum
    ir = reverb_ir(0.04, 0.03, 0.02, 0.01, rng, onset=0.0005)
    x = x + scaled(convolve(x, ir), x, 0.15)
    save("overwatch_scope_zoom", x, 0.7)


def breath(name, sec, inhale, seed):
    rng = np.random.default_rng(seed)
    t = t_axis(sec)
    N = t.size
    n = rng.standard_normal(N)
    u = t / sec
    if inhale:
        env = np.sin(np.pi * np.clip(u / 0.85, 0, 1) * 0.5) ** 1.5 * (1 - np.clip((u - 0.82) / 0.18, 0, 1)) ** 2
        air = bp(n, 900, 4500) * 0.8 + bp(n, 2200, 3200, 1) * 0.6 + bp(n, 300, 900) * 0.25
    else:
        env = (1 - np.exp(-u / 0.06)) * np.exp(-u * 2.6) * (1 - u ** 4)
        air = bp(n, 500, 3200) * 0.9 + bp(n, 1100, 1700, 1) * 0.5 + lp(n, 400) * 0.35
        # leicht gepresst: unruhige Amplitude + Hauch von Stimme (Stimmlippenreibung)
        jitter = 1 + 0.18 * lp(rng.standard_normal(N), 12) / 0.05
        env = env * np.clip(jitter, 0.6, 1.4)
        f0 = 105 * (1 - 0.12 * u)
        voice = bp(np.sign(sweep(f0)) * 0.5 + 0.0, 300, 1500) * 0.035 * np.exp(-u * 4)
        air = air + voice
    x = air * env
    x = x + scaled(convolve(x, reverb_ir(0.15, 0.12, 0.08, 0.04, rng)), x, 0.1)
    save(name, fade(x, 0.02, 0.05), 0.5)


def heartbeat():
    rng = np.random.default_rng(41)
    t = t_axis(0.85)
    N = t.size
    x = np.zeros(N)
    for t0, a, f0, d in [(0.02, 1.0, 50, 0.055), (0.30, 0.7, 58, 0.045)]:
        tt, on = shifted(t, t0)
        env = (1 - np.exp(-tt / 0.008)) * np.exp(-tt / d)
        tone = sweep(np.where(on > 0, f0 * (1 + 0.5 * np.exp(-tt / 0.02)) - 15 * (tt / 0.1).clip(0, 1), 0))
        thud = lp(rng.standard_normal(N), 140, 4) * 2.5
        x += on * (tone + thud * 0.6) * env * a
    x = lp(x, 180)
    save("overwatch_heartbeat", x, 0.7)


# ---------------------------------------------------------------- Mörser

def mortar_launch():
    rng = np.random.default_rng(51)
    t = t_axis(2.4)
    N = t.size
    att = 1 - np.exp(-t / 0.004)
    thoomp = sweep(62 + 45 * np.exp(-t / 0.02)) * att * np.exp(-t / 0.11) * 1.4
    puff = lp(rng.standard_normal(N), 450, 4) * att * np.exp(-t / 0.05) * 2.0
    tube = sweep(165 + 20 * np.exp(-t / 0.03)) * att * np.exp(-t / 0.07) * 0.35  # Rohr-Resonanz
    x = thoomp + puff + tube
    x = distant(x, 650, 2.2, 1.8, 0.7, rng, slap=(0.62, 0.3))
    save("overwatch_mortar_launch", fade(x, 0, 0.4), 0.8)


def mortar_whistle():
    rng = np.random.default_rng(61)
    T = 2.2
    t = t_axis(T)
    N = t.size
    u = t / T
    f = 1550 * (1 - 0.48 * u ** 1.25) * (1 + 0.006 * np.sin(2 * np.pi * 5.5 * t))
    tone = sweep(f) + 0.25 * sweep(2 * f) + 0.08 * sweep(3 * f)
    # schmalbandiges Rauschen um den Ton (Luftströmung an der Granate)
    nb = lp(rng.standard_normal(N), 120) * 6
    breathy = nb * sweep(f * 1.002)
    rush = bp(rng.standard_normal(N), 800, 5000) * u ** 3 * 0.35
    env = (0.08 + 0.92 * u ** 2.2) * (1 + 0.1 * lp(rng.standard_normal(N), 6) * 10)
    x = (tone * 0.7 + breathy * 0.5) * env + rush
    x = lp(x, 7000)
    k = int(SR * 0.006)
    x[-k:] *= np.linspace(1, 0, k)          # abrupter Abbruch (Einschlag folgt separat)
    save("overwatch_mortar_whistle", x, 0.8)


# ---------------------------------------------------------------- Loops

def steam_loop():
    rng = np.random.default_rng(71)
    xf = 0.6
    t = t_axis(6.0 + xf)
    N = t.size
    mod = lp(rng.standard_normal(N), 2.5)
    mod = 1 + 0.25 * mod / np.max(np.abs(mod))
    mod2 = lp(rng.standard_normal(N), 9)
    mod2 = 1 + 0.2 * mod2 / np.max(np.abs(mod2))
    hiss = bp(rng.standard_normal(N), 2200, 11000) * mod * 1.0
    jet = bp(rng.standard_normal(N), 700, 2600) * mod2 * 0.55
    turb = lp(rng.standard_normal(N), 180, 4) * mod2 * 2.2
    rumble = lp(rng.standard_normal(N), 60, 4) * 3.0
    x = hiss + jet + turb + rumble
    x = x + scaled(convolve(x, reverb_ir(0.5, 0.6, 0.4, 0.2, rng)), x, 0.3)
    x = hp(x, 25)
    x = x[int(SR * 0.3):]                    # Filter-Einschwingen verwerfen
    save("overwatch_steam_loop", make_loop(x, xf - 0.3), 0.55, loop=True)


def metal_clank(N, t0, rng, scale=1.0):
    t = np.arange(N) / SR
    tt, on = shifted(t, t0)
    hit = bp(rng.standard_normal(N), 300, 2500) * np.exp(-tt / 0.006)
    s = rng.uniform(0.7, 1.4) * scale
    ring = sum(np.sin(2 * np.pi * f * s * tt + rng.uniform(0, 6.28)) * a * np.exp(-tt / d)
               for f, a, d in [(310, 1.0, 0.35), (523, 0.7, 0.25), (871, 0.5, 0.18), (1340, 0.3, 0.12)])
    return on * (hit * 0.8 + ring * 0.5)


def amb_works():
    rng = np.random.default_rng(81)
    L, xf = 20.0, 2.0
    pre = 0.5
    t = t_axis(L + xf + pre)
    N = t.size

    # Industriebrummen: Netzbrumm-Harmonische + Gebläse, langsam schwankend
    drift = lp(rng.standard_normal(N), 0.3)
    drift = 1 + 0.3 * drift / np.max(np.abs(drift))
    hum = sum(np.sin(2 * np.pi * f * (1 + 0.002 * drift) * t) * a
              for f, a in [(49.5, 1.0), (99, 0.55), (148.5, 0.3), (198, 0.15), (73, 0.25)])
    hum = lp(hum, 300) * drift * 0.25
    rumble = lp(rng.standard_normal(N), 90, 4) * 1.6
    blower = bp(rng.standard_normal(N), 150, 600) * 0.12 * drift

    # Wind
    w = lp(rng.standard_normal(N), 0.15)
    w = 0.6 + 0.4 * (w - w.min()) / (w.max() - w.min())
    wind = bp(rng.standard_normal(N), 250, 1300) * w * 0.22 + bp(rng.standard_normal(N), 1500, 4000) * w ** 2 * 0.04

    # ferne Metallschläge (sehr verhallt)
    clanks = np.zeros(N)
    for t0, a in [(1.8, 1.0), (5.6, 0.6), (6.1, 0.4), (9.4, 0.8), (14.2, 0.7), (17.3, 0.5), (19.0, 0.9)]:
        clanks += metal_clank(N, t0 + rng.uniform(-0.2, 0.2), rng) * a
    clanks = lp(clanks, 1500)
    clanks = convolve(clanks, reverb_ir(3.0, 2.8, 2.0, 0.8, rng, onset=0.03)) * 0.5 + clanks * 0.12

    # einmal ein sehr ferner Zughorn-Akkord
    th, on = shifted(t, 10.5)
    hl = 2.6
    henv = on * np.clip(th / 0.25, 0, 1) * np.clip((hl - th) / 0.5, 0, 1) * (th < hl)
    horn = np.zeros(N)
    for f in (311.1, 370.0, 466.2):
        ph = 2 * np.pi * f * th
        horn += sum(np.sin(k * ph) / k for k in range(1, 7))
    horn = lp(horn * henv, 900)
    horn = convolve(horn, reverb_ir(3.5, 3.0, 2.2, 0.8, rng, onset=0.08)) * 0.6 + horn * 0.15

    # vereinzelte Vögel
    birds = np.zeros(N)
    for t0 in (3.2, 3.45, 12.8, 16.4, 16.62, 16.85):
        tt, on = shifted(t, t0 + rng.uniform(-0.05, 0.05))
        d = rng.uniform(0.08, 0.14)
        f0 = rng.uniform(3200, 4200)
        fi = f0 * (1 + 0.35 * np.sin(np.pi * np.clip(tt / d, 0, 1))) + 400 * np.sin(2 * np.pi * 28 * tt)
        birds += on * (tt < d) * sweep(np.where(on > 0, fi, 0)) * np.sin(np.pi * np.clip(tt / d, 0, 1)) ** 2
    birds = convolve(lp(birds, 5000), reverb_ir(1.5, 1.2, 1.0, 0.6, rng)) * 0.6 + birds * 0.1

    def norm(v):
        return v / (np.max(np.abs(v)) + 1e-12)

    x = (norm(hum) * 0.35 + norm(rumble) * 0.45 + norm(blower) * 0.12 + norm(wind) * 0.35
         + norm(clanks) * 0.4 + norm(horn) * 0.22 + norm(birds) * 0.07)
    x = hp(x, 25)
    x = x[int(SR * pre):]
    save("overwatch_amb_works", make_loop(x, xf), 0.5, loop=True)


# ---------------------------------------------------------------- Kleinkram

def glint():
    rng = np.random.default_rng(91)
    t = t_axis(0.7)
    N = t.size
    x = np.zeros(N)
    for f, a, d in [(6400, 1.0, 0.16), (9050, 0.6, 0.12), (11800, 0.35, 0.08)]:
        # verstimmte Paare -> Schwebung/Schimmer
        x += a * np.exp(-t / d) * (np.sin(2 * np.pi * f * t) + 0.7 * np.sin(2 * np.pi * (f + rng.uniform(5, 11)) * t))
    x *= 1 - np.exp(-t / 0.002)
    x += hp(rng.standard_normal(N), 7000) * np.exp(-t / 0.002) * 0.4
    x = x + scaled(convolve(x, reverb_ir(0.6, 0.5, 0.5, 0.4, rng)), x, 0.3)
    save("overwatch_glint", fade(x, 0, 0.1), 0.35)


def door_slam():
    rng = np.random.default_rng(101)
    t = t_axis(1.8)
    N = t.size
    att = 1 - np.exp(-t / 0.0015)
    thud = sweep(68 + 30 * np.exp(-t / 0.015)) * att * np.exp(-t / 0.12) * 1.3
    knock = lp(rng.standard_normal(N), 500) * att * np.exp(-t / 0.03) * 1.5
    panel = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * a * np.exp(-t / d)
                for f, a, d in [(182, 1.0, 0.30), (307, 0.8, 0.22), (519, 0.55, 0.16), (744, 0.35, 0.11), (1130, 0.2, 0.07)])
    tt, on = shifted(t, 0.018)
    latch = on * (bp(rng.standard_normal(N), 1200, 4000) * np.exp(-tt / 0.004)
                  + np.sin(2 * np.pi * 2300 * tt) * np.exp(-tt / 0.02) * 0.3)
    x = thud + knock + panel * att * 0.45 + latch * 0.35
    x = distant(x, 1500, 1.4, 1.1, 0.55, rng, slap=(0.31, 0.3))
    save("overwatch_door_slam", fade(x, 0, 0.3), 0.8)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    dmr_fire("overwatch_dmr_fire", 1001)
    dmr_fire("overwatch_dmr_fire_2", 1002)
    dmr_fire("overwatch_dmr_fire_3", 1003)
    impact_flesh("overwatch_impact_flesh", 2001)
    impact_flesh("overwatch_impact_flesh_2", 2002)
    impact_metal("overwatch_impact_metal", 3001)
    impact_metal("overwatch_impact_metal_2", 3002)
    scope_zoom()
    breath("overwatch_breath_in", 0.6, True, 4001)
    breath("overwatch_breath_out", 0.9, False, 4002)
    heartbeat()
    mortar_launch()
    mortar_whistle()
    steam_loop()
    amb_works()
    glint()
    door_slam()
