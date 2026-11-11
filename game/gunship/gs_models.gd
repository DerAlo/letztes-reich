extends RefCounted
## Waermebild-Modelle der Einheiten (lokal: vorn = -Z, Ursprung am Boden). Gecacht pro Art.
## Temperaturen (Nacht): Haut ~0.95, Koerper ~0.8, Motor ~1.0+, Auspuff ~1.2, Blech ~0.4, Laufwerk ~0.65.

const GSMesh := preload("res://game/gunship/gs_mesh.gd")

static var _cache: Dictionary = {}

static func get_mesh(kind: String) -> ArrayMesh:
	if _cache.has(kind):
		return _cache[kind]
	var b := GSMesh.new()
	match kind:
		"inf_0": _person(b, 0.0, false, false)
		"inf_1": _person(b, 1.0, false, false)
		"inf_2": _person(b, -1.0, false, false)
		"inf_aim": _person(b, 0.0, true, false)
		"inf_dead": _corpse(b)
		"team_0": _person(b, 0.0, false, true)
		"team_1": _person(b, 1.0, false, true)
		"team_2": _person(b, -1.0, false, true)
		"team_aim": _person(b, 0.0, true, true)
		"truck": _truck(b, false, false)
		"team_truck": _truck(b, true, false)
		"bowser": _truck(b, false, true)
		"jeep": _jeep(b)
		"apc": _apc(b)
		"tank": _tank(b)
		"flak": _flak(b)
		"sam": _sam(b)
		"radar": _radar_base(b)
		"radar_dish": _radar_dish(b)
		"jet": _jet(b)
		"fuel": _fuel_tank(b)
		"wreck_small": _wreck(b, Vector3(2.2, 1.4, 5.0))
		"wreck_big": _wreck(b, Vector3(3.2, 2.0, 7.0))
		"wreck_jet": _wreck_jet(b)
		"wreck_tank": _wreck_fuel(b)
		"wreck_flak": _wreck(b, Vector3(2.4, 0.9, 2.6))
	var m := b.commit()
	_cache[kind] = m
	return m

# ------------------------------------------------------------------ Menschen

static func _person(b: GSMesh, stride: float, aim: bool, team: bool) -> void:
	var leg := 0.3 * stride
	# Beine (Schritt: vor/zurueck)
	b.box_b(Vector3(-0.13, 0.45, -leg * 0.5), Basis(Vector3.RIGHT, leg * 0.8), Vector3(0.17, 0.9, 0.2), 0.7, 0.78)
	b.box_b(Vector3(0.13, 0.45, leg * 0.5), Basis(Vector3.RIGHT, -leg * 0.8), Vector3(0.17, 0.9, 0.2), 0.7, 0.78)
	# Rumpf
	b.box(Vector3(0, 1.22, 0), Vector3(0.5, 0.66, 0.3), 0.8, 0.0, 0.86)
	# Kopf (Haut heiss) + Helm (kuehler)
	b.sphere(Vector3(0, 1.69, -0.02), Vector3(0.24, 0.27, 0.25), 1.0)
	b.sphere(Vector3(0, 1.78, 0.01), Vector3(0.29, 0.16, 0.3), 0.55 if not team else 0.62)
	if team:
		b.box(Vector3(0, 1.2, 0.24), Vector3(0.38, 0.5, 0.2), 0.5)   # Rucksack/Funkgeraet
	if aim:
		# Arme nach vorn, Gewehr im Anschlag
		b.box_b(Vector3(-0.2, 1.36, -0.25), Basis(Vector3.RIGHT, PI * 0.42), Vector3(0.13, 0.55, 0.13), 0.82)
		b.box_b(Vector3(0.18, 1.36, -0.22), Basis(Vector3.RIGHT, PI * 0.4), Vector3(0.13, 0.5, 0.13), 0.82)
		b.box(Vector3(0.0, 1.42, -0.55), Vector3(0.07, 0.09, 0.85), 0.42)
	else:
		b.box_b(Vector3(-0.32, 1.18, leg * 0.35), Basis(Vector3.RIGHT, -leg * 0.6), Vector3(0.12, 0.6, 0.13), 0.82)
		b.box_b(Vector3(0.32, 1.18, -leg * 0.35), Basis(Vector3.RIGHT, leg * 0.6), Vector3(0.12, 0.6, 0.13), 0.82)
		b.box_b(Vector3(0.12, 1.22, -0.22), Basis(Vector3.FORWARD, 0.9), Vector3(0.07, 0.08, 0.8), 0.4)

