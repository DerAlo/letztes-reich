class_name EnemyHitbox
extends StaticBody3D
## Eigener Treffer-Collider (z.B. Kopf). Leitet Schaden an den Gegner weiter.
## Meta `headshot` = true markiert den Kopf-Hitbox. Nicht in Gruppe `damageable`,
## damit Flaechenschaden (Combat.explode) nicht doppelt zaehlt.

var enemy: Node = null
var is_head: bool = false

func take_damage(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if enemy != null and is_instance_valid(enemy) and enemy.has_method("take_hit_part"):
		enemy.call("take_hit_part", amount, source, hit_position, hit_normal, is_head)

func is_alive() -> bool:
	return enemy != null and is_instance_valid(enemy) and enemy.has_method("is_alive") and enemy.call("is_alive")

func get_enemy() -> Node:
	return enemy
