extends Node3D
## Testszene fuer Gegner: Boden, Waende, Cover-Points, zur Laufzeit gebackenes Navmesh,
## Fake-Player. Laeuft ~20 s Spielzeit, loggt State-Wechsel (Enemy.debug_log), Treffer, Tode.

const FakePlayer := preload("res://game/enemies/_test_fake_player.gd")

var fake: CharacterBody3D
var rifle: Enemy
var heavy: Enemy
var drone: Enemy
var drone2: Enemy
var t: float = 0.0
var step := 0
var killed: Array[String] = []
var dmg_events := 0
var navmesh_ok := false
var victim_r: Enemy
var victim_h: Enemy
var victim_done := false
var victims_spawned := false
var victim_checked := false
var victim_freed_checked := false

func _ready() -> void:
	set_physics_process(false)
	if Game.arg("shot", "") != "":
		_shot_mode()
		return
	Events.enemy_killed.connect(func(e: Node): killed.append(e.name); print("[%6.2f] EVENT enemy_killed %s" % [t, e.name]))
	Events.enemy_damaged.connect(func(e: Node, a: float): dmg_events += 1; print("[%6.2f] EVENT enemy_damaged %s %.1f" % [t, e.name, a]))
	Events.explosion.connect(func(p: Vector3, r: float, _s: float): print("[%6.2f] EVENT explosion at (%.1f,%.1f,%.1f) r=%.1f" % [t, p.x, p.y, p.z, r]))
	_build_world()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_spawn_all()
	set_physics_process(true)

func _box(parent: Node, pos: Vector3, size: Vector3, col: Color = Color(0.45, 0.45, 0.42)) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	mi.material_override = m
	sb.add_child(mi)
	parent.add_child(sb)
	return sb

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.6, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.7)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 14, 14)
	cam.rotation_degrees = Vector3(-35, 0, 0)
	add_child(cam)

	var region := NavigationRegion3D.new()
	add_child(region)
	_box(region, Vector3(0, -0.5, -15), Vector3(80, 1, 80), Color(0.3, 0.33, 0.28))
	_box(region, Vector3(0, 1.0, -12), Vector3(5, 2, 0.6))
	_box(region, Vector3(-9, 1.0, -15), Vector3(4, 2, 0.6))
	_box(region, Vector3(9, 1.0, -9), Vector3(4, 2, 0.6))
	_box(region, Vector3(3, 0.5, -16), Vector3(3, 1.0, 0.5))
	_box(region, Vector3(-4, 2.0, -6), Vector3(1, 4, 1))
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)
	navmesh_ok = nm.get_polygon_count() > 0
	print("NAVMESH polygons=%d vertices=%d" % [nm.get_polygon_count(), nm.get_vertices().size()])

	for p in [Vector3(0, 0, -13.2), Vector3(-9, 0, -16.2), Vector3(9, 0, -10.2), Vector3(3, 0, -17.0), Vector3(-4, 0, -7.4)]:
		var mk := Marker3D.new()
		mk.position = p
		mk.add_to_group("cover_point")
		add_child(mk)

func _spawn(path: String, pos: Vector3, yaw: float) -> Enemy:
	var en: Enemy = load(path).instantiate()
	en.debug_log = true
	add_child(en)
	en.global_position = pos
	en.rotation.y = yaw
	return en

func _spawn_all() -> void:
	fake = CharacterBody3D.new()
	fake.set_script(FakePlayer)
	fake.name = "FakePlayer"
	add_child(fake)
	fake.global_position = Vector3(0, 0.05, 0)
	rifle = _spawn("res://game/enemies/rifleman.tscn", Vector3(-5, 0.05, -28), PI)
	rifle.name = "Rifleman"
	rifle.cover_chance = 1.0
	heavy = _spawn("res://game/enemies/heavy.tscn", Vector3(7, 0.05, -30), 0.0)
	heavy.name = "Heavy"
	drone = _spawn("res://game/enemies/drone.tscn", Vector3(0, 4.0, -32), 0.0)
	drone.name = "Drone"
	print("SPAWNED all; navmesh_ok=%s" % navmesh_ok)

