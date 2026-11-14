extends RefCounted
## Streckenbaeume fuer den Nachtzug (Winter): Fichten aus Zweigkarten (night_props.spruce_mesh) und
## kahle Laubbaeume (Eiche mit trockenem Restlaub, Birke, Linde) als MultiMesh je Landschafts-Chunk.
## Nahstufe bis HI_END, danach Fichten-Impostor bzw. vereinfachter Laubbaum. Kein Wind/Schwanken:
## die Chunks fahren mit ~33 m/s am Zug vorbei, weltpositionsabhaengiges Schwanken wuerde zittern.
## Ersetzt die Kugelbuesche durch junge Fichten und kahle Straeucher.

const NP = preload("res://game/levels/night_props.gd")
const FOLIAGE_SHADER := preload("res://assets/environment/villa/foliage.gdshader")
const LEAF_TEX := "res://assets/environment/villa/leaves/leaf_cluster.png"
const NEAR_X := 80.0        ## bis hier Nahstufen-Baeume (Mischwald), dahinter nur Fichten-Impostor
const HI_END := 150.0       ## Sichtweite der Nahstufe (m)
const BROADLEAF_SHARE := 0.32

static var _c: Dictionary = {}

static func _still(m: ShaderMaterial, snow: float) -> ShaderMaterial:
	var d := m.duplicate() as ShaderMaterial
	d.set_shader_parameter("sway", 0.0)
	d.set_shader_parameter("flutter", 0.0)
	d.set_shader_parameter("noise_local", true)   # Baeume fahren mit den Chunks: Muster am Baum
	d.set_shader_parameter("snow_amount", snow)
	d.set_shader_parameter("needle_tint", Color(0.8, 0.84, 0.82))
	return d

static func _spruce_hi(v: int) -> Mesh:
	var key := "sp_hi%d" % v
	if not _c.has(key):
		if not _c.has("sp_mat"):
			_c["sp_mat"] = _still(NP.spruce_mat(), 0.24)
		var vr := RandomNumberGenerator.new()
		vr.seed = 811 + v * 37
		var m := NP.spruce_mesh(vr, NP.TREE_H * (0.9 + 0.1 * v))
		m.surface_set_material(0, _c["sp_mat"])
		_c[key] = m
	return _c[key]

static func _spruce_lo(v: int) -> Mesh:
	var key := "sp_lo%d" % v
	if not _c.has(key):
		if not _c.has("imp_mat"):
			_c["imp_mat"] = _still(NP.spruce_impostor_mat(), 0.3)
		var m := NP.spruce_impostor(v)
		m.surface_set_material(0, _c["imp_mat"])
		_c[key] = m
	return _c[key]

# ------------------------------------------------------------------ kahle Laubbaeume

## Arten: 0 Eiche (breit, knorrig, trockenes Restlaub), 1 Birke (schlank, hell), 2 Linde (rund, dicht verzweigt)
const SPECIES := [
	{"h": 11.0, "r": 0.28, "limbs": 5, "spread": 0.95, "up": 0.55, "bark": Color(0.5, 0.46, 0.42), "leaves": 90},
	{"h": 13.0, "r": 0.17, "limbs": 7, "spread": 0.45, "up": 0.9, "bark": Color(1.0, 0.98, 0.94), "leaves": 0},
	{"h": 12.0, "r": 0.24, "limbs": 6, "spread": 0.7, "up": 0.75, "bark": Color(0.62, 0.58, 0.54), "leaves": 0},
]

