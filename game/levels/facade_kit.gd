extends RefCounted
## Fassaden-Bausatz fuer test_range und berlin: Fassadenmaterial (Shader mit Grime/Russ/Detail-Normal),
## Fenster mit Laibung, Rahmen, Sprossen, Fensterbank und Interior-Mapping-Glas, Fallrohre,
## Regenrinnen, Dachaufbauten, Schornsteine und Schadens-Decals (Einschuesse, Russ).
## Alles nur Optik: Kollisionen bleiben bei den aufrufenden Buildern. Geometrie wird pro Material
## zu einem Mesh zusammengefasst (Parts), Glas zu einem Mesh pro Gebaeudezeile (WindowBatch).
##
## Koordinaten: o = Punkt auf der Aussenflaeche, n = Aussennormale (waagerecht),
## t = UP x n zeigt (von aussen betrachtet) nach rechts. Boxen werden mit Basis(t, UP, n) gedreht,
## Groessen also lokal (Breite entlang t, Hoehe, Tiefe entlang n).

const Geo = preload("res://game/levels/level_geo.gd")
const FACADE_SHADER := preload("res://assets/environment/facade/facade.gdshader")
const WINDOW_SHADER := preload("res://assets/environment/facade/window_interior.gdshader")
const FTEX := "res://assets/environment/facade/textures/"
const OTEX := "res://assets/textures/"
const DECALS := "res://assets/environment/decals/"
const BTEX := "res://assets/environment/berlin/textures/"

## Fassadenvarianten: Texturordner, Kacheln pro Meter, Rauheitsfaktor
const VARIANTS := {
	"brick_red": [FTEX + "red_brick_03", 0.42, 1.0],
	"brick_old": [OTEX + "brick_wall_02", 0.3, 1.0],
	"plaster": [FTEX + "painted_plaster_wall", 0.28, 1.0],
	"plaster_broken": [FTEX + "rough_plaster_broken", 0.3, 1.0],
	"concrete": [FTEX + "precast_concrete_wall", 0.22, 1.0],
	"concrete_old": [OTEX + "concrete_wall_008", 0.3, 1.0],
	"sandstone": [BTEX + "large_sandstone_blocks", 0.2, 1.0],
	"tile_facade": [BTEX + "concrete_tile_facade", 0.22, 1.0],
}

static var _cache: Dictionary = {}
static var _noise: NoiseTexture2D

# --------------------------------------------------------------------------- Materialien

static func noise_tex() -> NoiseTexture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.014
		fn.fractal_octaves = 4
		fn.seed = 4711
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.noise = fn
	return _noise

static func _tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

## Fassadenmaterial. opts: beliebige Shader-Parameter (grime_amount, grime_height, soot, wetness,
## streaks, variation, base_y, detail_strength, normal_strength, rough_mul).
static func facade_mat(variant: String, tint: Color = Color.WHITE, opts: Dictionary = {}) -> ShaderMaterial:
	var key := "fac|%s|%s|%s" % [variant, tint.to_html(), str(opts)]
	if _cache.has(key):
		return _cache[key]
	var v: Array = VARIANTS.get(variant, VARIANTS["concrete_old"])
	var dir: String = v[0]
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	m.set_shader_parameter("base_albedo", _tex(dir + "/diffuse.jpg"))
	m.set_shader_parameter("base_normal", _tex(dir + "/normal.jpg"))
	m.set_shader_parameter("base_arm", _tex(dir + "/arm.jpg"))
	m.set_shader_parameter("detail_normal", _tex(FTEX + "rough_plaster_broken/normal.jpg"))
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("base_scale", v[1])
	m.set_shader_parameter("rough_mul", v[2])
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	_cache[key] = m
	return m

