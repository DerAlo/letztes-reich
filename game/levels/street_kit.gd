extends RefCounted
## Bodendetail und Strassenmoeblierung fuer Stadtlevel (test_range, berlin): Decals (Risse, Flicken,
## Pfuetzen, Fahrbahnmarkierung, Laub, Papier, Brandflecken, Gullys), glitzernde Glasscherben (MultiMesh),
## Bordsteine, Kabel, Schilder, Ampeln, Absperrgitter und Poly-Haven-Modelle (CC0) an den Hauswaenden.
## Alles ohne Kollision: Deckung, Route und Navmesh bleiben unveraendert. Wandobjekte liegen innerhalb
## von ~0,45 m vor der Fassade (dort ist ohnehin der Navmesh-Rand).

const Geo = preload("res://game/levels/level_geo.gd")
const FK = preload("res://game/levels/facade_kit.gd")
const MODELS := "res://assets/environment/street/models/%s/%s.gltf"

static var _scenes: Dictionary = {}
static var _mats: Dictionary = {}

# --------------------------------------------------------------------------- Modelle

## Instanziert ein Poly-Haven-Modell (Unterkante auf pos.y). vis > 0 begrenzt die Sichtweite.
static func model(parent: Node3D, mname: String, pos: Vector3, yaw_deg: float, scale: float = 1.0, vis: float = 0.0, shadows: bool = true) -> Node3D:
	if not _scenes.has(mname):
		_scenes[mname] = load(MODELS % [mname, mname])
	var ps: PackedScene = _scenes[mname]
	if ps == null:
		return null
	var inst := ps.instantiate() as Node3D
	var root := Node3D.new()
	root.name = "M_" + mname
	root.add_child(inst)
	inst.scale = Vector3.ONE * scale
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		if vis > 0.0:
			mi.visibility_range_end = vis
			mi.visibility_range_end_margin = 6.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	parent.add_child(root)
	return root

# --------------------------------------------------------------------------- Materialien

static func _metal() -> StandardMaterial3D:
	if not _mats.has("metal"):
		_mats["metal"] = Geo.mat("rusty_metal_02", Color(0.55, 0.56, 0.56), 0.8, 0.8, 0.7)
	return _mats["metal"]

static func _galv() -> StandardMaterial3D:
	if not _mats.has("galv"):
		_mats["galv"] = Geo.flat(Color(0.55, 0.57, 0.58), 0.38, 0.85)
	return _mats["galv"]

static func _curb_mat() -> StandardMaterial3D:
	if not _mats.has("curb"):
		_mats["curb"] = Geo.mat("concrete_wall_008", Color(0.62, 0.61, 0.58), 0.9, 1.0)
	return _mats["curb"]

static func _glass_mat() -> StandardMaterial3D:
	if not _mats.has("shard"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.32, 0.38, 0.36)
		m.roughness = 0.03
		m.metallic = 0.55
		m.metallic_specular = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats["shard"] = m
	return _mats["shard"]

# --------------------------------------------------------------------------- Boden

## Bordsteinkante (nur Optik) entlang z: x = Aussenkante zur Fahrbahn, sx = Richtung zum Gehweg.
static func curb(parent: Node3D, x: float, sx: float, z0: float, z1: float, top: float = 0.16) -> void:
	var b := Geo.batch()
	var L := absf(z0 - z1)
	var seg := 1.0
	var k := int(L / seg)
	for i in k:
		var z := minf(z0, z1) + (float(i) + 0.5) * seg
		b.add(Vector3(x + sx * 0.08, top * 0.5 - 0.02, z), Vector3(0.16, top + 0.04, seg - 0.012))
	var mi := Geo.mesh_node(b.build(), _curb_mat())
	mi.name = "Curb"
	parent.add_child(mi)

