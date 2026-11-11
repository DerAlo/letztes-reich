extends "res://game/levels/level.gd"
## Mission 6 "Ausgangssperre" (Teil 2): Berlin-Mitte, 03.06.2030, 01:40. Nächtliche Ausgangssperre.
## Kerner schleicht durch eine Straße mit Kontrollpunkt (Umweg durch die Hinterhöfe), über den Platz vor
## dem Regierungsbau und durch die Lieferzufahrt in den Ministeriumsanbau. In der Fernmeldestelle lädt er
## Webers Funkprotokolle herunter und flieht durch den Notausgang in den U-Bahn-Tunnel zu Konrad Voss.
##
## Schleichsystem: curfew_stealth.gd (Direktor: Licht, Geräusch, Alarm), stealth_brain.gd (je Wache),
## curfew_drone.gd, curfew_searchlight.gd, curfew_terminal.gd, takedown.gd [F], curfew_hud.gd.
## Alarm draußen ist überlebbar (Verstärkung, Sirene, Hoftor zu); Alarm im Anbau vor dem Download löscht
## die Protokolle -> Neustart am Checkpoint "cp_annex".

const BP = preload("res://game/levels/berlin_props.gd")
const Screen = preload("res://game/levels/berlin_screen.gd")
const Stealth = preload("res://game/levels/curfew_stealth.gd")
const Brain = preload("res://game/enemies/stealth_brain.gd")
const DroneScript = preload("res://game/levels/curfew_drone.gd")
const SearchlightScript = preload("res://game/levels/curfew_searchlight.gd")
const TerminalScript = preload("res://game/levels/curfew_terminal.gd")
const TakedownScript = preload("res://game/weapons/takedown.gd")
const HudScript = preload("res://game/levels/curfew_hud.gd")
const EMBLEM := "res://assets/environment/berlin/emblem.png"

## Anbau (Innenraum y 0..4,5): Grundriss
const ANNEX_MIN := Vector2(25.0, -161.4)     ## x, z
const ANNEX_MAX := Vector2(45.4, -118.6)
const TERMINAL_POS := Vector3(44.8, 0.0, -145.5)
const VOSS_POS := Vector3(40.4, -5.0, -199.0)

var mats: Dictionary = {}
var director: Node
var terminal: Pickup
var takedown: Node
var hud: CanvasLayer
var _bot: bool = false
var _loops: Array[Node] = []
var _alarm_loops: Array[Node] = []
var _floods: Array[SpotLight3D] = []          ## Flutlicht auf dem Platz (nur bei Alarm)
var _flood_beams: Array[Node3D] = []
var _gate: StaticBody3D                        ## Hoftor (schließt bei Alarm)
var _gate_closed: bool = false
var _exit_gate: StaticBody3D                   ## Gitter vor der Treppe zum Tunnel
var _reinf: Array[Node] = []
var _reinf_waves: int = 0
var _reinf_t: float = -1.0
var _wiping: bool = false
var _finished: bool = false
var _sky_beams: Array[Node3D] = []
var _tower_lights: Array[MeshInstance3D] = []
var _t: float = 0.0
var _alarm_lamps: Array[OmniLight3D] = []

func _init() -> void:
	level_name = "curfew"
	end_z = -199.0
	build_seed = 2030
	_wave_count = 1
	default_faction = "reich"
	ambient_artillery = false

func _ready() -> void:
	_bot = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	await super()
	if not is_inside_tree():
		return
	_build_exit_gate()
	_equip_suppressed()
	Events.player_respawned.connect(_on_player_respawned)
	_loop_2d("wx_rain", -30.0)
	if _bot:
		Pickup.place_ammo_crate(self, Vector3(-9.0, 0.02, 3.0), 90.0)

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Ausgangssperre"
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

func _fade_out(p: Node, t: float) -> void:
	if p == null or not is_instance_valid(p):
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", -60.0, t)
	tw.tween_callback(p.queue_free)

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

## Blickrichtung in Grad -> Enemy-Yaw (0 = schaut nach -z, 90 = nach -x, 180 = nach +z, -90 = nach +x).
static func _wp(x: float, z: float, wait: float = 0.0, look_deg: float = INF) -> Dictionary:
	return {"p": Vector3(x, 0.05, z), "wait": wait, "yaw": NAN if is_inf(look_deg) else deg_to_rad(look_deg)}

## Box mit passgenauer Kollision (Optik im Builder, Form im gemeinsamen Body).
func _sbox(bd: BP.Builder, body: StaticBody3D, key: String, c: Vector3, s: Vector3, yaw_deg: float = 0.0) -> void:
	var rot := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	bd.box(key, c, s, rot)
	Geo.add_box_shape(body, c, s, Vector3(0, yaw_deg, 0))

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
	l.shaded = true
	l.double_sided = false
	l.position = pos
	l.rotation_degrees.y = yaw
	add_child(l)
	return l

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(0.012, 1.0)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.006, 0.008, 0.02)
	sm.sky_horizon_color = Color(0.085, 0.06, 0.07)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.015)
	sm.ground_horizon_color = Color(0.085, 0.06, 0.07)
	sm.sky_energy_multiplier = 1.0
	sm.sun_angle_max = 2.0
	sm.sun_curve = 0.05
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.25, 0.36)
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_exposure = 1.15
	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.sdfgi_enabled = true
	env.sdfgi_energy = 0.6
	env.ssil_intensity = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.065, 0.085)
	env.fog_light_energy = 1.0
	env.fog_density = 0.005
	env.fog_sky_affect = 0.8
	env.fog_aerial_perspective = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.82, 0.83, 0.86)
	env.volumetric_fog_emission = Color(0.006, 0.006, 0.009)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 110.0
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_ambient_inject = 0.1
	env.volumetric_fog_sky_affect = 0.7
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.9
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.92
	env.adjustment_contrast = 1.1
	env.adjustment_color_correction = null
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.64, 1.0)
	moon.light_energy = 0.12
	moon.light_indirect_energy = 0.5
	moon.light_volumetric_fog_energy = 0.4
	moon.shadow_enabled = true
	moon.shadow_blur = 2.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 80.0
	var dir := Vector3(0.35, -0.6, -0.7).normalized()
	moon.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3.ZERO)
	add_child(moon)
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "night_city")

# ------------------------------------------------------------------ Boden

func _build_ground() -> void:
	mats = BP.materials()
	var wet := BP.asphalt().duplicate() as StandardMaterial3D
	wet.roughness = 0.42
	wet.albedo_color = wet.albedo_color.darkened(0.25)
	mats["asphalt"] = wet
	mats["line"] = Geo.flat(Color(0.7, 0.7, 0.66), 0.5)
	mats["plaster"] = Geo.flat(Color(0.4, 0.42, 0.39), 0.92)
	mats["plaster_low"] = Geo.flat(Color(0.2, 0.24, 0.22), 0.8)
	mats["lino"] = Geo.flat(Color(0.1, 0.11, 0.105), 0.55)
	mats["ceiling"] = Geo.flat(Color(0.32, 0.32, 0.31), 0.95)
	mats["concrete"] = Geo.mat("concrete_wall_008", Color(0.42, 0.41, 0.4), 0.22, 1.0)
	mats["brick"] = Geo.mat("brick_wall_02", Color(0.5, 0.42, 0.38), 0.3, 1.0)
	mats["metal"] = Geo.mat("rusty_metal_02", Color(0.3, 0.3, 0.3), 0.5, 1.0)
	mats["rack"] = Geo.flat(Color(0.045, 0.05, 0.055), 0.4, 0.6)
	mats["led_g"] = BP.unshaded(Color(0.2, 2.6, 0.6))
	mats["led_r"] = BP.unshaded(Color(2.8, 0.15, 0.1))
	mats["led_b"] = BP.unshaded(Color(0.12, 0.4, 1.3))
	mats["tile"] = Geo.flat(Color(0.5, 0.52, 0.46), 0.3)
	mats["tile_band"] = Geo.flat(Color(0.12, 0.3, 0.26), 0.3)
	mats["crate"] = Geo.flat(Color(0.34, 0.26, 0.16), 0.85)
	mats["rail"] = Geo.flat(Color(0.34, 0.32, 0.3), 0.35, 0.9)
	mats["sleeper"] = Geo.flat(Color(0.13, 0.11, 0.09), 0.95)
	mats["gravel"] = Geo.flat(Color(0.16, 0.15, 0.14), 1.0)
	mats["fluor"] = BP.unshaded(Color(2.2, 2.4, 2.5))
	mats["fluor_off"] = Geo.flat(Color(0.5, 0.52, 0.52), 0.4)
	mats["exit_green"] = BP.unshaded(Color(0.2, 2.6, 0.7))
	mats["warn"] = Geo.flat(Color(0.75, 0.55, 0.04), 0.6)
	mats["shutter"] = Geo.flat(Color(0.22, 0.23, 0.24), 0.5, 0.6)
	mats["desk"] = Geo.flat(Color(0.3, 0.27, 0.22), 0.7)
	mats["paper"] = Geo.flat(Color(0.75, 0.74, 0.7), 0.9)
	mats["amber"] = BP.unshaded(Color(3.4, 1.7, 0.35))
	mats["red_glow"] = BP.unshaded(Color(3.0, 0.12, 0.08))
	mats["skin"] = Geo.flat(Color(0.55, 0.4, 0.32), 0.7)
	mats["coat"] = Geo.flat(Color(0.12, 0.12, 0.1), 0.85)
	mats["coat2"] = Geo.flat(Color(0.2, 0.18, 0.13), 0.85)
	# Boden: Platte y -1..0 mit Aussparung für den Treppenschacht (x 41..44, z -150..-160)
	var g := Geo.static_body()
	Geo.add_box_shape(g, Vector3(10.0, -0.5, -68.0), Vector3(100.0, 1.0, 164.0))
	Geo.add_box_shape(g, Vector3(0.5, -0.5, -155.0), Vector3(81.0, 1.0, 10.0))
	Geo.add_box_shape(g, Vector3(52.0, -0.5, -155.0), Vector3(16.0, 1.0, 10.0))
	Geo.add_box_shape(g, Vector3(10.0, -0.5, -195.0), Vector3(100.0, 1.0, 70.0))
	world.add_child(g)
	var far := Geo.box_mesh_node(Vector3(900.0, 0.2, 900.0), Geo.flat(Color(0.03, 0.03, 0.035), 0.9), Vector3(0, -0.16, -200.0))
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
	var bd := BP.Builder.new(mats)
	# Straße (Asphalt), Gehwege (Granit), Bordsteine
	bd.box("asphalt", Vector3(0, -0.1, -50.0), Vector3(14.0, 0.2, 124.0))
	for sx: float in [-1.0, 1.0]:
		bd.box("granite", Vector3(sx * 9.5, -0.08, -50.0), Vector3(5.0, 0.2, 124.0))
		bd.box("trim", Vector3(sx * 7.08, 0.03, -50.0), Vector3(0.16, 0.1, 124.0))
	for i in 18:
		bd.box("line", Vector3(0, 0.004, 8.0 - i * 6.5), Vector3(0.14, 0.02, 3.0))
	# Gassen und Hof (Pflaster/Asphalt)
	bd.box("asphalt", Vector3(-21.0, -0.09, -65.0), Vector3(18.0, 0.2, 52.0))
	for z: float in [-33.0, -79.0]:
		bd.box("asphalt", Vector3(18.0, -0.09, z), Vector3(12.0, 0.2, 6.0))
	# Platz (Granitplatten mit Fugen), Lieferzufahrt
	bd.box("granite", Vector3(-1.0, -0.08, -136.0), Vector3(50.0, 0.2, 52.0))
	for i in 10:
		bd.box("trim", Vector3(-1.0, 0.004, -114.0 - i * 5.0), Vector3(49.0, 0.02, 0.12))
	bd.box("asphalt", Vector3(35.0, -0.09, -114.0), Vector3(22.0, 0.2, 8.0))
	bd.build(world)
	# Grenzen
	_invisible_wall(Vector3(0, 7.0, 11.0), Vector3(30.0, 14.0, 1.0))

