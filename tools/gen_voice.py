#!/usr/bin/env python3
"""Vertont alle Sprechzeilen des Spiels -> assets/voice/<id>.ogg (Ogg Vorbis, mono, 32 kHz).

Laeuft in der Chatterbox-venv (tools/chatterbox/venv, siehe Einrichtung unten):

  tools/chatterbox/venv/Scripts/python tools/gen_voice.py             # fehlende/geaenderte Zeilen erzeugen
  tools/chatterbox/venv/Scripts/python tools/gen_voice.py --force     # alles neu (Rohaufnahmen aus dem Cache)
  tools/chatterbox/venv/Scripts/python tools/gen_voice.py --retake    # auch die TTS-Rohaufnahmen neu
  ... --only <id|figur>[,...]   nur bestimmte Zeilen/Figuren        ... --samples   Proben -> tools/voice_samples/
  ... --intro                   Webers Intro-Funksprueche -> assets/sfx/intro_vo*.wav (gleiche Stimme/Filter)
  ... --report                  nur Laengen-/Timing-Bericht

Ablauf: tools/voice_lines.py sammelt die Zeilen (ID = sha1(speaker|text)[:12], wie StoryUI.voice_id()).
Je Zeile mehrere Takes mit Chatterbox Multilingual (Resemble AI, MIT) per Voice-Cloning aus freien Referenzen
(tools/voice_refs/, siehe make_refs.py und assets/CREDITS.md). Jeder Take wird mit Whisper zurueckgehoert;
gewaehlt wird der verstaendlichste (WER), bei Gleichstand der, der am besten ins Zeitfenster passt.
Danach Kanal-Effekt (Funk / Funk leicht / Lautsprecher / Buehne / nah) und Lautheits-Normierung (pyloudnorm).

Einrichtung (einmalig, ~6 GB):
  py -3.11 -m venv tools/chatterbox/venv
  tools/chatterbox/venv/Scripts/python -m pip install torch==2.6.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu124
  tools/chatterbox/venv/Scripts/python -m pip install chatterbox-tts num2words
Modelle laden beim ersten Lauf von HuggingFace (ResembleAI/chatterbox, openai/whisper-large-v3-turbo) nach
tools/chatterbox/hf/.
"""
import argparse
import hashlib
import json
import os
import re
import sys

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
os.environ.setdefault("HF_HOME", os.path.join(HERE, "chatterbox", "hf"))
os.environ.setdefault("PYTHONIOENCODING", "utf-8")
sys.path.insert(0, HERE)
import voice_lines  # noqa: E402

OUT = os.path.join(ROOT, "assets", "voice")
SFX = os.path.join(ROOT, "assets", "sfx")
REFS = os.path.join(HERE, "voice_refs")
CACHE = os.path.join(HERE, ".voice_cache")
SAMPLES = os.path.join(HERE, "voice_samples")
SR = 32000
TAIL = 0.3          # = StoryUI.VOICE_TAIL
TAKES = 3
GEN_VERSION = "cb1"  # erhoehen, wenn sich Rohaufnahme-Parameter grundsaetzlich aendern