## Streut Boden-Decals auf ein Rechteck (x0..x1, z0..z1, y = Hoehe). counts: crack, patch, puddle,
## leaves, paper, scorch (Anzahl je Typ). wet: Pfuetzen spiegeln staerker.
static func ground_decals(parent: Node3D, rng: RandomNumberGenerator, x0: float, x1: float, z0: float, z1: float, y: float, counts: Dictionary) -> void:
	var up := Vector3.UP
	var zmin := minf(z0, z1)
	var zmax := maxf(z0, z1)
	for i in int(counts.get("crack", 0)):
		var s := rng.randf_range(2.5, 5.0)
		FK.decal(parent, Vector3(rng.randf_range(x0, x1), y, rng.randf_range(zmin, zmax)), up, Vector2(s, s), "crack.png", {"normal": "crack_n.png", "roll": rng.randf_range(0, 360), "depth": 0.4, "fade": 40.0})
	for i in int(counts.get("patch", 0)):
		FK.decal(parent, Vector3(rng.randf_range(x0, x1), y, rng.randf_range(zmin, zmax)), up, Vector2(rng.randf_range(1.4, 3.2), rng.randf_range(1.2, 2.6)), "patch.png", {"roll": rng.randf_range(-8, 8) + 90.0 * float(rng.randi() % 2), "depth": 0.4, "fade": 55.0, "mix": 0.95})
	for i in int(counts.get("puddle", 0)):
		var s2 := rng.randf_range(1.6, 3.8)
		FK.decal(parent, Vector3(rng.randf_range(x0, x1), y, rng.randf_range(zmin, zmax)), up, Vector2(s2, s2 * rng.randf_range(0.6, 1.0)), "puddle.png", {"orm": "puddle_orm.png", "roll": rng.randf_range(0, 360), "depth": 0.4, "fade": 60.0, "mix": 0.55})
	for i in int(counts.get("leaves", 0)):
		var s3 := rng.randf_range(1.0, 2.2)
		FK.decal(parent, Vector3(rng.randf_range(x0, x1), y, rng.randf_range(zmin, zmax)), up, Vector2(s3, s3), "leaves.png", {"roll": rng.randf_range(0, 360), "depth": 0.5, "fade": 35.0})
	for i in int(counts.get("paper", 0)):
		var s4 := rng.randf_range(0.9, 1.8)
		FK.decal(parent, Vector3(rng.randf_range(x0, x1), y, rng.randf_range(zmin, zmax)), up, Vector2(s4, s4), "paper.png", {"roll": rng.randf_range(0, 360), "depth": 0.5, "fade": 32.0})
	for i in int(counts.get("scorch", 0)):
		var s5 := rng.randf_range(2.5, 4.5)
		FK.decal(parent, Vector3(rng.randf_range(x0, x1), y, rng.randf_range(zmin, zmax)), up, Vector2(s5, s5), "scorch.png", {"roll": rng.randf_range(0, 360), "depth": 0.8, "fade": 60.0})

## Abgefahrene Fahrbahnmarkierung: Leitlinie (gestrichelt) in der Mitte, durchgezogene Randlinien.
static func lane_marks(parent: Node3D, z0: float, z1: float, y: float, edge_x: float, dash: float = 3.0, gap: float = 6.0) -> void:
	var zmin := minf(z0, z1)
	var zmax := maxf(z0, z1)
	var z := zmax - 1.0
	while z - dash > zmin:
		FK.decal(parent, Vector3(0, y, z - dash * 0.5), Vector3.UP, Vector2(0.15, dash), "paint_worn.png", {"depth": 0.3, "fade": 50.0, "mix": 0.9})
		z -= dash + gap
	if edge_x > 0.0:
		var seg := 8.0
		var zz := zmax
		while zz - seg > zmin:
			for sx: float in [-1.0, 1.0]:
				FK.decal(parent, Vector3(sx * edge_x, y, zz - seg * 0.5), Vector3.UP, Vector2(0.12, seg), "paint_worn.png", {"depth": 0.3, "fade": 40.0, "mix": 0.75, "roll": 180.0 * float(int(zz) % 2)})
			zz -= seg

