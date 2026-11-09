# Letztes Reich – Prototyp-Schnittstellen

Engine: **Godot 4.7.2** (Forward+, Jolt Physics), GDScript mit statischen Typen.
Godot-Binary: `tools/godot/Godot_v4.7.2-stable_win64_console.exe` (Console-Variante für Logs).
Start: `res://game/main.tscn` lädt `res://game/levels/<--level>.tscn` (Default `test_range`).
User-Args nach `--`, abrufbar per `Game.arg("key", default)`. Beispiel:
`godot --path . -- --level=test_range --autopilot --skill=novice`

## Ordner-Besitz (jeder Agent schreibt NUR in seine Ordner)
| Agent | Ordner |
|---|---|
| Player & Waffen | `game/player/`, `game/weapons/`, `game/ui/` |
| Gegner & KI | `game/enemies/` |
| VFX, Level, Umgebung | `game/vfx/`, `game/levels/`, `game/core/combat.gd`, `assets/` |
| Test-Infra | `game/debug/`, `tools/` (außer `tools/godot`), `telemetry/`, `captures/` |

**Runde 2 (aktuell):**
| Agent | Ordner |
|---|---|
| Waffe & Sound-Waffen | `game/player/`, `game/weapons/`, `game/ui/`, `assets/weapons/`, `assets/sfx/` nur Dateien der Player/Waffen-Hooks |
| Rauch & Sound-Welt | `game/vfx/`, `game/core/combat.gd`, `assets/vfx/`, `assets/sfx/` alle übrigen Hooks (Explosion, Gegner, Drohne, Ambient, Einschläge) |
| Gegner-Optik | `game/enemies/`, `assets/characters/` |
| Level 2 (Nacht/Schnee) | `game/levels/` (neue Dateien; `test_range` nicht kaputt machen), `game/main.gd` (Level-Abfolge), `assets/environment/` |
`assets/CREDITS.md`: jeder darf **anhängen** (eigener Abschnitt), nichts löschen.

`game/core/game.gd`, `game/core/events.gd`, `project.godot`: nur der Lead ändert. Brauchst du dort etwas, schreib es in deinen Abschlussbericht.

## Autoloads (existieren bereits)
- `Game`: `arg(key, default)`, `get_player()`, Input-Actions: `move_forward/back/left/right, jump, sprint, crouch, reload, grenade, interact, pause, fire (LMB), aim (RMB)`
- `Events`: Signale `player_damaged(amount, source)`, `player_died`, `player_respawned`, `enemy_damaged(enemy, amount)`, `enemy_killed(enemy)`, `explosion(position, radius, strength)`, `weapon_fired(weapon)`, `checkpoint_reached(id)`, `level_completed`
- `Combat`: `explode(position, radius=6.0, damage=120.0, source=null, visual_scale=1.0)`. Macht Schaden mit linearem Abfall an allen `damageable` im Radius (mit Sichtlinien-Check), gibt RigidBodies einen Impuls, ruft `VFX.spawn_explosion` und emittiert `Events.explosion`.
- `VFX`: `spawn_explosion(pos, scale=1.0)`, `spawn_impact(pos, normal, surface="concrete")`, `spawn_blood(pos, normal)`
- `DebugServer`: TCP-Fernsteuerung, siehe unten

## Physik-Layer
1 `world` (Level-Geometrie, Deckung), 2 `player`, 3 `enemy`, 4 `debris` (Trümmer, kollidiert nur mit world).
Hitscan-Raycasts treffen die Maske world+player+enemy.

## Gruppen
- `player`: genau ein Player-Node
- `enemy`: alle lebenden Gegner
- `damageable`: alles, was Schaden nehmen kann (Player, Gegner, explodierende Fässer, zerstörbare Props)
- `enemy_spawn`: Marker3D im Level; Meta `enemy_type` ∈ {`rifleman`,`heavy`,`drone`}, optional Meta `wave` (int, Default 0)
- `player_spawn`: Marker3D für den Spieler-Start
- `cover_point`: Marker3D an Deckungspositionen (die Gegner-KI darf sie nutzen; das Level setzt sie)

## Schadens-Schnittstelle (Duck-Typing)
Jeder `damageable` hat:
```gdscript
func take_damage(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void
func is_alive() -> bool
```

