extends RefCounted
## Bausteine fuer das Nachtlevel "baltic_night": Schnee-Materialien (Shader mit Schneeauflage),
## prozedurale Kiefern (MultiMesh), Holzhaeuser (statisch oder als Einzelteile fuer die
## Zerstoerung), Schuetzengraben-Verschalung, Sandsaecke, Stacheldraht, Strommasten,
## Schuetzenpanzer, Scheune, Bahnuebergang. Alle Funktionen statisch, per preload() einbinden.

const Geo = preload("res://game/levels/level_geo.gd")
const ENV_TEX := "res://assets/environment/textures/"
const OLD_TEX := "res://assets/textures/"
const SNOW_SHADER: Shader = preload("res://assets/environment/snowy.gdshader")

static var _cache: Dictionary = {}
static var _noise: NoiseTexture2D

# --------------------------------------------------------------------------- Materialien

static func noise_tex() -> NoiseTexture2D:
	if _noise == null:
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.012
		fn.fractal_octaves = 4
		fn.seed = 77
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

## Material mit Schneeauflage. base = Texturordner (voller res://-Pfad) oder "" fuer Vollfarbe.
static func snowy(base: String, tint: Color, scale: float = 0.3, snow: float = 0.45, opts: Dictionary = {}) -> ShaderMaterial:
	var key := "%s|%s|%s|%s|%s" % [base, tint.to_html(), scale, snow, str(opts)]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = SNOW_SHADER
	m.set_shader_parameter("use_base_tex", base != "")
	if base != "":
		m.set_shader_parameter("base_albedo", _tex(base + "/diffuse.jpg"))
		m.set_shader_parameter("base_normal", _tex(base + "/normal.jpg"))
		m.set_shader_parameter("base_arm", _tex(base + "/arm.jpg"))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("base_scale", scale)
	m.set_shader_parameter("snow_amount", snow)
	m.set_shader_parameter("snow_albedo", _tex(ENV_TEX + "snow_02/diffuse.jpg"))
	m.set_shader_parameter("snow_normal", _tex(ENV_TEX + "snow_02/normal.jpg"))
	m.set_shader_parameter("noise_tex", noise_tex())
	for k in opts:
		m.set_shader_parameter(k, opts[k])
	_cache[key] = m
	return m

static func ground_mat() -> ShaderMaterial:
	return snowy(ENV_TEX + "gravel", Color(0.32, 0.28, 0.24), 0.35, 0.93, {"noise_amp": 1.9, "noise_scale": 0.035, "snow_scale": 0.22, "snow_sharp": 5.0})

static func planks(tint: Color, snow: float = 0.3) -> ShaderMaterial:
	return snowy(ENV_TEX + "weathered_planks", tint, 0.45, snow, {"noise_amp": 0.5})

static func bark() -> ShaderMaterial:
	return snowy(ENV_TEX + "pine_bark", Color(0.55, 0.5, 0.46), 0.8, 0.12, {"noise_amp": 0.8})

static func needles() -> ShaderMaterial:
	return snowy("", Color(0.05, 0.085, 0.06), 1.0, 0.42, {"color_noise": 0.45, "noise_amp": 1.3, "noise_scale": 0.3, "snow_sharp": 5.0, "base_roughness": 0.92})

static func metal(tint: Color, snow: float = 0.4) -> ShaderMaterial:
	return snowy(OLD_TEX + "rusty_metal_02", tint, 0.45, snow, {"base_metallic": 0.35, "noise_amp": 0.9})

static func concrete(tint: Color, snow: float = 0.4) -> ShaderMaterial:
	return snowy(OLD_TEX + "concrete_wall_008", tint, 0.3, snow)

static func brick(tint: Color) -> ShaderMaterial:
	return snowy(OLD_TEX + "brick_wall_02", tint, 0.35, 0.35)

static func sand_mat() -> ShaderMaterial:
	return snowy("", Color(0.2, 0.19, 0.15), 1.0, 0.62, {"color_noise": 0.35, "noise_amp": 1.0, "noise_scale": 0.4, "base_roughness": 1.0})

static func glow(color: Color, energy: float) -> StandardMaterial3D:
	return Geo.flat(Color(0.04, 0.03, 0.02), 0.8, 0.0, color, energy)

