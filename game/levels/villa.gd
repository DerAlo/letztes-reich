extends "res://game/levels/level.gd"
## Mission 12 "Das Haus am See" (Villa am Traunsee, Oesterreich, 18.06.2030, 20:15) – Finale von Teil 3.
## Kerner klaert vom Hang mit der Aufklaerungsdrohne auf (game/systems/recon_drone.gd: Akku, Reichweite,
## Waermebild, Wind, Rotorlaerm macht Wachen misstrauisch, markierte Ziele bleiben im HUD).
## Zugang leise ueber Bootshaus und Garten (Takedowns, Kameras) oder laut ueber die Einfahrt. Alarm
## scheitert die Mission nicht, er schaltet nur um (Klaxon, Verstaerkung, Lena: kuerzester Weg).
## In der Bibliothek: Dialog mit Weber, er laesst die halbe Akte Nordlicht zurueck und geht durch die
## Hintertuer. Falks Jaeger (graue Zivilmaentel) stuermen das Haus. Danach zum Steg: Weber startet mit
## dem Wasserflugzeug Richtung Berlin – Lena: "Lass ihn, wir brauchen ihn lebend".
##
## Debug: --phase=1..5 (1 Wiese, 2 Hauseingang, 3 vor der Bibliothek, 4 Sturm, 5 Steg),
##        --villa-route=stealth|assault (Bot-Route; Standard: novice laut, sonst leise)

const BP = preload("res://game/levels/berlin_props.gd")
const VW = preload("res://game/levels/villa_world.gd")
const Stealth = preload("res://game/levels/curfew_stealth.gd")
const Brain = preload("res://game/enemies/stealth_brain.gd")
const TakedownScript = preload("res://game/weapons/takedown.gd")
const HudScript = preload("res://game/levels/curfew_hud.gd")
const DroneScript = preload("res://game/systems/recon_drone.gd")
const CameraScript = preload("res://game/levels/villa_camera.gd")
const VIP = preload("res://game/characters/vip_models.gd")

const SPAWN := Vector3(0.0, 5.1, 88.0)
const WEBER_POS := Vector3(4.0, 0.1, -28.5)
const LIB_HOLD := Vector3(5.0, 0.1, -25.6)
## Wachdienst des Strohmanns: dunkelblau. Falks Jaeger: graue Zivilmaentel, keine Abzeichen.
const SEC_COLORS := [Color(0.05, 0.06, 0.09), Color(0.1, 0.11, 0.15), Color(0.2, 0.3, 0.55)]
const JAEGER_COLORS := [Color(0.34, 0.34, 0.33), Color(0.25, 0.25, 0.26), Color(0.1, 0.1, 0.1)]
const DRONE_TOUR := [
	Vector3(0.0, 22.0, 60.0), Vector3(-24.0, 22.0, 26.0), Vector3(-18.0, 22.0, 0.0), Vector3(0.0, 22.0, -22.0),
	Vector3(16.0, 22.0, 10.0), Vector3(14.0, 22.0, 30.0), Vector3(42.0, 22.0, 22.0), Vector3(0.0, 14.0, 80.0),
]

var mats: Dictionary = {}
var pts: Dictionary = {}
var director: Node
var takedown: Node
var hud: CanvasLayer
var drone: Node

var _bot: bool = false
var _route: String = "stealth"
var _start_phase: int = 0
var _route_stage: int = 0            ## 0 = bis zur Bibliothek, 1 = Bibliothek -> Steg (Bot-Wegpunkte)
var _phase: int = 0                  ## 0 Drohne, 1 Anmarsch, 2 Haus, 3 Bibliothek, 4 Sturm, 5 Steg
var _t: float = 0.0
var _said: Dictionary = {}
var _loops: Array[Node] = []
var _alarm_loops: Array[Node] = []
var _alarm_lamps: Array[OmniLight3D] = []
var _guards: Array[Node] = []
var _reinf: Array[Node] = []
var _reinf_waves: int = 0
var _reinf_t: float = -1.0
var _weber: Dictionary = {}
var _jaeger_figs: Array[Node3D] = []
var _drone_cd: float = 0.0
var _drone_t: float = 0.0
var _drone_flights: int = 0
var _cine: bool = false
var _cine_look: Vector3 = Vector3.ZERO
var _cine_track: Node3D = null
var _storm: Array[Node] = []
var _storm_t: float = 0.0
var _storm_wave: int = 0
var _storm_on: bool = false
var _escape_started: bool = false
var _weber_speed := 1.0              # Tempo-Faktor der Weber-Tweens (Tween hat keinen Getter)
var _weber_tw: Tween = null         # laufende Flucht-/Einstiegs-Tween (fuer Tempo-Anpassung am Stegende)
var _weber_boarded: bool = false     # erst nach dem Einstieg verschwindet Weber (Kabine)
var _plane_departed: bool = false
var _end_area: Area3D
var _finished: bool = false
var _akte_taken: bool = false
var _prop_speed: float = 0.0
var _engine: AudioStreamPlayer3D
var _ap_t: float = 0.0

func _init() -> void:
	level_name = "villa"
	end_z = -54.0
	build_seed = 1806
	_wave_count = 1
	default_faction = "reich"
	ambient_artillery = false

func _ready() -> void:
	_bot = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	_route = _pick_route()
	_start_phase = clampi(int(str(Game.arg("phase", "0"))), 0, 5)
	_route_stage = 1 if _start_phase >= 5 else 0
	await super()
	if not is_inside_tree():
		return
	_equip_suppressed()
	Events.player_respawned.connect(_on_player_respawned)
	child_entered_tree.connect(_on_child_entered)
	_ambience()
	if str(Game.arg("shots", "")) != "":
		add_child(load("res://game/levels/tools/villa_shots.gd").new())
	if _start_phase > 0:
		_debug_start(_start_phase)
	else:
		_intro()

func _pick_route() -> String:
	var r := str(Game.arg("villa-route", ""))
	if r == "stealth" or r == "assault":
		return r
	return "assault" if str(Game.arg("skill", "average")) == "novice" else "stealth"

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Das Haus am See"
	var wps: Array = []
	for v: Vector3 in _bot_route():
		wps.append([v.x, v.y, v.z])
	info["waypoints"] = wps
	if not wps.is_empty():
		info["end_position"] = wps[wps.size() - 1]
	return info

## Autopilot-Hook: Drohnenflug und Zwischensequenzen faehrt der Level selbst.
func bot_drives_player() -> bool:
	if not _bot:
		return false
	if not _ready_done or _cine:
		return true
	if _phase == 0:
		return true
	return drone != null and bool(drone.get("active"))

## Pausenmenue "Checkpoint laden": Drohne zurueckholen, dann normal respawnen.
func menu_reload_checkpoint() -> void:
	if drone != null and bool(drone.get("active")):
		drone.call("stop", "menu")
	var pl := _player()
	if pl != null:
		pl.call("respawn")

# ------------------------------------------------------------------ Bot-Routen

func _bot_route() -> Array[Vector3]:
	var r: Array[Vector3] = []
	if _route_stage == 1:
		r.append_array([Vector3(7.6, 0.1, -27.9), Vector3(10.0, 0.1, -30.6), Vector3(10.0, 0.1, -33.6),
			Vector3(9.5, 0.05, -36.5), Vector3(-3.0, 0.05, -36.5), Vector3(-6.0, 0.05, -40.0),
			Vector3(-6.0, 0.05, -43.5), Vector3(-6.0, 0.25, -49.0), Vector3(-6.0, 0.25, -54.0)])
		if _start_phase >= 5:
			r = r.slice(6)
		return r
	var common: Array[Vector3] = [Vector3(0.0, 5.0, 84.0), Vector3(0.0, 5.0, 72.0), Vector3(0.0, 0.0, 47.0)]
	var stealth: Array[Vector3] = [Vector3(-12.0, 0.0, 45.0), Vector3(-26.0, 0.0, 42.0), Vector3(-27.5, 0.0, 36.0),
		Vector3(-27.5, 0.05, 28.0), Vector3(-27.5, 0.0, 20.5), Vector3(-26.0, 0.0, 16.0), Vector3(-24.0, 0.0, 4.0),
		Vector3(-22.0, 0.0, -8.0), Vector3(-17.0, 0.12, -18.0), Vector3(-14.0, 0.12, -22.8)]
	var stealth_in: Array[Vector3] = [Vector3(-10.0, 0.1, -22.8), Vector3(-2.5, 0.1, -18.0), Vector3(0.0, 0.1, -18.0),
		Vector3(4.0, 0.1, -18.0), Vector3(6.0, 0.1, -20.0)]
	var assault: Array[Vector3] = [Vector3(8.0, 0.0, 44.0), Vector3(14.0, 0.0, 38.0), Vector3(14.0, 0.0, 31.0),
		Vector3(14.0, 0.0, 20.0), Vector3(10.0, 0.0, 6.0), Vector3(6.0, 0.0, -8.0), Vector3(6.0, 0.06, -12.5)]
	var assault_in: Array[Vector3] = [Vector3(6.0, 0.1, -16.5), Vector3(6.0, 0.1, -20.0)]
	var lib: Array[Vector3] = [Vector3(6.0, 0.1, -22.0), Vector3(6.0, 0.1, -24.5), LIB_HOLD]
	if _start_phase <= 1:
		if _start_phase == 0:
			r.append_array(common)
		r.append_array(stealth if _route == "stealth" else assault)
	if _start_phase <= 2:
		r.append_array(stealth_in if _route == "stealth" else assault_in)
	r.append_array(lib)
	return r

