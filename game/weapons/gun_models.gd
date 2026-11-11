class_name GunModels
extends RefCounted
## Prozedurale Waffenmodelle (G36C, Panzerfaust 3, Holo-Visier, Munitionskisten) und Materialien.
## Alle Masse in Metern, Lauf entlang -Z, rechts = +X. Benannte Teile fuer die Animation:
## "Magazine" (Magazin bzw. Gefechtskopf) und "Charging_Handle" (Spannhebel).
## Die Modelle werden sowohl als Viewmodel (Layer 20) als auch als Pickup in der Welt benutzt.
##
## Bauweise: Seitenprofile mit abgerundeten Ecken werden mit runder Fase extrudiert (extrude),
## Drehkoerper per lathe; alle Teile tragen Vertexfarben (R = Kante fuer Abnutzung, G = Hohlraum/AO).
## Pro Gruppe und Material wird zu EINEM Mesh zusammengefasst (wenige Draw-Calls) und als Vorlage
## gecacht – jedes weitere Modell (Pickup, Drop) teilt sich die Meshes.
## Material: gun_surface.gdshader (objektraum-triplanare Mikrostruktur + Kantenabnutzung, ohne UVs).

const AK_PATH: String = "res://assets/weapons/ak47/ak47.glb"
const PISTOL_PATH: String = "res://assets/weapons/service_pistol/service_pistol.glb"   # Poly Haven, CC0
const SURFACE_SHADER: Shader = preload("res://game/weapons/gun_surface.gdshader")

static var _mats: Dictionary = {}
static var _mesh_cache: Dictionary = {}
static var _templates: Dictionary = {}

# ------------------------------------------------------------------ Materialien

static func _noise_tex(freq: float, seed_v: int, normal: bool = false, octaves: int = 4) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = freq
	noise.fractal_octaves = octaves
	noise.seed = seed_v
	var nt := NoiseTexture2D.new()
	nt.noise = noise
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.generate_mipmaps = true
	if normal:
		nt.as_normal_map = true
		nt.bump_strength = 6.0
	return nt

