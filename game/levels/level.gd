class_name Level
extends Node3D
## Testlevel "Kriegsstrasse im Daemmerlicht": ca. 200 m Strasse, drei Abschnitte, Set-Piece
## (Raketeneinschlag + Fassadeneinsturz) beim Betreten von Abschnitt 2.
## Alles wird zur Laufzeit gebaut (Geometrie, Marker, Navigation), damit die Datei klein bleibt.
## Schnittstelle laut CONTRACTS.md: get_level_info(), Gruppen player_spawn / enemy_spawn /
## cover_point / bot_waypoint, Events.checkpoint_reached, Events.level_completed.

const Geo = preload("res://game/levels/level_geo.gd")
const Buildings = preload("res://game/levels/level_buildings.gd")
const Props = preload("res://game/levels/level_props.gd")
const VfxEnv = preload("res://game/vfx/vfx_env.gd")
const PostFx = preload("res://game/vfx/post_fx.gd")
const StreetKit = preload("res://game/levels/street_kit.gd")

const PLAYER_PATH := "res://game/player/player.tscn"
const ENEMY_PATH := "res://game/enemies/%s.tscn"
const BARREL_PATH := "res://game/vfx/explosive_barrel.tscn"

signal wave_started(index: int)
signal setpiece_triggered

@export_group("Level")
@export var level_name: String = "test_range"
@export var spawn_player: bool = true
@export var spawn_enemies: bool = true
@export var build_seed: int = 1944
@export var end_z: float = -191.0
@export var default_faction: String = "ru"   ## Gegner-Optik: "ru" oder "reich" (Marker-Meta "faction" hat Vorrang)
@export_group("Umgebung")
@export var fog_density: float = 0.005
@export var sky_energy: float = 1.0
@export var ambient_artillery: bool = true
@export var artillery_interval_min: float = 7.0
@export var artillery_interval_max: float = 16.0
@export_group("Set-Piece")
@export var rocket_flight_time: float = 1.25
@export var rocket_start: Vector3 = Vector3(16.0, 26.0, -150.0)
@export var collapse_impulse: float = 6.0
@export var setpiece_shake: float = 0.55

var world: NavigationRegion3D
var player: Node3D = null
var covers: Array = []
var rng := RandomNumberGenerator.new()

var _waves_spawned: Dictionary = {}
var _wave_count: int = 3
var _blocks: Array[RigidBody3D] = []
var _setpiece_done: bool = false
var _setpiece_target: Vector3 = Vector3(-10.5, 8.0, -71.0)
var _end_done: bool = false
var _cp_done: Dictionary = {}
var _art_timer: Timer
var _ready_done: bool = false

func _ready() -> void:
	add_to_group("level")
	rng.seed = build_seed
	_setup_environment()
	world = NavigationRegion3D.new()
	world.name = "World"
	add_child(world)
	_build_ground()
	_build_street()
	_build_props()
	_build_markers()
	_build_set_piece_geometry()
	_build_skyline()
	_build_atmosphere()
	_bake_nav()
	# Navigation-Map braucht ein/zwei Physikframes, bevor Gegner Pfade finden.
	var map: RID = world.get_navigation_map()
	var waited := 0
	while waited < 120 and NavigationServer3D.map_get_iteration_id(map) == 0:
		await get_tree().physics_frame
		waited += 1
	_ready_done = true
	if spawn_player:
		_spawn_player()
	if spawn_enemies:
		_spawn_wave(0)
	if Game.arg("navdebug", false):
		print("LEVEL ready: player=%s enemies=%d covers=%d spawns=%d" % [str(player), get_tree().get_nodes_in_group("enemy").size(), get_tree().get_nodes_in_group("cover_point").size(), get_tree().get_nodes_in_group("enemy_spawn").size()])
	if ambient_artillery:
		_start_artillery()

# ------------------------------------------------------------------ Oeffentlich

func get_level_info() -> Dictionary:
	var wps: Array = []
	var nodes: Array = get_tree().get_nodes_in_group("bot_waypoint") if is_inside_tree() else []
	nodes.sort_custom(func(a: Node, b: Node) -> bool: return int(a.get_meta("order", 0)) < int(b.get_meta("order", 0)))
	for n in nodes:
		var p: Vector3 = (n as Node3D).global_position
		wps.append([p.x, p.y, p.z])
	var end_node := get_node_or_null("LevelEnd") as Node3D
	var ep: Vector3 = end_node.global_position if end_node != null else Vector3(0, 0, end_z)
	return {"name": level_name, "waves": _wave_count, "end_position": [ep.x, ep.y, ep.z], "waypoints": wps}

func is_level_ready() -> bool:
	return _ready_done

## Loest das Set-Piece manuell aus (auch fuer Tests/Kameratouren).
func trigger_setpiece() -> void:
	if _setpiece_done:
		return
	_setpiece_done = true
	setpiece_triggered.emit()
	_launch_rocket()

