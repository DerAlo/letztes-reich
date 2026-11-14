extends Node
## Screenshots der Waffen (Runde weapons3: + Nahaufnahme, Kiste, Drop am Boden): G36C Hüfte/ADS, AK-74M, Panzerfaust, Pickup-Hinweis, Rakete.
## godot --path . res://game/player/_capture_weapons.tscn -- --out=captures/weapons2
## Nicht headless starten (Screenshots brauchen den Renderer). Gibt "CAPTURE_DONE n=N" aus.

var player: Player
var _out: String = "captures/weapons2"
var _n: int = 0

func _ready() -> void:
	_out = str(Game.arg("out", _out))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	get_window().size = Vector2i(1600, 900)
	var lv: Node = (load("res://game/levels/test_range.tscn") as PackedScene).instantiate()
	lv.set("spawn_enemies", false)
	if "ambient_artillery" in lv:
		lv.set("ambient_artillery", false)
	add_child(lv)
	await _wait(0.6)
	if str(Game.arg("big", "")) != "":
		# --bg setzt das Fenster nach 1 s auf 480x270 -> danach wieder vergroessern (lesbare Visierbilder)
		await _wait(0.8)
		get_window().size = Vector2i(1280, 720)
		await _wait(0.3)
	player = Game.get_player() as Player
	player.external_input = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var start: Vector3 = player.global_position
	if str(Game.arg("set", "")) == "fix2":
		await _fix2_set(str(Game.arg("only", "")))
		print("CAPTURE_DONE n=%d" % _n)
		get_tree().quit()
		return
	if str(Game.arg("set", "")) == "mbus":
		await _mbus_set()
		print("CAPTURE_DONE n=%d" % _n)
		get_tree().quit()
		return
	if str(Game.arg("set", "")) == "arms":
		await _arms_set(str(Game.arg("only", "")))
		print("CAPTURE_DONE n=%d" % _n)
		get_tree().quit()
		return
	# G36C Hüfte / ADS
	player.set_view(0.0, -2.0)
	await _wait(1.0)
	await _shot("g36c_hip")
	player.ext.aim = true
	await _wait(0.8)
	await _shot("g36c_ads")
	player.ext.aim = false
	await _wait(0.5)
	# Feuern (Mündungsfeuer + Hülse)
	player.ext.fire = true
	await _wait(0.14)
	await _shot("g36c_fire")
	player.ext.fire = false
	await _wait(0.6)
	# Nahaufnahme: Waffen-Kamera seitlich links neben die Waffe (Spieler kurz eingefroren)
	await _closeup("g36c_closeup", Vector3(-0.42, 0.07, -0.02), Vector3(0.12, -0.17, -0.42), 38.0)
	await _closeup("g36c_sight", Vector3(0.03, 0.035, -0.17), Vector3(0.14, -0.045, -0.42), 40.0)
	await _closeup("g36c_closeup_r", Vector3(0.62, 0.02, -0.25), Vector3(0.12, -0.19, -0.44), 40.0)
	# Drop am Boden: liegende G36C (leer, wird nicht automatisch eingesammelt) vor dem Spieler
	Pickup.spawn_weapon(lv, start + Vector3(0.0, 0.0, -0.75), "g36c", 0, 0, 25.0, 35.0)
	player.set_view(0.0, -72.0)
	await _wait(0.5)
	await _shot("g36c_drop")
	# Munitionskiste (test_range: (-2.4, 0, 2.5), Front zeigt nach +X)
	player.global_position = Vector3(-0.5, start.y, 2.5)
	player.velocity = Vector3.ZERO
	player.set_view(90.0, -30.0)
	await _wait(0.6)
	await _shot("ammo_crate")
	player.global_position = start
	player.set_view(0.0, -2.0)
	await _wait(0.4)
	# Pickup-Hinweis vor der liegenden AK-74M
	player.global_position = Vector3(1.6, start.y, 0.2)
	player.velocity = Vector3.ZERO
	player.set_view(0.0, -38.0)
	await _wait(0.6)
	await _shot("pickup_hint")
	player.ext.interact = true
	await _wait(1.0)
	player.set_view(0.0, -2.0)
	await _wait(0.6)
	await _shot("ak74m_hip")
	player.ext.aim = true
	await _wait(0.8)
	await _shot("ak74m_ads")
	player.ext.aim = false
	# Panzerfaust-Kiste
	player.global_position = Vector3(5.6, start.y, 2.0)
	player.velocity = Vector3.ZERO
	player.set_view(90.0, -26.0)
	await _wait(0.6)
	await _shot("pzf_crate_hint")
	player.give_weapon("pzf3", 1, 2)
	player.global_position = start
	player.set_view(0.0, -1.0)
	await _wait(1.2)
	await _shot("pzf_hip")
	player.ext.aim = true
	await _wait(0.9)
	await _shot("pzf_ads")
	player.ext.fire = true
	await _wait(0.25)
	await _shot("pzf_rocket")
	player.ext.fire = false
	player.ext.aim = false
	await _wait(0.6)
	await _shot("pzf_reload")
	print("CAPTURE_DONE n=%d" % _n)
	get_tree().quit()

