extends Node3D
## Debug-Render gepanzerter Gegner (nicht headless):
## Godot --path . --resolution 1600x900 res://game/enemies/_test_armor_shot.tscn -- --out=C:/tmp/a.png
##   [--units=armored:ru,armored:reich,juggernaut:ru] [--view=front|q|side|back] [--focus=0] [--dist=2.2]
##   [--shots=0] (Treffer auf Einheit focus vor dem Foto) [--loco=0,0] [--aim=1] [--frames=40] [--dead=]

var _out := ""
var _frames := 0
var _units: Array = []
var _cam: Camera3D = null

func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + n + "="):
			return a.substr(n.length() + 3)
	return d

func _ready() -> void:
	_out = _arg("out", "user://armor.png")
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.47, 0.6)
	sm.sky_horizon_color = Color(0.68, 0.7, 0.72)
	sm.ground_horizon_color = Color(0.5, 0.48, 0.45)
	sm.ground_bottom_color = Color(0.2, 0.19, 0.17)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, float(_arg("sun", "35")), 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.29, 0.26)
	fm.roughness = 0.95
	floor.material_override = fm
	add_child(floor)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(30, 1, 30)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	var specs := _arg("units", "armored:ru,armored:reich").split(",")
	var n := specs.size()
	var spacing := float(_arg("spacing", "1.3"))
	for i in n:
		var parts := specs[i].split(":")
		var en: Enemy = (load("res://game/enemies/%s.tscn" % parts[0]) as PackedScene).instantiate()
		en.set_meta("faction", parts[1] if parts.size() > 1 else "ru")
		add_child(en)
		en.global_position = Vector3((float(i) - (n - 1) * 0.5) * spacing, 0, 0)
		en.rotation.y = PI
		en.set_physics_process(false)
		_units.append(en)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = float(_arg("fov", "38"))
	var dir := Vector3(0, 0.05, 1)
	match _arg("view", "front"):
		"q": dir = Vector3(0.7, 0.15, 1.0)
		"q2": dir = Vector3(-0.8, 0.1, 0.9)
		"side": dir = Vector3(1, 0.05, 0)
		"back": dir = Vector3(0.35, 0.12, -1)
		"low": dir = Vector3(0.3, -0.15, 1)
	dir = dir.normalized()
	var foc := _arg("focus", "")
	var la := Vector3(0, 1.0, 0)
	var dist := float(_arg("dist", str(2.5 + n * 1.1)))
	if foc != "":
		la = (_units[int(foc)] as Node3D).global_position + Vector3(0, float(_arg("fy", "1.25")), 0)
	_cam.position = la + dir * dist
	_cam.look_at(la)
	_cam.current = true

func _shoot_unit(en: Node3D, k: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + k
	var tgt := en.global_position + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(1.05, 1.45), 0)
	if _arg("aim_head", "") != "" and k % 3 == 2:
		tgt = en.global_position + Vector3(0.0, 1.66 * float(en.get("body_scale")), 0.0)
	var from := _cam.global_position
	var d := (tgt - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + d * 30.0, 1 | 4)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		return
	var c: Node = r.collider
	while c != null and not c.has_method("take_damage"):
		c = c.get_parent()
	if c == null:
		return
	var tn: Node = c
	if c.has_method("get_enemy"):
		tn = c.call("get_enemy")
	if tn.has_method("set_shot_dir"):
		tn.call("set_shot_dir", d)
	var dmg := 34.0 * (1.4 if bool(r.collider.get_meta("headshot", false)) else 1.0)
	c.call("take_damage", dmg, null, r.position, r.normal)
	print("shot %d -> %s zone=%s dealt=%.1f hp=%.1f" % [k, tn.name, str(tn.get("last_zone")), float(tn.get("last_dealt")), float(tn.get("health"))])

func _process(_delta: float) -> void:
	_frames += 1
	var loco := _arg("loco", "0,0").split(",")
	for en: Enemy in _units:
		var sv: SoldierVisual = en._soldier
		if sv == null or en.state == Enemy.State.DEAD:
			continue
		sv.set_loco(Vector2(float(loco[0]), float(loco[1])), float(_arg("stance", "0")))
		sv.ik.aim_weight = float(_arg("aim", "1"))
		sv.ik.aim_yaw = 0.0
		sv.ik.aim_pitch = 0.0
	var shots := int(_arg("shots", "0"))
	if shots > 0 and _frames >= 10 and _frames < 10 + shots:
		_shoot_unit(_units[int(_arg("focus", "0"))], _frames - 10)
	if _arg("dead", "") != "" and _frames == 12:
		for en: Enemy in _units:
			en._last_hit_dir = Vector3(0, 0, -1)
			en._die()
	if _frames == int(_arg("frames", "40")):
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("saved ", _out)
		get_tree().quit()
