extends Node3D
## Test: Panzerfaust-Raketen gegen Panzer und Hubschrauber. Loggt Einschlag + HP.
## godot --headless --path . res://game/weapons/_test_rocket_vehicles.tscn

var tank: Node3D
var heli: Node3D

func _ready() -> void:
	var floor_b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(200, 1, 200)
	cs.shape = bx
	floor_b.add_child(cs)
	floor_b.position.y = -0.5
	add_child(floor_b)
	tank = (load("res://game/vehicles/tank.tscn") as PackedScene).instantiate()
	add_child(tank)
	tank.global_position = Vector3(0, 0, -40)
	tank.rotation.y = 0.6
	heli = (load("res://game/vehicles/helicopter.tscn") as PackedScene).instantiate()
	add_child(heli)
	heli.global_position = Vector3(30, 15, -50)
	if heli.has_method("hover_at"):
		heli.call("hover_at", Vector3(30, 15, -50))
	await get_tree().create_timer(1.0).timeout
	var arm: Node = tank.get_node_or_null("Armor")
	print("[rt] armor=", arm, " pos=", (arm as Node3D).global_position if arm else Vector3.ZERO, " layer=", arm.get("collision_layer") if arm else -1, " shapes=", arm.get_child_count() if arm else 0, " disabled=", arm.get("process_mode") if arm else -1)
	for c in arm.get_children():
		print("[rt]  shape ", c, " ", (c as Node3D).position, " dis=", c.get("disabled"))
	var q := PhysicsRayQueryParameters3D.create(Vector3(0, 1.6, 0), Vector3(0, 1.0, -60), 0xFFFFFFFF)
	print("[rt] ray all-mask: ", get_world_3d().direct_space_state.intersect_ray(q))
	var aims := [Vector3(0, 1.0, 0), Vector3(0, 2.1, 0), Vector3(1.4, 0.6, 2.5), Vector3(-1.5, 1.2, -2.0), Vector3(0, 0.4, 3.3)]
	for i in 4:
		var a: Vector3 = aims[i % aims.size()]
		await _fire_at(tank, tank.global_transform * a, "tank")
	for i in 4:
		await _fire_at(heli, heli.global_position + Vector3(0, 0, 0), "heli")
	get_tree().quit()

func _fire_at(target: Node3D, p: Vector3, label: String) -> void:
	var from := Vector3(0, 1.6, 0)
	var hp0: float = float(target.get("health"))
	var r: Node = Rocket.launch(self, from, (p - from).normalized(), 72.0, self)
	var last := from
	while is_instance_valid(r):
		last = (r as Node3D).global_position
		await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout
	print("[rt] %s aim=%s end=%s dist_to_aim=%.2f hp %.0f -> %.0f alive=%s" % [label, str(p), str(last), last.distance_to(p), hp0, float(target.get("health")), str(target.call("is_alive"))])