## G36-Notvisier: --set=mbus -> Hüfte, ADS (+ Visier-Report), Detail Kimme/Korn, Seitenansichten.
func _mbus_set() -> void:
	player.set_view(0.0, -2.0)
	player.ext["weapon"] = 1
	await _wait(1.3)
	await _shot("g36_hip")
	await _closeup("g36_side", Vector3(-0.42, 0.07, -0.02), Vector3(0.12, -0.17, -0.42), 38.0)
	var sf: Vector3 = player.weapon.get("_sight_f")
	var sr: Vector3 = player.weapon.get("_sight_r")
	await _closeup_piv("g36_front_l", sf + Vector3(0, -0.018, 0.008), Vector3(-0.16, 0.05, 0.03), 30.0)
	await _closeup_piv("g36_rear_l", sr + Vector3(0, -0.018, -0.008), Vector3(-0.15, 0.05, -0.06), 30.0)
	await _closeup_piv("g36_rear_r", sr + Vector3(0, -0.018, -0.008), Vector3(0.15, 0.06, 0.08), 30.0)
	await _closeup_piv("g36_side_full", (sf + sr) * 0.5 + Vector3(0, -0.07, 0), Vector3(-0.75, 0.08, 0.0), 40.0)
	player.ext.aim = true
	await _near_probe("aim_in", 40)
	await _wait(1.0)
	_sight_report("g36c")
	_sight_static("g36c")
	await _shot("g36_ads")
	var old: float = player.weapon_cam.fov
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.weapon_cam.fov = old * 0.35
	await _wait(0.15)
	_sight_report("g36c_zoom")
	await _shot("g36_ads_detail")
	player.weapon_cam.fov = old
	player.process_mode = Node.PROCESS_MODE_INHERIT
	player.ext.fire = true
	await _near_probe("ads_fire", 30)
	player.ext.fire = false
	await _wait(0.5)
	await _fire_shot("g36_ads_fire")
	await _wait(0.1)
	await _shot("g36_ads_recoil")
	player.ext.aim = false
	await _near_probe("aim_out", 40)
	await _shot("g36_ads_exit")
	await _wait(0.5)

## Erste-Person-Arme: --set=arms [--only=pistol|rifle] -> Pistole/Gewehre Hüfte, ADS, Seitenansicht, Nachladen.
func _arms_set(only: String) -> void:
	player.set_view(0.0, -2.0)
	if only == "" or only == "pistol":
		player.ext["weapon"] = 2
		await _wait(1.0)
		await _arms_weapon("pistol")
	if only == "" or only == "rifle":
		player.ext["weapon"] = 1
		await _wait(1.0)
		await _arms_weapon("g36c")
		for id in ["ak74m", "g28", "pzf3"]:
			player.give_weapon(id, 30, 60)
			await _wait(1.2)
			await _arms_weapon(id)

