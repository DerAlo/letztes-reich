extends RefCounted
## Prozedurale Panzerung fuer gepanzerte Gegner (armored_enemy.gd) und den Juggernaut (juggernaut.gd).
## Alle Teile werden im Skelett-RUHERAUM gebaut (+Y oben, +Z vorne, Modell ~1.85 m) und an einem
## Rahmen (Transform = Ruhepose des Knochens invertiert) unter einem BoneAttachment3D eingehaengt.
## Platten sind echte Schalen (Aussen-/Innenflaeche + gerollte Kante), Vertex-Farbe = Lack,
## Alpha = Materialkanal fuer armor_plate.gdshader (1 Lack, 0.5 Gummi, 0 blankes Metall).
## Meshes werden je (Art, Fraktion) einmal gebaut und geteilt.

const MK = preload("res://game/vehicles/models/mesh_kit.gd")

static var _cache: Dictionary = {}

# ------------------------------------------------------------------ Farben

static func colors(faction: String) -> Dictionary:
	if faction == "reich":
		return {
			"paint": Color(0.17, 0.175, 0.185), "paint2": Color(0.115, 0.12, 0.13),
			"accent": Color(1.0, 0.58, 0.1), "soft": Color(0.085, 0.09, 0.095), "web": Color(0.04, 0.042, 0.045),
			"metal": Color(0.42, 0.42, 0.43), "rubber": Color(0.035, 0.035, 0.038), "suit": Color(0.11, 0.115, 0.125),
		}
	return {
		"paint": Color(0.26, 0.27, 0.185), "paint2": Color(0.2, 0.21, 0.145),
		"accent": Color(0.36, 0.32, 0.22), "soft": Color(0.2, 0.22, 0.14), "web": Color(0.075, 0.08, 0.06),
		"metal": Color(0.4, 0.4, 0.38), "rubber": Color(0.045, 0.045, 0.04), "suit": Color(0.2, 0.215, 0.15),
	}

