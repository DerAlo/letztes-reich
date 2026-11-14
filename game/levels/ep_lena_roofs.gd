extends RefCounted
## Berliner Dachlandschaft fuer "Lena – Ueber den Daechern" (ep_lena.gd). Reine Optik ohne Kollision:
## Dachpappe (Poly Haven "bitumen") auf allen Flachdaechern, Mansarden mit Schiefer ("roof_slates_03") statt
## der dunklen Quader aus berlin_props.block, Zinkkanten, Rinnen, Gauben, Brandwand-Bruestungen, Schornsteinkoepfe
## mit Tonaufsaetzen, Oberlichter, Entluefter, Antennen/Schuesseln, Klimageraete auf den Regierungsbauten und
## Aufbauten/Bruestungen auf den Hochhaeusern der Skyline. Alles wird je Material zu einem Mesh gebuendelt.
## Sperrzonen (EXCL) halten Stellungen, Schusslinien (Lampe, Gegenscharfschuetze) und die Sicht vom
## Aufzugshaus frei; Kollision, Navmesh und Bot-Wege bleiben unveraendert.

const Geo = preload("res://game/levels/level_geo.gd")
const SK = preload("res://game/levels/street_kit.gd")

## Sperrzonen fuer Aufbauten (Welt-xz): [x0, x1, z0, z1]
const EXCL: Array = [
	[-17.5, -10.5, -27.0, -8.0],     # Dach A (Stellung + Sicht entlang der Strasse)
	[0.0, 30.0, -172.0, -158.0],     # Dach B: Aufzugshaus + Blick ueber das Ministeriumsdach
	[22.5, 31.5, -134.0, -116.0],    # Schusslinie Dach B -> Suchscheinwerfer auf dem Anbau
	[-32.0, -24.0, -148.0, -120.0],  # Gegenscharfschuetze, Regierungsbau-Vorderkante
]

var mats: Dictionary
var rng := RandomNumberGenerator.new()
var xf := Transform3D.IDENTITY
var _bb: Dictionary = {}
var _cyl: Dictionary = {}
var _models: Array = []   # [name, pos, yaw, scale]

func _init(p_mats: Dictionary, seed_: int) -> void:
	mats = p_mats
	rng.seed = seed_

# --------------------------------------------------------------------------- Sammler

func _batch(key: String) -> Geo.BoxBatch:
	if not _bb.has(key):
		_bb[key] = Geo.BoxBatch.new()
	return _bb[key]

func box(key: String, c: Vector3, s: Vector3, rot: Basis = Basis.IDENTITY) -> void:
	_batch(key).add(xf * c, s, xf.basis * rot)

func cyl(key: String, c: Vector3, r_top: float, r_bot: float, h: float, seg: int = 10, rot: Basis = Basis.IDENTITY) -> void:
	var ck := "%s|%s|%s|%s" % [r_top, r_bot, h, seg]
	if not _cyl.has(ck):
		var cm := CylinderMesh.new()
		cm.top_radius = r_top
		cm.bottom_radius = r_bot
		cm.height = h
		cm.radial_segments = seg
		cm.rings = 1
		_cyl[ck] = cm
	var bb := _batch(key)
	bb.st.append_from(_cyl[ck], 0, Transform3D(xf.basis * rot, xf * c))
	bb.count += 1

