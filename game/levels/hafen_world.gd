extends RefCounted
## Mission "Kräne": statischer Aufbau des Ueberseehafens (frei gestaltet, angelehnt an einen Ostseehafen).
## Koordinaten: -z = Norden (Fahrtrichtung). Wasserspiegel y = -2, Land-Oberkante y = 0.
##   Containerterminal (Teil A): Hauptgasse x -4..8 von z 50 bis -300, Quergassen z -100/-170/-235,
##   Portalkran (Kerners Stellung) quer ueber der Gasse bei z 61, Laufsteg y 30.
##   Hafenbecken x 41..140 (Teil B), Hubbruecke z -620, Muendung noerdlich z -930, Molen, Frachter "Aurelia".

const Geo = preload("res://game/levels/level_geo.gd")
const VF := preload("res://game/vehicles/vehicle_fx.gd")

const WATER_Y := -2.0
const CRANE_Z := 61.0
const CRANE_Y := 30.0
const KERNER_SPOT := Vector3(2.0, 30.05, 59.6)
const LENA_START := Vector3(2.0, 0.0, -20.0)
const HUT := Vector3(12.0, 0.0, -98.0)
const MARKSMAN := Vector3(-5.0, 16.0, -232.0)
const BERTH7 := Vector3(46.0, -2.0, -236.0)
const BRIDGE_Z := -620.0
const BRIDGE_DECK_Y := 18.0
const FREIGHTER := Vector3(600.0, -2.0, -1080.0)
const FREIGHTER_BOARD := Vector3(545.0, -2.0, -1066.0)
const LANES: Array[float] = [-100.0, -170.0, -235.0]
const BARRIERS: Array[Vector3] = [Vector3(-1.0, 0, -158.0), Vector3(5.0, 0, -162.0), Vector3(1.0, 0, -168.0),
	Vector3(5.6, 0, -112.0), Vector3(-2.0, 0, -205.0)]

const C_LEN := 12.2
const C_H := 2.6
const C_W := 2.44
const C_PITCH := 2.84

static var _corr_tex: Texture2D = null

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
	_build_mouth(world)
	out["freighter"] = _build_freighter(lv)
	_build_skyline(lv, rng)
	return out

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
	NORMAL_MAP_DEPTH = 0.75;
	ALBEDO = mix(deep.rgb, crest.rgb, clamp(hgt * 0.5 + 0.5, 0.0, 1.0) * 0.6);
	ROUGHNESS = 0.07;
	METALLIC = 0.0;
	SPECULAR = 0.6;
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

static func _build_land(world: Node3D) -> void:
	var asphalt := Geo.mat("asphalt_02", Color(0.55, 0.55, 0.58), 0.12, 0.6)
	var conc := Geo.mat("concrete_wall_008", Color(0.5, 0.5, 0.52), 0.15)
	# Terminalflaeche (west), feiner unterteilt, damit das Navmesh-Backen schlank bleibt
	_slab(world, -60.0, 41.0, -320.0, 120.0, asphalt)
	_slab(world, -300.0, -60.0, -320.0, 120.0, asphalt)
	_slab(world, -300.0, 41.0, -1150.0, -320.0, conc)
	# Ostufer mit Lagerhallen
	_slab(world, 140.0, 420.0, -930.0, 120.0, conc)
	# Beckenende im Sueden
	_slab(world, 41.0, 140.0, 80.0, 120.0, conc)
	# Kaimauern (dunkler Rand ueber dem Wasser)
	var wall := Geo.flat(Color(0.16, 0.16, 0.17), 0.9)
	var bb := Geo.batch()
	bb.add(Vector3(41.4, -1.0, -515.0), Vector3(0.8, 2.2, 1270.0))
	bb.add(Vector3(139.6, -1.0, -405.0), Vector3(0.8, 2.2, 1050.0))
	var mesh := bb.build()
	world.add_child(Geo.mesh_node(mesh, wall, Vector3.ZERO, false))
	# Fender/Poller an der Kante
	var pol := Geo.flat(Color(0.75, 0.6, 0.1), 0.7)
	var pb := Geo.batch()
	var z := 100.0
	while z > -1140.0:
		pb.add(Vector3(40.4, 0.35, z), Vector3(0.5, 0.7, 0.5))
		z -= 18.0
	z = 100.0
	while z > -920.0:
		pb.add(Vector3(140.6, 0.35, z), Vector3(0.5, 0.7, 0.5))
		z -= 18.0
	world.add_child(Geo.mesh_node(pb.build(), pol, Vector3.ZERO, false))
	# Fahrbahnmarkierung in der Hauptgasse
	var paint := Geo.flat(Color(0.75, 0.72, 0.6), 0.6)
	var mb := Geo.batch()
	z = 45.0
	while z > -300.0:
		mb.add(Vector3(2.0, 0.012, z), Vector3(0.18, 0.02, 3.0))
		z -= 7.0
	world.add_child(Geo.mesh_node(mb.build(), paint, Vector3.ZERO, false))

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
		Color(0.42, 0.42, 0.4), Color(0.55, 0.26, 0.06), Color(0.62, 0.6, 0.55), Color(0.3, 0.1, 0.22)]
	var batches: Array = []
	for c in cols:
		batches.append(Geo.batch())
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
						(batches[ci] as Geo.BoxBatch).add(Vector3(cx, C_H * 0.5 + lvl * C_H, z), Vector3(C_LEN, C_H - 0.04, C_W))
					Geo.add_box_shape(body, Vector3(cx, h * C_H * 0.5, z), Vector3(C_LEN, h * C_H, C_W))
				z -= C_PITCH
	for j in cols.size():
		var mesh: ArrayMesh = (batches[j] as Geo.BoxBatch).build()
		if mesh != null:
			world.add_child(Geo.mesh_node(mesh, _container_mat(cols[j]), Vector3.ZERO))
	# Betonsperren (Jersey) in der Gasse
	var conc := Geo.flat(Color(0.55, 0.54, 0.5), 0.9)
	for p in BARRIERS:
		var b := Geo.solid_box(world, p + Vector3(0, 0.45, 0), Vector3(3.2, 0.9, 0.6), conc)
		b.set_meta("surface", "concrete")
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
	# Hauptträger (Laufsteg) – begehbar
	var floor_c := Vector3(2.0, CRANE_Y - 0.2, CRANE_Z)
	bb.add(floor_c, Vector3(36.0, 0.4, 6.0))
	Geo.add_box_shape(body, floor_c, Vector3(36.0, 0.4, 6.0))
	bb.add(Vector3(2.0, CRANE_Y - 1.4, CRANE_Z - 2.6), Vector3(36.0, 2.0, 0.5))
	bb.add(Vector3(2.0, CRANE_Y - 1.4, CRANE_Z + 2.6), Vector3(36.0, 2.0, 0.5))
	# Laufkatze + Kabine (hinter Kerner, Sueden)
	bb.add(Vector3(-6.0, CRANE_Y + 1.4, CRANE_Z + 1.2), Vector3(5.0, 2.8, 3.0))
	Geo.add_box_shape(body, Vector3(-6.0, CRANE_Y + 1.4, CRANE_Z + 1.2), Vector3(5.0, 2.8, 3.0))
	world.add_child(Geo.mesh_node(bb.build(), steel, Vector3.ZERO))
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
	world.add_child(flood)
	var work := OmniLight3D.new()
	work.light_color = Color(1.0, 0.8, 0.55)
	work.light_energy = 0.9
	work.omni_range = 7.0
	work.position = Vector3(-3.0, CRANE_Y + 2.5, CRANE_Z + 1.0)
	world.add_child(work)
	if wind != null:
		wind.call("add_flag", world, Vector3(20.0, CRANE_Y + 3.2, CRANE_Z))
		world.add_child(Geo.box_mesh_node(Vector3(0.08, 3.2, 0.08), dark, Vector3(20.0, CRANE_Y + 1.6, CRANE_Z)))

