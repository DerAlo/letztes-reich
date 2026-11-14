extends RefCounted
## Bausteine fuer Level 3 "Die Bruecke" (river_crossing): nasse PBR-Materialien (wet.gdshader),
## Fluss-Material, Poly-Haven-Modelle (nass gemacht), Plattenbauten, Fabrikhalle, Schuetzengraeben,
## Ufer-Boeschungen. Dazu Ersatz-Panzer und Ersatz-Sprengladung, falls game/vehicles/ fehlt.
## Alle Funktionen statisch, per preload() einbinden.

const Geo = preload("res://game/levels/level_geo.gd")
const DebrisSettle = preload("res://game/systems/debris_settle.gd")
const PH = preload("res://game/levels/ph_props.gd")
const TEX := "res://assets/environment/river/textures/"
const MODELS := "res://assets/environment/river/models/"
const WET_SHADER: Shader = preload("res://assets/environment/river/wet.gdshader")
const WATER_SHADER: Shader = preload("res://assets/environment/river/water.gdshader")

static var _cache: Dictionary = {}
static var _noise: NoiseTexture2D

# --------------------------------------------------------------------------- Texturen / Materialien

static func noise_tex() -> NoiseTexture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012
		fn.fractal_octaves = 4
		fn.seed = 3030
		_noise = NoiseTexture2D.new()
		_noise.width = 256
		_noise.height = 256
		_noise.seamless = true
		_noise.generate_mipmaps = true
		_noise.noise = fn
	return _noise

static func _water_normal(seed_v: int, freq: float) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = freq
	fn.fractal_octaves = 3
	fn.seed = seed_v
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 6.0
	t.generate_mipmaps = true
	t.noise = fn
	return t

static func _tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

## Nasses Material. dir = Ordnername unter assets/environment/river/textures oder "" fuer Vollfarbe.
static func wet(dir: String, tint: Color, scale: float = 0.3, opts: Dictionary = {}) -> ShaderMaterial:
	var key := "wet|%s|%s|%s|%s" % [dir, tint.to_html(), scale, str(opts)]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = WET_SHADER
	m.set_shader_parameter("use_base_tex", dir != "")
	if dir != "":
		m.set_shader_parameter("base_albedo", _tex(TEX + dir + "/diffuse.jpg"))
		m.set_shader_parameter("base_normal", _tex(TEX + dir + "/normal.jpg"))
		m.set_shader_parameter("base_arm", _tex(TEX + dir + "/arm.jpg"))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("base_scale", scale)
	m.set_shader_parameter("noise_tex", noise_tex())
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	_cache[key] = m
	return m

static func road() -> ShaderMaterial:
	return wet("road_damaged", Color(0.78, 0.78, 0.8), 0.12, {"puddles": 0.42, "wetness": 0.95, "puddle_scale": 0.06})

static func deck() -> ShaderMaterial:
	return wet("road_damaged", Color(0.7, 0.7, 0.72), 0.14, {"puddles": 0.5, "wetness": 1.0, "puddle_scale": 0.09})

static func concrete(tint: Color = Color(0.72, 0.72, 0.7)) -> ShaderMaterial:
	return wet("rough_concrete", tint, 0.25, {"wetness": 0.85, "streaks": 0.8})

static func steel(tint: Color = Color(0.55, 0.62, 0.55)) -> ShaderMaterial:
	return wet("green_metal_rust", tint, 0.4, {"base_metallic": 0.85, "wetness": 0.9, "base_roughness": 0.9, "streaks": 0.7})

static func mud() -> ShaderMaterial:
	return wet("brown_mud_02", Color(0.6, 0.56, 0.52), 0.2, {"puddles": 0.5, "wetness": 1.0, "puddle_scale": 0.05})

static func grass() -> ShaderMaterial:
	return wet("withered_grass", Color(0.62, 0.62, 0.55), 0.22, {"puddles": 0.2, "wetness": 0.7})

static func rocks() -> ShaderMaterial:
	return wet("river_small_rocks", Color(0.7, 0.7, 0.7), 0.3, {"wetness": 1.0})

static func brick(tint: Color = Color(0.8, 0.72, 0.68)) -> ShaderMaterial:
	return wet("factory_brick", tint, 0.3, {"wetness": 0.8, "streaks": 0.9})

