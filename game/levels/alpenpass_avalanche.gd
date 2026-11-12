extends Node3D
## Lawine fuer "Weisses Rauschen" (alpenpass.gd): eine Pulverschnee-Front laeuft die Rinne hinab (drei
## Partikelschichten: Bodenwalze, hohe Staubfahne, schnelle Gischt), rollende Schneebrocken, danach ein weisser
## Lawinenkegel. Ausserdem weisse Schnee-Woelkchen (Rotorabwind, Einschlaege im Schnee) statt braunem Staub.

const VfxLib = preload("res://game/vfx/vfx_lib.gd")

static var _powder: ShaderMaterial

## Lichtdurchlaessiger weisser Pulverschnee (beleuchteter Rauch-Shader ohne Schattenempfang).
static func powder_mat() -> ShaderMaterial:
	if _powder == null:
		_powder = VfxLib.smoke_mat({"smoke_color": Color(0.94, 0.96, 1.0), "smoke_color_end": Color(0.9, 0.93, 0.98),
			"density": 2.4, "self_shadow": 0.55, "glow": 0.0, "soft_dist": 2.0, "wrap": 0.75, "scatter": 0.9,
			"erosion": 0.14, "detail_erode": 0.12}, true)
	return _powder

## Einzelner Schneewirbel (z. B. Rotorabwind): ein paar Partikel, die sich ausbreiten und vergehen.
static func puff(parent: Node, pos: Vector3, size: float, amount: int = 6, life: float = 2.6) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = size * 0.25
	pm.direction = Vector3(0, 0.4, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = size * 0.25
	pm.initial_velocity_max = size * 0.6
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = size * 0.45
	pm.scale_max = size * 0.7
	pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.5], [0.4, 1.0], [1.0, 1.6]])
	pm.color_ramp = VfxLib.smoke_alpha_ramp(0.75, 0.1, 0.35)
	VfxLib.smoke_pm(pm, 12.0)
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = powder_mat()
	var p := VfxLib.make_particles(amount, life, pm, q, null)
	p.material_override = null
	p.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 50, 80))
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

# ------------------------------------------------------------------ Lawinenfront

var _pts: Array[Vector3] = []
var _cum: Array[float] = []
var _len: float = 1.0
var _dur: float = 5.0
var _t: float = 0.0
var _done: bool = false
var _ter: RefCounted
var _emit: Array[GPUParticles3D] = []
var _chunks: Array[Dictionary] = []   ## {node, lag, side, spin, r}
var _chunk_mat: Material

## pts: Bahn der Front (Weltkoordinaten), dur: Laufzeit, ter: Gelaende (height()), chunk_mat: Material der Brocken.
func setup(pts: Array, dur: float, ter: RefCounted, chunk_mat: Material) -> void:
	_ter = ter
	_dur = maxf(dur, 0.5)
	_chunk_mat = chunk_mat
	_pts.clear()
	for p: Vector3 in pts:
		_pts.append(p)
	_cum = [0.0]
	for i in range(1, _pts.size()):
		_cum.append(_cum[i - 1] + _pts[i - 1].distance_to(_pts[i]))
	_len = maxf(_cum[_cum.size() - 1], 1.0)
	# Bodenwalze: dichte, grosse Ballen, die mit der Front rollen und hinter ihr stehen bleiben
	_emit.append(_layer(200, 7.0, Vector3(0, 0.25, 1), 30.0, 9.0, 17.0, 1.1, 13.0, 19.0, [[0.0, 0.4], [0.25, 0.9], [1.0, 2.2]], Vector3(16, 3, 6), 1.0))
	# Hohe Staubfahne: steigt auf, sehr gross, langsam
	_emit.append(_layer(90, 11.0, Vector3(0, 1, 0.4), 30.0, 4.0, 9.0, 1.8, 22.0, 30.0, [[0.0, 0.45], [0.35, 1.3], [1.0, 2.6]], Vector3(20, 5, 8), 0.85))
	# Gischt: kleine, schnelle Fetzen vorne weg
	_emit.append(_layer(140, 2.4, Vector3(0, 0.12, 1), 22.0, 18.0, 27.0, -5.0, 4.0, 7.0, [[0.0, 0.6], [0.4, 1.2], [1.0, 1.7]], Vector3(9, 1, 3), 0.9))
	for e in _emit:
		e.emitting = true
	# Schneebrocken
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 26:
		var r := rng.randf_range(0.5, 1.6)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 1.6
		sm.radial_segments = 9
		sm.rings = 5
		mi.mesh = sm
		mi.material_override = _chunk_mat
		mi.scale = Vector3(rng.randf_range(0.8, 1.3), rng.randf_range(0.7, 1.0), rng.randf_range(0.8, 1.3))
		add_child(mi)
		_chunks.append({"node": mi, "lag": rng.randf_range(-3.0, 16.0), "side": rng.randf_range(-12.0, 12.0),
			"spin": Vector3(rng.randf_range(-9, 9), rng.randf_range(-3, 3), rng.randf_range(-9, 9)), "r": r, "ph": rng.randf() * TAU})
	_place(0.0, 0.0)