# ------------------------------------------------------------------ Casting
# ref: Referenz in tools/voice_refs, ex: Chatterbox "exaggeration" (Ausdruck), cfg: cfg_weight (kleiner = schneller),
# chan: Kanal-Effekt, pitch: Halbtoene Nachstimmung (0 = aus), lufs: Ziel-Lautheit
CAST = {
    "weber":    {"ref": "weber.wav",    "ex": 0.45, "cfg": 0.5,  "chan": "radio",       "pitch": -0.6, "lufs": -17.0, "tempo": 1.00,
                 "max_tempo": 1.08, "compress": False,   # starker Funkfilter: Raffen kostet hier hoerbar Verstaendlichkeit
                 "desc": "Hauptmann Weber – ruhig, autoritaer (Thorsten-Voice, CC0); starker Funkfilter wie im Intro"},
    "lena":     {"ref": "lena.wav",     "ex": 0.65, "cfg": 0.45, "chan": "radio_light", "pitch": 0.0,  "lufs": -17.0, "tempo": 1.10,
                 "desc": "Obergefreite Lena Aksoy – jung, energisch (CML-TTS/LibriVox, CC-BY 4.0); Headset-Funk leicht"},
    "kerner":   {"ref": "kerner.wav",   "ex": 0.4,  "cfg": 0.5,  "chan": "close",       "pitch": 0.0,  "lufs": -18.0, "tempo": 1.00,
                 "desc": "Feldwebel Jonas Kerner – knapp, muede (CML-TTS/LibriVox, CC-BY 4.0); nah, innerer Monolog"},
    "riedhammer": {"ref": "riedhammer.wav",   "ex": 0.35, "cfg": 0.55, "chan": "pa",          "pitch": -1.2, "lufs": -17.0, "tempo": 1.00,
                 "desc": "General Albrecht von Riedhammer – aelter, kalt (CML-TTS/LibriVox, CC-BY 4.0); Lautsprecher/Megafon + Hall"},
    "rednerin": {"ref": "rednerin.wav", "ex": 0.6,  "cfg": 0.5,  "chan": "stage",       "pitch": 0.0,  "lufs": -18.0, "tempo": 1.00,
                 "desc": "Rednerin auf der Siegesfeier (CML-TTS/LibriVox, CC-BY 4.0); Buehnen-PA, Platzhall"},
    "lage":     {"ref": "lage.wav",     "ex": 0.4,  "cfg": 0.5,  "chan": "radio_light", "pitch": 0.0,  "lufs": -18.0, "tempo": 1.05,
                 "desc": "Lagebericht/Briefing – sachlicher Stabsoffizier (CML-TTS/LibriVox, CC-BY 4.0); Funk leicht"},
    "voss":     {"ref": "lage.wav",     "ex": 0.55, "cfg": 0.45, "chan": "radio_light", "pitch": -2.2, "lufs": -17.0, "tempo": 1.00,
                 "desc": "Konrad Voss – Widerstandsfuehrer, rau, tiefer (Lage-Referenz, tiefer gestimmt); Headset-Funk"},
    "brandt":   {"ref": "riedhammer.wav", "ex": 0.4, "cfg": 0.5,  "chan": "radio",       "pitch": 0.8,  "lufs": -17.0, "tempo": 1.02,
                 "desc": "Oberstleutnant Brandt – aelterer Offizier, ruhig (Riedhammer-Referenz, hoeher gestimmt); Bordfunk"},
    "falk":     {"ref": "weber.wav",    "ex": 0.3,  "cfg": 0.55, "chan": "radio",       "pitch": -2.6, "lufs": -17.0, "tempo": 0.95,
                 "desc": "Oberst Falk – Garde-Kommandeur, kalt, langsam, hoehnisch (Weber-Referenz, deutlich tiefer); Garde-Funk"},
    "hartmann": {"ref": "hartmann.wav", "ex": 0.45, "cfg": 0.5,  "chan": "close",       "pitch": -0.5, "lufs": -18.0, "tempo": 1.00,
                 "desc": "Praesidentin Hartmann – Geisel, gefasst, erschoepft (Rednerin-Referenz, etwas tiefer); nah"},
    "funker":   {"ref": "lage.wav",     "ex": 0.5,  "cfg": 0.5,  "chan": "radio",       "pitch": 1.0,  "lufs": -17.0,
                 "desc": "unbekannter Sprecher (Fallback)"},
}

SAMPLE_TEXT = {
    "weber": "Kerner, hier Weber. Euer Zug überquert das Feld. Die Stellungen am Waldrand müssen fallen, bevor es hell wird.",
    "lena": "Bewegung bei den Sandsäcken! Zwölf Uhr! Bin direkt hinter dir, Jonas. Kopf unten.",
    "kerner": "Lena und ich sind noch hier. Und wir sind nicht die Einzigen.",
    "riedhammer": "Bürger Berlins. Die Ordnungsfront übernimmt ab sofort den Schutz des Landes. Bleibt in euren Häusern.",
    "rednerin": "Zwei Jahre Krieg. Und heute Nacht sagen wir: Europa hat gehalten!",
    "lage": "Daugavpils ist seit vier Stunden umkämpft. Kampfgruppe Nord nimmt die Straße zurück – Haus für Haus.",
}

