extends "res://game/levels/level.gd"
## Mission 10 (Teil 3) "Weißes Rauschen" – Grenzpass bei Mittenwald, 15.06.2030, 06:30.
## Drei Tage nach Rostock will Weber über den Pass nach Österreich. Brandt setzt Kerner und Lena im
## Schneesturm ab. Loyale Gebirgsjäger helfen mit einem Mörserzug (Funk über Lena), Falks Garde-Jäger
## (graue Wintermäntel) sind die dritte Partei. Ende: Weber entkommt mit der Seilbahn – Hinweis auf den
## Nachtzug Innsbruck–Wien (Übergang zu "nachtzug").
##
## Systeme: game/systems/weather_system.gd (Blizzard in Wellen, Sichtfenster),
##          game/systems/artillery_spotter.gd (Fernglas, Markieren, Korrekturen, Salven).
## Phasen: 0 Absetzpunkt, 1 Beobachtungsposten (Mörser auf 2 MG-Nester + Unterstand), 2 Kessel (Infanterie),
##         3 Sattel (Mörser auf Schützenpanzer), 4 Wechte/Lawine (Mörser oder Falk), 5 Grat (Garde-Jäger),
##         6 Bergstation (Kabine mit Weber – nicht treffen), Ende im Steuerraum.
## Debug: --phase=N (Einstieg in Phase N). Unter --autopilot spielt der Level-Bot die Beobachterteile selbst.

const BP = preload("res://game/levels/berlin_props.gd")
const NP = preload("res://game/levels/night_props.gd")
const Actor = preload("res://game/levels/overwatch_actor.gd")
const SD = preload("res://game/story/story_data.gd")
const WeatherSystem = preload("res://game/systems/weather_system.gd")
const Spotter = preload("res://game/systems/artillery_spotter.gd")
const CabinScript = preload("res://game/levels/alpenpass_cabin.gd")

const FR_PRIMARY := Color(0.86, 0.87, 0.88)        # Lena: weißer Schneeueberwurf
const FR_SECONDARY := Color(0.55, 0.57, 0.58)
const FR_ARMBAND := Color(0.3, 0.68, 1.0)
const GARDE_PRIMARY := Color(0.62, 0.64, 0.66)     # graue Wintermaentel
const GARDE_SECONDARY := Color(0.42, 0.44, 0.46)

const OP1 := Vector3(0.0, 0.0, -50.0)
const OP2 := Vector3(0.0, -4.0, -229.0)
const CABLE_A := Vector3(0.0, 3.0, -336.0)
const CABLE_B := Vector3(0.0, 92.0, -800.0)
const CABIN_HANG := 2.9
const CABIN_SPEED := 5.0
const CORNICE := Vector3(-47.0, 16.0, -262.0)
const VEH_START := Vector3(13.0, -4.0, -362.0)
const VEH_STOP := Vector3(10.0, -4.0, -302.0)
const GATE1_Z := -57.0
const GATE2_Z := -240.0

var mats: Dictionary = {}
var wx: Node3D
var spot: Node
var lena: Node3D
var _bot: bool = false
var _skill: String = "average"
var _phase: int = 0
var _t: float = 0.0
var _said: Dictionary = {}
var _cd: Dictionary = {}
var _loops: Array[Node] = []
var _gates: Dictionary = {}
var _targets: Array[Dictionary] = []    ## {id, kind, pos, radius, alive, phase, crew: Array, node}
var _spot_active: bool = false
var _salvo_hit: bool = false
var _misses: int = 0
var _refill_pending: bool = false
var _veh: Node3D
var _veh_state: String = "idle"       ## idle | driving | stopped | dead
var _veh_tw: Tween
var _veh_fire_t: float = 3.0
var _garde: Array[Node3D] = []
var _garde_t: float = -1.0
var _avalanche: bool = false
var _slab: Node3D
var _cabin: AnimatableBody3D
var _cabin_prog: float = 0.0
var _cabin_moving: bool = false
var _cabin_hits: int = 0
var _cabin_hit_cd: float = 0.0
var _cabin_gone: bool = false
var _cable_len: float = 1.0
var _weber: Node3D
var _waves: Dictionary = {1: [], 2: [], 3: []}
var _finished: bool = false
var _tick_t: float = 0.0
var _dbg_t: float = 0.0
var _lena_fire_t: float = 2.0
var _heli: Node3D
var _rotor: Node3D
var _intro_done: bool = false
# Level-Bot (Beobachterteile)
var _bt_id: String = ""
var _bt_marked: bool = false
var _bt_corr: bool = false
var _bt_remark: bool = false
var _bt_wait: float = 0.0
var _bt_aim := Vector3.ZERO
var _bt_had: bool = false
var _brng := RandomNumberGenerator.new()

func _init() -> void:
	level_name = "alpenpass"
	end_z = -340.0
	build_seed = 1506
	_wave_count = 3
	default_faction = "reich"
	ambient_artillery = false

func _ready() -> void:
	_bot = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	_skill = str(Game.arg("skill", "average"))
	_brng.seed = 1506 + (7 if _skill == "novice" else 0)
	await super()
	if not is_inside_tree():
		return
	_build_runtime()
	Events.player_respawned.connect(_on_player_respawned)
	_debug_phase()
	if _phase == 0:
		_intro()

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Weißes Rauschen"
	return info

## Autopilot-Hook: waehrend der Beobachterteile steuert der Level-Bot (Fernglas, Markieren, Korrekturen).
func bot_drives_player() -> bool:
	return _bot and _spot_active and spot != null and not _threat_near(40.0)

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

func _say_once(key: String, speaker: String, text: String, dur: float = 0.0) -> void:
	if _said.has(key):
		return
	_said[key] = true
	_say(speaker, text, dur)

## Funkspruch mit Abklingzeit (gleicher Schluessel frühestens nach cd Sekunden wieder).
func _say_cd(key: String, cd: float, speaker: String, text: String) -> void:
	if _t < float(_cd.get(key, -1000.0)):
		return
	_cd[key] = _t + cd
	_say(speaker, text)

func _obj(text: String) -> void:
	Events.story_objective.emit(text)

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _key(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return "?"

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

func _loop_3d(sfx_name: String, parent: Node3D, pos: Vector3, vol: float, unit: float, maxd: float) -> AudioStreamPlayer3D:
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
	parent.add_child(p)
	p.play()
	_loops.append(p)
	return p

func _fade_out(p: Node, t: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, t)
	tw.tween_callback(p.queue_free)

func _sfx_at(sfx_name: String, pos: Vector3, vol: float = 0.0, maxd: float = 90.0) -> void:
	var st := Sfx.get_stream(sfx_name)
	if st == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "SFX"
	p.volume_db = vol
	p.unit_size = 8.0
	p.max_distance = maxd
	p.position = pos
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _omni(pos: Vector3, c: Color, energy: float, rng_: float, fog: float = 0.6) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng_
	l.light_volumetric_fog_energy = fog
	l.shadow_enabled = false
	l.position = pos
	add_child(l)
	return l

func _sbox(bd: BP.Builder, body: StaticBody3D, key: String, c: Vector3, s: Vector3, yaw_deg: float = 0.0) -> void:
	bd.box(key, c, s, Basis(Vector3.UP, deg_to_rad(yaw_deg)))
	Geo.add_box_shape(body, c, s, Vector3(0, yaw_deg, 0))

func _mm(bd: BP.Builder, body: StaticBody3D, key: String, a: Vector3, b: Vector3) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	_sbox(bd, body, key, (lo + hi) * 0.5, hi - lo)

## Rampe: a/b = Oberkante (Mittellinie), width quer dazu. Massiv bis thick unter die Oberkante.
func _ramp(bd: BP.Builder, body: StaticBody3D, key: String, a: Vector3, b: Vector3, width: float, thick: float = 0.6) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.UP).normalized()
	var up := side.cross(d).normalized()
	if up.y < 0.0:
		up = -up
		side = -side
	var basis := Basis(d, up, d.cross(up))
	var size := Vector3(a.distance_to(b) + 0.3, thick, width)
	var c := (a + b) * 0.5 - up * thick * 0.5
	bd.box(key, c, size, basis)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, c)
	body.add_child(cs)

func _pipe(bd: BP.Builder, key: String, a: Vector3, b: Vector3, r: float, seg: int = 8) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var y := d / len
	var x := y.cross(Vector3.FORWARD) if absf(y.dot(Vector3.FORWARD)) < 0.95 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	bd.cyl(key, (a + b) * 0.5, r, r, len, seg, Basis(x, y, z))

func _alive(n: Variant) -> bool:
	if n == null or not (n is Node) or not is_instance_valid(n):
		return false
	var nd := n as Node
	if nd.has_method("is_alive"):
		return bool(nd.call("is_alive"))
	return nd.is_inside_tree()

func _is_puppet(n: Node) -> bool:
	return n.get_script() == Actor

