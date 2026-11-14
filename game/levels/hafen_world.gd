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
const FarCity := preload("res://game/levels/far_city.gd")
const Night := preload("res://game/levels/hafen_night.gd")   ## glow_light(): runde Positions-/Hindernisfeuer
const ENV_TEX := "res://assets/environment/"

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
static var _tmats: Dictionary = {}
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

## PBR-Material aus assets/environment/<rel>/ (diffuse/normal/arm, Poly Haven CC0), Welt-Triplanar wie Geo.mat.
static func _tmat(rel: String, tint: Color, scale: float, rough_mul: float = 1.0, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [rel, tint.to_html(), scale, rough_mul, metallic]
	if _tmats.has(key):
		return _tmats[key]
	var d := ENV_TEX + rel + "/"
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(d + "diffuse.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(d + "normal.jpg")
	m.roughness_texture = load(d + "arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = rough_mul
	m.ao_enabled = true
	m.ao_texture = load(d + "arm.jpg")
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = metallic
	if metallic > 0.0:
		m.metallic_texture = load(d + "arm.jpg")
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_tmats[key] = m
	return m

# ------------------------------------------------------------------ Wasser

const WATER_SHADER := """
shader_type spatial;
uniform vec4 deep : source_color = vec4(0.024, 0.04, 0.052, 1.0);
uniform vec4 crest : source_color = vec4(0.07, 0.09, 0.1, 1.0);
uniform sampler2D n1 : hint_normal;
uniform sampler2D n2 : hint_normal;
uniform float amp = 0.17;
// Himmelsspiegelung nach Fresnel (flacher Blickwinkel -> heller Horizontschimmer, steil -> dunkles Wasser).
// Die Bootsnacht (hafen_night.gd) setzt sky_tint auf den Nachthorizont.
uniform vec4 sky_tint : source_color = vec4(0.2, 0.16, 0.14, 1.0);
uniform float fresnel_amt = 0.5;
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
	// grosse, langsame Duenung als dritte Lage: bricht Spiegelungen in lange, unruhige Bahnen
	vec3 s = texture(n1, uv * 0.012 + vec2(-TIME * 0.006, TIME * 0.009)).rgb;
	NORMAL_MAP = normalize(mix(mix(a, b, 0.5), s, 0.35) * 2.0 - 1.0) * 0.5 + 0.5;
	// Feine Normalen + sehr glatte Oberflaeche gaben unter Scheinwerfern grelle Einzel-Glitzerpunkte
	// ("Konfetti"): Normal-Detail flacher, Rauheit hoeher und mit der Entfernung steigend (gegen Aliasing),
	// Spekular auf Wasser-F0 (~0.02) -> weiche, breitere nasse Lichtbahnen statt Funkeln.
	float dist = length(VERTEX);
	NORMAL_MAP_DEPTH = mix(0.32, 0.16, smoothstep(15.0, 140.0, dist));
	ALBEDO = mix(deep.rgb, crest.rgb, clamp(hgt * 0.5 + 0.5, 0.0, 1.0) * 0.6);
	ROUGHNESS = mix(0.2, 0.3, smoothstep(10.0, 160.0, dist));
	METALLIC = 0.0;
	SPECULAR = 0.42;
	float nv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fr = 0.02 + 0.98 * pow(1.0 - nv, 5.0);
	// Wellenkaemme fangen mehr Himmel, Taeler weniger (gegen eine glatte, tote Flaeche)
	float crest_k = 0.75 + 0.5 * clamp(hgt * 0.5 + 0.5, 0.0, 1.0);
	EMISSION = sky_tint.rgb * fr * fresnel_amt * crest_k;
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
	# Ortbeton mit Schalungsstruktur, Kante aus Granitquadern (statt flachem Dunkelgrau)
	var wall := _tmat("river/textures/rough_concrete", Color(0.6, 0.6, 0.58), 0.3)
	var cope := _tmat("berlin/textures/large_sandstone_blocks", Color(0.6, 0.6, 0.62), 0.32, 0.85)
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
	_quay_wall_details(world, walls)
	# Kranschiene der Containerbruecken (landseitig) im Kai
	var rail := Geo.flat(Color(0.3, 0.29, 0.28), 0.45, 0.8)
	var rb := Geo.batch()
	rb.add(Vector3(37.0, 0.04, -125.0), Vector3(0.14, 0.08, 350.0))
	rb.add(Vector3(37.0, 0.005, -125.0), Vector3(0.7, 0.01, 350.0))
	world.add_child(Geo.mesh_node(rb.build(), rail, Vector3.ZERO, false))

## Kaimauer-Details: Dehnfugen, Reibepfaehle aus Holz, Autoreifen-Fender an Ketten, Entwaesserungsrohre mit
## Rostfahne, nasser Streifen ueber der Wasserlinie. Alles nur Optik (Kollision bleibt die Wand-/Landplatte).
static func _quay_wall_details(world: Node3D, walls: Array) -> void:
	var joint := Geo.flat(Color(0.05, 0.05, 0.05), 0.9)
	var timber := _tmat("textures/weathered_planks", Color(0.5, 0.42, 0.34), 0.7)
	var rubber := Geo.flat(Color(0.03, 0.03, 0.03), 0.75)
	var chain := Geo.flat(Color(0.25, 0.2, 0.16), 0.6, 0.8)
	var rust := Geo.flat(Color(0.2, 0.1, 0.05), 0.9)
	var wet := Geo.flat(Color(0.09, 0.09, 0.085), 0.25)
	var jb := Geo.batch()
	var tb := Geo.batch()
	var cb := Geo.batch()
	var rb := Geo.batch()
	var wb := Geo.batch()
	var tires: Array = []
	var pipes: Array = []
	var tire := TorusMesh.new()
	tire.inner_radius = 0.24
	tire.outer_radius = 0.46
	tire.rings = 14
	tire.ring_segments = 8
	var pipe := _cyl_mesh(0.16, 0.16, 0.5, 10)
	for w: Array in walls:
		var x: float = w[0]
		var sd: float = w[1]
		var face := x + sd * 0.4
		var z0: float = float(w[2]) + float(w[3]) * 0.5 - 3.0
		var z1: float = float(w[2]) - float(w[3]) * 0.5 + 3.0
		wb.add(Vector3(face + sd * 0.006, -1.25, float(w[2])), Vector3(0.012, 0.45, float(w[3])))
		var z := z0
		var i := 0
		while z > z1:
			# Dehnfuge alle 15 m
			if i % 5 == 0:
				jb.add(Vector3(face + sd * 0.01, -1.15, z), Vector3(0.03, 2.1, 0.05))
			# Reibepfahl alle 6 m
			if i % 2 == 1:
				tb.add(Vector3(face + sd * 0.16, -1.05, z), Vector3(0.3, 2.3, 0.3))
				tb.add(Vector3(face + sd * 0.16, 0.12, z), Vector3(0.34, 0.06, 0.34))
			# Reifenfender an Ketten alle 24 m
			if i % 8 == 4:
				tires.append(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(face + sd * 0.48, -0.95, z)))
				cb.add(Vector3(face + sd * 0.42, -0.28, z - 0.2), Vector3(0.03, 0.62, 0.03))
				cb.add(Vector3(face + sd * 0.42, -0.28, z + 0.2), Vector3(0.03, 0.62, 0.03))
			# Entwaesserungsrohr mit Rostfahne alle 36 m
			if i % 12 == 7:
				pipes.append(Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(face + sd * 0.12, -0.75, z)))
				rb.add(Vector3(face + sd * 0.008, -1.25, z), Vector3(0.012, 0.85, 0.32))
			z -= 3.0
			i += 1
	world.add_child(Geo.mesh_node(jb.build(), joint, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(tb.build(), timber, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(cb.build(), chain, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(rb.build(), rust, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(wb.build(), wet, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(_mesh_batch(tire, tires), rubber, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(_mesh_batch(pipe, pipes), rubber, Vector3.ZERO, false))

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
	# Hindernisfeuer: kleine Kugelleuchte + runder Lichtpunkt (vorher leuchtende Wuerfel -> Glow-Quadrate)
	var red := Geo.flat(Color(1, 0.1, 0.05), 0.4, 0.0, Color(1, 0.1, 0.05), 3.0)
	var lamps: Array[Vector3] = [apex + Vector3(0.0, 1.3, 0.0), Vector3(20.0, by + 1.4, z)]
	lamps.append(Vector3(xw, by, z) + d * 50.0 if boom_up else Vector3(100.0, by + 1.2, z))
	for lp: Vector3 in lamps:
		world.add_child(Geo.mesh_node(_nav_sphere(0.16), red, lp, false))
		Night.glow_light(world, lp, Color(1.0, 0.1, 0.05), 4.0, 0.6)

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
	# Lagerhallen am Ostufer (Ziel-Kulisse fuer die Kai-Schuetzen). Kollision wie bisher (Kasten 50 x 12 x 60),
	# Optik aus far_city: Backstein mit Sprossenfensterband, Gesims, Satteldach; dazu Tore/Tueren zum Wasser.
	var fb := FarCity.Builder.new()
	var hall_i := 0
	var z := -280.0
	while z > -900.0:
		var body := Geo.static_body(Vector3(175.0, 6.0, z))
		Geo.add_box_shape(body, Vector3.ZERO, Vector3(50.0, 12.0, 60.0))
		world.add_child(body)
		fb.block(Vector3(175.0, 0.0, z), Vector3(50.0, 12.0, 60.0), "hall", "brick_old" if hall_i % 3 != 1 else "factory",
			Color(0.8, 0.7, 0.62), {"seed": fposmod(float(hall_i) * 0.381 + 0.2, 1.0), "damage": 0.12, "lit": 0.9,
			"roof": "gable", "roof_h": 5.5, "roof_col": Color(0.34, 0.33, 0.33), "trim_tex": "concrete_old", "cornice": true})
		_hall_front(world, z, hall_i)
		hall_i += 1
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.75, 0.45)
		lamp.light_energy = 2.0
		lamp.omni_range = 16.0
		lamp.position = Vector3(149.0, 8.0, z)
		world.add_child(lamp)
		z -= 80.0
	FarCity.build(fb, world, true, {"lit_ratio": 0.16, "emission_energy": 1.8, "sky_tint": Color(0.13, 0.14, 0.19), "reflect_amt": 0.16}, "Lagerhallen")
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

## Wasserseite einer Lagerhalle (Wand x = 150): drei Rolltore mit Stahlzarge (eins je Halle offen, Licht
## dahinter), Schlupftuer, Leuchte ueber dem Mitteltor (OmniLight aus _build_quay), Fallrohre, Sockel, Nummer.
static func _hall_front(world: Node3D, z: float, n: int) -> void:
	var fx := 150.0
	var gate := _tmat("rail/textures/rusty_corrugated_iron", Color(0.55, 0.6, 0.62), 0.5, 1.0, 0.3)
	var steel := _tmat("rail/textures/rusty_painted_metal", Color(0.35, 0.38, 0.4), 0.5, 0.9, 0.4)
	var conc := _tmat("river/textures/rough_concrete", Color(0.55, 0.55, 0.53), 0.4)
	var lens := Geo.flat(Color(1.0, 0.8, 0.55), 0.4, 0.0, Color(1.0, 0.75, 0.45), 5.0)
	var inner := Geo.flat(Color(0.02, 0.018, 0.015), 0.9, 0.0, Color(1.0, 0.68, 0.38), 0.45)
	var gb := Geo.batch()
	var sb := Geo.batch()
	var cb := Geo.batch()
	var ib := Geo.batch()
	for k in 3:
		var gz := z + (float(k) - 1.0) * 18.0
		if (n + k) % 3 == 2:
			# hochgefahrenes Tor: Torpaket oben, dahinter die schwach beleuchtete Halle
			gb.add(Vector3(fx - 0.12, 4.75, gz), Vector3(0.22, 0.9, 6.0))
			ib.add(Vector3(fx - 0.01, 2.15, gz), Vector3(0.02, 4.3, 5.9))
		else:
			gb.add(Vector3(fx - 0.06, 2.6, gz), Vector3(0.1, 5.2, 6.0))
		sb.add(Vector3(fx - 0.15, 2.65, gz - 3.15), Vector3(0.3, 5.3, 0.3))
		sb.add(Vector3(fx - 0.15, 2.65, gz + 3.15), Vector3(0.3, 5.3, 0.3))
		sb.add(Vector3(fx - 0.18, 5.45, gz), Vector3(0.36, 0.5, 6.6))
		cb.add(Vector3(fx - 0.6, 0.06, gz), Vector3(1.2, 0.12, 6.4))
	# Schlupftuer, Fallrohre, Sockel
	sb.add(Vector3(fx - 0.05, 1.1, z + 9.0), Vector3(0.08, 2.2, 1.1))
	sb.add(Vector3(fx - 0.08, 2.3, z + 9.0), Vector3(0.14, 0.12, 1.3))
	for dz: float in [-29.6, 29.6]:
		sb.add(Vector3(fx - 0.14, 6.2, z + dz), Vector3(0.14, 12.4, 0.14))
	cb.add(Vector3(fx - 0.05, 0.45, z), Vector3(0.12, 0.9, 60.2))
	world.add_child(Geo.mesh_node(gb.build(), gate, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(sb.build(), steel, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(cb.build(), conc, Vector3.ZERO, false))
	if ib.count > 0:
		world.add_child(Geo.mesh_node(ib.build(), inner, Vector3.ZERO, false))
	# Leuchte ueber dem Mitteltor (die OmniLight sitzt bei x 149, y 8)
	world.add_child(Geo.box_mesh_node(Vector3(1.0, 0.1, 0.1), steel, Vector3(fx - 0.5, 8.45, z)))
	world.add_child(Geo.box_mesh_node(Vector3(0.45, 0.22, 0.36), steel, Vector3(fx - 1.0, 8.3, z)))
	var lm := Geo.box_mesh_node(Vector3(0.38, 0.03, 0.3), lens, Vector3(fx - 1.0, 8.18, z))
	lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(lm)
	var lbl := Label3D.new()
	lbl.text = "SCHUPPEN %d" % (12 + n)
	lbl.font_size = 160
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.85, 0.82, 0.74, 0.9)
	lbl.outline_size = 0
	lbl.shaded = true
	lbl.double_sided = false
	lbl.position = Vector3(fx - 0.05, 9.6, z)
	lbl.rotation_degrees = Vector3(0, -90, 0)
	world.add_child(lbl)

# ------------------------------------------------------------------ Bruecke

## Hubbruecke: Fahrbahnplatte und Pfeiler wie bisher als Kollision (Masse unveraendert); Optik:
##   Pfeiler aus Stampfbeton mit Betonierfugen, Granitsockel mit Vorkoepfen (Eisbrecher), Reibhoelzer zur
##   Fahrrinne, Auflagerbank mit Lagern; darunter genietete Vollwandtraeger (Stegbleche mit Aussteifungen
##   und Laschen), Quertraeger und Windverband; Hubtuerme als Fachwerk mit Seilscheiben und Gegengewichten.
static func _build_bridge(world: Node3D) -> void:
	var conc := _tmat("river/textures/rough_concrete", Color(0.66, 0.65, 0.63), 0.16)
	var deck_m := _tmat("river/textures/rough_concrete", Color(0.55, 0.55, 0.54), 0.14)
	var deck_c := Vector3(90.0, BRIDGE_DECK_Y - 0.6, BRIDGE_Z)
	var b := Geo.solid_box(world, deck_c, Vector3(260.0, 1.2, 14.0), deck_m)
	b.set_meta("surface", "concrete")
	for x in [62.0, 118.0]:
		var p := Geo.solid_box(world, Vector3(x, (BRIDGE_DECK_Y - 1.2 + WATER_Y - 6.0) * 0.5, BRIDGE_Z), Vector3(4.0, BRIDGE_DECK_Y - 1.2 - WATER_Y + 6.0, 10.0), conc)
		p.set_meta("surface", "concrete")
	# Rampen auf beide Ufer (Optik)
	world.add_child(Geo.box_mesh_node(Vector3(80.0, 1.2, 14.0), deck_m, Vector3(-20.0, BRIDGE_DECK_Y * 0.5 - 0.6, BRIDGE_Z), Vector3(0, 0, -12.5)))
	world.add_child(Geo.box_mesh_node(Vector3(80.0, 1.2, 14.0), deck_m, Vector3(200.0, BRIDGE_DECK_Y * 0.5 - 0.6, BRIDGE_Z), Vector3(0, 0, 12.5)))
	var steel := _tmat("rail/textures/rusty_painted_metal", Color(0.44, 0.52, 0.5), 0.35, 0.9, 0.45)
	_bridge_piers(world)
	# Traeger: lackierter Stahl mit Blechstoessen (Poly Haven "Blue Metal Plate", entsaettigt) statt der dunklen
	# Rostfarbe - liest sich nachts als Stahlbau statt als flache Platte; darunter das Fachwerk der Hubspanne
	var girder := _tmat("bunker/textures/painted_steel", Color(0.5, 0.58, 0.56), 0.3, 0.8, 0.35)
	_bridge_girders(world, girder)
	_lift_span_truss(world, girder)
	# Gelaender (ohne Kollision)
	var rb := Geo.batch()
	for side in [-1.0, 1.0]:
		rb.add(Vector3(90.0, BRIDGE_DECK_Y + 1.0, BRIDGE_Z + side * 6.8), Vector3(130.0, 0.1, 0.1))
		rb.add(Vector3(90.0, BRIDGE_DECK_Y + 0.5, BRIDGE_Z + side * 6.8), Vector3(130.0, 0.05, 0.05))
		var x := 26.0
		while x <= 154.0:
			rb.add(Vector3(x, BRIDGE_DECK_Y + 0.5, BRIDGE_Z + side * 6.8), Vector3(0.08, 1.0, 0.08))
			x += 2.5
	world.add_child(Geo.mesh_node(rb.build(), steel, Vector3.ZERO))
	_lift_towers(world, steel)
	for x in [40.0, 90.0, 140.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.light_energy = 2.5
		l.omni_range = 18.0
		l.position = Vector3(x, BRIDGE_DECK_Y + 5.0, BRIDGE_Z)
		world.add_child(l)
	# Durchfahrtsfeuer (rot backbord / gruen steuerbord): Kugelleuchte + runder Lichtpunkt statt Wuerfel
	for nav: Array in [[Vector3(64.5, BRIDGE_DECK_Y - 2.0, BRIDGE_Z + 7.2), Color(1, 0.1, 0.05)],
			[Vector3(115.5, BRIDGE_DECK_Y - 2.0, BRIDGE_Z + 7.2), Color(0.1, 1, 0.25)]]:
		var nc: Color = nav[1]
		world.add_child(Geo.mesh_node(_nav_sphere(0.17), Geo.flat(nc, 0.4, 0.0, nc, 3.0), nav[0], false))
		Night.glow_light(world, nav[0], nc, 4.5, 0.6)

static func _bridge_piers(world: Node3D) -> void:
	var granite := _tmat("berlin/textures/large_sandstone_blocks", Color(0.52, 0.52, 0.55), 0.24, 0.8)
	var conc := _tmat("river/textures/rough_concrete", Color(0.72, 0.71, 0.68), 0.2)
	var timber := _tmat("textures/weathered_planks", Color(0.45, 0.38, 0.31), 0.6)
	var bearing := _tmat("rail/textures/rusty_painted_metal", Color(0.3, 0.32, 0.32), 0.6, 0.9, 0.5)
	var joint := Geo.flat(Color(0.12, 0.12, 0.12), 0.9)
	var algae := Geo.flat(Color(0.035, 0.05, 0.04), 0.3)
	var lamp_m := Geo.flat(Color(1.0, 0.8, 0.55), 0.4, 0.0, Color(1.0, 0.7, 0.42), 5.0)
	var gb := Geo.batch()
	var cb := Geo.batch()
	var tb := Geo.batch()
	var bb := Geo.batch()
	var jb := Geo.batch()
	var ab := Geo.batch()
	var r45 := Basis(Vector3.UP, PI * 0.25)
	for px: float in [62.0, 118.0]:
		var ch := 1.0 if px < 90.0 else -1.0     # Richtung Fahrrinne
		# Granitsockel mit Vorkoepfen an beiden Enden (bis 3 m ueber Wasser)
		gb.add(Vector3(px, 0.3, BRIDGE_Z), Vector3(4.3, 5.6, 10.1))
		gb.add(Vector3(px, 3.2, BRIDGE_Z), Vector3(4.6, 0.35, 10.4))
		for s: float in [-1.0, 1.0]:
			gb.add(Vector3(px, 0.3, BRIDGE_Z + s * 5.05), Vector3(3.04, 5.6, 3.04), r45)
			gb.add(Vector3(px, 3.2, BRIDGE_Z + s * 5.05), Vector3(3.25, 0.35, 3.25), r45)
			ab.add(Vector3(px, -1.75, BRIDGE_Z + s * 5.05), Vector3(3.1, 0.5, 3.1), r45)
		ab.add(Vector3(px, -1.75, BRIDGE_Z), Vector3(4.36, 0.5, 10.16))
		# Betonierfugen am Schaft
		var y := 4.6
		while y < 14.0:
			jb.add(Vector3(px, y, BRIDGE_Z), Vector3(4.04, 0.05, 10.04))
			y += 1.6
		# Auflagerbank mit Lagern unter den Traegern
		cb.add(Vector3(px, 14.45, BRIDGE_Z), Vector3(4.8, 0.7, 10.8))
		for gz: float in [-6.0, -2.0, 2.0, 6.0]:
			bb.add(Vector3(px, 15.0, BRIDGE_Z + gz), Vector3(0.9, 0.4, 0.7))
		# Reibhoelzer zur Fahrrinne (senkrechte Pfaehle + zwei Gurte)
		var fz := -4.2
		while fz <= 4.21:
			tb.add(Vector3(px + ch * 2.32, 0.4, BRIDGE_Z + fz), Vector3(0.3, 6.2, 0.3))
			fz += 1.4
		for wy: float in [0.4, 2.5]:
			tb.add(Vector3(px + ch * 2.55, wy, BRIDGE_Z), Vector3(0.22, 0.3, 9.4))
		# Leuchte unter der Fahrbahn: beleuchtet Pfeilerkopf, Traeger und die Durchfahrt
		var lp := Vector3(px + ch * 5.5, 14.7, BRIDGE_Z + 2.0)
		var lm := Geo.box_mesh_node(Vector3(0.5, 0.08, 0.3), lamp_m, lp)
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(lm)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.72, 0.42)
		l.light_energy = 1.6
		l.omni_range = 12.0
		l.omni_attenuation = 1.4
		l.light_volumetric_fog_energy = 0.3
		l.position = lp - Vector3(0, 0.4, 0)
		world.add_child(l)
	world.add_child(Geo.mesh_node(gb.build(), granite, Vector3.ZERO))
	world.add_child(Geo.mesh_node(cb.build(), conc, Vector3.ZERO))
	world.add_child(Geo.mesh_node(tb.build(), timber, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(bb.build(), bearing, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(jb.build(), joint, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(ab.build(), algae, Vector3.ZERO, false))

## Genietete Vollwandtraeger unter der Fahrbahnplatte (Unterkante 16,8): vier Laengstraeger mit Gurten,
## Aussteifungen und Stosslaschen (Nietbild als Andeutung), Quertraeger und Windverband in der Untersicht.
static func _bridge_girders(world: Node3D, steel: Material) -> void:
	var gb := Geo.batch()
	var rv := Geo.batch()
	var top := BRIDGE_DECK_Y - 1.2
	var web_h := 1.5
	var yc := top - web_h * 0.5
	var x0 := -38.0
	var x1 := 218.0
	var L := x1 - x0
	var xm := (x0 + x1) * 0.5
	for gz: float in [-6.0, -2.0, 2.0, 6.0]:
		var z := BRIDGE_Z + gz
		gb.add(Vector3(xm, yc, z), Vector3(L, web_h, 0.04))
		gb.add(Vector3(xm, top - web_h + 0.03, z), Vector3(L, 0.06, 0.55))
		gb.add(Vector3(xm, top - 0.03, z), Vector3(L, 0.06, 0.55))
		if absf(gz) > 4.0:
			var out := signf(gz)
			# Aussteifungen alle 1,6 m, Laschen an den Stoessen alle 12,8 m, Nietreihen an den Gurten
			var x := x0 + 0.8
			var i := 0
			while x < x1:
				if i % 8 == 0:
					gb.add(Vector3(x, yc, z + out * 0.04), Vector3(0.7, web_h - 0.1, 0.03))
					for k in 5:
						rv.add(Vector3(x - 0.24, yc - 0.56 + k * 0.28, z + out * 0.06), Vector3(0.05, 0.05, 0.03))
						rv.add(Vector3(x + 0.24, yc - 0.56 + k * 0.28, z + out * 0.06), Vector3(0.05, 0.05, 0.03))
				else:
					gb.add(Vector3(x, yc, z + out * 0.08), Vector3(0.1, web_h - 0.12, 0.13))
				rv.add(Vector3(x, top - web_h + 0.1, z + out * 0.04), Vector3(0.6, 0.045, 0.02))
				rv.add(Vector3(x, top - 0.1, z + out * 0.04), Vector3(0.6, 0.045, 0.02))
				x += 1.6
				i += 1
	# Quertraeger alle 4,8 m, dazwischen Windverband (Diagonalen in der Untersicht)
	var cx := x0 + 2.4
	var j := 0
	while cx < x1:
		gb.add(Vector3(cx, top - 0.5, BRIDGE_Z), Vector3(0.28, 1.0, 12.0))
		if j % 2 == 0 and cx + 9.6 < x1:
			_strut(gb, Vector3(cx, top - web_h + 0.08, BRIDGE_Z - 5.9), Vector3(cx + 9.6, top - web_h + 0.08, BRIDGE_Z + 5.9), 0.14, 0.1)
			_strut(gb, Vector3(cx, top - web_h + 0.08, BRIDGE_Z + 5.9), Vector3(cx + 9.6, top - web_h + 0.08, BRIDGE_Z - 5.9), 0.14, 0.1)
		cx += 4.8
		j += 1
	world.add_child(Geo.mesh_node(gb.build(), steel, Vector3.ZERO))
	world.add_child(Geo.mesh_node(rv.build(), steel, Vector3.ZERO, false))

## Hubspanne (zwischen den Pfeilern, x 64,6..115,4): unter die beiden aeusseren Vollwandtraeger gehaengtes,
## genietetes Fachwerk (Strebenfachwerk mit Pfosten, 8 Felder, 3,2 m hoch) aus Kastenprofilen mit
## Knotenblechen und Nietbild, Querriegel/Windverband im Untergurt, Arbeitsleuchten unter dem Untergurt.
## Reine Optik (keine Kollision; Durchfahrtshoehe bleibt > 12 m).
static func _lift_span_truss(world: Node3D, steel: Material) -> void:
	var tb := Geo.batch()
	var gp := Geo.batch()
	var rv := Geo.batch()
	var xa := 64.9
	var xb := 115.1
	var n := 8
	var pw := (xb - xa) / float(n)
	var yt := BRIDGE_DECK_Y - 1.2 - 1.5      # Unterkante Vollwandtraeger = Obergurt
	var yb := yt - 3.2
	for gz: float in [-6.0, 6.0]:
		var z := BRIDGE_Z + gz
		var out := signf(gz)
		# Ober-/Untergurt (Kastenprofil 0,5 x 0,42) mit Gurtplatte
		tb.add(Vector3((xa + xb) * 0.5, yt - 0.21, z), Vector3(xb - xa, 0.42, 0.5))
		tb.add(Vector3((xa + xb) * 0.5, yb, z), Vector3(xb - xa, 0.46, 0.52))
		tb.add(Vector3((xa + xb) * 0.5, yb - 0.25, z), Vector3(xb - xa, 0.04, 0.62))
		for i in n + 1:
			var x := xa + pw * i
			# Pfosten
			tb.add(Vector3(x, (yt + yb) * 0.5, z), Vector3(0.3, yt - yb, 0.36))
			# Knotenbleche oben/unten (aussen und innen) mit Nietbild 3 x 3
			for ny: float in [yt - 0.35, yb + 0.1]:
				for side: float in [-1.0, 1.0]:
					gp.add(Vector3(x, ny, z + side * 0.29), Vector3(1.15, 0.95, 0.03))
				for ix in 3:
					for iy in 3:
						rv.add_ball(Vector3(x - 0.36 + ix * 0.36, ny - 0.3 + iy * 0.3, z + out * 0.32), Vector3(0.07, 0.07, 0.05))
			if i < n:
				# Diagonale (fallend zur Feldmitte hin: Strebenfachwerk symmetrisch zur Spannmitte)
				var a := Vector3(x, yt - 0.3, z)
				var b := Vector3(x + pw, yb + 0.2, z)
				if i * 2 >= n:
					a = Vector3(x, yb + 0.2, z)
					b = Vector3(x + pw, yt - 0.3, z)
				_strut(tb, a, b, 0.32, 0.3)
				# Bindebleche auf der Diagonale (Gitterstab-Andeutung)
				for k in [0.3, 0.5, 0.7]:
					var c := a.lerp(b, k)
					rv.add(c + Vector3(0, 0, out * 0.16), Vector3(0.42, 0.42, 0.02))
	# Querriegel und Windverband im Untergurt
	for i in n + 1:
		var x := xa + pw * i
		tb.add(Vector3(x, yb, BRIDGE_Z), Vector3(0.26, 0.3, 12.0))
		if i < n:
			_strut(tb, Vector3(x, yb + 0.05, BRIDGE_Z - 5.8), Vector3(x + pw, yb + 0.05, BRIDGE_Z + 5.8), 0.14, 0.1)
			_strut(tb, Vector3(x, yb + 0.05, BRIDGE_Z + 5.8), Vector3(x + pw, yb + 0.05, BRIDGE_Z - 5.8), 0.14, 0.1)
	world.add_child(Geo.mesh_node(tb.build(), steel, Vector3.ZERO))
	world.add_child(Geo.mesh_node(gp.build(), steel, Vector3.ZERO, false))
	world.add_child(Geo.mesh_node(rv.build(), steel, Vector3.ZERO, false))
	# Arbeitsleuchten unter dem Untergurt (Fahrrinnenseite Sued = Anfahrt): machen das Fachwerk nachts lesbar
	var lamp_m := Geo.flat(Color(1.0, 0.85, 0.6), 0.4, 0.0, Color(1.0, 0.78, 0.5), 4.0)
	for lx: float in [77.5, 102.5]:
		for gz2: float in [6.9, -6.9]:
			var lp := Vector3(lx, yb - 0.35, BRIDGE_Z + gz2)
			var lm := Geo.box_mesh_node(Vector3(0.6, 0.12, 0.3), lamp_m, lp)
			lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world.add_child(lm)
			if gz2 > 0.0:
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.8, 0.55)
				l.light_energy = 2.4
				l.omni_range = 9.0
				l.omni_attenuation = 1.2
				l.light_volumetric_fog_energy = 0.25
				l.position = lp + Vector3(0, -0.3, 1.6)
				world.add_child(l)

## Hubtuerme ueber den Pfeilern: je zwei Fachwerkstiele (Eckwinkel, Riegel, Kreuzverband), oben ein
## Fachwerkriegel mit Maschinenhaus, Seilscheiben, Gegengewichte und Seile. Gleiche Grundflaeche wie frueher.
static func _lift_towers(world: Node3D, steel: Material) -> void:
	var tb := Geo.batch()
	var dark := _tmat("rail/textures/rusty_painted_metal", Color(0.24, 0.26, 0.26), 0.5, 0.9, 0.5)
	var weight := _tmat("river/textures/rough_concrete", Color(0.5, 0.5, 0.49), 0.4)
	var hut := _tmat("rail/textures/rusty_corrugated_iron", Color(0.45, 0.5, 0.5), 0.6, 1.0, 0.3)
	var y0 := BRIDGE_DECK_Y
	var y1 := BRIDGE_DECK_Y + 24.0
	var e := 0.85
	for x: float in [62.0, 118.0]:
		for side: float in [-1.0, 1.0]:
			var c := Vector3(x, 0.0, BRIDGE_Z + side * 5.5)
			var corners: Array[Vector3] = [Vector3(-e, 0, -e), Vector3(e, 0, -e), Vector3(e, 0, e), Vector3(-e, 0, e)]
			for k in 4:
				tb.add(c + corners[k] + Vector3(0, (y0 + y1) * 0.5, 0), Vector3(0.26, y1 - y0, 0.26))
			var y := y0
			while y < y1 - 0.1:
				var yn := minf(y + 3.0, y1)
				for k in 4:
					var a: Vector3 = c + corners[k]
					var bq: Vector3 = c + corners[(k + 1) % 4]
					tb.add((a + bq) * 0.5 + Vector3(0, yn, 0), (Vector3(absf(bq.x - a.x), 0, absf(bq.z - a.z)) + Vector3(0.14, 0.14, 0.14)))
					_strut(tb, a + Vector3(0, y, 0), bq + Vector3(0, yn, 0), 0.09)
					_strut(tb, bq + Vector3(0, y, 0), a + Vector3(0, yn, 0), 0.09)
				y = yn
			# Gegengewicht im Turm, Seilscheibe oben, Seile
			world.add_child(Geo.box_mesh_node(Vector3(1.1, 3.6, 1.1), weight, c + Vector3(0, y1 - 7.0, 0)))
			world.add_child(Geo.cylinder_node(1.25, 0.3, dark, c + Vector3(0, y1 + 1.4, 0), Vector3(0, 0, 90), 18))
			for dz: float in [-0.25, 0.25]:
				tb.add(c + Vector3(-0.6, y1 - 2.0, dz), Vector3(0.04, 4.6, 0.04))
				tb.add(c + Vector3(0.6, (y0 + y1 + 1.4) * 0.5, dz), Vector3(0.04, y1 + 1.4 - y0, 0.04))
		# Fachwerkriegel oben (laengs z zwischen den Stielen) und Maschinenhaus
		for yy: float in [y1, y1 + 2.2]:
			for dx: float in [-e, e]:
				tb.add(Vector3(x + dx, yy, BRIDGE_Z), Vector3(0.28, 0.3, 13.0))
		var zz := -5.5
		while zz < 5.4:
			for dx: float in [-e, e]:
				tb.add(Vector3(x + dx, y1 + 1.1, BRIDGE_Z + zz), Vector3(0.14, 2.2, 0.14))
				_strut(tb, Vector3(x + dx, y1, BRIDGE_Z + zz), Vector3(x + dx, y1 + 2.2, BRIDGE_Z + zz + 1.375), 0.1)
			zz += 1.375
		world.add_child(Geo.box_mesh_node(Vector3(2.6, 2.4, 4.4), hut, Vector3(x, y1 + 3.5, BRIDGE_Z)))
		world.add_child(Geo.box_mesh_node(Vector3(3.0, 0.15, 4.8), dark, Vector3(x, y1 + 4.75, BRIDGE_Z)))
	world.add_child(Geo.mesh_node(tb.build(), steel, Vector3.ZERO))

# ------------------------------------------------------------------ Muendung, Molen, Leuchtturm

static func _build_mouth(world: Node3D) -> void:
	var stone := Geo.mat("concrete_wall_008", Color(0.4, 0.4, 0.42), 0.15)
	# Westmole entlang z -1150, Ostmole x 420 von z -930 bis -1005
	var w := Geo.solid_box(world, Vector3(175.0, -0.5, -1155.0), Vector3(270.0, 5.0, 10.0), stone)
	w.set_meta("surface", "concrete")
	var e := Geo.solid_box(world, Vector3(425.0, -0.5, -967.0), Vector3(10.0, 5.0, 74.0), stone)
	e.set_meta("surface", "concrete")
	# Leuchttuerme an den Molenkoepfen (Molenoberkante y 2): West weiss mit rotem Band, Ost rot mit weissen Baendern
	var white := _tmat("facade/textures/painted_plaster_wall", Color(0.9, 0.9, 0.87), 0.35)
	var redm := _tmat("facade/textures/painted_plaster_wall", Color(0.62, 0.12, 0.09), 0.35)
	_lighthouse(world, Vector3(305.0, 2.0, -1155.0), 18.0, 2.2, white, redm, [0.62], Color(1.0, 0.95, 0.8))
	_lighthouse(world, Vector3(425.0, 2.0, -1000.0), 14.0, 1.8, redm, white, [0.3, 0.62], Color(1.0, 0.3, 0.2))
	# Fahrwassertonnen
	# Fahrwassertonnen: rot lackierter Schwimmkoerper (nicht selbstleuchtend) mit Toppzeichen und kleinem
	# Feuer obenauf - vorher leuchtete der ganze Zylinder und wirkte in der Ferne als rotes Quadrat
	var buoy := Geo.mat("rusty_metal_02", Color(0.72, 0.2, 0.15), 0.5, 1.0, 0.3)
	var lamp_m := Geo.flat(Color(1, 0.12, 0.08), 0.4, 0.0, Color(1, 0.12, 0.08), 3.0)
	for p: Vector3 in [Vector3(110.0, -1.4, -880.0), Vector3(170.0, -1.4, -950.0), Vector3(260.0, -1.4, -1000.0), Vector3(370.0, -1.4, -1020.0)]:
		world.add_child(Geo.cylinder_node(0.6, 1.6, buoy, p))
		world.add_child(Geo.cylinder_node(0.2, 1.1, buoy, p + Vector3(0, 1.35, 0)))
		var lp := p + Vector3(0, 2.0, 0)
		world.add_child(Geo.mesh_node(_nav_sphere(0.12), lamp_m, lp, false))
		Night.glow_light(world, lp, Color(1.0, 0.12, 0.08), 3.5, 0.4)

## Molenfeuer: Betonsockel, verjuengter Turm (Putz, mit Farbbaendern an den Hoehenanteilen bands), Tuer und
## Fenster, Galerie mit Gelaender, verglaste Laterne mit leuchtendem Feuer, Kupferhaube mit Lueftungskugel.
## Gleiche Hoehe/Grundflaeche wie die frueheren Zylinder; das Licht sitzt 1 m ueber dem Turmschaft.
static func _lighthouse(world: Node3D, base: Vector3, h: float, r: float, body: Material, band: Material,
		bands: Array, light_col: Color) -> void:
	var conc := _tmat("river/textures/rough_concrete", Color(0.6, 0.6, 0.58), 0.3)
	var metal := _tmat("rail/textures/rusty_painted_metal", Color(0.2, 0.22, 0.22), 0.8, 0.9, 0.5)
	var roof := _tmat("rail/textures/rusty_painted_metal", Color(0.42, 0.14, 0.1), 0.8, 0.8, 0.5)
	var dark := Geo.flat(Color(0.05, 0.05, 0.06), 0.6)
	var r_top := r * 0.74
	# Sockel
	var plinth := MeshInstance3D.new()
	plinth.mesh = _cyl_mesh(r + 0.5, r + 0.7, 1.2, 20)
	plinth.material_override = conc
	plinth.position = base + Vector3(0, 0.6, 0)
	world.add_child(plinth)
	# Schaft in Abschnitten (Baender als eigene Ringe, Radius entlang der Hoehe interpoliert)
	var y0 := base.y + 1.2
	var hs := h - 1.2
	var cuts: Array[float] = [0.0]
	for b: float in bands:
		cuts.append(b)
		cuts.append(b + 0.12)
	cuts.append(1.0)
	for i in cuts.size() - 1:
		var f0: float = cuts[i]
		var f1: float = cuts[i + 1]
		var seg := MeshInstance3D.new()
		seg.mesh = _cyl_mesh(lerpf(r, r_top, f1), lerpf(r, r_top, f0), hs * (f1 - f0), 20)
		seg.material_override = band if i % 2 == 1 else body
		seg.position = Vector3(base.x, y0 + hs * (f0 + f1) * 0.5, base.z)
		world.add_child(seg)
	# Tuer (Seeseite +z) und kleine Fenster im Schaft
	world.add_child(Geo.box_mesh_node(Vector3(0.9, 2.0, 0.3), dark, Vector3(base.x, y0 + 1.0, base.z + r - 0.08)))
	world.add_child(Geo.box_mesh_node(Vector3(1.2, 0.12, 0.5), conc, Vector3(base.x, y0 + 2.1, base.z + r + 0.05)))
	for k in 3:
		var f := 0.3 + k * 0.22
		var rr := lerpf(r, r_top, f)
		var ang := PI * 0.5 + (k - 1) * 0.6
		var wpos := Vector3(base.x + cos(ang) * rr, y0 + hs * f, base.z + sin(ang) * rr)
		var wn := Geo.box_mesh_node(Vector3(0.45, 0.7, 0.2), dark, wpos)
		wn.rotation.y = -ang + PI * 0.5
		world.add_child(wn)
	# Galerie: Kragplatte, Konsolen, Gelaender (Pfosten + Handlauf)
	var gy := base.y + h
	var gal := MeshInstance3D.new()
	gal.mesh = _cyl_mesh(r_top + 0.85, r_top + 0.85, 0.22, 24)
	gal.material_override = metal
	gal.position = Vector3(base.x, gy, base.z)
	world.add_child(gal)
	var pb := Geo.batch()
	for k in 16:
		var a := TAU * k / 16.0
		var d := Vector3(cos(a), 0, sin(a))
		pb.add(Vector3(base.x, gy + 0.55, base.z) + d * (r_top + 0.78), Vector3(0.05, 1.0, 0.05))
		_strut(pb, Vector3(base.x, gy - 0.1, base.z) + d * (r_top + 0.75), Vector3(base.x, gy - 0.8, base.z) + d * (r_top - 0.02), 0.12, 0.08)
	world.add_child(Geo.mesh_node(pb.build(), metal, Vector3.ZERO, false))
	var rail := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = r_top + 0.75
	tor.outer_radius = r_top + 0.81
	tor.rings = 32
	tor.ring_segments = 6
	rail.mesh = tor
	rail.material_override = metal
	rail.position = Vector3(base.x, gy + 1.05, base.z)
	world.add_child(rail)
	# Laterne: Brustwand, Sprossen, Verglasung, Feuer, Haube, Lueftungskugel
	var lr := r_top * 0.72
	var wall := MeshInstance3D.new()
	wall.mesh = _cyl_mesh(lr, lr, 0.6, 16)
	wall.material_override = metal
	wall.position = Vector3(base.x, gy + 0.41, base.z)
	world.add_child(wall)
	var glass := MeshInstance3D.new()
	glass.mesh = _cyl_mesh(lr - 0.04, lr - 0.04, 1.5, 16)
	glass.material_override = VF.glass_mat(Color(0.5, 0.55, 0.5, 0.25))
	glass.position = Vector3(base.x, gy + 1.46, base.z)
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(glass)
	var mb := Geo.batch()
	for k in 8:
		var a2 := TAU * k / 8.0
		mb.add(Vector3(base.x + cos(a2) * lr, gy + 1.46, base.z + sin(a2) * lr), Vector3(0.07, 1.5, 0.07))
	world.add_child(Geo.mesh_node(mb.build(), metal, Vector3.ZERO, false))
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.38
	sm.height = 0.9
	lamp.mesh = sm
	lamp.material_override = Geo.flat(light_col, 0.3, 0.0, light_col, 7.0)
	lamp.position = Vector3(base.x, gy + 1.4, base.z)
	lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(lamp)
	var cap := MeshInstance3D.new()
	cap.mesh = _cyl_mesh(0.12, lr + 0.18, 0.9, 16)
	cap.material_override = roof
	cap.position = Vector3(base.x, gy + 2.66, base.z)
	world.add_child(cap)
	var ball := MeshInstance3D.new()
	var bs := SphereMesh.new()
	bs.radius = 0.2
	bs.height = 0.4
	ball.mesh = bs
	ball.material_override = roof
	ball.position = Vector3(base.x, gy + 3.2, base.z)
	world.add_child(ball)
	var l := OmniLight3D.new()
	l.light_color = light_col
	l.light_energy = 6.0
	l.omni_range = 40.0
	l.position = Vector3(base.x, gy + 1.4, base.z)
	world.add_child(l)
	# schwaches Anstrahllicht von der Galerie auf den Schaft (sonst nachts nur Silhouette)
	var fl := SpotLight3D.new()
	fl.light_color = Color(1.0, 0.9, 0.75)
	fl.light_energy = 3.0
	fl.spot_range = h + 2.0
	fl.spot_angle = 20.0
	fl.shadow_enabled = false
	fl.position = Vector3(base.x, gy - 0.3, base.z + r_top + 1.6)
	fl.rotation_degrees = Vector3(-84, 0, 0)
	world.add_child(fl)

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
		Night.glow_light(h, Vector3(0, 32.7, 0), Color(1.0, 0.1, 0.05), 3.5, 0.6)
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

## Kleine Kugel fuer Positions-/Hindernisfeuer (der Lichthof kommt aus Night.glow_light).
static func _nav_sphere(r: float) -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 5
	return sm
