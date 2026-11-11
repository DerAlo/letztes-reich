extends RefCounted
## Prozedurales Zielfernrohr-Gewehr im Stil H&K G28 / HK417 (fiktive Beschriftung "MR7  Kal. 7,62 x 51").
## Masse in Metern, Lauf entlang -Z (Muendung bei z = -0.66), +Y oben, +X = rechte Waffenseite.
## Ursprung wie beim G36C im Bereich Abzug/Griffstueck. Gleiche Bauweise wie gun_models.gd:
## gerundete Extrusionen, Drehkoerper, echte Ausschnitte (M-LOK-Schlitze, Muendungsbremse, Schaftfenster).
##
## Teile: eloxiertes Ober-/Unterteil mit durchgehender Picatinny-Schiene, Vorderschaft mit M-LOK-Schlitzen,
## schwerer Lauf mit Muendungsbremse, verstellbarer Schaft mit Wangenauflage, 20-Schuss-Stahlmagazin
## ("Magazine"), Spannhebel ("Charging_Handle") und ein detailliertes Zielfernrohr 3-20x56 (30-mm-Rohr,
## Tuerme mit Skalen, Vergroesserungsring, Okular mit Dioptrienring, Klappdeckel) auf Blockmontage.
##
## Metas: muzzle, eject, length, optic_mount (Oberkante Schiene), scope_eye (Okularlinse auf der
## optischen Achse), scope_front (Objektivlinse auf der optischen Achse).

const BORE: float = 0.03          # Laufachse (y)
const RAIL_Y: float = 0.05        # Unterkante Picatinny = Oberkante Gehaeuse
const RAIL_TOP: float = 0.0595
const YS: float = 0.0965          # Zielfernrohr-Achse (y)
const ZT: float = -0.038          # Mitte der Tuerme (z)
const Z_EYE: float = 0.1325       # Okularlinse
const Z_OBJ: float = -0.2255      # Objektivlinse
# Vorderschaft-Querschnitt (abgerundetes Rechteck, hohl)
const HG_A: float = 0.025         # halbe Breite
const HG_C: float = 0.024         # halbe Hoehe
const HG_YC: float = 0.026        # Mitte (y)
const HG_RC: float = 0.011        # Eckenradius
const HG_T: float = 0.0028        # Wandstaerke
const HG_S: float = 0.00375       # halbe Schlitzbreite
const HG_Z0: float = -0.136
const HG_Z1: float = -0.495
const WHITE := Color(0.84, 0.84, 0.8)
const GREY := Color(0.6, 0.6, 0.58)

static var _lit: Dictionary = {}   # geteilte Material -> aufgehellte G28-Kopie

static func build() -> Node3D:
	var root := GunModels._instantiate(GunModels._template("g28", _parts), "G28")
	_brighten(root)
	return root

