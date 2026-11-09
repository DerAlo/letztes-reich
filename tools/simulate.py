#!/usr/bin/env python3
"""Bot-Laeufe (headless, Zeitraffer) fuer Balancing. Nur Standardbibliothek, Python 3.9.

  python tools/simulate.py --runs 3 --skills novice,average,veteran --parallel 3 --level test_range
Telemetrie: telemetry/run_<ts>_<skill>_<i>.json, Bericht: telemetry/summary.md
"""
import argparse
import collections
import concurrent.futures as cf
import glob
import json
import os
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GODOT = os.path.join(ROOT, "tools", "godot", "Godot_v4.7.2-stable_win64_console.exe")
TEL = os.path.join(ROOT, "telemetry")


def run_one(skill, idx, ts, a):
    out_file = os.path.join(TEL, "run_%s_%s_%d.json" % (ts, skill, idx))
    log_dir = os.path.join(TEL, "logs")
    os.makedirs(log_dir, exist_ok=True)
    log_file = os.path.join(log_dir, "run_%s_%s_%d.log" % (ts, skill, idx))
    args = [GODOT, "--headless", "--path", ROOT, "--"]
    args += ["--level=" + a.level, "--autopilot", "--skill=" + skill, "--timescale=%g" % a.timescale,
             "--max-time=%g" % a.max_time, "--max-deaths=%d" % a.max_deaths, "--out=" + out_file,
             "--seed=%d" % (a.seed + idx * 101 + sum(map(ord, skill)) % 97)]
    args += a.extra
    t0 = time.time()
    status = "ok"
    with open(log_file, "w") as lf:
        try:
            p = subprocess.run(args, cwd=ROOT, stdout=lf, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                               timeout=a.real_timeout)
            if p.returncode != 0:
                status = "exit%d" % p.returncode
        except subprocess.TimeoutExpired:
            status = "real_timeout"
    data = None
    if os.path.exists(out_file):
        try:
            with open(out_file, "r") as f:
                data = json.load(f)
        except ValueError:
            data = None
    if data is None:
        data = {"skill": skill, "result": "crash" if status != "real_timeout" else "real_timeout", "duration_sim": 0,
                "deaths": [], "death_count": 0, "damage_taken_by_type": {}, "kills_by_type": {}, "stuck_events": [],
                "section_times": {}, "section_deaths": {}, "shots": 0, "hits": 0, "accuracy": 0.0,
                "grenades_thrown": 0, "fps": None}
    data["_wall"] = round(time.time() - t0, 1)
    data["_file"] = os.path.relpath(out_file, ROOT)
    data["_log"] = os.path.relpath(log_file, ROOT)
    data["_status"] = status
    return data


def mean(xs):
    xs = list(xs)
    return sum(xs) / len(xs) if xs else 0.0


def hotspots(runs, cell=3.0, top=5):
    c = collections.Counter()
    for r in runs:
        for s in r.get("stuck_events", []):
            p = s.get("pos", [0, 0, 0])
            c[(round(p[0] / cell) * cell, round(p[2] / cell) * cell)] += 1
    return ["(%.0f, %.0f) x%d" % (k[0], k[1], v) for k, v in c.most_common(top)]


