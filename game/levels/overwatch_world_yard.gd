extends RefCounted
## Level 7 "Kaltes Auge": Werkhof (Spawn mit Containern + Widerstands-Transporter), Hofflaeche mit
## Halden, Rohrbruecke mit Laufsteg, Schuppen, Gleisanlage (entlang X), Strasse mit Leitplanken,
## Durchlass (IED), Zaun und Werksbauten suedlich der Strasse. Statische Funktionen.

const K = preload("res://game/levels/overwatch_world_kit.gd")
const RailProps = preload("res://game/levels/rail_props.gd")
const Props = preload("res://game/levels/level_props.gd")
const Geo = preload("res://game/levels/level_geo.gd")

const ROAD_Z := -140.0
const ROAD_W := 9.0

static func build(world: Node3D, covers: Array, rng: RandomNumberGenerator, pts: Dictionary) -> void:
	_spawn_yard(world, covers, rng)
	van(world, Vector3(-30.0, 0.0, -92.0), 180.0, Color(0.27, 0.3, 0.27), true)
	_yard(world, covers, rng)
	pts["catwalk"] = _pipe_rack(world, covers)
	pts["shed_roof"] = _shed(world, covers, Vector3(60.0, 0.0, -80.0))
	pts["friendly_cover"] = _sidings(world, covers, rng)
	var rr: Dictionary = _road(world, covers, rng)
	pts["enemy_cover"] = rr["enemy"]
	_south_works(world, covers, rng)
	pts["player_spawn"] = Vector3(3.0, 0.1, 30.0)
	pts["van"] = Vector3(-30.0, 0.0, -92.0)
	pts["ied"] = Vector3(-5.0, 0.0, ROAD_Z)
	pts["road_z"] = ROAD_Z
	pts["convoy_stops"] = [Vector3(-5.0, 0, ROAD_Z), Vector3(10.0, 0, ROAD_Z), Vector3(26.0, 0, ROAD_Z)]
	pts["weber_stop"] = Vector3(75.0, 0.0, -142.0)

# ------------------------------------------------------------------ Transporter (Bulli-Form)

## Kastenwagen im Stil eines T3/T4-Transporters, Front zeigt nach lokal -Z. team = Dachtraeger + Antenne.
static func van(world: Node3D, pos: Vector3, yaw: float, color: Color, team: bool) -> StaticBody3D:
	var b := Geo.static_body(pos, yaw)
	b.name = "TeamVan" if team else "ResistanceVan"
	world.add_child(b)
	var k := RailProps.kit()
	var body := K.paint(color)
	var dark := K.black()
	var trim := K.paint(Color(0.12, 0.12, 0.12))
	var gl := K.glass()
	var L := 4.9
	var W := 1.86
	var hz := L * 0.5
	# Unterbau + Aufbau (leicht eingezogen), Front: kurze Schnauze + schraege Scheibe
	k.b("vbody", body).add(Vector3(0, 0.78, 0.25), Vector3(W, 0.9, L - 0.5))
	k.b("vbody", body).add(Vector3(0, 1.55, 0.35), Vector3(W - 0.06, 0.66, L - 0.7))
	k.b("vbody", body).add(Vector3(0, 1.9, 0.4), Vector3(W - 0.16, 0.06, L - 0.85))
	k.b("vbody", body).add(Vector3(0, 0.7, -hz + 0.3), Vector3(W - 0.04, 0.72, 0.6))
	k.b("vbody", body).add(Vector3(0, 1.13, -hz + 0.42), Vector3(W - 0.08, 0.12, 0.85), Basis(Vector3.RIGHT, -0.18))
	k.b("vglass", gl).add(Vector3(0, 1.55, -hz + 0.82), Vector3(W - 0.2, 0.68, 0.04), Basis(Vector3.RIGHT, -0.38))
	# A-Saeulen
	for s: float in [-1.0, 1.0]:
		k.b("vbody", body).add(Vector3(s * (W * 0.5 - 0.06), 1.55, -hz + 0.82), Vector3(0.1, 0.72, 0.08), Basis(Vector3.RIGHT, -0.38))
	# Fenster: Fahrer-/Beifahrertuer, Seitenfensterband (Team: hinten dunkel), Heck
	for s: float in [-1.0, 1.0]:
		k.b("vglass", gl).add(Vector3(s * (W * 0.5 - 0.02), 1.58, -hz + 1.35), Vector3(0.03, 0.5, 0.8))
		if not team:
			k.b("vglass", gl).add(Vector3(s * (W * 0.5 - 0.02), 1.6, 0.6), Vector3(0.03, 0.46, 2.2))
		k.b("vtrim", trim).add(Vector3(s * (W * 0.5 + 0.005), 1.22, 0.25), Vector3(0.02, 0.05, L - 0.6))
		# Tuerfugen
		k.b("vtrim", trim).add(Vector3(s * (W * 0.5 + 0.004), 1.15, -hz + 1.85), Vector3(0.01, 1.4, 0.015))
		k.b("vtrim", trim).add(Vector3(s * (W * 0.5 + 0.004), 1.15, -0.4), Vector3(0.01, 1.4, 0.015))
		# Radlaeufe + Raeder
		for z: float in [-hz + 0.95, hz - 0.85]:
			K.pipe(k, "vtyre", dark, Vector3(s * (W * 0.5 - 0.3), 0.34, z), Vector3(s * (W * 0.5 + 0.02), 0.34, z), 0.34, 16)
			K.pipe(k, "vhub", K.paint(Color(0.5, 0.5, 0.48)), Vector3(s * (W * 0.5 + 0.0), 0.34, z), Vector3(s * (W * 0.5 + 0.03), 0.34, z), 0.18, 12)
			k.b("vtrim", trim).add(Vector3(s * (W * 0.5 - 0.1), 0.72, z), Vector3(0.22, 0.08, 0.9))
	k.b("vglass", gl).add(Vector3(0, 1.6, hz - 0.01), Vector3(W - 0.4, 0.5, 0.03))
	# Stossfaenger, Kuehlergrill, Scheinwerfer, Rueckleuchten
	k.b("vtrim", trim).add(Vector3(0, 0.42, -hz - 0.03), Vector3(W + 0.04, 0.2, 0.12))
	k.b("vtrim", trim).add(Vector3(0, 0.42, hz + 0.03), Vector3(W + 0.04, 0.2, 0.12))
	k.b("vtrim", trim).add(Vector3(0, 0.82, -hz + 0.005), Vector3(0.9, 0.16, 0.02))
	for s: float in [-1.0, 1.0]:
		k.b("vlight", K.lamp_glow(Color(0.95, 0.92, 0.8), 0.3)).add(Vector3(s * 0.68, 0.82, -hz - 0.005), Vector3(0.32, 0.16, 0.03))
		k.b("vtail", K.lamp_glow(Color(0.6, 0.06, 0.04), 0.4)).add(Vector3(s * 0.8, 0.95, hz + 0.01), Vector3(0.14, 0.3, 0.03))
		k.b("vtrim", trim).add(Vector3(s * (W * 0.5 + 0.08), 1.45, -hz + 1.05), Vector3(0.05, 0.16, 0.12))
	k.b("vtrim", dark).add(Vector3(0, 0.25, 0.2), Vector3(W - 0.3, 0.2, L - 1.0))
	if team:
		for x: float in [-0.7, 0.0, 0.7]:
			k.b("vrack", trim).add(Vector3(x, 1.99, 0.5), Vector3(0.04, 0.04, 3.4))
		for z: float in [-1.0, 0.5, 2.0]:
			k.b("vrack", trim).add(Vector3(0, 1.99, z), Vector3(1.5, 0.04, 0.04))
		K.pipe(k, "vrack", dark, Vector3(0.7, 1.95, 2.0), Vector3(0.75, 3.2, 2.05), 0.01, 4)
		k.b("vtrim", K.paint(Color(0.2, 0.2, 0.2))).add(Vector3(0, 2.1, 1.4), Vector3(1.1, 0.16, 0.9))
	else:
		# Verblasste Werbebeschriftung (heller Streifen) und Delle
		k.b("vstripe", K.paint(Color(0.55, 0.22, 0.12))).add(Vector3(W * 0.5 + 0.006, 1.0, 0.6), Vector3(0.01, 0.12, 3.6))
		k.b("vstripe", K.paint(Color(0.55, 0.22, 0.12))).add(Vector3(-W * 0.5 - 0.006, 1.0, 0.6), Vector3(0.01, 0.12, 3.6))
	# Batches lokal aufbauen (Kit arbeitet in Koerperkoordinaten)
	k.flush(b, true)
	Geo.add_box_shape(b, Vector3(0, 1.0, 0.1), Vector3(W + 0.1, 2.0, L + 0.1))
	return b

