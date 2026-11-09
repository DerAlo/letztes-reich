extends RefCounted
## Prozeduraler Kampfhubschrauber im Stil Mi-28 (fiktiv): facettierter Panzerrumpf mit Tandem-Cockpit aus
## flachen Panzerglasscheiben, Triebwerksgondeln mit Staubfiltern und nach aussen gelenkten Abgasrohren,
## Stummelfluegel mit Raketenbehaeltern und Lenkwaffen, Kinnkanone, Radarkuppel ueber dem Rotor.
## build(pivot, faction) haengt alle Teile an pivot und liefert die beweglichen Knoten (Schluessel unveraendert).
## Koordinaten: -Z = vorne, Ursprung = Schwerpunkt; Rotornabe bei y = 2.1. Lack: vehicle_paint.gdshader.

const VF = preload("res://game/vehicles/vehicle_fx.gd")
const MK = preload("res://game/vehicles/models/mesh_kit.gd")
const Livery = preload("res://game/vehicles/models/livery.gd")

const ROTOR_RADIUS := 7.4
const TAIL_ROTOR_RADIUS := 1.45
const Y_OFFSET := 1.6   # Hoehe des Rumpfbodens ueber Grund (fuer Schmutz im Lack-Shader)

# Rumpf-Stationen: (z, halbe Breite, Unterkante, Oberkante)
const FUSELAGE: Array[Vector4] = [
	Vector4(-4.35, 0.2, -0.72, -0.42), Vector4(-4.05, 0.48, -0.92, -0.1), Vector4(-3.35, 0.7, -1.0, 0.14),
	Vector4(-2.2, 0.76, -1.02, 0.42), Vector4(-0.9, 0.84, -1.02, 0.72), Vector4(0.6, 0.86, -1.0, 0.86),
	Vector4(1.9, 0.76, -0.85, 0.84), Vector4(2.9, 0.52, -0.42, 0.82)]
const BOOM: Array[Vector4] = [
	Vector4(2.8, 0.54, -0.38, 0.84), Vector4(5.0, 0.36, 0.14, 0.85), Vector4(8.6, 0.22, 0.4, 0.8), Vector4(9.35, 0.17, 0.46, 0.78)]

