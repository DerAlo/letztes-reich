extends Node3D
## Effekte fuer "Letzter Zug": Staubflocken im Gegenlicht, Feuerbaelle, Feuerwand + riesige Rauchsaeule
## der Kettenexplosion, Funkenregen, Panzerfaust-Rakete, Leuchtkugeln (Finale) und Ersatz-Jets mit
## Bombenkette, falls game/vehicles/jet_flyby.tscn fehlt.

const VfxLib = preload("res://game/vfx/vfx_lib.gd")
const Props = preload("res://game/levels/level_props.gd")

var _motes: GPUParticles3D
var _fire_lights: int = 0
var _flares: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 4242
	_build_motes()

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null and _motes != null:
		_motes.global_position = cam.global_position
	_update_flares(delta)

# ---------------------------------------------------------------- Staub im Licht

func _build_motes() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 5, 14)
	pm.direction = Vector3(1, 0.1, 0.4)
	pm.spread = 60.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.gravity = Vector3(0.08, 0.01, 0.03)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1, 1, 1, 0)], [0.2, Color(1, 1, 1, 1)], [0.8, Color(1, 1, 1, 1)], [1.0, Color(1, 1, 1, 0)]])
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.03, 0.03)
	# Beleuchtet statt unshaded: Staub glitzert nur im (Gegen-)Sonnenlicht (Backlight), im Schatten und in
	# den Hallen bleibt er unsichtbar. Runde weiche Flocke und Ausblenden nah an der Kamera – vorher
	# erschien eine Flocke direkt vor der Linse als helles Quadrat.
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 0.78, 0.5, 0.55)
	m.roughness = 1.0
	m.backlight_enabled = true
	m.backlight = Color(1.0, 0.78, 0.5)
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	m.distance_fade_min_distance = 0.8
	m.distance_fade_max_distance = 3.0
	var dot := GradientTexture2D.new()
	dot.width = 32
	dot.height = 32
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	var dg := Gradient.new()
	dg.set_color(0, Color(1, 1, 1, 1))
	dg.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = dg
	m.albedo_texture = dot
	mesh.material = m
	_motes = GPUParticles3D.new()
	_motes.name = "DustMotes"
	_motes.amount = 260
	_motes.lifetime = 7.0
	_motes.preprocess = 7.0
	_motes.local_coords = false
	_motes.process_material = pm
	_motes.draw_pass_1 = mesh
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visibility_aabb = AABB(Vector3(-20, -8, -20), Vector3(40, 16, 40))
	add_child(_motes)

# ---------------------------------------------------------------- Feuerball / Funken

## Aufsteigender, sich aufblaehender Feuerball mit kurzem Blitzlicht (ergaenzt die Pool-Explosion).
func fireball(pos: Vector3, scale: float) -> void:
	var s := scale
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2 * s
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 3.0 * s
	pm.initial_velocity_max = 9.0 * s
	pm.gravity = Vector3(0, 2.5 * s, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.scale_min = 3.0 * s
	pm.scale_max = 5.5 * s
	pm.scale_curve = VfxLib.curve_tex([[0.0, 0.4], [0.3, 1.0], [1.0, 1.4]])
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1, 1, 1, 1)], [0.55, Color(1, 0.8, 0.6, 0.85)], [1.0, Color(0.3, 0.2, 0.15, 0.0)]])
	var p := VfxLib.make_particles(int(18 + 8 * s), 1.6, pm, VfxLib.quad(1.0), VfxLib.fire_mat({"intensity": 2.6, "tex_scale": 0.5, "rise": 1.6, "core_heat": 2.0}))
	p.visibility_aabb = AABB(Vector3(-25, -5, -25) * s, Vector3(50, 60, 50) * s)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 14.0 * s
	l.omni_range = 26.0 * s
	l.omni_attenuation = 1.4
	l.light_volumetric_fog_energy = 2.0
	l.shadow_enabled = false
	add_child(l)
	l.global_position = pos + Vector3(0, 2, 0)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, 1.4).set_ease(Tween.EASE_IN)
	tw.tween_callback(l.queue_free)
	VFX.schedule_free(p, 3.0)
	spark_burst(pos, int(30 * s))