# ------------------------------------------------------------------ Spawn-Hof

static func _container(k: RailProps.Kit, b: StaticBody3D, c: Vector3, yaw: float, col: Color) -> void:
	var rot := K.yaw_b(yaw)
	var m := K.pbr(K.RAIL_TEX + "container_side", col, 0.35)
	var size := Vector3(2.44, 2.59, 6.06)
	k.b("cont", m).add(c + Vector3(0, size.y * 0.5, 0), size, rot)
	var fr := K.paint(col.darkened(0.35))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			k.b("cont_frame", fr).add(c + rot * Vector3(sx * 1.18, size.y * 0.5, sz * 2.98), Vector3(0.14, size.y + 0.02, 0.14), rot)
	for sz: float in [-1.0, 1.0]:
		k.b("cont_frame", fr).add(c + rot * Vector3(0, size.y - 0.06, sz * 2.98), Vector3(2.46, 0.14, 0.14), rot)
	for i in 4:
		k.b("cont_frame", K.dark_steel()).add(c + rot * Vector3(-0.85 + i * 0.57, 1.3, -3.04), Vector3(0.04, 2.3, 0.04), rot)
	K.col(b, c + Vector3(0, size.y * 0.5, 0), size, rot)

static func _spawn_yard(world: Node3D, covers: Array, rng: RandomNumberGenerator) -> void:
	var b := K.body(world, "SpawnYard", true)
	var k := RailProps.kit()
	_container(k, b, Vector3(13.5, 0, 27.0), 4.0, Color(0.42, 0.48, 0.52))
	_container(k, b, Vector3(13.5, 2.6, 27.0), 1.0, Color(0.6, 0.34, 0.22))
	_container(k, b, Vector3(16.5, 0, 32.5), 92.0, Color(0.36, 0.42, 0.3))
	_container(k, b, Vector3(-9.5, 0, 38.0), -6.0, Color(0.58, 0.5, 0.3))
	_container(k, b, Vector3(-12.6, 0, 36.5), -3.0, Color(0.4, 0.4, 0.42))
	_container(k, b, Vector3(-9.5, 0, 22.0), 85.0, Color(0.5, 0.3, 0.24))
	for c: Vector3 in [Vector3(11.5, 0, 31.0), Vector3(-6.8, 0, 25.5), Vector3(-6.0, 0, 36.0), Vector3(14.6, 0, 22.4)]:
		covers.append(c)
	K.flush(k, b, true, 0.0)
	van(world, Vector3(-4.6, 0.0, 31.0), 160.0, Color(0.74, 0.72, 0.66), false)
	covers.append(Vector3(-4.6, 0, 28.0))
	RailProps.crate_stack(world, Vector3(7.5, 0, 34.0), 20.0, rng, covers)
	RailProps.crate_stack(world, Vector3(10.0, 0, 24.2), -35.0, rng, covers)
	RailProps.crate_stack(world, Vector3(-2.8, 0, 36.5), 75.0, rng, covers)
	RailProps.place(world, "barrel_03", Vector3(8.6, 0, 26.0), 10.0, 1.0, Vector3(0.6, 0.9, 0.6), covers)
	RailProps.place(world, "barrel_03", Vector3(9.3, 0, 26.4), 40.0, 1.0, Vector3(0.6, 0.9, 0.6))
	RailProps.place(world, "metal_jerrycan_green", Vector3(-3.9, 0, 33.6), 30.0)
	RailProps.place(world, "old_tyre", Vector3(15.2, 0, 36.6), 0.0)