static func ch(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

# ------------------------------------------------------------------ Grundformen

## Schale aus einer parametrischen Mittelflaeche f(u, v) (u, v in 0..1), Dicke th.
## Normalen zeigen von der Achse (c, axis) weg (axis = 0: radial von c). Kanten werden gerollt.
## closed_u: u laeuft ringsum (Kuppel/Rohr); rim0/rim1: Kante an v = 0 / v = 1 schliessen.
static func shell(k: MK, f: Callable, nu: int, nv: int, th: float, c: Vector3, axis: Vector3,
		closed_u: bool = false, rim0: bool = true, rim1: bool = true, rim_seg: int = 4) -> void:
	var P: Array[PackedVector3Array] = []
	var den_u := float(nu if closed_u else nu - 1)
	for j in nv:
		var row := PackedVector3Array()
		for i in nu:
			row.append(f.call(float(i) / den_u, float(j) / float(nv - 1)))
		P.append(row)
	var N: Array[PackedVector3Array] = []
	for j in nv:
		var row := PackedVector3Array()
		for i in nu:
			var ip := (i + 1) % nu if closed_u else mini(i + 1, nu - 1)
			var im := (i - 1 + nu) % nu if closed_u else maxi(i - 1, 0)
			var jp := mini(j + 1, nv - 1)
			var jm := maxi(j - 1, 0)
			var p := P[j][i]
			var o := p - c
			if axis != Vector3.ZERO:
				o -= axis * o.dot(axis)
			var n := (P[j][ip] - P[j][im]).cross(P[jp][i] - P[jm][i])
			if n.length_squared() < 1e-12:
				n = o
			n = n.normalized()
			if n.dot(o) < 0.0:
				n = -n
			row.append(n)
		N.append(row)
	var h := th * 0.5
	var iu := nu if closed_u else nu - 1
	for j in nv - 1:
		for i in iu:
			var i2 := (i + 1) % nu
			var a := P[j][i]; var b := P[j][i2]; var cc := P[j + 1][i2]; var d := P[j + 1][i]
			var na := N[j][i]; var nb := N[j][i2]; var nc := N[j + 1][i2]; var nd := N[j + 1][i]
			k.quad_n(a + na * h, b + nb * h, cc + nc * h, d + nd * h, na, nb, nc, nd)
			k.quad_n(a - na * h, b - nb * h, cc - nc * h, d - nd * h, -na, -nb, -nc, -nd)
	# Rand-Schleifen
	var loops: Array = []
	if closed_u:
		if rim0:
			var l0: Array[Vector2i] = []
			for i in nu:
				l0.append(Vector2i(i, 0))
			loops.append(l0)
		if rim1:
			var l1: Array[Vector2i] = []
			for i in nu:
				l1.append(Vector2i(i, nv - 1))
			loops.append(l1)
	else:
		var l: Array[Vector2i] = []
		for i in nu:
			l.append(Vector2i(i, 0))
		for j in range(1, nv):
			l.append(Vector2i(nu - 1, j))
		for i in range(nu - 2, -1, -1):
			l.append(Vector2i(i, nv - 1))
		for j in range(nv - 2, 0, -1):
			l.append(Vector2i(0, j))
		loops.append(l)
	for lp: Array[Vector2i] in loops:
		var prof: Array[PackedVector3Array] = []
		var pn: Array[PackedVector3Array] = []
		for q in lp:
			var i := q.x
			var j := q.y
			var p := P[j][i]
			var n := N[j][i]
			var ii := i
			var jj := j
			if not closed_u:
				ii = i + (1 if i == 0 else (-1 if i == nu - 1 else 0))
			jj = j + (1 if j == 0 else (-1 if j == nv - 1 else 0))
			var e := p - P[jj][ii]
			e -= n * e.dot(n)
			if e.length_squared() < 1e-12:
				e = n.cross(Vector3.UP)
			e = e.normalized()
			var pts := PackedVector3Array()
			var nrm := PackedVector3Array()
			for s in rim_seg + 1:
				var ang := PI * float(s) / float(rim_seg)
				var dn := n * cos(ang) + e * sin(ang)
				pts.append(p + n * cos(ang) * h + e * sin(ang) * h)
				nrm.append(dn.normalized())
			prof.append(pts)
			pn.append(nrm)
		var m := lp.size()
		for q in m:
			var q2 := (q + 1) % m
			for s in rim_seg:
				k.quad_n(prof[q][s], prof[q2][s], prof[q2][s + 1], prof[q][s + 1], pn[q][s], pn[q2][s], pn[q2][s + 1], pn[q][s + 1])

## Kleiner Rundkopf-Bolzen auf einer Flaeche (p = Flaechenpunkt, n = Normale).
static func bolt(k: MK, p: Vector3, n: Vector3, r: float = 0.007) -> void:
	k.lathe(p - n * 0.002, n, PackedVector2Array([Vector2(0, 0), Vector2(0, r), Vector2(r * 0.3, r * 0.92),
		Vector2(r * 0.55, r * 0.6), Vector2(r * 0.68, 0.0)]), 8, true)

## Rohr entlang a -> b mit Profil prof (x = 0..1 entlang, y = Radius).
static func tube(k: MK, a: Vector3, b: Vector3, prof: PackedVector2Array, seg: int = 14) -> void:
	var l := a.distance_to(b)
	var p2 := PackedVector2Array()
	for q in prof:
		p2.append(Vector2(q.x * l, q.y))
	k.lathe(a, b - a, p2, seg, true)

## Punkt auf einem Ellipsoid (Azimut az um +Y, 0 = vorne +Z; Elevation el).
static func ell(c: Vector3, r: Vector3, az: float, el: float) -> Vector3:
	return c + Vector3(sin(az) * cos(el) * r.x, sin(el) * r.y, cos(az) * cos(el) * r.z)

static func ell_n(r: Vector3, az: float, el: float) -> Vector3:
	return Vector3(sin(az) * cos(el) / r.x, sin(el) / r.y, cos(az) * cos(el) / r.z).normalized()

## Rechtshaendiger Rahmen eines Glieds: Y entlang des Knochens, X zur Seite (side = +1 links/+X).
static func limb_frame(a: Vector3, b: Vector3, side: float) -> Basis:
	var y := (b - a).normalized()
	var x := Vector3(side, 0, 0)
	x = (x - y * x.dot(y)).normalized()
	var z := x.cross(y)
	return Basis(x, y, z)

static func bp(sk: Skeleton3D, bone: String) -> Vector3:
	return sk.get_bone_global_rest(sk.find_bone(bone)).origin

# ------------------------------------------------------------------ Teile-Liste

## Rueckgabe: Array von {id, bone, meshes: {plate|soft|visor|glow: ArrayMesh}}
static func pieces(kind: String, faction: String, sk: Skeleton3D) -> Array:
	var key := kind + "|" + faction + "|%d" % sk.get_bone_count()   # Glied-Teile haengen vom Rig ab
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	if kind == "juggernaut":
		_build_juggernaut(out, faction, sk)
	else:
		_build_armored(out, faction, sk)
	_cache[key] = out
	return out

static func _add(out: Array, id: String, bone: String, meshes: Dictionary) -> void:
	var m := {}
	for key: String in meshes:
		var k: MK = meshes[key]
		if k.tri_count() > 0:
			m[key] = k.commit()
	out.append({"id": id, "bone": bone, "meshes": m})

# ------------------------------------------------------------------ Operator-Rig

## Alle Rumpf-/Kopf-Konstanten dieser Datei sind im Ruheraum des alten SWAT-Rigs gebaut. Fuer das
## Operator-Rig (assets/characters/soldier_op) bildet op_fix(bone) diesen Raum auf dessen Ruhepose ab
## (gemessene Querschnitte: Rumpf ~0.1 m weiter hinten, breiter/tiefer wegen der Weste; Kopf weiter
## hinten). Glied-Teile werden aus den Knochen des Rigs gebaut und brauchen keine Korrektur.
const OP_FIX_CHEST := Transform3D(Vector3(1.3, 0, 0), Vector3(0, 0.912, 0), Vector3(0, 0, 1.37), Vector3(0.004 - 0.004 * 1.3, 0.949 - 0.865 * 0.912, -0.005 - 0.085 * 1.37))
const OP_FIX_HIPS := Transform3D(Vector3(1.2, 0, 0), Vector3(0, 1.0, 0), Vector3(0, 0, 1.25), Vector3(0.006 - 0.008 * 1.2, 0.949 - 0.865, -0.01 - 0.07 * 1.25))
const OP_FIX_HEAD := Transform3D(Vector3(1.05, 0, 0), Vector3(0, 1.03, 0), Vector3(0, 0, 1.18), Vector3(-0.004 - 0.004 * 1.05, 1.665 - 1.665 * 1.03, 0.055 - 0.108 * 1.18))

static func op_fix(bone: String) -> Transform3D:
	match bone:
		"Chest":
			return OP_FIX_CHEST
		"Hips":
			return OP_FIX_HIPS
		"Head":
			return OP_FIX_HEAD
	return Transform3D.IDENTITY

# ================================================================== Gepanzerter Soldat

const A_HC := Vector3(0.004, 1.665, 0.108)       # Helm-Mittelpunkt
const A_HR := Vector3(0.143, 0.172, 0.158)       # Helm-Radien

static func _build_armored(out: Array, faction: String, sk: Skeleton3D) -> void:
	var c := colors(faction)
	var reich := faction == "reich"
	# --- Plattentraeger (Stoff) + Taschen: bleibt immer am Koerper
	var soft := MK.new()
	soft.color = c["soft"]
	var rings: Array[PackedVector3Array] = []
	for yr: Vector3 in [Vector3(1.06, 0.97, 0.94), Vector3(1.075, 1.0, 1.0), Vector3(1.415, 1.0, 1.0), Vector3(1.43, 0.96, 0.93)]:
		var r := PackedVector3Array()
		for p in MK.superellipse(0.158 * yr.y, 0.135 * yr.z, 3.0, 28):
			r.append(Vector3(0.004 + p.x, yr.x, 0.085 + p.y))
		rings.append(r)
	soft.loft(rings, false, false, true)
	# Kummerbund-Gurtbaender (Querstreifen an den Seiten)
	soft.color = c["web"]
	for sx: float in [-1.0, 1.0]:
		for yy: float in [1.12, 1.17, 1.22]:
			soft.cbox(Vector3(sx * 0.158, yy, 0.085), Vector3(0.012, 0.018, 0.17), 0.004)
	# Schultergurte
	soft.color = c["soft"]
	for sx: float in [-1.0, 1.0]:
		soft.cbox(Vector3(0.004 + sx * 0.098, 1.462, 0.085), Vector3(0.068, 0.03, 0.27), 0.012, Vector3(0, 0, sx * -8.0))
	# Plakat mit drei Magazintaschen vor dem unteren Plattenrand
	for i in 3:
		var x := 0.004 - 0.072 + 0.072 * float(i)
		soft.color = c["soft"]
		soft.cbox(Vector3(x, 1.105, 0.262), Vector3(0.066, 0.105, 0.048), 0.012, Vector3(-4, 0, 0))
		soft.color = c["web"]
		soft.cbox(Vector3(x, 1.152, 0.266), Vector3(0.07, 0.02, 0.054), 0.006, Vector3(-4, 0, 0))
		soft.color = ch(c["metal"], 1.0)
		soft.cbox(Vector3(x, 1.128, 0.29), Vector3(0.016, 0.026, 0.006), 0.002, Vector3(-4, 0, 0))
	soft.color = c["web"]
	soft.cbox(Vector3(0.004, 1.06, 0.255), Vector3(0.23, 0.02, 0.05), 0.006)   # Plakat-Unterkante
	# Funkgeraet hinten links
	soft.color = c["web"]
	soft.cbox(Vector3(-0.1, 1.16, -0.085), Vector3(0.07, 0.15, 0.05), 0.01)
	soft.cyl(Vector3(-0.115, 1.235, -0.095), Vector3(-0.14, 1.58, -0.12), 0.004, 5)
	if reich:
		soft.color = c["accent"]
		for sx: float in [-1.0, 1.0]:
			soft.cbox(Vector3(0.004 + sx * 0.098, 1.479, 0.13), Vector3(0.07, 0.004, 0.05), 0.001, Vector3(0, 0, sx * -8.0))
	_add(out, "carrier", "Chest", {"soft": soft})

	# --- Brustplatte (SAPI-Form mit Schuetzenschnitt)
	var pf := MK.new()
	pf.color = ch(c["paint"], 1.0)
	var fpf := func(u: float, v: float) -> Vector3:
		var uu := u * 2.0 - 1.0
		var a := uu * 0.7
		var top := 1.455 - 0.075 * smoothstep(0.38, 0.97, absf(uu))
		var bot := 1.128 + 0.012 * uu * uu
		var y := lerpf(bot, top, v)
		var bul := sin(PI * clampf((y - 1.12) / 0.34, 0.0, 1.0))
		var rz := 0.19 + 0.02 * bul
		return Vector3(0.004 + sin(a) * 0.2, y, 0.04 + cos(a) * rz)
	shell(pf, fpf, 15, 11, 0.022, Vector3(0.004, 0, 0.04), Vector3.UP)
	_plate_details(pf, c, fpf, reich, true)
	_add(out, "plate_front", "Chest", {"plate": pf})

	# --- Rueckenplatte
	var pb := MK.new()
	pb.color = ch(c["paint2"], 1.0)
	var fpb := func(u: float, v: float) -> Vector3:
		var uu := u * 2.0 - 1.0
		var a := PI + uu * 0.68
		var top := 1.45 - 0.05 * smoothstep(0.45, 0.97, absf(uu))
		var y := lerpf(1.125, top, v)
		var rz := 0.19 + 0.008 * sin(PI * v)
		return Vector3(0.004 + sin(a) * 0.205, y, 0.122 + cos(a) * rz)
	shell(pb, fpb, 13, 9, 0.022, Vector3(0.004, 0, 0.122), Vector3.UP)
	_plate_details(pb, c, fpb, reich, false)
	_add(out, "plate_back", "Chest", {"plate": pb})

	# --- Schulterschutz (zwei Lamellen) und Oberschenkelplatten
	for side: float in [1.0, -1.0]:
		var sname := "L" if side > 0.0 else "R"
		var ua := bp(sk, "UpperArm." + sname)
		var la := bp(sk, "LowerArm." + sname)
		var bas := limb_frame(ua, la, side)
		var sh := MK.new()
		var org := ua + bas.y * 0.03 + bas.x * 0.012
		for lame in 2:
			sh.color = ch(c["paint"] if lame == 0 else c["paint2"], 1.0)
			var y0 := -0.075 + 0.075 * float(lame)
			var y1 := y0 + 0.095
			var rad := 0.083 + 0.008 * float(lame)
			var fs := func(u: float, v: float) -> Vector3:
				var az := lerpf(-1.55, 1.55, u)
				var t := lerpf(y0, y1, v)
				# Oben eingezogen (Kuppel ueber dem Gelenk)
				var dome := 1.0 - 0.5 * pow(clampf((-t - 0.02) / 0.06, 0.0, 1.0), 2.0)
				var rr := rad * dome * (1.0 + 0.06 * v)
				return org + bas.x * (cos(az) * rr) + bas.z * (sin(az) * rr * 1.05) + bas.y * t
			shell(sh, fs, 11, 6, 0.014, org, bas.y, false, true, true, 3)
			sh.color = ch(c["metal"], 0.0)
			for az: float in [-1.1, 0.0, 1.1]:
				var tt := y1 - 0.016
				var p: Vector3 = fs.call((az + 1.55) / 3.1, 0.85)
				var n := (bas.x * cos(az) + bas.z * sin(az)).normalized()
				bolt(sh, p + n * 0.007, n, 0.0055)
		# Gurt
		sh.color = ch(c["rubber"], 0.5)
		var gp := org + bas.y * 0.03
		sh.cbox(gp + bas.x * 0.0, Vector3.ONE * 0.001, 0.0)
		_add(out, "shoulder_" + sname, "UpperArm." + sname, {"plate": sh})

		var ul := bp(sk, "UpperLeg." + sname)
		var ll := bp(sk, "LowerLeg." + sname)
		var bl := limb_frame(ul, ll, side)
		var lenl := ul.distance_to(ll)
		var th := MK.new()
		th.color = ch(c["paint2"], 1.0)
		var fwd := 1.0 if bl.z.z > 0.0 else -1.0   # Vorderseite im Gliedrahmen
		var ft := func(u: float, v: float) -> Vector3:
			var az := lerpf(-0.35, 1.75, u)    # 0 = aussen, +PI/2 = vorne
			var t := lerpf(0.1, 0.62, v) * lenl
			var rr := lerpf(0.098, 0.082, v) * (1.0 + 0.04 * sin(PI * v))
			return ul + bl.x * (cos(az) * rr) + bl.z * (sin(az) * rr * fwd) + bl.y * t
		shell(th, ft, 11, 8, 0.016, ul, bl.y)
		th.color = ch(c["metal"], 0.0)
		for uv: Vector2 in [Vector2(0.15, 0.12), Vector2(0.85, 0.12), Vector2(0.15, 0.88), Vector2(0.85, 0.88)]:
			var p: Vector3 = ft.call(uv.x, uv.y)
			var n := p - (ul + bl.y * bl.y.dot(p - ul))
			n = n.normalized()
			bolt(th, p + n * 0.008, n, 0.006)
		var ths := MK.new()
		ths.color = c["web"]
		for t: float in [0.2, 0.5]:
			var pc := ul + bl.y * (t * lenl)
			var r2 := PackedVector2Array([Vector2(0, 0.0), Vector2(0, 0.1), Vector2(0.025, 0.1), Vector2(0.025, 0.0)])
			ths.lathe(pc, bl.y, PackedVector2Array([Vector2(0, 0.088 - t * 0.02), Vector2(0.022, 0.088 - t * 0.02)]), 14, true)
		_add(out, "thigh_" + sname, "UpperLeg." + sname, {"plate": th, "soft": ths})

	# --- Helm (Kuppel + Nackenschutz + Kinnschutz), Visier extra
	var hm := MK.new()
	_helmet(hm, c, reich, A_HC, A_HR)
	_add(out, "helmet", "Head", {"plate": hm})
	var vs := MK.new()
	vs.color = Color(1, 1, 1, 1)
	var fv := func(u: float, v: float) -> Vector3:
		var az := lerpf(-0.98, 0.98, u)
		var el := lerpf(-0.44, 0.07, v)
		return ell(A_HC, A_HR * 1.075, az, el)
	shell(vs, fv, 13, 7, 0.011, A_HC, Vector3.ZERO)
	_add(out, "visor", "Head", {"visor": vs})

static func _plate_details(k: MK, c: Dictionary, f: Callable, reich: bool, front: bool) -> void:
	# Bolzen in den Ecken, Gummi-Kantenschutz unten, Kennzeichnung
	k.color = ch(c["metal"], 0.0)
	for uv: Vector2 in [Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.23, 0.86), Vector2(0.77, 0.86)]:
		var p: Vector3 = f.call(uv.x, uv.y)
		var n := Vector3(p.x - 0.004, 0, p.z - (0.04 if front else 0.122)).normalized()
		bolt(k, p + n * 0.011, n, 0.0065)
	k.color = ch(c["rubber"], 0.5)
	var rows := PackedVector3Array()
	for i in 13:
		var p: Vector3 = f.call(float(i) / 12.0, 0.0)
		rows.append(p)
	for i in 12:
		var a := rows[i]
		var b := rows[i + 1]
		var mid := (a + b) * 0.5
		var n := Vector3(mid.x - 0.004, 0, mid.z - (0.04 if front else 0.122)).normalized()
		var len := a.distance_to(b) + 0.004
		var rot := rad_to_deg(atan2(n.x, n.z))
		k.cbox(mid + Vector3(0, 0.006, 0), Vector3(len, 0.016, 0.028), 0.006, Vector3(0, rot, 0))
	if front:
		# Klettfeld fuer Abzeichen
		k.color = ch(c["web"], 0.5)
		var p: Vector3 = f.call(0.5, 0.62)
		k.cbox(p + Vector3(0, 0, 0.012), Vector3(0.11, 0.045, 0.004), 0.002)
		if reich:
			k.color = ch(c["accent"], 1.0)
			k.cbox(p + Vector3(0, 0, 0.0145), Vector3(0.09, 0.012, 0.002), 0.001)
		else:
			k.color = ch(Color(0.12, 0.13, 0.09), 1.0)
			k.cbox(p + Vector3(-0.025, 0, 0.0145), Vector3(0.045, 0.03, 0.002), 0.001)

