extends "res://game/levels/level.gd"
## Teil 4, Mission 13 – "Letztes Gefecht" (Regierungsbunker unter dem Spreebogen, 25.06.2030 04:40).
## Finale von Teil 4. Kerner kommt von unten: alte Versorgungsroehre unter der Spree (nass, Beton),
## Bunkerschleuse, Technikebene (Generatoren, Dampf), Treppe hinab in die Schlafsaele, Kommandokorridor,
## Lagezentrum (Bosskampf gegen Oberst Falk im schweren Anzug), Kontrollraum: Riedhammer wird gestellt,
## Weber ist da (er hat die Zuendleitung gekappt, traegt die Akte Nordlicht). Entscheidung:
## [E] festnehmen / [F] gehen lassen -> Settings "game/weber_choice" = "arrest" | "release".
##
## Ablauf (Spieler laeuft nach -z, ab den Schlafsaelen auf y = -3):
##   Roehre z 36..4 -> Schleuse z 4..-4 -> Technik z -4..-34 -> Gang/Treppe z -34..-50
##   -> Schlafsaele z -50..-72 -> Korridor z -72..-80 -> Lagezentrum z -80..-104 -> Kontrollraum z -104..-116
## Debug: --bk-start=boss|control|decision|cutscene  (springt in den Abschnitt), --bunker-choice=arrest|release,
##        --bk-autochoose (waehlt ohne Autopilot automatisch, fuer den Endsequenz-Test).
## Unter --autopilot faehrt der Level die Zwischensequenz selbst (bot_drives_player()) und waehlt
## deterministisch: --bunker-choice hat Vorrang, sonst novice -> release, alle anderen -> arrest.

const BP = preload("res://game/levels/berlin_props.gd")
const VF = preload("res://game/vehicles/vehicle_fx.gd")
const AHUD = preload("res://game/enemies/armor_hud.gd")
const VIP = preload("res://game/characters/vip_models.gd")

const YL := -3.0         ## Fussboden der unteren Ebene
const CHOICE_KEY := "game/weber_choice"

var mats: Dictionary = {}
var _bd: BP.Builder
var _body: StaticBody3D
var _bot: bool = false
var _loops: Array[Node] = []
var _t: float = 0.0
var _flicker: Array = []                 ## [OmniLight3D, MeshInstance3D, phase]
var _rot_lights: Array = []              ## [Node3D-Pivot, Geschwindigkeit]
var _alarm_mat: StandardMaterial3D
var _inner_door: StaticBody3D
var _blast: StaticBody3D
var _hatch: StaticBody3D
var _end_area: Area3D
var _falk: Enemy
var _falk_half: bool = false
var _falk_dead: bool = false
var _cine: bool = false
var _cine_look: Vector3 = Vector3.ZERO
var _ried: Dictionary = {}               ## {root, arms, legs}
var _weber: Dictionary = {}
var _case: Node3D
var _deciding: bool = false
var _decide_t: float = 0.0
var _choice: String = ""
var _ui: CanvasLayer
var _scene_started: bool = false
var _start: String = ""

func _init() -> void:
	level_name = "bunker"
	end_z = -107.0
	build_seed = 2507
	_wave_count = 5
	default_faction = "reich"
	ambient_artillery = false

func _ready() -> void:
	_bot = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	_start = str(Game.arg("bk-start", ""))
	_ensure_actions()
	await super()
	if not is_inside_tree():
		return
	_build_doors()
	_build_figures()
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.enemy_damaged.connect(_on_enemy_damaged)
	_loop_2d("curfew_drone_hum", -30.0)
	_loop_3d("river_flow", Vector3(0, 1.0, 30.0), -10.0, 6.0, 40.0)
	_loop_3d("overwatch_steam_loop", Vector3(-7.5, 3.0, -13.0), -14.0, 5.0, 30.0)
	_loop_3d("overwatch_steam_loop", Vector3(7.5, 3.0, -25.0), -16.0, 5.0, 30.0)
	_loop_3d("curfew_klaxon", Vector3(0, YL + 2.5, -92.0), -30.0, 6.0, 50.0)
	if _start != "":
		_debug_start(_start)
	else:
		_later(1.2, _intro)

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Letztes Gefecht"
	return info

## Autopilot-Hook: waehrend der Kontrollraum-Sequenz und der Entscheidung steuert der Level selbst.
func bot_drives_player() -> bool:
	return _bot and _cine

static func _ensure_actions() -> void:
	if not InputMap.has_action("bunker_release"):
		InputMap.add_action("bunker_release")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		InputMap.action_add_event("bunker_release", ev)

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

## Falk ueber die Bunkerlautsprecher (Rueckkopplung an der naechsten Decke).
func _pa(text: String) -> void:
	var pl := _player()
	if pl != null:
		VF.play_at(self, "berlin_pa_feedback", pl.global_position + Vector3(0, 2.6, -3.0), -8.0, 6.0, 40.0)
	_say(StoryData.FALK, text)

func _obj(text: String) -> void:
	Events.story_objective.emit(text)

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

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

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
	l.shaded = false
	l.double_sided = false
	l.position = pos
	l.rotation_degrees.y = yaw
	add_child(l)
	return l

## Box aus zwei Ecken (Optik + Kollision im gemeinsamen Koerper).
func _bx(key: String, a: Vector3, b: Vector3, collide: bool = true) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var c := (lo + hi) * 0.5
	var s := hi - lo
	_bd.box(key, c, s)
	if collide:
		Geo.add_box_shape(_body, c, s)

## Nur Kollision (unsichtbar).
func _col(a: Vector3, b: Vector3) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	Geo.add_box_shape(_body, (lo + hi) * 0.5, hi - lo)

## Wand entlang x bei z, mit Oeffnungen [[x_mitte, breite, hoehe], ...].
func _wall_x(z: float, x0: float, x1: float, y0: float, y1: float, gaps: Array = [], key: String = "concrete") -> void:
	var t := 0.15
	var cur := x0
	var gs := gaps.duplicate()
	gs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for g: Array in gs:
		var g0: float = float(g[0]) - float(g[1]) * 0.5
		var g1: float = float(g[0]) + float(g[1]) * 0.5
		if g0 > cur:
			_bx(key, Vector3(cur, y0, z - t), Vector3(g0, y1, z + t))
		if y0 + float(g[2]) < y1:
			_bx(key, Vector3(g0, y0 + float(g[2]), z - t), Vector3(g1, y1, z + t))
		cur = g1
	if cur < x1:
		_bx(key, Vector3(cur, y0, z - t), Vector3(x1, y1, z + t))

## Wand entlang z bei x (z0 > z1), Oeffnungen [[z_mitte, breite, hoehe], ...].
func _wall_z(x: float, z0: float, z1: float, y0: float, y1: float, gaps: Array = [], key: String = "concrete") -> void:
	var t := 0.15
	var cur := z1
	var gs := gaps.duplicate()
	gs.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for g: Array in gs:
		var g0: float = float(g[0]) - float(g[1]) * 0.5
		var g1: float = float(g[0]) + float(g[1]) * 0.5
		if g0 > cur:
			_bx(key, Vector3(x - t, y0, cur), Vector3(x + t, y1, g0))
		if y0 + float(g[2]) < y1:
			_bx(key, Vector3(x - t, y0 + float(g[2]), g0), Vector3(x + t, y1, g1))
		cur = g1
	if cur < z0:
		_bx(key, Vector3(x - t, y0, cur), Vector3(x + t, y1, z0))

## Rampe (Kollision) + Stufen (Optik) zwischen (z_low, y_low) und (z_high, y_high), Breite x0..x1.
func _stairs(x0: float, x1: float, z_low: float, y_low: float, z_high: float, y_high: float) -> void:
	var dz := z_high - z_low
	var dy := y_high - y_low
	var L := sqrt(dz * dz + dy * dy)
	var th := 0.4
	var n := Vector3(0.0, absf(dz), -signf(dz) * dy) / L
	var zax := Vector3(1, 0, 0).cross(n)
	var basis := Basis(Vector3(1, 0, 0), n, zax)
	var mid := Vector3((x0 + x1) * 0.5, (y_low + y_high) * 0.5 + 0.09, (z_low + z_high) * 0.5) - n * th * 0.5
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(x1 - x0, th, L + 0.2)
	cs.shape = bs
	cs.transform = Transform3D(basis, mid)
	_body.add_child(cs)
	_bd.box("concrete_dark", mid - n * 0.05, Vector3(x1 - x0, th, L), basis)
	var steps := maxi(2, int(round(dy / 0.18)))
	for i in steps:
		var ya := y_low + dy * float(i + 1) / float(steps)
		var za := z_low + dz * float(i) / float(steps)
		var zb := z_low + dz * float(i + 1) / float(steps)
		_bx("concrete", Vector3(x0, ya - 0.34, za), Vector3(x1, ya, zb), false)
		_bx("hazard", Vector3(x0, ya - 0.015, za - signf(dz) * 0.02), Vector3(x1, ya + 0.005, za + signf(dz) * 0.06), false)

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(0.02, 0.2)
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.22, 0.24)
	env.ambient_light_energy = 0.22
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_exposure = 1.3
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.sdfgi_enabled = true
	env.sdfgi_energy = 0.6
	env.ssil_intensity = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.04, 0.045)
	env.fog_light_energy = 1.0
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color(0.82, 0.82, 0.85)
	env.volumetric_fog_emission = Color(0.004, 0.003, 0.004)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 60.0
	env.volumetric_fog_gi_inject = 0.5
	env.volumetric_fog_ambient_inject = 0.1
	env.volumetric_fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.8
	env.glow_intensity = 1.1
	env.glow_bloom = 0.08
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.15
	env.adjustment_color_correction = null
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "night_city")

