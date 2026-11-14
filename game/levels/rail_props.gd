extends RefCounted
## Requisiten fuer Level 4 "Letzter Zug" (rail_yard): Gleise, Gueterwagen, Lok, Stellwerk,
## Laderampen, Lagerhallen, Oberleitungsmasten, Flutlichtmasten und Poly-Haven-Modelle.
## Alle Funktionen statisch; `covers` sammelt Deckungspositionen (Array[Vector3]).

const Geo = preload("res://game/levels/level_geo.gd")

const TEX_DIR := "res://assets/environment/rail/textures/"
const MODEL_DIR := "res://assets/environment/rail/models/"
const GAUGE := 1.52            ## russische Breitspur
const RAIL_TOP := 0.36
const AXLE_Y := 0.81
const WHEEL_R := 0.45
const DECK_Y := 1.25

static var _cache: Dictionary = {}

# ------------------------------------------------------------------ Materialien

## PBR-Material aus assets/environment/rail/textures/<dir>. world = false: Objekt-Triplanar
## (fuer bewegliche Teile, damit die Textur beim Wegfliegen nicht "schwimmt").
static func mat(dir: String, tint: Color = Color.WHITE, scale: float = 0.3, rough_mul: float = 1.0, metallic: float = 0.0, world: bool = true) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s|%s" % [dir, tint.to_html(), scale, rough_mul, metallic, world]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX_DIR + dir + "/diffuse.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX_DIR + dir + "/normal.jpg")
	m.roughness_texture = load(TEX_DIR + dir + "/arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = rough_mul
	m.ao_enabled = true
	m.ao_texture = load(TEX_DIR + dir + "/arm.jpg")
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = metallic
	if metallic > 0.0:
		m.metallic_texture = load(TEX_DIR + dir + "/arm.jpg")
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world
	m.uv1_scale = Vector3.ONE * scale
	_cache[key] = m
	return m

## Matter Schotter/Kies: ohne glaenzende Stellen im Gegenlicht der tiefen Sonne (volle Rauheit,
## wenig Spekular, flachere Normalen). Eigene Kopie, damit mat() fuer andere Nutzer unveraendert bleibt.
static func matte(dir: String, tint: Color = Color.WHITE, scale: float = 0.3, world: bool = true) -> StandardMaterial3D:
	var key := "matte|%s|%s|%s|%s" % [dir, tint.to_html(), scale, world]
	if _cache.has(key):
		return _cache[key]
	var m := (mat(dir, tint, scale, 1.0, 0.0, world).duplicate()) as StandardMaterial3D
	m.roughness_texture = null
	m.roughness = 1.0
	m.metallic_specular = 0.12
	m.normal_scale = 0.45
	_cache[key] = m
	return m

static func steel() -> StandardMaterial3D:
	return mat("rust_coarse_01", Color(0.42, 0.36, 0.32), 0.6, 0.95, 0.0, false)

static func dark_steel() -> StandardMaterial3D:
	return mat("rust_coarse_01", Color(0.16, 0.14, 0.13), 0.7, 1.0, 0.0, false)

## Blanke Schienenoberkante: faengt das Abendlicht (Reflexionen).
static func polished() -> StandardMaterial3D:
	if not _cache.has("polished"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.78, 0.74, 0.7)
		m.metallic = 1.0
		m.roughness = 0.22
		_cache["polished"] = m
	return _cache["polished"]

static func glass() -> StandardMaterial3D:
	if not _cache.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.06, 0.07, 0.55)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.metallic = 0.4
		m.roughness = 0.05
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_cache["glass"] = m
	return _cache["glass"]

static func paint(color: Color, world: bool = false) -> StandardMaterial3D:
	return mat("rusty_painted_metal", color, 0.35, 1.0, 0.0, world)

static func corrugated(color: Color, world: bool = false) -> StandardMaterial3D:
	return mat("rusty_corrugated_iron", color, 0.4, 1.0, 0.0, world)

static func add_batch(parent: Node3D, b: Geo.BoxBatch, m: Material, shadows: bool = true) -> MeshInstance3D:
	var mesh := b.build()
	if mesh == null:
		return null
	var mi := Geo.mesh_node(mesh, m, Vector3.ZERO, shadows)
	parent.add_child(mi)
	return mi

## Mesh-Batches mit Materialschluessel (fuer viele Teile in einem Aufruf).
class Kit:
	var batches: Dictionary = {}
	var mats: Dictionary = {}
	func b(key: String, m: Material) -> Geo.BoxBatch:
		if not batches.has(key):
			batches[key] = Geo.batch()
			mats[key] = m
		return batches[key]
	func flush(parent: Node3D, shadows: bool = true) -> void:
		for k: String in batches:
			var mesh: ArrayMesh = (batches[k] as Geo.BoxBatch).build()
			if mesh == null:
				continue
			var mi := Geo.mesh_node(mesh, mats[k], Vector3.ZERO, shadows)
			mi.name = k
			parent.add_child(mi)
		batches.clear()

static func kit() -> Kit:
	return Kit.new()

# ------------------------------------------------------------------ Gleise

## Ein Gleis entlang Z (z0 > z1) bei x. Nur Optik (begehbar, keine Kollision).
static func track(k: Kit, x: float, z0: float, z1: float, rng: RandomNumberGenerator) -> void:
	var len := absf(z0 - z1)
	var cz := (z0 + z1) * 0.5
	var ballast := k.b("ballast", matte("gravel_stones", Color(0.62, 0.58, 0.54), 0.55))
	ballast.add(Vector3(x, 0.06, cz), Vector3(3.6, 0.12, len))
	ballast.add(Vector3(x, 0.0, cz), Vector3(4.4, 0.08, len))
	var sl := k.b("sleepers", mat("damaged_concrete_floor_02", Color(0.55, 0.52, 0.5), 0.9))
	var z := z0 - 0.3
	while z > z1 + 0.3:
		var jit := rng.randf_range(-0.05, 0.05)
		sl.add(Vector3(x + jit, 0.17, z), Vector3(2.7, 0.13, 0.26), Basis(Vector3.UP, rng.randf_range(-0.03, 0.03)))
		z -= 0.72
	var rail := k.b("rails", steel())
	var top := k.b("railtop", polished())
	for s: float in [-0.5, 0.5]:
		var rx := x + s * GAUGE
		rail.add(Vector3(rx, 0.28, cz), Vector3(0.075, 0.15, len))
		rail.add(Vector3(rx, 0.235, cz), Vector3(0.15, 0.03, len))
		top.add(Vector3(rx, RAIL_TOP - 0.006, cz), Vector3(0.068, 0.014, len))