func _layer(amount: int, life: float, dir: Vector3, spread: float, v0: float, v1: float, up: float, s0: float, s1: float,
		curve: Array, ext: Vector3, alpha: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = ext
	pm.direction = dir.normalized()
	pm.spread = spread
	pm.initial_velocity_min = v0
	pm.initial_velocity_max = v1
	pm.gravity = Vector3(0, up, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = s0
	pm.scale_max = s1
	pm.scale_curve = VfxLib.smooth_curve_tex(curve)
	pm.color_ramp = VfxLib.smoke_alpha_ramp(alpha, 0.06, 0.45)
	VfxLib.smoke_pm(pm, 8.0)
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = powder_mat()
	var p := VfxLib.make_particles(amount, life, pm, q, null)
	p.material_override = null
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-160, -60, -160), Vector3(320, 200, 320))
	add_child(p)
	return p

func _at(dist: float) -> Vector3:
	dist = clampf(dist, 0.0, _len)
	for i in range(1, _pts.size()):
		if dist <= _cum[i] or i == _pts.size() - 1:
			var seg := maxf(_cum[i] - _cum[i - 1], 0.001)
			return _pts[i - 1].lerp(_pts[i], clampf((dist - _cum[i - 1]) / seg, 0.0, 1.0))
	return _pts[_pts.size() - 1]

func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, float(_ter.call("height", p.x, p.z)), p.z)

func _place(dist: float, delta: float) -> void:
	var a := _ground(_at(dist))
	var b := _ground(_at(dist + 4.0))
	var dir := b - a
	if dir.length() < 0.01:
		dir = _pts[_pts.size() - 1] - _pts[0]
	dir = dir.normalized()
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	var bas := Basis.looking_at(-flat, Vector3.UP)   # lokales +Z = Laufrichtung
	if not _done:
		_emit[0].global_transform = Transform3D(bas, a + Vector3(0, 3.0, 0))
		_emit[1].global_transform = Transform3D(bas, a + Vector3(0, 9.0, 0) - flat * 6.0)
		_emit[2].global_transform = Transform3D(bas, a + Vector3(0, 1.2, 0) + flat * 4.0)
	var side := bas.x
	for c: Dictionary in _chunks:
		var n := c["node"] as MeshInstance3D
		var d := dist - float(c["lag"])
		if d < 0.0:
			n.visible = false
			continue
		n.visible = true
		var g := _ground(_at(d) + side * float(c["side"]))
		var r := float(c["r"])
		var bounce := absf(sin(_t * 5.0 + float(c["ph"]))) * (1.4 if not _done else 0.0)
		n.global_position = g + Vector3(0, r * 0.6 + bounce, 0)
		if not _done:
			n.rotation += (c["spin"] as Vector3) * delta

