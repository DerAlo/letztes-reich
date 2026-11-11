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
Layer 5 `move_block` (Bit 16): unsichtbare Bewegungs-Sperren, nur in der Kollisionsmaske der Körper von Player, Gegnern
und Drohnen (`... | 16`); Hitscan, Raketen, Granaten und Pickup-Raycasts nutzen sie NICHT.
- `PropCollision.fit_tree(level)` (`game/levels/prop_collision.gd`, läuft in `Level._ready` direkt VOR `_bake_nav()`; alle
  `_bake_nav` parsen `geometry_collision_mask = 1 | 16`, das Navmesh sieht also genau das, woran Körper hängen): Für jeden Deckungs-Prop (StaticBody3D auf Layer 1, primitive Shapes, sichtbare Meshes,
  max. 20 m) werden aus der Optik enge Formen gebaut (konvexe Hüllen je Mesh-Teil `FitHull`, konkave/hohle/importierte
  Modelle als Trimesh `FitMesh`) und auf Layer 1 gelegt; die alten groben Shapes wandern in den Kind-Body `MoveBlock`
  (Layer 16, Maske 0). Ergebnis: Kugeln treffen die sichtbare Oberfläche, Bewegung bleibt einfach.
- Teile, die überwiegend (> 25 % der Punkte) außerhalb der alten Boxen liegen und seitlich > 0.5 m herausragen
  (Kanonenrohre, Ausleger), bekommen wie bisher KEINE Kollision, damit sie keine bisher freien Wege versperren.
- Übersprungen: Bodies mit eigenem Skript, Meta `no_fit` (z. B. Shapes, die zur Laufzeit abgeschaltet werden), Blocker
  (Kollision ragt > 0.6 m über die Optik, z. B. Fundamente/Wände), Boden-/Ufer-/Rampenplatten (Optik in X und Z > 7 m
  oder bis unter y = -1), Fassaden/Gebäude > 20 m.
- Debug: `--debug-collisions` zeigt Schuss-Formen orange, `MoveBlock` grau; `-- --no-propfit` schaltet den Fit ab,
  `-- --fitdebug` druckt Statistik. Audit: `res://game/levels/_collision_audit.tscn -- --level=X`,
  Deckungstest: `res://game/levels/_test_cover.tscn`.

## Pickups (`game/pickups/`)
- `Pickup` (Node3D, Gruppe `pickup`): WEAPON (liegende Waffe, [E] tauscht die Primärwaffe, gleiche Waffe -> Munition
  automatisch), AMMO (automatisch beim Drüberlaufen), CRATE (Munitionskiste, [E] füllt auf Startreserve, 15 s Abklingzeit),
  PZF_CRATE ([E] Panzerfaust bzw. Raketen). Fabriken `spawn_weapon/spawn_ammo/spawn_crate`, Level-Helfer
  `Pickup.place_pzf_set(parent, pos, yaw)` und `Pickup.place_ammo_crate(parent, pos, yaw)`.