func _make_mats() -> void:
	mats = BP.materials()
	mats["concrete"] = Geo.mat("concrete_wall_008", Color(0.42, 0.43, 0.44), 0.25, 1.0)
	mats["concrete_dark"] = Geo.mat("concrete_wall_008", Color(0.24, 0.25, 0.26), 0.25, 0.8)
	mats["concrete_wet"] = Geo.mat("concrete_wall_008", Color(0.2, 0.22, 0.22), 0.3, 0.35)
	mats["rust"] = Geo.mat("rusty_metal_02", Color(0.55, 0.5, 0.46), 0.5, 1.0, 0.4)
	mats["steel_dark"] = Geo.flat(Color(0.16, 0.17, 0.18), 0.45, 0.7)
	mats["paint_green"] = Geo.flat(Color(0.17, 0.22, 0.18), 0.6, 0.3)
	mats["floor"] = Geo.flat(Color(0.28, 0.28, 0.27), 0.5)
	mats["linoleum"] = Geo.flat(Color(0.22, 0.24, 0.2), 0.4)
	mats["blanket"] = Geo.flat(Color(0.2, 0.22, 0.17), 0.97)
	mats["mattress"] = Geo.flat(Color(0.45, 0.43, 0.38), 0.95)
	mats["paper"] = Geo.flat(Color(0.8, 0.79, 0.74), 0.9)
	mats["map"] = Geo.flat(Color(0.32, 0.38, 0.33), 0.8)
	mats["hazard"] = Geo.flat(Color(0.75, 0.6, 0.08), 0.6)
	mats["leather"] = Geo.flat(Color(0.08, 0.07, 0.07), 0.45)
	mats["water"] = Geo.flat(Color(0.05, 0.07, 0.07), 0.02, 0.2)
	(mats["water"] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(mats["water"] as StandardMaterial3D).albedo_color = Color(0.06, 0.08, 0.08, 0.72)
	mats["exit_green"] = BP.unshaded(Color(0.15, 2.4, 0.6))
	mats["emerg_red"] = BP.unshaded(Color(2.8, 0.12, 0.08))
	mats["amber"] = BP.unshaded(Color(2.6, 1.2, 0.2))
	mats["screen"] = BP.unshaded(Color(0.25, 0.9, 0.55))
	mats["screen_red"] = BP.unshaded(Color(1.6, 0.15, 0.1))
	mats["lamp_dead"] = Geo.flat(Color(0.25, 0.25, 0.26), 0.4)
	_alarm_mat = StandardMaterial3D.new()
	_alarm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_alarm_mat.albedo_color = Color(3.0, 0.15, 0.05)
	mats["alarm"] = _alarm_mat

func _build_ground() -> void:
	_make_mats()
	_bd = BP.Builder.new(mats)
	_bd.no_shadow.append_array(["water", "exit_green", "emerg_red", "amber", "screen", "screen_red", "alarm"])
	_body = Geo.static_body()
	_body.name = "Bunker"
	_body.set_meta("no_fit", true)
	world.add_child(_body)
	_bx("concrete_wet", Vector3(-2.2, -0.3, 4.0), Vector3(2.2, 0.0, 36.8))          # Roehre
	_bx("floor", Vector3(-3.15, -0.3, -4.0), Vector3(3.15, 0.0, 4.0))               # Schleuse
	_bx("concrete_dark", Vector3(-13.15, -0.3, -34.0), Vector3(13.15, 0.0, -4.0))   # Technik
	_bx("concrete_dark", Vector3(-2.0, -0.3, -40.0), Vector3(2.0, 0.0, -34.0))      # Gang
	_bx("linoleum", Vector3(-11.15, YL - 0.3, -72.0), Vector3(11.15, YL, -50.0))    # Schlafsaele
	_bx("floor", Vector3(-2.5, YL - 0.3, -80.0), Vector3(2.5, YL, -72.0))           # Korridor
	_bx("floor", Vector3(-14.15, YL - 0.3, -104.0), Vector3(14.15, YL, -80.0))      # Lagezentrum
	_bx("linoleum", Vector3(-8.15, YL - 0.3, -116.0), Vector3(8.15, YL, -104.0))    # Kontrollraum
	_bx("floor", Vector3(8.0, YL - 0.3, -111.5), Vector3(12.0, YL, -108.5))         # Notausgang
	# stehendes Wasser in der Roehre (nur Optik)
	_bd.box("water", Vector3(0, 0.05, 20.4), Vector3(3.8, 0.02, 32.6))

func _build_street() -> void:
	pass

# ------------------------------------------------------------------ Bauabschnitte

func _build_props() -> void:
	_build_tube()
	_build_lock()
	_build_tech()
	_build_stairway()
	_build_dorms()
	_build_corridor()
	_build_situation_room()
	_build_control_room()
	_bd.build(world)
	_build_lights()

func _build_tube() -> void:
	# Betonroehre unter der Spree: Waende, Gewoelbe aus schraegen Platten, Rohre, Rinnsale
	_bx("concrete_wet", Vector3(-2.2, 0, 4.0), Vector3(-1.9, 3.2, 36.8))
	_bx("concrete_wet", Vector3(1.9, 0, 4.0), Vector3(2.2, 3.2, 36.8))
	_bx("concrete_wet", Vector3(-2.2, 3.0, 4.0), Vector3(2.2, 3.3, 36.8))
	_bx("concrete_wet", Vector3(-2.2, 0, 36.8), Vector3(2.2, 3.2, 37.1))
	var b45 := Basis(Vector3(0, 0, 1), deg_to_rad(45.0))
	for sx: float in [-1.0, 1.0]:
		_bd.box("concrete_wet", Vector3(sx * 1.62, 2.72, 20.4), Vector3(0.9, 0.25, 32.8), Basis(Vector3(0, 0, 1), deg_to_rad(-45.0 * sx)))
	# Gitter am Ende (dort kommt das Wasser rein)
	for i in 7:
		_bd.box("rust", Vector3(-1.5 + float(i) * 0.5, 1.4, 36.7), Vector3(0.06, 2.8, 0.06))
	_bd.box("rust", Vector3(0, 2.75, 36.7), Vector3(3.8, 0.1, 0.1))
	for z in [8.0, 14.0, 20.0, 26.0, 32.0]:
		_bx("rust", Vector3(-1.88, 2.15, z - 3.0), Vector3(-1.62, 2.4, z + 3.0), false)
		_bx("rust", Vector3(-1.88, 1.8, z - 3.0), Vector3(-1.7, 1.95, z + 3.0), false)
		_bx("steel_dark", Vector3(1.6, 2.2, z - 0.15), Vector3(1.88, 2.5, z + 0.15), false)   # Kabelhalter
		_bx("lamp_dead", Vector3(-0.15, 2.94, z - 0.4), Vector3(0.15, 3.0, z + 0.4), false)
	_bx("black", Vector3(1.75, 2.3, 4.2), Vector3(1.85, 2.4, 36.6), false)                    # Kabelstrang
	# Kilometrierung / alte Beschilderung
	_label("VERSORGUNGSROEHRE SPREE  -  ABSCHNITT 4", Vector3(-1.88, 1.4, 22.0), 90.0, 40, Color(0.75, 0.72, 0.6), 0.005)
	_label("SCHLEUSE  40 m", Vector3(1.88, 1.6, 12.0), -90.0, 44, Color(0.8, 0.75, 0.55), 0.005)
	# Treibgut, Sandsaecke (Deckung braucht es hier nicht)
	_bx("wood", Vector3(0.9, 0, 28.0), Vector3(1.7, 0.6, 29.0))
	_bx("steel_dark", Vector3(-1.7, 0, 17.0), Vector3(-1.1, 0.9, 17.6))

func _build_lock() -> void:
	# Bunkerschleuse x -3..3, z 4..-4: Stahlrahmen, Drucktafeln, innere Tuer bei z -4
	_wall_x(4.0, -3.15, 3.15, 0.0, 3.5, [[0.0, 3.8, 3.0]])
	_wall_z(-3.0, 4.0, -4.0, 0.0, 3.5)
	_wall_z(3.0, 4.0, -4.0, 0.0, 3.5)
	_bx("concrete", Vector3(-3.15, 3.2, -4.0), Vector3(3.15, 3.5, 4.0))
	_wall_x(-4.0, -3.15, 3.15, 0.0, 3.5, [[0.0, 2.0, 2.4]], "steel_dark")
	for z: float in [3.9, -3.9]:
		_bx("hazard", Vector3(-1.2, 2.4, z - 0.12), Vector3(1.2, 2.55, z + 0.12), false)
	_bx("steel_dark", Vector3(-2.85, 0.9, 0.5), Vector3(-2.6, 1.9, 1.6), false)               # Drucktafel
	_bd.box("screen_red", Vector3(-2.58, 1.6, 1.05), Vector3(0.02, 0.18, 0.5))
	_bd.box("alarm", Vector3(0.0, 3.1, -3.7), Vector3(0.25, 0.15, 0.25))
	_label("SCHLEUSE 2", Vector3(0, 2.85, 3.84), 180.0, 52, Color(0.85, 0.8, 0.6), 0.006)
	_label("DRUCKAUSGLEICH", Vector3(-2.57, 1.35, 1.05), 90.0, 26, Color(1.0, 0.3, 0.2), 0.004)

func _build_tech() -> void:
	# Technikebene x -13..13, z -4..-34, Hoehe 7
	_wall_x(-4.0, -13.15, 13.15, 0.0, 7.0, [[0.0, 6.3, 3.5]])
	_wall_z(-13.0, -4.0, -34.0, 0.0, 7.0)
	_wall_z(13.0, -4.0, -34.0, 0.0, 7.0)
	_wall_x(-34.0, -13.15, 13.15, 0.0, 7.0, [[0.0, 4.0, 3.2]])
	_bx("concrete_dark", Vector3(-13.15, 7.0, -34.15), Vector3(13.15, 7.3, -3.85))
	# Generatoren (Deckung) mit Auspuffrohren zur Decke
	for p: Vector3 in [Vector3(-7.5, 0, -13.0), Vector3(7.5, 0, -13.0), Vector3(-7.5, 0, -25.0), Vector3(7.5, 0, -25.0)]:
		_bx("paint_green", p + Vector3(-1.5, 0, -2.6), p + Vector3(1.5, 2.4, 2.6))
		_bx("steel_dark", p + Vector3(-1.6, 0, -2.7), p + Vector3(1.6, 0.25, 2.7), false)
		_bx("rust", p + Vector3(-1.2, 2.4, -2.0), p + Vector3(1.2, 2.9, 0.5), false)
		_bx("rust", p + Vector3(-0.25, 2.9, 1.2), p + Vector3(0.25, 7.0, 1.7), false)
		_bd.box("screen", p + Vector3(signf(-p.x) * 1.52, 1.6, -1.6), Vector3(0.02, 0.3, 0.5))
		_label("NOTSTROM %s" % ("A" if p.z > -20.0 else "B"), p + Vector3(signf(-p.x) * 1.53, 2.0, 0.6), 90.0 * signf(-p.x), 34, Color(0.85, 0.8, 0.55), 0.005)
	# Rohrtrassen unter der Decke (Optik)
	for x: float in [-10.5, -4.0, 4.0, 10.5]:
		_bx("rust", Vector3(x - 0.2, 5.6, -33.8), Vector3(x + 0.2, 6.0, -4.2), false)
		_bx("steel_dark", Vector3(x - 0.12, 5.0, -33.8), Vector3(x + 0.12, 5.25, -4.2), false)
	for z: float in [-8.0, -16.0, -24.0, -32.0]:
		_bx("steel_dark", Vector3(-12.8, 6.0, z - 0.1), Vector3(12.8, 6.15, z + 0.1), false)
	# Laufsteg an der Ostwand (Optik, nicht begehbar)
	_bx("steel_dark", Vector3(11.4, 3.6, -33.6), Vector3(12.85, 3.75, -4.4), false)
	_bx("hazard", Vector3(11.35, 4.5, -33.6), Vector3(11.45, 4.6, -4.4), false)
	# Kisten, Fass, Schaltschraenke (Deckung)
	_bx("wood", Vector3(-2.6, 0, -18.6), Vector3(-1.2, 1.1, -17.4))
	_bx("wood", Vector3(2.0, 0, -22.6), Vector3(3.4, 1.1, -21.4))
	_bx("wood", Vector3(-3.6, 0, -29.4), Vector3(-2.2, 1.0, -28.2))
	_bx("steel_dark", Vector3(2.4, 0, -30.2), Vector3(4.0, 1.2, -29.4))
	for z: float in [-8.0, -19.0, -30.0]:
		_bx("steel_dark", Vector3(-12.85, 0, z - 1.2), Vector3(-12.2, 2.2, z + 1.2))
		_bd.box("screen", Vector3(-12.18, 1.5, z), Vector3(0.02, 0.25, 0.8))
	_bx("hazard", Vector3(-1.8, 0.0, -33.8), Vector3(1.8, 0.01, -33.0), false)
	_label("TECHNIK  /  EBENE -1", Vector3(0, 4.2, -3.84), 180.0, 64, Color(0.85, 0.82, 0.7), 0.007)
	_label("ZU DEN UNTERKUENFTEN", Vector3(0, 3.6, -33.84), 0.0, 40, Color(0.85, 0.82, 0.7), 0.006)

func _build_stairway() -> void:
	# Gang z -34..-50 mit Treppe hinab auf -3
	_bx("concrete", Vector3(-2.3, YL, -50.0), Vector3(-2.0, 3.5, -34.0))
	_bx("concrete", Vector3(2.0, YL, -50.0), Vector3(2.3, 3.5, -34.0))
	_bx("concrete", Vector3(-2.3, 3.2, -50.0), Vector3(2.3, 3.5, -34.0))
	_stairs(-2.0, 2.0, -50.0, YL, -40.0, 0.0)
	for z: float in [-41.0, -44.0, -47.0]:
		_bx("steel_dark", Vector3(-1.98, 0.9 + (z + 40.0) * 0.3, z - 1.4), Vector3(-1.9, 0.98 + (z + 40.0) * 0.3, z + 1.4), false)
		_bx("steel_dark", Vector3(1.9, 0.9 + (z + 40.0) * 0.3, z - 1.4), Vector3(1.98, 0.98 + (z + 40.0) * 0.3, z + 1.4), false)

func _bunk(x: float, z: float) -> void:
	_col(Vector3(x - 0.48, YL, z - 1.0), Vector3(x + 0.48, YL + 1.85, z + 1.0))
	for cx: float in [-0.44, 0.44]:
		for cz: float in [-0.96, 0.96]:
			_bx("steel_dark", Vector3(x + cx - 0.03, YL, z + cz - 0.03), Vector3(x + cx + 0.03, YL + 1.85, z + cz + 0.03), false)
	for y: float in [0.45, 1.5]:
		_bx("steel_dark", Vector3(x - 0.47, YL + y - 0.05, z - 0.98), Vector3(x + 0.47, YL + y, z + 0.98), false)
		_bx("mattress", Vector3(x - 0.42, YL + y, z - 0.94), Vector3(x + 0.42, YL + y + 0.14, z + 0.94), false)
		_bx("blanket", Vector3(x - 0.43, YL + y + 0.1, z - 0.5), Vector3(x + 0.43, YL + y + 0.17, z + 0.94), false)

func _build_dorms() -> void:
	# Schlafsaele x -11..11, z -50..-72, Decke 0.5
	_wall_x(-50.0, -11.15, 11.15, YL, 0.5, [[0.0, 4.0, 3.5]])
	_bx("concrete", Vector3(-2.3, 0.5, -50.15), Vector3(2.3, 3.5, -49.85))
	_wall_z(-11.0, -50.0, -72.0, YL, 0.5)
	_wall_z(11.0, -50.0, -72.0, YL, 0.5)
	_wall_x(-72.0, -11.15, 11.15, YL, 0.5, [[0.0, 3.0, 2.6]])
	_bx("concrete", Vector3(-11.15, 0.5, -72.15), Vector3(11.15, 0.8, -49.85))
	for x: float in [-8.6, -5.2, 5.2, 8.6]:
		for z: float in [-54.0, -57.8, -66.0, -69.6]:
			_bunk(x, z)
	# Spinde an den Seitenwaenden
	for sx: float in [-1.0, 1.0]:
		for z: float in [-52.5, -61.5, -62.7]:
			_bx("paint_green", Vector3(sx * 10.85 - 0.3, YL, z - 0.55), Vector3(sx * 10.85 + 0.3, YL + 1.9, z + 0.55))
	# Tische in der Gasse zwischen den Reihen
	_bx("wood", Vector3(-2.9, YL + 0.72, -62.9), Vector3(-1.5, YL + 0.78, -61.1))
	_col(Vector3(-2.9, YL, -62.9), Vector3(-1.5, YL + 0.78, -61.1))
	_bx("paper", Vector3(-2.6, YL + 0.78, -62.4), Vector3(-2.1, YL + 0.8, -61.9), false)
	_bx("wood", Vector3(1.6, YL, -64.0), Vector3(2.8, YL + 0.9, -63.0))     # umgekippter Tisch (Deckung)
	# Kabelkanaele unter der Decke
	for x: float in [-6.9, 6.9]:
		_bx("steel_dark", Vector3(x - 0.15, 0.2, -71.8), Vector3(x + 0.15, 0.4, -50.2), false)
	_label("UNTERKUNFT  GARDE", Vector3(0, -0.2, -50.3), 0.0, 44, Color(0.8, 0.78, 0.66), 0.006)

func _build_corridor() -> void:
	# Kommandokorridor x -2.5..2.5, z -72..-80
	_bx("concrete", Vector3(-2.65, YL, -80.0), Vector3(-2.35, 0.3, -72.0))
	_bx("concrete", Vector3(2.35, YL, -80.0), Vector3(2.65, 0.3, -72.0))
	_bx("concrete", Vector3(-2.65, 0.0, -80.0), Vector3(2.65, 0.3, -72.0))
	for z: float in [-74.5, -77.5]:
		_bx("steel_dark", Vector3(-2.36, YL, z - 0.7), Vector3(-2.3, YL + 2.2, z + 0.7), false)   # verriegelte Seitentueren
		_bx("steel_dark", Vector3(2.3, YL, z - 0.7), Vector3(2.36, YL + 2.2, z + 0.7), false)
	_bx("hazard", Vector3(-1.5, YL, -79.9), Vector3(1.5, YL + 0.01, -79.4), false)
	_label("LAGEZENTRUM", Vector3(0, YL + 2.75, -72.3), 0.0, 44, Color(0.85, 0.8, 0.6), 0.006)

func _build_situation_room() -> void:
	# Lagezentrum x -14..14, z -80..-104, Decke 2.0
	_wall_x(-80.0, -14.15, 14.15, YL, 2.0, [[0.0, 3.0, 2.6]])
	_wall_z(-14.0, -80.0, -104.0, YL, 2.0)
	_wall_z(14.0, -80.0, -104.0, YL, 2.0)
	_wall_x(-104.0, -14.15, 14.15, YL, 2.0, [[0.0, 3.0, 2.8]])
	_bx("concrete_dark", Vector3(-14.15, 2.0, -104.15), Vector3(14.15, 2.3, -79.85))
	# Kartentisch (grosse Lagekarte)
	_bx("steel_dark", Vector3(-3.0, YL, -95.0), Vector3(3.0, YL + 0.95, -89.0))
	_bx("map", Vector3(-2.9, YL + 0.95, -94.9), Vector3(2.9, YL + 0.98, -89.1), false)
	for i in 6:
		_bx("emerg_red", Vector3(-2.0 + float(i) * 0.8, YL + 0.98, -92.6 + float(i % 3) * 0.7), Vector3(-1.85 + float(i) * 0.8, YL + 1.0, -92.45 + float(i % 3) * 0.7), false)
	# Saeulen
	for p: Vector3 in [Vector3(-7, 0, -86), Vector3(7, 0, -86), Vector3(-7, 0, -98), Vector3(7, 0, -98)]:
		_bx("concrete", Vector3(p.x - 0.5, YL, p.z - 0.5), Vector3(p.x + 0.5, 2.0, p.z + 0.5))
		_bx("hazard", Vector3(p.x - 0.52, YL, p.z - 0.52), Vector3(p.x + 0.52, YL + 0.3, p.z + 0.52), false)
	# Sandsack-Riegel und Konsolen an den Seitenwaenden
	for sx: float in [-1.0, 1.0]:
		_bx("canvas_white", Vector3(sx * 10.5 - 0.5, YL, -94.5), Vector3(sx * 10.5 + 0.5, YL + 1.0, -89.5))
		for z: float in [-84.0, -88.0, -96.0, -100.0]:
			_bx("steel_dark", Vector3(sx * 13.85 - 0.45, YL, z - 1.0), Vector3(sx * 13.85 + 0.45, YL + 1.1, z + 1.0))
			_bd.box("screen" if int(z) % 8 == 0 else "screen_red", Vector3(sx * 13.4, YL + 1.5, z), Vector3(0.02, 0.5, 1.6))
	# Lagewand (grosse Bildschirme ueber der Panzertuer)
	for i in 3:
		_bd.box("screen" if i != 1 else "screen_red", Vector3(-6.0 + float(i) * 6.0 if i != 1 else 6.5, 0.9, -103.82), Vector3(3.6, 1.6, 0.04))
	_label("LAGEZENTRUM", Vector3(-6.0, 0.9, -103.78), 0.0, 48, Color(0.05, 0.15, 0.08), 0.006)
	_label("KONTROLLRAUM", Vector3(0, YL + 3.1, -103.82), 0.0, 40, Color(0.9, 0.85, 0.7), 0.006)

func _build_control_room() -> void:
	# Kontrollraum x -8..8, z -104..-116, Decke 0.5; Notausgang Ost bei z -110
	_wall_z(-8.0, -104.0, -116.0, YL, 0.5)
	_wall_z(8.0, -104.0, -116.0, YL, 0.5, [[-110.0, 1.4, 2.3]])
	_wall_x(-116.0, -8.15, 8.15, YL, 0.5)
	_bx("concrete", Vector3(-8.15, 0.5, -116.15), Vector3(8.15, 0.8, -103.85))
	# Konsolenreihe und Schaltpult
	_bx("steel_dark", Vector3(-7.0, YL, -115.85), Vector3(7.0, YL + 1.0, -114.6))
	for i in 7:
		_bd.box("screen" if i % 3 != 1 else "screen_red", Vector3(-6.0 + float(i) * 2.0, YL + 1.6, -115.8), Vector3(1.6, 0.9, 0.04))
	_bx("steel_dark", Vector3(-1.5, YL, -112.2), Vector3(1.5, YL + 0.95, -111.4))         # Zuendpult
	_bx("hazard", Vector3(-1.45, YL + 0.95, -112.15), Vector3(1.45, YL + 0.97, -111.45), false)
	_bd.box("alarm", Vector3(0.0, YL + 1.02, -111.8), Vector3(0.18, 0.08, 0.18))
	_bx("steel_dark", Vector3(4.2, YL + 0.75, -108.8), Vector3(6.2, YL + 0.8, -107.6))   # Tisch (Akte)
	for lx in [4.28, 6.07]:
		for lz in [-108.72, -107.73]:
			_bx("steel_dark", Vector3(lx, YL, lz), Vector3(lx + 0.05, YL + 0.75, lz + 0.05), false)   # Tischbeine
	_col(Vector3(4.2, YL, -108.8), Vector3(6.2, YL + 0.8, -107.6))
	_bx("steel_dark", Vector3(-7.85, YL, -110.0), Vector3(-7.2, YL + 2.2, -106.0))       # Aktenschrank
	_label("ZUENDUNG", Vector3(0, YL + 0.6, -111.38), 0.0, 26, Color(1.0, 0.75, 0.2), 0.004)
	# Notausgang (dunkler Gang nach Osten)
	_bx("concrete", Vector3(8.0, YL, -108.5), Vector3(12.0, YL + 2.4, -108.2))
	_bx("concrete", Vector3(8.0, YL, -111.8), Vector3(12.0, YL + 2.4, -111.5))
	_bx("concrete", Vector3(8.0, YL + 2.3, -111.8), Vector3(12.0, YL + 2.6, -108.2))
	_bx("black", Vector3(12.0, YL, -111.8), Vector3(12.3, YL + 2.6, -108.2))
	_label("NOTAUSGANG SPREE", Vector3(7.84, YL + 2.45, -110.0), -90.0, 26, Color(0.3, 1.0, 0.45), 0.004)

func _build_lights() -> void:
	var red := Color(1.0, 0.1, 0.06)
	var amber := Color(1.0, 0.55, 0.2)
	var cold := Color(0.72, 0.85, 1.0)
	# Roehre: wenige Notleuchten, kalt und nass
	for z: float in [30.0, 18.0, 7.0]:
		_omni(Vector3(0.0, 2.6, z), red if z < 10.0 else Color(0.55, 0.65, 0.75), 0.9, 7.0, 0.8)
		_bd.box("emerg_red" if z < 10.0 else "lamp_dead", Vector3(0.0, 2.95, z), Vector3(0.25, 0.08, 0.5))
	_flicker_lamp(Vector3(0.0, 2.95, 24.0))
	# Schleuse: rot, Warnleuchte
	_omni(Vector3(0.0, 2.8, 0.0), red, 1.6, 7.0, 1.0)
	_rot_light(Vector3(0.0, 3.05, -3.6))
	# Technik: Bernstein an den Generatoren, kalte Roehren, rote Notlichter
	for p: Vector3 in [Vector3(-7.5, 3.2, -13.0), Vector3(7.5, 3.2, -25.0)]:
		_omni(p, amber, 1.4, 10.0, 1.0)
	for p: Vector3 in [Vector3(-11.5, 5.5, -6.0), Vector3(11.5, 5.5, -32.0), Vector3(11.5, 5.5, -10.0), Vector3(-11.5, 5.5, -30.0)]:
		_omni(p, red, 1.5, 12.0, 1.0)
		_bd.box("emerg_red", p + Vector3(0, 0.3, 0), Vector3(0.3, 0.12, 0.3))
	_flicker_lamp(Vector3(0.0, 6.9, -12.0))
	_flicker_lamp(Vector3(-3.0, 6.9, -22.0))
	_flicker_lamp(Vector3(3.5, 6.9, -29.0))
	_omni(Vector3(0.0, 6.5, -19.0), cold, 0.6, 14.0, 0.5)
	_exit_sign(Vector3(0, 3.35, -33.84), 0.0)
	# Gang/Treppe
	_omni(Vector3(0.0, 2.8, -37.0), red, 1.2, 7.0, 0.8)
	_omni(Vector3(0.0, 1.0, -47.0), red, 1.0, 7.0, 0.8)
	# Schlafsaele: Notlicht, einzelne Roehren
	for p: Vector3 in [Vector3(-9.5, 0.1, -51.0), Vector3(9.5, 0.1, -51.0), Vector3(-9.5, 0.1, -71.0), Vector3(9.5, 0.1, -71.0)]:
		_omni(p, red, 1.2, 9.0, 0.8)
		_bd.box("emerg_red", p + Vector3(0, 0.3, 0), Vector3(0.3, 0.1, 0.2))
	_flicker_lamp(Vector3(0.0, 0.45, -56.0))
	_flicker_lamp(Vector3(0.0, 0.45, -67.0))
	_omni(Vector3(0.0, 0.0, -62.0), cold, 0.45, 9.0, 0.4)
	# Korridor
	_omni(Vector3(0.0, -0.4, -76.0), red, 1.3, 7.0, 0.9)
	_rot_light(Vector3(0.0, -0.1, -79.5))
	# Lagezentrum: rotes Notlicht, kaltes Licht ueber dem Kartentisch, Rundumleuchten
	_omni(Vector3(0.0, 1.4, -92.0), cold, 1.2, 10.0, 0.8)
	for p: Vector3 in [Vector3(-12.0, 1.5, -82.0), Vector3(12.0, 1.5, -82.0), Vector3(-12.0, 1.5, -102.0), Vector3(12.0, 1.5, -102.0)]:
		_omni(p, red, 1.5, 13.0, 1.0)
	_rot_light(Vector3(-7.0, 1.85, -92.0))
	_rot_light(Vector3(7.0, 1.85, -92.0))
	_flicker_lamp(Vector3(-4.0, 1.95, -84.0))
	_flicker_lamp(Vector3(5.0, 1.95, -100.0))
	_exit_sign(Vector3(-12.0, YL + 2.6, -80.17), 180.0)
	# Kontrollraum: kaltes Bildschirmlicht, Riedhammer gut sichtbar
	_omni(Vector3(0.0, 0.1, -112.0), cold, 1.3, 9.0, 0.6)
	_omni(Vector3(0.0, YL + 1.6, -114.0), Color(0.3, 0.9, 0.55), 0.7, 6.0, 0.4)
	_omni(Vector3(5.0, 0.1, -108.0), amber, 0.6, 6.0, 0.4)
	_omni(Vector3(10.0, YL + 2.0, -110.0), Color(0.25, 1.0, 0.45), 0.4, 4.0, 0.5)
	_bd.build(world)

func _exit_sign(pos: Vector3, yaw: float) -> void:
	var mi := Geo.box_mesh_node(Vector3(0.62, 0.22, 0.05), mats["exit_green"], pos, Vector3(0, yaw, 0))
	add_child(mi)
	var l := _label("NOTAUSGANG", pos + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 0.03), yaw, 22, Color(0.05, 0.2, 0.08), 0.0035)
	l.render_priority = 1
	_omni(pos + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, -0.1, 0.4), Color(0.25, 1.0, 0.45), 0.35, 3.5, 0.6)

