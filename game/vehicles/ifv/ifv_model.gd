extends RefCounted
## Modell des Schuetzenpanzers "Rabe" (Marder 1A3, NATO-Dreifarbtarnung).
## Vorne = -Z, Ursprung = Bodenmitte. build() liefert die beweglichen Teile:
## hull, turret (Gierachse), mantlet (Hoehenrichtung Kanone), barrel (Ruecklauf), cam_pivot (Optik), muzzle,
## coax_muzzle, flash, coax_flash, smoke_tubes (Array[Marker3D]), wheels_l/wheels_r, antenna, exhaust;
## nur Marder: mg_mount (MG-Lafette, Hoehenrichtung wie die Kanone), ramp (Heckklappe, Scharnier = Ursprung).
## Standard: gebackenes Sketchfab-Modell "Marder 1A3 | High-Quality model" (Scout, CC-BY 4.0), siehe
## tools/bake_rabe_marder.gd -> assets/vehicles/marder/rabe_marder.scn (Vertex-Farbe = Materialkanal).
## Fallback (Szene fehlt/defekt): prozedurales Puma-aehnliches Modell ueber mesh_kit.gd.
## Lack ueber ifv_paint.gdshader (Ableger von vehicle_paint: Triplanar-Tarnung mit Spruehkante, Kantenabrieb,
## Schlamm/Laufspuren unten, Staub oben, matte Ketten).

const VF := preload("res://game/vehicles/vehicle_fx.gd")
const MK := preload("res://game/vehicles/models/mesh_kit.gd")
const Livery := preload("res://game/vehicles/models/livery.gd")

const IFV_PAINT_SHADER := "res://game/vehicles/shaders/ifv_paint.gdshader"
const MARDER_SCENE := "res://assets/vehicles/marder/rabe_marder.scn"
const MARDER_CAM := Vector3(0.42, 2.63, -0.42)        # Richtschuetzenoptik (Fahrzeugkoordinaten)
const MARDER_EXHAUST := Vector3(1.7, 1.55, -2.0)
const MARDER_RAMP_DECAL := Vector3(0.32, 1.2, 3.42)
static var _marder_failed := false

const TURRET_POS := Vector3(0.0, 1.82, -0.35)
const MANTLET_POS := Vector3(-0.32, 0.52, -1.18)
const CAM_POS := Vector3(0.52, 1.22, -0.72)
const TRACK_X := 1.32
const WHEEL_Y := 0.38
const WHEEL_R := 0.33

# Seitenprofil (z, y): Oberwanne ueber den Ketten (Bug -> Boden -> Heck -> Dach -> Bugplatte)
const UPPER_PROF: Array[Vector2] = [
	Vector2(-3.62, 1.12), Vector2(-3.48, 0.98), Vector2(3.42, 0.98), Vector2(3.5, 1.1),
	Vector2(3.5, 1.8), Vector2(3.4, 1.88), Vector2(-1.85, 1.9)]
# Unterwanne zwischen den Ketten
const LOWER_PROF: Array[Vector2] = [
	Vector2(-3.44, 1.0), Vector2(-2.9, 0.42), Vector2(3.1, 0.42), Vector2(3.42, 0.75), Vector2(3.42, 1.0)]
# Turm-Grundriss (x, z), Rohr sitzt links
const TURRET_PLAN: Array[Vector2] = [
	Vector2(-0.8, -1.12), Vector2(0.78, -1.12), Vector2(1.18, -0.72), Vector2(1.22, 1.2),
	Vector2(1.05, 1.32), Vector2(-1.05, 1.32), Vector2(-1.22, 1.2), Vector2(-1.18, -0.72)]