func _arms_weapon(id: String) -> void:
	if str(Game.arg("noarms", "")) != "":
		var an: Node3D = player.weapon.get_node_or_null("Arms") as Node3D
		if an:
			an.visible = false
	await _shot(id + "_hip")
	await _closeup(id + "_side", Vector3(-0.45, -0.05, -0.15), Vector3(0.06, -0.14, -0.3), 45.0)
	await _closeup(id + "_side_r", Vector3(0.5, -0.02, -0.2), Vector3(0.06, -0.14, -0.3), 45.0)
	player.ext.aim = true
	await _wait(0.8)
	await _shot(id + "_ads")
	player.ext.aim = false
	await _wait(0.5)
	player.weapon.ammo_mag = maxi(1, player.weapon.ammo_mag - 3)
	player.ext.reload = true
	await _wait(0.45)
	await _shot(id + "_reload_a")
	await _wait(0.45)
	await _shot(id + "_reload_b")
	await _wait(2.5)

## Fix-Runde 2: --set=fix2 [--only=id,id] -> je Waffe Hüfte/ADS, Schussmoment Hüfte/ADS und
## Visier-Projektion (Winkelabweichung Korn/Kimme von der Schussachse der Hauptkamera) als Konsolenzeile.
func _fix2_set(only: String) -> void:
	player.set_view(0.0, -2.0)
	var ids: Array = ["pistol", "pistol_sd", "g36c", "ak74m", "g28", "pzf3"]
	if only != "":
		ids = only.split(",")
	for id in ids:
		if id == "pistol":
			player.ext["weapon"] = 2
		elif id == "g36c":
			player.ext["weapon"] = 1
		else:
			player.give_weapon(id, 30, 60)
		await _wait(1.3)
		await _fix2_weapon(id)

func _fix2_weapon(id: String) -> void:
	var w: Node = player.weapon
	await _shot(id + "_hip")
	player.ext.aim = true
	await _wait(1.0)
	_sight_report(id)
	await _shot(id + "_ads")
	await _fire_shot(id + "_ads_fire")
	player.ext.aim = false
	await _wait(0.8)
	if id == "pzf3":
		player.give_weapon(id, 1, 2)
		await _wait(4.0)
	await _fire_shot(id + "_hip_fire")
	await _wait(0.6)

## Kleinster Abstand (vor der Kamera) der Kimmen-Bounding-Box ueber n Frames -> Near-Plane-Pruefung.
func _near_probe(tag: String, frames: int) -> void:
	var mi: MeshInstance3D = player.weapon.find_child("Rear", true, false) as MeshInstance3D
	var wc: Camera3D = player.weapon_cam
	var mn: float = 99.0
	for f in frames:
		await get_tree().process_frame
		if mi == null:
			continue
		var ab: AABB = mi.get_aabb()
		var xf: Transform3D = wc.global_transform.affine_inverse() * mi.global_transform
		for i in 8:
			mn = minf(mn, -(xf * ab.get_endpoint(i)).z)
	print("NEAR %s min_dist=%.4f near=%.3f" % [tag, mn, wc.near])

## Visierlinie ohne Atmen/Sway (Grundpose _base_pos/_base_rot des Pivots): reine Geometrie-Abweichung in Grad.
func _sight_static(id: String) -> void:
	var w: Node = player.weapon
	var piv: Node3D = w.get("_pivot")
	var wc: Camera3D = player.weapon_cam
	var base := Transform3D(Basis.from_euler((w.get("_base_rot") as Vector3) * (PI / 180.0)), w.get("_base_pos"))
	var xf: Transform3D = wc.global_transform.affine_inverse() * piv.get_parent_node_3d().global_transform * base
	var out: Array = []
	for p: Vector3 in [w.get("_sight_f"), w.get("_sight_r")]:
		var c: Vector3 = xf * p
		out.append(Vector2(rad_to_deg(atan2(c.x, -c.z)), rad_to_deg(atan2(c.y, -c.z))))
	print("SIGHT_STATIC %s front=%s rear=%s" % [id, out[0], out[1]])

## Winkel (Grad) eines Pivot-Punkts gegenüber der Hauptkamera-Achse (= Schussstrahl).
func _ang(p_local: Vector3) -> Vector2:
	var w: Node = player.weapon
	var piv: Node3D = w.get("_pivot")
	var wc: Camera3D = player.weapon_cam
	var c: Vector3 = wc.global_transform.affine_inverse() * (piv.global_transform * p_local)
	return Vector2(rad_to_deg(atan2(c.x, -c.z)), rad_to_deg(atan2(c.y, -c.z)))