func _flicker_lamp(pos: Vector3) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(2.2, 2.3, 2.4)
	var mi := Geo.box_mesh_node(Vector3(0.3, 0.05, 1.3), m, pos)
	add_child(mi)
	var l := _omni(pos + Vector3(0, -0.4, 0), Color(0.85, 0.92, 1.0), 1.3, 8.0, 0.7, false)
	_flicker.append([l, m, randf() * 10.0])

## Rote Rundumleuchte: drehender Spot + Gehaeuse.
func _rot_light(pos: Vector3) -> void:
	add_child(Geo.box_mesh_node(Vector3(0.2, 0.18, 0.2), _alarm_mat, pos))
	var pivot := Node3D.new()
	pivot.position = pos + Vector3(0, -0.05, 0)
	add_child(pivot)
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.12, 0.05)
	l.light_energy = 3.0
	l.spot_range = 12.0
	l.spot_angle = 28.0
	l.light_volumetric_fog_energy = 2.0
	l.shadow_enabled = false
	l.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	pivot.add_child(l)
	_rot_lights.append([pivot, 4.0 + randf()])

func _build_skyline() -> void:
	pass

func _build_atmosphere() -> void:
	# Dampf in der Technik, Dunst ueber dem Wasser, Rauch im Lagezentrum
	Props.fog_volume(self, Vector3(0, 1.0, 20.0), Vector3(4, 2, 32), 0.04, Color(0.55, 0.6, 0.62))
	Props.fog_volume(self, Vector3(-7.5, 3.5, -13.0), Vector3(6, 7, 8), 0.06, Color(0.8, 0.8, 0.82))
	Props.fog_volume(self, Vector3(7.5, 3.5, -25.0), Vector3(6, 7, 8), 0.06, Color(0.8, 0.8, 0.82))
	Props.fog_volume(self, Vector3(0, 3.5, -19.0), Vector3(26, 7, 30), 0.02, Color(0.6, 0.6, 0.62))
	Props.fog_volume(self, Vector3(0, YL + 1.6, -61.0), Vector3(22, 3.5, 22), 0.02, Color(0.5, 0.48, 0.48))
	Props.fog_volume(self, Vector3(0, YL + 2.5, -92.0), Vector3(28, 5, 24), 0.025, Color(0.5, 0.47, 0.47))

