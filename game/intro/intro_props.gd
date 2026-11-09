extends RefCounted
## Requisiten fuer das Kampagnen-Intro: einfache Fahrzeug-Silhouetten (Fallback, falls die echten
## Fahrzeuge aus game/vehicles/ fehlen), Grenzposten, Raketen. Alle Funktionen statisch.

const Geo = preload("res://game/levels/level_geo.gd")
const NightProps = preload("res://game/levels/night_props.gd")

const TANK_SCENE := "res://game/vehicles/tank.tscn"
const HELI_SCENE := "res://game/vehicles/helicopter.tscn"
const JET_SCENE := "res://game/vehicles/jet_flyby.tscn"

static var _smoke_mat: StandardMaterial3D

## Laedt eine Fahrzeugszene, falls vorhanden (sonst null). Gibt ein noch nicht eingehaengtes Node zurueck.
static func try_vehicle(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	return ps.instantiate() as Node3D

# --------------------------------------------------------------------------- Lichter

static func headlight(parent: Node3D, pos: Vector3, energy: float = 6.0, rng_m: float = 32.0, shadow: bool = false) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.93, 0.78)
	l.light_energy = energy
	l.spot_range = rng_m
	l.spot_angle = 32.0
	l.spot_attenuation = 1.2
	l.light_volumetric_fog_energy = 2.5
	l.shadow_enabled = shadow
	l.position = pos
	l.rotation_degrees = Vector3(-6, 0, 0)
	parent.add_child(l)
	return l

static func lamp_pair(parent: Node3D, z: float, half_w: float, y: float) -> void:
	var m := NightProps.glow(Color(1.0, 0.92, 0.75), 14.0)
	for sx: float in [-1.0, 1.0]:
		parent.add_child(Geo.box_mesh_node(Vector3(0.22, 0.14, 0.06), m, Vector3(sx * half_w, y, z)))

# --------------------------------------------------------------------------- Fahrzeuge (Silhouetten, Front = -Z)

