extends "res://game/levels/level.gd"
## Mission 10 (Teil 3) "Weißes Rauschen" – Grenzpass bei Mittenwald, 15.06.2030, 06:30.
## Drei Tage nach Rostock will Weber über den Pass nach Österreich. Brandt setzt Kerner und Lena im
## Schneesturm ab. Loyale Gebirgsjäger helfen mit einem Mörserzug (Funk über Lena), Falks Garde-Jäger
## (graue Wintermäntel) sind die dritte Partei. Ende: Weber entkommt mit der Seilbahn – Hinweis auf den
## Nachtzug Innsbruck–Wien.
##
## Overhaul (Hochgebirge): Hoehenmodell-Gelaende (alpenpass_terrain.gd) mit Kessel, Serpentine, Rinne,
## Grat-Steig und Passstrasse; Sturm in Wellen (weather_system.gd, nur Atmosphaere, Sicht nie unter ~200 m);
## Moerser: Ziel markieren = sofort eine Salve (4-5 Granaten, wenige Meter Streuung) genau auf den markierten
## Punkt, danach Nachladezeit – kein Einschiessen, keine Korrektur, keine Sichtfenster; Gegner-Auffindbarkeit
## ueber Muendungsblitze, Uhrzeit-Callouts und HUD-Marker; Hubschrauber als glTF-Slot (heli_gltf.gd).
##
## Ablauf: 0 Absetzen am Joch -> 1 Beobachtungsposten (MG-Nester, Schuetzengruppen + Unterstand per Moerser,
## Gegenstoss die Serpentine hoch) -> 2 Kessel (Nachhut) -> 3 Posten am Sattel (Schuetzenpanzer, MG-Nester und
## Schuetzengruppe an der Strasse + Begleitinfanterie)
## -> 4 Wechte/Lawine gegen Falks Garde in der Rinne -> 5 Grat-Steig unter Zeitdruck (Seilbahn-Countdown)
## -> 6 Bergstation sichern, Kabine nicht treffen -> Steuerraum.

const Terrain = preload("res://game/levels/alpenpass_terrain.gd")
const HeliGltf = preload("res://game/vehicles/models/heli_gltf.gd")
const IfvModel = preload("res://game/vehicles/ifv/ifv_model.gd")
const VF = preload("res://game/vehicles/vehicle_fx.gd")
const BP = preload("res://game/levels/berlin_props.gd")
const NP = preload("res://game/levels/night_props.gd")
const Actor = preload("res://game/levels/overwatch_actor.gd")
const SD = preload("res://game/story/story_data.gd")
const WeatherSystem = preload("res://game/systems/weather_system.gd")
const Spotter = preload("res://game/systems/artillery_spotter.gd")
const CabinScript = preload("res://game/levels/alpenpass_cabin.gd")
const Avalanche = preload("res://game/levels/alpenpass_avalanche.gd")

## glTF-Slot fuer den Hubschrauber (Anforderungen: heli_gltf.gd). Leer = prozedurales heli_model.
## Zur Laufzeit ueberschreibbar: --heli_model=res://pfad/heli.glb
const HELI_MODEL_PATH := "res://assets/models/vehicles/mi8/mi8.scn"   # Brandts Mi-8 (heli_real.gd), Fallback prozedural
const BOULDER_PATH := "res://assets/environment/props/models/boulder_01/boulder_01.gltf"

const FR_PRIMARY := Color(0.86, 0.87, 0.88)        # Lena: weißer Schneeueberwurf
const FR_SECONDARY := Color(0.55, 0.57, 0.58)
const FR_ARMBAND := Color(0.3, 0.68, 1.0)
const GARDE_PRIMARY := Color(0.62, 0.64, 0.66)     # graue Wintermaentel
const GARDE_SECONDARY := Color(0.42, 0.44, 0.46)

const OP1 := Vector2(0.0, -56.0)                   # Beobachtungsposten an der Kante (x, z)
const OP2 := Vector2(0.0, -398.0)                  # Posten am Sattel
const ST := Vector3(0.0, -26.0, -312.0)            # Versatz der Bergstation gegenueber dem alten Layout
const CABLE_A := Vector3(0.0, -23.0, -648.0)
const CABLE_B := Vector3(0.0, 70.0, -1150.0)
const CABIN_HANG := 2.9
const CABIN_SPEED := 5.0
const GATE1_Z := -66.0
const GATE2_Z := -425.0
const DEPART_TIME := 150.0
const FALK_TIME := 75.0
const GARDE_ALERT := 30.0
const ENEMY_SIGHT := 80.0

## Serpentine in den Kessel: vier Schlaege mit Kehren, ~12-14 Grad Gefaelle (vorher bis 24 Grad)
const SERP := [Vector3(6, 2, -62), Vector3(36, -6, -74), Vector3(32, -8, -84), Vector3(-24, -21, -96), Vector3(-26, -23, -106),
	Vector3(24, -36, -122), Vector3(20, -38, -132), Vector3(-4, -44, -150)]
## Anstieg zum Sattel: laenger auslaufend (Talboden-Profil in alpenpass_terrain.gd angepasst), max. ~17 Grad
const KESSEL_UP := [Vector3(-4, -47, -285), Vector3(-2, -42, -310), Vector3(1, -36, -335), Vector3(0, -29, -360), Vector3(0, -22, -386), Vector3(0, -22, -400)]
const ROAD := [Vector3(0, -22, -400), Vector3(4, -23, -430), Vector3(7, -25, -480), Vector3(7, -26, -540), Vector3(6, -28, -600)]
const STEIG := [Vector3(10, -22, -408), Vector3(30, -16, -425), Vector3(46, -11, -450), Vector3(50, -11, -500), Vector3(48, -15, -550), Vector3(34, -26, -585), Vector3(23, -29.5, -597), Vector3(16, -30, -605)]
const RINNE := [Vector3(-80, 12, -478), Vector3(-55, -8, -450), Vector3(-28, -21, -415)]
const VEH_PATH := [Vector2(12, -622), Vector2(10, -600), Vector2(7, -560)]
## Moerserziele (x, z): MG-Nester (M2 auf Dreibein) und Schuetzengruppen hinter Sandsaecken
const NESTS_P1 := [["nest_a", Vector2(-42, -240)], ["nest_b", Vector2(40, -275)], ["nest_c", Vector2(24, -205)], ["nest_d", Vector2(-30, -288)]]
const SQUADS_P1 := [["squad_a", Vector2(52, -224)], ["squad_b", Vector2(-50, -262)]]
const NESTS_P3 := [["nest_e", Vector2(-14, -515)], ["nest_f", Vector2(20, -548)]]
const SQUADS_P3 := [["squad_c", Vector2(-10, -575)]]
## Physik-Ebene 10: unsichtbare Ziel-Kollider nur fuer den Entfernungsmesser (blocken weder Bewegung noch Schuesse)
const LASE_LAYER := 512

var mats: Dictionary = {}
var ter: Terrain
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
var _targets: Array[Dictionary] = []    ## {id, kind, name, pos, radius, hp, alive, phase, crew, node, fire_t, seen}
var _spot_active: bool = false
var _salvo_hit: bool = false
var _misses: int = 0
var _refill_pending: bool = false
var _veh: Node3D
var _veh_parts: Dictionary = {}
var _veh_state: String = "idle"       ## idle | driving | stopped | dead
var _veh_i: int = 0
var _veh_fire_t: float = 3.0
var _escort: Array[Node3D] = []
var _garde: Array[Node3D] = []
var _garde_alert_t: float = -1.0
var _falk_t: float = -1.0
var _falk_warned: bool = false
var _avalanche: bool = false
var _backdrop: MeshInstance3D
var _env: Environment
var _optic_fog: Vector2 = Vector2(-1.0, -1.0)    # zuletzt geschriebene Nebeldichte (tief, volumetrisch) bei gehobenem Fernglas
var _optic_base: Vector2 = Vector2.ZERO          # Wetter-Nebeldichte ohne Optik-Faktor
var _debug_god: bool = false
var _wechte: Node3D
var _wechte_body: StaticBody3D
var _cabin: AnimatableBody3D
var _cabin_prog: float = 0.0
var _cabin_moving: bool = false
var _cabin_hits: int = 0
var _cabin_hit_cd: float = 0.0
var _cabin_gone: bool = false
var _cable_len: float = 1.0
var _cable_t: float = -1.0
var _late: bool = false
var _weber: Node3D
var _waves: Dictionary = {1: [], 2: [], 3: [], 9: []}
var _finished: bool = false
var _tick_t: float = 0.0
var _dbg_t: float = 0.0
var _lena_fire_t: float = 2.0
var _heli: Node3D
var _heli_parts: Dictionary = {}
var _heli_angle: float = 0.0
var _heli_dust_t: float = 0.0
var _counter_t: float = -1.0
var _counter: Array[Node3D] = []
var _report_t: float = 14.0
# HUD / Auffindbarkeit
var _hud: CanvasLayer
var _hud_ctrl: Control   ## Weltmarker (unproject_position -> echte Pixel)
var _hud_root: UIStyle.HudRoot
var _hud_ui: Control     ## Moerser-Tafel und Countdown (1080p-Flaeche unter HudRoot, skaliert mit dem Fenster)
var _reveal: Dictionary = {}            ## instance_id -> {n: Node3D, until: float}
var _shots: Dictionary = {}             ## instance_id -> int (stat_shots)
var _flash_cd: Dictionary = {}          ## instance_id -> float
var _tut: Dictionary = {}               ## raise | mark | impact
var _tut_on: bool = false
var _callout_cd: float = 0.0
# Level-Bot (Beobachter)
var _bt_id: String = ""
var _bt_next: String = "mark"           ## mark | wait
var _bt_wait: float = 0.0
var _bt_idle: float = 0.0
var _bt_aim := Vector3.ZERO
var _bt_had: bool = false
var _wp_idx: Dictionary = {}            ## Wegpunkt-Indizes fuer --phase (kessel | sattel | steig | station)
var _brng := RandomNumberGenerator.new()

func _init() -> void:
	level_name = "alpenpass"
	end_z = -650.0
	build_seed = 1506
	_wave_count = 3
	default_faction = "reich"
	ambient_artillery = false

func _ready() -> void:
	_bot = str(Game.arg("autopilot", "")) not in ["", "false", "0"] or str(Game.arg("spotbot", "")) not in ["", "false", "0"]  # spotbot: Level-Bot ohne Autopilot (Screenshots per DebugServer)
	_skill = str(Game.arg("skill", "average"))
	_brng.seed = 1506 + (7 if _skill == "novice" else 0)
	await super()
	if not is_inside_tree():
		return
	_build_runtime()
	RenderingServer.frame_pre_draw.connect(_optic_env)
	if str(Game.arg("shots", "")) != "":   # Debug-Aufnahmen mit festen Kameras (villa_shots.gd)
		add_child(load("res://game/levels/tools/villa_shots.gd").new())
	tree_exiting.connect(func() -> void:
		if RenderingServer.frame_pre_draw.is_connected(_optic_env):
			RenderingServer.frame_pre_draw.disconnect(_optic_env))
	Events.player_respawned.connect(_on_player_respawned)
	Events.player_damaged.connect(_on_player_damaged)
	var n := int(Game.arg("phase", 0))
	_debug_god = str(Game.arg("god", "")) not in ["", "false", "0"]  # Captures: Spieler-HP wird laufend aufgefuellt
	var wxa := str(Game.arg("wx", ""))  # Captures: --wx=clear / --wx=storm haelt das Wetter fest
	if wxa != "" and wx != null:
		wx.call("set_intensity", 0.0 if wxa == "clear" else 1.0, 0.1)
	if n > 0:
		_debug_phase(n)
	else:
		_intro()

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Weißes Rauschen"
	return info

## Autopilot-Hook: waehrend der Beobachterteile steuert der Level-Bot (Fernglas, Markieren).
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

## Funkzeile mit StoryUI-Optionen (max_age/valid/priority/cut/key/drop_live, siehe story_ui.gd say()).
## Zeilen im selben Frame bilden ein Gespraech: jede kommt direkt nach ihrer Vorgaengerin.
func _say_opt(speaker: String, text: String, dur: float, opts: Dictionary) -> void:
	get_tree().call_group(&"story_ui", &"say", speaker, text, dur, opts)

## Restdauer laufender + wartender Funkzeilen.
func _radio_left() -> float:
	var ui := get_tree().get_first_node_in_group(&"story_ui")
	if ui != null and ui.has_method("busy_left"):
		return float(ui.call("busy_left"))
	return 0.0

## f ausfuehren, sobald der Funk frei ist (hoechstens max_wait s warten).
func _when_radio_free(f: Callable, max_wait: float = 6.0) -> void:
	if _radio_left() <= 0.3 or max_wait <= 0.0:
		f.call()
		return
	_later(0.25, _when_radio_free.bind(f, max_wait - 0.25))

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

func _say_cd_opt(key: String, cd: float, speaker: String, text: String, opts: Dictionary) -> void:
	if _t < float(_cd.get(key, -1000.0)):
		return
	_cd[key] = _t + cd
	_say_opt(speaker, text, 0.0, opts)

## Kurzlebige Rückmeldung: nur wenn der Funk frei ist – sonst staut sich die Warteschlange und
## die Zeile käme Sekunden zu spät (der HUD zeigt dieselbe Information ohnehin).
func _radio_busy() -> bool:
	var ui := get_tree().get_first_node_in_group("story_ui")
	return ui != null and bool(ui.get("_showing"))

func _say_idle(key: String, cd: float, speaker: String, text: String) -> void:
	if _radio_busy():
		return
	_say_cd(key, cd, speaker, text)

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

func _sfx_at(sfx_name: String, pos: Vector3, vol: float = 0.0, maxd: float = 90.0, pitch: float = 1.0) -> void:
	var st := Sfx.get_stream(sfx_name)
	if st == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "SFX"
	p.pitch_scale = pitch
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

## Gelaendepunkt (x, z) mit Hoehe + up.
func _gp(x: float, z: float, up: float = 0.0) -> Vector3:
	return Vector3(x, ter.height(x, z) + up, z)

## Station: alte Koordinaten -> neue Lage.
func _so(v: Vector3) -> Vector3:
	return v + ST

static func _poly_dist(p: Vector2, pts: Array) -> float:
	var best := INF
	for i in range(pts.size() - 1):
		var a3: Vector3 = pts[i]
		var b3: Vector3 = pts[i + 1]
		var a := Vector2(a3.x, a3.z)
		var ab := Vector2(b3.x, b3.z) - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best

## Uhrzeit-Richtung (1..12) eines Punkts relativ zur Blickrichtung des Spielers.
func _clock(p: Vector3) -> int:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 12
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return 12
	fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var to := p - cam.global_position
	to.y = 0.0
	var a := rad_to_deg(atan2(to.dot(right), to.dot(fwd)))
	var h := roundi(a / 30.0)
	if h <= 0:
		h += 12
	return h

