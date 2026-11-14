extends RefCounted
## Koffer-Lkw des Sicherheitsdienstes (Vorplatz der Villa): detailliertes prozedurales 7,5-t-Frontlenker-
## Modell statt der Profil-Extrusion aus CarModel. Fahrerhaus mit geneigter Frontscheibe, Tuerfugen,
## Griffstange, Trittstufen, Spiegeln an Auslegern, Kuehlergrill, Scheinwerfern/Blinkern, Stossfaenger,
## Kennzeichen, Sonnenblende, Wischern und Dachmarkierungsleuchten; Leiterrahmen mit Tank, Batteriekasten,
## Luftkesseln und Auspufftopf; Kofferaufbau mit Alu-Eckprofilen, Seitenschutz, Kotfluegeln, Hecktueren
## mit Verschlussstangen und Scharnieren, Unterfahrschutz und Rueckleuchten; Raeder mit Reifenflanke,
## Profilrillen, Stahlfelge, Nabe und Radmuttern (hinten zwillingsbereift).
## Front = +Z, Boden y = 0, Breite 2,4 m, Laenge 7,0 m. Geometrie einmal gebaut und gecacht.

const Geo = preload("res://game/levels/level_geo.gd")
const Props = preload("res://game/levels/level_props.gd")

const HW := 1.15          # halbe Breite Fahrerhaus
const BOX_HW := 1.2       # halbe Breite Koffer
const ZF := 2.3           # Vorderachse
const ZR := -1.95         # Hinterachse
const WR := 0.48          # Radradius
const CAB_Z0 := 1.32      # Rueckwand Fahrerhaus
const CAB_ZF := 3.42      # Front Fahrerhaus (unten)
const BOX_Z0 := -3.45
const BOX_Z1 := 1.22
const BOX_Y0 := 1.02
const BOX_Y1 := 3.12

static var _parts: Dictionary = {}
static var _mats: Dictionary = {}

## Fahrzeug mit Kollision und Deckungspunkten wie LevelProps.vehicle(..., "truck", ...).
static func place(parent: Node3D, pos: Vector3, yaw_deg: float, cab_color: Color, covers: Array) -> StaticBody3D:
	var b := Geo.static_body(pos, yaw_deg)
	b.name = "Sicherheitsdienst_Lkw"
	var root := Node3D.new()
	b.add_child(root)
	build(root, cab_color)
	Geo.add_box_shape(b, Vector3(0, 0.3 + 2.82 * 0.5, -0.05), Vector3(2.4, 2.82, 6.95))
	Geo.add_box_shape(b, Vector3(0, BOX_Y1 - 0.15, (BOX_Z0 + BOX_Z1) * 0.5), Vector3(2.4, 0.3, BOX_Z1 - BOX_Z0))
	parent.add_child(b)
	Props._cover_sides(covers, pos, yaw_deg, 1.2, 3.5, 1.0, true)
	return b

static func build(root: Node3D, cab_color: Color) -> void:
	if _parts.is_empty():
		_make()
	var mats := _materials(cab_color)
	for key: String in _parts:
		var mi := MeshInstance3D.new()
		mi.name = "Truck_" + key
		mi.mesh = _parts[key]
		mi.material_override = mats[key]
		root.add_child(mi)

