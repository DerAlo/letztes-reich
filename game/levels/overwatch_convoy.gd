extends RefCounted
## Level 7 "Kaltes Auge": prozedurale Konvoi-Fahrzeuge der Ordnungsfront (mesh_kit + vehicle_paint).
##   build_truck(kind): "gun" (Pritsche mit Sandsaecken + MG), "prisoner"/"troop" (Plane), Lack Stahlgrau/Schwarz.
##   build_car(): Webers gepanzerter Gelaendewagen (schwarz) mit oeffnender Tuer hinten links + Panzerglas-Kollision.
## Lokal: vorne = -Z, links = -X. Wurzel = Node3D auf Bodenhoehe; Raeder drehen ueber den Shader-Parameter "spin".

const MK = preload("res://game/vehicles/models/mesh_kit.gd")
const Livery = preload("res://game/vehicles/models/livery.gd")

const WHEEL_R := 0.56
const CAR_WHEEL_R := 0.4

static var _mats: Dictionary = {}

# ------------------------------------------------------------------ Materialien

static func _std(key: String, c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m

static func _glass() -> StandardMaterial3D:
	if not _mats.has("glass"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.05, 0.065, 0.075)
		m.metallic = 0.85
		m.roughness = 0.06
		m.specular = 0.9
		_mats["glass"] = m
	return _mats["glass"]

static func _lamp(c: Color, e: float) -> StandardMaterial3D:
	var key := "lamp_%s_%.1f" % [c.to_html(), e]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = e
		m.roughness = 0.2
		_mats[key] = m
	return _mats[key]

static func _canvas() -> StandardMaterial3D:
	if not _mats.has("canvas"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.2, 0.205, 0.19)
		m.roughness = 1.0
		var nt := NoiseTexture2D.new()
		var fn := FastNoiseLite.new()
		fn.frequency = 0.05
		nt.noise = fn
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 3.0
		m.normal_enabled = true
		m.normal_texture = nt
		m.normal_scale = 0.5
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.7, 0.7, 0.7)
		_mats["canvas"] = m
	return _mats["canvas"]

static func _sandbag() -> StandardMaterial3D:
	if not _mats.has("sandbag"):
		var m := _std("sandbag_base", Color(0.36, 0.33, 0.26), 1.0).duplicate() as StandardMaterial3D
		var nt := NoiseTexture2D.new()
		var fn := FastNoiseLite.new()
		fn.frequency = 0.12
		nt.noise = fn
		nt.seamless = true
		nt.as_normal_map = true
		nt.bump_strength = 6.0
		m.normal_enabled = true
		m.normal_texture = nt
		m.uv1_triplanar = true
		_mats["sandbag"] = m
	return _mats["sandbag"]

# ------------------------------------------------------------------ Gemeinsame Teile

