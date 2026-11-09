extends AnimatableBody3D
## Panzerung eines Fahrzeugs (Kollision, Layer world). Faengt Kugeltreffer ab: kein Schaden, keine Trefferanzeige
## (is_alive() = false), die Waffe zeigt Metall-Funken. Explosionsschaden laeuft ueber das Fahrzeug selbst
## (Gruppe damageable), nicht ueber diesen Collider.

func take_damage(_amount: float, _source: Node, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	pass

func is_alive() -> bool:
	return false