static func _corpse(b: GSMesh) -> void:
	# liegend, Kopf nach -Z; kuehlt ueber heat_mul aus
	b.box(Vector3(0, 0.14, 0.1), Vector3(0.5, 0.26, 0.66), 0.78)
	b.box(Vector3(-0.15, 0.1, 0.85), Vector3(0.18, 0.18, 0.85), 0.7)
	b.box(Vector3(0.18, 0.1, 0.8), Vector3(0.18, 0.18, 0.85), 0.7)
	b.sphere(Vector3(0, 0.13, -0.42), Vector3(0.25, 0.22, 0.27), 0.95)
	b.box(Vector3(0.45, 0.06, -0.1), Vector3(0.12, 0.1, 0.6), 0.8)
	b.box(Vector3(-0.6, 0.05, 0.2), Vector3(0.08, 0.08, 0.8), 0.35)

# ------------------------------------------------------------------ Fahrzeuge

static func _wheels(b: GSMesh, xs: float, zs: Array, r: float, heat: float) -> void:
	var rot := Basis(Vector3.FORWARD, PI * 0.5)
	for z in zs:
		for sx: float in [-1.0, 1.0]:
			b.cyl(Vector3(xs * sx, r, float(z)), r, 0.32, heat, 10, -1.0, rot)

static func _truck(b: GSMesh, team: bool, bowser: bool) -> void:
	# Kabine vorn (-Z), Motor darunter
	b.box(Vector3(0, 1.0, -2.75), Vector3(2.3, 1.1, 1.5), 1.05, 0.0, 0.7)       # Motorraum
	b.box(Vector3(0, 2.05, -2.6), Vector3(2.3, 1.1, 1.6), 0.42, 0.0, 0.34)       # Kabine
	b.box(Vector3(0, 2.35, -3.42), Vector3(2.1, 0.55, 0.04), 0.28)               # Scheibe (kalt)
	b.box(Vector3(0, 0.78, 0.6), Vector3(2.0, 0.3, 6.2), 0.5)                    # Rahmen
	b.box(Vector3(1.05, 1.1, -1.3), Vector3(0.18, 0.18, 1.8), 1.3)               # Auspuff
	if bowser:
		b.cyl(Vector3(0, 1.85, 1.0), 1.1, 4.4, 0.36, 14, -1.0, Basis(Vector3.RIGHT, PI * 0.5))
		b.box(Vector3(0, 1.25, 3.4), Vector3(1.6, 0.8, 0.5), 0.55)
	else:
		b.box(Vector3(0, 1.75, 1.0), Vector3(2.35, 1.6, 4.6), 0.34, 0.0, 0.3)   # Plane
		b.box(Vector3(0, 2.6, 1.0), Vector3(2.25, 0.12, 4.5), 0.3)
	if team:
		b.box(Vector3(0, 2.75, -2.4), Vector3(0.8, 0.12, 0.6), 0.45)
	_wheels(b, 1.0, [-2.7, 0.4, 2.0], 0.5, 0.66)

