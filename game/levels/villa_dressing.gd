extends RefCounted
## Level 12 "villa": Ausstattung/Realismus-Pass fuer villa_world.gd. Nur Optik (keine neuen
## Kollisionskoerper, Navmesh unveraendert): Materialien (Rasen, Putz, Parkett, Dachziegel, Kies),
## Grashalme und Wiesenblumen als MultiMesh mit Distanz-Ausblendung, Hecken- und Strauchkarten,
## Laubbaeume, Blumenbeete, Gartenmoebel, Uferfelsen, Hoehenfeld-Berge rund um den Traunsee, Villa
## aussen (Walmdach, Sockel, Fenster mit Faschen/Laeden, Rinnen) und innen (Wandputz, Fussleisten,
## Stuck, Fenster mit Vorhaengen, Gemaelde, Karten, Wandleuchten, Gebrauchsspuren als Decals).
## Alle Funktionen statisch; Aufruf aus VillaWorld.build() bzw. VillaWorld.materials().

const Geo = preload("res://game/levels/level_geo.gd")
const K = preload("res://game/levels/overwatch_world_kit.gd")
const FKit = preload("res://game/levels/facade_kit.gd")
const FAR_CAM = preload("res://game/levels/villa_far_cam.gd")

const VTEX := "res://assets/environment/villa/"
const ETEX := "res://assets/environment/textures/"
const LAWN_SHADER := preload("res://assets/environment/villa/lawn.gdshader")
const GRASS_SHADER := preload("res://assets/environment/villa/grass_blades.gdshader")
const FOLIAGE_SHADER := preload("res://assets/environment/villa/foliage.gdshader")
const MOUNTAIN_SHADER := preload("res://assets/environment/villa/mountains.gdshader")

const FLOOR_Y := 0.1
const STOREY := 3.6
const EAVE := 7.2
const DOOR_H := 2.5

## Hecken (Mitte, Groesse) wie in VillaWorld._garden/_forecourt (dort mit Kollision).
const HEDGES: Array = [
	[Vector3(-16.5, 0.85, 12.0), Vector3(7.0, 1.7, 0.9)],
	[Vector3(-29.0, 0.85, 0.0), Vector3(4.0, 1.7, 0.9)],
	[Vector3(-15.75, 0.85, -4.0), Vector3(6.5, 1.7, 0.9)],
	[Vector3(-27.0, 0.85, -14.0), Vector3(6.0, 1.7, 0.9)],
	[Vector3(-8.0, 0.75, 20.0), Vector3(0.9, 1.5, 8.0)],
	[Vector3(32.0, 0.9, -10.0), Vector3(1.2, 1.8, 30.0)],
]

## Laubbaeume im Garten (Stammkollision bleibt in VillaWorld._trees).
const TREES: Array = [Vector3(-30.0, 0.0, 16.0), Vector3(-21.0, 0.0, 19.0), Vector3(-30.5, 0.0, -7.0),
		Vector3(-9.0, 0.0, -6.0), Vector3(-25.0, 0.0, -33.0)]

## Blumenbeete [xmin, zmin, xmax, zmax] (Erde + Blumen + Straeucher).
const BEDS: Array = [
	[-11.6, -13.3, 3.6, -12.4],      # vor der Villa (Westteil der Suedfassade)
	[-20.0, 12.55, -13.0, 13.4],     # vor der langen Gartenhecke
	[-15.4, 2.6, -12.6, 5.4],        # um die Steinfigur
	[-19.6, -13.8, -12.4, -13.1],    # Terrassenkante Sued
]

static var _cache: Dictionary = {}
static var _noise_h: FastNoiseLite
static var _noise_r: FastNoiseLite
static var _noise_s: FastNoiseLite
static var _noise_d: FastNoiseLite

# ===================================================================== Materialien

static func _tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

## Fassaden-Shader (facade.gdshader) mit eigenem Texturordner.
static func facade(dir: String, tint: Color, scale: float, opts: Dictionary = {}) -> ShaderMaterial:
	var key := "fac|%s|%s|%s|%s" % [dir, tint.to_html(), scale, str(opts)]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = FKit.FACADE_SHADER
	m.set_shader_parameter("base_albedo", _tex(dir + "/diffuse.jpg"))
	m.set_shader_parameter("base_normal", _tex(dir + "/normal.jpg"))
	m.set_shader_parameter("base_arm", _tex(dir + "/arm.jpg"))
	m.set_shader_parameter("detail_normal", _tex(FKit.FTEX + "rough_plaster_broken/normal.jpg"))
	m.set_shader_parameter("noise_tex", FKit.noise_tex())
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("base_scale", scale)
	for k: String in opts:
		m.set_shader_parameter(k, opts[k])
	_cache[key] = m
	return m

static func lawn_mat() -> ShaderMaterial:
	if _cache.has("lawn"):
		return _cache["lawn"]
	var m := ShaderMaterial.new()
	m.shader = LAWN_SHADER
	m.set_shader_parameter("base_albedo", _tex(VTEX + "leafy_grass/diffuse.jpg"))
	m.set_shader_parameter("base_normal", _tex(VTEX + "leafy_grass/normal.jpg"))
	m.set_shader_parameter("base_arm", _tex(VTEX + "leafy_grass/arm.jpg"))
	m.set_shader_parameter("noise_tex", FKit.noise_tex())
	_cache["lawn"] = m
	return m

static func foliage_mat(tex: String, tint: Color, tint2: Color, wind: float, back: Color = Color(0.3, 0.36, 0.1)) -> ShaderMaterial:
	var key := "fol|%s|%s|%s|%s" % [tex, tint.to_html(), tint2.to_html(), wind]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("leaf_tex", _tex(VTEX + "leaves/" + tex))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("tint2", tint2)
	m.set_shader_parameter("wind", wind)
	m.set_shader_parameter("backlight_color", back)
	_cache[key] = m
	return m

static func grass_mat(meadow: bool) -> ShaderMaterial:
	var key := "grass|%s" % meadow
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = GRASS_SHADER
	m.set_shader_parameter("noise_tex", FKit.noise_tex())
	if meadow:
		m.set_shader_parameter("tip_color", Color(0.25, 0.3, 0.11))
		m.set_shader_parameter("tip_dry", Color(0.42, 0.38, 0.17))
		m.set_shader_parameter("dry_amount", 0.45)
		m.set_shader_parameter("wind", 0.09)
	else:
		m.set_shader_parameter("tip_color", Color(0.2, 0.29, 0.1))
		m.set_shader_parameter("tip_dry", Color(0.3, 0.32, 0.13))
		m.set_shader_parameter("dry_amount", 0.2)
		m.set_shader_parameter("wind", 0.04)
	_cache[key] = m
	return m

## Ersetzt/ergaenzt Eintraege der Materialtabelle von VillaWorld.
static func apply_materials(m: Dictionary) -> void:
	m["grass"] = lawn_mat()
	m["gravel"] = K.matte(K.pbr(VTEX + "gravel_floor_02", Color(0.86, 0.82, 0.76), 0.42, 1.0))
	# Aussenputz (gebrochenes Weiss/Ocker, Spritzschmutz am Sockel, leichte Schlieren)
	m["plaster"] = facade(VTEX + "beige_wall_001", Color(1.32, 1.27, 1.16), 0.38,
			{"grime_amount": 0.45, "grime_height": 1.1, "streaks": 0.28, "variation": 0.12, "base_y": 0.0})
	m["plaster_dark"] = facade(VTEX + "beige_wall_001", Color(0.9, 0.86, 0.78), 0.38,
			{"grime_amount": 0.3, "grime_height": 0.6, "streaks": 0.35, "variation": 0.14, "base_y": 0.0})
	# Innenputz: hell, Gebrauchsschmutz knapp ueber dem Boden
	m["plaster_in"] = facade(VTEX + "plastered_wall_04", Color(0.93, 0.89, 0.8), 0.45,
			{"grime_amount": 0.32, "grime_height": 0.45, "streaks": 0.0, "variation": 0.07, "base_y": FLOOR_Y,
			"grime_color": Color(0.32, 0.27, 0.2), "detail_strength": 0.15})
	m["ceiling"] = facade(VTEX + "plastered_wall_04", Color(0.9, 0.88, 0.82), 0.4,
			{"grime_amount": 0.0, "streaks": 0.0, "variation": 0.1, "detail_strength": 0.1})
	m["sandstone"] = FKit.facade_mat("sandstone", Color(0.86, 0.8, 0.7), {"grime_amount": 0.5, "grime_height": 0.5, "streaks": 0.15})
	m["fasche"] = facade(VTEX + "beige_wall_001", Color(1.55, 1.52, 1.45), 0.5, {"grime_amount": 0.0, "streaks": 0.2, "variation": 0.06})
	m["parquet"] = K.pbr(VTEX + "herringbone_parquet", Color(0.78, 0.62, 0.48), 0.55, 0.75)
	m["roof"] = K.pbr(VTEX + "grey_roof_tiles", Color(0.62, 0.6, 0.6), 0.5, 1.0)
	# Heckenkern (Kollisionsquader, scheint durch Laubluecken): dunkles Laubgruen statt Schwarz
	m["hedge"] = Geo.flat(Color(0.07, 0.1, 0.05), 1.0)
	m["skirting"] = Geo.flat(Color(0.8, 0.78, 0.72), 0.45)
	m["stucco"] = Geo.flat(Color(0.9, 0.88, 0.82), 0.7)
	m["shutter"] = Geo.flat(Color(0.12, 0.2, 0.14), 0.6)
	m["zinc"] = Geo.flat(Color(0.42, 0.44, 0.45), 0.45, 0.6)
	m["gilt"] = Geo.flat(Color(0.55, 0.42, 0.2), 0.38, 0.85)
	m["soil"] = K.matte(K.pbr(ETEX + "gravel", Color(0.28, 0.22, 0.17), 0.9, 1.0))
	m["curtain"] = Geo.flat(Color(0.36, 0.07, 0.06), 0.95)
	m["linen"] = Geo.flat(Color(0.78, 0.72, 0.6), 0.95)
	m["teak"] = Geo.flat(Color(0.42, 0.3, 0.2), 0.7)
	m["canvas"] = Geo.flat(Color(0.82, 0.78, 0.66), 0.95)
	m["dusk_glass"] = Geo.flat(Color(0.02, 0.025, 0.04), 0.06, 0.0, Color(0.22, 0.3, 0.45), 0.45)
	m["shade"] = Geo.flat(Color(0.9, 0.8, 0.62), 0.8, 0.0, Color(1.0, 0.78, 0.5), 2.2)
	m["rock"] = K.matte(K.pbr(ETEX + "rock_face_03", Color(0.62, 0.6, 0.56), 0.4, 1.0))

