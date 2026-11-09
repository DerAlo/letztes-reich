extends Node3D
## Mehrschichtige Explosion (Blitz, Licht, Feuerball, Rauchpilz, Funken, Truemmer, Staubring,
## Schockwelle, Brandfleck). Wird vom VFX-Autoload gepoolt: play(pos, scale) startet sie neu,
## nach `duration` Sekunden wird `finished` emittiert.

signal finished(explosion: Node3D)

const VfxLib = preload("res://game/vfx/vfx_lib.gd")

@export_group("Allgemein")
@export var duration: float = 9.0
@export var debris_count: int = 7
@export var light_peak_energy: float = 55.0
@export var light_range: float = 30.0
@export var shadows: bool = true
@export_group("Feuer")
@export var fire_intensity: float = 1.9
@export_group("Rauch")
@export var smoke_color: Color = Color(0.1, 0.092, 0.085)
@export var smoke_density: float = 1.0

var _s: float = 1.0
var _busy: bool = false
var _tween: Tween
var _built: bool = false
var _ground_y: float = -1000.0
var _has_ground: bool = false

var _flash: MeshInstance3D
var _flash_mat: ShaderMaterial
var _light: OmniLight3D
var _shock: MeshInstance3D
var _shock_mat: ShaderMaterial
var _fire_core: GPUParticles3D
var _fire_body: GPUParticles3D
var _smoke_col: GPUParticles3D
var _smoke_cap: GPUParticles3D
var _smoke_low: GPUParticles3D
var _dust: GPUParticles3D
var _sparks: GPUParticles3D
var _embers: GPUParticles3D
var _pm: Dictionary = {}
## Rauch-Materialien mit Glut-Startwert: Glut wird pro Explosion global ausgeblendet (nicht pro Partikel-Alter,
## sonst gluehen spaet gespawnte Partikel noch Sekunden spaeter).
var _smoke_glow: Array = []

func is_busy() -> bool:
	return _busy

func _ready() -> void:
	_build()