- `DropManager` (Kind des Players): hört auf `Events.enemy_killed` (ru -> AK-74M, reich -> G36C, 35 % Munition) und
  `Events.checkpoint_reached` (Munitionskiste neben dem Spieler). Keine neuen Signale.

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
    # optional: "weapon": 1|2|3 -> Waffe wählen (Primärwaffe/Pistole/Panzerfaust, falls aufgenommen;
    #           Wegstecken/Ziehen ~0.5 s), wird zurückgesetzt
    # optional: "interact": true -> einmal [E] auslösen (Waffe aufnehmen/Kiste benutzen), Player setzt zurück
  }
  # Automatisch, ohne eigene Schlüssel:
  #  - Slide: crouch-Flanke (false->true) während sprint + vorwärts am Boden -> 0.9 s Rutschen, endet geduckt;
  #    jump bricht ab (behält Schwung)
  #  - Mantle: jump vor einer Kante bis 1.6 m (auch in der Luft, solange jump < 0.6 s her) -> hochziehen 0.4–0.6 s
  #  - Step-up: Absätze bis 0.35 m werden ohne Sprung überwunden
  func set_view(yaw_deg: float, pitch_deg: float) -> void   # sofort setzen
  func look_at_point(p: Vector3) -> void                    # sofort zielen
  func get_status() -> Dictionary
  # {alive, health, max_health, position:[x,y,z], yaw, pitch, weapon ("g36c"|"ak74m"|"pistol"|"pzf3"),
  #  weapon_index (1|2|3), ammo_mag, ammo_reserve,
  #  grenades, reloading, aiming, stance ("stand"|"crouch"|"prone"), prone, sliding, mantling}
  var is_crouching: bool   # true bei geduckt, liegend oder rutschend (Gegner werten das wie Ducken)
  ```
- Tasten (InputMap in `game/core/game.gd`, Fallback in `player._ensure_actions`): `crouch` = C (Umschalten),
  `crouch_hold` = Strg (geduckt halten), `prone` = Z (Umschalten), Sprint+C = Rutschen (endet geduckt, Springen/Sprinten
  richtet auf), `interact` = E, `weapon_1`/`weapon_2`/`weapon_3` = 1/2/3, `weapon_next`/`weapon_prev` = Mausrad,
  `weapon_last` = Q. Bot/`ext["crouch"]` bleibt ein Zustand (true = geduckt).
- Waffen (Runde weapons2): Slot 1 Primärwaffe (Start G36C, tauschbar gegen AK-74M/G36C vom Boden), Slot 2 P1 (Walther),
  Slot 3 Panzerfaust 3 (nur als Pickup). Katalog `game/weapons/weapon_defs.gd` (`WeaponDefs`), Modelle
  `game/weapons/gun_models.gd` (`GunModels`), Rakete `game/weapons/rocket.gd` (Projektil, Raycast-Maske 1|4,
  Volltreffer 650 + `Combat.explode`).
- Player-Inventar-API (für Pickups): `get_weapon(id)`, `weapon_for_ammo(type)`, `give_weapon(id, mag, reserve) -> Dictionary`
  (ersetzte Primärwaffe als {id, mag, reserve} oder {}), `needs_ammo()`, `refill_from_crate()`, `on_ammo_collected(n, type)`.
  `get_hud_info()` enthält zusätzlich `interact_hint` (z. B. „[E] AK-74M aufnehmen“) und `ammo_type`.
- Mit `--autopilot` (Game.arg) fällt die Reserve der Feuerwaffen nie unter ein Magazin (Simulation testet Kampf/Bewegung).
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
Twist: Die **„Ordnungsfront“** unter **General Albrecht von Riedhammer** (fiktiv) nutzt die Siegesfeier für einen Putsch und ruft das „Letzte Reich“ aus. Teile der eigenen Truppe laufen über. Weber ist am Ende der Verräter (Cliffhanger). **Keine realen NS-Symbole, Parolen, Lieder oder realen Personen.** Ordnungsfront-Ikonografie ist frei erfunden: Emblem = stilisierter, gebrochener Ring mit senkrechter Klinge. Farben: Stahlgrau, Schwarz, Bernstein/Amber.

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

# Runde 5: Teil 2 – „Ordnungsfront“ (drei neue Missionen)

## Kampagne Teil 2 (Reihenfolge in `game/main.gd` → `LEVELS`, nach `berlin`)
Nach Berlin spielt `main.gd` die Tafeln aus `StoryData.ENDING` ab. Danach folgt der Zwischentitel „Teil 2 – Ordnungsfront“ und es geht direkt weiter (`StoryData.ACT_ENDINGS`). Nach `gunship` kommen `StoryData.ENDING_2` und „Fortsetzung folgt“.

| # | Level | Titel | Ort / Zeit | Kern |
|---|---|---|---|---|
| 6 | `curfew` | Ausgangssperre | Berlin-Mitte, besetzt, 03.06.2030 01:40 | **Schleich-Mission** |
| 7 | `overwatch` | Kaltes Auge | Stahlwerk Hennigsdorf, 06.06.2030 05:20 | **Scharfschützen-Mission** |
| 8 | `gunship` | Wächter | über dem Fliegerhorst Lindenau, 09.06.2030 02:30 | **Gunship-Mission aus dem Flugzeug** |

### Story Teil 2
- **Ausgangslage:** Weber hat in Berlin auf Kerner geschossen, die Weste hat ihn gerettet. Lena hat ihn rausgezogen. Die Ordnungsfront hält Berlin; es gilt Ausgangssperre, auf allen Bildschirmen läuft Riedhammers Propaganda, die EU-Truppe ist gespalten. Der Widerstand um **Konrad Voss** (Ex-Bundespolizei) sitzt in stillgelegten U-Bahn-Tunneln.
- **6 `curfew`:**
  - Kerner schleicht nachts durch das besetzte Mitte zur Fernmeldestelle im Ministeriums-Nebengebäude. Dort liegen Webers verschlüsselte Funkprotokolle; sie beweisen, dass der Bühnenanschlag und der Putsch geplant waren.
  - Lena gibt per Funk von den Dächern aus Hinweise auf Patrouillen.
  - Kerner lädt die Protokolle herunter und flieht danach in den U-Bahn-Tunnel zu Voss.
  - Werkzeuge: schallgedämpfte Pistole und lautloses Ausschalten von hinten.
  - Entdeckt man ihn, gibt es Alarm, Verstärkung rückt an, Wege werden zu. Im Datenraum werden bei Alarm die Daten gelöscht, dann geht es zurück zum Checkpoint.
- **7 `overwatch`:**
  - Laut den Protokollen bringt die Ordnungsfront verhaftete loyale Offiziere und Journalisten im Konvoi ins „Lager Nord“, darunter **Oberstleutnant Brandt** von der Luftwaffe.
  - Voss' Trupp überfällt den Konvoi im nebligen Stahlwerk; Lena ist dabei.
  - Kerner deckt den Trupp mit Zielfernrohr-Gewehr von Kühlturm und Hochofen-Gerüst aus.
  - Ablauf: zuerst Wachen lautlos ausdünnen, dann der Konvoi-Hinterhalt, Gegen-Scharfschützen, Stellungswechsel wegen Mörserfeuer.
  - **Weber** taucht kurz im Zielfernrohr auf und entkommt; er muss überleben. Brandt wird befreit.
- **8 `gunship`:**
  - Brandt fliegt das loyale Gunship „Wächter“, einen fiktiven A400M-Umbau mit 3 Waffen.
  - Kerner sitzt am Feuerleitstand: Wärmebild, Kreisflug über dem Ziel.
  - Lenas und Voss' Trupp stürmt den Fliegerhorst Lindenau. Eigene Leute tragen IR-Blinker und dürfen nicht getroffen werden.
  - Dort betankt die Ordnungsfront Jets für Angriffe auf widerständige Städte; außerdem steht dort der Sendemast.
  - Ziele: Perimeter, Flak und SAM (Täuschkörper), fliehende Fahrzeuge, Tanklager und Jets. Am Ende sendet der Trupp Webers Protokolle landesweit.
  - `ENDING_2` erzählt danach: Riedhammer ist entlarvt, die Truppe kippt, Riedhammer verschanzt sich, Weber ist untergetaucht. Teil 3 folgt.
- **Sprecher:** nur die Konstanten aus `StoryData`: `WEBER`, `LENA`, `KERNER`, `VOSS`, `BRANDT`, `ORDNUNG`, Riedhammer als `"General von Riedhammer"`. Die Vertonung macht der Haupt-Agent am Ende mit `tools/gen_voice.py`; **Agenten starten gen_voice/gen_barks nicht** (GPU). Texte gehen über `_say(...)`/`Events.story_radio` bzw. `StoryData.SCRIPTS`, damit `tools/voice_lines.py` sie findet.
- **Weiterhin:** keine realen NS-Symbole, Parolen oder realen Personen.

## Besitz Runde 5
| Agent | Ordner/Dateien |
|---|---|
| Schleichen (`curfew`) | `game/levels/curfew*`, `assets/environment/curfew/`, `assets/sfx/curfew_*`, Stealth-Erweiterungen in `game/enemies/` (Wahrnehmung/Alarm, nur additiv; ohne Level-Opt-in bleibt alles wie bisher), `game/weapons/` nur für die schallgedämpfte Pistole/Takedown |
| Scharfschütze (`overwatch`) | `game/levels/overwatch*`, `assets/environment/overwatch/`, `assets/sfx/overwatch_*`, Zielfernrohr-Gewehr in `game/weapons/` (neue Dateien + additive Einträge in `weapon_defs.gd`/`gun_models.gd`, Zoom/Atem in `weapon.gd`) |
| Gunship (`gunship`) | `game/levels/gunship*`, neuer Ordner `game/gunship/`, `assets/environment/gunship/`, `assets/sfx/gunship_*` |
| Haupt-Agent | `game/main.gd`, `CONTRACTS.md`, `tools/voice_lines.py`, `tools/gen_voice.py`, Vertonung, Git |

### Gemeinsame Dateien
Betrifft `player.gd`, `weapon.gd`, `weapon_defs.gd`, `enemy.gd`, `autopilot.gd`, `story_data.gd` und `export_presets.cfg`.
- Änderungen nur additiv und klein; bestehendes Verhalten aller Level bleibt unverändert.
- Neues Verhalten nur hinter Level-Opt-in, z. B. Meta oder Export-Var.
- Vor jedem Edit die Datei frisch lesen: Andere Agenten arbeiten parallel im selben Baum.
- `story_data.gd`: jeder füllt nur seinen `BRIEFINGS`-Eintrag und fügt seinen eigenen `SCRIPTS`-Schlüssel hinzu; `ENDING_2` füllt der Gunship-Agent.
- `level.gd`, `level_geo.gd`, `level_buildings.gd`, `level_props.gd`, `prop_collision.gd` sowie fremde Level-Dateien bleiben unverändert. Eigene Level erben von `level.gd`. Sonderfälle entweder überschreiben oder vorher fragen.
- **Abnahme pro Level:**
  - `python tools/simulate.py --level <name> --runs 1 --skills average,novice --parallel 2` läuft durch.
  - Ist für die Mission ein eigenes Bot-Verhalten nötig, steckt es im Level-Skript unter `Game.arg("autopilot")`.
  - Die alten 5 Level laufen weiterhin durch.
  - Keine Script-Fehler im Log.
  - Screenshots via `tools/capture.py`.
- Testdateien bekommen den Präfix `_` und kommen in den Exclude-Filter von `export_presets.cfg`.
- **Kein Git** (kein commit/stash/checkout/reset) – das macht der Haupt-Agent.

### Kommt später (nicht selbst bauen)
- Gepanzerte Gegner und **Juggernaut-Endbosse** (`game/enemies/juggernaut.tscn`, schwer gepanzert, langsam, MG) baut ein eigener Agent, sobald ein Slot frei ist.
- Level können schon einen Marker vorsehen: Spawn-Marker mit Meta `enemy_type = "juggernaut"`. Fehlt die Szene, überspringt `level.gd` den Marker mit einer Warnung.

---

# Runde 6: Pause-Menü, Einstellungen, Grafik

Zwei Agenten parallel. Gemeinsamer Speicher ist das Autoload **`Settings`** (`game/core/settings.gd`, vom Hauptagenten angelegt, **nicht** umbauen; Ergänzungen nur additiv und abgesprochen):

- `Settings.get_value("sektion/key", default)`, `Settings.set_value("sektion/key", v)`, `Settings.reset_section("graphics")`, Signal `changed(key, value)`.
- Gespeichert in `user://settings.cfg` (verzögert, 0,5 s). Bei Bot-/Tool-Läufen (`--autopilot`, `--debug-server`, `--capture`, `--no-settings`) wird nichts geladen oder geschrieben → Simulationen laufen immer mit Standardwerten.
- Sektionen: `input/*`, `controls/*` (Agent A), `audio/*` und `game/*` (Agent A), `graphics/*` (Agent B).

