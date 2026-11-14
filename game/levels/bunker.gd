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
const FK = preload("res://game/levels/furniture_kit.gd")
const VF = preload("res://game/vehicles/vehicle_fx.gd")
const AHUD = preload("res://game/enemies/armor_hud.gd")
const VIP = preload("res://game/characters/vip_models.gd")

const YL := -3.0         ## Fussboden der unteren Ebene
const WK = preload("res://game/levels/overwatch_world_kit.gd")   ## pbr(): Poly-Haven-Texturordner
const BK_TEX := "res://assets/environment/bunker/textures/"     ## Bunker-Texturen (Poly Haven, CC0)
const SCREEN_SHADER = preload("res://game/levels/bunker_screen.gdshader")
enum Scr { MAP, TEXT, RADAR, ALARM, PAPER }   ## Bildinhalt der Monitore (bunker_screen.gdshader, uniform mode)
const PHOSPHOR := Color(0.35, 1.0, 0.55)   ## gruener Monitorphosphor
const AMBER_P := Color(1.0, 0.6, 0.18)     ## Bernstein-Phosphor
const RED_P := Color(1.0, 0.16, 0.1)       ## Alarm
const RED_DIM := 0.3     ## Faktor fuer rote Notleuchten (siehe _omni)
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
var _armed_lamp: StandardMaterial3D   ## blinkende Kontrollleuchte "Zuendkreis scharf" am Zuendpult
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
var _at_lock: bool = false

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
	if str(Game.arg("shots", "")) != "":   # Debug-Aufnahmen mit festen Kameras (villa_shots.gd)
		add_child(load("res://game/levels/tools/villa_shots.gd").new())
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

## Funkzeile mit StoryUI-Optionen (max_age/valid/priority/cut/key/drop_live, siehe story_ui.gd say()).
## Zeilen im selben Frame bilden ein Gespraech: jede kommt direkt nach ihrer Vorgaengerin.
func _say_opt(speaker: String, text: String, dur: float, opts: Dictionary) -> void:
	get_tree().call_group(&"story_ui", &"say", speaker, text, dur, opts)

## Restdauer laufender + wartender Funkzeilen.
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

## Falk ueber die Bunkerlautsprecher (Rueckkopplung an der naechsten Decke).
## Sticheleien verfallen, wenn sie nicht gleich drankommen.
func _pa(text: String, opts: Dictionary = {"priority": 1, "max_age": 3.0}) -> void:
	var pl := _player()
	if pl != null:
		VF.play_at(self, "berlin_pa_feedback", pl.global_position + Vector3(0, 2.6, -3.0), -8.0, 6.0, 40.0)
	_say_opt(StoryData.FALK, text, 0.0, opts)

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
	# Rotes Notlicht: entsaettigt und gedimmt (echte Sicherheitsleuchten tauchen nicht den ganzen Raum in Rot)
	if c.r > 0.9 and c.g < 0.3 and c.b < 0.3:
		c = Color(1.0, maxf(c.g, 0.24), maxf(c.b, 0.16))
		energy *= RED_DIM
		rng_ *= 0.6
		fog *= 0.5
	# Gruene Fluchtwegleuchte: nur ein Schild, kein Raumlicht
	elif c.g > 0.95 and c.r < 0.4 and c.b < 0.6:
		energy *= 0.35
		rng_ = minf(rng_, 3.5)
		fog *= 0.4
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

## Monitor: Blechgehaeuse mit Rahmen und einer Glasfront mit Shader-Inhalt (bunker_screen.gdshader) statt
## eines flachen Leuchtquaders. c = Mitte der Bildflaeche, n = Blickrichtung (waagrecht), w/h = Bildgroesse,
## kind = Scr.*, depth = Gehaeusetiefe hinter der Bildflaeche. Gedaempfte Emission, wirft keinen Schatten.
func _screen(c: Vector3, n: Vector3, w: float, h: float, kind: int, tint: Color, depth: float = 0.1) -> MeshInstance3D:
	var b := Basis(Vector3.UP, atan2(n.x, n.z))
	var fr := 0.03 + minf(w, h) * 0.025   # Rahmenbreite
	_bd.box("screen_case", c - n * (depth * 0.5), Vector3(w + fr * 2.0, h + fr * 2.0, depth), b)
	# Rahmen 1.2 cm vor der Bildflaeche, ueberdeckt deren Rand um 4 mm
	for sy: float in [-1.0, 1.0]:
		_bd.box("screen_case", c + b * Vector3(0.0, sy * (h * 0.5 + fr * 0.5 - 0.004), 0.006), Vector3(w + fr * 2.0, fr + 0.008, 0.012), b)
	for sx: float in [-1.0, 1.0]:
		_bd.box("screen_case", c + b * Vector3(sx * (w * 0.5 + fr * 0.5 - 0.004), 0.0, 0.006), Vector3(fr + 0.008, h, 0.012), b)
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	mi.mesh = q
	mi.material_override = _screen_mat(kind, tint)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(b, c + n * 0.003)
	add_child(mi)
	mi.set_instance_shader_parameter("seed", fmod(absf(c.x * 1.37 + c.z * 0.71 + c.y * 2.3), 9.0))
	mi.set_instance_shader_parameter("aspect", w / h)
	return mi

var _scr_mats: Dictionary = {}
func _screen_mat(kind: int, tint: Color) -> ShaderMaterial:
	var key := "%d|%s" % [kind, tint.to_html()]
	if not _scr_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = SCREEN_SHADER
		m.set_shader_parameter("mode", kind)
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("energy", 1.0 if kind != Scr.ALARM else 0.8)
		if kind == Scr.PAPER:   # Papierstruktur (ambientCG Paper003): Knitter, Rauheit
			m.set_shader_parameter("paper_textured", true)
			m.set_shader_parameter("paper_albedo", load(BK_TEX + "paper_creased/diffuse.jpg"))
			m.set_shader_parameter("paper_normal", load(BK_TEX + "paper_creased/normal.jpg"))
			m.set_shader_parameter("paper_rough", load(BK_TEX + "paper_creased/rough.jpg"))
			m.set_shader_parameter("paper_tiles", 1.6)
		_scr_mats[key] = m
	return _scr_mats[key]

## Papier-Lagekarte auf einer waagrechten Flaeche (Kartentisch), lit, nicht leuchtend.
func _paper_map(c: Vector3, w: float, d: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, d)
	mi.mesh = q
	mi.material_override = _screen_mat(Scr.PAPER, Color.WHITE)
	mi.rotation_degrees.x = -90.0
	mi.position = c
	add_child(mi)
	mi.set_instance_shader_parameter("seed", 2.0)
	mi.set_instance_shader_parameter("aspect", w / d)

## Box aus zwei Ecken (Optik + Kollision im gemeinsamen Koerper).
func _bx(key: String, a: Vector3, b: Vector3, collide: bool = true) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	var c := (lo + hi) * 0.5
	var s := hi - lo
	_bd.box(key, c, s)
	if collide:
		Geo.add_box_shape(_body, c, s)

## Moebel als Poly-Haven-Modell (furniture_kit.gd) in der alten Box a..b. Kollision wie bisher (collide),
## fehlt das Modell, wird der alte Quader gezeichnet.
func _fx(key: String, model: String, a: Vector3, b: Vector3, yaw: float = 0.0, opts: Dictionary = {}, collide: bool = true) -> void:
	if not FK.place_ab(_body, model, a, b, yaw, opts):
		_bx(key, a, b, collide)
	elif collide:
		_col(a, b)

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
	# Etwas neutraleres, helleres Grundlicht: ohne Nebelschleier sonst zu dunkel
	env.ambient_light_color = Color(0.27, 0.27, 0.28)   # neutral (vorher leicht violett)
	env.ambient_light_energy = 0.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_exposure = 1.3
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.sdfgi_enabled = true
	env.sdfgi_energy = 0.6
	env.ssil_intensity = 1.0
	# Innenraum: leichter Dunst. Dampf/Rauch nur lokal (FogVolumes in _build_atmosphere).
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.035, 0.04)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0012
	env.fog_sky_affect = 0.0
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.62, 0.62, 0.64)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_gi_inject = 0.12
	env.volumetric_fog_ambient_inject = 0.0
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
	_tune_interior_glow(env)

## Innenraum-Glow: nur echte Lichtquellen bluehen leicht, Deckenlampen ueberstrahlen nicht.
## Laeuft nach PostFx.apply (das Profil "night_city" setzt sonst Schwelle 1.0 / Intensitaet 0.8).
func _tune_interior_glow(env: Environment) -> void:
	env.glow_hdr_threshold = 1.8
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0

