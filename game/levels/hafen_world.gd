extends RefCounted
## Mission "Kräne": statischer Aufbau des Ueberseehafens (frei gestaltet, angelehnt an einen Ostseehafen).
## Koordinaten: -z = Norden (Fahrtrichtung). Wasserspiegel y = -2, Land-Oberkante y = 0.
##   Containerterminal (Teil A): Hauptgasse x -4..8 von z 50 bis -300, Quergassen z -100/-170/-235,
##   Portalkran (Kerners Stellung) quer ueber der Gasse bei z 61, Laufsteg y 30.
##   Hafenbecken x 41..140 (Teil B), Hubbruecke z -620, Muendung noerdlich z -930, Molen, Frachter "Aurelia".

const Geo = preload("res://game/levels/level_geo.gd")
const PH = preload("res://game/levels/ph_props.gd")
const VF := preload("res://game/vehicles/vehicle_fx.gd")
const RP = preload("res://game/levels/river_props.gd")
const Models := preload("res://game/levels/hafen_models.gd")

const WATER_Y := -2.0
const CRANE_Z := 61.0
const CRANE_Y := 30.0
const KERNER_SPOT := Vector3(2.0, 30.05, 59.6)
const LENA_START := Vector3(2.0, 0.0, -20.0)
const HUT := Vector3(12.0, 0.0, -98.0)
const MARKSMAN := Vector3(-5.0, 16.0, -182.0)   ## ~242 m vom Kran, Lichtmast links der Gasse hinter den Betonsperren
const BERTH7 := Vector3(46.0, -2.0, -236.0)
const BRIDGE_Z := -620.0
const BRIDGE_DECK_Y := 18.0
const FREIGHTER := Vector3(600.0, -2.0, -1080.0)
const FREIGHTER_BOARD := Vector3(557.0, -2.0, -1065.0)
## Frachter-Modell (freighter_aurelia.json: draft 6): Hauptdeck 8,7 m ueber Wasser, Schanzkleid 10,2 m,
## Rumpf-Halbbreite an der Gangway (lokal x -43..-31) ~11 m.
const FREIGHTER_DECK := 8.7
const FREIGHTER_DRAFT := 6.0
const LANES: Array[float] = [-100.0, -170.0, -235.0]
const BARRIERS: Array[Vector3] = [Vector3(-1.0, 0, -158.0), Vector3(5.0, 0, -162.0), Vector3(1.0, 0, -168.0),
	Vector3(5.6, 0, -112.0), Vector3(-2.0, 0, -205.0)]

const C_LEN := 12.2
const C_H := 2.6
const C_W := 2.44
const C_PITCH := 2.84

static var _corr_tex: Texture2D = null
static var _cont_mesh: Mesh = null
static var _cont_xf := Transform3D.IDENTITY
static var _cont_m: StandardMaterial3D = null
## 20-ft-Container-Modell ("Classic Shipping Container", Sebastian Webster, CC-BY): Masse nach dem Bake
## (assets/models/hafen/container, Tueren an +X) -> Ziel 6,0 x 2,56 x 2,40 m, zwei je 40-ft-Stellplatz.
const CONT20_SIZE := Vector3(5.288, 2.34, 2.24)
const CONT20_WANT := Vector3(6.0, 2.56, 2.40)
const CONT_CHUNK := 24.0

## Baut alles; gibt Knoten zurueck, die das Level braucht.
static func build(lv: Node3D, world: Node3D, wind: Node, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	_build_water(lv)
	_build_land(world)
	_build_yard(world, rng)
	_build_crane(world, wind)
	_build_masts(world, wind)
	_build_quay(world)
	_build_bridge(world)
	_build_port_cranes(world)
	_build_mouth(world)
	out["freighter"] = _build_freighter(lv)
	_build_skyline(lv, rng)
	_build_high_masts(world)
	return out

# ------------------------------------------------------------------ Bau-Helfer

## Balken von a nach b (Querschnitt w x d) in einen Box-Batch.
static func _strut(bb: Geo.BoxBatch, a: Vector3, b: Vector3, w: float, d: float = -1.0) -> void:
	var dv := b - a
	var l := dv.length()
	if l < 0.01:
		return
	var y := dv / l
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y)
	bb.add((a + b) * 0.5, Vector3(w, l, d if d > 0.0 else w), Basis(x, y, z))

## Viele Kopien eines Meshes (Flaeche 0) zu einem ArrayMesh zusammenfassen.
static func _mesh_batch(src: Mesh, xfs: Array) -> ArrayMesh:
	if xfs.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for xf: Transform3D in xfs:
		st.append_from(src, 0, xf)
	return st.commit()

static func _cyl_mesh(r_top: float, r_bot: float, h: float, segs: int = 12) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	return cm

# ------------------------------------------------------------------ Wasser

const WATER_SHADER := """
shader_type spatial;
uniform vec4 deep : source_color = vec4(0.02, 0.035, 0.045, 1.0);
uniform vec4 crest : source_color = vec4(0.06, 0.08, 0.09, 1.0);
uniform sampler2D n1 : hint_normal;
uniform sampler2D n2 : hint_normal;
uniform float amp = 0.17;
varying vec3 wpos;
varying float hgt;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float a1 = w.x * 0.21 + t * 1.3;
	float a2 = w.z * 0.17 - t * 1.1;
	float a3 = (w.x + w.z) * 0.43 + t * 2.1;
	float h = sin(a1) * 0.5 + sin(a2) * 0.35 + sin(a3) * 0.15;
	VERTEX.y += h * amp;
	float dx = cos(a1) * 0.5 * 0.21 + cos(a3) * 0.15 * 0.43;
	float dz = cos(a2) * 0.35 * 0.17 + cos(a3) * 0.15 * 0.43;
	NORMAL = normalize(vec3(-dx * amp, 1.0, -dz * amp));
	wpos = w;
	hgt = h;
}
void fragment() {
	vec2 uv = wpos.xz;
	vec3 a = texture(n1, uv * 0.045 + vec2(TIME * 0.018, TIME * 0.011)).rgb;
	vec3 b = texture(n2, uv * 0.13 - vec2(TIME * 0.015, -TIME * 0.022)).rgb;
	NORMAL_MAP = mix(a, b, 0.5);
	// Feine Normalen + sehr glatte Oberflaeche gaben unter Scheinwerfern grelle Einzel-Glitzerpunkte
	// ("Konfetti"): Normal-Detail flacher, Rauheit hoeher und mit der Entfernung steigend (gegen Aliasing),
	// Spekular auf Wasser-F0 (~0.02) -> weiche, breitere nasse Lichtbahnen statt Funkeln.
	float dist = length(VERTEX);
	NORMAL_MAP_DEPTH = mix(0.32, 0.16, smoothstep(15.0, 140.0, dist));
	ALBEDO = mix(deep.rgb, crest.rgb, clamp(hgt * 0.5 + 0.5, 0.0, 1.0) * 0.6);
	ROUGHNESS = mix(0.24, 0.32, smoothstep(10.0, 160.0, dist));
	METALLIC = 0.0;
	SPECULAR = 0.3;
}
"""

static func _noise_normal(seed: int, freq: float) -> NoiseTexture2D:
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.seed = seed
	fn.frequency = freq
	fn.fractal_octaves = 3
	nt.noise = fn
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.as_normal_map = true
	nt.bump_strength = 6.0
	return nt

static func _build_water(lv: Node3D) -> void:
	var sh := Shader.new()
	sh.code = WATER_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("n1", _noise_normal(11, 0.02))
	m.set_shader_parameter("n2", _noise_normal(23, 0.05))
	var pm := PlaneMesh.new()
	pm.size = Vector2(2600, 2600)
	pm.subdivide_width = 260
	pm.subdivide_depth = 260
	var mi := Geo.mesh_node(pm, m, Vector3(250.0, WATER_Y, -500.0), false)
	mi.name = "Water"
	lv.add_child(mi)
	# Kollision: Oberkante = Wasserspiegel (Einschlaege -> Fontaenen, Absturz-Ziel fuer Hubschrauber)
	var b := Geo.static_body(Vector3(250.0, WATER_Y - 5.0, -500.0))
	b.name = "WaterBody"
	b.set_meta("surface", "water")
	Geo.add_box_shape(b, Vector3.ZERO, Vector3(2600, 10, 2600))
	lv.add_child(b)

# ------------------------------------------------------------------ Land

static func _slab(world: Node3D, x0: float, x1: float, z0: float, z1: float, m: Material) -> void:
	var size := Vector3(x1 - x0, 8.0, z1 - z0)
	var c := Vector3((x0 + x1) * 0.5, -4.0, (z0 + z1) * 0.5)
	var b := Geo.solid_box(world, c, size, m)
	b.set_meta("surface", "concrete")

## Nasser Asphalt (Poly Haven asphalt_02 im Nass-Shader der Flusskarte): Pfuetzen und glaenzende Flaechen,
## in denen sich Mast- und Kranlichter spiegeln.
static func _wet_asphalt() -> Material:
	var m := (RP.wet("road_damaged", Color(0.5, 0.5, 0.53), 0.12, {"puddles": 0.38, "wetness": 0.85, "puddle_scale": 0.05, "base_roughness": 0.85}) as ShaderMaterial).duplicate() as ShaderMaterial
	var d := "res://assets/textures/asphalt_02/"
	if ResourceLoader.exists(d + "diffuse.jpg"):
		m.set_shader_parameter("base_albedo", load(d + "diffuse.jpg"))
		m.set_shader_parameter("base_normal", load(d + "normal.jpg"))
		m.set_shader_parameter("base_arm", load(d + "arm.jpg"))
	return m

