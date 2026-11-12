class_name Weather
extends Node3D
## Regen und Gewitter. Einfach in die Szene haengen (Node3D), Werte per Export/Skript setzen.
## - Regen folgt der aktiven Kamera (GPU-Partikel, Weltkoordinaten), Streifen-Shader, Kollision ueber
##   ein mitwanderndes Heightfield (unter Daechern regnet es nicht), Spritzer als Sub-Emitter.
## - Blitze: Bolt-Mesh am Horizont, Licht-Flash (gerichtetes Licht nur waehrend des Blitzes aktiv),
##   Donner verzoegert nach Distanz / 343 m/s auf Bus "Ambient".
## - Globaler Shader-Parameter "rain_wetness" (0..1) fuer nasse Oberflaechen (wird zur Laufzeit angelegt).

const VfxLib = preload("res://game/vfx/vfx_lib.gd")
const SOUND_SPEED := 343.0
const MAX_DROPS := 14000
const WET_PARAM := &"rain_wetness"

@export_range(0.0, 1.0) var rain_strength: float = 0.7:
	set(v):
		rain_strength = clampf(v, 0.0, 1.0)
		_apply_strength()
@export var lightning: bool = true
@export var lightning_interval: Vector2 = Vector2(8.0, 22.0)   ## zufaelliger Abstand (s)
@export var lightning_distance: Vector2 = Vector2(350.0, 1600.0)
@export var wind: Vector3 = Vector3(1.6, 0.0, 0.7)             ## seitlicher Drift der Tropfen (m/s)
@export var fall_speed: float = 24.0
@export var flash_color: Color = Color(0.78, 0.84, 1.0)
@export var flash_energy: float = 2.2
@export var rain_volume_db: float = -4.0

var wetness: float = 0.0

static var _param_ready: bool = false

var _rain: GPUParticles3D
var _splash: GPUParticles3D
var _rain_mat: ShaderMaterial
var _heightfield: GPUParticlesCollisionHeightField3D
var _flash_light: DirectionalLight3D
var _rain_snd: AudioStreamPlayer
var _next_bolt: float = 5.0
var _flash_t: float = -1.0
var _flash_curve: Array[float] = []
var _rng := RandomNumberGenerator.new()
var _bolt_mat: StandardMaterial3D
var _bolt_mi: MeshInstance3D
var _bolt_tw: Tween

func _ready() -> void:
	_rng.randomize()
	_next_bolt = _rng.randf_range(3.0, 8.0)
	_build_rain()
	_build_flash()
	_build_audio()
	_ensure_global_param()
	_apply_strength()
	if lightning:
		# Blitz-Shader schon beim Laden kompilieren (unsichtbar tief unter der Kamera, blendet sofort aus)
		_spawn_bolt.call_deferred(global_position + Vector3(0.0, -900.0, 0.0), 300.0)

func _exit_tree() -> void:
	if _param_ready:
		RenderingServer.global_shader_parameter_set(WET_PARAM, 0.0)

# ------------------------------------------------------------------ Aufbau

func _build_rain() -> void:
	# Spritzer (Sub-Emitter): kurze, kleine Tropfen, die bei Bodenkontakt hochspringen
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3.UP
	spm.spread = 55.0
	spm.initial_velocity_min = 0.8
	spm.initial_velocity_max = 2.0
	spm.gravity = Vector3(0, -9.8, 0)
	spm.scale_min = 0.5
	spm.scale_max = 1.0
	spm.color_ramp = VfxLib.ramp([[0.0, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0.0)]])
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	smat.vertex_color_use_as_albedo = true
	smat.albedo_color = Color(0.55, 0.6, 0.68)
	smat.albedo_texture = _dot_texture()
	_splash = VfxLib.make_particles(3000, 0.35, spm, VfxLib.quad(0.05), smat)
	_splash.name = "RainSplash"
	_splash.one_shot = false
	_splash.emitting = false
	_splash.local_coords = false
	_splash.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24.0, 1.0, 24.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = fall_speed * 0.9
	pm.initial_velocity_max = fall_speed * 1.1
	pm.gravity = Vector3(wind.x, -4.0, wind.z)
	pm.particle_flag_align_y = true
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	pm.color = Color(1, 1, 1, 0.55)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	pm.collision_use_scale = false
	pm.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	pm.sub_emitter_amount_at_collision = 2
	_rain_mat = VfxLib.shader_mat("rain_streak")
	var qm := QuadMesh.new()
	qm.size = Vector2(0.016, 0.85)
	_rain = VfxLib.make_particles(MAX_DROPS, 1.25, pm, qm, _rain_mat)
	_rain.name = "Rain"
	_rain.one_shot = false
	_rain.explosiveness = 0.0
	_rain.local_coords = false
	_rain.collision_base_size = 0.02
	_rain.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 60, 80))
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.preprocess = 1.2
	add_child(_rain)
	_rain.sub_emitter = _rain.get_path_to(_splash)

	_heightfield = GPUParticlesCollisionHeightField3D.new()
	_heightfield.name = "RainCollision"
	_heightfield.size = Vector3(56.0, 60.0, 56.0)
	_heightfield.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_heightfield.follow_camera_enabled = true
	add_child(_heightfield)