func _make_mats() -> void:
	mats = BP.materials()
	mats["concrete"] = Geo.mat("concrete_wall_008", Color(0.42, 0.43, 0.44), 0.25, 1.0)
	mats["concrete_dark"] = Geo.mat("concrete_wall_008", Color(0.32, 0.33, 0.34), 0.25, 0.8)
	mats["concrete_wet"] = Geo.mat("concrete_wall_008", Color(0.28, 0.3, 0.3), 0.3, 0.35)
	mats["rust"] = Geo.mat("rusty_metal_02", Color(0.55, 0.5, 0.46), 0.5, 1.0, 0.4)
	# Lackiertes Stahlblech (Poly Haven blue_metal_plate, entsaettigt): Konsolen, Schraenke, Rohre, Pulte
	mats["steel_dark"] = WK.pbr(BK_TEX + "painted_steel", Color(0.36, 0.38, 0.39), 0.45, 0.9)
	mats["screen_case"] = WK.pbr(BK_TEX + "painted_steel", Color(0.17, 0.18, 0.18), 0.9, 0.75)
	mats["desk_top"] = WK.matte(WK.pbr(BK_TEX + "painted_steel", Color(0.22, 0.23, 0.22), 0.7, 1.35, 0.2))   # stumpfe Pultplatte (keine Lampenspiegelung)
	# Gruen lackiertes, angerostetes Blech (Poly Haven green_metal_rust): Generatoren, Spinde
	mats["paint_green"] = WK.pbr("res://assets/environment/river/textures/green_metal_rust", Color(0.72, 0.76, 0.9), 0.4, 0.9)
	mats["floor"] = WK.pbr("res://assets/environment/river/textures/rough_concrete", Color(0.42, 0.42, 0.41), 0.35, 0.8)
	# Linoleum (Poly Haven linoleum_brown), Richtung Grauoliv getoent
	mats["linoleum"] = (WK.matte(WK.pbr(BK_TEX + "linoleum_brown", Color(0.45, 0.52, 0.55), 0.45, 0.85)) as StandardMaterial3D)
	(mats["linoleum"] as StandardMaterial3D).metallic_specular = 0.3
	# Holzkisten: verwitterte Bretter statt einfarbigem Quader
	mats["wood"] = WK.pbr("res://assets/environment/textures/weathered_planks", Color(0.75, 0.62, 0.48), 0.6, 1.0)
	# Stoffe (Leinen-Struktur): Decken, Matratzen, Sandsaecke
	mats["blanket"] = WK.pbr("res://assets/characters/textures/rough_linen", Color(0.38, 0.35, 0.22), 1.2, 1.0)
	mats["mattress"] = WK.pbr("res://assets/characters/textures/rough_linen", Color(0.8, 0.65, 0.49), 1.0, 1.0)
	mats["canvas_white"] = WK.pbr("res://assets/characters/textures/rough_linen", Color(0.97, 0.75, 0.5), 0.8, 1.0)
	# Papier (ambientCG Paper003, CC0): Knitterstruktur statt glatter Farbflaeche
	var pm := StandardMaterial3D.new()
	pm.albedo_texture = load(BK_TEX + "paper_creased/diffuse.jpg")
	pm.albedo_color = Color(0.86, 0.84, 0.78)
	pm.normal_enabled = true
	pm.normal_texture = load(BK_TEX + "paper_creased/normal.jpg")
	pm.roughness_texture = load(BK_TEX + "paper_creased/rough.jpg")
	pm.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	pm.metallic_specular = 0.3
	pm.uv1_triplanar = true
	pm.uv1_world_triplanar = true
	pm.uv1_scale = Vector3.ONE * 1.8
	mats["paper"] = pm
	# Schreibunterlage des Kartentischs: dunkelgruenes Leder (Poly Haven brown_leather, umgetoent)
	mats["map"] = WK.pbr(BK_TEX + "brown_leather", Color(0.3, 0.38, 0.32), 0.9, 1.05)
	# Kartennadeln: lackierte Stecknadelkoepfe (lit, nicht leuchtend)
	mats["pin_red"] = Geo.flat(Color(0.62, 0.06, 0.04), 0.35)
	mats["hazard"] = Geo.flat(Color(0.75, 0.6, 0.08), 0.6)
	# Leder (Poly Haven brown_leather, CC0): Aktenkoffer, dunkel getoent
	mats["leather"] = WK.pbr(BK_TEX + "brown_leather", Color(0.42, 0.33, 0.28), 1.6, 0.9)
	mats["water"] = Geo.flat(Color(0.05, 0.07, 0.07), 0.02, 0.2)
	(mats["water"] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(mats["water"] as StandardMaterial3D).albedo_color = Color(0.06, 0.08, 0.08, 0.72)
	mats["exit_green"] = BP.unshaded(Color(0.15, 2.4, 0.6))
	mats["emerg_red"] = BP.unshaded(Color(1.5, 0.12, 0.08))
	mats["amber"] = BP.unshaded(Color(2.6, 1.2, 0.2))
	mats["screen"] = BP.unshaded(Color(0.25, 0.9, 0.55))
	mats["screen_red"] = BP.unshaded(Color(1.1, 0.15, 0.1))
	mats["lamp_dead"] = Geo.flat(Color(0.25, 0.25, 0.26), 0.4)
	mats["lamp_on"] = BP.unshaded(Color(1.6, 1.52, 1.4))
	_alarm_mat = StandardMaterial3D.new()
	_alarm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_alarm_mat.albedo_color = Color(1.8, 0.15, 0.05)
	mats["alarm"] = _alarm_mat
	# Stahltueren: Poly Haven metal_plate (Rob Tuytel, CC0), dunkel lackiertes Stahlblech
	mats["door_steel"] = WK.pbr(BK_TEX + "metal_plate", Color(0.4, 0.42, 0.42), 0.5, 1.0, 0.6)
	# Kontrollraum-Ausstattung: verzinkte Kabeltrassen, hellgraue Schaltschraenke, Kabel, Loeschwasserrohr, Schilder
	mats["galv"] = WK.pbr(BK_TEX + "metal_plate", Color(0.62, 0.64, 0.63), 0.8, 1.0, 0.7)
	mats["cab_grey"] = WK.pbr(BK_TEX + "painted_steel", Color(0.62, 0.64, 0.6), 0.45, 0.9)
	mats["cable"] = Geo.flat(Color(0.05, 0.05, 0.05), 0.7)
	mats["pipe_red"] = Geo.flat(Color(0.48, 0.07, 0.05), 0.5)
	mats["sign_white"] = Geo.flat(Color(0.86, 0.86, 0.82), 0.6)
	# Realismus-Durchgang Lagezentrum/Technik (Poly Haven, CC0): Schalungsbeton mit Ankerloechern,
	# gruen gestrichener Sockelanstrich, Estrich mit abgetretener Bodenfarbe
	# Optik 14.11.: Beton neutral grau statt gelbstichig (Textur ist warm -> Blauanteil im Tint gleicht aus)
	mats["bk_wall"] = WK.pbr(BK_TEX + "concrete_wall_004", Color(0.72, 0.73, 0.82), 0.45, 1.0)
	mats["bk_wall_dark"] = WK.pbr(BK_TEX + "concrete_wall_004", Color(0.52, 0.53, 0.59), 0.45, 1.0)
	# Sockelanstrich an den Waenden: gedecktes Graugruen (vorher sattes Gruen, faerbte per GI die Raeume ein)
	mats["bk_dado"] = WK.pbr(BK_TEX + "painted_concrete", Color(0.86, 0.68, 0.8), 0.5, 0.9)
	# Saeulen: neutral grauer Anstrich (Textur gruen -> Tint gleicht auf Grau ab), dunkle Abschlusslinie
	mats["bk_dado_col"] = WK.pbr(BK_TEX + "painted_concrete", Color(1.0, 0.68, 0.9), 0.5, 0.9)
	mats["dado_line_col"] = Geo.flat(Color(0.13, 0.13, 0.13), 0.6)
	# Estrich: Poly Haven concrete_floor_worn_001 (CC0) - neutral grauer, abgetretener Zementestrich mit
	# Kratzern statt der fast schwarz-braunen concrete_floor_painted (Boden war kaum lesbar); leichter
	# Glanz (metallic_specular), damit die Deckenroehren sich matt im Boden abzeichnen
	mats["bk_floor"] = WK.matte(WK.pbr("res://assets/environment/curfew/textures/concrete_floor_worn_001", Color(1.2, 1.2, 1.18), 0.25, 0.9))
	(mats["bk_floor"] as StandardMaterial3D).metallic_specular = 0.3
	mats["bk_ceiling"] = WK.pbr(BK_TEX + "concrete_wall_004", Color(0.44, 0.45, 0.5), 0.35, 1.0)
	mats["dado_line"] = Geo.flat(Color(0.14, 0.18, 0.15), 0.6)
	mats["duct"] = WK.pbr(BK_TEX + "metal_plate", Color(0.55, 0.57, 0.56), 0.6, 0.8, 0.75)
	mats["pipe_blue"] = Geo.flat(Color(0.1, 0.2, 0.36), 0.5)
	mats["pipe_yellow"] = Geo.flat(Color(0.62, 0.5, 0.08), 0.55)
	mats["emerg_white"] = BP.unshaded(Color(1.7, 1.75, 1.6))

func _build_ground() -> void:
	_make_mats()
	_bd = BP.Builder.new(mats)
	_bd.no_shadow.append_array(["water", "exit_green", "emerg_red", "amber", "screen", "screen_red", "alarm", "lamp_on", "emerg_white"])
	_body = Geo.static_body()
	_body.name = "Bunker"
	_body.set_meta("no_fit", true)
	world.add_child(_body)
	_bx("concrete_wet", Vector3(-2.2, -0.3, 4.0), Vector3(2.2, 0.0, 36.8))          # Roehre
	_bx("floor", Vector3(-3.15, -0.3, -4.0), Vector3(3.15, 0.0, 4.0))               # Schleuse
	_bx("bk_floor", Vector3(-13.15, -0.3, -34.0), Vector3(13.15, 0.0, -4.0))        # Technik
	_bx("concrete_dark", Vector3(-2.0, -0.3, -40.0), Vector3(2.0, 0.0, -34.0))      # Gang
	_bx("linoleum", Vector3(-11.15, YL - 0.3, -72.0), Vector3(11.15, YL, -50.0))    # Schlafsaele
	_bx("floor", Vector3(-2.5, YL - 0.3, -80.0), Vector3(2.5, YL, -72.0))           # Korridor
	_bx("bk_floor", Vector3(-14.15, YL - 0.3, -104.0), Vector3(14.15, YL, -80.0))   # Lagezentrum
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
	_screen(Vector3(-2.585, 1.6, 1.05), Vector3.RIGHT, 0.46, 0.17, Scr.TEXT, RED_P, 0.02)
	_bd.box("alarm", Vector3(0.0, 3.1, -3.7), Vector3(0.25, 0.15, 0.25))
	_label("SCHLEUSE 2", Vector3(0, 2.85, 3.84), 180.0, 52, Color(0.85, 0.8, 0.6), 0.006)
	_label("DRUCKAUSGLEICH", Vector3(-2.57, 1.35, 1.05), 90.0, 26, Color(1.0, 0.3, 0.2), 0.004)

func _build_tech() -> void:
	# Technikebene x -13..13, z -4..-34, Hoehe 7
	_wall_x(-4.0, -13.15, 13.15, 0.0, 7.0, [[0.0, 6.3, 3.5]], "bk_wall")
	_wall_z(-13.0, -4.0, -34.0, 0.0, 7.0, [], "bk_wall")
	_wall_z(13.0, -4.0, -34.0, 0.0, 7.0, [], "bk_wall")
	_wall_x(-34.0, -13.15, 13.15, 0.0, 7.0, [[0.0, 4.0, 3.2]], "bk_wall")
	_bx("bk_ceiling", Vector3(-13.15, 7.0, -34.15), Vector3(13.15, 7.3, -3.85))
	_build_tech_dressing()
	# Generatoren (Deckung) mit Auspuffrohren zur Decke
	for p: Vector3 in [Vector3(-7.5, 0, -13.0), Vector3(7.5, 0, -13.0), Vector3(-7.5, 0, -25.0), Vector3(7.5, 0, -25.0)]:
		_bx("paint_green", p + Vector3(-1.5, 0, -2.6), p + Vector3(1.5, 2.4, 2.6))
		_bx("steel_dark", p + Vector3(-1.6, 0, -2.7), p + Vector3(1.6, 0.25, 2.7), false)
		_bx("rust", p + Vector3(-1.2, 2.4, -2.0), p + Vector3(1.2, 2.9, 0.5), false)
		_bx("rust", p + Vector3(-0.25, 2.9, 1.2), p + Vector3(0.25, 7.0, 1.7), false)
		_screen(p + Vector3(signf(-p.x) * 1.505, 1.6, -1.6), Vector3(signf(-p.x), 0, 0), 0.46, 0.28, Scr.TEXT, AMBER_P, 0.03)
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
		_screen(Vector3(-12.185, 1.5, z), Vector3.RIGHT, 0.74, 0.3, Scr.TEXT if z != -19.0 else Scr.RADAR, PHOSPHOR, 0.02)
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
	if not FK.place_ab(_body, "wooden_table_02", Vector3(-2.9, YL, -62.9), Vector3(-1.5, YL + 0.78, -61.1), 90.0, {"scale": 1.0, "stretch": 1.25}):
		_bx("wood", Vector3(-2.9, YL + 0.72, -62.9), Vector3(-1.5, YL + 0.78, -61.1))
	_col(Vector3(-2.9, YL, -62.9), Vector3(-1.5, YL + 0.78, -61.1))
	_bx("paper", Vector3(-2.6, YL + 0.78, -62.4), Vector3(-2.1, YL + 0.8, -61.9), false)
	_fx("wood", "wooden_table_02", Vector3(1.6, YL, -64.0), Vector3(2.8, YL + 0.9, -63.0), 0.0, {"tilt": Vector3(90.0, 0.0, 0.0)})     # umgekippter Tisch (Deckung)
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
		_bx("door_steel", Vector3(-2.36, YL, z - 0.7), Vector3(-2.3, YL + 2.2, z + 0.7), false)   # verriegelte Seitentueren
		_bx("door_steel", Vector3(2.3, YL, z - 0.7), Vector3(2.36, YL + 2.2, z + 0.7), false)
	_bx("hazard", Vector3(-1.5, YL, -79.9), Vector3(1.5, YL + 0.01, -79.4), false)
	_label("LAGEZENTRUM", Vector3(0, YL + 2.75, -72.3), 0.0, 44, Color(0.85, 0.8, 0.6), 0.006)

func _build_situation_room() -> void:
	# Lagezentrum x -14..14, z -80..-104, Decke 2.0
	_wall_x(-80.0, -14.15, 14.15, YL, 2.0, [[0.0, 3.0, 2.6]], "bk_wall")
	_wall_z(-14.0, -80.0, -104.0, YL, 2.0, [], "bk_wall")
	_wall_z(14.0, -80.0, -104.0, YL, 2.0, [], "bk_wall")
	_wall_x(-104.0, -14.15, 14.15, YL, 2.0, [[0.0, 3.0, 2.8]], "bk_wall")
	_bx("bk_ceiling", Vector3(-14.15, 2.0, -104.15), Vector3(14.15, 2.3, -79.85))
	# Kartentisch (grosse Lagekarte): Kollision wie bisher, Optik als Stahlkorpus mit Sockel,
	# Schubladenfronten, umlaufender Kante und Griffleiste
	_col(Vector3(-3.0, YL, -95.0), Vector3(3.0, YL + 0.95, -89.0))
	_bd.box("black", Vector3(0.0, YL + 0.06, -92.0), Vector3(5.6, 0.12, 5.6))                      # zurueckgesetzter Sockel
	_bd.box("steel_dark", Vector3(0.0, YL + 0.5, -92.0), Vector3(5.86, 0.76, 5.86))               # Korpus
	_bd.box("desk_top", Vector3(0.0, YL + 0.915, -92.0), Vector3(6.0, 0.07, 6.0))                 # Tischkante
	for s: float in [-1.0, 1.0]:
		for i in 4:
			var off := -2.1 + float(i) * 1.4
			_bd.box("screen_case", Vector3(off, YL + 0.55, -92.0 + s * 2.935), Vector3(1.28, 0.5, 0.02))   # Schubladenfronten N/S
			_bd.box("galv", Vector3(off, YL + 0.74, -92.0 + s * 2.955), Vector3(0.36, 0.03, 0.03))       # Griffe
			_bd.box("screen_case", Vector3(s * 2.935, YL + 0.55, -92.0 + off), Vector3(0.02, 0.5, 1.28))   # Schubladenfronten O/W
			_bd.box("galv", Vector3(s * 2.955, YL + 0.74, -92.0 + off), Vector3(0.03, 0.03, 0.36))
	_bx("map", Vector3(-2.9, YL + 0.95, -94.9), Vector3(2.9, YL + 0.98, -89.1), false)
	_paper_map(Vector3(0.0, YL + 0.982, -92.0), 5.7, 5.7)
	for i in 6:
		_bd.box("pin_red", Vector3(-1.95 + float(i) * 0.8, YL + 0.995, -92.55 + float(i % 3) * 0.7), Vector3(0.035, 0.025, 0.035))   # Kartennadel
	# Saeulen
	var col_i := 0
	for p: Vector3 in [Vector3(-7, 0, -86), Vector3(7, 0, -86), Vector3(-7, 0, -98), Vector3(7, 0, -98)]:
		col_i += 1
		_col(Vector3(p.x - 0.5, YL, p.z - 0.5), Vector3(p.x + 0.5, 2.0, p.z + 0.5))
		_column_dressing(p, col_i)
	# Sandsack-Riegel und Konsolen an den Seitenwaenden
	for sx: float in [-1.0, 1.0]:
		# 3 m statt 5 m: der lange Riegel wirkte wie ein Tisch und verstellte den Seitengang zur Panzertuer
		_bx("canvas_white", Vector3(sx * 10.5 - 0.5, YL, -93.5), Vector3(sx * 10.5 + 0.5, YL + 1.0, -90.5))
		for z: float in [-84.0, -88.0, -96.0, -100.0]:
			_bx("steel_dark", Vector3(sx * 13.85 - 0.45, YL, z - 1.0), Vector3(sx * 13.85 + 0.45, YL + 1.1, z + 1.0))
			var k: int = [Scr.TEXT, Scr.RADAR, Scr.MAP, Scr.TEXT][[-84.0, -88.0, -96.0, -100.0].find(z)]
			var tn: Color = RED_P if int(z) % 8 != 0 and sx > 0.0 else (AMBER_P if k == Scr.TEXT else PHOSPHOR)
			_screen(Vector3(sx * 13.4, YL + 1.55, z), Vector3(-sx, 0, 0), 1.5, 0.62, k, tn, 0.14)
	# Lagewand (grosse Bildschirme ueber der Panzertuer)
	_screen(Vector3(-6.0, 0.9, -103.84), Vector3.BACK, 3.4, 1.5, Scr.MAP, PHOSPHOR, 0.12)
	_screen(Vector3(6.0, 0.9, -103.84), Vector3.BACK, 2.6, 1.5, Scr.RADAR, PHOSPHOR, 0.12)
	_screen(Vector3(0.0, 1.3, -103.84), Vector3.BACK, 1.9, 0.7, Scr.TEXT, AMBER_P, 0.1)
	_label("LAGE BERLIN-MITTE  04:38", Vector3(-6.0, 1.54, -103.83), 0.0, 32, Color(0.3, 0.75, 0.42), 0.005)
	_label("KONTROLLRAUM", Vector3(0, YL + 3.1, -103.82), 0.0, 40, Color(0.9, 0.85, 0.7), 0.006)
	_build_situation_dressing()

func _build_control_room() -> void:
	# Kontrollraum x -8..8, z -104..-116, Decke 0.5; Notausgang Ost bei z -110
	_wall_z(-8.0, -104.0, -116.0, YL, 0.5)
	_wall_z(8.0, -104.0, -116.0, YL, 0.5, [[-110.0, 1.4, 2.3]])
	_wall_x(-116.0, -8.15, 8.15, YL, 0.5)
	_bx("concrete", Vector3(-8.15, 0.5, -116.15), Vector3(8.15, 0.8, -103.85))
	# Konsolenreihe und Schaltpult
	_bx("steel_dark", Vector3(-7.0, YL, -115.85), Vector3(7.0, YL + 1.0, -114.6))
	var kinds: Array = [Scr.MAP, Scr.ALARM, Scr.TEXT, Scr.RADAR, Scr.ALARM, Scr.TEXT, Scr.MAP]
	var tints: Array = [PHOSPHOR, RED_P, AMBER_P, PHOSPHOR, RED_P, PHOSPHOR, AMBER_P]
	for i in 7:
		var sc := Vector3(-6.0 + float(i) * 2.0, YL + 1.6, -115.8)
		_screen(sc, Vector3.BACK, 1.6, 0.9, kinds[i], tints[i], 0.14)
		if kinds[i] == Scr.ALARM:
			_label("WARNUNG  -  ZUENDKREIS", sc + Vector3(0, 0.36, 0.012), 0.0, 22, Color(0.85, 0.22, 0.14), 0.004)
	_bx("steel_dark", Vector3(-1.5, YL, -112.2), Vector3(1.5, YL + 0.95, -111.4))         # Zuendpult
	# Pultplatte lackierter Stahl, nur ein gelber Warnrahmen statt vollflaechigem Gelb
	_bx("desk_top", Vector3(-1.45, YL + 0.95, -112.15), Vector3(1.45, YL + 0.965, -111.45), false)
	for zz: float in [-112.15, -111.5]:
		_bx("hazard", Vector3(-1.45, YL + 0.965, zz), Vector3(1.45, YL + 0.97, zz + 0.05), false)
	for xx: float in [-1.45, 1.4]:
		_bx("hazard", Vector3(xx, YL + 0.965, -112.1), Vector3(xx + 0.05, YL + 0.97, -111.5), false)
	for i in 5:   # Kippschalter mit Schutzkappen links und rechts des Zuendknopfs
		for sx: float in [-1.0, 0.55]:
			var px := sx + float(i) * 0.11
			_bd.box("steel_dark", Vector3(px, YL + 0.985, -111.95), Vector3(0.06, 0.03, 0.08))
			_bd.box("lamp_dead", Vector3(px, YL + 1.01, -111.95), Vector3(0.012, 0.03, 0.012))
			# Kontrollleuchte hinter jedem Schalter: links Kreise klar (gruen), rechts Sprengladungen (bernstein)
			var lc := Color(0.35, 1.0, 0.45) if sx < 0.0 else Color(1.0, 0.62, 0.18)
			_pilot_lamp(Vector3(px, YL + 0.968, -112.06), lc, not (sx > 0.0 and i == 4))
	_build_firing_button(Vector3(0.0, YL + 0.965, -111.85))
	if not FK.place_ab(_body, "metal_office_desk", Vector3(4.2, YL, -108.8), Vector3(6.2, YL + 0.8, -107.6), 0.0, {"scale": 1.0}):
		_bx("steel_dark", Vector3(4.2, YL + 0.75, -108.8), Vector3(6.2, YL + 0.8, -107.6))   # Tisch (Akte)
		for lx in [4.28, 6.07]:
			for lz in [-108.72, -107.73]:
				_bx("steel_dark", Vector3(lx, YL, lz), Vector3(lx + 0.05, YL + 0.75, lz + 0.05), false)   # Tischbeine
	_col(Vector3(4.2, YL, -108.8), Vector3(6.2, YL + 0.8, -107.6))
	_bx("steel_dark", Vector3(-7.85, YL, -110.0), Vector3(-7.2, YL + 2.2, -106.0))       # Aktenschrank
	_label("ZUENDUNG", Vector3(0, YL + 0.6, -111.38), 0.0, 26, Color(1.0, 0.75, 0.2), 0.004)
	# Notausgang (dunkler Gang nach Osten)
	_bx("bk_wall", Vector3(8.0, YL, -108.5), Vector3(12.0, YL + 2.4, -108.2))
	_bx("bk_wall", Vector3(8.0, YL, -111.8), Vector3(12.0, YL + 2.4, -111.5))
	_bx("bk_ceiling", Vector3(8.0, YL + 2.3, -111.8), Vector3(12.0, YL + 2.6, -108.2))
	# Gangende: Kollision wie bisher, Optik als Stahl-Fluchttuer mit Zarge und Panikstange
	_col(Vector3(12.0, YL, -111.8), Vector3(12.3, YL + 2.6, -108.2))
	_bx("bk_wall", Vector3(12.0, YL, -111.8), Vector3(12.3, YL + 2.6, -108.2), false)
	_bd.box("steel_dark", Vector3(11.97, YL + 1.1, -110.0), Vector3(0.06, 2.2, 1.36))            # Zarge
	_bd.box("door_steel", Vector3(11.94, YL + 1.06, -110.0), Vector3(0.05, 2.08, 1.2))           # Tuerblatt
	_bd.box("galv", Vector3(11.86, YL + 1.0, -110.0), Vector3(0.05, 0.06, 1.0))                  # Panikstange
	for zz: float in [-110.48, -109.52]:
		_bd.box("galv", Vector3(11.89, YL + 1.0, zz), Vector3(0.06, 0.1, 0.05))
	_bd.box("hazard", Vector3(11.98, YL + 2.27, -110.0), Vector3(0.02, 0.06, 2.0))
	_bd.box("bk_dado", Vector3(10.0, YL + 0.7, -108.52), Vector3(4.0, 1.4, 0.03))               # Sockelanstrich Nord
	_bd.box("bk_dado", Vector3(10.0, YL + 0.7, -111.48), Vector3(4.0, 1.4, 0.03))               # Sockelanstrich Sued
	_label("NOTAUSGANG SPREE", Vector3(7.84, YL + 2.45, -110.0), -90.0, 26, Color(0.3, 1.0, 0.45), 0.004)
	_build_control_dressing()

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
		_omni(p, red, 1.5, 13.0, 0.3)   # wenig Nebelanteil: keine roten Lichtkugeln im Dunst
	_rot_light(Vector3(-7.0, 1.85, -92.0))
	_rot_light(Vector3(7.0, 1.85, -92.0))
	_flicker_lamp(Vector3(-4.0, 1.95, -84.0))
	_flicker_lamp(Vector3(5.0, 1.95, -100.0))
	_exit_sign(Vector3(-12.0, YL + 2.6, -80.17), 180.0)
	# Kontrollraum: kaltes Bildschirmlicht, Riedhammer gut sichtbar
	_omni(Vector3(0.0, 0.1, -112.0), cold, 1.3, 9.0, 0.6)
	_omni(Vector3(0.0, YL + 1.6, -114.0), Color(0.6, 0.78, 0.72), 0.45, 6.0, 0.4)   # Bildschirmlicht, gemischt gruen/bernstein
	_omni(Vector3(5.0, 0.1, -108.0), amber, 0.6, 6.0, 0.4)
	# Schwaches Fuelllicht von vorn-unten (Pultleuchten): Deckenlicht wirft sonst einen harten
	# Kinnschatten auf den Hals, der in der Nahaufnahme wie ein dunkler Fleck wirkt
	_omni(Vector3(0.0, YL + 1.3, -110.9), Color(0.95, 0.88, 0.8), 0.3, 2.8, 0.0)
	_omni(Vector3(10.0, YL + 2.0, -110.0), Color(0.25, 1.0, 0.45), 0.4, 4.0, 0.5)
	_build_ceiling_lights()
	_build_emergency_lights()
	_bd.build(world)

## Neutrale Deckenleuchten (Leuchtstoffroehren ~4000 K auf Notstrom): tragen das Grundlicht je
## Raum, damit Beton, Moebel und Gegner lesbar sind. Rot (Notlicht, Rundumleuchten) bleibt Akzent.
## Schatten nur bei je einem Hauptlicht in Technik und Lagezentrum.
func _build_ceiling_lights() -> void:
	# Roehre und Schleuse
	for z: float in [12.0, 26.0]:
		_ceil_lamp(Vector3(0.0, 2.95, z), 0.8, 7.0)
	_ceil_lamp(Vector3(0.0, 3.15, 1.5), 0.9, 6.0)
	# Technikebene: Roehren unter den Kabeltrassen
	for x: float in [-4.0, 4.0]:
		for z: float in [-9.0, -19.0, -29.0]:
			_ceil_lamp(Vector3(x, 4.85, z), 1.4, 11.0, x < 0.0 and z == -19.0)
	# Gang mit Treppe
	for z: float in [-38.0, -46.0]:
		_ceil_lamp(Vector3(0.0, 3.15, z), 0.9, 7.0)
	# Schlafsaele
	for x: float in [-5.5, 5.5]:
		for z: float in [-55.0, -67.0]:
			_ceil_lamp(Vector3(x, 0.45, z), 1.0, 8.0)
	# Kommandokorridor
	_ceil_lamp(Vector3(0.0, -0.05, -74.0), 0.8, 6.0)
	# Lagezentrum (Falk): Grundlicht neutral, Rundumleuchten bleiben
	for x: float in [-10.0, 10.0]:
		for z: float in [-86.0, -98.0]:
			_ceil_lamp(Vector3(x, 1.95, z), 1.2, 9.5)
	_ceil_lamp(Vector3(0.0, 1.95, -84.0), 1.2, 9.5, true)
	_ceil_lamp(Vector3(0.0, 1.95, -100.0), 1.1, 9.5)
	# Kontrollraum
	for x: float in [-4.0, 4.0]:
		for z: float in [-107.5, -113.0]:
			_ceil_lamp(Vector3(x, 0.45, z), 0.9, 7.0)

func _ceil_lamp(pos: Vector3, energy: float, rng_: float, shadows: bool = false) -> void:
	_bd.box("lamp_on", pos, Vector3(0.3, 0.05, 1.25))
	var l := _omni(pos + Vector3(0, -0.35, 0), Color(1.0, 0.94, 0.86), energy * 1.4, rng_ * 1.1, 0.25, shadows)
	l.omni_attenuation = 1.3

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

## Kleine Kontrollleuchte im Pult: Chromfassung + Glaskalotte (lit, schwach selbstleuchtend, kein Bloom-Block).
func _pilot_lamp(pos: Vector3, col: Color, on: bool, mat: StandardMaterial3D = null) -> void:
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.016
	rm.bottom_radius = 0.016
	rm.height = 0.008
	rm.radial_segments = 16
	ring.mesh = rm
	ring.material_override = Geo.flat(Color(0.62, 0.62, 0.6), 0.3, 0.9)
	ring.position = pos + Vector3(0, 0.004, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var cap := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.011
	cm.height = 0.014
	cm.radial_segments = 12
	cm.rings = 6
	cap.mesh = cm
	var m := mat
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = col.darkened(0.55)
		m.roughness = 0.15
		m.emission_enabled = on
		m.emission = col
		m.emission_energy_multiplier = 1.4
	cap.material_override = m
	cap.position = pos + Vector3(0, 0.009, 0)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cap)

## Zuendtaster mit hochgeklappter Schutzkappe, Schluesselschalter und blinkender Leuchte (Zuendkreis scharf).
func _build_firing_button(c: Vector3) -> void:
	var plate := Geo.flat(Color(0.12, 0.12, 0.12), 0.55, 0.6)
	add_child(Geo.box_mesh_node(Vector3(0.2, 0.012, 0.16), plate, c + Vector3(0, 0.006, 0)))
	# Taster: roter Pilzknopf (lackiert, nicht leuchtend)
	var btn := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.028
	bm.bottom_radius = 0.03
	bm.height = 0.022
	bm.radial_segments = 20
	btn.mesh = bm
	btn.material_override = Geo.flat(Color(0.55, 0.05, 0.03), 0.3)
	btn.position = c + Vector3(0, 0.023, 0.02)
	add_child(btn)
	# Schutzkappe aufgeklappt (Scharnier hinten), Warnfarbe
	var cover := Geo.box_mesh_node(Vector3(0.09, 0.004, 0.08), mats["hazard"], Vector3.ZERO)
	var hinge := Node3D.new()
	hinge.position = c + Vector3(0, 0.016, -0.025)
	hinge.rotation_degrees.x = 70.0
	add_child(hinge)
	hinge.add_child(cover)
	cover.position = Vector3(0, 0, -0.04)
	# Schluesselschalter rechts daneben
	var key := MeshInstance3D.new()
	var km := CylinderMesh.new()
	km.top_radius = 0.014
	km.bottom_radius = 0.016
	km.height = 0.012
	key.mesh = km
	key.material_override = Geo.flat(Color(0.7, 0.68, 0.62), 0.25, 1.0)
	key.position = c + Vector3(0.075, 0.018, 0.03)
	add_child(key)
	add_child(Geo.box_mesh_node(Vector3(0.004, 0.03, 0.012), Geo.flat(Color(0.6, 0.58, 0.5), 0.3, 1.0), c + Vector3(0.075, 0.036, 0.03), Vector3(0, 35.0, 0)))
	# Blinkende Kontrollleuchte links vom Taster
	_armed_lamp = StandardMaterial3D.new()
	_armed_lamp.albedo_color = Color(0.35, 0.03, 0.02)
	_armed_lamp.roughness = 0.15
	_armed_lamp.emission_enabled = true
	_armed_lamp.emission = Color(1.0, 0.12, 0.05)
	_armed_lamp.emission_energy_multiplier = 1.8
	_pilot_lamp(c + Vector3(-0.075, 0.012, 0.03), Color.RED, true, _armed_lamp)

## Rote Rundumleuchte: drehender Spot + Gehaeuse.
func _rot_light(pos: Vector3) -> void:
	add_child(Geo.box_mesh_node(Vector3(0.2, 0.18, 0.2), _alarm_mat, pos))
	var pivot := Node3D.new()
	pivot.position = pos + Vector3(0, -0.05, 0)
	add_child(pivot)
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.2, 0.1)
	l.light_energy = 1.8
	l.spot_range = 12.0
	l.spot_angle = 28.0
	l.light_volumetric_fog_energy = 0.45
	l.shadow_enabled = false
	l.rotation_degrees = Vector3(-25.0, 0.0, 0.0)
	pivot.add_child(l)
	_rot_lights.append([pivot, 4.0 + randf()])

