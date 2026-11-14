extends RefCounted
## Mesh-Baukasten fuer die Waermebild-Welt der Gunship-Mission.
## Haengt Primitive (Box, Zylinder, Kugel, Prisma) mit Transform und Temperatur an ein gemeinsames Surface an.
## Vertex-Farbe: r = Temperatur, g = Rausch-Variation, b = Formschattierung (siehe thermal.gdshader).
## Statische Materialien/Rauschtextur werden einmal angelegt und von allen Modulen geteilt.

const SH_OBJ := preload("res://game/gunship/thermal.gdshader")
const SH_GROUND := preload("res://game/gunship/thermal_ground.gdshader")
const SH_SPRITE := preload("res://game/gunship/thermal_sprite.gdshader")
const SH_PART := preload("res://game/gunship/thermal_particle.gdshader")
const SH_PART_ADD := preload("res://game/gunship/thermal_particle_add.gdshader")
const SH_DECAL := preload("res://game/gunship/thermal_decal.gdshader")

static var _noise: NoiseTexture2D = null
static var _mats: Dictionary = {}
static var _prims: Dictionary = {}

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _i := PackedInt32Array()

# ------------------------------------------------------------------ Materialien

static func noise_tex() -> NoiseTexture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.018
		fn.fractal_octaves = 4
		fn.seed = 1944
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.noise = fn
	return _noise