func _dist_to_player(p: Vector3) -> float:
	var pl := _player()
	return pl.global_position.distance_to(p) if pl != null else 9999.0

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.49, 0.68)
	sky_mat.sky_horizon_color = Color(0.76, 0.82, 0.9)
	sky_mat.ground_bottom_color = Color(0.72, 0.75, 0.8)
	sky_mat.ground_horizon_color = Color(0.8, 0.83, 0.88)
	sky_mat.sun_angle_max = 40.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.64, 0.74, 0.95)        # blaeuliches Himmelslicht -> blaue Schatten im Schnee
	env.ambient_light_energy = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.81, 0.86)
	env.fog_density = 0.01
	env.fog_sky_affect = 1.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.01
	env.volumetric_fog_albedo = Color(0.9, 0.92, 0.95)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_anisotropy = 0.3
	env.volumetric_fog_length = 64.0
	env.volumetric_fog_ambient_inject = 0.6
	env.glow_enabled = true
	env.glow_hdr_threshold = 1.0
	env.glow_intensity = 0.5
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.light_energy = 1.05
	sun.rotation_degrees = Vector3(-34.0, 150.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	sun.light_volumetric_fog_energy = 0.4
	add_child(sun)
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "day_war")
	# Schnee: nicht ausgewaschen und nicht grau -> etwas mehr Belichtung, weniger Kontrast/Entsaettigung
	env.tonemap_exposure = 0.95
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.92
	_env = env

# ------------------------------------------------------------------ Gelaende

func _build_ground() -> void:
	mats = BP.materials()
	mats["ter"] = Terrain.material()
	mats["snow"] = NP.snowy("", Color(0.93, 0.95, 0.99), 1.0, 1.0)
	mats["rock"] = mats["ter"]
	mats["concrete"] = NP.concrete(Color(0.62, 0.62, 0.6), 0.35)
	mats["metal"] = NP.metal(Color(0.42, 0.42, 0.44), 0.3)
	mats["wood"] = NP.planks(Color(0.45, 0.34, 0.24), 0.3)
	mats["logs"] = NP.planks(Color(0.32, 0.25, 0.18), 0.55)
	mats["steel_dark"] = Geo.flat(Color(0.12, 0.12, 0.13), 0.45, 0.7)
	mats["steel_grey"] = Geo.flat(Color(0.3, 0.31, 0.32), 0.5, 0.75)
	mats["cabin"] = Geo.flat(Color(0.62, 0.1, 0.08), 0.5, 0.2)
	mats["glass_d"] = Geo.flat(Color(0.08, 0.1, 0.12), 0.1, 0.6)
	mats["warn"] = Geo.flat(Color(0.8, 0.6, 0.05), 0.6)
	mats["red_white"] = Geo.flat(Color(0.75, 0.12, 0.1), 0.6)
	mats["white"] = Geo.flat(Color(0.85, 0.85, 0.83), 0.7)
	# Pultanzeige statt ueberstrahlender Leuchtflaeche (war unshaded 3.0/2.4/1.4 -> greller Fleck im Steuerraum)
	var pult := StandardMaterial3D.new()
	pult.albedo_color = Color(0.05, 0.06, 0.06)
	pult.roughness = 0.2
	pult.emission_enabled = true
	pult.emission = Color(0.3, 0.42, 0.34)
	pult.emission_energy_multiplier = 0.45
	mats["lamp"] = pult
	# Innenputz der Station: feiner, heller Anstrich statt grobem Aussenputz (Nahsicht im Steuerraum)
	mats["st_inner"] = preload("res://game/levels/overwatch_world_kit.gd").pbr("res://assets/environment/facade/textures/painted_plaster_wall", Color(0.74, 0.73, 0.7), 0.7, 1.0)
	mats["st_wall"] = NP.snowy("res://assets/environment/facade/textures/rough_plaster_broken", Color(0.8, 0.82, 0.84), 0.45, 0.22)
	mats["st_stone"] = NP.snowy("res://assets/environment/berlin/textures/large_sandstone_blocks", Color(0.62, 0.61, 0.6), 0.32, 0.3)
	mats["wreck"] = Geo.flat(Color(0.05, 0.05, 0.05), 0.95)
	var t0 := Time.get_ticks_msec()
	ter = Terrain.new(build_seed)
	_stamp_terrain()
	ter.build()
	var t1 := Time.get_ticks_msec()
	ter.build_collision(world)
	ter.build_visual(self, mats["ter"])
	(mats["ter"] as ShaderMaterial).set_shader_parameter("road_mask", ter.road_mask())
	_backdrop = ter.build_backdrop(self)
	print("[alpenpass] Gelaende: Raster %d ms, Knoten %d ms" % [t1 - t0, Time.get_ticks_msec() - t1])

func _stamp_terrain() -> void:
	# Weiche, breite Raender (fall): keine sichtbaren Plateau-Kanten/Ellipsen im Kessel
	ter.pad(Vector2(0, 5), 6.0, 18.0, 14.0)                        # Absetzpunkt am Joch
	ter.pad(OP1, 2.0, 6.0, 6.0)                                     # Beobachtungsposten 1
	ter.path(SERP, 6.0, 8.0, true)                                  # Serpentine in den Kessel (Fahrweg)
	for c: Vector2 in [Vector2(6, -305), Vector2(18, -262)] + _target_spots(1):
		ter.pad(c, NAN, 5.0, 12.0)                                  # Nester, Schuetzengruppen, Unterstand, Zollhuette
	ter.pad(OP2, -22.0, 14.0, 14.0)                                 # Posten 2 am Sattel (vor dem Anstieg: Strasse hat Vorrang)
	ter.path(KESSEL_UP, 8.0, 10.0, true)                            # Anstieg zum Sattel (Strasse)
	ter.path(ROAD, 7.0, 9.0, true)                                  # Passstrasse
	ter.path(STEIG, 4.0, 11.0)                                       # Grat-Steig im Osten
	ter.path(RINNE, 10.0, 14.0)                                     # Lawinenrinne im Westen
	ter.rect(-22.0, 18.0, -672.0, -598.0, -30.0, 12.0)              # Bergstation
	for c: Vector2 in _target_spots(3):
		ter.pad(c, NAN, 4.5, 9.0)                                   # Nester/Schuetzengruppe an der Passstrasse

func _build_street() -> void:
	_build_boundaries()
	_build_forest()
	_build_boulders()
	_build_snow_bridges()
	_build_powerline()
	_build_huts()
	var bd := BP.Builder.new(mats)
	var body := Geo.static_body()
	body.name = "Bauten"
	body.set_meta("no_fit", true)
	_build_basin_works(bd, body)
	_build_station(bd, body)
	_build_cableway(bd)
	_build_border(bd, body)
	world.add_child(body)
	bd.build(world)

## Unsichtbare Grenzen (nicht im Navmesh: unter self).
func _build_boundaries() -> void:
	var b := Geo.static_body()
	b.name = "Grenzen"
	b.set_meta("no_fit", true)
	Geo.add_box_shape(b, Vector3(0, 0, 42), Vector3(320, 400, 2))
	Geo.add_box_shape(b, Vector3(0, 0, -690), Vector3(320, 400, 2))
	Geo.add_box_shape(b, Vector3(-150, 0, -320), Vector3(2, 400, 800))
	Geo.add_box_shape(b, Vector3(150, 0, -320), Vector3(2, 400, 800))
	add_child(b)
	# Lawinenkegel-Sperre auf der Strasse hinter Sperre 2: von Anfang an im Navmesh, damit KI und Bot den
	# Grat-Steig nehmen (vor der Lawine kommt der Spieler wegen Sperre 2 ohnehin nicht hierher).
	var cone := Geo.static_body()
	cone.name = "Lawinenkegel"
	cone.set_meta("no_fit", true)
	cone.collision_layer = 16       # move_block: blockt Bewegung, nicht Sicht/Moerser-Entfernungsmesser
	Geo.add_box_shape(cone, Vector3(-14, -16, -453), Vector3(72, 28, 42))
	world.add_child(cone)

func _near_route(x: float, z: float, r: float) -> bool:
	var p := Vector2(x, z)
	for poly: Array in [SERP, KESSEL_UP, ROAD, STEIG]:
		if _poly_dist(p, poly) < r:
			return true
	if _poly_dist(p, RINNE) < r + 8.0:
		return true
	for c: Vector2 in [Vector2(0, 5), OP1, OP2, Vector2(6, -305), Vector2(18, -262)] + _target_spots(1) + _target_spots(3):
		if p.distance_to(c) < r + 10.0:
			return true
	if x > -30.0 and x < 26.0 and z < -590.0 and z > -680.0:
		return true
	return false

## Fichtenwald: Baumgruppen (Waldinseln) auf Almen und unteren Haengen, Einzelbaeume am Waldrand,
## Latschen (Legfoehren) hoeher oben.
func _build_forest() -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = build_seed + 11
	var trees: Array = []
	var centers: Array[Vector2] = []
	var tries := 0
	while centers.size() < 70 and tries < 12000:
		tries += 1
		var x := prng.randf_range(-156.0, 156.0)
		var z := prng.randf_range(-700.0, 36.0)
		var off := ter.height(x, z) - Terrain._tab(Terrain.FLOOR, z)
		if off < 1.0 or off > 55.0 or ter.normal(x, z).y < 0.8 or _near_route(x, z, 16.0):
			continue
		var c := Vector2(x, z)
		var close := false
		for o in centers:
			if o.distance_to(c) < 24.0:
				close = true
				break
		if not close:
			centers.append(c)
	for c in centers:
		var n := prng.randi_range(5, 13)
		var rad := prng.randf_range(8.0, 17.0)
		for k in n:
			var a := prng.randf() * TAU
			var rr := rad * sqrt(prng.randf())
			var x := c.x + cos(a) * rr
			var z := c.y + sin(a) * rr
			var h := ter.height(x, z)
			if h - Terrain._tab(Terrain.FLOOR, z) < 0.5 or ter.normal(x, z).y < 0.74 or _near_route(x, z, 6.0):
				continue
			# innen hoehere Baeume, am Rand juengere
			var sc := lerpf(15.0, 8.0, rr / rad) * prng.randf_range(0.8, 1.1)
			trees.append([Vector3(x, h - 0.3, z), sc / NP.TREE_H])
	tries = 0
	var single := 0
	while single < 170 and tries < 20000:
		tries += 1
		var x := prng.randf_range(-156.0, 156.0)
		var z := prng.randf_range(-700.0, 36.0)
		var h := ter.height(x, z)
		var off := h - Terrain._tab(Terrain.FLOOR, z)
		if off < 1.5 or off > 48.0:
			continue
		if ter.normal(x, z).y < 0.8:
			continue
		if _near_route(x, z, 8.0):
			continue
		trees.append([Vector3(x, h - 0.3, z), prng.randf_range(6.0, 14.0) / NP.TREE_H])
		single += 1
	print("[alpenpass] Baeume: %d (Gruppen %d)" % [trees.size(), centers.size()])
	NP.forest(self, trees, prng, true)
	var dwarf: Array = []
	tries = 0
	while dwarf.size() < 260 and tries < 24000:
		tries += 1
		var x := prng.randf_range(-150.0, 150.0)
		var z := prng.randf_range(-700.0, 36.0)
		var h := ter.height(x, z)
		var off := h - Terrain._tab(Terrain.FLOOR, z)
		if off < 12.0 or off > 75.0:
			continue
		if ter.normal(x, z).y < 0.72:
			continue
		if _near_route(x, z, 5.0):
			continue
		dwarf.append([Vector3(x, h - 0.2, z), prng.randf_range(1.8, 3.2) / NP.TREE_H])
	NP.forest(self, dwarf, prng, false)

## Poly-Haven-Felsbrocken (boulder_01) im Kessel als Deckung.
func _build_boulders() -> void:
	if not ResourceLoader.exists(BOULDER_PATH):
		return
	var ps := load(BOULDER_PATH) as PackedScene
	if ps == null:
		return
	var prng := RandomNumberGenerator.new()
	prng.seed = build_seed + 23
	var spots: Array[Vector2] = [Vector2(-20, -215), Vector2(16, -228), Vector2(-30, -262), Vector2(28, -250), Vector2(-12, -292),
		Vector2(22, -318), Vector2(-26, -312), Vector2(-6, -232), Vector2(34, -300), Vector2(-36, -205)]
	for c in spots:
		var inst := ps.instantiate() as Node3D
		if inst == null:
			continue
		var aabb := AABB()
		var first := true
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var bb := (mi as MeshInstance3D).get_aabb()
			aabb = bb if first else aabb.merge(bb)
			first = false
		var want := prng.randf_range(2.6, 4.6)
		var s := want / maxf(maxf(aabb.size.x, aabb.size.z), 0.1)
		var yaw := prng.randf() * TAU
		var pos := _gp(c.x, c.y, -0.25 * aabb.size.y * s)
		inst.scale = Vector3.ONE * s
		inst.rotation.y = yaw
		inst.position = pos
		inst.set_meta("no_fit", true)
		add_child(inst)
		var b := Geo.static_body(pos, rad_to_deg(yaw))
		b.set_meta("no_fit", true)
		var sz := aabb.size * s * Vector3(0.8, 1.0, 0.8)
		Geo.add_box_shape(b, (aabb.position + aabb.size * 0.5) * s, sz)
		world.add_child(b)
		for side: Vector3 in [Vector3(sz.x * 0.6 + 0.6, 0, 0), Vector3(-sz.x * 0.6 - 0.6, 0, 0)]:
			covers.append(pos + Basis(Vector3.UP, yaw) * side)

## Lawinenverbauung (Stahl-Schneebruecken) an West- und Osthang.
func _build_snow_bridges() -> void:
	var bd := BP.Builder.new(mats)
	for spec: Array in [[-1.0, -195.0, -265.0], [1.0, -285.0, -345.0], [-1.0, -500.0, -540.0]]:
		var side: float = spec[0]
		var z := float(spec[1])
		while z > float(spec[2]):
			for row in 4:
				var hw := Terrain._tab(Terrain.HALF_W, z)
				var aw := Terrain.alm_w(z)
				var x := side * (hw + (aw + 10.0 if aw > 1.0 else 26.0) + float(row) * 10.0)
				var y := ter.height(x, z)
				var n := ter.normal(x, z)
				var lean := Basis(Vector3.FORWARD, side * 0.35)
				for k in 2:
					bd.box("steel_dark", Vector3(x, y + 1.4, z + (-2.3 if k == 0 else 2.3)), Vector3(0.14, 3.0, 0.14), lean)
				for bar in 5:
					bd.box("steel_grey", Vector3(x - side * 0.25 * float(bar) * n.x, y + 0.5 + float(bar) * 0.6, z), Vector3(0.1, 0.12, 5.0), lean)
			z -= 6.0
	bd.build(self)

