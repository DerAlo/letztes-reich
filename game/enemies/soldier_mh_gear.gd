extends RefCounted
## Ausruestung fuer die realistischen MakeHuman-Soldaten (assets/characters/soldier_mh, soldier_visual.gd).
## Alle Masse in Metern im Skelettraum der Variante "a" (1,67 m; +Y oben, +Z vorne, +X linke Koerperseite).
## soldier_visual.gd haengt jede Baugruppe an einem ruhepose-ausgerichteten Rahmen am Knochen an und skaliert
## die Hoehe fuer die Varianten b/c (Huefthoehe / 0,915).
## Alles selbst modelliert (prozedural, CC0); Abzeichen sind erfunden.
##
## Bauweise (Gear-Realismus-Pass): statt gefaster Quader gepolsterte Stoffkoerper mit runden Kanten und
## Woelbung (_slab), Riemen/Gurte als gefegte Profile (_sweep), Helm als Schale mit Kantenschutz, Ohrausschnitt,
## Schienen und NVG-Halterung (_helmet). Feinstruktur (Gewebe, MOLLE-Reihen, Naehte, Strick, Lackkoernung)
## liefert soldier_mh_gear.gdshader aus Materialcode (Vertexfarbe Alpha) + Nahtdaten (CUSTOM0).
## Meshes werden je Fraktion/Rolle/Baugruppe einmal gebaut, indiziert und mit LODs gecacht (mesh()).

const SG = preload("res://game/enemies/soldier_gear.gd")
const MK = preload("res://game/vehicles/models/mesh_kit.gd")
const GEAR_SHADER := "res://game/enemies/soldier_mh_gear.gdshader"
const WEAVE_TEX := "res://assets/characters/textures/rough_linen/diffuse.jpg"

## Huefthoehe der Referenzvariante (Skalierungsbasis)
const REF_HIPS_Y := 0.915
## Knochen je Baugruppe
const GROUP_BONE := {"chest": "Chest", "hips": "Hips", "head": "Head"}
## Neigung der Plattentraeger-Vorderseite (Grad, oben nach hinten)
const FRONT_TILT := -12.0

## Materialcodes (Vertexfarbe Alpha * 15, siehe soldier_mh_gear.gdshader)
const MAT_PAINT := 0
const MAT_HARD := 1
const MAT_NYLON := 2
const MAT_MOLLE := 3
const MAT_WEB := 4
const MAT_KNIT := 5
const MAT_JUTE := 6
const MAT_RUBBER := 7
const MAT_LENS := 8
const MAT_CAMO := 9
const MAT_CAMO_MOLLE := 10
const MAT_LEATHER := 11
const MAT_FELT := 12
const MAT_METAL := 13

## Helmschale (Ellipsoid): Mitte und Halbachsen; Randwinkel (Grad ab Scheitel) ueber dem Azimut (0 = vorne)
const REF_HEAD := Vector3(0.0, 1.5483, 0.0472)   ## Kopfknoten Variante a (Kopf-Ausruestung wird nur verschoben)
const H_C := Vector3(0.0, 1.58, 0.06)
const H_R := Vector3(0.103, 0.109, 0.122)
const HIGH_CUT := [[0.0, 74.0], [25.0, 77.0], [45.0, 82.0], [62.0, 76.0], [80.0, 63.0], [100.0, 63.0], [118.0, 78.0], [140.0, 95.0], [180.0, 101.0]]
const FULL_CUT := [[0.0, 75.0], [40.0, 85.0], [80.0, 96.0], [130.0, 102.0], [180.0, 103.0]]

static var _mats := {}
static var _meshes := {}

## Ausruestungsfarben je Fraktion [Cordura, dunkel/Gurtband, Metall/Kunststoff, Akzent].
## ru/reich wie soldier_gear.gear_colors(); Garde schwarzgrau, Wintergarde hellgrau, Widerstand zivil-braun.
static func colors(faction: String) -> Array[Color]:
	match faction:
		"garde":
			return [Color(0.075, 0.078, 0.085), Color(0.035, 0.036, 0.04), Color(0.12, 0.12, 0.125), Color(0.5, 0.5, 0.52)]
		"garde_winter":
			return [Color(0.34, 0.35, 0.36), Color(0.11, 0.115, 0.12), Color(0.2, 0.2, 0.21), Color(0.6, 0.6, 0.62)]
		"resistance":
			return [Color(0.17, 0.14, 0.09), Color(0.06, 0.055, 0.045), Color(0.12, 0.12, 0.11), Color(0.3, 0.26, 0.18)]
	return SG.gear_colors(faction)

## Ausruestungsmaterial je Fraktion (ru: Traeger/Taschen/Helmbezug im Tarnmuster; reich: Helm stahlgrau, leicht metallisch).
static func gear_mat(faction: String) -> ShaderMaterial:
	if _mats.has(faction):
		return _mats[faction]
	var m := ShaderMaterial.new()
	m.shader = load(GEAR_SHADER)
	if ResourceLoader.exists(WEAVE_TEX):
		m.set_shader_parameter("weave_tex", load(WEAVE_TEX))
	if faction == "ru" and ResourceLoader.exists(SG.CAMO_TEX["ru"]):
		m.set_shader_parameter("camo_tex", load(SG.CAMO_TEX["ru"]))
		m.set_shader_parameter("use_camo", true)
		m.set_shader_parameter("camo_mul", Color(0.86, 0.86, 0.84))
	if faction == "reich":
		m.set_shader_parameter("paint_metal", 0.12)
		m.set_shader_parameter("paint_rough", 0.45)
	if faction == "garde_winter":
		m.set_shader_parameter("wear", 0.15)
	_mats[faction] = m
	return m

## Fertiges (gecachtes) Mesh einer Baugruppe mit LODs; null, wenn die Baugruppe leer ist.
static func mesh(faction: String, role: String, heavy: bool, group: String) -> Mesh:
	var key := "%s|%s|%s|%s" % [faction, role, heavy, group]
	if _meshes.has(key):
		return _meshes[key]
	var k := MK.new()
	match group:
		"chest":
			build_chest(k, faction, role, heavy)
		"hips":
			build_hips(k, faction)
		"head":
			build_head(k, faction, role)
	var m: Mesh = null if k.verts.is_empty() else _finish(k)
	_meshes[key] = m
	return m

## Nicht indizierte MeshKit-Daten -> indiziertes Mesh mit CUSTOM0 (Nahtdaten) und automatisch erzeugten LODs.
static func _finish(k: MK) -> Mesh:
	var idx := {}
	var vv := PackedVector3Array()
	var nn := PackedVector3Array()
	var cc := PackedColorArray()
	var ww := PackedFloat32Array()
	var ii := PackedInt32Array()
	for i in k.verts.size():
		var w := Vector3(k.custom[i * 4], k.custom[i * 4 + 1], k.custom[i * 4 + 2])
		var key := [k.verts[i].snapped(Vector3.ONE * 0.00002), k.norms[i].snapped(Vector3.ONE * 0.002), k.cols[i], w.snapped(Vector3.ONE * 0.0001)]
		var at: int = idx.get(key, -1)
		if at < 0:
			at = vv.size()
			idx[key] = at
			vv.append(k.verts[i])
			nn.append(k.norms[i])
			cc.append(k.cols[i])
			ww.append_array(PackedFloat32Array([w.x, w.y, w.z, 0.0]))
		ii.append(at)
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vv
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_COLOR] = cc
	arr[Mesh.ARRAY_CUSTOM0] = ww
	arr[Mesh.ARRAY_INDEX] = ii
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, null, "Gear", Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