static func _materials(cab_color: Color) -> Dictionary:
	var k := cab_color.to_html()
	if _mats.has(k):
		return _mats[k]
	var paint := StandardMaterial3D.new()
	paint.albedo_color = cab_color
	paint.metallic = 0.45
	paint.roughness = 0.34
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.6
	paint.clearcoat_roughness = 0.25
	var panel := StandardMaterial3D.new()     # GFK-Kofferwand: matter, etwas heller
	panel.albedo_color = cab_color.lightened(0.08)
	panel.metallic = 0.1
	panel.roughness = 0.52
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.012, 0.014, 0.017)
	glass.metallic = 0.15
	glass.roughness = 0.03
	glass.metallic_specular = 0.7
	var m := {
		"paint": paint,
		"panel": panel,
		"glass": glass,
		"plastic": Geo.flat(Color(0.028, 0.028, 0.03), 0.72),
		"frame": Geo.flat(Color(0.035, 0.035, 0.038), 0.6, 0.4),
		"alu": Geo.flat(Color(0.56, 0.57, 0.59), 0.38, 0.85),
		"chrome": Geo.flat(Color(0.78, 0.78, 0.8), 0.14, 1.0),
		"rubber": Geo.flat(Color(0.03, 0.03, 0.032), 0.92),
		"rim": Geo.flat(Color(0.42, 0.43, 0.45), 0.42, 0.75),
		"lens": Geo.flat(Color(0.72, 0.72, 0.7), 0.06, 0.2),
		"amber": Geo.flat(Color(0.62, 0.27, 0.03), 0.12, 0.0, Color(1.0, 0.45, 0.08), 0.15),
		"red": Geo.flat(Color(0.32, 0.02, 0.02), 0.12, 0.0, Color(1.0, 0.05, 0.03), 0.12),
		"plate": Geo.flat(Color(0.84, 0.84, 0.8), 0.45),
		"blue": Geo.flat(Color(0.03, 0.09, 0.42), 0.5),
	}
	_mats[k] = m
	return m

# ------------------------------------------------------------------ Geometrie

static var _st: Dictionary = {}

static func _s(key: String) -> SurfaceTool:
	if not _st.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_st[key] = st
	return _st[key]

static func _add(key: String, mesh: Mesh, xf: Transform3D = Transform3D.IDENTITY) -> void:
	# Primitive (Box/Zylinder) sind indiziert, Extrusionen nicht: gemischt wuerde der Index-Puffer die
	# nicht indizierten Dreiecke verschlucken -> alles ent-indiziert anhaengen.
	var tmp := SurfaceTool.new()
	tmp.create_from(mesh, 0)
	tmp.deindex()
	_s(key).append_from(tmp.commit(), 0, xf)

static func _box(key: String, c: Vector3, size: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	var bm := BoxMesh.new()
	bm.size = size
	_add(key, bm, Transform3D(basis, c))

## Profil (z, y) mit runden Ecken, in X extrudiert (halbe Breite hw), bei x verschoben.
static func _ext(key: String, pts: Array, hw: float, bevel: float, x: float = 0.0, r: float = 0.04) -> void:
	_add(key, GunModels.extrude(GunModels.rounded(pts, r, true, 3), hw, bevel, 2), Transform3D(Basis.IDENTITY, Vector3(x, 0, 0)))

## Zylinder entlang einer Achse (a -> b).
static func _cyl(key: String, a: Vector3, b: Vector3, r: float, seg: int = 14) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = a.distance_to(b)
	cm.radial_segments = seg
	cm.rings = 1
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	_add(key, cm, Transform3D(Basis(side, up, side.cross(up)), (a + b) * 0.5))

## Rotationskoerper um die X-Achse: prof = [Vector2(radius, x)], an Position c, Seite sx (+1/-1 spiegelt x).
static func _lathe(key: String, c: Vector3, prof: Array, sx: float, seg: int = 28) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := prof.size()
	for i in n - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var d := p1 - p0
		# Normale im Profil (radial, axial); Profil laeuft innen -> aussen, also rechts davon = aussen
		var nr := Vector2(d.y, -d.x).normalized()
		for k in seg:
			var a0 := TAU * float(k) / float(seg)
			var a1 := TAU * float(k + 1) / float(seg)
			var v := [
				c + Vector3(p0.y * sx, cos(a0) * p0.x, sin(a0) * p0.x),
				c + Vector3(p1.y * sx, cos(a0) * p1.x, sin(a0) * p1.x),
				c + Vector3(p1.y * sx, cos(a1) * p1.x, sin(a1) * p1.x),
				c + Vector3(p0.y * sx, cos(a1) * p0.x, sin(a1) * p0.x),
			]
			var n0 := Vector3(nr.y * sx, cos(a0) * nr.x, sin(a0) * nr.x).normalized()
			var n1 := Vector3(nr.y * sx, cos(a1) * nr.x, sin(a1) * nr.x).normalized()
			_tri(st, v[0], v[1], v[2], n0, n0, n1)
			_tri(st, v[0], v[2], v[3], n0, n1, n1)
	_add(key, st.commit())

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	# Godot: Vorderseite im Uhrzeigersinn -> Kreuzprodukt zeigt entgegen der Normalen (wie GunModels._tri3)
	if (b - a).cross(c - a).dot(na + nb + nc) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)

