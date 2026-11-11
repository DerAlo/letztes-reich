extends Grenade
## Blendgranate (Welle 4, Ausruestungswahl): kein Schaden. Greller Blitz + Knall; Gegner im Umkreis mit Sichtlinie
## brechen ab und zoegern einige Sekunden (Enemy.hesitate), werden aber alarmiert. Spieler nah dran: Kameraschuetteln.

const VF = preload("res://game/vehicles/vehicle_fx.gd")
const FLASH_RADIUS := 10.0
const STUN_TIME := 3.2


func _ready() -> void:
	super._ready()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.85, 0.95, 1.0)
	_lamp.material_override = m
	_blink.light_color = Color(0.85, 0.92, 1.0)


func _explode() -> void:
	_exploded = true
	var pos := global_position + Vector3(0, 0.15, 0)
	var parent := get_parent()
	if parent != null:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.97, 0.9)
		l.light_energy = 40.0
		l.omni_range = 14.0
		l.shadow_enabled = false
		parent.add_child(l)
		l.global_position = pos
		var tw := l.create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.5)
		tw.tween_callback(l.queue_free)
	VF.play_at(self, "explosion_2", pos, -6.0, 6.0, 80.0, 1.9)
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Node3D
		if e == null or not e.has_method("hesitate"):
			continue
		if e.has_method("is_alive") and not bool(e.call("is_alive")):
			continue
		var head := e.global_position + Vector3(0, 1.5, 0)
		var d := pos.distance_to(head)
		if d > FLASH_RADIUS:
			continue
		var q := PhysicsRayQueryParameters3D.create(pos, head, 1, [get_rid()])
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.get("collider") != e:
			continue
		if e.has_method("alert"):
			e.call("alert", pos, false)
		e.call("hesitate", STUN_TIME * clampf(1.4 - d / FLASH_RADIUS, 0.5, 1.0))
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p != null and p.has_method("add_trauma"):
		var pd := p.global_position.distance_to(pos)
		if pd < 6.0:
			p.call("add_trauma", lerpf(0.5, 0.15, pd / 6.0))
	queue_free()