## Strassenablauf (Gully) an der Bordsteinkante, x = Lage der Rostmitte.
static func gully(parent: Node3D, x: float, z: float, y: float) -> void:
	FK.decal(parent, Vector3(x, y, z), Vector3.UP, Vector2(0.45, 0.6), "gully.png", {"normal": "gully_n.png", "depth": 0.3, "fade": 35.0})

## Glasscherben als MultiMesh: kleine Quads, leicht gekippt, damit sie in Sonne/Licht glitzern.
static func glass_shards(parent: Node3D, rng: RandomNumberGenerator, center: Vector3, radius_x: float, radius_z: float, count: int) -> MultiMeshInstance3D:
	var qm := QuadMesh.new()
	qm.size = Vector2(0.05, 0.035)
	qm.orientation = PlaneMesh.FACE_Y
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = qm
	mm.instance_count = count
	for i in count:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf())
		var p := center + Vector3(cos(a) * r * radius_x, 0.006, sin(a) * r * radius_z)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.35, 0.35))
		b = b.scaled(Vector3.ONE * rng.randf_range(0.5, 2.2))
		mm.set_instance_transform(i, Transform3D(b, p))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "GlassShards"
	mmi.multimesh = mm
	mmi.material_override = _glass_mat()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 32.0
	mmi.visibility_range_end_margin = 4.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mmi)
	return mmi

# --------------------------------------------------------------------------- Moeblierung

## Haengendes Kabel zwischen a und b (Kettenlinie mit Durchhang sag), in einen Sammel-Batch.
static func cable(bb: Geo.BoxBatch, a: Vector3, b: Vector3, sag: float, thick: float = 0.025, segs: int = 14) -> void:
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var p := a.lerp(b, t) - Vector3.UP * (sag * 4.0 * t * (1.0 - t))
		var d := p - prev
		var L := d.length()
		if L > 0.001:
			var z := d / L
			var x := Vector3.UP.cross(z)
			if x.length() < 0.01:
				x = Vector3.RIGHT
			x = x.normalized()
			var y := z.cross(x)
			bb.add((p + prev) * 0.5, Vector3(thick, thick, L + 0.01), Basis(x, y, z))
		prev = p

static func cables_node(parent: Node3D, bb: Geo.BoxBatch) -> void:
	if bb.count == 0:
		return
	var mi := Geo.mesh_node(bb.build(), Geo.flat(Color(0.03, 0.03, 0.03), 0.6))
	mi.name = "Cables"
	parent.add_child(mi)

## Verkehrsschild auf Pfosten. kind: "stop", "prio" (Vorfahrt), "blue" (Hinweis), "noentry".
static func sign_post(bb: Geo.BoxBatch, parent: Node3D, pos: Vector3, yaw_deg: float, kind: String, lean_deg: float = 0.0) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = Vector3(0, yaw_deg, lean_deg)
	parent.add_child(root)
	root.add_child(Geo.cylinder_node(0.03, 2.6, _galv(), Vector3(0, 1.3, 0), Vector3.ZERO, 8))
	var col := Color(0.6, 0.06, 0.05)
	match kind:
		"blue":
			col = Color(0.05, 0.18, 0.45)
		"prio":
			col = Color(0.85, 0.65, 0.05)
	var face := Geo.flat(col, 0.45, 0.0)
	var white := Geo.flat(Color(0.82, 0.82, 0.8), 0.45)
	if kind == "prio":
		var p := Geo.box_mesh_node(Vector3(0.42, 0.42, 0.02), white, Vector3(0, 2.35, 0.05), Vector3(0, 0, 45))
		root.add_child(p)
		root.add_child(Geo.box_mesh_node(Vector3(0.3, 0.3, 0.02), face, Vector3(0, 2.35, 0.062), Vector3(0, 0, 45)))
	elif kind == "blue":
		root.add_child(Geo.box_mesh_node(Vector3(0.55, 0.55, 0.02), face, Vector3(0, 2.3, 0.05)))
		root.add_child(Geo.box_mesh_node(Vector3(0.1, 0.36, 0.01), white, Vector3(0, 2.3, 0.064)))
	else:
		root.add_child(Geo.cylinder_node(0.3, 0.02, face, Vector3(0, 2.3, 0.05), Vector3(90, 0, 0), 20))
		root.add_child(Geo.box_mesh_node(Vector3(0.38, 0.08, 0.01), white, Vector3(0, 2.3, 0.066)))
	root.add_child(Geo.box_mesh_node(Vector3(0.08, 0.08, 0.06), _galv(), Vector3(0, 2.3, 0.02)))