## Kampfpanzer-Silhouette. lights: Scheinwerfer + Spotlicht.
static func tank(tint: Color = Color(0.28, 0.3, 0.25), lights: bool = true, shadow_light: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = "TankSil"
	var hull := Geo.batch()
	hull.add(Vector3(0, 1.0, 0.2), Vector3(3.3, 0.8, 6.4))
	hull.add(Vector3(0, 0.95, -3.2), Vector3(3.3, 0.55, 1.0), Basis(Vector3.RIGHT, 0.5))
	hull.add(Vector3(0, 1.75, 0.6), Vector3(2.5, 0.75, 3.0))       # Turm
	hull.add(Vector3(0, 1.85, 2.3), Vector3(2.1, 0.55, 0.9))       # Turmheck
	hull.add(Vector3(0.6, 2.25, 0.9), Vector3(0.6, 0.25, 0.7))     # Kommandantenkuppel
	var m := NightProps.metal(tint, 0.35)
	NightProps.add_batch(root, hull, m)
	var tracks := Geo.batch()
	for sx: float in [-1.0, 1.0]:
		tracks.add(Vector3(sx * 1.55, 0.45, 0.1), Vector3(0.65, 0.9, 6.8))
	NightProps.add_batch(root, tracks, NightProps.metal(Color(0.12, 0.12, 0.11), 0.5))
	var barrel := Geo.cylinder_node(0.09, 5.2, m, Vector3(0, 1.8, -3.4), Vector3(90, 0, 0), 8)
	root.add_child(barrel)
	if lights:
		lamp_pair(root, -3.75, 1.2, 1.05)
		headlight(root, Vector3(0, 1.2, -3.9), 7.0, 38.0, shadow_light)
	return root

static func truck(tint: Color = Color(0.36, 0.38, 0.36), stripe: Color = Color(0.1, 0.25, 0.65)) -> Node3D:
	var root := Node3D.new()
	root.name = "TruckSil"
	var b := Geo.batch()
	b.add(Vector3(0, 1.55, -2.6), Vector3(2.4, 1.5, 1.8))      # Fuehrerhaus
	b.add(Vector3(0, 0.75, 0.3), Vector3(2.3, 0.35, 6.6))      # Rahmen
	var m := NightProps.metal(tint, 0.3)
	NightProps.add_batch(root, b, m)
	var cover := Geo.batch()
	cover.add(Vector3(0, 1.95, 1.0), Vector3(2.5, 2.0, 4.6))   # Plane
	NightProps.add_batch(root, cover, NightProps.metal(tint * 0.8, 0.5))
	# Kennung: blaues Band (keine realen Embleme)
	var sm := Geo.flat(stripe, 0.6, 0.0, stripe, 0.4)
	for sx: float in [-1.0, 1.0]:
		root.add_child(Geo.box_mesh_node(Vector3(0.02, 0.35, 2.2), sm, Vector3(sx * 1.26, 2.2, 1.0)))
	var wheels := Geo.batch()
	for z: float in [-2.6, 0.6, 2.2]:
		for sx: float in [-1.0, 1.0]:
			wheels.add(Vector3(sx * 1.05, 0.5, z), Vector3(0.4, 1.0, 1.0))
	NightProps.add_batch(root, wheels, NightProps.metal(Color(0.08, 0.08, 0.08), 0.4))
	lamp_pair(root, -3.52, 0.95, 1.0)
	headlight(root, Vector3(0, 1.1, -3.6), 5.0, 30.0)
	return root

static func jet(tint: Color = Color(0.45, 0.48, 0.52)) -> Node3D:
	var root := Node3D.new()
	root.name = "JetSil"
	var b := Geo.batch()
	b.add(Vector3(0, 0, 0), Vector3(1.4, 1.2, 14.0))
	b.add(Vector3(0, 0, 1.8), Vector3(10.0, 0.18, 4.0))
	b.add(Vector3(0, 0, -3.0), Vector3(3.0, 0.12, 1.6))
	b.add(Vector3(0, 1.4, 5.6), Vector3(0.18, 2.6, 2.2), Basis(Vector3.RIGHT, -0.35))
	b.add(Vector3(0, 0.55, -3.6), Vector3(0.8, 0.5, 2.2))
	NightProps.add_batch(root, b, Geo.flat(tint, 0.5, 0.4), false)
	var ab := Geo.flat(Color(0.1, 0.05, 0.02), 0.8, 0.0, Color(1.0, 0.55, 0.2), 12.0)
	root.add_child(Geo.box_mesh_node(Vector3(1.0, 0.9, 0.5), ab, Vector3(0, 0, 7.2)))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 4.0
	l.omni_range = 14.0
	l.position = Vector3(0, 0, 8.0)
	root.add_child(l)
	for sx: float in [-1.0, 1.0]:
		var nav := Geo.flat(Color.BLACK, 0.5, 0.0, Color(1, 0.1, 0.1) if sx < 0 else Color(0.1, 1, 0.2), 10.0)
		root.add_child(Geo.box_mesh_node(Vector3(0.25, 0.25, 0.25), nav, Vector3(sx * 5.0, 0.1, 1.8)))
	return root

static func heli(tint: Color = Color(0.25, 0.27, 0.24)) -> Node3D:
	var root := Node3D.new()
	root.name = "HeliSil"
	var b := Geo.batch()
	b.add(Vector3(0, 0, 0), Vector3(1.8, 2.0, 5.0))
	b.add(Vector3(0, 0.3, 5.0), Vector3(0.5, 0.6, 6.0))
	b.add(Vector3(0, 1.2, 7.8), Vector3(0.15, 2.0, 1.2))
	b.add(Vector3(0, 1.25, 0), Vector3(0.5, 0.4, 0.5))
	NightProps.add_batch(root, b, Geo.flat(tint, 0.6, 0.2), false)
	var rotor := Geo.cylinder_node(6.5, 0.04, Geo.flat(Color(0.05, 0.05, 0.05, 0.35), 0.9), Vector3(0, 1.5, 0), Vector3.ZERO, 24)
	var rm := rotor.material_override as StandardMaterial3D
	if rm != null:
		rm = rm.duplicate() as StandardMaterial3D
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rotor.material_override = rm
	root.add_child(rotor)
	var bl := Geo.flat(Color.BLACK, 0.5, 0.0, Color(1, 0.15, 0.1), 14.0)
	root.add_child(Geo.box_mesh_node(Vector3(0.2, 0.2, 0.2), bl, Vector3(0, -1.05, 0)))
	return root

# --------------------------------------------------------------------------- Grenzposten

static func border_post(parent: Node3D, rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	root.name = "BorderPost"
	parent.add_child(root)
	# Wachhaeuschen
	NightProps.house(root, Vector3(-5.5, 0, 0), 0.0, Vector3(3.0, 2.6, 2.6), Color(0.62, 0.6, 0.55), rng)
	var win := Geo.flat(Color(0.05, 0.04, 0.03), 0.4, 0.0, Color(1.0, 0.75, 0.42), 2.5)
	root.add_child(Geo.box_mesh_node(Vector3(1.4, 0.8, 0.05), win, Vector3(-5.5, 1.5, -1.33)))
	var inner := OmniLight3D.new()
	inner.light_color = Color(1.0, 0.72, 0.4)
	inner.light_energy = 1.6
	inner.omni_range = 6.0
	inner.position = Vector3(-5.5, 1.6, -2.0)
	root.add_child(inner)
	# Schlagbaum rot/weiss (Segmente)
	var arm := Node3D.new()
	arm.position = Vector3(-3.6, 1.05, -1.6)
	root.add_child(arm)
	var red := Geo.flat(Color(0.7, 0.08, 0.06), 0.5)
	var white := Geo.flat(Color(0.85, 0.85, 0.82), 0.5)
	for i in 8:
		arm.add_child(Geo.box_mesh_node(Vector3(0.9, 0.14, 0.14), red if i % 2 == 0 else white, Vector3(0.45 + i * 0.9, 0, 0)))
	root.add_child(Geo.box_mesh_node(Vector3(0.4, 1.0, 0.4), NightProps.concrete(Color(0.5, 0.5, 0.48), 0.5), Vector3(-3.6, 0.5, -1.6)))
	# Laternenmast mit Natriumlicht
	var pole_m := NightProps.metal(Color(0.3, 0.3, 0.3), 0.3)
	root.add_child(Geo.box_mesh_node(Vector3(0.18, 6.5, 0.18), pole_m, Vector3(5.5, 3.25, -2.5)))
	root.add_child(Geo.box_mesh_node(Vector3(1.6, 0.12, 0.12), pole_m, Vector3(4.9, 6.4, -2.5)))
	root.add_child(Geo.box_mesh_node(Vector3(0.5, 0.15, 0.3), NightProps.glow(Color(1.0, 0.7, 0.35), 10.0), Vector3(4.2, 6.3, -2.5)))
	var sl := SpotLight3D.new()
	sl.light_color = Color(1.0, 0.68, 0.36)
	sl.light_energy = 9.0
	sl.spot_range = 16.0
	sl.spot_angle = 55.0
	sl.light_volumetric_fog_energy = 2.0
	sl.shadow_enabled = true
	sl.position = Vector3(4.2, 6.2, -2.5)
	sl.rotation_degrees = Vector3(-90, 0, 0)
	root.add_child(sl)
	# Flaggenmast (Lettland: karminrot-weiss-karminrot, Nationalflagge, kein Logo)
	root.add_child(Geo.box_mesh_node(Vector3(0.08, 7.0, 0.08), pole_m, Vector3(-8.5, 3.5, -0.5)))
	var carmine := Geo.flat(Color(0.45, 0.07, 0.1), 0.8)
	var flag := Node3D.new()
	flag.name = "Flag"
	flag.position = Vector3(-8.5, 6.2, -0.5)
	root.add_child(flag)
	flag.add_child(Geo.box_mesh_node(Vector3(1.6, 0.32, 0.02), carmine, Vector3(0.8, 0.32, 0)))
	flag.add_child(Geo.box_mesh_node(Vector3(1.6, 0.16, 0.02), white, Vector3(0.8, 0.08, 0)))
	flag.add_child(Geo.box_mesh_node(Vector3(1.6, 0.32, 0.02), carmine, Vector3(0.8, -0.16, 0)))
	# Schild
	var sign := Label3D.new()
	sign.text = "LATVIJAS REPUBLIKA\nVALSTS ROBEŽA"
	sign.font_size = 64
	sign.pixel_size = 0.006
	sign.modulate = Color(0.85, 0.85, 0.8)
	sign.outline_size = 0
	sign.position = Vector3(1.8, 2.5, -2.0)
	root.add_child(sign)
	var board := Geo.box_mesh_node(Vector3(2.4, 0.8, 0.06), Geo.flat(Color(0.08, 0.15, 0.4), 0.6), Vector3(1.8, 2.5, -1.95))
	root.add_child(board)
	root.add_child(Geo.box_mesh_node(Vector3(0.1, 2.5, 0.1), pole_m, Vector3(1.0, 1.25, -1.9)))
	root.add_child(Geo.box_mesh_node(Vector3(0.1, 2.5, 0.1), pole_m, Vector3(2.6, 1.25, -1.9)))
	# Zaun mit Stacheldraht nach links und rechts
	for side: float in [-1.0, 1.0]:
		var x0: float = -9.5 if side < 0 else 7.0
		NightProps.wire(root, Vector3(x0, 0, -1.0), Vector3(x0 + side * 40.0, 0, -1.6), false)
	# Panzersperren (Hoeckerlinie)
	var tb := Geo.batch()
	for i in 14:
		var x := 9.0 + i * 1.7
		tb.add(Vector3(x, 0.45, -5.0 + sin(i * 1.3) * 0.4), Vector3(0.9, 0.9, 0.9), Basis(Vector3.UP, 0.785))
		tb.add(Vector3(-12.0 - i * 1.7, 0.45, -5.0 + cos(i * 1.1) * 0.4), Vector3(0.9, 0.9, 0.9), Basis(Vector3.UP, 0.785))
	NightProps.add_batch(root, tb, NightProps.concrete(Color(0.55, 0.55, 0.52), 0.6))
	return {"root": root, "flag": flag}

# --------------------------------------------------------------------------- Raketen

static func smoke_mat() -> StandardMaterial3D:
	if _smoke_mat != null:
		return _smoke_mat
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1, 1, 1, 1)
	var g := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 1))
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 64
	g.height = 64
	m.albedo_texture = g
	_smoke_mat = m
	return m