static func mat(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	var m := ShaderMaterial.new()
	match kind:
		"ground":
			m.shader = SH_GROUND
		"sprite":
			m.shader = SH_SPRITE
		"particle":
			m.shader = SH_PART
		"particle_add":
			m.shader = SH_PART_ADD
		"decal":
			m.shader = SH_DECAL
		"forest":
			m.shader = SH_OBJ
			m.set_shader_parameter("custom_heat_amt", 0.12)
			m.set_shader_parameter("noise_scale", 0.35)
		_:
			m.shader = SH_OBJ
	if kind != "sprite":
		m.set_shader_parameter("noise_tex", noise_tex())
	_mats[kind] = m
	return m

# ------------------------------------------------------------------ Aufbau

func is_empty() -> bool:
	return _v.is_empty()

## Fuegt ein beliebiges Primitive an. heat_bot/heat_top: Temperatur unten/oben (lokales y, -0.5..0.5 der Hoehe).
func add_prim(pm: PrimitiveMesh, xf: Transform3D, heat_bot: float, heat_top: float = -1.0, var_amt: float = 0.03, shade: float = 1.0) -> void:
	if heat_top < 0.0:
		heat_top = heat_bot
	var arr: Array = pm.get_mesh_arrays()
	var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var pn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var pi: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var aabb := pm.get_aabb()
	var y0 := aabb.position.y
	var hy := maxf(aabb.size.y, 0.0001)
	var base := _v.size()
	var nb := xf.basis.inverse().transposed()
	for k in pv.size():
		var p: Vector3 = pv[k]
		_v.append(xf * p)
		_n.append((nb * pn[k]).normalized())
		var t := clampf((p.y - y0) / hy, 0.0, 1.0)
		_c.append(Color(lerpf(heat_bot, heat_top, t), var_amt, shade, 1.0))
	if pi.is_empty():
		for k in pv.size():
			_i.append(base + k)
	else:
		for k in pi.size():
			_i.append(base + pi[k])

func box(center: Vector3, size: Vector3, heat: float, yaw: float = 0.0, heat_top: float = -1.0, var_amt: float = 0.03, shade: float = 1.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(size), center)
	add_prim(_prim("box"), xf, heat, heat_top, var_amt, shade)

## Box mit freier Basis (z. B. geneigte Teile). basis enthaelt Rotation, size wird lokal skaliert.
func box_b(center: Vector3, basis: Basis, size: Vector3, heat: float, heat_top: float = -1.0, var_amt: float = 0.03) -> void:
	add_prim(_prim("box"), Transform3D(basis * Basis.from_scale(size), center), heat, heat_top, var_amt)

## Zylinder (stehend). r = Radius, h = Hoehe, center = Mittelpunkt.
func cyl(center: Vector3, r: float, h: float, heat: float, segs: int = 12, heat_top: float = -1.0, basis: Basis = Basis(), var_amt: float = 0.03, r_top: float = -1.0) -> void:
	var key := "cyl%d_%s" % [segs, "c" if r_top < 0.0 else str(snappedf(r_top / r, 0.01))]
	var pm: PrimitiveMesh = _prims.get(key)
	if pm == null:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.5 if r_top < 0.0 else 0.5 * r_top / r
		cm.bottom_radius = 0.5
		cm.height = 1.0
		cm.radial_segments = segs
		cm.rings = 1
		_prims[key] = cm
		pm = cm
	add_prim(pm, Transform3D(basis * Basis.from_scale(Vector3(r * 2.0, h, r * 2.0)), center), heat, heat_top, var_amt)

func sphere(center: Vector3, size: Vector3, heat: float, heat_top: float = -1.0, var_amt: float = 0.03) -> void:
	add_prim(_prim("sphere"), Transform3D(Basis.from_scale(size), center), heat, heat_top, var_amt)

## Unregelmaessiger Klumpen (Baumkrone): Kugel mit rauschverschobener Oberflaeche, glatte Normalen.
## seed variiert die Form, amp = relative Beulentiefe, segs/rings = Aufloesung.
func lump(center: Vector3, size: Vector3, heat: float, heat_top: float = -1.0, var_amt: float = 0.05,
		seed: int = 0, amp: float = 0.28, segs: int = 8, rings: int = 5) -> void:
	if heat_top < 0.0:
		heat_top = heat
	var base := _v.size()
	var ph := float(seed) * 1.731
	for r in rings + 1:
		var v := float(r) / float(rings)
		var th := v * PI
		for s in segs + 1:
			var u := float(s % segs) / float(segs)
			var fi := u * TAU
			var dir := Vector3(sin(th) * cos(fi), cos(th), sin(th) * sin(fi))
			# Beulen: Summe weniger Sinuswellen auf der Kugel (Pole stabil)
			var b := sin(dir.x * 3.1 + ph) * sin(dir.z * 2.7 + ph * 1.3) + 0.6 * sin(dir.y * 4.3 + dir.x * 2.0 + ph * 0.7)
			var k := 1.0 + amp * b * 0.6
			if r == rings:
				k *= 0.82   # Unterseite flacher (Krone haengt nicht als Kugel nach unten)
			var p := Vector3(dir.x * size.x, dir.y * size.y, dir.z * size.z) * 0.5 * k
			_v.append(center + p)
			_n.append(Vector3(dir.x / size.x, dir.y / size.y, dir.z / size.z).normalized())
			_c.append(Color(lerpf(heat, heat_top, 1.0 - v), var_amt, 1.0, 1.0))
	for r in rings:
		for s in segs:
			var a := base + r * (segs + 1) + s
			var c := a + segs + 1
			_i.append_array([a, c, a + 1, a + 1, c, c + 1])

## Fichten-Etage: sternfoermiger Kegel (2n Zacken), Unterkante leicht haengend.
func star_cone(y0: float, h: float, r: float, heat: float, heat_top: float, var_amt: float = 0.05,
		n: int = 7, seed: int = 0, off: Vector3 = Vector3.ZERO) -> void:
	var base := _v.size()
	var tip := off + Vector3(0, y0 + h, 0)
	var rot := float(seed) * 0.9
	for k in n * 2:
		var a := rot + TAU * float(k) / float(n * 2)
		var rr := r * (1.0 if k % 2 == 0 else 0.58) * (1.0 + 0.12 * sin(float(k * 7 + seed)))
		var droop := -0.28 * h if k % 2 == 0 else 0.0
		var p := off + Vector3(cos(a) * rr, y0 + droop, sin(a) * rr)
		_v.append(p)
		_n.append(Vector3(cos(a), 0.55, sin(a)).normalized())
		_c.append(Color(heat, var_amt, 1.0, 1.0))
	_v.append(tip)
	_n.append(Vector3.UP)
	_c.append(Color(heat_top, var_amt, 1.0, 1.0))
	var ctr := off + Vector3(0, y0 + 0.1 * h, 0)
	_v.append(ctr)
	_n.append(Vector3.DOWN)
	_c.append(Color(heat + 0.02, var_amt, 1.0, 1.0))
	var ti := base + n * 2
	var ci := ti + 1
	for k in n * 2:
		var a := base + k
		var b := base + (k + 1) % (n * 2)
		_i.append_array([a, b, ti, a, ci, b])

## Dreiecksprisma (Dachfirst laengs x). size: x Laenge, y Hoehe, z Breite.
func prism(center: Vector3, size: Vector3, heat: float, yaw: float = 0.0, heat_top: float = -1.0) -> void:
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(size.z, size.y, size.x)), center)
	add_prim(_prim("prism"), xf, heat, heat_top)

func _prim(kind: String) -> PrimitiveMesh:
	if _prims.has(kind):
		return _prims[kind]
	var pm: PrimitiveMesh
	match kind:
		"box":
			var b := BoxMesh.new()
			b.size = Vector3.ONE
			pm = b
		"sphere":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 1.0
			s.radial_segments = 10
			s.rings = 6
			pm = s
		"prism":
			var p := PrismMesh.new()
			p.size = Vector3.ONE
			pm = p
	_prims[kind] = pm
	return pm

func commit(existing: ArrayMesh = null) -> ArrayMesh:
	var am := existing if existing != null else ArrayMesh.new()
	if _v.is_empty():
		return am
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _v
	arr[Mesh.ARRAY_NORMAL] = _n
	arr[Mesh.ARRAY_COLOR] = _c
	arr[Mesh.ARRAY_INDEX] = _i
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

## Fertige MeshInstance mit dem geteilten Waermebild-Material.
func instance(parent: Node, mname: String = "Mesh", mat_kind: String = "obj") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mname
	mi.mesh = commit()
	mi.material_override = mat(mat_kind)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
