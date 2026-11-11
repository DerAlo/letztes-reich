extends "res://game/levels/level.gd"
## Level 5 "Das letzte Reich" (berlin): Regierungsviertel bei Nacht, 01.06.2030, 22:10.
## Abschnitt 1: Siegesfeier auf dem Boulevard (Buehne, EU-Fahnen, Lichterketten, Feuerwerk) – Anschlag mitten in der Rede.
## Abschnitt 2: Putsch der (fiktiven) Ordnungsfront, Kampf den Boulevard hinunter (Wellen 1/2, Hubschrauber).
## Abschnitt 3: Platz vor den Regierungsbauten (Welle 3, Panzer), Vorplatz Sendezentrum (Welle 4).
## Ende: Funkraum – Weber verraet Kerner, Schuss, Schwarzblende, Lena.
## Alle Set-Piece-Explosionen sind reine Optik (kein Combat.explode), damit der Spieler nicht unverschuldet stirbt.

const BP = preload("res://game/levels/berlin_props.gd")
const NightFx = preload("res://game/levels/night_fx.gd")
const Screen = preload("res://game/levels/berlin_screen.gd")
const Fireworks = preload("res://game/levels/berlin_fireworks.gd")
const SD = preload("res://game/story/story_data.gd")

const HELI_PATH := "res://game/vehicles/helicopter.tscn"
const TANK_PATH := "res://game/vehicles/tank.tscn"
const EMBLEM := "res://assets/environment/berlin/emblem.png"
const PA := "Lautsprecher (Gen. von Riedhammer)"
const STAGE_SPEAKER := "Rednerin"
const STAGE := Vector3(0.0, 1.4, -33.5)
const EXPLODE_AFTER := 9.0

## Bot-Route (x, z). Gerade Linien muessen frei begehbar sein.
const ROUTE: Array = [
	Vector2(0, 4), Vector2(4, -6), Vector2(12.5, -20), Vector2(13, -34), Vector2(10, -46), Vector2(4, -58),
	Vector2(2, -72), Vector2(-0.5, -86), Vector2(-3, -100), Vector2(0, -114), Vector2(3, -128), Vector2(2, -142),
	Vector2(-1, -156), Vector2(0, -170), Vector2(2, -184), Vector2(6, -196), Vector2(8, -205), Vector2(10, -215),
	Vector2(8, -228), Vector2(3, -240), Vector2(0, -254), Vector2(0, -268), Vector2(0, -279), Vector2(0, -285),
	Vector2(0, -289)]

const FW_COLORS: Array = [Color(1.0, 0.75, 0.2), Color(0.25, 0.4, 1.0), Color(1.0, 1.0, 1.0), Color(1.0, 0.25, 0.18), Color(0.35, 1.0, 0.45)]

var mats: Dictionary = {}
var fx: Node3D
var fireworks: Node3D
var _screens: Array = []
var _stage_parts: Array[RigidBody3D] = []
var _stage_spots: Array[SpotLight3D] = []
var _strings: Array = []          ## [MultiMeshInstance3D, z]
var _crowd: MultiMeshInstance3D
var _crowd_pos: Array[Vector3] = []
var _crowd_vel: Array[Vector3] = []
var _crowd_t: float = -1.0
var _speech: AudioStreamPlayer3D
var _crowd_snd: AudioStreamPlayer3D
var _loops: Array[Node] = []
var _celebrating: bool = false
var _fw_t: float = 1.0
var _mast_lights: Array[Node3D] = []
var _mast_t: float = 0.0
var _door: StaticBody3D
var _room_light: OmniLight3D
var _alarm_light: OmniLight3D
var _weber: Node3D
var _weber_arm: Node3D
var _weber_muzzle: Node3D
var _room_screen: StaticBody3D
var _black: ColorRect
var _tank: Node3D
var _ending: bool = false
var _screen_line_done: bool = false
var _since_start: float = 0.0
var _started: bool = false

func _init() -> void:
	level_name = "berlin"
	end_z = -296.0
	build_seed = 601
	_wave_count = 5
	default_faction = "reich"
	ambient_artillery = false

func _ready() -> void:
	await super()
	if not is_inside_tree():
		return
	_begin_celebration()

# ------------------------------------------------------------------ Oeffentlich

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Das letzte Reich"
	return info

## Set-Piece: Anschlag auf die Buehne (auch fuer Tests/Touren).
func trigger_setpiece() -> void:
	if _setpiece_done:
		return
	_setpiece_done = true
	setpiece_triggered.emit()
	_explode()

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

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D

func _trauma(v: float) -> void:
	var pl := _player()
	if pl != null and pl.has_method("add_trauma"):
		pl.call("add_trauma", v)

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(0.012, 1.0)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.008, 0.01, 0.028)
	sm.sky_horizon_color = Color(0.11, 0.07, 0.075)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.015)
	sm.ground_horizon_color = Color(0.11, 0.07, 0.075)
	sm.sky_energy_multiplier = 1.0
	sm.sun_angle_max = 2.0
	sm.sun_curve = 0.05
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.24, 0.34)
	env.ambient_light_energy = 0.42
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_exposure = 1.1
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.sdfgi_enabled = true
	env.sdfgi_energy = 0.7
	env.ssil_intensity = 1.2
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.07, 0.08)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.8
	env.fog_aerial_perspective = 0.25
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.011
	env.volumetric_fog_albedo = Color(0.85, 0.82, 0.8)
	env.volumetric_fog_emission = Color(0.008, 0.006, 0.008)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.4
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_gi_inject = 0.5
	env.volumetric_fog_ambient_inject = 0.12
	env.volumetric_fog_sky_affect = 0.7
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.9
	env.glow_intensity = 0.95
	env.glow_bloom = 0.06
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.08
	env.adjustment_color_correction = null
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.62, 1.0)
	moon.light_energy = 0.14
	moon.light_indirect_energy = 0.5
	moon.light_volumetric_fog_energy = 0.5
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
	mats["neon_pink"] = BP.unshaded(Color(3.2, 0.35, 1.7))
	mats["neon_cyan"] = BP.unshaded(Color(0.3, 2.4, 3.4))
	mats["neon_amber"] = BP.unshaded(Color(3.4, 1.7, 0.35))
	mats["line"] = Geo.flat(Color(0.75, 0.75, 0.7), 0.6)
	var g := Geo.static_body(Vector3(0, -1.0, -140.0))
	Geo.add_box_shape(g, Vector3.ZERO, Vector3(80.0, 2.0, 360.0))
	world.add_child(g)
	var far := Geo.box_mesh_node(Vector3(900.0, 0.2, 900.0), Geo.flat(Color(0.03, 0.03, 0.035), 0.9), Vector3(0, -0.16, -200.0))
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
	var bd := BP.Builder.new(mats)
	# Boulevard (Asphalt), Gehwege (Granit), Bordsteine
	bd.box("asphalt", Vector3(0, -0.1, -73.0), Vector3(22.0, 0.2, 206.0))
	for sx: float in [-1.0, 1.0]:
		bd.box("granite", Vector3(sx * 15.0, -0.08, -73.0), Vector3(8.0, 0.2, 206.0))
		bd.box("trim", Vector3(sx * 11.0, 0.03, -73.0), Vector3(0.3, 0.1, 206.0))
	# Mittellinie, Zebrastreifen vor der Feier
	for i in 28:
		bd.box("line", Vector3(0, 0.005, 10.0 - i * 6.5), Vector3(0.18, 0.02, 3.0))
	for i in 9:
		bd.box("line", Vector3(-8.0 + i * 2.0, 0.006, -6.5), Vector3(0.9, 0.02, 3.2))
	# Platz und Vorplatz (Granit), Ring um den Brunnen
	bd.box("granite", Vector3(0, -0.08, -230.0), Vector3(68.0, 0.2, 108.0))
	for i in 9:
		bd.box("trim", Vector3(0, 0.004, -184.0 - i * 11.0), Vector3(66.0, 0.02, 0.25))
	bd.build(world)
	# Aussengrenzen
	for sx: float in [-1.0, 1.0]:
		_invisible_wall(Vector3(sx * 35.5, 7.0, -140.0), Vector3(1.0, 14.0, 340.0))
	_invisible_wall(Vector3(0, 7.0, 12.5), Vector3(80.0, 14.0, 1.0))
	_invisible_wall(Vector3(0, 7.0, -312.0), Vector3(80.0, 14.0, 1.0))

