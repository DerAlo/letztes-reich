extends RefCounted
## Kleiner Mesh-Baukasten fuer die prozeduralen Fahrzeuge: sammelt Dreiecke in einem Puffer und
## erzeugt daraus EIN ArrayMesh (ein Draw Call je Baugruppe).
## Vertex-Farbe = Materialkanal fuer vehicle_paint.gdshader:
##   r = Lack (1) / blankes Metall (0), g = Gummi, b = Akzentfarbe, a = Helligkeit (Abschattung/Panelton).
## CUSTOM0 = (Drehzentrum y, z, Radius, 0) fuer im Shader drehende Raeder (Radius 0 = starr).
## Godot: Vorderseite = im Uhrzeigersinn von aussen; tri()/quad() orientieren selbst ueber einen Aussen-Hinweis.

var verts := PackedVector3Array()
var norms := PackedVector3Array()
var cols := PackedColorArray()
var custom := PackedFloat32Array()
var xf := Transform3D.IDENTITY
var color := Color(1, 0, 0, 1)
var wheel := Vector3.ZERO   # (y, z, r) des aktuellen Rades
var use_custom := false

const PAINT := Color(1, 0, 0, 1)
const METAL := Color(0, 0, 0, 1)
const RUBBER := Color(0, 1, 0, 1)
const ACCENT := Color(1, 0, 1, 1)   # Akzent liegt auf dem Lack (r = 1)