# ------------------------------------------------------------------ Hofflaeche

## Halde (Schuettkegel) mit konvexer Kollision.
static func pile(world: Node3D, c: Vector3, r: float, h: float, stretch: float, yaw: float, m: Material, rng: RandomNumberGenerator, collide: bool = true) -> void:
	var prof: Array = [Vector2(r * 1.02, -0.3)]
	var n := 7
	for i in range(1, n + 1):
		var t := float(i) / n
		var rr := r * (1.0 - t) * (rng.randf_range(0.93, 1.07) if i < n else 0.0)
		prof.append(Vector2(maxf(0.01, rr), h * t * (1.15 - 0.15 * t)))
	var mesh := K.lathe(prof, 18)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.transform = Transform3D(K.yaw_b(yaw).scaled_local(Vector3(stretch, 1.0, 1.0)), c)
	if collide:
		var b := K.body(world, "Pile", true)
		b.add_child(mi)
		var cs := CollisionShape3D.new()
		cs.shape = mesh.create_convex_shape(true, true)
		cs.transform = mi.transform
		b.add_child(cs)
	else:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(mi)

static func _yard(world: Node3D, covers: Array, rng: RandomNumberGenerator) -> void:
	# Halden (links Erz, rechts Koks, Schrott)
	pile(world, Vector3(-68.0, 0, -48.0), 9.0, 6.5, 1.7, 8.0, K.ore(), rng)
	pile(world, Vector3(-80.0, 0, -32.0), 7.0, 5.0, 1.4, -20.0, K.ore(), rng)
	pile(world, Vector3(66.0, 0, -36.0), 8.0, 6.0, 1.6, -12.0, K.coke(), rng)
	pile(world, Vector3(82.0, 0, -58.0), 6.0, 4.2, 1.3, 30.0, K.coke(), rng)
	pile(world, Vector3(-55.0, 0, -100.0), 5.0, 2.6, 1.6, 5.0, K.slag(), rng)
	covers.append(Vector3(-62.0, 0, -36.0))
	covers.append(Vector3(58.0, 0, -28.0))
	_scrap_heap(world, Vector3(28.0, 0, -96.0), rng, covers)
	_scrap_heap(world, Vector3(-52.0, 0, -32.0), rng, covers)
	# Hallen links/rechts als Deckung und Silhouette
	_hall(world, Vector3(-88.0, 0, -66.0), Vector3(22.0, 14.0, 36.0), K.corr(Color(0.5, 0.47, 0.44)), rng)
	_hall(world, Vector3(98.0, 0, -42.0), Vector3(26.0, 16.0, 30.0), K.worn_corr(Color(0.6, 0.6, 0.58)), rng)
	_hall(world, Vector3(46.0, 0, 18.0), Vector3(24.0, 12.0, 18.0), K.factory_wall(Color(0.72, 0.62, 0.56)), rng)
	_small_shed(world, covers, Vector3(-62.0, 0, -80.0), 20.0)
	_small_shed(world, covers, Vector3(42.0, 0, -58.0), -8.0)
	_small_shed(world, covers, Vector3(-14.0, 0, -22.0), 90.0)
	# Pfuetzen (flach, glaenzend)
	var pk := RailProps.kit()
	var pm := K.puddle()
	for i in 34:
		var p := Vector3(rng.randf_range(-70, 90), 0.015, rng.randf_range(-105, 10))
		if absf(p.x + 30.0) < 3.0:
			p.x += 6.0
		pk.b("puddle", pm).add_ball(p, Vector3(rng.randf_range(1.2, 4.5), 0.01, rng.randf_range(0.8, 3.0)), K.yaw_b(rng.randf_range(0, 180)))
	var pn := Node3D.new()
	pn.name = "Puddles"
	world.add_child(pn)
	K.flush(pk, pn, false, 220.0)
	# Flutlichtmasten
	var fb := K.body(world, "FloodMasts", false)
	var fk := RailProps.kit()
	for p: Vector3 in [Vector3(-40.0, 0, -40.0), Vector3(30.0, 0, -30.0), Vector3(-8.0, 0, -104.0), Vector3(55.0, 0, -104.0)]:
		RailProps.flood_mast(fk, fb, p, 20.0)
		K.col(fb, p + Vector3(0, 10.0, 0), Vector3(0.9, 20.0, 0.9))
	K.flush(fk, fb, true, 0.0)
	# Kabeltrommeln, Faesser, Reifen verstreut
	for p: Vector3 in [Vector3(-20.0, 0, -50.0), Vector3(18.0, 0, -62.0), Vector3(-38.0, 0, -86.0), Vector3(6.0, 0, -84.0)]:
		RailProps.place(world, "barrel_03", p, rng.randf_range(0, 180), 1.0, Vector3(0.6, 0.9, 0.6), covers)
		RailProps.place(world, "barrel_03", p + Vector3(0.7, 0, 0.3), rng.randf_range(0, 180), 1.0, Vector3(0.6, 0.9, 0.6))
	RailProps.crate_stack(world, Vector3(-24.0, 0, -95.0), 10.0, rng, covers)
	RailProps.crate_stack(world, Vector3(-36.0, 0, -97.0), -20.0, rng, covers)
	_cable_drum(world, Vector3(12.0, 0, -46.0), covers)
	_cable_drum(world, Vector3(-44.0, 0, -60.0), covers)

