extends RefCounted
## Level 7 "Kaltes Auge": P1 Uebergabeturm mit Aussentreppe, Bandbruecke (Traverse) mit zwei Boecken,
## P2 Ofenbuehne mit Abstiegstreppe, schraege Bandgalerie in den Turm. Statische Funktionen.

const K = preload("res://game/levels/overwatch_world_kit.gd")
const RailProps = preload("res://game/levels/rail_props.gd")
const Geo = preload("res://game/levels/level_geo.gd")

const DECK := 22.0
const FLIGHT := 4.4                    ## Hoehe je Treppenlauf (5 Laeufe = 22 m)
const FLEN := 7.32                     ## Lauflaenge (24 x 0.305)
const LANE_W := 1.3

# P1-Treppe (Spuren entlang Z, +X-Seite)
const P1_LA := 7.75                    ## Spur A (aussen): Laeufe nach -Z
const P1_LB := 5.45                    ## Spur B (am Turm): Laeufe nach +Z
const P1_NZ0 := 7.6                    ## Podest Nord (-Z)
const P1_NZ1 := 9.4
const P1_SZ0 := 16.72                  ## Podest Sued (+Z)
const P1_SZ1 := 18.52
const P1_X0 := 4.62
const P1_X1 := 8.7

# P2-Abstieg (Spuren entlang Z, +Z-Seite der Buehne)
const P2_LO := -44.65                  ## Spur O: Laeufe 1/3/5
const P2_LW := -46.95                  ## Spur W: Laeufe 2/4
const P2_NZ0 := 18.0                   ## Podest an der Buehne
const P2_NZ1 := 19.8
const P2_FZ0 := 27.12                  ## fernes Podest
const P2_FZ1 := 28.92
const P2_X0 := -48.0
const P2_X1 := -43.8

static func build(world: Node3D, covers: Array, rng: RandomNumberGenerator, pts: Dictionary) -> void:
	_p1_tower(world, covers, rng)
	pts["stair_up"] = _p1_stairs(world)
	pts["gantry"] = _gantry(world, rng)
	_trestle(world, -13.0)
	_trestle(world, -24.0)
	_p2_deck(world, covers, rng)
	pts["stair_down"] = _p2_stairs(world)
	_gallery(world)
	pts["p1_snipe"] = Vector3(0.0, DECK, 8.6)
	pts["p2_snipe"] = Vector3(-42.0, DECK, 2.8)

# ------------------------------------------------------------------ gemeinsame Teile

static func _steel() -> StandardMaterial3D:
	return K.rust(Color(0.5, 0.42, 0.36))

static func _plate() -> StandardMaterial3D:
	return K.paint(Color(0.46, 0.45, 0.41))

## Stahlbruestung 1.1 m (Blech + Steifen + Handlauf) entlang einer Deck-Kante, inward = Richtung Deck.
static func _parapet(k: RailProps.Kit, b: StaticBody3D, a: Vector3, bb: Vector3, inward: Vector3) -> void:
	var d := bb - a
	var L := d.length()
	if L < 0.05:
		return
	var rot := K.basis_z(d)
	var c := (a + bb) * 0.5 + inward * 0.04 + Vector3(0, K.RAIL_H * 0.5, 0)
	K.box(k, "parapet", _plate(), c, Vector3(0.06, K.RAIL_H, L), rot, b)
	K.box(k, "parapet_cap", K.dark_steel(), c + Vector3(0, K.RAIL_H * 0.5 + 0.03, 0) + inward * 0.03, Vector3(0.14, 0.06, L + 0.04), rot)
	var n := int(L / 0.9)
	for i in n + 1:
		var p := a + d * (float(i) / maxf(1.0, n)) + inward * 0.1 + Vector3(0, K.RAIL_H * 0.5, 0)
		k.b("parapet_cap", K.dark_steel()).add(p, Vector3(0.1, K.RAIL_H, 0.1) - rot.z.abs() * 0.08)

## Gitterrost-Podest (Optik + Kollision), Oberkante y.
static func _landing(k: RailProps.Kit, b: StaticBody3D, x0: float, x1: float, z0: float, z1: float, y: float, col_z0: float, col_z1: float) -> void:
	var c := Vector3((x0 + x1) * 0.5, y - 0.075, (z0 + z1) * 0.5)
	k.b("landing", K.grating()).add(c, Vector3(x1 - x0, 0.15, z1 - z0))
	k.b("landing_frame", K.dark_steel()).add(c - Vector3(0, 0.15, 0), Vector3(x1 - x0 + 0.06, 0.18, 0.16) * Vector3(1, 1, 1))
	for z: float in [z0 + 0.06, z1 - 0.06]:
		k.b("landing_frame", K.dark_steel()).add(Vector3(c.x, y - 0.2, z), Vector3(x1 - x0, 0.25, 0.12))
	for x: float in [x0 + 0.06, x1 - 0.06]:
		k.b("landing_frame", K.dark_steel()).add(Vector3(x, y - 0.2, c.z), Vector3(0.12, 0.25, z1 - z0))
	K.col(b, Vector3(c.x, y - 0.1, (col_z0 + col_z1) * 0.5), Vector3(x1 - x0, 0.2, col_z1 - col_z0))

# ------------------------------------------------------------------ P1 Uebergabeturm