## Ampel am Mast mit Ausleger. state: "off" (Stromausfall), "red", "green", "amber_blink".
static func traffic_light(parent: Node3D, pos: Vector3, yaw_deg: float, state: String = "off") -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	parent.add_child(root)
	var paint := Geo.flat(Color(0.12, 0.13, 0.12), 0.55, 0.3)
	root.add_child(Geo.cylinder_node(0.09, 4.6, paint, Vector3(0, 2.3, 0), Vector3.ZERO, 10))
	root.add_child(Geo.box_mesh_node(Vector3(0.08, 0.08, 2.6), paint, Vector3(0, 4.45, 1.3)))
	for hz: float in [0.0, 2.4]:
		var hy := 2.9 if hz == 0.0 else 4.0
		var hx := 0.18 if hz == 0.0 else 0.0
		var hc := Vector3(hx, hy, hz)
		root.add_child(Geo.box_mesh_node(Vector3(0.3, 0.92, 0.26), paint, hc))
		for k in 3:
			var on := (state == "red" and k == 0) or (state == "amber_blink" and k == 1) or (state == "green" and k == 2)
			var lc: Color = [Color(1.0, 0.08, 0.04), Color(1.0, 0.55, 0.05), Color(0.1, 1.0, 0.45)][k]
			var lm := Geo.flat(lc * (1.0 if on else 0.12), 0.25, 0.0, lc, 3.5 if on else 0.0)
			root.add_child(Geo.cylinder_node(0.1, 0.03, lm, hc + Vector3(0.155, 0.28 - k * 0.28, 0), Vector3(0, 0, 90), 14))
			root.add_child(Geo.box_mesh_node(Vector3(0.12, 0.03, 0.22), paint, hc + Vector3(0.2, 0.39 - k * 0.28, 0)))

## Absperrgitter (Hamburger Gitter) entlang einer Linie ab pos in Richtung yaw, n Elemente.
static func barrier_fence(bb: Geo.BoxBatch, pos: Vector3, yaw_deg: float, n: int, rng: RandomNumberGenerator, toppled: int = -1) -> void:
	var R := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var w := 2.2
	var hgt := 1.1
	for i in n:
		var c := pos + R * Vector3(0, 0, (float(i) + 0.5) * (w + 0.06))
		var eb := R * Basis(Vector3.UP, deg_to_rad(rng.randf_range(-4.0, 4.0)))
		var lift := 0.0
		if i == toppled:
			eb = eb * Basis(Vector3.BACK, deg_to_rad(86.0))
			lift = -0.5
		var o := c + Vector3.UP * (0.1 + lift)
		# Rahmen
		bb.add(o + eb * Vector3(0, hgt, 0), Vector3(0.035, 0.035, w), eb)
		bb.add(o + eb * Vector3(0, 0.08, 0), Vector3(0.035, 0.035, w), eb)
		for s: float in [-1.0, 1.0]:
			bb.add(o + eb * Vector3(0, hgt * 0.5, s * w * 0.5), Vector3(0.035, hgt, 0.035), eb)
			# Fuesse
			bb.add(c + eb * Vector3(0, 0.05, s * (w * 0.5 - 0.1)), Vector3(0.6, 0.04, 0.06), eb)
		# Staebe
		var k := 15
		for j in range(1, k):
			bb.add(o + eb * Vector3(0, hgt * 0.5, -w * 0.5 + w * float(j) / float(k)), Vector3(0.016, hgt, 0.016), eb)