func _build() -> void:
	if _built:
		return
	_built = true
	var quad := VfxLib.quad(1.0)

	# --- Blitz -------------------------------------------------------------
	_flash_mat = VfxLib.shader_mat("flash", {"intensity": 9.0})
	_flash = MeshInstance3D.new()
	_flash.mesh = quad
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)

	# --- Licht -------------------------------------------------------------
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.62, 0.28)
	_light.omni_attenuation = 1.4
	_light.light_volumetric_fog_energy = 1.0
	_light.shadow_enabled = shadows
	_light.shadow_bias = 0.05
	_light.light_energy = 0.0
	_light.visible = false
	add_child(_light)

	# --- Schockwelle -------------------------------------------------------
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	sph.radial_segments = 48
	sph.rings = 24
	_shock_mat = VfxLib.shader_mat("shockwave")
	_shock = MeshInstance3D.new()
	_shock.mesh = sph
	_shock.material_override = _shock_mat
	_shock.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shock.visible = false
	add_child(_shock)

	# --- Feuer-Kern + Feuerball -------------------------------------------
	var fire_m := VfxLib.fire_mat({"intensity": fire_intensity})
	_pm["fire_core"] = _make_pm()
	_fire_core = VfxLib.make_particles(10, 0.5, _pm["fire_core"], quad, fire_m)
	_fire_core.explosiveness = 1.0
	_fire_core.name = "FireCore"
	add_child(_fire_core)

	_pm["fire_body"] = _make_pm()
	_fire_body = VfxLib.make_particles(30, 1.2, _pm["fire_body"], quad, VfxLib.fire_mat({"intensity": fire_intensity * 0.8, "tex_scale": 0.5, "rise": 0.9}))
	_fire_body.explosiveness = 0.85
	_fire_body.randomness = 0.35
	_fire_body.name = "FireBody"
	add_child(_fire_body)

	# --- Rauch -------------------------------------------------------------
	_pm["smoke_col"] = _make_pm()
	var sc := Vector3(smoke_color.r, smoke_color.g, smoke_color.b)
	_smoke_col = VfxLib.make_particles(44, 8.0, _pm["smoke_col"], quad, VfxLib.smoke_mat({"smoke_color": sc, "smoke_color_end": Vector3(0.24, 0.235, 0.23), "color_shift": 1.1,
		"glow": 2.6, "glow_decay": 3.0, "density": smoke_density * 1.0, "erosion": 0.4, "frame_span": 8.0, "soft_dist": 1.0}, true))
	_smoke_col.explosiveness = 0.7
	_smoke_col.randomness = 0.3
	_smoke_col.name = "SmokeColumn"
	_smoke_glow.append([_smoke_col.material_override, 2.6])
	add_child(_smoke_col)

	_pm["smoke_cap"] = _make_pm()
	_smoke_cap = VfxLib.make_particles(38, 7.0, _pm["smoke_cap"], quad, VfxLib.smoke_mat({"smoke_color": sc * 1.15, "smoke_color_end": Vector3(0.27, 0.265, 0.26), "color_shift": 1.0,
		"glow": 1.2, "glow_decay": 3.0, "density": smoke_density * 0.95, "erosion": 0.4, "frame_span": 8.0, "soft_dist": 1.0}, true))
	_smoke_cap.explosiveness = 0.9
	_smoke_cap.randomness = 0.3
	_smoke_cap.name = "SmokeCap"
	_smoke_glow.append([_smoke_cap.material_override, 1.2])
	add_child(_smoke_cap)

	_pm["smoke_low"] = _make_pm()
	_smoke_low = VfxLib.make_particles(26, 10.0, _pm["smoke_low"], quad, VfxLib.smoke_mat({"smoke_color": Vector3(0.07, 0.065, 0.06), "smoke_color_end": Vector3(0.3, 0.29, 0.27), "color_shift": 0.9,
		"glow": 1.6, "glow_decay": 3.0, "density": 0.85 * smoke_density, "erosion": 0.35, "frame_span": 9.0, "soft_dist": 1.2}, true))
	_smoke_low.explosiveness = 0.6
	_smoke_low.randomness = 0.4
	_smoke_low.name = "SmokeLow"
	_smoke_glow.append([_smoke_low.material_override, 1.6])
	add_child(_smoke_low)

	# --- Staubring ---------------------------------------------------------
	_pm["dust"] = _make_pm()
	_dust = VfxLib.make_particles(30, 4.0, _pm["dust"], quad, VfxLib.smoke_mat({"smoke_color": Vector3(0.3, 0.27, 0.23), "smoke_color_end": Vector3(0.4, 0.37, 0.33), "density": 0.75, "glow": 0.0,
		"soft_dist": 0.6, "erosion": 0.45, "frame_span": 5.0, "self_shadow": 0.35}, true))
	_dust.name = "DustRing"
	add_child(_dust)

	# --- Funken ------------------------------------------------------------
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.025, 0.28, 0.025)
	_pm["sparks"] = _make_pm()
	_sparks = VfxLib.make_particles(80, 1.8, _pm["sparks"], spark_mesh, VfxLib.shader_mat("spark", {"intensity": 5.0}))
	_sparks.randomness = 0.5
	_sparks.name = "Sparks"
	add_child(_sparks)

	var ember_mesh := BoxMesh.new()
	ember_mesh.size = Vector3(0.09, 0.09, 0.09)
	_pm["embers"] = _make_pm()
	_embers = VfxLib.make_particles(24, 2.4, _pm["embers"], ember_mesh, VfxLib.shader_mat("spark", {"intensity": 2.2}))
	_embers.randomness = 0.4
	_embers.name = "GlowingDebris"
	add_child(_embers)

	_configure_static()

func _make_pm() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	return pm