static func build(pivot: Node3D, faction: String = "ru") -> Dictionary:
	var paint := Livery.paint("heli", faction)
	var dark := VF.mat("heli_dark", Color(0.06, 0.065, 0.062), 0.45, 0.6)
	var glass := VF.glass_mat(Color(0.08, 0.12, 0.14, 0.62))
	var hot := VF.mat("heli_exhaust", Color(0.1, 0.06, 0.04), 0.5, 0.6, Color(1.0, 0.35, 0.1), 1.2)
	var tip_col := Color(0.62, 0.55, 0.16) if faction != "reich" else Color(1.0, 0.6, 0.12)
	var out: Dictionary = {}

	# --- Rumpf, Heck, Fluegel, Fahrwerk: ein Lack-Mesh ----------------------------
	var k := MK.new()
	_build_body(k, faction)
	var body := k.emit(pivot, paint, "Body")
	body.set_instance_shader_parameter("y_offset", Y_OFFSET)
	# Panzerglas-Kanzeln (facettiert)
	var gk := MK.new()
	gk.color = Color(1, 1, 1, 1)
	_canopy(gk, [Vector4(-3.95, -0.05, 0.46, 0.0), Vector4(-3.3, 0.12, 0.66, 0.6), Vector4(-2.35, 0.38, 0.72, 0.76)], 0.62)
	_canopy(gk, [Vector4(-2.3, 0.4, 0.74, 0.9), Vector4(-1.05, 0.68, 0.82, 1.24), Vector4(-0.45, 0.74, 0.8, 1.18)], 0.6)
	var gmi := gk.emit(pivot, glass, "Canopy")
	gmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Abgas-Gluehen
	for sx: float in [-1.0, 1.0]:
		var ex := Vector3(sx * 1.5, 0.82, 2.66)
		var g := VF.mesh_node(pivot, VF.cyl(0.2, 0.2, 0.03, 12), hot, ex, Vector3.ZERO)
		g.look_at_from_position(ex, ex + Vector3(sx * 0.5, -0.35, 1.0).normalized(), Vector3.UP)
		g.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	out["exhaust_l"] = Vector3(-1.55, 0.8, 2.75)
	out["exhaust_r"] = Vector3(1.55, 0.8, 2.75)
	# Sensor-Fenster in der Nase
	VF.mesh_node(pivot, VF.box(Vector3(0.26, 0.2, 0.02)), VF.glass_mat(Color(0.25, 0.1, 0.05, 0.8)), Vector3(0, -0.64, -4.36))
	_decals(pivot, faction)

	# Positionslichter (links rot, rechts gruen)
	out["nav_l"] = _light_bulb(pivot, Vector3(-3.22, 0.2, -0.3), Color(1.0, 0.05, 0.03))
	out["nav_r"] = _light_bulb(pivot, Vector3(3.22, 0.2, -0.3), Color(0.1, 1.0, 0.2))
	out["strobe"] = _light_bulb(pivot, Vector3(0, 0.95, 4.0), Color(1.0, 0.1, 0.05))

	# --- Kinnkanone ----------------------------------------------------------------
	var gun_yaw := Node3D.new()
	gun_yaw.name = "GunYaw"
	gun_yaw.position = Vector3(0, -0.95, -3.0)
	pivot.add_child(gun_yaw)
	var yk := MK.new()
	yk.color = MK.shade(MK.PAINT, 0.8)
	yk.lathe(Vector3(0, 0.12, 0), Vector3.DOWN, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.36), Vector2(0.14, 0.34), Vector2(0.22, 0.24), Vector2(0.24, 0.0)]), 16)
	yk.color = MK.shade(MK.PAINT, 0.7)
	for sx: float in [-1.0, 1.0]:
		yk.cbox(Vector3(sx * 0.2, -0.16, -0.05), Vector3(0.07, 0.3, 0.42), 0.02)
	yk.emit(gun_yaw, paint, "GunMount").set_instance_shader_parameter("y_offset", Y_OFFSET - 0.95)
	var gun_pitch := Node3D.new()
	gun_pitch.name = "GunPitch"
	gun_pitch.position = Vector3(0, -0.16, 0)
	gun_yaw.add_child(gun_pitch)
	var pk := MK.new()
	pk.color = MK.shade(MK.PAINT, 0.75)
	pk.cbox(Vector3(0, 0, -0.25), Vector3(0.3, 0.26, 0.8), 0.04)
	pk.color = MK.shade(MK.METAL, 0.45)
	pk.cbox(Vector3(0.19, 0.0, -0.2), Vector3(0.1, 0.18, 0.5), 0.02)   # Gurtzufuehrung
	pk.lathe(Vector3(0, 0, -0.6), Vector3.FORWARD, PackedVector2Array([
		Vector2(0, 0), Vector2(0, 0.085), Vector2(0.35, 0.085), Vector2(0.38, 0.065), Vector2(1.3, 0.06),
		Vector2(1.32, 0.09), Vector2(1.55, 0.09), Vector2(1.57, 0.04), Vector2(1.5, 0.04), Vector2(1.5, 0)]), 12)
	pk.emit(gun_pitch, paint, "Gun").set_instance_shader_parameter("y_offset", Y_OFFSET - 1.1)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0, -2.2)
	gun_pitch.add_child(muzzle)
	out["gun_yaw"] = gun_yaw
	out["gun_pitch"] = gun_pitch
	out["muzzle"] = muzzle
	out["flash"] = VF.make_muzzle_flash(muzzle, 0.9, 8.0, 10.0)
	var sl := Marker3D.new()
	sl.name = "SearchlightMount"
	sl.position = Vector3(0, -1.0, -2.0)
	pivot.add_child(sl)
	out["searchlight_mount"] = sl

	# --- Hauptrotor ------------------------------------------------------------------
	var rotor := Node3D.new()
	rotor.name = "MainRotor"
	rotor.position = Vector3(0, 2.1, 0.0)
	pivot.add_child(rotor)
	var rk := MK.new()
	rk.color = MK.shade(MK.METAL, 0.55)
	rk.lathe(Vector3(0, -0.2, 0), Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.46), Vector2(0.1, 0.48), Vector2(0.3, 0.44), Vector2(0.36, 0.3), Vector2(0.36, 0.0)]), 16)
	rk.color = MK.shade(MK.METAL, 0.35)
	for i in 5:
		var a := TAU * float(i) / 5.0
		var d := Vector3(-sin(a), 0, -cos(a))
		rk.cbox(d * 0.55, Vector3(0.22, 0.16, 0.5), 0.03, Vector3(0, rad_to_deg(a), 0))
	# Radarkuppel auf dem Mast
	rk.color = MK.shade(MK.PAINT, 0.85)
	rk.lathe(Vector3(0, 0.15, 0), Vector3.UP, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.12), Vector2(0.25, 0.1), Vector2(0.3, 0.38), Vector2(0.45, 0.4), Vector2(0.62, 0.3), Vector2(0.7, 0.0)]), 16)
	rk.emit(rotor, paint, "Hub").set_instance_shader_parameter("y_offset", Y_OFFSET + 2.1)
	var blades := Node3D.new()
	blades.name = "Blades"
	rotor.add_child(blades)
	var blade_mat := VF.mat("heli_blade", Color(0.07, 0.075, 0.07), 0.5, 0.3)
	var tip_mat := VF.mat("heli_tip_" + faction, tip_col, 0.5, 0.2)
	var blade_list: Array[MeshInstance3D] = []
	for i in 5:
		var arm := Node3D.new()
		arm.rotation.y = TAU * float(i) / 5.0
		blades.add_child(arm)
		var b := VF.mesh_node(arm, VF.box(Vector3(0.58, 0.06, ROTOR_RADIUS - 0.5)), blade_mat, Vector3(0, 0, -(ROTOR_RADIUS + 0.5) * 0.5), Vector3(1.5, 0, 0))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		blade_list.append(b)
		VF.mesh_node(arm, VF.box(Vector3(0.6, 0.065, 0.32)), tip_mat, Vector3(0, 0.0, -ROTOR_RADIUS + 0.18), Vector3(1.5, 0, 0))
	var disc_mesh := PlaneMesh.new()
	disc_mesh.size = Vector2.ONE * ROTOR_RADIUS * 2.0
	var disc_mat := ShaderMaterial.new()
	disc_mat.shader = load("res://game/vehicles/shaders/rotor_blur.gdshader")
	disc_mat.set_shader_parameter("blades", 5.0)
	var disc := VF.mesh_node(rotor, disc_mesh, disc_mat, Vector3(0, -0.02, 0))
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out["rotor"] = rotor
	out["blades"] = blades
	out["blade_meshes"] = blade_list
	out["disc"] = disc
	out["disc_mat"] = disc_mat

	# --- Heckrotor (X-Form) ------------------------------------------------------------
	var tail := Node3D.new()
	tail.name = "TailRotor"
	tail.position = Vector3(0.38, 2.35, 9.5)
	pivot.add_child(tail)
	VF.mesh_node(tail, VF.cyl(0.12, 0.14, 0.3, 10), VF.mat("heli_metal", Color(0.28, 0.29, 0.3), 0.32, 0.9), Vector3(-0.1, 0, 0), Vector3(0, 0, 90))
	var tail_blades := Node3D.new()
	tail.add_child(tail_blades)
	for i in 4:
		var arm := Node3D.new()
		arm.rotation.x = TAU * float(i) / 4.0 + (0.3 if i % 2 == 1 else 0.0)
		tail_blades.add_child(arm)
		VF.mesh_node(arm, VF.box(Vector3(0.05, TAIL_ROTOR_RADIUS, 0.24)), blade_mat, Vector3(0, TAIL_ROTOR_RADIUS * 0.5, 0))
		VF.mesh_node(arm, VF.box(Vector3(0.055, 0.18, 0.25)), tip_mat, Vector3(0, TAIL_ROTOR_RADIUS - 0.09, 0))
	var tdisc_mesh := PlaneMesh.new()
	tdisc_mesh.size = Vector2.ONE * TAIL_ROTOR_RADIUS * 2.0
	var tdisc_mat := disc_mat.duplicate() as ShaderMaterial
	tdisc_mat.set_shader_parameter("blades", 4.0)
	tdisc_mat.set_shader_parameter("opacity", 0.28)
	var tdisc := VF.mesh_node(tail, tdisc_mesh, tdisc_mat, Vector3(0.04, 0, 0), Vector3(0, 0, 90))
	tdisc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out["tail_rotor"] = tail_blades
	out["tail_disc_mat"] = tdisc_mat
	return out