static func plaster(tint: Color) -> ShaderMaterial:
	return wet("worn_plaster_wall", tint, 0.22, {"wetness": 0.8, "streaks": 1.0})

static func corrugated(tint: Color = Color(0.75, 0.72, 0.7)) -> ShaderMaterial:
	return wet("rusty_corrugated_iron", tint, 0.35, {"base_metallic": 0.6, "wetness": 0.9, "streaks": 0.6})

static func flat_wet(color: Color, rough: float = 0.3, metallic: float = 0.0) -> ShaderMaterial:
	return wet("", color, 1.0, {"base_roughness": rough, "base_metallic": metallic, "wetness": 0.6})

static func glass() -> StandardMaterial3D:
	return Geo.flat(Color(0.015, 0.018, 0.022), 0.05, 0.4)

static func glow(color: Color, energy: float) -> StandardMaterial3D:
	return Geo.flat(Color(0.04, 0.03, 0.02), 0.6, 0.0, color, energy)

static func water_mat(piers: Array) -> ShaderMaterial:
	if _cache.has("water"):
		return _cache["water"]
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("normal_a", _water_normal(11, 0.018))
	m.set_shader_parameter("normal_b", _water_normal(23, 0.04))
	m.set_shader_parameter("foam_noise", noise_tex())
	var arr: Array[Vector4] = []
	for i in 6:
		arr.append(piers[i] if i < piers.size() else Vector4(0, 0, 0, 0))
	m.set_shader_parameter("piers", arr)
	_cache["water"] = m
	return m

static func add_batch(parent: Node3D, b: Geo.BoxBatch, m: Material, shadows: bool = true) -> MeshInstance3D:
	var mesh := b.build()
	if mesh == null:
		return null
	var mi := Geo.mesh_node(mesh, m, Vector3.ZERO, shadows)
	parent.add_child(mi)
	return mi

## Box zwischen zwei Punkten (Traeger, Strebe) in ein Batch.
static func beam(b: Geo.BoxBatch, a: Vector3, c: Vector3, w: float, h: float) -> void:
	var d := c - a
	var up := Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.RIGHT
	var basis := Basis.looking_at(d.normalized(), up)
	b.add((a + c) * 0.5, Vector3(w, h, d.length()), basis)

# --------------------------------------------------------------------------- Modelle

## Poly-Haven-Modell instanziieren; Materialien werden einmalig "nass" gemacht (dunkler, glatter).
## collide: Groesse einer Box-Kollision (Vector3.ZERO = keine), Mitte auf halber Hoehe.
static func model(parent: Node3D, mname: String, pos: Vector3, yaw_deg: float = 0.0, scale: float = 1.0, collide: Vector3 = Vector3.ZERO, covers: Array = [], shadows: bool = true) -> Node3D:
	var path := MODELS + "%s/%s.gltf" % [mname, mname]
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = _tex_scene(path)
	var inst := scene.instantiate() as Node3D
	_wetify(inst, shadows)
	var root: Node3D = inst
	if collide != Vector3.ZERO:
		var b := Geo.static_body(pos, yaw_deg)
		Geo.add_box_shape(b, Vector3(0, collide.y * 0.5, 0), collide)
		inst.scale = Vector3.ONE * scale
		b.add_child(inst)
		root = b
		covers.append(pos)
	else:
		inst.position = pos
		inst.rotation_degrees.y = yaw_deg
		inst.scale = Vector3.ONE * scale
	parent.add_child(root)
	return root

static func _tex_scene(path: String) -> PackedScene:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

static func _wetify(n: Node, shadows: bool) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(s)
				if src is StandardMaterial3D:
					var key := "wetmat|%d" % src.get_instance_id()
					if not _cache.has(key):
						var m := (src as StandardMaterial3D).duplicate() as StandardMaterial3D
						m.roughness = m.roughness * 0.45
						m.albedo_color = m.albedo_color * Color(0.72, 0.72, 0.74, 1.0)
						_cache[key] = m
					mi.set_surface_override_material(s, _cache[key])
	for c in n.get_children():
		_wetify(c, shadows)

# --------------------------------------------------------------------------- Plattenbau / Haeuser

