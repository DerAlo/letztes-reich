extends RefCounted
## Stadtkulisse fuer funkturm (Berlin bei Nacht, Ausgangssperre) und Materialien der Messehallen.
## Ersetzt die frueheren untexturierten Quader: Gebaeude mit Fassaden-UV in Metern, Wandtextur (Poly Haven, CC0)
## und prozeduralem Fensterraster (funkturm_city.gdshader), Attika/Gesims, Dachaufbauten, Flugwarnlichter.
## Typen: Altbau-Zeilen (Ziegel/Putz, 4-6 Geschosse, Blockrand), Plattenbauten (WBS 70, 6-22 Geschosse),
## Buerohochhaeuser (Bandfenster) – jeweils mit Hoehen- und Farbvarianz.

const SHADER := preload("res://game/levels/funkturm_city.gdshader")
const FacadeKit = preload("res://game/levels/facade_kit.gd")
const FTEX := "res://assets/environment/facade/textures/"
const PTEX := "res://assets/environment/funkturm/textures/"

## Typ -> [Achsabstand, Geschosshoehe] (muss zum Shader passen; Breiten werden darauf gerastert)
const CELL := {0: Vector2(2.6, 3.4), 1: Vector2(2.6, 3.4), 2: Vector2(3.6, 2.8), 3: Vector2(1.8, 3.6)}

static var _mat: ShaderMaterial = null

static func _base_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tex_brick", load(FTEX + "red_brick_03/diffuse.jpg"))
	m.set_shader_parameter("tex_plaster", load(FTEX + "painted_plaster_wall/diffuse.jpg"))
	m.set_shader_parameter("tex_concrete", load(FTEX + "precast_concrete_wall/diffuse.jpg"))
	m.set_shader_parameter("tex_panel", load(PTEX + "concrete_panels/diffuse.jpg"))
	m.set_shader_parameter("noise_tex", FacadeKit.noise_tex())
	return m

static func city_mat() -> ShaderMaterial:
	if _mat == null:
		_mat = _base_mat()
	return _mat

## Material fuer achsparallele Hallenwaende (Fensterband band_lo..band_hi in Metern ueber base_y).
static func hall_mat(tint: Color, band_lo: float, band_hi: float, seed_v: float, lit: float = 0.55) -> ShaderMaterial:
	var m := _base_mat()
	m.set_shader_parameter("world_mode", true)
	m.set_shader_parameter("w_kind", 4.0)
	m.set_shader_parameter("w_tint", tint)
	m.set_shader_parameter("w_seed", seed_v)
	m.set_shader_parameter("band_lo", band_lo)
	m.set_shader_parameter("band_hi", band_hi)
	m.set_shader_parameter("lit_ratio", lit)
	return m

# --------------------------------------------------------------------------- Mesh-Sammler

class CityMesh:
	var st := SurfaceTool.new()
	var count: int = 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	## Viereck a (unten links), b (unten rechts), c (oben rechts), d (oben links), von aussen gesehen.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, uv2: Vector2, col: Color) -> void:
		var pts := [a, d, c, a, c, b]
		var uvs := [ua, ud, uc, ua, uc, ub]
		for i in 6:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(uvs[i])
			st.set_uv2(uv2)
			st.add_vertex(pts[i])
		count += 1

	## Quader: Grundflaeche um base (y = Unterkante), gedreht um yaw. top_mode >= 0: Waende mit Fenstern bis
	## top_mode (Traufhoehe), sonst ohne Fenster (-1 Dach dunkel, -2 Aufbau/Gesims).
	func box(base: Vector3, yaw: float, w: float, d: float, h: float, seed_v: float, top_mode: float, col: Color, roof: bool = true) -> void:
		var bs := Basis(Vector3.UP, yaw)
		var hx := bs.x * (w * 0.5)
		var hz := bs.z * (d * 0.5)
		var up := Vector3.UP * h
		# Ecken unten: p0 (-x,-z) p1 (+x,-z) p2 (+x,+z) p3 (-x,+z)
		var p := [base - hx - hz, base + hx - hz, base + hx + hz, base - hx + hz]
		var y0 := base.y
		var wall_uv2 := Vector2(seed_v, top_mode)
		# Waende: (links, rechts) von aussen gesehen, Normale, Laenge
		var walls := [[p[3], p[2], bs.z, w], [p[2], p[1], bs.x, d], [p[1], p[0], -bs.z, w], [p[0], p[3], -bs.x, d]]
		for wl in walls:
			var a: Vector3 = wl[0]
			var b: Vector3 = wl[1]
			var n: Vector3 = wl[2]
			var ln: float = wl[3]
			quad(a, b, b + up, a + up, n, Vector2(0, y0), Vector2(ln, y0), Vector2(ln, y0 + h), Vector2(0, y0 + h), wall_uv2, col)
		if roof:
			var r := [p[0] + up, p[1] + up, p[2] + up, p[3] + up]
			var ruv2 := Vector2(seed_v, -1.0 if top_mode >= 0.0 else top_mode)
			quad(r[3], r[2], r[1], r[0], Vector3.UP, Vector2(r[3].x, r[3].z), Vector2(r[2].x, r[2].z), Vector2(r[1].x, r[1].z), Vector2(r[0].x, r[0].z), ruv2, col)

	func build() -> ArrayMesh:
		if count == 0:
			return null
		return st.commit()