static func _arch(out: Array, zc: float, r: float, y0: float) -> void:
	for i in 11:
		var a := PI * float(i) / 10.0
		out.append(Vector2(zc + cos(a) * r, y0 + sin(a) * r * 0.95))

static func _make() -> void:
	_st.clear()
	_cab()
	_cab_front()
	_cab_side_details()
	_chassis()
	_box_body()
	_rear()
	_wheels()
	for key: String in _st:
		var st: SurfaceTool = _st[key]
		_parts[key] = st.commit()
	_st.clear()

static func _cab() -> void:
	# Seitenprofil Fahrerhaus: Rueckwand, Dach, Frontscheibe geneigt, Front, Radlauf vorn
	var top: Array = [Vector3(CAB_Z0, 0.62, 0.0), Vector3(CAB_Z0, 3.0, 0.1), Vector3(3.14, 3.03, 0.22),
		Vector3(3.3, 2.84, 0.08), Vector3(CAB_ZF, 1.78, 0.1), Vector3(CAB_ZF + 0.02, 0.62, 0.03)]
	var bottom: Array = []
	_arch(bottom, ZF, WR + 0.13, 0.62)
	_ext("paint", top + bottom, HW, 0.08, 0.0, 0.05)
	# Kabinenrueckwand-Fuge / Dachkante (Regenrinne)
	_ext("plastic", GunModels.stroke([Vector2(CAB_Z0 + 0.06, 3.0), Vector2(3.1, 3.02)], 0.035), HW + 0.012, 0.012)
	# Frontscheibe (leicht vor der Schraege) mit Gummirahmen
	var ws: Array = [Vector2(3.285, 2.76), Vector2(3.395, 1.9), Vector2(3.445, 1.9), Vector2(3.335, 2.76)]
	_ext("plastic", ws, HW - 0.08, 0.02, 0.0, 0.03)
	var wsg: Array = [Vector2(3.3, 2.72), Vector2(3.4, 1.94), Vector2(3.452, 1.94), Vector2(3.352, 2.72)]
	_ext("glass", wsg, HW - 0.13, 0.015, 0.0, 0.04)
	# Seitenscheiben (Tuerfenster + kleines Eckfenster) mit Rahmen
	var sw: Array = [Vector2(2.12, 1.98), Vector2(2.12, 2.78), Vector2(3.18, 2.8), Vector2(3.33, 1.98)]
	_ext("plastic", sw, HW + 0.008, 0.008, 0.0, 0.06)
	var swg: Array = [Vector2(2.17, 2.03), Vector2(2.17, 2.74), Vector2(3.15, 2.76), Vector2(3.28, 2.03)]
	_ext("glass", swg, HW + 0.016, 0.006, 0.0, 0.05)
	var rw: Array = [Vector2(1.5, 2.1), Vector2(1.5, 2.74), Vector2(1.98, 2.74), Vector2(1.98, 2.1)]
	_ext("plastic", rw, HW + 0.008, 0.008, 0.0, 0.05)
	_ext("glass", [Vector2(1.54, 2.14), Vector2(1.54, 2.7), Vector2(1.94, 2.7), Vector2(1.94, 2.14)], HW + 0.016, 0.006, 0.0, 0.04)
	# Sonnenblende und Dachmarkierungsleuchten
	_ext("paint", [Vector2(3.16, 2.98), Vector2(3.16, 3.035), Vector2(3.44, 2.975), Vector2(3.44, 2.945)], HW - 0.06, 0.015, 0.0, 0.01)
	for x: float in [-0.45, 0.0, 0.45]:
		_box("amber", Vector3(x, 3.075, 3.08), Vector3(0.14, 0.05, 0.06))
	# Dachluke
	_box("plastic", Vector3(0.0, 3.06, 2.2), Vector3(0.8, 0.05, 0.75))
	# Wischer (geparkt unten an der Scheibe)
	for x: float in [-0.55, 0.35]:
		_box("plastic", Vector3(x, 1.96, 3.46), Vector3(0.78, 0.025, 0.025), Basis(Vector3.FORWARD, 0.08))
		_box("plastic", Vector3(x - 0.36, 1.93, 3.47), Vector3(0.06, 0.06, 0.05))