static func _jeep(b: GSMesh) -> void:
	b.box(Vector3(0, 0.95, -1.2), Vector3(1.9, 0.6, 1.4), 1.05, 0.0, 0.85)       # Motorhaube
	b.box(Vector3(0, 1.0, 0.6), Vector3(1.95, 0.8, 2.4), 0.45)
	b.box(Vector3(0, 1.55, 0.3), Vector3(1.8, 0.55, 1.4), 0.36)
	b.box(Vector3(0.0, 1.95, 1.0), Vector3(0.18, 0.4, 0.18), 0.5)                # MG-Lafette
	b.box(Vector3(0.0, 2.2, 0.75), Vector3(0.1, 0.12, 0.9), 0.55)
	b.sphere(Vector3(0, 2.05, 1.25), Vector3(0.3, 0.35, 0.3), 0.95)              # Schuetze
	b.box(Vector3(0.75, 0.55, 1.95), Vector3(0.15, 0.15, 0.6), 1.25)
	_wheels(b, 0.9, [-1.3, 1.3], 0.42, 0.62)

static func _apc(b: GSMesh) -> void:
	b.box(Vector3(0, 1.25, 0), Vector3(2.9, 1.5, 7.0), 0.42, 0.0, 0.46)
	b.box_b(Vector3(0, 1.45, -3.65), Basis(Vector3.RIGHT, 0.6), Vector3(2.8, 0.2, 1.4), 0.4)
	b.box(Vector3(0.55, 2.05, 2.3), Vector3(1.4, 0.15, 1.8), 1.1)                # Motordeck hinten
	b.box(Vector3(1.4, 1.55, 2.6), Vector3(0.12, 0.3, 1.0), 1.35)                # Auspuffgitter
	b.cyl(Vector3(-0.2, 2.3, -0.6), 0.6, 0.55, 0.5, 10)
	b.box(Vector3(-0.2, 2.35, -1.65), Vector3(0.12, 0.12, 1.6), 0.55)
	_wheels(b, 1.35, [-2.6, -0.9, 0.9, 2.6], 0.55, 0.64)

static func _tank(b: GSMesh) -> void:
	b.box(Vector3(0, 1.05, 0), Vector3(3.5, 1.1, 7.2), 0.43, 0.0, 0.5)
	b.box(Vector3(1.55, 0.55, 0), Vector3(0.6, 1.0, 7.4), 0.66)                  # Kette rechts (warm)
	b.box(Vector3(-1.55, 0.55, 0), Vector3(0.6, 1.0, 7.4), 0.66)
	b.box(Vector3(0, 1.66, 2.6), Vector3(2.6, 0.14, 1.9), 1.15)                  # Turbine/Motordeck
	b.box(Vector3(0, 1.4, 3.62), Vector3(2.4, 0.5, 0.1), 1.35)                   # Abgas hinten
	b.box(Vector3(0, 2.0, -0.2), Vector3(2.5, 0.75, 3.1), 0.45, 0.0, 0.4)        # Turm
	b.cyl(Vector3(0, 2.1, -3.7), 0.12, 4.4, 0.5, 8, -1.0, Basis(Vector3.RIGHT, PI * 0.5))
	b.box(Vector3(0.6, 2.5, 0.4), Vector3(0.5, 0.25, 0.6), 0.55)

static func _flak(b: GSMesh) -> void:
	b.cyl(Vector3(0, 0.25, 0), 1.6, 0.5, 0.38, 12)                               # Sandsack-Ring
	b.cyl(Vector3(0, 0.55, 0), 2.2, 0.9, 0.3, 14, 0.27)
	b.box(Vector3(0, 0.95, 0), Vector3(1.2, 0.5, 1.4), 0.46)
	b.box_b(Vector3(-0.2, 1.55, -0.9), Basis(Vector3.RIGHT, 0.8), Vector3(0.12, 0.12, 2.2), 0.62)
	b.box_b(Vector3(0.2, 1.55, -0.9), Basis(Vector3.RIGHT, 0.8), Vector3(0.12, 0.12, 2.2), 0.62)
	b.box(Vector3(0, 1.25, 0.2), Vector3(0.5, 0.5, 0.4), 0.85)                   # Richtschuetze
	b.sphere(Vector3(0, 1.6, 0.25), Vector3(0.25, 0.28, 0.25), 0.98)
	b.box(Vector3(1.4, 0.8, 1.1), Vector3(0.4, 0.6, 0.3), 0.82)                  # Ladeschuetze
	b.sphere(Vector3(1.4, 1.25, 1.1), Vector3(0.23, 0.26, 0.23), 0.95)
	b.box(Vector3(-1.5, 0.3, 1.0), Vector3(0.8, 0.5, 0.5), 0.36)                 # Munitionskisten