## Shader-Material fuer Waffen-Oberflaechen.
static func _surf(base: Color, wear: Color, metal: float, metal_wear: float, rough: float, rough_wear: float,
		wear_amt: float, micro: float, bump: float, extra: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SURFACE_SHADER
	m.set_shader_parameter("noise_tex", _mats["_n"])
	m.set_shader_parameter("noise_nrm", _mats["_nn"])
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("wear_color", wear)
	m.set_shader_parameter("metallic_base", metal)
	m.set_shader_parameter("metallic_wear", metal_wear)
	m.set_shader_parameter("roughness_base", rough)
	m.set_shader_parameter("roughness_wear", rough_wear)
	m.set_shader_parameter("wear_amount", wear_amt)
	m.set_shader_parameter("micro_scale", micro)
	m.set_shader_parameter("bump_strength", bump)
	for k: String in extra:
		m.set_shader_parameter(k, extra[k])
	return m

static func _std(col: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	return m

static func mat(key: String) -> Material:
	if _mats.is_empty():
		_init_mats()
	return _mats.get(key, _mats["park"])

static func _init_mats() -> void:
	_mats["_n"] = _noise_tex(0.035, 7, false, 5)
	_mats["_nn"] = _noise_tex(0.11, 3, true, 3)
	# G36: schwarz-anthrazites, fein strukturiertes Polymer; Kanten glaenzen grauer (abgegriffen)
	_mats["poly"] = _surf(Color(0.045, 0.047, 0.046), Color(0.19, 0.19, 0.185), 0.0, 0.0, 0.66, 0.4, 0.6, 7.0, 0.22,
		{"dirt_amount": 0.18, "color_var": 0.1, "specular_level": 0.4})
	_mats["poly_grip"] = _surf(Color(0.05, 0.052, 0.05), Color(0.12, 0.12, 0.118), 0.0, 0.0, 0.72, 0.45, 0.4, 16.0, 0.75,
		{"dirt_amount": 0.25})
	_mats["poly_dark"] = _surf(Color(0.026, 0.027, 0.026), Color(0.05, 0.05, 0.05), 0.0, 0.0, 0.78, 0.6, 0.1, 8.0, 0.2,
		{"ao_strength": 0.9})
	# Schwarz eloxiertes Aluminium (Schiene, Visier): Kanten blank
	_mats["anod"] = _surf(Color(0.042, 0.044, 0.048), Color(0.62, 0.62, 0.64), 0.45, 1.0, 0.38, 0.22, 0.65, 5.0, 0.1,
		{"clearcoat_amount": 0.2, "dirt_amount": 0.12})
	# Parkerisierter Stahl (Lauf, Stifte, Feuerdaempfer)
	_mats["park"] = _surf(Color(0.085, 0.086, 0.088), Color(0.48, 0.48, 0.5), 0.7, 1.0, 0.5, 0.24, 0.5, 9.0, 0.3,
		{"dirt_amount": 0.2})
	_mats["steel"] = _surf(Color(0.36, 0.36, 0.37), Color(0.62, 0.62, 0.63), 1.0, 1.0, 0.32, 0.18, 0.4, 9.0, 0.15)
	_mats["bore"] = _surf(Color(0.008, 0.008, 0.008), Color(0.02, 0.02, 0.02), 0.3, 0.3, 0.6, 0.6, 0.0, 6.0, 0.0)
	_mats["rubber"] = _surf(Color(0.03, 0.03, 0.03), Color(0.06, 0.06, 0.058), 0.0, 0.0, 0.86, 0.7, 0.2, 18.0, 0.6,
		{"specular_level": 0.35})
	_mats["brass"] = _surf(Color(0.78, 0.57, 0.27), Color(0.92, 0.75, 0.45), 1.0, 1.0, 0.26, 0.16, 0.3, 12.0, 0.08,
		{"color_var": 0.18, "dirt_amount": 0.0})
	_mats["copper"] = _surf(Color(0.66, 0.36, 0.22), Color(0.85, 0.55, 0.38), 1.0, 1.0, 0.3, 0.2, 0.3, 12.0, 0.05,
		{"dirt_amount": 0.0})
	# Transluzentes Magazin (rauchig), Patronen scheinen durch
	var mag := StandardMaterial3D.new()
	mag.albedo_color = Color(0.24, 0.21, 0.16, 0.6)
	mag.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mag.roughness = 0.22
	mag.metallic_specular = 0.7
	mag.rim_enabled = true
	mag.rim = 0.35
	mag.rim_tint = 0.6
	mag.clearcoat_enabled = true
	mag.clearcoat = 0.4
	mag.clearcoat_roughness = 0.15
	_mats["mag_clear"] = mag
	var rib := mag.duplicate() as StandardMaterial3D
	rib.albedo_color = Color(0.09, 0.085, 0.075, 0.9)
	_mats["mag_rib"] = rib
	# Panzerfaust: Oliv lackiert (Abrieb zu dunklem Metall), Kunststoff dunkler, Gefechtskopf
	_mats["olive"] = _surf(Color(0.2, 0.225, 0.13), Color(0.2, 0.2, 0.19), 0.0, 0.85, 0.66, 0.35, 0.45, 4.0, 0.25,
		{"dirt_amount": 0.35, "dirt_color": Color(0.24, 0.21, 0.15), "color_var": 0.14})
	_mats["olive_dark"] = _surf(Color(0.105, 0.12, 0.08), Color(0.22, 0.23, 0.19), 0.0, 0.0, 0.64, 0.42, 0.45, 9.0, 0.3,
		{"dirt_amount": 0.08, "color_var": 0.05})
	_mats["olive_head"] = _surf(Color(0.24, 0.25, 0.155), Color(0.26, 0.26, 0.25), 0.0, 0.9, 0.58, 0.3, 0.35, 4.0, 0.2,
		{"dirt_amount": 0.25, "clearcoat_amount": 0.15})
	_mats["yellow"] = _surf(Color(0.72, 0.56, 0.09), Color(0.3, 0.28, 0.2), 0.0, 0.6, 0.55, 0.4, 0.4, 5.0, 0.15)
	_mats["sand"] = _mats["olive_head"]
	# Kisten: oliv lackiertes Holz (Abrieb zeigt Holz), Beschlaege
	_mats["crate_wood"] = _surf(Color(0.27, 0.3, 0.17), Color(0.36, 0.27, 0.16), 0.0, 0.0, 0.8, 0.7, 0.6, 2.2, 0.6,
		{"dirt_amount": 0.45, "dirt_color": Color(0.2, 0.17, 0.12), "color_var": 0.22, "ao_strength": 0.7})
	_mats["crate_dark"] = _surf(Color(0.18, 0.2, 0.115), Color(0.3, 0.23, 0.14), 0.0, 0.0, 0.82, 0.7, 0.55, 2.2, 0.55,
		{"dirt_amount": 0.45, "color_var": 0.2})
	_mats["crate_metal"] = _surf(Color(0.1, 0.105, 0.09), Color(0.45, 0.44, 0.42), 0.6, 1.0, 0.55, 0.3, 0.55, 6.0, 0.35,
		{"dirt_amount": 0.4, "dirt_color": Color(0.25, 0.16, 0.09)})
	_mats["can_olive"] = _surf(Color(0.17, 0.19, 0.11), Color(0.35, 0.35, 0.34), 0.2, 1.0, 0.6, 0.3, 0.55, 5.0, 0.2,
		{"dirt_amount": 0.3})
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color(0.25, 0.32, 0.36, 0.14)
	lens.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lens.metallic = 0.6
	lens.roughness = 0.05
	_mats["lens"] = lens
	var lens_blue := StandardMaterial3D.new()
	lens_blue.albedo_color = Color(0.12, 0.2, 0.35, 0.55)
	lens_blue.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lens_blue.metallic = 0.9
	lens_blue.roughness = 0.04
	lens_blue.rim_enabled = true
	lens_blue.rim = 0.6
	_mats["lens_coated"] = lens_blue
	var ret := StandardMaterial3D.new()
	ret.albedo_color = Color(0.02, 0.02, 0.02)
	ret.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats["reticle"] = ret
	# AK-74M (CC0-Modell mit eigenen UVs): brueniertes Metall, schwarzes Polymer, pflaumenfarbenes Magazin
	var n1 := _noise_tex(0.06, 17)
	var n2 := _noise_tex(0.18, 11)
	_mats["ak_metal_std"] = _ak_pbr(Color(0.075, 0.075, 0.08), 0.8, 0.42, n1, 5.0)
	_mats["ak_poly_std"] = _ak_pbr(Color(0.04, 0.04, 0.042), 0.0, 0.66, n2, 9.0)
	_mats["ak_mag_std"] = _ak_pbr(Color(0.3, 0.12, 0.07), 0.0, 0.5, n2, 9.0)
	# Wie G36: gun_surface-Shader (Kantenmaske wird in build_ak aus den Normalen gebacken)
	_mats["ak_metal"] = _surf(Color(0.062, 0.062, 0.066), Color(0.44, 0.44, 0.46), 0.75, 1.0, 0.46, 0.24, 0.6, 9.0, 0.28,
		{"dirt_amount": 0.22, "color_var": 0.1})
	_mats["ak_poly"] = _surf(Color(0.038, 0.038, 0.04), Color(0.15, 0.15, 0.148), 0.0, 0.0, 0.64, 0.42, 0.5, 8.0, 0.24,
		{"dirt_amount": 0.2, "color_var": 0.08, "specular_level": 0.4})
	_mats["ak_mag"] = _surf(Color(0.25, 0.095, 0.055), Color(0.42, 0.24, 0.15), 0.0, 0.0, 0.52, 0.36, 0.5, 8.0, 0.2,
		{"dirt_amount": 0.25, "color_var": 0.12})
	_mats["metal"] = _mats["park"]
	_mats["metal_worn"] = _mats["steel"]

static func _ak_pbr(col: Color, metal: float, rough: float, rough_noise: NoiseTexture2D, tri_scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness_texture = rough_noise
	m.roughness = minf(rough * 1.45, 1.0)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * tri_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

# ------------------------------------------------------------------ Geometrie-Helfer

static func _p2(v: Variant) -> Vector2:
	if v is Vector3:
		return Vector2((v as Vector3).x, (v as Vector3).y)
	return v as Vector2

## Ecken abrunden (quadratische Bezier). Punkte: Vector2 oder Vector3(x, y, eigener Radius).
static func rounded(pts: Array, r: float, closed: bool = true, segs: int = 3) -> PackedVector2Array:
	var n: int = pts.size()
	var out := PackedVector2Array()
	for i in n:
		var p1: Vector2 = _p2(pts[i])
		var rr: float = (pts[i] as Vector3).z if pts[i] is Vector3 else r
		if rr <= 0.0 or (not closed and (i == 0 or i == n - 1)):
			_push(out, p1)
			continue
		var p0: Vector2 = _p2(pts[(i - 1 + n) % n])
		var p2: Vector2 = _p2(pts[(i + 1) % n])
		var d0: float = p0.distance_to(p1)
		var d2: float = p2.distance_to(p1)
		var d: float = minf(rr, minf(d0, d2) * 0.48)
		if d < 1e-5:
			_push(out, p1)
			continue
		var a: Vector2 = p1 + (p0 - p1) / d0 * d
		var c: Vector2 = p1 + (p2 - p1) / d2 * d
		for k in segs + 1:
			var t: float = float(k) / float(segs)
			_push(out, a.lerp(p1, t).lerp(p1.lerp(c, t), t))
	if closed and out.size() > 2 and out[0].distance_to(out[out.size() - 1]) < 1e-5:
		out.remove_at(out.size() - 1)
	return out

static func _push(arr: PackedVector2Array, p: Vector2) -> void:
	if arr.is_empty() or arr[arr.size() - 1].distance_to(p) > 1e-5:
		arr.append(p)

## Offene Linie mit Breite w als geschlossenes Profil (Streben, Buegel, Hebel).
static func stroke(pts: Array, w: float) -> PackedVector2Array:
	var n: int = pts.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in n:
		var p: Vector2 = _p2(pts[i])
		var e0: Vector2 = (p - _p2(pts[maxi(i - 1, 0)])).normalized() if i > 0 else Vector2.ZERO
		var e1: Vector2 = (_p2(pts[mini(i + 1, n - 1)]) - p).normalized() if i < n - 1 else Vector2.ZERO
		var t: Vector2 = (e0 + e1).normalized()
		var nn := Vector2(-t.y, t.x)
		var sc: float = 1.0
		if i > 0 and i < n - 1:
			sc = 1.0 / maxf(nn.dot(Vector2(-e0.y, e0.x)), 0.5)
		left.append(p + nn * w * 0.5 * sc)
		right.append(p - nn * w * 0.5 * sc)
	right.reverse()
	left.append_array(right)
	return left

static func _signed_area(p: PackedVector2Array) -> float:
	var s: float = 0.0
	for i in p.size():
		var a: Vector2 = p[i]
		var c: Vector2 = p[(i + 1) % p.size()]
		s += a.x * c.y - c.x * a.y
	return s * 0.5

static func _in_normal(a: Vector2, c: Vector2) -> Vector2:
	var e: Vector2 = (c - a).normalized()
	return Vector2(-e.y, e.x)

static func _v3(p: Vector2, x: float) -> Vector3:
	return Vector3(x, p.y, p.x)

## Dreieck mit Vertex-Normalen und -Farben; Reihenfolge wird an der Normalen ausgerichtet.
static func _tri3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	var fn: Vector3 = (b - a).cross(c - a)
	if fn.length_squared() < 1e-16:
		return
	if fn.dot(na + nb + nc) > 0.0:
		var tv: Vector3 = b
		b = c
		c = tv
		var tn: Vector3 = nb
		nb = nc
		nc = tn
		var tc: Color = cb
		cb = cc
		cc = tc
	st.set_normal(na)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(nb)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.set_color(cc)
	st.add_vertex(c)

static func _quad3(st: SurfaceTool, v: Array, nr: Array, cl: Array) -> void:
	_tri3(st, v[0], v[1], v[2], nr[0], nr[1], nr[2], cl[0], cl[1], cl[2])
	_tri3(st, v[0], v[2], v[3], nr[0], nr[2], nr[3], cl[0], cl[2], cl[3])

## Seitenprofil (Punkte Vector2(z, y)) in X extrudiert (Breite 2*half_w), mit runder Fase.
static func extrude(profile: PackedVector2Array, half_w: float, bevel: float, bsegs: int = 2) -> ArrayMesh:
	var pts := PackedVector2Array()
	for p in profile:
		_push(pts, p)
	if pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) < 1e-5:
		pts.remove_at(pts.size() - 1)
	if _signed_area(pts) < 0.0:
		pts.reverse()
	var n: int = pts.size()
	var b: float = clampf(bevel, 0.0, half_w * 0.9)
	var segs: int = bsegs if b > 1e-5 else 0
	var en: Array[Vector2] = []
	for i in n:
		en.append(_in_normal(pts[i], pts[(i + 1) % n]))
	var miter: Array[Vector2] = []
	var vavg: Array[Vector2] = []
	var smooth: Array[bool] = []
	var vedge := PackedFloat32Array()
	var vcav := PackedFloat32Array()
	for i in n:
		var n1: Vector2 = en[(i - 1 + n) % n]
		var n2: Vector2 = en[i]
		var m: Vector2 = (n1 + n2).normalized()
		if m.length_squared() < 0.5:
			m = n2
		miter.append(m / maxf(m.dot(n1), 0.35))
		vavg.append(m)
		var e0: Vector2 = pts[i] - pts[(i - 1 + n) % n]
		var e1: Vector2 = pts[(i + 1) % n] - pts[i]
		var ang: float = absf(e0.angle_to(e1))
		smooth.append(ang < deg_to_rad(38.0))
		var convex: bool = e0.cross(e1) > 0.0
		vedge.append(smoothstep(0.12, 0.6, ang) if convex else 0.0)
		vcav.append(1.0 if convex else lerpf(1.0, 0.55, smoothstep(0.1, 0.8, ang)))
	# Ringe: k = 0 Seitenband, k = segs Deckflaeche
	var ring_pts: Array = []
	var ring_x := PackedFloat32Array()
	for k in segs + 1:
		var th: float = (float(k) / float(segs)) * PI * 0.5 if segs > 0 else 0.0
		var inset: float = b * (1.0 - cos(th))
		ring_x.append((half_w - b) + b * sin(th))
		var rp := PackedVector2Array()
		for i in n:
			rp.append(pts[i] + miter[i] * inset)
		ring_pts.append(rp)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n:
		var j: int = (i + 1) % n
		var side_e := Vector3(0, -en[i].y, -en[i].x)
		var si: Vector3 = Vector3(0, -vavg[i].y, -vavg[i].x) if smooth[i] else side_e
		var sj: Vector3 = Vector3(0, -vavg[j].y, -vavg[j].x) if smooth[j] else side_e
		var ci := Color(vedge[i], vcav[i], 0.0)
		var cj := Color(vedge[j], vcav[j], 0.0)
		var r0: PackedVector2Array = ring_pts[0]
		var x0: float = ring_x[0]
		_quad3(st, [_v3(r0[i], x0), _v3(r0[j], x0), _v3(r0[j], -x0), _v3(r0[i], -x0)], [si, sj, sj, si], [ci, cj, cj, ci])
		for sg: float in [1.0, -1.0]:
			for k in segs:
				var ta: float = float(k) / float(segs) * PI * 0.5
				var tb: float = float(k + 1) / float(segs) * PI * 0.5
				var ra: PackedVector2Array = ring_pts[k]
				var rb: PackedVector2Array = ring_pts[k + 1]
				var xa: float = ring_x[k] * sg
				var xb: float = ring_x[k + 1] * sg
				var cap := Vector3(sg, 0, 0)
				var nia: Vector3 = (si * cos(ta) + cap * sin(ta)).normalized()
				var nja: Vector3 = (sj * cos(ta) + cap * sin(ta)).normalized()
				var nib: Vector3 = (si * cos(tb) + cap * sin(tb)).normalized()
				var njb: Vector3 = (sj * cos(tb) + cap * sin(tb)).normalized()
				var ea_i: float = maxf(sin(2.0 * ta), vedge[i] * cos(ta))
				var ea_j: float = maxf(sin(2.0 * ta), vedge[j] * cos(ta))
				var eb_i: float = maxf(sin(2.0 * tb), vedge[i] * cos(tb))
				var eb_j: float = maxf(sin(2.0 * tb), vedge[j] * cos(tb))
				_quad3(st, [_v3(ra[i], xa), _v3(ra[j], xa), _v3(rb[j], xb), _v3(rb[i], xb)], [nia, nja, njb, nib],
					[Color(ea_i, vcav[i], 0), Color(ea_j, vcav[j], 0), Color(eb_j, vcav[j], 0), Color(eb_i, vcav[i], 0)])
	# Deckflaechen
	var cap_pts: PackedVector2Array = ring_pts[segs]
	var cap_x: float = ring_x[segs]
	var tris: PackedInt32Array = Geometry2D.triangulate_polygon(cap_pts)
	if tris.is_empty():
		cap_pts = pts
		tris = Geometry2D.triangulate_polygon(pts)
	var cc := Color(0.0, 1.0, 0.0)
	for sg: float in [1.0, -1.0]:
		var nn := Vector3(sg, 0, 0)
		for t in range(0, tris.size(), 3):
			_tri3(st, _v3(cap_pts[tris[t]], sg * cap_x), _v3(cap_pts[tris[t + 1]], sg * cap_x),
				_v3(cap_pts[tris[t + 2]], sg * cap_x), nn, nn, nn, cc, cc, cc)
	return st.commit()

## Drehkoerper um die Z-Achse: profile = Vector2(radius, z). round_r rundet Profilecken ab.
## Normalen werden an Knicken > 35 Grad getrennt; konvexe Knicke bekommen Kantenabnutzung.
static func lathe(profile: PackedVector2Array, segs: int = 20, round_r: float = 0.0, closed: bool = false) -> ArrayMesh:
	var src: Array = []
	for p in profile:
		src.append(p)
	var pts: PackedVector2Array = rounded(src, round_r, closed, 2) if round_r > 0.0 else profile.duplicate()
	if closed and pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) > 1e-6:
		pts.append(pts[0])
	var n: int = pts.size()
	# Orientierung ueber die Flaeche des (geschlossenen) Profils
	var area: float = _signed_area(pts)
	var flip: float = 1.0 if area >= 0.0 else -1.0
	var sn: Array[Vector2] = []   # Segment-Normale (r, z), nach aussen
	for i in n - 1:
		var e: Vector2 = (pts[i + 1] - pts[i]).normalized()
		sn.append(Vector2(e.y, -e.x) * flip)
	var vedge := PackedFloat32Array()
	var vcav := PackedFloat32Array()
	var vsmooth: Array[bool] = []
	for i in n:
		var has_prev: bool = i > 0 or closed
		var has_next: bool = i < n - 1
		if not (has_prev and has_next) or (closed and i == 0):
			vedge.append(0.0)
			vcav.append(1.0)
			vsmooth.append(false)
			continue
		var a0: Vector2 = sn[i - 1]
		var a1: Vector2 = sn[i]
		var ang: float = absf(a0.angle_to(a1))
		vsmooth.append(ang < deg_to_rad(35.0))
		var t1: Vector2 = (pts[i + 1] - pts[i]).normalized()
		var convex: bool = t1.dot(a0) < 0.0
		vedge.append(smoothstep(0.15, 0.7, ang) if convex else 0.0)
		vcav.append(1.0 if convex else lerpf(1.0, 0.6, smoothstep(0.1, 0.8, ang)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n - 1:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var n0: Vector2 = (sn[i - 1] + sn[i]).normalized() if i > 0 and vsmooth[i] else sn[i]
		var n1: Vector2 = (sn[i] + sn[i + 1]).normalized() if i + 1 < n - 1 and vsmooth[i + 1] else sn[i]
		var c0 := Color(vedge[i], vcav[i], 0)
		var c1 := Color(vedge[i + 1], vcav[i + 1], 0)
		for s in segs:
			var a0: float = TAU * float(s) / float(segs)
			var a1: float = TAU * float(s + 1) / float(segs)
			var d0 := Vector3(cos(a0), sin(a0), 0)
			var d1 := Vector3(cos(a1), sin(a1), 0)
			var v00: Vector3 = d0 * p0.x + Vector3(0, 0, p0.y)
			var v01: Vector3 = d1 * p0.x + Vector3(0, 0, p0.y)
			var v10: Vector3 = d0 * p1.x + Vector3(0, 0, p1.y)
			var v11: Vector3 = d1 * p1.x + Vector3(0, 0, p1.y)
			var m00: Vector3 = (d0 * n0.x + Vector3(0, 0, n0.y)).normalized()
			var m01: Vector3 = (d1 * n0.x + Vector3(0, 0, n0.y)).normalized()
			var m10: Vector3 = (d0 * n1.x + Vector3(0, 0, n1.y)).normalized()
			var m11: Vector3 = (d1 * n1.x + Vector3(0, 0, n1.y)).normalized()
			if p0.x > 1e-6:
				_tri3(st, v00, v10, v11, m00, m10, m11, c0, c1, c1)
			if p1.x > 1e-6 or p0.x > 1e-6:
				_tri3(st, v00, v11, v01, m00, m11, m01, c0, c1, c0)
	return st.commit()

## Gecachte Grundformen
static func _cached(key: String, fn: Callable) -> ArrayMesh:
	if not _mesh_cache.has(key):
		_mesh_cache[key] = fn.call()
	return _mesh_cache[key]

## Abgerundeter Quader (Kantenradius r).
static func rbox(size: Vector3, r: float = 0.002) -> ArrayMesh:
	var key: String = "rbox_%.4f_%.4f_%.4f_%.4f" % [size.x, size.y, size.z, r]
	return _cached(key, func() -> ArrayMesh:
		var hz: float = size.z * 0.5
		var hy: float = size.y * 0.5
		var rr: float = minf(r, minf(hz, hy) * 0.95)
		var prof: PackedVector2Array = rounded([Vector2(-hz, -hy), Vector2(hz, -hy), Vector2(hz, hy), Vector2(-hz, hy)], rr, true, 2)
		return extrude(prof, size.x * 0.5, minf(r, size.x * 0.45), 2))

## Zylinder entlang Z von z0 bis z1 (Mitte im Ursprung der Achse), Kanten leicht gerundet.
static func cylz(r: float, z0: float, z1: float, segs: int = 18, edge_r: float = -1.0) -> ArrayMesh:
	var er: float = edge_r if edge_r >= 0.0 else minf(r * 0.2, 0.0015)
	var key: String = "cyl_%.4f_%.4f_%.4f_%d_%.4f" % [r, z0, z1, segs, er]
	return _cached(key, func() -> ArrayMesh:
		return lathe(PackedVector2Array([Vector2(0, z0), Vector2(r, z0), Vector2(r, z1), Vector2(0, z1)]), segs, er))

static func ext(key: String, pts: Array, hw: float, bevel: float, r: float = 0.004, bsegs: int = 2) -> ArrayMesh:
	var ck: String = "%s_%.4f_%.4f_%.4f" % [key, hw, bevel, r]
	return _cached(ck, func() -> ArrayMesh:
		return extrude(rounded(pts, r, true, 3), hw, bevel, bsegs))

static func T(pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, sc: float = 1.0) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)).scaled(Vector3.ONE * sc), pos)

