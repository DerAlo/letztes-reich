extends RefCounted
## Prozeduraler Kampfpanzer im Stil T-72B3/T-90 (fiktiv): profilierte Wanne mit Bugplatte und Kontakt-Reaktivpanzerung,
## Gummi-Seitenschuerzen, 6 Doppel-Laufrollen, 3 Stuetzrollen, durchgehendes Kettenband, flacher Turm mit
## Keil-Reaktivpanzern, Shtora-Stoersendern, Nebelwerfern, Kommandantenkuppel mit fernbedientem MG und Staukorb.
## build(root, faction) haengt alles an root und liefert die beweglichen Knoten (Schluessel wie bisher + wheel_mat_l/r).
## Koordinaten: -Z = vorne, Ursprung = Boden-Mitte. Geometrie ueber mesh_kit.gd (1 Mesh je Baugruppe),
## Lack ueber vehicle_paint.gdshader (Triplanar-Tarnung, Rost, Schmutz), Raeder drehen im Vertex-Shader.

const VF = preload("res://game/vehicles/vehicle_fx.gd")
const MK = preload("res://game/vehicles/models/mesh_kit.gd")
const Livery = preload("res://game/vehicles/models/livery.gd")

const WHEEL_R := 0.36
const WHEEL_Y := 0.45
const WHEEL_X := 1.42
const TRACK_W := 0.62
const TRACK_T := 0.09
const WHEEL_ZS: Array[float] = [-2.45, -1.5, -0.55, 0.4, 1.35, 2.3]
const IDLER := Vector3(-3.12, 0.64, 0.3)      # (z, y, r)
const SPROCKET := Vector3(3.08, 0.68, 0.33)
const ROLLER_ZS: Array[float] = [-1.05, 0.75, 2.05]
const ROLLER_Y := 0.88
const ROLLER_R := 0.085
const TURRET_POS := Vector3(0, 1.54, 0.25)

# Seitenprofil der Wanne (z, y): Bug, Unterbug, Boden, Heck, Motordeck, Bugplatte
const HULL_PROF: Array[Vector2] = [
	Vector2(-3.45, 0.98), Vector2(-2.85, 0.36), Vector2(2.95, 0.36), Vector2(3.28, 0.62),
	Vector2(3.3, 1.42), Vector2(3.2, 1.5), Vector2(-1.95, 1.5)]
# Turm-Grundriss (x, z)
const TURRET_PLAN: Array[Vector2] = [
	Vector2(-0.5, -1.35), Vector2(0.5, -1.35), Vector2(1.25, -0.95), Vector2(1.45, -0.1), Vector2(1.38, 0.75),
	Vector2(0.95, 1.3), Vector2(-0.95, 1.3), Vector2(-1.38, 0.75), Vector2(-1.45, -0.1), Vector2(-1.25, -0.95)]