# ------------------------------------------------------------------ Gebäude

func _build_street() -> void:
	var bd := BP.Builder.new(mats)
	var body := Geo.static_body()
	var brng := RandomNumberGenerator.new()
	brng.seed = build_seed + 7
	# Linke Seite: Block, Hofgasse, flaches Hinterhaus, Hofgasse, Block
	BP.block(bd, body, -1, -12.0, 10.0, -40.0, 18.0, 22.0, "sandstone", brng, {"lit": 0.12, "shop": 0.0})
	BP.block(bd, body, -1, -12.0, -46.0, -84.0, 6.0, 13.0, "facade", brng, {"lit": 0.08, "shop": 0.0})
	BP.block(bd, body, -1, -12.0, -90.0, -110.0, 18.0, 24.0, "sandstone", brng, {"lit": 0.1, "shop": 0.0})
	# Rechte Seite: drei Blöcke mit zwei Sackgassen
	BP.block(bd, body, 1, 12.0, 10.0, -30.0, 18.0, 23.0, "facade", brng, {"lit": 0.1, "shop": 0.0})
	BP.block(bd, body, 1, 12.0, -36.0, -76.0, 18.0, 25.0, "sandstone", brng, {"lit": 0.14, "shop": 0.0})
	BP.block(bd, body, 1, 12.0, -82.0, -110.0, 18.0, 21.0, "facade", brng, {"lit": 0.1, "shop": 0.0})
	# Hof: Rückwand und Brandmauern, Sackgassen-Enden rechts, Hinterhaus hinter der Zufahrt
	_sbox(bd, body, "brick", Vector3(-31.0, 7.0, -65.0), Vector3(2.0, 14.0, 54.0))
	for z: float in [-33.0, -79.0]:
		_sbox(bd, body, "brick", Vector3(27.0, 7.0, z), Vector3(6.0, 14.0, 6.0))
	_sbox(bd, body, "concrete", Vector3(39.0, 9.0, -96.0), Vector3(18.0, 18.0, 28.0))
	_sbox(bd, body, "concrete", Vector3(47.0, 8.0, -114.0), Vector3(2.0, 16.0, 10.0))
	# Platz: links Regierungsbau mit Kolonnade, hinten Ministerium (Fassade nach +z, gedrehter Aufbau)
	BP.block(bd, body, -1, -26.0, -110.0, -162.0, 20.0, 24.0, "sandstone", brng, {"lit": 0.2, "shop": 0.0})
	BP.colonnade(bd, body, -1, -26.0, -116.0, -156.0, 11.0)
	bd.box("granite", Vector3(-21.4, 0.15, -136.0), Vector3(2.2, 0.3, 44.0))
	Geo.add_box_shape(body, Vector3(-21.4, 0.15, -136.0), Vector3(2.2, 0.3, 44.0))
	# Anbau: Fassadenschale zur Platzseite
	BP.block(bd, body, 1, 24.0, -118.0, -162.0, 1.0, 16.0, "facade", brng, {"lit": 0.0, "shop": 0.0, "roof": false})
	world.add_child(body)
	bd.build(world)
	_build_back_building()
	_build_courtyard_detail()
	_build_annex()
	_build_tunnel()

## Ministerium hinten am Platz: BP.block kennt nur x-Fassaden, also im um -90° gedrehten Rahmen bauen.
func _build_back_building() -> void:
	var root := Node3D.new()
	root.name = "Ministerium"
	root.rotation_degrees.y = -90.0
	world.add_child(root)
	var bd := BP.Builder.new(mats)
	var body := Geo.static_body()
	var brng := RandomNumberGenerator.new()
	brng.seed = build_seed + 31
	# lokal: x_l = Welt-z, z_l = -Welt-x
	BP.block(bd, body, -1, -162.0, 26.0, -24.0, 20.0, 26.0, "sandstone", brng, {"lit": 0.18, "shop": 0.0})
	# Portal mit Freitreppe in der Mitte
	_sbox(bd, body, "granite", Vector3(-160.6, 0.2, 1.0), Vector3(2.8, 0.4, 12.0))
	_sbox(bd, body, "granite", Vector3(-161.3, 0.5, 1.0), Vector3(1.4, 0.2, 11.0))
	for zl: float in [-4.0, 6.0]:
		_sbox(bd, body, "marble", Vector3(-159.8, 3.5, zl), Vector3(0.9, 7.0, 0.9))
	bd.box("marble", Vector3(-160.0, 7.4, 1.0), Vector3(1.6, 0.8, 12.0))
	bd.box("black", Vector3(-161.75, 2.6, 1.0), Vector3(0.1, 4.4, 4.0))
	root.add_child(body)
	bd.build(root)

func _build_courtyard_detail() -> void:
	var bd := BP.Builder.new(mats)
	var body := Geo.static_body()
	var crng := RandomNumberGenerator.new()
	crng.seed = build_seed + 77
	# Rückseite des Hinterhauses: Hintertüren, Fallrohre, Fensterbänder (meist dunkel)
	for z: float in [-52.0, -66.0, -78.0]:
		bd.box("black", Vector3(-18.05, 1.1, z), Vector3(0.1, 2.2, 1.1))
		bd.box("trim", Vector3(-18.08, 2.3, z), Vector3(0.12, 0.12, 1.4))
	for z: float in [-49.0, -59.0, -71.0, -82.0]:
		bd.box("metal", Vector3(-18.12, 6.5, z), Vector3(0.14, 13.0, 0.14))
	for row in 3:
		for i in 8:
			var z := -48.5 - i * 4.6
			var lit := crng.randf() < 0.12
			bd.box("win_warm" if lit else "black", Vector3(-18.04, 4.2 + row * 3.0, z), Vector3(0.08, 1.4, 1.1))
	# Mülltonnen/Container mit passender Kollision
	for p: Vector3 in [Vector3(-28.8, 0.0, -50.0), Vector3(-28.8, 0.0, -53.0), Vector3(-19.2, 0.0, -73.0)]:
		_sbox(bd, body, "metal", p + Vector3(0, 0.65, 0), Vector3(1.3, 1.3, 2.1))
		bd.box("rack", p + Vector3(0, 1.33, 0), Vector3(1.4, 0.06, 2.2))
	# Holzkisten-Stapel und Paletten
	for p: Vector3 in [Vector3(-27.5, 0.0, -61.0), Vector3(-28.4, 0.0, -62.6), Vector3(-27.6, 0.0, -71.5)]:
		_sbox(bd, body, "crate", p + Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 1.0), crng.randf_range(-20.0, 20.0))
	_sbox(bd, body, "crate", Vector3(-27.5, 1.45, -61.0), Vector3(0.9, 0.9, 0.9), 12.0)
	# Wäscheleinen über den Hof
	var cb := Geo.BoxBatch.new()
	for z: float in [-56.0, -68.0]:
		StreetKit.cable(cb, Vector3(-18.2, 6.0, z), Vector3(-29.9, 6.4, z + 1.5), 0.8, 0.012)
	StreetKit.cables_node(self, cb)
	StreetKit.model(self, "covered_car", Vector3(-22.5, 0.0, -84.0 + 7.0), 90.0)
	world.add_child(body)
	bd.build(world)
	# Hoftor in der nördlichen Gasse (schiebt bei Alarm zu)
	_gate = StaticBody3D.new()
	_gate.name = "Hoftor"
	_gate.position = Vector3(-12.6, 0.0, -49.0 - 3.0)
	var gm := mats["metal"] as Material
	for i in 13:
		_gate.add_child(Geo.box_mesh_node(Vector3(0.06, 2.6, 0.06), gm, Vector3(0, 1.3, -3.0 + i * 0.5)))
	_gate.add_child(Geo.box_mesh_node(Vector3(0.08, 0.1, 6.0), gm, Vector3(0, 2.55, 0)))
	_gate.add_child(Geo.box_mesh_node(Vector3(0.08, 0.1, 6.0), gm, Vector3(0, 0.25, 0)))
	_gate.add_child(Geo.box_mesh_node(Vector3(0.08, 0.1, 6.0), gm, Vector3(0, 1.4, 0)))
	var gcs := Geo.add_box_shape(_gate, Vector3(0, 1.3, 0), Vector3(0.2, 2.6, 6.0))
	gcs.disabled = true
	_gate.set_meta("no_fit", true)
	add_child(_gate)
	# Lesbare Dunkelheit: schwaches Mond-/Streulicht (zählt nicht für die Entdeckung)
	for z: float in [-50.0, -65.0, -80.0]:
		var f := _omni(Vector3(-24.0, 9.0, z), Color(0.45, 0.55, 1.0), 0.45, 17.0, 0.0)
		f.set_meta("no_stealth", true)
	for p: Vector3 in [Vector3(-18.6, 4.4, -57.7), Vector3(-18.6, 7.4, -71.5)]:
		var w := _omni(p, Color(1.0, 0.72, 0.42), 0.35, 5.0, 0.2)
		w.set_meta("no_stealth", true)
		add_child(Geo.box_mesh_node(Vector3(0.08, 1.4, 1.1), mats["win_warm"], Vector3(-18.04, p.y - 0.2, p.z)))
	# einzige Hoflampe über der Hintertür: ein Lichtkegel, den man meiden muss
	Props.lamp(self, Vector3(-18.5, 0.0, -66.0), -90.0, true, 0.0, true)