## Reifen mit Stollen um die X-Achse; wheel-Daten fuer das Drehen im Shader.
static func _wheel(k: MK, c: Vector3, r: float, w: float, lugs: int, side: float) -> void:
	k.wheel = Vector3(c.y, c.z, r)
	var hw := w * 0.5
	var prof := PackedVector2Array([
		Vector2(-hw, 0.0), Vector2(-hw, r * 0.5), Vector2(-hw * 1.05, r * 0.62), Vector2(-hw * 1.08, r * 0.8),
		Vector2(-hw * 0.95, r * 0.95), Vector2(-hw * 0.7, r), Vector2(hw * 0.7, r), Vector2(hw * 0.95, r * 0.95),
		Vector2(hw * 1.08, r * 0.8), Vector2(hw * 1.05, r * 0.62), Vector2(hw, r * 0.5), Vector2(hw, 0.0)])
	var hub := MK.shade(MK.PAINT, 0.7)
	var rub := MK.RUBBER
	var bands: Array = [hub, MK.shade(MK.METAL, 0.45), rub, rub, rub, rub, rub, rub, rub, MK.shade(MK.METAL, 0.45), hub]
	k.color = hub
	k.lathe(c, Vector3.RIGHT, prof, 22, true, bands)
	# Stollen
	k.color = MK.shade(MK.RUBBER, 0.8)
	for i in lugs:
		var a := TAU * float(i) / float(lugs)
		var p := c + Vector3(0.0, cos(a), sin(a)) * (r + 0.012)
		k.cbox(p, Vector3(w * 0.42, 0.035, 0.07), 0.01, Vector3(rad_to_deg(-a), 0.0, 0.0))
		k.cbox(p + Vector3(side * w * 0.22, 0, 0), Vector3(w * 0.3, 0.03, 0.06), 0.01, Vector3(rad_to_deg(-a) + 18.0, 0.0, 0.0))
	# Nabe mit Radmuttern (aussen)
	k.color = MK.shade(MK.METAL, 0.55)
	k.cyl(c + Vector3(side * hw * 0.9, 0, 0), c + Vector3(side * (hw + 0.05), 0, 0), r * 0.28, 12)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var p := c + Vector3(side * (hw + 0.03), cos(a) * r * 0.36, sin(a) * r * 0.36)
		k.cyl(p, p + Vector3(side * 0.04, 0, 0), 0.022, 6)
	k.wheel = Vector3.ZERO

static func _collider(root: Node3D, boxes: Array) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = "Collision"
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.set_meta("surface", "metal")
	sb.set_meta("no_fit", true)
	for b: Array in boxes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		cs.position = b[0]
		sb.add_child(cs)
	root.add_child(sb)
	return sb

static func _headlight(root: Node3D, pos: Vector3, energy: float) -> SpotLight3D:
	var sl := SpotLight3D.new()
	sl.name = "Headlight"
	sl.light_color = Color(1.0, 0.9, 0.72)
	sl.light_energy = energy
	sl.spot_range = 45.0
	sl.spot_angle = 32.0
	sl.spot_attenuation = 1.2
	sl.light_volumetric_fog_energy = 2.5
	sl.shadow_enabled = false
	sl.position = pos
	sl.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	root.add_child(sl)
	return sl

# ------------------------------------------------------------------ LKW