static func build(root: Node3D, faction: String = "ru") -> Dictionary:
	var paint := Livery.paint("tank", faction)
	var dark := VF.mat("tank_dark", Color(0.06, 0.062, 0.058), 0.6, 0.5)
	var glass := VF.glass_mat(Color(0.12, 0.16, 0.2, 0.75))
	var lamp := VF.mat("tank_lamp", Color(0.9, 0.85, 0.6), 0.2, 0.0, Color(1, 0.9, 0.6), 0.6)
	var lens := VF.mat("tank_shtora", Color(0.25, 0.04, 0.03), 0.15, 0.2, Color(0.8, 0.08, 0.04), 0.5)
	var wood := VF.mat("tank_log", Color(0.2, 0.14, 0.09), 0.9, 0.0)
	var out: Dictionary = {}

	var hull := Node3D.new()
	hull.name = "Hull"
	root.add_child(hull)
	out["hull"] = hull
	_build_hull(hull, paint, faction)
	# Scheinwerfer-Glaeser, Stamm (eigene Materialien, werden mit der Wanne verschmolzen)
	for sx: float in [-1.0, 1.0]:
		VF.mesh_node(hull, VF.cyl(0.075, 0.075, 0.02, 12), lamp, Vector3(sx * 1.22, 1.43, -3.16), Vector3(90, 0, 0))
	VF.mesh_node(hull, VF.cyl(0.13, 0.13, 2.4, 10), wood, Vector3(0, 1.64, 3.02), Vector3(0, 0, 90))
	VF.mesh_node(hull, VF.box(Vector3(0.36, 0.05, 0.1)), glass, Vector3(0, 1.57, -1.97), Vector3(-25, 0, 0))
	out["exhaust"] = Vector3(-1.82, 1.32, 2.4)

	# --- Laufwerk: ein Mesh je Seite, Drehung im Shader ------------------------
	var wm_l := Livery.paint("tank_wheel", faction).duplicate() as ShaderMaterial
	var wm_r := Livery.paint("tank_wheel", faction).duplicate() as ShaderMaterial
	for sx: float in [-1.0, 1.0]:
		var k := MK.new()
		k.use_custom = true
		_build_running_gear(k, sx)
		var mi := k.emit(hull, wm_l if sx < 0.0 else wm_r, "Wheels_%s" % ("L" if sx < 0.0 else "R"))
		mi.set_instance_shader_parameter("y_offset", 0.0)
	out["wheel_mat_l"] = wm_l
	out["wheel_mat_r"] = wm_r
	var no_wheels: Array[Node3D] = []
	out["wheels_l"] = no_wheels
	out["wheels_r"] = no_wheels.duplicate()

	# --- Ketten: durchgehendes Band je Seite ------------------------------------
	var track_shader := load("res://game/vehicles/shaders/track_loop.gdshader") as Shader
	var detail := load("res://assets/vehicles/textures/rusty_painted_metal/diffuse.jpg") as Texture2D
	for sx: float in [-1.0, 1.0]:
		var tm := ShaderMaterial.new()
		tm.shader = track_shader
		tm.set_shader_parameter("detail", detail)
		var res := _track_mesh(sx * WHEEL_X)
		tm.set_shader_parameter("link_len", res[1])
		var tmi := MeshInstance3D.new()
		tmi.name = "Track_%s" % ("L" if sx < 0.0 else "R")
		tmi.mesh = res[0]
		tmi.material_override = tm
		hull.add_child(tmi)
		out["track_mat_l" if sx < 0.0 else "track_mat_r"] = tm

	# --- Turm --------------------------------------------------------------------
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = TURRET_POS
	root.add_child(turret)
	out["turret"] = turret
	var tk := MK.new()
	_build_turret(tk, faction)
	var tmesh := tk.emit(turret, paint, "TurretShell")
	tmesh.set_instance_shader_parameter("y_offset", TURRET_POS.y)
	for sx: float in [-1.0, 1.0]:
		VF.mesh_node(turret, VF.box(Vector3(0.2, 0.14, 0.02)), lens, Vector3(sx * 0.62, 0.74, -1.235))
	VF.mesh_node(turret, VF.box(Vector3(0.3, 0.16, 0.02)), glass, Vector3(-0.55, 0.82, -0.76))
	_decals(turret, faction)
	var ant := VF.mesh_node(turret, VF.cyl(0.008, 0.02, 2.6, 5), dark, Vector3(-0.85, 2.0, 0.95), Vector3(-6, 0, 0))
	ant.name = "Antenna"
	out["antenna"] = ant
	VF.mesh_node(turret, VF.cyl(0.006, 0.016, 1.8, 5), dark, Vector3(0.95, 1.55, 1.1), Vector3(-4, 0, 3))

	# --- Kanone ------------------------------------------------------------------
	var mantlet := Node3D.new()
	mantlet.name = "Mantlet"
	mantlet.position = Vector3(0, 0.45, -1.3)
	turret.add_child(mantlet)
	var mk := MK.new()
	mk.cbox(Vector3(0, 0, -0.12), Vector3(0.66, 0.52, 0.44), 0.07)
	mk.color = MK.shade(MK.PAINT, 0.55)            # Segeltuch-Staubschutz
	mk.cbox(Vector3(0, 0, -0.38), Vector3(0.48, 0.42, 0.16), 0.06)
	mk.color = MK.shade(MK.METAL, 0.4)
	mk.cbox(Vector3(0.25, -0.1, -0.35), Vector3(0.08, 0.08, 0.12), 0.01)   # Koax-MG
	var mmi := mk.emit(mantlet, paint, "MantletShell")
	mmi.set_instance_shader_parameter("y_offset", TURRET_POS.y + 0.45)
	var barrel := Node3D.new()
	barrel.name = "Barrel"
	mantlet.add_child(barrel)
	var bk := MK.new()
	_build_barrel(bk)
	var bmi := bk.emit(barrel, paint, "BarrelShell")
	bmi.set_instance_shader_parameter("y_offset", TURRET_POS.y + 0.45)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -5.42)
	barrel.add_child(muzzle)
	out["mantlet"] = mantlet
	out["barrel"] = barrel
	out["muzzle"] = muzzle
	out["flash"] = VF.make_muzzle_flash(muzzle, 2.6, 30.0, 26.0)
	for c in root.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).material_override == glass:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return out

# ------------------------------------------------------------------ Wanne