## Echte Gegner-KI (keine Puppen) im Umkreis r um den Spieler.
func _threat_near(r: float) -> bool:
	var pl := _player()
	if pl == null:
		return false
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or _is_puppet(e) or not _alive(e):
			continue
		if (e as Node3D).global_position.distance_to(pl.global_position) < r:
			return true
	return false

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.74, 0.77, 0.82)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.82, 0.9)
	env.ambient_light_energy = 0.75
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.81, 0.86)
	env.fog_density = 0.02
	env.fog_sky_affect = 1.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.02
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_anisotropy = 0.3
	env.volumetric_fog_length = 64.0
	env.volumetric_fog_ambient_inject = 0.6
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.5
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.8
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(0.86, 0.9, 1.0)
	sun.light_energy = 0.55
	sun.rotation_degrees = Vector3(-38.0, 150.0, 0.0)
	sun.shadow_enabled = true
	sun.light_volumetric_fog_energy = 0.4
	add_child(sun)
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "day_war")

# ------------------------------------------------------------------ Geometrie

func _build_ground() -> void:
	mats = BP.materials()
	mats["snow"] = Geo.flat(Color(0.86, 0.88, 0.92), 0.8)
	mats["snow_dirty"] = Geo.flat(Color(0.7, 0.71, 0.72), 0.85)
	mats["rock"] = Geo.mat("concrete_wall_008", Color(0.34, 0.35, 0.37), 0.08, 1.0)
	mats["rock_dark"] = Geo.mat("concrete_wall_008", Color(0.22, 0.23, 0.25), 0.08, 1.0)
	mats["concrete"] = Geo.mat("concrete_wall_008", Color(0.5, 0.5, 0.5), 0.2, 1.0)
	mats["metal"] = Geo.mat("rusty_metal_02", Color(0.35, 0.35, 0.36), 0.5, 1.0)
	mats["steel_dark"] = Geo.flat(Color(0.12, 0.12, 0.13), 0.45, 0.7)
	mats["wood"] = Geo.flat(Color(0.28, 0.2, 0.13), 0.85)
	mats["logs"] = Geo.flat(Color(0.22, 0.17, 0.12), 0.9)
	mats["pine"] = Geo.flat(Color(0.1, 0.17, 0.12), 0.9)
	mats["spz"] = Geo.flat(Color(0.33, 0.35, 0.31), 0.7, 0.2)
	mats["spz_dark"] = Geo.flat(Color(0.12, 0.12, 0.11), 0.8, 0.2)
	mats["cabin"] = Geo.flat(Color(0.62, 0.1, 0.08), 0.5, 0.2)
	mats["glass_d"] = Geo.flat(Color(0.08, 0.1, 0.12), 0.1, 0.6)
	mats["heli"] = Geo.flat(Color(0.25, 0.28, 0.24), 0.6, 0.3)
	mats["warn"] = Geo.flat(Color(0.8, 0.6, 0.05), 0.6)
	mats["lamp"] = BP.unshaded(Color(3.0, 2.4, 1.4))

func _build_street() -> void:
	var bd := BP.Builder.new(mats)
	var body := Geo.static_body()
	body.name = "Gelaende"
	body.set_meta("no_fit", true)
	# A: Absetzpunkt-Plateau (y 0) mit Beobachtungsposten an der Kante
	_mm(bd, body, "snow", Vector3(-14, -3, 14), Vector3(14, 0, -56))
	# Abstieg in den Kessel
	_ramp(bd, body, "snow", Vector3(0, 0, -55.8), Vector3(0, -12, -90.5), 24.0, 1.2)
	# B: Kessel (y -12)
	_mm(bd, body, "snow", Vector3(-30, -15, -56), Vector3(30, -12, -206))
	# Aufstieg zum Sattel
	_ramp(bd, body, "snow", Vector3(0, -12, -205.8), Vector3(0, -4, -225.5), 22.0, 1.2)
	# C: Sattel / Passstrasse / Bergstation (y -4)
	_mm(bd, body, "snow", Vector3(-22, -7, -225), Vector3(30, -4, -368))
	# D: Grat-Steig im Osten (y 0) mit Rampen
	_mm(bd, body, "snow", Vector3(14, -4, -246), Vector3(28, 0, -290))
	_ramp(bd, body, "snow", Vector3(21, 0, -246.2), Vector3(21, -4, -235.5), 8.0, 1.0)
	_ramp(bd, body, "snow", Vector3(21, 0, -289.8), Vector3(21, -4, -300.5), 8.0, 1.0)
	# E: Rinne im Westen mit Wechte (Lawine)
	_ramp(bd, body, "snow", Vector3(-50, 15, -262), Vector3(-21, -4, -262), 24.0, 3.0)
	_mm(bd, body, "rock", Vector3(-60, -7, -249), Vector3(-36, 24, -244))
	_mm(bd, body, "rock", Vector3(-36, -7, -250), Vector3(-22, 7, -244))
	_mm(bd, body, "rock", Vector3(-60, -7, -280), Vector3(-22, 22, -274))
	_mm(bd, body, "rock", Vector3(-80, -7, -249), Vector3(-52, 40, -276))
	# Wechte: ueberhaengende Schneekante (Ziel fuer den Moerser, Kollision fuer den Entfernungsmesser)
	_mm(bd, body, "snow", Vector3(-54, 14, -252), Vector3(-44, 19, -272))
	# Berge links/rechts
	_mm(bd, body, "rock", Vector3(-40, -15, 30), Vector3(-14, 28, -56))
	_mm(bd, body, "rock", Vector3(14, -15, 30), Vector3(40, 30, -56))
	_mm(bd, body, "rock", Vector3(-60, -15, -56), Vector3(-30, 26, -206))
	_mm(bd, body, "rock", Vector3(30, -15, -56), Vector3(60, 26, -206))
	_mm(bd, body, "rock", Vector3(-60, -7, -206), Vector3(-22, 22, -244))
	_mm(bd, body, "rock", Vector3(-60, -7, -280), Vector3(-22, 24, -368))
	_mm(bd, body, "rock", Vector3(30, -7, -206), Vector3(60, 26, -368))
	_mm(bd, body, "rock", Vector3(-60, -7, -368), Vector3(60, 9, -378))
	_mm(bd, body, "rock", Vector3(-40, -15, 30), Vector3(40, 10, 40))
	_build_basin_works(bd, body)
	_build_station(bd, body)
	world.add_child(body)
	bd.build(world)
	_build_scenery()

## Kessel: Zollhuette, Unterstand (Ziel), Sandsaecke.
func _build_basin_works(bd: BP.Builder, body: StaticBody3D) -> void:
	var y := -12.0
	# Zollhuette mit Schranke
	_mm(bd, body, "wood", Vector3(7, y, -177), Vector3(14, y + 3.0, -185))
	bd.box("snow", Vector3(10.5, y + 3.3, -181), Vector3(8.4, 0.6, 9.2))
	bd.box("warn", Vector3(3.0, y + 1.0, -181), Vector3(7.5, 0.12, 0.12))
	bd.box("metal", Vector3(-1.0, y + 0.5, -181), Vector3(0.3, 1.0, 0.3))
	# Unterstand: niedriger Holz-Erd-Bunker (Ziel: nur Moerser)
	_mm(bd, body, "logs", Vector3(-9.5, y, -162.5), Vector3(-4.0, y + 1.4, -167.5))
	bd.box("snow", Vector3(-6.75, y + 1.6, -165), Vector3(6.0, 0.4, 5.5))
	bd.box("black", Vector3(-6.75, y + 0.7, -162.4), Vector3(3.0, 0.4, 0.05))
	# Felsbrocken als Deckung
	for p: Vector3 in [Vector3(-10, y, -138), Vector3(9, y, -120), Vector3(-14, y, -186), Vector3(16, y, -160), Vector3(-3, y, -128)]:
		_sbox(bd, body, "rock", p + Vector3(0, 0.7, 0), Vector3(2.4, 1.4, 1.8), p.x * 7.0)