## Sammelt Teile pro Gruppe und Material und erzeugt daraus wenige Meshes.
class Builder:
	var parts: Dictionary = {}
	var labels: Array = []
	var meta: Dictionary = {}

	func add(mesh: ArrayMesh, mat_key: String, xf: Transform3D = Transform3D.IDENTITY, group: String = "Body") -> void:
		if not parts.has(group):
			parts[group] = {}
		var g: Dictionary = parts[group]
		if not g.has(mat_key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			g[mat_key] = st
		(g[mat_key] as SurfaceTool).append_from(mesh, 0, xf)

	## Beschriftung (Label3D) in Modellkoordinaten; height = Buchstabenhoehe in m.
	func label(text: String, pos: Vector3, rot_deg: Vector3, height: float, col: Color, group: String = "Body") -> void:
		labels.append({"text": text, "xf": GunModels.T(pos, rot_deg), "h": height, "col": col, "group": group})

	func commit() -> Dictionary:
		var groups: Array = []
		for gname: String in parts:
			var am := ArrayMesh.new()
			var g: Dictionary = parts[gname]
			for mk: String in g:
				var st: SurfaceTool = g[mk]
				st.index()
				st.commit(am)
				am.surface_set_material(am.get_surface_count() - 1, GunModels.mat(mk))
			groups.append({"name": gname, "mesh": am})
		return {"groups": groups, "labels": labels, "meta": meta}

static func _instantiate(tpl: Dictionary, root_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = root_name
	var nodes: Dictionary = {}
	for g: Dictionary in tpl.groups:
		var gname: String = g.name
		var parent: Node3D = root
		if gname != "Body":
			parent = Node3D.new()
			parent.name = gname
			root.add_child(parent)
		nodes[gname] = parent
		var mi := MeshInstance3D.new()
		mi.name = gname + "Mesh"
		mi.mesh = g.mesh
		parent.add_child(mi)
	for l: Dictionary in tpl.labels:
		var lb := Label3D.new()
		lb.text = l.text
		lb.font_size = 48
		lb.pixel_size = float(l.h) / 34.0
		lb.modulate = l.col
		lb.outline_size = 0
		lb.shaded = true
		lb.double_sided = false
		lb.alpha_cut = Label3D.ALPHA_CUT_DISABLED
		lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		lb.transform = l.xf
		lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var par: Node3D = nodes.get(l.group, root)
		par.add_child(lb)
	for k: String in tpl.meta:
		root.set_meta(k, tpl.meta[k])
	return root

static func _template(id: String, fn: Callable) -> Dictionary:
	if not _templates.has(id):
		var b := Builder.new()
		fn.call(b)
		_templates[id] = b.commit()
	return _templates[id]

# ------------------------------------------------------------------ G36C

## H&K G36C (Stil): Polymergehaeuse mit Schienen-Bruecke + Picatinny, Spannhebel unter der Bruecke,
## gerippter Handschutz mit echten Lueftungsschlitzen, Skelett-Klappschaft, transluzentes Magazin mit
## 30 sichtbaren Patronen, Feuerwahlhebel mit Markierung, Mündungsfeuerdämpfer mit 4 Zinken.
## Metas: muzzle, optic_mount (Oberkante Schiene), eject, length.
static func build_g36c() -> Node3D:
	return _instantiate(_template("g36c", _g36c_parts), "G36C")

static func _g36c_parts(b: Builder) -> void:
	var bore: float = 0.030
	var hw: float = 0.025
	# --- Gehaeuse-Oberteil (Lauf-/Verschlussgehaeuse), oben stark gerundet
	b.add(ext("g_recv", [Vector2(0.108, 0.047), Vector3(-0.156, 0.047, 0.004), Vector2(-0.156, -0.018),
		Vector2(0.108, -0.018)], hw, 0.008, 0.006, 3), "poly")
	# Trennfuge Ober-/Unterteil und Laengssicke
	for sx: float in [1.0, -1.0]:
		b.add(rbox(Vector3(0.0012, 0.0016, 0.25), 0.0005), "poly_dark", T(Vector3(sx * (hw - 0.0002), -0.0175, -0.024)))
		b.add(rbox(Vector3(0.0016, 0.0065, 0.15), 0.0025), "poly", T(Vector3(sx * (hw + 0.0004), 0.0285, -0.05)))
	# --- Magazinschacht mit ausgestelltem Kragen
	b.add(ext("g_well", [Vector2(-0.02, -0.012), Vector2(-0.1, -0.012), Vector2(-0.102, -0.05),
		Vector2(-0.097, -0.066), Vector2(-0.021, -0.066), Vector2(-0.016, -0.04)], 0.0272, 0.005, 0.004, 2), "poly")
	b.add(ext("g_well_lip", [Vector2(-0.104, -0.058), Vector2(-0.016, -0.058), Vector2(-0.018, -0.0715),
		Vector2(-0.1, -0.0715)], 0.0292, 0.004, 0.003, 2), "poly")
	b.add(rbox(Vector3(0.05, 0.004, 0.072), 0.001), "poly_dark", T(Vector3(0, -0.0712, -0.06)))
	# --- Unterteil (Griffstueck) mit Pistolengriff (Fingerrillen, Stippling-Material)
	b.add(ext("g_lower", [Vector2(-0.02, -0.014), Vector2(0.108, -0.014), Vector2(0.108, -0.028),
		Vector2(0.084, -0.038), Vector2(0.03, -0.038), Vector2(-0.016, -0.042)], 0.0238, 0.004, 0.004, 2), "poly")
	b.add(ext("g_grip", [Vector2(0.03, -0.034), Vector2(0.086, -0.032), Vector2(0.094, -0.056), Vector2(0.106, -0.1),
		Vector3(0.114, -0.133, 0.008), Vector3(0.108, -0.147, 0.006), Vector3(0.074, -0.149, 0.006), Vector2(0.07, -0.138),
		Vector3(0.064, -0.124, 0.006), Vector3(0.069, -0.113, 0.005), Vector3(0.06, -0.099, 0.006), Vector3(0.064, -0.087, 0.005),
		Vector3(0.056, -0.073, 0.006), Vector2(0.05, -0.052), Vector2(0.036, -0.042)], 0.0168, 0.006, 0.004, 3), "poly_grip")
	b.add(ext("g_grip_cap", [Vector2(0.074, -0.142), Vector2(0.11, -0.139), Vector2(0.109, -0.15), Vector2(0.076, -0.152)],
		0.0175, 0.004, 0.003), "poly")
	# Abzugsbuegel (gross, einteilig mit dem Griffstueck) und Abzug
	b.add(ext("g_guard", Array(stroke([Vector2(-0.012, -0.036), Vector2(-0.01, -0.062), Vector2(0.0, -0.075),
		Vector2(0.03, -0.08), Vector2(0.05, -0.08), Vector2(0.062, -0.07)], 0.0075)), 0.0085, 0.003, 0.003), "poly")
	b.add(ext("g_trig", Array(stroke([Vector2(0.012, -0.038), Vector2(0.016, -0.05), Vector2(0.021, -0.06),
		Vector2(0.028, -0.065)], 0.0048)), 0.0032, 0.0012, 0.0015), "park")
	b.add(rbox(Vector3(0.012, 0.012, 0.006), 0.002), "park", T(Vector3(0, -0.07, -0.011), Vector3(-30, 0, 0)))
	# --- Handschutz: Ober- und Unterholm, Rippen dazwischen -> echte Lueftungsschlitze
	var hg_hw: float = 0.0285
	b.add(ext("g_hg_top", [Vector2(-0.154, 0.039), Vector2(-0.31, 0.039), Vector3(-0.33, 0.03, 0.006),
		Vector2(-0.334, 0.008), Vector2(-0.154, 0.008)], hg_hw, 0.007, 0.004, 3), "poly")
	b.add(ext("g_hg_bot", [Vector2(-0.154, -0.018), Vector2(-0.334, -0.018), Vector3(-0.332, -0.036, 0.008),
		Vector2(-0.31, -0.048), Vector2(-0.154, -0.048)], hg_hw, 0.007, 0.004, 3), "poly")
	var ribs: Array = [[-0.154, -0.184], [-0.206, -0.217], [-0.239, -0.25], [-0.272, -0.283], [-0.305, -0.334]]
	for rz: Array in ribs:
		var z0: float = rz[0]
		var z1: float = rz[1]
		b.add(rbox(Vector3(hg_hw * 2.0 - 0.0016, 0.032, z0 - z1), 0.0035), "poly", T(Vector3(0, -0.005, (z0 + z1) * 0.5)))
	# Hitzeschild innen (dunkel, sichtbar durch die Schlitze) + Lauf darin
	b.add(rbox(Vector3(0.042, 0.034, 0.13), 0.004), "poly_dark", T(Vector3(0, -0.004, -0.245)))
	b.add(cylz(0.011, -0.15, -0.33, 14), "park", T(Vector3(0, bore - 0.012, 0)))
	# Haltebolzen Handschutz
	b.add(cylz(0.0032, -0.031, 0.031, 12, 0.0006), "steel", T(Vector3(0, 0.022, -0.168), Vector3(0, 90, 0)))
	# Unterseite: kurze Picatinny-Schiene (eloxiert)
	_rail(b, Vector3(0, -0.048, -0.24), 7, true)
	# --- Lauf, Laufmutter und Mündungsfeuerdämpfer (4 Zinken, offener Kaefig)
	b.add(lathe(PackedVector2Array([Vector2(0, -0.33), Vector2(0.0145, -0.33), Vector2(0.0145, -0.338),
		Vector2(0.0105, -0.345), Vector2(0.0, -0.345)]), 24, 0.0015), "park", T(Vector3(0, bore, 0)))
	b.add(cylz(0.0088, -0.34, -0.425, 20), "park", T(Vector3(0, bore, 0)))
	b.add(lathe(PackedVector2Array([Vector2(0, -0.418), Vector2(0.0118, -0.418), Vector2(0.0125, -0.424),
		Vector2(0.0125, -0.434), Vector2(0.0108, -0.436), Vector2(0.0, -0.436)]), 24, 0.001), "park", T(Vector3(0, bore, 0)))
	b.add(cylz(0.0064, -0.434, -0.47, 16, 0.0), "bore", T(Vector3(0, bore, 0)))
	for k in 4:
		var a: float = TAU * float(k) / 4.0 + PI * 0.25
		var prong: ArrayMesh = ext("g_prong", [Vector2(-0.0, -0.0028), Vector2(-0.034, -0.0024), Vector2(-0.035, 0.0026),
			Vector2(0.0, 0.0034)], 0.003, 0.0011, 0.0012)
		b.add(prong, "park", Transform3D(Basis(Vector3.BACK, a + PI * 0.5), Vector3(cos(a) * 0.0093, bore + sin(a) * 0.0093, -0.434)))
	# --- Schienen-Bruecke (Riser) mit Fenster fuer den Spannhebel + Picatinny oben
	b.add(ext("g_riser", [Vector2(0.1, 0.046), Vector3(0.1, 0.082, 0.006), Vector3(0.086, 0.089, 0.004),
		Vector3(-0.142, 0.089, 0.004), Vector3(-0.152, 0.082, 0.006), Vector2(-0.152, 0.046), Vector2(-0.124, 0.046),
		Vector3(-0.11, 0.072, 0.008), Vector3(0.05, 0.072, 0.008), Vector2(0.064, 0.046)], 0.0145, 0.004, 0.005, 2), "poly")
	var rail_y: float = 0.089
	_rail(b, Vector3(0, rail_y, -0.026), 21, false)
	# Kimme (Notvisier) hinten, abgeklappt
	b.add(rbox(Vector3(0.018, 0.006, 0.016), 0.002), "anod", T(Vector3(0, rail_y + 0.012, 0.075)))
	# --- Spannhebel (Gruppe), Schlitz im Gehaeuse
	b.add(rbox(Vector3(0.0062, 0.0024, 0.14), 0.0008), "bore", T(Vector3(0, 0.0472, -0.05)))
	b.add(rbox(Vector3(0.007, 0.012, 0.03), 0.002), "park", T(Vector3(0, 0.053, 0.032)), "Charging_Handle")
	b.add(ext("g_ch_lever", Array(stroke([Vector2(0.0, 0.0), Vector2(0.022, 0.004), Vector2(0.034, 0.01)], 0.007)),
		0.003, 0.0012, 0.002), "park", Transform3D(Basis(Vector3.UP, -PI * 0.5 + 0.35) * Basis(Vector3.RIGHT, 0.0),
		Vector3(0.002, 0.058, 0.028)), "Charging_Handle")
	b.add(cylz(0.0055, -0.006, 0.006, 14, 0.0015), "poly", T(Vector3(0.033, 0.0605, 0.016), Vector3(0, 90, 0)), "Charging_Handle")
	# --- Auswurffenster rechts: Rahmen, sichtbarer Verschlussträger, Huelsenabweiser
	var ex: float = hw
	b.add(rbox(Vector3(0.0018, 0.022, 0.046), 0.0006), "steel", T(Vector3(ex - 0.0004, 0.019, -0.036)))
	b.add(rbox(Vector3(0.0022, 0.003, 0.03), 0.0006), "park", T(Vector3(ex + 0.0003, 0.019, -0.04)))
	for yy: float in [0.0065, 0.0315]:
		b.add(rbox(Vector3(0.003, 0.0035, 0.054), 0.0012), "poly", T(Vector3(ex + 0.0004, yy, -0.036)))
	for zz: float in [-0.0625, -0.0095]:
		b.add(rbox(Vector3(0.003, 0.028, 0.0035), 0.0012), "poly", T(Vector3(ex + 0.0004, 0.019, zz)))
	b.add(ext("g_deflector", [Vector2(0.0, -0.008), Vector2(0.016, -0.008), Vector2(0.018, 0.008), Vector2(0.0, 0.01)],
		0.004, 0.0025, 0.004), "poly", T(Vector3(ex + 0.003, 0.022, -0.006)))
	# --- Feuerwahlhebel beidseitig mit Markierung (S / E / F), Magazinhalter, Verschlussfang
	for sx: float in [1.0, -1.0]:
		b.add(cylz(0.0075, -0.0016, 0.0016, 18, 0.0007), "park", T(Vector3(sx * (hw + 0.0016), -0.022, 0.052), Vector3(0, 90, 0)))
		b.add(ext("g_sel", Array(stroke([Vector2(0.0, 0.0), Vector2(0.018, -0.006), Vector2(0.024, -0.01)], 0.0055)),
			0.0014, 0.0006, 0.0018), "park", T(Vector3(sx * (hw + 0.0032), -0.022, 0.052)))
	var wc := Color(0.78, 0.78, 0.74)
	b.label("S", Vector3(hw + 0.0006, -0.0085, 0.066), Vector3(0, 90, 0), 0.0042, wc)
	b.label("E", Vector3(hw + 0.0006, -0.007, 0.05), Vector3(0, 90, 0), 0.0042, wc)
	b.label("F", Vector3(hw + 0.0006, -0.0105, 0.036), Vector3(0, 90, 0), 0.0042, wc)
	b.label("G36C   Kal. 5,56 mm x 45", Vector3(0.0277, -0.038, -0.058), Vector3(0, 90, 0), 0.0036, Color(0.6, 0.6, 0.58))
	b.label("Nr. 17-041736", Vector3(hw + 0.0006, 0.004, 0.065), Vector3(0, 90, 0), 0.0028, Color(0.55, 0.55, 0.53))
	b.add(rbox(Vector3(0.034, 0.0055, 0.009), 0.0018), "park", T(Vector3(0, -0.0675, -0.0125)))
	# --- Sichtbare Bolzen (Enden glaenzen)
	for pz: Vector2 in [Vector2(-0.142, 0.03), Vector2(-0.012, -0.03), Vector2(0.094, -0.026), Vector2(0.022, -0.029), Vector2(0.075, 0.03)]:
		b.add(cylz(0.0031, -hw - 0.0009, hw + 0.0009, 12, 0.0006), "steel", T(Vector3(0, pz.y, pz.x), Vector3(0, 90, 0)))
	# --- Skelett-Klappschaft (ausgeklappt): Scharnier, Streben, Wangenauflage, Schaftkappe
	b.add(ext("g_hinge", [Vector2(0.104, 0.046), Vector2(0.132, 0.046), Vector2(0.136, -0.03), Vector2(0.104, -0.03)],
		0.027, 0.006, 0.006, 3), "poly")
	b.add(cylz(0.011, -0.006, 0.006, 20, 0.002), "poly_dark", T(Vector3(0.028, 0.008, 0.121), Vector3(0, 90, 0)))
	b.add(cylz(0.006, -0.004, 0.004, 16, 0.0015), "park", T(Vector3(0.032, 0.008, 0.121), Vector3(0, 90, 0)))
	b.add(ext("g_stock_top", Array(stroke([Vector2(0.128, 0.034), Vector2(0.24, 0.036), Vector2(0.336, 0.036)], 0.022)),
		0.0145, 0.0055, 0.006, 3), "poly")
	b.add(ext("g_stock_cheek", [Vector2(0.17, 0.046), Vector2(0.3, 0.047), Vector2(0.3, 0.03), Vector2(0.17, 0.03)],
		0.0175, 0.006, 0.008, 3), "poly")
	b.add(ext("g_stock_bot", Array(stroke([Vector2(0.128, -0.022), Vector2(0.2, -0.036), Vector2(0.33, -0.064)], 0.017)),
		0.0135, 0.005, 0.005, 3), "poly")
	b.add(ext("g_stock_web", Array(stroke([Vector2(0.21, 0.03), Vector2(0.236, -0.035)], 0.012)), 0.011, 0.004, 0.004), "poly")
	b.add(ext("g_stock_but", [Vector2(0.318, 0.052), Vector2(0.346, 0.054), Vector2(0.356, 0.032), Vector2(0.356, -0.074),
		Vector2(0.346, -0.094), Vector2(0.318, -0.092), Vector2(0.322, -0.02)], 0.019, 0.006, 0.008, 3), "poly")
	b.add(ext("g_stock_pad", [Vector2(0.354, 0.049), Vector2(0.367, 0.046), Vector2(0.369, -0.077), Vector2(0.356, -0.09)],
		0.0188, 0.004, 0.005), "rubber")
	for k in 9:
		b.add(rbox(Vector3(0.036, 0.0022, 0.003), 0.0008), "poly_dark", T(Vector3(0, 0.035 - float(k) * 0.0135, 0.3685)))
	# Riemenoese am Schaft und vorn
	var loop := lathe(PackedVector2Array([Vector2(0.007, 0.0), Vector2(0.0085, 0.0015), Vector2(0.01, 0.0),
		Vector2(0.0085, -0.0015), Vector2(0.007, 0.0)]), 16, 0.0, true)
	b.add(loop, "park", T(Vector3(0.0, -0.1, 0.33), Vector3(0, 90, 0)))
	b.add(loop, "park", T(Vector3(-0.031, 0.02, -0.17), Vector3(0, 0, 0)))
	# --- Magazin (Gruppe): transluzente Schale nach Kurve, Verstaerkungsrippen, 30 Patronen
	_g36_mag(b)
	b.meta["muzzle"] = Vector3(0, bore, -0.47)
	b.meta["optic_mount"] = Vector3(0, rail_y + 0.0095, -0.04)
	b.meta["eject"] = Vector3(0.03, 0.02, -0.036)
	b.meta["length"] = 0.84

## Picatinny-Abschnitt (n Rippen) mit Schwalbenschwanz-Querschnitt, Oberkante bei pos.y + 0.0095.
static func _rail(b: Builder, pos: Vector3, n: int, under: bool) -> void:
	var sgn: float = -1.0 if under else 1.0
	var pitch: float = 0.01
	var length: float = float(n) * pitch
	# Profil in (x, y), extrudiert entlang Z (Drehung um Y)
	var base: ArrayMesh = _cached("rail_base_%d" % n, func() -> ArrayMesh:
		return extrude(rounded([Vector2(-0.0078, 0.0), Vector2(0.0078, 0.0), Vector2(0.0078, 0.0015), Vector2(0.0106, 0.0042),
			Vector2(0.0106, 0.0052), Vector2(-0.0106, 0.0052), Vector2(-0.0106, 0.0042), Vector2(-0.0078, 0.0015)], 0.0006, true, 1),
			length * 0.5 + 0.004, 0.001, 1))
	var tooth: ArrayMesh = _cached("rail_tooth", func() -> ArrayMesh:
		return extrude(rounded([Vector2(-0.0106, 0.0052), Vector2(0.0106, 0.0052), Vector2(0.0106, 0.0072),
			Vector2(0.0088, 0.0095), Vector2(-0.0088, 0.0095), Vector2(-0.0106, 0.0072)], 0.0006, true, 1), 0.0026, 0.0007, 1))
	var rb := Basis(Vector3.UP, PI * 0.5)
	if under:
		rb = Basis(Vector3.BACK, PI) * rb
	b.add(base, "anod", Transform3D(rb, pos))
	for i in n:
		var z: float = pos.z + (float(i) - float(n - 1) * 0.5) * pitch
		b.add(tooth, "anod", Transform3D(rb, Vector3(pos.x, pos.y, z)))
	if not under:
		# Querbohrungen-Kennzeichnung wie auf echten Schienen (jede 2. Rippe)
		for i in range(0, n, 4):
			var z2: float = pos.z + (float(i) - float(n - 1) * 0.5) * pitch
			b.label(str(i / 2 + 1), Vector3(0.0107, pos.y + 0.0036 * sgn, z2), Vector3(0, 90, 0), 0.0022, Color(0.7, 0.7, 0.68))

static func _mag_curve(d: float) -> float:
	return -0.057 - 0.12 * d - 0.95 * d * d

static func _g36_mag(b: Builder) -> void:
	var g: String = "Magazine"
	var front: Array = []
	var back: Array = []
	var steps: int = 10
	for i in steps + 1:
		var d: float = 0.18 * float(i) / float(steps)
		var y: float = -0.03 - d
		var zc: float = _mag_curve(d)
		front.append(Vector2(zc - 0.0355, y))
		back.append(Vector2(zc + 0.0345, y))
	var shell: Array = []
	shell.append_array(back)
	front.reverse()
	shell.append_array(front)
	var shell_mesh: ArrayMesh = _cached("g_mag_shell", func() -> ArrayMesh:
		return extrude(rounded(shell, 0.004, true, 2), 0.0132, 0.0045, 3))
	b.add(shell_mesh, "mag_clear", Transform3D.IDENTITY, g)
	# Rippen vorn/hinten (dichter) und seitliche Verbindungsnasen
	front.reverse()
	var fr: Array = []
	var br: Array = []
	for i in range(1, steps + 1):
		fr.append(front[i] + Vector2(0.0018, 0.0))
		br.append(back[i] - Vector2(0.0018, 0.0))
	b.add(_cached("g_mag_rf", func() -> ArrayMesh: return extrude(stroke(fr, 0.0055), 0.0142, 0.0022, 2)), "mag_rib", Transform3D.IDENTITY, g)
	b.add(_cached("g_mag_rb", func() -> ArrayMesh: return extrude(stroke(br, 0.005), 0.0142, 0.0022, 2)), "mag_rib", Transform3D.IDENTITY, g)
	for dd: float in [0.06, 0.135]:
		var zc2: float = _mag_curve(dd)
		b.add(rbox(Vector3(0.0045, 0.012, 0.009), 0.0015), "mag_rib", T(Vector3(0.0145, -0.03 - dd, zc2 + 0.028), Vector3(-10.0 - dd * 120.0, 0, 0)), g)
		b.add(rbox(Vector3(0.0045, 0.012, 0.009), 0.0015), "mag_rib", T(Vector3(-0.0145, -0.03 - dd, zc2 - 0.026), Vector3(-10.0 - dd * 120.0, 0, 0)), g)
	# Bodenplatte (opak)
	var dl: float = 0.18
	var zb: float = _mag_curve(dl)
	var tilt: float = rad_to_deg(atan(0.12 + 1.9 * dl))
	b.add(rbox(Vector3(0.0305, 0.009, 0.078), 0.003), "poly", T(Vector3(0, -0.03 - dl - 0.002, zb - 0.0005), Vector3(-tilt * 0.55, 0, 0)), g)
	# Patronen (Doppelreihe), Geschoss nach vorn
	var case_m: ArrayMesh = _cached("round_case", func() -> ArrayMesh:
		return lathe(PackedVector2Array([Vector2(0, 0.0285), Vector2(0.0047, 0.0285), Vector2(0.0047, 0.0272), Vector2(0.0039, 0.0266),
			Vector2(0.0039, 0.0258), Vector2(0.0048, 0.0252), Vector2(0.0046, -0.006), Vector2(0.0032, -0.0105),
			Vector2(0.0031, -0.016), Vector2(0.0, -0.016)]), 8, 0.0004))
	var bullet_m: ArrayMesh = _cached("round_bullet", func() -> ArrayMesh:
		return lathe(PackedVector2Array([Vector2(0, -0.0158), Vector2(0.00285, -0.0158), Vector2(0.00285, -0.0195),
			Vector2(0.0024, -0.0235), Vector2(0.0013, -0.0268), Vector2(0.0, -0.0285)]), 8, 0.0))
	var count: int = 30
	for i in count:
		var d2: float = 0.004 + float(i) * 0.0054
		if d2 > 0.172:
			break
		var y2: float = -0.033 - d2
		var zc3: float = _mag_curve(d2) + 0.003
		var xo: float = 0.0027 if i % 2 == 0 else -0.0027
		var ang: float = atan(0.12 + 1.9 * d2)
		var xf := Transform3D(Basis(Vector3.RIGHT, -ang * 0.85), Vector3(xo, y2, zc3))
		b.add(case_m, "brass", xf, g)
		b.add(bullet_m, "copper", xf, g)
	# Zuführlippen oben
	b.add(rbox(Vector3(0.027, 0.006, 0.06), 0.002), "mag_rib", T(Vector3(0, -0.031, -0.058)), g)

# ------------------------------------------------------------------ Holo-Visier

## Holografisches Visier (Stil EOTech) fuer weapon.gd: Ursprung = Schienenoberkante.
## Glasmitte bei (0, 0.036, -0.012), Glasgroesse 0.034 x 0.026 (Meta "glass_center"/"glass_size").
static func build_holo() -> Node3D:
	return _instantiate(_template("holo", _holo_parts), "HoloSight")

static func _holo_parts(b: Builder) -> void:
	var gw: float = 0.034
	var gh: float = 0.026
	var gy: float = 0.036
	var gz: float = -0.012
	var y_bot: float = gy - gh * 0.5
	# Klemmfuss mit Querbolzen und Schraube
	b.add(ext("h_base", [Vector2(0.03, 0.0), Vector2(-0.044, 0.0), Vector2(-0.048, 0.006), Vector2(0.034, 0.006)],
		0.0135, 0.0025, 0.002), "anod")
	b.add(cylz(0.0062, -0.004, 0.004, 18, 0.0012), "anod", T(Vector3(0.0175, 0.004, 0.012), Vector3(0, 90, 0)))
	b.add(rbox(Vector3(0.0012, 0.0085, 0.0018), 0.0004), "bore", T(Vector3(0.0218, 0.004, 0.012)))
	# Gehaeuse unten (Elektronik), vorn Batteriefach quer
	b.add(ext("h_body", [Vector2(0.034, 0.005), Vector2(-0.046, 0.005), Vector3(-0.05, 0.012, 0.004),
		Vector3(-0.046, y_bot + 0.001, 0.002), Vector3(0.03, y_bot + 0.001, 0.002), Vector3(0.036, 0.016, 0.004)],
		gw * 0.5 + 0.0035, 0.004, 0.003, 3), "anod")
	b.add(cylz(0.0075, -0.024, 0.024, 20, 0.0015), "anod", T(Vector3(0, 0.0115, -0.04), Vector3(0, 90, 0)))
	b.add(cylz(0.0068, -0.002, 0.002, 18, 0.001), "park", T(Vector3(0.0255, 0.0115, -0.04), Vector3(0, 90, 0)))
	# Bedientasten hinten (Gummi)
	for sx: float in [-0.007, 0.007]:
		b.add(rbox(Vector3(0.008, 0.0065, 0.004), 0.0018), "rubber", T(Vector3(sx, 0.013, 0.0355)))
	b.add(rbox(Vector3(0.006, 0.002, 0.0008), 0.0003), "poly_dark", T(Vector3(0.0, 0.0175, 0.035)))
	# Haube: Seitenwaende + gewoelbtes Dach (Fenster frei)
	for sx: float in [1.0, -1.0]:
		b.add(ext("h_wall", [Vector2(0.026, y_bot - 0.002), Vector2(-0.044, y_bot - 0.002), Vector3(-0.044, gy + gh * 0.5 + 0.003, 0.003),
			Vector3(0.026, gy + gh * 0.5 + 0.003, 0.003)], 0.0022, 0.0012, 0.003, 2), "anod",
			T(Vector3(sx * (gw * 0.5 + 0.0022), 0, 0)))
	b.add(ext("h_roof", [Vector2(0.026, 0.0), Vector2(-0.044, 0.0), Vector2(-0.044, 0.0035), Vector2(0.026, 0.0035)],
		gw * 0.5 + 0.0044, 0.0018, 0.0015, 2), "anod", T(Vector3(0, gy + gh * 0.5 + 0.0012, 0)))
	# Fensterrahmen vorn (duenn) und hintere Scheibe (blau verguetet, nur am Rand sichtbar)
	b.add(rbox(Vector3(gw + 0.002, 0.0022, 0.004), 0.0008), "anod", T(Vector3(0, y_bot - 0.0005, gz - 0.002)))
	b.label("HWS", Vector3(gw * 0.5 + 0.0045, 0.012, -0.004), Vector3(0, 90, 0), 0.003, Color(0.62, 0.62, 0.6))
	b.meta["glass_center"] = Vector3(0, gy, gz)
	b.meta["glass_size"] = Vector2(gw, gh)

# ------------------------------------------------------------------ Panzerfaust 3

## Panzerfaust 3 (Stil): geripptes Abschussrohr mit Gummi-Endkappen, Abfeuereinrichtung mit Griff,
## Klappvisier mit Augenmuschel, Schulterstuetze; Gefechtskopf ("Magazine") mit Abstandssonde.
static func build_pzf() -> Node3D:
	return _instantiate(_template("pzf", _pzf_parts), "Panzerfaust3")

static func _pzf_parts(b: Builder) -> void:
	var tube_r: float = 0.036
	# Rohr mit flachen Laengsrillen-Abschnitten (Ringwulste) und ausgestelltem Heck
	var prof := PackedVector2Array([Vector2(0.0, 0.52), Vector2(0.03, 0.52), Vector2(0.041, 0.515), Vector2(0.043, 0.5),
		Vector2(0.039, 0.47), Vector2(tube_r, 0.44)])
	var z: float = 0.4
	while z > -0.38:
		prof.append(Vector2(tube_r, z))
		prof.append(Vector2(tube_r + 0.0016, z - 0.004))
		prof.append(Vector2(tube_r + 0.0016, z - 0.012))
		prof.append(Vector2(tube_r, z - 0.016))
		z -= 0.06 if absf(z) > 0.15 else 0.09
	prof.append_array(PackedVector2Array([Vector2(tube_r, -0.415), Vector2(0.0395, -0.42), Vector2(0.0395, -0.44),
		Vector2(0.034, -0.444), Vector2(0.0, -0.444)]))
	b.add(_cached("pzf_tube", func() -> ArrayMesh: return lathe(prof, 32, 0.0015)), "olive")
	# Gummi-Endkappe hinten (Rand) und Gummiring vorn
	b.add(_cached("pzf_rcap", func() -> ArrayMesh: return lathe(PackedVector2Array([Vector2(0.033, 0.53), Vector2(0.046, 0.53),
		Vector2(0.047, 0.5), Vector2(0.044, 0.49), Vector2(0.041, 0.49), Vector2(0.041, 0.52), Vector2(0.033, 0.52),
		Vector2(0.033, 0.53)]), 32, 0.002, true)), "rubber")
	b.add(_cached("pzf_rinner", func() -> ArrayMesh: return lathe(PackedVector2Array([Vector2(0.0, 0.505), Vector2(0.033, 0.505),
		Vector2(0.033, 0.52), Vector2(0.0, 0.52)]), 24, 0.0)), "bore")
	b.add(_cached("pzf_fring", func() -> ArrayMesh: return lathe(PackedVector2Array([Vector2(0.0392, -0.4), Vector2(0.0418, -0.402),
		Vector2(0.0418, -0.418), Vector2(0.0392, -0.42), Vector2(0.0392, -0.4)]), 32, 0.001, true)), "rubber")
	# Kennzeichnungsringe
	b.add(cylz(tube_r + 0.0012, -0.358, -0.346, 32, 0.0004), "yellow")
	b.add(cylz(tube_r + 0.0012, 0.43, 0.437, 32, 0.0004), "yellow")
	# Tragegurt-Oesen
	b.add(rbox(Vector3(0.012, 0.008, 0.02), 0.003), "olive_dark", T(Vector3(0.0, -tube_r - 0.003, 0.36)))
	b.add(rbox(Vector3(0.012, 0.008, 0.02), 0.003), "olive_dark", T(Vector3(0.0, -tube_r - 0.003, -0.3)))
	# Beschriftung (fiktiv), entlang der Rohrachse auf beiden Seiten
	var stencil := Color(0.86, 0.82, 0.62)
	for sx: float in [1.0, -1.0]:
		var ry: float = 90.0 if sx > 0.0 else -90.0
		var zz: float = 1.0 if sx > 0.0 else -1.0
		b.label("PZF 3   ABSCHUSSROHR   LOS 07-31", Vector3(sx * (tube_r + 0.0004), 0.006, -0.12 * zz * 0.0 + 0.12), Vector3(0, ry, 0), 0.0075, stencil)
		b.label("DM 22   NUR EINMAL VERWENDEN", Vector3(sx * (tube_r + 0.0004), -0.008, 0.12), Vector3(0, ry, 0), 0.0055, stencil)
		b.label("! RUECKSTRAHL  30 m !", Vector3(sx * (tube_r + 0.0004), 0.0, 0.39), Vector3(0, ry, 0), 0.0068, Color(0.85, 0.66, 0.12))
	# Abfeuereinrichtung oben: Gehaeuse, Seitendeckel, Sicherung
	var top: float = tube_r
	b.add(ext("p_fu", [Vector2(0.15, top - 0.006), Vector2(-0.165, top - 0.006), Vector3(-0.175, top + 0.026, 0.01),
		Vector2(-0.08, top + 0.04), Vector2(0.12, top + 0.036), Vector3(0.158, top + 0.012, 0.01)], 0.026, 0.007, 0.008, 3), "olive_dark")
	b.add(ext("p_fu_cover", [Vector2(0.11, top + 0.002), Vector2(-0.13, top + 0.002), Vector2(-0.12, top + 0.03),
		Vector2(0.1, top + 0.03)], 0.0278, 0.003, 0.006, 2), "olive_dark")
	for k in 4:
		b.add(cylz(0.003, -0.0285, 0.0285, 10, 0.0006), "park", T(Vector3(0, top + 0.016, 0.08 - float(k) * 0.06), Vector3(0, 90, 0)))
	b.add(rbox(Vector3(0.006, 0.012, 0.016), 0.002), "yellow", T(Vector3(0.029, top + 0.012, 0.11)))
	b.label("SICHERN", Vector3(0.0285, top + 0.024, 0.11), Vector3(0, 90, 0), 0.004, Color(0.85, 0.82, 0.7))
	# Klappvisier links: Traeger, Gehaeuse, hohles Okular mit Augenmuschel, Glas + Strichplatte
	b.add(ext("p_sight_arm", [Vector2(0.0, top + 0.02), Vector2(-0.03, top + 0.02), Vector2(-0.028, top + 0.075),
		Vector2(-0.004, top + 0.075)], 0.009, 0.003, 0.004), "olive_dark", T(Vector3(-0.036, 0, -0.035)))
	b.add(ext("p_sight_box", [Vector2(-0.018, top + 0.07), Vector2(-0.082, top + 0.07), Vector3(-0.086, top + 0.083, 0.004),
		Vector2(-0.016, top + 0.083)], 0.014, 0.004, 0.004, 2), "olive_dark", T(Vector3(-0.044, 0, 0)))
	var ring := lathe(PackedVector2Array([Vector2(0.0118, 0.026), Vector2(0.0148, 0.026), Vector2(0.0148, -0.026),
		Vector2(0.0118, -0.026), Vector2(0.0118, 0.026)]), 24, 0.0, true)
	b.add(ring, "olive_dark", T(Vector3(-0.044, top + 0.098, -0.05)))
	var cup := lathe(PackedVector2Array([Vector2(0.0125, 0.024), Vector2(0.0158, 0.024), Vector2(0.0178, 0.046),
		Vector2(0.0158, 0.046), Vector2(0.0125, 0.024)]), 24, 0.0006, true)
	b.add(cup, "rubber", T(Vector3(-0.044, top + 0.098, -0.05)))
	b.add(cylz(0.0118, -0.0005, 0.0005, 24, 0.0), "lens_coated", T(Vector3(-0.044, top + 0.098, -0.0755)))
	b.add(rbox(Vector3(0.016, 0.0005, 0.0005), 0.0), "reticle", T(Vector3(-0.044, top + 0.098, -0.074)))
	b.add(rbox(Vector3(0.0005, 0.008, 0.0005), 0.0), "reticle", T(Vector3(-0.044, top + 0.093, -0.074)))
	b.add(rbox(Vector3(0.006, 0.0005, 0.0005), 0.0), "reticle", T(Vector3(-0.044, top + 0.092, -0.074)))
	# Pistolengriff mit Abzugsbuegel, Abzug
	b.add(ext("p_grip", [Vector2(0.056, -top + 0.006), Vector2(0.102, -top + 0.006), Vector2(0.122, -top - 0.088),
		Vector3(0.116, -top - 0.098, 0.006), Vector2(0.088, -top - 0.1), Vector2(0.082, -top - 0.07), Vector2(0.076, -top - 0.058),
		Vector2(0.07, -top - 0.03)], 0.0165, 0.006, 0.006, 3), "olive_dark")
	b.add(ext("p_guard", Array(stroke([Vector2(0.0, -top + 0.002), Vector2(0.004, -top - 0.03), Vector2(0.03, -top - 0.042),
		Vector2(0.066, -top - 0.042)], 0.007)), 0.008, 0.0025, 0.003), "olive_dark")
	b.add(ext("p_trig", Array(stroke([Vector2(0.026, -top), Vector2(0.03, -top - 0.016), Vector2(0.038, -top - 0.026)], 0.0055)),
		0.0035, 0.0012, 0.0015), "park")
	# Vordergriff und Schulterstuetze (klappbar)
	b.add(ext("p_fgrip", [Vector2(-0.122, -top + 0.006), Vector2(-0.088, -top + 0.006), Vector2(-0.094, -top - 0.086),
		Vector3(-0.1, -top - 0.092, 0.005), Vector2(-0.124, -top - 0.088)], 0.015, 0.005, 0.005, 3), "olive_dark")
	b.add(ext("p_shoulder", [Vector2(0.2, -top + 0.006), Vector2(0.34, -top + 0.006), Vector2(0.352, -top - 0.024),
		Vector2(0.21, -top - 0.034)], 0.03, 0.007, 0.008, 3), "olive_dark")
	b.add(ext("p_shoulder_pad", [Vector2(0.336, -top - 0.002), Vector2(0.356, -top - 0.004), Vector2(0.356, -top - 0.028),
		Vector2(0.34, -top - 0.028)], 0.0305, 0.004, 0.004), "rubber")
	# Gefechtskopf (Tandem-Hohlladung) mit Abstandssonde und Leitwerk
	var g: String = "Magazine"
	b.add(_cached("pzf_head", func() -> ArrayMesh: return lathe(PackedVector2Array([Vector2(0.0, -0.44), Vector2(0.034, -0.44),
		Vector2(0.034, -0.495), Vector2(0.052, -0.53), Vector2(0.0565, -0.56), Vector2(0.0565, -0.64), Vector2(0.05, -0.69),
		Vector2(0.036, -0.73), Vector2(0.022, -0.75), Vector2(0.0, -0.752)]), 36, 0.003)), "olive_head", Transform3D.IDENTITY, g)
	b.add(cylz(0.0575, -0.6, -0.585, 36, 0.0008), "yellow", Transform3D.IDENTITY, g)
	b.add(cylz(0.0575, -0.545, -0.539, 36, 0.0006), "olive_dark", Transform3D.IDENTITY, g)
	b.add(_cached("pzf_probe", func() -> ArrayMesh: return lathe(PackedVector2Array([Vector2(0.0, -0.74), Vector2(0.013, -0.74),
		Vector2(0.0115, -0.77), Vector2(0.0115, -0.84), Vector2(0.0102, -0.845), Vector2(0.0102, -0.9), Vector2(0.013, -0.905),
		Vector2(0.013, -0.918), Vector2(0.008, -0.924), Vector2(0.0, -0.925)]), 20, 0.001)), "olive_dark", Transform3D.IDENTITY, g)
	b.add(cylz(0.0132, -0.913, -0.92, 20, 0.0005), "park", Transform3D.IDENTITY, g)
	for k in 4:
		var a: float = TAU * float(k) / 4.0 + PI * 0.25
		b.add(rbox(Vector3(0.003, 0.012, 0.05), 0.001), "olive_dark",
			Transform3D(Basis(Vector3.BACK, a + PI * 0.5), Vector3(cos(a) * 0.03, sin(a) * 0.03, -0.47)), g)
	b.label("HL  DM 12   110 mm", Vector3(0.0567, 0.0, -0.615), Vector3(0, 90, 0), 0.0072, Color(0.1, 0.1, 0.08), g)
	b.label("HL  DM 12   110 mm", Vector3(-0.0567, 0.0, -0.615), Vector3(0, -90, 0), 0.0072, Color(0.1, 0.1, 0.08), g)
	b.meta["muzzle"] = Vector3(0, 0, -0.92)
	b.meta["sight"] = Vector3(-0.044, top + 0.098, -0.05)
	b.meta["length"] = 1.4

## Rakete fuer den Flug (Gefechtskopf + ausgeklapptes Leitwerk), entlang -Z.
static func build_rocket() -> Node3D:
	return _instantiate(_template("rocket", _rocket_parts), "Rocket")

static func _rocket_parts(b: Builder) -> void:
	b.add(_cached("rk_head", func() -> ArrayMesh: return lathe(PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.034, 0.0),
		Vector2(0.034, -0.055), Vector2(0.052, -0.09), Vector2(0.0565, -0.12), Vector2(0.0565, -0.2), Vector2(0.05, -0.25),
		Vector2(0.03, -0.3), Vector2(0.0, -0.312)]), 20, 0.003)), "olive_head")
	b.add(cylz(0.0575, -0.16, -0.145, 20, 0.0008), "yellow")
	b.add(cylz(0.011, -0.3, -0.48, 10), "olive_dark")
	b.add(cylz(0.02, 0.0, 0.3, 12), "olive_dark")
	for k in 4:
		var a: float = TAU * float(k) / 4.0
		b.add(rbox(Vector3(0.003, 0.1, 0.09), 0.0012), "olive_dark",
			Transform3D(Basis(Vector3.BACK, a + PI * 0.5), Vector3(cos(a) * 0.05, sin(a) * 0.05, 0.25)))

