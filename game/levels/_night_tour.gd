extends Node3D
## Kamera-Tour fuer baltic_night (ohne Player). Args: --view=<name>, --setpiece=<s>, --tower=<s>,
## --enemies (Gegner von Welle 0..3 spawnen, eingefroren), --navtest, --flare (sofort Leuchtkugel).
## Beispiel: godot --path . --write-movie x.png --quit-after 240 res://game/levels/_night_tour.tscn -- --view=a

var _level: Node3D
var _cam: Camera3D

const VIEWS := {
	"a": [Vector3(2.5, 0.85, 0.3), Vector3(1.0, 1.5, -40.0)],      # aus dem Graben
	"b": [Vector3(-10.0, 2.2, -12.0), Vector3(-2.0, 1.0, -40.0)],  # Feld, Draht, Panzer
	"c": [Vector3(0.0, 1.7, -66.0), Vector3(0.0, 2.0, -100.0)],    # Waldweg
	"d": [Vector3(1.5, 1.7, -112.0), Vector3(-1.0, 2.0, -150.0)],  # Dorfgasse
	"e": [Vector3(2.0, 1.7, -124.0), Vector3(-8.0, 3.0, -142.0)],  # Sperrfeuer-Haeuser
	"f": [Vector3(2.0, 1.7, -172.0), Vector3(-2.0, 3.0, -200.0)],  # Dorfplatz
	"g": [Vector3(4.0, 1.7, -180.0), Vector3(-14.0, 6.0, -191.0)], # Wasserturm
	"h": [Vector3(0.5, 1.7, -210.0), Vector3(0.0, 2.0, -232.0)],   # Bahnuebergang
	"i": [Vector3(0.0, 55.0, 25.0), Vector3(0.0, 0.0, -90.0)],     # Uebersicht
	"j": [Vector3(0.0, 1.7, -40.0), Vector3(0.0, 2.0, -58.0)],     # Feld, Gegnerstellungen
}

func _ready() -> void:
	_level = (load("res://game/levels/baltic_night.tscn") as PackedScene).instantiate() as Node3D
	_level.set("spawn_player", false)
	_level.set("spawn_enemies", Game.arg("enemies", false) != false)
	_level.set("ambient_artillery", false)
	add_child(_level)
	_cam = Camera3D.new()
	_cam.fov = 75
	_cam.far = 700
	add_child(_cam)
	_cam.make_current()
	var v: Array = VIEWS.get(str(Game.arg("view", "a")), VIEWS["a"])
	_cam.look_at_from_position(v[0], v[1])
	if Game.arg("navtest", false):
		_navtest()
	if Game.arg("enemies", false):
		_spawn_all()
	if Game.arg("flare", false):
		await get_tree().create_timer(0.5).timeout
		var fx: Node = _level.get("fx")
		fx.call("spawn_flare", Vector3(v[0].x + 6.0, 34.0, v[0].z - 22.0), str(Game.arg("flare")) == "red")
	var sp := float(Game.arg("setpiece", -1.0))
	if sp >= 0.0:
		await get_tree().create_timer(sp).timeout
		_level.call("trigger_setpiece")
	var tw := float(Game.arg("tower", -1.0))
	if tw >= 0.0:
		await get_tree().create_timer(tw).timeout
		_level.call("trigger_tower")

func _spawn_all() -> void:
	while not _level.call("is_level_ready"):
		await get_tree().physics_frame
	for i in 4:
		_level.call("spawn_wave", i)

