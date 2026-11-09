extends CharacterBody3D
## Fake-Player nur fuer Test-Infra (gleiche Schnittstelle wie CONTRACTS.md). Besitzer: Test-Infra-Agent.

var max_health: float = 100.0
var health: float = 100.0
var external_input: bool = false
var ext: Dictionary = {
	"move": Vector2.ZERO, "look": Vector2.ZERO,
	"fire": false, "aim": false, "sprint": false, "crouch": false,
	"jump": false, "reload": false, "grenade": false,
}
var ammo_mag: int = 30
var ammo_reserve: int = 240
var grenades: int = 3
var reloading: bool = false
var respawn_pos: Vector3 = Vector3.ZERO

var _cam: Camera3D
var _pivot: Node3D
var _pitch: float = 0.0
var _fire_cd: float = 0.0
var _reload_t: float = 0.0
var _since_damage: float = 10.0
var _dead_t: float = 0.0
var _alive: bool = true


func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	collision_layer = 2
	collision_mask = 1
	var cs: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.height = 1.8
	cap.radius = 0.35
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_pivot = Node3D.new()
	_pivot.position.y = 1.6
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.current = true
	_pivot.add_child(_cam)
	respawn_pos = global_position


func get_camera() -> Camera3D:
	return _cam


func add_trauma(_a: float) -> void:
	pass


func set_view(yaw_deg: float, pitch_deg: float) -> void:
	rotation_degrees.y = yaw_deg
	_pitch = clampf(pitch_deg, -89.0, 89.0)
	_pivot.rotation_degrees.x = _pitch


func look_at_point(p: Vector3) -> void:
	var d: Vector3 = p - _cam.global_position
	var yaw: float = rad_to_deg(atan2(-d.x, -d.z))
	var pitch: float = rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
	set_view(yaw, pitch)


func is_alive() -> bool:
	return _alive


func get_status() -> Dictionary:
	return {
		"alive": _alive, "health": snappedf(health, 0.1), "max_health": max_health,
		"position": [snappedf(global_position.x, 0.01), snappedf(global_position.y, 0.01), snappedf(global_position.z, 0.01)],
		"yaw": snappedf(rotation_degrees.y, 0.1), "pitch": snappedf(_pitch, 0.1),
		"weapon": "fake_rifle", "ammo_mag": ammo_mag, "ammo_reserve": ammo_reserve,
		"grenades": grenades, "reloading": reloading, "aiming": bool(ext["aim"]),
	}


func take_damage(amount: float, source: Node, _hp: Vector3, _hn: Vector3) -> void:
	if not _alive:
		return
	health -= amount
	_since_damage = 0.0
	Events.player_damaged.emit(amount, source)
	if health <= 0.0:
		_alive = false
		_dead_t = 2.0
		Events.player_died.emit()


func _physics_process(delta: float) -> void:
	if not _alive:
		_dead_t -= delta
		if _dead_t <= 0.0:
			_alive = true
			health = max_health
			global_position = respawn_pos
			velocity = Vector3.ZERO
			ammo_mag = 30
			Events.player_respawned.emit()
		return
	_since_damage += delta
	if _since_damage > 4.0 and health < max_health:
		health = minf(max_health, health + 25.0 * delta)
	var mv: Vector2 = ext["move"]
	var look: Vector2 = ext["look"]
	rotation.y -= deg_to_rad(look.x) * delta
	_pitch = clampf(_pitch + look.y * delta, -89.0, 89.0)
	_pivot.rotation_degrees.x = _pitch
	var speed: float = 6.0 if bool(ext["sprint"]) else 4.0
	if bool(ext["crouch"]):
		speed = 2.0
	var dir: Vector3 = (global_transform.basis.x * mv.x + (-global_transform.basis.z) * mv.y)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		velocity.y = 0.0
		if bool(ext["jump"]):
			velocity.y = 5.0
	else:
		velocity.y -= 20.0 * delta
	ext["jump"] = false
	move_and_slide()

	_fire_cd -= delta
	if reloading:
		_reload_t -= delta
		if _reload_t <= 0.0:
			reloading = false
			var need: int = 30 - ammo_mag
			var take: int = mini(need, ammo_reserve)
			ammo_mag += take
			ammo_reserve -= take
	elif bool(ext["reload"]) and ammo_mag < 30:
		reloading = true
		_reload_t = 1.6
	ext["reload"] = false
	if bool(ext["fire"]) and not reloading and ammo_mag > 0 and _fire_cd <= 0.0:
		_fire_cd = 0.1
		ammo_mag -= 1
		_shoot()
	if bool(ext["grenade"]):
		ext["grenade"] = false
		if grenades > 0:
			grenades -= 1
			var pos: Vector3 = _cam.global_position - _cam.global_transform.basis.z * 15.0
			pos.y = 0.2
			Combat.explode(pos, 5.0, 120.0, self)
			for e in get_tree().get_nodes_in_group("enemy"):
				var n3: Node3D = e as Node3D
				if n3 != null and n3.global_position.distance_to(pos) < 5.0:
					e.take_damage(120.0, self, pos, Vector3.UP)


func _shoot() -> void:
	Events.weapon_fired.emit(self)
	var from: Vector3 = _cam.global_position
	var to: Vector3 = from - _cam.global_transform.basis.z * 100.0
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1 | 4)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit["collider"]
	if col is Node and (col as Node).has_method("take_damage"):
		col.take_damage(20.0, self, hit["position"], hit["normal"])