# ------------------------------------------------------------------ Kisten (Pickups)

## Munitionskiste (Holz, oliv lackiert, Bundeswehr-Stil) bzw. lange Panzerfaust-Kiste.
## Gibt die Kiste ohne Beschriftung zurueck; Meta "front" = Mitte der Frontflaeche (z) und "size".
static func build_crate(pzf: bool) -> Node3D:
	var id: String = "crate_pzf" if pzf else "crate_ammo"
	var size: Vector3 = Vector3(1.25, 0.34, 0.5) if pzf else Vector3(0.9, 0.42, 0.52)
	return _instantiate(_template(id, func(b: Builder) -> void: _crate_parts(b, size)), id)

static func _crate_parts(b: Builder, size: Vector3) -> void:
	var hx: float = size.x * 0.5
	var hz: float = size.z * 0.5
	var lid_h: float = 0.06
	var body_h: float = size.y - lid_h
	# Korpus aus Brettern (Fugen sichtbar)
	var planks: int = 3
	var ph: float = body_h / float(planks)
	for i in planks:
		var y: float = ph * (float(i) + 0.5)
		b.add(rbox(Vector3(size.x - 0.012, ph - 0.004, size.z - 0.012), 0.004), "crate_wood", T(Vector3(0, y, 0)))
	# Deckel mit Ueberstand und Fuge
	b.add(rbox(Vector3(size.x + 0.012, lid_h - 0.006, size.z + 0.012), 0.006), "crate_wood", T(Vector3(0, body_h + lid_h * 0.5 + 0.002, 0)))
	b.add(rbox(Vector3(size.x - 0.03, 0.012, size.z - 0.03), 0.004), "crate_dark", T(Vector3(0, size.y + 0.004, 0)))
	# Leisten senkrecht (vorn/hinten) und Kufen unten
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			b.add(rbox(Vector3(0.06, body_h + 0.004, 0.022), 0.005), "crate_dark", T(Vector3(sx * (hx - 0.1), body_h * 0.5, sz * (hz + 0.003))))
			# Metall-Eckwinkel
			b.add(rbox(Vector3(0.05, 0.05, 0.05), 0.004), "crate_metal", T(Vector3(sx * (hx - 0.018), size.y - 0.018, sz * (hz - 0.018)), Vector3.ZERO, 1.0))
			b.add(rbox(Vector3(0.05, 0.05, 0.05), 0.004), "crate_metal", T(Vector3(sx * (hx - 0.018), 0.022, sz * (hz - 0.018))))
		b.add(rbox(Vector3(0.07, 0.03, size.z + 0.01), 0.005), "crate_dark", T(Vector3(sx * (hx - 0.12), -0.012, 0)))
		# Seitliche Tragegriffe (Seil in Metallbuegel)
		b.add(rbox(Vector3(0.02, 0.05, 0.16), 0.006), "crate_dark", T(Vector3(sx * (hx + 0.006), body_h * 0.62, 0)))
		var handle := lathe(PackedVector2Array([Vector2(0.032, 0.0), Vector2(0.037, 0.005), Vector2(0.042, 0.0),
			Vector2(0.037, -0.005), Vector2(0.032, 0.0)]), 18, 0.0, true)
		b.add(handle, "crate_metal", Transform3D(Basis(Vector3.BACK, PI * 0.5).scaled(Vector3(1.0, 1.6, 1.0)), Vector3(sx * (hx + 0.02), body_h * 0.45, 0)))
	# Verschluesse vorn (Spannverschluss)
	for sx: float in [-1.0, 1.0]:
		b.add(rbox(Vector3(0.05, 0.07, 0.012), 0.004), "crate_metal", T(Vector3(sx * hx * 0.48, body_h - 0.01, hz + 0.004)))
		b.add(rbox(Vector3(0.03, 0.03, 0.016), 0.006), "crate_metal", T(Vector3(sx * hx * 0.48, body_h - 0.035, hz + 0.008)))
	# Kennzeichnungsstreifen gelb (zwischen den Leisten), auf beiden Laengsseiten
	for sz: float in [-1.0, 1.0]:
		b.add(rbox(Vector3(size.x - 0.32, 0.016, 0.004), 0.001), "yellow", T(Vector3(0, body_h * 0.2, sz * (hz - 0.004))))
	b.meta["size"] = size
	b.meta["body_h"] = body_h

