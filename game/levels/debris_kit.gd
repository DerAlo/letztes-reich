extends RefCounted
## Realistischer Schutt statt Quader-Batches: Schuttkegel als verrauschtes Hoehenfeld (Textur "brick_gravel",
## Poly Haven CC0) und darauf verstreute Ziegel, Ziegelbruch und Betonbrocken als MultiMesh (unregelmaessige,
## flach schattierte Polyeder; Textur "concrete_debris", Poly Haven CC0). Reine Optik, keine Kollision.
## Assets: tools/fetch_realism_assets.py -> assets/environment/realism.

const Geo = preload("res://game/levels/level_geo.gd")
const RL_TEX := "res://assets/environment/realism/textures/"

static var _mesh_cache: Dictionary = {}

## Texturmaterial (diffuse/normal/arm.jpg), weltbezogen triplanar. Fallback Flachfarbe, wenn die Textur fehlt.
static func tex(dir: String, tint: Color, scale: float, rough_mul: float = 1.0) -> StandardMaterial3D:
	if not ResourceLoader.exists(dir + "/diffuse.jpg"):
		return Geo.flat(tint * 0.6, 0.9).duplicate() as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + "/diffuse.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(dir + "/normal.jpg")
	if ResourceLoader.exists(dir + "/arm.jpg"):
		m.roughness_texture = load(dir + "/arm.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.ao_enabled = true
		m.ao_texture = load(dir + "/arm.jpg")
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = rough_mul
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

## Hoehe eines Schuttkegels: Plateau (core_min..core_max, Hoehe y_top) faellt nach aussen ueber falloff Meter
## auf y_base ab; Rauschen gibt Klumpen und Rinnen. Ausserhalb liegt die Flaeche knapp unter y_base.
static func heap_height(x: float, z: float, core_min: Vector2, core_max: Vector2, y_base: float, y_top: float,
		falloff: float, noise: FastNoiseLite) -> float:
	var dx := maxf(maxf(core_min.x - x, x - core_max.x), 0.0)
	var dz := maxf(maxf(core_min.y - z, z - core_max.y), 0.0)
	var e := sqrt(dx * dx + dz * dz) / falloff
	var n := noise.get_noise_2d(x, z)
	var t := clampf(1.0 - pow(minf(e, 1.0), 0.75) + n * 0.12, 0.0, 1.0)
	if e >= 1.0:
		return y_base - 0.06
	return lerpf(y_base - 0.04, y_top, t) + n * 0.1

static func make_noise(seed_v: int) -> FastNoiseLite:
	var nz := FastNoiseLite.new()
	nz.seed = seed_v
	nz.frequency = 1.6
	nz.fractal_octaves = 3
	return nz

## Schuttkegel als Hoehenfeld ueber area_min..area_max (x, z), Raster step.
static func heap(parent: Node3D, area_min: Vector2, area_max: Vector2, core_min: Vector2, core_max: Vector2,
		y_base: float, y_top: float, falloff: float, noise: FastNoiseLite, step: float = 0.14) -> MeshInstance3D:
	var nx := int(ceil((area_max.x - area_min.x) / step))
	var nz := int(ceil((area_max.y - area_min.y) / step))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	for j in nz + 1:
		for i in nx + 1:
			var x := lerpf(area_min.x, area_max.x, float(i) / nx)
			var z := lerpf(area_min.y, area_max.y, float(j) / nz)
			pts.append(Vector3(x, heap_height(x, z, core_min, core_max, y_base, y_top, falloff, noise), z))
	for j in nz:
		for i in nx:
			var a := pts[j * (nx + 1) + i]
			var b := pts[j * (nx + 1) + i + 1]
			var c := pts[(j + 1) * (nx + 1) + i]
			var d := pts[(j + 1) * (nx + 1) + i + 1]
			if a.y < y_base - 0.05 and b.y < y_base - 0.05 and c.y < y_base - 0.05 and d.y < y_base - 0.05:
				continue
			for v: Vector3 in [a, c, b, b, c, d]:
				st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Schuttkegel"
	mi.mesh = st.commit()
	mi.material_override = tex(RL_TEX + "brick_gravel", Color(0.7, 0.64, 0.6), 0.8, 1.0)
	parent.add_child(mi)
	return mi

## Unregelmaessiger Brocken (Einheitsgroesse ~1 m): verzerrte Kugel mit wenigen Segmenten, flach schattiert.
static func _chunk_mesh(variant: int) -> Mesh:
	var key := "chunk%d" % variant
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6 + variant % 3
	sm.rings = 3 + variant % 2
	var arr := sm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var r := RandomNumberGenerator.new()
	var stretch := Vector3(1.0, 0.55 + 0.1 * (variant % 3), 0.8 + 0.07 * variant)
	var moved: Dictionary = {}
	for k in verts.size():
		var v := verts[k]
		var hk := Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))
		if not moved.has(hk):
			r.seed = hash(hk) + variant * 7919
			var j := Vector3(r.randf_range(-0.17, 0.17), r.randf_range(-0.12, 0.12), r.randf_range(-0.17, 0.17))
			# Bruchflaechen: einzelne Seiten abgeflacht
			var w := v * stretch + j
			if w.y < -0.12:
				w.y = -0.12 - (w.y + 0.12) * 0.25
			moved[hk] = w
		verts[k] = moved[hk]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in idx.size():
		st.add_vertex(verts[idx[k]])
	st.generate_normals()
	var m := st.commit()
	_mesh_cache[key] = m
	return m