func spark_burst(pos: Vector3, amount: int = 40) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = 8.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1.0, 0.85, 0.5, 1)], [0.6, Color(1.0, 0.4, 0.08, 1)], [1.0, Color(0.4, 0.05, 0.0, 0.0)]])
	var em := BoxMesh.new()
	em.size = Vector3(0.05, 0.05, 0.05)
	var p := VfxLib.make_particles(amount, 2.2, pm, em, VfxLib.shader_mat("spark", {"intensity": 6.0}))
	add_child(p)
	p.global_position = pos
	p.emitting = true
	VFX.schedule_free(p, 3.0)

# ---------------------------------------------------------------- Brennende Wagen

## Feuer am zerstoerten Wagen. Nur wenige Lichter (max. 4), primaer = riesige Rauchsaeule.
func wagon_burn(center: Vector3, kind: String, primary: bool, i: int) -> void:
	var size := 2.6 if primary else (2.0 if kind == "tank" else 1.5)
	var light := _fire_lights < 4 and (primary or i % 2 == 0)
	if light:
		_fire_lights += 1
	var f := Props.fire(self, center + Vector3(0, 0.4, 0), size, light, 1.6, 9.0 if primary else 6.0)
	if f != null:
		f.set("light_range", 18.0)
	# zweites Feuer seitlich versetzt -> durchgehende Feuerwand entlang des Gleises
	if kind != "loco":
		Props.fire(self, center + Vector3(-1.5, 0.2, _rng.randf_range(4.0, 5.5)), size * 0.7, false, 0.9)
		Props.fire(self, center + Vector3(-2.5, 0.2, -_rng.randf_range(3.0, 5.0)), size * 0.6, false, 0.7)
	if primary:
		smoke_column(center + Vector3(0, 3.0, 0))

## Riesige, dauerhafte Rauchsaeule (schwarz, unten von der Glut angestrahlt), driftet mit dem Wind.
func smoke_column(pos: Vector3) -> void:
	var sp := VfxLib.smoke_pm(ParticleProcessMaterial.new(), 6.0)
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 3.5
	sp.direction = Vector3.UP
	sp.spread = 10.0
	sp.initial_velocity_min = 7.0
	sp.initial_velocity_max = 11.0
	sp.gravity = Vector3(0, 0.6, 0) + VfxLib.WIND * 1.6
	sp.damping_min = 0.15
	sp.damping_max = 0.3
	sp.scale_min = 7.0
	sp.scale_max = 11.0
	sp.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.35], [0.2, 0.8], [1.0, 2.6]])
	sp.color_ramp = VfxLib.smoke_alpha_ramp(1.0, 0.06, 0.65)
	sp.turbulence_enabled = true
	sp.turbulence_noise_strength = 0.3
	sp.turbulence_noise_scale = 9.0
	sp.turbulence_noise_speed = Vector3(0, 0.2, 0)
	sp.turbulence_influence_min = 0.02
	sp.turbulence_influence_max = 0.06
	var mat := VfxLib.smoke_mat({
		"smoke_color": Color(0.03, 0.028, 0.026),
		"smoke_color_end": Color(0.2, 0.17, 0.15),
		"color_shift": 1.2,
		"density": 2.0,
		"erosion": 0.2,
		"frame_span": 6.0,
		"soft_dist": 3.0,
		"glow": 1.2,
		"glow_height": 6.0,
		"glow_color": Color(1.0, 0.42, 0.12),
		"glow_origin_y": pos.y - 2.0,
	})
	var p := VfxLib.make_particles(130, 20.0, sp, VfxLib.quad(1.0), mat)
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.3
	p.visibility_aabb = AABB(Vector3(-80, -5, -80), Vector3(160, 200, 160))
	p.name = "SmokeColumn"
	add_child(p)
	p.global_position = pos
	p.emitting = true
	# Initialer Pilz: dichte, schnell aufsteigende Wolke
	var mp := sp.duplicate() as ParticleProcessMaterial
	mp.initial_velocity_min = 14.0
	mp.initial_velocity_max = 22.0
	mp.spread = 25.0
	mp.damping_min = 1.0
	mp.damping_max = 1.6
	mp.scale_min = 9.0
	mp.scale_max = 14.0
	var mush := VfxLib.make_particles(26, 14.0, mp, VfxLib.quad(1.0), mat)
	mush.visibility_aabb = p.visibility_aabb
	add_child(mush)
	mush.global_position = pos
	mush.emitting = true
	VFX.schedule_free(mush, 15.0)