# ===================================================================== Geometrie-Helfer

## Laubkarten-Sammler (eine Fl. = 2 Dreiecke, Normalen vom Volumenzentrum nach aussen).
class Cards:
	var st := SurfaceTool.new()
	var count: int = 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func card(c: Vector3, ax: Vector3, ay: Vector3, vol_c: Vector3, up_bias: float, col: Color) -> void:
		var p: Array[Vector3] = [c - ax - ay, c + ax - ay, c + ax + ay, c - ax + ay]
		var uv: Array[Vector2] = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			var v := p[idx]
			var n := (v - vol_c).normalized() + Vector3.UP * up_bias
			st.set_normal(n.normalized())
			st.set_color(col)
			st.set_uv(uv[idx])
			st.add_vertex(v)
		count += 1

	func node(mat: Material, name: String, shadows: bool = true) -> MeshInstance3D:
		if count == 0:
			return null
		var mi := MeshInstance3D.new()
		mi.name = name
		mi.mesh = st.commit()
		mi.material_override = mat
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

## Kartenachsen (halbe Kantenvektoren) fuer eine Karte mit ungefaehrer Normale d.
static func _axes(d: Vector3, w: float, h: float, rng: RandomNumberGenerator) -> Array[Vector3]:
	var t := d.cross(Vector3.UP)
	if t.length() < 0.15:
		t = d.cross(Vector3.RIGHT)
	t = t.normalized()
	var b := t.cross(d).normalized()
	var a := rng.randf() * TAU
	return [(t * cos(a) + b * sin(a)) * w * 0.5, (-t * sin(a) + b * cos(a)) * h * 0.5]

static func _rand_dir(rng: RandomNumberGenerator) -> Vector3:
	var z := rng.randf_range(-1.0, 1.0)
	var a := rng.randf() * TAU
	var r := sqrt(1.0 - z * z)
	return Vector3(cos(a) * r, z, sin(a) * r)

## Dreieck mit korrekter Wicklung (Godot: im Uhrzeigersinn = Vorderseite) zur Normale n.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
		var tu := uvb
		uvb = uvc
		uvc = tu
	for e: Array in [[a, uva], [b, uvb], [c, uvc]]:
		st.set_normal(n)
		st.set_uv(e[1])
		st.add_vertex(e[0])

static func _basis_n(n: Vector3) -> Basis:
	return FKit.basis_for(n)

## Decal auf einer Flaeche mit Normale n (Wand, Boden, Decke). size = Breite x Hoehe auf der Flaeche.
static func decal(parent: Node3D, pos: Vector3, n: Vector3, w: float, h: float, tex: String, alpha: float = 1.0, depth: float = 0.3, roll: float = 0.0) -> Decal:
	var d := Decal.new()
	d.texture_albedo = _tex(VTEX + "decals/" + tex)
	d.modulate = Color(1, 1, 1, alpha)
	d.size = Vector3(w, depth, h)
	d.normal_fade = 0.4
	d.upper_fade = 0.15
	d.lower_fade = 0.15
	d.distance_fade_enabled = true
	d.distance_fade_begin = 28.0
	d.distance_fade_length = 6.0
	var y := n.normalized()
	var x := Vector3.UP.cross(y)
	if x.length() < 0.1:
		x = Vector3.RIGHT
	x = x.normalized()
	var z := x.cross(y).normalized()
	d.transform = Transform3D(Basis(x, y, z).rotated(y, roll), pos)
	parent.add_child(d)
	return d

# ===================================================================== Gelaende-Hoehe (Level)

## Bodenhoehe im Levelbereich (Wiese y = 0, Boeschung z 48..70, Plateau y = 5).
static func ground_y(x: float, z: float) -> float:
	if x >= -20.0 and x <= 30.0:
		if z >= 70.0:
			return 5.0
		if z >= 48.0:
			return (z - 48.0) / 22.0 * 5.0
	return 0.0

# ===================================================================== Gras und Blumen

static func _blade(st: SurfaceTool, root: Vector3, yaw: float, height: float, half_w: float, lean: float, uvx: float) -> void:
	var fwd := Vector3(cos(yaw), 0.0, sin(yaw))
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var r0 := root - side * half_w
	var r1 := root + side * half_w
	var m0 := root - side * half_w * 0.7 + fwd * lean * 0.3 + Vector3.UP * height * 0.5
	var m1 := root + side * half_w * 0.7 + fwd * lean * 0.3 + Vector3.UP * height * 0.5
	var tip := root + fwd * lean + Vector3.UP * height
	var n := fwd * -1.0
	for v: Array in [[r0, 0.0], [r1, 0.0], [m1, 0.5], [r0, 0.0], [m1, 0.5], [m0, 0.5], [m0, 0.5], [m1, 0.5], [tip, 1.0]]:
		st.set_normal(n)
		st.set_uv(Vector2(uvx, float(v[1])))
		st.add_vertex(v[0])

## Grasbueschel (Hoehe 1 m, wird pro Instanz skaliert).
static func _clump_mesh(blades: int, radius: float, seed_v: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in blades:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius
		var root := Vector3(cos(a) * r, 0.0, sin(a) * r)
		_blade(st, root, rng.randf() * TAU, rng.randf_range(0.55, 1.0), rng.randf_range(0.008, 0.014), rng.randf_range(0.08, 0.35), 0.0)
	return st.commit()

## Bluete: wenige Halme + Stiele mit flachem Bluetenkopf (UV.x = 2 -> Farbe aus INSTANCE_CUSTOM).
static func _flower_mesh(seed_v: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		_blade(st, Vector3(rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.05, 0.05)), rng.randf() * TAU, rng.randf_range(0.4, 0.7), 0.01, 0.12, 0.0)
	for i in 3:
		var root := Vector3(rng.randf_range(-0.06, 0.06), 0.0, rng.randf_range(-0.06, 0.06))
		var h := rng.randf_range(0.75, 1.0)
		var lean := Vector3(rng.randf_range(-0.08, 0.08), 0.0, rng.randf_range(-0.08, 0.08))
		_blade(st, root, rng.randf() * TAU, h, 0.004, 0.04, 0.0)
		var top := root + lean * 0.3 + Vector3.UP * h
		var rad := rng.randf_range(0.035, 0.05)
		var tilt := Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.1, 0.5))
		for k in 6:
			var a0 := TAU * k / 6.0
			var a1 := TAU * (k + 1) / 6.0
			var p0 := top + tilt * Vector3(cos(a0) * rad, 0.0, sin(a0) * rad)
			var p1 := top + tilt * Vector3(cos(a1) * rad, 0.0, sin(a1) * rad)
			var c := top + tilt * Vector3(0, 0.012, 0)
			for v: Vector3 in [c, p0, p1]:
				st.set_normal(tilt * Vector3.UP)
				st.set_uv(Vector2(2.0, 1.0))
				st.add_vertex(v)
	return st.commit()

static func _excluded(x: float, z: float, rects: Array) -> bool:
	for r: Array in rects:
		if x > float(r[0]) and x < float(r[2]) and z > float(r[1]) and z < float(r[3]):
			return true
	return false

static func _dist_rects(x: float, z: float, rects: Array) -> float:
	var best := 1e9
	for r: Array in rects:
		var dx := maxf(maxf(float(r[0]) - x, x - float(r[2])), 0.0)
		var dz := maxf(maxf(float(r[1]) - z, z - float(r[3])), 0.0)
		best = minf(best, sqrt(dx * dx + dz * dz))
	return best

## Gras (MultiMesh in 16-m-Kacheln, ohne Kollision, ohne Schatten) und Wiesenblumen.
static func grass(lv: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 18062030
	var hedge_rects: Array = []
	for hd: Array in HEDGES:
		var c: Vector3 = hd[0]
		var s: Vector3 = hd[1]
		hedge_rects.append([c.x - s.x * 0.5, c.z - s.z * 0.5, c.x + s.x * 0.5, c.z + s.z * 0.5])
	var excl: Array = [
		[-12.7, -32.7, 12.7, -13.3], [3.8, -14.0, 8.2, -10.8], [-20.2, -30.4, -11.8, -13.8],
		[-28.7, 13.8, -26.3, 21.7], [-26.7, -10.2, -22.3, 14.2], [-22.7, -14.2, -17.8, -9.8],
		[10.3, -2.2, 17.7, 30.2], [1.8, -13.2, 26.2, 7.2], [-32.2, 21.8, -22.8, 34.2],
		[-7.2, -44.2, -4.8, -35.8], [-7.2, -37.7, 11.2, -35.3], [8.8, -36.2, 11.2, -31.8],
		[22.4, 4.6, 25.6, 11.4], [40.5, -60.0, 49.5, 170.0], [-23.2, 29.55, 34.45, 30.45],
		[33.55, -44.0, 34.45, 30.45], [-31.0, 7.0, -30.2, 9.0], [9.0, 7.4, 10.2, 24.6],
		[29.5, 87.5, 38.5, 91.5],
	]
	for r: Array in hedge_rects:
		excl.append([float(r[0]) - 0.12, float(r[1]) - 0.12, float(r[2]) + 0.12, float(r[3]) + 0.12])
	for b: Array in BEDS:
		excl.append(b)
	var edges: Array = hedge_rects + [[-12.6, -32.6, 12.6, -13.4], [-23.0, 29.75, 34.25, 30.25], [33.75, -44.0, 34.25, 30.25],
			[-32.0, 22.0, -23.0, 34.0], [-20.0, -30.0, -12.0, -14.0]]
	var chunk := 16.0
	var bins: Dictionary = {}   # key -> {"lawn": [], "meadow": [], "flower": []}
	var x0 := -32.0
	var z0 := -44.0
	var x1 := 40.0
	var z1 := 104.0
	var step := 0.5
	var nx := int((x1 - x0) / step)
	var nz := int((z1 - z0) / step)
	var flower_cols: Array[Color] = [Color(0.92, 0.92, 0.86), Color(0.95, 0.78, 0.12), Color(0.5, 0.36, 0.78),
			Color(0.92, 0.92, 0.86), Color(0.8, 0.16, 0.1), Color(0.95, 0.85, 0.3)]
	for ix in nx:
		for iz in nz:
			var bx := x0 + ix * step
			var bz := z0 + iz * step
			if bz > 48.0 and (bx < -20.0 or bx > 30.0):
				continue
			var in_estate := bx < 33.7 and bz < 29.7
			var per := 3 if in_estate else 2
			for k in per:
				var x := bx + rng.randf() * step
				var z := bz + rng.randf() * step
				if _excluded(x, z, excl):
					continue
				var y := ground_y(x, z)
				var de := _dist_rects(x, z, edges)
				var tree_d := 1e9
				for tp: Vector3 in TREES:
					tree_d = minf(tree_d, Vector2(x - tp.x, z - tp.z).length())
				var kind := "lawn"
				var h := rng.randf_range(0.1, 0.19)
				if not in_estate:
					kind = "meadow"
					h = rng.randf_range(0.28, 0.6)
				elif de < 0.9 or tree_d < 1.4:
					h = rng.randf_range(0.24, 0.42)
				elif de < 1.8:
					h = rng.randf_range(0.15, 0.28)
				var key := Vector2i(int(floor((x - x0) / chunk)), int(floor((z - z0) / chunk)))
				if not bins.has(key):
					bins[key] = {"lawn": [], "meadow": [], "flower": []}
				var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.8, 1.3), h, rng.randf_range(0.8, 1.3))), Vector3(x, y - 0.01, z))
				(bins[key][kind] as Array).append(xf)
				# Wiesenblumen (wenige Gaensebluemchen im Rasen)
				var fp := 0.11 if kind == "meadow" else (0.008 if de > 1.0 else 0.0)
				if rng.randf() < fp:
					var fh := rng.randf_range(0.32, 0.6) if kind == "meadow" else rng.randf_range(0.1, 0.16)
					var col := flower_cols[rng.randi() % flower_cols.size()] if kind == "meadow" else flower_cols[0]
					var fx := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.0, fh, 1.0)), Vector3(x + 0.1, y - 0.01, z))
					(bins[key]["flower"] as Array).append([fx, col])
	var clump := _clump_mesh(14, 0.13, 7)
	var flower := _flower_mesh(11)
	var root := Node3D.new()
	root.name = "VillaGrass"
	lv.add_child(root)
	for key: Vector2i in bins:
		var b: Dictionary = bins[key]
		for kind: String in ["lawn", "meadow"]:
			var arr: Array = b[kind]
			if arr.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = clump
			mm.instance_count = arr.size()
			for i in arr.size():
				mm.set_instance_transform(i, arr[i])
			root.add_child(_mm_node(mm, grass_mat(kind == "meadow"), 40.0))
		var fl: Array = b["flower"]
		if not fl.is_empty():
			root.add_child(_flower_node(flower, fl, 40.0))

