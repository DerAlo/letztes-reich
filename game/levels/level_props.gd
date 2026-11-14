extends RefCounted
## Requisiten fuer die Kriegsstrasse: Fahrzeuge, Panzerwrack, Betonbarrieren, Sandsaecke,
## Panzersperren, Truemmerhaufen, Strassenlampen, Krater, Feuer und Nebelvolumen.
## Alle Funktionen sind statisch; `covers` sammelt Deckungspositionen (Array[Vector3]).

const Geo = preload("res://game/levels/level_geo.gd")
const FireScene: PackedScene = preload("res://game/vfx/fire.tscn")
const TankWreck = preload("res://game/vehicles/models/tank_wreck_model.gd")
const CarModel = preload("res://game/vehicles/models/car_model.gd")
const WreckModel = preload("res://game/vehicles/models/wreck_model.gd")
const PH = preload("res://game/levels/ph_props.gd")

static func _rot(yaw_deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw_deg))

## Deckungspunkte rund um ein Objekt: seitlich (lokal x) und optional an den Enden (lokal z).
static func _cover_sides(covers: Array, pos: Vector3, yaw_deg: float, half_x: float, half_z: float, margin: float = 1.0, ends: bool = false) -> void:
	var b := _rot(yaw_deg)
	var zs: Array[float] = [0.0]
	if half_z > 2.2:
		zs = [-half_z * 0.5, half_z * 0.5]
	for z in zs:
		covers.append(pos + b * Vector3(half_x + margin, 0, z))
		covers.append(pos + b * Vector3(-(half_x + margin), 0, z))
	if ends:
		covers.append(pos + b * Vector3(0, 0, half_z + margin))
		covers.append(pos + b * Vector3(0, 0, -(half_z + margin)))

static func _paint(color: Color) -> StandardMaterial3D:
	return Geo.mat("rusty_metal_02", color, 0.45, 1.0, 0.0)

static func _dark_glass() -> StandardMaterial3D:
	return Geo.flat(Color(0.03, 0.035, 0.04), 0.15, 0.2)

static func _rubber() -> StandardMaterial3D:
	return Geo.flat(Color(0.03, 0.03, 0.03), 0.95)

# --- Fahrzeuge ----------------------------------------------------------------