static func _build_hull(hull: Node3D, paint: ShaderMaterial, faction: String) -> void:
	var k := MK.new()
	k.color = MK.PAINT
	k.prism_x(PackedVector2Array(HULL_PROF), -1.14, 1.14, 0.05)
	# Kettenbleche mit hochgezogenen Schmutzfaengern
	for sx: float in [-1.0, 1.0]:
		k.color = MK.PAINT
		k.cbox(Vector3(sx * 1.43, 1.245, -0.02), Vector3(0.64, 0.05, 6.5), 0.012)
		k.cbox(Vector3(sx * 1.43, 1.36, -3.42), Vector3(0.64, 0.04, 0.42), 0.01, Vector3(-38, 0, 0))
		k.cbox(Vector3(sx * 1.43, 1.2, 3.32), Vector3(0.64, 0.04, 0.3), 0.01, Vector3(30, 0, 0))
		# Seitenschuerzen: vorne Stahl mit Reaktivkacheln, sonst Gummi
		for i in 6:
			var z := -2.75 + i * 1.0
			var steel_panel := i < 2
			k.color = MK.PAINT if steel_panel else MK.shade(MK.RUBBER, 1.0)
			k.cbox(Vector3(sx * 1.765, 0.99, z), Vector3(0.035, 0.5, 0.97), 0.008)
			if steel_panel:
				k.color = MK.shade(MK.PAINT, 0.92)
				for j in 2:
					k.cbox(Vector3(sx * 1.8, 1.0, z - 0.24 + j * 0.48), Vector3(0.05, 0.42, 0.44), 0.012)
			k.color = MK.shade(MK.METAL, 0.5)
			k.cbox(Vector3(sx * 1.79, 1.21, z), Vector3(0.03, 0.04, 0.12), 0.005)   # Scharnier
		# Scheinwerfer mit Schutzbuegel
		k.color = MK.PAINT
		k.lathe(Vector3(sx * 1.22, 1.43, -3.0), Vector3.FORWARD, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.06), Vector2(0.1, 0.1), Vector2(0.15, 0.1), Vector2(0.15, 0.0)]), 12)
		k.cbox(Vector3(sx * 1.22, 1.29, -3.0), Vector3(0.05, 0.2, 0.05), 0.01)
		k.color = MK.shade(MK.METAL, 0.6)
		k.cbox(Vector3(sx * 0.7, 0.72, -3.2), Vector3(0.12, 0.16, 0.28), 0.02)  # Abschlepphaken
		k.cbox(Vector3(sx * 0.8, 0.62, 3.3), Vector3(0.12, 0.16, 0.2), 0.02)
	# Bugplatte: Kontakt-5-Kacheln in zwei Reihen, Spritzschutzblech
	var nose := Vector3(0, HULL_PROF[0].y, HULL_PROF[0].x)
	var gl_end := Vector3(0, HULL_PROF[6].y, HULL_PROF[6].x)
	var gdir := (gl_end - nose).normalized()
	var gn := Vector3(0, gdir.z, -gdir.y)      # Normale der Bugplatte (nach vorne oben)
	var tilt := -rad_to_deg(atan2(gdir.y, gdir.z))
	for row in 2:
		for col in 6:
			var x := -0.9 + col * 0.36
			var t := 0.42 + row * 0.6 + (0.06 if col % 2 == 1 else 0.0)
			k.color = MK.shade(MK.PAINT, 0.93 + 0.05 * float((row + col) % 2))
			var p := nose + gdir * t + gn * 0.075 + Vector3(x, 0, 0)
			k.cbox(p, Vector3(0.34, 0.12, 0.56), 0.02, Vector3(tilt, 0, 0))
	k.color = MK.PAINT
	k.cbox(gl_end - gdir * 0.12 + Vector3(0, 0.08, 0), Vector3(2.0, 0.15, 0.03), 0.01)
	# Fahrerluke
	k.lathe(Vector3(0, 1.5, -1.68), Vector3.UP, PackedVector2Array([Vector2(0, 0.0), Vector2(0, 0.3), Vector2(0.05, 0.3), Vector2(0.07, 0.27), Vector2(0.07, 0.0)]), 16)
	k.cbox(Vector3(0, 1.55, -1.95), Vector3(0.44, 0.1, 0.12), 0.02, Vector3(-25, 0, 0))
	# Motordeck: Luftgitter, Lukendeckel
	k.color = MK.shade(MK.METAL, 0.35)
	for i in 9:
		k.cbox(Vector3(0, 1.52, 1.6 + i * 0.16), Vector3(1.8, 0.03, 0.07), 0.008)
	k.color = MK.PAINT
	k.cbox(Vector3(0, 1.52, 2.25), Vector3(1.95, 0.025, 1.6), 0.01)
	k.cbox(Vector3(0, 1.53, 1.0), Vector3(1.6, 0.05, 0.6), 0.02)
	for sx: float in [-1.0, 1.0]:
		k.cbox(Vector3(sx * 0.5, 1.54, 2.95), Vector3(0.7, 0.06, 0.4), 0.02)
	# Heck: zwei Zusatzfaesser mit Sicken + Halterungen
	for sx: float in [-0.62, 0.62]:
		k.color = MK.shade(MK.PAINT, 0.88)
		var dp := PackedVector2Array([Vector2(-0.48, 0), Vector2(-0.48, 0.27), Vector2(-0.45, 0.3), Vector2(-0.18, 0.3), Vector2(-0.16, 0.315), Vector2(-0.14, 0.3), Vector2(0.14, 0.3), Vector2(0.16, 0.315), Vector2(0.18, 0.3), Vector2(0.45, 0.3), Vector2(0.48, 0.27), Vector2(0.48, 0)])
		k.lathe(Vector3(sx, 1.22, 3.62), Vector3.RIGHT, dp, 16)
		k.color = MK.shade(MK.METAL, 0.5)
		for bx: float in [-0.3, 0.3]:
			k.cbox(Vector3(sx + bx, 1.22, 3.62), Vector3(0.04, 0.64, 0.64), 0.005)
	# Seitliche Kraftstoffbehaelter (rechts) und Kisten (links) auf dem Kettenblech
	for i in 3:
		k.color = MK.shade(MK.PAINT, 0.96)
		k.cbox(Vector3(1.45, 1.47, -0.45 + i * 0.95), Vector3(0.52, 0.4, 0.86), 0.07)
		k.color = MK.shade(MK.METAL, 0.45)
		k.cbox(Vector3(1.45, 1.47, -0.45 + i * 0.95 - 0.44), Vector3(0.54, 0.42, 0.03), 0.005)
	k.color = MK.PAINT
	k.cbox(Vector3(-1.45, 1.43, -0.3), Vector3(0.52, 0.32, 1.1), 0.03)
	k.cbox(Vector3(-1.45, 1.42, 0.95), Vector3(0.52, 0.3, 0.9), 0.03)
	k.cbox(Vector3(-1.45, 1.38, -1.55), Vector3(0.5, 0.24, 0.8), 0.03)
	# Auspuff links hinten (verrusstes Gitter)
	k.color = MK.shade(MK.METAL, 0.18)
	k.cbox(Vector3(-1.72, 1.32, 2.4), Vector3(0.06, 0.22, 0.6), 0.015)
	if faction == "reich":
		# Amber-Kennstreifen auf den Schmutzfaengern
		k.color = MK.ACCENT
		for sx: float in [-1.0, 1.0]:
			k.cbox(Vector3(sx * 1.43, 1.385, -3.43), Vector3(0.6, 0.012, 0.18), 0.003, Vector3(-38, 0, 0))
	var mi := k.emit(hull, paint, "HullShell")
	mi.set_instance_shader_parameter("y_offset", 0.0)