## Lack: NATO-Dreifarbtarnung (Gruen/Braun/Schwarz), leicht verschmutzt, wenig Rost.
static func _paint() -> ShaderMaterial:
	var base := Livery.paint("tank", "eu")
	var m := ShaderMaterial.new()
	# eigener Ableger von vehicle_paint: Spruehkanten, Kantenabrieb, Schlamm/Laufspuren, matte Ketten
	m.shader = load(IFV_PAINT_SHADER) as Shader
	for tex: String in ["noise_tex", "rust_albedo", "rust_normal", "rust_arm"]:
		m.set_shader_parameter(tex, base.get_shader_parameter(tex))
	m.set_shader_parameter("camo_a", Color(0.14, 0.215, 0.12))    # Bronzegruen (RAL 6031)
	m.set_shader_parameter("camo_b", Color(0.036, 0.038, 0.034))  # Teerschwarz (RAL 9021)
	m.set_shader_parameter("camo_c", Color(0.17, 0.135, 0.1))     # Lederbraun (RAL 8027, entsaettigt, sonst kippt es im Abendlicht ins Orange)
	m.set_shader_parameter("camo_split", Vector2(0.36, 0.67))     # Gruen ~30 %, Rest Schwarz/Braun etwa gleich (Vorgabe 3:3:4 grob)
	m.set_shader_parameter("camo_scale", 0.36)  # Flecken ~1-1,5 m wie auf dem Marder; Rohr zeigt weiter mehrere Toene
	m.set_shader_parameter("camo_edge", 0.012)
	m.set_shader_parameter("camo_fray", 0.05)   # gesprueht: weiche, unruhige Fleckkante statt Linie
	m.set_shader_parameter("detail_scale", 1.3)  # feinere Abnutzungs-/Rostkoernung, sonst wirkt der Lack aus der Naehe glatt
	m.set_shader_parameter("rust_amount", 0.08)
	m.set_shader_parameter("chip_amount", 0.25)
	m.set_shader_parameter("edge_wear", 0.7)
	m.set_shader_parameter("deck_wear", 0.4)
	m.set_shader_parameter("dirt_amount", 0.7)
	m.set_shader_parameter("dirt_height", 1.25)
	m.set_shader_parameter("mud_height", 0.8)   # Schlammkante etwa Oberkante Laufrollen/Kettenabdeckung
	m.set_shader_parameter("streak_amount", 0.45)
	m.set_shader_parameter("dust_amount", 0.35)
	m.set_shader_parameter("paint_rough", 0.8)
	m.set_shader_parameter("track_metal", 0.1)
	m.set_shader_parameter("dirt_col", Color(0.15, 0.14, 0.118))
	m.set_shader_parameter("mud_col", Color(0.08, 0.074, 0.062))
	return m

static func build(root: Node3D) -> Dictionary:
	if _marder_available():
		var ps := load(MARDER_SCENE) as PackedScene
		var inst: Node3D = ps.instantiate() as Node3D if ps != null else null
		if inst != null and inst.has_node("Hull/Turret/Mantlet/Barrel") and inst.has_node("Hull/Turret/MgMount"):
			return _build_marder(root, inst)
		if inst != null:
			inst.free()
		_marder_failed = true
		push_warning("ifv_model: %s nicht nutzbar - prozedurales Modell" % MARDER_SCENE)
	return _build_procedural(root)

static func _marder_available() -> bool:
	return not _marder_failed and ResourceLoader.exists(MARDER_SCENE)

# ------------------------------------------------------------------ Marder 1A3 (gebacken)

## Kanalabhaengige Materialien je Oberflaeche: "paint" (vehicle_paint, Vertex-Farbe), "glass", "glass_lamp".
static func _build_marder(root: Node3D, inst: Node3D) -> Dictionary:
	var paint := _paint()
	var glass := VF.glass_mat(Color(0.1, 0.2, 0.19, 0.75))
	var lamp := VF.glass_mat(Color(0.55, 0.52, 0.42, 0.6))
	root.add_child(inst)
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var sn: String = mi.mesh.surface_get_name(i)
			if sn == "glass":
				mi.set_surface_override_material(i, glass)
			elif sn == "glass_lamp":
				mi.set_surface_override_material(i, lamp)
			else:
				mi.set_surface_override_material(i, paint)
		mi.set_instance_shader_parameter("y_offset", 0.0)
	var parts: Dictionary = {}
	var hull := inst.get_node("Hull") as Node3D
	var turret := hull.get_node("Turret") as Node3D
	var mantlet := turret.get_node("Mantlet") as Node3D
	var barrel := mantlet.get_node("Barrel") as Node3D
	var mg := turret.get_node("MgMount") as Node3D
	parts["hull"] = hull
	parts["turret"] = turret
	parts["mantlet"] = mantlet
	parts["barrel"] = barrel
	parts["mg_mount"] = mg
	parts["ramp"] = hull.get_node_or_null("RearRamp")
	var wl: Array[Node3D] = []
	var wr: Array[Node3D] = []
	for c in hull.get_children():
		if String(c.name).begins_with("Wheel_L_"):
			wl.append(c as Node3D)
		elif String(c.name).begins_with("Wheel_R_"):
			wr.append(c as Node3D)
	parts["wheels_l"] = wl
	parts["wheels_r"] = wr
	parts["antenna"] = hull.get_node_or_null("Antenna_0")
	# Muendungen (Metadaten in Fahrzeugkoordinaten)
	var mz_world: Vector3 = inst.get_meta("muzzle", Vector3(0.066, 2.575, -1.53))
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = mz_world - turret.position - mantlet.position - barrel.position
	barrel.add_child(muzzle)
	parts["muzzle"] = muzzle
	parts["flash"] = VF.make_muzzle_flash(muzzle, 0.7, 7.0, 10.0)
	var cx_world: Vector3 = inst.get_meta("coax_muzzle", Vector3(-0.8, 2.56, -0.18))
	var coax := Marker3D.new()
	coax.name = "CoaxMuzzle"
	coax.position = cx_world - turret.position - mg.position
	mg.add_child(coax)
	parts["coax_muzzle"] = coax
	parts["coax_flash"] = VF.make_muzzle_flash(coax, 0.35, 3.0, 5.0)
	# Optik des Richtschuetzen rechts neben der Waffenanlage (Kamera-Pivot, wird mit der Kanone gerichtet)
	var cp := Node3D.new()
	cp.name = "CamPivot"
	cp.position = MARDER_CAM - turret.position
	turret.add_child(cp)
	parts["cam_pivot"] = cp
	# Nebelwurfbecher: je drei links/rechts vorn am Turm
	var tubes: Array[Marker3D] = []
	for sx: float in [-1.0, 1.0]:
		for i in 3:
			var mk := Marker3D.new()
			mk.position = Vector3(sx * (0.62 + i * 0.06), 0.42 + i * 0.05, -0.55 + i * 0.08)
			turret.add_child(mk)
			tubes.append(mk)
	parts["smoke_tubes"] = tubes
	# Abgas: Auspuffgitter rechts vorn (Motorraum vorn rechts)
	var ex := Marker3D.new()
	ex.position = MARDER_EXHAUST
	hull.add_child(ex)
	parts["exhaust"] = ex
	# Taktische Nummern: Seitenschuerzen und Heckklappe
	var idx := randi() % 4
	var nm := Livery.decal_mat(Livery.DECAL_NUMBERS, Vector4(0.5 * float(idx % 2), 0.5 * float(idx / 2), 0.5, 0.5), Color(0.86, 0.86, 0.8))
	for sx: float in [-1.0, 1.0]:
		Livery.decal(hull, nm, Vector3(sx * 1.668, 1.02, 0.85), Vector3(sx, 0, 0), Vector2(0.36, 0.36))
	var ramp: Node3D = parts["ramp"]
	if ramp != null:
		Livery.decal(ramp, nm, MARDER_RAMP_DECAL - ramp.position, Vector3(0, 0.12, 1), Vector2(0.32, 0.32))
	return parts