## Ministeriumsanbau mit Lieferzufahrt, Ladehalle, Flur, Büro, Fernmeldestelle, Rückhalle und Schacht.
func _build_annex() -> void:
	var bd := BP.Builder.new(mats)
	var body := Geo.static_body()
	body.name = "Anbau"
	var arng := RandomNumberGenerator.new()
	arng.seed = build_seed + 99
	var H := 16.0
	var CH := 4.5
	# Außenwände: Nord (zur Zufahrt) mit Rolltor x 34..38, Ost, Süd; Decke, Dach
	_sbox(bd, body, "concrete", Vector3(29.5, H / 2.0, -118.3), Vector3(9.0, H, 0.6))
	_sbox(bd, body, "concrete", Vector3(42.0, H / 2.0, -118.3), Vector3(8.0, H, 0.6))
	_sbox(bd, body, "concrete", Vector3(36.0, (H + 3.8) / 2.0, -118.3), Vector3(4.0, H - 3.8, 0.6))
	_sbox(bd, body, "concrete", Vector3(45.7, H / 2.0, -140.0), Vector3(0.6, H, 44.0))
	_sbox(bd, body, "concrete", Vector3(35.0, H / 2.0, -161.7), Vector3(22.0, H, 0.6))
	_sbox(bd, body, "ceiling", Vector3(35.2, CH + 0.15, -140.0), Vector3(20.4, 0.3, 42.8))
	bd.box("dark", Vector3(35.0, H + 0.1, -140.0), Vector3(22.4, 0.2, 44.4))
	bd.box("trim", Vector3(35.0, H - 0.3, -117.95), Vector3(22.4, 0.5, 0.2))
	# Rolltor halb offen (Panzer oben im Kasten), Rahmen, Warnstreifen
	bd.box("shutter", Vector3(36.0, 3.3, -118.05), Vector3(4.0, 0.9, 0.12))
	bd.box("metal", Vector3(36.0, 3.95, -117.85), Vector3(4.4, 0.5, 0.5))
	for sx: float in [-1.0, 1.0]:
		bd.box("warn", Vector3(36.0 + sx * 2.06, 1.5, -117.98), Vector3(0.12, 3.0, 0.08))
	_label("ANLIEFERUNG  B", Vector3(36.0, 4.6, -117.94), 180.0, 64, Color(0.75, 0.75, 0.7))
	# Wandleuchte über dem Rolltor (Lichtpfütze in der Zufahrt), Kabelkanal, Rohre
	bd.box("metal", Vector3(36.0, 4.45, -117.75), Vector3(0.5, 0.2, 0.3))
	var lane_l := _spot(Vector3(36.0, 4.35, -117.6), Vector3(36.0, 0.0, -113.5), Color(1.0, 0.78, 0.5), 6.0, 10.0, 48.0, 1.6, true)
	lane_l.name = "ZufahrtLicht"
	for x: float in [26.5, 44.5]:
		bd.box("metal", Vector3(x, 7.0, -117.9), Vector3(0.18, 14.0, 0.18))
	bd.box("metal", Vector3(35.0, 5.4, -117.88), Vector3(21.0, 0.14, 0.14))
	# Innen: Bodenbelag, Wände (Höhe 4,5)
	bd.box("lino", Vector3(35.2, 0.01, -140.0), Vector3(20.4, 0.02, 42.8))
	var walls: Array = [
		# W1 z -128 (Tür x 35..37)
		[Vector3(30.0, CH / 2.0, -128.0), Vector3(10.0, CH, 0.3)],
		[Vector3(41.2, CH / 2.0, -128.0), Vector3(8.4, CH, 0.3)],
		[Vector3(36.0, (CH + 2.4) / 2.0, -128.0), Vector3(2.0, CH - 2.4, 0.3)],
		# W2 z -132 (Türen x 28..30 und 38..40)
		[Vector3(26.5, CH / 2.0, -132.0), Vector3(3.0, CH, 0.3)],
		[Vector3(34.0, CH / 2.0, -132.0), Vector3(8.0, CH, 0.3)],
		[Vector3(42.7, CH / 2.0, -132.0), Vector3(5.4, CH, 0.3)],
		[Vector3(29.0, (CH + 2.4) / 2.0, -132.0), Vector3(2.0, CH - 2.4, 0.3)],
		[Vector3(39.0, (CH + 2.4) / 2.0, -132.0), Vector3(2.0, CH - 2.4, 0.3)],
		# W3 x 34 (Tür z -139..-141)
		[Vector3(34.0, CH / 2.0, -135.5), Vector3(0.3, CH, 7.0)],
		[Vector3(34.0, CH / 2.0, -144.5), Vector3(0.3, CH, 7.0)],
		[Vector3(34.0, (CH + 2.4) / 2.0, -140.0), Vector3(0.3, CH - 2.4, 2.0)],
		# W4 z -148 (Tür x 41..43)
		[Vector3(33.0, CH / 2.0, -148.0), Vector3(16.0, CH, 0.3)],
		[Vector3(44.2, CH / 2.0, -148.0), Vector3(2.4, CH, 0.3)],
		[Vector3(42.0, (CH + 2.4) / 2.0, -148.0), Vector3(2.0, CH - 2.4, 0.3)],
	]
	for w: Array in walls:
		_sbox(bd, body, "plaster", w[0], w[1])
		# dunkler Sockelstreifen
		var c: Vector3 = w[0]
		var s: Vector3 = w[1]
		if c.y < CH / 2.0 + 0.01:
			bd.box("plaster_low", Vector3(c.x, 0.6, c.z), Vector3(s.x + 0.02, 1.2, s.z + 0.02))
	# Sockel an den Außenwänden innen
	bd.box("plaster_low", Vector3(45.38, 0.6, -140.0), Vector3(0.04, 1.2, 42.8))
	bd.box("plaster_low", Vector3(25.02, 0.6, -140.0), Vector3(0.04, 1.2, 42.8))
	# Türzargen und offene Türblätter
	for d: Array in [[Vector3(36.0, 0, -128.0), 0.0], [Vector3(29.0, 0, -132.0), 0.0], [Vector3(39.0, 0, -132.0), 0.0], [Vector3(34.0, 0, -140.0), 90.0], [Vector3(42.0, 0, -148.0), 0.0]]:
		var dp: Vector3 = d[0]
		var yaw: float = d[1]
		var R := Basis(Vector3.UP, deg_to_rad(yaw))
		for sx: float in [-1.0, 1.0]:
			bd.box("metal", dp + R * Vector3(sx * 1.02, 1.2, 0), Vector3(0.06, 2.4, 0.36), R)
		bd.box("metal", dp + R * Vector3(0, 2.43, 0), Vector3(2.1, 0.06, 0.36), R)
		# Türblatt um 90° an die Wand geklappt
		_sbox(bd, body, "shutter", dp + R * Vector3(-0.98, 1.1, -0.55), Vector3(0.05, 2.2, 0.95), yaw)
	# Schilder
	_label("FERNMELDESTELLE 4\nZUTRITT NUR MIT BEFUGNIS", Vector3(39.0, 2.85, -131.83), 180.0, 40, Color(0.85, 0.82, 0.75), 0.004)
	_label("BÜRO 4.12", Vector3(29.0, 2.75, -131.83), 180.0, 40, Color(0.85, 0.82, 0.75), 0.004)
	_label("LAGER / ANLIEFERUNG", Vector3(36.0, 2.75, -128.17), 0.0, 40, Color(0.85, 0.82, 0.75), 0.004)
	# --- Ladehalle: Kistenstapel, Regale, Lieferwagen
	for p: Vector3 in [Vector3(27.0, 0, -120.5), Vector3(28.3, 0, -120.5), Vector3(27.0, 0, -121.8), Vector3(31.0, 0, -126.6), Vector3(32.3, 0, -126.6)]:
		_sbox(bd, body, "crate", p + Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 1.2), arng.randf_range(-6.0, 6.0))
	_sbox(bd, body, "crate", Vector3(27.0, 1.75, -120.5), Vector3(1.1, 1.1, 1.1), 8.0)
	for i in 3:
		var z := -120.0 - i * 2.6
		_sbox(bd, body, "metal", Vector3(44.6, 1.6, z), Vector3(1.0, 3.2, 2.4))
		for k in 3:
			bd.box("crate", Vector3(44.5, 0.55 + k * 1.05, z + arng.randf_range(-0.4, 0.4)), Vector3(0.8, 0.6, 1.2))
	Props.vehicle(self, Vector3(29.6, 0.0, -124.0), 0.0, "van", Color(0.16, 0.17, 0.18), false, false, covers)
	# Paletten
	for p: Vector3 in [Vector3(39.5, 0, -126.5), Vector3(41.0, 0, -126.5)]:
		_sbox(bd, body, "crate", p + Vector3(0, 0.07, 0), Vector3(1.2, 0.14, 1.0))
	# --- Flur: Feuerlöscher, Anschlagbrett, Leuchtstoffröhren
	bd.cyl("red_light", Vector3(25.4, 0.95, -130.0), 0.09, 0.09, 0.55, 10)
	bd.box("crate", Vector3(45.33, 1.6, -130.0), Vector3(0.04, 1.0, 1.6))
	for i in 5:
		bd.box("paper", Vector3(45.3, 1.5 + (i % 2) * 0.35, -130.6 + i * 0.3), Vector3(0.02, 0.28, 0.21))
	for x: float in [27.0, 31.5, 36.0, 40.5, 44.0]:
		var on := x == 31.5 or x == 40.5
		bd.box("fluor" if on else "fluor_off", Vector3(x, CH - 0.06, -130.0), Vector3(1.3, 0.06, 0.18))
		if on:
			_omni(Vector3(x, CH - 0.35, -130.0), Color(0.82, 0.9, 1.0), 1.6, 6.0, 0.0)
	# Ladehalle: eine Arbeitsleuchte
	bd.box("fluor", Vector3(40.0, CH - 0.06, -123.0), Vector3(1.3, 0.06, 0.18))
	_omni(Vector3(40.0, CH - 0.4, -123.0), Color(1.0, 0.85, 0.65), 2.0, 9.0, 0.0, true)
	# --- Büro: Schreibtische, Aktenschränke, Porträt, Schreibtischlampe
	for p: Vector3 in [Vector3(27.5, 0, -136.0), Vector3(31.0, 0, -136.0), Vector3(27.5, 0, -143.0)]:
		_sbox(bd, body, "desk", p + Vector3(0, 0.74, 0), Vector3(1.6, 0.05, 0.8))
		_sbox(bd, body, "rack", p + Vector3(-0.7, 0.36, 0), Vector3(0.08, 0.72, 0.72))
		_sbox(bd, body, "rack", p + Vector3(0.7, 0.36, 0), Vector3(0.08, 0.72, 0.72))
		bd.box("rack", p + Vector3(0, 0.98, 0.2), Vector3(0.5, 0.36, 0.05))
		bd.box("paper", p + Vector3(0.4, 0.78, -0.1), Vector3(0.3, 0.03, 0.22))
	for z: float in [-133.5, -135.0, -146.5]:
		_sbox(bd, body, "metal", Vector3(25.45, 0.95, z), Vector3(0.7, 1.9, 1.2))
	_omni(Vector3(31.4, 1.25, -136.0), Color(1.0, 0.75, 0.45), 0.7, 3.2, 0.2)
	bd.box("amber", Vector3(31.4, 1.05, -136.1), Vector3(0.18, 0.04, 0.18))
	_portrait(Vector3(25.06, 2.6, -140.0), -90.0)
	# --- Fernmeldestelle: Serverschränke, Pult des Funkers, Kabelpritsche
	for i in 5:
		var z := -133.4 - i * 1.0
		_rack(bd, body, Vector3(44.95, 0, z), arng)
	for i in 4:
		var z := -141.0 - i * 1.0
		_rack(bd, body, Vector3(38.5, 0, z), arng)
	_sbox(bd, body, "desk", Vector3(34.75, 0.78, -137.5), Vector3(0.9, 0.06, 2.6))
	_sbox(bd, body, "rack", Vector3(34.6, 0.39, -137.5), Vector3(0.6, 0.78, 2.4))
	for k in 3:
		bd.box("rack", Vector3(34.45, 1.2, -136.7 - k * 0.8), Vector3(0.06, 0.45, 0.65))
		bd.box("led_b", Vector3(34.49, 1.2, -136.7 - k * 0.8), Vector3(0.01, 0.38, 0.58))
	bd.box("metal", Vector3(41.0, CH - 0.35, -140.0), Vector3(0.4, 0.08, 15.0))
	_omni(Vector3(39.5, 3.8, -137.5), Color(0.5, 0.65, 1.0), 0.7, 7.0, 0.0)
	_omni(Vector3(43.5, 3.4, -136.0), Color(0.4, 1.0, 0.6), 0.35, 4.5, 0.1)
	# Kabel und Lüftung
	bd.box("metal", Vector3(35.2, CH - 0.3, -125.0), Vector3(19.0, 0.35, 0.5))
	# --- Rückhalle: Schacht mit Geländer, Notausgang-Schild
	for sx: float in [41.0, 44.0]:
		_sbox(bd, body, "metal", Vector3(sx, 0.55, -155.0), Vector3(0.08, 1.1, 10.0))
	_sbox(bd, body, "metal", Vector3(42.5, 0.55, -160.0), Vector3(3.08, 1.1, 0.08))
	for sx: float in [41.0, 44.0]:
		bd.box("metal", Vector3(sx, 1.08, -155.0), Vector3(0.1, 0.06, 10.0))
	bd.box("exit_green", Vector3(42.5, 3.1, -148.17), Vector3(1.0, 0.32, 0.03))
	_label("NOTAUSGANG U-BAHN", Vector3(42.5, 3.1, -148.2), 180.0, 30, Color(0.05, 0.1, 0.05), 0.004)
	var ex := _omni(Vector3(42.5, 2.9, -149.0), Color(0.3, 1.0, 0.5), 0.6, 4.0, 0.3)
	ex.set_meta("no_stealth", true)
	# Rückhalle: eine flackerfreie Notleuchte, eine kaputte
	bd.box("fluor", Vector3(33.0, CH - 0.06, -154.0), Vector3(1.3, 0.06, 0.18))
	bd.box("fluor", Vector3(39.5, CH - 0.06, -156.0), Vector3(1.3, 0.06, 0.18))
	bd.box("fluor_off", Vector3(28.0, CH - 0.06, -158.0), Vector3(1.3, 0.06, 0.18))
	_omni(Vector3(39.5, CH - 0.4, -156.0), Color(0.78, 0.86, 1.0), 1.1, 7.5, 0.0)
	_omni(Vector3(33.0, CH - 0.4, -154.0), Color(0.8, 0.88, 1.0), 1.4, 8.0, 0.0, true)
	var fill := _omni(Vector3(40.0, 3.0, -140.0), Color(0.4, 0.5, 0.8), 0.35, 14.0, 0.0)
	fill.set_meta("no_stealth", true)
	for p: Vector3 in [Vector3(27.0, 0, -150.0), Vector3(28.4, 0, -150.0), Vector3(27.0, 0, -159.5), Vector3(32.0, 0, -160.2)]:
		_sbox(bd, body, "crate", p + Vector3(0, 0.6, 0), Vector3(1.2, 1.2, 1.2), arng.randf_range(-10.0, 10.0))
	# Treppenschacht: Rampe (Kollision) + Stufen (Optik), Wände bis zum Tunnel
	var slope := atan2(5.0, 10.0)
	var rlen := sqrt(125.0)
	var n := Vector3(0, cos(slope), -sin(slope))
	var rc := Vector3(42.5, -2.5, -155.0) - n * 0.2
	var rb := StaticBody3D.new()
	rb.name = "Treppe"
	var rcs := CollisionShape3D.new()
	var rbs := BoxShape3D.new()
	rbs.size = Vector3(3.0, 0.4, rlen)
	rcs.shape = rbs
	rcs.transform = Transform3D(Basis(Vector3.RIGHT, -slope), rc)
	rb.add_child(rcs)
	world.add_child(rb)
	for i in 20:
		var y := -0.25 * float(i + 1) + 0.12
		var z := -150.0 - 0.5 * float(i) - 0.25
		bd.box("concrete", Vector3(42.5, y - 0.5, z), Vector3(3.0, 1.0, 0.5))
		bd.box("warn", Vector3(42.5, y + 0.005, z + 0.22), Vector3(2.9, 0.01, 0.05))
	for sx: float in [40.8, 44.2]:
		_sbox(bd, body, "concrete", Vector3(sx, -2.5, -155.0), Vector3(0.4, 5.0, 10.0))
		bd.box("metal", Vector3(sx + (0.25 if sx < 42.0 else -0.25), 0.0, -155.0), Vector3(0.05, 0.05, 11.2), Basis(Vector3.RIGHT, -slope))
	# Schachtbeleuchtung (Notleuchte)
	bd.box("fluor", Vector3(42.5, -0.95, -158.0), Vector3(0.6, 0.06, 0.2))
	_omni(Vector3(42.5, -1.3, -157.5), Color(0.75, 0.85, 1.0), 0.8, 6.0, 0.3)
	world.add_child(body)
	bd.build(world)
	# Innenräume ohne Außennebel (negativer Nebel), sonst wirken die Räume milchig
	_fog_cut(Vector3(35.2, 2.3, -140.0), Vector3(20.6, 4.8, 43.0))
	# Portal zur Platzseite (geschlossene Flügeltür, Fahnenhalter, Wachlampe)
	var pb := BP.Builder.new(mats)
	var pbody := Geo.static_body()
	_sbox(pb, pbody, "granite", Vector3(23.4, 0.15, -140.0), Vector3(1.2, 0.3, 8.0))
	for z: float in [-137.2, -142.8]:
		_sbox(pb, pbody, "marble", Vector3(23.55, 3.0, z), Vector3(0.7, 6.0, 0.7))
	pb.box("marble", Vector3(23.6, 6.3, -140.0), Vector3(0.9, 0.6, 7.0))
	pb.box("black", Vector3(23.85, 2.0, -140.0), Vector3(0.1, 3.8, 2.6))
	pb.box("trim", Vector3(23.83, 4.05, -140.0), Vector3(0.12, 0.2, 2.9))
	world.add_child(pbody)
	pb.build(world)
	_omni(Vector3(22.6, 4.6, -140.0), Color(1.0, 0.8, 0.55), 2.2, 8.0, 0.8)
	_label("BUNDESMINISTERIUM DES INNERN\nDIENSTGEBÄUDE ANBAU", Vector3(23.82, 7.4, -140.0), -90.0, 64, Color(0.85, 0.8, 0.7), 0.008)