# ------------------------------------------------------------------ Laufwerk

static func _build_running_gear(k: MK, sx: float) -> void:
	var x := sx * WHEEL_X
	# Doppel-Laufrolle: Nabe, Scheibe (lackiert), Gummibandage, Spalt fuer die Fuehrungszaehne
	var prof := PackedVector2Array([
		Vector2(-0.31, 0), Vector2(-0.31, 0.07), Vector2(-0.29, 0.09), Vector2(-0.29, 0.2), Vector2(-0.27, 0.27),
		Vector2(-0.27, 0.3), Vector2(-0.25, 0.36), Vector2(-0.05, 0.36), Vector2(-0.03, 0.3), Vector2(0.03, 0.3),
		Vector2(0.05, 0.36), Vector2(0.25, 0.36), Vector2(0.27, 0.3), Vector2(0.27, 0.27), Vector2(0.29, 0.2),
		Vector2(0.29, 0.09), Vector2(0.31, 0.07), Vector2(0.31, 0)])
	var hub := MK.shade(MK.METAL, 0.55)
	var rub := MK.RUBBER
	var pnt := MK.PAINT
	var bands: Array = [hub, pnt, pnt, pnt, pnt, rub, rub, rub, MK.shade(MK.METAL, 0.4), rub, rub, rub, pnt, pnt, pnt, pnt, hub]
	for z: float in WHEEL_ZS:
		k.wheel = Vector3(WHEEL_Y, z, WHEEL_R)
		k.color = pnt
		k.lathe(Vector3(x, WHEEL_Y, z), Vector3.RIGHT, prof, 22, true, bands)
		_wheel_holes(k, Vector3(x + sx * 0.295, WHEEL_Y, z), sx, 0.19, 8, 0.065)
	# Leitrad vorne (ohne Gummi)
	var ip := PackedVector2Array([
		Vector2(-0.27, 0), Vector2(-0.27, 0.1), Vector2(-0.25, 0.14), Vector2(-0.25, 0.26), Vector2(-0.22, 0.3),
		Vector2(-0.05, 0.3), Vector2(-0.04, 0.24), Vector2(0.04, 0.24), Vector2(0.05, 0.3), Vector2(0.22, 0.3),
		Vector2(0.25, 0.26), Vector2(0.25, 0.14), Vector2(0.27, 0.1), Vector2(0.27, 0)])
	k.wheel = Vector3(IDLER.y, IDLER.x, IDLER.z)
	k.color = MK.shade(MK.PAINT, 0.9)
	k.lathe(Vector3(x, IDLER.y, IDLER.x), Vector3.RIGHT, ip, 20, true, [hub, MK.PAINT, MK.PAINT, MK.PAINT, MK.shade(MK.METAL, 0.7), MK.shade(MK.METAL, 0.5), MK.shade(MK.METAL, 0.4), MK.shade(MK.METAL, 0.5), MK.shade(MK.METAL, 0.7), MK.PAINT, MK.PAINT, MK.PAINT, hub])
	_wheel_holes(k, Vector3(x + sx * 0.255, IDLER.y, IDLER.x), sx, 0.17, 6, 0.06)
	# Antriebsrad hinten mit zwei Zahnkraenzen
	k.wheel = Vector3(SPROCKET.y, SPROCKET.x, SPROCKET.z)
	var sp := PackedVector2Array([
		Vector2(-0.25, 0), Vector2(-0.25, 0.12), Vector2(-0.2, 0.18), Vector2(-0.2, 0.22), Vector2(-0.17, 0.27),
		Vector2(-0.07, 0.27), Vector2(-0.07, 0.18), Vector2(0.07, 0.18), Vector2(0.07, 0.27), Vector2(0.17, 0.27),
		Vector2(0.2, 0.22), Vector2(0.2, 0.18), Vector2(0.25, 0.12), Vector2(0.25, 0)])
	k.color = MK.shade(MK.PAINT, 0.85)
	k.lathe(Vector3(x, SPROCKET.y, SPROCKET.x), Vector3.RIGHT, sp, 18, true, [hub, MK.PAINT, MK.PAINT, MK.PAINT, MK.shade(MK.METAL, 0.8), MK.shade(MK.METAL, 0.5), MK.shade(MK.METAL, 0.4), MK.shade(MK.METAL, 0.5), MK.shade(MK.METAL, 0.8), MK.PAINT, MK.PAINT, MK.PAINT, hub])
	k.color = MK.shade(MK.METAL, 0.75)
	for ring: float in [-0.12, 0.12]:
		for i in 13:
			var a := TAU * float(i) / 13.0
			var p := Vector3(x + ring, SPROCKET.y + cos(a) * 0.3, SPROCKET.x + sin(a) * 0.3)
			k.cbox(p, Vector3(0.08, 0.1, 0.085), 0.015, Vector3(rad_to_deg(a), 0, 0))
	# Stuetzrollen oben
	var rp := PackedVector2Array([Vector2(-0.14, 0), Vector2(-0.14, 0.05), Vector2(-0.12, ROLLER_R), Vector2(0.12, ROLLER_R), Vector2(0.14, 0.05), Vector2(0.14, 0)])
	for z: float in ROLLER_ZS:
		k.wheel = Vector3(ROLLER_Y, z, ROLLER_R)
		k.lathe(Vector3(x, ROLLER_Y, z), Vector3.RIGHT, rp, 12, true, [hub, MK.RUBBER, MK.RUBBER, MK.RUBBER, hub])
		k.wheel = Vector3.ZERO
		k.color = MK.PAINT
		k.cbox(Vector3(sx * 1.1, ROLLER_Y, z), Vector3(0.2, 0.08, 0.1), 0.02)   # Halter
	k.wheel = Vector3.ZERO
	# Schwingarme (starr) von der Wanne zu den Laufrollen
	k.color = MK.shade(MK.PAINT, 0.7)
	for z: float in WHEEL_ZS:
		k.cbox(Vector3(sx * 1.12, WHEEL_Y + 0.08, z - 0.2), Vector3(0.12, 0.1, 0.45), 0.02, Vector3(-18, 0, 0))