## Navigations-Selbsttest wie in _level_tour.gd.
func _navtest() -> void:
	for i in 30:
		await get_tree().physics_frame
	var world: NavigationRegion3D = _level.get("world")
	var map: RID = world.get_navigation_map()
	var info: Dictionary = _level.call("get_level_info")
	var wps: Array = info["waypoints"]
	var worst := 0.0
	for w in wps:
		var p := Vector3(w[0], w[1], w[2])
		worst = maxf(worst, p.distance_to(NavigationServer3D.map_get_closest_point(map, p)))
	var a := NavigationServer3D.map_get_closest_point(map, Vector3(wps[0][0], wps[0][1], wps[0][2]))
	var e: Array = info["end_position"]
	var ep := NavigationServer3D.map_get_closest_point(map, Vector3(e[0], 0.0, e[2]))
	var path := NavigationServer3D.map_get_path(map, a, ep, true)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i].distance_to(path[i - 1])
	print("NAVTEST waypoints=%d worst_offset=%.2f path_points=%d path_len=%.1f end=%s last=%s" % [wps.size(), worst, path.size(), length, str(e), str(path[path.size() - 1]) if path.size() > 0 else "none"])
	for i in range(1, wps.size()):
		var p0 := NavigationServer3D.map_get_closest_point(map, Vector3(wps[i - 1][0], wps[i - 1][1], wps[i - 1][2]))
		var p1 := NavigationServer3D.map_get_closest_point(map, Vector3(wps[i][0], wps[i][1], wps[i][2]))
		var pp := NavigationServer3D.map_get_path(map, p0, p1, true)
		var l := 0.0
		for k in range(1, pp.size()):
			l += pp[k].distance_to(pp[k - 1])
		if pp.is_empty() or l > p0.distance_to(p1) * 1.4 + 1.5:
			print("NAVTEST segment %d detour/blocked: straight=%.1f path=%.1f" % [i, p0.distance_to(p1), l])
	# Gerade Linien zwischen Waypoints per Physik-Shapecast pruefen (Bot laeuft gerade)
	var space := get_world_3d().direct_space_state
	var sh := SphereShape3D.new()
	sh.radius = 0.42
	for i in range(1, wps.size()):
		var q0 := Vector3(wps[i - 1][0], wps[i - 1][1] + 0.9, wps[i - 1][2])
		var q1 := Vector3(wps[i][0], wps[i][1] + 0.9, wps[i][2])
		var prm := PhysicsShapeQueryParameters3D.new()
		prm.shape = sh
		prm.transform = Transform3D(Basis.IDENTITY, q0)
		prm.motion = q1 - q0
		prm.collision_mask = 1
		var r := space.cast_motion(prm)
		if r.size() > 0 and r[0] < 0.999:
			print("NAVTEST line %d blocked at %.0f%% (%s -> %s)" % [i, r[0] * 100.0, str(q0), str(q1)])
	# Deckungspunkte: Bot laeuft gerade zum naechsten Cover (< 15 m) -> erreichbar?
	var covers: Array[Vector3] = []
	for c in get_tree().get_nodes_in_group("cover_point"):
		covers.append((c as Node3D).global_position)
	var bad := {}
	for i in range(1, wps.size()):
		var w0 := Vector3(wps[i - 1][0], 0.0, wps[i - 1][2])
		var w1 := Vector3(wps[i][0], 0.0, wps[i][2])
		var n := int(w0.distance_to(w1) / 1.5) + 1
		for k in n:
			for off: float in [-3.5, 0.0, 3.5]:
				var s := w0.lerp(w1, float(k) / n) + Vector3(off, 0, 0)
				var best := Vector3.ZERO
				var bd := 15.0
				for cv in covers:
					var d := Vector3(cv.x - s.x, 0, cv.z - s.z).length()
					if d < bd and d > 0.5:
						bd = d
						best = cv
				if bd >= 15.0:
					continue
				var y0 := 0.9 if absf(s.z) > 2.0 else 0.0
				var prm := PhysicsShapeQueryParameters3D.new()
				prm.shape = sh
				prm.transform = Transform3D(Basis.IDENTITY, Vector3(s.x, y0, s.z))
				prm.motion = Vector3(best.x, 0.9, best.z) - Vector3(s.x, y0, s.z)
				prm.collision_mask = 1
				var ok := space.intersect_shape(prm, 1).is_empty()
				var r := space.cast_motion(prm)
				if ok and r.size() > 0 and r[0] < 0.97 and (1.0 - r[0]) * prm.motion.length() > 1.0:
					bad[best] = str(s.snapped(Vector3.ONE))
	for b in bad:
		print("NAVTEST cover unreachable %s from %s" % [str(b), bad[b]])
	print("NAVTEST done")