def build_report(all_runs, a, ts):
    by_skill = collections.OrderedDict()
    for r in all_runs:
        by_skill.setdefault(r["skill"], []).append(r)
    lines = []
    lines.append("# Balancing-Bericht (%s)" % ts)
    lines.append("")
    lines.append("Level `%s`, %d Lauf/Laeufe pro Skill, timescale %g, max-time %gs, max-deaths %d" %
                 (a.level, a.runs, a.timescale, a.max_time, a.max_deaths))
    lines.append("")
    lines.append("| Skill | Laeufe | Abschluss | mittl. Tode | mittl. Dauer (s) | Accuracy | Granaten | Ergebnisse | gefaehrlichster Gegner | Stuck |")
    lines.append("|---|---|---|---|---|---|---|---|---|---|")
    details = []
    for skill, runs in by_skill.items():
        n = len(runs)
        comp = sum(1 for r in runs if r["result"] == "completed")
        res = collections.Counter(r["result"] for r in runs)
        dmg = collections.Counter()
        cause = collections.Counter()
        for r in runs:
            for k, v in r.get("damage_taken_by_type", {}).items():
                dmg[k] += v
            for d in r.get("deaths", []):
                cause[d.get("cause", "?")] += 1
        if cause:
            danger = "%s (%d Tode)" % cause.most_common(1)[0]
        elif dmg:
            danger = "%s (%.0f Schaden)" % dmg.most_common(1)[0]
        else:
            danger = "-"
        stuck_n = sum(len(r.get("stuck_events", [])) for r in runs)
        lines.append("| %s | %d | %d%% | %.1f | %.0f | %.0f%% | %.1f | %s | %s | %d |" % (
            skill, n, round(100.0 * comp / n), mean(r.get("death_count", 0) for r in runs),
            mean(r.get("duration_sim", 0) for r in runs), 100 * mean(r.get("accuracy", 0) for r in runs),
            mean(r.get("grenades_thrown", 0) for r in runs),
            ", ".join("%s:%d" % kv for kv in res.items()), danger, stuck_n))
        # Details
        sec_deaths = collections.Counter()
        sec_time = collections.defaultdict(list)
        order = []
        for r in runs:
            for k, v in r.get("section_deaths", {}).items():
                sec_deaths[k] += v
            for k, v in r.get("section_times", {}).items():
                sec_time[k].append(v)
                if k not in order:
                    order.append(k)
        for k in sec_deaths:
            if k not in order:
                order.append(k)
        d = ["", "### %s" % skill, ""]
        d.append("Tode pro Abschnitt (Summe / Zeit mittl.): " + (", ".join(
            "%s: %d / %.0fs" % (k, sec_deaths.get(k, 0), mean(sec_time.get(k, []))) for k in order) or "-"))
        d.append("Schaden nach Typ (Summe): " + (", ".join("%s %.0f" % kv for kv in dmg.most_common()) or "-"))
        kills = collections.Counter()
        for r in runs:
            for k, v in r.get("kills_by_type", {}).items():
                kills[k] += v
        d.append("Kills (Summe): " + (", ".join("%s %d" % kv for kv in kills.most_common()) or "-"))
        d.append("Todesursachen: " + (", ".join("%s %d" % kv for kv in cause.most_common()) or "-"))
        hs = hotspots(runs)
        d.append("Stuck-Hotspots (x,z): " + (", ".join(hs) or "keine"))
        fps = [r["fps"]["avg"] for r in runs if r.get("fps")]
        if fps:
            d.append("FPS avg: %.0f, min: %.0f" % (mean(fps), min(r["fps"]["min"] for r in runs if r.get("fps"))))
        bad = [r for r in runs if r.get("_status") != "ok"]
        if bad:
            d.append("Probleme: " + ", ".join("%s (%s, Log %s)" % (r["_file"], r["_status"], r["_log"]) for r in bad))
        d.append("Dateien: " + ", ".join(os.path.basename(r["_file"]) for r in runs))
        details.extend(d)
    lines.extend(details)
    lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="Bot-Simulation fuer Balancing")
    ap.add_argument("--level", default="test_range")
    ap.add_argument("--runs", type=int, default=3, help="Laeufe pro Skill")
    ap.add_argument("--skills", default="novice,average,veteran")
    ap.add_argument("--parallel", type=int, default=3)
    ap.add_argument("--timescale", type=float, default=4.0)
    ap.add_argument("--max-time", type=float, default=600.0, help="Sim-Sekunden")
    ap.add_argument("--max-deaths", type=int, default=15)
    ap.add_argument("--real-timeout", type=float, default=1200.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("extra", nargs="*", help="weitere User-Args fuers Spiel")
    a = ap.parse_args()

    os.makedirs(TEL, exist_ok=True)
    ts = time.strftime("%Y%m%d_%H%M%S")
    jobs = [(s, i) for s in a.skills.split(",") for i in range(a.runs)]
    print("Starte %d Laeufe (%d parallel)..." % (len(jobs), a.parallel), file=sys.stderr)
    results = []
    with cf.ThreadPoolExecutor(max_workers=max(1, a.parallel)) as ex:
        futs = {ex.submit(run_one, s, i, ts, a): (s, i) for s, i in jobs}
        for f in cf.as_completed(futs):
            r = f.result()
            results.append(r)
            print("  fertig: %s -> %s, Tode %s, %ss sim, %ss real" % (
                r["_file"], r["result"], r.get("death_count"), r.get("duration_sim"), r["_wall"]), file=sys.stderr)
    results.sort(key=lambda r: (r["skill"], r["_file"]))
    report = build_report(results, a, ts)
    with open(os.path.join(TEL, "summary.md"), "w", encoding="utf-8") as f:
        f.write(report)
    print(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
