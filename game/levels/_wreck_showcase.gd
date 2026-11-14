extends Node3D
## Vorher/Nachher-Aufnahmen der Fahrzeugwracks (Debug). Start:
##   --level=_wreck_showcase --wshots=<ordner unter captures/> [--wmode=props|intro]
## props: Pkw/Transporter/Lkw/Bus ausgebrannt (+ umgekippt) und Panzerwrack (normal/Schnee) auf Asphalt.
## intro: Nachrichten-Aufnahmen 0/1 des Intros (Kamera der Aufnahme).
## Rendert in feste 960x540 (SubViewport) und beendet sich danach selbst.

const VfxEnv = preload("res://game/vfx/vfx_env.gd")
const Props = preload("res://game/levels/level_props.gd")
const IntroNews = preload("res://game/intro/intro_news.gd")

var _vp: SubViewport
var _cam: Camera3D
var _dir: String = ""
var _shots: Array = []       ## [name, cam_pos, target] oder [name, news_node, t]
var _i: int = 0
var _wait: int = 0
var _news: Array[Node3D] = []
var _sun: DirectionalLight3D
var _sun_rot := Vector3.ZERO

func is_level_ready() -> bool:
	return true

func _ready() -> void:
	_dir = "res://captures/" + str(Game.arg("wshots", "wrecks/test"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	_vp = SubViewport.new()
	_vp.size = Vector2i(960, 540)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	VfxEnv.apply_render_quality(_vp)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 3000.0
	_vp.add_child(_cam)
	_cam.current = true
	var mode := str(Game.arg("wmode", "props"))
	if mode == "intro":
		_setup_intro()
	elif mode == "heavy":
		_setup_heavy()
	else:
		_setup_props()

func _setup_props() -> void:
	var we := WorldEnvironment.new()
	we.environment = VfxEnv.make_environment(0.004, 1.0)
	_cam.environment = we.environment
	add_child(we)
	add_child(VfxEnv.make_sun())
	var g := StaticBody3D.new()
	var gm := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(200, 1, 200)
	gm.mesh = gb
	gm.position.y = -0.5
	gm.material_override = Props.Geo.mat("asphalt_02", Color(0.6, 0.58, 0.55), 0.25)
	g.add_child(gm)
	add_child(g)
	var cv: Array = []
	Props.vehicle(self, Vector3(0, 0, 0), 30.0, "car", Color(0.4, 0.1, 0.08), true, false, cv)
	Props.vehicle(self, Vector3(6, 0, 1), -20.0, "car", Color(0.2, 0.25, 0.3), true, false, cv)
	Props.vehicle(self, Vector3(-6, 0, 2), 120.0, "car", Color(0.2, 0.2, 0.2), true, true, cv)
	Props.vehicle(self, Vector3(0, 0, -12), 80.0, "van", Color(0.7, 0.7, 0.68), true, false, cv)
	Props.vehicle(self, Vector3(9, 0, -12), 10.0, "truck", Color(0.3, 0.33, 0.25), true, false, cv)
	Props.vehicle(self, Vector3(-12, 0, -14), 6.0, "bus", Color(0.75, 0.55, 0.15), true, false, cv)
	Props.tank_wreck(self, Vector3(0, 0, -30), 160.0, cv)
	Props.tank_wreck(self, Vector3(12, 0, -30), 30.0, cv, true)
	_shots = [
		["car_front", Vector3(3.5, 1.7, 6.0), Vector3(0.5, 0.6, 0.5)],
		["car_side", Vector3(-1.5, 1.4, 7.5), Vector3(0, 0.7, 0)],
		["car_close", Vector3(2.2, 1.6, 2.6), Vector3(0, 0.7, 0)],
		["cars_group", Vector3(0, 3.0, 13.0), Vector3(0, 0.5, -2.0)],
		["van_truck_bus", Vector3(-2, 3.2, 1.0), Vector3(-1, 1.0, -13.0)],
		["tank", Vector3(6.5, 2.4, -22.0), Vector3(0, 1.2, -30.0)],
		["tank_snow", Vector3(17.0, 2.4, -23.0), Vector3(12, 1.2, -30.0)],
		["car_lit", Vector3(2.5, 1.6, -5.0), Vector3(0, 0.6, 0.5)],
		["cars_lit", Vector3(-1.0, 3.0, -9.0), Vector3(0, 0.5, 1.0)],
		["vehicles_lit", Vector3(-2.0, 3.5, -24.0), Vector3(-1, 1.0, -12.0)],
		["tank_lit", Vector3(5.0, 2.4, -38.5), Vector3(0, 1.2, -30.0)],
		["tank_snow_lit", Vector3(17.0, 2.4, -37.5), Vector3(12, 1.2, -30.0)],
	]

## heavy: Nahaufnahmen Transporter/Lkw/Bus ausgebrannt (vorn, Flanke, schraeg hinten) fuer Vorher/Nachher.
func _setup_heavy() -> void:
	var we := WorldEnvironment.new()
	we.environment = VfxEnv.make_environment(0.004, 1.0)
	_cam.environment = we.environment
	add_child(we)
	_sun = VfxEnv.make_sun()
	add_child(_sun)
	_sun_rot = _sun.rotation
	var g := StaticBody3D.new()
	var gm := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(200, 1, 200)
	gm.mesh = gb
	gm.position.y = -0.5
	gm.material_override = Props.Geo.mat("asphalt_02", Color(0.6, 0.58, 0.55), 0.25)
	g.add_child(gm)
	add_child(g)
	var cv: Array = []
	# je Fahrzeug eigener Platz entlang x, Front = +Z (yaw 0)
	Props.vehicle(self, Vector3(-30, 0, 0), 0.0, "van", Color(0.7, 0.7, 0.68), true, false, cv)
	Props.vehicle(self, Vector3(0, 0, 0), 0.0, "truck", Color(0.3, 0.33, 0.25), true, false, cv)
	Props.vehicle(self, Vector3(30, 0, 0), 0.0, "bus", Color(0.75, 0.55, 0.15), true, false, cv)
	Props.vehicle(self, Vector3(0, 0, 40), 0.0, "van", Color(0.32, 0.3, 0.28), true, true, cv)
	_shots = [
		["van_front", Vector3(-26.0, 1.6, 6.5), Vector3(-30, 0.9, 0.5)],
		["van_side", Vector3(-24.0, 1.4, -1.0), Vector3(-30, 0.9, -0.3)],
		["van_rear", Vector3(-33.5, 1.8, -6.5), Vector3(-30, 0.9, -1.0)],
		["truck_front", Vector3(4.5, 2.0, 8.0), Vector3(0, 1.2, 1.5)],
		["truck_side", Vector3(7.5, 1.7, -0.5), Vector3(0, 1.1, -0.5)],
		["truck_rear", Vector3(-4.5, 2.6, -9.0), Vector3(0, 1.1, -1.5)],
		["bus_front", Vector3(35.0, 2.0, 11.0), Vector3(30, 1.4, 3.0)],
		["bus_side", Vector3(39.0, 1.8, -2.0), Vector3(30, 1.4, -0.5)],
		["bus_rear", Vector3(25.0, 2.4, -12.0), Vector3(30, 1.4, -3.0)],
		["bus_wheel", Vector3(32.8, 0.8, 5.2), Vector3(31.1, 0.5, 4.0)],
		["van_flipped", Vector3(4.0, 1.6, 45.0), Vector3(0, 0.8, 40.0)],
		# Zusatz (4. Wert = Sonnen-Drehung um Y in Grad): Front im Licht, Tuerseite (-x), Nahaufnahmen
		["z_van_front_lit", Vector3(-26.5, 1.5, 5.5), Vector3(-30, 0.9, 0.8), 180.0],
		["z_van_door", Vector3(-35.5, 1.5, -1.0), Vector3(-30, 0.8, -0.2), 180.0],
		["z_truck_front_lit", Vector3(3.8, 2.0, 7.5), Vector3(0, 1.2, 2.0), 180.0],
		["z_truck_cab_close", Vector3(2.6, 1.9, 4.6), Vector3(0, 1.5, 2.6), 180.0],
		["z_bus_front_lit", Vector3(34.5, 2.2, 10.5), Vector3(30, 1.4, 3.5), 180.0],
		["z_bus_door", Vector3(23.0, 1.8, 3.5), Vector3(30, 1.3, 1.8), 180.0],
		["z_bus_wheel_lit", Vector3(32.6, 0.9, 6.2), Vector3(31.1, 0.45, 4.0), 180.0],
		["z_truck_wheels", Vector3(2.8, 0.9, -4.6), Vector3(1.0, 0.45, -2.2), 0.0],
	]

func _setup_intro() -> void:
	for s in [0, 1]:
		var n: Node3D = IntroNews.new()
		n.set("shot", s)
		add_child(n)
		_news.append(n)
	_shots = [["news0_t2", 0, 2.0], ["news1_t1", 1, 1.0], ["news1_t5", 1, 5.0]]

func _process(_d: float) -> void:
	if _i >= _shots.size():
		return
	var s: Array = _shots[_i]
	if _wait == 0:
		if s[1] is int:
			var n: Node3D = _news[int(s[1])]
			for o in _news:
				o.visible = o == n
			if not bool(n.get("_active")):
				n.call("activate")
			n.call("tick", float(s[2]))
			var src: Camera3D = n.get("cam")
			_cam.global_transform = src.global_transform
			_cam.fov = src.fov
			_cam.environment = n.get("env")
		else:
			_cam.look_at_from_position(s[1], s[2])
			if _sun != null:
				_sun.rotation = _sun_rot
				if s.size() > 3:
					_sun.rotation.y += deg_to_rad(float(s[3]))
	_wait += 1
	if _wait < 25:
		return
	_wait = 0
	var img := _vp.get_texture().get_image()
	var p := ProjectSettings.globalize_path("%s/%s.png" % [_dir, s[0]])
	img.save_png(p)
	print("[wreck-shots] ", p)
	_i += 1
	if _i >= _shots.size():
		get_tree().quit()