func _build_set_piece_geometry() -> void:
	pass

func _build_end_block() -> void:
	pass

# ------------------------------------------------------------------ Marker, Route

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(0.0, 0.1, 32.0), "player_spawn")
	ps.name = "PlayerSpawn"
	var route: Array = [
		Vector3(0, 0, 26.0), Vector3(0, 0, 14.0), Vector3(0, 0, 5.0), Vector3(0, 0, 0.0),
		Vector3(0, 0, -7.0), Vector3(-3.8, 0, -14.0), Vector3(-3.6, 0, -23.0), Vector3(0, 0, -31.0),       # 4-7 Technik
		Vector3(0, 0, -36.0), Vector3(0, 0, -39.5), Vector3(0, YL, -51.5),                                 # 8-10 Treppe
		Vector3(0, YL, -57.0), Vector3(2.0, YL, -62.0), Vector3(0, YL, -68.5), Vector3(0, YL, -74.0),       # 11-14 Schlafsaele
		Vector3(0, YL, -79.0), Vector3(0, YL, -83.0),                                                      # 15-16 Korridor
		Vector3(-9.5, YL, -84.5), Vector3(-10.8, YL, -92.0), Vector3(-9.5, YL, -100.5), Vector3(0, YL, -101.5),
		Vector3(9.5, YL, -100.5), Vector3(10.8, YL, -92.0), Vector3(9.5, YL, -84.5), Vector3(0, YL, -86.5),
		Vector3(-5.0, YL, -97.0), Vector3(0, YL, -102.0),                                                  # 17-26 Lagezentrum
	]
	for i in route.size():
		var w := Geo.marker(m, (route[i] as Vector3) + Vector3(0, 0.05, 0), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	# Checkpoints
	_trigger("CpSchleuse", Vector3(0, 1.5, 2.0), Vector3(5.6, 3, 1.5), _on_lock)
	_trigger("CpTechnik", Vector3(0, 1.5, -6.0), Vector3(6.0, 3, 1.5), _on_enter_tech)
	_trigger("TArmored", Vector3(0, 1.5, -12.0), Vector3(25.0, 3, 1.5), _on_tech_mid)
	_trigger("TGang", Vector3(0, 1.5, -36.0), Vector3(4.0, 3, 1.5), _on_enter_gang)
	_trigger("TDorms", Vector3(0, YL + 1.5, -52.0), Vector3(6.0, 3, 1.5), _on_enter_dorms)
	_trigger("TDormsMid", Vector3(0, YL + 1.5, -62.0), Vector3(21.0, 3, 1.5), _on_dorms_mid)
	_trigger("TKommando", Vector3(0, YL + 1.5, -74.0), Vector3(4.6, 3, 1.5), _on_enter_corridor)
	_trigger("TLage", Vector3(0, YL + 1.5, -81.5), Vector3(6.0, 3, 1.5), _on_enter_hall)
	_end_area = _trigger("LevelEnd", Vector3(0.0, YL + 1.5, -106.5), Vector3(4.0, 3, 2.0), _on_enter_control, false)
	_end_area.add_to_group("level_end")
	_end_area.monitoring = false
	# Munition
	Pickup.place_ammo_crate(self, Vector3(-1.2, 0.0, 9.0), 90.0)
	Pickup.place_ammo_crate(self, Vector3(-11.8, 0.0, -14.5), 90.0)
	Pickup.place_ammo_crate(self, Vector3(1.2, 0.0, -38.0), 0.0)
	Pickup.place_ammo_crate(self, Vector3(-3.0, YL, -71.2), 0.0)
	Pickup.place_ammo_crate(self, Vector3(1.9, YL, -73.0), -90.0)
	Pickup.place_ammo_crate(self, Vector3(-13.0, YL, -92.0), 90.0)
	Pickup.place_ammo_crate(self, Vector3(13.0, YL, -92.0), -90.0)

func _bake_nav() -> void:
	preload("res://game/systems/destructible_placements.gd").place(self)  # zerstoerbare Deckung (systeme-c), vor dem Bake
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1 | 16
	nm.filter_baking_aabb = AABB(Vector3(-15.0, -4.0, -117.0), Vector3(30.0, 12.0, 155.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

# ------------------------------------------------------------------ Tueren und Figuren

func _door_body(size: Vector3, pos: Vector3, mat: Material) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.set_meta("no_fit", true)
	b.add_child(Geo.box_mesh_node(size, mat, Vector3(0, size.y * 0.5, 0)))
	for y: float in [0.5, size.y * 0.5, size.y - 0.4]:
		b.add_child(Geo.box_mesh_node(Vector3(size.x - 0.2, 0.1, size.z + 0.06), mats["hazard"], Vector3(0, y, 0)))
	Geo.add_box_shape(b, Vector3(0, size.y * 0.5, 0), size)
	add_child(b)
	b.position = pos
	return b

func _build_doors() -> void:
	var steel := Geo.flat(Color(0.2, 0.21, 0.22), 0.45, 0.7)
	_inner_door = _door_body(Vector3(2.1, 2.45, 0.3), Vector3(0, 0, -4.0), steel)
	_blast = _door_body(Vector3(3.1, 2.85, 0.5), Vector3(0, YL, -104.0), steel)
	_hatch = _door_body(Vector3(0.12, 2.3, 1.5), Vector3(8.0, YL, -110.0), Geo.flat(Color(0.25, 0.27, 0.26), 0.5, 0.5))

func _open_inner_door() -> void:
	var tw := create_tween()
	tw.tween_property(_inner_door, "position:x", 2.2, 1.6).set_trans(Tween.TRANS_QUAD)
	VF.play_at(self, "rail_metal_creak", Vector3(0, 1.5, -4.0), -2.0, 8.0, 50.0, 0.8)
	VF.play_at(self, "overwatch_steam_loop", Vector3(0, 2.0, -3.5), -6.0, 6.0, 30.0, 1.3)

func _open_blast() -> void:
	var tw := create_tween()
	tw.tween_property(_blast, "position:x", -3.1, 2.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func() -> void: _end_area.set_deferred("monitoring", true))
	VF.play_at(self, "rail_metal_creak", Vector3(0, YL + 1.5, -104.0), 0.0, 10.0, 60.0, 0.6)

## Box-Figur (Mantel/Uniform, Muetze). Arme/Beine als Pivots fuer einfache Posen.
func _build_figures() -> void:
	# Riedhammer am Zuendpult (schaut zur Tuer), Weber am Tisch mit dem Aktenkoffer
	_ried = VIP.build(self, "riedhammer", Vector3(0.0, YL, -113.0), 0.0)
	_weber = VIP.build(self, "weber", Vector3(5.2, YL, -109.6), 35.0)
	_case = Node3D.new()
	# Koffer am Griff in Webers rechter Hand (Hand-Node folgt Armpose und Modell)
	var hand_r := (_weber["hands"] as Array)[1] as Node3D
	hand_r.add_child(_case)
	_case.position = Vector3(0.02, -0.135, 0.045)
	_case.add_child(Geo.box_mesh_node(Vector3(0.1, 0.32, 0.45), mats["leather"], Vector3.ZERO))
	_case.add_child(Geo.box_mesh_node(Vector3(0.12, 0.03, 0.12), Geo.flat(Color(0.7, 0.55, 0.2), 0.4, 0.8), Vector3(0, 0.17, 0)))

func _pose(fig: Dictionary, arm_x: float, t: float) -> void:
	var tw := create_tween().set_parallel(true)
	for a: Node3D in fig["arms"]:
		tw.tween_property(a, "rotation:x", arm_x, t)

# ------------------------------------------------------------------ Gegner

func _spawn(type: String, pos: Vector3, yaw_deg: float = 180.0, acc: float = 0.6) -> Enemy:
	var scene := load(ENEMY_PATH % type) as PackedScene
	if scene == null:
		return null
	var e := scene.instantiate() as Enemy
	e.set_meta("faction", "reich")
	add_child(e)
	e.global_position = pos + Vector3(0, 0.05, 0)
	e.rotation.y = deg_to_rad(yaw_deg)
	e.accuracy_scale = acc
	return e

func _spawn_wave(index: int) -> void:
	if _waves_spawned.has(index) or not spawn_enemies:
		return
	_waves_spawned[index] = true
	wave_started.emit(index)
	match index:
		0:
			# Technikebene: Garde zwischen den Generatoren
			_spawn("rifleman", Vector3(-4.5, 0, -20.0))
			_spawn("rifleman", Vector3(5.0, 0, -28.5))
			_spawn("rifleman", Vector3(10.5, 0, -18.0), 160.0)
			_spawn("assault", Vector3(-10.5, 0, -30.0), 200.0)
			_spawn("armored", Vector3(0.5, 0, -31.5), 180.0, 0.5)
		1:
			# Schlafsaele: zwischen den Etagenbetten
			_spawn("rifleman", Vector3(-7.0, YL, -62.0))
			_spawn("rifleman", Vector3(7.0, YL, -67.8))
			_spawn("rifleman", Vector3(0.5, YL, -70.5))
			_spawn("assault", Vector3(-3.5, YL, -59.5), 170.0)
			_spawn("assault", Vector3(6.9, YL, -56.0), 190.0)
			_spawn("officer", Vector3(-1.0, YL, -66.5), 180.0, 0.5)
		2:
			# Kommandokorridor: Gepanzerter haelt den Durchgang
			_spawn("armored", Vector3(0.0, YL, -77.5), 180.0, 0.5)
			_spawn("rifleman", Vector3(1.4, YL, -79.0), 180.0)
		3:
			# Lagezentrum: Oberst Falk im schweren Anzug + letzte Garde
			_spawn_falk()
			_spawn("armored", Vector3(-9.0, YL, -97.0), 160.0, 0.5)
			_spawn("armored", Vector3(9.0, YL, -97.0), 200.0, 0.5)
			_spawn("rifleman", Vector3(-12.0, YL, -88.0), 150.0)
			_spawn("rifleman", Vector3(12.0, YL, -88.0), 210.0)
		4:
			# Falk ruft Verstaerkung (durch die Seitentueren des Korridors)
			_spawn("assault", Vector3(-1.2, YL, -76.0), 180.0)
			_spawn("rifleman", Vector3(1.2, YL, -75.0), 180.0)

func _spawn_falk() -> void:
	var scene := load(ENEMY_PATH % "juggernaut") as PackedScene
	if scene == null:
		return
	var j := scene.instantiate() as Enemy
	j.set_meta("faction", "reich")
	j.name = "OberstFalk"
	add_child(j)
	j.global_position = Vector3(0.0, YL + 0.05, -99.5)
	j.rotation.y = 0.0
	_falk = j
	var hud := AHUD.get_hud(j)
	if hud != null:
		var ticks: Array[float] = [0.75, 0.5, 0.25]
		hud.call("set_boss", j, "OBERST FALK", ticks)
		j.set("_hud_set", true)
	if j.has_method("_engage"):
		j.call("_engage")
	var pl := _player()
	if pl != null:
		j.call("alert", pl.global_position)

func _on_enemy_damaged(enemy: Node, _amount: float) -> void:
	if enemy != _falk or _falk_half or _falk == null:
		return
	if float(_falk.get("health")) <= float(_falk.get("max_health")) * 0.5:
		_falk_half = true
		_pa("Weber hat immer gesagt, Sie geben nicht auf. Da hatte er recht. Mit allem anderen nicht.")
		_spawn_wave(4)

func _on_enemy_killed(enemy: Node) -> void:
	if enemy != _falk or _falk_dead:
		return
	_falk_dead = true
	_say(StoryData.FALK, "Der General … wird Sie … enttäuschen …", 3.4)
	_say(StoryData.LENA, "Falk ist erledigt. Ich hab die Panzertür zum Kontrollraum – sie geht auf.")
	_obj("Stelle Riedhammer im Kontrollraum")
	_later(2.5, func() -> void:
		_checkpoint("cp_kontroll")
		_open_blast())

# ------------------------------------------------------------------ Story

func _intro() -> void:
	_obj("Folge der Röhre unter der Spree zur Bunkerschleuse")
	_say(StoryData.VOSS, "Kerner, Voss hier. Das ist die alte Versorgungsröhre unter der Spree. Sie endet an der Bunkerschleuse – ab da sind Sie allein.")
	_say(StoryData.LENA, "Ich bin in der Haustechnik. Die Schleusen hängen am Notstromnetz. Ich krieg sie auf, aber nicht leise.")

func _on_lock() -> void:
	_checkpoint("cp_schleuse")
	_say(StoryData.KERNER, "Bin an der Schleuse.")
	_say(StoryData.LENA, "Druckausgleich läuft … drei Sekunden. Dahinter liegt die Technikebene.")
	_later(3.0, func() -> void:
		_open_inner_door()
		_obj("Kämpf dich durch die Technikebene"))

func _on_enter_tech() -> void:
	_pa("Kerner. Durch die Röhre, wie eine Ratte. Riedhammer hat gewettet, dass Sie das nicht wagen. Ich nicht.")

func _on_tech_mid() -> void:
	_say(StoryData.LENA, "Gepanzerter hinten bei den Generatoren. Kopf und Gelenke, Jonas.")

func _on_enter_gang() -> void:
	_spawn_wave(1)
	_obj("Säubere die Schlafsäle")
	_pa("Meine Männer haben hier unten geschlafen, gegessen, gewartet. Sie schlafen nicht mehr.")

func _on_enter_dorms() -> void:
	_checkpoint("cp_schlafsaal")

func _on_dorms_mid() -> void:
	_spawn_wave(2)
	_say(StoryData.LENA, "Der Kontrollraum liegt ganz am Ende, hinter dem Lagezentrum. Die Lüftung zeigt zwei Wärmequellen da drin.")

func _on_enter_corridor() -> void:
	_checkpoint("cp_kommando")
	_obj("Dring ins Lagezentrum vor")
	_say(StoryData.VOSS, "Kerner, oben kommen wir nicht durch die Panzertür. Was jetzt passiert, liegt bei Ihnen.")

func _on_enter_hall() -> void:
	if _waves_spawned.has(3):
		return
	_spawn_wave(3)
	_obj("Besiege Oberst Falk")
	_pa("Sie wollten mich sehen, Kerner. Hier bin ich.")
	_say(StoryData.LENA, "Das ist Falk – im schweren Anzug! Erst das Visier, dann der Tornister auf dem Rücken.")

# ------------------------------------------------------------------ Kontrollraum

func _on_enter_control() -> void:
	if _scene_started:
		return
	_scene_started = true
	_control_scene(false)

func _begin_cine(look: Vector3) -> void:
	_cine = true
	_cine_look = look
	Events.story_cinematic.emit(true)
	# Die letzte Garde legt die Waffen nieder (Voss' Leute sind im Lagezentrum)
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e != null and e.is_alive():
			e.queue_free()

func _control_scene(skip_dialog: bool) -> void:
	_obj("")
	_begin_cine(Vector3(0.0, YL + 1.6, -113.0))
	if not skip_dialog:
		# Zwischensequenz (game/cutscene): Kamerafahrt auf Riedhammer am Pult, dann Webers Auftritt im Halbdunkel.
		# Autopilot/--skip-cutscenes: sofort übersprungen. Danach geht es mit dem Spieler-Kino unten weiter.
		await _weber_reveal_cutscene()
		if not is_inside_tree():
			return
		_cine_look = Vector3(0.0, YL + 1.6, -113.0)
		_say(StoryData.KERNER, "Hände auf den Kopf, General. Langsam.")
		_pose(_ried, PI * 0.92, 1.2)
		await _wait_radio(15.0)
		if not is_inside_tree():
			return
		_cine_look = (_weber["root"] as Node3D).global_position + Vector3(0, 1.6, 0)
		_say(StoryData.KERNER, "Weber. Sie haben auf mich geschossen.")
		_say(StoryData.WEBER, "Auf Ihre Weste. Ich wusste, dass Sie sie tragen.")
		_say(StoryData.KERNER, "Die Protokolle im Funkturm. Die Spur durch die Kanalisation. Das waren Sie.")
		_say(StoryData.WEBER, "Ich wollte, dass ihr sie findet. Allein wäre ich nie an ihn herangekommen.")
		_say(StoryData.WEBER, "Das ist die Akte Nordlicht. Wer Riedhammer bezahlt hat, Konto für Konto. Damit fallen nicht nur Uniformen.")
		_say(StoryData.LENA, "Jonas, er hat Leute verraten. Unsere Leute. Vergiss das nicht.")
		_say(StoryData.WEBER, "Nehmen Sie mich fest, und ich sage vor Gericht aus. Lassen Sie mich gehen, und ich erledige den Rest auf meine Art.")
		await _wait_radio(80.0)
		if not is_inside_tree():
			return
	_cine_look = (_weber["root"] as Node3D).global_position + Vector3(0, 1.6, 0)
	_begin_decision()

## Webers Auftritt als Kamerafahrt (ersetzt die ersten beiden Dialogblöcke; Zeilen unverändert).
func _weber_reveal_cutscene() -> void:
	var ried := _ried["root"] as Node3D
	var weber := _weber["root"] as Node3D
	var pl := _player()
	var head := Vector3(0, 1.62, 0)
	var cs := Cutscene.new()
	cs.keep_letterbox = true     # das Spieler-Kino (_cine) läuft danach weiter, _begin_decision blendet aus
	# 1) Über die Schulter des Spielers langsam auf Riedhammer am Zündpult zu
	cs.shot(null, Vector3(-1.4, YL + 1.72, -108.4), 7.0, {"look": ried, "look_offset": head, "fov": 46.0,
		"shake": 0.28, "dof": true, "async": true})
	cs._say(StoryData.VOSS, "Kerner, meine Leute sind im Lagezentrum. Die Garde legt die Waffen nieder.")
	cs._say(StoryData.RIEDHAMMER, "Keinen Schritt weiter, Kerner. Ein Knopfdruck, und der Spreebogen fliegt in die Luft.")
	# 2) Schwenk ins Halbdunkel: Weber tritt vor (Gegenschuss von Riedhammers Seite)
	cs.shot(null, Vector3(1.3, YL + 1.5, -112.3), 2.6, {"look": weber, "look_offset": head, "fov": 40.0,
		"ease": Tween.EASE_IN_OUT, "trans": Tween.TRANS_CUBIC, "async": true})
	cs.aim(weber, ried, 1.2)
	cs._say(StoryData.WEBER, "Die Zündleitung ist tot, Herr General. Ich habe sie vor einer Stunde selbst gekappt.")
	# 3) Schnitt auf Riedhammer (aus Webers Blickwinkel)
	cs.cut(Vector3(3.6, YL + 1.68, -110.7), {"look": ried, "look_offset": head, "fov": 38.0})
	cs.aim(ried, weber, 0.9)
	cs._say(StoryData.RIEDHAMMER, "Weber … Sie Verräter.")
	# 4) Langsamer Push-in auf Weber
	cs.cut(Vector3(1.0, YL + 1.55, -112.0), {"look": weber, "look_offset": head, "fov": 42.0})
	cs.shot(null, Vector3(2.3, YL + 1.6, -111.2), 7.0, {"fov": 34.0, "async": true})
	cs._say(StoryData.WEBER, "Ich wollte nie, dass diese Stadt brennt. Das war immer der Unterschied zwischen uns.")
	cs._say(StoryData.RIEDHAMMER, "Dann ist es vorbei.")
	# 5) Zurück in den Blick des Spielers (auf Riedhammer, wo das Spieler-Kino weitermacht)
	cs.call_step(func() -> void: _cine_look = ried.global_position + Vector3(0, 1.6, 0), true)
	if pl != null:
		cs.shot(null, pl.get_camera(), 1.4, {"look": ried, "look_offset": Vector3(0, 1.6, 0), "fov": pl.get_camera().fov,
			"shake": 0.0, "dof": false})
	await cs.play(self)

func _begin_decision() -> void:
	Events.story_cinematic.emit(false)
	_obj("Entscheide über Weber")
	_build_decision_ui()
	_deciding = true
	_decide_t = 0.0
	print("[bunker] Entscheidung offen")

func _build_decision_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "BunkerChoice"
	_ui.layer = 30
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.02, 0.025, 0.86)
	sb.border_color = Color(0.85, 0.2, 0.12, 0.9)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.62
	panel.anchor_bottom = 0.62
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var title := Label.new()
	title.text = "WEBER – DEINE ENTSCHEIDUNG"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.35, 0.25))
	vb.add_child(title)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 60)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	for pair: Array in [["[E]", "Festnehmen"], ["[F]", "Gehen lassen"]]:
		var l := Label.new()
		l.text = "%s  %s" % [pair[0], pair[1]]
		l.add_theme_font_size_override("font_size", 34)
		l.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
		hb.add_child(l)

