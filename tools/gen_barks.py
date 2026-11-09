#!/usr/bin/env python3
"""Gegner-Barks (Kampfrufe) -> assets/voice/barks/<faction>_<voice>_<situation>_<n>.ogg (Ogg Vorbis, mono, 32 kHz,
trocken – das Spiel positioniert 3D). n beginnt bei 1 und ist lueckenlos (das Spiel probiert n=1,2,3,... per
ResourceLoader.exists, bis eine Datei fehlt). Doku: assets/voice/barks/manifest.json (Text, Stimme, Dauer, WER).

Laeuft in der Chatterbox-venv (wie tools/gen_voice.py, dessen DSP/Modelle hier wiederverwendet werden):

  tools/chatterbox/venv/Scripts/python tools/gen_barks.py              # nur fehlende/geaenderte Barks erzeugen
  ... --force                     alles neu rendern (TTS-Rohaufnahmen aus dem Cache)
  ... --retake                    auch die TTS-Rohaufnahmen neu
  ... --only <filter>[,...]       z. B. ru_v1  |  reich  |  spot  |  ru_off_order_reinf  |  ru_v3_mandown_2
  ... --samples                   Hoerproben -> tools/voice_samples/barks/ (aus vorhandenen Dateien)
  ... --list                      Plan ausgeben (Dateiname, Stimme, Text), nichts erzeugen

Fraktionen: "ru" (Russisch, Chatterbox language_id "ru") und "reich" (Deutsch, fiktive "Ordnungsfront").
Stimmen: v1..v5 (ru) bzw. v1..v3 (reich) = Soldaten, "off" = Offizier. Referenzen tools/voice_refs/bark_*.wav
(erzeugt von tools/voice_refs/make_refs.py, Quellen/Lizenzen siehe assets/CREDITS.md).

Russische Texte: "+" vor einem Vokal markiert die Betonung (nur fuer die Synthese, wird zu U+0301 hinter dem
Vokal – Chatterbox wurde mit Betonungszeichen trainiert; das Paket russian_text_stresser ist nicht installiert).
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys

import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_voice as gv  # noqa: E402  (setzt HF_HOME)
from gen_voice import SR, comp, fft_filter, loudness, norm_peak, pitch_shift, radio_fx, resample, trim_silence, write_ogg  # noqa: E402

OUT = os.path.join(gv.ROOT, "assets", "voice", "barks")
CACHE = os.path.join(gv.CACHE, "barks")
SAMPLES = os.path.join(gv.SAMPLES, "barks")
GEN_VERSION = "b2"

# ------------------------------------------------------------------ Stimmen
# ref: tools/voice_refs/..., ex/cfg: Chatterbox exaggeration/cfg_weight (gepresst: ex hoch, cfg niedrig),
# pitch: Halbtoene Nachstimmung (Unterscheidbarkeit), temp: Sampling-Temperatur
VOICES = {
    "ru_v1":    {"ref": "bark_ru_v1.wav",    "lang": "ru", "ex": 0.85, "cfg": 0.35, "pitch": 0.0,  "temp": 0.8},
    "ru_v2":    {"ref": "bark_ru_v2.wav",    "lang": "ru", "ex": 0.80, "cfg": 0.40, "pitch": -0.5, "temp": 0.8},
    "ru_v3":    {"ref": "bark_ru_v3.wav",    "lang": "ru", "ex": 0.90, "cfg": 0.35, "pitch": 0.5,  "temp": 0.8},
    "ru_v4":    {"ref": "bark_ru_v4.wav",    "lang": "ru", "ex": 0.85, "cfg": 0.40, "pitch": -1.0, "temp": 0.8},
    "ru_v5":    {"ref": "bark_ru_v5.wav",    "lang": "ru", "ex": 0.90, "cfg": 0.30, "pitch": 1.0,  "temp": 0.8},
    "ru_off":   {"ref": "bark_ru_off.wav",   "lang": "ru", "ex": 0.75, "cfg": 0.45, "pitch": -0.8, "temp": 0.75},
    "reich_v1":  {"ref": "bark_reich_v1.wav",  "lang": "de", "ex": 0.85, "cfg": 0.35, "pitch": 0.3,  "temp": 0.8},
    "reich_v2":  {"ref": "bark_reich_v2.wav",  "lang": "de", "ex": 0.90, "cfg": 0.35, "pitch": 0.0,  "temp": 0.8},
    "reich_v3":  {"ref": "bark_reich_v3.wav",  "lang": "de", "ex": 0.85, "cfg": 0.40, "pitch": -0.6, "temp": 0.8},
    "reich_off": {"ref": "bark_reich_off.wav", "lang": "de", "ex": 0.75, "cfg": 0.45, "pitch": -0.8, "temp": 0.75},
}

# ------------------------------------------------------------------ Texte
SOLDIER = {
    "ru": {
        "spot":    ["Конт+акт!", "В+ижу пр+отивника!", "Пр+отивник вперед+и!", "Вон он!", "В+ижу ег+о!", "Ц+ель в+ижу!"],
        "reload":  ["Перезаряж+аюсь!", "Мен+яю магаз+ин!", "Прикр+ой, перезаряж+аю!"],
        "grenade": ["Гран+ата!", "Лож+ись!", "Гран+ата, лож+ись!"],
        "cover":   ["В укр+ытие!", "Прикр+ой мен+я!", "Прикрыв+аю!"],
        "advance": ["Вперёд!", "Пошл+и, пошл+и!", "Дв+игаемся!", "Наступ+аем!"],
        "flank":   ["Обхож+у сл+ева!", "Захож+у с фл+анга!", "Обхож+у спр+ава!"],
        "hit":     ["Я р+анен!", "Задел+о!", "Чёрт!", "А-а, р+анен!"],
        "death":   ["А-а…", "Ох…", "Мать…"],
        "mandown": ["Двухс+отый!", "Потер+яли одног+о!", "У нас пот+ери!", "М+инус од+ин!"],
        "lost":    ["Где он?", "Потер+ял ег+о!", "Не в+ижу ег+о!"],
    },
    "reich": {
        "spot":    ["Kontakt!", "Feind gesichtet!", "Da vorne!", "Ziel erkannt!", "Feindkontakt!"],
        "reload":  ["Lade nach!", "Magazin wechseln!", "Nachladen, deck mich!"],
        "grenade": ["Granate!", "Runter, Granate!", "Granate, in Deckung!"],
        "cover":   ["Deckung!", "Gebe Feuerschutz!", "Deck mich!"],
        "advance": ["Vorrücken!", "Vorwärts, los!", "Weiter, weiter!"],
        "flank":   ["Gehe links rum!", "Flankiere rechts!", "Gehe rechts rum!"],
        "hit":     ["Ich bin getroffen!", "Verdammt!", "Treffer!"],
        "death":   ["Ah…", "Nein…", "Ugh…"],
        "mandown": ["Mann verloren!", "Wir haben einen verloren!", "Sanitäter!"],
        "lost":    ["Wo ist der hin?", "Kein Sichtkontakt!", "Wo steckt der?"],
    },
}
OFFICER = {
    "ru": {
        "spot":          ["Пр+отивник! К бо+ю!", "Конт+акт! Вс+ем к бо+ю!"],
        "hit":           ["Зацеп+ило!"],
        "death":         ["Ох…"],
        "mandown":       ["Двухс+отый! Держ+ать поз+ицию!", "У нас пот+ери! Не отступ+ать!"],
        "order_advance": ["Все вперёд! Дав+ить их!", "Вперёд, не сто+ять!"],
        "order_flank":   ["Обход+ите с фл+анга!", "Втор+ое отдел+ение — сл+ева!"],
        "order_reinf":   ["Н+ужно подкрепл+ение, ср+очно!", "Подкрепл+ение на мо+ю поз+ицию!"],
        "order_mark":    ["Цель обозн+ачена! Ог+онь по поз+иции!", "Он за укр+ытием — ог+онь!"],
    },
    "reich": {
        "spot":          ["Feindkontakt! Feuer frei!", "Kontakt! Alle in Stellung!"],
        "hit":           ["Ich bin getroffen!"],
        "death":         ["Ah…"],
        "mandown":       ["Mann verloren! Weiterkämpfen!", "Sanitäter! Stellung halten!"],
        "order_advance": ["Alle Mann vorrücken!", "Druck machen! Vorwärts!"],
        "order_flank":   ["Zweite Gruppe, Flanke links!", "Umgehen! Von der Seite!"],
        "order_reinf":   ["Brauche Verstärkung, sofort!", "Verstärkung zu meiner Position!"],
        "order_mark":    ["Ziel markiert! Feuer frei!", "Feuer auf die Markierung!"],
    },
}
COUNT = {"spot": 3}            # Varianten je Soldat (sonst 2)
RADIO = {"order_reinf", "order_mark"}
NO_QA = {"death"}              # reine Laute: keine Whisper-Pruefung
LOOSE_QA = {"hit"}             # Schmerzlaute: Pruefung nur weich
DEATH_MAX = 0.8
MAX_GAP = 0.28                 # laengere Pausen mitten im Ruf klingen unnatuerlich -> weiterer Take
LUFS = {"death": -19.0, "hit": -17.0}
LUFS_DEFAULT = -16.0
# Neue Seed-Serie fuer Barks, bei denen Whisper in keinem der 6 Takes alles verstanden hat
RESEED = {"reich_v3_hit_1": 1, "reich_v3_mandown_2": 1}


def plan():
    """Liste aller Barks: dict(name, faction, voice, situation, n, text)."""
    out = []
    for vkey in VOICES:
        faction, voice = vkey.split("_", 1)
        if voice == "off":
            table, idx = OFFICER[faction], 0
        else:
            table, idx = SOLDIER[faction], int(voice[1:]) - 1
        for sit, texts in table.items():
            k = len(texts) if voice == "off" else min(len(texts), COUNT.get(sit, 2))
            # jede Stimme bekommt eine andere Teilmenge/Reihenfolge (Rotation um den Stimmindex)
            sel = [texts[(idx + j) % len(texts)] for j in range(k)]
            if voice != "off" and len(texts) == k and idx % 2 == 1:
                sel = sel[::-1]
            for n, t in enumerate(sel, 1):
                out.append({"name": "%s_%s_%s_%d" % (faction, voice, sit, n), "faction": faction, "voice": voice,
                            "vkey": vkey, "situation": sit, "n": n, "text": t})
    return out


# ------------------------------------------------------------------ Text / QA

def display_text(t):
    return t.replace("+", "")


def tts_text(t, lang):
    if lang == "ru":
        t = re.sub(r"\+([аеёиоуыэюяАЕЁИОУЫЭЮЯ])", "\\1\u0301", t)
    return t.replace("…", "...").replace(" — ", ", ")


def transcribe(x, lang):
    import torch
    proc, m = gv.asr_model()
    x16 = resample(x, SR, 16000).astype(np.float32)
    f = proc(x16, sampling_rate=16000, return_tensors="pt").input_features.cuda().half()
    with torch.no_grad():
        ids = m.generate(f, language=lang, task="transcribe")
    return proc.batch_decode(ids, skip_special_tokens=True)[0].strip()


def words(s, lang):
    try:
        from num2words import num2words
        s = re.sub(r"\d+", lambda m: " " + num2words(int(m.group(0)), lang=lang) + " ", s)
    except Exception:
        pass
    s = s.lower().replace("ё", "е").replace("\u0301", "").replace("-", " ")
    s = re.sub(r"[^a-zäöüßа-я0-9 ]", " ", s)
    return s.split()


def wer(ref, hyp, lang):
    r, h = words(ref, lang), words(hyp, lang)
    if "".join(r) == "".join(h):
        return 0.0            # nur anders getrennt ("За дело" = "Задело", "Weiter weiter")
    d = list(range(len(h) + 1))
    for i, rw in enumerate(r, 1):
        nd = [i]
        for j, hw in enumerate(h, 1):
            nd.append(min(d[j] + 1, nd[j - 1] + 1, d[j - 1] + (rw != hw)))
        d = nd
    return d[-1] / max(1, len(r))


# ------------------------------------------------------------------ Synthese

def synth(text, v, seed):
    import torch
    torch.manual_seed(seed)
    m = gv.tts_model()
    wav = m.generate(text, language_id=v["lang"], audio_prompt_path=os.path.join(gv.REFS, v["ref"]),
                     exaggeration=v["ex"], cfg_weight=v["cfg"], temperature=v["temp"])
    return resample(wav.squeeze(0).cpu().numpy().astype(np.float64), m.sr, SR)


def _env_db(x, win=0.01):
    w = int(win * SR)
    e = np.sqrt(np.convolve(x ** 2, np.ones(w) / w, mode="same"))
    return 20 * np.log10(e / (np.max(e) + 1e-12) + 1e-12)


def trim_bark(x, front_db=-35.0, back_db=-30.0):
    """Bark muss sofort einsetzen: vorne nur 10 ms Luft. Hinten strenger (Rauschfahnen der Referenz weg)."""
    db = _env_db(x)
    on, off = np.where(db > front_db)[0], np.where(db > back_db)[0]
    if on.size == 0:
        return x
    a = max(0, on[0] - int(0.01 * SR))
    b = min(len(x), off[-1] + int(0.08 * SR))
    y = x[a:b].copy()
    fi, fo = min(len(y) // 4, int(0.004 * SR)), min(len(y) // 4, int(0.05 * SR))
    y[:fi] *= np.linspace(0, 1, fi)
    y[-fo:] *= np.linspace(1, 0, fo)
    return y


def gaps(x, min_gap=0.18, thr_db=-30.0):
    """Startpositionen (Samples) stiller Luecken >= min_gap nach dem Einsatz – Kandidaten fuer Nachplappern."""
    q = _env_db(x) < thr_db
    out, i, n = [], int(0.15 * SR), len(x)
    while i < n:
        if q[i]:
            j = i
            while j < n and q[j]:
                j += 1
            if j - i >= min_gap * SR and j < n:
                out.append(i)
            i = j
        else:
            i += 1
    return out


def max_gap(x, thr_db=-30.0):
    q = _env_db(x) < thr_db
    best, run = 0, 0
    for v in q[int(0.05 * SR): len(q) - int(0.05 * SR)]:
        run = run + 1 if v else 0
        best = max(best, run)
    return best / SR


def cut_tail(x, ref, lang, w_full):
    """Chatterbox haengt bei kurzen Rufen gelegentlich Gebrabbel an: an der fruehesten Luecke abschneiden,
    bei der Whisper den Text noch genauso gut versteht."""
    for g in gaps(x):
        y = trim_bark(x[: g + int(0.03 * SR)])
        hyp = transcribe(y, lang)
        w = wer(ref, hyp, lang)
        if w <= w_full:
            return y, w, hyp
    return None


def max_dur(text):
    t = display_text(text)
    return 0.55 + 0.075 * len(t) + 0.15 * t.count(",") + 0.25 * len(re.findall(r"[!?.…—]\s+\S", t))


def raw_key(b, v):
    return hashlib.sha1(json.dumps([GEN_VERSION, v["ref"], v["lang"], v["ex"], v["cfg"], v["temp"], b["text"]] + ([RESEED[b["name"]]] if b["name"] in RESEED else []),
                                   ensure_ascii=False).encode("utf-8")).hexdigest()[:10]


def best_take(b, v, retake=False, log=print):
    """Trockene, getrimmte Rohaufnahme (Cache) + QA-Info (wer, asr) oder None aus dem Cache."""
    os.makedirs(CACHE, exist_ok=True)
    key = raw_key(b, v)
    path = os.path.join(CACHE, "%s_%s.wav" % (b["name"], key))
    meta = path[:-4] + ".json"
    if os.path.exists(path) and not retake:
        x, _ = sf.read(path)
        qa = json.load(open(meta, encoding="utf-8")) if os.path.exists(meta) else None
        return x, qa
    text, sit = tts_text(b["text"], v["lang"]), b["situation"]
    ref = display_text(b["text"])
    seed0 = int(hashlib.sha1(b["name"].encode()).hexdigest()[:6], 16) + 100003 * RESEED.get(b["name"], 0)
    cands = []
    if sit in NO_QA:
        for k in range(3):
            x = trim_bark(synth(text, v, seed0 + k * 7919))
            d = len(x) / SR
            cands.append((abs(d - 0.55) + (5.0 if d > DEATH_MAX else 0.0), d, x))
            log("    take %d: %.2fs" % (k, d))
        cands.sort(key=lambda c: c[0])
        _, d, x = cands[0]
        if d > DEATH_MAX:                       # abgebrochen: hart auf max. Laenge mit Ausblende
            n, f = int(DEATH_MAX * SR), int(0.12 * SR)
            x = x[:n].copy()
            x[-f:] *= np.linspace(1, 0, f) ** 2
        qa = {"wer": None, "asr": None}
    else:
        lim = max_dur(b["text"])
        for k in range(6):
            if k >= 3 and any(c[0] == 0.0 and c[4] for c in cands):
                break
            x = trim_bark(synth(text, v, seed0 + k * 7919))
            d = len(x) / SR
            hyp = transcribe(x, v["lang"])
            w = wer(ref, hyp, v["lang"])
            c = cut_tail(x, ref, v["lang"], w) if w < 1.0 else None
            if c:
                x, w, hyp = c
                d = len(x) / SR
            if sit in LOOSE_QA:
                w = 0.0 if w <= 0.5 else w
            mg = max_gap(x)
            ok = d <= lim and mg <= MAX_GAP + (0.2 if re.search(r"[,!?.—]\s+\S", ref) else 0.0)
            cands.append((w, d, x, hyp, ok))
            log("    take %d: WER %.2f  %.2fs (max %.2f) Luecke %.2fs  %s" % (k, w, d, lim, mg, hyp[:60]))
            if w == 0.0 and ok:
                break
        best = min(c[0] for c in cands)
        good = [c for c in cands if c[0] <= best + 1e-6]
        good.sort(key=lambda c: (not c[4], c[1]))   # Laenge/Pausen ok, dann der knappste Take
        w, d, x, hyp, _ = good[0]
        qa = {"wer": round(w, 3), "asr": hyp}
    sf.write(path, x, SR, subtype="FLOAT")
    json.dump(qa, open(meta, "w", encoding="utf-8"), ensure_ascii=False)
    return x, qa


def render(x, b, v):
    x = pitch_shift(x, v["pitch"])
    x = fft_filter(x, 90, 0, soft=1.0)                       # Trittschall/Rumpeln weg
    x = comp(norm_peak(x, 1.0), -18.0, 3.0, att=0.002, rel=0.08)   # gepresst, nach vorne
    if b["situation"] in RADIO:
        x = radio_fx(x, pad=(0.05, 0.16), heavy=False)       # Offizier am Funkgeraet
    else:
        f = int(0.003 * SR)
        x = x.copy()
        x[:f] *= np.linspace(0, 1, f)
    return loudness(x, LUFS.get(b["situation"], LUFS_DEFAULT))


# ------------------------------------------------------------------ Befehle

def selected(b, sel):
    if not sel:
        return True
    for s in sel:
        if b["name"] == s or b["name"].startswith(s + "_") or s in (b["faction"], b["vkey"], b["situation"]):
            return True
    return False


def gen(args):
    bl = plan()
    sel = [s for s in args.only.split(",") if s] if args.only else None
    os.makedirs(OUT, exist_ok=True)
    mpath = os.path.join(OUT, "manifest.json")
    manifest = json.load(open(mpath, encoding="utf-8")) if os.path.exists(mpath) else {}
    todo = [b for b in bl if selected(b, sel)]
    for i, b in enumerate(todo, 1):
        v = VOICES[b["vkey"]]
        dst = os.path.join(OUT, b["name"] + ".ogg")
        key = raw_key(b, v)
        if os.path.exists(dst) and not (args.force or args.retake) and manifest.get(b["name"], {}).get("key") == key:
            continue
        print("[%d/%d] %s  %s" % (i, len(todo), b["name"], display_text(b["text"])))
        x, qa = best_take(b, v, retake=args.retake)
        y = render(x, b, v)
        write_ogg(dst, y)
        manifest[b["name"]] = {"faction": b["faction"], "voice": b["voice"], "situation": b["situation"], "n": b["n"],
                               "text": display_text(b["text"]), "lang": v["lang"], "ref": v["ref"], "key": key,
                               "seconds": round(len(y) / SR, 2), "wer": (qa or {}).get("wer"), "asr": (qa or {}).get("asr")}
        print("   -> %.2fs" % (len(y) / SR))
    valid = {b["name"] for b in bl}
    for fn in os.listdir(OUT):
        if fn.endswith(".ogg") and fn[:-4] not in valid:
            os.remove(os.path.join(OUT, fn))
            if os.path.exists(os.path.join(OUT, fn + ".import")):
                os.remove(os.path.join(OUT, fn + ".import"))
            print("entfernt (nicht mehr im Plan):", fn)
    manifest = {k: manifest[k] for k in sorted(manifest) if k in valid}
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    report(bl, manifest)


def report(bl, manifest):
    miss = [b["name"] for b in bl if b["name"] not in manifest or not os.path.exists(os.path.join(OUT, b["name"] + ".ogg"))]
    by = {}
    for b in bl:
        by[b["vkey"]] = by.get(b["vkey"], 0) + 1
    print("\n%d Barks geplant, %d vorhanden, %d fehlen" % (len(bl), len(bl) - len(miss), len(miss)))
    print("  " + ", ".join("%s %d" % kv for kv in by.items()))
    for n in miss[:20]:
        print("  FEHLT", n)
    for k, m in manifest.items():
        if (m.get("wer") or 0) > 0.0:
            print("  WER %.2f  %-28s %s | %s" % (m["wer"], k, m["text"], m.get("asr")))
    long_ = [(m["seconds"], k) for k, m in manifest.items() if m["situation"] == "death" and m["seconds"] > DEATH_MAX + 0.05]
    for s, k in long_:
        print("  death zu lang: %s %.2fs" % (k, s))


SAMPLE_LIST = ["ru_v1_spot_1", "ru_off_order_reinf_1", "reich_v2_grenade_1", "ru_v3_mandown_1", "reich_off_order_mark_1"]


def samples(args):
    os.makedirs(SAMPLES, exist_ok=True)
    mpath = os.path.join(OUT, "manifest.json")
    manifest = json.load(open(mpath, encoding="utf-8")) if os.path.exists(mpath) else {}
    with open(os.path.join(SAMPLES, "README.txt"), "w", encoding="utf-8") as f:
        f.write("Hoerproben Gegner-Barks (tools/gen_barks.py --samples, Kopien aus assets/voice/barks/).\n\n")
        for n in SAMPLE_LIST:
            src = os.path.join(OUT, n + ".ogg")
            if os.path.exists(src):
                shutil.copy(src, os.path.join(SAMPLES, n + ".ogg"))
                m = manifest.get(n, {})
                f.write("%-24s %s  (%s)\n" % (n, m.get("text", ""), m.get("ref", "")))
                print("Probe", n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--retake", action="store_true")
    ap.add_argument("--samples", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.list:
        for b in plan():
            print("%-30s %s" % (b["name"], display_text(b["text"])))
        print(len(plan()), "Barks")
    elif args.samples:
        samples(args)
    else:
        gen(args)


if __name__ == "__main__":
    main()