static func unshaded(color: Color, energy: float = 1.0) -> StandardMaterial3D:
	var key := "unsh|%s|%s" % [color.to_html(), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color * energy
	m.albedo_color.a = 1.0
	_cache[key] = m
	return m

# --------------------------------------------------------------------------- Mesh-Helfer

static func add_batch(parent: Node3D, b: Geo.BoxBatch, m: Material, shadows: bool = true) -> MeshInstance3D:
	var mesh := b.build()
	if mesh == null:
		return null
	var mi := Geo.mesh_node(mesh, m, Vector3.ZERO, shadows)
	parent.add_child(mi)
	return mi

## Schneeverwehung (abgeflachter Ellipsoid), nur Optik.
static func drift(b: Geo.BoxBatch, pos: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	b.add_ball(pos, size, Basis(Vector3.UP, yaw))

# --------------------------------------------------------------------------- Kiefern

## Kiefer: Flaeche 0 Stamm, Flaeche 1 Nadelkleid aus zackigen, haengenden Etagen.
static func pine_mesh(rng: RandomNumberGenerator, h: float) -> ArrayMesh:
	var trunk := SurfaceTool.new()
	trunk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.16 + h * 0.012
	cm.height = h * 0.96
	cm.radial_segments = 7
	cm.rings = 1
	trunk.append_from(cm, 0, Transform3D(Basis.IDENTITY, Vector3(0, h * 0.48, 0)))
	var fol := SurfaceTool.new()
	fol.begin(Mesh.PRIMITIVE_TRIANGLES)
	var layers := rng.randi_range(6, 8)
	var base_y := h * rng.randf_range(0.2, 0.3)
	var n := 11
	for i in layers:
		var t := float(i) / float(layers - 1)
		var y0 := base_y + (h * 0.98 - base_y - h * 0.16) * t
		var r := h * 0.21 * (1.0 - t * 0.82) + 0.25
		var lh := h * 0.17 * (1.0 - t * 0.3)
		var apex := Vector3(rng.randf_range(-0.08, 0.08), y0 + lh, rng.randf_range(-0.08, 0.08))
		var under := Vector3(0, y0 + lh * 0.3, 0)
		var ring: Array[Vector3] = []
		var a0 := rng.randf() * TAU
		for k in n:
			var a := a0 + TAU * float(k) / float(n) + rng.randf_range(-0.12, 0.12)
			var rr := r * rng.randf_range(0.72, 1.15)
			ring.append(Vector3(cos(a) * rr, y0 - rr * 0.22 + rng.randf_range(-0.12, 0.12), sin(a) * rr))
			# Zwischenzacke etwas weiter innen und hoeher (zerfranste Kante)
			var am := a + PI / float(n)
			var rm := r * rng.randf_range(0.55, 0.78)
			ring.append(Vector3(cos(am) * rm, y0 - rm * 0.1 + lh * 0.08, sin(am) * rm))
		var m := ring.size()
		for k in m:
			var p0 := ring[k]
			var p1 := ring[(k + 1) % m]
			fol.add_vertex(apex)
			fol.add_vertex(p1)
			fol.add_vertex(p0)
			fol.add_vertex(under)
			fol.add_vertex(p0)
			fol.add_vertex(p1)
	fol.index()
	fol.generate_normals()
	trunk.generate_normals()
	var mesh := trunk.commit()
	fol.commit(mesh)
	mesh.surface_set_material(0, bark())
	mesh.surface_set_material(1, needles())
	return mesh

## Kiefernbestand als MultiMesh (4 Varianten). trees = Array von [Vector3 pos, float scale].
static func forest(parent: Node3D, trees: Array, rng: RandomNumberGenerator, shadows: bool = true) -> void:
	var variants: Array[ArrayMesh] = []
	for v in 4:
		variants.append(pine_mesh(rng, 11.0 + v * 1.6))
	var buckets: Array = [[], [], [], []]
	for t in trees:
		buckets[rng.randi() % 4].append(t)
	for v in 4:
		var list: Array = buckets[v]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = variants[v]
		mm.instance_count = list.size()
		for i in list.size():
			var p: Vector3 = list[i][0]
			var s: float = list[i][1]
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s * rng.randf_range(0.9, 1.1), s, s * rng.randf_range(0.9, 1.1)))
			b = Basis(Vector3(1, 0, 0), rng.randf_range(-0.03, 0.03)) * b
			mm.set_instance_transform(i, Transform3D(b, p + Vector3(0, -0.2, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if not shadows:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)

## Kollision fuer Baumstaemme (ein Body, viele Zylinder).
static func trunk_colliders(parent: Node3D, trees: Array) -> void:
	var b := Geo.static_body()
	for t in trees:
		var p: Vector3 = t[0]
		var s: float = t[1]
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.28 * s + 0.05
		sh.height = 6.0
		cs.shape = sh
		cs.position = p + Vector3(0, 3.0, 0)
		b.add_child(cs)
	parent.add_child(b)

# --------------------------------------------------------------------------- Holzhaus

## Komponenten-Liste eines Holzhauses (lokal, Front zeigt nach +z).
## Rueckgabe: Array von [center, size, Basis, mat_key, chunk]
static func _house_parts(w: float, d: float, wall_h: float, rng: RandomNumberGenerator, opts: Dictionary) -> Array:
	var parts: Array = []
	var hollow: bool = opts.get("hollow", false)
	var lit: float = opts.get("lit", 0.25)
	var y0 := 0.5
	var yw := y0 + wall_h
	parts.append([Vector3(0, 0.25, 0), Vector3(w + 0.12, 0.5, d + 0.12), Basis.IDENTITY, "found", 0])
	if hollow:
		var t := 0.22
		for half: float in [-1.0, 1.0]:
			parts.append([Vector3(half * w / 4.0, y0 + wall_h / 2.0, d / 2.0 - t / 2.0), Vector3(w / 2.0, wall_h, t), Basis.IDENTITY, "wall", 1 if half < 0 else 2])
			parts.append([Vector3(half * w / 4.0, y0 + wall_h / 2.0, -d / 2.0 + t / 2.0), Vector3(w / 2.0, wall_h, t), Basis.IDENTITY, "wall", 3 if half < 0 else 4])
			parts.append([Vector3(half * (w / 2.0 - t / 2.0), y0 + wall_h / 2.0, 0), Vector3(t, wall_h, d - 2.0 * t), Basis.IDENTITY, "wall", 5 if half < 0 else 6])
	else:
		parts.append([Vector3(0, y0 + wall_h / 2.0, 0), Vector3(w, wall_h, d), Basis.IDENTITY, "wall", 1])
	# Eckbretter
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var ch := 1
			if hollow:
				ch = (1 if sx < 0 else 2) if sz > 0 else (3 if sx < 0 else 4)
			parts.append([Vector3(sx * (w / 2.0 + 0.03), y0 + wall_h / 2.0, sz * (d / 2.0 + 0.03)), Vector3(0.16, wall_h, 0.16), Basis.IDENTITY, "trim", ch])
	# Fenster vorn und hinten
	var nwin := maxi(1, int(w / 2.7))
	for side: float in [1.0, -1.0]:
		for i in nwin:
			var x := -w / 2.0 + (i + 0.5) * w / nwin
			if side > 0 and opts.get("door", true) and i == nwin / 2 and nwin > 1:
				# Tuer statt Fenster
				parts.append([Vector3(x, y0 + 1.05, side * (d / 2.0 + 0.04)), Vector3(1.0, 2.1, 0.1), Basis.IDENTITY, "door", 1 if x < 0 else 2])
				parts.append([Vector3(x, y0 + 2.2, side * (d / 2.0 + 0.06)), Vector3(1.25, 0.14, 0.14), Basis.IDENTITY, "trim", 1 if x < 0 else 2])
				continue
			var ch2 := 1
			if hollow:
				ch2 = (1 if x < 0 else 2) if side > 0 else (3 if x < 0 else 4)
			var wy := y0 + wall_h * 0.52
			parts.append([Vector3(x, wy, side * (d / 2.0 + 0.04)), Vector3(1.22, 1.42, 0.08), Basis.IDENTITY, "trim", ch2])
			var is_lit := rng.randf() < lit
			parts.append([Vector3(x, wy, side * (d / 2.0 + 0.07)), Vector3(0.98, 1.18, 0.06), Basis.IDENTITY, "lit" if is_lit else "glass", ch2])
			parts.append([Vector3(x, wy - 0.75, side * (d / 2.0 + 0.12)), Vector3(1.35, 0.08, 0.2), Basis.IDENTITY, "trim", ch2])
			# Fensterkreuz
			parts.append([Vector3(x, wy, side * (d / 2.0 + 0.1)), Vector3(0.06, 1.18, 0.04), Basis.IDENTITY, "trim", ch2])
			parts.append([Vector3(x, wy + 0.12, side * (d / 2.0 + 0.1)), Vector3(0.98, 0.06, 0.04), Basis.IDENTITY, "trim", ch2])
	# Giebel (45 Grad): duenne Rauten an beiden Enden, untere Haelfte steckt in der Wand
	var s := d / sqrt(2.0)
	var rot45 := Basis(Vector3(1, 0, 0), deg_to_rad(45.0))
	for sx: float in [-1.0, 1.0]:
		parts.append([Vector3(sx * (w / 2.0 - 0.12), yw, 0), Vector3(0.24, s, s), rot45, "wall", 7 if sx < 0 else 8])
	if not hollow:
		parts.append([Vector3(0, yw, 0), Vector3(w - 0.4, s * 0.98, s * 0.98), rot45, "wall", 1])
	# Dach: zwei Platten, Ueberstand 0.5
	var ov := 0.55
	var half := d / 2.0 + ov
	var slab_len := half * sqrt(2.0)
	var rise := d / 2.0
	for sz: float in [1.0, -1.0]:
		var zc := sz * half / 2.0
		var yc := yw + rise - half / 2.0 + 0.12
		var rot := Basis(Vector3(1, 0, 0), deg_to_rad(45.0 * sz))
		if hollow:
			for hx: float in [-1.0, 1.0]:
				parts.append([Vector3(hx * (w + 0.9) / 4.0, yc, zc), Vector3((w + 0.9) / 2.0, 0.2, slab_len), rot, "roof", (9 if hx < 0 else 10) if sz > 0 else (11 if hx < 0 else 12)])
		else:
			parts.append([Vector3(0, yc, zc), Vector3(w + 0.9, 0.2, slab_len), rot, "roof", 1])
	# Schornstein
	var cx := rng.randf_range(-w * 0.3, w * 0.3)
	parts.append([Vector3(cx, yw + rise * 0.7 + 0.6, -0.6), Vector3(0.6, rise * 0.9 + 1.0, 0.6), Basis.IDENTITY, "brick", 13 if hollow else 1])
	return parts

static func _house_mats(color: Color) -> Dictionary:
	return {
		"found": concrete(Color(0.45, 0.44, 0.42), 0.6),
		"wall": planks(color, 0.25),
		"trim": planks(Color(0.75, 0.74, 0.7), 0.5),
		"door": planks(Color(0.25, 0.18, 0.13), 0.2),
		"glass": Geo.flat(Color(0.02, 0.025, 0.03), 0.12, 0.3),
		"lit": glow(Color(1.0, 0.58, 0.26), 2.2),
		"roof": metal(Color(0.24, 0.24, 0.23), 0.62),
		"brick": brick(Color(0.55, 0.42, 0.36)),
	}

## Statisches Holzhaus. pos = Bodenmitte, yaw = Drehung (Front = lokal +z).
## size: x = Frontbreite, y = Wandhoehe, z = Tiefe. Rueckgabe: StaticBody3D.
static func house(parent: Node3D, pos: Vector3, yaw_deg: float, size: Vector3, color: Color, rng: RandomNumberGenerator, opts: Dictionary = {}) -> StaticBody3D:
	var parts := _house_parts(size.x, size.z, size.y, rng, opts)
	var mats := _house_mats(color)
	var b := Geo.static_body(pos, yaw_deg)
	var batches: Dictionary = {}
	for p in parts:
		var k: String = p[3]
		if not batches.has(k):
			batches[k] = Geo.batch()
		(batches[k] as Geo.BoxBatch).add(p[0], p[1], p[2])
	for k in batches:
		add_batch(b, batches[k], mats[k], k != "lit" and k != "glass")
	Geo.add_box_shape(b, Vector3(0, (0.5 + size.y) / 2.0, 0), Vector3(size.x + 0.1, 0.5 + size.y, size.z + 0.1))
	parent.add_child(b)
	return b

## Zerlegbares Haus: statische Kollision + eingefrorene RigidBody-Teile (Layer debris).
## Rueckgabe: {body: StaticBody3D, shape: CollisionShape3D, pieces: Array[RigidBody3D], center: Vector3}
static func house_pieces(parent: Node3D, pos: Vector3, yaw_deg: float, size: Vector3, color: Color, rng: RandomNumberGenerator, opts: Dictionary = {}) -> Dictionary:
	var o := opts.duplicate()
	o["hollow"] = true
	var parts := _house_parts(size.x, size.z, size.y, rng, o)
	var mats := _house_mats(color)
	var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)
	var chunks: Dictionary = {}
	for p in parts:
		var c: int = p[4]
		if not chunks.has(c):
			chunks[c] = []
		(chunks[c] as Array).append(p)
	var pieces: Array[RigidBody3D] = []
	var found_body := Geo.static_body(pos, yaw_deg)
	for c in chunks:
		var list: Array = chunks[c]
		if c == 0:
			var fb := Geo.batch()
			for p in list:
				fb.add(p[0], p[1], p[2])
			add_batch(found_body, fb, mats["found"])
			continue
		var centroid := Vector3.ZERO
		for p in list:
			centroid += p[0]
		centroid /= float(list.size())
		var rb := RigidBody3D.new()
		rb.collision_layer = 8
		rb.collision_mask = 1 | 8
		rb.mass = 180.0
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.transform = xf * Transform3D(Basis.IDENTITY, centroid)
		var batches: Dictionary = {}
		var big := Vector3.ZERO
		for p in list:
			var k: String = p[3]
			if not batches.has(k):
				batches[k] = Geo.batch()
			(batches[k] as Geo.BoxBatch).add((p[0] as Vector3) - centroid, p[1], p[2])
			if (p[1] as Vector3).length() > big.length():
				big = p[1]
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = (p[1] as Vector3).max(Vector3(0.2, 0.2, 0.2))
				cs.shape = bs
				cs.transform = Transform3D(p[2], (p[0] as Vector3) - centroid)
				for old in rb.get_children():
					if old is CollisionShape3D:
						old.queue_free()
				rb.add_child(cs)
		for k in batches:
			add_batch(rb, batches[k], mats[k], k != "lit" and k != "glass")
		parent.add_child(rb)
		pieces.append(rb)
	var shape := Geo.add_box_shape(found_body, Vector3(0, (0.5 + size.y) / 2.0, 0), Vector3(size.x + 0.1, 0.5 + size.y, size.z + 0.1))
	parent.add_child(found_body)
	return {"body": found_body, "shape": shape, "pieces": pieces, "center": pos + Vector3(0, size.y * 0.6, 0), "size": size, "yaw": yaw_deg}

# --------------------------------------------------------------------------- Graben, Sandsaecke, Draht

## Sandsackwall mit frei waehlbarer Lagenzahl (niedrige Grabenbrustwehr).
static func sandbags(parent: Node3D, pos: Vector3, yaw_deg: float, length: float, layers: int, rng: RandomNumberGenerator, covers: Array, collide: bool = true) -> void:
	var b := Geo.static_body(pos, yaw_deg)
	var bb := Geo.batch()
	var n := maxi(2, int(length / 0.55))
	for layer in layers:
		var off := 0.27 if layer % 2 == 1 else 0.0
		var cnt := n if off == 0.0 else n - 1
		for i in cnt:
			var z := -length / 2.0 + 0.3 + off + i * ((length - 0.6) / maxf(n - 1, 1))
			var sz := Vector3(rng.randf_range(0.44, 0.52), rng.randf_range(0.24, 0.3), rng.randf_range(0.58, 0.66))
			var rot := Basis(Vector3.UP, rng.randf_range(-0.12, 0.12)) * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
			for row: float in [-1.0, 1.0]:
				bb.add_ball(Vector3(row * 0.24 + rng.randf_range(-0.03, 0.03), 0.14 + layer * 0.23, z), sz, rot)
	add_batch(b, bb, sand_mat())
	var h := 0.14 + layers * 0.23
	if collide:
		Geo.add_box_shape(b, Vector3(0, h / 2.0, 0), Vector3(0.9, h, length))
	parent.add_child(b)
	if collide:
		var bs := Basis(Vector3.UP, deg_to_rad(yaw_deg))
		var zs: Array = [0.0] if length < 4.0 else [-length * 0.25, length * 0.25]
		for z in zs:
			covers.append(pos + bs * Vector3(1.35, 0, z))
			covers.append(pos + bs * Vector3(-1.35, 0, z))

## Holzverschalung einer Grabenwand: Bretter + Pfosten. a/b = Endpunkte am Boden (y = Sohle),
## h = Hoehe, inward = Richtung zur Grabenmitte (Bretter sitzen davor).
static func revetment(bb_planks: Geo.BoxBatch, bb_posts: Geo.BoxBatch, a: Vector3, b: Vector3, h: float, inward: Vector3, rng: RandomNumberGenerator) -> void:
	var dir := b - a
	var length := dir.length()
	var yaw := atan2(dir.x, dir.z)
	var rot := Basis(Vector3.UP, yaw)
	var rows := int(h / 0.22)
	for r in rows:
		var y := a.y + 0.11 + r * 0.22
		var c := (a + b) / 2.0 + inward * 0.04
		c.y = y
		var tilt := Basis(Vector3(0, 0, 1), rng.randf_range(-0.01, 0.01))
		bb_planks.add(c, Vector3(0.05, 0.2, length + rng.randf_range(-0.1, 0.1)), rot * tilt)
	var np := maxi(2, int(length / 1.6) + 1)
	for i in np:
		var p := a.lerp(b, float(i) / float(np - 1)) + inward * 0.1
		p.y = a.y + h / 2.0 + 0.1
		bb_posts.add(p, Vector3(0.14, h + 0.2 + rng.randf_range(0.0, 0.15), 0.14), rot)

## Stacheldraht-Rolle (Concertina) entlang einer Linie, mit Pfaehlen. Optional Kollision.
static func wire(parent: Node3D, a: Vector3, b: Vector3, collide: bool = true) -> void:
	var dir := b - a
	var length := dir.length()
	var yaw := atan2(dir.x, dir.z)
	var body := Geo.static_body((a + b) / 2.0, rad_to_deg(yaw))
	var tor := TorusMesh.new()
	tor.inner_radius = 0.42
	tor.outer_radius = 0.45
	tor.rings = 14
	tor.ring_segments = 4
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := int(length / 0.3)
	for i in n:
		var z := -length / 2.0 + (i + 0.5) * length / n
		var tb := Basis(Vector3(1, 0, 0), PI / 2.0) * Basis(Vector3(0, 0, 1), 0.0)
		tb = Basis(Vector3(1, 0, 0), deg_to_rad(90.0 + (12.0 if i % 2 == 0 else -12.0)))
		st.append_from(tor, 0, Transform3D(tb, Vector3(sin(i * 1.7) * 0.04, 0.45, z)))
	var wm := Geo.flat(Color(0.28, 0.27, 0.26), 0.45, 0.8)
	body.add_child(Geo.mesh_node(st.commit(), wm))
	var posts := Geo.batch()
	var np := maxi(2, int(length / 3.0) + 1)
	for i in np:
		var z := -length / 2.0 + i * length / (np - 1)
		posts.add(Vector3(0, 0.55, z), Vector3(0.08, 1.1, 0.08), Basis(Vector3(1, 0, 0), 0.1 * sin(i * 2.3)))
	add_batch(body, posts, planks(Color(0.35, 0.3, 0.25), 0.4))
	if collide:
		Geo.add_box_shape(body, Vector3(0, 0.5, 0), Vector3(0.9, 1.0, length))
	parent.add_child(body)

## Spanischer Reiter (X-Holzgestell mit Draht).
static func knife_rest(parent: Node3D, pos: Vector3, yaw_deg: float, covers: Array) -> void:
	var b := Geo.static_body(pos, yaw_deg)
	var bb := Geo.batch()
	bb.add(Vector3(0, 0.6, 0), Vector3(0.12, 0.12, 3.0))
	for z: float in [-1.3, 0.0, 1.3]:
		bb.add(Vector3(0, 0.55, z), Vector3(0.1, 1.5, 0.1), Basis(Vector3(0, 0, 1), deg_to_rad(40.0)))
		bb.add(Vector3(0, 0.55, z), Vector3(0.1, 1.5, 0.1), Basis(Vector3(0, 0, 1), deg_to_rad(-40.0)))
	add_batch(b, bb, planks(Color(0.4, 0.33, 0.26), 0.45))
	var wb := Geo.batch()
	for k in 6:
		wb.add(Vector3(sin(k * 1.3) * 0.35, 0.3 + k * 0.13, 0), Vector3(0.015, 0.015, 3.0), Basis(Vector3(1, 0, 0), 0.04 * sin(k * 2.1)))
	add_batch(b, wb, Geo.flat(Color(0.25, 0.24, 0.23), 0.4, 0.8))
	Geo.add_box_shape(b, Vector3(0, 0.55, 0), Vector3(1.4, 1.1, 3.0))
	parent.add_child(b)
	covers.append(pos + Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3(1.3, 0, 0))

# --------------------------------------------------------------------------- Strommasten

## Holzmasten mit durchhaengenden Leitungen entlang einer Punktliste. broken = Indizes schiefer Masten.
static func power_line(parent: Node3D, pts: Array, rng: RandomNumberGenerator, collide_box: AABB = AABB()) -> void:
	var wood := planks(Color(0.3, 0.25, 0.2), 0.3)
	var poles := Geo.batch()
	var wires := Geo.batch()
	var ins := Geo.batch()
	var tops: Array = []
	var col := Geo.static_body()
	for i in pts.size():
		var p: Vector3 = pts[i]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var prv: Vector3 = pts[maxi(i - 1, 0)]
		var d := (nxt - prv)
		d.y = 0.0
		var yaw := atan2(d.x, d.z)
		var lean := rng.randf_range(-0.04, 0.04)
		var rot := Basis(Vector3.UP, yaw) * Basis(Vector3(1, 0, 0), lean)
		var h := 8.5
		poles.add(p + rot * Vector3(0, h / 2.0, 0), Vector3(0.26, h, 0.26), rot)
		poles.add(p + rot * Vector3(0, h - 0.6, 0), Vector3(2.4, 0.16, 0.16), rot)
		var t3: Array = []
		for ox: float in [-1.0, 0.0, 1.0]:
			var tp: Vector3 = p + rot * Vector3(ox, h - 0.42 + (0.25 if ox == 0.0 else 0.0), 0)
			ins.add(tp - Vector3(0, 0.1, 0), Vector3(0.08, 0.2, 0.08))
			t3.append(tp)
		tops.append(t3)
		if collide_box.size != Vector3.ZERO and collide_box.has_point(p + Vector3(0, 1, 0)):
			Geo.add_box_shape(col, p + Vector3(0, 2.0, 0), Vector3(0.35, 4.0, 0.35))
	for i in range(1, tops.size()):
		for k in 3:
			var a: Vector3 = tops[i - 1][k]
			var b: Vector3 = tops[i][k]
			var segs := 10
			var sag := a.distance_to(b) * 0.035
			var prev := a
			for s in range(1, segs + 1):
				var t := float(s) / segs
				var q := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
				var mid := (prev + q) / 2.0
				var dd := q - prev
				var bas := Basis.looking_at(dd.normalized(), Vector3.UP) if dd.length() > 0.01 else Basis.IDENTITY
				wires.add(mid, Vector3(0.025, 0.025, dd.length() + 0.02), bas)
				prev = q
	add_batch(parent, poles, wood)
	add_batch(parent, wires, Geo.flat(Color(0.05, 0.05, 0.05), 0.5, 0.6), false)
	add_batch(parent, ins, Geo.flat(Color(0.5, 0.55, 0.5), 0.2))
	if col.get_child_count() > 0:
		parent.add_child(col)
	else:
		col.free()

# --------------------------------------------------------------------------- Fahrzeuge

## Liegengebliebener Schuetzenpanzer (angelehnt an CV90), leicht schraeg, Heckluke offen.
static func ifv(parent: Node3D, pos: Vector3, yaw_deg: float, covers: Array) -> StaticBody3D:
	var b := Geo.static_body(pos, yaw_deg)
	var root := Node3D.new()
	root.rotation_degrees = Vector3(-2.5, 0, 4.0)
	b.add_child(root)
	var hull_m := metal(Color(0.3, 0.33, 0.27), 0.55)
	var dark := metal(Color(0.1, 0.1, 0.09), 0.3)
	var hull := Geo.batch()
	hull.add(Vector3(0, 1.15, 0), Vector3(3.1, 1.1, 6.4))
	hull.add(Vector3(0, 0.9, 3.4), Vector3(3.0, 0.8, 1.0), Basis(Vector3(1, 0, 0), deg_to_rad(-35.0)))
	hull.add(Vector3(0, 1.75, 1.7), Vector3(3.0, 0.3, 2.6), Basis(Vector3(1, 0, 0), deg_to_rad(-8.0)))
	for sx: float in [-1.0, 1.0]:
		hull.add(Vector3(sx * 1.62, 1.2, 0), Vector3(0.12, 0.7, 6.6))
	# Turm + Kanone
	hull.add(Vector3(0.1, 2.15, -0.4), Vector3(2.0, 0.7, 2.6))
	hull.add(Vector3(0.1, 2.25, 1.1), Vector3(1.1, 0.5, 0.6))
	hull.add(Vector3(-0.6, 2.6, -1.0), Vector3(0.5, 0.3, 0.6))
	root.add_child(Geo.mesh_node(hull.build(), hull_m))
	var gun := Geo.cylinder_node(0.07, 3.2, dark, Vector3(0.1, 2.25, 3.0), Vector3(88.0, 0, 0), 8)
	root.add_child(gun)
	var tracks := Geo.batch()
	var wheel_m := Geo.flat(Color(0.06, 0.06, 0.055), 0.8, 0.3)
	for sx: float in [-1.0, 1.0]:
		tracks.add(Vector3(sx * 1.45, 0.45, 0), Vector3(0.6, 0.9, 6.9))
		for k in 7:
			root.add_child(Geo.cylinder_node(0.38, 0.5, wheel_m, Vector3(sx * 1.48, 0.42, -2.8 + k * 0.93), Vector3(0, 0, 90), 12))
	root.add_child(Geo.mesh_node(tracks.build(), dark))
	# Heckluke offen (Rampe), Innenraum rot beleuchtet
	var ramp := Geo.box_mesh_node(Vector3(1.6, 0.08, 1.6), hull_m, Vector3(0, 0.55, -3.9), Vector3(-30, 0, 0))
	root.add_child(ramp)
	root.add_child(Geo.box_mesh_node(Vector3(1.5, 1.0, 0.05), Geo.flat(Color(0.02, 0.02, 0.02), 0.9), Vector3(0, 1.15, -3.18)))
	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.12, 0.08)
	red.light_energy = 2.2
	red.omni_range = 5.0
	red.light_volumetric_fog_energy = 2.0
	red.position = Vector3(0, 1.2, -3.6)
	root.add_child(red)
	Geo.add_box_shape(b, Vector3(0, 1.1, 0), Vector3(3.3, 2.2, 7.0), Vector3(-2.5, 0, 4.0))
	Geo.add_box_shape(b, Vector3(0.1, 2.3, -0.4), Vector3(2.0, 0.9, 2.6), Vector3(-2.5, 0, 4.0))
	parent.add_child(b)
	var bs := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	for v: Vector3 in [Vector3(2.6, 0, -1.8), Vector3(2.6, 0, 1.8), Vector3(-2.6, 0, -1.8), Vector3(-2.6, 0, 1.8), Vector3(0, 0, -5.4), Vector3(0, 0, 4.6)]:
		covers.append(pos + bs * v)
	return b