static func _mm_node(mm: MultiMesh, mat: Material, vis_end: float) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = vis_end
	mi.visibility_range_end_margin = 4.0
	return mi

static func _flower_node(mesh: Mesh, items: Array, vis_end: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_custom_data(i, items[i][1])
	var mat := grass_mat(true)
	return _mm_node(mm, mat, vis_end)

# ===================================================================== Hecken, Straeucher, Beete

## Laubhuelle um die Heckenquader (Kollision bleibt an den Quadern in VillaWorld).
static func hedges(lv: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4411
	var cards := Cards.new()
	for hd: Array in HEDGES:
		var c: Vector3 = hd[0]
		var s: Vector3 = hd[1]
		var lo := c - s * 0.5
		var faces: Array = [
			[Vector3.UP, Vector2(s.x, s.z)], [Vector3.RIGHT, Vector2(s.z, s.y)], [Vector3.LEFT, Vector2(s.z, s.y)],
			[Vector3.BACK, Vector2(s.x, s.y)], [Vector3.FORWARD, Vector2(s.x, s.y)],
		]
		for f: Array in faces:
			var n: Vector3 = f[0]
			var dim: Vector2 = f[1]
			var sp := 0.2
			var nu := maxi(1, int(dim.x / sp))
			var nv := maxi(1, int(dim.y / sp))
			for iu in nu:
				for iv in nv:
					var u := (iu + rng.randf()) / nu
					var v := (iv + rng.randf()) / nv
					var p: Vector3
					if n == Vector3.UP:
						p = Vector3(lo.x + u * s.x, lo.y + s.y, lo.z + v * s.z)
					elif absf(n.x) > 0.5:
						p = Vector3(c.x + n.x * s.x * 0.5, lo.y + v * s.y, lo.z + u * s.z)
					else:
						p = Vector3(lo.x + u * s.x, lo.y + v * s.y, c.z + n.z * s.z * 0.5)
					if n != Vector3.UP and p.y < lo.y + 0.12:
						continue
					# knapp vor der Quaderflaeche (frueher bis 10 cm darin -> der Quader schien flaechig durch)
					p += n * rng.randf_range(-0.03, 0.09)
					var d := (n + _rand_dir(rng) * 0.4).normalized()
					var sz := rng.randf_range(0.38, 0.52)
					var ax := _axes(d, sz, sz, rng)
					var hrel := clampf((p.y - lo.y) / s.y, 0.0, 1.0)
					var col := Color(0.25 + hrel * 0.25, rng.randf(), lerpf(0.45, 1.0, hrel))
					var vol := p - n * 0.9
					cards.card(p, ax[0], ax[1], vol, 0.25, col)
	var mi := cards.node(hedge_mat(), "HedgeLeaves")
	mi.visibility_range_end = 160.0
	lv.add_child(mi)

## Heckenlaub: eigenes Material (nicht aus dem foliage_mat-Cache), damit die Schattenseite nicht schwarz
## absackt: hellere Blatt-Albedo, weniger Innen-Verschattung, Transluzenz im Gegenlicht und eine
## schwache Himmels-Aufhellung (Streulicht durchs Laub).
static func hedge_mat() -> ShaderMaterial:
	if _cache.has("hedge_leaves"):
		return _cache["hedge_leaves"]
	var m := ShaderMaterial.new()
	m.shader = FOLIAGE_SHADER
	m.set_shader_parameter("leaf_tex", _tex(VTEX + "leaves/leaf_cluster.png"))
	m.set_shader_parameter("tint", Color(0.5, 0.6, 0.36))
	m.set_shader_parameter("tint2", Color(0.56, 0.62, 0.38))
	m.set_shader_parameter("wind", 0.012)
	m.set_shader_parameter("backlight_color", Color(0.26, 0.32, 0.1))
	m.set_shader_parameter("shade_floor", 0.6)
	m.set_shader_parameter("ao_floor", 0.7)
	m.set_shader_parameter("fill_color", Vector3(0.34, 0.4, 0.52))
	_cache["hedge_leaves"] = m
	return m

## Kugeliger Strauch aus Laubkarten.
static func _bush(cards: Cards, c: Vector3, r: Vector3, n_cards: int, rng: RandomNumberGenerator, size: float = 0.45) -> void:
	for i in n_cards:
		var dir := _rand_dir(rng)
		if dir.y < -0.3:
			dir.y = -dir.y * 0.3
		var rr := pow(rng.randf(), 0.35)
		var p := c + Vector3(dir.x * r.x, dir.y * r.y, dir.z * r.z) * rr
		var d := (dir + _rand_dir(rng) * 0.5).normalized()
		var sz := size * rng.randf_range(0.8, 1.2)
		var ax := _axes(d, sz, sz, rng)
		cards.card(p, ax[0], ax[1], c - Vector3(0, r.y * 0.4, 0), 0.2, Color(rr * 0.6, rng.randf(), lerpf(0.4, 1.0, rr * (0.6 + dir.y * 0.4))))

## Blumenbeete, Kuebelpflanzen, Terrassen-Urnen.
static func beds(lv: Node3D, mats: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7731
	var parts := FKit.Parts.new()
	var bush := Cards.new()
	var flowers: Array = []
	var bed_cols: Array[Color] = [Color(0.72, 0.08, 0.1), Color(0.9, 0.55, 0.62), Color(0.95, 0.94, 0.88),
			Color(0.5, 0.42, 0.78), Color(0.95, 0.78, 0.2)]
	for b: Array in BEDS:
		var lo := Vector2(float(b[0]), float(b[1]))
		var hi := Vector2(float(b[2]), float(b[3]))
		var cc := (lo + hi) * 0.5
		var sz := hi - lo
		parts.box("soil", Vector3(cc.x, 0.02, cc.y), Vector3(sz.x, 0.05, sz.y))
		# Kantensteine
		parts.box("stone", Vector3(cc.x, 0.04, lo.y), Vector3(sz.x + 0.1, 0.09, 0.08))
		parts.box("stone", Vector3(cc.x, 0.04, hi.y), Vector3(sz.x + 0.1, 0.09, 0.08))
		parts.box("stone", Vector3(lo.x, 0.04, cc.y), Vector3(0.08, 0.09, sz.y))
		parts.box("stone", Vector3(hi.x, 0.04, cc.y), Vector3(0.08, 0.09, sz.y))
		# Straeucher (Buchs, Rosen) in Abstaenden, Blumen dazwischen
		var n_b := maxi(1, int(maxf(sz.x, sz.y) / 1.6))
		for i in n_b:
			var t := (i + 0.5) / n_b
			var p := Vector3(lo.x + sz.x * (t if sz.x >= sz.y else 0.5), 0.0, lo.y + sz.y * (t if sz.y > sz.x else 0.5))
			var rad := minf(sz.x, sz.y) * 0.5
			_bush(bush, p + Vector3(0, 0.32, 0), Vector3(rad * 0.9, 0.36, rad * 0.9), 40, rng, 0.5)
		var area := sz.x * sz.y
		var main_col := bed_cols[rng.randi() % bed_cols.size()]
		for i in int(area * 28.0):
			var x := rng.randf_range(lo.x + 0.08, hi.x - 0.08)
			var z := rng.randf_range(lo.y + 0.08, hi.y - 0.08)
			var col := main_col if rng.randf() < 0.65 else bed_cols[rng.randi() % bed_cols.size()]
			var fx := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.2, rng.randf_range(0.3, 0.55), 1.2)), Vector3(x, 0.03, z))
			flowers.append([fx, col])
	# Kuebelpflanzen an der Auffahrt (Steinkuebel mit Kollision in VillaWorld)
	for z: float in [24.0, 16.0, 8.0]:
		_bush(bush, Vector3(9.6, 1.15, z), Vector3(0.55, 0.45, 0.55), 55, rng, 0.55)
	# Steinurnen mit Buchs an der Terrasse
	for p: Vector3 in [Vector3(-19.4, 0.12, -15.0), Vector3(-12.9, 0.12, -29.1)]:
		parts.cyl("stone", p + Vector3(0, 0.25, 0), 0.22, 0.5, Basis.IDENTITY, 12)
		parts.cyl("stone", p + Vector3(0, 0.62, 0), 0.34, 0.24, Basis.IDENTITY, 14)
		_bush(bush, p + Vector3(0, 1.0, 0), Vector3(0.36, 0.34, 0.36), 36, rng, 0.45)
	parts.build(lv, mats)
	var bm := bush.node(foliage_mat("leaf_cluster.png", Color(0.4, 0.5, 0.3), Color(0.5, 0.56, 0.32), 0.03, Color(0.2, 0.26, 0.07)), "Bushes")
	bm.visibility_range_end = 120.0
	lv.add_child(bm)
	var fm := _flower_node(_flower_mesh(23), flowers, 45.0)
	fm.name = "BedFlowers"
	lv.add_child(fm)