## Mehrgeschossiges Wohnhaus (Plattenbau/Ziegel). pos = Bodenmitte, Front zeigt nach lokal +z.
## size: x = Frontbreite, y = Geschosse (float, wird gerundet), z = Tiefe.
## opts: brick (bool), tint, lit (Anteil beleuchteter Fenster), burnt (Anteil Brandfenster),
##       damage (0..1, abgebrochene Ecke oben), shop (Erdgeschoss-Schaufenster).
static func building(parent: Node3D, pos: Vector3, yaw_deg: float, size: Vector3, rng: RandomNumberGenerator, opts: Dictionary = {}) -> StaticBody3D:
	var floors := maxi(1, int(round(size.y)))
	var fh := 3.0
	var w := size.x
	var d := size.z
	var h := floors * fh + 0.6
	var tint: Color = opts.get("tint", Color(0.75, 0.7, 0.62))
	var wall_m: Material = brick(tint) if opts.get("brick", false) else plaster(tint)
	var b := Geo.static_body(pos, yaw_deg)
	var walls := Geo.batch()
	var dark := Geo.batch()
	var trims := Geo.batch()
	var lit_b := Geo.batch()
	var burn_b := Geo.batch()
	var damage: float = opts.get("damage", 0.0)
	# Grundkoerper, mit herausgebrochener oberer Ecke bei Schaden
	var cut_w := 0.0
	var cut_h := 0.0
	if damage > 0.0:
		cut_w = w * clampf(damage * 0.45, 0.15, 0.45)
		cut_h = fh * clampf(round(damage * floors * 0.8), 1.0, floors - 1.0)
	walls.add(Vector3(-cut_w * 0.5, h * 0.5, 0), Vector3(w - cut_w, h, d))
	if cut_w > 0.0:
		walls.add(Vector3(w * 0.5 - cut_w * 0.5, (h - cut_h) * 0.5, 0), Vector3(cut_w, h - cut_h, d))
		# Bruchkante: Deckenplatten ragen heraus
		for f in range(floors - int(cut_h / fh), floors):
			var bk := Basis(Vector3(0, 0, 1), rng.randf_range(-0.25, 0.25))
			trims.add(Vector3(w * 0.5 - cut_w + rng.randf_range(0.3, 1.2), f * fh + 0.3, rng.randf_range(-d * 0.3, d * 0.3)), Vector3(rng.randf_range(1.0, 2.4), 0.25, d * rng.randf_range(0.4, 0.8)), bk)
	# Sockel und Dachkante
	trims.add(Vector3(0, 0.4, 0), Vector3(w + 0.2, 0.8, d + 0.2))
	trims.add(Vector3(-cut_w * 0.5, h + 0.25, 0), Vector3(w - cut_w + 0.3, 0.5, d + 0.3))
	# Fenster auf Front und Rueckseite
	var nwin := maxi(2, int(w / 3.2))
	var lit: float = opts.get("lit", 0.08)
	var burnt: float = opts.get("burnt", 0.05)
	for side: float in [1.0, -1.0]:
		for f in floors:
			for i in nwin:
				var x := -w * 0.5 + (i + 0.5) * w / nwin
				var y := f * fh + 1.7
				if x > w * 0.5 - cut_w and y > h - cut_h:
					continue
				if f == 0 and side > 0 and opts.get("shop", false):
					if i % 2 == 0:
						dark.add(Vector3(x, 1.6, side * (d * 0.5 + 0.02)), Vector3(w / nwin * 0.8, 2.2, 0.06))
					continue
				if f == 0 and side > 0 and i == nwin / 2:
					# Hauseingang mit Vordach
					dark.add(Vector3(x, 1.25, side * (d * 0.5 + 0.02)), Vector3(1.4, 2.4, 0.06))
					trims.add(Vector3(x, 2.65, side * (d * 0.5 + 0.6)), Vector3(2.2, 0.15, 1.2))
					continue
				var fz := side * (d * 0.5 + 0.03)
				var r := rng.randf()
				if r < burnt:
					burn_b.add(Vector3(x, y, fz), Vector3(1.3, 1.5, 0.06))
					# Russfahne ueber dem Fenster
					dark.add(Vector3(x, y + 1.1, fz + side * 0.005), Vector3(1.5, 0.9, 0.04))
				elif r < burnt + lit:
					lit_b.add(Vector3(x, y, fz), Vector3(1.3, 1.5, 0.06))
				else:
					dark.add(Vector3(x, y, fz), Vector3(1.3, 1.5, 0.06))
				trims.add(Vector3(x, y - 0.82, side * (d * 0.5 + 0.12)), Vector3(1.6, 0.1, 0.24))
	# Balkonplatten an der Front (Plattenbau)
	if not opts.get("brick", false):
		for f in range(1, floors):
			for i in nwin:
				if (i + f) % 3 != 0:
					continue
				var x := -w * 0.5 + (i + 0.5) * w / nwin
				if x > w * 0.5 - cut_w and f * fh > h - cut_h - fh:
					continue
				trims.add(Vector3(x, f * fh + 0.6, d * 0.5 + 0.6), Vector3(2.4, 0.18, 1.2))
				trims.add(Vector3(x, f * fh + 1.2, d * 0.5 + 1.15), Vector3(2.4, 1.0, 0.1))
	add_batch(b, walls, wall_m)
	add_batch(b, trims, concrete(Color(0.6, 0.6, 0.58)))
	add_batch(b, dark, glass(), false)
	add_batch(b, lit_b, glow(Color(1.0, 0.62, 0.3), 2.0), false)
	add_batch(b, burn_b, glow(Color(1.0, 0.38, 0.1), 5.0), false)
	Geo.add_box_shape(b, Vector3(0, h * 0.5, 0), Vector3(w, h, d))
	parent.add_child(b)
	return b