## kind: "car", "van", "bus", "truck". burnt = verkohlt (dunkel, ohne Reifen).
static func vehicle(parent: Node3D, pos: Vector3, yaw_deg: float, kind: String, color: Color, burnt: bool, flipped: bool, covers: Array, roll_deg: float = 0.0) -> StaticBody3D:
	var length := 4.4
	var width := 1.8
	var body_h := 0.75
	var cab_len := 2.3
	var cab_h := 0.62
	var cab_off := -0.2
	match kind:
		"van":
			length = 5.2; width = 2.0; body_h = 1.5; cab_len = 0.0; cab_h = 0.0
		"bus":
			length = 11.0; width = 2.5; body_h = 2.7; cab_len = 0.0; cab_h = 0.0
		"truck":
			length = 7.0; width = 2.4; body_h = 2.4; cab_len = 2.0; cab_h = 0.5; cab_off = 2.2
	var tint := Color(0.2, 0.18, 0.165) if burnt else color
	var paint: Material = _paint(tint)
	if burnt:
		# ausgebrannt: verkohltes, rostiges Blech statt Lack
		paint = Geo.mat("rusty_metal_02", Color(0.34, 0.29, 0.26), 0.7, 1.0, 0.35)
	var b := Geo.static_body(pos, yaw_deg)
	var root := Node3D.new()
	b.add_child(root)
	if kind == "car" and not burnt and not flipped:
		# geparktes Auto unter Abdeckplane (Poly Haven "covered_car", CC0), Kollision wie bisher
		var ps: PackedScene = load("res://assets/environment/street/models/covered_car/covered_car.gltf")
		if ps != null:
			var car := ps.instantiate() as Node3D
			var sc := length / 4.38
			car.scale = Vector3(width / 1.78, sc, sc)
			car.position.y = 0.3 * sc
			root.add_child(car)
			root.rotation_degrees.z = roll_deg
			var hh := 0.32 + body_h + cab_h
			Geo.add_box_shape(b, Vector3(0, hh / 2.0, 0), Vector3(width, hh, length))
			parent.add_child(b)
			_cover_sides(covers, pos, yaw_deg, width / 2.0, length / 2.0, 1.0, true)
			return b
	var ride := 0.32
	var total_h := ride + body_h
	if kind == "car":
		total_h += cab_h
	elif kind == "truck":
		total_h = ride + 2.5
	if burnt:
		# ausgebrannt: Loft-Karosserie ohne Scheiben/Reifen auf nackten Felgen, Brandrost/Asche-Shader (WreckModel)
		var seed_v := fposmod(pos.x * 0.37 + pos.z * 0.71, 10.0)
		var mh := WreckModel.build_vehicle(root, kind, color, seed_v)
		root.rotation_degrees.z = roll_deg
		if flipped:
			root.rotation_degrees.z = 180.0 + roll_deg
			root.position.y = mh - 0.03
		Geo.add_box_shape(b, Vector3(0, total_h / 2.0, 0), Vector3(width, total_h, length))
		WreckModel.scorch(b, Vector2(width + 1.8, length + 1.6), fposmod(seed_v * 37.0, 30.0) - 15.0)
		parent.add_child(b)
		_cover_sides(covers, pos, yaw_deg, width / 2.0, length / 2.0, 1.0, true)
		return b
	# Karosserie aus Seitenprofilen mit Radlaeufen, Greenhouse, Saeulen, Raeder/Felgen (CarModel)
	var glass_m: Material = Geo.flat(Color(0.025, 0.022, 0.02), 0.95) if burnt else _dark_glass()
	var rim_m: Material = paint if burnt else Geo.flat(Color(0.5, 0.5, 0.52), 0.4, 0.8)
	CarModel.build(root, kind, paint, glass_m, _rubber(), rim_m, burnt)
	var half_h := total_h / 2.0
	root.rotation_degrees.z = roll_deg
	if flipped:
		root.rotation_degrees.z = 180.0 + roll_deg
		root.position.y = total_h
	Geo.add_box_shape(b, Vector3(0, half_h, 0), Vector3(width, total_h, length))
	parent.add_child(b)
	_cover_sides(covers, pos, yaw_deg, width / 2.0, length / 2.0, 1.0, true)
	return b

# --- Panzer -------------------------------------------------------------------

## Ausgebranntes Panzerwrack (verkohlter Marder 1A3, Turm verdreht, Rohr haengt, Heckklappe offen; Fallback TankModel).
## snow = Schneeauflage (Winterlevels). Kollision und Deckungspunkte wie bisher.
static func tank_wreck(parent: Node3D, pos: Vector3, yaw_deg: float, covers: Array, snow: bool = false) -> StaticBody3D:
	var b := Geo.static_body(pos, yaw_deg)
	var model := Node3D.new()
	model.name = "WreckModel"
	# TankModel: Front = -Z; das alte Wrack hatte die Front bei +Z -> 180 Grad drehen
	model.rotation_degrees = Vector3(0, 180.0, 0)
	b.add_child(model)
	# verkohlter Marder 1A3 (Scout, CC-BY 4.0); Fallback: prozedurales TankModel-Wrack
	if not WreckModel.build_marder(model, snow):
		TankWreck.build(model, snow)
	WreckModel.scorch(b, Vector2(6.5, 9.5), 8.0)
	Geo.add_box_shape(b, Vector3(0, 1.05, 0), Vector3(3.0, 1.2, 6.5))
	Geo.add_box_shape(b, Vector3(1.75, 0.65, 0), Vector3(0.8, 1.3, 7.1))
	Geo.add_box_shape(b, Vector3(-1.75, 0.65, 0), Vector3(0.8, 1.3, 7.1))
	Geo.add_box_shape(b, Vector3(0.1, 2.0, -0.3), Vector3(2.4, 0.9, 3.0), Vector3(3.0, 24.0, -4.0))
	parent.add_child(b)
	_cover_sides(covers, pos, yaw_deg, 2.2, 3.6, 1.0, true)
	return b