# ===================================================================== Laubbaeume

static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, seg: int) -> void:
	var d := (b - a).normalized()
	var t := d.cross(Vector3.UP)
	if t.length() < 0.1:
		t = d.cross(Vector3.RIGHT)
	t = t.normalized()
	var u := d.cross(t).normalized()
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var n0 := t * cos(a0) + u * sin(a0)
		var n1 := t * cos(a1) + u * sin(a1)
		var p00 := a + n0 * ra
		var p01 := a + n1 * ra
		var p10 := b + n0 * rb
		var p11 := b + n1 * rb
		var nf := ((n0 + n1) * 0.5).normalized()
		_tri(st, p00, p01, p11, nf, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
		_tri(st, p00, p11, p10, nf, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))

## Laubbaeume (Stamm + Aeste aus Rinde, Krone aus Laubbuescheln). Kollision der Staemme in VillaWorld.
static func broadleaf_trees(lv: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2030
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cards := Cards.new()
	for base: Vector3 in TREES:
		var sc := rng.randf_range(0.9, 1.15)
		# Stamm leicht gekruemmt
		var pts: Array[Vector3] = [base + Vector3(0, -0.1, 0)]
		var lean := Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		for k in 4:
			var t := float(k + 1) / 4.0
			pts.append(base + Vector3(0, 3.6 * sc * t, 0) + lean * t * t + Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08)))
		for k in 4:
			_tube(bark, pts[k], pts[k + 1], lerpf(0.3, 0.13, k / 4.0) * sc, lerpf(0.3, 0.13, (k + 1) / 4.0) * sc, 9)
		_tube(bark, base + Vector3(0, -0.1, 0), base + Vector3(0, 0.35, 0), 0.42 * sc, 0.3 * sc, 9)
		var crown_c := base + lean + Vector3(0, 5.0 * sc, 0)
		var radii := Vector3(rng.randf_range(2.5, 3.0), rng.randf_range(2.1, 2.5), rng.randf_range(2.5, 3.0)) * sc
		# Hauptaeste
		var n_br := 6
		var tips: Array[Vector3] = []
		for k in n_br:
			var a := TAU * k / n_br + rng.randf_range(-0.3, 0.3)
			var y0 := rng.randf_range(2.3, 3.4) * sc
			var p0 := base + Vector3(0, y0, 0) + lean * (y0 / (3.6 * sc))
			var dir := Vector3(cos(a), rng.randf_range(0.6, 1.1), sin(a)).normalized()
			var p1 := p0 + dir * rng.randf_range(1.6, 2.5) * sc
			_tube(bark, p0, p1, 0.1 * sc, 0.035, 6)
			var dir2 := (dir + Vector3(rng.randf_range(-0.4, 0.4), 0.4, rng.randf_range(-0.4, 0.4))).normalized()
			var p2 := p1 + dir2 * rng.randf_range(0.8, 1.4) * sc
			_tube(bark, p1, p2, 0.035, 0.015, 5)
			tips.append(p2)
		# Krone: Laubbuescheln in einem Ellipsoid (Huelle dichter), zwei Teilkronen
		var subs: Array = [[crown_c, radii, 70], [crown_c + Vector3(rng.randf_range(-0.8, 0.8), radii.y * 0.55, rng.randf_range(-0.8, 0.8)), radii * 0.62, 28]]
		for sub: Array in subs:
			var cc: Vector3 = sub[0]
			var rr3: Vector3 = sub[1]
			for i in int(sub[2]):
				var dir := _rand_dir(rng)
				var rr := pow(rng.randf(), 0.3)
				var p := cc + Vector3(dir.x * rr3.x, dir.y * rr3.y * 0.9, dir.z * rr3.z) * rr
				var d := (dir * 1.2 + _rand_dir(rng) * 0.7).normalized()
				var s := rng.randf_range(1.5, 2.2) * sc
				var ax := _axes(d, s, s, rng)
				var shade := clampf(rr * 0.75 + (dir.y * 0.5 + 0.5) * 0.35, 0.0, 1.0)
				cards.card(p, ax[0], ax[1], crown_c - Vector3(0, radii.y * 0.3, 0), 0.25, Color(rr, rng.randf(), shade))
		for tp: Vector3 in tips:
			for i in 3:
				var d := _rand_dir(rng)
				var ax := _axes(d, 1.4, 1.4, rng)
				cards.card(tp + d * 0.3, ax[0], ax[1], crown_c, 0.25, Color(0.8, rng.randf(), 0.75))
	var bm := Geo.mesh_node(bark.commit(), K.pbr(ETEX + "pine_bark", Color(0.62, 0.58, 0.52), 0.9, 1.0), Vector3.ZERO)
	bm.name = "BroadleafBark"
	lv.add_child(bm)
	var lm := cards.node(foliage_mat("leaf_cluster.png", Color(0.5, 0.6, 0.36), Color(0.66, 0.66, 0.36), 0.05, Color(0.3, 0.38, 0.1)), "BroadleafCrowns")
	lv.add_child(lm)

# ===================================================================== Garten-Ausstattung

## Kantensteine am Gartenweg, Wegleuchten, Liegestuehle, Pavillon-Moebel, Uferfelsen.
static func garden_props(lv: Node3D, mats: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 919
	var parts := FKit.Parts.new()
	# Weg-Kanten (niedrig, nur Optik)
	var segs: Array = [[-28.5, 14.0, -26.5, 21.5], [-26.5, -10.0, -22.5, 14.0], [-22.5, -14.0, -18.0, -10.0]]
	for sg: Array in segs:
		var ax0 := float(sg[0])
		var az0 := float(sg[1])
		var ax1 := float(sg[2])
		var az1 := float(sg[3])
		var lz := az1 - az0
		var lx := ax1 - ax0
		for xx: float in [ax0, ax1]:
			parts.box("stone", Vector3(xx, 0.04, (az0 + az1) * 0.5), Vector3(0.1, 0.08, lz))
		if lx > 4.1:
			parts.box("stone", Vector3((ax0 + ax1) * 0.5, 0.04, az0), Vector3(lx, 0.08, 0.1))
	# Wegleuchten (Poller) mit warmem Glas
	for p: Vector3 in [Vector3(-26.8, 0, 8.0), Vector3(-22.2, 0, 0.0), Vector3(-26.8, 0, -6.0), Vector3(-28.8, 0, 17.5), Vector3(-17.7, 0, -12.0)]:
		parts.cyl("iron", p + Vector3(0, 0.3, 0), 0.07, 0.6, Basis.IDENTITY, 10)
		parts.cyl("lamp_glow", p + Vector3(0, 0.68, 0), 0.075, 0.16, Basis.IDENTITY, 10)
		parts.box("iron", p + Vector3(0, 0.79, 0), Vector3(0.2, 0.04, 0.2))
	# Liegestuehle und Beistelltisch auf dem Rasen vor der Villa (nur Optik)
	for k in 2:
		var o := Vector3(-4.5 + k * 1.6, 0.0, 3.5)
		var yaw := deg_to_rad(-15.0 + k * 22.0)
		var R := Basis(Vector3.UP, yaw)
		parts.box("teak", o + R * Vector3(0, 0.3, 0.4), Vector3(0.62, 0.05, 1.3), R)
		parts.box("teak", o + R * Vector3(0, 0.6, -0.55), Vector3(0.62, 0.05, 0.85), R * Basis(Vector3.RIGHT, deg_to_rad(-50.0)))
		parts.box("linen", o + R * Vector3(0, 0.36, 0.35), Vector3(0.56, 0.06, 1.2), R)
		for sx: float in [-0.28, 0.28]:
			for sz: float in [-0.1, 0.95]:
				parts.box("teak", o + R * Vector3(sx, 0.15, sz), Vector3(0.05, 0.3, 0.05), R)
	parts.cyl("teak", Vector3(-3.7, 0.5, 2.6), 0.32, 0.04, Basis.IDENTITY, 16)
	parts.cyl("teak", Vector3(-3.7, 0.25, 2.6), 0.03, 0.5, Basis.IDENTITY, 8)
	# Pavillon: runder Tisch und zwei Stuehle (Optik)
	parts.cyl("white_paint", Vector3(-29.0, 0.72, -22.0), 0.55, 0.04, Basis.IDENTITY, 18)
	parts.cyl("white_paint", Vector3(-29.0, 0.36, -22.0), 0.04, 0.72, Basis.IDENTITY, 8)
	for a: float in [0.4, 2.6]:
		var cp := Vector3(-29.0 + cos(a) * 0.9, 0.0, -22.0 + sin(a) * 0.9)
		var R2 := Basis(Vector3.UP, -a + PI * 0.5)
		parts.box("white_paint", cp + Vector3(0, 0.45, 0), Vector3(0.42, 0.04, 0.42), R2)
		parts.box("white_paint", cp + R2 * Vector3(0, 0.75, 0.2), Vector3(0.42, 0.55, 0.03), R2)
		parts.box("white_paint", cp + Vector3(0, 0.22, 0), Vector3(0.05, 0.44, 0.05), R2)
	# Rosenbogen am Weg zum Bootshaus (Optik)
	for sx: float in [-28.9, -26.1]:
		parts.box("iron", Vector3(sx, 1.1, 21.9), Vector3(0.04, 2.2, 0.04))
	parts.box("iron", Vector3(-27.5, 2.22, 21.9), Vector3(2.85, 0.04, 0.04))
	parts.build(lv, mats, ["lamp_glow"])
	# Kletterrose ueber dem Bogen
	var c := Cards.new()
	for i in 34:
		var t := rng.randf()
		var p := Vector3(-28.9 + t * 2.8, 2.25, 21.9) if rng.randf() < 0.5 else Vector3(-28.9 if rng.randf() < 0.5 else -26.1, rng.randf_range(0.4, 2.2), 21.9)
		var d := _rand_dir(rng)
		var ax := _axes(d, 0.5, 0.5, rng)
		c.card(p + d * 0.12, ax[0], ax[1], p, 0.2, Color(0.5, rng.randf(), 0.8))
	var cm := c.node(foliage_mat("leaf_cluster.png", Color(0.4, 0.5, 0.3), Color(0.5, 0.5, 0.3), 0.04), "RoseArch")
	lv.add_child(cm)
	var roses: Array = []
	for i in 40:
		var p := Vector3(rng.randf_range(-28.9, -26.1), 2.2 + rng.randf_range(-0.05, 0.15), 21.9 + rng.randf_range(-0.25, 0.25)) if i < 24 \
				else Vector3(-28.9 if i % 2 == 0 else -26.1, rng.randf_range(0.5, 2.1), 21.9 + rng.randf_range(-0.2, 0.2))
		roses.append([Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(1.6, 0.12, 1.6)), p), Color(0.7, 0.06, 0.1)])
	lv.add_child(_flower_node(_flower_mesh(31), roses, 45.0))
	# Uferfelsen (im Wasser vor der Kaimauer, West- und Nordufer) und einzelne Findlinge im Garten
	var rocks := SurfaceTool.new()
	rocks.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rp: Array = []
	for i in 22:
		rp.append([Vector3(rng.randf_range(-35.5, -33.0), -0.6, rng.randf_range(-42.0, 20.0)), rng.randf_range(0.6, 1.4)])
	for i in 16:
		var x := rng.randf_range(-30.0, 30.0)
		if x > -9.0 and x < -3.0:
			continue
		rp.append([Vector3(x, -0.6, rng.randf_range(-47.5, -45.2)), rng.randf_range(0.6, 1.3)])
	rp.append([Vector3(-13.0, -0.25, 5.8), 0.55])
	rp.append([Vector3(-15.3, -0.25, 2.4), 0.4])
	rp.append([Vector3(-31.0, -0.3, -11.0), 0.7])
	for r: Array in rp:
		_rock(rocks, r[0], float(r[1]), rng)
	rocks.generate_normals()
	var rm := Geo.mesh_node(rocks.commit(), mats["rock"], Vector3.ZERO)
	rm.name = "ShoreRocks"
	lv.add_child(rm)