static func _cab_front() -> void:
	var zf := CAB_ZF + 0.03
	# Kuehlergrill: Rahmen + Lamellen
	_box("plastic", Vector3(0, 1.4, zf - 0.005), Vector3(1.62, 0.66, 0.03))
	for i in 6:
		_box("frame", Vector3(0, 1.14 + i * 0.1, zf + 0.022), Vector3(1.5, 0.035, 0.03))
	_box("chrome", Vector3(0, 1.74, zf + 0.02), Vector3(1.66, 0.04, 0.035))
	_cyl("chrome", Vector3(0, 1.62, zf + 0.01), Vector3(0, 1.62, zf + 0.055), 0.075, 20)
	# Scheinwerfer (Gehaeuse, Streuscheibe, Reflektoren) und Blinker
	for sx: float in [-1.0, 1.0]:
		var x := sx * 0.86
		_box("plastic", Vector3(x, 0.96, zf + 0.01), Vector3(0.48, 0.26, 0.06))
		_box("lens", Vector3(x - sx * 0.04, 0.96, zf + 0.045), Vector3(0.34, 0.2, 0.02))
		for k in 2:
			_cyl("chrome", Vector3(x - sx * (0.1 - k * 0.14), 0.96, zf + 0.03), Vector3(x - sx * (0.1 - k * 0.14), 0.96, zf + 0.05), 0.065, 16)
		_box("amber", Vector3(x + sx * 0.19, 0.96, zf + 0.045), Vector3(0.08, 0.2, 0.02))
		# seitlicher Blinker am Kotfluegel
		_box("amber", Vector3(sx * (HW + 0.004), 1.0, 3.02), Vector3(0.02, 0.05, 0.12))
	# Stossfaenger (Kunststoff) mit Trittmulde, Nebelscheinwerfern und Kennzeichen
	_ext("plastic", [Vector2(zf - 0.12, 0.34), Vector2(zf - 0.12, 0.8), Vector2(zf + 0.06, 0.8), Vector2(zf + 0.1, 0.62), Vector2(zf + 0.1, 0.42), Vector2(zf + 0.04, 0.34)],
		HW + 0.02, 0.04, 0.0, 0.03)
	_box("frame", Vector3(0, 0.79, zf + 0.06), Vector3(0.7, 0.03, 0.1))
	for sx: float in [-1.0, 1.0]:
		_cyl("plastic", Vector3(sx * 0.82, 0.5, zf + 0.08), Vector3(sx * 0.82, 0.5, zf + 0.12), 0.075, 16)
		_cyl("lens", Vector3(sx * 0.82, 0.5, zf + 0.115), Vector3(sx * 0.82, 0.5, zf + 0.125), 0.058, 16)
		# Abschlepp-Oese
		_box("frame", Vector3(sx * 0.35, 0.38, zf + 0.1), Vector3(0.08, 0.06, 0.06))
	_box("plate", Vector3(0, 0.58, zf + 0.112), Vector3(0.52, 0.115, 0.01))
	_box("blue", Vector3(-0.235, 0.58, zf + 0.118), Vector3(0.045, 0.11, 0.004))
	for i in 6:
		_box("plastic", Vector3(-0.15 + i * 0.065, 0.58, zf + 0.118), Vector3(0.035, 0.065, 0.003))

