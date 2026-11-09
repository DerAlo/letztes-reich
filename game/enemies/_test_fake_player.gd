extends CharacterBody3D
## Minimaler Fake-Player fuer Gegnertests: Gruppe player + damageable, Layer 2.
## Steht still oder laeuft im Kreis, loggt erhaltenen Schaden.

@export var mode: String = "still"  # still | circle
@export var circle_radius: float = 5.0
@export var circle_speed: float = 4.0
var crouching: bool = false
var total_damage: float = 0.0
var hit_count: int = 0
var damage_by_source: Dictionary = {}
var _center: Vector3
var _angle: float = 0.0
var _age: float = 0.0

func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	add_child(cs)
	_center = global_position

func take_damage(amount: float, source: Node, hit_position: Vector3, _hit_normal: Vector3) -> void:
	total_damage += amount
	hit_count += 1
	var key: String = source.name if source != null else "?"
	damage_by_source[key] = damage_by_source.get(key, 0.0) + amount
	print("[%6.2f] FAKEPLAYER hit %.1f from %s at (%.1f,%.1f,%.1f)  total=%.1f" % [_age, amount, key, hit_position.x, hit_position.y, hit_position.z, total_damage])

func is_alive() -> bool:
	return true

func _physics_process(delta: float) -> void:
	_age += delta
	if mode == "circle":
		_angle += circle_speed / circle_radius * delta
		var target := _center + Vector3(cos(_angle) - 1.0, 0.0, sin(_angle)) * circle_radius
		velocity = (target - global_position) / delta
		velocity.y = 0.0
	else:
		velocity = Vector3.ZERO
	velocity.y -= 9.8
	move_and_slide()
