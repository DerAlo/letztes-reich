extends Node3D
## Nacht-Effekte fuer "baltic_night": Schneetreiben (folgt der Kamera), Fallschirm-Leuchtkugeln,
## Suchscheinwerfer, ferne Leuchtspur-Salven, ferner Artilleriebeschuss, flackernde Feuerlichter.
## Wird vom Level als Kind angelegt; alle Werte als Exports einstellbar.

const Props = preload("res://game/levels/level_props.gd")

@export var snow_enabled: bool = true
@export var snow_amount: int = 9000
@export var wind: Vector3 = Vector3(2.2, 0.0, 0.9)
@export var flares_enabled: bool = true
@export var flare_interval_min: float = 7.0
@export var flare_interval_max: float = 12.0
@export var flare_max: int = 3
@export var flare_energy: float = 4.5
@export var flare_range: float = 80.0
@export var flare_height: float = 62.0
@export var tracers_enabled: bool = true
@export var artillery_enabled: bool = true
@export var artillery_interval_min: float = 6.0
@export var artillery_interval_max: float = 14.0
@export var end_z: float = -232.0

var rng := RandomNumberGenerator.new()
var _snow: Array[GPUParticles3D] = []
var _flares: Array[Dictionary] = []
var _search: Array[Dictionary] = []
var _flicker: Array[Dictionary] = []
var _tracer_pool: Array[MeshInstance3D] = []
var _tracer_mats: Array[StandardMaterial3D] = []
var _flare_t: float = 2.0
var _tracer_t: float = 1.0
var _art_t: float = 4.0
var _time: float = 0.0
var _last_cam: Vector3 = Vector3(0, 2, 0)

func _ready() -> void:
	rng.seed = 4711
	if snow_enabled:
		_build_snow()
	_build_tracer_pool()
	_art_t = rng.randf_range(3.0, 6.0)

# --------------------------------------------------------------------------- Schnee

