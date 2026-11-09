extends RefCounted
## Stahlfachwerk-Strassenbruecke ueber die Welikaja (Level river_crossing).
## Drei Felder mit untenliegender Fahrbahn: Fahrbahnplatte (Deckoberkante y = 0), zwei Fachwerktraeger
## bei x = +-6.6 mit Ober-/Untergurt, Diagonalen, Pfosten und oberem Windverband, Laengs-/Quertraeger
## unter der Platte, Gehweg mit Gelaender. Strompfeiler und Widerlager aus Beton.
## Feld 1 (West) wird als AnimatableBody3D gebaut und stuerzt im Spiel ein (siehe river_crossing.gd).

const Geo = preload("res://game/levels/level_geo.gd")
const RP = preload("res://game/levels/river_props.gd")
const Props = preload("res://game/levels/level_props.gd")

const HALF_W := 6.6          ## Fachwerkachse (x)
const DECK_T := 0.8
const TRUSS_H := 8.0
const WATER_Y := -9.0
const BED_Y := -15.0

## Baut ein Feld in parent (lokale Koordinaten), Fahrbahn von z0 (West, groesser) bis z1 (Ost).
## body: Kollisionen (Platte + seitliche Waende) werden hier angehaengt.
static func build_span(parent: Node3D, body: CollisionObject3D, z0: float, z1: float, rng: RandomNumberGenerator, damaged: bool = false) -> void:
	var L := z0 - z1
	var zc := (z0 + z1) * 0.5
	var steel := Geo.batch()
	var deck := Geo.batch()
	var walk := Geo.batch()
	var under := Geo.batch()
	var rail := Geo.batch()
	# Fahrbahnplatte und Gehwege (Gehweg 0.18 hoch: unter agent_max_climb)
	deck.add(Vector3(0, -DECK_T * 0.5, zc), Vector3(10.0, DECK_T, L))
	for s: float in [-1.0, 1.0]:
		walk.add(Vector3(s * 5.65, -DECK_T * 0.5 + 0.09, zc), Vector3(1.3, DECK_T + 0.18, L))
		walk.add(Vector3(s * 5.02, 0.1, zc), Vector3(0.12, 0.2, L))   # Bordstein
	# Laengs- und Quertraeger unter der Platte
	for x: float in [-4.5, -1.5, 1.5, 4.5]:
		under.add(Vector3(x, -DECK_T - 0.5, zc), Vector3(0.35, 1.0, L))
		under.add(Vector3(x, -DECK_T - 1.0, zc), Vector3(0.6, 0.08, L))
	var nq := int(L / 4.5)
	for i in nq + 1:
		var z := z0 - i * L / nq
		under.add(Vector3(0, -DECK_T - 0.7, z), Vector3(HALF_W * 2.0, 1.4, 0.4))
	# Fachwerktraeger
	var za := z0 - 4.5
	var zb := z1 + 4.5
	var panels := 8
	for s: float in [-1.0, 1.0]:
		var x := s * HALF_W
		var bot := -0.3
		var top := TRUSS_H
		# Untergurt, Obergurt, Endstreben
		steel.add(Vector3(x, bot, zc), Vector3(0.55, 0.8, L + 0.4))
		steel.add(Vector3(x, top, (za + zb) * 0.5), Vector3(0.6, 0.7, za - zb + 0.6))
		RP.beam(steel, Vector3(x, bot, z0), Vector3(x, top, za), 0.6, 0.7)
		RP.beam(steel, Vector3(x, bot, z1), Vector3(x, top, zb), 0.6, 0.7)
		# Pfosten + Diagonalen (Warren mit Pfosten)
		var step := (za - zb) / panels
		for i in panels + 1:
			var z := za - i * step
			steel.add(Vector3(x, (bot + top) * 0.5, z), Vector3(0.36, top - bot, 0.36))
			# Knotenbleche
			steel.add(Vector3(x + s * 0.05, top - 0.3, z), Vector3(0.62, 1.2, 1.4))
			steel.add(Vector3(x + s * 0.05, bot + 0.3, z), Vector3(0.62, 1.0, 1.4))
			if i < panels:
				var zn := z - step
				if i % 2 == 0:
					RP.beam(steel, Vector3(x, top, z), Vector3(x, bot, zn), 0.4, 0.4)
				else:
					RP.beam(steel, Vector3(x, bot, z), Vector3(x, top, zn), 0.4, 0.4)
		# Erstes/letztes Feld: Diagonale vom Auflager
		RP.beam(steel, Vector3(x, bot, z0), Vector3(x, bot + 0.1, za), 0.3, 0.3)
		# Gelaender am Gehweg (innen vor dem Fachwerk)
		var rx := s * 6.2
		rail.add(Vector3(rx, 1.05, zc), Vector3(0.07, 0.07, L))
		rail.add(Vector3(rx, 0.6, zc), Vector3(0.05, 0.05, L))
		var np := int(L / 2.0)
		for i in np + 1:
			rail.add(Vector3(rx, 0.55, z0 - i * L / np), Vector3(0.06, 1.0, 0.06))
	# Oberer Windverband: Quertraeger + Kreuze, Portalrahmen an den Enden
	var step2 := (za - zb) / panels
	for i in panels + 1:
		var z := za - i * step2
		steel.add(Vector3(0, TRUSS_H + 0.1, z), Vector3(HALF_W * 2.0, 0.45, 0.35))
		if i < panels:
			var zn := z - step2
			RP.beam(steel, Vector3(-HALF_W, TRUSS_H + 0.1, z), Vector3(HALF_W, TRUSS_H + 0.1, zn), 0.18, 0.18)
			RP.beam(steel, Vector3(HALF_W, TRUSS_H + 0.1, z), Vector3(-HALF_W, TRUSS_H + 0.1, zn), 0.18, 0.18)
	for z: float in [za, zb]:
		steel.add(Vector3(0, TRUSS_H - 1.1, z), Vector3(HALF_W * 2.0, 0.9, 0.4))
		for s: float in [-1.0, 1.0]:
			RP.beam(steel, Vector3(s * HALF_W, TRUSS_H - 2.6, z), Vector3(s * (HALF_W - 2.0), TRUSS_H - 0.7, z), 0.3, 0.3)
	RP.add_batch(parent, steel, RP.steel())
	RP.add_batch(parent, deck, RP.deck())
	RP.add_batch(parent, walk, RP.concrete(Color(0.6, 0.6, 0.6)))
	RP.add_batch(parent, under, RP.steel(Color(0.4, 0.44, 0.4)), false)
	RP.add_batch(parent, rail, RP.steel(Color(0.35, 0.38, 0.35)))
	# Schaeden: Granattrichter-Flicken / Brandflecken auf der Fahrbahn
	if damaged:
		var patch := Geo.batch()
		for i in 5:
			var p := Vector3(rng.randf_range(-3.5, 3.5), 0.012, zc + rng.randf_range(-L * 0.4, L * 0.4))
			patch.add(p, Vector3(rng.randf_range(1.2, 2.6), 0.02, rng.randf_range(1.2, 2.6)), Basis(Vector3.UP, rng.randf() * TAU))
		var mi := RP.add_batch(parent, patch, RP.flat_wet(Color(0.03, 0.028, 0.026), 0.25), false)
		if mi != null:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Kollision: Platte (inkl. Gehweg) und seitliche Sperren (Spieler kann nicht vom Deck fallen)
	Geo.add_box_shape(body, Vector3(0, -DECK_T * 0.5, zc), Vector3(HALF_W * 2.0, DECK_T, L))
	for s: float in [-1.0, 1.0]:
		Geo.add_box_shape(body, Vector3(s * 5.65, -DECK_T * 0.5 + 0.09, zc), Vector3(1.3, DECK_T + 0.18, L))
		Geo.add_box_shape(body, Vector3(s * 6.35, 2.0, zc), Vector3(0.3, 4.0, L))

