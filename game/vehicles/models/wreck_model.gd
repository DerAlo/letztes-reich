extends RefCounted
## Ausgebrannte Fahrzeugwracks (realistischere Ablösung der Profil-Extrusion aus car_model.gd):
##  - Pkw/Transporter/Bus/Lkw: Karosserie als Loft aus Querschnitten (Schweller, Tueren-Bauch, Guertellinie,
##    Motorhaube) mit ausgeschnittenen Radlaeufen und Radhaus-Schalen, beulig; Scheiben weggebrannt -> offene
##    Fensterflaechen mit duennen A/B/C-Saeulen und durchhaengendem Dach; Innenraum mit Sitzgestellen
##    (Federkerne ohne Polster), Armaturentraeger und Lenkradring; Stossfaenger weggeschmolzen -> Stahltraeger;
##    Reifen verbrannt -> Karosserie sitzt auf nackten Stahlfelgen mit Drahtkern-Resten.
##  - Panzerwrack: das Marder-1A3-Modell (Scout, CC-BY 4.0) verkohlt, Turm verdreht, Rohr haengt, Heckklappe offen.
##  - Material: burnt_vehicle.gdshader (Poly Haven rust_coarse_01 + rusty_metal_04, CC0), objektfest triplanar.
##  - Brandfleck: Decal aus Poly Haven burned_ground_01 mit Glaskruemeln (tools/gen_wreck_decal.py).
## Koordinaten: Front = +Z, Boden y = 0. Geometrie je Typ gecacht; pro Wrack 2 Draw-Calls (Karosserie,
## Detail mit Sichtweitenbegrenzung) + Decal.

const SHADER := "res://assets/vehicles/wrecks/burnt_vehicle.gdshader"
const TEX := "res://assets/vehicles/wrecks/textures/"
const NOISE_TEX := "res://assets/vehicles/textures/vehicle_noise.png"
const MARDER_SCENE := "res://assets/vehicles/marder/rabe_marder.scn"
const DETAIL_RANGE := 70.0          # Innenraum/Felgen/Draehte ab hier ausgeblendet
const DECAL_RANGE := 90.0
const RIM_RANGE := 60.0           # Scan-Felgen (~16k Dreiecke) nur in der Naehe
const RIM_DIR := "res://assets/props/vehicles_wreck/"

## Vertex-Farben (r = Lackflaeche, g = verkohlt, a = Helligkeit)
const C_PANEL := Color(1.0, 0.0, 0.0, 1.0)
const C_PILLAR := Color(1.0, 0.3, 0.0, 0.95)
const C_INNER := Color(0.0, 0.55, 0.0, 0.75)
const C_SPRING := Color(0.0, 0.2, 0.0, 0.85)
const C_STEEL := Color(0.25, 0.12, 0.0, 0.9)
const C_WIRE := Color(0.0, 0.35, 0.0, 0.8)

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}
static var _marder_failed := false

# ------------------------------------------------------------------ Material

static func material(snow: bool = false) -> ShaderMaterial:
	var key := "snow" if snow else "plain"
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = load(SHADER) as Shader
	m.set_shader_parameter("noise_tex", load(NOISE_TEX))
	m.set_shader_parameter("rust_albedo", load(TEX + "rust_coarse_01/diffuse.jpg"))
	m.set_shader_parameter("rust_normal", load(TEX + "rust_coarse_01/normal.jpg"))
	m.set_shader_parameter("rust_arm", load(TEX + "rust_coarse_01/arm.jpg"))
	m.set_shader_parameter("ash_albedo", load(TEX + "rusty_metal_04/diffuse.jpg"))
	m.set_shader_parameter("ash_normal", load(TEX + "rusty_metal_04/normal.jpg"))
	if snow:
		m.set_shader_parameter("snow_amount", 1.0)
	_mat_cache[key] = m
	return m

static func _soot_mat() -> StandardMaterial3D:
	if _mat_cache.has("soot"):
		return _mat_cache["soot"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.025, 0.023, 0.021)
	m.roughness = 0.97
	_mat_cache["soot"] = m
	return m

# ------------------------------------------------------------------ Pkw / Transporter / Bus / Lkw

## Haengt das Wrack (kind: "car", "van", "bus", "truck") an root. paint = urspruengliche Lackfarbe
## (bleibt nur als Rest unten sichtbar). Gibt die Modellhoehe zurueck.
static func build_vehicle(root: Node3D, kind: String, paint: Color, seed_v: float, snow: bool = false) -> float:
	if not _mesh_cache.has(kind):
		_mesh_cache[kind] = _make(kind)
	var parts: Dictionary = _mesh_cache[kind]
	var m := material(snow)
	var h: float = parts["height"]
	for k in ["body", "detail"]:
		var mi := MeshInstance3D.new()
		mi.name = "Wreck_" + k
		mi.mesh = parts[k]
		mi.material_override = m
		mi.set_instance_shader_parameter("paint_color", paint)
		mi.set_instance_shader_parameter("body_h", h)
		mi.set_instance_shader_parameter("seed", seed_v)
		if k == "detail":
			mi.visibility_range_end = DETAIL_RANGE
			mi.visibility_range_end_margin = 8.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind == "bus" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(mi)
	# Gescannte Rostfelgen (Poly Haven rusted_wheel_rim_01/02, CC0), verrusst; Fallback: Drehprofil fehlt dann
	var wheels: Array = parts.get("wheels", [])
	if not wheels.is_empty():
		var rims := _ph_rims(snow)
		for w: Array in wheels:
			var r: Array = rims[int(w[1]) % rims.size()] if not rims.is_empty() else []
			if r.is_empty():
				continue
			var wi := MeshInstance3D.new()
			wi.name = "Wreck_rim"
			wi.mesh = r[0]
			wi.material_override = r[1]
			wi.transform = w[0]
			wi.visibility_range_end = RIM_RANGE
			wi.visibility_range_end_margin = 6.0
			wi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(wi)
	return h

## [[Mesh, Material], ...] der Scan-Felgen; Formschluessel (Blendshape "Key 1" = 1) wird in das Mesh gebacken.
static func _ph_rims(snow: bool) -> Array:
	var key := "ph_rims_snow" if snow else "ph_rims"
	if _mat_cache.has(key):
		return _mat_cache[key]
	var out: Array = []
	for id: String in ["rusted_wheel_rim_01", "rusted_wheel_rim_02"]:
		var path := RIM_DIR + id + "/" + id + ".gltf"
		if not ResourceLoader.exists(path):
			continue
		var ps := load(path) as PackedScene
		if ps == null:
			continue
		var inst := ps.instantiate()
		var found: Array = inst.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			var src := found[0] as MeshInstance3D
			var mesh := _bake_blend(src)
			var sm := src.get_active_material(0)
			var m := (sm.duplicate() if sm != null else StandardMaterial3D.new()) as BaseMaterial3D
			# ausgegluehter Stahl: dunkler, kaum Glanz; Schnee: heller
			m.albedo_color = Color(0.85, 0.85, 0.85) if snow else Color(0.5, 0.44, 0.4)
			m.roughness = 1.0
			out.append([mesh, m])
		inst.free()
	_mat_cache[key] = out
	return out

## Statisches ArrayMesh ohne Blendshapes (der glTF-Formschluessel "Key 1" verschiebt nur ~1 cm).
static func _bake_blend(src: MeshInstance3D) -> Mesh:
	var am := src.mesh as ArrayMesh
	if am == null or am.get_blend_shape_count() == 0:
		return src.mesh
	var out := ArrayMesh.new()
	for i in am.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, am.surface_get_arrays(i))
	return out