static func _p1_tower(world: Node3D, covers: Array, rng: RandomNumberGenerator) -> void:
	var b := K.body(world, "P1Tower")
	var vis := Node3D.new()
	vis.name = "P1Visual"
	world.add_child(vis)
	var k := RailProps.kit()
	var kd := RailProps.kit()
	var st := _steel()
	var xs: Array[float] = [-4.3, 0.0, 4.3]
	var zs: Array[float] = [7.7, 12.0, 16.3]
	for x in xs:
		for z in zs:
			if x == 0.0 and z == 12.0:
				continue
			K.column(k, "col", st, Vector3(x, 0, z), 21.75, 0.5, b)
		# Fundamente
	for x in xs:
		for z in zs:
			if not (x == 0.0 and z == 12.0):
				k.b("found", K.concrete()).add(Vector3(x, 0.2, z), Vector3(1.2, 0.4, 1.2))
	# Riegel rundum
	for y: float in [5.5, 11.0, 14.0, 21.45]:
		for z in [7.7, 16.3]:
			K.ibeam(k, "girt", st, Vector3(-4.3, y, z), Vector3(4.3, y, z), 0.42, 0.22, b)
		for x in [-4.3, 4.3]:
			K.ibeam(k, "girt", st, Vector3(x, y, 7.7), Vector3(x, y, 16.3), 0.42, 0.22, b)
		if y > 20.0:
			K.ibeam(k, "girt", st, Vector3(0, y, 7.7), Vector3(0, y, 16.3), 0.42, 0.22, b)
			K.ibeam(k, "girt", st, Vector3(-4.3, y, 12.0), Vector3(4.3, y, 12.0), 0.42, 0.22, b)
	# Kreuzverbaende in den offenen Feldern
	var levels: Array[float] = [0.4, 5.5, 11.0, 14.0]
	for li in levels.size() - 1:
		var y0: float = levels[li]
		var y1: float = levels[li + 1]
		for z in [7.7, 16.3]:
			for xi in 2:
				var xa: float = xs[xi]
				var xb: float = xs[xi + 1]
				K.beam(k, "brace", st, Vector3(xa, y0, z), Vector3(xb, y1, z), 0.16, b)
				K.beam(k, "brace", st, Vector3(xb, y0, z), Vector3(xa, y1, z), 0.16, b)
		for x in [-4.3, 4.3]:
			for zi in 2:
				var za: float = zs[zi]
				var zb: float = zs[zi + 1]
				K.beam(k, "brace", st, Vector3(x, y0, za), Vector3(x, y1, zb), 0.16, b)
				K.beam(k, "brace", st, Vector3(x, y0, zb), Vector3(x, y1, za), 0.16, b)
	# Zwischenboden (Antriebsebene) bei 14 m
	k.b("floor14", K.grating()).add(Vector3(0, 13.9, 12.0), Vector3(8.6, 0.12, 8.6))
	K.col(b, Vector3(0, 13.9, 12.0), Vector3(8.6, 0.12, 8.6))
	# Wellblech-Verkleidung 14..21.4 m, Nordseite mit Oeffnung fuer die Bandgalerie
	var cm := K.corr(Color(0.62, 0.58, 0.54))
	var cy0 := 14.0
	var cy1 := 21.6
	var ch := cy1 - cy0
	var cyc := (cy0 + cy1) * 0.5
	K.box(k, "clad", cm, Vector3(0, cyc, 7.42), Vector3(9.3, ch, 0.08), Basis.IDENTITY, b)
	K.box(k, "clad", cm, Vector3(-4.62, cyc, 12.0), Vector3(0.08, ch, 9.2), Basis.IDENTITY, b)
	K.box(k, "clad", cm, Vector3(4.62, cyc, 12.0), Vector3(0.08, ch, 9.2), Basis.IDENTITY, b)
	# Nord: links/rechts der Galerie + Sturz
	K.box(k, "clad", cm, Vector3(-3.25, cyc, 16.58), Vector3(2.8, ch, 0.08), Basis.IDENTITY, b)
	K.box(k, "clad", cm, Vector3(3.25, cyc, 16.58), Vector3(2.8, ch, 0.08), Basis.IDENTITY, b)
	K.box(k, "clad", cm, Vector3(0, 19.6, 16.58), Vector3(3.7, 4.0, 0.08), Basis.IDENTITY, b)
	# Fensterband und Eckbleche
	var gl := K.glass()
	for z: float in [7.37]:
		for i in 4:
			kd.b("window", gl).add(Vector3(-3.0 + i * 2.0, 19.3, z), Vector3(1.5, 0.9, 0.04))
			kd.b("win_frame", K.dark_steel()).add(Vector3(-3.0 + i * 2.0, 19.3, z + 0.01), Vector3(1.62, 1.02, 0.03))
	for x: float in [-4.67]:
		for i in 3:
			kd.b("window", gl).add(Vector3(x, 19.3, 9.5 + i * 2.6), Vector3(0.04, 0.9, 1.5))
			kd.b("win_frame", K.dark_steel()).add(Vector3(x + 0.01, 19.3, 9.5 + i * 2.6), Vector3(0.03, 1.02, 1.62))
	for c in [Vector2(-4.62, 7.42), Vector2(4.62, 7.42), Vector2(-4.62, 16.58), Vector2(4.62, 16.58)]:
		k.b("trim", K.paint(Color(0.36, 0.35, 0.33))).add(Vector3(c.x, cyc, c.y), Vector3(0.2, ch + 0.1, 0.2))
	for y: float in [cy0, cy1]:
		k.b("trim", K.paint(Color(0.36, 0.35, 0.33))).add(Vector3(0, y, 7.38), Vector3(9.4, 0.12, 0.08))
		k.b("trim", K.paint(Color(0.36, 0.35, 0.33))).add(Vector3(-4.66, y, 12.0), Vector3(0.08, 0.12, 9.4))
		k.b("trim", K.paint(Color(0.36, 0.35, 0.33))).add(Vector3(4.66, y, 12.0), Vector3(0.08, 0.12, 9.4))
	# Deck (Oberkante exakt 22.0)
	K.box(k, "deck", K.grating(), Vector3(0, DECK - 0.125, 12.0), Vector3(9.2, 0.25, 9.2), Basis.IDENTITY, b)
	k.b("deck_edge", K.dark_steel()).add(Vector3(0, DECK - 0.2, 7.42), Vector3(9.3, 0.4, 0.1))
	k.b("deck_edge", K.dark_steel()).add(Vector3(0, DECK - 0.2, 16.58), Vector3(9.3, 0.4, 0.1))
	# Bruestungen (Sued, West mit Bandbruecken-Oeffnung, Ost mit Treppen-Oeffnung)
	_parapet(k, b, Vector3(-4.6, DECK, 7.5), Vector3(4.6, DECK, 7.5), Vector3(0, 0, 1))
	_parapet(k, b, Vector3(-4.5, DECK, 7.55), Vector3(-4.5, DECK, 9.2), Vector3(1, 0, 0))
	_parapet(k, b, Vector3(-4.5, DECK, 11.0), Vector3(-4.5, DECK, 16.5), Vector3(1, 0, 0))
	_parapet(k, b, Vector3(4.5, DECK, 9.4), Vector3(4.5, DECK, 16.5), Vector3(-1, 0, 0))
	var rm := K.rail_yellow()
	K.railing(k, rm, Vector3(-4.45, DECK, 16.45), Vector3(4.45, DECK, 16.45), b)
	# Dach auf vier Stuetzen (27.0 m, hoch genug fuer freie Sicht vom Deck)
	for c in [Vector2(-4.25, 7.75), Vector2(4.25, 7.75), Vector2(-4.25, 16.25), Vector2(4.25, 16.25)]:
		K.column(k, "col", st, Vector3(c.x, DECK, c.y), 4.85, 0.26, b)
	for z: float in [7.75, 12.0, 16.25]:
		K.ibeam(k, "girt", st, Vector3(-4.6, 26.75, z), Vector3(4.6, 26.75, z), 0.32, 0.18, b)
	for x: float in [-4.25, -1.4, 1.4, 4.25]:
		K.beam(k, "brace", st, Vector3(x, 26.95, 7.4), Vector3(x, 26.95, 16.6), 0.14)
	K.box(k, "roof", K.corr(Color(0.5, 0.47, 0.44)), Vector3(0, 27.06, 12.0), Vector3(10.0, 0.08, 10.0), Basis.IDENTITY, b)
	k.b("trim", K.paint(Color(0.36, 0.35, 0.33))).add(Vector3(0, 27.06, 7.0), Vector3(10.1, 0.22, 0.06))
	# Kopfstation: Antriebstrommel, Getriebe, Motor, Schurre (Deckung auf dem Deck)
	var drum_m := K.dark_steel()
	K.pipe(kd, "drum", drum_m, Vector3(-1.0, 22.95, 11.1), Vector3(-1.0, 22.95, 12.7), 0.45, 16)
	for z: float in [11.0, 12.8]:
		kd.b("frame", st).add(Vector3(-1.0, 22.5, z), Vector3(0.9, 1.0, 0.16))
	kd.b("frame", st).add(Vector3(-2.9, 22.45, 11.25), Vector3(3.2, 0.9, 0.12))
	kd.b("frame", st).add(Vector3(-2.9, 22.45, 12.55), Vector3(3.2, 0.9, 0.12))
	kd.b("belt", K.black()).add(Vector3(-2.75, 22.95, 11.9), Vector3(3.5, 0.06, 1.1))
	kd.b("gear", K.paint(Color(0.28, 0.36, 0.3))).add(Vector3(-1.0, 22.7, 13.45), Vector3(1.0, 1.1, 1.0))
	K.pipe(kd, "gear", K.paint(Color(0.28, 0.36, 0.3)), Vector3(-1.0, 22.6, 13.95), Vector3(-1.0, 22.6, 15.3), 0.36, 14)
	kd.b("gear", K.paint(Color(0.28, 0.36, 0.3))).add(Vector3(-1.0, 22.25, 14.6), Vector3(0.8, 0.5, 1.6))
	kd.b("chute", K.rust(Color(0.45, 0.36, 0.3))).add(Vector3(0.2, 22.5, 11.9), Vector3(1.4, 1.0, 1.7))
	kd.b("chute", K.rust(Color(0.45, 0.36, 0.3))).add(Vector3(0.2, 23.15, 11.9), Vector3(1.8, 0.3, 2.0))
	K.col(b, Vector3(-1.0, 22.75, 12.4), Vector3(2.2, 1.5, 3.0))
	K.col(b, Vector3(-2.9, 22.5, 11.9), Vector3(3.2, 1.0, 1.4))
	K.col(b, Vector3(-1.0, 22.5, 14.6), Vector3(1.0, 1.0, 1.4))
	# Schaltwarte (kleine Kabine) in der Nordost-Ecke
	var cab_m := K.worn_corr(Color(0.62, 0.66, 0.62))
	K.box(kd, "cabin", cab_m, Vector3(2.85, 23.25, 14.95), Vector3(2.7, 2.5, 2.7), Basis.IDENTITY, b)
	kd.b("cab_roof", K.dark_steel()).add(Vector3(2.85, 24.55, 14.95), Vector3(3.0, 0.1, 3.0))
	kd.b("window", gl).add(Vector3(2.85, 23.6, 13.58), Vector3(1.8, 0.8, 0.03))
	kd.b("win_frame", K.dark_steel()).add(Vector3(2.85, 23.6, 13.585), Vector3(1.95, 0.95, 0.02))
	kd.b("door", K.paint(Color(0.3, 0.33, 0.3))).add(Vector3(1.49, 23.0, 15.4), Vector3(0.03, 2.0, 0.9))
	covers.append(Vector3(2.85, DECK, 13.0))
	# Kabeltrasse an der Nordbruestung, Schaltschrank
	kd.b("tray", K.dark_steel()).add(Vector3(0, 22.9, 16.3), Vector3(8.6, 0.06, 0.35))
	for i in 5:
		K.pipe(kd, "cable", K.black(), Vector3(-4.3, 22.96, 16.2 + i * 0.05), Vector3(4.3, 22.96, 16.2 + i * 0.05), 0.025, 6)
	kd.b("cabinet", K.paint(Color(0.55, 0.55, 0.5))).add(Vector3(-3.7, 22.9, 15.8), Vector3(1.0, 1.8, 0.5))
	K.col(b, Vector3(-3.7, 22.9, 15.8), Vector3(1.0, 1.8, 0.5))
	# Lampen unter dem Dach (aus, Daemmerung)
	for x: float in [-2.5, 2.5]:
		kd.b("lamp", K.lamp_glow(Color(1.0, 0.8, 0.55), 1.5)).add(Vector3(x, 26.65, 10.0), Vector3(0.5, 0.12, 0.25))
	# Leitung + Steigleitung aussen an der Westseite
	K.pipe(kd, "pipe", K.paint(Color(0.55, 0.5, 0.32)), Vector3(-4.8, 0.3, 15.8), Vector3(-4.8, 21.6, 15.8), 0.12, 8)
	K.pipe(kd, "pipe", K.paint(Color(0.55, 0.5, 0.32)), Vector3(-4.95, 0.3, 15.3), Vector3(-4.95, 21.6, 15.3), 0.09, 8)
	for y in range(2, 21, 3):
		kd.b("frame", st).add(Vector3(-4.75, float(y), 15.55), Vector3(0.4, 0.08, 0.9))
	# Bodenlevel: Stahlkasten (Antriebsstation) im Turmfuss
	K.box(k, "cabin_low", K.corr(Color(0.5, 0.52, 0.5)), Vector3(-1.5, 1.6, 13.5), Vector3(4.5, 3.2, 4.0), Basis.IDENTITY, b)
	k.b("cab_roof", K.dark_steel()).add(Vector3(-1.5, 3.25, 13.5), Vector3(4.8, 0.12, 4.3))
	kd.b("door", K.paint(Color(0.3, 0.33, 0.3))).add(Vector3(-1.5, 1.1, 11.49), Vector3(1.2, 2.1, 0.03))
	covers.append(Vector3(-1.5, 0, 10.8))
	K.flush(k, vis)
	K.flush(kd, vis, true, 260.0)

