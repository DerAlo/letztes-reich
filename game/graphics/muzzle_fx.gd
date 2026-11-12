extends Node3D
## Muendungsfeuer im Stil moderner Militaer-Shooter (nur Optik, keine Balance).
## Ersetzt den alten Verlaufs-Kreis + gekreuzte Verlaufs-Zungen + Kugel-Funken ("Playmobil"-Look).
##  - Front-Stern: kamerazugewandtes Sprite aus assets/vfx/muzzle_flash_front.png (4 Varianten),
##    weissglühender Kern -> orange, unregelmaessige Zungen; je Schuss Variante/Rotation/Groesse zufaellig.
##  - Seitenflamme: um die Laufachse zur Kamera gedrehtes Sprite (muzzle_flash_side.png, 4 Varianten).
##  - Beide leben nur ~2 Frames (FLASH_TIME); im zweiten Frame frisst die Erosion die Ausleger weg.
##  - Feine Funken (duenne Geschwindigkeits-Striche), kurzer Hitze-/Rauchhauch, bei Dauerfeuer dichter.
##  - Optional (with_light): kurzes, warmes Flackern einer OmniLight (beleuchtet die Welt).
## Haengt unter weapon.gd -> muzzle (Viewmodel) bzw. unter dem Muendungs-Node der Gegnerwaffe.
## Shader: game/vfx/shaders/muzzle_flash.gdshader, muzzle_spark.gdshader. Aufruf: fire(), stop().

const FLASH_TIME := 0.034       # s, ~2 Frames bei 60 fps
const LIGHT_TIME := 0.05        # s, Licht klingt etwas laenger ab als das Sprite
const FRONT_TEX := "res://assets/vfx/muzzle_flash_front.png"
const SIDE_TEX := "res://assets/vfx/muzzle_flash_side.png"
const FLASH_SHADER := "res://game/vfx/shaders/muzzle_flash.gdshader"
const SPARK_SHADER := "res://game/vfx/shaders/muzzle_spark.gdshader"
const VfxLib := preload("res://game/vfx/vfx_lib.gd")

var _front: MeshInstance3D
var _side: MeshInstance3D
var _sparks: GPUParticles3D
var _smoke: GPUParticles3D
var _light: OmniLight3D
var _flash_t: float = 0.0
var _light_t: float = 0.0
var _light_peak: float = 0.0
var _smoke_t: float = 0.0
var _heat: float = 0.0
var _suppressed: bool = false
var _k: float = 1.0

static var _shader_vm: Shader       # Viewmodel: ohne Tiefentest (eigener Viewport, nur die Waffe)
static var _shader_world: Shader
static var _mats: Dictionary = {}
static var _spark_mat: ShaderMaterial
static var _spark_pm: ParticleProcessMaterial
static var _smoke_mat: ShaderMaterial
static var _smoke_pm: ParticleProcessMaterial