## Brandfleck mit Glaskruemeln unter dem Wrack (Decal, blendet in der Ferne aus).
static func scorch(parent: Node3D, size: Vector2, yaw_deg: float = 0.0) -> Decal:
	var key := "decal"
	if not _mat_cache.has(key):
		_mat_cache[key] = [load(TEX + "scorch_decal.png"), load(TEX + "scorch_decal_normal.png")]
	var tx: Array = _mat_cache[key]
	if tx[0] == null:
		return null
	var d := Decal.new()
	d.name = "Scorch"
	d.size = Vector3(size.x, 0.9, size.y)
	d.texture_albedo = tx[0]
	if tx[1] != null:
		d.texture_normal = tx[1]
	d.normal_fade = 0.55
	d.upper_fade = 0.2
	d.lower_fade = 0.3
	d.distance_fade_enabled = true
	d.distance_fade_begin = DECAL_RANGE - 20.0
	d.distance_fade_length = 20.0
	d.rotation_degrees.y = yaw_deg
	parent.add_child(d)
	return d

# --- Geometrie ---

class Spec:
	var hz := 2.2               # halbe Laenge
	var stations: Array = []    # [z, unten, Guertel, Dach/Haube (0 = offen), halbe Breite]
	var wheels: Array = []      # z der Achsen
	var rim_r := 0.2
	var rim_x := 0.72
	var dual_rear := false
	var arch_r := 0.38
	var roof: Array = []        # [z vorn, z hinten, y, halbe Breite, Schuerze, (Radius Dachschulter)]
	var pillars: Array = []     # [Vector3 unten, Vector3 oben, Breite, Tiefe] (rechte Seite, gespiegelt)
	var doors: Array = []       # [z vorn, z hinten, y oben] Tueroeffnungen bis zum Boden, nur Beifahrerseite (-x)
	var ph_rims := false        # gescannte Rostfelgen (Poly Haven) statt Drehprofil
	var height := 1.35

static func _spec(kind: String) -> Spec:
	var s := Spec.new()
	match kind:
		"van":
			s.hz = 2.6
			s.wheels = [1.75, -1.65]
			s.rim_r = 0.21
			s.rim_x = 0.8
			s.arch_r = 0.42
			# Kleinbus/Kastenwagen mit Fensterband (Scheiben weggebrannt), Schiebetuer rechts offen
			s.ph_rims = true
			s.stations = [[2.6, 0.34, 0.6, 0.62, 0.9], [2.52, 0.25, 0.74, 0.76, 0.96], [2.3, 0.2, 0.88, 0.9, 0.99],
				[2.05, 0.2, 0.98, 1.0, 0.99], [2.02, 0.2, 1.0, 0.0, 0.99], [1.3, 0.2, 1.02, 0.0, 1.0],
				[0.66, 0.2, 1.025, 0.0, 1.0], [-0.5, 0.2, 1.03, 0.0, 1.0], [-1.0, 0.2, 1.03, 0.0, 1.0],
				[-2.42, 0.2, 1.03, 0.0, 0.995], [-2.52, 0.23, 1.03, 0.0, 0.975], [-2.58, 0.28, 1.03, 0.0, 0.94],
				[-2.6, 0.34, 1.03, 0.0, 0.9]]
			s.roof = [1.36, -2.57, 1.8, 0.92, 0.05, 0.13]
			s.pillars = [[Vector3(0.95, 1.0, 2.03), Vector3(0.86, 1.72, 1.38), 0.1, 0.06],
				[Vector3(0.99, 1.02, 0.72), Vector3(0.88, 1.72, 0.7), 0.12, 0.05],
				[Vector3(1.0, 1.03, -0.52), Vector3(0.88, 1.72, -0.52), 0.1, 0.05],
				[Vector3(1.0, 1.03, -1.6), Vector3(0.88, 1.72, -1.6), 0.1, 0.05],
				[Vector3(0.93, 1.03, -2.57), Vector3(0.86, 1.72, -2.55), 0.15, 0.09]]
			s.doors = [[0.66, -0.5, 1.03]]
			s.height = 1.85
		"bus":
			s.hz = 5.5
			s.wheels = [4.0, -3.4]
			s.rim_r = 0.29
			s.rim_x = 1.0
			s.arch_r = 0.58
			# Stadtbus: im Grundriss gerundete Ecken, Tueren rechts (vorn + Mitte) offen bis zum Boden
			s.ph_rims = true
			s.stations = [[5.5, 0.42, 1.18, 0.0, 1.0], [5.48, 0.33, 1.19, 0.0, 1.12], [5.42, 0.28, 1.2, 0.0, 1.19],
				[5.3, 0.27, 1.21, 0.0, 1.235], [5.25, 0.27, 1.21, 0.0, 1.24], [5.1, 0.27, 1.22, 0.0, 1.25],
				[4.62, 0.27, 1.22, 0.0, 1.25], [3.0, 0.27, 1.22, 0.0, 1.25], [1.1, 0.27, 1.23, 0.0, 1.25],
				[-0.1, 0.27, 1.23, 0.0, 1.25], [-3.0, 0.27, 1.22, 0.0, 1.25], [-5.1, 0.27, 1.22, 0.0, 1.25],
				[-5.3, 0.27, 1.21, 0.0, 1.235], [-5.42, 0.28, 1.2, 0.0, 1.19], [-5.48, 0.33, 1.19, 0.0, 1.12],
				[-5.5, 0.42, 1.18, 0.0, 1.0]]
			s.roof = [5.4, -5.4, 2.86, 1.21, 0.07, 0.24]
			for i in 10:
				var z := -4.95 + float(i) * 1.1
				var lean := 0.0 if i % 3 != 1 else 0.04
				s.pillars.append([Vector3(1.23, 1.22, z), Vector3(1.19 - lean, 2.6, z + lean), 0.1, 0.06])
			s.pillars.append([Vector3(1.12, 1.19, 5.43), Vector3(1.1, 2.6, 5.38), 0.16, 0.1])
			s.pillars.append([Vector3(1.12, 1.19, -5.43), Vector3(1.1, 2.6, -5.38), 0.16, 0.1])
			s.doors = [[5.25, 4.62, 2.6], [1.1, -0.1, 2.6]]
			s.height = 2.95
		"truck":
			s.hz = 3.5
			s.wheels = [2.45, -2.2]
			s.rim_r = 0.29
			s.rim_x = 0.92
			s.dual_rear = true
			s.arch_r = 0.55
			s.ph_rims = true
			s.stations = [[3.5, 0.56, 1.62, 0.0, 1.0], [3.48, 0.52, 1.62, 0.0, 1.1], [3.43, 0.5, 1.62, 0.0, 1.16],
				[3.3, 0.5, 1.63, 0.0, 1.18], [2.4, 0.5, 1.64, 0.0, 1.18],
				[1.42, 0.5, 1.64, 0.0, 1.18], [1.38, 0.5, 1.64, 2.55, 1.18]]
			s.roof = [3.32, 1.38, 2.55, 1.1, 0.04, 0.12]
			s.pillars = [[Vector3(1.08, 1.62, 3.44), Vector3(1.03, 2.45, 3.3), 0.13, 0.08],
				[Vector3(1.17, 1.64, 1.44), Vector3(1.06, 2.45, 1.42), 0.1, 0.06]]
			s.height = 2.6
		_:
			s.hz = 2.2
			s.wheels = [1.36, -1.33]
			s.stations = [[2.2, 0.32, 0.62, 0.63, 0.78], [2.14, 0.23, 0.7, 0.71, 0.85], [1.95, 0.18, 0.76, 0.775, 0.88],
				[1.45, 0.17, 0.81, 0.825, 0.89], [0.95, 0.17, 0.85, 0.865, 0.89], [0.92, 0.17, 0.86, 0.0, 0.89],
				[0.3, 0.17, 0.875, 0.0, 0.895], [-0.3, 0.17, 0.885, 0.0, 0.895], [-0.95, 0.17, 0.9, 0.0, 0.89],
				[-1.27, 0.17, 0.905, 0.0, 0.89], [-1.3, 0.17, 0.905, 0.915, 0.89], [-1.8, 0.17, 0.9, 0.915, 0.885],
				[-2.1, 0.22, 0.87, 0.88, 0.86], [-2.2, 0.32, 0.8, 0.8, 0.8]]
			s.roof = [0.25, -0.8, 1.33, 0.7, 0.03]
			s.pillars = [[Vector3(0.86, 0.86, 0.93), Vector3(0.69, 1.31, 0.26), 0.08, 0.06],
				[Vector3(0.875, 0.88, -0.22), Vector3(0.7, 1.32, -0.3), 0.1, 0.05],
				[Vector3(0.86, 0.9, -1.28), Vector3(0.69, 1.31, -0.78), 0.2, 0.05]]
			s.height = 1.35
	return s

