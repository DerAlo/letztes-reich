extends Node3D
## Effekte im Waermebild: Leuchtpunkte/Leuchtspuren (ImmediateMesh, additiv), Partikel-Pools
## (Truemmer, Feuerball, Staub, Funken, Rauch), Hitzeflecken/Druckwellen-Ringe am Boden und Dauerbraende.
## Alles nutzt die thermal_*-Shader: Helligkeit = Temperatur.

const GSMesh := preload("res://game/gunship/gs_mesh.gd")

class Spr:
	var pos: Vector3
	var p2: Vector3
	var vel: Vector3 = Vector3.ZERO
	var size: float = 1.0
	var grow: float = 0.0
	var heat: float = 1.0
	var alpha: float = 1.0
	var life: float = 0.0
	var max_life: float = 0.0
	var streak: bool = false
	var grav: float = 0.0
	var fade: bool = true

class Fire:
	var pos: Vector3
	var size: float
	var heat: float
	var until: float
	var smoke: GPUParticles3D = null
	var seed: float

class DecalFx:
	var mi: MeshInstance3D
	var life: float = 0.0
	var max_life: float = 1.0
	var intensity: float = 1.0
	var ring: bool = false
	var r0: float = 1.0
	var r1: float = 1.0

var cam: Camera3D = null
var _im: ImmediateMesh
var _im_mi: MeshInstance3D
var _spr: Array[Spr] = []
var _frame: Array[Spr] = []
var _fires: Array[Fire] = []
var _decals: Array[DecalFx] = []
var _decal_i: int = 0
var _rings: Array[DecalFx] = []
var _ring_i: int = 0
var _pools: Dictionary = {}       # name -> {"list": Array, "i": int}
var _smoke_free: Array[GPUParticles3D] = []
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.seed = 77
	_im = ImmediateMesh.new()
	_im_mi = MeshInstance3D.new()
	_im_mi.name = "Sprites"
	_im_mi.mesh = _im
	_im_mi.material_override = GSMesh.mat("sprite")
	_im_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_im_mi.extra_cull_margin = 16384.0
	add_child(_im_mi)
	for i in 56:
		_decals.append(_make_decal(false))
	for i in 6:
		_rings.append(_make_decal(true))
	# Partikel-Pools: [art, groesse, anzahl Emitter]
	for spec in [["debris", 0.5, 8], ["debris", 1.0, 6], ["debris", 2.0, 4],
			["fireball", 0.5, 6], ["fireball", 1.0, 5], ["fireball", 2.0, 4], ["fireball", 4.0, 3],
			["dust", 0.4, 16], ["dust", 1.0, 6], ["dust", 2.0, 4],
			["sparks", 0.4, 14], ["sparks", 1.0, 6]]:
		var key := "%s_%s" % [spec[0], str(spec[1])]
		var list: Array = []
		for i in int(spec[2]):
			list.append(_make_particles(str(spec[0]), float(spec[1]), true))
		_pools[key] = {"list": list, "i": 0}
	for i in 14:
		var sm := _make_particles("smoke", 1.0, false)
		sm.emitting = false
		_smoke_free.append(sm)

# ------------------------------------------------------------------ Oeffentlich: Sprites

## Leuchtpunkt (rund). life <= 0: nur fuer diesen Frame.
func glow(pos: Vector3, size: float, heat: float, life: float = 0.0, vel: Vector3 = Vector3.ZERO, grow: float = 0.0, grav: float = 0.0, alpha: float = 1.0) -> void:
	var s := Spr.new()
	s.pos = pos
	s.size = size
	s.heat = heat
	s.life = life
	s.max_life = life
	s.vel = vel
	s.grow = grow
	s.grav = grav
	s.alpha = alpha
	if life <= 0.0:
		_frame.append(s)
	else:
		_spr.append(s)

