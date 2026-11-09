#!/usr/bin/env python3
"""CLI-Client fuer den DebugServer (rundenbasiertes Spielen). Nur Standardbibliothek, Python 3.9.

Beispiele:
  python tools/play.py start --level test_range
  python tools/play.py status
  python tools/play.py turn '{"move":[0,1],"fire":true}' 1.5 captures/t1.png
  python tools/play.py look_at 0 1.5 -20
  python tools/play.py quit
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GODOT = os.path.join(ROOT, "tools", "godot", "Godot_v4.7.2-stable_win64_console.exe")
STATE_DIR = os.path.join(ROOT, "tools", ".play")
PID_FILE = os.path.join(STATE_DIR, "godot.pid")
LOG_FILE = os.path.join(STATE_DIR, "godot.log")
HOST, PORT = "127.0.0.1", 9123
NEUTRAL = {"move": [0, 0], "look": [0, 0], "fire": False, "aim": False, "sprint": False, "crouch": False}


def out(obj):
    print(json.dumps(obj, separators=(",", ":"), ensure_ascii=False))


def abspath(p):
    return p if os.path.isabs(p) else os.path.join(ROOT, p)


class Client:
    def __init__(self, timeout=300.0):
        self.sock = socket.create_connection((HOST, PORT), timeout=5)
        self.sock.settimeout(timeout)
        self.buf = b""

    def call(self, cmd, **kw):
        d = {"cmd": cmd}
        d.update(kw)
        self.sock.sendall((json.dumps(d) + "\n").encode("utf-8"))
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("Server hat die Verbindung geschlossen")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line.decode("utf-8"))

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def port_open():
    try:
        s = socket.create_connection((HOST, PORT), timeout=0.5)
        s.close()
        return True
    except OSError:
        return False


def pid_alive(pid):
    try:
        r = subprocess.run(["tasklist", "/FI", "PID eq %d" % pid, "/NH"], capture_output=True)
        return str(pid) in r.stdout.decode("utf-8", errors="replace")
    except Exception:
        return False


def cmd_start(a):
    if port_open():
        out({"ok": False, "error": "Port %d ist schon belegt (laeuft Godot schon? 'quit' oder 'stop')" % PORT})
        return 1
    os.makedirs(STATE_DIR, exist_ok=True)
    args = [GODOT, "--path", ROOT, "--resolution", a.resolution, "--windowed", "--position", "40,40"]
    args += ["--", "--debug-server", "--level=" + a.level]
    if not a.run:
        args.append("--start-paused")
    args += a.extra
    log = open(LOG_FILE, "w")
    flags = 0
    if os.name == "nt":
        flags = 0x00000008 | 0x00000200  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    p = subprocess.Popen(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, creationflags=flags)
    with open(PID_FILE, "w") as f:
        f.write(str(p.pid))
    t0 = time.time()
    while time.time() - t0 < a.timeout:
        if p.poll() is not None:
            out({"ok": False, "error": "Godot beendet (exit %s), siehe %s" % (p.returncode, LOG_FILE), "log_tail": tail_log()})
            return 1
        if port_open():
            time.sleep(0.3)
            try:
                c = Client(30)
                r = c.call("status")
                c.close()
            except Exception as e:  # noqa
                r = {"ok": False, "error": str(e)}
            r["pid"] = p.pid
            r["log"] = LOG_FILE
            out(r)
            return 0
        time.sleep(0.25)
    out({"ok": False, "error": "Timeout beim Warten auf Port", "log_tail": tail_log()})
    return 1


def tail_log(n=15):
    try:
        with open(LOG_FILE, "r", errors="replace") as f:
            return f.read().splitlines()[-n:]
    except OSError:
        return []


def kill_pid():
    if not os.path.exists(PID_FILE):
        return False
    try:
        pid = int(open(PID_FILE).read().strip())
    except ValueError:
        return False
    if pid_alive(pid):
        subprocess.run(["taskkill", "/PID", str(pid), "/T", "/F"], capture_output=True)
        return True
    return False


def cmd_quit(a):
    try:
        c = Client(10)
        r = c.call("quit")
        c.close()
    except Exception as e:  # noqa
        r = {"ok": False, "error": str(e)}
    # Prozess aufraeumen
    time.sleep(1.0)
    killed = False
    if os.path.exists(PID_FILE):
        try:
            pid = int(open(PID_FILE).read().strip())
            if pid_alive(pid):
                killed = kill_pid()
        except ValueError:
            pass
        try:
            os.remove(PID_FILE)
        except OSError:
            pass
    r["killed"] = killed
    out(r)
    return 0


def cmd_stop(a):
    killed = kill_pid()
    out({"ok": True, "killed": killed})
    return 0


def parse_json(s):
    try:
        v = json.loads(s)
        if not isinstance(v, dict):
            raise ValueError("Objekt erwartet")
        return v
    except ValueError as e:
        out({"ok": False, "error": "JSON ungueltig: %s" % e})
        sys.exit(2)


def compact_status(st):
    """Kompakte Statusansicht fuer 'turn'."""
    p = st.get("player") or {}
    r = {"t": st.get("time"), "paused": st.get("paused")}
    for k in ("alive", "health", "position", "yaw", "pitch", "weapon", "ammo_mag", "ammo_reserve", "grenades", "reloading"):
        if k in p:
            r[k] = p[k]
    r["enemies_alive"] = st.get("enemies_alive")
    if st.get("checkpoint"):
        r["checkpoint"] = st["checkpoint"]
    if st.get("level_completed"):
        r["level_completed"] = True
    return r


def cmd_turn(a):
    spec = parse_json(a.json)
    secs = float(a.seconds)
    keep = bool(spec.pop("keep", False))
    look_at = spec.pop("look_at", None)
    view = spec.pop("view", None)
    c = Client()
    res = {"ok": True}
    try:
        if look_at:
            r = c.call("look_at", x=look_at[0], y=look_at[1], z=look_at[2])
            if not r.get("ok"):
                out(r)
                return 1
        if view:
            r = c.call("set_view", yaw=view[0], pitch=view[1])
            if not r.get("ok"):
                out(r)
                return 1
        base = dict(NEUTRAL)
        base.update(spec)
        r = c.call("input", **base)
        if not r.get("ok"):
            out(r)
            return 1
        c.call("events")  # Events vor dem Zug verwerfen
        r = c.call("step", seconds=secs)
        if not r.get("ok"):
            out(r)
            return 1
        if not keep:
            c.call("input", **NEUTRAL)
        if a.shot:
            s = c.call("screenshot", path=abspath(a.shot), width=a.width)
            res["shot"] = s.get("path") if s.get("ok") else {"error": s.get("error")}
        st = c.call("status")
        res["status"] = compact_status(st)
        ev = c.call("events")
        res["events"] = ev.get("events", [])
        res["summary"] = ev.get("summary", {})
        en = c.call("enemies")
        if en.get("ok"):
            res["enemies"] = [
                {k: e[k] for k in ("type", "dist", "bearing", "elev", "visible", "health", "state") if k in e}
                for e in en["enemies"][:8]
            ]
    finally:
        c.close()
    out(res)
    return 0


def run_cmd(d, timeout=300.0):
    c = Client(timeout)
    try:
        return c.call(**d)
    finally:
        c.close()


def main():
    ap = argparse.ArgumentParser(description="Fernsteuerung fuer Letztes Reich (DebugServer)")
    sub = ap.add_subparsers(dest="sub")

    s = sub.add_parser("start", help="Godot mit --debug-server --start-paused starten")
    s.add_argument("--level", default="test_range")
    s.add_argument("--resolution", default="1280x720")
    s.add_argument("--timeout", type=float, default=90.0)
    s.add_argument("--run", action="store_true", help="nicht pausiert starten")
    s.add_argument("extra", nargs="*", help="weitere User-Args, z.B. --autopilot")

    sub.add_parser("quit", help="Spiel beenden")
    sub.add_parser("stop", help="Godot-Prozess hart beenden")

    s = sub.add_parser("cmd", help="Rohbefehl als JSON")
    s.add_argument("json")

    for n in ("status", "enemies", "events", "level_info", "pause", "resume"):
        sub.add_parser(n)

    s = sub.add_parser("step")
    s.add_argument("seconds", type=float)
    s = sub.add_parser("shot")
    s.add_argument("path")
    s.add_argument("--width", type=int, default=1024)
    s = sub.add_parser("hold", help='hold \'{"move":[0,1],"fire":true,"duration":1.0}\'')
    s.add_argument("json")
    s = sub.add_parser("look_at")
    s.add_argument("x", type=float)
    s.add_argument("y", type=float)
    s.add_argument("z", type=float)
    s = sub.add_parser("set_view")
    s.add_argument("yaw", type=float)
    s.add_argument("pitch", type=float)
    s = sub.add_parser("timescale")
    s.add_argument("value", type=float)
    s = sub.add_parser("teleport")
    s.add_argument("x", type=float)
    s.add_argument("y", type=float)
    s.add_argument("z", type=float)
    s = sub.add_parser("spawn")
    s.add_argument("type")
    s.add_argument("x", type=float)
    s.add_argument("y", type=float)
    s.add_argument("z", type=float)
    s = sub.add_parser("explode")
    s.add_argument("x", type=float)
    s.add_argument("y", type=float)
    s.add_argument("z", type=float)
    s.add_argument("radius", type=float, nargs="?", default=6.0)

    s = sub.add_parser("turn", help="Input setzen, N Sekunden spielen, Screenshot+Status+Events")
    s.add_argument("json", help='Ext-Input, z.B. \'{"move":[0,1],"fire":true}\'; Extras: look_at:[x,y,z], view:[yaw,pitch], keep:true')
    s.add_argument("seconds", type=float)
    s.add_argument("shot", nargs="?", default=None)
    s.add_argument("--width", type=int, default=1024)

    a = ap.parse_args()
    if not a.sub:
        ap.print_help()
        return 2
    try:
        if a.sub == "start":
            return cmd_start(a)
        if a.sub == "quit":
            return cmd_quit(a)
        if a.sub == "stop":
            return cmd_stop(a)
        if a.sub == "turn":
            return cmd_turn(a)
        if a.sub == "cmd":
            d = parse_json(a.json)
            out(run_cmd(d))
            return 0
        if a.sub == "shot":
            out(run_cmd({"cmd": "screenshot", "path": abspath(a.path), "width": a.width}))
            return 0
        if a.sub == "hold":
            d = parse_json(a.json)
            d["cmd"] = "hold"
            out(run_cmd(d))
            return 0
        if a.sub == "step":
            out(run_cmd({"cmd": "step", "seconds": a.seconds}))
            return 0
        kw = {k: v for k, v in vars(a).items() if k != "sub"}
        kw["cmd"] = a.sub
        out(run_cmd(kw))
        return 0
    except (ConnectionError, OSError) as e:
        out({"ok": False, "error": "Keine Verbindung zum DebugServer (%s). Zuerst: python tools/play.py start" % e})
        return 1


if __name__ == "__main__":
    sys.exit(main())
