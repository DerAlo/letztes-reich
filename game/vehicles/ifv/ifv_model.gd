extends RefCounted
## Prozedurales Modell des Schuetzenpanzers "Rabe" (Puma-aehnlich, NATO-Oliv).
## Vorne = -Z, Ursprung = Bodenmitte. build() liefert die beweglichen Teile:
## hull, turret (Gierachse), mantlet (Hoehenrichtung Kanone), cam_pivot (Optik), muzzle, coax_muzzle,
## flash, coax_flash, smoke_tubes (Array[Marker3D]), wheels_l/wheels_r, antenna.

const VF := preload("res://game/vehicles/vehicle_fx.gd")
const Livery := preload("res://game/vehicles/models/livery.gd")

const TURRET_POS := Vector3(0.0, 1.82, -0.35)
const MANTLET_POS := Vector3(-0.32, 0.52, -1.18)
const CAM_POS := Vector3(0.52, 1.22, -0.72)

static func build(root: Node3D) -> Dictionary:
	var paint: Material = Livery.paint("tank", "eu")
	var dark := VF.mat("ifv_dark", Color(0.055, 0.055, 0.05), 0.85, 0.25)
	var rubber := VF.mat("ifv_rubber", Color(0.03, 0.03, 0.03), 0.95, 0.0)
	var steel := VF.mat("ifv_steel", Color(0.2, 0.2, 0.19), 0.45, 0.8)
	var glass := VF.glass_mat(Color(0.15, 0.3, 0.28, 0.7))
	var parts: Dictionary = {}

	var hull := Node3D.new()
	hull.name = "Hull"
	root.add_child(hull)
	parts["hull"] = hull
	# Wanne
	VF.mesh_node(hull, VF.box(Vector3(3.0, 1.0, 6.7)), paint, Vector3(0, 1.0, 0.1))
	VF.mesh_node(hull, VF.box(Vector3(3.36, 0.36, 6.3)), paint, Vector3(0, 1.62, 0.25))
	# Bugplatte (stark geneigt) und Heckklappe
	VF.mesh_node(hull, VF.box(Vector3(3.2, 0.14, 1.7)), paint, Vector3(0, 1.36, -3.45), Vector3(-24, 0, 0))
	VF.mesh_node(hull, VF.box(Vector3(3.0, 0.6, 0.14)), paint, Vector3(0, 0.82, -3.3), Vector3(30, 0, 0))
	VF.mesh_node(hull, VF.box(Vector3(1.4, 1.05, 0.12)), paint, Vector3(0, 1.15, 3.45))
	VF.mesh_node(hull, VF.box(Vector3(1.2, 0.08, 0.6)), steel, Vector3(0, 0.62, 3.6))
	# Seitenschuerzen (Zusatzpanzerung, segmentiert)
	for sx: float in [-1.0, 1.0]:
		for i in 5:
			var z := -2.55 + i * 1.3
			VF.mesh_node(hull, VF.box(Vector3(0.14, 0.78, 1.26)), paint, Vector3(sx * 1.66, 1.02, z))
		# Ketten + Laufrollen (unten sichtbar)
		VF.mesh_node(hull, VF.box(Vector3(0.56, 0.12, 6.4)), rubber, Vector3(sx * 1.32, 0.06, 0.05))
		VF.mesh_node(hull, VF.box(Vector3(0.56, 0.12, 5.6)), rubber, Vector3(sx * 1.32, 0.86, 0.05))
		var wheels: Array[Node3D] = []
		for i in 6:
			var w := Node3D.new()
			w.position = Vector3(sx * 1.32, 0.38, -2.5 + i * 1.0)
			hull.add_child(w)
			VF.mesh_node(w, VF.cyl(0.34, 0.34, 0.5, 14), dark, Vector3.ZERO, Vector3(0, 0, 90))
			VF.mesh_node(w, VF.cyl(0.14, 0.14, 0.54, 8), steel, Vector3.ZERO, Vector3(0, 0, 90))
			wheels.append(w)
		parts["wheels_l" if sx < 0.0 else "wheels_r"] = wheels
		# Leitrad / Triebrad
		VF.mesh_node(hull, VF.cyl(0.3, 0.3, 0.5, 12), dark, Vector3(sx * 1.32, 0.6, -3.15), Vector3(0, 0, 90))
		VF.mesh_node(hull, VF.cyl(0.3, 0.3, 0.5, 12), dark, Vector3(sx * 1.32, 0.6, 3.2), Vector3(0, 0, 90))
	# Fahrerluke, Winkelspiegel, Scheinwerfer, Werkzeug
	VF.mesh_node(hull, VF.cyl(0.36, 0.38, 0.1, 16), paint, Vector3(-0.85, 1.85, -2.35))
	for i in 3:
		VF.mesh_node(hull, VF.box(Vector3(0.16, 0.1, 0.08)), glass, Vector3(-0.85 + (i - 1) * 0.2, 1.9, -2.72))
	for sx: float in [-1.0, 1.0]:
		VF.mesh_node(hull, VF.box(Vector3(0.24, 0.16, 0.12)), dark, Vector3(sx * 1.25, 1.62, -3.12))
		VF.mesh_node(hull, VF.box(Vector3(0.18, 0.1, 0.02)), VF.mat("ifv_lamp", Color(0.9, 0.85, 0.6), 0.3, 0.0, Color(1.0, 0.85, 0.55), 0.6), Vector3(sx * 1.25, 1.62, -3.19))
	VF.mesh_node(hull, VF.box(Vector3(0.1, 0.06, 1.6)), steel, Vector3(1.3, 1.83, 1.2))
	VF.mesh_node(hull, VF.box(Vector3(0.9, 0.35, 0.6)), dark, Vector3(1.0, 1.98, 2.6))
	VF.mesh_node(hull, VF.box(Vector3(0.9, 0.3, 0.55)), paint, Vector3(-1.0, 1.95, 2.7))

	# Turm
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = TURRET_POS
	hull.add_child(turret)
	parts["turret"] = turret
	VF.mesh_node(turret, VF.cyl(1.05, 1.1, 0.16, 24), dark, Vector3(0, 0.05, 0.1))
	VF.mesh_node(turret, VF.box(Vector3(2.3, 0.72, 2.5)), paint, Vector3(0, 0.46, 0.25))
	VF.mesh_node(turret, VF.box(Vector3(2.3, 0.14, 0.9)), paint, Vector3(0, 0.62, -1.15), Vector3(18, 0, 0))
	VF.mesh_node(turret, VF.box(Vector3(2.5, 0.5, 0.9)), paint, Vector3(0, 0.5, 1.6))
	# Staukorb hinten
	VF.mesh_node(turret, VF.box(Vector3(2.2, 0.06, 0.7)), steel, Vector3(0, 0.3, 2.3))
	VF.mesh_node(turret, VF.box(Vector3(1.6, 0.3, 0.5)), VF.mat("ifv_canvas", Color(0.24, 0.22, 0.16), 0.95, 0.0), Vector3(0.2, 0.48, 2.3))
	# Nebelwurfbecher (2 x 3, schraeg nach vorn/oben)
	var tubes: Array[Marker3D] = []
	for sx: float in [-1.0, 1.0]:
		for i in 3:
			var tp := Vector3(sx * (1.22 + i * 0.02), 0.62 + i * 0.12, -0.55 + i * 0.05)
			VF.mesh_node(turret, VF.cyl(0.055, 0.055, 0.32, 8), dark, tp, Vector3(-60, 0, sx * -25.0))
			var mk := Marker3D.new()
			mk.position = tp + Vector3(sx * 0.1, 0.12, -0.1)
			turret.add_child(mk)
			tubes.append(mk)
	parts["smoke_tubes"] = tubes
	# Optik-Kopf (Richtschuetze) und Kommandantenperiskop
	VF.mesh_node(turret, VF.box(Vector3(0.42, 0.34, 0.46)), paint, Vector3(CAM_POS.x, 0.98, CAM_POS.z + 0.18))
	VF.mesh_node(turret, VF.box(Vector3(0.34, 0.22, 0.02)), glass, Vector3(CAM_POS.x, 1.0, CAM_POS.z - 0.06))
	VF.mesh_node(turret, VF.cyl(0.18, 0.2, 0.42, 14), paint, Vector3(-0.7, 1.02, 0.7))
	VF.mesh_node(turret, VF.box(Vector3(0.26, 0.16, 0.02)), glass, Vector3(-0.7, 1.12, 0.55))
	# Antennen
	var ant := Node3D.new()
	ant.position = Vector3(0.95, 0.85, 1.75)
	turret.add_child(ant)
	VF.mesh_node(ant, VF.cyl(0.012, 0.02, 2.4, 5), dark, Vector3(0, 1.2, 0))
	parts["antenna"] = ant
	VF.mesh_node(turret, VF.cyl(0.01, 0.018, 1.6, 5), dark, Vector3(-0.95, 1.65, 1.8))

	# Waffenblende mit 30-mm-Kanone und Koax-MG
	var mantlet := Node3D.new()
	mantlet.name = "Mantlet"
	mantlet.position = MANTLET_POS
	turret.add_child(mantlet)
	parts["mantlet"] = mantlet
	VF.mesh_node(mantlet, VF.box(Vector3(0.62, 0.46, 0.7)), paint, Vector3(0, 0, -0.05))
	var barrel := Node3D.new()
	barrel.name = "Barrel"
	mantlet.add_child(barrel)
	parts["barrel"] = barrel
	VF.mesh_node(barrel, VF.cyl(0.11, 0.11, 0.9, 14), steel, Vector3(0, 0, -0.75), Vector3(90, 0, 0))
	VF.mesh_node(barrel, VF.cyl(0.062, 0.07, 2.2, 12), steel, Vector3(0, 0, -2.25), Vector3(90, 0, 0))
	VF.mesh_node(barrel, VF.cyl(0.095, 0.095, 0.34, 12), dark, Vector3(0, 0, -3.45), Vector3(90, 0, 0))
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0, 0, -3.7)
	barrel.add_child(muzzle)
	parts["muzzle"] = muzzle
	parts["flash"] = VF.make_muzzle_flash(muzzle, 0.9, 7.0, 10.0)
	VF.mesh_node(mantlet, VF.cyl(0.03, 0.03, 0.7, 8), dark, Vector3(0.3, -0.05, -0.55), Vector3(90, 0, 0))
	var coax := Marker3D.new()
	coax.position = Vector3(0.3, -0.05, -0.92)
	mantlet.add_child(coax)
	parts["coax_muzzle"] = coax
	parts["coax_flash"] = VF.make_muzzle_flash(coax, 0.35, 3.0, 5.0)

	# Optik (Kamera-Pivot, wird mit der Kanone gerichtet)
	var cp := Node3D.new()
	cp.name = "CamPivot"
	cp.position = CAM_POS
	turret.add_child(cp)
	parts["cam_pivot"] = cp
	# Abgasstutzen (Rauch) rechts hinten
	var ex := Marker3D.new()
	ex.position = Vector3(1.55, 1.5, 2.6)
	hull.add_child(ex)
	parts["exhaust"] = ex
	return parts

## Kollisionsquader [Mitte, Groesse] in Fahrzeugkoordinaten (Wanne, Turm).
static func shapes() -> Array:
	return [[Vector3(0, 1.05, 0.1), Vector3(3.4, 1.7, 7.0)], [TURRET_POS + Vector3(0, 0.45, 0.25), Vector3(2.4, 0.8, 2.7)]]
