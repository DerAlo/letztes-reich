extends RefCounted
## Fliegerhorst Lindenau (Brandenburg) fuer die Gunship-Mission: Gelaende, Start-/Landebahn, Rollwege, Vorfeld,
## Hangars, Tower, Kasernen, Tanklager-Wall, Shelter, Radar-/SAM-/Flak-Stellungen, Zaun mit Wachtuermen,
## Funkbunker mit Sendemast, Strasse nach Norden mit Dorf, Wald und Feldgehoelze.
## Alles im Waermebild-Material (Temperatur in der Vertexfarbe). Kollision: Boden + Gebaeude-Boxen auf Layer 1.
## Koordinaten: Bahn laengs x (z = 0), Norden = -z.

const GSMesh := preload("res://game/gunship/gs_mesh.gd")

# Temperaturen (Nacht, ~8 Grad)
const H_CONC := 0.285      # Beton (Tageswaerme gespeichert)
const H_ASPH := 0.27
const H_PAINT := 0.235     # Markierungen (geringerer Emissionsgrad)
const H_GRAVEL := 0.205
const H_WALL := 0.27
const H_ROOF := 0.2
const H_WIN := 0.44        # beheizte Raeume hinter Fenstern
const H_VENT := 0.62
const H_LAMP := 1.05
const H_SAND := 0.24

static var _rng := RandomNumberGenerator.new()

static func build(parent: Node3D) -> Dictionary:
	_rng.seed = 1949
	var root := Node3D.new()
	root.name = "Base"
	parent.add_child(root)
	var body := StaticBody3D.new()
	body.name = "Colliders"
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	_ground(root, body)
	var m := GSMesh.new()       # Flaechen (Beton/Asphalt)
	var b := GSMesh.new()       # Gebaeude
	var d := GSMesh.new()       # Kleinkram/Lampen
	_paving(m, d)
	_hangars(b, d, body)
	_tower(b, d, body)
	_barracks(b, d, body)
	_shelters(b, body)
	_depot(b, d, body)
	_sites(b, d, body)
	_comms(b, d, body)
	_fence(b, d)
	_village(b, d, body)
	_parked(d)
	m.instance(root, "Paving")
	b.instance(root, "Buildings")
	d.instance(root, "Detail")
	_forest(root)
	return {
		"mast_top": Vector3(-185, 95, -385),
		"team_start": Vector3(-150, 0, 245),
		"hangar_door": Vector3(-155, 0, -190),
		"tower": Vector3(20, 0, -185),
		"bunker": Vector3(-200, 0, -360),
	}

