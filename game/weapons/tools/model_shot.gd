extends SceneTree
## Debug-Render einzelner Waffen-/Ausruestungsmodelle (nicht headless):
## Godot --path . -s res://game/weapons/tools/model_shot.gd -- --model=res://...glb --out=captures/x.png
##   [--view=side|q|front|top|back] [--dist=1.5] [--fy=0.0] [--hide=Node1,Node2] [--ref=1] (1-m-Massstab)

func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + n + "="):
			return a.substr(n.length() + 3)
	return d

func _initialize() -> void:
	root.size = Vector2i(1400, 800)
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.66)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.55, 0.58)
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	w.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(10, 10)
	fl.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.34, 0.31)
	fl.material_override = fm
	w.add_child(fl)
	var m: Node3D
	match _arg("build", ""):
		"pintle":   # Bord-MG (rail_ride_fx.build_pintle_mg)
			m = Node3D.new()
			var yaw := Node3D.new()
			var pitch := Node3D.new()
			m.add_child(yaw)
			yaw.add_child(pitch)
			load("res://game/systems/rail_ride_fx.gd").build_pintle_mg(yaw, pitch)
		"m2nest":   # M2 auf Sandsackmauer wie river_crossing
			m = Node3D.new()
			var rng := RandomNumberGenerator.new()
			rng.seed = 355
			load("res://game/levels/river_props.gd").sandbag_wall(m, Vector3(0, 0, -0.47), 0.0, 1.4, 3, rng, [], false)
			load("res://game/levels/river_props.gd").sandbag_wall(m, Vector3(0, 0, 0.03), 0.0, 1.4, 3, rng, [], false)
			var m2 := GunModels.build_m2()
			m2.position = Vector3(0, 0.74, 0)
			m2.rotation_degrees.y = 180.0
			m.add_child(m2)
		_:
			m = (load(_arg("model", "")) as PackedScene).instantiate() as Node3D
	w.add_child(m)
	m.position.y = float(_arg("y", "0"))
	for h in _arg("hide", "").split(",", false):
		var n := m.find_child(h, true, false) as Node3D
		if n != null:
			n.visible = false
	if _arg("ref", "") != "":
		for i in 11:
			var b := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.01, 0.01 if i % 5 else 0.04, 0.01)
			b.mesh = bm
			b.position = Vector3(0.12, m.position.y, -1.0 + i * 0.2)
			w.add_child(b)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.fov = float(_arg("fov", "35"))
	var la := Vector3(0, m.position.y + float(_arg("fy", "0")), float(_arg("fz", "0")))
	var dir := Vector3(-1, 0.15, 0)
	match _arg("view", "side"):
		"q": dir = Vector3(-1, 0.5, -0.9)
		"q2": dir = Vector3(1, 0.4, 0.9)
		"front": dir = Vector3(0, 0.1, -1)
		"back": dir = Vector3(0, 0.25, 1)
		"top": dir = Vector3(0.001, 1, 0.001)
		"right": dir = Vector3(1, 0.15, 0)
	cam.look_at_from_position(la + dir.normalized() * float(_arg("dist", "1.5")), la)
	cam.current = true
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := _arg("out", "user://model.png")
	if out.is_relative_path():
		out = ProjectSettings.globalize_path("res://").path_join(out)
	img.save_png(out)
	print("saved ", out)
	quit()
