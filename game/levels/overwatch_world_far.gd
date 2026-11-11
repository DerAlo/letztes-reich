extends RefCounted
## Level 7 "Kaltes Auge": Kuehlturm (Hyperboloid mit Ringsteg, Scharfschuetze A), Schornstein mit
## Ringpodest (Scharfschuetze B), Schlackenhalden und Hintergrund-Silhouetten (Walzwerk, Gasometer,
## Bandbruecken, Portalkrane). Statische Funktionen.

const K = preload("res://game/levels/overwatch_world_kit.gd")
const RailProps = preload("res://game/levels/rail_props.gd")
const Yard = preload("res://game/levels/overwatch_world_yard.gd")

const CT := Vector3(-120.0, 0.0, -230.0)
const STACK := Vector3(100.0, 0.0, -215.0)

static func build(world: Node3D, covers: Array, rng: RandomNumberGenerator, pts: Dictionary) -> void:
	pts["sniper_a"] = _cooling_tower(world)
	pts["sniper_b"] = _stack(world)
	_slag_heaps(world, rng)
	_background(world, rng)

static func _ct_r(h: float) -> float:
	return 17.0 * sqrt(1.0 + pow((h - 50.0) / 38.2, 2.0))

# ------------------------------------------------------------------ Kuehlturm

static func _cooling_tower(world: Node3D) -> Vector3:
	var b := K.body(world, "CoolingTower", true)
	var vis := Node3D.new()
	vis.name = "CoolingTowerVisual"
	world.add_child(vis)
	var shell := K.tower_concrete()
	# Schale: aussen aufwaerts, Krempe, innen abwaerts (beidseitig sichtbar, eine Huelle)
	var prof: Array = []
	var h0 := 8.0
	var steps := 18
	for i in steps + 1:
		var h := h0 + (68.0 - h0) * float(i) / steps
		prof.append(Vector2(_ct_r(h), h))
	prof.append(Vector2(_ct_r(68.0) - 0.45, 68.0))
	for i in range(steps, -1, -1):
		var h := h0 + (68.0 - h0) * float(i) / steps
		prof.append(Vector2(_ct_r(h) - 0.45, h))
	prof.append(Vector2(_ct_r(h0), h0))
	var mesh := K.lathe(prof, 56)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = shell
	mi.position = CT
	vis.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	cs.position = CT
	b.add_child(cs)
	var k := RailProps.kit()
	var kd := RailProps.kit()
	# V-Stuetzen (Diagonalpaare) zwischen Fundamentring und Schalenfuss
	var n := 36
	var rb := _ct_r(h0) - 0.2
	var cm := K.concrete(Color(0.66, 0.64, 0.6))
	for i in n:
		var a := TAU * float(i) / n
		var a1 := TAU * (float(i) + 0.5) / n
		var a2 := TAU * (float(i) - 0.5) / n
		var foot := CT + Vector3(cos(a), 0, sin(a)) * (rb + 0.8)
		K.beam(k, "vcol", cm, foot, CT + Vector3(cos(a1), 0, sin(a1)) * rb + Vector3(0, h0, 0), 0.7)
		K.beam(k, "vcol", cm, foot, CT + Vector3(cos(a2), 0, sin(a2)) * rb + Vector3(0, h0, 0), 0.7)
	K.torus(k, "vcol", cm, CT + Vector3(0, 0.3, 0), rb + 0.8, 0.6, Basis.IDENTITY, 56)
	# Innen: Wasserbecken (dunkel) und Einbauten
	k.b("basin", K.puddle()).add(CT + Vector3(0, 0.05, 0), Vector3(rb * 1.6, 0.05, rb * 1.6))
	# Ringsteg oben (y 68, r 18.4 .. 19.8) mit Gelaendern innen/aussen, Kollision als Segmente
	var r_in := 18.4
	var r_out := 19.8
	var ns := 48
	var rm := K.rail_yellow()
	var gm := K.grating()
	for i in ns:
		var a0 := TAU * float(i) / ns
		var a1 := TAU * float(i + 1) / ns
		var am := (a0 + a1) * 0.5
		var dir := Vector3(cos(am), 0, sin(am))
		var rot := Basis(Vector3.UP, -am)
		var rc := (r_in + r_out) * 0.5
		var seg_len := 2.0 * r_out * sin((a1 - a0) * 0.5) + 0.05
		K.box(kd, "ring", gm, CT + dir * rc + Vector3(0, 67.92, 0), Vector3(r_out - r_in, 0.16, seg_len), rot, b)
		kd.b("ring_frame", K.dark_steel()).add(CT + dir * (r_out - 0.04) + Vector3(0, 67.75, 0), Vector3(0.08, 0.3, seg_len), rot)
		var p0o := CT + Vector3(cos(a0), 0, sin(a0)) * (r_out - 0.06) + Vector3(0, 68.0, 0)
		var p1o := CT + Vector3(cos(a1), 0, sin(a1)) * (r_out - 0.06) + Vector3(0, 68.0, 0)
		var p0i := CT + Vector3(cos(a0), 0, sin(a0)) * (r_in + 0.06) + Vector3(0, 68.0, 0)
		var p1i := CT + Vector3(cos(a1), 0, sin(a1)) * (r_in + 0.06) + Vector3(0, 68.0, 0)
		K.railing(kd, rm, p0o, p1o, b)
		K.railing(kd, rm, p0i, p1i, b)
		# Konsolen unter dem Steg
		if i % 2 == 0:
			K.beam(kd, "ring_frame", K.dark_steel(), CT + dir * (_ct_r(66.0) - 0.1) + Vector3(0, 66.0, 0), CT + dir * (r_out - 0.1) + Vector3(0, 67.7, 0), 0.12)
	K.flush(k, vis, true, 0.0)
	K.flush(kd, vis, false, 0.0)
	# Grosse, langsame Dampffahne
	K.steam(world, CT + Vector3(0, 66.0, 0), 11.0, 24.0, 1.4, 46.0, 34, 1.0, 0.2, Color(0.88, 0.88, 0.9))
	K.steam(world, CT + Vector3(0, 60.0, 0), 13.0, 16.0, 0.9, 20.0, 14, 0.4, 0.14, Color(0.85, 0.86, 0.88))
	return Vector3(-111.4, 68.0, -212.7)