static func _cab_side_details() -> void:
	for sx: float in [-1.0, 1.0]:
		var xs := sx * (HW + 0.004)
		# Tuerfugen
		for seg: Array in [[Vector2(1.9, 0.72), Vector2(1.9, 2.95)], [Vector2(3.24, 1.32), Vector2(3.24, 1.95)],
				[Vector2(2.95, 1.25), Vector2(3.26, 1.25)], [Vector2(1.9, 2.95), Vector2(2.1, 2.98)]]:
			_ext("plastic", GunModels.stroke(seg, 0.012), 0.004, 0.0, xs)
		# Tuergriff, Schloss
		_box("plastic", Vector3(sx * (HW + 0.02), 1.82, 2.05), Vector3(0.035, 0.05, 0.22))
		_box("chrome", Vector3(sx * (HW + 0.02), 1.82, 2.2), Vector3(0.03, 0.03, 0.03))
		# Griffstange hinter der Tuer und Trittstufen hinter dem Vorderrad
		_cyl("chrome", Vector3(sx * (HW + 0.06), 1.15, 1.48), Vector3(sx * (HW + 0.06), 2.45, 1.48), 0.018, 10)
		_box("plastic", Vector3(sx * (HW + 0.04), 1.15, 1.48), Vector3(0.06, 0.05, 0.05))
		_box("plastic", Vector3(sx * (HW + 0.04), 2.45, 1.48), Vector3(0.06, 0.05, 0.05))
		for k in 2:
			var y := 0.36 + k * 0.32
			_box("alu", Vector3(sx * (HW - 0.2), y, 1.62), Vector3(0.42, 0.04, 0.34))
			_box("frame", Vector3(sx * (HW - 0.01), y - 0.08, 1.62), Vector3(0.03, 0.18, 0.34))
		# Spiegel: Ausleger oben/unten, Hauptspiegel + Weitwinkel, Frontspiegel
		var xm := sx * (HW + 0.3)
		_cyl("frame", Vector3(sx * HW, 2.62, 3.05), Vector3(xm, 2.6, 3.12), 0.017, 8)
		_cyl("frame", Vector3(sx * HW, 1.66, 3.1), Vector3(xm, 1.78, 3.12), 0.017, 8)
		_cyl("frame", Vector3(xm, 1.78, 3.12), Vector3(xm, 2.6, 3.12), 0.017, 8)
		_box("plastic", Vector3(xm + sx * 0.02, 2.3, 3.14), Vector3(0.24, 0.44, 0.06), Basis(Vector3.UP, sx * 0.12))
		_box("glass", Vector3(xm + sx * 0.02, 2.3, 3.11), Vector3(0.21, 0.4, 0.01), Basis(Vector3.UP, sx * 0.12))
		_box("plastic", Vector3(xm + sx * 0.02, 1.95, 3.14), Vector3(0.2, 0.2, 0.06), Basis(Vector3.UP, sx * 0.12))
		_box("glass", Vector3(xm + sx * 0.02, 1.95, 3.11), Vector3(0.17, 0.17, 0.01), Basis(Vector3.UP, sx * 0.12))
		# Kabinenaufhaengung hinten / Ansaugschnorchel rechts
		_box("frame", Vector3(sx * 0.5, 0.95, CAB_Z0 + 0.1), Vector3(0.12, 0.2, 0.12))
	_cyl("plastic", Vector3(HW + 0.06, 1.25, CAB_Z0 + 0.08), Vector3(HW + 0.06, 3.0, CAB_Z0 + 0.08), 0.085, 14)
	_box("plastic", Vector3(HW - 0.06, 2.92, CAB_Z0 + 0.08), Vector3(0.26, 0.12, 0.16))