# ------------------------------------------------------------------ Rumpf

static func _oct(st: Vector4) -> PackedVector3Array:
	var z := st.x
	var w := st.y
	var yb := st.z
	var yt := st.w
	var h := yt - yb
	return PackedVector3Array([
		Vector3(-0.62 * w, yb, z), Vector3(-w, yb + 0.3 * h, z), Vector3(-w, yt - 0.28 * h, z), Vector3(-0.58 * w, yt, z),
		Vector3(0.58 * w, yt, z), Vector3(w, yt - 0.28 * h, z), Vector3(w, yb + 0.3 * h, z), Vector3(0.62 * w, yb, z)])

static func _section(k: MK, stations: Array[Vector4]) -> void:
	var rings: Array[PackedVector3Array] = []
	for st in stations:
		rings.append(_oct(st))
	k.loft(rings)

## Nacelle/Verkleidung: Superellipsen-Ringe um (cx, cy). st = (z, Skalierung)
static func _pod(k: MK, cx: float, cy: float, rx: float, ry: float, e: float, st: Array[Vector2], smooth: bool = true) -> void:
	var base := MK.superellipse(rx, ry, e, 16)
	var rings: Array[PackedVector3Array] = []
	for s in st:
		var r := PackedVector3Array()
		for p in base:
			r.append(Vector3(cx + p.x * s.y, cy + p.y * s.y, s.x))
		rings.append(r)
	k.loft(rings, true, true, smooth)