# ------------------------------------------------------------------ Schornstein

static func _stack(world: Node3D) -> Vector3:
	var b := K.body(world, "Stack", true)
	var vis := Node3D.new()
	vis.name = "StackVisual"
	world.add_child(vis)
	var prof: Array = [Vector2(4.6, 0.0), Vector2(4.6, 2.0), Vector2(4.0, 2.2)]
	for i in range(1, 9):
		var h := 2.2 + (80.0 - 2.2) * float(i) / 8.0
		prof.append(Vector2(4.0 + (2.8 - 4.0) * (h / 80.0), h))
	prof.append(Vector2(3.05, 80.0))
	prof.append(Vector2(3.05, 81.0))
	prof.append(Vector2(2.4, 81.0))
	prof.append(Vector2(2.4, 78.0))
	var conc := K.concrete(Color(0.7, 0.68, 0.64))
	var mesh := K.lathe(prof, 32)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = conc
	mi.position = STACK
	vis.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	cs.position = STACK
	b.add_child(cs)
	var k := RailProps.kit()
	# Rot-weisse Warnbaender
	var red := K.paint(Color(0.55, 0.14, 0.1))
	for i in 3:
		var y0 := 66.0 + i * 5.0
		var r0 := 4.0 + (2.8 - 4.0) * (y0 / 80.0)
		K.cone(k, "bands", red, STACK + Vector3(0, y0, 0), 2.5, r0 + 0.04, r0 + 0.04 - 0.0375, 32)
	# Ringpodest y 30 (r 3.5 .. 5.5), Gelaender r 5.4, Konsolen
	var ns := 24
	var gm := K.grating()
	var rm := K.rail_yellow()
	for i in ns:
		var a0 := TAU * float(i) / ns
		var a1 := TAU * float(i + 1) / ns
		var am := (a0 + a1) * 0.5
		var dir := Vector3(cos(am), 0, sin(am))
		var seg_len := 2.0 * 5.5 * sin((a1 - a0) * 0.5) + 0.05
		K.box(k, "plat", gm, STACK + dir * 4.5 + Vector3(0, 29.92, 0), Vector3(2.0, 0.16, seg_len), Basis(Vector3.UP, -am), b)
		var p0 := STACK + Vector3(cos(a0), 0, sin(a0)) * 5.4 + Vector3(0, 30.0, 0)
		var p1 := STACK + Vector3(cos(a1), 0, sin(a1)) * 5.4 + Vector3(0, 30.0, 0)
		K.railing(k, rm, p0, p1, b)
		if i % 2 == 0:
			K.beam(k, "brk", K.dark_steel(), STACK + dir * 3.6 + Vector3(0, 28.0, 0), STACK + dir * 5.4 + Vector3(0, 29.8, 0), 0.14)
	# Zweites (kleines) Podest oben und Steigleiter
	K.torus(k, "plat", gm, STACK + Vector3(0, 74.0, 0), 3.6, 0.5, Basis.IDENTITY, 28)
	K.ladder(k, K.dark_steel(), STACK + Vector3(0, 0, 3.75), 74.0, Vector3(0, 0, -1), true)
	# Fuchs (Rauchgaskanal) am Fuss
	k.b("flue", K.brick(Color(0.58, 0.46, 0.4))).add(STACK + Vector3(-9.0, 2.5, 0), Vector3(12.0, 5.0, 4.0))
	K.col(b, STACK + Vector3(-9.0, 2.5, 0), Vector3(12.0, 5.0, 4.0))
	K.flush(k, vis, true, 0.0)
	K.steam(world, STACK + Vector3(0, 82.0, 0), 1.6, 8.0, 1.6, 26.0, 18, 1.5, 0.18, Color(0.8, 0.8, 0.82))
	return Vector3(100.0, 30.0, -210.5)