# Einmalige Einstellungen, die nicht von der Skalierung abhaengen.
func _configure_static() -> void:
	# Feuerkern
	var pm: ParticleProcessMaterial = _pm["fire_core"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -60.0
	pm.angular_velocity_max = 60.0
	pm.scale_curve = VfxLib.curve_tex([[0.0, 0.35], [0.25, 1.0], [1.0, 0.8]])
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1, 1, 1, 1)], [0.6, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0.0)]])

	pm = _pm["fire_body"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -35.0
	pm.angular_velocity_max = 35.0
	pm.scale_curve = VfxLib.curve_tex([[0.0, 0.3], [0.3, 1.0], [1.0, 0.75]])
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1, 1, 1, 0.0)], [0.08, Color(1, 1, 1, 1)], [0.7, Color(1, 1, 1, 0.85)], [1.0, Color(1, 1, 1, 0.0)]])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.turbulence_noise_scale = 2.0
	pm.turbulence_noise_speed_random = 0.4

	pm = _pm["smoke_col"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.direction = Vector3.UP
	pm.spread = 24.0
	VfxLib.smoke_pm(pm, 12.0)
	pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.3], [0.25, 0.85], [1.0, 1.5]])
	pm.color_ramp = VfxLib.smoke_alpha_ramp(1.0, 0.05, 0.45)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.7
	pm.turbulence_noise_scale = 1.2
	pm.turbulence_noise_speed = Vector3(0.0, 0.15, 0.0)

	pm = _pm["smoke_cap"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.flatness = 0.65
	VfxLib.smoke_pm(pm, 12.0)
	pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.35], [0.3, 0.9], [1.0, 1.45]])
	pm.color_ramp = VfxLib.smoke_alpha_ramp(1.0, 0.08, 0.45)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.8
	pm.turbulence_noise_scale = 1.4

	pm = _pm["smoke_low"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.flatness = 0.8
	VfxLib.smoke_pm(pm, 12.0)
	pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.4], [0.35, 0.95], [1.0, 1.6]])
	pm.color_ramp = VfxLib.smoke_alpha_ramp(0.9, 0.1, 0.5)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 1.0

	pm = _pm["dust"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_height = 0.2
	pm.direction = Vector3.UP
	pm.spread = 0.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	pm.gravity = Vector3.ZERO
	VfxLib.smoke_pm(pm, 12.0)
	pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.35], [0.3, 0.9], [1.0, 1.5]])
	pm.color_ramp = VfxLib.smoke_alpha_ramp(0.9, 0.06, 0.35)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 1.5

	pm = _pm["sparks"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.direction = Vector3.UP
	pm.spread = 160.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.particle_flag_align_y = true
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1.0, 0.95, 0.7, 1)], [0.25, Color(1.0, 0.6, 0.15, 1)], [0.7, Color(0.9, 0.2, 0.04, 0.8)], [1.0, Color(0.5, 0.05, 0.0, 0.0)]])
	pm.scale_curve = VfxLib.curve_tex([[0.0, 1.0], [0.8, 0.8], [1.0, 0.2]])
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.35
	pm.collision_friction = 0.35

	pm = _pm["embers"]
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.direction = Vector3.UP
	pm.spread = 120.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -400.0
	pm.angular_velocity_max = 400.0
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1.0, 0.7, 0.3, 1)], [0.3, Color(1.0, 0.3, 0.06, 1)], [0.75, Color(0.4, 0.08, 0.02, 0.7)], [1.0, Color(0.1, 0.02, 0.0, 0.0)]])
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_bounce = 0.3
	pm.collision_friction = 0.5