func _build_skyline() -> void:
	pass

func _build_atmosphere() -> void:
	# Dampf in der Technik, Dunst ueber dem Wasser, Rauch im Lagezentrum
	# Lokal und duenn: Dampf an den Generatoren, Dunst ueber dem Wasser, Gefechtsrauch im Lagezentrum.
	# Raumfuellender Nebel macht Gegner unsichtbar und ist in geschlossenen Raeumen unrealistisch.
	Props.fog_volume(self, Vector3(0, 1.0, 20.0), Vector3(4, 2, 32), 0.025, Color(0.5, 0.54, 0.56))
	Props.fog_volume(self, Vector3(-7.5, 3.5, -13.0), Vector3(5, 7, 6), 0.035, Color(0.72, 0.72, 0.74))
	Props.fog_volume(self, Vector3(7.5, 3.5, -25.0), Vector3(5, 7, 6), 0.035, Color(0.72, 0.72, 0.74))
	Props.fog_volume(self, Vector3(0, 3.5, -19.0), Vector3(26, 7, 30), 0.005, Color(0.55, 0.55, 0.57))
	# Lagezentrum: nur duenner Raumdunst. Die fruehere dichte Rauchschicht unter der Decke war unmotiviert
	# (kein Brand) und fing das rote Notlicht als farbige Nebelkugeln ein.
	Props.fog_volume(self, Vector3(0, YL + 2.5, -92.0), Vector3(28, 5, 24), 0.0035, Color(0.5, 0.49, 0.48))

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
		# Seitengaenge bei x=+-12.2 (zwischen Sandsackriegel x+-10..11 und Konsolen x+-13.4), Rueckweg
		# nordlich an den Saeulen (+-7,-86) vorbei und links am Kartentisch (x -3..3, z -95..-89) entlang
		Vector3(-9.5, YL, -84.5), Vector3(-12.2, YL, -92.0), Vector3(-9.5, YL, -100.5), Vector3(0, YL, -101.5),
		Vector3(9.5, YL, -100.5), Vector3(12.2, YL, -92.0), Vector3(9.5, YL, -84.0), Vector3(0, YL, -85.0),
		Vector3(-4.6, YL, -88.5), Vector3(-4.6, YL, -98.0), Vector3(0, YL, -102.0),                        # 17-27 Lagezentrum
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
	# Stahlblech (Poly Haven metal_plate) als Kopie mit objektbezogener Projektion: die Tueren gleiten,
	# Welt-Triplanar wuerde die Textur dabei stehen lassen. Gemeinsamer WK-Cache bleibt unveraendert.
	var steel := (WK.pbr(BK_TEX + "metal_plate", Color(0.36, 0.38, 0.38), 0.6, 1.0, 0.6) as StandardMaterial3D).duplicate() as StandardMaterial3D
	steel.uv1_world_triplanar = false
	var hatch_m := steel.duplicate() as StandardMaterial3D
	hatch_m.albedo_color = Color(0.4, 0.44, 0.41)
	_inner_door = _door_body(Vector3(2.1, 2.45, 0.3), Vector3(0, 0, -4.0), steel)
	_blast = _door_body(Vector3(3.1, 2.85, 0.5), Vector3(0, YL, -104.0), steel)
	_hatch = _door_body(Vector3(0.12, 2.3, 1.5), Vector3(8.0, YL, -110.0), hatch_m)

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
	_door_beacon()

