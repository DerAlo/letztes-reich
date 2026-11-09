extends CharacterBody3D
## Fake-Gegner nur fuer Test-Infra. Besitzer: Test-Infra-Agent.

var type: String = "rifleman"
var health: float = 60.0
var dmg: float = 8.0
var _alive: bool = true
var _fire_cd: float = 1.0
var _seen_t: float = 0.0
var _state: String = "idle"


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("damageable")
	collision_layer = 4
	collision_mask = 1
	if has_meta("enemy_type"):
		type = str(get_meta("enemy_type"))
	if type == "heavy":
		health = 160.0
		dmg = 12.0
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.4
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	var mi: MeshInstance3D = MeshInstance3D.new()
	var cm: CapsuleMesh = CapsuleMesh.new()
	cm.height = 1.8
	cm.radius = 0.4
	mi.mesh = cm
	mi.position.y = 0.9
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.15, 0.1) if type == "rifleman" else Color(0.9, 0.5, 0.1)
	mi.material_override = mat
	add_child(mi)


func is_alive() -> bool:
	return _alive


func get_status() -> Dictionary:
	return {
		"type": type, "alive": _alive, "health": health, "state": _state,
		"position": [global_position.x, global_position.y, global_position.z],
	}


func take_damage(amount: float, _source: Node, _hp: Vector3, _hn: Vector3) -> void:
	if not _alive:
		return
	health -= amount
	Events.enemy_damaged.emit(self, amount)
	if health <= 0.0:
		_alive = false
		_state = "dead"
		remove_from_group("enemy")
		Events.enemy_killed.emit(self)
		await get_tree().create_timer(3.0).timeout
		queue_free()


func _physics_process(delta: float) -> void:
	if not _alive:
		return
	var p: Node3D = Game.get_player() as Node3D
	if p == null or not p.has_method("is_alive") or not p.is_alive():
		return
	var to: Vector3 = p.global_position - global_position
	var d: float = to.length()
	if d > 30.0:
		_state = "idle"
		return
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.4, 0), p.global_position + Vector3(0, 1.2, 0), 1)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		_state = "search"
		_seen_t = 0.0
		return
	_seen_t += delta
	_state = "attack"
	var flat: Vector3 = Vector3(to.x, 0.0, to.z).normalized()
	if d > 12.0:
		velocity = flat * 2.0
		velocity.y = -2.0
		move_and_slide()
	_fire_cd -= delta
	if _fire_cd <= 0.0 and _seen_t > 0.6:
		_fire_cd = 0.9
		var chance: float = clampf(0.5 - d / 80.0, 0.1, 0.5)
		if randf() < chance:
			p.take_damage(dmg, self, p.global_position, -flat)
