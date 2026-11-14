extends Node3D
## Wasserflugzeug fuer Level 12 "villa": einmotoriger Hochdecker auf Schwimmern, Proportionen nach der
## DHC-2 Beaver (Rumpf ~9,3 m, Spannweite 14,64 m, Schwimmer 7,7 m). Vollstaendig prozedural (glatt
## geloftete Querschnitte), ein Lack-Material (villa_seaplane_paint.gdshader: Livree creme/dunkelrot,
## Kennzeichen OE-DBW, Blechstoesse, Nieten, Schmutz, Auspuffruss, Algenrand) plus Glas, Innenraum,
## Propellerscheibe und Kielwasser.
##
## Ursprung = Wasserlinie (root.y = WATER_Y), Nase nach -Z. villa.gd bewegt NUR diesen Root (Rollen,
## Start); Schaukeln/Vibration laufen auf dem inneren Kind "Body".
## API:
##   throttle: float 0..1        0 = Motor aus, ~0.15 Leerlauf, 1 = Vollgas
##   prop: Node3D                Propeller-Nabe (dreht um lokale Z)
##   door_point() -> Vector3     Standpunkt auf dem linken Schwimmer neben der Kabinentuer (global)
##   cabin_point() -> Vector3    Sitzplatz in der Kabine (global)
##   open_door(open: bool)       linke hintere Kabinentuer auf/zu
##   cast_off()                  Festmacherleinen loswerfen (fallen am Steg ins Wasser)
## Debug-Argumente (nur fuer Aufnahmen): --plane-throttle=0.6  --plane-door=1  --plane-taxi=8 (m/s nach -Z
## ab Sekunde 2)  --plane-ext=0 (aeussere Propellerdrehung aus villa.gd ignorieren).

const WATER_Y := -0.35
const PAINT_SH := preload("res://game/levels/villa_seaplane_paint.gdshader")
const GLASS_SH := preload("res://game/levels/villa_seaplane_glass.gdshader")
const FX_SH := preload("res://game/levels/villa_seaplane_fx.gdshader")
const NOISE_TEX := "res://assets/vehicles/textures/vehicle_noise.png"
const REGISTRATION := "OE-DBW"

## Festmacher: Klampe am linken Schwimmer (Body-lokal) -> Poller am Steg (global)
const MOORINGS: Array = [
	[Vector3(-1.52, 0.55, -3.0), Vector3(-5.1, 0.56, -65.5)],
	[Vector3(-1.5, 0.5, 2.2), Vector3(-5.1, 0.56, -60.0)],
]

const FLOAT_X := 1.25
const FLOAT_Z0 := -4.6
const FLOAT_LEN := 7.7
const PROP_POS := Vector3(0.0, 1.95, -3.3)
const PROP_R := 1.3
const DOOR_HINGE := Vector3(-0.66, 2.04, -0.36)
const WING_LE := -1.72
const WING_CHORD := 1.59
const WING_Y := 2.86
const HALF_SPAN := 7.32

## Rumpfstationen: z, halbe Breite, Unterkante, Oberkante, Superellipsen-Exponent
const FUS: Array = [
	[-2.30, 0.60, 1.35, 2.55, 2.0],
	[-2.05, 0.63, 1.33, 2.60, 2.4],
	[-1.62, 0.66, 1.32, 2.80, 2.9],
	[-1.00, 0.67, 1.32, 2.83, 3.1],
	[0.20, 0.67, 1.33, 2.83, 3.1],
	[0.95, 0.65, 1.38, 2.82, 3.0],
	[1.70, 0.57, 1.56, 2.80, 2.8],
	[2.60, 0.46, 1.80, 2.76, 2.6],
	[3.60, 0.34, 2.05, 2.72, 2.4],
	[4.60, 0.23, 2.28, 2.68, 2.3],
	[5.40, 0.14, 2.43, 2.66, 2.2],
	[5.95, 0.05, 2.55, 2.64, 2.0],
]

const C_CREAM := Color(0.84, 0.81, 0.72)
const C_TRIM := Color(0.42, 0.045, 0.04)
const C_ALU := Color(0.66, 0.67, 0.68)
const C_DARK := Color(0.035, 0.035, 0.035)
const C_DMETAL := Color(0.09, 0.085, 0.08)
const C_YELLOW := Color(0.85, 0.65, 0.05)

var throttle: float = 0.0
var prop: Node3D
var body: Node3D
var door: Node3D

var _noise: Texture2D
var _paint: ShaderMaterial
var _glass: ShaderMaterial
var _disc_mat: ShaderMaterial
var _wake_mat: ShaderMaterial
var _blades: MeshInstance3D
var _disc: MeshInstance3D
var _wake: MeshInstance3D
var _beacon_mat: StandardMaterial3D
var _spray: Array[GPUParticles3D] = []
var _wash_spray: GPUParticles3D
var _exhaust: GPUParticles3D
var _ropes: Array = []
var _cast := false
var _cast_t := 0.0
var _t := 0.0
var _omega := 0.0
var _prop_set := 0.0
var _ext_eff := 0.0
var _use_ext := true
var _speed := 0.0
var _travel := 0.0
var _last_pos := Vector3.ZERO
var _have_last := false
var _door_tw: Tween
var _dbg_taxi := 0.0
var _was_running := false


func _init() -> void:
	name = "Wasserflugzeug"
	_noise = load(NOISE_TEX) as Texture2D
	_paint = ShaderMaterial.new()
	_paint.shader = PAINT_SH
	_paint.set_shader_parameter("noise_tex", _noise)
	_glass = ShaderMaterial.new()
	_glass.shader = GLASS_SH
	_glass.render_priority = 1
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	_build_airframe()
	_build_prop()
	_build_interior()
	_build_lights()
	_build_labels()
	_build_wake()
	_build_particles()
	_build_ropes()
	_build_collision()


func _ready() -> void:
	_last_pos = global_position
	if Engine.has_singleton("Game") or get_node_or_null("/root/Game") != null:
		var g := get_node("/root/Game")
		var a: Variant = g.call("arg", "plane-throttle", null)
		if a != null:
			throttle = float(str(a))
		if g.call("arg", "plane-door", null) != null:
			open_door(true)
		var tx: Variant = g.call("arg", "plane-taxi", null)
		if tx != null:
			_dbg_taxi = float(str(tx))
		if str(g.call("arg", "plane-ext", "1")) == "0":
			_use_ext = false

# ------------------------------------------------------------------ API

func door_point() -> Vector3:
	return body.to_global(Vector3(-FLOAT_X, 0.54, 0.2))


func cabin_point() -> Vector3:
	return body.to_global(Vector3(-0.28, 1.58, 0.05))


