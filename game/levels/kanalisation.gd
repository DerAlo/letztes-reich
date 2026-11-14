extends "res://game/levels/level.gd"
## Mission 11 "Unter dem Reichstag" (Kanalisation Tiergarten, 25.06.2030, 01:50).
## Kerner schleicht durch Voss' Versorgungsgang und den alten Hauptsammler unter dem Reichstag
## zum Kanzleramt. Stockdunkel: Nachtsichtgeraet (N) oder Taschenlampe (L, verraet ihn).
## Garde-Streifen mit Lampen (Schleich-KI aus "curfew"), Takedowns, knietiefes Wasser (langsam, laut),
## Sprengladungen mit Lichtschranken an den Fundamentpfeilern (entschaerfen: E halten, oder durchs
## Becken umgehen). Entdeckung = Alarm, Garde und Gepanzerte ruecken nach. Ende: Leiter hoch in den
## Versorgungskeller des Kanzleramts (Uebergang zu "kanzleramt").
##
## Debug: --kn-start=sammler|halle|kanal|depot|schacht  (Startpunkt), --kn-nv (Nachtsicht sofort an)

const BP = preload("res://game/levels/berlin_props.gd")
const Stealth = preload("res://game/levels/kanalisation_stealth.gd")
const Brain = preload("res://game/enemies/stealth_brain.gd")
const TakedownScript = preload("res://game/weapons/takedown.gd")
const HudScript = preload("res://game/levels/curfew_hud.gd")
const NightVision = preload("res://game/systems/nightvision.gd")
const CivFigure = preload("res://game/characters/civ_figure.gd")
const PH = preload("res://game/levels/ph_props.gd")
const DK = preload("res://game/levels/debris_kit.gd")
const FK = preload("res://game/levels/furniture_kit.gd")
## Realismus-Durchgang (Poly Haven, CC0; tools/fetch_realism_assets.py, assets/CREDITS_ASSETS.md)
const RL_TEX := "res://assets/environment/realism/textures/"
const RL_MOD := "res://assets/environment/realism/models/"

const XA := -2.75                 ## Mitte Versorgungsgang (oben)
const Y_WALK := -4.5              ## Bankette / trockene Boeden im Sammler
const Y_WET := -5.1               ## Gerinne- und Beckensohle
const Y_WATER := -4.62            ## Wasserspiegel
const DEFUSE_TIME := 2.6
const STARTS := {
	"sammler": [Vector3(-2.75, -4.45, -38.0), "cp_sammler"],
	"halle": [Vector3(2.75, -4.45, -68.0), "cp_halle"],
	"kanal": [Vector3(1.4, -4.45, -115.0), "cp_kanal"],
	"depot": [Vector3(1.4, -4.45, -139.0), "cp_depot"],
	"schacht": [Vector3(0.0, -4.45, -174.0), "cp_depot"],
}

var mats: Dictionary = {}
var director: Node
var takedown: Node
var hud: CanvasLayer
var nv: Node
var _bot: bool = false
var _t: float = 0.0
var _loops: Array[Node] = []
var _alarm_loops: Array[Node] = []
var _alarm_lamps: Array[OmniLight3D] = []
var _reinf: Array[Node] = []
var _reinf_waves: int = 0
var _reinf_t: float = -1.0
var _finished: bool = false
var _water: Array[Dictionary] = []        ## {"min": Vector2, "max": Vector2, "y": float}
var _in_water: bool = false
var _base_speed: Array[float] = []
var _ladders: Array[Dictionary] = []
var _climbing: bool = false
var _climb_cd: float = 0.0
var _charges: Array[Dictionary] = []
var _defused: int = 0
var _defuse_lock: bool = false
var _splash_t: float = 0.0
var _splash: AudioStreamPlayer3D
var _said: Dictionary = {}
var _hold_t0: float = -1.0       ## Bot: Beginn des Wartens auf die Sammler-Einweisung

func _init() -> void:
	level_name = "kanalisation"
	end_z = -186.0
	build_seed = 2511
	_wave_count = 1
	default_faction = "reich"
	ambient_artillery = false

func _ready() -> void:
	_bot = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	await super()
	if not is_inside_tree():
		return
	if str(Game.arg("shots", "")) != "":   # Debug-Aufnahmen mit festen Kameras (villa_shots.gd)
		add_child(load("res://game/levels/tools/villa_shots.gd").new())
	var pl := _player()
	if pl != null:
		_base_speed = [pl.walk_speed, pl.sprint_speed, pl.crouch_speed]
	_equip_suppressed()
	Events.player_respawned.connect(_on_player_respawned)
	_ambience()
	_debug_start()
	if _bot or Game.arg("kn-nv", false):
		nv.call("set_nightvision", true)
	_intro()

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Unter dem Reichstag"
	return info

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
func _say_opt(speaker: String, text: String, opts: Dictionary, dur: float = 0.0) -> void:
	get_tree().call_group(&"story_ui", &"say", speaker, text, dur, opts)

func _say_once_opt(key: String, speaker: String, text: String, opts: Dictionary) -> void:
	if _said.has(key):
		return
	_said[key] = true
	_say_opt(speaker, text, opts)

func _radio_busy() -> float:
	var ui := get_tree().get_first_node_in_group(&"story_ui")
	if ui != null and ui.has_method("busy_left"):
		return float(ui.call("busy_left"))
	return 0.0

## f ausfuehren, sobald der Funk frei ist (hoechstens max_wait s warten).
func _when_radio_free(f: Callable, max_wait: float = 6.0) -> void:
	if _radio_busy() <= 0.3 or max_wait <= 0.0:
		f.call()
		return
	_later(0.25, _when_radio_free.bind(f, max_wait - 0.25))

func _no_alarm() -> bool:
	return not bool(director.get("alarm"))

## Funkspruch nur einmal (Schluessel), z. B. fuer Ausloeser, die mehrfach feuern koennen.
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

func _loop_3d(sfx_name: String, pos: Vector3, vol: float, unit: float, maxd: float) -> AudioStreamPlayer3D:
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
	add_child(p)
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

func _sfx_at(sfx_name: String, pos: Vector3, vol: float = 0.0) -> void:
	var st := Sfx.get_stream(sfx_name)
	if st == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = "SFX"
	p.volume_db = vol
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

func _label(text: String, pos: Vector3, yaw: float, size: int, c: Color, px: float = 0.006) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = c
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.position = pos
	l.rotation_degrees.y = yaw
	add_child(l)
	return l

## Box mit Kollision (Optik im Builder, Form im gemeinsamen Body).
func _sbox(bd: BP.Builder, body: StaticBody3D, key: String, c: Vector3, s: Vector3, yaw_deg: float = 0.0) -> void:
	var rot := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	bd.box(key, c, s, rot)
	Geo.add_box_shape(body, c, s, Vector3(0, yaw_deg, 0))

## Box aus zwei Ecken (min/max), mit Kollision.
func _mm(bd: BP.Builder, body: StaticBody3D, key: String, a: Vector3, b: Vector3) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	_sbox(bd, body, key, (lo + hi) * 0.5, hi - lo)

## Rampe: a/b = Oberkante (Mittellinie) oben/unten, width quer dazu.
func _ramp(bd: BP.Builder, body: StaticBody3D, key: String, a: Vector3, b: Vector3, width: float) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.UP).normalized()
	var up := side.cross(d).normalized()
	var basis := Basis(d, up, d.cross(up))
	var size := Vector3(a.distance_to(b) + 0.3, 0.25, width)
	var c := (a + b) * 0.5 - up * 0.125
	bd.box(key, c, size, basis)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, c)
	body.add_child(cs)

func _pipe(bd: BP.Builder, key: String, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var y := d / len
	var x := y.cross(Vector3.FORWARD) if absf(y.dot(Vector3.FORWARD)) < 0.95 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	bd.cyl(key, (a + b) * 0.5, r, r, len, 10, Basis(x, y, z))

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.27, 0.3)
	env.ambient_light_energy = 0.012
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.sdfgi_enabled = false
	env.fog_enabled = false
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.018
	env.volumetric_fog_albedo = Color(0.75, 0.78, 0.72)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.9
	env.glow_intensity = 0.8
	env.glow_bloom = 0.04
	env.adjustment_enabled = true
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "night_city")
	# Keine Auto-Belichtung: Dunkel bleibt dunkel (sonst hellt die Kamera das Gewoelbe auf).
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = false
	we.camera_attributes = ca
	env.tonemap_exposure = 1.0
	env.ambient_light_energy = 0.012
	env.ambient_light_color = Color(0.25, 0.27, 0.3)

# ------------------------------------------------------------------ Geometrie

func _build_ground() -> void:
	mats = BP.materials()
	mats["concrete"] = Geo.mat("concrete_wall_008", Color(0.42, 0.41, 0.4), 0.22, 1.0)
	mats["concrete_dark"] = Geo.mat("concrete_wall_008", Color(0.26, 0.26, 0.25), 0.25, 1.0)
	mats["brick"] = Geo.mat("brick_wall_02", Color(0.42, 0.33, 0.28), 0.3, 1.0)
	mats["brick_wet"] = Geo.mat("brick_wall_02", Color(0.3, 0.25, 0.21), 0.3, 0.55)
	mats["floor"] = Geo.mat("asphalt_02", Color(0.3, 0.29, 0.27), 0.3, 0.7)
	mats["sludge"] = Geo.flat(Color(0.09, 0.085, 0.06), 0.9)
	mats["metal"] = Geo.mat("rusty_metal_02", Color(0.3, 0.3, 0.3), 0.5, 1.0)
	mats["pipe"] = Geo.mat("rusty_metal_02", Color(0.4, 0.37, 0.33), 1.2, 0.9, 0.5)
	mats["pipe_red"] = Geo.mat("rusty_metal_02", Color(0.6, 0.18, 0.13), 1.2, 0.9, 0.3)
	mats["rack"] = Geo.flat(Color(0.045, 0.05, 0.055), 0.4, 0.6)
	mats["warn"] = Geo.flat(Color(0.75, 0.55, 0.04), 0.6)
	mats["crate"] = Geo.flat(Color(0.22, 0.24, 0.16), 0.85)
	mats["crate2"] = Geo.flat(Color(0.3, 0.24, 0.15), 0.85)
	mats["fluor"] = BP.unshaded(Color(2.2, 2.4, 2.5))
	mats["fluor_off"] = Geo.flat(Color(0.5, 0.52, 0.52), 0.4)
	mats["amber"] = BP.unshaded(Color(3.4, 1.7, 0.35))
	mats["red_glow"] = BP.unshaded(Color(3.0, 0.12, 0.08))
	mats["led_r"] = BP.unshaded(Color(3.2, 0.1, 0.06))
	mats["led_g"] = BP.unshaded(Color(0.2, 2.6, 0.6))
	mats["exit_green"] = BP.unshaded(Color(0.2, 2.6, 0.7))
	mats["laser"] = BP.unshaded(Color(4.0, 0.05, 0.05))
	mats["charge"] = Geo.flat(Color(0.28, 0.29, 0.2), 0.8)
	mats["wire"] = Geo.flat(Color(0.5, 0.06, 0.04), 0.6)
	mats["skin"] = Geo.flat(Color(0.55, 0.4, 0.32), 0.7)
	mats["coat"] = Geo.flat(Color(0.12, 0.12, 0.1), 0.85)
	mats["ladder"] = Geo.flat(Color(0.32, 0.3, 0.27), 0.45, 0.8)
	# Versorgungskeller: gestrichener Putz, Oelfarben-Sockel, gestrichener Estrich (CC0-Texturen)
	mats["plaster"] = DK.tex("res://assets/environment/facade/textures/painted_plaster_wall", Color(0.66, 0.66, 0.62), 0.45, 1.0)
	mats["plaster_sockel"] = DK.tex("res://assets/environment/facade/textures/painted_plaster_wall", Color(0.3, 0.38, 0.33), 0.45, 0.6)
	mats["lino"] = DK.tex("res://assets/environment/bunker/textures/concrete_floor_painted", Color(0.5, 0.5, 0.48), 0.3, 1.0)
	mats["galv"] = Geo.mat("rusty_metal_02", Color(0.62, 0.63, 0.64), 0.8, 0.6, 0.7)
	mats["insul"] = Geo.flat(Color(0.62, 0.6, 0.55), 0.95)
	mats["band"] = Geo.flat(Color(0.5, 0.5, 0.52), 0.4, 0.8)
	mats["wheel_red"] = Geo.flat(Color(0.5, 0.06, 0.04), 0.5, 0.2)
	mats["gauge"] = Geo.flat(Color(0.85, 0.84, 0.8), 0.3)
	mats["cab_grey"] = Geo.flat(Color(0.48, 0.49, 0.47), 0.5, 0.3)
	mats["beam"] = Geo.flat(Color(0.16, 0.12, 0.08), 0.9)
	var w := StandardMaterial3D.new()
	w.albedo_color = Color(0.035, 0.045, 0.03)
	w.roughness = 0.06
	w.metallic = 0.2
	w.metallic_specular = 0.7
	mats["water"] = w