func spawn_wave(index: int) -> void:
	_spawn_wave(index)

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = VfxEnv.make_environment(fog_density, sky_energy)
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	add_child(VfxEnv.make_sun())
	VfxEnv.apply_render_quality(get_viewport())
	# Bildlook (ACES, dezente Auto-Exposure, Vignette/Korn); nur das Basis-Level nutzt diesen Pfad
	PostFx.apply(self, "day_war")

# ------------------------------------------------------------------ Boden

func _build_ground() -> void:
	var asphalt := Geo.mat("asphalt_02", Color(0.62, 0.62, 0.64), 0.2, 1.0)
	var walk := Geo.mat("concrete_wall_008", Color(0.55, 0.53, 0.5), 0.35, 1.0)
	var dirt := Geo.mat("concrete_wall_008", Color(0.3, 0.27, 0.24), 0.12, 1.0)
	# Kollision: ein grosser Block
	var g := Geo.static_body(Vector3(0, -1.0, -90.0))
	Geo.add_box_shape(g, Vector3.ZERO, Vector3(80.0, 2.0, 360.0))
	world.add_child(g)
	# Weiter Boden (nur Optik) bis zum Horizont, damit der Dunst ihn verschluckt
	var far := Geo.box_mesh_node(Vector3(900.0, 0.2, 800.0), dirt, Vector3(0, -0.12, -240.0))
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
	# Fahrbahn
	world.add_child(Geo.box_mesh_node(Vector3(14.0, 0.2, 225.0), asphalt, Vector3(0, -0.1, -90.0)))
	# Buergersteige mit Bordstein
	for sx in [-1.0, 1.0]:
		var w := Geo.static_body(Vector3(sx * 8.5, 0.07, -90.0))
		w.add_child(Geo.box_mesh_node(Vector3(3.0, 0.14, 225.0), walk, Vector3.ZERO))
		Geo.add_box_shape(w, Vector3.ZERO, Vector3(3.0, 0.14, 225.0))
		world.add_child(w)
	# Unsichtbare Aussenwaende (Gassen enden an Mauern, Strassenenden sind zu)
	for sx in [-1.0, 1.0]:
		_invisible_wall(Vector3(sx * 26.0, 6.0, -90.0), Vector3(1.0, 12.0, 260.0))
	_invisible_wall(Vector3(0, 6.0, 15.0), Vector3(60.0, 12.0, 1.0))
	_invisible_wall(Vector3(0, 6.0, end_z - 12.0), Vector3(60.0, 12.0, 1.0))

func _invisible_wall(pos: Vector3, size: Vector3) -> void:
	var b := Geo.static_body(pos)
	Geo.add_box_shape(b, Vector3.ZERO, size)
	world.add_child(b)

# ------------------------------------------------------------------ Haeuser

func _build_street() -> void:
	var tints: Array[Color] = [Color(0.85, 0.7, 0.62), Color(0.8, 0.76, 0.68), Color(0.7, 0.62, 0.58), Color(0.78, 0.66, 0.58), Color(0.66, 0.64, 0.6)]
	# [side, z_near, z_far, floors, brick, damage, depth]
	var specs: Array = [
		[-1, 14.0, -18.0, 4, true, 0.35, 10.0],
		[-1, -18.0, -40.0, 3, false, 0.6, 14.0],
		[-1, -46.0, -62.0, 4, true, 0.4, 14.0],
		[-1, -62.0, -80.0, 4, true, 0.2, 12.0],   # Einsturz-Haus (Felder 1..3)
		[-1, -80.0, -108.0, 3, false, 0.55, 10.0],
		[-1, -108.0, -136.0, 4, true, 0.4, 10.0],
		[-1, -136.0, -160.0, 3, true, 0.6, 10.0],
		[-1, -160.0, -186.0, 4, false, 0.5, 10.0],
		[1, 14.0, -10.0, 3, false, 0.4, 10.0],
		[1, -10.0, -36.0, 4, true, 0.35, 14.0],
		[1, -42.0, -58.0, 3, true, 0.7, 14.0],
		[1, -58.0, -84.0, 4, false, 0.4, 10.0],
		[1, -84.0, -106.0, 3, true, 0.6, 10.0],
		[1, -106.0, -128.0, 4, true, 0.35, 10.0],
		[1, -128.0, -150.0, 2, false, 0.85, 10.0],
		[1, -150.0, -186.0, 4, true, 0.45, 10.0],
	]
	var brs := RandomNumberGenerator.new()
	brs.seed = build_seed + 7
	for i in specs.size():
		var s: Array = specs[i]
		var opts := {"brick": s[4], "tint": tints[brs.randi() % tints.size()], "damage": s[5], "lit": 0.07}
		if i == 3:
			opts["collapse_bays"] = Vector2i(1, 3)
			opts["tint"] = Color(0.8, 0.68, 0.6)
		var info := Buildings.build(world, s[0], s[1], s[2], s[3], s[6], opts, brs)
		if i == 3:
			_collapse_info = info
			_collapse_opts = opts
		# Schutt auf dem Buergersteig vor beschaedigten Feldern
		var fl: Array = info["floors"]
		var zc: Array = info["zc"]
		for k in fl.size():
			if int(fl[k]) < int(s[3]) and brs.randf() < 0.75:
				Props.rubble(world, Vector3(float(s[0]) * 8.6, 0.0, float(zc[k])), brs.randf_range(1.4, 2.4), brs.randf_range(0.5, 0.9), brs, false)
	# Gassenenden
	for e in [[-1.0, -43.0], [1.0, -39.0]]:
		var sx: float = e[0]
		var z: float = e[1]
		Props.wall(world, Vector3(sx * 24.0, 0, z), 0.0, 6.0, 5.0, 1.0, rng)
		Props.rubble(world, Vector3(sx * 15.0, 0, z), 2.2, 1.1, rng, true, covers)
	# Strassenende: Tordurchgang mit orangem Licht, dahinter geschlossen
	_build_end_block()
	# Startende: ausgebrannter Bus quer
	Props.vehicle(world, Vector3(0, 0, 12.5), 90.0, "bus", Color(0.3, 0.32, 0.28), true, false, covers)