## Material fuer Fensterscheiben mit Interior Mapping. profile: "day" oder "night".
static func window_mat(profile: String = "day") -> ShaderMaterial:
	var key := "win|" + profile
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = WINDOW_SHADER
	if profile == "night":
		m.set_shader_parameter("interior_ambient", 0.018)
		m.set_shader_parameter("lamp_energy", 2.6)
		m.set_shader_parameter("glass_rough", 0.04)
		m.set_shader_parameter("dirt", 0.35)
	else:
		m.set_shader_parameter("interior_ambient", 0.22)
		m.set_shader_parameter("lamp_energy", 1.6)
		m.set_shader_parameter("glass_rough", 0.06)
		m.set_shader_parameter("dirt", 0.6)
	_cache[key] = m
	return m

## Dunkles Rahmen-/Blechmaterial (Fensterrahmen, Fallrohre, Rinnen).
static func frame_mat(color: Color) -> StandardMaterial3D:
	return Geo.flat(color, 0.55, 0.0)

static func metal_mat(color: Color = Color(0.32, 0.33, 0.33)) -> StandardMaterial3D:
	return Geo.mat("rusty_metal_02", color, 0.6, 0.9, 0.6)

static func basis_for(n: Vector3) -> Basis:
	var t := Vector3.UP.cross(n).normalized()
	return Basis(t, Vector3.UP, n)

# --------------------------------------------------------------------------- Sammler

## Sammelt Boxen/Zylinder je Material-Schluessel und baut pro Schluessel ein Mesh.
class Parts:
	const G = preload("res://game/levels/level_geo.gd")
	var batches: Dictionary = {}
	var _cyl_cache: Dictionary = {}

	func bb(key: String) -> G.BoxBatch:
		if not batches.has(key):
			batches[key] = G.BoxBatch.new()
		return batches[key]

	func box(key: String, c: Vector3, s: Vector3, rot: Basis = Basis.IDENTITY) -> void:
		bb(key).add(c, s, rot)

	func cyl(key: String, c: Vector3, r: float, h: float, rot: Basis = Basis.IDENTITY, seg: int = 8) -> void:
		var ck := "%s|%s|%s" % [r, h, seg]
		if not _cyl_cache.has(ck):
			var cm := CylinderMesh.new()
			cm.top_radius = r
			cm.bottom_radius = r
			cm.height = h
			cm.radial_segments = seg
			cm.rings = 1
			cm.cap_top = false
			cm.cap_bottom = false
			_cyl_cache[ck] = cm
		var b := bb(key)
		b.st.append_from(_cyl_cache[ck], 0, Transform3D(rot, c))
		b.count += 1

	## mats: Schluessel -> Material. vis_range > 0 begrenzt die Sichtweite (feine Details).
	func build(parent: Node3D, mats: Dictionary, no_shadow: Array = [], vis_range: Dictionary = {}) -> void:
		for k: String in batches:
			var mesh: ArrayMesh = (batches[k] as G.BoxBatch).build()
			if mesh == null:
				continue
			var mi := G.mesh_node(mesh, mats.get(k, G.flat(Color.MAGENTA)), Vector3.ZERO, not no_shadow.has(k))
			mi.name = "FK_" + k
			if vis_range.has(k):
				mi.visibility_range_end = float(vis_range[k])
				mi.visibility_range_end_margin = 8.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			parent.add_child(mi)
		batches.clear()

## Glasflaechen mit Daten fuer den Interior-Mapping-Shader (siehe window_interior.gdshader).
class WindowBatch:
	var st := SurfaceTool.new()
	var count: int = 0

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	## c = Scheibenmitte, n = Aussennormale, w/h = Groesse in Metern.
	func add(c: Vector3, n: Vector3, w: float, h: float, light: float, warm: float, seed_v: float, broken: bool) -> void:
		var t := Vector3.UP.cross(n).normalized()
		var hw := t * (w * 0.5)
		var hh := Vector3.UP * (h * 0.5)
		var col := Color(clampf(light, 0.0, 1.0), clampf(warm, 0.0, 1.0), fposmod(seed_v, 1.0), 1.0 if broken else 0.0)
		var pts := [c - hw - hh, c - hw + hh, c + hw + hh, c - hw - hh, c + hw + hh, c + hw - hh]
		var uvs := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(1, 0)]
		for i in 6:
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(uvs[i])
			st.set_uv2(Vector2(w, h))
			st.add_vertex(pts[i])
		count += 1

	func build_node(mat: Material) -> MeshInstance3D:
		if count == 0:
			return null
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = "FK_glass"
		return mi