func _build_street() -> void:
	var bd := BP.Builder.new(mats)
	var body := Geo.static_body()
	body.name = "Kanal"
	_build_service_tunnel(bd, body)
	_build_collector(bd, body)
	_build_hall(bd, body)
	_build_brick_channel(bd, body)
	_build_depot(bd, body)
	_build_exit(bd, body)
	world.add_child(body)
	bd.build(world)

## A: Voss' Versorgungsgang (y = 0) mit Schacht hinunter in den Sammler.
func _build_service_tunnel(bd: BP.Builder, body: StaticBody3D) -> void:
	var x0 := XA - 1.5
	var x1 := XA + 1.5
	_mm(bd, body, "concrete_dark", Vector3(x0 - 0.4, -0.3, 4.2), Vector3(x1 + 0.4, 0.0, -33.6))        # Boden bis zum Schacht
	_mm(bd, body, "concrete_dark", Vector3(x0 - 0.4, -0.3, -36.0), Vector3(x1 + 0.4, 0.0, -36.6))
	_mm(bd, body, "concrete", Vector3(x0 - 0.4, 0.0, 4.2), Vector3(x0, 2.9, -36.6))                     # Waende
	_mm(bd, body, "concrete", Vector3(x1, 0.0, 4.2), Vector3(x1 + 0.4, 2.9, -36.6))
	_mm(bd, body, "concrete", Vector3(x0, 0.0, 4.2), Vector3(x1, 2.9, 4.6))                             # Stirn hinten
	_mm(bd, body, "concrete", Vector3(x0, 0.0, -36.2), Vector3(x1, 2.9, -36.6))                         # Stirn vorn
	_mm(bd, body, "concrete", Vector3(x0 - 0.4, 2.9, 4.6), Vector3(x1 + 0.4, 3.2, -36.6))               # Decke
	# Schachtwaende zwischen Gangboden und Sammlerdecke
	_mm(bd, body, "concrete_dark", Vector3(x0 - 0.2, -1.3, -33.6), Vector3(x0, -0.3, -36.2))
	_mm(bd, body, "concrete_dark", Vector3(x1, -1.3, -33.6), Vector3(x1 + 0.2, -0.3, -36.2))
	_mm(bd, body, "concrete_dark", Vector3(x0, -1.3, -33.4), Vector3(x1, -0.3, -33.6))
	_mm(bd, body, "concrete_dark", Vector3(x0, -1.3, -36.2), Vector3(x1, -0.3, -36.4))
	# Gelbe Kante und Gelaender am Schacht
	bd.box("warn", Vector3(XA, 0.01, -33.45), Vector3(3.0, 0.02, 0.25))
	for sx: float in [-1.0, 1.0]:
		bd.box("metal", Vector3(XA + sx * 1.4, 0.55, -34.8), Vector3(0.05, 1.1, 0.05))
	bd.box("metal", Vector3(XA, 1.05, -34.8 + 1.2), Vector3(0.05, 0.05, 0.05))
	# Rohre links, Kabelpritschen rechts
	for i in 3:
		_pipe(bd, "pipe" if i != 1 else "pipe_red", Vector3(x0 + 0.18, 2.3 - i * 0.28, 4.2), Vector3(x0 + 0.18, 2.3 - i * 0.28, -36.2), 0.09 - i * 0.015)
	for k in 3:
		bd.box("rack", Vector3(x1 - 0.2, 2.2 - k * 0.3, -16.0), Vector3(0.3, 0.03, 40.0))
	# Leuchten: fast alle tot, zwei Notleuchten glimmen
	var lz := 2.0
	var idx := 0
	while lz > -33.0:
		var on := idx == 0 or idx == 3
		bd.box("fluor" if on else "fluor_off", Vector3(XA, 2.85, lz), Vector3(0.18, 0.06, 1.1))
		if on:
			var l := _omni(Vector3(XA, 2.6, lz), Color(1.0, 0.75, 0.5), 0.35, 5.0, 0.4)
			l.set_meta("no_stealth", true)
		lz -= 7.0
		idx += 1
	# Kisten und Spinde im Gang (Voss' Lager)
	bd.box("crate2", Vector3(x1 - 0.5, 0.4, -5.0), Vector3(0.8, 0.8, 1.2))
	bd.box("crate", Vector3(x1 - 0.45, 1.05, -5.2), Vector3(0.7, 0.5, 0.8))
	bd.box("metal", Vector3(x0 + 0.35, 0.95, -12.0), Vector3(0.6, 1.9, 1.6))
	_label("VERSORGUNGSGANG 4 — BT", Vector3(x1 - 0.01, 1.9, -2.0), -90.0, 64, Color(0.85, 0.85, 0.8), 0.008)
	_label("SCHACHT S-7  ▼  SAMMLER TIERGARTEN III", Vector3(XA, 1.8, -36.19), 0.0, 52, Color(0.9, 0.75, 0.2), 0.008)
	_ladder_mesh(bd, Vector3(XA, -4.5, -33.6), 4.6, 180.0)
	# Voss mit Laterne am Einstieg
	_figure(Vector3(XA + 0.8, 0.0, 0.2), 200.0)
	# Sturmlaterne (Poly Haven "Lantern_01", CC0, 1,6-fach = 47 cm) auf dem Boden, Flamme als Leuchtkoerper
	PH.place(self, "lantern_01", PH.xform(Vector3(XA + 1.1, 0.0, -0.6), -20.0, Vector3.ONE * 1.6), -1.0, {"shadows": false})
	add_child(Geo.box_mesh_node(Vector3(0.03, 0.065, 0.03), mats["amber"], Vector3(XA + 1.1, 0.155, -0.6)))
	var lf := _omni(Vector3(XA + 1.1, 0.155, -0.6), Color(1.0, 0.66, 0.32), 1.8, 3.2, 0.0)   # Eigenlicht der Flamme (Glas, Messing)
	lf.set_meta("no_stealth", true)
	var ll := _omni(Vector3(XA + 1.1, 0.6, -0.6), Color(1.0, 0.7, 0.38), 1.6, 7.0, 0.8, true)
	ll.set_meta("no_stealth", true)

## B1: Hauptsammler, Bankette links/rechts, Gerinne in der Mitte. Links eingestuerzt -> durchs Wasser.
func _build_collector(bd: BP.Builder, body: StaticBody3D) -> void:
	var z0 := -28.0
	var z1 := -70.0
	_mm(bd, body, "floor", Vector3(-4.0, Y_WALK - 0.5, z0), Vector3(-1.5, Y_WALK, z1))
	_mm(bd, body, "floor", Vector3(1.5, Y_WALK - 0.5, z0), Vector3(4.0, Y_WALK, z1))
	_mm(bd, body, "sludge", Vector3(-1.5, Y_WET - 0.5, z0), Vector3(1.5, Y_WET, z1))
	bd.box("concrete_dark", Vector3(-1.52, (Y_WALK + Y_WET) * 0.5, (z0 + z1) * 0.5), Vector3(0.06, 0.6, absf(z1 - z0)))
	bd.box("concrete_dark", Vector3(1.52, (Y_WALK + Y_WET) * 0.5, (z0 + z1) * 0.5), Vector3(0.06, 0.6, absf(z1 - z0)))
	for sx: float in [-1.0, 1.0]:
		_mm(bd, body, "brick_wet", Vector3(sx * 4.0, Y_WET, z0), Vector3(sx * 4.4, -0.7, z1))
		# Gewoelbeansatz
		bd.box("brick", Vector3(sx * 3.4, -1.25, (z0 + z1) * 0.5), Vector3(1.6, 0.45, absf(z1 - z0)), Basis(Vector3.BACK, sx * 0.5))
	_mm(bd, body, "brick", Vector3(-4.4, Y_WET, z0), Vector3(4.4, -0.7, z0 + 0.4))                         # Stirn hinten
	# Decke mit Schachtloch (x XA+-1.5, z -33.6..-36.2)
	_mm(bd, body, "brick", Vector3(-4.4, -1.0, z0), Vector3(4.4, -0.7, -33.6))
	_mm(bd, body, "brick", Vector3(-4.4, -1.0, -36.2), Vector3(4.4, -0.7, z1))
	_mm(bd, body, "brick", Vector3(XA + 1.5, -1.0, -33.6), Vector3(4.4, -0.7, -36.2))
	_mm(bd, body, "brick", Vector3(-4.4, -1.0, -33.6), Vector3(XA - 1.5, -0.7, -36.2))
	_water_zone(Vector2(-1.5, z1), Vector2(1.5, z0))
	# Einsturz der linken Bankette (z -51..-55): Schutt bis unter die Decke. Kollision wie bisher (Block),
	# Optik als Schuttkegel mit Ziegeln und Betonbrocken (_collapse_debris)
	Geo.add_box_shape(body, Vector3(-2.8, (Y_WALK - 1.6) * 0.5, -53.0), Vector3(2.4, 2.9, 4.0))
	# Zufallsfolge von rng unveraendert lassen (frueher Props.rubble), Optik verworfen
	var tmp := Node3D.new()
	Props.rubble(tmp, Vector3(-2.6, Y_WALK, -50.4), 1.6, 1.2, rng, false)
	Props.rubble(tmp, Vector3(-1.0, Y_WET, -53.0), 1.3, 0.5, rng, false)
	tmp.free()
	_collapse_debris(bd)
	# Rampen: links hinunter ins Gerinne, rechts wieder hinauf
	_ramp(bd, body, "concrete_dark", Vector3(-1.5, Y_WALK, -48.8), Vector3(0.1, Y_WET, -48.8), 1.8)
	_ramp(bd, body, "concrete_dark", Vector3(1.5, Y_WALK, -57.6), Vector3(-0.1, Y_WET, -57.6), 1.8)
	# Rohre an der rechten Wand, Kabel links
	_pipe(bd, "pipe", Vector3(3.8, -2.0, z0), Vector3(3.8, -2.0, z1), 0.16)
	_pipe(bd, "pipe_red", Vector3(3.85, -2.45, z0), Vector3(3.85, -2.45, z1), 0.08)
	for k in 2:
		bd.box("rack", Vector3(-3.8, -1.9 - k * 0.25, (z0 + z1) * 0.5), Vector3(0.25, 0.03, absf(z1 - z0)))
	# Sprossen in der Wand (Steigeisen) als Detail, Stationszeichen
	_label("SAMMLER TIERGARTEN III", Vector3(-3.99, -2.4, -40.0), 90.0, 70, Color(0.85, 0.85, 0.8), 0.009)
	_label("REICHSTAG  ▲  ACHSE B", Vector3(3.99, -2.6, -62.0), -90.0, 64, Color(0.85, 0.85, 0.8), 0.009)
	_label("WIR SIND NOCH DA", Vector3(3.99, -3.4, -45.0), -90.0, 90, Color(0.8, 0.2, 0.15), 0.01)
	# Notleuchte rot ueber dem Einsturz (glimmt, zaehlt fuer die Sicht der Wachen)
	bd.box("red_glow", Vector3(0.0, -1.1, -60.0), Vector3(0.2, 0.08, 0.2))
	_omni(Vector3(0.0, -1.4, -60.0), Color(1.0, 0.18, 0.1), 0.9, 6.0, 0.6)
	# Endwand zur Pfeilerhalle (z -70..-70.6) mit zwei engen Durchgaengen auf den Banketten
	_wall_with_doors(bd, body, -70.0, -70.6, [Vector2(-3.5, -2.0), Vector2(2.0, 3.5)], -4.4, 4.4, -0.5)
	# Rechen ueber dem Gerinne
	var gx := -1.4
	while gx <= 1.41:
		bd.box("metal", Vector3(gx, -3.6, -69.85), Vector3(0.05, 2.6, 0.05))
		gx += 0.2

