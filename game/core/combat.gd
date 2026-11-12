extends Node
## Kampf-Hilfsfunktionen. Besitzer: VFX/Level-Agent.

const WORLD_MASK := 1
const PUSH_SPEED := 13.0     ## m/s Impuls-Geschwindigkeit direkt an der Explosion

## true, solange explode() Schaden verteilt. Ziele, die nur auf Explosionen reagieren (z. B. Panzer),
## koennen damit Kugel- von Explosionsschaden unterscheiden. (Runde 3, abwaertskompatibel)
var explosion_active: bool = false

## Explosion: Schaden im Radius (Abfall linear), Sichtlinien-Check gegen die Welt,
## Physik-Impuls auf RigidBody3D, VFX und Events.explosion.
func explode(position: Vector3, radius: float = 6.0, damage: float = 120.0, source: Node = null, visual_scale: float = 1.0) -> void:
	VFX.spawn_explosion(position, visual_scale)
	var world := get_tree().root.world_3d
	if world != null:
		var space := world.direct_space_state
		var prev_active := explosion_active
		explosion_active = true
		_apply_damage(space, position, radius, damage, source)
		explosion_active = prev_active
		_apply_impulse(space, position, radius)
	Events.explosion.emit(position, radius, visual_scale)

## Optional am Ziel: get_damage_points() -> Array[Vector3] (eigene Trefferpunkte, z. B. Fahrzeuge)
## und get_collision_rids() -> Array[RID] (eigene Collider, die die Sichtlinie nicht blockieren sollen).
func _target_points(n: Node3D) -> Array[Vector3]:
	if n.has_method("get_damage_points"):
		var custom: Array[Vector3] = []
		for p: Variant in n.call("get_damage_points"):
			if p is Vector3:
				custom.append(p)
		if not custom.is_empty():
			return custom
	var base := n.global_position
	if n is CharacterBody3D:
		return [base + Vector3.UP * 0.9, base + Vector3.UP * 1.6, base + Vector3.UP * 0.3]
	return [base + Vector3.UP * 0.15, base + Vector3.UP * 0.6]

func _apply_damage(space: PhysicsDirectSpaceState3D, origin: Vector3, radius: float, damage: float, source: Node) -> void:
	if damage <= 0.0:
		return
	var victims: Array[Node] = get_tree().get_nodes_in_group("damageable").duplicate()
	for v in victims:
		if not is_instance_valid(v) or not (v is Node3D):
			continue
		var n3 := v as Node3D
		if not v.has_method("take_damage"):
			continue
		if v.has_method("is_alive") and not v.call("is_alive"):
			continue
		var pts := _target_points(n3)
		var best_dist := INF
		var best_pt := pts[0]
		for p in pts:
			var d := origin.distance_to(p)
			if d < best_dist:
				best_dist = d
				best_pt = p
		if best_dist > radius:
			continue
		# Sichtlinie: mindestens ein Zielpunkt frei (Welt, ohne das Ziel selbst)
		var excl: Array[RID] = []
		if v is CollisionObject3D:
			excl.append((v as CollisionObject3D).get_rid())
		if v.has_method("get_collision_rids"):
			for r: Variant in v.call("get_collision_rids"):
				if r is RID:
					excl.append(r)
		var visible_pt := false
		for p in pts:
			if origin.distance_to(p) > radius:
				continue
			var q := PhysicsRayQueryParameters3D.create(origin, p, WORLD_MASK, excl)
			if space.intersect_ray(q).is_empty():
				visible_pt = true
				best_pt = p
				break
		if not visible_pt:
			continue
		var falloff := clampf(1.0 - best_dist / radius, 0.0, 1.0)
		var dir := (best_pt - origin).normalized() if best_dist > 0.01 else Vector3.UP
		v.call("take_damage", damage * falloff, source, best_pt, -dir)

func _apply_impulse(space: PhysicsDirectSpaceState3D, origin: Vector3, radius: float) -> void:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, origin)
	params.collision_mask = 0xFFFFFFFF
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var seen: Dictionary = {}
	for hit in space.intersect_shape(params, 96):
		var body: Object = hit.get("collider")
		if body == null or seen.has(body) or not (body is RigidBody3D):
			continue
		seen[body] = true
		var rb := body as RigidBody3D
		if rb.freeze:
			continue
		var to := rb.global_position - origin
		var d := to.length()
		if d > radius:
			continue
		var falloff := 1.0 - d / radius
		var dir := (to / d) if d > 0.05 else Vector3.UP
		dir = (dir + Vector3.UP * 0.35).normalized()
		rb.apply_central_impulse(dir * PUSH_SPEED * falloff * rb.mass)
		rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * falloff * rb.mass * 1.5)
