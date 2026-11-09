extends Node3D
## Effekte fuer Level river_crossing: Wetter (game/vfx/weather.gd, sonst eigener Regen + Blitze),
## Ambience (Fluss unter der Bruecke, Regen auf Stahl), Leuchtspur-Feuer am Horizont,
## wasserbewusster Artilleriebeschuss (Fontaenen im Fluss, Explosionen an Land) und Wasser-Gischt.

const VfxLib = preload("res://game/vfx/vfx_lib.gd")
const WEATHER_PATH := "res://game/vfx/weather.gd"

## Flussbereich (z) und halbe Brueckenbreite: Treffer dazwischen sind "Wasser".
var river_z0: float = -64.0
var river_z1: float = -190.0
var water_y: float = -9.0
var artillery_enabled: bool = false
var env: Environment
var sky_energy_base: float = 0.35
var weather: Node3D = null

var _rng := RandomNumberGenerator.new()
var _flash: DirectionalLight3D
var _flash_t: float = -1.0
var _next_bolt: float = 6.0
var _rain: GPUParticles3D
var _tracers: Array[MeshInstance3D] = []
var _tracer_t: float = 2.0
var _art_t: float = 9.0
var _splash_pm: ParticleProcessMaterial
var _splash_mat: ShaderMaterial
var _mist_pm: ParticleProcessMaterial
var _mist_mat: ShaderMaterial

func _ready() -> void:
	_rng.randomize()
	_build_weather()
	_build_ambience()
	_build_tracers()
	_build_splash_templates()

# ------------------------------------------------------------------ Wetter

func _build_weather() -> void:
	if ResourceLoader.exists(WEATHER_PATH):
		var scr := load(WEATHER_PATH) as Script
		if scr != null:
			weather = Node3D.new()
			weather.set_script(scr)
			weather.name = "Weather"
			weather.set("rain_strength", 0.9)
			weather.set("lightning", true)
			weather.set("lightning_interval", Vector2(7.0, 16.0))
			weather.set("wind", Vector3(2.2, 0.0, 1.0))
			add_child(weather)
			return
	# Eigener Ersatz: Regenstreifen um die Kamera + Blitzlicht + Regen-Loop
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22.0, 1.0, 22.0)
	pm.direction = Vector3(0.08, -1, 0.04)
	pm.spread = 3.0
	pm.initial_velocity_min = 20.0
	pm.initial_velocity_max = 25.0
	pm.gravity = Vector3(2.0, -6.0, 1.0)
	pm.particle_flag_align_y = true
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.45, 0.5, 0.58, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.9)
	_rain = VfxLib.make_particles(9000, 1.3, pm, q, m)
	_rain.one_shot = false
	_rain.explosiveness = 0.0
	_rain.preprocess = 1.3
	_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 60, 80))
	_rain.emitting = true
	add_child(_rain)
	var snd := AudioStreamPlayer.new()
	snd.stream = _loop("res://assets/sfx/river_rain.ogg")
	snd.volume_db = -6.0
	snd.bus = _bus("Ambient")
	snd.autoplay = true
	add_child(snd)
	_flash = DirectionalLight3D.new()
	_flash.name = "LightningFlash"
	_flash.light_color = Color(0.78, 0.84, 1.0)
	_flash.light_energy = 0.0
	_flash.shadow_enabled = true
	_flash.visible = false
	_flash.transform = Transform3D(Basis.looking_at(Vector3(0.4, -0.7, 0.55).normalized(), Vector3.UP), Vector3.ZERO)
	add_child(_flash)

