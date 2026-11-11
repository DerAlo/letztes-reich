extends RefCounted
## Level 7 "Kaltes Auge": Hochofen (Heldensilhouette) mit Gichtbuehne, Gasabzuegen, Fallrohr und
## Staubsack, Ringleitung mit Blasformen, drei Winderhitzern (Cowper), Abhitzeschornstein,
## Schraegaufzug und Giesshalle. Statische Funktionen.

const K = preload("res://game/levels/overwatch_world_kit.gd")
const RailProps = preload("res://game/levels/rail_props.gd")

const C := Vector3(-56.0, 0.0, 10.0)      ## Ofenachse
const TOP := 38.0                          ## Gichtverschluss / obere Konusoberkante

static func build(world: Node3D, covers: Array, rng: RandomNumberGenerator, pts: Dictionary) -> void:
	_furnace(world)
	_stoves(world)
	_casthouse(world, covers)
	_skip_bridge(world)
	# Dampffahne aus der Gicht (hell, weich, langsam, vom Wind abgetrieben)
	K.steam(world, C + Vector3(0, 50.5, 0), 1.6, 7.0, 1.6, 22.0, 26, 1.6, 0.26)
	K.steam(world, C + Vector3(2.5, 45.0, -1.5), 0.8, 3.5, 1.0, 12.0, 10, 1.2, 0.2)
	pts["furnace_top"] = C + Vector3(0, 44.0, 0)

# ------------------------------------------------------------------ Hochofen