var _collapse_info: Dictionary = {}
var _collapse_opts: Dictionary = {}

func _build_end_block() -> void:
	var z0 := end_z + 4.0     # Vorderseite
	var brick := Buildings.wall_mat(true, Color(0.62, 0.55, 0.5))
	var mass := Buildings.mass_mat()
	var b := Geo.static_body()
	var bb := Geo.batch()
	var h := 15.0
	var depth := 14.0
	# links / rechts neben dem Tor (Tor 8 m breit)
	bb.add(Vector3(-15.0, h / 2.0, z0 - depth / 2.0), Vector3(22.0, h, depth))
	bb.add(Vector3(15.0, h * 0.4, z0 - depth / 2.0), Vector3(22.0, h * 0.8, depth))
	bb.add(Vector3(0, 10.5, z0 - depth / 2.0), Vector3(8.0, 9.0, depth))
	b.add_child(Geo.mesh_node(bb.build(), brick))
	Geo.add_box_shape(b, Vector3(-15.0, h / 2.0, z0 - depth / 2.0), Vector3(22.0, h, depth))
	Geo.add_box_shape(b, Vector3(15.0, h * 0.4, z0 - depth / 2.0), Vector3(22.0, h * 0.8, depth))
	Geo.add_box_shape(b, Vector3(0, 10.5, z0 - depth / 2.0), Vector3(8.0, 9.0, depth))
	# Rueckwand des Tunnels
	Geo.add_box_shape(b, Vector3(0, 3.0, z0 - depth - 0.5), Vector3(30.0, 6.0, 1.0))
	b.add_child(Geo.box_mesh_node(Vector3(8.0, 6.0, 0.4), mass, Vector3(0, 3.0, z0 - depth + 0.2)))
	# Fensterlöcher in der Frontseite
	var win := Geo.batch()
	for row in 3:
		for col in 5:
			for sx in [-1.0, 1.0]:
				var x: float = sx * (8.0 + col * 3.6)
				if absf(x) < 5.5 or (sx > 0 and row == 2):
					continue
				win.add(Vector3(x, 2.2 + row * 3.5, z0 + 0.03), Vector3(1.6, 2.0, 0.08))
	b.add_child(Geo.mesh_node(win.build(), Geo.flat(Color(0.02, 0.02, 0.02), 0.9)))
	world.add_child(b)
	# Licht im Tunnel
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.22)
	l.light_energy = 9.0
	l.omni_range = 22.0
	l.position = Vector3(0, 3.0, z0 - 7.0)
	add_child(l)
	Props.fire(world, Vector3(2.6, 0.0, z0 - 6.0), 0.7, false)
	Props.fire(world, Vector3(-2.6, 0.0, z0 - 9.0), 0.8, false)

# ------------------------------------------------------------------ Requisiten

func _barrel(x: float, z: float) -> void:
	if not ResourceLoader.exists(BARREL_PATH):
		return
	var scene: PackedScene = load(BARREL_PATH)
	var b: Node3D = scene.instantiate()
	b.position = Vector3(x, 0.47, z)
	b.rotation.y = rng.randf() * TAU
	add_child(b)