## Helm mit Nackenschutz und Kinnschutz (Visier separat).
static func _helmet(k: MK, c: Dictionary, reich: bool, hc: Vector3, hr: Vector3, big: bool = false) -> void:
	k.color = ch(c["paint"], 1.0)
	var top_el := 0.04 if not big else 0.12
	var fd := func(u: float, v: float) -> Vector3:
		var az := u * TAU
		var el := lerpf(top_el, PI * 0.5, v)
		return ell(hc, hr, az, el)
	shell(k, fd, 28, 9, 0.016 if not big else 0.024, hc, Vector3.ZERO, true, true, false, 3)
	# Seiten- und Nackenschutz (vorne offen), unten ausgestellt
	k.color = ch(c["paint2"], 1.0)
	var fn := func(u: float, v: float) -> Vector3:
		var az := lerpf(0.92, TAU - 0.92, u)
		var el := lerpf(-0.8 if not big else -0.95, top_el + 0.05, v)
		var flare := 1.035 + 0.16 * clampf(-el - 0.35, 0.0, 1.0)
		return ell(hc, hr * flare, az, el)
	shell(k, fn, 20, 7, 0.016 if not big else 0.024, hc, Vector3.ZERO, false, true, true, 3)
	# Kinnschutz
	k.color = ch(c["paint"], 1.0)
	var fm := func(u: float, v: float) -> Vector3:
		var az := lerpf(-1.12, 1.12, u)
		var el := lerpf(-0.98 if not big else -0.9, -0.38, v)
		return ell(hc, hr * Vector3(1.055, 1.06, 1.06 + 0.06 * (1.0 - v)), az, el)
	shell(k, fm, 13, 5, 0.018 if not big else 0.026, hc, Vector3.ZERO)
	# Belueftungsschlitze im Kinnschutz
	k.color = ch(c["rubber"], 0.5)
	for i in 3:
		var el := -0.62 - 0.1 * float(i)
		var p := ell(hc, hr * 1.09, 0.0, el)
		k.cbox(p, Vector3(0.06 * (1.0 - 0.15 * float(i)), 0.008, 0.012), 0.003, Vector3(rad_to_deg(-el) * 0.6, 0, 0))
	# Visier-Scharniere + Schienen
	k.color = ch(c["metal"], 0.0)
	for sx: float in [-1.0, 1.0]:
		var az := sx * 1.07
		var p := ell(hc, hr * 1.06, az, -0.2)
		var n := ell_n(hr, az, -0.2)
		k.lathe(p, n, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.019), Vector2(0.012, 0.019), Vector2(0.016, 0.012), Vector2(0.018, 0.0)]), 12, true)
		k.color = ch(c["web"], 0.5)
		var rp := ell(hc, hr * 1.04, sx * 1.55, 0.2)
		k.cbox(rp, Vector3(0.012, 0.022, 0.12 if not big else 0.16), 0.004, Vector3(0, sx * 2.0, 0))
		k.color = ch(c["metal"], 0.0)
	# Halterung vorne oben
	var mp := ell(hc, hr * 1.02, 0.0, 0.42)
	k.color = ch(c["web"], 0.5)
	k.cbox(mp, Vector3(0.05, 0.035, 0.022), 0.008, Vector3(-28, 0, 0))
	k.color = ch(c["metal"], 0.0)
	for sx: float in [-1.0, 1.0]:
		bolt(k, mp + Vector3(sx * 0.016, 0.0, 0.012), Vector3(0, 0.45, 0.9).normalized(), 0.004)
	if reich:
		k.color = ch(c["accent"], 1.0)
		var fs := func(u: float, v: float) -> Vector3:
			var az := lerpf(-0.07, 0.07, u)
			var el := lerpf(0.25, 1.45, v)
			return ell(hc, hr * 1.012, az, el)
		shell(k, fs, 3, 8, 0.004, hc, Vector3.ZERO, false, true, true, 2)