# ------------------------------------------------------------------ Gebaeude

func _build_street() -> void:
	var bd := BP.Builder.new(mats)
	bd.no_shadow.append_array(["neon_pink", "neon_cyan", "neon_amber"])
	var body := Geo.static_body()
	var brng := RandomNumberGenerator.new()
	brng.seed = build_seed + 7
	var left: Array = [[30.0, -22.0, 24.0, "sandstone"], [-26.0, -58.0, 21.0, "facade"], [-62.0, -98.0, 25.0, "sandstone"], [-102.0, -136.0, 22.0, "facade"], [-140.0, -172.0, 26.0, "sandstone"]]
	var right: Array = [[30.0, -30.0, 22.0, "facade"], [-34.0, -66.0, 25.0, "sandstone"], [-70.0, -104.0, 21.0, "facade"], [-108.0, -140.0, 24.0, "sandstone"], [-144.0, -172.0, 22.0, "facade"]]
	for side_i in 2:
		var side := -1 if side_i == 0 else 1
		var rows: Array = left if side == -1 else right
		var fx_ := 19.0 * float(side)
		var prev_z1 := 99.0
		for r: Array in rows:
			BP.block(bd, body, side, fx_, r[0], r[1], 22.0, r[2], r[3], brng, {"lit": 0.3, "shop": 0.55})
			# Neon-Leiste ueber den Schaufenstern
			var nk: String = ["neon_pink", "neon_cyan", "neon_amber"][brng.randi() % 3]
			bd.box(nk, Vector3(fx_ - float(side) * 0.22, 4.25, (r[0] + r[1]) / 2.0), Vector3(0.06, 0.07, absf(r[0] - r[1]) - 2.0))
			# Seitengasse: zurueckgesetzte Rueckwand
			if prev_z1 < 99.0:
				var gz := (prev_z1 + float(r[0])) / 2.0
				var gl := absf(prev_z1 - float(r[0]))
				bd.box("facade", Vector3(float(side) * 33.0, 7.0, gz), Vector3(16.0, 14.0, gl))
				Geo.add_box_shape(body, Vector3(float(side) * 33.0, 7.0, gz), Vector3(16.0, 14.0, gl))
				var lamp_pos := Vector3(float(side) * 24.8, 3.6, gz)
				var gl_light := OmniLight3D.new()
				gl_light.light_color = Color(1.0, 0.6, 0.3)
				gl_light.light_energy = 1.4
				gl_light.omni_range = 7.0
				gl_light.position = lamp_pos
				add_child(gl_light)
			prev_z1 = r[1]
	# Platz: links Regierungsbau mit Kolonnade, rechts Ministerium
	BP.block(bd, body, -1, -34.0, -170.0, -282.0, 22.0, 24.0, "sandstone", brng, {"lit": 0.4, "shop": 0.0})
	BP.colonnade(bd, body, -1, -34.0, -188.0, -256.0, 11.0)
	BP.block(bd, body, 1, 34.0, -170.0, -282.0, 22.0, 22.0, "facade", brng, {"lit": 0.25, "shop": 0.2})
	# Freitreppe vor der Kolonnade (flach, begehbar ist sie nicht noetig)
	bd.box("granite", Vector3(-28.4, 0.15, -222.0), Vector3(2.2, 0.3, 70.0))
	_build_broadcast(bd, body)
	world.add_child(body)
	bd.build(world)
	_build_neon_signs()

func _build_broadcast(bd: BP.Builder, body: StaticBody3D) -> void:
	# Fluegel aussen (niedriger), Kern innen (hoch), Funkraum x -7..7, z -282.6..-298, y 0..4.2
	var vols: Array = [
		[Vector3(-28.0, 9.0, -294.0), Vector3(12.0, 18.0, 24.0), "facade"],
		[Vector3(28.0, 9.0, -294.0), Vector3(12.0, 18.0, 24.0), "facade"],
		[Vector3(-14.5, 15.0, -294.0), Vector3(15.0, 30.0, 24.0), "facade"],
		[Vector3(14.5, 15.0, -294.0), Vector3(15.0, 30.0, 24.0), "facade"],
		[Vector3(0, 15.0, -302.0), Vector3(14.0, 30.0, 8.0), "facade"],
		[Vector3(0, 17.1, -290.3), Vector3(14.0, 25.8, 15.4), "facade"],
		[Vector3(-4.75, 2.1, -282.3), Vector3(4.5, 4.2, 0.6), "facade"],
		[Vector3(4.75, 2.1, -282.3), Vector3(4.5, 4.2, 0.6), "facade"],
		[Vector3(0, 3.7, -282.3), Vector3(5.0, 1.0, 0.6), "facade"],
	]
	for v: Array in vols:
		bd.box(v[2], v[0], v[1])
		Geo.add_box_shape(body, v[0], v[1])
	# Fassade: Glasbaender, Gesimse, Vordach ueber der Tuer
	for i in 7:
		var x := -19.5 + i * 6.5
		if absf(x) < 3.0:
			continue
		bd.box("win_cool" if i % 3 == 0 else "glass", Vector3(x, 15.0, -281.95), Vector3(2.2, 26.0, 0.1))
	for y: float in [4.6, 18.4, 29.6]:
		bd.box("trim", Vector3(0, y, -281.85), Vector3(44.6, 0.4, 0.5))
	bd.box("dark", Vector3(0, 4.35, -280.6), Vector3(9.0, 0.3, 3.4))
	bd.box("win_warm", Vector3(0, 4.18, -280.6), Vector3(7.0, 0.04, 2.6))
	bd.box("granite", Vector3(0, 0.12, -281.0), Vector3(12.0, 0.24, 3.0))
	# Sendemast mit Abspannung
	bd.cyl("steel", Vector3(0, 30.0 + 22.0, -296.0), 0.18, 0.75, 44.0, 10)
	for k in 3:
		var a := TAU * float(k) / 3.0
		var foot := Vector3(sin(a) * 6.0, 30.0, -296.0 + cos(a) * 6.0)
		var top := Vector3(0, 62.0, -296.0)
		var d := top - foot
		bd.box("dark", (foot + top) / 2.0, Vector3(0.05, 0.05, d.length()), Basis.looking_at(d.normalized(), Vector3.UP))
	for y: float in [44.0, 60.0, 74.5]:
		var ml := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.35
		sm.height = 0.7
		ml.mesh = sm
		ml.material_override = mats["red_light"]
		ml.position = Vector3(0, y, -296.0)
		ml.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ml)
		_mast_lights.append(ml)
	# Schriftzug
	var sign := Label3D.new()
	sign.text = "SENDEZENTRUM"
	sign.font_size = 160
	sign.pixel_size = 0.02
	sign.modulate = Color(2.2, 2.3, 2.6)
	sign.shaded = false
	sign.outline_size = 0
	sign.position = Vector3(0, 21.0, -281.5)
	add_child(sign)
	# Fassaden-Anstrahler
	for sx: float in [-1.0, 1.0]:
		var sp := SpotLight3D.new()
		sp.light_color = Color(0.75, 0.82, 1.0)
		sp.light_energy = 9.0
		sp.spot_range = 34.0
		sp.spot_angle = 28.0
		sp.light_volumetric_fog_energy = 0.6
		sp.position = Vector3(sx * 12.0, 0.4, -278.0)
		sp.rotation_degrees = Vector3(78.0, 0, 0)
		add_child(sp)
	_build_radio_room(bd, body)