static func _sam(b: GSMesh) -> void:
	b.box(Vector3(0, 1.1, 0.4), Vector3(2.6, 1.0, 7.4), 0.42)
	b.box(Vector3(0, 2.0, -2.9), Vector3(2.5, 1.2, 1.6), 0.45, 0.0, 0.38)        # Kabine
	b.box(Vector3(0.7, 1.75, -1.6), Vector3(0.8, 0.4, 0.8), 1.15)                # Generator
	b.box(Vector3(1.25, 1.2, -1.4), Vector3(0.12, 0.25, 0.8), 1.35)
	var tilt := Basis(Vector3.RIGHT, 0.55)
	for x: float in [-0.55, 0.55]:
		for y: float in [0.0, 0.62]:
			b.cyl(Vector3(x, 2.4 + y, 1.3 - y * 0.3), 0.27, 4.6, 0.31, 8, -1.0, tilt * Basis(Vector3.RIGHT, PI * 0.5))
	_wheels(b, 1.2, [-2.6, -0.8, 1.2, 3.0], 0.55, 0.62)
	b.box(Vector3(3.5, 0.6, 0.5), Vector3(1.0, 1.2, 1.6), 1.0)                   # externes Aggregat

static func _radar_base(b: GSMesh) -> void:
	b.box(Vector3(0, 1.2, 0), Vector3(2.5, 1.5, 6.0), 0.43)
	b.box(Vector3(0, 2.3, 0), Vector3(1.4, 0.7, 1.4), 0.5)
	b.box(Vector3(4.0, 0.7, 1.0), Vector3(1.2, 1.4, 2.0), 1.08)                  # Generator
	b.box(Vector3(4.65, 1.2, 1.0), Vector3(0.12, 0.6, 0.6), 1.35)
	b.box(Vector3(0, 2.75, 0), Vector3(0.5, 0.6, 0.5), 0.6)
	_wheels(b, 1.2, [-2.0, 2.0], 0.5, 0.5)

static func _radar_dish(b: GSMesh) -> void:
	# sitzt auf y=3.1 der Basis; dreht sich um y
	b.box_b(Vector3(0, 1.3, 0.25), Basis(Vector3.RIGHT, -0.28), Vector3(6.0, 2.2, 0.18), 0.34, 0.3)
	b.box(Vector3(0, 0.3, 0), Vector3(0.5, 0.6, 0.5), 0.55)
	b.box(Vector3(0, 1.2, -0.7), Vector3(0.25, 0.25, 1.2), 0.5)

static func _jet(b: GSMesh) -> void:
	# einsitziger Jaeger, Laenge ~16 m, Nase -Z
	b.cyl(Vector3(0, 1.9, 0.5), 0.75, 12.5, 0.34, 10, -1.0, Basis(Vector3.RIGHT, PI * 0.5), 0.03, 0.6)
	b.cyl(Vector3(0, 1.9, -7.2), 0.55, 3.0, 0.33, 10, -1.0, Basis(Vector3.RIGHT, -PI * 0.5), 0.03, 0.05)   # Nase
	b.sphere(Vector3(0, 2.6, -4.2), Vector3(0.75, 0.6, 2.4), 0.26)              # Haube (kalt)
	# Deltafluegel
	b.box_b(Vector3(-3.1, 1.75, 2.2), Basis(Vector3.UP, -0.55), Vector3(5.2, 0.16, 3.4), 0.31)
	b.box_b(Vector3(3.1, 1.75, 2.2), Basis(Vector3.UP, 0.55), Vector3(5.2, 0.16, 3.4), 0.31)
	b.box(Vector3(0, 1.75, 2.8), Vector3(5.0, 0.18, 4.2), 0.32)
	b.box_b(Vector3(0, 3.6, 5.6), Basis(Vector3.RIGHT, -0.5), Vector3(0.18, 3.2, 2.2), 0.3)   # Seitenleitwerk
	b.cyl(Vector3(0, 1.9, 7.15), 0.62, 0.9, 0.95, 10, 1.25, Basis(Vector3.RIGHT, PI * 0.5))   # Duese (APU/Triebwerk warm)
	b.box(Vector3(0, 0.6, -5.0), Vector3(0.12, 1.2, 0.12), 0.5)
	b.box(Vector3(-1.4, 0.6, 2.0), Vector3(0.2, 1.2, 0.2), 0.55)
	b.box(Vector3(1.4, 0.6, 2.0), Vector3(0.2, 1.2, 0.2), 0.55)