Autoload-Reihenfolge (project.godot, schon eingetragen): Game → Settings → Graphics → Events → …

## Agent A – Pause-Menü, Einstellungs-UI, Steuerung, Audio
Besitzt: `game/ui/pause_menu.gd/.tscn`, `game/ui/settings_menu.gd/.tscn`, `game/ui/ui_theme.tres` (o. ä. unter `game/ui/`), `game/core/input_config.gd` (Umbelegung, Laden/Speichern der InputMap).
Darf additiv anfassen: `game/core/game.gd` (_setup_input → danach gespeicherte Belegung anwenden), `game/player/player.gd` (Maus-Empfindlichkeit, Y-Invertierung, FOV, ADS-Empfindlichkeit; ESC-Verhalten), `game/main.gd` (Pause-Menü instanziieren, Neustart-Hooks), Spezialsteuerungen in `game/gunship/gs_controller.gd`, `game/levels/overwatch*.gd`, `game/levels/curfew*.gd` nur soweit nötig, damit Empfindlichkeit/Invertierung/Pause dort auch greifen.

## Agent B – Grafik
Besitzt: `game/core/graphics.gd` (Autoload, Platzhalter existiert), `game/ui/fps_overlay.gd` (o. ä.), ggf. Shader unter `game/vfx/post/`.
Darf additiv anfassen: Level-Skripte nur, wenn eine Umgebung sich nicht generisch erfassen lässt (bevorzugt: generischer Hook über `get_tree().node_added` auf WorldEnvironment / DirectionalLight3D / Camera3D / Viewport).
**Nicht** anfassen: project.godot (außer [rendering]-Standardwerten, falls nötig), die UI-Dateien von Agent A.