# --------------------------------------------------------------------------- Stadt

## Stadt im Ring r_min..r_max um den Ursprung; keep_out: Rechteck (x0, z0, x1, z1), das frei bleibt (Level).
static func build(parent: Node3D, seed_v: int, clusters: int, r_min: float, r_max: float, keep_out: Rect2) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var cm := CityMesh.new()
	var beacons := PackedVector3Array()
	var placed: Array = []   # [Vector2 Mitte, Radius]
	var n_bld := 0
	for i in clusters:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf_range(r_min * r_min, r_max * r_max))
		var c := Vector3(sin(a) * r, 0.0, cos(a) * r)
		var yaw := rng.randf() * TAU
		if rng.randf() < 0.6:
			yaw = atan2(c.x, c.z) + PI * 0.5 * float(rng.randi() % 4)   # Strassenraster grob radial
		var roll := rng.randf()
		var near := r < 230.0
		var kind := 0
		if roll < (0.5 if near else 0.25):
			kind = 0      # Altbauzeile
		elif roll < (0.85 if near else 0.75):
			kind = 2      # Plattenbau
		else:
			kind = 3      # Buero
		var foot := 0.0
		var parts: Array = []   # [lokaler Versatz entlang x, w, d, h, kind, tint]
		if kind == 0:
			# Blockrand: 3-6 Haeuser nebeneinander, unterschiedliche Hoehen, Ziegel oder Putz
			var nh := rng.randi_range(3, 6)
			var dep := rng.randf_range(12.0, 15.0)
			var x := 0.0
			for k in nh:
				var sub := 0 if rng.randf() < 0.45 else 1
				var nw := rng.randi_range(4, 8)
				var w := nw * 2.6
				var fl := rng.randi_range(4, 6)
				var h := fl * 3.4 + 1.6
				var tint := _tint(rng, sub)
				parts.append([x + w * 0.5, w, dep, h, sub, tint])
				x += w
			for pt in parts:
				pt[0] = float(pt[0]) - x * 0.5
			foot = x * 0.5 + dep
		elif kind == 2:
			var nw := rng.randi_range(6, 18)
			var fl := rng.randi_range(6, 11) if rng.randf() < 0.7 else rng.randi_range(14, 22)
			var w := nw * 3.6
			var h := fl * 2.8 + 1.5
			parts.append([0.0, w, 3.6 * rng.randi_range(3, 4), h, 2, _tint(rng, 2)])
			foot = w * 0.5 + 8.0
		else:
			var nw := rng.randi_range(10, 22)
			var fl := rng.randi_range(9, 26)
			var w := nw * 1.8
			var h := fl * 3.6 + 1.8
			parts.append([0.0, w, 1.8 * rng.randi_range(9, 16), h, 3, _tint(rng, 3)])
			foot = maxf(w, 28.0) * 0.6
		# Kollisionen mit Level und Nachbarn vermeiden
		var c2 := Vector2(c.x, c.z)
		var ko := keep_out.grow(foot)
		if ko.has_point(c2):
			continue
		var clash := false
		for pl in placed:
			if c2.distance_to(pl[0]) < foot + float(pl[1]):
				clash = true
				break
		if clash:
			continue
		placed.append([c2, foot])
		var bs := Basis(Vector3.UP, yaw)
		for pt in parts:
			var off: float = pt[0]
			var w: float = pt[1]
			var d: float = pt[2]
			var h: float = pt[3]
			var k: int = pt[4]
			var tint: Color = pt[5]
			var sv := rng.randf()
			var col := Color(tint.r, tint.g, tint.b, float(k) / 8.0)
			var base := c + bs.x * off
			cm.box(base, yaw, w, d, h, sv, h, col)
			n_bld += 1
			# Attika/Gesims: leicht auskragende Kante, darauf ein niedriger Aufbau
			var cap_h := 0.35 if k <= 1 else 0.5
			cm.box(base + Vector3(0, h, 0), yaw, w + 0.5, d + 0.5, cap_h, sv, -2.0, col)
			# Dachaufbauten: Treppenhaus/Aufzug, Lueftung, bei Altbauten Schornsteine
			var nroof := rng.randi_range(1, 3)
			for j in nroof:
				var rw := rng.randf_range(2.0, 5.0)
				var rd := rng.randf_range(2.0, 4.5)
				var rh := rng.randf_range(1.2, 3.2)
				if k <= 1:
					rw = rng.randf_range(0.7, 1.1)
					rd = rw
					rh = rng.randf_range(1.0, 2.2)
				var lx := rng.randf_range(-0.35, 0.35) * w
				var lz := rng.randf_range(-0.3, 0.3) * d
				cm.box(base + bs.x * lx + bs.z * lz + Vector3(0, h + cap_h, 0), yaw, rw, rd, rh, sv, -2.0, col)
			# Antennen/Flugwarnlicht auf hohen Haeusern
			if h > 48.0:
				var top_p := base + Vector3(0, h + cap_h, 0)
				cm.box(top_p + bs.x * (w * 0.3), yaw, 0.18, 0.18, rng.randf_range(4.0, 9.0), sv, -2.0, col)
				beacons.append(top_p + bs.x * (w * 0.5 - 0.3) + bs.z * (d * 0.5 - 0.3) + Vector3(0, 0.4, 0))
				beacons.append(top_p - bs.x * (w * 0.5 - 0.3) - bs.z * (d * 0.5 - 0.3) + Vector3(0, 0.4, 0))
		# Plattenbau: oft mit niedrigerem Seitenfluegel
		if kind == 2 and rng.randf() < 0.35:
			var p0: Array = parts[0]
			var w2 := 3.6 * rng.randi_range(4, 8)
			var h2 := rng.randi_range(4, 6) * 2.8 + 1.5
			var d2 := 3.6 * 3.0
			var base2 := c + bs.x * (float(p0[1]) * 0.5 + w2 * 0.5)
			var tint2: Color = p0[5]
			var sv2 := rng.randf()
			cm.box(base2, yaw, w2, d2, h2, sv2, h2, Color(tint2.r, tint2.g, tint2.b, 2.0 / 8.0))
			cm.box(base2 + Vector3(0, h2, 0), yaw, w2 + 0.4, d2 + 0.4, 0.5, sv2, -2.0, tint2)
	var mi := MeshInstance3D.new()
	mi.name = "CityFacades"
	mi.mesh = cm.build()
	mi.material_override = city_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return {"beacons": beacons, "buildings": n_bld}