## Leuchtspur von a nach b (Breite w). life <= 0: nur fuer diesen Frame.
func streak(a: Vector3, b: Vector3, w: float, heat: float, life: float = 0.0, alpha: float = 1.0, vel: Vector3 = Vector3.ZERO) -> void:
	var s := Spr.new()
	s.pos = a
	s.p2 = b
	s.size = w
	s.heat = heat
	s.life = life
	s.max_life = life
	s.streak = true
	s.alpha = alpha
	s.vel = vel
	if life <= 0.0:
		_frame.append(s)
	else:
		_spr.append(s)

# ------------------------------------------------------------------ Oeffentlich: Einschlaege

## Einschlag/Explosion. size: 0.4 (25 mm), 1 (40 mm), 2.2 (105 mm/Fahrzeug), 4 (Tanklager).
func explosion(pos: Vector3, size: float, ring: bool = false, scorch: bool = true) -> void:
	var p := pos + Vector3(0, 0.3, 0)
	# Blitz: sehr heiss, kurz
	glow(p + Vector3(0, size * 1.2, 0), size * 9.0, 3.0, 0.12 + size * 0.04, Vector3.ZERO, size * 30.0)
	glow(p + Vector3(0, size * 0.8, 0), size * 4.5, 2.2, 0.35 + size * 0.1, Vector3(0, size * 3.0, 0), size * 6.0)
	if size <= 0.5:
		_emit("dust_0.4", p)
		if _rng.randf() < 0.6:
			_emit("sparks_0.4", p)
		for i in 2:
			var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.6, 1.6), _rng.randf_range(-1, 1))
			glow(p, 0.35, 1.6, 0.5, d * _rng.randf_range(5.0, 12.0), 0.0, 14.0)
	elif size <= 1.2:
		_emit("fireball_1.0" if size > 0.7 else "fireball_0.5", p)
		_emit("debris_0.5", p)
		_emit("dust_1.0", p)
		_emit("sparks_1.0", p)
	else:
		var big := size >= 3.0
		_emit("fireball_4.0" if big else "fireball_2.0", p)
		_emit("debris_2.0", p)
		_emit("debris_1.0", p)
		_emit("dust_2.0", p)
		_emit("sparks_1.0", p)
		for i in int(8 + size * 4):
			var d := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(0.4, 1.8), _rng.randf_range(-1, 1)).normalized()
			glow(p + d, _rng.randf_range(0.5, 1.1) * minf(size, 2.5), 1.8, _rng.randf_range(1.0, 2.4), d * _rng.randf_range(14.0, 30.0) * sqrt(size), 0.0, 18.0)
	if ring:
		_ring(pos, size * 16.0)
	if scorch:
		_scorch(pos, size)

## Bleibender Brand mit Rauchsaeule (Wracks, Tanklager). dur < 0 = bis Levelende.
func fire(pos: Vector3, size: float, heat: float = 1.6, dur: float = -1.0) -> void:
	var f := Fire.new()
	f.pos = pos
	f.size = size
	f.heat = heat
	f.until = (_time + dur) if dur > 0.0 else 1e12
	f.seed = _rng.randf() * 100.0
	if not _smoke_free.is_empty():
		f.smoke = _smoke_free.pop_back()
		f.smoke.global_position = pos + Vector3(0, size * 0.8, 0)
		f.smoke.amount_ratio = clampf(0.35 + size * 0.15, 0.3, 1.0)
		f.smoke.speed_scale = 1.0
		f.smoke.scale = Vector3.ONE * clampf(size * 0.6, 0.6, 3.0)
		f.smoke.emitting = true
	_fires.append(f)
	_scorch(pos, size * 0.8, 40.0 if dur < 0.0 else dur + 8.0)

func clear_all() -> void:
	_spr.clear()
	_frame.clear()

# ------------------------------------------------------------------ Ablauf