## Fabrikhalle mit Sheddach, Ziegelwaenden und hohem Schornstein. pos = Bodenmitte der Halle.
static func factory(parent: Node3D, pos: Vector3, yaw_deg: float, size: Vector3, rng: RandomNumberGenerator) -> StaticBody3D:
	var b := Geo.static_body(pos, yaw_deg)
	var w := size.x
	var h := size.y
	var d := size.z
	var walls := Geo.batch()
	var roof := Geo.batch()
	var dark := Geo.batch()
	var trims := Geo.batch()
	walls.add(Vector3(0, h * 0.5, 0), Vector3(w, h, d))
	# Pilaster an der Front
	for i in int(w / 4.0) + 1:
		var x := -w * 0.5 + i * w / int(w / 4.0)
		walls.add(Vector3(x, h * 0.5, d * 0.5 + 0.2), Vector3(0.7, h, 0.4))
	# Hohe Sprossenfenster (zum Teil zerschlagen = dunkel, sonst schwach erleuchtet)
	var lit_b := Geo.batch()
	for i in int(w / 4.0):
		var x := -w * 0.5 + (i + 0.5) * w / int(w / 4.0)
		var bb := lit_b if rng.randf() < 0.18 else dark
		bb.add(Vector3(x, h * 0.55, d * 0.5 + 0.04), Vector3(2.4, h * 0.5, 0.06))
		for k in 3:
			trims.add(Vector3(x, h * 0.35 + k * h * 0.15, d * 0.5 + 0.1), Vector3(2.5, 0.1, 0.08))
	# Sheddach: schraege Glasflaechen + senkrechte Seiten
	var n := int(d / 6.0)
	for k in n:
		var z := -d * 0.5 + (k + 0.5) * d / n
		var rot := Basis(Vector3(1, 0, 0), deg_to_rad(-35.0))
		roof.add(Vector3(0, h + 1.6, z + 0.6), Vector3(w + 0.4, 0.25, d / n * 1.15), rot)
		dark.add(Vector3(0, h + 1.6, z - d / n * 0.5 + 0.2), Vector3(w + 0.3, 3.0, 0.1))
	trims.add(Vector3(0, h + 0.15, 0), Vector3(w + 0.5, 0.3, d + 0.5))
	add_batch(b, walls, brick(Color(0.72, 0.6, 0.55)))
	add_batch(b, roof, corrugated(Color(0.5, 0.48, 0.46)))
	add_batch(b, trims, concrete(Color(0.5, 0.5, 0.48)))
	add_batch(b, dark, glass(), false)
	add_batch(b, lit_b, glow(Color(1.0, 0.7, 0.4), 1.4), false)
	Geo.add_box_shape(b, Vector3(0, h * 0.5, 0), Vector3(w, h, d))
	parent.add_child(b)
	return b