## small = Pistole, suppressed = Schalldaempfer (fast kein Feuer), layer_bit = Render-Layer.
## scale: Gesamtgroesse (Werfer/Gegner), viewmodel: im Waffen-Viewport,
## with_light: eigenes Muendungslicht (weapon.gd hat ein eigenes -> false).
func setup(small: bool, suppressed: bool, layer_bit: int, scale_k: float = 1.0, viewmodel: bool = true, with_light: bool = false) -> void:
	_suppressed = suppressed
	_k = (0.62 if small else 1.0) * scale_k
	var shader := _get_shader(viewmodel)
	# Front-Stern
	_front = MeshInstance3D.new()
	_front.name = "FlashFront"
	var fq := QuadMesh.new()
	fq.size = Vector2(0.19, 0.19) * _k
	_front.mesh = fq
	_front.material_override = _get_mat(shader, FRONT_TEX, false, Vector2(2, 2))
	_front.position = Vector3(0.0, 0.0, -0.015 * _k)
	_init_geo(_front, layer_bit)
	add_child(_front)
	if not suppressed:
		# Seitenflamme (Wurzel an der Muendung, nach vorn)
		_side = MeshInstance3D.new()
		_side.name = "FlashSide"
		var sq := QuadMesh.new()
		var ln := 0.4 * _k
		sq.size = Vector2(ln / 3.0 * 1.15, ln)
		sq.center_offset = Vector3(0.0, ln * 0.5 - 0.01 * _k, 0.0)
		_side.mesh = sq
		_side.material_override = _get_mat(shader, SIDE_TEX, true, Vector2(4, 1))
		_init_geo(_side, layer_bit)
		add_child(_side)
		# Funken
		_sparks = GPUParticles3D.new()
		_sparks.name = "MuzzleSparks"
		_sparks.process_material = _get_spark_pm()
		var spq := QuadMesh.new()
		spq.size = Vector2(0.0025, 0.028) * sqrt(_k)
		spq.material = _get_spark_mat()
		_sparks.draw_pass_1 = spq
		_sparks.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
		_sparks.amount = 7
		_sparks.lifetime = 0.16
		_sparks.one_shot = true
		_sparks.explosiveness = 1.0
		_sparks.randomness = 0.6
		_sparks.emitting = false
		_sparks.local_coords = false
		_sparks.speed_scale = 1.0
		_sparks.layers = layer_bit
		_sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sparks.visibility_aabb = AABB(Vector3(-2, -2, -3), Vector3(4, 4, 5))
		add_child(_sparks)
		if with_light:
			_light = OmniLight3D.new()
			_light.light_color = Color(1.0, 0.68, 0.36)
			_light.omni_range = 6.0 * scale_k
			_light.omni_attenuation = 1.6
			_light.shadow_enabled = false
			_light.position = Vector3(0, 0, -0.12)
			_light.visible = false
			add_child(_light)
	# Rauch-/Hitzehauch
	_smoke = GPUParticles3D.new()
	_smoke.name = "MuzzleSmoke"
	_smoke.process_material = _get_smoke_pm()
	var dq := QuadMesh.new()
	dq.size = Vector2(0.09, 0.09) * _k
	_smoke.draw_pass_1 = dq
	_smoke.material_override = _get_smoke_mat()
	_smoke.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	_smoke.amount = 8 if suppressed else 16
	_smoke.lifetime = 0.9
	_smoke.local_coords = false
	_smoke.emitting = false
	_smoke.layers = layer_bit
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke.visibility_aabb = AABB(Vector3(-1.5, -1.5, -2.5), Vector3(3.0, 3.0, 4.0))
	add_child(_smoke)
	set_process(false)


func _init_geo(g: GeometryInstance3D, layer_bit: int) -> void:
	g.layers = layer_bit
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	g.visible = false


func fire() -> void:
	_heat = minf(_heat + 0.25, 1.0)
	_flash_t = FLASH_TIME
	if _suppressed:
		# Schalldaempfer: nur ein schwaches, kleines Glimmen, nicht bei jedem Schuss
		_front.visible = randf() < 0.55
		_front.set_instance_shader_parameter("frame", float(randi() % 4))
		_front.set_instance_shader_parameter("rot", randf() * TAU)
		_front.set_instance_shader_parameter("strength", randf_range(0.08, 0.16))
		_front.set_instance_shader_parameter("age", 0.0)
		_front.scale = Vector3.ONE * randf_range(0.3, 0.45)
	else:
		_front.visible = true
		_front.set_instance_shader_parameter("frame", float(randi() % 4))
		_front.set_instance_shader_parameter("rot", randf() * TAU)
		_front.set_instance_shader_parameter("strength", randf_range(0.8, 1.15))
		_front.set_instance_shader_parameter("age", 0.0)
		_front.scale = Vector3.ONE * randf_range(0.75, 1.2)
		_side.visible = randf() > 0.06       # selten nur der Stern (wirkt lebendiger)
		_side.set_instance_shader_parameter("frame", float(randi() % 4))
		_side.set_instance_shader_parameter("strength", randf_range(0.75, 1.1))
		_side.set_instance_shader_parameter("age", 0.0)
		var w := randf_range(0.8, 1.2)
		_side.scale = Vector3(w * (1.0 if randf() < 0.5 else -1.0), 1.0, randf_range(0.7, 1.3))
		_sparks.amount_ratio = randf_range(0.3, 1.0)
		_sparks.restart()
		_sparks.emitting = true
		if _light != null:
			_light_peak = randf_range(2.2, 3.4)
			_light_t = LIGHT_TIME
			_light.light_energy = _light_peak
			_light.visible = true
	if _smoke != null:
		_smoke_t = 0.04 + 0.1 * _heat
		_smoke.amount_ratio = clampf(0.3 + _heat, 0.0, 1.0)
		_smoke.emitting = true
	set_process(true)