## Die geteilten Waffenmaterialien sind auf das kompakte G36 abgestimmt; auf dem langen G28 wirkten
## Eloxal/Polymer in der Daemmerung fast schwarz. Nur fuer dieses Modell: Grundfarbe etwas heller,
## Oberflaeche etwas matter (Override pro Instanz, andere Waffen bleiben unveraendert).
static func _brighten(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(i)
				var lm := _lit_mat(m)
				if lm != null:
					mi.set_surface_override_material(i, lm)
	for c in n.get_children():
		_brighten(c)

static func _lit_mat(m: Material) -> Material:
	if not (m is ShaderMaterial) or m == GunModels.mat("bore"):
		return null
	if _lit.has(m):
		return _lit[m]
	var sm := m as ShaderMaterial
	var base: Variant = sm.get_shader_parameter("base_color")
	if not (base is Color):
		_lit[m] = null
		return null
	var c: Color = base
	var d := sm.duplicate() as ShaderMaterial
	if c.get_luminance() < 0.2:
		d.set_shader_parameter("base_color", Color(c.r * 1.9 + 0.02, c.g * 1.9 + 0.02, c.b * 1.9 + 0.022, c.a))
		var r: Variant = sm.get_shader_parameter("roughness_base")
		if r is float:
			d.set_shader_parameter("roughness_base", minf(float(r) + 0.08, 0.9))
	_lit[m] = d
	return d

static func _parts(b: GunModels.Builder) -> void:
	_upper(b)
	_lower(b)
	_handguard(b)
	_barrel(b)
	_stock(b)
	_magazine(b)
	_scope(b)
	b.meta["muzzle"] = Vector3(0, BORE, -0.66)
	b.meta["eject"] = Vector3(0.016, 0.029, -0.066)
	b.meta["length"] = 1.065
	b.meta["optic_mount"] = Vector3(0, RAIL_TOP, -0.035)
	b.meta["scope_eye"] = Vector3(0, YS, Z_EYE)
	b.meta["scope_front"] = Vector3(0, YS, Z_OBJ)

# ------------------------------------------------------------------ Helfer

## Querschnitt (Punkte Vector2(x, y)) entlang Z von z0 bis z1 extrudiert.
static func _extz(b: GunModels.Builder, key: String, pts: Array, z0: float, z1: float, mat: String, bevel: float,
		r: float = 0.0, off: Vector3 = Vector3.ZERO, group: String = "Body", rsegs: int = 3) -> void:
	var hw: float = absf(z1 - z0) * 0.5
	# feine Eckenrundung (rsegs) haelt die Kantenabnutzung an langen Kanten dezent
	var mesh: ArrayMesh = GunModels._cached("%s|%.5f|%.5f|%.5f|%d" % [key, hw, bevel, r, rsegs], func() -> ArrayMesh:
		var prof: PackedVector2Array = GunModels.rounded(pts, r, true, rsegs) if r > 0.0 else PackedVector2Array(pts)
		return GunModels.extrude(prof, hw, bevel, 2))
	b.add(mesh, mat,
		Transform3D(Basis(Vector3.UP, PI * 0.5), off + Vector3(0, 0, (z0 + z1) * 0.5)), group)

## Gecachter Drehkoerper (Profil Vector2(radius, z)).
static func _lat(key: String, pts: Array, segs: int, round_r: float, closed: bool = false) -> ArrayMesh:
	return GunModels._cached(key, func() -> ArrayMesh:
		return GunModels.lathe(PackedVector2Array(pts), segs, round_r, closed))

## Ring (Rohrstueck) als geschlossenes Profil.
static func _ring(key: String, ri: float, ro: float, z0: float, z1: float, segs: int, round_r: float) -> ArrayMesh:
	return _lat(key, [Vector2(ri, z0), Vector2(ro, z0), Vector2(ro, z1), Vector2(ri, z1)], segs, round_r, true)

## Zahnrad-/Riffelprofil (Draufsicht) fuer Rendel- und Turmkappen.
static func _gear(n: int, ro: float, ri: float) -> Array:
	var pts: Array = []
	var da: float = TAU / float(n)
	for i in n:
		var a0: float = da * float(i)
		for f: Vector2 in [Vector2(0.0, ri), Vector2(0.18, ro), Vector2(0.62, ro), Vector2(0.8, ri)]:
			var a: float = a0 + da * f.x
			pts.append(Vector2(cos(a), sin(a)) * f.y)
	return pts

static func _arc(c: Vector2, r: float, a0: float, a1: float, n: int) -> Array:
	var out: Array = []
	for i in n + 1:
		var a: float = deg_to_rad(lerpf(a0, a1, float(i) / float(n)))
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out

## Beschriftung mit Flaechennormale und Schrift-Oben-Richtung.
static func _lbl(b: GunModels.Builder, text: String, pos: Vector3, normal: Vector3, up: Vector3, h: float, col: Color,
		group: String = "Body") -> void:
	var z: Vector3 = normal.normalized()
	var x: Vector3 = up.cross(z).normalized()
	var y: Vector3 = z.cross(x)
	b.label(text, pos, Basis(x, y, z).get_euler() * (180.0 / PI), h, col, group)

## Kurzer Picatinny-Abschnitt seitlich (side = +1 rechts, -1 links), Basis auf pos.
static func _side_rail(b: GunModels.Builder, pos: Vector3, n: int, side: float) -> void:
	var pitch: float = 0.01
	var length: float = float(n) * pitch
	var base: ArrayMesh = GunModels._cached("g28_srail_base_%d" % n, func() -> ArrayMesh:
		return GunModels.extrude(GunModels.rounded([Vector2(-0.0078, 0.0), Vector2(0.0078, 0.0), Vector2(0.0078, 0.0015),
			Vector2(0.0106, 0.0042), Vector2(0.0106, 0.0052), Vector2(-0.0106, 0.0052), Vector2(-0.0106, 0.0042),
			Vector2(-0.0078, 0.0015)], 0.0006, true, 1), length * 0.5 + 0.004, 0.001, 1))
	var tooth: ArrayMesh = GunModels._cached("g28_srail_tooth", func() -> ArrayMesh:
		return GunModels.extrude(GunModels.rounded([Vector2(-0.0106, 0.0052), Vector2(0.0106, 0.0052), Vector2(0.0106, 0.0072),
			Vector2(0.0088, 0.0095), Vector2(-0.0088, 0.0095), Vector2(-0.0106, 0.0072)], 0.0006, true, 1), 0.0026, 0.0007, 1))
	var rb: Basis = Basis(Vector3.BACK, -PI * 0.5 * side) * Basis(Vector3.UP, PI * 0.5)
	b.add(base, "anod", Transform3D(rb, pos))
	for i in n:
		var z: float = pos.z + (float(i) - float(n - 1) * 0.5) * pitch
		b.add(tooth, "anod", Transform3D(rb, Vector3(pos.x, pos.y, z)))

# ------------------------------------------------------------------ Oberteil

static func _upper(b: GunModels.Builder) -> void:
	var hw: float = 0.0115
	# Kern (oben stark gerundet), darauf die Seitenwangen (Stufe wie beim AR-Oberteil)
	b.add(GunModels.ext("g28_upper", [Vector2(-0.14, RAIL_Y), Vector2(0.072, RAIL_Y), Vector3(0.072, 0.024, 0.004),
		Vector3(0.066, 0.012, 0.004), Vector2(-0.14, 0.012)], hw, 0.0035, 0.002, 3), "anod")
	var pw: float = 0.00125
	var px: float = hw + pw
	b.add(GunModels.ext("g28_up_wl", [Vector2(-0.139, 0.0125), Vector2(0.069, 0.0125), Vector2(0.069, 0.042),
		Vector2(-0.139, 0.042)], pw, 0.0009, 0.0015, 2), "anod", GunModels.T(Vector3(-px, 0, 0)))
	# Rechte Wange mit Auswurffenster (echte Oeffnung: vier Teile um das Fenster)
	var pz0: float = -0.096
	var pz1: float = -0.036
	var py0: float = 0.0205
	var py1: float = 0.0375
	b.add(GunModels.ext("g28_up_wr_f", [Vector2(-0.139, 0.0125), Vector2(pz0, 0.0125), Vector2(pz0, 0.042),
		Vector2(-0.139, 0.042)], pw, 0.0009, 0.0012, 2), "anod", GunModels.T(Vector3(px, 0, 0)))
	b.add(GunModels.ext("g28_up_wr_r", [Vector2(pz1, 0.0125), Vector2(0.069, 0.0125), Vector2(0.069, 0.042),
		Vector2(pz1, 0.042)], pw, 0.0009, 0.0012, 2), "anod", GunModels.T(Vector3(px, 0, 0)))
	b.add(GunModels.ext("g28_up_wr_t", [Vector2(pz0, py1), Vector2(pz1, py1), Vector2(pz1, 0.042), Vector2(pz0, 0.042)],
		pw, 0.0009, 0.0008, 2), "anod", GunModels.T(Vector3(px, 0, 0)))
	b.add(GunModels.ext("g28_up_wr_b", [Vector2(pz0, 0.0125), Vector2(pz1, 0.0125), Vector2(pz1, py0), Vector2(pz0, py0)],
		pw, 0.0009, 0.0008, 2), "anod", GunModels.T(Vector3(px, 0, 0)))
	# Im Fenster: Verschlusstraeger (parkerisiert), Verschlusskopf (blank) mit Auszieher, Steuerbolzen
	b.add(GunModels.rbox(Vector3(0.0018, 0.0158, 0.046), 0.0006), "park", GunModels.T(Vector3(hw + 0.0003, 0.029, -0.059)))
	b.add(GunModels.rbox(Vector3(0.0016, 0.012, 0.014), 0.0012), "steel", GunModels.T(Vector3(hw + 0.0003, 0.029, -0.089)))
	b.add(GunModels.rbox(Vector3(0.0012, 0.0035, 0.009), 0.0005), "park", GunModels.T(Vector3(hw + 0.0012, 0.033, -0.0885)))
	b.add(GunModels.rbox(Vector3(0.0012, 0.0015, 0.04), 0.0004), "bore", GunModels.T(Vector3(hw + 0.0012, 0.0218, -0.06)))
	b.add(GunModels.cylz(0.0026, 0.0, 0.0016, 14, 0.0004), "steel", GunModels.T(Vector3(hw + 0.0009, 0.033, -0.05), Vector3(0, 90, 0)))
	# Staubschutzdeckel offen (nach unten geklappt) mit Scharnierstift
	b.add(GunModels.cylz(0.0011, pz0 - 0.001, pz1 + 0.001, 10, 0.0003), "steel", GunModels.T(Vector3(0.0146, 0.0195, 0)))
	var ang: float = deg_to_rad(-165.0)
	var hinge := Vector3(0.0146, 0.0195, 0.0)
	var dxf := Transform3D(Basis(Vector3.BACK, ang), hinge + Vector3(0, 0, -0.066))
	b.add(GunModels.rbox(Vector3(0.0012, 0.0175, 0.062), 0.0005), "park", dxf * GunModels.T(Vector3(0, 0.0095, 0)))
	b.add(GunModels.rbox(Vector3(0.0022, 0.003, 0.006), 0.0008), "park", dxf * GunModels.T(Vector3(-0.0008, 0.0172, 0.024)))
	for zz: float in [-0.024, 0.0, 0.024]:
		b.add(GunModels.cylz(0.0018, -0.0035, 0.0035, 10, 0.0004), "park", dxf * GunModels.T(Vector3(0, 0, zz)))
	# Vorderer Schliesshilfe-Knopf (forward assist) rechts hinten
	b.add(_lat("g28_fa_house", [Vector2(0.0, -0.004), Vector2(0.0035, -0.002), Vector2(0.0068, 0.012), Vector2(0.0072, 0.03),
		Vector2(0.0072, 0.058), Vector2(0.0, 0.058)], 20, 0.0015), "anod", GunModels.T(Vector3(0.0128, 0.033, 0.0)))
	b.add(_lat("g28_fa_btn", [Vector2(0.0, 0.056), Vector2(0.0063, 0.056), Vector2(0.0063, 0.0672), Vector2(0.0056, 0.069),
		Vector2(0.0048, 0.069), Vector2(0.0046, 0.0682), Vector2(0.0043, 0.069), Vector2(0.0033, 0.069), Vector2(0.0031, 0.0682),
		Vector2(0.0028, 0.069), Vector2(0.0, 0.069)], 20, 0.0003), "park", GunModels.T(Vector3(0.0128, 0.033, 0.0)))
	# Huelsenabweiser hinter dem Fenster
	b.add(GunModels.ext("g28_defl", [Vector2(-0.034, 0.024), Vector2(-0.031, 0.044), Vector3(-0.014, 0.045, 0.004),
		Vector3(-0.004, 0.032, 0.004), Vector2(-0.014, 0.024)], 0.0028, 0.0016, 0.003, 2), "anod",
		GunModels.T(Vector3(0.0158, 0, 0)))
	# Durchgehende Schiene oben (Gehaeuse)
	GunModels._rail(b, Vector3(0, RAIL_Y, -0.035), 20, false)
	# Spannhebel (T-Griff hinten, beidseitige Klinken)
	var g: String = "Charging_Handle"
	b.add(GunModels.rbox(Vector3(0.009, 0.0065, 0.03), 0.0015), "anod", GunModels.T(Vector3(0, 0.0462, 0.064)), g)
	b.add(GunModels.rbox(Vector3(0.028, 0.0085, 0.0095), 0.0028), "anod", GunModels.T(Vector3(0, 0.0465, 0.081)), g)
	for sx: float in [1.0, -1.0]:
		b.add(GunModels.rbox(Vector3(0.013, 0.0085, 0.0115), 0.0032), "anod",
			GunModels.T(Vector3(sx * 0.0178, 0.0465, 0.0828), Vector3(0, sx * 18.0, 0)), g)
		for k in 3:
			b.add(GunModels.rbox(Vector3(0.0085, 0.0012, 0.0016), 0.0004), "poly_dark",
				GunModels.T(Vector3(sx * (0.0165 + float(k) * 0.0025), 0.0511, 0.0828 + sx * float(k) * 0.0007),
				Vector3(0, sx * 18.0 + 90.0, 0)), g)
	b.label("MR7", Vector3(px + pw + 0.0002, 0.027, 0.04), Vector3(0, 90, 0), 0.004, GREY)

# ------------------------------------------------------------------ Unterteil

static func _lower(b: GunModels.Builder) -> void:
	var hw: float = 0.0142
	b.add(GunModels.ext("g28_lower", [Vector2(-0.124, 0.0115), Vector2(0.071, 0.0115), Vector3(0.071, 0.042, 0.003),
		Vector3(0.089, 0.042, 0.004), Vector3(0.093, 0.026, 0.006), Vector3(0.092, 0.004, 0.006), Vector3(0.083, -0.017, 0.006),
		Vector2(0.05, -0.02), Vector2(-0.024, -0.02), Vector2(-0.03, -0.004), Vector2(-0.124, -0.004)], hw, 0.003, 0.003, 3), "anod")
	# Magazinschacht mit ausgestelltem Trichter und dunkler Oeffnung
	b.add(GunModels.ext("g28_well", [Vector2(-0.124, 0.0112), Vector3(-0.133, 0.0112, 0.003), Vector3(-0.134, -0.045, 0.004),
		Vector2(-0.131, -0.052), Vector2(-0.027, -0.052), Vector3(-0.026, -0.03, 0.004), Vector2(-0.028, 0.0112)],
		0.0165, 0.0035, 0.003, 3), "anod")
	b.add(GunModels.ext("g28_well_lip", [Vector2(-0.1365, -0.046), Vector2(-0.0245, -0.046), Vector2(-0.025, -0.0565),
		Vector2(-0.136, -0.0565)], 0.0177, 0.003, 0.003, 2), "anod")
	b.add(GunModels.rbox(Vector3(0.026, 0.002, 0.083), 0.0008), "poly_dark", GunModels.T(Vector3(0, -0.0569, -0.0795)))
	# Abzugsbuegel, Abzug, Schlitz
	b.add(GunModels.ext("g28_guard", Array(GunModels.stroke([Vector2(-0.025, -0.012), Vector2(-0.024, -0.038), Vector2(-0.014, -0.048),
		Vector2(0.02, -0.0505), Vector2(0.04, -0.044), Vector2(0.046, -0.024)], 0.0065)), 0.0065, 0.0025, 0.003), "anod")
	b.add(GunModels.rbox(Vector3(0.0062, 0.002, 0.03), 0.0006), "bore", GunModels.T(Vector3(0, -0.0202, 0.012)))
	b.add(GunModels.ext("g28_trig", Array(GunModels.stroke([Vector2(0.004, -0.018), Vector2(0.006, -0.03), Vector2(0.011, -0.039),
		Vector2(0.018, -0.0435)], 0.005)), 0.0028, 0.0011, 0.0015), "steel")
	# Ergonomischer Pistolengriff mit Fingerrillen und Handballenauflage
	b.add(GunModels.ext("g28_grip", [Vector2(0.04, -0.015), Vector2(0.094, -0.015), Vector3(0.1, -0.03, 0.008),
		Vector3(0.102, -0.055, 0.01), Vector3(0.11, -0.095, 0.008), Vector3(0.113, -0.11, 0.005), Vector3(0.107, -0.119, 0.004),
		Vector3(0.076, -0.12, 0.004), Vector3(0.07, -0.112, 0.004), Vector3(0.063, -0.098, 0.006), Vector3(0.054, -0.085, 0.004),
		Vector3(0.056, -0.073, 0.006), Vector3(0.048, -0.06, 0.004), Vector3(0.05, -0.046, 0.006), Vector2(0.044, -0.03)],
		0.0165, 0.0062, 0.004, 3), "poly_grip")
	# Griffflaechen mit gummiertem Einsatz (leicht erhaben) und Daumenauflage
	b.add(GunModels.ext("g28_grip_pan", [Vector2(0.057, -0.029), Vector2(0.09, -0.029), Vector3(0.094, -0.058, 0.006),
		Vector3(0.101, -0.094, 0.005), Vector3(0.098, -0.104, 0.004), Vector3(0.081, -0.105, 0.004), Vector3(0.073, -0.094, 0.006),
		Vector3(0.063, -0.06, 0.006), Vector2(0.058, -0.045)], 0.0167, 0.0012, 0.003, 2), "rubber")
	b.add(GunModels.ext("g28_grip_thumb", Array(GunModels.stroke([Vector2(0.06, -0.022), Vector2(0.075, -0.0235),
		Vector2(0.092, -0.022)], 0.004)), 0.0172, 0.0016, 0.0015, 2), "poly_grip")
	b.add(GunModels.ext("g28_grip_cap", [Vector2(0.073, -0.1135), Vector2(0.1125, -0.1105), Vector2(0.11, -0.1225),
		Vector2(0.076, -0.1245)], 0.0172, 0.004, 0.003), "poly")
	# Feuerwahlhebel beidseitig (S / E), Hebel auf "E"
	for sx: float in [1.0, -1.0]:
		b.add(GunModels.cylz(0.0062, -0.0012, 0.0012, 18, 0.0005), "park",
			GunModels.T(Vector3(sx * (hw + 0.0012), -0.004, 0.052), Vector3(0, 90, 0)))
		b.add(GunModels.ext("g28_sel", Array(GunModels.stroke([Vector2(0.0, 0.0), Vector2(0.008, 0.008), Vector2(0.0115, 0.0102)],
			0.005)), 0.0012, 0.0005, 0.0018), "park", GunModels.T(Vector3(sx * (hw + 0.0026), -0.004, 0.052)))
		var nrm := Vector3(sx, 0, 0)
		_lbl(b, "S", Vector3(sx * (hw + 0.0003), 0.004, 0.039), nrm, Vector3.UP, 0.0042, WHITE)
		_lbl(b, "E", Vector3(sx * (hw + 0.0003), 0.0035, 0.0705), nrm, Vector3.UP, 0.0042, Color(0.8, 0.2, 0.15))
	# Magazinhalter rechts mit Schutzrippe, Verschlussfang links
	b.add(GunModels.cylz(0.0042, 0.0, 0.0028, 16, 0.0008), "park", GunModels.T(Vector3(hw, -0.006, -0.019), Vector3(0, 90, 0)))
	b.add(GunModels.ext("g28_fence", Array(GunModels.stroke([Vector2(-0.027, -0.012), Vector2(-0.019, -0.0145),
		Vector2(-0.011, -0.012)], 0.0035)), 0.0016, 0.0008, 0.0015), "anod", GunModels.T(Vector3(hw + 0.0006, 0, 0)))
	b.add(GunModels.ext("g28_bcatch", [Vector2(-0.024, -0.001), Vector2(-0.013, -0.001), Vector2(-0.012, 0.0085),
		Vector2(-0.022, 0.0105)], 0.0014, 0.0006, 0.002), "park", GunModels.T(Vector3(-(hw + 0.0013), 0, 0)))
	for k in 4:
		b.add(GunModels.rbox(Vector3(0.0008, 0.0085, 0.0008), 0.0003), "poly_dark",
			GunModels.T(Vector3(-(hw + 0.0027), 0.0048, -0.021 + float(k) * 0.0022)))
	# Bolzen (Enden blank)
	b.add(GunModels.cylz(0.0032, -0.0174, 0.0174, 14, 0.0006), "steel", GunModels.T(Vector3(0, 0.005, -0.129), Vector3(0, 90, 0)))
	b.add(GunModels.cylz(0.0032, -hw - 0.0009, hw + 0.0009, 14, 0.0006), "steel", GunModels.T(Vector3(0, 0.004, 0.084), Vector3(0, 90, 0)))
	for pz: Vector2 in [Vector2(0.004, -0.009), Vector2(0.026, -0.007)]:
		b.add(GunModels.cylz(0.0025, -hw - 0.0008, hw + 0.0008, 12, 0.0005), "steel",
			GunModels.T(Vector3(0, pz.y, pz.x), Vector3(0, 90, 0)))
	# Beschriftung
	_lbl(b, "MR7   Kal. 7,62 x 51", Vector3(-0.0168, -0.024, -0.08), Vector3.LEFT, Vector3.UP, 0.0036, GREY)
	_lbl(b, "Nr. 28-004117", Vector3(0.0168, -0.03, -0.08), Vector3.RIGHT, Vector3.UP, 0.003, GREY)
	_lbl(b, "MR7", Vector3(0.0168, -0.018, -0.08), Vector3.RIGHT, Vector3.UP, 0.0045, GREY)

# ------------------------------------------------------------------ Vorderschaft

## Linie des Querschnitts fuer Teilstueck piece (0 = Bogen oben, 1 = rechts unten, 2 = links unten), off = Einzug.
static func _hg_line(piece: int, off: float) -> Array:
	var a: float = HG_A - off
	var rr: float = HG_RC - off
	var cx: float = HG_A - HG_RC
	var cyt: float = HG_YC + HG_C - HG_RC
	var cyb: float = HG_YC - HG_C + HG_RC
	var bot: float = HG_YC - HG_C + off
	var pts: Array = []
	match piece:
		0:
			pts.append(Vector2(a, HG_YC + HG_S))
			pts.append_array(_arc(Vector2(cx, cyt), rr, 0.0, 90.0, 6))
			pts.append_array(_arc(Vector2(-cx, cyt), rr, 90.0, 180.0, 6))
			pts.append(Vector2(-a, HG_YC + HG_S))
		1:
			pts.append(Vector2(a, HG_YC - HG_S))
			pts.append_array(_arc(Vector2(cx, cyb), rr, 0.0, -90.0, 6))
			pts.append(Vector2(HG_S, bot))
		_:
			pts.append(Vector2(-HG_S, bot))
			pts.append_array(_arc(Vector2(-cx, cyb), rr, 270.0, 180.0, 6))
			pts.append(Vector2(-a, HG_YC - HG_S))
	return pts

static func _hg_piece(piece: int) -> Array:
	var outer: Array = _hg_line(piece, 0.0)
	var inner: Array = _hg_line(piece, HG_T)
	inner.reverse()
	outer.append_array(inner)
	return outer

static func _handguard(b: GunModels.Builder) -> void:
	# Durchlaufende Holme (Bogen oben + zwei untere Ecken) ...
	for p in 3:
		_extz(b, "g28_hg_p%d" % p, _hg_piece(p), HG_Z0, HG_Z1, "anod", 0.0012, 0.0009, Vector3.ZERO, "Body", 6)
	# ... und Stege zwischen den M-LOK-Schlitzen (rechts, links, unten) -> echte Oeffnungen
	var e: float = 0.001
	var xo: float = HG_A - 0.0004
	var xi: float = HG_A - HG_T + 0.0003
	var web_r: Array = [Vector2(xo, HG_YC - HG_S - e), Vector2(xo, HG_YC + HG_S + e), Vector2(xi, HG_YC + HG_S + e), Vector2(xi, HG_YC - HG_S - e)]
	var web_l: Array = []
	for v: Vector2 in web_r:
		web_l.append(Vector2(-v.x, v.y))
	var yb: float = HG_YC - HG_C
	var web_b: Array = [Vector2(-HG_S - e, yb + 0.0004), Vector2(HG_S + e, yb + 0.0004), Vector2(HG_S + e, yb + HG_T - 0.0003),
		Vector2(-HG_S - e, yb + HG_T - 0.0003)]
	var rows: Array = [["r", web_r, 7], ["l", web_l, 7], ["b", web_b, 6]]
	for row: Array in rows:
		var nm: String = row[0]
		var prof: Array = row[1]
		var cnt: int = row[2]
		var z: float = HG_Z0
		for k in cnt + 1:
			var zs: float = -0.165 - float(k) * 0.042 if k < cnt else HG_Z1
			_extz(b, "g28_hgw_" + nm, prof, z, zs, "anod", 0.001, 0.0006, Vector3.ZERO, "Body", 6)
			z = zs - 0.03
	# Innenrohr dunkel (Hitzeschutz) nur hinten, Laufmutter
	b.add(_lat("g28_bnut", [Vector2(0.0, -0.136), Vector2(0.0198, -0.136), Vector2(0.0198, -0.153), Vector2(0.0, -0.153)], 24, 0.001),
		"park", GunModels.T(Vector3(0, BORE - 0.003, 0)))
	# Klemmschrauben rechts, QD-Riemenbuchse links
	for yy: float in [0.018, 0.034]:
		b.add(GunModels.cylz(0.0028, 0.0, 0.0014, 6, 0.0004), "steel", GunModels.T(Vector3(HG_A - 0.0002, yy, -0.149), Vector3(0, 90, 30)))
		b.add(GunModels.cylz(0.0012, 0.0, 0.0016, 6, 0.0), "bore", GunModels.T(Vector3(HG_A - 0.0001, yy, -0.149), Vector3(0, 90, 0)))
	var qd: ArrayMesh = _lat("g28_qd", [Vector2(0.003, 0.0), Vector2(0.0068, 0.0), Vector2(0.0068, 0.0028), Vector2(0.0062, 0.0036),
		Vector2(0.003, 0.0036)], 20, 0.0004, true)
	b.add(qd, "steel", GunModels.T(Vector3(-HG_A + 0.0005, HG_YC, -0.15), Vector3(0, -90, 0)))
	b.add(GunModels.cylz(0.0031, -0.002, 0.0028, 12, 0.0), "bore", GunModels.T(Vector3(-HG_A + 0.0005, HG_YC, -0.15), Vector3(0, -90, 0)))
	# Schiene oben (durchgehend), kurze Schienen vorn seitlich und unten
	GunModels._rail(b, Vector3(0, RAIL_Y, -0.316), 34, false)
	GunModels._rail(b, Vector3(0, yb, -0.47), 5, true)
	_side_rail(b, Vector3(HG_A, HG_YC, -0.47), 3, 1.0)
	_side_rail(b, Vector3(-HG_A, HG_YC, -0.47), 3, -1.0)
	# Riemenoese an der unteren Schiene
	var loop: ArrayMesh = _lat("g28_loop", [Vector2(0.006, 0.0), Vector2(0.0075, 0.0015), Vector2(0.009, 0.0), Vector2(0.0075, -0.0015),
		Vector2(0.006, 0.0)], 16, 0.0, true)
	b.add(GunModels.rbox(Vector3(0.022, 0.006, 0.014), 0.002), "anod", GunModels.T(Vector3(0, yb - 0.0125, -0.47)))
	b.add(loop, "park", GunModels.T(Vector3(0, yb - 0.022, -0.47), Vector3(0, 90, 0)))

# ------------------------------------------------------------------ Lauf und Muendungsbremse

static func _barrel(b: GunModels.Builder) -> void:
	var bx := GunModels.T(Vector3(0, BORE, 0))
	b.add(_lat("g28_barrel", [Vector2(0.0, -0.14), Vector2(0.0108, -0.14), Vector2(0.0108, -0.33), Vector2(0.0098, -0.36),
		Vector2(0.0098, -0.594), Vector2(0.0, -0.594)], 28, 0.001), "park", bx)
	# Gasblock + Gasrohr (durch die Schlitze sichtbar)
	b.add(GunModels.rbox(Vector3(0.026, 0.026, 0.02), 0.004), "park", GunModels.T(Vector3(0, BORE + 0.002, -0.405)))
	b.add(GunModels.cylz(0.0025, -0.153, -0.396, 10), "steel", GunModels.T(Vector3(0, BORE + 0.0142, 0)))
	# Muendungsbremse: Bund, drei seitliche Kammern (Ringe + Stege oben/unten), Stirnteil mit Bohrung
	b.add(_lat("g28_mb_col", [Vector2(0.0, -0.591), Vector2(0.0112, -0.591), Vector2(0.0128, -0.595), Vector2(0.0132, -0.599),
		Vector2(0.0132, -0.6125), Vector2(0.0, -0.6125)], 28, 0.0008), "park", bx)
	for rz: Vector2 in [Vector2(-0.6195, -0.626), Vector2(-0.6335, -0.64)]:
		b.add(_ring("g28_mb_r%d" % int(-rz.x * 10000.0), 0.0056, 0.0132, rz.x, rz.y, 28, 0.0008), "park", bx)
	b.add(_lat("g28_mb_front", [Vector2(0.0045, -0.6475), Vector2(0.0132, -0.6475), Vector2(0.0132, -0.6555), Vector2(0.0116, -0.66),
		Vector2(0.0045, -0.66)], 28, 0.0006, true), "park", bx)
	for a0: float in [52.0, 232.0]:
		var pts: Array = _arc(Vector2.ZERO, 0.0131, a0, a0 + 76.0, 6)
		var inner: Array = _arc(Vector2.ZERO, 0.0057, a0, a0 + 76.0, 4)
		inner.reverse()
		pts.append_array(inner)
		_extz(b, "g28_mb_bridge%d" % int(a0), pts, -0.6105, -0.6495, "park", 0.0008, 0.0, Vector3(0, BORE, 0))
	b.add(GunModels.cylz(0.0056, -0.611, -0.6595, 16, 0.0), "bore", bx)
	# Kompensator-Bohrungen oben
	for zz: float in [-0.6165, -0.63]:
		b.add(GunModels.cylz(0.0018, 0.0, 0.001, 10, 0.0), "bore", GunModels.T(Vector3(0, BORE + 0.0127, zz), Vector3(-90, 0, 0)))

# ------------------------------------------------------------------ Schaft

static func _stock(b: GunModels.Builder) -> void:
	var ty: float = 0.028
	# Puffer-Rohr mit Endplatte und Ringmutter (Kerben)
	b.add(GunModels.cylz(0.0145, 0.088, 0.33, 28), "anod", GunModels.T(Vector3(0, ty, 0)))
	b.add(GunModels.rbox(Vector3(0.03, 0.034, 0.003), 0.0012), "park", GunModels.T(Vector3(0, 0.026, 0.0935)))
	b.add(GunModels.cylz(0.0172, 0.095, 0.104, 28, 0.001), "park", GunModels.T(Vector3(0, ty, 0)))
	for k in 6:
		var a: float = TAU * float(k) / 6.0 + PI / 6.0
		b.add(GunModels.rbox(Vector3(0.0035, 0.003, 0.0045), 0.0003), "bore",
			Transform3D(Basis(Vector3.BACK, a - PI * 0.5), Vector3(cos(a) * 0.0164, ty + sin(a) * 0.0164, 0.1025)))
	# Positionsmarken auf dem Rohr
	for k in 5:
		b.add(GunModels.rbox(Vector3(0.004, 0.0008, 0.0008), 0.0002), "steel",
			GunModels.T(Vector3(-0.0102, ty + 0.0102, 0.125 + float(k) * 0.0125), Vector3(0, 0, 45)))
	# Schaftkoerper: Kragen, Oberteil um das Rohr, Kolbenplatte, Strebe (Fenster dazwischen)
	b.add(_ring("g28_stk_collar", 0.0144, 0.0188, 0.19, 0.218, 28, 0.002), "poly", GunModels.T(Vector3(0, ty, 0)))
	b.add(GunModels.ext("g28_stk_top", Array(GunModels.stroke([Vector2(0.196, 0.032), Vector2(0.3, 0.032), Vector2(0.385, 0.033)], 0.04)),
		0.0182, 0.006, 0.006, 3), "poly")
	b.add(GunModels.ext("g28_stk_butt", [Vector2(0.362, 0.05), Vector3(0.39, 0.0535, 0.006), Vector2(0.393, 0.03),
		Vector2(0.393, -0.075), Vector3(0.388, -0.088, 0.008), Vector3(0.358, -0.086, 0.008), Vector2(0.368, -0.04),
		Vector2(0.366, 0.0)], 0.0195, 0.006, 0.008, 3), "poly")
	b.add(GunModels.ext("g28_stk_strut", Array(GunModels.stroke([Vector2(0.212, 0.016), Vector2(0.3, -0.032), Vector2(0.374, -0.075)],
		0.019)), 0.0172, 0.0055, 0.006, 3), "poly")
	# Fensterkanten dunkel (Innenseite), Verstellhebel unten
	b.add(GunModels.ext("g28_stk_lever", Array(GunModels.stroke([Vector2(0.206, 0.0115), Vector2(0.232, 0.0075), Vector2(0.25, 0.009)],
		0.0055)), 0.0062, 0.002, 0.002), "poly_dark")
	# Gummi-Schaftkappe mit Rillen
	b.add(GunModels.ext("g28_pad", [Vector2(0.392, 0.052), Vector3(0.402, 0.05, 0.004), Vector3(0.405, 0.0, 0.01),
		Vector3(0.403, -0.08, 0.005), Vector2(0.392, -0.0865)], 0.0205, 0.005, 0.005, 3), "rubber")
	for k in 10:
		var y: float = 0.042 - float(k) * 0.0125
		var zb: float = 0.4022 + 0.0025 * clampf(1.0 - absf(y) / 0.06, 0.0, 1.0)
		b.add(GunModels.rbox(Vector3(0.034, 0.0018, 0.003), 0.0007), "poly_dark", GunModels.T(Vector3(0, y, zb)))
	# Wangenauflage auf zwei Stahlstiften, Klemmknopf links
	b.add(GunModels.ext("g28_cheek", [Vector2(0.238, 0.0545), Vector3(0.25, 0.067, 0.008), Vector3(0.37, 0.069, 0.008),
		Vector2(0.377, 0.0545)], 0.0172, 0.006, 0.006, 3), "poly")
	for zz: float in [0.27, 0.345]:
		b.add(GunModels.cylz(0.0034, 0.0, 0.006, 14, 0.0006), "steel", GunModels.T(Vector3(0, 0.0505, zz), Vector3(-90, 0, 0)))
	b.add(GunModels.ext("g28_knob", _gear(14, 0.0072, 0.0064), 0.003, 0.0008, 0.0006), "poly_dark", GunModels.T(Vector3(-0.0215, 0.033, 0.308)))
	b.add(GunModels.cylz(0.0045, 0.0, 0.0018, 14, 0.0005), "park", GunModels.T(Vector3(-0.0245, 0.033, 0.308), Vector3(0, -90, 0)))
	# QD-Riemenbuchse am Kolben
	var qd: ArrayMesh = _lat("g28_qd", [Vector2(0.003, 0.0), Vector2(0.0068, 0.0), Vector2(0.0068, 0.0028), Vector2(0.0062, 0.0036),
		Vector2(0.003, 0.0036)], 20, 0.0004, true)
	b.add(qd, "steel", GunModels.T(Vector3(-0.0192, -0.035, 0.38), Vector3(0, -90, 0)))
	b.add(GunModels.cylz(0.0031, -0.002, 0.0028, 12, 0.0), "bore", GunModels.T(Vector3(-0.0192, -0.035, 0.38), Vector3(0, -90, 0)))

# ------------------------------------------------------------------ Magazin

static func _mag_z(d: float) -> float:
	return -0.079 - 0.03 * d - 0.3 * d * d

static func _magazine(b: GunModels.Builder) -> void:
	var g: String = "Magazine"
	var steps: int = 10
	var dl: float = 0.148
	var back: Array = []
	var front: Array = []
	for i in steps + 1:
		var d: float = dl * float(i) / float(steps)
		back.append(Vector2(_mag_z(d) + 0.0385, 0.006 - d))
		front.append(Vector2(_mag_z(d) - 0.0385, 0.006 - d))
	var shell: Array = back.duplicate()
	var fr: Array = front.duplicate()
	fr.reverse()
	shell.append_array(fr)
	b.add(GunModels._cached("g28_mag_shell", func() -> ArrayMesh:
		return GunModels.extrude(GunModels.rounded(shell, 0.003, true, 2), 0.0118, 0.0022, 2)), "park", Transform3D.IDENTITY, g)
	# Gepraegte Seitenflaeche (leicht erhaben) und Laengssicken vorn/hinten
	var pb: Array = []
	var pf: Array = []
	for i in 7:
		var d2: float = 0.072 + 0.064 * float(i) / 6.0
		pb.append(Vector2(_mag_z(d2) + 0.029, 0.006 - d2))
		pf.append(Vector2(_mag_z(d2) - 0.029, 0.006 - d2))
	pf.reverse()
	var panel: Array = pb.duplicate()
	panel.append_array(pf)
	b.add(GunModels._cached("g28_mag_panel", func() -> ArrayMesh:
		return GunModels.extrude(GunModels.rounded(panel, 0.006, true, 2), 0.0124, 0.0005, 1)), "park", Transform3D.IDENTITY, g)
	var rib: Array = []
	for i in 7:
		var d3: float = 0.068 + 0.072 * float(i) / 6.0
		rib.append(Vector2(_mag_z(d3) + 0.0335, 0.006 - d3))
	b.add(GunModels._cached("g28_mag_rib", func() -> ArrayMesh:
		return GunModels.extrude(GunModels.stroke(rib, 0.0022), 0.0123, 0.0006, 1)), "park", Transform3D.IDENTITY, g)
	# Bodenplatte (Polymer) senkrecht zur Magazinachse
	var zb: float = _mag_z(dl)
	var tilt: float = rad_to_deg(atan(0.03 + 0.6 * dl))
	var fxf := GunModels.T(Vector3(0, 0.006 - dl - 0.0025, zb), Vector3(tilt, 0, 0))
	b.add(GunModels.rbox(Vector3(0.0268, 0.0075, 0.0835), 0.0026), "poly", fxf, g)
	b.add(GunModels.rbox(Vector3(0.0275, 0.0035, 0.012), 0.0012), "poly_dark", fxf * GunModels.T(Vector3(0, -0.0022, -0.036)), g)
	b.add(GunModels.rbox(Vector3(0.012, 0.0012, 0.03), 0.0005), "poly_dark", fxf * GunModels.T(Vector3(0, -0.0038, 0.008)), g)
	# Zufuehrlippen + oberste Patronen (Messinghuelse, Kupfermantel-Geschoss)
	b.add(GunModels.rbox(Vector3(0.0242, 0.0035, 0.05), 0.0012), "steel", GunModels.T(Vector3(0, 0.0055, _mag_z(0.0) + 0.012)), g)
	var case_m: ArrayMesh = _lat("g28_case", [Vector2(0.0, 0.0255), Vector2(0.0059, 0.0255), Vector2(0.0059, 0.0245), Vector2(0.005, 0.024),
		Vector2(0.005, 0.0232), Vector2(0.006, 0.0225), Vector2(0.0058, -0.0125), Vector2(0.0045, -0.0175), Vector2(0.0041, -0.0195),
		Vector2(0.0041, -0.0255), Vector2(0.0, -0.0255)], 12, 0.0004)
	var bullet_m: ArrayMesh = _lat("g28_bullet", [Vector2(0.0, -0.024), Vector2(0.0039, -0.024), Vector2(0.0039, -0.031),
		Vector2(0.0033, -0.036), Vector2(0.0018, -0.041), Vector2(0.0, -0.0435)], 12, 0.0)
	for i in 3:
		var yy: float = 0.003 - float(i) * 0.0085
		var xo: float = 0.0042 if i % 2 == 0 else -0.0042
		var zz: float = _mag_z(-yy + 0.006) + 0.0115
		var rxf := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(3.0 - float(i) * 1.5)), Vector3(xo, yy, zz))
		b.add(case_m, "brass", rxf, g)
		b.add(bullet_m, "copper", rxf, g)
	_lbl(b, "7,62 x 51   20", Vector3(-0.0128, -0.1, _mag_z(0.106)), Vector3.LEFT, Vector3.UP, 0.0032, GREY, g)