static func shade(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

func _v(p: Vector3, n: Vector3) -> void:
	verts.append(xf * p)
	norms.append((xf.basis * n).normalized())
	cols.append(color)
	custom.append(wheel.x)
	custom.append(wheel.y)
	custom.append(wheel.z)
	custom.append(0.0)

## Flaches Dreieck; `out` = ungefaehre Aussenrichtung.
func tri(a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot(out) > 0.0:
		_v(a, n)
		_v(c, n)
		_v(b, n)
	else:
		_v(a, -n)
		_v(b, -n)
		_v(c, -n)

## Dreieck mit eigenen Vertex-Normalen (glatt); Orientierung nach der Flaechennormale.
func tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	if n.dot(na + nb + nc) > 0.0:
		_v(a, na)
		_v(c, nc)
		_v(b, nb)
	else:
		_v(a, na)
		_v(b, nb)
		_v(c, nc)

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3) -> void:
	var m := (a + b + c + d) * 0.25 - center
	tri(a, b, c, m)
	tri(a, c, d, m)

func quad_n(a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	tri_n(a, b, c, na, nb, nc)
	tri_n(a, c, d, na, nc, nd)

## Lokale Transformation fuer die naechsten Bausteine setzen (Rueckgabe = alte, zum Zuruecksetzen).
func push(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Transform3D:
	var old := xf
	var r := rot_deg * (PI / 180.0)
	xf = xf * Transform3D(Basis.from_euler(r), pos)
	return old

# ------------------------------------------------------------------ Grundkoerper

## Quader mit gefasten Kanten (Fase `bevel`), zentriert in `pos`.
func cbox(pos: Vector3, size: Vector3, bevel: float = 0.03, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var old := push(pos, rot_deg)
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.95)
	var cyc: Array[Vector2] = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for a in 3:
		var o1 := (a + 1) % 3
		var o2 := (a + 2) % 3
		for s: float in [-1.0, 1.0]:
			var pts: Array[Vector3] = []
			for cc: Vector2 in cyc:
				var c := Vector3.ZERO
				c[a] = s
				c[o1] = cc.x
				c[o2] = cc.y
				pts.append(_cp(c, a, h, b))
			quad(pts[0], pts[1], pts[2], pts[3], Vector3.ZERO)
	if b > 0.0005:
		for pr: Vector2i in [Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2)]:
			var a := pr.x
			var bb := pr.y
			var k := 3 - a - bb
			for sa: float in [-1.0, 1.0]:
				for sb: float in [-1.0, 1.0]:
					var c0 := Vector3.ZERO
					c0[a] = sa
					c0[bb] = sb
					c0[k] = -1.0
					var c1 := c0
					c1[k] = 1.0
					quad(_cp(c0, a, h, b), _cp(c1, a, h, b), _cp(c1, bb, h, b), _cp(c0, bb, h, b), Vector3.ZERO)
		for sx: float in [-1.0, 1.0]:
			for sy: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					var c := Vector3(sx, sy, sz)
					tri(_cp(c, 0, h, b), _cp(c, 1, h, b), _cp(c, 2, h, b), c)
	xf = old

static func _cp(c: Vector3, a: int, h: Vector3, b: float) -> Vector3:
	var p := Vector3(c.x * (h.x - b), c.y * (h.y - b), c.z * (h.z - b))
	p[a] = c[a] * h[a]
	return p

## Verbindet aufeinanderfolgende Ringe (gleiche Punktzahl, geschlossen) und deckelt die Enden.
## smooth = weiche Normalen rund um den Ring (harte Kanten zwischen den Ringen bleiben).
func loft(rings: Array[PackedVector3Array], cap0: bool = true, cap1: bool = true, smooth: bool = false) -> void:
	var nr := rings.size()
	if nr < 2:
		return
	var np := rings[0].size()
	var cents: Array[Vector3] = []
	for r in rings:
		var c := Vector3.ZERO
		for p in r:
			c += p
		cents.append(c / float(r.size()))
	for i in nr - 1:
		var ra := rings[i]
		var rb := rings[i + 1]
		var axis := (cents[i] + cents[i + 1]) * 0.5
		if not smooth:
			for j in np:
				var j2 := (j + 1) % np
				quad(ra[j], ra[j2], rb[j2], rb[j], axis)
		else:
			# Flaechennormalen je Segment, Vertex-Normale = Mittel der beiden Nachbarsegmente
			var fn: Array[Vector3] = []
			for j in np:
				var j2 := (j + 1) % np
				var n := (ra[j2] - ra[j]).cross(rb[j] - ra[j])
				if n.length_squared() < 1e-14:
					n = (rb[j2] - rb[j]).cross(rb[j] - ra[j])
				var m := (ra[j] + ra[j2] + rb[j] + rb[j2]) * 0.25 - axis
				if n.dot(m) < 0.0:
					n = -n
				fn.append(n.normalized())
			for j in np:
				var j2 := (j + 1) % np
				var n_j := (fn[j] + fn[(j - 1 + np) % np]).normalized()
				var n_j2 := (fn[j] + fn[j2]).normalized()
				quad_n(ra[j], ra[j2], rb[j2], rb[j], n_j, n_j2, n_j2, n_j)
	if cap0:
		_cap(rings[0], cents[0], cents[0] - cents[1])
	if cap1:
		_cap(rings[nr - 1], cents[nr - 1], cents[nr - 1] - cents[nr - 2])

func _cap(r: PackedVector3Array, c: Vector3, out: Vector3) -> void:
	for j in r.size():
		tri(c, r[j], r[(j + 1) % r.size()], out)

## Drehkoerper um `axis` durch `origin`. prof = (Position entlang Achse, Radius); Radius 0 schliesst.
## band_cols: optional eine Farbe je Profilabschnitt (sonst `color`). smooth = weich rundherum.
func lathe(origin: Vector3, axis: Vector3, prof: PackedVector2Array, seg: int = 16, smooth: bool = true, band_cols: Array = [], phase: float = 0.0) -> void:
	var ax := axis.normalized()
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
	var w := ax.cross(u).normalized()
	var keep := color
	for i in prof.size() - 1:
		var p0 := prof[i]
		var p1 := prof[i + 1]
		if i < band_cols.size() and band_cols[i] is Color:
			color = band_cols[i]
		else:
			color = keep
		var dt := p1.x - p0.x
		var dr := p1.y - p0.y
		for j in seg:
			var a0 := phase + TAU * float(j) / float(seg)
			var a1 := phase + TAU * float(j + 1) / float(seg)
			var r0 := u * cos(a0) + w * sin(a0)
			var r1 := u * cos(a1) + w * sin(a1)
			var v00 := origin + ax * p0.x + r0 * p0.y
			var v01 := origin + ax * p0.x + r1 * p0.y
			var v10 := origin + ax * p1.x + r0 * p1.y
			var v11 := origin + ax * p1.x + r1 * p1.y
			if smooth:
				var n0 := (ax * -dr + r0 * dt).normalized()
				var n1 := (ax * -dr + r1 * dt).normalized()
				if p0.y < 0.0001:
					tri_n(v00, v11, v10, n0, n1, n0)
				elif p1.y < 0.0001:
					tri_n(v00, v01, v10, n0, n1, n0)
				else:
					quad_n(v00, v01, v11, v10, n0, n1, n1, n0)
			else:
				var rm := (r0 + r1).normalized()
				var out := ax * -dr + rm * dt
				if p0.y < 0.0001:
					tri(v00, v11, v10, out)
				elif p1.y < 0.0001:
					tri(v00, v01, v10, out)
				else:
					quad(v00, v01, v11, v10, v00 - out)
	color = keep

## Einfacher Zylinder (Achse a -> b) mit Deckeln.
func cyl(a: Vector3, b: Vector3, r: float, seg: int = 12, smooth: bool = true) -> void:
	var l := a.distance_to(b)
	lathe(a, b - a, PackedVector2Array([Vector2(0, 0), Vector2(0, r), Vector2(l, r), Vector2(l, 0)]), seg, smooth)

## Prisma: Profil (z, y) quer extrudiert von x0 bis x1, Seitenkanten um `bevel` gefast.
func prism_x(prof: PackedVector2Array, x0: float, x1: float, bevel: float = 0.04) -> void:
	var inner := offset_poly(prof, -bevel)
	var rings: Array[PackedVector3Array] = []
	if bevel > 0.0005:
		rings.append(_ring_x(inner, x0))
		rings.append(_ring_x(prof, x0 + bevel))
		rings.append(_ring_x(prof, x1 - bevel))
		rings.append(_ring_x(inner, x1))
	else:
		rings.append(_ring_x(prof, x0))
		rings.append(_ring_x(prof, x1))
	loft(rings)

static func _ring_x(p: PackedVector2Array, x: float) -> PackedVector3Array:
	var r := PackedVector3Array()
	for q in p:
		r.append(Vector3(x, q.y, q.x))
	return r

## Ring aus 2D-Grundriss (x, z) auf Hoehe y.
static func ring_y(p: PackedVector2Array, y: float) -> PackedVector3Array:
	var r := PackedVector3Array()
	for q in p:
		r.append(Vector3(q.x, y, q.y))
	return r

## Konvexes Polygon nach aussen (d > 0) oder innen (d < 0) versetzen (Gehrung an den Ecken).
static func offset_poly(p: PackedVector2Array, d: float) -> PackedVector2Array:
	var n := p.size()
	var area := 0.0
	for i in n:
		var a := p[i]
		var b := p[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var s := 1.0 if area > 0.0 else -1.0
	var out := PackedVector2Array()
	for i in n:
		var a := p[(i - 1 + n) % n]
		var b := p[i]
		var c := p[(i + 1) % n]
		var e1 := (b - a).normalized()
		var e2 := (c - b).normalized()
		var n1 := Vector2(e1.y, -e1.x) * s
		var n2 := Vector2(e2.y, -e2.x) * s
		var m := (n1 + n2).normalized()
		var cs := maxf(m.dot(n1), 0.3)
		out.append(b + m * (d / cs))
	return out

## Superellipse-Ring (Grundriss) mit Halbachsen rx, rz und Exponent e (2 = Ellipse, groesser = eckiger).
static func superellipse(rx: float, rz: float, e: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		var c := cos(a)
		var s := sin(a)
		out.append(Vector2(signf(c) * pow(absf(c), 2.0 / e) * rx, signf(s) * pow(absf(s), 2.0 / e) * rz))
	return out

# ------------------------------------------------------------------ Ausgabe

func commit() -> ArrayMesh:
	var am := ArrayMesh.new()
	if verts.is_empty():
		return am
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	var flags := 0
	if use_custom:
		arr[Mesh.ARRAY_CUSTOM0] = custom
		flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, flags)
	return am

## Mesh erzeugen und als MeshInstance3D anhaengen.
func emit(parent: Node3D, m: Material, node_name: String = "Mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = commit()
	mi.material_override = m
	parent.add_child(mi)
	return mi

func tri_count() -> int:
	return verts.size() / 3