## Mansard-Mantel: Pyramidenstumpf ohne Deckel. Unten Rechteck (x0..x1, z0..z1) um m erweitert, oben um e.
func frustum(key: String, x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, m: float, e: float) -> void:
	var b := [Vector3(x0 - m, y0, z0 - m), Vector3(x1 + m, y0, z0 - m), Vector3(x1 + m, y0, z1 + m), Vector3(x0 - m, y0, z1 + m)]
	var t := [Vector3(x0 - e, y1, z0 - e), Vector3(x1 + e, y1, z0 - e), Vector3(x1 + e, y1, z1 + e), Vector3(x0 - e, y1, z1 + e)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var j := (i + 1) % 4
		var a: Vector3 = b[i]
		var bq: Vector3 = b[j]
		var c: Vector3 = t[j]
		var d: Vector3 = t[i]
		var nrm := (c - a).cross(bq - a).normalized()
		if nrm.dot(((a + bq) * 0.5) - Vector3((x0 + x1) * 0.5, y0, (z0 + z1) * 0.5)) < 0.0:
			nrm = -nrm
		var w := a.distance_to(bq)
		var hgt := a.distance_to(d)
		var quad := [[a, Vector2(0, hgt)], [bq, Vector2(w, hgt)], [c, Vector2(w, 0)], [a, Vector2(0, hgt)], [c, Vector2(w, 0)], [d, Vector2(0, 0)]]
		# Wicklung so waehlen, dass die Normale nach aussen zeigt
		if (bq - a).cross(c - a).dot(nrm) > 0.0:
			quad = [[a, Vector2(0, hgt)], [c, Vector2(w, 0)], [bq, Vector2(w, hgt)], [a, Vector2(0, hgt)], [d, Vector2(0, 0)], [c, Vector2(w, 0)]]
		for v: Array in quad:
			st.set_normal(nrm)
			st.set_uv(v[1])
			st.add_vertex(v[0])
	st.generate_tangents()
	var mesh := st.commit()
	var bb := _batch(key)
	bb.st.append_from(mesh, 0, xf)
	bb.count += 1

func build(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Dachlandschaft"
	parent.add_child(root)
	var no_shadow := ["glow", "red"]
	for k: String in _bb:
		var mesh: ArrayMesh = (_bb[k] as Geo.BoxBatch).build()
		if mesh == null:
			continue
		var mi := Geo.mesh_node(mesh, mats.get(k, Geo.flat(Color.MAGENTA)), Vector3.ZERO, not no_shadow.has(k))
		mi.name = "R_" + k
		root.add_child(mi)
	_bb.clear()
	for md: Array in _models:
		SK.model(root, md[0], md[1], md[2], md[3])
	_models.clear()
	return root

# --------------------------------------------------------------------------- Sperrzonen

func _free(local_p: Vector3) -> bool:
	var p := xf * local_p
	for e: Array in EXCL:
		if p.x > e[0] and p.x < e[1] and p.z > e[2] and p.z < e[3]:
			return false
	return true

# --------------------------------------------------------------------------- Gebaeude

## Dach eines berlin_props.block (gleiche Parameter). mansard = der Block hat den Dachaufbau (roof=true).
## frame: Transform des Bauframes (Ministerium ist um -90 Grad gedreht). gov = Regierungsbau (Technik statt Gauben).
func block_roof(side: int, face_x: float, z0: float, z1: float, depth: float, h: float, mansard: bool, frame: Transform3D = Transform3D.IDENTITY, gov: bool = false) -> void:
	xf = frame
	var n := -float(side)
	var L := absf(z0 - z1)
	var cz := (z0 + z1) / 2.0
	var cx := face_x - n * depth / 2.0
	var rear := face_x - n * depth
	# Dachpappe ueber die ganze Flaeche, Bahnen leicht versetzt (zweite Lage als Flicken)
	box("felt", Vector3(cx, h + 0.015, cz), Vector3(depth - 0.05, 0.03, L - 0.05))
	for i in rng.randi_range(2, 4):
		var pz := cz + rng.randf_range(-L * 0.4, L * 0.4)
		var px := face_x - n * rng.randf_range(1.0, 4.0)
		box("felt_patch", Vector3(px, h + 0.034, pz), Vector3(rng.randf_range(1.0, 2.2), 0.012, rng.randf_range(1.2, 3.0)))
	# Brandwaende/Attika an Rueckseite und Stirnseiten (Ziegel mit Betonabdeckung)
	var ph := 0.65
	box("brick", Vector3(rear + n * 0.16, h + ph / 2.0, cz), Vector3(0.32, ph, L))
	box("conc", Vector3(rear + n * 0.16, h + ph + 0.04, cz), Vector3(0.44, 0.08, L + 0.08))
	for zz: float in [z0 - 0.16, z1 + 0.16]:
		box("brick", Vector3(cx, h + ph / 2.0, zz), Vector3(depth, ph, 0.32))
		box("conc", Vector3(cx, h + ph + 0.04, zz), Vector3(depth + 0.08, 0.08, 0.44))
	# Mansarde
	var strip_x1 := rear + n * 0.6   # Ende des vorderen Flachstreifens
	if mansard and depth > 7.0:
		var mw := depth - 6.0
		var mcx := cx - n * 2.0
		var mx0 := mcx - mw / 2.0
		var mx1 := mcx + mw / 2.0
		var mz0 := cz - (L - 3.0) / 2.0
		var mz1 := cz + (L - 3.0) / 2.0
		var y1 := h + 3.24
		var m := 0.5
		frustum("slate", mx0, mx1, mz0, mz1, h + 0.03, y1, m, 0.04)
		box("felt", Vector3(mcx, y1 + 0.02, cz), Vector3(mw + 0.08, 0.04, L - 3.0 + 0.08))
		# Zinkkante am Knick und Rinne am Fuss
		for s: float in [-1.0, 1.0]:
			box("zinc", Vector3(mcx + s * (mw / 2.0 + 0.06), y1 - 0.02, cz), Vector3(0.1, 0.14, L - 3.0 + 0.28))
			box("zinc", Vector3(mcx, y1 - 0.02, cz + s * ((L - 3.0) / 2.0 + 0.06)), Vector3(mw + 0.28, 0.14, 0.1))
			box("zinc", Vector3(mcx + s * (mw / 2.0 + m + 0.05), h + 0.12, cz), Vector3(0.14, 0.12, L - 3.0 + 2.0 * m + 0.2))
			box("zinc", Vector3(mcx, h + 0.12, cz + s * ((L - 3.0) / 2.0 + m + 0.05)), Vector3(mw + 2.0 * m + 0.2, 0.12, 0.14))
		strip_x1 = mcx + n * (mw / 2.0 + m)
		_dormers(n, mcx + n * mw / 2.0, mz0, mz1, h, m, gov)
		_mansard_top(n, mcx, mw, cz, L - 3.0, y1, gov)
	if gov:
		# Traufgesims aus Sandstein mit Zinkabdeckung (nur 0,22 m hoch: verdeckt keinen liegenden Schuetzen)
		box("conc", Vector3(face_x - n * 0.3, h + 0.09, cz), Vector3(0.6, 0.18, L))
		box("zinc", Vector3(face_x - n * 0.3, h + 0.2, cz), Vector3(0.66, 0.04, L + 0.04))
		box("zinc", Vector3(face_x - n * 0.68, h + 0.07, cz), Vector3(0.16, 0.12, L - 0.2))   # Rinne
	# Vorderer Flachstreifen: Oberlichter, Entluefter, Ausstiegsluken
	var fx0 := face_x - n * 0.9
	var span := absf(strip_x1 - fx0)
	if span > 1.2:
		var cnt := int(L / 6.0)
		for i in cnt:
			var pz := z0 - (float(i) + rng.randf_range(0.2, 0.8)) * (L / float(cnt))
			var px := fx0 - n * rng.randf_range(0.4, maxf(0.5, span - 0.8))
			var p := Vector3(px, h, pz)
			if not _free(p):
				continue
			var r := rng.randf()
			if r < 0.35:
				_skylight(p, n)
			elif r < 0.7:
				_vent(p)
			elif r < 0.85:
				box("zinc", p + Vector3(0, 0.16, 0), Vector3(0.9, 0.32, 0.9))
				box("zinc", p + Vector3(0, 0.34, 0), Vector3(1.0, 0.04, 1.0))
			else:
				_vent(p)
				_vent(p + Vector3(0, 0, rng.randf_range(0.5, 0.9)))

func _dormers(n: float, x_edge: float, mz0: float, mz1: float, h: float, m: float, gov: bool = false) -> void:
	var ln := mz1 - mz0
	var cnt := int(ln / (5.0 if gov else 4.0))
	if cnt < 1:
		return
	var step := ln / float(cnt)
	for i in cnt:
		var z := mz0 + step * (float(i) + 0.5)
		if gov:
			_gov_dormer(n, x_edge, z, h, m)
			continue
		var w := 1.4
		var d := 0.9                         # Tiefe (in den Mansardmantel hinein)
		var fx := x_edge + n * (m + 0.02)     # Vorderflaeche auf Hoehe der Traufe
		var c := Vector3(fx - n * d / 2.0, h + 1.45, z)
		box("slate", c, Vector3(d, 1.7, w))
		box("zinc", c + Vector3(-n * 0.05, 0.9, 0), Vector3(d + 0.25, 0.08, w + 0.2))
		box("trim", Vector3(fx + n * 0.01, h + 1.35, z), Vector3(0.04, 1.2, w - 0.3))
		var lit := rng.randf() < 0.18
		box("glow" if lit else "glass", Vector3(fx + n * 0.03, h + 1.35, z), Vector3(0.03, 1.02, w - 0.5))
		box("trim", Vector3(fx + n * 0.05, h + 1.35, z), Vector3(0.03, 1.02, 0.06))
		box("zinc", Vector3(fx + n * 0.08, h + 0.78, z), Vector3(0.16, 0.05, w - 0.2))

## Regierungsbau-Gaube: Sandsteingewaende mit Segmentgiebel und Sohlbank, Sprossenfenster, Zinkdach.
func _gov_dormer(n: float, x_edge: float, z: float, h: float, m: float) -> void:
	var w := 1.6
	var d := 1.0
	var fx := x_edge + n * (m + 0.02)
	var c := Vector3(fx - n * d / 2.0, h + 1.5, z)
	box("slate", c, Vector3(d, 1.8, w))
	for s: float in [-1.0, 1.0]:
		box("conc", Vector3(fx + n * 0.03, h + 1.45, z + s * (w / 2.0 - 0.1)), Vector3(0.14, 1.7, 0.22))
	box("conc", Vector3(fx + n * 0.04, h + 2.38, z), Vector3(0.18, 0.2, w + 0.12))
	box("conc", Vector3(fx + n * 0.04, h + 2.6, z - w * 0.24), Vector3(0.16, 0.12, w * 0.56), Basis(Vector3(1, 0, 0), deg_to_rad(-18.0)))
	box("conc", Vector3(fx + n * 0.04, h + 2.6, z + w * 0.24), Vector3(0.16, 0.12, w * 0.56), Basis(Vector3(1, 0, 0), deg_to_rad(18.0)))
	box("zinc", c + Vector3(-n * 0.1, 1.0, 0), Vector3(d + 0.1, 0.06, w + 0.1))
	box("conc", Vector3(fx + n * 0.06, h + 0.6, z), Vector3(0.22, 0.1, w + 0.1))
	var lit := rng.randf() < 0.22
	box("glow" if lit else "glass", Vector3(fx, h + 1.45, z), Vector3(0.03, 1.5, w - 0.42))
	box("trim", Vector3(fx + n * 0.02, h + 1.45, z), Vector3(0.03, 1.5, 0.06))
	box("trim", Vector3(fx + n * 0.02, h + 1.75, z), Vector3(0.03, 0.06, w - 0.42))

func _mansard_top(n: float, mcx: float, mw: float, cz: float, ln: float, y1: float, gov: bool) -> void:
	# Schornsteinkoepfe paarweise entlang der Firstlinie, dazu einzelne an den Brandwaenden
	var cnt := maxi(int(ln / 6.5), 1)
	for i in cnt:
		var z := cz - ln / 2.0 + (float(i) + rng.randf_range(0.3, 0.7)) * ln / float(cnt)
		var x := mcx + rng.randf_range(-mw * 0.3, mw * 0.3)
		var p := Vector3(x, y1 + 0.04, z)
		if not _free(p):
			continue
		if gov and rng.randf() < 0.55:
			_hvac(p, n)
		else:
			_chimney(p, rng.randf_range(0.9, 1.9))
	for s: float in [-1.0, 1.0]:
		var p2 := Vector3(mcx + rng.randf_range(-mw * 0.25, mw * 0.25), y1 + 0.04, cz + s * (ln / 2.0 - 0.6))
		if _free(p2) and rng.randf() < 0.8:
			_chimney(p2, rng.randf_range(1.2, 2.0))
	# Antenne oder Schuessel
	var pa := Vector3(mcx + rng.randf_range(-mw * 0.3, mw * 0.3), y1 + 0.04, cz + rng.randf_range(-ln * 0.35, ln * 0.35))
	if _free(pa):
		_antenna(pa)
	var pd := Vector3(mcx + rng.randf_range(-mw * 0.3, mw * 0.3), y1 + 0.04, cz + rng.randf_range(-ln * 0.4, ln * 0.4))
	if _free(pd) and rng.randf() < 0.7:
		_dish(pd)
	if gov:
		for i in 2:
			var pm := Vector3(mcx + rng.randf_range(-mw * 0.3, mw * 0.3), y1 + 0.04, cz + rng.randf_range(-ln * 0.4, ln * 0.4))
			if _free(pm):
				_models.append(["exterior_aircon_unit", xf * pm, rad_to_deg(xf.basis.get_euler().y) + 90.0 * float(rng.randi_range(0, 3)), 1.3])

# --------------------------------------------------------------------------- Aufbauten

func _chimney(p: Vector3, ch: float) -> void:
	var w := rng.randf_range(0.7, 1.5)
	var d := rng.randf_range(0.5, 0.75)
	var R := Basis(Vector3.UP, deg_to_rad(90.0 * float(rng.randi_range(0, 1))))
	box("brick", p + Vector3(0, ch / 2.0, 0), Vector3(w, ch, d), R)
	box("conc", p + Vector3(0, ch + 0.05, 0), Vector3(w + 0.14, 0.1, d + 0.14), R)
	box("brick", p + Vector3(0, ch - 0.25, 0), Vector3(w + 0.08, 0.12, d + 0.08), R)   # Kragschicht
	var pots := clampi(int(w / 0.45), 1, 3)
	for j in pots:
		var off := R * Vector3((float(j) - (pots - 1) * 0.5) * 0.38, 0, 0)
		cyl("pot", p + off + Vector3(0, ch + 0.28, 0), 0.1, 0.13, 0.36, 8)

func _vent(p: Vector3) -> void:
	var hh := rng.randf_range(0.5, 1.1)
	cyl("zinc", p + Vector3(0, hh / 2.0, 0), 0.09, 0.09, hh, 8)
	cyl("zinc", p + Vector3(0, hh + 0.07, 0), 0.02, 0.2, 0.14, 8)
	if rng.randf() < 0.3:   # Drehlüfter
		cyl("zinc", p + Vector3(0, hh + 0.22, 0), 0.16, 0.16, 0.22, 10)
		cyl("zinc", p + Vector3(0, hh + 0.38, 0), 0.02, 0.17, 0.1, 10)

func _skylight(p: Vector3, n: float) -> void:
	var w := rng.randf_range(0.9, 1.4)
	var l := rng.randf_range(1.1, 1.8)
	box("zinc", p + Vector3(0, 0.18, 0), Vector3(w + 0.12, 0.36, l + 0.12))
	var tilt := Basis(Vector3(0, 0, 1), deg_to_rad(8.0 * n))
	var lit := rng.randf() < 0.25
	box("glow" if lit else "glass", p + Vector3(0, 0.4, 0), Vector3(w, 0.04, l), tilt)
	for s: float in [-1.0, 1.0]:
		box("trim", p + Vector3(0, 0.43, s * l * 0.25), Vector3(w + 0.04, 0.03, 0.04), tilt)

func _antenna(p: Vector3) -> void:
	var hh := rng.randf_range(2.6, 4.2)
	cyl("metal", p + Vector3(0, hh / 2.0, 0), 0.03, 0.035, hh, 6)
	box("metal", p + Vector3(0, 0.1, 0), Vector3(0.5, 0.2, 0.5))
	var yaw := Basis(Vector3.UP, rng.randf() * TAU)
	for k in 3:
		var y := hh - 0.25 - k * 0.55
		var lw := 1.3 - k * 0.25
		box("metal", p + Vector3(0, y, 0), Vector3(lw, 0.025, 0.025), yaw)
		for e in 5:
			var off := yaw * Vector3((float(e) - 2.0) * lw * 0.22, 0, 0)
			box("metal", p + off + Vector3(0, y, 0), Vector3(0.015, 0.015, 0.5), yaw)
	# Abspannseile
	for a in 3:
		var dir := Basis(Vector3.UP, a * TAU / 3.0) * Vector3(1, 0, 0)
		var top := p + Vector3(0, hh * 0.6, 0)
		var bot := p + dir * 1.4
		var mid := (top + bot) * 0.5
		var v := top - bot
		var b := Basis.looking_at(v.normalized(), Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT)
		box("metal", mid, Vector3(0.01, 0.01, v.length()), b)

func _dish(p: Vector3) -> void:
	box("metal", p + Vector3(0, 0.45, 0), Vector3(0.06, 0.9, 0.06))
	var b := Basis(Vector3.UP, deg_to_rad(rng.randf_range(150.0, 210.0))) * Basis(Vector3.RIGHT, deg_to_rad(65.0))
	cyl("dish", p + Vector3(0, 0.95, 0), 0.4, 0.33, 0.08, 14, b)

func _hvac(p: Vector3, n: float) -> void:
	var s := Vector3(rng.randf_range(1.8, 3.0), rng.randf_range(1.2, 1.7), rng.randf_range(1.2, 1.8))
	box("trapez", p + Vector3(0, s.y / 2.0, 0), s)
	box("zinc", p + Vector3(0, s.y + 0.03, 0), Vector3(s.x + 0.1, 0.06, s.z + 0.1))
	cyl("dark", p + Vector3(n * s.x * 0.2, s.y + 0.08, 0), 0.38, 0.38, 0.1, 16)
	cyl("zinc", p + Vector3(-n * s.x * 0.25, s.y + 0.5, 0), 0.22, 0.22, 1.0, 10)
	cyl("zinc", p + Vector3(-n * s.x * 0.25, s.y + 1.05, 0), 0.03, 0.34, 0.14, 10)

# --------------------------------------------------------------------------- Weitere Flachdaecher

## Flachdach (Rechteck x0..x1, z0..z1 auf Hoehe top): Pappe, umlaufende Attika, optional Technik.
func flat_roof(x0: float, x1: float, z0: float, z1: float, top: float, parapet: float, props: int, n: float = 1.0) -> void:
	xf = Transform3D.IDENTITY
	var c := Vector3((x0 + x1) / 2.0, top, (z0 + z1) / 2.0)
	var sx := x1 - x0
	var sz := z1 - z0
	box("felt", c + Vector3(0, 0.015, 0), Vector3(sx - 0.05, 0.03, sz - 0.05))
	if parapet > 0.0:
		for s: float in [-1.0, 1.0]:
			box("conc", c + Vector3(s * (sx / 2.0 - 0.14), parapet / 2.0, 0), Vector3(0.28, parapet, sz))
			box("conc", c + Vector3(0, parapet / 2.0, s * (sz / 2.0 - 0.14)), Vector3(sx, parapet, 0.28))
			box("zinc", c + Vector3(s * (sx / 2.0 - 0.14), parapet + 0.025, 0), Vector3(0.36, 0.05, sz + 0.04))
			box("zinc", c + Vector3(0, parapet + 0.025, s * (sz / 2.0 - 0.14)), Vector3(sx + 0.04, 0.05, 0.36))
	for i in props:
		var p := Vector3(rng.randf_range(x0 + 1.5, x1 - 1.5), top, rng.randf_range(z0 + 1.5, z1 - 1.5))
		if not _free(p):
			continue
		var r := rng.randf()
		if r < 0.3:
			_hvac(p, n)
		elif r < 0.6:
			_skylight(p, n)
		elif r < 0.85:
			_vent(p)
		else:
			_dish(p)

## Hochhaus der Skyline (Box mit Mitte c, Groesse s): Attika, Pappe, Treppen-/Aufzugsaufbau, Technik,
## auf hohen Bauten ein Antennenmast mit Flugwarnlicht.
func tower_roof(c: Vector3, s: Vector3) -> void:
	xf = Transform3D.IDENTITY
	var top := c.y + s.y / 2.0
	var p0 := Vector3(c.x, top, c.z)
	box("felt", p0 + Vector3(0, 0.015, 0), Vector3(s.x - 0.1, 0.03, s.z - 0.1))
	var ph := rng.randf_range(0.7, 1.2)
	for sd: float in [-1.0, 1.0]:
		box("sky", p0 + Vector3(sd * (s.x / 2.0 - 0.2), ph / 2.0, 0), Vector3(0.4, ph, s.z))
		box("sky", p0 + Vector3(0, ph / 2.0, sd * (s.z / 2.0 - 0.2)), Vector3(s.x, ph, 0.4))
		box("zinc", p0 + Vector3(sd * (s.x / 2.0 - 0.2), ph + 0.03, 0), Vector3(0.5, 0.06, s.z + 0.06))
		box("zinc", p0 + Vector3(0, ph + 0.03, sd * (s.z / 2.0 - 0.2)), Vector3(s.x + 0.06, 0.06, 0.5))
	# Treppenhaus/Aufzugsaufbau
	var hs := Vector3(rng.randf_range(3.5, 6.0), rng.randf_range(2.6, 3.6), rng.randf_range(3.5, 6.0))
	var hp := p0 + Vector3(rng.randf_range(-s.x * 0.2, s.x * 0.2), 0, rng.randf_range(-s.z * 0.2, s.z * 0.2))
	box("sky", hp + Vector3(0, hs.y / 2.0, 0), hs)
	box("zinc", hp + Vector3(0, hs.y + 0.04, 0), hs + Vector3(0.15, -hs.y + 0.08, 0.15))
	# Technik
	for i in rng.randi_range(1, 3):
		var tp := p0 + Vector3(rng.randf_range(-s.x * 0.35, s.x * 0.35), 0, rng.randf_range(-s.z * 0.35, s.z * 0.35))
		if tp.distance_to(hp) < 4.0:
			continue
		_hvac(tp, 1.0)
	if s.y > 34.0 or rng.randf() < 0.35:
		var mh := rng.randf_range(5.0, 10.0)
		var mp := hp + Vector3(0, hs.y, 0)
		cyl("metal", mp + Vector3(0, mh / 2.0, 0), 0.06, 0.1, mh, 6)
		for k in 3:
			box("metal", mp + Vector3(0, mh * (0.45 + 0.17 * k), 0), Vector3(1.4 - 0.3 * k, 0.04, 0.04))
		box("red", mp + Vector3(0, mh + 0.1, 0), Vector3(0.22, 0.22, 0.22))