## Strompfeiler (laeuft in Fliessrichtung x), Oberkante unter der Platte.
static func pier(parent: Node3D, z: float) -> void:
	var b := Geo.static_body(Vector3(0, 0, z))
	var m := RP.concrete(Color(0.62, 0.62, 0.6))
	var bb := Geo.batch()
	var top := -DECK_T - 1.4
	var h := top - BED_Y
	bb.add(Vector3(0, BED_Y + h * 0.5, 0), Vector3(11.0, h, 3.2))
	# Pfeilerkopf (Auflagerbank)
	bb.add(Vector3(0, top + 0.35, 0), Vector3(15.0, 0.7, 4.2))
	# Lager
	for s: float in [-1.0, 1.0]:
		bb.add(Vector3(s * HALF_W, top + 0.85, 0.9), Vector3(1.0, 0.3, 0.8))
		bb.add(Vector3(s * HALF_W, top + 0.85, -0.9), Vector3(1.0, 0.3, 0.8))
	RP.add_batch(b, bb, m)
	# Abgerundete Vorkoepfe (Eisbrecher) an beiden Enden
	for s: float in [-1.0, 1.0]:
		b.add_child(Geo.cylinder_node(1.6, h, m, Vector3(s * 5.5, BED_Y + h * 0.5, 0), Vector3.ZERO, 20))
	# Algen-/Schmutzband an der Wasserlinie
	var band := Geo.batch()
	band.add(Vector3(0, WATER_Y + 0.4, 0), Vector3(11.06, 1.4, 3.26))
	RP.add_batch(b, band, RP.wet("", Color(0.07, 0.08, 0.05), 1.0, {"base_roughness": 0.3, "wetness": 1.0}), false)
	for s: float in [-1.0, 1.0]:
		b.add_child(Geo.cylinder_node(1.63, 1.4, RP.wet("", Color(0.07, 0.08, 0.05), 1.0, {"base_roughness": 0.3, "wetness": 1.0}), Vector3(s * 5.5, WATER_Y + 0.4, 0), Vector3.ZERO, 20))
	Geo.add_box_shape(b, Vector3(0, BED_Y + h * 0.5, 0), Vector3(14.2, h, 3.2))
	parent.add_child(b)