## Einsturz im Sammler: Schuttkegel vom Block (x -4..-1.6, z -55..-51, bis unter die Decke) bis auf die
## Bankette, darauf Ziegel/Ziegelbruch/Betonbrocken, Ausrieselung ins Gerinne, ein abgebrochener Balken und
## Bewehrungseisen. Reine Optik; der Weg durchs Gerinne (x > -1.5) bleibt frei begehbar.
func _collapse_debris(bd: BP.Builder) -> void:
	var nz := DK.make_noise(build_seed + 51)
	var cmin := Vector2(-4.0, -54.3)
	var cmax := Vector2(-2.35, -51.7)
	var ytop := -1.35
	DK.heap(self, Vector2(-4.0, -56.4), Vector2(-1.38, -49.6), cmin, cmax, Y_WALK, ytop, 1.05, nz)
	var hf := func(x: float, z: float) -> float:
		return DK.heap_height(x, z, cmin, cmax, Y_WALK, ytop, 1.05, nz)
	var dr := RandomNumberGenerator.new()
	dr.seed = build_seed + 52
	DK.scatter(self, dr, Vector2(-4.0, -56.4), Vector2(-1.4, -49.6), 300, hf, 0.18, 0.55, 0.7)
	# Ausrieselung in die Rinne und auf die Bankette davor (kleine Teile, flach)
	var flat_wet := func(x: float, _z: float) -> float:
		return Y_WET if x > -1.5 else Y_WALK
	DK.scatter(self, dr, Vector2(-1.45, -55.6), Vector2(-0.4, -50.4), 55, flat_wet, 0.1, 0.3, 0.75, false)
	DK.scatter(self, dr, Vector2(-3.9, -50.0), Vector2(-1.6, -48.9), 30, flat_wet, 0.1, 0.25, 0.7, false)
	# abgebrochener Holzbalken und Bewehrungseisen ragen aus dem Kegel
	bd.box("beam", Vector3(-2.2, -3.2, -50.9), Vector3(0.16, 0.18, 2.4), Basis.from_euler(Vector3(0.9, 0.35, 0.2)))
	for i in 5:
		var a := Vector3(-2.7 + i * 0.12, -2.0 - i * 0.18, -51.4 + (i % 2) * 0.3)
		_pipe(bd, "metal", a, a + Vector3(0.5 + 0.1 * i, -0.25 - 0.08 * i, 0.35 - 0.15 * i), 0.008)
	bd.box("concrete_dark", Vector3(-2.0, -1.12, -53.0), Vector3(1.4, 0.24, 3.6), Basis.from_euler(Vector3(0.05, 0.1, -0.25)))

## Wand quer zum Gang mit Durchgaengen (Paare x_von..x_bis), Durchgangshoehe 2.2 m ueber Y_WALK.
func _wall_with_doors(bd: BP.Builder, body: StaticBody3D, za: float, zb: float, doors: Array, xa: float, xb: float, top: float) -> void:
	var x := xa
	for d: Vector2 in doors:
		if d.x > x:
			_mm(bd, body, "brick", Vector3(x, Y_WET, za), Vector3(d.x, top, zb))
		_mm(bd, body, "brick", Vector3(d.x, Y_WALK + 2.2, za), Vector3(d.y, top, zb))
		bd.box("metal", Vector3(d.x - 0.04, Y_WALK + 1.1, (za + zb) * 0.5), Vector3(0.08, 2.2, 0.7))
		bd.box("metal", Vector3(d.y + 0.04, Y_WALK + 1.1, (za + zb) * 0.5), Vector3(0.08, 2.2, 0.7))
		x = d.y
	if xb > x:
		_mm(bd, body, "brick", Vector3(x, Y_WET, za), Vector3(xb, top, zb))

## B2: Pfeilerhalle unter dem Plenarsaal. Trockener Mittelgang, geflutete Becken links/rechts.
func _build_hall(bd: BP.Builder, body: StaticBody3D) -> void:
	var z0 := -70.6
	var z1 := -112.0
	_mm(bd, body, "floor", Vector3(-3.0, Y_WALK - 0.5, z0), Vector3(3.0, Y_WALK, z1))
	_mm(bd, body, "sludge", Vector3(-11.0, Y_WET - 0.5, z0), Vector3(-3.0, Y_WET, z1))
	_mm(bd, body, "sludge", Vector3(3.0, Y_WET - 0.5, z0), Vector3(11.0, Y_WET, z1))
	bd.box("warn", Vector3(-2.95, Y_WALK + 0.01, (z0 + z1) * 0.5), Vector3(0.1, 0.02, absf(z1 - z0)))
	bd.box("warn", Vector3(2.95, Y_WALK + 0.01, (z0 + z1) * 0.5), Vector3(0.1, 0.02, absf(z1 - z0)))
	_water_zone(Vector2(-11.0, z1), Vector2(-3.0, z0))
	_water_zone(Vector2(3.0, z1), Vector2(11.0, z0))
	for sx: float in [-1.0, 1.0]:
		_mm(bd, body, "concrete", Vector3(sx * 11.0, Y_WET, z0), Vector3(sx * 11.4, -0.2, z1))
		_mm(bd, body, "concrete", Vector3(sx * 4.4, Y_WET, -70.0), Vector3(sx * 11.4, -0.2, -70.6))   # Stirn neben dem Sammler
		# Rampen Mittelgang <-> Becken (vorn und hinten)
		_ramp(bd, body, "concrete_dark", Vector3(sx * 3.0, Y_WALK, -74.0), Vector3(sx * 4.9, Y_WET, -74.0), 1.8)
		_ramp(bd, body, "concrete_dark", Vector3(sx * 3.0, Y_WALK, -108.6), Vector3(sx * 4.9, Y_WET, -108.6), 1.8)
	_mm(bd, body, "concrete", Vector3(-11.4, -0.5, z0), Vector3(11.4, -0.2, z1))                       # Decke
	# Rueckwand mit enger Oeffnung in der Mitte
	_mm(bd, body, "concrete", Vector3(-11.4, Y_WET, -112.0), Vector3(-1.2, -0.2, -112.4))
	_mm(bd, body, "concrete", Vector3(1.2, Y_WET, -112.0), Vector3(11.4, -0.2, -112.4))
	_mm(bd, body, "concrete", Vector3(-1.2, Y_WALK + 2.1, -112.0), Vector3(1.2, -0.2, -112.4))
	_mm(bd, body, "floor", Vector3(-1.2, Y_WALK - 0.5, -112.0), Vector3(1.2, Y_WALK, -112.4))
	# Pfeiler (Fundament Achse B) mit Unterzuegen
	for z: float in [-78.0, -86.0, -94.0, -102.0]:
		for x: float in [-7.5, -3.6, 3.6, 7.5]:
			_sbox(bd, body, "concrete", Vector3(x, (Y_WET - 0.2) * 0.5 - 0.1, z), Vector3(1.2, absf(Y_WET) + 0.1, 1.2))
			bd.box("concrete_dark", Vector3(x, Y_WET + 0.35, z), Vector3(1.32, 0.7, 1.32))
		bd.box("concrete_dark", Vector3(0.0, -0.75, z), Vector3(22.0, 0.5, 0.7))
	_label("FUNDAMENT ACHSE B", Vector3(0.0, -1.2, -77.6), 180.0, 70, Color(0.85, 0.85, 0.8), 0.009)
	_label("PFEILER B4", Vector3(3.6, -2.0, -93.39), 0.0, 48, Color(0.85, 0.85, 0.8), 0.008)
	# Notleuchte in der Hallenmitte (schwach), Arbeitslampe der Garde im rechten Becken
	bd.box("red_glow", Vector3(0.0, -1.05, -90.0), Vector3(0.2, 0.08, 0.2))
	_omni(Vector3(0.0, -1.3, -90.0), Color(1.0, 0.2, 0.1), 0.7, 7.0, 0.6)
	_work_lamp(Vector3(8.8, Y_WET, -98.0), -60.0)
	# Gardekisten auf dem Mittelgang (Deckung)
	bd.box("crate", Vector3(-2.2, Y_WALK + 0.4, -83.0), Vector3(0.9, 0.8, 1.2))
	bd.box("crate", Vector3(2.3, Y_WALK + 0.4, -98.5), Vector3(0.9, 0.8, 1.4))
	bd.box("crate2", Vector3(2.3, Y_WALK + 1.05, -98.3), Vector3(0.7, 0.5, 0.8))
	Geo.add_box_shape(body, Vector3(-2.2, Y_WALK + 0.4, -83.0), Vector3(0.9, 0.8, 1.2))
	Geo.add_box_shape(body, Vector3(2.3, Y_WALK + 0.65, -98.5), Vector3(0.9, 1.3, 1.4))
	# Kabeltrommeln und Zuendleitung entlang des Mittelgangs
	bd.box("wire", Vector3(-2.85, Y_WALK + 0.03, -90.0), Vector3(0.03, 0.03, 26.0))

## B3: enger Ziegelkanal, Bankett rechts.
func _build_brick_channel(bd: BP.Builder, body: StaticBody3D) -> void:
	var z0 := -112.4
	var z1 := -140.0
	_mm(bd, body, "floor", Vector3(0.3, Y_WALK - 0.5, z0), Vector3(2.5, Y_WALK, z1))
	_mm(bd, body, "sludge", Vector3(-2.5, Y_WET - 0.5, z0), Vector3(0.3, Y_WET, z1))
	_mm(bd, body, "floor", Vector3(-1.2, Y_WALK - 0.5, z0), Vector3(0.3, Y_WALK, z0 - 1.2))           # Absatz am Eingang
	bd.box("concrete_dark", Vector3(0.28, (Y_WALK + Y_WET) * 0.5, (z0 + z1) * 0.5), Vector3(0.06, 0.6, absf(z1 - z0)))
	_water_zone(Vector2(-2.5, z1), Vector2(0.3, z0 - 1.2))
	for sx: float in [-1.0, 1.0]:
		_mm(bd, body, "brick_wet", Vector3(sx * 2.5, Y_WET, z0), Vector3(sx * 2.9, -1.6, z1))
		bd.box("brick", Vector3(sx * 2.1, -1.95, (z0 + z1) * 0.5), Vector3(1.1, 0.35, absf(z1 - z0)), Basis(Vector3.BACK, sx * 0.55))
	_mm(bd, body, "brick", Vector3(-2.9, -1.7, z0), Vector3(2.9, -1.4, z1))
	_ramp(bd, body, "concrete_dark", Vector3(0.3, Y_WALK, -128.0), Vector3(-1.2, Y_WET, -128.0), 1.4)
	_pipe(bd, "pipe", Vector3(2.3, -2.3, z0), Vector3(2.3, -2.3, z1), 0.14)
	_label("ÜBERLAUF  ▶", Vector3(2.49, -3.0, -132.0), -90.0, 56, Color(0.85, 0.85, 0.8), 0.008)
	_label("FREIHEIT", Vector3(-2.49, -3.2, -122.0), 90.0, 110, Color(0.8, 0.2, 0.15), 0.011)
	bd.box("red_glow", Vector3(1.4, -1.45, -126.0), Vector3(0.18, 0.06, 0.18))
	_omni(Vector3(1.4, -1.7, -126.0), Color(1.0, 0.2, 0.1), 0.5, 5.0, 0.5)