# ------------------------------------------------------------------ Zielfernrohr 3-20x56 mit Montage

static func _scope(b: GunModels.Builder) -> void:
	var ax := GunModels.T(Vector3(0, YS, 0))
	# --- Montage: Klemmfuss auf der Schiene, Ausleger mit zwei Stuetzen, Querbolzen + Muttern
	b.add(GunModels.ext("g28_mnt_base", [Vector2(-0.08, 0.051), Vector2(0.046, 0.051), Vector3(0.048, 0.067, 0.003),
		Vector3(-0.082, 0.067, 0.003)], 0.0137, 0.0025, 0.002, 2), "anod")
	b.add(GunModels.ext("g28_mnt_web", [Vector2(0.044, 0.064), Vector2(0.038, YS - 0.012), Vector2(0.012, YS - 0.012),
		Vector3(0.003, 0.0745, 0.004), Vector3(-0.092, 0.0745, 0.004), Vector2(-0.103, YS - 0.012), Vector2(-0.127, YS - 0.012),
		Vector3(-0.129, 0.071, 0.005), Vector3(-0.085, 0.064, 0.008)], 0.0092, 0.0025, 0.004, 2), "anod")
	for bz: float in [-0.055, 0.025]:
		b.add(GunModels.rbox(Vector3(0.002, 0.0145, 0.022), 0.0008), "anod", GunModels.T(Vector3(0.0146, 0.058, bz)))
		b.add(GunModels.cylz(0.0047, 0.0, 0.0024, 20, 0.0007), "park", GunModels.T(Vector3(-0.0136, 0.0575, bz), Vector3(0, -90, 0)))
		b.add(GunModels.cylz(0.0019, 0.0, 0.0012, 6, 0.0), "bore", GunModels.T(Vector3(-0.0157, 0.0575, bz), Vector3(0, -90, 0)))
		b.add(GunModels.cylz(0.0058, 0.0, 0.0042, 6, 0.0006), "park", GunModels.T(Vector3(0.0155, 0.0575, bz), Vector3(0, 90, 30)))
		b.add(GunModels.cylz(0.0026, 0.0, 0.0058, 12, 0.0005), "steel", GunModels.T(Vector3(0.0155, 0.0575, bz), Vector3(0, 90, 0)))
	_lbl(b, "MR-M  30 mm", Vector3(-0.0139, 0.0595, -0.018), Vector3.LEFT, Vector3.UP, 0.0026, GREY)
	# --- Ringe (geteilte Deckel mit Ohren und je zwei Schrauben pro Seite)
	for rz: float in [0.025, -0.115]:
		b.add(_ring("g28_sc_ring", 0.0149, 0.0205, -0.0085, 0.0085, 36, 0.0015), "anod", GunModels.T(Vector3(0, YS, rz)))
		for sx: float in [1.0, -1.0]:
			b.add(GunModels.rbox(Vector3(0.0075, 0.0085, 0.0165), 0.0022), "anod", GunModels.T(Vector3(sx * 0.0205, YS + 0.0005, rz)))
			b.add(GunModels.rbox(Vector3(0.0085, 0.0007, 0.0172), 0.0002), "bore", GunModels.T(Vector3(sx * 0.0203, YS - 0.0008, rz)))
			for dz: float in [-0.0042, 0.0042]:
				b.add(GunModels.cylz(0.0022, 0.0, 0.0014, 14, 0.0004), "park",
					GunModels.T(Vector3(sx * 0.0215, YS + 0.0047, rz + dz), Vector3(-90, 0, 0)))
				b.add(GunModels.cylz(0.001, 0.0, 0.0006, 6, 0.0), "bore",
					GunModels.T(Vector3(sx * 0.0215, YS + 0.0057, rz + dz), Vector3(-90, 0, 0)))
	# --- Mittelrohr 30 mm
	b.add(GunModels.cylz(0.015, -0.142, 0.052, 40, 0.0008), "anod", ax)
	# --- Objektivglocke (hohl), Sonnenblende, Glas mit Tiefe
	b.add(_lat("g28_sc_obj", [Vector2(0.0148, -0.137), Vector2(0.0153, -0.14), Vector2(0.0175, -0.152), Vector2(0.0248, -0.176),
		Vector2(0.0276, -0.19), Vector2(0.028, -0.196), Vector2(0.028, -0.2275), Vector2(0.0272, -0.2292), Vector2(0.0252, -0.2292),
		Vector2(0.0252, -0.214), Vector2(0.0, -0.214), Vector2(0.0, -0.137)], 48, 0.0012, true), "anod", ax)
	b.add(_ring("g28_sc_obj_band", 0.0279, 0.0283, -0.1955, -0.1985, 48, 0.0), "steel", ax)
	b.add(_lat("g28_sc_shade", [Vector2(0.0263, -0.2286), Vector2(0.0285, -0.2286), Vector2(0.0285, -0.2895), Vector2(0.0278, -0.291),
		Vector2(0.0263, -0.291)], 48, 0.0005, true), "anod", ax)
	b.add(GunModels.cylz(0.0253, -0.2145, -0.2155, 40, 0.0), "bore", ax)
	b.add(_lat("g28_sc_lens_f", [Vector2(0.0, -0.2263), Vector2(0.0253, -0.2253), Vector2(0.0253, -0.2247), Vector2(0.0, -0.225)],
		40, 0.0), "lens_coated", ax)
	# --- Okular (hohl): Uebergang, Vergroesserungsring, Dioptrienring, Rendelring, Deckelband, Glas
	b.add(_lat("g28_sc_oc", [Vector2(0.0148, 0.049), Vector2(0.0152, 0.051), Vector2(0.0175, 0.057), Vector2(0.0175, 0.081),
		Vector2(0.0208, 0.093), Vector2(0.0208, 0.1365), Vector2(0.0198, 0.1375), Vector2(0.0178, 0.1375), Vector2(0.0178, 0.127),
		Vector2(0.0, 0.127), Vector2(0.0, 0.049)], 48, 0.0008, true), "anod", ax)
	b.add(GunModels.ext("g28_sc_pwr", _gear(32, 0.0198, 0.0189), 0.006, 0.0005, 0.0003, 1), "anod",
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, YS, 0.065)))
	b.add(_lat("g28_sc_pwr_band", [Vector2(0.0, 0.0708), Vector2(0.019, 0.0708), Vector2(0.0192, 0.0716), Vector2(0.0192, 0.0784),
		Vector2(0.0185, 0.0792), Vector2(0.0, 0.0792)], 48, 0.0), "anod", ax)
	b.add(GunModels.rbox(Vector3(0.0036, 0.0078, 0.0175), 0.0013), "anod",
		GunModels.T(Vector3(sin(deg_to_rad(42.0)) * 0.0222, YS + cos(deg_to_rad(42.0)) * 0.0222, 0.067), Vector3(0, 0, -42)))
	var mags: Array = ["3", "4", "6", "8", "12", "16", "20"]
	for i in mags.size():
		var psi: float = deg_to_rad(-60.0 + 20.0 * float(i))
		var nrm := Vector3(sin(psi), cos(psi), 0.0)
		_lbl(b, mags[i], Vector3(0, YS, 0.075) + nrm * 0.0195, nrm, Vector3.FORWARD, 0.0027, WHITE)
	b.add(GunModels.rbox(Vector3(0.0007, 0.0005, 0.0034), 0.0001), "steel", GunModels.T(Vector3(0, YS + 0.0182, 0.0832), Vector3(-15, 0, 0)))
	b.add(_lat("g28_sc_diop", [Vector2(0.0, 0.094), Vector2(0.0212, 0.094), Vector2(0.0215, 0.0948), Vector2(0.0215, 0.0995),
		Vector2(0.0, 0.0995)], 48, 0.0), "anod", ax)
	var dio: Array = ["-", "0", "+"]
	for i in 3:
		var psi2: float = deg_to_rad(-22.0 + 22.0 * float(i))
		var n2 := Vector3(sin(psi2), cos(psi2), 0.0)
		_lbl(b, dio[i], Vector3(0, YS, 0.0968) + n2 * 0.0218, n2, Vector3.FORWARD, 0.0028, WHITE)
	b.add(GunModels.ext("g28_sc_eyep", _gear(44, 0.0227, 0.0217), 0.0105, 0.0006, 0.0003, 1), "rubber",
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, YS, 0.1105)))
	b.add(_ring("g28_sc_capband_r", 0.0206, 0.0226, 0.1238, 0.1352, 48, 0.0005), "poly", ax)
	b.add(GunModels.cylz(0.0179, 0.1284, 0.1292, 40, 0.0), "bore", ax)
	b.add(_lat("g28_sc_lens_r", [Vector2(0.0, 0.1319), Vector2(0.0179, 0.1323), Vector2(0.0179, 0.1328), Vector2(0.0, 0.1332)],
		40, 0.0), "lens_coated", ax)
	# --- Turmgehaeuse (Sattel)
	b.add(GunModels.ext("g28_sc_saddle", [Vector2(-0.007, YS - 0.0145), Vector2(-0.069, YS - 0.0145), Vector2(-0.069, YS + 0.0168),
		Vector2(-0.007, YS + 0.0168)], 0.0175, 0.0065, 0.009, 3), "anod")
	# Hoehenturm oben
	_turret(b, Vector3(0, YS + 0.0168, ZT), 0)
	# Seitenturm rechts
	_turret(b, Vector3(0.0175, YS, ZT), 1)
	# Parallaxe-Rad + Leuchtabsehen-Knopf links
	_side_knob(b, Vector3(-0.0175, YS, ZT))
	# --- Beschriftung
	_lbl(b, "AQUILA", Vector3(-0.0153, YS, -0.088), Vector3.LEFT, Vector3.UP, 0.0042, WHITE)
	_lbl(b, "3-20x56", Vector3(0.0153, YS, -0.088), Vector3.RIGHT, Vector3.UP, 0.0038, WHITE)
	_lbl(b, "FFP  MRAD", Vector3(-0.0153, YS, 0.0425), Vector3.LEFT, Vector3.UP, 0.0024, GREY)
	# --- Klappdeckel: vorn nach oben geklappt, hinten zur Seite
	var cap: ArrayMesh = _lat("g28_sc_cap", [Vector2(0.0, -0.004), Vector2(0.029, -0.004), Vector2(0.0312, -0.002),
		Vector2(0.0312, 0.008), Vector2(0.0297, 0.008), Vector2(0.0297, 0.0), Vector2(0.0, 0.0)], 40, 0.0006, true)
	b.add(_ring("g28_sc_capband_f", 0.0284, 0.0297, -0.2718, -0.2905, 48, 0.0005), "poly", ax)
	var hf := Vector3(0, YS + 0.0318, -0.2905)
	b.add(GunModels.rbox(Vector3(0.008, 0.0045, 0.012), 0.0015), "poly", GunModels.T(Vector3(0, YS + 0.0302, -0.2848)))
	b.add(GunModels.cylz(0.0026, -0.0055, 0.0055, 12, 0.0006), "poly_dark", GunModels.T(hf, Vector3(0, 90, 0)))
	var fxf: Transform3D = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(158.0)), hf) * Transform3D(Basis.IDENTITY, Vector3(0, YS, -0.2935) - hf)
	b.add(cap, "poly", fxf)
	b.add(GunModels.rbox(Vector3(0.009, 0.0065, 0.0035), 0.0013), "poly", fxf * GunModels.T(Vector3(0, -0.032, -0.0012)))
	b.add(_ring("g28_sc_capring_f", 0.012, 0.0185, -0.0046, -0.0041, 32, 0.0), "poly_dark", fxf)
	var rs: float = 0.0232 / 0.0312
	var hr := Vector3(-0.0248, YS, 0.1352)
	b.add(GunModels.rbox(Vector3(0.0045, 0.008, 0.009), 0.0015), "poly", GunModels.T(Vector3(-0.0226, YS, 0.1305)))
	b.add(GunModels.cylz(0.0024, -0.005, 0.005, 12, 0.0006), "poly_dark", GunModels.T(hr, Vector3(-90, 0, 0)))
	var rxf: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(-162.0)), hr) * Transform3D(Basis(Vector3.UP, PI).scaled(Vector3(rs, rs, 1.0)), Vector3(0, YS, 0.1395) - hr)
	b.add(cap, "poly", rxf)
	b.add(GunModels.rbox(Vector3(0.0065, 0.009, 0.0035), 0.0013), "poly", rxf * GunModels.T(Vector3(0.0315, 0.0, -0.0012)))

