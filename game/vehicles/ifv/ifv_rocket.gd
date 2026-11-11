extends Rocket
## Feindliche Panzerfaust gegen den Schuetzenpanzer (spreebogen). Trifft Welt und Spieler-Layer
## (Rocket selbst nie den Spieler). Volltreffer am Fahrzeug -> rocket_hit_ifv(), sonst nur Explosionseffekt
## (Combat.explode mit 0 Schaden, damit die Nester sich nicht selbst sprengen).

const ENEMY_MASK: int = 1 | 2
var ifv_damage: float = 11.0
var deflect: bool = false       ## im Nebel: verfehlt sicher (Level setzt leicht versetztes Ziel)

static func fire(parent: Node, from: Vector3, target: Vector3, speed: float, src: Node, dmg: float) -> Node3D:
	var r: Node3D = (load("res://game/vehicles/ifv/ifv_rocket.gd") as GDScript).new()
	r.name = "FeindRakete"
	r.set("velocity", (target - from).normalized() * speed)
	r.set("source", src)
	r.set("ifv_damage", dmg)
	r.add_to_group("spree_rocket")
	parent.add_child(r)
	r.global_position = from
	r.call("_orient")
	return r

func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_life += delta
	velocity.y -= 1.2 * delta
	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	var ex: Array[RID] = []
	if source != null and is_instance_valid(source) and source is CollisionObject3D:
		ex.append((source as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, to, ENEMY_MASK, ex)
	var res: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if not res.is_empty():
		_explode(res.position, res.collider as Object, res.normal)
		return
	global_position = to
	_orient()
	if _life > 5.0:
		_explode(global_position, null, Vector3.UP)

func _explode(pos: Vector3, collider: Object, normal: Vector3) -> void:
	_exploded = true
	var n := collider as Node
	var d := 0
	while n != null and d < 4:
		if n.has_method("rocket_hit_ifv"):
			n.call("rocket_hit_ifv", ifv_damage, pos, source)
			break
		n = n.get_parent()
		d += 1
	Combat.explode(pos + normal * 0.2, 3.0, 0.0, source, 1.1)
	if _trail:
		_trail.emitting = false
		var root: Node = get_parent()
		var gt: Transform3D = _trail.global_transform
		remove_child(_trail)
		root.add_child(_trail)
		_trail.global_transform = gt
		get_tree().create_timer(_trail.lifetime + 0.2, false).timeout.connect(_trail.queue_free)
	queue_free()
