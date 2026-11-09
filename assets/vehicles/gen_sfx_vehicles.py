"""Synthetisiert die veh_*/wx_* Sounds (teilweise geschichtet mit vorhandenen CC0-Projekt-Sounds).
Aufruf: python -I synth_veh.py <projekt_root>"""
import os
import subprocess
import sys
import numpy as np
from scipy import signal

SR = 44100
ROOT = sys.argv[1]
SFX = os.path.join(ROOT, "assets", "sfx")
TMP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tmp_wav")
os.makedirs(TMP, exist_ok=True)
rng = np.random.default_rng(1234)


def load(name):
    p = os.path.join(SFX, name)
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)


def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def noise(sec):
    return rng.standard_normal(int(sec * SR))


def lp(x, f, o=4):
    return signal.sosfilt(signal.butter(o, f, "low", fs=SR, output="sos"), x)


def hp(x, f, o=4):
    return signal.sosfilt(signal.butter(o, f, "high", fs=SR, output="sos"), x)


def bp(x, f1, f2, o=3):
    return signal.sosfilt(signal.butter(o, [f1, f2], "band", fs=SR, output="sos"), x)


def lp_loop(x, f, o=4):
    """Filtert zyklisch (fuer nahtlose Loops): dreifach aneinanderhaengen, Mitte nehmen."""
    n = len(x)
    y = signal.sosfiltfilt(signal.butter(o, f, "low", fs=SR, output="sos"), np.concatenate([x, x, x]))
    return y[n:2 * n]


def bp_loop(x, f1, f2, o=3):
    n = len(x)
    y = signal.sosfiltfilt(signal.butter(o, [f1, f2], "band", fs=SR, output="sos"), np.concatenate([x, x, x]))
    return y[n:2 * n]


def hp_loop(x, f, o=3):
    n = len(x)
    y = signal.sosfiltfilt(signal.butter(o, f, "high", fs=SR, output="sos"), np.concatenate([x, x, x]))
    return y[n:2 * n]


def pitch(x, factor):
    """Tonhoehe/Tempo gemeinsam (Resampling). factor<1 = tiefer/laenger."""
    n = int(len(x) / factor)
    return signal.resample(x, n)


def env_exp(sec, decay, attack=0.002):
    t = t_axis(sec)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / decay)


def place(dst, src, at, gain=1.0):
    i = int(at * SR)
    if i >= len(dst):
        return
    n = min(len(src), len(dst) - i)
    dst[i:i + n] += src[:n] * gain


def place_wrap(dst, src, at, gain=1.0):
    n = len(dst)
    i = int(at * SR) % n
    for k in range(len(src)):
        pass
    idx = (np.arange(len(src)) + i) % n
    np.add.at(dst, idx, src * gain)


def soft(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def norm(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def fade(x, fin=0.005, fout=0.05):
    x = x.copy()
    a = int(fin * SR)
    b = int(fout * SR)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def save(name, x, q=5):
    x = np.clip(x, -1, 1).astype(np.float32)
    wav = os.path.join(TMP, name + ".raw")
    x.tofile(wav)
    out = os.path.join(SFX, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", wav,
                    "-c:a", "libvorbis", "-q:a", str(q), out], check=True)
    print("ok", name, "%.2fs" % (len(x) / SR))


# ---------------------------------------------------------------- Hubschrauber
def heli_rotor():
    sec = 4.0
    rate = 17.0  # Blattdurchgaenge/s (68 pro Loop -> nahtlos)
    n = int(sec * SR)
    out = np.zeros(n)
    period = 1.0 / rate
    base = noise(sec)
    for k in range(int(sec * rate)):
        t0 = k * period
        a = 1.0 + 0.12 * rng.standard_normal()
        # "Wop": tiefer Druckpuls + gefiltertes Rauschen
        pl = int(0.05 * SR)
        tt = np.arange(pl) / SR
        thump = np.sin(2 * np.pi * 55 * tt) * np.exp(-tt / 0.012) * np.clip(tt / 0.002, 0, 1)
        place_wrap(out, thump * a * 1.0, t0)
        sl = int(0.04 * SR)
        swish = rng.standard_normal(sl) * np.hanning(sl)
        place_wrap(out, swish * a * 0.25, t0 + 0.004)
    swish_band = bp_loop(out, 60, 900)
    low = lp_loop(out, 160)
    # Grundrauschen (Luft), amplitudenmoduliert mit der Blattfrequenz
    t = t_axis(sec)
    am = 0.6 + 0.4 * np.maximum(0, np.cos(2 * np.pi * rate * t)) ** 3
    air = bp_loop(base, 150, 2200) * am * 0.15
    x = low * 1.4 + swish_band * 0.6 + air
    save("veh_heli_rotor", norm(soft(norm(x), 1.3), 0.85))


def heli_turbine():
    sec = 4.0
    t = t_axis(sec)
    # Toene mit ganzzahligen Zyklen pro Loop (nahtlos)
    def tone(f, a):
        f = round(f * sec) / sec
        return a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28))
    vib = 1.0 + 0.04 * np.sin(2 * np.pi * 0.5 * t)
    x = (tone(1720, 0.18) + tone(3440, 0.07) + tone(860, 0.06) + tone(5160, 0.03)) * vib
    hiss = bp_loop(noise(sec), 400, 7000) * 0.22
    roar = lp_loop(noise(sec), 300) * 0.6
    save("veh_heli_turbine", norm(x + hiss + roar, 0.7))