## Offene Panzertuer hervorheben: warmes Licht im Tuerrahmen + Lichtkegel auf den Boden davor,
## damit der Weg zum Kontrollraum aus dem ganzen Lagezentrum lesbar ist.
func _door_beacon() -> void:
	if has_node("DoorBeacon"):
		return
	var root := Node3D.new()
	root.name = "DoorBeacon"
	add_child(root)
	var l := _omni(Vector3(0.0, YL + 2.3, -104.6), Color(1.0, 0.72, 0.38), 2.2, 7.5, 0.5)
	l.reparent(root)
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.82, 0.55)
	sp.light_energy = 3.0
	sp.spot_range = 7.0
	sp.spot_angle = 32.0
	sp.light_volumetric_fog_energy = 0.8
	sp.position = Vector3(0.0, YL + 2.7, -103.6)
	sp.rotation_degrees = Vector3(-62.0, 180.0, 0.0)   # schraeg nach unten, Richtung +Z ins Lagezentrum
	root.add_child(sp)

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
			_spawn("rifleman", Vector3(-8.0, 0, -18.0), 170.0)
			_spawn("rifleman", Vector3(6.0, 0, -20.0), 190.0)
		1:
			# Schlafsaele: zwischen den Etagenbetten
			_spawn("rifleman", Vector3(-7.0, YL, -62.0))
			_spawn("rifleman", Vector3(7.0, YL, -67.8))
			_spawn("rifleman", Vector3(0.5, YL, -70.5))
			_spawn("assault", Vector3(-3.5, YL, -59.5), 170.0)
			_spawn("assault", Vector3(6.9, YL, -56.0), 190.0)
			_spawn("officer", Vector3(-1.0, YL, -66.5), 180.0, 0.5)
			_spawn("rifleman", Vector3(-10.0, YL, -68.0), 160.0)
			_spawn("rifleman", Vector3(10.0, YL, -62.0), 200.0)
			_spawn("assault", Vector3(-10.0, YL, -56.0), 170.0)
		2:
			# Kommandokorridor: Gepanzerter haelt den Durchgang
			_spawn("armored", Vector3(0.0, YL, -77.5), 180.0, 0.5)
			_spawn("rifleman", Vector3(1.4, YL, -79.0), 180.0)
			# Rueckendeckung am Hallenende des Korridors
			_spawn("rifleman", Vector3(-4.0, YL, -84.0), 170.0)
			_spawn("rifleman", Vector3(4.0, YL, -84.0), 190.0)
		3:
			# Lagezentrum: Oberst Falk im schweren Anzug + letzte Garde
			_spawn_falk()
			_spawn("armored", Vector3(-9.0, YL, -97.0), 160.0, 0.5)
			_spawn("rifleman", Vector3(9.0, YL, -97.0), 200.0)   # vorher zweiter Gepanzerter (Bosskampf zog sich)
			_spawn("rifleman", Vector3(-12.0, YL, -88.0), 150.0)
			_spawn("rifleman", Vector3(12.0, YL, -88.0), 210.0)
			_spawn("rifleman", Vector3(-8.0, YL, -92.0), 165.0)
			_spawn("rifleman", Vector3(8.0, YL, -92.0), 195.0)
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
	_say_opt(StoryData.FALK, "Der General … wird Sie … enttäuschen …", 3.4, {"priority": 2, "cut": true})
	_say_opt(StoryData.LENA, "Falk ist erledigt. Ich hab die Panzertür zum Kontrollraum – sie geht auf.", 0.0, {"priority": 2})
	_obj("Stelle Riedhammer im Kontrollraum")
	_later(2.5, func() -> void:
		_checkpoint("cp_kontroll")
		_open_blast())
	_later(18.0, _control_nudge)