## B4: Ueberlaufkammer, von der Garde als Depot genutzt (Generator, Kisten, Arbeitslicht).
func _build_depot(bd: BP.Builder, body: StaticBody3D) -> void:
	var z0 := -140.0
	var z1 := -172.0
	_mm(bd, body, "floor", Vector3(-6.0, Y_WALK - 0.5, z0), Vector3(9.0, Y_WALK, z1))
	_mm(bd, body, "sludge", Vector3(-9.0, Y_WET - 0.5, z0), Vector3(-6.0, Y_WET, z1))
	_water_zone(Vector2(-9.0, z1), Vector2(-6.0, z0))
	_ramp(bd, body, "concrete_dark", Vector3(-6.0, Y_WALK, -168.0), Vector3(-7.6, Y_WET, -168.0), 1.6)
	_ramp(bd, body, "concrete_dark", Vector3(-6.0, Y_WALK, -144.0), Vector3(-7.6, Y_WET, -144.0), 1.6)
	for sx: float in [-1.0, 1.0]:
		_mm(bd, body, "concrete", Vector3(sx * 9.0, Y_WET, z0), Vector3(sx * 9.4, -0.6, z1))
	_mm(bd, body, "concrete", Vector3(-9.4, -0.9, z0), Vector3(9.4, -0.6, z1))
	# Stirnwand mit Kanalprofil
	_mm(bd, body, "concrete", Vector3(-9.4, Y_WET, -139.6), Vector3(-2.5, -0.6, -140.0))
	_mm(bd, body, "concrete", Vector3(2.5, Y_WET, -139.6), Vector3(9.4, -0.6, -140.0))
	_mm(bd, body, "concrete", Vector3(-2.5, -1.6, -139.6), Vector3(2.5, -0.6, -140.0))
	_mm(bd, body, "concrete_dark", Vector3(-2.5, Y_WET, -140.0), Vector3(0.3, Y_WALK, -140.3))
	# Rueckwand mit Durchgang zum Steigschacht
	_mm(bd, body, "concrete", Vector3(-9.4, Y_WET, -172.0), Vector3(-1.5, -0.6, -172.4))
	_mm(bd, body, "concrete", Vector3(1.5, Y_WET, -172.0), Vector3(9.4, -0.6, -172.4))
	_mm(bd, body, "concrete", Vector3(-1.5, Y_WALK + 2.2, -172.0), Vector3(1.5, -0.6, -172.4))
	# Kistenstapel (Deckung), Tische, Generator
	var stacks: Array = [
		[Vector3(-3.6, 0, -149.0), Vector3(1.4, 1.2, 1.4)], [Vector3(-3.4, 0, -150.6), Vector3(1.2, 0.8, 1.2)],
		[Vector3(1.5, 0, -156.0), Vector3(2.4, 1.0, 1.2)], [Vector3(-1.0, 0, -162.5), Vector3(1.2, 1.4, 1.2)],
		[Vector3(6.5, 0, -162.0), Vector3(1.4, 1.6, 2.6)], [Vector3(-4.2, 0, -166.0), Vector3(1.6, 0.9, 1.0)],
		[Vector3(4.5, 0, -144.0), Vector3(1.2, 1.2, 1.2)],
	]
	for i in stacks.size():
		var p: Vector3 = stacks[i][0]
		var s: Vector3 = stacks[i][1]
		_sbox(bd, body, "crate" if i % 2 == 0 else "crate2", Vector3(p.x, Y_WALK + s.y * 0.5, p.z), s)
	_sbox(bd, body, "metal", Vector3(5.6, Y_WALK + 0.55, -151.0), Vector3(1.8, 1.1, 1.0))           # Generator
	bd.box("rack", Vector3(5.6, Y_WALK + 1.2, -151.0), Vector3(0.3, 0.2, 0.3))
	_sbox(bd, body, "crate2", Vector3(2.0, Y_WALK + 0.4, -146.5), Vector3(1.8, 0.8, 0.9))           # Tisch
	_work_lamp(Vector3(4.2, Y_WALK, -149.6), 150.0)
	_label("RÜB 3 — ÜBERLAUFKAMMER", Vector3(8.99, -2.4, -156.0), -90.0, 64, Color(0.85, 0.85, 0.8), 0.009)
	_label("STEIGSCHACHT K  ▲", Vector3(0.0, Y_WALK + 2.5, -171.99), 0.0, 56, Color(0.9, 0.75, 0.2), 0.008)

## Ende: Gang zum Steigschacht, Leiter hoch in den Versorgungskeller des Kanzleramts (y = 0).
func _build_exit(bd: BP.Builder, body: StaticBody3D) -> void:
	_mm(bd, body, "floor", Vector3(-1.7, Y_WALK - 0.5, -172.4), Vector3(1.7, Y_WALK, -180.6))
	for sx: float in [-1.0, 1.0]:
		_mm(bd, body, "concrete_dark", Vector3(sx * 1.5, Y_WALK, -172.4), Vector3(sx * 1.9, -0.3, -180.6))
	_mm(bd, body, "concrete_dark", Vector3(-1.9, Y_WALK, -180.2), Vector3(1.9, -0.3, -180.6))
	_mm(bd, body, "concrete_dark", Vector3(-1.9, -2.0, -172.4), Vector3(1.9, -1.7, -176.0))           # Gangdecke
	_ladder_mesh(bd, Vector3(0.0, Y_WALK, -180.2), 4.7, 0.0)
	# Versorgungskeller oben
	var xa := -4.0
	var xb := 4.0
	var za := -173.6
	var zb := -192.0
	_mm(bd, body, "lino", Vector3(xa, -0.3, za), Vector3(xb, 0.0, -176.0))
	_mm(bd, body, "lino", Vector3(xa, -0.3, -176.0), Vector3(-1.5, 0.0, -180.2))
	_mm(bd, body, "lino", Vector3(1.5, -0.3, -176.0), Vector3(xb, 0.0, -180.2))
	_mm(bd, body, "lino", Vector3(xa, -0.3, -180.2), Vector3(xb, 0.0, zb))
	_mm(bd, body, "plaster", Vector3(xa - 0.3, -0.3, za), Vector3(xa, 3.0, zb))
	_mm(bd, body, "plaster", Vector3(xb, -0.3, za), Vector3(xb + 0.3, 3.0, zb))
	_mm(bd, body, "plaster", Vector3(xa, -0.3, za), Vector3(xb, 3.0, za + 0.3))
	_mm(bd, body, "plaster", Vector3(xa, -0.3, zb), Vector3(xb, 3.0, zb - 0.3))
	_mm(bd, body, "plaster", Vector3(xa - 0.3, 3.0, za), Vector3(xb + 0.3, 3.3, zb - 0.3))
	bd.box("warn", Vector3(0.0, 0.01, -180.35), Vector3(3.0, 0.02, 0.2))
	for i in 3:
		_pipe(bd, "pipe", Vector3(xa + 0.2, 2.5 - i * 0.3, za), Vector3(xa + 0.2, 2.5 - i * 0.3, zb), 0.1)
	bd.box("metal", Vector3(0.0, 1.1, zb + 0.05), Vector3(1.2, 2.2, 0.1))                             # Tuer
	bd.box("exit_green", Vector3(0.0, 2.45, zb + 0.12), Vector3(0.5, 0.18, 0.04))
	_label("BUNDESKANZLERAMT · VERSORGUNG UG 2", Vector3(0.0, 2.75, zb + 0.32), 0.0, 52, Color(0.85, 0.85, 0.8), 0.005)
	bd.box("fluor", Vector3(0.0, 2.95, -184.0), Vector3(0.18, 0.06, 1.2))
	var l := _omni(Vector3(0.0, 2.6, -184.0), Color(0.9, 0.95, 1.0), 0.8, 7.0, 0.3)
	l.set_meta("no_stealth", true)
	_cellar_detail(bd, xa, xb, za, zb)