## Vorderseite des Traegers (Mitte der Platte) auf Hoehe y
static func _front_z(y: float, heavy: bool) -> float:
	return (0.172 if heavy else 0.165) - (y - 1.25) * tan(deg_to_rad(-FRONT_TILT))

static func _ring(rx: float, rz: float, y: float, cz: float, n: int = 22, e: float = 2.4) -> PackedVector3Array:
	var r := PackedVector3Array()
	for p in MK.superellipse(rx, rz, e, n):
		r.append(Vector3(p.x, y, p.y + cz))
	return r

## Farbe mit Materialcode
static func _c(col: Color, code: int) -> Color:
	return Color(col.r, col.g, col.b, float(code) / 15.0)

# ------------------------------------------------------------------ Grundformen

## Abgerundetes Rechteck (halbe Groessen, Eckradius r, nc Segmente je Ecke), gegen den Uhrzeigersinn.
static func _rrect(hx: float, hy: float, r: float, nc: int) -> PackedVector2Array:
	hx = maxf(hx, 0.0004)
	hy = maxf(hy, 0.0004)
	r = clampf(r, 0.0002, minf(hx, hy))
	var out := PackedVector2Array()
	var cs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for ci in 4:
		var c: Vector2 = cs[ci]
		var cen := Vector2(c.x * (hx - r), c.y * (hy - r))
		for j in nc + 1:
			var a := PI * 0.5 * (float(ci) + float(j) / float(nc))
			out.append(cen + Vector2(cos(a), sin(a)) * r)
	return out

## Dreieck mit Normalen und Nahtdaten (CUSTOM0); Wicklung folgt den Normalen.
static func _tri(k: MK, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, wa: Vector3, wb: Vector3, wc: Vector3) -> void:
	var f := (b - a).cross(c - a)
	if f.length_squared() < 1e-20:
		return
	if f.dot(na + nb + nc) > 0.0:
		k.wheel = wa
		k._v(a, na)
		k.wheel = wc
		k._v(c, nc)
		k.wheel = wb
		k._v(b, nb)
	else:
		k.wheel = wa
		k._v(a, na)
		k.wheel = wb
		k._v(b, nb)
		k.wheel = wc
		k._v(c, nc)
	k.wheel = Vector3.ZERO

## Flaechengitter aus geschlossenen Reihen (gleiche Punktzahl). Normalen aus zentralen Differenzen,
## Ausrichtung so, dass die mittlere Reihe von refs weg zeigt. wd = Nahtdaten je Punkt, row_cols = Farbe je Reihenband.
static func _grid(k: MK, rows: Array[PackedVector3Array], refs: PackedVector3Array, wd: Array = [], row_cols: Array = [], wrap: bool = true) -> void:
	var nr := rows.size()
	if nr < 2:
		return
	var np := rows[0].size()
	var nn: Array[PackedVector3Array] = []
	for i in nr:
		var im := maxi(i - 1, 0)
		var ip := mini(i + 1, nr - 1)
		var rn := PackedVector3Array()
		rn.resize(np)
		for j in np:
			var du := rows[i][(j + 1) % np] - rows[i][(j - 1 + np) % np] if wrap else rows[i][mini(j + 1, np - 1)] - rows[i][maxi(j - 1, 0)]
			var dv := rows[ip][j] - rows[im][j]
			rn[j] = du.cross(dv)
		nn.append(rn)
	for i in nr:
		var rn := nn[i]
		for j in np:
			if rn[j].length_squared() < 1e-16:
				rn[j] = nn[1][j] if i == 0 else nn[i - 1][j]
		nn[i] = rn
	var mi := nr / 2
	var rf := refs[mi] if refs.size() > mi and refs.size() > 1 else refs[0]
	var s := 1.0 if nn[mi][0].dot(rows[mi][0] - rf) >= 0.0 else -1.0
	var keep := k.color
	var zero := Vector3.ZERO
	var has_w := wd.size() == nr
	for i in nr - 1:
		if i < row_cols.size() and row_cols[i] is Color:
			k.color = row_cols[i]
		var ra := rows[i]
		var rb := rows[i + 1]
		var na := nn[i]
		var nb := nn[i + 1]
		for j in (np if wrap else np - 1):
			var j2 := (j + 1) % np
			var n0 := (na[j] * s).normalized()
			var n1 := (na[j2] * s).normalized()
			var n2 := (nb[j2] * s).normalized()
			var n3 := (nb[j] * s).normalized()
			var w0 := zero
			var w1 := zero
			var w2 := zero
			var w3 := zero
			if has_w:
				w0 = wd[i][j]
				w1 = wd[i][j2]
				w2 = wd[i + 1][j2]
				w3 = wd[i + 1][j]
			_tri(k, ra[j], ra[j2], rb[j2], n0, n1, n2, w0, w1, w2)
			_tri(k, ra[j], rb[j2], rb[j], n0, n2, n3, w0, w2, w3)
	k.color = keep

## Gepolsterter Stoffkoerper (Tasche, Platte, Rucksack): abgerundetes Rechteck (size.x * size.y, Eckradius rc),
## Tiefe size.z (Vorderseite +z), Kantenradius re vorne (hinten flacher), Woelbung `bulge` der Vorderseite,
## taper = Verjuengung oben (Schulterausschnitt der Platte). Nahtdaten fuer Einfassung/Steppnaht.
static func _slab(k: MK, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO, rc: float = 0.012, re: float = 0.007,
		bulge: float = 0.004, nc: int = 3, taper: float = 0.0, seam: bool = true) -> void:
	var old := k.push(pos, rot)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var m := minf(hx, hy)
	rc = minf(rc, m * 0.95)
	re = minf(re, minf(hz * 0.9, m * 0.45))
	var rb := minf(re * 0.6, hz * 0.5)
	# Ringe: [Einzug von der Kontur, z]
	var spec: Array[Vector2] = []
	var fz := func(ins: float) -> float:
		return hz + bulge * smoothstep(re, maxf(m * 0.75, re + 0.001), ins)
	var fr: Array[float] = [m]
	for x: float in [m * 0.6, m * 0.3, re + 0.0035]:
		if x < fr[fr.size() - 1] - 0.0008 and x > re + 0.0008:
			fr.append(x)
	for x in fr:
		spec.append(Vector2(x, fz.call(x)))
	spec.append(Vector2(re, hz))
	for th: float in [30.0, 60.0, 90.0]:
		var t := deg_to_rad(th)
		spec.append(Vector2(re * (1.0 - sin(t)), hz - re + re * cos(t)))
	if -hz + rb < hz - re - 0.001:
		spec.append(Vector2(0.0, -hz + rb))
	spec.append(Vector2(rb * (1.0 - sin(deg_to_rad(135.0))), -hz + rb + rb * cos(deg_to_rad(135.0))))
	spec.append(Vector2(rb, -hz))
	spec.append(Vector2(m * 0.5, -hz))
	spec.append(Vector2(m, -hz))
	var rows: Array[PackedVector3Array] = []
	var wd: Array = []
	for sp in spec:
		var ins := minf(sp.x, m - 0.0003)
		var o := _rrect(hx - ins, hy - ins, rc - ins, nc)
		var row := PackedVector3Array()
		var wr := PackedVector3Array()
		var along := 0.0
		for j in o.size():
			var q := o[j]
			if taper > 0.0:
				q.x *= 1.0 - taper * smoothstep(hy * 0.2, hy, q.y)
			if j > 0:
				along += q.distance_to(o[j - 1])
			row.append(Vector3(q.x, q.y, sp.y))
			wr.append(Vector3(sp.x, along, 1.0 if seam else 0.0))
		rows.append(row)
		wd.append(wr)
	_grid(k, rows, PackedVector3Array([Vector3.ZERO]), wd)
	k.xf = old