## Nachfass-Hinweis, wenn der Spieler nach Falks Tod im Lagezentrum zoegert (vorhandene Lena-Zeile).
func _control_nudge() -> void:
	if _scene_started or _cine:
		return
	_when_radio_free(_control_nudge_say, 6.0)

func _control_nudge_say() -> void:
	if _scene_started or _cine:
		return
	# Steht der Spieler schon an der Panzertuer, braucht er den Hinweis nicht (blockiert sonst nur
	# den Funk fuer Kerners erste Zeile im Kontrollraum)
	var pl := _player()
	if pl != null and pl.global_position.distance_to(Vector3(0.0, YL, -104.0)) < 9.0:
		return
	_say_opt(StoryData.LENA, "Der Kontrollraum liegt ganz am Ende, hinter dem Lagezentrum. Die Lüftung zeigt zwei Wärmequellen da drin.", 0.0,
		{"priority": 1, "valid": func() -> bool: return not _scene_started})

# ------------------------------------------------------------------ Story

func _intro() -> void:
	_obj("Folge der Röhre unter der Spree zur Bunkerschleuse")
	_say_opt(StoryData.VOSS, "Kerner, Voss hier. Das ist die alte Versorgungsröhre unter der Spree. Sie endet an der Bunkerschleuse – ab da sind Sie allein.", 0.0, {"priority": 1})
	_say_opt(StoryData.LENA, "Ich bin in der Haustechnik. Die Schleusen hängen am Notstromnetz. Ich krieg sie auf, aber nicht leise.", 0.0,
		{"priority": 1, "valid": func() -> bool: return not _at_lock})

func _on_lock() -> void:
	_checkpoint("cp_schleuse")
	if _at_lock:
		return
	_at_lock = true
	_when_radio_free(_lock_talk, 8.0)

func _lock_talk() -> void:
	_say_opt(StoryData.KERNER, "Bin an der Schleuse.", 0.0, {"priority": 1})
	_say_opt(StoryData.LENA, "Druckausgleich läuft … drei Sekunden. Dahinter liegt die Technikebene.", 0.0, {"priority": 1})
	_later(3.0, func() -> void:
		_open_inner_door()
		_obj("Kämpf dich durch die Technikebene"))

func _on_enter_tech() -> void:
	_pa("Kerner. Durch die Röhre, wie eine Ratte. Riedhammer hat gewettet, dass Sie das nicht wagen. Ich nicht.")

func _on_tech_mid() -> void:
	_say_opt(StoryData.LENA, "Gepanzerter hinten bei den Generatoren. Kopf und Gelenke, Jonas.", 0.0, {"priority": 2})

func _on_enter_gang() -> void:
	_spawn_wave(1)
	_obj("Säubere die Schlafsäle")
	_pa("Meine Männer haben hier unten geschlafen, gegessen, gewartet. Sie schlafen nicht mehr.")

func _on_enter_dorms() -> void:
	_checkpoint("cp_schlafsaal")

func _on_dorms_mid() -> void:
	_spawn_wave(2)
	_say_opt(StoryData.LENA, "Der Kontrollraum liegt ganz am Ende, hinter dem Lagezentrum. Die Lüftung zeigt zwei Wärmequellen da drin.", 0.0, {"priority": 1})

func _on_enter_corridor() -> void:
	_checkpoint("cp_kommando")
	_obj("Dring ins Lagezentrum vor")
	_say_opt(StoryData.VOSS, "Kerner, oben kommen wir nicht durch die Panzertür. Was jetzt passiert, liegt bei Ihnen.", 0.0, {"max_age": 4.0})

func _on_enter_hall() -> void:
	if _waves_spawned.has(3):
		return
	_spawn_wave(3)
	_obj("Besiege Oberst Falk")
	_pa("Sie wollten mich sehen, Kerner. Hier bin ich.", {"priority": 2, "cut": true})
	_say_opt(StoryData.LENA, "Das ist Falk – im schweren Anzug! Erst das Visier, dann der Tornister auf dem Rücken.", 0.0, {"priority": 2})

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
		# Hand-Node sitzt beim geriggten Modell an einem BoneAttachment3D des Handknochens (vip_models.gd)
		((_ried["hands"] as Array)[1] as Node3D).add_child(nade)
		nade.position = Vector3(0.0, 0.01, -0.01)
		_nade_model(nade))
	# Granate vor die Brust: Oberarm halb nach vorn, Ellbogen angewinkelt (Unterarmknochen ueber den VipRig)
	cs.call_step(func() -> void: _ried_elbow(1.15, 0.35))
	cs.pose(arm_r, "rotation:x", PI * 0.3, 0.35, {"async": false})
	# Nahaufnahme: Kamera erst jetzt relativ zur Granate in der Hand setzen (Handknochen steht erst nach der
	# Pose fest), leicht seitlich vor Riedhammer auf Handhoehe; Granate im oberen Bilddrittel, Gesicht
	# unscharf dahinter. Danach langsamer Push-in. DOF moderat (dof_amount), Untertitel stehen im Kinobalken.
	var nade_cam_a := Node3D.new()
	var nade_cam_b := Node3D.new()
	cs.call_step(func() -> void:
		var fwd := -ried.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.BACK
		var side := fwd.cross(Vector3.UP).normalized()
		var np := nade.global_position
		for pair: Array in [[nade_cam_a, 1.05], [nade_cam_b, 0.72]]:
			var c := pair[0] as Node3D
			if c.get_parent() == null:
				add_child(c)
			var d: float = pair[1]
			c.global_position = np + fwd * d - side * (d * 0.5) + Vector3(0, -0.12, 0)   # von seiner linken Seite: Granate frei vor dem Hintergrund, nicht vor dem Gesicht
			c.look_at(np + Vector3(0, -0.05, 0), Vector3.UP))
	cs.cut(nade_cam_a, {"look": nade, "look_offset": Vector3(0, -0.05, 0), "fov": 34.0, "shake": 0.25,
		"dof": true, "dof_amount": 0.03})
	cs._say(StoryData.KERNER, "Granate! Raus, raus!", {"async": true, "dur": 1.5})
	cs.call_step(func() -> void:
		VF.play_at(self, "rail_metal_creak", ried.global_position + Vector3(0, 1.4, 0), -6.0, 6.0, 30.0, 1.8))
	cs.shot(null, nade_cam_b, 1.6, {"fov": 30.0, "trans": Tween.TRANS_SINE, "ease": Tween.EASE_OUT})
	cs.call_step(func() -> void:
		for c: Node3D in [nade_cam_a, nade_cam_b]:
			if c.get_parent() != null:
				c.queue_free()
			else:
				c.free(), true)
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
	# Schwarzbild unter die Untertitel (StoryUi, Ebene 20) legen: die Zeilen im Dunkeln bleiben lesbar,
	# statt ~18 s stummes Schwarz (nur hier, andere Cutscenes blenden weiter alles ab)
	cs.call_step(func() -> void:
		var fl := cs.get_node_or_null("CutsceneFade") as CanvasLayer
		if fl != null:
			fl.layer = 19, true)
	cs.wait(1.2)
	# 5) Im Dunkeln
	cs._say(StoryData.LENA, "Jonas? Jonas, hörst du mich? Sag was!")
	cs._say(StoryData.KERNER, "… Ich bin da. Riedhammer ist tot. Der Kontrollraum ist weg.")
	cs._say(StoryData.LENA, "Komm nach oben, Jonas. Die Sonne geht auf.", {"hold": 0.8})
	await cs.play(self)

