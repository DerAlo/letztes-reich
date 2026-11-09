extends Node3D
## Kleiner gepoolter Effekt fuer Einschlaege (Staub, Funken), Blut und grosse Staubwolken.

signal finished(fx: Node3D)

const VfxLib = preload("res://game/vfx/vfx_lib.gd")

## true = grosse Staubwolke (viele Partikel), false = kleiner Einschlag/Blut
@export var big: bool = false

var _busy: bool = false
var _tween: Tween
var _dust: GPUParticles3D
var _sparks: GPUParticles3D
var _drops: GPUParticles3D
var _dust_pm: ParticleProcessMaterial
var _dust_mat: ShaderMaterial
var _spark_pm: ParticleProcessMaterial
var _drop_pm: ParticleProcessMaterial
var _built: bool = false

func is_busy() -> bool:
	return _busy

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	var quad := VfxLib.quad(1.0)
	_dust_pm = ParticleProcessMaterial.new()
	_dust_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	VfxLib.smoke_pm(_dust_pm, 20.0)
	_dust_pm.damping_min = 2.0
	_dust_pm.damping_max = 3.0
	_dust_pm.gravity = Vector3(0, 0.3, 0) + VfxLib.WIND * (0.5 if big else 0.2)
	_dust_pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.35], [0.3, 0.85], [1.0, 1.5]])
	_dust_pm.color_ramp = VfxLib.smoke_alpha_ramp(1.0, 0.06, 0.3)
	_dust_pm.turbulence_enabled = big
	_dust_pm.turbulence_noise_strength = 0.6
	_dust_mat = VfxLib.smoke_mat({"smoke_color": Vector3(0.3, 0.27, 0.23), "density": 1.0, "soft_dist": 0.25 if not big else 0.8,
		"erosion": 0.5, "frame_span": 6.0 if big else 3.0, "self_shadow": 0.35, "near_fade": 0.5 if not big else 1.2}, true)
	_dust = VfxLib.make_particles(60 if big else 10, 5.5 if big else 1.3, _dust_pm, quad, _dust_mat)
	_dust.explosiveness = 0.85 if big else 1.0
	_dust.randomness = 0.3
	add_child(_dust)

	if not big:
		var sm := BoxMesh.new()
		sm.size = Vector3(0.012, 0.1, 0.012)
		_spark_pm = ParticleProcessMaterial.new()
		_spark_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_spark_pm.emission_sphere_radius = 0.03
		_spark_pm.spread = 55.0
		_spark_pm.gravity = Vector3(0, -9.8, 0)
		_spark_pm.initial_velocity_min = 2.0
		_spark_pm.initial_velocity_max = 7.0
		_spark_pm.particle_flag_align_y = true
		_spark_pm.color_ramp = VfxLib.ramp([[0.0, Color(1.0, 0.95, 0.7, 1)], [0.35, Color(1.0, 0.55, 0.12, 1)], [1.0, Color(0.6, 0.1, 0.0, 0.0)]])
		_spark_pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		_spark_pm.collision_bounce = 0.4
		_spark_pm.collision_friction = 0.3
		_sparks = VfxLib.make_particles(16, 0.7, _spark_pm, sm, VfxLib.shader_mat("spark", {"intensity": 8.0}))
		_sparks.randomness = 0.5
		add_child(_sparks)

		var dm := SphereMesh.new()
		dm.radius = 0.025
		dm.height = 0.05
		dm.radial_segments = 6
		dm.rings = 3
		_drop_pm = ParticleProcessMaterial.new()
		_drop_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		_drop_pm.emission_sphere_radius = 0.05
		_drop_pm.spread = 40.0
		_drop_pm.gravity = Vector3(0, -9.8, 0)
		_drop_pm.initial_velocity_min = 1.0
		_drop_pm.initial_velocity_max = 3.5
		_drop_pm.scale_min = 0.5
		_drop_pm.scale_max = 1.4
		_drop_pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
		var blood_mat := StandardMaterial3D.new()
		blood_mat.albedo_color = Color(0.32, 0.01, 0.01)
		blood_mat.roughness = 0.2
		_drops = VfxLib.make_particles(8, 0.8, _drop_pm, dm, blood_mat)
		_drops.randomness = 0.4
		add_child(_drops)

## kind: concrete, dirt, metal, wood, sand, blood, cloud
func play(kind: String, pos: Vector3, normal: Vector3, s: float = 1.0) -> void:
	_build()
	if _tween and _tween.is_valid():
		_tween.kill()
	_busy = true
	global_position = pos + normal * 0.03
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.UP
	_dust_pm.direction = n
	var col := Vector3(0.34, 0.31, 0.27)
	var dens := 0.6
	var dust_scale := 0.35
	var spark := false
	var drops := false
	match kind:
		"metal":
			col = Vector3(0.22, 0.2, 0.19); dens = 0.35; spark = true; dust_scale = 0.22
		"dirt", "sand":
			col = Vector3(0.28, 0.2, 0.13); dens = 0.7; dust_scale = 0.45
		"wood":
			col = Vector3(0.3, 0.2, 0.12); dens = 0.4; dust_scale = 0.25
		"blood":
			col = Vector3(0.32, 0.015, 0.012); dens = 0.55; dust_scale = 0.2; drops = true
		"cloud":
			col = Vector3(0.38, 0.34, 0.29); dens = 0.8; dust_scale = 1.0
		_:
			col = Vector3(0.36, 0.33, 0.29); dens = 0.55; spark = false
	_dust_mat.set_shader_parameter("smoke_color", col)
	_dust_mat.set_shader_parameter("smoke_color_end", col * 1.2 + Vector3(0.03, 0.03, 0.03))
	_dust_mat.set_shader_parameter("density", dens)
	if big:
		_dust_pm.spread = 80.0
		_dust_pm.emission_sphere_radius = 1.0 * s
		_dust_pm.initial_velocity_min = 2.0 * s
		_dust_pm.initial_velocity_max = 9.0 * s
		_dust_pm.scale_min = 3.6 * s
		_dust_pm.scale_max = 6.5 * s
		_dust.visibility_aabb = AABB(Vector3(-40, -5, -40) * s, Vector3(80, 60, 80) * s)
	else:
		_dust_pm.spread = 35.0 if kind != "blood" else 60.0
		_dust_pm.emission_sphere_radius = 0.04
		_dust_pm.initial_velocity_min = 0.6 * s
		_dust_pm.initial_velocity_max = 2.0 * s if kind != "blood" else 1.0
		_dust_pm.scale_min = dust_scale * 0.8 * s
		_dust_pm.scale_max = dust_scale * 1.4 * s
		_dust.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 8, 8))
	_dust.restart()
	if _sparks:
		_spark_pm.direction = n
		if spark:
			_sparks.restart()
	if _drops:
		_drop_pm.direction = n
		if drops:
			_drops.restart()
	_tween = create_tween()
	_tween.tween_interval(5.5 if big else 2.0)
	_tween.tween_callback(func() -> void:
		_busy = false
		finished.emit(self))