## Bauernwagen bzw. Heuwagen, umgekippt moeglich.
static func cart(parent: Node3D, pos: Vector3, yaw_deg: float, tipped: bool, covers: Array) -> void:
	var b := Geo.static_body(pos, yaw_deg)
	var root := Node3D.new()
	if tipped:
		root.rotation_degrees.z = 80.0
		root.position = Vector3(0.6, 0.15, 0)
	b.add_child(root)
	var bb := Geo.batch()
	bb.add(Vector3(0, 0.9, 0), Vector3(1.8, 0.12, 3.6))
	for sx: float in [-1.0, 1.0]:
		bb.add(Vector3(sx * 0.9, 1.2, 0), Vector3(0.08, 0.5, 3.6))
	bb.add(Vector3(0, 1.2, 1.8), Vector3(1.8, 0.5, 0.08))
	bb.add(Vector3(0, 0.75, 2.6), Vector3(0.1, 0.1, 2.0))
	root.add_child(Geo.mesh_node(bb.build(), planks(Color(0.42, 0.33, 0.24), 0.5)))
	for sx: float in [-1.0, 1.0]:
		for z: float in [-1.2, 1.2]:
			root.add_child(Geo.cylinder_node(0.45, 0.1, planks(Color(0.3, 0.24, 0.18), 0.3), Vector3(sx * 1.0, 0.45, z), Vector3(0, 0, 90), 10))
	Geo.add_box_shape(b, Vector3(0, 0.75, 0), Vector3(2.0, 1.5, 3.6))
	parent.add_child(b)
	var bs := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	covers.append(pos + bs * Vector3(1.8, 0, 0))
	covers.append(pos + bs * Vector3(-1.8, 0, 0))