# ------------------------------------------------------------------ Prozedural (Fallback)

static func _build_procedural(root: Node3D) -> Dictionary:
	var paint := _paint()
	var dark := VF.mat("ifv_dark", Color(0.055, 0.055, 0.05), 0.85, 0.25)
	var glass := VF.glass_mat(Color(0.15, 0.3, 0.28, 0.7))
	var lamp := VF.mat("ifv_lamp", Color(0.9, 0.85, 0.6), 0.3, 0.0, Color(1.0, 0.85, 0.55), 0.6)
	var parts: Dictionary = {}

	var hull := Node3D.new()
	hull.name = "Hull"
	root.add_child(hull)
	parts["hull"] = hull
	_build_hull(hull, paint)
	for sx: float in [-1.0, 1.0]:
		VF.mesh_node(hull, VF.box(Vector3(0.18, 0.1, 0.02)), lamp, Vector3(sx * 1.25, 1.42, -3.6))
	for i in 3:
		VF.mesh_node(hull, VF.box(Vector3(0.15, 0.07, 0.02)), glass, Vector3(-0.85 + (i - 1) * 0.19, 1.93, -2.4), Vector3(-20, 0, 0))

	# Laufwerk: Raeder als eigene Knoten (ifv.gd dreht sie), Kette starr
	for sx: float in [-1.0, 1.0]:
		var wheels: Array[Node3D] = []
		for i in 6:
			var w := Node3D.new()
			w.position = Vector3(sx * TRACK_X, WHEEL_Y, -2.5 + i * 1.0)
			hull.add_child(w)
			var wk := MK.new()
			_road_wheel(wk, sx)
			wk.emit(w, paint, "Wheel").set_instance_shader_parameter("y_offset", WHEEL_Y)
			wheels.append(w)
		parts["wheels_l" if sx < 0.0 else "wheels_r"] = wheels
	var tk := MK.new()
	_build_tracks(tk)
	tk.emit(hull, paint, "Tracks").set_instance_shader_parameter("y_offset", 0.0)

	# Turm (unbemannt, flach, Kanone links)
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = TURRET_POS
	hull.add_child(turret)
	parts["turret"] = turret
	var trk := MK.new()
	var tubes := _build_turret(trk, turret)
	trk.emit(turret, paint, "TurretShell").set_instance_shader_parameter("y_offset", TURRET_POS.y)
	parts["smoke_tubes"] = tubes
	# Optiken: Richtschuetze (ueber der Kamera) und Kommandant (Rundblick)
	VF.mesh_node(turret, VF.box(Vector3(0.34, 0.2, 0.02)), glass, Vector3(CAM_POS.x, 1.0, CAM_POS.z - 0.06))
	VF.mesh_node(turret, VF.box(Vector3(0.24, 0.14, 0.02)), glass, Vector3(-0.7, 1.1, 0.5))
	_decals(hull, turret)
	# Antennen
	var ant := Node3D.new()
	ant.position = Vector3(0.95, 0.75, 1.15)
	turret.add_child(ant)
	VF.mesh_node(ant, VF.cyl(0.012, 0.02, 2.4, 5), dark, Vector3(0, 1.2, 0))
	parts["antenna"] = ant
	VF.mesh_node(turret, VF.cyl(0.01, 0.018, 1.6, 5), dark, Vector3(-0.95, 1.55, 1.2))

	# Waffenblende mit 30-mm-Kanone und Koax-MG
	var mantlet := Node3D.new()
	mantlet.name = "Mantlet"
	mantlet.position = MANTLET_POS
	turret.add_child(mantlet)
	parts["mantlet"] = mantlet
	var mk := MK.new()
	mk.color = MK.PAINT
	mk.cbox(Vector3(0, 0, -0.02), Vector3(0.58, 0.44, 0.62), 0.07)
	mk.color = MK.shade(MK.PAINT, 0.8)
	mk.cbox(Vector3(0, 0, -0.38), Vector3(0.4, 0.34, 0.14), 0.05)
	mk.color = MK.shade(MK.METAL, 0.35)
	mk.cyl(Vector3(0.3, -0.05, -0.2), Vector3(0.3, -0.05, -0.9), 0.022, 8)
	mk.cbox(Vector3(0.3, -0.05, -0.3), Vector3(0.09, 0.09, 0.2), 0.015)
	mk.emit(mantlet, paint, "MantletShell").set_instance_shader_parameter("y_offset", TURRET_POS.y + MANTLET_POS.y)
	var barrel := Node3D.new()
	barrel.name = "Barrel"
	mantlet.add_child(barrel)
	parts["barrel"] = barrel
	var bk := MK.new()
	_build_barrel(bk)
	bk.emit(barrel, paint, "BarrelShell").set_instance_shader_parameter("y_offset", TURRET_POS.y + MANTLET_POS.y)
	var muzzle := Marker3D.new()
	muzzle.position = Vector3(0, 0, -3.3)
	barrel.add_child(muzzle)
	parts["muzzle"] = muzzle
	parts["flash"] = VF.make_muzzle_flash(muzzle, 0.9, 7.0, 10.0)
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
	for c in root.find_children("*", "MeshInstance3D", true, false):
		if (c as MeshInstance3D).material_override == glass:
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return parts