## Strommasten entlang der Ostseite.
func _build_powerline() -> void:
	var pts: Array = []
	for c: Vector2 in [Vector2(-16, 26), Vector2(-20, -8), Vector2(-26, -42), Vector2(-34, -80), Vector2(-46, -120), Vector2(-50, -165),
			Vector2(-50, -210), Vector2(-48, -300), Vector2(-40, -340), Vector2(-30, -372), Vector2(-14, -410)]:
		pts.append(_gp(c.x, c.y))
	NP.power_line(self, pts, rng)
	var pts2: Array = []
	for c: Vector2 in [Vector2(-6, -430), Vector2(-6, -480), Vector2(-4, -530), Vector2(-2, -580), Vector2(-14, -612)]:
		pts2.append(_gp(c.x, c.y))
	NP.power_line(self, pts2, rng)

func _build_huts() -> void:
	NP.house(world, _gp(-20, 22), 25.0, Vector3(8.0, 3.0, 6.5), Color(0.42, 0.3, 0.2), rng, {"lit": true})       # Alm am Joch
	NP.house(world, _gp(22, -262), -80.0, Vector3(6.0, 2.8, 5.0), Color(0.5, 0.36, 0.24), rng)                    # Zollhuette im Kessel
	NP.house(world, _gp(-17, -606), 90.0, Vector3(8.0, 3.2, 7.0), Color(0.55, 0.52, 0.48), rng, {"lit": true})   # Grenzhaus

## Kessel: Unterstand (Ziel), Schranke an der Zollhuette.
func _build_basin_works(bd: BP.Builder, body: StaticBody3D) -> void:
	var d := _gp(6, -305)
	_mm(bd, body, "logs", d + Vector3(-2.75, -0.3, 2.5), d + Vector3(2.75, 1.4, -2.5))
	bd.box("snow", d + Vector3(0, 1.6, 0), Vector3(6.0, 0.4, 5.5))
	bd.box("black", d + Vector3(0, 0.7, 2.56), Vector3(3.0, 0.4, 0.05))
	var g := _gp(13, -262)
	bd.box("warn", g + Vector3(0, 1.0, 0), Vector3(0.12, 0.12, 7.5))
	bd.box("metal", g + Vector3(0, 0.5, 4.0), Vector3(0.3, 1.0, 0.3))

## Bergstation: Halle, Steuerraum, Umlenkrad, Strassensperre (Layout wie zuvor, neue Lage).
func _build_station(bd: BP.Builder, body: StaticBody3D) -> void:
	var y := -4.0
	var top := 4.0
	# Huelle: Kollision wie bisher (volle Waende), Optik aus Bruchsteinsockel, Putzflaechen mit echten
	# Fensteroeffnungen (Rahmen, Steingewaende, Bank, Glas), Sturz ueber dem Tor, Dachplatte mit Blechkante.
	var parts := BP.FK.Parts.new()
	var wins := BP.FK.WindowBatch.new()
	var wr := RandomNumberGenerator.new()
	wr.seed = 4711
	for ab: Array in [
			[Vector3(-12.5, y, -318), Vector3(-12, top, -345.5)], [Vector3(8, y, -318), Vector3(8.5, top, -345.5)],
			[Vector3(-12, y, -345), Vector3(-3, top, -345.5)], [Vector3(3, y, -345), Vector3(8, top, -345.5)],
			[Vector3(-12, y, -317.5), Vector3(-6, top, -318)], [Vector3(4, y, -317.5), Vector3(8, top, -318)],
			[Vector3(-6, y + 5.4, -317.5), Vector3(4, top, -318)]]:
		var a := _so(ab[0])
		var b := _so(ab[1])
		Geo.add_box_shape(body, (a + b) * 0.5, (b - a).abs())
	var wz: Array = [-321.6, -326.2, -330.8, -335.4, -340.0]
	# Seitenwaende (Fensterband), Rueckwand (Seilausfahrt), Front (Tor mit Sturz)
	_st_face(bd, parts, wins, wr, Vector3(-12.5, y, -331.75), Vector3.LEFT, 27.5, 8.0, wz.map(func(z): return [z + 331.75, 2.2, 3.3, 5.6]))
	_st_face(bd, parts, wins, wr, Vector3(8.5, y, -331.75), Vector3.RIGHT, 27.5, 8.0, wz.map(func(z): return [-331.75 - z, 2.2, 3.3, 5.6]))
	_st_face(bd, parts, wins, wr, Vector3(-2.0, y, -345.5), Vector3.FORWARD, 20.0, 8.0, [[5.5, 2.0, 3.3, 5.6], [-2.0, 6.0, 0.0, 8.0, true], [-7.5, 2.0, 3.3, 5.6]])
	_st_face(bd, parts, wins, wr, Vector3(-2.0, y, -317.5), Vector3.BACK, 21.0, 8.0, [[-7.25, 2.2, 3.3, 5.6], [1.0, 10.0, 0.0, 5.4, true], [8.25, 1.6, 3.3, 5.6]])
	# Torrahmen aus Stahl + Laibung
	bd.box("steel_dark", _so(Vector3(-1.0, y + 5.3, -317.42)), Vector3(10.2, 0.25, 0.3))
	for sx: float in [-6.0, 4.0]:
		bd.box("st_stone", _so(Vector3(sx, y + 2.7, -317.5)), Vector3(0.36, 5.4, 0.62))
	# Dachplatte mit Ueberstand, Blechkante, Schneeauflage, Fallrohre
	_mm(bd, body, "concrete", _so(Vector3(-12.5, top, -317.5)), _so(Vector3(8.5, top + 0.5, -345.5)))
	bd.box("st_wall", _so(Vector3(-2.0, top + 0.32, -331.5)), Vector3(22.8, 0.44, 29.8))
	for e: Array in [[Vector3(-2.0, 0, -316.6), Vector3(22.9, 0.5, 0.06)], [Vector3(-2.0, 0, -346.4), Vector3(22.9, 0.5, 0.06)],
			[Vector3(-13.42, 0, -331.5), Vector3(0.06, 0.5, 29.9)], [Vector3(9.42, 0, -331.5), Vector3(0.06, 0.5, 29.9)]]:
		var ep: Vector3 = e[0]
		bd.box("steel_grey", _so(Vector3(ep.x, top + 0.34, ep.z)), e[1])
	bd.box("snow", _so(Vector3(-2.0, top + 0.68, -331.5)), Vector3(22.6, 0.3, 29.6))
	for dp: Array in [[Vector3(-12.5, 0, -318.6), Vector3.LEFT], [Vector3(-12.5, 0, -344.4), Vector3.LEFT], [Vector3(8.5, 0, -318.6), Vector3.RIGHT], [Vector3(8.5, 0, -344.4), Vector3.RIGHT]]:
		BP.FK.downpipe(parts, _so(dp[0]), dp[1], ST.y + y, ST.y + top + 0.3, "metal")
	# Lueftungsaufbau + Antenne auf dem Dach
	bd.box("st_wall", _so(Vector3(-7.0, top + 1.2, -338.0)), Vector3(2.4, 1.6, 2.0))
	bd.box("snow", _so(Vector3(-7.0, top + 2.05, -338.0)), Vector3(2.5, 0.12, 2.1))
	bd.box("steel_grey", _so(Vector3(5.5, top + 3.0, -342.0)), Vector3(0.08, 5.0, 0.08))
	parts.build(self, {
		"frame": BP.FK.frame_mat(Color(0.3, 0.21, 0.13)),
		"sill": mats["st_stone"],
		"metal": BP.FK.metal_mat(Color(0.3, 0.31, 0.32)),
	}, [], {})
	var gl := wins.build_node(BP.FK.window_mat("day"))
	if gl != null:
		add_child(gl)
	# Steuerraum (Ostseite, offen zur Halle)
	_mm(bd, body, "concrete", _so(Vector3(3, y, -330)), _so(Vector3(8, 0.0, -330.4)))
	_mm(bd, body, "concrete", _so(Vector3(3, y, -341.6)), _so(Vector3(8, 0.0, -342)))
	_mm(bd, body, "steel_dark", _so(Vector3(6.4, y, -333.5)), _so(Vector3(7.8, y + 1.05, -339.0)))
	bd.box("lamp", _so(Vector3(7.1, y + 1.08, -336.2)), Vector3(1.0, 0.04, 2.6))
	# Bahnsteig-Kante und Umlenkrad
	_mm(bd, body, "concrete", _so(Vector3(-10, y, -322)), _so(Vector3(-4, y + 0.9, -343)))
	_pipe(bd, "steel_dark", _so(Vector3(-3.0, 3.3, -326)), _so(Vector3(3.0, 3.3, -326)), 2.2, 16)
	_pipe(bd, "steel_dark", _so(Vector3(0, 3.3, -326)), _so(Vector3(0, top, -326)), 0.4)
	# Strassensperre vor der Station
	_sbox(bd, body, "concrete", _so(Vector3(4.0, y + 0.5, -298.0)), Vector3(3.0, 1.0, 0.8), 15.0)
	_sbox(bd, body, "concrete", _so(Vector3(16.0, y + 0.5, -297.0)), Vector3(3.0, 1.0, 0.8), -10.0)
	bd.box("warn", _so(Vector3(10.0, y + 1.0, -296.5)), Vector3(5.0, 0.15, 0.15))
	var lbl := Label3D.new()
	lbl.text = "BERGSTATION  ·  GRENZE 0,4 km"
	lbl.font_size = 64
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.15, 0.15, 0.15)
	lbl.position = _so(Vector3(-1.0, y + 6.6, -317.35))
	add_child(lbl)

## Eine Aussenwand der Station (nur Optik): c = Mitte unten auf der Aussenflaeche (alte Koordinaten),
## n = Aussennormale, L = Laenge, H = Hoehe. ops: [u (Mitte, entlang t = UP x n), Breite, v0, v1, (true = Tor ohne Fenster)].
## Bruchsteinsockel bis 1,2 m, darueber Putz; Fenster mit Steingewaende, Holzrahmen, Bank und Glas.
func _st_face(bd: BP.Builder, parts, wins, wr: RandomNumberGenerator, c: Vector3, n: Vector3, L: float, H: float, ops: Array) -> void:
	var t := Vector3.UP.cross(n).normalized()
	var R := BP.FK.basis_for(n)
	var th := 0.5
	var mid := c - n * (th * 0.5)
	var sorted := ops.duplicate()
	sorted.sort_custom(func(a, b): return a[0] < b[0])
	var u := -L * 0.5
	var plinth := 1.2
	for o: Array in sorted:
		var u0: float = o[0] - o[1] * 0.5
		var u1: float = o[0] + o[1] * 0.5
		var v0: float = o[2]
		var v1: float = o[3]
		if u0 > u + 0.01:
			_st_piece(bd, mid, t, R, th, u, u0, 0.0, H, plinth)
		if v0 > 0.01:
			_st_piece(bd, mid, t, R, th, u0, u1, 0.0, v0, plinth)
		if v1 < H - 0.01:
			_st_piece(bd, mid, t, R, th, u0, u1, v1, H, plinth)
		if o.size() < 5:
			var oc: Vector3 = c + t * float(o[0]) +Vector3.UP * ((v0 + v1) * 0.5)
			var w: float = o[1]
			var h := v1 - v0
			var wo := _so(oc)
			BP.FK.window(parts, wins, wo, n, w, h, 0.22, "frame", "sill", "cross" if w > 1.9 else "t", 0.0, wr.randf_range(0.5, 1.0), wr.randf(), false, true)
			# Steingewaende (umlaufender Rahmen, steht 6 cm vor)
			var fw := 0.2
			bd.box("st_stone", wo + n * 0.03 + Vector3.UP * (h * 0.5 + fw * 0.5), Vector3(w + fw * 2.0, fw, 0.06) * 1.0, R)
			for s: float in [-1.0, 1.0]:
				bd.box("st_stone", wo + n * 0.03 + t * (s * (w * 0.5 + fw * 0.5)), Vector3(fw, h, 0.06), R)
			bd.box("st_stone", wo + n * 0.06 - Vector3.UP * (h * 0.5 + 0.09), Vector3(w + fw * 2.4, 0.18, 0.12), R)
		u = u1
	if u < L * 0.5 - 0.01:
		_st_piece(bd, mid, t, R, th, u, L * 0.5, 0.0, H, plinth)
	# Sockelabschluss und Traufgesims, an Toren unterbrochen
	for band: Array in [[plinth, 0.16, 0.12], [H - 0.35, 0.3, 0.16]]:
		var bv: float = band[0]
		var cuts: Array = []
		for o: Array in sorted:
			if o.size() >= 5 and bv >= float(o[2]) - 0.2 and bv <= float(o[3]) + 0.2:
				cuts.append([float(o[0]) - float(o[1]) * 0.5, float(o[0]) + float(o[1]) * 0.5])
		var a := -L * 0.5 - 0.12
		cuts.append([L * 0.5 + 0.12, L * 0.5 + 0.12])
		for cu: Array in cuts:
			if cu[0] > a + 0.05:
				var bc := (a + float(cu[0])) * 0.5
				bd.box("st_stone", _so(c + t * bc + n * (float(band[2]) * 0.5) + Vector3.UP * bv), Vector3(float(cu[0]) - a, band[1], band[2]), R)
			a = cu[1]

## Wandstueck (u0..u1, v0..v1) der Station: unterhalb von plinth Bruchstein (6 cm vorstehend), darueber Putz.
func _st_piece(bd: BP.Builder, mid: Vector3, t: Vector3, R: Basis, th: float, u0: float, u1: float, v0: float, v1: float, plinth: float) -> void:
	var w := u1 - u0
	var cu := (u0 + u1) * 0.5
	var n := R.z
	# Innenseite: duenne Putzschale (nur Optik) vor der Wand, damit innen nicht der grobe Aussenputz erscheint
	if v1 > v0 + 0.01:
		bd.box("st_inner", _so(mid + t * cu - n * (th * 0.5 + 0.012) + Vector3.UP * ((v0 + v1) * 0.5)), Vector3(w, v1 - v0, 0.02), R)
	if v0 < plinth:
		var pv1 := minf(v1, plinth)
		bd.box("st_stone", _so(mid + t * cu + n * 0.03 + Vector3.UP * ((v0 + pv1) * 0.5)), Vector3(w, pv1 - v0, th + 0.06), R)
		v0 = pv1
	if v1 > v0 + 0.01:
		bd.box("st_wall", _so(mid + t * cu + Vector3.UP * ((v0 + v1) * 0.5)), Vector3(w, v1 - v0, th), R)

