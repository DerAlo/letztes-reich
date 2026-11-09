extends Node3D
## Optik-Tour fuer Vorher/Nachher-Vergleiche: laedt ein Level ohne Player/Gegner, faehrt feste
## Kamerapositionen ab, misst je Ansicht die FPS (VSync aus) und speichert Screenshots.
## Start: godot --path . --resolution 1920x1080 res://game/levels/_look_tour.tscn -- --level=berlin --out=captures/look/berlin_pre
## Optional: --views=a,b,c  --settle=2.5 (Sekunden bis zur Messung)  --measure=2.0

const VIEWS := {
	"test_range": {
		"a": [Vector3(0.5, 1.7, 6.0), Vector3(0, 2.5, -60.0)],
		"b": [Vector3(-2.0, 1.7, -35.0), Vector3(1.0, 3.0, -100.0)],
		"c": [Vector3(3.0, 1.7, -50.0), Vector3(-10.0, 7.0, -72.0)],
		"d": [Vector3(5.5, 1.7, -88.0), Vector3(10.5, 4.0, -97.0)],
		"e": [Vector3(0.0, 1.7, -130.0), Vector3(0.0, 3.0, -190.0)],
		"g": [Vector3(-1.0, 1.7, -117.0), Vector3(9.0, 3.0, -134.0)],
		# Nahansichten fuer Kollisions-Debug (--debug-collisions)
		"k1": [Vector3(1.0, 1.7, -57.5), Vector3(5.2, 0.6, -62.0)],
		"k2": [Vector3(4.5, 1.6, -36.0), Vector3(4.6, 0.4, -41.0)],
		"k3": [Vector3(4.0, 7.0, -89.0), Vector3(-1.0, 0.0, -98.0)],
	},
	"berlin": {
		"a": [Vector3(0.0, 1.7, 4.0), Vector3(0, 3.0, -60.0)],
		"b": [Vector3(8.0, 1.7, -58.0), Vector3(-19.0, 7.0, -74.0)],
		"c": [Vector3(0.0, 1.7, -120.0), Vector3(0, 3.0, -180.0)],
		"d": [Vector3(9.0, 1.7, -94.0), Vector3(19.0, 4.5, -110.0)],
		"e": [Vector3(0.0, 1.7, -190.0), Vector3(-22.0, 6.0, -236.0)],
		"f": [Vector3(0.0, 1.7, -248.0), Vector3(0, 10.0, -282.0)],
	},
	"baltic_night": {
		"a": [Vector3(0.0, 1.7, 4.0), Vector3(0, 2.0, -60.0)],
		"b": [Vector3(0.0, 1.7, -80.0), Vector3(0, 3.0, -140.0)],
		"c": [Vector3(0.0, 1.7, -150.0), Vector3(0, 3.0, -210.0)],
		"d": [Vector3(2.0, 1.7, -200.0), Vector3(-16.0, 4.0, -232.0)],
		"k1": [Vector3(7.0, 1.6, -24.5), Vector3(9.5, 0.4, -30.0)],
	},
	"river_crossing": {
		"a": [Vector3(0.0, 1.7, -18.0), Vector3(4.0, 4.0, -50.0)],
		"b": [Vector3(-1.0, 1.7, -100.0), Vector3(3.0, 3.5, -121.0)],
		"c": [Vector3(0.0, 1.7, -190.0), Vector3(-8.0, 3.5, -207.5)],
	},
	"rail_yard": {
		"a": [Vector3(-6.0, 1.7, -52.0), Vector3(-16.0, 4.0, -72.0)],
		"b": [Vector3(0.0, 1.7, -150.0), Vector3(-60.0, 14.0, -360.0)],
		"c": [Vector3(1.5, 1.7, 8.0), Vector3(0.0, 3.0, -60.0)],
	},
}

var _level: Node
var _cam: Camera3D

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var lname := str(Game.arg("level", "test_range"))
	var out := str(Game.arg("out", "captures/look/" + lname))
	var settle := float(Game.arg("settle", 2.5))
	var measure := float(Game.arg("measure", 2.0))
	_level = (load("res://game/levels/%s.tscn" % lname) as PackedScene).instantiate()
	_level.set("spawn_player", false)
	_level.set("spawn_enemies", false)
	_level.set("ambient_artillery", false)
	add_child(_level)
	_cam = Camera3D.new()
	_cam.fov = 75
	_cam.far = 900
	add_child(_cam)
	_cam.make_current()
	var views: Dictionary = VIEWS.get(lname, VIEWS["test_range"])
	var pick: Array = views.keys()
	var vs := str(Game.arg("views", ""))
	if vs != "":
		pick = Array(vs.split(","))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out.get_base_dir()))
	var t0 := Time.get_ticks_msec()
	while _level.has_method("is_level_ready") and not _level.call("is_level_ready") and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	print("LOOKTOUR level=%s build_ms=%d" % [lname, Time.get_ticks_msec() - t0])
	var all_fps: Array[float] = []
	for k in pick:
		if not views.has(k):
			continue
		var v: Array = views[k]
		_cam.look_at_from_position(v[0], v[1])
		await get_tree().create_timer(settle).timeout
		var f0 := Engine.get_frames_drawn()
		var m0 := Time.get_ticks_usec()
		await get_tree().create_timer(measure).timeout
		var fps := float(Engine.get_frames_drawn() - f0) / (float(Time.get_ticks_usec() - m0) / 1000000.0)
		all_fps.append(fps)
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://%s_%s.png" % [out, k])
		img.save_png(path)
		print("LOOKTOUR view=%s fps=%.1f shot=%s" % [k, fps, path])
	var mn := 9999.0
	var sum := 0.0
	for f in all_fps:
		mn = minf(mn, f)
		sum += f
	if all_fps.size() > 0:
		print("LOOKTOUR summary level=%s min_fps=%.1f avg_fps=%.1f" % [lname, mn, sum / all_fps.size()])
	get_tree().quit()