## Riemen/Gurt: abgerundetes Rechteckprofil (Breite w quer, Dicke t entlang `up`) entlang path.
## up: Vector3 (fest), PackedVector3Array (je Punkt) oder - bei radial = true - Mittelpunkt, von dem aus "oben" nach aussen zeigt.
static func _sweep(k: MK, path: PackedVector3Array, up: Variant, w: float, t: float, closed: bool = false, radial: bool = false, nc: int = 1, seam: bool = true) -> void:
	var n := path.size()
	if n < 2:
		return
	var prof := _rrect(w * 0.5, t * 0.5, minf(w, t) * 0.45, nc)
	var rows: Array[PackedVector3Array] = []
	var refs := PackedVector3Array()
	var wd: Array = []
	var along := 0.0
	var cnt := n + (1 if closed else 0)
	var tans: Array[Vector3] = []
	for ii in cnt:
		var i := ii % n
		if ii > 0:
			along += path[i].distance_to(path[(ii - 1) % n])
		var ip := (i + 1) % n if closed else mini(i + 1, n - 1)
		var im := (i - 1 + n) % n if closed else maxi(i - 1, 0)
		var tg := (path[ip] - path[im]).normalized()
		var u: Vector3
		if radial:
			u = path[i] - (up as Vector3)
		elif up is PackedVector3Array:
			u = (up as PackedVector3Array)[i]
		else:
			u = up as Vector3
		var sd := tg.cross(u).normalized()
		u = sd.cross(tg).normalized()
		var row := PackedVector3Array()
		var wr := PackedVector3Array()
		for q in prof:
			row.append(path[i] + sd * q.x + u * q.y)
			wr.append(Vector3(w * 0.5 - absf(q.x), along, 1.0 if seam else 0.0))
		rows.append(row)
		refs.append(path[i])
		wd.append(wr)
		tans.append(tg)
	_grid(k, rows, refs, wd)
	if not closed:
		for e in 2:
			var row := rows[0] if e == 0 else rows[rows.size() - 1]
			var cen := path[0] if e == 0 else path[n - 1]
			var out := -tans[0] if e == 0 else tans[tans.size() - 1]
			for j in row.size():
				k.tri(cen, row[j], row[(j + 1) % row.size()], out)