def heli_gun():
    sec = 0.45
    mg = load("enemy_mg.ogg")
    # ersten Schuss herausschneiden, tiefer pitchen
    seg = mg[: int(0.18 * SR)]
    seg = pitch(seg, 0.72)
    out = np.zeros(int(sec * SR))
    place(out, seg * np.hanning(len(seg) * 2)[len(seg):], 0.0, 0.8)
    t = t_axis(sec)
    boom = np.sin(2 * np.pi * (70 * np.exp(-t / 0.08) + 45) * t) * env_exp(sec, 0.05)
    crack = hp(noise(sec), 1500) * env_exp(sec, 0.006)
    body = bp(noise(sec), 200, 1500) * env_exp(sec, 0.04)
    x = out + boom * 0.9 + crack * 0.5 + body * 0.5
    save("veh_heli_gun", fade(norm(soft(norm(x), 2.0), 0.95), 0.0, 0.1))


def heli_gun_spin():
    sec = 0.9
    t = t_axis(sec)
    f = 60 + 420 * (t / sec) ** 1.4
    ph = 2 * np.pi * np.cumsum(f) / SR
    whir = (np.sin(ph) + 0.4 * np.sin(2 * ph) + 0.25 * signal.sawtooth(ph * 3)) * 0.3
    clicks = np.zeros_like(t)
    cyc = np.cumsum(f / 3) / SR
    idx = np.where(np.diff(np.floor(cyc)) > 0)[0]
    for i in idx:
        place(clicks, rng.standard_normal(80) * np.exp(-np.arange(80) / 12), i / SR, 0.4)
    x = whir + hp(clicks, 1500) + bp(noise(sec), 800, 4000) * 0.05
    env = np.clip(t / 0.05, 0, 1) * np.clip((sec - t) / 0.08, 0, 1)
    save("veh_heli_gun_spin", norm(x * env, 0.8))


def big_blast(sec, ex_names, pitch_f, metal=True, sub=40.0):
    out = np.zeros(int(sec * SR))
    for i, nm in enumerate(ex_names):
        e = pitch(load(nm), pitch_f * (1.0 - 0.06 * i))
        place(out, e, 0.03 * i, 0.8 / (1 + 0.3 * i))
    t = t_axis(sec)
    boom = np.sin(2 * np.pi * (sub * 2.2 * np.exp(-t / 0.15) + sub) * t) * env_exp(sec, 0.45, 0.004)
    rumble = lp(noise(sec), 120) * env_exp(sec, 1.4, 0.05) * 3.0
    out += boom * 0.9 + rumble * 0.6
    if metal:
        for k in range(10):
            m = load(["impact_metal.ogg", "impact_metal_2.ogg", "impact_metal_3.ogg"][k % 3])
            m = pitch(m, rng.uniform(0.45, 0.8))
            place(out, m, rng.uniform(0.15, sec * 0.6), rng.uniform(0.1, 0.3))
    return fade(norm(soft(norm(out), 1.6), 0.97), 0.0, 0.5)


def heli_crash():
    save("veh_heli_crash", big_blast(5.0, ["explosion.ogg", "explosion_3.ogg"], 0.85))