## Prellbock am Gleisende (bei z, Front zeigt nach dir_z).
static func buffer_stop(parent: Node3D, x: float, z: float, dir_z: float, covers: Array) -> void:
	var b := Geo.static_body(Vector3(x, 0, z))
	var k := kit()
	var st := k.b("st", paint(Color(0.35, 0.33, 0.3)))
	var red := k.b("red", paint(Color(0.55, 0.1, 0.06)))
	for s: float in [-0.5, 0.5]:
		st.add(Vector3(s * GAUGE, 0.75, 0), Vector3(0.25, 1.2, 0.3))
		st.add(Vector3(s * GAUGE, 0.6, -dir_z * 0.8), Vector3(0.2, 0.25, 1.9), Basis(Vector3.RIGHT, dir_z * 0.5))
	red.add(Vector3(0, 1.15, dir_z * 0.18), Vector3(2.4, 0.4, 0.22))
	k.flush(b)
	Geo.add_box_shape(b, Vector3(0, 0.7, 0), Vector3(2.4, 1.4, 0.6))
	parent.add_child(b)
	covers.append(Vector3(x, 0, z + dir_z * 1.2))

# ------------------------------------------------------------------ Wagen-Bausteine

static func _bogies(k: Kit, half_len: float) -> void:
	var w := k.b("wheels_dark", dark_steel())
	for bz: float in [-half_len + 2.2, half_len - 2.2]:
		w.add(Vector3(0, 0.95, bz), Vector3(2.5, 0.42, 2.6))      # Drehgestellrahmen
		w.add(Vector3(0, 0.7, bz), Vector3(0.3, 0.3, 2.4))
		for az: float in [-0.9, 0.9]:
			w.add(Vector3(0, AXLE_Y, bz + az), Vector3(GAUGE + 0.35, 0.12, 0.12))   # Achse
	var wheels := k.b("wheels", steel())
	for bz: float in [-half_len + 2.2, half_len - 2.2]:
		for az: float in [-0.9, 0.9]:
			for s: float in [-0.5, 0.5]:
				# Rad als achteckiger Stapel (3 gedrehte Boxen)
				for r in 3:
					wheels.add(Vector3(s * GAUGE, AXLE_Y, bz + az), Vector3(0.13, WHEEL_R * 1.85, WHEEL_R * 0.77), Basis(Vector3.RIGHT, PI / 3.0 * r))

static func _underframe(k: Kit, half_len: float, width: float) -> void:
	var f := k.b("frame", dark_steel())
	f.add(Vector3(0, DECK_Y - 0.12, 0), Vector3(width, 0.24, half_len * 2.0))
	for s: float in [-0.5, 0.5]:
		f.add(Vector3(s * (width - 0.1), DECK_Y - 0.35, 0), Vector3(0.12, 0.3, half_len * 2.0 - 0.4))
	# Puffer + Kupplung
	var bu := k.b("buffers", steel())
	for e: float in [-1.0, 1.0]:
		for s: float in [-0.5, 0.5]:
			bu.add(Vector3(s * 1.75, 1.05, e * (half_len + 0.3)), Vector3(0.36, 0.36, 0.6))
			bu.add(Vector3(s * 1.75, 1.05, e * (half_len + 0.62)), Vector3(0.5, 0.5, 0.06))
		f.add(Vector3(0, 1.05, e * (half_len + 0.1)), Vector3(width, 0.35, 0.2))
		f.add(Vector3(0, 1.0, e * (half_len + 0.45)), Vector3(0.25, 0.22, 0.7))

## Gedeckter Gueterwagen. Gibt die Kollisionsgroesse zurueck (Mitte auf y=size.y/2).
static func boxcar(root: Node3D, rng: RandomNumberGenerator, color: Color, door_open: float = 0.0) -> Vector3:
	var L := 13.8
	var W := 2.95
	var H := 2.9
	var k := kit()
	_bogies(k, L * 0.5)
	_underframe(k, L * 0.5, W)
	var body := k.b("body", corrugated(color))
	var y0 := DECK_Y
	body.add(Vector3(0, y0 + H * 0.5, 0), Vector3(W, H, L))
	# Rippen (vertikal) und Eckpfosten
	var rib := k.b("ribs", paint(color * 0.8))
	var z := -L * 0.5 + 0.6
	while z < L * 0.5 - 0.4:
		for s: float in [-0.5, 0.5]:
			rib.add(Vector3(s * (W + 0.06), y0 + H * 0.5, z), Vector3(0.07, H, 0.12))
		z += 1.15
	for e: float in [-0.5, 0.5]:
		rib.add(Vector3(0, y0 + H * 0.5, e * (L + 0.05)), Vector3(W + 0.1, H, 0.08))
	# Dach (flache Woelbung aus drei Platten)
	var roof := k.b("roof", paint(Color(0.32, 0.3, 0.28)))
	roof.add(Vector3(0, y0 + H + 0.14, 0), Vector3(1.4, 0.08, L + 0.15))
	for s: float in [-1.0, 1.0]:
		roof.add(Vector3(s * 1.0, y0 + H + 0.06, 0), Vector3(0.95, 0.08, L + 0.15), Basis(Vector3.BACK, s * 0.18))
	# Schiebetueren (eine Seite evtl. offen -> dunkler Innenraum)
	var door := k.b("door", corrugated(color * 0.9))
	var dark := k.b("dark", Geo.flat(Color(0.02, 0.018, 0.016), 1.0))
	for s: float in [-1.0, 1.0]:
		var off := door_open if s > 0.0 else 0.0
		if off > 0.1:
			dark.add(Vector3(s * (W * 0.5 + 0.01), y0 + 1.2, 0), Vector3(0.02, 2.3, off))
		door.add(Vector3(s * (W * 0.5 + 0.1), y0 + 1.25, off), Vector3(0.08, 2.45, 2.6))
		rib.add(Vector3(s * (W * 0.5 + 0.16), y0 + 2.55, 0.0), Vector3(0.06, 0.1, 5.4))
	# Kennzeichnung / Schmutzstreifen
	var stripe := k.b("stripe", paint(Color(0.82, 0.78, 0.66)))
	for s: float in [-1.0, 1.0]:
		stripe.add(Vector3(s * (W * 0.5 + 0.08), y0 + 2.2, -L * 0.33), Vector3(0.02, 0.35, 1.6))
		stripe.add(Vector3(s * (W * 0.5 + 0.08), y0 + 1.75, -L * 0.33), Vector3(0.02, 0.18, 1.1))
	k.flush(root)
	return Vector3(W + 0.3, y0 + H + 0.2, L + 1.2)