static func _build_land(world: Node3D) -> void:
	var asphalt := _wet_asphalt()
	var conc := Geo.mat("concrete_wall_008", Color(0.5, 0.5, 0.52), 0.15)
	# Terminalflaeche (west), feiner unterteilt, damit das Navmesh-Backen schlank bleibt
	_slab(world, -60.0, 41.0, -320.0, 120.0, asphalt)
	_slab(world, -300.0, -60.0, -320.0, 120.0, asphalt)
	_slab(world, -300.0, 41.0, -1150.0, -320.0, conc)
	# Ostufer mit Lagerhallen
	_slab(world, 140.0, 420.0, -930.0, 120.0, conc)
	# Beckenende im Sueden
	_slab(world, 41.0, 140.0, 80.0, 120.0, conc)
	_build_quay_walls(world)
	var z := 0.0
	# Fahrbahnmarkierung in der Hauptgasse
	var paint := Geo.flat(Color(0.75, 0.72, 0.6), 0.6)
	var mb := Geo.batch()
	z = 45.0
	while z > -300.0:
		mb.add(Vector3(2.0, 0.012, z), Vector3(0.18, 0.02, 3.0))
		z -= 7.0
	world.add_child(Geo.mesh_node(mb.build(), paint, Vector3.ZERO, false))