func _choose(choice: String) -> void:
	if not _deciding:
		return
	_deciding = false
	_choice = choice
	if _ui != null:
		_ui.queue_free()
		_ui = null
	_obj("")
	var st := get_node_or_null("/root/Settings")
	if st != null:
		st.call("set_value", CHOICE_KEY, choice)
	print("[bunker] Entscheidung: %s (gespeichert unter %s)" % [choice, CHOICE_KEY])
	Events.story_cinematic.emit(true)
	if choice == "arrest":
		_say(StoryData.KERNER, "Sie sind festgenommen, Weber. Die Akte geht ans Gericht – und Sie auch.")
		_say(StoryData.WEBER, "Wie Sie meinen. Passen Sie gut auf sie auf. Es gibt Leute, die dafür töten würden.")
		_say(StoryData.LENA, "Voss' Leute kommen runter. Es ist vorbei, Jonas.")
		# Weber legt den Koffer auf den Tisch und hebt die Haende
		var w := _weber["root"] as Node3D
		_case.reparent(self)
		var tw := create_tween()
		tw.tween_property(_case, "global_position", Vector3(5.2, YL + 0.97, -108.2), 0.8)
		tw.parallel().tween_property(_case, "rotation", Vector3(0, 0, PI * 0.5), 0.8)
		tw.tween_callback(func() -> void: _pose(_weber, PI * 0.92, 1.0))
		tw.tween_property(w, "rotation:y", deg_to_rad(10.0), 0.6)
	else:
		_say(StoryData.KERNER, "Gehen Sie, Weber. Bevor ich es mir anders überlege.")
		_say(StoryData.WEBER, "Sie werden von mir hören, Kerner. Oder von denen, die auf der Liste stehen.")
		_say(StoryData.LENA, "Du hast ihn laufen lassen? Jonas …")
		_say(StoryData.KERNER, "Hoffentlich war es das Richtige.")
		_weber_leaves()
	await _wait_radio(60.0)
	if not is_inside_tree():
		return
	# Riedhammer ergibt sich nicht: Granate, Explosion, Flucht, Schwarzbild (Zwischensequenz)
	await _riedhammer_finale()
	if not is_inside_tree():
		return
	await get_tree().create_timer(1.0, false).timeout
	_on_level_end()