# --- Barrieren ----------------------------------------------------------------

static func jersey(parent: Node3D, pos: Vector3, yaw_deg: float, covers: Array) -> void:
	# Poly-Haven "concrete_road_barrier" (1,55 m Segment), auf 2,4 x 1,08 m gebracht; Laenge entlang lokal z
	var b := Geo.static_body(pos, yaw_deg)
	PH.place(b, "concrete_road_barrier", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(1.55, 1.31, 1.25)), Vector3(-0.03, 0.01, 0)))
	Geo.add_box_shape(b, Vector3(0, 0.55, 0), Vector3(0.8, 1.1, 2.4))
	parent.add_child(b)
	_cover_sides(covers, pos, yaw_deg, 0.4, 1.2, 0.9)

static func sandbags(parent: Node3D, pos: Vector3, yaw_deg: float, length: float, rng: RandomNumberGenerator, covers: Array) -> void:
	# Gefuellte Jutesaecke (ph_props.gd, ein MultiMesh je Wall), 4 Lagen, zwei Reihen
	var b := Geo.static_body(pos, yaw_deg)
	PH.sandbag_wall(b, length, 4, rng)
	Geo.add_box_shape(b, Vector3(0, 0.46, 0), Vector3(0.9, 0.92, length))
	parent.add_child(b)
	_cover_sides(covers, pos, yaw_deg, 0.45, length / 2.0, 0.9)

static func hedgehog(parent: Node3D, pos: Vector3, yaw_deg: float, covers: Array) -> void:
	var mat := Geo.mat("rusty_metal_02", Color(0.42, 0.34, 0.28), 0.6, 1.0)
	var b := Geo.static_body(pos, yaw_deg)
	var bb := Geo.batch()
	for r in [Vector3(0, 0, 0), Vector3(0, 0, 90), Vector3(90, 0, 0)]:
		var rv: Vector3 = r
		bb.add(Vector3(0, 0.55, 0), Vector3(0.14, 1.9, 0.14), Basis.from_euler(Vector3(deg_to_rad(rv.x), deg_to_rad(rv.y), deg_to_rad(rv.z))) * Basis(Vector3.RIGHT, deg_to_rad(35)))
	b.add_child(Geo.mesh_node(bb.build(), mat))
	Geo.add_box_shape(b, Vector3(0, 0.55, 0), Vector3(1.1, 1.1, 1.1))
	parent.add_child(b)
	covers.append(pos + Vector3(0, 0, 1.3))
	covers.append(pos + Vector3(0, 0, -1.3))

## Gemauertes Wandstueck (Strassensperre, Gassenende, Ruinenwand).
static func wall(parent: Node3D, pos: Vector3, yaw_deg: float, length: float, height: float, thick: float, rng: RandomNumberGenerator, covers: Array = []) -> void:
	var b := Geo.static_body(pos, yaw_deg)
	var bb := Geo.batch()
	var n := maxi(1, roundi(length / 1.6))
	var seg := length / n
	for i in n:
		var h := height * rng.randf_range(0.55, 1.0)
		bb.add(Vector3(0, h / 2.0, -length / 2.0 + (i + 0.5) * seg), Vector3(thick, h, seg + 0.02))
	b.add_child(Geo.mesh_node(bb.build(), Geo.mat("brick_wall_02", Color(0.7, 0.62, 0.58), 0.3, 1.0)))
	Geo.add_box_shape(b, Vector3(0, height / 2.0, 0), Vector3(thick, height, length))
	parent.add_child(b)
	if not covers.is_empty() or height < 2.0:
		_cover_sides(covers, pos, yaw_deg, thick / 2.0, length / 2.0, 0.9)