# ------------------------------------------------------------------ P1 Aussentreppe

static func _p1_stairs(world: Node3D) -> Array:
	var b := K.body(world, "P1Stairs")
	var vis := Node3D.new()
	vis.name = "P1StairVisual"
	world.add_child(vis)
	var k := RailProps.kit()
	var rm := K.rail_yellow()
	var st := _steel()
	var path: Array = [Vector3(P1_LA, 0, 19.4), Vector3(P1_LA, 0, P1_SZ0 + 0.1)]
	var y := 0.0
	for f in 5:
		var lane_a := f % 2 == 0
		var x := P1_LA if lane_a else P1_LB
		var z0 := P1_SZ0 if lane_a else P1_NZ1
		var dir := Vector3(0, 0, -1) if lane_a else Vector3(0, 0, 1)
		K.stair_flight(k, b, Vector3(x, y, z0), dir, FLIGHT, LANE_W, true, true, rm)
		y += FLIGHT
		var zend := z0 + dir.z * FLEN
		path.append(Vector3(x, y, zend - dir.z * 0.1))
		# Podest am Laufende
		var north := lane_a
		var lz0 := P1_NZ0 if north else P1_SZ0
		var lz1 := P1_NZ1 if north else P1_SZ1
		var cz0 := lz0 if north else lz0 - 0.32
		var cz1 := lz1 + 0.32 if north else lz1
		var x0 := P1_X0
		if f == 4:
			x0 = 4.42
		_landing(k, b, x0, P1_X1, lz0, lz1, y, cz0, cz1)
		var mid := (lz0 + lz1) * 0.5
		var far_edge := lz0 + 0.05 if north else lz1 - 0.05
		# Gelaender: Stirnseite, Aussenseite, Turmseite (oben offen zum Deck)
		K.railing(k, rm, Vector3(P1_X0, y, far_edge), Vector3(P1_X1 - 0.05, y, far_edge), b)
		K.railing(k, rm, Vector3(P1_X1 - 0.05, y, lz0), Vector3(P1_X1 - 0.05, y, lz1), b)
		if f < 4:
			K.railing(k, rm, Vector3(P1_X0 + 0.05, y, lz0), Vector3(P1_X0 + 0.05, y, lz1), b)
		# Spalt zwischen den Spuren an der Laufkante
		var edge := lz1 if north else lz0
		K.railing(k, rm, Vector3(6.14, y, edge), Vector3(7.06, y, edge), b, K.RAIL_H, false)
		if f == 4:
			# oben kein weiterer Lauf in Spur B
			K.railing(k, rm, Vector3(P1_X0, y, edge), Vector3(6.14, y, edge), b)
			path.append(Vector3(P1_LA, y, mid))
			path.append(Vector3(4.5, y, mid))
			path.append(Vector3(2.0, y, 9.6))
		else:
			var nx := P1_LB if lane_a else P1_LA
			path.append(Vector3(x, y, mid))
			path.append(Vector3(nx, y, mid))
			path.append(Vector3(nx, y, edge + (0.1 if north else -0.1)))
	# Stuetzen und Verbaende der Treppe
	for z: float in [P1_NZ0, P1_NZ1, P1_SZ0, P1_SZ1]:
		K.column(k, "scol", st, Vector3(P1_X1 + 0.05, 0, z), 22.0 + (0.0 if z < 10.0 else -4.4), 0.24, b)
	K.column(k, "scol", st, Vector3(4.62, 0, P1_SZ1), 17.6, 0.24, b)
	var lv: Array[float] = [0.3, 4.4, 8.8, 13.2, 17.6]
	for i in lv.size() - 1:
		K.beam(k, "sbrace", st, Vector3(P1_X1 + 0.05, lv[i], P1_NZ1), Vector3(P1_X1 + 0.05, lv[i + 1], P1_SZ0), 0.12, b)
		K.beam(k, "sbrace", st, Vector3(P1_X1 + 0.05, lv[i], P1_SZ1), Vector3(4.62, lv[i + 1], P1_SZ1), 0.12, b)
	K.flush(k, vis)
	return path