## Kesselwagen. marked = rote Markierung + Gefahrguttafeln (Munitionszug).
static func tank_wagon(root: Node3D, rng: RandomNumberGenerator, color: Color, marked: bool = false) -> Vector3:
	var L := 12.0
	var W := 2.9
	var k := kit()
	_bogies(k, L * 0.5)
	_underframe(k, L * 0.5, W)
	var r := 1.42
	var cy := DECK_Y + r + 0.05
	var shell := paint(color)
	var cyl := Geo.cylinder_node(r, L - 1.0, shell, Vector3(0, cy, 0), Vector3(90, 0, 0), 20)
	root.add_child(cyl)
	for e: float in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = r
		sm.height = r * 2.0
		sm.radial_segments = 20
		sm.rings = 8
		cap.mesh = sm
		cap.material_override = shell
		cap.scale = Vector3(1.0, 1.0, 0.32)
		cap.position = Vector3(0, cy, e * (L - 1.0) * 0.5)
		root.add_child(cap)
	root.add_child(Geo.cylinder_node(0.45, 0.5, shell, Vector3(0, cy + r + 0.1, 0), Vector3.ZERO, 14))
	var st := k.b("tank_st", dark_steel())
	st.add(Vector3(0, cy + r + 0.38, 0), Vector3(1.4, 0.05, 1.4))
	for s: float in [-0.5, 0.5]:
		st.add(Vector3(s * 1.4, cy + r + 0.75, 0), Vector3(0.04, 0.7, 1.4))   # Gelaender
		st.add(Vector3(s * 0.25 + 1.5, DECK_Y + 1.3, 0.0), Vector3(0.04, 2.8, 0.04))
	for i in 7:
		st.add(Vector3(1.55, DECK_Y + 0.2 + i * 0.4, 0), Vector3(0.04, 0.04, 0.5))
	# Spannbaender
	for bz: float in [-L * 0.3, L * 0.3]:
		var band := Geo.cylinder_node(r + 0.03, 0.12, Geo.flat(Color(0.08, 0.075, 0.07), 0.8), Vector3(0, cy, bz), Vector3(90, 0, 0), 20)
		root.add_child(band)
	if marked:
		var red := Geo.cylinder_node(r + 0.02, 1.1, paint(Color(0.75, 0.06, 0.04)), Vector3(0, cy, 0), Vector3(90, 0, 0), 20)
		root.add_child(red)
		for bz: float in [-L * 0.36, L * 0.36]:
			var wb := Geo.cylinder_node(r + 0.025, 0.35, paint(Color(0.9, 0.88, 0.8)), Vector3(0, cy, bz), Vector3(90, 0, 0), 20)
			root.add_child(wb)
		# orange Gefahrguttafeln (leicht selbstleuchtend, damit sie im Gegenlicht erkennbar sind)
		var plate := Geo.flat(Color(0.95, 0.42, 0.05), 0.6, 0.0, Color(1.0, 0.4, 0.05), 0.6)
		var pb := k.b("plates", plate)
		var black := k.b("plate_txt", Geo.flat(Color(0.02, 0.02, 0.02)))
		for s: float in [-1.0, 1.0]:
			for pz: float in [-2.6, 2.6]:
				pb.add(Vector3(s * (r + 0.05), cy - 0.2, pz), Vector3(0.04, 0.55, 0.85))
				black.add(Vector3(s * (r + 0.075), cy - 0.2, pz), Vector3(0.01, 0.03, 0.85))
				black.add(Vector3(s * (r + 0.075), cy - 0.2, pz), Vector3(0.01, 0.55, 0.03))
	else:
		var tag := k.b("tag", paint(Color(0.85, 0.82, 0.7)))
		for s: float in [-1.0, 1.0]:
			tag.add(Vector3(s * (r + 0.01), cy + 0.2, -2.8), Vector3(0.03, 0.3, 1.6))
	k.flush(root)
	return Vector3(W + 0.2, cy + r + 0.2, L + 1.2)

## Offener Wagen (Hochbord), gefuellt mit Schrott/Kohle.
static func gondola(root: Node3D, rng: RandomNumberGenerator, color: Color) -> Vector3:
	var L := 12.6
	var W := 3.0
	var H := 2.0
	var k := kit()
	_bogies(k, L * 0.5)
	_underframe(k, L * 0.5, W)
	var wall := k.b("wall", paint(color))
	for s: float in [-0.5, 0.5]:
		wall.add(Vector3(s * (W - 0.1), DECK_Y + H * 0.5, 0), Vector3(0.1, H, L))
		wall.add(Vector3(0, DECK_Y + H * 0.5, s * (L - 0.1)), Vector3(W, H, 0.1))
	var rib := k.b("ribs", paint(color * 0.75))
	var z := -L * 0.5 + 0.8
	while z < L * 0.5 - 0.5:
		for s: float in [-0.5, 0.5]:
			rib.add(Vector3(s * (W + 0.04), DECK_Y + H * 0.5, z), Vector3(0.08, H, 0.14))
		z += 1.6
	var fill := k.b("fill", matte("gravel_stones", Color(0.18, 0.16, 0.15), 0.8, false))
	fill.add(Vector3(0, DECK_Y + H - 0.4, 0), Vector3(W - 0.25, 0.6, L - 0.3))
	for i in 5:
		fill.add_ball(Vector3(rng.randf_range(-0.7, 0.7), DECK_Y + H - 0.1, rng.randf_range(-5.0, 5.0)), Vector3(1.6, 0.8, 2.5))
	k.flush(root)
	return Vector3(W + 0.2, DECK_Y + H + 0.1, L + 1.2)