static func _make(kind: String) -> Dictionary:
	var s := _spec(kind)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind) & 0x7fffffff
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 1.6
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var det := SurfaceTool.new()
	det.begin(Mesh.PRIMITIVE_TRIANGLES)
	_loft(body, s, noise)
	_wheel_wells(body, s)
	_roof(body, s, noise)
	for p: Array in s.pillars:
		for sx: float in [1.0, -1.0]:
			var a: Vector3 = p[0]
			var b: Vector3 = p[1]
			if sx < 0.0 and _in_door(s, a.z, 0.0):
				continue
			_bar(body, Vector3(a.x * sx, a.y, a.z), Vector3(b.x * sx, b.y, b.z), p[2], p[3], C_PILLAR)
	_seams(body, kind, s)
	_doors(body, s)
	_extras(body, det, kind, s, rng)
	_interior(det, kind, s, rng)
	var wheels := _rims(det, s, rng)
	var res := {"height": s.height, "wheels": wheels}
	for pair in [["body", body], ["detail", det]]:
		var st: SurfaceTool = pair[1]
		st.generate_normals()
		st.index()
		res[pair[0]] = st.commit()
	return res

## Querschnitt (Ring, rechts unten -> Dach -> links) an Station st; Radlaeufe heben die Unterkante an.
static func _section(st: Array, s: Spec, noise: FastNoiseLite) -> PackedVector3Array:
	var z: float = st[0]
	var bot: float = st[1]
	var belt: float = st[2]
	var top: float = st[3]
	var hw: float = st[4]
	var open := top <= 0.0
	var box := not open and top > belt + 0.3
	var half: Array[Vector2] = [Vector2(0.0, bot + 0.03), Vector2(hw - 0.12, bot), Vector2(hw - 0.01, bot + 0.1),
		Vector2(hw + 0.012, bot + (belt - bot) * 0.45)]
	if box:
		half.append(Vector2(hw - 0.01, top - 0.1))
		half.append(Vector2(hw - 0.12, top - 0.005))
		half.append(Vector2(0.0, top + 0.02))
	elif open:
		half.append(Vector2(hw - 0.02, belt))
		half.append(Vector2(hw - 0.07, belt + 0.012))
		half.append(Vector2(0.0, belt))
	else:
		half.append(Vector2(hw - 0.02, belt))
		half.append(Vector2(hw - 0.16, top - 0.01))
		half.append(Vector2(0.0, top + 0.015))
	# Radlauf: Punkte 1..3 auf den Bogen heben
	for wz: float in s.wheels:
		var dz := absf(z - wz)
		if dz < s.arch_r:
			var ya := s.rim_r + 0.0 + sqrt(s.arch_r * s.arch_r - dz * dz) * 0.95
			for i in [1, 2, 3]:
				half[i].y = minf(maxf(half[i].y, ya), half[4].y - 0.06)
	var ring := PackedVector3Array()
	for i in half.size():
		ring.append(_dent(Vector3(half[i].x, half[i].y, z), i, noise))
	for i in range(half.size() - 2, 0, -1):
		ring.append(_dent(Vector3(-half[i].x, half[i].y, z), i, noise))
	return ring

## Beulen: Seiten nach innen/aussen, Dachflaechen nach unten.
static func _dent(p: Vector3, idx: int, noise: FastNoiseLite) -> Vector3:
	var n := noise.get_noise_3d(p.x, p.y, p.z)
	if idx >= 5:
		p.y -= absf(n) * 0.035
	elif idx >= 2:
		p.x += signf(p.x) * n * 0.025
	return p

static func _densify(s: Spec) -> Array:
	var out: Array = []
	for i in s.stations.size():
		var a: Array = s.stations[i]
		out.append(a)
		if i + 1 >= s.stations.size():
			break
		var b: Array = s.stations[i + 1]
		var za: float = a[0]
		var zb: float = b[0]
		if (float(a[3]) <= 0.0) != (float(b[3]) <= 0.0):
			continue
		# Schrittweite: an den Radlaeufen fein (Bogen), sonst grob
		var z := za
		while true:
			var step := 0.6
			for wz: float in s.wheels:
				if absf(z - wz) < s.arch_r + 0.15:
					step = 0.07
			z -= step
			if z <= zb + 0.03:
				break
			var t := (za - z) / (za - zb)
			var c: Array = []
			for k in 5:
				c.append(lerpf(float(a[k]), float(b[k]), t))
			c[0] = z
			out.append(c)
	return out

static func _loft(st: SurfaceTool, s: Spec, noise: FastNoiseLite) -> void:
	st.set_smooth_group(1)
	var stations := _densify(s)
	var rings: Array = []
	for sd: Array in stations:
		rings.append(_section(sd, s, noise))
	for i in rings.size() - 1:
		var ra: PackedVector3Array = rings[i]
		var rb: PackedVector3Array = rings[i + 1]
		var open: bool = float(stations[i][3]) <= 0.0 or float(stations[i + 1][3]) <= 0.0
		var n := ra.size()
		# Tueroeffnung (-x): Seitenwand-Quads 7..10 (Spiegelpunkte 5L..1L) weglassen
		var door := _in_door(s, float(stations[i][0]), 0.001) and _in_door(s, float(stations[i + 1][0]), 0.001)
		for k in n:
			if open and (k == 5 or k == 6):
				continue
			if door and k >= 7 and k <= 10:
				continue
			var k2 := (k + 1) % n
			_quad(st, ra[k], ra[k2], rb[k2], rb[k], C_PANEL)
	# Stirnflaechen vorn/hinten und Schottwaende an den Uebergaengen geschlossen/offen
	st.set_smooth_group(0xFFFFFFFF)
	for i in rings.size():
		var cap := i == 0 or i == rings.size() - 1
		var closed: bool = float(stations[i][3]) > 0.0
		if not cap and closed:
			var prev_open: bool = float(stations[i - 1][3]) <= 0.0
			var next_open: bool = float(stations[i + 1][3]) <= 0.0
			cap = prev_open or next_open
		if cap:
			var c := Color(0.6, 0.45, 0.0, 0.9) if (i == 0 or i == rings.size() - 1) else C_INNER
			_fan(st, rings[i], c)
	st.set_smooth_group(0)