func _process(delta: float) -> void:
	_t += delta
	var f := clampf(_t / _dur, 0.0, 1.0)
	var prog := f * f * 0.55 + f * 0.45     # beschleunigt
	_place(prog * _len, delta)
	if f >= 1.0 and not _done:
		_done = true
		for e in _emit:
			e.emitting = false
		# Abschluss: grosse, langsam sinkende Wolke ueber dem Kegel
		var end := _ground(_pts[_pts.size() - 1])
		for k in 4:
			puff(get_parent(), end + Vector3(randf_range(-14, 14), 4.0, randf_range(-10, 10)), 22.0, 8, 7.0)
		get_tree().create_timer(12.0).timeout.connect(_finish)

func _finish() -> void:
	# Brocken bleiben liegen (werden an den Elternknoten umgehaengt), die Partikel-Emitter verschwinden
	for c: Dictionary in _chunks:
		var n := c["node"] as MeshInstance3D
		if is_instance_valid(n) and n.visible:
			var gt := n.global_transform
			remove_child(n)
			get_parent().add_child(n)
			n.global_transform = gt
	queue_free()

# ------------------------------------------------------------------ Lawinenkegel

## Weisser Ablagerungskegel als Hoehenfeld ueber dem Gelaende: Ellipsen [cx, cz, rx, rz, h], weiche Kuppen + Knollen.
static func build_cone(parent: Node, ter: RefCounted, blobs: Array, mat: Material) -> MeshInstance3D:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for bl: Array in blobs:
		lo = Vector2(minf(lo.x, float(bl[0]) - float(bl[2])), minf(lo.y, float(bl[1]) - float(bl[3])))
		hi = Vector2(maxf(hi.x, float(bl[0]) + float(bl[2])), maxf(hi.y, float(bl[1]) + float(bl[3])))
	var step := 1.5
	var nx := int(ceil((hi.x - lo.x) / step)) + 1
	var nz := int(ceil((hi.y - lo.y) / step)) + 1
	var fn := FastNoiseLite.new()
	fn.seed = 77
	fn.frequency = 0.12
	fn.fractal_octaves = 3
	var verts := PackedVector3Array()
	var hts := PackedFloat32Array()
	for j in nz:
		for i in nx:
			var x := lo.x + float(i) * step
			var z := lo.y + float(j) * step
			var h := 0.0
			for bl: Array in blobs:
				var dx := (x - float(bl[0])) / float(bl[2])
				var dz := (z - float(bl[1])) / float(bl[3])
				var r2 := dx * dx + dz * dz
				if r2 < 1.0:
					h = maxf(h, float(bl[4]) * pow(1.0 - r2, 1.4))
			if h > 0.05:
				h += (fn.get_noise_2d(x, z) * 0.5 + 0.5) * minf(h * 0.35, 1.4)   # Knollen
			hts.append(h)
			verts.append(Vector3(x, float(ter.call("height", x, z)) + (h - 0.35 if h > 0.05 else -0.6), z))
	var norms := PackedVector3Array()
	for j in nz:
		for i in nx:
			var l := verts[j * nx + maxi(i - 1, 0)]
			var r := verts[j * nx + mini(i + 1, nx - 1)]
			var u := verts[maxi(j - 1, 0) * nx + i]
			var d := verts[mini(j + 1, nz - 1) * nx + i]
			var nn := (d - u).cross(r - l).normalized()
			if nn.y < 0.0:
				nn = -nn
			norms.append(nn)
	var idx := PackedInt32Array()
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			if hts[a] <= 0.05 and hts[a + 1] <= 0.05 and hts[a + nx] <= 0.05 and hts[a + nx + 1] <= 0.05:
				continue
			idx.append_array([a, a + 1, a + nx, a + 1, a + nx + 1, a + nx])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Lawinenkegel_Optik"
	mi.mesh = m
	mi.material_override = mat
	parent.add_child(mi)
	return mi