## Autopilot nachfuehren (Fortschritts-Watchdog; reload = neue Wegpunkte ab Index 0).
func _ap_reset(reload: bool = false) -> void:
	if not _bot:
		return
	var ap := get_tree().root.find_child("Autopilot", true, false)
	if ap == null:
		return
	if reload:
		ap.call("_read_level_info")
		ap.set("_wp_idx", 0)
	ap.set("_route_done_time", -1.0)
	ap.set("_last_progress_t", ap.get("_sim_time"))
	ap.set("_stall_streak", 0)
	ap.set("_stuck_streak", 0)

# ------------------------------------------------------------------ Helfer

func _later(t: float, f: Callable) -> void:
	var tm := Timer.new()
	tm.one_shot = true
	tm.wait_time = maxf(t, 0.01)
	tm.timeout.connect(f)
	tm.timeout.connect(tm.queue_free)
	add_child(tm)
	tm.start()

func _say(speaker: String, text: String, dur: float = 0.0) -> void:
	Events.story_radio.emit(speaker, text, dur)

## Funkzeile mit StoryUI-Optionen (max_age/valid/priority/cut/key/drop_live, siehe story_ui.gd say()).
## Zeilen im selben Frame bilden ein Gespraech: jede kommt direkt nach ihrer Vorgaengerin.
func _say_opt(speaker: String, text: String, dur: float, opts: Dictionary) -> void:
	get_tree().call_group(&"story_ui", &"say", speaker, text, dur, opts)

func _say_once_opt(key: String, speaker: String, text: String, opts: Dictionary) -> void:
	if _said.has(key):
		return
	_said[key] = true
	_say_opt(speaker, text, 0.0, opts)

## Restzeit der Funk-Warteschlange (laufende Zeile + Wartende, echte Audiolaengen aus StoryUI).
func _radio_busy() -> float:
	var ui := get_tree().get_first_node_in_group(&"story_ui")
	if ui != null and ui.has_method("busy_left"):
		return float(ui.call("busy_left"))
	return 0.0

## f aufrufen, sobald der Funk frei ist (spaetestens nach max_wait s): Zeilen, die nicht unterbrechen sollen.
func _when_radio_free(f: Callable, max_wait: float = 6.0) -> void:
	if _radio_busy() <= 0.3 or max_wait <= 0.0:
		f.call()
		return
	_later(0.25, _when_radio_free.bind(f, max_wait - 0.25))

func _say_once(key: String, speaker: String, text: String, dur: float = 0.0) -> void:
	if _said.has(key):
		return
	_said[key] = true
	_say(speaker, text, dur)

func _obj(text: String) -> void:
	Events.story_objective.emit(text)

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

static func _wp(x: float, y: float, z: float, wait: float = 0.0, look_deg: float = INF) -> Dictionary:
	return {"p": Vector3(x, y + 0.05, z), "wait": wait, "yaw": NAN if is_inf(look_deg) else deg_to_rad(look_deg)}

func _story_ui() -> Node:
	return get_tree().root.find_child("StoryUI", true, false)

## Wartet (pausierbar), bis die Funk-Warteschlange leer ist; max_t als Sicherung.
func _wait_radio(max_t: float) -> void:
	await get_tree().create_timer(0.4, false).timeout
	var sui := _story_ui()
	var t := 0.0
	while t < max_t and is_inside_tree():
		if sui == null or not is_instance_valid(sui) or not bool(sui.get("_showing")):
			break
		await get_tree().create_timer(0.2, false).timeout
		t += 0.2
	if is_inside_tree():
		await get_tree().create_timer(0.3, false).timeout

func _loop_stream(sfx_name: String) -> AudioStream:
	var path := "res://assets/sfx/%s.ogg" % sfx_name
	if not ResourceLoader.exists(path):
		return null
	var st := load(path) as AudioStreamOggVorbis
	if st == null:
		return null
	st = st.duplicate() as AudioStreamOggVorbis
	st.loop = true
	return st

func _loop_3d(sfx_name: String, pos: Vector3, vol: float, unit: float, maxd: float, parent: Node = null) -> AudioStreamPlayer3D:
	var st := _loop_stream(sfx_name)
	if st == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "SFX"
	p.volume_db = vol
	p.unit_size = unit
	p.max_distance = maxd
	p.position = pos
	(parent if parent != null else self).add_child(p)
	p.play()
	_loops.append(p)
	return p

func _loop_2d(sfx_name: String, vol: float) -> AudioStreamPlayer:
	var st := _loop_stream(sfx_name)
	if st == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = "SFX"
	p.volume_db = vol
	add_child(p)
	p.play()
	_loops.append(p)
	return p

func _fade_out(p: Node, t: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, t)
	tw.tween_callback(p.queue_free)