static func chimney(parent: Node3D, pos: Vector3, height: float) -> void:
	var m := brick(Color(0.62, 0.5, 0.45))
	var cm := CylinderMesh.new()
	cm.top_radius = 1.3
	cm.bottom_radius = 2.2
	cm.height = height
	cm.radial_segments = 16
	cm.rings = 1
	var mi := Geo.mesh_node(cm, m, pos + Vector3(0, height * 0.5, 0))
	parent.add_child(mi)
	for k in 3:
		var ring := Geo.cylinder_node(lerpf(2.1, 1.4, (k + 1) / 4.0) + 0.12, 0.5, concrete(Color(0.45, 0.45, 0.44)), pos + Vector3(0, height * (k + 1) / 4.0, 0), Vector3.ZERO, 16)
		parent.add_child(ring)

# --------------------------------------------------------------------------- Graeben / Stellungen

## Sandsackreihe (Jutesaecke aus ph_props.gd, eine Reihe), optional mit Kollision. Laenge entlang lokal x.
static func sandbag_wall(parent: Node3D, pos: Vector3, yaw_deg: float, length: float, layers: int, rng: RandomNumberGenerator, covers: Array, collide: bool = true) -> void:
	var b := Geo.static_body(pos, yaw_deg)
	# Gefuellte Jutesaecke (ph_props.gd, Poly-Haven hessian_230) statt Ellipsoid-Klumpen; PH-Wall laeuft
	# entlang lokal z, hier entlang lokal x -> um 90 Grad gedreht. Regennass: dunklerer Jute-Ton.
	var wall := Node3D.new()
	wall.name = "SandbagWall"
	wall.rotation.y = PI * 0.5
	b.add_child(wall)
	var mmi := PH.sandbag_wall(wall, length, layers, rng, -1.0, 1)
	mmi.material_override = PH.sandbag_mat(-1.0, Color(0.6, 0.55, 0.46))
	var top := 0.12 + layers * PH.BAG_PITCH
	if collide:
		Geo.add_box_shape(b, Vector3(0, top * 0.5, 0), Vector3(length, top, 0.5))
		covers.append(pos)
	parent.add_child(b)

## Schuetzengraben quer zur Strasse: Wellblech-Verschalung an beiden Waenden, Pfosten, Sandsack-Brustwehr.
## a, b = Enden der Grabenmitte am Boden (y = 0), depth = Tiefe, width = Breite.
static func trench_dressing(parent: Node3D, a: Vector3, b: Vector3, width: float, depth: float, rng: RandomNumberGenerator, covers: Array) -> void:
	var dir := (b - a).normalized()
	var len := a.distance_to(b)
	var side := Vector3(-dir.z, 0, dir.x)
	var sheets := Geo.batch()
	var posts := Geo.batch()
	var basis := Basis.looking_at(dir, Vector3.UP)
	for s: float in [-1.0, 1.0]:
		var c := (a + b) * 0.5 + side * s * (width * 0.5 - 0.04) + Vector3(0, -depth * 0.5, 0)
		sheets.add(c, Vector3(0.06, depth + 0.1, len), basis)
		var n := int(len / 1.8)
		for i in n + 1:
			var p := a + dir * (i * len / n) + side * s * (width * 0.5 - 0.1) + Vector3(0, -depth * 0.5 + 0.15, 0)
			posts.add(p, Vector3(0.12, depth + 0.4, 0.12))
		# Brustwehr: Sandsaecke am Grabenrand (nur Optik, Kollision niedrig halten)
		var bag_c := (a + b) * 0.5 + side * s * (width * 0.5 + 0.45)
		var yaw := rad_to_deg(atan2(dir.x, dir.z)) + 90.0
		sandbag_wall(parent, bag_c, yaw, len - 0.4, 2, rng, covers, true)
	add_batch(parent, sheets, corrugated(Color(0.55, 0.52, 0.48)))
	add_batch(parent, posts, wet("", Color(0.2, 0.17, 0.14), 1.0, {"base_roughness": 0.8}))

# --------------------------------------------------------------------------- Ersatz-Fahrzeuge