func _build_radio_room(bd: BP.Builder, body: StaticBody3D) -> void:
	# Innenausstattung (keine Kollision am Pult-Rand noetig, ausser Rueckwandpulte)
	bd.box("dark", Vector3(0, 0.45, -297.2), Vector3(12.0, 0.9, 1.4))
	Geo.add_box_shape(body, Vector3(0, 0.45, -297.2), Vector3(12.0, 0.9, 1.4))
	for i in 5:
		var x := -4.8 + i * 2.4
		bd.box("win_cool", Vector3(x, 1.35, -297.5), Vector3(1.6, 0.9, 0.06), Basis(Vector3.RIGHT, deg_to_rad(-12.0)))
		bd.box("dark", Vector3(x, 1.35, -297.56), Vector3(1.7, 1.0, 0.04), Basis(Vector3.RIGHT, deg_to_rad(-12.0)))
	for sx: float in [-1.0, 1.0]:
		for i in 4:
			var z := -285.0 - i * 3.0
			bd.box("dark", Vector3(sx * 6.4, 1.1, z), Vector3(1.0, 2.2, 2.0))
			Geo.add_box_shape(body, Vector3(sx * 6.4, 1.1, z), Vector3(1.0, 2.2, 2.0))
			for k in 6:
				bd.box("red_light" if (i + k) % 3 == 0 else "win_cool", Vector3(sx * 5.88, 0.6 + k * 0.28, z - 0.6 + (k % 3) * 0.5), Vector3(0.03, 0.04, 0.12))
	bd.box("trim", Vector3(0, 4.15, -290.3), Vector3(14.0, 0.1, 15.4))
	for z: float in [-285.5, -290.0, -294.5]:
		bd.box("win_cool", Vector3(0, 4.08, z), Vector3(5.0, 0.04, 0.3))
	_room_light = OmniLight3D.new()
	_room_light.light_color = Color(0.5, 0.72, 1.0)
	_room_light.light_energy = 1.6
	_room_light.omni_range = 11.0
	_room_light.position = Vector3(0, 3.5, -290.0)
	add_child(_room_light)
	_alarm_light = OmniLight3D.new()
	_alarm_light.light_color = Color(1.0, 0.45, 0.1)
	_alarm_light.light_energy = 0.0
	_alarm_light.omni_range = 12.0
	_alarm_light.shadow_enabled = true
	_alarm_light.position = Vector3(0, 3.6, -293.0)
	add_child(_alarm_light)
	# Tuer (gleitet beim Finale zu); liegt verborgen in der Wand rechts
	_door = Geo.static_body(Vector3(5.0, 1.6, -282.3))
	_door.add_child(Geo.box_mesh_node(Vector3(5.0, 3.2, 0.2), mats["steel"], Vector3.ZERO))
	Geo.add_box_shape(_door, Vector3.ZERO, Vector3(5.0, 3.2, 0.2))
	add_child(_door)
	# Wand-Bildschirm der Ordnungsfront (geht beim Finale an)
	_room_screen = Screen.new()
	_room_screen.set("size", Vector2(4.2, 2.3))
	_room_screen.set("light_energy", 2.0)
	_room_screen.position = Vector3(0, 2.75, -297.75)
	add_child(_room_screen)
	_weber = _build_weber()
	_weber.position = Vector3(0, 0, -295.2)
	add_child(_weber)

## Weber in Uniform (Amber-Armbinde, Brille), schaut zur Tuer (+z); Pistole in der rechten Hand.
func _build_weber() -> Node3D:
	var fig: Dictionary = preload("res://game/characters/vip_models.gd").make("weber_uniform")
	var root: Node3D = fig["root"]
	root.rotation.y = PI
	_weber_arm = (fig["arms"] as Array)[1]
	var gun := Geo.flat(Color(0.05, 0.05, 0.05), 0.4, 0.6)
	# Pistole im Griffpunkt der rechten Hand (Hand-Node folgt Armpose und Modell)
	var hand := (fig["hands"] as Array)[1] as Node3D
	# Hand-lokal: -y = Armrichtung (Lauf zeigt bei gehobenem Arm nach vorn), +z = unten, -z = oben
	hand.add_child(Geo.box_mesh_node(Vector3(0.028, 0.04, 0.11), gun, Vector3(0, 0.005, 0.03), Vector3(-15, 0, 0)))
	hand.add_child(Geo.box_mesh_node(Vector3(0.03, 0.17, 0.036), gun, Vector3(0, -0.045, -0.035)))
	# Muendung: vorderes Ende des Verschlusses
	_weber_muzzle = Node3D.new()
	_weber_muzzle.name = "Muzzle"
	hand.add_child(_weber_muzzle)
	_weber_muzzle.position = Vector3(0, -0.135, -0.035)
	return root

func _build_neon_signs() -> void:
	var signs: Array = [
		["CAFÉ", Vector3(-18.6, 5.6, -8.0), 90.0, Color(1.0, 0.35, 0.6)],
		["HOTEL", Vector3(-18.6, 9.5, -80.0), 90.0, Color(0.35, 0.8, 1.0)],
		["KINO", Vector3(18.6, 5.8, -52.0), -90.0, Color(1.0, 0.25, 0.25)],
		["APOTHEKE", Vector3(18.6, 5.6, -120.0), -90.0, Color(0.3, 1.0, 0.45)],
		["BAR 24", Vector3(-18.6, 5.6, -150.0), 90.0, Color(1.0, 0.6, 0.2)],
		["KIOSK", Vector3(18.6, 5.6, 2.0), -90.0, Color(0.6, 0.45, 1.0)],
	]
	for s: Array in signs:
		_neon(s[0], s[1], s[2], s[3])

func _neon(text: String, pos: Vector3, yaw: float, c: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.014
	l.outline_size = 14
	l.outline_modulate = Color(c.r, c.g, c.b, 0.3)
	l.modulate = Color(c.r * 2.8, c.g * 2.8, c.b * 2.8)
	l.shaded = false
	l.double_sided = false
	l.position = pos
	l.rotation_degrees.y = yaw
	add_child(l)
	var o := OmniLight3D.new()
	o.light_color = c
	o.light_energy = 1.6
	o.omni_range = 8.0
	o.position = pos + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 1.2)
	add_child(o)

# ------------------------------------------------------------------ Requisiten