## Turm: kind 0 = Hoehe (Achse +Y), 1 = Seite (Achse +X). pos = Mitte der Auflageflaeche.
static func _turret(b: GunModels.Builder, pos: Vector3, kind: int) -> void:
	var rot: Vector3 = Vector3(-90, 0, 0) if kind == 0 else Vector3(0, 90, 0)
	var axis: Vector3 = Vector3.UP if kind == 0 else Vector3.RIGHT
	var xf := GunModels.T(pos, rot)
	b.add(_lat("g28_tur_base", [Vector2(0.0, -0.004), Vector2(0.0132, -0.004), Vector2(0.0132, 0.0045), Vector2(0.0124, 0.005),
		Vector2(0.0124, 0.006), Vector2(0.0, 0.006)], 36, 0.0006), "anod", xf)
	b.add(_lat("g28_tur_band", [Vector2(0.0, 0.006), Vector2(0.0154, 0.006), Vector2(0.0158, 0.0068), Vector2(0.0158, 0.0122),
		Vector2(0.0, 0.0122)], 40, 0.0), "anod", xf)
	var gb: Basis = Basis(Vector3.BACK, PI * 0.5) if kind == 0 else Basis.IDENTITY
	b.add(GunModels.ext("g28_tur_cap", _gear(36, 0.0168, 0.0158), 0.006, 0.0005, 0.0003, 1), "anod",
		Transform3D(gb, pos + axis * 0.0184))
	b.add(_lat("g28_tur_top", [Vector2(0.0, 0.0242), Vector2(0.0162, 0.0242), Vector2(0.0162, 0.0256), Vector2(0.015, 0.0268),
		Vector2(0.0, 0.0268)], 40, 0.0005), "anod", xf)
	b.add(_lat("g28_tur_screw", [Vector2(0.0, 0.026), Vector2(0.0058, 0.026), Vector2(0.0058, 0.0272), Vector2(0.005, 0.0278),
		Vector2(0.0, 0.0278)], 24, 0.0002), "park", xf)
	# Skala: Striche (blank, wie graviert) und Zahlen auf dem glatten Band, Indexstrich am Sockel
	var nums: int = 10
	for k in nums * 2:
		var th: float = TAU * float(k) / float(nums * 2)
		var major: bool = k % 2 == 0
		var hh: float = 0.0026 if major else 0.0014
		var radial: Vector3
		var tick_xf: Transform3D
		if kind == 0:
			radial = Vector3(sin(th), 0, cos(th))
			tick_xf = GunModels.T(pos + axis * (0.0122 - hh * 0.5) + radial * 0.0158, Vector3(0, rad_to_deg(th), 0))
		else:
			radial = Vector3(0, sin(th), cos(th))
			tick_xf = GunModels.T(pos + axis * (0.0122 - hh * 0.5) + radial * 0.0158, Vector3(-rad_to_deg(th), 0, 90))
		b.add(GunModels.rbox(Vector3(0.0006, hh, 0.0006), 0.0001), "steel", tick_xf)
		if major:
			var up_dir: Vector3 = axis
			_lbl(b, str(k / 2), pos + axis * 0.0082 + radial * 0.016, radial, up_dir, 0.0026, WHITE)
	var idx_dir: Vector3 = Vector3.BACK if kind == 0 else Vector3.UP
	var idx_rot: Vector3 = Vector3.ZERO if kind == 0 else Vector3(0, 0, 90)
	b.add(GunModels.rbox(Vector3(0.0007, 0.0034, 0.0007), 0.0001), "steel",
		GunModels.T(pos + axis * 0.0022 + idx_dir * 0.0133, idx_rot))
	if kind == 0:
		_lbl(b, "UP", pos + axis * 0.0279 + Vector3(0, 0, 0.0095), Vector3.UP, Vector3.FORWARD, 0.0028, WHITE)
	else:
		_lbl(b, "R", pos + axis * 0.0279 + Vector3(0, 0.0098, 0), Vector3.RIGHT, Vector3.UP, 0.003, WHITE)

