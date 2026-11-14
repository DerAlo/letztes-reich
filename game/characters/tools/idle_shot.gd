extends Node3D
## Debug-Render des Idle-Lebens (nicht headless): VIP-Figuren (VipRig), stehende Zivilfigur und sitzende Geisel
## (civ_figure/civ_idle), Soldat (Idle-Animation). Speichert Bilder zu mehreren Zeitpunkten -> Bewegung vergleichen.
## Godot --audio-driver Dummy --path . --resolution 1600x900 res://game/characters/tools/idle_shot.tscn -- --out=C:/tmp/idle [--times=1,2.5,4] [--view=close]

const VIP = preload("res://game/characters/vip_models.gd")
const CivFigure = preload("res://game/characters/civ_figure.gd")
const Hostage = preload("res://game/systems/breach_hostage.gd")

var _out := ""
var _times: Array[float] = []
var _t := 0.0
var _shot := 0

func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + n + "="):
			return a.substr(n.length() + 3)
	return d

func _ready() -> void:
	_out = _arg("out", "user://idle")
	for s in _arg("times", "1.0,2.4,3.8").split(","):
		_times.append(float(s))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.36, 0.33)
	floor.material_override = fm
	add_child(floor)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(30, 1, 30)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	# Figuren (Blick zur Kamera = +Z -> yaw 180)
	VIP.build(self, "weber", Vector3(-2.4, 0, 0), 180.0)
	VIP.build(self, "graumantel", Vector3(-1.2, 0, 0), 180.0)
	CivFigure.stand(self, "voss", Vector3(0.0, 0, 0), 180.0)
	var h := Hostage.new()
	h.pose = "seat"
	h.variant = "praesidentin"
	add_child(h)
	h.position = Vector3(1.2, 0, 0)
	h.rotation_degrees.y = 180.0
	var en: Node3D = (load("res://game/enemies/rifleman.tscn") as PackedScene).instantiate()
	add_child(en)
	en.global_position = Vector3(2.4, 0, 0)
	en.rotation.y = PI
	en.set_physics_process(false)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	if _arg("view", "") == "close":
		var fx := float(_arg("x", "0"))
		cam.fov = 22
		cam.position = Vector3(fx, 1.45, 2.6)
		cam.look_at(Vector3(fx, 1.25, 0))
	else:
		cam.position = Vector3(0, 1.3, 6.5)
		cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true

func _process(dt: float) -> void:
	_t += dt
	if _shot < _times.size() and _t >= _times[_shot]:
		var img := get_viewport().get_texture().get_image()
		var p := "%s_%d.png" % [_out, _shot]
		img.save_png(p)
		print("saved ", p)
		_shot += 1
		if _shot >= _times.size():
			get_tree().quit()