func _build_props() -> void:
	var props := Node3D.new()
	props.name = "Props"
	world.add_child(props)
	var bd := BP.Builder.new(mats)
	_build_stage(bd)
	_build_crowd()
	# Absperrgitter an der Buehne (mit Kollision)
	_fence(bd, Vector3(-10.0, 0, -12.0), Vector3(-10.0, 0, -42.0))
	_fence(bd, Vector3(10.8, 0, -24.0), Vector3(10.8, 0, -42.0))
	# Strassenlaternen + Lichterketten
	var palette: Array = [Color(1.0, 0.8, 0.5), Color(1.0, 0.55, 0.2), Color(0.3, 0.45, 1.0), Color(1.0, 0.3, 0.25), Color(1.0, 0.85, 0.3)]
	var z := 6.0
	while z > -168.0:
		Props.lamp(world, Vector3(-16.0, 0, z), 90.0, true, 0.0, true)
		Props.lamp(world, Vector3(16.0, 0, z), -90.0, true, 0.0, true)
		z -= 20.0
	z = 8.0
	var flip := 1.0
	while z > -158.0:
		var mmi := BP.string_lights(self, Vector3(-16.0 * flip, 6.4, z), Vector3(16.0 * flip, 6.4, z - 10.0), 1.4, 0.5, palette, rng)
		_strings.append([mmi, z - 5.0])
		flip = -flip
		z -= 13.0
	# Buehnen-Fahnen und Fahnenallee
	for sx: float in [-1.0, 1.0]:
		BP.flag(world, Vector3(sx * 9.0, 0, -40.5), 0.0, 11.0, Vector2(3.6, 2.4), rng)
	var fz := -50.0
	while fz > -165.0:
		BP.flag(world, Vector3(-11.5, 0, fz), 0.0, 8.0, Vector2(2.4, 1.6), rng)
		BP.flag(world, Vector3(11.5, 0, fz - 6.0), 0.0, 8.0, Vector2(2.4, 1.6), rng)
		fz -= 24.0
	# Imbissbuden (links), eine rechts weiter hinten
	for p: Vector3 in [Vector3(-14.5, 0, -50.0), Vector3(-14.5, 0, -66.0), Vector3(-14.5, 0, -118.0), Vector3(15.0, 0, -96.0)]:
		_stand(bd, p)
	# Deckung / Strassensperren (nach dem Putsch aufgebaut)
	Props.vehicle(world, Vector3(-8.0, 0, -52.0), 80.0, "bus", Color(0.85, 0.75, 0.15), false, false, covers)
	Props.vehicle(world, Vector3(12.0, 0, -64.0), 15.0, "car", Color(0.2, 0.22, 0.3), false, false, covers)
	for x: float in [-6.4, -8.8, -11.2, 6.4, 8.8, 11.2]:
		Props.jersey(world, Vector3(x, 0, -78.0), 90.0, covers)
	Props.sandbags(world, Vector3(8.0, 0, -84.0), 90.0, 4.0, rng, covers)
	Props.sandbags(world, Vector3(-9.0, 0, -83.0), 90.0, 4.0, rng, covers)
	Props.vehicle(world, Vector3(-9.5, 0, -104.0), 10.0, "truck", Color(0.18, 0.2, 0.18), false, false, covers)
	Props.vehicle(world, Vector3(9.0, 0, -110.0), -20.0, "car", Color(0.4, 0.1, 0.08), true, false, covers)
	Props.rubble(world, Vector3(12.0, 0, -125.0), 2.6, 1.0, rng, true, covers)
	Props.sandbags(world, Vector3(-7.0, 0, -133.0), 90.0, 4.0, rng, covers)
	Props.jersey(world, Vector3(7.0, 0, -140.0), 90.0, covers)
	Props.vehicle(world, Vector3(-11.0, 0, -150.0), 5.0, "van", Color(0.75, 0.75, 0.78), false, false, covers)
	Props.vehicle(world, Vector3(9.0, 0, -158.0), 160.0, "car", Color(0.1, 0.1, 0.12), false, false, covers)
	Props.hedgehog(world, Vector3(-5.5, 0, -165.0), 20.0, covers)
	Props.hedgehog(world, Vector3(6.0, 0, -168.0), 60.0, covers)
	# Absperrung hinter dem Spieler
	for x: float in [-9.0, -6.6, -4.2, -1.8, 0.6, 3.0, 5.4, 7.8]:
		Props.jersey(world, Vector3(x, 0, 11.0), 90.0, [])
	# Platz
	Props.vehicle(world, Vector3(-18.0, 0, -190.0), 30.0, "truck", Color(0.15, 0.16, 0.14), true, false, covers)
	Props.sandbags(world, Vector3(14.0, 0, -235.0), 0.0, 5.0, rng, covers)
	Props.sandbags(world, Vector3(-2.0, 0, -232.0), 90.0, 3.0, rng, covers)
	Props.sandbags(world, Vector3(16.0, 0, -200.0), 90.0, 4.0, rng, covers)
	Props.rubble(world, Vector3(-14.0, 0, -246.0), 2.2, 0.9, rng, true, covers)
	for x: float in [-14.0, -11.6, 11.6, 14.0]:
		Props.jersey(world, Vector3(x, 0, -262.0), 90.0, covers)
	Props.sandbags(world, Vector3(-6.0, 0, -270.0), 90.0, 3.0, rng, covers)
	Props.sandbags(world, Vector3(7.0, 0, -271.0), 90.0, 3.0, rng, covers)
	var pz := -186.0
	while pz > -262.0:
		Props.lamp(world, Vector3(-25.5, 0, pz), 90.0, true, 0.0, true)
		Props.lamp(world, Vector3(25.5, 0, pz - 8.0), -90.0, true, 0.0, true)
		pz -= 22.0
	for i in 6:
		BP.flag(world, Vector3(-27.5, 0, -194.0 - i * 11.0), 90.0, 9.0, Vector2(2.6, 1.7), rng)
	_fountain(bd, Vector3(-6.0, 0, -214.0))
	_banners()
	bd.build(world)
	# Bodendetail, Wandobjekte, Ampeln (nur Optik, ohne Kollision)
	StreetKit.dress_street(self, {"road": 11.0, "wall": 19.0, "y_walk": 0.02, "z0": 10.0, "z1": -168.0, "style": "city", "seed": build_seed + 501,
		"avoid": [Vector2(-19, -24), Vector2(-19, -60), Vector2(-19, -100), Vector2(-19, -138), Vector2(19, -32), Vector2(19, -68), Vector2(19, -106), Vector2(19, -142)]})
	StreetKit.traffic_light(self, Vector3(-11.6, 0.02, -3.0), 90.0, "red")
	StreetKit.traffic_light(self, Vector3(11.6, 0.02, -10.0), -90.0, "red")
	_build_screens()

func _fence(bd: BP.Builder, a: Vector3, b: Vector3) -> void:
	var body := Geo.static_body()
	var d := b - a
	var basis := Basis.looking_at(d.normalized(), Vector3.UP)
	var mid := (a + b) / 2.0
	bd.box("steel", mid + Vector3(0, 1.05, 0), Vector3(0.05, 0.05, d.length()), basis)
	bd.box("steel", mid + Vector3(0, 0.2, 0), Vector3(0.05, 0.05, d.length()), basis)
	var n := int(d.length() / 0.25)
	for i in n:
		var p := a.lerp(b, (float(i) + 0.5) / float(n))
		bd.box("steel", p + Vector3(0, 0.62, 0), Vector3(0.02, 0.85, 0.02))
	for i in int(d.length() / 2.4) + 1:
		var p := a.lerp(b, minf(float(i) * 2.4 / d.length(), 1.0))
		bd.box("dark", p + Vector3(0, 0.03, 0), Vector3(0.7, 0.06, 0.15), basis)
	Geo.add_box_shape(body, mid + Vector3(0, 0.55, 0), Vector3(0.12, 1.1, d.length()), Vector3(0, rad_to_deg(basis.get_euler().y), 0))
	world.add_child(body)

func _stand(bd: BP.Builder, p: Vector3) -> void:
	var body := Geo.static_body(p)
	var side := -1.0 if p.x < 0.0 else 1.0
	bd.box("wood", p + Vector3(0, 1.1, 0), Vector3(2.4, 2.2, 3.4))
	bd.box("win_warm", p + Vector3(-side * 1.21, 1.6, 0), Vector3(0.04, 0.9, 2.8))
	for i in 6:
		var k := "canvas_red" if i % 2 == 0 else "canvas_white"
		bd.box(k, p + Vector3(-side * 0.6, 2.75, -1.45 + i * 0.58), Vector3(3.0, 0.08, 0.58), Basis(Vector3.BACK, deg_to_rad(side * 12.0)))
	Geo.add_box_shape(body, Vector3(0, 1.1, 0), Vector3(2.4, 2.2, 3.4))
	world.add_child(body)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.4)
	l.light_energy = 1.8
	l.omni_range = 6.0
	l.position = p + Vector3(-side * 2.0, 2.3, 0)
	add_child(l)

func _fountain(bd: BP.Builder, c: Vector3) -> void:
	var body := Geo.static_body(c)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 6.0
	sh.height = 1.6
	cs.shape = sh
	body.add_child(cs)
	world.add_child(body)
	bd.cyl("granite", c + Vector3(0, 0.4, 0), 6.0, 6.1, 0.8, 40)
	bd.cyl("marble", c + Vector3(0, 1.6, 0), 0.55, 0.8, 3.2, 16)
	bd.cyl("marble", c + Vector3(0, 3.3, 0), 1.8, 0.4, 0.4, 20)
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 5.6
	wm.bottom_radius = 5.6
	wm.height = 0.05
	wm.radial_segments = 40
	water.mesh = wm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.02, 0.05, 0.07)
	mat.roughness = 0.03
	mat.metallic = 0.2
	water.material_override = mat
	water.position = c + Vector3(0, 0.72, 0)
	add_child(water)
	var l := OmniLight3D.new()
	l.light_color = Color(0.4, 0.8, 1.0)
	l.light_energy = 2.4
	l.omni_range = 10.0
	l.position = c + Vector3(0, 1.4, 0)
	add_child(l)

## Ordnungsfront-Banner (fiktives Emblem) am Ministerium – nach dem Putsch aufgehaengt.
func _banners() -> void:
	if not ResourceLoader.exists(EMBLEM):
		return
	var em := StandardMaterial3D.new()
	em.albedo_texture = load(EMBLEM)
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	em.emission_enabled = true
	em.emission_texture = em.albedo_texture
	em.emission = Color(1, 1, 1)
	em.emission_energy_multiplier = 0.7
	var black := Geo.flat(Color(0.02, 0.02, 0.025), 0.9)
	for z: float in [-196.0, -246.0]:
		add_child(Geo.box_mesh_node(Vector3(0.08, 11.0, 3.4), black, Vector3(33.85, 12.5, z)))
		var q := QuadMesh.new()
		q.size = Vector2(2.8, 2.8)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = em
		mi.position = Vector3(33.78, 15.0, z)
		mi.rotation_degrees.y = -90.0
		add_child(mi)
		add_child(Geo.box_mesh_node(Vector3(0.1, 0.2, 3.4), mats["neon_amber"], Vector3(33.8, 7.2, z)))