func _dot_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t

func _build_flash() -> void:
	_flash_light = DirectionalLight3D.new()
	_flash_light.name = "LightningFlash"
	_flash_light.light_color = flash_color
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = true
	_flash_light.directional_shadow_max_distance = 120.0
	_flash_light.visible = false
	_flash_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_flash_light)

func _build_audio() -> void:
	var st := Sfx.get_stream("wx_rain")
	if st == null:
		return
	st = st.duplicate() as AudioStream
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	elif st is AudioStreamWAV:
		(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_rain_snd = AudioStreamPlayer.new()
	_rain_snd.stream = st
	_rain_snd.bus = &"Ambient"
	add_child(_rain_snd)
	_rain_snd.play(_rng.randf() * 3.0)

func _ensure_global_param() -> void:
	# Bevorzugt in project.godot deklariert (shader_globals/rain_wetness); sonst einmalig zur Laufzeit anlegen.
	if _param_ready:
		return
	if not ProjectSettings.has_setting("shader_globals/" + WET_PARAM):
		RenderingServer.global_shader_parameter_add(WET_PARAM, RenderingServer.GLOBAL_VAR_TYPE_FLOAT, 0.0)
	_param_ready = true

func _apply_strength() -> void:
	if _rain == null:
		return
	_rain.amount_ratio = maxf(rain_strength, 0.001)
	_rain.emitting = rain_strength > 0.01
	if _rain_snd:
		_rain_snd.volume_db = rain_volume_db + linear_to_db(maxf(rain_strength, 0.01))

# ------------------------------------------------------------------ Laufzeit

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		var fwd := -cam.global_transform.basis.z
		fwd.y = 0.0
		var c := cam.global_position
		# Emitter oberhalb, leicht vor der Kamera und gegen den Wind versetzt (Tropfen driften hinein)
		var off := fwd.normalized() * 6.0 - Vector3(wind.x, 0.0, wind.z) * 0.9
		_rain.global_position = c + Vector3(0, 16.0, 0) + off
		_rain.global_rotation = Vector3.ZERO
	# Naesse steigt langsam an bzw. trocknet ab
	wetness = move_toward(wetness, rain_strength, delta * 0.05)
	if _param_ready:
		RenderingServer.global_shader_parameter_set(WET_PARAM, wetness)
	if lightning and rain_strength > 0.05:
		_next_bolt -= delta
		if _next_bolt <= 0.0:
			_next_bolt = _rng.randf_range(lightning_interval.x, lightning_interval.y)
			strike()
	_update_flash(delta)

## Loest sofort einen Blitz aus. distance < 0: zufaellig im Bereich lightning_distance.
func strike(distance: float = -1.0) -> void:
	var cam := get_viewport().get_camera_3d()
	var c := cam.global_position if cam else global_position
	var d := distance if distance > 0.0 else _rng.randf_range(lightning_distance.x, lightning_distance.y)
	var ang := _rng.randf() * TAU
	if cam:  # bevorzugt grob im Sichtfeld, damit man den Bolt auch sieht
		var f := -cam.global_transform.basis.z
		ang = atan2(f.x, f.z) + _rng.randf_range(-1.1, 1.1)
	var ground := c + Vector3(sin(ang), 0.0, cos(ang)) * d
	ground.y = c.y - 20.0
	_spawn_bolt(ground, d)
	# Licht-Flash: 2-4 Flackerer
	_flash_curve.clear()
	var n := _rng.randi_range(2, 4)
	for i in n:
		_flash_curve.append(_rng.randf_range(0.5, 1.0) * (1.0 if i == 0 else 0.7))
	_flash_t = 0.0
	var energy := flash_energy * clampf(900.0 / d, 0.35, 1.6)
	_flash_light.set_meta("peak", energy)
	_flash_light.visible = true
	var dir := (c - (ground + Vector3.UP * 400.0)).normalized()
	_flash_light.look_at_from_position(c - dir * 10.0, c, Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT)
	# Donner: verzoegert nach Schalllaufzeit, Lautstaerke nach Entfernung
	var close := d < 700.0
	var vol := lerpf(4.0, -12.0, clampf((d - 300.0) / 1400.0, 0.0, 1.0))
	_play_thunder("wx_thunder_close" if close else "wx_thunder", vol, d / SOUND_SPEED, _rng.randf_range(0.9, 1.08))

func _play_thunder(sfx_name: String, vol: float, delay: float, pitch: float) -> void:
	var st := Sfx.get_stream(sfx_name)
	if st == null:
		st = Sfx.get_stream("wx_thunder")
	if st == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = &"Ambient"
	p.volume_db = vol
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	get_tree().create_timer(delay, false).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.play())