# ---------------------------------------------------------------- Panzer
def tank_engine():
    sec = 4.0
    t = t_axis(sec)
    fire = round(26.0 * sec) / sec  # Zuendfrequenz
    ph = 2 * np.pi * fire * t
    pulses = np.maximum(0, np.sin(ph)) ** 6
    jitter = 1.0 + 0.15 * lp_loop(noise(sec), 30) / 0.05
    x = pulses * jitter
    x = lp_loop(x - x.mean(), 420) * 1.2
    harm = sum(np.sin(ph * k + rng.uniform(0, 6)) / k for k in (1, 2, 3, 4)) * 0.25
    rumble = lp_loop(noise(sec), 110) * 2.5
    mech = bp_loop(noise(sec), 600, 2500) * (0.4 + 0.6 * pulses) * 0.08
    # Turbolader-Pfeifen leise
    whine = np.sin(2 * np.pi * (round(1150 * sec) / sec) * t) * 0.02
    save("veh_tank_engine", norm(soft(norm(x + harm + rumble + mech + whine), 1.4), 0.85))


def tank_tracks():
    sec = 2.0
    n = int(sec * SR)
    out = np.zeros(n)
    links = 18  # Kettenglieder-Anschlaege pro Loop
    for k in range(links):
        t0 = k * sec / links + rng.uniform(-0.01, 0.01)
        L = int(0.12 * SR)
        tt = np.arange(L) / SR
        clank = np.zeros(L)
        for _ in range(3):
            f = rng.uniform(700, 2600)
            clank += np.sin(2 * np.pi * f * tt + rng.uniform(0, 6)) * np.exp(-tt / rng.uniform(0.01, 0.04))
        clank += rng.standard_normal(L) * np.exp(-tt / 0.004) * 0.8
        place_wrap(out, clank, t0, rng.uniform(0.4, 1.0))
        # Rollen-Aufschlag tief
        thud = np.sin(2 * np.pi * 70 * tt) * np.exp(-tt / 0.03)
        place_wrap(out, thud, t0 + 0.02, 0.5)
    squeal_t = t_axis(sec)
    sq = np.sin(2 * np.pi * (round(1900 * sec) / sec) * squeal_t + 3 * np.sin(2 * np.pi * 1.5 * squeal_t)) * 0.04 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.5 * squeal_t))
    grind = bp_loop(noise(sec), 200, 1800) * 0.12
    rumble = lp_loop(noise(sec), 90) * 1.2
    x = hp_loop(out, 60) + sq + grind + rumble
    save("veh_tank_tracks", norm(x, 0.85))


def tank_turret():
    sec = 2.0
    t = t_axis(sec)
    def f(v):
        return round(v * sec) / sec
    whine = np.sin(2 * np.pi * f(240) * t) * 0.3 + np.sin(2 * np.pi * f(480) * t) * 0.12 + signal.sawtooth(2 * np.pi * f(120) * t) * 0.08
    gear = (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * f(31) * t))) * bp_loop(noise(sec), 900, 3000) * 0.1
    hum = lp_loop(noise(sec), 150) * 0.6
    save("veh_tank_turret", norm(whine + gear + hum, 0.75))


def tank_warn():
    sec = 0.55
    out = np.zeros(int(sec * SR))
    for i, (fr, at) in enumerate([(1850, 0.0), (2350, 0.16)]):
        L = int(0.12 * SR)
        tt = np.arange(L) / SR
        b = np.sin(2 * np.pi * fr * tt) * np.minimum(1, np.minimum(tt / 0.005, (0.12 - tt) / 0.02))
        place(out, b, at, 0.6)
    # leiser Laser-Zirp
    t = t_axis(sec)
    out += np.sin(2 * np.pi * (3000 + 2000 * t) * t) * np.exp(-t / 0.15) * 0.08
    save("veh_tank_warn", norm(out, 0.7))


def tank_cannon():
    sec = 3.5
    out = np.zeros(int(sec * SR))
    e = load("explosion_2.ogg")
    place(out, pitch(e, 1.1), 0.0, 0.7)
    t = t_axis(sec)
    crack = hp(noise(sec), 900) * env_exp(sec, 0.012, 0.0005)
    boom = np.sin(2 * np.pi * (110 * np.exp(-t / 0.06) + 38) * t) * env_exp(sec, 0.35, 0.002)
    blast = bp(noise(sec), 80, 1200) * env_exp(sec, 0.12)
    tail = lp(noise(sec), 400) * env_exp(sec, 1.1, 0.04) * 1.2  # Echo/Nachhall
    x = out + crack * 1.4 + boom * 1.3 + blast * 0.9 + tail * 0.5
    save("veh_tank_cannon", fade(norm(soft(norm(x), 2.2), 0.98), 0.0, 0.4))