func _build_screens() -> void:
	var defs: Array = [
		[Vector3(-18.6, 10.0, -74.0), 90.0, Vector2(9.0, 5.0)],
		[Vector3(18.6, 9.5, -122.0), -90.0, Vector2(9.0, 5.0)],
		[Vector3(33.6, 13.0, -221.0), -90.0, Vector2(14.0, 7.8)],
		[Vector3(0.0, 11.0, -281.6), 0.0, Vector2(16.0, 8.6)],
	]
	for d: Array in defs:
		var s := Screen.new()
		s.set("size", d[2])
		s.set("light_energy", 4.0 if (d[2] as Vector2).x < 10.0 else 7.0)
		s.position = d[0]
		s.rotation_degrees.y = d[1]
		add_child(s)
		s.connect("destroyed", _on_screen_destroyed)
		_screens.append(s)

func _on_screen_destroyed() -> void:
	if _screen_line_done or _ending:
		return
	_screen_line_done = true
	_say(SD.LENA, "Gut so. Ein Bildschirm weniger, der lügt.")

# ------------------------------------------------------------------ Buehne und Publikum

func _build_stage(bd: BP.Builder) -> void:
	# Podest (bleibt stehen)
	var plat := Geo.static_body()
	bd.box("dark", Vector3(0, 0.7, -33.5), Vector3(16.0, 1.4, 9.0))
	bd.box("wood", Vector3(0, 1.42, -33.5), Vector3(16.2, 0.06, 9.2))
	bd.box("canvas_red", Vector3(0, 0.7, -28.98), Vector3(16.0, 1.3, 0.04))
	Geo.add_box_shape(plat, Vector3(0, 0.7, -33.5), Vector3(16.0, 1.4, 9.0))
	world.add_child(plat)
	# Aufbauten als eingefrorene Truemmerteile (fliegen beim Anschlag weg)
	var steel: Material = mats["steel"]
	var dark: Material = mats["dark"]
	for p: Vector3 in [Vector3(-7.6, 5.6, -29.6), Vector3(7.6, 5.6, -29.6), Vector3(-7.6, 5.6, -37.6), Vector3(7.6, 5.6, -37.6)]:
		_part(p, Vector3(0.4, 8.4, 0.4), steel)
	var front := _part(Vector3(0, 9.9, -29.6), Vector3(15.6, 0.45, 0.45), steel)
	_part(Vector3(0, 9.9, -37.6), Vector3(15.6, 0.45, 0.45), steel)
	for sx: float in [-1.0, 1.0]:
		_part(Vector3(sx * 7.6, 9.9, -33.6), Vector3(0.45, 0.45, 8.0), steel)
		_part(Vector3(sx * 9.6, 2.2, -31.0), Vector3(1.3, 4.4, 1.2), dark)
		_part(Vector3(sx * 9.6, 5.2, -31.0), Vector3(1.1, 1.6, 1.0), dark)
	# Rednerpult
	_part(Vector3(0, 2.0, -30.6), Vector3(0.9, 1.2, 0.6), mats["marble"])
	# LED-Wand: vier Paneele mit Europaflagge
	var tex: Texture2D = load(BP.EU_FLAG) if ResourceLoader.exists(BP.EU_FLAG) else null
	for i in 4:
		var ix := i % 2
		var iy := i / 2
		var rb := _part(Vector3(-1.75 + ix * 3.5, 6.85 - iy * 2.5, -37.3), Vector3(3.5, 2.5, 0.25), dark)
		var q := QuadMesh.new()
		q.size = Vector2(3.4, 2.4)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if tex != null:
			m.albedo_texture = tex
			m.uv1_scale = Vector3(0.5, 0.5, 1.0)
			m.uv1_offset = Vector3(0.5 * ix, 0.5 * iy, 0.0)
		m.albedo_color = Color(1.7, 1.7, 1.7)
		mi.material_override = m
		mi.position = Vector3(0, 0, 0.13)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(mi)
	# Banner
	var ban := Label3D.new()
	ban.text = "FRIEDEN · 1. JUNI 2030"
	ban.font_size = 120
	ban.pixel_size = 0.009
	ban.modulate = Color(2.6, 2.2, 1.2)
	ban.shaded = false
	ban.position = Vector3(0, 0, 0.26)
	front.add_child(ban)
	# Buehnenlicht: farbige Spots am Traversenbalken
	var cols: Array = [Color(0.3, 0.45, 1.0), Color(1.0, 0.75, 0.3), Color(1.0, 0.75, 0.3), Color(0.3, 0.45, 1.0)]
	for i in 4:
		var sp := SpotLight3D.new()
		sp.light_color = cols[i]
		sp.light_energy = 14.0
		sp.spot_range = 26.0
		sp.spot_angle = 16.0
		sp.light_volumetric_fog_energy = 3.0
		sp.position = Vector3(-5.4 + i * 3.6, -0.3, 0)
		sp.rotation_degrees = Vector3(-122.0, (float(i) - 1.5) * 9.0, 0)
		front.add_child(sp)
		_stage_spots.append(sp)
	# Fuss-Licht auf die Buehne
	var wash := OmniLight3D.new()
	wash.light_color = Color(1.0, 0.85, 0.65)
	wash.light_energy = 2.5
	wash.omni_range = 12.0
	wash.position = Vector3(0, 4.0, -27.0)
	add_child(wash)
	_stage_spots.append(null)
	wash.set_meta("stage_wash", true)
	_stage_wash = wash

var _stage_wash: OmniLight3D

func _part(pos: Vector3, size: Vector3, mat: Material) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.freeze = true
	rb.collision_layer = 8
	rb.collision_mask = 1 | 8
	rb.mass = 30.0
	rb.add_child(Geo.box_mesh_node(size, mat, Vector3.ZERO))
	Geo.add_box_shape(rb, Vector3.ZERO, size)
	rb.position = pos
	add_child(rb)
	_stage_parts.append(rb)
	return rb

func _build_crowd() -> void:
	var cm := CapsuleMesh.new()
	cm.radius = 0.23
	cm.height = 1.72
	cm.radial_segments = 8
	cm.rings = 2
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	cm.material = mat
	var cols: Array = [Color(0.08, 0.08, 0.1), Color(0.18, 0.16, 0.14), Color(0.1, 0.14, 0.25), Color(0.3, 0.1, 0.08), Color(0.22, 0.22, 0.24), Color(0.35, 0.3, 0.12)]
	var crng := RandomNumberGenerator.new()
	crng.seed = 77
	var pts: Array[Vector3] = []
	for i in 230:
		pts.append(Vector3(crng.randf_range(-8.6, 7.6), 0, crng.randf_range(-27.2, -12.0)))
	for i in 50:
		pts.append(Vector3(crng.randf_range(-13.0, -11.0), 0, crng.randf_range(-70.0, -44.0)))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cm
	mm.instance_count = pts.size()
	for i in pts.size():
		var s := crng.randf_range(0.92, 1.08)
		var p := pts[i] + Vector3(0, 0.86 * s, 0)
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(1, s, 1)), p))
		mm.set_instance_color(i, cols[crng.randi() % cols.size()])
		_crowd_pos.append(p)
		var away := Vector3(p.x - STAGE.x, 0, p.z - STAGE.z)
		var dir := Vector3(signf(away.x + 0.01) * 1.0, 0, 0.7 + crng.randf() * 0.6).normalized()
		if p.z < -40.0:
			dir = Vector3(-1.0, 0, crng.randf_range(-0.3, 0.6)).normalized()
		_crowd_vel.append(dir * crng.randf_range(5.0, 8.0))
	_crowd = MultiMeshInstance3D.new()
	_crowd.multimesh = mm
	add_child(_crowd)