## Parallaxe-Rad (gross, geriffelt, mit Entfernungen) und Leuchtpunkt-Knopf links, Achse -X.
static func _side_knob(b: GunModels.Builder, pos: Vector3) -> void:
	var xf := GunModels.T(pos, Vector3(0, -90, 0))
	b.add(_lat("g28_tur_base", [Vector2(0.0, -0.004), Vector2(0.0132, -0.004), Vector2(0.0132, 0.0045), Vector2(0.0124, 0.005),
		Vector2(0.0124, 0.006), Vector2(0.0, 0.006)], 36, 0.0006), "anod", xf)
	b.add(GunModels.ext("g28_plx_wheel", _gear(40, 0.019, 0.0181), 0.0045, 0.0006, 0.0003, 1), "anod",
		GunModels.T(pos + Vector3(-0.0105, 0, 0)))
	b.add(_lat("g28_plx_face", [Vector2(0.0, 0.0145), Vector2(0.0176, 0.0145), Vector2(0.0176, 0.0152), Vector2(0.0168, 0.016),
		Vector2(0.0, 0.016)], 40, 0.0), "anod", xf)
	b.add(GunModels.ext("g28_ill_knob", _gear(16, 0.0098, 0.0091), 0.0045, 0.0006, 0.0003, 1), "anod",
		GunModels.T(pos + Vector3(-0.0205, 0, 0)))
	b.add(_lat("g28_ill_cap", [Vector2(0.0, 0.0248), Vector2(0.0086, 0.0248), Vector2(0.0086, 0.0262), Vector2(0.0078, 0.027),
		Vector2(0.0, 0.027)], 28, 0.0003), "park", xf)
	b.add(GunModels.rbox(Vector3(0.0008, 0.0095, 0.0013), 0.0003), "bore", GunModels.T(pos + Vector3(-0.0271, 0, 0)))
	var dists: Array = ["50", "100", "200", "400", "800", "oo"]
	for i in dists.size():
		var th: float = deg_to_rad(-75.0 + 30.0 * float(i))
		var radial := Vector3(0, sin(th), cos(th))
		_lbl(b, dists[i], pos + Vector3(-0.0162, 0, 0) + radial * 0.0136, Vector3.LEFT, radial, 0.0022, WHITE)
	var ill: Array = ["0", "2", "4", "6", "8"]
	for i in ill.size():
		var th2: float = deg_to_rad(-60.0 + 30.0 * float(i))
		var r2 := Vector3(0, sin(th2), cos(th2))
		b.add(GunModels.rbox(Vector3(0.0012, 0.0006, 0.0006), 0.0001), "steel", GunModels.T(pos + Vector3(-0.0162, 0, 0) + r2 * 0.0106))
	b.add(GunModels.rbox(Vector3(0.0034, 0.0007, 0.0007), 0.0001), "steel", GunModels.T(pos + Vector3(-0.0022, 0.0, 0.0133)))