static func _canopy(k: MK, st: Array, top_scale: float) -> void:
	# st: (z, Unterkante y, halbe Breite unten, Oberkante y) -> facettierte Trapez-Ringe
	var rings: Array[PackedVector3Array] = []
	for s: Vector4 in st:
		var wt := s.z * top_scale
		var ym := lerpf(s.y, s.w, 0.55)
		rings.append(PackedVector3Array([
			Vector3(-s.z, s.y, s.x), Vector3(-s.z * 0.96, ym, s.x), Vector3(-wt, s.w, s.x),
			Vector3(wt, s.w, s.x), Vector3(s.z * 0.96, ym, s.x), Vector3(s.z, s.y, s.x)]))
	k.loft(rings)

static func _build_body(k: MK, faction: String) -> void:
	k.color = MK.PAINT
	_section(k, FUSELAGE)
	_section(k, BOOM)
	# Kanzelrahmen
	k.color = MK.shade(MK.PAINT, 0.6)
	for f: Vector4 in [Vector4(-3.3, 0.12, 0.66, 0.6), Vector4(-2.32, 0.39, 0.73, 0.83), Vector4(-1.05, 0.68, 0.82, 1.24)]:
		k.cbox(Vector3(0, f.w + 0.015, f.x), Vector3(f.z * 1.25, 0.05, 0.07), 0.015)
	k.cbox(Vector3(0, 1.0, -1.7), Vector3(0.06, 0.06, 1.3), 0.015, Vector3(-14, 0, 0))
	# Seitliche Avionik-Kaesten und Einstiegsstufen
	k.color = MK.shade(MK.PAINT, 0.95)
	for sx: float in [-1.0, 1.0]:
		k.cbox(Vector3(sx * 0.86, -0.35, 0.5), Vector3(0.22, 0.75, 2.4), 0.06)
		k.cbox(Vector3(sx * 0.78, -0.55, -2.2), Vector3(0.1, 0.5, 1.0), 0.03)
	# Getriebeverkleidung + Mast
	_pod(k, 0.0, 1.12, 0.62, 0.36, 3.0, [Vector2(-1.4, 0.55), Vector2(-1.0, 1.0), Vector2(1.7, 1.0), Vector2(2.6, 0.45)], false)
	k.color = MK.shade(MK.METAL, 0.45)
	k.cyl(Vector3(0, 1.3, 0), Vector3(0, 2.0, 0), 0.17, 12)
	# Triebwerksgondeln mit Staubfiltern (Pilzhauben) und Abgasrohren
	for sx: float in [-1.0, 1.0]:
		k.color = MK.PAINT
		_pod(k, sx * 1.0, 1.02, 0.42, 0.44, 2.6, [Vector2(-1.3, 0.82), Vector2(-1.05, 1.0), Vector2(1.5, 1.0), Vector2(2.2, 0.72)])
		k.color = MK.shade(MK.PAINT, 0.8)
		k.lathe(Vector3(sx * 1.0, 1.02, -1.3), Vector3.FORWARD, PackedVector2Array([Vector2(0, 0.0), Vector2(0, 0.37), Vector2(0.06, 0.4), Vector2(0.22, 0.36), Vector2(0.34, 0.2), Vector2(0.38, 0.0)]), 14)
		k.color = MK.shade(MK.METAL, 0.3)
		k.lathe(Vector3(sx * 1.0, 1.02, -1.36), Vector3.FORWARD, PackedVector2Array([Vector2(0, 0.41), Vector2(0.05, 0.41), Vector2(0.05, 0.0)]), 14)
		# Abgasrohr nach aussen/unten
		var ex0 := Vector3(sx * 1.1, 1.0, 2.05)
		var exd := Vector3(sx * 0.5, -0.35, 1.0).normalized()
		k.color = MK.shade(MK.METAL, 0.3)
		k.lathe(ex0, exd, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.28), Vector2(0.72, 0.24), Vector2(0.72, 0.2), Vector2(0.6, 0.2), Vector2(0.6, 0.0)]), 14)
		# Verkleidungsfugen / Wartungsklappen
		k.color = MK.shade(MK.PAINT, 0.7)
		k.cbox(Vector3(sx * 1.38, 1.02, 0.2), Vector3(0.03, 0.4, 0.03), 0.005)
		k.cbox(Vector3(sx * 1.38, 1.02, 1.0), Vector3(0.03, 0.4, 0.03), 0.005)
	# Seitenleitwerk (gepfeilt) + Hoehenleitwerk
	k.color = MK.PAINT
	k.prism_x(PackedVector2Array([Vector2(8.4, 0.78), Vector2(9.65, 0.7), Vector2(9.95, 2.62), Vector2(9.35, 2.78)]), -0.1, 0.1, 0.035)
	k.cbox(Vector3(0, 1.4, 9.45), Vector3(2.7, 0.07, 0.62), 0.025, Vector3(0, 0, 0))
	for sx: float in [-1.0, 1.0]:
		k.cbox(Vector3(sx * 1.36, 1.4, 9.5), Vector3(0.05, 0.36, 0.6), 0.015)
	k.color = MK.shade(MK.METAL, 0.45)
	k.cbox(Vector3(0.22, 2.35, 9.5), Vector3(0.22, 0.28, 0.3), 0.04)   # Heckrotorgetriebe
	# Stummelfluegel (Anhedral), Pylone, Raketenbehaelter, Lenkwaffen, Taeuschkoerper
	for sx: float in [-1.0, 1.0]:
		k.color = MK.PAINT
		var rings: Array[PackedVector3Array] = [_wing_ring(sx * 0.75, 0.34, -0.95, 0.45, 0.17), _wing_ring(sx * 3.15, 0.12, -0.62, 0.12, 0.1)]
		k.loft(rings)
		for px: float in [1.85, 2.8]:
			k.cbox(Vector3(sx * px, 0.08 + (0.34 - 0.12) * (1.0 - (px - 0.75) / 2.4) - 0.1, -0.3), Vector3(0.12, 0.3, 0.75), 0.02)
		# Raketenbehaelter
		k.lathe(Vector3(sx * 1.85, -0.16, -0.3), Vector3.BACK, PackedVector2Array([
			Vector2(-0.95, 0), Vector2(-0.95, 0.23), Vector2(-0.92, 0.27), Vector2(0.65, 0.27), Vector2(0.95, 0.12), Vector2(0.95, 0)]), 16, true,
			[MK.shade(MK.METAL, 0.12), MK.PAINT, MK.PAINT, MK.PAINT, MK.PAINT])
		k.color = MK.shade(MK.METAL, 0.5)
		for i in 8:
			var a := TAU * float(i) / 8.0
			var c := Vector3(sx * 1.85 + cos(a) * 0.15, -0.16 + sin(a) * 0.15, -1.25)
			k.lathe(c, Vector3.FORWARD, PackedVector2Array([Vector2(0, 0.045), Vector2(0.02, 0.045), Vector2(0.02, 0.03), Vector2(0.0, 0.03)]), 8)
		# Lenkwaffen 2x2
		for oy: float in [0.0, 1.0]:
			for ox: float in [0.0, 1.0]:
				k.color = MK.shade(MK.PAINT, 0.85)
				var c := Vector3(sx * (2.72 + ox * 0.2), -0.06 - oy * 0.2, -0.3)
				k.lathe(c, Vector3.FORWARD, PackedVector2Array([Vector2(-0.85, 0), Vector2(-0.85, 0.085), Vector2(0.85, 0.085), Vector2(0.85, 0.06), Vector2(0.88, 0.0)]), 10, true,
					[MK.shade(MK.PAINT, 0.6), MK.shade(MK.PAINT, 0.85), MK.shade(MK.METAL, 0.5), MK.shade(MK.METAL, 0.5)])
		k.color = MK.shade(MK.PAINT, 0.8)
		k.cbox(Vector3(sx * 2.82, 0.07, -0.3), Vector3(0.48, 0.06, 1.0), 0.015)
		k.cbox(Vector3(sx * 3.22, 0.04, -0.3), Vector3(0.12, 0.26, 0.75), 0.03)
		# Hauptfahrwerk
		k.color = MK.shade(MK.METAL, 0.5)
		k.cyl(Vector3(sx * 0.72, -0.9, -1.4), Vector3(sx * 1.32, -1.55, -1.4), 0.065, 8)
		k.cyl(Vector3(sx * 0.7, -0.6, -0.9), Vector3(sx * 1.3, -1.5, -1.38), 0.05, 8)
		k.lathe(Vector3(sx * 1.38, -1.62, -1.4), Vector3.RIGHT, PackedVector2Array([
			Vector2(-0.12, 0), Vector2(-0.12, 0.2), Vector2(-0.1, 0.3), Vector2(-0.06, 0.32), Vector2(0.06, 0.32), Vector2(0.1, 0.3), Vector2(0.12, 0.2), Vector2(0.12, 0)]), 16, true,
			[MK.shade(MK.METAL, 0.5), MK.RUBBER, MK.RUBBER, MK.RUBBER, MK.RUBBER, MK.RUBBER, MK.shade(MK.METAL, 0.5)])
	# Spornrad
	k.color = MK.shade(MK.METAL, 0.5)
	k.cyl(Vector3(0, 0.42, 7.6), Vector3(0, -0.4, 7.7), 0.05, 8)
	k.lathe(Vector3(0, -0.5, 7.7), Vector3.RIGHT, PackedVector2Array([Vector2(-0.07, 0), Vector2(-0.07, 0.18), Vector2(0.07, 0.18), Vector2(0.07, 0)]), 12, true, [MK.shade(MK.METAL, 0.5), MK.RUBBER, MK.shade(MK.METAL, 0.5)])
	# Sensorkopf unter der Nase, Staurohre, Antennen
	k.color = MK.shade(MK.PAINT, 0.7)
	k.lathe(Vector3(0, -0.62, -3.85), Vector3.FORWARD, PackedVector2Array([Vector2(0, 0), Vector2(0, 0.3), Vector2(0.35, 0.3), Vector2(0.48, 0.18), Vector2(0.5, 0.0)]), 14)
	k.color = MK.shade(MK.METAL, 0.6)
	for sx: float in [-1.0, 1.0]:
		k.cyl(Vector3(sx * 0.35, 0.05, -3.9), Vector3(sx * 0.35, 0.05, -4.7), 0.018, 6)
	k.cbox(Vector3(0, 0.9, 2.6), Vector3(0.04, 0.25, 0.3), 0.01, Vector3(-20, 0, 0))
	if faction == "reich":
		# Amber-Ring am Heckausleger
		k.color = MK.ACCENT
		var a0 := _oct(Vector4(7.4, 0.256, 0.335, 0.818))
		var a1 := _oct(Vector4(7.8, 0.243, 0.362, 0.812))
		var band: Array[PackedVector3Array] = [_grow(a0, 0.012), _grow(a1, 0.012)]
		k.loft(band, false, false)