static func _chassis() -> void:
	# Leiterrahmen und Querträger
	for sx: float in [-1.0, 1.0]:
		_box("frame", Vector3(sx * 0.44, 0.75, -0.15), Vector3(0.08, 0.26, 6.5))
		# Hilfsrahmen unter dem Koffer
		_box("frame", Vector3(sx * 0.46, 0.94, (BOX_Z0 + BOX_Z1) * 0.5), Vector3(0.1, 0.12, BOX_Z1 - BOX_Z0 - 0.1))
	for z: float in [2.9, 1.6, 0.4, -0.9, -2.7, -3.25]:
		_box("frame", Vector3(0, 0.74, z), Vector3(0.84, 0.18, 0.08))
	# Querträger des Koffers (sichtbar unter dem Aufbau)
	for i in 9:
		_box("frame", Vector3(0, BOX_Y0 - 0.05, BOX_Z0 + 0.2 + i * 0.53), Vector3(2.3, 0.07, 0.06))
	# Tank links (Alu, D-Form), Batteriekasten rechts, Luftkessel, Auspufftopf
	_cyl("alu", Vector3(-0.86, 0.66, 0.05), Vector3(-0.86, 0.66, 1.05), 0.27, 24)
	for z: float in [0.12, 0.98]:
		_cyl("frame", Vector3(-0.86, 0.66, z - 0.02), Vector3(-0.86, 0.66, z + 0.02), 0.28, 24)
	_cyl("plastic", Vector3(-0.86, 0.95, 0.85), Vector3(-0.86, 0.98, 0.85), 0.05, 12)
	_box("plastic", Vector3(0.84, 0.68, 0.55), Vector3(0.44, 0.42, 0.7))
	_box("frame", Vector3(0.84, 0.9, 0.55), Vector3(0.46, 0.03, 0.72))
	for sx: float in [-1.0, 1.0]:
		_cyl("frame", Vector3(sx * 0.7, 0.58, -0.75), Vector3(sx * 0.7, 0.58, -0.05), 0.12, 14)
	_cyl("alu", Vector3(0.62, 0.52, -0.25), Vector3(0.62, 0.52, 1.0), 0.16, 16)
	_cyl("frame", Vector3(0.62, 0.52, -0.25), Vector3(0.62, 0.52, -0.6), 0.04, 8)
	# Kardanwelle und Hinterachse
	_cyl("frame", Vector3(0, 0.5, 1.6), Vector3(0, 0.48, ZR + 0.2), 0.045, 10)
	_cyl("frame", Vector3(-0.9, WR, ZR), Vector3(0.9, WR, ZR), 0.06, 12)
	_box("frame", Vector3(0, WR, ZR), Vector3(0.36, 0.3, 0.3))
	_cyl("frame", Vector3(-0.85, WR, ZF), Vector3(0.85, WR, ZF), 0.05, 12)
	# Blattfedern
	for sx: float in [-1.0, 1.0]:
		for zc: float in [ZF, ZR]:
			_box("frame", Vector3(sx * 0.44, WR + 0.1, zc), Vector3(0.08, 0.06, 1.1))