## Tuerfugen (dunkle Linien an der Flanke) sowie ausgebrannte Scheinwerfer-/Rueckleuchten-/Kuehlergrill-Hoehlen.
static func _seams(st: SurfaceTool, kind: String, s: Spec) -> void:
	st.set_smooth_group(0xFFFFFFFF)
	var doors: Array = [0.88, -0.24, -1.26]
	var lights_f: Array = [Vector3(0.52, 0.55, 0.0), Vector3(0.36, 0.13, 0.0)]
	var lights_r: Array = [Vector3(0.55, 0.64, 0.0), Vector3(0.36, 0.14, 0.0)]
	var grille: Array = [Vector3(0, 0.47, 0.0), Vector3(0.6, 0.12, 0.0)]
	match kind:
		"van":
			doors = [2.0, 0.72, -0.5]
			lights_f = [Vector3(0.64, 0.52, 0.0), Vector3(0.3, 0.14, 0.0)]
			lights_r = [Vector3(0.82, 0.55, 0.0), Vector3(0.14, 0.3, 0.0)]
			grille = [Vector3(0, 0.46, 0.0), Vector3(0.9, 0.14, 0.0)]
		"bus":
			doors = [4.95, 4.0 - 0.6 - 0.05, 0.6, -0.5]
			lights_f = [Vector3(0.85, 0.62, 0.0), Vector3(0.3, 0.16, 0.0)]
			lights_r = [Vector3(0.9, 0.75, 0.0), Vector3(0.2, 0.35, 0.0)]
			grille = [Vector3(0, 0.75, 0.0), Vector3(1.0, 0.25, 0.0)]
		"truck":
			doors = [3.25, 1.48]
			lights_f = [Vector3(0.86, 0.8, 0.0), Vector3(0.3, 0.16, 0.0)]
			lights_r = []
			grille = [Vector3(0, 1.15, 0.0), Vector3(1.2, 0.5, 0.0)]
	var dark := Color(0.0, 1.0, 0.0, 0.7)
	for z: float in doors:
		var sd := _station_at(s, z)
		var hw: float = sd[4]
		var y0: float = float(sd[1]) + 0.1
		for wz: float in s.wheels:
			if absf(z - wz) < s.arch_r:
				y0 = maxf(y0, s.rim_r + sqrt(s.arch_r * s.arch_r - (z - wz) * (z - wz)) * 0.95 + 0.02)
		var y1: float = float(sd[2]) - 0.03
		for sx: float in [1.0, -1.0]:
			if kind == "bus" and sx > 0.0:
				continue
			if sx < 0.0 and _in_door(s, z, 0.03):
				continue
			_bar(st, Vector3(sx * hw, y0, z), Vector3(sx * hw, y1, z), 0.012, 0.06, dark)
	for e: Array in [[lights_f, s.hz], [lights_r, -s.hz]]:
		var l: Array = e[0]
		if l.is_empty():
			continue
		var zc: float = e[1]
		for sx: float in [1.0, -1.0]:
			var c: Vector3 = l[0]
			var sz: Vector3 = l[1]
			_box(st, Vector3(sx * c.x, c.y, zc), Vector3(sz.x, sz.y, 0.07), Basis.IDENTITY, dark)
	var gc: Vector3 = grille[0]
	var gs: Vector3 = grille[1]
	_box(st, Vector3(0, gc.y, s.hz), Vector3(gs.x, gs.y, 0.07), Basis.IDENTITY, dark)
	st.set_smooth_group(0)

static func _station_at(s: Spec, z: float) -> Array:
	var best: Array = s.stations[0]
	for i in s.stations.size() - 1:
		var a: Array = s.stations[i]
		var b: Array = s.stations[i + 1]
		if z <= float(a[0]) and z >= float(b[0]):
			var t := (float(a[0]) - z) / maxf(float(a[0]) - float(b[0]), 0.001)
			best = []
			for k in 5:
				best.append(lerpf(float(a[k]), float(b[k]), t))
			# Guertel offener Stationen gilt auch hier
			best[2] = lerpf(float(a[2]), float(b[2]), t)
			break
	return best

## Radhaus-Schalen (innen), damit man durch den Radlauf nicht in die Karosserie sieht.
static func _wheel_wells(st: SurfaceTool, s: Spec) -> void:
	st.set_smooth_group(2)
	var hw: float = s.stations[int(s.stations.size() * 0.5)][4]
	var z_front: float = s.stations[0][0]
	var z_back: float = s.stations[s.stations.size() - 1][0]
	for wz: float in s.wheels:
		if wz < z_back or wz > z_front:
			continue        # Lkw-Hinterachse unter der Pritsche: keine Karosserie -> keine Radhaus-Schale
		for sx: float in [1.0, -1.0]:
			var prev_o := Vector3.ZERO
			var prev_i := Vector3.ZERO
			for i in 13:
				var a := PI * float(i) / 12.0
				var y := s.rim_r + sin(a) * s.arch_r * 0.95
				var z := wz + cos(a) * s.arch_r
				var po := Vector3(sx * (hw - 0.03), y, z)
				var pi_ := Vector3(sx * (hw - 0.33), y, z)
				if i > 0:
					_quad(st, prev_o, po, pi_, prev_i, C_INNER)
				prev_o = po
				prev_i = pi_
	st.set_smooth_group(0)

## Dachblech mit Mulde (durchgehangen), Regenrinne/Schuerze rundum.
static func _roof(st: SurfaceTool, s: Spec, noise: FastNoiseLite) -> void:
	var zf: float = s.roof[0]
	var zr: float = s.roof[1]
	var y0: float = s.roof[2]
	var hw: float = s.roof[3]
	var skirt: float = s.roof[4]
	var sr: float = s.roof[5] if s.roof.size() > 5 else 0.0
	# Querschnitt (x, dy): flach bzw. mit gerundeter Dachschulter (Viertelkreis) zu beiden Seiten
	var cs: Array[Vector2] = []
	if sr <= 0.0:
		for i in 9:
			cs.append(Vector2((float(i) / 8.0 * 2.0 - 1.0) * hw, 0.0))
	else:
		for i in 4:
			var a := PI - float(i) * PI / 6.0
			cs.append(Vector2(-hw + sr + cos(a) * sr, -sr + sin(a) * sr))
		for i in range(1, 6):
			cs.append(Vector2(lerpf(-hw + sr, hw - sr, float(i) / 6.0), 0.0))
		for i in 4:
			var a := PI * 0.5 - float(i) * PI / 6.0
			cs.append(Vector2(hw - sr + cos(a) * sr, -sr + sin(a) * sr))
	var nx := cs.size() - 1
	var nz := maxi(6, int(absf(zf - zr) / 0.35))
	var grid: Array = []
	for j in nz + 1:
		var row: Array = []
		var tz := float(j) / float(nz)
		var z := lerpf(zf, zr, tz)
		for i in nx + 1:
			var tx := clampf(cs[i].x / hw, -1.0, 1.0)
			var x := cs[i].x
			var inner := 1.0 - tx * tx
			var crown := inner * 0.035
			var sag := inner * (1.0 - pow(tz * 2.0 - 1.0, 2.0)) * 0.07
			var y := y0 + cs[i].y + crown - sag + noise.get_noise_2d(x * 1.3, z * 1.3) * 0.02 * (1.0 - absf(tx))
			row.append(Vector3(x, y, z))
		grid.append(row)
	st.set_smooth_group(3)
	for j in nz:
		for i in nx:
			_quad(st, grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i], C_PANEL)
	st.set_smooth_group(0xFFFFFFFF)
	var down := Vector3(0, -skirt, 0)
	for j in nz:
		for i in [0, nx]:
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j + 1][i]
			_quad(st, a, b, b + down, a + down, C_PILLAR)
	for j in [0, nz]:
		for i in nx:
			var a: Vector3 = grid[j][i]
			var b: Vector3 = grid[j][i + 1]
			_quad(st, a, b, b + down, a + down, C_PILLAR)
	st.set_smooth_group(0)