func _process(delta: float) -> void:
	_time += delta
	# Sprites bewegen/altern
	var i := 0
	while i < _spr.size():
		var s := _spr[i]
		s.life -= delta
		if s.life <= 0.0:
			_spr[i] = _spr[_spr.size() - 1]
			_spr.pop_back()
			continue
		if s.vel != Vector3.ZERO or s.grav != 0.0:
			s.vel.y -= s.grav * delta
			s.vel *= 1.0 - minf(delta * 0.8, 0.5)
			s.pos += s.vel * delta
			if s.streak:
				s.p2 += s.vel * delta
		s.size += s.grow * delta
		i += 1
	# Braende
	i = 0
	while i < _fires.size():
		var f := _fires[i]
		if _time > f.until:
			if f.smoke != null:
				f.smoke.emitting = false
				_smoke_free.append(f.smoke)
			_fires.remove_at(i)
			continue
		var fl := 0.75 + 0.25 * sin(_time * 13.0 + f.seed) * sin(_time * 7.3 + f.seed * 2.0)
		var n := 3 if f.size < 2.0 else 5
		for k in n:
			var ph := f.seed + k * 1.7
			var o := Vector3(sin(_time * 1.9 + ph) * f.size * 0.35, f.size * (0.35 + 0.42 * k) + sin(_time * 6.0 + ph) * f.size * 0.12, cos(_time * 2.3 + ph) * f.size * 0.35)
			glow(f.pos + o, f.size * (1.9 - k * 0.22) * fl, f.heat * (1.0 - k * 0.1), 0.0, Vector3.ZERO, 0.0, 0.0, 0.75)
		i += 1
	# Bodenflecken
	for d in _decals:
		if d.life > 0.0:
			d.life -= delta
			var t := clampf(d.life / d.max_life, 0.0, 1.0)
			d.mi.set_instance_shader_parameter("intensity", d.intensity * (0.28 + 0.72 * t * t))
			if d.life <= 0.0:
				d.mi.visible = false
	for d in _rings:
		if d.life > 0.0:
			d.life -= delta
			var t2 := 1.0 - clampf(d.life / d.max_life, 0.0, 1.0)
			var r := lerpf(d.r0, d.r1, 1.0 - pow(1.0 - t2, 2.2))
			d.mi.scale = Vector3(r * 2.0, 1.0, r * 2.0)
			d.mi.set_instance_shader_parameter("intensity", d.intensity * (1.0 - t2))
			d.mi.set_instance_shader_parameter("ring", clampf(0.35 - t2 * 0.25, 0.08, 0.35))
			if d.life <= 0.0:
				d.mi.visible = false
	_draw_sprites()

func _draw_sprites() -> void:
	_im.clear_surfaces()
	if cam == null or (_spr.is_empty() and _frame.is_empty()):
		_frame.clear()
		return
	var cb := cam.global_transform.basis
	var right := cb.x
	var up := cb.y
	var cpos := cam.global_position
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in _spr:
		_quad(s, right, up, cpos)
	for s in _frame:
		_quad(s, right, up, cpos)
	_im.surface_end()
	_frame.clear()

func _quad(s: Spr, right: Vector3, up: Vector3, cpos: Vector3) -> void:
	var h := s.heat
	var a := s.alpha
	if s.max_life > 0.0 and s.fade:
		var t := clampf(s.life / s.max_life, 0.0, 1.0)
		h *= 0.35 + 0.65 * t
		a *= minf(1.0, t * 3.0)
	var col := Color(h, h, h, a)
	var p0: Vector3
	var p1: Vector3
	var p2: Vector3
	var p3: Vector3
	var uv2 := Vector2.ZERO
	if s.streak:
		var dir := s.p2 - s.pos
		var len := dir.length()
		if len < 0.001:
			return
		var dn := dir / len
		var side := dn.cross(cpos - s.pos).normalized() * s.size
		var ext := dn * s.size
		p0 = s.pos - ext - side
		p1 = s.p2 + ext - side
		p2 = s.p2 + ext + side
		p3 = s.pos - ext + side
		uv2 = Vector2(1, 0)
	else:
		var r := right * s.size * 0.5
		var u := up * s.size * 0.5
		p0 = s.pos - r - u
		p1 = s.pos + r - u
		p2 = s.pos + r + u
		p3 = s.pos - r + u
	_v(p0, Vector2(0, 0), col, uv2)
	_v(p1, Vector2(1, 0), col, uv2)
	_v(p2, Vector2(1, 1), col, uv2)
	_v(p0, Vector2(0, 0), col, uv2)
	_v(p2, Vector2(1, 1), col, uv2)
	_v(p3, Vector2(0, 1), col, uv2)