## Flachwagen; cargo: "container", "crates" oder "".
static func flatcar(root: Node3D, rng: RandomNumberGenerator, color: Color, cargo: String) -> Vector3:
	var L := 13.0
	var W := 2.9
	var k := kit()
	_bogies(k, L * 0.5)
	_underframe(k, L * 0.5, W)
	var deck := k.b("deck", mat("rust_coarse_01", Color(0.35, 0.3, 0.25), 0.6, 1.0, 0.0, false))
	deck.add(Vector3(0, DECK_Y + 0.08, 0), Vector3(W, 0.16, L))
	var h := 0.3
	if cargo == "container":
		var cm := mat("container_side", color, 0.25, 1.0, 0.0, false)
		var cb := k.b("container", cm)
		cb.add(Vector3(0, DECK_Y + 0.16 + 1.3, 0), Vector3(2.44, 2.6, 12.0))
		var cr := k.b("cont_ribs", paint(color * 0.7))
		for e: float in [-0.5, 0.5]:
			cr.add(Vector3(0, DECK_Y + 0.16 + 1.3, e * 12.02), Vector3(2.5, 2.62, 0.06))
			for s: float in [-0.5, 0.5]:
				cr.add(Vector3(s * 2.46, DECK_Y + 0.16 + 1.3, e * 11.9), Vector3(0.08, 2.62, 0.18))
		h = 2.8
	elif cargo == "crates":
		var crate := k.b("crates", mat("rust_coarse_01", Color(0.28, 0.33, 0.2), 0.8, 1.0, 0.0, false))
		var tarp := k.b("tarp", Geo.flat(Color(0.2, 0.22, 0.15), 0.95))
		for i in 4:
			var cz := -4.8 + i * 3.2
			crate.add(Vector3(0, DECK_Y + 0.16 + 0.6, cz), Vector3(2.4, 1.2, 2.6))
			if i % 2 == 0:
				tarp.add(Vector3(0, DECK_Y + 0.16 + 1.25, cz), Vector3(2.5, 0.1, 2.7))
				crate.add(Vector3(rng.randf_range(-0.4, 0.4), DECK_Y + 0.16 + 1.7, cz), Vector3(1.4, 0.8, 1.6))
		h = 2.1
	k.flush(root)
	return Vector3(W + 0.2, DECK_Y + 0.2 + h, L + 1.2)

## Diesellok (lange Haube, Fuehrerstand vorne bei -Z).
static func locomotive(root: Node3D, rng: RandomNumberGenerator, lit: bool) -> Vector3:
	var L := 17.0
	var W := 3.1
	var k := kit()
	_bogies(k, L * 0.5)
	_underframe(k, L * 0.5, W)
	var green := paint(Color(0.2, 0.32, 0.22))
	var hood := k.b("hood", green)
	hood.add(Vector3(0, DECK_Y + 1.35, 2.0), Vector3(2.3, 2.7, 12.0))
	hood.add(Vector3(0, DECK_Y + 2.8, 2.0), Vector3(1.9, 0.2, 11.8))
	var cab := k.b("cab", green)
	cab.add(Vector3(0, DECK_Y + 1.7, -5.6), Vector3(W, 3.4, 3.2))
	cab.add(Vector3(0, DECK_Y + 3.5, -5.6), Vector3(W + 0.15, 0.18, 3.5))
	hood.add(Vector3(0, DECK_Y + 0.7, -7.7), Vector3(2.4, 1.4, 1.2))
	var stripe := k.b("stripe", paint(Color(0.85, 0.62, 0.12)))
	for s: float in [-0.5, 0.5]:
		stripe.add(Vector3(s * (W + 0.02), DECK_Y + 0.9, -5.6), Vector3(0.02, 0.2, 3.2))
		stripe.add(Vector3(s * 2.32, DECK_Y + 0.9, 2.0), Vector3(0.02, 0.2, 12.0))
	stripe.add(Vector3(0, DECK_Y + 0.9, -8.31), Vector3(2.4, 0.3, 0.02))
	var grille := k.b("grille", dark_steel())
	for i in 8:
		for s: float in [-0.5, 0.5]:
			grille.add(Vector3(s * 2.31, DECK_Y + 1.9, -2.5 + i * 1.3), Vector3(0.03, 1.0, 0.9))
	grille.add(Vector3(0, DECK_Y + 3.05, 4.5), Vector3(0.6, 0.35, 0.6))   # Auspuff
	var g := k.b("glass", glass())
	g.add(Vector3(0, DECK_Y + 2.6, -7.21), Vector3(2.5, 0.9, 0.05))
	for s: float in [-0.5, 0.5]:
		g.add(Vector3(s * (W + 0.01), DECK_Y + 2.6, -5.6), Vector3(0.05, 0.85, 1.6))
	var rail := k.b("rail", steel())
	for s: float in [-0.5, 0.5]:
		rail.add(Vector3(s * 1.45, DECK_Y + 1.0, 2.0), Vector3(0.04, 0.04, 12.0))
	k.flush(root)
	var lm: Material = Geo.flat(Color(0.1, 0.1, 0.09), 0.3, 0.0, Color(1.0, 0.85, 0.6), 6.0) if lit else Geo.flat(Color(0.1, 0.1, 0.09), 0.3)
	root.add_child(Geo.cylinder_node(0.18, 0.08, lm, Vector3(0, DECK_Y + 3.15, -7.25), Vector3(90, 0, 0), 12))
	return Vector3(W + 0.2, DECK_Y + 3.7, L + 1.2)

## Baut einen Wagen-Typ in root. Gibt die Kollisionsgroesse zurueck.
static func build_wagon(root: Node3D, kind: String, rng: RandomNumberGenerator, color: Color, extra: Variant = null) -> Vector3:
	match kind:
		"boxcar": return boxcar(root, rng, color, float(extra) if extra != null else 0.0)
		"tank": return tank_wagon(root, rng, color, bool(extra) if extra != null else false)
		"gondola": return gondola(root, rng, color)
		"flat": return flatcar(root, rng, color, str(extra) if extra != null else "")
		"loco": return locomotive(root, rng, bool(extra) if extra != null else false)
	return Vector3.ONE

## Statischer Wagen auf einem Gleis (Deckung). yaw 0 oder 180.
static func static_wagon(parent: Node3D, kind: String, pos: Vector3, yaw: float, rng: RandomNumberGenerator, color: Color, covers: Array, extra: Variant = null) -> StaticBody3D:
	var b := Geo.static_body(pos, yaw)
	var root := Node3D.new()
	b.add_child(root)
	var size := build_wagon(root, kind, rng, color, extra)
	Geo.add_box_shape(b, Vector3(0, size.y * 0.5, 0), size)
	parent.add_child(b)
	# Deckung an beiden Laengsseiten und den Enden
	var hl := size.z * 0.5
	for s: float in [-1.0, 1.0]:
		for f: float in [-0.3, 0.3]:
			covers.append(pos + Vector3(s * (size.x * 0.5 + 0.9), 0, f * hl * 2.0))
		covers.append(pos + Vector3(0, 0, s * (hl + 0.9)))
	return b

# ------------------------------------------------------------------ Gebaeude