## Kleiner Munitionskasten (Blech, oliv) mit Klappgriff und Kennstreifen.
static func build_ammo_can() -> Node3D:
	return _instantiate(_template("ammo_can", _ammo_can_parts), "AmmoCan")

static func _ammo_can_parts(b: Builder) -> void:
	b.add(rbox(Vector3(0.11, 0.16, 0.26), 0.008), "can_olive", T(Vector3(0, 0.08, 0), Vector3(0, 90, 0)))
	b.add(rbox(Vector3(0.12, 0.028, 0.27), 0.006), "can_olive", T(Vector3(0, 0.172, 0), Vector3(0, 90, 0)))
	b.add(rbox(Vector3(0.112, 0.016, 0.262), 0.002), "yellow", T(Vector3(0, 0.118, 0), Vector3(0, 90, 0)))
	b.add(rbox(Vector3(0.02, 0.012, 0.1), 0.004), "crate_metal", T(Vector3(0, 0.192, 0), Vector3(0, 90, 0)))
	b.add(rbox(Vector3(0.012, 0.05, 0.03), 0.003), "crate_metal", T(Vector3(0.135, 0.15, 0)))
	b.label("5,56 mm", Vector3(0, 0.07, 0.0562), Vector3.ZERO, 0.016, Color(0.85, 0.8, 0.6))

