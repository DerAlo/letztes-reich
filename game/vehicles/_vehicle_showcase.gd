extends Node3D
## Showcase fuer Fahrzeuge & Wetter. Start: --level=../vehicles/_vehicle_showcase
## User-Args: --show=all|heli|tank|jet|charge|rain|wreck  --cam=a|b|c|d  --kill=<s> (Heli abschiessen)
##            --tankkill=<s>  --night  --norain  --fps (FPS-Ausgabe jede Sekunde)  --quit=<s>

const VfxEnv = preload("res://game/vfx/vfx_env.gd")
const VF = preload("res://game/vehicles/vehicle_fx.gd")

var _cam: Camera3D
var _target: Node3D
var _t: float = 0.0
var _fps_acc: float = 0.0
var _fps_samples: Array[float] = []
var _show: String = "all"
var _heli: Node
var _tank: Node
var _cam_mode: String = "a"

class Dummy extends Node3D:
	func take_damage(_a: float, _s: Node, _p: Vector3, _n: Vector3) -> void:
		pass
	func is_alive() -> bool:
		return true
	func add_trauma(_a: float) -> void:
		pass

func _ready() -> void:
	_show = str(Game.arg("show", "all"))
	_cam_mode = str(Game.arg("cam", "a"))
	var night := bool(Game.arg("night", false))
	var we := WorldEnvironment.new()
	we.environment = VfxEnv.make_environment(0.006, 0.12 if night else 1.0)
	if night:
		we.environment.ambient_light_energy = 0.25
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	var sun := VfxEnv.make_sun()
	if night:
		sun.light_energy = 0.15
		sun.light_color = Color(0.6, 0.7, 1.0)
	add_child(sun)
	VfxEnv.apply_render_quality(get_viewport())
	_build_ground()
	_target = Dummy.new()
	_target.name = "ShowcaseTarget"
	_target.add_to_group("player")
	add_child(_target)
	_target.global_position = Vector3(0, 0, 0)
	VF.mesh_node(_target, VF.capsule(0.35, 1.8), VF.mat("dummy", Color(0.3, 0.35, 0.3)), Vector3(0, 0.9, 0))
	_cam = Camera3D.new()
	_cam.fov = 65
	_cam.far = 4000.0
	add_child(_cam)
	_cam.make_current()
	_setup_show()

func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	ground.set_meta("surface", "dirt")
	var gm := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(400, 1, 400)
	gm.mesh = gb
	gm.position = Vector3(0, -0.5, 0)
	var m := StandardMaterial3D.new()
	var dir := "res://assets/textures/asphalt_02/"
	if ResourceLoader.exists(dir + "diffuse.jpg"):
		m.albedo_texture = load(dir + "diffuse.jpg")
		m.normal_enabled = true
		m.normal_texture = load(dir + "normal.jpg")
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * 0.2
	m.albedo_color = Color(0.55, 0.52, 0.46)
	gm.material_override = m
	ground.add_child(gm)
	var gc := CollisionShape3D.new()
	var gs := BoxShape3D.new()
	gs.size = gb.size
	gc.shape = gs
	gc.position = Vector3(0, -0.5, 0)
	ground.add_child(gc)
	add_child(ground)
	# Wasserflaeche (Downwash-Spray)
	var water := StaticBody3D.new()
	water.set_meta("surface", "water")
	var wm := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(40, 0.1, 40)
	wm.mesh = wb
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.05, 0.08, 0.1)
	wmat.roughness = 0.05
	wmat.metallic = 0.3
	wm.material_override = wmat
	water.add_child(wm)
	var wc := CollisionShape3D.new()
	var ws := BoxShape3D.new()
	ws.size = wb.size
	wc.shape = ws
	water.add_child(wc)
	add_child(water)
	water.position = Vector3(-50, 0.02, -40)
	# ein paar Deckungsbloecke als Massstab
	for i in 6:
		var b := StaticBody3D.new()
		var bm := MeshInstance3D.new()
		var bx := BoxMesh.new()
		bx.size = Vector3(2.5, 1.2, 0.8)
		bm.mesh = bx
		bm.material_override = VF.mat("block", Color(0.5, 0.5, 0.48), 0.9, 0.0)
		b.add_child(bm)
		var bc := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bx.size
		bc.shape = bs
		b.add_child(bc)
		add_child(b)
		b.position = Vector3(-12 + i * 5, 0.6, 6 + (i % 2) * 3)