static func _grow(r: PackedVector3Array, d: float) -> PackedVector3Array:
	var c := Vector3.ZERO
	for p in r:
		c += p
	c /= float(r.size())
	var out := PackedVector3Array()
	for p in r:
		var o := p - c
		o.z = 0.0
		out.append(p + o.normalized() * d)
	return out

static func _wing_ring(x: float, y: float, z_le: float, z_te: float, t: float) -> PackedVector3Array:
	var c := z_te - z_le
	return PackedVector3Array([
		Vector3(x, y, z_le), Vector3(x, y + t * 0.5, z_le + c * 0.18), Vector3(x, y + t * 0.35, z_te - c * 0.15),
		Vector3(x, y, z_te), Vector3(x, y - t * 0.35, z_te - c * 0.15), Vector3(x, y - t * 0.5, z_le + c * 0.18)])

static func _decals(pivot: Node3D, faction: String) -> void:
	var idx := randi() % 4
	var nm := Livery.decal_mat(Livery.DECAL_NUMBERS, Vector4(0.5 * float(idx % 2), 0.5 * float(idx / 2), 0.5, 0.5), Color(0.9, 0.9, 0.86) if faction != "reich" else Color(1.0, 0.72, 0.3))
	for sx: float in [-1.0, 1.0]:
		var n := Vector3(sx, 0, 0)
		Livery.decal(pivot, nm, Vector3(sx * 0.318, 0.55, 6.4), n, Vector2(0.4, 0.4))
		if faction == "reich":
			# Ordnungsfront-Emblem auf dem Heckausleger
			Livery.decal(pivot, Livery.decal_mat(Livery.EMBLEM_TEX), Vector3(sx * 0.455, 0.39, 4.0), n, Vector2(0.46, 0.46))

static func _light_bulb(parent: Node3D, pos: Vector3, c: Color) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 6.0
	var mi := VF.mesh_node(parent, VF.sphere(0.07, -1.0, 8), m, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = c
	l.omni_range = 3.0
	l.light_energy = 1.2
	l.shadow_enabled = false
	mi.add_child(l)
	return mi