## Schnittstelle Grafik → UI (Agent B liefert, Agent A rendert generisch)
```gdscript
# in graphics.gd
func get_options() -> Array[Dictionary]
# Eintrag: {"key": "graphics/xyz", "label": "Schatten", "section": "Qualität", "type": "enum"|"bool"|"float"|"int",
#           "values": [...], "labels": [...] (enum), "min"/"max"/"step" (float/int), "default": v,
#           "tooltip": "…", "requires_restart": false}
func apply_all() -> void            # beim Start und nach Preset-Wechsel
func apply_preset(name: String)     # "niedrig"|"mittel"|"hoch"|"ultra" → setzt die Einzelwerte via Settings.set_value
```
Graphics reagiert selbst auf `Settings.changed` für `graphics/*` – die UI muss nur `Settings.set_value` aufrufen. Agent A zeigt im Tab „Grafik“ einfach `Graphics.get_options()` an (gruppiert nach `section`, Tooltip unten im Menü). Wenn `get_options()` noch fehlt/leer ist: Tab zeigt „—“, kein Fehler (Agent A per `has_method` prüfen).

## Regeln (wie immer)
- Kein git. Kein gen_voice. Testdateien `_test*` (sind exportiert-ausgeschlossen).
- Akzeptanz: `python tools/simulate.py --level <x> --runs 1 --skills average --parallel 2` für mind. berlin, curfew, overwatch, gunship ohne Skriptfehler; Headless-Start ohne Parse-Fehler; Screenshots des Menüs (Agent A) bzw. Vorher/Nachher der Presets (Agent B) unter `captures/`.