static func _wheel_holes(k: MK, c: Vector3, sx: float, r: float, n: int, size: float) -> void:
	var keep := k.color
	k.color = MK.shade(MK.METAL, 0.12)
	for i in n:
		var a := TAU * float(i) / float(n) + 0.3
		k.cbox(c + Vector3(sx * 0.004, cos(a) * r, sin(a) * r), Vector3(0.02, size, size), 0.012)
	k.color = MK.shade(MK.METAL, 0.6)
	for i in 6:
		var a := TAU * float(i) / 6.0
		k.cbox(c + Vector3(sx * 0.03, cos(a) * 0.05, sin(a) * 0.05), Vector3(0.03, 0.022, 0.022), 0.005)
	k.color = keep

# ------------------------------------------------------------------ Kette

## Kettenband um alle Raeder einer Seite. Rueckgabe [ArrayMesh, Gliedlaenge (passend zur Bandlaenge)].
static func _track_mesh(x: float) -> Array:
	var tc := TRACK_T * 0.5
	var circles: Array[Vector3] = [Vector3(IDLER.x, IDLER.y, IDLER.z + tc)]
	for z: float in WHEEL_ZS:
		circles.append(Vector3(z, WHEEL_Y, WHEEL_R + tc))
	circles.append(Vector3(SPROCKET.x, SPROCKET.y, SPROCKET.z + tc))
	for i in range(ROLLER_ZS.size() - 1, -1, -1):
		circles.append(Vector3(ROLLER_ZS[i], ROLLER_Y, ROLLER_R + tc))
	var nc := circles.size()
	# Aussennormale jedes Tangentenstuecks i -> i+1 (Umlauf gegen den Uhrzeigersinn in der (z, y)-Ebene)
	var seg_n: Array[Vector2] = []
	for i in nc:
		var a := circles[i]
		var b := circles[(i + 1) % nc]
		var d := Vector2(b.x - a.x, b.y - a.y)
		var l := d.length()
		var th := acos(clampf((a.z - b.z) / l, -1.0, 1.0))
		seg_n.append(d.normalized().rotated(-th))
	var pts: Array[Vector2] = []
	var nrm: Array[Vector2] = []
	for i in nc:
		var c := circles[i]
		var n_in := seg_n[(i - 1 + nc) % nc]
		var n_out := seg_n[i]
		var a0 := n_in.angle()
		var delta := fposmod(n_out.angle() - a0 + 0.3, TAU) - 0.3
		delta = maxf(delta, 0.0)
		var steps := maxi(1, ceili(delta / 0.14))
		for s in steps + 1:
			var a := a0 + delta * float(s) / float(steps)
			var n := Vector2(cos(a), sin(a))
			pts.append(Vector2(c.x, c.y) + n * c.z)
			nrm.append(n)
	pts.append(pts[0])
	nrm.append(nrm[0])
	var dist: Array[float] = [0.0]
	for i in range(1, pts.size()):
		dist.append(dist[i - 1] + pts[i].distance_to(pts[i - 1]))
	var total: float = dist[dist.size() - 1]
	var link := total / roundf(total / 0.16)
	# Querschnitt (quer, normal) mit Kennung aussen/innen
	var hw := TRACK_W * 0.5
	var prof: Array[Vector2] = [Vector2(-hw, -tc), Vector2(-hw, tc * 0.7), Vector2(-hw + 0.025, tc), Vector2(hw - 0.025, tc), Vector2(hw, tc * 0.7), Vector2(hw, -tc)]
	var v := PackedVector3Array()
	var nn := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var tan := PackedFloat32Array()
	for i in pts.size() - 1:
		var t0 := _tdir(pts, i)
		var t1 := _tdir(pts, i + 1)
		for j in prof.size():
			var q0 := prof[j]
			var q1 := prof[(j + 1) % prof.size()]
			var e := q1 - q0
			var bn := Vector2(e.y, -e.x).normalized()    # Querschnitt-Normale (quer, normal)
			if bn.dot((q0 + q1) * 0.5) < 0.0:
				bn = -bn
			var outer := 1.0 if (bn.y > 0.5) else 0.0
			var quad: Array[Vector3] = []
			var qn: Array[Vector3] = []
			var quv: Array[Vector2] = []
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]:
				var ri := i + corner.x
				var q := q0 if corner.y == 0 else q1
				var p2 := pts[ri] + nrm[ri] * q.y
				quad.append(Vector3(x + q.x, p2.y, p2.x))
				var n2 := nrm[ri] * bn.y
				qn.append(Vector3(bn.x, n2.y, n2.x).normalized())
				quv.append(Vector2((q.x + hw) / TRACK_W, dist[ri]))
			var ta := [t0, t0, t1, t1]
			for tri_idx: Vector3i in [Vector3i(0, 1, 2), Vector3i(0, 2, 3)]:
				var ids: Array[int] = [tri_idx.x, tri_idx.y, tri_idx.z]
				var fnrm := (quad[ids[1]] - quad[ids[0]]).cross(quad[ids[2]] - quad[ids[0]])
				if fnrm.dot(qn[ids[0]]) > 0.0:
					ids = [tri_idx.x, tri_idx.z, tri_idx.y]
				for id in ids:
					v.append(quad[id])
					nn.append(qn[id])
					uv.append(quv[id])
					col.append(Color(outer, 0, 0, 1))
					var td: Vector2 = ta[id]
					tan.append_array([0.0, td.y, td.x, 1.0])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_TANGENT] = tan
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return [am, link]