func _sight_report(id: String) -> void:
	var w: Node = player.weapon
	var wc: Camera3D = player.weapon_cam
	var cam: Camera3D = player.camera
	var axis_err: float = rad_to_deg((-wc.global_basis.z).angle_to(-cam.global_basis.z))
	var f: Vector3 = w.get("_sight_f")
	var r: Vector3 = w.get("_sight_r")
	var m: Vector3 = (w.get("muzzle") as Node3D).position
	var vs: Vector2 = wc.get_viewport().get_visible_rect().size
	var fpx: Vector2 = wc.unproject_position((w.get("_pivot") as Node3D).global_transform * f) - vs * 0.5
	print("SIGHT %s front=%s rear=%s muzzle=%s front_px=%s camaxis_err=%.3f ads_pos=%s" % [id, _ang(f), _ang(r), _ang(m), fpx, axis_err, w.get("ads_pos")])

## Feuern und genau das Bild aufnehmen, in dem das Mündungsfeuer sichtbar ist.
func _fire_shot(name: String) -> void:
	var fx: Node = player.weapon.get("_muzzle_fx")
	await _wait(0.3)
	# Zeitlupe: die Screenshot-Rückleseung blockiert einen Frame länger als das Feuer (~2 Frames) lebt
	Engine.time_scale = 0.08
	player.ext.fire = true
	for i in 400:
		await get_tree().process_frame
		if fx != null and ((fx.get("_front") != null and fx.get("_front").visible) or (fx.get("_side") != null and fx.get("_side").visible)):
			print("FLASH %s frame=%d" % [name, i])
			break
	await _shot(name)
	if str(Game.arg("freeze", "")) != "" and fx != null:
		fx.set_process(false)
		var fr: MeshInstance3D = fx.get("_front")
		fr.visible = true
		fr.set_instance_shader_parameter("age", 0.0)
		fr.set_instance_shader_parameter("strength", 1.0)
		if fx.get("_side") != null:
			fx.get("_side").visible = true
			fx.get("_side").set_instance_shader_parameter("age", 0.0)
		print("FREEZE vis=%s gpos=%s scale=%s layers=%d" % [fr.is_visible_in_tree(), fr.global_position, fr.scale, fr.layers])
		await _shot(name + "_frz")
		fx.set_process(true)
	if str(Game.arg("burst", "")) != "":
		for k in 3:
			await _shot(name + "_%d" % (k + 1))
	player.ext.fire = false
	Engine.time_scale = 1.0

## Nahaufnahme auf einen Pivot-Punkt (Waffenraum): Kamera bei Punkt + off (Pivot-Achsen).
func _closeup_piv(name: String, target: Vector3, off: Vector3, fov: float) -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var piv: Node3D = player.weapon.get("_pivot")
	var wc: Camera3D = player.weapon_cam
	var old_fov: float = wc.fov
	var t: Vector3 = piv.global_transform * target
	var cp: Vector3 = piv.global_transform * (target + off)
	wc.look_at_from_position(cp, t, piv.global_basis.y)
	wc.fov = fov
	await _wait(0.15)
	await _shot(name)
	wc.fov = old_fov
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await _wait(0.1)

## Waffen-Kamera relativ zur Hauptkamera versetzen (cam_off) und auf look (Kameraraum) richten.
func _closeup(name: String, cam_off: Vector3, look: Vector3, fov: float) -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var cam: Camera3D = player.camera
	var wc: Camera3D = player.weapon_cam
	var cb: Transform3D = cam.global_transform
	var old_fov: float = wc.fov
	wc.look_at_from_position(cb * cam_off, cb * look, cb.basis.y)
	wc.fov = fov
	await _wait(0.15)
	await _shot(name)
	wc.fov = old_fov
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await _wait(0.1)

func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	img.save_png(ProjectSettings.globalize_path("res://").path_join(_out).path_join(name + ".png"))
	_n += 1
	print("shot ", name)