func open_door(open: bool) -> void:
	if door == null:
		return
	if _door_tw != null and _door_tw.is_valid():
		_door_tw.kill()
	if not is_inside_tree():
		door.rotation.y = deg_to_rad(-78.0) if open else 0.0
		return
	_door_tw = create_tween()
	_door_tw.tween_property(door, "rotation:y", deg_to_rad(-78.0) if open else 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func cast_off() -> void:
	if _cast:
		return
	_cast = true
	_cast_t = 0.0

# ------------------------------------------------------------------ Laufzeit

func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	if _dbg_taxi > 0.0 and _t > 2.0:
		position += Vector3(0.0, 0.0, -_dbg_taxi * minf((_t - 2.0) / 3.0, 1.0)) * delta
	var gp := global_position
	if not _have_last:
		_last_pos = gp
		_have_last = true
	var hv := Vector2(gp.x - _last_pos.x, gp.z - _last_pos.z).length() / delta
	_last_pos = gp
	_speed = lerpf(_speed, minf(hv, 80.0), 1.0 - exp(-delta * 3.0))
	_travel += _speed * delta
	var alt := gp.y - WATER_Y
	var on_water := clampf(1.0 - alt / 1.0, 0.0, 1.0)

	# Propeller: eigene Drehzahl aus throttle; aeussere Drehung (altes villa.gd) wird erkannt
	var ext_rate := 0.0
	if _use_ext:
		ext_rate = absf(wrapf(prop.rotation.z - _prop_set, -PI, PI)) / delta
	_ext_eff = lerpf(_ext_eff, clampf(ext_rate / 30.0, 0.0, 1.0), 1.0 - exp(-delta * 4.0))
	var eff := maxf(throttle, _ext_eff)
	var target := 0.0 if eff < 0.005 else 22.0 + 218.0 * eff
	var rate := 60.0 if target > _omega else 25.0
	_omega = move_toward(_omega, target, rate * delta)
	if ext_rate < 1.0:
		prop.rotation.z = wrapf(prop.rotation.z + _omega * delta, -PI, PI)
	_prop_set = prop.rotation.z
	var disc_k := smoothstep(16.0, 55.0, _omega)
	_blades.visible = disc_k < 0.6
	_disc.visible = disc_k > 0.01
	_disc_mat.set_shader_parameter("strength", disc_k)
	_disc_mat.set_shader_parameter("spin", _t * 2.3)
	var running := _omega > 5.0
	if _beacon_mat != null:
		var bl := 1.0 if running and fmod(_t, 1.2) < 0.12 else 0.0
		_beacon_mat.emission_energy_multiplier = 0.2 + 7.0 * bl

	# Schaukeln auf dem Wasser + Motorvibration (nur Body, nie den Root)
	var calm := 1.0 - clampf(_speed / 14.0, 0.0, 0.75)
	var bob := on_water * calm
	var vib := (_omega / 240.0) * 0.0018 + (0.0025 if running and _omega < 40.0 else 0.0)
	var plow := on_water * smoothstep(2.0, 7.0, _speed) * (1.0 - smoothstep(12.0, 20.0, _speed)) * 0.065
	body.position = Vector3(
		sin(_t * 47.0) * vib,
		(sin(_t * 1.27) * 0.022 + sin(_t * 2.13 + 1.0) * 0.009) * bob + sin(_t * 61.0) * vib,
		0.0)
	body.rotation = Vector3(
		(sin(_t * 0.93 + 0.5) * 0.007 + sin(_t * 1.71) * 0.004) * bob + plow + sin(_t * 53.0) * vib * 0.5,
		0.0,
		(sin(_t * 1.11) * 0.012 + sin(_t * 0.57 + 2.0) * 0.006) * bob + sin(_t * 43.0) * vib)

	# Kielwasser (ortsfest auf Wasserhoehe, nur Gierwinkel)
	var spd_k := clampf(_speed / 9.0, 0.0, 1.0)
	_wake.visible = on_water > 0.01
	if _wake.visible:
		var yaw := global_rotation.y
		_wake.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(gp.x, WATER_Y + 0.05, gp.z))
		_wake_mat.set_shader_parameter("strength", spd_k * on_water)
		_wake_mat.set_shader_parameter("wash", clampf((_omega - 130.0) / 100.0, 0.0, 1.0) * on_water)
		_wake_mat.set_shader_parameter("contact", (0.35 + 0.4 * spd_k) * on_water)
		_wake_mat.set_shader_parameter("travel", _travel)
	for s in _spray:
		s.emitting = on_water > 0.5 and _speed > 2.0
		s.amount_ratio = clampf((_speed - 2.0) / 10.0, 0.15, 1.0)
	_wash_spray.emitting = on_water > 0.6 and _omega > 150.0
	_exhaust.emitting = running
	if running and not _was_running:
		_exhaust.amount_ratio = 1.0
	_exhaust.amount_ratio = move_toward(_exhaust.amount_ratio, 0.25, delta * 0.4)
	_was_running = running
	_update_ropes(delta)

# ------------------------------------------------------------------ Mesh-Werkzeug