static func _box_body() -> void:
	# Kofferaufbau: Waende mit kleiner Fase, Alu-Eckprofile, Bodenrahmen, Dachkante
	_ext("panel", [Vector2(BOX_Z0, BOX_Y0), Vector2(BOX_Z0, BOX_Y1), Vector2(BOX_Z1, BOX_Y1), Vector2(BOX_Z1, BOX_Y0)], BOX_HW - 0.02, 0.025, 0.0, 0.02)
	var hz := BOX_HW
	for sx: float in [-1.0, 1.0]:
		for z: float in [BOX_Z0, BOX_Z1]:
			_box("alu", Vector3(sx * (hz - 0.02), (BOX_Y0 + BOX_Y1) * 0.5, z), Vector3(0.07, BOX_Y1 - BOX_Y0 + 0.02, 0.07))
		# Dach- und Bodenleiste laengs
		_box("alu", Vector3(sx * (hz - 0.02), BOX_Y1, (BOX_Z0 + BOX_Z1) * 0.5), Vector3(0.07, 0.07, BOX_Z1 - BOX_Z0))
		_box("alu", Vector3(sx * (hz - 0.01), BOX_Y0 + 0.07, (BOX_Z0 + BOX_Z1) * 0.5), Vector3(0.06, 0.16, BOX_Z1 - BOX_Z0))
		# Paneelstoesse und Zurrleiste aussen
		for i in 3:
			var z := BOX_Z0 + (i + 1) * (BOX_Z1 - BOX_Z0) / 4.0
			_box("alu", Vector3(sx * (hz - 0.012), (BOX_Y0 + BOX_Y1) * 0.5, z), Vector3(0.012, BOX_Y1 - BOX_Y0 - 0.1, 0.035))
		_box("alu", Vector3(sx * (hz - 0.008), BOX_Y0 + 0.62, (BOX_Z0 + BOX_Z1) * 0.5), Vector3(0.014, 0.05, BOX_Z1 - BOX_Z0 - 0.1))
		# Seitenmarkierungsleuchten
		for i in 3:
			_box("amber", Vector3(sx * (hz + 0.005), BOX_Y0 + 0.05, BOX_Z0 + 0.6 + i * 1.6), Vector3(0.02, 0.04, 0.08))
		# Seitlicher Unterfahrschutz (2 Alu-Holme an Konsolen) zwischen den Achsen
		var z0 := ZR + WR + 0.25
		var z1 := ZF - WR - 0.6
		for y: float in [0.48, 0.78]:
			_box("alu", Vector3(sx * (hz - 0.06), y, (z0 + z1) * 0.5), Vector3(0.04, 0.1, z1 - z0))
		for z: float in [z0 + 0.15, (z0 + z1) * 0.5, z1 - 0.15]:
			_box("frame", Vector3(sx * (hz - 0.35), 0.72, z), Vector3(0.55, 0.06, 0.05))
			_box("frame", Vector3(sx * (hz - 0.08), 0.65, z), Vector3(0.04, 0.36, 0.05))
		# Kotfluegel ueber den Zwillingsreifen
		var arc: Array = []
		for i in 9:
			var a := lerpf(0.15, PI - 0.15, float(i) / 8.0)
			arc.append(Vector2(ZR + cos(a) * (WR + 0.1), WR + sin(a) * (WR + 0.1)))
		_add("plastic", GunModels.extrude(GunModels.stroke(arc, 0.03), 0.17, 0.008, 1), Transform3D(Basis.IDENTITY, Vector3(sx * 0.98, 0, 0)))
		_box("rubber", Vector3(sx * 0.98, 0.4, ZR - WR - 0.12), Vector3(0.36, 0.45, 0.012))

static func _rear() -> void:
	var zr := BOX_Z0 - 0.012
	# Hecktueren: Mittelfuge, Rahmenfugen
	_box("plastic", Vector3(0, (BOX_Y0 + BOX_Y1) * 0.5, zr), Vector3(0.02, BOX_Y1 - BOX_Y0 - 0.14, 0.01))
	_box("plastic", Vector3(0, BOX_Y1 - 0.08, zr), Vector3(2.2, 0.015, 0.01))
	_box("plastic", Vector3(0, BOX_Y0 + 0.16, zr), Vector3(2.2, 0.015, 0.01))
	for sx: float in [-1.0, 1.0]:
		# Verschlussstangen mit Lagern und Hebelgriffen
		for x: float in [0.3, 0.92]:
			var p := Vector3(sx * x, 0.0, zr - 0.03)
			_cyl("alu", p + Vector3(0, BOX_Y0 + 0.08, 0), p + Vector3(0, BOX_Y1 - 0.04, 0), 0.016, 10)
			for y: float in [BOX_Y0 + 0.12, BOX_Y0 + 1.05, BOX_Y1 - 0.12]:
				_box("alu", p + Vector3(0, y, 0.012), Vector3(0.07, 0.06, 0.035))
			_box("alu", p + Vector3(-sx * 0.12, BOX_Y0 + 0.75, -0.012), Vector3(0.26, 0.035, 0.025))
		# Scharniere
		for y: float in [BOX_Y0 + 0.3, BOX_Y0 + 1.05, BOX_Y1 - 0.62, BOX_Y1 - 0.25]:
			_box("alu", Vector3(sx * (BOX_HW - 0.1), y, zr - 0.02), Vector3(0.2, 0.06, 0.03))
		# Ruckleuchten am Unterfahrschutz
		_box("plastic", Vector3(sx * 0.82, 0.62, -3.38), Vector3(0.36, 0.16, 0.06))
		_box("red", Vector3(sx * 0.88, 0.62, -3.415), Vector3(0.2, 0.12, 0.02))
		_box("amber", Vector3(sx * 0.7, 0.62, -3.415), Vector3(0.08, 0.12, 0.02))
		_box("lens", Vector3(sx * 0.62, 0.62, -3.415), Vector3(0.05, 0.12, 0.02))
		# Konsolen des Unterfahrschutzes
		_box("frame", Vector3(sx * 0.44, 0.64, -3.3), Vector3(0.07, 0.26, 0.12))
	# Heck-Unterfahrschutz
	_box("alu", Vector3(0, 0.46, -3.36), Vector3(2.2, 0.12, 0.1))
	_box("plate", Vector3(0, 0.62, -3.41), Vector3(0.52, 0.115, 0.01))
	_box("blue", Vector3(-0.235, 0.62, -3.417), Vector3(0.045, 0.11, 0.004))
	for i in 6:
		_box("plastic", Vector3(-0.15 + i * 0.065, 0.62, -3.417), Vector3(0.035, 0.065, 0.003))
	# Rueckfahrkamera und Rundumleuchte-Sockel am Koffer
	_box("plastic", Vector3(0, BOX_Y1 - 0.06, zr - 0.04), Vector3(0.14, 0.08, 0.08))

