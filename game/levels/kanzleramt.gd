extends "res://game/levels/level.gd"
## Teil 4 – "Geiseln" (Kanzleramt, Berlin, 25.06.2030 03:20). Breach & Clear mit Geiselbefreiung bei Nacht
## unter Notbeleuchtung. Kerner kommt durch Voss' alten Versorgungstunnel in den Keller unter der Lobby.
##
## Ablauf (Spieler laeuft nach -z):
##   Tunnel -> Lobby (Garde, Sprengladungen an den Saeulen) -> Tuer 1 Kabinettssaal (3 Abgeordnete sitzend)
##   -> EG-Flur, Ostbuero (Garde) -> Tuer 2 Westbuero (2 Geiseln kniend) -> Treppenhaus (Garde, Gepanzerte)
##   -> 2. OG -> Tuer 3 Saal unterm Dach (Praesidentin Hartmann + 2 Abgeordnete)
##   -> Riedhammer flieht hinter Panzerglas durch den Bunkergang, die Panzertuer schliesst -> Ende an der Tuer.
## Breach-System: game/systems/breach_*.gd (Tuer, Geisel, Bewacher, Raum, Zeitlupe, Bot).
## Unter --autopilot spielt breach_bot.gd die Breach-Sequenzen (bot_drives_player()).

const BP = preload("res://game/levels/berlin_props.gd")
const RoomScript = preload("res://game/systems/breach_room.gd")
const SlowmoScript = preload("res://game/systems/breach_slowmo.gd")
const BotScript = preload("res://game/systems/breach_bot.gd")

const Y2 := 9.0          ## Fussboden 2. OG

var mats: Dictionary = {}
var _bd: BP.Builder
var _body: StaticBody3D
var _bot: bool = false
var _bb: RefCounted
var slowmo: Node
var rooms: Array[Node] = []
var room_saal: Node
var room_buero: Node
var room_halle: Node
var _loops: Array[Node] = []
var _t: float = 0.0
var _flicker: Array = []                 ## [OmniLight3D, MeshInstance3D, phase]
var _leds: StandardMaterial3D
var _beams: Array[Node3D] = []
var _cine: bool = false
var _cine_look: Vector3 = Vector3.ZERO
var _ried: Node3D
var _ried_legs: Array[Node3D] = []
var _ried_run: bool = false
var _blast: StaticBody3D
var _ne_door: StaticBody3D
var _end_area: Area3D
var _finished: bool = false
var _restarting: bool = false
var _fail_count: int = 0
var _bot_cool: float = 0.0

func _init() -> void:
	level_name = "kanzleramt"
	end_z = -76.5
	build_seed = 2506
	_wave_count = 3
	default_faction = "reich"
	ambient_artillery = false

func _ready() -> void:
	_bot = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	await super()
	if not is_inside_tree():
		return
	slowmo = SlowmoScript.new()
	slowmo.name = "BreachSlowmo"
	add_child(slowmo)
	_build_rooms()
	_build_cinematic_props()
	Events.player_respawned.connect(_on_player_respawned)
	if _bot:
		_bb = BotScript.new(str(Game.arg("skill", "average")))
	_loop_2d("wx_rain", -34.0)
	_loop_3d("amb_siren", Vector3(-90.0, 25.0, -60.0), -20.0, 30.0, 400.0)
	_loop_3d("curfew_klaxon", Vector3(0.0, 12.0, -60.0), -34.0, 8.0, 60.0)
	_later(1.2, _intro)

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Geiseln"
	return info

## Autopilot-Hook: der Breach-Bot steuert, solange eine Breach-Sequenz/Zwischensequenz laeuft.
func bot_drives_player() -> bool:
	if not _bot or _bb == null:
		return false
	return _cine or bool(_bb.call("active"))

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

func _spot(pos: Vector3, target: Vector3, c: Color, energy: float, rng_: float, angle: float, fog: float = 1.5, shadows: bool = true) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.spot_range = rng_
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.8
	l.light_volumetric_fog_energy = fog
	l.shadow_enabled = shadows
	add_child(l)
	l.global_position = pos
	l.look_at(target, Vector3.UP if absf((target - pos).normalized().y) < 0.98 else Vector3.FORWARD)
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
func _wall_x(z: float, x0: float, x1: float, y0: float, y1: float, gaps: Array = [], key: String = "wall") -> void:
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
func _wall_z(x: float, z0: float, z1: float, y0: float, y1: float, gaps: Array = [], key: String = "wall") -> void:
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

## Fensterwand entlang z bei x: Bruestung, Sturz, Pfeiler, Glas; Kollision durchgehend.
func _window_wall_z(x: float, z0: float, z1: float, y0: float, y1: float, sill: float, top: float, bay: float = 3.0) -> void:
	var t := 0.15
	_col(Vector3(x - t, y0, z1), Vector3(x + t, y1, z0))
	_bx("wall", Vector3(x - t, y0, z1), Vector3(x + t, y0 + sill, z0), false)
	_bx("wall", Vector3(x - t, y0 + top, z1), Vector3(x + t, y1, z0), false)
	var n := maxi(1, int(round((z0 - z1) / bay)))
	var step := (z0 - z1) / float(n)
	for i in n + 1:
		var z := z1 + step * float(i)
		_bx("trim", Vector3(x - t - 0.05, y0 + sill, z - 0.3), Vector3(x + t + 0.05, y0 + top, z + 0.3), false)
	for i in n:
		var zc := z1 + step * (float(i) + 0.5)
		_bd.box("glass", Vector3(x, y0 + (sill + top) * 0.5, zc), Vector3(0.04, top - sill, step - 0.6))
		_bd.box("dark", Vector3(x, y0 + (sill + top) * 0.5, zc), Vector3(0.06, 0.06, step - 0.6))

func _window_wall_x(z: float, x0: float, x1: float, y0: float, y1: float, sill: float, top: float, bay: float = 3.0) -> void:
	var t := 0.15
	_col(Vector3(x0, y0, z - t), Vector3(x1, y1, z + t))
	_bx("wall", Vector3(x0, y0, z - t), Vector3(x1, y0 + sill, z + t), false)
	_bx("wall", Vector3(x0, y0 + top, z - t), Vector3(x1, y1, z + t), false)
	var n := maxi(1, int(round((x1 - x0) / bay)))
	var step := (x1 - x0) / float(n)
	for i in n + 1:
		var xx := x0 + step * float(i)
		_bx("trim", Vector3(xx - 0.3, y0 + sill, z - t - 0.05), Vector3(xx + 0.3, y0 + top, z + t + 0.05), false)
	for i in n:
		var xc := x0 + step * (float(i) + 0.5)
		_bd.box("glass", Vector3(xc, y0 + (sill + top) * 0.5, z), Vector3(step - 0.6, top - sill, 0.04))

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
	_bd.box("stone_dark", mid - n * 0.05, Vector3(x1 - x0, th, L), basis)
	var steps := maxi(2, int(round(dy / 0.18)))
	for i in steps:
		var ya := y_low + dy * float(i + 1) / float(steps)
		var za := z_low + dz * float(i) / float(steps)
		var zb := z_low + dz * float(i + 1) / float(steps)
		_bx("stone", Vector3(x0, ya - 0.34, za), Vector3(x1, ya, zb), false)
		_bx("trim", Vector3(x0, ya - 0.015, za - signf(dz) * 0.02), Vector3(x1, ya + 0.005, za + signf(dz) * 0.04), false)

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(0.012, 1.0)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.005, 0.007, 0.018)
	sm.sky_horizon_color = Color(0.11, 0.07, 0.07)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.015)
	sm.ground_horizon_color = Color(0.1, 0.065, 0.07)
	sm.sky_energy_multiplier = 1.0
	sm.sun_angle_max = 2.0
	sm.sun_curve = 0.05
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.2, 0.3)
	env.ambient_light_energy = 0.32
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_exposure = 1.25
	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.sdfgi_enabled = true
	env.sdfgi_energy = 0.7
	env.ssil_intensity = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.06, 0.08)
	env.fog_light_energy = 1.0
	env.fog_density = 0.004
	env.fog_sky_affect = 0.8
	env.fog_aerial_perspective = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.016
	env.volumetric_fog_albedo = Color(0.85, 0.84, 0.86)
	env.volumetric_fog_emission = Color(0.005, 0.004, 0.006)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_ambient_inject = 0.1
	env.volumetric_fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.85
	env.glow_intensity = 1.0
	env.glow_bloom = 0.06
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.95
	env.adjustment_contrast = 1.12
	env.adjustment_color_correction = null
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.64, 1.0)
	moon.light_energy = 0.14
	moon.light_indirect_energy = 0.5
	moon.light_volumetric_fog_energy = 0.5
	moon.shadow_enabled = true
	moon.shadow_blur = 2.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 80.0
	var dir := Vector3(-0.55, -0.45, -0.4).normalized()
	moon.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3.ZERO)
	add_child(moon)
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "night_city")