# ---------------------------------------------------------------- Rakete

## Panzerfaust-/Raketengeschoss mit Rauchfahne von from nach to, danach callback.
func rocket(from: Vector3, to: Vector3, time: float, callback: Callable) -> void:
	var r := Node3D.new()
	r.name = "Rocket"
	add_child(r)
	r.global_position = from
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.06
	cm.height = 0.7
	body.mesh = cm
	body.rotation_degrees.x = 90.0
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.2, 0.22, 0.18)
	body.material_override = bm
	r.add_child(body)
	var glow := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.12
	gs.height = 0.24
	glow.mesh = gs
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.7, 0.3)
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.6, 0.2)
	gm.emission_energy_multiplier = 16.0
	glow.material_override = gm
	glow.position = Vector3(0, 0, 0.4)
	r.add_child(glow)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 4.0
	l.omni_range = 7.0
	l.position = Vector3(0, 0, 0.5)
	r.add_child(l)
	# Rauchfahne in Weltkoordinaten
	var sp := VfxLib.smoke_pm(ParticleProcessMaterial.new(), 20.0)
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	sp.direction = Vector3.UP
	sp.spread = 180.0
	sp.initial_velocity_min = 0.1
	sp.initial_velocity_max = 0.5
	sp.gravity = Vector3(0, 0.3, 0) + VfxLib.WIND * 0.4
	sp.scale_min = 0.5
	sp.scale_max = 0.9
	sp.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.5], [1.0, 3.0]])
	sp.color_ramp = VfxLib.smoke_alpha_ramp(0.8, 0.05, 0.4)
	var trail := VfxLib.make_particles(70, 3.5, sp, VfxLib.quad(1.0), VfxLib.smoke_mat({
		"smoke_color": Color(0.5, 0.48, 0.45), "smoke_color_end": Color(0.7, 0.66, 0.6), "density": 1.4, "soft_dist": 0.4}, true))
	trail.one_shot = false
	trail.explosiveness = 0.0
	trail.emitting = true
	trail.visibility_aabb = AABB(Vector3(-100, -20, -100), Vector3(200, 60, 200))
	r.add_child(trail)
	var up := Vector3.UP
	var d := (to - from).normalized()
	if absf(d.dot(up)) > 0.95:
		up = Vector3.RIGHT
	r.global_basis = Basis.looking_at(d, up)
	VFX.play_sfx_3d("grenade_throw", from, 4.0, 10.0, 120.0)
	var tw := r.create_tween()
	tw.tween_property(r, "global_position", to, time)
	tw.tween_callback(func() -> void:
		trail.emitting = false
		trail.reparent(self)
		VFX.schedule_free(trail, 4.0)
		r.queue_free()
		if callback.is_valid():
			callback.call())

# ---------------------------------------------------------------- Leuchtkugeln (Finale)