## Versorgungskeller ausstatten (reine Optik, keine neue Kollision; Leiterloch x +-1.5 / z -176..-180.2 und
## der Weg zur Tuer bleiben frei): Oelfarbensockel, Heizungsrohre mit Flanschen, Schellen, Daemmung,
## Absperrschieber und Manometer, Steigleitung, Lueftungskanal, Kabelpritsche, Verteilerkaesten, Hauptverteilung,
## Stahlregal, Werkzeugkiste, Faesser und Zementsaecke (Poly Haven, CC0).
func _cellar_detail(bd: BP.Builder, xa: float, xb: float, za: float, zb: float) -> void:
	var zc := (za + zb) * 0.5
	var zl := absf(za - zb)
	# Sockel (1,4 m) in gruener Oelfarbe, Trennstrich
	bd.box("plaster_sockel", Vector3(xa + 0.01, 0.7, zc), Vector3(0.02, 1.4, zl))
	bd.box("plaster_sockel", Vector3(xb - 0.01, 0.7, zc), Vector3(0.02, 1.4, zl))
	bd.box("plaster_sockel", Vector3(0.0, 0.7, za - 0.01), Vector3(xb - xa, 1.4, 0.02))
	bd.box("plaster_sockel", Vector3(0.0, 0.7, zb + 0.01), Vector3(xb - xa, 1.4, 0.02))
	for x: float in [xa + 0.022, xb - 0.022]:
		bd.box("rack", Vector3(x, 1.41, zc), Vector3(0.006, 0.02, zl))
	# Heizungsrohre an der Westwand: Schellen an Konsolen, Flansche, Daemmung mit Blechbaendern
	var zr := Basis(Vector3.RIGHT, PI * 0.5)
	var z := za - 0.6
	while z > zb + 0.3:
		bd.box("metal", Vector3(xa + 0.12, 2.2, z), Vector3(0.05, 0.9, 0.06))
		for i in 3:
			bd.box("metal", Vector3(xa + 0.17, 2.5 - i * 0.3, z), Vector3(0.1, 0.03, 0.05))
		z -= 2.4
	z = za - 1.6
	while z > zb + 0.5:
		for i in 3:
			bd.cyl("band", Vector3(xa + 0.2, 2.5 - i * 0.3, z), 0.14, 0.14, 0.05, 12, zr)
		z -= 3.1
	bd.cyl("insul", Vector3(xa + 0.2, 2.2, -179.5), 0.155, 0.155, 9.0, 12, zr)
	for k in 7:
		bd.cyl("band", Vector3(xa + 0.2, 2.2, -175.3 - k * 1.4), 0.158, 0.158, 0.03, 12, zr)
	_label("HEIZUNG  VL  ▶", Vector3(xa + 0.33, 2.5, -186.5), 90.0, 26, Color(0.85, 0.85, 0.8), 0.004)
	_label("◀  RL", Vector3(xa + 0.33, 1.9, -186.5), 90.0, 26, Color(0.85, 0.85, 0.8), 0.004)
	# Abgang mit Absperrschieber (Handrad) und Manometer
	_pipe(bd, "pipe_red", Vector3(xa + 0.2, 1.9, -185.2), Vector3(xa + 0.2, 0.25, -185.2), 0.06)
	bd.cyl("band", Vector3(xa + 0.2, 1.05, -185.2), 0.085, 0.085, 0.22, 12)
	bd.box("metal", Vector3(xa + 0.2, 1.05, -185.2), Vector3(0.16, 0.14, 0.2))
	_pipe(bd, "band", Vector3(xa + 0.28, 1.05, -185.2), Vector3(xa + 0.48, 1.05, -185.2), 0.012)
	bd.cyl("wheel_red", Vector3(xa + 0.48, 1.05, -185.2), 0.13, 0.13, 0.025, 16, Basis(Vector3.BACK, PI * 0.5))
	bd.cyl("wheel_red", Vector3(xa + 0.49, 1.05, -185.2), 0.02, 0.02, 0.05, 8, Basis(Vector3.BACK, PI * 0.5))
	_pipe(bd, "band", Vector3(xa + 0.2, 1.55, -185.2), Vector3(xa + 0.33, 1.55, -185.2), 0.008)
	bd.cyl("rack", Vector3(xa + 0.35, 1.55, -185.2), 0.055, 0.055, 0.03, 16, Basis(Vector3.BACK, PI * 0.5))
	bd.cyl("gauge", Vector3(xa + 0.366, 1.55, -185.2), 0.046, 0.046, 0.005, 16, Basis(Vector3.BACK, PI * 0.5))
	bd.box("pipe_red", Vector3(xa + 0.2, 0.12, -185.2), Vector3(0.22, 0.24, 0.22))
	# Steigleitung in der Nordwestecke mit Schieber
	_pipe(bd, "pipe", Vector3(xa + 0.6, 0.0, za - 0.2), Vector3(xa + 0.6, 3.0, za - 0.2), 0.08)
	bd.cyl("band", Vector3(xa + 0.6, 1.3, za - 0.2), 0.12, 0.12, 0.05, 12)
	bd.cyl("band", Vector3(xa + 0.6, 1.5, za - 0.2), 0.12, 0.12, 0.05, 12)
	bd.cyl("wheel_red", Vector3(xa + 0.6, 1.4, za - 0.42), 0.11, 0.11, 0.02, 16, zr)
	# Lueftungskanal (verzinkt) unter der Decke mit Abhaengern und Gitter
	# endet 1 m vor der Stirnwand und knickt in die Decke; nah an der Ostwand, damit er das Schild ueber der Tuer nicht verdeckt
	bd.box("galv", Vector3(3.0, 2.72, (za + zb + 1.0) * 0.5), Vector3(0.6, 0.36, zl - 1.0))
	bd.box("galv", Vector3(3.0, 2.95, zb + 1.25), Vector3(0.6, 0.1, 0.5))
	bd.box("band", Vector3(3.0, 2.72, zb + 1.015), Vector3(0.63, 0.39, 0.03))
	z = za - 1.0
	while z > zb + 1.5:
		bd.box("band", Vector3(3.0, 2.72, z), Vector3(0.63, 0.39, 0.03))
		for sx: float in [-0.33, 0.33]:
			bd.box("metal", Vector3(3.0 + sx, 2.95, z), Vector3(0.012, 0.1, 0.012))
		z -= 2.2
	bd.box("rack", Vector3(2.69, 2.72, -186.0), Vector3(0.02, 0.22, 0.5))
	for k in 6:
		bd.box("band", Vector3(2.68, 2.63 + k * 0.035, -186.0), Vector3(0.012, 0.012, 0.48))
	_label("LÜFTUNG  ZU 2", Vector3(2.68, 2.72, -183.0), -90.0, 24, Color(0.15, 0.15, 0.15), 0.004)
	# Kabelpritsche an der Ostwand mit Kabeln, Verteilerkaesten mit Kabelrohren
	bd.box("galv", Vector3(xb - 0.2, 2.62, zc), Vector3(0.3, 0.05, zl))
	for k in 5:
		_pipe(bd, "rack", Vector3(xb - 0.32 + k * 0.05, 2.665, za), Vector3(xb - 0.32 + k * 0.05, 2.665, zb), 0.014)
	for zz: float in [-183.2, -184.6]:
		if FK.place(self, "res://assets/environment/river/models/utility_box_01", Vector3(xb - 0.13, 1.5, zz), Vector3(0.22, 0.62, 0.46), -90.0):
			_pipe(bd, "band", Vector3(xb - 0.08, 1.82, zz), Vector3(xb - 0.08, 2.6, zz), 0.02)
	# Hauptverteilung (Standschrank) an der Ostwand
	var hz := -188.6
	bd.box("cab_grey", Vector3(xb - 0.2, 1.0, hz), Vector3(0.4, 2.0, 1.2))
	bd.box("rack", Vector3(xb - 0.2, 0.05, hz), Vector3(0.36, 0.1, 1.16))
	bd.box("rack", Vector3(xb - 0.405, 1.05, hz), Vector3(0.01, 1.85, 0.008))
	for sz: float in [-0.08, 0.08]:
		bd.box("band", Vector3(xb - 0.415, 1.1, hz + sz), Vector3(0.025, 0.14, 0.03))
	bd.box("warn", Vector3(xb - 0.403, 1.6, hz - 0.3), Vector3(0.005, 0.16, 0.18))
	_label("HV  UG 2\n400 V", Vector3(xb - 0.408, 1.75, hz + 0.25), -90.0, 26, Color(0.9, 0.9, 0.85), 0.004)
	_pipe(bd, "band", Vector3(xb - 0.2, 2.0, hz), Vector3(xb - 0.2, 2.6, hz), 0.05)
	# Stahlregal mit Kartons, Werkzeugkiste (Nordostecke, ausserhalb des Leiterlochs)
	FK.place(self, RL_MOD + "steel_frame_shelves_02", Vector3(xb - 0.3, 0.95, -175.4), Vector3(0.5, 1.9, 1.5), -90.0)
	for k in 3:
		FK.place(self, "res://assets/environment/street/models/cardboard_box_01", Vector3(xb - 0.32, 0.17 + k * 0.0, -174.9 - k * 0.45), Vector3(0.4, 0.3, 0.4), -90.0 + k * 9.0)
	FK.place(self, RL_MOD + "metal_tool_chest", Vector3(xb - 0.3, 0.2, -177.4), Vector3(0.4, 0.4, 0.8), -90.0)
	# Faesser und Zementsaecke in den Westecken
	FK.place(self, "res://assets/environment/river/models/Barrel_01", Vector3(xa + 0.45, 0.45, -189.9), Vector3(0.6, 0.9, 0.6), 20.0)
	FK.place(self, "res://assets/environment/river/models/Barrel_01", Vector3(xa + 1.1, 0.45, -190.6), Vector3(0.6, 0.9, 0.6), -35.0)
	for k in 3:
		FK.place(self, "res://assets/environment/river/models/cement_bag", Vector3(xa + 0.5, 0.07 + k * 0.13, -175.2 - (k % 2) * 0.1), Vector3(0.45, 0.14, 0.7), 5.0 + k * 11.0)
	if ResourceLoader.exists("res://assets/environment/interior/models/fire_extinguisher_de/fire_extinguisher_de.gltf"):
		FK.place(self, "res://assets/environment/interior/models/fire_extinguisher_de", Vector3(1.25, 0.65, zb + 0.15), Vector3(0.2, 0.62, 0.2), 0.0)
	# zweite Leuchte (tot) und schwaches Notlicht ueber der Hauptverteilung (ohne Einfluss aufs Schleichen)
	bd.box("fluor_off", Vector3(0.0, 2.95, -177.0), Vector3(0.18, 0.06, 1.2))
	var nl := _omni(Vector3(2.6, 2.4, -188.6), Color(1.0, 0.86, 0.66), 0.35, 4.5, 0.2)
	nl.set_meta("no_stealth", true)

## Leiter an einer Wand: Fuss bei foot, Hoehe h, Blickrichtung (yaw) der Wand, an der sie haengt.
func _ladder_mesh(bd: BP.Builder, foot: Vector3, h: float, yaw: float) -> void:
	var b := Basis(Vector3.UP, deg_to_rad(yaw))
	var off := b * Vector3(0, 0, 0.12)
	for sx: float in [-0.24, 0.24]:
		bd.box("ladder", foot + b * Vector3(sx, h * 0.5, 0.0) + off, Vector3(0.05, h, 0.05), b)
	var y := 0.3
	while y < h:
		bd.box("ladder", foot + b * Vector3(0, y, 0.0) + off, Vector3(0.5, 0.035, 0.035), b)
		y += 0.32

func _work_lamp(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	for a: float in [0.0, 120.0, 240.0]:
		var leg := Geo.box_mesh_node(Vector3(0.03, 1.7, 0.03), mats["metal"], Vector3(0, 0.82, 0), Vector3(0, a, 12.0))
		root.add_child(leg)
	root.add_child(Geo.box_mesh_node(Vector3(0.36, 0.26, 0.14), mats["rack"], Vector3(0, 1.75, 0)))
	root.add_child(Geo.box_mesh_node(Vector3(0.3, 0.2, 0.02), mats["amber"], Vector3(0, 1.75, -0.08)))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.6)
	l.light_energy = 2.2
	l.omni_range = 9.0
	l.light_volumetric_fog_energy = 0.8
	l.shadow_enabled = true
	l.position = Vector3(0, 1.75, -0.4)
	root.add_child(l)

func _figure(pos: Vector3, yaw: float) -> void:
	# Konrad Voss als MakeHuman-Figur; Kastenfigur nur, falls das Modell fehlt
	if CivFigure.stand(self, "voss", pos, yaw) != null:
		return
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	var cm: Material = mats["coat"]
	for sx: float in [-0.12, 0.12]:
		root.add_child(Geo.box_mesh_node(Vector3(0.16, 0.86, 0.18), mats["rack"], Vector3(sx, 0.43, 0)))
	root.add_child(Geo.box_mesh_node(Vector3(0.5, 0.66, 0.28), cm, Vector3(0, 1.2, 0)))
	for sx: float in [-0.31, 0.31]:
		root.add_child(Geo.box_mesh_node(Vector3(0.13, 0.6, 0.14), cm, Vector3(sx, 1.17, 0.02)))
	root.add_child(Geo.box_mesh_node(Vector3(0.2, 0.24, 0.22), mats["skin"], Vector3(0, 1.66, 0)))
	root.add_child(Geo.box_mesh_node(Vector3(0.23, 0.08, 0.25), mats["rack"], Vector3(0, 1.8, 0)))
	var sb := StaticBody3D.new()
	Geo.add_box_shape(sb, Vector3(0, 0.9, 0), Vector3(0.6, 1.8, 0.4))
	root.add_child(sb)

# ------------------------------------------------------------------ Wasser