## Stellwerk: Ziegel-Untergeschoss, verglaste Kanzel oben (begehbar), Aussentreppe.
## pos = Mitte am Boden, Front (Fensterseite) zeigt nach -X (zum Gleisfeld).
static func signal_box(parent: Node3D, pos: Vector3, covers: Array) -> StaticBody3D:
	var b := Geo.static_body(pos)
	var k := kit()
	var brick := k.b("brick", Geo.mat("brick_wall_02", Color(0.85, 0.7, 0.62), 0.45))
	var conc := k.b("conc", mat("damaged_concrete_floor_02", Color(0.7, 0.68, 0.64), 0.4))
	var frame := k.b("frame", paint(Color(0.55, 0.52, 0.45)))
	var roof := k.b("roof", mat("rust_coarse_01", Color(0.3, 0.27, 0.25), 0.5))
	var W := 6.0    # x
	var D := 10.0   # z
	var H0 := 4.2
	# Untergeschoss (massiv)
	brick.add(Vector3(0, H0 * 0.5, 0), Vector3(W, H0, D))
	Geo.add_box_shape(b, Vector3(0, H0 * 0.5, 0), Vector3(W, H0, D))
	# Boden der Kanzel (kragt 0.8 m vor)
	conc.add(Vector3(-0.4, H0 + 0.12, 0), Vector3(W + 0.8, 0.24, D + 0.6))
	Geo.add_box_shape(b, Vector3(-0.4, H0 + 0.12, 0), Vector3(W + 0.8, 0.24, D + 0.6))
	var fy := H0 + 0.24
	var ox := -0.4 - (W + 0.8) * 0.5   # Frontkante
	# Bruestung rundum (1.0 m, Deckung fuer Gegner oben)
	brick.add(Vector3(ox + 0.12, fy + 0.5, 0), Vector3(0.24, 1.0, D + 0.6))
	Geo.add_box_shape(b, Vector3(ox + 0.12, fy + 0.5, 0), Vector3(0.24, 1.0, D + 0.6))
	for s: float in [-0.5, 0.5]:
		brick.add(Vector3(-0.4, fy + 0.5, s * (D + 0.36)), Vector3(W + 0.8, 1.0, 0.24))
		Geo.add_box_shape(b, Vector3(-0.4, fy + 0.5, s * (D + 0.36)), Vector3(W + 0.8, 1.0, 0.24))
	brick.add(Vector3(W * 0.5 - 0.12, fy + 1.45, 0), Vector3(0.24, 2.9, D + 0.6))
	Geo.add_box_shape(b, Vector3(W * 0.5 - 0.12, fy + 1.45, 0), Vector3(0.24, 2.9, D + 0.6))
	# Fensterband: Pfosten + Glas (teilweise zerschossen)
	var g := k.b("glass", glass())
	var n := 6
	for i in n + 1:
		var z := -D * 0.5 - 0.3 + (D + 0.6) * float(i) / n
		frame.add(Vector3(ox + 0.1, fy + 1.9, z), Vector3(0.12, 1.8, 0.12))
		if i < n and i % 3 != 1:
			g.add(Vector3(ox + 0.1, fy + 1.9, z + (D + 0.6) / n * 0.5), Vector3(0.03, 1.75, (D + 0.6) / n - 0.12))
	for s: float in [-0.5, 0.5]:
		for i in 4:
			var x := ox + 0.3 + (W + 0.4) * float(i) / 4.0
			frame.add(Vector3(x, fy + 1.9, s * (D + 0.36)), Vector3(0.12, 1.8, 0.12))
		if s < 0.0:
			g.add(Vector3(-0.8, fy + 1.9, s * (D + 0.36)), Vector3(W - 0.5, 1.75, 0.03))
	frame.add(Vector3(ox + 0.1, fy + 2.85, 0), Vector3(0.14, 0.14, D + 0.6))
	# Dach mit Ueberstand
	roof.add(Vector3(-0.4, fy + 3.05, 0), Vector3(W + 1.8, 0.25, D + 1.6))
	Geo.add_box_shape(b, Vector3(-0.4, fy + 3.05, 0), Vector3(W + 1.8, 0.25, D + 1.6))
	# Schild "Стрелочный пост" (nur Flaeche) + Treppenhaus-Anbau
	frame.add(Vector3(ox - 0.05, fy - 0.6, 0), Vector3(0.05, 0.5, 3.4))
	conc.add(Vector3(W * 0.5 + 1.3, 1.2, D * 0.5 - 2.0), Vector3(2.4, 2.4, 3.6))
	Geo.add_box_shape(b, Vector3(W * 0.5 + 1.3, 1.2, D * 0.5 - 2.0), Vector3(2.4, 2.4, 3.6))
	# Innen: Stelltisch (dunkler Block) als Deckung oben
	var dk := k.b("desk", paint(Color(0.3, 0.35, 0.3)))
	dk.add(Vector3(0.6, fy + 0.45, 0), Vector3(1.2, 0.9, 6.0))
	Geo.add_box_shape(b, Vector3(0.6, fy + 0.45, 0), Vector3(1.2, 0.9, 6.0))
	k.flush(b)
	parent.add_child(b)
	covers.append(pos + Vector3(-W * 0.5 - 1.0, 0, -D * 0.5 + 1.0))
	covers.append(pos + Vector3(-W * 0.5 - 1.0, 0, D * 0.5 - 1.0))
	covers.append(pos + Vector3(0, 0, -D * 0.5 - 1.0))
	return b

## Laderampe (Beton, 1.25 m hoch), entlang Z. Mit Kollision und Kantenschutz.
static func loading_ramp(parent: Node3D, pos: Vector3, size: Vector3, covers: Array) -> void:
	var b := Geo.static_body(pos)
	var k := kit()
	var c := k.b("c", mat("damaged_concrete_floor_02", Color(0.72, 0.7, 0.66), 0.35))
	var e := k.b("e", steel())
	c.add(Vector3(0, size.y * 0.5, 0), size)
	Geo.add_box_shape(b, Vector3(0, size.y * 0.5, 0), size)
	for s: float in [-0.5, 0.5]:
		e.add(Vector3(s * (size.x + 0.02), size.y - 0.08, 0), Vector3(0.06, 0.16, size.z))
	# schraege Auffahrt am Ende (+Z)
	var ang := atan2(size.y, 5.0)
	var rl := sqrt(size.y * size.y + 25.0)
	var rc := Vector3(0, size.y * 0.5 - 0.15, size.z * 0.5 + 2.5)
	c.add(rc, Vector3(size.x * 0.6, 0.3, rl), Basis(Vector3.RIGHT, ang))
	Geo.add_box_shape(b, rc, Vector3(size.x * 0.6, 0.3, rl), Vector3(rad_to_deg(ang), 0, 0))
	k.flush(b)
	parent.add_child(b)
	var z := -size.z * 0.5 + 3.0
	while z < size.z * 0.5:
		covers.append(pos + Vector3(size.x * 0.5 + 0.8, 0, z))
		z += 6.0