# --------------------------------------------------------------------------- Fenster

## Fenster in einer Wandoeffnung. o = Mitte der Oeffnung auf der Aussenflaeche, w/h = Oeffnung,
## reveal = Laibungstiefe bis zur Glasebene. style: "cross" (Kreuzstock), "t" (Kaempfer + Mittelpfosten
## unten), "single", "shop" (Schaufenster mit Oberlicht). Rahmen in parts[frame_key], Bank in parts[sill_key].
static func window(parts: Parts, wins: WindowBatch, o: Vector3, n: Vector3, w: float, h: float, reveal: float, frame_key: String, sill_key: String, style: String, light: float, warm: float, seed_v: float, broken: bool = false, sill: bool = true) -> void:
	var R := basis_for(n)
	var t := R.x
	var gc := o - n * reveal
	var ft := 0.07
	var fd := 0.08
	var fc := gc + n * (fd * 0.5)
	# Blendrahmen
	parts.box(frame_key, fc + Vector3.UP * (h * 0.5 - ft * 0.5), Vector3(w, ft, fd), R)
	parts.box(frame_key, fc - Vector3.UP * (h * 0.5 - ft * 0.5), Vector3(w, ft, fd), R)
	parts.box(frame_key, fc + t * (w * 0.5 - ft * 0.5), Vector3(ft, h, fd), R)
	parts.box(frame_key, fc - t * (w * 0.5 - ft * 0.5), Vector3(ft, h, fd), R)
	# Sprossen
	var mw := 0.055
	match style:
		"cross":
			parts.box(frame_key, fc, Vector3(mw, h, fd * 0.9), R)
			parts.box(frame_key, fc + Vector3.UP * (h * 0.22), Vector3(w, mw, fd * 0.9), R)
		"t":
			parts.box(frame_key, fc + Vector3.UP * (h * 0.25), Vector3(w, mw, fd * 0.9), R)
			parts.box(frame_key, fc - Vector3.UP * (h * 0.125), Vector3(mw, h * 0.75, fd * 0.9), R)
		"shop":
			parts.box(frame_key, fc + Vector3.UP * (h * 0.3), Vector3(w, mw * 1.4, fd), R)
			var k := maxi(1, int(w / 1.6))
			for i in range(1, k):
				parts.box(frame_key, fc + t * (-w * 0.5 + w * float(i) / float(k)), Vector3(mw * 1.2, h, fd), R)
		_:
			pass
	wins.add(gc - n * 0.005, n, w - ft, h - ft, light, warm, seed_v, broken)
	if sill:
		# Fensterbank aus Blech/Stein, steht leicht vor und ist breiter als die Oeffnung
		var sd := reveal + 0.07
		parts.box(sill_key, o - n * (reveal - sd * 0.5) - Vector3.UP * (h * 0.5 + 0.025), Vector3(w + 0.1, 0.05, sd), R)

## Leere Fensterhoehle (ausgeschossen): nur der Raum dahinter, ohne Glas und Rahmen.
static func hole(wins: WindowBatch, o: Vector3, n: Vector3, w: float, h: float, reveal: float, seed_v: float) -> void:
	wins.add(o - n * reveal, n, w, h, 0.0, 1.0, seed_v, true)

# --------------------------------------------------------------------------- Fassadendetails