---

# Runde 7: Teil 3 „Jagd auf Weber“ + Teil 4 „Die Garde“

> **Änderung (Nutzerwunsch 10.11.):** Story-Richtung B kommt als **Teil 3** vor der Garde. Die Garde-Missionen sind jetzt **Teil 4** (Daten 24./25. Juni 2030). Nach `villa` folgen `ENDING_3` und der Zwischentitel „Teil 4 – Die Garde“. Nach `bunker` folgen **`ENDING_4`** (bisher ENDING_3) und „Ende von Teil 4“. Danach kommen als Bonus die Episoden aus Richtung C (später).

## Kampagne Teil 4 (`game/main.gd` → `LEVELS`, nach `villa`; Titel stehen schon in `TITLES`)
Fehlende Level überspringt main.gd.

| # | Level | Titel | Ort / Zeit | Kern (Spielgefühl) |
|---|---|---|---|---|
| 9 | `spreebogen` | Spreebogen | Berlin-Moabit, 24.06.2030 05:10 | **Fahrzeug:** Kerner im Turm eines Schützenpanzers (Maschinenkanone + Koax-MG + Nebelwerfer), Fahrt auf festem Pfad durch den Belagerungsring, Stopps mit Gefechten, am Ende Absitzen und Brücke zu Fuß nehmen |
| 10 | `funkturm` | Stimme der Ordnung | Funkturm Charlottenburg, 24.06.2030 21:40 | **Vertikal:** Messehallen-Gelände → Turmfuß → Treppen/Aufzugsschacht nach oben → Sendesaal; oben greift ein Kampfhubschrauber an (Panzerfaust), Abstieg per Seil/Fassadenlift unter Zeitdruck |
| 11 | `kanalisation` | Unter dem Reichstag | Kanalisation Tiergarten, 25.06.2030 01:50 | **Dunkelheit:** Nachtsichtgerät (neues, wiederverwendbares System) + Taschenlampe, Schleichen light (curfew-Technik), Wasser, Engstellen, Garde-Patrouillen mit Lampen |
| 12 | `kanzleramt` | Geiseln | Kanzleramt, 25.06.2030 03:20 | **Breach & Clear:** Türen sprengen/aufbrechen mit Zeitlupe, Geiseln dürfen nicht getroffen werden (Fehlschlag), Raum für Raum, Befreiung von Präsidentin Hartmann |
| 13 | `bunker` | Letztes Gefecht | Regierungsbunker, 25.06.2030 04:40 | **Finale:** Garde-Juggernauts, Riedhammer stellen, **Weber taucht auf**, Entscheidung des Spielers (festnehmen / laufen lassen) → zwei Varianten von `ENDING_4` |