# Skalierungsabhaengige Werte.
func _configure(s: float) -> void:
	_s = s
	var aabb := AABB(Vector3(-30, -8, -30) * s, Vector3(60, 90, 60) * s)
	for p: GPUParticles3D in [_fire_core, _fire_body, _smoke_col, _smoke_cap, _smoke_low, _dust, _sparks, _embers]:
		p.visibility_aabb = aabb

	var pm: ParticleProcessMaterial = _pm["fire_core"]
	pm.emission_sphere_radius = 0.5 * s
	pm.initial_velocity_min = 2.0 * s
	pm.initial_velocity_max = 7.0 * s
	pm.damping_min = 4.0
	pm.damping_max = 6.0
	pm.gravity = Vector3(0, 1.5 * s, 0)
	pm.scale_min = 2.4 * s
	pm.scale_max = 3.6 * s

	pm = _pm["fire_body"]
	pm.emission_sphere_radius = 0.9 * s
	pm.initial_velocity_min = 3.0 * s
	pm.initial_velocity_max = 11.0 * s
	pm.damping_min = 2.5
	pm.damping_max = 4.5
	pm.gravity = Vector3(0, 2.6 * s, 0)
	pm.scale_min = 2.4 * s
	pm.scale_max = 4.4 * s

	pm = _pm["smoke_col"]
	pm.emission_sphere_radius = 0.9 * s
	pm.initial_velocity_min = 5.0 * s
	pm.initial_velocity_max = 14.0 * s
	pm.damping_min = 1.0
	pm.damping_max = 1.7
	pm.gravity = Vector3(0, 0.6 * s, 0) + VfxLib.WIND * 0.5
	pm.scale_min = 4.0 * s
	pm.scale_max = 6.6 * s

	pm = _pm["smoke_cap"]
	pm.emission_sphere_radius = 1.0 * s
	pm.initial_velocity_min = 3.5 * s
	pm.initial_velocity_max = 10.0 * s
	pm.damping_min = 1.3
	pm.damping_max = 2.0
	pm.gravity = Vector3(0, 0.55 * s, 0) + VfxLib.WIND * 0.6
	pm.scale_min = 4.4 * s
	pm.scale_max = 7.2 * s

	pm = _pm["smoke_low"]
	pm.emission_sphere_radius = 1.4 * s
	pm.initial_velocity_min = 1.5 * s
	pm.initial_velocity_max = 6.5 * s
	pm.damping_min = 0.8
	pm.damping_max = 1.4
	pm.gravity = Vector3(0, 0.25 * s, 0) + VfxLib.WIND * 0.4
	pm.scale_min = 4.0 * s
	pm.scale_max = 6.4 * s

	pm = _pm["dust"]
	pm.emission_ring_radius = 0.6 * s
	pm.emission_ring_inner_radius = 0.0
	pm.radial_velocity_min = 5.0 * s
	pm.radial_velocity_max = 11.0 * s
	pm.damping_min = 2.2
	pm.damping_max = 3.2
	pm.scale_min = 2.4 * s
	pm.scale_max = 3.8 * s

	pm = _pm["sparks"]
	pm.emission_sphere_radius = 0.3 * s
	pm.initial_velocity_min = 7.0 * s
	pm.initial_velocity_max = 26.0 * s
	pm.damping_min = 0.2
	pm.damping_max = 0.9
	pm.scale_min = 0.5 * sqrt(s)
	pm.scale_max = 1.3 * sqrt(s)
	pm.turbulence_enabled = false

	pm = _pm["embers"]
	pm.emission_sphere_radius = 0.4 * s
	pm.initial_velocity_min = 5.0 * s
	pm.initial_velocity_max = 17.0 * s
	pm.damping_min = 0.1
	pm.damping_max = 0.5
	pm.scale_min = 0.5 * sqrt(s)
	pm.scale_max = 1.5 * sqrt(s)

	_light.omni_range = light_range * s
	_flash.scale = Vector3.ONE * 9.0 * s