func _build_props() -> void:
	var grey := Color(0.4, 0.42, 0.43)
	var olive := Color(0.3, 0.34, 0.28)
	var sand := Color(0.55, 0.5, 0.4)
	var blue := Color(0.22, 0.3, 0.42)
	var red := Color(0.5, 0.18, 0.14)
	# --- Abschnitt 1 (Start bis z -55) ---
	var v1 := Props.vehicle(world, Vector3(5.5, 0, -8.0), 12.0, "car", grey, true, false, covers)
	Props.fire(world, v1.position + Vector3(0, 1.2, 0.3), 0.8, true, 1.4, 5.0)
	Props.vehicle(world, Vector3(-5.5, 0, -16.0), -8.0, "car", blue, false, false, covers, 2.0)
	Props.jersey(world, Vector3(-3.0, 0, -27.0), 90.0, covers)
	Props.jersey(world, Vector3(-0.2, 0, -27.5), 84.0, covers)
	Props.sandbags(world, Vector3(4.5, 0, -30.5), 90.0, 4.2, rng, covers)
	Props.vehicle(world, Vector3(-6.0, 0, -36.0), 30.0, "car", red, true, true, covers)
	for x in [2.0, 4.6, 7.0]:
		Props.hedgehog(world, Vector3(x, 0, -41.0 + rng.randf_range(-0.4, 0.4)), rng.randf() * 90.0, covers)
	Props.hedgehog(world, Vector3(-6.5, 0, -41.0), 20.0, covers)
	Props.rubble(world, Vector3(7.5, 0, -48.0), 2.2, 1.0, rng, true, covers)
	Props.rubble(world, Vector3(-6.5, 0, -53.0), 1.8, 0.7, rng, false)
	Props.crater(world, Vector3(0.5, 0, -18.0), 3.2, rng)
	Props.crater(world, Vector3(-3.0, 0, -47.0), 2.8, rng)
	Props.crater(world, Vector3(3.0, 0, -4.0), 2.2, rng)
	# --- Abschnitt 2 (z -55 bis -120) ---
	Props.vehicle(world, Vector3(5.2, 0, -62.0), 80.0, "car", sand, false, false, covers)
	var bus := Props.vehicle(world, Vector3(6.2, 0, -73.0), 6.0, "bus", Color(0.34, 0.36, 0.3), true, false, covers)
	Props.fire(world, bus.position + Vector3(0, 2.8, 2.0), 1.1, true, 1.8, 7.0)
	Props.jersey(world, Vector3(-2.5, 0, -86.0), 90.0, covers)
	Props.jersey(world, Vector3(0.0, 0, -86.5), 94.0, covers)
	var tank := Props.tank_wreck(world, Vector3(-2.0, 0, -98.0), 18.0, covers)
	Props.fire(world, tank.position + Vector3(0.8, 1.7, -2.4), 1.2, true, 2.0, 7.0)
	Props.sandbags(world, Vector3(5.2, 0, -92.0), 95.0, 5.0, rng, covers)
	Props.rubble(world, Vector3(-7.0, 0, -104.0), 3.0, 1.6, rng, true, covers)
	Props.rubble(world, Vector3(6.5, 0, -112.0), 2.5, 1.2, rng, true, covers)
	Props.vehicle(world, Vector3(-3.0, 0, -112.0), -30.0, "car", olive, true, false, covers)
	Props.crater(world, Vector3(2.0, 0, -96.0), 4.5, rng)
	Props.crater(world, Vector3(-4.0, 0, -114.0), 3.0, rng)
	Props.crater(world, Vector3(0.0, 0, -66.0), 3.4, rng)
	# --- Abschnitt 3 (z -120 bis Ende) ---
	var truck := Props.vehicle(world, Vector3(-4.2, 0, -124.0), 5.0, "truck", Color(0.3, 0.33, 0.27), true, false, covers)
	Props.fire(world, truck.position + Vector3(0.2, 3.0, 2.0), 1.0, true, 1.5, 6.0)
	Props.vehicle(world, Vector3(4.0, 0, -128.0), 100.0, "car", grey, false, false, covers, -3.0)
	for x in [-6.5, -3.6, 3.6, 6.5]:
		Props.jersey(world, Vector3(x, 0, -134.0 + rng.randf_range(-0.3, 0.3)), 90.0 + rng.randf_range(-8.0, 8.0), covers)
	Props.sandbags(world, Vector3(-5.0, 0, -142.0), 90.0, 5.0, rng, covers)
	Props.sandbags(world, Vector3(5.0, 0, -146.0), 90.0, 5.0, rng, covers)
	Props.vehicle(world, Vector3(0.5, 0, -151.0), 12.0, "van", Color(0.45, 0.45, 0.4), true, true, covers)
	Props.rubble(world, Vector3(-6.5, 0, -154.0), 3.0, 1.5, rng, true, covers)
	Props.rubble(world, Vector3(7.0, 0, -157.0), 2.6, 1.2, rng, true, covers)
	for x in [-5.5, -2.8, 3.0, 5.8]:
		Props.hedgehog(world, Vector3(x, 0, -165.0 + rng.randf_range(-0.5, 0.5)), rng.randf() * 90.0, covers)
	Props.vehicle(world, Vector3(-6.0, 0, -172.0), 80.0, "bus", Color(0.4, 0.3, 0.2), true, false, covers)
	Props.rubble(world, Vector3(6.5, 0, -175.0), 2.4, 1.0, rng, true, covers)
	Props.crater(world, Vector3(0.0, 0, -140.0), 3.6, rng)
	Props.crater(world, Vector3(2.0, 0, -168.0), 3.0, rng)
	# --- Strassenlampen (einige noch an) ---
	var lamp_zs := [-2.0, -22.0, -48.0, -76.0, -102.0, -128.0, -154.0, -178.0]
	for i in lamp_zs.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		var lit := i in [1, 4, 5, 7]
		Props.lamp(world, Vector3(side * 7.3, 0, lamp_zs[i]), 90.0 if side < 0 else -90.0, lit, rng.randf_range(-8.0, 8.0) if not lit else 0.0, lit)
	# --- Explosive Faesser (8) ---
	for p in [Vector2(6.8, -21.0), Vector2(7.4, -22.0), Vector2(-7.0, -33.0), Vector2(7.2, -45.0), Vector2(5.8, -68.0), Vector2(-6.0, -90.0), Vector2(6.8, -101.0), Vector2(-7.2, -131.0), Vector2(3.4, -160.0), Vector2(4.0, -161.0)]:
		_barrel(p.x, p.y)
	_build_street_detail()