### Story Teil 4
- **Ausgangslage:** Zwei Wochen nach der Ausstrahlung der Protokolle schließen loyale Divisionen den Ring um das Regierungsviertel. Riedhammer hält sich mit der **Garde** (Elite, schwarze Uniformen, viele Gepanzerte/Juggernauts) im Spreebogen. Er sendet weiter Propaganda über den Funkturm und hält Abgeordnete als Geiseln im Kanzleramt. Kommandeur der Garde ist **Oberst Falk** (wiederkehrende Funkstimme, höhnisch, kalt, beobachtet Kerner seit Teil 2).
- **9 `spreebogen`:** Großangriff im Morgengrauen. Voss fährt den Schützenpanzer, Lena ist Kommandantin, Kerner sitzt am Turm. Durch Moabit zur Moltkebrücke: Straßensperren, Panzerfaust-Trupps an Fenstern, Garde-Panzer. Kurz vor der Brücke wird der Panzer getroffen, und alle sitzen ab, um die Brücke zu Fuß zu nehmen. Falk meldet sich zum ersten Mal im Funk.
- **10 `funkturm`:** Riedhammers Sender koordiniert die Garde und hält die Stadt in Angst. Kerner und Lena stürmen den Turm. Oben unterbricht Kerner die Sendung, Lena schaltet die eigene Botschaft auf. Ein Kampfhubschrauber greift an, dann folgt der Abstieg unter Zeitdruck. **Vorbote:** Auf dem Garde-Kanal ist kurz Webers Stimme zu hören, der Falk Koordinaten gibt.
- **11 `kanalisation`:** Voss kennt einen alten Versorgungsgang unter dem Reichstag zum Kanzleramt. Kerner geht mit Nachtsicht vor. Die Garde hat Sprengladungen an den Pfeilern verteilt; Riedhammer will notfalls alles mitnehmen. Kerner entschärft die Ladungen oder umgeht sie.
- **12 `kanzleramt`:** Kerner, Lena und Voss' Leute befreien die Geiseln Raum für Raum. Präsidentin Hartmann wird befreit. Riedhammer flieht durch einen Gang in den Regierungsbunker.
- **13 `bunker`:** Kerner verfolgt Riedhammer in den Bunker, wo ihn Falks letzte Garde-Juggernauts erwarten. Falk fällt. Riedhammer wird im Kontrollraum gestellt und ergibt sich oder stirbt, das entscheidet der Bunker-Agent. **Twist:** Weber ist da. Er hat die Protokolle bewusst hinterlassen, als Versicherung gegen Riedhammer: „Ich wollte, dass ihr sie findet.“ Sein Material über die Geldgeber des Putsches hat er bei sich. **Entscheidung** mit zwei Tasten im Endraum: festnehmen oder gehen lassen. `ENDING_4` gibt es in zwei Varianten. Weber wurde in Teil 3 schon gejagt; im Bunker schließt sich der Kreis. Bei „Laufen lassen“ bleibt ein Haken offen (Akte über die Geldgeber). Das Level legt die gewählte Variante in `StoryData`-kompatibler Form ab, etwa als `Settings.set_value("game/weber_choice", "arrest"|"release")`, und main.gd spielt die passende Kartenliste. Der Bunker-Agent erweitert dazu `ACT_ENDINGS`/main.gd minimal und additiv.
- **Sprecher:** nur die Konstanten aus `StoryData`, also `WEBER`, `LENA`, `KERNER`, `VOSS`, `BRANDT`, `ORDNUNG`, `FALK`, `RIEDHAMMER` und `HARTMANN`.
  - `FALK` und `HARTMANN` vertont der Haupt-Agent neu.
  - Agenten starten **kein** `gen_voice`/`gen_barks`. Sie liefern Text über `_say(...)`/`Events.story_radio` bzw. `StoryData.SCRIPTS` und listen neue Zeilen im Abschlussbericht.
- Keine realen NS-Symbole, keine realen Personen, keine realen Parteien. Gebäude dürfen an Berlin erinnern, sind aber frei gestaltet.