func _fog_cut(pos: Vector3, size: Vector3, density: float = -1.0) -> void:
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fv.size = size
	var fm := FogMaterial.new()
	fm.density = density
	fm.albedo = Color(1, 1, 1)
	fv.material = fm
	fv.position = pos
	add_child(fv)

func _rack(bd: BP.Builder, body: StaticBody3D, p: Vector3, r: RandomNumberGenerator) -> void:
	_sbox(bd, body, "rack", p + Vector3(0, 1.05, 0), Vector3(0.8, 2.1, 0.95))
	var face := -1.0 if p.x > 40.0 else 1.0
	for k in 7:
		var y := 0.35 + k * 0.25
		bd.box("dark", p + Vector3(face * 0.41, y, 0), Vector3(0.02, 0.18, 0.86))
		for j in 3:
			if r.randf() < 0.7:
				var key: String = ["led_g", "led_g", "led_b", "led_r"][r.randi() % 4]
				bd.box(key, p + Vector3(face * 0.425, y + 0.04, -0.3 + j * 0.06 + r.randf() * 0.4), Vector3(0.01, 0.018, 0.018))

func _portrait(pos: Vector3, yaw: float) -> void:
	if not ResourceLoader.exists(EMBLEM):
		return
	var em := StandardMaterial3D.new()
	em.albedo_texture = load(EMBLEM)
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var frame := Geo.box_mesh_node(Vector3(1.0, 1.2, 0.05), Geo.flat(Color(0.12, 0.09, 0.05), 0.6), pos)
	frame.rotation_degrees.y = yaw
	add_child(frame)
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = em
	mi.position = pos + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0.05, 0.03)
	mi.rotation_degrees.y = yaw
	add_child(mi)