## Bodendetail und Strassenmoeblierung (nur Optik, ohne Kollision; eigener RNG).
func _build_street_detail() -> void:
	for sx: float in [-1.0, 1.0]:
		StreetKit.curb(self, sx * 7.0, sx, 22.5, -202.5)
	StreetKit.lane_marks(self, 12.0, -190.0, 0.0, 6.6)
	StreetKit.dress_street(self, {"road": 7.0, "wall": 10.0, "y_walk": 0.14, "z0": 12.0, "z1": -186.0, "style": "war", "seed": build_seed + 501})
	var drng := RandomNumberGenerator.new()
	drng.seed = build_seed + 502
	var sb := Geo.BoxBatch.new()
	StreetKit.sign_post(sb, self, Vector3(-7.6, 0.14, -24.5), 90.0, "prio", 4.0)
	StreetKit.sign_post(sb, self, Vector3(7.6, 0.14, -58.0), -90.0, "stop", -9.0)
	StreetKit.sign_post(sb, self, Vector3(-7.6, 0.14, -118.0), 90.0, "blue")
	StreetKit.sign_post(sb, self, Vector3(7.6, 0.14, -148.0), -90.0, "noentry", 12.0)
	StreetKit.traffic_light(self, Vector3(-7.5, 0.14, -80.0), 90.0, "off")
	StreetKit.traffic_light(self, Vector3(7.5, 0.14, -138.0), -90.0, "amber_blink")
	var fb := Geo.BoxBatch.new()
	StreetKit.barrier_fence(fb, Vector3(-9.6, 0.14, -60.0), 0.0, 3, drng, 1)
	StreetKit.barrier_fence(fb, Vector3(9.6, 0.14, -118.0), 0.0, 4, drng, 2)
	StreetKit.barrier_fence(fb, Vector3(-9.6, 0.14, -162.0), 0.0, 2, drng)
	StreetKit.fences_node(self, fb)