## Besitz Runde 7
| Agent | Ordner/Dateien |
|---|---|
| `spreebogen` | `game/levels/spreebogen*`, neuer Ordner `game/vehicles/ifv/` (Schützenpanzer-Turm, spielbar), `assets/sfx/spreebogen_*` |
| `funkturm` | `game/levels/funkturm*`, `assets/sfx/funkturm_*` |
| `kanzleramt` | `game/levels/kanzleramt*`, `game/systems/breach*` (Türsprengung/Zeitlupe, wiederverwendbar), `assets/sfx/kanzleramt_*` |
| `kanalisation` (Welle 2) | `game/levels/kanalisation*`, `game/systems/nightvision*` (Nachtsicht als wiederverwendbares System, Taste N, nur mit Level-Opt-in), `assets/sfx/kanalisation_*` |
| `bunker` (Welle 2) | `game/levels/bunker*`, `ENDING_4` in `story_data.gd`, Entscheidungs-Ende (minimal in main.gd) |
| `hafen` (Welle 2) | `game/levels/hafen*`, neuer Ordner `game/systems/rail_ride*` (Fahrt mit Bordwaffe auf festem Pfad, wiederverwendbar für Zug/Heli), `assets/sfx/hafen_*`, BRIEFINGS["hafen"] |
| `alpenpass` (Welle 3) | `game/levels/alpenpass*`, neuer Ordner `game/systems/artillery_spotter*` (Fernglas + Funk-Feuerleitung, wiederverwendbar), `game/systems/weather*` (Schnee/Sturm, später Regen; wiederverwendbar), `assets/sfx/alpenpass_*`, BRIEFINGS["alpenpass"] |
| `villa` (Welle 3) | `game/levels/villa*`, neuer Ordner `game/systems/recon_drone*` (Aufklärungsdrohne: fliegen, Wärmebild, Ziele markieren; wiederverwendbar für Lena-Episode), `ENDING_3` in `story_data.gd`, BRIEFINGS["villa"], `assets/sfx/villa_*` |
| `nachtzug` (Welle 3) | `game/levels/nachtzug*`, `assets/sfx/nachtzug_*`, BRIEFINGS["nachtzug"]; nutzt `game/systems/rail_ride*` nur (Änderungen dort nur additiv und rückwärtskompatibel) |
| `systeme-a` (Welle 4) | neuer Ordner `game/progress/` (Sterne/Herausforderungen, Schwierigkeitsgrad, Bestzeiten, Speicherstand), Kapitel-/Levelauswahl im Hauptmenü in `game/main.gd` (additiv), Abschluss-Bildschirm mit Sternen, Spiel-Tab in `game/ui/settings_menu.gd` (additiv), Schwierigkeits-Hook in `game/enemies/enemy.gd`/`game/core/combat.gd` (minimal, additiv) |
| `systeme-b` (Welle 4) | neuer Ordner `game/briefing/` (Briefing-Karte mit Pfeilen, Stimme aus dem Off), neuer Ordner `game/loadout/` (Ausrüstungswahl vor der Mission), additiv in `game/main.gd` (`_run_briefing`, Ladeablauf), `game/player/player.gd`/Waffen-Setup minimal |
| `systeme-c` (Welle 4) | neuer Ordner `game/systems/destructible*` (zerstörbare Deckung: Holz, Sandsack, Mauer, Glas), Nachrüstung in fertigen Leveln `berlin`, `river_crossing`, `spreebogen`, `bunker`, `funkturm` (nur additiv, Platzierung + Navmesh), `assets/sfx/destruct_*` |
| `episode-lena` (Welle 5) | `game/levels/ep_lena*`, neuer Ordner `game/episodes/` (Episoden-Liste + Menü „Episoden“ im Pausen-/Hauptmenü), additiv `game/main.gd` (Episoden-Modus: einzelnes Level ohne Kampagnen-Fortgang), BRIEFINGS["ep_lena"], Karte in `game/briefing/briefing_maps.gd` (additiv) |
| Haupt-Agent | `game/main.gd` (LEVELS/TITLES), `CONTRACTS.md`, `tools/voice_lines.py`, `tools/gen_voice.py`, Vertonung, Git |