static func _cable_drum(world: Node3D, p: Vector3, covers: Array) -> void:
	var b := K.body(world, "Drum", false)
	var k := RailProps.kit()
	var wood := K.pbr(K.RIVER_TEX + "worn_plaster_wall", Color(0.45, 0.34, 0.24), 0.6)
	K.pipe(k, "drum", wood, p + Vector3(-0.55, 0.9, 0), p + Vector3(-0.45, 0.9, 0), 0.9, 18)
	K.pipe(k, "drum", wood, p + Vector3(0.45, 0.9, 0), p + Vector3(0.55, 0.9, 0), 0.9, 18)
	K.pipe(k, "drum_core", K.black(), p + Vector3(-0.45, 0.9, 0), p + Vector3(0.45, 0.9, 0), 0.62, 14)
	K.col(b, p + Vector3(0, 0.9, 0), Vector3(1.1, 1.8, 1.7))
	K.flush(k, b, true, 160.0)
	covers.append(p + Vector3(0, 0, 1.4))

static func _scrap_heap(world: Node3D, c: Vector3, rng: RandomNumberGenerator, covers: Array) -> void:
	pile(world, c, 4.5, 2.2, 1.4, rng.randf_range(0, 90), K.rust(Color(0.4, 0.3, 0.24)), rng)
	var k := RailProps.kit()
	var m := K.rust(Color(0.45, 0.35, 0.28))
	for i in 14:
		var a := rng.randf_range(0, TAU)
		var r := rng.randf_range(0.5, 4.5)
		var p := c + Vector3(cos(a) * r * 1.3, 0, sin(a) * r)
		p.y = maxf(0.1, 2.2 * (1.0 - r / 4.6)) + rng.randf_range(-0.1, 0.3)
		var rot := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0, TAU), rng.randf_range(-0.6, 0.6)))
		if i % 3 == 0:
			K.pipe(k, "scrap", m, p - rot.z * 1.2, p + rot.z * 1.2, rng.randf_range(0.1, 0.25), 8)
		else:
			k.b("scrap", m).add(p, Vector3(rng.randf_range(0.1, 1.2), rng.randf_range(0.04, 0.4), rng.randf_range(0.8, 2.8)), rot)
	var n := Node3D.new()
	n.name = "Scrap"
	world.add_child(n)
	K.flush(k, n, true, 180.0)
	covers.append(c + Vector3(0, 0, 4.8))

## Halle mit Wellblechwaenden, Satteldach, Pilastern und Toren (geschlossen, Box-Kollision).
static func _hall(world: Node3D, c: Vector3, size: Vector3, wm: Material, rng: RandomNumberGenerator) -> void:
	var b := K.body(world, "Hall", true)
	var k := RailProps.kit()
	var kd := RailProps.kit()
	K.box(k, "hwall", wm, c + Vector3(0, size.y * 0.5, 0), size)
	K.col(b, c + Vector3(0, size.y * 0.5, 0), size)
	var half := size.x * 0.5
	var pitch := 0.2
	var rm := K.corr(Color(0.4, 0.38, 0.36))
	for s: float in [-1.0, 1.0]:
		var rc := c + Vector3(s * half * 0.5, size.y + half * tan(pitch) * 0.5, 0)
		K.box(k, "hroof", rm, rc, Vector3(half / cos(pitch) + 0.6, 0.14, size.z + 0.6), Basis(Vector3.FORWARD, s * pitch), b)
	# Giebeldreiecke (als gestufte Bleche)
	for sz: float in [-1.0, 1.0]:
		for i in 4:
			var t := float(i) / 4.0
			k.b("hwall", wm).add(c + Vector3(0, size.y + half * tan(pitch) * (t + 0.125), sz * size.z * 0.5), Vector3(size.x * (1.0 - t - 0.125), half * tan(pitch) / 4.0 + 0.02, 0.15))
	var x := -half
	while x <= half + 0.01:
		for sz: float in [-1.0, 1.0]:
			kd.b("hpil", K.dark_steel()).add(c + Vector3(x, size.y * 0.5, sz * (size.z * 0.5 + 0.12)), Vector3(0.3, size.y, 0.22))
		x += 6.0
	var z := -size.z * 0.5
	while z <= size.z * 0.5 + 0.01:
		for sx: float in [-1.0, 1.0]:
			kd.b("hpil", K.dark_steel()).add(c + Vector3(sx * (half + 0.12), size.y * 0.5, z), Vector3(0.22, size.y, 0.3))
			if z < size.z * 0.5 - 1.0:
				kd.b("hwin", K.glass()).add(c + Vector3(sx * (half + 0.03), size.y - 2.4, z + 3.0), Vector3(0.04, 1.6, 4.2))
		z += 6.0
	kd.b("hdoor", K.paint(Color(0.3, 0.33, 0.3).lerp(Color(0.45, 0.3, 0.2), rng.randf()))).add(c + Vector3(0, 3.0, size.z * 0.5 + 0.06), Vector3(5.0, 6.0, 0.08))
	kd.b("hdoor", K.paint(Color(0.3, 0.33, 0.3))).add(c + Vector3(0, 3.0, -size.z * 0.5 - 0.06), Vector3(5.0, 6.0, 0.08))
	K.flush(k, b, true, 0.0)
	K.flush(kd, b, true, 260.0)