func _physics_process(delta: float) -> void:
	if fake == null:
		return
	t += delta
	if t >= 1.0 and not victims_spawned:
		victims_spawned = true
		victim_r = _spawn("res://game/enemies/rifleman.tscn", Vector3(25, 0.05, -35), 0.0)
		victim_r.name = "VictimRifle"
		victim_h = _spawn("res://game/enemies/heavy.tscn", Vector3(-25, 0.05, -35), 0.0)
		victim_h.name = "VictimHeavy"
		victim_h.tree_exited.connect(func(): print("[%6.2f] TEST VictimHeavy tree_exited" % t))
	if t >= 2.0 and not victim_done and victim_r != null:
		victim_done = true
		victim_r._head_hitbox.take_damage(30.0, fake, victim_r.global_position + Vector3.UP * 1.6, Vector3(0, 0, 1))
		print("[%6.2f] TEST victim rifle after headshot hp=%.0f" % [t, victim_r.health])
		victim_r._head_hitbox.take_damage(60.0, fake, victim_r.global_position + Vector3.UP * 1.6, Vector3(0, 0, 1))
		victim_h.take_damage(299.0, fake, victim_h.global_position + Vector3.UP, Vector3(0, 0, 1))
		victim_h.take_damage(5.0, fake, victim_h.global_position + Vector3.UP, Vector3(0, 0, 1))
		Events.explosion.emit(victim_h.global_position + Vector3(2, 0, 0), 6.0, 1.0)
		print("[%6.2f] TEST victim heavy ragdoll bodies=%d" % [t, _ragdoll_bodies(victim_h).size()])
	if t >= 2.6 and victim_h != null and is_instance_valid(victim_h) and not victim_checked:
		victim_checked = true
		for c in _ragdoll_bodies(victim_h):
			if true:
				print("   ragdoll part at (%.1f, %.1f, %.1f) v=%.1f" % [c.global_position.x, c.global_position.y, c.global_position.z, c.linear_velocity.length()])
	if t >= 12.0 and not victim_freed_checked:
		victim_freed_checked = true
		print("[%6.2f] TEST victims freed after cleanup: rifle=%s heavy=%s" % [t, str(not is_instance_valid(victim_r)), str(not is_instance_valid(victim_h))])
	if t >= 3.0 and step == 0:
		step = 1
		print("[%6.2f] TEST emit weapon_fired" % t)
		Events.weapon_fired.emit(fake)
	if t >= 10.0 and step == 1:
		step = 2
		fake.mode = "circle"
		print("[%6.2f] TEST fake player starts running in circle (damage so far %.1f in %d hits)" % [t, fake.total_damage, fake.hit_count])
	if t >= 13.0 and step == 2:
		step = 3
		print("[%6.2f] TEST damage before kill phase: %.1f (%d hits) %s" % [t, fake.total_damage, fake.hit_count, str(fake.damage_by_source)])
		drone2 = _spawn("res://game/enemies/drone.tscn", Vector3(3, 3.0, -20), 0.0)
		drone2.name = "Drone2"
	if t >= 14.5 and step == 3:
		step = 4
		if is_instance_valid(drone2):
			for i in 3:
				drone2.take_damage(15.0, fake, drone2.global_position, Vector3.UP)
	if t >= 15.0 and step == 4:
		step = 5
		if is_instance_valid(rifle) and rifle.is_alive():
			for i in 6:
				if rifle.is_alive():
					rifle.take_damage(20.0, fake, rifle.global_position + Vector3.UP, Vector3(0, 0, 1))
	if t >= 16.5 and step == 5:
		step = 6
		if is_instance_valid(heavy) and heavy.is_alive():
			heavy.take_damage(250.0, fake, heavy.global_position + Vector3.UP, Vector3(0, 0, 1))
			print("[%6.2f] TEST heavy health=%.0f, now explosion kill" % [t, heavy.health])
			heavy.take_damage(100.0, fake, heavy.global_position + Vector3.UP, Vector3(0, 0, 1))
			Events.explosion.emit(heavy.global_position + Vector3(0, -0.5, 2), 6.0, 1.0)
	if t >= 19.9 and step == 6:
		step = 7
		_report()
		get_tree().quit()

## Ragdoll-Koerper: PhysicalBone3D (Soldatenmodell) bzw. RigidBody3D (Primitiv-Fallback, Waffe).
func _ragdoll_bodies(en: Node) -> Array:
	var out: Array = []
	for c in en.find_children("*", "PhysicsBody3D", true, false):
		if c is PhysicalBone3D or c is RigidBody3D:
			out.append(c)
	return out

func _report() -> void:
	print("==== REPORT ====")
	print("Fake player total damage: %.1f in %d hits  by source: %s" % [fake.total_damage, fake.hit_count, str(fake.damage_by_source)])
	print("Killed: %s" % str(killed))
	print("enemy_damaged events: %d" % dmg_events)
	for en in [rifle, heavy, drone, drone2]:
		if is_instance_valid(en):
			print("status: %s shots=%d hits=%d" % [str(en.get_status()), en.stat_shots, en.stat_hits])
	print("enemies in group: %d" % get_tree().get_nodes_in_group("enemy").size())
	print("==== END ====")

## Optional: --shot=<png-pfad> (nicht headless) rendert die Gegner statisch von vorne.
func _shot_mode() -> void:
	_build_world()
	await get_tree().physics_frame
	var fp := CharacterBody3D.new()
	fp.set_script(FakePlayer)
	add_child(fp)
	fp.global_position = Vector3(0, 0.05, 6)
	var a := _spawn("res://game/enemies/rifleman.tscn", Vector3(-1.5, 0.05, -2), PI)
	var b := _spawn("res://game/enemies/heavy.tscn", Vector3(1.5, 0.05, -2), PI)
	var c := _spawn("res://game/enemies/drone.tscn", Vector3(0, 1.8, -1), 0.0)
	for e in [a, b, c]:
		e.debug_log = false
		e.set_physics_process(false)
	var cam := get_viewport().get_camera_3d()
	cam.global_position = Vector3(1.0, 1.7, 3.5)
	cam.look_at(Vector3(0, 1.0, -2))
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(str(Game.arg("shot", "")))
	print("screenshot saved")
	get_tree().quit()
