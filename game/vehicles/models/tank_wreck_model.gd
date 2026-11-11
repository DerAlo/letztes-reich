extends RefCounted
## Ausgebranntes Panzerwrack auf Basis des detaillierten TankModel (T-72-Stil):
## verkohlte Rost-Lackierung (Livery "wreck"/"wreck_snow"), Turm vom Drehkranz gehoben und verdreht,
## Rohr haengt, rechte Kette abgeworfen und neben dem Wrack ausgelegt, Antennen, Glas, Lampen und
## Abziehbilder weggebrannt. Nur Optik – Kollision setzt der Aufrufer (level_props.tank_wreck).
## Koordinaten: Front des Modells = -Z (wie TankModel); der Aufrufer dreht bei Bedarf.

const TankModel = preload("res://game/vehicles/models/tank_model.gd")
const VF = preload("res://game/vehicles/vehicle_fx.gd")
const Geo = preload("res://game/levels/level_geo.gd")

## Baut das Wrack unter `root`. turret_rot = Euler-Grad des Turms (Modellraum).
static func build(root: Node3D, snow: bool = false, turret_off: Vector3 = Vector3(-0.1, 0.05, 0.05), turret_rot: Vector3 = Vector3(-3.0, 24.0, 4.0)) -> void:
	var parts: Dictionary = TankModel.build(root, "wreck_snow" if snow else "wreck")
	# Muendungsfeuer samt Licht entfernen (Wrack schiesst nicht)
	var muzzle := parts.get("muzzle") as Node3D
	if muzzle != null:
		muzzle.get_parent().remove_child(muzzle)
		muzzle.free()
	# Weggebrannt: Glas, Lampen/Lichtschutz (emissiv), Abziehbilder, Antennen
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var m := mi.material_override
		var drop := false
		if m is StandardMaterial3D:
			var sm := m as StandardMaterial3D
			drop = sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled
		if mi.mesh is CylinderMesh and (mi.mesh as CylinderMesh).top_radius < 0.01:
			drop = true
		if drop:
			mi.get_parent().remove_child(mi)
			mi.free()
	# Ketten: Rest-Kette verrostet; rechte Kette abgeworfen
	for side: String in ["track_mat_l", "track_mat_r"]:
		var tm := parts.get(side) as ShaderMaterial
		if tm != null:
			tm.set_shader_parameter("steel", Vector3(0.11, 0.085, 0.07))
			tm.set_shader_parameter("rust", Vector3(0.24, 0.12, 0.06))
			tm.set_shader_parameter("dirt", Vector3(0.6, 0.62, 0.66) if snow else Vector3(0.14, 0.12, 0.1))
	var hull := parts["hull"] as Node3D
	var tr := hull.get_node_or_null("Track_R")
	if tr != null:
		hull.remove_child(tr)
		tr.free()
	_thrown_track(root, snow)
	# Wanne sackt auf der kettenlosen Seite leicht ab
	hull.position.y = -0.03
	hull.rotation_degrees.z = -1.6
	# Turm vom Drehkranz gehoben, verdreht und gekippt; Rohr haengt
	var turret := parts["turret"] as Node3D
	turret.position += turret_off
	turret.rotation_degrees = turret_rot
	var mantlet := parts["mantlet"] as Node3D
	mantlet.rotation_degrees.x = -7.5
	# Statische Standard-Materialien zusammenfassen (Lack-Shader bleiben je Teil, wenige Draw-Calls)
	VF.merge_static(hull, [])
	VF.merge_static(turret, [])

## Abgeworfene Kette: Glieder als ein Mesh, flach im Bogen vom Leitrad nach hinten ausgelegt.
static func _thrown_track(root: Node3D, snow: bool) -> void:
	var bb := Geo.batch()
	var n := 34
	var p := Vector3(2.15, 0.03, -3.4)
	var heading := deg_to_rad(2.5)
	for i in n:
		var b := Basis(Vector3.UP, heading)
		var yb := 0.03 + (0.04 if i % 9 == 4 else 0.0)
		bb.add(Vector3(p.x, yb, p.z), Vector3(0.6, 0.045, 0.14), b)
		# Steg (Grouser) und Fuehrungszahn
		bb.add(Vector3(p.x, yb + 0.035, p.z) + b * Vector3(0, 0, 0.02), Vector3(0.56, 0.03, 0.04), b)
		bb.add(Vector3(p.x, yb + 0.06, p.z) + b * Vector3(0, 0, -0.01), Vector3(0.05, 0.07, 0.08), b)
		p += b * Vector3(0, 0, 0.158)
		# Hinter dem Heck biegt die Kette nach aussen ab
		if i > 20:
			heading += deg_to_rad(6.5)
	var col := Color(0.3, 0.22, 0.17) if not snow else Color(0.34, 0.28, 0.24)
	var m := Geo.mat("rusty_metal_02", col, 0.6, 1.0, 0.0)
	var mi := Geo.mesh_node(bb.build(), m)
	mi.name = "ThrownTrack"
	root.add_child(mi)
