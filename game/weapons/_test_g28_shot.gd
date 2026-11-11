extends Node3D
## Test: rendert das G28-Modell aus mehreren Blickwinkeln nach captures/g28_model/.
## godot --path . res://game/weapons/_test_g28_shot.tscn  (nicht headless)

const OUT: String = "res://captures/g28_model/"

var cam: Camera3D

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_window().size = Vector2i(1600, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.43, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.56, 0.6)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.5
	add_child(fill)
	var model: Node3D = load("res://game/weapons/g28_model.gd").call("build")
	add_child(model)
	var tris: int = 0
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var arr: Array = m.surface_get_arrays(s)
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	print("[g28] tris=", tris, " meta=", model.get_meta_list())
	for k in model.get_meta_list():
		print("[g28] ", k, " = ", model.get_meta(k))
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.01
	add_child(cam)
	var c := Vector3(0, 0.02, -0.12)
	await _shot("side", c + Vector3(1.25, 0.05, 0), c, 40.0)
	await _shot("front34", c + Vector3(0.75, 0.3, -0.85), c, 40.0)
	await _shot("scope_close", Vector3(0.16, 0.2, 0.26), Vector3(0, 0.095, -0.05), 40.0)
	await _shot("shooter", Vector3(0.05, 0.14, 0.42), Vector3(0, 0.08, -0.3), 50.0)
	await _shot("left", c + Vector3(-1.25, 0.05, 0), c, 40.0)
	await _shot("lower_close", Vector3(0.35, -0.02, 0.05), Vector3(0, -0.02, -0.04), 40.0)
	await _shot("muzzle_close", Vector3(0.15, 0.08, -0.82), Vector3(0, 0.03, -0.58), 40.0)
	await _shot("hg_close", Vector3(0.2, 0.06, -0.2), Vector3(0, 0.03, -0.33), 40.0)
	await _shot("stock_close", Vector3(0.4, 0.05, 0.3), Vector3(0, 0.0, 0.25), 40.0)
	get_tree().quit()

func _shot(name: String, from: Vector3, at: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.look_at_from_position(from, at, Vector3.UP)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("[g28] saved ", name)
