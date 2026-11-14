extends RefCounted
## Grosse Truemmer (umgestuerzte Waggons, Fassadenbloecke, Hausteile, Panzertuerme) fliegen als RigidBody auf
## dem Debris-Layer (8): Spieler, Gegner und Kugeln gehen dort durch. Sobald so ein Teil liegt, macht
## solidify_when_settled() es zur festen Welt-Kollision (Layer 1, Box-Shapes in der Liegepose): man kann
## dahinter Deckung nehmen, Kugeln schlagen ein, man laeuft nicht mehr hindurch.
##
## Sicherheit: Liegt das Teil beim Umschalten in einem Spieler/Gegner (Layer 2/4), wird gewartet, bis der Platz
## frei ist (sonst Einklemmen). Teile, die unter die Welt gefallen sind, bleiben aus.
## Kosten: ein Timer je Teil alle 0.5 s bis zum Einfrieren, danach nichts mehr (statischer Body, eingefroren).

const LAYER_WORLD := 1
const ACTOR_MASK := 2 | 4      ## player + enemy
const STEP := 0.5

static func solidify_when_settled(rb: RigidBody3D, min_wait: float = 2.0, max_wait: float = 15.0, give_up: float = 60.0) -> void:
	if rb == null or not is_instance_valid(rb) or not rb.is_inside_tree():
		return
	var tree := rb.get_tree()
	var t := 0.0
	var calm := 0.0
	while true:
		await tree.create_timer(STEP, false).timeout
		if not is_instance_valid(rb) or not rb.is_inside_tree():
			return
		t += STEP
		var slow := rb.freeze or rb.sleeping or (rb.linear_velocity.length() < 0.3 and rb.angular_velocity.length() < 0.5)
		calm = calm + STEP if slow else 0.0
		if t < min_wait or (calm < 1.0 and t < max_wait):
			continue
		if rb.global_position.y < -4.0 or not rb.visible:
			return
		await tree.physics_frame
		if not is_instance_valid(rb) or not rb.is_inside_tree():
			return
		if _overlaps_actor(rb):
			if t > give_up:
				return
			continue
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.freeze = true
		rb.collision_layer |= LAYER_WORLD
		rb.set_meta("settled", true)
		return

static func _overlaps_actor(rb: RigidBody3D) -> bool:
	var space := rb.get_world_3d().direct_space_state
	for c in rb.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.disabled or cs.shape == null:
			continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = cs.shape
		q.transform = cs.global_transform
		q.collision_mask = ACTOR_MASK
		q.margin = 0.05
		q.exclude = [rb.get_rid()]
		if not space.intersect_shape(q, 1).is_empty():
			return true
	return false
