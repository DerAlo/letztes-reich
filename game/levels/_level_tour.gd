extends Node3D
## Kamera-Tour fuer Level-Screenshots (ohne Player/Gegner). Args: --view=a..g, --setpiece=<sekunden>
## Beispiel: godot --path . --write-movie x.png --quit-after 90 res://game/levels/_level_tour.tscn -- --view=b

var _level: Level
var _cam: Camera3D

const VIEWS := {
	"a": [Vector3(0.5, 1.7, 6.0), Vector3(0, 2.5, -60.0)],
	"b": [Vector3(-2.0, 1.7, -35.0), Vector3(1.0, 3.0, -100.0)],
	"c": [Vector3(3.0, 1.7, -50.0), Vector3(-10.0, 7.0, -72.0)],
	"d": [Vector3(1.0, 1.7, -88.0), Vector3(-2.0, 1.5, -99.0)],
	"e": [Vector3(0.0, 1.7, -130.0), Vector3(0.0, 3.0, -190.0)],
	"f": [Vector3(0.0, 40.0, 20.0), Vector3(0.0, 0.0, -80.0)],
	"g": [Vector3(-5.0, 1.7, -120.0), Vector3(6.0, 1.0, -134.0)],
}

func _ready() -> void:
	_level = (load("res://game/levels/test_range.tscn") as PackedScene).instantiate() as Level
	_level.spawn_player = false
	_level.spawn_enemies = false
	_level.ambient_artillery = false
	add_child(_level)
	_cam = Camera3D.new()
	_cam.fov = 70
	_cam.far = 700
	add_child(_cam)
	_cam.make_current()
	var v: Array = VIEWS.get(str(Game.arg("view", "a")), VIEWS["a"])
	_cam.look_at_from_position(v[0], v[1])
	if Game.arg("navtest", false):
		_navtest()
	var sp := float(Game.arg("setpiece", -1.0))
	if sp >= 0.0:
		await get_tree().create_timer(sp).timeout
		_level.trigger_setpiece()

## Navigations-Selbsttest: --navtest druckt Pfadlaenge Start->Ende und Abstand der Waypoints zum NavMesh.
func _navtest() -> void:
	for i in 30:
		await get_tree().physics_frame
	var map: RID = _level.world.get_navigation_map()
	print("NAVTEST map active=%s regions=%d region_enabled=%s" % [NavigationServer3D.map_is_active(map), NavigationServer3D.map_get_regions(map).size(), _level.world.enabled])
	var info := _level.get_level_info()
	var wps: Array = info["waypoints"]
	var worst := 0.0
	for w in wps:
		var p := Vector3(w[0], w[1], w[2])
		var q := NavigationServer3D.map_get_closest_point(map, p)
		worst = maxf(worst, p.distance_to(q))
	var a := Vector3(wps[0][0], 0.0, wps[0][2])
	var e: Array = info["end_position"]
	var path := NavigationServer3D.map_get_path(map, a, Vector3(e[0], 0.0, e[2]), true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
	print("NAVTEST waypoints=%d worst_offset=%.2f path_points=%d path_len=%.1f end=%s last=%s" % [wps.size(), worst, path.size(), length, str(e), str(path[path.size() - 1]) if path.size() > 0 else "none"])
	for i in range(1, wps.size()):
		var p0 := NavigationServer3D.map_get_closest_point(map, Vector3(wps[i - 1][0], 0.0, wps[i - 1][2]))
		var p1 := NavigationServer3D.map_get_closest_point(map, Vector3(wps[i][0], 0.0, wps[i][2]))
		var pp := NavigationServer3D.map_get_path(map, p0, p1, true)
		var l := 0.0
		for k in range(1, pp.size()):
			l += pp[k].distance_to(pp[k - 1])
		if pp.is_empty() or l > p0.distance_to(p1) * 1.6 + 2.0:
			print("NAVTEST segment %d detour/blocked: straight=%.1f path=%.1f" % [i, p0.distance_to(p1), l])