## Innenraum: Boden, Sitzgestelle (Federkern ohne Polster), Armaturentraeger, Lenkradring, Stahltraeger.
static func _interior(st: SurfaceTool, kind: String, s: Spec, rng: RandomNumberGenerator) -> void:
	st.set_smooth_group(0xFFFFFFFF)
	var floor_y := 0.3
	var z0 := 0.9
	var z1 := -1.28
	var seats: Array = []       # [Mitte, Breite, Tiefe, Lehnenhoehe]
	var dash := Vector3(0, 0.72, 0.72)
	var dash_w := 1.55
	var wheel := Vector3(0.37, 0.9, 0.52)
	var wheel_tilt := 25.0
	var wheel_r := 0.19
	var beam_y := 0.36
	match kind:
		"van":
			floor_y = 0.36; z0 = 2.0; z1 = -2.5
			seats = [[Vector3(0.45, 0.0, 1.15), 0.5, 0.5, 0.6], [Vector3(-0.45, 0.0, 1.15), 0.5, 0.5, 0.6],
				[Vector3(0.22, 0.0, -0.15), 1.4, 0.48, 0.6], [Vector3(0.0, 0.0, -1.25), 1.75, 0.48, 0.6]]
			dash = Vector3(0, 0.9, 1.85); dash_w = 1.8
			wheel = Vector3(0.45, 1.12, 1.62); wheel_tilt = 40.0
			beam_y = 0.42
		"bus":
			floor_y = 0.5; z0 = 5.35; z1 = -5.35
			var z := 3.4
			while z > -4.9:
				for sx: float in [1.0, -1.0]:
					if rng.randf() < 0.85:
						seats.append([Vector3(sx * 0.72, 0.0, z), 0.88, 0.45, 0.55])
				z -= 0.85
			seats.append([Vector3(0.75, 0.0, 4.5), 0.5, 0.5, 0.6])
			dash = Vector3(0, 1.1, 5.25); dash_w = 2.2
			wheel = Vector3(0.75, 1.35, 4.95); wheel_tilt = 60.0; wheel_r = 0.25
			beam_y = 0.5
		"truck":
			floor_y = 0.78; z0 = 3.35; z1 = 1.45
			seats = [[Vector3(0.55, 0.0, 1.95), 0.55, 0.5, 0.65], [Vector3(-0.5, 0.0, 1.95), 0.7, 0.5, 0.65]]
			dash = Vector3(0, 1.48, 3.18); dash_w = 2.1
			wheel = Vector3(0.55, 1.72, 2.85); wheel_tilt = 55.0; wheel_r = 0.24
			beam_y = 0.62
			_truck_bed(st, s, rng)
		_:
			seats = [[Vector3(0.4, 0.0, -0.05), 0.5, 0.5, 0.58], [Vector3(-0.4, 0.0, -0.05), 0.5, 0.5, 0.58],
				[Vector3(0.0, 0.0, -0.95), 1.3, 0.48, 0.5]]
	var hw: float = s.stations[int(s.stations.size() * 0.5)][4] - 0.05
	# Boden: Mittelteil innerhalb der Radhaeuser, Randstreifen nur zwischen den Radlaeufen
	# (sonst sieht man das Bodenblech als Brett durch den leeren Radlauf)
	var hi := hw - 0.3
	_box(st, Vector3(0, floor_y, (z0 + z1) * 0.5), Vector3(hi * 2.0, 0.03, absf(z0 - z1)), Basis.IDENTITY, C_INNER)
	var cuts: Array = [z0]
	for wz: float in s.wheels:
		if wz < z0 and wz > z1:
			cuts.append(wz + s.arch_r + 0.04)
			cuts.append(wz - s.arch_r - 0.04)
	cuts.append(z1)
	for ci in range(0, cuts.size() - 1, 2):
		var za: float = minf(float(cuts[ci]), z0)
		var zb: float = maxf(float(cuts[ci + 1]), z1)
		for wz: float in s.wheels:
			if absf(za - wz) < s.arch_r + 0.04:
				za = wz - s.arch_r - 0.04
			if absf(zb - wz) < s.arch_r + 0.04:
				zb = wz + s.arch_r + 0.04
		if za - zb < 0.1:
			continue
		for sx: float in [1.0, -1.0]:
			_box(st, Vector3(sx * (hi + hw) * 0.5, floor_y, (za + zb) * 0.5), Vector3(hw - hi, 0.03, za - zb), Basis.IDENTITY, C_INNER)
	for sd: Array in seats:
		_seat(st, sd[0] + Vector3(0, floor_y, 0), sd[1], sd[2], sd[3], rng)
	_box(st, dash, Vector3(dash_w, 0.12, 0.22), Basis(Vector3.RIGHT, deg_to_rad(-12.0)), C_INNER)
	_bar(st, dash + Vector3(-dash_w * 0.5, -0.05, -0.1), dash + Vector3(dash_w * 0.5, -0.05, -0.1), 0.05, 0.05, C_SPRING)
	var wb := Basis(Vector3.RIGHT, deg_to_rad(90.0 - wheel_tilt))
	_ring(st, wheel, wb, wheel_r, 0.016, 16, 5, C_STEEL)
	_bar(st, wheel, wheel + wb * Vector3(0, -0.35, 0.0), 0.04, 0.04, C_STEEL)
	# Stossfaenger weggeschmolzen: Stahl-Quertraeger vorn/hinten
	var bw: float = float(s.stations[1][4]) * 1.6
	for sz: float in [1.0, -1.0]:
		var zb := sz * (s.hz - 0.06)
		_bar(st, Vector3(-bw * 0.5, beam_y, zb), Vector3(bw * 0.5, beam_y, zb), 0.09, 0.12, C_STEEL)
	st.set_smooth_group(0)

## Sitzgestell: Rahmen + Federkern-Draehte, Lehne leicht nach hinten.
static func _seat(st: SurfaceTool, base: Vector3, w: float, d: float, back_h: float, rng: RandomNumberGenerator) -> void:
	var sy := 0.28
	var c := base + Vector3(0, sy, 0)
	var hx := w * 0.5
	var hz := d * 0.5
	var corners := [c + Vector3(-hx, 0, hz), c + Vector3(hx, 0, hz), c + Vector3(hx, 0, -hz), c + Vector3(-hx, 0, -hz)]
	for i in 4:
		_bar(st, corners[i], corners[(i + 1) % 4], 0.025, 0.025, C_SPRING)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var top := c + Vector3(sx * hx * 0.8, 0, sz * hz * 0.8)
			_bar(st, top, Vector3(top.x, base.y, top.z), 0.035, 0.035, C_INNER)
	# Federkern (Zickzack quer)
	var n := maxi(3, int(d / 0.1))
	for i in n:
		var z := lerpf(-hz + 0.05, hz - 0.05, float(i) / float(n - 1))
		var droop := -0.03 - rng.randf() * 0.03
		_bar(st, c + Vector3(-hx, 0, z), c + Vector3(0, droop, z), 0.012, 0.012, C_SPRING)
		_bar(st, c + Vector3(0, droop, z), c + Vector3(hx, 0, z), 0.012, 0.012, C_SPRING)
	# Lehne
	var lean := Vector3(0, back_h, -0.12 - rng.randf() * 0.08)
	var b0 := c + Vector3(0, 0, -hz)
	var bl := b0 + Vector3(-hx * 0.9, 0, 0)
	var br := b0 + Vector3(hx * 0.9, 0, 0)
	_bar(st, bl, bl + lean, 0.03, 0.03, C_SPRING)
	_bar(st, br, br + lean, 0.03, 0.03, C_SPRING)
	_bar(st, bl + lean, br + lean, 0.03, 0.03, C_SPRING)
	for i in 4:
		var t := 0.25 + float(i) * 0.2
		_bar(st, bl + lean * t, br + lean * t + Vector3(0, -0.02, 0), 0.012, 0.012, C_SPRING)

