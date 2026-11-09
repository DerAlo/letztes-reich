extends SceneTree
## Debug: rendert ein Modell in mehreren Animationen nebeneinander.
## godot --path . -s res://game/enemies/tools/anim_sheet.gd -- --model=res://... --anims=a,b,c --t=0.5 --out=path.png [--side]

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
		if a == "--" + k:
			return "1"
	return d

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var s := _find_ap(c)
		if s:
			return s
	return null

func _init() -> void:
	var model := _arg("model", "res://assets/characters/soldier/swat.glb")
	var anims := _arg("anims", "").split(",", false)
	var tt := float(_arg("t", "0.5"))
	var side := _arg("side", "") != ""
	var scene: PackedScene = load(model)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.65)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	root.add_child(sun)
	var n := anims.size()
	for i in n:
		var inst := scene.instantiate() as Node3D
		root.add_child(inst)
		inst.position = Vector3((i - (n - 1) * 0.5) * 1.3, 0, 0)
		inst.rotation_degrees.y = 90.0 if side else 0.0
		var ap := _find_ap(inst)
		var nm := anims[i]
		var full := nm
		for a in ap.get_animation_list():
			if a.ends_with(nm) and (a == nm or a.ends_with("|" + nm)):
				full = a
		ap.play(full)
		ap.seek(ap.get_animation(full).length * tt, true)
		ap.pause()
		var lbl := Label3D.new()
		lbl.text = nm
		lbl.font_size = 24
		lbl.position = Vector3(0, 2.1, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		inst.add_child(lbl)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.1, maxf(3.0, n * 0.75))
	cam.fov = 50
	cam.make_current()
	for k in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(_arg("out", "user://sheet.png"))
	print("saved")
	quit()