Die **Regeln für gemeinsame Dateien und die Abnahme** gelten wie in Runde 5. Dazu kommt:
- Der Nutzer arbeitet tagsüber am PC. Tests laufen deshalb nur headless, mit `--parallel 1`, und ohne sichtbare Fenster, bis der Haupt-Agent sie freigibt.
- Screenshot-Vorschläge stehen im Bericht; der Haupt-Agent macht die Screenshots nachts.
- Bestehende Systeme werden wiederverwendet:
  - Gegnertypen `armored`/`juggernaut`, Fahrzeuge `tank`/`helicopter`, Panzerfaust;
  - `stealth_brain` aus curfew;
  - Story-Funk über `_say`;
  - Einstellungen über `Settings`.
- Pause-Menü, Einstellungen und Grafik (Runde 6) müssen funktionieren. Pause und Zeitlupe dürfen sich nicht beißen.
- Ein eigener Simulations-Bot steckt im Level-Skript unter `Game.arg("autopilot")`.

## Teil 3 – „Jagd auf Weber“ (Missionen 9–12, zwischen `gunship` und `spreebogen`)
| # | Level | Titel | Ort / Zeit | Kern |
|---|---|---|---|---|
| 9 | `hafen` | Kräne | Überseehafen Rostock, 12.06.2030 23:10 | Containerterminal bei Nacht und Regen, Kräne als Scharfschützenposition (G28 + Ballistik/Wind wiederverwenden), danach **Fahrt mit Bordwaffe** auf einem Schnellboot hinter Webers Boot her |
| 10 | `alpenpass` | Weißes Rauschen | Grenzpass bei Mittenwald, 15.06.2030 06:30 | Schneesturm mit kaum Sicht, **Artillerie-Beobachter** (Fernglas und Funk, Mörserfeuer loyaler Gebirgsjäger lenken und korrigieren), Seilbahn bzw. Lawine als Skript-Event |
| 11 | `nachtzug` | Nachtzug | Nachtzug Innsbruck–Wien, 16.06.2030 22:40 | Kampf durch den fahrenden Zug, Waggon für Waggon, Dach-Abschnitt mit Tunnelwarnungen |
| 12 | `villa` | Das Haus am See | Villa am Traunsee, 18.06.2030 20:15 | **Aufklärungsdrohne** vor dem Zugriff (Ziele markieren), dann wahlweise Schleichen oder Angriff. Das Finale ist ein Dialog mit Weber, er entkommt (Wasserflugzeug/Boot) |

### Story Teil 3
- Weber flieht mit der **„Akte Nordlicht“**. Sie belegt, dass ein fiktives ausländisches Konsortium den Putsch finanziert hat.
- Brandt fliegt Kerner und Lena inoffiziell hinterher; Voss bleibt in Berlin.
- Falk (Garde) schickt eigene Jäger hinter Weber her, weil Weber zu viel weiß. In Teil 3 gibt es also drei Parteien: Kerner, Weber und die Garde-Jäger.
- **Villa:**
  - Kerner stellt Weber. Weber sagt, Riedhammer werde das Regierungsviertel lieber sprengen als aufgeben: „Nur ich komme noch an ihn ran.“
  - Er hinterlässt die halbe Akte und entkommt Richtung Berlin.
  - `ENDING_3` leitet über zu Teil 4.
- **Neue Gegnerfarbe:** Garde-Jäger in grauen Winter- bzw. Zivilmänteln.
- **Begleitung:** Lena immer in der Nähe, Brandt per Funk aus dem Hubschrauber.

## Roadmap (Reihenfolge der Wellen, max. 3 Agenten gleichzeitig)
1. **Welle 1 (läuft):** `spreebogen`, `funkturm`, `kanzleramt`.
2. **Welle 2:** `kanalisation` (Nachtsicht), `bunker` (Finale + Entscheidung), `hafen` (Kran-Sniper + Schnellboot).
3. **Welle 3:** `alpenpass` (Artillerie-Beobachter + Schnee), `nachtzug`, `villa` (Drohne + Dialog-Finale).
4. **Welle 4 – Systeme:**
   - Sterne/Herausforderungen pro Level und Schwierigkeitsgrade
   - Briefing-Karte
   - Squad-Befehle light
   - Ausrüstungswahl vor der Mission
   - Wetter (Regen/Schnee wiederverwendbar)
   - zerstörbare Deckung
   - In-Engine-Zwischensequenzen
5. **Welle 5 – Bonus-Episoden (Richtung C):**
   - Lena (Dach/Drohne)
   - Brandt (Ausbruch ohne Waffe)
   - Voss (Putschmorgen)
   - Überläufer
   - Erreichbar über ein eigenes Menü „Episoden“.