static func _small_shed(world: Node3D, covers: Array, c: Vector3, yaw: float) -> void:
	var b := Geo.static_body(c, yaw)
	b.name = "SmallShed"
	b.set_meta("no_fit", true)
	world.add_child(b)
	var k := RailProps.kit()
	k.b("wall", K.worn_corr(Color(0.6, 0.6, 0.56))).add(Vector3(0, 1.5, 0), Vector3(5.0, 3.0, 3.6))
	k.b("roof", K.corr(Color(0.42, 0.4, 0.38))).add(Vector3(0, 3.15, 0), Vector3(5.6, 0.1, 4.2), Basis(Vector3.RIGHT, 0.08))
	k.b("door", K.paint(Color(0.32, 0.3, 0.26))).add(Vector3(1.2, 1.05, 1.82), Vector3(0.9, 2.0, 0.04))
	k.b("win", K.glass()).add(Vector3(-1.0, 1.7, 1.82), Vector3(1.2, 0.7, 0.03))
	k.flush(b, true)
	Geo.add_box_shape(b, Vector3(0, 1.5, 0), Vector3(5.0, 3.0, 3.6))
	covers.append(c + K.yaw_b(yaw) * Vector3(0, 0, 2.9))

# ------------------------------------------------------------------ Rohrbruecke mit Laufsteg

static func _pipe_rack(world: Node3D, covers: Array) -> Vector3:
	var b := K.body(world, "PipeRack", true)
	var vis := Node3D.new()
	vis.name = "PipeRackVisual"
	world.add_child(vis)
	var k := RailProps.kit()
	var kd := RailProps.kit()
	var st := K.rust(Color(0.5, 0.42, 0.36))
	var z := -70.0
	var x0 := -45.0
	var x1 := 15.0
	var x := x0
	while x <= x1 + 0.01:
		for sz: float in [-1.15, 1.15]:
			K.column(k, "rcol", st, Vector3(x, 0, z + sz), 7.85, 0.32, b)
			k.b("found", K.concrete()).add(Vector3(x, 0.15, z + sz), Vector3(0.8, 0.3, 0.8))
		for yy: float in [5.85, 6.95]:
			K.ibeam(k, "rbeam", st, Vector3(x, yy, z - 1.35), Vector3(x, yy, z + 1.35), 0.24, 0.16)
		K.ibeam(k, "rbeam", st, Vector3(x, 7.84, z - 1.3), Vector3(x, 7.84, z + 1.3), 0.2, 0.14)
		K.beam(k, "rbrace", st, Vector3(x, 0.4, z - 1.15), Vector3(x, 5.7, z + 1.15), 0.1)
		x += 6.0
	# Laengstraeger
	for sz: float in [-1.15, 1.15]:
		K.ibeam(k, "rbeam", st, Vector3(x0, 7.84, z + sz), Vector3(x1, 7.84, z + sz), 0.2, 0.14)
	# Rohre (zwei Lagen)
	var cols: Array = [Color(0.5, 0.46, 0.32), Color(0.32, 0.36, 0.33), Color(0.5, 0.5, 0.48), Color(0.45, 0.22, 0.14)]
	var lay: Array = [[6.25, -0.8, 0.32, 0], [6.25, 0.0, 0.26, 1], [6.25, 0.75, 0.38, 2], [7.25, -0.7, 0.22, 3], [7.25, 0.15, 0.3, 2], [7.25, 0.85, 0.16, 1]]
	for l: Array in lay:
		var pm := K.paint(cols[int(l[3])])
		K.pipe(k, "rpipe%d" % int(l[3]), pm, Vector3(x0 - 25.0, float(l[0]), z + float(l[1])), Vector3(x1 + 3.0, float(l[0]), z + float(l[1])), float(l[2]), 12)
	K.col(b, Vector3((x0 + x1) * 0.5, 6.7, z), Vector3(x1 - x0, 1.4, 2.4))
	K.col(b, Vector3(x0 - 12.0, 6.7, z), Vector3(26.0, 1.4, 2.0))
	# Weiterfuehrung nach Westen auf Einzelstuetzen
	for xx in range(-51, -70, -6):
		K.column(k, "rcol", st, Vector3(float(xx), 0, z), 5.95, 0.3, b)
		K.ibeam(k, "rbeam", st, Vector3(float(xx), 5.95, z - 1.1), Vector3(float(xx), 5.95, z + 1.1), 0.24, 0.16)
	# Laufsteg y 8.0 (1.2 m) mit Gelaendern beidseits
	K.box(k, "walk", K.grating(), Vector3((x0 + x1) * 0.5, 7.97, z), Vector3(x1 - x0 + 0.4, 0.06, 1.2), Basis.IDENTITY, b)
	var rm := K.rail_yellow()
	K.railing(kd, rm, Vector3(x0 - 0.2, 8.0, z - 0.6), Vector3(x1 + 0.2, 8.0, z - 0.6), b)
	K.railing(kd, rm, Vector3(x0 - 0.2, 8.0, z + 0.6), Vector3(-20.4, 8.0, z + 0.6), b)
	K.railing(kd, rm, Vector3(-19.6, 8.0, z + 0.6), Vector3(x1 + 0.2, 8.0, z + 0.6), b)
	K.railing(kd, rm, Vector3(x0 - 0.2, 8.0, z - 0.6), Vector3(x0 - 0.2, 8.0, z + 0.6), b)
	K.railing(kd, rm, Vector3(x1 + 0.2, 8.0, z - 0.6), Vector3(x1 + 0.2, 8.0, z + 0.6), b)
	# Steigleiter mit Rueckenschutz an der Nordseite (Optik)
	K.ladder(kd, K.dark_steel(), Vector3(-20.0, 0, z + 1.35), 8.0, Vector3(0, 0, -1), true)
	# Kabeltrasse unter dem Laufsteg
	kd.b("tray", K.dark_steel()).add(Vector3((x0 + x1) * 0.5, 7.6, z - 1.0), Vector3(x1 - x0, 0.05, 0.4))
	covers.append(Vector3(-36.0, 0, -68.0))
	covers.append(Vector3(-24.0, 0, -68.0))
	covers.append(Vector3(0.0, 0, -68.0))
	K.flush(k, vis)
	K.flush(kd, vis, true, 220.0)
	return Vector3(-20.0, 8.0, z)