static func broadleaf(sp: int, lod: int) -> Mesh:
	var key := "bl%d_%d" % [sp, lod]
	if _c.has(key):
		return _c[key]
	var cfg: Dictionary = SPECIES[sp]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4410 + sp * 101
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tips: Array[Vector3] = []
	var max_depth := 3 if lod == 0 else 1
	var h: float = cfg["h"]
	var r0: float = cfg["r"]
	# Stamm bis zum Kronenansatz, darueber Leittrieb
	var crown_y := h * (0.32 if sp != 1 else 0.22)
	var lean := Vector3(rng.randf_range(-0.12, 0.12), 1.0, rng.randf_range(-0.12, 0.12)).normalized()
	var trunk_top := _limb(st, Vector3(0, -0.3, 0), lean, h * (0.62 if sp != 0 else 0.45), r0 * 1.25, r0 * 0.35, 4 if lod == 0 else 2, 9 if lod == 0 else 5, rng, 0.06)
	var limbs: int = cfg["limbs"]
	for k in limbs:
		var t := float(k) / float(limbs)
		var a := TAU * t * 1.618 + rng.randf_range(-0.3, 0.3)
		var y := crown_y + (trunk_top.y - crown_y) * pow(t, 0.8)
		var p := Vector3(lean.x, 0, lean.z) * (y / lean.y) + Vector3(0, y, 0)
		var dir := Vector3(cos(a) * float(cfg["spread"]), float(cfg["up"]) + rng.randf_range(-0.1, 0.25), sin(a) * float(cfg["spread"])).normalized()
		var L := h * rng.randf_range(0.34, 0.46) * (1.0 - t * 0.45)
		_branch(st, p, dir, L, r0 * lerpf(0.55, 0.3, t), 1, max_depth, rng, tips, cfg)
	st.generate_tangents()
	var mesh := st.commit()
	var bm_key := "bark%d" % sp
	if not _c.has(bm_key):
		if not _c.has("sp_mat"):
			_c["sp_mat"] = _still(NP.spruce_mat(), 0.24)
		var bm := (_c["sp_mat"] as ShaderMaterial).duplicate() as ShaderMaterial
		bm.set_shader_parameter("bark_tint", cfg["bark"])
		bm.set_shader_parameter("snow_amount", 0.3)
		_c[bm_key] = bm
	mesh.surface_set_material(0, _c[bm_key])
	# Trockenes Eichenlaub (bleibt im Winter haengen) als duenne Kartenbueschel an den Zweigspitzen
	var n_leaves: int = cfg["leaves"]
	if n_leaves > 0 and lod == 0 and not tips.is_empty():
		var ls := SurfaceTool.new()
		ls.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in n_leaves:
			var tp: Vector3 = tips[rng.randi() % tips.size()]
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 1.0), rng.randf_range(-1, 1)).normalized()
			var s := rng.randf_range(0.35, 0.65)
			var ax := Vector3(d.z, 0, -d.x).normalized()
			if ax.length() < 0.1:
				ax = Vector3.RIGHT
			var ay := d.cross(ax).normalized()
			var rot := rng.randf() * TAU
			var u := (ax * cos(rot) + ay * sin(rot)) * s * 0.5
			var w := (-ax * sin(rot) + ay * cos(rot)) * s * 0.5
			var c := tp + d * 0.2
			var col := Color(0.0, rng.randf(), rng.randf_range(0.5, 1.0))
			var n := (c - Vector3(0, h * 0.6, 0)).normalized()
			var pts: Array[Vector3] = [c - u - w, c + u - w, c + u + w, c - u + w]
			var uvs: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
			for idx: int in [0, 1, 2, 0, 2, 3]:
				ls.set_color(col)
				ls.set_normal(n)
				ls.set_uv(uvs[idx])
				ls.add_vertex(pts[idx])
		ls.commit(mesh)
		mesh.surface_set_material(1, _leaf_mat())
	_c[key] = mesh
	return mesh

static func _leaf_mat() -> ShaderMaterial:
	if not _c.has("leaf_mat"):
		var m := ShaderMaterial.new()
		m.shader = FOLIAGE_SHADER
		m.set_shader_parameter("leaf_tex", load(LEAF_TEX))
		m.set_shader_parameter("tint", Color(0.42, 0.26, 0.13))
		m.set_shader_parameter("tint2", Color(0.55, 0.36, 0.18))
		m.set_shader_parameter("backlight_color", Color(0.12, 0.07, 0.03))
		m.set_shader_parameter("wind", 0.0)
		m.set_shader_parameter("alpha_cut", 0.5)
		_c["leaf_mat"] = m
	return _c["leaf_mat"]