## Seilbahn: Trag- und Zugseil ins Tal, Gitterstuetze.
func _build_cableway(bd: BP.Builder) -> void:
	_pipe(bd, "steel_dark", CABLE_A + Vector3(0, 0.4, 0), CABLE_B, 0.06, 6)
	_pipe(bd, "steel_dark", CABLE_A + Vector3(0.7, 0.1, 0), CABLE_B + Vector3(0.7, -0.3, 0), 0.04, 5)
	_pipe(bd, "steel_dark", CABLE_A + Vector3(0, 0.4, 10), CABLE_A + Vector3(0, 0.4, 0), 0.06, 6)
	var top := CABLE_A.lerp(CABLE_B, 0.46)
	var gy := ter.height(top.x, top.z) - 1.0
	var legs_b: Array[Vector3] = []
	var legs_t: Array[Vector3] = []
	for c: Vector2 in [Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)]:
		legs_b.append(Vector3(top.x + c.x, gy, top.z + c.y))
		legs_t.append(Vector3(top.x + c.x * 0.3, top.y - 0.8, top.z + c.y * 0.3))
	for i in 4:
		_pipe(bd, "steel_grey", legs_b[i], legs_t[i], 0.14, 6)
		var j := (i + 1) % 4
		var hgt := top.y - 0.8 - gy
		var k := 0.0
		while k < 1.0:
			var a := legs_b[i].lerp(legs_t[i], k)
			var b := legs_b[j].lerp(legs_t[j], k + 0.12)
			_pipe(bd, "steel_grey", a, b, 0.06, 4)
			_pipe(bd, "steel_grey", legs_b[j].lerp(legs_t[j], k), legs_b[i].lerp(legs_t[i], k + 0.12), 0.06, 4)
			k += 0.12 if hgt > 20.0 else 0.2
	bd.box("steel_grey", top + Vector3(0, -0.5, 0), Vector3(6.0, 0.5, 1.2))

## Staatsgrenze hinter der Station: Grenzsteine, Zaun, Schranke, Schild.
func _build_border(bd: BP.Builder, body: StaticBody3D) -> void:
	var z := -676.0
	NP.fence(self, _gp(-60, z), _gp(-8, z), rng, false, 0.2)
	NP.fence(self, _gp(14, z), _gp(60, z), rng, false, 0.2)
	for x: float in [-8.0, 14.0]:
		_sbox(bd, body, "white", _gp(x, z, 0.6), Vector3(0.5, 1.2, 0.3))
	var bar := _gp(3, z, 1.0)
	for i in 8:
		bd.box("red_white" if i % 2 == 0 else "white", bar + Vector3(-9.0 + 2.25 * float(i) * 1.0 + 1.1, 0, 0), Vector3(2.25, 0.18, 0.18))
	var lbl := Label3D.new()
	lbl.text = "STAATSGRENZE\nREPUBLIK ÖSTERREICH"
	lbl.font_size = 72
	lbl.pixel_size = 0.012
	lbl.modulate = Color(0.12, 0.12, 0.12)
	lbl.outline_size = 0
	lbl.position = _gp(-12, z, 3.2)
	lbl.rotation_degrees.y = 180.0
	add_child(lbl)

func _build_props() -> void:
	# Beobachtungsposten 1 an der Kante
	Props.sandbags(world, _gp(-3.5, -61.0), 0.0, 3.0, rng, covers)
	Props.sandbags(world, _gp(3.5, -61.0), 0.0, 3.0, rng, covers)
	# Posten 2 am Sattel (Blick Richtung Station/Rinne)
	Props.sandbags(world, _gp(-4.0, -408.0), 0.0, 3.0, rng, covers)
	Props.sandbags(world, _gp(5.0, -408.0), 0.0, 3.0, rng, covers)
	Props.sandbags(world, _gp(-11.0, -403.0), 60.0, 3.0, rng, covers)
	# Kessel-Deckung
	for c: Vector3 in [Vector3(-8, 0, -205), Vector3(10, 30, -222), Vector3(-2, 0, -248), Vector3(14, 90, -286), Vector3(-16, 20, -300)]:
		Props.sandbags(world, _gp(c.x, c.z), c.y, 3.0, rng, covers)
	# Grat-Steig
	Props.sandbags(world, _gp(46.0, -472.0), 90.0, 3.0, rng, covers)
	Props.sandbags(world, _gp(50.0, -528.0), 90.0, 2.5, rng, covers)
	Props.sandbags(world, _gp(40.0, -566.0), 50.0, 3.0, rng, covers)
	# Station
	Props.sandbags(world, _so(Vector3(-6.0, -4.0, -308.0)), 0.0, 3.0, rng, covers)
	Props.sandbags(world, _so(Vector3(-14.0, -4.0, -312.0)), 30.0, 3.0, rng, covers)
	Props.vehicle(world, _so(Vector3(-16.0, -4.0, -326.0)), 80.0, "van", Color(0.55, 0.56, 0.58), false, false, covers)
	# MG-Nester (Sandsack-Ringe)
	for d: Array in NESTS_P1 + NESTS_P3:
		var c2: Vector2 = d[1]
		var c := _gp(c2.x, c2.y)
		Props.sandbags(world, c + Vector3(0, 0, 1.8), 0.0, 3.0, rng, covers)
		Props.sandbags(world, c + Vector3(-1.9, 0, 0), 90.0, 2.4, rng, covers)
		Props.sandbags(world, c + Vector3(1.9, 0, 0), 90.0, 2.4, rng, covers)
	# Schuetzengruppen: lange Sandsackmauer nach vorn, kurze Flanken
	for d: Array in SQUADS_P1 + SQUADS_P3:
		var c2: Vector2 = d[1]
		var c := _gp(c2.x, c2.y)
		Props.sandbags(world, c + Vector3(0, 0, 1.6), 0.0, 5.0, rng, covers)
		Props.sandbags(world, c + Vector3(-2.9, 0, 0.3), 70.0, 2.0, rng, covers)
		Props.sandbags(world, c + Vector3(2.9, 0, 0.3), -70.0, 2.0, rng, covers)

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, _gp(0, 2, 0.1), "player_spawn")
	ps.name = "PlayerSpawn"
	ps.rotation_degrees.y = 0.0
	var route: Array[Vector2] = [Vector2(0, -5), Vector2(0, -30), Vector2(0, -55)]
	_wp_idx["start"] = 2
	for p: Vector3 in SERP:
		route.append(Vector2(p.x, p.z))
	_wp_idx["kessel"] = route.size() - 1
	route.append_array([Vector2(0, -200), Vector2(10, -250)])
	for p: Vector3 in KESSEL_UP:
		route.append(Vector2(p.x, p.z))
	_wp_idx["sattel"] = route.size() - 2
	_wp_idx["steig"] = route.size()
	for p: Vector3 in STEIG:
		route.append(Vector2(p.x, p.z))
	_wp_idx["station"] = route.size() - 1
	route.append_array([Vector2(4, -622), Vector2(0, -634), Vector2(0.5, -647), Vector2(5, -648)])
	for i in route.size():
		var w := Geo.marker(m, _gp(route[i].x, route[i].y, 0.05), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	_trigger("Posten1", _gp(0, -45, 2.0), Vector3(60, 10, 3), _start_phase1)
	_trigger("Gate1Hint", Vector3(0, 1.0, GATE1_Z + 1.5), Vector3(80, 12, 1.5), func() -> void:
		if _phase == 1:
			_say_cd_opt("gate1", 25.0, SD.LENA, "Noch nicht! Erst die Stellungen ausschalten – sonst laufen wir ins MG-Feuer.", {"max_age": 2.0, "valid": func() -> bool: return _phase == 1}), false)
	_trigger("Kessel", Vector3(0, -40.0, -160.0), Vector3(300, 26, 3), _on_basin)
	_trigger("Posten2", Vector3(0, -22.0, -390.0), Vector3(60, 12, 3), _start_phase3)
	_trigger("Gate2Hint", Vector3(0, -20.0, GATE2_Z + 2.0), Vector3(120, 24, 1.5), func() -> void:
		if _phase == 3 or _phase == 4:
			_say_cd("gate2", 25.0, SD.LENA, "Wir bleiben hier, bis der Weg frei ist. Erst der Mörser."), false)
	_trigger("Grat", Vector3(46, -8.0, -455.0), Vector3(16, 10, 3), _on_ridge)
	_trigger("Station", Vector3(4, -28.0, -606.0), Vector3(70, 12, 2), _start_phase6)
	var area := _trigger("LevelEnd", Vector3(5.5, -28.5, -648.0), Vector3(5.0, 3.0, 11.0), _try_finish, false)
	area.add_to_group("level_end")

func _build_set_piece_geometry() -> void:
	pass

func _build_skyline() -> void:
	pass

func _build_atmosphere() -> void:
	_omni(_so(Vector3(6.0, -1.0, -336.0)), Color(1.0, 0.85, 0.6), 1.0, 9.0)
	_omni(_so(Vector3(-2.0, 2.5, -330.0)), Color(1.0, 0.9, 0.7), 1.2, 16.0)
	_omni(_gp(-20, 22, 2.0) + Vector3(0, 0, 3.5), Color(1.0, 0.8, 0.55), 1.0, 8.0)

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.7
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 42.0
	nm.cell_size = 0.35
	nm.cell_height = 0.2
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1 | 16
	nm.filter_baking_aabb = AABB(Vector3(-95.0, -60.0, -680.0), Vector3(155.0, 100.0, 712.0))
	var map := world.get_navigation_map()
	NavigationServer3D.map_set_cell_size(map, 0.35)
	NavigationServer3D.map_set_cell_height(map, 0.2)
	world.navigation_mesh = nm
	var t0 := Time.get_ticks_msec()
	world.bake_navigation_mesh(false)
	print("[alpenpass] Navmesh %d ms: vertices=%d polygons=%d" % [Time.get_ticks_msec() - t0, nm.get_vertices().size(), nm.get_polygon_count()])

func _spawn_wave(index: int) -> void:
	# Wellen kommen aus den Phasen-Ausloesern (_spawn_wave_alp).
	if _waves_spawned.has(index):
		return
	_waves_spawned[index] = true
	wave_started.emit(index)

# ------------------------------------------------------------------ Laufzeit-Aufbau (nach dem Navmesh)

func _build_runtime() -> void:
	# Wetter: Sturm in Wellen mit Aufrissen (nur Atmosphaere – der Moerser haengt nicht mehr daran)
	wx = WeatherSystem.new()
	wx.name = "Weather"
	wx.set("mode", "blizzard")
	wx.set("base_intensity", 0.75)
	wx.set("window_intensity", 0.1)
	wx.set("fog_color", Color(0.85, 0.89, 0.95))
	wx.set("clear_fog_density", 0.0013)
	wx.set("storm_duration", Vector2(20.0, 28.0))
	wx.set("window_duration", Vector2(22.0, 28.0))
	add_child(wx)
	# Lena
	lena = _make_actor("friendly", "rifleman", _gp(1.6, 3.0), FR_PRIMARY, FR_SECONDARY, FR_ARMBAND, 0.0)
	lena.set("invulnerable", true)
	lena.name = "Lena"
	_build_targets()
	_build_vehicle()
	_build_wechte()
	_build_cabin()
	# Sperren (nach dem Bake: nicht im Navmesh). Gegner bekommen Ausnahmen.
	_gates["g1"] = _gate(Vector3(0, -10, GATE1_Z), Vector3(300, 140, 1.0))
	_gates["g2"] = _gate(Vector3(0, -30, GATE2_Z), Vector3(300, 140, 1.0))
	# Moerser / Beobachter
	spot = Spotter.new()
	spot.name = "ArtillerySpotter"
	# Markieren = sofort eine Salve mit 4-5 Granaten auf den Punkt (keine Ablage, kein Einschiessen)
	spot.set("salvos_left", 40)
	spot.set("rounds_per_salvo", 4)
	spot.set("rounds_extra", 1)
	spot.set("reload_time", 8.0)
	spot.set("prep_time", 0.8)
	spot.set("flight_base", 2.5)
	spot.set("round_interval", 0.45)
	spot.set("dispersion", 2.2)
	spot.set("range_spread", 1.4)
	spot.set("deflection_spread", 0.9)
	spot.set("bias_initial", 0.0)
	spot.set("adjust_mode", false)
	spot.set("corrections_enabled", false)
	spot.set("look_mask", 1 | LASE_LAYER)   # Entfernungsmesser trifft auch die Ziel-Kollider (flache Blickwinkel am Sattel)
	spot.set("min_range", 35.0)
	spot.set("danger_radius", 30.0)
	spot.set("blast_radius", 9.0)
	spot.set("north", Vector3(0, 0, 1))
	spot.set("battery_dir", Vector3(0.3, 0, 1))
	add_child(spot)
	spot.set("protected", [{"node": lena, "radius": 12.0, "name": "Lena"}])
	spot.set("no_fire", [{"node": _cabin, "radius": 14.0, "name": "Seilbahn"}])
	spot.connect("mission_requested", _on_mission_requested)
	spot.connect("mission_refused", _on_mission_refused)
	spot.connect("danger_close", _on_danger_close)
	spot.connect("salvo_fired", _on_salvo_fired)
	spot.connect("shell_impact", _on_shell_impact)
	spot.connect("salvo_complete", _on_salvo_complete)
	spot.connect("binoculars_changed", func(up: bool) -> void:
		if up:
			_tut["raise"] = true)
	_build_heli()
	_build_hud()

func _gate(center: Vector3, size: Vector3) -> StaticBody3D:
	var b := Geo.static_body(center)
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

## Gegner duerfen durch die Spieler-Sperren (sonst bleiben Gegenstoesse haengen).
func _pass_gates(e: Node) -> void:
	if not (e is PhysicsBody3D):
		return
	for g: Variant in _gates.values():
		if g is PhysicsBody3D and is_instance_valid(g):
			(e as PhysicsBody3D).add_collision_exception_with(g as PhysicsBody3D)

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
	e.global_position = pos + Vector3(0, 0.1, 0)
	e.rotation.y = 0.0
	e.set("accuracy_scale", acc)
	e.set("sight_range", ENEMY_SIGHT * _sight())
	_pass_gates(e)
	return e

func _acc() -> float:
	return 0.5 if _skill == "novice" else 0.58

func _sight() -> float:
	return float(wx.call("sight_factor")) if wx != null else 1.0

## Moerser-Ziele: MG-Nester und Schuetzengruppen (Besatzung = Puppen mit Leuchtspur), Unterstand,
## Schuetzenpanzer, Wechte. hp = Trefferpunkte: Granate im Kern (0.4 r) 2, im Radius 1 (eine gut
## markierte Salve reicht fuer jedes Ziel).
func _build_targets() -> void:
	for d: Array in NESTS_P1:
		_build_nest(str(d[0]), d[1] as Vector2, 1)
	for d: Array in SQUADS_P1:
		_build_squad(str(d[0]), d[1] as Vector2, 1)
	var dp := _gp(6, -305)
	var dug := Node3D.new()
	dug.name = "Unterstand"
	add_child(dug)
	dug.global_position = dp
	_lase_box(dug, Vector3(7.0, 2.6, 7.0), Vector3(0, 1.0, 0))
	_targets.append({"id": "dugout", "kind": "dugout", "name": "Unterstand", "pos": dp, "radius": 8.0, "hp": 3, "alive": true, "phase": 1,
		"crew": [], "node": dug, "fire_t": 99.0, "seen": false})
	var vp: Vector2 = VEH_PATH[VEH_PATH.size() - 1]
	_targets.append({"id": "vehicle", "kind": "vehicle", "name": "Schützenpanzer", "pos": _gp(vp.x, vp.y), "radius": 7.0, "hp": 2, "alive": true,
		"phase": 3, "crew": [], "node": null, "fire_t": 99.0, "seen": false})
	for d: Array in NESTS_P3:
		_build_nest(str(d[0]), d[1] as Vector2, 3)
	for d: Array in SQUADS_P3:
		_build_squad(str(d[0]), d[1] as Vector2, 3)
	var r0: Vector3 = RINNE[0]
	_targets.append({"id": "cornice", "kind": "cornice", "name": "Wechte", "pos": Vector3(r0.x - 2.0, r0.y + 3.0, r0.z - 2.0), "radius": 14.0, "hp": 1,
		"alive": true, "phase": 4, "crew": [], "node": null, "fire_t": 99.0, "seen": false})

## MG-Nest: M2 auf Dreibein, MG-Schuetze + Gewehrschuetze (Puppen), Lauf Richtung Posten (+z).
func _build_nest(id: String, c2: Vector2, phase: int) -> void:
	var c := _gp(c2.x, c2.y)
	var node := Node3D.new()
	node.name = id
	add_child(node)
	node.global_position = c
	var m2 := GunModels.build_m2()   # M2 auf Dreibein oben auf der vorderen Sandsackmauer, Lauf Richtung Posten
	m2.position = Vector3(0, 0.9, 2.0)
	m2.rotation_degrees.y = 180.0
	node.add_child(m2)
	node.add_child(Geo.box_mesh_node(Vector3(0.6, 0.9, 0.1), mats["steel_dark"], Vector3(0, 0.5, -0.2), Vector3(20, 0, 0)))
	node.add_child(Geo.box_mesh_node(Vector3(3.2, 0.12, 2.6), mats["white"], Vector3(0, 1.45, -0.3), Vector3(4, 0, 0)))
	_lase_box(node, Vector3(5.0, 2.2, 5.0), Vector3(0, 1.0, 0))
	var crew: Array = []
	var g := _make_actor("enemy", "heavy", c + Vector3(0.3, 0, -0.4), Color.BLACK, Color.BLACK, Color.BLACK, 180.0)
	g.set("sfx_shot", "enemy_mg")
	g.set("crouch", true)
	g.set("invulnerable", true)
	crew.append(g)
	var r := _make_actor("enemy", "rifleman", c + Vector3(-1.0, 0, -0.9), Color.BLACK, Color.BLACK, Color.BLACK, 180.0)
	r.set("crouch", true)
	r.set("invulnerable", true)
	crew.append(r)
	_targets.append({"id": id, "kind": "nest", "name": "MG-Nest", "pos": c, "radius": 8.0, "hp": 2, "alive": true, "phase": phase,
		"crew": crew, "node": node, "fire_t": 2.0 + randf() * 3.0, "seen": false})

## Unsichtbarer Kollider (nur LASE_LAYER) fuer den Entfernungsmesser: Markieren auf das Ziel trifft das Ziel,
## auch bei flachem Blickwinkel (sonst rutscht der Strahl am Ziel vorbei auf den Hang dahinter).
func _lase_box(parent: Node3D, size: Vector3, off: Vector3) -> void:
	var b := StaticBody3D.new()
	b.name = "Lase"
	b.collision_layer = LASE_LAYER
	b.collision_mask = 0
	b.set_meta("no_fit", true)
	Geo.add_box_shape(b, off, size)
	parent.add_child(b)

## Schuetzengruppe: drei Gewehrschuetzen (Puppen) hinter einer Sandsackmauer, Einzelfeuer Richtung Posten.
func _build_squad(id: String, c2: Vector2, phase: int) -> void:
	var c := _gp(c2.x, c2.y)
	var node := Node3D.new()
	node.name = id
	add_child(node)
	node.global_position = c
	_lase_box(node, Vector3(7.0, 2.0, 4.0), Vector3(0, 0.9, 0))
	var crew: Array = []
	for k in 3:
		var p := c + Vector3(-1.8 + 1.8 * float(k), 0, -0.2 - 0.4 * float(k % 2))
		var a := _make_actor("enemy", "marksman" if k == 1 else "rifleman", Vector3(p.x, ter.height(p.x, p.z), p.z), Color.BLACK, Color.BLACK, Color.BLACK, 180.0)
		a.set("crouch", true)
		a.set("invulnerable", true)
		crew.append(a)
	_targets.append({"id": id, "kind": "squad", "name": "Schützengruppe", "pos": c, "radius": 8.0, "hp": 2, "alive": true, "phase": phase,
		"crew": crew, "node": node, "fire_t": 1.0 + randf() * 3.0, "seen": false})

func _target(id: String) -> Dictionary:
	for t in _targets:
		if str(t["id"]) == id:
			return t
	return {}

func _target_pos(t: Dictionary) -> Vector3:
	if str(t["kind"]) == "vehicle" and _veh != null and is_instance_valid(_veh):
		return _veh.global_position
	return t["pos"]

## Schuetzenpanzer (Modell "Rabe", ifv_model) mit beweglichem Turm; AnimatableBody als Deckung.
func _build_vehicle() -> void:
	_veh = Node3D.new()
	_veh.name = "Schuetzenpanzer"
	add_child(_veh)
	var p0: Vector2 = VEH_PATH[0]
	_veh.global_position = _gp(p0.x, p0.y)
	var model := Node3D.new()
	model.name = "Model"
	_veh.add_child(model)
	_veh_parts = IfvModel.build(model)
	var ab := AnimatableBody3D.new()
	ab.name = "Body"
	ab.collision_layer = 1
	ab.collision_mask = 0
	for s: Array in IfvModel.shapes():
		Geo.add_box_shape(ab, s[0] as Vector3, s[1] as Vector3)
	_veh.add_child(ab)
	_lase_box(_veh, Vector3(4.0, 3.2, 7.5), Vector3(0, 1.4, 0))
	_veh.visible = false

## Wechte: ueberhaengende Schneekante oben an der Rinne (Moerserziel, Kollision fuer den Entfernungsmesser).
func _build_wechte() -> void:
	var t := _target("cornice")
	var c: Vector3 = t["pos"]
	_wechte = Node3D.new()
	_wechte.name = "Wechte"
	add_child(_wechte)
	_wechte.global_position = c
	var r0: Vector3 = RINNE[0]
	var r1: Vector3 = RINNE[1]
	var dir := Vector2(r1.x - r0.x, r1.z - r0.z).normalized()
	_wechte.rotation.y = atan2(dir.x, dir.y)
	for i in 6:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 20
		sm.rings = 10
		mi.mesh = sm
		mi.material_override = mats["snow"]
		mi.position = Vector3(-12.0 + float(i) * 4.8, randf_range(-0.4, 0.6), 1.5 + randf_range(-0.5, 0.5))
		mi.scale = Vector3(randf_range(3.4, 4.6), randf_range(1.6, 2.3), randf_range(4.0, 5.5))
		_wechte.add_child(mi)
	_wechte_body = Geo.static_body(c)
	_wechte_body.set_meta("no_fit", true)
	Geo.add_box_shape(_wechte_body, Vector3.ZERO, Vector3(26, 4, 26))
	add_child(_wechte_body)

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

## Hubschrauber: glTF-Slot (HELI_MODEL_PATH / --heli_model) mit Fallback auf das prozedurale heli_model.
func _build_heli() -> void:
	_heli = Node3D.new()
	_heli.name = "Hubschrauber"
	add_child(_heli)
	_heli.global_position = _gp(-8.0, -3.0, 1.6)
	_heli.rotation.y = deg_to_rad(-25.0)
	var path := str(Game.arg("heli_model", HELI_MODEL_PATH))
	if path == "true" or path == "false":
		path = HELI_MODEL_PATH
	_heli_parts = HeliGltf.build(_heli, path, {"faction": "eu"})
	print("[alpenpass] Hubschrauber-Modell: %s" % str(_heli_parts.get("source", "?")))
	_loop_3d("veh_heli_rotor", _heli, Vector3(0, 2.0, 0), 2.0, 14.0, 160.0)

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
	tw.tween_property(_heli, "global_position", _heli.global_position + Vector3(0, 16, 8), 4.0).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_heli, "rotation:x", deg_to_rad(8.0), 4.0)
	tw.tween_property(_heli, "global_position", Vector3(-60, 70, 260), 12.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_heli, "rotation:y", deg_to_rad(160.0), 5.0)
	tw.tween_callback(func() -> void:
		_heli.queue_free()
		_heli = null)