## Sofortiger Blitz (z. B. fuer Story-Momente). close = naher Einschlag mit lautem Donner.
func strike(close: bool = false) -> void:
	if weather != null and weather.has_method("strike"):
		weather.call("strike", 260.0 if close else -1.0)
		return
	_flash_t = 0.0
	var dist := 250.0 if close else _rng.randf_range(400.0, 1500.0)
	get_tree().create_timer(dist / 343.0, false).timeout.connect(func() -> void:
		var s := AudioStreamPlayer.new()
		s.stream = load("res://assets/sfx/river_thunder_close.ogg" if dist < 600.0 else "res://assets/sfx/river_thunder.ogg")
		s.volume_db = 0.0 if dist < 600.0 else -5.0
		s.bus = _bus("Ambient")
		add_child(s)
		s.play()
		s.finished.connect(s.queue_free))

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if _rain != null and cam != null:
		_rain.global_position = cam.global_position + Vector3(0, 14.0, 0) - cam.global_basis.z * 8.0
	if weather == null:
		_next_bolt -= delta
		if _next_bolt <= 0.0:
			_next_bolt = _rng.randf_range(7.0, 18.0)
			strike(false)
		if _flash_t >= 0.0:
			_flash_t += delta
			# Doppelblitz: zwei kurze Spitzen
			var e := 0.0
			if _flash_t < 0.08:
				e = 1.0
			elif _flash_t < 0.16:
				e = 0.25
			elif _flash_t < 0.26:
				e = 0.8
			elif _flash_t < 0.6:
				e = lerpf(0.5, 0.0, (_flash_t - 0.26) / 0.34)
			else:
				_flash_t = -1.0
			_flash.visible = e > 0.0
			_flash.light_energy = e * 2.4
			if env != null:
				env.background_energy_multiplier = sky_energy_base * (1.0 + e * 5.0)
	_update_tracers(delta)
	if artillery_enabled:
		_art_t -= delta
		if _art_t <= 0.0:
			_art_t = _rng.randf_range(6.0, 13.0)
			_random_shell()

# ------------------------------------------------------------------ Ambience

func _build_ambience() -> void:
	# Fluss rauscht unter der Bruecke (zwei Quellen ueber die Laenge verteilt)
	for z: float in [-90.0, -160.0]:
		var p := AudioStreamPlayer3D.new()
		p.stream = _loop("res://assets/sfx/river_flow.ogg")
		p.position = Vector3(0, water_y + 1.0, z)
		p.unit_size = 22.0
		p.max_distance = 140.0
		p.volume_db = 2.0
		p.bus = _bus("Ambient")
		p.autoplay = true
		add_child(p)
	# Regen auf dem Stahlfachwerk
	for z: float in [-84.0, -125.0, -167.0]:
		var p := AudioStreamPlayer3D.new()
		p.stream = _loop("res://assets/sfx/river_rain_metal.ogg")
		p.position = Vector3(0, 5.0, z)
		p.unit_size = 9.0
		p.max_distance = 45.0
		p.volume_db = -5.0
		p.bus = _bus("Ambient")
		p.autoplay = true
		add_child(p)

static func _loop(path: String) -> AudioStream:
	var s := load(path) as AudioStreamOggVorbis
	if s != null:
		s = s.duplicate() as AudioStreamOggVorbis
		s.loop = true
	return s

static func _bus(n: String) -> StringName:
	return StringName(n) if AudioServer.get_bus_index(n) >= 0 else &"Master"

# ------------------------------------------------------------------ Leuchtspur am Horizont

func _build_tracers() -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.5, 0.2)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.45, 0.15)
	m.emission_energy_multiplier = 9.0
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 0.12, 5.0)
	for i in 14:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		mi.top_level = true
		add_child(mi)
		_tracers.append(mi)

func _update_tracers(delta: float) -> void:
	_tracer_t -= delta
	if _tracer_t > 0.0:
		return
	_tracer_t = _rng.randf_range(1.4, 4.0)
	# Feuerstoss weit seitlich (MG-Stellungen am Ostufer schiessen in den Himmel / auf das Westufer)
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var from := Vector3(side * _rng.randf_range(70.0, 160.0), _rng.randf_range(1.0, 6.0), _rng.randf_range(-260.0, -200.0))
	var to := from + Vector3(_rng.randf_range(-40.0, 40.0), _rng.randf_range(25.0, 70.0), _rng.randf_range(120.0, 220.0))
	var n := _rng.randi_range(4, 7)
	for k in n:
		get_tree().create_timer(k * 0.09, false).timeout.connect(_fire_tracer.bind(from, to + Vector3(_rng.randf_range(-4, 4), _rng.randf_range(-4, 4), 0)))

func _fire_tracer(from: Vector3, to: Vector3) -> void:
	for t in _tracers:
		if t.visible:
			continue
		t.visible = true
		t.global_position = from
		t.look_at_from_position(from, to, Vector3.UP)
		var tw := t.create_tween()
		tw.tween_property(t, "global_position", to, from.distance_to(to) / 260.0)
		tw.tween_callback(func() -> void: t.visible = false)
		return

# ------------------------------------------------------------------ Artillerie und Gischt