## Finale: Riedhammer zieht eine Granate und sprengt sich mit dem Kontrollraum. Kerner (und Lena am Funk)
## kommen raus; Druckwelle, Schwarzbild, letzte Zeilen im Dunkeln. Danach Levelende -> Epilog-Tafeln.
## Überspringen/Autopilot: Explosion und Riedhammers Tod werden trotzdem ausgeführt (always-Callbacks).
func _riedhammer_finale() -> void:
	var ried := _ried["root"] as Node3D
	var arms: Array = _ried["arms"]
	var arm_l := arms[0] as Node3D
	var arm_r := arms[1] as Node3D
	var pl := _player()
	var head := Vector3(0, 1.62, 0)
	var door := Vector3(0.0, YL, -105.0)
	var nade := Node3D.new()
	nade.name = "RiedGrenade"
	var cs := Cutscene.new()
	cs.keep_letterbox = true
	cs.keep_fade = true
	# 1) Riedhammer lässt die Hände sinken und dreht sich zu Kerner um
	cs.cut(Vector3(-2.3, YL + 1.55, -109.2), {"look": ried, "look_offset": head, "fov": 44.0, "shake": 0.35, "dof": true})
	cs.aim(ried, door, 0.9)
	cs.pose(arm_l, "rotation:x", 0.0, 0.8)
	cs.pose(arm_r, "rotation:x", 0.0, 0.8)
	cs._say(StoryData.RIEDHAMMER, "Vor Gericht, Kerner? Damit Leute wie Sie über mich urteilen?")
	cs.shot(null, Vector3(-1.1, YL + 1.62, -110.5), 5.5, {"fov": 33.0, "async": true})
	cs._say(StoryData.RIEDHAMMER, "Nein. Ich bleibe auf meinem Posten.")
	# 2) Die Granate: Nahaufnahme der Hand
	cs.call_step(func() -> void:
		((_ried["hands"] as Array)[1] as Node3D).add_child(nade)
		nade.position = Vector3(0.0, 0.0, -0.015)
		nade.add_child(Geo.box_mesh_node(Vector3(0.09, 0.12, 0.09), Geo.flat(Color(0.2, 0.24, 0.16), 0.6), Vector3.ZERO))
		nade.add_child(Geo.box_mesh_node(Vector3(0.04, 0.05, 0.04), Geo.flat(Color(0.5, 0.5, 0.48), 0.4, 0.8), Vector3(0, 0.08, 0))))
	cs.pose(arm_r, "rotation:x", PI * 0.42, 0.35, {"async": false})
	cs.cut(Vector3(0.75, YL + 1.35, -111.3), {"look": nade, "fov": 30.0, "shake": 0.5, "dof": true})
	cs._say(StoryData.KERNER, "Granate! Raus, raus!", {"async": true, "dur": 1.5})
	cs.call_step(func() -> void:
		VF.play_at(self, "rail_metal_creak", ried.global_position + Vector3(0, 1.4, 0), -6.0, 6.0, 30.0, 1.8))
	cs.wait(1.0)
	cs._say(StoryData.LENA, "Jonas, lauf!", {"async": true, "dur": 1.4})
	# 3) Flucht: Handkamera aus Kerners Kopf durch die Panzertür ins Lagezentrum
	if pl != null:
		cs.cut(pl.get_camera(), {"look": Vector3(0.0, YL + 1.4, -96.0), "fov": 68.0, "shake": 1.2, "dof": false})
	cs.shot(null, Vector3(0.4, YL + 1.45, -101.2), 1.4, {"fov": 74.0, "trans": Tween.TRANS_QUAD, "ease": Tween.EASE_IN})
	# 4) Detonation: Feuerball, Licht, Druckwelle wirft die Kamera nach vorn, Blackout
	cs.call_step(func() -> void: _ried_detonate(ried, nade), true)
	cs.shot(null, Vector3(0.9, YL + 0.45, -99.6), 0.55, {"look": Vector3(1.5, YL - 0.4, -97.0), "fov": 80.0,
		"shake": 3.0, "trans": Tween.TRANS_EXPO, "ease": Tween.EASE_OUT, "async": true})
	cs.wait(0.35)
	cs.fade(1.0, 0.4)
	cs.wait(2.2)
	# 5) Im Dunkeln
	cs._say(StoryData.LENA, "Jonas? Jonas, hörst du mich? Sag was!")
	cs._say(StoryData.KERNER, "… Ich bin da. Riedhammer ist tot. Der Kontrollraum ist weg.")
	cs._say(StoryData.LENA, "Komm nach oben, Jonas. Die Sonne geht auf.", {"hold": 0.8})
	await cs.play(self)