static func _tdir(pts: Array[Vector2], i: int) -> Vector2:
	var a := pts[maxi(i - 1, 0)]
	var b := pts[mini(i + 1, pts.size() - 1)]
	var d := b - a
	return d.normalized() if d.length_squared() > 1e-10 else Vector2(1, 0)

# ------------------------------------------------------------------ Turm

static func _build_turret(k: MK, faction: String) -> void:
	var plan := PackedVector2Array(TURRET_PLAN)
	k.color = MK.PAINT
	var rings: Array[PackedVector3Array] = [
		MK.ring_y(MK.offset_poly(plan, -0.14), 0.0),
		MK.ring_y(plan, 0.12),
		MK.ring_y(MK.offset_poly(plan, -0.06), 0.44),
		MK.ring_y(MK.offset_poly(plan, -0.24), 0.62)]
	k.loft(rings, true, true)
	# Drehkranz
	k.color = MK.shade(MK.METAL, 0.3)
	k.lathe(Vector3(0, -0.06, 0.15), Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(0, 1.2), Vector2(0.08, 1.2), Vector2(0.08, 0)]), 28, false)
	# Keil-Reaktivpanzer vorne (Kontakt-5-Stil): Kasten + schraeger Deckel
	for sx: float in [-1.0, 1.0]:
		var yaw := sx * -28.0
		var nrm := Vector3(sx * 0.47, 0, -0.88)
		var base := Vector3(sx * 0.875, 0, -1.15) + nrm * 0.2
		k.color = MK.shade(MK.PAINT, 0.95)
		k.cbox(base + Vector3(0, 0.27, 0), Vector3(0.86, 0.46, 0.38), 0.035, Vector3(0, yaw, 0))
		k.cbox(base + Vector3(0, 0.53, 0.12) + nrm * -0.02, Vector3(0.84, 0.1, 0.5), 0.025, Vector3(-12, yaw, 0))
		k.color = MK.shade(MK.METAL, 0.5)
		for j in 3:
			var off := Vector3(sx * 0.88, 0, 0.47) * (-0.3 + j * 0.3)
			k.cbox(base + off + Vector3(0, 0.27, 0) + nrm * 0.19, Vector3(0.025, 0.4, 0.02), 0.004, Vector3(0, yaw, 0))
		# Dachkacheln
		k.color = MK.shade(MK.PAINT, 0.9)
		for j in 3:
			k.cbox(Vector3(sx * (0.35 + j * 0.27), 0.64, -0.82 + j * 0.13), Vector3(0.24, 0.06, 0.34), 0.012, Vector3(0, yaw, 0))
		# Shtora-Stoersender auf den Keilen
		k.color = MK.PAINT
		k.cbox(Vector3(sx * 0.62, 0.74, -1.08), Vector3(0.32, 0.24, 0.32), 0.03)
		# Nebelwerfer (6 je Seite, schraeg nach vorne/aussen)
		k.color = MK.shade(MK.PAINT, 0.8)
		var ax := Vector3(sx * 0.35, 0.7, -0.62).normalized()
		for i in 6:
			var p := Vector3(sx * (1.3 + float(i) * 0.015), 0.5, -0.72 + float(i) * 0.17)
			k.lathe(p, ax, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.055), Vector2(0.3, 0.055), Vector2(0.3, 0.035), Vector2(0.28, 0.0)]), 8)
		k.color = MK.shade(MK.METAL, 0.5)
		k.cbox(Vector3(sx * 1.31, 0.45, -0.3), Vector3(0.1, 0.08, 1.05), 0.02)
	# Richtschuetzen-Visier (Sosna-Stil) links vorne
	k.color = MK.PAINT
	k.cbox(Vector3(-0.55, 0.8, -0.55), Vector3(0.42, 0.34, 0.44), 0.04)
	k.cbox(Vector3(-0.55, 0.98, -0.55), Vector3(0.36, 0.04, 0.5), 0.015)
	# Kommandantenkuppel mit Winkelspiegeln und fernbedientem MG
	var cp := Vector3(0.55, 0.6, 0.25)
	k.lathe(cp, Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.44), Vector2(0.2, 0.42), Vector2(0.24, 0.38), Vector2(0.27, 0.36), Vector2(0.3, 0.0)]), 18)
	k.color = MK.shade(MK.METAL, 0.25)
	for i in 6:
		var a := TAU * float(i) / 6.0 + 0.4
		k.cbox(cp + Vector3(cos(a) * 0.4, 0.13, sin(a) * 0.4), Vector3(0.1, 0.07, 0.07), 0.01, Vector3(0, -rad_to_deg(a), 0))
	k.color = MK.PAINT
	k.cbox(cp + Vector3(0, 0.37, -0.05), Vector3(0.24, 0.12, 0.3), 0.03)
	k.color = MK.shade(MK.METAL, 0.45)
	k.cbox(cp + Vector3(0, 0.5, -0.12), Vector3(0.14, 0.14, 0.62), 0.02)
	k.cyl(cp + Vector3(0, 0.52, -0.42), cp + Vector3(0, 0.52, -1.35), 0.026, 8)
	k.cyl(cp + Vector3(0, 0.52, -1.25), cp + Vector3(0, 0.52, -1.38), 0.04, 8)
	k.color = MK.shade(MK.PAINT, 0.85)
	k.cbox(cp + Vector3(0.14, 0.46, -0.05), Vector3(0.14, 0.18, 0.26), 0.02)   # Munitionskasten
	# Ladeschuetzenluke
	k.color = MK.PAINT
	k.lathe(Vector3(-0.45, 0.6, 0.45), Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.32), Vector2(0.06, 0.31), Vector2(0.08, 0.27), Vector2(0.08, 0.0)]), 16)
	# Windsensor-Mast
	k.color = MK.shade(MK.METAL, 0.5)
	k.cyl(Vector3(-0.15, 0.6, 1.0), Vector3(-0.15, 1.05, 1.0), 0.02, 6)
	k.cbox(Vector3(-0.15, 1.08, 1.0), Vector3(0.06, 0.06, 0.12), 0.01)
	# Staukorb hinten mit Spanngurten, Schnorchel
	k.color = MK.shade(MK.PAINT, 0.92)
	k.cbox(Vector3(0, 0.36, 1.55), Vector3(2.1, 0.5, 0.55), 0.05)
	k.color = MK.shade(MK.METAL, 0.35)
	for i in 4:
		k.cbox(Vector3(-0.75 + i * 0.5, 0.36, 1.83), Vector3(0.05, 0.52, 0.02), 0.004)
	k.color = MK.PAINT
	k.cyl(Vector3(-1.0, 0.72, 1.45), Vector3(0.35, 0.72, 1.45), 0.11, 12)
	if faction == "reich":
		# Amber-Kennband rund um den Turm
		k.color = MK.ACCENT
		var band: Array[PackedVector3Array] = [MK.ring_y(MK.offset_poly(plan, -0.022), 0.3), MK.ring_y(MK.offset_poly(plan, -0.03), 0.38)]
		k.loft(band, false, false)