## Fallrohr von y0 bis y1 an der Fassade (o auf Aussenflaeche, y wird ueberschrieben) mit Schellen.
static func downpipe(parts: Parts, o: Vector3, n: Vector3, y0: float, y1: float, key: String) -> void:
	var c := Vector3(o.x, 0.0, o.z) + n * 0.11
	var h := y1 - y0
	parts.cyl(key, c + Vector3.UP * (y0 + h * 0.5), 0.055, h, Basis.IDENTITY, 8)
	var R := basis_for(n)
	var k := int(h / 2.2)
	for i in k + 1:
		parts.box(key, c - n * 0.05 + Vector3.UP * (y0 + 0.4 + i * 2.2), Vector3(0.14, 0.04, 0.12), R)
	# Fuss: Bogen nach aussen
	parts.box(key, c + n * 0.05 + Vector3.UP * (y0 + 0.08), Vector3(0.1, 0.1, 0.2), R)

## Regenrinne entlang der Fassade (von a nach b auf Traufhoehe y).
static func gutter(parts: Parts, a: Vector3, b: Vector3, n: Vector3, y: float, key: String) -> void:
	var mid := (a + b) * 0.5
	var L := Vector2(a.x - b.x, a.z - b.z).length()
	var R := basis_for(n)
	parts.box(key, Vector3(mid.x, y, mid.z) + n * 0.16, Vector3(L, 0.13, 0.17), R)

## Dachaufbauten auf einer Dachflaeche (Mitte c auf Dachhoehe, Groesse size = (Breite entlang t,
## Tiefe entlang -n)). Schornsteine, Lueftungskaesten, Antennen, Attika-Abdeckung.
static func roof(parts: Parts, c: Vector3, n: Vector3, width: float, depth: float, rng: RandomNumberGenerator, keys: Dictionary) -> void:
	var R := basis_for(n)
	var t := R.x
	# Attika-Abdeckblech an der Vorderkante
	parts.box(keys.get("cap", "trim"), c + n * (depth * 0.5 - 0.15) + Vector3.UP * 0.06, Vector3(width + 0.1, 0.12, 0.45), R)
	var nchim := rng.randi_range(0, 2) if width > 6.0 else rng.randi_range(0, 1)
	for i in nchim:
		var p := c + t * rng.randf_range(-width * 0.4, width * 0.4) - n * rng.randf_range(depth * 0.1, depth * 0.45)
		var ch := rng.randf_range(1.2, 2.2)
		var cw := rng.randf_range(0.6, 1.1)
		parts.box(keys.get("chimney", "brick"), p + Vector3.UP * (ch * 0.5), Vector3(cw, ch, 0.6), R)
		parts.box(keys.get("cap", "trim"), p + Vector3.UP * (ch + 0.05), Vector3(cw + 0.12, 0.1, 0.72), R)
		for j in rng.randi_range(1, 2):
			parts.cyl(keys.get("metal", "metal"), p + t * ((j - 0.5) * cw * 0.45) + Vector3.UP * (ch + 0.3), 0.08, 0.5, Basis.IDENTITY, 6)
	if rng.randf() < 0.6:
		var p2 := c + t * rng.randf_range(-width * 0.35, width * 0.35) - n * rng.randf_range(depth * 0.3, depth * 0.6)
		parts.box(keys.get("metal", "metal"), p2 + Vector3.UP * 0.5, Vector3(rng.randf_range(1.2, 2.4), 1.0, rng.randf_range(1.0, 1.8)), R)
	if rng.randf() < 0.35:
		var p3 := c + t * rng.randf_range(-width * 0.4, width * 0.4) - n * rng.randf_range(1.0, depth * 0.5)
		parts.cyl(keys.get("metal", "metal"), p3 + Vector3.UP * 1.6, 0.03, 3.2, Basis.IDENTITY, 5)
		parts.box(keys.get("metal", "metal"), p3 + Vector3.UP * 2.8, Vector3(1.2, 0.03, 0.03), R)
		parts.box(keys.get("metal", "metal"), p3 + Vector3.UP * 2.4, Vector3(0.9, 0.03, 0.03), R)

