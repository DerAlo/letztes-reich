extends Node3D
## Debug-Render der Soldaten-Posen (nicht headless):
## Godot --path . --resolution 1600x800 res://game/enemies/tools/pose_shot.tscn -- --out=C:/tmp/p.png [--faction=ru|reich] [--aim=1] [--loco=0,0] [--stance=0] [--view=front|side|q] [--reload=0.3] [--recoil=0]

var _out := ""
var _frames := 0
var _soldiers: Array = []
var _cfg := {}

func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + n + "="):
			return a.substr(n.length() + 3)
	return d

func _ready() -> void:
	_out = _arg("out", "user://pose.png")
	var root3 := Node3D.new()
	add_child(root3)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment = e
	root3.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	root3.add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.36, 0.33)
	floor.material_override = fm
	root3.add_child(floor)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(20, 1, 20)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	root3.add_child(sb)
	if _arg("drone", "") != "":
		var dr: Node3D = (load("res://game/enemies/drone.tscn") as PackedScene).instantiate()
		root3.add_child(dr)
		dr.global_position = Vector3(0, 1.3, 0)
		dr.rotation.y = PI
		dr.set_physics_process(false)
		var dc := Camera3D.new()
		root3.add_child(dc)
		dc.fov = 35
		dc.position = Vector3(0.9, 1.75, 1.2)
		dc.look_at(Vector3(0, 1.28, 0))
		dc.current = true
		return
	var paths := ["res://game/enemies/rifleman.tscn", "res://game/enemies/heavy.tscn"]
	var xs := [-0.8, 0.8]
	for i in 2:
		if _arg("only", "") != "" and int(_arg("only", "")) != i:
			continue
		var en: Enemy = (load(paths[i]) as PackedScene).instantiate()
		if _arg("faction", "") != "":
			en.set_meta("faction", _arg("faction", "ru"))
		root3.add_child(en)
		en.global_position = Vector3(xs[i], 0, 0)
		en.rotation.y = PI  # Blick nach +Z (zur Kamera)
		en.set_physics_process(false)
		_soldiers.append(en)
	var cam := Camera3D.new()
	root3.add_child(cam)
	cam.fov = 40
	match _arg("view", "front"):
		"side":
			cam.position = Vector3(5.5, 1.2, 0)
		"q":
			cam.position = Vector3(3.2, 1.5, 4.0)
		"back":
			cam.position = Vector3(0.5, 1.4, -5.0)
		"top":
			cam.position = Vector3(0.0, 4.5, 2.0)
		_:
			cam.position = Vector3(0, 1.2, 5.5)
	var foc := _arg("focus", "")
	if foc != "":
		var fx: float = xs[int(foc)]
		var la := Vector3(fx, 1.3, 0)
		var dir := (cam.position - Vector3(0, 0.95, 0)).normalized()
		cam.position = la + dir * float(_arg("dist", "2.0"))
		cam.look_at(la)
	else:
		cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true

func _process(_delta: float) -> void:
	_frames += 1
	var loco := _arg("loco", "0,0").split(",")
	for en in _soldiers:
		var sv: SoldierVisual = en._soldier
		if sv == null:
			continue
		sv.set_loco(Vector2(float(loco[0]), float(loco[1])), float(_arg("stance", "0")))
		sv.ik.aim_weight = float(_arg("aim", "1"))
		sv.ik.aim_yaw = float(_arg("yaw", "0"))
		sv.ik.aim_pitch = float(_arg("pitch", "0"))
		sv.ik.recoil = float(_arg("recoil", "0"))
		sv.ik.reload_t = float(_arg("reload", "-1"))
		if _arg("dead", "") != "" and _frames == 5:
			en._last_hit_dir = Vector3(0, 0, -1)
			en._last_hit_head = _arg("dead", "") == "head"
			en._die()
	if _frames == int(_arg("frames", "40")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		get_tree().quit()
