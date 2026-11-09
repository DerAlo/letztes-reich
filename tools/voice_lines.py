#!/usr/bin/env python3
"""Sammelt alle gesprochenen Zeilen des Spiels aus den GDScript-Quellen (ohne Abhaengigkeiten).

  python tools/voice_lines.py            # Tabelle ausgeben
  python tools/voice_lines.py --json     # nach tools/voice_lines.json schreiben

Quellen:
  * game/story/story_data.gd   SCRIPTS ([WEBER, "..."]), BRIEFINGS ("lvl": "..."), ENDING (["...", sek])
  * game/**/*.gd               _say(<sprecher>, "...") / _radio(<sprecher>, "...") / story_radio.emit(<sprecher>, "...")
Sprecher-Ausdruecke: "Literal", SD.X / StoryData.X (Konstante in story_data.gd) oder lokale const der Datei.

ID = sha1(speaker + "|" + text)[:12] (UTF-8) – identisch mit StoryUI.voice_id() im Spiel.
Briefings laufen mit speaker "Lage", das Ende mit speaker "Kerner" (siehe main.gd).
"""
import hashlib
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
STORY_DATA = os.path.join(ROOT, "game", "story", "story_data.gd")
OUT_JSON = os.path.join(ROOT, "tools", "voice_lines.json")

BRIEFING_SPEAKER = "Lage"
ENDING_SPEAKER = "Kerner"

STR = r'"((?:[^"\\]|\\.)*)"'
CALL_RE = re.compile(r'(?:\b_say|\b_radio|story_radio\.emit)\(\s*([A-Za-z_][\w.]*|' + STR + r')\s*,\s*' + STR)
CONST_RE = re.compile(r'^const\s+([A-Z_][A-Z0-9_]*)\s*(?::\s*\w+\s*)?:?=\s*' + STR, re.M)


def unescape(s):
    return re.sub(r'\\(.)', lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def voice_id(speaker, text):
    return hashlib.sha1((speaker + "|" + text).encode("utf-8")).hexdigest()[:12]


def character_of(speaker):
    """Sprecher-String -> Figur (Casting-Schluessel)."""
    s = speaker.lower()
    if speaker == BRIEFING_SPEAKER:
        return "lage"
    for key, ch in (("weber", "weber"), ("aksoy", "lena"), ("lena", "lena"), ("lautsprecher", "riedhammer"),
                    ("riedhammer", "riedhammer"), ("ordnungsfront", "riedhammer"), ("rednerin", "rednerin"), ("kerner", "kerner")):
        if key in s:
            return ch
    return "funker"


def _block(src, name):
    """Text des const-Blocks NAME := { ... } bzw. [ ... ] (Klammerzaehlung, Strings beachtet)."""
    m = re.search(r'^const\s+' + name + r'\s*:?=\s*([\[{])', src, re.M)
    if not m:
        return ""
    i, depth, in_str = m.start(1), 0, False
    j = i
    while j < len(src):
        c = src[j]
        if in_str:
            if c == "\\":
                j += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
            if depth == 0:
                return src[i:j + 1]
        j += 1
    return src[i:]


def collect():
    with open(STORY_DATA, encoding="utf-8") as f:
        sd_src = f.read()
    sd_consts = {k: unescape(v) for k, v in CONST_RE.findall(sd_src)}
    lines = []
    seen = set()

    def add(speaker, text, source):
        key = (speaker, text)
        if key in seen:
            return
        seen.add(key)
        lines.append({"id": voice_id(speaker, text), "speaker": speaker, "character": character_of(speaker),
                      "text": text, "source": source})

    # story_data: SCRIPTS
    scripts = _block(sd_src, "SCRIPTS")
    for m in re.finditer(r'\[\s*([A-Z_]+)\s*,\s*' + STR + r'\s*\]', scripts):
        add(sd_consts.get(m.group(1), m.group(1)), unescape(m.group(2)), "story_data.SCRIPTS")
    # BRIEFINGS
    for m in re.finditer(STR + r'\s*:\s*' + STR, _block(sd_src, "BRIEFINGS")):
        add(BRIEFING_SPEAKER, unescape(m.group(2)), "story_data.BRIEFINGS:" + m.group(1))
    # ENDING
    for m in re.finditer(r'\[\s*' + STR + r'\s*,\s*[\d.]+\s*\]', _block(sd_src, "ENDING")):
        add(ENDING_SPEAKER, unescape(m.group(1)), "story_data.ENDING")

    # Level-/Story-Skripte
    for dirpath, _dirs, files in os.walk(os.path.join(ROOT, "game")):
        for fn in sorted(files):
            if not fn.endswith(".gd"):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, encoding="utf-8") as f:
                src = f.read()
            local = {k: unescape(v) for k, v in CONST_RE.findall(src)}
            rel = os.path.relpath(path, ROOT).replace("\\", "/")
            for m in CALL_RE.finditer(src):
                expr, lit, text = m.group(1), m.group(2), unescape(m.group(3))
                if lit is not None:
                    speaker = unescape(lit)
                else:
                    name = expr.split(".")[-1]
                    if expr.startswith(("SD.", "StoryData.")):
                        speaker = sd_consts.get(name)
                    else:
                        speaker = local.get(name)
                if speaker is None:
                    continue   # dynamischer Sprecher (z. B. Funktionsparameter) -> kein fester Text
                line_no = src.count("\n", 0, m.start()) + 1
                add(speaker, text, "%s:%d" % (rel, line_no))
    return lines


def main():
    lines = collect()
    if "--json" in sys.argv:
        with open(OUT_JSON, "w", encoding="utf-8") as f:
            json.dump(lines, f, ensure_ascii=False, indent=1)
        print("%d Zeilen -> %s" % (len(lines), OUT_JSON))
    else:
        for l in lines:
            print("%s  %-8s %-28s %s" % (l["id"], l["character"], l["speaker"][:28], l["text"][:90]))
        print(len(lines), "Zeilen")


if __name__ == "__main__":
    main()