# ------------------------------------------------------------------ Wanne

static func _build_hull(hull: Node3D, paint: ShaderMaterial) -> void:
	var k := MK.new()
	k.color = MK.PAINT
	k.prism_x(PackedVector2Array(UPPER_PROF), -1.6, 1.6, 0.05)
	k.color = MK.shade(MK.PAINT, 0.85)
	k.prism_x(PackedVector2Array(LOWER_PROF), -1.02, 1.02, 0.04)
	# Bugplatte: Zusatzpanzer-Module, Ersatzkettenglieder, Abschlepphaken
	var nose := Vector3(0, UPPER_PROF[0].y, UPPER_PROF[0].x)
	var gl_end := Vector3(0, UPPER_PROF[6].y, UPPER_PROF[6].x)
	var gdir := (gl_end - nose).normalized()
	var gn := Vector3(0, gdir.z, -gdir.y)
	var tilt := -rad_to_deg(atan2(gdir.y, gdir.z))
	for col in 4:
		var x := -1.17 + col * 0.78
		k.color = MK.shade(MK.PAINT, 0.94 + 0.04 * float(col % 2))
		k.cbox(nose + gdir * 0.95 + gn * 0.05 + Vector3(x, 0, 0), Vector3(0.74, 0.08, 1.3), 0.025, Vector3(tilt, 0, 0))
		k.color = MK.shade(MK.METAL, 0.45)
		for b in 2:
			k.cbox(nose + gdir * (0.5 + b * 0.9) + gn * 0.1 + Vector3(x + 0.27, 0, 0), Vector3(0.05, 0.03, 0.05), 0.01, Vector3(tilt, 0, 0))
	k.color = MK.shade(MK.METAL, 0.3)
	for i in 4:
		k.cbox(nose + gdir * (0.35 + i * 0.2) + gn * 0.12 + Vector3(0.25, 0, 0), Vector3(0.5, 0.05, 0.16), 0.015, Vector3(tilt, 0, 0))
	for sx: float in [-1.0, 1.0]:
		k.color = MK.shade(MK.METAL, 0.55)
		k.cbox(Vector3(sx * 0.62, 0.72, -3.24), Vector3(0.12, 0.18, 0.3), 0.03)
		k.cbox(Vector3(sx * 0.62, 0.62, 3.48), Vector3(0.12, 0.18, 0.2), 0.03)
		# Scheinwerfer mit Schutzbuegel
		k.color = MK.PAINT
		k.cbox(Vector3(sx * 1.25, 1.42, -3.52), Vector3(0.3, 0.2, 0.16), 0.03)
		k.color = MK.shade(MK.METAL, 0.5)
		k.cbox(Vector3(sx * 1.25, 1.55, -3.64), Vector3(0.36, 0.025, 0.025), 0.005)
		for gx: float in [-0.17, 0.17]:
			k.cbox(Vector3(sx * 1.25 + gx, 1.48, -3.64), Vector3(0.025, 0.15, 0.025), 0.005)
		# Seitenschuerzen: fuenf Zusatzpanzer-Module mit Bolzen, darunter Gummilappen
		for i in 5:
			var z := -2.6 + i * 1.3
			k.color = MK.shade(MK.PAINT, 0.92 + 0.06 * float(i % 2))
			k.cbox(Vector3(sx * 1.7, 0.98, z), Vector3(0.14, 0.62, 1.26), 0.03)
			k.color = MK.shade(MK.METAL, 0.4)
			for b in 3:
				k.cbox(Vector3(sx * 1.775, 1.2, z - 0.45 + b * 0.45), Vector3(0.025, 0.05, 0.05), 0.01)
				k.cbox(Vector3(sx * 1.775, 0.76, z - 0.45 + b * 0.45), Vector3(0.025, 0.05, 0.05), 0.01)
			k.color = MK.shade(MK.RUBBER, 1.0)
			k.cbox(Vector3(sx * 1.69, 0.56, z), Vector3(0.04, 0.24, 1.24), 0.01)
		# Kettenbleche vorne/hinten (Schmutzfaenger)
		k.color = MK.PAINT
		k.cbox(Vector3(sx * TRACK_X, 1.01, -3.5), Vector3(0.6, 0.04, 0.4), 0.01, Vector3(-30, 0, 0))
		k.color = MK.shade(MK.RUBBER, 1.0)
		k.cbox(Vector3(sx * TRACK_X, 0.75, 3.55), Vector3(0.58, 0.4, 0.03), 0.01)
		# Haltegriffe/Leiter seitlich
		k.color = MK.shade(MK.METAL, 0.5)
		k.cbox(Vector3(sx * 1.62, 1.6, 2.6), Vector3(0.03, 0.03, 0.6), 0.008)
	# Fahrerluke (links vorne), Kommandanten-/Ausstiegsluken, Lueftungsgitter (rechts vorne)
	k.color = MK.PAINT
	k.lathe(Vector3(-0.85, 1.88, -2.2), Vector3.UP, PackedVector2Array([Vector2(0, 0.0), Vector2(0, 0.38), Vector2(0.05, 0.38), Vector2(0.08, 0.34), Vector2(0.08, 0.0)]), 18)
	k.cbox(Vector3(-0.85, 1.95, -2.62), Vector3(0.62, 0.1, 0.16), 0.03, Vector3(-15, 0, 0))
	k.color = MK.shade(MK.METAL, 0.3)
	for i in 7:
		k.cbox(Vector3(0.75, 1.905, -1.75 + i * 0.13), Vector3(1.0, 0.03, 0.06), 0.008)
	k.color = MK.shade(MK.PAINT, 0.9)
	k.cbox(Vector3(0.75, 1.9, -1.36), Vector3(1.12, 0.02, 1.0), 0.008)
	for sx: float in [-1.0, 1.0]:
		k.color = MK.PAINT
		k.cbox(Vector3(sx * 0.62, 1.925, 2.2), Vector3(0.72, 0.06, 0.95), 0.025)
		k.color = MK.shade(MK.METAL, 0.45)
		k.cbox(Vector3(sx * 0.62, 1.965, 1.82), Vector3(0.36, 0.03, 0.05), 0.008)
	# Heckklappe (Rampe) mit Scharnieren und Trittstufen, Staukaesten
	k.color = MK.shade(MK.PAINT, 0.95)
	k.cbox(Vector3(0, 1.2, 3.53), Vector3(1.5, 1.15, 0.08), 0.02)
	k.color = MK.shade(MK.METAL, 0.45)
	for hx: float in [-0.55, 0.55]:
		k.cbox(Vector3(hx, 0.67, 3.56), Vector3(0.18, 0.08, 0.1), 0.02)
	k.cbox(Vector3(0, 0.6, 3.62), Vector3(1.1, 0.04, 0.22), 0.01)
	k.cbox(Vector3(0.48, 1.35, 3.59), Vector3(0.14, 0.05, 0.05), 0.01)
	for sx: float in [-1.0, 1.0]:
		k.color = MK.PAINT
		k.cbox(Vector3(sx * 1.2, 1.3, 3.6), Vector3(0.65, 0.6, 0.26), 0.04)
		k.color = MK.shade(MK.PAINT, 0.88)
		k.cbox(Vector3(sx * 1.2, 1.62, 3.6), Vector3(0.68, 0.04, 0.29), 0.01)
	# Auspuffgitter rechts hinten (verrusst)
	k.color = MK.shade(MK.METAL, 0.15)
	k.cbox(Vector3(1.61, 1.5, 2.6), Vector3(0.04, 0.24, 0.62), 0.01)
	# Werkzeug, Seil, Kisten auf dem Dach
	k.color = MK.shade(MK.METAL, 0.55)
	k.cbox(Vector3(1.3, 1.92, 1.0), Vector3(0.08, 0.05, 1.5), 0.01)
	k.color = MK.shade(MK.PAINT, 0.7)
	k.cyl(Vector3(-1.35, 1.95, 0.3), Vector3(-1.35, 1.95, 2.9), 0.04, 6)
	var mi := k.emit(hull, paint, "HullShell")
	mi.set_instance_shader_parameter("y_offset", 0.0)