## Player (`res://game/player/player.tscn`, `class_name Player`, CharacterBody3D)
- Gruppe `player` und `damageable`, Layer 2
- Gesundheit regeneriert wie bei CoD, `max_health = 100`
- Kamera als `Camera3D`, abrufbar über `get_camera() -> Camera3D`
- Shake: hört auf `Events.explosion`, Stärke nach Distanz; dazu `add_trauma(amount: float)`
- **Externe Steuerung** (für Bot und Debug-Server):
  ```gdscript
  var external_input: bool = false   # true = Maus/Tastatur ignorieren
  var ext := {
    "move": Vector2.ZERO,   # x = strafe rechts(+), y = vorwärts(+), Länge <= 1
    "look": Vector2.ZERO,   # Grad pro Sekunde (x = yaw rechts+, y = pitch hoch+), wird intern * delta angewandt
    "fire": false, "aim": false, "sprint": false, "crouch": false,
    "jump": false, "reload": false, "grenade": false,  # jump/reload/grenade: auf true setzen = einmal auslösen, Player setzt zurück
    "prone": false,         # Zustand: true = hinlegen (Augenhöhe ~0.35 m), false = aufstehen (nur wenn oben Platz)
    # optional: "weapon": 1|2 -> Waffe wählen (Gewehr/Pistole, mit Wegstecken/Ziehen ~0.5 s), wird zurückgesetzt
  }
  # Automatisch, ohne eigene Schlüssel:
  #  - Slide: crouch-Flanke (false->true) während sprint + vorwärts am Boden -> 0.9 s Rutschen, endet geduckt;
  #    jump bricht ab (behält Schwung)
  #  - Mantle: jump vor einer Kante bis 1.6 m (auch in der Luft, solange jump < 0.6 s her) -> hochziehen 0.4–0.6 s
  #  - Step-up: Absätze bis 0.35 m werden ohne Sprung überwunden
  func set_view(yaw_deg: float, pitch_deg: float) -> void   # sofort setzen
  func look_at_point(p: Vector3) -> void                    # sofort zielen
  func get_status() -> Dictionary
  # {alive, health, max_health, position:[x,y,z], yaw, pitch, weapon, weapon_index (1|2), ammo_mag, ammo_reserve,
  #  grenades, reloading, aiming, stance ("stand"|"crouch"|"prone"), prone, sliding, mantling}
  var is_crouching: bool   # true bei geduckt, liegend oder rutschend (Gegner werten das wie Ducken)
  ```
- Tasten (InputMap in `game/core/game.gd`): `prone` = Z (physisch + logisch) bzw. C lange halten,
  `weapon_1`/`weapon_2` = 1/2, `weapon_next`/`weapon_prev` = Mausrad, `weapon_last` = Q
- Respawn am letzten Checkpoint (bzw. am `player_spawn`) nach Tod, emittiert `Events.player_respawned`

## Gegner (`res://game/enemies/{rifleman,heavy,drone}.tscn`)
- Basisklasse `class_name Enemy` (`game/enemies/enemy.gd`); Gruppen `enemy` und `damageable`; Layer 3
- `get_status() -> Dictionary`: `{type, alive, health, position:[...], state}`
- Navigation über `NavigationAgent3D`; das Level stellt eine gebackene `NavigationRegion3D` bereit (Drohnen fliegen frei)
- Schaden am Spieler über `player.take_damage(...)`. Treffsicherheit hängt von Distanz, Bewegung und Zeit seit Sichtkontakt ab. Gegner treffen anfangs schlecht (fair, „nicht zu schwer“).
- Beim Tod: `Events.enemy_killed.emit(self)`, Gruppe `enemy` verlassen, Ragdoll oder Todes-Animation, nach ein paar Sekunden aufräumen

## Level (`res://game/levels/test_range.tscn`)
- Script `game/levels/level.gd` (`class_name Level`): spawnt bei `_ready` den Player am `player_spawn` und die Gegner an den `enemy_spawn`-Markern (Welle 0 sofort, weitere Wellen über Trigger-Area3D). Szenen werden per Pfad und `load()` geladen, nicht über eine harte ext_resource, damit das Level auch ohne fertige Gegner lädt.
- `WorldEnvironment` (SDFGI, Volumetric Fog, Glow, Tonemap), Sonne mit Schatten
- `LevelEnd` als Area3D, emittiert `Events.level_completed`
- `get_level_info() -> Dictionary` mit `{name, waves, end_position:[...], waypoints:[[...],...]}`. Waypoints sind die ideale Route für den Bot (Gruppe `bot_waypoint`, sortiert nach Meta `order`).

