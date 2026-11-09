extends StaticBody3D
## Test-Dummy: damageable + enemy, mit Kopf-Hitbox (Area3D, Meta headshot).

var health: float = 200.0
var hits: int = 0
var last_damage: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("damageable")

func take_damage(amount: float, _source: Node, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if health <= 0.0:
		return
	health -= amount
	hits += 1
	last_damage = amount
	if health <= 0.0:
		remove_from_group("enemy")
		Events.enemy_killed.emit(self)

func is_alive() -> bool:
	return health > 0.0
