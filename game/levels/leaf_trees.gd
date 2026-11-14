extends RefCounted
## Belaubte Laubbaeume (Spaetsommer/Fruehherbst) als MultiMesh: Rindenstamm + Astwerk aus dem
## Nachtzug-Baukasten (track_trees.gd, _limb/_branch, Fichten-Rindenpfad ohne Schnee) und eine
## Krone aus Laubbueschel-Karten (villa foliage.gdshader), die an den Zweigspitzen sitzen und
## das Kronenvolumen von innen auffuellen. Ersetzt die alten Kugelkronen (Ellipsoid + Quader-Stamm).
## Zwei Stufen: Nahstufe (volles Astwerk, dichte Karten) bis HI_END, Fernstufe (grobe Aeste,
## weniger, groessere Karten). Optional Stammkollision (ein Body, Zylinder je Baum).

const TT = preload("res://game/levels/track_trees.gd")
const NP = preload("res://game/levels/night_props.gd")
const Geo = preload("res://game/levels/level_geo.gd")
const FOLIAGE_SHADER := preload("res://assets/environment/villa/foliage.gdshader")
const LEAF_TEX := "res://assets/environment/villa/leaves/leaf_cluster.png"
const HI_END := 90.0
const VARIANTS := 4

## Arten: 0 Linde/Ahorn (rund, dicht), 1 Eiche (breit, knorrig), 2 Pappel (hoch, schmal), 3 Birke (licht)
const SPECIES := [
	{"h": 13.0, "r": 0.3, "limbs": 7, "spread": 0.8, "up": 0.75, "bark": Color(0.5, 0.47, 0.43), "crown": Vector3(4.2, 4.0, 4.2), "cy": 0.62, "cards": 260},
	{"h": 12.0, "r": 0.36, "limbs": 6, "spread": 1.0, "up": 0.5, "bark": Color(0.45, 0.42, 0.38), "crown": Vector3(5.0, 3.6, 5.0), "cy": 0.6, "cards": 280},
	{"h": 18.0, "r": 0.3, "limbs": 9, "spread": 0.35, "up": 1.0, "bark": Color(0.52, 0.5, 0.46), "crown": Vector3(2.6, 6.5, 2.6), "cy": 0.6, "cards": 240},
	{"h": 14.0, "r": 0.2, "limbs": 8, "spread": 0.5, "up": 0.9, "bark": Color(0.95, 0.93, 0.9), "crown": Vector3(3.0, 4.6, 3.0), "cy": 0.64, "cards": 170},
]

static var _c: Dictionary = {}

static func _bark_mat(sp: int) -> ShaderMaterial:
	var key := "bark%d" % sp
	if not _c.has(key):
		var m := NP.spruce_mat().duplicate() as ShaderMaterial
		m.set_shader_parameter("sway", 0.0)
		m.set_shader_parameter("flutter", 0.0)
		m.set_shader_parameter("snow_amount", 0.0)
		m.set_shader_parameter("bark_tint", SPECIES[sp]["bark"])
		_c[key] = m
	return _c[key]

static func _leaf_mat(autumn: float) -> ShaderMaterial:
	var key := "leaf%.2f" % autumn
	if not _c.has(key):
		var m := ShaderMaterial.new()
		m.shader = FOLIAGE_SHADER
		m.set_shader_parameter("leaf_tex", load(LEAF_TEX))
		# gedecktes Spaetsommergruen, mit autumn Richtung Gelb-/Braunstich
		m.set_shader_parameter("tint", Color(0.38, 0.44, 0.24).lerp(Color(0.5, 0.42, 0.2), autumn))
		m.set_shader_parameter("tint2", Color(0.5, 0.52, 0.27).lerp(Color(0.62, 0.46, 0.2), autumn))
		m.set_shader_parameter("backlight_color", Color(0.2, 0.24, 0.07))
		m.set_shader_parameter("wind", 0.03)
		m.set_shader_parameter("alpha_cut", 0.45)
		m.set_shader_parameter("shade_floor", 0.3)
		_c[key] = m
	return _c[key]