func _update_flash(delta: float) -> void:
	if _flash_t < 0.0:
		return
	_flash_t += delta
	# Flackerer je 0.09 s, kurze Pausen dazwischen, danach Abklingen
	var slot := int(_flash_t / 0.11)
	var local := fmod(_flash_t, 0.11) / 0.11
	var k := 0.0
	if slot < _flash_curve.size():
		k = _flash_curve[slot] * (1.0 - local * 0.7) * (1.0 if local < 0.75 else 0.15)
	else:
		var tail := _flash_t - _flash_curve.size() * 0.11
		k = maxf(0.0, 0.3 - tail * 1.2)
		if k <= 0.0:
			_flash_t = -1.0
			_flash_light.visible = false
	_flash_light.light_energy = float(_flash_light.get_meta("peak", 1.0)) * k
	_rain_mat.set_shader_parameter("flash", k)

func _spawn_bolt(ground: Vector3, dist: float) -> void:
	var top := ground + Vector3(_rng.randf_range(-80, 80), _rng.randf_range(420.0, 560.0), _rng.randf_range(-80, 80))
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else global_position
	var width := clampf(dist * 0.004, 1.2, 6.0)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_bolt_branch(im, top, ground, width, 0, cam_pos)
	im.surface_end()
	# Ein dauerhafter Bolt-Knoten mit festem Material: Mit je Blitz neuem MeshInstance3D + Materialkopie
	# kompilierte der Renderer bei jedem Blitz 6 Pipelines neu (river_crossing: 30-45 ms Ruckler alle 8-22 s).
	if _bolt_mi == null:
		_bolt_mat = StandardMaterial3D.new()
		_bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bolt_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_bolt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_bolt_mat.vertex_color_use_as_albedo = true
		_bolt_mat.albedo_color = Color(2.6, 2.8, 3.4, 1.0)
		_bolt_mat.disable_fog = true
		_bolt_mi = MeshInstance3D.new()
		_bolt_mi.material_override = _bolt_mat
		_bolt_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bolt_mi.extra_cull_margin = 2000.0
		add_child(_bolt_mi)
	if _bolt_tw != null and _bolt_tw.is_valid():
		_bolt_tw.kill()
	_bolt_mi.mesh = im
	_bolt_mi.visible = true
	_bolt_mi.global_transform = Transform3D.IDENTITY
	_bolt_mat.albedo_color.a = 1.0
	var mi := _bolt_mi
	var tw := mi.create_tween()
	_bolt_tw = tw
	tw.tween_property(_bolt_mat, "albedo_color:a", 0.2, 0.06)
	tw.tween_property(_bolt_mat, "albedo_color:a", 1.0, 0.04)
	tw.tween_property(_bolt_mat, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(func() -> void: mi.visible = false)

## Rekursive Zickzack-Linie mit Abzweigungen als kamerazugewandte Baender.
func _bolt_branch(im: ImmediateMesh, a: Vector3, b: Vector3, width: float, depth: int, cam_pos: Vector3) -> void:
	var segs := 22 if depth == 0 else 9
	var pts: Array[Vector3] = [a]
	var len := a.distance_to(b)
	for i in range(1, segs):
		var t := float(i) / segs
		var p := a.lerp(b, t)
		var j := len / segs * 0.9
		p += Vector3(_rng.randf_range(-j, j), _rng.randf_range(-j, j) * 0.3, _rng.randf_range(-j, j))
		pts.append(p)
	pts.append(b)
	for i in pts.size() - 1:
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var w0 := width * (1.0 - float(i) / pts.size() * 0.5)
		var w1 := width * (1.0 - float(i + 1) / pts.size() * 0.5)
		var axis := (p1 - p0).normalized()
		var side := axis.cross((cam_pos - p0).normalized()).normalized()
		var col := Color(0.85, 0.9, 1.0, 1.0 if depth == 0 else 0.6)
		var glow := Color(0.5, 0.6, 1.0, 0.18 if depth == 0 else 0.1)
		_quad(im, p0, p1, side * w0, side * w1, col)
		_quad(im, p0, p1, side * w0 * 5.0, side * w1 * 5.0, glow)
		if depth < 2 and _rng.randf() < (0.22 if depth == 0 else 0.12):
			var bl := len / segs * _rng.randf_range(2.0, 5.0)
			var bd := (axis + Vector3(_rng.randf_range(-1, 1), -0.2, _rng.randf_range(-1, 1))).normalized()
			_bolt_branch(im, p0, p0 + bd * bl, width * 0.45, depth + 1, cam_pos)

func _quad(im: ImmediateMesh, p0: Vector3, p1: Vector3, s0: Vector3, s1: Vector3, col: Color) -> void:
	im.surface_set_color(col)
	im.surface_add_vertex(p0 - s0)
	im.surface_set_color(col)
	im.surface_add_vertex(p0 + s0)
	im.surface_set_color(col)
	im.surface_add_vertex(p1 + s1)
	im.surface_set_color(col)
	im.surface_add_vertex(p0 - s0)
	im.surface_set_color(col)
	im.surface_add_vertex(p1 + s1)
	im.surface_set_color(col)
	im.surface_add_vertex(p1 - s1)
