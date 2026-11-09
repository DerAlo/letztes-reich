extends Node3D
## Standbild-Render der Fahrzeugmodelle (nicht headless), fuer Vorher/Nachher-Vergleiche.
## Godot --path . --resolution 1600x900 res://game/vehicles/tools/model_shot.tscn -- --out=C:/tmp/t.png
##   --what=tank|heli  --faction=ru|reich|eu  --view=q|side|front|back|top|close  [--frames=30]

const VfxEnv = preload("res://game/vfx/vfx_env.gd")

var _out: String = ""
var _frames: int = 0
var _max_frames: int = 30

func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + n + "="):
			return a.substr(n.length() + 3)
	return d

func _ready() -> void:
	_out = _arg("out", "user://model.png")
	_max_frames = int(_arg("frames", "30"))
	var we := WorldEnvironment.new()
	we.environment = VfxEnv.make_environment(0.002, 1.0)
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	add_child(VfxEnv.make_sun())
	VfxEnv.apply_render_quality(get_viewport())
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.38, 0.36, 0.32)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	var what := _arg("what", "tank")
	var faction := _arg("faction", "ru")
	var path := "res://game/vehicles/%s.tscn" % ("helicopter" if what == "heli" else "tank")
	var v: Node3D = (load(path) as PackedScene).instantiate()
	v.set_meta("faction", faction)
	v.set("faction", faction)
	if what == "heli":
		v.set("downwash", false)
	add_child(v)
	var center := Vector3(0, 1.4, 0)
	var dist := 11.0
	if what == "heli":
		v.global_position = Vector3(0, 3.5, 0)
		v.set_physics_process(false)
		center = Vector3(0, 3.8, 1.5)
		dist = 17.0
	var dir := Vector3(0.75, 0.32, -0.6)
	match _arg("view", "q"):
		"side":
			dir = Vector3(1.0, 0.12, 0.0)
		"front":
			dir = Vector3(0.15, 0.2, -1.0)
		"back":
			dir = Vector3(-0.6, 0.35, 0.8)
		"top":
			dir = Vector3(0.3, 1.0, 0.25)
		"close":
			dir = Vector3(0.9, 0.25, -0.35)
			dist *= 0.5
	var cam := Camera3D.new()
	cam.fov = 45
	add_child(cam)
	cam.position = center + dir.normalized() * dist
	cam.look_at(center)
	cam.current = true

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == _max_frames:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		get_tree().quit()