# ------------------------------------------------------------------ Lichtmasten

static func _build_masts(world: Node3D, wind: Node) -> void:
	var pole := Geo.flat(Color(0.35, 0.36, 0.37), 0.6, 0.6)
	var lamp := Geo.flat(Color(1.0, 0.85, 0.6), 0.3, 0.0, Color(1.0, 0.8, 0.5), 8.0)
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
			sp.light_volumetric_fog_energy = 0.6
			sp.position = Vector3(x, 19.8, z)
			sp.rotation_degrees = Vector3(-90, 0, 0)
			world.add_child(sp)
			if wind != null and n % 3 == 0:
				wind.call("add_flag", world, Vector3(x, 21.2, z))
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
	world.add_child(Geo.mesh_node(pb.build(), pole, Vector3.ZERO))
	world.add_child(Geo.mesh_node(lb.build(), lamp, Vector3.ZERO, false))

# ------------------------------------------------------------------ Kai, Containerbruecken

static func _sts_crane(world: Node3D, z: float, m: Material, boom_up: bool) -> void:
	var bb := Geo.batch()
	for zz in [z - 8.0, z + 8.0]:
		bb.add(Vector3(37.0, 20.0, zz), Vector3(1.4, 40.0, 1.4))
		bb.add(Vector3(47.0, 20.0, zz), Vector3(1.4, 40.0, 1.4))
	bb.add(Vector3(42.0, 40.0, z), Vector3(12.0, 2.0, 18.0))
	bb.add(Vector3(42.0, 14.0, z), Vector3(12.0, 1.0, 17.0))
	if boom_up:
		bb.add(Vector3(55.0, 56.0, z), Vector3(30.0, 1.6, 2.0), Basis(Vector3.BACK, deg_to_rad(70.0)))
	else:
		bb.add(Vector3(70.0, 41.0, z), Vector3(56.0, 1.6, 2.0))
	bb.add(Vector3(30.0, 41.0, z), Vector3(18.0, 1.6, 2.0))
	bb.add(Vector3(26.0, 38.0, z), Vector3(5.0, 5.0, 5.0))
	world.add_child(Geo.mesh_node(bb.build(), m, Vector3.ZERO))
	var red := Geo.flat(Color(1, 0.1, 0.05), 0.4, 0.0, Color(1, 0.1, 0.05), 6.0)
	world.add_child(Geo.box_mesh_node(Vector3(0.4, 0.4, 0.4), red, Vector3(42.0, 41.4, z)))

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
	for zz in [-330.0, -370.0, -410.0, -470.0]:
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
	return root

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