## Lkw-Pritsche: Rahmen, Ladeflaeche, Bordwaende (eine abgefallen), Spriegel ohne Plane.
static func _truck_bed(st: SurfaceTool, s: Spec, rng: RandomNumberGenerator) -> void:
	for sx: float in [1.0, -1.0]:
		_bar(st, Vector3(sx * 0.45, 0.72, -3.45), Vector3(sx * 0.45, 0.72, 3.2), 0.12, 0.24, C_STEEL)
	_box(st, Vector3(0, 1.04, -1.12), Vector3(2.36, 0.07, 4.66), Basis.IDENTITY, C_PANEL)
	for i in 6:
		var z := 1.15 - float(i) * 0.9
		_bar(st, Vector3(-1.15, 0.94, z), Vector3(1.15, 0.94, z), 0.08, 0.12, C_STEEL)
	# Bordwaende: rechts stehend, links heruntergeklappt, hinten schraeg
	_box(st, Vector3(1.16, 1.32, -1.12), Vector3(0.04, 0.48, 4.6), Basis.IDENTITY, C_PANEL)
	_box(st, Vector3(-1.32, 0.86, -1.12), Vector3(0.04, 0.48, 4.6), Basis(Vector3.BACK, deg_to_rad(-72.0)), C_PANEL)
	_box(st, Vector3(0, 1.3, -3.44), Vector3(2.3, 0.46, 0.04), Basis(Vector3.RIGHT, deg_to_rad(-14.0)), C_PANEL)
	_box(st, Vector3(0, 1.4, 1.2), Vector3(2.36, 0.65, 0.05), Basis.IDENTITY, C_PANEL)
	# Spriegel (Planenbuegel), einer verbogen
	var zs := [0.95, -0.35, -1.65, -2.95]
	for zi in zs.size():
		var z: float = zs[zi]
		var bend := 0.25 if zi == 2 else 0.0
		var pts := [Vector3(1.15, 1.08, z), Vector3(1.15, 2.25, z), Vector3(0.85, 2.55 - bend, z + bend * 0.4),
			Vector3(-0.85, 2.55 - bend * 0.5, z), Vector3(-1.15, 2.25, z), Vector3(-1.15, 1.08, z)]
		for i in pts.size() - 1:
			_bar(st, pts[i], pts[i + 1], 0.035, 0.035, C_STEEL)
	_bar(st, Vector3(0, 2.55, 0.95), Vector3(0, 2.5, -2.95), 0.03, 0.03, C_STEEL)
	# Tank und Kotfluegel hinten
	_cbox(st, Transform3D(Basis.IDENTITY, Vector3(-0.9, 0.7, 0.4)), Vector3(0.5, 0.5, 1.1), 0.14, C_STEEL)
	for sz: float in [-0.25, 0.25]:
		_bar(st, Vector3(-1.16, 0.7, 0.4 + sz), Vector3(-0.64, 0.98, 0.4 + sz), 0.04, 0.02, C_STEEL)
	for sx: float in [1.0, -1.0]:
		_box(st, Vector3(sx * 0.92, 0.95, s.wheels[1]), Vector3(0.62, 0.03, 1.25), Basis.IDENTITY, C_STEEL)

## Nackte Stahlfelgen (Drehprofil) mit Drahtkern-Resten; Karosserie sitzt darauf.
## Bei ph_rims nur Drahtkerne; die Felgen-Transformationen (Achse lokal +Z = aussen) kommen zurueck.
static func _rims(st: SurfaceTool, s: Spec, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var k := s.rim_r / 0.2
	var prof: Array[Vector2] = [Vector2(0.208, 0.0), Vector2(0.2, 0.012), Vector2(0.19, 0.02), Vector2(0.185, 0.05),
		Vector2(0.165, 0.065), Vector2(0.165, 0.14), Vector2(0.185, 0.155), Vector2(0.19, 0.18),
		Vector2(0.2, 0.188), Vector2(0.208, 0.2)]
	var disc: Array[Vector2] = [Vector2(0.166, 0.06), Vector2(0.12, 0.052), Vector2(0.075, 0.025),
		Vector2(0.045, 0.03), Vector2(0.0, 0.03)]
	for wi in s.wheels.size():
		var wz: float = s.wheels[wi]
		var dual := s.dual_rear and wi == s.wheels.size() - 1
		for sx: float in [1.0, -1.0]:
			var hub := s.rim_r * 1.04 - 0.012 + rng.randf() * 0.01
			var camber := deg_to_rad(rng.randf_range(2.0, 6.0))
			var b := Basis(Vector3.UP, 0.0 if sx > 0.0 else PI)
			b = Basis(Vector3.BACK, -camber * sx) * b
			var offs := [0.0, -0.2 * k] if dual else [0.0]
			for o: float in offs:
				var c := Vector3(sx * (s.rim_x + o), hub, wz)
				var xf := Transform3D(b, c)
				if s.ph_rims:
					# Scan-Felge: Radius 0.2025, Breite 0.15 entlang Z; Z -> Fahrzeug-aussen, zufaellig verdreht
					var sc := s.rim_r * 1.04 / 0.2025
					var rb := b * Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.BACK, rng.randf() * TAU)
					out.append([Transform3D(rb.scaled_local(Vector3(sc, sc, sc * 1.25)), c), rng.randi() % 2])
				else:
					st.set_smooth_group(4)
					_lathe(st, xf, prof, k, 0.1 * k, C_STEEL)
					_lathe(st, xf, disc, k, 0.1 * k, C_STEEL)
				st.set_smooth_group(0xFFFFFFFF)
				# Drahtkerne der Reifenwulst, lose
				for a: float in [0.0, 0.2]:
					var rb := xf.basis * Basis(Vector3.BACK, PI * 0.5)
					var pc := xf * Vector3(0.1 * k - a * k, 0, 0)
					_ring(st, pc + Vector3(0, -0.01, 0), rb, 0.212 * k, 0.005, 20, 3, C_WIRE)
				# Gummireste: zerlaufene, verkohlte Wulst am Boden unter der Felge
				if s.ph_rims:
					var gb := Basis.IDENTITY.scaled(Vector3(1.0, 0.35, 1.5))
					_ring(st, Vector3(c.x, 0.012, c.z), gb, 0.13 * k, 0.06, 14, 5, C_INNER)
	st.set_smooth_group(0)
	return out

static func _in_door(s: Spec, z: float, margin: float) -> bool:
	for d: Array in s.doors:
		if z <= float(d[0]) + margin and z >= float(d[1]) - margin:
			return true
	return false

## Tuerrahmen (-x): Pfosten vom Boden bis Tueroberkante, Schwelle; Kanten der offenen Seitenwand verdeckt.
static func _doors(st: SurfaceTool, s: Spec) -> void:
	st.set_smooth_group(0xFFFFFFFF)
	for d: Array in s.doors:
		var top: float = d[2]
		for z: float in [float(d[0]), float(d[1])]:
			var sd := _station_at(s, z)
			var x: float = -(float(sd[4]) - 0.02)
			_bar(st, Vector3(x, float(sd[1]) + 0.02, z), Vector3(x + 0.02, top, z), 0.07, 0.09, C_PILLAR)
		var sm := _station_at(s, (float(d[0]) + float(d[1])) * 0.5)
		var xs: float = -(float(sm[4]) - 0.06)
		_bar(st, Vector3(xs, float(sm[1]) + 0.04, float(d[0])), Vector3(xs, float(sm[1]) + 0.04, float(d[1])), 0.1, 0.05, C_STEEL)
		if top > float(sm[2]) + 0.3:
			_bar(st, Vector3(xs + 0.04, top, float(d[0])), Vector3(xs + 0.04, top, float(d[1])), 0.08, 0.1, C_PILLAR)
	st.set_smooth_group(0)