class Mesher:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()

	## Flaeche aus Ringen gleicher Punktzahl mit weichen Normalen (Kante = doppelter Punkt/Ring).
	## c: eine Farbe oder Array (je Ring). Orientierung automatisch (nach aussen vom Ringmittelpunkt).
	func grid(rings: Array, c: Variant, closed: bool = true, cap0: bool = false, cap1: bool = false, hint: Vector3 = Vector3.ZERO) -> void:
		var nr := rings.size()
		var np := (rings[0] as PackedVector3Array).size()
		var base := v.size()
		var cents: Array[Vector3] = []
		for i in nr:
			var r: PackedVector3Array = rings[i]
			var ce := Vector3.ZERO
			for q in r:
				ce += q
			cents.append(ce / float(np))
			var ci: Color = (c as Array)[i] if c is Array else c
			for q in r:
				v.append(q)
				col.append(ci)
				nrm.append(Vector3.ZERO)
		var tris := PackedInt32Array()
		var score := 0.0
		var segs := np if closed else np - 1
		for i in nr - 1:
			for j in segs:
				var j2 := (j + 1) % np
				var a := base + i * np + j
				var b := base + i * np + j2
				var cc := base + (i + 1) * np + j2
				var d := base + (i + 1) * np + j
				tris.append(a)
				tris.append(b)
				tris.append(cc)
				tris.append(a)
				tris.append(cc)
				tris.append(d)
				var fn := (v[b] - v[a]).cross(v[cc] - v[a]) + (v[cc] - v[a]).cross(v[d] - v[a])
				var rf := hint if hint != Vector3.ZERO else (v[a] + v[cc]) * 0.5 - (cents[i] + cents[i + 1]) * 0.5
				score += fn.dot(rf)
		var flip := score > 0.0
		for t in range(0, tris.size(), 3):
			var a := tris[t]
			var b := tris[t + 1]
			var cc := tris[t + 2]
			var fn := (v[b] - v[a]).cross(v[cc] - v[a])
			if not flip:
				fn = -fn
			nrm[a] += fn
			nrm[b] += fn
			nrm[cc] += fn
			if flip:
				idx.append(a)
				idx.append(cc)
				idx.append(b)
			else:
				idx.append(a)
				idx.append(b)
				idx.append(cc)
		for k in range(base, v.size()):
			nrm[k] = nrm[k].normalized() if nrm[k].length_squared() > 1e-18 else Vector3.UP
		var c0: Color = (c as Array)[0] if c is Array else c
		var c1: Color = (c as Array)[nr - 1] if c is Array else c
		if cap0:
			cap(rings[0], cents[0], cents[0] - cents[1], c0)
		if cap1:
			cap(rings[nr - 1], cents[nr - 1], cents[nr - 1] - cents[nr - 2], c1)

	func cap(r: PackedVector3Array, ce: Vector3, out: Vector3, c: Color) -> void:
		if out.length_squared() < 1e-12:
			return
		var n := out.normalized()
		var base := v.size()
		v.append(ce)
		nrm.append(n)
		col.append(c)
		for q in r:
			v.append(q)
			nrm.append(n)
			col.append(c)
		var m := r.size()
		for j in m:
			var a := base
			var b := base + 1 + j
			var cc := base + 1 + (j + 1) % m
			if (v[b] - v[a]).cross(v[cc] - v[a]).dot(out) > 0.0:
				idx.append(a)
				idx.append(cc)
				idx.append(b)
			else:
				idx.append(a)
				idx.append(b)
				idx.append(cc)

	func tri(a: Vector3, b: Vector3, c: Vector3, out: Vector3, colr: Color) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-16:
			return
		if n.dot(out) < 0.0:
			n = -n
			var tmp := b
			b = c
			c = tmp
		n = n.normalized()
		var base := v.size()
		for q: Vector3 in [a, b, c]:
			v.append(q)
			nrm.append(n)
			col.append(colr)
		idx.append(base)
		idx.append(base + 2)
		idx.append(base + 1)

	func box(center: Vector3, size: Vector3, colr: Color, basis: Basis = Basis.IDENTITY) -> void:
		var h := size * 0.5
		for a in 3:
			for s: float in [-1.0, 1.0]:
				var e := Vector3.ZERO
				e[a] = s
				var u := Vector3.ZERO
				u[(a + 1) % 3] = 1.0
				var w := Vector3.ZERO
				w[(a + 2) % 3] = 1.0
				var pts: Array[Vector3] = []
				for cc: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var l := e * h + u * h * cc.x + w * h * cc.y
					pts.append(center + basis * l)
				var out := basis * e
				tri(pts[0], pts[1], pts[2], out, colr)
				tri(pts[0], pts[2], pts[3], out, colr)

	## Drehkoerper: prof = (Weg entlang Achse, Radius); doppelte Profilpunkte ergeben harte Kanten.
	func lathe(origin: Vector3, axis: Vector3, prof: Array, seg: int, c: Variant, phase: float = 0.0) -> void:
		var ax := axis.normalized()
		var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
		var w := ax.cross(u).normalized()
		var rings: Array = []
		for pp: Vector2 in prof:
			var r := PackedVector3Array()
			for j in seg:
				var a := phase + TAU * float(j) / float(seg)
				r.append(origin + ax * pp.x + (u * cos(a) + w * sin(a)) * pp.y)
			rings.append(r)
		grid(rings, c, true)

	func tube(a: Vector3, b: Vector3, r: float, seg: int, colr: Color) -> void:
		var l := a.distance_to(b)
		lathe(a, b - a, [Vector2(0, 0), Vector2(0, r), Vector2(0, r), Vector2(l, r), Vector2(l, r), Vector2(l, 0)], seg, colr)

	## Stromlinien-Strebe (elliptischer Querschnitt, lange Achse in Flugrichtung).
	func strut(a: Vector3, b: Vector3, chord: float, thick: float, colr: Color, seg: int = 10) -> void:
		var d := (b - a).normalized()
		var fwd := Vector3(0, 0, -1)
		var u := (fwd - d * fwd.dot(d))
		if u.length_squared() < 1e-6:
			u = Vector3.RIGHT
		u = u.normalized()
		var w := d.cross(u).normalized()
		var rings: Array = []
		for p: Vector3 in [a, b]:
			var r := PackedVector3Array()
			for j in seg:
				var t := TAU * float(j) / float(seg)
				var cu := cos(t)
				var k := 1.0 if cu > 0.0 else 1.35
				r.append(p + u * cu * chord * 0.5 * k * 0.85 + w * sin(t) * thick * 0.5)
			rings.append(r)
		grid(rings, colr, true, true, true)

	func commit() -> ArrayMesh:
		var am := ArrayMesh.new()
		if v.is_empty():
			return am
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_INDEX] = idx
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return am


static func _cf(c: Color, flag: float) -> Color:
	return Color(c.r, c.g, c.b, flag)