## Lagerhalle mit Ziegelsockel, Wellblechwaenden, Satteldach und grossem Tor zur Seite gate_side (+1/-1 in x).
static func warehouse(parent: Node3D, pos: Vector3, size: Vector3, gate_side: float, gates: Array, rng: RandomNumberGenerator) -> StaticBody3D:
	var b := Geo.static_body(pos)
	var k := kit()
	var plinth := k.b("plinth", mat("factory_wall", Color(0.85, 0.78, 0.72), 0.3))
	var wall := k.b("wall", mat("worn_corrugated_iron", Color(0.75, 0.72, 0.68), 0.25))
	var roof := k.b("roof", mat("rusty_corrugated_iron", Color(0.55, 0.5, 0.47), 0.25))
	var frame := k.b("frame", dark_steel())
	var W := size.x
	var D := size.z
	var H := size.y
	var ph := 2.2
	var t := 0.3
	# Waende: hinten, Stirnseiten, Torseite mit Oeffnungen (gates = Array von [z_mitte, breite])
	var back_x := -gate_side * (W * 0.5 - t * 0.5)
	var front_x := gate_side * (W * 0.5 - t * 0.5)
	for wx: float in [back_x]:
		plinth.add(Vector3(wx, ph * 0.5, 0), Vector3(t + 0.05, ph, D))
		wall.add(Vector3(wx, ph + (H - ph) * 0.5, 0), Vector3(t, H - ph, D))
		Geo.add_box_shape(b, Vector3(wx, H * 0.5, 0), Vector3(t, H, D))
	for s: float in [-0.5, 0.5]:
		plinth.add(Vector3(0, ph * 0.5, s * (D - t)), Vector3(W, ph, t + 0.05))
		wall.add(Vector3(0, ph + (H - ph) * 0.5, s * (D - t)), Vector3(W, H - ph, t))
		Geo.add_box_shape(b, Vector3(0, H * 0.5, s * (D - t)), Vector3(W, H, t))
		# Giebel
		for i in 4:
			var gh := (H * 0.22) * (1.0 - float(i) / 4.0)
			wall.add(Vector3(0, H + gh * 0.5, s * (D - t)), Vector3(W * (1.0 - float(i) / 4.0), gh / 4.0 + 0.6, t))
	# Torseite in Segmente
	var zs: Array = [-D * 0.5]
	var sorted := gates.duplicate()
	sorted.sort_custom(func(a: Array, c: Array) -> bool: return float(a[0]) < float(c[0]))
	for gt: Array in sorted:
		zs.append(float(gt[0]) - float(gt[1]) * 0.5)
		zs.append(float(gt[0]) + float(gt[1]) * 0.5)
	zs.append(D * 0.5)
	for i in range(0, zs.size(), 2):
		var z0: float = zs[i]
		var z1: float = zs[i + 1]
		if z1 - z0 < 0.1:
			continue
		var cz := (z0 + z1) * 0.5
		plinth.add(Vector3(front_x, ph * 0.5, cz), Vector3(t + 0.05, ph, z1 - z0))
		wall.add(Vector3(front_x, ph + (H - ph) * 0.5, cz), Vector3(t, H - ph, z1 - z0))
		Geo.add_box_shape(b, Vector3(front_x, H * 0.5, cz), Vector3(t, H, z1 - z0))
	for gt: Array in sorted:
		var gz: float = gt[0]
		var gw: float = gt[1]
		var gh2 := minf(H - 1.5, 6.0)
		wall.add(Vector3(front_x, gh2 + (H - gh2) * 0.5, gz), Vector3(t, H - gh2, gw))
		frame.add(Vector3(front_x + gate_side * 0.2, gh2 + 0.15, gz), Vector3(0.25, 0.3, gw + 0.4))
		for s: float in [-0.5, 0.5]:
			frame.add(Vector3(front_x + gate_side * 0.2, gh2 * 0.5, gz + s * (gw + 0.2)), Vector3(0.25, gh2, 0.25))
		# halb offenes Rolltor
		wall.add(Vector3(front_x + gate_side * 0.05, gh2 - 0.9, gz), Vector3(0.1, 1.8, gw - 0.2))
	# Fensterband: aussen dunkles, leicht spiegelndes Drahtglas; innen milchig vom Abendhimmel hinterleuchtet
	var glass_out := k.b("glass_out", Geo.flat(Color(0.12, 0.13, 0.14), 0.18, 0.35))
	var glass_in := k.b("glass_in", Geo.flat(Color(0.5, 0.52, 0.55), 0.6, 0.0, Color(0.78, 0.8, 0.86), 1.1))
	for wx: float in [back_x, front_x]:
		var z := -D * 0.5 + 3.0
		while z < D * 0.5 - 2.0:
			glass_out.add(Vector3(wx + signf(wx) * 0.17, H - 1.4, z), Vector3(0.02, 1.0, 2.2))
			glass_in.add(Vector3(wx - signf(wx) * 0.17, H - 1.4, z), Vector3(0.02, 1.0, 2.2))
			z += 4.0
	# Satteldach
	var pitch := atan2(H * 0.22, W * 0.5)
	var rw := (W * 0.5 + 0.6) / cos(pitch)
	for s: float in [-1.0, 1.0]:
		var c := Vector3(s * (W * 0.25 + 0.15), H + H * 0.11, 0)
		roof.add(c, Vector3(rw, 0.15, D + 1.0), Basis(Vector3.BACK, -s * pitch))
	Geo.add_box_shape(b, Vector3(0, H + 0.4, 0), Vector3(W, 0.6, D))
	# Lichtband-Oberlichter in beiden Dachflaechen (innen unter der Dachhaut, von aussen verdeckt)
	var sky_in := k.b("skylight", Geo.flat(Color(0.6, 0.62, 0.66), 0.5, 0.0, Color(0.82, 0.85, 0.92), 1.6))
	for s: float in [-1.0, 1.0]:
		var bas := Basis(Vector3.BACK, -s * pitch)
		var c := Vector3(s * (W * 0.25 + 0.15), H + H * 0.11, 0) - bas.y * 0.12
		var zs2 := -D * 0.5 + 4.0
		while zs2 < D * 0.5 - 3.0:
			sky_in.add(c + Vector3(0, 0, zs2 + 1.5), Vector3(rw * 0.4, 0.03, 3.0), bas)
			zs2 += 6.0
	# Innen: Betonboden + Stuetzen
	k.b("floor", mat("damaged_concrete_floor_02", Color(0.5, 0.48, 0.46), 0.3)).add(Vector3(0, 0.02, 0), Vector3(W - 0.6, 0.04, D - 0.6))
	var z2 := -D * 0.5 + 6.0
	while z2 < D * 0.5 - 3.0:
		for s: float in [-0.5, 0.5]:
			frame.add(Vector3(s * (W - 2.0), H * 0.5, z2), Vector3(0.3, H, 0.3))
		frame.add(Vector3(0, H - 0.3, z2), Vector3(W - 1.0, 0.35, 0.25))
		z2 += 6.0
	k.flush(b)
	# Duenne Blechwaende bei tiefer Sonne: doppelseitig Schatten werfen, sonst leckt Licht auf den Hallenboden
	for n: String in ["plinth", "wall", "roof"]:
		var mi := b.get_node_or_null(n) as GeometryInstance3D
		if mi != null:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	_warehouse_lights(b, W, H, D, pitch)
	parent.add_child(b)
	return b