## Typabhaengige Anbauten: Stossfaenger, Kuehlergrill-Lamellen, Spiegelarme, Trittstufen, Zielschild,
## Klimaanlage, Heckklappen-Rahmen, herausgefallene Tuerfluegel.
static func _extras(body: SurfaceTool, det: SurfaceTool, kind: String, s: Spec, rng: RandomNumberGenerator) -> void:
	body.set_smooth_group(0xFFFFFFFF)
	det.set_smooth_group(0xFFFFFFFF)
	var dark := Color(0.0, 1.0, 0.0, 0.7)
	match kind:
		"van":
			# Frontscheiben-Oberkante, Heck: Rahmen + Mittelpfosten der Fluegeltueren
			_cbox(body, Transform3D(Basis.IDENTITY, Vector3(0, 1.69, 1.39)), Vector3(1.7, 0.08, 0.06), 0.02, C_PILLAR)
			_cbox(body, Transform3D(Basis.IDENTITY, Vector3(0, 1.68, -2.575)), Vector3(1.72, 0.1, 0.06), 0.02, C_PILLAR)
			_bar(body, Vector3(0, 0.34, -2.61), Vector3(0, 1.66, -2.6), 0.07, 0.05, C_PILLAR)
			# Stossfaenger (Kunststoff weg, Traeger mit Ecken), Kennzeichenmulde hinten
			for sz: float in [1.0, -1.0]:
				var zb := sz * (s.hz + 0.04)
				_cbox(body, Transform3D(Basis.IDENTITY, Vector3(0, 0.36, zb)), Vector3(1.78, 0.2, 0.12), 0.05, C_STEEL)
			# Schiebetuer aufgeschoben, haengt schief in der hinteren Fuehrung
			var db := Basis(Vector3.FORWARD, deg_to_rad(4.0)) * Basis(Vector3.UP, deg_to_rad(-2.0))
			_cbox(body, Transform3D(db, Vector3(-1.07, 0.66, -1.08)), Vector3(0.04, 0.82, 1.14), 0.015, C_PANEL)
			_cbox(body, Transform3D(Basis.IDENTITY, Vector3(-1.04, 1.06, -1.0)), Vector3(0.05, 0.04, 2.0), 0.01, C_STEEL)
			# Spiegelarme
			for sx: float in [1.0, -1.0]:
				var a := Vector3(sx * 0.98, 1.08, 1.98)
				_bar(det, a, a + Vector3(sx * 0.2, 0.06, -0.04), 0.03, 0.03, C_STEEL)
				_cbox(det, Transform3D(Basis.IDENTITY, a + Vector3(sx * 0.24, 0.08, -0.05)), Vector3(0.05, 0.24, 0.14), 0.015, C_STEEL)
		"bus":
			# Zielschild-Kasten vorn, Heckfenster-Sturz, Stossfaenger, Motorraum-Lamellen hinten
			_cbox(body, Transform3D(Basis.IDENTITY, Vector3(0, 2.6, 5.4)), Vector3(2.12, 0.26, 0.08), 0.03, C_PILLAR)
			_box(body, Vector3(0, 2.61, 5.45), Vector3(1.5, 0.16, 0.02), Basis.IDENTITY, dark)
			_cbox(body, Transform3D(Basis.IDENTITY, Vector3(0, 2.5, -5.41)), Vector3(2.12, 0.42, 0.08), 0.03, C_PILLAR)
			_bar(body, Vector3(0, 1.2, 5.46), Vector3(0, 2.48, 5.44), 0.06, 0.05, C_PILLAR)
			for sz: float in [1.0, -1.0]:
				var zb := sz * (s.hz + 0.03)
				_cbox(body, Transform3D(Basis.IDENTITY, Vector3(0, 0.4, zb)), Vector3(2.1, 0.26, 0.14), 0.06, C_STEEL)
			for i in 5:
				var y := 0.68 + float(i) * 0.1
				_bar(body, Vector3(-0.85, y, -5.52), Vector3(0.85, y, -5.52), 0.035, 0.04, dark)
			# Klimaanlage auf dem Dach (Haube teils weggebrannt -> Rippenpaket sichtbar)
			_cbox(body, Transform3D(Basis.IDENTITY, Vector3(0, 2.95, 1.6)), Vector3(1.8, 0.2, 2.6), 0.08, C_PANEL)
			for i in 7:
				var z := 0.6 + float(i) * 0.33
				_bar(det, Vector3(-0.7, 3.06, z), Vector3(0.7, 3.06, z), 0.03, 0.06, C_STEEL)
			# Tuerfluegel: vorn einer schraeg herausgebrochen, Mitte einer auf der Strasse
			var fb := Basis(Vector3.BACK, deg_to_rad(-14.0)) * Basis(Vector3.UP, deg_to_rad(10.0))
			_cbox(body, Transform3D(fb, Vector3(-1.42, 1.25, 5.0)), Vector3(0.04, 1.95, 0.5), 0.015, C_PILLAR)
			_cbox(body, Transform3D(Basis(Vector3.UP, deg_to_rad(7.0)), Vector3(-1.95, 0.03, 0.45)), Vector3(0.6, 0.04, 1.9), 0.012, C_PILLAR)
			# Spiegelarme (Bus: Fuehler-Arme nach vorn)
			for sx: float in [1.0, -1.0]:
				var a := Vector3(sx * 1.15, 2.45, 5.3)
				var e := a + Vector3(sx * 0.25, -0.15, 0.3)
				_bar(det, a, e, 0.04, 0.04, C_STEEL)
				_cbox(det, Transform3D(Basis.IDENTITY, e + Vector3(0, -0.2, 0)), Vector3(0.07, 0.38, 0.22), 0.02, C_STEEL)
		"truck":
			# schwerer Stahl-Stossfaenger mit Abschleppmaul, Grill-Lamellen, Scheinwerfertoepfe
			_cbox(body, Transform3D(Basis.IDENTITY, Vector3(0, 0.6, s.hz + 0.08)), Vector3(2.32, 0.34, 0.2), 0.05, C_STEEL)
			_box(body, Vector3(0, 0.6, s.hz + 0.19), Vector3(0.3, 0.14, 0.02), Basis.IDENTITY, dark)
			for i in 6:
				var y := 0.94 + float(i) * 0.085
				_bar(body, Vector3(-0.58, y, s.hz + 0.035), Vector3(0.58, y, s.hz + 0.035), 0.04, 0.03, C_STEEL)
			for sx: float in [1.0, -1.0]:
				_ring(body, Vector3(sx * 0.82, 0.8, s.hz + 0.04), Basis(Vector3.RIGHT, PI * 0.5), 0.13, 0.025, 14, 4, C_STEEL)
				# Spiegelarme + Spiegelgehaeuse
				var a := Vector3(sx * 1.12, 2.15, 3.3)
				var e := a + Vector3(sx * 0.32, 0.05, -0.05)
				_bar(det, a, e, 0.035, 0.035, C_STEEL)
				_bar(det, a + Vector3(0, -0.45, 0.02), e + Vector3(0, -0.3, 0), 0.03, 0.03, C_STEEL)
				_cbox(det, Transform3D(Basis.IDENTITY, e + Vector3(sx * 0.03, -0.12, 0)), Vector3(0.06, 0.42, 0.22), 0.02, C_STEEL)
				# Trittstufen hinter dem Vorderrad
				for ty: float in [0.38, 0.72]:
					_cbox(body, Transform3D(Basis.IDENTITY, Vector3(sx * 1.06, ty, 1.72)), Vector3(0.16, 0.035, 0.4), 0.01, C_STEEL)
				_bar(body, Vector3(sx * 1.13, 0.3, 1.52), Vector3(sx * 1.13, 0.78, 1.52), 0.03, 0.03, C_STEEL)
				_bar(body, Vector3(sx * 1.13, 0.3, 1.92), Vector3(sx * 1.13, 0.78, 1.92), 0.03, 0.03, C_STEEL)
			# Rueckwand-Fenster des Fahrerhauses
			_box(body, Vector3(0, 2.05, 1.37), Vector3(1.3, 0.45, 0.03), Basis.IDENTITY, dark)
	body.set_smooth_group(0)
	det.set_smooth_group(0)