def tank_explode():
    save("veh_tank_explode", big_blast(6.0, ["explosion_4.ogg", "explosion_2.ogg", "explosion.ogg"], 0.78, True, 34.0))


def metal_crash():
    sec = 2.2
    out = np.zeros(int(sec * SR))
    for k in range(6):
        m = load(["impact_metal.ogg", "impact_metal_2.ogg", "impact_metal_3.ogg"][k % 3])
        place(out, pitch(m, rng.uniform(0.35, 0.6)), rng.uniform(0, 0.25), rng.uniform(0.4, 0.9))
    t = t_axis(sec)
    thud = np.sin(2 * np.pi * (60 * np.exp(-t / 0.05) + 35) * t) * env_exp(sec, 0.25)
    rumble = lp(noise(sec), 200) * env_exp(sec, 0.5) * 2
    save("veh_metal_crash", fade(norm(soft(norm(out + thud + rumble * 0.4), 1.4), 0.9), 0.0, 0.3))


# ---------------------------------------------------------------- Jet / Bombe
def jet_loop():
    sec = 4.0
    n = int(sec * SR)
    w = noise(sec)
    # rosa-artiges Spektrum: Summe aus Baendern
    roar = lp_loop(w, 180) * 3.0 + bp_loop(w, 180, 900) * 1.2 + bp_loop(w, 900, 4000) * 0.45 + hp_loop(w, 4000) * 0.12
    # Nachbrenner-Knistern
    crack = np.zeros(n)
    for _ in range(int(sec * 140)):
        L = int(rng.uniform(0.001, 0.004) * SR)
        place_wrap(crack, rng.standard_normal(L) * np.hanning(L), rng.uniform(0, sec), rng.uniform(0.2, 1.0))
    crack = bp_loop(crack, 300, 3000) * 0.6
    t = t_axis(sec)
    whine = np.sin(2 * np.pi * (round(2100 * sec) / sec) * t) * 0.04
    x = roar + crack + whine
    save("veh_jet_loop", norm(soft(norm(x), 1.5), 0.9))


def jet_boom():
    sec = 3.0
    n = int(sec * SR)
    out = np.zeros(n)
    # N-Welle: zwei scharfe Druckstoesse
    for at, g in ((0.0, 1.0), (0.11, 0.85)):
        L = int(0.012 * SR)
        nw = np.linspace(1, -1, L)
        place(out, nw, at, g)
    out = lp(out, 2500, 2)
    t = t_axis(sec)
    boom = np.sin(2 * np.pi * (50 * np.exp(-t / 0.2) + 28) * t) * env_exp(sec, 0.5, 0.003)
    rumble = lp(noise(sec), 160) * env_exp(sec, 0.9, 0.03) * 2.0
    rattle = bp(noise(sec), 1500, 5000) * env_exp(sec, 0.08) * 0.3
    x = out * 1.6 + boom * 0.9 + rumble * 0.7 + rattle
    save("veh_jet_boom", fade(norm(soft(norm(x), 1.8), 0.98), 0.0, 0.5))