## Steigt von pos auf (Signalpistole), haengt dann leuchtend am Fallschirm und sinkt langsam.
func signal_flare(pos: Vector3, col: Color, height: float = 55.0) -> void:
	var root := Node3D.new()
	root.name = "SignalFlare"
	add_child(root)
	root.global_position = pos
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.0
	light.light_volumetric_fog_energy = 1.2
	light.omni_range = 70.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	root.add_child(light)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	sm.radial_segments = 8
	sm.rings = 4
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = col
	cm.emission_enabled = true
	cm.emission = col
	cm.emission_energy_multiplier = 18.0
	core.material_override = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var trail := Props.fire(root, Vector3.ZERO, 0.25, false, 0.4)
	if trail != null:
		trail.set("embers_enabled", true)
	VFX.play_sfx_3d("rail_flare_launch", pos, 2.0, 15.0, 400.0)
	var top := pos + Vector3(_rng.randf_range(-6, 6), height, _rng.randf_range(-6, 6))
	var tw := root.create_tween()
	tw.tween_property(root, "global_position", top, 2.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(light, "light_energy", 9.0, 1.6)
	tw.tween_callback(func() -> void:
		_flares.append({"node": root, "light": light, "age": 0.0, "life": _rng.randf_range(16.0, 22.0),
			"drift": Vector3(VfxLib.WIND.x * 1.2, -_rng.randf_range(1.0, 1.5), VfxLib.WIND.z), "seed": _rng.randf() * 50.0}))

func _update_flares(delta: float) -> void:
	for i in range(_flares.size() - 1, -1, -1):
		var f: Dictionary = _flares[i]
		var n: Node3D = f["node"]
		if not is_instance_valid(n):
			_flares.remove_at(i)
			continue
		f["age"] = float(f["age"]) + delta
		var age: float = f["age"]
		var life: float = f["life"]
		n.global_position += (f["drift"] as Vector3) * delta
		var l: OmniLight3D = f["light"]
		var fl := 0.85 + 0.15 * sin(age * 23.0 + float(f["seed"])) * sin(age * 7.0)
		l.light_energy = 9.0 * fl * clampf((life - age) / 3.0, 0.0, 1.0)
		if age >= life:
			n.queue_free()
			_flares.remove_at(i)

# ---------------------------------------------------------------- Ersatz-Jets

## Ersatz, falls JetFlyby fehlt: zwei dunkle Silhouetten mit Nachbrenner + Bombenkette per Combat.explode.
func fallback_jets(from: Vector3, to: Vector3, targets: Array[Vector3]) -> void:
	for j in 2:
		var jet := _jet_silhouette()
		add_child(jet)
		var off := Vector3(j * 18.0, j * 6.0, j * 25.0)
		jet.global_position = from + off
		var d := (to - from).normalized()
		jet.global_basis = Basis.looking_at(d, Vector3.UP)
		var tw := jet.create_tween()
		tw.tween_property(jet, "global_position", to + off, 3.2)
		tw.tween_callback(jet.queue_free)
	VFX.play_sfx_3d("drone_dive", from.lerp(to, 0.5), 10.0, 120.0, 2000.0)
	var delay := 1.1
	for t in targets:
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			Combat.explode(t, 9.0, 140.0, null, 3.2))
		delay += 0.35

func _jet_silhouette() -> Node3D:
	var root := Node3D.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.27, 0.3)
	m.metallic = 0.5
	m.roughness = 0.5
	var parts := [[Vector3(0, 0, 0), Vector3(1.4, 1.3, 15.0)], [Vector3(0, 0, 1.0), Vector3(11.0, 0.18, 4.5)],
		[Vector3(0, 1.4, 6.0), Vector3(0.2, 2.6, 2.4)], [Vector3(0, 0, 6.5), Vector3(5.0, 0.15, 2.0)]]
	for p: Array in parts:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = p[1]
		mi.mesh = bm
		mi.material_override = m
		mi.position = p[0]
		root.add_child(mi)
	var flame := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.55
	fm.bottom_radius = 0.1
	fm.height = 3.5
	flame.mesh = fm
	flame.rotation_degrees.x = 90.0
	flame.position = Vector3(0, 0, 9.2)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(1.0, 0.6, 0.3)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.5, 0.2)
	em.emission_energy_multiplier = 10.0
	flame.material_override = em
	root.add_child(flame)
	return root