## Gekruemmter, sich verjuengender Ast (Rindenpfad des Fichten-Shaders: COLOR.b = 1). Gibt die Spitze zurueck.
static func _limb(st: SurfaceTool, p0: Vector3, dir: Vector3, L: float, ra: float, rb: float, segs: int, sides: int, rng: RandomNumberGenerator, wobble: float) -> Vector3:
	var pts: Array[Vector3] = [p0]
	var d := dir
	for i in segs:
		d = (d + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.4, 0.6), rng.randf_range(-1, 1)) * wobble).normalized()
		pts.append(pts[i] + d * (L / segs))
	var prev: Array = []
	var vacc := 0.0
	for i in pts.size():
		var f := float(i) / float(segs)
		var r := lerpf(ra, rb, f)
		var fwd := (pts[mini(i + 1, segs)] - pts[maxi(i - 1, 0)]).normalized()
		var t := fwd.cross(Vector3.UP)
		if t.length() < 0.1:
			t = fwd.cross(Vector3.RIGHT)
		t = t.normalized()
		var b := fwd.cross(t).normalized()
		if i > 0:
			vacc += pts[i].distance_to(pts[i - 1]) / maxf(TAU * r * 1.4, 0.15)
		var ring: Array = []
		for k in sides + 1:
			var a := TAU * float(k) / float(sides)
			var n := t * cos(a) + b * sin(a)
			ring.append([pts[i] + n * r, n, Vector2(float(k) / float(sides), vacc), Color(0.0, lerpf(0.55, 1.0, f), 1.0)])
		if i > 0:
			for k in sides:
				NP._sp_quad(st, [prev[k], prev[k + 1], ring[k + 1], ring[k]], Color(-1, 0, 0))
		prev = ring
	return pts[pts.size() - 1]

static func _branch(st: SurfaceTool, p: Vector3, dir: Vector3, L: float, r: float, depth: int, max_depth: int, rng: RandomNumberGenerator, tips: Array[Vector3], cfg: Dictionary) -> void:
	var emit := depth <= max_depth
	var sides: int = [6, 5, 4, 3][mini(depth, 3)]
	var segs := 3 if depth <= 1 else 2
	var tip := p + dir * L
	if emit:
		tip = _limb(st, p, dir, L, r, r * 0.4, segs, sides, rng, 0.12 + 0.05 * depth)
	else:
		# Zufallsfolge wie im sichtbaren Fall verbrauchen (gleiche Struktur in beiden Stufen)
		for i in segs:
			for _j in 3:
				rng.randf()
	if depth >= 3:
		tips.append(tip)
		return
	var kids := rng.randi_range(2, 4) if depth < 2 else rng.randi_range(3, 4)
	for k in kids:
		var f := rng.randf_range(0.35, 1.0)
		var base := p.lerp(tip, f)
		var side := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
		var nd := (dir * 0.7 + side.normalized() * rng.randf_range(0.45, 0.8) + Vector3.UP * float(cfg["up"]) * 0.35).normalized()
		_branch(st, base, nd, L * rng.randf_range(0.45, 0.62), r * 0.5, depth + 1, max_depth, rng, tips, cfg)