## U-Bahn-Tunnel: x 38..46, z -160..-212, Boden y -5, Decke y -1.
func _build_tunnel() -> void:
	var bd := BP.Builder.new(mats)
	var body := Geo.static_body()
	body.name = "Tunnel"
	var trng := RandomNumberGenerator.new()
	trng.seed = build_seed + 123
	var z0 := -160.0
	var z1 := -212.0
	var L := absf(z1 - z0)
	var cz := (z0 + z1) / 2.0
	_sbox(bd, body, "gravel", Vector3(42.0, -5.5, cz), Vector3(8.0, 1.0, L))
	_sbox(bd, body, "concrete", Vector3(42.0, -0.9, cz), Vector3(8.0, 0.2, L))
	for sx: float in [-1.0, 1.0]:
		var wx := 42.0 + sx * 4.2
		_sbox(bd, body, "tile", Vector3(wx, -3.0, cz), Vector3(0.4, 4.0, L))
		bd.box("tile_band", Vector3(wx - sx * 0.205, -3.4, cz), Vector3(0.01, 0.3, L))
		# Gewölbeansatz
		bd.box("concrete", Vector3(42.0 + sx * 3.6, -1.35, cz), Vector3(1.2, 0.5, L), Basis(Vector3.BACK, sx * 0.6))
		# Kabelpritschen
		for k in 3:
			bd.box("rack", Vector3(wx - sx * 0.28, -2.1 - k * 0.22, cz), Vector3(0.16, 0.03, L))
	# Stirnwände: Nord neben dem Schachtende, Süd verschüttet
	_sbox(bd, body, "concrete", Vector3(39.4, -3.0, -159.8), Vector3(2.8, 4.0, 0.4))
	_sbox(bd, body, "concrete", Vector3(45.2, -3.0, -159.8), Vector3(1.6, 4.0, 0.4))
	_sbox(bd, body, "concrete", Vector3(42.0, -3.0, z1 - 0.2), Vector3(8.4, 4.0, 0.4))
	Props.rubble(self, Vector3(42.0, -5.0, z1 + 1.8), 3.2, 1.6, trng, true)
	# Gleise: Schwellen und Schienen (flach, begehbar)
	var z := z0 - 1.0
	while z > z1 + 1.0:
		bd.box("sleeper", Vector3(43.0, -4.96, z), Vector3(2.6, 0.08, 0.26))
		z -= 0.75
	for x: float in [42.25, 43.75]:
		bd.box("rail", Vector3(x, -4.88, cz), Vector3(0.07, 0.1, L - 2.0))
	# Bahnsteigkante links (flach), Notbeleuchtung: wenige Leuchten funktionieren
	bd.box("warn", Vector3(40.4, -4.99, cz - 4.0), Vector3(0.25, 0.02, L - 12.0))
	var lz := -166.0
	var idx := 0
	while lz > z1 + 3.0:
		var on := idx % 3 != 1
		bd.box("fluor" if on else "fluor_off", Vector3(45.9, -1.9, lz), Vector3(0.12, 0.2, 0.5))
		bd.box("metal", Vector3(45.95, -1.9, lz), Vector3(0.1, 0.32, 0.64))
		if on:
			_omni(Vector3(45.5, -2.0, lz), Color(1.0, 0.8, 0.55), 1.0, 7.0, 0.5)
		lz -= 9.0
		idx += 1
	# Graffiti des Widerstands
	_label("FREIHEIT", Vector3(37.81, -2.9, -176.0), 90.0, 120, Color(0.8, 0.2, 0.15), 0.012)
	_label("WIR SIND NOCH DA", Vector3(46.19, -3.2, -188.0), -90.0, 90, Color(0.85, 0.85, 0.8), 0.01)
	_label("U2  ←  MOHRENSTRASSE", Vector3(37.81, -2.0, -166.0), 90.0, 48, Color(0.9, 0.9, 0.85), 0.008)
	world.add_child(body)
	bd.build(world)
	_fog_cut(Vector3(42.0, -3.0, -186.0), Vector3(8.4, 4.2, 53.0), -0.009)
	Props.fog_volume(self, Vector3(42.0, -4.7, -185.0), Vector3(8.0, 1.2, 50.0), 0.02, Color(0.6, 0.62, 0.65))
	# Voss und zwei Kämpfer mit Laterne
	_figure(VOSS_POS, -60.0, "coat")
	_figure(Vector3(39.4, -5.0, -202.5), -20.0, "coat2")
	_figure(Vector3(44.6, -5.0, -203.5), 30.0, "coat2")
	var lan := MeshInstance3D.new()
	var lb := BoxMesh.new()
	lb.size = Vector3(0.2, 0.3, 0.2)
	lan.mesh = lb
	lan.material_override = mats["amber"]
	lan.position = Vector3(41.4, -4.85, -200.5)
	add_child(lan)
	var ll := _omni(Vector3(41.4, -4.3, -200.5), Color(1.0, 0.7, 0.38), 2.4, 9.0, 1.2, true)
	ll.set_meta("no_stealth", true)

func _figure(pos: Vector3, yaw: float, coat: String) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw
	add_child(root)
	var cm: Material = mats[coat]
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

# ------------------------------------------------------------------ Requisiten

func _build_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	add_child(props)
	var prng := RandomNumberGenerator.new()
	prng.seed = build_seed + 5
	# Start: ausgebrannter Bus quer über der Straße, dahinter Kerner
	Props.vehicle(props, Vector3(-3.4, 0.0, 1.5), 78.0, "bus", Color(0.3, 0.28, 0.25), true, false, covers)
	Props.fire(props, Vector3(-6.2, 0.4, 2.2), 0.6, true, 1.6, 2.2)
	# Straße: ausgebrannte Autos, Barrikaden, Müll
	Props.vehicle(props, Vector3(5.2, 0.0, -11.0), 8.0, "car", Color(0.25, 0.22, 0.2), true, false, covers)
	Props.vehicle(props, Vector3(-4.8, 0.0, -24.0), -12.0, "car", Color(0.2, 0.25, 0.3), true, false, covers)
	Props.vehicle(props, Vector3(9.5, 0.0, -38.0), 4.0, "car", Color(0.4, 0.38, 0.33), false, false, covers)
	Props.vehicle(props, Vector3(-5.6, 0.0, -46.0), 172.0, "van", Color(0.32, 0.3, 0.28), true, false, covers)
	Props.fire(props, Vector3(-5.6, 1.6, -46.0), 0.5, true, 2.0, 1.4)
	Props.vehicle(props, Vector3(5.4, 0.0, -84.0), -6.0, "car", Color(0.18, 0.18, 0.2), true, true, covers, 0.0)
	Props.vehicle(props, Vector3(-5.0, 0.0, -100.0), 190.0, "car", Color(0.3, 0.1, 0.08), true, false, covers)
	for p: Vector3 in [Vector3(-9.8, 0, -18.0), Vector3(10.0, 0, -58.0), Vector3(-10.0, 0, -94.0)]:
		Props.sandbags(props, p, 0.0, 2.4, prng, covers)
	Props.rubble(props, Vector3(10.2, 0.0, -22.0), 1.6, 0.6, prng, true, covers)
	Props.rubble(props, Vector3(-10.4, 0.0, -78.0), 1.4, 0.5, prng, true, covers)
	# Kontrollpunkt (z -62): Betonsperren mit Durchlass, Häuschen, Schranke hoch, Flutlicht
	for x: float in [-6.0, -3.4, 3.4, 6.0]:
		Props.jersey(props, Vector3(x, 0.0, -62.0), 90.0, covers)
	var fb := Geo.BoxBatch.new()
	StreetKit.barrier_fence(fb, Vector3(-7.4, 0.0, -62.0), -90.0, 2, prng)
	StreetKit.fences_node(props, fb)
	var cbd := BP.Builder.new(mats)
	var cbody := Geo.static_body()
	_sbox(cbd, cbody, "concrete", Vector3(-9.8, 1.2, -62.0), Vector3(4.4, 2.4, 0.5))
	# Wachhäuschen rechts
	_sbox(cbd, cbody, "canvas_white", Vector3(9.6, 1.3, -63.0), Vector3(2.4, 2.6, 2.4))
	cbd.box("dark", Vector3(9.6, 2.7, -63.0), Vector3(2.7, 0.2, 2.7))
	cbd.box("win_warm", Vector3(8.38, 1.7, -63.0), Vector3(0.04, 0.8, 1.6))
	cbd.box("red_light", Vector3(8.4, 2.45, -61.9), Vector3(0.1, 0.12, 0.1))
	_sbox(cbd, cbody, "concrete", Vector3(10.6, 1.2, -61.0), Vector3(3.0, 2.4, 0.5))
	_sbox(cbd, cbody, "concrete", Vector3(9.6, 1.2, -60.4), Vector3(4.6, 2.4, 0.5))
	# Schranke (hochgeklappt) am Durchlass
	cbd.box("canvas_white", Vector3(2.1, 0.55, -62.0), Vector3(0.3, 1.1, 0.3))
	for i in 6:
		var key := "canvas_red" if i % 2 == 0 else "canvas_white"
		cbd.box(key, Vector3(2.1, 1.3 + i * 0.55, -62.0), Vector3(0.1, 0.55, 0.1))
	props.add_child(cbody)
	cbd.build(props)
	_label("KONTROLLPUNKT 7\nAUSWEISE BEREITHALTEN", Vector3(-9.8, 1.6, -61.73), 0.0, 44, Color(0.9, 0.85, 0.7), 0.006)
	for sx: float in [-1.0, 1.0]:
		var mp := Vector3(sx * 7.6, 0.0, -66.0)
		props.add_child(Geo.cylinder_node(0.1, 6.0, mats["metal"], mp + Vector3(0, 3.0, 0), Vector3.ZERO, 8))
		props.add_child(Geo.box_mesh_node(Vector3(0.7, 0.45, 0.35), mats["dark"], mp + Vector3(-sx * 0.2, 6.0, 0.15)))
		var fl := _spot(mp + Vector3(-sx * 0.3, 5.9, 0.3), Vector3(sx * 1.0, 0.0, -58.0), Color(0.92, 0.95, 1.0), 9.0, 18.0, 34.0, 1.8, true)
		fl.name = "KontrollFlutlicht"
		var beam := SearchlightScript.beam_mesh(11.0, 0.25, 6.0, 0.035, Color(0.9, 0.95, 1.0))
		fl.add_child(beam)
		var pole := StaticBody3D.new()
		Geo.add_box_shape(pole, mp + Vector3(0, 3.0, 0), Vector3(0.24, 6.0, 0.24))
		props.add_child(pole)
	Props.fire(props, Vector3(8.6, 0.55, -66.0), 0.4, true, 1.2, 1.6)
	props.add_child(Geo.cylinder_node(0.3, 0.9, mats["metal"], Vector3(8.6, 0.45, -66.0), Vector3.ZERO, 12))
	# Straßenlampen: viele aus, wenige brennen (Lichtinseln)
	var lamps: Array = [[-7.6, -4.0, false], [7.6, -18.0, true], [-7.6, -32.0, false], [7.6, -46.0, false],
		[-7.6, -78.0, true], [7.6, -92.0, false], [-7.6, -106.0, true]]
	for l: Array in lamps:
		var lx: float = l[0]
		Props.lamp(props, Vector3(lx, 0.0, l[1]), 90.0 if lx < 0.0 else -90.0, l[2], 0.0, l[2])
	StreetKit.traffic_light(props, Vector3(7.5, 0.0, -108.0), -90.0, "amber_blink")
	StreetKit.traffic_light(props, Vector3(-7.5, 0.0, 6.0), 90.0, "amber_blink")
	var sb := Geo.BoxBatch.new()
	StreetKit.sign_post(sb, props, Vector3(-7.4, 0.0, -56.0), 180.0, "red")
	StreetKit.dress_street(props, {"road": 7.0, "wall": 12.0, "y_walk": 0.02, "z0": 8.0, "z1": -108.0, "style": "war", "seed": build_seed,
		"avoid": [Vector2(-12, -62), Vector2(12, -62), Vector2(-12, -43), Vector2(-12, -87), Vector2(12, -33), Vector2(12, -79)]})
	# Propagandaschirme und Plakate
	_screen(Vector3(11.6, 8.0, -52.0), -90.0, Vector2(8.0, 4.5), 3.5, 0.5)
	_screen(Vector3(-11.6, 9.0, -100.0), 90.0, Vector2(7.0, 4.0), 3.0, 1.4)
	_screen(Vector3(-25.6, 12.0, -128.0), 90.0, Vector2(12.0, 6.8), 5.0, 0.2)
	_screen(Vector3(0.0, 13.5, -161.6), 0.0, Vector2(14.0, 7.8), 5.5, 0.9)
	_banners()
	_build_plaza_props(props, prng)
	_build_alarm_lights()