# --- Truemmer, Krater -----------------------------------------------------------

static func rubble(parent: Node3D, pos: Vector3, radius: float, height: float, rng: RandomNumberGenerator, collide: bool, covers: Array = []) -> void:
	var conc := Geo.batch()
	var brick := Geo.batch()
	var wood := Geo.batch()
	var b := Geo.static_body(pos)
	var n := int(14.0 + radius * 14.0)
	var big := 0
	for i in n:
		var a := rng.randf() * TAU
		var d := radius * pow(rng.randf(), 0.7)
		var fall := pow(1.0 - d / radius, 1.1)
		var sz := Vector3(rng.randf_range(0.25, 0.9), rng.randf_range(0.15, 0.45), rng.randf_range(0.25, 0.8)) * rng.randf_range(0.7, 1.6)
		var y := height * fall * rng.randf_range(0.25, 1.0) + sz.y * 0.25
		var rot := Basis.from_euler(Vector3(rng.randf_range(-0.7, 0.7), rng.randf() * TAU, rng.randf_range(-0.7, 0.7)))
		var p := Vector3(cos(a) * d, y, sin(a) * d)
		var r := rng.randf()
		if r < 0.5:
			conc.add(p, sz, rot)
		elif r < 0.9:
			brick.add(p, sz * Vector3(0.7, 0.8, 0.7), rot)
		else:
			wood.add(p, Vector3(0.12, 0.12, rng.randf_range(1.2, 2.6)), rot)
		if collide and sz.x > 0.75 and fall > 0.35 and big < 3:
			big += 1
			Geo.add_box_shape(b, p, sz * 0.85, rot.get_euler() * 180.0 / PI)
	if conc.count > 0:
		b.add_child(Geo.mesh_node(conc.build(), Geo.mat("concrete_wall_008", Color(0.5, 0.47, 0.44), 0.7, 1.0)))
	if brick.count > 0:
		b.add_child(Geo.mesh_node(brick.build(), Geo.mat("brick_wall_02", Color(0.6, 0.5, 0.45), 0.7, 1.0)))
	if wood.count > 0:
		b.add_child(Geo.mesh_node(wood.build(), Geo.flat(Color(0.12, 0.09, 0.07), 0.9)))
	if collide:
		Geo.add_box_shape(b, Vector3(0, height * 0.3, 0), Vector3(radius * 1.1, height * 0.6, radius * 1.1))
	parent.add_child(b)
	if not covers.is_empty() or collide:
		covers.append(pos + Vector3(0, 0, radius + 0.8))
		covers.append(pos + Vector3(0, 0, -radius - 0.8))

static func crater(parent: Node3D, pos: Vector3, radius: float, rng: RandomNumberGenerator) -> void:
	var d := Decal.new()
	d.texture_albedo = load("res://assets/vfx/burn_mark.png")
	d.size = Vector3(radius * 2.4, 3.0, radius * 2.4)
	d.position = pos + Vector3(0, 0.5, 0)
	d.rotation.y = rng.randf() * TAU
	d.cull_mask = 1
	d.upper_fade = 0.5
	d.lower_fade = 0.5
	parent.add_child(d)

# --- Lampen, Feuer, Nebel --------------------------------------------------------