# ------------------------------------------------------------------ Bandbruecke P1 -> P2

static func _gantry(world: Node3D, rng: RandomNumberGenerator) -> Array:
	var b := K.body(world, "Gantry")
	var vis := Node3D.new()
	vis.name = "GantryVisual"
	world.add_child(vis)
	var k := RailProps.kit()
	var kd := RailProps.kit()
	var st := _steel()
	var xa := -4.5
	var xb := -36.0
	var L := absf(xb - xa)
	var xc := (xa + xb) * 0.5
	var zs := 8.9          # Suedgurt
	var zn := 12.9         # Nordgurt
	# Laufsteg (Oberkante 22.0) und Bandboden
	K.box(k, "walk", K.grating(), Vector3(xc, DECK - 0.06, 10.1), Vector3(L, 0.12, 1.8), Basis.IDENTITY, b)
	k.b("walk_edge", K.dark_steel()).add(Vector3(xc, DECK - 0.17, 9.18), Vector3(L, 0.3, 0.06))
	K.box(k, "beltdeck", K.dark_steel(), Vector3(xc, 21.9, 11.95), Vector3(L, 0.08, 1.9), Basis.IDENTITY, b)
	# Quertraeger + Untergurte
	var n := 10
	for i in n + 1:
		var x := xa + (xb - xa) * float(i) / n
		K.ibeam(k, "cross", st, Vector3(x, 21.65, zs), Vector3(x, 21.65, zn), 0.4, 0.2)
	K.col(b, Vector3(xc, 21.65, 10.9), Vector3(L, 0.4, 4.0))
	# Seitenfachwerke (offen) und Dachverband
	K.truss(k, "truss", st, Vector3(xa, 21.6, zs), Vector3(xb, 21.6, zs), 3.6, L / n, 0.17, b)
	K.truss(k, "truss", st, Vector3(xa, 21.6, zn), Vector3(xb, 21.6, zn), 3.6, L / n, 0.17, b)
	for i in n + 1:
		var x := xa + (xb - xa) * float(i) / n
		K.beam(k, "truss", st, Vector3(x, 25.2, zs), Vector3(x, 25.2, zn), 0.16, b)
		if i < n:
			var x2 := xa + (xb - xa) * float(i + 1) / n
			K.beam(k, "rbrace", st, Vector3(x, 25.2, zs), Vector3(x2, 25.2, zn), 0.08)
	# Wellblechdach nur ueber dem Band (Laufsteg bleibt offen)
	K.box(k, "roof", K.corr(Color(0.52, 0.48, 0.45)), Vector3(xc, 25.4, 12.1), Vector3(L + 0.4, 0.07, 2.3), Basis(Vector3.RIGHT, -0.06), b)
	K.box(kd, "side", K.corr(Color(0.5, 0.47, 0.44)), Vector3(xc, 24.4, zn + 0.12), Vector3(L, 1.6, 0.06), Basis.IDENTITY, b)
	# Gelaender beidseits des Stegs
	var rm := K.rail_yellow()
	K.railing(k, rm, Vector3(xa, DECK, 9.26), Vector3(xb, DECK, 9.26), b)
	K.railing(k, rm, Vector3(xa, DECK, 10.95), Vector3(xb, DECK, 10.95), b)
	# Foerderband: Tragrollen (Mulde), Gurt, Untertrum, Erzschuettung
	var belt := K.black()
	var roll := K.dark_steel()
	var x := xa - 0.6
	while x > xb + 0.5:
		kd.b("idler", st).add(Vector3(x, 22.25, 11.95), Vector3(0.1, 0.5, 1.5))
		K.pipe(kd, "roller", roll, Vector3(x, 22.62, 11.72), Vector3(x, 22.62, 12.18), 0.06, 8)
		K.pipe(kd, "roller", roll, Vector3(x, 22.62, 11.7), Vector3(x, 22.86, 11.3), 0.06, 8)
		K.pipe(kd, "roller", roll, Vector3(x, 22.62, 12.2), Vector3(x, 22.86, 12.6), 0.06, 8)
		x -= 1.25
	kd.b("belt", belt).add(Vector3(xc, 22.69, 11.95), Vector3(L, 0.03, 0.5))
	kd.b("belt", belt).add(Vector3(xc, 22.8, 11.47), Vector3(L, 0.03, 0.5), Basis(Vector3.RIGHT, 0.55))
	kd.b("belt", belt).add(Vector3(xc, 22.8, 12.43), Vector3(L, 0.03, 0.5), Basis(Vector3.RIGHT, -0.55))
	kd.b("belt", belt).add(Vector3(xc, 22.08, 11.95), Vector3(L, 0.02, 1.0))
	var ore := K.ore()
	x = xa - 0.4
	while x > xb + 0.4:
		kd.b("ore", ore).add_ball(Vector3(x, 22.78, 11.95 + rng.randf_range(-0.12, 0.12)), Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(0.12, 0.22), rng.randf_range(0.5, 0.75)))
		x -= rng.randf_range(0.35, 0.6)
	K.col(b, Vector3(xc, 22.45, 11.95), Vector3(L, 0.9, 1.4))
	# Kabeltrasse am Nordfachwerk, Leuchten
	kd.b("tray", K.dark_steel()).add(Vector3(xc, 24.1, zn - 0.25), Vector3(L, 0.06, 0.4))
	for i in 4:
		K.pipe(kd, "cable", belt, Vector3(xa, 24.16, zn - 0.36 + i * 0.07), Vector3(xb, 24.16, zn - 0.36 + i * 0.07), 0.025, 6)
	var lx := xa - 3.0
	while lx > xb:
		kd.b("lamp", K.lamp_glow(Color(1.0, 0.8, 0.55), 2.0)).add(Vector3(lx, 25.0, 10.1), Vector3(0.35, 0.1, 0.2))
		lx -= 6.3
	K.flush(k, vis)
	K.flush(kd, vis, true, 240.0)
	var pts: Array = []
	var gx := xa
	while gx >= xb - 0.01:
		pts.append(Vector3(gx, DECK, 10.1))
		gx -= 3.5
	if absf(float((pts[pts.size() - 1] as Vector3).x) - xb) > 0.2:
		pts.append(Vector3(xb, DECK, 10.1))
	return pts