## Kasten mit abgefasten Laengskanten (Achtkant-Querschnitt in xy, entlang z extrudiert).
static func _cbox(st: SurfaceTool, xf: Transform3D, size: Vector3, ch: float, col: Color) -> void:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var c := minf(ch, minf(hx, hy) * 0.9)
	var pts: Array[Vector2] = [Vector2(hx, -hy + c), Vector2(hx, hy - c), Vector2(hx - c, hy), Vector2(-hx + c, hy),
		Vector2(-hx, hy - c), Vector2(-hx, -hy + c), Vector2(-hx + c, -hy), Vector2(hx - c, -hy)]
	var hz := size.z * 0.5
	var f := PackedVector3Array()
	var r := PackedVector3Array()
	for p in pts:
		f.append(xf * Vector3(p.x, p.y, hz))
		r.append(xf * Vector3(p.x, p.y, -hz))
	for i in pts.size():
		var j := (i + 1) % pts.size()
		_quad(st, f[i], r[i], r[j], f[j], col)
	_fan(st, f, col)
	_fan(st, r, col)

# --- Primitive ---

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	st.set_color(col)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

static func _fan(st: SurfaceTool, ring: PackedVector3Array, col: Color) -> void:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	c /= float(ring.size())
	st.set_color(col)
	for i in ring.size():
		st.add_vertex(c)
		st.add_vertex(ring[i])
		st.add_vertex(ring[(i + 1) % ring.size()])

static func _box(st: SurfaceTool, c: Vector3, size: Vector3, b: Basis, col: Color) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for i in 8:
		p.append(c + b * Vector3(h.x * (1.0 if i & 1 else -1.0), h.y * (1.0 if i & 2 else -1.0), h.z * (1.0 if i & 4 else -1.0)))
	for f: Array in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		_quad(st, p[f[0]], p[f[1]], p[f[2]], p[f[3]], col)

## Vierkantstab von a nach b.
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, w: float, d: float, col: Color) -> void:
	var f := b - a
	if f.length() < 0.001:
		return
	f = f.normalized()
	var u := Vector3.UP if absf(f.y) < 0.9 else Vector3.RIGHT
	var r := f.cross(u).normalized() * w * 0.5
	u = r.cross(f).normalized() * d * 0.5
	var q: Array[Vector3] = [r + u, -r + u, -r - u, r - u]
	for i in 4:
		var j := (i + 1) % 4
		_quad(st, a + q[i], a + q[j], b + q[j], b + q[i], col)
	_quad(st, a + q[0], a + q[1], a + q[2], a + q[3], col)
	_quad(st, b + q[3], b + q[2], b + q[1], b + q[0], col)

## Ring (Torus) um die lokale Y-Achse von b.
static func _ring(st: SurfaceTool, c: Vector3, b: Basis, rr: float, r: float, seg: int, sides: int, col: Color) -> void:
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		for j in sides:
			var t0 := TAU * float(j) / float(sides)
			var t1 := TAU * float(j + 1) / float(sides)
			_quad(st, c + b * _tor(a0, t0, rr, r), c + b * _tor(a1, t0, rr, r), c + b * _tor(a1, t1, rr, r), c + b * _tor(a0, t1, rr, r), col)

static func _tor(a: float, t: float, rr: float, r: float) -> Vector3:
	var d := Vector3(cos(a), 0, sin(a))
	return d * (rr + cos(t) * r) + Vector3(0, sin(t) * r, 0)

## Drehkoerper um die lokale X-Achse: prof = (Radius, axialer Abstand von aussen); x = off - axial.
static func _lathe(st: SurfaceTool, xf: Transform3D, prof: Array[Vector2], k: float, off: float, col: Color) -> void:
	var seg := 18
	for i in seg:
		var a0 := TAU * float(i) / float(seg)
		var a1 := TAU * float(i + 1) / float(seg)
		for j in prof.size() - 1:
			var p0 := prof[j] * k
			var p1 := prof[j + 1] * k
			_quad(st, xf * _lp(p0, a0, off), xf * _lp(p1, a0, off), xf * _lp(p1, a1, off), xf * _lp(p0, a1, off), col)

static func _lp(p: Vector2, a: float, off: float) -> Vector3:
	return Vector3(off - p.y, cos(a) * p.x, sin(a) * p.x)

# ------------------------------------------------------------------ Panzerwrack (Marder)

## Verkohlter Marder 1A3 unter root (Front = -Z wie das Modell). false, wenn das Modell fehlt.
static func build_marder(root: Node3D, snow: bool) -> bool:
	if _marder_failed or not ResourceLoader.exists(MARDER_SCENE):
		return false
	var ps := load(MARDER_SCENE) as PackedScene
	var inst: Node3D = ps.instantiate() as Node3D if ps != null else null
	if inst == null or not inst.has_node("Hull/Turret/Mantlet"):
		if inst != null:
			inst.free()
		_marder_failed = true
		return false
	inst.name = "MarderWreck"
	root.add_child(inst)
	var m := material(snow)
	var soot := _soot_mat()
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var sn: String = mi.mesh.surface_get_name(i)
			mi.set_surface_override_material(i, soot if sn.begins_with("glass") else m)
		var y := 0.0
		var p: Node = mi
		while p != null and p != inst:
			y += (p as Node3D).position.y
			p = p.get_parent()
		mi.set_instance_shader_parameter("y_offset", y)
		mi.set_instance_shader_parameter("body_h", 2.6)
		mi.set_instance_shader_parameter("paint_color", Color(0.14, 0.17, 0.11))
		mi.set_instance_shader_parameter("seed", 0.37 if snow else 0.0)
	var hull := inst.get_node("Hull") as Node3D
	var turret := hull.get_node("Turret") as Node3D
	var mantlet := turret.get_node("Mantlet") as Node3D
	# Turm vom Drehkranz gehoben und verdreht, Rohr haengt
	turret.position += Vector3(0.05, 0.07, 0.0)
	turret.rotation_degrees = Vector3(2.5, 36.0, -4.0)
	mantlet.rotation_degrees.x = -9.0
	var ramp := hull.get_node_or_null("RearRamp") as Node3D
	if ramp != null:
		ramp.rotation.x = deg_to_rad(52.0)
	for c in hull.get_children():
		var nm := String(c.name)
		if nm.begins_with("Antenna"):
			c.queue_free()
		elif nm == "Wheel_L_2" or nm == "Wheel_R_4":
			(c as Node3D).visible = false
	inst.rotation_degrees = Vector3(-1.2, 0.0, 1.8)
	return true