## Doppel-Laufrolle: Gummibandagen, lackierte Scheibe, Nabe mit Bolzen (Achse = X).
static func _road_wheel(k: MK, sx: float) -> void:
	var prof := PackedVector2Array([
		Vector2(-0.24, 0), Vector2(-0.24, 0.06), Vector2(-0.22, 0.09), Vector2(-0.22, 0.19), Vector2(-0.2, 0.25),
		Vector2(-0.2, 0.28), Vector2(-0.18, 0.33), Vector2(-0.04, 0.33), Vector2(-0.025, 0.28), Vector2(0.025, 0.28),
		Vector2(0.04, 0.33), Vector2(0.18, 0.33), Vector2(0.2, 0.28), Vector2(0.2, 0.25), Vector2(0.22, 0.19),
		Vector2(0.22, 0.09), Vector2(0.24, 0.06), Vector2(0.24, 0)])
	var hub := MK.shade(MK.METAL, 0.55)
	var rub := MK.RUBBER
	var pnt := MK.PAINT
	var bands: Array = [hub, pnt, pnt, pnt, pnt, rub, rub, rub, MK.shade(MK.METAL, 0.4), rub, rub, rub, pnt, pnt, pnt, pnt, hub]
	k.color = pnt
	k.lathe(Vector3.ZERO, Vector3.RIGHT, prof, 20, true, bands)
	k.color = MK.shade(MK.METAL, 0.12)
	for i in 6:
		var a := TAU * float(i) / 6.0
		k.cbox(Vector3(sx * 0.225, cos(a) * 0.15, sin(a) * 0.15), Vector3(0.02, 0.06, 0.06), 0.012)
	k.color = MK.shade(MK.METAL, 0.6)
	for i in 6:
		var a := TAU * float(i) / 6.0
		k.cbox(Vector3(sx * 0.25, cos(a) * 0.05, sin(a) * 0.05), Vector3(0.03, 0.022, 0.022), 0.005)