## kind: "gun" | "prisoner" | "troop". Laenge ~7.8 m, Breite 2.5 m.
static func build_truck(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Truck_" + kind
	var paint := Livery.paint("tank", "reich")
	var body := MK.new()
	var wheels := MK.new()
	wheels.use_custom = true
	var glass := MK.new()
	var lamps := MK.new()
	var tail := MK.new()
	var k := body
	var P := MK.PAINT
	var M := MK.METAL
	# --- Fahrgestell
	k.color = MK.shade(M, 0.35)
	for sx: float in [-0.48, 0.48]:
		k.cbox(Vector3(sx, 0.92, 0.2), Vector3(0.16, 0.3, 7.5), 0.02)
	for z: float in [-3.0, -1.2, 0.6, 2.2, 3.6]:
		k.cbox(Vector3(0, 0.92, z), Vector3(0.96, 0.18, 0.12), 0.01)
	# Achsen / Differentiale
	for z: float in [-2.45, 1.45, 2.85]:
		k.cyl(Vector3(-1.0, WHEEL_R, z), Vector3(1.0, WHEEL_R, z), 0.07, 8)
		k.cbox(Vector3(0, WHEEL_R, z), Vector3(0.42, 0.34, 0.38), 0.06)
		# Blattfedern
		for sx: float in [-0.72, 0.72]:
			for i in 4:
				k.cbox(Vector3(sx, WHEEL_R + 0.12 + i * 0.035, z), Vector3(0.09, 0.03, 1.05 - i * 0.18), 0.008)
	# Tank, Batteriekasten, Werkzeugkiste
	k.color = MK.shade(P, 0.75)
	k.cyl(Vector3(-1.1, 1.0, -1.55), Vector3(-1.1, 1.0, -0.35), 0.29, 14)
	k.color = MK.shade(M, 0.5)
	for z: float in [-1.45, -0.45]:
		k.cyl(Vector3(-1.1, 1.0, z), Vector3(-1.1, 1.0, z + 0.04), 0.31, 14)
	k.color = MK.shade(P, 0.7)
	k.cbox(Vector3(1.08, 1.0, -1.0), Vector3(0.36, 0.5, 0.9), 0.04)
	k.cbox(Vector3(1.08, 0.98, 0.15), Vector3(0.36, 0.42, 0.7), 0.04)
	# --- Fahrerhaus (Frontlenker, leicht geneigte Front)
	k.color = P
	k.cbox(Vector3(0, 1.62, -2.9), Vector3(2.46, 1.0, 1.85), 0.1)          # unterer Kasten
	k.cbox(Vector3(0, 2.5, -2.82), Vector3(2.4, 0.8, 1.7), 0.12, Vector3(-4.0, 0, 0))   # Fensterband
	k.cbox(Vector3(0, 2.97, -2.8), Vector3(2.36, 0.16, 1.66), 0.07)       # Dach
	k.color = MK.shade(P, 0.85)
	k.cbox(Vector3(0, 3.08, -2.55), Vector3(1.2, 0.08, 0.9), 0.03)        # Dachluke
	# Kotfluegel vorne (Bogen aus Segmenten)
	k.color = MK.shade(P, 0.9)
	for sx: float in [-1.12, 1.12]:
		for i in 7:
			var a := lerpf(-1.25, 1.25, float(i) / 6.0)
			var p := Vector3(sx, WHEEL_R + cos(a) * 0.7, -2.45 + sin(a) * 0.7)
			k.cbox(p, Vector3(0.36, 0.05, 0.34), 0.015, Vector3(rad_to_deg(-a), 0, 0))
	# Tueren: Fugen + Griffe + Trittstufen
	k.color = MK.shade(M, 0.15)
	for sx: float in [-1.235, 1.235]:
		k.cbox(Vector3(sx, 2.0, -3.55), Vector3(0.012, 1.7, 0.02), 0.0)
		k.cbox(Vector3(sx, 2.0, -2.15), Vector3(0.012, 1.7, 0.02), 0.0)
		k.cbox(Vector3(sx, 1.16, -2.85), Vector3(0.012, 0.02, 1.4), 0.0)
		k.color = MK.shade(M, 0.6)
		k.cbox(Vector3(sx * 1.01, 1.9, -2.35), Vector3(0.03, 0.04, 0.22), 0.01)
		k.color = MK.shade(M, 0.4)
		k.cbox(Vector3(sx * 0.97, 0.78, -2.9), Vector3(0.36, 0.05, 0.6), 0.01)
		k.cbox(Vector3(sx * 0.97, 0.42, -2.9), Vector3(0.3, 0.05, 0.55), 0.01)
		k.color = MK.shade(M, 0.15)
	# Kuehlergrill + Stossstange + Seilwinde
	k.color = MK.shade(M, 0.22)
	k.cbox(Vector3(0, 1.55, -3.83), Vector3(1.7, 0.62, 0.06), 0.02)
	k.color = MK.shade(M, 0.45)
	for i in 6:
		k.cbox(Vector3(0, 1.32 + i * 0.09, -3.87), Vector3(1.6, 0.025, 0.03), 0.0)
	k.color = MK.shade(P, 0.6)
	k.cbox(Vector3(0, 0.95, -3.98), Vector3(2.5, 0.3, 0.26), 0.05)
	k.color = MK.shade(M, 0.4)
	k.cyl(Vector3(-0.35, 0.95, -4.12), Vector3(0.35, 0.95, -4.12), 0.12, 12)
	for sx: float in [-0.9, 0.9]:
		k.cbox(Vector3(sx, 0.95, -4.14), Vector3(0.1, 0.18, 0.08), 0.02)
	# Akzentstreifen (Amber) quer ueber die Front
	k.color = MK.ACCENT
	k.cbox(Vector3(0, 2.07, -3.81), Vector3(2.3, 0.07, 0.02), 0.0)
	# Spiegel
	k.color = MK.shade(M, 0.3)
	for sx: float in [-1.0, 1.0]:
		k.cyl(Vector3(sx * 1.2, 2.55, -3.5), Vector3(sx * 1.48, 2.6, -3.62), 0.018, 6)
		k.cbox(Vector3(sx * 1.5, 2.45, -3.62), Vector3(0.05, 0.42, 0.22), 0.02)
	# Auspuff hinter dem Fahrerhaus
	k.cyl(Vector3(1.0, 1.4, -1.85), Vector3(1.0, 3.35, -1.85), 0.065, 10)
	k.cyl(Vector3(1.0, 3.35, -1.85), Vector3(1.0, 3.42, -1.8), 0.075, 10)
	# Ersatzrad hinter dem Fahrerhaus (stehend)
	_wheel(k, Vector3(-0.55, 1.95, -1.82), WHEEL_R * 0.98, 0.42, 14, 1.0)
	k.wheel = Vector3.ZERO
	# Glas
	glass.cbox(Vector3(0, 2.52, -3.68), Vector3(2.14, 0.66, 0.04), 0.01, Vector3(-4.0, 0, 0))
	for sx: float in [-1.215, 1.215]:
		glass.cbox(Vector3(sx, 2.5, -2.95), Vector3(0.03, 0.6, 1.05), 0.01)
	# Scheinwerfer / Blinker
	for sx: float in [-0.95, 0.95]:
		lamps.cyl(Vector3(sx, 1.25, -3.85), Vector3(sx, 1.25, -3.93), 0.12, 14)
	for sx: float in [-1.0, 1.0]:
		tail.cbox(Vector3(sx, 1.05, 3.95), Vector3(0.22, 0.1, 0.05), 0.01)
	# --- Aufbau
	var bed_z0 := -1.62
	var bed_z1 := 3.95
	var bed_len := bed_z1 - bed_z0
	var bed_c := (bed_z0 + bed_z1) * 0.5
	k.color = MK.shade(P, 0.8)
	k.cbox(Vector3(0, 1.22, bed_c), Vector3(2.5, 0.14, bed_len), 0.03)      # Ladeflaeche
	k.color = P
	for sx: float in [-1.22, 1.22]:
		k.cbox(Vector3(sx, 1.58, bed_c), Vector3(0.06, 0.6, bed_len), 0.02)  # Bordwaende
		k.color = MK.shade(P, 0.7)
		for i in 7:
			k.cbox(Vector3(sx * 1.02, 1.58, bed_z0 + 0.15 + i * (bed_len - 0.3) / 6.0), Vector3(0.05, 0.62, 0.07), 0.01)
		k.cbox(Vector3(sx * 1.02, 1.86, bed_c), Vector3(0.05, 0.05, bed_len), 0.01)
		k.color = P
	k.cbox(Vector3(0, 1.58, bed_z0 + 0.03), Vector3(2.5, 0.6, 0.06), 0.02)   # Stirnwand
	k.cbox(Vector3(0, 1.58, bed_z1 - 0.03), Vector3(2.5, 0.6, 0.06), 0.02)   # Heckklappe
	k.color = MK.shade(M, 0.5)
	for sx: float in [-0.8, 0.0, 0.8]:
		k.cbox(Vector3(sx, 1.58, bed_z1 + 0.01), Vector3(0.05, 0.56, 0.04), 0.01)
	k.color = MK.shade(M, 0.35)
	k.cbox(Vector3(0, 0.88, bed_z1 + 0.05), Vector3(2.3, 0.16, 0.12), 0.02)   # Unterfahrschutz
	# Kennzeichen-Nummern (Akzent) an der Heckklappe
	k.color = MK.ACCENT
	k.cbox(Vector3(0.0, 1.72, bed_z1 + 0.035), Vector3(0.55, 0.16, 0.01), 0.0)
	# Hintere Kotfluegel
	k.color = MK.shade(P, 0.75)
	for sx: float in [-1.1, 1.1]:
		k.cbox(Vector3(sx, 1.25, 2.15), Vector3(0.42, 0.05, 2.35), 0.01)
	var cols: Array = [
		[Vector3(0, 1.95, -2.85), Vector3(2.46, 2.1, 1.9)],
		[Vector3(0, 1.15, 1.1), Vector3(2.5, 0.75, 6.2)],
	]
	if kind == "gun":
		_gun_bed(root, k, bed_z0, bed_z1)
		cols.append([Vector3(0, 1.85, 1.2), Vector3(2.5, 0.75, 5.4)])
	else:
		_canvas_top(root, bed_z0 + 0.06, bed_z1 - (0.0 if kind == "prisoner" else 0.25), kind == "prisoner")
		cols.append([Vector3(0, 2.45, 1.15), Vector3(2.48, 2.2, 5.5)])
	# --- Raeder
	for z: float in [-2.45, 1.45, 2.85]:
		for sx: float in [-1.0, 1.0]:
			_wheel(wheels, Vector3(sx * 1.02, WHEEL_R, z), WHEEL_R, 0.44, 18, sx)
	# --- Ausgabe
	body.emit(root, paint, "Body")
	var wm := (paint as ShaderMaterial).duplicate() as ShaderMaterial
	var wmi := wheels.emit(root, wm, "Wheels")
	wmi.set_meta("spin_mat", wm)
	root.set_meta("wheel_mat", wm)
	root.set_meta("wheel_r", WHEEL_R)
	var gmi := glass.emit(root, _glass(), "Glass")
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamps.emit(root, _lamp(Color(1.0, 0.93, 0.78), 6.0), "Lamps").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tail.emit(root, _lamp(Color(0.9, 0.08, 0.04), 3.0), "TailLamps").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_headlight(root, Vector3(0, 1.3, -4.0), 3.0)
	_collider(root, cols)
	return root

## Plane mit Spriegeln: weich geloftet, zwischen den Spriegeln leicht durchhaengend.
static func _canvas_top(root: Node3D, z0: float, z1: float, closed_rear: bool) -> void:
	var k := MK.new()
	var hw := 1.24
	var y0 := 1.86
	var arch := PackedVector2Array()
	var n := 9
	for i in n + 1:
		var a := PI * float(i) / float(n)          # 0 = rechts, PI = links
		arch.append(Vector2(cos(a) * hw, 2.75 + sin(a) * 0.5))
	var ring_pts := PackedVector2Array()
	ring_pts.append(Vector2(hw, y0))
	for p in arch:
		ring_pts.append(p)
	ring_pts.append(Vector2(-hw, y0))
	var bows := 5
	var rings: Array[PackedVector3Array] = []
	var steps := bows * 2
	for s in steps + 1:
		var z := lerpf(z0, z1, float(s) / float(steps))
		var sag := 0.0 if s % 2 == 0 else 1.0
		var r := PackedVector3Array()
		for p in ring_pts:
			var q := p
			if p.y > y0 + 0.01:
				q = Vector2(p.x * (1.0 - 0.012 * sag), y0 + (p.y - y0) * (1.0 - 0.028 * sag))
			r.append(Vector3(q.x, q.y, z))
		rings.append(r)
	k.loft(rings, true, closed_rear, true)
	# Spannriemen + Seitenstreifen
	var straps := MK.new()
	for s in bows + 1:
		var z := lerpf(z0, z1, float(s) / float(bows))
		for i in arch.size() - 1:
			var a0 := arch[i]
			var a1 := arch[i + 1]
			var mid := (a0 + a1) * 0.5 * 1.012
			var ang := rad_to_deg(atan2(a1.y - a0.y, a1.x - a0.x))
			straps.cbox(Vector3(mid.x, mid.y, z), Vector3(a0.distance_to(a1) + 0.02, 0.025, 0.07), 0.005, Vector3(0, 0, ang))
		for sx: float in [-1.0, 1.0]:
			straps.cbox(Vector3(sx * (hw + 0.01), (y0 + 2.75) * 0.5, z), Vector3(0.025, 2.75 - y0, 0.07), 0.005)
	for sx: float in [-1.0, 1.0]:
		straps.cbox(Vector3(sx * (hw + 0.012), y0 + 0.12, (z0 + z1) * 0.5), Vector3(0.02, 0.05, z1 - z0), 0.005)
	if not closed_rear:
		# Hecköffnung: hochgerollte Plane
		straps.cyl(Vector3(-hw * 0.9, 3.05, z1 + 0.05), Vector3(hw * 0.9, 3.05, z1 + 0.05), 0.12, 10)
	var mi := k.emit(root, _canvas(), "Canvas")
	mi.set_meta("canvas", true)
	straps.emit(root, _std("strap", Color(0.08, 0.08, 0.075), 0.9), "Straps")

## Pritsche des Gun-Trucks: Sandsackwall + MG auf Sockel.
static func _gun_bed(root: Node3D, k: MK, z0: float, z1: float) -> void:
	var sb := MK.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for layer in 3:
		var y := 1.38 + layer * 0.2
		var zz := z0 + 0.4
		while zz < z1 - 0.3:
			for sx: float in [-1.0, 1.0]:
				var p := Vector3(sx * 1.0, y, zz + (0.2 if layer % 2 == 1 else 0.0))
				sb.cbox(p, Vector3(0.38, 0.19, 0.56), 0.08, Vector3(rng.randf_range(-4, 4), rng.randf_range(-6, 6), rng.randf_range(-5, 5)))
			zz += 0.58
	for layer in 3:
		var y := 1.38 + layer * 0.2
		for i in 4:
			var x := -0.75 + i * 0.5 + (0.25 if layer % 2 == 1 else 0.0)
			if x > 0.95:
				continue
			sb.cbox(Vector3(x, y, z1 - 0.32), Vector3(0.56, 0.19, 0.38), 0.08, Vector3(rng.randf_range(-5, 5), rng.randf_range(-6, 6), 0))
	sb.emit(root, _sandbag(), "Sandbags")
	# MG-Sockel und Waffe
	k.color = MK.shade(MK.METAL, 0.4)
	k.cyl(Vector3(0, 1.3, -0.6), Vector3(0, 2.5, -0.6), 0.07, 10)
	k.cbox(Vector3(0, 2.55, -0.6), Vector3(0.3, 0.1, 0.3), 0.02)
	# M2 Browning ohne Dreibein auf dem Sockel (GunModels, mit prozeduralem Rueckfall)
	var m2 := GunModels.build_m2(false)
	m2.position = Vector3(0, 2.6, -0.6) - (m2.get_meta("pivot", Vector3(0, 0.27, 0.1)) as Vector3)
	root.add_child(m2)
	k.color = MK.shade(MK.PAINT, 0.8)
	k.cbox(Vector3(0, 2.95, -1.0), Vector3(0.8, 0.5, 0.04), 0.02, Vector3(-8, 0, 0))   # Schutzschild

# ------------------------------------------------------------------ Webers Wagen

## Schwarzer gepanzerter Gelaendewagen (~5.1 m). Tuer hinten links haengt an "RearDoorPivot".
## Meta: "door_pivot" (Node3D), "shield" (StaticBody3D, Panzerglas-Kollision an der offenen Tuer).
static func build_car() -> Node3D:
	var root := Node3D.new()
	root.name = "WeberCar"
	var black := _std("car_black", Color(0.018, 0.019, 0.022), 0.22, 0.55)
	var trim := _std("car_trim", Color(0.03, 0.03, 0.032), 0.7, 0.1)
	var chrome := _std("car_chrome", Color(0.55, 0.56, 0.58), 0.12, 1.0)
	var b := MK.new()
	var t := MK.new()
	var c := MK.new()
	var g := MK.new()
	var wh := MK.new()
	wh.use_custom = true
	var yb := CAR_WHEEL_R
	# Unterbau + Karosserie (kantig, Gelaendewagen)
	b.cbox(Vector3(0, yb + 0.42, 0.0), Vector3(1.98, 0.8, 4.9), 0.12)
	b.cbox(Vector3(0, yb + 0.92, -1.75), Vector3(1.92, 0.22, 1.35), 0.1, Vector3(4.0, 0, 0))   # Motorhaube
	# Fahrgastzelle: Saeulen + Dach (Glas liegt dazwischen)
	var zf := -1.05
	var zr := 2.3
	b.cbox(Vector3(0, yb + 1.68, (zf + zr) * 0.5 + 0.05), Vector3(1.86, 0.1, zr - zf - 0.1), 0.05)
	for sx: float in [-0.9, 0.9]:
		b.cbox(Vector3(sx, yb + 1.25, zf + 0.12), Vector3(0.09, 0.82, 0.1), 0.02, Vector3(-14.0, 0, 0))    # A-Saeule
		b.cbox(Vector3(sx, yb + 1.25, 0.55), Vector3(0.08, 0.82, 0.12), 0.02)    # B
		b.cbox(Vector3(sx, yb + 1.25, 1.65), Vector3(0.08, 0.82, 0.12), 0.02)    # C
		b.cbox(Vector3(sx, yb + 1.25, zr - 0.06), Vector3(0.08, 0.82, 0.14), 0.02)   # D
	b.cbox(Vector3(0, yb + 1.25, zr), Vector3(1.86, 0.82, 0.07), 0.02)    # Heck oben
	# Glas
	g.cbox(Vector3(0, yb + 1.26, zf + 0.04), Vector3(1.74, 0.78, 0.04), 0.01, Vector3(-14.0, 0, 0))
	for sx: float in [-0.915, 0.915]:
		g.cbox(Vector3(sx, yb + 1.26, (zf + 0.55) * 0.5 + 0.05), Vector3(0.025, 0.72, 1.35), 0.005)
		g.cbox(Vector3(sx, yb + 1.26, 2.0), Vector3(0.025, 0.72, 0.5), 0.005)
	g.cbox(Vector3(0.915, yb + 1.26, 1.1), Vector3(0.025, 0.72, 1.0), 0.005)   # rechte hintere Tuer (fest)
	g.cbox(Vector3(0, yb + 1.26, zr + 0.04), Vector3(1.5, 0.6, 0.03), 0.005)
	# Anbauteile: Kuehler, Stossstangen, Schweller, Radlaeufe, Spiegel
	t.cbox(Vector3(0, yb + 0.1, -2.5), Vector3(2.02, 0.32, 0.2), 0.05)
	t.cbox(Vector3(0, yb + 0.1, 2.5), Vector3(2.02, 0.32, 0.2), 0.05)
	for sx: float in [-1.0, 1.0]:
		t.cbox(Vector3(sx * 1.0, yb - 0.05, 0.0), Vector3(0.1, 0.12, 2.6), 0.03)
		for z: float in [-1.6, 1.6]:
			for i in 6:
				var a := lerpf(-1.3, 1.3, float(i) / 5.0)
				t.cbox(Vector3(sx * 1.0, yb + cos(a) * 0.5, z + sin(a) * 0.5), Vector3(0.09, 0.05, 0.22), 0.01, Vector3(rad_to_deg(-a), 0, 0))
		t.cbox(Vector3(sx * 1.08, yb + 1.1, zf - 0.05), Vector3(0.16, 0.14, 0.22), 0.03)
	c.cbox(Vector3(0, yb + 0.58, -2.47), Vector3(1.0, 0.36, 0.04), 0.01)
	for i in 5:
		t.cbox(Vector3(0, yb + 0.44 + i * 0.07, -2.5), Vector3(0.96, 0.02, 0.03), 0.0)
	c.cbox(Vector3(0, yb + 0.28, -2.61), Vector3(1.5, 0.05, 0.04), 0.01)
	# Raeder
	for z: float in [-1.6, 1.6]:
		for sx: float in [-1.0, 1.0]:
			_wheel(wh, Vector3(sx * 0.92, yb, z), CAR_WHEEL_R, 0.3, 16, sx)
	b.emit(root, black, "Body")
	t.emit(root, trim, "Trim")
	c.emit(root, chrome, "Chrome")
	g.emit(root, _glass(), "Glass").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wm := Livery.paint("tank", "reich").duplicate() as ShaderMaterial
	wh.emit(root, wm, "Wheels")
	root.set_meta("wheel_mat", wm)
	root.set_meta("wheel_r", CAR_WHEEL_R)
	var lamps := MK.new()
	for sx: float in [-0.72, 0.72]:
		lamps.cbox(Vector3(sx, yb + 0.6, -2.47), Vector3(0.28, 0.14, 0.04), 0.02)
	lamps.emit(root, _lamp(Color(1.0, 0.95, 0.85), 7.0), "Lamps").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tl := MK.new()
	for sx: float in [-0.88, 0.88]:
		tl.cbox(Vector3(sx, yb + 0.72, 2.49), Vector3(0.12, 0.3, 0.04), 0.01)
	tl.emit(root, _lamp(Color(0.9, 0.06, 0.03), 3.0), "TailLamps").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_headlight(root, Vector3(0, yb + 0.6, -2.55), 2.5)
	# Hintere linke Tuer: Drehpunkt an der Vorderkante (z = 0.6), schwenkt nach aussen (-X)
	var pivot := Node3D.new()
	pivot.name = "RearDoorPivot"
	pivot.position = Vector3(-0.97, 0.0, 0.6)
	root.add_child(pivot)
	var d := MK.new()
	d.cbox(Vector3(0.0, yb + 0.5, 0.52), Vector3(0.1, 0.78, 1.0), 0.03)
	d.cbox(Vector3(0.02, yb + 1.25, 0.04), Vector3(0.09, 0.82, 0.08), 0.02)
	d.cbox(Vector3(0.02, yb + 1.25, 1.0), Vector3(0.09, 0.82, 0.08), 0.02)
	d.cbox(Vector3(0.02, yb + 1.68, 0.52), Vector3(0.09, 0.08, 1.0), 0.02)
	d.emit(pivot, black, "Door")
	var dg := MK.new()
	dg.cbox(Vector3(0.0, yb + 1.26, 0.52), Vector3(0.06, 0.74, 0.88), 0.005)   # dickes Panzerglas
	dg.emit(pivot, _glass(), "DoorGlass").cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dc := MK.new()
	dc.cbox(Vector3(-0.06, yb + 0.72, 0.85), Vector3(0.03, 0.04, 0.16), 0.01)
	dc.emit(pivot, chrome, "Handle")
	# Panzerglas-/Tuer-Kollision: haengt an der Tuer, deckt Weber dahinter ab (Kugeln -> Metall)
	var shield := StaticBody3D.new()
	shield.name = "ArmorShield"
	shield.collision_layer = 1
	shield.collision_mask = 0
	shield.set_meta("surface", "metal")
	shield.set_meta("no_fit", true)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.14, 2.2, 1.12)
	cs.shape = bs
	cs.position = Vector3(0.0, 1.1, 0.52)
	shield.add_child(cs)
	pivot.add_child(shield)
	root.set_meta("door_pivot", pivot)
	root.set_meta("shield", shield)
	_collider(root, [[Vector3(0, yb + 0.55, 0), Vector3(1.98, 1.1, 4.95)], [Vector3(0, yb + 1.3, 0.7), Vector3(1.86, 0.85, 3.3)]])
	return root

## Raeder drehen: Weg in Metern.
static func set_spin(v: Node3D, travelled: float) -> void:
	var m: ShaderMaterial = v.get_meta("wheel_mat", null)
	if m != null:
		m.set_shader_parameter("spin", travelled)