## Gittermast-Bock unter der Bandbruecke (vier geneigte Stiele, Riegel, Kreuzverbaende).
static func _trestle(world: Node3D, xc: float) -> void:
	var b := K.body(world, "Trestle%d" % int(absf(xc)))
	var vis := Node3D.new()
	vis.name = "TrestleVisual"
	world.add_child(vis)
	var k := RailProps.kit()
	var st := _steel()
	var top_y := 21.45
	var corners: Array = []
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var base := Vector3(xc + sx * 2.4, 0.0, 10.9 + sz * 3.3)
			var top := Vector3(xc + sx * 1.3, top_y, 10.9 + sz * 2.0)
			corners.append([base, top])
			K.beam(k, "leg", st, base, top, 0.45, b)
			k.b("found", K.concrete()).add(base + Vector3(0, 0.3, 0), Vector3(1.5, 0.6, 1.5))
	var levels: Array[float] = [0.0, 5.4, 10.7, 16.1, top_y]
	for li in levels.size():
		var t: float = levels[li] / top_y
		var ring: Array = []
		for c: Array in corners:
			ring.append((c[0] as Vector3).lerp(c[1] as Vector3, t))
		if li > 0:
			var order: Array[int] = [0, 1, 3, 2, 0]
			for oi in 4:
				K.beam(k, "strut", st, ring[order[oi]], ring[order[oi + 1]], 0.22, b)
		if li < levels.size() - 1:
			var t2: float = levels[li + 1] / top_y
			var ring2: Array = []
			for c: Array in corners:
				ring2.append((c[0] as Vector3).lerp(c[1] as Vector3, t2))
			var order2: Array[int] = [0, 1, 3, 2, 0]
			for oi in 4:
				var a0: Vector3 = ring[order2[oi]]
				var a1: Vector3 = ring[order2[oi + 1]]
				var b0: Vector3 = ring2[order2[oi]]
				var b1: Vector3 = ring2[order2[oi + 1]]
				K.beam(k, "xbrace", st, a0, b1, 0.12, b)
				K.beam(k, "xbrace", st, a1, b0, 0.12, b)
	K.ibeam(k, "strut", st, Vector3(xc - 1.6, top_y, 8.9), Vector3(xc + 1.6, top_y, 8.9), 0.4, 0.25)
	K.ibeam(k, "strut", st, Vector3(xc - 1.6, top_y, 12.9), Vector3(xc + 1.6, top_y, 12.9), 0.4, 0.25)
	K.ladder(k, K.dark_steel(), Vector3(xc + 1.85, 0.0, 10.9), 21.2, Vector3(-1, 0, 0), true)
	K.flush(k, vis)