## Kettenbaender (unten, oben, schraege Enden) mit Leitrad vorn und Triebrad hinten.
static func _build_tracks(k: MK) -> void:
	for sx: float in [-1.0, 1.0]:
		var x := sx * TRACK_X
		k.color = MK.shade(MK.RUBBER, 0.85)
		k.cbox(Vector3(x, 0.045, 0.0), Vector3(0.54, 0.09, 5.2), 0.02)
		k.cbox(Vector3(x, 0.93, 0.02), Vector3(0.54, 0.08, 6.36), 0.02)
		k.cbox(Vector3(x, 0.25, -2.98), Vector3(0.54, 0.09, 0.9), 0.02, Vector3(29, 0, 0))
		k.cbox(Vector3(x, 0.27, 2.98), Vector3(0.54, 0.09, 0.9), 0.02, Vector3(-31, 0, 0))
		# Fuehrungszaehne/Stege als dunkle Querrippen auf dem unteren Trum
		k.color = MK.shade(MK.METAL, 0.25)
		for i in 26:
			k.cbox(Vector3(x, 0.095, -2.5 + i * 0.2), Vector3(0.5, 0.02, 0.05), 0.005)
		# Leitrad (vorne) und Triebrad (hinten), vom Kettenband umschlossen
		for ends: Vector3 in [Vector3(-3.18, 0.6, 0.3), Vector3(3.18, 0.64, 0.3)]:
			k.color = MK.shade(MK.RUBBER, 0.85)
			k.lathe(Vector3(x, ends.y, ends.x), Vector3.RIGHT, PackedVector2Array([Vector2(-0.27, 0), Vector2(-0.27, ends.z + 0.04), Vector2(0.27, ends.z + 0.04), Vector2(0.27, 0)]), 18)
			k.color = MK.shade(MK.PAINT, 0.8)
			k.lathe(Vector3(x, ends.y, ends.x), Vector3.RIGHT, PackedVector2Array([Vector2(-0.285, 0), Vector2(-0.285, ends.z - 0.06), Vector2(0.285, ends.z - 0.06), Vector2(0.285, 0)]), 16)
			k.color = MK.shade(MK.METAL, 0.5)
			k.cyl(Vector3(x - 0.3, ends.y, ends.x), Vector3(x + 0.3, ends.y, ends.x), 0.07, 8)
		# Stuetzrollen
		k.color = MK.shade(MK.METAL, 0.4)
		for z: float in [-1.5, 0.0, 1.5]:
			k.cyl(Vector3(x - 0.2, 0.84, z), Vector3(x + 0.2, 0.84, z), 0.06, 8)

