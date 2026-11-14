extends SceneTree
## Einmal-Portrait einer VIP-Figur. Nutzung: -s res://tools/_portrait.gd -- --kind=riedhammer --out=PATH
## Optional: --pose=up (Haende hoch), --views=full,face,q34,q34full,side,hand,handside (Standard: alle)
## --props=nade|case|pistol: Requisite wie im Level an hands[1] (inkl. Armpose) zur Kontrolle
func _initialize() -> void:
	var kind := "riedhammer"
	var out := "user://portrait.png"
	var pose := ""
	var views := "full,face,q34,q34full,side"
	var props := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kind="): kind = a.substr(7)
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--pose="): pose = a.substr(7)
		if a.begins_with("--views="): views = a.substr(8)
		if a.begins_with("--props="): props = a.substr(8)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.62)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, -140, 0)
	fill.light_energy = 0.5
	root.add_child(fill)
	var VM = load("res://game/characters/vip_models.gd")
	var t0 := Time.get_ticks_usec()
	var fig: Dictionary = VM.build(root, kind, Vector3.ZERO, 180.0, {})
	print("[portrait] build ms: ", (Time.get_ticks_usec() - t0) / 1000.0)
	if pose == "up":
		for a: Node3D in fig["arms"]:
			a.rotation.x = PI * 0.92
	var hand: Node3D = (fig["hands"] as Array)[1]
	var arm_r: Node3D = (fig["arms"] as Array)[1]
	if props == "nade":
		# wie bunker.gd (_riedhammer_finale): Oberarm halb vor, Ellbogen gebeugt
		arm_r.rotation.x = PI * 0.3
		var drv := (fig["root"] as Node).get_node_or_null("VipRig")
		if drv != null:
			drv.call("_pose_extra", "lowerarm_r", 1.15)
		var nade := Node3D.new()
		hand.add_child(nade)
		nade.position = Vector3(0.0, 0.01, -0.01)
		load("res://game/levels/bunker.gd")._nade_model(nade)   # dasselbe Modell wie im Finale
	elif props == "pistol":
		arm_r.rotation_degrees.x = 88.0
		var gp := _box(Vector3(0.028, 0.04, 0.11), Color(0.05, 0.05, 0.05), Vector3(0, 0.005, 0.03))
		gp.rotation_degrees = Vector3(-15, 0, 0)
		hand.add_child(gp)
		hand.add_child(_box(Vector3(0.03, 0.17, 0.036), Color(0.05, 0.05, 0.05), Vector3(0, -0.045, -0.035)))
		hand.add_child(_box(Vector3(0.012, 0.012, 0.012), Color(1, 0.2, 0), Vector3(0, -0.135, -0.035)))
	elif props == "case":
		var c := Node3D.new()
		hand.add_child(c)
		c.position = Vector3(0.02, -0.135, 0.045)
		c.add_child(_box(Vector3(0.1, 0.32, 0.45), Color(0.25, 0.16, 0.08), Vector3.ZERO))
		c.add_child(_box(Vector3(0.12, 0.03, 0.12), Color(0.7, 0.55, 0.2), Vector3(0, 0.17, 0)))
	await process_frame
	var hp := hand.global_position
	var all := {
		"hand": [hp + Vector3(-0.35, 0.12, 0.45), hp],
		"handside": [hp + Vector3(-0.6, 0.05, 0.0), hp],
		"handin": [hp + Vector3(0.5, 0.25, 0.25), hp],
		"handtop": [hp + Vector3(-0.05, 0.6, 0.05), hp],
		"full": [Vector3(0, 1.0, 3.2), Vector3(0, 0.95, 0)],
		"face": [Vector3(0.25, 1.72, 0.95), Vector3(0, 1.7, 0)],
		"q34": [Vector3(-0.62, 1.74, 0.68), Vector3(0, 1.7, 0)],
		"q34full": [Vector3(-2.1, 1.15, 2.4), Vector3(0, 0.95, 0)],
		"side": [Vector3(-0.95, 1.71, 0.02), Vector3(0, 1.7, 0)],
	}
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	for v: String in views.split(","):
		if not all.has(v):
			continue
		var c: Array = all[v]
		await process_frame
		cam.look_at_from_position(c[0], c[1])
		for i in 20:
			await process_frame
		var img := get_root().get_texture().get_image()
		img.save_png(out.replace(".png", "_%s.png" % v))
		print("[portrait] ", v)
	quit()


func _box(size: Vector3, col: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	bm.material = m
	mi.mesh = bm
	mi.position = pos
	return mi