static func _wheels() -> void:
	# Reifen: Flanke + Lauffläche mit Rillen (Radius, x relativ zur Radmitte)
	var tw := 0.27
	var h := tw * 0.5
	var tire: Array = [Vector2(0.31, -h + 0.01), Vector2(0.38, -h - 0.005), Vector2(0.44, -h + 0.005), Vector2(WR - 0.01, -h + 0.03),
		Vector2(WR, -h + 0.06), Vector2(WR, -0.06), Vector2(WR - 0.012, -0.055), Vector2(WR - 0.012, -0.035), Vector2(WR, -0.03),
		Vector2(WR, 0.03), Vector2(WR - 0.012, 0.035), Vector2(WR - 0.012, 0.055), Vector2(WR, 0.06), Vector2(WR, h - 0.06),
		Vector2(WR - 0.01, h - 0.03), Vector2(0.44, h - 0.005), Vector2(0.38, h + 0.005), Vector2(0.31, h - 0.01)]
	# Stahlfelge: Felgenhorn, Schuessel zur Nabe, Nabe; x positiv = aussen
	var rim: Array = [Vector2(0.315, -h + 0.02), Vector2(0.315, h - 0.005), Vector2(0.3, h - 0.012), Vector2(0.27, h - 0.04),
		Vector2(0.2, h - 0.05), Vector2(0.15, h - 0.04), Vector2(0.12, h - 0.03), Vector2(0.1, h - 0.005), Vector2(0.0, h - 0.005)]
	for sx: float in [-1.0, 1.0]:
		# Vorderrad (einfach)
		var cf := Vector3(sx * (HW - 0.1), WR, ZF)
		_lathe("rubber", cf, tire, sx)
		_lathe("rim", cf, rim, sx, 24)
		_nuts(cf, sx, h)
		# Hinterachse: Zwillingsreifen
		var outer := Vector3(sx * (BOX_HW - 0.13 - 0.005), WR, ZR)
		var inner := outer - Vector3(sx * (tw + 0.02), 0, 0)
		_lathe("rubber", outer, tire, sx)
		_lathe("rubber", inner, tire, sx)
		_lathe("rim", outer, rim, sx, 24)
		_nuts(outer, sx, h)

static func _nuts(c: Vector3, sx: float, h: float) -> void:
	for k in 8:
		var a := TAU * float(k) / 8.0
		var p := c + Vector3(sx * (h - 0.02), cos(a) * 0.14, sin(a) * 0.14)
		_cyl("chrome", p, p + Vector3(sx * 0.03, 0, 0), 0.016, 6)
	_cyl("chrome", c + Vector3(sx * (h - 0.01), 0, 0), c + Vector3(sx * (h + 0.04), 0, 0), 0.07, 16)