func _start_phase1() -> void:
	if _phase >= 1:
		return
	_phase = 1
	_spot_active = true
	_tut_on = true
	spot.set("enabled", true)
	_update_phase1_obj()
	# Einweisung schliesst an das Absetz-Briefing an (sobald der Funk frei ist), nicht hinten in der Schlange
	_when_radio_free(func() -> void:
		if _phase == 1:
			_say_opt(SD.LENA, "Unten im Kessel: MG-Nester, Schützengruppen und ein Unterstand. Fernglas, Ziel markieren – der Mörserzug schießt sofort, eine volle Salve.", 0.0,
				{"priority": 1}), 20.0)
	_later(6.0, func() -> void:
		if _phase == 1:
			wx.call("open_window", 26.0))   # Sturm reisst kurz auf (nur Optik)
	_counter_t = 90.0
	_report_t = 8.0

func _update_phase1_obj() -> void:
	_obj("Stellungen im Kessel mit dem Mörser ausschalten (%s)" % _phase_count(1))

## "erledigt/gesamt" der Moerserziele einer Phase.
func _phase_count(phase: int) -> String:
	var n := 0
	var all := 0
	for t in _targets:
		if int(t["phase"]) == phase:
			all += 1
			if not bool(t["alive"]):
				n += 1
	return "%d/%d" % [n, all]