static func _build_barrel(k: MK) -> void:
	var paint := MK.PAINT
	var band := MK.shade(MK.PAINT, 0.7)
	var steel := MK.shade(MK.METAL, 0.9)
	var bore := MK.shade(MK.METAL, 0.05)
	var prof := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, 0.15), Vector2(0.4, 0.15), Vector2(0.43, 0.13),
		Vector2(1.0, 0.128), Vector2(1.02, 0.138), Vector2(1.07, 0.138), Vector2(1.09, 0.126),
		Vector2(1.95, 0.123), Vector2(1.97, 0.134), Vector2(2.02, 0.134), Vector2(2.04, 0.121),
		Vector2(2.9, 0.118), Vector2(2.96, 0.162), Vector2(3.56, 0.162), Vector2(3.62, 0.116),
		Vector2(4.45, 0.112), Vector2(4.47, 0.122), Vector2(4.52, 0.122), Vector2(4.54, 0.11),
		Vector2(5.0, 0.106), Vector2(5.02, 0.1), Vector2(5.36, 0.097), Vector2(5.38, 0.108),
		Vector2(5.42, 0.108), Vector2(5.42, 0.068), Vector2(5.3, 0.068), Vector2(5.3, 0.0)])
	var bands: Array = [paint, paint, paint, paint, band, band, band, paint, band, band, band, paint, paint, paint, paint, paint, band, band, band, paint, steel, steel, steel, steel, steel, bore, bore]
	k.color = paint
	k.lathe(Vector3.ZERO, Vector3.FORWARD, prof, 18, true, bands)
	# Muendungs-Referenzsensor
	k.color = steel
	k.cbox(Vector3(0, 0.13, -5.12), Vector3(0.06, 0.05, 0.1), 0.01)