func _water_zone(a: Vector2, b: Vector2) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	_water.append({"min": lo, "max": hi, "y": Y_WATER})
	var pm := PlaneMesh.new()
	pm.size = hi - lo
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.material_override = mats["water"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3((lo.x + hi.x) * 0.5, Y_WATER, (lo.y + hi.y) * 0.5)
	add_child(mi)

func _water_at(p: Vector3) -> bool:
	for w: Dictionary in _water:
		var lo: Vector2 = w["min"]
		var hi: Vector2 = w["max"]
		if p.x > lo.x and p.x < hi.x and p.z > lo.y and p.z < hi.y and p.y < float(w["y"]) + 0.05:
			return true
	return false

func _update_water(pl: Player, delta: float) -> void:
	var wet := _water_at(pl.global_position) and pl.is_alive()
	if wet != _in_water:
		_in_water = wet
		if wet:
			_sfx_at("land", pl.global_position, -6.0)
	director.set("in_water", _in_water)
	if _base_speed.size() == 3:
		var k := 1.0
		var ks := 1.0
		if _in_water:
			k = 0.55
			ks = 0.5
		if _defuse_lock:
			k = 0.0
			ks = 0.0
		pl.walk_speed = _base_speed[0] * k
		pl.sprint_speed = _base_speed[1] * ks
		pl.crouch_speed = _base_speed[2] * (0.7 if _in_water and not _defuse_lock else k)
	# Platschen beim Waten
	if _in_water:
		var v := Vector2(pl.velocity.x, pl.velocity.z).length()
		if v > 0.5:
			_splash_t -= delta * v
			if _splash_t <= 0.0:
				_splash_t = 1.15
				var snd := "kanalisation_wade" if not Sfx.get_variants("kanalisation_wade").is_empty() else "footstep"
				_sfx_at(snd, pl.global_position + Vector3(0, 0.1, 0), -4.0 if pl.is_crouching else 0.0)

# ------------------------------------------------------------------ Leitern

## Leiter-Zonen: unten hinein = hochklettern, oben hinein = hinunter (ueber die Kletter-Bewegung des Spielers).
func _add_ladder(lname: String, bottom_zone: AABB, top_zone: AABB, up_to: Vector3, down_to: Vector3) -> void:
	var lad := {"up_to": up_to, "down_to": down_to}
	_ladders.append(lad)
	if bottom_zone.size != Vector3.ZERO:
		_trigger(lname + "Unten", bottom_zone.get_center(), bottom_zone.size, func() -> void: _climb(up_to, true), false)
	if top_zone.size != Vector3.ZERO:
		_trigger(lname + "Oben", top_zone.get_center(), top_zone.size, func() -> void: _climb(down_to, false), false)

func _climb(to: Vector3, up: bool) -> void:
	var pl := _player()
	if pl == null or _climbing or _climb_cd > 0.0 or not pl.is_alive():
		return
	_climbing = true
	var from := pl.global_position
	var dur := clampf(absf(to.y - from.y) * (0.36 if up else 0.24), 0.8, 2.2)
	pl.velocity = Vector3.ZERO
	pl.set("_mantle_from", from)
	pl.set("_mantle_to", to)
	pl.set("_mantle_dur", dur)
	pl.set("_mantle_t", 0.0)
	pl.set("_mantling", true)
	pl.play_sfx("player_mantle", 0.05)
	_later(dur + 0.05, func() -> void:
		_climbing = false
		_climb_cd = 0.6)

# ------------------------------------------------------------------ Sprengladungen

func _build_charge(pillar: Vector3, side: float, laser_z: float) -> void:
	var cpos := Vector3(pillar.x + side * 0.66, Y_WALK + 0.9, pillar.z)
	var root := Node3D.new()
	root.name = "Ladung%d" % _charges.size()
	root.position = cpos
	add_child(root)
	root.add_child(Geo.box_mesh_node(Vector3(0.12, 0.5, 0.36), mats["charge"], Vector3.ZERO))
	root.add_child(Geo.box_mesh_node(Vector3(0.13, 0.08, 0.38), mats["rack"], Vector3(0, 0.12, 0)))
	root.add_child(Geo.box_mesh_node(Vector3(0.13, 0.08, 0.38), mats["rack"], Vector3(0, -0.12, 0)))
	root.add_child(Geo.box_mesh_node(Vector3(0.04, 0.6, 0.02), mats["wire"], Vector3(side * 0.05, -0.5, 0.1)))
	var led := Geo.box_mesh_node(Vector3(0.03, 0.04, 0.04), mats["led_r"], Vector3(side * 0.07, 0.2, 0.1))
	root.add_child(led)
	var led_l := OmniLight3D.new()
	led_l.light_color = Color(1.0, 0.1, 0.05)
	led_l.light_energy = 0.25
	led_l.omni_range = 1.4
	led_l.position = Vector3(side * 0.15, 0.2, 0.1)
	led_l.set_meta("no_stealth", true)
	root.add_child(led_l)
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.font_size = 40
	lbl.pixel_size = 0.004
	lbl.outline_size = 8
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	lbl.modulate = Color(1.0, 0.85, 0.4)
	lbl.shaded = false
	lbl.position = Vector3(side * 0.4, 0.45, 0)
	lbl.visible = false
	root.add_child(lbl)
	# Lichtschranken quer ueber den Mittelgang (zwei Strahlen), Ausloeser nur fuer den Spieler
	var beams: Array[Node3D] = []
	for h: float in [0.42, 1.05]:
		var bm := Geo.box_mesh_node(Vector3(6.0, 0.012, 0.012), mats["laser"], Vector3(0.0, Y_WALK + h, laser_z))
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(bm)
		beams.append(bm)
		for sx: float in [-1.0, 1.0]:
			add_child(Geo.box_mesh_node(Vector3(0.06, 0.1, 0.06), mats["rack"], Vector3(sx * 2.98, Y_WALK + h, laser_z)))
	var idx := _charges.size()
	var area := _trigger("Lichtschranke%d" % idx, Vector3(0.0, Y_WALK + 0.8, laser_z), Vector3(6.0, 1.5, 0.2), func() -> void: _trip(idx), false)
	_charges.append({"root": root, "pos": cpos, "led": led, "led_light": led_l, "label": lbl, "beams": beams,
		"area": area, "laser_z": laser_z, "armed": true, "progress": 0.0, "blown": false})

func _trip(idx: int) -> void:
	var c: Dictionary = _charges[idx]
	if not bool(c["armed"]):
		return
	c["armed"] = false
	c["blown"] = true
	var pos: Vector3 = c["pos"]
	(c["root"] as Node3D).visible = false
	for b: Node3D in c["beams"]:
		b.visible = false
	Combat.explode(pos, 5.5, 85.0, self, 1.2)
	director.call("raise_alarm", pos, "shot", false)
	_update_charge_objective()
	# Falk reagiert, Voss antwortet direkt (Gespraech im selben Frame)
	_later(1.4, func() -> void:
		_say_once_opt("blown", StoryData.FALK, "Da unten hat es geknallt. Alle Streifen zur Achse B – ich will ihn, lebend oder in Stücken.",
			{"priority": 1, "max_age": 3.0})
		_say_once_opt("blown_voss", StoryData.VOSS, "Das war nur eine. Hängen die anderen auch noch dran, kommt die halbe Halle runter. Vorsicht an den Lichtschranken.",
			{"max_age": 3.0, "valid": func() -> bool: return _defused + _blown_count() < _charges.size()}))

func _defuse(idx: int) -> void:
	var c: Dictionary = _charges[idx]
	c["armed"] = false
	(c["label"] as Label3D).visible = false
	(c["led"] as MeshInstance3D).material_override = mats["led_g"]
	(c["led_light"] as OmniLight3D).light_color = Color(0.1, 1.0, 0.2)
	for b: Node3D in c["beams"]:
		b.visible = false
	_sfx_at("kanalisation_defuse" if not Sfx.get_variants("kanalisation_defuse").is_empty() else "pistol_mag_out", pos_of(c), -2.0)
	_defused += 1
	_update_charge_objective()
	match _defused:
		1:
			_say_once_opt("def1", StoryData.LENA, "Grüne Lampe – die ist tot. Noch zwei, Jonas.", {"priority": 1, "max_age": 3.0, "key": "kan_def"})
		2:
			_say_once_opt("def2", StoryData.VOSS, "Sauber. Ich hab früher so was gebaut, nicht entschärft. Du machst das besser als ich.", {"priority": 1, "max_age": 3.0, "key": "kan_def"})
		3:
			_say_once_opt("def3", StoryData.KERNER, "Letzte Ladung ist kalt. Die Halle bleibt stehen.", {"priority": 1, "max_age": 3.0, "key": "kan_def"})

func _blown_count() -> int:
	var n := 0
	for c: Dictionary in _charges:
		if bool(c.get("blown", false)):
			n += 1
	return n

func pos_of(c: Dictionary) -> Vector3:
	return c["pos"]

func _update_charge_objective() -> void:
	var open := 0
	for c: Dictionary in _charges:
		if bool(c["armed"]):
			open += 1
	if open > 0:
		_obj("Ladungen an den Pfeilern entschärfen (E halten) oder durchs Becken umgehen – %d/%d entschärft" % [_defused, _charges.size()])
	else:
		_obj("Weiter zum Steigschacht unter dem Kanzleramt")

func _update_charges(pl: Player, delta: float) -> void:
	var held := Input.is_action_pressed("interact") if InputMap.has_action("interact") else false
	var pp := pl.global_position
	_defuse_lock = false
	for i in _charges.size():
		var c: Dictionary = _charges[i]
		var lbl := c["label"] as Label3D
		if not bool(c["armed"]):
			continue
		var cp: Vector3 = c["pos"]
		var d := Vector2(pp.x - cp.x, pp.z - cp.z).length()
		var near := d < 2.0 and absf(pp.y - Y_WALK) < 1.2 and pl.is_alive()
		var auto := false
		if _bot and pl.is_alive() and d < 3.2 and pp.z > float(c["laser_z"]) + 0.35 and absf(pp.y - Y_WALK) < 1.2:
			auto = true
		lbl.visible = near or float(c["progress"]) > 0.0
		if (near and held) or auto:
			c["progress"] = float(c["progress"]) + delta
			if auto:
				_defuse_lock = true
			var pct := clampf(float(c["progress"]) / DEFUSE_TIME, 0.0, 1.0)
			lbl.text = "Entschärfe … %d%%" % int(pct * 100.0)
			if pct >= 1.0:
				_defuse(i)
				_defuse_lock = false
		else:
			c["progress"] = maxf(0.0, float(c["progress"]) - delta * 2.0)
			lbl.text = "[%s] halten: Ladung entschärfen" % _key("interact")
		# LED blinkt
		var led := c["led"] as MeshInstance3D
		led.visible = fmod(_t, 1.0) < 0.15 or float(c["progress"]) > 0.0

func _key(action: String) -> String:
	if not InputMap.has_action(action):
		return "E"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return "E"

# ------------------------------------------------------------------ Requisiten, Marker

func _build_props() -> void:
	# Schutt, Pfuetzen-Treibgut, Ratten-Nester: dezente Details
	var prng := RandomNumberGenerator.new()
	prng.seed = build_seed + 7
	for i in 10:
		var z := prng.randf_range(-30.0, -68.0)
		var x := prng.randf_range(1.8, 3.6) if i % 2 == 0 else prng.randf_range(-3.6, -1.8)
		if z < -50.0 and z > -56.0 and x < 0.0:
			continue
		var s := prng.randf_range(0.15, 0.35)
		add_child(Geo.box_mesh_node(Vector3(s, s * 0.6, s * 1.2), mats["concrete_dark"], Vector3(x, Y_WALK + s * 0.3, z), Vector3(0, prng.randf() * 180.0, 0)))
	for i in 6:
		var z := prng.randf_range(-118.0, -138.0)
		var s := prng.randf_range(0.2, 0.4)
		add_child(Geo.box_mesh_node(Vector3(s, s * 0.5, s), mats["brick"], Vector3(prng.randf_range(0.6, 2.2), Y_WALK + s * 0.25, z), Vector3(0, prng.randf() * 180.0, 0)))
	# Nebel ueber dem Wasser
	Props.fog_volume(self, Vector3(0.0, Y_WATER + 0.3, -49.0), Vector3(3.0, 0.8, 40.0), 0.05, Color(0.7, 0.72, 0.66))
	Props.fog_volume(self, Vector3(-7.0, Y_WATER + 0.3, -91.0), Vector3(8.0, 0.8, 40.0), 0.05, Color(0.7, 0.72, 0.66))
	Props.fog_volume(self, Vector3(7.0, Y_WATER + 0.3, -91.0), Vector3(8.0, 0.8, 40.0), 0.05, Color(0.7, 0.72, 0.66))

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(XA, 0.1, 2.6), "player_spawn")
	ps.name = "PlayerSpawn"
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
	nv = NightVision.new()
	nv.set("battery_seconds", 240.0)
	nv.set("recharge_seconds", 40.0)
	add_child(nv)
	director.set("nightvision", nv)
	# Leitern
	_add_ladder("SchachtS7",
		AABB(Vector3(XA - 1.0, Y_WALK, -34.3), Vector3(2.0, 1.8, 0.6)),
		AABB(Vector3(XA - 1.5, 0.0, -33.4), Vector3(3.0, 2.0, 0.8)),
		Vector3(XA, 0.05, -31.6), Vector3(XA, Y_WALK + 0.05, -35.3))
	_add_ladder("SteigschachtK",
		AABB(Vector3(-1.4, Y_WALK, -180.2), Vector3(2.8, 1.8, 0.9)),
		AABB(),
		Vector3(0.0, 0.05, -182.2), Vector3.ZERO)
	_label("▲ Leiter", Vector3(0.0, Y_WALK + 1.9, -180.05), 0.0, 40, Color(0.9, 0.85, 0.6), 0.006)
	_label("▼ Leiter", Vector3(XA, 1.3, -33.5), 0.0, 40, Color(0.9, 0.85, 0.6), 0.006)
	# Sprengladungen an den inneren Pfeilern, Lichtschranken davor
	_build_charge(Vector3(-3.6, 0, -78.0), 1.0, -78.0)
	_build_charge(Vector3(3.6, 0, -94.0), -1.0, -94.0)
	_build_charge(Vector3(-3.6, 0, -102.0), 1.0, -102.0)
	# Bot-Route
	var route: Array = [
		Vector3(XA, 0, 0.0), Vector3(XA, 0, -20.0), Vector3(XA, 0, -32.2),
		Vector3(XA, Y_WALK, -38.0), Vector3(XA, Y_WALK, -46.0), Vector3(-1.0, Y_WALK, -48.6),
		Vector3(0.0, Y_WET, -50.5), Vector3(0.0, Y_WET, -56.0), Vector3(1.6, Y_WALK, -57.6),
		Vector3(2.75, Y_WALK, -60.0), Vector3(2.75, Y_WALK, -68.6), Vector3(2.75, Y_WALK, -70.3),
		Vector3(2.0, Y_WALK, -73.0), Vector3(-2.3, Y_WALK, -76.8), Vector3(0.0, Y_WALK, -86.0),
		Vector3(2.3, Y_WALK, -92.8), Vector3(-0.5, Y_WALK, -97.0), Vector3(-2.3, Y_WALK, -100.8),
		Vector3(0.0, Y_WALK, -106.0), Vector3(0.0, Y_WALK, -111.0), Vector3(0.6, Y_WALK, -112.8),
		Vector3(1.4, Y_WALK, -115.0), Vector3(1.4, Y_WALK, -126.0), Vector3(1.4, Y_WALK, -138.0),
		Vector3(1.0, Y_WALK, -143.0), Vector3(-1.5, Y_WALK, -152.0), Vector3(-2.5, Y_WALK, -159.0),
		Vector3(0.0, Y_WALK, -168.0), Vector3(0.0, Y_WALK, -172.2), Vector3(0.0, Y_WALK, -176.5),
		Vector3(0.0, Y_WALK, -178.6), Vector3(0.0, 0.0, -184.5),
	]
	for i in route.size():
		var w := Geo.marker(m, (route[i] as Vector3) + Vector3(0, 0.05, 0), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	# Checkpoints und Story-Ausloeser
	# Einweisung (Falk/Lena) noch im sicheren Versorgungsgang, bevor der Spieler in den Sammler zur ersten
	# Streife hinabsteigt; der Checkpoint-Ausloeser unten bleibt Rueckfall (_on_sammler spielt nur einmal).
	_trigger("SammlerFunk", Vector3(XA, 1.5, -21.0), Vector3(3.0, 3.0, 1.0), func() -> void: _on_sammler())
	_trigger("CpSammler", Vector3(XA, Y_WALK + 1.5, -40.0), Vector3(2.6, 3.0, 1.0), func() -> void: _checkpoint("cp_sammler"); _on_sammler())
	_trigger("Einsturz", Vector3(0.0, Y_WALK + 1.5, -45.0), Vector3(8.0, 3.0, 1.0), _on_collapse)
	_trigger("CpHalle", Vector3(0.0, Y_WALK + 1.5, -72.0), Vector3(8.0, 3.0, 1.0), func() -> void: _checkpoint("cp_halle"); _on_hall())
	_trigger("CpKanal", Vector3(0.0, Y_WALK + 1.5, -114.0), Vector3(5.0, 3.0, 1.0), func() -> void: _checkpoint("cp_kanal"); _on_channel())
	_trigger("CpDepot", Vector3(0.0, Y_WALK + 1.5, -141.0), Vector3(5.0, 3.0, 1.0), func() -> void: _checkpoint("cp_depot"); _on_depot())
	_trigger("Schacht", Vector3(0.0, Y_WALK + 1.5, -173.5), Vector3(3.0, 3.0, 1.0), _on_final_shaft)
	var area := _trigger("LevelEnd", Vector3(0.0, 1.2, -184.5), Vector3(8.0, 2.4, 3.0), _finish, false)
	area.add_to_group("level_end")

func _build_set_piece_geometry() -> void:
	pass

func _build_skyline() -> void:
	pass

func _build_atmosphere() -> void:
	# Alarmleuchten (nur bei Alarm sichtbar)
	for p: Vector3 in [Vector3(0.0, -1.2, -40.0), Vector3(0.0, -1.2, -64.0), Vector3(-6.0, -0.8, -84.0), Vector3(6.0, -0.8, -100.0), Vector3(1.4, -1.8, -132.0), Vector3(0.0, -1.1, -158.0)]:
		var l := _omni(p, Color(1.0, 0.12, 0.06), 0.0, 9.0, 0.8)
		l.visible = false
		_alarm_lamps.append(l)

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
	nm.filter_baking_aabb = AABB(Vector3(-12.0, -6.0, -194.0), Vector3(24.0, 10.0, 200.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

# ------------------------------------------------------------------ Wachen

func _spawn_wave(index: int) -> void:
	if _waves_spawned.has(index) or not spawn_enemies or index != 0:
		return
	_waves_spawned[index] = true
	wave_started.emit(index)
	var W := Y_WALK
	var guards: Array = [
		# Sammler: Streife auf der rechten Bankette
		["rifleman", true, [_wp(2.75, W, -40.0, 3.0, 0.0), _wp(2.75, W, -64.0, 3.0, 180.0)]],
		# Halle: Posten am rechten Durchgang (schaut in die Halle), Streife im Mittelgang, Streife im linken Becken
		["rifleman", false, [_wp(3.2, W, -73.2, 0.0, 90.0)]],
		["assault", true, [_wp(0.0, W, -82.0, 2.5, 180.0), _wp(0.0, W, -106.0, 2.5, 0.0)]],
		["rifleman", true, [_wp(-5.55, Y_WET, -76.0, 3.0, 0.0), _wp(-5.55, Y_WET, -108.0, 3.0, 180.0)]],
		["officer", false, [_wp(1.6, W, -109.8, 0.0, 90.0)]],
		# Ziegelkanal
		["rifleman", true, [_wp(1.4, W, -118.0, 3.0, 180.0), _wp(1.4, W, -136.0, 3.0, 0.0)]],
		# Depot: Mann am Generator, Streife, Posten am Steigschacht
		["rifleman", false, [_wp(4.1, W, -152.6, 0.0, -90.0)]],
		["assault", true, [_wp(-4.0, W, -145.0, 2.0, 90.0), _wp(-4.6, W, -163.0, 2.0, -90.0), _wp(4.0, W, -167.0, 2.0, 0.0)]],
		["rifleman", false, [_wp(0.0, W, -174.6, 0.0, 0.0)]],
		# Zusatzwachen (mehr Gegner): linke Bankette, rechtes Becken, Kanalende, Depot links
		["rifleman", true, [_wp(-2.75, W, -58.0, 4.0, 180.0), _wp(-3.2, W, -73.2, 3.0, 0.0)]],
		["rifleman", true, [_wp(5.55, Y_WET, -100.0, 3.0, 0.0), _wp(5.55, Y_WET, -80.0, 3.0, 180.0)]],
		["rifleman", false, [_wp(-1.4, W, -140.0, 0.0, 180.0)]],
		["rifleman", false, [_wp(-4.1, W, -152.6, 0.0, 90.0)]],
	]
	for g: Array in guards:
		_spawn_guard(str(g[0]), bool(g[1]), g[2] as Array)

func _spawn_guard(type: String, flash: bool, route: Array) -> Enemy:
	var scene := load(ENEMY_PATH % type) as PackedScene
	if scene == null:
		return null
	var e := scene.instantiate() as Enemy
	e.set_meta("faction", "reich")
	add_child(e)
	var r0: Dictionary = route[0]
	e.global_position = r0["p"]
	var y: float = r0.get("yaw", NAN)
	e.rotation.y = 0.0 if is_nan(y) else y
	e.accuracy_scale = 0.55
	var b := Brain.new()
	b.setup(e, director, route, flash)
	return e

func _spawn_reinforcement(type: String, pos: Vector3, target: Vector3) -> void:
	var scene := load(ENEMY_PATH % type) as PackedScene
	if scene == null:
		return
	var e := scene.instantiate() as Enemy
	e.set_meta("faction", "reich")
	add_child(e)
	e.global_position = pos
	e.accuracy_scale = 0.6
	e.alert(target, false)
	_reinf.append(e)

# ------------------------------------------------------------------ Ablauf

func _physics_process(delta: float) -> void:
	_t += delta
	_climb_cd = maxf(0.0, _climb_cd - delta)
	var pl := _player()
	if pl == null or not _ready_done or director == null:
		return
	_update_water(pl, delta)
	_update_charges(pl, delta)
	if _reinf_t >= 0.0:
		_reinf_t -= delta
		if _reinf_t < 0.0:
			_call_reinforcements()
	_update_alarm_note()
	if _bot:
		if takedown != null and takedown.get("candidate") != null:
			takedown.call("try_auto")
		if nv != null and not bool(nv.get("nv_on")) and float(nv.get("battery")) > 0.4:
			nv.call("set_nightvision", true)
		# Bot: beim Schleichen die Schalldaempferpistole, im Alarm das Gewehr
		var want := 0 if bool(director.get("alarm")) else 1
		if pl.weapons.size() > want and pl.weapon_index != want and pl.is_alive():
			pl._do_switch(want)
	if bool(director.get("alarm")):
		for l in _alarm_lamps:
			l.light_energy = 2.0 + 1.6 * sin(_t * 8.0)

## Autopilot-Hook: schleichen, solange kein Alarm laeuft (geduckt, kein Feuer, Takedowns, Streifen abwarten).
func autopilot_stealth() -> bool:
	return director != null and not bool(director.get("alarm")) and not _finished

## Autopilot-Hook: oben am Schacht die Sammler-Einweisung (Falk/Lena) abhoeren, bevor es hinuntergeht --
## wie ein Spieler, der der Einweisung folgt ("Unten keine Hast"). Hoechstens 30 s.
func autopilot_hold() -> bool:
	var pl := _player()
	if pl == null or pl.global_position.y < -1.0 or pl.global_position.z > -24.0:
		return false
	if _hold_t0 < 0.0:
		_hold_t0 = _t
	if _t - _hold_t0 > 30.0:
		return false
	return not _said.has("sammler_lena") or _radio_busy() > 0.3

## HUD-Zeile unter "ALARM": naechste Welle (zweite mit Gepanzerten) bzw. Staerke des Suchtrupps.
func _update_alarm_note() -> void:
	if hud == null:
		return
	if not bool(director.get("alarm")):
		hud.set("alarm_note", "")
		return
	var n := 0
	for e in _reinf:
		if is_instance_valid(e) and (not e.has_method("is_alive") or bool(e.call("is_alive"))):
			n += 1
	var parts: Array[String] = []
	if _reinf_t >= 0.0:
		parts.append(("Zweiter Zug rückt" if _reinf_waves == 0 else "Gepanzerte rücken") + " an in %d s" % ceili(_reinf_t))
	if n > 0:
		parts.append("Suchtrupp im Sammler: %d Mann" % n)
	if parts.is_empty():
		parts.append("Streifen durchkämmen den Sammler")
	hud.set("alarm_note", " · ".join(parts))

func _intro() -> void:
	_obj("Durch die Kanalisation zum Kanzleramt – [%s] Nachtsicht, [%s] Lampe" % [_key("nightvision"), _key("flashlight")])
	_later(1.2, func() -> void:
		_say(StoryData.VOSS, "Bis hier hab ich dich gebracht, Jonas. Der Schacht am Ende führt in den alten Sammler unter dem Reichstag – da unten ist es stockfinster.")
		_say_opt(StoryData.LENA, "Nimm das Nachtsichtgerät. Die Lampe siehst du besser – aber jeder Gardist sieht dich auch.", {})
		_say_opt(StoryData.VOSS, "Ich bleibe am Einstieg und halte den Funk. Unten keine Hast. Wasser trägt jedes Geräusch.", {"valid": _no_alarm}))

func _on_sammler() -> void:
	if _said.has("sammler"):
		return
	# Falk auf dem Gardefunk, Lena kommentiert direkt (Gespraech im selben Frame); der Schleich-Tipp nur ohne Alarm
	_say_once_opt("sammler", StoryData.FALK, "Hier Falk. Alle Streifen im Sammler Tiergarten: Lampen an, Augen auf. Wer sich da unten bewegt, gehört nicht zu uns.",
		{"valid": _no_alarm})
	_say_once_opt("sammler_lena", StoryData.LENA, "Das ist Falk persönlich auf dem Gardefunk. Lampen voraus – bleib im Dunkeln, geduckt. Von hinten, lautlos.",
		{"valid": _no_alarm})

func _on_collapse() -> void:
	_say_once_opt("collapse", StoryData.VOSS, "Die linke Bankette ist eingebrochen. Du musst durchs Gerinne – langsam, das Wasser plätschert bis zur Halle.",
		{"priority": 2, "max_age": 6.0})

func _on_hall() -> void:
	if _said.has("hall"):
		return
	_said["hall"] = true
	# Hallen-Einweisung als ein Gespraech; die Tipps entfallen, wenn die Ladungen schon erledigt sind
	_say_opt(StoryData.LENA, "Jonas, die Pfeiler – da hängen Ladungen dran. Mit Lichtschranken quer über den Gang.", {"priority": 2, "cut": true})
	_say_opt(StoryData.VOSS, "Das sind die Fundamente des Plenarsaals. Falk will alles hinter sich zusprengen, wenn der Ring sich schließt.",
		{"priority": 2, "valid": func() -> bool: return _defused + _blown_count() < _charges.size()})
	_say_opt(StoryData.LENA, "Entschärf sie, wenn du rankommst. Oder geh durchs Becken außen herum – nass und laut, aber an den Strahlen vorbei.",
		{"priority": 1, "valid": func() -> bool: return _defused + _blown_count() < _charges.size()})
	_update_charge_objective()

func _on_channel() -> void:
	_say_once_opt("channel", StoryData.FALK, "Achse B, Meldung. … Achse B? Riedhammer will den Sammler dicht, bevor die Divisionen am Spreebogen stehen.",
		{"priority": 1, "max_age": 4.0})

func _on_depot() -> void:
	_say_once_opt("depot", StoryData.VOSS, "Die Überlaufkammer. Die Garde hat sich da ein Depot eingerichtet. Dahinter der Steigschacht zum Kanzleramt – den hab ich vor zwanzig Jahren selbst vermessen.",
		{"priority": 1, "max_age": 3.0})

func _on_final_shaft() -> void:
	_obj("Leiter hoch in den Versorgungskeller des Kanzleramts")
	_say_once_opt("shaft", StoryData.VOSS, "Die Leiter hoch. Oben ist der Versorgungskeller des Kanzleramts. Ab da bist du drin, Jonas.",
		{"priority": 1, "max_age": 3.0, "valid": func() -> bool: return not _finished})

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_obj("")
	# Schlussgespraech direkt, Level endet erst, wenn es durch ist
	_say_opt(StoryData.KERNER, "Bin oben. Keller ist leer.", {"priority": 2, "cut": true})
	_say(StoryData.FALK, "Wer auch immer da unten war: Ich weiß, wohin der Schacht führt. Oben warte ich.")
	_later(1.0, _when_radio_free.bind(_on_level_end, 14.0))

func _on_alarm_raised(reason: String, _pos: Vector3, first: bool) -> void:
	if not first:
		return
	_set_alarm_fx(true)
	if _reinf_waves < 2 and _reinf_t < 0.0:
		_reinf_t = 8.0
	var on_alarm := func() -> bool: return bool(director.get("alarm"))
	match reason:
		"body":
			_say_opt(StoryData.FALK, "Mann am Boden im Sammler! Alle Streifen absuchen – jeden Winkel!", {"priority": 1, "cut": true, "valid": on_alarm})
		"shot":
			_say_opt(StoryData.FALK, "Schüsse unter Achse B! Alarm. Riegelt die Durchgänge ab!", {"priority": 1, "cut": true, "valid": on_alarm})
		_:
			_say_opt(StoryData.FALK, "Kontakt im Sammler. Er ist allein – holt ihn mir!", {"priority": 1, "cut": true, "valid": on_alarm})
	_say_opt(StoryData.LENA, "Sie haben dich! Lampe aus, raus aus ihrem Licht – oder kämpf dich durch.", {"priority": 1, "valid": on_alarm})

func _on_alarm_ended() -> void:
	_set_alarm_fx(false)
	_reinf_t = -1.0
	_say_opt(StoryData.FALK, "… Nichts? Streifen zurück auf ihre Posten. Und haltet die Augen offen.", {"priority": 1, "max_age": 3.0, "bark": true,
		"valid": func() -> bool: return _no_alarm() and not _finished})
	var pl := _player()
	for e in _reinf:
		if is_instance_valid(e) and pl != null and (e as Node3D).global_position.distance_to(pl.global_position) > 22.0:
			e.queue_free()

func _set_alarm_fx(on: bool) -> void:
	for l in _alarm_lamps:
		l.visible = on
		l.light_energy = 2.0 if on else 0.0
	if on:
		if _alarm_loops.is_empty():
			var k1 := _loop_3d("curfew_klaxon", Vector3(0.0, -1.5, -90.0), -6.0, 14.0, 120.0)
			var k2 := _loop_3d("curfew_klaxon", Vector3(0.0, -1.5, -155.0), -8.0, 12.0, 100.0)
			for n: Node in [k1, k2]:
				if n != null:
					_alarm_loops.append(n)
	else:
		for n in _alarm_loops:
			_fade_out(n, 2.5)
		_alarm_loops.clear()

func _call_reinforcements() -> void:
	if not bool(director.get("alarm")) or _reinf_waves >= 2:
		return
	_reinf_waves += 1
	var pl := _player()
	if pl == null:
		return
	var pts: Array[Vector3] = [Vector3(2.75, Y_WALK + 0.1, -32.0), Vector3(0.0, Y_WALK + 0.1, -84.0), Vector3(0.0, Y_WALK + 0.1, -110.0),
		Vector3(1.4, Y_WALK + 0.1, -128.0), Vector3(0.0, Y_WALK + 0.1, -160.0), Vector3(6.0, Y_WALK + 0.1, -168.0)]
	var best := pts[0]
	var best_score := -1.0e9
	for p in pts:
		var d := p.distance_to(pl.global_position)
		var score := -absf(d - 30.0)
		if d < 18.0:
			score -= 100.0
		if score > best_score:
			best_score = score
			best = p
	var target := pl.global_position
	var types: Array = ["rifleman", "assault", "rifleman", "rifleman"] if _reinf_waves == 1 else ["assault", "armored", "rifleman", "rifleman"]
	for i in types.size():
		_spawn_reinforcement(types[i], best + Vector3((float(i) - 1.5) * 0.7, 0, float(i % 2) * 0.8), target)
	if _reinf_waves == 1:
		_say_opt(StoryData.FALK, "Zweiter Zug runter in den Sammler. Von beiden Seiten.", {"priority": 1, "max_age": 8.0, "bark": true, "key": "kan_reinf"})
	else:
		_say_opt(StoryData.FALK, "Schickt die Gepanzerten. Ich will das erledigt haben.", {"priority": 1, "max_age": 8.0, "bark": true, "key": "kan_reinf"})
	# Eskalation: haelt der Alarm an, folgen nach 30 s die Gepanzerten (HUD zaehlt herunter)
	if _reinf_waves < 2:
		_reinf_t = 30.0

func _on_player_respawned() -> void:
	for e in _reinf:
		if is_instance_valid(e):
			e.queue_free()
	_reinf.clear()
	_reinf_t = -1.0
	_reinf_waves = 0
	director.call("reset_all")
	_set_alarm_fx(false)
	_climbing = false
	for c: Dictionary in _charges:
		c["progress"] = 0.0
	if nv != null:
		nv.call("set_flashlight", false)
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
	if not _bot:
		_select_sd()

func _select_sd() -> void:
	var pl := _player()
	if pl != null and pl.weapons.size() > 1 and pl.weapon_index != 1:
		pl._do_switch(1)

func _ambience() -> void:
	_loop_2d("kanalisation_drips" if ResourceLoader.exists("res://assets/sfx/kanalisation_drips.ogg") else "amb_wind", -26.0)
	_loop_3d("overwatch_steam_loop", Vector3(3.8, -2.0, -44.0), -20.0, 4.0, 25.0)
	_loop_3d("overwatch_steam_loop", Vector3(5.6, -3.6, -151.0), -16.0, 4.0, 30.0)
	_loop_2d("amb_battle", -38.0)

## --kn-start=<abschnitt>: Spieler an einen Checkpoint versetzen (Debug/Captures).
func _debug_start() -> void:
	var s := str(Game.arg("kn-start", ""))
	if s == "" or not STARTS.has(s):
		return
	var pl := _player()
	if pl == null:
		return
	var e: Array = STARTS[s]
	pl.global_position = e[0]
	pl.velocity = Vector3.ZERO
	_said["hall"] = s != "sammler" and s != "halle"
	Events.checkpoint_reached.emit(str(e[1]))