## Baum-Mesh (Flaeche 0 Rinde, Flaeche 1 Laub). v = Variante (Art = v % SPECIES.size()).
static func mesh(v: int, lod: int, autumn: float = 0.15) -> ArrayMesh:
	var key := "t%d_%d_%.2f" % [v, lod, autumn]
	if _c.has(key):
		return _c[key]
	var sp := v % SPECIES.size()
	var cfg: Dictionary = SPECIES[sp]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7310 + v * 191
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tips: Array[Vector3] = []
	var max_depth := 3 if lod == 0 else 1
	var h: float = cfg["h"] * rng.randf_range(0.92, 1.08)
	var r0: float = cfg["r"]
	var crown_y := h * (0.36 if sp != 2 else 0.25)
	var lean := Vector3(rng.randf_range(-0.1, 0.1), 1.0, rng.randf_range(-0.1, 0.1)).normalized()
	var trunk_top := TT._limb(st, Vector3(0, -0.3, 0), lean, h * (0.7 if sp != 1 else 0.5), r0 * 1.3, r0 * 0.35, 4 if lod == 0 else 2, 9 if lod == 0 else 5, rng, 0.05)
	var limbs: int = cfg["limbs"]
	for k in limbs:
		var t := float(k) / float(limbs)
		var a := TAU * t * 1.618 + rng.randf_range(-0.3, 0.3)
		var y := crown_y + (trunk_top.y - crown_y) * pow(t, 0.8)
		var p := Vector3(lean.x, 0, lean.z) * (y / lean.y) + Vector3(0, y, 0)
		var dir := Vector3(cos(a) * float(cfg["spread"]), float(cfg["up"]) + rng.randf_range(-0.1, 0.25), sin(a) * float(cfg["spread"])).normalized()
		var L := h * rng.randf_range(0.3, 0.42) * (1.0 - t * 0.45)
		TT._branch(st, p, dir, L, r0 * lerpf(0.55, 0.3, t), 1, max_depth, rng, tips, cfg)
	st.generate_tangents()
	var m := st.commit()
	m.surface_set_material(0, _bark_mat(sp))
	# Krone: Kartenbueschel an den Zweigspitzen + Fuellung im Kronen-Ellipsoid (Huelle dichter)
	var cr: Vector3 = cfg["crown"]
	var cc := Vector3(lean.x, 0, lean.z) * (h * float(cfg["cy"])) + Vector3(0, h * float(cfg["cy"]), 0)
	var ls := SurfaceTool.new()
	ls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_cards: int = cfg["cards"]
	if lod == 1:
		n_cards = int(n_cards * 0.35)
	var size_k := 1.0 if lod == 0 else 1.55
	for i in n_cards:
		var c: Vector3
		if i % 2 == 0 and not tips.is_empty():
			c = tips[rng.randi() % tips.size()] + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.6), rng.randf_range(-0.5, 0.5))
		else:
			var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			if d.length() < 0.05:
				d = Vector3.UP
			d = d.normalized()
			var rr := pow(rng.randf(), 0.35)
			c = cc + Vector3(d.x * cr.x, d.y * cr.y * 0.9, d.z * cr.z) * rr
		var rel := c - cc
		var radial := Vector3(rel.x / cr.x, rel.y / cr.y, rel.z / cr.z).length()
		var outward := rel.normalized() if rel.length() > 0.05 else Vector3.UP
		var nd := (outward * 1.2 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.6).normalized()
		var s := rng.randf_range(1.3, 2.0) * size_k
		var tx := nd.cross(Vector3.UP)
		if tx.length() < 0.15:
			tx = nd.cross(Vector3.RIGHT)
		tx = tx.normalized()
		var ty := tx.cross(nd).normalized()
		var rot := rng.randf() * TAU
		var ax := (tx * cos(rot) + ty * sin(rot)) * s * 0.5
		var ay := (-tx * sin(rot) + ty * cos(rot)) * s * 0.5
		var shade := clampf(radial * 0.75 + (outward.y * 0.5 + 0.5) * 0.35, 0.0, 1.0)
		var col := Color(clampf(radial, 0.0, 1.0), rng.randf(), shade)
		var pts: Array[Vector3] = [c - ax - ay, c + ax - ay, c + ax + ay, c - ax + ay]
		var uvs: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			var n := ((pts[idx] - (cc - Vector3(0, cr.y * 0.3, 0))).normalized() + Vector3.UP * 0.25).normalized()
			ls.set_color(col)
			ls.set_normal(n)
			ls.set_uv(uvs[idx])
			ls.add_vertex(pts[idx])
	ls.commit(m)
	m.surface_set_material(1, _leaf_mat(autumn))
	_c[key] = m
	return m

## Baeume pflanzen. trees: Array von [Vector3 fuss, float skalierung] oder [Vector3, float, int variante].
## Gruppiert je Variante und Zelle (cell m) fuer Culling und Sichtweiten-LOD.
## opts: "collide" (bool, Stammzylinder), "shadows" (bool), "autumn" (0..1), "cell" (m), "hi_end" (m)
static func plant(parent: Node3D, trees: Array, rng: RandomNumberGenerator, opts: Dictionary = {}) -> void:
	var cell: float = opts.get("cell", 60.0)
	var autumn: float = opts.get("autumn", 0.15)
	var shadows: bool = opts.get("shadows", true)
	var hi_end: float = opts.get("hi_end", HI_END)
	var groups: Dictionary = {}
	var body: StaticBody3D = null
	for t: Array in trees:
		var p: Vector3 = t[0]
		var s: float = t[1]
		var v: int = t[2] if t.size() > 2 else rng.randi() % VARIANTS
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.9, 1.1), s * rng.randf_range(0.92, 1.08), s * rng.randf_range(0.9, 1.1)))
		var key := "%d|%d_%d" % [v, floori(p.x / cell), floori(p.z / cell)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(Transform3D(b, p))
		if opts.get("collide", false):
			if body == null:
				body = Geo.static_body()
				body.name = "LeafTreeTrunks"
				body.set_meta("surface", "wood")
			var cs := CollisionShape3D.new()
			var sh := CylinderShape3D.new()
			sh.radius = float(SPECIES[v % SPECIES.size()]["r"]) * 1.2 * s + 0.05
			sh.height = 6.0
			cs.shape = sh
			cs.position = p + Vector3(0, 3.0, 0)
			body.add_child(cs)
	for key: String in groups:
		var v := int(key.get_slice("|", 0))
		var xs: Array = groups[key]
		parent.add_child(_mmi(mesh(v, 0, autumn), xs, 0.0, hi_end, shadows))
		parent.add_child(_mmi(mesh(v, 1, autumn), xs, hi_end, 0.0, shadows))
	if body != null:
		parent.add_child(body)

static func _mmi(m: Mesh, xs: Array, vis_begin: float, vis_end: float, shadows: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mi := MultiMeshInstance3D.new()
	mi.name = "LeafTrees"
	mi.multimesh = mm
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if vis_begin > 0.0:
		mi.visibility_range_begin = vis_begin
		mi.visibility_range_begin_margin = 8.0
	if vis_end > 0.0:
		mi.visibility_range_end = vis_end
		mi.visibility_range_end_margin = 8.0
	return mi