## Hallenlicht: kuehles Tageslicht unter den Oberlichtern (schattenlos, weich) und einige warme
## Hallenstrahler an den Bindern (Notstrom), damit das Innere lesbar, aber nicht taghell ist.
static func _warehouse_lights(b: Node3D, W: float, H: float, D: float, pitch: float) -> void:
	var lamp_m := Geo.flat(Color(0.2, 0.2, 0.19), 0.5, 0.6)
	var bulb_m := Geo.flat(Color(1.0, 0.85, 0.6), 0.4, 0.0, Color(1.0, 0.78, 0.5), 5.0)
	var z := -D * 0.5 + 7.0
	var i := 0
	while z < D * 0.5 - 4.0:
		# Tageslicht unter dem Oberlicht (Streulicht nach unten)
		var day := OmniLight3D.new()
		day.light_color = Color(0.8, 0.85, 0.95)
		day.light_energy = 1.1
		day.light_indirect_energy = 0.6
		day.light_volumetric_fog_energy = 0.15
		day.light_specular = 0.2
		day.omni_range = maxf(W, H) * 1.05
		day.omni_attenuation = 0.8
		day.shadow_enabled = false
		day.position = Vector3(0, H - 0.8, z)
		b.add_child(day)
		# jeder zweite Binder: warmer Hallenstrahler mit Schirm
		if i % 2 == 0:
			var lp := Vector3(0, H - 1.6, z - 1.0)
			var shade := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.12
			cm.bottom_radius = 0.38
			cm.height = 0.32
			shade.mesh = cm
			shade.material_override = lamp_m
			shade.position = lp
			b.add_child(shade)
			var bulb := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.1
			sm.height = 0.14
			bulb.mesh = sm
			bulb.material_override = bulb_m
			bulb.position = lp + Vector3(0, -0.14, 0)
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			b.add_child(bulb)
			var cable := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(0.02, 1.3, 0.02)
			cable.mesh = bx
			cable.material_override = lamp_m
			cable.position = lp + Vector3(0, 0.8, 0)
			b.add_child(cable)
			var sp := SpotLight3D.new()
			sp.light_color = Color(1.0, 0.8, 0.55)
			sp.light_energy = 3.5
			sp.light_indirect_energy = 0.5
			sp.light_volumetric_fog_energy = 0.4
			sp.spot_range = H + 3.0
			sp.spot_angle = 62.0
			sp.spot_attenuation = 0.9
			sp.shadow_enabled = false
			sp.position = lp + Vector3(0, -0.2, 0)
			sp.rotation_degrees = Vector3(-90.0, 0, 0)
			b.add_child(sp)
		z += 6.0
		i += 1

# ------------------------------------------------------------------ Masten und Leitungen

## Oberleitungs-Joch quer ueber mehrere Gleise (x0..x1) bei z, mit Fahrdraehten ueber track_xs.
static func catenary_portal(k: Kit, body: StaticBody3D, x0: float, x1: float, z: float) -> void:
	var m := k.b("cat_mast", steel())
	for x: float in [x0, x1]:
		m.add(Vector3(x, 4.6, z), Vector3(0.32, 9.2, 0.32))
		m.add(Vector3(x, 0.3, z), Vector3(0.7, 0.6, 0.7))
		Geo.add_box_shape(body, Vector3(x, 4.6, z), Vector3(0.4, 9.2, 0.4))
	var w := absf(x1 - x0)
	var cx := (x0 + x1) * 0.5
	m.add(Vector3(cx, 8.9, z), Vector3(w, 0.22, 0.22))
	m.add(Vector3(cx, 8.3, z), Vector3(w, 0.1, 0.1))
	var n := int(w / 1.6)
	for i in n:
		var x := x0 + (float(i) + 0.5) * w / n
		m.add(Vector3(x, 8.6, z), Vector3(0.06, 0.65, 0.06), Basis(Vector3.BACK, 0.6 if i % 2 == 0 else -0.6))

static func catenary_wires(k: Kit, track_xs: Array, z0: float, z1: float) -> void:
	var w := k.b("cat_wire", Geo.flat(Color(0.12, 0.1, 0.09), 0.4, 0.6))
	var len := absf(z0 - z1)
	var cz := (z0 + z1) * 0.5
	for x: float in track_xs:
		w.add(Vector3(x, 6.4, cz), Vector3(0.025, 0.025, len))
		w.add(Vector3(x, 7.7, cz), Vector3(0.03, 0.03, len))

## Flutlichtmast (Gittermast, 22 m) mit Scheinwerferkranz.
static func flood_mast(k: Kit, body: StaticBody3D, pos: Vector3, h: float = 22.0) -> void:
	var m := k.b("flood", steel())
	var s := 0.55
	for c: Vector2 in [Vector2(-s, -s), Vector2(s, -s), Vector2(-s, s), Vector2(s, s)]:
		m.add(pos + Vector3(c.x * 0.6, h * 0.5, c.y * 0.6), Vector3(0.12, h, 0.12))
	var y := 1.5
	while y < h - 1.0:
		m.add(pos + Vector3(0, y, 0), Vector3(s * 1.3, 0.06, 0.06), Basis(Vector3.FORWARD, 0.7))
		m.add(pos + Vector3(0, y + 0.6, 0), Vector3(0.06, 0.06, s * 1.3), Basis(Vector3.RIGHT, 0.7))
		y += 1.4
	m.add(pos + Vector3(0, h + 0.1, 0), Vector3(3.4, 0.15, 1.2))
	var lamp := k.b("flood_lamp", Geo.flat(Color(0.2, 0.2, 0.19), 0.4))
	for i in 5:
		lamp.add(pos + Vector3(-1.4 + i * 0.7, h + 0.6, 0.2), Vector3(0.55, 0.5, 0.3))
	Geo.add_box_shape(body, pos + Vector3(0, h * 0.5, 0), Vector3(0.9, h, 0.9))