## Bergstation: Halle, Steuerraum, Seilbahn, Strassensperre.
func _build_station(bd: BP.Builder, body: StaticBody3D) -> void:
	var y := -4.0
	var top := 4.0
	_mm(bd, body, "concrete", Vector3(-12.5, y, -318), Vector3(-12, top, -345.5))
	_mm(bd, body, "concrete", Vector3(8, y, -318), Vector3(8.5, top, -345.5))
	_mm(bd, body, "concrete", Vector3(-12, y, -345), Vector3(-3, top, -345.5))
	_mm(bd, body, "concrete", Vector3(3, y, -345), Vector3(8, top, -345.5))
	_mm(bd, body, "concrete", Vector3(-12, y, -317.5), Vector3(-6, top, -318))
	_mm(bd, body, "concrete", Vector3(4, y, -317.5), Vector3(8, top, -318))
	_mm(bd, body, "concrete", Vector3(-12.5, top, -317.5), Vector3(8.5, top + 0.5, -345.5))
	bd.box("snow", Vector3(-2.0, top + 0.75, -331.5), Vector3(21.0, 0.3, 28.0))
	# Steuerraum (Ostseite, offen zur Halle)
	_mm(bd, body, "concrete", Vector3(3, y, -330), Vector3(8, 0.0, -330.4))
	_mm(bd, body, "concrete", Vector3(3, y, -341.6), Vector3(8, 0.0, -342))
	_mm(bd, body, "steel_dark", Vector3(6.4, y, -333.5), Vector3(7.8, y + 1.05, -339.0))
	bd.box("lamp", Vector3(7.1, y + 1.08, -336.2), Vector3(1.0, 0.04, 2.6))
	# Bahnsteig-Kante und Umlenkrad
	_mm(bd, body, "concrete", Vector3(-10, y, -322), Vector3(-4, y + 0.9, -343))
	_pipe(bd, "steel_dark", Vector3(-3.0, 3.3, -326), Vector3(3.0, 3.3, -326), 2.2, 16)
	_pipe(bd, "steel_dark", Vector3(0, 3.3, -326), Vector3(0, top, -326), 0.4)
	# Seil und Stuetze im Tal
	var tower := CABLE_A.lerp(CABLE_B, 0.46)
	_pipe(bd, "steel_dark", CABLE_A + Vector3(0, 0.4, 0), CABLE_B, 0.06, 6)
	_pipe(bd, "steel_dark", CABLE_A + Vector3(0, 0.4, 10), CABLE_A + Vector3(0, 0.4, 0), 0.06, 6)
	bd.box("metal", tower + Vector3(0, -80.0, 0), Vector3(2.0, 160.0, 2.0))
	bd.box("metal", tower + Vector3(0, 0.8, 0), Vector3(6.0, 0.6, 1.2))
	# Strassensperre an der Grenzbruecke (Ziel des Schuetzenpanzers)
	_sbox(bd, body, "concrete", Vector3(4.0, y + 0.5, -298.0), Vector3(3.0, 1.0, 0.8), 15.0)
	_sbox(bd, body, "concrete", Vector3(16.0, y + 0.5, -297.0), Vector3(3.0, 1.0, 0.8), -10.0)
	bd.box("warn", Vector3(10.0, y + 1.0, -296.5), Vector3(5.0, 0.15, 0.15))
	# Schild
	var lbl := Label3D.new()
	lbl.text = "BERGSTATION  ·  GRENZE 0,4 km"
	lbl.font_size = 64
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.15, 0.15, 0.15)
	lbl.position = Vector3(-2.0, 2.6, -317.4)
	lbl.rotation_degrees.y = 0.0
	add_child(lbl)