# ------------------------------------------------------------------ P2 Ofenbuehne

static func _p2_deck(world: Node3D, covers: Array, rng: RandomNumberGenerator) -> void:
	var b := K.body(world, "P2Deck")
	var vis := Node3D.new()
	vis.name = "P2Visual"
	world.add_child(vis)
	var k := RailProps.kit()
	var kd := RailProps.kit()
	var st := _steel()
	var xs: Array[float] = [-47.7, -42.0, -36.3]
	var zs: Array[float] = [2.3, 10.0, 17.7]
	for x in xs:
		for z in zs:
			K.column(k, "col", st, Vector3(x, 0, z), 21.75, 0.55, b)
			k.b("found", K.concrete()).add(Vector3(x, 0.2, z), Vector3(1.3, 0.4, 1.3))
	for y: float in [7.2, 14.4, 21.45]:
		for z in zs:
			K.ibeam(k, "girt", st, Vector3(-47.7, y, z), Vector3(-36.3, y, z), 0.5, 0.25, b)
		for x in xs:
			K.ibeam(k, "girt", st, Vector3(x, y, 2.3), Vector3(x, y, 17.7), 0.5, 0.25, b)
	var lv: Array[float] = [0.4, 7.2, 14.4, 21.45]
	for li in lv.size() - 1:
		for xi in 2:
			K.beam(k, "brace", st, Vector3(xs[xi], lv[li], 2.3), Vector3(xs[xi + 1], lv[li + 1], 2.3), 0.18, b)
			K.beam(k, "brace", st, Vector3(xs[xi + 1], lv[li], 2.3), Vector3(xs[xi], lv[li + 1], 2.3), 0.18, b)
		for zi in 2:
			K.beam(k, "brace", st, Vector3(-36.3, lv[li], zs[zi]), Vector3(-36.3, lv[li + 1], zs[zi + 1]), 0.18, b)
			K.beam(k, "brace", st, Vector3(-36.3, lv[li], zs[zi + 1]), Vector3(-36.3, lv[li + 1], zs[zi]), 0.18, b)
	# Deck
	K.box(k, "deck", K.grating(), Vector3(-42.0, DECK - 0.125, 10.0), Vector3(12.0, 0.25, 16.0), Basis.IDENTITY, b)
	k.b("deck_edge", K.dark_steel()).add(Vector3(-42.0, DECK - 0.25, 2.0), Vector3(12.1, 0.5, 0.12))
	k.b("deck_edge", K.dark_steel()).add(Vector3(-36.0, DECK - 0.25, 10.0), Vector3(0.12, 0.5, 16.1))
	# Bruestungen
	_parapet(k, b, Vector3(-48.0, DECK, 2.0), Vector3(-36.0, DECK, 2.0), Vector3(0, 0, 1))
	_parapet(k, b, Vector3(-48.0, DECK, 2.05), Vector3(-48.0, DECK, 18.0), Vector3(1, 0, 0))
	_parapet(k, b, Vector3(-36.0, DECK, 2.05), Vector3(-36.0, DECK, 9.2), Vector3(-1, 0, 0))
	_parapet(k, b, Vector3(-36.0, DECK, 11.0), Vector3(-36.0, DECK, 18.0), Vector3(-1, 0, 0))
	K.railing(k, K.rail_yellow(), Vector3(-43.8, DECK, 17.95), Vector3(-36.05, DECK, 17.95), b)
	# Ausstattung: Windenhaus, Rohrbuendel, Gasflaschen, Kisten, Schwenkkran
	var hm := K.worn_corr(Color(0.6, 0.6, 0.56))
	K.box(kd, "house", hm, Vector3(-38.6, 23.4, 15.4), Vector3(4.2, 2.8, 4.0), Basis.IDENTITY, b)
	kd.b("roof", K.dark_steel()).add(Vector3(-38.6, 24.86, 15.4), Vector3(4.5, 0.12, 4.3))
	kd.b("door", K.paint(Color(0.33, 0.3, 0.27))).add(Vector3(-38.6, 23.05, 13.39), Vector3(1.0, 2.1, 0.03))
	kd.b("window", K.glass()).add(Vector3(-40.71, 23.7, 15.4), Vector3(0.03, 0.8, 1.6))
	covers.append(Vector3(-38.6, DECK, 12.6))
	var pipe_m := K.paint(Color(0.5, 0.46, 0.3))
	for i in 3:
		var pz := 0.45 * i
		K.pipe(kd, "pipes", pipe_m, Vector3(-46.9 + pz, 22.55, 3.4), Vector3(-46.9 + pz, 22.55, 16.6), 0.17, 10)
	for z in range(4, 17, 3):
		kd.b("stand", st).add(Vector3(-46.45, 22.2, float(z)), Vector3(1.5, 0.4, 0.15))
	K.col(b, Vector3(-46.45, 22.4, 10.0), Vector3(1.5, 0.8, 13.2))
	# Gasflaschen-Gestell
	for i in 6:
		K.pipe(kd, "bottle", K.paint(Color(0.2, 0.32, 0.5) if i % 2 == 0 else Color(0.55, 0.12, 0.08)), Vector3(-36.9, 22.0, 5.0 + i * 0.32), Vector3(-36.9, 23.5, 5.0 + i * 0.32), 0.12, 8)
	kd.b("stand", st).add(Vector3(-36.9, 23.0, 5.8), Vector3(0.35, 0.06, 2.1))
	K.col(b, Vector3(-36.9, 22.75, 5.8), Vector3(0.4, 1.5, 2.1))
	RailProps.crate_stack(world, Vector3(-40.5, DECK, 7.2), 15.0, rng, covers)
	RailProps.crate_stack(world, Vector3(-44.0, DECK, 12.8), -70.0, rng, covers)
	# Schwenkkran (Saeule + Ausleger)
	K.pipe(kd, "crane", K.rail_yellow(), Vector3(-46.9, 22.0, 6.5), Vector3(-46.9, 26.5, 6.5), 0.18, 10)
	kd.b("crane", K.rail_yellow()).add(Vector3(-49.2, 26.3, 6.5), Vector3(4.8, 0.35, 0.25))
	K.beam(kd, "crane", K.rail_yellow(), Vector3(-46.9, 25.0, 6.5), Vector3(-50.5, 26.15, 6.5), 0.1)
	K.pipe(kd, "chain", K.black(), Vector3(-50.6, 26.1, 6.5), Vector3(-50.6, 23.8, 6.5), 0.02, 4)
	K.col(b, Vector3(-46.9, 24.25, 6.5), Vector3(0.36, 4.5, 0.36))
	# Unter der Buehne: Torpedopfannenwagen auf Gleis
	_torpedo_car(world, Vector3(-42.0, 0.0, 10.0))
	K.flush(k, vis)
	K.flush(kd, vis, true, 240.0)