func _random_shell() -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var pz := pl.global_position.z if pl != null else -60.0
	var side := -1.0 if _rng.randf() < 0.5 else 1.0
	var pos := Vector3(side * _rng.randf_range(28.0, 110.0), 0.0, pz - _rng.randf_range(-20.0, 90.0))
	shell(pos)
	if pl != null and pl.has_method("add_trauma"):
		pl.call("add_trauma", clampf(0.16 - pl.global_position.distance_to(pos) / 700.0, 0.02, 0.16))

## Granateinschlag: im Fluss Wasserfontaene, an Land Explosion. Kein Schaden (Kulisse).
func shell(pos: Vector3) -> void:
	if is_water(pos):
		splash(Vector3(pos.x, water_y, pos.z), 2.2)
		VFX.audio.call("explosion", Vector3(pos.x, water_y, pos.z), 1.4)
	else:
		VFX.spawn_explosion(pos, _rng.randf_range(2.4, 3.6))

func is_water(p: Vector3) -> bool:
	return p.z < river_z0 + 2.0 and p.z > river_z1 - 2.0

func _build_splash_templates() -> void:
	_splash_pm = ParticleProcessMaterial.new()
	_splash_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_splash_pm.emission_sphere_radius = 1.0
	_splash_pm.direction = Vector3.UP
	_splash_pm.spread = 16.0
	_splash_pm.initial_velocity_min = 9.0
	_splash_pm.initial_velocity_max = 20.0
	_splash_pm.gravity = Vector3(0, -14.0, 0)
	_splash_pm.damping_min = 0.5
	_splash_pm.damping_max = 1.5
	_splash_pm.scale_min = 1.2
	_splash_pm.scale_max = 3.0
	_splash_pm.scale_curve = VfxLib.curve_tex([[0.0, 0.4], [0.3, 1.0], [1.0, 1.6]])
	_splash_pm.color = Color(0.82, 0.86, 0.9)
	_splash_pm.color_ramp = VfxLib.smoke_alpha_ramp(0.9, 0.05, 0.4)
	VfxLib.smoke_pm(_splash_pm, 25.0)
	_splash_mat = VfxLib.smoke_mat({"density": 1.4}, true)  # fx2: Flipbook duenner -> Dichte hoch
	_mist_pm = ParticleProcessMaterial.new()
	_mist_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	_mist_pm.emission_ring_axis = Vector3.UP
	_mist_pm.emission_ring_radius = 2.0
	_mist_pm.emission_ring_inner_radius = 0.5
	_mist_pm.emission_ring_height = 0.2
	_mist_pm.direction = Vector3.UP
	_mist_pm.spread = 70.0
	_mist_pm.initial_velocity_min = 2.0
	_mist_pm.initial_velocity_max = 5.0
	_mist_pm.gravity = Vector3(0.8, 0.3, 0)
	_mist_pm.damping_min = 1.0
	_mist_pm.damping_max = 2.0
	_mist_pm.scale_min = 3.0
	_mist_pm.scale_max = 6.0
	_mist_pm.scale_curve = VfxLib.curve_tex([[0.0, 0.5], [1.0, 1.8]])
	_mist_pm.color = Color(0.7, 0.74, 0.78)
	_mist_pm.color_ramp = VfxLib.smoke_alpha_ramp(0.5, 0.1, 0.35)
	VfxLib.smoke_pm(_mist_pm, 8.0)
	_mist_mat = VfxLib.smoke_mat({"density": 1.4}, true)

## Wasserfontaene + Gischtnebel. size ~ 1 (Granate) bis 4 (Brueckenfeld/Hubschrauber).
func splash(pos: Vector3, size: float = 1.0, sound: bool = true) -> void:
	var col := VfxLib.make_particles(int(40 * size), 2.6, _splash_pm, VfxLib.quad(1.0), _splash_mat)
	col.scale = Vector3.ONE * size
	col.speed_scale = 1.0 / sqrt(size)
	col.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 80, 60))
	add_child(col)
	col.global_position = pos
	col.emitting = true
	var mist := VfxLib.make_particles(int(24 * size), 5.0, _mist_pm, VfxLib.quad(1.0), _mist_mat)
	mist.scale = Vector3.ONE * size
	mist.explosiveness = 0.8
	add_child(mist)
	mist.global_position = pos + Vector3(0, 0.5, 0)
	mist.emitting = true
	get_tree().create_timer(6.5, false).timeout.connect(func() -> void:
		col.queue_free()
		mist.queue_free())
	if sound:
		VFX.audio.call("play_3d", "river_splash", pos, 4.0 + size * 2.0, 14.0 * size, 300.0, _rng.randf_range(0.85, 1.05))