# ------------------------------------------------------------------ Modelle (Poly Haven)

## Instanziert ein glTF-Modell aus assets/environment/rail/models/<name>/. Null, wenn nicht importiert.
static func model(name: String) -> Node3D:
	var path := MODEL_DIR + name + "/" + name + ".gltf"
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	return ps.instantiate() as Node3D

## Erstes Mesh eines Modells (fuer MultiMesh-Streuung).
static func model_mesh(name: String) -> Mesh:
	var key := "mesh|" + name
	if _cache.has(key):
		return _cache[key]
	var n := model(name)
	var mesh: Mesh = null
	if n != null:
		var mi := _find_mesh(n)
		if mi != null:
			mesh = mi.mesh
		n.free()
	_cache[key] = mesh
	return mesh

static func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null

## Modell platzieren; collide_size > 0: Box-Kollision (Mitte auf halber Hoehe).
static func place(parent: Node3D, name: String, pos: Vector3, yaw_deg: float, scale: float = 1.0, collide_size: Vector3 = Vector3.ZERO, covers: Array = []) -> Node3D:
	var n := model(name)
	if n == null:
		return null
	var root: Node3D = n
	if collide_size != Vector3.ZERO:
		var b := Geo.static_body(pos, yaw_deg)
		b.add_child(n)
		n.scale = Vector3.ONE * scale
		Geo.add_box_shape(b, Vector3(0, collide_size.y * 0.5, 0), collide_size)
		parent.add_child(b)
		root = b
		if collide_size.y >= 0.9:
			covers.append(pos + Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3(0, 0, collide_size.z * 0.5 + 0.9))
	else:
		n.position = pos
		n.rotation_degrees.y = yaw_deg
		n.scale = Vector3.ONE * scale
		parent.add_child(n)
	return root

## Viele Instanzen eines Modells als MultiMesh (Gras, Bueschel). xforms: Array[Transform3D].
static func scatter(parent: Node3D, name: String, xforms: Array, shadows: bool = false) -> MultiMeshInstance3D:
	var mesh := model_mesh(name)
	if mesh == null or xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 120.0
	parent.add_child(mmi)
	return mmi

## Kistenstapel aus Poly-Haven-Kisten (mit einer Box-Kollision).
static func crate_stack(parent: Node3D, pos: Vector3, yaw_deg: float, rng: RandomNumberGenerator, covers: Array) -> void:
	var b := Geo.static_body(pos, yaw_deg)
	var names: Array = ["wooden_military_crate", "old_military_crate", "ammo_box"]
	var placed := 0
	for i in 3:
		var n := model(names[rng.randi() % 2])
		if n == null:
			continue
		n.position = Vector3(-0.55 + i * 0.55 + rng.randf_range(-0.05, 0.05), 0, rng.randf_range(-0.1, 0.1))
		n.rotation_degrees.y = rng.randf_range(-12, 12) + (90.0 if i == 1 else 0.0)
		b.add_child(n)
		placed += 1
	var top := model("ammo_box")
	if top != null:
		top.position = Vector3(rng.randf_range(-0.3, 0.3), 0.62, 0)
		top.rotation_degrees.y = rng.randf_range(0, 180)
		b.add_child(top)
	if placed == 0:
		b.add_child(Geo.box_mesh_node(Vector3(1.6, 1.0, 0.8), mat("rust_coarse_01", Color(0.3, 0.33, 0.2), 0.8), Vector3(0, 0.5, 0)))
	Geo.add_box_shape(b, Vector3(0, 0.5, 0), Vector3(1.7, 1.0, 0.9))
	parent.add_child(b)
	# Deckungspunkt immer auf der Spielerseite (+Z), unabhaengig von der Drehung
	covers.append(pos + Vector3(0, 0, 1.3))

## Betonbarriere-Reihe (Poly-Haven-Modell; Ersatz: Box).
static func barrier_row(parent: Node3D, a: Vector3, b2: Vector3, covers: Array) -> void:
	var d := b2 - a
	var n := maxi(1, int(d.length() / 1.6))
	var yaw := rad_to_deg(atan2(d.x, d.z)) + 90.0
	for i in n:
		var p := a + d * ((float(i) + 0.5) / n)
		var b := Geo.static_body(p, yaw)
		var m := model("concrete_road_barrier")
		if m != null:
			b.add_child(m)
		else:
			b.add_child(Geo.box_mesh_node(Vector3(1.6, 0.8, 0.5), mat("damaged_concrete_floor_02", Color(0.8, 0.78, 0.74), 0.5), Vector3(0, 0.4, 0)))
		Geo.add_box_shape(b, Vector3(0, 0.45, 0), Vector3(1.6, 0.9, 0.6))
		parent.add_child(b)
	var side := Vector3(-d.z, 0, d.x).normalized()
	covers.append((a + b2) * 0.5 + side * 0.9)
	covers.append((a + b2) * 0.5 - side * 0.9)

## Sandsack-Stellung (Bogen), mit Kollision.
static func sandbag_arc(parent: Node3D, center: Vector3, radius: float, from_deg: float, to_deg: float, rng: RandomNumberGenerator, covers: Array) -> void:
	var b := Geo.static_body(center)
	var batch := Geo.batch()
	var steps := int(absf(to_deg - from_deg) / 360.0 * TAU * radius / 0.62)
	for layer in 3:
		for i in steps:
			var a := deg_to_rad(lerpf(from_deg, to_deg, (float(i) + 0.5 * (layer % 2)) / steps))
			var p := Vector3(sin(a) * radius, 0.16 + layer * 0.27, cos(a) * radius)
			batch.add_ball(p, Vector3(0.64, 0.3, 0.38), Basis(Vector3.UP, a + PI * 0.5 + rng.randf_range(-0.1, 0.1)))
	var m := Geo.flat(Color(0.42, 0.37, 0.27), 0.95)
	add_batch(b, batch, m)
	var n := maxi(1, steps / 3)
	for i in n:
		var a := deg_to_rad(lerpf(from_deg, to_deg, (float(i) + 0.5) / n))
		var p := Vector3(sin(a) * radius, 0.45, cos(a) * radius)
		Geo.add_box_shape(b, p, Vector3(0.7, 0.9, absf(to_deg - from_deg) / 360.0 * TAU * radius / n + 0.2), Vector3(0, rad_to_deg(a) + 90.0, 0))
	parent.add_child(b)
	var mid := deg_to_rad((from_deg + to_deg) * 0.5)
	covers.append(center + Vector3(sin(mid), 0, cos(mid)) * (radius - 0.8))