static func fences_node(parent: Node3D, bb: Geo.BoxBatch) -> void:
	if bb.count == 0:
		return
	var mi := Geo.mesh_node(bb.build(), _galv())
	mi.name = "Fences"
	parent.add_child(mi)

# --------------------------------------------------------------------------- Komplett-Ausstattung

## Moebliert eine gerade Strasse entlang -z. opts:
##   road (halbe Fahrbahnbreite), wall (x der Fassaden), y_walk (Hoehe Gehweg), z0/z1 (Bereich),
##   style "war" | "city", seed, avoid (Array[Vector2] (x,z), Stellen ohne Wandobjekte, z. B. Tueren)
static func dress_street(parent: Node3D, opts: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 1))
	var road: float = opts.get("road", 7.0)
	var wall: float = opts.get("wall", 10.0)
	var yw: float = opts.get("y_walk", 0.14)
	var z0: float = opts.get("z0", 0.0)
	var z1: float = opts.get("z1", -180.0)
	var war: bool = opts.get("style", "war") == "war"
	var L := absf(z0 - z1)
	var zmax := maxf(z0, z1)
	var zmin := minf(z0, z1)
	# Fahrbahn: Risse, Flicken, Pfuetzen, Brand, Laub und Papier an den Raendern
	var per := L / 100.0
	ground_decals(parent, rng, -road + 0.8, road - 0.8, zmin, zmax, 0.0, {
		"crack": int(10 * per), "patch": int(8 * per), "puddle": int((7 if war else 10) * per),
		"scorch": int((5 if war else 0) * per)})
	for sx: float in [-1.0, 1.0]:
		ground_decals(parent, rng, sx * (road - 1.0), sx * (road - 0.3), zmin, zmax, 0.0, {"leaves": int(6 * per), "paper": int(5 * per)})
		ground_decals(parent, rng, sx * (road + 0.6), sx * (wall - 0.6), zmin, zmax, yw, {"leaves": int(4 * per), "paper": int(4 * per), "crack": int(3 * per), "puddle": int(2 * per)})
		# Gullys an der Bordsteinkante
		var gz := zmax - rng.randf_range(4.0, 10.0)
		while gz > zmin:
			gully(parent, sx * (road - 0.32), gz, 0.0)
			gz -= rng.randf_range(16.0, 22.0)
	# Kanaldeckel (flach, ohne Kollision)
	var mz := zmax - 12.0
	while mz > zmin:
		model(parent, "water_manhole_cover", Vector3(rng.randf_range(-2.5, 2.5), -0.035, mz), rng.randf() * 360.0, 1.0, 45.0, false)
		mz -= rng.randf_range(28.0, 40.0)
	# Wandobjekte (wandbuendig; an der Wand ist der Navmesh-Rand ohnehin 0,5 m entfernt)
	var avoid: Array = opts.get("avoid", [])
	var fb := Geo.BoxBatch.new()
	for sx: float in [-1.0, 1.0]:
		var yaw := -90.0 * sx   # Modelle schauen mit +z zur Strasse
		var wx := sx * wall
		var z := zmax - rng.randf_range(2.0, 6.0)
		while z > zmin + 2.0:
			var blocked := false
			for a: Vector2 in avoid:
				if absf(a.y - z) < 2.0 and signf(a.x) == sx:
					blocked = true
			if not blocked:
				var r := rng.randf()
				if r < 0.22:
					# Klimageraet an der Fassade (1. OG)
					model(parent, "exterior_aircon_unit", Vector3(wx - sx * 0.2, rng.randf_range(2.6, 3.4), z), yaw, 1.0, 50.0)
				elif r < 0.34:
					model(parent, "power_box_01", Vector3(wx - sx * 0.05, 1.3, z), yaw, 1.0, 35.0)
				elif r < 0.46:
					model(parent, "utility_box_02", Vector3(wx - sx * 0.24, yw, z), yaw, 1.0, 55.0)
				elif r < 0.64:
					for k in rng.randi_range(2, 4):
						model(parent, "trashbag", Vector3(wx - sx * rng.randf_range(0.22, 0.42), yw, z + rng.randf_range(-0.7, 0.7)), rng.randf() * 360.0, rng.randf_range(0.85, 1.15), 40.0)
					if rng.randf() < 0.5:
						model(parent, "cardboard_box_01", Vector3(wx - sx * 0.3, yw, z + 1.0), rng.randf() * 360.0, 1.4, 30.0)
				elif r < 0.74:
					model(parent, "metal_trash_can", Vector3(wx - sx * 0.32, yw + 0.07, z), rng.randf() * 360.0, 1.0, 45.0)
				elif r < 0.8:
					model(parent, "security_light", Vector3(wx - sx * 0.02, 3.2, z), yaw, 1.0, 40.0)
			z -= rng.randf_range(4.0, 9.0)
	# Kriegsschaeden: Glasscherben am Gehweg, Reifen/Felgen, Kabel ueber der Strasse
	var cb := Geo.BoxBatch.new()
	if war:
		for i in int(14 * per):
			var sx2 := -1.0 if rng.randf() < 0.5 else 1.0
			glass_shards(parent, rng, Vector3(sx2 * rng.randf_range(road + 0.8, wall - 0.8), yw, rng.randf_range(zmin, zmax)), rng.randf_range(0.6, 1.4), rng.randf_range(0.8, 2.0), rng.randi_range(40, 90))
		for i in int(6 * per):
			var p := Vector3(rng.randf_range(-road + 0.5, road - 0.5), 0.0, rng.randf_range(zmin, zmax))
			if rng.randf() < 0.5:
				model(parent, "old_tyre", p + Vector3.UP * 0.08, 0.0, 1.0, 45.0).rotation_degrees = Vector3(90.0, rng.randf() * 360.0, 0.0)
			else:
				model(parent, "rusted_wheel_rim_01", p + Vector3.UP * 0.07, 0.0, 1.0, 35.0).rotation_degrees = Vector3(90.0, rng.randf() * 360.0, 0.0)
		var kz := zmax - rng.randf_range(6.0, 14.0)
		while kz > zmin + 4.0:
			var ya := rng.randf_range(6.5, 8.5)
			var yb := rng.randf_range(6.0, 8.5)
			if rng.randf() < 0.3:
				# abgerissenes Kabel haengt von einer Seite herab
				var s3 := -1.0 if rng.randf() < 0.5 else 1.0
				cable(cb, Vector3(s3 * (wall - 0.05), ya, kz), Vector3(s3 * rng.randf_range(2.0, wall - 3.0), 0.6, kz + rng.randf_range(-2.0, 2.0)), 1.2)
			else:
				cable(cb, Vector3(-wall + 0.05, ya, kz), Vector3(wall - 0.05, yb, kz + rng.randf_range(-3.0, 3.0)), rng.randf_range(0.6, 1.6))
			kz -= rng.randf_range(14.0, 26.0)
	else:
		var kz2 := zmax - rng.randf_range(8.0, 16.0)
		while kz2 > zmin + 4.0:
			cable(cb, Vector3(-wall + 0.05, 9.0, kz2), Vector3(wall - 0.05, 9.0, kz2), 0.5, 0.02)
			kz2 -= rng.randf_range(24.0, 36.0)
	cables_node(parent, cb)
	fences_node(parent, fb)