## Kleiner Stoffriegel/Zuglasche (kantig, ohne Naht)
static func _tab(k: MK, pos: Vector3, size: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	k.cbox(pos, size, minf(size.x, minf(size.y, size.z)) * 0.4, rot)

## Euler-Winkel (Grad, YXZ), die +Z auf die Richtung n drehen
static func _rot_to(n: Vector3) -> Vector3:
	n = n.normalized()
	return Vector3(-rad_to_deg(asin(clampf(n.y, -1.0, 1.0))), rad_to_deg(atan2(n.x, n.z)), 0.0)

# ------------------------------------------------------------------ Brust

## Brust: Plattentraeger (Front-/Rueckenplatte mit MOLLE, gepolsterte Schulterriemen, Kummerbund), drei
## Magazintaschen mit Klappen, Admin-Tasche, Sprechtaste, Funkgeraet mit Antenne, Trinkrucksack.
## resistance: nur leichtes Koppeltragegestell.
static func build_chest(k: MK, faction: String, role: String, heavy: bool) -> void:
	var c := colors(faction)
	if faction == "resistance":
		_build_chest_rig(k, c)
		return
	var camo := faction == "ru"
	var cm := MAT_CAMO_MOLLE if camo else MAT_MOLLE
	var cn := MAT_CAMO if camo else MAT_NYLON
	var dz := 0.045 if heavy else 0.035
	var fy := 1.25
	var fz := _front_z(fy, heavy)
	var bz := -0.127 - (0.01 if heavy else 0.0)
	k.color = _c(c[0], cm)
	_slab(k, Vector3(0, fy, fz), Vector3(0.285, 0.32, dz), Vector3(FRONT_TILT, 0, 0), 0.035, 0.012, 0.006, 3, 0.22)    # Frontplatte
	_slab(k, Vector3(0, 1.255, bz), Vector3(0.285, 0.33, dz - 0.004), Vector3(-6, 180, 0), 0.035, 0.012, 0.005, 3, 0.22)   # Rueckenplatte
	# Schulterriemen (gepolstert) von der Front- zur Rueckenplatte ueber die Schulter
	k.color = _c(c[0].lerp(c[1], 0.3), cn)
	for sx: float in [-1.0, 1.0]:
		var p := PackedVector3Array([
			Vector3(sx * 0.088, 1.385, _front_z(1.385, heavy) - 0.004),
			Vector3(sx * 0.094, 1.425, 0.118),
			Vector3(sx * 0.098, 1.452, 0.07),
			Vector3(sx * 0.1, 1.462, 0.015),
			Vector3(sx * 0.099, 1.455, -0.045),
			Vector3(sx * 0.095, 1.43, -0.098),
			Vector3(sx * 0.09, 1.4, bz - 0.004)])
		_sweep(k, p, Vector3(sx * 0.03, 1.37, 0.0), 0.052, 0.014, false, true, 2)
	# Kummerbund (Seitenteile, Laminat mit MOLLE), laeuft unter den Platten durch
	k.color = _c(c[0].lerp(c[1], 0.2), cm)
	_sweep(k, _ring(0.18, 0.142, 1.165, 0.028, 32), Vector3(0, 1.165, 0.028), 0.1, 0.009, true, true, 2)
	# Magazintaschen unten an der Front (mit Klappe, Zuglasche)
	var py := 1.155
	var pz := _front_z(py, heavy) + dz * 0.5 + 0.023
	for i in 3:
		var x := -0.074 + 0.074 * float(i)
		k.color = _c(c[0], cn)
		_slab(k, Vector3(x, py, pz), Vector3(0.068, 0.118, 0.046), Vector3(FRONT_TILT, 0, 0), 0.01, 0.009, 0.004, 2)
		k.color = _c(c[0].lerp(c[1], 0.15), cn)
		_slab(k, Vector3(x, py + 0.047, pz + 0.004), Vector3(0.072, 0.036, 0.05), Vector3(FRONT_TILT - 4.0, 0, 0), 0.008, 0.007, 0.002, 2)   # Klappe
		k.color = _c(c[1], MAT_WEB)
		_tab(k, Vector3(x, py + 0.026, pz + 0.029), Vector3(0.016, 0.026, 0.004), Vector3(FRONT_TILT, 0, 0))   # Zuglasche
	# Admin-Tasche, Sprechtaste
	var ay := 1.325
	var az := _front_z(ay, heavy) + dz * 0.5
	k.color = _c(c[0], cn)
	_slab(k, Vector3(-0.07, ay, az + 0.013), Vector3(0.095, 0.078, 0.026), Vector3(FRONT_TILT, 0, 0), 0.012, 0.007, 0.004, 2)
	k.color = _c(c[1], MAT_HARD)
	_slab(k, Vector3(0.088, 1.385, _front_z(1.385, heavy) + dz * 0.5 + 0.01), Vector3(0.028, 0.045, 0.02), Vector3(FRONT_TILT, 0, 0), 0.006, 0.005, 0.0, 2, 0.0, false)
	# Funkgeraet hinten rechts (Tasche + Geraet) mit Antenne
	var rz := bz - dz * 0.5
	k.color = _c(c[0], cn)
	_slab(k, Vector3(-0.105, 1.255, rz - 0.024), Vector3(0.07, 0.13, 0.044), Vector3(0, 180, 0), 0.01, 0.008, 0.003, 2)
	k.color = _c(c[2] * 0.6, MAT_HARD)
	_slab(k, Vector3(-0.105, 1.335, rz - 0.024), Vector3(0.062, 0.04, 0.036), Vector3(0, 180, 0), 0.006, 0.005, 0.0, 2, 0.0, false)
	k.color = _c(Color(0.05, 0.05, 0.05), MAT_RUBBER)
	k.cyl(Vector3(-0.12, 1.35, rz - 0.03), Vector3(-0.15, 1.72, rz - 0.06), 0.004, 6)
	k.cyl(Vector3(-0.09, 1.35, rz - 0.024), Vector3(-0.09, 1.375, rz - 0.024), 0.008, 8)
	if heavy:
		# Munitionsrucksack fuer das MG (kein Kragen mehr - der Halsschutz las sich als dunkles Band)
		k.color = _c(c[0], cn)
		_slab(k, Vector3(0.0, 1.2, rz - 0.058), Vector3(0.24, 0.26, 0.11), Vector3(0, 180, 0), 0.04, 0.03, 0.01, 3)
		k.color = _c(c[1], MAT_WEB)
		_sweep(k, PackedVector3Array([Vector3(-0.1, 1.29, rz - 0.112), Vector3(0.1, 1.29, rz - 0.112)]), Vector3(0, 0, -1), 0.025, 0.004)
		_sweep(k, PackedVector3Array([Vector3(-0.1, 1.13, rz - 0.112), Vector3(0.1, 1.13, rz - 0.112)]), Vector3(0, 0, -1), 0.025, 0.004)
	elif role != "officer" and role != "marksman":
		# Trinkrucksack
		k.color = _c(c[0], cn)
		_slab(k, Vector3(0.03, 1.2, rz - 0.03), Vector3(0.16, 0.25, 0.055), Vector3(0, 180, 0), 0.04, 0.022, 0.012, 3)
		k.color = _c(c[1], MAT_WEB)
		for yy: float in [1.27, 1.15]:
			_sweep(k, PackedVector3Array([Vector3(-0.05, yy, rz - 0.06), Vector3(0.03, yy, rz - 0.063), Vector3(0.11, yy, rz - 0.06)]), Vector3(0, 0, -1), 0.018, 0.003)
	if faction == "reich":
		# Amber-Kennstreifen auf den Schulterriemen
		k.color = _c(c[3], MAT_WEB)
		for sx: float in [-1.0, 1.0]:
			_sweep(k, PackedVector3Array([Vector3(sx * 0.099, 1.462, 0.05), Vector3(sx * 0.1, 1.468, 0.015), Vector3(sx * 0.1, 1.466, -0.01)]),
				Vector3(sx * 0.03, 1.37, 0.0), 0.024, 0.003, false, true)
	match role:
		"assault":
			_grenade_pouches(k, faction, heavy)
		"officer":
			_officer_radio(k, faction, rz)
		"marksman":
			_ghillie_back(k, faction, rz)

## Widerstand: Koppeltragegestell (Y-Riemen aus Gurtband) mit zwei Taschen, keine Platten.
static func _build_chest_rig(k: MK, c: Array[Color]) -> void:
	k.color = _c(c[1], MAT_WEB)
	for sx: float in [-1.0, 1.0]:
		var p := PackedVector3Array([
			Vector3(sx * 0.09, 1.14, 0.168), Vector3(sx * 0.088, 1.26, 0.152), Vector3(sx * 0.092, 1.37, 0.128),
			Vector3(sx * 0.097, 1.432, 0.08), Vector3(sx * 0.098, 1.452, 0.015), Vector3(sx * 0.08, 1.43, -0.07),
			Vector3(sx * 0.03, 1.36, -0.112)])
		_sweep(k, p, Vector3(sx * 0.03, 1.32, 0.02), 0.038, 0.004, false, true)
	_sweep(k, PackedVector3Array([Vector3(0, 1.36, -0.115), Vector3(0, 1.25, -0.122), Vector3(0, 1.08, -0.122)]), Vector3(0, 0, -1), 0.04, 0.004)
	for sx: float in [-1.0, 1.0]:
		k.color = _c(c[0], MAT_NYLON)
		_slab(k, Vector3(sx * 0.09, 1.075, 0.172), Vector3(0.075, 0.1, 0.045), Vector3(-4, 0, 0), 0.012, 0.012, 0.006, 2)
		k.color = _c(c[0] * 0.9, MAT_NYLON)
		_slab(k, Vector3(sx * 0.09, 1.117, 0.176), Vector3(0.079, 0.032, 0.05), Vector3(-8, 0, 0), 0.008, 0.008, 0.002, 2)

## Sturm: zwei Handgranatentaschen seitlich am Kummerbund + Zusatz-Magazintasche oben.
static func _grenade_pouches(k: MK, faction: String, heavy: bool) -> void:
	var c := colors(faction)
	var cn := MAT_CAMO if faction == "ru" else MAT_NYLON
	for sx: float in [-1.0, 1.0]:
		var p := Vector3(sx * 0.185, 1.16, 0.07)
		k.color = _c(c[0], cn)
		_slab(k, p, Vector3(0.05, 0.08, 0.05), Vector3(0, sx * 58.0, 0), 0.02, 0.014, 0.004, 2)
		k.color = _c(c[0].lerp(c[1], 0.2), cn)
		_slab(k, p + Vector3(0, 0.038, 0), Vector3(0.054, 0.02, 0.054), Vector3(0, sx * 58.0, 0), 0.016, 0.008, 0.002, 2)
	var y := 1.325
	k.color = _c(c[0], cn)
	_slab(k, Vector3(0.07, y, _front_z(y, heavy) + 0.03), Vector3(0.072, 0.075, 0.032), Vector3(FRONT_TILT, 0, 0), 0.012, 0.009, 0.004, 2)

static func _officer_radio(k: MK, faction: String, rz: float) -> void:
	var c := colors(faction)
	k.color = _c(c[0], MAT_CAMO if faction == "ru" else MAT_NYLON)
	_slab(k, Vector3(0.0, 1.23, rz - 0.05), Vector3(0.21, 0.27, 0.09), Vector3(0, 180, 0), 0.03, 0.02, 0.006, 3)   # Funkgeraet-Tasche
	k.color = _c(c[2] * 0.7, MAT_HARD)
	_slab(k, Vector3(0.0, 1.37, rz - 0.05), Vector3(0.17, 0.03, 0.07), Vector3(0, 180, 0), 0.008, 0.006, 0.0, 2, 0.0, false)
	k.color = _c(Color(0.05, 0.05, 0.05), MAT_RUBBER)
	k.cyl(Vector3(0.07, 1.385, rz - 0.06), Vector3(0.07, 1.41, rz - 0.06), 0.012, 10)
	k.cyl(Vector3(0.07, 1.41, rz - 0.06), Vector3(0.1, 2.2, rz - 0.14), 0.0045, 6)  # Peitschenantenne
	k.color = _c(c[3] if faction == "reich" else Color(0.7, 0.1, 0.08), MAT_HARD)
	k.cyl(Vector3(0.1, 2.2, rz - 0.14), Vector3(0.101, 2.23, rz - 0.142), 0.008, 6)

## Scharfschuetze: Jute-Streifen am Ruecken und auf den Schultern (haengend, leicht gebogen)
static func _ghillie_back(k: MK, faction: String, rz: float) -> void:
	# Jute-Streifen am Rueckenteil: haengen flach nach unten, bleiben innerhalb der Schulterbreite
	var cols := _ghillie_cols(faction)
	var rng := RandomNumberGenerator.new()
	rng.seed = 815
	for i in 30:
		var x := rng.randf_range(-0.13, 0.13)
		var ln := rng.randf_range(0.07, 0.15)
		var z := rz - rng.randf_range(0.0, 0.02)
		var y := 1.44 + rng.randf_range(-0.05, 0.01)
		k.color = _c(cols[rng.randi() % cols.size()], MAT_JUTE)
		_tuft(k, Vector3(x, y, z), Vector3(0, 0, -1), ln, rng.randf_range(0.022, 0.036), rng)

static func _ghillie_cols(faction: String) -> Array[Color]:
	# Jute-Mischung oliv / braun / beige (Winter: weiss/beige/grau); [3] = dunkle Grundfarbe des Netzes
	if faction == "garde_winter":
		return [Color(0.55, 0.56, 0.57), Color(0.44, 0.42, 0.37), Color(0.64, 0.64, 0.62), Color(0.34, 0.34, 0.32)]
	return [Color(0.085, 0.085, 0.04), Color(0.075, 0.05, 0.028), Color(0.17, 0.14, 0.09), Color(0.045, 0.05, 0.028), Color(0.12, 0.1, 0.055), Color(0.06, 0.065, 0.035)]

# ------------------------------------------------------------------ Huefte

## Huefte: Koppel (Gurt mit Steppnaehten; Militaer mit MOLLE-Polster) mit Taschen und Schnalle.
static func build_hips(k: MK, faction: String) -> void:
	var c := colors(faction)
	var res := faction == "resistance"
	var cn := MAT_CAMO if faction == "ru" else MAT_NYLON
	k.color = _c(c[1], MAT_WEB if res else MAT_MOLLE)
	_sweep(k, _ring(0.176, 0.131, 0.997, 0.022, 32), Vector3(0, 0.997, 0.022), 0.034 if res else 0.05, 0.007, true, true, 2)
	k.color = _c(c[0], cn)
	_slab(k, Vector3(0.158, 0.962, 0.085), Vector3(0.048, 0.085, 0.055), Vector3(0, 32, 0), 0.012, 0.01, 0.004, 2)
	_slab(k, Vector3(-0.162, 0.958, 0.058), Vector3(0.05, 0.095, 0.07), Vector3(0, -22, 0), 0.016, 0.014, 0.006, 2)
	_slab(k, Vector3(0.09, 0.96, -0.115), Vector3(0.09, 0.08, 0.045), Vector3(0, 180, 0), 0.014, 0.012, 0.006, 2)
	k.color = _c(c[0].lerp(c[1], 0.2), cn)
	_slab(k, Vector3(0.158, 0.998, 0.087), Vector3(0.052, 0.026, 0.06), Vector3(-6, 32, 0), 0.008, 0.007, 0.002, 2)
	k.color = _c(Color(0.16, 0.16, 0.16) if not res else Color(0.35, 0.32, 0.25), MAT_METAL if res else MAT_HARD)
	_slab(k, Vector3(0.0, 0.997, 0.155), Vector3(0.052, 0.036, 0.012), Vector3.ZERO, 0.006, 0.004, 0.0, 2, 0.0, false)

# ------------------------------------------------------------------ Kopf

## Kopf: Helm (ru: vollschaliger Helm mit Tarnbezug; sonst High-Cut-Helm mit Schienen/NVG-Halterung);
## Sturm = Schutzbrille auf dem Helm (Halstuch: im Haut-Shader, gaiter_color), Scharfschuetze = Ghillie-Haube, Offizier = Schirmmuetze.
## resistance: Strickmuetze (Sturm: nur Halstuch).
static func build_head(k: MK, faction: String, role: String) -> void:
	var c := colors(faction)
	if faction == "resistance":
		# kein nackter Schaedel: Offizier traegt Feldmuetze, alle anderen Strickmuetze (Sturm: dunkler, passt zum Halstuch)
		if role == "officer":
			_field_cap(k, c[1].lerp(c[0], 0.5))
		elif role == "assault":
			_beanie(k, Color(0.07, 0.07, 0.065))
		else:
			_beanie(k, c[1].lerp(c[0], 0.3))
		return
	if role == "officer":
		_peaked_cap(k, faction)
		return
	_helmet(k, faction, role == "marksman")
	match role:
		"assault":
			_goggles(k, faction)
		"marksman":
			_ghillie_hood(k, faction)

static func _amax(phi: float, tab: Array) -> float:
	var d := absf(wrapf(rad_to_deg(phi), -180.0, 180.0))
	for i in tab.size() - 1:
		var a: Array = tab[i]
		var b: Array = tab[i + 1]
		if d <= float(b[0]):
			var t := (d - float(a[0])) / (float(b[0]) - float(a[0]))
			t = t * t * (3.0 - 2.0 * t)
			return deg_to_rad(lerpf(float(a[1]), float(b[1]), t))
	return deg_to_rad(float(tab[tab.size() - 1][1]))

## Punkt auf der Helmschale (Azimut phi, 0 = vorne, + = links; Polwinkel a ab Scheitel; off = Abstand nach aussen)
static func _hp(phi: float, a: float, off: float = 0.0) -> Vector3:
	return H_C + Vector3((H_R.x + off) * sin(a) * sin(phi), (H_R.y + off) * cos(a), (H_R.z + off) * sin(a) * cos(phi))

static func _hn(phi: float, a: float) -> Vector3:
	var p := _hp(phi, a) - H_C
	return Vector3(p.x / (H_R.x * H_R.x), p.y / (H_R.y * H_R.y), p.z / (H_R.z * H_R.z)).normalized()

static func _helmet_cols(faction: String) -> Array:
	# [Schale, Code, Kantenschutz, Schienen/Halterung]
	match faction:
		"ru":
			return [Color(0.32, 0.33, 0.24), MAT_CAMO, Color(0.06, 0.065, 0.05), Color(0.05, 0.05, 0.05)]
		"reich":
			return [Color(0.1, 0.105, 0.115), MAT_PAINT, Color(0.035, 0.035, 0.04), Color(0.05, 0.05, 0.055)]
		"garde":
			return [Color(0.07, 0.072, 0.078), MAT_PAINT, Color(0.03, 0.03, 0.032), Color(0.045, 0.045, 0.05)]
		"garde_winter":
			return [Color(0.55, 0.56, 0.57), MAT_PAINT, Color(0.08, 0.08, 0.085), Color(0.1, 0.1, 0.105)]
	var gc := colors(faction)
	return [gc[0], MAT_PAINT, gc[1], gc[1]]

## Helm: Schale (Ellipsoid, Randverlauf HIGH_CUT mit Ohrausschnitt bzw. FULL_CUT), umlaufender Kantenschutz,
## Innenpolster; High-Cut mit ARC-Schienen, NVG-Halterung, Klett-Flaechen und Gegengewicht hinten.
static func _helmet(k: MK, faction: String, bare: bool = false) -> void:
	var hc := _helmet_cols(faction)
	var full := faction == "ru"
	var tab: Array = FULL_CUT if full else HIGH_CUT
	var shell: Color = _c(hc[0], hc[1])
	var trim: Color = _c(hc[2], MAT_RUBBER)
	var liner := _c(Color(0.035, 0.035, 0.035), MAT_NYLON)
	var n := 44
	var ts: Array[float] = [0.0, 0.13, 0.26, 0.39, 0.52, 0.64, 0.75, 0.84, 0.92, 1.0]
	var rows: Array[PackedVector3Array] = []
	var rc: Array = []
	var am := PackedFloat32Array()
	for j in n:
		am.append(_amax(TAU * float(j) / float(n), tab))
	for t in ts:
		var row := PackedVector3Array()
		for j in n:
			row.append(_hp(TAU * float(j) / float(n), (am[j] - 0.075) * t))
		rows.append(row)
		rc.append(shell)
	# Kantenschutz (Stufe nach aussen, Kante, innen) und Innenpolster
	var trim_rows: Array[Vector2] = [Vector2(-0.07, 0.0032), Vector2(0.004, 0.0035), Vector2(0.011, -0.002), Vector2(0.005, -0.008), Vector2(-0.2, -0.011)]
	rc[rc.size() - 1] = trim
	for ti in trim_rows.size():
		var tr: Vector2 = trim_rows[ti]
		var row := PackedVector3Array()
		for j in n:
			row.append(_hp(TAU * float(j) / float(n), am[j] + tr.x, tr.y))
		rows.append(row)
		rc.append(trim if ti < 3 else liner)
	_grid(k, rows, PackedVector3Array([H_C]), [], rc)
	if full:
		# Bezug: Gummiband mit Laschen um die Schale
		k.color = _c(Color(0.06, 0.06, 0.05), MAT_WEB)
		var band := PackedVector3Array()
		for j in 36:
			var phi := TAU * float(j) / 36.0
			band.append(_hp(phi, _amax(phi, tab) - 0.32, 0.003))
		_sweep(k, band, H_C, 0.012, 0.004, true, true)
		return
	if bare:   # unter der Ghillie-Haube unsichtbar
		return
	var dark: Color = _c(hc[3], MAT_HARD)
	# ARC-Schienen seitlich, dem Rand folgend
	k.color = dark
	for sx: float in [-1.0, 1.0]:
		var p := PackedVector3Array()
		for i in 9:
			var phi := sx * deg_to_rad(lerpf(52.0, 128.0, float(i) / 8.0))
			p.append(_hp(phi, _amax(phi, tab) - 0.2, 0.004))
		_sweep(k, p, H_C, 0.02, 0.008, false, true, 1, false)
	# NVG-Halterung (Shroud) vorne
	var a0 := deg_to_rad(52.0)
	k.color = dark
	_slab(k, _hp(0.0, a0, 0.006), Vector3(0.056, 0.038, 0.012), _rot_to(_hn(0.0, a0)), 0.008, 0.004, 0.001, 2, 0.0, false)
	# Klettflaechen oben und hinten, Gegengewicht-Tasche hinten unten
	var velc := _c(Color(hc[0]).lerp(Color(hc[2]), 0.35), MAT_NYLON)
	k.color = velc
	var at := deg_to_rad(18.0)
	_slab(k, _hp(0.0, at, 0.0015), Vector3(0.075, 0.05, 0.003), _rot_to(_hn(0.0, at)), 0.008, 0.0015, 0.0, 2)
	var ab := deg_to_rad(62.0)
	_slab(k, _hp(PI, ab, 0.0015), Vector3(0.085, 0.045, 0.003), _rot_to(_hn(PI, ab)), 0.008, 0.0015, 0.0, 2)
	var ac := deg_to_rad(88.0)
	k.color = _c(Color(hc[0]) * 0.8, MAT_NYLON)
	_slab(k, _hp(PI, ac, 0.012), Vector3(0.075, 0.05, 0.024), _rot_to(_hn(PI, ac)), 0.012, 0.009, 0.003, 2)

## Schutzbrille auf der Helmfront: Rahmen (Gummi), gewoelbtes Glas, Band um den Helm.
static func _goggles(k: MK, faction: String) -> void:
	var tab: Array = FULL_CUT if faction == "ru" else HIGH_CUT
	var frame := PackedVector3Array()
	var lens := PackedVector3Array()
	for i in 11:
		var phi := deg_to_rad(lerpf(-58.0, 58.0, float(i) / 10.0))
		var a := _amax(phi, tab) - 0.36
		frame.append(_hp(phi, a, 0.011))
		lens.append(_hp(phi, a, 0.021))
	k.color = _c(Color(0.05, 0.052, 0.055), MAT_RUBBER)
	_sweep(k, frame, H_C, 0.044, 0.018, false, true, 2, false)
	k.color = _c(Color(0.16, 0.12, 0.05) if faction == "reich" else Color(0.07, 0.08, 0.08), MAT_LENS)
	_sweep(k, lens, H_C, 0.032, 0.003, false, true, 1, false)
	k.color = _c(Color(0.06, 0.06, 0.065), MAT_WEB)
	var strap := PackedVector3Array()
	for i in 17:
		var phi := deg_to_rad(lerpf(56.0, 304.0, float(i) / 16.0))
		strap.append(_hp(phi, _amax(phi, tab) - 0.33, 0.0035))
	_sweep(k, strap, H_C, 0.03, 0.003, false, true)

## Halstuch-Farbe der Sturmtruppe (linear); wird im Haut-Shader (soldier_mh_skin.gdshader) direkt auf
## Kinn/Mund/Nase/Hals gelegt statt als eigenes Netz -> keine Durchdringung bei Mimik/Pose.
static func gaiter_color(faction: String) -> Color:
	var c := colors(faction)
	return c[1].lerp(c[0], 0.6 if faction == "resistance" else 0.5)

## Strickmuetze mit Umschlag (Widerstand)
static func _beanie(k: MK, col: Color) -> void:
	var cz := 0.056
	k.color = _c(col, MAT_KNIT)
	var rows: Array[PackedVector3Array] = []
	var spec := [[0.0855, 0.1065, 1.598], [0.087, 0.108, 1.63], [0.086, 0.107, 1.64], [0.084, 0.104, 1.665], [0.075, 0.093, 1.688],
		[0.058, 0.072, 1.703], [0.033, 0.04, 1.712], [0.0, 0.0, 1.714]]
	for s: Array in spec:
		rows.append(_ring(maxf(float(s[0]), 0.0003), maxf(float(s[1]), 0.0003), float(s[2]), cz - (float(s[2]) - 1.6) * 0.06, 32, 2.2))
	_grid(k, rows, PackedVector3Array([Vector3(0, 1.62, cz)]))
	# Umschlag
	k.color = _c(col * 0.9, MAT_KNIT)
	var cuff: Array[PackedVector3Array] = [_ring(0.0835, 0.1045, 1.594, cz, 32, 2.2), _ring(0.0895, 0.1105, 1.597, cz, 32, 2.2),
		_ring(0.0905, 0.1115, 1.628, cz, 32, 2.2), _ring(0.087, 0.108, 1.634, cz, 32, 2.2)]
	_grid(k, cuff, PackedVector3Array([Vector3(0, 1.614, cz)]))

## Feldmuetze (Patrol-Cap): weicher, oben flacher Stoffkoerper mit kurzem, leicht gebogenem Schirm.
static func _field_cap(k: MK, col: Color) -> void:
	var cz := 0.057
	var rows: Array[PackedVector3Array] = []
	# [rx, rz, y]: eng am Kopf, nach oben leicht geweitet, flacher Deckel
	var spec := [[0.0865, 0.1075, 1.598], [0.0885, 0.1095, 1.625], [0.0905, 0.1115, 1.66], [0.092, 0.113, 1.688],
		[0.089, 0.11, 1.697], [0.07, 0.087, 1.701], [0.0, 0.0, 1.703]]
	k.color = _c(col, MAT_FELT)
	for sp: Array in spec:
		rows.append(_ring(maxf(float(sp[0]), 0.0003), maxf(float(sp[1]), 0.0003), float(sp[2]), cz, 32, 2.3))
	_grid(k, rows, PackedVector3Array([Vector3(0, 1.64, cz)]))
	var vis: Array[PackedVector3Array] = []
	var nv := 13
	for sp: Vector2 in [Vector2(0.0, 0.002), Vector2(0.5, 0.0025), Vector2(1.0, 0.0015), Vector2(1.0, -0.0015), Vector2(0.5, -0.0025), Vector2(0.0, -0.002)]:
		var row := PackedVector3Array()
		for j in nv:
			var a := deg_to_rad(lerpf(-70.0, 70.0, float(j) / float(nv - 1)))
			var base := Vector3(sin(a) * 0.0875, 1.601, cos(a) * 0.1085 + cz)
			var reach := 0.052 * pow(cos(a), 0.8)
			var p := base + Vector3(sin(a) * 0.3, 0, cos(a)).normalized() * reach * sp.x
			p.y += -0.012 * sp.x - 0.004 * sp.x * sp.x + sp.y - 0.006 * sp.x * sin(a) * sin(a)
			row.append(p)
		vis.append(row)
	k.color = _c(col * 0.85, MAT_FELT)
	_grid_open(k, vis, Vector3(0, 1.64, cz))

## Ghillie-Haube: Netz eng auf dem Helm (Gesicht frei), daran Jute-Streifen, die nach hinten/seitlich fallen.
static func _ghillie_hood(k: MK, faction: String) -> void:
	var cols := _ghillie_cols(faction)
	var tab: Array = FULL_CUT if faction == "ru" else HIGH_CUT
	k.color = _c(cols[3] * 0.8, MAT_JUTE)
	var rows: Array[PackedVector3Array] = []
	var n := 32
	for t: float in [0.0, 0.25, 0.5, 0.72, 0.9, 1.0]:
		var row := PackedVector3Array()
		for j in n:
			var phi := TAU * float(j) / float(n)
			row.append(_hp(phi, (_amax(phi, tab) + 0.02) * t, 0.019))
		rows.append(row)
	_grid(k, rows, PackedVector3Array([H_C]))
	# Jute-Buesche in Schindel-Reihen: liegen eng auf der Haube, haengen nach unten/hinten, ueberlappen sich
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var a := 0.04
	while a < 1.9:
		var cnt := maxi(4, roundi(sin(a) * 40.0))
		var ph0 := rng.randf() * TAU
		for j in cnt:
			var phi := wrapf(ph0 + TAU * (float(j) + rng.randf_range(-0.35, 0.35)) / float(cnt), -PI, PI)
			var am := _amax(phi, tab)
			if a > am + 0.02:
				continue
			var la := rng.randf_range(0.25, 0.4) * (1.3 if cos(phi) < -0.3 else 1.0)
			if cos(phi) > 0.3:   # vorne: nur bis zum Rand, nichts haengt ins Gesicht
				la = minf(la * 0.7, am + 0.01 - a)
				if la < 0.06:
					continue
			k.color = _c(cols[rng.randi() % cols.size()], MAT_JUTE)
			_shingle(k, phi, a, la, rng.randf_range(0.015, 0.025), tab, 0.024 - 0.006 * a / 1.8, rng)
		a += 0.12

## Jute-Schindel auf der Haube: 4 Punkte entlang der Schale (Polwinkel a -> a + la, leicht nach hinten),
## unterhalb des Randes senkrecht nach unten; Normalen = Schalennormale (weich beleuchtet).
static func _shingle(k: MK, phi: float, a: float, la: float, w: float, tab: Array, off: float, rng: RandomNumberGenerator) -> void:
	var back := signf(phi) * rng.randf_range(0.04, 0.12) if absf(phi) > 0.15 else rng.randf_range(-0.05, 0.05)
	var wob := rng.randf_range(-0.12, 0.12)
	var lift := rng.randf_range(0.001, 0.008)
	var pts := PackedVector3Array()
	var nrs := PackedVector3Array()
	for i in 4:
		var t := float(i) / 3.0
		var ph := phi + back * t + wob * t * t
		var lim := _amax(ph, tab) + 0.02
		var ai := a + la * t
		var o := off + lift * sin(t * PI * 0.8)
		var p := _hp(ph, minf(ai, lim), o)
		if ai > lim:
			p.y -= (ai - lim) * H_R.y
		pts.append(p)
		nrs.append(_hn(ph, minf(ai, lim)))
	var ws := [w * 0.8, w, w * 0.65, w * 0.15]
	for i in 3:
		var tg := (pts[i + 1] - pts[i]).normalized()
		var sa := nrs[i].cross(tg).normalized() * float(ws[i]) * 0.5
		var tg2 := tg if i < 2 else (pts[3] - pts[2]).normalized()
		var sb := nrs[i + 1].cross(tg2).normalized() * float(ws[i + 1]) * 0.5
		k.quad_n(pts[i] - sa, pts[i] + sa, pts[i + 1] + sb, pts[i + 1] - sb, nrs[i], nrs[i], nrs[i + 1], nrs[i + 1])

## Ghillie-Busch: flacher, doppelseitiger Jute-Streifen (3 Abschnitte, verjuengt), faellt der Flaeche nach unten.
static func _tuft(k: MK, top: Vector3, n: Vector3, ln: float, w: float, rng: RandomNumberGenerator) -> void:
	var d := Vector3.DOWN - n * n.dot(Vector3.DOWN)
	if d.length() < 0.25:
		var r := rng.randf() * TAU
		d = Vector3(cos(r), 0, sin(r)) - n * n.dot(Vector3(cos(r), 0, sin(r)))
	d = (d.normalized() + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))).normalized()
	var sd := n.cross(d).normalized()
	var lift := rng.randf_range(0.004, 0.014)
	var pts := [top, top + d * ln * 0.4 + n * lift, top + d * ln * 0.75 + n * lift * 1.3 + Vector3(0, -0.01, 0), top + d * ln + n * lift * 0.9 + Vector3(0, -0.02, 0)]
	var ws := [w, w * 0.9, w * 0.6, w * 0.2]
	for i in 3:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var wa: float = ws[i] * 0.5
		var wb: float = ws[i + 1] * 0.5
		var nn := sd.cross(b - a).normalized()
		if nn.dot(n) < 0.0:
			nn = -nn
		nn = (nn + n).normalized()   # weich wie das Netz darunter beleuchten
		k.quad_n(a - sd * wa, a + sd * wa, b + sd * wb, b - sd * wb, nn, nn, nn, nn)
		k.quad_n(a - sd * wa, a + sd * wa, b + sd * wb, b - sd * wb, -nn, -nn, -nn, -nn)