static func _furnace(world: Node3D) -> void:
	var b := K.body(world, "BlastFurnace", true)
	var vis := Node3D.new()
	vis.name = "FurnaceVisual"
	world.add_child(vis)
	var shell := K.rust(Color(0.42, 0.33, 0.28))
	var st := K.rust(Color(0.5, 0.42, 0.36))
	var dk := K.dark_steel()
	# Ofenpanzer als Drehkoerper: Gestell, Rast, Kohlensack, Schacht, Gichtkonus
	var prof: Array = [
		Vector2(5.6, 0.0), Vector2(5.6, 1.2), Vector2(5.2, 1.4), Vector2(5.2, 8.0), Vector2(5.5, 8.6),
		Vector2(6.1, 12.0), Vector2(6.1, 14.0), Vector2(5.9, 16.0), Vector2(4.5, 34.0),
		Vector2(4.6, 34.3), Vector2(4.6, 34.8), Vector2(2.6, 38.0), Vector2(2.2, 38.2), Vector2(0.01, 38.2),
	]
	K.lathe_node(vis, prof, shell, C, 40)
	K.col_cyl(b, C, 12.0, 5.9)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 5.0
	cyl.height = 26.0
	cs.shape = cyl
	cs.position = C + Vector3(0, 25.0, 0)
	b.add_child(cs)
	var k := RailProps.kit()
	var kd := RailProps.kit()
	# Panzerringe (Kuehlplattenbaender) am Schacht
	var y := 16.5
	while y < 33.5:
		var r := 5.9 + (4.5 - 5.9) * (y - 16.0) / 18.0
		K.torus(kd, "bands", dk, C + Vector3(0, y, 0), r + 0.05, 0.09, Basis.IDENTITY, 40)
		y += 1.6
	for yy: float in [2.0, 4.5, 7.0]:
		K.torus(kd, "bands", dk, C + Vector3(0, yy, 0), 5.25, 0.1, Basis.IDENTITY, 40)
	# Senkrechte Kuehlwasserrohre am Schacht
	for i in 16:
		var a := TAU * float(i) / 16.0
		var dir := Vector3(cos(a), 0, sin(a))
		K.pipe(kd, "cool", K.paint(Color(0.32, 0.36, 0.34)), C + dir * 6.05 + Vector3(0, 15.6, 0), C + dir * 4.65 + Vector3(0, 33.6, 0), 0.07, 6)
	# Ringleitung (Heisswind) mit Blasformstoecken
	var bustle_y := 13.2
	var refr := K.rust(Color(0.55, 0.45, 0.38))
	K.torus(k, "bustle", refr, C + Vector3(0, bustle_y, 0), 8.6, 0.85, Basis.IDENTITY, 48)
	for i in 20:
		var a := TAU * (float(i) + 0.5) / 20.0
		var dir := Vector3(cos(a), 0, sin(a))
		var p0 := C + dir * 8.4 + Vector3(0, bustle_y - 0.5, 0)
		var p1 := C + dir * 6.4 + Vector3(0, 9.4, 0)
		var p2 := C + dir * 5.4 + Vector3(0, 9.0, 0)
		K.pipe_path(kd, "tuyere", refr, [p0, p0 - Vector3(0, 1.8, 0), p1, p2], 0.2, 8)
	# Giessbuehne um das Gestell (begehbar, y 6)
	var plat := K.grating()
	var ring_pts := 24
	for i in ring_pts:
		var a0 := TAU * float(i) / ring_pts
		var a1 := TAU * float(i + 1) / ring_pts
		var mid := (a0 + a1) * 0.5
		var cc := C + Vector3(cos(mid), 0, sin(mid)) * 7.6 + Vector3(0, 5.9, 0)
		var rot := Basis(Vector3.UP, -mid + PI * 0.5)
		var w := 2.0 * 9.9 * sin((a1 - a0) * 0.5)
		k.b("plat", plat).add(cc, Vector3(w, 0.2, 4.6), rot)
	K.col_cyl(b, C + Vector3(0, 5.8, 0), 0.2, 9.9)
	for i in 8:
		var a := TAU * float(i) / 8.0
		K.column(k, "col", st, C + Vector3(cos(a), 0, sin(a)) * 9.4, 5.8, 0.4, b)
	# Gichtbuehne: zwei Plattformebenen (38 / 44) mit Fachwerk, Gelaendern, Haus
	for py: float in [37.8, 43.8]:
		var half := 7.0 if py < 40.0 else 5.5
		K.box(k, "gplat", plat, C + Vector3(0, py, 0), Vector3(half * 2.0, 0.25, half * 2.0), Basis.IDENTITY, b)
		k.b("gframe", dk).add(C + Vector3(0, py - 0.35, 0), Vector3(half * 2.0 + 0.2, 0.45, half * 2.0 + 0.2))
		var rm := K.rail_yellow()
		var hh := half - 0.05
		var cy := py + 0.125
		var corners: Array = [C + Vector3(-hh, cy, -hh), C + Vector3(hh, cy, -hh), C + Vector3(hh, cy, hh), C + Vector3(-hh, cy, hh), C + Vector3(-hh, cy, -hh)]
		K.railing_path(kd, rm, corners)
	# Buehnentraeger: vier Stiele vom Schacht bis 44
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var base := C + Vector3(sx * 4.6, 34.5, sz * 4.6)
			K.column(k, "col", st, C + Vector3(sx * 6.6, 34.5, sz * 6.6), 3.3, 0.4)
			K.column(k, "col", st, C + Vector3(sx * 5.2, 38.0, sz * 5.2), 5.8, 0.36)
			K.beam(k, "brace", st, base, C + Vector3(sx * 6.6, 37.6, sz * 6.6), 0.25)
			K.beam(k, "brace", st, C + Vector3(sx * 5.2, 38.0, sz * 5.2), C + Vector3(sx * 5.2, 43.6, -sz * 5.2), 0.14)
	# Glockenhaus / Gichtverschluss
	K.box(k, "ghouse", K.corr(Color(0.5, 0.47, 0.43)), C + Vector3(1.0, 47.0, -1.5), Vector3(5.0, 6.0, 4.2), Basis.IDENTITY)
	k.b("gframe", dk).add(C + Vector3(1.0, 50.1, -1.5), Vector3(5.4, 0.25, 4.6))
	K.cone(k, "gcone", shell, C + Vector3(0, 38.2, 0), 2.6, 2.2, 1.3, 24)
	# Vier Gasabzuege (Uptakes) -> zwei Hosenrohre -> Fallrohr (Downcomer) zum Staubsack
	var gas := K.rust(Color(0.46, 0.37, 0.31))
	var tops: Array = []
	for i in 4:
		var a := TAU * (float(i) + 0.5) / 4.0
		var dir := Vector3(cos(a), 0, sin(a))
		var p0 := C + dir * 3.4 + Vector3(0, 36.4, 0)
		var p1 := C + dir * 3.8 + Vector3(0, 46.0, 0)
		var p2 := C + dir * 2.6 + Vector3(0, 51.5, 0)
		K.pipe_path(k, "uptake", gas, [p0, p1, p2], 0.75, 14)
		tops.append(p2)
		K.flange(kd, "flange", dk, p1 - Vector3(0, 3.0, 0), Vector3.UP, 0.85)
		# Entlastungsventile oben
		K.pipe(kd, "valve", dk, p2, p2 + Vector3(0, 2.2, 0), 0.32, 10)
		K.cone(kd, "valve", dk, p2 + Vector3(0, 2.2, 0), 0.6, 0.55, 0.12, 10)
	var junction := C + Vector3(-3.0, 53.0, 3.5)
	K.pipe_path(k, "uptake", gas, [tops[1], junction], 0.75, 14)
	K.pipe_path(k, "uptake", gas, [tops[2], junction], 0.75, 14)
	K.pipe_path(k, "uptake", gas, [tops[0], tops[1] + Vector3(0, 0.6, 0)], 0.6, 14)
	K.pipe_path(k, "uptake", gas, [tops[3], tops[2] + Vector3(0, 0.6, 0)], 0.6, 14)
	K.ball(k, "uptake", gas, junction, 1.0, 14)
	var dc := Vector3(-66.0, 0.0, 30.0)
	K.pipe_path(k, "downcomer", gas, [junction, dc + Vector3(0, 26.0, 0)], 1.0, 16)
	# Staubsack (Kegel + Zylinder auf Stuetzen)
	K.lathe_node(vis, [Vector2(0.4, 8.0), Vector2(3.8, 13.5), Vector2(3.8, 22.0), Vector2(2.4, 25.0), Vector2(1.0, 26.2), Vector2(0.01, 26.3)], shell, dc, 28)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			K.column(k, "col", st, dc + Vector3(sx * 3.0, 0, sz * 3.0), 14.0, 0.45, b)
			K.beam(k, "brace", st, dc + Vector3(sx * 3.0, 0.5, sz * 3.0), dc + Vector3(-sx * 3.0, 8.0, sz * 3.0), 0.16)
	K.col_cyl(b, dc + Vector3(0, 10.0, 0), 13.0, 3.8)
	K.pipe(k, "downcomer", gas, dc + Vector3(2.5, 18.0, 0), C + Vector3(-12.0, 18.0, 6.0), 0.9, 14)
	# Gasreinigung: Leitung nach Westen zu den Cowpern (Reingas) als zweite Rohrbruecke
	K.pipe_path(k, "downcomer", gas, [C + Vector3(-12.0, 18.0, 6.0), Vector3(-72.0, 18.0, 16.0), Vector3(-72.0, 18.0, -12.0)], 0.7, 14)
	# Treppenturm zur Gichtbuehne (Optik, Gitterturm an der Westseite)
	var tw := C + Vector3(-9.5, 0, 0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			K.column(k, "col", st, tw + Vector3(sx * 1.6, 0, sz * 1.6), 44.0, 0.3, b)
	var ly := 4.0
	while ly < 44.0:
		for side in 4:
			var ax := [Vector3(-1.6, 0, -1.6), Vector3(1.6, 0, -1.6), Vector3(1.6, 0, 1.6), Vector3(-1.6, 0, 1.6)]
			var a0: Vector3 = ax[side]
			var a1: Vector3 = ax[(side + 1) % 4]
			K.beam(k, "brace", st, tw + a0 + Vector3(0, ly, 0), tw + a1 + Vector3(0, ly, 0), 0.14)
			K.beam(k, "xbrace", st, tw + a0 + Vector3(0, ly - 4.0, 0), tw + a1 + Vector3(0, ly, 0), 0.08)
		k.b("plat", plat).add(tw + Vector3(0, ly, 0), Vector3(3.2, 0.08, 3.2))
		ly += 4.0
	K.beam(k, "brace", st, tw + Vector3(1.6, 37.8, 0), C + Vector3(-7.0, 37.8, 0), 0.4)
	K.flush(k, vis)
	K.flush(kd, vis, true, 260.0)

# ------------------------------------------------------------------ Winderhitzer

static func _stoves(world: Node3D) -> void:
	var b := K.body(world, "Stoves", true)
	var vis := Node3D.new()
	vis.name = "StoveVisual"
	world.add_child(vis)
	var shell := K.rust(Color(0.48, 0.4, 0.35))
	var st := K.rust(Color(0.5, 0.42, 0.36))
	var dk := K.dark_steel()
	var k := RailProps.kit()
	var kd := RailProps.kit()
	var prof: Array = [Vector2(4.2, 0.0), Vector2(4.2, 0.8), Vector2(4.0, 1.0), Vector2(4.0, 30.0)]
	# Kuppel (Halbkugel-artig)
	for i in range(1, 9):
		var a := PI * 0.5 * float(i) / 8.0
		prof.append(Vector2(maxf(0.01, 4.0 * cos(a)), 30.0 + 3.6 * sin(a)))
	var zs: Array[float] = [-8.0, 6.0, 20.0]
	var hb_main_x := -71.0
	for z in zs:
		var p := Vector3(-78.0, 0, z)
		K.lathe_node(vis, prof, shell, p, 32)
		K.col_cyl(b, p, 33.0, 4.1)
		for yy: float in [4.0, 10.0, 16.0, 22.0, 28.0]:
			K.torus(kd, "bands", dk, p + Vector3(0, yy, 0), 4.05, 0.08, Basis.IDENTITY, 32)
		# Ringpodest mit Gelaender auf halber Hoehe und oben
		for py: float in [12.0, 30.0]:
			K.torus(kd, "sring", K.grating(), p + Vector3(0, py, 0), 4.7, 0.6, Basis.IDENTITY, 32)
			K.torus(kd, "srail", K.rail_yellow(), p + Vector3(0, py + 1.1, 0), 5.25, 0.03, Basis.IDENTITY, 32)
			for j in 12:
				var a := TAU * float(j) / 12.0
				kd.b("srail", K.rail_yellow()).add(p + Vector3(cos(a) * 5.25, py + 0.55, sin(a) * 5.25), Vector3(0.05, 1.1, 0.05))
		# Heisswindstutzen zur Hauptleitung, Kaltwind- und Abgasleitung
		K.pipe(k, "hotblast", K.rust(Color(0.56, 0.46, 0.38)), p + Vector3(3.6, 9.0, 0), Vector3(hb_main_x, 9.0, z), 0.75, 14)
		K.flange(kd, "flange", dk, p + Vector3(5.0, 9.0, 0), Vector3.RIGHT, 0.9)
		K.pipe_path(k, "coldblast", K.paint(Color(0.34, 0.37, 0.35)), [p + Vector3(-3.7, 4.0, 1.5), p + Vector3(-6.0, 4.0, 1.5), Vector3(-84.0, 4.0, z + 1.5)], 0.5, 12)
		K.pipe_path(k, "coldblast", K.paint(Color(0.34, 0.37, 0.35)), [p + Vector3(-3.0, 2.0, -2.0), p + Vector3(-7.0, 2.0, -2.0)], 0.7, 12)
		# Leiter
		K.ladder(kd, dk, p + Vector3(0, 0, -4.3), 30.0, Vector3(0, 0, 1), true)
	# Heisswind-Hauptleitung (N-S) und Anschluss an die Ringleitung
	K.pipe(k, "hotblast", K.rust(Color(0.56, 0.46, 0.38)), Vector3(hb_main_x, 9.0, -11.0), Vector3(hb_main_x, 9.0, 23.0), 1.0, 16)
	K.pipe_path(k, "hotblast", K.rust(Color(0.56, 0.46, 0.38)), [Vector3(hb_main_x, 9.0, 10.0), Vector3(-66.0, 9.0, 10.0), C + Vector3(-8.6, 13.2, 0)], 0.9, 16)
	for z in range(-10, 24, 6):
		K.column(k, "col", st, Vector3(hb_main_x, 0, float(z)), 7.9, 0.4, b)
		k.b("brace", st).add(Vector3(hb_main_x, 7.9, float(z)), Vector3(2.4, 0.3, 0.4))
	# Kaltwind-Sammelleitung und Abgaskanal
	K.pipe(k, "coldblast", K.paint(Color(0.34, 0.37, 0.35)), Vector3(-84.0, 4.0, -12.0), Vector3(-84.0, 4.0, 24.0), 0.8, 14)
	k.b("flue", K.brick(Color(0.6, 0.48, 0.42))).add(Vector3(-86.5, 1.4, 6.0), Vector3(2.6, 2.8, 34.0))
	K.col(b, Vector3(-86.5, 1.4, 6.0), Vector3(2.6, 2.8, 34.0))
	# Kaminschornstein der Cowper (gemauert, hoch)
	var ch := Vector3(-92.0, 0, 6.0)
	K.lathe_node(vis, [Vector2(3.2, 0.0), Vector2(3.0, 3.0), Vector2(2.6, 40.0), Vector2(2.1, 62.0), Vector2(2.3, 62.6), Vector2(2.3, 63.2), Vector2(1.7, 63.2), Vector2(1.7, 61.0)], K.brick(Color(0.52, 0.4, 0.36)), ch, 28)
	K.col_cyl(b, ch, 62.0, 2.8)
	for yy: float in [20.0, 40.0, 55.0]:
		K.torus(kd, "bands", dk, ch + Vector3(0, yy, 0), 2.6 - (yy / 62.0) * 0.5 + 0.06, 0.08, Basis.IDENTITY, 28)
	K.steam(world, ch + Vector3(0, 64.0, 0), 1.0, 5.0, 1.2, 16.0, 12, 1.4, 0.14, Color(0.72, 0.72, 0.74))
	K.flush(k, vis)
	K.flush(kd, vis, true, 260.0)

# ------------------------------------------------------------------ Giesshalle

static func _casthouse(world: Node3D, covers: Array) -> void:
	var b := K.body(world, "Casthouse", true)
	var vis := Node3D.new()
	vis.name = "CasthouseVisual"
	world.add_child(vis)
	var k := RailProps.kit()
	var kd := RailProps.kit()
	var x0 := -70.0
	var x1 := -44.0
	var z0 := -20.0
	var z1 := 2.5
	var h := 15.0
	var wm := K.corr(Color(0.52, 0.47, 0.43))
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# Sockel aus Beton, darueber Wellblech
	K.box(k, "plinth", K.concrete(), Vector3(cx, 1.5, z0), Vector3(x1 - x0, 3.0, 0.4), Basis.IDENTITY, b)
	K.box(k, "plinth", K.concrete(), Vector3(x1, 1.5, cz), Vector3(0.4, 3.0, z1 - z0), Basis.IDENTITY, b)
	K.box(k, "plinth", K.concrete(), Vector3(x0, 1.5, cz), Vector3(0.4, 3.0, z1 - z0), Basis.IDENTITY, b)
	K.box(k, "wall", wm, Vector3(cx, 3.0 + (h - 3.0) * 0.5, z0), Vector3(x1 - x0, h - 3.0, 0.2), Basis.IDENTITY, b)
	K.box(k, "wall", wm, Vector3(x1, 3.0 + (h - 3.0) * 0.5, cz), Vector3(0.2, h - 3.0, z1 - z0), Basis.IDENTITY, b)
	K.box(k, "wall", wm, Vector3(x0, 3.0 + (h - 3.0) * 0.5, cz), Vector3(0.2, h - 3.0, z1 - z0), Basis.IDENTITY, b)
	K.box(k, "wall", wm, Vector3(cx, 3.0 + (h - 3.0) * 0.5 + 4.0, z1), Vector3(x1 - x0, h - 7.0, 0.2), Basis.IDENTITY, b)
	K.col(b, Vector3(cx, 3.5, z1), Vector3(x1 - x0, 7.0, 0.3))
	# Satteldach mit Laternenaufsatz
	var half := (z1 - z0) * 0.5
	var pitch := 0.24
	var rl := half / cos(pitch)
	var rm := K.corr(Color(0.42, 0.4, 0.38))
	for s: float in [-1.0, 1.0]:
		var rc := Vector3(cx, h + half * tan(pitch) * 0.5, cz + s * half * 0.5)
		K.box(k, "roof", rm, rc, Vector3(x1 - x0 + 0.8, 0.12, rl + 0.6), Basis(Vector3.RIGHT, s * pitch), b)
	var ridge := h + half * tan(pitch)
	K.box(k, "lantern", wm, Vector3(cx, ridge + 1.1, cz), Vector3(x1 - x0 - 4.0, 2.2, 3.4), Basis.IDENTITY)
	k.b("roof", rm).add(Vector3(cx, ridge + 2.3, cz), Vector3(x1 - x0 - 3.0, 0.12, 4.6))
	for i in 10:
		kd.b("louvre", K.dark_steel()).add(Vector3(x0 + 3.5 + i * 2.1, ridge + 1.1, cz - 1.72), Vector3(1.6, 1.4, 0.05))
	# Pilaster und Fensterbaender
	var i := 0
	var x := x0
	while x <= x1 + 0.01:
		kd.b("pilaster", K.dark_steel()).add(Vector3(x, h * 0.5, z0 - 0.15), Vector3(0.35, h, 0.25))
		if i % 2 == 1 and x < x1 - 1.0:
			kd.b("window", K.glass()).add(Vector3(x + 1.3, 11.0, z0 - 0.12), Vector3(2.6, 2.4, 0.04))
		x += 2.6
		i += 1
	# Grosses Tor zur Hofseite (Abstich-Gleis)
	kd.b("door", K.paint(Color(0.32, 0.3, 0.27))).add(Vector3(-50.0, 3.5, z0 - 0.14), Vector3(6.0, 7.0, 0.06))
	kd.b("door_frame", K.rail_yellow()).add(Vector3(-50.0, 7.1, z0 - 0.17), Vector3(6.4, 0.25, 0.06))
	# Rinnen-Abluft: zwei Dachaufsaetze mit Dampf
	for px: float in [-62.0, -52.0]:
		K.box(k, "hood", K.rust(Color(0.45, 0.36, 0.3)), Vector3(px, ridge + 3.4, cz - 2.0), Vector3(2.4, 2.6, 2.4), Basis.IDENTITY)
		K.steam(world, Vector3(px, ridge + 5.0, cz - 2.0), 0.8, 4.0, 1.2, 12.0, 8, 1.4, 0.2)
	# Anbauten / Deckung am Hallenfuss
	K.box(kd, "annex", K.factory_wall(), Vector3(-41.0, 2.0, -14.0), Vector3(5.6, 4.0, 8.0), Basis.IDENTITY, b)
	kd.b("roof", K.dark_steel()).add(Vector3(-41.0, 4.1, -14.0), Vector3(6.0, 0.15, 8.4))
	covers.append(Vector3(-37.6, 0, -14.0))
	K.flush(k, vis)
	K.flush(kd, vis, true, 250.0)

# ------------------------------------------------------------------ Schraegaufzug

static func _skip_bridge(world: Node3D) -> void:
	var b := K.body(world, "SkipBridge", true)
	var vis := Node3D.new()
	vis.name = "SkipVisual"
	world.add_child(vis)
	var k := RailProps.kit()
	var st := K.rust(Color(0.5, 0.42, 0.36))
	var a := Vector3(-56.0, 1.0, 52.0)
	var e := C + Vector3(0, 42.0, 6.0)
	var d := e - a
	var L := d.length()
	var n := int(L / 3.0)
	for sx: float in [-1.4, 1.4]:
		var o := Vector3(sx, 0, 0)
		K.beam(k, "skip", st, a + o, e + o, 0.35)
		K.beam(k, "skip", st, a + o + Vector3(0, 2.6, 0), e + o + Vector3(0, 2.6, 0), 0.3)
		for i in n + 1:
			var p := a + d * (float(i) / n) + o
			K.beam(k, "skip", st, p, p + Vector3(0, 2.6, 0), 0.16)
			if i < n:
				var q := a + d * (float(i + 1) / n) + o
				K.beam(k, "skip", st, p, q + Vector3(0, 2.6, 0), 0.12)
	for i in n + 1:
		var p := a + d * (float(i) / n)
		K.beam(k, "skip", st, p + Vector3(-1.4, 0, 0), p + Vector3(1.4, 0, 0), 0.14)
	# Kuebel
	k.b("skipcar", K.dark_steel()).add(a + d * 0.62 + Vector3(0, 1.0, 0), Vector3(2.0, 1.4, 2.4), K.basis_z(d))
	# Portalstuetzen
	for t: float in [0.3, 0.6]:
		var p := a + d * t
		for sx: float in [-2.2, 2.2]:
			K.beam(k, "skipcol", st, Vector3(p.x + sx, 0, p.z), Vector3(p.x + sx * 0.7, p.y, p.z), 0.5, b)
		K.beam(k, "skipcol", st, Vector3(p.x - 1.6, p.y, p.z), Vector3(p.x + 1.6, p.y, p.z), 0.45)
	# Bunkeranlage am Fuss
	K.box(k, "stock", K.corr(Color(0.55, 0.52, 0.48)), Vector3(-56.0, 5.0, 58.0), Vector3(16.0, 10.0, 10.0), Basis.IDENTITY, b)
	k.b("stock_roof", K.dark_steel()).add(Vector3(-56.0, 10.15, 58.0), Vector3(16.6, 0.3, 10.6))
	K.flush(k, vis, true, 0.0)