static func _fuel_tank(b: GSMesh) -> void:
	# Fuellstand sichtbar: unten warmer Treibstoff, oben kuehlerer Gasraum
	b.cyl(Vector3(0, 4.0, 0), 11.0, 8.0, 0.42, 28, 0.4, Basis(), 0.02)
	b.cyl(Vector3(0, 10.0, 0), 11.0, 4.0, 0.28, 28, 0.27, Basis(), 0.02)
	b.cyl(Vector3(0, 12.6, 0), 11.0, 1.2, 0.24, 28, 0.21, Basis(), 0.02, 9.0)   # flaches Kegeldach
	b.box(Vector3(10.6, 6.0, 0), Vector3(0.6, 12.0, 0.9), 0.32)                   # Leiter
	b.box(Vector3(0, 0.6, -12.5), Vector3(3.0, 1.2, 2.0), 0.6)                    # Pumpe

static func _wreck(b: GSMesh, s: Vector3) -> void:
	b.box_b(Vector3(0, s.y * 0.4, 0), Basis(Vector3.FORWARD, 0.12), Vector3(s.x, s.y * 0.8, s.z), 1.0, 1.25, 0.12)
	b.box(Vector3(0.3, s.y * 0.85, -s.z * 0.2), Vector3(s.x * 0.6, s.y * 0.5, s.z * 0.35), 1.3, 0.0, 1.5, 0.15)
	b.box(Vector3(s.x * 0.7, 0.15, s.z * 0.3), Vector3(0.8, 0.3, 1.0), 0.9)
	b.box(Vector3(-s.x * 0.8, 0.12, -s.z * 0.35), Vector3(0.7, 0.24, 0.6), 0.85)

static func _wreck_jet(b: GSMesh) -> void:
	b.box_b(Vector3(0, 1.0, 0.5), Basis(Vector3.FORWARD, 0.25), Vector3(1.6, 1.4, 11.0), 1.1, 1.35, 0.15)
	b.box_b(Vector3(-3.0, 0.4, 2.0), Basis(Vector3.UP, -0.5), Vector3(4.5, 0.2, 3.0), 0.9, -1.0, 0.15)
	b.box_b(Vector3(2.6, 0.5, 1.6), Basis(Vector3(0.3, 1.0, 0.0).normalized(), 0.6), Vector3(3.8, 0.2, 2.6), 0.95, -1.0, 0.15)
	b.box(Vector3(0.5, 0.15, -6.5), Vector3(1.2, 0.3, 1.5), 0.85)

static func _wreck_fuel(b: GSMesh) -> void:
	b.cyl(Vector3(0, 2.5, 0), 11.0, 5.0, 1.2, 24, 1.0, Basis(), 0.18)
	b.box_b(Vector3(3.0, 5.5, 2.0), Basis(Vector3.FORWARD, 0.9), Vector3(8.0, 0.4, 6.0), 0.9, -1.0, 0.15)
	b.box_b(Vector3(-4.0, 4.8, -3.0), Basis(Vector3.RIGHT, -1.1), Vector3(6.0, 0.4, 5.0), 0.95, -1.0, 0.15)
	b.cyl(Vector3(0, 0.2, 0), 15.0, 0.4, 1.0, 24, 0.9, Basis(), 0.2)              # brennende Lache