## Lage der Moerserziele (MG-Nester + Schuetzengruppen) einer Phase.
static func _target_spots(phase: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for d: Array in (NESTS_P1 + SQUADS_P1 if phase == 1 else NESTS_P3 + SQUADS_P3):
		out.append(d[1] as Vector2)
	return out

func _end_phase1(quiet: bool = false) -> void:
	if _phase != 1:
		return
	_phase = 2
	_spot_active = false
	_tut_on = false
	spot.set("enabled", false)
	_open_gate("g1")
	_obj("Durch den Kessel – Webers Nachhut bei der Zollhütte")
	if not quiet:
		_say_opt(SD.BRANDT, "Alle Stellungen im Kessel sind still. Webers Nachhut zieht sich zur Zollhütte zurück – geht runter und räumt auf.", 0.0, {"priority": 1, "cut": true})

## Gegenstoss: echte Gegner steigen die Serpentine zum Posten hoch.
func _spawn_counter() -> void:
	if not _counter.is_empty() or _phase != 1:
		return
	var pl := _player()
	var to: Vector3 = pl.global_position if pl != null else _gp(OP1.x, OP1.y)
	for d: Array in [["assault", Vector2(-4, -150)], ["rifleman", Vector2(6, -143)], ["rifleman", Vector2(14, -137)], ["assault", Vector2(0, -154)],
			["rifleman", Vector2(20, -128)], ["assault", Vector2(-8, -155)]]:
		var c: Vector2 = d[1]
		var e := _enemy(str(d[0]), _gp(c.x, c.y), "reich", _acc())
		if e == null:
			continue
		_counter.append(e)
		if e.has_method("alert"):
			e.call("alert", to, false)
		_reveal[e.get_instance_id()] = {"n": e, "until": _t + 10.0}
	_say_opt(SD.LENA, "Bewegung an der Serpentine – die kommen zu uns hoch! Erst die, dann weiter mit dem Mörser.", 0.0, {"priority": 1, "cut": true})

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
			list = [["rifleman", Vector2(10, -245)], ["assault", Vector2(-8, -255)], ["rifleman", Vector2(20, -275)], ["heavy", Vector2(-14, -280)],
				["marksman", Vector2(4, -300)], ["rifleman", Vector2(24, -292)], ["assault", Vector2(-4, -270)],
				["rifleman", Vector2(-20, -230)], ["assault", Vector2(30, -240)], ["rifleman", Vector2(-24, -300)], ["heavy", Vector2(12, -312)]]
		2:
			list = [["rifleman", Vector2(48, -490)], ["assault", Vector2(50, -505)], ["marksman", Vector2(49, -520)],
				["rifleman", Vector2(40, -570)], ["assault", Vector2(30, -590)],
				["assault", Vector2(49, -540)], ["rifleman", Vector2(46, -555)], ["marksman", Vector2(36, -582)]]
		3:
			list = [["rifleman", Vector2(-7, -634)], ["officer", Vector2(-2, -644)], ["rifleman", Vector2(-9, -622)],
				["assault", Vector2(6, -626)], ["heavy", Vector2(-4, -652)],
				["rifleman", Vector2(10, -640)], ["assault", Vector2(-15, -624)], ["marksman", Vector2(2, -664)]]
		9:
			list = [["assault", Vector2(-14, -615)], ["rifleman", Vector2(12, -618)], ["marksman", Vector2(-18, -640)],
				["rifleman", Vector2(16, -630)], ["assault", Vector2(-20, -630)]]
	var faction := "garde_winter" if index == 2 or index == 9 else "reich"
	for d: Array in list:
		var c: Vector2 = d[1]
		var pos := Vector3(c.x, -30.0, c.y) if index == 3 or index == 9 else _gp(c.x, c.y)
		var e := _enemy(str(d[0]), pos, faction, _acc())
		if e == null:
			continue
		(_waves[index] as Array).append(e)
		if e.has_method("alert") and index != 9:
			e.call("alert", alert_to, false)
	if index == 1:
		_later(2.5, func() -> void:
			if not _said.has("contact1"):
				_said["contact1"] = true
				_say_opt(SD.LENA, "Kontakt! Sie sind noch nicht alle tot.", 0.0, {"priority": 1, "max_age": 2.0}))

func _start_phase3() -> void:
	if _phase != 2:
		return
	_phase = 3
	_checkpoint("cp_sattel")
	_spot_active = true
	spot.set("salvos_left", maxi(int(spot.get("salvos_left")), 6))
	spot.set("enabled", true)
	_update_phase3_obj()
	_say(SD.BRANDT, "Ein Schützenpanzer rollt von der Bergstation hoch zur Brücke. Wenn der sich dort eingräbt, kommt keiner durch.")
	_veh_drive()
	var pl := _player()
	for d: Array in [["rifleman", Vector2(-4, -520)], ["assault", Vector2(10, -528)], ["rifleman", Vector2(3, -540)],
			["assault", Vector2(-6, -548)], ["rifleman", Vector2(12, -552)]]:
		var c: Vector2 = d[1]
		var e := _enemy(str(d[0]), _gp(c.x, c.y), "reich", _acc())
		if e == null:
			continue
		_escort.append(e)
		if e.has_method("alert") and pl != null:
			e.call("alert", pl.global_position, false)
	_later(8.0, func() -> void:
		if _phase == 3:
			_say_opt(SD.LENA, "Infanterie vor dem Panzer, auf der Straße! Die halten wir mit dem Gewehr – den Panzer nimmt der Mörser.", 0.0,
				{"priority": 1, "max_age": 2.0, "valid": func() -> bool: return _phase == 3}))
	_later(16.0, func() -> void:
		if _phase == 3:
			_say_idle("p3_nests", 60.0, SD.LENA, "Dazu MG-Nester und eine Schützengruppe an der Straße. Alles Ziele für den Mörser."))

func _update_phase3_obj() -> void:
	_obj("Schützenpanzer und Stellungen an der Passstraße mit dem Mörser zerstören (%s)" % _phase_count(3))

func _veh_drive() -> void:
	if _veh_state != "idle":
		return
	_veh_state = "driving"
	_veh_i = 1
	_veh.visible = true
	_loop_3d("veh_tank_engine" if ResourceLoader.exists("res://assets/sfx/veh_tank_engine.ogg") else "rail_metal_creak", _veh, Vector3(0, 1, 0), -2.0, 10.0, 160.0)

func _veh_stopped() -> void:
	if _veh_state != "driving":
		return
	_veh_state = "stopped"
	var t := _target("vehicle")
	t["seen"] = true
	_say_opt(SD.LENA, "Er steht. Jetzt oder nie – markier ihn.", 0.0,
		{"priority": 2, "cut": true, "drop_live": true, "valid": func() -> bool: return _veh_state == "stopped"})
	wx.call("open_window", 24.0)

func _tick_vehicle(delta: float) -> void:
	if _veh == null or _veh_state == "idle" or _veh_state == "dead":
		return
	if _veh_state == "driving":
		var tgt: Vector2 = VEH_PATH[_veh_i]
		var p := _veh.global_position
		var d := Vector2(tgt.x - p.x, tgt.y - p.z)
		if d.length() < 0.5:
			_veh_i += 1
			if _veh_i >= VEH_PATH.size():
				_veh_stopped()
			return
		var dn := d.normalized()
		var step := minf(4.0 * delta, d.length())
		var nx := p.x + dn.x * step
		var nz := p.z + dn.y * step
		_veh.global_position = Vector3(nx, ter.height(nx, nz), nz)
		_veh.rotation.y = lerp_angle(_veh.rotation.y, atan2(-dn.x, -dn.y), clampf(delta * 2.0, 0.0, 1.0))
		return
	# steht: Turm folgt dem Spieler, Koax-MG schiesst Leuchtspur-Feuerstoesse
	var pl := _player()
	if pl == null:
		return
	var tur: Node3D = _veh_parts.get("turret")
	if tur != null:
		var l := _veh.global_transform.basis.inverse() * (pl.global_position - tur.global_position)
		tur.rotation.y = lerp_angle(tur.rotation.y, atan2(-l.x, -l.z), clampf(delta * 1.2, 0.0, 1.0))
	_veh_fire_t -= delta
	if _veh_fire_t > 0.0:
		return
	_veh_fire_t = randf_range(2.6, 4.4)
	var mz: Node3D = _veh_parts.get("coax_muzzle")
	if mz == null:
		return
	_sfx_at("enemy_mg", _veh.global_position + Vector3(0, 2.2, 0), 3.0, 260.0)
	for k in 6:
		_later(0.09 * float(k), func() -> void:
			if _veh_state != "stopped" or not is_instance_valid(mz):
				return
			var p2 := _player()
			if p2 == null:
				return
			var aim := p2.global_position + Vector3(randf_range(-4, 4), randf_range(0.0, 3.0), randf_range(-4, 4))
			VF.tracer(self, mz.global_position, aim, 300.0)
			var fl: Variant = _veh_parts.get("coax_flash")
			if fl is Node3D:
				VF.show_flash(fl as Node3D, 0.05))
	if pl.global_position.distance_to(_veh.global_position) < 240.0:
		pl.add_trauma(0.08)

func _destroy_vehicle(quiet: bool) -> void:
	var t := _target("vehicle")
	if t.is_empty() or not bool(t["alive"]):
		return
	t["alive"] = false
	if _veh_state == "idle" or _veh_state == "driving":
		var vp: Vector2 = VEH_PATH[VEH_PATH.size() - 1]
		_veh.global_position = _gp(vp.x, vp.y)
		_veh.visible = true
	_veh_state = "dead"
	for c in _veh.find_children("*", "", true, false):
		if c is AudioStreamPlayer3D:
			(c as Node).queue_free()
		elif c is GeometryInstance3D:
			(c as GeometryInstance3D).material_override = mats["wreck"]
		elif c is Light3D:
			(c as Light3D).visible = false
	var tur: Node3D = _veh_parts.get("turret")
	if tur != null:
		tur.rotation_degrees += Vector3(6, 25, -4)
	Props.fire(_veh, Vector3(0, 2.0, 0.6), 1.6, true, 3.0, 5.0)
	if not quiet:
		Combat.explode(_veh.global_position + Vector3(0, 1.5, 0), 6.0, 60.0, _player(), 1.5)
		_say_opt(SD.LENA, "Panzer brennt! Treffer!", 0.0, {"priority": 2, "cut": true})

func _start_phase4() -> void:
	if _phase != 3:
		return
	_phase = 4
	_obj("Wechte über der Rinne beschießen – Lawine auslösen, bevor Falk sprengt")
	_say(SD.BRANDT, "Bewegung in der Rinne westlich von euch. Graue Mäntel – Falks Garde-Jäger. Die wollen zur Bergstation, vor euch.")
	_say_opt(SD.FALK, "Weber gehört mir. Wer sich mir in den Weg stellt, bleibt im Schnee.", 0.0,
		{"drop_live": true, "valid": func() -> bool: return not _avalanche})
	_say_opt(SD.LENA, "Über der Rinne hängt eine Wechte. Ein Treffer, und der ganze Hang kommt runter.", 0.0,
		{"drop_live": true, "valid": func() -> bool: return not _avalanche})
	_target("cornice")["seen"] = true
	spot.set("salvos_left", maxi(int(spot.get("salvos_left")), 4))
	for d: Array in [["assault", Vector2(-74, -470)], ["rifleman", Vector2(-70, -466)], ["marksman", Vector2(-77, -462)], ["assault", Vector2(-66, -474)], ["rifleman", Vector2(-72, -480)]]:
		var c: Vector2 = d[1]
		var e := _enemy(str(d[0]), _gp(c.x, c.y), "garde_winter", _acc())
		if e != null:
			_garde.append(e)
	_garde_alert_t = GARDE_ALERT
	_falk_t = FALK_TIME
	_later(5.0, func() -> void:
		if _phase == 4:
			wx.call("open_window", 24.0))

func _tick_garde(delta: float) -> void:
	if _phase != 4 or _avalanche:
		return
	if _garde_alert_t > 0.0:
		_garde_alert_t -= delta
		if _garde_alert_t <= 0.0:
			var pl := _player()
			for e in _garde:
				if _alive(e) and e.has_method("alert") and pl != null:
					e.call("alert", pl.global_position, false)
				if _alive(e):
					_reveal[e.get_instance_id()] = {"n": e, "until": _t + 8.0}
			_say_opt(SD.LENA, "Die Grauen kommen die Rinne runter – linke Flanke, %d Uhr!" % _clock(Vector3(-55, 0, -450)), 0.0,
				{"priority": 1, "max_age": 3.0, "valid": func() -> bool: return not _avalanche})
	if _falk_t > 0.0:
		_falk_t -= delta
		if _falk_t <= 20.0 and not _falk_warned:
			_falk_warned = true
			_say_opt(SD.BRANDT, "Die Garde schleppt Ladungen an die Wechte. Noch zwanzig Sekunden, dann jagen sie den Hang selbst hoch!", 0.0,
				{"priority": 1, "max_age": 3.0, "valid": func() -> bool: return not _avalanche})
		if _falk_t <= 0.0:
			_trigger_avalanche(false)

func _trigger_avalanche(by_player: bool, quiet: bool = false) -> void:
	if _avalanche:
		return
	_avalanche = true
	var t := _target("cornice")
	if not t.is_empty():
		t["alive"] = false
	_falk_t = -1.0
	if _wechte_body != null and is_instance_valid(_wechte_body):
		_wechte_body.queue_free()
	var dur := 0.3 if quiet else 5.0
	if not quiet:
		if by_player:
			_say_opt(SD.LENA, "Da kommt der Hang! Runter, runter!", 0.0, {"priority": 2, "cut": true})
			_say(SD.BRANDT, "Die Rinne ist zu. Von den Grauen kommt keiner mehr raus. Die Straße auch nicht – nehmt den Steig über den Grat.")
		else:
			Combat.explode(_wechte.global_position + Vector3(2, 1, 0), 6.0, 0.0, null, 1.6)
			_say_opt(SD.BRANDT, "Sprengung am Hang! Falk jagt die Wechte selbst hoch!", 0.0, {"priority": 2, "cut": true})
			_say(SD.LENA, "Er begräbt seine eigenen Leute, nur um die Straße zu sperren...")
			_say(SD.BRANDT, "Die Straße ist zu. Nehmt den Steig über den Grat.")
		_avalanche_fx(dur)
	if _wechte != null and is_instance_valid(_wechte):
		var tw := create_tween()
		tw.tween_property(_wechte, "global_position", _wechte.global_position + Vector3(10, -14, 12), 1.2 if not quiet else 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(_wechte.queue_free)
	_later(dur, _avalanche_landed.bind(quiet))

## Schneemassen rollen die Rinne hinab: Pulverschnee-Front (alpenpass_avalanche.gd), Brocken, Kamerabeben,
## dumpfes Grollen (tief gepitchte Einsturz-/Donner-Sounds).
func _avalanche_fx(dur: float) -> void:
	var p0: Vector3 = RINNE[0]
	var p1: Vector3 = RINNE[1]
	var p2: Vector3 = RINNE[2]
	var top := p0 + (p0 - p1).normalized() * 30.0          # Anriss oberhalb der Wechte
	var av := Avalanche.new()
	av.name = "Lawine"
	add_child(av)
	av.setup([top, p0, p1, p2.lerp(Vector3(-14, -22, -453), 0.5), Vector3(-6, -22, -458)], dur + 1.0, ter, mats["snow"])
	_sfx_at("river_thunder", top, 10.0, 600.0, 0.55)
	_sfx_at("river_collapse", p0, 8.0, 450.0, 0.7)
	_later(1.2, func() -> void: _sfx_at("destruct_collapse", p1, 9.0, 450.0, 0.5))
	_later(1.6, func() -> void: _sfx_at("river_thunder", p1, 8.0, 600.0, 0.45))
	_later(2.8, func() -> void: _sfx_at("river_collapse", p2, 8.0, 450.0, 0.6))
	_later(4.2, func() -> void: _sfx_at("destruct_collapse", Vector3(-10, -22, -450), 6.0, 450.0, 0.45))
	var pl := _player()
	if pl != null:
		pl.add_trauma(0.35)
		for k in 5:
			_later(0.8 + float(k) * 0.9, func() -> void:
				var p3 := _player()
				if p3 != null:
					p3.add_trauma(0.32 + 0.1 * float(k % 3)))

func _avalanche_landed(quiet: bool) -> void:
	# Alles in der Rinne verschuettet (Garde, die noch nicht heraus ist)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not _alive(e):
			continue
		var p := (e as Node3D).global_position
		if _poly_dist(Vector2(p.x, p.z), RINNE) < 14.0:
			if _is_puppet(e):
				(e as Node).call("_die")
			elif (e as Node).has_method("take_damage"):
				(e as Node).call("take_damage", 5000.0, null, p, Vector3.UP)
	_garde.assign(_garde.filter(func(g: Variant) -> bool: return _alive(g)))
	# Lawinenkegel auf der Strasse (Kollision steht schon im Navmesh, siehe _build_boundaries): weisse
	# Ablagerung als Hoehenfeld (Material ohne Strassenmaske, sonst laegen Spurrillen auf dem Kegel)
	var cm := (mats["ter"] as ShaderMaterial).duplicate() as ShaderMaterial
	cm.set_shader_parameter("road_mask", null)
	Avalanche.build_cone(self, ter, [[-14.0, -453.0, 40.0, 24.0, 13.0], [-34.0, -436.0, 20.0, 15.0, 7.0], [6.0, -462.0, 18.0, 14.0, 6.0]], cm)
	if not quiet:
		Avalanche.puff(self, Vector3(-6, -14, -446), 18.0, 6, 6.0)
		Avalanche.puff(self, Vector3(8, -16, -456), 16.0, 6, 6.0)
		_later(3.0, _start_phase5)

func _start_phase5() -> void:
	if _phase >= 5:
		return
	_phase = 5
	_spot_active = false
	spot.set("enabled", false)
	_open_gate("g2")
	_obj("Über den Grat-Steig zur Bergstation – bevor die Seilbahn abfährt")
	_spawn_wave_alp(2)
	_cable_t = DEPART_TIME
	_later(4.0, _when_radio_free.bind(func() -> void:
		if _phase == 5:
			_say_opt(SD.BRANDT, "Die Bergstation macht die Seilbahn klar. Zweieinhalb Minuten, dann ist Weber über die Grenze – lauft!", 0.0, {"priority": 1}), 10.0))

func _tick_countdown(delta: float) -> void:
	if _cable_t <= 0.0 or _phase != 5:
		return
	var before := _cable_t
	_cable_t -= delta
	if before > 60.0 and _cable_t <= 60.0:
		_say_opt(SD.BRANDT, "Noch eine Minute bis zur Abfahrt!", 0.0, {"priority": 1, "max_age": 3.0})
	if _cable_t <= 0.0:
		_late = true
		_depart_cabin()
		_spawn_wave_alp(9)
		_say(SD.LENA, "Zu spät – und Falks Leute sind vor uns an der Station.")

func _on_ridge() -> void:
	if _phase < 5:
		return
	_checkpoint("cp_grat")
	if not _said.has("ridge"):
		_said["ridge"] = true
		_say_opt(SD.LENA, "Garde auf dem Grat! Deckung!", 0.0, {"priority": 1, "max_age": 2.0})

func _start_phase6() -> void:
	if _phase != 5:
		return
	_phase = 6
	_cable_t = -1.0
	_checkpoint("cp_station")
	_obj("Bergstation sichern – nicht auf die Kabine schießen")
	_spawn_wave_alp(3)
	if not _cabin_moving:
		_depart_cabin()

func _depart_cabin() -> void:
	if _cabin_moving or _cabin_prog > 0.0:
		return
	_cabin_moving = true
	_loop_3d("rail_metal_creak", self, _so(Vector3(0, 2.0, -326)), -6.0, 8.0, 80.0)
	_say(SD.BRANDT, "Die Seilbahn läuft – Weber sitzt in der Kabine! Nicht darauf schießen, er muss lebend vor Gericht.")
	_say(SD.WEBER, "Kerner. Hartnäckig wie immer. Grüßen Sie Falk von mir – falls er Sie vorher nicht erwischt.")

func _try_finish() -> void:
	if _finished or _phase < 6:
		return
	var alive := 0
	for e in (_waves[3] as Array) + (_waves[9] as Array):
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

func _on_mission_requested(_target_p: Vector3, _dist: float) -> void:
	_salvo_hit = false
	_tut["mark"] = true
	_say_idle("req", 75.0, SD.LENA, "Feuerauftrag ist raus. Mörserzug bestätigt.")

func _on_salvo_fired(_aim: Vector3, _ft: float, _rounds: int) -> void:
	_salvo_hit = false

func _on_mission_refused(reason: String) -> void:
	if _bot and _t >= float(_cd.get("dbg_ref", -1.0)):
		_cd["dbg_ref"] = _t + 5.0
		print("[alpenpass] verweigert: %s" % reason)
	match reason:
		"laden":
			_say_idle("laden", 30.0, SD.LENA, "Die Rohre laden noch. Geduld.")
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
	_tut["impact"] = true
	for t in _targets:
		if not bool(t["alive"]) or int(t["phase"]) != _phase:
			continue
		var tp := _target_pos(t)
		var r := float(t["radius"])
		var d := Vector2(pos.x - tp.x, pos.z - tp.z).length()
		var pts := 0
		if str(t["kind"]) == "cornice":
			d = pos.distance_to(tp)
			pts = 1 if d < r else 0
		else:
			pts = 2 if d < r * 0.4 else (1 if d < r else 0)
		if pts <= 0:
			continue
		_salvo_hit = true
		t["seen"] = true
		t["hp"] = int(t["hp"]) - pts
		if int(t["hp"]) <= 0:
			_destroy_target(t, false)
		else:
			_say_idle("partial", 6.0, SD.LENA, "Treffer am %s – aber es ist noch nicht erledigt. Gleiche Werte, noch eine Salve!" % str(t["name"]))
	if lena != null and is_instance_valid(lena) and pos.distance_to(lena.global_position) < 12.0:
		_say_cd("lena_close", 15.0, SD.LENA, "Kerner! Die lag fast auf mir!")

func _on_salvo_complete(impacts: Array) -> void:
	var open := _open_targets()
	if not _salvo_hit and not open.is_empty() and not impacts.is_empty():
		_misses += 1
		_say_idle("miss", 25.0, SD.LENA, "Die Salve lag daneben. Markier direkt auf das Ziel.")
	if not open.is_empty() and int(spot.get("salvos_left")) <= 0:
		_request_refill()
	if _bot:
		var mi := Vector3.ZERO
		for p: Variant in impacts:
			mi += (p as Vector3) / float(maxi(impacts.size(), 1))
		var tt := _target(_bt_id)
		print("[alpenpass] salve: treffer=%s ziel=%s n=%d mitte=%s ziel_pos=%s aim=%s" % [str(_salvo_hit), _bt_id, impacts.size(), str(mi.snapped(Vector3.ONE)),
			str(_target_pos(tt).snapped(Vector3.ONE)) if not tt.is_empty() else "-", str(_bt_aim.snapped(Vector3.ONE))])
		_bot_after_salvo(impacts)

func _open_targets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for t in _targets:
		if bool(t["alive"]) and int(t["phase"]) == _phase:
			if str(t["kind"]) == "vehicle" and _veh_state == "idle":
				continue
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
				_say_opt(SD.LENA, "MG-Nest ist weg. Volltreffer.", 0.0, {"max_age": 2.0, "key": "ap_kill"})
		"squad":
			t["alive"] = false
			for a: Variant in (t["crew"] as Array):
				if _alive(a):
					(a as Node).call("_die")
			Props.fire(self, (t["pos"] as Vector3) + Vector3(0.6, 0.1, 0.8), 0.5, true, 1.2, 2.5)
			if not quiet:
				_say_idle("squad_down", 4.0, SD.LENA, "Die Schützengruppe ist erledigt.")
		"dugout":
			t["alive"] = false
			var p: Vector3 = t["pos"]
			var b := Geo.box_mesh_node(Vector3(6.4, 0.9, 5.8), mats["logs"], p + Vector3(0, 0.6, 0), Vector3(8, 15, -6))
			add_child(b)
			Props.fire(self, p + Vector3(1, 0.4, 2.4), 0.8, true, 2.0, 3.0)
			if not quiet:
				VFX.spawn_dust_cloud(p, 8.0)
				_say_opt(SD.LENA, "Der Unterstand ist eingestürzt. Gute Arbeit.", 0.0, {"max_age": 2.0, "key": "ap_kill"})
		"vehicle":
			_destroy_vehicle(quiet)
		"cornice":
			_trigger_avalanche(true, quiet)
	if int(t["phase"]) == 1:
		_update_phase1_obj()
		if not quiet:
			_counter_t = minf(_counter_t, 10.0)
		var all_dead := true
		for o in _targets:
			if int(o["phase"]) == 1 and bool(o["alive"]):
				all_dead = false
		if all_dead and not quiet:
			_later(3.0, func() -> void: _end_phase1())
	elif int(t["phase"]) == 3:
		if _phase == 3:
			_update_phase3_obj()
		var all_dead3 := true
		for o in _targets:
			if int(o["phase"]) == 3 and bool(o["alive"]):
				all_dead3 = false
		if all_dead3 and not quiet:
			_later(4.0, _start_phase4)

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

# ------------------------------------------------------------------ Auffindbarkeit (Muendungsfeuer, Callouts)

## Treffer am Spieler: Lena ruft Richtung (Uhrzeit) und Entfernung des Schuetzen aus, HUD markiert ihn.
func _on_player_damaged(_amount: float, source: Node) -> void:
	if source == null or not is_instance_valid(source) or not (source is Node3D) or source.is_in_group("player"):
		return
	if not source.is_in_group("enemy"):
		return
	var e := source as Node3D
	_reveal[e.get_instance_id()] = {"n": e, "until": _t + 8.0}
	if _t < _callout_cd:
		return
	_callout_cd = _t + 14.0
	var pl := _player()
	if pl == null:
		return
	var d := pl.global_position.distance_to(e.global_position)
	var dy := e.global_position.y - pl.global_position.y
	var extra := ""
	if dy > 8.0:
		extra = ", oben am Hang"
	elif dy < -8.0:
		extra = ", unter uns"
	_say_idle("shooter", 4.0, SD.LENA, "Schütze auf %d Uhr, %d Meter%s!" % [_clock(e.global_position), roundi(d / 5.0) * 5, extra])

## Schuesse der Gegner: kurzer Muendungsblitz (sichtbar durch den Nebel) + HUD-Markierung.
func _tick_muzzles() -> void:
	var pl := _player()
	if pl == null:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not _alive(e):
			continue
		var s: Variant = e.get("stat_shots")
		if s == null:
			continue
		var id := e.get_instance_id()
		var prev := int(_shots.get(id, int(s)))
		_shots[id] = int(s)
		if int(s) <= prev:
			continue
		var n3 := e as Node3D
		var d := n3.global_position.distance_to(pl.global_position)
		if d > 320.0:
			continue
		_reveal[id] = {"n": n3, "until": _t + 5.0}
		if d < 22.0 or _t < float(_flash_cd.get(id, -1.0)):
			continue
		_flash_cd[id] = _t + 0.14
		var mp: Vector3 = n3.call("muzzle_pos") if n3.has_method("muzzle_pos") else n3.global_position + Vector3(0, 1.4, 0)
		var l := _omni(mp, Color(1.0, 0.72, 0.38), 8.0, 9.0, 6.0)
		_later(0.07, l.queue_free)

## Moerserziele entdecken: Fernglasblick (<6 Grad, bei Sicht), Muendungsfeuer im Fenster, Lenas Meldungen.
func _tick_discovery(delta: float) -> void:
	if not _spot_active:
		return
	var cam := get_viewport().get_camera_3d()
	if cam != null and bool(spot.call("is_up")):
		var fwd := -cam.global_transform.basis.z
		for t in _open_targets():
			if bool(t["seen"]):
				continue
			var tp := _target_pos(t)
			if fwd.angle_to((tp - cam.global_position).normalized()) < deg_to_rad(6.0):
				t["seen"] = true
				_say_idle("spotted", 6.0, SD.LENA, "Gesehen – %s, %d Meter. Markier es." % [str(t["name"]), roundi(_dist_to_player(tp) / 10.0) * 10])
	_report_t -= delta
	if _report_t > 0.0:
		return
	_report_t = 12.0
	for t in _open_targets():
		if bool(t["seen"]):
			continue
		if str(t["kind"]) == "vehicle" and _veh_state != "stopped":
			continue
		t["seen"] = true
		var tp := _target_pos(t)
		_say_idle("tgt_clock", 4.0, SD.LENA, "%s auf %d Uhr, %d Meter." % [str(t["name"]), _clock(tp), roundi(_dist_to_player(tp) / 10.0) * 10])
		break

# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "AlpenpassHud"
	_hud.layer = 6
	add_child(_hud)
	_hud_ctrl = Control.new()
	_hud_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hud_ctrl)
	_hud_ctrl.draw.connect(_draw_hud)
	_hud_root = UIStyle.HudRoot.new()
	_hud.add_child(_hud_root)
	_hud_ui = Control.new()
	_hud_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_root.add_child(_hud_ui)
	_hud_ui.draw.connect(_draw_hud_ui)

func _draw_hud_ui() -> void:
	var pl := _player()
	if pl == null or spot == null:
		return
	var f := ThemeDB.fallback_font
	var vs := _hud_ui.size
	var c := _hud_ui
	var fac := _hud_root.factor
	# --- Moerser (links): Tutorial-Schritte bzw. Status
	if _spot_active:
		var y0 := vs.y * 0.34
		var lines: Array = []
		if _tut_on:
			lines = [
				[_tut.has("raise"), "[%s] Fernglas heben" % _key("binoculars")],
				[_tut.has("mark"), "Ziel anvisieren, [LMB] markieren – Salve kommt sofort"],
				[_tut.has("impact"), "Einschläge beobachten – steht noch was, erneut markieren"],
			]
		var k := float(UIStyle.min_fs(14, fac)) / 14.0   # Tafel waechst mit der Mindestschrift (kleine Fenster)
		var h := (36.0 + 22.0 * float(lines.size())) * k
		c.draw_rect(Rect2(16, y0, 480 * k, h), Color(0.02, 0.03, 0.05, 0.5))
		c.draw_string(f, Vector2(28, y0 + 22 * k), "MÖRSERZUG", HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.min_fs(16, fac), Color(1.0, 0.78, 0.4))
		var st := str(spot.call("state"))
		var tl := float(spot.call("state_time_left"))
		var st_txt := {"ready": "feuerbereit", "prep": "Feuer!", "flight": "Salve in der Luft %d s" % ceili(tl), "reload": "lädt %d s" % ceili(tl), "empty": "keine Salven"}.get(st, st) as String
		c.draw_string(f, Vector2(28 + 102 * k, y0 + 22 * k), "%s  ·  Salven %d" % [st_txt, int(spot.get("salvos_left"))], HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.min_fs(14, fac), Color(0.9, 0.9, 0.9))
		for i in lines.size():
			var done: bool = lines[i][0]
			c.draw_string(f, Vector2(28, y0 + (46 + 22.0 * float(i)) * k), ("✔ " if done else "○ ") + str(lines[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, UIStyle.min_fs(14, fac),
				Color(0.55, 0.9, 0.55) if done else Color(0.95, 0.95, 0.95))
	# --- Seilbahn-Countdown (oben Mitte)
	if _phase == 5 and _cable_t > 0.0:
		var txt := "SEILBAHN FÄHRT AB IN %d:%02d" % [int(_cable_t) / 60, int(_cable_t) % 60]
		var cc := Color(1.0, 0.35, 0.3) if _cable_t < 30.0 else Color(1.0, 0.9, 0.6)
		c.draw_string(f, Vector2(vs.x * 0.5 - 200, 120), txt, HORIZONTAL_ALIGNMENT_CENTER, 400, 22, cc)

func _draw_hud() -> void:
	var pl := _player()
	if pl == null or spot == null:
		return
	# --- Marker (echte Pixel)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for id: Variant in _reveal.keys():
		var r: Dictionary = _reveal[id]
		var n: Variant = r["n"]
		if not _alive(n) or _t > float(r["until"]):
			_reveal.erase(id)
			continue
		var p := (n as Node3D).global_position + Vector3(0, 1.0, 0)
		_draw_marker(cam, p, Color(1.0, 0.28, 0.22), "", false)
	if _spot_active:
		for t in _open_targets():
			if bool(t["seen"]):
				var tp := _target_pos(t)
				_draw_marker(cam, tp + Vector3(0, 1.5, 0), Color(1.0, 0.65, 0.15), "%s  %d m" % [str(t["name"]).to_upper(), roundi(_dist_to_player(tp))], true)

func _draw_marker(cam: Camera3D, p: Vector3, col: Color, label: String, diamond: bool) -> void:
	var c := _hud_ctrl
	var vs := c.size
	var behind := cam.is_position_behind(p)
	var sp := cam.unproject_position(p)
	var m := 36.0
	if not behind and sp.x > m and sp.y > m and sp.x < vs.x - m and sp.y < vs.y - m:
		var d := cam.global_position.distance_to(p)
		var ms := clampf(UIStyle.hud_scale(vs), 0.6, 2.0)
		var s := clampf(700.0 / maxf(d, 1.0), 7.0, 22.0) * ms
		if diamond:
			var pts := PackedVector2Array([sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0), sp + Vector2(0, -s)])
			c.draw_polyline(pts, col, 2.0)
		else:
			for k in 4:
				var sx := -1.0 if k % 2 == 0 else 1.0
				var sy := -1.0 if k < 2 else 1.0
				var cn := sp + Vector2(sx * s, sy * s)
				c.draw_line(cn, cn - Vector2(sx * s * 0.5, 0), col, 2.0)
				c.draw_line(cn, cn - Vector2(0, sy * s * 0.5), col, 2.0)
		if label != "":
			c.draw_string(ThemeDB.fallback_font, sp + Vector2(-120, s + 18 * ms), label, HORIZONTAL_ALIGNMENT_CENTER, 240, maxi(roundi(13 * ms), 9), col)
		return
	# ausserhalb: Pfeil am Rand
	var ctr := vs * 0.5
	var dir := sp - ctr
	if behind:
		dir = -dir
	if dir.length() < 1.0:
		dir = Vector2(0, 1)
	dir = dir.normalized()
	var ext := ctr - Vector2(m + 10, m + 10)
	var k2 := minf(ext.x / maxf(absf(dir.x), 0.001), ext.y / maxf(absf(dir.y), 0.001))
	var tip := ctr + dir * k2
	var side := Vector2(-dir.y, dir.x)
	c.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 16 + side * 8, tip - dir * 16 - side * 8]), col)