func _flake_mat(alpha: float) -> StandardMaterial3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	var m := StandardMaterial3D.new()
	m.albedo_texture = gt
	m.albedo_color = Color(0.85, 0.9, 1.0, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.roughness = 1.0
	m.disable_receive_shadows = true
	return m

func _make_snow(amount: int, box: Vector3, flake: float, alpha: float, lifetime: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.fixed_fps = 0
	p.visibility_aabb = AABB(Vector3(-80, -60, -80), Vector3(160, 120, 160))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.collision_base_size = 0.02
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(wind.x, -1.6, wind.z)
	pm.damping_min = 0.4
	pm.damping_max = 0.8
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.6
	pm.turbulence_noise_scale = 2.6
	pm.turbulence_noise_speed = Vector3(0.3, 0.0, 0.2)
	pm.turbulence_influence_min = 0.08
	pm.turbulence_influence_max = 0.22
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color = Color(0.72, 0.75, 0.82, 1)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(flake, flake)
	q.material = _flake_mat(alpha)
	p.draw_pass_1 = q
	add_child(p)
	return p

func _build_snow() -> void:
	_snow.append(_make_snow(snow_amount, Vector3(34, 10, 34), 0.065, 0.85, 7.0))
	_snow.append(_make_snow(int(snow_amount * 0.35), Vector3(9, 5, 9), 0.032, 0.9, 3.5))

func _update_snow(cam: Vector3, delta: float) -> void:
	if _snow.is_empty():
		return
	var vel := (cam - _last_cam) / maxf(delta, 0.001)
	# Emitter laeuft der Kamera leicht voraus und gegen den Wind versetzt
	var ahead := Vector3(vel.x, 0, vel.z) * 0.8 - Vector3(wind.x, 0, wind.z) * 2.5
	_snow[0].global_position = cam + Vector3(0, 9.0, 0) + ahead
	if _snow.size() > 1:
		_snow[1].global_position = cam + Vector3(0, 4.0, 0) + ahead * 0.5

# --------------------------------------------------------------------------- Leuchtkugeln

func spawn_flare(pos: Vector3, red: bool = false) -> void:
	var root := Node3D.new()
	root.name = "Flare"
	add_child(root)
	root.global_position = pos
	var col := Color(1.0, 0.22, 0.12) if red else Color(1.0, 0.9, 0.72)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = flare_energy * (1.25 if red else 1.0)
	light.light_indirect_energy = 0.6
	light.light_volumetric_fog_energy = 0.7
	light.omni_range = flare_range
	light.omni_attenuation = 1.0
	light.shadow_enabled = true
	light.shadow_blur = 1.6
	light.shadow_bias = 0.06
	light.light_size = 0.2
	light.position = Vector3(0, -0.4, 0)
	root.add_child(light)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 8
	sm.rings = 4
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = col
	cm.emission_enabled = true
	cm.emission = col
	cm.emission_energy_multiplier = 12.0
	core.material_override = cm
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	# Fallschirm (flache Kuppel) + Leinen
	var chute := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.9
	dm.height = 0.7
	dm.is_hemisphere = true
	dm.radial_segments = 10
	dm.rings = 3
	chute.mesh = dm
	chute.material_override = Geo_flat(Color(0.5, 0.5, 0.46))
	chute.position = Vector3(0, 2.4, 0)
	chute.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(chute)
	# Rauchfahne: kleines Feuer ohne Licht, Partikel bleiben in Weltkoordinaten
	var trail := Props.fire(root, Vector3(0, -0.1, 0), 0.22, false, 0.25)
	if trail != null:
		trail.set("embers_enabled", true)
	_flares.append({"node": root, "light": light, "core": cm, "age": 0.0, "life": rng.randf_range(26.0, 34.0), "base": light.light_energy, "drift": Vector3(wind.x * 0.5 + rng.randf_range(-0.6, 0.6), -rng.randf_range(1.4, 1.9), wind.z * 0.4 + rng.randf_range(-0.4, 0.4)), "seed": rng.randf() * 100.0})

static func Geo_flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m

func _update_flares(cam: Vector3, delta: float) -> void:
	if flares_enabled:
		_flare_t -= delta
		if _flare_t <= 0.0:
			_flare_t = rng.randf_range(flare_interval_min, flare_interval_max)
			if _flares.size() < flare_max:
				var z := clampf(cam.z - rng.randf_range(25.0, 70.0), end_z - 30.0, 10.0)
				spawn_flare(Vector3(cam.x + rng.randf_range(-26.0, 26.0), flare_height + rng.randf_range(-6.0, 8.0), z), rng.randf() < 0.25)
	for i in range(_flares.size() - 1, -1, -1):
		var f: Dictionary = _flares[i]
		var node: Node3D = f["node"]
		f["age"] = float(f["age"]) + delta
		var age: float = f["age"]
		var life: float = f["life"]
		node.global_position += (f["drift"] as Vector3) * delta
		var s: float = f["seed"]
		var flick := 0.82 + 0.1 * sin(_time * 23.0 + s) + 0.08 * sin(_time * 41.0 + s * 2.0) + rng.randf_range(-0.05, 0.05)
		var fade := clampf(age / 0.8, 0.0, 1.0) * clampf((life - age) / 4.0, 0.0, 1.0)
		(f["light"] as OmniLight3D).light_energy = float(f["base"]) * flick * fade
		(f["core"] as StandardMaterial3D).emission_energy_multiplier = 30.0 * flick * fade
		if age >= life or node.global_position.y < 2.0:
			_flares.remove_at(i)
			node.queue_free()

# --------------------------------------------------------------------------- Suchscheinwerfer

## Suchscheinwerfer mit sichtbarem Lichtkegel im Volumen-Nebel. yaw/pitch in Grad, Schwenk +-sweep.
func add_searchlight(pos: Vector3, yaw_deg: float, pitch_deg: float, sweep_deg: float, speed: float, energy: float = 60.0) -> SpotLight3D:
	var pivot := Node3D.new()
	pivot.name = "Searchlight"
	add_child(pivot)
	pivot.global_position = pos
	var sl := SpotLight3D.new()
	sl.light_color = Color(0.85, 0.9, 1.0)
	sl.light_energy = energy
	sl.light_indirect_energy = 0.2
	sl.light_volumetric_fog_energy = 5.0
	sl.spot_range = 190.0
	sl.spot_angle = 3.6
	sl.spot_angle_attenuation = 0.6
	sl.spot_attenuation = 0.35
	sl.shadow_enabled = true
	sl.shadow_bias = 0.08
	pivot.add_child(sl)
	# Gehaeuse mit leuchtender Scheibe
	var housing := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.42
	cyl.bottom_radius = 0.5
	cyl.height = 0.7
	housing.mesh = cyl
	housing.rotation_degrees = Vector3(90, 0, 0)
	housing.position = Vector3(0, 0, 0.3)
	housing.material_override = Geo_flat(Color(0.12, 0.13, 0.12))
	sl.add_child(housing)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.4
	lm.bottom_radius = 0.4
	lm.height = 0.04
	lens.mesh = lm
	lens.rotation_degrees = Vector3(90, 0, 0)
	lens.position = Vector3(0, 0, -0.06)
	var em := StandardMaterial3D.new()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.albedo_color = Color(1, 1, 1)
	em.emission_enabled = true
	em.emission = Color(0.9, 0.95, 1.0)
	em.emission_energy_multiplier = 40.0
	lens.material_override = em
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sl.add_child(lens)
	_search.append({"pivot": pivot, "light": sl, "yaw": yaw_deg, "pitch": pitch_deg, "sweep": sweep_deg, "speed": speed, "phase": rng.randf() * TAU})
	_update_search_one(_search[_search.size() - 1])
	return sl

func _update_search_one(s: Dictionary) -> void:
	var t: float = _time * float(s["speed"]) + float(s["phase"])
	var yaw: float = float(s["yaw"]) + float(s["sweep"]) * sin(t)
	var pitch: float = float(s["pitch"]) + 2.5 * sin(t * 1.7 + 0.6)
	(s["pivot"] as Node3D).rotation_degrees = Vector3(pitch, yaw, 0)

# --------------------------------------------------------------------------- Flackernde Feuerlichter

## Warmes, flackerndes Punktlicht (z. B. brennende Scheune). Schatten optional.
func add_fire_light(pos: Vector3, energy: float, rng_range: float, shadows: bool = true) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.48, 0.16)
	l.light_energy = energy
	l.omni_range = rng_range
	l.omni_attenuation = 1.2
	l.light_volumetric_fog_energy = 1.6
	l.shadow_enabled = shadows
	l.shadow_blur = 2.0
	l.shadow_bias = 0.08
	add_child(l)
	l.global_position = pos
	_flicker.append({"light": l, "base": energy, "seed": rng.randf() * 50.0, "pos": pos})
	return l

func _update_flicker() -> void:
	for f in _flicker:
		var l: OmniLight3D = f["light"]
		if not is_instance_valid(l):
			continue
		var s: float = f["seed"]
		var k := 0.75 + 0.15 * sin(_time * 9.0 + s) + 0.1 * sin(_time * 17.3 + s * 1.7) + 0.06 * sin(_time * 31.0 + s * 0.3)
		l.light_energy = float(f["base"]) * k
		l.position = (f["pos"] as Vector3) + Vector3(sin(_time * 5.0 + s) * 0.15, sin(_time * 7.0 + s) * 0.1, cos(_time * 6.0 + s) * 0.15)  # FX-Knoten liegt im Ursprung

# --------------------------------------------------------------------------- Leuchtspur

func _build_tracer_pool() -> void:
	for c: Color in [Color(1.0, 0.45, 0.12), Color(1.0, 0.18, 0.08), Color(0.4, 1.0, 0.3)]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 18.0
		_tracer_mats.append(m)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.09, 4.0)
	for i in 40:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_tracer_pool.append(mi)