## Kahler Strauch (mehrere Triebe aus dem Boden, ~1,5-2,5 m)
static func shrub() -> Mesh:
	if _c.has("shrub"):
		return _c["shrub"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tips: Array[Vector3] = []
	var cfg := {"up": 1.0}
	for k in 7:
		var a := TAU * float(k) / 7.0 + rng.randf_range(-0.3, 0.3)
		var dir := Vector3(cos(a) * 0.45, 1.0, sin(a) * 0.45).normalized()
		_branch(st, Vector3(cos(a) * 0.12, -0.1, sin(a) * 0.12), dir, rng.randf_range(1.3, 2.1), 0.035, 2, 3, rng, tips, cfg)
	st.generate_tangents()
	var mesh := st.commit()
	if not _c.has("bark2"):
		broadleaf(2, 1)
	mesh.surface_set_material(0, _c["bark2"])
	_c["shrub"] = mesh
	return mesh

# ------------------------------------------------------------------ Bepflanzung eines Chunks

static func _mmi(c: Node3D, mesh: Mesh, xs: Array, vis_begin: float, vis_end: float) -> void:
	if xs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_begin > 0.0:
		mi.visibility_range_begin = vis_begin
		mi.visibility_range_begin_margin = 10.0
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = 10.0
	c.add_child(mi)

static func _add(groups: Dictionary, key: String, xf: Transform3D) -> void:
	if not groups.has(key):
		groups[key] = []
	groups[key].append(xf)

## trees: [Vector3 pos, Basis basis(Drehung+Skalierung wie bisher), int idx]; shrubs: [Vector3 pos, float s, int idx].
## Gruppen je Seite und Chunk-Haelfte, damit die Sichtweiten-LOD greift.
static func plant(c: Node3D, trees: Array, shrubs: Array, chunk_len: float) -> void:
	var g: Dictionary = {}
	for t: Array in trees:
		var p: Vector3 = t[0]
		var b: Basis = t[1]
		var i: int = t[2]
		var h := absi(int(p.x * 7.31) * 31 + int(p.z * 3.7) * 17 + i * 13)
		var cell := "%d_%d" % [1 if p.x > 0.0 else 0, 0 if p.z > -chunk_len * 0.5 else 1]
		if absf(p.x) < NEAR_X:
			if float(h % 100) < BROADLEAF_SHARE * 100.0:
				var sp := (h / 100) % 3
				# Laubbaeume etwas niedriger als die Fichten-Skala, gerade stehend
				var bb := b.scaled(Vector3(0.95, 0.85, 0.95))
				_add(g, "bl%d|%s" % [sp, cell], Transform3D(bb, p + Vector3(0, 0.1, 0)))
			else:
				_add(g, "sh%d|%s" % [h % 3, cell], Transform3D(b, p))
		else:
			_add(g, "sl%d|%d" % [h % 3, 1 if p.x > 0.0 else 0], Transform3D(b, p))
	for s: Array in shrubs:
		var p: Vector3 = s[0]
		var sc: float = s[1]
		var i: int = s[2]
		var cell := "%d_%d" % [1 if p.x > 0.0 else 0, 0 if p.z > -chunk_len * 0.5 else 1]
		var bas := Basis(Vector3.UP, float(i) * 2.1 + p.z)
		if i % 3 == 2:
			_add(g, "shrub|" + cell, Transform3D(bas.scaled(Vector3.ONE * sc), p + Vector3(0, -0.2, 0)))
		else:
			# junge Fichte 2-4 m
			var ys := 0.2 + 0.1 * sc
			_add(g, "young%d|%s" % [i % 3, cell], Transform3D(bas.scaled(Vector3(ys, ys * 1.05, ys)), p + Vector3(0, -0.4, 0)))
	for key: String in g:
		var kind := key.get_slice("|", 0)
		var xs: Array = g[key]
		if kind.begins_with("sh"):
			var v := int(kind.substr(2))
			_mmi(c, _spruce_hi(v), xs, 0.0, HI_END)
			_mmi(c, _spruce_lo(v), xs, HI_END, 0.0)
		elif kind.begins_with("sl"):
			_mmi(c, _spruce_lo(int(kind.substr(2))), xs, 0.0, 0.0)
		elif kind.begins_with("bl"):
			var sp := int(kind.substr(2))
			_mmi(c, broadleaf(sp, 0), xs, 0.0, HI_END)
			_mmi(c, broadleaf(sp, 1), xs, HI_END, 0.0)
		elif kind.begins_with("young"):
			_mmi(c, _spruce_hi(int(kind.substr(5))), xs, 0.0, HI_END)
		elif kind == "shrub":
			_mmi(c, shrub(), xs, 0.0, 90.0)