## Schirmmuetze (Offizier): Band, nach oben ausgestellte Krone mit hochgezogener Front (Sattel), gewoelbter
## Lackschirm, Kinnkordel, Kokarde (erfunden, Fraktionsfarbe).
static func _peaked_cap(k: MK, faction: String) -> void:
	var c := colors(faction)
	var cap := Color(0.2, 0.23, 0.14) if faction == "ru" else (Color(0.07, 0.072, 0.078) if faction == "reich" else c[0] * 1.15)
	var bandc: Color = c[3] if faction == "reich" else (Color(0.5, 0.06, 0.05) if faction == "ru" else cap * 0.55)
	var cz := 0.058
	var n := 36
	var rows: Array[PackedVector3Array] = []
	var rc: Array = []
	# [rx, rz, y, Sattel (Front hoeher), Farbe]
	var spec := [[0.0865, 0.1105, 1.598, 0.0, 0], [0.088, 0.112, 1.612, 0.0, 1], [0.0885, 0.1125, 1.635, 0.0, 0], [0.096, 0.122, 1.66, 0.006, 0],
		[0.104, 0.132, 1.682, 0.016, 0], [0.106, 0.134, 1.692, 0.022, 0], [0.1, 0.127, 1.698, 0.024, 0], [0.07, 0.09, 1.702, 0.016, 0],
		[0.0, 0.0, 1.704, 0.0, 0]]
	for s: Array in spec:
		var row := PackedVector3Array()
		var rx := maxf(float(s[0]), 0.0003)
		var rz := maxf(float(s[1]), 0.0003)
		for p in MK.superellipse(rx, rz, 2.15, n):
			var fr := maxf(p.y / rz, 0.0)
			row.append(Vector3(p.x, float(s[2]) + float(s[3]) * fr * fr, p.y + cz + 0.008 * fr * float(s[3]) / 0.024))
		rows.append(row)
		rc.append(_c(bandc, MAT_FELT) if int(s[4]) == 1 else _c(cap, MAT_FELT))
	_grid(k, rows, PackedVector3Array([Vector3(0, 1.64, cz)]), [], rc)
	# Schirm: gewoelbte Platte vorne (Oberseite, Kante, Unterseite)
	var vis: Array[PackedVector3Array] = []
	var nv := 15
	# [Anteil nach aussen 0..1, Hoehenversatz (Dicke)]
	for sp: Vector2 in [Vector2(0.0, 0.0025), Vector2(0.5, 0.003), Vector2(1.0, 0.002), Vector2(1.0, -0.002), Vector2(0.5, -0.003), Vector2(0.0, -0.0025)]:
		var row := PackedVector3Array()
		for j in nv:
			var a := deg_to_rad(lerpf(-78.0, 78.0, float(j) / float(nv - 1)))
			var base := Vector3(sin(a) * 0.0875, 1.6, cos(a) * 0.1115 + cz)
			var reach := 0.058 * pow(cos(a), 0.7)
			var dir := Vector3(sin(a) * 0.35, 0, cos(a)).normalized()
			var p := base + dir * reach * sp.x
			p.y += -0.024 * sp.x - 0.006 * sp.x * sp.x + sp.y
			row.append(p)
		vis.append(row)
	k.color = _c(Color(0.025, 0.025, 0.028), MAT_LEATHER)
	_grid_open(k, vis, Vector3(0, 1.64, cz))
	# Kinnkordel und Knoepfe
	k.color = _c(Color(0.6, 0.48, 0.2) if faction != "garde_winter" else Color(0.6, 0.6, 0.62), MAT_METAL)
	var cord := PackedVector3Array()
	for j in 9:
		var a := deg_to_rad(lerpf(-74.0, 74.0, float(j) / 8.0))
		cord.append(Vector3(sin(a) * 0.0905, 1.607, cos(a) * 0.1145 + cz))
	_sweep(k, cord, Vector3(0, 1.607, cz), 0.003, 0.003, false, true, 1, false)
	# Kokarde
	k.color = _c(Color(0.75, 0.62, 0.25) if faction == "ru" else c[3], MAT_METAL)
	var cp := Vector3(0, 1.655, cz + 0.1135)
	k.lathe(cp, Vector3(0, 0.15, 1), PackedVector2Array([Vector2(0, 0), Vector2(0, 0.012), Vector2(0.003, 0.011), Vector2(0.004, 0.0)]), 12)

## Offenes Gitter (Reihen nicht geschlossen, z.B. Muetzenschirm) mit weichen Normalen und gedeckelten Seitenkanten.
static func _grid_open(k: MK, rows: Array[PackedVector3Array], ref: Vector3) -> void:
	_grid(k, rows, PackedVector3Array([ref]), [], [], false)
	var nr := rows.size()
	var np := rows[0].size()
	for e in 2:
		var pe := PackedVector3Array()
		for i in nr:
			pe.append(rows[i][0 if e == 0 else np - 1])
		var cen := Vector3.ZERO
		for p in pe:
			cen += p
		cen /= float(nr)
		var out := (rows[0][0] - rows[0][1]) if e == 0 else (rows[0][np - 1] - rows[0][np - 2])
		for i in nr:
			k.tri(cen, pe[i], pe[(i + 1) % nr], out)