# ------------------------------------------------------------------ Marker

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(0, 0.1, 5.0), "player_spawn")
	ps.name = "PlayerSpawn"
	# Gegner: [typ, welle, x, y, z]
	var spawns: Array = [
		["rifleman", 0, 3.4, 0.05, -33.5], ["rifleman", 0, -3.0, 0.05, -29.5],
		["rifleman", 0, -14.0, 0.05, -43.0], ["rifleman", 0, 6.0, 0.05, -50.0],
		["rifleman", 1, -4.0, 0.05, -102.0], ["rifleman", 1, 5.4, 0.05, -95.0],
		["rifleman", 1, 6.5, 0.05, -115.0], ["heavy", 1, 1.5, 0.05, -108.0],
		["drone", 1, 0.0, 6.0, -112.0],
		["rifleman", 2, -5.0, 0.05, -145.0], ["rifleman", 2, 5.0, 0.05, -149.0],
		["rifleman", 2, -2.0, 0.05, -166.0], ["heavy", 2, 0.5, 0.05, -158.0],
		["drone", 2, -5.0, 7.0, -150.0], ["drone", 2, 5.0, 8.0, -162.0],
	]
	for i in spawns.size():
		var s: Array = spawns[i]
		var mk := Geo.marker(m, Vector3(s[2], s[3], s[4]), "enemy_spawn")
		mk.name = "EnemySpawn%d_%s" % [i, s[0]]
		mk.set_meta("enemy_type", s[0])
		mk.set_meta("wave", s[1])
	for p in covers:
		var v: Vector3 = p
		if absf(v.x) > 9.0 and absf(v.x) < 12.0:
			continue
		Geo.marker(m, Vector3(clampf(v.x, -9.5, 9.5), 0.0, v.z), "cover_point")
	# Gassen-Deckung zaehlt auch
	# Bot-Route (Zickzack durch die freien Gassen zwischen den Requisiten)
	var route: Array = [Vector2(0, 4), Vector2(1, -10), Vector2(1.5, -20), Vector2(1.9, -25.5), Vector2(1.9, -29.5), Vector2(0.5, -31), Vector2(-1.5, -38),
		Vector2(-1, -50), Vector2(0.5, -58), Vector2(-1, -70), Vector2(1, -82), Vector2(1.5, -91),
		Vector2(3.5, -100), Vector2(2.5, -108), Vector2(0, -118), Vector2(0, -130), Vector2(0, -138),
		Vector2(0, -147), Vector2(0.5, -156), Vector2(0.3, -170), Vector2(0, -180)]
	for i in route.size():
		var r: Vector2 = route[i]
		var w := Geo.marker(m, Vector3(r.x, 0.05, r.y), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	# Wellen-Trigger
	_trigger("TriggerWave1", Vector3(0, 3, -62.0), Vector3(20, 6, 1.5), func() -> void: _spawn_wave(1))
	_trigger("TriggerWave2", Vector3(0, 3, -122.0), Vector3(20, 6, 1.5), func() -> void: _spawn_wave(2))
	# Set-Piece: Abschnitt 2
	_trigger("TriggerSection2", Vector3(0, 3, -50.0), Vector3(20, 6, 1.5), trigger_setpiece)
	# Checkpoints
	_trigger("Checkpoint1", Vector3(0, 3, -54.0), Vector3(20, 6, 1.5), func() -> void: _checkpoint("cp_section2"))
	_trigger("Checkpoint2", Vector3(0, 3, -118.0), Vector3(20, 6, 1.5), func() -> void: _checkpoint("cp_section3"))
	# Levelende im Tor
	var ez := end_z + 4.0 - 4.0
	var area := _trigger("LevelEnd", Vector3(0, 2.0, ez), Vector3(8, 4, 3), _on_level_end, false)
	area.add_to_group("level_end")

func _trigger(trig_name: String, pos: Vector3, size: Vector3, action: Callable, once: bool = true) -> Area3D:
	var a := Area3D.new()
	a.name = trig_name
	a.collision_layer = 0
	a.collision_mask = 2
	a.monitoring = true
	a.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	a.add_child(cs)
	add_child(a)
	var fired := [false]
	a.body_entered.connect(func(body: Node3D) -> void:
		if not body.is_in_group("player"):
			return
		if once and fired[0]:
			return
		fired[0] = true
		action.call())
	return a

func _checkpoint(id: String) -> void:
	if _cp_done.has(id):
		return
	_cp_done[id] = true
	Events.checkpoint_reached.emit(id)

func _on_level_end() -> void:
	if _end_done:
		return
	_end_done = true
	Events.level_completed.emit()

# ------------------------------------------------------------------ Spawns

func _spawn_player() -> void:
	if get_tree().get_first_node_in_group("player") != null:
		player = get_tree().get_first_node_in_group("player") as Node3D
		return
	if not ResourceLoader.exists(PLAYER_PATH):
		push_warning("Level: Player-Szene fehlt: " + PLAYER_PATH)
		return
	var scene := load(PLAYER_PATH) as PackedScene
	if scene == null:
		push_warning("Level: Player-Szene nicht ladbar")
		return
	var p := scene.instantiate() as Node3D
	var sp := get_tree().get_first_node_in_group("player_spawn") as Node3D
	add_child(p)
	if sp != null:
		p.global_position = sp.global_position
	if p.has_method("set_view"):
		p.call("set_view", 0.0, 0.0)
	player = p

func _spawn_wave(index: int) -> void:
	if _waves_spawned.has(index) or not spawn_enemies:
		return
	_waves_spawned[index] = true
	wave_started.emit(index)
	for mk in get_tree().get_nodes_in_group("enemy_spawn"):
		if not is_ancestor_of(mk):
			continue
		if int(mk.get_meta("wave", 0)) != index:
			continue
		var t: String = str(mk.get_meta("enemy_type", "rifleman"))
		var path := ENEMY_PATH % t
		if not ResourceLoader.exists(path):
			push_warning("Level: Gegner-Szene fehlt: " + path)
			continue
		var scene := load(path) as PackedScene
		if scene == null:
			push_warning("Level: Gegner-Szene nicht ladbar: " + path)
			continue
		var e := scene.instantiate() as Node3D
		# Fraktion (Optik): Marker-Meta "faction" schlaegt Level-Default; Enemy liest die Meta in _ready.
		e.set_meta("faction", str(mk.get_meta("faction", default_faction)))
		add_child(e)
		e.global_position = (mk as Node3D).global_position
		# Spieler schaut nach -Z, Gegner schauen ihm entgegen (+Z)
		e.rotation.y = 0.0

# ------------------------------------------------------------------ Set-Piece

func _build_set_piece_geometry() -> void:
	if _collapse_info.is_empty():
		return
	var wb: float = _collapse_info["wb"]
	var zcs: Array = _collapse_info["zc"]
	var floors: Array = _collapse_info["floors"]
	var brick: bool = _collapse_opts.get("brick", true)
	var tint: Color = _collapse_opts.get("tint", Color.WHITE)
	var crng := RandomNumberGenerator.new()
	crng.seed = build_seed + 99
	for bay in range(1, 4):
		for f in range(1, int(floors[bay])):
			var c := Vector3(-(Buildings.FRONT_X + Buildings.WALL_T / 2.0), f * Buildings.FLOOR_H + Buildings.FLOOR_H / 2.0, float(zcs[bay]))
			var rb := Buildings.make_block(-1, c, wb, brick, tint, crng)
			add_child(rb)
			_blocks.append(rb)
	# Einschlagspunkt: Mitte des mittleren Feldes, zweites Geschoss
	_setpiece_target = Vector3(-(Buildings.FRONT_X + 0.4), 1.5 * Buildings.FLOOR_H + 1.2, float(zcs[2]))

func _launch_rocket() -> void:
	var rocket := Node3D.new()
	rocket.name = "Rocket"
	var metal := Geo.flat(Color(0.18, 0.2, 0.17), 0.5, 0.6)
	var body := CylinderMesh.new()
	body.top_radius = 0.09
	body.bottom_radius = 0.09
	body.height = 1.6
	body.radial_segments = 8
	var mi := Geo.mesh_node(body, metal)
	mi.rotation_degrees.x = 90.0
	rocket.add_child(mi)
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.09
	nose.height = 0.4
	nose.radial_segments = 8
	var ni := Geo.mesh_node(nose, Geo.flat(Color(0.4, 0.15, 0.1), 0.5))
	ni.rotation_degrees.x = -90.0
	ni.position = Vector3(0, 0, -1.0)
	rocket.add_child(ni)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 14.0
	light.omni_range = 18.0
	light.position = Vector3(0, 0, 1.0)
	rocket.add_child(light)
	add_child(rocket)
	Props.fire(rocket, Vector3(0, 0, 1.0), 0.55, false, 0.4)
	var start := rocket_start
	var target := _setpiece_target
	rocket.global_position = start
	rocket.look_at(target, Vector3.UP)
	var tw := create_tween()
	tw.tween_property(rocket, "global_position", target, rocket_flight_time)
	tw.tween_callback(func() -> void:
		rocket.queue_free()
		_rocket_hit())

func _rocket_hit() -> void:
	var t := _setpiece_target
	Combat.explode(t, 10.0, 70.0, null, 2.6)
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("add_trauma"):
		var d := (pl as Node3D).global_position.distance_to(t)
		pl.call("add_trauma", clampf(setpiece_shake * (1.0 - d / 90.0), 0.15, 1.0))
	# Zweite, kleinere Detonation im Haus und Staubwolken entlang der Fassade
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		Combat.explode(t + Vector3(-2.0, -2.5, 2.5), 5.0, 0.0, null, 1.4))
	for i in 5:
		var zc := t.z + (i - 2) * 3.4
		get_tree().create_timer(0.1 + i * 0.22).timeout.connect(func() -> void:
			VFX.spawn_dust_cloud(Vector3(-9.0, 0.6 + (i % 2) * 5.0, zc), 5.5 + (i % 3)))
	# Bloecke loslassen (obere Geschosse etwas spaeter)
	for rb in _blocks:
		var delay := 0.03 + clampf(rb.global_position.distance_to(t) / 40.0, 0.0, 0.3) + rng.randf() * 0.12
		get_tree().create_timer(delay).timeout.connect(func() -> void: _release_block(rb, t))
	_spawn_chunks(t)
	# Das Haus brennt danach
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		Props.fire(self, Vector3(-11.5, t.y - 1.0, t.z), 1.5, true, 2.2, 9.0)
		Props.fire(self, Vector3(-11.5, 1.0, t.z + 5.0), 1.0, true, 1.5, 6.0))