static func _col(body: StaticBody3D, center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	body.add_child(cs)

static func _ground(root: Node3D, body: StaticBody3D) -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = pm
	mi.material_override = GSMesh.mat("ground")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	_col(body, Vector3(0, -1, 0), Vector3(9000, 2, 9000))

## Flache Platte knapp ueber dem Boden (keine eigene Kollision: der Boden reicht).
static func _slab(m, cx: float, cz: float, sx: float, sz: float, heat: float, yaw: float = 0.0, y: float = 0.0) -> void:
	m.box(Vector3(cx, y + 0.06, cz), Vector3(sx, 0.12, sz), heat, yaw, -1.0, 0.025, 0.0)

static func _strip(m, a: Vector3, bb: Vector3, w: float, heat: float, y: float = 0.0) -> void:
	var dv := bb - a
	dv.y = 0.0
	var c := (a + bb) * 0.5
	m.box(Vector3(c.x, y + 0.06, c.z), Vector3(w, 0.12, dv.length() + w * 0.5), heat, atan2(dv.x, dv.z), -1.0, 0.025, 0.0)

static func _paving(m, d) -> void:
	# Start-/Landebahn 09/27 mit Schultern
	_slab(m, 0, 0, 1320, 54, H_CONC - 0.02)
	_slab(m, 0, 0, 1300, 40, H_CONC, 0.0, 0.02)
	# Reifenabrieb in den Aufsetzzonen (kuehler, dunkler Gummi)
	for side: float in [-1.0, 1.0]:
		for k in 14:
			var x: float = side * (560.0 - k * 22.0 - _rng.randf_range(0, 10))
			_slab(m, x, _rng.randf_range(-6, 6), _rng.randf_range(16, 34), _rng.randf_range(2.0, 4.5), H_CONC - 0.035, 0.0, 0.05)
	# Mittellinie, Schwellen, Aufsetzzonen
	var x0 := -600.0
	while x0 < 600.0:
		_slab(d, x0, 0, 30, 0.9, H_PAINT, 0.0, 0.08)
		x0 += 50.0
	for side2: float in [-1.0, 1.0]:
		for k2 in 8:
			_slab(d, side2 * 636.0, -15.75 + k2 * 4.5, 22, 1.8, H_PAINT, 0.0, 0.08)
		for k3 in 3:
			var xx: float = side2 * (540.0 - k3 * 60.0)
			_slab(d, xx, -9, 22, 3.0, H_PAINT, 0.0, 0.08)
			_slab(d, xx, 9, 22, 3.0, H_PAINT, 0.0, 0.08)
	# Befeuerung (Randfeuer, warm)
	var lx := -640.0
	while lx <= 640.0:
		for zz: float in [-21.5, 21.5]:
			d.box(Vector3(lx, 0.35, zz), Vector3(0.7, 0.7, 0.7), H_LAMP, 0.0, -1.0, 0.0, 0.0)
		lx += 60.0
	# Anflugbefeuerung West
	for k4 in 10:
		var ax := -680.0 - k4 * 30.0
		for zz2: float in [-6.0, 0.0, 6.0]:
			d.box(Vector3(ax, 1.2, zz2), Vector3(0.8, 0.8, 0.8), H_LAMP, 0.0, -1.0, 0.0, 0.0)
		d.box(Vector3(ax, 0.6, 0), Vector3(14, 0.3, 0.4), 0.26, 0.0, -1.0, 0.0, 0.0)
	# Rollweg parallel + Verbindungen
	_slab(m, 0, -85, 1280, 22, H_CONC - 0.01)
	for cxx: float in [-450.0, -150.0, 150.0, 450.0, -620.0, 620.0]:
		_slab(m, cxx, -42, 22, 64, H_CONC - 0.01)
	var tx := -620.0
	while tx < 620.0:
		_slab(d, tx, -85, 8, 0.5, H_PAINT + 0.03, 0.0, 0.08)
		tx += 14.0
	# Vorfeld vor den Hangars, Betankungsvorfeld, Shelter-Vorfeld
	_slab(m, -105, -140, 330, 80, H_CONC + 0.005)
	_slab(m, 235, -140, 170, 64, H_CONC + 0.005)
	_slab(m, -510, -128, 230, 44, H_CONC - 0.005)
	for k5 in 4:
		_slab(m, -585.0 + k5 * 50.0, -165, 14, 34, H_CONC - 0.005)
	# Abstellpositionen (Markierungen)
	for k6 in 4:
		var px := 175.0 + k6 * 40.0
		_slab(d, px, -140, 0.6, 40, H_PAINT, 0.0, 0.08)
		_slab(d, px, -122, 10, 0.6, H_PAINT, 0.0, 0.08)
	# Ringstrasse innen am Zaun, Lagerstrassen
	_strip(m, Vector3(-690, 0, 175), Vector3(690, 0, 175), 7, H_ASPH)
	_strip(m, Vector3(-690, 0, -418), Vector3(690, 0, -418), 7, H_ASPH)
	_strip(m, Vector3(-690, 0, 175), Vector3(-690, 0, -418), 7, H_ASPH)
	_strip(m, Vector3(690, 0, 175), Vector3(690, 0, -418), 7, H_ASPH)
	_strip(m, Vector3(-150, 0, 175), Vector3(-150, 0, 30), 8, H_ASPH)          # Suedtor -> Bahnkreuzung
	_strip(m, Vector3(-150, 0, 260), Vector3(-150, 0, 175), 8, H_ASPH)         # Feldweg zum Wald
	_strip(m, Vector3(-150, 0, -100), Vector3(-150, 0, -185), 8, H_ASPH)
	_strip(m, Vector3(-240, 0, -255), Vector3(160, 0, -255), 9, H_ASPH)        # Lagerstrasse hinter den Hangars
	_strip(m, Vector3(160, 0, -255), Vector3(300, 0, -255), 9, H_ASPH)
	_strip(m, Vector3(300, 0, -255), Vector3(300, 0, -430), 9, H_ASPH)         # zum Nordtor
	_strip(m, Vector3(20, 0, -255), Vector3(20, 0, -360), 8, H_ASPH)           # Kasernen
	_strip(m, Vector3(-240, 0, -255), Vector3(-240, 0, -330), 7, H_ASPH)
	_strip(m, Vector3(-240, 0, -330), Vector3(-340, 0, -300), 6, H_ASPH)       # Radar
	_strip(m, Vector3(-240, 0, -330), Vector3(-200, 0, -360), 6, H_ASPH)       # Funkbunker
	_strip(m, Vector3(300, 0, -255), Vector3(470, 0, -255), 8, H_ASPH)         # Tanklager
	_strip(m, Vector3(470, 0, -255), Vector3(470, 0, -230), 8, H_ASPH)
	_strip(m, Vector3(255, 0, -175), Vector3(300, 0, -255), 8, H_ASPH)
	_strip(m, Vector3(560, 0, -110), Vector3(600, 0, -255), 5, H_GRAVEL)       # SAM A
	_strip(m, Vector3(-160, 0, 110), Vector3(-150, 0, 100), 5, H_GRAVEL)
	# Fahrzeugpark
	_slab(m, 130, -320, 80, 50, H_CONC - 0.01)
	# Strasse nach Norden (Fluchtweg des Konvois) und Dorf
	_strip(m, Vector3(300, 0, -430), Vector3(300, 0, -660), 8, H_ASPH)
	_strip(m, Vector3(300, 0, -660), Vector3(262, 0, -860), 8, H_ASPH)
	_strip(m, Vector3(262, 0, -860), Vector3(240, 0, -1150), 8, H_ASPH)
	_strip(m, Vector3(240, 0, -1150), Vector3(225, 0, -1700), 8, H_ASPH)
	_strip(m, Vector3(262, 0, -860), Vector3(80, 0, -900), 6, H_ASPH)          # Dorfstrasse
	_strip(m, Vector3(262, 0, -860), Vector3(470, 0, -820), 6, H_ASPH)
	_strip(m, Vector3(-690, 0, -150), Vector3(-1600, 0, -260), 7, H_ASPH)      # Kreisstrasse West

static func _hangars(b, d, body: StaticBody3D) -> void:
	for i in 3:
		var cx := -230.0 + i * 75.0
		var cz := -215.0
		var w := 60.0
		var dep := 44.0
		var hw := 13.0
		b.box(Vector3(cx, hw * 0.5, cz), Vector3(w, hw, dep), H_WALL, 0.0, H_WALL - 0.02, 0.03, 1.0)
		# Bogendach
		var basis := Basis.from_scale(Vector3(1, 0.32, 1)) * Basis(Vector3.RIGHT, PI * 0.5)
		b.cyl(Vector3(cx, hw, cz), w * 0.5, dep, H_ROOF, 20, -1.0, basis, 0.03)
		# Dachoberlichter (Waermeverlust)
		for k in 3:
			b.box(Vector3(cx - 18.0 + k * 18.0, hw + 9.4, cz), Vector3(3, 0.4, dep - 6), H_ROOF + 0.05, 0.0, -1.0, 0.02, 1.0)
		# Tore nach Sueden (+z): Hangar 2 offen -> warmes Inneres sichtbar
		if i == 1:
			b.box(Vector3(cx, 6.5, cz + dep * 0.5 + 0.05), Vector3(w - 6, 13, 0.3), 0.46, 0.0, 0.4, 0.05, 0.0)
			b.box(Vector3(cx - w * 0.5 - 6, 6.5, cz + dep * 0.5 - 1), Vector3(12, 13, 1.0), H_WALL - 0.03)
			b.box(Vector3(cx + w * 0.5 + 6, 6.5, cz + dep * 0.5 - 1), Vector3(12, 13, 1.0), H_WALL - 0.03)
			# Lichtschein auf dem Vorfeld
			d.box(Vector3(cx, 0.1, cz + dep * 0.5 + 9), Vector3(w - 10, 0.1, 18), 0.315, 0.0, -1.0, 0.02, 0.0)
		else:
			for k2 in 6:
				b.box(Vector3(cx - w * 0.5 + 5 + k2 * 10.0, 6.0, cz + dep * 0.5 + 0.3), Vector3(9.4, 12, 0.5), H_WALL - 0.035, 0.0, H_WALL - 0.01, 0.02, 1.0)
		# Anbau (Werkstatt, beheizt)
		b.box(Vector3(cx, 3.0, cz - dep * 0.5 - 5), Vector3(w * 0.7, 6, 10), H_WALL + 0.03, 0.0, -1.0, 0.03, 1.0)
		for k3 in 5:
			b.box(Vector3(cx - w * 0.3 + k3 * w * 0.15, 3.4, cz - dep * 0.5 - 10.1), Vector3(2.2, 1.2, 0.2), H_WIN, 0.0, -1.0, 0.02, 0.0)
		b.box(Vector3(cx + 10, 7.5, cz - dep * 0.5 - 6), Vector3(1.4, 3, 1.4), H_VENT)
		_col(body, Vector3(cx, hw * 0.5 + 2.0, cz), Vector3(w, hw + 4.0, dep))

static func _tower(b, d, body: StaticBody3D) -> void:
	var c := Vector3(20, 0, -200)
	b.box(c + Vector3(-10, 4.5, 0), Vector3(30, 9, 14), H_WALL + 0.01, 0.0, -1.0, 0.03, 1.0)
	for k in 6:
		for fl in 2:
			b.box(c + Vector3(-23 + k * 5.0, 2.6 + fl * 3.6, 7.1), Vector3(2.4, 1.4, 0.2), H_WIN, 0.0, -1.0, 0.02, 0.0)
	b.box(c + Vector3(-10, 9.2, 0), Vector3(30, 0.4, 14), H_ROOF)
	b.box(c + Vector3(-18, 10.2, -2), Vector3(3, 2, 3), H_VENT)
	b.box(c + Vector3(8, 12, 0), Vector3(7, 24, 7), H_WALL, 0.0, H_WALL - 0.02, 0.03, 1.0)
	# Kanzel: rundum Glas, Inneres beleuchtet/geheizt
	b.box(c + Vector3(8, 25.5, 0), Vector3(11, 3.2, 11), 0.5, 0.0, 0.42, 0.04, 0.0)
	b.box(c + Vector3(8, 27.4, 0), Vector3(12.5, 0.6, 12.5), H_ROOF)
	b.cyl(c + Vector3(8, 30.5, 0), 0.15, 5.6, 0.3, 6)
	d.box(c + Vector3(8, 33.4, 0), Vector3(0.6, 0.6, 0.6), H_LAMP + 0.4)
	_col(body, c + Vector3(-10, 4.5, 0), Vector3(30, 9, 14))
	_col(body, c + Vector3(8, 14, 0), Vector3(11, 28, 11))

static func _barracks(b, d, body: StaticBody3D) -> void:
	for xx: float in [-20.0, 60.0]:
		for zz: float in [-300.0, -345.0]:
			var c := Vector3(xx, 0, zz)
			b.box(c + Vector3(0, 4.5, 0), Vector3(50, 9, 14), H_WALL + 0.01, 0.0, -1.0, 0.03, 1.0)
			b.prism(c + Vector3(0, 10.5, 0), Vector3(51, 3, 15), H_ROOF, 0.0, H_ROOF - 0.02)
			for side: float in [-1.0, 1.0]:
				for k in 10:
					for fl in 2:
						var lit := _rng.randf() < 0.55
						b.box(c + Vector3(-22.5 + k * 5.0, 2.4 + fl * 3.6, side * 7.06), Vector3(1.8, 1.4, 0.15), H_WIN if lit else H_WALL - 0.04, 0.0, -1.0, 0.02, 0.0)
			for k2 in 3:
				b.box(c + Vector3(-15.0 + k2 * 15.0, 12.2, 0), Vector3(1.2, 2.2, 1.2), H_VENT)
			_col(body, c + Vector3(0, 6, 0), Vector3(50, 12, 14))
	# Exerzierplatz und Kantine
	_slab(d, 20, -322, 120, 18, H_ASPH)
	b.box(Vector3(120, 4, -380), Vector3(30, 8, 18), H_WALL + 0.03, 0.0, -1.0, 0.03, 1.0)
	b.box(Vector3(120, 8.2, -380), Vector3(30.4, 0.4, 18.4), H_ROOF)
	b.box(Vector3(128, 10, -376), Vector3(2.4, 4, 2.4), 0.75, 0.0, 0.9)
	_col(body, Vector3(120, 4, -380), Vector3(30, 8, 18))
	# Carport Fahrzeugpark
	b.box(Vector3(130, 5.0, -338), Vector3(70, 0.5, 12), H_ROOF - 0.01)
	for k3 in 8:
		b.box(Vector3(97.0 + k3 * 9.5, 2.5, -332.5), Vector3(0.4, 5, 0.4), 0.25)

static func _shelters(b, body: StaticBody3D) -> void:
	for k in 4:
		var cx := -585.0 + k * 50.0
		var cz := -195.0
		var basis := Basis.from_scale(Vector3(1, 0.5, 1)) * Basis(Vector3.RIGHT, PI * 0.5)
		b.cyl(Vector3(cx, 0, cz), 14.0, 36.0, 0.31, 18, -1.0, basis, 0.04)
		b.box(Vector3(cx, 3.5, cz + 18.2), Vector3(22, 7, 1.2), 0.27)
		_col(body, Vector3(cx, 3.5, cz), Vector3(26, 7, 36))

static func _depot(b, d, body: StaticBody3D) -> void:
	var c := Vector3(460, 0, -290)
	# Auffangwall um die Tanks
	for s in [[Vector3(0, 0, -50), Vector3(120, 0, 4)], [Vector3(0, 0, 50), Vector3(120, 0, 4)],
			[Vector3(-60, 0, 0), Vector3(4, 0, 104)], [Vector3(60, 0, 0), Vector3(4, 0, 104)]]:
		var off: Vector3 = s[0]
		var sz: Vector3 = s[1]
		b.box(c + off + Vector3(0, 1.2, 0), Vector3(sz.x, 2.4, sz.z), 0.25, 0.0, 0.23, 0.04, 1.0)
	_slab(d, c.x, c.z, 116, 96, H_GRAVEL + 0.01)
	# Rohrleitungen, Pumpenhaus
	for zz: float in [-265.0, -315.0]:
		d.box(Vector3(460, 0.8, zz), Vector3(60, 0.6, 0.6), 0.3)
	d.box(Vector3(460, 0.8, -290), Vector3(0.6, 0.6, 50), 0.3)
	b.box(Vector3(540, 3, -240), Vector3(14, 6, 10), H_WALL + 0.04, 0.0, -1.0, 0.03, 1.0)
	b.box(Vector3(544, 6.8, -238), Vector3(1.2, 1.6, 1.2), H_VENT + 0.1)
	_col(body, Vector3(540, 3, -240), Vector3(14, 6, 10))
	# Tankfahrzeug-Stellplatz
	_slab(d, 520, -205, 40, 20, H_CONC)

static func _ring(b, c: Vector3, r: float, h: float, heat: float, n: int = 10, gap: int = -1) -> void:
	for k in n:
		if k == gap:
			continue
		var a := TAU * float(k) / float(n)
		var p := c + Vector3(cos(a) * r, h * 0.5, sin(a) * r)
		b.box(p, Vector3(2 * PI * r / float(n) * 1.05, h, 1.6), heat, -a + PI * 0.5, heat - 0.02, 0.05, 1.0)

static func _sites(b, d, body: StaticBody3D) -> void:
	# SAM-Stellungen: Splitterwall-Ring, Zufahrt
	for c: Vector3 in [Vector3(580, 0, -110), Vector3(-160, 0, 110)]:
		_slab(d, c.x, c.z, 26, 26, H_GRAVEL + 0.02)
		_ring(b, c, 12.0, 2.2, H_SAND, 14, 3)
		b.box(c + Vector3(16, 1.5, 6), Vector3(6, 3, 4), H_WALL + 0.06)       # Generator (warm)
		b.box(c + Vector3(17.5, 3.3, 6), Vector3(0.6, 0.8, 0.6), 0.9)
	# Flak-Stellungen
	for c2: Vector3 in [Vector3(-330, 0, 80), Vector3(260, 0, 90), Vector3(-330, 0, -245), Vector3(330, 0, -260)]:
		_ring(b, c2, 6.5, 1.4, H_SAND, 10, 7)
		b.box(c2 + Vector3(-9, 0.8, -3), Vector3(3, 1.6, 2), 0.25)
	# Radar-Stellung
	var rc := Vector3(-340, 0, -300)
	_slab(d, rc.x, rc.z, 34, 30, H_CONC)
	b.box(rc + Vector3(-12, 2, -9), Vector3(8, 4, 6), H_WALL + 0.06, 0.0, -1.0, 0.03, 1.0)
	b.box(rc + Vector3(-9, 4.4, -9), Vector3(1, 1, 1), H_VENT + 0.15)
	_col(body, rc + Vector3(-12, 2, -9), Vector3(8, 4, 6))
	# Windsack, Peilanlage
	b.cyl(Vector3(-60, 4, 40), 0.15, 8, 0.27, 6)
	b.box(Vector3(-58, 7.6, 40), Vector3(4, 0.8, 0.8), 0.22)
	for k in 8:
		var a := TAU * k / 8.0
		b.cyl(Vector3(380 + cos(a) * 9.0, 3, 60 + sin(a) * 9.0), 0.2, 6, 0.26, 6)

static func _comms(b, d, body: StaticBody3D) -> void:
	# Funkbunker (erdbedeckt) + Sendemast 95 m
	var c := Vector3(-200, 0, -370)
	b.box(c + Vector3(0, 2.5, 0), Vector3(24, 5, 16), 0.3, 0.0, 0.26, 0.04, 1.0)
	b.box(c + Vector3(0, 2.6, 8.2), Vector3(4, 3.2, 0.4), 0.36)          # Tor
	b.box(c + Vector3(8, 5.8, -3), Vector3(1.6, 1.6, 1.6), H_VENT + 0.12)  # Kuehlung Sender
	b.box(c + Vector3(-7, 5.6, 4), Vector3(2.4, 1.2, 2.4), H_VENT)
	_col(body, c + Vector3(0, 2.5, 0), Vector3(24, 5, 16))
	var m := Vector3(-185, 0, -385)
	_slab(d, m.x, m.z, 14, 14, H_CONC)
	var hgt := 95.0
	var seg := 10
	for i in seg:
		var y0 := hgt * float(i) / seg
		var y1 := hgt * float(i + 1) / seg
		var r0 := lerpf(2.6, 0.6, float(i) / seg)
		var r1 := lerpf(2.6, 0.6, float(i + 1) / seg)
		for k in 3:
			var a := TAU * k / 3.0
			var p0 := m + Vector3(cos(a) * r0, y0, sin(a) * r0)
			var p1 := m + Vector3(cos(a) * r1, y1, sin(a) * r1)
			var dv := p1 - p0
			var basis := Basis(Quaternion(Vector3.UP, dv.normalized()))
			b.box_b((p0 + p1) * 0.5, basis, Vector3(0.45, dv.length(), 0.45), 0.29, -1.0, 0.0)
			# Querstreben
			var a2 := TAU * (k + 1) / 3.0
			var q0 := m + Vector3(cos(a2) * r1, y1, sin(a2) * r1)
			var dv2 := q0 - p1
			var basis2 := Basis(Quaternion(Vector3.UP, dv2.normalized()))
			b.box_b((p1 + q0) * 0.5, basis2, Vector3(0.25, dv2.length(), 0.25), 0.29, -1.0, 0.0)
		# Antennen-Plattformen
		if i == 5 or i == 8:
			b.cyl(m + Vector3(0, y1, 0), r1 + 1.2, 0.5, 0.3, 8)
	b.cyl(m + Vector3(0, hgt + 4, 0), 0.25, 8, 0.3, 6)
	# Kabeltrasse Bunker -> Mast
	d.box(Vector3(-192, 0.3, -377), Vector3(1.0, 0.5, 22), 0.33, 0.6)
	# Abspannseile
	for k2 in 3:
		var a3 := TAU * k2 / 3.0 + 0.5
		var anchor := m + Vector3(cos(a3) * 50.0, 0.0, sin(a3) * 50.0)
		var top := m + Vector3(0, 70, 0)
		var dv3 := top - anchor
		b.box_b((anchor + top) * 0.5, Basis(Quaternion(Vector3.UP, dv3.normalized())), Vector3(0.12, dv3.length(), 0.12), 0.25, -1.0, 0.0)
		b.box(anchor + Vector3(0, 0.5, 0), Vector3(2, 1, 2), 0.28)
	_col(body, m + Vector3(0, hgt * 0.5, 0), Vector3(3, hgt, 3))

static func _fence(b, d) -> void:
	var x0 := -700.0
	var x1 := 700.0
	var z0 := -430.0
	var z1 := 190.0
	var segs := [[Vector3(x0, 0, z1), Vector3(x1, 0, z1)], [Vector3(x0, 0, z0), Vector3(x1, 0, z0)],
		[Vector3(x0, 0, z0), Vector3(x0, 0, z1)], [Vector3(x1, 0, z0), Vector3(x1, 0, z1)]]
	for s in segs:
		var a: Vector3 = s[0]
		var e: Vector3 = s[1]
		var dv := e - a
		var yaw := atan2(dv.x, dv.z)
		var c := (a + e) * 0.5
		# geraeumter Streifen beidseits + Zaunfeld
		d.box(Vector3(c.x, 0.04, c.z), Vector3(10, 0.08, dv.length() + 10), H_GRAVEL, yaw, -1.0, 0.03, 0.0)
		b.box(Vector3(c.x, 1.25, c.z), Vector3(0.35, 2.5, dv.length()), 0.255, yaw, 0.24, 0.0, 0.0)
		var n := int(dv.length() / 30.0)
		for k in n + 1:
			var p := a + dv * (float(k) / maxf(n, 1))
			d.box(p + Vector3(0, 1.4, 0), Vector3(0.5, 2.8, 0.5), 0.3)
	# Wachtuerme Suedzaun
	for wx: float in [-450.0, -150.0, 150.0, 450.0]:
		var c2 := Vector3(wx, 0, 192)
		for k2 in 4:
			var o := Vector3((k2 % 2) * 2.6 - 1.3, 3.5, int(k2 >= 2) * 2.6 - 1.3)
			b.box(c2 + o, Vector3(0.3, 7, 0.3), 0.27)
		b.box(c2 + Vector3(0, 8.2, 0), Vector3(3.6, 2.2, 3.6), 0.36, 0.0, 0.3, 0.03, 1.0)
		b.prism(c2 + Vector3(0, 9.9, 0), Vector3(4.2, 1.2, 4.2), H_ROOF)
		d.box(c2 + Vector3(0, 9.4, 1.9), Vector3(1.0, 0.6, 0.6), H_LAMP)     # Suchscheinwerfer
	# Tore
	for g: Vector3 in [Vector3(-150, 0, 190), Vector3(300, 0, -430)]:
		b.box(g + Vector3(8, 2, 6 if g.z > 0 else -6), Vector3(4, 4, 4), H_WALL + 0.06, 0.0, -1.0, 0.03, 1.0)
		b.box(g + Vector3(8, 4.2, 6 if g.z > 0 else -6), Vector3(4.6, 0.4, 4.6), H_ROOF)
		b.box(g + Vector3(0, 1.0, 0), Vector3(9, 0.25, 0.25), 0.3)
	# Lichtmasten Vorfeld
	for k3 in 9:
		var lp := Vector3(-260.0 + k3 * 60.0, 0, -100)
		b.cyl(lp + Vector3(0, 9, 0), 0.25, 18, 0.27, 6)
		d.box(lp + Vector3(0, 18.4, 0), Vector3(1.6, 0.6, 1.0), H_LAMP)
		d.box(lp + Vector3(0, 0.1, 0), Vector3(14, 0.05, 14), 0.305, 0.0, -1.0, 0.02, 0.0)

static func _house(b, d, c: Vector3, yaw: float, w: float, dep: float, lit: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	b.box(c + Vector3(0, 3.0, 0), Vector3(w, 6.0, dep), H_WALL + 0.03, yaw, -1.0, 0.03, 1.0)
	b.prism(c + Vector3(0, 7.6, 0), Vector3(w + 0.8, 3.2, dep + 1.0), H_ROOF + 0.03, yaw, H_ROOF)
	var nwin := int(w / 3.0)
	for k in nwin:
		if _rng.randf() < lit:
			var lp := Vector3(-w * 0.5 + 1.5 + k * 3.0, 3.4, dep * 0.5 + 0.06)
			b.box(c + basis * lp, Vector3(1.2, 1.1, 0.12), H_WIN + 0.04, yaw, -1.0, 0.02, 0.0)
	if _rng.randf() < 0.8:
		b.box(c + basis * Vector3(w * 0.3, 9.0, 0), Vector3(0.8, 2.4, 0.8), 0.7 if _rng.randf() < 0.7 else 0.32, yaw)
	# Hof, Auto
	if _rng.randf() < 0.5:
		var cp := c + basis * Vector3(w * 0.5 + 3.5, 0, dep * 0.3)
		d.box(cp + Vector3(0, 0.75, 0), Vector3(1.8, 1.5, 4.3), 0.23 if _rng.randf() < 0.7 else 0.42, yaw)

static func _village(b, d, body: StaticBody3D) -> void:
	# Lindenau-Dorf beidseits der Kreuzung (262, -860)
	var houses := 0
	for k in 18:
		var t := float(k) / 17.0
		var p := Vector3(80, 0, -900).lerp(Vector3(470, 0, -820), t)
		for side: float in [-1.0, 1.0]:
			if _rng.randf() < 0.18:
				continue
			var dirv := (Vector3(470, 0, -820) - Vector3(80, 0, -900)).normalized()
			var n := Vector3(dirv.z, 0, -dirv.x) * side
			if absf(p.x - 262.0) < 16.0:
				continue
			var c := p + n * _rng.randf_range(14.0, 18.0)
			var yaw := atan2(dirv.x, dirv.z) + PI * 0.5 + (PI if side < 0 else 0.0)
			var w := _rng.randf_range(9.0, 14.0)
			var dep := _rng.randf_range(8.0, 10.0)
			_house(b, d, c, yaw, w, dep, 0.35)
			_col(body, c + Vector3(0, 4, 0), Vector3(w, 8, dep), yaw)
			houses += 1
			# Scheune/Schuppen dahinter
			if _rng.randf() < 0.5:
				var c2 := c + n * 16.0
				b.box(c2 + Vector3(0, 3.5, 0), Vector3(16, 7, 10), H_WALL - 0.02, yaw, -1.0, 0.03, 1.0)
				b.prism(c2 + Vector3(0, 8.5, 0), Vector3(16.5, 3, 10.5), H_ROOF - 0.01, yaw, H_ROOF - 0.03)
	# Kirche
	var ch := Vector3(200, 0, -900)
	b.box(ch + Vector3(0, 6, 0), Vector3(12, 12, 26), H_WALL, 0.25, -1.0, 0.03, 1.0)
	b.prism(ch + Vector3(0, 14.5, 0), Vector3(12.5, 5, 26.5), H_ROOF, 0.25 + PI * 0.5)
	b.box(ch + Basis(Vector3.UP, 0.25) * Vector3(0, 13, 15), Vector3(6, 26, 6), H_WALL, 0.25, -1.0, 0.03, 1.0)
	b.cyl(ch + Basis(Vector3.UP, 0.25) * Vector3(0, 30, 15), 3.0, 8, H_ROOF, 8, -1.0, Basis(), 0.03, 0.2)
	_col(body, ch + Vector3(0, 7, 0), Vector3(12, 14, 26), 0.25)
	# Hoefe an der Hauptstrasse
	for k2 in 7:
		var zz := -720.0 - k2 * 60.0
		var xx := lerpf(300.0, 240.0, clampf((-zz - 660.0) / 490.0, 0.0, 1.0)) + (22.0 if k2 % 2 == 0 else -24.0)
		if absf(zz + 860.0) < 24.0:
			continue
		_house(b, d, Vector3(xx, 0, zz), PI * 0.5 + (0.0 if k2 % 2 == 0 else PI), 12.0, 9.0, 0.3)

static func _parked(d) -> void:
	# Kalte Fahrzeuge im Fahrzeugpark, Gepaeckwagen/Schlepper auf dem Vorfeld
	for k in 7:
		var p := Vector3(100.0 + k * 10.0, 0, -332)
		d.box(p + Vector3(0, 1.3, 0), Vector3(2.5, 2.6, 7.5), 0.22, 0.0, 0.2, 0.03, 1.0)
	for k2 in 5:
		var p2 := Vector3(105.0 + k2 * 12.0, 0, -305)
		d.box(p2 + Vector3(0, 0.8, 0), Vector3(2.0, 1.6, 4.2), 0.23 if k2 != 2 else 0.4, 0.0, -1.0, 0.03, 1.0)
	for k3 in 6:
		var p3 := Vector3(-260.0 + k3 * 11.0, 0, -165)
		d.box(p3 + Vector3(0, 0.6, 0), Vector3(1.8, 1.2, 3.5), 0.24, 0.3)

# ------------------------------------------------------------------ Wald

static func _forest(root: Node3D) -> void:
	var fn := FastNoiseLite.new()
	fn.seed = 77
	fn.frequency = 0.0021
	fn.fractal_octaves = 3
	var pts: Array[Vector3] = []
	var heat: Array[float] = []
	var scl: Array[float] = []
	var x := -1900.0
	while x < 1900.0:
		var z := -1750.0
		while z < 1150.0:
			var px := x + _rng.randf_range(-5.0, 5.0)
			var pz := z + _rng.randf_range(-5.0, 5.0)
			var n := fn.get_noise_2d(px, pz)
			var ok := n > 0.12
			# Waldrand suedlich des Platzes (Truppe startet dort)
			if pz > 225.0 and pz < 520.0 and px > -520.0 and px < 380.0:
				ok = n > -0.25
			# Freihalten: Platz, Anflugschneise, Strasse, Dorf
			if px > -760.0 and px < 760.0 and pz > -480.0 and pz < 228.0:
				ok = false
			if absf(pz) < 70.0 and absf(px) < 1300.0:
				ok = false
			if px > 140.0 and px < 560.0 and pz < -480.0 and pz > -1000.0:
				ok = false
			if absf(px - 250.0) < 22.0 and pz < -400.0:
				ok = false
			if absf(px + 150.0) < 7.0 and pz > 180.0 and pz < 300.0:
				ok = false
			if ok:
				pts.append(Vector3(px, 0, pz))
				heat.append(_rng.randf())
				scl.append(_rng.randf_range(1.0, 1.6))
			z += 12.0
		x += 12.0
	# Baumreihen an Feldwegen
	for k in 12:
		var a := Vector3(_rng.randf_range(-2000, 2000), 0, _rng.randf_range(-1800, 1100))
		var dirv := Vector3(cos(0.21 + (PI * 0.5 if k % 2 == 0 else 0.0)), 0, sin(0.21 + (PI * 0.5 if k % 2 == 0 else 0.0)))
		for j in 60:
			var p := a + dirv * j * 8.0
			if p.x > -760.0 and p.x < 760.0 and p.z > -480.0 and p.z < 228.0:
				continue
			if absf(p.z) < 70.0 and absf(p.x) < 1300.0:
				continue
			pts.append(p)
			heat.append(_rng.randf())
			scl.append(_rng.randf_range(0.9, 1.25))
	var tm := GSMesh.new()
	tm.cyl(Vector3(0, 2.5, 0), 0.35, 5.0, 0.3, 5)
	tm.sphere(Vector3(0, 9.0, 0), Vector3(7.5, 9.0, 7.5), 0.33, 0.29, 0.06)
	tm.sphere(Vector3(1.2, 11.5, 0.8), Vector3(4.5, 5.0, 4.5), 0.31, 0.28, 0.06)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = tm.commit()
	mm.instance_count = pts.size()
	for i in pts.size():
		var s := scl[i]
		var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.85, 1.15), s)), pts[i])
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, Color(heat[i], 0.5, 0.0, 0.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Forest"
	mmi.multimesh = mm
	mmi.material_override = GSMesh.mat("forest")
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