## Explosion im Kontrollraum (auch beim Überspringen ausgeführt).
func _ried_detonate(ried: Node3D, nade: Node3D) -> void:
	var pos := Vector3(0.0, YL + 1.0, -112.6)
	if is_instance_valid(ried):
		pos = ried.global_position + Vector3(0, 1.0, 0)
		ried.visible = false
	if is_instance_valid(nade):
		nade.queue_free()
	var vfx := get_node_or_null("/root/VFX")
	if vfx != null:
		vfx.call("spawn_explosion", pos, 2.4)
		vfx.call("spawn_explosion", pos + Vector3(2.5, 0.4, 1.5), 1.6)
		vfx.call("spawn_dust_cloud", Vector3(0.0, YL + 0.5, -103.5), 5.0)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.62, 0.3)
	flash.light_energy = 18.0
	flash.omni_range = 26.0
	add_child(flash)
	flash.global_position = pos + Vector3(0, 0.6, 0)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 1.4).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(flash.queue_free)
	# Notbeleuchtung fällt aus
	for f: Array in _flicker:
		var l := f[0] as OmniLight3D
		if l != null and is_instance_valid(l) and l.global_position.z < -80.0:
			l.visible = false
	VF.shake_player(self, pos, 1.0, 30.0)

func _weber_leaves() -> void:
	var w := _weber["root"] as Node3D
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(_hatch, "position:z", -111.3, 1.0)
	tw.tween_property(w, "rotation:y", deg_to_rad(-90.0), 0.5)
	tw.tween_callback(func() -> void: w.set_meta("walk", true))
	tw.tween_property(w, "position", Vector3(7.2, YL, -110.0), 1.6)
	tw.tween_property(w, "position", Vector3(11.5, YL, -110.0), 2.0)
	tw.tween_callback(func() -> void:
		w.visible = false
		w.set_meta("walk", false)
		VF.play_at(self, "overwatch_door_slam", Vector3(8.0, YL + 1.2, -110.0), -4.0, 8.0, 40.0)
		var t2 := create_tween()
		t2.tween_property(_hatch, "position:z", -110.0, 0.5))