# ------------------------------------------------------------------ Abziehbilder

static func _decals(turret: Node3D, faction: String) -> void:
	var idx := randi() % 4
	var nm := Livery.decal_mat(Livery.DECAL_NUMBERS, Vector4(0.5 * float(idx % 2), 0.5 * float(idx / 2), 0.5, 0.5), Color(0.9, 0.9, 0.86) if faction != "reich" else Color(1.0, 0.72, 0.3))
	var plan := TURRET_PLAN
	for sx: float in [-1.0, 1.0]:
		# Seitenflaeche hinten (zwischen Punkt 3 und 4 bzw. gespiegelt)
		var a := Vector2(sx * absf(plan[3].x), plan[3].y)
		var b := Vector2(sx * absf(plan[4].x), plan[4].y)
		var mid := (a + b) * 0.5
		var e := (b - a).normalized()
		var n := Vector3(e.y, 0, -e.x) * (1.0 if sx > 0.0 else -1.0)
		var p := Vector3(mid.x, 0.3, mid.y) + n * -0.012
		if faction == "reich":
			var em := Livery.decal_mat(Livery.EMBLEM_TEX)
			Livery.decal(turret, em, p + Vector3(0, -0.02, 0.08), n, Vector2(0.56, 0.56))
			Livery.decal(turret, nm, Vector3(0, 0.36, 1.83 + 0.005) + Vector3(sx * 0.62, 0, 0), Vector3.BACK, Vector2(0.4, 0.4))
		else:
			Livery.decal(turret, nm, p + Vector3(0, 0.0, -0.05), n, Vector2(0.5, 0.5))