func _screen(pos: Vector3, yaw: float, size: Vector2, energy: float, delay: float) -> void:
	var s := Screen.new()
	s.set("size", size)
	s.set("light_energy", energy)
	s.set("slogans", ["AUSGANGSSPERRE 22–05 UHR", "ORDNUNG.", "WER DRAUSSEN IST, IST SCHULDIG.", "DAS LETZTE REICH."] as Array[String])
	s.position = pos
	s.rotation_degrees.y = yaw
	add_child(s)
	s.call("power_on", delay)

func _banners() -> void:
	if not ResourceLoader.exists(EMBLEM):
		return
	var em := StandardMaterial3D.new()
	em.albedo_texture = load(EMBLEM)
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	em.emission_enabled = true
	em.emission_texture = em.albedo_texture
	em.emission = Color(1, 1, 1)
	em.emission_energy_multiplier = 0.5
	var black := Geo.flat(Color(0.02, 0.02, 0.025), 0.9)
	var defs: Array = [[Vector3(-25.85, 0, -116.0), 90.0], [Vector3(-25.85, 0, -156.0), 90.0], [Vector3(-12.0, 0, -161.85), 0.0], [Vector3(12.0, 0, -161.85), 0.0], [Vector3(23.85, 0, -126.0), -90.0], [Vector3(23.85, 0, -154.0), -90.0]]
	for d: Array in defs:
		var p: Vector3 = d[0]
		var yaw: float = d[1]
		var R := Basis(Vector3.UP, deg_to_rad(yaw))
		var b := Geo.box_mesh_node(Vector3(3.2, 10.0, 0.06), black, p + Vector3(0, 11.0, 0))
		b.rotation_degrees.y = yaw
		add_child(b)
		var q := QuadMesh.new()
		q.size = Vector2(2.6, 2.6)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = em
		mi.position = p + Vector3(0, 13.0, 0) + R * Vector3(0, 0, 0.05)
		mi.rotation_degrees.y = yaw
		add_child(mi)
		var bar := Geo.box_mesh_node(Vector3(3.2, 0.14, 0.1), mats["amber"], p + Vector3(0, 6.1, 0) + R * Vector3(0, 0, 0.06))
		bar.rotation_degrees.y = yaw
		add_child(bar)

func _build_plaza_props(props: Node3D, prng: RandomNumberGenerator) -> void:
	# Denkmal in der Mitte mit "ewiger Flamme" (Licht in der Platzmitte)
	var bd := BP.Builder.new(mats)
	var body := Geo.static_body()
	_sbox(bd, body, "granite", Vector3(0, 0.3, -136.0), Vector3(7.0, 0.6, 7.0))
	_sbox(bd, body, "marble", Vector3(0, 2.6, -136.0), Vector3(2.4, 4.0, 2.4))
	bd.box("trim", Vector3(0, 4.7, -136.0), Vector3(2.8, 0.3, 2.8))
	bd.box("dark", Vector3(0, 5.2, -136.0), Vector3(1.4, 0.7, 1.4))
	props.add_child(body)
	bd.build(props)
	Props.fire(props, Vector3(0, 5.6, -136.0), 0.55, true, 2.5, 3.2)
	_label("FÜR ORDNUNG UND VATERLAND", Vector3(0, 2.6, -134.78), 0.0, 52, Color(0.75, 0.68, 0.5), 0.006)
	# Fahrzeuge der Ordnungsfront, Sperren
	Props.vehicle(props, Vector3(-15.0, 0.0, -121.0), 30.0, "truck", Color(0.1, 0.11, 0.1), false, false, covers)
	Props.vehicle(props, Vector3(14.5, 0.0, -150.0), -100.0, "truck", Color(0.1, 0.11, 0.1), false, false, covers)
	Props.vehicle(props, Vector3(29.5, 0.0, -111.4), 90.0, "truck", Color(0.18, 0.18, 0.17), false, false, covers)
	Props.vehicle(props, Vector3(9.0, 0.0, -128.0), -20.0, "van", Color(0.12, 0.12, 0.13), false, false, covers)
	Props.vehicle(props, Vector3(-11.0, 0.0, -150.0), 140.0, "car", Color(0.2, 0.2, 0.22), true, true, covers, 0.0)
	for p: Array in [[Vector3(-6.0, 0, -120.0), 0.0], [Vector3(6.5, 0, -142.0), 30.0], [Vector3(-7.0, 0, -152.0), 90.0], [Vector3(17.5, 0, -136.0), 0.0]]:
		Props.jersey(props, p[0], p[1], covers)
	for p: Vector3 in [Vector3(-17.0, 0, -142.0), Vector3(19.0, 0, -122.0), Vector3(3.0, 0, -156.0)]:
		Props.hedgehog(props, p, prng.randf() * 90.0, covers)
	Props.sandbags(props, Vector3(19.5, 0.0, -130.0), 0.0, 3.0, prng, covers)
	Props.sandbags(props, Vector3(-16.0, 0.0, -132.0), 90.0, 2.4, prng, covers)
	# Wenige Platzlaternen
	for p: Array in [[Vector3(-19.0, 0, -112.5), true], [Vector3(-19.0, 0, -146.0), false], [Vector3(20.0, 0, -144.0), true]]:
		var lp: Vector3 = p[0]
		Props.lamp(props, lp, -90.0 if lp.x < 0.0 else 90.0, p[1], 0.0, p[1])
	# Zufahrt: Müllcontainer, Kabel, Paletten
	var lbd := BP.Builder.new(mats)
	var lbody := Geo.static_body()
	_sbox(lbd, lbody, "metal", Vector3(44.6, 0.7, -112.0), Vector3(1.6, 1.4, 2.4))
	_sbox(lbd, lbody, "crate", Vector3(40.0, 0.5, -110.8), Vector3(1.0, 1.0, 1.0), 14.0)
	props.add_child(lbody)
	lbd.build(props)
	Props.fog_volume(self, Vector3(0, 0.6, -136.0), Vector3(46.0, 1.6, 48.0), 0.012, Color(0.7, 0.72, 0.78))
	Props.fog_volume(self, Vector3(-24.0, 0.8, -65.0), Vector3(12.0, 2.0, 44.0), 0.02, Color(0.6, 0.62, 0.66))

## Flutlicht am Ministerium (nur bei Alarm) und rotierende Alarmleuchten.
func _build_alarm_lights() -> void:
	for x: float in [-14.0, 14.0]:
		var p := Vector3(x, 9.0, -161.3)
		add_child(Geo.box_mesh_node(Vector3(0.8, 0.5, 0.5), mats["dark"], p))
		var l := _spot(p + Vector3(0, -0.1, 0.4), Vector3(x * 0.3, 0.0, -128.0), Color(0.95, 0.97, 1.0), 0.0, 45.0, 30.0, 1.2, true)
		l.visible = false
		_floods.append(l)
		var beam := SearchlightScript.beam_mesh(30.0, 0.3, 12.0, 0.03, Color(0.9, 0.95, 1.0))
		beam.visible = false
		l.add_child(beam)
		_flood_beams.append(beam)
	for p: Vector3 in [Vector3(9.2, 2.85, -63.0), Vector3(36.0, 4.9, -117.7), Vector3(-25.0, 6.0, -112.0)]:
		add_child(Geo.box_mesh_node(Vector3(0.2, 0.2, 0.2), mats["red_glow"], p))
		var l := _omni(p + Vector3(0, -0.2, 0.3), Color(1.0, 0.12, 0.06), 0.0, 9.0, 0.8)
		l.visible = false
		_alarm_lamps.append(l)