# ------------------------------------------------------------------ Turm

static func _build_turret(k: MK, turret: Node3D) -> Array[Marker3D]:
	var plan := PackedVector2Array(TURRET_PLAN)
	# Drehkranz-Schuerze
	k.color = MK.shade(MK.METAL, 0.3)
	k.lathe(Vector3(0, -0.02, 0.1), Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(0, 1.0), Vector2(0.12, 1.0), Vector2(0.12, 0)]), 26, false)
	k.color = MK.PAINT
	var rings: Array[PackedVector3Array] = [
		MK.ring_y(MK.offset_poly(plan, -0.12), 0.06),
		MK.ring_y(plan, 0.16),
		MK.ring_y(MK.offset_poly(plan, -0.05), 0.68),
		MK.ring_y(MK.offset_poly(plan, -0.2), 0.8)]
	k.loft(rings, true, true)
	# Zusatzpanzer-Module an den Turmseiten (Keilform vorn)
	for sx: float in [-1.0, 1.0]:
		k.color = MK.shade(MK.PAINT, 0.93)
		k.cbox(Vector3(sx * 1.24, 0.42, 0.25), Vector3(0.1, 0.5, 1.6), 0.025)
		k.color = MK.shade(MK.METAL, 0.4)
		for b in 3:
			k.cbox(Vector3(sx * 1.3, 0.6, -0.35 + b * 0.6), Vector3(0.02, 0.045, 0.045), 0.008)
	k.color = MK.shade(MK.PAINT, 0.95)
	k.cbox(Vector3(0.45, 0.38, -1.18), Vector3(0.7, 0.44, 0.12), 0.03, Vector3(0, 0, 0))
	# Richtschuetzen-Optik ueber der Kamera, Kommandanten-Rundblickoptik
	k.color = MK.PAINT
	k.cbox(Vector3(CAM_POS.x, 0.98, CAM_POS.z + 0.18), Vector3(0.44, 0.34, 0.48), 0.05)
	k.color = MK.shade(MK.METAL, 0.3)
	k.cbox(Vector3(CAM_POS.x, 1.0, CAM_POS.z - 0.04), Vector3(0.38, 0.26, 0.04), 0.01)
	k.color = MK.PAINT
	k.lathe(Vector3(-0.7, 0.8, 0.7), Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.2), Vector2(0.26, 0.2), Vector2(0.3, 0.17), Vector2(0.42, 0.17), Vector2(0.45, 0.0)]), 16)
	k.color = MK.shade(MK.METAL, 0.3)
	k.cbox(Vector3(-0.7, 1.1, 0.56), Vector3(0.28, 0.18, 0.04), 0.01)
	# Nebelwurfbecher (2 x 3, schraeg nach vorn/oben) + Halteleiste
	var tubes: Array[Marker3D] = []
	for sx: float in [-1.0, 1.0]:
		k.color = MK.shade(MK.METAL, 0.45)
		k.cbox(Vector3(sx * 1.2, 0.6, -0.5), Vector3(0.14, 0.08, 0.5), 0.02)
		for i in 3:
			var tp := Vector3(sx * (1.22 + i * 0.02), 0.62 + i * 0.12, -0.55 + i * 0.05)
			var ax := Basis.from_euler(Vector3(deg_to_rad(-60), 0, deg_to_rad(sx * -25.0))) * Vector3.UP
			k.color = MK.shade(MK.PAINT, 0.8)
			k.lathe(tp - ax * 0.16, ax, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.055), Vector2(0.32, 0.055), Vector2(0.32, 0.04), Vector2(0.3, 0.0)]), 8)
			var mk := Marker3D.new()
			mk.position = tp + Vector3(sx * 0.1, 0.12, -0.1)
			turret.add_child(mk)
			tubes.append(mk)
	# Staukorb hinten mit Planen
	k.color = MK.shade(MK.METAL, 0.4)
	k.cbox(Vector3(0, 0.3, 1.62), Vector3(2.2, 0.05, 0.62), 0.01)
	for i in 5:
		k.cbox(Vector3(-1.05 + i * 0.525, 0.48, 1.92), Vector3(0.04, 0.4, 0.04), 0.008)
	k.cbox(Vector3(0, 0.66, 1.92), Vector3(2.15, 0.04, 0.04), 0.008)
	k.color = MK.shade(MK.PAINT, 0.7)
	k.cbox(Vector3(0.25, 0.47, 1.62), Vector3(1.3, 0.3, 0.5), 0.1)
	k.cbox(Vector3(-0.7, 0.45, 1.6), Vector3(0.5, 0.26, 0.48), 0.06)
	# Dachdetails: Sensorkopf, Waffenstation-Sockel, Handgriffe
	k.color = MK.shade(MK.METAL, 0.45)
	k.cbox(Vector3(0.15, 0.84, 0.9), Vector3(0.9, 0.03, 0.04), 0.008)
	k.cyl(Vector3(0.95, 0.8, 1.15), Vector3(0.95, 0.88, 1.15), 0.05, 8)
	k.color = MK.PAINT
	k.cbox(Vector3(0.1, 0.86, 0.3), Vector3(0.36, 0.12, 0.36), 0.03)
	return tubes