## Rechten Unterarm von Riedhammer beugen (rad, nur geriggtes Modell; die prozedurale Figur hat keinen Ellbogen).
func _ried_elbow(a: float, t: float) -> void:
	var root := _ried.get("root") as Node3D
	var drv := root.get_node_or_null("VipRig") if root != null else null
	if drv == null or not drv.has_method("_pose_extra"):
		return
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: drv.call("_pose_extra", "lowerarm_r", v), 0.0, a, t)

## Splittergranate (DM51-artig): ovaler Oliv-Koerper mit Rillen, Zuender, Sicherungsbuegel und Ring.
## Lokal: +y = Zuender (zur Schulter), Mitte im Griffpunkt der Faust.
static func _nade_model(nade: Node3D) -> void:
	var olive := Geo.flat(Color(0.19, 0.23, 0.15), 0.55, 0.2)
	var metal := Geo.flat(Color(0.52, 0.52, 0.5), 0.35, 0.85)
	var body := MeshInstance3D.new()
	body.mesh = VF.sphere(0.03, 0.075, 16)
	body.material_override = olive
	nade.add_child(body)
	for y: float in [-0.018, 0.0, 0.018]:
		var rib := Geo.cylinder_node(0.03 * sqrt(1.0 - pow(y / 0.0375, 2.0)) + 0.0012, 0.005, olive, Vector3(0, y, 0), Vector3.ZERO, 16)
		nade.add_child(rib)
	nade.add_child(Geo.cylinder_node(0.011, 0.024, metal, Vector3(0, 0.045, 0), Vector3.ZERO, 10))
	nade.add_child(Geo.box_mesh_node(Vector3(0.012, 0.07, 0.004), metal, Vector3(0, 0.024, 0.031), Vector3(-6, 0, 0)))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.009
	tm.outer_radius = 0.012
	ring.mesh = tm
	ring.material_override = metal
	ring.position = Vector3(0.016, 0.05, 0)
	ring.rotation_degrees = Vector3(0, 0, 90)
	nade.add_child(ring)
	for c: Node in nade.get_children():
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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
			_door_beacon()
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
		_alarm_mat.albedo_color = Color(1.8, 0.15, 0.05) if fmod(_t, 0.9) < 0.45 else Color(0.4, 0.03, 0.01)
	if _armed_lamp != null:
		_armed_lamp.emission_energy_multiplier = 1.8 if fmod(_t, 0.9) < 0.45 else 0.08
	# Webers Beine: Geh-Zyklus kommt aus dem VIP-Treiber (game/characters/vip_rig.gd, folgt dem Tween-Tempo)
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

## Ausstattung Kontrollraum (Zuendraum): Kabeltrassen, Schaltschraenke, Spinde, Rohre, Schilder.
## Freizuhalten: Eingang x +-2 / z > -106, Notausgang Ost x > 7 / z -108.5..-111.5, Kamerazone Mitte.
func _build_control_dressing() -> void:
	var IM := "res://assets/environment/interior/models/"
	var wx := 7.85   # Innenflaeche der Seitenwaende
	# --- Deckentrassen (verzinktes Blech, Kabelbuendel), an Gewindestangen abgehaengt
	for x: float in [-2.4, 2.4]:
		_bx("galv", Vector3(x - 0.2, 0.3, -115.7), Vector3(x + 0.2, 0.32, -104.4), false)
		for s: float in [-1.0, 1.0]:
			_bx("galv", Vector3(x + s * 0.2 - 0.01, 0.32, -115.7), Vector3(x + s * 0.2 + 0.01, 0.39, -104.4), false)
		for k in 4:
			_bx("cable", Vector3(x - 0.16 + float(k) * 0.085, 0.32, -115.7), Vector3(x - 0.1 + float(k) * 0.085, 0.37 - float(k % 2) * 0.015, -104.4), false)
		for z: float in [-105.0, -108.0, -111.0, -114.0, -115.5]:
			_bx("steel_dark", Vector3(x - 0.24, 0.29, z - 0.02), Vector3(x + 0.24, 0.3, z + 0.02), false)
			_bx("steel_dark", Vector3(x - 0.012, 0.3, z - 0.012), Vector3(x + 0.012, 0.5, z + 0.012), false)
	# Wandtrassen oben an beiden Seitenwaenden und an der Rueckwand
	for s: float in [-1.0, 1.0]:
		var xi := s * wx
		_bx("galv", Vector3(xi, 0.08, -115.85), Vector3(xi - s * 0.35, 0.1, -104.15), false)
		_bx("galv", Vector3(xi - s * 0.34, 0.1, -115.85), Vector3(xi - s * 0.36, 0.17, -104.15), false)
		for k in 3:
			_bx("cable", Vector3(xi - s * (0.05 + float(k) * 0.1), 0.1, -115.85), Vector3(xi - s * (0.12 + float(k) * 0.1), 0.16, -104.15), false)
	_bx("galv", Vector3(-7.85, 0.2, -115.85), Vector3(7.85, 0.22, -115.5), false)
	for k in 3:
		_bx("cable", Vector3(-7.85, 0.22, -115.82 + float(k) * 0.1), Vector3(7.85, 0.27, -115.76 + float(k) * 0.1), false)
	# --- Rohre an der Rueckwand ueber den Bildschirmen: Loeschwasser (rot) + Lueftung/Druckluft (grau)
	_pipe("pipe_red", Vector3(-7.85, -0.42, -115.7), Vector3(7.85, -0.42, -115.7), 0.065)
	_pipe("steel_dark", Vector3(-7.85, -0.18, -115.72), Vector3(7.85, -0.18, -115.72), 0.045)
	for x: float in [-7.0, -5.0, -3.0, -1.0, 1.0, 3.0, 5.0, 7.0]:
		_bx("steel_dark", Vector3(x - 0.03, -0.52, -115.85), Vector3(x + 0.03, -0.1, -115.6), false)   # Rohrschellen
	for x: float in [-5.0, 1.0, 5.0]:   # Kabelschutzrohre von der Trasse in die Konsolen (zwischen den Monitoren)
		_pipe("galv", Vector3(x, 0.2, -115.78), Vector3(x, YL + 1.0, -115.78), 0.025)
	# Absperrschieber am Loeschwasserrohr
	_pipe("pipe_red", Vector3(-6.0, -0.42, -115.5), Vector3(-6.0, -0.2, -115.5), 0.03)
	_bd.cyl("pipe_red", Vector3(-6.0, -0.18, -115.5), 0.11, 0.11, 0.02, 14)
	# --- Schaltschrankreihe an der Westwand (hellgrau lackiert), Front zeigt nach +x
	var names := ["UV 1  NOTSTROM", "UV 2  LUEFTUNG", "ZUENDKREIS  A-C"]
	for i in 3:
		var z0 := -115.6 + float(i) * 1.08
		var z1 := z0 + 1.0
		var fx := -7.2
		_bx("cab_grey", Vector3(-7.85, YL, z0), Vector3(fx, YL + 2.1, z1))
		_bx("steel_dark", Vector3(-7.85, YL, z0), Vector3(fx + 0.01, YL + 0.1, z1), false)   # Sockel
		_bx("steel_dark", Vector3(fx, YL + 0.12, (z0 + z1) * 0.5 - 0.004), Vector3(fx + 0.008, YL + 2.0, (z0 + z1) * 0.5 + 0.004), false)   # Tuerfuge
		for zh: float in [z0 + 0.42, z1 - 0.42]:   # Schwenkgriffe
			_bx("steel_dark", Vector3(fx, YL + 1.0, zh - 0.02), Vector3(fx + 0.04, YL + 1.22, zh + 0.02), false)
		for k in 5:   # Lueftungsschlitze unten
			_bx("black", Vector3(fx, YL + 0.25 + float(k) * 0.05, z0 + 0.15), Vector3(fx + 0.004, YL + 0.27 + float(k) * 0.05, z1 - 0.15), false)
		_bx("sign_white", Vector3(fx, YL + 1.72, z0 + 0.12), Vector3(fx + 0.006, YL + 1.86, z1 - 0.12), false)
		_label(names[i], Vector3(fx + 0.012, YL + 1.79, (z0 + z1) * 0.5), 90.0, 20, Color(0.08, 0.08, 0.08), 0.003)
		_bx("hazard", Vector3(fx, YL + 1.42, (z0 + z1) * 0.5 - 0.09), Vector3(fx + 0.006, YL + 1.6, (z0 + z1) * 0.5 + 0.09), false)
		_label("!", Vector3(fx + 0.012, YL + 1.5, (z0 + z1) * 0.5), 90.0, 40, Color(0.05, 0.05, 0.05), 0.003)
		for k in 3:   # Meldeleuchten gruen / bernstein / rot
			var lc: Color = [Color(0.35, 1.0, 0.45), Color(1.0, 0.62, 0.18), Color(1.0, 0.2, 0.12)][k]
			var lp := Vector3(fx + 0.004, YL + 1.98, z0 + 0.3 + float(k) * 0.2)
			_pilot_lamp_wall(lp, lc, k != 2 or i == 2)
		_pipe("galv", Vector3(-7.6, YL + 2.1, (z0 + z1) * 0.5), Vector3(-7.6, 0.08, (z0 + z1) * 0.5), 0.04)   # Kabeleinfuehrung zur Trasse
	_label("HOCHSPANNUNG  -  LEBENSGEFAHR", Vector3(-7.83, YL + 2.45, -114.0), 90.0, 24, Color(0.9, 0.2, 0.12), 0.004)
	_bx("hazard", Vector3(-7.0, YL, -115.6), Vector3(-6.94, YL + 0.006, -112.4), false)   # Sicherheitsabstand am Boden
	# Feuerloescher + Schild zwischen Schaltschraenken und Aktenschrank
	FK.place(_body, IM + "fire_extinguisher_de", Vector3(-7.62, YL, -111.2), Vector3.ZERO, 90.0, {"scale": 1.0, "stretch": 1.0, "shadows": false})
	_bx("pin_red", Vector3(-7.85, YL + 1.05, -111.38), Vector3(-7.84, YL + 1.33, -111.02), false)
	_label("F", Vector3(-7.835, YL + 1.19, -111.2), 90.0, 36, Color(0.95, 0.95, 0.9), 0.004)
	FK.place(_body, IM + "metal_toolbox", Vector3(-6.85, YL + 0.05, -112.05), Vector3.ZERO, 75.0, {"scale": 1.0, "stretch": 1.0, "shadows": false})
	# --- Spinde an der Ostwand (gruen), suedlich vom Notausgang
	for i in 4:
		var z0 := -115.6 + float(i) * 0.8
		var z1 := z0 + 0.78
		var fx := wx - 0.55
		_bx("paint_green", Vector3(fx, YL, z0), Vector3(wx, YL + 1.9, z1))
		_bx("steel_dark", Vector3(fx - 0.04, YL + 1.0, z0 + 0.12), Vector3(fx, YL + 1.12, z0 + 0.15), false)   # Griff
		for k in 4:
			_bx("black", Vector3(fx - 0.004, YL + 1.5 + float(k) * 0.05, z0 + 0.22), Vector3(fx, YL + 1.52 + float(k) * 0.05, z1 - 0.22), false)
			_bx("black", Vector3(fx - 0.004, YL + 0.2 + float(k) * 0.05, z0 + 0.22), Vector3(fx, YL + 0.22 + float(k) * 0.05, z1 - 0.22), false)
		_bx("sign_white", Vector3(fx - 0.005, YL + 1.75, z1 - 0.32), Vector3(fx, YL + 1.83, z1 - 0.2), false)
		_label(str(11 + i), Vector3(fx - 0.008, YL + 1.79, z1 - 0.26), -90.0, 18, Color(0.08, 0.08, 0.08), 0.003)
	_bx("wood", Vector3(wx - 0.5, YL + 1.9, -115.5), Vector3(wx - 0.05, YL + 2.15, -114.9), false)   # Kiste auf dem Spind
	# Stahlregal + Feuerloescher noerdlich vom Notausgang (nur flach an der Wand)
	FK.place(_body, IM + "steel_frame_shelves_01", Vector3(wx - 0.26, YL, -105.2), Vector3.ZERO, -90.0, {"scale": 0.1, "stretch": 1.0, "shadows": false})
	_col(Vector3(wx - 0.52, YL, -105.78), Vector3(wx, YL + 2.14, -104.62))
	# Regalinhalt: Munitions-/Werkzeugkisten, Werkzeugkasten, Aktenstapel
	_bx("wood", Vector3(wx - 0.48, YL + 0.29, -105.6), Vector3(wx - 0.06, YL + 0.6, -105.0), false)
	FK.place(_body, IM + "metal_toolbox", Vector3(wx - 0.26, YL + 0.8, -105.35), Vector3.ZERO, -90.0, {"scale": 1.0, "stretch": 1.0, "shadows": false})
	_bx("paint_green", Vector3(wx - 0.45, YL + 0.77, -104.95), Vector3(wx - 0.1, YL + 0.98, -104.7), false)
	for k in 3:
		_bx("paper", Vector3(wx - 0.4, YL + 1.17 + float(k) * 0.035, -105.6 + float(k) * 0.02), Vector3(wx - 0.12, YL + 1.2 + float(k) * 0.035, -105.25 + float(k) * 0.02), false)
	_bx("steel_dark", Vector3(wx - 0.46, YL + 1.17, -105.1), Vector3(wx - 0.08, YL + 1.4, -104.75), false)
	_bx("wood", Vector3(wx - 0.46, YL + 1.64, -105.55), Vector3(wx - 0.08, YL + 1.9, -104.95), false)
	FK.place(_body, IM + "fire_extinguisher_de", Vector3(wx - 0.24, YL, -107.1), Vector3.ZERO, -90.0, {"scale": 1.0, "stretch": 1.0, "shadows": false})
	_bx("pin_red", Vector3(wx - 0.01, YL + 1.05, -107.28), Vector3(wx, YL + 1.33, -106.92), false)
	_label("F", Vector3(wx - 0.015, YL + 1.19, -107.1), -90.0, 36, Color(0.95, 0.95, 0.9), 0.004)
	# Notbeleuchtung: Gitterleuchten an beiden Seitenwaenden, schwach bernstein
	for sp: Array in [[Vector3(-7.85, -0.62, -108.0), 90.0, -1.0], [Vector3(wx, -0.75, -113.6), -90.0, 1.0]]:
		FK.place(_body, IM + "industrial_caged_sconce", sp[0], Vector3.ZERO, sp[1], {"scale": 1.0, "stretch": 1.0, "shadows": false})
		_omni((sp[0] as Vector3) + Vector3(-float(sp[2]) * 0.35, 0.05, 0), Color(1.0, 0.72, 0.4), 0.35, 3.5, 0.6)
	# --- Schilder an der Nordwand (Raumseite) beiderseits der Panzertuer
	_bx("pin_red", Vector3(-4.9, YL + 1.75, -104.16), Vector3(-3.1, YL + 2.15, -104.15), false)
	_label("ZUTRITT NUR FUER BEFUGTE", Vector3(-4.0, YL + 1.95, -104.17), 180.0, 22, Color(0.95, 0.94, 0.9), 0.004)
	_bx("sign_white", Vector3(3.2, YL + 1.75, -104.16), Vector3(4.8, YL + 2.15, -104.15), false)
	_label("RAUCHEN UND OFFENES\nFEUER VERBOTEN", Vector3(4.0, YL + 1.95, -104.17), 180.0, 18, Color(0.7, 0.08, 0.05), 0.004)
	FK.place(_body, IM + "fire_alarm", Vector3(-2.3, YL + 1.35, -104.15), Vector3.ZERO, 180.0, {"scale": 1.0, "stretch": 1.0, "shadows": false})

