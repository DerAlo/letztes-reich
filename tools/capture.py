#!/usr/bin/env python3
"""Movie-Writer-Aufnahme + Kontaktabzug (Raster aus gleichmaessig verteilten Frames).

  python tools/capture.py --name intro --seconds 12 --autopilot --level test_range
  -> captures/intro/f########.png (Frames) und captures/intro_sheet.png (4x4 Kontaktabzug)
Benoetigt Pillow (python -m pip install --user pillow).
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:  # pragma: no cover
    print("Pillow fehlt: python -m pip install --user pillow", file=sys.stderr)
    sys.exit(2)

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GODOT = os.path.join(ROOT, "tools", "godot", "Godot_v4.7.2-stable_win64_console.exe")


def make_sheet(frames, out_path, cols, rows, cell_w, fps, start_index=0):
    n = cols * rows
    if len(frames) <= n:
        picks = list(range(len(frames)))
    else:
        picks = [round(i * (len(frames) - 1) / (n - 1)) for i in range(n)]
    first = Image.open(frames[0])
    cell_h = int(round(cell_w * first.height / first.width))
    sheet = Image.new("RGB", (cols * cell_w, rows * cell_h), (20, 20, 20))
    for slot, idx in enumerate(picks):
        im = Image.open(frames[idx]).convert("RGB").resize((cell_w, cell_h), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        label = "t=%.1fs #%d" % (idx / float(fps), idx)
        d.rectangle([0, 0, 8 * len(label) + 6, 14], fill=(0, 0, 0))
        d.text((3, 1), label, fill=(255, 255, 0))
        sheet.paste(im, ((slot % cols) * cell_w, (slot // cols) * cell_h))
    sheet.save(out_path)
    return picks


def main():
    ap = argparse.ArgumentParser(description="Sequenz aufnehmen und Kontaktabzug erzeugen")
    ap.add_argument("--name", default="seq")
    ap.add_argument("--level", default="test_range")
    ap.add_argument("--seconds", type=float, default=10.0, help="Aufnahmedauer (Spielzeit)")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--resolution", default="960x540")
    ap.add_argument("--autopilot", action="store_true")
    ap.add_argument("--skill", default="average")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--rows", type=int, default=4)
    ap.add_argument("--cell-width", type=int, default=480)
    ap.add_argument("--keep-frames", action="store_true", help="alle Frames behalten (sonst nur die Kontaktabzug-Frames)")
    ap.add_argument("--sheet-only", action="store_true", help="nur Kontaktabzug aus vorhandenen Frames bauen")
    ap.add_argument("--timeout", type=float, default=600.0)
    ap.add_argument("extra", nargs="*", help="weitere User-Args fuers Spiel")
    a = ap.parse_args()

    cap_dir = os.path.join(ROOT, "captures", a.name)
    if not a.sheet_only:
        if os.path.isdir(cap_dir):
            shutil.rmtree(cap_dir)
        os.makedirs(cap_dir)
        frames_total = int(round(a.seconds * a.fps))
        args = [GODOT, "--path", ROOT, "--windowed", "--resolution", a.resolution, "--position", "40,40",
                "--write-movie", os.path.join(cap_dir, "f.png"), "--fixed-fps", str(a.fps),
                "--quit-after", str(frames_total), "--"]
        args += ["--level=" + a.level]
        if a.autopilot:
            args += ["--autopilot", "--skill=" + a.skill, "--out=" + os.path.join("captures", a.name, "telemetry.json")]
        args += a.extra
        print("Nehme %d Frames auf..." % frames_total, file=sys.stderr)
        log = os.path.join(cap_dir, "godot.log")
        with open(log, "w") as lf:
            try:
                subprocess.run(args, cwd=ROOT, stdout=lf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, timeout=a.timeout)
            except subprocess.TimeoutExpired:
                print("Timeout, verwende vorhandene Frames", file=sys.stderr)
    frames = sorted(glob.glob(os.path.join(cap_dir, "f*.png")))
    if not frames:
        print("Keine Frames erzeugt, siehe %s" % os.path.join(cap_dir, "godot.log"), file=sys.stderr)
        return 1
    sheet_path = os.path.join(ROOT, "captures", a.name + "_sheet.png")
    picks = make_sheet(frames, sheet_path, a.cols, a.rows, a.cell_width, a.fps)
    if not a.keep_frames and not a.sheet_only:
        keep = set(picks)
        for i, f in enumerate(frames):
            if i not in keep:
                os.remove(f)
    for wav in glob.glob(os.path.join(cap_dir, "*.wav")):
        os.remove(wav)
    print("Frames: %d, Kontaktabzug: %s (%d Bilder)" % (len(frames), sheet_path, len(picks)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