## Widerlager: Betonwand von der Ufer-Boeschung bis zur Platte. dir = +1 (Westufer, Wand zeigt nach -z) / -1.
static func abutment(parent: Node3D, z: float, dir: float) -> void:
	var b := Geo.static_body(Vector3(0, 0, z))
	var m := RP.concrete(Color(0.58, 0.58, 0.56))
	var bb := Geo.batch()
	bb.add(Vector3(0, (BED_Y - DECK_T) * 0.5, dir * 2.0), Vector3(16.0, -BED_Y - DECK_T, 4.0))
	# Fluegelmauern
	for s: float in [-1.0, 1.0]:
		bb.add(Vector3(s * 8.6, (BED_Y + 0.6) * 0.5, dir * 6.0), Vector3(1.2, -BED_Y + 0.6, 12.0))
		bb.add(Vector3(s * 8.6, 0.75, dir * 6.0), Vector3(1.4, 0.3, 12.2))
	RP.add_batch(b, bb, m)
	Geo.add_box_shape(b, Vector3(0, (BED_Y - DECK_T) * 0.5, dir * 2.0), Vector3(16.0, -BED_Y - DECK_T, 4.0))
	for s: float in [-1.0, 1.0]:
		Geo.add_box_shape(b, Vector3(s * 8.6, (BED_Y + 0.6) * 0.5, dir * 6.0), Vector3(1.2, -BED_Y + 0.6, 12.0))
	parent.add_child(b)