## Gestrichener Sockelanstrich (1.5 m) mit dunkler Abschlusslinie vor einer Wandinnenflaeche (nur Optik).
## along_x: Wand verlaeuft entlang x bei z = at; sonst entlang z bei x = at. skip: [[von, bis], ...] (Tueren).
func _dado(along_x: bool, at: float, a0: float, a1: float, skip: Array = [], y0: float = YL, h: float = 1.5) -> void:
	var segs: Array = []
	var cur := a0
	for s: Array in skip:
		if float(s[0]) > cur:
			segs.append([cur, float(s[0])])
		cur = maxf(cur, float(s[1]))
	if cur < a1:
		segs.append([cur, a1])
	for s: Array in segs:
		var ln: float = float(s[1]) - float(s[0])
		var mid: float = (float(s[0]) + float(s[1])) * 0.5
		if along_x:
			_bd.box("bk_dado", Vector3(mid, y0 + h * 0.5, at), Vector3(ln, h, 0.03))
			_bd.box("dado_line", Vector3(mid, y0 + h + 0.025, at), Vector3(ln, 0.05, 0.045))
		else:
			_bd.box("bk_dado", Vector3(at, y0 + h * 0.5, mid), Vector3(0.03, h, ln))
			_bd.box("dado_line", Vector3(at, y0 + h + 0.025, mid), Vector3(0.045, 0.05, ln))

## Stahlbetonsaeule im Lagezentrum (Optik; Kollision setzt der Aufrufer): Schalungsbeton, Voute unter
## der Decke, Sockelanstrich, gelb-schwarzer Anfahrschutz, verzinkte Kantenschutzwinkel, Nummernschild.
func _column_dressing(p: Vector3, idx: int) -> void:
	var h := 2.0 - YL
	_bd.box("bk_wall", Vector3(p.x, YL + h * 0.5, p.z), Vector3(1.0, h, 1.0))
	_bd.box("bk_wall", Vector3(p.x, 1.84, p.z), Vector3(1.24, 0.32, 1.24))        # Voute
	_bd.box("bk_wall", Vector3(p.x, 1.62, p.z), Vector3(1.1, 0.12, 1.1))
	_bd.box("bk_dado_col", Vector3(p.x, YL + 0.75, p.z), Vector3(1.03, 1.5, 1.03))
	_bd.box("dado_line_col", Vector3(p.x, YL + 1.525, p.z), Vector3(1.045, 0.05, 1.045))
	_bd.box("hazard", Vector3(p.x, YL + 0.15, p.z), Vector3(1.05, 0.3, 1.05))
	for k in 4:   # schwarze Schraegstreifen auf dem Anfahrschutz
		var bs := Basis(Vector3(0, 0, 1), deg_to_rad(45.0))
		for sz: float in [-1.0, 1.0]:
			_bd.box("black", Vector3(p.x - 0.36 + float(k) * 0.24, YL + 0.15, p.z + sz * 0.527), Vector3(0.07, 0.36, 0.004), bs)
		var bx := Basis(Vector3(1, 0, 0), deg_to_rad(45.0))
		for sx: float in [-1.0, 1.0]:
			_bd.box("black", Vector3(p.x + sx * 0.527, YL + 0.15, p.z - 0.36 + float(k) * 0.24), Vector3(0.004, 0.36, 0.07), bx)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_bd.box("galv", Vector3(p.x + sx * 0.52, YL + 1.2, p.z + sz * 0.47), Vector3(0.012, 1.8, 0.11))
			_bd.box("galv", Vector3(p.x + sx * 0.47, YL + 1.2, p.z + sz * 0.52), Vector3(0.11, 1.8, 0.012))
	# Nummernschild zur Raummitte, Schalterdose mit Leerrohr zur Decke an der Nordseite
	var fs := -signf(p.x)
	_bd.box("sign_white", Vector3(p.x + fs * 0.525, -0.55, p.z), Vector3(0.01, 0.34, 0.46))
	_label("S %d" % idx, Vector3(p.x + fs * 0.535, -0.55, p.z), 90.0 * fs, 64, Color(0.08, 0.08, 0.08), 0.004)
	_bd.box("cab_grey", Vector3(p.x + 0.2, YL + 1.75, p.z + 0.54), Vector3(0.12, 0.16, 0.07))
	_bd.box("galv", Vector3(p.x + 0.2, 0.25, p.z + 0.535), Vector3(0.035, 3.3, 0.035))

