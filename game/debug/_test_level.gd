extends Node3D
## Mini-Testlevel fuer die Test-Infra (Korridor mit Fake-Gegnern). Besitzer: Test-Infra-Agent.
## Start: godot --path . -- --level=../debug/_test_level   (Arg --fake-player erzwingt den Fake-Player,
## --blocked baut eine Wand quer in den Weg fuer den Stuck-Test, --real-enemies nutzt game/enemies/*.tscn)

const FakePlayer: GDScript = preload("res://game/debug/_fake_player.gd")
const FakeEnemy: GDScript = preload("res://game/debug/_fake_enemy.gd")
const PLAYER_SCENE: String = "res://game/player/player.tscn"

var _wps: Array[Vector3] = [Vector3(0, 0.5, -10), Vector3(0, 0.5, -25), Vector3(0, 0.5, -40), Vector3(0, 0.5, -55), Vector3(0, 0.5, -70)]
var _end: Vector3 = Vector3(0, 0.5, -78)
var player: Node3D = null


func _ready() -> void:
	_build_world()
	_spawn_player()
	_spawn_enemies()


func get_level_info() -> Dictionary:
	var wp: Array = []
	for w in _wps:
		wp.append([w.x, w.y, w.z])
	return {"name": "test_level", "waves": 1, "end_position": [_end.x, _end.y, _end.z], "waypoints": wp}


func _box(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var b: StaticBody3D = StaticBody3D.new()
	b.collision_layer = 1
	b.position = pos
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	b.add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var bm: BoxMesh = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	b.add_child(mi)
	add_child(b)
	return b


func _build_world() -> void:
	_box(Vector3(0, -0.5, -40), Vector3(12, 1, 100), Color(0.35, 0.35, 0.38))
	_box(Vector3(-6.5, 2, -40), Vector3(1, 4, 100), Color(0.5, 0.45, 0.4))
	_box(Vector3(6.5, 2, -40), Vector3(1, 4, 100), Color(0.5, 0.45, 0.4))
	_box(Vector3(0, 2, 11), Vector3(14, 4, 1), Color(0.5, 0.45, 0.4))
	_box(Vector3(0, 2, -90.5), Vector3(14, 4, 1), Color(0.5, 0.45, 0.4))
	if Game.arg("blocked", false) != false:
		_box(Vector3(0, 2, -32), Vector3(12, 4, 0.5), Color(0.8, 0.2, 0.2))
	var covers: Array[Vector3] = [Vector3(-3, 0.6, -18), Vector3(3, 0.6, -34), Vector3(-3, 0.6, -50), Vector3(2.5, 0.6, -63)]
	for c in covers:
		_box(c, Vector3(2, 1.2, 0.6), Color(0.3, 0.5, 0.3))
		var m: Marker3D = Marker3D.new()
		m.position = c + Vector3(0, -0.6, 1.2)
		m.add_to_group("cover_point")
		add_child(m)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.65, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment = e
	add_child(env)
	var order: int = 0
	for w in _wps:
		var mk: Marker3D = Marker3D.new()
		mk.position = w
		mk.set_meta("order", order)
		mk.add_to_group("bot_waypoint")
		add_child(mk)
		order += 1
	var sp: Marker3D = Marker3D.new()
	sp.position = Vector3(0, 0.1, 0)
	sp.add_to_group("player_spawn")
	add_child(sp)
	_trigger(Vector3(0, 1, -30), "cp1")
	_trigger(Vector3(0, 1, -55), "cp2")
	var end_area: Area3D = _trigger(_end + Vector3(0, 0.5, 0), "")
	end_area.name = "LevelEnd"


func _trigger(pos: Vector3, id: String) -> Area3D:
	var a: Area3D = Area3D.new()
	a.position = pos
	a.collision_mask = 2
	var cs: CollisionShape3D = CollisionShape3D.new()
	var bs: BoxShape3D = BoxShape3D.new()
	bs.size = Vector3(12, 4, 4)
	cs.shape = bs
	a.add_child(cs)
	add_child(a)
	a.body_entered.connect(func(body: Node3D) -> void:
		if not body.is_in_group("player"):
			return
		if id == "":
			Events.level_completed.emit()
		else:
			Events.checkpoint_reached.emit(id)
			if "respawn_pos" in body:
				body.set("respawn_pos", pos + Vector3(0, -0.9, 0))
		a.set_deferred("monitoring", false))
	return a


func _spawn_player() -> void:
	var p: Node3D = null
	if Game.arg("fake-player", false) == false and ResourceLoader.exists(PLAYER_SCENE):
		p = (load(PLAYER_SCENE) as PackedScene).instantiate() as Node3D
	else:
		p = FakePlayer.new()
	add_child(p)
	p.global_position = Vector3(0, 0.1, 0)
	player = p


func _spawn_enemies() -> void:
	var defs: Array = [
		["rifleman", Vector3(-3, 0, -22)], ["rifleman", Vector3(3, 0, -24)],
		["rifleman", Vector3(-3, 0, -45)], ["heavy", Vector3(0, 0, -47)], ["rifleman", Vector3(3, 0, -45)],
		["rifleman", Vector3(-2, 0, -66)], ["heavy", Vector3(2, 0, -68)],
	]
	var real: bool = Game.arg("real-enemies", false) != false
	for d in defs:
		var path: String = "res://game/enemies/%s.tscn" % str(d[0])
		var e: Node3D = null
		if real and ResourceLoader.exists(path):
			e = (load(path) as PackedScene).instantiate() as Node3D
		else:
			e = FakeEnemy.new()
			e.set_meta("enemy_type", d[0])
		add_child(e)
		e.global_position = d[1]