# ------------------------------------------------------------------ Marker, Wachen, Logik

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(0.0, 0.1, 6.5), "player_spawn")
	ps.name = "PlayerSpawn"
	# Schleich-Direktor, Takedown, HUD
	director = Stealth.new(self)
	add_child(director)
	director.connect("alarm_raised", _on_alarm_raised)
	director.connect("alarm_ended", _on_alarm_ended)
	director.connect("body_reported", _on_body_reported)
	takedown = TakedownScript.new()
	takedown.set("director", director)
	add_child(takedown)
	terminal = TerminalScript.new() as Pickup
	terminal.position = TERMINAL_POS
	terminal.rotation_degrees.y = 90.0
	add_child(terminal)
	terminal.connect("download_started", _on_download_started)
	terminal.connect("download_finished", _on_download_finished)
	hud = HudScript.new() as CanvasLayer
	hud.set("director", director)
	hud.set("takedown", takedown)
	hud.set("terminal", terminal)
	add_child(hud)
	# Suchscheinwerfer auf dem Anbau und Drohne über dem Platz
	var sl := SearchlightScript.new()
	sl.set("director", director)
	sl.set("yaw_a", 40.0)
	sl.set("yaw_b", 150.0)
	sl.set("pitch", -24.0)
	sl.set("sweep_speed", 0.07)
	sl.position = Vector3(26.0, 16.2, -121.0)
	add_child(sl)
	var dr := DroneScript.new()
	dr.set("director", director)
	var path: Array[Vector3] = [Vector3(-14.0, 7.5, -118.0), Vector3(12.0, 7.5, -118.0), Vector3(14.0, 7.0, -152.0), Vector3(-16.0, 7.5, -154.0)]
	dr.set("path", path)
	add_child(dr)
	# Bot-Route
	var route: Array = [
		Vector3(4.6, 0, 4.0), Vector3(4.6, 0, -3.0), Vector3(2.0, 0, -20.0), Vector3(1.0, 0, -40.0), Vector3(0.0, 0, -56.0),
		Vector3(0.0, 0, -60.0), Vector3(0.0, 0, -66.0), Vector3(-1.0, 0, -80.0), Vector3(-1.5, 0, -95.0), Vector3(0.0, 0, -108.0),
		Vector3(8.0, 0, -114.5), Vector3(20.0, 0, -115.0), Vector3(30.0, 0, -115.0), Vector3(36.0, 0, -115.5),
		Vector3(36.0, 0, -117.5), Vector3(36.0, 0, -120.0), Vector3(36.0, 0, -124.0), Vector3(36.0, 0, -127.0),
		Vector3(36.0, 0, -129.2), Vector3(39.0, 0, -130.2), Vector3(39.0, 0, -131.6), Vector3(39.0, 0, -133.5),
		Vector3(41.0, 0, -138.0), Vector3(43.0, 0, -143.0), Vector3(42.0, 0, -146.6), Vector3(42.0, 0, -148.2),
		Vector3(42.5, 0, -149.4), Vector3(42.5, -0.5, -151.0), Vector3(42.5, -2.5, -155.0), Vector3(42.5, -4.9, -159.8),
		Vector3(42.5, -4.9, -162.5), Vector3(41.5, -4.9, -175.0), Vector3(41.5, -4.9, -188.0), Vector3(41.8, -4.9, -198.5),
	]
	for i in route.size():
		var w := Geo.marker(m, (route[i] as Vector3) + Vector3(0, 0.05, 0), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	# Checkpoints und Auslöser
	_trigger("CpStreet", Vector3(0, 3, -70.0), Vector3(24, 6, 1.5), func() -> void: _checkpoint("cp_street"))
	_trigger("CpCourtyard", Vector3(-21, 3, -88.0), Vector3(18, 6, 1.5), func() -> void: _checkpoint("cp_street"))
	_trigger("CpPlaza", Vector3(-1, 3, -112.0), Vector3(50, 6, 1.5), func() -> void: _checkpoint("cp_plaza"))
	_trigger("CpAnnex", Vector3(36, 2, -119.6), Vector3(4, 4, 1.2), func() -> void: _checkpoint("cp_annex"))
	_trigger("DataRoom", Vector3(39.8, 2, -140.0), Vector3(11.0, 4, 15.0), _on_enter_data_room)
	_trigger("CpTunnel", Vector3(42, -3, -164.0), Vector3(8, 4, 1.5), func() -> void: _checkpoint("cp_tunnel"))
	var area := _trigger("LevelEnd", Vector3(42.0, -3.0, -199.0), Vector3(8, 4, 3), _finish, false)
	area.add_to_group("level_end")
	# Hupen-/Hundekulisse fern, Funkrauschen der Wachen
	_loop_3d("amb_siren", Vector3(-80.0, 20.0, -150.0), -22.0, 30.0, 400.0)

func _build_set_piece_geometry() -> void:
	pass

func _build_skyline() -> void:
	var srng := RandomNumberGenerator.new()
	srng.seed = build_seed + 400
	var bb := Geo.batch()
	var wb := Geo.batch()
	for i in 34:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * srng.randf_range(40.0, 120.0)
		var z := srng.randf_range(40.0, -320.0)
		if x > 0.0 and z < -100.0 and z > -230.0:
			x += 20.0
		var h := srng.randf_range(18.0, 46.0)
		var s := Vector3(srng.randf_range(14.0, 26.0), h, srng.randf_range(14.0, 26.0))
		bb.add(Vector3(x, h / 2.0, z), s)
		for k in srng.randi_range(2, 7):
			wb.add(Vector3(x - side * s.x / 2.0 - side * 0.05, srng.randf_range(6.0, h - 3.0), z + srng.randf_range(-s.z / 2.5, s.z / 2.5)), Vector3(0.1, 1.2, 1.4))
	add_child(Geo.mesh_node(bb.build(), Geo.mat("concrete_wall_008", Color(0.2, 0.2, 0.21), 0.08, 1.0)))
	add_child(Geo.mesh_node(wb.build(), BP.unshaded(Color(1.4, 0.95, 0.55)), Vector3.ZERO, false))
	# Fernsehturm am Horizont mit roten Warnlichtern
	var tp := Vector3(-150.0, 0.0, -420.0)
	var tm := Geo.flat(Color(0.12, 0.12, 0.13), 0.6, 0.2)
	add_child(Geo.cylinder_node(4.5, 200.0, tm, tp + Vector3(0, 100.0, 0), Vector3.ZERO, 16))
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 16.0
	sm.height = 32.0
	ball.mesh = sm
	ball.material_override = tm
	ball.position = tp + Vector3(0, 205.0, 0)
	add_child(ball)
	add_child(Geo.cylinder_node(1.2, 60.0, tm, tp + Vector3(0, 250.0, 0), Vector3.ZERO, 8))
	for y: float in [140.0, 212.0, 279.0]:
		var rl := MeshInstance3D.new()
		var rs := SphereMesh.new()
		rs.radius = 1.4
		rs.height = 2.8
		rl.mesh = rs
		rl.material_override = mats["red_glow"]
		rl.position = tp + Vector3(0, y, 0)
		rl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(rl)
		_tower_lights.append(rl)
	# Suchscheinwerfer-Kegel am Himmel (nur Optik)
	for p: Vector3 in [Vector3(90.0, 0.0, -260.0), Vector3(-110.0, 0.0, -200.0), Vector3(60.0, 0.0, 40.0)]:
		var root := Node3D.new()
		root.position = p
		add_child(root)
		var beam := SearchlightScript.beam_mesh(260.0, 1.0, 26.0, 0.025, Color(0.75, 0.8, 1.0))
		root.add_child(beam)
		root.rotation_degrees = Vector3(62.0, srng.randf() * 360.0, 0.0)
		_sky_beams.append(root)

func _build_atmosphere() -> void:
	pass

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
	nm.filter_baking_aabb = AABB(Vector3(-32.0, -7.0, -214.0), Vector3(80.0, 13.0, 226.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

## Wachen mit Schleich-KI (statt Marker-Wellen).
func _spawn_wave(index: int) -> void:
	if _waves_spawned.has(index) or not spawn_enemies or index != 0:
		return
	_waves_spawned[index] = true
	wave_started.emit(index)
	var guards: Array = [
		# Straße vor dem Kontrollpunkt
		["rifleman", true, [_wp(-8.5, -14.0, 3.0, 180.0), _wp(-8.5, -31.0, 1.5, 0.0), _wp(5.0, -33.0, 3.0, 0.0), _wp(5.0, -18.0, 2.0, 180.0)]],
		# Kontrollpunkt: Offizier am Häuschen, Posten an der Schranke
		["officer", false, [_wp(6.2, -64.2, 0.0, 180.0)]],
		["rifleman", false, [_wp(-2.0, -60.2, 3.0, 180.0), _wp(2.6, -60.4, 3.0, 160.0)]],
		# Hinterhof
		["rifleman", true, [_wp(-23.0, -50.0, 4.0, 180.0), _wp(-27.0, -66.0, 2.5, 90.0), _wp(-23.5, -80.0, 4.0, 0.0)]],
		# Straße nach dem Kontrollpunkt
		["rifleman", true, [_wp(-4.5, -92.0, 3.0, 0.0), _wp(4.5, -101.0, 3.0, 180.0)]],
		# Platz
		["rifleman", true, [_wp(-10.0, -125.0, 2.0, 90.0), _wp(10.0, -125.0, 2.0, -90.0), _wp(10.0, -146.0, 2.0, -90.0), _wp(-10.0, -146.0, 2.0, 90.0)]],
		["assault", true, [_wp(-19.5, -117.0, 3.0, 180.0), _wp(-19.5, -155.0, 3.0, 0.0)]],
		["rifleman", false, [_wp(22.4, -137.6, 0.0, 90.0)]],
		["rifleman", false, [_wp(22.4, -142.4, 0.0, 90.0)]],
		# Lieferzufahrt
		["rifleman", true, [_wp(26.5, -115.2, 5.0, 90.0), _wp(42.5, -115.2, 3.5, 180.0)]],
		# Anbau: Ladehalle, Flur, Funker
		["rifleman", true, [_wp(32.0, -122.5, 3.0, 180.0), _wp(41.5, -124.5, 3.0, 0.0)]],
		["rifleman", true, [_wp(26.5, -130.0, 3.0, -90.0), _wp(44.2, -130.0, 3.0, 90.0)]],
		["officer", false, [_wp(35.9, -137.5, 0.0, 90.0)]],
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
	var pl := _player()
	if pl == null or not _ready_done:
		return
	var alarm: bool = director.get("alarm")
	terminal.set("locked", alarm and not _bot)
	if alarm and not _wiping and not _bot and _in_annex(pl.global_position) and not bool(terminal.get("done")):
		_wipe()
	if _reinf_t >= 0.0:
		_reinf_t -= delta
		if _reinf_t < 0.0:
			_call_reinforcements()
	if _bot and takedown != null and takedown.get("candidate") != null:
		takedown.call("try_auto")

func _process(delta: float) -> void:
	for i in _sky_beams.size():
		_sky_beams[i].rotation.y += delta * (0.05 + 0.03 * i)
		_sky_beams[i].rotation_degrees.x = 62.0 + sin(_t * 0.2 + i) * 10.0
	var on := fmod(_t, 1.6) < 0.8
	for rl in _tower_lights:
		rl.visible = on
	if director != null and bool(director.get("alarm")):
		for l in _alarm_lamps:
			l.light_energy = 2.5 + 2.0 * sin(_t * 9.0)

func _in_annex(p: Vector3) -> bool:
	return p.x > ANNEX_MIN.x and p.x < ANNEX_MAX.x and p.z > ANNEX_MIN.y and p.z < ANNEX_MAX.y and p.y > -0.6

func _on_alarm_raised(reason: String, pos: Vector3, first: bool) -> void:
	if not first:
		return
	_set_alarm_fx(true)
	if _reinf_waves < 2:
		_reinf_t = 8.0
	match reason:
		"body":
			_say(StoryData.ORDNUNG, "Mann am Boden! Alle Posten: Sperrgebiet absuchen!")
		"drone":
			_say(StoryData.ORDNUNG, "Drohne meldet Kontakt. Eindringling im Sperrgebiet!")
		"searchlight":
			_say(StoryData.ORDNUNG, "Scheinwerfer hat ihn! Alarm, Alarm!")
		"shot":
			_say(StoryData.ORDNUNG, "Schüsse! Alle Einheiten, Alarmstufe Rot!")
		_:
			_say(StoryData.ORDNUNG, "Eindringling gesichtet! Alarm!")
	_later(2.4, func() -> void:
		if bool(director.get("alarm")):
			_say(StoryData.LENA, "Jonas, sie haben dich! Raus aus dem Licht – lauf, versteck dich, warte, bis sie aufgeben."))

func _on_alarm_ended() -> void:
	_set_alarm_fx(false)
	_reinf_t = -1.0
	_say(StoryData.ORDNUNG, "Suche ergebnislos. Alle Posten zurück auf Streife.")
	_later(2.5, func() -> void: _say(StoryData.LENA, "Sie geben auf. Atme durch – und dann weiter."))
	# Verstärkung zieht ab, wenn Kerner sie nicht im Blick hat
	var pl := _player()
	for e in _reinf:
		if is_instance_valid(e) and pl != null and (e as Node3D).global_position.distance_to(pl.global_position) > 22.0:
			e.queue_free()

func _on_body_reported(_pos: Vector3) -> void:
	pass

func _set_alarm_fx(on: bool) -> void:
	for l in _floods:
		l.visible = on
		l.light_energy = 14.0 if on else 0.0
	for b in _flood_beams:
		b.visible = on
	for l in _alarm_lamps:
		l.visible = on
	_close_gate(on)
	if on:
		if _alarm_loops.is_empty():
			var k1 := _loop_3d("curfew_klaxon", Vector3(0.0, 8.0, -150.0), -4.0, 18.0, 160.0)
			var k2 := _loop_3d("curfew_klaxon", Vector3(9.0, 4.0, -63.0), -8.0, 12.0, 90.0)
			var s := _loop_2d("amb_siren", -16.0)
			for n: Node in [k1, k2, s]:
				if n != null:
					_alarm_loops.append(n)
	else:
		for n in _alarm_loops:
			_fade_out(n, 2.5)
		_alarm_loops.clear()

func _close_gate(close: bool) -> void:
	if _gate == null or close == _gate_closed:
		return
	_gate_closed = close
	var target_z := -43.0 if close else -52.0
	var tw := create_tween()
	tw.tween_property(_gate, "position:z", target_z, 2.2).set_trans(Tween.TRANS_SINE)
	var cs := _gate.get_child(_gate.get_child_count() - 1) as CollisionShape3D
	if cs != null:
		cs.set_deferred("disabled", not close)

func _call_reinforcements() -> void:
	if not bool(director.get("alarm")) or _reinf_waves >= 2:
		return
	_reinf_waves += 1
	var pl := _player()
	if pl == null:
		return
	var pts: Array[Vector3] = [Vector3(0.0, 0.1, -20.0), Vector3(-20.0, 0.1, -150.0), Vector3(16.0, 0.1, -112.0), Vector3(-4.0, 0.1, -98.0), Vector3(0.0, 0.1, -48.0), Vector3(36.0, 0.1, -125.0)]
	var best := pts[0]
	var best_score := -1.0e9
	for p in pts:
		var d := p.distance_to(pl.global_position)
		var score := -absf(d - 38.0)
		if d < 22.0:
			score -= 100.0
		if score > best_score:
			best_score = score
			best = p
	var target := pl.global_position
	var types: Array[String] = ["rifleman", "assault", "rifleman"]
	for i in types.size():
		_spawn_reinforcement(types[i], best + Vector3(float(i) - 1.0, 0, float(i % 2)), target)
	_say(StoryData.ORDNUNG, "Verstärkung rückt an. Sektor abriegeln!")

## Alarm im Anbau vor Ende des Downloads: Protokolle gelöscht -> Neustart am Checkpoint.
func _wipe() -> void:
	_wiping = true
	terminal.call("wipe")
	hud.call("show_wipe", "ALARM IM ANBAU\nDie Funkprotokolle wurden gelöscht.")
	_say(StoryData.ORDNUNG, "Eindringling in der Fernmeldestelle! Server löschen – sofort!")
	_later(0.7, _restart_annex)

func _restart_annex() -> void:
	for e in _reinf:
		if is_instance_valid(e):
			e.queue_free()
	_reinf.clear()
	_reinf_t = -1.0
	_reinf_waves = 0
	for b: Dictionary in director.get("bodies"):
		b["found"] = true
	director.call("reset_all")
	_set_alarm_fx(false)
	var pl := _player()
	if pl != null:
		pl.respawn()
	terminal.call("reset")
	_later(2.5, func() -> void:
		_wiping = false
		_say(StoryData.LENA, "Sie haben gelöscht – aber der Nachtlauf spielt die Sicherung zurück. Noch ein Versuch, Jonas. Leiser."))

func _on_player_respawned() -> void:
	if not _wiping:
		for e in _reinf:
			if is_instance_valid(e):
				e.queue_free()
		_reinf.clear()
		_reinf_t = -1.0
		_reinf_waves = 0
		director.call("reset_all")
		_set_alarm_fx(false)
		if not bool(terminal.get("done")):
			terminal.call("reset")
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

func _build_exit_gate() -> void:
	_exit_gate = StaticBody3D.new()
	_exit_gate.name = "Notausgang"
	_exit_gate.position = Vector3(42.5, 0.0, -150.0)
	var gm := mats["metal"] as Material
	for i in 12:
		_exit_gate.add_child(Geo.box_mesh_node(Vector3(0.05, 2.4, 0.05), gm, Vector3(-1.38 + i * 0.25, 1.2, 0)))
	for y: float in [0.15, 1.2, 2.35]:
		_exit_gate.add_child(Geo.box_mesh_node(Vector3(2.9, 0.08, 0.06), gm, Vector3(0, y, 0)))
	_exit_gate.add_child(Geo.box_mesh_node(Vector3(0.18, 0.25, 0.1), mats["warn"], Vector3(0.9, 1.15, 0.06)))
	Geo.add_box_shape(_exit_gate, Vector3(0, 1.2, 0), Vector3(2.9, 2.4, 0.16))
	_exit_gate.set_meta("no_fit", true)
	add_child(_exit_gate)

func _open_exit_gate() -> void:
	if _exit_gate == null:
		return
	var tw := create_tween()
	tw.tween_property(_exit_gate, "position:y", 2.6, 1.6).set_trans(Tween.TRANS_SINE)
	for c in _exit_gate.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)

func _on_enter_data_room() -> void:
	if not _bot:
		return
	terminal.set("duration", 2.5)
	terminal.call("start")

func _on_download_started() -> void:
	_say(StoryData.LENA, "Die Übertragung läuft. Bleib in der Nähe des Terminals, bis sie durch ist.")

func _on_download_finished() -> void:
	_open_exit_gate()
	_checkpoint("cp_logs")
	_obj("Flieh durch den Notausgang in den U-Bahn-Tunnel")
	_say(StoryData.KERNER, "Hab sie. Alles drauf.")
	_later(2.6, func() -> void: _say(StoryData.LENA, "Das Gitter zum Notausgang ist offen – die Zeitschaltung hat es mit der Übertragung entriegelt. Runter in den Schacht, Voss wartet unten."))
	_later(9.0, func() -> void: _say(StoryData.ORDNUNG, "Zentrale an Anbau B: unautorisierter Zugriff auf Fernmeldestelle 4. Streife, nachsehen."))
	_later(10.5, _send_late_patrol)

## Nach dem Download: zwei Wachen kommen durch das Rolltor und sehen nach (kein Alarm).
func _send_late_patrol() -> void:
	if _finished or not spawn_enemies:
		return
	for i in 2:
		var x := 35.4 + i * 1.2
		var e := _spawn_guard("rifleman", true, [_wp(x, -121.0, 1.0, 180.0), _wp(x, -129.5, 2.0, 0.0), _wp(39.0 + i, -138.0, 4.0, 0.0)])
		if e != null:
			e.global_position = Vector3(x, 0.05, -116.5)
			var b := e.get_node_or_null("StealthBrain")
			if b != null:
				b.call("start_search", TERMINAL_POS + Vector3(-1.5, 0, 0))

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_obj("")
	_say(StoryData.VOSS, "Kerner. Konrad Voss. Willkommen im Untergrund – Lena hat nicht übertrieben.")
	_later(3.2, func() -> void: _say(StoryData.VOSS, "Geben Sie mir die Protokolle. Wenn stimmt, was Weber vermutet hat, bricht Riedhammers Lüge heute Nacht zusammen."))
	_later(4.5, _on_level_end)