func _build_situation_dressing() -> void:
	var IM := "res://assets/environment/interior/models/"
	# Gruener Sockelanstrich an allen vier Waenden (Tueren ausgespart)
	_dado(true, -80.165, -13.85, 13.85, [[-1.5, 1.5]])
	_dado(true, -103.835, -13.85, 13.85, [[-1.5, 1.5]])
	_dado(false, -13.835, -103.85, -80.15)
	_dado(false, 13.835, -103.85, -80.15)
	# Wandtrassen oben an beiden Seitenwaenden (verzinktes Blech, Kabelbuendel, Konsolen)
	for s: float in [-1.0, 1.0]:
		var xi := s * 13.85
		_bd.box("galv", Vector3(xi - s * 0.2, 1.6, -92.0), Vector3(0.4, 0.02, 23.7))
		_bd.box("galv", Vector3(xi - s * 0.4, 1.645, -92.0), Vector3(0.02, 0.09, 23.7))
		for k in 3:
			_bd.box("cable", Vector3(xi - s * (0.08 + float(k) * 0.1), 1.635 - float(k % 2) * 0.008, -92.0), Vector3(0.075, 0.05, 23.7))
		for z: float in [-81.0, -84.5, -88.0, -91.5, -95.0, -98.5, -102.0, -103.5]:
			_bd.box("steel_dark", Vector3(xi - s * 0.21, 1.58, z), Vector3(0.42, 0.03, 0.04))
		# Kabelschutzrohre von der Trasse hinab in die Konsolen
		for z: float in [-84.0, -88.0, -96.0, -100.0]:
			_bd.box("galv", Vector3(xi - s * 0.08, (1.58 + YL + 1.1) * 0.5, z + 0.75), Vector3(0.04, 1.58 - YL - 1.1, 0.04))
	# Deckentrassen ueber den Gaengen, an Gewindestangen abgehaengt
	for x: float in [-2.6, 2.6]:
		_bd.box("galv", Vector3(x, 1.7, -92.0), Vector3(0.45, 0.02, 23.6))
		for sd: float in [-1.0, 1.0]:
			_bd.box("galv", Vector3(x + sd * 0.225, 1.74, -92.0), Vector3(0.02, 0.08, 23.6))
		for k in 4:
			_bd.box("cable", Vector3(x - 0.15 + float(k) * 0.1, 1.735 - float(k % 2) * 0.008, -92.0), Vector3(0.075, 0.05, 23.6))
		for z: float in [-81.0, -84.0, -87.0, -90.0, -93.0, -96.0, -99.0, -102.0]:
			_bd.box("steel_dark", Vector3(x, 1.685, z), Vector3(0.5, 0.025, 0.04))
			for sd: float in [-1.0, 1.0]:
				_bd.box("steel_dark", Vector3(x + sd * 0.24, 1.84, z), Vector3(0.014, 0.32, 0.014))
	# Lueftungskanal (verzinkt) entlang der Westwand mit Flanschen und Zuluftgittern
	var dx := -12.75
	_bd.box("duct", Vector3(dx, 1.72, -92.0), Vector3(0.7, 0.44, 23.6))
	for i in 16:
		_bd.box("galv", Vector3(dx, 1.72, -80.9 - float(i) * 1.5), Vector3(0.76, 0.5, 0.05))
	for z: float in [-84.0, -90.0, -96.0, -102.0]:
		_bd.box("black", Vector3(dx + 0.355, 1.7, z), Vector3(0.01, 0.26, 0.62))
		for k in 6:
			_bd.box("galv", Vector3(dx + 0.365, 1.6 + float(k) * 0.04, z), Vector3(0.01, 0.012, 0.6))
	for z: float in [-82.0, -86.5, -91.0, -95.5, -100.0]:   # Abhaengung
		_bd.box("steel_dark", Vector3(dx, 1.49, z), Vector3(0.8, 0.03, 0.05))
		for sd: float in [-1.0, 1.0]:
			_bd.box("steel_dark", Vector3(dx + sd * 0.39, 1.75, z), Vector3(0.014, 0.52, 0.014))
	_label("ZULUFT  L 3", Vector3(dx + 0.37, 1.84, -93.0), 90.0, 26, Color(0.12, 0.12, 0.12), 0.004)
	# Loeschwasser- und Kuehlwasserleitung an der Ostwand
	_pipe("pipe_red", Vector3(13.68, 1.36, -80.2), Vector3(13.68, 1.36, -103.8), 0.065)
	_pipe("pipe_blue", Vector3(13.7, 1.18, -80.2), Vector3(13.7, 1.18, -103.8), 0.045)
	for z: float in [-82.0, -85.0, -88.0, -91.0, -94.0, -97.0, -100.0, -103.0]:
		_bd.box("steel_dark", Vector3(13.73, 1.27, z), Vector3(0.24, 0.3, 0.05))
	_bd.box("pipe_blue", Vector3(13.6, 1.18, -92.0), Vector3(0.08, 0.08, 0.06))
	_label("KUEHLWASSER  >", Vector3(13.6, 1.05, -89.0), -90.0, 18, Color(0.85, 0.85, 0.82), 0.004)
	_label("LOESCHWASSER  >", Vector3(13.6, 1.5, -89.0), -90.0, 18, Color(0.85, 0.85, 0.82), 0.004)
	# Pendelleuchten ueber dem Kartentisch (Emailschirme an Kabeln)
	for x: float in [-1.5, 1.5]:
		_bd.cyl("steel_dark", Vector3(x, 1.08, -92.0), 0.08, 0.3, 0.22, 18)
		_bd.cyl("lamp_on", Vector3(x, 0.965, -92.0), 0.27, 0.27, 0.01, 18)
		_bd.box("cable", Vector3(x, 1.59, -92.0), Vector3(0.012, 0.8, 0.012))
		_omni(Vector3(x, 0.55, -92.0), Color(1.0, 0.88, 0.72), 0.55, 5.0, 0.15)
	# Beschilderung: Raumkennung und Belegung (Westwand), Ebene (Nordwand), Rauchverbot (Ostwand)
	_bd.box("sign_white", Vector3(-13.83, 0.25, -92.0), Vector3(0.01, 0.5, 1.6))
	_label("SCHUTZRAUM  LAGEZENTRUM\nBELEGUNG MAX. 40 PERSONEN", Vector3(-13.82, 0.25, -92.0), 90.0, 22, Color(0.08, 0.08, 0.08), 0.004)
	_label("EBENE  -2", Vector3(-7.5, 0.6, -80.18), 180.0, 120, Color(0.78, 0.76, 0.68, 0.85), 0.006)
	_label("EBENE  -2", Vector3(7.5, 0.6, -80.18), 180.0, 120, Color(0.78, 0.76, 0.68, 0.85), 0.006)
	_bd.box("sign_white", Vector3(13.83, 0.3, -92.0), Vector3(0.01, 0.4, 1.3))
	_label("RAUCHEN VERBOTEN", Vector3(13.82, 0.3, -92.0), -90.0, 24, Color(0.7, 0.08, 0.05), 0.004)
	# Feuerloescher an der Suedwand neben der Panzertuer
	FK.place(_body, IM + "fire_extinguisher_de", Vector3(-2.4, YL, -103.62), Vector3.ZERO, 0.0, {"scale": 1.0, "stretch": 1.0, "shadows": false})
	_bx("pin_red", Vector3(-2.58, YL + 1.05, -103.85), Vector3(-2.22, YL + 1.33, -103.84), false)
	_label("F", Vector3(-2.4, YL + 1.19, -103.83), 0.0, 36, Color(0.95, 0.95, 0.9), 0.004)

func _build_tech_dressing() -> void:
	# Sockelanstrich (Tueren ausgespart)
	_dado(true, -4.165, -12.85, 12.85, [[-3.15, 3.15]], 0.0)
	_dado(true, -33.835, -12.85, 12.85, [[-2.0, 2.0]], 0.0)
	_dado(false, -12.835, -33.85, -4.15, [], 0.0)
	_dado(false, 12.835, -33.85, -4.15, [], 0.0)
	# Rechteckiger Zuluftkanal unter der Decke (liegt auf den Quertraegern) mit Flanschen
	_bd.box("duct", Vector3(-1.0, 6.5, -19.0), Vector3(0.8, 0.6, 29.6))
	for i in 20:
		_bd.box("galv", Vector3(-1.0, 6.5, -4.9 - float(i) * 1.5), Vector3(0.86, 0.66, 0.05))
	for z: float in [-10.0, -20.0, -30.0]:
		_bd.box("black", Vector3(-1.0, 6.19, z), Vector3(0.5, 0.01, 0.7))
		for k in 7:
			_bd.box("galv", Vector3(-1.0, 6.18, z - 0.3 + float(k) * 0.1), Vector3(0.48, 0.012, 0.012))
	_label("ZULUFT  TECHNIK", Vector3(-0.59, 6.55, -16.0), 90.0, 30, Color(0.12, 0.12, 0.12), 0.005)
	# Wickelfalzrohr (Abluft) an der Ostwand ueber dem Laufsteg
	_bd.cyl("duct", Vector3(12.35, 5.25, -19.0), 0.3, 0.3, 29.6, 18, Basis(Vector3(1, 0, 0), PI * 0.5))
	for i in 10:
		_bd.cyl("galv", Vector3(12.35, 5.25, -5.5 - float(i) * 3.0), 0.32, 0.32, 0.06, 18, Basis(Vector3(1, 0, 0), PI * 0.5))
		_bd.box("steel_dark", Vector3(12.7, 5.25, -5.5 - float(i) * 3.0), Vector3(0.3, 0.05, 0.05))
	# Kabeltrasse an der Westwand ueber den Schaltschraenken, Steigrohre aus den Schraenken
	_bd.box("galv", Vector3(-12.65, 3.2, -19.0), Vector3(0.4, 0.02, 29.6))
	_bd.box("galv", Vector3(-12.45, 3.245, -19.0), Vector3(0.02, 0.09, 29.6))
	for k in 3:
		_bd.box("cable", Vector3(-12.77 + float(k) * 0.1, 3.235, -19.0), Vector3(0.075, 0.05, 29.6))
	for z: float in [-8.0, -19.0, -30.0]:
		for dz: float in [-0.6, 0.0, 0.6]:
			_bd.box("galv", Vector3(-12.55, 2.7, z + dz), Vector3(0.05, 1.0, 0.05))
	# Leitungen an der Nordwand: Kraftstoff (gelb) und Kuehlwasser (blau) zu den Generatoren
	_pipe("pipe_yellow", Vector3(-12.8, 4.05, -4.3), Vector3(12.8, 4.05, -4.3), 0.06)
	_pipe("pipe_blue", Vector3(-12.8, 3.8, -4.3), Vector3(12.8, 3.8, -4.3), 0.06)
	for x: float in [-11.0, -8.0, -5.0, -2.0, 2.0, 5.0, 8.0, 11.0]:
		_bd.box("steel_dark", Vector3(x, 3.93, -4.25), Vector3(0.05, 0.36, 0.2))
	_label("DIESEL  >", Vector3(-6.5, 4.2, -4.37), 180.0, 22, Color(0.85, 0.82, 0.7), 0.004)
	# Warn- und Gebotsschilder
	_bd.box("pipe_blue", Vector3(-7.0, 2.0, -4.17), Vector3(1.2, 0.5, 0.01))
	_label("GEHOERSCHUTZ\nBENUTZEN", Vector3(-7.0, 2.0, -4.18), 180.0, 22, Color(0.95, 0.95, 0.95), 0.004)
	_bd.box("hazard", Vector3(7.0, 2.0, -4.17), Vector3(1.3, 0.5, 0.01))
	_label("VORSICHT\nHOCHSPANNUNG", Vector3(7.0, 2.0, -4.18), 180.0, 22, Color(0.05, 0.05, 0.05), 0.004)
	_bd.box("sign_white", Vector3(-12.83, 2.6, -13.5), Vector3(0.01, 0.4, 1.4))
	_label("NOTSTROMZENTRALE", Vector3(-12.82, 2.6, -13.5), 90.0, 24, Color(0.08, 0.08, 0.08), 0.004)
	FK.place(_body, "res://assets/environment/interior/models/fire_extinguisher_de", Vector3(4.2, 0.0, -4.38), Vector3.ZERO, 180.0, {"scale": 1.0, "stretch": 1.0, "shadows": false})
	_bx("pin_red", Vector3(4.02, 1.05, -4.16), Vector3(4.38, 1.33, -4.15), false)
	_label("F", Vector3(4.2, 1.19, -4.17), 180.0, 36, Color(0.95, 0.95, 0.9), 0.004)

## Notbeleuchtung in der Versorgungsroehre und im Notausgang: kleine Sicherheitsleuchten an der Wand.
func _build_emergency_lights() -> void:
	for z: float in [9.0, 15.0, 21.0, 27.0, 33.0]:
		_bd.box("steel_dark", Vector3(1.86, 1.7, z), Vector3(0.08, 0.16, 0.38))
		_bd.box("emerg_white", Vector3(1.815, 1.7, z), Vector3(0.015, 0.09, 0.3))
		_omni(Vector3(1.3, 1.75, z), Color(1.0, 0.9, 0.74), 0.55, 6.5, 0.3)
	# Notausgang Spree: Leuchte unter der Decke, Fluchtwegschild ueber der Tuer
	_bd.box("steel_dark", Vector3(10.0, YL + 2.28, -110.0), Vector3(0.38, 0.05, 0.16))
	_bd.box("emerg_white", Vector3(10.0, YL + 2.25, -110.0), Vector3(0.3, 0.012, 0.09))
	_omni(Vector3(10.0, YL + 1.9, -110.0), Color(1.0, 0.92, 0.78), 0.7, 5.0, 0.3)
	_exit_sign(Vector3(11.9, YL + 2.12, -110.0), -90.0)

## Rohr als gedrehter Zylinder von a nach b (nur Optik).
func _pipe(key: String, a: Vector3, b: Vector3, r: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mats[key]
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)), (a + b) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Meldeleuchte an senkrechter Schrankfront (+x).
func _pilot_lamp_wall(pos: Vector3, col: Color, on: bool) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col.darkened(0.55)
	m.roughness = 0.15
	m.emission_enabled = on
	m.emission = col
	m.emission_energy_multiplier = 1.6
	var cap := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.018
	sm.height = 0.022
	cap.mesh = sm
	cap.material_override = m
	cap.position = pos
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cap)