func _release_block(rb: RigidBody3D, hit: Vector3) -> void:
	if not is_instance_valid(rb):
		return
	rb.freeze = false
	var away := rb.global_position - hit
	away.y = 0.0
	var dir := Vector3(1.0, 0.0, 0.0) * 0.9 + away.normalized() * 0.35 + Vector3.UP * 0.12
	rb.apply_central_impulse(dir.normalized() * rb.mass * collapse_impulse * rng.randf_range(0.6, 1.2))
	rb.apply_torque_impulse(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * rb.mass * 0.9)

func _spawn_chunks(t: Vector3) -> void:
	var mat := VFX.debris_material()
	for i in 22:
		var rb := RigidBody3D.new()
		rb.collision_layer = 8
		rb.collision_mask = 1
		var s := Vector3(rng.randf_range(0.25, 0.7), rng.randf_range(0.2, 0.5), rng.randf_range(0.25, 0.7))
		rb.mass = 14.0
		rb.add_child(Geo.box_mesh_node(s, mat, Vector3.ZERO))
		Geo.add_box_shape(rb, Vector3.ZERO, s)
		if not VFX.add_debris(rb):
			continue
		rb.global_position = t + Vector3(-1.0, rng.randf_range(-2.5, 3.0), rng.randf_range(-5.0, 5.0))
		rb.linear_velocity = Vector3(rng.randf_range(3.0, 11.0), rng.randf_range(1.0, 7.0), rng.randf_range(-4.0, 4.0))
		rb.angular_velocity = Vector3(rng.randf_range(-6, 6), rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		VFX.schedule_free(rb, rng.randf_range(18.0, 30.0))

# ------------------------------------------------------------------ Atmosphaere

func _build_atmosphere() -> void:
	# Rauchsaeulen hinter den Haeusern und Brandherde in den Ruinen
	var cols: Array = [Vector3(-48, 0, -35), Vector3(52, 0, -70), Vector3(-60, 0, -120), Vector3(45, 0, -150), Vector3(-40, 0, -190), Vector3(20, 0, -230)]
	for c in cols:
		Props.fire(self, c, 2.6, false, 3.5)
	# Brand in einzelnen Fensterhoehlen
	Props.fire(world, Vector3(11.5, 5.0, -44.0), 0.9, true, 1.2, 7.0)
	Props.fire(world, Vector3(-11.5, 4.5, -26.0), 0.9, true, 1.2, 7.0)
	Props.fire(world, Vector3(11.5, 8.5, -118.0), 1.0, true, 1.5, 7.0)
	# Bodennebel / Rauchschwaden in der Strasse
	for z in [-20.0, -60.0, -95.0, -135.0, -170.0]:
		Props.fog_volume(self, Vector3(0, 1.5, z), Vector3(30, 6, 36), 0.035, Color(0.55, 0.5, 0.46))

func _build_skyline() -> void:
	# Ferne Haeuserzeilen als Silhouetten (keine Kollision), dunstverhangen
	var srng := RandomNumberGenerator.new()
	srng.seed = build_seed + 31
	var bb := Geo.batch()
	for i in 46:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -srng.randf_range(-30.0, 330.0)
		var x := side * srng.randf_range(32.0, 110.0)
		var w := srng.randf_range(10.0, 26.0)
		var h := srng.randf_range(12.0, 46.0)
		bb.add(Vector3(x, h / 2.0, z), Vector3(w, h, srng.randf_range(10.0, 24.0)))
	# Querriegel am Strassenende
	for i in 8:
		bb.add(Vector3(srng.randf_range(-70.0, 70.0), 0, end_z - srng.randf_range(30.0, 160.0)) + Vector3(0, 12.0, 0), Vector3(srng.randf_range(12.0, 28.0), srng.randf_range(24.0, 60.0), 16.0))
	var mi := Geo.mesh_node(bb.build(), Geo.mat("concrete_wall_008", Color(0.28, 0.27, 0.27), 0.08, 1.0))
	add_child(mi)

# ------------------------------------------------------------------ Navigation

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1
	nm.filter_baking_aabb = AABB(Vector3(-27.0, -1.0, end_z - 12.0), Vector3(54.0, 15.0, 15.0 - end_z + 12.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

# ------------------------------------------------------------------ Ferner Artilleriebeschuss

func _start_artillery() -> void:
	_art_timer = Timer.new()
	_art_timer.one_shot = true
	_art_timer.timeout.connect(_on_artillery)
	add_child(_art_timer)
	_art_timer.start(rng.randf_range(artillery_interval_min, artillery_interval_max) * 0.6)

func _on_artillery() -> void:
	var pz := -40.0
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl != null:
		pz = pl.global_position.z
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var pos := Vector3(side * rng.randf_range(38.0, 120.0), 0.0, clampf(pz - rng.randf_range(30.0, 170.0), end_z - 60.0, 0.0))
	VFX.spawn_explosion(pos, rng.randf_range(2.6, 4.2))
	if pl != null and pl.has_method("add_trauma"):
		var d := pl.global_position.distance_to(pos)
		pl.call("add_trauma", clampf(0.18 - d / 900.0, 0.02, 0.18))
	_art_timer.start(rng.randf_range(artillery_interval_min, artillery_interval_max))