# ------------------------------------------------------------------ Schlackenhalden

static func _slag_heaps(world: Node3D, rng: RandomNumberGenerator) -> void:
	var m := K.slag()
	var specs: Array = [
		[Vector3(-190.0, 0, -60.0), 45.0, 22.0, 1.5], [Vector3(-240.0, 0, -150.0), 60.0, 34.0, 1.3],
		[Vector3(-170.0, 0, -260.0), 50.0, 26.0, 1.6], [Vector3(-260.0, 0, -300.0), 55.0, 30.0, 1.2],
		[Vector3(200.0, 0, -80.0), 50.0, 24.0, 1.4], [Vector3(250.0, 0, -190.0), 65.0, 38.0, 1.3],
		[Vector3(180.0, 0, -290.0), 45.0, 22.0, 1.7],
	]
	for s: Array in specs:
		Yard.pile(world, s[0], float(s[1]), float(s[2]), float(s[3]), rng.randf_range(0, 180), m, rng, false)

# ------------------------------------------------------------------ Hintergrund

static func _background(world: Node3D, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "Background"
	world.add_child(root)
	var k := RailProps.kit()
	var st := K.rust(Color(0.42, 0.36, 0.32))
	var wall := K.corr(Color(0.42, 0.4, 0.38))
	# Walzwerk: lange Hallen hinter dem Kuehlturm / Schornstein (einfache Silhouetten)
	for h: Array in [[Vector3(-10.0, 0, -270.0), Vector3(120.0, 24.0, 40.0)], [Vector3(180.0, 0, -250.0), Vector3(80.0, 20.0, 36.0)], [Vector3(-230.0, 0, -220.0), Vector3(70.0, 22.0, 40.0)], [Vector3(-180.0, 0, 40.0), Vector3(60.0, 26.0, 40.0)], [Vector3(140.0, 0, 30.0), Vector3(70.0, 22.0, 34.0)]]:
		var c: Vector3 = h[0]
		var s: Vector3 = h[1]
		k.b("bg_wall", wall).add(c + Vector3(0, s.y * 0.5, 0), s)
		k.b("bg_roof", K.dark_steel()).add(c + Vector3(0, s.y + 1.2, 0), Vector3(s.x + 1.0, 2.4, s.z * 0.55))
		var x := -s.x * 0.5 + 6.0
		while x < s.x * 0.5:
			k.b("bg_roof", K.dark_steel()).add(c + Vector3(x, s.y + 3.4, 0), Vector3(2.0, 2.0, s.z * 0.4))
			x += 14.0
	# Gasometer (Scheibengasbehaelter) mit Fuehrungsgeruest
	var gc := Vector3(-60.0, 0, -300.0)
	K.lathe_node(root, [Vector2(22.0, 0.0), Vector2(22.0, 46.0), Vector2(18.0, 48.0), Vector2(0.01, 50.0)], K.paint(Color(0.38, 0.4, 0.38)), gc, 40, false)
	for i in 16:
		var a := TAU * float(i) / 16.0
		var p := gc + Vector3(cos(a), 0, sin(a)) * 22.3
		k.b("bg_frame", st).add(p + Vector3(0, 24.0, 0), Vector3(0.8, 48.0, 0.8))
	for y: float in [12.0, 24.0, 36.0, 47.0]:
		K.torus(k, "bg_frame", st, gc + Vector3(0, y, 0), 22.4, 0.3, Basis.IDENTITY, 40)
	# Bandbruecken (schraeg) zwischen Hallen und Halden
	for br: Array in [[Vector3(-160.0, 2.0, -40.0), Vector3(-110.0, 30.0, -20.0)], [Vector3(150.0, 2.0, -120.0), Vector3(120.0, 28.0, -60.0)], [Vector3(30.0, 4.0, -250.0), Vector3(70.0, 34.0, -225.0)]]:
		var a: Vector3 = br[0]
		var e: Vector3 = br[1]
		var d := e - a
		var rot := K.basis_z(d)
		k.b("bg_gal", wall).add((a + e) * 0.5 + rot.y * 1.4, Vector3(3.4, 2.8, d.length()), rot)
		K.truss(k, "bg_frame", st, a + rot.x * 1.7 - Vector3(0, 1.2, 0), e + rot.x * 1.7 - Vector3(0, 1.2, 0), 1.2, 4.0, 0.2, null, false)
		for t: float in [0.33, 0.66]:
			var p := a + d * t
			k.b("bg_frame", st).add(Vector3(p.x, p.y * 0.5, p.z), Vector3(1.6, p.y, 1.6))
		var top_house := e + Vector3(0, 2.0, 0)
		k.b("bg_wall", wall).add(top_house, Vector3(8.0, 8.0, 8.0))
		k.b("bg_frame", st).add(Vector3(e.x, e.y * 0.5 - 1.0, e.z), Vector3(5.0, e.y - 2.0, 5.0))
	# Portalkrane ueber dem Erzlager (links) und rechts
	for cr: Array in [[Vector3(-150.0, 0, -110.0), 0.0], [Vector3(160.0, 0, -20.0), 90.0]]:
		var c2: Vector3 = cr[0]
		var rot2 := K.yaw_b(float(cr[1]))
		for sx: float in [-18.0, 18.0]:
			for sz: float in [-4.0, 4.0]:
				K.beam(k, "bg_crane", K.paint(Color(0.55, 0.42, 0.18)), c2 + rot2 * Vector3(sx, 0, sz), c2 + rot2 * Vector3(sx * 0.92, 22.0, sz * 0.4), 0.9)
		k.b("bg_crane", K.paint(Color(0.55, 0.42, 0.18))).add(c2 + rot2 * Vector3(0, 23.0, 0), Vector3(54.0, 2.4, 3.0), rot2)
		k.b("bg_crane", K.paint(Color(0.55, 0.42, 0.18))).add(c2 + rot2 * Vector3(6.0, 25.5, 0), Vector3(5.0, 3.0, 4.0), rot2)
	# Strommasten (Silhouette) im Westen und Sueden
	for i in 6:
		var p2 := Vector3(-300.0 + i * 120.0, 0, -360.0 + rng.randf_range(-10, 10))
		for sx2: float in [-3.0, 3.0]:
			K.beam(k, "bg_mast", st, p2 + Vector3(sx2, 0, 0), p2 + Vector3(sx2 * 0.2, 36.0, 0), 0.5)
		k.b("bg_mast", st).add(p2 + Vector3(0, 30.0, 0), Vector3(16.0, 0.6, 0.6))
		k.b("bg_mast", st).add(p2 + Vector3(0, 24.0, 0), Vector3(12.0, 0.6, 0.6))
	K.flush(k, root, false, 0.0)