func _process(delta: float) -> void:
	_heat = maxf(_heat - delta * 0.6, 0.0)
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_front.visible = false
			if _side != null:
				_side.visible = false
		else:
			var age := 1.0 - _flash_t / FLASH_TIME
			_front.set_instance_shader_parameter("age", age)
			if _side != null:
				_side.set_instance_shader_parameter("age", age)
	if _light != null and _light_t > 0.0:
		_light_t -= delta
		if _light_t <= 0.0:
			_light.visible = false
		else:
			var f := _light_t / LIGHT_TIME
			_light.light_energy = _light_peak * f * f * randf_range(0.8, 1.0)
	if _smoke_t > 0.0:
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke.emitting = false
	if _flash_t <= 0.0 and _smoke_t <= 0.0 and _light_t <= 0.0 and _heat <= 0.0:
		set_process(false)


func stop() -> void:
	_flash_t = 0.0
	_smoke_t = 0.0
	_light_t = 0.0
	if _front != null:
		_front.visible = false
	if _side != null:
		_side.visible = false
	if _light != null:
		_light.visible = false
	if _smoke != null:
		_smoke.emitting = false


static func _get_shader(viewmodel: bool) -> Shader:
	if _shader_world == null:
		_shader_world = load(FLASH_SHADER)
		# Viewmodel: MIT Tiefentest. Ohne ihn lag der kamerazugewandte Front-Stern im Zielen (Mündung direkt
		# hinter Korn/Verschluss) als Scheibe mitten auf der Waffe; mit Tiefentest verdeckt die Waffe den
		# Teil des Feuers, der physikalisch hinter ihr liegt, und das Feuer sitzt sichtbar vor der Mündung.
		_shader_vm = _shader_world
	return _shader_vm if viewmodel else _shader_world


static func _get_mat(shader: Shader, tex_path: String, axial: bool, grid: Vector2) -> ShaderMaterial:
	var key := "%d|%s" % [shader.get_instance_id(), tex_path]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("flash_tex", load(tex_path))
	m.set_shader_parameter("grid", grid)
	m.set_shader_parameter("axial", axial)
	m.set_shader_parameter("energy", 1.9 if axial else 1.8)
	_mats[key] = m
	return m


static func _get_spark_mat() -> ShaderMaterial:
	if _spark_mat != null:
		return _spark_mat
	_spark_mat = ShaderMaterial.new()
	_spark_mat.shader = load(SPARK_SHADER)
	_spark_mat.set_shader_parameter("intensity", 3.0)
	return _spark_mat


static func _get_spark_pm() -> ParticleProcessMaterial:
	if _spark_pm != null:
		return _spark_pm
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 16.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -4.0, 0)
	pm.damping_min = 6.0
	pm.damping_max = 14.0
	pm.particle_flag_align_y = true
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var cr := Gradient.new()
	cr.set_color(0, Color(1.0, 0.92, 0.7, 1.0))
	cr.add_point(0.35, Color(1.0, 0.55, 0.15, 0.9))
	cr.set_color(cr.get_point_count() - 1, Color(0.7, 0.15, 0.02, 0.0))
	var crt := GradientTexture1D.new()
	crt.gradient = cr
	pm.color_ramp = crt
	_spark_pm = pm
	return pm


static func _get_smoke_mat() -> ShaderMaterial:
	if _smoke_mat != null:
		return _smoke_mat
	# beleuchteter, zerfaserter Rauch (gemeinsamer Rauch-Shader) statt Verlaufsscheibe
	_smoke_mat = VfxLib.smoke_mat({
		"smoke_color": Color(0.42, 0.41, 0.4), "smoke_color_end": Color(0.55, 0.54, 0.53),
		"density": 0.9, "erosion": 0.5, "frame_span": 4.0,
		"near_fade": 0.12, "close_cull": 0.41, "soft_dist": 0.04, "soft_size_factor": 0.2,
		"glow": 1.2, "glow_decay": 14.0,
	}, true)
	return _smoke_mat


static func _get_smoke_pm() -> ParticleProcessMaterial:
	if _smoke_pm != null:
		return _smoke_pm
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 16.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.3, 0)
	pm.damping_min = 1.4
	pm.damping_max = 2.4
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	VfxLib.smoke_pm(pm, 50.0)
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.3))
	sc.add_point(Vector2(0.4, 1.0))
	sc.add_point(Vector2(1.0, 2.3))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var cr := Gradient.new()
	cr.set_color(0, Color(1, 1, 1, 0.0))
	cr.add_point(0.08, Color(1, 1, 1, 0.3))
	cr.add_point(0.4, Color(1, 1, 1, 0.16))
	cr.set_color(cr.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var crt := GradientTexture1D.new()
	crt.gradient = cr
	pm.color_ramp = crt
	_smoke_pm = pm
	return pm