## Farbvarianz je Typ: Ziegel rot bis braun, Putz ocker/grau/gebrochen weiss, Beton grau bis beige.
static func _tint(rng: RandomNumberGenerator, kind: int) -> Color:
	var v := rng.randf_range(0.75, 1.05)
	match kind:
		0:
			var t: Array = [Color(0.85, 0.72, 0.65), Color(0.7, 0.58, 0.52), Color(0.8, 0.78, 0.74), Color(0.62, 0.5, 0.45)]
			return (t[rng.randi() % t.size()] as Color) * v
		1:
			var t: Array = [Color(0.92, 0.84, 0.68), Color(0.78, 0.76, 0.72), Color(0.88, 0.72, 0.58), Color(0.7, 0.72, 0.7), Color(0.95, 0.9, 0.82)]
			return (t[rng.randi() % t.size()] as Color) * v
		2:
			var t: Array = [Color(0.85, 0.84, 0.8), Color(0.78, 0.74, 0.66), Color(0.72, 0.74, 0.76), Color(0.9, 0.82, 0.7)]
			return (t[rng.randi() % t.size()] as Color) * v
		_:
			var t: Array = [Color(0.6, 0.62, 0.64), Color(0.78, 0.76, 0.72), Color(0.5, 0.52, 0.55)]
			return (t[rng.randi() % t.size()] as Color) * v