func _setup_show() -> void:
	var all := _show == "all"
	if all or _show == "heli" or _show == "wreck":
		var heli := (load("res://game/vehicles/helicopter.tscn") as PackedScene).instantiate()
		heli.set("searchlight", true)
		add_child(heli)
		heli.global_position = Vector3(-30, 22, -45)
		var pts: Array[Vector3] = [Vector3(-40, 14, -40), Vector3(-10, 18, -30)]
		heli.call("fly_path", pts, 14.0, false)
		heli.call("attack", true)
		_heli = heli
		var kill := float(Game.arg("kill", 6.0 if _show == "wreck" else -1.0))
		if kill > 0.0:
			get_tree().create_timer(kill, false).timeout.connect(func() -> void:
				if is_instance_valid(heli):
					heli.call("take_damage", 9999.0, null, (heli as Node3D).global_position, Vector3.UP))
	if all or _show == "tank" or _show == "charge":
		var tank := (load("res://game/vehicles/tank.tscn") as PackedScene).instantiate()
		add_child(tank)
		tank.global_position = Vector3(25, 0, -35)
		var pts: Array[Vector3] = [Vector3(20, 0, -25), Vector3(12, 0, -18)]
		tank.call("drive_path", pts, 4.0)
		tank.call("set_target", _target)
		_tank = tank
		if _show == "charge":
			var ch := (load("res://game/vehicles/demo_charge.tscn") as PackedScene).instantiate()
			ch.set("target", tank)
			tank.add_child(ch)
			(ch as Node3D).position = Vector3(1.8, 1.0, 0)
			get_tree().create_timer(2.0, false).timeout.connect(func() -> void: ch.call("plant"))
		var tk := float(Game.arg("tankkill", -1.0))
		if tk > 0.0:
			get_tree().create_timer(tk, false).timeout.connect(func() -> void:
				if is_instance_valid(tank):
					tank.call("destroy"))
	if all or _show == "jet":
		get_tree().create_timer(3.0 if all else 0.5, false).timeout.connect(func() -> void:
			var jet := (load("res://game/vehicles/jet_flyby.tscn") as PackedScene).instantiate()
			add_child(jet)
			var bombs: Array[Vector3] = [Vector3(30, 0, -60), Vector3(38, 0, -70), Vector3(46, 0, -80)]
			jet.call("run", Vector3(-600, 45, 120), Vector3(600, 55, -260), bombs))
	if (all or _show == "rain") and not Game.arg("norain", false):
		var w := Weather.new()
		w.rain_strength = 0.85
		add_child(w)
		if _show == "rain":
			get_tree().create_timer(1.0, false).timeout.connect(func() -> void: w.strike(600.0))

func _process(delta: float) -> void:
	_t += delta
	match _cam_mode:
		"b":  # nah am Panzer
			_cam.look_at_from_position(Vector3(4, 2.0, -12), Vector3(18, 1.5, -24))
		"c":  # Heli von unten
			var hp := (_heli as Node3D).global_position if is_instance_valid(_heli) else Vector3(-20, 15, -35)
			_cam.look_at_from_position(Vector3(-6, 1.7, -10), hp)
		"e":  # Panzer-Nahaufnahme (schraeg vorne)
			if is_instance_valid(_tank):
				var tp := (_tank as Node3D).global_position
				var tb := (_tank as Node3D).global_transform.basis
				_cam.look_at_from_position(tp + tb * Vector3(7.5, 3.2, -8.5), tp + Vector3.UP * 1.3)
		"f":  # Heli-Nahaufnahme
			if is_instance_valid(_heli):
				var hp2 := (_heli as Node3D).global_position
				_cam.look_at_from_position(hp2 + Vector3(13, -3, 12), hp2)
		"d":  # Jet-Bahn
			_cam.look_at_from_position(Vector3(0, 1.8, 10), Vector3(20, 25, -60))
		_:
			_cam.look_at_from_position(Vector3(6, 3.0, 14), Vector3(-2, 7, -30))
	if Game.arg("fps", false):
		_fps_acc += delta
		if _fps_acc >= 1.0:
			_fps_acc = 0.0
			var f := Engine.get_frames_per_second()
			_fps_samples.append(f)
			print("[showcase] t=%.0f fps=%d draw=%d prims=%d" % [_t, f,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	var q := float(Game.arg("quit", -1.0))
	if q > 0.0 and _t >= q:
		if not _fps_samples.is_empty():
			var s := 0.0
			var mn := 1e9
			for f in _fps_samples.slice(2):
				s += f
				mn = minf(mn, f)
			var n := maxi(_fps_samples.size() - 2, 1)
			print("[showcase] avg_fps=%.1f min_fps=%.0f" % [s / n, mn])
		get_tree().quit()