# ================================================================== Juggernaut (Bombenschutzanzug)

const J_HC := Vector3(0.004, 1.672, 0.1)
const J_HR := Vector3(0.19, 0.2, 0.2)

static func _build_juggernaut(out: Array, faction: String, sk: Skeleton3D) -> void:
	var c := colors(faction)
	var reich := faction == "reich"
	# --- Anzug-Rumpf (gesteppt) + Kragen
	var suit := MK.new()
	suit.color = c["suit"]
	var rings: Array[PackedVector3Array] = []
	var ys := [0.86, 0.9, 0.98, 1.06, 1.14, 1.22, 1.3, 1.38, 1.46, 1.5]
	for idx in ys.size():
		var y: float = ys[idx]
		var t := (y - 0.86) / 0.64
		var w := lerpf(0.215, 0.255, smoothstep(0.0, 0.75, t)) * (1.0 - 0.18 * smoothstep(0.85, 1.0, t))
		var d := lerpf(0.165, 0.185, smoothstep(0.1, 0.7, t)) * (1.0 - 0.15 * smoothstep(0.85, 1.0, t))
		var quilt := 0.985 if idx % 2 == 1 else 1.0
		var r := PackedVector3Array()
		for p in MK.superellipse(w * quilt, d * quilt, 2.6, 30):
			r.append(Vector3(0.004 + p.x, y, 0.075 + p.y))
		rings.append(r)
	suit.loft(rings, false, false, true)
	# Dicker Kragen
	var cr: Array[PackedVector3Array] = []
	for yr: Vector2 in [Vector2(1.44, 0.2), Vector2(1.5, 0.215), Vector2(1.56, 0.2), Vector2(1.6, 0.17), Vector2(1.585, 0.13)]:
		var r := PackedVector3Array()
		for p in MK.superellipse(yr.y, yr.y * 0.92, 2.3, 26):
			r.append(Vector3(0.004 + p.x, yr.x, 0.085 + p.y))
		cr.append(r)
	suit.loft(cr, false, false, true)
	# Gurtzeug
	suit.color = c["web"]
	for yy: float in [0.96, 1.2]:
		var r := PackedVector3Array()
		var r2 := PackedVector3Array()
		var t := (yy - 0.86) / 0.64
		var w := lerpf(0.215, 0.255, smoothstep(0.0, 0.75, t)) + 0.008
		var d := lerpf(0.165, 0.185, smoothstep(0.1, 0.7, t)) + 0.008
		for p in MK.superellipse(w, d, 2.6, 30):
			r.append(Vector3(0.004 + p.x, yy - 0.022, 0.075 + p.y))
			r2.append(Vector3(0.004 + p.x, yy + 0.022, 0.075 + p.y))
		suit.loft([r, r2] as Array[PackedVector3Array], false, false, true)
	suit.color = ch(c["metal"], 1.0)
	for sx: float in [-1.0, 1.0]:
		suit.cbox(Vector3(sx * 0.14, 0.96, 0.255), Vector3(0.05, 0.04, 0.02), 0.006)
	_add(out, "suit", "Chest", {"soft": suit})

	# --- Brust-Explosionsschutz (grosse gewoelbte Platte, zwei Lagen) + Leistenklappe
	var chp := MK.new()
	chp.color = ch(c["paint"], 1.0)
	var fc := func(u: float, v: float) -> Vector3:
		var uu := u * 2.0 - 1.0
		var a := uu * 0.86
		var y := lerpf(0.98, 1.5 - 0.06 * smoothstep(0.5, 1.0, absf(uu)), v)
		var bul := sin(PI * clampf((y - 0.95) / 0.6, 0.0, 1.0))
		return Vector3(0.004 + sin(a) * 0.29, y, 0.02 + cos(a) * (0.255 + 0.035 * bul))
	shell(chp, fc, 17, 12, 0.034, Vector3(0.004, 0, 0.02), Vector3.UP)
	chp.color = ch(c["paint2"], 1.0)
	var fc2 := func(u: float, v: float) -> Vector3:
		var uu := u * 2.0 - 1.0
		var a := uu * 0.5
		var y := lerpf(1.17, 1.44, v)
		var bul := sin(PI * clampf((y - 0.95) / 0.6, 0.0, 1.0))
		return Vector3(0.004 + sin(a) * 0.3, y, 0.02 + cos(a) * (0.29 + 0.035 * bul))
	shell(chp, fc2, 11, 7, 0.022, Vector3(0.004, 0, 0.02), Vector3.UP)
	chp.color = ch(c["metal"], 0.0)
	for uv: Vector2 in [Vector2(0.08, 0.08), Vector2(0.92, 0.08), Vector2(0.08, 0.6), Vector2(0.92, 0.6), Vector2(0.5, 0.04)]:
		var p: Vector3 = fc.call(uv.x, uv.y)
		var n := Vector3(p.x - 0.004, 0, p.z - 0.02).normalized()
		bolt(chp, p + n * 0.017, n, 0.009)
	for uv: Vector2 in [Vector2(0.1, 0.15), Vector2(0.9, 0.15), Vector2(0.1, 0.85), Vector2(0.9, 0.85)]:
		var p: Vector3 = fc2.call(uv.x, uv.y)
		var n := Vector3(p.x - 0.004, 0, p.z - 0.02).normalized()
		bolt(chp, p + n * 0.011, n, 0.007)
	# Warnschild / Kennung
	var lp: Vector3 = fc2.call(0.5, 0.5)
	if reich:
		chp.color = ch(c["accent"], 1.0)
		chp.cbox(lp + Vector3(0, 0, 0.012), Vector3(0.16, 0.022, 0.003), 0.001)
		chp.cbox(lp + Vector3(0, -0.045, 0.012), Vector3(0.16, 0.022, 0.003), 0.001)
	else:
		chp.color = ch(Color(0.62, 0.55, 0.3), 1.0)
		chp.cbox(lp + Vector3(0, 0, 0.012), Vector3(0.14, 0.05, 0.003), 0.001)
	_add(out, "chest_plate", "Chest", {"plate": chp})

	var gr := MK.new()
	gr.color = ch(c["paint2"], 1.0)
	var fg := func(u: float, v: float) -> Vector3:
		var uu := u * 2.0 - 1.0
		var a := uu * 0.62
		var y := lerpf(0.98, 0.58 + 0.04 * uu * uu, v)
		return Vector3(0.004 + sin(a) * 0.27, y, 0.0 + cos(a) * (0.25 - 0.03 * v))
	shell(gr, fg, 11, 8, 0.026, Vector3(0.004, 0, 0.0), Vector3.UP)
	gr.color = ch(c["metal"], 0.0)
	for u: float in [0.2, 0.8]:
		var p: Vector3 = fg.call(u, 0.08)
		bolt(gr, p + Vector3(0, 0, 0.014), Vector3(0, 0, 1), 0.008)
	_add(out, "groin", "Hips", {"plate": gr})

	# --- Tornister (Treibstoff/Munition) auf dem Ruecken = Schwachstelle
	var pk := MK.new()
	pk.color = ch(c["paint2"], 1.0)
	pk.cbox(Vector3(0.004, 1.22, -0.17), Vector3(0.34, 0.4, 0.13), 0.025)      # Rahmen/Kasten
	pk.color = ch(c["metal"], 0.0)
	for sx: float in [-1.0, 1.0]:
		pk.cbox(Vector3(0.004 + sx * 0.172, 1.22, -0.17), Vector3(0.012, 0.42, 0.11), 0.004)
	var tank_col := ch(Color(0.42, 0.12, 0.08), 1.0) if not reich else ch(c["accent"] * 0.75, 1.0)
	for sx: float in [-1.0, 1.0]:
		pk.color = tank_col
		var tx := 0.004 + sx * 0.085
		tube(pk, Vector3(tx, 1.02, -0.29), Vector3(tx, 1.47, -0.29), PackedVector2Array([Vector2(0, 0), Vector2(0.0, 0.05),
			Vector2(0.04, 0.068), Vector2(0.96, 0.068), Vector2(1.0, 0.05), Vector2(1.0, 0.0)]), 16)
		pk.color = ch(c["metal"], 0.0)
		tube(pk, Vector3(tx, 1.47, -0.29), Vector3(tx, 1.52, -0.29), PackedVector2Array([Vector2(0, 0.022), Vector2(0.4, 0.022),
			Vector2(0.45, 0.03), Vector2(0.8, 0.03), Vector2(1.0, 0.0)]), 10)
		for yy: float in [1.12, 1.38]:
			tube(pk, Vector3(tx, yy - 0.012, -0.29), Vector3(tx, yy + 0.012, -0.29), PackedVector2Array([Vector2(0, 0.0705), Vector2(1, 0.0705)]), 16)
	# Schlaeuche zum Anzug
	pk.color = ch(c["rubber"], 0.5)
	for sx: float in [-1.0, 1.0]:
		var a := Vector3(0.004 + sx * 0.085, 1.53, -0.29)
		var b := Vector3(0.004 + sx * 0.16, 1.56, -0.1)
		tube(pk, a, b, PackedVector2Array([Vector2(0, 0.012), Vector2(1, 0.012)]), 8)
	pk.color = ch(Color(0.75, 0.62, 0.15), 1.0)
	pk.cbox(Vector3(0.004, 1.32, -0.237), Vector3(0.06, 0.06, 0.004), 0.001, Vector3(0, 0, 45))   # Warnraute
	_add(out, "pack", "Chest", {"plate": pk})

	# --- Glieder: gesteppte Anzugrohre + Platten
	for side: float in [1.0, -1.0]:
		var sname := "L" if side > 0.0 else "R"
		var ua := bp(sk, "UpperArm." + sname)
		var la := bp(sk, "LowerArm." + sname)
		var wr := bp(sk, "Wrist." + sname)
		var arm := MK.new()
		arm.color = c["suit"]
		tube(arm, ua - (la - ua).normalized() * 0.02, la, _quilt(0.085, 0.078, 4), 14)
		tube(arm, la - (wr - la).normalized() * 0.03, wr - (wr - la).normalized() * 0.02, _quilt(0.077, 0.066, 3), 14)
		var armp := MK.new()
		var bas := limb_frame(ua, la, side)
		var org := ua + bas.y * 0.02
		armp.color = ch(c["paint"], 1.0)
		var fs := func(u: float, v: float) -> Vector3:
			var az := lerpf(-1.75, 1.75, u)
			var t := lerpf(-0.11, 0.1, v)
			var dome := 1.0 - 0.55 * pow(clampf((-t - 0.03) / 0.08, 0.0, 1.0), 2.0)
			var rr := 0.125 * dome
			return org + bas.x * (cos(az) * rr) + bas.z * (sin(az) * rr * 1.08) + bas.y * t
		shell(armp, fs, 13, 7, 0.022, org, bas.y, false, true, true, 3)
		armp.color = ch(c["paint2"], 1.0)
		var fs2 := func(u: float, v: float) -> Vector3:
			var az := lerpf(-1.5, 1.5, u)
			var t := lerpf(0.07, 0.15, v)
			return org + bas.x * (cos(az) * 0.112) + bas.z * (sin(az) * 0.118) + bas.y * t
		shell(armp, fs2, 11, 4, 0.018, org, bas.y, false, true, true, 3)
		armp.color = ch(c["metal"], 0.0)
		for az: float in [-1.2, 0.0, 1.2]:
			var n := (bas.x * cos(az) + bas.z * sin(az)).normalized()
			bolt(armp, org + n * 0.138 + bas.y * 0.07, n, 0.007)
		_add(out, "arm_" + sname, "UpperArm." + sname, {"soft": arm, "plate": armp})
		# Unterarm-Schiene
		var fa := MK.new()
		var bf := limb_frame(la, wr, side)
		fa.color = ch(c["paint2"], 1.0)
		var lfa := la.distance_to(wr)
		var ff := func(u: float, v: float) -> Vector3:
			var az := lerpf(-1.3, 1.3, u)
			var t := lerpf(0.12, 0.85, v) * lfa
			return la + bf.x * (cos(az) * 0.088) + bf.z * (sin(az) * 0.088) + bf.y * t
		shell(fa, ff, 9, 5, 0.016, la, bf.y)
		_add(out, "forearm_" + sname, "LowerArm." + sname, {"plate": fa})

		var ul := bp(sk, "UpperLeg." + sname)
		var ll := bp(sk, "LowerLeg." + sname)
		var ft := bp(sk, "Foot." + sname)
		var leg := MK.new()
		leg.color = c["suit"]
		tube(leg, ul - (ll - ul).normalized() * 0.06, ll + (ll - ul).normalized() * 0.07, _quilt(0.122, 0.104, 5), 16)
		var bl := limb_frame(ul, ll, side)
		var fwd := 1.0 if bl.z.z > 0.0 else -1.0
		var lenl := ul.distance_to(ll)
		var lp2 := MK.new()
		lp2.color = ch(c["paint"], 1.0)
		var fth := func(u: float, v: float) -> Vector3:
			var az := lerpf(-0.5, 2.1, u)
			var t := lerpf(0.08, 0.78, v) * lenl
			var rr := lerpf(0.142, 0.118, v)
			return ul + bl.x * (cos(az) * rr) + bl.z * (sin(az) * rr * fwd) + bl.y * t
		shell(lp2, fth, 13, 8, 0.022, ul, bl.y)
		lp2.color = ch(c["metal"], 0.0)
		for uv: Vector2 in [Vector2(0.12, 0.1), Vector2(0.88, 0.1), Vector2(0.12, 0.9), Vector2(0.88, 0.9)]:
			var p: Vector3 = fth.call(uv.x, uv.y)
			var n := (p - (ul + bl.y * bl.y.dot(p - ul))).normalized()
			bolt(lp2, p + n * 0.011, n, 0.007)
		_add(out, "thigh_" + sname, "UpperLeg." + sname, {"soft": leg, "plate": lp2})
		# Schienbein + Knie
		var shin := MK.new()
		shin.color = c["suit"]
		tube(shin, ll + (ll - ft).normalized() * 0.08, ft + (ll - ft).normalized() * 0.07, _quilt(0.108, 0.088, 4), 16)
		var sp := MK.new()
		var bs := limb_frame(ll, ft, side)
		var fws := 1.0 if bs.z.z > 0.0 else -1.0
		var lens := ll.distance_to(ft)
		sp.color = ch(c["paint2"], 1.0)
		var fsh := func(u: float, v: float) -> Vector3:
			var az := lerpf(0.35, 2.8, u)
			var t := lerpf(0.06, 0.72, v) * lens
			var rr := lerpf(0.118, 0.1, v)
			return ll + bs.x * (cos(az) * rr) + bs.z * (sin(az) * rr * fws) + bs.y * t
		shell(sp, fsh, 11, 8, 0.02, ll, bs.y)
		sp.color = ch(c["paint"], 1.0)
		var fk := func(u: float, v: float) -> Vector3:
			var az := lerpf(0.5, 2.65, u)
			var t := lerpf(-0.075, 0.06, v)
			var rr := 0.128 * (1.0 + 0.12 * sin(PI * v))
			return ll + bs.x * (cos(az) * rr) + bs.z * (sin(az) * rr * fws) + bs.y * t
		shell(sp, fk, 11, 6, 0.024, ll, bs.y)
		sp.color = ch(c["metal"], 0.0)
		var kc: Vector3 = fk.call(0.5, 0.5)
		var kn := (kc - ll).normalized()
		bolt(sp, kc + kn * 0.013, kn, 0.011)
		_add(out, "shin_" + sname, "LowerLeg." + sname, {"soft": shin, "plate": sp})

	# --- Helm (gross, rund) + Visier
	var hm := MK.new()
	_helmet(hm, c, reich, J_HC, J_HR, true)
	# Atemfilter seitlich
	hm.color = ch(c["web"], 0.5)
	for sx: float in [-1.0, 1.0]:
		var p := ell(J_HC, J_HR * 1.08, sx * 1.25, -0.55)
		var n := ell_n(J_HR, sx * 1.25, -0.55)
		hm.lathe(p - n * 0.01, n, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.034), Vector2(0.03, 0.036), Vector2(0.036, 0.03), Vector2(0.04, 0.0)]), 14, true)
	_add(out, "helmet", "Head", {"plate": hm})
	var vs := MK.new()
	vs.color = Color(1, 1, 1, 1)
	var fv := func(u: float, v: float) -> Vector3:
		var az := lerpf(-1.0, 1.0, u)
		var el := lerpf(-0.42, 0.15, v)
		return ell(J_HC, J_HR * 1.06, az, el)
	shell(vs, fv, 13, 7, 0.016, J_HC, Vector3.ZERO)
	_add(out, "visor", "Head", {"visor": vs})

## Gesteppter Rohrquerschnitt (x 0..1 entlang, y Radius) mit n Wuelsten.
static func _quilt(r0: float, r1: float, n: int) -> PackedVector2Array:
	var p := PackedVector2Array([Vector2(0, 0), Vector2(0, r0 * 0.92)])
	var steps := n * 4
	for i in steps + 1:
		var t := float(i) / float(steps)
		var r := lerpf(r0, r1, t) * (0.955 + 0.045 * absf(sin(PI * t * float(n))))
		p.append(Vector2(t, r))
	p.append(Vector2(1.0, lerpf(r0, r1, 1.0) * 0.92))
	p.append(Vector2(1.0, 0.0))
	return p