## Debug-Server (Autoload `DebugServer`)
Nur aktiv mit `--debug-server`. TCP `127.0.0.1:9123`, ein JSON-Objekt pro Zeile, eine Antwort pro Zeile.
Befehle: `status`, `input {...ext}`, `hold {ext..., "duration": s}` (für Dauer halten, dann neutral), `look_at {x,y,z}`, `set_view {yaw,pitch}`, `step {seconds}` (spielt N Sekunden und pausiert dann; ohne Pause-Modus läuft das Spiel normal), `pause`, `resume`, `screenshot {path}`, `enemies`, `level_info`, `timescale {value}`, `spawn {type, x,y,z}`, `explode {x,y,z,radius}`, `teleport {x,y,z}`, `quit`.

---
# Runde 3: Kampagne, Fahrzeuge, Effekte

## Kampagne (Reihenfolge in `game/main.gd` → `LEVELS`)
| # | Level-Datei | Titel | Ort / Zeit | Kern |
|---|---|---|---|---|
| 1 | `baltic_night` | Nacht an der Grenze | Grenze Lettland–Russland, 14.03.2030 03:40 | russischer Einfall, Schnee, Nacht |
| 2 | `test_range` | Kriegsstraße | Daugavpils, 14.03.2030 07:15 | Gegenangriff in der Stadt |
| 3 | `river_crossing` | Die Brücke | Fluss Welikaja bei Pskow, 22.03.2030 05:50 | Gewitter, Regen, Morgengrauen; Hubschrauber, Panzer, Brückeneinsturz |
| 4 | `rail_yard` | Letzter Zug | Güterbahnhof Pskow, 02.04.2030 19:20 | Abendsonne; Munitionszug-Kettenexplosion, EU-Jets mit Bombenangriff; Ende: Waffenstillstand (EU siegt) |
| 5 | `berlin` | Das letzte Reich | Berlin, Regierungsviertel, 01.06.2030 22:10 | Plot-Twist: Putsch während der Siegesfeier |

Story-Figuren (fiktiv): Spieler = Feldwebel **Jonas Kerner**, EU-Kampfgruppe „Nord“. Funker/Vorgesetzter = **Hauptmann Weber**. Kamerad = **Obergefreite Lena Aksoy**.
Twist: Die **„Ordnungsfront“** unter **General Albrecht von Hagen** (fiktiv) nutzt die Siegesfeier für einen Putsch und ruft das „Letzte Reich“ aus. Teile der eigenen Truppe laufen über. Weber ist am Ende der Verräter (Cliffhanger). **Keine realen NS-Symbole, Parolen, Lieder oder realen Personen.** Ordnungsfront-Ikonografie ist frei erfunden: Emblem = stilisierter, gebrochener Ring mit senkrechter Klinge. Farben: Stahlgrau, Schwarz, Bernstein/Amber.

## Story-Signale (Events, existieren bereits)
- `Events.story_radio(speaker, text, duration)`: Funkspruch als Untertitel. duration 0 = automatisch.
- `Events.story_objective(text)`: Missionsziel (leer = ausblenden).
- `Events.story_cinematic(active)`: Letterbox für Set-Pieces.
Level senden diese Signale aus ihren eigenen Triggern. Die Anzeige baut der Story-Agent (`game/story/`). Sie wird von `main.gd` instanziiert und muss nicht existieren, damit ein Level läuft.

## Gegner-Fraktion
`Level.default_faction` ("ru" | "reich") und Marker-Meta `faction` überschreiben einander (Marker gewinnt). `level.gd` setzt vor `add_child` die Meta `faction` auf dem Gegner. Gegner lesen `get_meta("faction", "ru")` in `_ready` und passen nur die **Optik** an (Uniform-Farbe, Armbinde/Emblem). Werte und KI bleiben gleich.