## 30-mm-Kanone: Rohrwiege, Rohr mit Waermeschutz, Muendungsbremse.
static func _build_barrel(k: MK) -> void:
	var paint := MK.PAINT
	var band := MK.shade(MK.PAINT, 0.75)
	var steel := MK.shade(MK.METAL, 0.8)
	var bore := MK.shade(MK.METAL, 0.05)
	var prof := PackedVector2Array([
		Vector2(0.3, 0.0), Vector2(0.3, 0.12), Vector2(1.05, 0.12), Vector2(1.1, 0.085),
		Vector2(1.6, 0.075), Vector2(1.63, 0.085), Vector2(1.7, 0.085), Vector2(1.73, 0.072),
		Vector2(2.6, 0.068), Vector2(2.63, 0.06), Vector2(2.95, 0.06), Vector2(2.97, 0.085),
		Vector2(3.3, 0.085), Vector2(3.3, 0.04), Vector2(3.2, 0.04), Vector2(3.2, 0.0)])
	var bands: Array = [paint, paint, paint, band, band, steel, steel, band, band, steel, steel, steel, steel, bore, bore]
	k.color = paint
	k.lathe(Vector3.ZERO, Vector3.FORWARD, prof, 16, true, bands)
	# Schlitze der Muendungsbremse
	k.color = bore
	for i in 3:
		for sx: float in [-1.0, 1.0]:
			k.cbox(Vector3(sx * 0.08, 0, -3.05 - i * 0.09), Vector3(0.02, 0.1, 0.04), 0.005)

# ------------------------------------------------------------------ Abziehbilder

static func _decals(hull: Node3D, turret: Node3D) -> void:
	var idx := randi() % 4
	var nm := Livery.decal_mat(Livery.DECAL_NUMBERS, Vector4(0.5 * float(idx % 2), 0.5 * float(idx / 2), 0.5, 0.5), Color(0.86, 0.86, 0.8))
	for sx: float in [-1.0, 1.0]:
		Livery.decal(turret, nm, Vector3(sx * 1.296, 0.4, 0.55), Vector3(sx, 0, 0), Vector2(0.42, 0.42))
		Livery.decal(hull, nm, Vector3(sx * 1.605, 1.5, 2.0), Vector3(sx, 0, 0), Vector2(0.38, 0.38))
	Livery.decal(hull, nm, Vector3(0.0, 1.45, 3.575), Vector3.BACK, Vector2(0.36, 0.36))

## Kollisionsquader [Mitte, Groesse] in Fahrzeugkoordinaten (Wanne, Turm).
static func shapes() -> Array:
	if _marder_available():
		return [[Vector3(0, 1.09, 0), Vector3(3.32, 1.86, 6.78)], [Vector3(-0.02, 2.46, 0.12), Vector3(1.95, 0.88, 1.8)]]
	return [[Vector3(0, 1.05, 0.1), Vector3(3.4, 1.7, 7.0)], [TURRET_POS + Vector3(0, 0.45, 0.25), Vector3(2.4, 0.8, 2.7)]]