# ------------------------------------------------------------------ Tick

func _process(delta: float) -> void:
	if _debug_god:
		var gp := _player()
		if gp != null:
			gp.set("health", float(gp.get("max_health")))
	if _heli != null and is_instance_valid(_heli):
		_heli_angle += delta * 11.0
		var bl: Variant = _heli_parts.get("blades")
		if bl is Node3D and is_instance_valid(bl):
			(bl as Node3D).rotation.y = -_heli_angle
		var tr: Variant = _heli_parts.get("tail_rotor")
		if tr is Node3D and is_instance_valid(tr):
			(tr as Node3D).rotate_object_local(_heli_parts.get("tail_axis", Vector3.RIGHT) as Vector3, delta * 23.0)
		for key: String in ["disc_mat", "tail_disc_mat"]:
			var dm: Variant = _heli_parts.get(key)
			if dm is ShaderMaterial:
				(dm as ShaderMaterial).set_shader_parameter("spin", _heli_angle * (2.7 if key == "disc_mat" else -5.0))
				(dm as ShaderMaterial).set_shader_parameter("opacity", 0.34 if key == "disc_mat" else 0.28)
		# Rotorabwind wirbelt Schnee auf
		_heli_dust_t -= delta
		var gy := ter.height(_heli.global_position.x, _heli.global_position.z)
		if _heli_dust_t <= 0.0 and _heli.global_position.y - gy < 18.0:
			_heli_dust_t = 0.35
			var a := randf() * TAU
			Avalanche.puff(self, Vector3(_heli.global_position.x + cos(a) * 6.0, gy + 0.8, _heli.global_position.z + sin(a) * 6.0), 6.0, 4, 2.4)
	_tick_backdrop()
	if _hud_ctrl != null:
		_hud_ctrl.queue_redraw()
	if _hud_ui != null:
		_hud_ui.queue_redraw()

