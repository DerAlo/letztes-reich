extends Node3D
## Showcase fuer Explosionen: Boden + Wand + Fass-Reihe, loest nach `delay` eine Explosion aus.
## Optionale User-Args (nach --): --scale=1.5 --delay=0.3 --cam=a|b|c --impacts

const VfxEnv = preload("res://game/vfx/vfx_env.gd")

@export var delay: float = 0.3
@export var blast_scale: float = 1.6

var _cam: Camera3D

func _ready() -> void:
	blast_scale = float(Game.arg("scale", blast_scale))
	delay = float(Game.arg("delay", delay))
	var we := WorldEnvironment.new()
	we.environment = VfxEnv.make_environment()
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	add_child(VfxEnv.make_sun())
	VfxEnv.apply_render_quality(get_viewport())

	var tex_mat := func(dir: String, tint: Color, scale: float) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/%s/diffuse.jpg" % dir)
		m.normal_enabled = true
		m.normal_texture = load("res://assets/textures/%s/normal.jpg" % dir)
		m.roughness_texture = load("res://assets/textures/%s/arm.jpg" % dir)
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.ao_enabled = true
		m.ao_texture = load("res://assets/textures/%s/arm.jpg" % dir)
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.albedo_color = tint
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * scale
		return m

	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var gm := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(80, 1, 80)
	gm.mesh = gb
	gm.position = Vector3(0, -0.5, 0)
	gm.material_override = tex_mat.call("asphalt_02", Color(0.75, 0.75, 0.78), 0.2)
	ground.add_child(gm)
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = Vector3(80, 1, 80)
	gc.shape = gs
	gc.position = Vector3(0, -0.5, 0)
	ground.add_child(gc)
	add_child(ground)

	var wall := StaticBody3D.new()
	var wm := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(30, 12, 1)
	wm.mesh = wb
	wm.material_override = tex_mat.call("brick_wall_02", Color(0.85, 0.8, 0.78), 0.3)
	wall.add_child(wm)
	var wc := CollisionShape3D.new()
	var ws := BoxShape3D.new()
	ws.size = wb.size
	wc.shape = ws
	wall.add_child(wc)
	wall.position = Vector3(0, 6, -9)
	if Game.arg("nowalls", false):
		wall.free()
	else:
		add_child(wall)
		var side := wall.duplicate()
		side.position = Vector3(-12, 6, 0)
		side.rotation_degrees.y = 90
		add_child(side)

	_cam = Camera3D.new()
	_cam.fov = 62
	add_child(_cam)
	_cam.make_current()
	match str(Game.arg("cam", "a")):
		"b":
			_cam.look_at_from_position(Vector3(9, 1.7, 7), Vector3(0, 3.5, 0))
		"c":
			_cam.look_at_from_position(Vector3(0, 2.0, 22), Vector3(0, 7, 0))
		"d":
			_cam.look_at_from_position(Vector3(-6, 1.5, 6), Vector3(0, 2.5, -2))
		"e":
			# Gegenlicht: Blick Richtung Sonne (Sonne kommt aus +X/-Z-Richtung, siehe VfxEnv)
			var sd := VfxEnv.sun_to_dir()
			var hd := Vector3(sd.x, 0, sd.z).normalized()
			var tgt := Vector3(0, 6, 0)
			_cam.look_at_from_position(tgt - hd * 22.0 + Vector3(-hd.z, 0, hd.x) * 6.0 + Vector3(0, -4.3, 0), tgt)
		"f":
			_cam.look_at_from_position(Vector3(2, 1.7, 30), Vector3(0, 8, -20))
		_:
			_cam.look_at_from_position(Vector3(4, 1.7, 15), Vector3(0, 4.0, 0))

	var barrel_scene: PackedScene = load("res://game/vfx/explosive_barrel.tscn") if ResourceLoader.exists("res://game/vfx/explosive_barrel.tscn") else null
	if barrel_scene and Game.arg("barrels", false):
		for i in 3:
			var b: Node3D = barrel_scene.instantiate()
			add_child(b)
			b.global_position = Vector3(-3 + i * 3.0, 0.5, -4)

	if Game.arg("fires", false):
		# Brand-Testaufbau: kleines Feuer, Fahrzeugbrand, grosse Rauchsaeule im Hintergrund
		var fs: PackedScene = load("res://game/vfx/fire.tscn")
		var specs := [[Vector3(-3, 0, -2), 0.8, 1.2], [Vector3(3, 0, -3), 1.2, 2.0], [Vector3(6, 0, -40), 2.6, 3.5]]
		for sp in specs:
			var f: Node3D = fs.instantiate()
			f.set("size", sp[1])
			f.set("smoke_height", sp[2])
			f.set("light_enabled", sp[1] < 2.0)
			add_child(f)
			f.global_position = sp[0]
	if Game.arg("fps", false):
		_fps_overlay()
	if Game.arg("fires", false) or Game.arg("noblast", false):
		return
	await get_tree().create_timer(delay).timeout
	if Game.arg("barrels", false):
		get_tree().get_first_node_in_group("damageable").call("take_damage", 100.0, null, Vector3.ZERO, Vector3.UP)
	elif Game.arg("impacts", false):
		VFX.spawn_impact(Vector3(2, 0, 2), Vector3.UP, "concrete")
		VFX.spawn_impact(Vector3(-2, 4, -8.5), Vector3.BACK, "metal")
		VFX.spawn_blood(Vector3(0, 1.2, 0), Vector3.BACK)
	else:
		Combat.explode(Vector3(0, 0.5, 0), 8.0, 0.0, null, blast_scale)

func _fps_overlay() -> void:
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(func() -> void:
		print("FPS %d  draw_calls=%d  prim=%d" % [Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)]))
	add_child(t)