## Balkon vor einem Fenster: Platte, Konsolen, Gelaender. o = Fenstermitte auf der Aussenflaeche, y_floor = Bodenhoehe.
static func balcony(parts: Parts, o: Vector3, n: Vector3, y_floor: float, w: float, keys: Dictionary, damaged: bool = false) -> void:
	var R := basis_for(n)
	var t := R.x
	var base := Vector3(o.x, y_floor, o.z)
	var dep := 1.05
	parts.box(keys.get("slab", "trim"), base + n * (dep * 0.5) + Vector3.UP * 0.07, Vector3(w, 0.14, dep), R)
	for s in [-1.0, 1.0]:
		parts.box(keys.get("slab", "trim"), base + t * (s * (w * 0.5 - 0.15)) + n * 0.3 - Vector3.UP * 0.12, Vector3(0.14, 0.25, 0.6), R)
	var rail: String = keys.get("rail", "metal")
	var rh := 1.0
	if damaged:
		rh = 0.6
	parts.box(rail, base + n * (dep - 0.04) + Vector3.UP * (0.14 + rh), Vector3(w, 0.05, 0.05), R)
	for s in [-1.0, 1.0]:
		parts.box(rail, base + t * (s * (w * 0.5 - 0.03)) + n * (dep * 0.5) + Vector3.UP * (0.14 + rh), Vector3(0.05, 0.05, dep), R)
	var k := int(w / 0.14)
	for i in k + 1:
		if damaged and i % 3 == 0:
			continue
		var tt := -w * 0.5 + 0.05 + (w - 0.1) * float(i) / float(k)
		parts.box(rail, base + t * tt + n * (dep - 0.04) + Vector3.UP * (0.14 + rh * 0.5), Vector3(0.018, rh, 0.018), R)

# --------------------------------------------------------------------------- Decals

## Decal auf eine Flaeche mit Normale n (Wand oder Boden). size = (Breite, Hoehe) auf der Flaeche.
## opts: normal (Pfad), orm (Pfad), modulate (Color), fade (Sichtweite), depth, roll (Grad), mix
static func decal(parent: Node3D, pos: Vector3, n: Vector3, size: Vector2, tex: String, opts: Dictionary = {}) -> Decal:
	var d := Decal.new()
	d.texture_albedo = _tex(DECALS + tex)
	if opts.has("normal"):
		d.texture_normal = _tex(DECALS + String(opts["normal"]))
	if opts.has("orm"):
		d.texture_orm = _tex(DECALS + String(opts["orm"]))
	d.modulate = opts.get("modulate", Color.WHITE)
	d.albedo_mix = opts.get("mix", 1.0)
	var depth: float = opts.get("depth", 0.6)
	d.size = Vector3(size.x, depth, size.y)
	d.normal_fade = opts.get("normal_fade", 0.35)
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.distance_fade_enabled = true
	d.distance_fade_begin = opts.get("fade", 45.0)
	d.distance_fade_length = 10.0
	var basis: Basis
	if absf(n.y) > 0.9:
		basis = Basis(Vector3.UP, deg_to_rad(float(opts.get("roll", 0.0))))
	else:
		var t := Vector3.UP.cross(n).normalized()
		basis = Basis(t, n, t.cross(n))
		basis = basis * Basis(Vector3.UP, deg_to_rad(float(opts.get("roll", 0.0))))
	d.transform = Transform3D(basis, pos)
	parent.add_child(d)
	return d

## Einschussgarbe auf einer Wand.
static func bullet_holes(parent: Node3D, pos: Vector3, n: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var v := rng.randi() % 2
	decal(parent, pos, n, Vector2(size, size), "bullet_holes_%d.png" % v, {"normal": "bullet_holes_%d_n.png" % v, "roll": rng.randf_range(0.0, 360.0), "depth": 0.5, "fade": 38.0})

## Russfahne ueber einer Oeffnung (pos = Oberkante der Oeffnung, Mitte).
static func soot_above(parent: Node3D, pos: Vector3, n: Vector3, w: float, h: float) -> void:
	decal(parent, pos + Vector3.UP * (h * 0.5 - 0.15), n, Vector2(w, h), "soot.png", {"depth": 0.9, "fade": 70.0, "modulate": Color(1, 1, 1, 0.95)})