## Gipfelketten: eigene Luftperspektive aus dem aktuellen Nebel (Sturm -> verschwinden, Sichtfenster -> Fernsicht).
func _tick_backdrop() -> void:
	if _backdrop == null or _env == null:
		return
	# Spieler-Kamera sieht standardmaessig nur 500 m -> Fernring/Gipfelketten waeren abgeschnitten
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.far < 4000.0:
		cam.far = 4000.0
	var m := _backdrop.material_override as ShaderMaterial
	var fd := _env.fog_density if _env.fog_enabled else 0.0
	m.set_shader_parameter("haze_k", fd * 0.26)
	m.set_shader_parameter("haze_cap", lerpf(0.62, 1.0, clampf((fd - 0.0015) / 0.004, 0.0, 1.0)))
	m.set_shader_parameter("haze_color", _env.fog_light_color)

## Fernglas-Optik: Der Tiefennebel (Wetter ~0.009/m) macht 250 m Zielentfernung zu >90 % Weiss -> im Glas nur Marker.
## Bei gehobenem Fernglas laeuft der Nebel mit 0.3fach Dichte (verguetete Optik, Kontrast) und die Belichtung sinkt etwas,
## damit Schnee Zeichnung behaelt. Laeuft nach allen _process (WeatherSystem schreibt die Dichte jeden Frame neu).
func _optic_env() -> void:
	if _env == null or spot == null or not is_instance_valid(spot):
		return
	var up := bool(spot.call("is_up"))
	var cur := Vector2(_env.fog_density, _env.volumetric_fog_density)
	if not is_equal_approx(cur.x, _optic_fog.x) or not is_equal_approx(cur.y, _optic_fog.y):
		_optic_base = cur   # Wetter hat neu geschrieben (oder Fernglas war unten)
	if up:
		_env.fog_density = _optic_base.x * 0.3
		_env.volumetric_fog_density = _optic_base.y * 0.35
		_env.tonemap_exposure = 0.84
		_optic_fog = Vector2(_env.fog_density, _env.volumetric_fog_density)
	else:
		if _optic_fog.x >= 0.0:
			_env.fog_density = _optic_base.x
			_env.volumetric_fog_density = _optic_base.y
			_env.tonemap_exposure = 0.95
		_optic_fog = Vector2(-1.0, -1.0)

func _physics_process(delta: float) -> void:
	if spot == null or not is_inside_tree():
		return
	_t += delta
	_tick_cabin(delta)
	_tick_targets(delta)
	_tick_vehicle(delta)
	_tick_garde(delta)
	_tick_countdown(delta)
	_tick_muzzles()
	_tick_discovery(delta)
	if _phase == 1 and _counter_t > 0.0:
		_counter_t -= delta
		if _counter_t <= 0.0:
			_spawn_counter()
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
			alive.append("%s:%d" % [str(t["id"]), int(t["hp"])])
	print("[alpenpass] t=%.0f phase=%d pos=%s spot=%s salvos=%d drive=%s targets=%s veh=%s cabin=%.2f cable_t=%.0f enemies=%d" % [_t, _phase,
		str(pl.global_position.snapped(Vector3.ONE)) if pl != null else "-", str(spot.call("state")), int(spot.get("salvos_left")),
		str(bot_drives_player()), ",".join(alive), _veh_state, _cabin_prog, _cable_t,
		get_tree().get_nodes_in_group("enemy").size()])

func _tick_cabin(delta: float) -> void:
	if not _cabin_moving or _cabin == null:
		return
	_cabin_prog = minf(1.0, _cabin_prog + delta * CABIN_SPEED / _cable_len)
	_cabin.global_position = _cabin_pos(_cabin_prog)
	if _cabin_prog > 0.55 and not _cabin_gone:
		_cabin_gone = true
		_say(SD.LENA, "Weg. Der Sturm hat ihn verschluckt.")
		if not _finished and _phase >= 6:
			_obj("Steuerraum der Bergstation durchsuchen")
	if _cabin_prog >= 1.0:
		_cabin_moving = false
		_cabin.visible = false

func _tick_targets(delta: float) -> void:
	var pl := _player()
	if pl == null or (_phase != 1 and _phase != 3):
		return
	# MG-Nester: Leuchtspur-Feuerstoesse Richtung Posten, Schuetzengruppen Einzelfeuer (verraten ihre Lage)
	for t in _targets:
		var kind := str(t["kind"])
		if (kind != "nest" and kind != "squad") or not bool(t["alive"]) or int(t["phase"]) != _phase:
			continue
		var crew: Array = t["crew"]
		t["fire_t"] = float(t["fire_t"]) - delta
		if float(t["fire_t"]) > 0.0:
			continue
		t["seen"] = true
		if kind == "squad":
			t["fire_t"] = randf_range(1.6, 3.0)
			for k in 2:
				var sh: Variant = crew[randi() % crew.size()]
				var aim_s := pl.global_position + Vector3(randf_range(-5, 5), randf_range(-1.0, 3.0), randf_range(-4, 4))
				_later(0.35 * float(k) + randf() * 0.2, func() -> void:
					if _alive(sh):
						(sh as Node).call("puppet_fire", aim_s, 2.0))
			continue
		t["fire_t"] = randf_range(3.0, 5.0)
		var a0: Variant = crew[0]
		if not _alive(a0):
			continue
		var aim := pl.global_position + Vector3(randf_range(-6, 6), randf_range(-1.0, 3.0), randf_range(-4, 4))
		for k in 5:
			_later(0.11 * float(k), func() -> void:
				if _alive(a0):
					(a0 as Node).call("puppet_fire", aim, 2.0))

func _tick_sight() -> void:
	var f := _sight()
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Node and not _is_puppet(e):
			(e as Node).set("sight_range", ENEMY_SIGHT * f)
	# aufraeumen
	for id: Variant in _shots.keys():
		if not is_instance_id_valid(int(id)):
			_shots.erase(id)
			_flash_cd.erase(id)

func _tick_lena() -> void:
	var pl := _player()
	if pl == null or lena == null or not is_instance_valid(lena):
		return
	var to := pl.global_position - lena.global_position
	var dist := to.length()
	if dist > 45.0 or absf(to.y) > 14.0:
		_lena_to_player()
		return
	var spotting := _spot_active and (_phase == 1 or _phase == 3 or _phase == 4)
	lena.set("crouch", spotting)
	var flat := Vector3(to.x, 0, to.z)
	if dist > 4.0:
		var goal := pl.global_position - flat.normalized() * 2.5 + pl.global_transform.basis.x * 1.2
		lena.call("walk_to", goal, 4.6 if dist > 10.0 else 2.6, true)

func _lena_to_player() -> void:
	var pl := _player()
	if pl == null or lena == null:
		return
	var back := pl.global_transform.basis.z
	back.y = 0.0
	var p := pl.global_position + back.normalized() * 2.0 + pl.global_transform.basis.x * 1.0
	p.y = maxf(p.y, ter.height(p.x, p.z)) + 0.3
	lena.global_position = p
	lena.set("has_goal", false)

func _tick_lena_fire(delta: float) -> void:
	_lena_fire_t -= delta
	if _lena_fire_t > 0.0 or lena == null:
		return
	_lena_fire_t = randf_range(1.2, 2.2)
	var best: Node3D = null
	var bd := 40.0
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
		return t
	return {}

func _bot_stand() -> Vector3:
	if _phase == 1:
		return _gp(OP1.x, OP1.y - 6.0)
	return _gp(OP2.x, OP2.y - 6.0)

func _bot_err() -> float:
	return 4.0 if _skill == "novice" else (2.5 if _skill == "average" else 1.2)

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
	var stand := _bot_stand()
	var off := stand - pl.global_position
	off.y = 0.0
	if off.length() > 0.8:
		# Navmesh-Pfad zum Standplatz (gerade Linie scheitert an Haengen)
		var path := NavigationServer3D.map_get_path(world.get_navigation_map(), pl.global_position, stand, true)
		for q in path:
			var o2 := q - pl.global_position
			o2.y = 0.0
			if o2.length() > 0.7:
				off = o2
				break
		var loc := pl.global_transform.basis.inverse() * off.normalized()
		ext["move"] = Vector2(loc.x, -loc.z)
	var t := _bot_target()
	if t.is_empty():
		var look: Vector3 = _gp(0, -260) if _phase == 1 else (_veh.global_position if _phase == 3 else (_target("cornice")["pos"] as Vector3))
		pl.look_at_point(look + Vector3(0, 1.0, 0))
		return
	var tp := _target_pos(t)
	if str(t["id"]) != _bt_id:
		_bt_id = str(t["id"])
		_bt_next = "mark"
		_bt_idle = 0.0
		_bt_wait = _brng.randf_range(0.8, 2.0)
	if not bool(spot.call("is_up")):
		spot.call("raise", true)
		_bt_wait = maxf(_bt_wait, 0.6)
		return
	pl.look_at_point(_bt_aim if _bt_next == "wait" else tp + Vector3(0, 0.5, 0))
	if _bt_next == "wait":
		_bt_idle += delta
		if _bt_idle > 20.0:
			_bt_next = "mark"
		return
	if _bt_wait > 0.0:
		_bt_wait -= delta
		return
	var st := str(spot.call("state"))
	if st != "ready" and st != "empty":
		return
	if _bt_next == "mark":
		var e := _bot_err()
		_bt_aim = tp + Vector3(_brng.randf_range(-e, e), 0.4, _brng.randf_range(-e, e))
		pl.look_at_point(_bt_aim)
		if bool(spot.call("mark_from_camera")):
			_bt_next = "wait"
			_bt_idle = 0.0
		_bt_wait = 1.5

## Nach der Salve: Ziel steht noch -> neu markieren (keine Korrektur noetig, die Salve liegt am Zielpunkt).
func _bot_after_salvo(_impacts: Array) -> void:
	var t := _target(_bt_id)
	_bt_next = "mark"
	if t.is_empty() or not bool(t["alive"]):
		return
	_bt_aim = _target_pos(t) + Vector3(0, 0.4, 0)
	_bt_wait = _brng.randf_range(0.6, 1.6) if _skill != "novice" else _brng.randf_range(1.5, 3.0)

# ------------------------------------------------------------------ Debug-Einstieg

## --phase=N: direkt in Phase N einsteigen (Captures, Tests). Wartet auf den Spieler.
func _debug_phase(n: int) -> void:
	var waited := 0
	while _player() == null and waited < 900:
		await get_tree().physics_frame
		waited += 1
	var pl := _player()
	if pl == null:
		return
	if _heli != null:
		_heli.queue_free()
		_heli = null
	var pos := _gp(0, -50, 0.2)
	var first_wp := int(_wp_idx.get("start", 2))
	_start_phase1()
	if n >= 2:
		for t in _targets:
			if int(t["phase"]) == 1:
				_destroy_target(t, true)
		_end_phase1(true)
		pos = _gp(-4, -150, 0.2)
		first_wp = int(_wp_idx.get("kessel", 9))
	if n >= 3:
		_start_phase3()
		pos = _gp(0, -392, 0.2)
		first_wp = int(_wp_idx.get("sattel", 14))
	if n >= 4:
		for t in _targets:
			if int(t["phase"]) == 3:
				_destroy_target(t, true)
		_start_phase4()
		pos = _gp(0, -400, 0.2)
	if n == 4 and str(Game.arg("avalanche", "")) != "":  # Captures: Lawine nach x s ausloesen
		_later(float(Game.arg("avalanche", "3")), _trigger_avalanche.bind(true))
	if n >= 5:
		_trigger_avalanche(true, true)
		_start_phase5()
		pos = _gp(10, -408, 0.2)
		first_wp = int(_wp_idx.get("steig", 16))
	if n >= 6:
		pos = _gp(4, -604, 0.2)
		first_wp = int(_wp_idx.get("station", 22))
		_start_phase6()
	for w in get_tree().get_nodes_in_group("bot_waypoint"):
		if int(w.get_meta("order", 0)) < first_wp:
			w.remove_from_group("bot_waypoint")
	pl.global_position = pos
	pl.velocity = Vector3.ZERO
	pl.set_view(0.0, 0.0)
	_lena_to_player()
	_checkpoint("cp_debug_%d" % n)
	# Die übersprungenen Phasen haben ihre Funksprüche schon eingereiht – verwerfen.
	get_tree().call_group(&"story_ui", &"interrupt")