# ------------------------------------------------------------------ Marker

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(0.0, 0.1, 5.0), "player_spawn")
	ps.name = "PlayerSpawn"
	# [typ, welle, x, y, z]
	var spawns: Array = [
		["rifleman", 1, -6.0, 0.05, -82.0], ["rifleman", 1, 6.0, 0.05, -86.0], ["rifleman", 1, -12.0, 0.05, -88.0],
		["rifleman", 1, 11.0, 0.05, -81.0], ["officer", 1, 0.0, 0.05, -92.0],
		["rifleman", 2, -8.0, 0.05, -136.0], ["rifleman", 2, 7.0, 0.05, -143.0], ["marksman", 2, -11.0, 0.05, -154.0],
		["rifleman", 2, 10.0, 0.05, -160.0], ["heavy", 2, 0.0, 0.05, -150.0], ["drone", 2, 0.0, 6.0, -140.0],
		["rifleman", 3, -12.0, 0.05, -224.0], ["rifleman", 3, 14.0, 0.05, -238.0], ["rifleman", 3, -20.0, 0.05, -238.0],
		["assault", 3, 6.0, 0.05, -244.0], ["heavy", 3, -2.0, 0.05, -236.0], ["drone", 3, -8.0, 7.0, -220.0], ["drone", 3, 10.0, 8.0, -228.0],
		["assault", 4, -6.0, 0.05, -273.0], ["rifleman", 4, 7.0, 0.05, -274.0], ["rifleman", 4, -12.0, 0.05, -268.0],
		["heavy", 4, 10.0, 0.05, -275.0],
		# gepanzerte Soldaten + Juggernaut vor dem Sendezentrum (Finale nach dem Buehnenanschlag)
		["armored", 2, -4.0, 0.05, -158.0], ["armored", 3, 8.0, 0.05, -231.0], ["armored", 4, -14.0, 0.05, -276.0],
		["juggernaut", 4, 0.0, 0.05, -281.0],
	]
	for i in spawns.size():
		var s: Array = spawns[i]
		var mk := Geo.marker(m, Vector3(s[2], s[3], s[4]), "enemy_spawn")
		mk.name = "EnemySpawn%d_%s" % [i, s[0]]
		mk.set_meta("enemy_type", s[0])
		mk.set_meta("wave", s[1])
	for c in covers:
		var v: Vector3 = c
		if absf(v.x) > 33.0 or v.z > 0.0:
			continue
		Geo.marker(m, Vector3(v.x, 0.0, v.z), "cover_point")
	for i in ROUTE.size():
		var r: Vector2 = ROUTE[i]
		var w := Geo.marker(m, Vector3(r.x, 0.05, r.y), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	_trigger("TriggerExplosion", Vector3(0, 3, -14.0), Vector3(40, 6, 1.5), trigger_setpiece)
	_trigger("Checkpoint0", Vector3(0, 3, -46.0), Vector3(40, 6, 1.5), func() -> void: _checkpoint("cp_feier"))
	# Panzerfaust gegen Helikopter (Boulevard) und Panzer (Platz) + Munitionskisten
	Pickup.place_pzf_set(self, Vector3(-5.0, 0.0, -50.0), 90.0)
	Pickup.place_pzf_set(self, Vector3(-6.0, 0.0, -170.0), 90.0)
	_trigger("TriggerWave2",Vector3(0, 3, -96.0), Vector3(40, 6, 1.5), func() -> void: _spawn_wave(2))
	_trigger("Checkpoint1", Vector3(0, 3, -94.0), Vector3(40, 6, 1.5), _on_cp_boulevard)
	_trigger("TriggerHeli", Vector3(0, 3, -100.0), Vector3(40, 6, 1.5), _spawn_heli)
	_trigger("TriggerWave3", Vector3(0, 3, -176.0), Vector3(70, 6, 1.5), _on_wave3)
	_trigger("Checkpoint2", Vector3(0, 3, -174.0), Vector3(70, 6, 1.5), _on_cp_plaza)
	_trigger("TriggerWave4", Vector3(0, 3, -246.0), Vector3(70, 6, 1.5), func() -> void:
		_spawn_wave(4)
		_later(2.5, func() -> void:
			if _boss_alive():
				_say(SD.LENA, "Ein Koloss vor dem Eingang! Kopf oder Tornister, Jonas – nicht auf die Panzerung!", 4.2)))
	_trigger("Checkpoint3", Vector3(0, 3, -250.0), Vector3(70, 6, 1.5), _on_cp_tower)
	var area := _trigger("LevelEnd", Vector3(0, 2.0, -288.5), Vector3(12, 4, 3), _start_ending, true)
	area.add_to_group("level_end")

func _build_set_piece_geometry() -> void:
	pass

# ------------------------------------------------------------------ Kulisse

func _build_skyline() -> void:
	var srng := RandomNumberGenerator.new()
	srng.seed = build_seed + 31
	var bb := Geo.batch()
	var wb := Geo.batch()
	for i in 60:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -srng.randf_range(-40.0, 380.0)
		var x := side * srng.randf_range(62.0, 160.0)
		var w := srng.randf_range(14.0, 30.0)
		var h := srng.randf_range(18.0, 52.0)
		bb.add(Vector3(x, h / 2.0, z), Vector3(w, h, srng.randf_range(12.0, 26.0)))
		for k in srng.randi_range(4, 12):
			wb.add(Vector3(x - side * (w / 2.0 + 0.05), srng.randf_range(4.0, h - 2.0), z + srng.randf_range(-5.0, 5.0)), Vector3(0.1, 1.2, srng.randf_range(1.0, 3.0)))
	for i in 14:
		var x := srng.randf_range(-120.0, 120.0)
		var h := srng.randf_range(26.0, 70.0)
		bb.add(Vector3(x, h / 2.0, -330.0 - srng.randf_range(0.0, 140.0)), Vector3(srng.randf_range(16.0, 30.0), h, 18.0))
	add_child(Geo.mesh_node(bb.build(), Geo.flat(Color(0.05, 0.05, 0.06), 0.9), Vector3.ZERO, false))
	add_child(Geo.mesh_node(wb.build(), mats["win_warm"], Vector3.ZERO, false))
	# Ferner Fernsehturm (generische Silhouette) mit Warnlicht
	var bd := BP.Builder.new(mats)
	var tc := Vector3(-170.0, 0, -520.0)
	bd.cyl("dark", tc + Vector3(0, 100.0, 0), 2.6, 5.0, 200.0, 16)
	bd.ball("dark", tc + Vector3(0, 208.0, 0), Vector3(32.0, 30.0, 32.0))
	bd.cyl("dark", tc + Vector3(0, 250.0, 0), 0.6, 1.2, 60.0, 8)
	bd.box("win_warm", tc + Vector3(0, 214.0, 0), Vector3(30.0, 1.0, 30.0))
	bd.build(self)
	var tl := MeshInstance3D.new()
	var tsm := SphereMesh.new()
	tsm.radius = 1.6
	tsm.height = 3.2
	tl.mesh = tsm
	tl.material_override = mats["red_light"]
	tl.position = tc + Vector3(0, 281.0, 0)
	add_child(tl)
	_mast_lights.append(tl)

func _build_atmosphere() -> void:
	fx = NightFx.new()
	fx.name = "NightFx"
	fx.set("end_z", end_z)
	fx.set("snow_enabled", false)
	fx.set("flares_enabled", false)
	fx.set("tracers_enabled", false)
	fx.set("artillery_enabled", false)
	add_child(fx)
	fireworks = Fireworks.new()
	fireworks.name = "Fireworks"
	add_child(fireworks)
	# Lichtshow der Feier: zwei Himmelsstrahler auf den Daechern
	fx.call("add_searchlight", Vector3(-30.0, 25.0, -96.0), 20.0, 62.0, 40.0, 0.25, 30.0)
	fx.call("add_searchlight", Vector3(30.0, 26.0, -88.0), -20.0, 64.0, 40.0, 0.21, 30.0)
	# Brennender Panzerwagen auf dem Platz, Feuertonnen am Vorplatz
	Props.fire(world, Vector3(-18.0, 1.2, -190.0), 1.6, true, 3.0, 6.0)
	for p: Vector3 in [Vector3(-9.0, 0.4, -266.0), Vector3(9.5, 0.4, -267.0)]:
		Props.fire(world, p, 0.7, true, 1.2, 3.0)
	for z: float in [-60.0, -130.0, -210.0, -265.0]:
		Props.fog_volume(self, Vector3(0, 1.5, z), Vector3(40, 5, 40), 0.02, Color(0.6, 0.55, 0.55))

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
	nm.geometry_collision_mask = 1 | 16   # world + move_block (= alles, woran Player/Gegner haengen)
	nm.filter_baking_aabb = AABB(Vector3(-35.0, -1.0, -300.0), Vector3(70.0, 15.0, 314.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

# ------------------------------------------------------------------ Ablauf: Feier

func _begin_celebration() -> void:
	_started = true
	_celebrating = true
	_speech = _loop_3d("berlin_speech", STAGE + Vector3(0, 3, 0), -1.0, 16.0, 170.0)
	_crowd_snd = _loop_3d("berlin_crowd", Vector3(0, 1.5, -20.0), -2.0, 18.0, 160.0)
	_later(0.8, func() -> void: _obj("Halte die Ehrenwache an der Bühne"))
	_later(1.4, func() -> void: _say(SD.WEBER, "Kerner, Aksoy – ruhige Nacht heute. Genießt die Feier, ihr habt sie euch verdient."))
	_later(4.6, func() -> void:
		if not _setpiece_done:
			_say(STAGE_SPEAKER, "…zwei Jahre Krieg. Und heute Nacht sagen wir: Europa hat gehalten!", 3.0))
	_later(7.4, func() -> void:
		if not _setpiece_done:
			_say(SD.LENA, "Sagt der Mann, der uns zur Ehrenwache eingeteilt hat. Ganz vorne. Direkt an der Bühne.", 3.4))

func _process(delta: float) -> void:
	if not _started:
		return
	_since_start += delta
	if _celebrating:
		if _since_start >= EXPLODE_AFTER:
			trigger_setpiece()
		_fw_t -= delta
		if _fw_t <= 0.0:
			_fw_t = rng.randf_range(0.7, 1.5)
			var from := Vector3(rng.randf_range(-7.0, 7.0), 1.5, -44.0)
			var to := Vector3(rng.randf_range(-30.0, 30.0), rng.randf_range(30.0, 52.0), rng.randf_range(-52.0, -95.0))
			fireworks.call("launch", from, to, FW_COLORS[rng.randi() % FW_COLORS.size()], rng.randf_range(1.1, 1.6))
	if _crowd_t >= 0.0:
		_update_crowd(delta)
	_mast_t += delta
	var on := fmod(_mast_t, 1.6) < 0.8
	for ml in _mast_lights:
		ml.visible = on
	if _ending and _alarm_light != null:
		_alarm_light.light_energy = 2.6 + 1.6 * sin(_mast_t * 5.0)

func _update_crowd(delta: float) -> void:
	_crowd_t += delta
	if _crowd_t > 3.6:
		_crowd.visible = false
		_crowd_t = -1.0
		return
	var mm := _crowd.multimesh
	for i in _crowd_pos.size():
		_crowd_pos[i] += _crowd_vel[i] * delta
		var v := _crowd_vel[i]
		var b := Basis.looking_at(-v.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, deg_to_rad(-12.0))
		mm.set_instance_transform(i, Transform3D(b, _crowd_pos[i]))

# ------------------------------------------------------------------ Ablauf: Anschlag

func _explode() -> void:
	_celebrating = false
	Events.story_cinematic.emit(true)
	_later(2.8, func() -> void: Events.story_cinematic.emit(false))
	VFX.play_sfx_3d("berlin_pa_feedback", STAGE + Vector3(0, 3, 0), 2.0, 20.0, 200.0)
	if _speech != null:
		_speech.stop()
	_later(0.35, _blast)

func _blast() -> void:
	get_tree().call_group(&"story_ui", &"interrupt")   # Explosion schneidet Rede und Geplauder ab
	VFX.spawn_explosion(STAGE + Vector3(0, 0.6, -1.0), 3.6)
	VFX.spawn_dust_cloud(STAGE, 8.0)
	_later(0.25, func() -> void: VFX.spawn_explosion(Vector3(-9.6, 2.0, -31.0), 2.0))
	_later(0.5, func() -> void: VFX.spawn_explosion(Vector3(9.6, 2.0, -31.0), 2.2))
	_trauma(0.85)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.7, 0.4)
	l.light_energy = 40.0
	l.omni_range = 60.0
	l.position = STAGE + Vector3(0, 4, 0)
	add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 1.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)
	for rb in _stage_parts:
		if not is_instance_valid(rb):
			continue
		rb.freeze = false
		var away := rb.global_position - (STAGE + Vector3(0, -0.5, 0))
		away.y = absf(away.y) + 2.0
		rb.apply_central_impulse(away.normalized() * rb.mass * rng.randf_range(8.0, 15.0))
		rb.apply_torque_impulse(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * rb.mass * 6.0)
	for sp in _stage_spots:
		if sp != null and is_instance_valid(sp):
			sp.light_energy = 0.0
	if is_instance_valid(_stage_wash):
		_stage_wash.light_energy = 0.0
	# Buehnenbrand
	for fp: Vector3 in [Vector3(-3.0, 1.45, -33.0), Vector3(3.5, 1.45, -35.0), Vector3(0.0, 1.45, -31.0), Vector3(-6.0, 0.2, -27.5), Vector3(7.0, 0.2, -26.0)]:
		Props.fire(world, fp, 1.6 if fp.y > 1.0 else 1.0, true, 2.6, 6.0)
	VFX.spawn_scorch(STAGE + Vector3(0, 0.05, 0), Vector3.UP, 9.0)
	# Stromausfall: Lichterketten nahe der Buehne aus, uebrige gedimmt
	for s: Array in _strings:
		var k := 0.05 if absf(float(s[1]) - STAGE.z) < 32.0 else 0.55
		BP.set_lights_level(s[0], k)
	# Publikum flieht, Geraeusche
	_crowd_t = 0.0
	_fade_out(_crowd_snd, 0.6)
	_fade_out(_speech, 0.1)
	_later(1.4, func() -> void: _loop_2d("amb_siren", -15.0))
	# Fehlgezuendetes Feuerwerk – Feuerwerk wird zu Chaos
	for i in 4:
		_later(0.6 + i * 0.45, func() -> void:
			var from := Vector3(rng.randf_range(-5.0, 5.0), 1.8, -42.0)
			var to := Vector3(rng.randf_range(-16.0, 16.0), rng.randf_range(3.5, 9.0), rng.randf_range(-12.0, -40.0))
			fireworks.call("launch", from, to, FW_COLORS[rng.randi() % FW_COLORS.size()], 0.5))
	_later(1.2, func() -> void: _say(SD.LENA, "Jonas! Die Bühne – runter, runter!", 2.4))
	_later(2.6, func() -> void: _obj("Such Deckung"))
	_later(2.8, func() -> void: _spawn_wave(1))
	_later(4.0, func() -> void: _say(SD.WEBER, "Explosion an der Bühne! Haltet die Stellung, ich kläre die Lage.", 3.2))
	_later(4.5, func() -> void: _loop_2d("amb_battle", -16.0))
	_later(7.0, _start_coup)

func _start_coup() -> void:
	for i in _screens.size():
		var s: Node = _screens[i]
		if is_instance_valid(s):
			s.call("power_on", 0.2 + i * 0.6)
	fx.set("tracers_enabled", true)
	fx.call("add_searchlight", Vector3(-19.0, 26.5, -100.0), -30.0, -18.0, 35.0, 0.3, 45.0)
	fx.call("add_searchlight", Vector3(19.0, 25.5, -140.0), 30.0, -16.0, 35.0, 0.26, 45.0)
	fx.call("add_searchlight", Vector3(10.0, 31.0, -286.0), 180.0, -14.0, 30.0, 0.2, 55.0)
	_say(PA, "Bürger Berlins. Ausländische Kräfte haben unsere Feier angegriffen. Die Ordnungsfront übernimmt ab sofort den Schutz des Landes.", 6.0)
	_later(6.5, func() -> void: _say(SD.LENA, "Das sind unsere Leute – mit Armbinden. Ordnungsfront! Die schießen auf alles, was sich bewegt.", 4.0))
	_later(11.0, func() -> void:
		_say(SD.WEBER, "Das ist ein Putsch. Das Sendezentrum am Ende der Achse – solange sie senden, glaubt ihnen das Land. Schaltet es ab.", 5.0)
		_obj("Kämpf dich zum Sendezentrum durch"))
	_spawn_tank()

# ------------------------------------------------------------------ Ablauf: Kampf

func _on_cp_boulevard() -> void:
	_checkpoint("cp_boulevard")
	_say(PA, "Bleibt in euren Häusern. Wer sich fügt, hat nichts zu befürchten.", 3.6)
	_later(3.8, func() -> void: _say(SD.LENA, "Klingt, als hätten sie die Durchsage schon vor der Feier aufgenommen.", 3.2))

func _spawn_heli() -> void:
	var pts: Array[Vector3] = [Vector3(30.0, 30.0, -118.0), Vector3(0.0, 27.0, -150.0), Vector3(-40.0, 34.0, -195.0), Vector3(-150.0, 60.0, -260.0)]
	var start := Vector3(80.0, 40.0, -70.0)
	_later(1.0, func() -> void: _say(SD.LENA, "Hubschrauber! Unsere Kennung – die haben auch die Flieger auf ihrer Seite.", 3.4))
	if ResourceLoader.exists(HELI_PATH):
		var scene := load(HELI_PATH) as PackedScene
		if scene != null:
			var h := scene.instantiate() as Node3D
			h.set("faction", "eu")
			h.set("searchlight", true)
			h.set("downwash", false)
			add_child(h)
			h.global_position = start
			if h.has_method("set_searchlight"):
				h.call("set_searchlight", true)
			if h.has_method("attack"):
				h.call("attack", false)
			if h.has_method("fly_path"):
				h.call("fly_path", pts, 22.0, false)
			_later(17.0, func() -> void:
				if is_instance_valid(h):
					h.queue_free())
			return
	_fallback_heli(start, pts)

## Ersatz, falls kein Hubschrauber-Asset existiert: Silhouette mit Suchscheinwerfer und Positionslicht.
func _fallback_heli(start: Vector3, pts: Array[Vector3]) -> void:
	var h := Node3D.new()
	var dark := Geo.flat(Color(0.06, 0.065, 0.07), 0.6, 0.3)
	h.add_child(Geo.box_mesh_node(Vector3(2.2, 2.0, 6.0), dark, Vector3.ZERO))
	h.add_child(Geo.box_mesh_node(Vector3(0.5, 0.6, 6.0), dark, Vector3(0, 0.4, 5.5)))
	h.add_child(Geo.box_mesh_node(Vector3(11.0, 0.05, 0.35), dark, Vector3(0, 1.3, 0)))
	var sp := SpotLight3D.new()
	sp.light_energy = 16.0
	sp.spot_range = 80.0
	sp.spot_angle = 9.0
	sp.light_volumetric_fog_energy = 4.0
	sp.rotation_degrees = Vector3(-65, 0, 0)
	sp.position = Vector3(0, -1.0, -2.6)
	h.add_child(sp)
	add_child(h)
	h.global_position = start
	var tw := h.create_tween()
	var prev := start
	for p in pts:
		h.look_at(p)
		tw.tween_property(h, "global_position", p, prev.distance_to(p) / 22.0)
		prev = p
	tw.tween_callback(h.queue_free)
	VFX.play_sfx_3d("amb_battle", start, -6.0, 20.0, 200.0)

func _spawn_tank() -> void:
	if not ResourceLoader.exists(TANK_PATH):
		return
	var scene := load(TANK_PATH) as PackedScene
	if scene == null:
		return
	var t := scene.instantiate() as Node3D
	t.set("faction", "reich")
	t.set("shell_damage", 30.0)
	t.set("miss_min", 6.0)
	t.set("miss_max", 10.0)
	t.set("fire_interval", 8.0)
	add_child(t)
	t.global_position = Vector3(27.0, 0.0, -264.0)
	t.rotation.y = 0.0
	_tank = t

func _on_wave3() -> void:
	_spawn_wave(3)
	if _tank != null and is_instance_valid(_tank):
		var pts: Array[Vector3] = [Vector3(26.5, 0, -240.0), Vector3(25.5, 0, -214.0)]
		_tank.call("drive_path", pts, 2.2)
		_later(6.0, func() -> void:
			if is_instance_valid(_tank) and not _ending:
				_tank.call("set_target", _player()))
		_later(3.0, func() -> void: _say(SD.LENA, "Panzer auf dem Platz! Bleib in Deckung – Kugeln bringen da nichts.", 3.4))

func _on_cp_plaza() -> void:
	_checkpoint("cp_plaza")
	_obj("Überquere den Platz – Sendezentrum am Nordende")
	_say(PA, "Ordnung. Stärke. Das letzte Reich beginnt heute Nacht.", 3.4)
	_later(3.8, func() -> void: _say(SD.LENA, "„Das letzte Reich.“ Gefeiert mit Sprengstoff unter der Bühne.", 3.2))
	_later(8.0, func() -> void: _say(SD.WEBER, "Funkraum im Erdgeschoss des Sendezentrums. Ich bin schon drin – ich warte auf euch.", 4.0))

func _on_cp_tower() -> void:
	_checkpoint("cp_tower")
	_obj("Triff Weber im Funkraum")
	_say(SD.WEBER, "Kommt rein, Kerner. Nur du. Aksoy sichert den Eingang.", 3.4)
	_later(3.8, func() -> void: _say(SD.LENA, "Warum nur du? Und wie ist er vor uns da reingekommen? Jonas – pass auf.", 4.0))
	if _tank != null and is_instance_valid(_tank):
		_tank.call("set_target", null)

# ------------------------------------------------------------------ Ablauf: Finale

## Juggernaut (Welle 4) lebt noch und ist im Kampf?
func _boss_alive() -> bool:
	for b in get_tree().get_nodes_in_group("boss"):
		if is_ancestor_of(b) and b.has_method("is_alive") and bool(b.call("is_alive")):
			return true
	return false

func _start_ending() -> void:
	if _ending:
		return
	if _boss_alive():
		# Eingang erst frei, wenn der Juggernaut liegt
		_later(1.0, _start_ending)
		return
	_ending = true
	Events.story_cinematic.emit(true)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_ancestor_of(e):
			e.queue_free()
	if _tank != null and is_instance_valid(_tank):
		_tank.call("set_target", null)
	var pl := _player()
	if pl != null:
		if "external_input" in pl and not bool(Game.arg("autopilot", false)):
			pl.set("external_input", true)
		if pl.has_method("set_view"):
			pl.call("set_view", 0.0, -4.0)
	var tw := create_tween()
	tw.tween_property(_door, "position:x", 0.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	VFX.play_sfx_3d("story_drone", Vector3(0, 2, -290.0), -4.0, 10.0, 60.0)
	tw.parallel().tween_property(_room_light, "light_energy", 0.35, 1.2)
	if is_instance_valid(_room_screen):
		_room_screen.call("power_on", 0.5)
	for s in _loops:
		if is_instance_valid(s):
			_fade_out(s, 2.0)
	_later(1.4, func() -> void: _say(SD.WEBER, "Tut mir leid, Kerner. Deutschland braucht Ordnung.", 3.6))
	_later(2.6, func() -> void:
		var at := create_tween()
		at.tween_property(_weber_arm, "rotation_degrees:x", 88.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	_later(5.2, _gunshot)
	_later(6.6, func() -> void: _say(SD.LENA, "Jonas… er war es die ganze Zeit.", 4.2))
	_later(11.2, _on_level_end)

func _gunshot() -> void:
	var muzzle := _weber.global_position + Vector3(-0.31, 1.6, 0.86)
	if is_instance_valid(_weber_muzzle):
		muzzle = _weber_muzzle.global_position
	VFX.play_sfx_3d("pistol_fire", muzzle, 4.0, 12.0, 60.0)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.8, 0.5)
	fl.light_energy = 12.0
	fl.omni_range = 9.0
	add_child(fl)
	fl.global_position = muzzle
	_trauma(1.0)
	# Schwarzblende sofort (Untertitel liegen darueber)
	var cl := CanvasLayer.new()
	cl.layer = 15
	add_child(cl)
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 1)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_black)
	_later(0.06, fl.queue_free)