## Fahrzeuge & Effekte (`game/vehicles/`, neue Dateien in `game/vfx/`)
Alle Szenen per `load()` mit `ResourceLoader.exists`-Check verwenden. Fehlt eine Szene, läuft das Level trotzdem (Set-Piece fällt dann aus).
- `res://game/vehicles/helicopter.tscn`, `class_name Helicopter` (Kampfhubschrauber)
  - Gruppen `enemy`, `damageable`, `vehicle`; `take_damage`/`is_alive`/`get_status()` wie Gegner (`type = "helicopter"`).
  - `fly_path(points: Array[Vector3], speed := 18.0, loop := false)`, `hover_at(p: Vector3)`, `attack(enable: bool)` (MG-Salven mit Tracern und Einschlägen auf den Spieler, fair und gut sichtbar).
  - Etwa 600 HP; mit dem Gewehr in ca. 2 Magazinen abschießbar. Tod: rauchende Trudel-Spirale, Absturz, große Explosion, brennendes Wrack. Signal `destroyed`.
- `res://game/vehicles/tank.tscn`, `class_name Tank`
  - Gruppen `damageable`, `vehicle` (**nicht** `enemy`). Kugeln machen keinen Schaden, nur Explosionen (Granaten, Fässer, Sprengladung).
  - `drive_path(points, speed := 4.0)`, `set_target(node_or_null)` (Turm dreht nach; Kanonenschuss alle ~6 s mit Warnung: Turm richtet sich 1,5 s sichtbar aus, dann Mündungsfeuer, Einschlag in der Nähe des Spielers über `Combat.explode`, nicht direkt tödlich), `destroy()`.
  - Signal `destroyed`. Tod: Turm fliegt hoch, Brand, Rauchsäule.
- `res://game/vehicles/jet_flyby.tscn`, `class_name JetFlyby`: `run(from: Vector3, to: Vector3, bomb_targets: Array[Vector3] = [])`. Überflug mit Überschallknall und Doppler; Bomben fallen sichtbar, Explosionskette. Danach `queue_free`.
- `res://game/vehicles/demo_charge.tscn`, `class_name DemoCharge` (Area3D-Sprengladungspunkt)
  - `target: Node`, Hinweis-Label3D „[E] Sprengladung anbringen“. Halte `interact` 1,5 s, dann piept es 4 s und `target.destroy()` (bzw. `take_damage(99999, …)`), dazu `Combat.explode`.
  - Ist `Game.arg("autopilot")` aktiv, setzt der Bot die Ladung automatisch, sobald der Spieler näher als 2,5 m ist. Die Bot-Route muss daran vorbeiführen.
  - Signale `planted` und `detonated`.
- `res://game/vfx/weather.gd` (Node3D, `class_name Weather`): `rain_strength`, `lightning := true`. Regen folgt der Kamera, Pfützen-Spritzer, Blitze (Licht-Flash plus Donner verzögert nach Distanz), optional nasse Oberflächen über einen globalen Shader-Parameter.
- Weitere Effekte nach Ermessen, zum Beispiel ein generischer Gebäude-/Brückeneinsturz (`game/vfx/collapse.gd`), Leuchtspur-Feuerkulissen in der Ferne, Signalfackeln oder Funkenregen.

## Besitz Runde 3
| Agent | Ordner/Dateien |
|---|---|
| Fahrzeuge & Effekte | `game/vehicles/`, **neue** Dateien in `game/vfx/` (+ kleine Ergänzungen in `vfx.gd`), `game/core/combat.gd` (nur abwärtskompatible Ergänzungen), `assets/vehicles/`, `assets/sfx/` mit Präfix `veh_`/`wx_` |
| Level 3 | `game/levels/river_*` (neue Dateien), `assets/environment/river/`, `assets/sfx/` mit Präfix `river_` |
| Level 4 | `game/levels/rail_*` (neue Dateien), `assets/environment/rail/`, `assets/sfx/` mit Präfix `rail_` |
| Story & Berlin | `game/story/`, `game/main.gd`, `game/enemies/` (nur Fraktions-Optik), `game/levels/berlin_*`, `assets/environment/berlin/`, `assets/characters/` (Fraktions-Texturen), `assets/sfx/` mit Präfix `story_`/`berlin_` |
`level.gd`, `level_geo.gd`, `level_buildings.gd`, `level_props.gd`, `baltic_night*`, `night_*`: **nicht ändern**. Eigene Level erben von `level.gd` wie `baltic_night.gd`. Gemeinsame Helfer dürfen gelesen, aber nur kopiert und angepasst werden.