func _fire_burst(from: Vector3, to: Vector3, mat_i: int) -> void:
	var n := rng.randi_range(4, 9)
	for k in n:
		var mi: MeshInstance3D = null
		for t in _tracer_pool:
			if not t.visible:
				mi = t
				break
		if mi == null:
			return
		var spread := Vector3(rng.randf_range(-2, 2), rng.randf_range(-1, 2), rng.randf_range(-2, 2))
		var a := from
		var b := to + spread
		var dur := a.distance_to(b) / 280.0
		mi.material_override = _tracer_mats[mat_i]
		var delay := k * 0.11
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func() -> void:
			mi.visible = true
			mi.global_position = a
			mi.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.95 else Vector3.RIGHT))
		tw.tween_property(mi, "global_position", b, dur)
		tw.tween_callback(func() -> void: mi.visible = false)

func _update_tracers(cam: Vector3, delta: float) -> void:
	_tracer_t -= delta
	if _tracer_t > 0.0:
		return
	_tracer_t = rng.randf_range(0.6, 2.2)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var z := cam.z - rng.randf_range(20.0, 150.0)
	var from := Vector3(side * rng.randf_range(45.0, 110.0), rng.randf_range(0.8, 4.0), z)
	var to: Vector3
	if rng.randf() < 0.35:
		# Flak in den Himmel
		to = from + Vector3(rng.randf_range(-30, 30), rng.randf_range(90, 140), rng.randf_range(-30, 30))
	else:
		to = Vector3(-side * rng.randf_range(30.0, 110.0), rng.randf_range(0.5, 12.0), z + rng.randf_range(-60, 60))
	var mat_i := 0
	var r := rng.randf()
	if r < 0.25:
		mat_i = 1
	elif r < 0.4:
		mat_i = 2
	_fire_burst(from, to, mat_i)