# ------------------------------------------------------------------ Schuppen mit begehbarem Flachdach

static func _shed(world: Node3D, covers: Array, c: Vector3) -> Vector3:
	var b := K.body(world, "RoofShed", true)
	var k := RailProps.kit()
	var size := Vector3(12.0, 4.5, 8.0)
	var wm := K.factory_wall(Color(0.7, 0.64, 0.58))
	K.box(k, "swall", wm, c + Vector3(0, size.y * 0.5 - 0.1, 0), Vector3(size.x, size.y - 0.2, size.z), Basis.IDENTITY, b)
	K.box(k, "sroof", K.concrete_floor(), c + Vector3(0, size.y - 0.1, 0), Vector3(size.x + 0.3, 0.2, size.z + 0.3), Basis.IDENTITY, b)
	# Attika 0.45 m (Deckung auf dem Dach)
	var ah := 0.45
	for sz: float in [-1.0, 1.0]:
		K.box(k, "sattic", K.concrete(), c + Vector3(0, size.y + ah * 0.5, sz * (size.z * 0.5 + 0.05)), Vector3(size.x + 0.4, ah, 0.2), Basis.IDENTITY, b)
	for sx: float in [-1.0, 1.0]:
		K.box(k, "sattic", K.concrete(), c + Vector3(sx * (size.x * 0.5 + 0.05), size.y + ah * 0.5, 0), Vector3(0.2, ah, size.z + 0.4), Basis.IDENTITY, b)
	k.b("sdoor", K.paint(Color(0.34, 0.3, 0.26))).add(c + Vector3(-2.0, 1.6, size.z * 0.5 + 0.03), Vector3(3.2, 3.2, 0.05))
	for i in 3:
		k.b("swin", K.glass()).add(c + Vector3(-5.0 + i * 3.5, 3.0, -size.z * 0.5 - 0.02), Vector3(1.6, 0.9, 0.03))
	K.ladder(k, K.dark_steel(), c + Vector3(size.x * 0.5 + 0.25, 0, 1.5), 5.0, Vector3(-1, 0, 0), false)
	# Dachaufbauten: Luefter + Kabelkanal
	K.box(k, "svent", K.paint(Color(0.5, 0.52, 0.5)), c + Vector3(3.5, size.y + 0.5, -1.5), Vector3(1.4, 1.0, 1.4), Basis.IDENTITY, b)
	K.flush(k, b, true, 0.0)
	covers.append(c + Vector3(0, size.y, -size.z * 0.5 + 0.7))
	covers.append(c + Vector3(-6.8, 0, 2.0))
	return c + Vector3(0, size.y, 0)

# ------------------------------------------------------------------ Gleisanlage (entlang X)

static func _track_x(k: RailProps.Kit, z: float, x0: float, x1: float, rng: RandomNumberGenerator) -> void:
	var L := absf(x1 - x0)
	var cx := (x0 + x1) * 0.5
	k.b("ballast", K.stones(Color(0.62, 0.58, 0.54))).add(Vector3(cx, 0.06, z), Vector3(L, 0.12, 3.6))
	k.b("ballast", K.stones(Color(0.62, 0.58, 0.54))).add(Vector3(cx, 0.0, z), Vector3(L, 0.08, 4.4))
	var x := x0 + 0.3
	while x < x1 - 0.3:
		k.b("sleepers", K.concrete_floor(Color(0.55, 0.52, 0.5))).add(Vector3(x, 0.17, z + rng.randf_range(-0.05, 0.05)), Vector3(0.26, 0.13, 2.7), K.yaw_b(rng.randf_range(-2.0, 2.0)))
		x += 0.72
	for s: float in [-0.5, 0.5]:
		var rz := z + s * RailProps.GAUGE
		k.b("rails", K.dark_steel()).add(Vector3(cx, 0.28, rz), Vector3(L, 0.15, 0.075))
		k.b("rails", K.dark_steel()).add(Vector3(cx, 0.235, rz), Vector3(L, 0.03, 0.15))
		k.b("railtop", K.paint(Color(0.55, 0.53, 0.5))).add(Vector3(cx, RailProps.RAIL_TOP - 0.006, rz), Vector3(L, 0.014, 0.068))

