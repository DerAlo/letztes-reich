extends AnimatableBody3D
## Seilbahnkabine der Mission "Weißes Rauschen" (alpenpass): Weber sitzt drin.
## Jeder Treffer (Kugel, Splitter) wird an das Level gemeldet – die Kabine selbst nimmt keinen Schaden.

var level_ref: Node = null

func take_damage(_amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	VFX.spawn_impact(hit_position, hit_normal, "metal")
	if level_ref != null and is_instance_valid(level_ref) and level_ref.has_method("on_cabin_hit"):
		level_ref.call("on_cabin_hit", source)