static func _torpedo_car(world: Node3D, p: Vector3) -> void:
	var b := Geo.static_body()
	b.name = "TorpedoCar"
	b.set_meta("no_fit", true)
	world.add_child(b)
	var k := RailProps.kit()
	RailProps.track(k, p.x, p.z + 14.0, p.z - 14.0, RandomNumberGenerator.new())
	var shell := K.rust(Color(0.32, 0.27, 0.24))
	K.pipe(k, "torp", shell, p + Vector3(0, 2.6, -4.0), p + Vector3(0, 2.6, 4.0), 1.7, 20)
	K.add_mesh(k, "torp", shell, _cone_mesh(1.7, 0.7, 3.2), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 2.6, 5.6)))
	K.add_mesh(k, "torp", shell, _cone_mesh(1.7, 0.7, 3.2), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), p + Vector3(0, 2.6, -5.6)))
	k.b("torp_frame", K.dark_steel()).add(p + Vector3(0, 0.95, 0), Vector3(2.6, 0.5, 15.0))
	for z: float in [-5.5, -2.5, 2.5, 5.5]:
		for s: float in [-0.76, 0.76]:
			K.pipe(k, "wheel", K.dark_steel(), p + Vector3(s - 0.06, 0.46, z), p + Vector3(s + 0.06, 0.46, z), 0.45, 12)
	k.b("torp_frame", K.dark_steel()).add(p + Vector3(0, 4.35, 0), Vector3(1.4, 0.25, 1.8))
	K.col(b, p + Vector3(0, 2.4, 0), Vector3(3.2, 4.0, 15.0))
	K.flush(k, b, true, 220.0)

static func _cone_mesh(r0: float, r1: float, h: float) -> CylinderMesh:
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = h
	cm.radial_segments = 20
	cm.rings = 1
	return cm

# ------------------------------------------------------------------ P2 Abstiegstreppe

static func _p2_stairs(world: Node3D) -> Array:
	var b := K.body(world, "P2Stairs")
	var vis := Node3D.new()
	vis.name = "P2StairVisual"
	world.add_child(vis)
	var k := RailProps.kit()
	var rm := K.rail_yellow()
	var st := _steel()
	# Laeufe von unten nach oben bauen: 5 (Spur O, Boden) .. 1 (Spur O, Deck)
	var y := 0.0
	for f in 5:
		var lane_o := f % 2 == 0
		var x := P2_LO if lane_o else P2_LW
		var z0 := P2_FZ0 if lane_o else P2_NZ1
		var dir := Vector3(0, 0, -1) if lane_o else Vector3(0, 0, 1)
		K.stair_flight(k, b, Vector3(x, y, z0), dir, FLIGHT, LANE_W, true, true, rm)
		y += FLIGHT
		var near := lane_o            # Lauf endet am Podest an der Buehne
		var lz0 := P2_NZ0 if near else P2_FZ0
		var lz1 := P2_NZ1 if near else P2_FZ1
		var cz0 := lz0 if near else lz0 - 0.32
		var cz1 := lz1 + 0.32 if near else lz1
		_landing(k, b, P2_X0, P2_X1, lz0 - (0.3 if (near and f == 4) else 0.0), lz1, y, cz0 - (0.3 if (near and f == 4) else 0.0), cz1)
		var far_edge := lz0 + 0.05 if near else lz1 - 0.05
		var edge := lz1 if near else lz0
		if f < 4:
			K.railing(k, rm, Vector3(P2_X0 + 0.05, y, far_edge), Vector3(P2_X1 - 0.05, y, far_edge), b)
		K.railing(k, rm, Vector3(P2_X0 + 0.05, y, lz0), Vector3(P2_X0 + 0.05, y, lz1), b)
		K.railing(k, rm, Vector3(P2_X1 - 0.05, y, lz0), Vector3(P2_X1 - 0.05, y, lz1), b)
		K.railing(k, rm, Vector3(-46.24, y, edge), Vector3(-45.36, y, edge), b, K.RAIL_H, false)
		if f == 4:
			K.railing(k, rm, Vector3(P2_X0 + 0.05, y, edge), Vector3(-46.24, y, edge), b)
	# Stuetzen (aussen am fernen Podest) und Verbaende
	for x: float in [P2_X0 - 0.05, P2_X1 + 0.05]:
		K.column(k, "scol", st, Vector3(x, 0, P2_FZ1 + 0.05), 17.6, 0.24, b)
		K.column(k, "scol", st, Vector3(x, 0, P2_NZ1 + 0.05), 22.0, 0.24, b)
		var lv: Array[float] = [0.3, 4.4, 8.8, 13.2, 17.6]
		for i in lv.size() - 1:
			K.beam(k, "sbrace", st, Vector3(x, lv[i], P2_NZ1 + 0.05), Vector3(x, lv[i + 1], P2_FZ1 + 0.05), 0.12, b)
	K.flush(k, vis)
	# Laufweg (Deck -> Boden)
	var p: Array = [Vector3(P2_LO, DECK, 15.5), Vector3(P2_LO, DECK, P2_NZ1 + 0.1)]
	y = DECK
	for f in 5:
		var lane_o := f % 2 == 0
		var x := P2_LO if lane_o else P2_LW
		var dz := 1.0 if lane_o else -1.0
		var zs := P2_NZ1 if lane_o else P2_FZ0
		var ze := zs + dz * FLEN
		y -= FLIGHT
		p.append(Vector3(x, y, ze + dz * 0.12))
		if f < 4:
			var mid := (P2_FZ0 + P2_FZ1) * 0.5 if lane_o else (P2_NZ0 + P2_NZ1) * 0.5
			var nx := P2_LW if lane_o else P2_LO
			p.append(Vector3(x, y, mid))
			p.append(Vector3(nx, y, mid))
			p.append(Vector3(nx, y, ze - dz * 0.12))
	p.append(Vector3(P2_LO, 0.0, 28.1))
	return p