static func _sidings(world: Node3D, covers: Array, rng: RandomNumberGenerator) -> Array:
	var root := Node3D.new()
	root.name = "Sidings"
	world.add_child(root)
	var k := RailProps.kit()
	_track_x(k, -112.0, -170.0, 170.0, rng)
	_track_x(k, -120.0, -170.0, 170.0, rng)
	K.flush(k, root, false, 0.0)
	# Abgestellte Wagen auf z -112 (Luecke x -10..40 fuer die Sicht auf den Konvoi-Halt)
	var cols: Array = [Color(0.42, 0.25, 0.18), Color(0.3, 0.32, 0.28), Color(0.38, 0.3, 0.24), Color(0.2, 0.22, 0.22)]
	var kinds: Array = ["boxcar", "tank", "gondola", "boxcar", "flat", "boxcar"]
	var xs: Array = [-19.0, -35.0, -51.0, -67.0, -83.0, -99.0, 49.0, 65.0, 81.0, 97.0, 113.0]
	for i in xs.size():
		var kind: String = kinds[i % kinds.size()]
		var extra: Variant = null
		if kind == "flat":
			extra = "crates"
		RailProps.static_wagon(world, kind, Vector3(float(xs[i]), RailProps.RAIL_TOP, -112.0), 90.0, rng, cols[i % cols.size()], covers, extra)
	# Zwei Wagen auf z -120 weit draussen
	RailProps.static_wagon(world, "tank", Vector3(-110.0, RailProps.RAIL_TOP, -120.0), 90.0, rng, cols[1], covers)
	RailProps.static_wagon(world, "gondola", Vector3(120.0, RailProps.RAIL_TOP, -120.0), 90.0, rng, cols[2], covers)
	# Boeschung + flacher Graben, Betonbarriere bei z -126 (Stellung der Verbuendeten)
	var bk := RailProps.kit()
	var bb := K.body(world, "Embankment", true)
	bk.b("berm", K.gravel(Color(0.5, 0.47, 0.42))).add(Vector3(10.0, 0.0, -124.8), Vector3(140.0, 0.4, 3.2))
	bk.b("ditch", K.mud(Color(0.36, 0.33, 0.3))).add(Vector3(10.0, 0.012, -129.2), Vector3(200.0, 0.02, 2.4))
	bk.b("ditch", K.puddle()).add(Vector3(10.0, 0.02, -129.2), Vector3(200.0, 0.01, 0.8))
	K.flush(bk, root, false, 0.0)
	K.col(bb, Vector3(10.0, 0.0, -124.8), Vector3(140.0, 0.4, 3.2))
	RailProps.barrier_row(world, Vector3(-22.0, 0.2, -126.2), Vector3(42.0, 0.2, -126.2), covers)
	var fc: Array = []
	for i in 8:
		fc.append(Vector3(-20.0 + i * (60.0 / 7.0), 0.2, -124.5))
	return fc

# ------------------------------------------------------------------ Strasse

static func _road(world: Node3D, covers: Array, rng: RandomNumberGenerator) -> Dictionary:
	var root := Node3D.new()
	root.name = "Road"
	world.add_child(root)
	var k := RailProps.kit()
	var kd := RailProps.kit()
	var x0 := -320.0
	var x1 := 320.0
	var L := x1 - x0
	# Asphalt (nur Optik, Boden-Kollision ist eben -> keine Huckel)
	k.b("asphalt", K.asphalt()).add(Vector3(0, 0.02, ROAD_Z), Vector3(L, 0.04, ROAD_W))
	# Randstreifen (Mittellinie verblasst, gestrichelt)
	var lm := K.paint(Color(0.78, 0.76, 0.7))
	var x := x0
	while x < x1:
		kd.b("lines", lm).add(Vector3(x + 1.5, 0.042, ROAD_Z), Vector3(3.0, 0.005, 0.12))
		x += 9.0
	for s: float in [-1.0, 1.0]:
		k.b("lines", lm).add(Vector3(0, 0.042, ROAD_Z + s * (ROAD_W * 0.5 - 0.3)), Vector3(L, 0.005, 0.12))
		# Bordstein (niedrig, nur Optik) + Bankett
		k.b("kerb", K.concrete(Color(0.66, 0.64, 0.6))).add(Vector3(0, 0.05, ROAD_Z + s * (ROAD_W * 0.5 + 0.1)), Vector3(L, 0.1, 0.2))
		k.b("shoulder", K.gravel(Color(0.52, 0.49, 0.45))).add(Vector3(0, 0.01, ROAD_Z + s * (ROAD_W * 0.5 + 1.2)), Vector3(L, 0.02, 2.0))
	# Flicken / Risse
	for i in 18:
		kd.b("patch", K.paint(Color(0.1, 0.1, 0.1))).add(Vector3(rng.randf_range(-150, 200), 0.041, ROAD_Z + rng.randf_range(-3.5, 3.5)), Vector3(rng.randf_range(1.0, 4.0), 0.004, rng.randf_range(0.6, 2.0)), K.yaw_b(rng.randf_range(-20, 20)))
	K.flush(k, root, false, 0.0)
	K.flush(kd, root, false, 260.0)
	# Durchlass bei x -5 (Betonstirnwaende beidseits der Strasse, Rohrmuendung)
	var cb := K.body(world, "Culvert", true)
	var ck := RailProps.kit()
	for s: float in [-1.0, 1.0]:
		var zc := ROAD_Z + s * (ROAD_W * 0.5 + 2.4)
		K.box(ck, "culvert", K.concrete(Color(0.6, 0.58, 0.55)), Vector3(-5.0, 0.3, zc), Vector3(3.6, 0.6, 0.4), Basis.IDENTITY, cb)
		ck.b("culvert_hole", K.black()).add(Vector3(-5.0, 0.15, zc + s * 0.21), Vector3(1.2, 0.3, 0.02))
		ck.b("ditch", K.mud(Color(0.34, 0.31, 0.28))).add(Vector3(-5.0, 0.012, zc + s * 2.0), Vector3(1.8, 0.02, 4.0))
	K.flush(ck, root, true, 240.0)
	# Leitplanken (Suedseite, Luecken) und niedrige Mauern -> Gegnerdeckung
	var gb := K.body(world, "GuardRails", true)
	var gk := RailProps.kit()
	var gm := K.paint(Color(0.62, 0.62, 0.6))
	var segs: Array = [[-70.0, -22.0], [-14.0, 18.0], [22.0, 60.0], [66.0, 130.0]]
	var zr := ROAD_Z - (ROAD_W * 0.5 + 1.4)
	for sg: Array in segs:
		var a := float(sg[0])
		var e := float(sg[1])
		gk.b("guard", gm).add(Vector3((a + e) * 0.5, 0.62, zr), Vector3(e - a, 0.32, 0.06))
		var px := a
		while px <= e + 0.01:
			gk.b("guard_post", K.dark_steel()).add(Vector3(px, 0.38, zr - 0.12), Vector3(0.1, 0.76, 0.14))
			px += 2.0
		K.col(gb, Vector3((a + e) * 0.5, 0.45, zr), Vector3(e - a, 0.9, 0.3))
	# Leitplanke Nordseite westlich/oestlich
	for sg2: Array in [[-180.0, -60.0], [120.0, 220.0]]:
		var a2 := float(sg2[0])
		var e2 := float(sg2[1])
		gk.b("guard", gm).add(Vector3((a2 + e2) * 0.5, 0.62, ROAD_Z + ROAD_W * 0.5 + 1.4), Vector3(e2 - a2, 0.32, 0.06))
	K.flush(gk, root, true, 260.0)
	var wb := K.body(world, "LowWalls", true)
	var wk := RailProps.kit()
	var enemy: Array = []
	var walls: Array = [Vector3(-38.0, 0, -149.0), Vector3(-8.0, 0, -149.5), Vector3(14.0, 0, -148.8), Vector3(40.0, 0, -149.2), Vector3(90.0, 0, -148.6)]
	for w: Vector3 in walls:
		K.box(wk, "lwall", K.concrete(Color(0.62, 0.6, 0.56)), w + Vector3(0, 0.55, 0), Vector3(4.5, 1.1, 0.35), K.yaw_b(rng.randf_range(-6, 6)), wb)
	K.flush(wk, root, true, 260.0)
	for xx: float in [-46.0, -30.0, -18.0, 2.0, 30.0, 52.0]:
		enemy.append(Vector3(xx, 0.0, zr - 0.9))
	enemy.append(Vector3(14.0, 0.0, -149.9))
	enemy.append(Vector3(40.0, 0.0, -150.3))
	# Strassenlaternen (Nordseite, aus) + Mast mit Leuchte
	x = -150.0
	while x <= 200.0:
		Props.lamp(world, Vector3(x, 0, ROAD_Z + ROAD_W * 0.5 + 0.9), 180.0, false)
		x += 32.0
	return {"enemy": enemy}