## Ersatz-Panzer, falls game/vehicles/tank.tscn fehlt: Wanne, Turm, Rohr; Turm folgt dem Ziel,
## alle paar Sekunden Schuss mit Fehlweite (wie im Contract, nicht direkt toedlich). destroy() sprengt ihn.
class FallbackTank extends Node3D:
	signal destroyed
	var target: Node3D = null
	var alive: bool = true
	var turret: Node3D
	var _fire_t: float = 4.0
	var _laser: MeshInstance3D
	var _aim_t: float = -1.0
	func _ready() -> void:
		add_to_group("damageable")
		add_to_group("vehicle")
		var body := Geo.static_body()
		var hull := Geo.batch()
		hull.add(Vector3(0, 0.95, 0), Vector3(3.4, 1.1, 6.8))
		hull.add(Vector3(0, 1.2, -3.3), Vector3(3.2, 0.6, 0.6), Basis(Vector3(1, 0, 0), 0.6))
		for s: float in [-1.0, 1.0]:
			hull.add(Vector3(s * 1.55, 0.55, 0), Vector3(0.7, 1.0, 7.0))
			hull.add(Vector3(s * 1.85, 1.15, 0), Vector3(0.5, 0.08, 6.8))
		var m := RiverPropsSelf.steel(Color(0.35, 0.38, 0.3))
		RiverPropsSelf.add_batch(body, hull, m)
		var wheels := Geo.batch()
		for s: float in [-1.0, 1.0]:
			for i in 6:
				wheels.add_ball(Vector3(s * 1.55, 0.45, -2.6 + i * 1.04), Vector3(0.3, 0.8, 0.8))
		RiverPropsSelf.add_batch(body, wheels, Geo.flat(Color(0.05, 0.05, 0.05), 0.6))
		Geo.add_box_shape(body, Vector3(0, 0.95, 0), Vector3(3.5, 1.9, 7.0))
		add_child(body)
		turret = Node3D.new()
		turret.position = Vector3(0, 1.75, 0.4)
		add_child(turret)
		var tb := Geo.batch()
		tb.add(Vector3(0, 0.3, 0), Vector3(2.5, 0.6, 3.0))
		tb.add(Vector3(0, 0.25, 1.6), Vector3(2.0, 0.5, 0.6))
		tb.add(Vector3(0, 0.3, -4.0), Vector3(0.2, 0.2, 5.2))
		tb.add(Vector3(0, 0.3, -6.6), Vector3(0.3, 0.3, 0.5))
		tb.add(Vector3(0.6, 0.75, 0.2), Vector3(0.6, 0.35, 0.6))
		RiverPropsSelf.add_batch(turret, tb, m)
		_laser = MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(0.02, 0.02, 1.0)
		_laser.mesh = cm
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1.0, 0.1, 0.05)
		_laser.material_override = lm
		_laser.visible = false
		_laser.top_level = true
		add_child(_laser)
	func set_target(n: Node) -> void:
		target = n as Node3D
	func is_alive() -> bool:
		return alive
	func take_damage(amount: float, _source: Node, _hp: Vector3, _hn: Vector3) -> void:
		if amount >= 200.0:
			destroy()
	func _process(delta: float) -> void:
		if not alive or target == null or not is_instance_valid(target):
			_laser.visible = false
			return
		var tp := target.global_position
		var local := turret.global_transform.affine_inverse() * tp
		var ang := atan2(-local.x, -local.z)
		turret.rotate_y(clampf(ang, -delta * 0.6, delta * 0.6))
		_fire_t -= delta
		if _fire_t < 1.5 and _fire_t > 0.0:
			var muzzle := turret.global_transform * Vector3(0, 0.3, -6.8)
			_laser.visible = true
			_laser.global_position = (muzzle + tp) * 0.5
			_laser.look_at(tp, Vector3.UP)
			_laser.scale = Vector3(1, 1, muzzle.distance_to(tp))
		else:
			_laser.visible = false
		if _fire_t <= 0.0:
			_fire_t = randf_range(6.5, 8.0)
			var muzzle := turret.global_transform * Vector3(0, 0.3, -6.8)
			VFX.spawn_explosion(muzzle, 0.5)
			VFX.play_sfx_3d("explosion_3", muzzle, 4.0, 20.0, 400.0)
			var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf_range(5.0, 8.0)
			Combat.explode(Vector3(tp.x, 0.2, tp.z) + off, 4.0, 30.0, self, 1.4)
	func destroy() -> void:
		if not alive:
			return
		alive = false
		_laser.visible = false
		var p := global_position + Vector3(0, 1.5, 0)
		Combat.explode(p, 3.0, 0.0, self, 3.2)
		# Turm fliegt hoch
		var rb := RigidBody3D.new()
		rb.collision_layer = 8
		rb.collision_mask = 1
		rb.mass = 400.0
		var tr := turret.global_transform
		turret.get_parent().remove_child(turret)
		rb.add_child(turret)
		turret.transform = Transform3D.IDENTITY
		Geo.add_box_shape(rb, Vector3(0, 0.3, 0), Vector3(2.5, 0.6, 3.0))
		get_parent().add_child(rb)
		rb.global_transform = tr
		rb.linear_velocity = Vector3(randf_range(-2, 2), 13.0, randf_range(-2, 2))
		rb.angular_velocity = Vector3(randf_range(-2, 2), randf_range(-4, 4), randf_range(-2, 2))
		DebrisSettle.solidify_when_settled(rb, 3.0, 12.0)
		var f := Props.fire(self, Vector3(0, 1.6, 0.4), 1.6, true, 2.4, 9.0)
		f.name = "TankFire"
		destroyed.emit()