## Holzkisten-Stapel (Munitionskisten).
static func crates(parent: Node3D, pos: Vector3, yaw_deg: float, rng: RandomNumberGenerator, covers: Array) -> void:
	var b := Geo.static_body(pos, yaw_deg)
	var bb := Geo.batch()
	var n := rng.randi_range(3, 6)
	for i in n:
		var lvl := 0 if i < 3 else 1
		bb.add(Vector3((i % 3 - 1) * 0.75 + rng.randf_range(-0.05, 0.05), 0.25 + lvl * 0.5, rng.randf_range(-0.08, 0.08)), Vector3(0.7, 0.48, 0.5), Basis(Vector3.UP, rng.randf_range(-0.15, 0.15)))
	add_batch(b, bb, planks(Color(0.33, 0.36, 0.26), 0.55))
	Geo.add_box_shape(b, Vector3(0, 0.5, 0), Vector3(2.3, 1.0, 0.7))
	parent.add_child(b)
	var bs := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	covers.append(pos + bs * Vector3(0, 0, 1.2))
	covers.append(pos + bs * Vector3(0, 0, -1.2))

## Holzzaun (Latten), nur Optik oder mit niedriger Kollision.
static func fence(parent: Node3D, a: Vector3, b: Vector3, rng: RandomNumberGenerator, collide: bool = false, gaps: float = 0.15) -> void:
	var dir := b - a
	var length := dir.length()
	var yaw := atan2(dir.x, dir.z)
	var rot := Basis(Vector3.UP, yaw)
	var bb := Geo.batch()
	var n := int(length / 0.18)
	for i in n:
		if rng.randf() < gaps:
			continue
		var p := a.lerp(b, (i + 0.5) / n)
		var h := rng.randf_range(1.0, 1.3)
		bb.add(p + Vector3(0, h / 2.0, 0), Vector3(0.1, h, 0.03), rot * Basis(Vector3(0, 0, 1), rng.randf_range(-0.08, 0.08)))
	for y: float in [0.35, 0.95]:
		bb.add((a + b) / 2.0 + Vector3(0, y, 0), Vector3(0.05, 0.08, length), rot)
	var m := planks(Color(0.45, 0.4, 0.34), 0.5)
	if collide:
		var body := Geo.static_body()
		add_batch(body, bb, m)
		Geo.add_box_shape(body, (a + b) / 2.0 + Vector3(0, 0.6, 0), Vector3(0.12, 1.2, length), Vector3(0, rad_to_deg(yaw), 0))
		parent.add_child(body)
	else:
		add_batch(parent, bb, m)

## Strohballen-Gruppe.
static func hay(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, covers: Array) -> void:
	var b := Geo.static_body(pos)
	var m := snowy("", Color(0.5, 0.42, 0.25), 1.0, 0.45, {"color_noise": 0.5, "noise_scale": 0.6})
	for i in 3:
		var c := Geo.cylinder_node(0.65, 1.2, m, Vector3((i - 1) * 1.35, 0.65, rng.randf_range(-0.2, 0.2)), Vector3(90, rng.randf_range(-10, 10), 0), 14)
		b.add_child(c)
	Geo.add_box_shape(b, Vector3(0, 0.65, 0), Vector3(4.0, 1.3, 1.3))
	parent.add_child(b)
	covers.append(pos + Vector3(0, 0, 1.6))
	covers.append(pos + Vector3(0, 0, -1.6))