def bomb_whistle():
    sec = 4.2
    t = t_axis(sec)
    f = 1500 * np.exp(-t / 3.2) + 350
    ph = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.15 * np.sin(2 * ph)
    wind = bp(noise(sec), 600, 3000) * 0.3
    env = (0.15 + 0.85 * (t / sec) ** 2) * np.clip(t / 0.3, 0, 1)
    x = (tone * 0.6 + wind) * env
    x[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
    save("veh_bomb_whistle", norm(x, 0.8))


# ---------------------------------------------------------------- Sprengladung
def charge_beep():
    sec = 0.09
    t = t_axis(sec)
    b = np.sign(np.sin(2 * np.pi * 2900 * t)) * 0.5 + np.sin(2 * np.pi * 2900 * t) * 0.5
    b = lp(b, 6000, 2) * np.minimum(1, np.minimum(t / 0.003, (sec - t) / 0.01))
    save("veh_charge_beep", norm(b, 0.6))


def charge_plant():
    sec = 0.7
    out = np.zeros(int(sec * SR))
    for at in (0.0, 0.12, 0.38, 0.45):
        L = int(0.03 * SR)
        click = hp(rng.standard_normal(L), 1200) * np.exp(-np.arange(L) / (0.004 * SR))
        place(out, click, at, rng.uniform(0.5, 1.0))
    # Klebeband-Ratsch
    tape = bp(noise(0.2), 1500, 6000) * np.hanning(int(0.2 * SR)) * 0.4
    place(out, tape, 0.15)
    t = t_axis(sec)
    arm = np.sin(2 * np.pi * 1800 * t) * ((t > 0.55) & (t < 0.62)) * 0.3
    save("veh_charge_plant", norm(out + arm, 0.7))


# ---------------------------------------------------------------- Wetter
def wx_rain():
    sec = 12.0
    n = int(sec * SR)
    w = noise(sec)
    hiss = bp_loop(w, 700, 9000) * 0.5 + lp_loop(w, 400) * 0.5
    # langsame Intensitaetsschwankung, nahtlos (ganzzahlige Perioden)
    t = t_axis(sec)
    mod = 0.85 + 0.1 * np.sin(2 * np.pi * t / sec * 2) + 0.05 * np.sin(2 * np.pi * t / sec * 5)
    drops = np.zeros(n)
    for _ in range(int(sec * 260)):
        L = int(0.006 * SR)
        tt = np.arange(L) / SR
        f = rng.uniform(1500, 6000)
        d = np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.0015)
        place_wrap(drops, d, rng.uniform(0, sec), rng.uniform(0.05, 0.4))
    # gelegentliche Tropfen aus Rinnen (tiefer, lauter)
    for _ in range(int(sec * 3)):
        L = int(0.05 * SR)
        tt = np.arange(L) / SR
        f = rng.uniform(400, 900)
        d = np.sin(2 * np.pi * (f + 600 * np.exp(-tt / 0.01)) * tt) * np.exp(-tt / 0.012)
        place_wrap(drops, d, rng.uniform(0, sec), rng.uniform(0.3, 0.7))
    x = hiss * mod + drops * 0.7
    save("wx_rain", norm(x, 0.7), 4)


def thunder(close):
    sec = 9.0 if close else 10.0
    n = int(sec * SR)
    t = t_axis(sec)
    out = np.zeros(n)
    if close:
        crack = hp(noise(sec), 700) * env_exp(sec, 0.05, 0.0005)
        # zerrissener Knall: mehrere kurze Bursts
        for _ in range(6):
            place(out, hp(noise(0.15), 400) * env_exp(0.15, 0.03), rng.uniform(0, 0.35), rng.uniform(0.3, 0.8))
        out += crack * 1.5
        boom = np.sin(2 * np.pi * (60 * np.exp(-t / 0.3) + 30) * t) * env_exp(sec, 0.8, 0.01)
        out += boom * 0.8
    # Grollen: tiefpassgefiltertes Rauschen mit unregelmaessiger, rollender Huelle
    env = np.zeros(n)
    k = 0.3 if close else 0.0
    while k < sec * 0.8:
        dur = rng.uniform(0.5, 1.8)
        amp = rng.uniform(0.4, 1.0) * np.exp(-k / (3.5 if close else 4.5))
        seg = t_axis(dur)
        e = np.sin(np.pi * seg / dur) ** 2 * amp
        place(env, e, k)
        k += rng.uniform(0.25, 0.9)
    env = lp(env, 8, 2)
    env = np.maximum(env, 0) + 0.02 * np.exp(-t / 3.0)
    if not close:
        env *= np.clip(t / 0.4, 0, 1)
    rumble = lp(noise(sec), 140 if not close else 220) * 3.0 + bp(noise(sec), 140, 600) * 0.6
    out += rumble * env
    save("wx_thunder_close" if close else "wx_thunder", fade(norm(soft(norm(out), 1.5), 0.95), 0.0, 1.0), 4)


if __name__ == "__main__":
    only = set(sys.argv[2:])
    jobs = [heli_rotor, heli_turbine, heli_gun, heli_gun_spin, heli_crash, tank_engine, tank_tracks, tank_turret,
            tank_warn, tank_cannon, tank_explode, metal_crash, jet_loop, jet_boom, bomb_whistle, charge_beep,
            charge_plant, wx_rain, lambda: thunder(False), lambda: thunder(True)]
    for j in jobs:
        if not only or getattr(j, "__name__", "") in only:
            j()