# ------------------------------------------------------------------ AK-74M (CC0-Modell)

## AK-Modell laden und Materialien zuweisen. Teile: Body, Wood (Schaft/Handschutz), Magazine, Charging_Handle.
static func build_ak() -> Node3D:
	if not ResourceLoader.exists(AK_PATH):
		return null
	var ps := load(AK_PATH) as PackedScene
	if ps == null:
		return null
	var model := ps.instantiate() as Node3D
	model.name = "AK74M"
	for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm: String = m.name.to_lower()
		m.mesh = _ak_baked(m.mesh)
		if nm.begins_with("wood"):
			m.material_override = mat("ak_poly")
		elif nm.begins_with("magazine"):
			m.material_override = mat("ak_mag")
		else:
			m.material_override = mat("ak_metal")
	return model

## AK-Meshes ohne UV/Vertexfarben: Kantenmaske fuer gun_surface (COLOR.r = Kante, G = AO) aus harten
## Kanten backen – Vertices gleicher Position mit abweichenden Normalen gelten als Kante. Gecacht.
static func _ak_baked(src: Mesh) -> Mesh:
	if src == null:
		return src
	var key := "ak_bake_%d" % src.get_instance_id()
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var out := ArrayMesh.new()
	for si in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(si)
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var acc: Dictionary = {}
		var keys: Array[Vector3i] = []
		keys.resize(pos.size())
		for i in pos.size():
			var k := Vector3i((pos[i] * 4000.0).round())
			keys[i] = k
			acc[k] = (acc.get(k, Vector3.ZERO) as Vector3) + nrm[i]
		var cols := PackedColorArray()
		cols.resize(pos.size())
		for i in pos.size():
			var avg: Vector3 = (acc[keys[i]] as Vector3).normalized()
			var e := clampf((1.0 - nrm[i].dot(avg)) * 5.0, 0.0, 1.0)
			cols[i] = Color(e, 0.9 - e * 0.15, 0.0, 1.0)
		arr[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(src.surface_get_primitive_type(si), arr)
	_mesh_cache[key] = out
	return out

## Weltmodell fuer Pickups (Layer 1, wirft Schatten). Laenge in Metern als Meta "length".
static func build_world(weapon_id: String) -> Node3D:
	var n: Node3D = null
	match weapon_id:
		"ak74m", "rpk74":
			var ak := build_ak()
			if ak != null:
				n = Node3D.new()
				ak.scale = Vector3.ONE * 1.27
				ak.position = Vector3(0.022, 0.0, 0.0)
				n.add_child(ak)
		"pzf3":
			n = build_pzf()
		"pistol":
			n = Node3D.new()
			var ps := load(PISTOL_PATH) as PackedScene if ResourceLoader.exists(PISTOL_PATH) else null
			if ps != null:
				var pm := ps.instantiate() as Node3D
				pm.rotation_degrees = Vector3(0, 90, 0)
				pm.scale = Vector3.ONE * 0.85
				n.add_child(pm)
			else:
				var b := MeshInstance3D.new()
				b.mesh = rbox(Vector3(0.03, 0.12, 0.19), 0.004)
				b.material_override = mat("park")
				n.add_child(b)
	if n == null:
		n = build_g36c()
		# Liegende Waffe: Holo-Visier mit dazu
		var holo := build_holo()
		holo.position = n.get_meta("optic_mount") as Vector3
		n.add_child(holo)
	# Ab ~35 m ausblenden (kleine Details, spart Draw-Calls/Schatten)
	_set_vis_range(n, 45.0)
	return n

static func _set_vis_range(n: Node, dist: float) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).visibility_range_end = dist
		(n as GeometryInstance3D).visibility_range_end_margin = 4.0
	for c in n.get_children():
		_set_vis_range(c, dist)
