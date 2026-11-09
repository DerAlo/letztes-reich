#!/usr/bin/env python3
"""Schneidet Referenzstimmen fuer das Voice-Cloning aus freien Datensaetzen (nach tools/voice_refs/<name>.wav).

Quellen (nur ohne Login, HuggingFace-Parquet-Shards nach tools/voice_refs/raw/ laden, siehe CREDITS):
  * Thorsten-Voice TV-44kHz-Full (CC0), https://huggingface.co/datasets/Thorsten-Voice/TV-44kHz-Full
      raw/thorsten_2022_00.parquet = TV-2022.10-Neutral/train-00000-of-00008.parquet
      raw/thorsten_emo_00.parquet  = TV-2021.06-Emotional/train-00000-of-00002.parquet
  * CML-TTS German (CC-BY 4.0, Aufnahmen aus LibriVox/MLS), https://huggingface.co/datasets/freds0/cml_tts_dataset_german
      raw/cml_de_dev_00.parquet  = data/dev-00000-of-00004.parquet
      raw/cml_de_test_00.parquet = data/test-00000-of-00004.parquet
  * Google FLEURS ru_ru (CC-BY 4.0), https://huggingface.co/datasets/google/fleurs (Gegner-Barks, Russisch)
      raw/fleurs_ru/train_0.parquet = https://huggingface.co/api/datasets/google/fleurs/parquet/ru_ru/train/0.parquet
      (automatische Parquet-Konvertierung von HF, Spalten audio{bytes,path}, gender 0 = maennlich; FLEURS hat keine
      Sprecher-IDs -> je Stimme genau EIN Clip, ausgewaehlt per Stimm-Embedding-Clusterung der Maennerclips)

  tools/chatterbox/venv/Scripts/python -I tools/voice_refs/make_refs.py            # alle Referenzen
  tools/chatterbox/venv/Scripts/python -I tools/voice_refs/make_refs.py --barks    # nur bark_*.wav
"""
import io
import os

import numpy as np
import pyarrow.parquet as pq
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
SR = 24000

# name -> (datei, filter, anzahl clips). filter: dict feld->wert
REFS = {
    "weber": ("thorsten_2022_00", {"microphone": "good_rodePodcaster"}, 3),
}
# CML-Sprecher (client_id) werden unten ergaenzt, sobald ausgewaehlt
# Casting (siehe tools/gen_voice.py CAST): name -> (datei, client_id, anzahl clips, ueberspringen)
CML = {
    "lena": ("cml_de_test_00", 8450, 2, 0),      # weiblich, ~223 Hz
    "rednerin": ("cml_de_dev_00", 1593, 2, 0),   # weiblich, ~197 Hz
    "riedhammer": ("cml_de_test_00", 4911, 2, 0),    # maennlich, tief ~96 Hz
    "kerner": ("cml_de_test_00", 91, 2, 0),      # maennlich, ~144 Hz
    "lage": ("cml_de_dev_00", 7002, 2, 0),       # maennlich, ~113 Hz
}
# Gegner-Barks (tools/gen_barks.py VOICES), Deutsch "Ordnungsfront": weitere CML-Maennerstimmen
BARK_CML = {
    "bark_reich_v1": ("cml_de_dev_00", 5295, 2, 0),    # ~141 Hz, jung/hell
    "bark_reich_v2": ("cml_de_test_00", 3052, 2, 0),   # ~115 Hz, helles Timbre
    "bark_reich_v3": ("cml_de_dev_00", 138, 2, 0),     # ~115 Hz, weiter Tonumfang
    "bark_reich_off": ("cml_de_dev_00", 4001, 2, 0),   # ~106 Hz, ruhig/gleichmaessig (Offizier)
}
# Russisch: FLEURS ru_ru train, je ein Clip (audio.path); F0 der Referenz in Klammern
BARK_FLEURS = {
    "bark_ru_v1": "6070315263568956937.wav",    # ~123 Hz
    "bark_ru_v2": "4627039069170210682.wav",    # ~93 Hz, tief
    "bark_ru_v3": "15597926945427512812.wav",   # ~130 Hz, hell
    "bark_ru_v4": "10463014390435637574.wav",   # ~120 Hz
    "bark_ru_v5": "3949639651547107576.wav",    # ~113 Hz, eigenes Timbre
    "bark_ru_off": "5591603984983668316.wav",   # ~92 Hz, tief, Studioqualitaet (Offizier)
}
# Kandidaten fuer neues Casting: python make_refs.py --cand  (schreibt cand/<g>_<id>.wav)
CANDIDATES = {"f": [("cml_de_dev_00", 10349), ("cml_de_dev_00", 1593), ("cml_de_test_00", 7120), ("cml_de_test_00", 7261),
                    ("cml_de_test_00", 8223), ("cml_de_test_00", 3588), ("cml_de_test_00", 8450), ("cml_de_test_00", 1660)],
              "m": [("cml_de_dev_00", 138), ("cml_de_dev_00", 7272), ("cml_de_test_00", 4911), ("cml_de_test_00", 3052),
                    ("cml_de_dev_00", 4001), ("cml_de_dev_00", 7002), ("cml_de_dev_00", 5295), ("cml_de_test_00", 91),
                    ("cml_de_test_00", 1054), ("cml_de_test_00", 4705)]}