## Startet die Explosion an `pos` (Weltkoordinaten) mit Skalierung `s`.
func play(pos: Vector3, s: float = 1.0) -> void:
	_build()
	if _tween and _tween.is_valid():
		_tween.kill()
	_busy = true
	s = maxf(s, 0.1)
	_configure(s)
	global_position = pos
	global_rotation = Vector3.ZERO
	visible = true
	_probe_ground(pos, s)

	# Bodenebene: Ring/Low-Smoke am Boden, falls Boden nah
	var ground_offset := 0.0
	if _has_ground:
		ground_offset = _ground_y - pos.y
	_dust.position = Vector3(0, minf(ground_offset, 0.0) + 0.25, 0)
	_dust.visible = _has_ground
	_smoke_low.position = Vector3(0, minf(ground_offset, 0.0) + 0.5 * s, 0)
	_smoke_cap.position = Vector3(0, 5.0 * s, 0)
	_smoke_col.position = Vector3(0, 0.3 * s, 0)
	_fire_core.position = Vector3(0, 0.3 * s, 0)
	_fire_body.position = Vector3(0, 0.5 * s, 0)

	# t = 0: Blitz, Feuer, Funken, Truemmer, Licht, Schockwelle, Staub
	_flash_mat.set_shader_parameter("seed", randf() * 6.28)
	_flash_mat.set_shader_parameter("fade", 1.0)
	_flash.visible = true
	_flash.scale = Vector3.ONE * 6.0 * s
	var tf := create_tween().set_parallel(true)
	tf.tween_property(_flash, "scale", Vector3.ONE * 11.0 * s, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tf.tween_property(_flash_mat, "shader_parameter/fade", 0.0, 0.14).set_ease(Tween.EASE_IN)
	tf.chain().tween_callback(func() -> void: _flash.visible = false)

	_light.visible = true
	_light.light_energy = 0.0
	_light.light_color = Color(1.0, 0.75, 0.42)
	_light.shadow_enabled = shadows
	var peak := light_peak_energy * (0.6 + 0.4 * minf(s, 3.0))
	var tl := create_tween()
	tl.tween_property(_light, "light_energy", peak, 0.03)
	tl.tween_property(_light, "light_energy", peak * 0.28, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tl.parallel().tween_property(_light, "light_color", Color(1.0, 0.42, 0.12), 0.35)
	tl.tween_property(_light, "light_energy", 0.0, 1.8).set_ease(Tween.EASE_IN)
	tl.tween_callback(func() -> void: _light.visible = false)

	_shock.visible = true
	_shock.scale = Vector3.ONE * 0.4 * s
	_shock_mat.set_shader_parameter("progress", 0.0)
	_shock_mat.set_shader_parameter("strength", 0.1)
	var ts := create_tween().set_parallel(true)
	ts.tween_property(_shock, "scale", Vector3.ONE * 9.0 * s, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	ts.tween_property(_shock_mat, "shader_parameter/progress", 1.0, 0.5)
	ts.chain().tween_callback(func() -> void: _shock.visible = false)

	var tg := create_tween().set_parallel(true)
	for e in _smoke_glow:
		var m: ShaderMaterial = e[0]
		m.set_shader_parameter("glow", e[1])
		tg.tween_property(m, "shader_parameter/glow", 0.0, 1.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	_fire_core.restart()
	_fire_body.restart()
	_sparks.restart()
	_embers.restart()
	if _has_ground:
		_dust.restart()
	_smoke_col.emitting = false
	_smoke_cap.emitting = false
	_smoke_low.emitting = false

	# gestaffelt: Rauch ab ~0.06 s, Pilzkappe ab ~0.35 s
	_tween = create_tween()
	_tween.tween_interval(0.06)
	_tween.tween_callback(func() -> void:
		_smoke_col.restart()
		_smoke_low.restart())
	_tween.tween_interval(0.3)
	_tween.tween_callback(func() -> void: _smoke_cap.restart())
	_tween.tween_interval(maxf(duration - 0.4, 1.0))
	_tween.tween_callback(_finish)

	_spawn_debris(pos, s)
	if _has_ground:
		VFX.spawn_scorch(Vector3(pos.x, _ground_y + 0.02, pos.z), Vector3.UP, 7.5 * s, 40.0)

func _finish() -> void:
	_busy = false
	visible = false
	_light.visible = false
	finished.emit(self)

func _probe_ground(pos: Vector3, s: float) -> void:
	_has_ground = false
	var world := get_world_3d()
	if world == null:
		return
	var space := world.direct_space_state
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * (6.0 * s + 1.5), 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		# Fallback: Ebene y = 0, wenn nahe genug
		if absf(pos.y) < 6.0 * s:
			_ground_y = 0.0
			_has_ground = true
		return
	_ground_y = (hit["position"] as Vector3).y
	_has_ground = true

func _spawn_debris(pos: Vector3, s: float) -> void:
	var n := int(round(debris_count * clampf(s, 0.6, 2.5)))
	for i in n:
		var d := RigidBody3D.new()
		d.collision_layer = 8
		d.collision_mask = 1
		d.mass = 3.0 * s
		d.continuous_cd = true
		var size := Vector3(randf_range(0.18, 0.5), randf_range(0.12, 0.35), randf_range(0.18, 0.45)) * sqrt(s)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		d.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = VFX.debris_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		d.add_child(mi)
		if not VFX.add_debris(d):
			return
		d.global_position = pos + Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 0.9), randf_range(-0.6, 0.6)) * s
		d.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.5, 1.6), randf_range(-1, 1)).normalized()
		d.linear_velocity = dir * randf_range(6.0, 16.0) * sqrt(s)
		d.angular_velocity = Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9))
		VFX.schedule_free(d, randf_range(5.0, 8.0))