# ------------------------------------------------------------------ Bandgalerie (schraeg in den Turm)

static func _gallery(world: Node3D) -> void:
	var b := K.body(world, "Gallery")
	var vis := Node3D.new()
	vis.name = "GalleryVisual"
	world.add_child(vis)
	var k := RailProps.kit()
	var kd := RailProps.kit()
	var st := _steel()
	var a := Vector3(0, 14.0, 16.6)        # Boden der Galerie am Turm
	var e := Vector3(0, 3.2, 47.0)         # unteres Ende (Aufgabestation)
	var d := e - a
	var L := d.length()
	var rot := K.basis_z(d)
	var up := rot.y
	var side := rot.x
	var c := (a + e) * 0.5
	var w := 3.6
	var h := 3.0
	var cm := K.corr(Color(0.6, 0.57, 0.52))
	K.box(k, "gal_wall", cm, c + up * (h * 0.5) + side * (w * 0.5), Vector3(0.07, h, L), rot)
	K.box(k, "gal_wall", cm, c + up * (h * 0.5) - side * (w * 0.5), Vector3(0.07, h, L), rot)
	K.box(k, "gal_roof", K.corr(Color(0.48, 0.45, 0.42)), c + up * (h + 0.05), Vector3(w + 0.3, 0.07, L), rot)
	K.box(k, "gal_floor", K.dark_steel(), c, Vector3(w, 0.15, L), rot)
	K.col(b, c + up * (h * 0.5), Vector3(w + 0.2, h + 0.2, L), rot)
	# Untergurt-Fachwerk beidseits
	for s: float in [-1.0, 1.0]:
		var o := side * s * (w * 0.5 + 0.06)
		var n := int(L / 2.6)
		K.beam(k, "gal_truss", st, a + o - up * 1.2, e + o - up * 1.2, 0.2)
		for i in n + 1:
			var p := a + d * (float(i) / n) + o
			K.beam(k, "gal_truss", st, p, p - up * 1.2, 0.14)
			if i < n:
				var q := a + d * (float(i + 1) / n) + o
				K.beam(k, "gal_truss", st, p, q - up * 1.2, 0.12)
		# Rippen auf dem Wellblech
		for i in int(L / 1.8):
			var p2 := a + d * ((float(i) + 0.5) / int(L / 1.8)) + side * s * (w * 0.5 + 0.06)
			kd.b("gal_rib", K.dark_steel()).add(p2 + up * (h * 0.5), Vector3(0.06, h, 0.1), rot)
	# Fensterband
	for i in int(L / 3.0):
		var p3 := a + d * ((float(i) + 0.5) / int(L / 3.0))
		for s: float in [-1.0, 1.0]:
			kd.b("gal_win", K.glass()).add(p3 + up * 2.1 + side * s * (w * 0.5 + 0.05), Vector3(0.03, 0.55, 1.2), rot)
	# Portalstuetzen
	for t: float in [0.36, 0.7]:
		var p := a + d * t
		var under := p.y - 1.25
		for s: float in [-1.0, 1.0]:
			K.column(k, "gal_col", st, Vector3(s * 2.45, 0, p.z), under, 0.4, b)
		K.ibeam(k, "gal_col", st, Vector3(-2.6, under, p.z), Vector3(2.6, under, p.z), 0.45, 0.25, b)
		K.beam(k, "gal_col", st, Vector3(-2.45, 0.4, p.z), Vector3(2.45, under - 0.5, p.z), 0.14, b)
		k.b("found", K.concrete()).add(Vector3(-2.45, 0.2, p.z), Vector3(1.0, 0.4, 1.0))
		k.b("found", K.concrete()).add(Vector3(2.45, 0.2, p.z), Vector3(1.0, 0.4, 1.0))
	# Aufgabestation am unteren Ende
	var hm := K.corr(Color(0.56, 0.54, 0.5))
	K.box(k, "gal_house", hm, Vector3(0, 3.5, 51.0), Vector3(8.0, 7.0, 8.0), Basis.IDENTITY, b)
	k.b("gal_house_roof", K.dark_steel()).add(Vector3(0, 7.1, 51.0), Vector3(8.4, 0.2, 8.4))
	kd.b("door", K.paint(Color(0.32, 0.3, 0.27))).add(Vector3(4.02, 1.6, 50.0), Vector3(0.03, 3.2, 3.0))
	K.flush(k, vis)
	K.flush(kd, vis, true, 220.0)