def resample(x, sr_in, sr_out):
    if sr_in == sr_out:
        return x
    import scipy.signal as ss
    from math import gcd
    g = gcd(sr_in, sr_out)
    return ss.resample_poly(x, sr_out // g, sr_in // g)


def trim(x, thr=0.01):
    idx = np.where(np.abs(x) > thr)[0]
    return x[max(0, idx[0] - 1200):idx[-1] + 2400] if idx.size else x


def build(rows, n, min_d=4.0, max_d=9.0, skip=0):
    clips = []
    for r in rows[skip:]:
        x, sr = sf.read(io.BytesIO(r["audio"]["bytes"]))
        if x.ndim > 1:
            x = x.mean(axis=1)
        d = len(x) / sr
        if not (min_d <= d <= max_d):
            continue
        x = trim(resample(x, sr, SR))
        clips.append(x / (np.max(np.abs(x)) + 1e-9) * 0.9)
        clips.append(np.zeros(int(0.35 * SR)))
        if len(clips) >= 2 * n:
            break
    return np.concatenate(clips[:-1])


def fleurs_refs():
    t = pq.read_table(os.path.join(RAW, "fleurs_ru", "train_0.parquet"), columns=["audio", "gender"])
    want = {v: k for k, v in BARK_FLEURS.items()}
    for r in t.to_pylist():
        name = want.get(r["audio"]["path"])
        if not name:
            continue
        x, sr = sf.read(io.BytesIO(r["audio"]["bytes"]))
        if x.ndim > 1:
            x = x.mean(axis=1)
        x = trim(resample(x, sr, SR))[: int(14 * SR)]
        x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
        sf.write(os.path.join(HERE, name + ".wav"), x, SR, subtype="PCM_16")
        print(name, "%.1fs" % (len(x) / SR))


def main():
    import sys
    if "--barks" in sys.argv:
        CML.clear()
        REFS.clear()
    if "--barks" in sys.argv or "--cand" not in sys.argv:
        CML.update(BARK_CML)
        fleurs_refs()
    if "--cand" in sys.argv:
        os.makedirs(os.path.join(HERE, "cand"), exist_ok=True)
        for g, lst in CANDIDATES.items():
            for fn, cid in lst:
                CML["cand/%s_%d" % (g, cid)] = (fn, cid, 3, 0)
    for name, (fn, flt, n) in REFS.items():
        cols = None
        rows = pq.read_table(os.path.join(RAW, fn + ".parquet")).to_pylist()
        if "microphone" in flt:
            rows = [r for r in rows if r.get("microphone") == flt["microphone"]]
        if "style_prefix" in flt:
            rows = [r for r in rows if str(r.get("style", "")).startswith(flt["style_prefix"])]
        x = build(rows, n)[: int(14 * SR)]
        sf.write(os.path.join(HERE, name + ".wav"), x, SR, subtype="PCM_16")
        print(name, "%.1fs" % (len(x) / SR))
    for name, (fn, cid, n, skip) in CML.items():
        rows = [r for r in pq.read_table(os.path.join(RAW, fn + ".parquet")).to_pylist() if r["client_id"] == cid]
        rows.sort(key=lambda r: -r["levenshtein"])   # beste Transkript-Uebereinstimmung zuerst
        x = build(rows, n, 5.0, 11.0, skip)[: int(14 * SR)]
        sf.write(os.path.join(HERE, name + ".wav"), x, SR, subtype="PCM_16")
        print(name, "%.1fs" % (len(x) / SR))


if __name__ == "__main__":
    main()