# --------------------------------------------------------------------------- Artillerie (nur Optik + Erschuetterung)

func artillery_strike(pos: Vector3, scale: float, shake: float) -> void:
	# Truemmer-Limit von VFX nicht ausreizen (sonst landen Debris ausserhalb des Baums)
	if int(VFX.get("_debris_count")) < 45:
		VFX.spawn_explosion(pos, scale)
	else:
		VFX.spawn_dust_cloud(pos + Vector3(0, 1.0, 0), 3.0 * scale)
	var fl := OmniLight3D.new()
	fl.light_color = Color(1.0, 0.6, 0.3)
	fl.light_energy = 28.0
	fl.omni_range = 18.0 + scale * 10.0
	fl.light_volumetric_fog_energy = 3.0
	add_child(fl)
	fl.global_position = pos + Vector3(0, 3, 0)
	var tw := fl.create_tween()
	tw.tween_property(fl, "light_energy", 0.0, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_callback(fl.queue_free)
	Events.explosion.emit(pos, 1.5, scale)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl != null and pl.has_method("add_trauma") and shake > 0.0:
		pl.call("add_trauma", shake)

func _update_artillery(cam: Vector3, delta: float) -> void:
	if not artillery_enabled:
		return
	_art_t -= delta
	if _art_t > 0.0:
		return
	_art_t = rng.randf_range(artillery_interval_min, artillery_interval_max)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var z := clampf(cam.z - rng.randf_range(10.0, 120.0), end_z - 80.0, 30.0)
	var pos := Vector3(side * rng.randf_range(42.0, 110.0), 0.0, z)
	var d := cam.distance_to(pos)
	var salvo := rng.randi_range(1, 3)
	for k in salvo:
		var p := pos + Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-12, 12))
		var tw := create_tween()
		tw.tween_interval(k * rng.randf_range(0.4, 0.9))
		tw.tween_callback(func() -> void: artillery_strike(p, rng.randf_range(2.6, 4.0), clampf(0.2 - d / 700.0, 0.03, 0.16)))

# --------------------------------------------------------------------------- Ablauf

func _process(delta: float) -> void:
	_time += delta
	var cam := _last_cam
	var c := get_viewport().get_camera_3d()
	if c != null:
		cam = c.global_position
	_update_snow(cam, delta)
	_update_flares(cam, delta)
	for s in _search:
		_update_search_one(s)
	_update_flicker()
	if tracers_enabled:
		_update_tracers(cam, delta)
	_update_artillery(cam, delta)
	_last_cam = cam