## cone: zusaetzlicher Spot nach unten, der im Volumetric Fog einen sichtbaren Lichtkegel zeichnet.
## Berliner Gaslaterne (Poly-Haven "street_lamp_01", 4,6 m). lit = Glaskoerper leuchtet + Licht,
## cone = zusaetzlicher Lichtkegel nach unten, lean_deg = verbogener Mast.
static func lamp(parent: Node3D, pos: Vector3, yaw_deg: float, lit: bool, lean_deg: float = 0.0, cone: bool = false) -> void:
	const SC := 1.2
	const HEAD := 3.33 * SC        # Mitte des Laternenkopfs
	var b := Geo.static_body(pos, yaw_deg)
	var root := Node3D.new()
	root.rotation_degrees.z = lean_deg
	b.add_child(root)
	var m := PH.place(root, "street_lamp_01", Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * SC), Vector3.ZERO))
	if lit:
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh.get_surface_count() > 2:
				# Gluehstrumpf hell, Glasscheiben warm durchscheinend (wie eine brennende Gaslaterne)
				mi.set_surface_override_material(1, _lamp_glass())
				mi.set_surface_override_material(2, _lamp_bulb())
			# eigene Render-Ebene: das Laternenlicht sitzt im Glaskoerper und wuerde das Glas aus 10 cm
			# Abstand ueberstrahlen (weisses Quadrat) -> Laternenlichter beleuchten die Laternen selbst nicht
			mi.layers = LAMP_LAYER
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.74, 0.46)
		l.light_energy = 3.0
		l.omni_range = 14.0
		l.omni_attenuation = 1.2
		l.light_volumetric_fog_energy = 1.5
		l.shadow_enabled = false
		l.position = Vector3(0, HEAD, 0)
		l.light_cull_mask = 0xFFFFF & ~LAMP_LAYER
		root.add_child(l)
		if cone:
			l.light_energy = 1.2
			l.light_volumetric_fog_energy = 0.4
			var sp := SpotLight3D.new()
			sp.light_color = Color(1.0, 0.76, 0.5)
			sp.light_energy = 4.0
			sp.spot_range = 8.0
			sp.spot_angle = 58.0
			sp.spot_angle_attenuation = 0.8
			sp.light_volumetric_fog_energy = 2.0
			sp.shadow_enabled = false
			sp.position = Vector3(0, HEAD - 0.15, 0)
			sp.light_cull_mask = 0xFFFFF & ~LAMP_LAYER
			sp.rotation_degrees = Vector3(-90.0, 0, 0)
			root.add_child(sp)
	Geo.add_box_shape(b, Vector3(0, 2.3, 0), Vector3(0.36, 4.6, 0.36))
	parent.add_child(b)

static var _glow: Dictionary = {}
const LAMP_LAYER := 1 << 13

## Leuchtende Gluehstruempfe / Glas der Gaslaterne (geteilt).
static func _lamp_bulb() -> Material:
	if not _glow.has("bulb"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.86, 0.62)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.78, 0.5)
		m.emission_energy_multiplier = 4.0
		_glow["bulb"] = m
	return _glow["bulb"]

static func _lamp_glass() -> Material:
	if not _glow.has("glass"):
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.82, 0.58, 0.55)
		m.roughness = 0.35
		m.emission_enabled = true
		m.emission = Color(1.0, 0.7, 0.4)
		m.emission_energy_multiplier = 1.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glow["glass"] = m
	return _glow["glass"]

static func fire(parent: Node3D, pos: Vector3, size: float, light: bool = true, smoke_height: float = 1.0, light_energy: float = 6.0, burn_time: float = 0.0) -> Node3D:
	var f: Node3D = FireScene.instantiate()
	f.set("size", size)
	f.set("light_enabled", light)
	f.set("light_energy", light_energy)
	f.set("smoke_height", smoke_height)
	f.set("burn_time", burn_time)
	f.position = pos
	parent.add_child(f)
	return f

static func fog_volume(parent: Node3D, pos: Vector3, size: Vector3, density: float, albedo: Color) -> void:
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fv.size = size
	var fm := FogMaterial.new()
	fm.density = density
	fm.albedo = albedo
	fm.emission = Color(0.0, 0.0, 0.0)
	fv.material = fm
	fv.position = pos
	parent.add_child(fv)