## Rakete mit Flamme, Licht und Rauchspur. Fliegt entlang +Y des Knotens (Knoten rotieren).
static func missile() -> Node3D:
	var root := Node3D.new()
	root.name = "Missile"
	var body := Geo.cylinder_node(0.35, 6.0, Geo.flat(Color(0.6, 0.6, 0.58), 0.5, 0.3), Vector3(0, 0, 0), Vector3.ZERO, 10)
	root.add_child(body)
	var flame := Geo.flat(Color(0.1, 0.05, 0.0), 0.8, 0.0, Color(1.0, 0.75, 0.35), 40.0)
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.7
	sm.height = 3.2
	core.mesh = sm
	core.material_override = flame
	core.position = Vector3(0, -4.2, 0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.light_energy = 22.0
	l.omni_range = 120.0
	l.omni_attenuation = 1.4
	l.light_volumetric_fog_energy = 4.0
	l.position = Vector3(0, -5.0, 0)
	root.add_child(l)
	# Rauchspur (Weltkoordinaten)
	var p := GPUParticles3D.new()
	p.amount = 260
	p.lifetime = 6.0
	p.local_coords = false
	p.position = Vector3(0, -4.5, 0)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 8.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(1.2, 0.4, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 2.5
	pm.scale_max = 4.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 3.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var gr := Gradient.new()
	gr.set_color(0, Color(1.0, 0.75, 0.45, 0.9))
	gr.add_point(0.08, Color(0.75, 0.72, 0.7, 0.55))
	gr.set_color(gr.get_point_count() - 1, Color(0.5, 0.5, 0.52, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = smoke_mat()
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))
	root.add_child(p)
	return root