# Intro (game/intro/intro.gd): Datei -> (Text, max. Laenge in s inkl. Funk-Klicks)
INTRO = {
    "vo2": ("An alle Einheiten. Hier Weber.", 5.0),
    "vo3": ("Drei Uhr zwölf. Sie sind über die Grenze.", 5.2),
    "vo4": ("Ihr Ziel ist Riga. Und die Ostsee.", 4.8),
    "vo5": ("Kampfgruppe Nord ist die erste Linie.", 4.8),
    "vo6": ("Wir halten, bis Verstärkung kommt.", 3.4),
    "vo8": ("Jede Stunde zählt. Weber, Ende.", 4.5),
    "vo7": ("Kerner. ... Sie kommen.", 4.0),
}

# Aussprache / Schreibweise nur fuer die Sprachsynthese (Untertitel bleiben unveraendert)
SPEECH_FIX = [
    (r"\bBrueckenkopf\b", "Brückenkopf"), (r"\bBruecke\b", "Brücke"), (r"\brueber\b", "rüber"),
    (r"\bGraeben\b", "Gräben"), (r"\bStrasse\b", "Straße"), (r"\bbeschaeftigt\b", "beschäftigt"),
    (r"\bueber\b", "über"), (r"\bfuer\b", "für"), (r"\bMG-Nest\b", "Em-Geh-Nest"), (r"\bMG\b", "Em-Geh"),
    (r"\bEU\b", "E-U"), (r"\bPskow\b", "Pskoff"), (r"\bDaugavpils\b", "Daugawpils"), (r"\bAksoy\b", "Aksoi"), (r"\bJets\b", "Djets"),
    (r"„|“|\"", ""), (r"\s*[–—]\s*", ", "), (r"…|\.\.\.", "... "), (r"\n", " "), (r"\s{2,}", " "),
]


def speech_text(text):
    t = text
    for a, b in SPEECH_FIX:
        t = re.sub(a, b, t)
    t = t.strip()
    if t.startswith("... "):
        t = t[4:]
    return t


# ------------------------------------------------------------------ DSP

def fft_filter(x, lo, hi, sr=SR, soft=1.0):
    n = len(x)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1 / sr)
    g = np.ones_like(f)
    if lo > 0:
        g *= 1 / (1 + (lo / np.maximum(f, 1e-3)) ** (4 * soft))
    if hi > 0:
        g *= 1 / (1 + (f / hi) ** (4 * soft))
    return np.fft.irfft(X * g, n)


def peak_eq(x, fc, gain_db, q=1.0, sr=SR):
    """Glocken-EQ im Frequenzbereich (gausssche Kurve auf log-Achse)."""
    X = np.fft.rfft(x)
    f = np.maximum(np.fft.rfftfreq(len(x), 1 / sr), 1.0)
    g = 10 ** (gain_db / 20 * np.exp(-0.5 * (np.log2(f / fc) * 2 * q) ** 2))
    return np.fft.irfft(X * g, len(x))


