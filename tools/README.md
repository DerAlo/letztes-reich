# Test-Infrastruktur (fuer Claude)

Alle Befehle im Projektordner `D:\project_alo`. Godot: `tools/godot/Godot_v4.7.2-stable_win64_console.exe`.
Das Testlevel `../debug/_test_level` (Fake-Gegner, echter Player falls vorhanden) funktioniert ohne fertiges Level:
`--level ../debug/_test_level`. Es gibt `--blocked` (Wand im Weg, Stuck-Test), `--real-enemies`, `--fake-player`.

## 1. Rundenbasiert spielen (Fernsteuerung + Screenshots)
```
python tools/play.py start --level test_range        # Fenster 1280x720, pausiert, wartet auf Port 9123
python tools/play.py turn '{"move":[0,1],"sprint":true}' 2.0 captures/z1.png
python tools/play.py turn '{"look_at":[0,1.5,-30],"fire":true}' 1.0 captures/z2.png
python tools/play.py quit
```
- `turn '<json>' <sek> [shot.png]` = Input setzen, N Sekunden spielen, Input zuruecksetzen (ausser `"keep":true`),
  Screenshot, Status, Events, Gegnerliste (Distanz, Peilung `bearing` + = rechts, `visible`) in EINER JSON-Zeile.
  Extras im JSON: `look_at:[x,y,z]`, `view:[yaw,pitch]`, `keep:true`. Sonst Ext-Felder aus CONTRACTS.md
  (`move`, `look` Grad/s, `fire`, `aim`, `sprint`, `crouch`, `jump`, `reload`, `grenade`).
- Screenshot ansehen: vorher verkleinern
  `node C:/Users/snofl/.claude/plugins/cache/ww-w-ai/super-token-saver/3.6.1/scripts/shrink-img.js <png> --maxdim 800`,
  dann mit Read lesen. (`turn`/`shot` speichern standardmaessig schon 1024 px breit, `--width N` aendert das.)
- Einzelbefehle: `status`, `step 0.5`, `shot pfad.png`, `hold '{"move":[0,1],"duration":1}'`, `look_at x y z`,
  `set_view yaw pitch`, `enemies`, `events`, `level_info`, `teleport x y z`, `spawn rifleman x y z`,
  `explode x y z [radius]`, `timescale 2`, `pause`, `resume`, `cmd '<roh-json>'`, `stop` (Prozess hart beenden).
- Das Spiel steht zwischen den Zuegen still (`step` laeuft exakt N Sim-Sekunden). Zeit laeuft nur in `turn/step/hold`.
- Log: `tools/.play/godot.log`. Port belegt? `python tools/play.py stop` oder `quit`.
- Taktik: erst `status`/`enemies` lesen, mit `look_at` auf Gegner zielen, dann feuern. `bearing` ist der Winkel zum Gegner
  relativ zur Blickrichtung; mit `{"look":[bearing*2,0]}` fuer 0.5 s dreht man ca. dorthin (Grad/s).

## 2. Balancing simulieren (Bots, headless, Zeitraffer)
```
python tools/simulate.py --level test_range --runs 5 --skills novice,average,veteran --parallel 3 --timescale 4
```
Schreibt `telemetry/run_<ts>_<skill>_<i>.json` und `telemetry/summary.md` (Abschlussrate, mittlere Tode, Tode pro
Abschnitt, gefaehrlichster Gegner, Stuck-Hotspots, Dauer). Logs pro Lauf: `telemetry/logs/`.
Einzellauf direkt: `godot --headless --path . -- --level=test_range --autopilot --skill=average --timescale=4
--max-time=600 --max-deaths=10 [--out=pfad.json] [--ap-debug]`.
Ergebnisse: `completed`, `timeout`, `stuck`, `max_deaths`. Der Bot folgt `bot_waypoints`, nutzt `cover_point`s,
wirft Granaten auf Gruppen und loggt Stuck/Stall (kein Fortschritt 45 s).
Zeitraffer: Godot skaliert das Physics-Delta mit `time_scale`; deshalb setzt der DebugServer bei `--timescale=N`
auch `physics_ticks_per_second = 60*N` (stabiles dt = 1/60 Sim-Sekunde). Bei sehr hohem N limitiert die CPU.

## 3. Optik aufnehmen (Bewegungsablauf in einem Bild)
```
python tools/capture.py --name intro --seconds 12 --autopilot --skill veteran --level test_range
```
Movie-Writer (30 fps, Fenster 960x540) -> `captures/intro_sheet.png` (4x4 Raster, beschriftet mit Zeit/Frame).
Optionen: `--cols/--rows`, `--cell-width`, `--keep-frames`, `--sheet-only` (Raster aus vorhandenen Frames neu),
`--resolution`. Danach das Sheet mit shrink-img verkleinern und lesen. Benoetigt Pillow (bereits installiert).
Hinweis: Aufnahme laeuft langsamer als Echtzeit (Movie-Writer rendert jeden Frame).

## Allgemein
- Args gehen nach `--` ans Spiel (`Game.arg`): `--debug-server --start-paused --autopilot --skill= --timescale=
  --max-time= --max-deaths= --out= --seed= --ap-debug`.
- `captures/` und `telemetry/` enthalten eine `.gdignore` (Godot importiert dort keine PNGs).