## Kaimauern: Betonwand mit Algen-/Wasserlinie, heller Kantenbalken mit gelber Kantenmarkierung,
## gusseiserne Poller (Pilzform), Gummifender und Steigleitern.
static func _build_quay_walls(world: Node3D) -> void:
	var wall := Geo.mat("concrete_wall_008", Color(0.36, 0.36, 0.37), 0.25)
	var cope := Geo.mat("concrete_wall_008", Color(0.62, 0.62, 0.6), 0.3)
	var algae := Geo.flat(Color(0.05, 0.07, 0.05), 0.35)
	var paint := Geo.flat(Color(0.85, 0.66, 0.08), 0.55)
	# [x Wandmitte, Richtung zum Wasser, z Mitte, Laenge]
	var walls: Array = [[41.4, 1.0, -515.0, 1270.0], [139.6, -1.0, -405.0, 1050.0]]
	var wb := Geo.batch()
	var cb := Geo.batch()
	var ab := Geo.batch()
	var mb := Geo.batch()
	for w: Array in walls:
		var x: float = w[0]
		var sd: float = w[1]
		wb.add(Vector3(x, -1.2, w[2]), Vector3(0.8, 2.2, w[3]))
		cb.add(Vector3(x + sd * 0.05, -0.05, w[2]), Vector3(0.95, 0.3, w[3]))
		ab.add(Vector3(x + sd * 0.41, -1.75, w[2]), Vector3(0.03, 0.55, w[3]))
		mb.add(Vector3(x - sd * 0.75, 0.006, w[2]), Vector3(0.15, 0.012, w[3]))
	world.add_child(Geo.mesh_node(wb.build(), wall, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(cb.build(), cope, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(ab.build(), algae, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(mb.build(), paint, Vector3.ZERO, false))
	# Poller (Schaft + Kopf) und Fender dazwischen
	var pol := Geo.flat(Color(0.72, 0.56, 0.1), 0.55, 0.3)
	var rubber := Geo.flat(Color(0.035, 0.035, 0.035), 0.8)
	var steel := Geo.flat(Color(0.2, 0.2, 0.21), 0.6, 0.7)
	var shaft := _cyl_mesh(0.17, 0.21, 0.5, 14)
	var head := _cyl_mesh(0.27, 0.24, 0.12, 14)
	var fender := _cyl_mesh(0.42, 0.42, 1.9, 14)
	var sx: Array = []
	var hx: Array = []
	var fx: Array = []
	var lb := Geo.batch()
	for w: Array in walls:
		var x: float = w[0]
		var sd: float = w[1]
		var z0: float = float(w[2]) + float(w[3]) * 0.5 - 6.0
		var z1: float = float(w[2]) - float(w[3]) * 0.5 + 6.0
		var px := x - sd * 1.0
		var z := z0
		var i := 0
		while z > z1:
			sx.append(Transform3D(Basis.IDENTITY, Vector3(px, 0.25, z)))
			hx.append(Transform3D(Basis.IDENTITY, Vector3(px, 0.56, z)))
			fx.append(Transform3D(Basis.IDENTITY, Vector3(x + sd * 0.85, -1.05, z - 9.0)))
			if i % 4 == 2:
				# Steigleiter in der Wand
				var lx := x + sd * 0.44
				for dz in [-0.22, 0.22]:
					lb.add(Vector3(lx, -1.05, z - 4.5 + dz), Vector3(0.05, 2.3, 0.05))
				var y := -2.0
				while y < 0.0:
					lb.add(Vector3(lx, y, z - 4.5), Vector3(0.04, 0.035, 0.44))
					y += 0.3
			z -= 18.0
			i += 1
	world.add_child(Geo.mesh_node(_mesh_batch(shaft, sx), pol, Vector3.ZERO))
	world.add_child(Geo.mesh_node(_mesh_batch(head, hx), pol, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(_mesh_batch(fender, fx), rubber, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(lb.build(), steel, Vector3.ZERO, false))
	# Kranschiene der Containerbruecken (landseitig) im Kai
	var rail := Geo.flat(Color(0.3, 0.29, 0.28), 0.45, 0.8)
	var rb := Geo.batch()
	rb.add(Vector3(37.0, 0.04, -125.0), Vector3(0.14, 0.08, 350.0))
	rb.add(Vector3(37.0, 0.005, -125.0), Vector3(0.7, 0.01, 350.0))
	world.add_child(Geo.mesh_node(rb.build(), rail, Vector3.ZERO, false))

# ------------------------------------------------------------------ Containerlager

static func _corrugation() -> Texture2D:
	if _corr_tex != null:
		return _corr_tex
	var img := Image.create(64, 4, false, Image.FORMAT_RGB8)
	for x in 64:
		var s := sin(float(x) / 64.0 * TAU * 8.0)
		var nx := clampf(0.5 + s * 0.42, 0.0, 1.0)
		for y in 4:
			img.set_pixel(x, y, Color(nx, 0.5, 1.0))
	_corr_tex = ImageTexture.create_from_image(img)
	return _corr_tex

## Laedt das 20-ft-Container-Modell (Mesh + Material mit Instanzfarbe); false = Platzhalter-Boxen bauen.
static func _container_model() -> bool:
	if _cont_mesh != null:
		return true
	var p := Models.path_for("container")
	if p == "":
		return false
	var n := (load(p) as PackedScene).instantiate() as Node3D
	var mi := n.find_children("*", "MeshInstance3D", true, false)
	if mi.is_empty():
		n.free()
		return false
	var m := mi[0] as MeshInstance3D
	_cont_mesh = m.mesh
	_cont_xf = Models._rel(n, m)
	n.free()
	var d := "res://assets/models/hafen/container/textures/"
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(d + "BODY_tint.png")
	mat.normal_enabled = true
	mat.normal_texture = load(d + "BODY_normal.png")
	mat.roughness_texture = load(d + "BODY_metallicRoughness.png")
	mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	mat.roughness = 1.0
	mat.metallic = 0.25
	mat.metallic_specular = 0.45
	_cont_m = mat
	return true

static func _container_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.62
	m.metallic = 0.35
	m.normal_enabled = true
	m.normal_texture = _corrugation()
	m.normal_scale = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.36, 0.36, 0.36)
	return m

## Bloecke: west x -60..-6 (4 Container je Reihe), ost x 10..36 (2 je Reihe); Gassen frei.
static func _build_yard(world: Node3D, rng: RandomNumberGenerator) -> void:
	var cols: Array[Color] = [Color(0.42, 0.12, 0.08), Color(0.1, 0.2, 0.36), Color(0.12, 0.28, 0.16),
		Color(0.42, 0.42, 0.4), Color(0.55, 0.26, 0.06), Color(0.62, 0.6, 0.55), Color(0.3, 0.17, 0.1)]
	var batches: Array = []
	for c in cols:
		batches.append(Geo.batch())
	var detail := Geo.batch()      # Tuerverschluesse, Eckbeschlaege (dunkler Stahl)
	var shadow := Geo.batch()      # Modell-Container: Schattenwurf ueber einfache Stapelboxen (billiger)
	# Echtes Container-Modell: je 40-ft-Stellplatz zwei 20-ft-Container als MultiMesh-Instanzen (Farbe je
	# Instanz), gruppiert in Bloecke von CONT_CHUNK m, damit die Auto-LOD je Block greift. Kollision bleibt Box.
	var use_model := _container_model()
	var chunks := {}          # Schluessel -> Array[[Transform3D, Color]]
	var crng := RandomNumberGenerator.new()
	crng.seed = 7731
	var segs: Array = []      # [z_start (sued), z_end (nord)]
	var edges: Array[float] = [44.0]
	for lz in LANES:
		edges.append(lz + 7.0)
		edges.append(lz - 7.0)
	edges.append(-300.0)
	var i := 0
	while i + 1 < edges.size():
		segs.append([edges[i], edges[i + 1]])
		i += 2
	for seg: Array in segs:
		for side in [0, 1]:
			var x0: float = -60.0 if side == 0 else 10.0
			var per: int = 4 if side == 0 else 2
			var maxh: int = 4 if side == 0 else 3
			var body := Geo.static_body()
			body.name = "Stack"
			body.set_meta("surface", "metal")
			world.add_child(body)
			var z: float = float(seg[0]) - C_W * 0.5 - 0.3
			while z - C_W * 0.5 > float(seg[1]):
				for k in per:
					var cx := x0 + C_LEN * 0.5 + k * (C_LEN + 0.2)
					# niedrige Stapel an der Gasse (Sicht), hoehere aussen
					var near_aisle: bool = (side == 0 and k == per - 1) or (side == 1 and k == 0)
					var hmax := maxh if not near_aisle else maxi(maxh - 1, 1)
					var h := rng.randi_range(1, hmax)
					for lvl in h:
						var ci := rng.randi_range(0, cols.size() - 1)
						var cb: Geo.BoxBatch = batches[ci]
						var cy := C_H * 0.5 + lvl * C_H
						if use_model:
							var key := "%d_%d_%d" % [side, int(seg[0]), int(floorf(z / CONT_CHUNK))]
							if not chunks.has(key):
								chunks[key] = []
							for half in [-1.0, 1.0]:
								var col: Color = cols[ci] if half < 0.0 or crng.randf() < 0.45 else cols[crng.randi_range(0, cols.size() - 1)]
								var v := crng.randf_range(0.85, 1.12)
								col = Color(col.r * v, col.g * v, col.b * v)
								var b := Basis.IDENTITY.scaled(CONT20_WANT / CONT20_SIZE)
								if half < 0.0:
									b = Basis(Vector3.UP, PI) * b
								(chunks[key] as Array).append([Transform3D(b, Vector3(cx + half * (C_LEN * 0.25 + 0.05), cy - 0.02, z)) * _cont_xf, col])
							continue
						cb.add(Vector3(cx, cy, z), Vector3(C_LEN, C_H - 0.04, C_W))
						# Rahmen: Eckpfosten und Stirnriegel stehen ueber die Wellwand vor
						for ex in [-1.0, 1.0]:
							var fx: float = cx + ex * (C_LEN * 0.5 - 0.06)
							for ez in [-1.0, 1.0]:
								cb.add(Vector3(fx, cy, z + ez * (C_W * 0.5 - 0.07)), Vector3(0.16, C_H - 0.04, 0.18))
								for ey in [-1.0, 1.0]:
									# Eckbeschlag (ISO-Eckguss)
									detail.add(Vector3(cx + ex * (C_LEN * 0.5 - 0.08), cy + ey * (C_H * 0.5 - 0.1), z + ez * (C_W * 0.5 - 0.08)), Vector3(0.18, 0.16, 0.18))
							cb.add(Vector3(fx, cy + C_H * 0.5 - 0.1, z), Vector3(0.16, 0.18, C_W))
							cb.add(Vector3(fx, cy - C_H * 0.5 + 0.1, z), Vector3(0.16, 0.18, C_W))
						cb.add(Vector3(cx, cy + C_H * 0.5 - 0.08, z + C_W * 0.5 - 0.05), Vector3(C_LEN, 0.14, 0.12))
						cb.add(Vector3(cx, cy + C_H * 0.5 - 0.08, z - C_W * 0.5 + 0.05), Vector3(C_LEN, 0.14, 0.12))
						# Tuerseite zur Gasse: vier Verschlussstangen, Mittelfuge, Griffe
						if near_aisle:
							var dx: float = cx + (C_LEN * 0.5 + 0.03) * (1.0 if side == 0 else -1.0)
							for bz in [-0.88, -0.36, 0.36, 0.88]:
								detail.add(Vector3(dx, cy, z + bz), Vector3(0.05, C_H - 0.45, 0.05))
								detail.add(Vector3(dx + (0.02 if side == 0 else -0.02), cy - 0.15, z + bz + 0.08), Vector3(0.04, 0.06, 0.2))
							detail.add(Vector3(dx, cy, z), Vector3(0.03, C_H - 0.3, 0.025))
					Geo.add_box_shape(body, Vector3(cx, h * C_H * 0.5, z), Vector3(C_LEN, h * C_H, C_W))
					if use_model:
						shadow.add(Vector3(cx, h * C_H * 0.5, z), Vector3(C_LEN - 0.1, h * C_H - 0.05, C_W - 0.1))
				z -= C_PITCH
	for key in chunks:
		var arr: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _cont_mesh
		mm.instance_count = arr.size()
		for q in arr.size():
			mm.set_instance_transform(q, arr[q][0])
			mm.set_instance_color(q, arr[q][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Containers_" + str(key)
		mmi.multimesh = mm
		mmi.material_override = _cont_m
		mmi.lod_bias = 0.5
		# Schatten kommen aus den Stapelboxen (s. u.), Sichtweite begrenzt (Hafenbecken: Stapel weit weg)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 420.0
		mmi.visibility_range_end_margin = 40.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		world.add_child(mmi)
	var smesh := shadow.build()
	if smesh != null:
		var sn := Geo.mesh_node(smesh, Geo.flat(Color(0.3, 0.3, 0.3), 0.9), Vector3.ZERO)
		sn.name = "ContainerShadows"
		sn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		world.add_child(sn)
	for j in cols.size():
		var mesh: ArrayMesh = (batches[j] as Geo.BoxBatch).build()
		if mesh != null:
			world.add_child(Geo.mesh_node(mesh, _container_mat(cols[j]), Vector3.ZERO))
	var dmesh := detail.build()
	if dmesh != null:
		world.add_child(Geo.mesh_node(dmesh, Geo.flat(Color(0.16, 0.15, 0.14), 0.55, 0.7), Vector3.ZERO, false))
	# Betonsperren (Jersey) in der Gasse: Poly-Haven "concrete_road_barrier" (2 Segmente je Sperre),
	# Kollision unveraendert 3,2 x 0,9 x 0,6 (Deckung/Navmesh wie bisher)
	for p in BARRIERS:
		var b := Geo.static_body(p + Vector3(0, 0.45, 0))
		b.set_meta("surface", "concrete")
		Geo.add_box_shape(b, Vector3.ZERO, Vector3(3.2, 0.9, 0.6))
		world.add_child(b)
		for sx in [-0.8, 0.8]:
			PH.place(b, "concrete_road_barrier", Transform3D(Basis.IDENTITY.scaled(Vector3(1.03, 1.1, 0.94)), Vector3(sx, -0.45, 0.0)))
	# Wachhaeuschen
	var hut_m := Geo.flat(Color(0.7, 0.7, 0.66), 0.8)
	var hb := Geo.solid_box(world, HUT + Vector3(0, 1.4, 0), Vector3(4.0, 2.8, 3.4), hut_m)
	hb.set_meta("surface", "metal")
	var win := Geo.flat(Color(0.9, 0.85, 0.6), 0.3, 0.0, Color(1.0, 0.85, 0.55), 2.5)
	world.add_child(Geo.box_mesh_node(Vector3(0.05, 0.9, 2.2), win, HUT + Vector3(-2.02, 1.7, 0)))
	var hl := OmniLight3D.new()
	hl.light_color = Color(1.0, 0.82, 0.55)
	hl.light_energy = 1.6
	hl.omni_range = 9.0
	hl.position = HUT + Vector3(-3.0, 2.2, 0)
	world.add_child(hl)

# ------------------------------------------------------------------ Portalkran (Kerners Stellung)

static func _build_crane(world: Node3D, wind: Node) -> void:
	var steel := Geo.flat(Color(0.62, 0.42, 0.08), 0.6, 0.5)
	var dark := Geo.flat(Color(0.12, 0.12, 0.13), 0.8, 0.4)
	var body := Geo.static_body()
	body.name = "GantryCrane"
	body.set_meta("surface", "metal")
	world.add_child(body)
	var bb := Geo.batch()
	# Beine (je zwei pro Seite) + Querriegel
	for x in [-14.0, 18.0]:
		for z in [CRANE_Z - 2.6, CRANE_Z + 2.6]:
			bb.add(Vector3(x, CRANE_Y * 0.5, z), Vector3(1.2, CRANE_Y, 1.2))
			Geo.add_box_shape(body, Vector3(x, CRANE_Y * 0.5, z), Vector3(1.2, CRANE_Y, 1.2))
		bb.add(Vector3(x, 0.5, CRANE_Z), Vector3(2.0, 1.0, 9.0))
		bb.add(Vector3(x, 12.0, CRANE_Z), Vector3(0.6, 0.6, 5.2))
		bb.add(Vector3(x, 22.0, CRANE_Z), Vector3(0.6, 0.6, 5.2))
		# Kreuzverbaende zwischen den Beinpaaren (Fachwerk statt glatter Pfosten)
		for yy: Array in [[1.2, 11.7], [12.3, 21.7], [22.3, CRANE_Y - 2.6]]:
			_strut(bb, Vector3(x, yy[0], CRANE_Z - 2.3), Vector3(x, yy[1], CRANE_Z + 2.3), 0.28)
			_strut(bb, Vector3(x, yy[0], CRANE_Z + 2.3), Vector3(x, yy[1], CRANE_Z - 2.3), 0.28)
	# Hauptträger (Laufsteg) – begehbar
	var floor_c := Vector3(2.0, CRANE_Y - 0.2, CRANE_Z)
	bb.add(floor_c, Vector3(36.0, 0.4, 6.0))
	Geo.add_box_shape(body, floor_c, Vector3(36.0, 0.4, 6.0))
	bb.add(Vector3(2.0, CRANE_Y - 1.4, CRANE_Z - 2.6), Vector3(36.0, 2.0, 0.5))
	bb.add(Vector3(2.0, CRANE_Y - 1.4, CRANE_Z + 2.6), Vector3(36.0, 2.0, 0.5))
	# Laufkatze + Kabine (hinter Kerner, Sueden)
	bb.add(Vector3(-6.0, CRANE_Y + 1.4, CRANE_Z + 1.2), Vector3(5.0, 2.8, 3.0))
	Geo.add_box_shape(body, Vector3(-6.0, CRANE_Y + 1.4, CRANE_Z + 1.2), Vector3(5.0, 2.8, 3.0))
	# Eckstreben Bein -> Hauptträger (Portalrahmen)
	for x in [-14.0, 18.0]:
		var dx := 4.0 if x < 0.0 else -4.0
		for zz in [CRANE_Z - 2.6, CRANE_Z + 2.6]:
			_strut(bb, Vector3(x, CRANE_Y - 6.0, zz), Vector3(x + dx, CRANE_Y - 2.3, zz), 0.4)
	world.add_child(Geo.mesh_node(bb.build(), steel, Vector3.ZERO))
	# Kabine: Fensterband (schwach beleuchtet), Seile der Laufkatze und Spreader darunter
	var cab_win := Geo.flat(Color(0.3, 0.35, 0.4), 0.15, 0.0, Color(0.85, 0.75, 0.55), 0.6)
	world.add_child(Geo.box_mesh_node(Vector3(4.6, 0.9, 0.04), cab_win, Vector3(-6.0, CRANE_Y + 1.9, CRANE_Z + 2.72)))
	world.add_child(Geo.box_mesh_node(Vector3(0.04, 0.9, 2.4), cab_win, Vector3(-8.52, CRANE_Y + 1.9, CRANE_Z + 1.2)))
	var ropes := Geo.batch()
	var spr_y := 9.0
	for rx in [-7.4, -4.6]:
		for rz in [CRANE_Z + 0.4, CRANE_Z + 2.0]:
			ropes.add(Vector3(rx, (CRANE_Y - 0.4 + spr_y + 0.6) * 0.5, rz), Vector3(0.035, CRANE_Y - 1.0 - spr_y, 0.035))
	world.add_child(Geo.mesh_node(ropes.build(), dark, Vector3.ZERO, false))
	var spreader := Geo.flat(Color(0.75, 0.55, 0.05), 0.6, 0.4)
	var sb := Geo.batch()
	sb.add(Vector3(-6.0, spr_y + 0.3, CRANE_Z + 1.2), Vector3(12.0, 0.45, 0.5))
	sb.add(Vector3(-6.0, spr_y + 0.55, CRANE_Z + 1.2), Vector3(3.2, 0.6, 2.2))
	for ex in [-1.0, 1.0]:
		sb.add(Vector3(-6.0 + ex * 5.9, spr_y + 0.3, CRANE_Z + 1.2), Vector3(0.4, 0.45, 2.44))
	world.add_child(Geo.mesh_node(sb.build(), spreader, Vector3.ZERO))
	# Kranschienen (Portalkran faehrt in z)
	var rail := Geo.flat(Color(0.3, 0.29, 0.28), 0.45, 0.8)
	var rlb := Geo.batch()
	for x in [-14.0, 18.0]:
		rlb.add(Vector3(x, 0.04, CRANE_Z + 20.0), Vector3(0.14, 0.08, 60.0))
	world.add_child(Geo.mesh_node(rlb.build(), rail, Vector3.ZERO, false))
	# Gelaender: Nordseite nur Handlauf (liegend frei schiessen), Sued voll
	var rb := Geo.batch()
	var rail_n := Vector3(2.0, CRANE_Y + 1.0, CRANE_Z - 2.9)
	rb.add(rail_n, Vector3(36.0, 0.08, 0.08))
	rb.add(Vector3(2.0, CRANE_Y + 1.0, CRANE_Z + 2.9), Vector3(36.0, 0.08, 0.08))
	rb.add(Vector3(2.0, CRANE_Y + 0.5, CRANE_Z + 2.9), Vector3(36.0, 0.06, 0.06))
	var x := -16.0
	while x <= 20.0:
		rb.add(Vector3(x, CRANE_Y + 0.5, CRANE_Z - 2.9), Vector3(0.07, 1.0, 0.07))
		rb.add(Vector3(x, CRANE_Y + 0.5, CRANE_Z + 2.9), Vector3(0.07, 1.0, 0.07))
		x += 2.0
	world.add_child(Geo.mesh_node(rb.build(), dark, Vector3.ZERO, false))
	Geo.add_box_shape(body, rail_n, Vector3(36.0, 0.2, 0.15))
	# Unsichtbare Absturzsicherung (nur Bewegung, Layer 5 = move_block; Kugeln fliegen durch)
	var guard := StaticBody3D.new()
	guard.name = "CraneGuard"
	guard.collision_layer = 16
	guard.collision_mask = 0
	world.add_child(guard)
	Geo.add_box_shape(guard, Vector3(2.0, CRANE_Y + 1.0, CRANE_Z - 3.2), Vector3(37.0, 2.0, 0.3))
	Geo.add_box_shape(guard, Vector3(2.0, CRANE_Y + 1.0, CRANE_Z + 3.2), Vector3(37.0, 2.0, 0.3))
	Geo.add_box_shape(guard, Vector3(-16.2, CRANE_Y + 1.0, CRANE_Z), Vector3(0.3, 2.0, 6.6))
	Geo.add_box_shape(guard, Vector3(20.2, CRANE_Y + 1.0, CRANE_Z), Vector3(0.3, 2.0, 6.6))
	# Leiter (Optik) am Westbein
	var lb := Geo.batch()
	var y := 0.4
	while y < CRANE_Y:
		lb.add(Vector3(-14.0, y, CRANE_Z - 3.5), Vector3(0.7, 0.05, 0.05))
		y += 0.4
	world.add_child(Geo.mesh_node(lb.build(), dark, Vector3.ZERO, false))
	# Flugwarnlichter + Flutlicht
	var red := Geo.flat(Color(1, 0.1, 0.05), 0.4, 0.0, Color(1, 0.1, 0.05), 6.0)
	for p in [Vector3(-14.0, CRANE_Y + 0.4, CRANE_Z - 3.0), Vector3(18.0, CRANE_Y + 0.4, CRANE_Z - 3.0), Vector3(-6.0, CRANE_Y + 3.0, CRANE_Z + 1.2)]:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.18
		sm.height = 0.36
		s.mesh = sm
		s.material_override = red
		s.position = p
		world.add_child(s)
	var flood := SpotLight3D.new()
	flood.light_color = Color(1.0, 0.86, 0.66)
	flood.light_energy = 6.0
	flood.spot_range = 70.0
	flood.spot_angle = 50.0
	flood.position = Vector3(2.0, CRANE_Y - 2.0, CRANE_Z - 3.2)
	flood.rotation_degrees = Vector3(-80, 0, 0)
	# Kein Lichtkegel im Dunst direkt vor Kerners Zielfernrohr (frueher Hauptgrund fuer die "Nebelwand")
	flood.light_volumetric_fog_energy = 0.0
	flood.shadow_enabled = false
	world.add_child(flood)
	var work := OmniLight3D.new()
	work.light_color = Color(1.0, 0.8, 0.55)
	work.light_energy = 0.9
	work.omni_range = 7.0
	work.position = Vector3(-3.0, CRANE_Y + 2.5, CRANE_Z + 1.0)
	work.light_volumetric_fog_energy = 0.0
	world.add_child(work)
	if wind != null:
		# Windsack auf dem Kopftraeger (Ostende), 18 m neben Kerner: Nahanzeige fuer den Seewind
		wind.call("add_sock", world, Vector3(19.3, CRANE_Y, CRANE_Z + 2.2), {"len": 2.4, "mount": "pole", "pole_h": 3.4, "guys": false, "glow": 0.1, "top_light": true})
		var sl := OmniLight3D.new()
		sl.light_color = Color(1.0, 0.86, 0.66)
		sl.light_energy = 0.8
		sl.omni_range = 5.0
		sl.light_volumetric_fog_energy = 0.0
		sl.shadow_enabled = false
		sl.position = Vector3(18.6, CRANE_Y + 2.4, CRANE_Z + 1.6)
		world.add_child(sl)

# ------------------------------------------------------------------ Lichtmasten

static func _build_masts(world: Node3D, wind: Node) -> void:
	var pole := Geo.flat(Color(0.35, 0.36, 0.37), 0.6, 0.6)
	var lamp := Geo.flat(Color(1.0, 0.85, 0.6), 0.3, 0.0, Color(1.0, 0.8, 0.5), 4.0)
	var pb := Geo.batch()
	var lb := Geo.batch()
	var body := Geo.static_body()
	body.name = "Masts"
	body.set_meta("surface", "metal")
	world.add_child(body)
	var z := 20.0
	var n := 0
	while z > -290.0:
		for x in [-5.0, 9.0]:
			if Vector2(x, z).distance_to(Vector2(MARKSMAN.x, MARKSMAN.z)) < 20.0:
				continue
			pb.add(Vector3(x, 10.0, z), Vector3(0.45, 20.0, 0.45))
			Geo.add_box_shape(body, Vector3(x, 10.0, z), Vector3(0.45, 20.0, 0.45))
			lb.add(Vector3(x, 20.1, z), Vector3(1.6, 0.25, 0.8))
			var sp := SpotLight3D.new()
			sp.light_color = Color(1.0, 0.8, 0.52)
			sp.light_energy = 5.0
			sp.spot_range = 34.0
			sp.spot_angle = 58.0
			sp.spot_attenuation = 0.8
			sp.light_volumetric_fog_energy = 0.2
			sp.position = Vector3(x, 19.8, z)
			sp.rotation_degrees = Vector3(-90, 0, 0)
			world.add_child(sp)
			if wind != null and n % 3 == 0:
				# Windsack am Ausleger unter dem Leuchtenkopf (vom eigenen Mastlicht angestrahlt), Ausleger nach Osten = windabwaerts
				wind.call("add_sock", world, Vector3(x + 0.24, 17.6, z), {"len": 3.0, "mount": "bracket", "arm": Vector3(1.1, 0.0, 0.0), "stub_h": 0.7, "glow": 0.12})
			n += 1
		z -= 40.0
	# Mast mit Plattform fuer den Garde-Schuetzen (Lichtmast Nr. 7)
	pb.add(Vector3(MARKSMAN.x, 9.0, MARKSMAN.z - 1.2), Vector3(0.6, 18.0, 0.6))
	Geo.add_box_shape(body, Vector3(MARKSMAN.x, 9.0, MARKSMAN.z - 1.2), Vector3(0.6, 18.0, 0.6))
	pb.add(MARKSMAN + Vector3(0, -0.15, 0), Vector3(2.6, 0.3, 2.6))
	Geo.add_box_shape(body, MARKSMAN + Vector3(0, -0.15, 0), Vector3(2.6, 0.3, 2.6))
	pb.add(MARKSMAN + Vector3(0, 0.5, 1.3), Vector3(2.6, 1.0, 0.06))
	pb.add(MARKSMAN + Vector3(1.3, 0.5, 0), Vector3(0.06, 1.0, 2.6))
	pb.add(MARKSMAN + Vector3(-1.3, 0.5, 0), Vector3(0.06, 1.0, 2.6))
	lb.add(MARKSMAN + Vector3(0, 4.0, -1.2), Vector3(1.6, 0.25, 0.8))
	# Die Plattform liegt im eigenen Lampenlicht: Der Schuetze ist auf 240 m als Silhouette lesbar.
	var psl := SpotLight3D.new()
	psl.name = "MarksmanLamp"
	psl.light_color = Color(1.0, 0.78, 0.5)
	psl.light_energy = 6.0
	psl.spot_range = 9.0
	psl.spot_angle = 50.0
	psl.light_volumetric_fog_energy = 0.4
	psl.shadow_enabled = false
	psl.position = MARKSMAN + Vector3(0, 3.8, -0.6)
	psl.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(psl)
	world.add_child(Geo.mesh_node(pb.build(), pole, Vector3.ZERO))
	world.add_child(Geo.mesh_node(lb.build(), lamp, Vector3.ZERO, false))

# ------------------------------------------------------------------ Kai, Containerbruecken

## Containerbruecke (STS): Portal mit Riegeln und Kreuzverbaenden, A-Bock, Zwillings-Kastentraeger-Ausleger
## mit Abspannungen, Maschinenhaus, Laufkatze/Spreader (bei abgesenktem Ausleger), Leuchten und Flughindernisfeuern.
## Wasserseitiges Bein steht auf einem Pfahlrost-Kopf vor der Kaimauer. Keine Kollision (reine Kulisse).
static func _sts_crane(world: Node3D, z: float, m: Material, boom_up: bool) -> void:
	var bb := Geo.batch()
	var xl := 37.0
	var xw := 47.0
	for zz in [z - 8.0, z + 8.0]:
		for x in [xl, xw]:
			bb.add(Vector3(x, 15.0, zz), Vector3(1.4, 30.0, 1.6))
			bb.add(Vector3(x, 37.0, zz), Vector3(1.1, 14.0, 1.2))
		bb.add(Vector3(42.0, 14.0, zz), Vector3(10.0, 1.2, 1.2))
		bb.add(Vector3(42.0, 29.0, zz), Vector3(10.0, 1.6, 1.4))
	for x in [xl, xw]:
		# Fahrwerksschwelle mit Drehgestellen
		bb.add(Vector3(x, 1.0, z), Vector3(1.8, 1.2, 19.0))
		for zz in [z - 8.0, z - 5.0, z + 5.0, z + 8.0]:
			bb.add(Vector3(x, 0.45, zz), Vector3(1.4, 0.9, 2.4))
		# Laengsriegel und Kreuzverbaende in der Seitenansicht
		bb.add(Vector3(x, 14.0, z), Vector3(1.2, 1.2, 16.0))
		bb.add(Vector3(x, 29.0, z), Vector3(1.4, 1.6, 16.0))
		_strut(bb, Vector3(x, 14.6, z - 7.5), Vector3(x, 28.4, z + 7.5), 0.5)
		_strut(bb, Vector3(x, 14.6, z + 7.5), Vector3(x, 28.4, z - 7.5), 0.5)
	# A-Bock (Spitze ueber dem wasserseitigen Bein) und Rueckstreben
	var apex := Vector3(45.0, 60.0, z)
	for sz in [-1.0, 1.0]:
		var top: Vector3 = apex + Vector3(0.0, 0.0, sz * 4.5)
		_strut(bb, Vector3(xw, 43.6, z + sz * 8.0), top, 1.0)
		_strut(bb, Vector3(xl, 43.6, z + sz * 8.0), top, 0.8)
	bb.add(apex + Vector3(0.0, 0.4, 0.0), Vector3(1.2, 1.2, 10.0))
	# Ausleger (Zwillings-Kastentraeger) mit Abspannungen
	var by := 42.6
	var ang := deg_to_rad(75.0)
	var d := Vector3(cos(ang), sin(ang), 0.0)
	for sz in [-1.0, 1.0]:
		var zz: float = z + sz * 3.2
		var top: Vector3 = apex + Vector3(0.0, 0.0, sz * 4.5)
		bb.add(Vector3((20.0 + xw) * 0.5, by, zz), Vector3(xw - 20.0, 2.2, 1.2))
		if boom_up:
			bb.add(Vector3(xw, by, zz) + d * 25.0, Vector3(50.0, 1.8, 1.1), Basis(Vector3.BACK, ang))
			_strut(bb, top, Vector3(xw, by, zz) + d * 34.0, 0.25)
		else:
			bb.add(Vector3((xw + 100.0) * 0.5, by, zz), Vector3(100.0 - xw, 1.8, 1.1))
			_strut(bb, top, Vector3(65.0, by + 1.0, zz), 0.25)
			_strut(bb, top, Vector3(90.0, by + 1.0, zz), 0.22)
		_strut(bb, top, Vector3(22.0, by + 1.0, zz), 0.3)
	var x_end := xw if boom_up else 100.0
	var xq := 22.0
	while xq <= x_end:
		bb.add(Vector3(xq, by - 0.9, z), Vector3(0.5, 0.4, 7.6))
		xq += 6.0
	# Maschinenhaus (hell) und Gegengewicht
	var house := Geo.flat(Color(0.72, 0.73, 0.72), 0.7)
	world.add_child(Geo.box_mesh_node(Vector3(9.0, 4.4, 7.8), house, Vector3(27.0, by + 3.3, z)))
	bb.add(Vector3(21.5, by - 2.2, z), Vector3(3.0, 2.6, 6.4))
	var dark := Geo.flat(Color(0.08, 0.08, 0.09), 0.6, 0.5)
	var hb := Geo.batch()
	if not boom_up:
		# Laufkatze mit Kabine, Seile, Spreader und haengender Container ueber dem Wasser
		var tx := 70.0
		bb.add(Vector3(tx, by + 0.2, z), Vector3(5.0, 1.6, 7.6))
		var cab := Geo.flat(Color(0.7, 0.7, 0.68), 0.6, 0.2)
		world.add_child(Geo.box_mesh_node(Vector3(2.6, 2.6, 2.4), cab, Vector3(tx - 1.0, by - 2.4, z - 2.4)))
		var win := Geo.flat(Color(0.3, 0.33, 0.36), 0.15, 0.0, Color(0.9, 0.8, 0.6), 1.2)
		world.add_child(Geo.box_mesh_node(Vector3(2.62, 1.0, 1.8), win, Vector3(tx - 1.0, by - 2.2, z - 2.4)))
		var sy := 12.0
		for rx in [-1.6, 1.6]:
			for rz in [-1.0, 1.0]:
				hb.add(Vector3(tx + rx, (by - 0.6 + sy + 0.8) * 0.5, z + rz), Vector3(0.05, by - 0.6 - sy - 0.8, 0.05))
		var spr := Geo.flat(Color(0.75, 0.55, 0.05), 0.6, 0.4)
		world.add_child(Geo.box_mesh_node(Vector3(12.2, 0.5, 2.5), spr, Vector3(tx, sy + 0.6, z)))
		world.add_child(Geo.box_mesh_node(Vector3(C_LEN, C_H, C_W), _container_mat(Color(0.55, 0.16, 0.1)), Vector3(tx, sy - C_H * 0.5 + 0.35, z)))
	world.add_child(Geo.mesh_node(bb.build(), m, Vector3.ZERO))
	if hb.count > 0:
		world.add_child(Geo.mesh_node(hb.build(), dark, Vector3.ZERO, false))
	# Pfahlrost-Kopf unter dem wasserseitigen Bein
	var conc := Geo.mat("concrete_wall_008", Color(0.4, 0.4, 0.41), 0.2)
	world.add_child(Geo.box_mesh_node(Vector3(4.0, 2.4, 22.0), conc, Vector3(xw - 0.5, -0.9, z)))
	# Leuchtbaender, Arbeitslicht nach unten, Flughindernisfeuer
	var lamp := Geo.flat(Color(1.0, 0.88, 0.7), 0.3, 0.0, Color(1.0, 0.85, 0.6), 6.0)
	var lb := Geo.batch()
	for x in [30.0, 40.0, 44.0]:
		lb.add(Vector3(x, by - 1.25, z), Vector3(1.2, 0.2, 0.6))
	lb.add(Vector3(42.0, 28.1, z - 8.0), Vector3(1.0, 0.2, 0.5))
	lb.add(Vector3(42.0, 28.1, z + 8.0), Vector3(1.0, 0.2, 0.5))
	world.add_child(Geo.mesh_node(lb.build(), lamp, Vector3.ZERO, false))
	var sp := SpotLight3D.new()
	sp.light_color = Color(1.0, 0.86, 0.66)
	sp.light_energy = 6.0
	sp.spot_range = 48.0
	sp.spot_angle = 55.0
	sp.spot_attenuation = 0.7
	sp.light_volumetric_fog_energy = 0.3
	sp.position = Vector3(42.0, 38.5, z)
	sp.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(sp)
	var red := Geo.flat(Color(1, 0.1, 0.05), 0.4, 0.0, Color(1, 0.1, 0.05), 8.0)
	var rb := Geo.batch()
	rb.add(apex + Vector3(0.0, 1.3, 0.0), Vector3(0.45, 0.45, 0.45))
	rb.add(Vector3(20.0, by + 1.4, z), Vector3(0.4, 0.4, 0.4))
	if boom_up:
		rb.add(Vector3(xw, by, z) + d * 50.0, Vector3(0.45, 0.45, 0.45))
	else:
		rb.add(Vector3(100.0, by + 1.2, z), Vector3(0.4, 0.4, 0.4))
	world.add_child(Geo.mesh_node(rb.build(), red, Vector3.ZERO, false))

## Hohe Flutlichtmasten (32 m) neben den Quergassen: machen Gassen und Gegnerstellungen auf 150-400 m lesbar,
## ohne Lichtkegel im Dunst (geringe Volumetrik-Energie, keine Schatten).
static func _build_high_masts(world: Node3D) -> void:
	var steel := Geo.flat(Color(0.4, 0.41, 0.42), 0.55, 0.6)
	var lamp := Geo.flat(Color(1.0, 0.9, 0.75), 0.3, 0.0, Color(1.0, 0.88, 0.7), 10.0)
	var body := Geo.static_body()
	body.name = "HighMasts"
	body.set_meta("surface", "metal")
	world.add_child(body)
	var pole_xfs: Array = []
	var bb := Geo.batch()
	var lb := Geo.batch()
	var h := 32.0
	for p: Vector2 in [Vector2(-44.0, -104.0), Vector2(-46.0, -174.0), Vector2(-46.0, -239.0), Vector2(24.0, -174.0), Vector2(26.0, -106.0)]:
		var base := Vector3(p.x, 0.0, p.y)
		pole_xfs.append(Transform3D(Basis.IDENTITY, base + Vector3(0.0, h * 0.5, 0.0)))
		Geo.add_box_shape(body, base + Vector3(0.0, h * 0.5, 0.0), Vector3(0.9, h, 0.9))
		bb.add(base + Vector3(0.0, 0.25, 0.0), Vector3(1.8, 0.5, 1.8))
		bb.add(base + Vector3(0.0, h + 0.3, 0.0), Vector3(3.6, 0.3, 3.6))
		for k in 6:
			var a := TAU * float(k) / 6.0
			lb.add(base + Vector3(cos(a) * 1.5, h + 0.05, sin(a) * 1.5), Vector3(0.7, 0.18, 0.45), Basis(Vector3.UP, -a))
		var sp := SpotLight3D.new()
		sp.light_color = Color(1.0, 0.86, 0.66)
		sp.light_energy = 7.5
		sp.spot_range = 75.0
		sp.spot_angle = 62.0
		sp.spot_attenuation = 0.6
		sp.light_volumetric_fog_energy = 0.3
		sp.shadow_enabled = false
		sp.position = base + Vector3(0.0, h - 0.4, 0.0)
		sp.rotation_degrees = Vector3(-90, 0, 0)
		world.add_child(sp)
	world.add_child(Geo.mesh_node(_mesh_batch(_cyl_mesh(0.22, 0.45, h, 10), pole_xfs), steel, Vector3.ZERO))
	world.add_child(Geo.mesh_node(bb.build(), steel, Vector3.ZERO))
	world.add_child(Geo.mesh_node(lb.build(), lamp, Vector3.ZERO, false))

static func _build_quay(world: Node3D) -> void:
	var m := Geo.flat(Color(0.12, 0.25, 0.42), 0.6, 0.5)
	_sts_crane(world, -55.0, m, true)
	_sts_crane(world, -140.0, m, false)
	_sts_crane(world, -275.0, m, true)
	# Lagerhallen am Ostufer (Ziel-Kulisse fuer die Kai-Schuetzen)
	var wall := Geo.mat("brick_wall_02", Color(0.5, 0.45, 0.42), 0.12)
	var roof := Geo.mat("rusty_metal_02", Color(0.6, 0.6, 0.6), 0.1, 1.0, 0.4)
	var z := -280.0
	while z > -900.0:
		Geo.solid_box(world, Vector3(175.0, 6.0, z), Vector3(50.0, 12.0, 60.0), wall)
		world.add_child(Geo.box_mesh_node(Vector3(52.0, 0.6, 62.0), roof, Vector3(175.0, 12.3, z)))
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.75, 0.45)
		lamp.light_energy = 2.0
		lamp.omni_range = 16.0
		lamp.position = Vector3(149.0, 8.0, z)
		world.add_child(lamp)
		z -= 80.0
	# Kai-Deckung fuer die Schuetzen (Paletten/Kisten)
	var crate := Geo.flat(Color(0.35, 0.28, 0.18), 0.9)
	for zz in [-350.0, -385.0, -420.0, -470.0]:
		Geo.solid_box(world, Vector3(144.5, 0.6, zz), Vector3(1.4, 1.2, 3.0), crate)
	# Webers Liegeplatz 7 mit Laterne
	var berth := OmniLight3D.new()
	berth.light_color = Color(0.9, 0.95, 1.0)
	berth.light_energy = 2.5
	berth.omni_range = 14.0
	berth.position = Vector3(40.0, 5.0, BERTH7.z)
	world.add_child(berth)

# ------------------------------------------------------------------ Bruecke

static func _build_bridge(world: Node3D) -> void:
	var conc := Geo.mat("concrete_wall_008", Color(0.45, 0.45, 0.47), 0.1)
	var steel := Geo.flat(Color(0.3, 0.32, 0.3), 0.6, 0.6)
	var deck_c := Vector3(90.0, BRIDGE_DECK_Y - 0.6, BRIDGE_Z)
	var b := Geo.solid_box(world, deck_c, Vector3(260.0, 1.2, 14.0), conc)
	b.set_meta("surface", "concrete")
	for x in [62.0, 118.0]:
		var p := Geo.solid_box(world, Vector3(x, (BRIDGE_DECK_Y - 1.2 + WATER_Y - 6.0) * 0.5, BRIDGE_Z), Vector3(4.0, BRIDGE_DECK_Y - 1.2 - WATER_Y + 6.0, 10.0), conc)
		p.set_meta("surface", "concrete")
	# Rampen auf beide Ufer (Optik)
	world.add_child(Geo.box_mesh_node(Vector3(80.0, 1.2, 14.0), conc, Vector3(-20.0, BRIDGE_DECK_Y * 0.5 - 0.6, BRIDGE_Z), Vector3(0, 0, -12.5)))
	world.add_child(Geo.box_mesh_node(Vector3(80.0, 1.2, 14.0), conc, Vector3(200.0, BRIDGE_DECK_Y * 0.5 - 0.6, BRIDGE_Z), Vector3(0, 0, 12.5)))
	# Gelaender (ohne Kollision) + Fachwerk-Hubtuerme
	var rb := Geo.batch()
	for side in [-1.0, 1.0]:
		rb.add(Vector3(90.0, BRIDGE_DECK_Y + 1.0, BRIDGE_Z + side * 6.8), Vector3(130.0, 0.1, 0.1))
		var x := 26.0
		while x <= 154.0:
			rb.add(Vector3(x, BRIDGE_DECK_Y + 0.5, BRIDGE_Z + side * 6.8), Vector3(0.08, 1.0, 0.08))
			x += 2.5
	for x in [62.0, 118.0]:
		for side in [-1.0, 1.0]:
			rb.add(Vector3(x, BRIDGE_DECK_Y + 12.0, BRIDGE_Z + side * 5.5), Vector3(2.0, 24.0, 2.0))
		rb.add(Vector3(x, BRIDGE_DECK_Y + 24.0, BRIDGE_Z), Vector3(2.4, 2.0, 13.0))
	world.add_child(Geo.mesh_node(rb.build(), steel, Vector3.ZERO))
	for x in [40.0, 90.0, 140.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.light_energy = 2.5
		l.omni_range = 18.0
		l.position = Vector3(x, BRIDGE_DECK_Y + 5.0, BRIDGE_Z)
		world.add_child(l)
	var red := Geo.flat(Color(1, 0.1, 0.05), 0.4, 0.0, Color(1, 0.1, 0.05), 6.0)
	var grn := Geo.flat(Color(0.1, 1, 0.2), 0.4, 0.0, Color(0.1, 1, 0.2), 6.0)
	world.add_child(Geo.box_mesh_node(Vector3(0.5, 0.5, 0.5), red, Vector3(64.5, BRIDGE_DECK_Y - 2.0, BRIDGE_Z + 7.2)))
	world.add_child(Geo.box_mesh_node(Vector3(0.5, 0.5, 0.5), grn, Vector3(115.5, BRIDGE_DECK_Y - 2.0, BRIDGE_Z + 7.2)))

# ------------------------------------------------------------------ Muendung, Molen, Leuchtturm

static func _build_mouth(world: Node3D) -> void:
	var stone := Geo.mat("concrete_wall_008", Color(0.4, 0.4, 0.42), 0.15)
	# Westmole entlang z -1150, Ostmole x 420 von z -930 bis -1005
	var w := Geo.solid_box(world, Vector3(175.0, -0.5, -1155.0), Vector3(270.0, 5.0, 10.0), stone)
	w.set_meta("surface", "concrete")
	var e := Geo.solid_box(world, Vector3(425.0, -0.5, -967.0), Vector3(10.0, 5.0, 74.0), stone)
	e.set_meta("surface", "concrete")
	# Leuchttuerme an den Molenkoepfen
	var white := Geo.flat(Color(0.85, 0.85, 0.82), 0.6)
	var redm := Geo.flat(Color(0.6, 0.1, 0.08), 0.6)
	world.add_child(Geo.cylinder_node(2.0, 18.0, white, Vector3(305.0, 11.0, -1155.0)))
	world.add_child(Geo.cylinder_node(1.6, 14.0, redm, Vector3(425.0, 9.0, -1000.0)))
	for p: Vector3 in [Vector3(305.0, 21.0, -1155.0), Vector3(425.0, 17.0, -1000.0)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.95, 0.8) if p.x < 400.0 else Color(1.0, 0.3, 0.2)
		l.light_energy = 6.0
		l.omni_range = 40.0
		l.position = p
		world.add_child(l)
	# Fahrwassertonnen
	var buoy := Geo.flat(Color(0.8, 0.15, 0.1), 0.6, 0.0, Color(0.8, 0.15, 0.1), 1.5)
	for p: Vector3 in [Vector3(110.0, -1.4, -880.0), Vector3(170.0, -1.4, -950.0), Vector3(260.0, -1.4, -1000.0), Vector3(370.0, -1.4, -1020.0)]:
		world.add_child(Geo.cylinder_node(0.6, 1.6, buoy, p))

static func _build_freighter(lv: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Aurelia"
	lv.add_child(root)
	root.global_position = FREIGHTER
	var hull := Geo.flat(Color(0.12, 0.14, 0.18), 0.7, 0.3)
	var red := Geo.flat(Color(0.4, 0.08, 0.06), 0.8)
	var white := Geo.flat(Color(0.8, 0.8, 0.78), 0.6)
	var win := Geo.flat(Color(1.0, 0.85, 0.55), 0.3, 0.0, Color(1.0, 0.85, 0.55), 3.0)
	var body := Geo.static_body()
	body.set_meta("surface", "metal")
	root.add_child(body)
	# Rumpf laengs x, Breite 22 (z), Bordwand 12 m ueber Wasser
	root.add_child(Geo.box_mesh_node(Vector3(150.0, 12.0, 22.0), hull, Vector3(0, 8.0, 0)))
	root.add_child(Geo.box_mesh_node(Vector3(150.2, 4.0, 22.2), red, Vector3(0, 0.0, 0)))
	Geo.add_box_shape(body, Vector3(0, 5.0, 0), Vector3(150.0, 18.0, 22.0))
	# Bug als Keil
	var bow := Geo.box_mesh_node(Vector3(16.0, 14.0, 16.0), hull, Vector3(-78.0, 7.0, 0), Vector3(0, 45, 0))
	root.add_child(bow)
	# Aufbauten achtern (Osten) + Containerladung
	root.add_child(Geo.box_mesh_node(Vector3(16.0, 16.0, 20.0), white, Vector3(62.0, 22.0, 0)))
	root.add_child(Geo.box_mesh_node(Vector3(3.0, 10.0, 3.0), red, Vector3(56.0, 34.0, 0)))
	for i in 5:
		root.add_child(Geo.box_mesh_node(Vector3(0.1, 1.2, 14.0), win, Vector3(53.9, 18.0 + i * 3.0, 0)))
	var cb := Geo.batch()
	var x := -60.0
	while x < 45.0:
		for zz in [-6.0, 0.0, 6.0]:
			var h := 1 + (int(absf(x + zz * 3.0)) % 3)
			cb.add(Vector3(x, 14.0 + h * 1.3, zz), Vector3(12.0, h * 2.6, 5.6))
		x += 13.0
	root.add_child(Geo.mesh_node(cb.build(), _container_mat(Color(0.35, 0.2, 0.12)), Vector3.ZERO))
	# Fallreep (Treppe) an der Suedseite bei x 545
	var stair := Geo.flat(Color(0.5, 0.5, 0.5), 0.6, 0.6)
	root.add_child(Geo.box_mesh_node(Vector3(14.0, 0.3, 1.4), stair, Vector3(FREIGHTER_BOARD.x - FREIGHTER.x + 6.0, 6.0, 11.8), Vector3(0, 0, -40)))
	# Positionslichter + Decksbeleuchtung
	for p: Vector3 in [Vector3(-70, 16, 0), Vector3(62, 32, 0), Vector3(0, 16, 12), Vector3(30, 16, 12)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.6)
		l.light_energy = 3.0
		l.omni_range = 26.0
		l.position = p
		root.add_child(l)
	var name_m := Geo.flat(Color(0.9, 0.9, 0.9), 0.5, 0.0, Color(0.9, 0.9, 0.9), 0.8)
	root.add_child(Geo.box_mesh_node(Vector3(14.0, 1.4, 0.05), name_m, Vector3(-55.0, 11.0, 11.05)))
	# Modell-Slot: echtes Frachtermodell (Bug -Z) ersetzt die Platzhalter-Optik; Bug liegt hier bei -X -> +90 Grad
	if Models.attach(root, "freighter_aurelia", 150.0, 90.0) != null:
		for ch in root.get_children():
			if ch is MeshInstance3D:
				ch.free()
		for ch in body.get_children():
			ch.free()
		# Kollision am Modell: Rumpf bis Hauptdeck, Aufbau achtern
		Geo.add_box_shape(body, Vector3(0, (FREIGHTER_DECK - FREIGHTER_DRAFT) * 0.5, 0), Vector3(146.0, FREIGHTER_DECK + FREIGHTER_DRAFT, 21.0))
		Geo.add_box_shape(body, Vector3(62.0, FREIGHTER_DECK + 8.0, 0), Vector3(14.0, 16.0, 18.0))
		# Platzhalter-Licht oben am alten Aufbau sass im Modell-Schornstein -> heller senkrechter Streifen
		for ch in root.get_children():
			if ch is OmniLight3D and (ch as OmniLight3D).position.y > 30.0:
				ch.free()
		_freighter_gangway(root)
		_freighter_name(root)
	return root

## Fallreep (Accommodation Ladder) an der Suedseite: unteres Podest knapp ueber Wasser neben FREIGHTER_BOARD,
## Treppe mit Handlaeufen schraeg nach achtern hinauf zum Hauptdeck; zwei Matrosen oben am Podest.
static func _freighter_gangway(root: Node3D) -> void:
	var steel := Geo.flat(Color(0.42, 0.43, 0.44), 0.55, 0.6)
	var white := Geo.flat(Color(0.75, 0.75, 0.72), 0.6, 0.2)
	var bb := Geo.batch()
	var rb := Geo.batch()
	var lo := Vector3(FREIGHTER_BOARD.x - FREIGHTER.x + 1.0, 0.9, 12.2)
	var hi := Vector3(lo.x + 10.0, FREIGHTER_DECK + 0.1, 11.9)
	# Podeste
	bb.add(lo + Vector3(-1.1, -0.1, 0), Vector3(2.4, 0.16, 1.5))
	bb.add(hi + Vector3(0.9, -0.1, 0), Vector3(1.8, 0.16, 1.4))
	# Stufen + Wangen
	var n := 22
	for i in n:
		var t := (float(i) + 0.5) / float(n)
		bb.add(lo.lerp(hi, t), Vector3(0.28, 0.05, 1.0))
	for sz: float in [-0.55, 0.55]:
		_strut(bb, lo + Vector3(0, -0.12, sz), hi + Vector3(0, -0.12, sz), 0.08, 0.3)
		_strut(rb, lo + Vector3(0, 1.0, sz), hi + Vector3(0, 1.0, sz), 0.05)
		for i in 5:
			var q := lo.lerp(hi, float(i) / 4.0) + Vector3(0, 0.5, sz)
			rb.add(q, Vector3(0.04, 1.0, 0.04))
	# Gelaender am unteren Podest (seeseitig) und Taljenseil zum Davit
	_strut(rb, lo + Vector3(-2.3, 1.0, 0.75), lo + Vector3(0.1, 1.0, 0.75), 0.05)
	for x: float in [-2.3, -1.1, 0.1]:
		rb.add(lo + Vector3(x, 0.5, 0.75), Vector3(0.04, 1.0, 0.04))
	_strut(rb, lo + Vector3(-0.2, 0.0, 0.6), Vector3(lo.x + 1.0, FREIGHTER_DECK + 3.0, 11.4), 0.03)
	root.add_child(Geo.mesh_node(bb.build(), steel, Vector3.ZERO))
	root.add_child(Geo.mesh_node(rb.build(), white, Vector3.ZERO, false))
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 2.2
	lamp.omni_range = 14.0
	lamp.position = hi + Vector3(0.5, 3.0, 0.8)
	root.add_child(lamp)
	var lm := Geo.flat(Color(1.0, 0.9, 0.7), 0.3, 0.0, Color(1.0, 0.85, 0.6), 5.0)
	root.add_child(Geo.box_mesh_node(Vector3(0.3, 0.2, 0.3), lm, hi + Vector3(0.5, 3.0, 0.2)))
	_sailor(root, hi + Vector3(1.0, 0.0, -0.1), 100.0, Color(0.15, 0.2, 0.32))
	_sailor(root, hi + Vector3(0.4, 0.0, 0.3), 60.0, Color(0.6, 0.35, 0.08))

## Matrose an der Gangway: echte Figur (Gegner-Visual-Pipeline, Zivil/Widerstand-Ausstattung mit Muetze),
## ohne Waffe, Idle-Animation; Fusspunkt pos, Blickrichtung yaw (Grad).
static func _sailor(root: Node3D, pos: Vector3, yaw: float, c: Color) -> void:
	Models.puppet(root, "resistance", [c, c.darkened(0.35), c], pos, yaw + 180.0,
		{"unarmed": true, "name": "Matrose"})

## Schiffsname am Vorschiff (beide Seiten).
static func _freighter_name(root: Node3D) -> void:
	for side: float in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "AURELIA"
		l.font_size = 160
		l.pixel_size = 0.012
		l.outline_size = 0
		l.modulate = Color(0.86, 0.86, 0.82)
		l.shaded = true
		l.double_sided = false
		l.position = Vector3(-56.0, 6.6, side * 9.75)
		l.rotation_degrees.y = 0.0 if side > 0.0 else 180.0
		root.add_child(l)
	# Heck (+X): Name + Heimathafen am Spiegel, x aus der Modell-Huelle unten am Rumpf (Spiegel, nicht Aufbau)
	var sx := _stern_x(root)
	for row: Array in [["AURELIA", 150, STERN_NAME_Y], ["ROSTOCK", 96, STERN_NAME_Y - 1.5]]:
		var t := Label3D.new()
		t.text = str(row[0])
		t.font_size = int(row[1])
		t.pixel_size = 0.012
		t.outline_size = 0
		t.modulate = Color(0.86, 0.86, 0.82)
		t.shaded = true
		t.double_sided = false
		t.position = Vector3(sx + 0.06, float(row[2]), 0.0)
		t.rotation_degrees.y = 90.0
		root.add_child(t)
	# Hecklaterne/Arbeitslicht ueber dem Spiegel, sonst ist die Heckschrift nachts unsichtbar
	var sl := OmniLight3D.new()
	sl.light_color = Color(1.0, 0.86, 0.62)
	sl.light_energy = 0.8
	sl.omni_range = 14.0
	sl.shadow_enabled = false
	sl.position = Vector3(sx + 5.0, STERN_NAME_Y + 4.5, 0.0)
	root.add_child(sl)

## Hoehe der Heckschrift (Root-Lokal, Wasser bei y 0 = Modell-Tiefgang abgezogen)
const STERN_NAME_Y := 6.2

## Hinterste Rumpfkante (+X) im Root-Raum, nur Vertices im Hoehenband der Heckschrift.
static func _stern_x(root: Node3D) -> float:
	var h := Models.find(root, "freighter_aurelia")
	var best := 70.0
	if h == null:
		return best
	best = -INF
	for mi: MeshInstance3D in h.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := Models._rel(root, mi)
		for si in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			for v in vs:
				var w := xf * v
				if w.y > STERN_NAME_Y - 2.2 and w.y < STERN_NAME_Y + 1.0 and absf(w.z) < 3.0 and w.x > best:
					best = w.x
	return best if best > 0.0 else 70.0

# ------------------------------------------------------------------ Wippdrehkrane (Sokol) am Westkai

## Portal-Wippdrehkrane ("Port Crane Sokol", Domender, CC-BY) auf dem Westkai noerdlich des Terminals,
## Ausleger zum Becken; Animation (Drehen/Wippen) laeuft hin und zurueck, rote Hindernisfeuer.
const PORT_CRANES: Array[Vector3] = [Vector3(32.0, 0.0, -385.0), Vector3(32.0, 0.0, -465.0),
	Vector3(32.0, 0.0, -545.0), Vector3(32.0, 0.0, -705.0), Vector3(32.0, 0.0, -790.0)]

static func _build_port_cranes(world: Node3D) -> void:
	if Models.path_for("port_crane") == "":
		return
	var red := Geo.flat(Color(1.0, 0.1, 0.05), 0.4, 0.0, Color(1.0, 0.08, 0.04), 6.0)
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sm.radial_segments = 8
	sm.rings = 4
	var rail := Geo.flat(Color(0.3, 0.29, 0.28), 0.45, 0.8)
	var rb := Geo.batch()
	var body := Geo.static_body()
	body.set_meta("surface", "metal")
	world.add_child(body)
	var yaws := [0.0, 6.0, -4.0, 3.0, -7.0]
	for i in PORT_CRANES.size():
		var p: Vector3 = PORT_CRANES[i]
		var h := Models.attach(world, "port_crane", 0.0, 0.0)
		if h == null:
			return
		h.name = "PortCrane%d" % i
		h.position = p
		h.rotation_degrees.y = yaws[i % yaws.size()]
		for lx: float in [-6.5, 6.5]:
			for lz: float in [-5.5, 5.5]:
				Geo.add_box_shape(body, p + Vector3(lx, 4.0, lz), Vector3(1.2, 8.0, 1.2))
		# Hindernisfeuer: Auslegerspitze (folgt der Animation) und Maschinenhaus
		var tip := _crane_tip(h)
		if tip != null:
			var mi := MeshInstance3D.new()
			mi.mesh = sm
			mi.material_override = red
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			tip.add_child(mi)
			mi.position = tip.get_meta("tip_local")
			mi.scale = Vector3.ONE / Models._rel(h, tip).basis.get_scale()
		var top := MeshInstance3D.new()
		top.mesh = sm
		top.material_override = red
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.add_child(top)
		top.position = Vector3(0, 32.7, 0)
	for lx: float in [-6.5, 6.5]:
		rb.add(Vector3(32.0 + lx, 0.04, -590.0), Vector3(0.14, 0.08, 440.0))
	world.add_child(Geo.mesh_node(rb.build(), rail, Vector3.ZERO, false))

## Mesh der Auslegerspitze (groesste Reichweite in +X oberhalb 20 m, im Halter-Raum);
## Meta tip_local = Spitze im lokalen Raum dieses Meshes.
static func _crane_tip(h: Node3D) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_x := -INF
	var best_p := Vector3.ZERO
	for m in h.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var xf := Models._rel(h, mi)
		var a := xf * mi.get_aabb()
		if a.end.y > 20.0 and a.end.x > best_x:
			best_x = a.end.x
			best = mi
			# Spitze: Punkt des Mesh-AABB mit max. x (lokal), oben
			var la := mi.get_aabb()
			var cand := la.get_center()
			var bx := -INF
			for k in 8:
				var c := la.get_endpoint(k)
				var w := xf * c
				if w.x > bx:
					bx = w.x
					cand = c
			best_p = cand
	if best != null:
		best.set_meta("tip_local", best_p)
	return best

# ------------------------------------------------------------------ Ferne Stadt

static func _build_skyline(lv: Node3D, rng: RandomNumberGenerator) -> void:
	var m := Geo.flat(Color(0.05, 0.05, 0.06), 0.9)
	var wm := Geo.flat(Color(1.0, 0.8, 0.5), 0.5, 0.0, Color(1.0, 0.8, 0.5), 2.0)
	var bb := Geo.batch()
	var wb := Geo.batch()
	for i in 70:
		var a := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(900.0, 1300.0)
		var c := Vector3(250.0 + cos(a) * r, 0.0, -500.0 + sin(a) * r)
		if c.x > 450.0 and c.z < -700.0:
			continue          # offene See im Nordosten
		var h := rng.randf_range(12.0, 60.0)
		var w := rng.randf_range(20.0, 60.0)
		bb.add(c + Vector3(0, h * 0.5, 0), Vector3(w, h, w))
		for k in 4:
			wb.add(c + Vector3(rng.randf_range(-w, w) * 0.4, rng.randf_range(4.0, h - 2.0), w * 0.51), Vector3(2.0, 1.4, 0.2))
	lv.add_child(Geo.mesh_node(bb.build(), m, Vector3.ZERO, false))
	lv.add_child(Geo.mesh_node(wb.build(), wm, Vector3.ZERO, false))