func _make_mats() -> void:
	mats = BP.materials()
	mats["wall"] = Geo.flat(Color(0.6, 0.58, 0.54), 0.85)
	mats["wall_dark"] = Geo.flat(Color(0.32, 0.31, 0.3), 0.85)
	mats["concrete"] = Geo.mat("concrete_wall_008", Color(0.45, 0.44, 0.43), 0.25, 1.0)
	mats["stone"] = Geo.flat(Color(0.5, 0.49, 0.47), 0.6)
	mats["stone_dark"] = Geo.flat(Color(0.3, 0.29, 0.28), 0.7)
	mats["floor"] = Geo.flat(Color(0.36, 0.35, 0.33), 0.35)
	mats["carpet"] = Geo.flat(Color(0.2, 0.06, 0.06), 0.97)
	mats["carpet_blue"] = Geo.flat(Color(0.07, 0.09, 0.16), 0.97)
	mats["oak"] = Geo.flat(Color(0.3, 0.19, 0.11), 0.5)
	mats["leather"] = Geo.flat(Color(0.08, 0.07, 0.07), 0.45)
	mats["ceiling"] = Geo.flat(Color(0.5, 0.5, 0.5), 0.9)
	mats["sandbag"] = Geo.flat(Color(0.3, 0.28, 0.2), 0.95)
	mats["c4"] = Geo.flat(Color(0.5, 0.48, 0.38), 0.85)
	mats["paper"] = Geo.flat(Color(0.8, 0.8, 0.76), 0.9)
	mats["exit_green"] = BP.unshaded(Color(0.15, 2.4, 0.6))
	mats["emerg_red"] = BP.unshaded(Color(2.6, 0.12, 0.08))
	mats["amber"] = BP.unshaded(Color(2.6, 1.2, 0.2))
	mats["lamp_dead"] = Geo.flat(Color(0.25, 0.25, 0.26), 0.4)
	mats["armor_glass"] = Geo.flat(Color(0.2, 0.25, 0.28), 0.05, 0.3)
	(mats["armor_glass"] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(mats["armor_glass"] as StandardMaterial3D).albedo_color = Color(0.25, 0.3, 0.34, 0.22)
	_leds = StandardMaterial3D.new()
	_leds.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_leds.albedo_color = Color(3.0, 0.1, 0.05)
	mats["led"] = _leds

func _build_ground() -> void:
	_make_mats()
	_bd = BP.Builder.new(mats)
	_bd.no_shadow.append_array(["glass", "exit_green", "emerg_red", "amber", "led", "armor_glass"])
	_body = Geo.static_body()
	_body.name = "Kanzleramt"
	_body.set_meta("no_fit", true)
	world.add_child(_body)
	# Aussenflaeche (durch die Fenster sichtbar) und Gebaeudeboden
	_bx("asphalt", Vector3(-70, -0.4, 40), Vector3(80, -0.02, -130))
	_bx("floor", Vector3(-14.5, -0.02, 0.2), Vector3(14.5, 0.0, -24.0))
	_bx("carpet", Vector3(-12, -0.02, -24.0), Vector3(12, 0.01, -44.0))
	_bx("floor", Vector3(-12, -0.02, -44.0), Vector3(20, 0.0, -62.0))
	_bx("concrete", Vector3(-1.8, -0.02, 0.2), Vector3(1.8, 0.0, 16.5))

func _build_street() -> void:
	# Aussen: Rasen/Platz vor dem Fensterband, Laternen
	var r := RandomNumberGenerator.new()
	r.seed = build_seed
	for i in 7:
		var z := 6.0 - float(i) * 12.0
		for sx: float in [-1.0, 1.0]:
			var x := sx * (22.0 + r.randf_range(0.0, 4.0))
			_bx("dark", Vector3(x - 0.08, 0, z - 0.08), Vector3(x + 0.08, 5.5, z + 0.08), false)
			_bx("amber", Vector3(x - 0.25, 5.4, z - 0.15), Vector3(x + 0.25, 5.55, z + 0.15), false)
			if i % 2 == 0:
				_omni(Vector3(x, 5.0, z), Color(1.0, 0.62, 0.3), 1.6, 14.0, 0.8)

# ------------------------------------------------------------------ Gebaeude

func _build_props() -> void:
	_build_tunnel()
	_build_lobby()
	_build_saal()
	_build_eg_corridor()
	_build_stairwell()
	_build_og2()
	_build_bunker_room()
	_bd.build(world)
	_build_lights()

func _build_tunnel() -> void:
	# Voss' alter Versorgungstunnel (Beton, Rohre)
	_bx("concrete", Vector3(-1.95, 0, 0.0), Vector3(-1.65, 3.2, 16.5))
	_bx("concrete", Vector3(1.65, 0, 0.0), Vector3(1.95, 3.2, 16.5))
	_bx("concrete", Vector3(-1.95, 3.0, 0.0), Vector3(1.95, 3.3, 16.5))
	_bx("concrete", Vector3(-1.95, 0, 16.5), Vector3(1.95, 3.2, 16.8))
	for z in [2.0, 6.0, 10.0, 14.0]:
		_bx("steel", Vector3(-1.62, 2.4, z - 2.0), Vector3(-1.45, 2.55, z + 2.0), false)
		_bx("steel", Vector3(-1.62, 2.1, z - 2.0), Vector3(-1.5, 2.2, z + 2.0), false)
		_bx("lamp_dead", Vector3(-0.2, 2.94, z - 0.4), Vector3(0.2, 3.0, z + 0.4), false)
	# Kisten von Voss' Leuten
	_bx("wood", Vector3(0.8, 0, 12.0), Vector3(1.6, 0.8, 13.2))
	_bx("wood", Vector3(0.9, 0.8, 12.2), Vector3(1.5, 1.3, 12.9))

func _build_lobby() -> void:
	# Lobby: x -14..14, z 0..-24, 7 m hoch, Fensterband Ost/West
	_wall_x(0.0, -14.3, 14.3, 0, 7.3, [[0.0, 3.2, 3.0]])
	_window_wall_z(-14.15, 0.0, -24.0, 0, 7.0, 1.0, 6.0, 4.0)
	_window_wall_z(14.15, 0.0, -24.0, 0, 7.0, 1.0, 6.0, 4.0)
	_wall_x(-24.0, -14.3, 14.3, 0, 7.3, [[0.0, 1.6, 2.45]])
	_bx("ceiling", Vector3(-14.3, 7.0, 0.3), Vector3(14.3, 7.4, -24.3))
	# Saeulen mit Sprengladungen der Garde
	for sx: float in [-6.5, 6.5]:
		for z: float in [-6.5, -16.5]:
			_bx("stone", Vector3(sx - 0.55, 0, z - 0.55), Vector3(sx + 0.55, 7.0, z + 0.55))
			_bx("trim", Vector3(sx - 0.65, 0, z - 0.65), Vector3(sx + 0.65, 0.3, z + 0.65), false)
			var face := 0.58 if sx < 0.0 else -0.58
			_bx("c4", Vector3(sx + face - 0.06, 1.2, z - 0.15), Vector3(sx + face + 0.06, 1.75, z + 0.15), false)
			_bx("c4", Vector3(sx + face - 0.06, 2.0, z - 0.15), Vector3(sx + face + 0.06, 2.55, z + 0.15), false)
			_bx("black", Vector3(sx + face - 0.07, 1.4, z - 0.6), Vector3(sx + face + 0.07, 1.45, z + 0.6), false)
			_bx("led", Vector3(sx + face * 1.12 - 0.03, 1.8, z - 0.03), Vector3(sx + face * 1.12 + 0.03, 1.86, z + 0.03), false)
	# Empfangstresen (Deckung)
	_bx("oak", Vector3(-3.2, 0, -9.0), Vector3(3.2, 1.1, -9.8))
	_bx("stone", Vector3(-3.3, 1.1, -8.95), Vector3(3.3, 1.16, -9.85), false)
	_bx("oak", Vector3(-3.2, 0, -9.8), Vector3(-2.6, 1.1, -11.5))
	# Sitzgruppen, Pflanzkuebel
	for sx: float in [-10.5, 10.5]:
		_bx("leather", Vector3(sx - 1.2, 0, -3.0), Vector3(sx + 1.2, 0.45, -3.8))
		_bx("leather", Vector3(sx - 1.2, 0.45, -3.6), Vector3(sx + 1.2, 0.85, -3.8), false)
		_bd.cyl("stone_dark", Vector3(sx, 0.45, -11.5), 0.55, 0.45, 0.9)
		Geo.add_box_shape(_body, Vector3(sx, 0.45, -11.5), Vector3(1.0, 0.9, 1.0))
	# Sandsack-Stellungen der Garde vor dem Saal
	for sx: float in [-6.5, 6.5]:
		for i in 6:
			var x := sx - 1.5 + float(i) * 0.6
			_bd.ball("sandbag", Vector3(x, 0.15, -20.2), Vector3(0.62, 0.3, 0.42))
			_bd.ball("sandbag", Vector3(x + 0.3, 0.42, -20.2), Vector3(0.62, 0.3, 0.42))
		_col(Vector3(sx - 1.8, 0, -19.95), Vector3(sx + 1.9, 0.62, -20.45))
	# Umgestuerzte Stuehle, Papier
	var r := RandomNumberGenerator.new()
	r.seed = build_seed + 3
	for i in 26:
		var p := Vector3(r.randf_range(-12, 12), 0.012, r.randf_range(-2, -22))
		_bd.box("paper", p, Vector3(0.21, 0.004, 0.3), Basis(Vector3.UP, r.randf() * TAU))
	# Schriftzug ueber dem Saal-Eingang (fiktiv)
	_label("BUNDESKANZLERAMT", Vector3(0, 5.2, -23.8), 0.0, 96, Color(0.75, 0.72, 0.62), 0.008)
	_label("KABINETTSSAAL", Vector3(0, 2.9, -23.8), 0.0, 40, Color(0.75, 0.72, 0.62), 0.006)

func _build_saal() -> void:
	# Kabinettssaal x -12..12, z -24..-44, Decke 4.5, Fenster nach Westen
	_window_wall_z(-12.15, -24.0, -44.0, 0, 4.5, 0.9, 3.7, 4.0)
	_wall_z(12.15, -24.0, -44.0, 0, 4.5)
	_wall_x(-44.0, -12.3, 12.3, 0, 4.5, [[8.0, 1.8, 2.5]])
	_bx("ceiling", Vector3(-12.3, 4.5, -24.0), Vector3(12.3, 4.8, -44.0))
	# Grosser Kabinettstisch (Oval angenaehert) mit Stuehlen
	_bx("oak", Vector3(-4.6, 0.72, -33.0), Vector3(4.6, 0.8, -38.0))
	_bx("oak", Vector3(-5.3, 0.72, -33.7), Vector3(5.3, 0.8, -37.3), false)
	_col(Vector3(-5.3, 0, -33.0), Vector3(5.3, 0.8, -38.0))
	for x: float in [-3.0, 3.0]:
		_bx("dark", Vector3(x - 0.3, 0, -35.2), Vector3(x + 0.3, 0.72, -35.8), false)
	for i in 8:
		var x := -4.2 + float(i) * 1.2
		_bx("leather", Vector3(x - 0.25, 0, -38.3), Vector3(x + 0.25, 0.5, -38.8), false)
		_bx("leather", Vector3(x - 0.25, 0.5, -38.75), Vector3(x + 0.25, 1.15, -38.85), false)
	# Wandbilder (leer), Fahnenstaender ohne Hoheitszeichen
	for x: float in [-8.0, 0.0]:
		_bx("dark", Vector3(x - 1.2, 1.6, -43.8), Vector3(x + 1.2, 3.2, -43.84), false)
	# Eckschrank, Sideboard (Deckung am Rand)
	_bx("oak", Vector3(9.0, 0, -25.0), Vector3(11.8, 0.9, -25.6))
	_bx("oak", Vector3(-11.8, 0, -40.0), Vector3(-11.2, 2.0, -43.6))

func _build_eg_corridor() -> void:
	# EG-Flur x -12..12, z -44..-48 (Decke 3.5); Bueros z -48..-60
	_wall_z(-12.15, -44.0, -60.0, 0, 3.5)
	_wall_x(-48.0, -12.3, 12.0, 0, 3.5, [[-6.0, 1.6, 2.45], [6.0, 1.8, 2.5]])
	_bx("ceiling", Vector3(-12.3, 3.5, -43.85), Vector3(12.0, 3.8, -60.3))
	_wall_x(-60.15, -12.3, 12.3, 0, 3.5)
	_wall_z(0.0, -48.0, -60.0, 0, 3.5)
	_bx("carpet_blue", Vector3(-11.9, 0.0, -48.2), Vector3(-0.2, 0.012, -59.9), false)
	# Schilder
	_label("WESTFLÜGEL  ←", Vector3(-3.0, 2.6, -47.8), 0.0, 32, Color(0.8, 0.8, 0.75), 0.005)
	_label("TREPPENHAUS  →", Vector3(9.0, 2.6, -44.2), 180.0, 32, Color(0.8, 0.8, 0.75), 0.005)
	# Westbuero: Schreibtische an den Waenden, Aktenschraenke
	_bx("oak", Vector3(-11.8, 0, -50.0), Vector3(-10.6, 0.76, -53.0))
	_bx("oak", Vector3(-1.4, 0, -57.0), Vector3(-0.2, 0.76, -59.8))
	for z: float in [-58.0, -59.0]:
		_bx("steel", Vector3(-11.8, 0, z - 0.45), Vector3(-11.2, 1.4, z + 0.45))
	_bx("leather", Vector3(-7.8, 0, -58.8), Vector3(-5.4, 0.45, -59.7))
	# Ostbuero: Garde hat sich verbarrikadiert
	_bx("oak", Vector3(3.0, 0, -52.0), Vector3(6.0, 0.76, -53.2))
	_bx("oak", Vector3(8.0, 0, -55.5), Vector3(11.8, 0.76, -56.7))
	_bx("steel", Vector3(1.0, 0, -58.6), Vector3(3.4, 1.9, -59.8))
	for i in 5:
		_bd.ball("sandbag", Vector3(4.0 + float(i) * 0.6, 0.15, -50.4), Vector3(0.62, 0.3, 0.42))
	_col(Vector3(3.7, 0, -50.15), Vector3(6.9, 0.4, -50.65))

func _build_stairwell() -> void:
	# Treppenhaus x 12..20, z -44..-62, bis 13.5 m
	# Wand x=12: EG-Durchgang z -44..-48 (3.5 hoch), 2.OG-Durchgang z -44..-48 (y 9..12)
	_bx("wall", Vector3(11.85, 0, -48.0), Vector3(12.15, 13.5, -62.15))
	_bx("wall", Vector3(11.85, 3.5, -43.85), Vector3(12.15, Y2, -48.0))
	_bx("wall", Vector3(11.85, Y2 + 3.0, -43.85), Vector3(12.15, 13.5, -48.0))
	_bx("concrete", Vector3(19.85, 0, -43.85), Vector3(20.15, 13.5, -62.15))
	_bx("concrete", Vector3(11.85, 0, -43.85), Vector3(20.15, 13.5, -44.15))
	_bx("concrete", Vector3(11.85, 0, -61.85), Vector3(20.15, 13.5, -62.15))
	_bx("ceiling", Vector3(11.85, 13.5, -43.85), Vector3(20.15, 13.8, -62.15))
	# Zwischenwand
	_bx("concrete", Vector3(15.5, 0, -48.0), Vector3(16.5, 13.5, -58.0))
	# Lauf A: hoch nach -z (EG -> Podest 4.5)
	_stairs(12.15, 15.5, -48.0, 0.0, -58.0, 4.5)
	# Podest L1
	_bx("stone_dark", Vector3(12.15, 4.2, -58.0), Vector3(19.85, 4.5, -61.85))
	# Block unter Lauf B, Lauf B hoch nach +z (4.5 -> 9)
	_bx("concrete", Vector3(16.5, 0, -48.0), Vector3(19.85, 4.5, -58.0))
	_bx("concrete", Vector3(16.5, 4.5, -47.85), Vector3(19.85, Y2 - 0.3, -48.15))
	_stairs(16.5, 19.85, -58.0, 4.5, -48.0, Y2)
	# Podest L2 + Gelaender ueber Lauf A
	_bx("stone_dark", Vector3(12.15, Y2 - 0.3, -44.15), Vector3(19.85, Y2, -48.0))
	_bx("steel", Vector3(12.15, Y2, -47.95), Vector3(15.5, Y2 + 1.05, -48.05))
	_col(Vector3(12.15, Y2, -47.9), Vector3(15.5, Y2 + 2.0, -48.1))
	# Notbeleuchtung-Schilder
	_label("2. OG", Vector3(19.8, Y2 + 2.0, -46.0), -90.0, 64, Color(0.85, 0.85, 0.8), 0.006)
	_label("1. OG", Vector3(18.0, 6.8, -61.8), 0.0, 64, Color(0.85, 0.85, 0.8), 0.006)
	# Feuerloescher, Kisten (Deckung) unten
	_bx("canvas_red", Vector3(19.5, 0.8, -45.0), Vector3(19.8, 1.4, -45.3), false)
	_bx("wood", Vector3(17.2, 0, -44.6), Vector3(18.6, 1.0, -46.0))

func _build_og2() -> void:
	# 2. OG Flur x -12..12, z -44..-48
	_bx("floor", Vector3(-12.3, Y2 - 0.3, -43.85), Vector3(12.0, Y2, -48.0))
	_wall_x(-44.0, -12.3, 12.0, Y2, Y2 + 3.5)
	_wall_z(-12.15, -44.0, -48.0, Y2, Y2 + 3.5)
	_bx("ceiling", Vector3(-12.3, Y2 + 3.5, -43.85), Vector3(12.0, Y2 + 3.8, -48.0))
	_bx("leather", Vector3(-10.0, Y2, -44.2), Vector3(-7.0, Y2 + 0.45, -44.9))
	_bx("steel", Vector3(-11.9, Y2, -45.2), Vector3(-11.3, Y2 + 1.2, -46.8))
	# Saal unterm Dach x -14..14, z -48..-70, 6 m hoch
	_bx("carpet", Vector3(-14.3, Y2 - 0.3, -48.0), Vector3(14.3, Y2, -70.0))
	_wall_x(-48.0, -14.3, 14.3, Y2, Y2 + 6.3, [[0.0, 1.6, 2.45]])
	_window_wall_z(-14.15, -48.0, -70.0, Y2, Y2 + 6.0, 1.0, 5.2, 3.7)
	_window_wall_z(14.15, -48.0, -70.0, Y2, Y2 + 6.0, 1.0, 5.2, 3.7)
	_bx("ceiling", Vector3(-14.3, Y2 + 6.0, -47.85), Vector3(14.3, Y2 + 6.3, -70.3))
	# Nordwand: Panzerglas zum Bunkervorraum (x -5..5), Tuer Nordost (x 10)
	var z := -70.0
	_bx("wall", Vector3(-14.3, Y2, z - 0.15), Vector3(-5.0, Y2 + 6.0, z + 0.15))
	_bx("wall", Vector3(5.0, Y2, z - 0.15), Vector3(9.2, Y2 + 6.0, z + 0.15))
	_bx("wall", Vector3(10.8, Y2, z - 0.15), Vector3(14.3, Y2 + 6.0, z + 0.15))
	_bx("wall", Vector3(9.2, Y2 + 2.45, z - 0.15), Vector3(10.8, Y2 + 6.0, z + 0.15))
	_bx("wall", Vector3(-5.0, Y2, z - 0.15), Vector3(5.0, Y2 + 0.9, z + 0.15))
	_bx("wall", Vector3(-5.0, Y2 + 3.4, z - 0.15), Vector3(5.0, Y2 + 6.0, z + 0.15))
	_bx("armor_glass", Vector3(-5.0, Y2 + 0.9, z - 0.06), Vector3(5.0, Y2 + 3.4, z + 0.06))
	for x: float in [-5.0, -1.7, 1.7, 5.0]:
		_bx("steel", Vector3(x - 0.08, Y2 + 0.9, z - 0.1), Vector3(x + 0.08, Y2 + 3.4, z + 0.1), false)
	_label("REGIERUNGSBUNKER – ZUGANG NUR MIT FREIGABE", Vector3(0, Y2 + 3.8, -69.8), 0.0, 36, Color(0.85, 0.2, 0.15), 0.006)
	# Moebel: Rednerpult, Stuhlreihen am Rand
	_bx("oak", Vector3(-1.0, Y2, -66.5), Vector3(1.0, Y2 + 1.15, -67.2))
	for row in 3:
		for i in 6:
			var x := -12.5 + float(i) * 0.75
			var zz := -52.0 - float(row) * 1.4
			_bx("chair", Vector3(x - 0.25, Y2, zz - 0.25), Vector3(x + 0.25, Y2 + 0.48, zz + 0.25), false)
			_bx("chair", Vector3(10.0 + float(i) * 0.6 - 0.25, Y2, zz - 0.25), Vector3(10.0 + float(i) * 0.6 + 0.25, Y2 + 0.48, zz + 0.25), false)
	_bx("oak", Vector3(-9.0, Y2, -63.0), Vector3(-6.5, Y2 + 0.8, -64.2))
	_bx("oak", Vector3(6.5, Y2, -63.0), Vector3(9.0, Y2 + 0.8, -64.2))

func _build_bunker_room() -> void:
	# Bunkervorraum hinter dem Panzerglas: x -8..12, z -70..-78
	_bx("concrete", Vector3(-8.0, Y2 - 0.3, -70.0), Vector3(12.0, Y2, -78.0))
	_wall_z(-8.15, -70.0, -78.0, Y2, Y2 + 3.5, [[-74.0, 1.4, 2.4]], "concrete")
	_wall_z(12.15, -70.0, -78.0, Y2, Y2 + 3.5, [], "concrete")
	_wall_x(-78.15, -8.3, 12.3, Y2, Y2 + 3.5, [[0.0, 2.4, 2.8]], "concrete")
	_bx("concrete", Vector3(-8.3, Y2 + 3.5, -69.85), Vector3(12.3, Y2 + 3.8, -78.3))
	# Nische links (Riedhammers Weg), dahinter Sackgasse
	_bx("concrete", Vector3(-11.0, Y2 - 0.3, -72.8), Vector3(-8.0, Y2, -75.2))
	_bx("concrete", Vector3(-11.0, Y2, -72.5), Vector3(-8.3, Y2 + 2.6, -72.8))
	_bx("concrete", Vector3(-11.0, Y2, -75.2), Vector3(-8.3, Y2 + 2.6, -75.5))
	_bx("black", Vector3(-11.3, Y2, -72.5), Vector3(-11.0, Y2 + 2.6, -75.5))
	_bx("concrete", Vector3(-11.3, Y2 + 2.6, -72.5), Vector3(-8.3, Y2 + 2.9, -75.5))
	# Hinter der Panzertuer: Treppe in die Tiefe (dunkel)
	_bx("concrete", Vector3(-1.6, Y2 - 0.3, -78.0), Vector3(1.6, Y2, -79.2))
	for i in 8:
		var y := Y2 - 0.3 - float(i) * 0.3
		_bx("stone_dark", Vector3(-1.4, y - 0.3, -79.2 - float(i) * 0.4), Vector3(1.4, y, -79.6 - float(i) * 0.4), false)
	_bx("black", Vector3(-1.8, Y2 - 4.0, -79.0), Vector3(-1.5, Y2 + 3.0, -83.0))
	_bx("black", Vector3(1.5, Y2 - 4.0, -79.0), Vector3(1.8, Y2 + 3.0, -83.0))
	_bx("black", Vector3(-1.8, Y2 - 4.0, -83.0), Vector3(1.8, Y2 + 3.0, -83.3))
	_col(Vector3(-1.6, Y2, -79.0), Vector3(1.6, Y2 + 3.0, -79.3))
	_label("BUNKER", Vector3(0, Y2 + 3.05, -77.95), 0.0, 48, Color(0.9, 0.85, 0.7), 0.006)
	# Rohre an der Decke
	_bx("steel", Vector3(-8.0, Y2 + 3.2, -77.4), Vector3(12.0, Y2 + 3.35, -77.25), false)

func _build_lights() -> void:
	var red := Color(1.0, 0.12, 0.08)
	var amber := Color(1.0, 0.55, 0.2)
	var cold := Color(0.75, 0.85, 1.0)
	# Tunnel: Voss' Baulampen
	_omni(Vector3(0.0, 2.6, 13.0), amber, 1.2, 7.0, 0.8)
	_omni(Vector3(0.0, 2.6, 5.0), amber, 0.9, 7.0, 0.8)
	_bd.box("amber", Vector3(0.0, 2.85, 13.0), Vector3(0.2, 0.1, 0.2))
	# Lobby: rote Notleuchten, Ausgangsschilder, ein flackerndes Neonfeld
	for p: Vector3 in [Vector3(-12.5, 6.2, -1.5), Vector3(12.5, 6.2, -1.5), Vector3(-12.5, 6.2, -22.5), Vector3(12.5, 6.2, -22.5)]:
		_omni(p, red, 1.6, 13.0, 1.0)
		_bd.box("emerg_red", p + Vector3(0, 0.25, 0), Vector3(0.4, 0.12, 0.2))
	_omni(Vector3(0, 2.0, -9.4), amber, 0.6, 5.0, 0.3)
	_exit_sign(Vector3(0, 3.3, -0.25), 180.0)
	_exit_sign(Vector3(0, 2.75, -23.75), 0.0)
	_flicker_lamp(Vector3(-3.0, 6.95, -14.0))
	_flicker_lamp(Vector3(4.0, 6.95, -5.0))
	# Kabinettssaal: Notlicht + Mondlicht durch die Fenster
	_omni(Vector3(10.5, 4.0, -26.0), red, 1.2, 10.0, 0.8)
	_omni(Vector3(-10.5, 4.0, -42.0), red, 1.0, 10.0, 0.8)
	_omni(Vector3(0.0, 4.1, -30.0), cold, 0.5, 9.0, 0.4)
	_flicker_lamp(Vector3(0.0, 4.45, -35.5))
	_exit_sign(Vector3(8.0, 2.75, -43.75), 0.0)
	# EG-Flur und Bueros
	_omni(Vector3(-8.0, 3.0, -46.0), red, 1.0, 8.0, 0.6)
	_omni(Vector3(8.0, 3.0, -46.0), red, 1.0, 8.0, 0.6)
	_omni(Vector3(-6.0, 3.0, -55.0), cold, 0.45, 8.0, 0.4)
	_omni(Vector3(6.0, 3.0, -55.0), amber, 0.6, 8.0, 0.4)
	_flicker_lamp(Vector3(0.0, 3.45, -46.0))
	# Treppenhaus: gruene Fluchtwegleuchten, rot am Podest
	_omni(Vector3(14.0, 3.0, -46.5), Color(0.3, 1.0, 0.5), 0.8, 8.0, 0.8)
	_omni(Vector3(16.0, 7.5, -60.0), red, 1.4, 10.0, 1.0)
	_omni(Vector3(16.0, Y2 + 2.8, -46.0), red, 1.2, 10.0, 1.0)
	_exit_sign(Vector3(12.25, 2.9, -46.0), 90.0)
	_exit_sign(Vector3(12.25, Y2 + 2.6, -46.0), 90.0)
	# 2. OG
	_omni(Vector3(-6.0, Y2 + 3.0, -46.0), red, 0.9, 9.0, 0.6)
	_omni(Vector3(6.0, Y2 + 3.0, -46.0), amber, 0.6, 9.0, 0.6)
	_omni(Vector3(-11.0, Y2 + 5.0, -50.0), red, 1.4, 14.0, 1.0)
	_omni(Vector3(11.0, Y2 + 5.0, -50.0), red, 1.4, 14.0, 1.0)
	_omni(Vector3(0.0, Y2 + 5.0, -60.0), cold, 0.7, 14.0, 0.6)
	_flicker_lamp(Vector3(-4.0, Y2 + 5.95, -58.0))
	_flicker_lamp(Vector3(5.0, Y2 + 5.95, -64.0))
	_exit_sign(Vector3(10.0, Y2 + 2.75, -69.75), 0.0)
	# Bunkervorraum: kaltes Licht (Riedhammer gut sichtbar), Warnlampe an der Panzertuer
	_omni(Vector3(0.0, Y2 + 3.0, -74.0), cold, 1.6, 10.0, 0.8)
	_omni(Vector3(0.0, Y2 + 2.9, -77.5), red, 1.6, 6.0, 1.0)
	_bd.box("emerg_red", Vector3(1.7, Y2 + 3.0, -77.9), Vector3(0.25, 0.25, 0.12))
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
	var l := _omni(pos + Vector3(0, -0.4, 0), Color(0.85, 0.92, 1.0), 1.4, 9.0, 0.7, false)
	_flicker.append([l, m, randf() * 10.0])

# ------------------------------------------------------------------ Skyline

func _build_skyline() -> void:
	var srng := RandomNumberGenerator.new()
	srng.seed = build_seed + 31
	var bb := Geo.batch()
	var wb := Geo.batch()
	for i in 70:
		var ang := srng.randf() * TAU
		var dist := srng.randf_range(70.0, 220.0)
		var c := Vector3(cos(ang) * dist, 0.0, sin(ang) * dist - 40.0)
		var w := srng.randf_range(12.0, 30.0)
		var d := srng.randf_range(12.0, 26.0)
		var h := srng.randf_range(10.0, 42.0)
		bb.add(c + Vector3(0, h * 0.5, 0), Vector3(w, h, d))
		# einzelne erleuchtete Fenster (Notstrom / Kerzen)
		for k in 6:
			if srng.randf() < 0.55:
				continue
			var face := srng.randi() % 2
			var wy := srng.randf_range(3.0, h - 2.0)
			if face == 0:
				wb.add(c + Vector3(srng.randf_range(-w * 0.4, w * 0.4), wy, d * 0.5 * signf(-c.z - 40.0 + 0.001)), Vector3(1.3, 1.6, 0.1))
			else:
				wb.add(c + Vector3(w * 0.5 * signf(-c.x + 0.001), wy, srng.randf_range(-d * 0.4, d * 0.4)), Vector3(0.1, 1.6, 1.3))
	add_child(Geo.mesh_node(bb.build(), Geo.mat("concrete_wall_008", Color(0.12, 0.12, 0.13), 0.08, 1.0)))
	var wm := wb.build()
	if wm != null:
		add_child(Geo.mesh_node(wm, BP.unshaded(Color(1.6, 1.0, 0.45)), Vector3.ZERO, false))
	# Kuppelbau in der Ferne (generisch) und Fernsehturm-Silhouette
	var dome := Geo.cylinder_node(14.0, 18.0, Geo.flat(Color(0.1, 0.1, 0.11)), Vector3(-60.0, 9.0, 40.0))
	add_child(dome)
	var tower := Geo.cylinder_node(2.2, 150.0, Geo.flat(Color(0.08, 0.08, 0.09)), Vector3(160.0, 75.0, -260.0))
	add_child(tower)
	add_child(Geo.mesh_node(SphereMesh.new(), BP.unshaded(Color(2.5, 0.1, 0.05)), Vector3(160.0, 151.0, -260.0), false))
	# Suchscheinwerfer der loyalen Truppen am Ring um das Regierungsviertel
	for i in 5:
		var base := Vector3(-120.0 + float(i) * 60.0, 0.0, -150.0 + float(i % 2) * 260.0)
		_beams.append(_beam(base, srng.randf() * TAU))

func _beam(base: Vector3, phase: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = base
	pivot.set_meta("phase", phase)
	add_child(pivot)
	var cm := CylinderMesh.new()
	cm.top_radius = 6.0
	cm.bottom_radius = 0.4
	cm.height = 160.0
	cm.radial_segments = 16
	cm.cap_top = false
	cm.cap_bottom = false
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(0.55, 0.62, 0.8, 0.07)
	var mi := Geo.mesh_node(cm, m, Vector3(0, 80.0, 0), false)
	pivot.add_child(mi)
	return pivot

func _build_atmosphere() -> void:
	# Staub/Rauch in der Lobby und im Treppenhaus
	Props.fog_volume(self, Vector3(0, 3.0, -12.0), Vector3(28, 6, 24), 0.03, Color(0.5, 0.46, 0.44))
	Props.fog_volume(self, Vector3(16, 6.0, -53.0), Vector3(8, 12, 18), 0.025, Color(0.5, 0.46, 0.44))

func _build_set_piece_geometry() -> void:
	pass

func _build_end_block() -> void:
	pass

# ------------------------------------------------------------------ Marker, Route

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(0.0, 0.1, 13.5), "player_spawn")
	ps.name = "PlayerSpawn"
	var route: Array = [
		Vector3(0, 0, 8.0), Vector3(0, 0, -2.5), Vector3(-4.6, 0, -8.0), Vector3(-4.4, 0, -13.0), Vector3(-1.5, 0, -18.5),
		Vector3(0.6, 0, -22.4),                                   # 5: Tuer 1
		Vector3(0, 0, -27.0), Vector3(9.0, 0, -30.0), Vector3(9.0, 0, -41.5), Vector3(8.0, 0, -46.0),
		Vector3(6.0, 0, -50.5), Vector3(7.0, 0, -54.5), Vector3(6.0, 0, -46.3),
		Vector3(-5.4, 0, -46.6),                                  # 13: Tuer 2
		Vector3(-6.0, 0, -52.5), Vector3(-5.0, 0, -46.0), Vector3(10.5, 0, -46.0), Vector3(13.8, 0, -46.5),
		Vector3(13.8, 0, -51.0), Vector3(13.8, 4.5, -59.6), Vector3(18.2, 4.5, -60.0), Vector3(18.2, 4.5, -57.0),
		Vector3(18.2, Y2, -46.5), Vector3(11.0, Y2, -46.0),
		Vector3(0.6, Y2, -46.6),                                  # 24: Tuer 3
		Vector3(0, Y2, -53.0), Vector3(9.6, Y2, -66.0), Vector3(10.0, Y2, -69.0), Vector3(9.0, Y2, -73.0), Vector3(1.5, Y2, -76.0),
	]
	for i in route.size():
		var w := Geo.marker(m, (route[i] as Vector3) + Vector3(0, 0.05, 0), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	# Checkpoints
	_trigger("CpSaal", Vector3(0, 1.5, -22.6), Vector3(5.0, 3, 1.6), func() -> void: _checkpoint("cp_saal"))
	_trigger("CpBuero", Vector3(-2.5, 1.5, -46.0), Vector3(1.5, 3, 3.8), func() -> void: _checkpoint("cp_buero"))
	_trigger("CpTreppe", Vector3(13.8, 1.5, -46.0), Vector3(3.0, 3, 3.8), func() -> void: _checkpoint("cp_treppe"))
	_trigger("CpHalle", Vector3(5.0, Y2 + 1.5, -46.0), Vector3(1.5, 3, 3.8), func() -> void: _checkpoint("cp_halle"))
	# Story-/Wellen-Ausloeser
	_trigger("TLobby", Vector3(0, 1.5, -1.0), Vector3(4.0, 3, 1.5), _on_enter_lobby)
	_trigger("TDoor1", Vector3(0, 1.5, -19.0), Vector3(10.0, 3, 1.2), _on_near_door1)
	_trigger("TCorridor", Vector3(8.0, 1.5, -45.5), Vector3(2.0, 3, 2.0), _on_enter_corridor)
	_trigger("TStairs", Vector3(11.0, 1.5, -46.0), Vector3(1.2, 3, 3.8), _on_enter_stairs)
	_trigger("TLanding", Vector3(18.0, 5.8, -60.0), Vector3(3.5, 3, 3.5), _on_landing)
	_trigger("TOg2", Vector3(10.0, Y2 + 1.5, -46.0), Vector3(1.2, 3, 3.8), _on_enter_og2)
	_end_area = _trigger("LevelEnd", Vector3(0.5, Y2 + 1.5, -76.4), Vector3(4.0, 3, 2.4), _finish, false)
	_end_area.add_to_group("level_end")
	_end_area.monitoring = false
	# Munition fuer den Weg
	Pickup.place_ammo_crate(self, Vector3(1.0, 0.0, 10.0), 90.0)
	Pickup.place_ammo_crate(self, Vector3(-10.5, 0.0, -45.0), 0.0)
	Pickup.place_ammo_crate(self, Vector3(18.6, 0.0, -45.4), 0.0)
	Pickup.place_ammo_crate(self, Vector3(-9.5, Y2, -45.2), 0.0)

func _bake_nav() -> void:
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
	nm.filter_baking_aabb = AABB(Vector3(-15.0, -1.0, -80.0), Vector3(36.0, 16.0, 98.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

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
			# Lobby: Garde hinter Sandsaecken und Saeulen
			_spawn("rifleman", Vector3(-6.5, 0, -21.0))
			_spawn("rifleman", Vector3(6.5, 0, -21.2))
			_spawn("assault", Vector3(-9.5, 0, -15.0), 160.0)
			_spawn("rifleman", Vector3(9.8, 0, -13.5), 200.0)
			_spawn("officer", Vector3(2.0, 0, -18.0), 180.0, 0.5)
		1:
			# Ostbuero
			_spawn("rifleman", Vector3(5.0, 0, -54.5), 180.0)
			_spawn("assault", Vector3(9.5, 0, -58.0), 200.0)
		2:
			# Treppenhaus: Gepanzerter am Podest, Garde oben
			_spawn("armored", Vector3(14.0, 4.5, -60.5), 0.0, 0.55)
			_spawn("rifleman", Vector3(18.5, 4.5, -61.0), 0.0)
			_spawn("rifleman", Vector3(18.3, Y2, -45.0), 0.0)
		3:
			# 2. OG Flur vor dem Saal
			_spawn("armored", Vector3(-9.5, Y2, -46.0), -90.0, 0.5)
			_spawn("rifleman", Vector3(-6.0, Y2, -44.8), -90.0)

# ------------------------------------------------------------------ Breach-Raeume

func _build_rooms() -> void:
	# Tuer 1: Kabinettssaal – drei Abgeordnete auf Stuehlen
	room_saal = RoomScript.new()
	room_saal.set("room_id", "saal")
	add_child(room_saal)
	room_saal.call("setup_door", Transform3D(Basis.IDENTITY, Vector3(0, 0, -24.0)), slowmo)
	room_saal.call("add_hostage", Vector3(-5.0, 0, -30.0), 180.0, "seat", {"suit": Color(0.12, 0.13, 0.17), "hair": Color(0.4, 0.38, 0.36)})
	room_saal.call("add_hostage", Vector3(0.0, 0, -30.5), 180.0, "seat", {"suit": Color(0.3, 0.27, 0.22), "hair": Color(0.18, 0.12, 0.07), "shirt": Color(0.75, 0.8, 0.9)})
	room_saal.call("add_hostage", Vector3(5.0, 0, -30.0), 180.0, "seat", {"suit": Color(0.1, 0.1, 0.1), "hair": Color(0.55, 0.52, 0.5)})
	room_saal.call("add_captor", "rifleman", Vector3(-6.3, 0, -29.6), 0)
	room_saal.call("add_captor", "officer", Vector3(1.25, 0, -30.1), 1)
	room_saal.call("add_captor", "rifleman", Vector3(6.3, 0, -29.6), 2)
	# Tuer 2: Westbuero – zwei kniende Geiseln
	room_buero = RoomScript.new()
	room_buero.set("room_id", "buero")
	add_child(room_buero)
	room_buero.call("setup_door", Transform3D(Basis.IDENTITY, Vector3(-6.0, 0, -48.0)), slowmo)
	room_buero.call("add_hostage", Vector3(-8.0, 0, -54.0), 180.0, "kneel", {"suit": Color(0.2, 0.2, 0.22), "hair": Color(0.1, 0.08, 0.06)})
	room_buero.call("add_hostage", Vector3(-4.0, 0, -55.0), 180.0, "kneel", {"suit": Color(0.35, 0.3, 0.33), "hair": Color(0.5, 0.35, 0.2), "shirt": Color(0.85, 0.82, 0.8)})
	room_buero.call("add_captor", "rifleman", Vector3(-9.2, 0, -53.4), 0)
	room_buero.call("add_captor", "assault", Vector3(-2.8, 0, -54.6), 1)
	# Tuer 3: Saal unterm Dach – Praesidentin Hartmann + zwei Abgeordnete
	room_halle = RoomScript.new()
	room_halle.set("room_id", "halle")
	room_halle.set("exec_charge", 4.4)
	room_halle.set("exec_kick", 3.6)
	add_child(room_halle)
	room_halle.call("setup_door", Transform3D(Basis.IDENTITY, Vector3(0, Y2, -48.0)), slowmo)
	room_halle.call("add_hostage", Vector3(0.0, Y2, -56.5), 180.0, "seat", {"suit": Color(0.42, 0.08, 0.1), "hair": Color(0.72, 0.72, 0.72), "shirt": Color(0.1, 0.1, 0.1), "display_name": "Hartmann"})
	room_halle.call("add_hostage", Vector3(-5.0, Y2, -57.5), 180.0, "kneel", {"suit": Color(0.14, 0.15, 0.2)})
	room_halle.call("add_hostage", Vector3(5.0, Y2, -57.5), 180.0, "kneel", {"suit": Color(0.25, 0.22, 0.2), "hair": Color(0.3, 0.2, 0.12)})
	room_halle.call("add_captor", "officer", Vector3(1.3, Y2, -56.3), 0)
	room_halle.call("add_captor", "rifleman", Vector3(-6.4, Y2, -57.0), 1)
	room_halle.call("add_captor", "rifleman", Vector3(6.4, Y2, -57.0), 2)
	rooms = [room_saal, room_buero, room_halle]
	for r in rooms:
		r.connect("failed", _on_room_failed)
		r.connect("warned", _on_room_warned)
		r.connect("breached", func(kind: String, flash: bool) -> void: _on_room_breached(r, kind, flash))
		r.call("arm")
	room_saal.connect("cleared", func(_r: Node) -> void: _on_saal_cleared())
	room_buero.connect("cleared", func(_r: Node) -> void: _on_buero_cleared())
	room_halle.connect("cleared", func(_r: Node) -> void: _on_halle_cleared())

func _on_room_breached(r: Node, kind: String, flash: bool) -> void:
	print("[kanzleramt] breach %s: %s%s" % [str(r.get("room_id")), kind, " + Blendgranate" if flash else ""])

func _on_room_warned(_r: Node) -> void:
	_say(StoryData.LENA, "Da drin zählt einer laut runter, Jonas. Die machen ernst – geh rein, jetzt!")

func _on_room_failed(r: Node, reason: String) -> void:
	if _restarting:
		return
	_restarting = true
	_fail_count += 1
	print("[kanzleramt] FEHLSCHLAG %s: %s" % [str(r.get("room_id")), reason])
	if reason == "shot":
		_say(StoryData.VOSS, "Feuer einstellen! Das war eine Geisel! Kerner – Abbruch, zurück auf Position.")
	else:
		_say(StoryData.LENA, "Schuss im Raum – sie haben eine Geisel erschossen. Zu langsam, Jonas. Zurück, noch mal.")
	if slowmo != null:
		slowmo.call("stop")
	_later(1.8, func() -> void:
		var pl := _player()
		if pl != null:
			pl.respawn()
		else:
			_restarting = false)

func _on_player_respawned() -> void:
	if slowmo != null:
		slowmo.call("stop")
	for r in rooms:
		if not bool(r.call("is_cleared")):
			if not bool(r.call("is_idle")):
				r.call("reset")
			else:
				r.set("_approach_t", 0.0)
				r.set("_warned", false)
	if _bb != null:
		_bb.set("phase", "idle")
	_bot_cool = 1.0
	if _restarting:
		_restarting = false
		_later(1.5, func() -> void:
			_say(StoryData.LENA, "Neuer Versuch. Ladung, Deckung, rein – und schieß nur, wenn die Linie frei ist."))

# ------------------------------------------------------------------ Story

func _intro() -> void:
	_obj("Dringe durch den Versorgungstunnel in die Lobby vor")
	_say(StoryData.VOSS, "Kerner, hier Voss. Der Versorgungsgang endet unter der Lobby. Meine Leute sind direkt hinter Ihnen.")
	_say(StoryData.LENA, "Die Garde hat die Säulen verdrahtet. Weber hatte recht – Riedhammer sprengt lieber das Viertel, als aufzugeben.")

func _on_enter_lobby() -> void:
	_obj("Säubere die Lobby")
	_say(StoryData.FALK, "Kerner. Ich hatte gehofft, dass Sie es sind. Hinter jeder Tür hier steht einer meiner Männer mit einer Pistole. Klopfen Sie ruhig an.")

func _on_near_door1() -> void:
	_obj("Befreie die Abgeordneten im Kabinettssaal")
	_say(StoryData.LENA, "Kabinettssaal: drei Geiseln, drei Wachen. [E] halten für die Ladung, [F] tritt die Tür ein, [B] nimmt eine Blendgranate mit. Danach hast du zwei Sekunden – triff nur die Wachen.")

func _on_saal_cleared() -> void:
	_checkpoint("cp_saal_frei")
	_obj("Durchsuche die Büros im Erdgeschoss")
	_say(StoryData.VOSS, "Saal gesichert! Meine Leute holen die Abgeordneten raus. Weiter, Kerner – erst das Ostbüro, dann der Westflügel.")

func _on_enter_corridor() -> void:
	_spawn_wave(1)

func _on_buero_cleared() -> void:
	_obj("Kämpf dich durch das Treppenhaus in den zweiten Stock")
	_say(StoryData.LENA, "Zwei mehr in Sicherheit. Hartmann ist oben im Saal unterm Dach. Das Treppenhaus ist dicht – Garde und Gepanzerte.")

func _on_enter_stairs() -> void:
	_spawn_wave(2)
	_say(StoryData.FALK, "Meine Garde weicht nicht, Kerner. Sie hat keinen Ort mehr, an den sie gehen könnte. Genau wie Sie.")

func _on_landing() -> void:
	_spawn_wave(3)
	_say(StoryData.LENA, "Gepanzerte! Zieh auf Kopf und Gelenke, nicht auf die Platten.")

func _on_enter_og2() -> void:
	_spawn_wave(3)
	_obj("Befreie Präsidentin Hartmann")
	_say(StoryData.LENA, "Letzte Tür. Die Präsidentin und zwei Abgeordnete, drei Wachen. Das muss sitzen, Jonas.")

func _on_halle_cleared() -> void:
	_obj("")
	_cine = true
	_cine_look = Vector3(0, Y2 + 1.6, -57.0)
	_say(StoryData.HARTMANN, "Nicht schießen! Ich bin Hartmann … Sie sind Voss' Leute?")
	_say(StoryData.KERNER, "Kerner. Wir bringen Sie raus, Frau Präsidentin.")
	_say(StoryData.HARTMANN, "Riedhammer war eben noch hier – er will in den Bunker! Da, hinter dem Glas!")
	_later(4.0, _riedhammer_run)

# ------------------------------------------------------------------ Zwischensequenz: Riedhammer flieht

func _build_cinematic_props() -> void:
	# Panzertuer (offen, seitlich in der Wand)
	_blast = StaticBody3D.new()
	_blast.collision_layer = 1
	_blast.set_meta("no_fit", true)
	var steel := Geo.flat(Color(0.2, 0.21, 0.22), 0.45, 0.7)
	_blast.add_child(Geo.box_mesh_node(Vector3(2.7, 3.0, 0.5), steel, Vector3(0, 1.5, 0)))
	for y: float in [0.6, 1.5, 2.4]:
		_blast.add_child(Geo.box_mesh_node(Vector3(2.5, 0.12, 0.08), Geo.flat(Color(0.75, 0.6, 0.1), 0.6), Vector3(0, y, 0.27)))
	Geo.add_box_shape(_blast, Vector3(0, 1.5, 0), Vector3(2.7, 3.0, 0.5))
	add_child(_blast)
	_blast.position = Vector3(2.75, Y2, -78.6)
	# Tuer Nordost (verriegelt bis nach der Flucht)
	_ne_door = StaticBody3D.new()
	_ne_door.collision_layer = 1
	_ne_door.set_meta("no_fit", true)
	_ne_door.add_child(Geo.box_mesh_node(Vector3(1.6, 2.45, 0.1), Geo.flat(Color(0.32, 0.33, 0.34), 0.4, 0.6), Vector3(0, 1.225, 0)))
	Geo.add_box_shape(_ne_door, Vector3(0, 1.225, 0), Vector3(1.6, 2.45, 0.12))
	add_child(_ne_door)
	_ne_door.position = Vector3(10.0, Y2, -70.0)
	# Riedhammer (Generalsuniform, Schirmmuetze), zunaechst verborgen in der Nische
	var fig: Dictionary = preload("res://game/characters/vip_models.gd").build(self, "riedhammer", Vector3(-10.2, Y2, -74.0), 0.0)
	_ried = fig["root"]
	_ried.visible = false
	_ried_legs.assign(fig["legs"])

func _riedhammer_run() -> void:
	if not is_inside_tree():
		return
	_ried.visible = true
	_ried_run = true
	_ried.rotation.y = deg_to_rad(-90.0)   # schaut nach +x
	_cine_look = _ried.global_position + Vector3(0, 1.6, 0)
	_say(StoryData.RIEDHAMMER, "Falk! Die Tür – schließen Sie die verdammte Tür!", 2.6)
	var tw := create_tween()
	tw.tween_property(_ried, "position", Vector3(-2.0, Y2, -74.6), 2.4)
	tw.tween_property(_ried, "position", Vector3(0.0, Y2, -77.4), 1.0)
	tw.tween_callback(func() -> void:
		_ried_run = false
		_ried.rotation.y = 0.0
		for l in _ried_legs:
			l.rotation.x = 0.0)
	# er dreht sich um, sieht Kerner durch das Glas
	tw.tween_property(_ried, "rotation:y", PI, 0.5)
	tw.tween_interval(1.0)
	tw.tween_property(_ried, "position", Vector3(0.0, Y2, -79.6), 0.8)
	tw.tween_callback(_close_blast)

func _close_blast() -> void:
	var tw := create_tween()
	tw.tween_property(_blast, "position:x", 0.0, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		var vf := preload("res://game/vehicles/vehicle_fx.gd")
		vf.play_at(self, "rail_metal_crash", _blast.global_position + Vector3(0, 1.5, 0), 2.0, 10.0, 80.0, 0.7)
		_ried.visible = false
		_after_escape())

func _after_escape() -> void:
	_say(StoryData.FALK, "Zu spät, Kerner. Der General ist dort, wo Sie ihn nie erreichen. Und unter Ihren Füßen liegt genug Sprengstoff für den ganzen Spreebogen.")
	_say(StoryData.VOSS, "Hartmann ist bei uns, Kerner. Der Bunker hat einen zweiten Zugang – unter der Spree. Lena hat die Haustechnik: Tür Nordost ist offen. Zur Panzertür!")
	_obj("Erreiche die Panzertür zum Regierungsbunker")
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(_ne_door, "position:x", 11.65, 1.2)
	tw.tween_callback(func() -> void:
		_cine = false
		_end_area.set_deferred("monitoring", true))

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_obj("")
	_say(StoryData.KERNER, "Riedhammer ist hinter der Panzertür. Er hat sich eingemauert.")
	_say(StoryData.VOSS, "Dann gehen wir von unten rein. Gute Arbeit, Kerner – heute Nacht holen wir uns den General.")
	_later(4.0, _on_level_end)

# ------------------------------------------------------------------ Laufzeit

func _process(delta: float) -> void:
	_t += delta
	# Ladungs-LEDs an den Saeulen blinken
	if _leds != null:
		var on := fmod(_t, 1.1) < 0.12
		_leds.albedo_color = Color(3.0, 0.1, 0.05) if on else Color(0.25, 0.02, 0.01)
	# flackernde Neonroehren
	for f: Array in _flicker:
		var l := f[0] as OmniLight3D
		var m := f[1] as StandardMaterial3D
		var ph: float = f[2]
		var s := sin(_t * 23.0 + ph) + sin(_t * 7.3 + ph * 2.0)
		var lit := s > -0.6 and fmod(_t + ph, 6.0) > 0.35
		l.light_energy = 1.4 if lit else 0.05
		m.albedo_color = Color(2.2, 2.3, 2.4) if lit else Color(0.2, 0.2, 0.22)
	# Suchscheinwerfer schwenken
	for b in _beams:
		var ph2: float = b.get_meta("phase", 0.0)
		b.rotation = Vector3(deg_to_rad(18.0 + sin(_t * 0.21 + ph2) * 12.0), _t * 0.08 + ph2, deg_to_rad(sin(_t * 0.17 + ph2) * 14.0))
	# Riedhammer: Laufanimation
	if _ried_run and _ried != null:
		for i in _ried_legs.size():
			_ried_legs[i].rotation.x = sin(_t * 13.0 + float(i) * PI) * 0.6

func _physics_process(delta: float) -> void:
	if _bot and _bb != null and _ready_done:
		_bot_tick(delta)

## Breach-Bot (nur --autopilot): uebernimmt an der Tuer, solange keine anderen Gegner sichtbar sind.
func _bot_tick(delta: float) -> void:
	var pl := _player()
	if pl == null or bool(pl.get("dead")):
		return
	if _cine:
		pl.external_input = true
		var ext: Dictionary = pl.ext
		ext["move"] = Vector2.ZERO
		ext["look"] = Vector2.ZERO
		ext["fire"] = false
		ext["aim"] = false
		ext["sprint"] = false
		ext["crouch"] = false
		if _ried != null and _ried.visible:
			_cine_look = _ried.global_position + Vector3(0, 1.6, 0)
		pl.look_at_point(_cine_look)
		return
	if bool(_bb.call("active")):
		_bb.call("tick", delta)
		if not bool(_bb.call("active")):
			_bot_cool = 0.5
		return
	_bot_cool -= delta
	if _bot_cool > 0.0 or _restarting:
		return
	for r in rooms:
		if bool(r.call("is_cleared")):
			continue
		var door := r.get("door") as Node3D
		var d := pl.global_position.distance_to(door.global_position)
		if absf(pl.global_position.y - door.global_position.y) > 2.0:
			continue
		if bool(r.call("is_breached")) and d < 14.0:
			_bb.call("begin", pl, r, true)
			_bb.set("phase", "fight")
			return
		if bool(r.call("is_idle")) and d < 4.2 and not _hostiles_near(pl, r):
			_bb.call("begin", pl, r, true)
			return

func _hostiles_near(pl: Player, room: Node) -> bool:
	var caps: Array = room.get("captors")
	var cam := pl.get_camera()
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e == null or not e.is_alive() or caps.has(e):
			continue
		var is_captor := false
		for r in rooms:
			if (r.get("captors") as Array).has(e):
				is_captor = true
				break
		if is_captor:
			continue
		if e.global_position.distance_to(pl.global_position) > 28.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, e.global_position + Vector3(0, 1.4, 0), 1)
		if space.intersect_ray(q).is_empty():
			return true
	return false