func _v(p: Vector3, uv: Vector2, c: Color, uv2: Vector2) -> void:
	_im.surface_set_color(c)
	_im.surface_set_uv(uv)
	_im.surface_set_uv2(uv2)
	_im.surface_add_vertex(p)

# ------------------------------------------------------------------ Boden

func _make_decal(ring: bool) -> DecalFx:
	var d := DecalFx.new()
	d.ring = ring
	d.mi = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE
	d.mi.mesh = pm
	d.mi.material_override = GSMesh.mat("decal")
	d.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	d.mi.visible = false
	add_child(d.mi)
	d.mi.set_instance_shader_parameter("ring", 0.3 if ring else 0.0)
	return d

func _scorch(pos: Vector3, size: float, life: float = -1.0) -> void:
	var d := _decals[_decal_i]
	_decal_i = (_decal_i + 1) % _decals.size()
	var r := clampf(size * 5.0, 1.6, 26.0)
	d.mi.global_position = pos + Vector3(0, 0.22 + _rng.randf() * 0.1, 0)
	d.mi.rotation = Vector3(0, _rng.randf() * TAU, 0)
	d.mi.scale = Vector3(r * 2.0, 1.0, r * 2.0)
	d.max_life = life if life > 0.0 else (14.0 + size * 10.0)
	d.life = d.max_life
	d.intensity = clampf(0.75 + size * 0.15, 0.7, 1.3)
	d.mi.set_instance_shader_parameter("seed", _rng.randf() * 10.0)
	d.mi.set_instance_shader_parameter("intensity", d.intensity)
	d.mi.visible = true

func _ring(pos: Vector3, radius: float) -> void:
	var d := _rings[_ring_i]
	_ring_i = (_ring_i + 1) % _rings.size()
	d.mi.global_position = pos + Vector3(0, 0.35, 0)
	d.r0 = radius * 0.1
	d.r1 = radius
	d.max_life = 0.75
	d.life = d.max_life
	d.intensity = 1.25
	d.mi.scale = Vector3(d.r0 * 2.0, 1.0, d.r0 * 2.0)
	d.mi.set_instance_shader_parameter("seed", _rng.randf() * 10.0)
	d.mi.visible = true

# ------------------------------------------------------------------ Partikel

func _emit(key: String, pos: Vector3) -> void:
	var pool: Dictionary = _pools.get(key, {})
	if pool.is_empty():
		return
	var list: Array = pool["list"]
	var idx: int = pool["i"]
	pool["i"] = (idx + 1) % list.size()
	var gp: GPUParticles3D = list[idx]
	gp.global_position = pos
	gp.restart()