func _sfx_at(sfx_name: String, pos: Vector3, vol: float = 0.0, pitch: float = 1.0) -> void:
	var st := Sfx.get_stream(sfx_name)
	if st == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "SFX"
	p.volume_db = vol
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = 60.0
	p.position = pos
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _omni(pos: Vector3, c: Color, energy: float, rng_: float, fog: float = 0.6, shadows: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng_
	l.light_volumetric_fog_energy = fog
	l.shadow_enabled = shadows
	l.position = pos
	add_child(l)
	return l

func _key(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return "?"

func _pose(fig: Dictionary, arm_x: float, t: float, only_right: bool = false) -> void:
	var tw := create_tween().set_parallel(true)
	var arms: Array = fig["arms"]
	for i in arms.size():
		if only_right and i == 0:
			continue
		tw.tween_property(arms[i] as Node3D, "rotation:x", arm_x, t)

static func _face(n: Node3D, target: Vector3) -> void:
	var d := target - n.position
	if Vector2(d.x, d.z).length() > 0.01:
		n.rotation.y = atan2(-d.x, -d.z)

# ------------------------------------------------------------------ Aufbau

func _setup_environment() -> void:
	VW.setup_environment(self)
	PostFx.apply(self, "day_war")

func _build_ground() -> void:
	mats = VW.materials()
	pts = VW.build(self, world, mats, covers, rng)

func _build_street() -> void:
	pass

func _build_props() -> void:
	pass

func _build_set_piece_geometry() -> void:
	pass

func _build_skyline() -> void:
	pass

func _build_atmosphere() -> void:
	pass

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, SPAWN, "player_spawn")
	ps.name = "PlayerSpawn"
	for p in covers:
		var v: Vector3 = p
		Geo.marker(m, Vector3(v.x, 0.0, v.z), "cover_point")
	director = Stealth.new(self)
	add_child(director)
	director.connect("alarm_raised", _on_alarm_raised)
	director.connect("alarm_ended", _on_alarm_ended)
	takedown = TakedownScript.new()
	takedown.set("director", director)
	add_child(takedown)
	hud = HudScript.new() as CanvasLayer
	hud.set("director", director)
	hud.set("takedown", takedown)
	add_child(hud)
	drone = DroneScript.new()
	drone.set("director", director)
	add_child(drone)
	drone.connect("launched", _on_drone_launched)
	drone.connect("finished", _on_drone_finished)
	drone.connect("noticed", _on_drone_noticed)
	drone.connect("target_marked", _on_target_marked)
	# Waermebild: der spiegelglatte See warf die tiefe Sonne als weissen "heissen" Fleck ins Bild.
	# Kaltes Wasser ist im Waermebild dunkel und matt -> waehrend Drohnen-Waermebild Spiegelung abschalten.
	drone.connect("launched", _water_thermal)
	drone.connect("finished", func(_r: String) -> void: _water_thermal())
	drone.connect("thermal_toggled", func(_on: bool) -> void: _water_thermal())
	hud.set("drone", drone)     # Radar + Verdachtsanzeige nur fuer aufgeklaerte Wachen/Kameras
	# Alarmlampen (rot, erst bei Alarm)
	for lp: Vector3 in [Vector3(6.0, 3.4, -13.0), Vector3(-12.7, 3.2, -22.8), Vector3(14.0, 3.6, 29.2), Vector3(-23.0, 3.0, 21.6)]:
		var l := _omni(lp, Color(1.0, 0.12, 0.08), 0.0, 9.0, 0.8)
		l.visible = false
		_alarm_lamps.append(l)
	# Ausloeser
	_trigger("Wiese", Vector3(5.0, 2.0, 46.0), Vector3(64.0, 4.0, 1.5), _on_meadow)
	_trigger("HausVorne", Vector3(6.0, 1.6, -14.5), Vector3(2.6, 3.0, 1.2), _on_house)
	_trigger("HausTerrasse", Vector3(-11.9, 1.6, -22.8), Vector3(1.2, 3.0, 2.6), _on_house)
	_trigger("Bibliothek", Vector3(6.0, 1.6, -23.5), Vector3(11.4, 3.0, 1.0), _on_library)
	_trigger("CpSteg", Vector3(2.0, 1.6, -38.0), Vector3(26.0, 3.0, 3.0), _on_outside_back, false)
	_end_area = _trigger("LevelEnd", Vector3(-6.0, 1.2, -54.0), Vector3(3.0, 2.4, 4.0), _on_jetty_end, false)
	_end_area.add_to_group("level_end")
	_end_area.monitoring = _start_phase >= 5

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1 | 16
	nm.filter_baking_aabb = AABB(Vector3(-34.0, -1.0, -74.0), Vector3(72.0, 8.0, 178.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

# ------------------------------------------------------------------ Gegner, Kameras, Figuren

func _spawn_wave(index: int) -> void:
	if _waves_spawned.has(index) or not spawn_enemies or index != 0:
		return
	_waves_spawned[index] = true
	wave_started.emit(index)
	# Ueberwachungskameras (director vor add_child setzen)
	for c: Array in [[Vector3(-23.5, 3.0, 21.7), -10.0, -80.0], [Vector3(-12.3, 3.4, -14.3), 120.0, 200.0],
			[Vector3(19.0, 3.0, 30.6), 150.0, 220.0], [Vector3(9.2, 3.4, -13.7), 150.0, 220.0]]:
		var cam := CameraScript.new()
		cam.set("director", director)
		cam.set("yaw_a", float(c[1]))
		cam.set("yaw_b", float(c[2]))
		add_child(cam)
		(cam as Node3D).position = c[0]
		drone.call("add_target", cam, "camera", "Kamera")
	# Weber in der Bibliothek, Jaeger an den grauen Wagen hinter der Ostmauer
	# --phase=5 (Debug): Weber startet ebenfalls in der Bibliothek und flieht sofort; der Spieler steht
	# dann VOR ihm am Steg (Test fuer "Stegende vor Weber erreicht").
	if _start_phase < 4 or _start_phase == 5:
		_weber = VIP.build(self, "weber", WEBER_POS, 180.0)
		drone.call("add_target", _weber["root"], "weber", "Weber")
		_jaeger_post()
	if _start_phase >= 3:
		return
	var guards: Array = [
		# Tor: zwei Posten, Blick nach draussen
		["rifleman", false, [_wp(11.6, 0.0, 28.0, 0.0, 180.0)]],
		["rifleman", false, [_wp(16.4, 0.0, 28.0, 0.0, 180.0)]],
		# Auffahrt und Vorplatz
		["assault", true, [_wp(13.0, 0.0, 22.0, 3.0, 180.0), _wp(13.0, 0.0, 4.5, 3.0, 0.0)]],
		["rifleman", true, [_wp(1.5, 0.0, -9.5, 3.0, 90.0), _wp(20.0, 0.0, -9.5, 3.0, -90.0)]],
		["marksman", false, [_wp(9.0, 0.0, -10.8, 0.0, 180.0)]],
		# Bootshaus-Ausgang und Garten
		["rifleman", true, [_wp(-25.5, 0.0, 18.0, 3.0, 90.0), _wp(-13.5, 0.0, 18.0, 3.0, -90.0)]],
		["rifleman", true, [_wp(-20.5, 0.0, 8.0, 3.0, 180.0), _wp(-20.5, 0.0, -8.0, 3.0, 0.0)]],
		# Terrasse, Halle, Salon
		["rifleman", false, [_wp(-16.0, 0.12, -27.0, 0.0, 90.0)]],
		["officer", false, [_wp(6.0, 0.1, -16.0, 0.0, 180.0)]],
		["rifleman", true, [_wp(-2.0, 0.1, -16.0, 3.0, 180.0), _wp(-2.0, 0.1, -29.0, 3.0, 0.0)]],
		# Ostrasen und Vorplatz-West
		["rifleman", true, [_wp(21.0, 0.0, 8.0, 3.0, 180.0), _wp(21.0, 0.0, -4.0, 3.0, 0.0)]],
		["rifleman", false, [_wp(24.0, 0.0, -10.0, 0.0, 180.0)]],
		["rifleman", false, [_wp(-6.0, 0.0, -8.0, 0.0, 90.0)]],
	]
	for g: Array in guards:
		_spawn_guard(str(g[0]), bool(g[1]), g[2] as Array)

## Falks Beobachtungsposten an der Bundesstrasse (vor dem Sturm): einer beobachtet die Villa ueber die Ostmauer,
## einer steht mit Funk an der offenen Hecktuer des Transporters, zwei gehen an der Mauer Streife (echter Gang).
## Die Drohne kann sie markieren (Lena: "Graue Maentel an der Strasse ..."); beim Sturm sind sie weg - sie sind
## die Jaeger, die dann ins Haus kommen.
func _jaeger_post() -> void:
	var watch := VIP.build(self, "graumantel", Vector3(41.6, 0.0, 22.6), 90.0)       # Blick nach Westen auf die Villa
	var radio := VIP.build(self, "graumantel", Vector3(45.6, 0.0, 26.9), 200.0)      # am Heck des Transporters
	_pose(radio, -0.55, 0.1, true)
	for f: Dictionary in [watch, radio]:
		_jaeger_figs.append(f["root"])
		drone.call("add_target", f["root"], "jaeger", "Graumantel (fremder Posten)")
	# Streife entlang der Mauer, gegenlaeufig
	for spec: Array in [[Vector3(41.2, 0.0, 12.0), Vector3(41.2, 0.0, 36.0), 0.0], [Vector3(42.4, 0.0, 34.0), Vector3(42.4, 0.0, 14.0), 9.0]]:
		var f := VIP.build(self, "graumantel", spec[0], 0.0)
		var r: Node3D = f["root"]
		_jaeger_figs.append(r)
		drone.call("add_target", r, "jaeger", "Graumantel (fremder Posten)")
		var a: Vector3 = spec[0]
		var b: Vector3 = spec[1]
		var tw := create_tween().set_loops()
		tw.tween_interval(0.5 + float(spec[2]) * 0.2)
		for leg: Array in [[a, b], [b, a]]:
			tw.tween_callback(_face.bind(r, leg[1]))
			tw.tween_property(r, "position", leg[1], (leg[0] as Vector3).distance_to(leg[1]) / 1.25).from(leg[0])
			tw.tween_interval(3.0)
		r.tree_exiting.connect(tw.kill)

## Farben vor add_child setzen (eigene Fraktions-Optik), danach Meta zurueck auf "reich" (deutsche Rufe).
func _dress(e: Enemy, colors: Array, vis_faction: String) -> void:
	e.set_meta("faction", vis_faction)
	e.set_meta("voice", "off" if e.enemy_type == "officer" else "v%d" % (1 + randi() % 3))
	e.color_primary = colors[0]
	e.color_secondary = colors[1]
	e.color_armband = colors[2]
	e.set_meta("villa_own", true)

## Fremd gespawnte Gegner (Offiziers-Verstaerkung) einkleiden und mitverwalten (aufraeumen beim Sturm/Respawn).
func _on_child_entered(n: Node) -> void:
	if not (n is Enemy) or n.has_meta("villa_own"):
		return
	var e := n as Enemy
	var jaeger := _phase >= 3
	_dress(e, JAEGER_COLORS if jaeger else SEC_COLORS, "villa_jaeger" if jaeger else "villa_wache")
	e.ready.connect(func() -> void: e.set_meta("faction", "reich"), CONNECT_ONE_SHOT)
	if jaeger:
		_storm.append(e)
	else:
		_reinf.append(e)

func _spawn_guard(type: String, flash: bool, route: Array) -> Enemy:
	var scene := load(ENEMY_PATH % type) as PackedScene
	if scene == null:
		return null
	var e := scene.instantiate() as Enemy
	_dress(e, SEC_COLORS, "villa_wache")
	add_child(e)
	e.set_meta("faction", "reich")
	var r0: Dictionary = route[0]
	e.global_position = r0["p"]
	var y: float = r0.get("yaw", NAN)
	e.rotation.y = 0.0 if is_nan(y) else y
	e.accuracy_scale = 0.55
	var b := Brain.new()
	b.setup(e, director, route, flash)
	_guards.append(e)
	drone.call("add_target", e, "guard", "Wache")
	return e

func _spawn_fighter(type: String, pos: Vector3, target: Vector3, jaeger: bool) -> Enemy:
	var scene := load(ENEMY_PATH % type) as PackedScene
	if scene == null:
		return null
	var e := scene.instantiate() as Enemy
	_dress(e, JAEGER_COLORS if jaeger else SEC_COLORS, "villa_jaeger" if jaeger else "villa_wache")
	add_child(e)
	e.set_meta("faction", "reich")
	e.global_position = pos
	var d := target - pos
	e.rotation.y = atan2(-d.x, -d.z)
	e.accuracy_scale = 0.5 if jaeger else 0.6
	e.alert(target, false)
	return e

# ------------------------------------------------------------------ Ablauf

func _physics_process(delta: float) -> void:
	_t += delta
	if not _ready_done:
		return
	var pl := _player()
	if pl == null:
		return
	_drone_cd = maxf(0.0, _drone_cd - delta)
	var flying := drone != null and bool(drone.get("active"))
	if flying:
		_drone_t += delta
		if _bot and _drone_t > 70.0:
			drone.call("stop", "bot")
	elif not _bot and _phase <= 1 and _drone_cd <= 0.0 and not _cine and not pl.dead \
			and InputMap.has_action("drone_toggle") and Input.is_action_just_pressed("drone_toggle"):
		_launch_drone()
	if _reinf_t >= 0.0:
		_reinf_t -= delta
		if _reinf_t < 0.0:
			_call_reinforcements()
	_update_alarm_note()
	if _bot and _phase < 3 and not flying and takedown != null and takedown.get("candidate") != null:
		takedown.call("try_auto")
	if director != null and bool(director.get("alarm")):
		for l in _alarm_lamps:
			l.light_energy = 2.2 + 1.8 * sin(_t * 8.0)
	if director != null:
		# Daemmerung: draussen sehen Wachen weit (ca. 14 m stehend, 8 m geduckt), im Haus zaehlen die Lampen
		var pp := pl.global_position
		var inside := pp.x > -12.0 and pp.x < 12.0 and pp.z > -32.0 and pp.z < -14.0
		director.set("ambient", 0.16 if inside else 0.31)
	_update_countdown(delta)
	if _storm_on:
		_update_storm(delta, pl)
	if _bot and (_phase == 4 or (_phase == 3 and not _cine)):
		# Bibliothek halten: Wegpunkt-Ende ist hier gewollt, kein Stillstand
		_ap_t -= delta
		if _ap_t <= 0.0:
			_ap_t = 2.0
			_ap_reset()
	if not _akte_taken and _phase >= 3 and not _cine and pts.has("akte") and (pts["akte"] as Node3D).visible:
		var ak: Node3D = pts["akte"]
		var d := ak.global_position - pl.global_position
		if Vector2(d.x, d.z).length() < 2.4:
			_take_akte()
	if _prop_speed > 0.0 and pts.has("prop"):
		(pts["prop"] as Node3D).rotation.z += _prop_speed * delta
	if _cine:
		_cine_frame(pl)

func _cine_frame(pl: Player) -> void:
	if pl.dead:
		return
	if _cine_track != null and is_instance_valid(_cine_track):
		_cine_look = _cine_track.global_position + Vector3(0.0, 1.6, 0.0)
	pl.external_input = true
	var ext: Dictionary = pl.ext
	ext["move"] = Vector2.ZERO
	ext["look"] = Vector2.ZERO
	ext["fire"] = false
	ext["aim"] = false
	ext["sprint"] = false
	ext["crouch"] = false
	ext["jump"] = false
	ext["reload"] = false
	ext["grenade"] = false
	ext["interact"] = false
	pl.look_at_point(_cine_look)

func _begin_cine(look: Vector3, track: Node3D = null) -> void:
	_cine = true
	_cine_look = look
	_cine_track = track
	Events.story_cinematic.emit(true)
	var pl := _player()
	if pl != null:
		pl.velocity = Vector3.ZERO

func _end_cine() -> void:
	_cine = false
	_cine_track = null
	Events.story_cinematic.emit(false)
	var pl := _player()
	if pl != null and not _bot:
		pl.external_input = false

func _intro() -> void:
	_obj("Aufklärung vom Hang: Drohne startet")
	_later(1.0, func() -> void:
		# Prioritaet 1 (Erzaehlzeilen): die Drohnen-Meldungen (Graumaentel, Weber; ebenfalls Prio 1, ohne cut)
		# warten, bis Lenas Anweisung durch ist, statt sie zu unterbrechen.
		_say_opt(StoryData.BRANDT, "Kerner, Brandt hier. Ich kreise mit dem Hubschrauber drei Kilometer südlich über dem Wald. Die Villa gehört einem Strohmann des Konsortiums – Weber ist seit Mittag drin.", 0.0, {"priority": 1})
		# Lena direkt im Anschluss (Gespraech im selben Frame)
		_say_opt(StoryData.LENA, "Ich bin hinter dir am Hang. Schick zuerst die Drohne runter – ich will jede Wache und jede Kamera kennen, bevor du gehst.", 0.0, {"priority": 1}))
	_later(9.0, func() -> void:
		if _phase == 0 and drone != null and not bool(drone.get("active")):
			_launch_drone())

func _launch_drone() -> void:
	var pl := _player()
	if pl == null or drone == null:
		_recon_done()
		return
	var fwd := -pl.global_transform.basis.z
	fwd.y = 0.0
	var at := pl.global_position + Vector3(0.0, 1.5, 0.0) + fwd.normalized() * 0.8
	if _bot:
		drone.call("set_thermal", true)
	var ok: bool = drone.call("start", at, rad_to_deg(atan2(-fwd.x, -fwd.z)))
	if not ok:
		if _phase == 0:
			_recon_done()
		return
	_drone_t = 0.0
	if _bot:
		drone.call("autofly", DRONE_TOUR, 1.2)

func _water_thermal() -> void:
	var lake := find_child("Traunsee", true, false) as MeshInstance3D
	if lake == null or not (lake.material_override is ShaderMaterial):
		return
	var th := drone != null and bool(drone.get("active")) and bool(drone.get("thermal"))
	var m := lake.material_override as ShaderMaterial
	m.set_shader_parameter("roughness_base", 0.85 if th else 0.04)
	m.set_shader_parameter("normal_strength", 0.2 if th else 0.75)

func _on_drone_launched() -> void:
	if hud != null:
		hud.visible = false
	_obj(_drone_objective())

func _on_drone_finished(_reason: String) -> void:
	_drone_cd = 0.6
	_drone_flights += 1
	if hud != null:
		hud.visible = _phase < 3
		# Was die Aufklaerung bringt, direkt nach dem Flug sagen (Markierte: Rauten durch Waende, Radar, Verdachtsauge)
		var mk := int(drone.call("marked_count", "guard")) + int(drone.call("marked_count", "camera")) if drone != null else 0
		if mk > 0 and _phase <= 1:
			hud.call("flash", "%d Ziele markiert: durch Wände sichtbar, auf dem Radar, mit Verdachtsanzeige" % mk, 6.0, Color(0.62, 0.85, 1.0))
	if _phase == 0:
		_recon_done()
	elif _phase <= 2:
		_obj(_approach_objective())

func _recon_done() -> void:
	if _phase != 0:
		return
	_phase = 1
	_checkpoint("cp_start")
	_obj(_approach_objective())
	# Lohn fuers Schleichen vorab ankuendigen (s. _loud(): Sturmgroesse, Nachhut am Steg)
	if hud != null:
		_later(6.5, func() -> void:
			if _phase == 1 and director != null and int(director.get("alarm_count")) == 0:
				hud.call("flash", "Unentdeckt bis zur Bibliothek: kleinerer Sturm, keine Nachhut am Steg", 7.0))
	_say_once("routes", StoryData.LENA, "Zwei Wege: übers Bootshaus und den Garten, leise. Oder durch die Einfahrt – da stehen mehr von denen.")
	# Kerner antwortet direkt (Gespraech im selben Frame); entfaellt, wenn inzwischen Alarm ist
	_say_once_opt("go_down", StoryData.KERNER, "Verstanden. Ich geh runter.",
		{"valid": func() -> bool: return not bool(director.get("alarm"))})
	_ap_reset()

func _approach_objective() -> String:
	return "Zur Villa: leise über Bootshaus und Garten – oder laut durch die Einfahrt  ([%s] Drohne · %s)" % [_key("drone_toggle"), _recon_text()]

## "Aufgeklärt 7/13 Wachen, 2/4 Kameras" (nur Markierte erscheinen auf Radar und Verdachtsanzeige).
func _recon_text() -> String:
	if drone == null:
		return ""
	var g := int(drone.call("target_count", "guard"))
	var c := int(drone.call("target_count", "camera"))
	var mg := int(drone.call("marked_count", "guard"))
	var mc := int(drone.call("marked_count", "camera"))
	if mg + mc == 0:
		return "nicht aufgeklärt"
	return "aufgeklärt: %d/%d Wachen, %d/%d Kameras" % [mg, g, mc, c]

func _drone_objective() -> String:
	return "Drohne: Wachen, Kameras und Weber markieren (%s) – [%s] Wärmebild, [%s] zurück" % [_recon_text(), _key("drone_thermal"), _key("drone_toggle")]

## Hat es vor der Bibliothek Alarm gegeben? Dann: mehr Verstaerkung, groesserer Sturm, Nachhut am Steg, kein Stern.
func _loud() -> bool:
	return director != null and int(director.get("alarm_count")) > 0

func _on_drone_noticed(_w: Object) -> void:
	_say_once("drone_noise", StoryData.LENA, "Zu tief, Jonas – die Wache hat den Rotor gehört. Geh höher.")

func _on_target_marked(_node: Node3D, kind: String) -> void:
	if drone != null and bool(drone.get("active")):
		_obj(_drone_objective())
	elif _phase == 1 and not bool(director.get("alarm")):
		_obj(_approach_objective())
	match kind:
		"jaeger":
			# Erzaehlzeile Prio 1 (kein max_age, kein cut): wartet hinter Lenas Drohnen-Anweisung (gleiche Prio,
			# unterbricht sie nicht) und wird auch von Kerners Weber-Zeile nicht mehr abgeschnitten. Verfaellt erst,
			# wenn Kerner schon im Haus ist.
			_say_once_opt("jaeger_seen", StoryData.LENA, "Graue Mäntel an der Straße. Das ist nicht Webers Wachdienst.",
					{"priority": 1, "valid": func() -> bool: return _phase < 2})
		"weber":
			_say_once_opt("weber_seen", StoryData.KERNER, "Weber. In der Bibliothek, Erdgeschoss hinten rechts. Allein.",
					{"priority": 1, "valid": func() -> bool: return _phase < 2})

func _on_meadow() -> void:
	if _phase == 0 and drone != null and bool(drone.get("active")):
		return
	if _phase == 0:
		_recon_done()

func _on_house() -> void:
	if _phase >= 2 or _phase == 0:
		if _phase == 0:
			_recon_done()
		else:
			return
	_phase = 2
	_checkpoint("cp_house")
	_obj("Bibliothek: hinten rechts im Erdgeschoss")
	_say_once("inside", StoryData.LENA, "Du bist drin. Die Bibliothek liegt hinten rechts – Weber ist allein.")

## Haus fuer die Szene raeumen: Wachen/Verstaerkung weg, Alarm aus, Schleich-Direktor still.
func _clear_house() -> void:
	if director != null:
		director.call("end_alarm")
		director.set("enabled", false)
	_set_alarm_fx(false)
	_reinf_t = -1.0
	for e in _guards + _reinf:
		if is_instance_valid(e):
			e.queue_free()
	_guards.clear()
	_reinf.clear()
	if hud != null:
		hud.visible = false

func _on_library() -> void:
	if _phase >= 3:
		return
	_phase = 3
	_checkpoint("cp_library")
	_clear_house()
	if drone != null and bool(drone.get("active")):
		drone.call("stop", "scene")
	_library_scene()

func _weber_head() -> Vector3:
	if _weber.is_empty():
		return WEBER_POS + Vector3(0, 1.6, 0)
	return (_weber["root"] as Node3D).global_position + Vector3(0.0, 1.65, 0.0)

## Vorwarnzeit zwischen Webers Szene und dem Sturm der Jaeger: Spieler hat die Kontrolle, Countdown oben.
const STORM_WARN := 24.0

func _library_scene() -> void:
	_obj("")
	_begin_cine(_weber_head())
	# Zwischensequenz (game/cutscene): Kamerafahrt auf Weber in der Bibliothek, Gegenschuss, Nahaufnahme.
	# Autopilot/--skip-cutscenes: sofort übersprungen.
	await _weber_library_cutscene()
	if not is_inside_tree():
		return
	# Danach KEIN Standbild mehr: Kontrolle zurueck, Webers restliche Zeilen laufen als Funk/Untertitel weiter,
	# waehrend ein Countdown bis zum Zugriff der Jaeger laeuft (Stellung beziehen, nachladen).
	_end_cine()
	_obj("Falks Jäger rücken an – Stellung in der Bibliothek beziehen")
	_start_countdown(STORM_WARN, "ZUGRIFF DER JÄGER IN %d s", _payoff_text())
	# Alle Zeilen sofort einreihen (Reihenfolge bleibt: Weber verabschiedet sich, bevor Falk "Zugriff" funkt)
	_say(StoryData.LENA, "Jonas, Fahrzeuge auf der Bundesstraße. Graue Mäntel. Das sind Falks Jäger.")
	_say(StoryData.WEBER, "Fragen Sie sich lieber, wie die so schnell hier sein können.")
	_say(StoryData.WEBER, "Riedhammer vertraut seinen Leitungen. Das war immer sein Fehler.")
	_say(StoryData.WEBER, "Hier. Die Hälfte der Akte Nordlicht. Konten, Strohmänner, das Konsortium. Die andere Hälfte ist meine Lebensversicherung.")
	_say(StoryData.WEBER, "Wir sehen uns in Berlin, Kerner.")
	# Akte auf den Tisch, wenn Weber "Hier." sagt (ca. 17 s nach Beginn der Zeilen)
	_later(STORM_WARN - 7.0, func() -> void:
		if _phase != 3:
			return
		if not _weber.is_empty() and not _escape_started:
			_pose(_weber, -1.1, 0.6, true)
		if pts.has("akte") and not _akte_taken:
			(pts["akte"] as Node3D).visible = true)
	# Countdown aus: Weber geht (waehrend seines Abschieds), die Jaeger stuermen
	_later(STORM_WARN, func() -> void:
		if _phase != 3:
			return
		if pts.has("akte") and not _akte_taken:
			(pts["akte"] as Node3D).visible = true
		if not _weber.is_empty() and not _escape_started:
			_pose(_weber, 0.0, 0.4)
			_weber_escape()
		_start_storm())

## Lohn bzw. Preis der Annaeherung, beim Countdown eingeblendet (Schleichen soll spuerbar etwas bringen).
func _payoff_text() -> String:
	if _loud():
		return "Alarm ausgelöst: Falk schickt mehr Jäger – und eine Nachhut an den Steg"
	return "Unentdeckt geblieben: kleinerer Sturm, keine Nachhut am Steg"

var _cd_layer: CanvasLayer
var _cd_label: Label
var _cd_sub: Label
var _cd_t: float = -1.0
var _cd_fmt: String = ""

func _start_countdown(t: float, fmt: String, sub: String) -> void:
	if _cd_layer == null:
		_cd_layer = CanvasLayer.new()
		_cd_layer.layer = 6
		add_child(_cd_layer)
		var root := UIStyle.HudRoot.new()
		_cd_layer.add_child(root)
		_cd_label = _cd_make_label(root, 26, Color(1.0, 0.62, 0.3), 18.0)
		_cd_sub = _cd_make_label(root, 17, Color(0.85, 0.9, 0.82), 56.0)
	_cd_t = t
	_cd_fmt = fmt
	_cd_sub.text = sub
	_cd_sub.add_theme_color_override("font_color", Color(1.0, 0.55, 0.42) if _loud() else Color(0.62, 0.92, 0.7))
	_cd_layer.visible = true

func _cd_make_label(parent: Control, fs: int, col: Color, y: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.offset_top = y
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _update_countdown(delta: float) -> void:
	if _cd_t < 0.0 or _cd_layer == null:
		return
	_cd_t -= delta
	if _cd_t <= 0.0 or _phase >= 4:
		_cd_t = -1.0
		_cd_layer.visible = false
		return
	_cd_label.text = _cd_fmt % ceili(_cd_t)
	_cd_label.modulate.a = 1.0 if _cd_t > 5.0 or fmod(_cd_t, 0.5) > 0.2 else 0.55

## Erster Dialogblock der Bibliothek als Kamerafahrt (Zeilen unverändert).
func _weber_library_cutscene() -> void:
	var pl := _player()
	var head := Vector3(0, 1.65, 0)
	var look_w: Variant = _weber_head()
	var off_w := Vector3.ZERO
	if not _weber.is_empty():
		look_w = _weber["root"] as Node3D
		off_w = head
	var cs := Cutscene.new()
	cs.keep_letterbox = true     # das Spieler-Kino (_cine) läuft danach weiter
	# 1) Langsam an Weber heran (er wartet im Sessel-Licht)
	cs.shot(null, Vector3(6.0, 1.72, -25.2), 5.0, {"look": look_w, "look_offset": off_w, "fov": 44.0,
		"shake": 0.22, "dof": true, "async": true})
	cs._say(StoryData.KERNER, "Weber.")
	cs._say(StoryData.WEBER, "Kerner. Pünktlich wie immer. Setzen Sie sich – wir haben weniger Zeit, als Sie glauben.")
	# 2) Gegenschuss über Webers Schulter auf Kerner
	if pl != null:
		cs.cut(Vector3(3.3, 1.85, -30.2), {"look": pl.get_camera(), "fov": 40.0})
	cs._say(StoryData.KERNER, "Die Akte. Jetzt.")
	# 3) Nahaufnahme Weber von der Seite, langsamer Push-in
	cs.cut(Vector3(2.0, 1.58, -26.6), {"look": look_w, "look_offset": off_w, "fov": 38.0})
	cs.shot(null, Vector3(2.6, 1.62, -27.2), 9.0, {"fov": 31.0, "async": true})
	cs._say(StoryData.WEBER, "Riedhammer … lieber jagt er das Regierungsviertel in die Luft, als vor Gericht zu stehen.")
	cs._say(StoryData.WEBER, "Nur ich komme noch an ihn ran.")
	# 4) zurück in Kerners Blick
	if pl != null:
		cs.shot(null, pl.get_camera(), 1.3, {"look": look_w, "look_offset": off_w, "fov": pl.get_camera().fov,
			"shake": 0.0, "dof": false})
	await cs.play(self)

## Weber geht durch die Hintertuer (die sich hinter ihm schliesst) zum Steg und steigt ins Flugzeug.
func _weber_escape() -> void:
	if _weber.is_empty() or _escape_started:
		return
	_escape_started = true
	var root: Node3D = _weber["root"]
	root.visible = true
	drone.call("remove_target", root)
	var tw := create_tween()
	_weber_tw = tw
	var prev := root.position
	# Wegpunkte = Fusspunkte auf echter Bodenhoehe: Parkett 0.1, Wiese/Plattenweg 0.0/0.03, Kaimauer 0.12,
	# Steg 0.2. Hoehenwechsel nur auf kurzen Stufen-Segmenten; Tempo unter der Lauf-Schwelle des Gangzyklus
	# (VipRig: Laufen ab ~2.3 m/s), damit Schrittlaenge und Bodenkontakt passen.
	# [Punkt, Tempo m/s, Aktion]
	var steps: Array = [
		[Vector3(4.5, 0.1, -27.6), 1.1, ""],            # vom Schreibtisch weg (nicht hindurch)
		[Vector3(7.8, 0.1, -27.5), 1.35, ""],
		[Vector3(9.7, 0.1, -29.7), 1.35, ""],
		[Vector3(10.0, 0.1, -31.1), 1.1, "door_open"],
		[Vector3(10.0, 0.1, -32.35), 1.0, ""],          # Schwelle
		[Vector3(10.0, 0.02, -32.9), 0.9, "door_close"],  # Stufe hinab
		[Vector3(10.0, 0.03, -35.4), 1.7, ""],
		[Vector3(9.0, 0.03, -36.5), 1.7, ""],
		[Vector3(-4.6, 0.03, -36.5), 1.9, ""],
		[Vector3(-6.0, 0.03, -37.9), 1.8, ""],
		[Vector3(-6.0, 0.03, -43.6), 1.8, ""],
		[Vector3(-6.0, 0.12, -44.15), 1.0, ""],         # Kaimauer
		[Vector3(-6.0, 0.2, -44.7), 1.0, ""],           # auf den Steg
	]
	var plane: Node3D = pts.get("plane") as Node3D
	var door := Vector3(-5.4, 0.2, -60.5)
	if plane != null and plane.has_method("door_point"):
		door = plane.call("door_point")
	var on_jetty := Vector3(clampf(door.x, -6.6, -5.4), 0.2, door.z)
	steps.append([Vector3(-6.0, 0.2, on_jetty.z + 1.2), 1.75, ""])
	steps.append([on_jetty, 1.0, "board"])
	for s: Array in steps:
		var p: Vector3 = s[0]
		tw.tween_callback(_face.bind(root, p))
		tw.tween_property(root, "position", p, maxf(0.05, prev.distance_to(p) / float(s[1])))
		match str(s[2]):
			"door_open":
				tw.tween_callback(_door_to.bind(100.0))
				tw.tween_interval(0.75)
			"door_close":
				tw.tween_callback(_door_to.bind(0.0))
		prev = p
	tw.tween_callback(_weber_board.bind(root, door))

## Einsteigen: zur Tuer drehen, Tuer auf, hinauf auf den Schwimmer und in die Kabine, Tuer zu, Motor an.
func _weber_board(root: Node3D, door: Vector3) -> void:
	var plane: Node3D = pts.get("plane") as Node3D
	if plane == null or not is_instance_valid(root):
		return
	if plane.has_method("open_door"):
		plane.call("open_door", true)
	var cabin := door + Vector3(1.2, 0.5, 0.0)
	if plane.has_method("cabin_point"):
		cabin = plane.call("cabin_point")
	var tw := create_tween()
	tw.set_speed_scale(_weber_speed)
	_weber_tw = tw
	tw.tween_callback(_face.bind(root, door))
	tw.tween_interval(0.6)
	tw.tween_property(root, "position", door, maxf(0.2, root.position.distance_to(door) / 0.8))
	tw.tween_interval(0.35)
	tw.tween_callback(_face.bind(root, cabin))
	# hinaufsteigen (Trittstufe/Strebe): erst hoch, dann hinein
	var mid := Vector3(lerpf(door.x, cabin.x, 0.35), cabin.y - 0.25, lerpf(door.z, cabin.z, 0.35))
	tw.tween_property(root, "position", mid, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(root, "position", cabin, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		root.visible = false
		_weber_boarded = true
		if plane.has_method("open_door"):
			plane.call("open_door", false)
		if not _finished:
			_set_throttle(0.18)
			_start_engine(-12.0 if _phase < 5 else -6.0))

## Propeller/Motor: neues Flugzeug (villa_seaplane.gd) hat "throttle", sonst altes Drehen ueber _prop_speed.
func _set_throttle(v: float) -> void:
	var plane: Node3D = pts.get("plane") as Node3D
	if plane != null and "throttle" in plane:
		plane.set("throttle", maxf(float(plane.get("throttle")), v) if v > 0.0 else 0.0)
	else:
		_prop_speed = maxf(_prop_speed, v * 40.0)

func _door_to(deg: float) -> void:
	if not pts.has("back_door"):
		return
	var hinge: Node3D = pts["back_door"]
	var tw := create_tween()
	tw.tween_property(hinge, "rotation:y", deg_to_rad(deg), 0.7).set_trans(Tween.TRANS_SINE)
	if deg == 0.0:
		tw.tween_callback(func() -> void: _sfx_at("overwatch_door_slam", hinge.global_position, -8.0))

func _start_engine(vol: float) -> void:
	if not pts.has("plane"):
		return
	if _engine == null or not is_instance_valid(_engine):
		_engine = _loop_3d("hafen_boat_engine", Vector3(0.0, 2.0, -3.0), vol, 10.0, 160.0, pts["plane"] as Node3D)
		if _engine != null:
			_engine.pitch_scale = 1.45
	elif _engine != null:
		create_tween().tween_property(_engine, "volume_db", vol, 1.5)

func _take_akte() -> void:
	_akte_taken = true
	(pts["akte"] as Node3D).visible = false
	_sfx_at("ammo_pickup", (pts["akte"] as Node3D).global_position, -6.0)
	if _phase >= 5:
		_say_once("akte", StoryData.KERNER, "Ich hab die Akte. Konten, Namen, Überweisungen … das ist echt.")

# ------------------------------------------------------------------ Sturm der Jaeger

func _start_storm() -> void:
	_phase = 4
	_storm_on = true
	_storm_t = 0.0
	_storm_wave = 0
	for f in _jaeger_figs:
		if is_instance_valid(f):
			f.queue_free()
	_jaeger_figs.clear()
	_obj("Halte die Bibliothek – Falks Jäger stürmen das Haus")
	_say(StoryData.FALK, "Zugriff. Weber gehört mir. Den Mann in der Bibliothek lasst ihr leben – den will ich mir selbst ansehen.")
	# Lena direkt nach Falk (Gespraech im selben Frame), nur solange der Sturm laeuft
	_say_once_opt("storm_lena", StoryData.LENA, "Sie kommen durch die Vordertür und über die Terrasse! Halt die Bibliothek!",
		{"valid": func() -> bool: return _storm_on})
	# Brandt erst, wenn Falk/Lena durch sind und der Funk frei ist (als zeitgebundene Zeile mit max_age hat er
	# Lenas "Halt die Bibliothek!" sonst bei Verzug unterbrochen); ohne max_age, aber nur waehrend des Sturms
	_later(16.0, func() -> void:
		_when_radio_free(func() -> void:
			_say_once_opt("storm_brandt", StoryData.BRANDT, "Kerner, hier Brandt. Bin im Anflug, zehn Minuten. Haltet durch.",
				{"valid": func() -> bool: return _storm_on}), 14.0))
	_storm_spawn(1)
	_ap_reset()

func _storm_spawn(wave: int) -> void:
	_storm_wave = wave
	var tgt := LIB_HOLD
	var list: Array = []
	if wave == 1:
		list = [["assault", Vector3(5.4, 0.05, -8.5)], ["rifleman", Vector3(7.0, 0.05, -9.5)],
			["rifleman", Vector3(-16.5, 0.15, -24.5)], ["assault", Vector3(-16.5, 0.15, -20.5)],
			["rifleman", Vector3(3.0, 0.05, -9.0)], ["assault", Vector3(6.6, 0.05, -7.0)], ["rifleman", Vector3(-17.0, 0.15, -26.5)]]
	else:
		list = [["officer", Vector3(6.0, 0.05, -7.5)], ["assault", Vector3(4.2, 0.05, -8.8)],
			["rifleman", Vector3(-17.5, 0.15, -22.0)], ["assault", Vector3(8.0, 0.15, -16.5)],
			["rifleman", Vector3(2.8, 0.05, -7.2)], ["rifleman", Vector3(-15.0, 0.15, -24.5)], ["rifleman", Vector3(-17.0, 0.15, -26.5)]]
	if _loud():
		# Alarm vor der Bibliothek: Falk weiss, dass jemand drin ist - mehr Leute, besser ausgeruestet
		if wave == 1:
			list.append_array([["assault", Vector3(4.6, 0.05, -7.6)], ["marksman", Vector3(-17.8, 0.15, -21.5)]])
		else:
			list.append_array([["assault", Vector3(7.4, 0.05, -8.0)], ["assault", Vector3(-16.0, 0.15, -27.5)], ["officer", Vector3(-17.4, 0.15, -23.4)]])
	for s: Array in list:
		var e := _spawn_fighter(str(s[0]), s[1], tgt, true)
		if e != null:
			_storm.append(e)

func _storm_alive() -> int:
	var n := 0
	for e in _storm:
		if is_instance_valid(e) and (e as Enemy).is_alive():
			n += 1
	return n

func _update_storm(delta: float, pl: Player) -> void:
	if pl.dead:
		return
	_storm_t += delta
	var alive := _storm_alive()
	if _storm_wave == 1 and (_storm_t > 13.0 or alive <= 1):
		_storm_spawn(2)
		return
	if _storm_wave == 2 and (alive == 0 or _storm_t > 36.0):
		_end_storm()

func _end_storm() -> void:
	_storm_on = false
	# Rest zieht sich zurueck (Falk hat, was er wollte: Weber ist weg)
	for e in _storm:
		if is_instance_valid(e) and (e as Enemy).is_alive():
			e.queue_free()
	_storm.clear()
	_say(StoryData.LENA, "Sie ziehen sich zurück – Jonas, der Steg! Weber will zum Wasserflugzeug!")
	_start_escape()

func _start_escape() -> void:
	_phase = 5
	if not _escape_started:
		_weber_escape()
	_door_to(100.0)
	_start_engine(-6.0)
	_set_throttle(0.22)
	_end_area.set_deferred("monitoring", true)
	_obj("Zum Steg – Weber flieht mit dem Wasserflugzeug")
	if _loud():
		_jetty_rear_guard()
	_route_stage = 1
	_ap_reset(true)

## Nach Alarm: Falks Nachhut sichert Webers Abflug am Ufer (Kaimauer, Bootssteg-Zugang).
func _jetty_rear_guard() -> void:
	_obj("Zum Steg – Falks Nachhut deckt Webers Abflug")
	for s: Array in [["assault", Vector3(-3.6, 0.05, -41.6)], ["rifleman", Vector3(-8.8, 0.05, -41.2)],
			["marksman", Vector3(-6.0, 0.2, -50.5)]]:
		var e := _spawn_fighter(str(s[0]), s[1], Vector3(10.0, 0.1, -33.0), true)
		if e != null:
			_storm.append(e)

func _on_outside_back() -> void:
	if _phase >= 5:
		_checkpoint("cp_jetty")

func _on_jetty_end() -> void:
	if _finished or _phase < 5:
		return
	_finished = true
	_obj("")
	var plane: Node3D = pts.get("plane") as Node3D
	# Weber verschwindet NICHT mehr sofort: ist er noch unterwegs (schneller Spieler), rennt er jetzt
	# (Tween schneller) am Spieler vorbei zum Flugzeug; die Kamera folgt ihm, abgelegt wird erst nach
	# dem Einstieg (_weber_board blendet ihn in der Kabine aus).
	var weber_root: Node3D = null if _weber.is_empty() else _weber["root"] as Node3D
	var pending := weber_root != null and is_instance_valid(weber_root) and weber_root.visible and not _weber_boarded
	print("[villa] Stegende erreicht: Weber %s, sichtbar=%s, an Bord=%s" % [
		str(weber_root.global_position) if weber_root != null else "-", str(weber_root != null and weber_root.visible), str(_weber_boarded)])
	if pending and not _escape_started:
		_weber_escape()
	if pending:
		_weber_speed = 2.0
		if _weber_tw != null and _weber_tw.is_valid():
			_weber_tw.set_speed_scale(_weber_speed)
		print("[villa] Stegende vor Weber erreicht – Weber rennt zum Flugzeug, Abflug wartet auf Einstieg")
		_make_way_for_weber()
	_begin_cine(plane.global_position + Vector3(0, 2, 0), weber_root if pending else plane)
	_set_throttle(1.0)
	_start_engine(0.0)
	_loop_2d("veh_heli_rotor", -34.0)
	_plane_depart(plane, weber_root)
	_say(StoryData.KERNER, "Ich hab ihn im Visier.")
	_say(StoryData.LENA, "Lass ihn, Jonas. Wir brauchen ihn lebend.")
	_say(StoryData.BRANDT, "Wasserflugzeug startet nach Nordosten. Kurs … Berlin. Ich bleib dran, solange der Sprit reicht.")
	_say(StoryData.KERNER, "Er hat uns die halbe Akte dagelassen.")
	_say(StoryData.LENA, "Und die andere Hälfte fliegt nach Berlin.")
	await _wait_radio(60.0)
	if not is_inside_tree():
		return
	# falls Weber spaet eingestiegen ist: Start abwarten, bevor das Level endet
	var t_wait := 0.0
	while not _plane_departed and t_wait < 30.0:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		t_wait += get_process_delta_time()
	await get_tree().create_timer(1.0, false).timeout
	if not is_inside_tree():
		return
	_on_level_end()

## Abflug erst, wenn Weber an Bord ist (max. 25 s, dann ist er ohnehin ausser Sicht im Haus/Garten).
func _plane_depart(plane: Node3D, weber_root: Node3D) -> void:
	var waited := 0.0
	while not _weber_boarded and waited < 25.0 and weber_root != null and is_instance_valid(weber_root) and weber_root.visible:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		waited += get_process_delta_time()
	if weber_root != null and is_instance_valid(weber_root):
		weber_root.visible = false
	_cine_track = plane
	if plane.has_method("cast_off"):
		plane.call("cast_off")
	_set_throttle(1.0)
	# Rollen nach Norden auf den See, dann Steigflug nach Nordosten
	var tw := create_tween()
	var p0 := plane.position
	tw.tween_interval(1.5)     # Leinen los, Motor kommt hoch
	tw.tween_property(plane, "position", p0 + Vector3(0.0, 0.0, -70.0), 10.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Abheben: Nase leicht hoch, Schwimmer kommen frei
	tw.tween_property(plane, "rotation:x", 0.1, 2.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(plane, "position", p0 + Vector3(0.0, 3.5, -112.0), 3.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# Steigflug mit Rechtskurve nach Nordosten
	tw.tween_property(plane, "rotation", Vector3(0.2, -0.55, -0.2), 4.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(plane, "position", p0 + Vector3(60.0, 38.0, -260.0), 14.0)
	_plane_departed = true

## Spieler steht auf Webers Laufspur (Stegmitte x=-6): sanft an den Steg-Rand schieben, damit Weber
## vorbeilaeuft statt durch ihn hindurch.
func _make_way_for_weber() -> void:
	var pl := _player()
	if pl == null:
		return
	var gx := pl.global_position.x
	if absf(gx - (-6.0)) >= 0.7:
		return
	var tx := -6.72 if gx <= -6.0 else -5.28
	var tw := create_tween()
	tw.tween_property(pl, "global_position:x", tx, 0.5).set_trans(Tween.TRANS_SINE)

# ------------------------------------------------------------------ Alarm

func _on_alarm_raised(_reason: String, _pos: Vector3, first: bool) -> void:
	if not first or _phase >= 3:
		return
	_set_alarm_fx(true)
	if _reinf_waves < 3:
		_reinf_t = 7.0 if _reinf_waves == 0 else 5.0
	_obj("Alarm! Verstärkung rückt an – kürzester Weg: Haustür, Bibliothek")
	_later(1.2, func() -> void:
		if bool(director.get("alarm")):
			_say_once_opt("alarm", StoryData.LENA, "Alarm im Haus! Vergiss das Leise – nimm den kürzesten Weg zur Haustür.",
				{"priority": 2, "cut": true, "valid": func() -> bool: return bool(director.get("alarm"))}))

func _on_alarm_ended() -> void:
	_set_alarm_fx(false)
	_reinf_t = -1.0
	if _phase < 3:
		_obj(_approach_objective() if _phase < 2 else "Bibliothek: hinten rechts im Erdgeschoss")
	var pl := _player()
	for e in _reinf:
		if is_instance_valid(e) and pl != null and (e as Node3D).global_position.distance_to(pl.global_position) > 22.0:
			e.queue_free()

## HUD-Zeile unter "ALARM": naechste Welle + was der Alarm spaeter kostet (Sturm/Nachhut, s. _loud()).
func _update_alarm_note() -> void:
	if hud == null or director == null:
		return
	if not bool(director.get("alarm")) or _phase >= 3:
		hud.set("alarm_note", "")
		return
	var n := 0
	for e in _reinf:
		if is_instance_valid(e) and (e as Enemy).is_alive():
			n += 1
	var parts: Array[String] = []
	if _reinf_t >= 0.0:
		parts.append("Welle %d rückt an in %d s" % [_reinf_waves + 1, ceili(_reinf_t)])
	if n > 0:
		parts.append("Wachleute im Einsatz: %d" % n)
	parts.append("Folge: mehr Jäger beim Sturm")
	hud.set("alarm_note", " · ".join(parts))

func _set_alarm_fx(on: bool) -> void:
	for l in _alarm_lamps:
		l.visible = on
		l.light_energy = 2.2 if on else 0.0
	if on:
		if _alarm_loops.is_empty():
			for kp: Vector3 in [Vector3(0.0, 4.0, -23.0), Vector3(14.0, 3.0, 29.0)]:
				var k := _loop_3d("curfew_klaxon", kp, -6.0, 14.0, 140.0)
				if k != null:
					_alarm_loops.append(k)
	else:
		for n in _alarm_loops:
			_fade_out(n, 2.5)
		_alarm_loops.clear()

func _call_reinforcements() -> void:
	if director == null or not bool(director.get("alarm")) or _reinf_waves >= 3 or _phase >= 3:
		return
	_reinf_waves += 1
	var pl := _player()
	if pl == null:
		return
	var cand: Array[Vector3] = [Vector3(14.0, 0.05, 24.0), Vector3(20.0, 0.05, -9.0), Vector3(-6.0, 0.05, -10.0), Vector3(-22.0, 0.05, 2.0)]
	var best := cand[0]
	var best_score := -1.0e9
	for p in cand:
		var d := p.distance_to(pl.global_position)
		var score := -absf(d - 30.0)
		if d < 18.0:
			score -= 100.0
		if score > best_score:
			best_score = score
			best = p
	var types: Array = ["rifleman", "assault", "rifleman"]
	if _reinf_waves == 2:
		types = ["assault", "assault", "rifleman", "marksman"]
	elif _reinf_waves >= 3:
		types = ["officer", "assault", "assault", "rifleman"]
	for i in types.size():
		var e := _spawn_fighter(str(types[i]), best + Vector3((float(i) - 1.0) * 0.9, 0.0, float(i % 2) * 0.9), pl.global_position, false)
		if e != null:
			e.accuracy_scale = 0.6 + 0.06 * float(_reinf_waves)
			_reinf.append(e)
	# solange der Alarm laeuft, rueckt alle ~25 s die naechste (staerkere) Welle nach
	if _reinf_waves < 3:
		_reinf_t = 25.0
	if _reinf_waves == 1:
		_say_once_opt("reinf", StoryData.LENA, "Mehr Wachleute vom Pförtnerhaus – drei Mann, sie kommen zu dir.", {"priority": 1, "max_age": 8.0})

func _on_player_respawned() -> void:
	for e in _reinf:
		if is_instance_valid(e):
			e.queue_free()
	_reinf.clear()
	_reinf_t = -1.0
	_reinf_waves = 0
	if director != null:
		director.call("reset_all")
	_set_alarm_fx(false)
	if drone != null and bool(drone.get("active")):
		drone.call("stop", "respawn")
	if _phase == 4 and _storm_on:
		# Sturm geht weiter, aber ohne die Leute, die schon im Raum standen
		for e in _storm:
			if is_instance_valid(e):
				e.queue_free()
		_storm.clear()
		_storm_spawn(2)
	if not _bot:
		_select_sd.call_deferred()

func _equip_suppressed() -> void:
	var pl := _player()
	if pl == null or pl.weapons.size() < 2:
		return
	var w := WeaponDefs.instantiate("pistol_sd")
	if w == null:
		return
	pl.weapon_root.add_child(w)
	w.setup(pl)
	w.fired.connect(pl._on_weapon_fired)
	w.hit_confirmed.connect(pl._on_hit_confirmed)
	w.set_active(false)
	var old: Weapon = pl.weapons[1]
	old.set_active(false)
	pl.weapons[1] = w
	old.queue_free()
	if not _bot and _route != "assault":
		_select_sd()

func _select_sd() -> void:
	var pl := _player()
	if pl != null and pl.weapons.size() > 1 and pl.weapon_index != 1:
		pl._do_switch(1)

func _ambience() -> void:
	_loop_2d("amb_wind", -26.0)
	_loop_3d("hafen_water_hull", Vector3(-8.0, 0.0, -46.0), -14.0, 8.0, 60.0)
	_loop_3d("hafen_water_hull", Vector3(-32.5, 0.0, 6.0), -16.0, 8.0, 50.0)
	_loop_3d("fire_crackle", Vector3(0.7, 0.6, -27.0), -18.0, 3.0, 14.0)
	_loop_3d("fire_crackle", Vector3(-11.3, 0.6, -19.0), -18.0, 3.0, 14.0)

## --phase=N: Sprung an einen Abschnitt (Debug/Captures).
func _debug_start(n: int) -> void:
	var pl := _player()
	if pl == null:
		return
	var pos := Vector3(0.0, 0.15, 47.0)
	var cp := "cp_start"
	match n:
		1:
			_phase = 1
			_obj(_approach_objective())
		2:
			_phase = 1
			pos = Vector3(-14.5, 0.2, -22.8) if _route == "stealth" else Vector3(6.0, 0.15, -12.0)
			cp = "cp_approach"
		3:
			_phase = 2
			_clear_house()
			pos = Vector3(6.0, 0.15, -20.0)
			cp = "cp_house"
			_obj("Bibliothek: hinten rechts im Erdgeschoss")
		4:
			_phase = 3
			_clear_house()
			pos = Vector3(5.0, 0.15, -26.0)
			cp = "cp_library"
			if pts.has("akte"):
				(pts["akte"] as Node3D).visible = true
			_start_storm()
		5:
			_phase = 4
			_clear_house()
			pos = Vector3(-6.0, 0.15, -42.0)
			cp = "cp_jetty"
			if pts.has("akte"):
				(pts["akte"] as Node3D).visible = true
			_start_escape()
	pl.global_position = pos
	pl.velocity = Vector3.ZERO
	_cp_done[cp] = true
	Events.checkpoint_reached.emit(cp)