## Ersatz-Sprengladung, falls game/vehicles/demo_charge.tscn fehlt (gleiches Verhalten wie im Contract).
class FallbackCharge extends Area3D:
	signal planted
	signal detonated
	var target: Node = null
	var _hold: float = 0.0
	var _planted: bool = false
	var _inside: Node3D = null
	var _label: Label3D
	func _ready() -> void:
		collision_layer = 0
		collision_mask = 2
		monitoring = true
		var cs := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = 2.5
		cs.shape = sp
		add_child(cs)
		_label = Label3D.new()
		_label.text = "[E] Sprengladung anbringen"
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.font_size = 40
		_label.pixel_size = 0.004
		_label.modulate = Color(1.0, 0.85, 0.4)
		_label.outline_size = 8
		_label.no_depth_test = true
		_label.position = Vector3(0, 1.2, 0)
		add_child(_label)
		body_entered.connect(func(b: Node3D) -> void:
			if b.is_in_group("player"):
				_inside = b)
		body_exited.connect(func(b: Node3D) -> void:
			if b == _inside:
				_inside = null
				_hold = 0.0)
	func _process(delta: float) -> void:
		if _planted:
			return
		if target != null and is_instance_valid(target) and target.has_method("is_alive") and not target.call("is_alive"):
			_label.visible = false
			return
		_label.visible = _inside != null
		if _inside == null:
			return
		var auto: bool = Game.arg("autopilot", false)
		var pressed := InputMap.has_action("interact") and Input.is_action_pressed("interact")
		if auto:
			_plant()
		elif pressed:
			_hold += delta
			_label.text = "Anbringen ... %d%%" % int(_hold / 1.5 * 100.0)
			if _hold >= 1.5:
				_plant()
		else:
			_hold = 0.0
			_label.text = "[E] Sprengladung anbringen"
	func _plant() -> void:
		_planted = true
		_label.visible = false
		planted.emit()
		var charge := Geo.box_mesh_node(Vector3(0.35, 0.25, 0.12), Geo.flat(Color(0.25, 0.27, 0.2), 0.6), Vector3(0, 0.2, 0))
		add_child(charge)
		var led := OmniLight3D.new()
		led.light_color = Color(1, 0.1, 0.05)
		led.omni_range = 1.5
		led.light_energy = 2.0
		led.position = Vector3(0, 0.4, 0.1)
		add_child(led)
		for i in 8:
			get_tree().create_timer(i * 0.5, false).timeout.connect(func() -> void:
				if is_instance_valid(led):
					led.visible = not led.visible
				VFX.play_sfx_3d("drone_beep", global_position, -2.0, 6.0, 60.0))
		get_tree().create_timer(4.0, false).timeout.connect(_detonate)
	func _detonate() -> void:
		Combat.explode(global_position, 3.5, 60.0, null, 2.4)
		if target != null and is_instance_valid(target):
			if target.has_method("destroy"):
				target.call("destroy")
			elif target.has_method("take_damage"):
				target.call("take_damage", 99999.0, null, global_position, Vector3.UP)
		detonated.emit()
		queue_free()

const Props = preload("res://game/levels/level_props.gd")
const RiverPropsSelf = preload("res://game/levels/river_props.gd")