func _emit(parent: Node3D, m: Mesher, mat: Material, nm: String, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = m.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

# ------------------------------------------------------------------ Rumpfform

static func _interp(tab: Array, z: float, k: int) -> float:
	var n := tab.size()
	if z <= float(tab[0][0]):
		return float(tab[0][k])
	if z >= float(tab[n - 1][0]):
		return float(tab[n - 1][k])
	var i := 0
	while i < n - 2 and z > float(tab[i + 1][0]):
		i += 1
	var z0 := float(tab[i][0])
	var z1 := float(tab[i + 1][0])
	var p0 := float(tab[i][k])
	var p1 := float(tab[i + 1][k])
	var dz := z1 - z0
	var m0 := _slope(tab, i, k) * dz
	var m1 := _slope(tab, i + 1, k) * dz
	var t := (z - z0) / dz
	var t2 := t * t
	var t3 := t2 * t
	return (2.0 * t3 - 3.0 * t2 + 1.0) * p0 + (t3 - 2.0 * t2 + t) * m0 + (-2.0 * t3 + 3.0 * t2) * p1 + (t3 - t2) * m1


static func _slope(tab: Array, i: int, k: int) -> float:
	var n := tab.size()
	if i == 0:
		return (float(tab[1][k]) - float(tab[0][k])) / (float(tab[1][0]) - float(tab[0][0]))
	if i == n - 1:
		return (float(tab[n - 1][k]) - float(tab[n - 2][k])) / (float(tab[n - 1][0]) - float(tab[n - 2][0]))
	var a := float(tab[i][k]) - float(tab[i - 1][k])
	var b := float(tab[i + 1][k]) - float(tab[i][k])
	if a * b <= 0.0:
		return 0.0
	return (float(tab[i + 1][k]) - float(tab[i - 1][k])) / (float(tab[i + 1][0]) - float(tab[i - 1][0]))


## [w, yb, yt, e] an der Stelle z
static func _fus(z: float) -> Array:
	return [_interp(FUS, z, 1), _interp(FUS, z, 2), _interp(FUS, z, 3), _interp(FUS, z, 4)]


static func _fus_ring(z: float, n: int) -> PackedVector3Array:
	var f := _fus(z)
	var w: float = f[0]
	var mid: float = (float(f[1]) + float(f[2])) * 0.5
	var h: float = (float(f[2]) - float(f[1])) * 0.5
	var e: float = f[3]
	var r := PackedVector3Array()
	for j in n:
		var a := TAU * float(j) / float(n)
		var c := cos(a)
		var s := sin(a)
		r.append(Vector3(signf(c) * pow(absf(c), 2.0 / e) * w, mid + signf(s) * pow(absf(s), 2.0 / e) * h, z))
	return r


## Halbe Rumpfbreite in Hoehe y an der Stelle z (Superellipse).
static func _fus_x(z: float, y: float) -> float:
	var f := _fus(z)
	var mid: float = (float(f[1]) + float(f[2])) * 0.5
	var h: float = (float(f[2]) - float(f[1])) * 0.5
	var e: float = f[3]
	var t := clampf(absf(y - mid) / h, 0.0, 1.0)
	return float(f[0]) * pow(maxf(1.0 - pow(t, e), 0.0), 1.0 / e)

# ------------------------------------------------------------------ Profile

## NACA-4-Profil: Punkte (x 0..1, y) von Hinterkante oben ueber Nase nach Hinterkante unten.
static func _airfoil(thick: float, camber: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var pc := 0.4
	for side in 2:
		var ks: Array = []
		if side == 0:
			for k in range(n, -1, -1):
				ks.append(k)
		else:
			for k in range(1, n + 1):
				ks.append(k)
		for k: int in ks:
			var x := 0.5 * (1.0 - cos(PI * float(k) / float(n)))
			var yt := 5.0 * thick * (0.2969 * sqrt(x) - 0.126 * x - 0.3516 * x * x + 0.2843 * x * x * x - 0.1036 * x * x * x * x)
			var yc := 0.0
			if camber > 0.0:
				yc = camber / (pc * pc) * (2.0 * pc * x - x * x) if x < pc else camber / ((1.0 - pc) * (1.0 - pc)) * ((1.0 - 2.0 * pc) + 2.0 * pc * x - x * x)
			out.append(Vector2(x, yc + (yt if side == 0 else -yt)))
	return out

# ------------------------------------------------------------------ Zelle

func _build_airframe() -> void:
	var m := Mesher.new()
	_fuselage(m)
	_cowling(m)
	_wing(m)
	_tail(m)
	for sx: float in [-1.0, 1.0]:
		_float(m, sx * FLOAT_X)
	_struts(m)
	_details(m)
	_emit(body, m, _paint, "Airframe")
	# Verglasung: Kopie der Rumpfhaut (nur Fensterflaechen sichtbar)
	var g := Mesher.new()
	_fuselage(g)
	var gi := _emit(body, g, _glass, "Glass", false)
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_door()


func _fuselage(m: Mesher) -> void:
	var rings: Array = []
	var z := -2.3
	while z < 5.95:
		rings.append(_fus_ring(z, 48))
		z += 0.1 if z > -2.1 else 0.05
	rings.append(_fus_ring(5.95, 48))
	m.grid(rings, _cf(C_CREAM, 1.0), true, false, true)


func _cowling(m: Mesher) -> void:
	var o := Vector3(0.0, 1.95, -2.15)
	var ax := Vector3(0, 0, -1)
	var cr := _cf(C_CREAM, 0.62)
	var red := _cf(C_TRIM, 0.62)
	var dk := _cf(C_DMETAL, 0.15)
	# Motorhaube: hinten creme, vorn roter Nasenring, Lippe, dunkles Inneres
	var prof: Array = [Vector2(-0.16, 0.602), Vector2(0.2, 0.606), Vector2(0.52, 0.598), Vector2(0.52, 0.598),
		Vector2(0.72, 0.585), Vector2(0.86, 0.555), Vector2(0.94, 0.51), Vector2(0.975, 0.47), Vector2(0.98, 0.445),
		Vector2(0.965, 0.425), Vector2(0.965, 0.425), Vector2(0.9, 0.405), Vector2(0.78, 0.4)]
	var cols: Array = [cr, cr, cr, red, red, red, red, red, red, red, dk, dk, dk]
	m.lathe(o, ax, prof, 40, cols)
	# Motorstirnwand und Sternmotor (9 Zylinder) hinter der Haube
	m.lathe(o, ax, [Vector2(0.74, 0.41), Vector2(0.74, 0.0)], 24, dk)
	for k in 9:
		var a := TAU * float(k) / 9.0 + 0.17
		var d := Vector3(cos(a), sin(a), 0.0)
		var c0 := o + ax * 0.84 + d * 0.11
		var c1 := o + ax * 0.84 + d * 0.36
		m.tube(c0, c1, 0.058, 8, dk)
		for f in 4:
			m.lathe(o + ax * 0.84 + d * (0.2 + f * 0.045), d, [Vector2(0, 0), Vector2(0, 0.075), Vector2(0.012, 0.075), Vector2(0.012, 0)], 8, dk)
	m.lathe(o + ax * 0.8, ax, [Vector2(0, 0.16), Vector2(0.12, 0.15), Vector2(0.22, 0.09), Vector2(0.25, 0.0)], 16, dk)
	# Vergaser-Lufthutze unten, Oelkuehler
	m.box(Vector3(0.0, 1.33, -2.55), Vector3(0.24, 0.1, 0.5), _cf(C_TRIM, 0.62))
	m.box(Vector3(0.0, 1.30, -2.72), Vector3(0.2, 0.05, 0.02), _cf(C_DARK, 0.3))
	# Auspuff rechts unten
	m.tube(Vector3(0.36, 1.5, -2.5), Vector3(0.56, 1.47, -2.08), 0.045, 10, _cf(C_DMETAL, 0.15))
	m.lathe(Vector3(0.56, 1.47, -2.08), Vector3(0.4, -0.05, 1.0), [Vector2(0, 0.045), Vector2(0.03, 0.05), Vector2(0.03, 0.035), Vector2(-0.02, 0.035)], 10, _cf(C_DARK, 0.15))


func _wing(m: Mesher) -> void:
	var foil := _airfoil(0.155, 0.02, 14)
	var xs: Array = [-7.32, -7.29, -7.22, -7.1, -6.9, -6.0, -4.6, -3.0, -1.5, -0.6, 0.0, 0.6, 1.5, 3.0, 4.6, 6.0, 6.9, 7.1, 7.22, 7.29, 7.32]
	var rings: Array = []
	var inc := deg_to_rad(1.5)
	for x: float in xs:
		var ax := absf(x)
		var f := clampf((ax - 6.95) / (HALF_SPAN - 6.95), 0.0, 1.0)
		var thick_k := sqrt(maxf(1.0 - f * f, 0.0)) * 0.92 + 0.08 if f > 0.0 else 1.0
		var chord := WING_CHORD * (1.0 - 0.18 * f * f)
		var le := WING_LE + 0.12 * f * f
		var y0 := WING_Y + ax * 0.026
		var r := PackedVector3Array()
		for q in foil:
			var cx := q.x * chord
			var cy := q.y * chord * thick_k
			r.append(Vector3(x, y0 - cx * sin(inc) + cy * cos(inc), le + cx * cos(inc)))
		rings.append(r)
	m.grid(rings, _cf(C_CREAM, 0.85), true, true, true)
	# Pitotrohr links, Positionslicht-Gehaeuse
	m.tube(Vector3(-5.6, WING_Y + 5.6 * 0.026 - 0.12, -1.5), Vector3(-5.6, WING_Y + 5.6 * 0.026 - 0.12, -1.98), 0.012, 6, _cf(C_ALU, 0.5))
	m.tube(Vector3(-5.6, WING_Y + 5.6 * 0.026 - 0.02, -1.55), Vector3(-5.6, WING_Y + 5.6 * 0.026 - 0.12, -1.55), 0.01, 6, _cf(C_ALU, 0.5))


func _tail(m: Mesher) -> void:
	# Hoehenleitwerk
	var foil := _airfoil(0.095, 0.0, 10)
	var xs: Array = [-2.55, -2.52, -2.45, -2.3, -1.6, -0.8, 0.0, 0.8, 1.6, 2.3, 2.45, 2.52, 2.55]
	var rings: Array = []
	for x: float in xs:
		var ax := absf(x)
		var s := ax / 2.55
		var f := clampf((ax - 2.25) / 0.3, 0.0, 1.0)
		var tk := sqrt(maxf(1.0 - f * f, 0.0)) * 0.9 + 0.1 if f > 0.0 else 1.0
		var le := lerpf(4.55, 4.86, s) + 0.1 * f * f
		var te := lerpf(5.92, 5.82, s) - 0.08 * f * f
		var chord := te - le
		var r := PackedVector3Array()
		for q in foil:
			r.append(Vector3(x, 2.56 + q.y * chord * tk, le + q.x * chord))
		rings.append(r)
	m.grid(rings, _cf(C_CREAM, 0.78), true, true, true)
	# Seitenleitwerk mit Rueckenflosse
	var fin: Array = [[2.45, 3.4, 6.02], [2.62, 4.0, 6.02], [2.8, 4.32, 6.0], [3.2, 4.58, 5.98], [3.6, 4.76, 5.95],
		[3.9, 4.88, 5.92], [4.05, 4.98, 5.88], [4.12, 5.1, 5.82], [4.15, 5.25, 5.72]]
	var frings: Array = []
	var ffoil := _airfoil(0.1, 0.0, 10)
	for row: Array in fin:
		var y: float = row[0]
		var le: float = row[1]
		var te: float = row[2]
		var chord := te - le
		var tk := 0.35 if y > 4.14 else 1.0
		var r := PackedVector3Array()
		for q in ffoil:
			r.append(Vector3(q.y * minf(chord, 1.6) * tk, y, le + q.x * chord))
		frings.append(r)
	m.grid(frings, _cf(C_CREAM, 0.78), true, true, true)
	# Leitwerksstreben unter dem Hoehenleitwerk
	for sx: float in [-1.0, 1.0]:
		m.strut(Vector3(sx * 0.12, 2.36, 5.05), Vector3(sx * 1.35, 2.53, 5.15), 0.07, 0.025, _cf(C_CREAM, 0.62), 8)


## Schwimmer-Querschnitt bei u (0 Bug .. 1 Heck): [halbe Breite, Deck, Kimm, Kiel]
static func _float_sec(u: float, after_step: bool) -> Array:
	var b := 0.35
	if u < 0.24:
		var k := 1.0 - u / 0.24
		b = 0.04 + 0.31 * (1.0 - k * k)
	elif u > 0.62:
		var k2 := (u - 0.62) / 0.38
		b = 0.35 - 0.15 * k2 * k2
	var yd := 0.5 - 0.06 * (u - 0.15) / 0.85
	if u < 0.15:
		var kb := 1.0 - u / 0.15
		yd = 0.5 + 0.045 * kb * kb
	var yk := -0.27
	if u < 0.28:
		yk = -0.27 + 0.63 * pow(1.0 - u / 0.28, 2.2)
	elif u >= 0.6 and after_step:
		yk = lerpf(-0.18, 0.2, (u - 0.6) / 0.4)
	var yc := maxf(yk + 0.01, minf(yk + 0.12, yd - 0.15))
	return [b, yd, yc, yk]


static func _float_ring(xc: float, z: float, u: float, after_step: bool) -> PackedVector3Array:
	var s := _float_sec(u, after_step)
	var b: float = s[0]
	var yd: float = s[1]
	var yc: float = s[2]
	var yk: float = s[3]
	var half: Array = [Vector2(0.55 * b, yd + 0.025), Vector2(0.92 * b, yd - 0.005), Vector2(b, yd - 0.06),
		Vector2(b, yc + 0.03), Vector2(0.985 * b, yc), Vector2(0.985 * b, yc), Vector2(0.5 * b, lerpf(yc, yk, 0.58)),
		Vector2(0.0, yk), Vector2(0.0, yk)]
	var r := PackedVector3Array()
	r.append(Vector3(xc, yd + 0.035, z))
	for i in range(0, 8):
		var q: Vector2 = half[i]
		r.append(Vector3(xc + q.x, q.y, z))
	r.append(Vector3(xc, yk, z))   # Kiel (doppelt -> harte Kante)
	for i in range(6, -1, -1):
		var q: Vector2 = half[i]
		r.append(Vector3(xc - q.x, q.y, z))
	return r


func _float(m: Mesher, xc: float) -> void:
	var us: Array = [0.0, 0.008, 0.022, 0.022, 0.04, 0.06, 0.09, 0.12, 0.16, 0.2, 0.25, 0.3, 0.38, 0.46, 0.54, 0.6, 0.6]
	var rings: Array = []
	var cols: Array = []
	var alu := _cf(C_ALU, 0.70)
	var rub := _cf(C_DARK, 0.3)
	for i in us.size():
		var u: float = us[i]
		rings.append(_float_ring(xc, FLOAT_Z0 + u * FLOAT_LEN, u, false))
		cols.append(rub if (u < 0.022 or (u == 0.022 and i == 2)) else alu)
	# Stufe
	for u: float in [0.6, 0.6, 0.66, 0.74, 0.82, 0.9, 0.95, 0.985, 1.0]:
		rings.append(_float_ring(xc, FLOAT_Z0 + u * FLOAT_LEN + (0.003 if u == 0.6 else 0.0), u, true))
		cols.append(alu)
	m.grid(rings, cols, true, true, true)
	var sx := signf(xc)
	var zs := FLOAT_Z0 + FLOAT_LEN
	# Wasserruder am Heck
	m.box(Vector3(xc, 0.1, zs + 0.13), Vector3(0.014, 0.46, 0.22), _cf(C_DMETAL, 0.15))
	m.box(Vector3(xc, 0.4, zs + 0.03), Vector3(0.05, 0.05, 0.16), _cf(C_DMETAL, 0.15))
	# Klampen, Deckel, Stossleisten
	for zc: float in [-3.0, -0.6, 2.2]:
		var u2 := (zc - FLOAT_Z0) / FLOAT_LEN
		var sec := _float_sec(u2, u2 > 0.6)
		var yd: float = sec[1]
		var bb: float = sec[0]
		for side: float in [-1.0, 1.0]:
			m.box(Vector3(xc + side * (bb - 0.03), yd + 0.02, zc), Vector3(0.04, 0.035, 0.16), _cf(C_DMETAL, 0.15))
	for zc: float in [-3.4, -2.1, -0.6, 1.2, 2.5]:
		var u3 := (zc - FLOAT_Z0) / FLOAT_LEN
		var yd3: float = _float_sec(u3, u3 > 0.6)[1]
		m.lathe(Vector3(xc, yd3 + 0.03, zc), Vector3.UP, [Vector2(0, 0.085), Vector2(0.012, 0.085), Vector2(0.012, 0.0)], 14, _cf(C_ALU, 0.5))
	# Stossleiste aussen entlang der Kimm (Gummi)
	var rail: Array = []
	for k in 13:
		var u4 := lerpf(0.12, 0.95, float(k) / 12.0)
		var sec4 := _float_sec(u4, u4 > 0.6)
		var b4: float = sec4[0]
		var y4: float = float(sec4[1]) - 0.06
		var p := Vector3(xc + sx * (b4 + 0.008), y4, FLOAT_Z0 + u4 * FLOAT_LEN)
		rail.append(p)
	for k in rail.size() - 1:
		m.tube(rail[k], rail[k + 1], 0.016, 6, _cf(C_DARK, 0.3))


func _struts(m: Mesher) -> void:
	var paint := _cf(C_CREAM, 0.62)
	var dk := _cf(C_DMETAL, 0.15)
	for sx: float in [-1.0, 1.0]:
		var fx := sx * FLOAT_X
		# Schwimmergestell
		m.strut(Vector3(fx, 0.5, -1.75), Vector3(sx * 0.5, 1.37, -1.95), 0.11, 0.04, paint)
		m.strut(Vector3(fx, 0.48, 0.45), Vector3(sx * 0.5, 1.38, 0.35), 0.11, 0.04, paint)
		m.strut(Vector3(fx, 0.5, -1.62), Vector3(sx * 0.52, 1.38, 0.2), 0.08, 0.03, paint)
		# Flaechenstreben (V)
		var wy := WING_Y + 4.55 * 0.026 - 0.06
		m.strut(Vector3(sx * 0.6, 1.42, -1.2), Vector3(sx * 4.55, wy, -1.38), 0.12, 0.04, paint)
		m.strut(Vector3(sx * 0.6, 1.42, -1.02), Vector3(sx * 4.55, wy, -0.45), 0.12, 0.04, paint)
		m.strut(Vector3(sx * 2.6, 1.42 + (wy - 1.42) * 0.5, -1.27), Vector3(sx * 2.6, WING_Y + 2.6 * 0.026 - 0.05, -1.0), 0.05, 0.02, paint, 8)
		# Spanndraehte
		m.tube(Vector3(fx, 0.55, -1.75), Vector3(-sx * 0.48, 1.36, -1.95), 0.006, 4, dk)
		m.tube(Vector3(fx, 0.53, 0.45), Vector3(-sx * 0.48, 1.37, 0.35), 0.006, 4, dk)
	# Spreizstangen zwischen den Schwimmern
	m.strut(Vector3(-FLOAT_X, 0.54, -1.75), Vector3(FLOAT_X, 0.54, -1.75), 0.1, 0.035, paint)
	m.strut(Vector3(-FLOAT_X, 0.52, 0.45), Vector3(FLOAT_X, 0.52, 0.45), 0.1, 0.035, paint)
	# Trittstufe am hinteren linken Schwimmerbein
	m.box(Vector3(-0.92, 0.95, 0.4), Vector3(0.24, 0.025, 0.16), _cf(C_DARK, 0.3))


## Kollision fuer die Flaechenstreben (V-Streben + Hilfsstrebe) beider Seiten: die linken ragen
## ueber den Steg und muessen den Spieler aufhalten. Haengt an "body", schaukelt/rollt also mit.
func _build_collision() -> void:
	var sb := StaticBody3D.new()
	sb.name = "StrutCollision"
	body.add_child(sb)
	var wy := WING_Y + 4.55 * 0.026 - 0.06
	for sx: float in [-1.0, 1.0]:
		_capsule(sb, Vector3(sx * 0.6, 1.42, -1.2), Vector3(sx * 4.55, wy, -1.38), 0.08)
		_capsule(sb, Vector3(sx * 0.6, 1.42, -1.02), Vector3(sx * 4.55, wy, -0.45), 0.08)
		_capsule(sb, Vector3(sx * 2.6, 1.42 + (wy - 1.42) * 0.5, -1.27), Vector3(sx * 2.6, WING_Y + 2.6 * 0.026 - 0.05, -1.0), 0.05)


func _capsule(parent: Node3D, a: Vector3, b: Vector3, r: float) -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = a.distance_to(b) + 2.0 * r
	cs.shape = cap
	# Kapsel-Achse = lokale Y-Achse -> auf die Strebe ausrichten
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	cs.transform = Transform3D(Basis(side, up, side.cross(up)).orthonormalized(), (a + b) * 0.5)
	parent.add_child(cs)


func _details(m: Mesher) -> void:
	var dk := _cf(C_DARK, 0.3)
	var alu := _cf(C_ALU, 0.5)
	# Antennenmast und Draht zum Seitenleitwerk
	m.strut(Vector3(0, 2.8, 1.1), Vector3(0, 3.1, 1.25), 0.06, 0.015, dk, 8)
	m.tube(Vector3(0, 3.08, 1.25), Vector3(0, 4.0, 4.95), 0.003, 4, dk)
	# Tuergriffe
	for sx: float in [-1.0, 1.0]:
		var gx := sx * (_fus_x(0.6, 2.0) + 0.012)
		if sx > 0.0:
			m.box(Vector3(gx, 2.0, 0.6), Vector3(0.025, 0.03, 0.14), alu)
		var px := sx * (_fus_x(-0.62, 2.0) + 0.012)
		m.box(Vector3(px, 2.0, -0.62), Vector3(0.025, 0.03, 0.14), alu)
	# Scheibenmittelstrebe aussen
	m.tube(Vector3(0, 2.58, -2.02), Vector3(0, 2.82, -1.62), 0.012, 6, dk)
	# Heck-Festmacheroese, Schleifsporn
	m.box(Vector3(0, 2.52, 5.6), Vector3(0.03, 0.08, 0.1), alu)

# ------------------------------------------------------------------ Tuer

func _build_door() -> void:
	door = Node3D.new()
	door.name = "CabinDoor"
	door.position = DOOR_HINGE
	body.add_child(door)
	var cols := 14
	var rows := 18
	var rings: Array = []
	for i in cols + 1:
		var z := lerpf(-0.36, 0.72, float(i) / float(cols))
		var r := PackedVector3Array()
		for j in rows + 1:
			var y := lerpf(1.39, 2.69, float(j) / float(rows))
			var x := -(_fus_x(z, y) + 0.003)
			r.append(Vector3(x, y, z) - DOOR_HINGE)
		rings.append(r)
	for pass_i in 2:
		var m := Mesher.new()
		m.grid(rings, _cf(C_CREAM, 0.95), false, false, false, Vector3(-1, 0, 0))
		var mi := _emit(door, m, _paint if pass_i == 0 else _glass, "DoorSkin" if pass_i == 0 else "DoorGlass", pass_i == 0)
		mi.set_instance_shader_parameter("part_offset", DOOR_HINGE)
	var hm := Mesher.new()
	hm.box(Vector3(-0.015, 0.0, 0.92) + Vector3(-(_fus_x(0.6, 2.0) + 0.012) - DOOR_HINGE.x, 2.0 - DOOR_HINGE.y, 0.6 - DOOR_HINGE.z - 0.92), Vector3(0.025, 0.03, 0.14), _cf(C_ALU, 0.5))
	var hmi := _emit(door, hm, _paint, "DoorHandle")
	hmi.set_instance_shader_parameter("part_offset", DOOR_HINGE)

# ------------------------------------------------------------------ Propeller

func _build_prop() -> void:
	prop = Node3D.new()
	prop.name = "Propeller"
	prop.position = PROP_POS
	body.add_child(prop)
	var m := Mesher.new()
	# Spinner + Nabe
	m.lathe(Vector3(0, 0, 0.06), Vector3(0, 0, -1), [Vector2(0, 0.0), Vector2(0, 0.17), Vector2(0, 0.17), Vector2(0.12, 0.165),
		Vector2(0.24, 0.13), Vector2(0.33, 0.07), Vector2(0.37, 0.0)], 24, _cf(C_ALU, 0.5))
	# Zwei Blaetter: verwunden, Spitzen gelb
	var rs: Array = [0.12, 0.2, 0.32, 0.5, 0.72, 0.94, 1.12, 1.2, 1.2, 1.26, 1.3]
	var cs: Array = [0.09, 0.15, 0.2, 0.215, 0.205, 0.185, 0.155, 0.14, 0.14, 0.12, 0.07]
	var foil := _airfoil(0.11, 0.03, 6)
	for b in 2:
		var rot := Basis(Vector3(0, 0, 1), PI * float(b))
		var rings: Array = []
		var cols: Array = []
		for i in rs.size():
			var r: float = rs[i]
			var c: float = cs[i]
			var beta := atan(1.7 / (TAU * maxf(r, 0.2)))
			var cd := Vector3(0, cos(beta), sin(beta))
			var td := Vector3(0, -sin(beta), cos(beta))
			var tk := 1.0 + 3.0 * maxf(0.0, (0.3 - r) / 0.18)
			var ring := PackedVector3Array()
			for q in foil:
				ring.append(rot * (Vector3(r, 0, 0) + cd * (q.x - 0.4) * c - td * q.y * c * tk))
			rings.append(ring)
			cols.append(_cf(C_YELLOW, 0.3) if i >= 8 else _cf(Color(0.03, 0.03, 0.03), 0.3))
		m.grid(rings, cols, true, false, true)
	_blades = _emit(prop, m, _paint, "Blades")
	# Bewegungsunschaerfe-Scheibe (dreht nicht mit)
	_disc_mat = ShaderMaterial.new()
	_disc_mat.shader = FX_SH
	_disc_mat.set_shader_parameter("mode", 0)
	_disc_mat.set_shader_parameter("radius", PROP_R)
	_disc_mat.set_shader_parameter("noise_tex", _noise)
	_disc_mat.render_priority = 2
	var dm := Mesher.new()
	var ring := PackedVector3Array()
	for j in 48:
		var a := TAU * float(j) / 48.0
		ring.append(Vector3(cos(a), sin(a), 0.0) * PROP_R)
	dm.cap(ring, Vector3.ZERO, Vector3(0, 0, -1), Color.WHITE)
	_disc = _emit(body, dm, _disc_mat, "PropDisc", false)
	_disc.position = PROP_POS + Vector3(0, 0, -0.02)
	_disc.visible = false

# ------------------------------------------------------------------ Kabine

func _build_interior() -> void:
	var m := Mesher.new()
	var seat := Color(0.08, 0.06, 0.045)
	var dk := Color(0.03, 0.03, 0.032)
	m.box(Vector3(0, 1.43, -0.7), Vector3(1.18, 0.04, 2.2), Color(0.05, 0.05, 0.05))
	m.box(Vector3(0, 1.46, 0.85), Vector3(0.95, 0.04, 0.9), Color(0.05, 0.05, 0.05))
	# Instrumentenbrett mit Blendschutz, Steuerhoerner
	m.box(Vector3(0, 2.2, -1.82), Vector3(1.15, 0.36, 0.08), dk)
	m.box(Vector3(0, 2.4, -1.74), Vector3(1.15, 0.03, 0.22), dk)
	for sx: float in [-0.3, 0.3]:
		m.box(Vector3(sx, 2.05, -1.6), Vector3(0.025, 0.025, 0.4), dk)
		m.box(Vector3(sx, 2.08, -1.42), Vector3(0.24, 0.05, 0.03), dk)
	# Vordersitze, Mittelbank, Rueckbank
	for row: Array in [[-0.95, [-0.3, 0.3], 0.44], [0.08, [0.0], 1.05], [1.0, [0.0], 0.95]]:
		var z: float = row[0]
		var w: float = row[2]
		for sx: float in row[1]:
			m.box(Vector3(sx, 1.68, z), Vector3(w, 0.12, 0.46), seat)
			m.box(Vector3(sx, 2.02, z + 0.26), Vector3(w, 0.62, 0.09), seat, Basis(Vector3.RIGHT, deg_to_rad(-10.0)))
			if w < 0.5:
				m.box(Vector3(sx, 2.42, z + 0.31), Vector3(0.26, 0.18, 0.08), seat)
			m.box(Vector3(sx, 1.53, z), Vector3(w * 0.8, 0.18, 0.3), dk)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.82
	_emit(body, m, mat, "Interior", false)

# ------------------------------------------------------------------ Lichter, Kennzeichen

func _light_mat(c: Color, e: float) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = c.darkened(0.6)
	mt.emission_enabled = true
	mt.emission = c
	mt.emission_energy_multiplier = e
	mt.roughness = 0.2
	return mt


func _build_lights() -> void:
	var tip_y := WING_Y + HALF_SPAN * 0.026
	for d: Array in [[-1.0, Color(1.0, 0.08, 0.04)], [1.0, Color(0.1, 1.0, 0.25)]]:
		var m := Mesher.new()
		var sx: float = d[0]
		m.lathe(Vector3(sx * (HALF_SPAN - 0.02), tip_y, -1.5), Vector3(sx, 0, 0), [Vector2(0, 0.035), Vector2(0.03, 0.03), Vector2(0.045, 0.0)], 10, Color.WHITE)
		_emit(body, m, _light_mat(d[1], 2.0), "NavLight", false)
	var tm := Mesher.new()
	tm.lathe(Vector3(0, 2.6, 5.96), Vector3(0, 0, 1), [Vector2(0, 0.03), Vector2(0.03, 0.025), Vector2(0.04, 0.0)], 10, Color.WHITE)
	_emit(body, tm, _light_mat(Color(1, 0.95, 0.85), 1.2), "TailLight", false)
	var bm := Mesher.new()
	bm.lathe(Vector3(0, 4.13, 5.4), Vector3.UP, [Vector2(0, 0.045), Vector2(0.04, 0.04), Vector2(0.07, 0.0)], 10, Color.WHITE)
	_beacon_mat = _light_mat(Color(1.0, 0.1, 0.05), 0.2)
	_emit(body, bm, _beacon_mat, "Beacon", false)


func _build_labels() -> void:
	for sx: float in [-1.0, 1.0]:
		var l := Label3D.new()
		l.name = "Registration"
		l.text = REGISTRATION
		l.font_size = 72
		l.pixel_size = 0.0032
		l.outline_size = 0
		l.modulate = Color(0.1, 0.09, 0.1)
		l.shaded = true
		l.double_sided = false
		l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var z := 2.75
		var y := 2.16
		var x := _fus_x(z, y) + 0.006
		var slope := atan((_fus_x(z + 0.3, y) - _fus_x(z - 0.3, y)) / 0.6)
		l.position = Vector3(sx * x, y, z)
		l.rotation = Vector3(0.0, sx * (PI * 0.5) + sx * slope * 0.0 - slope * 1.0 * sx * -1.0, 0.0)
		l.rotation.y = sx * PI * 0.5 + slope * sx
		body.add_child(l)

# ------------------------------------------------------------------ Wasser

func _build_wake() -> void:
	_wake_mat = ShaderMaterial.new()
	_wake_mat.shader = FX_SH
	_wake_mat.set_shader_parameter("mode", 1)
	_wake_mat.set_shader_parameter("noise_tex", _noise)
	_wake_mat.set_shader_parameter("float_x", FLOAT_X)
	_wake_mat.set_shader_parameter("bow_z", FLOAT_Z0)
	_wake_mat.set_shader_parameter("stern_z", FLOAT_Z0 + FLOAT_LEN - 0.3)
	var m := Mesher.new()
	var rings: Array = []
	for z: float in [-5.2, -3.0, 0.0, 4.0, 10.0, 20.0, 34.0]:
		var hw := 1.9 + maxf(z + 4.6, 0.0) * 0.37
		var r := PackedVector3Array()
		for k in 9:
			r.append(Vector3(lerpf(-hw, hw, float(k) / 8.0), 0.0, z))
		rings.append(r)
	m.grid(rings, Color.WHITE, false, false, false, Vector3.UP)
	_wake = _emit(self, m, _wake_mat, "Wake", false)
	_wake.top_level = true
	_wake.visible = false


func _soft_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	return gt


func _particles(nm: String, pos: Vector3, amount: int, life: float, dir: Vector3, vel: Vector2, size: float, col: Color, grav: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = nm
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.position = pos
	p.visibility_aabb = AABB(Vector3(-8, -3, -8), Vector3(16, 8, 30))
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir.normalized()
	pm.spread = 22.0
	pm.initial_velocity_min = vel.x
	pm.initial_velocity_max = vel.y
	pm.gravity = Vector3(0, grav, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.5
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var gr := Gradient.new()
	gr.set_color(0, Color(col.r, col.g, col.b, col.a))
	gr.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var grt := GradientTexture1D.new()
	grt.gradient = gr
	pm.color_ramp = grt
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.08, 0.04, 0.25)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mt := StandardMaterial3D.new()
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.vertex_color_use_as_albedo = true
	mt.albedo_texture = _soft_tex()
	mt.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mt.billboard_keep_scale = true
	mt.disable_receive_shadows = true
	q.material = mt
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(p)
	return p


func _build_particles() -> void:
	for sx: float in [-1.0, 1.0]:
		var bow_z := FLOAT_Z0 + 0.75
		_spray.append(_particles("Spray", Vector3(sx * (FLOAT_X + 0.25), 0.05, bow_z), 70, 0.8,
			Vector3(sx * 1.0, 0.9, 0.55), Vector2(1.5, 3.5), 0.3, Color(0.62, 0.65, 0.7, 0.55), -7.0))
		_spray.append(_particles("SprayStern", Vector3(sx * FLOAT_X, 0.0, FLOAT_Z0 + FLOAT_LEN - 0.2), 20, 1.1,
			Vector3(sx * 0.2, 0.5, 1.0), Vector2(1.0, 2.5), 0.6, Color(0.6, 0.63, 0.68, 0.35), -6.0))
	_wash_spray = _particles("PropWash", Vector3(0, 0.05, -1.0), 28, 1.2, Vector3(0, 0.35, 1.0), Vector2(3.0, 6.0), 0.9, Color(0.6, 0.63, 0.68, 0.22), -2.0)
	_exhaust = _particles("Exhaust", Vector3(0.6, 1.46, -2.02), 18, 1.6, Vector3(0.3, 0.1, 1.0), Vector2(0.6, 1.4), 0.35, Color(0.2, 0.2, 0.21, 0.35), 0.4)

# ------------------------------------------------------------------ Festmacher

func _build_ropes() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.47, 0.36)
	mat.roughness = 0.9
	for mo: Array in MOORINGS:
		var mi := MeshInstance3D.new()
		mi.name = "Rope"
		mi.top_level = true
		mi.material_override = mat
		mi.mesh = ArrayMesh.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_ropes.append({"mi": mi, "a": mo[0], "b": mo[1], "end": Vector3.ZERO})


func _update_ropes(delta: float) -> void:
	if _ropes.is_empty():
		return
	if _cast:
		_cast_t += delta
	var gp := global_position
	var far := Vector2(gp.x + 5.1, gp.z + 60.0).length() > 60.0
	for rp: Dictionary in _ropes:
		var mi: MeshInstance3D = rp["mi"]
		if far:
			mi.visible = false
			continue
		mi.visible = true
		var b: Vector3 = rp["b"]
		var a := body.to_global(rp["a"])
		var sag := 0.18
		if _cast:
			# Leine faellt vom Schwimmer ins Wasser neben dem Steg
			var k := clampf(_cast_t / 1.1, 0.0, 1.0)
			var drop := b + Vector3(0.3, WATER_Y - b.y - 0.02, 0.6 if b.z > -62.0 else -0.6)
			if k <= 0.0001:
				rp["end"] = a
			var start: Vector3 = rp["end"] if rp["end"] != Vector3.ZERO else a
			a = start.lerp(drop, k * k)
			sag = lerpf(0.18, 0.05, k)
			if k >= 1.0:
				rp["end"] = drop
		else:
			rp["end"] = a
		_rope_mesh(mi, b, a, sag)


func _rope_mesh(mi: MeshInstance3D, a: Vector3, b: Vector3, sag: float) -> void:
	var m := Mesher.new()
	var rings: Array = []
	var segs := 12
	var r := 0.013
	for i in segs + 1:
		var t := float(i) / float(segs)
		var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t) * a.distance_to(b) * 0.35, 0)
		var t2 := minf(t + 0.05, 1.0)
		var t1 := maxf(t - 0.05, 0.0)
		var p2 := a.lerp(b, t2) - Vector3(0, sag * 4.0 * t2 * (1.0 - t2) * a.distance_to(b) * 0.35, 0)
		var p1 := a.lerp(b, t1) - Vector3(0, sag * 4.0 * t1 * (1.0 - t1) * a.distance_to(b) * 0.35, 0)
		var d := (p2 - p1).normalized()
		var u := d.cross(Vector3.UP)
		if u.length_squared() < 1e-6:
			u = Vector3.RIGHT
		u = u.normalized()
		var w := d.cross(u).normalized()
		var ring := PackedVector3Array()
		for j in 6:
			var an := TAU * float(j) / 6.0
			ring.append(p + (u * cos(an) + w * sin(an)) * r)
		rings.append(ring)
	m.grid(rings, Color.WHITE, true)
	mi.mesh = m.commit()