func _make_particles(kind: String, s: float, one_shot: bool) -> GPUParticles3D:
	var gp := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	gp.draw_pass_1 = quad
	gp.one_shot = one_shot
	gp.local_coords = false
	gp.fixed_fps = 30
	gp.interpolate = true
	gp.visibility_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 140, 160))
	gp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gp.process_material = pm
	var heat0 := 1.0
	var heat1 := 0.5
	var a0 := 1.0
	var grow0 := 1.0
	var grow1 := 1.0
	var additive := true
	match kind:
		"debris":
			gp.amount = int(16 + s * 14)
			gp.lifetime = 1.6 + s * 0.6
			gp.explosiveness = 1.0
			pm.direction = Vector3.UP
			pm.spread = 65.0
			pm.initial_velocity_min = 8.0 * sqrt(s)
			pm.initial_velocity_max = 26.0 * sqrt(s)
			pm.gravity = Vector3(0, -15.0, 0)
			pm.damping_min = 0.3
			pm.damping_max = 1.0
			pm.scale_min = 0.25 * s + 0.25
			pm.scale_max = 0.6 * s + 0.4
			heat0 = 1.5
			heat1 = 0.6
		"fireball":
			gp.amount = int(10 + s * 3)
			gp.lifetime = 0.55 + s * 0.22
			gp.explosiveness = 0.95
			pm.direction = Vector3.UP
			pm.spread = 180.0
			pm.initial_velocity_min = 1.5 * s
			pm.initial_velocity_max = 6.0 * s
			pm.gravity = Vector3(0, 3.0 * s, 0)
			pm.damping_min = 2.0
			pm.damping_max = 4.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.8 * s
			pm.scale_min = 2.2 * s
			pm.scale_max = 4.0 * s
			heat0 = 2.6
			heat1 = 0.9
			grow0 = 0.5
			grow1 = 1.6
		"dust":
			additive = false
			gp.amount = int(8 + s * 6)
			gp.lifetime = 3.5 + s * 2.5
			gp.explosiveness = 0.9
			pm.direction = Vector3.UP
			pm.spread = 75.0
			pm.initial_velocity_min = 1.5 * s + 1.0
			pm.initial_velocity_max = 5.0 * s + 2.0
			pm.gravity = Vector3(0.6, 0.5, 0.2)
			pm.damping_min = 1.0
			pm.damping_max = 2.0
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 0.6 * s + 0.3
			pm.scale_min = 2.0 * s + 1.0
			pm.scale_max = 4.0 * s + 1.6
			heat0 = 0.62
			heat1 = 0.3
			a0 = 0.75
			grow0 = 0.45
			grow1 = 1.8
		"sparks":
			gp.amount = int(14 + s * 10)
			gp.lifetime = 0.7 + s * 0.3
			gp.explosiveness = 1.0
			pm.direction = Vector3.UP
			pm.spread = 80.0
			pm.initial_velocity_min = 10.0 * sqrt(s) + 4.0
			pm.initial_velocity_max = 30.0 * sqrt(s) + 8.0
			pm.gravity = Vector3(0, -18.0, 0)
			pm.scale_min = 0.18 + s * 0.12
			pm.scale_max = 0.35 + s * 0.2
			heat0 = 2.2
			heat1 = 0.8
		"smoke":
			additive = false
			gp.amount = 26
			gp.lifetime = 10.0
			gp.explosiveness = 0.0
			gp.preprocess = 0.0
			pm.direction = Vector3.UP
			pm.spread = 14.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 4.0
			pm.gravity = Vector3(1.1, 0.9, 0.35)
			pm.damping_min = 0.1
			pm.damping_max = 0.3
			pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			pm.emission_sphere_radius = 1.5
			pm.scale_min = 4.0
			pm.scale_max = 7.0
			heat0 = 0.7
			heat1 = 0.3
			a0 = 0.55
			grow0 = 0.5
			grow1 = 2.6
			gp.visibility_aabb = AABB(Vector3(-60, -10, -60), Vector3(160, 160, 120))
	pm.color = Color(heat0, heat0, heat0, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, a0))
	g.set_color(1, Color(heat1 / heat0, heat1 / heat0, heat1 / heat0, 0.0))
	if kind == "dust" or kind == "smoke":
		g.add_point(0.15, Color(1, 1, 1, a0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.use_hdr = true
	pm.color_ramp = gt
	var c := Curve.new()
	c.max_value = 4.0
	c.add_point(Vector2(0, grow0))
	c.add_point(Vector2(1, grow1))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	gp.material_override = GSMesh.mat("particle_add" if additive else "particle")
	gp.emitting = false
	add_child(gp)
	return gp