## Ziegel (NF 24 x 11,5 x 7,1 cm) oder Ziegelhaelfte mit leicht gebrochenen Kanten.
static func _brick_mesh(half: bool) -> Mesh:
	var key := "brick_half" if half else "brick"
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12 if half else 0.24, 0.071, 0.115)
	var arr := bm.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var r := RandomNumberGenerator.new()
	for k in verts.size():
		var v := verts[k]
		r.seed = hash(Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))) + (3 if half else 0)
		if half and v.x > 0.0:
			v.x += r.randf_range(-0.025, 0.02)
			v.z += r.randf_range(-0.01, 0.01)
		verts[k] = v + Vector3(r.randf_range(-0.004, 0.004), r.randf_range(-0.004, 0.004), r.randf_range(-0.004, 0.004))
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in idx.size():
		st.add_vertex(verts[idx[k]])
	st.generate_normals()
	var m := st.commit()
	_mesh_cache[key] = m
	return m

## Verstreut count Teile in area_min..area_max; Hoehe aus height_fn(x, z) (Callable -> float).
## brick_ratio = Anteil Ziegel/Ziegelbruch, Rest Betonbrocken (size_min..size_max m).
## Je Mesh-Typ eine MultiMeshInstance3D unter parent.
static func scatter(parent: Node3D, rng: RandomNumberGenerator, area_min: Vector2, area_max: Vector2, count: int,
		height_fn: Callable, size_min: float, size_max: float, brick_ratio: float = 0.65, shadows: bool = true) -> void:
	var groups: Dictionary = {}
	for i in count:
		var x := rng.randf_range(area_min.x, area_max.x)
		var z := rng.randf_range(area_min.y, area_max.y)
		var y: float = height_fn.call(x, z)
		if is_nan(y):
			continue
		var kind := ""
		var s := 1.0
		if rng.randf() < brick_ratio:
			kind = "brick_half" if rng.randf() < 0.45 else "brick"
			s = rng.randf_range(0.92, 1.08)
		else:
			kind = "chunk%d" % (rng.randi() % 4)
			s = rng.randf_range(size_min, size_max) * (0.6 if rng.randf() < 0.6 else 1.0)
		var basis := Basis.from_euler(Vector3(rng.randf_range(-0.9, 0.9), rng.randf() * TAU, rng.randf_range(-0.9, 0.9)))
		var sink := 0.015 if kind.begins_with("brick") else s * 0.18
		var xf := Transform3D(basis.scaled(Vector3.ONE * s), Vector3(x, y - sink, z))
		var tone := rng.randf_range(0.7, 1.12)
		var col := Color(tone, tone * rng.randf_range(0.92, 1.0), tone * rng.randf_range(0.86, 1.0))
		if not groups.has(kind):
			groups[kind] = []
		groups[kind].append([xf, col])
	var m_brick := tex(RL_TEX + "concrete_debris", Color(0.62, 0.3, 0.2), 2.4, 1.0)
	m_brick.vertex_color_use_as_albedo = true
	var m_conc := tex(RL_TEX + "concrete_debris", Color(0.66, 0.64, 0.6), 1.4, 1.0)
	m_conc.vertex_color_use_as_albedo = true
	for kind: String in groups:
		var list: Array = groups[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _brick_mesh(kind == "brick_half") if kind.begins_with("brick") else _chunk_mesh(int(kind.substr(5)))
		mm.instance_count = list.size()
		for k in list.size():
			mm.set_instance_transform(k, list[k][0])
			mm.set_instance_color(k, list[k][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Schutt_" + kind
		mmi.multimesh = mm
		mmi.material_override = m_brick if kind.begins_with("brick") else m_conc
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
