extends Node3D
## Feuerwerk fuer die Siegesfeier: Raketen mit Leuchtspur, Sternbuersten (GPUParticles, Pool), Lichtblitz.
## launch() feuert eine Rakete von -> nach, burst() zuendet direkt (auch tief/chaotisch nach der Explosion).

const POOL := 8

var _pool: Array[GPUParticles3D] = []
var _next: int = 0
var _spark_mesh: QuadMesh
var _rocket_mat: StandardMaterial3D

func _ready() -> void:
	_spark_mesh = QuadMesh.new()
	_spark_mesh.size = Vector2(0.22, 0.22)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.vertex_color_use_as_albedo = true
	sm.albedo_texture = _dot_tex()
	sm.disable_receive_shadows = true
	_spark_mesh.material = sm
	_rocket_mat = StandardMaterial3D.new()
	_rocket_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rocket_mat.albedo_color = Color(3.0, 2.2, 1.2)
	for i in POOL:
		var p := GPUParticles3D.new()
		p.amount = 160
		p.lifetime = 2.4
		p.one_shot = true
		p.explosiveness = 0.96
		p.emitting = false
		p.local_coords = false
		p.draw_pass_1 = _spark_mesh
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
		p.process_material = _burst_material(Color.WHITE)
		add_child(p)
		_pool.append(p)

func _dot_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.9))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 32
	t.height = 32
	return t

func _burst_material(c: Color) -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.3
	m.direction = Vector3(0, 1, 0)
	m.spread = 180.0
	m.initial_velocity_min = 9.0
	m.initial_velocity_max = 14.0
	m.gravity = Vector3(0, -3.5, 0)
	m.damping_min = 2.5
	m.damping_max = 4.0
	m.scale_min = 0.7
	m.scale_max = 1.3
	var g := Gradient.new()
	g.set_color(0, Color(4.0, 4.0, 3.6, 1.0))
	g.add_point(0.12, Color(c.r * 4.0, c.g * 4.0, c.b * 4.0, 1.0))
	g.set_color(g.get_point_count() - 1, Color(c.r * 1.5, c.g * 0.8, c.b * 0.4, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	return m

## Rakete von from nach to (Flugzeit t), dann Buerste in color.
func launch(from: Vector3, to: Vector3, color: Color, t: float = 1.3) -> void:
	VFX.play_sfx_3d("berlin_firework_launch", from, -4.0, 8.0, 140.0)
	var r := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	r.mesh = sm
	r.material_override = _rocket_mat
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(r)
	r.global_position = from
	var trail := GPUParticles3D.new()
	trail.amount = 40
	trail.lifetime = 0.6
	trail.local_coords = false
	trail.draw_pass_1 = _spark_mesh
	var tm := ParticleProcessMaterial.new()
	tm.direction = Vector3(0, -1, 0)
	tm.spread = 20.0
	tm.initial_velocity_min = 0.5
	tm.initial_velocity_max = 1.5
	tm.gravity = Vector3(0, -1.0, 0)
	tm.scale_min = 0.4
	tm.scale_max = 0.7
	var g := Gradient.new()
	g.set_color(0, Color(3.0, 2.0, 1.0, 1.0))
	g.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	tm.color_ramp = gt
	trail.process_material = tm
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	r.add_child(trail)
	var tw := r.create_tween()
	tw.tween_property(r, "global_position", to, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		burst(r.global_position, color)
		trail.emitting = false
		r.material_override = null
		r.visible = false)
	tw.tween_interval(0.8)
	tw.tween_callback(r.queue_free)

## Sternbuerste mit Lichtblitz.
func burst(pos: Vector3, color: Color, scale_k: float = 1.0) -> void:
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	var pm := p.process_material as ParticleProcessMaterial
	var g := (pm.color_ramp as GradientTexture1D).gradient
	g.set_color(1, Color(color.r * 4.0, color.g * 4.0, color.b * 4.0, 1.0))
	g.set_color(g.get_point_count() - 1, Color(color.r * 1.5, color.g * 0.8, color.b * 0.4, 0.0))
	pm.initial_velocity_min = 9.0 * scale_k
	pm.initial_velocity_max = 14.0 * scale_k
	p.global_position = pos
	p.restart()
	p.emitting = true
	VFX.play_sfx_3d("berlin_firework_burst", pos, 0.0, 22.0, 260.0)
	var l := OmniLight3D.new()
	l.light_color = color.lerp(Color.WHITE, 0.3)
	l.light_energy = 14.0 * scale_k
	l.omni_range = 45.0 * scale_k
	l.light_volumetric_fog_energy = 2.0
	add_child(l)
	l.global_position = pos
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_callback(l.queue_free)