## Nicht begehbare Kulisse: Felsbrocken, Kiefern, Schneewehen.
func _build_scenery() -> void:
	var bd := BP.Builder.new(mats)
	var prng := RandomNumberGenerator.new()
	prng.seed = build_seed + 11
	# Kiefern an den Raendern (keine Kollision, fern der Wege)
	var spots: Array[Vector3] = []
	for i in 22:
		spots.append(Vector3(prng.randf_range(-28.0, -18.0), -12.0, prng.randf_range(-95.0, -200.0)))
		spots.append(Vector3(prng.randf_range(20.0, 28.0), -12.0, prng.randf_range(-95.0, -200.0)))
	for i in 8:
		spots.append(Vector3(prng.randf_range(-13.0, -10.0), 0.0, prng.randf_range(10.0, -30.0)))
		spots.append(Vector3(prng.randf_range(10.0, 13.0), 0.0, prng.randf_range(10.0, -30.0)))
	# Fichten (Zweigkarten + Impostor-Fernstufe, MultiMesh in Zellen)
	var trees: Array = []
	for p in spots:
		trees.append([p, prng.randf_range(4.5, 9.0) / NP.TREE_H])
	NP.forest(self, trees, prng, true)
	# Felsbrocken an den Waenden
	for i in 40:
		var z := prng.randf_range(20.0, -360.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (30.0 if z < -56.0 else 14.0) + side * prng.randf_range(-1.5, 2.0)
		if z < -206.0:
			x = -22.0 if side < 0.0 else 30.0
			if side < 0.0 and z < -244.0 and z > -280.0:
				continue
		var yb := 0.0 if z > -56.0 else (-12.0 if z > -206.0 else -4.0)
		var s := Vector3(prng.randf_range(3.0, 7.0), prng.randf_range(3.0, 9.0), prng.randf_range(3.0, 7.0))
		var basis := Basis.from_euler(Vector3(prng.randf_range(-0.3, 0.3), prng.randf() * TAU, prng.randf_range(-0.3, 0.3)))
		bd.box("rock_dark" if i % 3 == 0 else "rock", Vector3(x, yb + s.y * 0.35, z), s, basis)
	# Schneekappen auf den Bergen
	bd.box("snow", Vector3(-27.0, 28.2, -13.0), Vector3(26.0, 0.4, 86.0))
	bd.box("snow", Vector3(27.0, 30.2, -13.0), Vector3(26.0, 0.4, 86.0))
	bd.build(self)

func _build_props() -> void:
	# Beobachtungsposten 1: Sandsaecke an der Kante
	Props.sandbags(world, Vector3(-3.5, 0.0, -53.6), 0.0, 3.0, rng, covers)
	Props.sandbags(world, Vector3(3.5, 0.0, -53.6), 0.0, 3.0, rng, covers)
	# Sattel: Posten 2
	Props.sandbags(world, Vector3(-4.0, -4.0, -232.5), 0.0, 3.0, rng, covers)
	Props.sandbags(world, Vector3(4.5, -4.0, -232.5), 0.0, 3.0, rng, covers)
	# Kessel-Deckung
	Props.sandbags(world, Vector3(-9.0, -12.0, -150.0), 0.0, 3.0, rng, covers)
	Props.sandbags(world, Vector3(7.0, -12.0, -155.0), 0.0, 3.0, rng, covers)
	Props.sandbags(world, Vector3(9.0, -12.0, -172.0), 0.0, 3.0, rng, covers)
	# Grat
	Props.sandbags(world, Vector3(18.0, 0.0, -275.0), 90.0, 3.0, rng, covers)
	Props.sandbags(world, Vector3(25.0, 0.0, -262.0), 90.0, 2.5, rng, covers)
	# Station
	Props.sandbags(world, Vector3(-6.0, -4.0, -308.0), 0.0, 3.0, rng, covers)
	Props.sandbags(world, Vector3(-14.0, -4.0, -312.0), 30.0, 3.0, rng, covers)
	Props.vehicle(world, Vector3(-16.0, -4.0, -326.0), 80.0, "van", Color(0.55, 0.56, 0.58), false, false, covers)
	# MG-Nester (Sandsack-Ringe)
	for c: Vector3 in [Vector3(-14, -12, -120), Vector3(16, -12, -138)]:
		Props.sandbags(world, c + Vector3(0, 0, 1.8), 0.0, 3.0, rng, covers)
		Props.sandbags(world, c + Vector3(-1.9, 0, 0), 90.0, 2.4, rng, covers)
		Props.sandbags(world, c + Vector3(1.9, 0, 0), 90.0, 2.4, rng, covers)

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(0, 0.1, 2.0), "player_spawn")
	ps.name = "PlayerSpawn"
	ps.rotation_degrees.y = 0.0
	var route: Array[Vector3] = [
		Vector3(0, 0, -10), Vector3(0, 0, -30), Vector3(0, 0, -50),
		Vector3(0, 0, -60), Vector3(0, -6, -73), Vector3(0, -12, -93),
		Vector3(-4, -12, -115), Vector3(4, -12, -140), Vector3(0, -12, -165),
		Vector3(-2, -12, -190), Vector3(0, -12, -203), Vector3(0, -8, -215),
		Vector3(0, -4, -228), Vector3(14, -4, -233), Vector3(21, -4, -235),
		Vector3(21, 0, -249), Vector3(21, 0, -268), Vector3(21, 0, -287),
		Vector3(21, -4, -302), Vector3(4, -4, -310), Vector3(0, -4, -322),
		Vector3(0.5, -4, -335), Vector3(5, -4, -336),
	]
	for i in route.size():
		var w := Geo.marker(m, route[i] + Vector3(0, 0.05, 0), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	_trigger("Posten1", Vector3(0, 1.5, -46.0), Vector3(28, 4, 3), _start_phase1)
	_trigger("Gate1Hint", Vector3(0, 1.5, GATE1_Z + 1.5), Vector3(28, 4, 1.5), func() -> void:
		if _phase == 1:
			_say_cd("gate1", 25.0, SD.LENA, "Noch nicht! Erst die Stellungen ausschalten – sonst laufen wir ins MG-Feuer."), false)
	_trigger("Kessel", Vector3(0, -10.5, -100.0), Vector3(60, 4, 3), _on_basin)
	_trigger("Posten2", Vector3(4, -2.5, -226.5), Vector3(52, 4, 3), _start_phase3)
	_trigger("Gate2Hint", Vector3(4, -2.0, GATE2_Z + 1.5), Vector3(52, 6, 1.5), func() -> void:
		if _phase == 3 or _phase == 4:
			_say_cd("gate2", 25.0, SD.LENA, "Wir bleiben hier, bis der Weg frei ist. Erst der Mörser."), false)
	_trigger("Grat", Vector3(21, 1.5, -252.0), Vector3(12, 4, 2), _on_ridge)
	_trigger("Station", Vector3(4, -2.0, -298.5), Vector3(52, 6, 2), _start_phase6)
	var area := _trigger("LevelEnd", Vector3(5.5, -2.5, -336.0), Vector3(5.0, 3.0, 11.0), _try_finish, false)
	area.add_to_group("level_end")

func _build_set_piece_geometry() -> void:
	pass

func _build_skyline() -> void:
	pass

func _build_atmosphere() -> void:
	_omni(Vector3(6.0, -1.0, -336.0), Color(1.0, 0.85, 0.6), 1.6, 9.0)
	_omni(Vector3(-2.0, 2.5, -330.0), Color(1.0, 0.9, 0.7), 1.2, 16.0)

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 42.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1 | 16
	nm.filter_baking_aabb = AABB(Vector3(-50.0, -15.0, -370.0), Vector3(80.0, 34.0, 386.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

func _spawn_wave(index: int) -> void:
	# Wellen kommen aus den Phasen-Ausloesern (_spawn_wave_alp).
	if _waves_spawned.has(index):
		return
	_waves_spawned[index] = true
	wave_started.emit(index)

# ------------------------------------------------------------------ Laufzeit-Aufbau (nach dem Navmesh)

func _build_runtime() -> void:
	# Wetter
	wx = WeatherSystem.new()
	wx.name = "Weather"
	wx.set("mode", "blizzard")
	wx.set("storm_duration", Vector2(18.0, 26.0))
	wx.set("window_duration", Vector2(10.0, 14.0))
	add_child(wx)
	# Lena
	lena = _make_actor("friendly", "rifleman", Vector3(1.6, 0.0, 3.0), FR_PRIMARY, FR_SECONDARY, FR_ARMBAND, 0.0)
	lena.set("invulnerable", true)
	lena.set("walk_speed", 2.6)
	lena.set("run_speed", 4.6)
	lena.name = "Lena"
	# Ziele
	_build_targets()
	_build_vehicle()
	_build_cabin()
	# Sperren (nach dem Bake: nicht im Navmesh)
	_gates["g1"] = _gate(Vector3(0, 0, GATE1_Z), Vector3(30, 8, 1.0))
	_gates["g2"] = _gate(Vector3(4, -4, GATE2_Z), Vector3(54, 14, 1.0))
	# Moerser / Beobachter
	spot = Spotter.new()
	spot.name = "ArtillerySpotter"
	spot.set("salvos_left", 10)
	spot.set("reload_time", 6.0)
	spot.set("prep_time", 2.0)
	spot.set("flight_base", 4.5)
	spot.set("round_interval", 0.6)
	spot.set("dispersion", 5.5)
	spot.set("bias_initial", 28.0)
	spot.set("danger_radius", 30.0)
	spot.set("blast_radius", 9.0)
	spot.set("north", Vector3(0, 0, 1))
	spot.set("battery_dir", Vector3(0.3, 0, 1))
	add_child(spot)
	spot.set("visibility_check", _spot_visible)
	spot.set("protected", [{"node": lena, "radius": 12.0, "name": "Lena"}])
	spot.set("no_fire", [{"node": _cabin, "radius": 14.0, "name": "Seilbahn"}])
	spot.connect("mission_requested", _on_mission_requested)
	spot.connect("mission_refused", _on_mission_refused)
	spot.connect("danger_close", _on_danger_close)
	spot.connect("correction_sent", _on_correction_sent)
	spot.connect("salvo_fired", _on_salvo_fired)
	spot.connect("shell_impact", _on_shell_impact)
	spot.connect("salvo_complete", _on_salvo_complete)
	_build_heli()

func _gate(pos: Vector3, size: Vector3) -> StaticBody3D:
	var b := Geo.static_body(pos + Vector3(0, size.y * 0.5 - 1.0, 0))
	b.collision_layer = 16
	b.set_meta("no_fit", true)
	Geo.add_box_shape(b, Vector3.ZERO, size)
	add_child(b)
	return b

func _open_gate(id: String) -> void:
	var g: Variant = _gates.get(id, null)
	if g is Node and is_instance_valid(g):
		(g as Node).queue_free()
	_gates.erase(id)

func _make_actor(role: String, etype: String, pos: Vector3, prim: Color, sec: Color, band: Color, yaw: float, faction: String = "") -> Node3D:
	var a: CharacterBody3D = Actor.new()
	a.set("role", role)
	a.set("enemy_type", etype)
	a.set("level_ref", self)
	if faction != "":
		a.set_meta("faction", faction)
		if faction == "garde_winter":
			a.set("color_primary", GARDE_PRIMARY)
			a.set("color_secondary", GARDE_SECONDARY)
	elif role == "enemy":
		a.set_meta("faction", "reich")
	else:
		a.set_meta("faction", "resistance")
		a.set("color_primary", prim)
		a.set("color_secondary", sec)
		a.set("color_armband", band)
	a.set("max_health", 60.0)
	a.set("damage_per_hit", 0.0)
	a.name = "%s_%s_%d" % [role, etype, get_child_count()]
	add_child(a)
	a.global_position = pos + Vector3(0, 0.05, 0)
	a.rotation.y = deg_to_rad(yaw)
	return a

func _enemy(type: String, pos: Vector3, faction: String, acc: float) -> Node3D:
	var path := ENEMY_PATH % type
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var e := scene.instantiate() as Node3D
	e.set_meta("faction", faction)
	if faction == "garde_winter":
		e.set("color_primary", GARDE_PRIMARY)
		e.set("color_secondary", GARDE_SECONDARY)
	add_child(e)
	e.global_position = pos + Vector3(0, 0.05, 0)
	e.rotation.y = 0.0
	e.set("accuracy_scale", acc)
	e.set("sight_range", 55.0 * _sight())
	return e

func _sight() -> float:
	return float(wx.call("sight_factor")) if wx != null else 1.0

## Spotter-Ziele: MG-Nester (Besatzung = Puppen mit Leuchtspur), Unterstand.
func _build_targets() -> void:
	var y := -12.0
	for d: Array in [["nest_a", Vector3(-14, y, -120)], ["nest_b", Vector3(16, y, -138)]]:
		var c: Vector3 = d[1]
		var node := Node3D.new()
		node.name = str(d[0])
		add_child(node)
		node.global_position = c
		var mg := Geo.box_mesh_node(Vector3(0.18, 0.18, 1.3), mats["steel_dark"], Vector3(0, 1.05, 0.2))
		node.add_child(mg)
		node.add_child(Geo.box_mesh_node(Vector3(0.6, 0.9, 0.1), mats["steel_dark"], Vector3(0, 0.5, -0.2), Vector3(20, 0, 0)))
		var crew: Array = []
		var g := _make_actor("enemy", "heavy", c + Vector3(0.3, 0, -0.4), Color.BLACK, Color.BLACK, Color.BLACK, 0.0)
		g.set("sfx_shot", "enemy_mg")
		g.set("crouch", true)
		crew.append(g)
		var r := _make_actor("enemy", "rifleman", c + Vector3(-1.0, 0, -0.9), Color.BLACK, Color.BLACK, Color.BLACK, 0.0)
		r.set("crouch", true)
		crew.append(r)
		_targets.append({"id": str(d[0]), "kind": "nest", "pos": c, "radius": 8.5, "alive": true, "phase": 1, "crew": crew, "node": node, "fire_t": 2.0 + float(crew.size())})
	var dug := Node3D.new()
	dug.name = "Unterstand"
	add_child(dug)
	dug.global_position = Vector3(-6.75, y, -165.0)
	_targets.append({"id": "dugout", "kind": "dugout", "pos": Vector3(-6.75, y, -165.0), "radius": 8.0, "alive": true, "phase": 1, "crew": [], "node": dug, "fire_t": 99.0})
	_targets.append({"id": "vehicle", "kind": "vehicle", "pos": VEH_STOP, "radius": 7.0, "alive": true, "phase": 3, "crew": [], "node": null, "fire_t": 99.0})
	_targets.append({"id": "cornice", "kind": "cornice", "pos": CORNICE, "radius": 14.0, "alive": true, "phase": 4, "crew": [], "node": null, "fire_t": 99.0})

func _target(id: String) -> Dictionary:
	for t in _targets:
		if str(t["id"]) == id:
			return t
	return {}

func _target_pos(t: Dictionary) -> Vector3:
	if str(t["kind"]) == "vehicle" and _veh != null and is_instance_valid(_veh):
		return _veh.global_position
	return t["pos"]

## Schuetzenpanzer aus Boxen (bewegt: AnimatableBody als Deckung).
func _build_vehicle() -> void:
	_veh = Node3D.new()
	_veh.name = "Schuetzenpanzer"
	add_child(_veh)
	_veh.global_position = VEH_START
	_veh.rotation.y = PI
	var bd := BP.Builder.new(mats)
	bd.box("spz", Vector3(0, 1.1, 0), Vector3(3.1, 1.3, 6.4))
	bd.box("spz", Vector3(0, 1.55, -2.6), Vector3(3.0, 0.6, 1.4), Basis(Vector3.RIGHT, deg_to_rad(-25.0)))
	bd.box("spz_dark", Vector3(-1.75, 0.55, 0), Vector3(0.45, 1.0, 6.2))
	bd.box("spz_dark", Vector3(1.75, 0.55, 0), Vector3(0.45, 1.0, 6.2))
	bd.box("spz", Vector3(0.2, 2.05, -0.4), Vector3(1.6, 0.6, 2.0))
	bd.box("spz_dark", Vector3(0.2, 2.15, -2.4), Vector3(0.12, 0.12, 2.6))
	bd.box("snow", Vector3(0, 1.78, 1.6), Vector3(2.9, 0.06, 2.6))
	bd.build(_veh)
	var ab := AnimatableBody3D.new()
	ab.name = "Body"
	ab.collision_layer = 1
	ab.collision_mask = 0
	Geo.add_box_shape(ab, Vector3(0, 1.1, 0), Vector3(3.6, 2.0, 6.4))
	_veh.add_child(ab)
	_veh.visible = false

func _build_cabin() -> void:
	_cable_len = CABLE_A.distance_to(CABLE_B)
	_cabin = CabinScript.new()
	_cabin.name = "Kabine"
	_cabin.collision_layer = 1
	_cabin.collision_mask = 0
	_cabin.set("level_ref", self)
	add_child(_cabin)
	_cabin.global_position = _cabin_pos(0.0)
	var bd := BP.Builder.new(mats)
	bd.box("cabin", Vector3(0, -0.95, 0), Vector3(2.2, 0.3, 3.4))
	bd.box("cabin", Vector3(0, 1.05, 0), Vector3(2.2, 0.3, 3.4))
	bd.box("glass_d", Vector3(0, 0.05, 0), Vector3(2.1, 1.7, 3.3))
	for sx: float in [-1.08, 1.08]:
		for sz: float in [-1.68, 1.68]:
			bd.box("cabin", Vector3(sx, 0.05, sz), Vector3(0.1, 1.8, 0.1))
	bd.box("steel_dark", Vector3(0, 2.05, 0), Vector3(0.12, 1.8, 0.12))
	bd.box("steel_dark", Vector3(0, 2.95, 0), Vector3(0.5, 0.3, 1.2))
	bd.build(_cabin)
	Geo.add_box_shape(_cabin, Vector3(0, 0.05, 0), Vector3(2.2, 2.3, 3.4))
	# Weber sitzt drin (Puppe, unverwundbar, Treffer -> on_weber_hit)
	var a: CharacterBody3D = Actor.new()
	a.set("role", "weber")
	a.set("enemy_type", "officer")
	a.set("level_ref", self)
	a.set("frozen", true)
	a.set("unarmed", true)
	a.set_meta("faction", "reich")
	a.set("max_health", 60.0)
	a.set("damage_per_hit", 0.0)
	a.name = "Weber"
	_cabin.add_child(a)
	a.position = Vector3(0.3, -0.8, -0.6)
	a.rotation.y = PI
	_weber = a
	_loop_3d("rail_metal_creak", _cabin, Vector3.ZERO, -14.0, 6.0, 60.0)

func _cabin_pos(prog: float) -> Vector3:
	return CABLE_A.lerp(CABLE_B, prog) - Vector3(0, CABIN_HANG, 0)

func _build_heli() -> void:
	_heli = Node3D.new()
	_heli.name = "Hubschrauber"
	add_child(_heli)
	_heli.global_position = Vector3(-2.0, 4.5, 9.0)
	var bd := BP.Builder.new(mats)
	bd.box("heli", Vector3(0, 0, 0), Vector3(2.4, 2.2, 5.0))
	bd.box("glass_d", Vector3(0, 0.2, -2.7), Vector3(2.0, 1.4, 0.8))
	bd.box("heli", Vector3(0, 0.4, 5.0), Vector3(0.6, 0.6, 5.5))
	bd.box("heli", Vector3(0, 1.2, 7.6), Vector3(0.2, 1.8, 0.8))
	bd.box("steel_dark", Vector3(-1.1, -1.4, 0), Vector3(0.12, 0.12, 4.0))
	bd.box("steel_dark", Vector3(1.1, -1.4, 0), Vector3(0.12, 0.12, 4.0))
	bd.build(_heli)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 1.35, 0)
	_heli.add_child(_rotor)
	_rotor.add_child(Geo.box_mesh_node(Vector3(13.0, 0.06, 0.4), mats["steel_dark"], Vector3.ZERO))
	_rotor.add_child(Geo.box_mesh_node(Vector3(0.4, 0.06, 13.0), mats["steel_dark"], Vector3.ZERO))
	_loop_3d("veh_heli_rotor", _heli, Vector3.ZERO, 2.0, 14.0, 160.0)

# ------------------------------------------------------------------ Ablauf

func _intro() -> void:
	_obj("Zum Beobachtungsposten an der Kante")
	_say(SD.BRANDT, "Kerner, Aksoy – Absetzpunkt. Weiter runter kann ich nicht, da unten sieht man die eigene Hand nicht. Raus!")
	_say(SD.BRANDT, "Weber will heute Morgen über den Pass nach Österreich. Seine Leute halten den Kessel – und Falks Garde-Jäger in grauen Wintermänteln sind auch irgendwo da draußen.")
	_say(SD.LENA, "Die Gebirgsjäger vom Bataillon stehen zu uns. Sie haben einen Mörserzug hinter dem Grat. Ich halte den Funk zu ihnen.")
	_later(7.0, _heli_leave)

func _heli_leave() -> void:
	if _heli == null or not is_instance_valid(_heli):
		return
	var tw := create_tween()
	tw.tween_property(_heli, "global_position", _heli.global_position + Vector3(0, 14, 10), 4.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_heli, "global_position", Vector3(-30, 50, 200), 10.0)
	tw.tween_callback(_heli.queue_free)

func _start_phase1() -> void:
	if _phase >= 1:
		return
	_phase = 1
	_spot_active = true
	spot.set("enabled", true)
	_update_phase1_obj()
	_say(SD.LENA, "Zwei MG-Nester und ein Unterstand unten im Kessel. Fernglas, Ziel markieren – ich gebe es an den Mörserzug. Warte auf die Lücken im Sturm.")
	_later(9.0, func() -> void: wx.call("open_window", 14.0))

func _update_phase1_obj() -> void:
	var n := 0
	for t in _targets:
		if int(t["phase"]) == 1 and not bool(t["alive"]):
			n += 1
	_obj("Stellungen im Kessel ausschalten (%d/3) – [%s] Fernglas, [LMB] Ziel markieren, Pfeiltasten Korrektur" % [n, _key("binoculars")])

func _end_phase1(quiet: bool = false) -> void:
	if _phase != 1:
		return
	_phase = 2
	_spot_active = false
	spot.set("enabled", false)
	_open_gate("g1")
	_obj("Durch den Kessel – Webers Nachhut bei der Zollhütte")
	if not quiet:
		_say(SD.BRANDT, "Alle drei Stellungen sind still. Webers Nachhut zieht sich zur Zollhütte zurück – geht runter und räumt auf.")

func _on_basin() -> void:
	if _phase != 2 or _waves_spawned.has(1):
		return
	_checkpoint("cp_kessel")
	_spawn_wave_alp(1)

func _spawn_wave_alp(index: int) -> void:
	if _waves_spawned.has(index):
		return
	_waves_spawned[index] = true
	wave_started.emit(index)
	var pl := _player()
	var alert_to: Vector3 = pl.global_position if pl != null else Vector3.ZERO
	var list: Array = []
	match index:
		1:
			list = [["rifleman", Vector3(10, -12, -170)], ["assault", Vector3(5, -12, -188)], ["rifleman", Vector3(-10, -12, -172)],
				["heavy", Vector3(14, -12, -158)], ["rifleman", Vector3(-12, -12, -148)], ["marksman", Vector3(2, -12, -196)]]
		2:
			list = [["rifleman", Vector3(22, 0, -282)], ["assault", Vector3(25, 0, -276)], ["marksman", Vector3(18, 0, -287)],
				["rifleman", Vector3(16, -4, -296)], ["assault", Vector3(24, -4, -304)]]
		3:
			list = [["rifleman", Vector3(-7, -4, -322)], ["officer", Vector3(-2, -4, -332)], ["rifleman", Vector3(-9, -4, -310)],
				["assault", Vector3(6, -4, -314)], ["heavy", Vector3(-4, -4, -340)]]
	var faction := "garde_winter" if index == 2 else "reich"
	for d: Array in list:
		var e := _enemy(str(d[0]), d[1] as Vector3, faction, 0.5 if _skill == "novice" else 0.58)
		if e == null:
			continue
		(_waves[index] as Array).append(e)
		if e.has_method("alert"):
			e.call("alert", alert_to, false)
	if index == 1:
		_later(2.5, func() -> void: _say_once("contact1", SD.LENA, "Kontakt! Sie sind noch nicht alle tot."))

func _start_phase3() -> void:
	if _phase != 2:
		return
	_phase = 3
	_checkpoint("cp_sattel")
	_spot_active = true
	spot.set("salvos_left", maxi(int(spot.get("salvos_left")), 6))
	spot.set("enabled", true)
	_obj("Schützenpanzer an der Grenzbrücke mit dem Mörser zerstören")
	_say(SD.BRANDT, "Ein Schützenpanzer rollt von der Bergstation hoch zur Brücke. Wenn der sich dort eingräbt, kommt keiner durch.")
	_veh_drive()

func _veh_drive() -> void:
	if _veh_state != "idle":
		return
	_veh_state = "driving"
	_veh.visible = true
	_veh.global_position = VEH_START
	_loop_3d("veh_tank_engine" if ResourceLoader.exists("res://assets/sfx/veh_tank_engine.ogg") else "rail_metal_creak", _veh, Vector3(0, 1, 0), -2.0, 10.0, 120.0)
	_veh_tw = create_tween()
	_veh_tw.tween_property(_veh, "global_position", VEH_STOP, 16.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_veh_tw.tween_callback(_veh_stopped)

func _veh_stopped() -> void:
	if _veh_state != "driving":
		return
	_veh_state = "stopped"
	_say(SD.LENA, "Er steht. Jetzt oder nie – markier ihn.")
	wx.call("open_window", 14.0)

func _destroy_vehicle(quiet: bool) -> void:
	var t := _target("vehicle")
	if t.is_empty() or not bool(t["alive"]):
		return
	t["alive"] = false
	if _veh_tw != null and _veh_tw.is_valid():
		_veh_tw.kill()
	if _veh_state == "idle" or _veh_state == "driving":
		_veh.global_position = VEH_STOP
		_veh.visible = true
	_veh_state = "dead"
	for c in _veh.get_children():
		if c is AudioStreamPlayer3D:
			(c as Node).queue_free()
		elif c is MeshInstance3D:
			var mi := c as MeshInstance3D
			mi.material_override = mats["spz_dark"]
	Props.fire(self, _veh.global_position + Vector3(0, 2.0, 0), 1.6, true, 3.0, 5.0)
	if not quiet:
		Combat.explode(_veh.global_position + Vector3(0, 1.5, 0), 6.0, 60.0, _player(), 1.5)
		_say(SD.LENA, "Panzer brennt! Treffer!")
		_later(4.0, _start_phase4)

func _start_phase4() -> void:
	if _phase != 3:
		return
	_phase = 4
	_obj("Wechte über der Rinne beschießen – Lawine auslösen")
	_say(SD.BRANDT, "Bewegung in der Rinne westlich von euch. Graue Mäntel – Falks Garde-Jäger. Die wollen zur Bergstation, vor euch.")
	_say(SD.FALK, "Weber gehört mir. Wer sich mir in den Weg stellt, bleibt im Schnee.")
	_say(SD.LENA, "Über der Rinne hängt eine Wechte. Ein Treffer, und der ganze Hang kommt runter.")
	spot.set("salvos_left", maxi(int(spot.get("salvos_left")), 4))
	for i in 5:
		var x := -44.0 + float(i % 3) * 2.5
		var z := -256.0 - float(i) * 2.6
		var gy := _gully_y(x) + 0.4
		var a := _make_actor("enemy", "assault" if i % 2 == 0 else "rifleman", Vector3(x, gy, z), Color.BLACK, Color.BLACK, Color.BLACK, 90.0, "garde_winter")
		a.set("walk_speed", 1.2)
		a.call("walk_to", Vector3(-27.0 + float(i % 2) * 2.0, _gully_y(-27.0), z), 1.0 + 0.1 * float(i), false)
		_garde.append(a)
	_garde_t = 46.0
	_later(5.0, func() -> void: wx.call("open_window", 16.0))

func _gully_y(x: float) -> float:
	# Rampe (-50, 15) -> (-21, -4)
	return lerpf(15.0, -4.0, clampf((x + 50.0) / 29.0, 0.0, 1.0))

func _trigger_avalanche(by_player: bool, quiet: bool = false) -> void:
	if _avalanche:
		return
	_avalanche = true
	var t := _target("cornice")
	if not t.is_empty():
		t["alive"] = false
	_garde_t = -1.0
	if not quiet:
		if by_player:
			_say(SD.LENA, "Da kommt der Hang! Runter, runter!")
			_say(SD.BRANDT, "Die Rinne ist zu. Von den Grauen kommt keiner mehr raus. Die Straße auch nicht – nehmt den Steig über den Grat.")
		else:
			Combat.explode(CORNICE + Vector3(2, 1, 0), 6.0, 0.0, null, 1.6)
			_say(SD.BRANDT, "Sprengung am Hang! Falk jagt die Wechte selbst hoch!")
			_say(SD.LENA, "Er begräbt seine eigenen Leute, nur um die Straße zu sperren...")
			_say(SD.BRANDT, "Die Straße ist zu. Nehmt den Steig über den Grat.")
	# Lawine: Schneebrett rutscht die Rinne hinunter
	_slab = Node3D.new()
	_slab.name = "Lawine"
	add_child(_slab)
	var bd := BP.Builder.new(mats)
	bd.box("snow", Vector3(0, 0, 0), Vector3(14.0, 4.0, 22.0))
	for i in 7:
		bd.ball("snow", Vector3(randf_range(-6, 6), randf_range(1.0, 3.0), randf_range(-10, 10)), Vector3.ONE * randf_range(2.5, 4.5))
	bd.build(_slab)
	_slab.global_position = CORNICE + Vector3(-2, 2, 0)
	var dur := 0.4 if quiet else 4.0
	var tw := create_tween()
	tw.tween_property(_slab, "global_position", Vector3(-12.0, -2.0, -262.0), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_avalanche_landed.bind(quiet))
	if not quiet:
		_sfx_at("river_collapse", Vector3(-30, 6, -262), 6.0, 250.0)
		_sfx_at("river_collapse", Vector3(-20, 0, -262), 4.0, 250.0)
		var pl := _player()
		if pl != null:
			pl.add_trauma(0.6)
		for i in 6:
			_later(0.6 * float(i), func() -> void:
				VFX.spawn_dust_cloud(Vector3(randf_range(-45, -18), _gully_y(-30) + 2.0, randf_range(-272, -252)), 9.0))

func _avalanche_landed(quiet: bool) -> void:
	# Garde in der Rinne verschuettet
	for a in _garde:
		if _alive(a):
			a.call("_die")
	_garde.clear()
	# Schneehaufen auf der Strasse (Kollision nach dem Bake)
	var body := Geo.static_body()
	body.name = "Lawinenkegel"
	body.set_meta("no_fit", true)
	var bd := BP.Builder.new(mats)
	_mm(bd, body, "snow", Vector3(-22, -4.5, -246), Vector3(13, 1.0, -280))
	for i in 9:
		bd.ball("snow", Vector3(randf_range(-20, 10), randf_range(0.0, 1.5), randf_range(-248, -278)), Vector3(randf_range(5, 9), randf_range(2, 4), randf_range(5, 9)))
	add_child(body)
	bd.build(self)
	if _slab != null and is_instance_valid(_slab):
		_slab.queue_free()
	if not quiet:
		VFX.spawn_dust_cloud(Vector3(-6, -2, -262), 14.0)
		VFX.spawn_dust_cloud(Vector3(4, -2, -268), 12.0)
		var pl := _player()
		if pl != null:
			pl.add_trauma(0.4)
		_later(3.0, _start_phase5)

func _start_phase5() -> void:
	if _phase >= 5:
		return
	_phase = 5
	_spot_active = false
	spot.set("enabled", false)
	_open_gate("g2")
	_obj("Über den Grat zur Bergstation")
	_spawn_wave_alp(2)

func _on_ridge() -> void:
	if _phase < 5:
		return
	_checkpoint("cp_grat")
	_say_once("ridge", SD.LENA, "Garde auf dem Grat! Deckung!")

func _start_phase6() -> void:
	if _phase != 5:
		return
	_phase = 6
	_checkpoint("cp_station")
	_obj("Bergstation sichern – nicht auf die Kabine schießen")
	_spawn_wave_alp(3)
	_cabin_moving = true
	_loop_3d("rail_metal_creak", self, Vector3(0, 2.0, -326), -6.0, 8.0, 80.0)
	_say(SD.BRANDT, "Die Seilbahn läuft – Weber sitzt in der Kabine! Nicht darauf schießen, er muss lebend vor Gericht.")
	_say(SD.WEBER, "Kerner. Hartnäckig wie immer. Grüßen Sie Falk von mir – falls er Sie vorher nicht erwischt.")

func _try_finish() -> void:
	if _finished or _phase < 6:
		return
	var alive := 0
	for e in (_waves[3] as Array):
		if _alive(e):
			alive += 1
	if alive > 1 or _cabin_prog < 0.35:
		return
	_finished = true
	_obj("")
	_say(SD.LENA, "Hier, im Steuerraum. Ein Fahrplan – Nachtzug Innsbruck–Wien, heute Abend, mit Webers Handschrift angestrichen.")
	_say(SD.KERNER, "Dann fahren wir mit.")
	_say(SD.BRANDT, "Ich hole euch an der Talstation ab. Österreich weiß Bescheid – mehr oder weniger.")
	_later(9.0, _on_level_end)

# ------------------------------------------------------------------ Moerser-Rueckmeldungen

func _spot_visible(p: Vector3) -> bool:
	if wx == null:
		return true
	if bool(wx.call("is_window_open")):
		return true
	var pl := _player()
	return pl != null and pl.global_position.distance_to(p) < float(wx.call("visibility_range")) * 0.8

func _on_mission_requested(_target_p: Vector3, _dist: float) -> void:
	_salvo_hit = false
	_say_cd("req", 75.0, SD.LENA, "Feuerauftrag ist raus. Mörserzug bestätigt.")

func _on_salvo_fired(_aim: Vector3, _ft: float, _rounds: int) -> void:
	_salvo_hit = false

func _on_correction_sent(_f: float, _r: float) -> void:
	_salvo_hit = false
	_say_cd("corr", 90.0, SD.LENA, "Korrektur ist raus. Nächste Salve auf die verbesserten Werte.")

func _on_mission_refused(reason: String) -> void:
	if _bot and _t >= float(_cd.get("dbg_ref", -1.0)):
		_cd["dbg_ref"] = _t + 5.0
		print("[alpenpass] verweigert: %s" % reason)
	match reason:
		"sicht":
			_say_cd("sicht", 30.0, SD.LENA, "Ich sehe nichts, du siehst nichts. Warte, bis der Sturm Luft holt.")
		"laden":
			_say_cd("laden", 30.0, SD.LENA, "Die Rohre laden noch. Geduld.")
		"leer":
			_request_refill()
		"gesperrt":
			_say_cd("gesperrt", 20.0, SD.BRANDT, "Feuer verweigert! Da hängt Weber drin – wir brauchen ihn lebend.")

func _on_danger_close(_p: Vector3, _who: String) -> void:
	_say_cd("danger", 12.0, SD.LENA, "Das liegt viel zu nah an uns! Wenn du sicher bist, markier es nochmal.")

func _request_refill() -> void:
	if _refill_pending:
		return
	_refill_pending = true
	_say(SD.LENA, "Der Mörserzug meldet: Munition alle. Sie schicken Nachschub hoch.")
	_later(12.0, func() -> void:
		_refill_pending = false
		if spot != null:
			spot.call("refill", 4)
		_say(SD.LENA, "Nachschub ist da. Vier Salven."))

func _on_shell_impact(pos: Vector3, _i: int) -> void:
	for t in _targets:
		if not bool(t["alive"]) or int(t["phase"]) != _phase:
			continue
		var tp := _target_pos(t)
		var d := Vector2(pos.x - tp.x, pos.z - tp.z).length()
		if str(t["kind"]) == "cornice":
			d = pos.distance_to(tp)
		if d < float(t["radius"]):
			_salvo_hit = true
			_destroy_target(t, false)
	if lena != null and is_instance_valid(lena) and pos.distance_to(lena.global_position) < 12.0:
		_say_cd("lena_close", 15.0, SD.LENA, "Kerner! Die lag fast auf mir!")

func _on_salvo_complete(impacts: Array) -> void:
	var open := _open_targets()
	if not _salvo_hit and not open.is_empty():
		_misses += 1
		if _misses == 1:
			_say(SD.LENA, "Daneben. Sag mir die Korrektur – weiter, kürzer, links, rechts.")
		else:
			_say_cd("miss", 70.0, SD.LENA, "Liegt nicht im Ziel. Korrigieren!")
	if not open.is_empty() and int(spot.get("salvos_left")) <= 0:
		_request_refill()
	if _bot:
		print("[alpenpass] salve: treffer=%s ziel=%s" % [str(_salvo_hit), _bt_id])
		_bot_correction(impacts)

func _open_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in _targets:
		if bool(t["alive"]) and int(t["phase"]) == _phase:
			out.append(t)
	return out

func _destroy_target(t: Dictionary, quiet: bool) -> void:
	if not bool(t["alive"]):
		return
	match str(t["kind"]):
		"nest":
			t["alive"] = false
			for a: Variant in (t["crew"] as Array):
				if _alive(a):
					(a as Node).call("_die")
			var n: Node3D = t["node"]
			if n != null and is_instance_valid(n):
				for c in n.get_children():
					(c as Node3D).rotation_degrees += Vector3(randf_range(30, 70), randf_range(-40, 40), 0)
				Props.fire(self, n.global_position + Vector3(0.4, 0.1, 0.2), 0.7, true, 1.5, 3.0)
			if not quiet:
				_say(SD.LENA, "MG-Nest ist weg. Volltreffer.")
		"dugout":
			t["alive"] = false
			var p: Vector3 = t["pos"]
			var b := Geo.box_mesh_node(Vector3(6.4, 0.9, 5.8), mats["logs"], p + Vector3(0, 0.6, 0), Vector3(8, 15, -6))
			add_child(b)
			Props.fire(self, p + Vector3(1, 0.4, 2.4), 0.8, true, 2.0, 3.0)
			if not quiet:
				VFX.spawn_dust_cloud(p, 8.0)
				_say(SD.LENA, "Der Unterstand ist eingestürzt. Gute Arbeit.")
		"vehicle":
			_destroy_vehicle(quiet)
		"cornice":
			_trigger_avalanche(true, quiet)
	if int(t["phase"]) == 1:
		_update_phase1_obj()
		var all_dead := true
		for o in _targets:
			if int(o["phase"]) == 1 and bool(o["alive"]):
				all_dead = false
		if all_dead and not quiet:
			_later(3.0, func() -> void: _end_phase1())

# ------------------------------------------------------------------ Kabine / Weber

func on_cabin_hit(source: Node) -> void:
	if source == null or not is_instance_valid(source) or not source.is_in_group("player"):
		return
	if _t < _cabin_hit_cd:
		return
	_cabin_hit_cd = _t + 1.2
	_cabin_hits += 1
	match _cabin_hits:
		1:
			_say(SD.BRANDT, "Feuer einstellen! Das ist die Kabine!")
		2:
			_say(SD.LENA, "Jonas! Nicht die Kabine!")
		_:
			_cabin_hits = 0
			_say(SD.BRANDT, "Abbruch! So nicht!")
			_later(1.0, func() -> void:
				var pl := _player()
				if pl != null and not pl.dead:
					pl.respawn())

func on_weber_hit() -> void:
	on_cabin_hit(_player())

func on_friendly_hit(_a: Node) -> void:
	_say_cd("ff", 20.0, SD.LENA, "Pass auf, wohin du schießt!")

func on_enemy_wounded(_a: Node) -> void:
	pass

# ------------------------------------------------------------------ Tick

func _process(delta: float) -> void:
	if _rotor != null and is_instance_valid(_rotor):
		_rotor.rotate_y(delta * 22.0)

func _physics_process(delta: float) -> void:
	if spot == null or not is_inside_tree():
		return
	_t += delta
	_tick_cabin(delta)
	_tick_targets(delta)
	_tick_garde(delta)
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = 0.5
		_tick_lena()
		_tick_sight()
		if _phase == 6:
			_try_finish()
	_tick_lena_fire(delta)
	if _bot:
		_tick_bot(delta)
		_dbg_t -= delta
		if _dbg_t <= 0.0:
			_dbg_t = 15.0
			_dbg_status()

func _dbg_status() -> void:
	var pl := _player()
	var alive: Array[String] = []
	for t in _targets:
		if bool(t["alive"]):
			alive.append(str(t["id"]))
	print("[alpenpass] t=%.0f phase=%d pos=%s spot=%s salvos=%d win=%s drive=%s targets=%s veh=%s cabin=%.2f" % [_t, _phase,
		str(pl.global_position.snapped(Vector3.ONE)) if pl != null else "-", str(spot.call("state")), int(spot.get("salvos_left")),
		str(wx.call("is_window_open")), str(bot_drives_player()), ",".join(alive), _veh_state, _cabin_prog])

func _tick_cabin(delta: float) -> void:
	if not _cabin_moving or _cabin == null:
		return
	_cabin_prog = minf(1.0, _cabin_prog + delta * CABIN_SPEED / _cable_len)
	_cabin.global_position = _cabin_pos(_cabin_prog)
	if _cabin_prog > 0.55 and not _cabin_gone:
		_cabin_gone = true
		_say(SD.LENA, "Weg. Der Sturm hat ihn verschluckt.")
		if not _finished:
			_obj("Steuerraum der Bergstation durchsuchen")
	if _cabin_prog >= 1.0:
		_cabin_moving = false
		_cabin.visible = false

func _tick_targets(delta: float) -> void:
	var pl := _player()
	if pl == null:
		return
	var vis := bool(wx.call("is_window_open"))
	# MG-Nester: kosmetische Leuchtspur-Feuerstoesse Richtung Posten
	if _phase == 1:
		for t in _targets:
			if str(t["kind"]) != "nest" or not bool(t["alive"]):
				continue
			var crew: Array = t["crew"]
			var any := false
			for a: Variant in crew:
				if _alive(a):
					any = true
			if not any:
				_destroy_target(t, false)
				continue
			t["fire_t"] = float(t["fire_t"]) - delta
			if float(t["fire_t"]) <= 0.0:
				t["fire_t"] = randf_range(2.5, 4.5) if vis else randf_range(5.0, 8.0)
				var a0: Variant = crew[0]
				if _alive(a0):
					var aim := pl.global_position + Vector3(randf_range(-6, 6), randf_range(-1.0, 3.0), randf_range(-4, 4))
					for k in 4:
						_later(0.12 * float(k), func() -> void:
							if _alive(a0):
								(a0 as Node).call("puppet_fire", aim, 2.0))
	# Schuetzenpanzer: MG-Feuer (kosmetisch), solange er steht
	if _veh_state == "stopped":
		_veh_fire_t -= delta
		if _veh_fire_t <= 0.0:
			_veh_fire_t = randf_range(3.0, 5.0)
			_sfx_at("enemy_mg", _veh.global_position + Vector3(0, 2.2, 0), 2.0, 160.0)
			var fl := _omni(_veh.global_position + Vector3(0.2, 2.2, 2.6), Color(1.0, 0.75, 0.4), 4.0, 6.0)
			_later(0.12, fl.queue_free)

func _tick_garde(delta: float) -> void:
	if _garde_t < 0.0 or _avalanche:
		return
	_garde_t -= delta
	var pl := _player()
	# Garde feuert gelegentlich herueber (kosmetisch)
	if pl != null and randf() < delta * 0.6:
		var a: Variant = _garde.pick_random() if not _garde.is_empty() else null
		if _alive(a):
			(a as Node).call("puppet_fire", pl.global_position + Vector3(randf_range(-5, 5), 1.0, randf_range(-5, 5)), 2.5)
	if _garde_t <= 0.0:
		_trigger_avalanche(false)

func _tick_sight() -> void:
	var f := _sight()
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node and not _is_puppet(e):
			(e as Node).set("sight_range", 55.0 * f)

func _tick_lena() -> void:
	var pl := _player()
	if pl == null or lena == null or not is_instance_valid(lena):
		return
	var to := pl.global_position - lena.global_position
	var dist := to.length()
	if dist > 30.0 or absf(to.y) > 6.0:
		_lena_to_player()
		return
	var spotting := _spot_active and (_phase == 1 or _phase == 3 or _phase == 4)
	lena.set("crouch", spotting)
	var flat := Vector3(to.x, 0, to.z)
	if dist > 4.0:
		var goal := pl.global_position - flat.normalized() * 2.5 + pl.global_transform.basis.x * 1.2
		lena.call("walk_to", goal, 4.4 if dist > 10.0 else 2.6, true)

func _lena_to_player() -> void:
	var pl := _player()
	if pl == null or lena == null:
		return
	var back := pl.global_transform.basis.z
	back.y = 0.0
	lena.global_position = pl.global_position + back.normalized() * 2.0 + pl.global_transform.basis.x * 1.0 + Vector3(0, 0.3, 0)
	lena.set("has_goal", false)

func _tick_lena_fire(delta: float) -> void:
	_lena_fire_t -= delta
	if _lena_fire_t > 0.0 or lena == null:
		return
	_lena_fire_t = randf_range(1.2, 2.2)
	var best: Node3D = null
	var bd := 35.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not _alive(e):
			continue
		var d := (e as Node3D).global_position.distance_to(lena.global_position)
		if d < bd:
			bd = d
			best = e
	if best != null:
		lena.call("puppet_fire", best.global_position + Vector3(0, 1.2, 0), 1.2)

func _on_player_respawned() -> void:
	_lena_to_player.call_deferred()
	_cabin_hits = 0

# ------------------------------------------------------------------ Level-Bot (Beobachter)

func _bot_target() -> Dictionary:
	for t in _targets:
		if not bool(t["alive"]) or int(t["phase"]) != _phase:
			continue
		if str(t["kind"]) == "vehicle" and _veh_state != "stopped":
			continue
		if str(t["kind"]) == "cornice" and _garde.is_empty():
			continue
		return t
	return {}

func _bot_stand() -> Vector3:
	match _phase:
		1:
			return Vector3(0, 0, -52.0)
		_:
			return Vector3(0, -4, -230.0)

func _bot_err() -> float:
	return 10.0 if _skill == "novice" else (5.0 if _skill == "average" else 2.5)

func _tick_bot(delta: float) -> void:
	var pl := _player()
	if pl == null or pl.dead:
		return
	if not bot_drives_player():
		if _bt_had:
			_bt_had = false
			if bool(spot.call("is_up")):
				spot.call("raise", false)
		return
	_bt_had = true
	pl.external_input = true
	var ext: Dictionary = pl.ext
	ext["move"] = Vector2.ZERO
	ext["look"] = Vector2.ZERO
	ext["fire"] = false
	ext["aim"] = false
	ext["sprint"] = false
	ext["crouch"] = false
	# Erst an die Kante des Beobachtungspostens (freie Sicht ueber die Sandsaecke)
	var stand := _bot_stand()
	var off := stand - pl.global_position
	off.y = 0.0
	if off.length() > 0.8:
		var loc := pl.global_transform.basis.inverse() * off.normalized()
		ext["move"] = Vector2(loc.x, -loc.z)
	var t := _bot_target()
	if t.is_empty():
		# warten (Fahrzeug faehrt noch, Garde noch nicht da): Blick in die Zielrichtung
		var look := VEH_STOP if _phase == 3 else (CORNICE if _phase == 4 else Vector3(0, -12, -140))
		if _phase == 3 and _veh_state == "driving":
			look = _veh.global_position
		pl.look_at_point(look + Vector3(0, 1.0, 0))
		return
	var tp := _target_pos(t)
	if str(t["id"]) != _bt_id:
		_bt_id = str(t["id"])
		_bt_marked = false
		_bt_corr = false
		_bt_remark = false
		_bt_wait = _brng.randf_range(0.8, 2.0)
	if not bool(spot.call("is_up")):
		spot.call("raise", true)
		_bt_wait = maxf(_bt_wait, 0.6)
		return
	pl.look_at_point(_bt_aim if _bt_marked else tp + Vector3(0, 0.5, 0))
	if _bt_wait > 0.0:
		_bt_wait -= delta
		return
	if str(spot.call("state")) != "ready":
		return
	if _bt_corr:
		_bt_corr = false
		if bool(spot.call("send_correction")):
			_bt_wait = 1.0
			return
		# Korrektur verweigert (Sperrzone/Gefahr nahe): verwerfen und neu markieren
		spot.call("clear_correction")
		_bt_remark = true
		_bt_wait = 1.0
		return
	if not _bt_marked or _bt_remark:
		if not bool(wx.call("is_window_open")):
			return
		var e := _bot_err()
		_bt_aim = tp + Vector3(_brng.randf_range(-e, e), 0.4, _brng.randf_range(-e, e))
		pl.look_at_point(_bt_aim)
		if bool(spot.call("mark_from_camera")):
			_bt_marked = true
			_bt_remark = false
		_bt_wait = 1.5

func _bot_correction(impacts: Array) -> void:
	if not bot_drives_player() and not _spot_active:
		return
	var t := _target(_bt_id)
	if t.is_empty() or not bool(t["alive"]) or impacts.is_empty():
		return
	var tp := _target_pos(t)
	var mean := Vector3.ZERO
	for p: Variant in impacts:
		mean += p as Vector3
	mean /= float(impacts.size())
	var b: Array = spot.call("ot_basis", tp)
	var diff := tp - mean
	diff.y = 0.0
	var f := diff.dot(b[0] as Vector3)
	var r := diff.dot(b[1] as Vector3)
	if _skill == "novice":
		f += _brng.randf_range(-7.0, 7.0)
		r += _brng.randf_range(-7.0, 7.0)
	var fr := roundf(f / 10.0) * 10.0
	var rr := roundf(r / 10.0) * 10.0
	if fr == 0.0 and rr == 0.0:
		fr = roundf(f / 5.0) * 5.0
		rr = roundf(r / 5.0) * 5.0
	if fr == 0.0 and rr == 0.0:
		_bt_remark = true
		_bt_aim = tp + Vector3(0, 0.4, 0)
	else:
		spot.call("clear_correction")
		spot.call("add_correction", fr, rr)
		_bt_corr = true
		_bt_aim = tp + Vector3(0, 0.4, 0)
	_bt_wait = _brng.randf_range(1.0, 2.5) if _skill != "novice" else _brng.randf_range(2.0, 4.0)

# ------------------------------------------------------------------ Debug-Einstieg

## --phase=N: direkt in Phase N einsteigen (Captures, Tests).
func _debug_phase() -> void:
	var n := int(Game.arg("phase", 0))
	if n <= 0:
		return
	var pl := _player()
	if pl == null:
		return
	if _heli != null:
		_heli.queue_free()
		_heli = null
	var pos := Vector3(0, 0.1, -44.0)
	var first_wp := 2
	if n >= 2:
		_phase = 1
		for t in _targets:
			if int(t["phase"]) == 1:
				_destroy_target(t, true)
		_end_phase1(true)
		pos = Vector3(0, -11.9, -92.0)
		first_wp = 5
	if n >= 3:
		pos = Vector3(0, -3.9, -222.0)
		first_wp = 12
	if n >= 4:
		_start_phase3()
		_destroy_vehicle(true)
		_veh_state = "dead"
		_start_phase4()
		pos = Vector3(0, -3.9, -229.0)
	if n >= 5:
		_trigger_avalanche(true, true)
		_start_phase5()
		pos = Vector3(14, -3.9, -233.0)
		first_wp = 13
	if n >= 6:
		pos = Vector3(12, -3.9, -303.0)
		first_wp = 19
		_start_phase6()
	# Autopilot: bereits erledigte Wegpunkte entfernen (liest die Route erst im naechsten Physikframe)
	for w in get_tree().get_nodes_in_group("bot_waypoint"):
		if int(w.get_meta("order", 0)) < first_wp:
			w.remove_from_group("bot_waypoint")
	pl.global_position = pos
	pl.velocity = Vector3.ZERO
	pl.set_view(0.0, 0.0)
	_lena_to_player()
	_checkpoint("cp_debug_%d" % n)