## Unregelmaessiger Felsbrocken (verformte Kugel).
static func _rock(st: SurfaceTool, c: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var rings := 5
	var seg := 8
	var scale := Vector3(rng.randf_range(0.9, 1.4), rng.randf_range(0.55, 0.8), rng.randf_range(0.8, 1.2)) * r
	var yaw := Basis(Vector3.UP, rng.randf() * TAU)
	var grid: Array = []
	for i in rings + 1:
		var row: Array[Vector3] = []
		var th := PI * i / rings
		for j in seg:
			var ph := TAU * j / seg
			var dir := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var k := rng.randf_range(0.8, 1.15)
			if i == 0 or i == rings:
				k = 1.0
			var v := dir * k
			if v.y < -0.3:
				v.y = -0.3
			row.append(c + yaw * Vector3(v.x * scale.x, v.y * scale.y, v.z * scale.z))
		grid.append(row)
	for i in rings:
		for j in seg:
			var a: Vector3 = grid[i][j]
			var b: Vector3 = grid[i][(j + 1) % seg]
			var cc: Vector3 = grid[i + 1][(j + 1) % seg]
			var d: Vector3 = grid[i + 1][j]
			var n := ((a + b + cc + d) * 0.25 - c).normalized()
			_tri(st, a, b, cc, n, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
			_tri(st, a, cc, d, n, Vector2(0, 0), Vector2(1, 1), Vector2(0, 1))

# ===================================================================== Berge

static func _noises() -> void:
	if _noise_h != null:
		return
	_noise_h = FastNoiseLite.new()
	_noise_h.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_h.frequency = 1.0 / 420.0
	_noise_h.fractal_octaves = 3
	_noise_h.seed = 31
	_noise_r = FastNoiseLite.new()
	_noise_r.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_r.frequency = 1.0 / 1700.0
	_noise_r.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise_r.fractal_octaves = 5
	_noise_r.fractal_gain = 0.4   # vorher 0.5: zu viele Nadelspitzen (Dolomiten statt Traunstein-Massiv)
	_noise_r.seed = 1806
	_noise_s = FastNoiseLite.new()
	_noise_s.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_s.frequency = 1.0 / 260.0
	_noise_s.seed = 77
	# Detail der Bergflanken: Seitengrate und Rinnen (ridged, ~250 m), damit die Silhouette nicht aus
	# glatten Dreieckszacken besteht
	_noise_d = FastNoiseLite.new()
	_noise_d.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_d.frequency = 1.0 / 520.0
	_noise_d.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise_d.fractal_octaves = 3
	_noise_d.seed = 4242

## Gelaendehoehe rund um den See (Weltkoordinaten). Im Levelbereich tief (unter dem Levelboden).
static func terrain_h(x: float, z: float) -> float:
	_noises()
	if x > -32.0 and x < 110.0 and z > -44.0 and z < 160.0:
		return -8.0
	var ex := (x + 60.0) / 410.0
	var ez := (z + 80.0) / 320.0
	var s_lake := (sqrt(ex * ex + ez * ez) - 1.0 + _noise_s.get_noise_2d(x, z) * 0.07) * 330.0
	var dqx := maxf(-32.0 - x, 0.0)
	var dqz := maxf(-44.0 - z, 0.0)
	var s_q: float
	if dqx == 0.0 and dqz == 0.0:
		var dbx := maxf(x - 110.0, 0.0)
		var dbz := maxf(z - 160.0, 0.0)
		s_q = sqrt(dbx * dbx + dbz * dbz) + 2.0
	else:
		s_q = -sqrt(dqx * dqx + dqz * dqz)
	var s := maxf(s_lake, s_q)
	if s < 0.0:
		return maxf(-2.0 + s * 0.12, -45.0)
	var hills := _noise_h.get_noise_2d(x, z) * 0.5 + 0.5
	var ridge := clampf(_noise_r.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var shore := 0.6 + minf(s, 40.0) * 0.05
	var hl := smoothstep(15.0, 420.0, s) * (30.0 + 150.0 * hills)
	var mt := smoothstep(300.0, 1800.0, s) * (100.0 + 900.0 * pow(ridge, 1.7))
	var det := clampf(_noise_d.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	mt += smoothstep(250.0, 1200.0, s) * (30.0 + mt * 0.12) * (det - 0.45)
	return shore + hl + mt

## Hoehenfeld-Mesh (Polarraster um den See) mit Berg-Shader.
static func mountains(lv: Node3D) -> void:
	var cx := -60.0
	var cz := -80.0
	var rings := 132
	var seg := 640
	var r0 := 90.0
	var r1 := 7000.0
	var grid: Array = []
	for i in rings + 1:
		var r := r0 * pow(r1 / r0, float(i) / rings)
		var row := PackedVector3Array()
		row.resize(seg)
		for j in seg:
			var a := TAU * j / seg
			var x := cx + cos(a) * r
			var z := cz + sin(a) * r
			row[j] = Vector3(x, terrain_h(x, z), z)
		grid.append(row)
	# Direkt als Arrays (feineres Raster: ~85k Punkte; SurfaceTool waere hier spuerbar langsamer)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	verts.resize((rings + 1) * seg)
	norms.resize((rings + 1) * seg)
	for i in rings + 1:
		var row: PackedVector3Array = grid[i]
		var prev: PackedVector3Array = grid[maxi(i - 1, 0)]
		var nxt: PackedVector3Array = grid[mini(i + 1, rings)]
		for j in seg:
			var tr := nxt[j] - prev[j]
			var ta := row[(j + 1) % seg] - row[(j - 1 + seg) % seg]
			var n := ta.cross(tr).normalized()
			if n.y < 0.0:
				n = -n
			verts[i * seg + j] = row[j]
			norms[i * seg + j] = n
	var idx := PackedInt32Array()
	idx.resize(rings * seg * 6)
	var k := 0
	for i in rings:
		var ri: PackedVector3Array = grid[i]
		var rn: PackedVector3Array = grid[i + 1]
		for j in seg:
			var j1 := (j + 1) % seg
			var a := i * seg + j
			var b := i * seg + j1
			var c := (i + 1) * seg + j1
			var d := (i + 1) * seg + j
			# Wicklung: im Uhrzeigersinn von oben gesehen
			if (ri[j1] - ri[j]).cross(rn[j1] - ri[j]).y > 0.0:
				idx[k] = a; idx[k + 1] = c; idx[k + 2] = b
				idx[k + 3] = a; idx[k + 4] = d; idx[k + 5] = c
			else:
				idx[k] = a; idx[k + 1] = b; idx[k + 2] = c
				idx[k + 3] = a; idx[k + 4] = c; idx[k + 5] = d
			k += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_INDEX] = idx
	var amesh := ArrayMesh.new()
	amesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var m := ShaderMaterial.new()
	m.shader = MOUNTAIN_SHADER
	m.set_shader_parameter("rock_albedo", _tex(ETEX + "rock_face_03/diffuse.jpg"))
	m.set_shader_parameter("noise_tex", FKit.noise_tex())
	# Dunstfarbe zur Sonne hin warm: Richtung aus dem Sonnenlicht des Levels
	for dl in lv.find_children("*", "DirectionalLight3D", true, false):
		var l := dl as DirectionalLight3D
		if l.sky_mode != DirectionalLight3D.SKY_MODE_SKY_ONLY and l.light_energy > 0.5:
			m.set_shader_parameter("sun_dir", l.global_transform.basis.z.normalized())
			break
	var mi := MeshInstance3D.new()
	mi.name = "Traunsee_Berge"
	mi.mesh = amesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lv.add_child(mi)
	# Kameras: Sichtweite fuer die Berge
	var fc := Node.new()
	fc.name = "VillaFarCam"
	fc.set_script(FAR_CAM)
	lv.add_child(fc)

## Ufer-Lichtpunkt: vom Seezentrum nach aussen bis Land, dann knapp ueber dem Gelaende.
static func shore_point(p: Vector3) -> Vector3:
	var c := Vector2(-60.0, -80.0)
	var d := Vector2(p.x, p.z) - c
	var dir := d.normalized()
	var q := Vector2(p.x, p.z)
	for k in 80:
		var h := terrain_h(q.x, q.y)
		if h > 0.8:
			return Vector3(q.x, h + p.y * 0.4 + 0.6, q.y)
		q += dir * 8.0
	return p

# ===================================================================== Villa aussen

## Walmdach mit Ziegel-UVs, Firstziegel, Traufbrett, Untersicht, Rinnen und Fallrohre.
static func villa_roof(lv: Node3D, mats: Dictionary) -> void:
	var x0 := -12.8
	var x1 := 12.8
	var z0 := -32.8
	var z1 := -13.2
	var ye := EAVE + 0.2
	var rise := 3.6
	var half := (z1 - z0) * 0.5
	var zc := (z0 + z1) * 0.5
	var yr := ye + rise
	var rx0 := x0 + half
	var rx1 := x1 - half
	var slope_len := sqrt(half * half + rise * rise)
	var ts := 0.55   # Ziegel-Kacheln pro Meter
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ang := atan2(rise, half)
	# Sued (+z) und Nord (-z)
	for side: float in [1.0, -1.0]:
		var ze := zc + side * half
		var n := Vector3(0, cos(ang), side * sin(ang))
		var a := Vector3(x0, ye, ze)
		var b := Vector3(x1, ye, ze)
		var c := Vector3(rx1, yr, zc)
		var d := Vector3(rx0, yr, zc)
		var ua := Vector2(x0 * ts, 0.0)
		var ub := Vector2(x1 * ts, 0.0)
		var uc := Vector2(rx1 * ts, -slope_len * ts)
		var ud := Vector2(rx0 * ts, -slope_len * ts)
		_tri(st, a, b, c, n, ua, ub, uc)
		_tri(st, a, c, d, n, ua, uc, ud)
	# Walmflaechen West/Ost
	for side: float in [-1.0, 1.0]:
		var xe := x0 if side < 0.0 else x1
		var rxe := rx0 if side < 0.0 else rx1
		var n := Vector3(side * sin(ang), cos(ang), 0).normalized()
		var a := Vector3(xe, ye, z0)
		var b := Vector3(xe, ye, z1)
		var c := Vector3(rxe, yr, zc)
		_tri(st, a, b, c, n, Vector2(z0 * ts, 0), Vector2(z1 * ts, 0), Vector2(zc * ts, -slope_len * ts))
	st.generate_tangents()
	var rm := StandardMaterial3D.new()
	rm.albedo_texture = _tex(VTEX + "grey_roof_tiles/diffuse.jpg")
	rm.albedo_color = Color(0.66, 0.6, 0.58)
	rm.normal_enabled = true
	rm.normal_texture = _tex(VTEX + "grey_roof_tiles/normal.jpg")
	rm.roughness_texture = _tex(VTEX + "grey_roof_tiles/arm.jpg")
	rm.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	rm.ao_enabled = true
	rm.ao_texture = _tex(VTEX + "grey_roof_tiles/arm.jpg")
	rm.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	rm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var roof := Geo.mesh_node(st.commit(), rm, Vector3.ZERO)
	roof.name = "VillaRoof"
	lv.add_child(roof)
	var parts := FKit.Parts.new()
	# Firstziegel (First + Grate)
	parts.box("roof_ridge", Vector3(0, yr + 0.06, zc), Vector3(rx1 - rx0 + 0.2, 0.16, 0.3))
	for e: Array in [[Vector3(x0, ye, z0), Vector3(rx0, yr, zc)], [Vector3(x0, ye, z1), Vector3(rx0, yr, zc)],
			[Vector3(x1, ye, z0), Vector3(rx1, yr, zc)], [Vector3(x1, ye, z1), Vector3(rx1, yr, zc)]]:
		var a: Vector3 = e[0]
		var b: Vector3 = e[1]
		var dd := b - a
		var fwd := dd.normalized()
		var side := fwd.cross(Vector3.UP).normalized()
		var up := fwd.cross(side).normalized()
		if up.y < 0.0:
			up = -up
			side = -side
		parts.box("roof_ridge", (a + b) * 0.5 + up * 0.07, Vector3(0.28, 0.14, dd.length()), Basis(side, up, fwd).orthonormalized())
	# Traufbrett und Untersicht
	for side: float in [-1.0, 1.0]:
		parts.box("timber_dark", Vector3(0, ye - 0.08, zc + side * half), Vector3(x1 - x0, 0.2, 0.05))
		parts.box("timber_dark", Vector3(x0 if side < 0.0 else x1, ye - 0.08, zc), Vector3(0.05, 0.2, z1 - z0))
	parts.box("plaster_dark", Vector3(0, ye - 0.02, zc), Vector3(x1 - x0, 0.04, z1 - z0))
	# Rinnen und Fallrohre (Zink)
	for side: float in [-1.0, 1.0]:
		parts.cyl("zinc", Vector3(0, ye - 0.05, zc + side * (half + 0.08)), 0.075, x1 - x0, Basis(Vector3.FORWARD, PI * 0.5), 8)
		parts.cyl("zinc", Vector3(x0 - 0.08 if side < 0.0 else x1 + 0.08, ye - 0.05, zc), 0.075, z1 - z0, Basis(Vector3.RIGHT, PI * 0.5), 8)
	for c: Array in [[Vector3(-12.0, 0, -13.825), Vector3.BACK], [Vector3(12.0, 0, -13.825), Vector3.BACK],
			[Vector3(-12.0, 0, -32.175), Vector3.FORWARD], [Vector3(12.0, 0, -32.175), Vector3.FORWARD]]:
		var o: Vector3 = c[0]
		var n: Vector3 = c[1]
		var px := o + Vector3(signf(o.x) * -0.35, 0, 0)
		FKit.downpipe(parts, px, n, 0.0, ye - 0.15, "zinc")
		parts.box("zinc", Vector3(px.x, ye - 0.12, px.z) + n * 0.45, Vector3(0.1, 0.1, 0.75), _basis_n(n))
	# Schornsteinkoepfe
	for cp: Vector3 in [Vector3(0.4, EAVE + 5.0, -27.0), Vector3(-6.0, EAVE + 4.3, -20.0)]:
		parts.box("sandstone", cp + Vector3(0, 0.05, 0), Vector3(1.1, 0.12, 1.1))
		parts.box("dark", cp + Vector3(0, 0.12, 0), Vector3(0.5, 0.04, 0.5))
	var pm := mats.duplicate()
	pm["roof_ridge"] = K.pbr(VTEX + "grey_roof_tiles", Color(0.5, 0.46, 0.45), 1.2, 1.0)
	parts.build(lv, pm)

## Sockel (Sandstein), Fenster mit Faschen, Verdachung, Sohlbank, Interior-Mapping-Glas, Laeden.
static func villa_facade(lv: Node3D, mats: Dictionary) -> void:
	var parts := FKit.Parts.new()
	var wins := FKit.WindowBatch.new()
	var xa := -12.0
	var xb := 12.0
	var za := -32.0
	var zb := -14.0
	var t := 0.175
	# Sockelband (0..0.75 m) mit Abdeckung, Tueroeffnungen frei
	var sides: Array = [
		["z", zb + t, xa - t, xb + t, Vector3.BACK, [[4.8, 7.2]]],
		["z", za - t, xa - t, xb + t, Vector3.FORWARD, [[9.3, 10.7]]],
		["x", xa - t, za - t, zb + t, Vector3.LEFT, [[-24.0, -21.6]]],
		["x", xb + t, za - t, zb + t, Vector3.RIGHT, []],
	]
	for sd: Array in sides:
		var fixed: float = sd[1]
		var n: Vector3 = sd[4]
		var spans := _spans(float(sd[2]), float(sd[3]), sd[5])
		for sp: Vector2 in spans:
			var mid := (sp.x + sp.y) * 0.5
			var ln := sp.y - sp.x
			var c := Vector3(mid, 0.0, fixed) if sd[0] == "z" else Vector3(fixed, 0.0, mid)
			var size := Vector3(ln, 0.75, 0.06) if sd[0] == "z" else Vector3(0.06, 0.75, ln)
			parts.box("sandstone", c + Vector3(0, 0.375, 0) + n * 0.03, size)
			var cap := Vector3(ln + 0.02, 0.06, 0.1) if sd[0] == "z" else Vector3(0.1, 0.06, ln + 0.02)
			parts.box("sandstone", c + Vector3(0, 0.78, 0) + n * 0.05, cap)
	# Fenster (gleiche Positionen wie zuvor in VillaWorld._villa)
	var fronts: Array = [
		["z", zb + t, xa, xb, [6.0], Vector3.BACK, [[4.8, 7.2]]],
		["z", za - t, xa, xb, [10.0], Vector3.FORWARD, [[9.3, 10.7]]],
		["x", xa - t, za, zb, [-22.8], Vector3.LEFT, [[-24.0, -21.6]]],
		["x", xb + t, za, zb, [], Vector3.RIGHT, []],
	]
	var w := 1.1
	var h := 1.6
	for f: Array in fronts:
		var fixed: float = f[1]
		var a: float = f[2]
		var b: float = f[3]
		var skip: Array = f[4]
		var n: Vector3 = f[5]
		var R := _basis_n(n)
		var tv := R.x
		var cnt := int((b - a) / 3.0)
		for i in cnt:
			var u := a + 1.5 + i * 3.0
			var skip_this := false
			for s: float in skip:
				if absf(u - s) < 1.6:
					skip_this = true
			for floor_i in 2:
				if floor_i == 0 and skip_this:
					continue
				var y := 1.8 if floor_i == 0 else 5.3
				var o := Vector3(u, y, fixed) if f[0] == "z" else Vector3(fixed, y, u)
				var lit := (i + floor_i * 3) % 4 != 1
				# Glas mit Raum dahinter (Interior Mapping), etwas zurueckgesetzt hinter die Fasche
				wins.add(o + n * 0.025, n, w - 0.08, h - 0.08, 0.9 if lit else 0.04, 0.85, float(i * 7 + floor_i * 3) * 0.137, false)
				# Blendrahmen + Kreuzstock (weiss)
				var fc := o + n * 0.06
				parts.box("white_paint", fc + Vector3.UP * (h * 0.5 - 0.035), Vector3(w, 0.07, 0.07), R)
				parts.box("white_paint", fc - Vector3.UP * (h * 0.5 - 0.035), Vector3(w, 0.07, 0.07), R)
				parts.box("white_paint", fc + tv * (w * 0.5 - 0.035), Vector3(0.07, h, 0.07), R)
				parts.box("white_paint", fc - tv * (w * 0.5 - 0.035), Vector3(0.07, h, 0.07), R)
				parts.box("white_paint", fc, Vector3(0.05, h, 0.06), R)
				parts.box("white_paint", fc + Vector3.UP * (h * 0.22), Vector3(w, 0.05, 0.06), R)
				# Fasche (Putzband um die Oeffnung, steht vor -> wirkt wie Laibung)
				var fw := 0.16
				var fd := 0.11
				var fcen := o + n * (fd * 0.5)
				parts.box("fasche", fcen + Vector3.UP * (h * 0.5 + fw * 0.5), Vector3(w + fw * 2.0, fw, fd), R)
				parts.box("fasche", fcen + tv * (w * 0.5 + fw * 0.5), Vector3(fw, h, fd), R)
				parts.box("fasche", fcen - tv * (w * 0.5 + fw * 0.5), Vector3(fw, h, fd), R)
				# Sohlbank (Sandstein) und im Erdgeschoss Verdachung
				parts.box("sandstone", o + n * 0.1 - Vector3.UP * (h * 0.5 + 0.04), Vector3(w + 0.44, 0.08, 0.2), R)
				if floor_i == 0:
					parts.box("fasche", o + n * 0.1 + Vector3.UP * (h * 0.5 + fw + 0.06), Vector3(w + 0.5, 0.1, 0.2), R)
					parts.box("fasche", o + n * 0.07 + Vector3.UP * (h * 0.5 + fw + 0.0), Vector3(w + 0.38, 0.05, 0.14), R)
				# Klappladen, geoeffnet, mit Lamellen
				for sgn: float in [-1.0, 1.0]:
					var sc := o + tv * sgn * (w * 0.5 + fw + 0.04 + 0.25) + n * 0.03
					var su := sc.x if f[0] == "z" else sc.z
					var hits_gap := false
					for g: Array in f[6]:
						if floor_i == 0 and su + 0.3 > float(g[0]) and su - 0.3 < float(g[1]):
							hits_gap = true
					if hits_gap:
						continue
					parts.box("shutter", sc + Vector3.UP * (h * 0.5 - 0.0), Vector3(0.5, 0.06, 0.04), R)
					parts.box("shutter", sc - Vector3.UP * (h * 0.5 - 0.0), Vector3(0.5, 0.06, 0.04), R)
					parts.box("shutter", sc + tv * 0.22, Vector3(0.06, h + 0.06, 0.04), R)
					parts.box("shutter", sc - tv * 0.22, Vector3(0.06, h + 0.06, 0.04), R)
					for k in 13:
						var yy := -h * 0.5 + 0.1 + k * (h - 0.2) / 12.0
						parts.box("shutter", sc + Vector3.UP * yy, Vector3(0.4, 0.06, 0.012), R * Basis(Vector3.RIGHT, 0.6))
	# Gesimsband unter der Traufe (Konsolen) und Haustuer
	for sd: Array in sides:
		var fixed: float = sd[1]
		var n: Vector3 = sd[4]
		var a := float(sd[2])
		var b := float(sd[3])
		var cnt := int((b - a) / 0.9)
		for i in cnt:
			var u := a + 0.45 + i * 0.9
			var c := Vector3(u, EAVE - 0.32, fixed) if sd[0] == "z" else Vector3(fixed, EAVE - 0.32, u)
			parts.box("white_paint", c + n * 0.08, Vector3(0.1, 0.16, 0.16), _basis_n(n))
	# Haustuer (Doppelfluegel, zurueckgesetzt) + Oberlicht unter dem Vordach
	parts.box("white_paint", Vector3(4.75, FLOOR_Y + 1.3, -13.78), Vector3(0.12, 2.6, 0.1))
	parts.box("white_paint", Vector3(7.25, FLOOR_Y + 1.3, -13.78), Vector3(0.12, 2.6, 0.1))
	parts.box("white_paint", Vector3(6.0, FLOOR_Y + 2.62, -13.78), Vector3(2.62, 0.14, 0.1))
	parts.build(lv, mats, ["white_paint"])
	var g := wins.build_node(FKit.window_mat("night"))
	if g != null:
		g.name = "VillaWindows"
		lv.add_child(g)

## Teilt [a, b] an den Luecken gaps = [[g0, g1], ...] in Abschnitte.
static func _spans(a: float, b: float, gaps: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var x := a
	var gs := gaps.duplicate()
	gs.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	for g: Array in gs:
		if float(g[0]) > x:
			out.append(Vector2(x, float(g[0])))
		x = maxf(x, float(g[1]))
	if b > x:
		out.append(Vector2(x, b))
	return out

# ===================================================================== Villa innen

## Wandflaechen innen: [achse, fester Wert, von, bis, Normale, Tuerluecken, aussenwand?]
static func _inner_faces() -> Array:
	var zi_front := -14.175
	var zi_back := -31.825
	var xi_w := -11.825
	var xi_e := 11.825
	return [
		# Salon
		["z", zi_front, xi_w, -0.125, Vector3.FORWARD, [], true],
		["z", zi_back, xi_w, -0.125, Vector3.BACK, [], true],
		["x", xi_w, zi_back, zi_front, Vector3.RIGHT, [[-24.0, -21.6]], true],
		["x", -0.125, zi_back, zi_front, Vector3.LEFT, [[-18.8, -17.2]], false],
		# Halle
		["z", zi_front, 0.125, xi_e, Vector3.FORWARD, [[4.8, 7.2]], true],
		["z", -21.875, 0.125, xi_e, Vector3.BACK, [[5.1, 6.9]], false],
		["x", 0.125, -21.875, zi_front, Vector3.RIGHT, [[-18.8, -17.2]], false],
		["x", xi_e, -21.875, zi_front, Vector3.LEFT, [], true],
		# Bibliothek
		["z", zi_back, 0.125, xi_e, Vector3.BACK, [[9.3, 10.7]], true],
		["z", -22.125, 0.125, xi_e, Vector3.FORWARD, [[5.1, 6.9]], false],
		["x", 0.125, zi_back, -22.125, Vector3.RIGHT, [], false],
		["x", xi_e, zi_back, -22.125, Vector3.LEFT, [], true],
	]

static func _fp(axis: String, fixed: float, u: float, y: float) -> Vector3:
	return Vector3(u, y, fixed) if axis == "z" else Vector3(fixed, y, u)

static func _fs(axis: String, along: float, h: float, depth: float) -> Vector3:
	return Vector3(along, h, depth) if axis == "z" else Vector3(depth, h, along)

static func interior(lv: Node3D, mats: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1230
	var parts := FKit.Parts.new()
	var deco := Node3D.new()
	deco.name = "VillaInteriorDeco"
	lv.add_child(deco)
	var y0 := FLOOR_Y
	var hh := STOREY - FLOOR_Y
	for f: Array in _inner_faces():
		var ax: String = f[0]
		var fixed: float = f[1]
		var n: Vector3 = f[4]
		var gaps: Array = f[5]
		var outer: bool = f[6]
		# Innenputz vor den Aussenwaenden (Aussenwaende haben Fassadenputz)
		if outer:
			for sp: Vector2 in _spans(float(f[2]), float(f[3]), gaps):
				parts.box("plaster_in", _fp(ax, fixed, (sp.x + sp.y) * 0.5, y0 + hh * 0.5) + n * 0.01, _fs(ax, sp.y - sp.x, hh, 0.02))
			for g: Array in gaps:
				var gl := float(g[1]) - float(g[0])
				parts.box("plaster_in", _fp(ax, fixed, (float(g[0]) + float(g[1])) * 0.5, y0 + DOOR_H + (hh - DOOR_H) * 0.5) + n * 0.01, _fs(ax, gl, hh - DOOR_H, 0.02))
		# Fussleisten und Stuckleiste
		for sp: Vector2 in _spans(float(f[2]), float(f[3]), gaps):
			var mid := (sp.x + sp.y) * 0.5
			parts.box("skirting", _fp(ax, fixed, mid, y0 + 0.07) + n * 0.035, _fs(ax, sp.y - sp.x, 0.14, 0.03))
			parts.box("skirting", _fp(ax, fixed, mid, y0 + 0.145) + n * 0.03, _fs(ax, sp.y - sp.x, 0.015, 0.02))
		parts.box("stucco", _fp(ax, fixed, (float(f[2]) + float(f[3])) * 0.5, STOREY - 0.07) + n * 0.05, _fs(ax, float(f[3]) - float(f[2]), 0.14, 0.1))
		parts.box("stucco", _fp(ax, fixed, (float(f[2]) + float(f[3])) * 0.5, STOREY - 0.17) + n * 0.03, _fs(ax, float(f[3]) - float(f[2]), 0.05, 0.06))
		# Tuerrahmen (Bekleidung)
		for g: Array in gaps:
			var g0 := float(g[0])
			var g1 := float(g[1])
			parts.box("white_paint", _fp(ax, fixed, g0 - 0.06, y0 + (DOOR_H + 0.1) * 0.5) + n * 0.02, _fs(ax, 0.12, DOOR_H + 0.1, 0.03))
			parts.box("white_paint", _fp(ax, fixed, g1 + 0.06, y0 + (DOOR_H + 0.1) * 0.5) + n * 0.02, _fs(ax, 0.12, DOOR_H + 0.1, 0.03))
			parts.box("white_paint", _fp(ax, fixed, (g0 + g1) * 0.5, y0 + DOOR_H + 0.08) + n * 0.02, _fs(ax, g1 - g0 + 0.24, 0.14, 0.035))
			# Griffspuren neben der Tuer, Schmutz an der Schwelle
			var hs := g0 - 0.3 if rng.randf() < 0.5 else g1 + 0.3
			decal(deco, _fp(ax, fixed, hs, y0 + 1.15), n, 0.36, 0.75, "handmarks.png", 0.75, 0.2)
			var thr := _fp(ax, fixed, (g0 + g1) * 0.5, y0) + n * 0.45
			decal(deco, thr, Vector3.UP, (g1 - g0) * 0.9, 0.9, "smudge.png", 0.45, 0.2)
		# Sockelschmutz und Schrammen entlang der Waende
		var length := float(f[3]) - float(f[2])
		var cnt := int(length / 3.2)
		for i in cnt:
			var u := float(f[2]) + (i + rng.randf_range(0.3, 0.7)) * length / cnt
			var in_gap := false
			for g: Array in gaps:
				if u > float(g[0]) - 1.0 and u < float(g[1]) + 1.0:
					in_gap = true
			if in_gap:
				continue
			decal(deco, _fp(ax, fixed, u, y0 + 0.3), n, rng.randf_range(1.8, 2.8), 0.5, "smudge.png", rng.randf_range(0.45, 0.8), 0.18)
			if rng.randf() < 0.45:
				decal(deco, _fp(ax, fixed, u + rng.randf_range(-0.8, 0.8), y0 + rng.randf_range(0.55, 1.0)), n, 1.1, 0.55, "scuffs.png", rng.randf_range(0.5, 0.85), 0.16, rng.randf_range(-0.1, 0.1))
	# Decke (heller Putz) je Raum
	for r: Array in [[-11.825, -31.825, -0.125, -14.175], [0.125, -21.875, 11.825, -14.175], [0.125, -31.825, 11.825, -22.125]]:
		var cx := (float(r[0]) + float(r[2])) * 0.5
		var cz := (float(r[1]) + float(r[3])) * 0.5
		parts.box("ceiling", Vector3(cx, STOREY - 0.01, cz), Vector3(float(r[2]) - float(r[0]), 0.02, float(r[3]) - float(r[1])))
		parts.cyl("stucco", Vector3(cx, STOREY - 0.03, cz), 0.45, 0.04, Basis.IDENTITY, 24)
	# Wasserflecken an der Decke und in einer Wandecke
	decal(deco, Vector3(-10.6, STOREY - 0.01, -30.6), Vector3.DOWN, 2.0, 2.0, "water_stain.png", 0.8, 0.2)
	decal(deco, Vector3(10.4, STOREY - 0.01, -23.2), Vector3.DOWN, 1.4, 1.4, "water_stain.png", 0.65, 0.2, 1.3)
	decal(deco, Vector3(-11.825, STOREY - 0.6, -15.2), Vector3.RIGHT, 1.2, 1.0, "water_stain.png", 0.55, 0.2)
	# Heller Abdruck eines abgehaengten Bildes (Halle)
	decal(deco, Vector3(9.0, 1.9, -21.875), Vector3.BACK, 0.9, 1.15, "ghost_frame.png", 0.8, 0.12)
	_inner_windows(parts)
	_pictures(deco, parts, mats)
	_sconces(lv, parts)
	parts.build(deco, mats, ["shade", "stucco", "skirting", "white_paint", "curtain", "linen", "gilt", "dusk_glass"])

## Fenster von innen: Glas (Daemmerung), Rahmen, Laibung, Fensterbank, Vorhaenge.
static func _inner_windows(parts: FKit.Parts) -> void:
	var list: Array = [
		# [achse, fester Wert (Innenflaeche), u, Normale nach innen, Vorhang]
		["z", -14.175, -10.5, Vector3.FORWARD, "curtain"], ["z", -14.175, -7.5, Vector3.FORWARD, "curtain"],
		["z", -14.175, -4.5, Vector3.FORWARD, "curtain"], ["z", -14.175, -1.5, Vector3.FORWARD, "curtain"],
		["z", -14.175, 1.5, Vector3.FORWARD, "linen"], ["z", -14.175, 10.5, Vector3.FORWARD, "linen"],
		["z", -31.825, -10.5, Vector3.BACK, "curtain"], ["z", -31.825, -7.5, Vector3.BACK, "curtain"],
		["z", -31.825, -4.5, Vector3.BACK, "curtain"],
		["x", -11.825, -30.5, Vector3.RIGHT, "curtain"], ["x", -11.825, -27.5, Vector3.RIGHT, "curtain"],
		["x", -11.825, -15.5, Vector3.RIGHT, "curtain"],
		["x", 11.825, -15.5, Vector3.LEFT, ""],
	]
	var w := 1.1
	var h := 1.6
	var yc := 1.8
	for e: Array in list:
		var ax: String = e[0]
		var fixed: float = e[1]
		var u: float = e[2]
		var n: Vector3 = e[3]
		var R := _basis_n(n)
		var tv := R.x
		var o := _fp(ax, fixed, u, yc)
		parts.box("dusk_glass", o + n * 0.026, _fs(ax, w, h, 0.01))
		# Laibung (vorgemauert), Rahmen, Kreuzstock
		var ld := 0.16
		parts.box("plaster_in", o + n * (ld * 0.5) + Vector3.UP * (h * 0.5 + 0.05), Vector3(w + 0.2, 0.1, ld), R)
		parts.box("plaster_in", o + n * (ld * 0.5) + tv * (w * 0.5 + 0.05), Vector3(0.1, h, ld), R)
		parts.box("plaster_in", o + n * (ld * 0.5) - tv * (w * 0.5 + 0.05), Vector3(0.1, h, ld), R)
		var fc := o + n * 0.04
		parts.box("white_paint", fc + Vector3.UP * (h * 0.5 - 0.035), Vector3(w, 0.07, 0.06), R)
		parts.box("white_paint", fc - Vector3.UP * (h * 0.5 - 0.035), Vector3(w, 0.07, 0.06), R)
		parts.box("white_paint", fc + tv * (w * 0.5 - 0.035), Vector3(0.07, h, 0.06), R)
		parts.box("white_paint", fc - tv * (w * 0.5 - 0.035), Vector3(0.07, h, 0.06), R)
		parts.box("white_paint", fc, Vector3(0.05, h, 0.05), R)
		parts.box("white_paint", fc + Vector3.UP * (h * 0.22), Vector3(w, 0.05, 0.05), R)
		parts.box("marble", o + n * 0.14 - Vector3.UP * (h * 0.5 + 0.03), Vector3(w + 0.36, 0.05, 0.3), R)
		var cur: String = e[4]
		if cur != "":
			parts.cyl("brass", o + n * 0.2 + Vector3.UP * (h * 0.5 + 0.28), 0.018, w + 1.3, R * Basis(Vector3.FORWARD, PI * 0.5), 8)
			for sgn: float in [-1.0, 1.0]:
				# Stoffbahn mit Falten (versetzte Streifen)
				for k in 4:
					var off := w * 0.5 + 0.05 + k * 0.12
					var dep := 0.13 + (0.05 if k % 2 == 0 else 0.0)
					parts.box(cur, o + n * dep + tv * sgn * off + Vector3.UP * (-yc + FLOOR_Y + 1.37), Vector3(0.13, 2.55, 0.05), R)

## Gemaelde mit Goldrahmen, Karten (Bibliothek), Bilder in der Halle.
static func _pictures(deco: Node3D, parts: FKit.Parts, mats: Dictionary) -> void:
	var pics: Array = [
		# [Mitte auf der Wand, Normale, Breite, Hoehe, Textur, Rahmen]
		[Vector3(0.125, 2.0, -16.0), Vector3.RIGHT, 1.5, 0.9, "painting_lake.jpg", "gilt"],
		[Vector3(-0.125, 2.05, -26.0), Vector3.LEFT, 1.9, 1.33, "painting_storm.jpg", "gilt"],
		[Vector3(-11.825, 2.1, -27.0), Vector3.RIGHT, 1.0, 1.25, "painting_alps.jpg", "gilt"],
		[Vector3(-0.125, 2.0, -20.6), Vector3.LEFT, 0.7, 0.9, "painting_portrait.jpg", "gilt"],
		[Vector3(2.6, 1.85, -22.125), Vector3.FORWARD, 1.5, 1.12, "map_topo.jpg", "timber_dark"],
		[Vector3(9.4, 1.85, -22.125), Vector3.FORWARD, 1.4, 1.0, "map_lake.jpg", "timber_dark"],
		[Vector3(2.8, 1.9, -21.875), Vector3.BACK, 0.75, 0.95, "painting_portrait.jpg", "gilt"],
		[Vector3(0.125, 1.95, -30.0), Vector3.RIGHT, 1.0, 0.7, "painting_lake.jpg", "timber_dark"],
	]
	for p: Array in pics:
		var c: Vector3 = p[0]
		var n: Vector3 = p[1]
		var w: float = p[2]
		var h: float = p[3]
		var R := _basis_n(n)
		var fw := 0.09 if p[5] == "gilt" else 0.04
		var fk: String = p[5]
		var cc := c + n * 0.035
		parts.box(fk, cc + Vector3.UP * (h * 0.5 + fw * 0.5), Vector3(w + fw * 2.0, fw, 0.06), R)
		parts.box(fk, cc - Vector3.UP * (h * 0.5 + fw * 0.5), Vector3(w + fw * 2.0, fw, 0.06), R)
		parts.box(fk, cc + R.x * (w * 0.5 + fw * 0.5), Vector3(fw, h, 0.06), R)
		parts.box(fk, cc - R.x * (w * 0.5 + fw * 0.5), Vector3(fw, h, 0.06), R)
		if fk == "gilt":
			parts.box("timber_dark", cc + Vector3.UP * (h * 0.5 + 0.01), Vector3(w + 0.02, 0.02, 0.07), R)
		var qm := QuadMesh.new()
		qm.size = Vector2(w, h)
		var m := StandardMaterial3D.new()
		m.albedo_texture = _tex(VTEX + "art/" + str(p[4]))
		m.roughness = 0.55 if fk == "gilt" else 0.85
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.material_override = m
		mi.transform = Transform3D(R, c + n * 0.02)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		deco.add_child(mi)
	# Alte Bildplaetze aus VillaWorld (Kisten) sind entfernt; Karte mit Nadeln: rote Markierungen
	for k in 4:
		parts.box("red_paint", Vector3(2.0 + k * 0.33, 1.7 + (k % 2) * 0.25, -22.125 - 0.06), Vector3(0.025, 0.025, 0.03))

## Wandleuchten (Messing, Stoffschirm) mit einem schwachen Licht je Paar.
static func _sconces(lv: Node3D, parts: FKit.Parts) -> void:
	var pairs: Array = [
		[Vector3(4.2, 2.05, -14.175), Vector3(7.8, 2.05, -14.175), Vector3.FORWARD],
		[Vector3(-0.125, 2.05, -27.6), Vector3(-0.125, 2.05, -24.4), Vector3.LEFT],
		[Vector3(1.4, 2.05, -22.125), Vector3(3.8, 2.05, -22.125), Vector3.FORWARD],
	]
	for pr: Array in pairs:
		var n: Vector3 = pr[2]
		var R := _basis_n(n)
		for p: Vector3 in [pr[0], pr[1]]:
			parts.box("brass", p + n * 0.015, Vector3(0.1, 0.2, 0.03), R)
			parts.box("brass", p + n * 0.1 - Vector3.UP * 0.05, Vector3(0.025, 0.025, 0.18), R)
			parts.box("brass", p + n * 0.19, Vector3(0.025, 0.12, 0.025), R)
			parts.cyl("shade", p + n * 0.19 + Vector3.UP * 0.12, 0.08, 0.16, Basis.IDENTITY, 12)
		var mid: Vector3 = ((pr[0] as Vector3) + (pr[1] as Vector3)) * 0.5 + n * 0.4 + Vector3.UP * 0.1
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.74, 0.48)
		l.light_energy = 0.45
		l.omni_range = 3.8
		l.light_volumetric_fog_energy = 0.0
		l.shadow_enabled = false
		l.position = mid
		lv.add_child(l)