# ------------------------------------------------------------------ Suedseite: Zaun + Werksbauten

static func _south_works(world: Node3D, covers: Array, rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "SouthWorks"
	world.add_child(root)
	var k := RailProps.kit()
	var fz := -153.5
	var x := -200.0
	var post := K.dark_steel()
	var mesh := K.pbr(K.BERLIN_TEX + "metal_plate", Color(0.4, 0.4, 0.4), 0.8, 1.0, 0.0, true)
	while x < 220.0:
		k.b("fpost", post).add(Vector3(x, 1.25, fz), Vector3(0.07, 2.5, 0.07))
		k.b("fpost", post).add(Vector3(x, 2.6, fz - 0.12), Vector3(0.05, 0.4, 0.05), Basis(Vector3.RIGHT, -0.5))
		x += 3.0
	# Zaunfelder: duenne, halbtransparent wirkende Gitterbaender (Draehte)
	for yy: float in [0.1, 0.6, 1.1, 1.6, 2.1, 2.45]:
		k.b("fwire", post).add(Vector3(10.0, yy, fz), Vector3(420.0, 0.02, 0.02))
	var wx := -200.0
	while wx < 220.0:
		k.b("fwire", post).add(Vector3(wx + 0.75, 1.25, fz), Vector3(0.012, 2.4, 0.012))
		k.b("fwire", post).add(Vector3(wx + 1.5, 1.25, fz), Vector3(0.012, 2.4, 0.012))
		k.b("fwire", post).add(Vector3(wx + 2.25, 1.25, fz), Vector3(0.012, 2.4, 0.012))
		wx += 3.0
	K.flush(k, root, false, 200.0)
	# Werksbauten z -160..-200
	_hall(world, Vector3(-48.0, 0, -178.0), Vector3(30.0, 13.0, 26.0), K.brick(Color(0.66, 0.52, 0.46)), rng)
	_hall(world, Vector3(10.0, 0, -182.0), Vector3(36.0, 17.0, 30.0), K.corr(Color(0.5, 0.48, 0.45)), rng)
	_hall(world, Vector3(62.0, 0, -176.0), Vector3(24.0, 11.0, 22.0), K.factory_wall(Color(0.7, 0.62, 0.56)), rng)
	_hall(world, Vector3(-100.0, 0, -176.0), Vector3(28.0, 15.0, 26.0), K.worn_corr(Color(0.58, 0.58, 0.55)), rng)
	_hall(world, Vector3(150.0, 0, -180.0), Vector3(40.0, 20.0, 34.0), K.corr(Color(0.45, 0.43, 0.41)), rng)
	_small_shed(world, covers, Vector3(-20.0, 0, -160.0), 0.0)
	_small_shed(world, covers, Vector3(38.0, 0, -161.0), 0.0)
	# Pfoertnerhaus mit Schranke an der Werkseinfahrt (x 80)
	_small_shed(world, covers, Vector3(84.0, 0, -158.0), 0.0)
	var gk := RailProps.kit()
	K.pipe(gk, "gate", K.paint(Color(0.75, 0.15, 0.1)), Vector3(78.0, 1.0, fz + 0.5), Vector3(70.0, 1.0, fz + 0.5), 0.05, 6)
	K.flush(gk, root, true, 200.0)