## Bot-Wahl: --bunker-choice hat Vorrang, sonst deterministisch nach Skill.
func _bot_choice() -> String:
	var c := str(Game.arg("bunker-choice", ""))
	if c in ["arrest", "release"]:
		return c
	return "release" if str(Game.arg("skill", "average")) == "novice" else "arrest"

# ------------------------------------------------------------------ Debug-Start

func _debug_start(phase: String) -> void:
	var pl := _player()
	_inner_door.position.x = 2.2
	for i in 3:
		_waves_spawned[i] = true
	for n in get_tree().get_nodes_in_group("enemy"):
		(n as Node).queue_free()
	for id: String in ["cp_schleuse", "cp_schlafsaal"]:
		_cp_done[id] = true
	match phase:
		"boss":
			if pl != null:
				pl.global_position = Vector3(0.0, YL + 0.1, -75.0)
				pl.set_view(0.0, 0.0)
			_checkpoint("cp_kommando")
		"control", "decision", "cutscene":
			_waves_spawned[3] = true
			_waves_spawned[4] = true
			_falk_dead = true
			_blast.position.x = -3.1
			if pl != null:
				pl.global_position = Vector3(0.0, YL + 0.1, -102.5 if phase == "control" else -106.0)
				pl.set_view(0.0, 0.0)
			_checkpoint("cp_kontroll")
			if phase == "control":
				_end_area.set_deferred("monitoring", true)
			elif phase == "cutscene":
				# direkt in Webers Auftritt (Zwischensequenz) – für Capture/Tests ohne Laufweg
				_scene_started = true
				_later(0.5, func() -> void: _control_scene(false))
			else:
				_scene_started = true
				_pose(_ried, PI * 0.92, 0.1)
				_later(0.5, func() -> void: _control_scene(true))
	print("[bunker] Debug-Start: %s" % phase)

# ------------------------------------------------------------------ Laufzeit

func _process(delta: float) -> void:
	_t += delta
	for f: Array in _flicker:
		var l := f[0] as OmniLight3D
		var m := f[1] as StandardMaterial3D
		var ph: float = f[2]
		var s := sin(_t * 23.0 + ph) + sin(_t * 7.3 + ph * 2.0)
		var lit := s > -0.6 and fmod(_t + ph, 6.0) > 0.35
		l.light_energy = 1.3 if lit else 0.05
		m.albedo_color = Color(2.2, 2.3, 2.4) if lit else Color(0.2, 0.2, 0.22)
	for r: Array in _rot_lights:
		(r[0] as Node3D).rotation.y = _t * float(r[1])
	if _alarm_mat != null:
		_alarm_mat.albedo_color = Color(3.0, 0.15, 0.05) if fmod(_t, 0.9) < 0.45 else Color(0.4, 0.03, 0.01)
	if not _weber.is_empty():
		var w := _weber["root"] as Node3D
		if bool(w.get_meta("walk", false)):
			var legs: Array = _weber["legs"]
			for i in legs.size():
				(legs[i] as Node3D).rotation.x = sin(_t * 11.0 + float(i) * PI) * 0.55
	if _deciding:
		_decide_t += delta
		var auto: bool = _bot or str(Game.arg("bk-autochoose", "")) not in ["", "false", "0"]
		if auto:
			if _decide_t > 2.5:
				_choose(_bot_choice())
		elif Input.is_action_just_pressed("interact"):
			_choose("arrest")
		elif Input.is_action_just_pressed("bunker_release"):
			_choose("release")

func _physics_process(_delta: float) -> void:
	if not _cine or not _ready_done:
		return
	# Zwischensequenz/Entscheidung: Spieler eingefroren, Blick auf die Szene (Mensch und Bot)
	var pl := _player()
	if pl == null or pl.dead:
		return
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