def resample(x, sr_in, sr_out):
    if sr_in == sr_out:
        return x
    from math import gcd
    import scipy.signal as ss
    g = gcd(int(sr_in), int(sr_out))
    return ss.resample_poly(x, int(sr_out) // g, int(sr_in) // g)


def norm_peak(x, p=0.95):
    return x / (np.max(np.abs(x)) + 1e-9) * p


def trim_silence(x, thr_db=-45.0, pad_front=0.08, pad_back=0.12):
    win = int(0.01 * SR)
    e = np.sqrt(np.convolve(x ** 2, np.ones(win) / win, mode="same"))
    thr = np.max(e) * 10 ** (thr_db / 20)
    idx = np.where(e > thr)[0]
    if idx.size == 0:
        return x
    a = max(0, idx[0] - int(pad_front * SR))
    b = min(len(x), idx[-1] + int(pad_back * SR))
    y = x[a:b].copy()
    f = min(len(y) // 4, int(0.015 * SR))
    if f > 0:
        y[:f] *= np.linspace(0, 1, f)
        y[-f:] *= np.linspace(1, 0, f)
    return y


def comp(x, thr_db=-20.0, ratio=3.0, att=0.004, rel=0.12):
    """Einfacher Feed-forward-Kompressor (RMS-Huellkurve)."""
    a_att, a_rel = np.exp(-1 / (att * SR)), np.exp(-1 / (rel * SR))
    lvl = np.abs(x)
    env = np.empty_like(x)
    e = 0.0
    for i, v in enumerate(lvl):           # ~32k Samples/s, fuer kurze Zeilen schnell genug
        a = a_att if v > e else a_rel
        e = a * e + (1 - a) * v
        env[i] = e
    db = 20 * np.log10(env + 1e-9)
    gain_db = np.minimum(0.0, (thr_db - db) * (1 - 1 / ratio))
    return x * 10 ** (gain_db / 20)


def reverb_ir(seconds, sr=SR, damp_hz=3500.0, early=(), seed=1):
    rng = np.random.default_rng(seed)
    n = int(seconds * sr)
    t = np.arange(n) / sr
    ir = rng.standard_normal(n) * np.exp(-6.9 * t / seconds)
    ir = fft_filter(ir, 120, damp_hz, sr)
    ir[: int(0.012 * sr)] *= np.linspace(0, 1, int(0.012 * sr))   # Vorverzoegerung weich
    for d, g in early:                                             # diskrete Echos (Hauswaende)
        k = int(d * sr)
        if k < n:
            ir[k] += g * np.max(np.abs(ir)) * 3
    return ir / np.sqrt(np.sum(ir ** 2))


def convolve(x, ir, wet, tail):
    import scipy.signal as ss
    y = np.concatenate([x, np.zeros(int(tail * SR))])
    w = ss.fftconvolve(y, ir)[: len(y)]
    return y + w * wet


_rng = np.random.default_rng(2030)


def radio_click(n_sec=0.09, strength=1.0):
    n = int(n_sec * SR)
    t = np.arange(n) / SR
    c = np.zeros(n)
    k = int(0.004 * SR)
    c[:k] = np.linspace(1, -0.6, k)
    c += fft_filter(_rng.standard_normal(n), 900, 5000) * np.exp(-t * 45) * 0.7
    return c * strength


def bitcrush(x, bits=7, sr_hold=9000):
    step = max(1, int(round(SR / sr_hold)))
    y = np.repeat(x[::step], step)[: len(x)]
    q = 2 ** (bits - 1)
    return np.round(y * q) / q


def radio_fx(x, pad=(0.14, 0.24), heavy=True):
    """Funkgeraet wie im Intro (tools/piper/gen_intro_audio.py): Bandpass 300-3400 Hz, Saettigung, Bitcrush,
    Rauschteppich, Klick vorn, Squelch-Schwanz hinten. heavy=False: Headset-Funk, offener und sauberer."""
    x = norm_peak(x, 1.0)
    if heavy:
        x = fft_filter(x, 300, 3400, soft=1.6)
        x = norm_peak(x, 1.0)
        x = np.tanh(x * 4.0) / np.tanh(4.0)
        x = bitcrush(x, 7, 9000)
        x = fft_filter(x, 300, 3400, soft=1.2)
        bed_amp, hum_amp = 0.07, 0.012
    else:
        x = fft_filter(x, 260, 4200, soft=1.3)
        x = peak_eq(x, 1800, 3.0, 0.8)
        x = norm_peak(x, 1.0)
        x = np.tanh(x * 2.0) / np.tanh(2.0)
        x = fft_filter(x, 240, 4600, soft=1.0)
        bed_amp, hum_amp = 0.035, 0.005
    x = np.concatenate([np.zeros(int(pad[0] * SR)), x * 0.75, np.zeros(int(pad[1] * SR))])
    n = len(x)
    bed = fft_filter(_rng.standard_normal(n), 400, 4200) * bed_amp
    bed *= 1.0 + 0.35 * np.sin(np.arange(n) / SR * 2 * np.pi * 0.7)
    x = x + bed + np.sin(np.arange(n) / SR * 2 * np.pi * 120) * hum_amp
    f = int(0.02 * SR)
    x[:f] *= np.linspace(0, 1, f)
    ck = radio_click(0.09, 1.0 if heavy else 0.6)
    x[: len(ck)] += ck
    m = int(0.16 * SR)
    x[n - m:] += fft_filter(_rng.standard_normal(m), 700, 5500) * np.linspace(1, 0, m) ** 1.5 * (0.45 if heavy else 0.25)
    ck2 = radio_click(0.06, 0.8 if heavy else 0.5)
    x[n - len(ck2):] += ck2
    return x


def pa_fx(x):
    """Lautsprecherwagen/Megafon ueber einem Platz: Hornresonanz, Verzerrung, Strassenschlucht-Echos + langer Hall."""
    x = norm_peak(x, 1.0)
    x = fft_filter(x, 420, 3600, soft=1.5)
    x = peak_eq(x, 1700, 7.0, 1.2)
    x = peak_eq(x, 900, 3.0, 1.5)
    x = norm_peak(x, 1.0)
    x = np.tanh(x * 3.2) / np.tanh(3.2)
    x = fft_filter(x, 380, 4200, soft=1.0)
    ir = reverb_ir(2.4, damp_hz=2600, early=[(0.11, 0.55), (0.23, 0.4), (0.37, 0.3), (0.52, 0.18)], seed=7)
    y = convolve(x, ir, 0.42, 1.6)
    return np.concatenate([np.zeros(int(0.05 * SR)), y])


def stage_fx(x):
    """Buehnen-Beschallung bei der Feier: voller als Megafon, leicht komprimiert, Platz-Hall mit Echo."""
    x = norm_peak(x, 1.0)
    x = fft_filter(x, 160, 6500, soft=1.2)
    x = peak_eq(x, 2500, 3.0, 0.8)
    x = comp(x, -18, 3.0)
    x = norm_peak(x, 1.0)
    x = np.tanh(x * 1.6) / np.tanh(1.6)
    ir = reverb_ir(2.0, damp_hz=4000, early=[(0.16, 0.4), (0.31, 0.25)], seed=11)
    y = convolve(x, ir, 0.34, 1.3)
    return np.concatenate([np.zeros(int(0.05 * SR)), y])


def close_fx(x):
    """Nah/innerer Monolog: Trittschall weg, sanfte Kompression, kleiner Raum."""
    x = fft_filter(x, 75, 0, soft=1.0)
    x = comp(norm_peak(x, 1.0), -16, 2.2)
    ir = reverb_ir(0.45, damp_hz=5000, seed=3)
    return convolve(x, ir, 0.07, 0.3)


CHANNELS = {
    "radio": lambda x: radio_fx(x, heavy=True),
    "radio_light": lambda x: radio_fx(x, heavy=False),
    "pa": pa_fx,
    "stage": stage_fx,
    "close": close_fx,
}


def loudness(x, target):
    try:
        import pyloudnorm as pyln
        meter = pyln.Meter(SR)
        l = meter.integrated_loudness(x) if len(x) > SR * 0.45 else None
    except Exception:
        l = None
    if l is None or not np.isfinite(l):
        rms = np.sqrt(np.mean(x ** 2)) + 1e-9
        l = 20 * np.log10(rms) - 0.7
    y = x * 10 ** ((target - l) / 20)
    pk = np.max(np.abs(y))
    if pk > 0.89:                     # weicher Limiter auf ~-1 dBFS
        y = np.tanh(y / 0.89) * 0.89
    return y


def pitch_shift(x, semis):
    if abs(semis) < 0.05:
        return x
    import librosa
    return librosa.effects.pitch_shift(x.astype(np.float32), sr=SR, n_steps=semis, res_type="soxr_hq")


def time_stretch(x, rate):
    """Tempo ohne Tonhoehe aendern (WSOLA, audiotsm) – sauberer als Phase-Vocoder bei Sprache."""
    if abs(rate - 1.0) < 0.01:
        return x
    from audiotsm import wsola
    from audiotsm.io.array import ArrayReader, ArrayWriter
    w = ArrayWriter(1)
    wsola(1, speed=rate).run(ArrayReader(x.reshape(1, -1).astype(np.float32)), w)
    return w.data[0].astype(np.float64)


def compress_pauses(x, max_gap=0.22, thr_db=-40.0, sr=SR):
    """Satzpausen > max_gap auf max_gap kuerzen (Chatterbox/LibriVox-Prosodie ist fuer Funk zu gemaechlich)."""
    win = int(0.01 * sr)
    e = np.sqrt(np.convolve(x ** 2, np.ones(win) / win, mode="same"))
    quiet = e < np.max(e) * 10 ** (thr_db / 20)
    keep, f, n = int(max_gap * sr), int(0.01 * sr), len(x)
    out, i = [], 0
    while i < n:
        j = i
        while j < n and quiet[j] == quiet[i]:
            j += 1
        if quiet[i] and j - i > keep and 0 < i and j < n:
            a, b = x[i:i + keep // 2].copy(), x[j - keep // 2:j].copy()
            a[-f:] *= np.linspace(1, 0, f)
            b[:f] *= np.linspace(0, 1, f)
            out += [a, b]
        else:
            out.append(x[i:j])
        i = j
    return np.concatenate(out)


# ------------------------------------------------------------------ Modelle

_tts = None
_asr = None


def tts_model():
    global _tts
    if _tts is None:
        import torch
        from chatterbox.mtl_tts import ChatterboxMultilingualTTS
        _tts = ChatterboxMultilingualTTS.from_pretrained(device="cuda" if torch.cuda.is_available() else "cpu")
    return _tts


def asr_model():
    global _asr
    if _asr is None:
        import torch
        from transformers import WhisperForConditionalGeneration, WhisperProcessor
        name = "openai/whisper-large-v3-turbo"
        proc = WhisperProcessor.from_pretrained(name)
        m = WhisperForConditionalGeneration.from_pretrained(name, torch_dtype=torch.float16).cuda().eval()
        _asr = (proc, m)
    return _asr


def transcribe(x):
    import torch
    proc, m = asr_model()
    x16 = resample(x, SR, 16000).astype(np.float32)
    f = proc(x16, sampling_rate=16000, return_tensors="pt").input_features.cuda().half()
    with torch.no_grad():
        ids = m.generate(f, language="de", task="transcribe")
    return proc.batch_decode(ids, skip_special_tokens=True)[0].strip()


def _words(s):
    try:
        from num2words import num2words
        s = re.sub(r"\d+", lambda m: " " + num2words(int(m.group(0)), lang="de") + " ", s)
    except ImportError:
        pass
    s = s.lower().replace("-", " ")
    s = re.sub(r"[^a-zäöüß0-9 ]", " ", s)
    return s.split()


def wer(ref, hyp):
    r, h = _words(ref), _words(hyp)
    d = list(range(len(h) + 1))
    for i, rw in enumerate(r, 1):
        nd = [i]
        for j, hw in enumerate(h, 1):
            nd.append(min(d[j] + 1, nd[j - 1] + 1, d[j - 1] + (rw != hw)))
        d = nd
    return d[-1] / max(1, len(r))


def synth(text, cast, seed):
    import torch
    torch.manual_seed(seed)
    m = tts_model()
    ex = cast["ex"]
    if text.rstrip().endswith("!"):
        ex = min(0.9, ex + 0.15)       # Rufe etwas lebhafter
    wav = m.generate(text, language_id="de", audio_prompt_path=os.path.join(REFS, cast["ref"]),
                     exaggeration=ex, cfg_weight=cast["cfg"], temperature=0.75)
    return resample(wav.squeeze(0).cpu().numpy().astype(np.float64), m.sr, SR)


def cast_key(cast):
    return hashlib.sha1(json.dumps([GEN_VERSION, cast["ref"], cast["ex"], cast["cfg"]]).encode()).hexdigest()[:8]


EXTRA_TAKES = 3   # bis zu 3 weitere Seeds, wenn Whisper in keinem Take alles verstanden hat


def best_take(uid, text, cast, budget, retake=False, takes=TAKES, log=None):
    """Rohaufnahme (trocken, 32 kHz, getrimmt) aus Cache oder neu: bester von N Takes nach Whisper-WER."""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, "%s_%s.wav" % (uid, cast_key(cast)))
    if os.path.exists(path) and not retake:
        x, _ = sf.read(path)
        return x, None
    stext = speech_text(text)
    cands = []
    for k in range(takes + EXTRA_TAKES):
        if k >= takes and min(c[0] for c in cands) == 0.0:
            break   # Zusatz-Takes nur, solange noch kein fehlerfreier Take dabei ist
        x = trim_silence(synth(stext, cast, 1000 + k * 7919))
        hyp = transcribe(x)
        w = min(wer(stext, hyp), wer(text, hyp))   # Umschreibungen (Djets, Aksoi) nicht als Fehler werten
        d = len(x) / SR
        cands.append((w, d, x, hyp))
        if log:
            log("    take %d: WER %.2f  %.2fs  %s" % (k, w, d, hyp[:70]))
        if w == 0.0 and (budget is None or d <= budget):
            break
    good = [c for c in cands if c[0] <= min(c2[0] for c2 in cands) + 1e-6]
    if budget is not None:
        good.sort(key=lambda c: max(0.0, c[1] - budget) + 0.02 * c[1])
    w, d, x, hyp = good[0]
    sf.write(path, x, SR, subtype="FLOAT")
    return x, (w, hyp)


MAX_TEMPO = 1.18   # staerker raffen klingt hoerbar gepresst


def render(x, cast, budget=None):
    """Trockene Aufnahme -> fertiger Kanal-Klang. Pausen kuerzen, Figuren-Tempo, bei Ueberlaenge
    (budget = verfuegbare Sprechzeit in s) zusaetzlich bis MAX_TEMPO raffen."""
    if cast.get("compress", True):
        x = compress_pauses(x)
    x = pitch_shift(x, cast["pitch"])
    rate = cast.get("tempo", 1.0)
    if budget is not None:
        rate = max(rate, min(cast.get("max_tempo", MAX_TEMPO), (len(x) / SR) / budget))
    x = time_stretch(x, rate)
    y = CHANNELS[cast["chan"]](x)
    return loudness(y, cast["lufs"])


def write_ogg(path, y):
    # blockweise: libsndfile/Vorbis laeuft bei langen Einzel-writes (> ~15 s) in einen Stack Overflow (Windows)
    y = np.clip(y, -1, 1).astype(np.float32)
    with sf.SoundFile(path, "w", SR, 1, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(y), SR):
            f.write(y[i:i + SR])


def chan_overhead(chan):
    return {"radio": 0.38, "radio_light": 0.38, "pa": 0.0, "stage": 0.0, "close": 0.0}[chan]


# ------------------------------------------------------------------ Zeilen-Dauern aus dem Quelltext

def explicit_durations():
    """(speaker, text) -> vorgegebene Dauer aus _say/_radio(..., dur) bzw. ENDING-Sekunden."""
    out = {}
    rx = re.compile(r'(?:_say|_radio)\(\s*(?:[\d.]+\s*,\s*"[^"]*"\s*,\s*)?[^,]+,\s*"((?:[^"\\]|\\.)*)"\s*,\s*([\d.]+)\s*\)')
    for dirpath, _d, files in os.walk(os.path.join(ROOT, "game", "levels")):
        for fn in files:
            if fn.endswith(".gd"):
                src = open(os.path.join(dirpath, fn), encoding="utf-8").read()
                for m in rx.finditer(src):
                    out[voice_lines.unescape(m.group(1))] = float(m.group(2))
    sd = open(voice_lines.STORY_DATA, encoding="utf-8").read()
    for m in re.finditer(r'\[\s*"((?:[^"\\]|\\.)*)"\s*,\s*([\d.]+)\s*\]', voice_lines._block(sd, "ENDING")):
        out[voice_lines.unescape(m.group(1))] = float(m.group(2))
    return out


def auto_duration(text):
    return min(8.0, max(2.5, 1.6 + 0.055 * len(text)))


def slot_of(line, durs):
    if line["character"] == "lage":
        return None                    # Briefing: Titelkarte wartet auf die Stimme
    d = durs.get(line["text"])
    return d if d is not None else auto_duration(line["text"])


# ------------------------------------------------------------------ Befehle

def gen_lines(args):
    lines = voice_lines.collect()
    with open(voice_lines.OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(lines, f, ensure_ascii=False, indent=1)
    durs = explicit_durations()
    sel = set(args.only.split(",")) if args.only else None
    os.makedirs(OUT, exist_ok=True)
    manifest_path = os.path.join(OUT, "manifest.json")
    manifest = json.load(open(manifest_path, encoding="utf-8")) if os.path.exists(manifest_path) else {}
    valid_ids = {l["id"] for l in lines}
    for l in lines:
        uid, ch = l["id"], l["character"]
        if sel and uid not in sel and ch not in sel:
            continue
        cast = CAST.get(ch, CAST["funker"])
        dst = os.path.join(OUT, uid + ".ogg")
        if os.path.exists(dst) and not (args.force or args.retake) and manifest.get(uid, {}).get("cast") == cast_key(cast):
            continue
        slot = slot_of(l, durs)
        budget = None if slot is None else max(0.6, slot - TAIL - chan_overhead(cast["chan"]))
        print("%s [%s] %s" % (uid, ch, l["text"][:80]))
        x, qa = best_take(uid, l["text"], cast, budget, retake=args.retake, log=print)
        y = render(x, cast, budget)
        write_ogg(dst, y)
        info = {"speaker": l["speaker"], "character": ch, "text": l["text"], "cast": cast_key(cast),
                "seconds": round(len(y) / SR, 2), "slot": slot}
        if qa:
            info["wer"], info["asr"] = round(qa[0], 3), qa[1]
        elif uid in manifest:
            info["wer"], info["asr"] = manifest[uid].get("wer"), manifest[uid].get("asr")
        manifest[uid] = info
        print("   -> %.2fs (Slot %s)" % (len(y) / SR, slot))
    # verwaiste Dateien (Text geaendert) entfernen
    for fn in os.listdir(OUT):
        if fn.endswith(".ogg") and fn[:-4] not in valid_ids:
            os.remove(os.path.join(OUT, fn))
            imp = os.path.join(OUT, fn + ".import")
            if os.path.exists(imp):
                os.remove(imp)
            manifest.pop(fn[:-4], None)
            print("entfernt (veraltet):", fn)
    manifest = {k: v for k, v in manifest.items() if k in valid_ids}
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1, sort_keys=True)
    report(lines, manifest)


def report(lines=None, manifest=None):
    lines = lines or voice_lines.collect()
    if manifest is None:
        mp = os.path.join(OUT, "manifest.json")
        manifest = json.load(open(mp, encoding="utf-8")) if os.path.exists(mp) else {}
    durs = explicit_durations()
    over = []
    for l in lines:
        m = manifest.get(l["id"])
        if not m:
            print("FEHLT", l["id"], l["text"][:60])
            continue
        slot = slot_of(l, durs)
        if slot is not None:
            o = m["seconds"] + TAIL - slot
            if o > 0.05:
                over.append((o, l["id"], l["character"], slot, m["seconds"], l["text"][:60]))
    bad = [(k, v) for k, v in manifest.items() if (v.get("wer") or 0) > 0.2]
    print("\n%d Zeilen, %d vertont. Laenger als vorgesehene Dauer: %d (Summe %.1fs)" % (
        len(lines), len(manifest), len(over), sum(o[0] for o in over)))
    for o in sorted(over, reverse=True)[:25]:
        print("  +%.2fs  %s %-8s slot %.1f audio %.2f  %s" % o)
    for k, v in bad:
        print("  WER %.2f  %s  %s | %s" % (v["wer"], k, v["text"][:50], v.get("asr", "")[:50]))


def gen_samples(args):
    os.makedirs(SAMPLES, exist_ok=True)
    for ch, text in SAMPLE_TEXT.items():
        if args.only and ch not in args.only.split(","):
            continue
        cast = CAST[ch]
        x, _ = best_take("sample_" + ch, text, cast, None, retake=args.retake, log=print)
        y = render(x, cast)
        write_ogg(os.path.join(SAMPLES, "%s_%s.ogg" % (ch, cast["chan"])), y)
        write_ogg(os.path.join(SAMPLES, "%s_roh.ogg" % ch), loudness(pitch_shift(x, cast["pitch"]), -18.0))
        print("Probe", ch, "%.2fs" % (len(y) / SR))
    with open(os.path.join(SAMPLES, "README.txt"), "w", encoding="utf-8") as f:
        f.write("Stimmproben (erzeugt mit tools/gen_voice.py --samples). <figur>_roh = ohne Effekt, sonst mit Kanal-Effekt.\n\n")
        for ch in SAMPLE_TEXT:
            f.write("%-9s %s\n          Text: %s\n" % (ch, CAST[ch]["desc"], SAMPLE_TEXT[ch]))


def gen_intro(args):
    cast = CAST["weber"]
    for key, (text, max_len) in INTRO.items():
        budget = max_len - chan_overhead("radio")
        x, _ = best_take("intro_" + key, text, cast, budget, retake=args.retake, log=print)
        x = pitch_shift(x, cast["pitch"])
        if len(x) / SR > budget:
            x = time_stretch(x, min(1.15, (len(x) / SR) / budget))
        y = norm_peak(radio_fx(x, pad=(0.32, 0.32), heavy=True), 0.93)
        path = os.path.join(SFX, "intro_%s.wav" % key)
        sf.write(path, y, SR, subtype="PCM_16")
        print("  intro_%s.wav %.2fs" % (key, len(y) / SR))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--retake", action="store_true")
    ap.add_argument("--samples", action="store_true")
    ap.add_argument("--intro", action="store_true")
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()
    if args.report:
        report()
    elif args.samples:
        gen_samples(args)
    elif args.intro:
        gen_intro(args)
    else:
        gen_lines(args)


if __name__ == "__main__":
    main()
